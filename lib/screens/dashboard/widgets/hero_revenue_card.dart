import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../api/dashboard_api.dart';
import '../../../core/util/format.dart';
import '../../../services/app_resumed_signal.dart';
import '../../../services/subscriber_events.dart';
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
    // Listen for subscriber mutations app-wide so revenue updates
    // immediately after any activate / extend / pay-debt / etc.
    // op succeeds. Without this the parent DashboardScreen
    // refreshed its other cards on the event but the revenue card
    // — owning its own state — kept the stale total visible until
    // the user pulled to refresh or switched periods (user report
    // 2026-06-09: "ما يتحدث بشكل حي مع الحركات").
    SubscriberEvents.dataChanged.addListener(_onDataChanged);
    // إعادة جلب على resume من الخلفيّة — الكارت يملك state خاص
    // ولا يعتمد على _refreshLive في DashboardScreen، فبدون هذا
    // الـlistener الإيرادات تبقى قديمة بعد رجوع التطبيق.
    AppResumedSignal.tick.addListener(_onDataChanged);
  }

  void _onDataChanged() {
    if (!mounted) return;
    // Drop cached values for all 3 periods so the strip doesn't
    // briefly flash stale 'يومي/أسبوعي/شهري' totals when the user
    // switches tabs right after an op. Only re-fetch the active
    // period now — the others will re-fetch lazily when tapped.
    setState(() {
      _amounts[RevenuePeriod.day] = null;
      _amounts[RevenuePeriod.week] = null;
      _amounts[RevenuePeriod.month] = null;
      _failed.clear();
    });
    _refresh(_period);
  }

  @override
  void dispose() {
    SubscriberEvents.dataChanged.removeListener(_onDataChanged);
    AppResumedSignal.tick.removeListener(_onDataChanged);
    super.dispose();
  }

  Future<void> _refresh(RevenuePeriod p) async {
    setState(() {
      _loading = p;
      _failed.remove(p);
    });
    // Safety net: timeout 20 ثانية + catchError — نضمن أن الـUI ما
    // يعلق على spinner للأبد لو الشبكة هنغت أو الـauth refresh دخل
    // بلوب. المدير رفع screenshot 2026-07-22 يوضّح spinner ثابت في
    // كارت البطل بسبب /api/reports/finance بطيء.
    RevenueResult? r;
    try {
      r = await DashboardApi.fetchRevenue(p)
          .timeout(const Duration(seconds: 20));
    } catch (_) {
      r = null;
    }
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
        RevenuePeriod.day => 'reports.today'.tr(),
        RevenuePeriod.week => 'reports.this_week'.tr(),
        RevenuePeriod.month => 'reports.this_month'.tr(),
      };

  void _select(RevenuePeriod p) {
    if (p == _period) return;
    HapticFeedback.selectionClick();
    setState(() => _period = p);
    if (_amounts[p] == null && !_failed.contains(p)) _refresh(p);
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
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
                decoration: BoxDecoration(
                  color: AppColors.brand,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: Sp.sm),
              Text(
                '${'dashboard.revenue'.tr()} • $_periodLabel',
                style: AppType.label(color: AppColors.textMid)
                    .copyWith(fontSize: 12.5, fontWeight: FontWeight.w600),
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
                SizedBox(
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
                    Icon(LucideIcons.triangleAlert,
                        color: AppColors.error, size: 16),
                    const SizedBox(width: 6),
                    Text(
                      'dashboard.fetch_failed_swipe'.tr(),
                      style: AppType.label(color: AppColors.error).copyWith(
                          fontSize: 12.5, fontWeight: FontWeight.w600),
                    ),
                  ],
                )
              else if (_amount != null) ...[
                Text(
                  formatIQD(_amount!),
                  style: AppType.title(color: AppColors.textHi).copyWith(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.4,
                    height: 1.05,
                  ),
                ),
                const SizedBox(width: 6),
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Text(
                    'common.currency'.tr(),
                    style: AppType.subtitle(color: AppColors.textLow)
                        .copyWith(fontSize: 11, fontWeight: FontWeight.w700),
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
    Theme.of(context); // theme-dep (dark-mode)
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: AppColors.surfaceInput,
        borderRadius: BorderRadius.circular(R.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _tab(RevenuePeriod.day, 'dashboard.period_daily'.tr()),
          _tab(RevenuePeriod.week, 'dashboard.period_weekly'.tr()),
          _tab(RevenuePeriod.month, 'dashboard.period_monthly'.tr()),
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
            color: selected ? AppColors.onBrand : AppColors.textMid,
          ).copyWith(
            fontSize: 11,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

// Sparkline (fl_chart LineChart) dropped along with mock data — re-add
// once /api/reports/finance's `data.timeseries` is wired into RevenueResult.
