import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../api/reports_api.dart';
import '../../core/util/format.dart';
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
  int _page = 0;
  int _pageSize = 25;

  /// فلاتر متقدّمة (مدير الحركة / مدير المستخدم / الموظف).
  ReportFilters _filters = const ReportFilters();

  // فلتر النوع القديم استُبدل بـReportFiltersPanel multi-select.
  // _visibleRows يفلتر بحسب _filters.actionTypes.
  List<ActivityRow> get _visibleRows {
    final types = _filters.actionTypes;
    if (types == null || types.isEmpty) return _rows;
    final wanted = types.toSet();
    return _rows
        .where((r) => wanted.contains(r.actionType.toUpperCase().trim()))
        .toList();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    _scopeIds ??= await loadScopeUserIds();
    final r = await ReportsApi.activities(
      from: _range.from,
      to: _range.to,
      userIds:
          _filters.actionManagerId == null ? _scopeIds : null,
      actionManagerId: _filters.actionManagerId,
      userManager: _filters.userManager,
      employeeId: _filters.employeeId,
      limit: 5000,
    );
    if (!mounted) return;
    final filtered = r.rows.where((row) {
      final at = (row.actionType).toUpperCase().trim();
      final desc = (row.actionDescription ?? '').toLowerCase();
      return at == 'SUBSCRIBER_ACTIVATE' ||
          at == 'SUBSCRIBER_EXTEND' ||
          (at == 'SUBSCRIBER_ADD' && desc.contains('تفعيل'));
    }).toList();
    setState(() {
      _loading = false;
      _rows = filtered;
      _error = r.ok ? null : (r.error ?? 'تعذّر التحميل');
      _page = 0;
    });
  }

  // العدّادات + المجموع يعكسان الفلتر النشط (visible) — لو الفلتر "الكل"
  // نستعمل _rows كامل، لو مختار نوع محدّد نستعمل الصفوف المفلترة فقط.
  num get _totalCash {
    num s = 0;
    for (final r in _visibleRows) {
      final isCash = (r.actionDescription ?? '').contains('نقدي') &&
          !(r.actionDescription ?? '').contains('غير نقدي');
      if (isCash) s += r.amount;
    }
    return s;
  }

  int get _activateCount => _visibleRows.where((r) {
        final at = r.actionType.toUpperCase().trim();
        return at == 'SUBSCRIBER_ACTIVATE' || at == 'SUBSCRIBER_ADD';
      }).length;
  int get _extendCount => _visibleRows.where((r) {
        return r.actionType.toUpperCase().trim() == 'SUBSCRIBER_EXTEND';
      }).length;

  // صفوف للتصدير — visible (يحترم الفلتر النشط).
  // ترتيب الأعمدة (2026-07-12): اسم المشترك بارز → يوزر → مبلغ → تاريخ
  // → وصف → نوع (عربي) → منفّذ.
  List<List<String>> get _exportRows => _visibleRows
      .map((r) => [
            r.userFullName ?? r.targetName ?? r.userUsername ?? '',
            r.userUsername ?? '',
            r.amount == 0 ? '0' : r.amount.toString(),
            r.createdAt,
            (r.actionDescription ?? '').replaceAll('\n', ' '),
            _actionLabel(r),
            r.actingEmployeeFullName ?? r.adminUsername ?? '',
          ])
      .toList();

  // أوزان أعمدة PDF — الاسم/الوصف الأوسع، النوع/المنفّذ الأضيق.
  static const List<double> _pdfWeights = [2.2, 1.4, 1.2, 1.4, 2.6, 1.1, 1.3];

  String _actionLabel(ActivityRow r) {
    final at = r.actionType.toUpperCase().trim();
    if (at == 'SUBSCRIBER_EXTEND') return 'تمديد';
    return 'تفعيل';
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final visible = _visibleRows;
    final totalPages =
        (visible.length / _pageSize).ceil().clamp(1, 99999);
    final pageStart = _page * _pageSize;
    final pageEnd = (pageStart + _pageSize).clamp(0, visible.length);
    final pageRows = visible.isEmpty
        ? const <ActivityRow>[]
        : visible.sublist(pageStart, pageEnd);

    return ReportPermissionGate(
      permission: 'reports.activations',
      title: 'reports.activations'.tr(),
      child: Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          'reports.activations'.tr(),
          style: AppType.title(color: AppColors.textHi).copyWith(fontSize: 16),
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
              DateRangeChipBar(
                value: _range,
                onChanged: (r) {
                  setState(() => _range = r);
                  _load();
                },
              ),
              const SizedBox(height: Sp.sm),
              ReportFiltersPanel(
                value: _filters,
                actionTypeOptions: kActivationsActionTypes,
                onChanged: (v) {
                  setState(() {
                    _filters = v;
                    _page = 0;
                  });
                  _load();
                },
              ),
              const SizedBox(height: Sp.md),
              _summary(),
              const SizedBox(height: Sp.md),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: Sp.huge),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_error != null)
                _errorBlock()
              else if (_rows.isEmpty)
                _emptyBlock()
              else ...[
                Row(
                  children: [
                    Expanded(
                      child: ReportStatsBar(
                        totalItems: visible.length,
                        pageStart: pageStart,
                        pageEnd: pageEnd,
                        pageSize: _pageSize,
                        onPageSizeChange: (s) => setState(() {
                          _pageSize = s;
                          _page = 0;
                        }),
                      ),
                    ),
                    ReportExportBar(
                      title: 'reports.activations'.tr(),
                      subtitle:
                          '${_dateStr(_range.from)} → ${_dateStr(_range.to)}',
                      fileNameBase: 'activations',
                      columns: const [
                        'اسم المشترك',
                        'اليوزر',
                        'المبلغ',
                        'التاريخ',
                        'الوصف',
                        'النوع',
                        'المنفّذ',
                      ],
                      columnWeights: _pdfWeights,
                      rows: _exportRows,
                    ),
                  ],
                ),
                const SizedBox(height: Sp.sm),
                for (final r in pageRows) ...[
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
                  ),
                  const SizedBox(height: 4),
                ],
                if (totalPages > 1)
                  ReportPager(
                    page: _page,
                    totalPages: totalPages,
                    onPrev: () => setState(() => _page--),
                    onNext: () => setState(() => _page++),
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
              label: 'إجمالي',
              value: '${_visibleRows.length}',
              color: const Color(0xFF14B8A6),
            ),
          ),
          Container(width: 1, height: 32, color: AppColors.border),
          Expanded(
            child: _stat(
              icon: LucideIcons.userCheck,
              label: 'تفعيلات',
              value: '$_activateCount',
              color: const Color(0xFF14B8A6),
            ),
          ),
          Container(width: 1, height: 32, color: AppColors.border),
          Expanded(
            child: _stat(
              icon: LucideIcons.repeat,
              label: 'تمديدات',
              value: '$_extendCount',
              color: const Color(0xFF26A69A),
            ),
          ),
          Container(width: 1, height: 32, color: AppColors.border),
          Expanded(
            child: _stat(
              icon: LucideIcons.dollarSign,
              label: 'إيراد',
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
        Text(value,
            style: TextStyle(
              color: AppColors.textHi,
              fontSize: 13,
              fontWeight: FontWeight.w900,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis),
        Text(label,
            style: AppType.muted().copyWith(fontSize: 10),
            maxLines: 1),
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
              Text('لا توجد تفعيلات أو تمديدات في هذه الفترة',
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
              Text(_error!,
                  style: AppType.subtitle(color: AppColors.textMid)),
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

  static String _dateStr(DateTime? d) {
    if (d == null) return '';
    String p(int v) => v.toString().padLeft(2, '0');
    return '${d.year}-${p(d.month)}-${p(d.day)}';
  }

}
