import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../api/account_api.dart';
import '../api/api_client.dart';
import '../core/platform/app_platform.dart';
import '../models/app_notification.dart';
import 'account_service.dart';
import 'auth_storage.dart';
import 'desktop_push_service.dart';
import 'inbox_service.dart';
import 'app_version.dart';

/// FCM lifecycle: تسجيل/إلغاء توكن + معالجة الرسائل.
///
/// **متى تُستدعى:**
/// * `initAfterLogin()` — بعد `AuthStorage.saveSession()` مباشرة.
///   تُسجّل الـtoken لدى backend + تُركّب handlers الـforeground/opened.
/// * `unregister()` — قبل `AuthStorage.clear()` (logout).
///
/// **Handlers:**
/// * `onMessage` (foreground): يضيف للـinbox + يستدعي `onNotification`.
/// * `onMessageOpenedApp` (background tap): يضيف للـinbox + يستدعي
///   `onTap` (للـrouting).
/// * `getInitialMessage` (killed → tapped): نفس onMessageOpenedApp.
///
/// **Background messages** (killed/background بلا tap): OS يعرضها
/// كnotification نظام. الـinbox ما يستلمها إلا لو المستخدم فتح الـapp
/// وضغطها.
///
/// **thread-safety:** كل الـmutations على InboxService في الـmain isolate.
class FcmService {
  FcmService._();

  /// callback عند وصول إشعار foreground — الـUI يستعمله لعرض banner.
  /// null = لا banner (بس inbox).
  static void Function(AppNotification)? onForegroundNotification;

  /// callback عند tap إشعار (background→foreground أو killed→foreground).
  /// الـUI يستعمله للـrouting.
  static void Function(AppNotification)? onNotificationTap;

  /// حالة التركيب — نتفادى تسجيل مضاعف عند hot-reload.
  static bool _handlersRegistered = false;
  static StreamSubscription<RemoteMessage>? _onMessageSub;
  static StreamSubscription<RemoteMessage>? _onOpenedSub;
  static StreamSubscription<String>? _tokenRefreshSub;

  /// آخر token مُسجّل. نستعمله لتفادي إعادة الإرسال بلا داعٍ.
  static String? _lastRegisteredToken;

  /// آخر تسجيلٍ للشركة المفتوحة «المدير|التوكن» (٤ نوفمبر): التوكن نفسه بعد تبديل الشركة يُسجَّل لها من جديد — كان التكرار
  /// بالتوكن وحده فيبقى الهاتف للشركة السابقة حتى يُعاد تشغيل التطبيق، فيصله دفعها ونقرته تفتح شاشة المفتوحة.
  static String? _lastRegisteredKey;

  /// «إشعارات كلّ شركاتي» (٤ نوفمبر): التوكن مسجَّلٌ للحساب «uid|التوكن» — فيصل الهاتف دفع كلّ شركات الحساب باسمها.
  static String? _lastAccountKey;
  static String? _lastAccountToken;

  /// منفذ الاختبار: حساب Pro على الجهاز (Firebase uid) — null = لا حساب (موظّفٌ مباشر).
  @visibleForTesting
  static String? Function() accountUid = () => AccountService.currentUser?.uid;

  @visibleForTesting
  static Future<void> debugRegister(String token) => _registerToken(token);

  @visibleForTesting
  static Future<void> debugUnregisterAccount() => _unregisterAccount();

  @visibleForTesting
  static void debugReset() {
    _lastRegisteredToken = null;
    _lastRegisteredKey = null;
    _lastAccountKey = null;
    _lastAccountToken = null;
    accountUid = () => AccountService.currentUser?.uid;
  }

  /// يجب استدعاؤها بعد نجاح تسجيل الدخول وحفظ الجلسة. آمنة الاستدعاء
  /// المتكرر (idempotent).
  static Future<void> initAfterLogin() async {
    // الحاسبة: لا FCM فيها (firebase_messaging بلا تطبيقٍ لويندوز) — إشعارات الخادم نفسها تُقرأ من DesktopPushService.
    if (AppPlatform.isDesktop) {
      unawaited(DesktopPushService.start());
      return;
    }
    // 1) اطلب الإذن — على Android يُمنح تلقائياً < API 33.
    try {
      final settings = await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      if (kDebugMode) {
        debugPrint('FCM permission: ${settings.authorizationStatus}');
      }
    } catch (e) {
      if (kDebugMode) debugPrint('FCM requestPermission failed: $e');
      // لا نُوقف — العملية تكمّل حتى لو الـpermission في وضع مبهم.
    }

    // 2) foreground presentation options (iOS)
    if (Platform.isIOS) {
      try {
        await FirebaseMessaging.instance
            .setForegroundNotificationPresentationOptions(
          alert: true,
          badge: true,
          sound: true,
        );
      } catch (_) {}
    }

    // 3) اجلب الـtoken وسجّله في backend
    await _fetchAndRegisterToken();

    // 4) استمع لتحديث الـtoken (يتجدّد أحياناً بعد fresh install/reinstall)
    _tokenRefreshSub ??=
        FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
      if (kDebugMode) debugPrint('FCM token refreshed');
      await _registerToken(newToken);
    });

    // 5) ركّب handlers مرة واحدة
    if (!_handlersRegistered) {
      _handlersRegistered = true;

      // foreground
      _onMessageSub = FirebaseMessaging.onMessage.listen(_handleForeground);

      // ضغط الإشعار بعد ما كان الـapp بالخلفية
      _onOpenedSub =
          FirebaseMessaging.onMessageOpenedApp.listen(_handleOpenedApp);

      // ضغط الإشعار وقت الـapp مقفول → يجيبنا مع initial message
      // (نستدعيه بعد أول build عشان يوصل onNotificationTap اللي انضبطت).
      // نأخّر بـmicrotask حتى الـUI يبني نفسه ويسجّل الـcallback.
      Future.microtask(() async {
        try {
          final initial = await FirebaseMessaging.instance.getInitialMessage();
          if (initial != null) {
            await _handleOpenedApp(initial);
          }
        } catch (e) {
          if (kDebugMode) debugPrint('FCM getInitialMessage failed: $e');
        }
      });
    }
  }

  /// عند تسجيل الخروج: نُلغي التوكن من backend + نطفي الـstreams.
  static Future<void> unregister() async {
    if (AppPlatform.isDesktop) {
      await DesktopPushService.stop();
      return;
    }
    final token = _lastRegisteredToken;
    if (token != null && token.isNotEmpty) {
      try {
        await ApiClient.dio.post<Map<String, dynamic>>(
          '/api/fcm/unregister',
          data: {'token': token},
        );
      } on DioException catch (e) {
        if (kDebugMode) {
          debugPrint(
              'FCM unregister failed: ${e.response?.statusCode} ${e.message}');
        }
      } catch (e) {
        if (kDebugMode) debugPrint('FCM unregister threw: $e');
      }
    }
    // «إشعارات كلّ شركاتي»: الهاتف لا يبقى للحساب بعد الخروج (هنا قبل خروج Firebase — توكن الحساب ما زال صالحاً).
    await _unregisterAccount();
    _lastRegisteredToken = null;
    _lastRegisteredKey = null;

    await _onMessageSub?.cancel();
    _onMessageSub = null;
    await _onOpenedSub?.cancel();
    _onOpenedSub = null;
    await _tokenRefreshSub?.cancel();
    _tokenRefreshSub = null;
    _handlersRegistered = false;

    // احذف الـtoken من Firebase (يمنع الجهاز يستلم إشعارات جديدة
    // للحساب المسجّل السابق).
    try {
      await FirebaseMessaging.instance.deleteToken();
    } catch (_) {}
  }

  // ────────────────────────────────────────────
  // Internal
  // ────────────────────────────────────────────

  static Future<void> _fetchAndRegisterToken() async {
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null || token.isEmpty) {
        if (kDebugMode) debugPrint('FCM: no token available');
        return;
      }
      await _registerToken(token);
    } catch (e) {
      if (kDebugMode) debugPrint('FCM getToken failed: $e');
    }
  }

  static Future<void> _registerToken(String token) async {
    await _registerCompany(token);
    await _registerAccount(token);
  }

  /// «إشعارات كلّ شركاتي»: التوكن للحساب — مرّةً لكلّ (حساب، توكن) في هذا التشغيل (والإقلاع التالي يجدّده فيبقى حديثاً).
  static Future<void> _registerAccount(String token) async {
    final uid = accountUid();
    if (uid == null || uid.isEmpty) return;
    final key = '$uid|$token';
    if (key == _lastAccountKey) return;
    if (await AccountApi.registerPush(token, _shortDeviceInfo())) {
      _lastAccountKey = key;
      _lastAccountToken = token;
    }
  }

  static Future<void> _unregisterAccount() async {
    final token = _lastAccountToken;
    _lastAccountKey = null;
    _lastAccountToken = null;
    if (token != null && token.isNotEmpty) await AccountApi.unregisterPush(token);
  }

  static Future<void> _registerCompany(String token) async {
    final adminId = await AuthStorage.readAdminId();
    final username = await AuthStorage.readAdminUsername();
    if (adminId == null || adminId.isEmpty) {
      if (kDebugMode) {
        debugPrint('FCM register skipped: no adminId in AuthStorage');
      }
      return;
    }
    final key = '$adminId|$token';
    if (key == _lastRegisteredKey) return;
    final deviceInfo = _shortDeviceInfo();
    try {
      final r = await ApiClient.dio.post<Map<String, dynamic>>(
        '/api/fcm/register',
        data: {
          'adminId': adminId,
          'adminUsername': username ?? '',
          'token': token,
          'deviceInfo': deviceInfo,
        },
      );
      final ok = r.data?['success'] == true;
      if (ok) {
        _lastRegisteredToken = token;
        _lastRegisteredKey = key;
        if (kDebugMode) debugPrint('FCM token registered ok');
      } else {
        if (kDebugMode) {
          debugPrint(
              'FCM register response: ${r.statusCode} ${r.data?['message']}');
        }
      }
    } on DioException catch (e) {
      if (kDebugMode) {
        debugPrint(
            'FCM register failed: ${e.response?.statusCode} ${e.message}');
      }
    } catch (e) {
      if (kDebugMode) debugPrint('FCM register threw: $e');
    }
  }

  static String _shortDeviceInfo() {
    final os =
        Platform.isIOS ? 'iOS' : (Platform.isAndroid ? 'Android' : 'other');
    // رقم النسخة (٣ نوفمبر): الخادم يحذف تسجيلات النسخ الأقدم من الحدّ حين يُفعَّل إجبار التحديث (scripts/app_gate.js)
    final b = AppVersion.buildNumber;
    return b.isEmpty ? '$os v2' : '$os v2 b$b';
  }

  // ────────────────────────────────────────────
  // Message handlers
  // ────────────────────────────────────────────

  static Future<void> _handleForeground(RemoteMessage m) async {
    final n = _fromRemote(m);
    await InboxService.add(n);
    onForegroundNotification?.call(n);
  }

  static Future<void> _handleOpenedApp(RemoteMessage m) async {
    final n = _fromRemote(m);
    await InboxService.add(n);
    // نُعلّمها كمقروءة تلقائياً — المستخدم رآها.
    await InboxService.markRead(n.id);
    onNotificationTap?.call(n);
  }

  static AppNotification _fromRemote(RemoteMessage m) {
    return AppNotification.fromFcmPayload(
      messageId: m.messageId,
      title: m.notification?.title,
      body: m.notification?.body,
      data: m.data,
    );
  }
}
