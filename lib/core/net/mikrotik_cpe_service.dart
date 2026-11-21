import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../api/mikrotik_api.dart' show MikrotikW60gLink, MikrotikWirelessClient;
import '../../api/mikrotik_binary_api.dart';
import '../../api/routeros_channel.dart';
import '../../models/device_health.dart';
import 'device_net.dart';
import 'router_types.dart';

/// طريق القراءة إلى RouterOS: الـAPI الثنائيّ (8728) · REST فوق https (7.1+) · REST فوق http (7.9+) · SSH.
enum MtRoute { api, restHttps, restHttp, ssh }

/// سبب فشل قراءة جهاز ميكروتك عند المشترك.
enum MtCpeIssue {
  /// الجهاز رفض اليوزر/الباسورد (لا يُعاد الزوج نفسه تلقائيّاً).
  rejected,

  /// عرّفناه ميكروتك (Winbox مفتوح) ولا طريق قراءةٍ مفتوح: الـAPI مقفول، ولا REST، وSSH غير متاح الآن.
  apiClosed,

  /// لا يردّ على أيّ طريق.
  unreachable,

  /// دخلنا ولم ترجع القراءات.
  readFailed,
}

/// جهاز المشترك من ميكروتك (١٦ نوفمبر — المالك: «اكو مشتركين عدهم نانوات نوع مايكروتك… لازم نضمنها ونضيفلها اعتمادات… وكذلك
/// راوترات مايكروتك»): نانو لاسلكيّ (SXT · LHG · LDF · DISC · Wireless Wire · LHG 60G) أو راوتر منزليّ (hAP · hEX · RB750…).
///
/// - **التعرّف بلا دخول ([detect]):** منفذ الـAPI (8728) أو Winbox (8291) مفتوح — منفذان لا يفتحهما غير RouterOS. اتّصال TCP يُغلق
///   فوراً، لا يُرسل شيء.
/// - **القراءة ([readOnce]):** قناة RouterOS نفسها التي تقرأ أجهزة قسم الأجهزة ([RouterOsChannel]) — الـAPI أوّلاً، ثمّ REST (https
///   ثمّ http)، ثمّ SSH مرّةً كلّ [sshEvery] على الأكثر لكلّ جهاز (قواعد «القوّة الغاشمة» الشائعة بميكروتك تحظر من يفتح SSH مراراً).
///   أوامر قراءةٍ وحدها (print · monitor once). ⛔ لا set/add/remove/reboot/reset، ولا `pppoe-client print` (فيها كلمة سرّ PPPoE)
///   — حالة PPPoE من `monitor` وحده. الاختبار يتأكّد.
/// - **الجلسات:** RouterOS يقبل جلسات API كثيرة معاً ولا يطرد أحداً — دخولنا لا يقطع WinBox الوكيل. الزوج المرفوض يُحفظ ولا يُعاد
///   تلقائيّاً حتى «حفظ وفحص الجهاز» ([forget]): قواعد الحظر تعدّ المحاولات الغلط.
/// - **النموذج:** [UbiquitiStatus] نفسه (البطاقة والقائمة والتنبيهات بلا تغيير): [vendorRadio] للنانو (وصلةٌ لاسلكيّة بوضع
///   station: الإشارة · CCQ · سرعة الربط · كيبل ether1)، و[vendorRouter] لراوتر المشترك (المتّصلون الآن · مدّة PPPoE · DHCP · سرعة منفذ
///   الإنترنت). النانو الذي يطلب PPPoE بنفسه يحمل مدّة الاتّصال أيضاً.
class MikrotikCpeService {
  MikrotikCpeService._();

  static const vendorRadio = 'mikrotik';
  static const vendorRouter = 'mtrouter';

  static bool isVendor(String? v) => v == vendorRadio || v == vendorRouter;

  // ── منافذ الاختبار ─────────────────────────────────────────────
  @visibleForTesting
  static int Function(String host) apiPortOf = (_) => 8728;
  @visibleForTesting
  static int Function(String host) winboxPortOf = (_) => 8291;
  @visibleForTesting
  static Duration detectTimeout = const Duration(milliseconds: 1500);

  /// صانع القناة لكلّ طريق — يُستبدل في الاختبار (REST/SSH وهميّان).
  @visibleForTesting
  static RouterOsChannel Function(String host, MtRoute route, String user, String pass)? channelFactory;

  /// أقلّ مدّةٍ بين محاولتَي SSH على جهازٍ لم يعمل SSH عليه قبلاً (اكتشاف الطريق).
  static const sshEvery = Duration(minutes: 10);

  /// أقلّ مدّةٍ بين جلستَي SSH على جهازٍ طريقُه المحفوظ SSH (الـAPI مقفول).
  static const sshRepeatEvery = Duration(minutes: 2);

  /// مدّة تذكّر الطريق الذي نجح.
  static const routeFor = Duration(minutes: 20);

  // ── الحال ─────────────────────────────────────────────────────
  static final _rejected = <String>{};
  static final _issue = <String, ({MtCpeIssue issue, String trace, DateTime at})>{};
  static final _route = <String, ({MtRoute r, DateTime at})>{};
  static final _sshTried = <String, DateTime>{};
  static final _serial = <String, Future<void>>{};

  /// آخر سببٍ لهذا العنوان (يكتبه [readOnce]).
  static ({MtCpeIssue issue, String trace})? lastIssue(String host) {
    final e = _issue[host];
    return e == null ? null : (issue: e.issue, trace: e.trace);
  }

  /// «حفظ وفحص الجهاز»: الرفض السابق يُنسى، والطريق يُكتشف من جديد.
  static void forget(String address) {
    final host = hostOf(address);
    _rejected.removeWhere((k) => k.startsWith('$host|'));
    _issue.remove(host);
    _issue.remove(address);
    _route.remove(host);
    _sshTried.remove(host);
  }

  /// كلّ ما يُحفظ لكلّ جهاز (الخروج من الحساب).
  static void clear() {
    _rejected.clear();
    _issue.clear();
    _route.clear();
    _sshTried.clear();
  }

  @visibleForTesting
  static void reset() {
    clear();
    _serial.clear();
    channelFactory = null;
    apiPortOf = (_) => 8728;
    winboxPortOf = (_) => 8291;
    detectTimeout = const Duration(milliseconds: 1500);
  }

  /// «IP:منفذ» (بورت فورورد لصفحة راوتر) ⇒ العنوان وحده: الـAPI وWinbox على منفذيهما المعروفين.
  static String hostOf(String address) {
    final a = address.trim();
    final m = RegExp(r'^(\d{1,3}(?:\.\d{1,3}){3}):\d{1,5}$').firstMatch(a);
    return m == null ? a : m.group(1)!;
  }

  /// RouterOS؟ — منفذ الـAPI أو Winbox يقبل الاتّصال (أوّل «نعم» يحسم). مباشرةً من الهاتف — وعبر ممرّ VPN لكرت مشتركٍ مفتوح
  /// بـ«وضع VPN» وحده ([DeviceNet.cpeZone]).
  static Future<bool> detect(String address) async {
    final host = hostOf(address);
    Future<bool> open(int port) async {
      try {
        final s = await DeviceNet.cpeConnect(host, port, timeout: detectTimeout);
        s.destroy();
        return true;
      } catch (_) {
        return false;
      }
    }

    final c = Completer<bool>();
    var left = 2;
    void done(bool yes) {
      if (c.isCompleted) return;
      if (yes) {
        c.complete(true);
      } else if (--left == 0) {
        c.complete(false);
      }
    }

    open(apiPortOf(host)).then(done);
    open(winboxPortOf(host)).then(done);
    return c.future;
  }

  static String _key(String host, String user, String pass) => '$host|$user|$pass';

  static void _note(String host, MtCpeIssue issue, String trace) =>
      _issue[host] = (issue: issue, trace: trace, at: DateTime.now());

  static RouterOsChannel _channel(String host, MtRoute r, String user, String pass) {
    final f = channelFactory;
    if (f != null) return f(host, r, user, pass);
    const t = Duration(seconds: 5);
    return switch (r) {
      MtRoute.api => BinaryRouterOsChannel(MikrotikBinaryClient(host: host, port: apiPortOf(host), user: user, pass: pass, timeout: t)),
      MtRoute.restHttps => RestRouterOsChannel(host: host, port: 443, https: true, user: user, pass: pass, timeout: t),
      MtRoute.restHttp => RestRouterOsChannel(host: host, port: 80, https: false, user: user, pass: pass, timeout: t),
      MtRoute.ssh => SshRouterOsChannel(host: host, port: 22, user: user, pass: pass, timeout: t),
    };
  }

  /// يفتح قناةً بأوّل طريقٍ يجيب. الرفض الصريح للاعتماد يرمي [_Rejected] (لا يُجرَّب طريقٌ آخر بالزوج نفسه — قاعدة المستخدمين
  /// واحدة). null ⇒ لا طريق.
  static Future<({RouterOsChannel ch, MtRoute route})?> _open(String host, String user, String pass) async {
    final now = DateTime.now();
    final known = _route[host];
    final first = known != null && now.difference(known.at) < routeFor ? known.r : null;
    final order = <MtRoute>[
      if (first != null) first,
      for (final r in MtRoute.values)
        if (r != first) r,
    ];
    for (final r in order) {
      if (r == MtRoute.ssh) {
        // اكتشافٌ (لم يعمل SSH قبلاً) مرّة كلّ [sshEvery]، وطريقٌ محفوظٌ بـSSH مرّة كلّ [sshRepeatEvery] — لا SSH جديد كلّ نبضة
        final last = _sshTried[host];
        final wait = first == MtRoute.ssh ? sshRepeatEvery : sshEvery;
        if (last != null && now.difference(last) < wait) continue;
        _sshTried[host] = now;
      }
      final ch = _channel(host, r, user, pass);
      try {
        await ch.open();
        _route[host] = (r: r, at: now);
        return (ch: ch, route: r);
      } on MikrotikBinaryException catch (e) {
        await _quietClose(ch);
        if (e.code == 'auth') throw _Rejected(r);
      } catch (_) {
        await _quietClose(ch);
      }
    }
    return null;
  }

  static Future<void> _quietClose(RouterOsChannel ch) async {
    try {
      await ch.close();
    } catch (_) {}
  }

  /// أمر قراءةٍ واحد — أمرٌ لا يعرفه الجهاز (حزمةٌ غير منصّبة، إصدارٌ أقدم) ⇒ لا صفوف، لا خطأ.
  static Future<List<Map<String, String>>> _q(RouterOsChannel ch, List<String> words) async {
    try {
      return await ch.query(words);
    } on MikrotikBinaryException catch (e) {
      final m = e.message.toLowerCase();
      if (m.contains('no such command') ||
          m.contains('no such item') ||
          m.contains('unknown parameter') ||
          m.contains('bad command') ||
          m.contains('not enough permissions')) {
        return const [];
      }
      rethrow;
    }
  }

  /// قراءةٌ واحدة: دخول ← أوامر قراءة ← إغلاق. null ⇒ السبب في [lastIssue] (بالعنوان كما أُعطي).
  static Future<UbiquitiStatus?> readOnce(String address, String user, String pass) async {
    final host = hostOf(address);
    final r = await _readSerial(host, user, pass);
    if (host != address) {
      final e = _issue[host];
      if (e != null) _issue[address] = e;
    }
    return r;
  }

  static Future<UbiquitiStatus?> _readSerial(String host, String user, String pass) {
    final prev = _serial[host] ?? Future<void>.value();
    final mine = Completer<void>();
    _serial[host] = mine.future;
    return prev.then((_) => DeviceNet.cpe(() => _read(host, user, pass))).whenComplete(() {
      mine.complete();
      if (identical(_serial[host], mine.future)) _serial.remove(host);
    });
  }

  static Future<UbiquitiStatus?> _read(String host, String user, String pass) async {
    if (_rejected.contains(_key(host, user, pass))) {
      _note(host, MtCpeIssue.rejected, 'remembered');
      return null;
    }
    ({RouterOsChannel ch, MtRoute route})? opened;
    try {
      opened = await _open(host, user, pass);
    } on _Rejected catch (e) {
      _rejected.add(_key(host, user, pass));
      _note(host, MtCpeIssue.rejected, 'auth ${e.route.name}');
      return null;
    }
    if (opened == null) {
      // تعرّفٌ إيجابيّ سبق (Winbox مفتوح) ولا طريق: الخدمات مقفولة — غير «لا يجاوب»
      final winbox = await _portOpen(host, winboxPortOf(host));
      _note(host, winbox ? MtCpeIssue.apiClosed : MtCpeIssue.unreachable, winbox ? 'no-route winbox-open' : 'no-route');
      return null;
    }
    final ch = opened.ch;
    try {
      final rows = await _collect(ch);
      final status = MikrotikCpeParse.status(host: host, rows: rows);
      _issue.remove(host);
      return status;
    } catch (e) {
      _note(host, MtCpeIssue.readFailed, 'read ${opened.route.name} ${e.runtimeType}');
      return null;
    } finally {
      await _quietClose(ch);
    }
  }

  static Future<bool> _portOpen(String host, int port) async {
    try {
      final s = await DeviceNet.cpeConnect(host, port, timeout: detectTimeout);
      s.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// الأوامر بالترتيب — كلّها قراءة. ما يعرفه الجهاز من حزمه (wireless · wifi · w60g) يُسأل وحده.
  static Future<MtCpeRows> _collect(RouterOsChannel ch) async {
    final resource = await _q(ch, ['/system/resource/print', '=.proplist=uptime,version,board-name,cpu-load']);
    final identity = await _q(ch, ['/system/identity/print']);
    final ifaces = await _q(ch, ['/interface/print', '=.proplist=name,type,running,disabled']);
    bool has(Set<String> types) => ifaces.any((r) => types.contains((r['type'] ?? '').toLowerCase()));

    var wireless = const <Map<String, String>>[];
    var wirelessReg = const <Map<String, String>>[];
    if (has({'wlan'})) {
      wireless = await _q(ch, ['/interface/wireless/print', '=.proplist=name,mode,ssid,frequency,band,running,disabled']);
      wirelessReg = await _q(ch, [
        '/interface/wireless/registration-table/print',
        '=.proplist=interface,mac-address,ap,signal-strength,tx-signal-strength,signal-to-noise,tx-ccq,rx-ccq,tx-rate,rx-rate,uptime,distance,last-ip,radio-name',
      ]);
    }
    var wifi = const <Map<String, String>>[];
    var wifiReg = const <Map<String, String>>[];
    if (has({'wifi', 'wifiwave2'})) {
      wifi = await _q(ch, ['/interface/wifi/print']);
      wifiReg = await _q(ch, ['/interface/wifi/registration-table/print']);
      if (wifi.isEmpty) {
        wifi = await _q(ch, ['/interface/wifiwave2/print']);
        wifiReg = await _q(ch, ['/interface/wifiwave2/registration-table/print']);
      }
    }
    final w60 = <MikrotikW60gLink>[];
    var w60Rows = const <Map<String, String>>[];
    if (has({'w60g'})) {
      w60Rows = await _q(ch, ['/interface/w60g/print', '=.proplist=name,mode,frequency,running,disabled']);
      for (final r in w60Rows) {
        final name = r['name'] ?? '';
        if (name.isEmpty || (r['disabled'] ?? '') == 'true') continue;
        final m = await _q(ch, ['/interface/w60g/monitor', '=numbers=$name', '=once=']);
        if (m.isNotEmpty) w60.add(MikrotikW60gLink.fromMonitor(name, m.first));
      }
    }
    // منفذ الكيبل: ether1 (المنفذ الوحيد في النانو، ومنفذ الإنترنت في الراوتر بإعداده الافتراضيّ)، وإلّا أوّل منفذ إيثر شغّال
    final ethers = [for (final r in ifaces) if ((r['type'] ?? '').toLowerCase() == 'ether') r];
    Map<String, String>? ether;
    for (final r in ethers) {
      if (r['name'] == 'ether1') ether = r;
    }
    ether ??= ethers.where((r) => r['running'] == 'true').firstOrNull ?? ethers.firstOrNull;
    Map<String, String>? etherMon;
    if (ether != null) {
      final m = await _q(ch, ['/interface/ethernet/monitor', '=numbers=${ether['name']}', '=once=']);
      if (m.isNotEmpty) etherMon = {'name': ether['name'] ?? '', ...m.first};
    }
    // PPPoE: الحال من monitor وحده (⛔ لا print — فيه كلمة سرّ PPPoE)
    final pppoe = [for (final r in ifaces) if ((r['type'] ?? '').toLowerCase() == 'pppoe-out' && r['disabled'] != 'true') r['name'] ?? ''];
    Map<String, String>? pppoeMon;
    if (pppoe.isNotEmpty && pppoe.first.isNotEmpty) {
      final m = await _q(ch, ['/interface/pppoe-client/monitor', '=numbers=${pppoe.first}', '=once=']);
      if (m.isNotEmpty) pppoeMon = m.first;
    }
    final rows = MtCpeRows(
      resource: resource.firstOrNull ?? const {},
      identity: identity.firstOrNull ?? const {},
      ifaces: ifaces,
      wireless: wireless,
      wirelessReg: wirelessReg,
      wifi: wifi,
      wifiReg: wifiReg,
      w60g: w60,
      w60gRows: w60Rows,
      ether: etherMon,
      pppoe: pppoeMon,
    );
    // راوتر المشترك (لا وصلة station): إيجارات DHCP وعميل DHCP على منفذ الإنترنت
    if (!MikrotikCpeParse.hasStationLink(rows)) {
      final leases = await _q(ch, ['/ip/dhcp-server/lease/print', '=.proplist=address,mac-address,host-name,status']);
      final dhcpClient = pppoeMon == null ? await _q(ch, ['/ip/dhcp-client/print', '=.proplist=interface,status']) : const <Map<String, String>>[];
      return rows.withRouter(leases: leases, dhcpClient: dhcpClient);
    }
    return rows;
  }

  /// جلسةٌ حيّة للبطاقة: قناةٌ تُفتح مرّةً، ثمّ `monitor-traffic` (معدّلٌ جاهز من الجهاز) كلّ نبضة، والإشارة/المتّصلون/مدّة PPPoE
  /// كلّ رابعة. null ⇒ لم تُفتح (رفضٌ أو لا طريق أو SSH — `monitor-traffic` لا يُترجَم سكربتاً).
  static Future<RouterLive?> openLive(String address, String user, String pass) => DeviceNet.cpe(() async {
        final host = hostOf(address);
        if (_rejected.contains(_key(host, user, pass))) return null;
        ({RouterOsChannel ch, MtRoute route})? o;
        try {
          o = await _open(host, user, pass);
        } on _Rejected {
          _rejected.add(_key(host, user, pass));
          return null;
        }
        if (o == null) return null;
        if (o.route == MtRoute.ssh) {
          await _quietClose(o.ch);
          return null;
        }
        try {
          final ifaces = await _q(o.ch, ['/interface/print', '=.proplist=name,type,running,disabled']);
          bool has(Set<String> t) => ifaces.any((r) => t.contains((r['type'] ?? '').toLowerCase()));
          final wl = has({'wlan'}) ? await _q(o.ch, ['/interface/wireless/print', '=.proplist=name,mode,running,disabled']) : const <Map<String, String>>[];
          var wifi = const <Map<String, String>>[];
          var wifiPkg = '';
          if (has({'wifi', 'wifiwave2'})) {
            wifi = await _q(o.ch, ['/interface/wifi/print']);
            wifiPkg = wifi.isEmpty ? '' : 'wifi';
            if (wifi.isEmpty) {
              wifi = await _q(o.ch, ['/interface/wifiwave2/print']);
              wifiPkg = wifi.isEmpty ? '' : 'wifiwave2';
            }
          }
          final target = MikrotikCpeParse.liveTarget(ifaces: ifaces, wireless: wl, wifi: wifi);
          if (target == null) {
            await _quietClose(o.ch);
            return null;
          }
          // جدول التسجيل الذي يُقرأ منه ما يحدّث البطاقة: حزمة الجهاز نفسها. بلا وايرلس (hEX) ⇒ لا عدّ «متّصلين» (لا «0» مخترع).
          final regCmds = <List<String>>[
            if (wl.isNotEmpty)
              ['/interface/wireless/registration-table/print', '=.proplist=interface,mac-address,signal-strength,tx-ccq,rx-ccq,last-ip'],
            if (wifiPkg.isNotEmpty) ['/interface/$wifiPkg/registration-table/print'],
          ];
          return MikrotikCpeLive._(o.ch, target.iface, target.pppoe, target.station, regCmds, w60: target.w60);
        } catch (_) {
          await _quietClose(o.ch);
          return null;
        }
      });
}

class _Rejected implements Exception {
  _Rejected(this.route);
  final MtRoute route;
}

/// ما رجع من الجهاز في قراءةٍ واحدة — صفوف الـAPI كما هي، يحلّلها [MikrotikCpeParse].
@immutable
class MtCpeRows {
  const MtCpeRows({
    this.resource = const {},
    this.identity = const {},
    this.ifaces = const [],
    this.wireless = const [],
    this.wirelessReg = const [],
    this.wifi = const [],
    this.wifiReg = const [],
    this.w60g = const [],
    this.w60gRows = const [],
    this.ether,
    this.pppoe,
    this.leases = const [],
    this.dhcpClient = const [],
  });

  final Map<String, String> resource;
  final Map<String, String> identity;
  final List<Map<String, String>> ifaces;
  final List<Map<String, String>> wireless;
  final List<Map<String, String>> wirelessReg;
  final List<Map<String, String>> wifi;
  final List<Map<String, String>> wifiReg;
  final List<MikrotikW60gLink> w60g;
  final List<Map<String, String>> w60gRows;
  final Map<String, String>? ether;
  final Map<String, String>? pppoe;
  final List<Map<String, String>> leases;
  final List<Map<String, String>> dhcpClient;

  MtCpeRows withRouter({required List<Map<String, String>> leases, required List<Map<String, String>> dhcpClient}) => MtCpeRows(
        resource: resource,
        identity: identity,
        ifaces: ifaces,
        wireless: wireless,
        wirelessReg: wirelessReg,
        wifi: wifi,
        wifiReg: wifiReg,
        w60g: w60g,
        w60gRows: w60gRows,
        ether: ether,
        pppoe: pppoe,
        leases: leases,
        dhcpClient: dhcpClient,
      );
}

/// التحليل الخالص: صفوف RouterOS ← [UbiquitiStatus].
class MikrotikCpeParse {
  MikrotikCpeParse._();

  static bool _isStationMode(String mode) {
    final m = mode.toLowerCase();
    return m.startsWith('station') || m == 'sta';
  }

  static bool _on(Map<String, String> r) => (r['disabled'] ?? '') != 'true';

  /// وضع واجهة wifi (RouterOS 7): `configuration.mode` مسطّحاً، أو `mode`.
  static String _wifiMode(Map<String, String> r) => r['configuration.mode'] ?? r['mode'] ?? '';
  static String _wifiSsid(Map<String, String> r) => r['configuration.ssid'] ?? r['ssid'] ?? '';

  /// وصلة 60 GHz بوضع station متّصلة؟
  static MikrotikW60gLink? _w60Station(MtCpeRows x) {
    for (final l in x.w60g) {
      if (!l.connected) continue;
      final row = x.w60gRows.where((r) => r['name'] == l.iface).firstOrNull;
      final mode = (row?['mode'] ?? '').toLowerCase();
      if (mode.startsWith('station') || mode.isEmpty) return l;
    }
    return null;
  }

  /// النانو: واجهةٌ لاسلكيّة بوضع station (wireless · wifi) أو وصلة 60 GHz station متّصلة.
  static bool hasStationLink(MtCpeRows x) =>
      _w60Station(x) != null ||
      x.wireless.any((r) => _on(r) && _isStationMode(r['mode'] ?? '')) ||
      x.wifi.any((r) => _on(r) && _isStationMode(_wifiMode(r)));

  static int _secs(String? raw) {
    if (raw == null || raw.isEmpty) return 0;
    var total = 0;
    final w = RegExp(r'(\d+)w').firstMatch(raw)?.group(1);
    final d = RegExp(r'(\d+)d').firstMatch(raw)?.group(1);
    final h = RegExp(r'(\d+)h').firstMatch(raw)?.group(1);
    final m = RegExp(r'(\d+)m(?!s)').firstMatch(raw)?.group(1);
    final s = RegExp(r'(\d+)s').firstMatch(raw)?.group(1);
    if (w != null) total += int.parse(w) * 604800;
    if (d != null) total += int.parse(d) * 86400;
    if (h != null) total += int.parse(h) * 3600;
    if (m != null) total += int.parse(m) * 60;
    if (s != null) total += int.parse(s);
    return total;
  }

  /// «100Mbps» · «1Gbps» · «2.5Gbps» ← ميغابت.
  static int? linkMbps(String? rate) {
    if (rate == null) return null;
    final m = RegExp(r'([\d.]+)\s*([GgMm])bps').firstMatch(rate);
    final v = m == null ? null : double.tryParse(m.group(1)!);
    if (v == null || v <= 0) return null;
    return (m!.group(2)!.toLowerCase() == 'g' ? v * 1000 : v).round();
  }

  /// منفذ الكيبل كما يقرؤه الجهاز (`ethernet monitor`): «100Mbps-Full» بصيغة [LanPort] — غير موصول ⇒ بلا سرعة.
  static LanPort? lanPort(Map<String, String>? mon) {
    if (mon == null) return null;
    final status = (mon['status'] ?? '').toLowerCase();
    final up = status.contains('link-ok') || status == 'link ok';
    final mbps = linkMbps(mon['rate']);
    final full = (mon['full-duplex'] ?? '') == 'true';
    return LanPort(
      name: mon['name'] ?? 'ether1',
      speed: up && mbps != null ? '${mbps}Mbps-${full ? 'Full' : 'Half'}' : null,
      plugged: up,
    );
  }

  /// «6.48.6 (long-term)» ← «RouterOS 6.48.6».
  static String firmware(String? version) {
    final v = (version ?? '').trim();
    if (v.isEmpty) return '';
    return 'RouterOS ${v.split(' ').first}';
  }

  static UbiquitiStatus status({required String host, required MtCpeRows rows}) {
    final x = rows;
    final up = _secs(x.resource['uptime']);
    final board = (x.resource['board-name'] ?? '').trim();
    final name = (x.identity['name'] ?? '').trim();
    final lan = lanPort(x.ether);
    final pppUp = x.pppoe != null && (x.pppoe!['status'] ?? '').toLowerCase().contains('connected');
    final wanSecs = pppUp ? _secs(x.pppoe!['uptime']) : null;
    final wanType = x.pppoe != null
        ? 'PPPoE'
        : (x.dhcpClient.any((r) => (r['status'] ?? '').toLowerCase() == 'bound') ? 'DHCP' : '');

    // ── النانو: الوصلة كما يراها هو (المحطّة) ──
    final w60 = _w60Station(x);
    if (w60 != null) {
      return UbiquitiStatus(
        hostname: name,
        firmware: firmware(x.resource['version']),
        uptimeSeconds: up > 0 ? up : null,
        ssid: '',
        mode: 'sta',
        signalDbm: w60.rssi,
        noiseFloorDbm: null,
        // الـ60 GHz لا CCQ له — جودة الإشارة ٪ شيءٌ آخر، فلا تُعرض باسمه
        ccqPercent: null,
        distanceMeters: w60.distanceMeters?.round(),
        txRateKbps: w60.phyRateMbps == null ? null : w60.phyRateMbps! * 1000,
        rxRateKbps: null,
        lanPorts: [if (lan != null) lan],
        peerMac: w60.remoteMac,
        peerCount: 1,
        baseUrl: 'http://$host',
        vendor: MikrotikCpeService.vendorRadio,
        model: board,
        wanOnlineSeconds: wanSecs,
        wanType: wanType,
      );
    }
    final staWl = x.wireless.where((r) => _on(r) && _isStationMode(r['mode'] ?? '')).toList()
      ..sort((a, b) => (b['running'] == 'true' ? 1 : 0) - (a['running'] == 'true' ? 1 : 0));
    final staWifi = x.wifi.where((r) => _on(r) && _isStationMode(_wifiMode(r))).toList();
    if (staWl.isNotEmpty || staWifi.isNotEmpty) {
      final legacy = staWl.isNotEmpty;
      final iface = legacy ? staWl.first : staWifi.first;
      final ifName = iface['name'] ?? '';
      final regs = legacy ? x.wirelessReg : x.wifiReg;
      final row = regs.where((r) => (r['interface'] ?? '') == ifName).firstOrNull ?? (regs.length == 1 ? regs.first : null);
      final c = row == null ? null : MikrotikWirelessClient.fromApiMap(row);
      final sig = c != null && c.signalStrength < 0 ? c.signalStrength : null;
      final snr = c != null && c.signalToNoise > 0 ? c.signalToNoise : null;
      final ccq = c == null ? null : (c.txCcq > 0 ? c.txCcq : (c.rxCcq > 0 ? c.rxCcq : null));
      final dist = MikrotikW60gLink.meters(row?['distance']);
      return UbiquitiStatus(
        hostname: name,
        firmware: firmware(x.resource['version']),
        uptimeSeconds: up > 0 ? up : null,
        ssid: legacy ? (iface['ssid'] ?? '') : _wifiSsid(iface),
        mode: 'sta',
        signalDbm: sig,
        noiseFloorDbm: sig != null && snr != null ? sig - snr : null,
        ccqPercent: ccq,
        distanceMeters: dist?.round(),
        txRateKbps: c == null || c.txRate <= 0 ? null : c.txRate * 1000,
        rxRateKbps: c == null || c.rxRate <= 0 ? null : c.rxRate * 1000,
        lanPorts: [if (lan != null) lan],
        peerMac: c == null || c.mac.isEmpty ? null : c.mac,
        peerCount: c == null ? 0 : 1,
        baseUrl: 'http://$host',
        vendor: MikrotikCpeService.vendorRadio,
        model: board,
        wanOnlineSeconds: wanSecs,
        wanType: wanType,
      );
    }

    // ── راوتر المشترك: المتّصلون الآن بالوايرلس (جدول التسجيل على واجهات الـAP)، والإيجارات للأسماء والعدّ ──
    final apIfaces = <String>{
      for (final r in x.wireless)
        if (_on(r) && !_isStationMode(r['mode'] ?? '')) r['name'] ?? '',
      for (final r in x.wifi)
        if (_on(r) && !_isStationMode(_wifiMode(r))) r['name'] ?? '',
    };
    final hasWifi = apIfaces.isNotEmpty;
    final leaseByMac = <String, Map<String, String>>{
      for (final l in x.leases)
        if ((l['mac-address'] ?? '').isNotEmpty) (l['mac-address'] ?? '').toUpperCase(): l,
    };
    final regRows = [
      for (final r in [...x.wirelessReg, ...x.wifiReg])
        if (apIfaces.contains(r['interface'] ?? '')) r,
    ];
    final seen = <String>{};
    final clients = <RouterClient>[];
    for (final r in regRows) {
      final mac = (r['mac-address'] ?? r['mac'] ?? '').toUpperCase();
      if (mac.isEmpty || !seen.add(mac)) continue;
      final l = leaseByMac[mac];
      final host = (l?['host-name'] ?? '').trim();
      clients.add(RouterClient(
        mac: mac,
        ip: (l?['address'] ?? r['last-ip'] ?? '').trim().isEmpty ? null : (l?['address'] ?? r['last-ip'])!.trim(),
        name: host.isEmpty ? null : host,
      ));
    }
    final bound = x.leases.where((l) => (l['status'] ?? '').toLowerCase() == 'bound').length;
    final wanMbps = lan != null && lan.plugged ? linkMbps(x.ether?['rate']) : null;
    return UbiquitiStatus(
      hostname: name,
      firmware: firmware(x.resource['version']),
      uptimeSeconds: up > 0 ? up : null,
      ssid: '',
      mode: hasWifi ? 'ap' : '',
      signalDbm: null,
      noiseFloorDbm: null,
      ccqPercent: null,
      distanceMeters: null,
      txRateKbps: null,
      rxRateKbps: null,
      lanPorts: const [],
      peerMac: null,
      // بلا وايرلس (hEX): لا «متّصلون الآن» نعرفهم — الإيجارات تبقى بعد خروج الجهاز فلا تُعدّ «الآن»
      peerCount: hasWifi ? clients.length : null,
      baseUrl: 'http://$host',
      vendor: MikrotikCpeService.vendorRouter,
      model: board,
      wanOnlineSeconds: wanSecs,
      dhcpCount: x.leases.isEmpty ? null : bound,
      wanType: wanType,
      clients: clients,
      wanLinkMbps: wanMbps,
    );
  }

  /// واجهة النبضة الحيّة: النانو ⇐ واجهته اللاسلكيّة بوضع station (ما يستقبله = التنزيل) — وصلة الـ60 أوّلاً إن وُجدت (لا
  /// الاحتياطيّ ٥)، والراوتر ⇐ PPPoE إن وُجد وإلّا ether1.
  static ({String iface, String? pppoe, bool station, bool w60})? liveTarget({
    required List<Map<String, String>> ifaces,
    required List<Map<String, String>> wireless,
    List<Map<String, String>> wifi = const [],
  }) {
    String? firstOf(Set<String> types) {
      for (final r in ifaces) {
        if (types.contains((r['type'] ?? '').toLowerCase()) && _on(r)) return r['name'];
      }
      return null;
    }

    final pppoe = firstOf({'pppoe-out'});
    final w60 = firstOf({'w60g'});
    if (w60 != null) return (iface: w60, pppoe: pppoe, station: true, w60: true);
    for (final r in wireless) {
      if (_on(r) && _isStationMode(r['mode'] ?? '')) return (iface: r['name'] ?? 'wlan1', pppoe: pppoe, station: true, w60: false);
    }
    for (final r in wifi) {
      if (_on(r) && _isStationMode(_wifiMode(r))) return (iface: r['name'] ?? 'wifi1', pppoe: pppoe, station: true, w60: false);
    }
    if (pppoe != null) return (iface: pppoe, pppoe: pppoe, station: false, w60: false);
    final eth = ifaces.where((r) => r['name'] == 'ether1').firstOrNull?['name'] ?? firstOf({'ether'});
    return eth == null ? null : (iface: eth, pppoe: null, station: false, w60: false);
  }
}

/// النبضة الحيّة لجهاز ميكروتك (نانو أو راوتر) — [RouterLive] نفسه الذي تستعمله البطاقة لراوترات MER.
class MikrotikCpeLive implements RouterLive {
  MikrotikCpeLive._(this._ch, this._iface, this._pppoe, this._station, this._regCmds, {bool w60 = false}) : _w60 = w60;

  final RouterOsChannel _ch;
  final String _iface;
  final String? _pppoe;
  final bool _station;
  final bool _w60;

  /// أوامر جدول التسجيل بحزمة الجهاز (wireless · wifi) — فارغة بلا وايرلس.
  final List<List<String>> _regCmds;
  bool _lost = false;
  int _n = 0;

  @override
  bool get lost => _lost;

  @override
  Future<RouterSample?> sample() async {
    if (_lost) return null;
    try {
      final t = await MikrotikCpeService._q(_ch, ['/interface/monitor-traffic', '=interface=$_iface', '=once=']);
      final r = t.isEmpty ? const <String, String>{} : t.first;
      final rx = int.tryParse(r['rx-bits-per-second'] ?? '');
      final tx = int.tryParse(r['tx-bits-per-second'] ?? '');
      int? wan;
      int? sig;
      int? ccq;
      List<RouterClient>? clients;
      if (_n++ % 4 == 0) {
        if (_pppoe != null) {
          final m = await MikrotikCpeService._q(_ch, ['/interface/pppoe-client/monitor', '=numbers=$_pppoe', '=once=']);
          final row = m.firstOrNull;
          if (row != null && (row['status'] ?? '').toLowerCase().contains('connected')) {
            wan = MikrotikCpeParse._secs(row['uptime']);
          }
        }
        if (_w60) {
          final m = await MikrotikCpeService._q(_ch, ['/interface/w60g/monitor', '=numbers=$_iface', '=once=']);
          if (m.isNotEmpty) sig = MikrotikW60gLink.fromMonitor(_iface, m.first).rssi;
        } else if (_regCmds.isNotEmpty) {
          final reg = <Map<String, String>>[
            for (final cmd in _regCmds) ...await MikrotikCpeService._q(_ch, cmd),
          ];
          if (_station) {
            final row = reg.where((x) => (x['interface'] ?? '') == _iface).firstOrNull;
            if (row != null) {
              final c = MikrotikWirelessClient.fromApiMap(row);
              sig = c.signalStrength < 0 ? c.signalStrength : null;
              ccq = c.txCcq > 0 ? c.txCcq : (c.rxCcq > 0 ? c.rxCcq : null);
            }
          } else {
            final seen = <String>{};
            clients = [
              for (final x in reg)
                if ((x['mac-address'] ?? x['mac'] ?? '').isNotEmpty && seen.add((x['mac-address'] ?? x['mac'] ?? '').toUpperCase()))
                  RouterClient(
                    mac: (x['mac-address'] ?? x['mac'] ?? '').toUpperCase(),
                    ip: (x['last-ip'] ?? '').isEmpty ? null : x['last-ip'],
                  ),
            ];
          }
        }
      }
      return RouterSample(
        downBps: rx,
        upBps: tx,
        wanOnlineSeconds: wan,
        clients: _station ? null : clients,
        signalDbm: sig,
        ccq: ccq,
        at: DateTime.now(),
      );
    } catch (_) {
      _lost = true;
      return null;
    }
  }

  @override
  Future<void> close() => MikrotikCpeService._quietClose(_ch);
}
