import 'dart:math' as math;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../models/dashboard.dart';
import '../../../screens/subscribers/widgets/filter_chips_bar.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';

/// Subscribers card — direct port of v1's
/// mobile-app/lib/screens/dashboard_screen.dart layout. Same shape:
///   • 130×130 dual-arc ring (active teal + expired red) on the leading
///     side, big total + 'مشترك' label inside.
///   • 5 tappable _RingStatRow on the trailing side (الفعالين, متصل الآن,
///     غير متصل, منتهي, قريب الانتهاء).
///   • Thin gradient progress bar underneath (active teal vs expired red).
///
/// stats=null → loading skeleton. onOpen wires each tap target back to
/// MainShell so the subscribers tab opens with the matching filter.
class SubscribersCard extends StatelessWidget {
  const SubscribersCard({super.key, required this.stats, this.onOpen});

  final SubscribersStats? stats;
  final ValueChanged<SubscriberFilter?>? onOpen;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    if (stats == null) return const _Skeleton();
    final s = stats!;
    final activeRatio = s.total > 0 ? s.active / s.total : 0.0;
    final expiredRatio = s.total > 0 ? s.expired / s.total : 0.0;

    return Container(
      padding: const EdgeInsets.all(Sp.xl),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.xl),
        border: Border.all(
          color: AppColors.brand.withValues(alpha: 0.08),
        ),
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _Ring(
                total: s.total,
                activeRatio: activeRatio,
                expiredRatio: expiredRatio,
                onTap: onOpen == null
                    ? null
                    : () => onOpen!(SubscriberFilter.all),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  children: [
                    _RingStatRow(
                      color: AppColors.brand,
                      icon: LucideIcons.circleCheck,
                      label: 'dashboard.active'.tr(),
                      value: s.active,
                      onTap: onOpen == null
                          ? null
                          : () => onOpen!(SubscriberFilter.active),
                    ),
                    const SizedBox(height: 7),
                    _RingStatRow(
                      color: const Color(0xFF26A69A),
                      icon: LucideIcons.wifi,
                      label: 'dashboard.online'.tr(),
                      value: s.online,
                      onTap: onOpen == null
                          ? null
                          : () => onOpen!(SubscriberFilter.online),
                    ),
                    const SizedBox(height: 7),
                    _RingStatRow(
                      color: const Color(0xFF90A4AE),
                      icon: LucideIcons.wifiOff,
                      label: 'dashboard.offline'.tr(),
                      value: s.offline,
                      onTap: onOpen == null
                          ? null
                          : () => onOpen!(SubscriberFilter.offline),
                    ),
                    const SizedBox(height: 7),
                    _RingStatRow(
                      color: const Color(0xFFEF5350),
                      icon: LucideIcons.timerOff,
                      label: 'dashboard.expired'.tr(),
                      value: s.expired,
                      onTap: onOpen == null
                          ? null
                          : () => onOpen!(SubscriberFilter.expired),
                    ),
                    const SizedBox(height: 7),
                    _RingStatRow(
                      color: Colors.deepOrange,
                      icon: LucideIcons.triangleAlert,
                      label: 'dashboard.near_expiry'.tr(),
                      value: s.nearExpiry,
                      onTap: onOpen == null
                          ? null
                          : () => onOpen!(SubscriberFilter.nearExpiry),
                    ),
                    const SizedBox(height: 7),
                    // "بدون نت" — متصل + منتهي. لون بنفسجي مطابق
                    // للـchip في صفحة المشتركين والويب.
                    _RingStatRow(
                      color: const Color(0xFF9333EA),
                      icon: LucideIcons.wifiOff,
                      label: 'dashboard.online_no_plan'.tr(),
                      value: s.onlineNoPlan,
                      onTap: onOpen == null
                          ? null
                          : () => onOpen!(SubscriberFilter.onlineNoPlan),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Active vs expired gradient bar. Flex ratios match v1: when
          // there are 0 active subs the active strip still shows a
          // 1-flex hint so the bar isn't entirely red.
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              height: 6,
              child: Row(
                children: [
                  Expanded(
                    flex: s.active > 0 ? s.active : 1,
                    child: Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Color(0xFF1F4634), // brand darker
                            Color(0xFF26A69A), // teal400
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (s.expired > 0)
                    Expanded(
                      flex: s.expired,
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.red.shade400,
                              Colors.red.shade700,
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Loading skeleton matching the card's resting height so the dashboard
/// doesn't jump when real data arrives.
class _Skeleton extends StatelessWidget {
  const _Skeleton();
  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Container(
      height: 220,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.xl),
        border: Border.all(
          color: AppColors.brand.withValues(alpha: 0.08),
        ),
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

/// 130×130 dual-arc ring with the total + 'مشترك' label centered.
/// Same dimensions and behavior as v1's `Container(width:130, height:130)
/// + CustomPaint(_RingPainter)`.
class _Ring extends StatelessWidget {
  const _Ring({
    required this.total,
    required this.activeRatio,
    required this.expiredRatio,
    this.onTap,
  });

  final int total;
  final double activeRatio;
  final double expiredRatio;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 130,
        height: 130,
        child: CustomPaint(
          painter: _RingPainter(
            activeRatio: activeRatio,
            expiredRatio: expiredRatio,
          ),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$total',
                  style: AppType.title(color: AppColors.brand).copyWith(
                    fontSize: 30,
                    fontWeight: FontWeight.w900,
                    height: 1,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'dashboard.subscriber_singular'.tr(),
                  style: AppType.muted(color: AppColors.textLow)
                      .copyWith(fontSize: 10, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One stat row in the trailing list. Icon-box (rounded square, 8px
/// radius) + label + value + chevron. Tappable surface highlights on
/// press; matches v1's _RingStatRow 1:1.
class _RingStatRow extends StatelessWidget {
  const _RingStatRow({
    required this.color,
    required this.icon,
    required this.label,
    required this.value,
    this.onTap,
  });

  final Color color;
  final IconData icon;
  final String label;
  final int value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 15),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: AppType.label(color: AppColors.textMid)
                  .copyWith(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
          Text(
            '$value',
            style: AppType.title(color: color).copyWith(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              height: 1,
            ),
          ),
          const SizedBox(width: 4),
          Icon(
            LucideIcons.chevronLeft,
            size: 16,
            color: AppColors.textLow,
          ),
        ],
      ),
    );
  }
}

/// Direct port of v1's _RingPainter. Background ring (teal100 tint),
/// then the active arc (teal sweep), then the expired arc (red sweep)
/// with a 0.04 rad gap between them so they read as separate segments.
class _RingPainter extends CustomPainter {
  _RingPainter({required this.activeRatio, required this.expiredRatio});

  final double activeRatio;
  final double expiredRatio;

  static const _stroke = 14.0;
  static const _startAngle = -math.pi / 2;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 10;

    final bgPaint = Paint()
      ..color = const Color(0xFFB2DFDB).withValues(alpha: 0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = _stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, bgPaint);

    if (activeRatio <= 0) return;

    final rect = Rect.fromCircle(center: center, radius: radius);
    final activeSweep = 2 * math.pi * activeRatio;

    final activeGradient = SweepGradient(
      startAngle: _startAngle,
      endAngle: _startAngle + activeSweep,
      colors: const [
        Color(0xFF80CBC4), // teal300
        Color(0xFF26A69A), // teal400
        Color(0xFF2D5F47), // brand (teal800-ish)
      ],
      stops: const [0.0, 0.5, 1.0],
    );
    final activePaint = Paint()
      ..shader = activeGradient.createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = _stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, _startAngle, activeSweep, false, activePaint);

    if (expiredRatio <= 0) return;

    const gap = 0.04;
    final expiredSweep = 2 * math.pi * expiredRatio;
    final expiredGradient = SweepGradient(
      startAngle: _startAngle + activeSweep + gap,
      endAngle: _startAngle + activeSweep + expiredSweep,
      colors: const [
        Color(0xFFEF9A9A),
        Color(0xFFE53935),
        Color(0xFFB71C1C),
      ],
      stops: const [0.0, 0.5, 1.0],
    );
    final expiredPaint = Paint()
      ..shader = expiredGradient.createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = _stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      rect,
      _startAngle + activeSweep + gap,
      expiredSweep - gap,
      false,
      expiredPaint,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.activeRatio != activeRatio || old.expiredRatio != expiredRatio;
}
