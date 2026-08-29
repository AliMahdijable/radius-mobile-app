import 'dart:async';

import 'package:flutter/foundation.dart';

import '../api/device_config_api.dart';
import '../api/device_probe_api.dart';
import '../api/subscribers_api.dart';
import '../api/whatsapp_api.dart';
import 'alerts_service.dart';
import 'auth_storage.dart';
import 'badge_service.dart';
import 'dashboard_cache.dart';
import 'device_alerts_service.dart';
import 'fcm_service.dart';
import 'inbox_service.dart';
import 'permissions_service.dart';

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
    // 2026-08-28 (Google 2027 audit CRITICAL): WhatsApp templates cache
    // كان يسرّب بين المدراء على نفس الجهاز (10د TTL). أي إرسال آلي بعد
    // login جديد قد يستعمل قوالب المدير السابق.
    _guardSync('WhatsAppApi.clearCaches', () => WhatsAppApi.clearCaches());

    // 2) Async persistent stores — PARALLEL via Future.wait.
    //    Previously sequential: each waited on the last (~40ms × 4).
    //    Now bounded by the slowest single write, not the sum.
    await Future.wait([
      _guardAsync(
          'DeviceProbeApi.clearAllCaches', DeviceProbeApi.clearAllCaches()),
      _guardAsync('BadgeService.clear', BadgeService.clear()),
      _guardAsync('InboxService.clear', InboxService.clear()),
      _guardAsync('PermissionsService.clear', PermissionsService.clear()),
      // 2026-08-18: device alerts + dedup map + OS notifications — كانت
      // تبقى للمدير التالي فتظهر تنبيهات أجهزة السابق.
      _guardAsync(
          'DeviceAlertsService.reset', DeviceAlertsService.instance.reset()),
      // 2026-08-28 (Google 2027 audit HIGH): docstring في dashboard_cache
      // ينصّ صراحةً "call on logout" لكن ما استُدعيت من قبل — المدير
      // الجديد كان يرى KPIs المدير السابق حتى تعود شبكته بأرقام جديدة.
      _guardAsync('DashboardCache.clear', DashboardCache.clear()),
    ]);

    // 3) FCM unregister (network — only on real logout).
    if (unregisterFcm) {
      await _guardAsync('FcmService.unregister', FcmService.unregister());
    }

    // 4) Auth wipe — last so anything above that reads auth still works.
    if (clearAuth) {
      await _guardAsync('AuthStorage.clear', AuthStorage.clear());
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
