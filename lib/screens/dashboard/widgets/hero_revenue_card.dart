import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../api/dashboard_api.dart';
import '../../../core/util/format.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';

/// Revenue hero card. Pulls live totals from /api/reports/finance for
/// the selected period (day/week/month). No mock fallbacks — while a
/// period is loading we show a spinner and dashes; on error we show an
/// inline error label. Sparkline is omitted until the timeseries field
/// is wired (it was previously rendering mock points, which the user
/// noticed and asked us to drop).
class HeroRevenueCard extends StatefulWidget {
  const HeroRevenueCard({super.key});

  @override
  State<HeroRevenueCard> createState() => _HeroRevenueCardState();
}

class _HeroRevenueCardState extends State<HeroRevenueCard> {
  RevenuePeriod _period = RevenuePeriod.day;

  // null = not loaded yet; -1 = fetch failed; else = live total.
  // Using a sentinel keeps the cache shape simple without a parallel set.
  final Map<RevenuePeriod, int?> _amounts = {
    RevenuePeriod.day: null,
    RevenuePeriod.week: null,
    RevenuePeriod.month: null,
  };
  final Set<RevenuePeriod> _failed = {};
  RevenuePeriod? _loading;

  @override
  void initState() {
    super.initState();
    _refresh(_period);
  }

  Future<void> _refresh(RevenuePeriod p) async {
    setState(() {
      _loading = p;
      _failed.remove(p);
    });
    final r = await DashboardApi.fetchRevenue(p);
    if (!mounted) return;
    setState(() {
      if (r != null) {
        _amounts[p] = r.amount;
      } else {
        _failed.add(p);
      }
      _loading = null;
    });
  }

  bool get _periodFailed => _failed.contains(_period);
  bool get _periodLoading => _loading == _period && _amounts[_period] == null;
  int? get _amount => _amounts[_period];

  String get _periodLabel => switch (_period) {
        RevenuePeriod.day => 'اليوم',
        RevenuePeriod.week => 'هذا الأسبوع',
        RevenuePeriod.month => 'هذا الشهر',
      };

  void _select(RevenuePeriod p) {
    if (p == _period) return;
    HapticFeedback.selectionClick();
    setState(() => _period = p);
    if (_amounts[p] == null && !_failed.contains(p)) _refresh(p);
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
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (_periodLoading)
                const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    color: AppColors.brand,
                  ),
                )
              else if (_periodFailed)
                Row(
                  children: [
                    const Icon(LucideIcons.triangleAlert,
                        color: AppColors.error, size: 16),
                    const SizedBox(width: 6),
                    Text(
                      'تعذّر الجلب — اسحب للتحديث',
                      style: AppType.label(color: AppColors.error)
                          .copyWith(fontSize: 12),
                    ),
                  ],
                )
              else if (_amount != null) ...[
                Text(
                  formatIQD(_amount!),
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
              ],
            ],
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
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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

// Sparkline (fl_chart LineChart) dropped along with mock data — re-add
// once /api/reports/finance's `data.timeseries` is wired into RevenueResult.
