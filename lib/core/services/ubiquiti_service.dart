import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';

import '../../models/ubiquiti_info.dart';

/// Ubiquiti airOS service — handles both airOS 6.x (NanoStation M2/M5 and
/// similar legacy gear) and airOS 8.x (newer firmware, AC-series). The two
/// variants use different login & status endpoints, so the service tries
/// v6 first (more common in the field) then falls back to v8.
///
/// Both endpoints return a JSON document whose keys we collapse into a
/// single [UbiquitiStatus] shape, independent of firmware version, so the
/// UI never has to branch.
class UbiquitiService {
  static Dio _buildDio(String baseUrl) {
    final dio = Dio(BaseOptions(
      baseUrl: baseUrl,
      // Keep per-request timeouts short so the 15s probe cap is not blown
      // through on unreachable HTTPS before we even try HTTP.
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

  /// Tries HTTPS first (default for airOS), then falls back to HTTP.
  static Future<UbiquitiLoginResult?> login(
      String host, String user, String pass) async {
    final bases = [
      'https://$host',
      'http://$host',
    ];

    for (final base in bases) {
      // Try v6.x first (simpler form POST)
      final v6 = await _tryLoginV6(base, user, pass);
      if (v6 != null) return v6;

      // Fall back to v8.x (JSON API)
      final v8 = await _tryLoginV8(base, user, pass);
      if (v8 != null) return v8;
    }
    return null;
  }

  // ── airOS 6.x ────────────────────────────────────────────────────────
  //   Most variants issue the session cookie on GET / (before the POST),
  //   but some firmware sets it only on the login.cgi 302 response, and
  //   some use cookie names that don't start with AIROS_. We handle all
  //   three cases: try GET / first, proceed without a cookie if none is
  //   found (some devices work without it), and also harvest any cookie
  //   that the login.cgi 302 response sets.
  static Future<UbiquitiLoginResult?> _tryLoginV6(
      String base, String user, String pass) async {
    final dio = _buildDio(base);
    try {
      // Step 1: GET / — grab whatever cookie the device offers.
      final rootRes = await dio.get('/');
      // Accept AIROS_* / SESSION by name; fall back to any cookie the
      // server sets in case this firmware uses a different naming scheme.
      String? cookie =
          _extractAirosCookie(rootRes) ?? _extractAnyCookie(rootRes);

      // Step 2: POST /login.cgi — send cookie if we got one; some variants
      // work without a pre-existing cookie and set it on the 302 response.
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
      // Successful login → 302 redirect to /index.cgi
      if (res.statusCode != 302) return null;
      final location = res.headers.value('location') ?? '';
      if (!location.contains('index')) return null;

      // Some firmware sets / refreshes the cookie on the login 302 response.
      cookie ??= _extractAirosCookie(res) ?? _extractAnyCookie(res);
      if (cookie == null) return null;

      // Step 3: Verify the cookie authenticates us.
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

  // ── airOS 8.x ────────────────────────────────────────────────────────
  //   POST /api/auth
  //     Content-Type: application/json
  //     Body: {"username":"<u>","password":"<p>"}
  //   → Set-Cookie: AIROS_... + X-Auth-Token header
  //   Success if GET /api/status returns a JSON body.
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
    if (data is Map) return data.containsKey('wireless') || data.containsKey('host');
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
      if (nameVal.toUpperCase().startsWith('AIROS_') || nameVal.contains('SESSION')) {
        parts.add(nameVal);
      }
    }
    return parts.isEmpty ? null : parts.join('; ');
  }

  /// Fallback: grab every Set-Cookie value regardless of name.
  /// Used when the device firmware uses a non-standard cookie name.
  static String? _extractAnyCookie(Response res) {
    final raw = res.headers.map['set-cookie'] ?? const [];
    final parts = <String>[];
    for (final line in raw) {
      final nameVal = line.split(';').first.trim();
      if (nameVal.contains('=')) parts.add(nameVal);
    }
    return parts.isEmpty ? null : parts.join('; ');
  }

  // ── Status fetch ─────────────────────────────────────────────────────
  static Future<UbiquitiStatus?> fetchStatus(UbiquitiLoginResult session) async {
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

  /// Both v6 and v8 return roughly the same JSON tree:
  ///   { "host": {...}, "wireless": {...}, "interfaces": [...] }
  /// Field names are stable across versions.
  static UbiquitiStatus _parseStatus(Map<String, dynamic> j, String base) {
    final host = (j['host'] ?? const {}) as Map;
    final wireless = (j['wireless'] ?? const {}) as Map;
    final interfaces = (j['interfaces'] ?? const []) as List;

    // Collect ALL eth interfaces as LanPort entries.
    final lanPorts = <LanPort>[];
    for (final iface in interfaces) {
      if (iface is! Map) continue;
      final name = (iface['ifname'] ?? '').toString().toLowerCase();
      if (!name.startsWith('eth')) continue;
      final s = iface['status'] as Map?;
      final plugged = (s?['plugged'] == true) || (s?['plugged'] == 1);
      lanPorts.add(LanPort(
        name: name,
        speed: _buildLanSpeed(s),
        plugged: plugged,
      ));
    }

    // `sta` is present when wireless mode is station; `num_sta` in AP mode.
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

  // CCQ is 0–1000 in airOS JSON (1000 = 100%). Normalise to 0–100.
  static int? _ccq(dynamic v) {
    final raw = _int(v);
    if (raw == null) return null;
    return raw > 100 ? (raw / 10).round() : raw;
  }

  // TX/RX rates may be kbps integers (older) or Mbps strings like "19.5".
  // Normalise everything to kbps.
  static int? _rateToKbps(dynamic v) {
    if (v == null) return null;
    final d = v is num ? v.toDouble() : double.tryParse(v.toString());
    if (d == null) return null;
    return d >= 1000 ? d.round() : (d * 1000).round();
  }

  // Build a human-readable LAN speed string from the integer speed + duplex.
  // e.g. speed=100, duplex=1  →  "100Mbps-Full"
  static String? _buildLanSpeed(Map? s) {
    if (s == null) return null;
    final speed = _int(s['speed']);
    if (speed == null || speed == 0) return null;
    final duplex = s['duplex'];
    final duplexStr = duplex == 1 ? '-Full' : duplex == 0 ? '-Half' : '';
    return '${speed}Mbps$duplexStr';
  }
}
