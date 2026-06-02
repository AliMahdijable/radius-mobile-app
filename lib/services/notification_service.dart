import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

/// Result of the platform permission ask. Distinguishes the three
/// outcomes we need to drive the UI:
///   - granted:        iOS / Android said yes.
///   - userDenied:     The OS *showed* the popup and the user said no.
///                     Treat as "ask again later via settings".
///   - silentlyBlocked: The OS *did not* show a popup — meaning iOS
///                     remembered a previous denial OR there's no
///                     enrolled push entitlement. Same UX: send to
///                     settings, but show a clearer message because
///                     the user never saw a prompt.
enum NotifPermissionResult { granted, userDenied, silentlyBlocked }

class NotificationService {
  NotificationService._();

  static bool _firebaseAvailable = false;

  /// Called from main() AFTER Firebase.initializeApp() succeeds (or
  /// fails). Lets the rest of the service know whether to use the
  /// Firebase path or fall back.
  static void markFirebaseReady(bool ready) {
    _firebaseAvailable = ready;
    if (kDebugMode) {
      debugPrint('NotificationService: firebase ready = $ready');
    }
  }

  /// Asks for notification permission. Tries Firebase Messaging first
  /// (the exact path v1 uses) and falls back to permission_handler if
  /// Firebase isn't configured on this build.
  static Future<NotifPermissionResult> request() async {
    final beforeStatus = await Permission.notification.status;
    final wasPossiblyFirstAsk =
        !beforeStatus.isGranted && !beforeStatus.isLimited;

    if (_firebaseAvailable) {
      try {
        final settings = await FirebaseMessaging.instance.requestPermission(
          alert: true,
          badge: true,
          sound: true,
        );
        return _classify(settings.authorizationStatus, wasPossiblyFirstAsk);
      } catch (e) {
        if (kDebugMode) {
          debugPrint('NotificationService: firebase request threw $e');
        }
        // fall through to permission_handler
      }
    }

    // Fallback: permission_handler. Same underlying iOS API.
    final status = await Permission.notification.request();
    if (status.isGranted) return NotifPermissionResult.granted;
    // If iOS *would* have shown a popup and still came back denied, the
    // user picked deny; otherwise iOS silently blocked.
    return wasPossiblyFirstAsk
        ? NotifPermissionResult.userDenied
        : NotifPermissionResult.silentlyBlocked;
  }

  static NotifPermissionResult _classify(
    AuthorizationStatus s,
    bool wasPossiblyFirstAsk,
  ) {
    if (s == AuthorizationStatus.authorized ||
        s == AuthorizationStatus.provisional) {
      return NotifPermissionResult.granted;
    }
    // Same heuristic as above: a true first-time ask shows UI; if we
    // were already denied iOS skips UI and returns denied immediately.
    return wasPossiblyFirstAsk
        ? NotifPermissionResult.userDenied
        : NotifPermissionResult.silentlyBlocked;
  }

  /// Whether the OS currently considers us authorized — used by the
  /// permissions screen to render the badge state on first render.
  static Future<bool> isAuthorized() async {
    if (_firebaseAvailable) {
      try {
        final s =
            await FirebaseMessaging.instance.getNotificationSettings();
        return s.authorizationStatus == AuthorizationStatus.authorized ||
            s.authorizationStatus == AuthorizationStatus.provisional;
      } catch (_) {/* fall through */}
    }
    final s = await Permission.notification.status;
    return s.isGranted;
  }

  /// Opens the OS Settings app for this app's notification settings.
  /// Same call for both branches.
  static Future<void> openSettings() => openAppSettings();
}
