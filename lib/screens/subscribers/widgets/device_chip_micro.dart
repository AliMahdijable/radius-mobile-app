import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../api/device_probe_api.dart';
import '../../../models/device_health.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';

/// Notifier that lets the list-view wave broadcast cache updates to
/// every visible card at once. Wave loop calls `bump()` after each
/// concurrent batch; chips listen and re-render against the freshly
/// warmed cache without re-probing themselves.
class DeviceProbeBus {
  static final ValueNotifier<int> tick = ValueNotifier<int>(0);
  static void bump() => tick.value = tick.value + 1;
}

/// Compact device-health indicator for subscriber-list cards.
/// Reads from DeviceProbeApi's cache only — never starts its own
/// probe (the list-view wave is responsible for filling the cache).
/// Shows nothing while the cache is cold so we don't render a flash
/// of grey "loading" chips for an offline list.
class DeviceChipMicro extends StatelessWidget {
  const DeviceChipMicro({super.key, required this.ip});
  final String? ip;

  @override
  Widget build(BuildContext context) {
    final clean = ip?.trim() ?? '';
    if (clean.isEmpty) return const SizedBox.shrink();
    return ValueListenableBuilder<int>(
      valueListenable: DeviceProbeBus.tick,
      builder: (_, __, ___) {
        final snap = DeviceProbeApi.cached(clean);
        if (snap == null) return const SizedBox.shrink();
        if (snap.kind == DeviceKind.ont && snap.ont != null) {
          return _ontChip(snap.ont!);
        }
        if (snap.kind == DeviceKind.ubiquiti && snap.ubnt != null) {
          return _ubntChip(snap.ubnt!);
        }
        return const SizedBox.shrink();
      },
    );
  }

  Widget _ontChip(OntOpticalInfo o) {
    final color = o.rxOk ? AppColors.brand : AppColors.error;
    return _chip(
      icon: LucideIcons.signalHigh,
      label: 'ONT',
      value: '${o.rxPower} dBm',
      color: color,
    );
  }

  Widget _ubntChip(UbiquitiStatus u) {
    final color = _signalColor(u.signalDbm);
    final value = u.signalDbm != null ? '${u.signalDbm} dBm' : '—';
    return _chip(
      icon: LucideIcons.wifi,
      label: 'UBNT',
      value: value,
      color: color,
    );
  }

  static Color _signalColor(int? signal) {
    if (signal == null) return AppColors.textMid;
    if (signal > -65) return AppColors.brand;
    if (signal > -75) return const Color(0xFFE08F2D);
    return AppColors.error;
  }

  Widget _chip({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(R.sm),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 8.5, color: color),
          const SizedBox(width: 3),
          Text(
            label,
            style: AppType.label(color: color)
                .copyWith(fontSize: 8.5, fontWeight: FontWeight.w800),
          ),
          const SizedBox(width: 3),
          Text(
            value,
            style: AppType.muted(color: color)
                .copyWith(fontSize: 8.5, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
