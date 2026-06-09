import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';

import '../../models/device_health.dart';

/// Direct port of mobile-app/lib/core/services/huawei_ont_service.dart —
/// keeps the same login flow, base URL fallback order, and HTML
/// parsing so behavior matches v1 1:1.
class HuaweiOntService {
  static Dio _buildDio(String baseUrl) {
    final dio = Dio(BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 4),
      receiveTimeout: const Duration(seconds: 4),
      validateStatus: (_) => true,
      followRedirects: false,
      headers: {'Accept': 'text/html,application/xhtml+xml,*/*'},
    ));
    (dio.httpClientAdapter as IOHttpClientAdapter).createHttpClient = () {
      final c = HttpClient();
      c.badCertificateCallback = (_, __, ___) => true;
      return c;
    };
    return dio;
  }

  static Future<OntLoginResult?> login(
      String host, String user, String pass) async {
    final bases = [
      'https://$host:80',
      'https://$host:443',
      'https://$host',
      'http://$host',
    ];
    for (final base in bases) {
      final result = await _tryLogin(base, user, pass);
      if (result != null) return result;
    }
    return null;
  }

  static Future<OntLoginResult?> _tryLogin(
      String base, String user, String pass) async {
    final dio = _buildDio(base);
    try {
      await dio.get('/');
      final tokRes = await dio.post(
        '/asp/GetRandCount.asp',
        data: '',
        options: Options(headers: {'Referer': '$base/'}),
      );
      final raw = (tokRes.data ?? '').toString().trim();
      final m = RegExp(r'[0-9a-fA-F]{16,}').firstMatch(raw);
      final token = m?.group(0);
      if (token == null) return null;

      final b64Pass = base64Encode(utf8.encode(pass));
      final body = 'UserName=${Uri.encodeQueryComponent(user)}'
          '&PassWord=${Uri.encodeQueryComponent(b64Pass)}'
          '&x.X_HW_Token=${Uri.encodeQueryComponent(token)}';
      final res = await dio.post(
        '/login.cgi',
        data: body,
        options: Options(headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
          'Origin': base,
          'Referer': '$base/',
          'Cookie': 'Cookie=body:Language:english:id=-1',
        }),
      );

      final sessionCookie = _extractSid(res);
      final bodyStr = (res.data ?? '').toString();
      final success =
          bodyStr.contains("pageName = 'index.asp'") && sessionCookie != null;
      if (!success) return null;
      return OntLoginResult(sessionCookie: sessionCookie, baseUrl: base);
    } catch (_) {
      return null;
    }
  }

  static String? _extractSid(Response res) {
    final raw = res.headers.map['set-cookie'] ?? const [];
    for (final line in raw) {
      final nameVal = line.split(';').first;
      final eq = nameVal.indexOf('=');
      if (eq > 0) {
        final name = nameVal.substring(0, eq).trim();
        final val = nameVal.substring(eq + 1).trim();
        if (name == 'Cookie' && val.contains('sid=')) {
          return '$name=$val';
        }
      }
    }
    return null;
  }

  static Future<OntOpticalInfo?> fetchOptical(OntLoginResult session) async {
    final dio = _buildDio(session.baseUrl);
    try {
      final res = await dio.get(
        '/html/amp/opticinfo/opticinfo.asp',
        options: Options(headers: {
          'Cookie': session.sessionCookie,
          'Referer': '${session.baseUrl}/index.asp',
        }),
      );
      return _parseOptical((res.data ?? '').toString());
    } catch (_) {
      return null;
    }
  }

  static String _unescapeJs(String s) {
    return s.replaceAllMapped(
      RegExp(r'\\x([0-9a-fA-F]{2})'),
      (m) => String.fromCharCode(int.parse(m.group(1)!, radix: 16)),
    );
  }

  static OntOpticalInfo? _parseOptical(String html) {
    final m = RegExp(
      r'new stOpticInfo\s*\(\s*"[^"]*"\s*,\s*"([^"]*)"\s*,\s*"([^"]*)"\s*,\s*"([^"]*)"\s*,\s*"([^"]*)"\s*,\s*"([^"]*)"',
    ).firstMatch(html);
    if (m == null) return null;
    final ssm = RegExp(r'new stSendStatus\s*\(\s*"([^"]*)"').firstMatch(html);
    return OntOpticalInfo(
      txPower: _unescapeJs(m.group(1)!).trim(),
      rxPower: _unescapeJs(m.group(2)!).trim(),
      voltage: _unescapeJs(m.group(3)!).trim(),
      temperature: _unescapeJs(m.group(4)!).trim(),
      bias: _unescapeJs(m.group(5)!).trim(),
      sendStatus: _unescapeJs(ssm?.group(1) ?? '--').trim(),
    );
  }
}
