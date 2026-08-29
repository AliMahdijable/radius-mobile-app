import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../services/biometric_service.dart';
import '../services/notification_service.dart';
import '../theme/colors.dart';
import '../theme/spacing.dart';
import '../theme/typography.dart';

/// شاشة "صلاحيات التطبيق" — تجمع الأذونات الخاصة بالتطبيق نفسه:
///   • إشعارات النظام (FCM push) — toggle يطلب OS permission أو يفتح
///     الإعدادات لو محظور.
///   • القفل بالبصمة / Face ID — toggle محفوظ في secure storage.
class AppPermissionsScreen extends StatefulWidget {
  const AppPermissionsScreen({super.key});

  @override
  State<AppPermissionsScreen> createState() => _AppPermissionsScreenState();
}

class _AppPermissionsScreenState extends State<AppPermissionsScreen>
    with WidgetsBindingObserver {
  bool _loading = true;
  // Biometric
  bool _bioEnabled = false;
  bool _bioCanAuth = false;
  List<BiometricType> _bioTypes = const [];
  bool _bioBusy = false;
  // Notification
  bool _notifAuthorized = false;
  bool _notifBusy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// لو الـadmin خرج من التطبيق لتسجيل البصمة في إعدادات النظام أو
  /// تفعيل الإشعارات، نعيد التحميل عند العودة عشان الحالة تنعكس.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  Future<void> _load() async {
    final results = await Future.wait([
      BiometricService.isEnabled(),
      BiometricService.canAuthenticate(),
      BiometricService.available(),
      NotificationService.isAuthorized(),
    ]);
    if (!mounted) return;
    setState(() {
      _bioEnabled = results[0] as bool;
      _bioCanAuth = results[1] as bool;
      _bioTypes = results[2] as List<BiometricType>;
      _notifAuthorized = results[3] as bool;
      _loading = false;
    });
  }

  // --- Notifications -------------------------------------------------

  Future<void> _toggleNotif() async {
    if (_notifBusy) return;
    setState(() => _notifBusy = true);
    if (_notifAuthorized) {
      // لا يمكن "إلغاء" إذن الإشعارات برمجياً — نفتح إعدادات النظام
      // ليلغيها يدوياً.
      await NotificationService.openSettings();
      if (!mounted) return;
      setState(() => _notifBusy = false);
      return;
    }
    final r = await NotificationService.request();
    if (!mounted) return;
    final granted = r == NotifPermissionResult.granted;
    setState(() {
      _notifAuthorized = granted;
      _notifBusy = false;
    });
    if (!granted) {
      // iOS يحفظ القرار الأول — لو رفض المستخدم سابقاً، لا يظهر
      // الـpopup. نوجّهه لإعدادات النظام.
      if (r == NotifPermissionResult.silentlyBlocked) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'perms.blocked_open_system'.tr(),
            ),
            backgroundColor: AppColors.warning,
            behavior: SnackBarBehavior.floating,
            action: SnackBarAction(
              label: 'settings.title'.tr(),
              textColor: Colors.white,
              onPressed: NotificationService.openSettings,
            ),
          ),
        );
      }
    }
  }

  // --- Biometric -----------------------------------------------------

  Future<void> _toggleBio(bool v) async {
    if (_bioBusy) return;
    setState(() => _bioBusy = true);
    if (v) {
      final r = await BiometricService.enable();
      if (!mounted) return;
      setState(() {
        _bioEnabled = r.ok;
        _bioBusy = false;
      });
      if (!r.ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(r.reason ?? 'perms.enable_failed'.tr()),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('perms.bio_lock_enabled'.tr()),
            backgroundColor: AppColors.brand,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } else {
      await BiometricService.disable();
      if (!mounted) return;
      setState(() {
        _bioEnabled = false;
        _bioBusy = false;
      });
    }
  }

  String get _bioLabel {
    if (!_bioCanAuth) return 'perms.bio_unavailable'.tr();
    if (_bioTypes.contains(BiometricType.face)) return 'Face ID متاح';
    if (_bioTypes.contains(BiometricType.fingerprint) ||
        _bioTypes.contains(BiometricType.strong)) {
      return 'perms.bio_fingerprint_available'.tr();
    }
    if (_bioTypes.contains(BiometricType.iris))
      return 'perms.bio_iris_available'.tr();
    return 'perms.bio_generic_available'.tr();
  }

  IconData get _bioIcon {
    if (_bioTypes.contains(BiometricType.face)) {
      return LucideIcons.scanFace;
    }
    return LucideIcons.fingerprint;
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text('settings.permissions'.tr(),
            style:
                AppType.title(color: AppColors.textHi).copyWith(fontSize: 16)),
        iconTheme: IconThemeData(color: AppColors.textHi),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, Sp.huge),
              children: [
                _SectionLabel('notifications.title'.tr()),
                _BioCard(
                  icon: LucideIcons.bell,
                  label: 'perms.system_notifs'.tr(),
                  sub: _notifAuthorized
                      ? 'perms.notifs_on_hint'.tr()
                      : 'perms.notifs_off_hint'.tr(),
                  enabled: _notifAuthorized,
                  canAuth: !_notifBusy,
                  busy: _notifBusy,
                  onChanged: (_) => _toggleNotif(),
                ),
                const SizedBox(height: Sp.md),
                _SectionLabel('perms.lock_section'.tr()),
                _BioCard(
                  icon: _bioIcon,
                  label: 'perms.bio_app_lock'.tr(),
                  sub: _bioCanAuth
                      ? (_bioEnabled
                          ? 'perms.bio_asks_hint'.tr()
                          : 'perms.bio_enable_hint'.tr())
                      : _bioLabel,
                  enabled: _bioEnabled,
                  canAuth: _bioCanAuth,
                  busy: _bioBusy,
                  onChanged: _toggleBio,
                ),
                if (_bioCanAuth) ...[
                  const SizedBox(height: 4),
                  Padding(
                    padding: const EdgeInsets.only(right: 4, left: 4),
                    child: Text(
                      _bioLabel,
                      style: AppType.muted(color: AppColors.textMid)
                          .copyWith(fontSize: 10.5),
                    ),
                  ),
                ],
                if (!_bioCanAuth) ...[
                  const SizedBox(height: Sp.sm),
                  Container(
                    padding: const EdgeInsets.all(Sp.md),
                    decoration: BoxDecoration(
                      color: AppColors.warning.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(R.md),
                      border: Border.all(
                          color: AppColors.warning.withValues(alpha: 0.25)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(LucideIcons.triangleAlert,
                            size: 14, color: AppColors.warning),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'perms.no_bio_enrolled'.tr(),
                            style: AppType.muted(color: AppColors.textHi)
                                .copyWith(fontSize: 11, height: 1.5),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);
  final String label;
  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, Sp.sm, 4, 6),
      child: Text(
        label,
        style: AppType.muted(color: AppColors.textMid).copyWith(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

/// كارت صلاحية بزر action (للإشعارات لأن iOS ما يقبل re-prompt).
class _PermCard extends StatelessWidget {
  const _PermCard({
    required this.icon,
    required this.label,
    required this.sub,
    required this.granted,
    required this.busy,
    required this.switchLabel,
    required this.onAction,
  });
  final IconData icon;
  final String label;
  final String sub;
  final bool granted;
  final bool busy;
  final String switchLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: Sp.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.md),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: granted
                  ? AppColors.brand.withValues(alpha: 0.14)
                  : AppColors.surfaceInput,
              borderRadius: BorderRadius.circular(R.sm),
            ),
            alignment: Alignment.center,
            child: Icon(icon,
                size: 18, color: granted ? AppColors.brand : AppColors.textLow),
          ),
          const SizedBox(width: Sp.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: AppType.label(color: AppColors.textHi)
                      .copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  sub,
                  style: AppType.muted(color: AppColors.textMid)
                      .copyWith(fontSize: 11, height: 1.4),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton(
            onPressed: busy ? null : onAction,
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              foregroundColor: granted ? AppColors.textMid : AppColors.brand,
              side: BorderSide(
                color: granted
                    ? AppColors.border
                    : AppColors.brand.withValues(alpha: 0.5),
              ),
            ),
            child: busy
                ? const SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(
                    switchLabel,
                    style: const TextStyle(
                        fontSize: 11.5, fontWeight: FontWeight.w800),
                  ),
          ),
        ],
      ),
    );
  }
}

/// كارت toggle للبصمة (يقدر يفعّل/يعطّل برمجياً، عكس الإشعارات).
class _BioCard extends StatelessWidget {
  const _BioCard({
    required this.icon,
    required this.label,
    required this.sub,
    required this.enabled,
    required this.canAuth,
    required this.busy,
    required this.onChanged,
  });
  final IconData icon;
  final String label;
  final String sub;
  final bool enabled;
  final bool canAuth;
  final bool busy;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: Sp.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.md),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: enabled
                  ? AppColors.brand.withValues(alpha: 0.14)
                  : AppColors.surfaceInput,
              borderRadius: BorderRadius.circular(R.sm),
            ),
            alignment: Alignment.center,
            child: Icon(icon,
                size: 18, color: enabled ? AppColors.brand : AppColors.textLow),
          ),
          const SizedBox(width: Sp.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: AppType.label(color: AppColors.textHi)
                      .copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  sub,
                  style: AppType.muted(color: AppColors.textMid)
                      .copyWith(fontSize: 11, height: 1.4),
                ),
              ],
            ),
          ),
          Switch.adaptive(
            value: enabled,
            onChanged: (canAuth && !busy) ? onChanged : null,
          ),
        ],
      ),
    );
  }
}
