import 'package:easy_localization/easy_localization.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'firebase_options.dart';
import 'screens/notifications/in_app_notification_banner.dart';
import 'screens/splash_screen.dart';
import 'api/device_probe_api.dart';
import 'services/fcm_service.dart';
import 'services/inbox_service.dart';
import 'services/locale_service.dart';
import 'services/notification_service.dart';
import 'services/app_version.dart';
import 'services/badge_service.dart';
import 'services/permissions_service.dart';
import 'services/print_prefs.dart';
import 'services/theme_service.dart';
import 'theme/colors.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // easy_localization يحتاج init قبل runApp — يحمّل الـcache ويتأكّد إن
  // الـstorage جاهز حتى الـsaveLocale يشتغل من اللحظة الأولى. مطلب
  // 2026-07-12: التطبيق يدعم عربي/إنجليزي مع حفظ اختيار المستخدم.
  await EasyLocalization.ensureInitialized();

  // Load the user's saved theme preference BEFORE the first frame so we
  // don't paint a light flash then snap to dark on the next tick. The
  // notifier is read synchronously below; this `await` guarantees it
  // already holds the persisted value by the time runApp fires.
  await ThemeService.load();
  // Print prefs — يحدّد نوع القالب الافتراضي (a4/pos) لأزرار "طباعة الوصل"
  // بعد التفعيل/التسديد. يُقرأ قبل أي زر يظهر.
  await PrintPrefs.load();
  // Version — يُحمَّل مرّة من pubspec.yaml (عبر manifest) حتى الشاشات تعرضه
  // synchronously بدون كل واحدة تعمل PackageInfo.fromPlatform().
  await AppVersion.load();
  // Permissions service يعيد تحميل الـcache المخزّن من الجلسة السابقة
  // قبل أول frame عشان الـgating يشتغل صح.
  await PermissionsService.init();
  // Inbox الإشعارات — نحمّل من الـcache قبل أي رسالة FCM محتملة عند
  // startup (الـinit idempotent فآمن). الـFCM registration نفسه يصير
  // بعد login (في fcm_service.initAfterLogin).
  await InboxService.init();
  // Badge — يزامن عدد الإشعارات على أيقونة التطبيق (iOS badge + Android
  // launchers) مع InboxService.unreadCount. لولاه iOS badge يتراكم للأبد
  // بينما داخل التطبيق العدد دقيق (شكوى مستخدم 2026-07-13: 12 خارجي، 4 داخلي).
  await BadgeService.init();
  // Device probe snapshot cache — نستعيد من SharedPreferences حتى قائمة
  // المشتركين تعرض آخر حالة معروفة فوراً بلا انتظار wave جديد. مطلب
  // المستخدم 2026-07-12 "instant load".
  await DeviceProbeApi.hydrateFromPrefs();

  // Bring up Firebase with options baked into firebase_options.dart —
  // same approach as v1. This bypasses the GoogleService-Info.plist /
  // google-services.json wiring entirely, so the build doesn't depend
  // on the plist being registered in the Xcode project (most common
  // cause of TestFlight white-screen). Still wrapped just in case.
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    NotificationService.markFirebaseReady(true);
  } catch (e) {
    if (kDebugMode) {
      debugPrint('Firebase init failed: $e');
    }
    NotificationService.markFirebaseReady(false);
  }

  runApp(
    EasyLocalization(
      // اللغتان المدعومتان (نتّبع نفس ثوابت LocaleService حتى المكوّنات
      // الأخرى تعتمد نفس المصدر). Fallback عربي — لغة التطبيق الأصلية.
      supportedLocales: LocaleService.supported,
      path: 'assets/translations',
      fallbackLocale: LocaleService.arabic,
      // startLocale: مطلب المستخدم 2026-07-12 — أوّل تشغيل يبدأ عربي
      // دائماً حتى لو جهاز الـOS إنجليزي. لو المستخدم بدّل لاحقاً،
      // saveLocale يحفظ اختياره فتبقى الجلسات التالية على الإنجليزي.
      startLocale: LocaleService.arabic,
      // saveLocale: EasyLocalization يحفظ اللغة في SharedPreferences
      // ويستعيدها عند التشغيل التالي — بدون كود إضافي.
      saveLocale: true,
      child: const MyServicesApp(),
    ),
  );
}

/// المرجع الأساسي للـNavigator — نستعمله لعرض الـInAppNotificationBanner
/// من داخل FcmService.onForegroundNotification (خارج شجرة الـwidgets).
final GlobalKey<NavigatorState> _appNavigatorKey =
    GlobalKey<NavigatorState>();

class MyServicesApp extends StatefulWidget {
  const MyServicesApp({super.key});

  @override
  State<MyServicesApp> createState() => _MyServicesAppState();
}

class _MyServicesAppState extends State<MyServicesApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // اربط الـFCM foreground handler بـBanner. نستعمل الـnavigator key
    // للـcontext لأن الـcallback يشتغل خارج شجرة الـwidgets.
    FcmService.onForegroundNotification = (n) {
      final ctx = _appNavigatorKey.currentContext;
      if (ctx != null) {
        InAppNotificationBanner.show(ctx, notification: n);
      }
    };
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// عند رجوع التطبيق من الخلفيّة (foreground)، نُعيد مزامنة badge
  /// الأيقونة مع InboxService.unreadCount. iOS badge يتراكم أحياناً لو
  /// وصلت push notifications متعدّدة والمدير ما دخل التطبيق بينها.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      BadgeService.sync();
    }
  }

  /// Triggered when the OS-level light/dark setting changes. We only
  /// need to repaint when the user has opted into `system` mode — in
  /// the explicit light/dark modes the OS toggle should be ignored.
  /// Bumping the notifier value (without changing it) forces the
  /// outer `ValueListenableBuilder` to rebuild and re-resolve the
  /// `AppColors._isDark` flag against the new platform brightness.
  @override
  void didChangePlatformBrightness() {
    super.didChangePlatformBrightness();
    if (ThemeService.notifier.value == ThemeMode.system && mounted) {
      // Notify listeners by reassigning the same value — ValueNotifier
      // only fires on `!=`, so we have to force a rebuild ourselves.
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeService.notifier,
      builder: (context, mode, _) {
        // Resolve `system` mode against the platform brightness so that
        // AppColors getters and the system-chrome overlay paint with the
        // right palette right now — Theme.of(context) inside child trees
        // also matches because we pass `themeMode` to MaterialApp.
        final isDark = ThemeService.resolveIsDark(
          mode,
          WidgetsBinding.instance.platformDispatcher.platformBrightness,
        );
        AppColors.setDarkMode(isDark);

        SystemChrome.setSystemUIOverlayStyle(
          SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness:
                isDark ? Brightness.light : Brightness.dark,
            systemNavigationBarColor: AppColors.bg,
            systemNavigationBarIconBrightness:
                isDark ? Brightness.light : Brightness.dark,
          ),
        );

        return MaterialApp(
          title: 'MyServices Radius',
          debugShowCheckedModeBanner: false,
          themeMode: mode,
          theme: _buildTheme(Brightness.light),
          darkTheme: _buildTheme(Brightness.dark),
          // مطلب 2026-07-12: اللغة تُقرأ من EasyLocalization لتصبح reactive
          // على tap زر التبديل. MaterialApp نفسه يحدّد Directionality
          // تلقائياً من الـlocale (ar → rtl, en → ltr) — أزلنا builder
          // اليدوي اللي كان يجبر rtl.
          locale: context.locale,
          supportedLocales: context.supportedLocales,
          localizationsDelegates: context.localizationDelegates,
          builder: (context, child) => MediaQuery.withClampedTextScaling(
            minScaleFactor: 0.9,
            maxScaleFactor: 1.2,
            child: child ?? const SizedBox.shrink(),
          ),
          home: const SplashScreen(),
          navigatorKey: _appNavigatorKey,
        );
      },
    );
  }

  /// Build the ThemeData for a given brightness. We flip `AppColors`
  /// before reading the values so that even though `AppColors.bg` is a
  /// runtime getter, this call reflects whichever palette the caller
  /// wants — the bottom of the function restores the previous state so
  /// the outer paint sequence stays consistent.
  ThemeData _buildTheme(Brightness brightness) {
    final wasDark = AppColors.isDark;
    AppColors.setDarkMode(brightness == Brightness.dark);

    final base = brightness == Brightness.dark
        ? ThemeData.dark()
        : ThemeData.light();

    final theme = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: AppColors.bg,
      // Cairo as the default font for the WHOLE app. This catches
      // every Text widget — incl. ElevatedButton/FilledButton/
      // TextButton labels that don't pass an explicit style — so
      // we don't have to retrofit AppType.button() on each Text.
      textTheme: GoogleFonts.cairoTextTheme(base.textTheme),
      colorScheme: brightness == Brightness.dark
          ? ColorScheme.dark(
              primary: AppColors.brand,
              onPrimary: Colors.white,
              surface: AppColors.surface,
              onSurface: AppColors.textHi,
              error: AppColors.error,
            )
          : ColorScheme.light(
              primary: AppColors.brand,
              onPrimary: Colors.white,
              surface: AppColors.surface,
              onSurface: AppColors.textHi,
              error: AppColors.error,
            ),
      splashFactory: InkSparkle.splashFactory,
      // Swipe-to-back gesture — Cupertino page-transitions تعكس الاتجاه
      // تلقائياً حسب Directionality: في RTL يكون Swipe من اليمين، وفي
      // LTR (إنجليزي) من اليسار. iOS النمط الأصلي، Android نُطبّقه
      // صراحةً لنفس السلوك.
      pageTransitionsTheme: PageTransitionsTheme(
        builders: {
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.android: CupertinoPageTransitionsBuilder(),
        },
      ),
    );

    AppColors.setDarkMode(wasDark);
    return theme;
  }
}
