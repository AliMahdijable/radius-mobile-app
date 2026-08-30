import 'package:easy_localization/easy_localization.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'firebase_options.dart';
import 'screens/notifications/in_app_notification_banner.dart';
import 'screens/splash_screen.dart';
import 'api/device_probe_api.dart';
import 'api/subscribers_api.dart';
import 'services/app_resumed_signal.dart';
import 'services/device_alerts_service.dart';
import 'services/fcm_service.dart';
import 'services/inbox_service.dart';
import 'services/locale_service.dart';
import 'services/manual_wa_prefs.dart';
import 'services/notification_service.dart';
import 'services/app_version.dart';
import 'services/badge_service.dart';
import 'services/permissions_service.dart';
import 'services/print_prefs.dart';
import 'services/theme_service.dart';
import 'theme/colors.dart';
import 'theme/spacing.dart';
import 'theme/typography.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // easy_localization يحتاج init قبل runApp — يحمّل الـcache ويتأكّد إن
  // الـstorage جاهز حتى الـsaveLocale يشتغل من اللحظة الأولى. مطلب
  // 2026-07-12: التطبيق يدعم عربي/إنجليزي مع حفظ اختيار المستخدم.
  //
  // هذي الوحيدة اللي تبقى منفصلة لأن runApp يعتمد على EasyLocalization
  // ككلمة widget أعلى الشجرة — لازم تكون جاهزة قبل ما ننشئه.
  await EasyLocalization.ensureInitialized();

  // Perf 2026-08-05: كل الـinits التالية مستقلّة عن بعضها — نشغّلها
  // بالتوازي عبر Future.wait. كانت متتالية (~570-1290ms شاشة سوداء
  // قبل ظهور splash). الآن الوقت = مدّة أبطأ عمليّة، مو مجموعهم.
  // كل واحدة idempotent وتكتب في storage منفصل، فلا race conditions.
  await Future.wait([
    // Theme — يحمّل تفضيل المستخدم قبل أول frame (يمنع light-flash → dark).
    ThemeService.load(),
    // Print prefs — نوع القالب الافتراضي (a4/pos) لأزرار طباعة الوصل.
    PrintPrefs.load(),
    // Version — من manifest حتى الشاشات تعرض synchronously.
    AppVersion.load(),
    // Permissions — يعيد تحميل الـcache من الجلسة السابقة للـgating.
    PermissionsService.init(),
    // Inbox — cache الإشعارات قبل أي رسالة FCM.
    InboxService.init(),
    // Badge — يزامن العدد على أيقونة التطبيق (iOS badge لا يتراكم للأبد).
    BadgeService.init(),
    // Device probe — snapshot cache لقائمة المشتركين (instant load).
    DeviceProbeApi.hydrateFromPrefs(),
    // Device alerts — client-side فقط (لا سيرفر). يحمّل الـalerts المحفوظة
    // + يهيّئ OS notifications channel. مطلوب قبل ما شاشة الأجهزة تشتغل.
    DeviceAlertsService.instance.init(),
    // 2026-08-26: تفضيل "الوضع اليدوي للواتساب" — يقرّر لو الإرسالات
    // الفرديّة تفتح واتساب المدير أو تمرّ عبر جلسة السيرفر. لازم يُقرأ
    // قبل الشاشات حتى الـchip يعرض الوضع الصحيح من اللحظة الأولى.
    ManualWaPrefs.init(),
    // Firebase — options baked في firebase_options.dart. Wrapped catchError
    // حتى TestFlight ما يصير white-screen لو plist مو registered.
    // 2026-08-05: أضفنا Crashlytics wiring داخل نفس الـchain — يبدأ
    // يجمع crashes فوراً بعد Firebase init. Zero overhead لو ما في crash.
    Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform)
        .then((_) {
      NotificationService.markFirebaseReady(true);
      // Crashlytics: كل uncaught Flutter error يُرسل تلقائياً
      FlutterError.onError =
          FirebaseCrashlytics.instance.recordFlutterFatalError;
      // Crashlytics: كل uncaught async error يُرسل تلقائياً
      PlatformDispatcher.instance.onError = (error, stack) {
        FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
        return true;
      };
      // Debug mode: نعطّل الإرسال حتى لا نضيف noise أثناء التطوير
      FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(!kDebugMode);
    }).catchError((e) {
      if (kDebugMode) debugPrint('Firebase init failed: $e');
      NotificationService.markFirebaseReady(false);
    }),
  ]);

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
final GlobalKey<NavigatorState> _appNavigatorKey = GlobalKey<NavigatorState>();

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

  /// عند رجوع التطبيق من الخلفيّة (foreground):
  ///   1. مزامنة badge الأيقونة مع InboxService.unreadCount — iOS badge
  ///      يتراكم أحياناً لو وصلت push notifications متعدّدة والمدير ما
  ///      دخل التطبيق بينها.
  ///   2. إلغاء كاش قائمة المشتركين (TTL=45s) — لضمان أن الشاشات اللي
  ///      تجلب بعد الـresume تحصل على بيانات طازة من الـbackend حتى لو
  ///      الغياب كان أقل من 45 ثانية.
  ///   3. bump للـAppResumedSignal — كل شاشة تجلب بيانات (Dashboard،
  ///      SubscriberDetail، إلخ) تستمع لهذا الـtick وتنفّذ refresh صامت.
  ///      يعالج bug: بعد رجوع التطبيق من الخلفيّة، البيانات المعروضة
  ///      كانت stale لأن initState فقط يجلب مرّة واحدة (v1 كان يعالجها
  ///      عبر WidgetsBindingObserver على HomeScreen).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      BadgeService.sync();
      SubscribersApi.invalidateListCache();
      AppResumedSignal.bump();
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

    final base =
        brightness == Brightness.dark ? ThemeData.dark() : ThemeData.light();

    final theme = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: AppColors.bg,
      // Cairo as the default font for the WHOLE app. Perf 2026-08-05:
      // كان GoogleFonts.cairoTextTheme يفتح network fetch → text flash.
      // الآن apply(fontFamily: 'Cairo') يستعمل الـfont المُضمَّن في
      // assets (see pubspec.yaml fonts section). Offline من اللحظة
      // الأولى، لا flash.
      textTheme: base.textTheme.apply(fontFamily: 'Cairo'),
      colorScheme: brightness == Brightness.dark
          ? ColorScheme.dark(
              primary: AppColors.brand,
              onPrimary: AppColors.onBrand,
              surface: AppColors.surface,
              onSurface: AppColors.textHi,
              error: AppColors.error,
            )
          : ColorScheme.light(
              primary: AppColors.brand,
              onPrimary: AppColors.onBrand,
              surface: AppColors.surface,
              onSurface: AppColors.textHi,
              error: AppColors.error,
            ),
      // ═══ حوارات التأكيد ═══
      // 37 حواراً موزّعاً على 20 ملفّاً كانت ترث ثيم Material الافتراضي:
      // نصف قطر 28 وخطّ Roboto-metrics وأزرار خارج السلّم. تنسيقها هنا
      // مرّة واحدة أرخص وأأمن من إعادة كتابة 37 موضعاً، ويشمل ما يُضاف
      // مستقبلاً تلقائيّاً.
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surfaceSheet,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(R.xl),
        ),
        insetPadding:
            const EdgeInsets.symmetric(horizontal: Sp.xxl, vertical: Sp.xxl),
        titleTextStyle: AppType.sheetTitle(),
        contentTextStyle:
            AppType.rowValue(color: AppColors.textBody).copyWith(height: 1.6),
        actionsPadding: const EdgeInsets.fromLTRB(Sp.xl, Sp.sm, Sp.xl, Sp.lg),
      ),
      // أزرار الحوارات: ارتفاع وسلّم المخطّط بدل مقاسات Material.
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, H.chip),
          padding: const EdgeInsets.symmetric(horizontal: Sp.xl),
          textStyle: AppType.button(),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(R.md),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(0, H.chip),
          padding: const EdgeInsets.symmetric(horizontal: Sp.lg),
          foregroundColor: AppColors.textBody,
          textStyle: AppType.button(),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(R.md),
          ),
        ),
      ),
      // الرسائل الطافية (SnackBar) — كانت تأخذ زوايا Material الحادّة.
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.textHi,
        contentTextStyle: AppType.body(color: AppColors.onBrand),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(R.md),
        ),
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
