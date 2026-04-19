import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:workmanager/workmanager.dart';

import '../constants/api_constants.dart';
import '../constants/app_constants.dart';
import '../../models/app_notification_model.dart';
import 'storage_service.dart';

class FcmEnableResult {
  final bool enabled;
  final bool pushLinked;
  final bool osPermissionGranted;
  final String? message;

  const FcmEnableResult({
    required this.enabled,
    required this.pushLinked,
    required this.osPermissionGranted,
    this.message,
  });
}

@pragma('vm:entry-point')
Future<void> _firebaseBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  debugPrint('FCM background message: ${message.messageId}');
}

class FcmService {
  FcmService._();

  static const String periodicSyncUniqueName = 'mysvcs_fcm_sync_v1';
  static const String periodicSyncTaskName = 'fcmTokenSync';
  static const Duration _periodicSyncFrequency = Duration(hours: 3);
  static const Duration _softResyncWindow = Duration(minutes: 30);

  static bool _initialized = false;
  static bool _tokenRefreshListenerAttached = false;
  static bool _deferredRegistrationRunning = false;
  static final FlutterLocalNotificationsPlugin _fln =
      FlutterLocalNotificationsPlugin();

  static Future<void> init() async {
    if (_initialized) return;

    await Firebase.initializeApp();
    await FirebaseMessaging.instance.setAutoInitEnabled(true);
    FirebaseMessaging.onBackgroundMessage(_firebaseBackgroundHandler);

    // إعداد local notifications لعرض الإشعارات في foreground
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings();
    await _fln.initialize(
      const InitializationSettings(android: androidInit, iOS: iosInit),
    );

    if (Platform.isAndroid) {
      const ch = AndroidNotificationChannel(
        'mysvcs_fcm',
        'إشعارات التطبيق',
        description: 'إشعارات Firebase Cloud Messaging',
        importance: Importance.high,
      );
      await _fln
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(ch);

      const appAlertsChannel = AndroidNotificationChannel(
        'mysvcs_app_alerts',
        'تنبيهات التطبيق المباشرة',
        description: 'تنبيهات الجرس المباشرة عند فتح التطبيق',
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
        showBadge: true,
      );
      await _fln
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(appAlertsChannel);
    }

    // عرض الإشعارات عندما التطبيق مفتوح (foreground)
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

    _initialized = true;
    debugPrint('✅ FCM Service initialized');
  }

  static void _handleForegroundMessage(RemoteMessage message) {
    final notification = message.notification;
    if (notification == null) return;

    _fln.show(
      notification.hashCode,
      notification.title ?? '',
      notification.body ?? '',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'mysvcs_fcm',
          'إشعارات التطبيق',
          channelDescription: 'إشعارات Firebase Cloud Messaging',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
    );
  }

  static Future<void> showAppNotificationAlert(
    AppNotificationModel notification,
  ) async {
    await init();

    await _fln.show(
      notification.id > 0 ? notification.id : notification.hashCode,
      notification.title,
      notification.body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'mysvcs_app_alerts',
          'تنبيهات التطبيق المباشرة',
          channelDescription: 'تنبيهات الجرس المباشرة عند فتح التطبيق',
          importance: Importance.max,
          priority: Priority.max,
          playSound: true,
          enableVibration: true,
          ticker: 'MyServices Radius',
          channelShowBadge: true,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBanner: true,
          presentBadge: true,
          presentList: true,
          presentSound: true,
        ),
      ),
    );
  }

  static Future<bool> _ensureOsPermission() async {
    if (Platform.isAndroid || Platform.isIOS) {
      final current = await Permission.notification.status;
      if (current.isGranted) return true;
      final requested = await Permission.notification.request();
      return requested.isGranted;
    }
    return true;
  }

  static Future<bool> hasOsPermission() async {
    if (Platform.isAndroid || Platform.isIOS) {
      final status = await Permission.notification.status;
      return status.isGranted;
    }
    return true;
  }

  static Future<String?> _tryGetFcmToken() async {
    try {
      final messaging = FirebaseMessaging.instance;
      await messaging.setAutoInitEnabled(true);
      try {
        await messaging.requestPermission(
          alert: true,
          badge: true,
          sound: true,
        );
      } catch (error) {
        debugPrint('FCM: requestPermission warning: $error');
      }

      final token = await messaging.getToken();
      debugPrint('FCM token: $token');
      return token;
    } catch (error) {
      debugPrint('FCM: getToken failed: $error');
      return null;
    }
  }

  static Future<void> _saveLastSuccessfulRegistration(String fcmToken) async {
    final prefs = await SharedPreferences.getInstance();
    final adminId = prefs.getString(AppConstants.storageAdminId);
    await prefs.setInt(
      AppConstants.storageFcmLastSyncMs,
      DateTime.now().millisecondsSinceEpoch,
    );
    await prefs.setString(AppConstants.storageFcmLastToken, fcmToken);
    if (adminId != null && adminId.isNotEmpty) {
      await prefs.setString(AppConstants.storageFcmLastAdminId, adminId);
    }
  }

  static Future<void> _clearLastSuccessfulRegistration() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(AppConstants.storageFcmLastSyncMs);
    await prefs.remove(AppConstants.storageFcmLastToken);
  }

  static Future<int> _getLastSyncMs() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(AppConstants.storageFcmLastSyncMs) ?? 0;
  }

  static Future<String?> _getLastRegisteredAdminId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(AppConstants.storageFcmLastAdminId);
  }

  static void _ensureTokenRefreshListener() {
    if (_tokenRefreshListenerAttached) return;
    FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
      unawaited(_registerSpecificToken(newToken));
    });
    _tokenRefreshListenerAttached = true;
  }

  static Future<bool> _registerSpecificToken(String fcmToken) async {
    final ok = await registerToken(fcmToken);
    if (ok) {
      await _saveLastSuccessfulRegistration(fcmToken);
    }
    return ok;
  }

  static Future<bool> _registerCurrentTokenOnce() async {
    final fcmToken = await _tryGetFcmToken();
    if (fcmToken == null || fcmToken.isEmpty) return false;
    return _registerSpecificToken(fcmToken);
  }

  static Future<bool> _forceRefreshAndRegister({String? previousToken}) async {
    final delays = <Duration>[
      Duration.zero,
      const Duration(seconds: 2),
      const Duration(seconds: 5),
    ];

    String? lastSeenToken = previousToken;
    for (final delay in delays) {
      if (delay > Duration.zero) {
        await Future<void>.delayed(delay);
      }

      try {
        await FirebaseMessaging.instance.deleteToken();
      } catch (error) {
        debugPrint('FCM: deleteToken failed during recovery: $error');
      }

      final refreshedToken = await _tryGetFcmToken();
      if (refreshedToken == null || refreshedToken.isEmpty) {
        continue;
      }

      if (lastSeenToken != null && refreshedToken == lastSeenToken) {
        debugPrint('FCM: refreshed token unchanged, retrying recovery');
      }

      if (await _registerSpecificToken(refreshedToken)) {
        return true;
      }

      lastSeenToken = refreshedToken;
    }

    return false;
  }

  static Future<bool> _registerCurrentTokenWithRecovery() async {
    final firstToken = await _tryGetFcmToken();
    if (firstToken != null &&
        firstToken.isNotEmpty &&
        await _registerSpecificToken(firstToken)) {
      return true;
    }

    debugPrint('FCM: token registration failed, forcing token refresh');
    return _forceRefreshAndRegister(previousToken: firstToken);
  }

  static void _scheduleDeferredRegistration() {
    if (_deferredRegistrationRunning) return;
    _deferredRegistrationRunning = true;
    unawaited(_runDeferredRegistration());
  }

  static Future<void> _runDeferredRegistration() async {
    const retryDelays = <Duration>[
      Duration(seconds: 3),
      Duration(seconds: 10),
      Duration(seconds: 25),
    ];

    try {
      for (final delay in retryDelays) {
        await Future<void>.delayed(delay);
        final ok = await _registerCurrentTokenWithRecovery();
        if (ok) {
          debugPrint('FCM: deferred token registration succeeded');
          return;
        }
      }
      debugPrint('FCM: deferred token registration exhausted');
    } finally {
      _deferredRegistrationRunning = false;
    }
  }

  static Future<bool> isEnabled(StorageService storage) async {
    final stored = await storage.getFcmEnabled();
    if (!stored) return false;

    final granted = await hasOsPermission();
    if (!granted) {
      await storage.setFcmEnabled(false);
      return false;
    }
    return true;
  }

  /// تسجيل التوكن في السيرفر
  static Future<bool> registerToken(String fcmToken) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(AppConstants.storageToken);
    final adminId = prefs.getString(AppConstants.storageAdminId);
    final adminUsername = prefs.getString(AppConstants.storageAdminUsername);
    if (token == null || adminId == null) {
      debugPrint('FCM register: no auth token or adminId in storage');
      return false;
    }

    final dio = Dio(BaseOptions(
      baseUrl: ApiConstants.backendUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
        'x-auth-token': token,
      },
    ));

    try {
      debugPrint(
        'FCM register request: adminId=$adminId, adminUsername=${adminUsername ?? '-'}',
      );
      final res = await dio.post(ApiConstants.fcmRegister, data: {
        'adminId': adminId,
        'adminUsername': adminUsername,
        'token': fcmToken,
        'deviceInfo': Platform.isAndroid ? 'Android' : 'iOS',
      });
      debugPrint('FCM register response: ${res.data}');
      final success = res.data?['success'] == true;
      if (!success) {
        debugPrint('FCM register rejected: ${res.data}');
      }
      return success;
    } catch (e) {
      debugPrint('FCM register error: $e');
      return false;
    } finally {
      dio.close();
    }
  }

  static Future<void> registerPeriodicSyncTask() async {
    try {
      await Workmanager().registerPeriodicTask(
        periodicSyncUniqueName,
        periodicSyncTaskName,
        frequency: _periodicSyncFrequency,
        constraints: Constraints(networkType: NetworkType.connected),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.replace,
      );
    } catch (error) {
      debugPrint('FCM periodic sync register warning: $error');
    }
  }

  static Future<void> cancelPeriodicSyncTask() async {
    try {
      await Workmanager().cancelByUniqueName(periodicSyncUniqueName);
    } catch (error) {
      debugPrint('FCM periodic sync cancel warning: $error');
    }
  }

  static Future<void> syncRegistrationIfNeeded(
    StorageService storage, {
    bool force = false,
  }) async {
    if (!await storage.getFcmEnabled()) return;
    if (!await hasOsPermission()) {
      await storage.setFcmEnabled(false);
      await cancelPeriodicSyncTask();
      return;
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    final lastSyncMs = await _getLastSyncMs();
    final currentAdminId = await storage.getAdminId();
    final lastRegisteredAdminId = await _getLastRegisteredAdminId();
    final adminChanged = currentAdminId != null &&
        currentAdminId.isNotEmpty &&
        currentAdminId != lastRegisteredAdminId;

    if (!force &&
        !adminChanged &&
        now - lastSyncMs < _softResyncWindow.inMilliseconds) {
      return;
    }

    await init();
    _ensureTokenRefreshListener();

    final ok = await _registerCurrentTokenWithRecovery();
    await registerPeriodicSyncTask();
    if (!ok) {
      _scheduleDeferredRegistration();
    }
  }

  @pragma('vm:entry-point')
  static Future<void> runBackgroundTokenSync() async {
    final storage = StorageService();
    if (!await storage.getFcmEnabled()) return;
    if (!await hasOsPermission()) {
      await storage.setFcmEnabled(false);
      await cancelPeriodicSyncTask();
      return;
    }

    await init();
    final ok = await _registerCurrentTokenWithRecovery();
    if (!ok) {
      debugPrint('FCM: background token sync failed');
    }
  }

  /// حذف التوكن من السيرفر
  static Future<void> unregisterToken() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(AppConstants.storageToken);
    final adminId = prefs.getString(AppConstants.storageAdminId);
    final adminUsername = prefs.getString(AppConstants.storageAdminUsername);
    if (token == null || adminId == null) return;

    String? fcmToken;
    try {
      fcmToken = await FirebaseMessaging.instance.getToken();
    } catch (_) {}

    final dio = Dio(BaseOptions(
      baseUrl: ApiConstants.backendUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
        'x-auth-token': token,
      },
    ));

    try {
      await dio.post(ApiConstants.fcmUnregister, data: {
        'adminId': adminId,
        'adminUsername': adminUsername,
        'token': fcmToken,
      });
    } catch (_) {}
    dio.close();
  }

  /// تفعيل FCM: طلب إذن + تسجيل التوكن
  static Future<FcmEnableResult> enable(StorageService storage) async {
    await init();
    final granted = await _ensureOsPermission();
    if (!granted) {
      await storage.setFcmEnabled(false);
      return const FcmEnableResult(
        enabled: false,
        pushLinked: false,
        osPermissionGranted: false,
        message: 'لم يتم منح إذن إشعارات الجهاز',
      );
    }

    await storage.setFcmEnabled(true);
    _ensureTokenRefreshListener();
    await registerPeriodicSyncTask();
    unawaited(syncRegistrationIfNeeded(storage, force: true));

    return FcmEnableResult(
      enabled: true,
      pushLinked: true,
      osPermissionGranted: true,
      message: 'تم تفعيل إشعارات الجهاز',
    );
  }

  /// تعطيل FCM: حذف التوكن
  static Future<void> disable(StorageService storage) async {
    await unregisterToken();
    await storage.setFcmEnabled(false);
    await cancelPeriodicSyncTask();
    await _clearLastSuccessfulRegistration();
  }

  /// عند تسجيل الدخول: إعادة تسجيل التوكن إذا كان FCM مفعل
  static Future<void> onLoggedIn(StorageService storage) async {
    await syncRegistrationIfNeeded(storage, force: true);
  }

  /// عند تسجيل الخروج: حذف التوكن
  static Future<void> onLoggedOut() async {
    await unregisterToken();
    await cancelPeriodicSyncTask();
    await _clearLastSuccessfulRegistration();
  }
}
