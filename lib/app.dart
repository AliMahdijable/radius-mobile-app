import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:url_launcher/url_launcher.dart';
import 'core/theme/app_theme.dart';
import 'core/router/app_router.dart';
import 'core/services/app_version_check.dart';
import 'core/services/expiry_push_service.dart';
import 'core/services/session_events.dart';
import 'providers/theme_provider.dart';
import 'providers/auth_provider.dart';

class MyApp extends ConsumerStatefulWidget {
  const MyApp({super.key});

  @override
  ConsumerState<MyApp> createState() => _MyAppState();
}

class _MyAppState extends ConsumerState<MyApp> with WidgetsBindingObserver {
  StreamSubscription<SessionExpiredEvent>? _sessionExpiredSub;
  // dialog إجباري للتحديث — يُعرض مرة واحدة لكل جلسة عشان ما نتكرر
  // كل resume.
  bool _forceUpdateShown = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Future.microtask(() {
      ref.read(authProvider.notifier).checkAuth();
    });
    _sessionExpiredSub = SessionEvents.stream.listen((event) {
      ref
          .read(authProvider.notifier)
          .handleSessionExpired(reason: event.reason);
    });
    // فحص نسخة التطبيق بالخلفية بعد ما الـwidgets تستقر. لو إصدار
    // الجهاز < min المطلوب → نعرض dialog غير قابل للإغلاق يفتح Play.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _runVersionCheck();
    });
  }

  @override
  void dispose() {
    _sessionExpiredSub?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ExpiryPushService.runExpiryCheck();
      ref.read(authProvider.notifier).syncSessionState();
      // إعادة الفحص عند رجوع التطبيق من background — لو المستخدم سار
      // للـPlay وحدّث، ما نريد نظل نطلق الـdialog.
      _forceUpdateShown = false;
      _runVersionCheck();
    }
  }

  Future<void> _runVersionCheck() async {
    final result = await AppVersionService.check();
    if (!mounted || !result.forceUpdate || _forceUpdateShown) return;
    _forceUpdateShown = true;
    final ctx = appNavigatorKey.currentContext;
    if (ctx == null) return;
    showDialog<void>(
      context: ctx,
      barrierDismissible: false,
      builder: (dialogCtx) => PopScope(
        // ما نسمح بالخروج بزر الرجوع
        canPop: false,
        child: AlertDialog(
          title: const Text(
            'تحديث ضروري',
            style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w800),
          ),
          content: const Text(
            'يتوفّر إصدار جديد من التطبيق ولا يمكن المتابعة بالإصدار الحالي.\n'
            'يرجى التحديث من Google Play للاستمرار.',
            style: TextStyle(fontFamily: 'Cairo', fontSize: 13, height: 1.6),
          ),
          actions: [
            FilledButton(
              onPressed: () async {
                final uri = Uri.tryParse(result.playUrl);
                if (uri != null) {
                  await launchUrl(uri,
                      mode: LaunchMode.externalApplication);
                }
              },
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
              child: const Text(
                'تحديث الآن',
                style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'MyServices Radius',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme(),
      darkTheme: AppTheme.darkTheme(),
      themeMode: themeMode,
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      routerConfig: router,
    );
  }
}
