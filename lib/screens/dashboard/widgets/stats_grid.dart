import 'package:flutter/material.dart';

import '../../../core/mock/dashboard_data.dart';
import '../../../core/util/format.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';

/// 2×2 grid of quick stats: activations / payments / debtors / expired.
class StatsGrid extends StatelessWidget {
  const StatsGrid({super.key, required this.stats});

  final DailyStats stats;

  @override
  Widget build(BuildContext context) {
    // Round 8: dropped مدفوعات and منتهين per user request — those live
    // elsewhere now (payments will surface inside the revenue card, and
    // total expired count is already in the SubscribersCard ring).
    return Row(
      children: [
        Expanded(
          child: _StatCell(
            icon: Icons.bolt_rounded,
            accent: AppColors.brand,
            label: 'تفعيلات',
            value: '${stats.activations}',
            delta:
                '${stats.activationsDelta > 0 ? '+' : ''}${stats.activationsDelta} أمس',
            deltaUp: stats.activationsDelta >= 0,
          ),
        ),
        const SizedBox(width: Sp.md),
        Expanded(
          child: _StatCell(
            icon: Icons.account_balance_wallet_rounded,
            accent: AppColors.error,
            label: 'مدينين',
            value: '${stats.debtorsCount}',
            delta: '${formatIQD(stats.debtorsTotal)} د.ع',
            deltaUp: false,
            flipDeltaSemantics: true,
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
    this.unit,
    required this.delta,
    required this.deltaUp,
    this.flipDeltaSemantics = false,
  });

  final IconData icon;
  final Color accent;
  final String label;
  final String value;
  final String? unit;
  final String delta;
  final bool deltaUp;
  final bool flipDeltaSemantics;

  @override
  Widget build(BuildContext context) {
    // For metrics where LESS is better (debtors, expired), the delta
    // color stays neutral — no false "good news" greens for bad numbers.
    final Color deltaColor;
    if (flipDeltaSemantics) {
      deltaColor = AppColors.textMid;
    } else {
      deltaColor = deltaUp ? AppColors.brand : AppColors.error;
    }

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.lg),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.all(Sp.sm + 4), // 12px — slightly tighter
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
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: Text(
                  value,
                  style: AppType.title(color: AppColors.textHi).copyWith(
                    fontSize: 20, // was 24
                    fontWeight: FontWeight.w700,
                    height: 1.1,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (unit != null) ...[
                const SizedBox(width: 4),
                Text(
                  unit!,
                  style: AppType.subtitle(color: AppColors.textLow)
                      .copyWith(fontSize: 10),
                ),
              ],
            ],
          ),
          const SizedBox(height: 3),
          Text(
            delta,
            style: AppType.muted(color: deltaColor).copyWith(fontSize: 10),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
