import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:local_auth/local_auth.dart';

import '../theme/colors.dart';
import '../theme/spacing.dart';
import '../theme/typography.dart';

/// Login — Soft Pastel + Premium aesthetic. Forest-green brand on cream.
/// The company logo is tinted brand via colorBlendMode so it lives in
/// the palette without needing a separate asset.
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

  @override
  void dispose() {
    _userCtrl.dispose();
    _passCtrl.dispose();
    _userFocus.dispose();
    _passFocus.dispose();
    super.dispose();
  }

  Future<void> _onLogin() async {
    HapticFeedback.lightImpact();
    setState(() => _loading = true);
    // TODO[wire-auth]: hit /api/auth/login here. For now just simulate.
    await Future<void>.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;
    setState(() => _loading = false);
    // TODO[navigate-home]: navigate to /home once shell screen exists.
  }

  Future<void> _onBiometric() async {
    HapticFeedback.selectionClick();
    final auth = LocalAuthentication();
    try {
      final ok = await auth.authenticate(
        localizedReason: 'استخدم بصمتك أو Face ID للدخول',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );
      if (!mounted) return;
      if (ok) {
        // TODO[biometric-login]: load saved token + nav to home.
      }
    } catch (_) {
      // device may not support biometrics — silent fallback to password
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(
            horizontal: Sp.xxl,
            vertical: Sp.xl,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: MediaQuery.sizeOf(context).height -
                  MediaQuery.paddingOf(context).vertical -
                  Sp.xl * 2,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: Sp.mega),
                _Logo()
                    .animate()
                    .scale(
                      begin: const Offset(0.6, 0.6),
                      end: const Offset(1, 1),
                      duration: const Duration(milliseconds: 600),
                      curve: Curves.easeOutBack,
                    )
                    .fadeIn(duration: const Duration(milliseconds: 400)),
                const SizedBox(height: Sp.xl),
                _BrandTitle()
                    .animate()
                    .fadeIn(
                      delay: const Duration(milliseconds: 200),
                      duration: const Duration(milliseconds: 400),
                    )
                    .slideY(begin: 0.1, end: 0),
                const SizedBox(height: Sp.mega),
                _FormCard(
                  userCtrl: _userCtrl,
                  passCtrl: _passCtrl,
                  userFocus: _userFocus,
                  passFocus: _passFocus,
                  obscure: _obscure,
                  loading: _loading,
                  onToggleObscure: () => setState(() => _obscure = !_obscure),
                  onLogin: _loading ? null : _onLogin,
                )
                    .animate()
                    .fadeIn(
                      delay: const Duration(milliseconds: 350),
                      duration: const Duration(milliseconds: 400),
                    )
                    .slideY(begin: 0.08, end: 0),
                const SizedBox(height: Sp.xl),
                _BiometricButton(onTap: _onBiometric).animate().fadeIn(
                      delay: const Duration(milliseconds: 500),
                      duration: const Duration(milliseconds: 400),
                    ),
                const Spacer(),
                const SizedBox(height: Sp.xl),
                _Footer(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Logo extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 120,
        height: 120,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(R.xl),
          boxShadow: [
            BoxShadow(
              color: AppColors.brand.withValues(alpha: 0.12),
              blurRadius: 32,
              offset: const Offset(0, 16),
            ),
          ],
        ),
        padding: const EdgeInsets.all(Sp.lg),
        // Logo tinted brand-green so it lives in the palette.
        child: Image.asset(
          'assets/images/logo.png',
          color: AppColors.brand,
          colorBlendMode: BlendMode.srcIn,
          fit: BoxFit.contain,
        ),
      ),
    );
  }
}

class _BrandTitle extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          'MyServices Radius',
          textAlign: TextAlign.center,
          style: AppType.title(color: AppColors.textHi),
        ),
        const SizedBox(height: Sp.xs),
        Text(
          'إدارة ذكية لمزود الإنترنت',
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
    required this.onToggleObscure,
    required this.onLogin,
  });

  final TextEditingController userCtrl;
  final TextEditingController passCtrl;
  final FocusNode userFocus;
  final FocusNode passFocus;
  final bool obscure;
  final bool loading;
  final VoidCallback onToggleObscure;
  final VoidCallback? onLogin;

  @override
  Widget build(BuildContext context) {
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
            label: 'اسم المستخدم',
            child: TextField(
              controller: userCtrl,
              focusNode: userFocus,
              textInputAction: TextInputAction.next,
              onSubmitted: (_) => passFocus.requestFocus(),
              style: AppType.input(color: AppColors.textHi),
              decoration: _inputDecoration(hint: 'مثلاً ali300'),
            ),
          ),
          const SizedBox(height: Sp.lg),
          _LabeledInput(
            label: 'كلمة المرور',
            child: TextField(
              controller: passCtrl,
              focusNode: passFocus,
              obscureText: obscure,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => onLogin?.call(),
              style: AppType.input(color: AppColors.textHi),
              decoration: _inputDecoration(
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
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton(
              onPressed: () {},
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: Sp.sm,
                  vertical: Sp.xs,
                ),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                'نسيت كلمة المرور؟',
                style: AppType.link(color: AppColors.brand),
              ),
            ),
          ),
          const SizedBox(height: Sp.lg),
          _PrimaryButton(label: 'دخول', loading: loading, onTap: onLogin),
        ],
      ),
    );
  }

  InputDecoration _inputDecoration({required String hint, Widget? suffix}) {
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
        borderSide: const BorderSide(color: AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(R.md),
        borderSide: const BorderSide(color: AppColors.border),
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
                'دخول بالبصمة أو Face ID',
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
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        'v2.0  •  جميع الحقوق محفوظة',
        style: AppType.muted(color: AppColors.textLow),
      ),
    );
  }
}
