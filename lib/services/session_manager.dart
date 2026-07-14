import 'dart:async';

import 'package:flutter/foundation.dart';

import '../api/device_config_api.dart';
import '../api/device_probe_api.dart';
import '../api/subscribers_api.dart';
import 'alerts_service.dart';
import 'auth_storage.dart';
import 'badge_service.dart';
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
///   1. In-memory API caches first (don't need to await FCM/network).
///   2. Async persistent stores (Inbox, Perms, Auth) — awaited.
///   3. FCM unregister LAST because it hits network; missed unregister
///      just means old device gets a few extra push messages once,
///      never a permanent leak.
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
    // 1) in-memory API caches — sync
    try {
      SubscribersApi.clearAllCaches();
    } catch (e) {
      _log('SubscribersApi.clearAllCaches', e);
    }
    try {
      DeviceConfigApi.clearAllCaches();
    } catch (e) {
      _log('DeviceConfigApi.clearAllCaches', e);
    }
    try {
      await DeviceProbeApi.clearAllCaches();
    } catch (e) {
      _log('DeviceProbeApi.clearAllCaches', e);
    }
    try {
      AlertsService.reset();
    } catch (e) {
      _log('AlertsService.reset', e);
    }
    try {
      await BadgeService.clear();
    } catch (e) {
      _log('BadgeService.clear', e);
    }

    // 2) persistent per-session stores
    try {
      await InboxService.clear();
    } catch (e) {
      _log('InboxService.clear', e);
    }
    try {
      await PermissionsService.clear();
    } catch (e) {
      _log('PermissionsService.clear', e);
    }

    // 3) FCM unregister (network — after everything else)
    if (unregisterFcm) {
      try {
        await FcmService.unregister();
      } catch (e) {
        _log('FcmService.unregister', e);
      }
    }

    // 4) Auth wipe — last so anything above that reads auth still works.
    if (clearAuth) {
      try {
        await AuthStorage.clear();
      } catch (e) {
        _log('AuthStorage.clear', e);
      }
    }
  }
}

void _log(String tag, Object err) {
  if (kDebugMode) debugPrint('[SessionManager] $tag: $err');
}
