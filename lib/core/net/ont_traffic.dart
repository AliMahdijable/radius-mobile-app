import 'dart:async';

import '../../models/device_health.dart';
import 'huawei_ont_service.dart';
import 'zte_ont_service.dart';

/// ترافيك الـONU اللحظيّ (Huawei) في كارت المشترك — طلب المالك ٢٢ أكتوبر («اشتغلي على جلب ترفك onu»).
///
/// المصدر: عدّادات البايت التراكميّة لواجهات **المشترك** على الجهاز — كلّ شبكة واي فاي (`wlaninfo.asp`) وكلّ منفذ LAN
/// (`ethinfo.asp`) — مجموعةً. والمجموع لا واجهةٌ واحدة: المشترك يربط LAN والواي فاي معاً (المالك: «لا يكون اعتمادك فقط ع
/// كاونتر الواي فاي»)، وكلّها تواجه المشترك فلا ازدواج — الـPON وحده يواجه البرج، وعدّاداته حزمٌ لا بايت.
/// المُرسَل على الواجهة إلى أجهزة المشترك = **تحميله**، والمُستقبَل منها = **رفعه**.
///
/// قِيس ٢٢ أكتوبر على ستّة أجهزة حقيقيّة في شبكة popq (HG8245Q2، HS8545M، HG8245C، HG8145C، HG8546M، وآخر): الصيغة
/// واحدة، وجهازٌ كان ترافيكه كلّه تقريباً على LAN (واي فاي ~١ م.ب من ١٫٧ ج.ب).

/// عدّادات الواجهات: مفتاحٌ لكلّ واجهة (مسار TR-069) ⇒ (المُرسَل للمشترك، المُستقبَل منه) بالبايت، ووقت وصول صفحتها.
///
/// الوقت لكلّ صفحة لا للقراءة كلّها: الصفحتان تُقرآن بالتتابع (~٠٫٧ث بينهما)، ونبضةٌ مدّتها ٥ث يجعل فيها فارقُ الثانية
/// خطأً بـ١٥٪ لو حُسبت الواجهتان بوقتٍ واحد.
class OntByteCounters {
  const OntByteCounters(this.byIface);

  final Map<String, ({int sent, int received, DateTime at})> byIface;
}

/// تحليل الصفحتين — نصٌّ ⇒ عدّادات (نقيّ، يُختبر بلا جهاز).
class OntCounterParse {
  OntCounterParse._();

  /// `stPacketInfo(domain,totalBytesSent,totalPacketsSent,totalBytesReceived,totalPacketsReceived)` — شبكةٌ لكلّ صفّ.
  static final RegExp _wifi = RegExp(r'new stPacketInfo\("([^"]*)","(\d+)","\d+","(\d+)","\d+"\)');

  /// `LANStats(domain,txPakets,txBytes,rxPackets,rxBytes)` — منفذٌ لكلّ صفّ (المرسَل إلى جهاز المشترك أوّلاً).
  static final RegExp _lan = RegExp(r'new LANStats\("([^"]*)","\d+","(\d+)","\d+","(\d+)"\)');

  /// نهاية مصفوفة كلّ صفحة — عندها يكفي ما قُرئ (HuaweiOntService.fetchHead يقطع القراءة).
  ///
  /// ⚠️ مصفوفةٌ **بصفٍّ أو null** لا أيّ `new Array(`: صفحة الواي فاي تُعلن `var PacketInfo = new Array();` فارغةً أوّلاً
  /// ثمّ تملؤها بعد ٢٧ بايتاً (كلّ الطرازات الستّة، ٢٢ أكتوبر) — والتوقّف عند الفارغة كان يُسقط الواي فاي كلّه بصمت.
  static final RegExp wifiEnd = RegExp(r'PacketInfo = new Array\((?:new stPacketInfo\(|null).*?\);', dotAll: true);
  static final RegExp lanEnd = RegExp(r'userEthInfos = new Array\((?:new LANStats\(|null).*?\);', dotAll: true);

  static Map<String, ({int sent, int received})> wifi(String html) => {
        for (final m in _wifi.allMatches(html))
          _key(m.group(1)!): (sent: int.parse(m.group(2)!), received: int.parse(m.group(3)!)),
      };

  static Map<String, ({int sent, int received})> lan(String html) => {
        for (final m in _lan.allMatches(html))
          _key(m.group(1)!): (sent: int.parse(m.group(2)!), received: int.parse(m.group(3)!)),
      };

  /// المسار بترميز `\x2e` في بعض الطرازات (صفحة الواي فاي) ونصّاً في غيرها.
  static String _key(String domain) => domain.replaceAll(r'\x2e', '.');
}

/// معدّل التحميل والرفع (بت/ث) من قراءتين متتاليتين — بأمانٍ على التفاف العدّاد وإعادة الإقلاع.
class OntTrafficMeter {
  OntByteCounters? _prev;
  DateTime? _at;

  /// عدّادات ٣٢ بت (كلّ القيم المرصودة دون ٢^٣٢): بترافيكٍ عالٍ تلتفّ كلّ بضع دقائق.
  static const int _wrap = 4294967296;

  /// سقف العقلانيّة: GPON نزولاً ٢٫٥ جيجابت — ما فوقه قراءةٌ شاذّة لا ترافيك.
  static const int _sane = 2500000000;

  /// يُضيف قراءةً ويُرجع المعدّل منذ السابقة — null للأولى (تزرع المرجع)، أو بعد إعادة إقلاعٍ/تصفير، أو قراءةٍ شاذّة.
  ({int downBps, int upBps})? add(OntByteCounters now, DateTime at) {
    final prev = _prev;
    final prevAt = _at;
    _prev = now;
    _at = at;
    if (prev == null || prevAt == null) return null;
    if (at.difference(prevAt).inMilliseconds < 500) return null;
    var down = 0.0;
    var up = 0.0;
    var counted = 0;
    for (final e in now.byIface.entries) {
      final p = prev.byIface[e.key];
      // واجهةٌ ظهرت للتوّ (شبكةٌ فُعّلت) تُعدّ من القراءة التالية
      if (p == null) continue;
      final secs = e.value.at.difference(p.at).inMilliseconds / 1000.0;
      if (secs < 0.5) continue;
      final ds = _delta(p.sent, e.value.sent);
      final dr = _delta(p.received, e.value.received);
      // إعادة إقلاعٍ أو تصفير: لا رقمٌ كاذب — القراءة التالية تحسب على المرجع الجديد
      if (ds == null || dr == null) return null;
      down += ds * 8 / secs;
      up += dr * 8 / secs;
      counted++;
    }
    if (counted == 0) return null;
    final d = down.round();
    final u = up.round();
    if (d > _sane || u > _sane) return null;
    return (downBps: d, upBps: u);
  }

  void reset() {
    _prev = null;
    _at = null;
  }

  static int? _delta(int prev, int now) {
    if (now >= prev) return now - prev;
    // التفاف: كان قريباً من القمّة وعاد قريباً من الصفر — وإلّا فتصفير
    if (prev < _wrap && prev >= _wrap * 3 ~/ 4 && now < _wrap ~/ 4) return now + _wrap - prev;
    return null;
  }
}

/// جلسة ويب معمَّرة لقياس ترافيك الـONU: دخولٌ واحد لعمر الكارت، ثمّ في كلّ نبضة رأسا الصفحتين وحدهما (~٨ ك.ب و~٠٫٧ث
/// لكلٍّ بدل ٢٠٠ ك.ب–٢ م.ب كاملة)، والخروج عند الإغلاق.
///
/// ZTE (ZXIC MH80، ٢٥ أكتوبر): العدّادات نفسها (كلّ SSID وكلّ منفذ، ٣٢ بت) من صفحتي `status_wlaninfo_t` و`status_ponlan_info_t`
/// كاملتين (~١٤٠ ك.ب و~١ث لكلٍّ — لا رأسَ يُقطع: الجدول بعد القالب). الواي فاي كلّ نبضة؛ والمنافذ في الأولى ثمّ كلّ سادسة ما دامت
/// غير موصولة، وكلّ نبضة حين يُوصل منفذ.
class OntTrafficSession {
  OntTrafficSession._(this._session) : _zte = null;
  OntTrafficSession._zte(ZteOntSession zte)
      : _session = null,
        _zte = zte;

  final OntLoginResult? _session;
  final ZteOntSession? _zte;
  bool _closed = false;
  int _zteSamples = 0;
  bool _zteLanLinked = true;

  /// صفحات الترافيك الموجودة فعلاً في قائمة الجهاز — تُحسم مرّةً. D401 أسماؤه ≠ MH80، وطلب اسمٍ غير موجودٍ يفسد الجلسة
  /// (كصفحة الضوء)، فنختار من القائمة. null لم تُحسم بعد؛ `''` حُسمت وليست موجودة.
  String? _zteWlanPage;
  String? _zteLanPage;
  bool _ztePagesResolved = false;

  /// صفحةٌ أعطت عدّادات مرّةً ثمّ غابت ⇒ القراءة فاشلة (لا معدّل LAN وحده يُعرض كأنّه الكلّ).
  bool _hadWifi = false;
  bool _hadLan = false;

  /// [vendor] من الفحص (`OntOpticalInfo.vendor`): `zte` ⇒ دخول ZTE باعتمادات الوكيل نفسها؛ وإلّا هواوي كما كان.
  static Future<OntTrafficSession?> open({
    required String ip,
    required String user,
    required String pass,
    String vendor = 'huawei',
    Duration budget = const Duration(seconds: 15),
  }) async {
    if (vendor == 'zte') {
      final z = await ZteOntService.loginConfigured(ip, user, pass);
      return z == null ? null : OntTrafficSession._zte(z);
    }
    final s = await HuaweiOntService.login(ip, user, pass, budget: budget);
    return s == null ? null : OntTrafficSession._(s);
  }

  /// عدّادات الواجهات لحظة القراءة — null: تعذّرت (جلسةٌ انتهت أو صفحةٌ غابت ⇒ المتصل يُغلق ويعيد الفتح بعد مهلة).
  Future<OntByteCounters?> sample() async {
    if (_closed) return null;
    final zte = _zte;
    if (zte != null) return _sampleZte(zte);
    final session = _session!;
    final w = await HuaweiOntService.fetchHead(session, '/html/amp/wlaninfo/wlaninfo.asp', OntCounterParse.wifiEnd);
    final wAt = DateTime.now();
    final l = await HuaweiOntService.fetchHead(session, '/html/amp/ethinfo/ethinfo.asp', OntCounterParse.lanEnd);
    final lAt = DateTime.now();
    final wifi = OntCounterParse.wifi(w ?? '');
    final lan = OntCounterParse.lan(l ?? '');
    if ((_hadWifi && wifi.isEmpty) || (_hadLan && lan.isEmpty)) return null;
    if (wifi.isEmpty && lan.isEmpty) return null;
    _hadWifi = _hadWifi || wifi.isNotEmpty;
    _hadLan = _hadLan || lan.isNotEmpty;
    return OntByteCounters({
      for (final e in wifi.entries) e.key: (sent: e.value.sent, received: e.value.received, at: wAt),
      for (final e in lan.entries) e.key: (sent: e.value.sent, received: e.value.received, at: lAt),
    });
  }

  /// ZTE: صفحةٌ عادت دخولاً (جلسةٌ انتهت أو طُردنا) ⇒ null فيُغلق المتصل ويعيد الفتح بعد مهلة.
  ///
  /// الصفحات تُحسم من قائمة الجهاز أوّلاً (MH80: `status_wlaninfo_t`+`status_ponlan_info_t`؛ D401: `pon_status_lan_info_t`
  /// بلا واي فاي، جدول خلايا «Bytes Received/Sent»). منفذٌ يُقرأ كلّ نبضةٍ حين لا واي فاي (مصدرٌ وحيد)، وإلّا كـMH80.
  Future<OntByteCounters?> _sampleZte(ZteOntSession zte) async {
    if (!_ztePagesResolved) {
      final menu = await ZteOntService.menuPages(zte);
      if (menu.isEmpty) {
        // 🛡️ احتياطٌ: جهازٌ تعذّرت قراءة قائمته (إطارٌ مختلف) ⇒ أسماء MH80 المعروفة مباشرةً كما كان. D401 قائمته تُقرأ.
        _zteWlanPage = 'status_wlaninfo_t.gch';
        _zteLanPage = 'status_ponlan_info_t.gch';
      } else {
        _zteWlanPage = _pickZtePage(menu, has: 'wlan');
        _zteLanPage = _pickZtePage(menu, has: 'lan', avoid: 'wlan');
      }
      _ztePagesResolved = true;
    }
    var wifi = const <String, ({int sent, int received})>{};
    var wAt = DateTime.now();
    if (_zteWlanPage != null && _zteWlanPage!.isNotEmpty) {
      final w = await ZteOntService.page(zte, _zteWlanPage!);
      wAt = DateTime.now();
      if (w == null) return null;
      wifi = ZteOntParse.wifi(w);
    }
    // بلا واي فاي (D401): المنافذ كلّ نبضة. مع واي فاي (MH80): في الأولى ثمّ كلّ سادسة ما لم يُوصل منفذ.
    final noWifi = _zteWlanPage == null || _zteWlanPage!.isEmpty;
    final readLan = noWifi || _zteLanLinked || _zteSamples % 6 == 0;
    _zteSamples++;
    ({Map<String, ({int sent, int received})> counters, bool linked})? lan;
    var lAt = wAt;
    if (readLan && _zteLanPage != null && _zteLanPage!.isNotEmpty) {
      final l = await ZteOntService.page(zte, _zteLanPage!);
      lAt = DateTime.now();
      if (l == null) return null;
      lan = ZteOntParse.lan(l); // MH80 (Table_laninterface)
      if (lan.counters.isEmpty) lan = ZteOntParse.lanLabels(l); // D401 (جدول Bytes Received/Sent)
      _zteLanLinked = lan.linked;
    }
    if (wifi.isEmpty && (lan == null || lan.counters.isEmpty)) return null;
    return OntByteCounters({
      for (final e in wifi.entries) e.key: (sent: e.value.sent, received: e.value.received, at: wAt),
      if (lan != null)
        for (final e in lan.counters.entries) e.key: (sent: e.value.sent, received: e.value.received, at: lAt),
    });
  }

  /// صفحةٌ في القائمة تحوي [has] وحالةً (status/info) وليست إعداداً، بلا [avoid]. `''` حين لا شيء.
  static String _pickZtePage(Set<String> menu, {required String has, String? avoid}) {
    for (final n in menu) {
      final l = n.toLowerCase();
      if (!l.contains(has)) continue;
      if (avoid != null && l.contains(avoid)) continue;
      if (!(l.contains('status') || l.contains('info'))) continue;
      if (RegExp(r'conf|set|mode|vlan|ratelimit|flowctl|isolate').hasMatch(l)) continue;
      return n;
    }
    return '';
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    final zte = _zte;
    if (zte != null) {
      await ZteOntService.logout(zte);
      return;
    }
    await HuaweiOntService.logout(_session!);
  }
}
