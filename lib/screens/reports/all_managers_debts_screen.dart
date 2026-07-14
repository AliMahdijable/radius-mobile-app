import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../api/manager_debts_api.dart';
import '../../api/managers_api.dart';
import '../../core/util/format.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import '../managers/sheets/pay_custom_debt_sheet.dart';

/// تقرير ديون المدراء لكل المدراء الفرعيين — يفتح من:
///   قوائم أخرى → التقارير → ديون المدراء
///
/// يعرض:
///   • ملخّص إجمالي (المستحق / المسدّد / المتبقّي + عدد المدينين)
///   • فلتر حالة (الكل/مفتوح/جزئي/مسدّد)
///   • قائمة مسطّحة لكل الديون مع اسم المدين + المبلغ + المتبقّي
///   • pull-to-refresh
///   • نقر على الدين → sheet تسديد + سجل الدفعات (تُعيد استعمال
///     showPayCustomDebtSheet الموجود)
class AllManagersDebtsScreen extends StatefulWidget {
  const AllManagersDebtsScreen({super.key});

  @override
  State<AllManagersDebtsScreen> createState() => _AllManagersDebtsScreenState();
}

enum _StatusFilter { all, open, partial, paid }

class _AllManagersDebtsScreenState extends State<AllManagersDebtsScreen> {
  List<ManagerDebt> _debts = const [];
  ManagerDebtsSummary? _summary;
  bool _loading = true;
  _StatusFilter _filter = _StatusFilter.all;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    // نجلب الاثنين بالتوازي — summary للـstats، list لعرض التفاصيل.
    final results = await Future.wait([
      ManagerDebtsApi.list(),
      ManagerDebtsApi.summary(),
    ]);
    if (!mounted) return;
    setState(() {
      _debts = results[0] as List<ManagerDebt>;
      _summary = results[1] as ManagerDebtsSummary?;
      _loading = false;
    });
  }

  List<ManagerDebt> get _visible {
    switch (_filter) {
      case _StatusFilter.all:
        return _debts;
      case _StatusFilter.open:
        return _debts.where((d) => d.status == ManagerDebtStatus.open).toList();
      case _StatusFilter.partial:
        return _debts
            .where((d) => d.status == ManagerDebtStatus.partial)
            .toList();
      case _StatusFilter.paid:
        return _debts.where((d) => d.status == ManagerDebtStatus.paid).toList();
    }
  }

  Future<void> _openDebt(ManagerDebt d) async {
    // نبني Manager stub من الحقول المتوفّرة في الـdebt — يكفي pay_custom_debt
    // sheet (يستعمل username للعرض + id للـAPI).
    final stub = Manager(
      id: d.debtorAdminId,
      username: d.debtorAdminUsername ?? '#${d.debtorAdminId}',
      mobile: d.debtorAdminPhone ?? '',
    );
    final changed = await showPayCustomDebtSheet(context, stub, d);
    if (changed == true) _load();
  }

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
                  SliverToBoxAdapter(child: _statusFilters()),
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

  // ─── Summary card ───────────────────────

  Widget _summaryCard() {
    final s = _summary?.totals;
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
              if (s != null)
                Text(
                  '${s.debtsCount} دين / ${s.debtorsCount} مدين',
                  style: AppType.muted().copyWith(fontSize: 11),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _statTile(
                label: 'المستحق',
                value: s?.totalAmount ?? 0,
                color: AppColors.textHi,
              ),
              const SizedBox(width: 6),
              _statTile(
                label: 'المسدّد',
                value: s?.totalPaid ?? 0,
                color: const Color(0xFF14B8A6),
              ),
              const SizedBox(width: 6),
              _statTile(
                label: 'المتبقّي',
                value: s?.totalRemaining ?? 0,
                color: (s?.totalRemaining ?? 0) > 0
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
            Text(label,
                style: AppType.muted().copyWith(fontSize: 10.5)),
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

  // ─── Status filters ──────────────────────

  Widget _statusFilters() {
    const filters = <(_StatusFilter, String, Color)>[
      (_StatusFilter.all, 'الكل', Color(0xFF3B82F6)),
      (_StatusFilter.open, 'مفتوح', Color(0xFFDC2626)),
      (_StatusFilter.partial, 'جزئي', Color(0xFFE08F2D)),
      (_StatusFilter.paid, 'مسدّد', Color(0xFF14B8A6)),
    ];
    return SizedBox(
      height: 34,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: Sp.lg, vertical: 4),
        children: [
          for (final (k, label, color) in filters) ...[
            _filterChip(k, label, color),
            const SizedBox(width: 6),
          ],
        ],
      ),
    );
  }

  Widget _filterChip(_StatusFilter k, String label, Color color) {
    final active = _filter == k;
    return Material(
      color: active
          ? color.withValues(alpha: 0.12)
          : AppColors.surfaceInput,
      borderRadius: BorderRadius.circular(R.pill),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => setState(() => _filter = k),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Text(
            label,
            style: AppType.button(
              color: active ? color : AppColors.textMid,
            ).copyWith(fontSize: 12),
          ),
        ),
      ),
    );
  }

  // ─── Empty state ─────────────────────────

  Widget _empty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.receipt, size: 56, color: AppColors.textLow),
          const SizedBox(height: 12),
          Text(
            _filter == _StatusFilter.all
                ? 'لا توجد ديون على المدراء'
                : 'لا توجد ديون بهذا الفلتر',
            style: AppType.subtitle(color: AppColors.textMid),
          ),
          const SizedBox(height: 4),
          Text(
            'الديون تُضاف من: قوائم أخرى → المدراء → الإجراءات → ديون أخرى',
            textAlign: TextAlign.center,
            style: AppType.muted().copyWith(fontSize: 11, height: 1.5),
          ),
        ],
      ),
    );
  }

  // ─── Debt card ───────────────────────────

  Widget _debtCard(ManagerDebt d) {
    final (color, statusText) = _statusVisual(d.status);
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(R.md),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _openDebt(d),
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
                    child: Icon(LucideIcons.userCog,
                        size: 14, color: color),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          d.debtorAdminUsername ?? '#${d.debtorAdminId}',
                          style: AppType.title(color: AppColors.textHi)
                              .copyWith(fontSize: 13),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 1),
                        Text(
                          _formatDate(d.debtDate),
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
                          color: color.withValues(alpha: 0.25),
                          width: 0.5),
                    ),
                    child: Text(statusText,
                        style: AppType.button(color: color)
                            .copyWith(fontSize: 10)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _amountRow(
                      label: 'الأصل',
                      amount: d.amount,
                      color: AppColors.textMid,
                    ),
                  ),
                  Container(
                      width: 1, height: 22, color: AppColors.border),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _amountRow(
                      label: 'مسدَّد',
                      amount: d.paidAmount,
                      color: const Color(0xFF14B8A6),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                      width: 1, height: 22, color: AppColors.border),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _amountRow(
                      label: 'متبقٍ',
                      amount: d.remainingAmount,
                      color: d.remainingAmount > 0
                          ? AppColors.error
                          : const Color(0xFF14B8A6),
                      bold: true,
                    ),
                  ),
                ],
              ),
              if ((d.note ?? '').isNotEmpty) ...[
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
                          d.note!,
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
            ],
          ),
        ),
      ),
    );
  }

  Widget _amountRow({
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

  // ─── helpers ─────────────────────────────

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

  String _formatDate(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}/${two(d.month)}/${two(d.day)}';
  }
}
