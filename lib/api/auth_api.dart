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
    this.isSuperAdmin = false,
    this.canAccessManagers = false,
    this.canAccessPackages = false,
    this.isEmployee = false,
    this.sas4Token,
  });

  final String token;

  /// للموظف: توكن SAS4 الأب (parent admin) من الـlogin response. للأدمن
  /// العادي: null (نستعمل token نفسه).
  final String? sas4Token;
  final String adminId;
  final String adminUsername;
  final String displayName;

  /// ISO8601 string of when the token expires. Stored as-is in
  /// AuthStorage so the interceptor can do proactive refresh.
  final String? expiresAt;
  final bool requires2fa;

  /// True when the SAS4 user permissions resolve to super-admin.
  final bool isSuperAdmin;

  /// True when the user can create sub-managers — درجة الـ
  /// 'prm_managers_create' SAS4. Drives the parent picker visibility
  /// on the add/edit subscriber sheets (مطابق v1 canAccessManagers).
  final bool canAccessManagers;

  /// True when the user can create/manage packages — درجة الـ
  /// 'prm_profiles_create' SAS4. Combined with canAccessManagers to
  /// gate the expiration date picker (canEditExpiration = either).
  final bool canAccessPackages;

  /// True عند login موظف (user.role='employee' في الـbackend response).
  /// يُحفظ في AuthStorage عشان AuthApi.refreshToken() ترفض التجديد
  /// للموظف — الـempToken لا يقدر يتجدد عبر /api/auth/refresh-token
  /// (الذي يجدد SAS4 admin token للأب) بدون ما يخسر الموظف صلاحياته.
  final bool isEmployee;
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
      final token =
          (body['token'] ?? body['accessToken'] ?? user['token'] ?? '')
              .toString();
      if (token.isEmpty) {
        return const LoginFailure('لم يصل رمز الجلسة من السيرفر.');
      }

      // Backend sets user.role='super_admin' AND user.isSuperAdmin=true
      // when SAS4 permissions resolve to super (server.js ~1640/1880).
      // We accept either signal so a minor backend rename doesn't
      // silently strip the flag client-side.
      final isSuperAdmin = user['isSuperAdmin'] == true ||
          user['is_super_admin'] == true ||
          (user['role']?.toString() == 'super_admin');
      // canAccessManagers / canAccessPackages — مصدرها مختلف حسب نوع
      // المستخدم:
      //  • أدمن عادي: user.permissions = List من رموز SAS4 مثل
      //    'prm_managers_create' / 'prm_profiles_create' (v1 pattern)
      //  • موظف: user.employee.permissions = Map من مفاتيحنا الداخليّة
      //    مثل {'subscribers.add': true, 'packages.view': true, ...}
      //    الرموز SAS4 لا تصل للموظف — كنّا نحسبها = false دائماً وهذا
      //    يمنع _canEditExpiration من الظهور ويكسر flow التفعيل عند الإضافة.
      //
      // super-admin دائماً true (fast path).
      final isEmployee = user['role']?.toString() == 'employee';
      bool canAccessManagers;
      bool canAccessPackages;
      if (isSuperAdmin) {
        canAccessManagers = true;
        canAccessPackages = true;
      } else if (isEmployee) {
        // employee: نقرأ Map من user.employee.permissions
        final empBlock = user['employee'];
        final Map<String, dynamic> empPerms = (empBlock is Map)
            ? Map<String, dynamic>.from(
                empBlock['permissions'] as Map? ?? const {})
            : const {};
        bool has(String k) => empPerms[k] == true;
        // الموظف لا يقدر يُنشئ مدير فرعي بشكل طبيعي — parent picker يبقى مخفي.
        // نُبقيها strict على managers.add عشان ما نظهر UI ما يقدر يستعمله.
        canAccessManagers = has('managers.add');
        // packages access = عرض الباقات + أي صلاحيّة تحتاج ضبط expiration
        // (add/edit/activate/extend) — عشان يظهر حقل التاريخ عند الحاجة.
        canAccessPackages = has('packages.view') ||
            has('subscribers.add') ||
            has('subscribers.edit') ||
            has('subscribers.activate') ||
            has('subscribers.extend');
      } else {
        // admin عادي: List من رموز SAS4 (المسار الأصلي — بلا تغيير)
        final perms = (user['permissions'] ?? body['permissions']) as List?;
        final permSet =
            perms?.map((e) => e.toString()).toSet() ?? const <String>{};
        canAccessManagers = permSet.contains('prm_managers_create');
        canAccessPackages = permSet.contains('prm_profiles_create');
      }
      // مطلب 2026-06-11: لو الدخول كموظف، نعرض اسم الموظف لا اسم
      // المدير الأب في الـgreeting. الـbackend يميّز هذي الحالة بحقل
      // user.role='employee' + user.employee.{full_name, username}.
      // الـdisplay name ياخذ الأولوية للموظف؛ فاضي = نسقط للـusername
      // العادي وفي النهاية 'مستخدم'.
      final empBlock = user['employee'];
      String displayName;
      if (isEmployee && empBlock is Map) {
        final empFull = (empBlock['full_name'] ?? '').toString().trim();
        final empUser = (empBlock['username'] ?? '').toString().trim();
        displayName = empFull.isNotEmpty
            ? empFull
            : (empUser.isNotEmpty ? empUser : 'موظف');
      } else {
        displayName =
            (user['display_name'] ?? user['username'] ?? 'مستخدم').toString();
      }
      // 2026-07-12 fix: sas4Token يجي في response للموظف — توكن الأب
      // للاستدعاءات المباشرة على SAS4. للأدمن العادي، الـtoken هو نفسه
      // (سنُخزّنه كـsas4Token لتوحيد قراءات SAS4).
      final sas4Token =
          body['sas4Token']?.toString() ?? body['sas4_token']?.toString();
      return LoginSuccess(
        token: token,
        adminId: (user['admin_id'] ?? user['id'] ?? '').toString(),
        adminUsername: (user['username'] ?? '').toString(),
        displayName: displayName,
        expiresAt: body['expiresAt']?.toString(),
        requires2fa: body['requires2fa'] == true,
        isSuperAdmin: isSuperAdmin,
        canAccessManagers: canAccessManagers,
        canAccessPackages: canAccessPackages,
        isEmployee: isEmployee,
        sas4Token: sas4Token,
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
  ///
  /// 2026-07-12 fix (v1 parity): للموظفين، نجدّد SAS4 admin token فقط
  /// (نُخزّنه في sas4Token المنفصل)، بدون لمس empJWT الرئيسي. هيك
  /// الموظف يبقى موظف (perms.cache، is_employee=true) لكن استدعاءات
  /// SAS4 تحصل على توكن حديث. يطابق mobile-app v1
  /// (SessionRefreshService._refreshSession).
  static Future<({String token, String? expiresAt})?> refreshToken() async {
    final adminId = await AuthStorage.readAdminId();
    if (adminId == null) return null;
    final isEmp = await AuthStorage.isEmployee();
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
      // 2026-07-12 fix: للموظف نحدّث sas4Token فقط. الـempJWT الرئيسي
      // (token) يبقى كما هو — الـmiddleware في backend يقرأ empJWT
      // ويستعمله للتحقق من is_employee + perms، وسـsas4Token المُخزَّن
      // يُستعمل للاستدعاءات المباشرة على SAS4.
      // للأدمن العادي نحدّث الاثنين (نفس التوكن).
      if (isEmp) {
        await AuthStorage.saveSas4Token(newToken);
      } else {
        await AuthStorage.saveRefreshedToken(
          token: newToken,
          tokenExpiry: expiresAt,
        );
        await AuthStorage.saveSas4Token(newToken);
      }
      if (!kReleaseMode) {
        debugPrint(
            '🟢 refresh-token: ${isEmp ? "sas4Token only (employee)" : "token+sas4Token"} saved, expires=$expiresAt');
      }
      return (token: newToken, expiresAt: expiresAt);
    } catch (e) {
      if (!kReleaseMode) debugPrint('🔴 refresh-token failed: $e');
      return null;
    }
  }

  static String _friendlyDioError(DioException e) {
    // 2026-07-13: dio 5.10+ أضاف DioExceptionType.transformTimeout. نستعمل
    // default بدل تعداد الحالات صراحةً — مقاومة لإضافات dio المستقبلية.
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
      default:
        // cancel / badCertificate / unknown / transformTimeout / أي جديد
        return 'حدث خطأ في الشبكة. حاول مجدداً.';
    }
  }
}
