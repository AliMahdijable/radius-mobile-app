import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';

import '../constants/api_constants.dart';
import '../constants/app_constants.dart';
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

  static bool _initialized = false;
  static final FlutterLocalNotificationsPlugin _fln =
      FlutterLocalNotificationsPlugin();

  static Future<void> init() async {
    if (_initialized) return;

    await Firebase.initializeApp();
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
      final res = await dio.post(ApiConstants.fcmRegister, data: {
        'adminId': adminId,
        'token': fcmToken,
        'deviceInfo': Platform.isAndroid ? 'Android' : 'iOS',
      });
      debugPrint('FCM register response: ${res.data}');
      return res.data?['success'] == true;
    } catch (e) {
      debugPrint('FCM register error: $e');
      return false;
    } finally {
      dio.close();
    }
  }

  /// حذف التوكن من السيرفر
  static Future<void> unregisterToken() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(AppConstants.storageToken);
    final adminId = prefs.getString(AppConstants.storageAdminId);
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

    final fcmToken = await _tryGetFcmToken();
    if (fcmToken == null || fcmToken.isEmpty) {
      return const FcmEnableResult(
        enabled: true,
        pushLinked: false,
        osPermissionGranted: true,
        message:
            'تم تفعيل إشعارات الجهاز، لكن تعذر ربط التنبيهات الفورية على هذا الجهاز حاليًا.',
      );
    }

    final ok = await registerToken(fcmToken);
    FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
      registerToken(newToken);
    });

    return FcmEnableResult(
      enabled: true,
      pushLinked: ok,
      osPermissionGranted: true,
      message: ok
          ? 'تم تفعيل إشعارات الجهاز'
          : 'تم تفعيل إشعارات الجهاز، لكن تعذر ربط التنبيهات الفورية على هذا الجهاز حاليًا.',
    );
  }

  /// تعطيل FCM: حذف التوكن
  static Future<void> disable(StorageService storage) async {
    await unregisterToken();
    await storage.setFcmEnabled(false);
  }

  /// عند تسجيل الدخول: إعادة تسجيل التوكن إذا كان FCM مفعل
  static Future<void> onLoggedIn(StorageService storage) async {
    if (!await storage.getFcmEnabled()) return;
    if (!await hasOsPermission()) {
      await storage.setFcmEnabled(false);
      return;
    }
    await init();
    final fcmToken = await _tryGetFcmToken();
    if (fcmToken != null) {
      await registerToken(fcmToken);
      FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
        registerToken(newToken);
      });
    }
  }

  /// عند تسجيل الخروج: حذف التوكن
  static Future<void> onLoggedOut() async {
    await unregisterToken();
  }
}
