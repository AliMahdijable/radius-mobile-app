import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/util/server_time.dart';
import '../../api/reports_api.dart';
import '../../core/util/format.dart';
import '../../models/merged_company.dart';
import '../../services/merged_mode.dart';
import '../../services/merged_report_loader.dart';
import '../../widgets/company_tag.dart';
import '../../widgets/merged_breakdown.dart';
import '../../widgets/merged_company_strip.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import 'widgets/date_range_chip.dart';
import 'widgets/report_export.dart';
import 'widgets/report_filters.dart';
import 'widgets/report_log_tile.dart';
import 'widgets/report_pagination.dart';
import 'widgets/report_permission_gate.dart';
import 'widgets/scope_helper.dart';
import '../desktop/desk_widgets.dart';
import '../../services/merged_text.dart';

/// التفعيلات — تفعيلات + تمديدات في الفترة، ضمن scope المدير الحالي.
/// نجلب الكل من backend ونفلتر client-side (مطابق web Activations.tsx).
class ActivationsReportScreen extends StatefulWidget {
  const ActivationsReportScreen({super.key});

  @override
  State<ActivationsReportScreen> createState() =>
      _ActivationsReportScreenState();
}

class _ActivationsReportScreenState extends State<ActivationsReportScreen> {
  DateRange _range = DateRange.thisMonth();
  List<ActivityRow> _rows = const []; // بعد فلتر التفعيل/التمديد
  bool _loading = true;
  String? _error;
  List<String>? _scopeIds;
  int _visibleCount = kReportPageStep;

  /// فلاتر متقدّمة (مدير الحركة / مدير المستخدم / الموظف).
  ReportFilters _filters = const ReportFilters();

  // ── «كل الشركات» (٧ نوفمبر — المالك: «التقارير… بنفس فكرة عرض المشتركين والاختيار بين الكل وشركة»): الشاشة نفسها وشريط
  // الشركات أعلاها، و«حسب الشركة» (عددها وإيرادها — الضغط يعرضها وحدها)، والحركات معاً الأحدث أوّلاً بشارة شركتها. حركات كلّ شركةٍ
  // بطلبٍ موجَّه بنطاقها هي (معرّف مديرها)؛ الإيراد بالدينار وحده (غيره مسمّى)، والمتعذّرة تُسمّى لا صفراً، وشركةٌ بلغت سقف
  // الحركات تُسمّى «قد تنقص». فلاتر المدير والموظّف لقوائم المفتوحة فتُخفى، ونوع الحركة يبقى.
  bool get _mergedOn => MergedMode.active.value;
  MergedReport<ActivityRow>? _merged;
  int _gen = 0;
  static const _rowCap = 5000;

  static bool _isActivation(ActivityRow row) {
    final at = (row.actionType).toUpperCase().trim();
    final desc = (row.actionDescription ?? '').toLowerCase();
    return at == 'SUBSCRIBER_ACTIVATE' || at == 'SUBSCRIBER_EXTEND' || (at == 'SUBSCRIBER_ADD' && desc.contains('تفعيل'));
  }

  static bool _isCash(ActivityRow r) =>
      (r.actionDescription ?? '').contains('نقدي') && !(r.actionDescription ?? '').contains('غير نقدي');

  /// نقد الصفّ يدخل المجموع؟ خارج الوضع دائماً؛ فيه للدينار وحده.
  bool _cashCounts(String? key) => key == null || MergedMode.companyOf(key)?.currency == 'IQD';

  /// الصفوف قبل فلتر النوع — كلٌّ بمفتاح شركته في الوضع (الأحدث أوّلاً بين الشركات).
  List<({String? key, ActivityRow row})> get _base {
    final m = _mergedOn ? _merged : null;
    if (m == null) return [for (final r in _rows) (key: null, row: r)];
    final rows = [for (final e in m.rowsFor(MergedMode.focused?.key)) (key: e.key as String?, row: e.row)];
    rows.sort((a, b) => b.row.createdAt.compareTo(a.row.createdAt));
    return rows;
  }

  // فلتر النوع القديم استُبدل بـReportFiltersPanel multi-select.
  // _visibleRows يفلتر بحسب _filters.actionTypes.
  List<({String? key, ActivityRow row})> get _visibleRows {
    final base = _base;
    final types = _filters.actionTypes;
    if (types == null || types.isEmpty) return base;
    final wanted = types.toSet();
    return base.where((e) => wanted.contains(e.row.actionType.toUpperCase().trim())).toList();
  }

  void _onMergedMode() {
    if (!mounted) return;
    _merged = null;
    _filters = ReportFilters(actionTypes: _filters.actionTypes);
    _load();
  }

  void _onMergedFocus() {
    if (mounted && _mergedOn) setState(() => _visibleCount = kReportPageStep);
  }

  /// سطر الشريط: من لم يُقرأ ولماذا (و«قد تنقص»)، وإيراد شركةٍ بعملةٍ أخرى خارج المجموع.
  String? _mergedNote(MergedReport<ActivityRow> m) {
    final focus = MergedMode.focused;
    final lines = <String>[
      if (m.noteFor(focus?.key,
              unsupportedText: 'لا حركاتٍ تُقرأ لنوعها من هنا',
              missingText: 'merged.missing'.trm(args: [m.missing.map((c) => c.name).join('، ')]))
          case final n?)
        n,
      if (focus == null)
        for (final p in m.parts)
          if (p.ok && p.company.currency != 'IQD')
            'merged.not_in_sum'.trm(args: ['إيراد «${p.company.name}» (${p.company.currency ?? 'عملةٌ غير معروفة'})']),
    ];
    return lines.isEmpty ? null : lines.join('\n');
  }

  /// «حسب الشركة»: عدد حركات كلّ شركةٍ وإيرادها (بفلتر النوع)، أو سبب غيابها.
  List<MergedBreakdownRow> _breakdown(MergedReport<ActivityRow> m) {
    final types = _filters.actionTypes;
    bool keep(ActivityRow r) => types == null || types.isEmpty || types.toSet().contains(r.actionType.toUpperCase().trim());
    return [
      for (final p in m.parts)
        if (p.ok)
          (() {
            final rows = p.rows!.where(keep).toList();
            final cash = rows.where(_isCash).fold<num>(0, (s, r) => s + r.amount);
            final iqd = p.company.currency == 'IQD';
            return (
              key: p.company.key,
              value: '${rows.length} ${'reports.activations_count'.tr()}',
              sub: iqd
                  ? '${'dashboard.revenue'.tr()}: ${formatIQD(cash)} ${'common.currency'.tr()}'
                  : '${'dashboard.revenue'.tr()}: ${formatIQD(cash)} ${p.company.currency ?? ''} — خارج المجموع',
              reason: null,
            );
          })()
        else
          (
            key: p.company.key,
            value: null,
            sub: null,
            reason: p.unsupported ? 'لا حركاتٍ تُقرأ لنوعها من هنا' : (p.error ?? 'تعذّر جلب التقرير الآن'),
          ),
    ];
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
      final m = await loadMergedReport<ActivityRow>(
        supports: (c) => c.provider != MergedProvider.ftth && c.provider != MergedProvider.fiberx,
        fetch: (c) async {
          final r = await ReportsApi.activities(from: _range.from, to: _range.to, userIds: [c.adminId], limit: _rowCap);
          return (
            ok: r.ok,
            rows: r.rows.where(_isActivation).toList(),
            error: r.error,
            note: r.ok && r.rows.length >= _rowCap ? 'بلغت ${formatIQD(_rowCap)} حركة — الأرقام قد تنقص' : null,
          );
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
    final r = await ReportsApi.activities(
      from: _range.from,
      to: _range.to,
      userIds: _filters.actionManagerId == null ? _scopeIds : null,
      actionManagerId: _filters.actionManagerId,
      userManager: _filters.userManager,
      employeeId: _filters.employeeId,
      limit: 5000,
    );
    if (!mounted || gen != _gen || _mergedOn) return;
    final filtered = r.rows.where(_isActivation).toList();
    setState(() {
      _merged = null;
      _loading = false;
      _rows = filtered;
      _error = r.ok ? null : (r.error ?? 'common.load_failed'.tr());
      _visibleCount = kReportPageStep;
    });
  }

  // العدّادات + المجموع يعكسان الفلتر النشط (visible) — لو الفلتر "الكل"
  // نستعمل _rows كامل، لو مختار نوع محدّد نستعمل الصفوف المفلترة فقط.
  num get _totalCash {
    num s = 0;
    for (final e in _visibleRows) {
      // «كل الشركات»: الدينار وحده يُجمع
      if (_isCash(e.row) && _cashCounts(e.key)) s += e.row.amount;
    }
    return s;
  }

  int get _activateCount => _visibleRows.where((e) {
        final at = e.row.actionType.toUpperCase().trim();
        return at == 'SUBSCRIBER_ACTIVATE' || at == 'SUBSCRIBER_ADD';
      }).length;
  int get _extendCount => _visibleRows.where((e) {
        return e.row.actionType.toUpperCase().trim() == 'SUBSCRIBER_EXTEND';
      }).length;

  // صفوف للتصدير — visible (يحترم الفلتر النشط).
  // ترتيب الأعمدة (2026-07-12): اسم المشترك بارز → يوزر → مبلغ → تاريخ
  // → وصف → نوع (عربي) → منفّذ.
  List<List<String>> get _exportRows => [
        for (final e in _visibleRows)
          [
            if (_mergedOn) MergedMode.companyOf(e.key)?.name ?? '',
            e.row.userFullName ?? e.row.targetName ?? e.row.userUsername ?? '',
            e.row.userUsername ?? '',
            e.row.amount == 0 ? '' : e.row.amount.toString(),
            exportTime(e.row.createdAt),
            (e.row.actionDescription ?? '').replaceAll('\n', ' '),
            _actionLabel(e.row),
            e.row.actingEmployeeFullName ?? e.row.adminUsername ?? '',
          ],
      ];

  // أوزان أعمدة PDF — الاسم/الوصف الأوسع، النوع/المنفّذ الأضيق.
  static const List<double> _pdfWeights = [2.2, 1.4, 1.2, 1.4, 2.6, 1.1, 1.3];

  String _actionLabel(ActivityRow r) {
    final at = r.actionType.toUpperCase().trim();
    if (at == 'SUBSCRIBER_EXTEND') return 'actions.extend'.tr();
    return 'actions.activate'.tr();
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final visible = _visibleRows;
    final shown = _visibleCount.clamp(0, visible.length);
    final remaining = visible.length - shown;
    final pageRows = visible.isEmpty
        ? const <({String? key, ActivityRow row})>[]
        : visible.take(_visibleCount).toList();
    final merged = _mergedOn ? _merged : null;
    final mergedAll = merged != null && MergedMode.focused == null;

    return ReportPermissionGate(
      permission: 'reports.activations',
      title: 'reports.activations'.tr(),
      child: Scaffold(
        backgroundColor: AppColors.bg,
        appBar: deskPageBar(
          context,
          mobile: AppBar(
            backgroundColor: AppColors.surface,
            elevation: 0,
            scrolledUnderElevation: 0,
            title: Text(
              'reports.activations'.tr(),
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
                // «كل الشركات»: الشركات بعدد حركات كلٍّ منها، ومن لم يُقرأ ولماذا
                if (merged != null) ...[
                  MergedCompanyStrip(
                    countOf: merged.countOf,
                    total: merged.total,
                    problemOf: (c) => merged.problemOf(c,
                        failedLabel: 'merged.chip_failed'.trm(), unsupportedLabel: 'merged.web_only'.trm()),
                    note: _mergedNote(merged),
                  ),
                  const SizedBox(height: Sp.md),
                ],
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
                  includeActionManager: !_mergedOn,
                  includeUserManager: !_mergedOn,
                  includeEmployee: !_mergedOn,
                  value: _filters,
                  actionTypeOptions: kActivationsActionTypes,
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
                if (!_loading && mergedAll && merged.parts.isNotEmpty) ...[
                  MergedBreakdownCard(rows: _breakdown(merged)),
                  const SizedBox(height: Sp.md),
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
                        title: 'reports.activations'.tr(),
                        subtitle:
                            '${_dateStr(_range.from)} → ${_dateStr(_range.to)}',
                        fileNameBase: 'activations',
                        columns: [
                          if (_mergedOn) 'merged.col_company'.trm(),
                          'reports.col_subscriber'.tr(),
                          'reports.col_username'.tr(),
                          'reports.col_amount'.tr(),
                          'reports.col_date'.tr(),
                          'reports.col_description'.tr(),
                          'reports.col_type'.tr(),
                          'reports.col_executor'.tr(),
                        ],
                        columnWeights: [if (_mergedOn) 1.4, ..._pdfWeights],
                        rows: _exportRows,
                      ),
                    ],
                  ),
                  const SizedBox(height: Sp.sm),
                  for (final e in pageRows) ...[
                    // «كل الشركات»: شركة الحركة فوق سطرها (كالتقرير الماليّ)
                    if (mergedAll && e.key != null)
                      Padding(
                        padding: const EdgeInsetsDirectional.only(start: 4, bottom: 2),
                        child: CompanyTag(companyKey: e.key!, fontSize: 11),
                      ),
                    if (e.row case final r)
                    ReportLogTile(
                      actionType: r.actionType,
                      description: r.actionDescription ?? '',
                      amount: r.amount,
                      adminUsername: r.adminUsername,
                      employeeFullName: r.actingEmployeeFullName,
                      subscriberFullName: r.userFullName,
                      subscriberUsername: r.userUsername,
                      targetName: r.targetName ?? r.userUsername,
                      createdAt: r.createdAt,
balanceAfter: r.balanceAfter,
                    ),
                    const SizedBox(height: 4),
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
            child: _stat(
              icon: LucideIcons.zap,
              label: 'reports.total'.tr(),
              value: '${_visibleRows.length}',
              color: AppColors.success,
            ),
          ),
          Container(width: 1, height: 32, color: AppColors.border),
          Expanded(
            child: _stat(
              icon: LucideIcons.userCheck,
              label: 'reports.activations_count'.tr(),
              value: '$_activateCount',
              color: AppColors.success,
            ),
          ),
          Container(width: 1, height: 32, color: AppColors.border),
          Expanded(
            child: _stat(
              icon: LucideIcons.repeat,
              label: 'reports.extensions_count'.tr(),
              value: '$_extendCount',
              color: AppColors.success,
            ),
          ),
          Container(width: 1, height: 32, color: AppColors.border),
          Expanded(
            child: _stat(
              icon: LucideIcons.dollarSign,
              label: 'dashboard.revenue'.tr(),
              value: formatIQD(_totalCash),
              color: AppColors.brand,
            ),
          ),
        ],
      ),
    );
  }

  Widget _stat({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Column(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(height: 4),
        // ⚠️ الإيراد يتقلّص ولا يُقصّ: العمود ٦٥ نقطةً عند ٣٢٠،
        // و«12,500,000» يتجاوزها — ورقمٌ ماليٌّ مبتورٌ يُقرأ خطأً.
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(value,
              style: AppType.rowLabelBold(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
        ),
        // `maxLines: 1` بلا `overflow` تعني `TextOverflow.clip` —
        // تُشرَّح الكلمة من منتصف الحرف بلا «…»، فيرى المستخدم كلمةً
        // تبدو تامّةً لكنّها **مختلفة**. الحذف الظاهر أصدق من بترٍ صامت.
        Text(label,
            style: AppType.muted().copyWith(fontSize: 10.5),
            maxLines: 1,
            overflow: TextOverflow.ellipsis),
      ],
    );
  }

  Widget _emptyBlock() => Padding(
        padding: const EdgeInsets.symmetric(vertical: Sp.huge),
        child: Center(
          child: Column(
            children: [
              Icon(LucideIcons.zap, size: 36, color: AppColors.textLow),
              const SizedBox(height: 10),
              Text('reports.no_activations_extensions'.tr(),
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
                label: Text('common.retry'.tr()),
              ),
            ],
          ),
        ),
      );

  static String _dateStr(DateTime? d) {
    if (d == null) return '';
    String p(int v) => v.toString().padLeft(2, '0');
    return '${d.year}-${p(d.month)}-${p(d.day)}';
  }
}
