import 'package:flutter/material.dart';

import '../../../core/util/format.dart';
import '../../../models/dashboard.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';

/// 2-cell grid of quick stats: activations + debtors.
/// stats=null → both cells show a loading spinner instead of fabricated
/// numbers.
class StatsGrid extends StatelessWidget {
  const StatsGrid({super.key, required this.stats});

  final DailyStats? stats;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _StatCell(
            icon: Icons.bolt_rounded,
            accent: AppColors.brand,
            label: 'تفعيلات',
            value: stats == null ? null : '${stats!.activations}',
            delta: null,
          ),
        ),
        const SizedBox(width: Sp.md),
        Expanded(
          child: _StatCell(
            icon: Icons.account_balance_wallet_rounded,
            accent: AppColors.error,
            label: 'مدينين',
            value: stats == null ? null : '${stats!.debtorsCount}',
            delta: stats == null
                ? null
                : '${formatIQD(stats!.debtorsTotal)} د.ع',
          ),
        ),
      ],
    );
  }
}

class _StatCell extends StatelessWidget {
  const _StatCell({
    required this.icon,
    required this.accent,
    required this.label,
    required this.value,
    required this.delta,
  });

  final IconData icon;
  final Color accent;
  final String label;
  /// `null` = loading. The cell shows a spinner instead of a number.
  final String? value;
  final String? delta;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.lg),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.all(Sp.sm + 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(R.sm),
                ),
                child: Icon(icon, color: accent, size: 16),
              ),
              const SizedBox(width: Sp.sm),
              Expanded(
                child: Text(
                  label,
                  style: AppType.label(color: AppColors.textMid)
                      .copyWith(fontSize: 11),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: Sp.sm),
          if (value == null)
            const SizedBox(
              height: 22,
              width: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.brand,
              ),
            )
          else
            Text(
              value!,
              style: AppType.title(color: AppColors.textHi).copyWith(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                height: 1.1,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          const SizedBox(height: 3),
          Text(
            delta ?? '',
            style: AppType.muted(color: AppColors.textMid).copyWith(fontSize: 10),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
