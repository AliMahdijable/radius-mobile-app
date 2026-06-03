import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/mock/dashboard_data.dart';
import '../../../core/util/format.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';

/// Subscribers card v2: hero total on the left with a brand-tinted
/// progress ring around it, status grid on the right.
///
/// Designed to read in one glance:
/// - Total dominates (left).
/// - 4 status mini-tiles tell you what's healthy + what needs attention.
class SubscribersCard extends StatelessWidget {
  const SubscribersCard({super.key, required this.stats});

  final SubscribersStats stats;

  @override
  Widget build(BuildContext context) {
    final activeRatio =
        stats.total == 0 ? 0.0 : stats.active / stats.total;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.lg),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.all(Sp.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.people_alt_rounded,
                  color: AppColors.brand, size: 20),
              const SizedBox(width: Sp.sm),
              Text('المشتركون',
                  style: AppType.label(color: AppColors.textHi)
                      .copyWith(fontSize: 16)),
              const Spacer(),
              Text(
                '${(activeRatio * 100).round()}% نشط',
                style: AppType.muted(color: AppColors.brand)
                    .copyWith(fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: Sp.xl),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _TotalWithRing(total: stats.total, ratio: activeRatio),
              const SizedBox(width: Sp.lg),
              Expanded(
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _Mini(
                            value: stats.active,
                            label: 'نشط',
                            icon: LucideIcons.circleCheck,
                            color: AppColors.brand,
                          ),
                        ),
                        const SizedBox(width: Sp.sm),
                        Expanded(
                          child: _Mini(
                            value: stats.online,
                            label: 'متصل الآن',
                            icon: LucideIcons.wifi,
                            color: const Color(0xFF3B82F6),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: Sp.sm),
                    Row(
                      children: [
                        Expanded(
                          child: _Mini(
                            value: stats.expired,
                            label: 'منتهي',
                            icon: LucideIcons.timerOff,
                            color: AppColors.error,
                          ),
                        ),
                        const SizedBox(width: Sp.sm),
                        Expanded(
                          child: _Mini(
                            value: stats.nearExpiry,
                            label: 'قارب الانتهاء',
                            icon: LucideIcons.triangleAlert,
                            color: const Color(0xFFE08F2D),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TotalWithRing extends StatelessWidget {
  const _TotalWithRing({required this.total, required this.ratio});

  final int total;
  final double ratio;

  @override
  Widget build(BuildContext context) {
    const size = 120.0; // up from 96 — gives the total number more room
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Background ring (light gray)
          const SizedBox(
            width: size,
            height: size,
            child: CircularProgressIndicator(
              value: 1,
              strokeWidth: 7,
              backgroundColor: Colors.transparent,
              valueColor: AlwaysStoppedAnimation(AppColors.border),
            ),
          ),
          // Brand ring — active percentage
          SizedBox(
            width: size,
            height: size,
            child: CircularProgressIndicator(
              value: ratio.clamp(0, 1),
              strokeWidth: 7,
              backgroundColor: Colors.transparent,
              valueColor:
                  const AlwaysStoppedAnimation(AppColors.brand),
              strokeCap: StrokeCap.round,
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                formatIQD(total),
                style: AppType.title(color: AppColors.textHi).copyWith(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  height: 1.05,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'إجمالي',
                style: AppType.muted(color: AppColors.textMid)
                    .copyWith(fontSize: 11),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Mini extends StatelessWidget {
  const _Mini({
    required this.value,
    required this.label, // kept as tooltip — long-press for the word
    required this.icon,
    required this.color,
  });

  final int value;
  final String label;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    // Icon-only design — the icon alone carries the meaning, and the
    // Arabic word kept clipping in narrow tiles. Long-press still shows
    // the label as a tooltip for users who want to confirm.
    return Tooltip(
      message: label,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: Sp.md,
          vertical: Sp.md,
        ),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(R.sm),
          border: Border.all(color: color.withValues(alpha: 0.18)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Smaller than the counter so the number stays the focal
            // point of the tile (per user request).
            Icon(icon, color: color, size: 16),
            Text(
              '$value',
              style: AppType.title(color: AppColors.textHi).copyWith(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                height: 1.1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
