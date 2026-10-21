import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../api/merged_finance_api.dart';
import '../../api/reports_api.dart';
import '../settlements/widgets/archive_bar.dart';
import '../../core/util/format.dart';
import '../../services/merged_mode.dart';
import '../../services/permissions_service.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import '../../widgets/company_tag.dart';
import '../../widgets/merged_company_strip.dart';
import 'widgets/action_labels.dart';
import 'widgets/date_range_chip.dart';
import 'widgets/report_export.dart';
import 'widgets/report_filters.dart';
import 'widgets/report_log_tile.dart';
import 'widgets/report_pagination.dart';
import 'widgets/report_permission_gate.dart';
import 'widgets/scope_helper.dart';

/// التقرير المالي — نسخة موبايل من client-v2/Financial.tsx:
///  • هيرو إجمالي الإيراد + صافي بعد المصاريف — ولمالك حسابٍ على ساسٍ بعيد
///    أو ايرث لنك: بعد كلفة الباقات أيضاً (سوبرنت والموظّف بلا تغيير)
///  • شريط فلتر فترة (سريع: اليوم/أمس/هذا الشهر + custom)
///  • KPI cards: نقدي / تسديد / استقطاع / غير نقدي / مصاريف / تفعيلات / تمديدات
///  • قائمة آخر النشاطات المالية (مع تمييز سالب/موجب)
class FinancialReportScreen extends StatefulWidget {
  const FinancialReportScreen({super.key});

  @override
  State<FinancialReportScreen> createState() => _FinancialReportScreenState();
}

class _FinancialReportScreenState extends State<FinancialReportScreen> {
  DateRange _range = DateRange.thisMonth();
  FinanceReport? _data;
  bool _loading = true;
  String? _error;
  List<String>? _scopeIds; // cache — لا يتغيّر خلال الجلسة عملياً
  int _visibleCount = kReportPageStep;

  /// فلاتر متقدّمة (مدير الحركة / مدير المستخدم / الموظف).
  ReportFilters _filters = const ReportFilters();

  /// هل نطلب ما غطّته التسويات؟ الخادم يُخفيه افتراضيّاً من الأرقام
  /// والسلسلة وآخر الحركات والصرفيات معاً (§٤).
  bool _withArchive = false;

  // فلتر النوع القديم (chips) استُبدل بـReportFiltersPanel multi-select
  // في actionTypes. المنطق: _filterLogs يفلتر بحسب _filters.actionTypes.

  /// مفتاح الشاشة — نفسه لحارسها ([ReportPermissionGate]) ولطلبها الأوّل.
  static const _perm = 'reports.financial';

  /// طُلب التقرير بعد؟ الحالة تُبنى ولو أقفل الحارس الشاشة، فكان الطلب يخرج
  /// ويرتدّ ٤٠٣ خلف «لا صلاحيّة». وصلاحيّةٌ تصل والشاشة مفتوحة (تحديث القدرات
  /// بعد الإقلاع) تفتحها — فتطلبه حينها، لا دوّارةً بلا طلب.
  bool _requested = false;

  // ── «كل الشركات» (٢١ أكتوبر، المالك: «حتى التقارير المالية»): تقريرٌ لكلّ شركة موجَّهاً ثمّ المجموع
  // (MergedFinanceApi)، وتفصيلٌ لكلّ شركة، والحركات معاً بشارة شركتها. شركةٌ مختارة في الشريط ⇒ تقريرها وحده كأنّها
  // مفتوحة. فلاتر المدير والموظّف للشركة المفتوحة وحدها (قوائمها منها) فتُخفى هنا، ونوع الحركة يبقى.
  MergedFinanceResult? _mergedRes;
  ({DateTime from, DateTime to, bool archive})? _mergedParams;
  bool get _mergedOn => MergedMode.active.value;

  @override
  void initState() {
    super.initState();
    PermissionsService.changes.addListener(_onPermsChanged);
    MergedMode.active.addListener(_onMergedChanged);
    MergedMode.focus.addListener(_onMergedFocus);
    _loadIfAllowed();
  }

  @override
  void dispose() {
    PermissionsService.changes.removeListener(_onPermsChanged);
    MergedMode.active.removeListener(_onMergedChanged);
    MergedMode.focus.removeListener(_onMergedFocus);
    super.dispose();
  }

  void _onMergedChanged() {
    if (!mounted) return;
    setState(() {
      _mergedRes = null;
      _mergedParams = null;
      _data = null;
      // مدير الحركة/المستخدم والموظّف من قوائم الشركة المفتوحة — لا تنتقل بين الوضعين
      _filters = ReportFilters(actionTypes: _filters.actionTypes);
    });
    if (_requested) _load();
  }

  void _onMergedFocus() {
    if (mounted && _mergedOn && _requested) _load();
  }

  void _onPermsChanged() {
    if (mounted && !_requested) _loadIfAllowed();
  }

  void _loadIfAllowed() {
    if (!Perms.has(_perm)) return;
    _requested = true;
    _load();
  }

  Future<void> _load() async {
    if (_mergedOn) return _loadMerged();
    setState(() {
      _loading = true;
      _error = null;
    });
    // جالب scope مرّة واحدة ثم يُعاد استخدامه
    _scopeIds ??= await loadScopeUserIds();
    final r = await ReportsApi.finance(
      from: _range.from,
      to: _range.to,
      // scope الافتراضي فقط لو المستخدم ما اختار مدير حركة محدّد.
      userIds: _filters.actionManagerId == null ? _scopeIds : null,
      actionManagerId: _filters.actionManagerId,
      userManager: _filters.userManager,
      employeeId: _filters.employeeId,
      // 2000 حد أعلى مطمئن للـmerge بين backend KPIs والمُحسَبة client-side
      // عند تفعيل فلتر. مغلق على 2000 لتقليل حجم الاستجابة.
      recentLimit: 2000,
      includeArchived: _withArchive,
      // كلفة الباقات وصافي الربح بعدها (قرار ٢٠٢٦-١٠-١٨): لمالك الحساب وحده،
      // ولساسٍ بعيد أو ايرث لنك لا سوبرنت. الخادم لا يرسلها لغيرهما أصلاً؛
      // وهذا حاجزٌ ثانٍ لو أرسلها — فشاشة الموظّف وسوبرنت كما كانت حرفيّاً.
      withPackageCost: !Perms.isEmployee &&
          isCostBearingAdminId(
              (_scopeIds?.isNotEmpty ?? false) ? _scopeIds!.first : null),
    );
    if (!mounted || _mergedOn) return;
    setState(() {
      _loading = false;
      _data = r.data;
      _error = r.ok ? null : (r.error ?? 'common.load_failed'.tr());
      _visibleCount = kReportPageStep;
    });
  }

  /// «كل الشركات»: المجموع، أو الشركة المختارة وحدها — من المجموع المحفوظ للمدّة نفسها بلا طلب، وإلّا موجَّهاً إليها.
  Future<void> _loadMerged() async {
    final f = MergedMode.focused;
    final params = (from: _range.from, to: _range.to, archive: _withArchive);
    final kept = _mergedParams == params ? _mergedRes : null;
    if (f != null && kept?.partOf(f.key)?.report != null) {
      setState(() {
        _loading = false;
        _data = kept!.partOf(f.key)!.report;
        _error = null;
        _visibleCount = kReportPageStep;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    if (f != null) {
      final r = await MergedFinanceApi.one(f, from: _range.from, to: _range.to, includeArchived: _withArchive);
      if (!mounted || !_mergedOn || MergedMode.focused?.key != f.key) return;
      setState(() {
        _loading = false;
        _data = r.data;
        _error = r.ok ? null : (r.error ?? 'common.load_failed'.tr());
        _visibleCount = kReportPageStep;
      });
      return;
    }
    final res = await MergedFinanceApi.load(from: _range.from, to: _range.to, includeArchived: _withArchive);
    if (!mounted || !_mergedOn || MergedMode.focused != null) return;
    setState(() {
      _loading = false;
      _mergedRes = res;
      _mergedParams = params;
      _data = res.report;
      _error = res.report == null ? 'merged.finance_none'.tr(args: [res.excluded.join('، ')]) : null;
      _visibleCount = kReportPageStep;
    });
  }

  /// «كل الشركات» (الكلّ) — المجموع المعروض الآن (null: الشركة المختارة أو الوضع العاديّ).
  MergedFinanceResult? get _mergedAll => _mergedOn && MergedMode.focused == null ? _mergedRes : null;

  /// سطر الشريط: من خرج من المجموع ولماذا، أو ما ينقص تقرير الشركة المختارة.
  String? _mergedNote() {
    final f = MergedMode.focused;
    if (f != null) {
      final d = _data;
      final why = d == null ? null : MergedFinanceApi.gapReason(f, d);
      return why == null ? null : 'merged.finance_gap'.tr(args: [why]);
    }
    final m = _mergedRes;
    if (m == null) return null;
    final lines = <String>[
      if (m.excluded.isNotEmpty) 'merged.not_in_sum'.tr(args: [m.excluded.join('، ')]),
      if (m.logsPartial.isNotEmpty) 'merged.finance_logs_partial'.tr(args: [m.logsPartial.join('، ')]),
    ];
    return lines.isEmpty ? null : lines.join('\n');
  }

  /// فلتر النوع في «الكل»: أرقام كلّ شركةٍ من سطورها (وكلفتها من سطورها) ثمّ المجموع — لا سطور شركةٍ بكلفة أخرى.
  ({FinanceKPIs kpis, bool costUnavailable}) _mergedTypeKpis(MergedFinanceResult m, List<FinanceLog> filtered) {
    final parts = <FinanceKPIs>[];
    var unavailable = false;
    for (final p in m.included) {
      final key = p.company.key;
      final mine = [
        for (final l in filtered)
          if (m.logCompany[l] == key) l,
      ];
      final cost = PackageCostKpis.forFilteredLogs(
        period: p.report!.kpis.packageCost,
        allLogs: p.report!.recentLogs,
        filtered: mine,
      );
      unavailable = unavailable || cost.unavailable;
      parts.add(_kpisFromLogs(mine, packageCost: cost.cost));
    }
    return (kpis: MergedFinanceApi.sumKpis(parts), costUnavailable: unavailable);
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return ReportPermissionGate(
      permission: _perm,
      title: 'reports.financial'.tr(),
      child: Scaffold(
        backgroundColor: AppColors.bg,
        appBar: AppBar(
          backgroundColor: AppColors.surface,
          elevation: 0,
          scrolledUnderElevation: 0,
          title: Text(
            'reports.financial'.tr(),
            style:
                AppType.title(color: AppColors.textHi).copyWith(fontSize: 16),
          ),
          iconTheme: IconThemeData(color: AppColors.textHi),
        ),
        body: SafeArea(
          child: RefreshIndicator(
            onRefresh: _load,
            color: AppColors.brand,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, Sp.huge),
              children: [
                if (_mergedOn) ...[
                  MergedCompanyStrip(note: _mergedNote()),
                  const SizedBox(height: Sp.md),
                ],
                ArchiveBar(
                  archive: _data?.archive,
                  includeArchived: _withArchive,
                  onChanged: (v) {
                    setState(() => _withArchive = v);
                    _load();
                  },
                  padding: const EdgeInsetsDirectional.only(bottom: Sp.sm),
                ),
                DateRangeChipBar(
                  value: _range,
                  onChanged: (r) {
                    setState(() => _range = r);
                    _load();
                  },
                ),
                const SizedBox(height: Sp.sm),
                ReportFiltersPanel(
                  // «كل الشركات»: قوائم المدراء والموظّفين للشركة المفتوحة وحدها — تُخفى
                  key: ValueKey(_mergedOn),
                  value: _filters,
                  actionTypeOptions: kFinancialActionTypes,
                  includeActionManager: !_mergedOn,
                  includeUserManager: !_mergedOn,
                  includeEmployee: !_mergedOn,
                  onChanged: (v) {
                    setState(() {
                      _filters = v;
                      _visibleCount = kReportPageStep;
                    });
                    _load();
                  },
                ),
                const SizedBox(height: Sp.md),
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: Sp.huge),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_error != null)
                  _errorPanel()
                else if (_data != null) ...[
                  // KPIs: عند فلتر أنواع الحركات نحسبها من الـrecentLogs
                  // المفلترة (client-side)، وإلا نستعمل قيم backend للفترة كاملة.
                  Builder(builder: (_) {
                    final hasTypeFilter = _filters.actionTypes != null &&
                        _filters.actionTypes!.isNotEmpty;
                    final filtered = _filterLogs(_data!.recentLogs);
                    final all = _mergedAll;
                    // «كل الشركات»: تحت فلتر النوع كلّ شركةٍ من سطورها ثمّ المجموع
                    final mergedTyped = hasTypeFilter && all != null
                        ? _mergedTypeKpis(all, filtered)
                        : null;
                    // الكلفة تحت فلتر النوع من كلفة كلّ سطر — كبقيّة أرقامه.
                    final filterCost = hasTypeFilter && mergedTyped == null
                        ? PackageCostKpis.forFilteredLogs(
                            period: _data!.kpis.packageCost,
                            allLogs: _data!.recentLogs,
                            filtered: filtered,
                          )
                        : null;
                    final effectiveKpis = mergedTyped?.kpis ??
                        (hasTypeFilter
                            ? _kpisFromLogs(filtered,
                                packageCost: filterCost?.cost)
                            : _data!.kpis);
                    return Column(
                      children: [
                        _hero(effectiveKpis,
                            costNeedsAllTypes: mergedTyped?.costUnavailable ??
                                filterCost?.unavailable ??
                                false,
                            mergedRule: all?.mixedProfitRules ?? false),
                        const SizedBox(height: Sp.md),
                        _kpiGrid(effectiveKpis),
                        const SizedBox(height: Sp.lg),
                        if (all != null && all.parts.length > 1) ...[
                          _mergedBreakdown(all),
                          const SizedBox(height: Sp.lg),
                        ],
                      ],
                    );
                  }),
                  _recentLogs(_data!.recentLogs,
                      showCost: _data!.kpis.packageCost != null),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _errorPanel() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Sp.xl),
      child: Center(
        child: Column(
          children: [
            Icon(LucideIcons.triangleAlert, size: 32, color: AppColors.error),
            const SizedBox(height: 8),
            Text(_error!, style: AppType.subtitle(color: AppColors.textMid)),
            const SizedBox(height: Sp.md),
            ElevatedButton.icon(
              onPressed: _load,
              icon: const Icon(LucideIcons.refreshCw, size: 16),
              label: Text('common.retry'.tr()),
            ),
          ],
        ),
      ),
    );
  }

  /// هيرو — الإيراد الإجمالي + الصافي بعد المصاريف.
  /// تصميم موحّد مع بقية بطاقات KPI (surface + border خفيف)، والاعتماد
  /// على اللون فقط في القيم الرقمية والأيقونات (تعليق مستخدم 2026-07-10:
  /// الـgradient كان نشازاً).
  ///
  /// كلفة الباقات (٢٠٢٦-١٠-١٨) — حين يرسلها الخادم للمالك فقط: تحت صافي
  /// النقد (كما كان) قسمٌ ثانٍ: «كلفة الباقات» ثمّ «صافي الربح بعد كلفة
  /// الباقات» = المبيعات − المصاريف − الكلفة، وصيغته تحته. على أساس المبيعات
  /// لا النقد (انظر [FinanceKPIs.profitAfterCost]). بلاها (سوبرنت، الموظّف)
  /// الهيرو كما كان حرفيّاً.
  /// [costNeedsAllTypes]: فلتر النوع لا يستطيع حساب الكلفة من السطور (لا كلفة
  /// لكلّ سطر، أو السطور مقطوعة عند سقف الخادم)، فيُقال ذلك بدل رقمٍ كاذب.
  Widget _hero(FinanceKPIs k,
      {bool costNeedsAllTypes = false, bool mergedRule = false}) {
    final brand = AppColors.brand;
    final cost = k.packageCost;
    final profit = k.profitAfterCost;
    return Container(
      padding: const EdgeInsets.all(Sp.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.lg),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: brand.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(R.sm),
                ),
                child: Icon(LucideIcons.wallet, size: 14, color: brand),
              ),
              const SizedBox(width: 8),
              Text('reports.total_cash_revenue'.tr(),
                  style: AppType.muted()
                      .copyWith(fontSize: 11, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${formatIQD(k.totalCashRevenue)} ${'common.currency'.tr()}',
            style: AppType.title(color: brand).copyWith(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: Sp.sm),
          // خط فاصل خفيف يفصل الإيراد عن الصافي/المصاريف
          Container(height: 1, color: AppColors.border),
          const SizedBox(height: Sp.sm),
          // صف الخصومات: المصاريف + إضافة الدين اليدوي (كلاهما يُطرح
          // من الصافي).
          Row(
            children: [
              Expanded(
                child: _heroMini(
                  icon: LucideIcons.receipt,
                  label: 'reports.expenses'.tr(),
                  value: '-${formatIQD(k.expensesSum)}',
                  color: AppColors.error,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _heroMini(
                  icon: LucideIcons.plus,
                  label: 'actions.debt_add'.tr(),
                  value: '-${formatIQD(k.balanceAddSum)}',
                  color: AppColors.error,
                ),
              ),
            ],
          ),
          const SizedBox(height: Sp.sm),
          // صف الصافي — يعرض netCash بشكل بارز مع رمزه ولونه.
          _heroMini(
            icon: k.netCash < 0
                ? LucideIcons.trendingDown
                : LucideIcons.trendingUp,
            label: 'reports.kpi_net'.tr(),
            value: k.netCash < 0
                ? '-${formatIQD(k.netCash)}'
                : formatIQD(k.netCash),
            color: k.netCash < 0 ? AppColors.error : brand,
          ),
          if (cost != null && profit != null) ...[
            const SizedBox(height: Sp.sm),
            Container(height: 1, color: AppColors.border),
            const SizedBox(height: Sp.sm),
            // ما دفعه الوكيل للساس/ايرث لنك عن تفعيلات الفترة وتمديداتها.
            // صفرٌ معروف «0» لا «-0».
            _heroMini(
              icon: LucideIcons.package,
              label: 'reports.package_cost'.tr(),
              value: cost.sum > 0 ? '-${formatIQD(cost.sum)}' : formatIQD(0),
              color: AppColors.error,
            ),
            const SizedBox(height: Sp.sm),
            // صافي الربح بعد كلفة الباقات = المبيعات − المصاريف − الكلفة.
            _heroMini(
              icon: profit < 0
                  ? LucideIcons.trendingDown
                  : LucideIcons.trendingUp,
              label: 'reports.kpi_net_after_cost'.tr(),
              value: profit < 0 ? '-${formatIQD(profit)}' : formatIQD(profit),
              color: profit < 0 ? AppColors.error : brand,
            ),
            // «كل الشركات» بقاعدتين: الصيغة الواحدة لا تصحّ على المجموع — كلّ شركةٍ بقاعدتها
            if (mergedRule)
              _heroNote('merged.finance_profit_rule'.tr(), warn: false)
            else
              _heroNote(
                'reports.profit_after_cost_formula'.tr(namedArgs: {
                  'sales': formatIQD(k.salesSum),
                  'expenses': formatIQD(k.expensesSum),
                  'cost': formatIQD(cost.sum),
                }),
                warn: false,
              ),
            if (cost.missingRows > 0)
              _heroNote(
                'reports.package_cost_missing'.tr(namedArgs: {
                  'missing': '${cost.missingRows}',
                  'rows': '${cost.rows}',
                }),
              ),
            if (cost.hasEstimates)
              _heroNote(
                cost.estimatedRows > 0
                    ? 'reports.package_cost_estimated'
                        .tr(namedArgs: {'count': '${cost.estimatedRows}'})
                    : 'reports.package_cost_estimated_some'.tr(),
              ),
          ],
          if (cost == null && costNeedsAllTypes)
            _heroNote('reports.package_cost_needs_all_types'.tr()),
        ],
      ),
    );
  }

  /// سطرٌ صغير تحت الصافي — يلتفّ على سطرين عمداً، فلا maxLines. [warn]:
  /// تنبيهٌ (أيقونة معلومات بلون التنبيه) أو شرحٌ محايد (الصيغة).
  Widget _heroNote(String text, {bool warn = true}) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(top: Sp.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.only(top: 1),
            child: Icon(
              warn ? LucideIcons.info : LucideIcons.calculator,
              size: 13,
              color: warn ? AppColors.warning : AppColors.textMid,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: AppType.muted(color: AppColors.textMid)
                  .copyWith(fontSize: 10.5, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _heroMini({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    // بدون خلفية ملوّنة — نعتمد على اللون في الأيقونة + القيمة فقط،
    // بحيث تنسجم مع hero card الجديدة (خلفية surface).
    return Row(
      children: [
        Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(R.sm),
          ),
          child: Icon(icon, size: 13, color: color),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label,
                  style: AppType.muted()
                      .copyWith(fontSize: 10.5, fontWeight: FontWeight.w600)),
              Text(
                value,
                style: AppType.rowLabelBold(color: color),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// «كل الشركات»: سطرٌ لكلّ شركة — نقدها المستلم وصافيها، أو سبب خروجها من المجموع. الضغط يعرضها وحدها.
  Widget _mergedBreakdown(MergedFinanceResult m) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.lg),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(Sp.md, Sp.md, Sp.md, Sp.xs),
            child: Text('merged.finance_by_company'.tr(),
                style: AppType.label(color: AppColors.textHi)
                    .copyWith(fontSize: 13, fontWeight: FontWeight.w700)),
          ),
          for (final p in m.parts)
            InkWell(
              onTap: () => MergedMode.focus.value = p.company.key,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: 10),
                child: Row(
                  children: [
                    Expanded(child: CompanyTag(companyKey: p.company.key, fontSize: 12.5)),
                    const SizedBox(width: Sp.sm),
                    if (p.included) ...[
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '${formatIQD(p.report!.kpis.totalCashRevenue)} ${'common.currency'.tr()}',
                            style: AppType.rowLabelBold(color: AppColors.textHi),
                          ),
                          Text(
                            '${'reports.kpi_net'.tr()}: ${p.report!.kpis.netCash < 0 ? '-' : ''}${formatIQD(p.report!.kpis.netCash)}',
                            style: AppType.muted(color: p.report!.kpis.netCash < 0 ? AppColors.error : AppColors.textMid)
                                .copyWith(fontSize: 11),
                          ),
                        ],
                      ),
                    ] else
                      Flexible(
                        child: Text(
                          p.reason ?? 'common.load_failed'.tr(),
                          textAlign: TextAlign.end,
                          style: AppType.muted(color: AppColors.warning).copyWith(fontSize: 11.5),
                        ),
                      ),
                    const SizedBox(width: 4),
                    Icon(Icons.chevron_left_rounded, size: 18, color: AppColors.textLow),
                  ],
                ),
              ),
            ),
          const SizedBox(height: Sp.xs),
        ],
      ),
    );
  }

  Widget _kpiGrid(FinanceKPIs k) {
    // تسديد دين = payments + debt_pay + balance_deduct مجموعان — مطابق web
    // Financial.tsx. كان يفتقد paymentsSum ويظهر أقلّ من الويب.
    final debtPayTotal = k.totalDebtPayments;
    final items = <_KpiItem>[
      _KpiItem('actions.activate_cash'.tr(), formatIQD(k.activateCashSum),
          AppColors.success, LucideIcons.zap),
      _KpiItem('actions.debt_pay'.tr(), formatIQD(debtPayTotal),
          AppColors.success, LucideIcons.banknote),
      _KpiItem(
          'actions.activate_non_cash'.tr(),
          formatIQD(k.activateNonCashSum),
          AppColors.error,
          LucideIcons.creditCard,
          isDebit: true),
      _KpiItem('actions.debt_add'.tr(), formatIQD(k.balanceAddSum),
          AppColors.error, LucideIcons.plus,
          isDebit: true),
      _KpiItem('# تفعيلات', '${k.activationsCount}', AppColors.brandAccent,
          LucideIcons.userCheck,
          isCount: true),
      _KpiItem('# تمديدات', '${k.extendCount}', AppColors.success,
          LucideIcons.repeat,
          isCount: true),
      _KpiItem('# مصاريف', '${k.expensesCount}', AppColors.error,
          LucideIcons.receipt,
          isCount: true),
    ];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: items
          .map((it) => SizedBox(
                width: (MediaQuery.sizeOf(context).width - Sp.lg * 2 - 8) / 2,
                child: _kpiCard(it),
              ))
          .toList(),
    );
  }

  Widget _kpiCard(_KpiItem it) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.md),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: it.color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(R.sm),
            ),
            child: Icon(it.icon, color: it.color, size: 13),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  it.label,
                  style: AppType.muted().copyWith(fontSize: 9.5),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  it.isCount ? it.value : '${it.isDebit ? '-' : ''}${it.value}',
                  style: TextStyle(
                    // المبالغ: أحمر (سالب) لـdebit، أخضر (موجب) للباقي.
                    // العدّاد يبقى بلون النص العادي.
                    color: it.isCount
                        ? AppColors.textHi
                        : (it.isDebit ? AppColors.error : AppColors.success),
                    fontSize: 12.5, height: 1.4,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// virtual types: SUBSCRIBER_ACTIVATE_CASH / _NON_CASH يتفكّكان بحسب
  /// description (مطابق backend FinanceReportController).
  bool _matchesFinancialType(FinanceLog l, String type) {
    final at = l.actionType.toUpperCase().trim();
    final desc = (l.actionDescription ?? '');
    final isNonCash = desc.contains('غير نقدي');
    final isCash = desc.contains('نقدي') && !isNonCash;
    switch (type) {
      case 'SUBSCRIBER_ACTIVATE_CASH':
        return (at == 'SUBSCRIBER_ACTIVATE' ||
                (at == 'SUBSCRIBER_ADD' && desc.contains('تفعيل'))) &&
            isCash;
      case 'SUBSCRIBER_ACTIVATE_NON_CASH':
        return (at == 'SUBSCRIBER_ACTIVATE' ||
                (at == 'SUBSCRIBER_ADD' && desc.contains('تفعيل'))) &&
            isNonCash;
      case 'ADMIN_EXPENSE':
        return at == 'ADMIN_EXPENSE' || at == 'EXPENSE_ADD';
      default:
        return at == type;
    }
  }

  // مطلب المستخدم 2026-07-12: إشعارات الانتهاء الآلية ما تخص التقرير
  // المالي — نستثنيها قبل أي فلترة إضافية.
  static const _excludedTypes = {
    'EXPIRY_NOTIFICATION',
    'NEAR_EXPIRY_NOTIFICATION',
    'AUTO_NOTIFICATION',
  };

  List<FinanceLog> _filterLogs(List<FinanceLog> logs) {
    final base = logs.where(
        (l) => !_excludedTypes.contains(l.actionType.toUpperCase().trim()));
    final types = _filters.actionTypes;
    if (types == null || types.isEmpty) return base.toList();
    return base
        .where((l) => types.any((t) => _matchesFinancialType(l, t)))
        .toList();
  }

  /// نحسب KPIs من قائمة FinanceLog — يُستدعى عند تفعيل فلتر لعرض
  /// قيم مطابقة للفلتر بدلاً من فترة كاملة. عند "الكل" نستعمل قيم
  /// backend مباشرةً (أدقّ لأنها من الاستعلام الكامل بلا حد).
  /// [packageCost] كلفة السطور نفسها ([PackageCostKpis.forFilteredLogs]).
  FinanceKPIs _kpisFromLogs(
    List<FinanceLog> logs, {
    PackageCostKpis? packageCost,
  }) {
    num activateCash = 0,
        activateNonCash = 0,
        partialUnpaid = 0,
        debtPay = 0,
        balanceDeduct = 0,
        balanceAdd = 0,
        expenses = 0;
    int activationsCount = 0, extendCount = 0, expensesCount = 0;
    for (final l in logs) {
      final at = l.actionType.toUpperCase().trim();
      final desc = l.actionDescription ?? '';
      final isNonCash = desc.contains('غير نقدي');
      final isCash = desc.contains('نقدي') && !isNonCash;
      if (at == 'SUBSCRIBER_ACTIVATE' ||
          (at == 'SUBSCRIBER_ADD' && desc.contains('تفعيل'))) {
        activationsCount++;
        if (isNonCash) {
          activateNonCash += l.amount;
        } else if (isCash) {
          activateCash += l.amount;
          // غير المدفوع من «نقدي جزئي» — يدخل المبيعات (صافي الربح بعد الكلفة)
          // كما يضمّه الخادم إلى «الديون الجديدة».
          partialUnpaid += l.partialUnpaid;
        }
      } else if (at == 'SUBSCRIBER_EXTEND') {
        extendCount++;
      } else if (at == 'DEBT_PAY') {
        debtPay += l.amount;
      } else if (at == 'BALANCE_DEDUCT') {
        balanceDeduct += l.amount;
      } else if (at == 'BALANCE_ADD') {
        balanceAdd += l.amount;
      } else if (at == 'EXPENSE_ADD' || at == 'ADMIN_EXPENSE') {
        expenses += l.amount;
        expensesCount++;
      }
    }
    return FinanceKPIs(
      activateCashSum: activateCash,
      activateNonCashSum: activateNonCash,
      debtPaySum: debtPay,
      balanceDeductSum: balanceDeduct,
      balanceAddSum: balanceAdd,
      expensesSum: expenses,
      expensesCount: expensesCount,
      activationsCount: activationsCount,
      extendCount: extendCount,
      packageCost: packageCost,
      partialUnpaidFromLogs: partialUnpaid,
    );
  }

  /// [showCost]: الخادم أرسل كلفة الباقات للمالك — سطر الكلفة تحت كلّ عمليّة
  /// بيع وعمودٌ في التصدير. بلاها القائمة والملفّ كما كانا.
  Widget _recentLogs(List<FinanceLog> logs, {bool showCost = false}) {
    if (logs.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: Sp.xl),
        child: Center(
          child: Column(
            children: [
              Icon(LucideIcons.fileText, size: 32, color: AppColors.textLow),
              const SizedBox(height: 8),
              Text('reports.no_financial_movements'.tr(),
                  style: AppType.muted().copyWith(fontSize: 12.5)),
            ],
          ),
        ),
      );
    }
    final filtered = _filterLogs(logs);
    final shown = _visibleCount.clamp(0, filtered.length);
    final remaining = filtered.length - shown;
    final pageRows = filtered.isEmpty
        ? const <FinanceLog>[]
        : filtered.take(_visibleCount).toList();
    // ترتيب أعمدة Excel/PDF المطلوب (2026-07-12): اسم المشترك (بارز
    // بالعربي) → المبلغ → التاريخ → الوصف → البقية. الاسم العربي أولاً
    // ويجمع firstname+lastname؛ نضيف عمود username منفصل لتسهيل الفرز
    // والبحث في الشيت. النوع يُترجَم لعربي (arabicActionLabel) بدل
    // SUBSCRIBER_ACTIVATE الإنجليزي.
    final all = _mergedAll;
    String coName(FinanceLog l) =>
        MergedMode.companyOf(all?.logCompany[l])?.name ?? '';
    final exportRows = filtered
        .map((l) => [
              if (all != null) coName(l),
              l.userFullName ?? l.targetName ?? l.userUsername ?? '',
              l.userUsername ?? '',
              l.amount == 0 ? '' : l.amount.toString(),
              if (showCost)
                l.packageCost == null ? '' : _plainNumber(l.packageCost!),
              l.createdAt,
              (l.actionDescription ?? '').replaceAll('\n', ' '),
              arabicActionLabel(l.actionType, l.actionDescription ?? ''),
              l.actingEmployeeFullName ?? l.adminUsername ?? '',
            ])
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6, right: 4),
          child: Row(
            children: [
              Icon(LucideIcons.history, size: 14, color: AppColors.textMid),
              const SizedBox(width: 6),
              Text('آخر الحركات',
                  style: AppType.label(color: AppColors.textHi)
                      .copyWith(fontSize: 13, fontWeight: FontWeight.w700)),
              const Spacer(),
              Text('${filtered.length}',
                  style: AppType.muted().copyWith(fontSize: 11)),
            ],
          ),
        ),
        const SizedBox(height: Sp.sm),
        Row(
          children: [
            Expanded(
              child: ReportStatsBar(
                totalItems: filtered.length,
                shown: shown,
              ),
            ),
            ReportExportBar(
              title: 'reports.financial'.tr(),
              subtitle: '${_dateStr(_range.from)} → ${_dateStr(_range.to)}',
              fileNameBase: 'financial',
              columns: [
                if (all != null) 'merged.col_company'.tr(),
                'reports.col_subscriber'.tr(),
                'reports.col_username'.tr(),
                'reports.col_amount'.tr(),
                if (showCost) 'reports.col_package_cost'.tr(),
                'reports.col_date'.tr(),
                'reports.col_description'.tr(),
                'reports.col_type'.tr(),
                'reports.col_executor'.tr(),
              ],
              // مطلب 2026-07-12: الاسم/الوصف يأخذون مساحة أوسع، النوع
              // والمنفّذ أضيق (خصوصاً بعد الترجمة العربية).
              columnWeights: [
                if (all != null) 1.4,
                ...(showCost
                    ? const [2.2, 1.4, 1.2, 1.2, 1.4, 2.6, 1.1, 1.3]
                    : const [2.2, 1.4, 1.2, 1.4, 2.6, 1.1, 1.3]),
              ],
              rows: exportRows,
            ),
          ],
        ),
        const SizedBox(height: Sp.sm),
        for (final l in pageRows) ...[
          if (all != null && all.logCompany[l] != null)
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 4, bottom: 2),
              child: CompanyTag(companyKey: all.logCompany[l]!, fontSize: 11),
            ),
          ReportLogTile(
            actionType: l.actionType,
            description: l.actionDescription ?? '',
            amount: l.amount,
            adminUsername: l.adminUsername,
            employeeFullName: l.actingEmployeeFullName,
            employeeUsername: l.actingEmployeeUsername,
            subscriberFullName: l.userFullName,
            subscriberUsername: l.userUsername,
            targetName: l.targetName ?? l.userUsername,
            createdAt: l.createdAt,
balanceAfter: l.balanceAfter,
            costLine: showCost ? _costLine(l) : null,
            costLineWarn: showCost && l.packageCostUnknown,
          ),
          const SizedBox(height: 4),
        ],
        if (remaining > 0)
          ReportLoadMore(
            remaining: remaining,
            onTap: () => setState(() => _visibleCount += kReportPageStep),
          ),
      ],
    );
  }

  static String _dateStr(DateTime? d) {
    if (d == null) return '';
    String p(int v) => v.toString().padLeft(2, '0');
    return '${d.year}-${p(d.month)}-${p(d.day)}';
  }

  /// سطر كلفة الباقة تحت الحركة — `null` لما لا كلفة له (تسديد، صرفية،
  /// المُزامَن من الساس، أو سطرٌ لم يرسل الخادم كلفته).
  static String? _costLine(FinanceLog l) {
    final c = l.packageCost;
    if (c != null) {
      final line = 'reports.log_package_cost'
          .tr(namedArgs: {'amount': formatIQD(c)});
      return l.packageCostEstimated
          ? '$line · ${'reports.package_cost_estimated_tag'.tr()}'
          : line;
    }
    if (l.packageCostUnknown) return 'reports.log_package_cost_unknown'.tr();
    return null;
  }

  /// رقمٌ للتصدير بلا «.0» الزائدة (DECIMAL يصل من الخادم نصّاً كـ"20000.00").
  static String _plainNumber(num v) =>
      v == v.roundToDouble() ? v.round().toString() : v.toString();
}

class _KpiItem {
  const _KpiItem(this.label, this.value, this.color, this.icon,
      {this.isDebit = false, this.isCount = false});
  final String label;
  final String value;
  final Color color;
  final IconData icon;
  final bool isDebit;
  final bool isCount;
}
