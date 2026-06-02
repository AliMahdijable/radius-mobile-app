import 'package:flutter/material.dart';

import '../../../core/mock/dashboard_data.dart';
import '../../../core/util/format.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';

/// Recent activity feed for home — last N events, one row each.
class RecentActivities extends StatelessWidget {
  const RecentActivities({super.key, required this.items});

  final List<Activity> items;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.lg),
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (int i = 0; i < items.length; i++) ...[
            _Row(item: items[i]),
            if (i < items.length - 1)
              const Divider(
                height: 1,
                indent: Sp.huge + Sp.sm,
                endIndent: Sp.lg,
                color: AppColors.border,
              ),
          ],
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.item});
  final Activity item;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = _visualFor(item.kind);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {},
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Sp.lg,
            vertical: Sp.md,
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(R.sm),
                ),
                child: Icon(icon, color: color, size: 18),
              ),
              const SizedBox(width: Sp.md),
              Expanded(
                child: Text(
                  item.title,
                  style: AppType.label(color: AppColors.textHi)
                      .copyWith(fontSize: 13),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: Sp.sm),
              if (item.amount != 0) ...[
                Text(
                  '${item.amount < 0 ? '-' : '+'}${formatIQD(item.amount)}',
                  style: AppType.label(
                    color: item.amount < 0
                        ? AppColors.error
                        : AppColors.brand,
                  ).copyWith(fontSize: 12),
                ),
                const SizedBox(width: Sp.sm),
              ],
              Text(
                humanMinutesAgo(item.minutesAgo),
                style:
                    AppType.muted(color: AppColors.textLow).copyWith(fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static (IconData, Color) _visualFor(ActivityKind k) => switch (k) {
        ActivityKind.activation => (Icons.bolt_rounded, AppColors.brand),
        ActivityKind.extension =>
          (Icons.loop_rounded, Color(0xFF3B82F6)),
        ActivityKind.payment =>
          (Icons.payments_rounded, AppColors.brand),
        ActivityKind.debt =>
          (Icons.account_balance_wallet_rounded, AppColors.error),
        ActivityKind.message =>
          (Icons.chat_bubble_rounded, Color(0xFFE08F2D)),
        ActivityKind.system =>
          (Icons.settings_suggest_rounded, AppColors.textMid),
      };
}
