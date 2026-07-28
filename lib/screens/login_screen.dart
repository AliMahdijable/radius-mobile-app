import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:local_auth/local_auth.dart';

import '../api/auth_api.dart';
import '../services/app_version.dart';
import '../services/auth_storage.dart';
import '../services/fcm_service.dart';
import '../services/permissions_service.dart';
import '../services/session_manager.dart';
import '../theme/colors.dart';
import '../theme/spacing.dart';
import '../theme/typography.dart';
import 'main_shell.dart';

/// Login — Soft Pastel + Premium. Wired to https://rad.mysvcs.net/api/auth/login.
/// Persists token on success via AuthStorage. On failure shows a snackbar.
///
/// Layout note: previous version used ConstrainedBox + Spacer + animations,
/// which tripped Flutter's semantics assertions during animation frames
/// (`!semantics.parentDataDirty`). Replaced with a flat Column inside
/// SingleChildScrollView — no Spacer, no min-height tricks.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _userFocus = FocusNode();
  final _passFocus = FocusNode();
  bool _obscure = true;
  bool _loading = false;
  // Default ON — matches v1 behavior. Users who don't want auto-login
  // on a shared device can untick before submitting.
  bool _remember = true;

  @override
  void dispose() {
    _userCtrl.dispose();
    _passCtrl.dispose();
    _userFocus.dispose();
    _passFocus.dispose();
    super.dispose();
  }

  void _showSnack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: AppType.button(color: Colors.white)),
        backgroundColor: error ? AppColors.error : AppColors.brand,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(R.md),
        ),
        margin: const EdgeInsets.all(Sp.lg),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _onLogin() async {
    final user = _userCtrl.text.trim();
    final pass = _passCtrl.text;
    if (user.isEmpty || pass.isEmpty) {
      _showSnack('login.enter_credentials'.tr(), error: true);
      return;
    }
    HapticFeedback.lightImpact();
    setState(() => _loading = true);
    final result = await AuthApi.login(username: user, password: pass);
    if (!mounted) return;
    setState(() => _loading = false);

    switch (result) {
      case LoginSuccess(
          :final token,
          :final adminId,
          :final adminUsername,
          :final displayName,
          :final expiresAt,
          :final requires2fa,
          :final isSuperAdmin,
          :final canAccessManagers,
          :final canAccessPackages,
          :final isEmployee,
          :final sas4Token,
        ):
        // 2026-07-14: مسح كل caches الجلسة السابقة قبل تفعيل الجديدة —
        // يحمي من رواسب admin سابق (لو 401 kick شغّل واحد ما مسح
        // الا AuthStorage + Perms). unregisterFcm=false لأن ما في
        // token لنستعمله وقت الاستدعاء + FcmService.initAfterLogin
        // بعد قليل يسجّل الحساب الجديد. clearAuth=false لأن saveSession
        // فوراً بعده يكتب الجديد.
        await SessionManager.clearAllSessionData(
          unregisterFcm: false,
          clearAuth: false,
        );
        await AuthStorage.saveSession(
          token: token,
          adminId: adminId,
          adminUsername: adminUsername,
          displayName: displayName,
          autoLogin: _remember,
          tokenExpiry: expiresAt,
          isSuperAdmin: isSuperAdmin,
          canAccessManagers: canAccessManagers,
          canAccessPackages: canAccessPackages,
          isEmployee: isEmployee,
          sas4Token: sas4Token,
        );
        if (!mounted) return;
        HapticFeedback.mediumImpact();
        if (requires2fa) {
          _showSnack('login.needs_2fa'.tr());
          // TODO[2fa-screen]: route to 2FA when that screen exists.
          return;
        }
        // Perf 2026-XX: نجلب الصلاحيات في الخلفيّة للـadmin (default =
        // كل شي مسموح، فما في fallout بصري لو الشبكة بطيئة). للـemployee
        // نستنّى الجلب لأن سلوك has() للـemployee "كل شي ممنوع افتراضياً"
        // — بدون الاستنظار سيرى قوائم فارغة لثوانٍ قبل ما تتحدّث.
        // النتيجة: admin يدخل بـ~-300ms، employee بنفس السلوك السابق.
        if (isEmployee) {
          final permsOk = await PermissionsService.refreshFromBackend();
          if (!mounted) return;
          if (!permsOk) {
            await PermissionsService.clear();
            if (!mounted) return;
            _showSnack('login.perms_fetch_failed'.tr(), error: true);
            return;
          }
        } else {
          // Admin (99% من الحالات): unrestricted افتراضياً → آمن unaware.
          // لو الجلب فشل، الـUI يبقى مسموحاً كأدمن (سلوك صحيح).
          unawaited(PermissionsService.refreshFromBackend());
        }
        // نُسجّل FCM بعد إتمام الجلسة. آمنة الفشل — ما تعطّل الدخول لو
        // Firebase غير متوفّر (fire-and-forget).
        unawaited(FcmService.initAfterLogin());
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const MainShell()),
        );
      case LoginFailure(:final message):
        HapticFeedback.heavyImpact();
        _showSnack(message, error: true);
    }
  }

  Future<void> _onBiometric() async {
    HapticFeedback.selectionClick();
    final token = await AuthStorage.readToken();
    if (token == null || token.isEmpty) {
      _showSnack('login.password_login_first'.tr(), error: true);
      return;
    }
    final auth = LocalAuthentication();
    try {
      final ok = await auth.authenticate(
        localizedReason: 'login.biometric_reason'.tr(),
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );
      if (!mounted) return;
      if (ok) {
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const MainShell()),
        );
      }
    } catch (_) {
      if (!mounted) return;
      _showSnack('login.biometric_unavailable'.tr(), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Scaffold(
      backgroundColor: AppColors.bg,
      // resizeToAvoidBottomInset lets the layout shift up when the keyboard
      // appears — without ConstrainedBox/Spacer fighting the new constraints.
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(
            horizontal: Sp.xxl,
            vertical: Sp.xxl,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: Sp.huge),
              const _Logo()
                  .animate()
                  .scale(
                    begin: const Offset(0.7, 0.7),
                    end: const Offset(1, 1),
                    duration: const Duration(milliseconds: 550),
                    curve: Curves.easeOutBack,
                  )
                  .fadeIn(duration: const Duration(milliseconds: 350)),
              const SizedBox(height: Sp.xl),
              const _BrandTitle()
                  .animate()
                  .fadeIn(
                    delay: const Duration(milliseconds: 200),
                    duration: const Duration(milliseconds: 350),
                  )
                  .slideY(begin: 0.1, end: 0),
              const SizedBox(height: Sp.huge),
              _FormCard(
                userCtrl: _userCtrl,
                passCtrl: _passCtrl,
                userFocus: _userFocus,
                passFocus: _passFocus,
                obscure: _obscure,
                loading: _loading,
                remember: _remember,
                onToggleObscure: () => setState(() => _obscure = !_obscure),
                onToggleRemember: () => setState(() => _remember = !_remember),
                onLogin: _loading ? null : _onLogin,
              )
                  .animate()
                  .fadeIn(
                    delay: const Duration(milliseconds: 320),
                    duration: const Duration(milliseconds: 350),
                  )
                  .slideY(begin: 0.06, end: 0),
              const SizedBox(height: Sp.lg),
              _BiometricButton(onTap: _onBiometric).animate().fadeIn(
                    delay: const Duration(milliseconds: 450),
                    duration: const Duration(milliseconds: 350),
                  ),
              const SizedBox(height: Sp.huge),
              const _Footer(),
              const SizedBox(height: Sp.lg),
            ],
          ),
        ),
      ),
    );
  }
}

class _Logo extends StatelessWidget {
  const _Logo();
  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    // Tint the logo brand-green using BlendMode.modulate via ColorFilter.
    // The logo is violet shapes on a transparent/white background.
    // We render it inside a ShaderMask that:
    //   1. Takes the alpha mask from the image (the violet shapes only).
    //   2. Fills the masked area with brand green.
    // White/transparent areas of the source stay transparent (white card
    // shows through), violet shapes get re-colored to brand.
    return Center(
      child: Container(
        width: 130,
        height: 130,
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
        // The PNG itself is now pre-tinted brand-green with the white
        // background converted to transparent (recolor_logo.js, 2026-06-02).
        // No runtime tinting needed — what you see is what's in the asset.
        child: Image.asset(
          'assets/images/logo.png',
          fit: BoxFit.contain,
        ),
      ),
    );
  }
}

class _BrandTitle extends StatelessWidget {
  const _BrandTitle();
  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Column(
      children: [
        Text(
          'MyServices Radius',
          textAlign: TextAlign.center,
          style: AppType.title(color: AppColors.textHi),
        ),
        const SizedBox(height: Sp.xs),
        Text(
          'login.subtitle'.tr(),
          textAlign: TextAlign.center,
          style: AppType.subtitle(color: AppColors.textMid),
        ),
      ],
    );
  }
}

class _FormCard extends StatelessWidget {
  const _FormCard({
    required this.userCtrl,
    required this.passCtrl,
    required this.userFocus,
    required this.passFocus,
    required this.obscure,
    required this.loading,
    required this.remember,
    required this.onToggleObscure,
    required this.onToggleRemember,
    required this.onLogin,
  });

  final TextEditingController userCtrl;
  final TextEditingController passCtrl;
  final FocusNode userFocus;
  final FocusNode passFocus;
  final bool obscure;
  final bool loading;
  final bool remember;
  final VoidCallback onToggleObscure;
  final VoidCallback onToggleRemember;
  final VoidCallback? onLogin;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.xl),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 60,
            offset: const Offset(0, 20),
          ),
        ],
      ),
      padding: const EdgeInsets.all(Sp.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _LabeledInput(
            label: 'login.username'.tr(),
            child: TextField(
              controller: userCtrl,
              focusNode: userFocus,
              textInputAction: TextInputAction.next,
              onSubmitted: (_) => passFocus.requestFocus(),
              style: AppType.input(color: AppColors.textHi),
              decoration: _decoration(hint: 'login.username_hint'.tr()),
            ),
          ),
          const SizedBox(height: Sp.lg),
          _LabeledInput(
            label: 'login.password'.tr(),
            child: TextField(
              controller: passCtrl,
              focusNode: passFocus,
              obscureText: obscure,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => onLogin?.call(),
              style: AppType.input(color: AppColors.textHi),
              decoration: _decoration(
                hint: '••••••',
                suffix: IconButton(
                  splashRadius: 18,
                  icon: Icon(
                    obscure
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    color: AppColors.textMid,
                    size: 20,
                  ),
                  onPressed: onToggleObscure,
                ),
              ),
            ),
          ),
          const SizedBox(height: Sp.md),
          // Forgot-password link removed per user request — admins
          // who lose their password are reset by their parent admin, no
          // public reset flow exists. Toggle stays aligned to RTL start.
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: _RememberToggle(
              value: remember,
              onChanged: onToggleRemember,
            ),
          ),
          const SizedBox(height: Sp.lg),
          _PrimaryButton(
            label: 'login.sign_in'.tr(),
            loading: loading,
            onTap: onLogin,
          ),
        ],
      ),
    );
  }

  InputDecoration _decoration({required String hint, Widget? suffix}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: AppType.input(color: AppColors.textLow),
      filled: true,
      fillColor: AppColors.surfaceInput,
      suffixIcon: suffix,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: Sp.lg,
        vertical: Sp.md,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(R.md),
        borderSide: BorderSide(color: AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(R.md),
        borderSide: BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(R.md),
        borderSide: const BorderSide(color: AppColors.brand, width: 1.5),
      ),
    );
  }
}

class _LabeledInput extends StatelessWidget {
  const _LabeledInput({required this.label, required this.child});
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(right: Sp.xs, bottom: Sp.sm),
          child: Text(label, style: AppType.label(color: AppColors.textMid)),
        ),
        child,
      ],
    );
  }
}

class _RememberToggle extends StatelessWidget {
  const _RememberToggle({required this.value, required this.onChanged});

  final bool value;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(R.sm),
      child: InkWell(
        onTap: onChanged,
        borderRadius: BorderRadius.circular(R.sm),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Sp.sm,
            vertical: Sp.xs,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Custom check box — Material's Checkbox is too noisy here.
              AnimatedContainer(
                duration: const Duration(milliseconds: 140),
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: value ? AppColors.brand : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: value ? AppColors.brand : AppColors.borderStrong,
                    width: 1.5,
                  ),
                ),
                child: value
                    ? const Icon(Icons.check_rounded,
                        color: Colors.white, size: 14)
                    : null,
              ),
              const SizedBox(width: Sp.sm),
              Text('login.remember_me'.tr(),
                  style: AppType.link(color: AppColors.textHi)),
            ],
          ),
        ),
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
    required this.label,
    required this.loading,
    required this.onTap,
  });
  final String label;
  final bool loading;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return SizedBox(
      height: 54,
      child: Material(
        color: onTap == null ? AppColors.borderStrong : AppColors.brand,
        borderRadius: BorderRadius.circular(R.md),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Center(
            child: loading
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      color: Colors.white,
                    ),
                  )
                : Text(label, style: AppType.button(color: Colors.white)),
          ),
        ),
      ),
    );
  }
}

class _BiometricButton extends StatelessWidget {
  const _BiometricButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(R.md),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: Sp.md),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.fingerprint_rounded,
                  color: AppColors.brand, size: 22),
              const SizedBox(width: Sp.sm),
              Text(
                'login.biometric_prompt'.tr(),
                style: AppType.button(color: AppColors.brand),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer();
  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Center(
      child: Text(
        '${AppVersion.shortVersion}  •  ${'login.footer_copyright'.tr()}',
        style: AppType.muted(color: AppColors.textLow),
      ),
    );
  }
}
