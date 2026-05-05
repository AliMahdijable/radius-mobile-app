import 'dart:developer' as dev;
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import '../constants/api_constants.dart';

/// نتيجة فحص إصدار التطبيق مقابل الـbackend.
class AppVersionCheck {
  /// لازم المستخدم يحدّث (current < min). dialog إجباري غير قابل للإلغاء.
  final bool forceUpdate;

  /// يوجد تحديث متاح بس مش إجباري (current < latest && current >= min).
  /// تنبيه ناعم قابل للتجاهل.
  final bool optionalUpdate;

  /// رابط Play Store اللي نفتحه عند ضغط "تحديث الآن".
  final String playUrl;

  /// الإصدار الحالي للجهاز (للعرض، اختياري).
  final int currentCode;

  /// الإصدار الأدنى المطلوب (للعرض).
  final int minCode;

  const AppVersionCheck({
    required this.forceUpdate,
    required this.optionalUpdate,
    required this.playUrl,
    required this.currentCode,
    required this.minCode,
  });

  static const AppVersionCheck noop = AppVersionCheck(
    forceUpdate: false,
    optionalUpdate: false,
    playUrl: '',
    currentCode: 0,
    minCode: 0,
  );
}

class AppVersionService {
  AppVersionService._();

  static const _channel = MethodChannel('com.mysvcs.rad_mysvcs/app_info');

  /// يقرأ versionCode من الـnative side عبر نفس channel اللي تستعمله شاشة
  /// الإعدادات. لو فشل (debug mode بدون native code) → 0.
  static Future<int> _currentVersionCode() async {
    try {
      final info = await _channel.invokeMapMethod<String, dynamic>('getAppVersion');
      final raw = info?['buildNumber'];
      if (raw is int) return raw;
      return int.tryParse(raw?.toString() ?? '') ?? 0;
    } catch (e) {
      dev.log('Failed to read app version: $e', name: 'VERSION');
      return 0;
    }
  }

  /// يفحص الـbackend ويقارن. صامت عند الفشل (لا نعطّل التطبيق إذا الـAPI
  /// نزل أو الشبكة سيئة) — يرجّع noop.
  static Future<AppVersionCheck> check() async {
    final dio = Dio(BaseOptions(
      baseUrl: ApiConstants.backendUrl,
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 8),
    ));
    try {
      final res = await dio.get('/api/app-version');
      final data = res.data;
      if (data is! Map || data['success'] != true) return AppVersionCheck.noop;

      final minCode = (data['min_android_version_code'] as num?)?.toInt() ?? 0;
      final latestCode = (data['latest_android_version_code'] as num?)?.toInt() ?? minCode;
      final playUrl = data['play_url']?.toString() ?? '';
      final currentCode = await _currentVersionCode();

      // currentCode == 0 يعني ما قدرنا نقرأ نسخة الجهاز — ما نزعج المستخدم
      if (currentCode == 0) return AppVersionCheck.noop;

      return AppVersionCheck(
        forceUpdate: currentCode < minCode,
        optionalUpdate: currentCode >= minCode && currentCode < latestCode,
        playUrl: playUrl,
        currentCode: currentCode,
        minCode: minCode,
      );
    } catch (e) {
      dev.log('AppVersionService.check failed: $e', name: 'VERSION');
      return AppVersionCheck.noop;
    } finally {
      dio.close();
    }
  }
}
