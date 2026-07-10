import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../api/reports_api.dart';
import '../../core/util/format.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import 'widgets/date_range_chip.dart';
import 'widgets/report_log_tile.dart';
import 'widgets/scope_helper.dart';

/// التقرير المالي — نسخة موبايل من client-v2/Financial.tsx:
///  • هيرو إجمالي الإيراد + صافي بعد المصاريف
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
    // جالب scope مرّة واحدة ثم يُعاد استخدامه
    _scopeIds ??= await loadScopeUserIds();
    final r = await ReportsApi.finance(
      from: _range.from,
      to: _range.to,
      userIds: _scopeIds,
    );
    if (!mounted) return;
    setState(() {
      _loading = false;
      _data = r.data;
      _error = r.ok ? null : (r.error ?? 'تعذّر التحميل');
    });
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          'التقرير المالي',
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
              if (_loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: Sp.huge),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_error != null)
                _errorPanel()
              else if (_data != null) ...[
                _hero(_data!.kpis),
                const SizedBox(height: Sp.md),
                _kpiGrid(_data!.kpis),
                const SizedBox(height: Sp.lg),
                _recentLogs(_data!.recentLogs),
              ],
            ],
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
              label: const Text('إعادة المحاولة'),
            ),
          ],
        ),
      ),
    );
  }

  /// هيرو — الإيراد الإجمالي + الصافي بعد المصاريف.
  Widget _hero(FinanceKPIs k) {
    final brand = AppColors.brand;
    return Container(
      padding: const EdgeInsets.all(Sp.lg),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            brand.withValues(alpha: 0.18),
            brand.withValues(alpha: 0.04),
          ],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: BorderRadius.circular(R.lg),
        border: Border.all(color: brand.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('الإيراد النقدي الإجمالي',
              style: AppType.muted().copyWith(fontSize: 11)),
          const SizedBox(height: 4),
          Text(
            '${formatIQD(k.totalCashRevenue)} د.ع',
            style: AppType.title(color: AppColors.textHi).copyWith(
              fontSize: 24,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: Sp.sm),
          Row(
            children: [
              Expanded(
                child: _heroMini(
                  icon: LucideIcons.receipt,
                  label: 'المصاريف',
                  value: '-${formatIQD(k.expensesSum)}',
                  color: AppColors.error,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _heroMini(
                  icon: LucideIcons.trendingUp,
                  label: 'الصافي',
                  value: formatIQD(k.netCash),
                  color: brand,
                ),
              ),
            ],
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(R.sm),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label,
                    style: AppType.muted().copyWith(
                        fontSize: 10, color: color.withValues(alpha: 0.85))),
                Text(
                  value,
                  style: TextStyle(
                    color: color,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _kpiGrid(FinanceKPIs k) {
    final items = <_KpiItem>[
      _KpiItem('تفعيل نقدي', formatIQD(k.activateCashSum), const Color(0xFF14B8A6), LucideIcons.zap),
      _KpiItem('تسديد دين', formatIQD(k.debtPaySum), const Color(0xFF0EA5E9), LucideIcons.banknote),
      _KpiItem('استقطاع رصيد', formatIQD(k.balanceDeductSum), const Color(0xFF3B82F6), LucideIcons.minus),
      _KpiItem('تفعيل غير نقدي', formatIQD(k.activateNonCashSum), const Color(0xFFE08F2D), LucideIcons.creditCard, isDebit: true),
      _KpiItem('إضافة دين', formatIQD(k.balanceAddSum), const Color(0xFFE08F2D), LucideIcons.plus, isDebit: true),
      _KpiItem('# تفعيلات', '${k.activationsCount}', const Color(0xFF8B5CF6), LucideIcons.userCheck, isCount: true),
      _KpiItem('# تمديدات', '${k.extendCount}', const Color(0xFF26A69A), LucideIcons.repeat, isCount: true),
      _KpiItem('# مصاريف', '${k.expensesCount}', AppColors.error, LucideIcons.receipt, isCount: true),
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
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.md),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: it.color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(R.sm),
            ),
            child: Icon(it.icon, color: it.color, size: 16),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  it.label,
                  style: AppType.muted().copyWith(fontSize: 10),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  it.isCount ? it.value : '${it.isDebit ? '-' : ''}${it.value}',
                  style: TextStyle(
                    color: it.isDebit ? AppColors.error : AppColors.textHi,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
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

  Widget _recentLogs(List<FinanceLog> logs) {
    if (logs.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: Sp.xl),
        child: Center(
          child: Column(
            children: [
              Icon(LucideIcons.fileText, size: 32, color: AppColors.textLow),
              const SizedBox(height: 8),
              Text('لا توجد حركات مالية في هذه الفترة',
                  style: AppType.muted().copyWith(fontSize: 12)),
            ],
          ),
        ),
      );
    }
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
                      .copyWith(fontSize: 13, fontWeight: FontWeight.w800)),
              const Spacer(),
              Text('${logs.length}',
                  style: AppType.muted().copyWith(fontSize: 11)),
            ],
          ),
        ),
        for (final l in logs) ...[
          ReportLogTile(
            actionType: l.actionType,
            description: l.actionDescription ?? '',
            amount: l.amount,
            adminUsername: l.adminUsername,
            employeeFullName: l.actingEmployeeFullName,
            employeeUsername: l.actingEmployeeUsername,
            targetName: l.targetName ?? l.userUsername,
            createdAt: l.createdAt,
          ),
          const SizedBox(height: 4),
        ],
      ],
    );
  }
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
