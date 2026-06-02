import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../api/dashboard_api.dart';
import '../../../core/mock/dashboard_data.dart';
import '../../../core/util/format.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';

/// Revenue hero — labelled "الإيرادات" (was "صافي اليوم"). Pulls live
/// totals from /api/reports/finance for whichever period the user picks
/// (day / week / month). The number on display is `data.totals.total_payments`,
/// exactly what the v1 web Financial Reports page shows as "الإيرادات".
class HeroRevenueCard extends StatefulWidget {
  const HeroRevenueCard({super.key, required this.stats});
  final DailyStats stats; // kept for the sparkline placeholder

  @override
  State<HeroRevenueCard> createState() => _HeroRevenueCardState();
}

class _HeroRevenueCardState extends State<HeroRevenueCard> {
  RevenuePeriod _period = RevenuePeriod.day;

  // Cache live results per period so flipping back to a previously-loaded
  // tab is instant. Each entry: null = not loaded yet, value = live result.
  final Map<RevenuePeriod, int?> _liveAmounts = {
    RevenuePeriod.day: null,
    RevenuePeriod.week: null,
    RevenuePeriod.month: null,
  };
  RevenuePeriod? _loading;

  @override
  void initState() {
    super.initState();
    // Warm the current tab on first build.
    _refresh(_period);
  }

  Future<void> _refresh(RevenuePeriod p) async {
    setState(() => _loading = p);
    final r = await DashboardApi.fetchRevenue(p);
    if (!mounted) return;
    setState(() {
      if (r != null) _liveAmounts[p] = r.amount;
      _loading = null;
    });
  }

  int get _displayAmount {
    final live = _liveAmounts[_period];
    if (live != null) return live;
    // Fallback: while loading or on failure, show the mock for the
    // matching period so the card isn't blank.
    return switch (_period) {
      RevenuePeriod.day => mockRevenueDaily.amount,
      RevenuePeriod.week => mockRevenueWeekly.amount,
      RevenuePeriod.month => mockRevenueMonthly.amount,
    };
  }

  String get _periodLabel => switch (_period) {
        RevenuePeriod.day => 'اليوم',
        RevenuePeriod.week => 'هذا الأسبوع',
        RevenuePeriod.month => 'هذا الشهر',
      };

  List<int> get _sparkline => switch (_period) {
        RevenuePeriod.day => mockRevenueDaily.points,
        RevenuePeriod.week => mockRevenueWeekly.points,
        RevenuePeriod.month => mockRevenueMonthly.points,
      };

  void _select(RevenuePeriod p) {
    if (p == _period) return;
    HapticFeedback.selectionClick();
    setState(() => _period = p);
    if (_liveAmounts[p] == null) _refresh(p);
  }

  @override
  Widget build(BuildContext context) {
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
                'الإيرادات • $_periodLabel',
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
                formatIQD(_displayAmount),
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
              if (_loading == _period)
                const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.6,
                    color: AppColors.brand,
                  ),
                ),
            ],
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
                        for (int i = 0; i < _sparkline.length; i++)
                          FlSpot(i.toDouble(), _sparkline[i].toDouble()),
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
  final RevenuePeriod current;
  final ValueChanged<RevenuePeriod> onSelect;

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
          _tab(RevenuePeriod.day, 'يومي'),
          _tab(RevenuePeriod.week, 'أسبوعي'),
          _tab(RevenuePeriod.month, 'شهري'),
        ],
      ),
    );
  }

  Widget _tab(RevenuePeriod p, String label) {
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
          ).copyWith(
            fontSize: 10,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
