import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../api/package_report_api.dart';
import '../../../core/platform/desktop_layout.dart';
import '../../../core/util/format.dart';
import '../../../core/widgets/permission_locked.dart';
import '../../../services/app_resumed_signal.dart';
import '../../../services/dashboard_refresh_signal.dart';
import '../../../services/merged_mode.dart';
import '../../../services/subscriber_events.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';
import '../../desktop/desk_widgets.dart';
import '../../reports/package_distribution_screen.dart';
import '../../reports/widgets/date_range_chip.dart';
import '../../reports/widgets/scope_helper.dart';
import 'pill_tabs.dart';

/// «توزيع الباقات» في الرئيسيّة (#٥ — طلب المالك ٢٥ أكتوبر: «مختصر منهن بشكل كارتات بالداش بورد وبالتطبيق يتضمنن بنطاق
/// العرض وصلاحيات الموظفين»).
///
/// مختصر التقرير لفترةٍ تُختار باختصار (اليوم · أمس · الأسبوع الماضي · الشهر الماضي) كبطاقة الويب: الفعّالون من الكلّ · التفعيلات وتمديداتها · الربح المقدَّر لصاحب الحساب وحده
/// (قرار الخادم: `owner`) أو عدد الباقات للموظّف · أكثر ٤ باقاتٍ فعّالين بشريط حصّة · «التقرير الكامل».
///
/// - القسم في «نطاق العرض» (`packages`) يُخفى كغيره؛ والمقفل (بلا «التقرير الماليّ») لا يبني هذه الودجة أصلاً — المتّصل
///   يعرض بطاقة القفل مكانها، فلا نداء. وردٌّ ٤٠٣ (صلاحيّةٌ سُحبت بعد آخر تحديث) ⇒ قفلٌ هنا لا «تعذّر».
/// - «كل الشركات»: للشركة المختارة في الشريط (موجَّهاً)؛ بلا اختيارٍ سطرٌ يطلبه — باقات الشركات لا تُجمع.
/// - تتحدّث مع أيّ عمليّة مشترك، والرجوع من الخلفيّة، وسحب التحديث — كبطاقة الإيرادات.
class PackagesSummaryCard extends StatefulWidget {
  const PackagesSummaryCard({super.key});

  static const top = 4;

  /// اختصارات الفترة (المالك ٢٥ أكتوبر: «اختصارات سريعة تتغير مع القيمة: اليوم، أمس، الأسبوع الماضي، الشهر الماضي»).
  /// الفعّالون والربح المقدَّر حالةُ الآن — الفترة تغيّر التفعيلات والتمديدات وحركة الباقات.
  static const periods = ['today', 'yesterday', 'last_week', 'last_month'];

  static DateRange rangeOf(String period) => switch (period) {
        'yesterday' => DateRange.yesterday(),
        'last_week' => DateRange.lastWeek(),
        'last_month' => DateRange.lastMonth(),
        _ => DateRange.today(),
      };

  @override
  State<PackagesSummaryCard> createState() => _PackagesSummaryCardState();
}

class _PackagesSummaryCardState extends State<PackagesSummaryCard> {
  PackageReport? _data;
  String? _error;
  bool _loading = true;
  bool _denied = false;
  bool _needsFocus = false;
  int _gen = 0;

  /// الفترة المختارة — تُحفظ على الجهاز (آخر اختيارٍ يبقى).
  String _period = PackagesSummaryCard.periods.first;
  static const _periodKey = 'pkgcard.period';

  /// «الربح المقدَّر» مخفيٌّ حتى يُظهره صاحب الحساب (المالك ٢٥ أكتوبر: «خلي مخفي الا يظهر الشخص… حتى لاتصير خربطه
  /// بينه وبين الايرادات اعلاه») — واختياره يُحفظ على الجهاز كالفترة.
  bool _showProfit = false;
  static const _profitKey = 'pkgcard.show_profit';

  @override
  void initState() {
    super.initState();
    _restorePrefs();
    SubscriberEvents.dataChanged.addListener(_load);
    AppResumedSignal.tick.addListener(_load);
    DashboardRefreshSignal.tick.addListener(_load);
    MergedMode.active.addListener(_onScopeChanged);
    MergedMode.focus.addListener(_onScopeChanged);
  }

  @override
  void dispose() {
    SubscriberEvents.dataChanged.removeListener(_load);
    AppResumedSignal.tick.removeListener(_load);
    DashboardRefreshSignal.tick.removeListener(_load);
    MergedMode.active.removeListener(_onScopeChanged);
    MergedMode.focus.removeListener(_onScopeChanged);
    super.dispose();
  }

  /// شركةٌ أخرى ⇒ لا تبقى أرقام السابقة لحظةً تحت اسم غيرها.
  void _onScopeChanged() {
    if (!mounted) return;
    setState(() {
      _data = null;
      _error = null;
    });
    _load();
  }

  Future<void> _restorePrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final v = prefs.getString(_periodKey);
      if (v != null && PackagesSummaryCard.periods.contains(v)) _period = v;
      _showProfit = prefs.getBool(_profitKey) ?? false;
    } catch (_) {/* الافتراضيّ: اليوم، والربح مخفيّ */}
    _load();
  }

  void _setShowProfit(bool v) {
    setState(() => _showProfit = v);
    SharedPreferences.getInstance().then((p) => p.setBool(_profitKey, v)).catchError((_) => false);
  }

  void _pick(String period) {
    if (period == _period) return;
    setState(() {
      _period = period;
      _data = null;
      _error = null;
    });
    _load();
    SharedPreferences.getInstance().then((p) => p.setString(_periodKey, period)).catchError((_) => false);
  }

  Future<void> _load() async {
    if (!mounted) return;
    final gen = ++_gen;
    final merged = MergedMode.active.value;
    final focused = merged ? MergedMode.focused : null;
    if (merged && focused == null) {
      setState(() {
        _needsFocus = true;
        _loading = false;
        _data = null;
        _error = null;
      });
      return;
    }
    setState(() {
      _needsFocus = false;
      _loading = _data == null;
    });
    final range = PackagesSummaryCard.rangeOf(_period);
    final ids = focused == null ? await loadScopeUserIds() : null;
    final r = await PackageReportApi.fetch(
      from: range.from,
      to: range.to,
      userIds: ids,
      companyKey: focused?.key,
    );
    if (!mounted || gen != _gen) return;
    setState(() {
      _loading = false;
      _denied = r.status == 403;
      if (r.data != null) {
        _data = r.data;
        _error = null;
      } else {
        // تحديثٌ صامتٌ فشل والأرقام معروضة: تبقى (لا وميض «تعذّر» فوق أرقامٍ صحيحةٍ قبل لحظة).
        _error =
            _data == null ? (r.error ?? 'pkgdist.fetch_failed'.tr()) : null;
      }
    });
  }

  void _openReport() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const PackageDistributionScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    // ٤٠٣: صلاحيّةٌ سُحبت بعد آخر تحديث — مقفلةٌ بمكانها كبقيّة الأقسام، لا «تعذّر».
    if (_denied) {
      return LockedCard(
          title: 'pkgdist.card_title'.tr(), icon: LucideIcons.package);
    }
    final desk = DesktopScope.of(context);
    return Container(
      // الحاسبة: بحدّ بطاقاتها وظلّها كبقيّة الرئيسيّة؛ الهاتف كبطاقة الإيرادات.
      decoration: desk
          ? DeskCard.decoration(radius: R.lg)
          : BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(R.lg),
              border: Border.all(color: AppColors.border),
            ),
      padding: const EdgeInsets.all(Sp.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(),
          const SizedBox(height: Sp.sm),
          _periodBar(),
          const SizedBox(height: Sp.sm),
          ..._body(),
        ],
      ),
    );
  }

  Widget _header() {
    return Row(
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: AppColors.brand.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(R.sm),
          ),
          child: Icon(LucideIcons.package, size: 16, color: AppColors.brand),
        ),
        const SizedBox(width: Sp.sm),
        // `Expanded` لا نصّ عارٍ: يُقصّ العنوان ولا يُخرج «التقرير الكامل» عن الحافّة (كبطاقة الإيرادات).
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'pkgdist.card_title'.tr(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppType.label(color: AppColors.textHi)
                    .copyWith(fontSize: 13.5, fontWeight: FontWeight.w700),
              ),
              Text(
                'pkgdist.card_period_x'.tr(namedArgs: {'period': PackagesSummaryCard.rangeOf(_period).label}),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppType.micro(color: AppColors.textLow),
              ),
            ],
          ),
        ),
        TextButton.icon(
          onPressed: _openReport,
          style: TextButton.styleFrom(
            foregroundColor: AppColors.brand,
            padding: const EdgeInsets.symmetric(horizontal: Sp.sm),
            visualDensity: VisualDensity.compact,
          ),
          icon: const Icon(LucideIcons.chevronLeft, size: 16),
          label: Text(
            'pkgdist.full_report'.tr(),
            style: AppType.label(color: AppColors.brand)
                .copyWith(fontSize: 12.5, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }

  /// الاختصارات الأربعة بشكل فترات بطاقة الإيرادات («يومي · أسبوعي · شهري»): حبوبٌ في مسارٍ واحد بطرف البطاقة.
  Widget _periodBar() {
    return Align(
      alignment: AlignmentDirectional.centerEnd,
      child: PillTabs<String>(
        options: [for (final p in PackagesSummaryCard.periods) (p, PackagesSummaryCard.rangeOf(p).label)],
        current: _period,
        onSelect: _pick,
      ),
    );
  }

  List<Widget> _body() {
    if (_needsFocus) {
      return [
        _note(LucideIcons.info, 'pkgdist.pick_company'.tr(), AppColors.textLow)
      ];
    }
    if (_loading) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: Sp.lg),
          child: Center(
            child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                  strokeWidth: 2.2, color: AppColors.brand),
            ),
          ),
        ),
      ];
    }
    final d = _data;
    if (d == null) {
      return [
        InkWell(
          onTap: _load,
          borderRadius: BorderRadius.circular(R.sm),
          child: _note(
              LucideIcons.triangleAlert,
              '${_error ?? 'pkgdist.fetch_failed'.tr()} — ${'pkgdist.retry'.tr()}',
              AppColors.error),
        ),
      ];
    }
    final t = d.totals;
    final (:top, :rest) = d.topRows(PackagesSummaryCard.top);
    final byActive = d.countsKnown;
    final max = top.fold<int>(0, (m, r) {
      final v = byActive ? (r.subscribersActive ?? 0) : r.activations;
      return v > m ? v : m;
    });
    return [
      Row(
        children: [
          Expanded(
            child: _Stat(
              icon: LucideIcons.users,
              color: AppColors.brand,
              label: 'pkgdist.active'.tr(),
              value: t.subscribersActive == null
                  ? '—'
                  : formatIQD(t.subscribersActive!),
              hint: t.subscribersTotal == null
                  ? 'pkgdist.unavailable'.tr()
                  : 'pkgdist.of_total'
                      .tr(namedArgs: {'total': formatIQD(t.subscribersTotal!)}),
            ),
          ),
          Container(width: 1, height: 40, color: AppColors.border),
          Expanded(
            child: _Stat(
              icon: LucideIcons.zap,
              color: AppColors.success,
              label: 'pkgdist.activations'.tr(),
              value: formatIQD(t.activations),
              hint: 'pkgdist.extensions_n'
                  .tr(namedArgs: {'n': formatIQD(t.extensions)}),
            ),
          ),
          if (!d.owner) ...[
            Container(width: 1, height: 40, color: AppColors.border),
            Expanded(
              child: _Stat(
                icon: LucideIcons.package,
                color: AppColors.warning,
                label: 'pkgdist.packages'.tr(),
                value: formatIQD(t.packages),
                hint: 'pkgdist.packages_hint'.tr(),
              ),
            ),
          ],
        ],
      ),
      // الربح (مبلغٌ طويل) بعرض السطر لا ثلثه — رقمٌ ماليٌّ مقصوصٌ يُقرأ خطأً. مخفيٌّ افتراضيّاً: لا رقم بجانب التفعيلات
      // يُظنّ إيراداً — سطرٌ «إظهار» مكانه.
      if (d.owner) ...[
        const SizedBox(height: Sp.sm),
        _showProfit
            ? _ProfitRow(
                value: t.profitEstimated,
                onHide: () => _setShowProfit(false),
              )
            : _ProfitReveal(onShow: () => _setShowProfit(true)),
      ],
      const SizedBox(height: Sp.sm),
      if (top.isEmpty)
        _note(LucideIcons.package, 'pkgdist.empty'.tr(), AppColors.textLow)
      else
        for (final r in top)
          _TopRow(
            name: r.name,
            meta: byActive
                ? 'pkgdist.row_counts'.tr(namedArgs: {
                    'active': formatIQD(r.subscribersActive ?? 0),
                    'acts': formatIQD(r.activations),
                  })
                : 'pkgdist.row_acts'
                    .tr(namedArgs: {'acts': formatIQD(r.activations)}),
            share: max > 0
                ? (byActive ? (r.subscribersActive ?? 0) : r.activations) / max
                : 0,
          ),
      if (rest > 0)
        Padding(
          padding: const EdgeInsets.only(top: Sp.xs),
          child: Text(
            rest == 1
                ? 'pkgdist.more_one'.tr()
                : 'pkgdist.more_n'.tr(namedArgs: {'n': '$rest'}),
            style: AppType.micro(color: AppColors.textLow),
          ),
        ),
      for (final p in d.unavailableParts)
        Padding(
          padding: const EdgeInsets.only(top: Sp.xs),
          child: Text(packagePartText(p),
              style: AppType.micro(color: AppColors.warning)),
        ),
      if (d.subscribersPartial)
        Padding(
          padding: const EdgeInsets.only(top: Sp.xs),
          child: Text('pkgdist.partial'.tr(),
              style: AppType.micro(color: AppColors.textLow)),
        ),
    ];
  }

  Widget _note(IconData icon, String text, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Sp.sm),
      child: Row(
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: AppType.label(color: color)
                  .copyWith(fontSize: 12.5, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
    required this.hint,
  });

  final IconData icon;
  final Color color;
  final String label;
  final String value;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(height: 4),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppType.micro(color: AppColors.textLow),
        ),
        // يتقلّص ولا يُقصّ (كملخّص التفعيلات): رقمٌ مبتورٌ يُقرأ خطأً.
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            value,
            maxLines: 1,
            style: AppType.title(color: AppColors.textHi).copyWith(
                fontSize: 17, fontWeight: FontWeight.w700, height: 1.15),
          ),
        ),
        Text(
          hint,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppType.micro(color: AppColors.textLow),
        ),
      ],
    );
  }
}

/// «الربح المقدَّر» مخفيّاً — بمكان [_ProfitRow] ومقاسه، بلا رقم؛ النقر يُظهره.
class _ProfitReveal extends StatelessWidget {
  const _ProfitReveal({required this.onShow});

  final VoidCallback onShow;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'pkgdist.profit_show_full'.tr(),
      excludeSemantics: true,
      child: Material(
        color: AppColors.warning.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(R.md),
        child: InkWell(
          onTap: onShow,
          borderRadius: BorderRadius.circular(R.md),
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: Sp.md, vertical: Sp.sm),
            child: Row(
              children: [
                Icon(LucideIcons.eye, size: 16, color: AppColors.warning),
                const SizedBox(width: Sp.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('pkgdist.profit_est'.tr(),
                          style: AppType.micro(color: AppColors.textMid)),
                      Text('pkgdist.profit_hidden_hint'.tr(),
                          style: AppType.micro(color: AppColors.textLow)),
                    ],
                  ),
                ),
                Text('pkgdist.profit_show'.tr(),
                    style: AppType.labelBold(color: AppColors.brand)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ProfitRow extends StatelessWidget {
  const _ProfitRow({required this.value, required this.onHide});

  final num? value;
  final VoidCallback onHide;

  @override
  Widget build(BuildContext context) {
    final v = value;
    final color = v == null
        ? AppColors.textLow
        : (v < 0 ? AppColors.error : AppColors.success);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: Sp.sm),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(R.md),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.sparkles, size: 16, color: AppColors.warning),
          const SizedBox(width: Sp.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // زرّ الإخفاء بجانب العنوان لا آخر السطر: هناك يأكل عرض التلميح فيلتفّ على ٣٢٠.
                Row(
                  children: [
                    Flexible(
                      child: Text('pkgdist.profit_est'.tr(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppType.micro(color: AppColors.textMid)),
                    ),
                    Tooltip(
                      message: 'pkgdist.profit_hide'.tr(),
                      child: InkResponse(
                        onTap: onHide,
                        radius: 16,
                        child: Padding(
                          padding: const EdgeInsetsDirectional.only(
                              start: 6, end: 4, top: 2, bottom: 2),
                          child: Icon(LucideIcons.eyeOff,
                              size: 14, color: AppColors.textLow),
                        ),
                      ),
                    ),
                  ],
                ),
                Text('pkgdist.profit_est_hint'.tr(),
                    style: AppType.micro(color: AppColors.textLow)),
              ],
            ),
          ),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              v == null
                  ? '—'
                  : '${v < 0 ? '-' : ''}${formatIQD(v)} ${'common.currency'.tr()}',
              maxLines: 1,
              style: AppType.title(color: color)
                  .copyWith(fontSize: 17, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _TopRow extends StatelessWidget {
  const _TopRow({required this.name, required this.meta, required this.share});

  final String name;
  final String meta;
  final double share;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.label(color: AppColors.textHi)
                      .copyWith(fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: Sp.sm),
              Text(meta, style: AppType.micro(color: AppColors.textMid)),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(R.pill),
            child: LinearProgressIndicator(
              value: share.clamp(0, 1).toDouble(),
              minHeight: 5,
              backgroundColor: AppColors.border,
              color: AppColors.brand,
            ),
          ),
        ],
      ),
    );
  }
}
