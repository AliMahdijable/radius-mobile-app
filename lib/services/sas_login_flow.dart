import 'dart:async';

import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

import '../api/auth_api.dart';
import 'active_company.dart';
import 'auth_storage.dart';
import 'company_creds_store.dart';
import 'fcm_service.dart';
import 'permissions_service.dart';
import 'provider_service.dart';
import 'saved_profiles_store.dart';
import 'secure_storage_health.dart';
import 'session_manager.dart';

/// [storageFailed]: الدخول نجح في الخادم وتعذّر حفظه على الجهاز (خزنةٌ لا تُفكّ، أو خطوةٌ علِقت) —
/// يُعرض للمستخدم بدل الصمت. انظر [SasLoginFlow.completeSafely].
///
/// ولا نتيجة «يحتاج تحقّقاً بخطوتين» هنا: كود التحقّق يُكتب **قبل** أن تصير الجلسة [LoginSuccess]
/// (نافذة الكود في `SasCaptchaLogin`)، فما يصل هنا جلسةٌ كاملة دائماً.
enum SasLoginOutcome { ok, permsFailed, storageFailed }

/// ما بعد دخولٍ ناجح للساس — مكانٌ واحد لشاشة الدخول و«شركاتي».
///
/// الترتيب ملزِم (كان مكرّراً في شاشة الدخول): مسح بقايا الجلسة السابقة ←
/// حفظ الجلسة ← الصلاحيّات (الموظّف ينتظر جلبها، المدير من الساس فوراً) ←
/// FCM. والنداء لا يتنقّل بين الشاشات؛ المتّصل يقرّر حسب النتيجة.
class SasLoginFlow {
  SasLoginFlow._();

  /// [complete] محميّاً — المدخل الذي تستعمله الشاشات.
  ///
  /// 🐛 بلاغ ٢٠٢٦-١٠-١٥: كانت رميةُ [complete] (خزنة أندرويد لا تُفكّ بعد استعادة نسخةٍ احتياطيّة —
  /// [SecureStorageHealth]) تسقط خارج الشاشة: الدخول ناجحٌ في الخادم والواجهة صامتة، فيضغط المدير «دخول»
  /// مرّةً بعد مرّة (٢٤٤ دخولاً لمديرٍ واحد في يوم). الآن: رميةٌ أو تعليقٌ ← علاج الخزنة ثمّ محاولةٌ ثانية،
  /// وإلّا [SasLoginOutcome.storageFailed] برسالةٍ واضحة.
  static Future<SasLoginOutcome> completeSafely(
    LoginSuccess s, {
    required String username,
    required String? password,
    required String sasUrl,
    required bool remember,
    String? companyLabel,
    String? sasCode,
  }) async {
    Future<SasLoginOutcome> run() => complete(s,
            username: username,
            password: password,
            sasUrl: sasUrl,
            remember: remember,
            companyLabel: companyLabel,
            sasCode: sasCode)
        // خطوةٌ علِقت (إضافةٌ لا تردّ) لا تُبقي الشاشة بلا جوابٍ إلى الأبد.
        .timeout(const Duration(seconds: 20));
    try {
      return await run();
    } catch (e, st) {
      _report(e, st, 'complete');
      if (await SecureStorageHealth.healIfBroken()) {
        try {
          return await run();
        } catch (e2, st2) {
          _report(e2, st2, 'complete-after-heal');
        }
      }
      return SasLoginOutcome.storageFailed;
    }
  }

  static void _report(Object e, StackTrace st, String where) {
    if (kDebugMode) debugPrint('🔴 [SasLoginFlow] $where: $e');
    try {
      FirebaseCrashlytics.instance.recordError(e, st, reason: 'SasLoginFlow.$where', fatal: false);
    } catch (_) {/* Firebase غير مهيّأ */}
  }

  /// [companyLabel]/[sasCode]: اسم الشركة وكودها إن عرفهما المتّصل («شركاتي»
  /// أو الدليل) — لشريط الشركة أعلى الواجهة؛ غيابهما يُقدَّر ثمّ يُحسم.
  ///
  /// [password] `null`: جلسةٌ بلا كلمة سرٍّ على هذا الجهاز («استئناف الشركة» من الخادم) — لا يُكتب فوق المحفوظ شيء.
  static Future<SasLoginOutcome> complete(
    LoginSuccess s, {
    required String username,
    required String? password,
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
    if (password != null && password.isNotEmpty) {
      unawaited(CompanyCredsStore.upsert(sasUrl: sasUrl, username: username, password: password)
          .catchError((_) {}));
      unawaited(SavedProfilesStore.upsert(
        username: username,
        plainPassword: password,
        displayName: s.displayName,
      ).catchError((_) {}));
    }

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
