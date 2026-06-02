import 'package:flutter/material.dart';

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
      padding: const EdgeInsets.all(Sp.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.people_alt_rounded,
                  color: AppColors.brand, size: 18),
              const SizedBox(width: Sp.sm),
              Text('المشتركون',
                  style: AppType.label(color: AppColors.textHi)
                      .copyWith(fontSize: 14)),
              const Spacer(),
              Text(
                '${(activeRatio * 100).round()}% نشط',
                style: AppType.muted(color: AppColors.brand)
                    .copyWith(fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: Sp.lg),
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
                            color: AppColors.brand,
                          ),
                        ),
                        const SizedBox(width: Sp.sm),
                        Expanded(
                          child: _Mini(
                            value: stats.online,
                            label: 'متصل الآن',
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
                            color: AppColors.error,
                          ),
                        ),
                        const SizedBox(width: Sp.sm),
                        Expanded(
                          child: _Mini(
                            value: stats.nearExpiry,
                            label: 'قارب الانتهاء',
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
    return SizedBox(
      width: 96,
      height: 96,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Background ring (light gray)
          SizedBox(
            width: 96,
            height: 96,
            child: CircularProgressIndicator(
              value: 1,
              strokeWidth: 6,
              backgroundColor: Colors.transparent,
              valueColor:
                  AlwaysStoppedAnimation(AppColors.border),
            ),
          ),
          // Brand ring — active percentage
          SizedBox(
            width: 96,
            height: 96,
            child: CircularProgressIndicator(
              value: ratio.clamp(0, 1),
              strokeWidth: 6,
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
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  height: 1.05,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'إجمالي',
                style: AppType.muted(color: AppColors.textMid)
                    .copyWith(fontSize: 10),
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
    required this.label,
    required this.color,
  });

  final int value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Sp.sm,
        vertical: Sp.sm,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(R.sm),
      ),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$value',
                  style: AppType.title(color: AppColors.textHi).copyWith(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    height: 1.1,
                  ),
                ),
                Text(
                  label,
                  style: AppType.muted(color: AppColors.textMid)
                      .copyWith(fontSize: 10),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
