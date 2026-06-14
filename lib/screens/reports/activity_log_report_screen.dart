import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../api/reports_api.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import 'widgets/date_range_chip.dart';
import 'widgets/report_log_tile.dart';

/// سجل النشاط الكامل — كل العمليات في النظام، مع filter فترة + بحث.
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
    final r = await ReportsApi.activities(
      from: _range.from,
      to: _range.to,
      search: _search.isEmpty ? null : _search,
    );
    if (!mounted) return;
    setState(() {
      _loading = false;
      _rows = r.rows;
      _error = r.ok ? null : (r.error ?? 'تعذّر التحميل');
    });
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep
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
                            : ListView.separated(
                                padding: const EdgeInsets.fromLTRB(
                                    Sp.lg, Sp.sm, Sp.lg, Sp.huge),
                                itemCount: _rows.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: 4),
                                itemBuilder: (_, i) {
                                  final r = _rows[i];
                                  return ReportLogTile(
                                    actionType: r.actionType,
                                    description: r.actionDescription ?? '',
                                    amount: r.amount,
                                    adminUsername: r.adminUsername,
                                    employeeFullName: r.actingEmployeeFullName,
                                    targetName: r.targetName ?? r.userUsername,
                                    createdAt: r.createdAt,
                                  );
                                },
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
}
