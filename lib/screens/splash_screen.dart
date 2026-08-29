import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../api/auth_api.dart';
import '../services/auth_storage.dart';
import '../services/biometric_service.dart';
import '../services/fcm_service.dart';
import '../services/permissions_service.dart';
import '../theme/colors.dart';
// permissions_screen is gone — biometric guard runs inline, notification
// permission is offered from the app-permissions settings screen.
import '../theme/spacing.dart';
import '../theme/typography.dart';
import 'main_shell.dart';
import 'login_screen.dart';

/// First screen on launch. Decides where to route:
///   - Token + autoLogin enabled  → home (skipping login + perms)
///   - Token + autoLogin disabled → login
///   - No token                   → login
///
/// While the storage read runs we show a small branded splash with the
/// logo + spinner so the first frame isn't a jarring blank screen.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _decide();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Perf 2026-08-05: نُحمّل الـlogo في memory قبل ما يظهر على شاشات
    // الدخول والداشبورد → صور فوريّة بلا "flash of nothing".
    // precacheImage يحتاج context جاهز، لهيك في didChangeDependencies
    // مو initState.
    precacheImage(
      const AssetImage('assets/images/logo.png'),
      context,
    );
  }

  Future<void> _decide() async {
    // Perf 2026-08-05: كنّا نفرض Future.delayed(350ms) "حتى splash ما
    // يكون flash-of-nothing". الفعليّة: splash يظهر فعلاً لأن main.dart
    // يستهلك 500ms+ قبله، فالـsplash يعرض ~1s على الأقل بلا تأخير مصنّع.
    // احذفنا الـdelay → نفتح 350ms أسرع.
    await _route();
  }

  /// Fire-and-forget: يتحقّق من انتهاء الـtoken ويجدّد لو منتهي.
  /// كنّا await هنا → splash يعلق حتى 20 ثانية لو الشبكة بطيئة.
  /// الآن unawaited: splash يمشي فوراً؛ لو token منتهي، api_client
  /// interceptor يعمل refresh + retry تلقائياً على أوّل request في
  /// Dashboard (لا فرق في السلوك النهائي، سرعة ملموسة أفضل).
  void _refreshIfExpiredInBackground() {
    Future<void> run() async {
      final expiryStr = await AuthStorage.readTokenExpiry();
      final expiry = expiryStr == null ? null : DateTime.tryParse(expiryStr);
      final now = DateTime.now().toUtc();
      final shouldRefresh = expiry == null ||
          !expiry.toUtc().isAfter(now.add(const Duration(minutes: 2)));
      if (!shouldRefresh) return;
      await AuthApi.refreshToken();
    }

    unawaited(run());
  }

  Future<void> _route() async {
    // Perf 2026-08-05: كانت 3 storage reads متتالية (~180ms).
    // الآن بالتوازي — نطلقها ثم نستقبل نتائجها. أنظف من Future.wait
    // مع types مختلطة (String? / bool / bool). التوفير ~120-160ms.
    final tokenFuture = AuthStorage.readToken();
    final autoLoginFuture = AuthStorage.isAutoLoginEnabled();
    final permsShownFuture = AuthStorage.hasShownPermissions();

    final token = await tokenFuture;
    final autoLogin = await autoLoginFuture;
    final permsShown = await permsShownFuture;
    if (!mounted) return;

    final Widget next;
    if (token != null && token.isNotEmpty && autoLogin) {
      // Perf 2026-08-05: unawaited بدل await — لو token منتهي،
      // api_client interceptor يعالج 401 → refresh → retry تلقائياً
      // على أوّل request في Dashboard. Splash يفتح فوراً بدل انتظار
      // 20 ثانية لـSAS4 لو الشبكة بطيئة.
      _refreshIfExpiredInBackground();

      // Perf 2026-08-05: Fast-path — لو bio مو مفعّل أصلاً، نتجنّب
      // كل platform channels (canAuthenticate + isDeviceSupported).
      // Only spawn guard() لو المستخدم فعّلها من الإعدادات.
      final bioEnabled = await BiometricService.isEnabled();
      if (bioEnabled) {
        // Wrap بـtimeout 30 ثانية — لو المستخدم ما تفاعل، نرجع login.
        final passed = await BiometricService.guard().timeout(
          const Duration(seconds: 30),
          onTimeout: () => false,
        );
        if (!mounted) return;
        if (!passed) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const LoginScreen()),
          );
          return;
        }
      }

      // مطلب 2026-06-12: نُعيد جلب صلاحيات الـactor حتى لو الـauto-login
      // (الـadmin قد يكون عدّل صلاحيات الموظف من الويب بين فتح وفتح).
      // الكاش يُحدّث؛ لو فشل الجلب يبقى الكاش الأخير.
      unawaited(PermissionsService.refreshFromBackend());
      // auto-login جلسة قديمة — نُسجّل FCM (idempotent).
      unawaited(FcmService.initAfterLogin());
      next = const MainShell();
    } else if (token != null && token.isNotEmpty && !autoLogin) {
      // User has logged in before but chose not to be remembered.
      next = const LoginScreen();
    } else if (permsShown) {
      // Returning user with no session: straight to login.
      next = const LoginScreen();
    } else {
      // First-ever launch.
      next = const LoginScreen();
    }

    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => next,
        // Perf 2026-08-05: قصر الـfade من 320ms → 180ms.
        // لسّة يحسّ smooth، توفير 140ms.
        transitionDuration: const Duration(milliseconds: 180),
        transitionsBuilder: (_, anim, __, child) => FadeTransition(
          opacity: anim,
          child: child,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 110,
              height: 110,
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(R.lg),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.brandSoftBg,
                    blurRadius: 32,
                    offset: const Offset(0, 16),
                  ),
                ],
              ),
              padding: const EdgeInsets.all(Sp.md),
              child: Image.asset(
                'assets/images/logo.png',
                fit: BoxFit.contain,
                // 2026-08-28: cache على 320px بدل الأصل الكامل
                // (~4MB → ~200KB في imageCache)
                cacheWidth: 320,
              ),
            ).animate().scale(
                  begin: const Offset(0.85, 0.85),
                  end: const Offset(1, 1),
                  duration: const Duration(milliseconds: 400),
                  curve: Curves.easeOutBack,
                ),
            const SizedBox(height: Sp.xl),
            Text(
              'MyServices Radius',
              style: AppType.title(color: AppColors.textHi),
            ).animate().fadeIn(
                  delay: const Duration(milliseconds: 150),
                  duration: const Duration(milliseconds: 300),
                ),
            const SizedBox(height: Sp.huge),
            SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2.2,
                color: AppColors.brand,
              ),
            ).animate().fadeIn(
                  delay: const Duration(milliseconds: 300),
                  duration: const Duration(milliseconds: 200),
                ),
          ],
        ),
      ),
    );
  }
}
