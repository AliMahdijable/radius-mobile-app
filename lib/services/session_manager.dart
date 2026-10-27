import 'dart:async';
import 'notification_router.dart';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/cards_api.dart';
import '../api/device_config_api.dart';
import '../api/device_probe_api.dart';
import '../api/el_deposit_password.dart';
import '../api/sales_api.dart';
import '../api/self_deposit_api.dart';
import '../api/subscribers_api.dart';
import '../api/whatsapp_api.dart';
import 'account_service.dart';
import 'active_company.dart';
import 'ai_assistant_state.dart';
import 'alerts_service.dart';
import 'auth_storage.dart';
import 'badge_service.dart';
import 'dashboard_cache.dart';
import 'subscribers_offline_cache.dart';
import 'device_alerts_service.dart';
import 'employee_session.dart';
import 'fiber/fiber_monitor.dart';
import 'fiber/fiber_store.dart';
import 'fiber/fiber_watch.dart';
import 'fcm_service.dart';
import 'inbox_service.dart';
import 'linked_companies.dart';
import 'olt_name_cache.dart';
import 'merged_mode.dart';
import 'permissions_service.dart';
import 'provider_service.dart';
import 'saved_profiles_store.dart';
import 'subscriber_usage_store.dart';

/// Central place that wipes every in-memory + persistent cache tied to
/// a user session. Called from:
///
///   • Manual logout (SettingsScreen._logout)
///   • Auto-kick on 401 (api_client._refreshAndRetry)
///   • Before starting a new session (LoginScreen._doLogin) — protects
///     against the case where user 401-kicked mid-flow, only Auth got
///     cleared, then a different admin signs in on top of the previous
///     admin's leftover in-memory data.
///
/// Order matters:
///   1. In-memory API caches first — sync, instant, no await.
///   2. Async persistent stores — parallelized via Future.wait
///      (previously ran sequentially, wasting ~150ms during login).
///   3. FCM unregister LAST because it hits network; missed unregister
///      just means old device gets a few extra push messages once,
///      never a permanent leak.
///   4. Auth wipe — last so anything above that reads auth still works.
class SessionManager {
  SessionManager._();

  /// Full wipe — safe to call multiple times, idempotent.
  ///
  /// * `unregisterFcm` = true (default) — call before proper logout.
  ///   Pass false when we're about to LOGIN (no previous FCM to strip).
  /// * `clearAuth` = true (default) — wipes AuthStorage. Pass false
  ///   from LoginScreen (about to write a new session anyway).
  static Future<void> clearAllSessionData({
    bool unregisterFcm = true,
    bool clearAuth = true,
  }) async {
    // 1) In-memory API caches — SYNC, instant. Fire before any await
    //    so subsequent screens never see prior admin's list/config data.
    _guardSync(
        'SubscribersApi.clearAllCaches', () => SubscribersApi.clearAllCaches());
    _guardSync('DeviceConfigApi.clearAllCaches',
        () => DeviceConfigApi.clearAllCaches());
    _guardSync('AlertsService.reset', () => AlertsService.reset());
    // §١٢: عدّاد الكارتات المتبقّية — لا يرى المدير التالي مخزون سابقه.
    _guardSync('CardsState.reset', () => CardsState.reset());
    // 2026-08-28 (Google 2027 audit CRITICAL): WhatsApp templates cache
    // كان يسرّب بين المدراء على نفس الجهاز (10د TTL). أي إرسال آلي بعد
    // login جديد قد يستعمل قوالب المدير السابق.
    _guardSync('WhatsAppApi.clearCaches', () => WhatsAppApi.clearCaches());
    // باسورد إيداع ايرث لنك المحفوظ (حالته لا نصّه) — لا يرى المدير التالي حالة سابقه.
    _guardSync('ElDepositPassword.reset', () => ElDepositPassword.reset());
    // استهلاك المشتركين (القائمة) — أرقام حساب المدير السابق.
    _guardSync('SubscriberUsageStore.reset', () => SubscriberUsageStore.reset());
    // «شحن رصيد الصفحة» — وسائل الدفع ورصيد صفحة المدير السابق. (عمليّات زين
    // كاش المعلّقة **لا** تُمسح هنا: خروجٌ وسط الدفع لا يمحو ماله —
    // SelfDepositPendingStore يحفظها لصاحبها وحده.)
    _guardSync('SelfDepositState.reset', () => SelfDepositState.reset());
    // «المبيعات» — حالة المفتاح لحساب المدير السابق.
    _guardSync('SalesState.reset', () => SalesState.reset());
    // المساعد الذكيّ — حالته (الحصّة، القفل) وآخر أخطاء الخادم المحفوظة
    // لـ«اشرحلي»: لا يرى المدير التالي حال سابقه ولا يُشرح له خطؤه.
    _guardSync('AiAssistantState.reset', () => AiAssistantState.reset());
    // شركات الحساب (زرّ «تبديل الشركة» في الرئيسيّة) — لا يرى الحساب التالي
    // شركات سابقه، والجلسة الجديدة تسأل من جديد.
    _guardSync('LinkedCompanies.reset', () => LinkedCompanies.reset());
    // «كل الشركات»: لا يرث أحدٌ وضع سابقه ولا مراجعه ولا قوائم شركاته.
    _guardSync('MergedMode.reset', () => MergedMode.reset());
    // شبكة الألياف: مراقبات الأولتات تتوقّف (لا يُقرأ أولت سابقه ولا يُبلَّغ عن عطله)، وتخطيطه يفرغ من الذاكرة.
    _guardSync('FiberWatch.stop', () => FiberWatch.stop());
    _guardSync('FiberMonitor.resetAll', () => FiberMonitor.resetAll());
    _guardSync('FiberStore.reset', () => FiberStore.reset());

    // 2) Async persistent stores — PARALLEL via Future.wait.
    //    Previously sequential: each waited on the last (~40ms × 4).
    //    Now bounded by the slowest single write, not the sum.
    await Future.wait([
      _guardAsync(
          'DeviceProbeApi.clearAllCaches', DeviceProbeApi.clearAllCaches()),
      _guardAsync('BadgeService.clear', BadgeService.clear()),
      _guardAsync('InboxService.clear', InboxService.clear()),
      _guardAsync('PermissionsService.clear', PermissionsService.clear()),
      // مزوّد الساس (EarthLink؟) — لا يرى المدير التالي شاشات سابقه الخاصّة.
      _guardAsync('ProviderService.clear', ProviderService.clear()),
      // الشركة المفتوحة (شريط MainShell) — لا تبقى بعد الخروج، والدخول
      // التالي يكتب شركته بعد هذا المسح (SasLoginFlow).
      _guardAsync('ActiveCompany.clear', ActiveCompany.clear()),
      // علامة «موظّف مباشر» (دخول ايرث لنك بلا حساب) — تتبع الجلسة، وتُذكَر
      // في الذاكرة فيُوجَّه الطرد/الخروج لشاشة دخول الموظّف لا البوّابة.
      // `clearAuth: false` = قبل دخولٍ جديد ⇒ الجلسة القادمة تحدّد الوجهة.
      _guardAsync('EmployeeSession.clear',
          EmployeeSession.clear(newSession: !clearAuth)),
      // 2026-08-18: device alerts + dedup map + OS notifications — كانت
      // تبقى للمدير التالي فتظهر تنبيهات أجهزة السابق.
      _guardAsync(
          'DeviceAlertsService.reset', DeviceAlertsService.instance.reset()),
      // 2026-08-28 (Google 2027 audit HIGH): docstring في dashboard_cache
      // ينصّ صراحةً "call on logout" لكن ما استُدعيت من قبل — المدير
      // الجديد كان يرى KPIs المدير السابق حتى تعود شبكته بأرقام جديدة.
      _guardAsync('DashboardCache.clear', DashboardCache.clear()),
      // 2026-09-13: نسخة المشتركين المحفوظة على القرص (تعمل بلا نت).
      // ⚠️ **منتظَرة لا مُطلَقة**: لو مات التطبيق بعد الخروج مباشرةً
      // والملفّ لم يُحذف، يفتحه المدير التالي فيرى مشتركي سابقه. وقد
      // حدث تسريبان كهذا سلفاً (قوالب الواتساب · مؤشّرات اللوحة)،
      // وسطراهما فوق شاهدان.
      _guardAsync(
          'SubscribersOfflineCache.clear', SubscribersOfflineCache.clear()),
      // وعلى القرص: أسماء المشتركين المربوطة بأجهزتهم لا تبقى بعد الخروج، ولا أسماء واجهات أولتات الحساب.
      if (clearAuth) _guardAsync('FiberStore.clear', FiberStore.clear()),
      if (clearAuth) _guardAsync('OltNameCache.clear', OltNameCache.clear()),
    ]);

    // 3) FCM unregister (network — only on real logout).
    if (unregisterFcm) {
      await _guardAsync('FcmService.unregister', FcmService.unregister());
      // لا تُفتح شاشةٌ لحسابٍ انتهت جلسته بنقرةٍ محفوظة.
      NotificationRouter.reset();
    }

    // 4) Auth wipe — last so anything above that reads auth still works.
    if (clearAuth) {
      await _guardAsync('AuthStorage.clear', AuthStorage.clear());
    }
  }

  // ───────────── الترقية من الكلاسيك (٣.٠.٠) ─────────────

  /// علامة «فُحصت بقايا الكلاسيك» — في SharedPreferences لا الخزنة عمداً:
  /// تُمسح مع حذف التطبيق (والخزنة لا تُمسح على iOS، وتُزامَن عبر iCloud)،
  /// فتثبيتٌ جديد يفحص من جديد.
  static const _kClassicChecked = 'pro.classic_session_checked_v3';

  /// أوّل إقلاعٍ بعد التحديث من التطبيق الكلاسيكيّ (MyServices Radius ≤ ٢.٢.٨،
  /// معرّف الحزمة نفسه): الخزنة تحمل جلسة ساسٍ أصدرها خادم الكلاسيك
  /// (rad.mysvcs.net) بلا حساب Pro. البوّابة تتجاوزها اليوم (لا حساب جاهز)،
  /// لكن ما إن يدخل المستخدم حسابه ويُغلق التطبيق قبل اختيار شركة حتى يفتح
  /// الإقلاع التالي MainShell بتوكن الكلاسيك وبلا شركة نشطة. فتُمسح مرّةً واحدة.
  ///
  /// «بقايا كلاسيك» = توكن ساس **و** لا مستخدم Firebase **و** ليست جلسة موظّفٍ
  /// مباشر. الكلاسيك لم يعرف Firebase Auth ولا الموظّف المباشر، ونسخة Pro لا
  /// تستعمل جلسة ساسٍ بلا أحدهما — فلا تُمسّ جلسة Pro سليمة أبداً.
  ///
  /// Firebase غير جاهز ← لا يُحكم الآن (لا نميّز Pro من كلاسيك) ويُعاد الفحص
  /// في الإقلاع التالي. لا يُلغى تسجيل FCM: توكن الساس للخادم الآخر، وتوكن
  /// الجهاز يتجدّد مع أوّل دخول. الإعدادات (المظهر، اللغة، الطباعة) والحسابات
  /// المحفوظة تبقى؛ يُمسح مرجع «العودة للأصل» وحده لأنّه جزءٌ من الجلسة.
  ///
  /// لا يرمي أبداً: أيّ فشلٍ يترك الإقلاع يمضي كما كان.
  static Future<void> migrateClassicSessionOnce() async {
    SharedPreferences prefs;
    try {
      prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_kClassicChecked) == true) return;
    } catch (e) {
      _log('classic.prefs', e);
      return;
    }
    if (!AccountService.available) return; // يُعاد في الإقلاع التالي
    try {
      if (AccountService.currentUser == null) {
        final token = await AuthStorage.readToken();
        if (token != null && token.isNotEmpty) {
          final direct = await EmployeeSession.restore();
          if (!direct) {
            if (kDebugMode) debugPrint('[SessionManager] مسح جلسة كلاسيك قديمة');
            await clearAllSessionData(unregisterFcm: false);
            await _guardAsync(
                'SavedProfilesStore.clearOriginal', SavedProfilesStore.clearOriginal());
          }
        }
      }
      await prefs.setBool(_kClassicChecked, true);
    } catch (e) {
      // قراءة الخزنة رمت (عطل KeyStore) — بلا علامة: يُعاد الفحص لاحقاً.
      _log('classic.migrate', e);
    }
  }

  static void _guardSync(String tag, void Function() fn) {
    try {
      fn();
    } catch (e) {
      _log(tag, e);
    }
  }

  static Future<void> _guardAsync(String tag, Future<void> fut) async {
    try {
      await fut;
    } catch (e) {
      _log(tag, e);
    }
  }
}

void _log(String tag, Object err) {
  if (kDebugMode) debugPrint('[SessionManager] $tag: $err');
}
