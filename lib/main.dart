import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app.dart';
import 'core/services/expiry_push_service.dart';
import 'core/services/fcm_service.dart';
import 'core/utils/platform_utils.dart';

// يلفّ خطوة async في timeout + try/catch حتى لا يحجب أي init مُعلَّق
// (مثلاً Firebase Messaging على iOS ينتظر APNs token إلى الأبد لو Push
// Notifications capability ناقصة في entitlements) — يلوغ ويكمل.
Future<void> _safeStep(String name, Future<void> Function() body,
    {Duration timeout = const Duration(seconds: 8)}) async {
  try {
    await body().timeout(timeout);
  } on TimeoutException {
    debugPrint('⏰ [BOOT] $name timed out after ${timeout.inSeconds}s');
  } catch (e, st) {
    debugPrint('⚠️ [BOOT] $name failed: $e');
    debugPrint('$st');
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // SystemChrome لـmobile فقط — قبل runApp عشان يطبّق على أول رسم.
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

  // تهيئة FCM/WorkManager في الخلفية (fire-and-forget) — لا ننتظرها قبل
  // runApp. هذا النمط القياسي على iOS: التطبيق يفتح فوراً، ويظهر طلب إذن
  // الإشعارات فوق شاشة الدخول خلال ثانية أو ثانيتين (مثل WhatsApp/Telegram).
  // النتيجة: لا يوجد احتمال شاشة بيضاء بسبب تعليق FCM/APNs على iOS.
  if (PlatformUtils.supportsPushNotifications) {
    unawaited(_safeStep('FcmService.init', () => FcmService.init()));
    unawaited(_safeStep(
        'ExpiryPushService.init', () => ExpiryPushService.init()));
    unawaited(_safeStep('Workmanager.init',
        () => ExpiryPushService.ensureWorkmanagerInitialized()));
  }

  runApp(
    const ProviderScope(
      child: MyApp(),
    ),
  );
}
