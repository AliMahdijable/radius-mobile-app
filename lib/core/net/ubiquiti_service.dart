import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';

import '../../models/device_health.dart';

/// Direct port of mobile-app/lib/core/services/ubiquiti_service.dart.
/// Handles both airOS 6.x (form login) and 8.x (JSON /api/auth).
class UbiquitiService {
  static Dio _buildDio(String baseUrl) {
    final dio = Dio(BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 5),
      receiveTimeout: const Duration(seconds: 8),
      validateStatus: (_) => true,
      followRedirects: false,
      headers: {'Accept': 'application/json, text/html, */*'},
    ));
    (dio.httpClientAdapter as IOHttpClientAdapter).createHttpClient = () {
      final c = HttpClient();
      c.badCertificateCallback = (_, __, ___) => true;
      return c;
    };
    return dio;
  }

  /// ⚠️ [budget] — ميزانيّة زمنيّة للسلسلة كلّها. راجع الشرح المفصّل
  /// في `HuaweiOntService.login`: المستدعي يتخلّى عنّا عند سقف الفحص،
  /// و`.timeout` في Dart لا يُلغي العمل تحته — فتُكمل السلسلة وحدها
  /// بلا قارئ. وهذه أقصر من سلسلة Huawei (عنوانان × محاولتين × خمس
  /// ثوانٍ = عشرون) لكنّها تتجاوز السقف كذلك، والنمط يجب أن يكون
  /// واحداً في المسارين وإلّا صار السلوك يعتمد على نوع الجهاز.
  static Future<UbiquitiLoginResult?> login(
    String host,
    String user,
    String pass, {
    Duration? budget,
  }) async {
    final bases = ['https://$host', 'http://$host'];
    final deadline = budget == null ? null : DateTime.now().add(budget);
    bool spent() => deadline != null && !DateTime.now().isBefore(deadline);
    for (final base in bases) {
      if (spent()) return null;
      // ⚠️ إن كان المنفذ نفسه مغلقاً فلا معنى لثلاث محاولات عليه.
      //
      // 🐛 الميزانيّة مشتركة: جهاز airOS 5 لا يفتح 443 يُنفق عليه
      // `https://` ثلاث مهلات اتّصال (٥ ثوانٍ لكلٍّ = ١٥) — وهي
      // الميزانيّة كلّها. فلا يُبلَغ `http://` أبداً، ويُعلَن الجهاز
      // متعذّراً وهو يُجيب فوراً على HTTP. أي أنّ مسار v5 كان قد
      // يبقى معطّلاً ميدانيّاً رغم صحّته.
      if (!await _canConnect(base)) continue;
      final v6 = await _tryLoginV6(base, user, pass);
      if (v6 != null) return v6;
      if (spent()) return null;
      final v8 = await _tryLoginV8(base, user, pass);
      if (v8 != null) return v8;
      if (spent()) return null;
      // أخيراً: airOS 5 (XM) القديم. يُجرَّب بعدهما لأنّ فحصه أضعف —
      // يقبل صفحةً بدل JSON، فلا نريده يسبق مساراً أدقّ.
      final v5 = await _tryLoginV5(base, user, pass);
      if (v5 != null) return v5;
    }
    return null;
  }

  /// فحصٌ رخيص: هل يقبل هذا العنوان اتّصالاً أصلاً؟ محاولةٌ واحدة
  /// بمهلةٍ قصيرة بدل ثلاث محاولاتٍ كاملة على منفذٍ مغلق.
  static Future<bool> _canConnect(String base) async {
    try {
      final uri = Uri.parse(base);
      final port = uri.hasPort ? uri.port : (uri.scheme == 'https' ? 443 : 80);
      final sock = await Socket.connect(uri.host, port,
          timeout: const Duration(milliseconds: 1200));
      sock.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<UbiquitiLoginResult?> _tryLoginV6(
      String base, String user, String pass) async {
    final dio = _buildDio(base);
    try {
      final rootRes = await dio.get('/');
      String? cookie =
          _extractAirosCookie(rootRes) ?? _extractAnyCookie(rootRes);
      final body =
          'uri=&username=${Uri.encodeQueryComponent(user)}&password=${Uri.encodeQueryComponent(pass)}';
      final res = await dio.post(
        '/login.cgi',
        data: body,
        options: Options(headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
          if (cookie != null) 'Cookie': cookie,
          'Referer': '$base/login.cgi',
        }),
      );
      if (res.statusCode != 302) return null;
      final location = res.headers.value('location') ?? '';
      if (!location.contains('index')) return null;
      cookie ??= _extractAirosCookie(res) ?? _extractAnyCookie(res);
      if (cookie == null) return null;
      final check = await dio.get(
        '/status.cgi',
        options: Options(headers: {
          'Cookie': cookie,
          'Referer': '$base/',
          'Accept': 'application/json',
        }),
      );
      if (check.statusCode != 200) return null;
      if (!_looksLikeJsonStatus(check.data)) return null;
      return UbiquitiLoginResult(
          baseUrl: base, sessionCookie: cookie, airosVariant: 'v6');
    } catch (_) {
      return null;
    }
  }

  /// **airOS 5 (XM) القديم** — `status.cgi` فيه صفحة HTML تحمل
  /// متغيّرات JavaScript، لا JSON.
  ///
  /// 🐛 بلاغ المستخدم: جهاز مشترك بياناته صحيحة ولا يجلب معلومات.
  /// والسبب أنّ [_tryLoginV6] **يرفض جلسةً ناجحة** بسطر
  /// `if (!_looksLikeJsonStatus(...)) return null;` — فالدخول يتمّ
  /// والكوكي يصل، ثمّ تُرمى الجلسة لأنّ الردّ ليس JSON. فالأجهزة
  /// القديمة كانت تظهر «تعذّر الوصول» وهي حيّةٌ تُجيب.
  ///
  /// مُلتقَطٌ من جهازٍ حقيقيّ (PowerStation5):
  /// ```js
  /// uptime="1288018"; essid="..."; signal=-29; noisef=-90;
  /// ccq=1000; tx_rate=54.0; rx_rate=54.0; lan_state="ON";
  /// ```
  static Future<UbiquitiLoginResult?> _tryLoginV5(
      String base, String user, String pass) async {
    final dio = _buildDio(base);
    try {
      final rootRes = await dio.get('/');
      String? cookie =
          _extractAirosCookie(rootRes) ?? _extractAnyCookie(rootRes);
      // ⚠️ **multipart لا urlencoded**: قِيست الصيغتان على جهازٍ حقيقيّ
      // (PowerStation5) بنفس الكوكي والرأسيّات:
      //   urlencoded → 200 بلا `Location`  = صفحة الدخول ثانيةً (فشل)
      //   multipart  → 302 إلى `/`          = نجاح
      // فالإصدار القديم لا يقبل غيرها. وهذا سبب بقاء الجهاز «متعذّراً»
      // رغم صحّة بياناته.
      final res = await dio.post(
        '/login.cgi',
        data: FormData.fromMap({
          'uri': '/',
          'username': user,
          'password': pass,
        }),
        options: Options(headers: {
          if (cookie != null) 'Cookie': cookie,
          'Referer': '$base/login.cgi',
        }),
      );
      // ولا نشترط أن يحوي `Location` كلمة `index` كما يفعل مسار v6 —
      // هذا الإصدار يُحوّل إلى `/` مجرّدة.
      if (res.statusCode != 302) return null;
      cookie ??= _extractAirosCookie(res) ?? _extractAnyCookie(res);
      if (cookie == null) return null;
      // الحُكم على النجاح: هل تحمل الصفحة متغيّرات الحالة فعلاً؟
      // كلمةُ سرٍّ خاطئة تُعيد صفحة الدخول ولا `signal` فيها.
      final check = await dio.get(
        '/status.cgi',
        options: Options(headers: {'Cookie': cookie, 'Referer': '$base/'}),
      );
      if (check.statusCode != 200) return null;
      final text = (check.data ?? '').toString();
      if (!_looksLikeLegacyStatus(text)) return null;
      return UbiquitiLoginResult(
          baseUrl: base, sessionCookie: cookie, airosVariant: 'v5');
    } catch (_) {
      return null;
    }
  }

  /// يحوّل صفحة airOS 5 إلى [UbiquitiStatus] — بنفس دلالات مسار JSON
  /// كي لا تتفرّع الواجهة على نوع الجهاز.
  static Future<UbiquitiStatus?> _parseLegacy(
      String body, UbiquitiLoginResult session, Dio dio) async {
    String? str(String k) =>
        RegExp('\\b$k\\s*=\\s*"([^"]*)"').firstMatch(body)?.group(1);
    num? num_(String k) => num.tryParse(
        RegExp('\\b$k\\s*=\\s*([-0-9.]+)').firstMatch(body)?.group(1) ?? '');

    final signal = num_('signal')?.toInt();
    final essid = str('essid') ?? '';
    if (signal == null && essid.isEmpty) return null;

    // الاسم والطراز من عنوان الصفحة الرئيسة:
    //   <title>abbas.jable@popq:  [PowerStation5-22V] - Main</title>
    // وهو الموضع الوحيد الذي يحملهما في هذا الإصدار.
    var hostname = '';
    var model = '';
    try {
      // ⚠️ مهلةٌ قصيرة صريحة: البيانات المفيدة **بين أيدينا أصلاً**،
      // وهذا الطلب تحسينٌ للاسم والطراز. وجهازٌ بطيء في `/index.cgi`
      // كان يُعلّق اللقطة ثماني ثوانٍ بعد أن اكتملت — وعلى موجةٍ
      // بعشرات المشتركين يتراكم ذلك سلاسلَ يتيمة تخنق المقابس،
      // فيُعلَن جهازٌ حيٌّ ميّتاً. لا شيء هنا يستحقّ ذلك الثمن.
      final idx = await dio
          .get(
            '/index.cgi',
            options: Options(headers: {
              'Cookie': session.sessionCookie,
              'Referer': '${session.baseUrl}/',
            }),
          )
          .timeout(const Duration(milliseconds: 1500));
      final t = RegExp(r'<title>([^<]*)</title>')
              .firstMatch((idx.data ?? '').toString())
              ?.group(1) ??
          '';
      hostname = t.split(':').first.trim();
      model = RegExp(r'\[([^\]]+)\]').firstMatch(t)?.group(1)?.trim() ?? '';
    } catch (_) {
      // العنوان تحسينٌ لا شرط — الإشارة والجودة أهمّ منه.
    }

    // `lan_state="ON"` هو كلّ ما يعطيه هذا الإصدار عن المنفذ: لا سرعة.
    final lanOn = (str('lan_state') ?? '').toUpperCase() == 'ON';
    // `ccq=1000` في هذا الإصدار = ١٠٠٪ — نفس قسمة مسار JSON.
    final rawCcq = num_('ccq');
    final ccq = rawCcq == null
        ? null
        : (rawCcq > 100 ? (rawCcq / 10).round() : rawCcq.toInt());
    // المعدّلات بالميغابت هنا، والنموذج يريد الكيلوبت.
    int? kbps(String k) {
      final v = num_(k);
      return v == null ? null : (v * 1000).round();
    }

    return UbiquitiStatus(
      hostname: hostname,
      firmware: model,
      uptimeSeconds: int.tryParse(str('uptime') ?? ''),
      ssid: essid,
      mode: 'station',
      signalDbm: signal,
      noiseFloorDbm: num_('noisef')?.toInt(),
      ccqPercent: ccq,
      distanceMeters: null,
      txRateKbps: kbps('tx_rate'),
      rxRateKbps: kbps('rx_rate'),
      lanPorts: [
        LanPort(name: 'LAN', speed: null, plugged: lanOn),
      ],
      peerMac: str('apmac'),
      peerCount: null,
      rxBytes: num_('lan_rxbytes')?.toInt(),
      txBytes: num_('lan_txbytes')?.toInt(),
      baseUrl: session.baseUrl,
    );
  }

  static bool _looksLikeLegacyStatus(String body) =>
      body.contains('signal=') && body.contains('essid=');

  static Future<UbiquitiLoginResult?> _tryLoginV8(
      String base, String user, String pass) async {
    final dio = _buildDio(base);
    try {
      final res = await dio.post(
        '/api/auth',
        data: jsonEncode({'username': user, 'password': pass}),
        options: Options(
          headers: {
            'Content-Type': 'application/json',
            'Referer': '$base/',
          },
          responseType: ResponseType.json,
        ),
      );
      if (res.statusCode != 200) return null;
      final cookie = _extractAirosCookie(res);
      final token = res.headers.value('x-auth-token');
      if (cookie == null && token == null) return null;
      final check = await dio.get(
        '/api/status',
        options: Options(headers: {
          if (cookie != null) 'Cookie': cookie,
          if (token != null) 'X-Auth-Token': token,
          'Accept': 'application/json',
        }),
      );
      if (check.statusCode != 200) return null;
      if (!_looksLikeJsonStatus(check.data)) return null;
      return UbiquitiLoginResult(
        baseUrl: base,
        sessionCookie: cookie ?? '',
        csrfToken: token,
        airosVariant: 'v8',
      );
    } catch (_) {
      return null;
    }
  }

  static bool _looksLikeJsonStatus(dynamic data) {
    if (data is Map) {
      return data.containsKey('wireless') || data.containsKey('host');
    }
    if (data is String && data.trim().startsWith('{')) {
      try {
        final m = jsonDecode(data);
        return m is Map && (m.containsKey('wireless') || m.containsKey('host'));
      } catch (_) {
        return false;
      }
    }
    return false;
  }

  static String? _extractAirosCookie(Response res) {
    final raw = res.headers.map['set-cookie'] ?? const [];
    final parts = <String>[];
    for (final line in raw) {
      final nameVal = line.split(';').first.trim();
      if (nameVal.toUpperCase().startsWith('AIROS_') ||
          nameVal.contains('SESSION')) {
        parts.add(nameVal);
      }
    }
    return parts.isEmpty ? null : parts.join('; ');
  }

  static String? _extractAnyCookie(Response res) {
    final raw = res.headers.map['set-cookie'] ?? const [];
    final parts = <String>[];
    for (final line in raw) {
      final nameVal = line.split(';').first.trim();
      if (nameVal.contains('=')) parts.add(nameVal);
    }
    return parts.isEmpty ? null : parts.join('; ');
  }

  static Future<UbiquitiStatus?> fetchStatus(
      UbiquitiLoginResult session) async {
    final dio = _buildDio(session.baseUrl);
    try {
      final path = session.airosVariant == 'v8' ? '/api/status' : '/status.cgi';
      final res = await dio.get(
        path,
        options: Options(headers: {
          if (session.sessionCookie.isNotEmpty) 'Cookie': session.sessionCookie,
          if (session.csrfToken != null) 'X-Auth-Token': session.csrfToken!,
          'Accept': 'application/json',
          'Referer': '${session.baseUrl}/',
        }),
      );
      if (res.statusCode != 200) return null;
      if (session.airosVariant == 'v5') {
        return await _parseLegacy(
            (res.data ?? '').toString(), session, dio);
      }
      final data = res.data is Map
          ? Map<String, dynamic>.from(res.data)
          : (res.data is String
              ? jsonDecode(res.data) as Map<String, dynamic>
              : null);
      if (data == null) return null;
      return _parseStatus(data, session.baseUrl);
    } catch (_) {
      return null;
    }
  }

  /// واجهات تحمل حركة المشترك. `lo` مستثناة، والواجهات الافتراضيّة
  /// (vlan/tun) كذلك لأنّها تُضاعف نفس البايتات.
  static bool _isDataIface(String n) =>
      n.startsWith('eth') ||
      n.startsWith('ath') ||
      n.startsWith('wlan') ||
      n == 'br0';

  static UbiquitiStatus _parseStatus(Map<String, dynamic> j, String base) {
    final host = (j['host'] ?? const {}) as Map;
    final wireless = (j['wireless'] ?? const {}) as Map;
    final interfaces = (j['interfaces'] ?? const []) as List;
    final lanPorts = <LanPort>[];
    // عدّادات البايت: نجمع واجهات البيانات كلّها لا منافذ eth وحدها،
    // فالحركة على CPE قد تمرّ على ath0 أو br0 حسب الوضع.
    int? rxTotal;
    int? txTotal;
    for (final iface in interfaces) {
      if (iface is! Map) continue;
      final name = (iface['ifname'] ?? '').toString().toLowerCase();
      final st = iface['status'] as Map?;
      if (_isDataIface(name) && st != null) {
        final rx = _int(st['rx_bytes']);
        final tx = _int(st['tx_bytes']);
        if (rx != null) rxTotal = (rxTotal ?? 0) + rx;
        if (tx != null) txTotal = (txTotal ?? 0) + tx;
      }
      if (!name.startsWith('eth')) continue;
      final s = iface['status'] as Map?;
      final plugged = (s?['plugged'] == true) || (s?['plugged'] == 1);
      lanPorts.add(LanPort(
        name: name,
        speed: _buildLanSpeed(s),
        plugged: plugged,
      ));
    }
    final staList = wireless['sta'] as List?;
    final peerMac = (staList != null && staList.isNotEmpty)
        ? (staList.first as Map)['mac']?.toString()
        : null;
    return UbiquitiStatus(
      hostname: (host['hostname'] ?? '').toString(),
      firmware: (host['fwversion'] ?? '').toString(),
      uptimeSeconds: _int(host['uptime']),
      ssid: (wireless['essid'] ?? '').toString(),
      mode: (wireless['mode'] ?? '').toString(),
      signalDbm: _int(wireless['signal']),
      noiseFloorDbm: _int(wireless['noisef']),
      rxBytes: rxTotal,
      txBytes: txTotal,
      ccqPercent: _ccq(wireless['ccq']),
      distanceMeters: _int(wireless['distance']),
      txRateKbps: _rateToKbps(wireless['txrate']),
      rxRateKbps: _rateToKbps(wireless['rxrate']),
      lanPorts: lanPorts,
      peerMac: peerMac,
      peerCount: _int(wireless['count']),
      baseUrl: base,
    );
  }

  static int? _int(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is double) return v.round();
    return int.tryParse(v.toString());
  }

  static int? _ccq(dynamic v) {
    final raw = _int(v);
    if (raw == null) return null;
    return raw > 100 ? (raw / 10).round() : raw;
  }

  static int? _rateToKbps(dynamic v) {
    if (v == null) return null;
    final d = v is num ? v.toDouble() : double.tryParse(v.toString());
    if (d == null) return null;
    return d >= 1000 ? d.round() : (d * 1000).round();
  }

  static String? _buildLanSpeed(Map? s) {
    if (s == null) return null;
    final speed = _int(s['speed']);
    if (speed == null || speed == 0) return null;
    final duplex = s['duplex'];
    final duplexStr = duplex == 1
        ? '-Full'
        : duplex == 0
            ? '-Half'
            : '';
    return '${speed}Mbps$duplexStr';
  }
}
