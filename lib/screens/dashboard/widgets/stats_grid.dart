import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../api/dashboard_api.dart';
import '../../../core/util/format.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';

/// Pair of hero metric cards on the dashboard:
///   • Balance + Points (manager wallet, brand-colored accent)
///   • Debt total + count (warning-colored accent)
///
/// Visual style mirrors the surrounding cards (white surface, soft
/// border, subtle shadow) — no gradient backgrounds per user
/// 'تكدر تسوي شفاف مثل بقية كارتات الداش بورد'. The accent color
/// shows up only on the icon chip + the hero number, which keeps the
/// row consistent with SubscribersCard / HeroRevenueCard while still
/// reading at-a-glance.
///
/// wallet/debtors=null = loading → each cell shows a spinner instead
/// of a fabricated number.
class StatsGrid extends StatelessWidget {
  const StatsGrid({
    super.key,
    required this.wallet,
    required this.debtors,
    this.onOpenDebtors,
  });

  final WalletResult? wallet;
  final DebtorsResult? debtors;
  /// Tapping the debt card opens the subscribers screen with the
  /// debtors filter pre-applied. No equivalent for the wallet card —
  /// it isn't a list view target.
  final VoidCallback? onOpenDebtors;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: _BalancePointsCard(wallet: wallet)),
          const SizedBox(width: Sp.md),
          Expanded(
            child: _DebtCard(debtors: debtors, onTap: onOpenDebtors),
          ),
        ],
      ),
    );
  }
}

/// White card with a brand-tinted icon chip + a brand-colored balance.
/// The reward-points chip sits below, slightly muted so it doesn't
/// compete with the hero number.
class _BalancePointsCard extends StatelessWidget {
  const _BalancePointsCard({required this.wallet});
  final WalletResult? wallet;

  // getter لا حقل: القيمة theme-aware ويجب أن تُقرأ عند كل بناء
  static Color get _accent => AppColors.brand;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return _ShellCard(
      icon: LucideIcons.wallet,
      iconAccent: _accent,
      title: 'dashboard.balance'.tr(),
      body: wallet == null
          ? _Spinner(color: _accent)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _HeroAmount(
                  amount: wallet!.balance.round(),
                  color: _accent,
                ),
                const SizedBox(height: 7),
                Row(
                  children: [
                    const Icon(LucideIcons.star,
                        color: Color(0xFFCD8B00), size: 12),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        '${formatIQD(wallet!.points.round())} ${'dashboard.points_singular'.tr()}',
                        style: AppType.muted(color: AppColors.textMid)
                            .copyWith(fontSize: 11, fontWeight: FontWeight.w500),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
    );
  }
}

class _DebtCard extends StatelessWidget {
  const _DebtCard({required this.debtors, this.onTap});
  final DebtorsResult? debtors;
  final VoidCallback? onTap;

  static const _accent = Color(0xFFEA580C); // warm orange

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return _ShellCard(
      icon: LucideIcons.creditCard,
      iconAccent: _accent,
      title: 'dashboard.debtors'.tr(),
      onTap: onTap,
      body: debtors == null
          ? _Spinner(color: _accent)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _HeroAmount(
                  amount: debtors!.total,
                  color: _accent,
                ),
                const SizedBox(height: 7),
                Row(
                  children: [
                    Icon(LucideIcons.users,
                        color: AppColors.textMid, size: 12),
                    const SizedBox(width: 4),
                    Text(
                      '${debtors!.count} ${'dashboard.subscriber_singular'.tr()}',
                      style: AppType.muted(color: AppColors.textMid)
                          .copyWith(fontSize: 11, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ],
            ),
    );
  }
}

/// Shared shell — icon chip on the top row + a title, body below.
/// Keeps the dashboard's cards visually uniform.
class _ShellCard extends StatelessWidget {
  const _ShellCard({
    required this.icon,
    required this.iconAccent,
    required this.title,
    required this.body,
    this.onTap,
  });

  final IconData icon;
  final Color iconAccent;
  final String title;
  final Widget body;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(R.lg),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(R.lg),
        child: Container(
          padding: const EdgeInsets.all(Sp.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(R.lg),
            border: Border.all(color: AppColors.border),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: _buildBody(),
        ),
      ),
    );
  }

  Widget _buildBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: iconAccent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(R.sm),
              ),
              child: Icon(icon, color: iconAccent, size: 14),
            ),
            const SizedBox(width: Sp.sm),
            Text(
              title,
              style: AppType.label(color: AppColors.textMid)
                  .copyWith(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ],
        ),
        const SizedBox(height: Sp.sm),
        body,
      ],
    );
  }
}

/// Hero IQD amount — large weight + the accent color, with the 'IQD'
/// suffix in a smaller, muted gray.
class _HeroAmount extends StatelessWidget {
  const _HeroAmount({required this.amount, required this.color});
  final int amount;
  final Color color;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: AlignmentDirectional.centerStart,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(
            formatIQD(amount),
            style: AppType.title(color: color).copyWith(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              height: 1.1,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            'IQD',
            style: AppType.muted(color: AppColors.textLow)
                .copyWith(fontSize: 10, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _Spinner extends StatelessWidget {
  const _Spinner({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return SizedBox(
      height: 22,
      width: 22,
      child: CircularProgressIndicator(
        strokeWidth: 2,
        color: color,
      ),
    );
  }
}
