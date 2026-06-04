import 'dart:math' as math;

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
                  '${(activeRatio * 100).round()}% فعال',
                  style: AppType.muted(color: AppColors.brand)
                      .copyWith(fontSize: 11, fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: Sp.lg),
          // Hero row: ring + 2×2 mini grid on the trailing side. The
          // vertical-list iteration felt too tall on home; back to a
          // compact 2-by-2 per the user.
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _TotalWithRing(total: s.total, ratio: activeRatio),
              const SizedBox(width: Sp.lg),
              Expanded(child: _statsGrid(s)),
            ],
          ),
        ],
      ),
    );
  }

  /// 2×2 compact grid next to the ring. Tooltips carry the label on
  /// long-press so the icons can stay self-explanatory at small size.
  Widget _statsGrid(SubscribersStats s) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _Mini(
                icon: LucideIcons.circleCheck,
                label: 'نشط',
                value: s.active,
                color: AppColors.brand,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _Mini(
                icon: LucideIcons.wifi,
                label: 'متصل الآن',
                value: s.online,
                color: const Color(0xFF3B82F6),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: _Mini(
                icon: LucideIcons.timerOff,
                label: 'منتهي',
                value: s.expired,
                color: AppColors.error,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _Mini(
                icon: LucideIcons.triangleAlert,
                label: 'قارب الانتهاء',
                value: s.nearExpiry,
                color: const Color(0xFFE08F2D),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// One tile in the 2×2 mini grid. Icon + value on a tinted pill —
/// no inline label (it'd clip with 4-tile width). Long-press shows
/// the Arabic label as a tooltip.
class _Mini extends StatelessWidget {
  const _Mini({
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
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(R.sm),
          border: Border.all(color: color.withValues(alpha: 0.18)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Icon(icon, color: color, size: 15),
            Text(
              '$value',
              style: AppType.title(color: AppColors.textHi).copyWith(
                fontSize: 17,
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

/// Ring + total — sized to match the 2×2 mini grid next to it so the
/// row looks balanced (was 120px, dominating the card). The progress
/// arc uses a gradient sweep (brand → teal → brand) for a modern,
/// less flat look. Painted manually so we get gradient + rounded cap
/// + custom stroke width without fighting CircularProgressIndicator.
class _TotalWithRing extends StatelessWidget {
  const _TotalWithRing({required this.total, required this.ratio});

  final int total;
  final double ratio;

  @override
  Widget build(BuildContext context) {
    const size = 92.0; // matches the 2×2 grid height to its right
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: const Size(size, size),
            painter: _GradientRingPainter(ratio: ratio.clamp(0, 1)),
          ),
          Padding(
            // Inset matches the stroke so the text never collides with
            // the arc, even on long totals like 12,345.
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    formatIQD(total),
                    style: AppType.title(color: AppColors.textHi).copyWith(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      height: 1.05,
                      letterSpacing: -0.3,
                    ),
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  'إجمالي',
                  style: AppType.muted(color: AppColors.textLow)
                      .copyWith(fontSize: 9, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GradientRingPainter extends CustomPainter {
  _GradientRingPainter({required this.ratio});
  final double ratio;

  static const _stroke = 6.0;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - _stroke) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    // Background ring — subtle so it's just a hint of where the arc lives.
    final bgPaint = Paint()
      ..color = AppColors.border.withValues(alpha: 0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = _stroke;
    canvas.drawCircle(center, radius, bgPaint);

    if (ratio <= 0) return;

    // Sweep gradient brand → teal → brand. Starting angle is rotated so
    // the gradient seam doesn't sit at the top (where the arc begins).
    final gradient = SweepGradient(
      colors: const [
        Color(0xFF2D5F47), // brand dark
        Color(0xFF14B8A6), // teal accent (mid)
        Color(0xFF2D5F47), // brand dark again so the end ties to the start
      ],
      stops: const [0.0, 0.5, 1.0],
      transform: const GradientRotation(-math.pi / 2),
    );
    final fgPaint = Paint()
      ..shader = gradient.createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = _stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(rect, -math.pi / 2, 2 * math.pi * ratio, false, fgPaint);
  }

  @override
  bool shouldRepaint(_GradientRingPainter old) => old.ratio != ratio;
}

