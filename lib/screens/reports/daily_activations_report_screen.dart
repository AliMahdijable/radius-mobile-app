import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../api/reports_api.dart';
import '../../core/util/format.dart';
import '../../models/merged_company.dart';
import '../../services/merged_mode.dart';
import '../../services/merged_report_loader.dart';
import '../../widgets/merged_company_strip.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import 'widgets/date_range_chip.dart';
import 'widgets/report_export.dart';
import 'widgets/report_filters.dart';
import 'widgets/report_pagination.dart';
import 'widgets/report_permission_gate.dart';
import 'widgets/scope_helper.dart';
import '../desktop/desk_widgets.dart';
import '../../services/merged_text.dart';

/// التفعيلات اليومية — مُجمّعة بـday + إيراد لكل يوم + عدد نقدي/غير.
class DailyActivationsReportScreen extends StatefulWidget {
  const DailyActivationsReportScreen({super.key});

  @override
  State<DailyActivationsReportScreen> createState() =>
      _DailyActivationsReportScreenState();
}

class _DailyActivationsReportScreenState
    extends State<DailyActivationsReportScreen> {
  // 2026-07-10: الصفحة "التفعيلات اليومية" مخصّصة لليوم الحالي فقط
  // (feed مباشر). لا نعرض شريط تحديد الفترة — الافتراضي اليوم دائماً.
  final DateRange _range = DateRange.today();
  List<DailyActivationRow> _rows = const [];
  bool _loading = true;
  String? _error;
  List<String>? _scopeIds;
  int _visibleCount = kReportPageStep;

  /// فلاتر متقدّمة (مدير الحركة/المستخدم/الموظف) — بلا actionTypes لأن
  /// الشاشة scope=تفعيلات-اليوم أصلاً.
  ReportFilters _filters = const ReportFilters();

  /// فلتر: all / cash_only (يوم بأي نقدي) / non_cash_only / no_revenue
  String _typeFilter = 'all';

  // ── «كل الشركات» (٧ نوفمبر — المالك: «التقارير… بنفس فكرة عرض المشتركين والاختيار بين الكل وشركة»): الشاشة نفسها وشريط
  // الشركات أعلاها. تفعيلات كلّ شركةٍ بطلبٍ موجَّه لها بنطاقها (معرّف مديرها — كما تراها وحدها)؛ «الكل» سطرٌ لكلّ شركة (الضغط
  // يعرضها وحدها بأيّامها)، والمجموع: العدد من كلّ شركةٍ قُرئت، والنقد بالدينار وحده — شركةٌ بعملةٍ أخرى أو مجهولة تُسمّى ولا
  // يُجمع نقدها، والمتعذّرة تُسمّى ولا تُعدّ صفراً. فلاتر المدير والموظّف لقوائم الشركة المفتوحة فتُخفى هنا.
  bool get _mergedOn => MergedMode.active.value;
  MergedReport<DailyActivationRow>? _merged;
  int _gen = 0;

  /// صفوف الشاشة قبل فلتر النوع: «الكل» سطرٌ لكلّ شركة (مجموع أيّامها)، والمختارة أيّامها، وخارج الوضع كما كان.
  List<({String? key, DailyActivationRow row})> get _base {
    final m = _mergedOn ? _merged : null;
    if (m == null) return [for (final r in _rows) (key: null, row: r)];
    final f = MergedMode.focused;
    if (f != null) return [for (final e in m.rowsFor(f.key)) (key: e.key as String?, row: e.row)];
    return [
      for (final p in m.parts)
        if (p.ok) (key: p.company.key as String?, row: _sumRows(p.rows!)),
    ];
  }

  static DailyActivationRow _sumRows(List<DailyActivationRow> rows) => DailyActivationRow(
        day: '',
        count: rows.fold(0, (s, r) => s + r.count),
        cashSum: rows.fold<num>(0, (s, r) => s + r.cashSum),
        nonCashCount: rows.fold(0, (s, r) => s + r.nonCashCount),
      );

  /// نقد الصفّ يدخل المجموع؟ خارج الوضع دائماً؛ فيه للدينار وحده.
  bool _cashCounts(String? key) {
    if (key == null) return true;
    return MergedMode.companyOf(key)?.currency == 'IQD';
  }

  void _onMergedMode() {
    if (!mounted) return;
    _merged = null;
    _filters = const ReportFilters();
    _load();
  }

  void _onMergedFocus() {
    if (mounted && _mergedOn) {
      setState(() {
        _typeFilter = 'all';
        _visibleCount = kReportPageStep;
      });
    }
  }

  /// سطر الشريط: من لم يُقرأ ولماذا، وشركاتٌ بعملةٍ أخرى نقدها خارج المجموع.
  String? _mergedNote(MergedReport<DailyActivationRow> m) {
    final focus = MergedMode.focused;
    final lines = <String>[
      if (m.noteFor(focus?.key,
              unsupportedText: 'لا تفعيلاتٍ تُقرأ لنوعها من هنا',
              missingText: 'merged.missing'.trm(args: [m.missing.map((c) => c.name).join('، ')]))
          case final n?)
        n,
      if (focus == null)
        for (final p in m.parts)
          if (p.ok && p.company.currency != 'IQD')
            'merged.not_in_sum'.trm(args: ['نقد «${p.company.name}» (${p.company.currency ?? 'عملةٌ غير معروفة'})']),
    ];
    return lines.isEmpty ? null : lines.join('\n');
  }

  List<({String? key, DailyActivationRow row})> get _visibleRows {
    final base = _base;
    if (_typeFilter == 'all') return base;
    return base.where((e) {
      final r = e.row;
      switch (_typeFilter) {
        case 'cash_only':
          return r.count > 0;
        case 'non_cash_only':
          return r.nonCashCount > 0;
        case 'no_revenue':
          return r.count == 0;
        default:
          return true;
      }
    }).toList();
  }

  @override
  void initState() {
    super.initState();
    MergedMode.active.addListener(_onMergedMode);
    MergedMode.focus.addListener(_onMergedFocus);
    _load();
  }

  @override
  void dispose() {
    _gen++;
    MergedMode.active.removeListener(_onMergedMode);
    MergedMode.focus.removeListener(_onMergedFocus);
    super.dispose();
  }

  Future<void> _load() async {
    final gen = ++_gen;
    setState(() {
      _loading = true;
      _error = null;
    });
    if (_mergedOn) {
      // كلّ شركةٍ بنطاقها هي (معرّف مديرها) — نطاق المفتوحة لا يُرسل لغيرها
      final m = await loadMergedReport<DailyActivationRow>(
        supports: (c) => c.provider != MergedProvider.ftth && c.provider != MergedProvider.fiberx,
        fetch: (c) async {
          final r = await ReportsApi.dailyActivations(from: _range.from, to: _range.to, userIds: [c.adminId]);
          return (ok: r.ok, rows: r.rows, error: r.error, note: null);
        },
      );
      if (!mounted || gen != _gen || !_mergedOn) return;
      setState(() {
        _loading = false;
        _merged = m;
        _rows = const [];
        _error = m.parts.any((p) => p.ok) ? null : 'common.load_failed'.tr();
        _visibleCount = kReportPageStep;
      });
      return;
    }
    _scopeIds ??= await loadScopeUserIds();
    final r = await ReportsApi.dailyActivations(
      from: _range.from,
      to: _range.to,
      userIds: _filters.actionManagerId == null ? _scopeIds : null,
      actionManagerId: _filters.actionManagerId,
      userManager: _filters.userManager,
      employeeId: _filters.employeeId,
    );
    if (!mounted || gen != _gen || _mergedOn) return;
    setState(() {
      _merged = null;
      _loading = false;
      _rows = r.rows;
      _error = r.ok ? null : (r.error ?? 'common.load_failed'.tr());
      _visibleCount = kReportPageStep;
    });
  }

  List<List<String>> get _exportRows => _visibleRows
      .map((e) => [
            if (_mergedOn) MergedMode.companyOf(e.key)?.name ?? '',
            e.row.day.isEmpty ? _dateStr(_range.from) : e.row.day,
            '${e.row.count}',
            '${e.row.nonCashCount}',
            e.row.cashSum.toString(),
          ])
      .toList();

  int get _totalActivations =>
      _visibleRows.fold(0, (s, e) => s + e.row.count + e.row.nonCashCount);
  // «كل الشركات»: نقد الدينار وحده يُجمع (غيره مسمّى في سطر الشريط)
  num get _totalRevenue =>
      _visibleRows.fold<num>(0, (s, e) => s + (_cashCounts(e.key) ? e.row.cashSum : 0));

  int get _totalCount => _totalActivations;
  num get _totalCash => _totalRevenue;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep
    final visible = _visibleRows;
    final shown = _visibleCount.clamp(0, visible.length);
    final remaining = visible.length - shown;
    final pageRows = visible.isEmpty
        ? const <({String? key, DailyActivationRow row})>[]
        : visible.take(_visibleCount).toList();
    final merged = _mergedOn ? _merged : null;
    return ReportPermissionGate(
      permission: 'reports.daily_activations',
      title: 'reports.daily_activations'.tr(),
      child: Scaffold(
        backgroundColor: AppColors.bg,
        appBar: deskPageBar(
          context,
          mobile: AppBar(
            backgroundColor: AppColors.surface,
            elevation: 0,
            scrolledUnderElevation: 0,
            title: Text(
              'reports.daily_activations'.tr(),
              style:
                  AppType.title(color: AppColors.textHi).copyWith(fontSize: 16),
            ),
            iconTheme: IconThemeData(color: AppColors.textHi),
          ),
        ),
        body: SafeArea(
          child: RefreshIndicator(
            onRefresh: _load,
            color: AppColors.brand,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, Sp.huge),
              children: [
                // «كل الشركات»: الشركات بعدد تفعيلات اليوم لكلٍّ منها، ومن لم يُقرأ ولماذا
                if (merged != null) ...[
                  MergedCompanyStrip(
                    countOf: (c) => merged.partOf(c.key)?.rows?.fold<int>(0, (s, r) => s + r.count + r.nonCashCount),
                    total: [for (final p in merged.parts) ...?p.rows].fold<int>(0, (s, r) => s + r.count + r.nonCashCount),
                    problemOf: (c) => merged.problemOf(c,
                        failedLabel: 'merged.chip_failed'.trm(), unsupportedLabel: 'merged.web_only'.trm()),
                    note: _mergedNote(merged),
                  ),
                  const SizedBox(height: Sp.md),
                ],
                // شريط "اليوم" ثابت — تنبيه بصري بأن الصفحة scope=today.
                _todayBadge(),
                const SizedBox(height: Sp.sm),
                // «كل الشركات»: قوائم المدراء والموظّفين للشركة المفتوحة وحدها — تُخفى
                if (!_mergedOn)
                ReportFiltersPanel(
                  value: _filters,
                  // بلا actionTypes — الشاشة scope=تفعيلات-اليوم-أصلاً.
                  includeActionTypes: false,
                  onChanged: (v) {
                    setState(() {
                      _filters = v;
                      _visibleCount = kReportPageStep;
                    });
                    _load();
                  },
                ),
                const SizedBox(height: Sp.md),
                _summary(),
                const SizedBox(height: Sp.md),
                // «كل الشركات» (الكلّ): السطور شركاتٌ لا أيّام — شرائح الأيّام للشركة المختارة
                if (!(_mergedOn && MergedMode.focused == null)) ...[
                  _typeChips(),
                  const SizedBox(height: Sp.sm),
                ],
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: Sp.huge),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_error != null)
                  _errorBlock()
                else if (_base.isEmpty)
                  _emptyBlock()
                else ...[
                  Row(
                    children: [
                      Expanded(
                        child: ReportStatsBar(
                          totalItems: visible.length,
                          shown: shown,
                        ),
                      ),
                      ReportExportBar(
                        title: 'reports.daily_activations'.tr(),
                        subtitle:
                            '${_dateStr(_range.from)} → ${_dateStr(_range.to)}',
                        fileNameBase: 'daily_activations',
                        columns: [
                          if (_mergedOn) 'merged.col_company'.trm(),
                          'reports.col_day'.tr(),
                          'sheets.pay_cash'.tr(),
                          'actions.activate_non_cash'.tr(),
                          'dashboard.revenue'.tr(),
                        ],
                        rows: _exportRows,
                      ),
                    ],
                  ),
                  const SizedBox(height: Sp.sm),
                  // «الكل»: سطرٌ لكلّ شركة (الضغط يعرضها وحدها)؛ وإلّا الأيّام
                  if (_mergedOn && MergedMode.focused == null)
                    for (final e in pageRows) ...[
                      _companyRow(e.key!, e.row),
                      const SizedBox(height: 6),
                    ]
                  else
                    for (final e in pageRows) ...[
                      _dayRow(e.row),
                      const SizedBox(height: 6),
                    ],
                  if (remaining > 0)
                    ReportLoadMore(
                      remaining: remaining,
                      onTap: () =>
                          setState(() => _visibleCount += kReportPageStep),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _summary() {
    return Container(
      padding: const EdgeInsets.all(Sp.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.md),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: _kpi(
              icon: LucideIcons.zap,
              label: 'reports.total_activations'.tr(),
              value: '$_totalCount',
              color: AppColors.success,
            ),
          ),
          Container(width: 1, height: 32, color: AppColors.border),
          Expanded(
            child: _kpi(
              icon: LucideIcons.banknote,
              label: 'إجمالي النقدي',
              value: formatIQD(_totalCash),
              color: AppColors.brand,
            ),
          ),
        ],
      ),
    );
  }

  Widget _kpi({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Column(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(height: 4),
        Text(value,
            style: AppType.cardTitleBold(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis),
        Text(label,
            style: AppType.muted().copyWith(fontSize: 10.5), maxLines: 1),
      ],
    );
  }

  Widget _dayRow(DailyActivationRow r) {
    return Container(
      padding: const EdgeInsets.all(Sp.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.md),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.brandSoftBg,
              borderRadius: BorderRadius.circular(R.sm),
            ),
            child: Text(
              r.day,
              style: AppType.bodyBold(color: AppColors.brand),
            ),
          ),
          const SizedBox(width: Sp.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(LucideIcons.zap, size: 12, color: AppColors.success),
                    const SizedBox(width: 4),
                    Text('${r.count} نقدي',
                        style: AppType.label(color: AppColors.textHi).copyWith(
                            fontSize: 11, fontWeight: FontWeight.w700)),
                    const SizedBox(width: 10),
                    Icon(LucideIcons.creditCard,
                        size: 12, color: AppColors.warning),
                    const SizedBox(width: 4),
                    Text('${r.nonCashCount} غير نقدي',
                        style: AppType.label(color: AppColors.textHi).copyWith(
                            fontSize: 11, fontWeight: FontWeight.w700)),
                  ],
                ),
                const SizedBox(height: 2),
                Text('إيراد: ${formatIQD(r.cashSum)} د.ع',
                    style: AppType.muted()
                        .copyWith(fontSize: 11, color: AppColors.brand)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// «كل الشركات» (الكلّ): سطر شركةٍ بمجموع يومها — بتصميم سطر اليوم، واسمها مكان التاريخ؛ الضغط يعرضها وحدها.
  Widget _companyRow(String key, DailyActivationRow r) {
    final c = MergedMode.companyOf(key);
    final color = c == null ? AppColors.brand : AppColors.company(c.colorIndex);
    final cash = _cashCounts(key);
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(R.md),
      child: InkWell(
        key: ValueKey('daily-company-$key'),
        borderRadius: BorderRadius.circular(R.md),
        onTap: () => MergedMode.focus.value = key,
        child: Container(
          padding: const EdgeInsets.all(Sp.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(R.md),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Container(
                constraints: const BoxConstraints(maxWidth: 130),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(R.sm),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(c?.name ?? '—',
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.bodyBold(color: AppColors.textHi)),
                  ),
                ]),
              ),
              const SizedBox(width: Sp.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(LucideIcons.zap, size: 12, color: AppColors.success),
                        const SizedBox(width: 4),
                        Text('${r.count} نقدي',
                            style: AppType.label(color: AppColors.textHi).copyWith(fontSize: 11, fontWeight: FontWeight.w700)),
                        const SizedBox(width: 10),
                        Icon(LucideIcons.creditCard, size: 12, color: AppColors.warning),
                        const SizedBox(width: 4),
                        Text('${r.nonCashCount} غير نقدي',
                            style: AppType.label(color: AppColors.textHi).copyWith(fontSize: 11, fontWeight: FontWeight.w700)),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                        cash
                            ? 'إيراد: ${formatIQD(r.cashSum)} د.ع'
                            : 'إيراد: ${formatIQD(r.cashSum)} ${c?.currency ?? ''} — خارج المجموع',
                        style: AppType.muted().copyWith(fontSize: 11, color: AppColors.brand)),
                  ],
                ),
              ),
              Icon(LucideIcons.chevronLeft, size: 16, color: AppColors.textLow),
            ],
          ),
        ),
      ),
    );
  }

  static String _dateStr(DateTime? d) {
    if (d == null) return '';
    String p(int v) => v.toString().padLeft(2, '0');
    return '${d.year}-${p(d.month)}-${p(d.day)}';
  }

  Widget _todayBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.sm),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(LucideIcons.calendarCheck, size: 14, color: AppColors.brand),
          const SizedBox(width: 6),
          Text('اليوم — ${_fmtToday()}',
              style: AppType.label(color: AppColors.textHi)
                  .copyWith(fontSize: 12.5, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  String _fmtToday() {
    final n = _range.from;
    String p(int v) => v.toString().padLeft(2, '0');
    return '${n.year}-${p(n.month)}-${p(n.day)}';
  }

  Widget _typeChips() {
    // كل chip: (key, label, count, color)
    final rows = [for (final e in _base) e.row];
    final all = rows.length;
    final cashOnly = rows.where((r) => r.count > 0).length;
    final nonCashOnly = rows.where((r) => r.nonCashCount > 0).length;
    final noRev = rows.where((r) => r.count == 0).length;
    final chips = [
      ('all', 'الكل', all, AppColors.success),
      ('cash_only', 'أيام نقدي', cashOnly, AppColors.success),
      ('non_cash_only', 'أيام غير نقدي', nonCashOnly, AppColors.error),
      ('no_revenue', 'بلا إيراد', noRev, AppColors.textLow),
    ];
    return SizedBox(
      height: 30,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: chips.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (_, i) {
          final c = chips[i];
          final selected = _typeFilter == c.$1;
          return InkWell(
            borderRadius: BorderRadius.circular(R.sm),
            onTap: () => setState(() {
              _typeFilter = c.$1;
              _visibleCount = kReportPageStep;
            }),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color:
                    selected ? c.$4.withValues(alpha: 0.18) : AppColors.surface,
                borderRadius: BorderRadius.circular(R.sm),
                border: Border.all(
                  color: selected
                      ? c.$4.withValues(alpha: 0.55)
                      : AppColors.border,
                ),
              ),
              alignment: Alignment.center,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    c.$2,
                    style: AppType.pillBold(
                        color: selected ? c.$4 : AppColors.textMid),
                  ),
                  const SizedBox(width: 5),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: (selected ? c.$4 : AppColors.textLow)
                          .withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(R.pill),
                    ),
                    child: Text(
                      '${c.$3}',
                      style: AppType.microBold(
                          color: selected ? c.$4 : AppColors.textMid),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _emptyBlock() => Padding(
        padding: const EdgeInsets.symmetric(vertical: Sp.huge),
        child: Center(
          child: Column(
            children: [
              Icon(LucideIcons.calendar, size: 36, color: AppColors.textLow),
              const SizedBox(height: 10),
              Text('لا توجد تفعيلات في هذه الفترة',
                  style: AppType.label(color: AppColors.textMid)),
            ],
          ),
        ),
      );

  Widget _errorBlock() => Padding(
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
                label: const Text('إعادة المحاولة'),
              ),
            ],
          ),
        ),
      );
}
