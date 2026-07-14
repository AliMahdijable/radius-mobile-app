import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../api/manager_debts_api.dart';
import '../../api/managers_api.dart';
import '../../core/util/format.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import '../managers/movements_screen.dart';
import '../managers/sheets/pay_custom_debt_sheet.dart';
import '../managers/sheets/pay_debt_sheet.dart';

/// تقرير ديون المدراء لكل المدراء الفرعيين — يفتح من:
///   قوائم أخرى → التقارير → ديون المدراء
///
/// يوحّد مصدرَي الديون:
///   • SAS: Manager.totalDebt (من إيداعات آجلة/سحوبات — external SAS4)
///   • أخرى: manager_debts table المحلي (ديون تُضاف يدوياً بالـsheet)
///
/// فلاتر: مدير (بحث نصّي) + مصدر (all/sas/custom) + حالة + تاريخ (مطبّق
/// على custom فقط لأن SAS ما عندها date field).
class AllManagersDebtsScreen extends StatefulWidget {
  const AllManagersDebtsScreen({super.key});

  @override
  State<AllManagersDebtsScreen> createState() => _AllManagersDebtsScreenState();
}

enum _StatusFilter { all, open, partial, paid }
enum _SourceFilter { all, sas, custom }

/// row مُوحَّد يجمع SAS و custom debts في نفس القائمة.
class _DebtRow {
  const _DebtRow.sas(this.manager)
      : custom = null,
        source = _SourceFilter.sas;
  const _DebtRow.custom(this.manager, this.custom)
      : source = _SourceFilter.custom;

  final Manager manager;
  final ManagerDebt? custom;
  final _SourceFilter source;

  bool get isSas => source == _SourceFilter.sas;
  bool get isCustom => source == _SourceFilter.custom;

  double get amount =>
      isSas ? manager.totalDebt : (custom?.amount ?? 0);
  double get paid =>
      isSas ? 0 : (custom?.paidAmount ?? 0); // SAS ما نتتبّع مسدَّد فيه هنا
  double get remaining =>
      isSas ? manager.totalDebt : (custom?.remainingAmount ?? 0);
  DateTime? get date => custom?.debtDate;
  ManagerDebtStatus get status => custom?.status ??
      (manager.totalDebt > 0 ? ManagerDebtStatus.open : ManagerDebtStatus.paid);
}

class _AllManagersDebtsScreenState extends State<AllManagersDebtsScreen> {
  List<Manager> _managers = const [];
  List<ManagerDebt> _customDebts = const [];
  ManagerDebtsSummary? _summary;
  bool _loading = true;

  _StatusFilter _statusFilter = _StatusFilter.all;
  _SourceFilter _sourceFilter = _SourceFilter.all;
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
    // 3 استدعاءات بالتوازي.
    final results = await Future.wait([
      ManagersApi.listFull(count: 500),
      ManagerDebtsApi.list(
        from: _dateFrom == null ? null : _fmtDate(_dateFrom!),
        to: _dateTo == null ? null : _fmtDate(_dateTo!),
      ),
      ManagerDebtsApi.summary(
        from: _dateFrom == null ? null : _fmtDate(_dateFrom!),
        to: _dateTo == null ? null : _fmtDate(_dateTo!),
      ),
    ]);
    if (!mounted) return;
    setState(() {
      _managers = (results[0] as ({List<Manager> rows, int total})).rows;
      _customDebts = results[1] as List<ManagerDebt>;
      _summary = results[2] as ManagerDebtsSummary?;
      _loading = false;
    });
  }

  // ─── unified rows ──────────────────────────

  List<_DebtRow> get _allRows {
    final out = <_DebtRow>[];
    // SAS: كل مدير عنده totalDebt > 0 يظهر كصف SAS.
    for (final m in _managers) {
      if (m.totalDebt > 0) out.add(_DebtRow.sas(m));
    }
    // Custom: كل دين من الجدول المحلي — نبني _DebtRow معه Manager الأصل
    // (لعرض اسم المدير)؛ لو المدير مش موجود بالقائمة، نبني stub.
    final byId = {for (final m in _managers) m.id: m};
    for (final d in _customDebts) {
      final mgr = byId[d.debtorAdminId] ??
          Manager(
            id: d.debtorAdminId,
            username: d.debtorAdminUsername ?? '#${d.debtorAdminId}',
            mobile: d.debtorAdminPhone ?? '',
          );
      out.add(_DebtRow.custom(mgr, d));
    }
    // ترتيب: SAS أعلى، ثم custom الأحدث فالأقدم.
    out.sort((a, b) {
      if (a.isSas != b.isSas) return a.isSas ? -1 : 1;
      final ad = a.date ?? DateTime(1970);
      final bd = b.date ?? DateTime(1970);
      return bd.compareTo(ad);
    });
    return out;
  }

  List<_DebtRow> get _visible {
    final q = _managerFilter.trim().toLowerCase();
    return _allRows.where((r) {
      // Source filter
      if (_sourceFilter != _SourceFilter.all && r.source != _sourceFilter) {
        return false;
      }
      // Status filter
      if (_statusFilter != _StatusFilter.all) {
        final want = _statusFilter == _StatusFilter.open
            ? ManagerDebtStatus.open
            : _statusFilter == _StatusFilter.partial
                ? ManagerDebtStatus.partial
                : ManagerDebtStatus.paid;
        if (r.status != want) return false;
      }
      // Manager search
      if (q.isNotEmpty) {
        final u = r.manager.username.toLowerCase();
        final n = r.manager.fullName.toLowerCase();
        if (!u.contains(q) && !n.contains(q)) return false;
      }
      return true;
    }).toList();
  }

  // ─── totals (SAS + Custom) ─────────────────

  double get _totalSasDebt =>
      _managers.fold<double>(0, (acc, m) => acc + m.totalDebt);
  double get _totalCustomAmount => _summary?.totals.totalAmount ?? 0;
  double get _totalCustomPaid => _summary?.totals.totalPaid ?? 0;
  double get _totalCustomRemaining => _summary?.totals.totalRemaining ?? 0;
  double get _grandRemaining => _totalSasDebt + _totalCustomRemaining;

  int get _debtorsCount {
    final ids = <int>{};
    for (final m in _managers) {
      if (m.totalDebt > 0) ids.add(m.id);
    }
    for (final d in _customDebts) {
      if (d.remainingAmount > 0) ids.add(d.debtorAdminId);
    }
    return ids.length;
  }

  // ─── row actions ───────────────────────────

  Future<void> _openRow(_DebtRow row) async {
    if (row.isSas) {
      final changed = await showPayDebtSheet(context, row.manager);
      if (changed == true) _load();
    } else {
      final changed =
          await showPayCustomDebtSheet(context, row.manager, row.custom!);
      if (changed == true) _load();
    }
  }

  Future<void> _openMovements(_DebtRow row) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ManagerMovementsScreen(manager: row.manager),
      ),
    );
    if (mounted) _load();
  }

  // ─── date picker ───────────────────────────

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
                  SliverToBoxAdapter(child: _sourceFilters()),
                  SliverToBoxAdapter(child: _statusFilters()),
                  SliverToBoxAdapter(child: _dateRangeBar()),
                  if (_visible.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: _empty(),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(
                          Sp.lg, 4, Sp.lg, Sp.huge),
                      sliver: SliverList.separated(
                        itemCount: _visible.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (_, i) => _debtCard(_visible[i]),
                      ),
                    ),
                ],
              ),
            ),
    );
  }

  // ─── Summary card ──────────────────────────

  Widget _summaryCard() {
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
              Text(
                '$_debtorsCount مدين',
                style: AppType.muted().copyWith(fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // 3 كارتات: دين SAS، دين أخرى (متبقّي)، الإجمالي.
          Row(
            children: [
              _statTile(
                label: 'دين SAS',
                value: _totalSasDebt,
                color: const Color(0xFF0EA5E9),
              ),
              const SizedBox(width: 6),
              _statTile(
                label: 'ديون أخرى',
                value: _totalCustomRemaining,
                color: const Color(0xFF8B5CF6),
              ),
              const SizedBox(width: 6),
              _statTile(
                label: 'الإجمالي',
                value: _grandRemaining,
                color: _grandRemaining > 0
                    ? AppColors.error
                    : const Color(0xFF14B8A6),
                emphasize: true,
              ),
            ],
          ),
          if (_totalCustomPaid > 0) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(LucideIcons.check,
                    size: 12, color: const Color(0xFF14B8A6)),
                const SizedBox(width: 4),
                Text(
                  'مسدَّد من ديون أخرى: ${formatIQD(_totalCustomPaid.round())} د.ع',
                  style: AppType.muted(color: const Color(0xFF14B8A6))
                      .copyWith(fontSize: 11),
                ),
              ],
            ),
          ],
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

  // ─── Source filters ────────────────────────

  Widget _sourceFilters() {
    const filters = <(_SourceFilter, String, Color)>[
      (_SourceFilter.all, 'كل المصادر', Color(0xFF64748B)),
      (_SourceFilter.sas, 'SAS', Color(0xFF0EA5E9)),
      (_SourceFilter.custom, 'ديون أخرى', Color(0xFF8B5CF6)),
    ];
    return SizedBox(
      height: 32,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: Sp.lg, vertical: 4),
        children: [
          for (final (k, label, color) in filters) ...[
            _chip(
              active: _sourceFilter == k,
              label: label,
              color: color,
              onTap: () => setState(() => _sourceFilter = k),
            ),
            const SizedBox(width: 6),
          ],
        ],
      ),
    );
  }

  // ─── Status filters ────────────────────────

  Widget _statusFilters() {
    const filters = <(_StatusFilter, String, Color)>[
      (_StatusFilter.all, 'كل الحالات', Color(0xFF3B82F6)),
      (_StatusFilter.open, 'مفتوح', Color(0xFFDC2626)),
      (_StatusFilter.partial, 'جزئي', Color(0xFFE08F2D)),
      (_StatusFilter.paid, 'مسدّد', Color(0xFF14B8A6)),
    ];
    return SizedBox(
      height: 32,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: Sp.lg, vertical: 4),
        children: [
          for (final (k, label, color) in filters) ...[
            _chip(
              active: _statusFilter == k,
              label: label,
              color: color,
              onTap: () => setState(() => _statusFilter = k),
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
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Text(
            label,
            style: AppType.button(color: active ? color : AppColors.textMid)
                .copyWith(fontSize: 12),
          ),
        ),
      ),
    );
  }

  // ─── Date range bar ────────────────────────

  Widget _dateRangeBar() {
    final hasRange = _dateFrom != null || _dateTo != null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Sp.lg, 4, Sp.lg, 6),
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
        _statusFilter != _StatusFilter.all ||
        _sourceFilter != _SourceFilter.all ||
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
                  ? 'لا توجد نتائج للفلاتر المحدّدة'
                  : 'لا توجد ديون على المدراء',
              style: AppType.subtitle(color: AppColors.textMid),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              'الديون تُضاف من: قوائم أخرى → المدراء → الإجراءات\n(SAS: شحن آجل / ديون أخرى)',
              textAlign: TextAlign.center,
              style: AppType.muted().copyWith(fontSize: 11, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Row card ──────────────────────────────

  Widget _debtCard(_DebtRow row) {
    final (color, statusText) = _statusVisual(row.status);
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(R.md),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _openRow(row),
        child: Container(
          padding: const EdgeInsets.all(Sp.md),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(R.md),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(LucideIcons.userCog, size: 14, color: color),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                row.manager.username,
                                style: AppType.title(color: AppColors.textHi)
                                    .copyWith(fontSize: 13),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 6),
                            _sourceBadge(row.source),
                          ],
                        ),
                        const SizedBox(height: 1),
                        Text(
                          row.date != null
                              ? _fmtDateShort(row.date!)
                              : (row.isSas ? 'دين SAS مستمر' : '—'),
                          style: AppType.muted().copyWith(fontSize: 10.5),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(R.sm),
                      border: Border.all(
                          color: color.withValues(alpha: 0.25), width: 0.5),
                    ),
                    child: Text(statusText,
                        style:
                            AppType.button(color: color).copyWith(fontSize: 10)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              row.isSas
                  ? _sasAmountRow(row)
                  : _customAmountRow(row),
              if (row.isCustom && (row.custom?.note ?? '').isNotEmpty) ...[
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceInput,
                    borderRadius: BorderRadius.circular(R.sm),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(LucideIcons.stickyNote,
                          size: 11, color: AppColors.textLow),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          row.custom!.note!,
                          style: AppType.muted(color: AppColors.textMid)
                              .copyWith(fontSize: 11),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 6),
              Row(
                children: [
                  TextButton.icon(
                    onPressed: () => _openMovements(row),
                    icon: Icon(LucideIcons.activity,
                        size: 12, color: AppColors.brand),
                    label: Text(
                      'الحركات',
                      style: AppType.button(color: AppColors.brand)
                          .copyWith(fontSize: 11),
                    ),
                    style: TextButton.styleFrom(
                      minimumSize: const Size(0, 28),
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                    ),
                  ),
                  const Spacer(),
                  Icon(LucideIcons.chevronLeft,
                      size: 14, color: AppColors.textLow),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sourceBadge(_SourceFilter s) {
    final color = s == _SourceFilter.sas
        ? const Color(0xFF0EA5E9)
        : const Color(0xFF8B5CF6);
    final label = s == _SourceFilter.sas ? 'SAS' : 'أخرى';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(R.sm),
        border: Border.all(color: color.withValues(alpha: 0.25), width: 0.5),
      ),
      child: Text(label,
          style: AppType.button(color: color)
              .copyWith(fontSize: 9.5, fontWeight: FontWeight.w800)),
    );
  }

  Widget _sasAmountRow(_DebtRow row) {
    return Row(
      children: [
        Expanded(
          child: _amountBlock(
            label: 'مبلغ الدين (SAS)',
            amount: row.remaining,
            color: AppColors.error,
            bold: true,
          ),
        ),
      ],
    );
  }

  Widget _customAmountRow(_DebtRow row) {
    return Row(
      children: [
        Expanded(
          child: _amountBlock(
            label: 'الأصل',
            amount: row.amount,
            color: AppColors.textMid,
          ),
        ),
        Container(width: 1, height: 22, color: AppColors.border),
        const SizedBox(width: 8),
        Expanded(
          child: _amountBlock(
            label: 'مسدَّد',
            amount: row.paid,
            color: const Color(0xFF14B8A6),
          ),
        ),
        const SizedBox(width: 8),
        Container(width: 1, height: 22, color: AppColors.border),
        const SizedBox(width: 8),
        Expanded(
          child: _amountBlock(
            label: 'متبقٍ',
            amount: row.remaining,
            color: row.remaining > 0
                ? AppColors.error
                : const Color(0xFF14B8A6),
            bold: true,
          ),
        ),
      ],
    );
  }

  Widget _amountBlock({
    required String label,
    required double amount,
    required Color color,
    bool bold = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: AppType.muted().copyWith(fontSize: 10)),
        const SizedBox(height: 1),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: AlignmentDirectional.centerStart,
          child: Text(
            formatIQD(amount.round()),
            style: AppType.title(color: color).copyWith(
              fontSize: bold ? 13.5 : 12.5,
              fontWeight: bold ? FontWeight.w800 : FontWeight.w700,
              height: 1.1,
            ),
          ),
        ),
      ],
    );
  }

  // ─── helpers ───────────────────────────────

  (Color, String) _statusVisual(ManagerDebtStatus s) {
    switch (s) {
      case ManagerDebtStatus.paid:
        return (const Color(0xFF14B8A6), 'مسدّد');
      case ManagerDebtStatus.partial:
        return (const Color(0xFFE08F2D), 'جزئي');
      case ManagerDebtStatus.open:
        return (AppColors.error, 'مفتوح');
    }
  }

  String _fmtDate(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)}';
  }

  String _fmtDateShort(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}/${two(d.month)}/${two(d.day)}';
  }
}
