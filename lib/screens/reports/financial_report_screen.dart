import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../api/reports_api.dart';
import '../../core/util/format.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import 'widgets/date_range_chip.dart';
import 'widgets/report_export.dart';
import 'widgets/report_log_tile.dart';
import 'widgets/report_pagination.dart';
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
  int _page = 0;
  int _pageSize = 25;

  /// فلتر نوع الحركة على قائمة "آخر الحركات".
  String _typeFilter = 'all';

  static const Map<String, ({String label, List<String> types})>
      _typeGroups = {
    'activate': (
      label: 'تفعيل',
      types: ['SUBSCRIBER_ACTIVATE', 'SUBSCRIBER_ADD'],
    ),
    'extend': (label: 'تمديد', types: ['SUBSCRIBER_EXTEND']),
    'debt_pay': (label: 'تسديد دين', types: ['DEBT_PAY', 'BALANCE_DEDUCT']),
    'debt_add': (label: 'إضافة دين', types: ['BALANCE_ADD']),
    // backend `/api/reports/finance` يحقن الصرفيات كصفوف صناعية بـ
    // action_type='ADMIN_EXPENSE' (مطلع 2026-05-x)، مو EXPENSE_ADD.
    // نقبل كليهما للتوافق مع كلاّ المسارَين.
    'expenses': (label: 'صرفيات', types: ['ADMIN_EXPENSE', 'EXPENSE_ADD']),
  };

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
      // 2000 حد أعلى مطمئن للـmerge بين backend KPIs والمُحسَبة client-side
      // عند تفعيل فلتر. مغلق على 2000 لتقليل حجم الاستجابة.
      recentLimit: 2000,
    );
    if (!mounted) return;
    setState(() {
      _loading = false;
      _data = r.data;
      _error = r.ok ? null : (r.error ?? 'تعذّر التحميل');
      _page = 0;
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
                // KPIs: عند الفلتر "الكل" استعمل قيم backend (فترة كاملة).
                // عند فلتر محدّد نحسب من الـrecentLogs المفلترة.
                Builder(builder: (_) {
                  final filtered = _filterLogs(_data!.recentLogs);
                  final effectiveKpis = _typeFilter == 'all'
                      ? _data!.kpis
                      : _kpisFromLogs(filtered);
                  return Column(
                    children: [
                      _hero(effectiveKpis),
                      const SizedBox(height: Sp.md),
                      _kpiGrid(effectiveKpis),
                      const SizedBox(height: Sp.lg),
                    ],
                  );
                }),
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
  /// تصميم موحّد مع بقية بطاقات KPI (surface + border خفيف)، والاعتماد
  /// على اللون فقط في القيم الرقمية والأيقونات (تعليق مستخدم 2026-07-10:
  /// الـgradient كان نشازاً).
  Widget _hero(FinanceKPIs k) {
    final brand = AppColors.brand;
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
                child: Icon(LucideIcons.wallet,
                    size: 14, color: brand),
              ),
              const SizedBox(width: 8),
              Text('الإيراد النقدي الإجمالي',
                  style: AppType.muted().copyWith(
                      fontSize: 11, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${formatIQD(k.totalCashRevenue)} د.ع',
            style: AppType.title(color: brand).copyWith(
              fontSize: 24,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: Sp.sm),
          // خط فاصل خفيف يفصل الإيراد عن الصافي/المصاريف
          Container(height: 1, color: AppColors.border),
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
                  icon: k.netCash < 0
                      ? LucideIcons.trendingDown
                      : LucideIcons.trendingUp,
                  label: 'الصافي',
                  // formatIQD تشيل الإشارة — نضيفها هنا. الأيقونة واللون
                  // يتبدّلان كذلك حتى يوضح الصافي السالب (المصاريف > الإيراد).
                  value: k.netCash < 0
                      ? '-${formatIQD(k.netCash)}'
                      : formatIQD(k.netCash),
                  color: k.netCash < 0 ? AppColors.error : brand,
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
                  style: AppType.muted().copyWith(
                      fontSize: 10, fontWeight: FontWeight.w600)),
              Text(
                value,
                style: TextStyle(
                  color: color,
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _kpiGrid(FinanceKPIs k) {
    // تسديد دين = debt_pay + balance_deduct مجموعان (BALANCE_DEDUCT مع
    // description "تسديد دين …" هو تسديد دين فعلياً — مطابق web _shared.tsx).
    final debtPayTotal = k.debtPaySum + k.balanceDeductSum;
    final items = <_KpiItem>[
      _KpiItem('تفعيل نقدي', formatIQD(k.activateCashSum), const Color(0xFF14B8A6), LucideIcons.zap),
      _KpiItem('تسديد دين', formatIQD(debtPayTotal), const Color(0xFF14B8A6), LucideIcons.banknote),
      _KpiItem('تفعيل غير نقدي', formatIQD(k.activateNonCashSum), AppColors.error, LucideIcons.creditCard, isDebit: true),
      _KpiItem('إضافة دين', formatIQD(k.balanceAddSum), AppColors.error, LucideIcons.plus, isDebit: true),
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
                    // المبالغ: أحمر (سالب) لـdebit، أخضر (موجب) للباقي.
                    // العدّاد يبقى بلون النص العادي.
                    color: it.isCount
                        ? AppColors.textHi
                        : (it.isDebit
                            ? AppColors.error
                            : const Color(0xFF14B8A6)),
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

  List<FinanceLog> _filterLogs(List<FinanceLog> logs) {
    if (_typeFilter == 'all') return logs;
    final grp = _typeGroups[_typeFilter];
    if (grp == null) return logs;
    final wanted = grp.types.toSet();
    return logs
        .where((l) => wanted.contains(l.actionType.toUpperCase().trim()))
        .toList();
  }

  /// نحسب KPIs من قائمة FinanceLog — يُستدعى عند تفعيل فلتر لعرض
  /// قيم مطابقة للفلتر بدلاً من فترة كاملة. عند "الكل" نستعمل قيم
  /// backend مباشرةً (أدقّ لأنها من الاستعلام الكامل بلا حد).
  FinanceKPIs _kpisFromLogs(List<FinanceLog> logs) {
    num activateCash = 0,
        activateNonCash = 0,
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
    );
  }

  int _countLogsFor(String key, List<FinanceLog> logs) {
    if (key == 'all') return logs.length;
    final grp = _typeGroups[key];
    if (grp == null) return 0;
    final wanted = grp.types.toSet();
    return logs
        .where((l) => wanted.contains(l.actionType.toUpperCase().trim()))
        .length;
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
    final filtered = _filterLogs(logs);
    final totalPages =
        (filtered.length / _pageSize).ceil().clamp(1, 99999);
    final pageStart = _page * _pageSize;
    final pageEnd = (pageStart + _pageSize).clamp(0, filtered.length);
    final pageRows = filtered.isEmpty
        ? const <FinanceLog>[]
        : filtered.sublist(pageStart, pageEnd);
    final exportRows = filtered
        .map((l) => [
              l.createdAt,
              l.actionType,
              l.targetName ?? l.userUsername ?? '',
              (l.actionDescription ?? '').replaceAll('\n', ' '),
              l.amount == 0 ? '' : l.amount.toString(),
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
                      .copyWith(fontSize: 13, fontWeight: FontWeight.w800)),
              const Spacer(),
              Text('${filtered.length}',
                  style: AppType.muted().copyWith(fontSize: 11)),
            ],
          ),
        ),
        _typeChipsFor(logs),
        const SizedBox(height: Sp.sm),
        Row(
          children: [
            Expanded(
              child: ReportStatsBar(
                totalItems: filtered.length,
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
              title: 'التقرير المالي',
              subtitle: '${_dateStr(_range.from)} → ${_dateStr(_range.to)}',
              fileNameBase: 'financial',
              columns: const [
                'التاريخ',
                'النوع',
                'الهدف',
                'الوصف',
                'المبلغ',
                'المنفّذ',
              ],
              rows: exportRows,
            ),
          ],
        ),
        const SizedBox(height: Sp.sm),
        for (final l in pageRows) ...[
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
        if (totalPages > 1)
          ReportPager(
            page: _page,
            totalPages: totalPages,
            onPrev: () => setState(() => _page--),
            onNext: () => setState(() => _page++),
          ),
      ],
    );
  }

  static String _dateStr(DateTime? d) {
    if (d == null) return '';
    String p(int v) => v.toString().padLeft(2, '0');
    return '${d.year}-${p(d.month)}-${p(d.day)}';
  }

  Widget _typeChipsFor(List<FinanceLog> logs) {
    Color colorFor(String key) => switch (key) {
          'activate' => const Color(0xFF14B8A6),
          'extend' => const Color(0xFF3B82F6),
          'debt_pay' => const Color(0xFF14B8A6),
          'debt_add' => AppColors.error,
          'expenses' => AppColors.error,
          _ => const Color(0xFF14B8A6),
        };
    final entries = [
      ('all', 'الكل', _countLogsFor('all', logs), const Color(0xFF14B8A6)),
      for (final e in _typeGroups.entries)
        (e.key, e.value.label, _countLogsFor(e.key, logs), colorFor(e.key)),
    ];
    return SizedBox(
      height: 30,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: entries.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (_, i) {
          final c = entries[i];
          final selected = _typeFilter == c.$1;
          return InkWell(
            borderRadius: BorderRadius.circular(R.sm),
            onTap: () => setState(() {
              _typeFilter = c.$1;
              _page = 0;
            }),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: selected
                    ? c.$4.withValues(alpha: 0.18)
                    : AppColors.surface,
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
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: selected ? c.$4 : AppColors.textMid,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: (selected ? c.$4 : AppColors.textLow)
                          .withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text(
                      '${c.$3}',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        color: selected ? c.$4 : AppColors.textMid,
                      ),
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
