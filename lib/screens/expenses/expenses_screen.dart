import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../api/expenses_api.dart';
import '../../core/util/format.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import 'sheets/add_expense_sheet.dart';
import 'sheets/edit_expense_sheet.dart';

/// مديول "الصرفيات" — قائمة الصرفيات + فلتر نطاق التواريخ + كرت
/// إجمالي + add/edit/delete. منقول لـv2 من ضمن "قوائم أخرى".
/// مصمم بنفس قواعد بقية شاشات v2: AppBar نظيف، كروت ملوّنة، أيقونات
/// Lucide، تفاعل ناعم. الـbackend جاهز:
///   GET    /api/admin/expenses?from=&to=
///   PUT    /api/admin/expenses/:id
///   DELETE /api/admin/expenses/:id
class ExpensesScreen extends StatefulWidget {
  const ExpensesScreen({super.key});

  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends State<ExpensesScreen> {
  List<ExpenseRow> _rows = const [];
  num _total = 0;
  bool _loading = true;
  // النطاق الافتراضي: أول الشهر إلى اليوم (مطابق الويب).
  late DateTime _from;
  late DateTime _to;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _from = DateTime(now.year, now.month, 1);
    _to = DateTime(now.year, now.month, now.day);
    _load();
  }

  String _fmtDate(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)}';
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final r = await ExpensesApi.list(
      from: _fmtDate(_from),
      to: _fmtDate(_to),
    );
    if (!mounted) return;
    setState(() {
      _rows = r.rows;
      _total = r.total;
      _loading = false;
    });
  }

  Future<void> _pickRange() async {
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDateRange: DateTimeRange(start: _from, end: _to),
      locale: const Locale('ar'),
      helpText: 'exp.pick_range'.tr(),
      saveText: 'common.save'.tr(),
      cancelText: 'common.cancel'.tr(),
    );
    if (r == null) return;
    setState(() {
      _from = r.start;
      _to = r.end;
    });
    _load();
  }

  Future<void> _openAdd() async {
    final added = await showAddExpenseSheet(context);
    if (added == true) _load();
  }

  Future<void> _openEdit(ExpenseRow row) async {
    final changed = await showEditExpenseSheet(context, row);
    if (changed == true) _load();
  }

  Future<void> _confirmDelete(ExpenseRow row) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('exp.delete_title'.tr()),
        content: Text(
          'exp.delete_body'.tr(namedArgs: {'amt': '${formatIQD(row.amount)} ${'common.currency'.tr()}'}),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('common.cancel'.tr()),
          ),
          FilledButton(
            style:
                FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('common.delete'.tr()),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final result = await ExpensesApi.delete(row.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result.ok
            ? 'exp.deleted'.tr()
            : (result.message ?? 'subscribers.delete_failed'.tr())),
        backgroundColor:
            result.ok ? AppColors.brand : AppColors.error,
        behavior: SnackBarBehavior.floating,
      ),
    );
    if (result.ok) _load();
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    const accent = Color(0xFF8B5CF6);
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          'more.expenses'.tr(),
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
        label: Text('common.add'.tr()),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          color: accent,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
                Sp.lg, Sp.md, Sp.lg, Sp.huge + Sp.huge),
            children: [
              _headerCard(accent),
              const SizedBox(height: Sp.md),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_rows.isEmpty)
                _emptyState()
              else
                Column(
                  children: [
                    for (final row in _rows) ...[
                      _ExpenseTile(
                        row: row,
                        onEdit: () => _openEdit(row),
                        onDelete: () => _confirmDelete(row),
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

  Widget _headerCard(Color accent) {
    String two(int n) => n.toString().padLeft(2, '0');
    final rangeLabel =
        '${_from.year}/${two(_from.month)}/${two(_from.day)} → '
        '${_to.year}/${two(_to.month)}/${two(_to.day)}';
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
                child:
                    Icon(LucideIcons.receipt, color: accent, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'exp.total_expenses'.tr(),
                      style: AppType.muted().copyWith(fontSize: 11),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${formatIQD(_total)} د.ع',
                      style: AppType.title(color: AppColors.textHi)
                          .copyWith(
                              fontSize: 22, letterSpacing: -0.5),
                    ),
                  ],
                ),
              ),
              Text(
                '${_rows.length} عملية',
                style: AppType.label(color: accent)
                    .copyWith(fontSize: 12, fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: Sp.md),
          InkWell(
            onTap: _pickRange,
            borderRadius: BorderRadius.circular(R.md),
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(R.md),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  Icon(LucideIcons.calendar,
                      size: 14, color: AppColors.textMid),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      rangeLabel,
                      style:
                          AppType.label(color: AppColors.textHi).copyWith(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Icon(LucideIcons.chevronDown,
                      size: 14, color: AppColors.textMid),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyState() {
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
'exp.empty_range'.tr(),
            style: AppType.muted(color: AppColors.textHi)
                .copyWith(fontSize: 13),
          ),
          const SizedBox(height: 4),
          Text(
            'exp.empty_hint'.tr(),
            style: AppType.muted().copyWith(fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _ExpenseTile extends StatelessWidget {
  const _ExpenseTile({
    required this.row,
    required this.onEdit,
    required this.onDelete,
  });
  final ExpenseRow row;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onEdit,
        borderRadius: BorderRadius.circular(R.lg),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(R.lg),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(R.md),
                ),
                alignment: Alignment.center,
                child: const Icon(
                  LucideIcons.arrowDownToLine,
                  size: 16,
                  color: AppColors.error,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${formatIQD(row.amount)} د.ع',
                      style: AppType.title(color: AppColors.error)
                          .copyWith(fontSize: 16),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Icon(LucideIcons.calendar,
                            size: 11, color: AppColors.textLow),
                        const SizedBox(width: 3),
                        Text(
                          row.expenseDate,
                          style: AppType.muted().copyWith(fontSize: 11),
                        ),
                        if ((row.actingEmployeeUsername ?? '')
                            .isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Container(
                            width: 2,
                            height: 10,
                            color: AppColors.border,
                          ),
                          const SizedBox(width: 8),
                          const Icon(Icons.badge,
                              size: 11, color: Color(0xFF7C3AED)),
                          const SizedBox(width: 3),
                          Flexible(
                            child: Text(
                              row.actingEmployeeUsername!,
                              style: AppType.muted(
                                      color: const Color(0xFF7C3AED))
                                  .copyWith(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w700),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ],
                    ),
                    if ((row.note ?? '').trim().isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        row.note!.trim(),
                        style: AppType.muted(color: AppColors.textMid)
                            .copyWith(fontSize: 11, height: 1.4),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 4),
              InkResponse(
                onTap: onDelete,
                radius: 22,
                child: Container(
                  width: 32,
                  height: 32,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.08),
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: AppColors.error.withValues(alpha: 0.3)),
                  ),
                  child: const Icon(
                    LucideIcons.trash2,
                    size: 14,
                    color: AppColors.error,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
