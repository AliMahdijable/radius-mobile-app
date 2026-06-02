import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:local_auth/local_auth.dart';
import 'package:permission_handler/permission_handler.dart' show openAppSettings;

import '../services/auth_storage.dart';
import '../services/notification_service.dart';
import '../theme/colors.dart';
import '../theme/spacing.dart';
import '../theme/typography.dart';
import 'main_shell.dart';

/// Round 4 rewrite — root-cause approach to the "popup never appears"
/// problem the user kept hitting:
///
///   Cause: once iOS records a notification-permission decision for a
///   bundle ID, requestAuthorization() never re-displays the popup on
///   that device. Same rule applies regardless of which Flutter package
///   wraps the call (permission_handler, firebase_messaging, anything).
///
///   What changed here:
///   1. NotificationService.request() is used instead of calling
///      permission_handler directly — same path v1 uses (Firebase
///      Messaging) when Firebase is configured.
///   2. We fire the request automatically the first time this screen
///      appears, matching v1's first-launch behavior (user said: "v1
///      shows the permission popup right when the app first opens").
///   3. We distinguish a true "user-denied" outcome (popup shown, user
///      tapped Don't Allow) from a "silently-blocked" outcome (no popup
///      because iOS remembered a previous denial). The second case gets
///      a banner explaining how to reset — that's the situation 99% of
///      our previous bug reports turned out to be.
class PermissionsScreen extends StatefulWidget {
  const PermissionsScreen({super.key});

  @override
  State<PermissionsScreen> createState() => _PermissionsScreenState();
}

enum _State { idle, requesting, granted, userDenied, silentlyBlocked }

class _PermissionsScreenState extends State<PermissionsScreen>
    with WidgetsBindingObserver {
  _State _notif = _State.idle;
  _State _bio = _State.idle;
  bool _bioAvailable = true;
  String? _bioKind;
  bool _autoFired = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _refresh() async {
    final granted = await NotificationService.isAuthorized();
    final auth = LocalAuthentication();
    bool canBio = false;
    String? kind;
    try {
      canBio = await auth.isDeviceSupported();
      if (canBio) {
        final list = await auth.getAvailableBiometrics();
        if (list.contains(BiometricType.face)) {
          kind = 'Face ID';
        } else if (list.contains(BiometricType.fingerprint) ||
            list.contains(BiometricType.strong) ||
            list.contains(BiometricType.weak)) {
          kind = 'البصمة';
        } else {
          kind = null;
          canBio = false;
        }
      }
    } catch (_) {/* keep defaults */}

    if (!mounted) return;
    setState(() {
      if (granted) _notif = _State.granted;
      _bioAvailable = canBio;
      _bioKind = kind;
    });

    // Auto-fire the OS request the FIRST time this screen mounts (after
    // a tiny pause so the user sees the screen come up first). This
    // matches v1's "popup on first launch" UX. The auto-fire fires once
    // per screen lifetime; manual taps still work afterward.
    if (!_autoFired && !granted) {
      _autoFired = true;
      Future<void>.delayed(const Duration(milliseconds: 600), _requestNotif);
    }
  }

  Future<void> _requestNotif() async {
    if (!mounted || _notif == _State.granted || _notif == _State.requesting) return;
    HapticFeedback.selectionClick();
    setState(() => _notif = _State.requesting);
    final res = await NotificationService.request();
    if (!mounted) return;
    setState(() {
      _notif = switch (res) {
        NotifPermissionResult.granted => _State.granted,
        NotifPermissionResult.userDenied => _State.userDenied,
        NotifPermissionResult.silentlyBlocked => _State.silentlyBlocked,
      };
    });
  }

  Future<void> _requestBio() async {
    if (!_bioAvailable) {
      await openAppSettings();
      return;
    }
    HapticFeedback.selectionClick();
    setState(() => _bio = _State.requesting);
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
      setState(() => _bio = ok ? _State.granted : _State.userDenied);
    } catch (_) {
      if (!mounted) return;
      setState(() => _bio = _State.userDenied);
    }
  }

  Future<void> _continue() async {
    await AuthStorage.markPermissionsShown();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const MainShell()),
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
              _Card(
                icon: Icons.notifications_active_rounded,
                title: 'إشعارات النظام',
                body:
                    'لتنبيهك بانتهاء اشتراك، تسديد دين، أو ربط واتساب — حتى لو التطبيق مغلق.',
                state: _notif,
                actionLabel: switch (_notif) {
                  _State.granted => 'مفعّلة',
                  _State.requesting => 'جاري الطلب...',
                  _State.silentlyBlocked => 'افتح إعدادات النظام',
                  _State.userDenied => 'حاول مجدداً',
                  _State.idle => 'تفعيل',
                },
                onAction: switch (_notif) {
                  _State.granted => null,
                  _State.silentlyBlocked => NotificationService.openSettings,
                  _ => _requestNotif,
                },
              )
                  .animate()
                  .fadeIn(
                    delay: const Duration(milliseconds: 150),
                    duration: const Duration(milliseconds: 350),
                  )
                  .slideY(begin: 0.05, end: 0),
              // CRITICAL UX: if iOS silently blocked us (no popup
              // appeared because of an earlier denial), tell the user
              // EXACTLY how to recover. This was the source of every
              // "why doesn't the popup appear" bug report.
              if (_notif == _State.silentlyBlocked) ...[
                const SizedBox(height: Sp.md),
                _SilentlyBlockedBanner(),
              ],
              const SizedBox(height: Sp.lg),
              _Card(
                icon: Icons.fingerprint_rounded,
                title: 'بصمة / Face ID',
                body: _bioAvailable
                    ? 'دخول سريع بـ${_bioKind ?? "البصمة"} بدون كتابة كلمة المرور.'
                    : 'الجهاز لا يدعم البصمة أو لم يتم تسجيلها بعد.',
                state: _bio,
                actionLabel: switch (_bio) {
                  _State.granted => 'مفعّلة',
                  _State.requesting => 'جاري المصادقة...',
                  _ => _bioAvailable ? 'تفعيل' : 'افتح إعدادات النظام',
                },
                onAction: _bio == _State.granted ? null : _requestBio,
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
          'فعّل الإذونات التالية لتعمل التطبيق بشكل أفضل. يمكنك تخطّيها وتفعيلها لاحقاً.',
          style: AppType.subtitle(color: AppColors.textMid)
              .copyWith(height: 1.6),
        ),
      ],
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({
    required this.icon,
    required this.title,
    required this.body,
    required this.state,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String title;
  final String body;
  final _State state;
  final String actionLabel;
  final VoidCallback? onAction;

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
              _Badge(state: state),
            ],
          ),
          const SizedBox(height: Sp.md),
          Text(body,
              style: AppType.subtitle(color: AppColors.textMid)
                  .copyWith(height: 1.55)),
          if (state != _State.granted) ...[
            const SizedBox(height: Sp.md),
            SizedBox(
              height: 44,
              child: Material(
                color: state == _State.silentlyBlocked
                    ? AppColors.error.withValues(alpha: 0.1)
                    : AppColors.brand.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(R.md),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: state == _State.requesting ? null : onAction,
                  child: Center(
                    child: state == _State.requesting
                        ? SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: state == _State.silentlyBlocked
                                  ? AppColors.error
                                  : AppColors.brand,
                            ),
                          )
                        : Text(
                            actionLabel,
                            style: AppType.button(
                              color: state == _State.silentlyBlocked
                                  ? AppColors.error
                                  : AppColors.brand,
                            ).copyWith(fontSize: 14),
                          ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.state});
  final _State state;

  @override
  Widget build(BuildContext context) {
    final (label, color, icon) = switch (state) {
      _State.granted => ('مفعّلة', AppColors.brand, Icons.check_rounded),
      _State.silentlyBlocked =>
        ('بحاجة إعدادات', AppColors.error, Icons.settings_rounded),
      _State.userDenied =>
        ('رفض', AppColors.textLow, Icons.close_rounded),
      _State.requesting =>
        ('...', AppColors.textMid, Icons.more_horiz_rounded),
      _State.idle =>
        ('غير مفعّلة', AppColors.textLow, Icons.circle_outlined),
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

class _SilentlyBlockedBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(R.md),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.25)),
      ),
      padding: const EdgeInsets.all(Sp.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded,
              color: AppColors.error, size: 18),
          const SizedBox(width: Sp.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'iOS لن يعرض النافذة مجدداً',
                  style:
                      AppType.label(color: AppColors.error).copyWith(fontSize: 13),
                ),
                const SizedBox(height: 4),
                Text(
                  'الإذن مرفوض سابقاً على هذا الجهاز. ٣ طرق للحل:\n'
                  '١. افتح إعدادات النظام → الإشعارات → MyServices Radius → فعّل.\n'
                  '٢. أو احذف التطبيق من الجهاز وأعد تثبيته.\n'
                  '٣. على المحاكي: Device → Erase All Content and Settings.',
                  style: AppType.subtitle(color: AppColors.textMid)
                      .copyWith(fontSize: 12, height: 1.55),
                ),
              ],
            ),
          ),
        ],
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
