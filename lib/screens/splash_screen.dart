import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../api/auth_api.dart';
import '../services/auth_storage.dart';
import '../services/biometric_service.dart';
import '../theme/colors.dart';
import '../theme/spacing.dart';
import '../theme/typography.dart';
import 'main_shell.dart';
import 'login_screen.dart';
import 'permissions_screen.dart';

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

  Future<void> _decide() async {
    // A short visible delay so the splash isn't a flash-of-nothing on
    // fast launches. 350ms feels intentional, not slow.
    await Future.wait([
      Future<void>.delayed(const Duration(milliseconds: 350)),
      _route(),
    ]);
  }

  /// Calls /api/auth/refresh-token if the stored expiry is missing OR
  /// within 2 minutes of now. Failures fall through silently — the
  /// auth interceptor will catch the resulting 401 on the next request.
  Future<void> _refreshIfExpired() async {
    final expiryStr = await AuthStorage.readTokenExpiry();
    final expiry = expiryStr == null ? null : DateTime.tryParse(expiryStr);
    final now = DateTime.now().toUtc();
    final shouldRefresh = expiry == null ||
        !expiry.toUtc().isAfter(now.add(const Duration(minutes: 2)));
    if (!shouldRefresh) return;
    await AuthApi.refreshToken();
  }

  Future<void> _route() async {
    final token = await AuthStorage.readToken();
    final autoLogin = await AuthStorage.isAutoLoginEnabled();
    final permsShown = await AuthStorage.hasShownPermissions();

    if (!mounted) return;

    final Widget next;
    if (token != null && token.isNotEmpty && autoLogin) {
      // Trusted session: refresh proactively if the stored token is
      // expired or close to expiring. v1 does the same in
      // SessionRefreshService.ensureValidSession — without it, the very
      // first dashboard call would fail and the auth interceptor would
      // catch the 401, which works but causes a visible loading flash.
      await _refreshIfExpired();
      // مطلب 2026-06-11: لو الـadmin فعّل البصمة من الإعدادات،
      // نطلبها قبل الدخول. لو فشل → نرجع لشاشة login.
      final passed = await BiometricService.guard();
      if (!mounted) return;
      if (!passed) {
        next = const LoginScreen();
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => next),
        );
        return;
      }
      next = const MainShell();
    } else if (token != null && token.isNotEmpty && !autoLogin) {
      // User has logged in before but chose not to be remembered. Send
      // them back to the login form (token will be overwritten on success).
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
        transitionDuration: const Duration(milliseconds: 320),
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
                    color: AppColors.brand.withValues(alpha: 0.12),
                    blurRadius: 32,
                    offset: const Offset(0, 16),
                  ),
                ],
              ),
              padding: const EdgeInsets.all(Sp.md),
              child: Image.asset(
                'assets/images/logo.png',
                fit: BoxFit.contain,
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
            )
                .animate()
                .fadeIn(
                  delay: const Duration(milliseconds: 150),
                  duration: const Duration(milliseconds: 300),
                ),
            const SizedBox(height: Sp.huge),
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2.2,
                color: AppColors.brand,
              ),
            )
                .animate()
                .fadeIn(
                  delay: const Duration(milliseconds: 300),
                  duration: const Duration(milliseconds: 200),
                ),
          ],
        ),
      ),
    );
  }
}
