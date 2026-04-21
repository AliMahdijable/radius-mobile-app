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
          // Silent loading — probe can take a few seconds on slow links,
          // so we don't want to shove a spinner into the subscriber card.
          // Keep just the title + gear so the admin can still edit creds.
          loading: () => _buildBody(
            context, ref,
            leading: Icon(Icons.router_outlined, color: cs.onSurfaceVariant),
            title: 'الجهاز',
            body: null,
            onTap: null,
          ),
          error: (_, __) => _buildBody(
            context, ref,
            leading: Icon(Icons.error_outline, color: cs.error),
            title: 'الجهاز',
            body: null,
            onTap: null,
          ),
          data: (snap) {
            if (snap == null) {
              return _buildBody(
                context, ref,
                leading: Icon(Icons.link_off, color: cs.onSurfaceVariant),
                title: 'الجهاز',
                body: null,
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

  // Abbreviate verbose labels so all three chips fit on one line on
  // narrow phones. "RX Power" → "RX", "الإشارة" → "sig", etc.
  String _shortLabel(String label) {
    switch (label) {
      case 'RX Power': return 'RX';
      case 'TX Power': return 'TX';
      case 'Temp':     return 'T';
      case 'الإشارة':  return 'sig';
      default:         return label;
    }
  }

  // Strip units from values when the chip is already narrow — for the
  // card summary the number itself is what matters, the unit is in the
  // detail screen. Keeps e.g. "dBm" off the chip but leaves "%" on CCQ.
  String _shortValue(String value) {
    return value
        .replaceAll(' dBm', '')
        .replaceAll(' Mbps', 'M')
        .replaceAll(' kbps', 'k')
        .trim();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final chips = <Widget>[];
    if (snap.headlineValue != null) {
      chips.add(_chip(_shortLabel(snap.headlineLabel ?? ''),
          _shortValue(snap.headlineValue!), snap.headlineHealth, cs));
    }
    if (snap.secondaryValue != null) {
      chips.add(_chip(_shortLabel(snap.secondaryLabel ?? ''),
          _shortValue(snap.secondaryValue!), snap.secondaryHealth, cs));
    }
    if (snap.tertiaryValue != null) {
      chips.add(_chip(_shortLabel(snap.tertiaryLabel ?? ''),
          _shortValue(snap.tertiaryValue!), snap.tertiaryHealth, cs));
    }
    // Single scrollable row — if device screen is wide enough all fit,
    // on narrow phones the admin can swipe horizontally rather than have
    // the chips wrap and break the card height.
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (int i = 0; i < chips.length; i++) ...[
            if (i > 0) const SizedBox(width: 6),
            chips[i],
          ],
        ],
      ),
    );
  }

  Widget _chip(String label, String value, String health, ColorScheme cs) {
    final color = ConnectionStatusCard._healthColor(health, cs);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 5, height: 5,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 9, color: cs.onSurfaceVariant)),
          const SizedBox(width: 3),
          Text(value, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: color)),
        ],
      ),
    );
  }
}
