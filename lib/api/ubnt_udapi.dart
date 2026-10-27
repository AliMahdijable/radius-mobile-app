import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';

import 'ubnt_api.dart';

/// أجهزة Ubiquiti من الجيل الحديث (UISP «gen3»: Wave Pro · Wave AP · Wave Long-Range · Wave Nano · LTU…) —
/// بلاغ المالك ٢٧ أكتوبر: «ال wave برو نقص هواي كلش معلومات: التردّدات والنقل والاسم والنوع».
///
/// السبب كما فُحص على Wave Long-Range حقيقيّ (firmware 4.1.1، حساب popq التجريبيّ): نظامه Linux 5.4 بلا أيّ
/// أداةٍ من أدوات airOS (`mca-status` · `mca-dump` · `wstalist` · `af`)، فقارئ SSH لا يجد شيئاً. وبياناته كلّها في
/// خدمة udapi التي تكشفها واجهة الويب نفسها `/api/v1.0` (نفس عائلة EdgeSwitch):
///   POST /api/v1.0/user/login     → رأس `x-auth-token`
///   GET  /api/v1.0/device         → identification (product · model · family · firmwareVersion)
///   GET  /api/v1.0/system         → hostname
///   GET  /api/v1.0/statistics     → [ {device, interfaces, wireless{radios, peers, linkQuality}} ]
///   GET  /api/v1.0/interfaces     → سرعة منفذ الإيثرنت ووصله
///
/// كلّه قراءة — لا كتابة إعدادات. التوكن في الذاكرة وحدها، والجلسة تُغلق بعد كلّ قراءة (الجهاز يحدّ الجلسات).
class UbntUdapi {
  UbntUdapi._();

  static const int defaultPort = 443;

  /// الاختبارات: ردودٌ جاهزة بدل جهاز.
  @visibleForTesting
  static Future<UbntStats> Function()? debugFetch;

  static Dio _dio(String host, int port) {
    // المنفذ الافتراضيّ يُحذف من الأصل: أجهزة udapi تقارن `Referer` بأصلها نصّيّاً (انظر EdgeSwitchApi).
    final base = port == 443 ? 'https://$host' : 'https://$host:$port';
    final dio = Dio(BaseOptions(
      baseUrl: base,
      connectTimeout: const Duration(seconds: 6),
      receiveTimeout: const Duration(seconds: 12),
      validateStatus: (_) => true,
      headers: {'Accept': 'application/json, text/plain, */*', 'Referer': '$base/'},
    ));
    (dio.httpClientAdapter as IOHttpClientAdapter).createHttpClient = () {
      final c = HttpClient();
      // شهادة الجهاز موقَّعةٌ ذاتيّاً كحال معدّات الشبكة المحلّيّة.
      c.badCertificateCallback = (_, __, ___) => true;
      return c;
    };
    return dio;
  }

  /// هل ملفّ `/etc/board.json` (من جلسة SSH) لجهاز udapi؟ يُرجع اسم المنتج أو `null`.
  static String? productFromBoardJson(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final j = json.decode(raw);
      if (j is! Map) return null;
      final id = j['identification'];
      if (id is! Map) return null;
      final family = (id['family'] ?? '').toString().toLowerCase();
      if (family.isEmpty) return null;
      final product = (id['product'] ?? id['model'] ?? '').toString().trim();
      return product.isEmpty ? family : product;
    } catch (_) {
      return null;
    }
  }

  static Future<String?> _login(Dio d, String user, String pass) async {
    final r = await d.post<dynamic>(
      '/api/v1.0/user/login',
      data: {'username': user, 'password': pass},
      options: Options(contentType: Headers.jsonContentType),
    );
    if (r.statusCode != 200) return null;
    final tok = r.headers.value('x-auth-token');
    return (tok == null || tok.isEmpty) ? null : tok;
  }

  /// لقطةٌ كاملة بنموذج [UbntStats] نفسه، فتعرضها لوحات يوبيكويتي كما هي (والـ60 GHz تفتح لوحة airFiber 60).
  static Future<UbntStats> fetch({
    required String host,
    required String user,
    required String pass,
    int port = defaultPort,
  }) async {
    final fake = debugFetch;
    if (fake != null) return fake();
    final d = _dio(host, port);
    String? token;
    try {
      for (final u in {user.trim(), 'ubnt'}) {
        if (u.isEmpty) continue;
        token = await _login(d, u, pass);
        if (token != null) break;
      }
      if (token == null) {
        throw UbntException('اسم المستخدم أو كلمة المرور خطأ (واجهة الجهاز)');
      }
      final auth = Options(headers: {'x-auth-token': token});
      final res = await Future.wait([
        d.get<dynamic>('/api/v1.0/device', options: auth),
        d.get<dynamic>('/api/v1.0/system', options: auth),
        d.get<dynamic>('/api/v1.0/statistics', options: auth),
        d.get<dynamic>('/api/v1.0/interfaces', options: auth),
      ]);
      if (res[2].statusCode != 200) {
        throw UbntException('الجهاز لم يُرجع إحصاءاته (${res[2].statusCode})');
      }
      return parse(
        device: res[0].statusCode == 200 ? res[0].data : null,
        system: res[1].statusCode == 200 ? res[1].data : null,
        statistics: res[2].data,
        interfaces: res[3].statusCode == 200 ? res[3].data : null,
      );
    } on UbntException {
      rethrow;
    } on DioException catch (e) {
      throw UbntException(e.type == DioExceptionType.connectionError || e.type == DioExceptionType.connectionTimeout
          ? 'الجهاز غير قابل للوصول عبر HTTPS — تحقّق من الشبكة'
          : 'تعذّر قراءة واجهة الجهاز');
    } catch (e) {
      throw UbntException('تعذّر قراءة واجهة الجهاز: $e');
    } finally {
      if (token != null) {
        try {
          await d.post<dynamic>('/api/v1.0/user/logout', options: Options(headers: {'x-auth-token': token}));
        } catch (_) {/* أفضل جهد */}
      }
      d.close(force: true);
    }
  }

  static Map<String, dynamic> _map(Object? v) => v is Map ? v.cast<String, dynamic>() : const {};
  static List<dynamic> _list(Object? v) => v is List ? v : const [];

  static int? _int(Object? v) {
    if (v is int) return v;
    if (v is num) return v.round();
    if (v is String) return int.tryParse(v.trim()) ?? double.tryParse(v.trim())?.round();
    return null;
  }

  static double? _dbl(Object? v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v.trim());
    return null;
  }

  /// «1000-full» ⇒ 1000.
  static int? _speedOf(Object? v) {
    final m = RegExp(r'(\d+)').firstMatch((v ?? '').toString());
    return m == null ? null : int.tryParse(m.group(1)!);
  }

  static String _mbps(int? kbps) => kbps == null ? '—' : '${(kbps / 1000).round()}';

  /// يحوّل ردود الواجهة إلى [UbntStats]. دالّةٌ نقيّة تُختبر بردودٍ حقيقيّة مسجّلة.
  static UbntStats parse({
    required Object? device,
    required Object? system,
    required Object? statistics,
    required Object? interfaces,
  }) {
    final st = statistics is List && statistics.isNotEmpty ? _map(statistics.first) : _map(statistics);
    final dev = _map(st['device']);
    final id = _map(_map(device)['identification']);
    final sys = _map(system);
    final wl = _map(st['wireless']);

    // ── الجهاز ─────────────────────────────────────────────────────────────────────────
    final cpus = [for (final c in _list(dev['cpu'])) _int(_map(c)['usage'])].whereType<int>().toList();
    final temps = [for (final t in _list(dev['temperatures'])) _map(t)];
    final cpuTemp = temps.where((t) => t['type'] == 'cpu').map((t) => _int(t['value'])).whereType<int>().firstOrNull ??
        temps.map((t) => _int(t['value'])).whereType<int>().fold<int?>(null, (a, b) => a == null || b > a ? b : a);
    final ram = _map(dev['ram']);
    final gps = _map(dev['gps']);
    final hasFix = gps['fix'] == true;
    final host = UbntHost(
      hostname: (sys['hostname'] ?? '').toString(),
      devmodel: (id['product'] ?? id['model'] ?? '').toString(),
      fwversion: (id['firmwareVersion'] ?? id['firmware'] ?? '').toString(),
      uptime: _int(dev['uptime']) ?? 0,
      cpuload: cpus.isEmpty ? 0 : (cpus.reduce((a, b) => a + b) / cpus.length).round(),
      temperature: cpuTemp ?? 0,
    );

    // ── الراديو الرئيسيّ والاحتياطيّ ──────────────────────────────────────────────────────
    final radios = [for (final r in _list(wl['radios'])) _map(r)];
    final main = radios.where((r) => r['id'] == 'main').firstOrNull ?? radios.firstOrNull ?? const <String, dynamic>{};
    final backup = radios.where((r) => r['id'] == 'backup').firstOrNull;
    final mainFreq = _int(_map(main['frequency'])['center']) ?? 0;
    final mainWidth = _int(_map(main['channelWidth'])['tx']) ?? 0;
    final mainCap = _map(_map(main['linkQuality'])['capacity']);
    final linkCap = mainCap.isNotEmpty ? mainCap : _map(_map(wl['linkQuality'])['capacity']);
    final is60 = mainFreq >= 50000;

    // ── الأطراف (PtP: طرفٌ واحد · PtMP: محطّات) ───────────────────────────────────────────
    final peers = [for (final p in _list(wl['peers'])) _map(p)];
    final stations = <UbntStation>[];
    for (final p in peers) {
      final common = _map(p['common']);
      final pid = _map(common['identification']);
      final locals = [for (final l in _list(p['local'])) _map(l)];
      final remotes = [for (final r in _list(p['remote'])) _map(r)];
      final local = locals.where((l) => l['id'] == 'main').firstOrNull ?? locals.firstOrNull ?? const <String, dynamic>{};
      final remote = remotes.where((r) => r['id'] == 'main').firstOrNull ?? remotes.firstOrNull ?? const <String, dynamic>{};
      final lq = _map(local['linkQuality']);
      final rq = _map(remote['linkQuality']);
      final cap = _map(lq['capacity']);
      final mcs = _map(lq['mcs']);
      final dl = _int(cap['dl']);
      final ul = _int(cap['ul']);
      stations.add(UbntStation(
        mac: (pid['mac'] ?? '').toString(),
        ip: common['mgmtIp']?.toString(),
        hostname: common['hostname']?.toString(),
        signal: _int(lq['signal']) ?? 0,
        txSignal: _int(rq['signal']) ?? 0,
        noise: 0,
        ccq: 0,
        txRate: dl == null ? 0 : (dl / 1000).round(),
        rxRate: ul == null ? 0 : (ul / 1000).round(),
        connTime: _int(local['connectionTime']) ?? 0,
        txMcs: _int(mcs['txIdx']),
        rxMcs: _int(mcs['rxIdx']),
        distanceMeters: _int(common['distance']),
        linkUptimeSec: _int(local['connectionTime']),
        dlSignalExpect: _int(lq['idealSignal']),
        ulSignalExpect: _int(rq['idealSignal']),
        dlCapacityKbps: dl,
        ulCapacityKbps: ul,
        dlCapacityExpectKbps: _int(cap['dlIdeal']),
        ulCapacityExpectKbps: _int(cap['ulIdeal']),
        isLinked60: is60,
      ));
    }
    final first = peers.firstOrNull;
    final firstLocal = first == null ? null : [for (final l in _list(first['local'])) _map(l)].firstOrNull;
    final firstQ = _map(firstLocal?['linkQuality']);

    final wireless = radios.isEmpty && peers.isEmpty
        ? null
        : UbntWireless(
            essid: '',
            mode: peers.length > 1 ? 'ap-ptmp' : '',
            signal: _int(firstQ['signal']) ?? 0,
            noise: 0,
            ccq: 0,
            txRate: _int(linkCap['dl']) == null ? 0 : (_int(linkCap['dl'])! / 1000).round(),
            rxRate: _int(linkCap['ul']) == null ? 0 : (_int(linkCap['ul'])! / 1000).round(),
            channel: 0,
            frequency: mainFreq,
            distance: _int(_map(first?['common'])['distance']) ?? 0,
            chanbw: mainWidth,
          );

    // ── المنافذ: العدّادات من الإحصاءات، والسرعة والوصل من /interfaces ────────────────────────
    final ifStatus = <String, Map<String, dynamic>>{};
    final ifMac = <String, String>{};
    for (final i in _list(interfaces)) {
      final m = _map(i);
      final ident = _map(m['identification']);
      final name = (ident['id'] ?? '').toString();
      if (name.isEmpty) continue;
      ifStatus[name] = _map(m['status']);
      ifMac[name] = (ident['mac'] ?? '').toString();
    }
    final ifs = <UbntInterface>[];
    String? lanSpeed;
    for (final i in _list(st['interfaces'])) {
      final m = _map(i);
      final name = (m['id'] ?? '').toString();
      if (name.isEmpty || name == 'lo') continue;
      final s = _map(m['statistics']);
      final status = {..._map(m['status']), ...?ifStatus[name]};
      final isEth = status['type'] == 'ethernet' || name.startsWith('eth');
      final speed = isEth ? _speedOf(status['currentSpeed'] ?? status['speed']) : null;
      final plugged = isEth ? status['plugged'] == true : status['enabled'] != false;
      if (isEth && plugged && lanSpeed == null && speed != null) {
        final full = (status['currentSpeed'] ?? status['speed'] ?? '').toString().toLowerCase().contains('full');
        lanSpeed = '${speed}Mbps-${full ? 'Full' : 'Half'}';
      }
      ifs.add(UbntInterface(
        ifname: name,
        hwaddr: ifMac[name] ?? '',
        enabled: status['enabled'] != false,
        plugged: plugged,
        rxBytes: _int(s['rxBytes']),
        txBytes: _int(s['txBytes']),
        speed: speed,
        duplex: (status['currentSpeed'] ?? '').toString().toLowerCase().contains('full'),
      ));
    }
    // المنفذ السلكيّ أوّلاً: منه يُحسب «سير الترفك» في اللوحات.
    ifs.sort((a, b) => (b.ifname.startsWith('eth') ? 1 : 0) - (a.ifname.startsWith('eth') ? 1 : 0));

    // ── ما لا خانة له في النموذج: يُعرض حقائق إضافيّة ─────────────────────────────────────
    final extras = <({String k, String v})>[];
    final mainPower = _map(main['outputPower']);
    if (mainFreq > 0) {
      extras.add((k: 'الراديو الرئيسيّ', v: '${is60 ? (mainFreq / 1000).toStringAsFixed(2) : mainFreq} ${is60 ? 'GHz' : 'MHz'} · عرض $mainWidth MHz'));
    }
    if (linkCap.isNotEmpty) {
      extras.add((k: 'السعة', v: '↓${_mbps(_int(linkCap['dl']))} / ↑${_mbps(_int(linkCap['ul']))} Mbps'));
    }
    final mcs = _map(firstQ['mcs']);
    if (mcs['rxLabel'] != null || mcs['txLabel'] != null) {
      extras.add((k: 'التعديل', v: 'استقبال ${mcs['rxLabel'] ?? '—'} · إرسال ${mcs['txLabel'] ?? '—'}'));
    }
    if (mainPower['conducted'] != null) {
      extras.add((k: 'قدرة الإرسال', v: '${mainPower['conducted']} dBm · EIRP ${mainPower['eirp'] ?? '—'}'));
    }
    final ideal = _int(firstQ['idealSignal']);
    if (ideal != null) extras.add((k: 'الإشارة المثاليّة', v: '$ideal dBm'));
    final score = _int(_map(_map(wl['linkQuality'])['linkScore'])['dl']);
    if (score != null) extras.add((k: 'تقييم الوصلة', v: '$score / 100'));
    final interference = _dbl(_map(_map(main['channelUtilization'])['common'])['interference']);
    if (interference != null) extras.add((k: 'التداخل', v: '${interference.toStringAsFixed(1)}٪'));
    if (backup != null) {
      final bf = _map(backup['frequency']);
      final bc = _map(_map(backup['linkQuality'])['capacity']);
      final bw = _int(_map(backup['channelWidth'])['tx']);
      extras.add((
        k: 'الاحتياطيّ 5 GHz',
        v: '${_int(bf['center']) ?? '—'} MHz · عرض ${bw ?? '—'} · ↓${_mbps(_int(bc['dl']))} / ↑${_mbps(_int(bc['ul']))} Mbps'
            '${backup['linkState'] == 'connected' ? ' · متّصل' : ''}',
      ));
    }
    if (gps.isNotEmpty) {
      extras.add((k: 'GPS', v: hasFix ? 'مثبّت · ${_int(gps['sats']) ?? 0} أقمار' : 'بلا تثبيت'));
    }
    final remoteCommon = _map(first?['common']);
    if (remoteCommon['mgmtIp'] != null || remoteCommon['hostname'] != null) {
      extras.add((k: 'الطرف الآخر', v: [remoteCommon['hostname'], remoteCommon['mgmtIp']].whereType<Object>().join(' · ')));
    }

    return UbntStats(
      apiVersion: 8,
      host: host,
      wireless: wireless,
      interfaces: ifs,
      stations: stations,
      latitude: hasFix ? _dbl(gps['lat']) : null,
      longitude: hasFix ? _dbl(gps['lon']) : null,
      memTotalKb: _int(ram['total']) == null ? null : (_int(ram['total'])! / 1024).round(),
      memFreeKb: _int(ram['free']) == null ? null : (_int(ram['free'])! / 1024).round(),
      lanSpeed: lanSpeed,
      extras: extras,
    );
  }
}
