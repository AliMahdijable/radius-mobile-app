import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../api/manager_debts_api.dart';
import '../../api/manager_movements_api.dart';
import '../../api/managers_api.dart';
import '../../core/util/format.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import '../managers/sheets/pay_custom_debt_sheet.dart';
import '../managers/sheets/pay_debt_sheet.dart';
import 'widgets/report_export.dart';

/// تقرير موحّد للحركات المالية على المدراء الفرعيين — timeline.
///
/// يفتح من: قوائم أخرى → التقارير → ديون المدراء
///
/// تصميم متّسق مع تقارير المشتركين: كل صف = event مستقل. يشمل:
///   • debt_created  — إضافة دين أخرى (مدين +)
///   • debt_payment  — تسديد دين أخرى (كامل / جزئي)
///   • deposit_cash  — شحن نقدي (يزيد الرصيد)
///   • deposit_loan  — شحن آجل = دين SAS (+ يزيد الدين)
///   • withdraw      — سحب رصيد
///   • sas_pay_debt  — تسديد دين SAS
///   • points        — نقاط مكافأة
///
/// فلاتر: المدير (بحث) + النوع + الحالة (للـpayments) + نطاق تاريخ.
/// Summary: إجمالي دين SAS + إجمالي المتبقّي من ديون أخرى + عدد المدينين.
/// Export: Excel + PDF.
class AllManagersDebtsScreen extends StatefulWidget {
  const AllManagersDebtsScreen({super.key});

  @override
  State<AllManagersDebtsScreen> createState() => _AllManagersDebtsScreenState();
}

enum _TypeFilter {
  all,
  depositCash,
  depositLoan,
  withdraw,
  debtCreated,
  paymentSas,
  paymentCustom,
  points,
}

class _MgrEvent {
  const _MgrEvent({
    required this.manager,
    required this.movement,
    this.isFullPayment = false,
  });

  final Manager manager;
  final ManagerMovement movement;
  /// true = تسديد كامل (لآخر جزء من دين). يُحسب post-fetch من الملاحظات.
  final bool isFullPayment;

  DateTime get date => movement.eventAt;
  double get amount => movement.amount.toDouble();

  /// يطابق الـfilter المنطقي.
  _TypeFilter get typeFilter {
    switch (movement.rowType) {
      case 'debt_created':
        return _TypeFilter.debtCreated;
      case 'debt_payment':
        return _TypeFilter.paymentCustom;
    }
    switch (movement.subKind) {
      case 'deposit_cash':
        return _TypeFilter.depositCash;
      case 'deposit_loan':
        return _TypeFilter.depositLoan;
      case 'withdraw':
        return _TypeFilter.withdraw;
      case 'sas_pay_debt':
        return _TypeFilter.paymentSas;
      case 'points':
        return _TypeFilter.points;
      default:
        return _TypeFilter.all;
    }
  }

  ({String label, IconData icon, Color color, bool debit}) get meta {
    // debt_created — أحمر (سالب على المدير، يزيد دينه)
    if (movement.rowType == 'debt_created') {
      return (
        label: 'إضافة دين أخرى',
        icon: LucideIcons.receipt,
        color: AppColors.error,
        debit: true,
      );
    }
    // debt_payment — أخضر
    if (movement.rowType == 'debt_payment') {
      return (
        label: isFullPayment ? 'تسديد كامل — دين أخرى' : 'تسديد جزئي — دين أخرى',
        icon: LucideIcons.banknote,
        color: const Color(0xFF14B8A6),
        debit: false,
      );
    }
    switch (movement.subKind) {
      case 'deposit_cash':
        return (
          label: 'شحن نقدي',
          icon: LucideIcons.plus,
          color: const Color(0xFF14B8A6),
          debit: false,
        );
      case 'deposit_loan':
        return (
          label: 'شحن آجل — دين SAS',
          icon: LucideIcons.plus,
          color: const Color(0xFFE08F2D),
          debit: true,
        );
      case 'withdraw':
        return (
          label: 'سحب رصيد',
          icon: LucideIcons.circleMinus,
          color: AppColors.error,
          debit: true,
        );
      case 'sas_pay_debt':
        return (
          label: 'تسديد دين SAS',
          icon: LucideIcons.banknote,
          color: const Color(0xFF14B8A6),
          debit: false,
        );
      case 'points':
        return (
          label: 'نقاط مكافأة',
          icon: LucideIcons.star,
          color: const Color(0xFF8B5CF6),
          debit: false,
        );
      default:
        return (
          label: movement.arabicLabel,
          icon: LucideIcons.activity,
          color: AppColors.textMid,
          debit: false,
        );
    }
  }
}

class _AllManagersDebtsScreenState extends State<AllManagersDebtsScreen> {
  List<Manager> _managers = const [];
  List<_MgrEvent> _events = const [];
  ManagerDebtsSummary? _summary;
  bool _loading = true;

  _TypeFilter _typeFilter = _TypeFilter.all;
  String _managerFilter = '';
  DateTime? _dateFrom;
  DateTime? _dateTo;

  final _managerSearchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _managerSearchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    // 1) fetch managers + summary + custom debts (لحساب "تسديد كامل" لاحقاً)
    final coreResults = await Future.wait([
      ManagersApi.listFull(count: 500),
      ManagerDebtsApi.summary(
        from: _dateFrom == null ? null : _fmtDate(_dateFrom!),
        to: _dateTo == null ? null : _fmtDate(_dateTo!),
      ),
      ManagerDebtsApi.list(),
    ]);
    if (!mounted) return;
    final mgrs = (coreResults[0] as ({List<Manager> rows, int total})).rows;
    final summary = coreResults[1] as ManagerDebtsSummary?;
    final customDebts = coreResults[2] as List<ManagerDebt>;

    // 2) concurrent fetch movements — قيد للـtop 60 مدير لتفادي الإرهاق.
    final targets = mgrs.take(60).toList();
    final moveResults = await Future.wait(
      targets.map((m) =>
          ManagerMovementsApi.list(targetAdminId: m.id, limit: 100)),
    );

    // 3) اربط الديون بالـid — عشان نميّز "تسديد كامل" من "جزئي".
    // debt_payment movement.foreignId (لو موجود) يشير للـdebt. نتحقّق:
    //   remainingAmount == 0 و آخر دفعة على هذا الدين → تسديد كامل.
    final debtsById = {for (final d in customDebts) d.id: d};

    // 4) flatten + sort + apply date filter (client-side لأن movements API
    // ما تدعم from/to حالياً).
    final events = <_MgrEvent>[];
    for (int i = 0; i < targets.length; i++) {
      for (final mv in moveResults[i]) {
        if (_dateFrom != null && mv.eventAt.isBefore(_dateFrom!)) continue;
        if (_dateTo != null &&
            mv.eventAt.isAfter(_dateTo!.add(const Duration(days: 1)))) {
          continue;
        }
        bool full = false;
        if (mv.rowType == 'debt_payment') {
          final id = mv.debtId ?? mv.relatedDebtId;
          if (id != null) {
            final d = debtsById[id];
            if (d != null && d.remainingAmount == 0) full = true;
          }
        }
        events.add(_MgrEvent(
          manager: targets[i],
          movement: mv,
          isFullPayment: full,
        ));
      }
    }
    events.sort((a, b) => b.date.compareTo(a.date));

    setState(() {
      _managers = mgrs;
      _events = events;
      _summary = summary;
      _loading = false;
    });
  }

  // ─── filtered view ─────────────────────────

  List<_MgrEvent> get _visible {
    final q = _managerFilter.trim().toLowerCase();
    return _events.where((e) {
      if (_typeFilter != _TypeFilter.all && e.typeFilter != _typeFilter) {
        return false;
      }
      if (q.isNotEmpty) {
        final u = e.manager.username.toLowerCase();
        final n = e.manager.fullName.toLowerCase();
        if (!u.contains(q) && !n.contains(q)) return false;
      }
      return true;
    }).toList();
  }

  // ─── totals (reactive to filters) ─────────────

  /// المدراء المطابقون لبحث اسم المدير — يُستعملون لـSAS totals + عدد
  /// المدينين. لا يتأثر بفلتر النوع/التاريخ (SAS current state).
  List<Manager> get _filteredManagers {
    final q = _managerFilter.trim().toLowerCase();
    if (q.isEmpty) return _managers;
    return _managers
        .where((m) =>
            m.username.toLowerCase().contains(q) ||
            m.fullName.toLowerCase().contains(q))
        .toList();
  }

  double get _totalSasDebt =>
      _filteredManagers.fold<double>(0, (acc, m) => acc + m.totalDebt);

  double get _totalCustomRemaining {
    if (_summary == null) return 0;
    final q = _managerFilter.trim().toLowerCase();
    if (q.isEmpty) return _summary!.totals.totalRemaining;
    return _summary!.perDebtor
        .where((d) => (d.debtorAdminUsername ?? '').toLowerCase().contains(q))
        .fold<double>(0, (acc, d) => acc + d.totalRemaining);
  }

  double get _grandRemaining => _totalSasDebt + _totalCustomRemaining;

  /// إيرادات مستحصَلة من المدراء (من _visible events — تتأثر بكل الفلاتر:
  /// نوع/تاريخ/بحث مدير):
  ///   • شحن نقدي (deposit_cash) = المدير دفع لنا نقداً
  ///   • تسديد دين SAS (sas_pay_debt) = المدير سدّد دين
  ///   • تسديد دين أخرى (debt_payment) = المدير سدّد دين أخرى
  /// النقاط و deposit_loan (رصيد آجل = دين، ليس إيراد) و withdraw
  /// (نحن ندفع للمدير) لا تُحسب.
  double get _totalIncoming {
    double sum = 0;
    for (final e in _visible) {
      final sk = e.movement.subKind;
      if (sk == 'deposit_cash' || sk == 'sas_pay_debt') {
        sum += e.amount;
      } else if (e.movement.rowType == 'debt_payment') {
        sum += e.amount;
      }
    }
    return sum;
  }

  int get _debtorsCount {
    final ids = <int>{};
    for (final m in _filteredManagers) {
      if (m.totalDebt > 0) ids.add(m.id);
    }
    if (_summary != null) {
      final q = _managerFilter.trim().toLowerCase();
      for (final row in _summary!.perDebtor) {
        if (row.totalRemaining <= 0) continue;
        if (q.isNotEmpty &&
            !(row.debtorAdminUsername ?? '').toLowerCase().contains(q)) {
          continue;
        }
        ids.add(row.debtorAdminId);
      }
    }
    return ids.length;
  }

  // ─── actions ───────────────────────────────

  Future<void> _openEvent(_MgrEvent e) async {
    // 2026-07-14: كنّا نفتح شاشة "حركات المدير" — المستخدم قال إنها
    // تخصّ صفحة المدراء (زر الحركات هناك). الآن نفتح sheet تسديد الدين
    // فقط للأنواع المدينة، وبقيّة الأنواع تعطي تلميحاً.
    if (e.movement.subKind == 'sas_pay_debt' ||
        (e.movement.rowType == 'debt_created' && e.manager.totalDebt >= 0)) {
      if (e.manager.totalDebt > 0) {
        final changed = await showPayDebtSheet(context, e.manager);
        if (changed == true) _load();
        return;
      }
    }
    // لا فعل — البطاقة عرض فقط. Snackbar اختياري:
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'للتفاعل مع هذا المدير، افتح: قوائم أخرى → المدراء → ${e.manager.username}'),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final initial = DateTimeRange(
      start: _dateFrom ?? now.subtract(const Duration(days: 30)),
      end: _dateTo ?? now,
    );
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: DateTime(now.year + 1),
      initialDateRange: initial,
    );
    if (picked == null) return;
    setState(() {
      _dateFrom = picked.start;
      _dateTo = picked.end;
    });
    _load();
  }

  void _clearDateRange() {
    setState(() {
      _dateFrom = null;
      _dateTo = null;
    });
    _load();
  }

  // ─── build ─────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final visible = _visible;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        title: Text(
          'reports.manager_debts'.tr(),
          style: AppType.title(color: AppColors.textHi).copyWith(fontSize: 16),
        ),
        iconTheme: IconThemeData(color: AppColors.textHi),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: ReportExportBar(
              title: 'reports.manager_debts'.tr(),
              subtitle: _dateFrom != null && _dateTo != null
                  ? '${_fmtDate(_dateFrom!)} → ${_fmtDate(_dateTo!)}'
                  : 'كل الفترات',
              fileNameBase: 'manager_debts_timeline',
              columns: const [
                'المدير',
                'اسم المستخدم',
                'التاريخ',
                'الحركة',
                'المبلغ',
                'الاتجاه',
                'المصدر',
                'الملاحظة',
              ],
              rows: visible
                  .map((e) => [
                        e.manager.fullName.isEmpty
                            ? e.manager.username
                            : e.manager.fullName,
                        e.manager.username,
                        _fmtDateTime(e.date),
                        e.meta.label,
                        formatIQD(e.amount.abs().round()),
                        e.meta.debit ? '-' : '+',
                        e.movement.source == MovementSource.sas4
                            ? 'الساس'
                            : (e.movement.source != null ? 'يدوي' : ''),
                        (e.movement.note ?? '').trim(),
                      ])
                  .toList(),
              columnWeights: const [1.4, 1.2, 1.2, 1.5, 1.0, 0.6, 0.7, 2.0],
            ),
          ),
          IconButton(
            tooltip: 'common.refresh'.tr(),
            icon: Icon(LucideIcons.refreshCw,
                size: 18, color: AppColors.textMid),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              color: AppColors.brand,
              onRefresh: _load,
              child: CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(child: _summaryCard()),
                  SliverToBoxAdapter(child: _managerSearch()),
                  SliverToBoxAdapter(child: _typeFilters()),
                  SliverToBoxAdapter(child: _dateRangeBar()),
                  if (visible.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: _empty(),
                    )
                  else ...[
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(Sp.lg, 6, Sp.lg, 4),
                        child: Row(
                          children: [
                            Icon(LucideIcons.activity,
                                size: 13, color: AppColors.textMid),
                            const SizedBox(width: 5),
                            Text(
                              '${visible.length} حركة',
                              style: AppType.muted().copyWith(fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(
                          Sp.lg, 4, Sp.lg, Sp.huge),
                      sliver: SliverList.separated(
                        itemCount: visible.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 6),
                        itemBuilder: (_, i) => _eventTile(visible[i]),
                      ),
                    ),
                  ],
                ],
              ),
            ),
    );
  }

  // ─── Summary card ──────────────────────────

  Widget _summaryCard() {
    final visibleCount = _visible.length;
    return Container(
      margin: const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, Sp.sm),
      padding: const EdgeInsets.all(Sp.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(R.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(LucideIcons.wallet, size: 14, color: AppColors.brand),
              const SizedBox(width: 6),
              Text(
                'الملخّص',
                style: AppType.title(color: AppColors.textHi)
                    .copyWith(fontSize: 13),
              ),
              const Spacer(),
              // 2026-07-14: الأرقام أعلى تفاعلية مع الفلاتر — نُظهر
              // الحركات المرئية + المدينين المطابقين.
              Icon(LucideIcons.activity, size: 11, color: AppColors.textLow),
              const SizedBox(width: 3),
              Text('$visibleCount حركة',
                  style: AppType.muted().copyWith(fontSize: 10.5)),
              const SizedBox(width: 8),
              Icon(LucideIcons.userCog, size: 11, color: AppColors.textLow),
              const SizedBox(width: 3),
              Text('$_debtorsCount مدين',
                  style: AppType.muted().copyWith(fontSize: 10.5)),
            ],
          ),
          const SizedBox(height: 10),
          // الصفّ الأوّل: إيرادات مستحصَلة (تتفاعل مع كل الفلاتر) — أهم رقم.
          _heroTile(
            label: 'إيرادات مستحصَلة',
            hint: 'شحن نقدي + تسديد ديون (SAS + أخرى)',
            value: _totalIncoming,
            color: const Color(0xFF14B8A6),
            icon: LucideIcons.trendingUp,
          ),
          const SizedBox(height: 8),
          // الصفّ الثاني: تفصيل المتبقّي (SAS + أخرى) + إجمالي.
          Row(
            children: [
              _statTile(
                label: 'متبقّي SAS',
                value: _totalSasDebt,
                color: const Color(0xFF0EA5E9),
              ),
              const SizedBox(width: 6),
              _statTile(
                label: 'متبقّي أخرى',
                value: _totalCustomRemaining,
                color: const Color(0xFF8B5CF6),
              ),
              const SizedBox(width: 6),
              _statTile(
                label: 'إجمالي المتبقّي',
                value: _grandRemaining,
                color: _grandRemaining > 0
                    ? AppColors.error
                    : const Color(0xFF14B8A6),
                emphasize: true,
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// كارت hero بارز لأهم رقم (الإيرادات المستحصَلة).
  Widget _heroTile({
    required String label,
    required String hint,
    required double value,
    required Color color,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
          colors: [
            color.withValues(alpha: 0.14),
            color.withValues(alpha: 0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(R.sm),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(R.sm),
            ),
            alignment: Alignment.center,
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: AppType.title(color: color)
                      .copyWith(fontSize: 12.5, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 1),
                Text(
                  hint,
                  style: AppType.muted().copyWith(fontSize: 10),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                formatIQD(value.round()),
                style: AppType.title(color: color).copyWith(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    height: 1.1),
              ),
              const SizedBox(width: 4),
              Text(
                'د.ع',
                style: AppType.muted(color: color).copyWith(
                    fontSize: 10.5, fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statTile({
    required String label,
    required double value,
    required Color color,
    bool emphasize = false,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: emphasize ? 0.1 : 0.06),
          borderRadius: BorderRadius.circular(R.sm),
          border: emphasize
              ? Border.all(color: color.withValues(alpha: 0.3))
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: AppType.muted().copyWith(fontSize: 10.5)),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    formatIQD(value.round()),
                    style: AppType.title(color: color).copyWith(
                      fontSize: emphasize ? 16 : 14,
                      fontWeight: FontWeight.w800,
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(width: 3),
                  Text(
                    'د.ع',
                    style: AppType.muted(color: color).copyWith(
                        fontSize: 9, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Manager search ────────────────────────

  Widget _managerSearch() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Sp.lg, 4, Sp.lg, 4),
      child: TextField(
        controller: _managerSearchCtrl,
        onChanged: (v) => setState(() => _managerFilter = v),
        decoration: InputDecoration(
          hintText: 'ابحث باسم المدير…',
          hintStyle: AppType.muted().copyWith(fontSize: 12),
          prefixIcon:
              Icon(LucideIcons.search, size: 15, color: AppColors.textMid),
          suffixIcon: _managerSearchCtrl.text.isEmpty
              ? null
              : IconButton(
                  icon: Icon(LucideIcons.x,
                      size: 14, color: AppColors.textMid),
                  onPressed: () {
                    _managerSearchCtrl.clear();
                    setState(() => _managerFilter = '');
                  },
                ),
          filled: true,
          fillColor: AppColors.surfaceInput,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(R.sm),
            borderSide: BorderSide(color: AppColors.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(R.sm),
            borderSide: BorderSide(color: AppColors.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(R.sm),
            borderSide: BorderSide(color: AppColors.brand),
          ),
        ),
        style: AppType.input(color: AppColors.textHi).copyWith(fontSize: 13),
      ),
    );
  }

  // ─── Type filters ──────────────────────────

  Widget _typeFilters() {
    // 2026-07-14: فلاتر مفصّلة — شحن نقدي/آجل منفصلان، تسديد SAS/أخرى
    // منفصلان. المستخدم يقدر يفصّل الحركات بدقّة.
    const filters = <(_TypeFilter, String, Color)>[
      (_TypeFilter.all, 'الكل', Color(0xFF64748B)),
      (_TypeFilter.depositCash, 'شحن نقدي', Color(0xFF14B8A6)),
      (_TypeFilter.depositLoan, 'شحن آجل', Color(0xFFE08F2D)),
      (_TypeFilter.debtCreated, 'إضافة دين', Color(0xFFDC2626)),
      (_TypeFilter.paymentSas, 'تسديد SAS', Color(0xFF0EA5E9)),
      (_TypeFilter.paymentCustom, 'تسديد أخرى', Color(0xFF8B5CF6)),
      (_TypeFilter.withdraw, 'سحب', Color(0xFFCD8B00)),
      (_TypeFilter.points, 'نقاط', Color(0xFFC084FC)),
    ];
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: Sp.lg),
        children: [
          for (final (k, label, color) in filters) ...[
            Center(
              child: _chip(
                active: _typeFilter == k,
                label: label,
                color: color,
                onTap: () => setState(() => _typeFilter = k),
              ),
            ),
            const SizedBox(width: 6),
          ],
        ],
      ),
    );
  }

  Widget _chip({
    required bool active,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: active ? color.withValues(alpha: 0.12) : AppColors.surfaceInput,
      borderRadius: BorderRadius.circular(R.pill),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Text(
            label,
            style: AppType.button(color: active ? color : AppColors.textMid)
                .copyWith(fontSize: 12, height: 1.2),
          ),
        ),
      ),
    );
  }

  // ─── Date range bar ────────────────────────

  Widget _dateRangeBar() {
    final hasRange = _dateFrom != null || _dateTo != null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Sp.lg, 2, Sp.lg, 6),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _pickDateRange,
              icon: Icon(LucideIcons.calendar,
                  size: 14, color: AppColors.textMid),
              label: Text(
                hasRange
                    ? '${_fmtDateShort(_dateFrom!)} → ${_fmtDateShort(_dateTo!)}'
                    : 'كل الفترات',
                style: AppType.button(color: AppColors.textHi)
                    .copyWith(fontSize: 12),
              ),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: AppColors.border),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 34),
              ),
            ),
          ),
          if (hasRange) ...[
            const SizedBox(width: 6),
            IconButton(
              tooltip: 'مسح',
              onPressed: _clearDateRange,
              icon: Icon(LucideIcons.x, size: 16, color: AppColors.textMid),
              style: IconButton.styleFrom(
                backgroundColor: AppColors.surfaceInput,
                minimumSize: const Size(34, 34),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ─── Empty state ───────────────────────────

  Widget _empty() {
    final hasAnyFilter = _managerFilter.isNotEmpty ||
        _typeFilter != _TypeFilter.all ||
        _dateFrom != null;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Sp.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.receipt, size: 56, color: AppColors.textLow),
            const SizedBox(height: 12),
            Text(
              hasAnyFilter
                  ? 'لا توجد حركات للفلاتر المحدّدة'
                  : 'لا توجد حركات على المدراء',
              style: AppType.subtitle(color: AppColors.textMid),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  // ─── Event tile (متّسق مع ReportLogTile) ─────

  Widget _eventTile(_MgrEvent e) {
    final meta = e.meta;
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(R.md),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _openEvent(e),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(R.md),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Icon square (نفس تصميم ReportLogTile)
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: meta.color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(R.sm),
                ),
                child: Icon(meta.icon, color: meta.color, size: 16),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Row 1: type badge + amount
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: meta.color.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            meta.label,
                            style: TextStyle(
                              color: meta.color,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const Spacer(),
                        if (e.amount != 0)
                          Text(
                            '${meta.debit ? '-' : '+'}${formatIQD(e.amount.abs().round())} د.ع',
                            style: TextStyle(
                              color: meta.debit
                                  ? AppColors.error
                                  : const Color(0xFF14B8A6),
                              fontSize: 12,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                      ],
                    ),
                    // Row 2: الى من (manager) — أخضر برند بارز
                    const SizedBox(height: 4),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Icon(LucideIcons.userCog,
                            size: 11,
                            color: AppColors.isDark
                                ? AppColors.brandLight
                                : AppColors.brand),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            e.manager.fullName.isEmpty
                                ? e.manager.username
                                : e.manager.fullName,
                            style: TextStyle(
                              color: AppColors.isDark
                                  ? AppColors.brandLight
                                  : AppColors.brand,
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              height: 1.15,
                              letterSpacing: -0.1,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (e.manager.fullName.isNotEmpty &&
                            e.manager.username.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              e.manager.username,
                              style: AppType.muted().copyWith(
                                fontSize: 10.5,
                                height: 1.2,
                                color: AppColors.textLow,
                                fontWeight: FontWeight.w500,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ],
                    ),
                    // Row 3: note (لو موجود)
                    if ((e.movement.note ?? '').trim().isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        e.movement.note!.trim(),
                        style: AppType.muted(color: AppColors.textMid)
                            .copyWith(fontSize: 11.5, height: 1.3),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    // Row 4: time + source
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Icon(LucideIcons.clock,
                            size: 10, color: AppColors.textLow),
                        const SizedBox(width: 3),
                        Text(
                          _fmtDateTime(e.date),
                          style: AppType.muted()
                              .copyWith(fontSize: 10, height: 1.2),
                        ),
                        if (e.movement.source != null) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceInput,
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: Text(
                              e.movement.source == MovementSource.sas4
                                  ? 'الساس'
                                  : 'يدوي',
                              style: AppType.muted().copyWith(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── helpers ───────────────────────────────

  String _fmtDate(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)}';
  }

  String _fmtDateShort(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}/${two(d.month)}/${two(d.day)}';
  }

  String _fmtDateTime(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
  }
}
