import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../core/mock/dashboard_data.dart';
import '../../../core/util/format.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';

/// Hero card: today's net revenue as the dominant element.
/// White surface, large black number, small green delta, brand sparkline.
class HeroRevenueCard extends StatelessWidget {
  const HeroRevenueCard({super.key, required this.stats});

  final DailyStats stats;

  @override
  Widget build(BuildContext context) {
    final isUp = stats.netDeltaPct >= 0;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.xl),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.all(Sp.xl),
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
                'الصافي اليوم',
                style: AppType.label(color: AppColors.textMid),
              ),
            ],
          ),
          const SizedBox(height: Sp.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                formatIQD(stats.netToday),
                style: AppType.title(color: AppColors.textHi).copyWith(
                  fontSize: 44,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -1,
                  height: 1.05,
                ),
              ),
              const SizedBox(width: Sp.sm),
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  'د.ع',
                  style: AppType.subtitle(color: AppColors.textMid)
                      .copyWith(fontSize: 14),
                ),
              ),
            ],
          ),
          const SizedBox(height: Sp.xs),
          Row(
            children: [
              Icon(
                isUp ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                color: isUp ? AppColors.brand : AppColors.error,
                size: 14,
              ),
              const SizedBox(width: 2),
              Text(
                '${formatDeltaPct(stats.netDeltaPct)} مقارنة بأمس',
                style: AppType.label(
                  color: isUp ? AppColors.brand : AppColors.error,
                ).copyWith(fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: Sp.lg),
          SizedBox(
            height: 60,
            child: LineChart(
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
                      for (int i = 0; i < stats.last7Days.length; i++)
                        FlSpot(i.toDouble(), stats.last7Days[i].toDouble()),
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
        ],
      ),
    );
  }
}
