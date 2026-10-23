import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart' show FirebaseAuthException;
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../firebase_options.dart';
import 'account_user.dart';

/// حساب Pro على ويندوز — Firebase Auth عبر واجهته الرسميّة على الإنترنت (REST).
///
/// Firebase يقول إنّ نسخته لويندوز «ليست للاستعمال الحقيقيّ» (firebase.google.com/docs/flutter/setup،
/// ٢٢ أكتوبر ٢٠٢٦)، فنكلّم نفس المشروع مباشرةً: نفس الحسابات، ونفس توكن الهويّة الذي يتحقّق منه
/// الخادم (`x-account-token`). Google يصل هنا توكناً مخصّصاً من «الدخول عبر المتصفّح»
/// ([DesktopBrowserLogin]).
///
/// الأخطاء تُرمى [FirebaseAuthException] بنفس رموز الهاتف، فرسائل الشاشات هي هي.
class DesktopAccountAuth {
  DesktopAccountAuth._();

  static const _storeKey = 'account.desktop.v1';
  static const _identity = 'https://identitytoolkit.googleapis.com/v1/accounts';
  static const _secureToken = 'https://securetoken.googleapis.com/v1/token';

  /// مفتاح المشروع العامّ — نفسه الذي يستعمله الموقع وتطبيق أندرويد.
  static String get _apiKey => DefaultFirebaseOptions.android.apiKey;

  static const _storage = FlutterSecureStorage();

  @visibleForTesting
  static Dio? debugDio;

  /// تتغيّر عند الدخول والخروج وتجديد البيانات.
  static final ValueNotifier<AccountUser?> user = ValueNotifier<AccountUser?>(null);

  static _Session? _session;
  static Future<String?>? _refreshing;

  static AccountUser? get currentUser => user.value;

  static Dio get _dio =>
      debugDio ??
      (_client ??= Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 20),
        sendTimeout: const Duration(seconds: 15),
        validateStatus: (_) => true,
        headers: {'Content-Type': 'application/json'},
      )));
  static Dio? _client;

  /// عند الإقلاع: الجلسة المحفوظة (إن وُجدت). لا شبكة.
  static Future<void> restore() async {
    try {
      final raw = await _storage.read(key: _storeKey);
      if (raw == null || raw.isEmpty) return;
      final s = _Session.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      _session = s;
      user.value = s.user;
    } catch (e) {
      if (kDebugMode) debugPrint('🟠 desktop account restore: $e');
    }
  }

  /// توكن الهويّة للخادم — يُجدَّد قبل انتهائه بخمس دقائق أو عند [force]. null = لا حساب أو
  /// رفض Firebase التجديد (الحساب عُطّل/حُذف ⇒ خروجٌ محلّيّ).
  static Future<String?> idToken({bool force = false}) {
    final s = _session;
    if (s == null) return Future.value(null);
    final fresh = s.expiresAt.isAfter(DateTime.now().add(const Duration(minutes: 5)));
    if (fresh && !force) return Future.value(s.idToken);
    return _refreshing ??= _refresh().whenComplete(() => _refreshing = null);
  }

  static Future<String?> _refresh() async {
    final s = _session;
    if (s == null) return null;
    try {
      final r = await _dio.post<Object?>(
        '$_secureToken?key=$_apiKey',
        data: 'grant_type=refresh_token&refresh_token=${Uri.encodeQueryComponent(s.refreshToken)}',
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );
      final body = r.data;
      if (r.statusCode == 200 && body is Map) {
        await _adopt(
          idToken: '${body['id_token']}',
          refreshToken: '${body['refresh_token']}',
          expiresIn: int.tryParse('${body['expires_in']}') ?? 3600,
        );
        return _session?.idToken;
      }
      final code = _errorCode(body);
      if (_isDeadSession(code)) {
        await signOut();
        return null;
      }
      // رفضٌ مؤقّت: التوكن الحاليّ ما دام صالحاً.
      return s.expiresAt.isAfter(DateTime.now()) ? s.idToken : null;
    } catch (e) {
      if (kDebugMode) debugPrint('🟠 desktop account refresh: $e');
      return s.expiresAt.isAfter(DateTime.now()) ? s.idToken : null;
    }
  }

  static Future<AccountUser?> signInWithPassword(String email, String password) async {
    final body = await _call('signInWithPassword', {
      'email': email.trim(),
      'password': password,
      'returnSecureToken': true,
    });
    return _adoptSignIn(body);
  }

  static Future<AccountUser?> signUp(String email, String password) async {
    final body = await _call('signUp', {
      'email': email.trim(),
      'password': password,
      'returnSecureToken': true,
    });
    final u = await _adoptSignIn(body);
    await sendVerification();
    return u;
  }

  static Future<AccountUser?> signInWithCustomToken(String token) async {
    final body = await _call('signInWithCustomToken', {
      'token': token,
      'returnSecureToken': true,
    });
    return _adoptSignIn(body);
  }

  static Future<void> sendVerification() async {
    final t = await idToken();
    if (t == null) return;
    await _call('sendOobCode', {'requestType': 'VERIFY_EMAIL', 'idToken': t});
  }

  static Future<void> sendPasswordReset(String email) async {
    await _call('sendOobCode', {'requestType': 'PASSWORD_RESET', 'email': email.trim()});
  }

  /// بعد ضغط رابط التأكيد: توكنٌ جديد يحمل `email_verified`.
  static Future<bool> reloadVerified() async {
    final t = await idToken(force: true);
    if (t == null) return false;
    return currentUser?.emailVerified ?? false;
  }

  /// حذف مستخدم Firebase نفسه (بعد أن يحذف الخادم الحساب). فشله لا يمنع الخروج.
  static Future<void> deleteUser() async {
    final t = await idToken();
    if (t == null) return;
    await _call('delete', {'idToken': t});
  }

  static Future<void> signOut() async {
    _session = null;
    user.value = null;
    try {
      await _storage.delete(key: _storeKey);
    } catch (_) {}
  }

  // ───────────────────────────── داخليّ ─────────────────────────────

  static Future<Map<String, dynamic>> _call(String method, Map<String, Object?> data) async {
    final Response<Object?> r;
    try {
      r = await _dio.post<Object?>('$_identity:$method?key=$_apiKey', data: data);
    } on DioException {
      throw FirebaseAuthException(code: 'network-request-failed');
    }
    final body = r.data;
    if (r.statusCode == 200 && body is Map) return Map<String, dynamic>.from(body);
    throw FirebaseAuthException(code: mapError(_errorCode(body)));
  }

  static Future<AccountUser?> _adoptSignIn(Map<String, dynamic> body) async {
    await _adopt(
      idToken: '${body['idToken']}',
      refreshToken: '${body['refreshToken']}',
      expiresIn: int.tryParse('${body['expiresIn']}') ?? 3600,
    );
    return currentUser;
  }

  static Future<void> _adopt({
    required String idToken,
    required String refreshToken,
    required int expiresIn,
  }) async {
    final u = userFromIdToken(idToken);
    if (u == null) throw FirebaseAuthException(code: 'internal-error');
    final s = _Session(
      idToken: idToken,
      refreshToken: refreshToken,
      expiresAt: DateTime.now().add(Duration(seconds: expiresIn)),
      user: u,
    );
    _session = s;
    user.value = u;
    try {
      await _storage.write(key: _storeKey, value: jsonEncode(s.toJson()));
    } catch (e) {
      if (kDebugMode) debugPrint('🟠 desktop account save: $e');
    }
  }

  /// الحساب من توكن الهويّة نفسه (JWT موقَّع من Google يتحقّق منه الخادم) — بلا نداءٍ آخر.
  @visibleForTesting
  static AccountUser? userFromIdToken(String jwt) {
    try {
      final parts = jwt.split('.');
      if (parts.length != 3) return null;
      final claims = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))))
          as Map<String, dynamic>;
      final uid = '${claims['user_id'] ?? claims['sub'] ?? ''}';
      if (uid.isEmpty) return null;
      final fb = claims['firebase'];
      final identities = fb is Map ? fb['identities'] : null;
      final providers = <String>[
        if (identities is Map) ...identities.keys.map((k) => k == 'email' ? 'password' : '$k'),
      ];
      return AccountUser(
        uid: uid,
        email: claims['email'] as String?,
        displayName: claims['name'] as String?,
        emailVerified: claims['email_verified'] == true,
        providerIds: providers,
      );
    } catch (_) {
      return null;
    }
  }

  static String _errorCode(Object? body) {
    if (body is Map) {
      final e = body['error'];
      if (e is Map && e['message'] != null) return '${e['message']}';
      if (e is String) return e; // securetoken: {"error": "invalid_grant", ...}
    }
    return '';
  }

  static bool _isDeadSession(String code) => const {
        'TOKEN_EXPIRED',
        'USER_DISABLED',
        'USER_NOT_FOUND',
        'INVALID_REFRESH_TOKEN',
        'invalid_grant',
      }.contains(code.split(' ').first);

  /// رموز Firebase REST ⇒ رموز FirebaseAuthException على الهاتف (AccountService.messageFor).
  @visibleForTesting
  static String mapError(String raw) {
    final code = raw.split(' ').first.split(':').first.trim();
    switch (code) {
      case 'EMAIL_NOT_FOUND':
      case 'INVALID_PASSWORD':
      case 'INVALID_LOGIN_CREDENTIALS':
        return 'invalid-credential';
      case 'USER_DISABLED':
        return 'user-disabled';
      case 'EMAIL_EXISTS':
        return 'email-already-in-use';
      case 'WEAK_PASSWORD':
        return 'weak-password';
      case 'TOO_MANY_ATTEMPTS_TRY_LATER':
        return 'too-many-requests';
      case 'INVALID_EMAIL':
      case 'MISSING_EMAIL':
        return 'invalid-email';
      case 'TOKEN_EXPIRED':
      case 'INVALID_ID_TOKEN':
      case 'CREDENTIAL_TOO_OLD_LOGIN_AGAIN':
        return 'requires-recent-login';
      case 'INVALID_CUSTOM_TOKEN':
      case 'CREDENTIAL_MISMATCH':
        return 'invalid-custom-token';
      case 'OPERATION_NOT_ALLOWED':
        return 'operation-not-allowed';
    }
    return code.isEmpty ? 'unknown' : code.toLowerCase();
  }
}

class _Session {
  const _Session({
    required this.idToken,
    required this.refreshToken,
    required this.expiresAt,
    required this.user,
  });

  factory _Session.fromJson(Map<String, dynamic> j) => _Session(
        idToken: '${j['idToken']}',
        refreshToken: '${j['refreshToken']}',
        expiresAt: DateTime.fromMillisecondsSinceEpoch((j['expiresAt'] as num).toInt()),
        user: AccountUser.fromJson(Map<String, dynamic>.from(j['user'] as Map)),
      );

  final String idToken;
  final String refreshToken;
  final DateTime expiresAt;
  final AccountUser user;

  Map<String, dynamic> toJson() => {
        'idToken': idToken,
        'refreshToken': refreshToken,
        'expiresAt': expiresAt.millisecondsSinceEpoch,
        'user': user.toJson(),
      };
}
