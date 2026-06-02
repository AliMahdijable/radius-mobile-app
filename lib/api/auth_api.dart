import 'package:dio/dio.dart';

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
    this.requires2fa = false,
  });

  final String token;
  final String adminId;
  final String adminUsername;
  final String displayName;
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
        requires2fa: body['requires2fa'] == true,
      );
    } on DioException catch (e) {
      return LoginFailure(_friendlyDioError(e));
    } catch (_) {
      return const LoginFailure('حدث خطأ غير متوقع. حاول مجدداً.');
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
