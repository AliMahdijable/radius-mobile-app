import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../api/expenses_api.dart';
import '../../api/reports_api.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import 'widgets/action_labels.dart';
import 'widgets/date_range_chip.dart';
import 'widgets/report_export.dart';
import 'widgets/report_filters.dart';
import 'widgets/report_log_tile.dart';
import 'widgets/report_pagination.dart';
import 'widgets/report_permission_gate.dart';
import 'widgets/scope_helper.dart';

/// سجل النشاط الكامل — كل العمليات في النظام، مع filter فترة + بحث +
/// pagination + تصدير.
class ActivityLogReportScreen extends StatefulWidget {
  const ActivityLogReportScreen({super.key});

  @override
  State<ActivityLogReportScreen> createState() =>
      _ActivityLogReportScreenState();
}

class _ActivityLogReportScreenState extends State<ActivityLogReportScreen> {
  DateRange _range = DateRange.thisWeek();
  String _search = '';
  List<ActivityRow> _rows = const [];
  bool _loading = true;
  String? _error;
  final _searchCtrl = TextEditingController();
  List<String>? _scopeIds;
  int _page = 0;
  int _pageSize = 25;

  /// فلاتر متقدّمة (مدير الحركة / مدير المستخدم / الموظف).
  ReportFilters _filters = const ReportFilters();

  // فلتر النوع القديم استُبدل بـReportFiltersPanel multi-select.
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

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    _scopeIds ??= await loadScopeUserIds();
    // نجلب activities + expenses بالتوازي.
    // الصرفيات في جدول منفصل ولا تظهر في /api/activities — نجلبها من
    // /api/admin/expenses ونحوّلها إلى ActivityRow صناعية.
    final results = await Future.wait([
      ReportsApi.activities(
        from: _range.from,
        to: _range.to,
        search: _search.isEmpty ? null : _search,
        userIds:
            _filters.actionManagerId == null ? _scopeIds : null,
        actionManagerId: _filters.actionManagerId,
        userManager: _filters.userManager,
        employeeId: _filters.employeeId,
        limit: 5000,
      ),
      ExpensesApi.list(
        from: _fmt(_range.from),
        to: _fmt(_range.to),
        limit: 2000,
      ),
    ]);
    final r = results[0] as ({bool ok, List<ActivityRow> rows, String? error});
    final expList = results[1] as ({List<ExpenseRow> rows, num total});

    if (!mounted) return;

    // نحوّل الصرفيات لـActivityRow-shaped rows. نصنع id مركّب مع فارق
    // كبير حتى لا يتصادم مع IDs الحقيقية.
    final expenseRows = expList.rows
        .where((e) {
          if (_search.isNotEmpty) {
            return (e.note ?? '').contains(_search);
          }
          return true;
        })
        .map((e) => ActivityRow(
              id: 900000000 + e.id,
              actionType: 'EXPENSE_ADD',
              actionDescription: e.note ?? 'actions.expense'.tr(),
              amount: e.amount,
              adminUsername: null,
              actingEmployeeFullName: e.actingEmployeeUsername,
              targetName: null,
              createdAt: e.expenseDate,
            ))
        .toList();

    // ندمج ونرتّب DESC حسب createdAt (نص ISO / YYYY-MM-DD).
    final merged = [...r.rows, ...expenseRows]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    setState(() {
      _loading = false;
      _rows = merged;
      _error = r.ok ? null : (r.error ?? 'common.load_failed'.tr());
      _page = 0;
    });
  }

  static String _fmt(DateTime? d) {
    if (d == null) return '';
    String p(int v) => v.toString().padLeft(2, '0');
    return '${d.year}-${p(d.month)}-${p(d.day)}';
  }

  // ترتيب أعمدة Excel/PDF المطلوب (2026-07-12): اسم المشترك بالعربي أولاً
  // → يوزر → مبلغ → تاريخ → وصف → نوع (عربي) → منفّذ.
  List<List<String>> get _exportRows => _visibleRows
      .map((r) => [
            r.userFullName ?? r.targetName ?? r.userUsername ?? '',
            r.userUsername ?? '',
            r.amount == 0 ? '' : r.amount.toString(),
            r.createdAt,
            (r.actionDescription ?? '').replaceAll('\n', ' '),
            arabicActionLabel(r.actionType, r.actionDescription ?? ''),
            r.actingEmployeeFullName ?? r.adminUsername ?? '',
          ])
      .toList();

  static const List<double> _pdfWeights = [2.2, 1.4, 1.2, 1.4, 2.6, 1.1, 1.3];

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
      permission: 'reports.activity_log',
      title: 'reports.activity_log'.tr(),
      child: Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          'reports.activity_log'.tr(),
          style: AppType.title(color: AppColors.textHi).copyWith(fontSize: 16),
        ),
        iconTheme: IconThemeData(color: AppColors.textHi),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, Sp.sm),
              child: Column(
                children: [
                  DateRangeChipBar(
                    value: _range,
                    onChanged: (r) {
                      setState(() => _range = r);
                      _load();
                    },
                  ),
                  const SizedBox(height: Sp.sm),
                  TextField(
                    controller: _searchCtrl,
                    onSubmitted: (v) {
                      _search = v.trim();
                      _load();
                    },
                    decoration: InputDecoration(
                      hintText: 'reports.search_hint'.tr(),
                      hintStyle: AppType.input(color: AppColors.textLow),
                      prefixIcon: Icon(LucideIcons.search,
                          size: 18, color: AppColors.textMid),
                      filled: true,
                      fillColor: AppColors.surfaceInput,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(R.sm),
                        borderSide: BorderSide(color: AppColors.border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(R.sm),
                        borderSide: BorderSide(color: AppColors.border),
                      ),
                    ),
                  ),
                  const SizedBox(height: Sp.sm),
                  ReportFiltersPanel(
                    value: _filters,
                    onChanged: (v) {
                      setState(() {
                        _filters = v;
                        _page = 0;
                      });
                      _load();
                    },
                  ),
                ],
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _load,
                color: AppColors.brand,
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _error != null
                        ? _errorState()
                        : _rows.isEmpty
                            ? _emptyState()
                            : ListView(
                                padding: const EdgeInsets.fromLTRB(
                                    Sp.lg, Sp.sm, Sp.lg, Sp.huge),
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: ReportStatsBar(
                                          totalItems: visible.length,
                                          pageStart: pageStart,
                                          pageEnd: pageEnd,
                                          pageSize: _pageSize,
                                          onPageSizeChange: (s) =>
                                              setState(() {
                                            _pageSize = s;
                                            _page = 0;
                                          }),
                                        ),
                                      ),
                                      ReportExportBar(
                                        title: 'reports.activity_log'.tr(),
                                        subtitle:
                                            '${_dateStr(_range.from)} → ${_dateStr(_range.to)}',
                                        fileNameBase: 'activity_log',
                                        columns: [
                                          'reports.col_subscriber'.tr(),
                                          'reports.col_username'.tr(),
                                          'reports.col_amount'.tr(),
                                          'reports.col_date'.tr(),
                                          'reports.col_description'.tr(),
                                          'reports.col_type'.tr(),
                                          'reports.col_executor'.tr(),
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
                                      employeeFullName:
                                          r.actingEmployeeFullName,
                                      subscriberFullName: r.userFullName,
                                      subscriberUsername: r.userUsername,
                                      targetName:
                                          r.targetName ?? r.userUsername,
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
                              ),
              ),
            ),
          ],
        ),
      ),
    ),
    );
  }

  Widget _emptyState() => ListView(
        children: [
          const SizedBox(height: Sp.huge * 2),
          Center(
            child: Column(
              children: [
                Icon(LucideIcons.fileText, size: 36, color: AppColors.textLow),
                const SizedBox(height: 10),
                Text('reports.no_activities_period'.tr(),
                    style: AppType.label(color: AppColors.textMid)),
              ],
            ),
          ),
        ],
      );

  Widget _errorState() => ListView(
        children: [
          const SizedBox(height: Sp.huge),
          Center(
            child: Column(
              children: [
                Icon(LucideIcons.triangleAlert,
                    size: 32, color: AppColors.error),
                const SizedBox(height: 8),
                Text(_error!,
                    style: AppType.subtitle(color: AppColors.textMid)),
                const SizedBox(height: Sp.md),
                ElevatedButton.icon(
                  onPressed: _load,
                  icon: const Icon(LucideIcons.refreshCw, size: 16),
                  label: Text('common.retry'.tr()),
                ),
              ],
            ),
          ),
        ],
      );

  static String _dateStr(DateTime? d) {
    if (d == null) return '';
    String p(int v) => v.toString().padLeft(2, '0');
    return '${d.year}-${p(d.month)}-${p(d.day)}';
  }

}
