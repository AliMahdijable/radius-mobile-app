import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../services/auth_storage.dart';
import 'api_client.dart';

/// Result of a login attempt. Either we got a session (token + admin
/// info) or a friendly Arabic error message to show the user.
sealed class LoginResult {
  const LoginResult();
}

class LoginSuccess extends LoginResult {
  const LoginSuccess({
    required this.token,
    required this.adminId,
    required this.adminUsername,
    required this.displayName,
    this.expiresAt,
    this.requires2fa = false,
  });

  final String token;
  final String adminId;
  final String adminUsername;
  final String displayName;
  /// ISO8601 string of when the token expires. Stored as-is in
  /// AuthStorage so the interceptor can do proactive refresh.
  final String? expiresAt;
  final bool requires2fa;
}

class LoginFailure extends LoginResult {
  const LoginFailure(this.message);
  final String message;
}

class AuthApi {
  AuthApi._();

  /// POST /api/auth/login. Returns LoginSuccess on success (response
  /// success=true) or LoginFailure with an Arabic message otherwise.
  static Future<LoginResult> login({
    required String username,
    required String password,
  }) async {
    try {
      final res = await ApiClient.dio.post<Map<String, dynamic>>(
        '/api/auth/login',
        data: {'username': username.trim(), 'password': password},
      );
      final body = res.data ?? const {};

      if (body['success'] != true) {
        return LoginFailure(
          (body['message'] as String?)?.trim().isNotEmpty == true
              ? body['message'] as String
              : 'فشل تسجيل الدخول. تأكد من اسم المستخدم وكلمة المرور.',
        );
      }

      final user = body['user'] as Map<String, dynamic>? ?? body;
      final token = (body['token'] ??
              body['accessToken'] ??
              user['token'] ??
              '')
          .toString();
      if (token.isEmpty) {
        return const LoginFailure('لم يصل رمز الجلسة من السيرفر.');
      }

      return LoginSuccess(
        token: token,
        adminId: (user['admin_id'] ?? user['id'] ?? '').toString(),
        adminUsername: (user['username'] ?? '').toString(),
        displayName: (user['display_name'] ??
                user['username'] ??
                'مستخدم')
            .toString(),
        expiresAt: body['expiresAt']?.toString(),
        requires2fa: body['requires2fa'] == true,
      );
    } on DioException catch (e) {
      return LoginFailure(_friendlyDioError(e));
    } catch (_) {
      return const LoginFailure('حدث خطأ غير متوقع. حاول مجدداً.');
    }
  }

  /// POST /api/auth/refresh-token with {adminId}. The backend regenerates
  /// the SAS4 session using the parent admin's stored password (this is
  /// the same flow v1's SessionRefreshService uses). For regular admins,
  /// the new token IS the new SAS4 token. Returns null on any failure
  /// so the caller can fall back to forcing logout.
  static Future<({String token, String? expiresAt})?> refreshToken() async {
    final adminId = await AuthStorage.readAdminId();
    if (adminId == null) return null;
    try {
      // Fresh Dio without the auth interceptor — otherwise a 401 on the
      // refresh call itself would try to refresh recursively.
      final dio = Dio(BaseOptions(
        baseUrl: ApiClient.baseUrl,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
        headers: const {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ));
      final res = await dio.post<Map<String, dynamic>>(
        '/api/auth/refresh-token',
        data: {'adminId': adminId},
      );
      dio.close();
      final body = res.data ?? const {};
      if (body['success'] != true) {
        if (!kReleaseMode) {
          debugPrint('🟡 refresh-token: success!=true body=$body');
        }
        return null;
      }
      final newToken = body['token']?.toString();
      final expiresAt = body['expiresAt']?.toString();
      if (newToken == null || newToken.isEmpty) return null;
      await AuthStorage.saveRefreshedToken(
        token: newToken,
        tokenExpiry: expiresAt,
      );
      if (!kReleaseMode) {
        debugPrint('🟢 refresh-token: new token saved, expires=$expiresAt');
      }
      return (token: newToken, expiresAt: expiresAt);
    } catch (e) {
      if (!kReleaseMode) debugPrint('🔴 refresh-token failed: $e');
      return null;
    }
  }

  static String _friendlyDioError(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return 'انتهت مهلة الاتصال. تأكد من الإنترنت.';
      case DioExceptionType.connectionError:
        return 'تعذّر الاتصال بالسيرفر. تأكد من الإنترنت.';
      case DioExceptionType.badResponse:
        final code = e.response?.statusCode;
        if (code == 401) return 'اسم المستخدم أو كلمة المرور غير صحيحة.';
        if (code == 429) return 'محاولات كثيرة. انتظر دقيقة ثم أعد المحاولة.';
        return 'استجابة غير متوقعة من السيرفر (HTTP $code).';
      case DioExceptionType.cancel:
      case DioExceptionType.badCertificate:
      case DioExceptionType.unknown:
        return 'حدث خطأ في الشبكة. حاول مجدداً.';
    }
  }
}
