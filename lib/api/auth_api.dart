import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../services/account_service.dart';
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
    this.canonicalPermissions = const {},
  });

  final String token;
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

  /// Pro: الصلاحيّات المعياريّة للمدير من الساس (subscribers.delete،
  /// show_password، change_profile…). تُضبَط بها أزرار الإجراءات عبر Perms —
  /// المدير الفرعيّ فاعلٌ مقيَّد لا كامل الصلاحيّات. فارغةٌ = غير مقيَّد
  /// (super-admin أو لم يُرسِلها الخادم). لا تخصّ الموظّف (له خريطته من /me).
  final Map<String, bool> canonicalPermissions;
}

class LoginFailure extends LoginResult {
  const LoginFailure(this.message, {this.code, this.captcha, this.rejected = false});
  final String message;

  /// الساس رفض اليوزر/كلمة السرّ (401 بلا رمز بوّابة) — لا شبكة ولا حساب.
  final bool rejected;

  /// Pro البند ٤: رمز بوّابة الحساب من الخادم — `subscription-ended` (402)،
  /// `account-required`/`account-token-invalid` (401)، `account-disabled`/
  /// `no-account` (403)، `bad-sas-url` (400). null لأخطاء الساس المعتادة.
  /// و`captcha-required`: الساس يطلب رمز صورة ([captcha])، و`captcha-cancelled`:
  /// أغلق المستخدم نافذة الرمز (لا رسالة).
  final String? code;

  /// صورة الرمز حين يطلبها الساس (الحياة عمارة…).
  final SasCaptcha? captcha;

  static const _notGate = {'bad-sas-url', 'captcha-required', 'captcha-cancelled'};

  /// رمزٌ من بوّابة الحساب (انتهى الاشتراك/الحساب معطّل…) ← البوّابة تقرّر.
  bool get isAccountGate => code != null && !_notGate.contains(code);
  bool get needsCaptcha => code == 'captcha-required' && captcha != null;
  bool get isCancelled => code == 'captcha-cancelled';
}

/// Pro: رمز صورةٍ يطلبه الساس عند الدخول — المعرّف يعود مع الرمز المكتوب.
class SasCaptcha {
  const SasCaptcha({required this.id, required this.image});
  final String id;
  final Uint8List image;

  static SasCaptcha? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id']?.toString() ?? '';
    final img = raw['image']?.toString() ?? '';
    if (id.isEmpty || img.isEmpty) return null;
    try {
      return SasCaptcha(id: id, image: base64Decode(img));
    } catch (_) {
      return null;
    }
  }
}

/// نتيجة تجديد التوكن: نجاحٌ، أو رفضٌ صريح من الخادم، أو تعثّر شبكة.
enum RefreshOutcome { ok, serverRejected, networkFailure }

class AuthApi {
  AuthApi._();

  /// POST /api/auth/login. Returns LoginSuccess on success (response
  /// success=true) or LoginFailure with an Arabic message otherwise.
  static Future<LoginResult> login({
    required String username,
    required String password,
    String? sasUrl,
    String? captchaId,
    String? captchaText,
  }) async {
    try {
      // Pro: رابط صفحة الشركة (إن لصقه المستخدم) — الخادم يشتقّ منه الساس
      // ويؤهّل الهويّة (jt:6836). فارغٌ = الأصل (supernet). يُرسَل فقط إن وُجد.
      final sas = sasUrl?.trim() ?? '';
      // Pro البند ٤: دخول الساس يشترط حساب إيميل باشتراكٍ صالح — توكن الحساب
      // في x-account-token (المعترض يتخطّى /api/auth/ فلا يلمسه).
      final accountToken = await AccountService.idToken();
      final res = await ApiClient.dio.post<Map<String, dynamic>>(
        '/api/auth/login',
        data: {
          'username': username.trim(),
          'password': password,
          if (sas.isNotEmpty) 'sasUrl': sas,
          if (captchaId != null) 'captchaId': captchaId,
          if (captchaText != null) 'captchaText': captchaText,
        },
        options: Options(headers: {
          if (accountToken != null) 'x-account-token': accountToken,
        }),
      );
      final body = res.data ?? const {};

      if (body['success'] != true) {
        return LoginFailure(
          (body['message'] as String?)?.trim().isNotEmpty == true
              ? body['message'] as String
              : 'فشل تسجيل الدخول. تأكد من اسم المستخدم وكلمة المرور.',
          code: body['error']?.toString(),
          captcha: SasCaptcha.tryParse(body['captcha']),
          rejected: res.statusCode == 401 && body['error'] == null,
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
      // الردّ يحمل `sas4Token` أيضاً (توكن الساس للأب). نتجاهله عمداً:
      // الهاتف لا يخاطب الساس، وحفظه كان يترك سرّاً لا يقرؤه أحد —
      // انظر `_kSas4TokenLegacy` ورأس `api_client.dart`.
      // Pro: الخريطة المعياريّة للمدير (الخادم يُرجِعها تحت user). كان يُهمَلها
      // التطبيق فتظهر كلّ الأزرار للمدير الفرعيّ؛ نلتقطها لتضبط Perms الأزرار.
      final canonRaw =
          user['canonicalPermissions'] ?? body['canonicalPermissions'];
      final Map<String, bool> canonicalPermissions = (canonRaw is Map)
          ? {
              for (final e in canonRaw.entries)
                e.key.toString(): e.value == true,
            }
          : const <String, bool>{};
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
        canonicalPermissions: canonicalPermissions,
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
  /// نتيجة محاولة التجديد — والتمييز بينها ليس ترفاً.
  ///
  /// 🐛 كان كلّ فشلٍ يُعامَل «جلسةً ميتة» فتُمحى: انقطاع شبكةٍ لحظيّ،
  /// أو مهلة عشر ثوانٍ، أو حدّ طلباتٍ من الخادم — كلّها تُخرج الموظّف
  /// من حسابه وسط عمله. والجلسة لا تموت إلّا بحكمٍ صريح من الخادم.
  static Future<RefreshOutcome> refreshTokenDetailed() async {
    final adminId = await AuthStorage.readAdminId();
    if (adminId == null) return RefreshOutcome.serverRejected;

    // ── الموظّف لا يُجدَّد، ونقولها رفضاً لا نجاحاً كاذباً ──
    //
    // النقطة تأخذ `adminId` وحدها ولا تعرف الموظّفين أصلاً: تفكّ كلمة
    // سرّ **الأب** المخزَّنة وتسجّل دخوله في الساس فتُعيد توكناً له.
    // و`adminId` المحفوظ للموظّف هو معرّف أبيه (ردّ الدخول يضع
    // `user.id = parent_admin_id`) — فالنداء ينجح دائماً ويُعيد توكناً
    // لا يصلح للموظّف: `empJWT` وحده يحمل صلاحيّاته.
    //
    // وكان ذلك التوكن يُحفظ في `sas4Token` — حقلٌ لم يقرأه أحدٌ قطّ —
    // ثمّ يُعلَن النجاح. فيعيد المعترض الطلبَ بالـ`empJWT` المنتهي
    // نفسه، فيفشل ثانيةً، ويُبتلَع الفشل. والنتيجة موظّفٌ انتهت جلسته
    // يبقى في واجهةٍ كلُّ نداءٍ فيها 401 صامت، ولا يُطرد أبداً.
    //
    // ومع النجاح الكاذب نداءُ شبكةٍ بلا طائل يُعيد تسجيل دخول الأب في
    // الساس ويكتب توكنه في قاعدتنا عند كلّ موجة 401.
    //
    // فالرفض صريحٌ هنا: الموظّف يستعمل `empJWT` طوال مدّته (٢٤ ساعة)
    // ثمّ يُعيد الدخول. و`serverRejected` لا `networkFailure` — هذا
    // حكمٌ قاطع لا تعثّرٌ عابر، فيجب أن يُطرد لا أن يُنتظَر.
    if (await AuthStorage.isEmployee()) {
      if (!kReleaseMode) {
        debugPrint('🟡 refresh-token: موظّف — لا تجديد، الطرد إلى الدخول');
      }
      return RefreshOutcome.serverRejected;
    }

    try {
      // Fresh Dio without the auth interceptor — otherwise a 401 on the
      // refresh call itself would try to refresh recursively.
      // ⚠️ `validateStatus` لازمة لا تجميل.
      //
      // 🐛 بدونها يستعمل Dio الافتراضيّ (2xx فقط)، فيرمي على **كلّ**
      // ردٍّ ٤٠١/٤٠٣ — والرمية تسقط في `catch` العامّ فتُصنَّف
      // «تعثّر شبكة». والنتيجة عكس المقصود تماماً: رفضٌ صريح من
      // الخادم يُقرأ انقطاعاً، فلا تُمحى الجلسة أبداً ويبقى المستخدم
      // في تطبيقٍ ميّت لا يطلب منه الدخول.
      final dio = Dio(BaseOptions(
        baseUrl: ApiClient.baseUrl,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
        validateStatus: (s) => s != null && s < 500,
        headers: const {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ));
      // Pro البند ٤ ③: التجديد يشترط حساباً مربوطاً بهذا المدير (كان بلا
      // أيّ تحقّق). بلا حساب = رفضٌ صريح، فيعود المستخدم لطبقة الحساب.
      final accountToken = await AccountService.idToken();
      if (accountToken == null) {
        dio.close();
        return RefreshOutcome.serverRejected;
      }
      final res = await dio.post<Map<String, dynamic>>(
        '/api/auth/refresh-token',
        data: {'adminId': adminId},
        options: Options(headers: {'x-account-token': accountToken}),
      );
      dio.close();
      // ٤xx = حكمٌ صريح من الخادم. (٥xx و٤٢٩ لا تصل هنا — تُرمى وتُعامَل
      // تعثّراً، وهو الصواب: خادمٌ متعثّر لا يعني جلسةً ميتة.)
      final code = res.statusCode ?? 0;
      if (code >= 400) {
        if (!kReleaseMode) debugPrint('🟡 refresh-token: HTTP $code');
        return RefreshOutcome.serverRejected;
      }
      final body = res.data ?? const {};
      if (body['success'] != true) {
        if (!kReleaseMode) {
          debugPrint('🟡 refresh-token: success!=true body=$body');
        }
        // ردٌّ وصل وقال «لا» — حكمٌ صريح لا تعثّر شبكة.
        return RefreshOutcome.serverRejected;
      }
      final newToken = body['token']?.toString();
      final expiresAt = body['expiresAt']?.toString();
      if (newToken == null || newToken.isEmpty) {
        return RefreshOutcome.serverRejected;
      }
      // أدمنٌ عاديّ وحده يصل هنا — الموظّف ارتدّ أعلاه — وتوكنه هو
      // توكن الساس نفسه. و`saveSas4Token` حُذف في ٢٠٢٦-٠٩-١٥ لأنّه
      // كان يُكتب ولا يُقرأ.
      await AuthStorage.saveRefreshedToken(
        token: newToken,
        tokenExpiry: expiresAt,
      );
      if (!kReleaseMode) {
        debugPrint('🟢 refresh-token: token saved, expires=$expiresAt');
      }
      return RefreshOutcome.ok;
    } on DioException catch (e) {
      // ٥xx أو ٤٢٩ أو مهلةٌ أو انقطاع — الخادم متعثّر لا رافض.
      if (!kReleaseMode) {
        debugPrint('🔴 refresh-token dio: ${e.type} ${e.response?.statusCode}');
      }
      return RefreshOutcome.networkFailure;
    } catch (e) {
      if (!kReleaseMode) debugPrint('🔴 refresh-token failed: $e');
      return RefreshOutcome.networkFailure;
    }
  }

  /// غلافٌ للمستدعين القدامى الذين يريدون «نجح أم لا» فقط.
  static Future<bool> refreshToken() async =>
      await refreshTokenDetailed() == RefreshOutcome.ok;

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
        // ٥xx يُرمى (validateStatus < 500) لكنّ الخادم يرسل رسالةً عربيّة واضحة
        // («لا يمكن الوصول لخادم المصادقة»…) — نعرضها بدل «HTTP 503» الخام.
        final data = e.response?.data;
        final serverMsg = data is Map ? (data['message'] as String?)?.trim() : null;
        if (serverMsg != null && serverMsg.isNotEmpty) return serverMsg;
        if (code == 401) return 'اسم المستخدم أو كلمة المرور غير صحيحة.';
        if (code == 429) return 'محاولات كثيرة. انتظر دقيقة ثم أعد المحاولة.';
        return 'استجابة غير متوقعة من السيرفر (HTTP $code).';
      default:
        // cancel / badCertificate / unknown / transformTimeout / أي جديد
        return 'حدث خطأ في الشبكة. حاول مجدداً.';
    }
  }
}
