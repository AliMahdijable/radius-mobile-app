import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/util/format.dart';
import '../../../models/dashboard.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';

/// Subscribers card v2: hero total on the left with a brand-tinted
/// progress ring around it, status grid on the right.
///
/// stats=null → loading skeleton (no fabricated numbers). Real data
/// flows in once SAS4 + debtors fetches complete.
class SubscribersCard extends StatelessWidget {
  const SubscribersCard({super.key, required this.stats});

  final SubscribersStats? stats;

  @override
  Widget build(BuildContext context) {
    if (stats == null) return const _Skeleton();
    final s = stats!;
    final activeRatio = s.total == 0 ? 0.0 : s.active / s.total;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
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
      padding: const EdgeInsets.all(Sp.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with title + total badge inline
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: AppColors.brand.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(R.sm),
                ),
                child: const Icon(LucideIcons.users,
                    color: AppColors.brand, size: 16),
              ),
              const SizedBox(width: Sp.sm),
              Text('المشتركون',
                  style: AppType.label(color: AppColors.textHi)
                      .copyWith(fontSize: 14)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.brand.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(R.pill),
                ),
                child: Text(
                  '${(activeRatio * 100).round()}% نشط',
                  style: AppType.muted(color: AppColors.brand)
                      .copyWith(fontSize: 11, fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: Sp.lg),
          // Hero row: big total on the right, ring on the left
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _TotalWithRing(total: s.total, ratio: activeRatio),
              const SizedBox(width: Sp.lg),
              Expanded(
                child: _statsList(s),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Vertical list of 4 stat lines on the trailing side of the hero.
  /// Each line is a compact pill: icon + label + value, with the value
  /// on the far end. Reads top-to-bottom in priority order (active →
  /// online → expired → near expiry).
  Widget _statsList(SubscribersStats s) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _StatLine(
          icon: LucideIcons.circleCheck,
          label: 'نشط',
          value: s.active,
          color: AppColors.brand,
        ),
        const SizedBox(height: 6),
        _StatLine(
          icon: LucideIcons.wifi,
          label: 'متصل الآن',
          value: s.online,
          color: const Color(0xFF3B82F6),
        ),
        const SizedBox(height: 6),
        _StatLine(
          icon: LucideIcons.timerOff,
          label: 'منتهي',
          value: s.expired,
          color: AppColors.error,
        ),
        const SizedBox(height: 6),
        _StatLine(
          icon: LucideIcons.triangleAlert,
          label: 'قارب الانتهاء',
          value: s.nearExpiry,
          color: const Color(0xFFE08F2D),
        ),
      ],
    );
  }
}

/// One row in the stats list — icon chip, label, value. Larger than the
/// old 2×2 grid; reads cleanly without label truncation since each row
/// has the full card width to spread out.
class _StatLine extends StatelessWidget {
  const _StatLine({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });
  final IconData icon;
  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: Sp.sm, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(R.sm),
          border: Border.all(color: color.withValues(alpha: 0.15)),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 14),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                label,
                style: AppType.muted(color: AppColors.textMid)
                    .copyWith(fontSize: 11),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(
              '$value',
              style: AppType.title(color: color).copyWith(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                height: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Loading skeleton for the subscribers card. Same outer shape so the
/// layout doesn't jump when real data arrives.
class _Skeleton extends StatelessWidget {
  const _Skeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 220,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.lg),
        border: Border.all(color: AppColors.border),
      ),
      child: const Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            strokeWidth: 2.4,
            color: AppColors.brand,
          ),
        ),
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

