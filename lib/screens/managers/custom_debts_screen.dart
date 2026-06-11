import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../api/manager_debts_api.dart';
import '../../api/managers_api.dart';
import '../../core/util/format.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import 'sheets/add_custom_debt_sheet.dart';
import 'sheets/pay_custom_debt_sheet.dart';

/// شاشة "ديون أخرى" لمدير فرعي محدد. مطابق v1
/// manager_debts_provider + manager_movements_screen. تعرض:
///   • ملخص: إجمالي / المسدّد / المتبقي
///   • قائمة كل دين مفتوح/مغلق
///   • زر إضافة دين (FAB)
///   • نقر على الدين → sheet تسديد جزئي + قائمة الدفعات السابقة
class ManagerCustomDebtsScreen extends StatefulWidget {
  const ManagerCustomDebtsScreen({super.key, required this.manager});
  final Manager manager;

  @override
  State<ManagerCustomDebtsScreen> createState() =>
      _ManagerCustomDebtsScreenState();
}

class _ManagerCustomDebtsScreenState extends State<ManagerCustomDebtsScreen> {
  List<ManagerDebt> _debts = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final debts =
        await ManagerDebtsApi.list(debtorAdminId: widget.manager.id);
    if (!mounted) return;
    setState(() {
      _debts = debts;
      _loading = false;
    });
  }

  num get _totalOwed => _debts.fold<num>(0, (acc, d) => acc + d.amount);
  num get _totalPaid => _debts.fold<num>(0, (acc, d) => acc + d.paidAmount);
  num get _remaining {
    final r = _totalOwed - _totalPaid;
    return r < 0 ? 0 : r;
  }

  Future<void> _openAdd() async {
    final added = await showAddCustomDebtSheet(context, widget.manager);
    if (added == true) _load();
  }

  Future<void> _openDebt(ManagerDebt d) async {
    final changed = await showPayCustomDebtSheet(context, widget.manager, d);
    if (changed == true) _load();
  }

  Future<void> _confirmDelete(ManagerDebt d) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('حذف الدين'),
        content: Text(
          'حذف دين ${formatIQD(d.amount)} د.ع؟ هذا الإجراء لا يمكن التراجع عنه.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('إلغاء')),
          FilledButton(
            style:
                FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final r = await ManagerDebtsApi.delete(d.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(r.ok ? 'تم الحذف' : (r.message ?? 'تعذّر الحذف')),
        backgroundColor: r.ok ? AppColors.brand : AppColors.error,
        behavior: SnackBarBehavior.floating,
      ),
    );
    if (r.ok) _load();
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    const accent = Color(0xFF0EA5E9);
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          'ديون ${widget.manager.username}',
          style: AppType.title(color: AppColors.textHi)
              .copyWith(fontSize: 16),
        ),
        iconTheme: IconThemeData(color: AppColors.textHi),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: accent,
        foregroundColor: Colors.white,
        onPressed: _openAdd,
        icon: const Icon(LucideIcons.plus, size: 16),
        label: const Text('دين جديد'),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          color: accent,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
                Sp.lg, Sp.md, Sp.lg, Sp.huge + Sp.huge),
            children: [
              _summaryCard(accent),
              const SizedBox(height: Sp.md),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_debts.isEmpty)
                _empty()
              else
                Column(
                  children: [
                    for (final d in _debts) ...[
                      _DebtTile(
                        debt: d,
                        onTap: () => _openDebt(d),
                        onDelete: () => _confirmDelete(d),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _summaryCard(Color accent) {
    return Container(
      padding: const EdgeInsets.all(Sp.md),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            accent.withValues(alpha: 0.18),
            accent.withValues(alpha: 0.05),
          ],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: BorderRadius.circular(R.lg),
        border: Border.all(color: accent.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(R.md),
                ),
                child: Icon(LucideIcons.receipt, color: accent, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'الدين المتبقي',
                      style: AppType.muted().copyWith(fontSize: 11),
                    ),
                    Text(
                      '${formatIQD(_remaining)} د.ع',
                      style: AppType.title(color: AppColors.textHi)
                          .copyWith(
                              fontSize: 22, letterSpacing: -0.5),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: Sp.md),
          Row(
            children: [
              Expanded(child: _miniStat('الإجمالي', _totalOwed, AppColors.textHi)),
              const SizedBox(width: 8),
              Expanded(child: _miniStat('المسدّد', _totalPaid, AppColors.brand)),
              const SizedBox(width: 8),
              Expanded(child: _miniStat('عدد الديون', _debts.length, accent, isCount: true)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _miniStat(String label, num value, Color color, {bool isCount = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.sm),
        border:
            Border.all(color: AppColors.border.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppType.muted().copyWith(fontSize: 10)),
          const SizedBox(height: 2),
          Text(
            isCount ? '${value.toInt()}' : '${formatIQD(value)} د.ع',
            style: AppType.label(color: color)
                .copyWith(fontSize: 12, fontWeight: FontWeight.w800),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _empty() {
    return Container(
      padding: const EdgeInsets.all(Sp.huge),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.lg),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Icon(LucideIcons.receiptText,
              size: 36, color: AppColors.textLow),
          const SizedBox(height: 10),
          Text(
            'لا توجد ديون مفتوحة',
            style: AppType.muted(color: AppColors.textHi)
                .copyWith(fontSize: 13),
          ),
          const SizedBox(height: 4),
          Text(
            'اضغط "دين جديد" لإضافة دين',
            style: AppType.muted().copyWith(fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _DebtTile extends StatelessWidget {
  const _DebtTile({
    required this.debt,
    required this.onTap,
    required this.onDelete,
  });
  final ManagerDebt debt;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final closed = debt.isClosed;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(R.lg),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(R.lg),
            border: Border.all(
              color: closed
                  ? AppColors.brand.withValues(alpha: 0.3)
                  : AppColors.border,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: (closed
                              ? AppColors.brand
                              : const Color(0xFF0EA5E9))
                          .withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(R.md),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      closed
                          ? LucideIcons.circleCheck
                          : LucideIcons.receipt,
                      size: 16,
                      color: closed
                          ? AppColors.brand
                          : const Color(0xFF0EA5E9),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${formatIQD(debt.amount)} د.ع',
                          style: AppType.title(color: AppColors.textHi)
                              .copyWith(fontSize: 14),
                        ),
                        Text(
                          _fmtIsoDate(debt.debtDate),
                          style: AppType.muted().copyWith(fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  if (closed)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.brand.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(R.sm),
                        border: Border.all(
                            color: AppColors.brand.withValues(alpha: 0.3)),
                      ),
                      child: const Text(
                        'مسدَّد',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: AppColors.brand,
                        ),
                      ),
                    )
                  else
                    Text(
                      'تبقى ${formatIQD(debt.remainingAmount)}',
                      style: AppType.label(color: AppColors.error)
                          .copyWith(
                              fontSize: 12, fontWeight: FontWeight.w800),
                    ),
                  const SizedBox(width: 6),
                  InkResponse(
                    onTap: onDelete,
                    radius: 18,
                    child: Container(
                      width: 30,
                      height: 30,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppColors.error.withValues(alpha: 0.08),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(LucideIcons.trash2,
                          size: 13, color: AppColors.error),
                    ),
                  ),
                ],
              ),
              if ((debt.note ?? '').trim().isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  debt.note!.trim(),
                  style: AppType.muted(color: AppColors.textMid)
                      .copyWith(fontSize: 11, height: 1.4),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// "yyyy-MM-dd" — used in the debt list to render `debt_date` next
/// to each row. ManagerDebt now exposes a DateTime (non-null), so we
/// no longer parse strings here.
String _fmtIsoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
