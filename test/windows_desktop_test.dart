import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart' show FirebaseAuthException;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/core/platform/app_platform.dart';
import 'package:rad_mysvcs/services/account_service.dart';
import 'package:rad_mysvcs/services/desktop_account_auth.dart';
import 'package:rad_mysvcs/services/desktop_browser_login.dart';

/// نسخة ويندوز: الدخول عبر واجهة Firebase على الإنترنت + «الدخول عبر المتصفّح» + ملصق الجهاز.
/// تجري على أيّ جهاز (AppPlatform.debugIsDesktop)، بلا شبكة إلّا 127.0.0.1.

String _jwt(Map<String, Object?> claims) {
  String part(Object o) => base64Url.encode(utf8.encode(jsonEncode(o))).replaceAll('=', '');
  return '${part({'alg': 'RS256'})}.${part(claims)}.c2ln';
}

Map<String, Object?> _claims({
  String uid = 'uid-1',
  String email = 'owner@example.com',
  bool verified = true,
  Map<String, Object?> identities = const {'google.com': ['1'], 'email': ['owner@example.com']},
}) =>
    {
      'user_id': uid,
      'sub': uid,
      'email': email,
      'email_verified': verified,
      'name': 'Owner',
      'firebase': {'identities': identities, 'sign_in_provider': 'custom'},
    };

class _Fake implements HttpClientAdapter {
  _Fake(this.handler);
  final ({int status, Object body}) Function(RequestOptions o) handler;
  final calls = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
      RequestOptions o, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    calls.add(o);
    final r = handler(o);
    return ResponseBody.fromString(jsonEncode(r.body), r.status, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}

Dio _dio(_Fake fake) => Dio(BaseOptions(validateStatus: (_) => true))..httpClientAdapter = fake;

void main() {
  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    AppPlatform.debugIsDesktop = true;
    await DesktopAccountAuth.signOut();
  });
  tearDown(() {
    AppPlatform.debugIsDesktop = null;
    DesktopAccountAuth.debugDio = null;
    DesktopBrowserLogin.debugDio = null;
  });

  group('ملصق الجهاز', () {
    test('ويندوز يُرسل windows', () {
      expect(AppPlatform.deviceLabel, 'windows');
    });
    test('غير ويندوز كما كان (أندرويد على جهاز الاختبار)', () {
      AppPlatform.debugIsDesktop = false;
      expect(AppPlatform.deviceLabel, 'android');
    });
  });

  group('توكن الهويّة ⇒ الحساب', () {
    test('Google: مزوّدٌ مؤكَّد والبريد مؤكَّد', () {
      final u = DesktopAccountAuth.userFromIdToken(_jwt(_claims()))!;
      expect(u.uid, 'uid-1');
      expect(u.email, 'owner@example.com');
      expect(u.emailVerified, isTrue);
      expect(u.providerIds, containsAll(['google.com', 'password']));
      expect(u.isFederated, isTrue);
    });
    test('إيميل غير مؤكَّد', () {
      final u = DesktopAccountAuth.userFromIdToken(
          _jwt(_claims(verified: false, identities: {'email': ['a@b.c']})))!;
      expect(u.isFederated, isFalse);
      expect(u.emailVerified, isFalse);
    });
    test('توكنٌ تالف ⇒ null', () {
      expect(DesktopAccountAuth.userFromIdToken('not-a-jwt'), isNull);
    });
  });

  group('رموز الأخطاء = رموز الهاتف', () {
    final cases = {
      'INVALID_LOGIN_CREDENTIALS': 'invalid-credential',
      'EMAIL_NOT_FOUND': 'invalid-credential',
      'INVALID_PASSWORD': 'invalid-credential',
      'USER_DISABLED': 'user-disabled',
      'EMAIL_EXISTS': 'email-already-in-use',
      'WEAK_PASSWORD : Password should be at least 6 characters': 'weak-password',
      'TOO_MANY_ATTEMPTS_TRY_LATER : Access to this account has been temporarily disabled':
          'too-many-requests',
      'INVALID_EMAIL': 'invalid-email',
    };
    cases.forEach((raw, code) {
      test(raw.split(' ').first, () => expect(DesktopAccountAuth.mapError(raw), code));
    });
  });

  group('الدخول بالإيميل', () {
    test('ينجح، يُحفظ، ويُستعاد بعد إعادة التشغيل', () async {
      final fake = _Fake((o) {
        expect(o.uri.toString(), contains('accounts:signInWithPassword'));
        expect(o.data['email'], 'owner@example.com');
        return (status: 200, body: {
          'idToken': _jwt(_claims(identities: {'email': ['owner@example.com']})),
          'refreshToken': 'r-1',
          'expiresIn': '3600',
        });
      });
      DesktopAccountAuth.debugDio = _dio(fake);
      final u = await AccountService.signInWithEmail(' owner@example.com ', 'pw');
      expect(u?.uid, 'uid-1');
      expect(AccountService.isReady, isTrue);
      expect(await AccountService.idToken(), isNotNull);
      expect(fake.calls, hasLength(1)); // التوكن صالحٌ ساعة ⇒ لا تجديد

      // «إعادة تشغيل»: الذاكرة تُمسح والتخزين باقٍ.
      final saved = await const FlutterSecureStorage().read(key: 'account.desktop.v1');
      expect(saved, isNotNull);
      DesktopAccountAuth.user.value = null;
      await DesktopAccountAuth.restore();
      expect(AccountService.currentUser?.email, 'owner@example.com');
    });

    test('كلمة سرّ خاطئة ⇒ نفس رمز الهاتف', () async {
      DesktopAccountAuth.debugDio = _dio(_Fake((o) => (
            status: 400,
            body: {
              'error': {'code': 400, 'message': 'INVALID_LOGIN_CREDENTIALS'}
            }
          )));
      expect(
        () => AccountService.signInWithEmail('x@y.z', 'bad'),
        throwsA(isA<FirebaseAuthException>()
            .having((e) => e.code, 'code', 'invalid-credential')),
      );
      expect(AccountService.messageFor(FirebaseAuthException(code: 'invalid-credential')),
          'account.err_wrong_credentials');
    });
  });

  group('تجديد التوكن', () {
    Future<void> signIn(int expiresIn) async {
      DesktopAccountAuth.debugDio = _dio(_Fake((o) => (
            status: 200,
            body: {'idToken': _jwt(_claims()), 'refreshToken': 'r-1', 'expiresIn': '$expiresIn'}
          )));
      await DesktopAccountAuth.signInWithCustomToken('custom');
    }

    test('قرب الانتهاء ⇒ يُجدَّد من securetoken', () async {
      await signIn(60); // أقلّ من خمس دقائق
      final fresh = _jwt(_claims(email: 'new@example.com'));
      final fake = _Fake((o) {
        expect(o.uri.host, 'securetoken.googleapis.com');
        expect('${o.data}', contains('refresh_token=r-1'));
        return (status: 200, body: {'id_token': fresh, 'refresh_token': 'r-2', 'expires_in': '3600'});
      });
      DesktopAccountAuth.debugDio = _dio(fake);
      expect(await AccountService.idToken(), fresh);
      expect(AccountService.currentUser?.email, 'new@example.com');
    });

    test('حسابٌ معطَّل عند Firebase ⇒ خروجٌ محلّيّ', () async {
      await signIn(60);
      DesktopAccountAuth.debugDio = _dio(_Fake((o) => (
            status: 400,
            body: {
              'error': {'code': 400, 'message': 'USER_DISABLED'}
            }
          )));
      expect(await AccountService.idToken(), isNull);
      expect(AccountService.currentUser, isNull);
    });

    test('الشبكة مقطوعة ⇒ التوكن الحاليّ ما دام صالحاً', () async {
      await signIn(120);
      final before = await DesktopAccountAuth.idToken();
      DesktopAccountAuth.debugDio = Dio()
        ..httpClientAdapter = _Fake((o) => throw DioException.connectionError(
            requestOptions: o, reason: 'offline'));
      expect(await AccountService.idToken(force: true), before);
      expect(AccountService.currentUser, isNotNull);
    });
  });

  group('الدخول عبر المتصفّح', () {
    late Uri opened;
    setUp(() {
      DesktopBrowserLogin.openUrl = (url) async {
        opened = url;
        return true;
      };
    });

    Future<int> hit(Uri page, {String? state, String code = 'code-1234567890abcd'}) async {
      final c = HttpClient();
      try {
        final req = await c.getUrl(Uri.parse(
            'http://127.0.0.1:${page.queryParameters['port']}/callback?code=$code&state=${state ?? page.queryParameters['state']}'));
        final res = await req.close();
        await res.drain<void>();
        return res.statusCode;
      } finally {
        c.close(force: true);
      }
    }

    test('الرمز يرجع لهذا الجهاز ويُبدَّل مع سرّ PKCE', () async {
      String? sentVerifier;
      DesktopBrowserLogin.debugDio = _dio(_Fake((o) {
        expect(o.path, '/api/account/desktop-login/token');
        sentVerifier = o.data['verifier'] as String;
        expect(o.data['code'], 'code-1234567890abcd');
        return (status: 200, body: {'token': 'custom-token'});
      }));
      final login = DesktopBrowserLogin(timeout: const Duration(seconds: 10));
      final result = login.run();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(opened.path, '/v2/desktop-login');
      expect(int.parse(opened.queryParameters['port']!), greaterThan(0));
      expect(await hit(opened), 200);
      expect(await result, 'custom-token');
      // الخادم يتحقّق: sha256(السرّ) = البصمة التي في رابط الصفحة.
      expect(DesktopBrowserLogin.challengeOf(sentVerifier!), opened.queryParameters['challenge']);
    });

    test('حالةٌ غريبة تُرفض والانتظار يستمرّ؛ الإلغاء ⇒ null', () async {
      final login = DesktopBrowserLogin(timeout: const Duration(seconds: 10));
      final result = login.run();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(await hit(opened, state: 'not-ours'), 400);
      login.cancel();
      expect(await result, isNull);
    });

    test('رفض الخادم ⇒ رسالته', () async {
      DesktopBrowserLogin.debugDio = _dio(_Fake((o) => (
            status: 410,
            body: {'error': 'DESKTOP_CODE_EXPIRED', 'message': 'انتهت صلاحيّة الرمز — ابدأ الدخول مرّةً أخرى'}
          )));
      final login = DesktopBrowserLogin(timeout: const Duration(seconds: 10));
      final result = login.run();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await hit(opened);
      await expectLater(
          result,
          throwsA(isA<DesktopLoginException>()
              .having((e) => e.message, 'message', contains('انتهت'))));
    });

    // ٢٨ أكتوبر (رفض متجر مايكروسوفت): البرنامج يسأل الخادم بسرّه أيضاً، والانتظار ٣٠ دقيقة.
    test('الانتظار ٣٠ دقيقة، والصفحة تُفتح بـpoll=1', () async {
      expect(DesktopBrowserLogin().timeout, const Duration(minutes: 30));
      final login = DesktopBrowserLogin(timeout: const Duration(seconds: 10));
      final result = login.run();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(opened.queryParameters['poll'], '1');
      login.cancel();
      expect(await result, isNull);
    });

    test('الدخول يصل بسؤال الخادم وحده (بلا رجوعٍ إلى 127.0.0.1)', () async {
      var polls = 0;
      String? sentVerifier;
      DesktopBrowserLogin.debugDio = _dio(_Fake((o) {
        expect(o.path, '/api/account/desktop-login/poll');
        sentVerifier = o.data['verifier'] as String;
        polls++;
        return polls < 3 ? (status: 202, body: {'pending': true}) : (status: 200, body: {'token': 'polled-token'});
      }));
      final login = DesktopBrowserLogin(timeout: const Duration(seconds: 10), pollEvery: const Duration(milliseconds: 20));
      expect(await login.run(), 'polled-token');
      expect(polls, 3);
      expect(DesktopBrowserLogin.challengeOf(sentVerifier!), opened.queryParameters['challenge']);
    });

    test('خادمٌ أقدم بلا السؤال (404) ⇒ يكفّ ويبقى 127.0.0.1', () async {
      var polls = 0;
      DesktopBrowserLogin.debugDio = _dio(_Fake((o) {
        if (o.path.endsWith('/poll')) {
          polls++;
          return (status: 404, body: {'error': 'not found'});
        }
        return (status: 200, body: {'token': 'custom-token'});
      }));
      final login = DesktopBrowserLogin(timeout: const Duration(seconds: 10), pollEvery: const Duration(milliseconds: 10));
      final result = login.run();
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(polls, 1, reason: 'سؤالٌ واحد ثمّ يكفّ');
      expect(await hit(opened), 200);
      expect(await result, 'custom-token');
    });

    test('سؤالٌ ورفضٌ من الخادم (410) ⇒ رسالته', () async {
      DesktopBrowserLogin.debugDio = _dio(_Fake((o) => (
            status: 410,
            body: {'error': 'DESKTOP_CODE_EXPIRED', 'message': 'انتهت صلاحيّة رمز الدخول'}
          )));
      final login = DesktopBrowserLogin(timeout: const Duration(seconds: 10), pollEvery: const Duration(milliseconds: 10));
      await expectLater(
          login.run(),
          throwsA(isA<DesktopLoginException>().having((e) => e.message, 'message', contains('انتهت'))));
    });

    test('Google على ويندوز يمرّ بالمتصفّح ثمّ التوكن المخصّص', () async {
      DesktopBrowserLogin.debugDio =
          _dio(_Fake((o) => (status: 200, body: {'token': 'custom-token'})));
      DesktopAccountAuth.debugDio = _dio(_Fake((o) {
        expect(o.uri.toString(), contains('accounts:signInWithCustomToken'));
        expect(o.data['token'], 'custom-token');
        return (status: 200, body: {'idToken': _jwt(_claims()), 'refreshToken': 'r', 'expiresIn': '3600'});
      }));
      final result = AccountService.signInWithGoogle();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(AccountService.desktopLogin, isNotNull);
      await hit(opened);
      final u = await result;
      expect(u?.isFederated, isTrue);
      expect(AccountService.isReady, isTrue);
      expect(AccountService.desktopLogin, isNull);
      await AccountService.signOut();
      expect(AccountService.currentUser, isNull);
    });
  });
}
