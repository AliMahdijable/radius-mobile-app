import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:permission_handler/permission_handler.dart';

import '../constants/api_constants.dart';
import '../constants/app_constants.dart';
import 'storage_service.dart';

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

  /// طلب إذن الإشعارات وإرجاع FCM token
  static Future<String?> requestPermissionAndGetToken() async {
    // Android 13+ يحتاج طلب إذن POST_NOTIFICATIONS بشكل runtime
    if (Platform.isAndroid) {
      final status = await Permission.notification.request();
      if (!status.isGranted) {
        debugPrint('FCM: OS notification permission denied');
        return null;
      }
    }

    final messaging = FirebaseMessaging.instance;
    final settings = await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    if (settings.authorizationStatus != AuthorizationStatus.authorized &&
        settings.authorizationStatus != AuthorizationStatus.provisional) {
      debugPrint('FCM: Firebase permission denied');
      return null;
    }

    final token = await messaging.getToken();
    debugPrint('FCM token: $token');
    return token;
  }

  /// تسجيل التوكن في السيرفر
  static Future<bool> registerToken(String fcmToken) async {
    const secure = FlutterSecureStorage();
    final token = await secure.read(key: AppConstants.storageToken);
    final adminId = await secure.read(key: AppConstants.storageAdminId);
    if (token == null || adminId == null) return false;

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
    const secure = FlutterSecureStorage();
    final token = await secure.read(key: AppConstants.storageToken);
    final adminId = await secure.read(key: AppConstants.storageAdminId);
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
  static Future<bool> enable(StorageService storage) async {
    await init();
    final fcmToken = await requestPermissionAndGetToken();
    if (fcmToken == null) return false;

    final ok = await registerToken(fcmToken);
    if (ok) {
      await storage.setFcmEnabled(true);

      // الاستماع لتحديث التوكن
      FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
        registerToken(newToken);
      });
    }
    return ok;
  }

  /// تعطيل FCM: حذف التوكن
  static Future<void> disable(StorageService storage) async {
    await unregisterToken();
    await storage.setFcmEnabled(false);
  }

  /// عند تسجيل الدخول: إعادة تسجيل التوكن إذا كان FCM مفعل
  static Future<void> onLoggedIn(StorageService storage) async {
    if (!await storage.getFcmEnabled()) return;
    await init();
    final fcmToken = await FirebaseMessaging.instance.getToken();
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
