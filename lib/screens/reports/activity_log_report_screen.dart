import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../api/reports_api.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import 'widgets/date_range_chip.dart';
import 'widgets/report_export.dart';
import 'widgets/report_log_tile.dart';
import 'widgets/report_pagination.dart';
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
    final r = await ReportsApi.activities(
      from: _range.from,
      to: _range.to,
      search: _search.isEmpty ? null : _search,
      userIds: _scopeIds,
      limit: 5000,
    );
    if (!mounted) return;
    setState(() {
      _loading = false;
      _rows = r.rows;
      _error = r.ok ? null : (r.error ?? 'تعذّر التحميل');
      _page = 0;
    });
  }

  List<List<String>> get _exportRows => _rows
      .map((r) => [
            r.createdAt,
            r.actionType,
            r.targetName ?? r.userUsername ?? '',
            (r.actionDescription ?? '').replaceAll('\n', ' '),
            r.amount == 0 ? '' : r.amount.toString(),
            r.actingEmployeeFullName ?? r.adminUsername ?? '',
          ])
      .toList();

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final totalPages =
        (_rows.length / _pageSize).ceil().clamp(1, 99999);
    final pageStart = _page * _pageSize;
    final pageEnd = (pageStart + _pageSize).clamp(0, _rows.length);
    final pageRows = _rows.isEmpty
        ? const <ActivityRow>[]
        : _rows.sublist(pageStart, pageEnd);

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          'سجل النشاط',
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
                      hintText: 'ابحث في الوصف / المشترك / المدير...',
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
                  ReportExportBar(
                    title: 'سجل النشاط',
                    subtitle:
                        '${_dateStr(_range.from)} → ${_dateStr(_range.to)}',
                    fileNameBase: 'activity_log',
                    columns: const [
                      'التاريخ',
                      'النوع',
                      'الهدف',
                      'الوصف',
                      'المبلغ',
                      'المنفّذ',
                    ],
                    rows: _exportRows,
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
                                  ReportStatsBar(
                                    totalItems: _rows.length,
                                    pageStart: pageStart,
                                    pageEnd: pageEnd,
                                    pageSize: _pageSize,
                                    onPageSizeChange: (s) => setState(() {
                                      _pageSize = s;
                                      _page = 0;
                                    }),
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
                Text('لا توجد نشاطات في هذه الفترة',
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
                  label: const Text('إعادة المحاولة'),
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
