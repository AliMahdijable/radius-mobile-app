import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:local_auth/local_auth.dart';
import 'package:permission_handler/permission_handler.dart';

import '../theme/colors.dart';
import '../theme/spacing.dart';
import '../theme/typography.dart';
import 'home_placeholder.dart';

/// Shown after the first successful login. Two OS permissions:
///   1. Notifications (push)
///   2. Biometric (Face ID / Touch ID)
///
/// iOS quirk: once a permission is denied, calling .request() again does
/// nothing — the system won't re-prompt. So when the live status reports
/// "denied" (or permanently denied), the button switches to "افتح الإعدادات"
/// which opens the OS app settings page.
class PermissionsScreen extends StatefulWidget {
  const PermissionsScreen({super.key});

  @override
  State<PermissionsScreen> createState() => _PermissionsScreenState();
}

enum _PermState { unknown, granted, deniedOnce, permanentlyDenied, requesting }

class _PermissionsScreenState extends State<PermissionsScreen>
    with WidgetsBindingObserver {
  _PermState _notif = _PermState.unknown;
  _PermState _bio = _PermState.unknown;
  bool _bioAvailable = true;
  String? _bioKind; // "بصمة" / "Face ID" — what the device actually has

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Re-check status when returning from system Settings.
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final notif = await Permission.notification.status;
    final auth = LocalAuthentication();
    bool canBio = false;
    String? kind;
    try {
      canBio = await auth.isDeviceSupported();
      if (canBio) {
        final available = await auth.getAvailableBiometrics();
        if (available.contains(BiometricType.face)) {
          kind = 'Face ID';
        } else if (available.contains(BiometricType.fingerprint)) {
          kind = 'البصمة';
        } else if (available.contains(BiometricType.strong) ||
            available.contains(BiometricType.weak)) {
          kind = 'البصمة';
        } else {
          // Device supports it but nothing enrolled yet.
          kind = null;
          canBio = false;
        }
      }
    } catch (_) {/* keep defaults */}

    if (!mounted) return;
    setState(() {
      _notif = _mapNotif(notif);
      _bioAvailable = canBio;
      _bioKind = kind;
      // Biometric has no permission concept — "granted" only after the
      // user successfully proves they can authenticate at least once.
      // Until then, leave it unknown.
      if (!canBio) _bio = _PermState.deniedOnce;
    });
  }

  _PermState _mapNotif(PermissionStatus s) {
    if (s.isGranted || s.isLimited || s.isProvisional) return _PermState.granted;
    if (s.isPermanentlyDenied) return _PermState.permanentlyDenied;
    if (s.isDenied || s.isRestricted) return _PermState.deniedOnce;
    return _PermState.unknown;
  }

  // ── Notification ───────────────────────────────────────────────────
  Future<void> _onNotifTap() async {
    HapticFeedback.selectionClick();
    if (_notif == _PermState.granted) return;
    if (_notif == _PermState.deniedOnce || _notif == _PermState.unknown) {
      setState(() => _notif = _PermState.requesting);
      final res = await Permission.notification.request();
      if (!mounted) return;
      setState(() => _notif = _mapNotif(res));
      return;
    }
    // permanentlyDenied → open settings; system Settings handles the rest.
    await openAppSettings();
  }

  // ── Biometric ──────────────────────────────────────────────────────
  Future<void> _onBioTap() async {
    HapticFeedback.selectionClick();
    if (_bio == _PermState.granted) return;
    if (!_bioAvailable) {
      // Likely simulator without enrolled biometric, OR a device with the
      // sensor disabled. Push them to system settings to set it up.
      await openAppSettings();
      return;
    }
    setState(() => _bio = _PermState.requesting);
    final auth = LocalAuthentication();
    try {
      final ok = await auth.authenticate(
        localizedReason: 'فعّل ${_bioKind ?? "البصمة"} لتسجيل دخول أسرع لاحقاً',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );
      if (!mounted) return;
      setState(() => _bio = ok ? _PermState.granted : _PermState.deniedOnce);
    } catch (_) {
      if (!mounted) return;
      setState(() => _bio = _PermState.deniedOnce);
    }
  }

  void _continue() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const HomePlaceholder()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Sp.xxl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: Sp.huge),
              _Header()
                  .animate()
                  .fadeIn(duration: const Duration(milliseconds: 350))
                  .slideY(begin: 0.06, end: 0),
              const SizedBox(height: Sp.huge),
              _PermCard(
                icon: Icons.notifications_active_rounded,
                title: 'إشعارات النظام',
                body:
                    'لتنبيهك بانتهاء اشتراك، تسديد دين، أو ربط واتساب — حتى لو التطبيق مغلق.',
                state: _notif,
                buttonLabel: _notifButtonLabel(),
                onTap: _onNotifTap,
              )
                  .animate()
                  .fadeIn(
                    delay: const Duration(milliseconds: 150),
                    duration: const Duration(milliseconds: 350),
                  )
                  .slideY(begin: 0.05, end: 0),
              const SizedBox(height: Sp.lg),
              _PermCard(
                icon: Icons.fingerprint_rounded,
                title: 'بصمة / Face ID',
                body: _bioAvailable
                    ? 'دخول سريع بـ${_bioKind ?? "البصمة"} بدون كتابة كلمة المرور.'
                    : 'الجهاز لا يدعم البصمة أو لم يتم تسجيلها بعد. يمكنك الاستمرار بدون.',
                state: _bio,
                buttonLabel: _bioButtonLabel(),
                onTap: _onBioTap,
              )
                  .animate()
                  .fadeIn(
                    delay: const Duration(milliseconds: 260),
                    duration: const Duration(milliseconds: 350),
                  )
                  .slideY(begin: 0.05, end: 0),
              const Spacer(),
              _ContinueButton(onTap: _continue).animate().fadeIn(
                    delay: const Duration(milliseconds: 450),
                    duration: const Duration(milliseconds: 350),
                  ),
              const SizedBox(height: Sp.sm),
              TextButton(
                onPressed: _continue,
                child: Text(
                  'تخطّى الآن',
                  style: AppType.link(color: AppColors.textMid),
                ),
              ),
              const SizedBox(height: Sp.sm),
            ],
          ),
        ),
      ),
    );
  }

  String _notifButtonLabel() {
    switch (_notif) {
      case _PermState.granted:
        return 'مفعّلة';
      case _PermState.permanentlyDenied:
        return 'افتح إعدادات النظام';
      case _PermState.requesting:
        return 'جاري الطلب...';
      case _PermState.deniedOnce:
      case _PermState.unknown:
        return 'تفعيل';
    }
  }

  String _bioButtonLabel() {
    if (!_bioAvailable) return 'افتح إعدادات النظام';
    switch (_bio) {
      case _PermState.granted:
        return 'مفعّلة';
      case _PermState.requesting:
        return 'جاري المصادقة...';
      case _PermState.deniedOnce:
      case _PermState.permanentlyDenied:
      case _PermState.unknown:
        return 'تفعيل';
    }
  }
}

class _Header extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: AppColors.brand.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(R.lg),
          ),
          alignment: Alignment.center,
          child: const Icon(Icons.shield_outlined,
              color: AppColors.brand, size: 28),
        ),
        const SizedBox(height: Sp.lg),
        Text(
          'إذونات الجهاز',
          style:
              AppType.title(color: AppColors.textHi).copyWith(fontSize: 24),
        ),
        const SizedBox(height: Sp.xs),
        Text(
          'فعّل الإذونات التالية لتعمل بشكل أفضل. يمكنك تخطّيها وتفعيلها لاحقاً.',
          style: AppType.subtitle(color: AppColors.textMid)
              .copyWith(height: 1.6),
        ),
      ],
    );
  }
}

class _PermCard extends StatelessWidget {
  const _PermCard({
    required this.icon,
    required this.title,
    required this.body,
    required this.state,
    required this.buttonLabel,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String body;
  final _PermState state;
  final String buttonLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.lg),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.all(Sp.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.brand.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(R.sm),
                ),
                child: Icon(icon, color: AppColors.brand, size: 22),
              ),
              const SizedBox(width: Sp.md),
              Expanded(
                child: Text(title,
                    style: AppType.button(color: AppColors.textHi)
                        .copyWith(fontSize: 16)),
              ),
              _StateBadge(state: state),
            ],
          ),
          const SizedBox(height: Sp.md),
          Text(body,
              style: AppType.subtitle(color: AppColors.textMid)
                  .copyWith(height: 1.55)),
          const SizedBox(height: Sp.md),
          _Button(label: buttonLabel, state: state, onTap: onTap),
        ],
      ),
    );
  }
}

class _StateBadge extends StatelessWidget {
  const _StateBadge({required this.state});
  final _PermState state;

  @override
  Widget build(BuildContext context) {
    final (label, color, icon) = switch (state) {
      _PermState.granted => ('مفعّلة', AppColors.brand, Icons.check_rounded),
      _PermState.permanentlyDenied =>
        ('بحاجة إعدادات', AppColors.error, Icons.settings_rounded),
      _PermState.deniedOnce =>
        ('غير مفعّلة', AppColors.textLow, Icons.circle_outlined),
      _PermState.requesting =>
        ('...', AppColors.textMid, Icons.more_horiz_rounded),
      _PermState.unknown =>
        ('—', AppColors.textLow, Icons.circle_outlined),
    };
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Sp.sm,
        vertical: Sp.xs,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(R.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 12),
          const SizedBox(width: 4),
          Text(label,
              style: AppType.muted(color: color).copyWith(fontSize: 11)),
        ],
      ),
    );
  }
}

class _Button extends StatelessWidget {
  const _Button({
    required this.label,
    required this.state,
    required this.onTap,
  });

  final String label;
  final _PermState state;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    if (state == _PermState.granted) return const SizedBox.shrink();
    final loading = state == _PermState.requesting;
    final danger = state == _PermState.permanentlyDenied;
    final bg = danger
        ? AppColors.error.withValues(alpha: 0.1)
        : AppColors.brand.withValues(alpha: 0.1);
    final fg = danger ? AppColors.error : AppColors.brand;

    return SizedBox(
      height: 44,
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(R.md),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: loading ? null : onTap,
          child: Center(
            child: loading
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: fg,
                    ),
                  )
                : Text(label,
                    style: AppType.button(color: fg).copyWith(fontSize: 14)),
          ),
        ),
      ),
    );
  }
}

class _ContinueButton extends StatelessWidget {
  const _ContinueButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 54,
      child: Material(
        color: AppColors.brand,
        borderRadius: BorderRadius.circular(R.md),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Center(
            child: Text('متابعة',
                style: AppType.button(color: Colors.white)),
          ),
        ),
      ),
    );
  }
}
