import 'dart:async';

import '../api/auth_api.dart';
import 'active_company.dart';
import 'auth_storage.dart';
import 'company_creds_store.dart';
import 'fcm_service.dart';
import 'permissions_service.dart';
import 'provider_service.dart';
import 'saved_profiles_store.dart';
import 'session_manager.dart';

enum SasLoginOutcome { ok, needs2fa, permsFailed }

/// ما بعد دخولٍ ناجح للساس — مكانٌ واحد لشاشة الدخول و«شركاتي».
///
/// الترتيب ملزِم (كان مكرّراً في شاشة الدخول): مسح بقايا الجلسة السابقة ←
/// حفظ الجلسة ← الصلاحيّات (الموظّف ينتظر جلبها، المدير من الساس فوراً) ←
/// FCM. والنداء لا يتنقّل بين الشاشات؛ المتّصل يقرّر حسب النتيجة.
class SasLoginFlow {
  SasLoginFlow._();

  /// [companyLabel]/[sasCode]: اسم الشركة وكودها إن عرفهما المتّصل («شركاتي»
  /// أو الدليل) — لشريط الشركة أعلى الواجهة؛ غيابهما يُقدَّر ثمّ يُحسم.
  static Future<SasLoginOutcome> complete(
    LoginSuccess s, {
    required String username,
    required String password,
    required String sasUrl,
    required bool remember,
    String? companyLabel,
    String? sasCode,
  }) async {
    await SessionManager.clearAllSessionData(unregisterFcm: false, clearAuth: false);
    await AuthStorage.saveSession(
      token: s.token,
      adminId: s.adminId,
      adminUsername: s.adminUsername,
      displayName: s.displayName,
      autoLogin: remember,
      tokenExpiry: s.expiresAt,
      isSuperAdmin: s.isSuperAdmin,
      canAccessManagers: s.canAccessManagers,
      canAccessPackages: s.canAccessPackages,
      isEmployee: s.isEmployee,
      sasUrl: sasUrl,
    );
    // الشركة المفتوحة الآن (شريط MainShell) — تحلّ محلّ السابقة التي مسحها
    // `clearAllSessionData` أعلاه. الموظّف تُعرض معه شركة مديره الأب.
    await ActiveCompany.saveFromLogin(
      sasUrl: sasUrl,
      adminId: s.adminId,
      loginUsername: username,
      adminUsername: s.adminUsername,
      isEmployee: s.isEmployee,
      label: companyLabel,
      sasCode: sasCode,
    );
    // كلمة السرّ على الجهاز فقط (قرار المستخدم): لكلّ شركة+يوزر — لدخول
    // «شركاتي» بضغطة — وفي الحسابات المحفوظة لمبدّل المدراء الفرعيّين.
    unawaited(CompanyCredsStore.upsert(sasUrl: sasUrl, username: username, password: password)
        .catchError((_) {}));
    unawaited(SavedProfilesStore.upsert(
      username: username,
      plainPassword: password,
      displayName: s.displayName,
    ).catchError((_) {}));

    if (s.requires2fa) return SasLoginOutcome.needs2fa;

    if (s.isEmployee) {
      final ok = await PermissionsService.refreshFromBackend();
      if (!ok) {
        await PermissionsService.clear();
        return SasLoginOutcome.permsFailed;
      }
    } else {
      await PermissionsService.setManagerCapabilities(
        isSuperAdmin: s.isSuperAdmin,
        canonical: s.canonicalPermissions,
      );
    }
    // مزوّد الساس (EarthLink؟) — من `/api/auth/me`. غير مُنتظَر: قائمة
    // «قوائم أخرى» تستمع لـ`ProviderService.changes` فتُحدَّث تفاعليّاً،
    // والدخول لا ينتظر نداءً إضافيّاً.
    unawaited(ProviderService.refreshFromBackend());
    unawaited(FcmService.initAfterLogin());
    return SasLoginOutcome.ok;
  }
}
