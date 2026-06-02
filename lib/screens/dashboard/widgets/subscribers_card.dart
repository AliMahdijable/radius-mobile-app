import 'package:flutter/material.dart';

import '../../../core/mock/dashboard_data.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';

/// Subscribers summary: total + active and online progress bars + 3 small
/// status indicators below.
class SubscribersCard extends StatelessWidget {
  const SubscribersCard({super.key, required this.stats});

  final SubscribersStats stats;

  @override
  Widget build(BuildContext context) {
    final activeRatio =
        stats.total == 0 ? 0.0 : stats.active / stats.total;
    final onlineRatio =
        stats.active == 0 ? 0.0 : stats.online / stats.active;

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
                  color: AppColors.brand, size: 20),
              const SizedBox(width: Sp.sm),
              Text('المشتركون',
                  style: AppType.title(color: AppColors.textHi)
                      .copyWith(fontSize: 15)),
              const Spacer(),
              Text(
                '${stats.total}',
                style: AppType.title(color: AppColors.textHi).copyWith(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: Sp.lg),
          _ProgressRow(
            label: 'نشط',
            value: stats.active,
            total: stats.total,
            ratio: activeRatio,
            color: AppColors.brand,
          ),
          const SizedBox(height: Sp.md),
          _ProgressRow(
            label: 'متصل الآن',
            value: stats.online,
            total: stats.active,
            ratio: onlineRatio,
            color: const Color(0xFF3B82F6),
          ),
        ],
      ),
    );
  }
}

class _ProgressRow extends StatelessWidget {
  const _ProgressRow({
    required this.label,
    required this.value,
    required this.total,
    required this.ratio,
    required this.color,
  });

  final String label;
  final int value;
  final int total;
  final double ratio;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: Sp.sm),
            Expanded(
              child: Text(
                label,
                style: AppType.label(color: AppColors.textMid)
                    .copyWith(fontSize: 12),
              ),
            ),
            Text(
              '$value / $total',
              style: AppType.label(color: AppColors.textHi)
                  .copyWith(fontSize: 13),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(R.pill),
          child: LinearProgressIndicator(
            value: ratio.clamp(0, 1),
            minHeight: 6,
            backgroundColor: AppColors.surfaceInput,
            valueColor: AlwaysStoppedAnimation(color),
          ),
        ),
      ],
    );
  }
}
