import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../api/dashboard_api.dart';
import '../../../core/util/format.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';

/// Replaces the previous activations+debtors counters with v1's pair of
/// gradient hero cards: balance + reward points on the left, debtors
/// (total IQD as hero, count as a small line at the bottom) on the
/// right. Mirrors mobile-app/lib/screens/dashboard_screen.dart
/// _BalancePointsCard + _DebtCard 1:1, just modernized typography.
///
/// wallet/debtors=null while the API calls are in flight → both cells
/// render a loading spinner instead of fabricated numbers.
class StatsGrid extends StatelessWidget {
  const StatsGrid({
    super.key,
    required this.wallet,
    required this.debtors,
  });

  final WalletResult? wallet;
  final DebtorsResult? debtors;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: _BalancePointsCard(wallet: wallet)),
          const SizedBox(width: Sp.md),
          Expanded(child: _DebtCard(debtors: debtors)),
        ],
      ),
    );
  }
}

/// Green gradient card — hero balance with the reward-point count as a
/// small chip below. v1's primaryGradient ported to the v2 brand color.
class _BalancePointsCard extends StatelessWidget {
  const _BalancePointsCard({required this.wallet});
  final WalletResult? wallet;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF2D5F47), Color(0xFF1F4634)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(R.lg),
        boxShadow: [
          BoxShadow(
            color: AppColors.brand.withValues(alpha: 0.2),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(LucideIcons.wallet, color: Colors.white, size: 16),
              const SizedBox(width: 5),
              Text(
                'الرصيد',
                style: AppType.muted(
                  color: Colors.white.withValues(alpha: 0.85),
                ).copyWith(fontSize: 11, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (wallet == null)
            const SizedBox(
              height: 22,
              width: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          else ...[
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    formatIQD(wallet!.balance.round()),
                    style: AppType.title(color: Colors.white).copyWith(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      height: 1.1,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'IQD',
                    style: AppType.muted(
                      color: Colors.white.withValues(alpha: 0.75),
                    ).copyWith(fontSize: 11, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 7),
            Row(
              children: [
                const Icon(LucideIcons.star,
                    color: Color(0xFFFCD34D), size: 13),
                const SizedBox(width: 4),
                Text(
                  '${formatIQD(wallet!.points.round())} نقطة',
                  style: AppType.muted(
                    color: Colors.white.withValues(alpha: 0.9),
                  ).copyWith(fontSize: 11, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Orange gradient card — hero debt total in IQD with the debtors count
/// as a small line below. Mirrors v1's _DebtCard exactly.
class _DebtCard extends StatelessWidget {
  const _DebtCard({required this.debtors});
  final DebtorsResult? debtors;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFEA580C), Color(0xFFC2410C)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(R.lg),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFEA580C).withValues(alpha: 0.2),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(LucideIcons.creditCard,
                  color: Colors.white, size: 16),
              const SizedBox(width: 5),
              Text(
                'المدينون',
                style: AppType.muted(
                  color: Colors.white.withValues(alpha: 0.85),
                ).copyWith(fontSize: 11, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (debtors == null)
            const SizedBox(
              height: 22,
              width: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          else ...[
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    formatIQD(debtors!.total),
                    style: AppType.title(color: Colors.white).copyWith(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      height: 1.1,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'IQD',
                    style: AppType.muted(
                      color: Colors.white.withValues(alpha: 0.75),
                    ).copyWith(fontSize: 11, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 7),
            Row(
              children: [
                Icon(LucideIcons.users,
                    color: Colors.white.withValues(alpha: 0.85), size: 13),
                const SizedBox(width: 4),
                Text(
                  '${debtors!.count} مشترك',
                  style: AppType.muted(
                    color: Colors.white.withValues(alpha: 0.9),
                  ).copyWith(fontSize: 11, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
