import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' as intl;

import '../../core/utils/helpers.dart';
import '../../models/admin_expense.dart';
import '../../providers/expenses_provider.dart';

/// Admin's own expense ledger. The list is sorted newest first and the
/// header shows the period total — which is what the financial reports
/// subtract from revenue.
class ExpensesScreen extends ConsumerStatefulWidget {
  const ExpensesScreen({super.key});

  @override
  ConsumerState<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends ConsumerState<ExpensesScreen> {
  DateTime? _from;
  DateTime? _to;

  ExpensesRangeArgs get _args =>
      ExpensesRangeArgs(from: _from, to: _to);

  @override
  Widget build(BuildContext context) {
    final asyncPage = ref.watch(expensesProvider(_args));
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('الصرفيات')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(context),
        icon: const Icon(Icons.add),
        label: const Text('إضافة'),
      ),
      body: Column(
        children: [
          _FilterRow(
            from: _from,
            to: _to,
            onFromChanged: (d) => setState(() => _from = d),
            onToChanged: (d) => setState(() => _to = d),
            onClear: () => setState(() { _from = null; _to = null; }),
          ),
          _TotalBanner(asyncPage: asyncPage),
          Expanded(
            child: asyncPage.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('خطأ: $e')),
              data: (page) {
                if (page.expenses.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.inbox_outlined, size: 48, color: cs.onSurfaceVariant),
                        const SizedBox(height: 12),
                        const Text('لا توجد صرفيات'),
                      ],
                    ),
                  );
                }
                return RefreshIndicator(
                  onRefresh: () async => ref.invalidate(expensesProvider(_args)),
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 96),
                    itemCount: page.expenses.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 6),
                    itemBuilder: (_, i) => _ExpenseTile(
                      expense: page.expenses[i],
                      onEdit: () => _openForm(context, existing: page.expenses[i]),
                      onDelete: () => _confirmDelete(context, page.expenses[i]),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openForm(BuildContext context, {AdminExpense? existing}) async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => _ExpenseFormDialog(existing: existing),
    );
    if (changed == true) ref.invalidate(expensesProvider(_args));
  }

  Future<void> _confirmDelete(BuildContext context, AdminExpense e) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('حذف الصرفية'),
        content: Text(
          'سيحذف هذا السجل بقيمة ${AppHelpers.formatCompactMoney(e.amount)}. '
          'متأكد؟',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final deleted = await deleteExpense(ref, e.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(deleted ? 'تم الحذف' : 'تعذّر الحذف')),
    );
  }
}

class _TotalBanner extends StatelessWidget {
  final AsyncValue<AdminExpensesPage> asyncPage;
  const _TotalBanner({required this.asyncPage});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final total = asyncPage.asData?.value.total ?? 0;
    final count = asyncPage.asData?.value.expenses.length ?? 0;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.errorContainer.withValues(alpha: 0.30),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(Icons.account_balance_wallet, color: cs.error),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('إجمالي الصرفيات', style: TextStyle(fontSize: 12)),
                const SizedBox(height: 2),
                Text(
                  AppHelpers.formatCompactMoney(total),
                  style: TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w800, color: cs.error),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: cs.outlineVariant),
            ),
            child: Text('$count حركة', style: const TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }
}

class _FilterRow extends StatelessWidget {
  final DateTime? from;
  final DateTime? to;
  final ValueChanged<DateTime?> onFromChanged;
  final ValueChanged<DateTime?> onToChanged;
  final VoidCallback onClear;
  const _FilterRow({
    required this.from,
    required this.to,
    required this.onFromChanged,
    required this.onToChanged,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Row(
        children: [
          Expanded(child: _dateField(context, label: 'من', value: from, onChanged: onFromChanged)),
          const SizedBox(width: 6),
          Expanded(child: _dateField(context, label: 'إلى', value: to, onChanged: onToChanged)),
          IconButton(icon: const Icon(Icons.clear), onPressed: onClear),
        ],
      ),
    );
  }

  Widget _dateField(BuildContext context,
      {required String label, required DateTime? value, required ValueChanged<DateTime?> onChanged}) {
    final text = value == null ? '—' : intl.DateFormat('y-MM-dd').format(value);
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: value ?? DateTime.now(),
          firstDate: DateTime(2020),
          lastDate: DateTime(2100),
        );
        if (picked != null) onChanged(picked);
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          border: const OutlineInputBorder(),
        ),
        child: Text(text, style: const TextStyle(fontSize: 13)),
      ),
    );
  }
}

class _ExpenseTile extends StatelessWidget {
  final AdminExpense expense;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  const _ExpenseTile({required this.expense, required this.onEdit, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dateStr = intl.DateFormat('y-MM-dd HH:mm').format(expense.expenseDate);
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: cs.outlineVariant),
      ),
      child: InkWell(
        onTap: onEdit,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 38, height: 38,
                decoration: BoxDecoration(
                  color: cs.error.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.remove_circle_outline, color: cs.error, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppHelpers.formatCompactMoney(expense.amount),
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: cs.error),
                    ),
                    if (expense.note != null && expense.note!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(expense.note!, style: const TextStyle(fontSize: 12), maxLines: 2, overflow: TextOverflow.ellipsis),
                    ],
                    const SizedBox(height: 2),
                    Text(dateStr,
                        style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(Icons.delete_outline, color: cs.error, size: 20),
                onPressed: onDelete,
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ExpenseFormDialog extends ConsumerStatefulWidget {
  final AdminExpense? existing;
  const _ExpenseFormDialog({this.existing});

  @override
  ConsumerState<_ExpenseFormDialog> createState() => _ExpenseFormDialogState();
}

class _ExpenseFormDialogState extends ConsumerState<_ExpenseFormDialog> {
  final _amount = TextEditingController();
  final _note = TextEditingController();
  late DateTime _date;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _amount.text = _formatThousands(e.amount.toStringAsFixed(0));
      _note.text = e.note ?? '';
      _date = e.expenseDate;
    } else {
      _date = DateTime.now();
    }
  }

  double _parseAmount(String s) => double.tryParse(s.replaceAll(',', '').trim()) ?? 0;

  void _addQuick(int delta) {
    final current = _parseAmount(_amount.text);
    final next = (current + delta).toStringAsFixed(0);
    _amount.text = _formatThousands(next);
    setState(() {});
  }

  Future<void> _submit() async {
    final amt = _parseAmount(_amount.text);
    if (!amt.isFinite || amt <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('أدخل مبلغ صحيح')),
      );
      return;
    }
    setState(() => _saving = true);
    bool ok;
    if (widget.existing == null) {
      ok = await createExpense(ref, amount: amt, note: _note.text.trim(), date: _date);
    } else {
      ok = await updateExpense(ref, widget.existing!.id,
          amount: amt, note: _note.text.trim(), date: _date);
    }
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) Navigator.of(context).pop(true);
    else ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تعذّر الحفظ')));
  }

  Future<void> _pickDateTime() async {
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (pickedDate == null) return;
    if (!mounted) return;
    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_date),
    );
    final t = pickedTime ?? TimeOfDay.fromDateTime(_date);
    setState(() {
      _date = DateTime(pickedDate.year, pickedDate.month, pickedDate.day, t.hour, t.minute);
    });
  }

  @override
  Widget build(BuildContext context) {
    final dateStr = intl.DateFormat('y-MM-dd  HH:mm').format(_date);
    final isEdit = widget.existing != null;
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      title: Text(isEdit ? 'تعديل صرفية' : 'إضافة صرفية'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(decimal: false),
              textDirection: TextDirection.ltr,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
              inputFormatters: [_ExpenseThousandsFormatter()],
              decoration: const InputDecoration(
                labelText: 'المبلغ',
                suffixText: 'IQD',
                prefixIcon: Icon(Icons.monetization_on_outlined, size: 20),
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            // Quick amount chips mirroring the debt modal — small + nudges
            // the admin toward round thousands without fighting the keyboard.
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [5, 10, 25, 50, 100, 250, 500].map((k) {
                return ActionChip(
                  label: Text('+${k}K', style: const TextStyle(fontSize: 12)),
                  onPressed: () => _addQuick(k * 1000),
                  visualDensity: VisualDensity.compact,
                );
              }).toList()
                ..add(ActionChip(
                  label: const Text('مسح', style: TextStyle(fontSize: 12)),
                  onPressed: () { _amount.clear(); setState(() {}); },
                  visualDensity: VisualDensity.compact,
                )),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _note,
              decoration: const InputDecoration(
                labelText: 'ملاحظة (اختياري)',
                prefixIcon: Icon(Icons.note_outlined),
                isDense: true,
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 10),
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: _pickDateTime,
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'التاريخ والوقت',
                  prefixIcon: Icon(Icons.calendar_today),
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                child: Text(dateStr, style: const TextStyle(fontSize: 13)),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          onPressed: _saving ? null : _submit,
          child: _saving
              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(isEdit ? 'حفظ' : 'إضافة'),
        ),
      ],
    );
  }
}


/// Commas-on-input formatter matching the one in subscriber_details —
/// keeps the field readable while typing. Stored as plain digits on submit.
class _ExpenseThousandsFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return newValue.copyWith(text: '');
    final n = int.tryParse(digits);
    if (n == null) return oldValue;
    final formatted = _formatThousands(n.toString());
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

String _formatThousands(String digits) {
  final clean = digits.replaceAll(RegExp(r"[^0-9]"), "");
  if (clean.isEmpty) return "";
  final buf = StringBuffer();
  for (int i = 0; i < clean.length; i++) {
    if (i > 0 && (clean.length - i) % 3 == 0) buf.write(",");
    buf.write(clean[i]);
  }
  return buf.toString();
}
