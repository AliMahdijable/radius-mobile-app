import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' as intl;

import '../../core/utils/helpers.dart';
import '../../models/manager_debt.dart';
import '../../models/manager_debt_payment.dart';
import '../../providers/manager_debts_provider.dart';
import '../../widgets/app_snackbar.dart';

class ManagerDebtDetailScreen extends ConsumerStatefulWidget {
  final ManagerDebt debt;
  const ManagerDebtDetailScreen({super.key, required this.debt});

  @override
  ConsumerState<ManagerDebtDetailScreen> createState() =>
      _ManagerDebtDetailScreenState();
}

class _ManagerDebtDetailScreenState
    extends ConsumerState<ManagerDebtDetailScreen> {
  bool _sendingWa = false;

  @override
  Widget build(BuildContext context) {
    // Fetch fresh debt from the list provider — it's the source of truth
    // after mutations. Falls back to widget.debt on first paint.
    final allDebts = ref.watch(managerDebtsListProvider(const DebtsFilterArgs()));
    final debt = allDebts.maybeWhen(
          data: (list) {
            try {
              return list.firstWhere((d) => d.id == widget.debt.id);
            } catch (_) {
              return widget.debt;
            }
          },
          orElse: () => widget.debt,
        );
    final payments = ref.watch(managerDebtPaymentsProvider(debt.id));
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('تفاصيل الدين'),
        actions: [
          IconButton(
            tooltip: 'تعديل',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => _openEdit(context, debt),
          ),
          IconButton(
            tooltip: 'حذف',
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _confirmDelete(context, debt),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(managerDebtsListProvider);
          ref.invalidate(managerDebtPaymentsProvider(debt.id));
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 28),
          children: [
            _DebtorHeader(debt: debt),
            const SizedBox(height: 12),
            _AmountsBand(debt: debt),
            const SizedBox(height: 14),
            if (debt.remainingAmount > 0) ...[
              _ActionsRow(
                onPartial: () => _openPayment(context, debt, full: false),
                onFull: () => _openPayment(context, debt, full: true),
              ),
              const SizedBox(height: 10),
            ],
            _WhatsAppButton(
              sending: _sendingWa,
              onPressed: () => _sendWhatsApp(context, debt.id),
            ),
            const SizedBox(height: 22),
            _PaymentsSection(payments: payments, debtId: debt.id),
          ],
        ),
      ),
    );
  }

  Future<void> _sendWhatsApp(BuildContext context, int debtId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('إرسال تذكير واتساب'),
        content: const Text('سيُرسل تذكير على رقم الواتساب المسجّل. متابعة؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('إرسال')),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _sendingWa = true);
    final ok = await sendManagerDebtWhatsApp(ref, debtId);
    if (!mounted) return;
    setState(() => _sendingWa = false);
    if (ok) {
      AppSnackBar.success(context, 'تم الإرسال');
    } else {
      AppSnackBar.error(context, 'فشل الإرسال — تأكد من اتصال واتساب');
    }
  }

  Future<void> _openPayment(BuildContext context, ManagerDebt debt,
      {required bool full}) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _PaymentDialog(debt: debt, prefillFull: full),
    );
    if (saved == true && mounted) {
      AppSnackBar.success(context, 'تم تسجيل التسديد');
    }
  }

  Future<void> _openEdit(BuildContext context, ManagerDebt debt) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _EditDebtDialog(debt: debt),
    );
    if (saved == true && mounted) {
      AppSnackBar.success(context, 'تم التحديث');
    }
  }

  Future<void> _confirmDelete(BuildContext context, ManagerDebt debt) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('حذف الدين'),
        content: Text(
          'سيُحذف الدين (${AppHelpers.formatMoney(debt.amount)}) وكل تسديداته بشكل نهائي.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          FilledButton.tonal(
            style: FilledButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final success = await deleteManagerDebt(ref, debt.id);
    if (!mounted) return;
    if (success) {
      AppSnackBar.success(context, 'تم الحذف');
      Navigator.pop(context);
    } else {
      AppSnackBar.error(context, 'تعذّر الحذف');
    }
  }
}

// ─── Debtor header (name + date row) ───────────────────────────────────

class _DebtorHeader extends StatelessWidget {
  final ManagerDebt debt;
  const _DebtorHeader({required this.debt});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final statusColor = _statusColor(debt.status);
    final dateStr = intl.DateFormat('y/MM/dd').format(debt.debtDate);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [cs.primary.withOpacity(0.10), cs.primary.withOpacity(0.02)],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.5)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: cs.primary.withOpacity(0.15),
            child: Icon(Icons.person_outline, color: cs.primary, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  debt.debtorAdminUsername ?? 'مدير #${debt.debtorAdminId}',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Icon(Icons.event, size: 13, color: cs.onSurfaceVariant),
                    const SizedBox(width: 3),
                    Text(
                      dateStr,
                      style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
                if (debt.note != null && debt.note!.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    debt.note!,
                    style: TextStyle(
                      fontSize: 12,
                      color: cs.onSurfaceVariant,
                      fontStyle: FontStyle.italic,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.15),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              debtStatusLabel(debt.status),
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: statusColor),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── 3 amount cards, single balanced row ───────────────────────────────

class _AmountsBand extends StatelessWidget {
  final ManagerDebt debt;
  const _AmountsBand({required this.debt});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: _AmountTile(
            label: 'الأصلي',
            value: debt.amount,
            color: cs.primary,
          )),
          const SizedBox(width: 8),
          Expanded(child: _AmountTile(
            label: 'المسدّد',
            value: debt.paidAmount,
            color: Colors.green,
          )),
          const SizedBox(width: 8),
          Expanded(child: _AmountTile(
            label: 'المتبقي',
            value: debt.remainingAmount,
            color: debt.remainingAmount > 0 ? Colors.redAccent : Colors.green,
            bold: true,
          )),
        ],
      ),
    );
  }
}

class _AmountTile extends StatelessWidget {
  final String label;
  final double value;
  final Color color;
  final bool bold;
  const _AmountTile({
    required this.label,
    required this.value,
    required this.color,
    this.bold = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              AppHelpers.formatMoney(value),
              style: TextStyle(
                fontSize: bold ? 15 : 13.5,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Action row: partial / full ────────────────────────────────────────

class _ActionsRow extends StatelessWidget {
  final VoidCallback onPartial;
  final VoidCallback onFull;
  const _ActionsRow({required this.onPartial, required this.onFull});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: onPartial,
            icon: const Icon(Icons.payments_outlined, size: 18),
            label: const Text('تسديد جزئي'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: FilledButton.icon(
            onPressed: onFull,
            icon: const Icon(Icons.done_all, size: 18),
            label: const Text('تسديد كامل'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
      ],
    );
  }
}

class _WhatsAppButton extends StatelessWidget {
  final bool sending;
  final VoidCallback onPressed;
  const _WhatsAppButton({required this.sending, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: sending ? null : onPressed,
        icon: sending
            ? const SizedBox(
                width: 16, height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.send, size: 18),
        label: Text(sending ? 'جاري الإرسال...' : 'إرسال تذكير واتساب'),
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.green.shade700,
          side: BorderSide(color: Colors.green.shade300),
          padding: const EdgeInsets.symmetric(vertical: 12),
        ),
      ),
    );
  }
}

// ─── Payments section ──────────────────────────────────────────────────

class _PaymentsSection extends ConsumerWidget {
  final AsyncValue<List<ManagerDebtPayment>> payments;
  final int debtId;
  const _PaymentsSection({required this.payments, required this.debtId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.history, size: 18),
            const SizedBox(width: 6),
            const Text('سجل التسديدات',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            const Spacer(),
            payments.when(
              data: (p) => Text('${p.length}', style: TextStyle(color: cs.onSurfaceVariant)),
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
            ),
          ],
        ),
        const SizedBox(height: 10),
        payments.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(20),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => Text('خطأ: $e'),
          data: (list) {
            if (list.isEmpty) {
              return Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: cs.outlineVariant.withOpacity(0.5)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, size: 16, color: cs.onSurfaceVariant),
                    const SizedBox(width: 8),
                    Text('لا توجد تسديدات بعد',
                        style: TextStyle(color: cs.onSurfaceVariant)),
                  ],
                ),
              );
            }
            return Column(
              children: list
                  .map((p) => _PaymentTile(
                        payment: p,
                        onDelete: () => _confirmDeletePayment(context, ref, p, debtId),
                      ))
                  .toList(),
            );
          },
        ),
      ],
    );
  }

  Future<void> _confirmDeletePayment(BuildContext context, WidgetRef ref,
      ManagerDebtPayment p, int debtId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('حذف التسديد'),
        content: Text('حذف تسديد ${AppHelpers.formatMoney(p.amountPaid)}؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          FilledButton.tonal(
            style: FilledButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final success = await deleteManagerDebtPayment(ref, p.id, debtId);
    if (!context.mounted) return;
    if (success) {
      AppSnackBar.success(context, 'تم الحذف');
    } else {
      AppSnackBar.error(context, 'تعذّر الحذف');
    }
  }
}

class _PaymentTile extends StatelessWidget {
  final ManagerDebtPayment payment;
  final VoidCallback onDelete;
  const _PaymentTile({required this.payment, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final date = intl.DateFormat('y/MM/dd').format(payment.paymentDate);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.green.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.green.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: Colors.green.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check, color: Colors.green, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppHelpers.formatMoney(payment.amountPaid),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Colors.green,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  payment.note != null && payment.note!.isNotEmpty
                      ? '$date · ${payment.note}'
                      : date,
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            iconSize: 20,
            color: Colors.redAccent,
            onPressed: onDelete,
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}

// ─── Payment AlertDialog (matches expense modal style) ─────────────────

class _PaymentDialog extends ConsumerStatefulWidget {
  final ManagerDebt debt;
  final bool prefillFull;
  const _PaymentDialog({required this.debt, required this.prefillFull});

  @override
  ConsumerState<_PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends ConsumerState<_PaymentDialog> {
  late final TextEditingController _amount;
  late final TextEditingController _note;
  late DateTime _date;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _amount = TextEditingController(
      text: widget.prefillFull
          ? _formatThousands(widget.debt.remainingAmount.toStringAsFixed(0))
          : '',
    );
    _note = TextEditingController();
    _date = DateTime.now();
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  double _parseAmount(String s) =>
      double.tryParse(s.replaceAll(',', '').trim()) ?? 0;

  void _addQuick(int delta) {
    final current = _parseAmount(_amount.text);
    final next = (current + delta).toStringAsFixed(0);
    _amount.text = _formatThousands(next);
    setState(() {});
  }

  void _setExact(int value) {
    _amount.text = _formatThousands(value.toString());
    setState(() {});
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _submit() async {
    final amt = _parseAmount(_amount.text);
    if (!amt.isFinite || amt <= 0) {
      AppSnackBar.error(context, 'أدخل مبلغ صحيح');
      return;
    }
    if (amt > widget.debt.remainingAmount + 0.01) {
      AppSnackBar.error(context,
          'المبلغ يتجاوز المتبقي (${AppHelpers.formatMoney(widget.debt.remainingAmount)})');
      return;
    }
    setState(() => _saving = true);
    final result = await addManagerDebtPayment(
      ref,
      widget.debt.id,
      amountPaid: amt,
      note: _note.text.trim().isEmpty ? null : _note.text.trim(),
      paymentDate: _date,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (result.success) {
      Navigator.pop(context, true);
    } else {
      AppSnackBar.error(context, result.errorMessage ?? 'تعذّر حفظ التسديد');
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateStr = intl.DateFormat('y-MM-dd').format(_date);
    final remaining = widget.debt.remainingAmount;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
      scrollable: true,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('تسجيل تسديد'),
          const SizedBox(height: 4),
          Text(
            'المتبقي: ${AppHelpers.formatMoney(remaining)}',
            style: const TextStyle(
              fontSize: 12,
              color: Colors.redAccent,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(decimal: false),
              textDirection: TextDirection.ltr,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
              inputFormatters: [_DebtThousandsFormatter()],
              decoration: const InputDecoration(
                labelText: 'المبلغ المسدّد',
                suffixText: 'IQD',
                prefixIcon: Icon(Icons.monetization_on_outlined, size: 20),
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            // Quick-amount chips, same pattern as the expenses modal.
            // The first chip "ملء" pre-fills the exact remaining so the
            // admin can tap once for a full payment even if the button
            // was "partial".
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                ActionChip(
                  avatar: const Icon(Icons.done_all, size: 16),
                  label: Text('ملء (${_formatThousands(remaining.toStringAsFixed(0))})',
                      style: const TextStyle(fontSize: 12)),
                  onPressed: () => _setExact(remaining.toInt()),
                  visualDensity: VisualDensity.compact,
                ),
                for (final v in const [5000, 10000, 25000, 50000, 100000, 250000])
                  ActionChip(
                    label: Text('+${_formatThousands(v.toString())}',
                        style: const TextStyle(fontSize: 12)),
                    onPressed: () => _addQuick(v),
                    visualDensity: VisualDensity.compact,
                  ),
                ActionChip(
                  label: const Text('مسح', style: TextStyle(fontSize: 12)),
                  onPressed: () { _amount.clear(); setState(() {}); },
                  visualDensity: VisualDensity.compact,
                ),
              ],
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
              onTap: _pickDate,
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'تاريخ التسديد',
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
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
        FilledButton.icon(
          onPressed: _saving ? null : _submit,
          icon: _saving
              ? const SizedBox(
                  width: 14, height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.save_outlined, size: 18),
          label: Text(_saving ? 'حفظ...' : 'حفظ'),
        ),
      ],
    );
  }
}

// ─── Edit Debt AlertDialog ─────────────────────────────────────────────

class _EditDebtDialog extends ConsumerStatefulWidget {
  final ManagerDebt debt;
  const _EditDebtDialog({required this.debt});

  @override
  ConsumerState<_EditDebtDialog> createState() => _EditDebtDialogState();
}

class _EditDebtDialogState extends ConsumerState<_EditDebtDialog> {
  late final TextEditingController _amount;
  late final TextEditingController _note;
  late DateTime _date;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _amount = TextEditingController(
      text: _formatThousands(widget.debt.amount.toStringAsFixed(0)),
    );
    _note = TextEditingController(text: widget.debt.note ?? '');
    _date = widget.debt.debtDate;
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  double _parseAmount(String s) =>
      double.tryParse(s.replaceAll(',', '').trim()) ?? 0;

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 30)),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _submit() async {
    final amt = _parseAmount(_amount.text);
    if (!amt.isFinite || amt <= 0) {
      AppSnackBar.error(context, 'أدخل مبلغ صحيح');
      return;
    }
    setState(() => _saving = true);
    final ok = await updateManagerDebt(
      ref,
      widget.debt.id,
      amount: amt,
      note: _note.text.trim(),
      debtDate: _date,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) {
      Navigator.pop(context, true);
    } else {
      AppSnackBar.error(context, 'تعذّر التحديث');
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateStr = intl.DateFormat('y-MM-dd').format(_date);
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
      scrollable: true,
      title: const Text('تعديل الدين'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(decimal: false),
              textDirection: TextDirection.ltr,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
              inputFormatters: [_DebtThousandsFormatter()],
              decoration: const InputDecoration(
                labelText: 'المبلغ',
                suffixText: 'IQD',
                prefixIcon: Icon(Icons.monetization_on_outlined, size: 20),
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _note,
              decoration: const InputDecoration(
                labelText: 'ملاحظة',
                prefixIcon: Icon(Icons.note_outlined),
                isDense: true,
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 10),
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: _pickDate,
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'تاريخ الدين',
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
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
        FilledButton.icon(
          onPressed: _saving ? null : _submit,
          icon: _saving
              ? const SizedBox(
                  width: 14, height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.save_outlined, size: 18),
          label: Text(_saving ? 'حفظ...' : 'حفظ'),
        ),
      ],
    );
  }
}

// ─── Helpers ───────────────────────────────────────────────────────────

Color _statusColor(ManagerDebtStatus s) {
  switch (s) {
    case ManagerDebtStatus.paid:
      return Colors.green;
    case ManagerDebtStatus.partial:
      return Colors.orange;
    case ManagerDebtStatus.open:
      return Colors.redAccent;
  }
}

// Mirrors the expenses modal formatter so amount fields across the app
// share the same typing behaviour (typing "25000" auto-formats to
// "25,000").
class _DebtThousandsFormatter extends TextInputFormatter {
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
