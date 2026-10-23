import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../api/auth_api.dart';
import '../services/account_service.dart';
import '../services/auth_storage.dart';
import '../services/biometric_service.dart';
import '../services/employee_session.dart';
import '../services/fcm_service.dart';
import '../services/permissions_service.dart';
import '../services/provider_service.dart';
import '../services/session_manager.dart';
import '../theme/colors.dart';
// permissions_screen is gone — biometric guard runs inline, notification
// permission is offered from the app-permissions settings screen.
import '../theme/spacing.dart';
import '../theme/typography.dart';
import 'main_shell.dart';
import 'account/account_gate_screen.dart';
import 'account/employee_login_screen.dart';
import 'desktop/desk_auth_frame.dart';

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
    //
    // ٢٠٢٦-٠٩-٢٢ — `_route` يقرأ ثلاث قيمٍ من الخزنة بلا حماية، وقراءة
    // الخزنة ترمي عند عطل KeyStore. والرمية هنا لا تُظهر خطأً ولا تنقل
    // إلى شاشة: الـsplash يبقى معلّقاً للأبد بشعارٍ ودوّارة. المخرج
    // الآمن شاشة الدخول — الجلسة قد تكون سليمة، لكنّ بابها يُفتح باليد
    // خيرٌ من بابٍ لا يُفتح.
    try {
      await _route();
    } catch (e, st) {
      if (kDebugMode) debugPrint('🔴 توجيه الإقلاع: $e\n$st');
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => EmployeeSession.routeToEmployeeLogin &&
                  (EmployeeSession.isActive || !AccountService.isReady)
              ? const EmployeeLoginScreen()
              : const AccountGateScreen(),
        ),
      );
    }
  }

  /// Fire-and-forget: يتحقّق من انتهاء الـtoken ويجدّد لو منتهي.
  /// كنّا await هنا → splash يعلق حتى 20 ثانية لو الشبكة بطيئة.
  /// الآن unawaited: splash يمشي فوراً؛ لو token منتهي، api_client
  /// interceptor يعمل refresh + retry تلقائياً على أوّل request في
  /// Dashboard (لا فرق في السلوك النهائي، سرعة ملموسة أفضل).
  ///
  /// والـFuture المُرجَع يكتمل حين يصير التوكن صالحاً (أو تنتهي المحاولة):
  /// `/api/auth/me` يتخطّاه المعترض، فلا يُسأل قبله ([ProviderService.refreshOnColdStart]).
  /// الإقلاع نفسه لا ينتظره.
  Future<void> _refreshIfExpiredInBackground() {
    Future<void> run() async {
      final expiryStr = await AuthStorage.readTokenExpiry();
      final expiry = expiryStr == null ? null : DateTime.tryParse(expiryStr);
      final now = DateTime.now().toUtc();
      final shouldRefresh = expiry == null ||
          !expiry.toUtc().isAfter(now.add(const Duration(minutes: 2)));
      if (!shouldRefresh) return;
      await AuthApi.refreshToken();
    }

    return run();
  }

  Future<void> _route() async {
    // ٣.٠.٠: أوّل إقلاعٍ بعد التحديث من الكلاسيك — جلسة ساسٍ قديمة بلا حساب
    // Pro تُمسح مرّةً واحدة قبل قراءة الجلسة أدناه (التفصيل عند الدالّة).
    // بسقفٍ زمنيّ: خزنةٌ متعثّرة لا تعلّق الشعار — الإقلاع يمضي بلا هجرة.
    try {
      await SessionManager.migrateClassicSessionOnce()
          .timeout(const Duration(seconds: 6));
    } catch (e) {
      if (kDebugMode) debugPrint('🟠 هجرة الكلاسيك: $e');
    }
    if (!mounted) return;

    // Perf 2026-08-05: كانت 3 storage reads متتالية (~180ms).
    // الآن بالتوازي — نطلقها ثم نستقبل نتائجها. أنظف من Future.wait
    // مع types مختلطة (String? / bool / bool). التوفير ~120-160ms.
    final tokenFuture = AuthStorage.readToken();
    final autoLoginFuture = AuthStorage.isAutoLoginEnabled();
    final permsShownFuture = AuthStorage.hasShownPermissions();
    final directEmployeeFuture = EmployeeSession.restore();

    final token = await tokenFuture;
    final autoLogin = await autoLoginFuture;
    final permsShown = await permsShownFuture;
    final directEmployee = await directEmployeeFuture;
    if (!mounted) return;

    final Widget next;
    // Pro: موظّف ايرث لنك دخل مباشرةً (يوزر + كلمة سرّ) — لا حساب إيميل له
    // ولا اشتراك، فلا يمرّ بالبوّابة أبداً: جلسته وحدها تكفي. وتوكنه لا
    // يُجدَّد؛ أوّل ٤٠١ يطرده إلى شاشة دخول الموظّف (MainShell).
    final direct = directEmployee && token != null && token.isNotEmpty;
    // Pro البند ٤: جلسة الساس وحدها لا تكفي — يلزم حساب إيميل جاهز (مؤكَّد).
    // بدونه (تحديثٌ من نسخةٍ بلا طبقة الحساب، أو خروجٌ من الحساب) ← البوّابة.
    if (token != null && token.isNotEmpty && autoLogin && (direct || AccountService.isReady)) {
      // Perf 2026-08-05: unawaited بدل await — لو token منتهي،
      // api_client interceptor يعالج 401 → refresh → retry تلقائياً
      // على أوّل request في Dashboard. Splash يفتح فوراً بدل انتظار
      // 20 ثانية لـSAS4 لو الشبكة بطيئة.
      final tokenReady = _refreshIfExpiredInBackground();

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
            MaterialPageRoute(
              builder: (_) =>
                  direct ? const EmployeeLoginScreen() : const AccountGateScreen(),
            ),
          );
          return;
        }
      }

      // مطلب 2026-06-12: نُعيد جلب صلاحيات الـactor حتى لو الـauto-login
      // (الـadmin قد يكون عدّل صلاحيات الموظف من الويب بين فتح وفتح).
      // الكاش يُحدّث؛ لو فشل الجلب يبقى الكاش الأخير.
      unawaited(PermissionsService.refreshFromBackend());
      // + المزوّد وقدرات **كلّ** مدير (SAS4 الأصل والبعيد، ايرث لنك، FTTH) من
      // /api/auth/me — كانت لايرث لنك وحده، فمفتاحٌ أخرجه الخادم من خريطة الساس
      // (reports.financial، ١٨ أكتوبر) بقي يقفل رصيد المدير الفرعيّ حتى يخرج
      // ويدخل. والموظّف يُسأل أيضاً (مزوّده)، وقدراته لا تُمَسّ (الشروط هناك).
      unawaited(ProviderService.refreshOnColdStart(tokenReady));
      // auto-login جلسة قديمة — نُسجّل FCM (idempotent).
      unawaited(FcmService.initAfterLogin());
      next = const MainShell();
    } else if (direct ||
        (EmployeeSession.routeToEmployeeLogin && !AccountService.isReady)) {
      // موظّفٌ مباشر: جلسته قائمة بلا دخولٍ تلقائيّ، أو انتهت قبل الإقلاع
      // (خروج/طرد) ولا حساب إيميل جاهز على الجهاز ← شاشة دخوله هو، لا شاشة
      // حسابٍ لا يملكه. ورجوعه منها يختار طريق الحساب صراحةً.
      next = const EmployeeLoginScreen();
    } else if (token != null && token.isNotEmpty && !autoLogin) {
      // User has logged in before but chose not to be remembered.
      next = const AccountGateScreen();
    } else if (permsShown) {
      // Returning user with no session: straight to login.
      next = const AccountGateScreen();
    } else {
      // First-ever launch.
      next = const AccountGateScreen();
    }

    // بلا هذا الحارس: لو غادر المستخدم الشاشة أثناء التحميل أعلاه
    // (أو أُعيد بناء الجذر) رمى `Navigator.of` على سياق ميّت.
    if (!mounted) return;
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
    return DeskAuthLayout.wrap(context, Scaffold(
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
              'MyServices Pro',
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
    ));
  }
}
