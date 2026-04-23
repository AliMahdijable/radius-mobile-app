import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
    // Fetch fresh debt data from list provider (list is source of truth).
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
            onPressed: () => _openEditSheet(context, debt),
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
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [cs.primary.withOpacity(0.12), cs.primary.withOpacity(0.02)],
                  begin: Alignment.topRight,
                  end: Alignment.bottomLeft,
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: cs.outlineVariant.withOpacity(0.5)),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: cs.primary.withOpacity(0.2),
                    child: Icon(Icons.person, color: cs.primary),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          debt.debtorAdminUsername ?? 'مدير #${debt.debtorAdminId}',
                          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${_fmtDate(debt.debtDate)}${debt.note != null ? ' · ${debt.note}' : ''}',
                          style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  _StatusBadge(status: debt.status),
                ],
              ),
            ),

            const SizedBox(height: 14),

            // 3 amount cards
            Row(
              children: [
                Expanded(child: _AmountCard(label: 'الأصلي', value: debt.amount, color: Colors.blueAccent)),
                const SizedBox(width: 8),
                Expanded(child: _AmountCard(label: 'المسدّد', value: debt.paidAmount, color: Colors.green)),
                const SizedBox(width: 8),
                Expanded(child: _AmountCard(
                  label: 'المتبقي',
                  value: debt.remainingAmount,
                  color: debt.remainingAmount > 0 ? Colors.redAccent : Colors.green,
                )),
              ],
            ),

            const SizedBox(height: 18),

            // Action buttons (payment + WhatsApp)
            if (debt.remainingAmount > 0) ...[
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _openPaymentSheet(context, debt, full: false),
                      icon: const Icon(Icons.payments_outlined),
                      label: const Text('تسديد جزئي'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => _openPaymentSheet(context, debt, full: true),
                      icon: const Icon(Icons.done_all),
                      label: Text('تسديد كامل (${AppHelpers.formatMoney(debt.remainingAmount)})'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
            ],
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _sendingWa ? null : () => _sendWhatsApp(context, debt.id),
                icon: _sendingWa
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send),
                label: Text(_sendingWa ? 'جاري الإرسال...' : 'إرسال تذكير واتساب'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.green.shade700,
                  side: BorderSide(color: Colors.green.shade300),
                ),
              ),
            ),

            const SizedBox(height: 22),

            // Payments timeline
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
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: cs.outlineVariant.withOpacity(0.5)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline, size: 16, color: cs.onSurfaceVariant),
                        const SizedBox(width: 8),
                        Text(
                          'لا توجد تسديدات بعد',
                          style: TextStyle(color: cs.onSurfaceVariant),
                        ),
                      ],
                    ),
                  );
                }
                return Column(
                  children: [
                    for (int i = 0; i < list.length; i++)
                      _PaymentTile(
                        payment: list[i],
                        isLast: i == list.length - 1,
                        onDelete: () => _confirmDeletePayment(context, list[i], debt.id),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  String _fmtDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _sendWhatsApp(BuildContext context, int debtId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('إرسال تذكير واتساب'),
        content: const Text('سيُرسل رسالة تذكير على رقم الواتساب المسجل. متابعة؟'),
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
      AppSnackBar.error(context, 'فشل الإرسال — تأكد من اتصال واتساب ومن رقم المدير الفرعي');
    }
  }

  Future<void> _openPaymentSheet(BuildContext context, ManagerDebt debt,
      {required bool full}) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _PaymentFormSheet(debt: debt, prefillFull: full),
    );
    if (saved == true && mounted) {
      AppSnackBar.success(context, 'تم تسجيل التسديد');
    }
  }

  Future<void> _openEditSheet(BuildContext context, ManagerDebt debt) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _EditDebtSheet(debt: debt),
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

  Future<void> _confirmDeletePayment(
      BuildContext context, ManagerDebtPayment p, int debtId) async {
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
    if (!mounted) return;
    if (success) {
      AppSnackBar.success(context, 'تم الحذف');
    } else {
      AppSnackBar.error(context, 'تعذّر الحذف');
    }
  }
}

// ─── Status badge ──────────────────────────────────────────────────────

class _StatusBadge extends StatelessWidget {
  final ManagerDebtStatus status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final color = status == ManagerDebtStatus.paid
        ? Colors.green
        : status == ManagerDebtStatus.partial
            ? Colors.orange
            : Colors.redAccent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        debtStatusLabel(status),
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color),
      ),
    );
  }
}

class _AmountCard extends StatelessWidget {
  final String label;
  final double value;
  final Color color;
  const _AmountCard({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 11, color: color)),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: Text(
              AppHelpers.formatMoney(value),
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: color),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Payment row (compact timeline) ────────────────────────────────────

class _PaymentTile extends StatelessWidget {
  final ManagerDebtPayment payment;
  final bool isLast;
  final VoidCallback onDelete;
  const _PaymentTile({
    required this.payment,
    required this.isLast,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final date =
        '${payment.paymentDate.year}-${payment.paymentDate.month.toString().padLeft(2, '0')}-${payment.paymentDate.day.toString().padLeft(2, '0')}';
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
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: Colors.green.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check, color: Colors.green, size: 20),
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
                  '$date${payment.note != null ? ' · ${payment.note}' : ''}',
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            iconSize: 20,
            color: Colors.redAccent,
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}

// ─── Payment form sheet (partial or full) ──────────────────────────────

class _PaymentFormSheet extends ConsumerStatefulWidget {
  final ManagerDebt debt;
  final bool prefillFull;
  const _PaymentFormSheet({required this.debt, required this.prefillFull});

  @override
  ConsumerState<_PaymentFormSheet> createState() => _PaymentFormSheetState();
}

class _PaymentFormSheetState extends ConsumerState<_PaymentFormSheet> {
  final _formKey = GlobalKey<FormState>();
  final _amountCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  DateTime _date = DateTime.now();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    if (widget.prefillFull) {
      _amountCtrl.text = widget.debt.remainingAmount.toStringAsFixed(0);
    }
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, scrollCtrl) => SingleChildScrollView(
          controller: scrollCtrl,
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'تسجيل تسديد',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'المتبقي: ${AppHelpers.formatMoney(widget.debt.remainingAmount)}',
                  style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _amountCtrl,
                  autofocus: !widget.prefillFull,
                  decoration: const InputDecoration(
                    labelText: 'المبلغ المسدّد (د.ع)',
                    prefixIcon: Icon(Icons.payments_outlined),
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                  validator: (v) {
                    final n = double.tryParse((v ?? '').trim());
                    if (n == null || n <= 0) return 'أدخل مبلغ صحيح';
                    if (n > widget.debt.remainingAmount + 0.01) {
                      return 'المبلغ يتجاوز المتبقي (${AppHelpers.formatMoney(widget.debt.remainingAmount)})';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _noteCtrl,
                  decoration: const InputDecoration(
                    labelText: 'ملاحظة (اختياري)',
                    prefixIcon: Icon(Icons.note_outlined),
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 12),
                InkWell(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _date,
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now(),
                    );
                    if (picked != null) setState(() => _date = picked);
                  },
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'تاريخ التسديد',
                      prefixIcon: Icon(Icons.event_outlined),
                      border: OutlineInputBorder(),
                    ),
                    child: Text(
                      '${_date.year}-${_date.month.toString().padLeft(2, '0')}-${_date.day.toString().padLeft(2, '0')}',
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _saving ? null : _submit,
                    icon: _saving
                        ? const SizedBox(
                            width: 16, height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.save_outlined),
                    label: Text(_saving ? 'جاري الحفظ...' : 'حفظ التسديد'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    final result = await addManagerDebtPayment(
      ref,
      widget.debt.id,
      amountPaid: double.parse(_amountCtrl.text.trim()),
      note: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
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
}

// ─── Edit debt sheet (amount/note/date) ────────────────────────────────

class _EditDebtSheet extends ConsumerStatefulWidget {
  final ManagerDebt debt;
  const _EditDebtSheet({required this.debt});

  @override
  ConsumerState<_EditDebtSheet> createState() => _EditDebtSheetState();
}

class _EditDebtSheetState extends ConsumerState<_EditDebtSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amountCtrl;
  late final TextEditingController _noteCtrl;
  late DateTime _date;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _amountCtrl = TextEditingController(text: widget.debt.amount.toStringAsFixed(0));
    _noteCtrl = TextEditingController(text: widget.debt.note ?? '');
    _date = widget.debt.debtDate;
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text('تعديل الدين',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _amountCtrl,
                decoration: const InputDecoration(
                  labelText: 'المبلغ (د.ع)',
                  prefixIcon: Icon(Icons.payments_outlined),
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
                validator: (v) {
                  final n = double.tryParse((v ?? '').trim());
                  if (n == null || n <= 0) return 'أدخل مبلغ صحيح';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _noteCtrl,
                decoration: const InputDecoration(
                  labelText: 'ملاحظة',
                  prefixIcon: Icon(Icons.note_outlined),
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 12),
              InkWell(
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _date,
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now().add(const Duration(days: 30)),
                  );
                  if (picked != null) setState(() => _date = picked);
                },
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'تاريخ الدين',
                    prefixIcon: Icon(Icons.event_outlined),
                    border: OutlineInputBorder(),
                  ),
                  child: Text(
                    '${_date.year}-${_date.month.toString().padLeft(2, '0')}-${_date.day.toString().padLeft(2, '0')}',
                  ),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _saving ? null : _submit,
                  icon: _saving
                      ? const SizedBox(
                          width: 16, height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.save_outlined),
                  label: Text(_saving ? 'جاري الحفظ...' : 'حفظ التغييرات'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    final ok = await updateManagerDebt(
      ref,
      widget.debt.id,
      amount: double.parse(_amountCtrl.text.trim()),
      note: _noteCtrl.text.trim(),
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
}
