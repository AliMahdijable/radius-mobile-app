import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/notification_prefs.dart';
import '../providers/notification_prefs_provider.dart';
import '../widgets/app_snackbar.dart';

/// Per-admin controls for which push notifications fire (in-app bell
/// keeps populating from activity_logs regardless — this screen only
/// gates the FCM side) plus an optional quiet-hours window.
///
/// Saving is eager-on-toggle: every change POSTs immediately so there's
/// no "unsaved changes" confusion. Saving for the quiet-hours time
/// picker commits on dialog close.
class NotificationSettingsScreen extends ConsumerStatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  ConsumerState<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends ConsumerState<NotificationSettingsScreen> {
  // Local optimistic copy so switches flip instantly while the PUT is
  // in flight. Reconciles against the provider on success.
  NotificationPrefs? _local;
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(notificationPrefsProvider);
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('إعدادات الإشعارات')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('خطأ: $e')),
        data: (prefs) {
          final p = _local ?? prefs;
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(notificationPrefsProvider);
            },
            child: ListView(
              padding: const EdgeInsets.all(14),
              children: [
                _HeaderNote(cs: cs),
                const SizedBox(height: 14),
                _SectionTitle(title: 'إشعارات Push'),
                const SizedBox(height: 4),
                _PrefCard(
                  child: Column(
                    children: [
                      _PrefTile(
                        icon: Icons.warning_amber_rounded,
                        iconColor: Colors.orange,
                        title: 'قرب الانتهاء',
                        subtitle: 'المشتركين الذين يتبقى لهم 3 أيام أو أقل',
                        value: p.pushNearExpiry,
                        onChanged: (v) => _applyAndSave(p.copyWith(pushNearExpiry: v)),
                      ),
                      _Divider(),
                      _PrefTile(
                        icon: Icons.error_outline,
                        iconColor: Colors.redAccent,
                        title: 'الانتهاء',
                        subtitle: 'المشتركين الذين انتهى اشتراكهم اليوم',
                        value: p.pushExpiredToday,
                        onChanged: (v) => _applyAndSave(p.copyWith(pushExpiredToday: v)),
                      ),
                      _Divider(),
                      _PrefTile(
                        icon: Icons.assignment_ind_rounded,
                        iconColor: Colors.amber,
                        title: 'ديون المدراء',
                        subtitle: 'إضافة دين أو تسديد من المدير الرئيسي',
                        value: p.pushManagerDebt,
                        onChanged: (v) => _applyAndSave(p.copyWith(pushManagerDebt: v)),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),
                _SectionTitle(title: 'ساعات الصمت'),
                const SizedBox(height: 4),
                _PrefCard(
                  child: Column(
                    children: [
                      _PrefTile(
                        icon: Icons.nights_stay_rounded,
                        iconColor: Colors.indigo,
                        title: 'تفعيل ساعات الصمت',
                        subtitle: 'لا يصل Push خلال الفترة المحددة',
                        value: p.quietHoursEnabled,
                        onChanged: (v) =>
                            _applyAndSave(p.copyWith(quietHoursEnabled: v)),
                      ),
                      if (p.quietHoursEnabled) ...[
                        _Divider(),
                        _TimeRow(
                          label: 'يبدأ',
                          time: p.quietHoursStart,
                          onPicked: (t) =>
                              _applyAndSave(p.copyWith(quietHoursStart: t)),
                        ),
                        _Divider(),
                        _TimeRow(
                          label: 'ينتهي',
                          time: p.quietHoursEnd,
                          onPicked: (t) =>
                              _applyAndSave(p.copyWith(quietHoursEnd: t)),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                if (p.quietHoursEnabled)
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.indigo.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.indigo.withOpacity(0.3)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.info_outline, size: 16, color: Colors.indigo.shade700),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'خلال ساعات الصمت لا يصل إشعار Push لهاتفك، '
                            'لكن يظل الإشعار يظهر في الجرس داخل التطبيق '
                            'لمراجعته عند الفتح.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.indigo.shade900,
                              height: 1.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _applyAndSave(NotificationPrefs next) async {
    if (_saving) return;
    setState(() {
      _local = next;
      _saving = true;
    });
    final ok = await saveNotificationPrefs(ref, next);
    if (!mounted) return;
    setState(() => _saving = false);
    if (!ok) {
      AppSnackBar.error(context, 'تعذّر حفظ الإعداد');
      // Roll back optimistic update
      setState(() => _local = null);
    }
  }
}

// ─── Building blocks ──────────────────────────────────────────────────

class _HeaderNote extends StatelessWidget {
  final ColorScheme cs;
  const _HeaderNote({required this.cs});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.primary.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.primary.withOpacity(0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.notifications_active_outlined, size: 20, color: cs.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'تتحكّم هذه الإعدادات بإشعارات Push فقط. جرس التطبيق يعرض '
              'كل الأحداث دائماً كسجلّ للمراجعة.',
              style: TextStyle(fontSize: 12, color: cs.primary, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      child: Text(
        title,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _PrefCard extends StatelessWidget {
  final Widget child;
  const _PrefCard({required this.child});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.4)),
      ),
      child: child,
    );
  }
}

class _PrefTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _PrefTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: iconColor, size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            Transform.scale(
              scale: 0.9,
              child: Switch(
                value: value,
                onChanged: onChanged,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      height: 1,
      color: cs.outlineVariant.withOpacity(0.3),
    );
  }
}

class _TimeRow extends StatelessWidget {
  final String label;
  final String time;
  final ValueChanged<String> onPicked;
  const _TimeRow({
    required this.label,
    required this.time,
    required this.onPicked,
  });

  Future<void> _pick(BuildContext ctx) async {
    final parts = time.split(':');
    final initial = TimeOfDay(
      hour: int.tryParse(parts.isNotEmpty ? parts[0] : '22') ?? 22,
      minute: int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0,
    );
    final picked = await showTimePicker(context: ctx, initialTime: initial);
    if (picked != null) {
      final hh = picked.hour.toString().padLeft(2, '0');
      final mm = picked.minute.toString().padLeft(2, '0');
      onPicked('$hh:$mm');
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: () => _pick(context),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        child: Row(
          children: [
            Icon(Icons.schedule_rounded, size: 18, color: cs.onSurfaceVariant),
            const SizedBox(width: 10),
            Expanded(
              child: Text(label, style: const TextStyle(fontSize: 14)),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: cs.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                time,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: cs.primary,
                  fontFamily: 'monospace',
                ),
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right, size: 18, color: cs.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}
