import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shimmer/shimmer.dart';

import '../models/device_config.dart';
import '../providers/device_provider.dart';
import '../screens/devices/device_config_dialog.dart';
import '../screens/devices/ont_device_screen.dart';
import '../screens/devices/ubiquiti_device_screen.dart';

/// Compact row showing the subscriber's CPE health summary — styled to
/// match the other _DetailRow entries in subscriber_details_screen so
/// the card stays a single, consistent list rather than a bordered
/// sub-panel.
class ConnectionStatusCard extends ConsumerWidget {
  final String subscriberUsername;
  final String? fallbackIp;

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
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final labelStyle = theme.textTheme.bodySmall?.copyWith(
      color: cs.onSurface.withValues(alpha: 0.55),
      fontWeight: FontWeight.w600,
    );

    final isLoading = asyncSnap.isLoading;
    // What goes on the left side of the row (the "value" slot).
    final valueChild = asyncSnap.when(
      loading: () => const _ScanningShimmer(),
      error: (_, __) => _PlaceholderChip(text: 'فشل', color: cs.error),
      data: (snap) {
        if (snap == null) {
          return const _PlaceholderChip(text: 'غير متاح');
        }
        return _MetricsInlineRow(snap: snap, onTap: () => _openDetail(context, ref, snap));
      },
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(Icons.router_rounded, size: 16, color: cs.primary),
          const SizedBox(width: 8),
          Text('الاتصال', style: labelStyle),
          const SizedBox(width: 8),
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: valueChild,
            ),
          ),
          // Config gear — always enabled, even during loading/error.
          InkResponse(
            onTap: () => _openConfig(context, ref),
            radius: 16,
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(Icons.settings_outlined, size: 16, color: cs.onSurfaceVariant),
            ),
          ),
          // Refresh — disabled while a probe is in flight so the admin
          // doesn't queue duplicate requests against the router.
          InkResponse(
            onTap: isLoading
                ? null
                : () => ref.invalidate(deviceStatusProvider(args)),
            radius: 16,
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(
                Icons.refresh_rounded,
                size: 16,
                color: isLoading
                    ? cs.onSurfaceVariant.withValues(alpha: 0.35)
                    : cs.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _openConfig(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (_) => DeviceConfigDialog(subscriberUsername: subscriberUsername),
    ).then((_) {
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

  static Color healthColor(String h, ColorScheme cs) {
    switch (h) {
      case 'good': return const Color(0xFF2E7D32);
      case 'warn': return const Color(0xFFF9A825);
      case 'bad':  return cs.error;
      default:     return cs.onSurfaceVariant;
    }
  }
}

/// Loading indicator for the connection row — three skeleton chips that
/// shimmer, plus a tiny "يفحص..." label. Adapts to light/dark themes by
/// reading the current ColorScheme instead of hard-coded greys.
class _ScanningShimmer extends StatelessWidget {
  const _ScanningShimmer();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = isDark
        ? cs.onSurface.withValues(alpha: 0.08)
        : cs.onSurface.withValues(alpha: 0.10);
    final highlight = isDark
        ? cs.onSurface.withValues(alpha: 0.22)
        : cs.onSurface.withValues(alpha: 0.30);

    Widget pill(double w) => Container(
          width: w,
          height: 18,
          decoration: BoxDecoration(
            color: Colors.white, // overridden by Shimmer gradient
            borderRadius: BorderRadius.circular(6),
          ),
        );

    return Shimmer.fromColors(
      baseColor: base,
      highlightColor: highlight,
      period: const Duration(milliseconds: 1200),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          pill(44),
          const SizedBox(width: 4),
          pill(44),
          const SizedBox(width: 4),
          pill(44),
          const SizedBox(width: 6),
          // Small "يفحص" text — still inside the shimmer so it reads as
          // part of the animation, visible in both themes.
          Text(
            'يفحص…',
            style: TextStyle(
              fontSize: 10,
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _PlaceholderChip extends StatelessWidget {
  final String text;
  final Color? color;
  const _PlaceholderChip({required this.text, this.color});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final c = color ?? cs.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: c.withValues(alpha: 0.22)),
      ),
      child: Text(text, style: TextStyle(fontSize: 11, color: c, fontWeight: FontWeight.w600)),
    );
  }
}

class _MetricsInlineRow extends StatelessWidget {
  final DeviceHealthSnapshot snap;
  final VoidCallback onTap;
  const _MetricsInlineRow({required this.snap, required this.onTap});

  String _shortLabel(String label) {
    switch (label) {
      case 'RX Power': return 'RX';
      case 'TX Power': return 'TX';
      case 'Temp':     return 'T';
      case 'الإشارة':  return 'sig';
      default:         return label;
    }
  }

  String _shortValue(String value) => value
      .replaceAll(' dBm', '')
      .replaceAll(' Mbps', 'M')
      .replaceAll(' kbps', 'k')
      .trim();

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

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        children: chips,
      ),
    );
  }

  Widget _chip(String label, String value, String health, ColorScheme cs) {
    final color = ConnectionStatusCard.healthColor(health, cs);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.30)),
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
          Text(value, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: color)),
        ],
      ),
    );
  }
}
