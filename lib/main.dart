import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'screens/splash_screen.dart';
import 'services/notification_service.dart';
import 'theme/colors.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: AppColors.bg,
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );

  // Try to bring up Firebase. Wrapped because GoogleService-Info.plist /
  // google-services.json may not be present on a fresh clone yet. If
  // it fails the app still launches — NotificationService falls back to
  // permission_handler for the OS prompt.
  try {
    await Firebase.initializeApp();
    NotificationService.markFirebaseReady(true);
  } catch (e) {
    if (kDebugMode) {
      debugPrint('Firebase init skipped: $e');
    }
    NotificationService.markFirebaseReady(false);
  }

  runApp(const MyServicesApp());
}

class MyServicesApp extends StatelessWidget {
  const MyServicesApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MyServices Radius',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        scaffoldBackgroundColor: AppColors.bg,
        colorScheme: const ColorScheme.light(
          primary: AppColors.brand,
          onPrimary: Colors.white,
          surface: AppColors.surface,
          onSurface: AppColors.textHi,
          error: AppColors.error,
        ),
        splashFactory: InkSparkle.splashFactory,
      ),
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) => Directionality(
        textDirection: TextDirection.rtl,
        child: MediaQuery.withClampedTextScaling(
          minScaleFactor: 0.9,
          maxScaleFactor: 1.2,
          child: child ?? const SizedBox.shrink(),
        ),
      ),
      home: const SplashScreen(),
    );
  }
}
