import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../api/notifications_api.dart';
import '../theme/colors.dart';
import '../theme/spacing.dart';
import '../theme/typography.dart';

/// شاشة "الإشعارات" — تجمع 3 toggles لإشعارات FCM + أوقات السكون
/// (DND). كل تغيير يُحفظ تلقائياً بـPUT مع snackbar.
class NotificationsSettingsScreen extends StatefulWidget {
  const NotificationsSettingsScreen({super.key});

  @override
  State<NotificationsSettingsScreen> createState() =>
      _NotificationsSettingsScreenState();
}

class _NotificationsSettingsScreenState
    extends State<NotificationsSettingsScreen> {
  NotificationPrefs? _prefs;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final p = await NotificationsApi.load();
    if (!mounted) return;
    setState(() {
      _prefs = p ?? NotificationPrefs.defaults;
      _loading = false;
    });
  }

  /// كل تعديل يُحفظ optimistically — نحدّث الـlocal state فوراً ثم
  /// نضرب PUT. لو فشل، نُرجِع القديم ونطبع snackbar.
  Future<void> _patch(NotificationPrefs Function(NotificationPrefs) op) async {
    if (_prefs == null || _saving) return;
    final old = _prefs!;
    final next = op(old);
    setState(() {
      _prefs = next;
      _saving = true;
    });
    final r = await NotificationsApi.save(next);
    if (!mounted) return;
    setState(() {
      _prefs = r.prefs ?? (r.ok ? next : old);
      _saving = false;
    });
    if (!r.ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(r.message ?? 'notifs.save_failed'.tr()),
          backgroundColor: AppColors.errorFill,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _pickTime(bool isStart) async {
    final p = _prefs;
    if (p == null) return;
    final current = _parseTime(isStart ? p.quietHoursStart : p.quietHoursEnd);
    final picked = await showTimePicker(
      context: context,
      initialTime: current,
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true),
        child: child ?? const SizedBox.shrink(),
      ),
    );
    if (picked == null) return;
    final hh = picked.hour.toString().padLeft(2, '0');
    final mm = picked.minute.toString().padLeft(2, '0');
    final formatted = '$hh:$mm';
    await _patch((p) => isStart
        ? p.copyWith(quietHoursStart: formatted)
        : p.copyWith(quietHoursEnd: formatted));
  }

  TimeOfDay _parseTime(String s) {
    final parts = s.split(':');
    final h = int.tryParse(parts[0]) ?? 22;
    final m = parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;
    return TimeOfDay(hour: h, minute: m);
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final p = _prefs;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text('notifications.title'.tr(),
            style:
                AppType.title(color: AppColors.textHi).copyWith(fontSize: 16)),
        iconTheme: IconThemeData(color: AppColors.textHi),
      ),
      body: _loading || p == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, Sp.huge),
              children: [
                _SectionLabel('notifs.types_section'.tr()),
                _Toggle(
                  icon: LucideIcons.clock,
                  label: 'notifs.near_expiry_label'.tr(),
                  sub: 'notifs.near_expiry_hint'.tr(),
                  value: p.pushNearExpiry,
                  onChanged: (v) =>
                      _patch((x) => x.copyWith(pushNearExpiry: v)),
                ),
                _Toggle(
                  icon: LucideIcons.calendarX,
                  label: 'notifs.expired_today_label'.tr(),
                  sub: 'notifs.expired_today_hint'.tr(),
                  value: p.pushExpiredToday,
                  onChanged: (v) =>
                      _patch((x) => x.copyWith(pushExpiredToday: v)),
                ),
                _Toggle(
                  icon: LucideIcons.creditCard,
                  label: 'notifs.mgr_debt_label'.tr(),
                  sub: 'notifs.mgr_debt_hint'.tr(),
                  value: p.pushManagerDebt,
                  onChanged: (v) =>
                      _patch((x) => x.copyWith(pushManagerDebt: v)),
                ),
                const SizedBox(height: Sp.md),
                _SectionLabel('notifs.dnd_section'.tr()),
                _Toggle(
                  icon: LucideIcons.moon,
                  label: 'notifs.mute_window_label'.tr(),
                  sub: p.quietHoursEnabled
                      ? 'notifs.mute_range'.tr(namedArgs: {
                          'from': p.quietHoursStart,
                          'to': p.quietHoursEnd
                        })
                      : 'notifs.no_mute_hint'.tr(),
                  value: p.quietHoursEnabled,
                  onChanged: (v) =>
                      _patch((x) => x.copyWith(quietHoursEnabled: v)),
                ),
                if (p.quietHoursEnabled) ...[
                  const SizedBox(height: Sp.sm),
                  Row(
                    children: [
                      Expanded(
                        child: _TimePickerTile(
                          label: 'notifs.from'.tr(),
                          value: p.quietHoursStart,
                          onTap: () => _pickTime(true),
                        ),
                      ),
                      const SizedBox(width: Sp.sm),
                      Expanded(
                        child: _TimePickerTile(
                          label: 'notifs.to'.tr(),
                          value: p.quietHoursEnd,
                          onTap: () => _pickTime(false),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'notifs.mute_deferred_hint'.tr(),
                    style: AppType.muted(color: AppColors.textMid)
                        .copyWith(fontSize: 11, height: 1.5),
                  ),
                ],
                if (_saving) ...[
                  const SizedBox(height: Sp.lg),
                  Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'notifs.saving'.tr(),
                          style: AppType.muted().copyWith(fontSize: 11),
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

class _Toggle extends StatelessWidget {
  const _Toggle({
    required this.icon,
    required this.label,
    required this.sub,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String label;
  final String sub;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.md),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: value
                  ? AppColors.brand.withValues(alpha: 0.14)
                  : AppColors.surfaceInput,
              borderRadius: BorderRadius.circular(R.sm),
            ),
            alignment: Alignment.center,
            child: Icon(
              icon,
              size: 16,
              color: value ? AppColors.brand : AppColors.textLow,
            ),
          ),
          const SizedBox(width: 10),
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
          Switch.adaptive(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

class _TimePickerTile extends StatelessWidget {
  const _TimePickerTile({
    required this.label,
    required this.value,
    required this.onTap,
  });
  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(R.md),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: Sp.md, vertical: Sp.md),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(R.md),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: AppType.muted(color: AppColors.textMid)
                    .copyWith(fontSize: 11),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(LucideIcons.clock, size: 14, color: AppColors.brand),
                  const SizedBox(width: 6),
                  Text(
                    value,
                    style: AppType.title(color: AppColors.textHi).copyWith(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
