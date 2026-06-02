import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/mock/dashboard_data.dart';
import '../../../core/util/format.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';

enum _Period { day, week, month }

/// Net-revenue hero with a day / week / month switcher (matches the v1
/// web version per user request round 8). Each period swaps in its own
/// total, delta vs previous period, and sparkline points.
class HeroRevenueCard extends StatefulWidget {
  const HeroRevenueCard({super.key, required this.stats});

  /// Kept on the API for backwards compat — the daily fallback comes
  /// from this object when the mock day-only data isn't useful (e.g.,
  /// once we wire a real per-period endpoint later).
  final DailyStats stats;

  @override
  State<HeroRevenueCard> createState() => _HeroRevenueCardState();
}

class _HeroRevenueCardState extends State<HeroRevenueCard> {
  _Period _period = _Period.day;

  NetRevenuePeriod get _data => switch (_period) {
        _Period.day => mockRevenueDaily,
        _Period.week => mockRevenueWeekly,
        _Period.month => mockRevenueMonthly,
      };

  String get _deltaLabel => switch (_period) {
        _Period.day => 'مقارنة بأمس',
        _Period.week => 'مقارنة بالأسبوع السابق',
        _Period.month => 'مقارنة بالشهر السابق',
      };

  void _select(_Period p) {
    if (p == _period) return;
    HapticFeedback.selectionClick();
    setState(() => _period = p);
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    final isUp = d.deltaPct >= 0;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.lg),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.all(Sp.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(
                  color: AppColors.brand,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: Sp.sm),
              Text(
                'صافي ${d.label}',
                style: AppType.label(color: AppColors.textMid)
                    .copyWith(fontSize: 12),
              ),
              const Spacer(),
              _PeriodTabs(current: _period, onSelect: _select),
            ],
          ),
          const SizedBox(height: Sp.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                formatIQD(d.amount),
                style: AppType.title(color: AppColors.textHi).copyWith(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                  height: 1.05,
                ),
              ),
              const SizedBox(width: 6),
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(
                  'د.ع',
                  style: AppType.subtitle(color: AppColors.textMid)
                      .copyWith(fontSize: 12),
                ),
              ),
              const Spacer(),
              Row(
                children: [
                  Icon(
                    isUp
                        ? Icons.arrow_upward_rounded
                        : Icons.arrow_downward_rounded,
                    color: isUp ? AppColors.brand : AppColors.error,
                    size: 12,
                  ),
                  const SizedBox(width: 2),
                  Text(
                    formatDeltaPct(d.deltaPct),
                    style: AppType.label(
                      color: isUp ? AppColors.brand : AppColors.error,
                    ).copyWith(fontSize: 11),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            _deltaLabel,
            style: AppType.muted(color: AppColors.textLow)
                .copyWith(fontSize: 10),
          ),
          const SizedBox(height: Sp.sm),
          SizedBox(
            height: 32,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child: LineChart(
                key: ValueKey(_period),
                LineChartData(
                  lineBarsData: [
                    LineChartBarData(
                      isCurved: true,
                      curveSmoothness: 0.35,
                      color: AppColors.brand,
                      barWidth: 2.2,
                      dotData: const FlDotData(show: false),
                      belowBarData: BarAreaData(
                        show: true,
                        gradient: LinearGradient(
                          colors: [
                            AppColors.brand.withValues(alpha: 0.25),
                            AppColors.brand.withValues(alpha: 0),
                          ],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                      ),
                      spots: [
                        for (int i = 0; i < d.points.length; i++)
                          FlSpot(i.toDouble(), d.points[i].toDouble()),
                      ],
                    ),
                  ],
                  gridData: const FlGridData(show: false),
                  titlesData: const FlTitlesData(show: false),
                  borderData: FlBorderData(show: false),
                  lineTouchData: const LineTouchData(enabled: false),
                  minY: 0,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PeriodTabs extends StatelessWidget {
  const _PeriodTabs({required this.current, required this.onSelect});
  final _Period current;
  final ValueChanged<_Period> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: AppColors.surfaceInput,
        borderRadius: BorderRadius.circular(R.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _tab(_Period.day, 'يومي'),
          _tab(_Period.week, 'أسبوعي'),
          _tab(_Period.month, 'شهري'),
        ],
      ),
    );
  }

  Widget _tab(_Period p, String label) {
    final selected = current == p;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onSelect(p),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(
          horizontal: 10,
          vertical: 4,
        ),
        decoration: BoxDecoration(
          color: selected ? AppColors.brand : Colors.transparent,
          borderRadius: BorderRadius.circular(R.pill),
        ),
        child: Text(
          label,
          style: AppType.muted(
            color: selected ? Colors.white : AppColors.textMid,
          ).copyWith(fontSize: 10, fontWeight: selected ? FontWeight.w700 : FontWeight.w500),
        ),
      ),
    );
  }
}
