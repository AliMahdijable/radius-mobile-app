import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../api/reports_api.dart';
import '../../core/util/format.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import 'widgets/date_range_chip.dart';
import 'widgets/report_export.dart';
import 'widgets/report_pagination.dart';
import 'widgets/scope_helper.dart';

/// التفعيلات اليومية — مُجمّعة بـday + إيراد لكل يوم + عدد نقدي/غير.
class DailyActivationsReportScreen extends StatefulWidget {
  const DailyActivationsReportScreen({super.key});

  @override
  State<DailyActivationsReportScreen> createState() =>
      _DailyActivationsReportScreenState();
}

class _DailyActivationsReportScreenState
    extends State<DailyActivationsReportScreen> {
  DateRange _range = DateRange.thisMonth();
  List<DailyActivationRow> _rows = const [];
  bool _loading = true;
  String? _error;
  List<String>? _scopeIds;
  int _page = 0;
  int _pageSize = 25;

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
    final r = await ReportsApi.dailyActivations(
      from: _range.from,
      to: _range.to,
      userIds: _scopeIds,
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
            r.day,
            '${r.count}',
            '${r.nonCashCount}',
            r.cashSum.toString(),
          ])
      .toList();

  int get _totalCount =>
      _rows.fold(0, (s, r) => s + r.count + r.nonCashCount);
  num get _totalCash => _rows.fold<num>(0, (s, r) => s + r.cashSum);

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep
    final totalPages =
        (_rows.length / _pageSize).ceil().clamp(1, 99999);
    final pageStart = _page * _pageSize;
    final pageEnd = (pageStart + _pageSize).clamp(0, _rows.length);
    final pageRows = _rows.isEmpty
        ? const <DailyActivationRow>[]
        : _rows.sublist(pageStart, pageEnd);
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          'التفعيلات اليومية',
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
              const SizedBox(height: Sp.md),
              _summary(),
              const SizedBox(height: Sp.md),
              ReportExportBar(
                title: 'التفعيلات اليومية',
                subtitle:
                    '${_dateStr(_range.from)} → ${_dateStr(_range.to)}',
                fileNameBase: 'daily_activations',
                columns: const [
                  'اليوم',
                  'نقدي',
                  'غير نقدي',
                  'إيراد',
                ],
                rows: _exportRows,
              ),
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
                  _dayRow(r),
                  const SizedBox(height: 6),
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
              label: 'إجمالي التفعيلات',
              value: '$_totalCount',
              color: const Color(0xFF14B8A6),
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
            style: TextStyle(
              color: AppColors.textHi,
              fontSize: 14,
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
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.brand.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(R.sm),
            ),
            child: Text(
              r.day,
              style: TextStyle(
                color: AppColors.brand,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: Sp.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(LucideIcons.zap,
                        size: 12, color: const Color(0xFF14B8A6)),
                    const SizedBox(width: 4),
                    Text('${r.count} نقدي',
                        style: AppType.label(color: AppColors.textHi)
                            .copyWith(fontSize: 11, fontWeight: FontWeight.w700)),
                    const SizedBox(width: 10),
                    Icon(LucideIcons.creditCard,
                        size: 12, color: const Color(0xFFE08F2D)),
                    const SizedBox(width: 4),
                    Text('${r.nonCashCount} غير نقدي',
                        style: AppType.label(color: AppColors.textHi)
                            .copyWith(fontSize: 11, fontWeight: FontWeight.w700)),
                  ],
                ),
                const SizedBox(height: 2),
                Text('إيراد: ${formatIQD(r.cashSum)} د.ع',
                    style: AppType.muted().copyWith(
                        fontSize: 11, color: AppColors.brand)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _dateStr(DateTime? d) {
    if (d == null) return '';
    String p(int v) => v.toString().padLeft(2, '0');
    return '${d.year}-${p(d.month)}-${p(d.day)}';
  }

  Widget _emptyBlock() => Padding(
        padding: const EdgeInsets.symmetric(vertical: Sp.huge),
        child: Center(
          child: Column(
            children: [
              Icon(LucideIcons.calendar,
                  size: 36, color: AppColors.textLow),
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
      );
}
