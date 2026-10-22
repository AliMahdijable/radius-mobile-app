import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';

/// أين يعمل التطبيق — موضعٌ واحد لتفرّعات المنصّة حتى لا تقع نسخة ويندوز في مسارٍ
/// خاصٍّ بأندرويد/آيفون سهواً.
///
/// نسخة ويندوز (سطح المكتب) بلا: إشعارات Firebase (FCM)، تقارير أعطال Crashlytics،
/// نافذة Google الأصليّة، WebView الدفع، دليل الأسماء، رقم الأيقونة. دخول الحساب فيها
/// عبر [DesktopAccountAuth] (واجهة Firebase الرسميّة على الإنترنت) لأنّ Firebase يقول إنّ
/// نسخته لويندوز «ليست للاستعمال الحقيقيّ».
class AppPlatform {
  AppPlatform._();

  /// الاختبارات تقلبه لتجرّب تفرّعات سطح المكتب على أيّ جهاز.
  @visibleForTesting
  static bool? debugIsDesktop;

  static bool get isWindows => !kIsWeb && Platform.isWindows;

  /// نسخة سطح المكتب (ويندوز اليوم).
  static bool get isDesktop => debugIsDesktop ?? isWindows;

  /// قيمة ترويسة `x-device-label`: الخادم يعرضها في «أجهزتي» ويعدّ ios/android/windows
  /// تطبيقاً لا موقعاً. غير ويندوز كما كان حرفاً (آيفون وإلّا أندرويد).
  static String get deviceLabel {
    if (!kIsWeb && Platform.isIOS) return 'ios';
    if (isDesktop) return 'windows';
    return 'android';
  }
}
