import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/device_config.dart';
import '../providers/device_provider.dart';
import '../screens/devices/device_config_dialog.dart';
import '../screens/devices/ont_device_screen.dart';
import '../screens/devices/ubiquiti_device_screen.dart';

/// Compact card showing the subscriber's CPE health summary. Sits under
/// the IP row on the subscriber details screen. Tap → full device screen;
/// gear → credential edit dialog.
class ConnectionStatusCard extends ConsumerWidget {
  final String subscriberUsername;
  final String? fallbackIp; // framedipaddress

  const ConnectionStatusCard({
    super.key,
    required this.subscriberUsername,
    required this.fallbackIp,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final args = DeviceStatusArgs(
      subscriberUsername: subscriberUsername,
      fallbackIp: fallbackIp,
    );
    final asyncSnap = ref.watch(deviceStatusProvider(args));
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Container(
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: cs.outlineVariant),
        ),
        child: asyncSnap.when(
          loading: () => _buildBody(
            context, ref,
            leading: const SizedBox(
              width: 16, height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            title: 'جاري فحص الجهاز...',
            body: null,
            onTap: null,
          ),
          error: (_, __) => _buildBody(
            context, ref,
            leading: Icon(Icons.error_outline, color: cs.error),
            title: 'فشل الاتصال بالجهاز',
            body: Text('اضغط ⚙️ لضبط الإعدادات', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 11)),
            onTap: null,
          ),
          data: (snap) {
            if (snap == null) {
              return _buildBody(
                context, ref,
                leading: Icon(Icons.link_off, color: cs.onSurfaceVariant),
                title: 'الجهاز غير متاح',
                body: Text(
                  (fallbackIp == null || fallbackIp!.isEmpty)
                      ? 'لا يوجد IP للمشترك'
                      : 'لم نصل للجهاز عبر $fallbackIp',
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 11),
                ),
                onTap: null,
              );
            }
            return _buildBody(
              context, ref,
              leading: Icon(
                snap.kind == DeviceKind.ont ? Icons.sensors : Icons.wifi,
                color: _healthColor(snap.overallHealth, cs),
              ),
              title: snap.kind == DeviceKind.ont ? 'Huawei ONT' : 'Ubiquiti',
              body: _MetricsRow(snap: snap),
              onTap: () => _openDetail(context, ref, snap),
            );
          },
        ),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    WidgetRef ref, {
    required Widget leading,
    required String title,
    required Widget? body,
    required VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            leading,
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  if (body != null) ...[
                    const SizedBox(height: 4),
                    body,
                  ],
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.settings_outlined, size: 20),
              tooltip: 'إعدادات الجهاز',
              onPressed: () => _openConfig(context, ref),
            ),
            IconButton(
              icon: const Icon(Icons.refresh, size: 20),
              tooltip: 'تحديث',
              onPressed: () {
                ref.invalidate(deviceStatusProvider(
                  DeviceStatusArgs(subscriberUsername: subscriberUsername, fallbackIp: fallbackIp),
                ));
              },
            ),
          ],
        ),
      ),
    );
  }

  void _openConfig(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (_) => DeviceConfigDialog(subscriberUsername: subscriberUsername),
    ).then((_) {
      // Refetch status after closing the dialog regardless — config may
      // have changed, and even dismissal shouldn't cost us a stale read.
      ref.invalidate(deviceStatusProvider(
        DeviceStatusArgs(subscriberUsername: subscriberUsername, fallbackIp: fallbackIp),
      ));
    });
  }

  void _openDetail(BuildContext context, WidgetRef ref, DeviceHealthSnapshot snap) async {
    final cfg = await ref.read(deviceConfigProvider(subscriberUsername).future) ??
        const DeviceConfig();
    final resolved = cfg.resolve(fallbackIp: fallbackIp);
    if (!context.mounted) return;
    if (snap.kind == DeviceKind.ont) {
      context.push('/ont-device',
          extra: OntDeviceArgs(host: resolved.ip, user: resolved.username, pass: resolved.password));
    } else {
      context.push('/ubiquiti-device',
          extra: UbiquitiDeviceArgs(host: resolved.ip, user: resolved.username, pass: resolved.password));
    }
  }

  static Color _healthColor(String h, ColorScheme cs) {
    switch (h) {
      case 'good': return const Color(0xFF2E7D32);
      case 'warn': return const Color(0xFFF9A825);
      case 'bad':  return cs.error;
      default:     return cs.onSurfaceVariant;
    }
  }
}

class _MetricsRow extends StatelessWidget {
  final DeviceHealthSnapshot snap;
  const _MetricsRow({required this.snap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        if (snap.headlineValue != null)
          _chip(snap.headlineLabel ?? '', snap.headlineValue!, snap.headlineHealth, cs),
        if (snap.secondaryValue != null)
          _chip(snap.secondaryLabel ?? '', snap.secondaryValue!, snap.secondaryHealth, cs),
        if (snap.tertiaryValue != null)
          _chip(snap.tertiaryLabel ?? '', snap.tertiaryValue!, snap.tertiaryHealth, cs),
      ],
    );
  }

  Widget _chip(String label, String value, String health, ColorScheme cs) {
    final color = ConnectionStatusCard._healthColor(health, cs);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6, height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant)),
          const SizedBox(width: 4),
          Text(value, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color)),
        ],
      ),
    );
  }
}
