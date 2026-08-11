import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';

/// UBNT airOS HTTP client — يدعم airOS 6 (XM قديم) و 8 (حديث).
/// حسب بحث Home Assistant integration الرسمي (CoMPaTech/python-airos).
///
/// **auth flow**:
/// - airOS 8: POST /api/auth JSON → cookie AIROS_*
/// - airOS 6: GET /login.cgi → POST /login.cgi form → GET /index.cgi
///
/// نجرّب v8 أوّلاً، لو 404 نستعمل v6.
///
/// **HTTPS**: UBNT يستعمل self-signed certificate — نتجاهله (LAN فقط).
class UbntApi {
  static Future<UbntStats> fetchStats({
    required String ip,
    int port = 443,
    required String user,
    required String pass,
    bool useHttps = true,
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final scheme = useHttps ? 'https' : 'http';
    final baseUrl = '$scheme://$ip:$port';
    final dio = _createDio(baseUrl, timeout);

    String? cookie;
    int apiVersion = 8;

    // 1) جرّب airOS 8 login (POST /api/auth)
    try {
      final r = await dio.post(
        '/api/auth',
        data: {'username': user, 'password': pass},
        options: Options(
          contentType: Headers.jsonContentType,
          followRedirects: false,  // ما نتبع redirects حتى نفحص الـcookie
          validateStatus: (s) => s != null && s < 500,
        ),
      );
      // 200 = airOS 8 نجاح مباشر
      if (r.statusCode == 200) {
        cookie = _extractAirosCookie(r.headers);
        if (cookie == null) {
          throw UbntException('لم يرجع الراوتر cookie صالح — تحقّق من user/pass');
        }
      }
      // 302 = airOS 8 قديم أو مسار مختلف — لو معه cookie نجاح، وإلا نجرّب v6
      else if (r.statusCode == 302) {
        final maybeCookie = _extractAirosCookie(r.headers);
        if (maybeCookie != null) {
          cookie = maybeCookie;
        } else {
          apiVersion = 6;
          cookie = await _loginV6(dio, baseUrl, user, pass);
        }
      } else if (r.statusCode == 401 || r.statusCode == 403) {
        throw UbntException('اسم المستخدم أو كلمة المرور خطأ');
      } else if (r.statusCode == 404) {
        apiVersion = 6;
        cookie = await _loginV6(dio, baseUrl, user, pass);
      } else {
        // أي رمز آخر — نجرّب v6 كـfallback
        apiVersion = 6;
        cookie = await _loginV6(dio, baseUrl, user, pass);
      }
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        apiVersion = 6;
        cookie = await _loginV6(dio, baseUrl, user, pass);
      } else {
        _throwDio(e);
      }
    }

    if (cookie == null) throw UbntException('فشل تسجيل الدخول');

    // 2) اجلب status
    try {
      final r = await dio.get(
        '/status.cgi',
        options: Options(
          headers: {'Cookie': cookie},
          responseType: ResponseType.plain,   // نستقبل نصّاً ثم نُحلّل
          followRedirects: false,
          validateStatus: (s) => s != null && s < 500,
        ),
      );
      if (r.statusCode == 302 || r.statusCode == 401 || r.statusCode == 403) {
        throw UbntException(
          'الجلسة انتهت أو غير مصرّح — تحقّق من user/pass وصلاحيّة القراءة',
        );
      }
      if (r.statusCode != 200) {
        throw UbntException('/status.cgi رجع ${r.statusCode}');
      }
      final raw = (r.data ?? '').toString().trim();
      if (raw.isEmpty) {
        throw UbntException('استجابة فارغة من /status.cgi');
      }
      // لو الردّ HTML بدل JSON (يحدث لو الـcookie انتهت)
      if (raw.startsWith('<')) {
        throw UbntException('الجهاز رجع HTML بدل JSON — الجلسة انتهت أو الحساب بلا صلاحيّة');
      }
      final decoded = json.decode(raw);
      if (decoded is! Map<String, dynamic>) {
        throw UbntException('صيغة الردّ غير متوقّعة');
      }
      return UbntStats.fromJson(decoded, apiVersion: apiVersion);
    } on FormatException {
      throw UbntException('فشل تحليل JSON من الجهاز');
    } on DioException catch (e) {
      _throwDio(e);
      rethrow;
    }
  }

  // ═══════════════════════════════════════════════════════════
  // Helpers
  // ═══════════════════════════════════════════════════════════

  static Dio _createDio(String baseUrl, Duration timeout) {
    final dio = Dio(BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: timeout,
      receiveTimeout: timeout,
      validateStatus: (s) => s != null && s < 500,
    ));
    // تجاهل self-signed certificate errors — LAN فقط
    (dio.httpClientAdapter as IOHttpClientAdapter).createHttpClient = () {
      return HttpClient()
        ..badCertificateCallback = (X509Certificate cert, String host, int port) => true;
    };
    return dio;
  }

  /// يستخرج كل الـcookies من Set-Cookie، يُعطي أولوية لـAIROS ثمّ AIROS_
  /// ثمّ أي cookie يبدو مثل session (PHPSESSID/session/id).
  static String? _extractAirosCookie(Headers headers) {
    final setCookies = headers.map['set-cookie'] ?? const [];
    if (setCookies.isEmpty) return null;
    // اجمع كل الـcookies المرسلة
    final cookies = <String>[];
    for (final raw in setCookies) {
      // خذ الجزء قبل أوّل ";" (name=value فقط، بدون attributes)
      final semi = raw.indexOf(';');
      final nameVal = (semi > 0 ? raw.substring(0, semi) : raw).trim();
      if (nameVal.contains('=') && !nameVal.startsWith('=')) {
        cookies.add(nameVal);
      }
    }
    if (cookies.isEmpty) return null;

    // أولوية لـAIROS
    final airos = cookies.where((c) =>
        c.toUpperCase().startsWith('AIROS')).toList();
    if (airos.isNotEmpty) return airos.join('; ');

    // fallback: أي session cookie (PHPSESSID, JSESSIONID, session, id)
    final session = cookies.where((c) {
      final name = c.split('=').first.toLowerCase();
      return name.contains('sess') || name == 'id' || name.startsWith('ui-');
    }).toList();
    if (session.isNotEmpty) return session.join('; ');

    // أخير: كل الـcookies (بعض إصدارات airOS تستعمل أسماء مخصّصة)
    return cookies.join('; ');
  }

  /// airOS 6 login flow (XM devices).
  /// 3 خطوات: get cookie → post login → activate.
  /// نتتبّع الـcookie في كل خطوة لأن airOS 6 قد يجدّده بعد POST.
  static Future<String?> _loginV6(
    Dio dio, String baseUrl, String user, String pass,
  ) async {
    try {
      // Step 1: GET /login.cgi → session cookie
      final r1 = await dio.get(
        '/login.cgi',
        options: Options(
          followRedirects: false,
          validateStatus: (s) => s != null && s < 500,
        ),
      );
      String? cookie = _extractAirosCookie(r1.headers);
      // بعض الأجهزة ما تُصدر cookie قبل POST — نستمرّ بدون
      if (kDebugMode) debugPrint('🔵 UBNT v6 step1 cookie: ${cookie ?? "(none)"}');

      // Step 2: POST /login.cgi → 302 (قد يُجدّد الـcookie هنا)
      final r2 = await dio.post(
        '/login.cgi',
        data: {
          'username': user,
          'password': pass,
          'uri': '/index.cgi',
        },
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          headers: {
            if (cookie != null) 'Cookie': cookie,
            'Referer': '$baseUrl/login.cgi',
            'Origin': baseUrl,
          },
          followRedirects: false,
          validateStatus: (s) => s != null && s < 500,
        ),
      );

      // نتحقّق من status: 302 = نجاح (redirect لـ/index.cgi)
      // 200 مع HTML قد يعني إعادة عرض login page (فشل)
      final newCookie = _extractAirosCookie(r2.headers);
      if (newCookie != null) {
        cookie = newCookie;
        if (kDebugMode) debugPrint('🔵 UBNT v6 step2 new cookie: $cookie');
      }
      if (r2.statusCode != 302) {
        // بعض الإصدارات ترجع 200 عند النجاح — نتحقّق من الـLocation header
        final loc = r2.headers.value('location');
        if (r2.statusCode == 200 && loc == null) {
          throw UbntException('airOS 6: user/pass خطأ (لم نحصل على redirect)');
        }
      }
      if (cookie == null) {
        throw UbntException('airOS 6: لم نستلم session cookie بعد login');
      }

      // Step 3: GET /index.cgi لتفعيل الجلسة (يجب أن نرى صفحة index، ليس login)
      final r3 = await dio.get(
        '/index.cgi',
        options: Options(
          headers: {'Cookie': cookie, 'Referer': '$baseUrl/login.cgi'},
          followRedirects: false,
          validateStatus: (s) => s != null && s < 500,
        ),
      );
      // لو رجعنا redirect لـ/login.cgi → session لم تُفعَّل
      final loc3 = r3.headers.value('location') ?? '';
      if (loc3.contains('login.cgi')) {
        throw UbntException('airOS 6: user/pass خطأ (session ما اتفعّلت)');
      }
      // قد يُصدر cookie جديد في هذه الخطوة
      final finalCookie = _extractAirosCookie(r3.headers);
      if (finalCookie != null) {
        cookie = finalCookie;
        if (kDebugMode) debugPrint('🔵 UBNT v6 step3 final cookie: $cookie');
      }

      return cookie;
    } on DioException catch (e) {
      _throwDio(e);
      return null;
    }
  }

  static Never _throwDio(DioException e) {
    if (kDebugMode) debugPrint('❌ UbntApi: ${e.message}');
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout) {
      throw UbntException('انتهت مهلة الاتصال — تأكّد أنك على شبكة الجهاز');
    }
    if (e.error is SocketException) {
      throw UbntException('الجهاز غير قابل للوصول (شبكة)');
    }
    if (e.response?.statusCode == 401 || e.response?.statusCode == 403) {
      throw UbntException('اسم المستخدم أو كلمة المرور خطأ');
    }
    throw UbntException('فشل الاتصال: ${e.message ?? "غير معروف"}');
  }
}

class UbntException implements Exception {
  final String message;
  UbntException(this.message);
  @override
  String toString() => message;
}

// ═══════════════════════════════════════════════════════════
// Models
// ═══════════════════════════════════════════════════════════

class UbntStats {
  final int apiVersion;                       // 6 or 8
  final UbntHost host;
  final UbntWireless? wireless;
  final List<UbntInterface> interfaces;
  final List<UbntStation> stations;

  const UbntStats({
    required this.apiVersion,
    required this.host,
    this.wireless,
    this.interfaces = const [],
    this.stations = const [],
  });

  bool get isAp => wireless?.mode.startsWith('ap-') ?? false;
  bool get isStation => wireless?.mode.startsWith('sta-') ?? false;
  bool get isPtp => wireless?.mode.endsWith('-ptp') ?? false;
  bool get isPtmp => wireless?.mode.endsWith('-ptmp') ?? false;

  factory UbntStats.fromJson(Map<String, dynamic> j, {required int apiVersion}) {
    final hostJ = (j['host'] as Map?)?.cast<String, dynamic>() ?? const {};
    final wJ = (j['wireless'] as Map?)?.cast<String, dynamic>();
    final ifaces = (j['interfaces'] as List?) ?? const [];

    // stations قد يكون داخل wireless['sta'] (AP mode)
    final sta = wJ != null ? (wJ['sta'] as List? ?? const []) : const [];

    return UbntStats(
      apiVersion: apiVersion,
      host: UbntHost.fromJson(hostJ),
      wireless: wJ != null ? UbntWireless.fromJson(wJ) : null,
      interfaces: ifaces
          .whereType<Map>()
          .map((m) => UbntInterface.fromJson(m.cast<String, dynamic>()))
          .toList(),
      stations: sta
          .whereType<Map>()
          .map((m) => UbntStation.fromJson(m.cast<String, dynamic>()))
          .toList(),
    );
  }
}

class UbntHost {
  final String hostname;
  final String devmodel;         // e.g. "PBE-5AC-500"
  final String fwversion;        // e.g. "8.7.11"
  final int uptime;              // seconds
  final int cpuload;             // %
  final int temperature;         // °C (قد يكون null على بعض الأجهزة)

  const UbntHost({
    required this.hostname,
    required this.devmodel,
    required this.fwversion,
    required this.uptime,
    required this.cpuload,
    required this.temperature,
  });

  factory UbntHost.fromJson(Map<String, dynamic> j) => UbntHost(
        hostname: (j['hostname'] ?? '').toString(),
        devmodel: (j['devmodel'] ?? '').toString(),
        fwversion: (j['fwversion'] ?? '').toString(),
        uptime: _n(j['uptime']),
        cpuload: _n(j['cpuload']),
        temperature: _n(j['temperature']),
      );
}

class UbntWireless {
  final String essid;
  final String mode;             // sta-ptp/ap-ptp/sta-ptmp/ap-ptmp
  final int signal;              // dBm
  final int noise;               // dBm (noisef in JSON)
  final int ccq;                 // %
  final int txRate;              // Mbps
  final int rxRate;              // Mbps
  final int channel;
  final int frequency;           // MHz
  final int distance;            // meters
  final int chanbw;              // channel width MHz

  const UbntWireless({
    required this.essid,
    required this.mode,
    required this.signal,
    required this.noise,
    required this.ccq,
    required this.txRate,
    required this.rxRate,
    required this.channel,
    required this.frequency,
    required this.distance,
    required this.chanbw,
  });

  /// Signal-to-Noise Ratio (dB) — أهمّ مقياس جودة الإشارة
  int get snr => (signal - noise).abs();

  /// جودة الإشارة (كنسبة %) — للـgauge
  /// -40 dBm ممتاز (100%) / -95 dBm سيّئ جداً (0%)
  double get signalQualityPercent {
    if (signal >= -40) return 100.0;
    if (signal <= -95) return 0.0;
    return ((-40.0 - signal.abs().toDouble()) / 55.0 * 100 + 100).clamp(0, 100);
  }

  factory UbntWireless.fromJson(Map<String, dynamic> j) => UbntWireless(
        essid: (j['essid'] ?? '').toString(),
        mode: (j['mode'] ?? '').toString(),
        signal: _n(j['signal']),
        noise: _n(j['noisef']),
        ccq: _n(j['ccq']),
        txRate: _n(j['txrate']),
        rxRate: _n(j['rxrate']),
        channel: _n(j['channel']),
        frequency: _n(j['frequency']),
        distance: _n(j['distance']),
        chanbw: _n(j['chanbw']),
      );
}

class UbntInterface {
  final String ifname;
  final String hwaddr;
  final bool enabled;
  final bool plugged;
  final int? rxBytes;
  final int? txBytes;
  final int? speed;              // Mbps
  final bool duplex;

  const UbntInterface({
    required this.ifname,
    required this.hwaddr,
    required this.enabled,
    required this.plugged,
    this.rxBytes,
    this.txBytes,
    this.speed,
    this.duplex = false,
  });

  factory UbntInterface.fromJson(Map<String, dynamic> j) {
    final s = (j['status'] as Map?)?.cast<String, dynamic>() ?? const {};
    return UbntInterface(
      ifname: (j['ifname'] ?? '').toString(),
      hwaddr: (j['hwaddr'] ?? '').toString(),
      enabled: j['enabled'] == true || j['enabled'] == 1,
      plugged: s['plugged'] == true || s['plugged'] == 1,
      rxBytes: s['rx_bytes'] is int ? s['rx_bytes'] : int.tryParse('${s['rx_bytes']}'),
      txBytes: s['tx_bytes'] is int ? s['tx_bytes'] : int.tryParse('${s['tx_bytes']}'),
      speed: s['speed'] is int ? s['speed'] : int.tryParse('${s['speed']}'),
      duplex: s['duplex'] == true || s['duplex'] == 1,
    );
  }
}

class UbntStation {
  final String mac;
  final String? ip;
  final String? hostname;
  final int signal;
  final int noise;
  final int ccq;
  final int txRate;
  final int rxRate;
  final int connTime;            // seconds

  const UbntStation({
    required this.mac,
    this.ip,
    this.hostname,
    required this.signal,
    required this.noise,
    required this.ccq,
    required this.txRate,
    required this.rxRate,
    required this.connTime,
  });

  int get snr => (signal - noise).abs();

  factory UbntStation.fromJson(Map<String, dynamic> j) {
    // remote قد تكون داخل j أو داخل j['remote']
    final remote = (j['remote'] as Map?)?.cast<String, dynamic>() ?? const {};
    return UbntStation(
      mac: (j['mac'] ?? '').toString(),
      ip: (j['lastip'] ?? remote['ip'] ?? '').toString().isEmpty ? null
          : (j['lastip'] ?? remote['ip']).toString(),
      hostname: (j['name'] ?? remote['hostname'] ?? '').toString().isEmpty ? null
          : (j['name'] ?? remote['hostname']).toString(),
      signal: _n(j['signal']),
      noise: _n(j['noisefloor']),
      ccq: _n(j['ccq']),
      txRate: _n(j['tx']),
      rxRate: _n(j['rx']),
      connTime: _n(j['uptime'] ?? j['conn_time']),
    );
  }
}

// ── Utilities
int _n(dynamic v) {
  if (v == null) return 0;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString()) ?? 0;
}
