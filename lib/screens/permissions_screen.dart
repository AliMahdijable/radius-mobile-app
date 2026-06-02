import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:local_auth/local_auth.dart';
import 'package:permission_handler/permission_handler.dart';

import '../theme/colors.dart';
import '../theme/spacing.dart';
import '../theme/typography.dart';
import 'home_placeholder.dart';

/// One-time setup screen shown after the first successful login.
/// Asks for two OS-level permissions:
///   1. Notifications (FCM-style push)
///   2. Biometric (Face ID / Touch ID)
/// Each row reflects its live status. "متابعة" forwards to home; user can
/// skip permissions and grant them later from settings.
class PermissionsScreen extends StatefulWidget {
  const PermissionsScreen({super.key});

  @override
  State<PermissionsScreen> createState() => _PermissionsScreenState();
}

enum _PermStatus { unknown, granted, denied, requesting }

class _PermissionsScreenState extends State<PermissionsScreen> {
  _PermStatus _notifStatus = _PermStatus.unknown;
  _PermStatus _bioStatus = _PermStatus.unknown;
  bool _bioAvailable = true;

  @override
  void initState() {
    super.initState();
    _refreshStatus();
  }

  Future<void> _refreshStatus() async {
    final notif = await Permission.notification.status;
    final auth = LocalAuthentication();
    bool canBio = false;
    try {
      canBio = await auth.canCheckBiometrics && await auth.isDeviceSupported();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _notifStatus = notif.isGranted ? _PermStatus.granted : _PermStatus.denied;
      _bioAvailable = canBio;
      _bioStatus = canBio ? _PermStatus.unknown : _PermStatus.denied;
    });
  }

  Future<void> _requestNotifications() async {
    HapticFeedback.selectionClick();
    setState(() => _notifStatus = _PermStatus.requesting);
    final res = await Permission.notification.request();
    if (!mounted) return;
    setState(() => _notifStatus =
        res.isGranted ? _PermStatus.granted : _PermStatus.denied);
    if (res.isPermanentlyDenied) {
      _showOpenSettingsSnack();
    }
  }

  Future<void> _requestBiometric() async {
    HapticFeedback.selectionClick();
    setState(() => _bioStatus = _PermStatus.requesting);
    final auth = LocalAuthentication();
    try {
      final ok = await auth.authenticate(
        localizedReason: 'فعّل بصمتك أو Face ID لتسجيل دخول أسرع لاحقاً',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );
      if (!mounted) return;
      setState(() =>
          _bioStatus = ok ? _PermStatus.granted : _PermStatus.denied);
    } catch (_) {
      if (!mounted) return;
      setState(() => _bioStatus = _PermStatus.denied);
    }
  }

  void _showOpenSettingsSnack() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'تم رفض الإذن. افتح إعدادات النظام لتفعيله يدوياً.',
          style: AppType.button(color: Colors.white),
        ),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(
          label: 'الإعدادات',
          textColor: Colors.white,
          onPressed: openAppSettings,
        ),
        margin: const EdgeInsets.all(Sp.lg),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(R.md),
        ),
      ),
    );
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
              _PermissionRow(
                icon: Icons.notifications_active_rounded,
                title: 'إشعارات النظام',
                body:
                    'لتنبيهك بانتهاء اشتراك مشترك، تسديد دين، أو ربط واتساب — حتى لو التطبيق مغلق.',
                status: _notifStatus,
                onRequest: _requestNotifications,
              )
                  .animate()
                  .fadeIn(
                    delay: const Duration(milliseconds: 150),
                    duration: const Duration(milliseconds: 350),
                  )
                  .slideY(begin: 0.05, end: 0),
              const SizedBox(height: Sp.lg),
              _PermissionRow(
                icon: Icons.fingerprint_rounded,
                title: 'بصمة / Face ID',
                body: _bioAvailable
                    ? 'دخول سريع بدون كتابة كلمة المرور في كل مرة.'
                    : 'الجهاز لا يدعم البصمة. يمكنك الاستمرار بدون.',
                status: _bioStatus,
                onRequest: _bioAvailable ? _requestBiometric : null,
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
              const SizedBox(height: Sp.lg),
            ],
          ),
        ),
      ),
    );
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
          style: AppType.title(color: AppColors.textHi).copyWith(fontSize: 24),
        ),
        const SizedBox(height: Sp.xs),
        Text(
          'فعّل الإذونات التالية لتعمل بشكل أفضل. يمكنك تخطّيها وتفعيلها لاحقاً من الإعدادات.',
          style: AppType.subtitle(color: AppColors.textMid).copyWith(height: 1.6),
        ),
      ],
    );
  }
}

class _PermissionRow extends StatelessWidget {
  const _PermissionRow({
    required this.icon,
    required this.title,
    required this.body,
    required this.status,
    required this.onRequest,
  });

  final IconData icon;
  final String title;
  final String body;
  final _PermStatus status;
  final VoidCallback? onRequest;

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
              _StatusBadge(status: status),
            ],
          ),
          const SizedBox(height: Sp.md),
          Text(body,
              style: AppType.subtitle(color: AppColors.textMid)
                  .copyWith(height: 1.55)),
          const SizedBox(height: Sp.md),
          if (status != _PermStatus.granted)
            _RowButton(
              label: status == _PermStatus.requesting
                  ? 'جاري الطلب...'
                  : 'تفعيل',
              loading: status == _PermStatus.requesting,
              enabled: onRequest != null && status != _PermStatus.requesting,
              onTap: onRequest,
            ),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});
  final _PermStatus status;

  @override
  Widget build(BuildContext context) {
    final (label, color, icon) = switch (status) {
      _PermStatus.granted => ('مفعّلة', AppColors.brand, Icons.check_rounded),
      _PermStatus.denied => ('غير مفعّلة', AppColors.textLow, Icons.circle_outlined),
      _PermStatus.requesting => ('...', AppColors.textMid, Icons.more_horiz_rounded),
      _PermStatus.unknown => ('—', AppColors.textLow, Icons.circle_outlined),
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
              style:
                  AppType.muted(color: color).copyWith(fontSize: 11)),
        ],
      ),
    );
  }
}

class _RowButton extends StatelessWidget {
  const _RowButton({
    required this.label,
    required this.loading,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final bool loading;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: Material(
        color: enabled
            ? AppColors.brand.withValues(alpha: 0.1)
            : AppColors.surfaceInput,
        borderRadius: BorderRadius.circular(R.md),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: enabled ? onTap : null,
          child: Center(
            child: loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.brand,
                    ),
                  )
                : Text(label,
                    style: AppType.button(
                            color: enabled
                                ? AppColors.brand
                                : AppColors.textLow)
                        .copyWith(fontSize: 14)),
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
