import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app.dart';
import 'core/services/expiry_push_service.dart';
import 'core/services/fcm_service.dart';
import 'core/utils/platform_utils.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase Messaging + WorkManager متاحان فقط على Android/iOS. على Windows
  // و macOS و Linux نتجاوزهما — التطبيق يبقى يشتغل بدون push (المستخدم
  // يفتح التطبيق مباشرة).
  if (PlatformUtils.supportsPushNotifications) {
    // نلفّ تهيئة FCM بـtry/catch — لو فشل Firebase أو الأذونات أو
    // workmanager لأي سبب (مثل GoogleService-Info.plist غير مُسجَّل في
    // Xcode على iOS) لا نريد أن ينطلق exception ويترك الشاشة بيضاء.
    // التطبيق يستمر بلا push وهذا أفضل من crash كامل.
    try {
      await FcmService.init();
      await ExpiryPushService.init();
      await ExpiryPushService.ensureWorkmanagerInitialized();
    } catch (e, st) {
      debugPrint('⚠️ FCM/push init failed (continuing without push): $e');
      debugPrint('$st');
    }
  }

  // SystemChrome لـmobile فقط — على desktop ما يوجد status bar.
  if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ));
  }

  runApp(
    const ProviderScope(
      child: MyApp(),
    ),
  );
}
