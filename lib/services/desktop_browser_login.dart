import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/api_client.dart';

/// «الدخول عبر المتصفّح» لنسخة ويندوز — نمط التطبيقات المكتبيّة (RFC 8252).
///
/// ١) البرنامج يستمع على 127.0.0.1 بمنفذٍ عشوائيّ ويولّد سرّاً (PKCE) لا يغادره.
/// ٢) يفتح `/v2/desktop-login` في متصفّح الجهاز؛ المستخدم يدخل هناك بحسابه (Google أو إيميل).
/// ٣) الموقع يأخذ من الخادم رمزاً لمرّةٍ واحدة (دقيقتان) ويعيده إلى 127.0.0.1 — أي إلى هذا
///    الجهاز وحده، فرابطٌ مرسَلٌ لغيره لا يوصل الرمز لأحد.
/// ٤) البرنامج يبدّل الرمز + سرّه بتوكنٍ مخصّص لنفس الحساب ([DesktopAccountAuth.signInWithCustomToken]).
///
/// لماذا لا نافذة Google داخل البرنامج: Google يمنع الدخول من WebView مضمَّن، ولا مكتبة Google
/// لويندوز في فلاتر.
class DesktopBrowserLogin {
  DesktopBrowserLogin({this.timeout = const Duration(minutes: 5)});

  final Duration timeout;

  @visibleForTesting
  static Future<bool> Function(Uri url) openUrl =
      (url) => launchUrl(url, mode: LaunchMode.externalApplication);

  @visibleForTesting
  static Dio? debugDio;

  HttpServer? _server;
  Completer<String?>? _code;
  Uri? _pageUrl;

  /// رابط الصفحة المفتوحة (لزرّ «افتح الصفحة مرّةً أخرى»).
  Uri? get pageUrl => _pageUrl;

  /// يُرجع التوكن المخصّص، أو null إن أُلغي/انتهت المهلة. يرمي [DesktopLoginException] برسالةٍ
  /// جاهزة عند رفض الخادم.
  Future<String?> run() async {
    final state = _random(24);
    final verifier = _random(48);
    final challenge = _challengeOf(verifier);
    final code = Completer<String?>();
    _code = code;

    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server = server;
    unawaited(server.forEach((req) => _handle(req, state, code)).catchError((_) {}));

    _pageUrl = Uri.parse('${ApiClient.baseUrl}/v2/desktop-login').replace(queryParameters: {
      'port': '${server.port}',
      'state': state,
      'challenge': challenge,
    });
    try {
      await openUrl(_pageUrl!);
      final got = await code.future.timeout(timeout, onTimeout: () => null);
      if (got == null) return null;
      return await _exchange(got, verifier);
    } finally {
      await close();
    }
  }

  /// يفتح الصفحة ثانيةً (أغلقها المستخدم بالخطأ).
  Future<void> reopen() async {
    final u = _pageUrl;
    if (u != null) await openUrl(u);
  }

  /// إلغاءٌ من البرنامج.
  void cancel() {
    final c = _code;
    if (c != null && !c.isCompleted) c.complete(null);
  }

  Future<void> close() async {
    cancel();
    final s = _server;
    _server = null;
    if (s != null) await s.close(force: true);
  }

  Future<void> _handle(HttpRequest req, String state, Completer<String?> done) async {
    final q = req.uri.queryParameters;
    final ok = req.method == 'GET' &&
        req.uri.path == '/callback' &&
        q['state'] == state &&
        (q['code'] ?? '').length >= 16;
    req.response
      ..statusCode = ok ? HttpStatus.ok : HttpStatus.badRequest
      ..headers.contentType = ContentType.html
      ..headers.set('Cache-Control', 'no-store')
      ..write(ok ? _donePage : _badPage);
    await req.response.close();
    if (ok && !done.isCompleted) done.complete(q['code']);
  }

  Future<String?> _exchange(String code, String verifier) async {
    final dio = debugDio ??
        Dio(BaseOptions(
          baseUrl: ApiClient.baseUrl,
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 20),
          validateStatus: (_) => true,
        ));
    final Response<Object?> r;
    try {
      r = await dio.post<Object?>('/api/account/desktop-login/token',
          data: {'code': code, 'verifier': verifier});
    } on DioException {
      throw const DesktopLoginException('account.err_network');
    }
    final body = r.data;
    if (r.statusCode == 200 && body is Map && body['token'] is String) {
      return body['token'] as String;
    }
    throw DesktopLoginException(
        body is Map && body['message'] is String ? body['message'] as String : 'account.err_generic');
  }

  static String _random(int bytes) {
    final rnd = Random.secure();
    return base64Url
        .encode(List<int>.generate(bytes, (_) => rnd.nextInt(256)))
        .replaceAll('=', '');
  }

  @visibleForTesting
  static String challengeOf(String verifier) => _challengeOf(verifier);

  static String _challengeOf(String verifier) =>
      base64Url.encode(sha256.convert(utf8.encode(verifier)).bytes).replaceAll('=', '');

  static const _donePage = '<!doctype html><html lang="ar" dir="rtl"><head><meta charset="utf-8">'
      '<title>MyServices Pro</title><style>body{font-family:system-ui,Segoe UI,Tahoma,sans-serif;'
      'background:#F4F5F2;color:#121614;display:flex;align-items:center;justify-content:center;'
      'height:100vh;margin:0}div{background:#fff;border-radius:20px;padding:32px 40px;'
      'box-shadow:0 2px 12px rgba(0,0,0,.06);text-align:center}h1{color:#103D2E;font-size:22px;'
      'margin:0 0 8px}p{margin:0;color:#4a524e}</style></head><body><div><h1>تمّ تسجيل الدخول ✓</h1>'
      '<p>ارجع إلى برنامج MyServices Pro — يمكنك إغلاق هذه الصفحة.</p></div></body></html>';

  static const _badPage = '<!doctype html><html lang="ar" dir="rtl"><head><meta charset="utf-8">'
      '<title>MyServices Pro</title></head><body style="font-family:system-ui,Segoe UI,Tahoma,sans-serif">'
      '<p>رابطٌ غير صالح — ابدأ الدخول من البرنامج مرّةً أخرى.</p></body></html>';
}

/// رفض الخادم تبديل الرمز. [message] مفتاح ترجمة (`account.*`) أو نصّ الخادم العربيّ.
class DesktopLoginException implements Exception {
  const DesktopLoginException(this.message);
  final String message;

  @override
  String toString() => message;
}
