import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import '../constants/api_constants.dart';
import '../constants/app_constants.dart';
import 'fcm_service.dart';
import 'storage_service.dart';

const String _wmUniqueName = 'mysvcs_expiry_v1';
const String _wmTaskName = 'expirySubscriberCheck';

final FlutterLocalNotificationsPlugin _fln = FlutterLocalNotificationsPlugin();

/// Throttle HTTP polling (foreground + background) to avoid hammering the API.
const int _fetchThrottleMs = 20 * 60 * 1000;

int? _remainingDaysInt(dynamic days) {
  if (days == null) return null;
  if (days is int) return days;
  if (days is double) return days.round();
  return int.tryParse(days.toString().trim());
}

@pragma('vm:entry-point')
void expiryPushCallbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    // Android passes `taskName`; iOS may pass `uniqueName` instead.
    if (task == _wmTaskName || task == _wmUniqueName) {
      try {
        await ExpiryPushService.init();
        await ExpiryPushService.runExpiryCheck();
      } catch (e, st) {
        debugPrint('ExpiryPushService background: $e\n$st');
      }
    }
    if (task == FcmService.periodicSyncTaskName ||
        task == FcmService.periodicSyncUniqueName) {
      try {
        await FcmService.runBackgroundTokenSync();
      } catch (e, st) {
        debugPrint('FcmService background sync: $e\n$st');
      }
    }
    return Future.value(true);
  });
}

/// Local OS notifications for near-expiry (1–3 days) and expired-today (0 days).
/// At most one summary notification per category per local calendar day (dedup in prefs).
class ExpiryPushService {
  ExpiryPushService._();

  static bool _initialized = false;
  static bool _workmanagerInitialized = false;

  static Future<void> init() async {
    if (_initialized) return;
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings();
    await _fln.initialize(
      const InitializationSettings(android: androidInit, iOS: iosInit),
    );
    if (Platform.isAndroid) {
      const ch = AndroidNotificationChannel(
        'mysvcs_expiry',
        'تنبيهات الاشتراك',
        description: 'قرب انتهاء الاشتراك أو انتهائه اليوم',
        importance: Importance.high,
      );
      await _fln
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(ch);
    }
    _initialized = true;
  }

  static Future<void> ensureWorkmanagerInitialized() async {
    if (_workmanagerInitialized) return;
    await Workmanager().initialize(
      expiryPushCallbackDispatcher,
      isInDebugMode: kDebugMode,
    );
    _workmanagerInitialized = true;
  }

  /// Request OS notification permission (Android 13+ / iOS).
  static Future<bool> requestOsPermission() async {
    if (Platform.isAndroid) {
      final st = await Permission.notification.request();
      return st.isGranted;
    }
    if (Platform.isIOS) {
      final impl = _fln.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      final ok = await impl?.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          ) ??
          false;
      return ok;
    }
    return true;
  }

  static Future<void> registerPeriodicTask() async {
    await ensureWorkmanagerInitialized();
    await Workmanager().registerPeriodicTask(
      _wmUniqueName,
      _wmTaskName,
      frequency: const Duration(hours: 6),
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.replace,
    );
  }

  static Future<void> cancelPeriodicTask() async {
    await Workmanager().cancelByUniqueName(_wmUniqueName);
  }

  /// After successful login: reschedule background job if user opted in.
  static Future<void> onLoggedIn(StorageService storage) async {
    if (!await storage.getPushExpiryOutsideEnabled()) return;
    await init();
    await registerPeriodicTask();
  }

  static Future<void> onLoggedOut() async {
    await cancelPeriodicTask();
  }

  /// Enable/disable from settings (must be logged in for background fetch).
  static Future<void> setEnabled(StorageService storage, bool enabled) async {
    await storage.setPushExpiryOutsideEnabled(enabled);
    if (enabled) {
      await init();
      await registerPeriodicTask();
      await runExpiryCheck();
    } else {
      await cancelPeriodicTask();
    }
  }

  static String _todayLocal() =>
      DateFormat('yyyy-MM-dd').format(DateTime.now());

  /// Fetch subscribers and show at most one «near» and one «expired» summary per local day.
  static Future<void> runExpiryCheck() async {
    final prefs = await SharedPreferences.getInstance();
    if (!(prefs.getBool(AppConstants.storagePushExpiryOutsideEnabled) ??
        false)) {
      return;
    }

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final lastFetch = prefs.getInt(AppConstants.storagePushLastFetchMs) ?? 0;
    if (nowMs - lastFetch < _fetchThrottleMs) {
      return;
    }
    await prefs.setInt(AppConstants.storagePushLastFetchMs, nowMs);

    final token = prefs.getString(AppConstants.storageToken);
    final adminId = prefs.getString(AppConstants.storageAdminId);
    if (token == null || adminId == null) return;

    final exp = prefs.getString(AppConstants.storageTokenExpiry);
    if (exp != null) {
      final expDt = DateTime.tryParse(exp);
      if (expDt != null && !expDt.isAfter(DateTime.now().toUtc())) {
        return;
      }
    }

    final dio = Dio(BaseOptions(
      baseUrl: ApiConstants.backendUrl,
      connectTimeout: const Duration(seconds: 25),
      receiveTimeout: const Duration(seconds: 25),
      headers: {
        'Accept': 'application/json',
        'Authorization': 'Bearer $token',
        'x-auth-token': token,
      },
    ));

    final Response res;
    try {
      res = await dio.get(
        '${ApiConstants.subscribersWithPhones}?adminId=$adminId',
      );
    } catch (_) {
      return;
    } finally {
      dio.close();
    }

    final data = res.data;
    if (data is! Map || data['success'] != true) return;
    final list = data['data'];
    if (list is! List) return;

    int near = 0;
    int expired = 0;
    int overdue = 0;
    for (final raw in list) {
      if (raw is! Map) continue;
      final sub = Map<String, dynamic>.from(raw);
      final d = _remainingDaysInt(sub['remaining_days']);
      if (d != null && d >= 1 && d <= 3) near++;
      if (d == 0) expired++;
      if (d != null && d < 0) overdue++;
    }

    final today = _todayLocal();
    const androidDetails = AndroidNotificationDetails(
      'mysvcs_expiry',
      'تنبيهات الاشتراك',
      channelDescription: 'قرب الانتهاء وانتهى اليوم',
      importance: Importance.high,
      priority: Priority.high,
    );
    const iosDetails = DarwinNotificationDetails();
    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    if (near > 0 &&
        prefs.getString(AppConstants.storagePushLastNearNotifDay) != today) {
      await _fln.show(
        91001,
        'قرب انتهاء الاشتراك',
        near == 1
            ? 'مشترك واحد ضمن 3 أيام من الانتهاء.'
            : '$near مشتركين ضمن 3 أيام من الانتهاء.',
        details,
      );
      await prefs.setString(AppConstants.storagePushLastNearNotifDay, today);
    }

    if (expired > 0 &&
        prefs.getString(AppConstants.storagePushLastExpiredNotifDay) !=
            today) {
      await _fln.show(
        91002,
        'انتهى الاشتراك اليوم',
        expired == 1
            ? 'مشترك واحد انتهى اشتراكه اليوم.'
            : '$expired مشتركين انتهى اشتراكهم اليوم.',
        details,
      );
      await prefs.setString(
          AppConstants.storagePushLastExpiredNotifDay, today);
    }

    if (overdue > 0 &&
        prefs.getString(AppConstants.storagePushLastOverdueNotifDay) !=
            today) {
      await _fln.show(
        91003,
        'مشتركون منتهية اشتراكاتهم',
        overdue == 1
            ? 'مشترك واحد منتهي الاشتراك.'
            : '$overdue مشتركين منتهية اشتراكاتهم.',
        details,
      );
      await prefs.setString(
          AppConstants.storagePushLastOverdueNotifDay, today);
    }
  }
}
