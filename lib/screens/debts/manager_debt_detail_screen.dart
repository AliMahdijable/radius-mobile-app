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
            const SizedBox(height: 16),
            _HeroRemaining(debt: debt),
            const SizedBox(height: 12),
            _SecondaryAmounts(debt: debt),
            const SizedBox(height: 18),
            if (debt.remainingAmount > 0) ...[
              _ActionsRow(
                onPartial: () => _openPayment(context, debt, full: false),
                onFull: () => _openPayment(context, debt, full: true),
              ),
              const SizedBox(height: 10),
            ],
            _WhatsAppButton(
              sending: _sendingWa,
              onPressed: () => _openWhatsAppDialog(context, debt),
            ),
            const SizedBox(height: 24),
            _PaymentsSection(payments: payments, debtId: debt.id),
          ],
        ),
      ),
    );
  }

  Future<void> _openWhatsAppDialog(BuildContext context, ManagerDebt debt) async {
    final phone = await showDialog<String?>(
      context: context,
      builder: (_) => _WhatsAppDialog(debt: debt),
    );
    if (phone == null || phone.isEmpty) return;

    setState(() => _sendingWa = true);
    final ok = await sendManagerDebtWhatsApp(ref, debt.id, phone: phone);
    if (!mounted) return;
    setState(() => _sendingWa = false);
    if (ok) {
      AppSnackBar.success(context, 'تم الإرسال');
    } else {
      AppSnackBar.error(context,
          'فشل الإرسال — تأكد أن رقم واتساب الفرعي صحيح ومسجّل على واتساب');
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

// ─── Debtor header (compact card) ──────────────────────────────────────

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
        color: cs.surfaceContainerHighest.withOpacity(0.4),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.4)),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [cs.primary.withOpacity(0.3), cs.primary.withOpacity(0.1)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.person_outline_rounded, color: cs.primary, size: 26),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  debt.debtorAdminUsername ?? 'مدير #${debt.debtorAdminId}',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.calendar_month_rounded,
                        size: 13, color: cs.onSurfaceVariant),
                    const SizedBox(width: 4),
                    Text(dateStr,
                        style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                  ],
                ),
                if (debt.note != null && debt.note!.isNotEmpty) ...[
                  const SizedBox(height: 4),
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
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: statusColor.withOpacity(0.35)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6, height: 6,
                  decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle),
                ),
                const SizedBox(width: 5),
                Text(
                  debtStatusLabel(debt.status),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: statusColor,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Hero remaining card with progress bar ─────────────────────────────

class _HeroRemaining extends StatelessWidget {
  final ManagerDebt debt;
  const _HeroRemaining({required this.debt});

  @override
  Widget build(BuildContext context) {
    final isDone = debt.remainingAmount <= 0;
    final heroColor = isDone ? Colors.green : Colors.redAccent;
    final secondaryColor = isDone ? Colors.green.shade700 : Colors.red.shade700;
    final progress = debt.amount > 0
        ? (debt.paidAmount / debt.amount).clamp(0.0, 1.0)
        : 0.0;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            heroColor.withOpacity(0.13),
            heroColor.withOpacity(0.03),
          ],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: heroColor.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                isDone ? Icons.check_circle_rounded : Icons.hourglass_bottom_rounded,
                color: heroColor,
                size: 20,
              ),
              const SizedBox(width: 6),
              Text(
                isDone ? 'مسدّد بالكامل' : 'المبلغ المتبقي',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: secondaryColor,
                ),
              ),
              const Spacer(),
              Text(
                '${(progress * 100).toStringAsFixed(0)}%',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: secondaryColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              AppHelpers.formatMoney(
                isDone ? debt.amount : debt.remainingAmount,
              ),
              style: TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.w900,
                color: heroColor,
                letterSpacing: -0.5,
              ),
            ),
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor: heroColor.withOpacity(0.15),
              color: heroColor,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                'مسدّد ${AppHelpers.formatMoney(debt.paidAmount)}',
                style: TextStyle(fontSize: 12, color: secondaryColor, fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              Text(
                'من ${AppHelpers.formatMoney(debt.amount)}',
                style: TextStyle(fontSize: 12, color: secondaryColor, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Secondary amounts (original + paid as small twin cards) ───────────

class _SecondaryAmounts extends StatelessWidget {
  final ManagerDebt debt;
  const _SecondaryAmounts({required this.debt});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          child: _MiniStat(
            icon: Icons.request_quote_outlined,
            label: 'المبلغ الأصلي',
            value: debt.amount,
            color: cs.primary,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _MiniStat(
            icon: Icons.savings_outlined,
            label: 'المسدّد',
            value: debt.paidAmount,
            color: Colors.green.shade700,
          ),
        ),
      ],
    );
  }
}

class _MiniStat extends StatelessWidget {
  final IconData icon;
  final String label;
  final double value;
  final Color color;
  const _MiniStat({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: color,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              AppHelpers.formatMoney(value),
              style: TextStyle(
                fontSize: 16,
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

// ─── Action buttons row ────────────────────────────────────────────────

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
              padding: const EdgeInsets.symmetric(vertical: 13),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: FilledButton.icon(
            onPressed: onFull,
            icon: const Icon(Icons.done_all, size: 18),
            label: const Text('تسديد كامل'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 13),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
            : const Icon(Icons.send_rounded, size: 18),
        label: Text(sending ? 'جاري الإرسال...' : 'إرسال تذكير واتساب'),
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.green.shade700,
          side: BorderSide(color: Colors.green.shade400, width: 1.2),
          padding: const EdgeInsets.symmetric(vertical: 13),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }
}

// ─── Payments timeline ─────────────────────────────────────────────────

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
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: cs.primary.withOpacity(0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.history_rounded, size: 16, color: cs.primary),
            ),
            const SizedBox(width: 8),
            const Text(
              'سجل التسديدات',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
            ),
            const Spacer(),
            payments.when(
              data: (p) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: cs.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${p.length}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: cs.primary,
                  ),
                ),
              ),
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
            ),
          ],
        ),
        const SizedBox(height: 12),
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
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: cs.outlineVariant.withOpacity(0.4),
                    style: BorderStyle.solid,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline_rounded, size: 18, color: cs.onSurfaceVariant),
                    const SizedBox(width: 10),
                    Text(
                      'لا توجد تسديدات بعد',
                      style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
                    ),
                  ],
                ),
              );
            }
            return Column(
              children: [
                for (int i = 0; i < list.length; i++)
                  _PaymentRow(
                    payment: list[i],
                    isFirst: i == 0,
                    isLast: i == list.length - 1,
                    onDelete: () => _confirmDeletePayment(context, ref, list[i], debtId),
                  ),
              ],
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

class _PaymentRow extends StatelessWidget {
  final ManagerDebtPayment payment;
  final bool isFirst;
  final bool isLast;
  final VoidCallback onDelete;
  const _PaymentRow({
    required this.payment,
    required this.isFirst,
    required this.isLast,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final date = intl.DateFormat('y/MM/dd').format(payment.paymentDate);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Timeline rail (dots + connecting line)
          SizedBox(
            width: 28,
            child: Column(
              children: [
                if (!isFirst)
                  Container(
                    width: 2,
                    height: 8,
                    color: Colors.green.withOpacity(0.3),
                  )
                else
                  const SizedBox(height: 8),
                Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: Colors.green,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.green.withOpacity(0.3),
                        blurRadius: 4,
                      ),
                    ],
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      color: Colors.green.withOpacity(0.3),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.green.withOpacity(0.25)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.check_circle,
                                  color: Colors.green, size: 16),
                              const SizedBox(width: 5),
                              Text(
                                AppHelpers.formatMoney(payment.amountPaid),
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.green,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 3),
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
                    InkWell(
                      onTap: onDelete,
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        child: Icon(
                          Icons.delete_outline,
                          size: 18,
                          color: Colors.red.shade300,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── WhatsApp send dialog (with manual phone entry) ────────────────────

class _WhatsAppDialog extends StatefulWidget {
  final ManagerDebt debt;
  const _WhatsAppDialog({required this.debt});

  @override
  State<_WhatsAppDialog> createState() => _WhatsAppDialogState();
}

class _WhatsAppDialogState extends State<_WhatsAppDialog> {
  final _phone = TextEditingController();

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
      scrollable: true,
      title: Row(
        children: [
          Icon(Icons.send_rounded, color: Colors.green.shade700, size: 20),
          const SizedBox(width: 8),
          const Text('إرسال تذكير واتساب'),
        ],
      ),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.orange.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 18, color: Colors.orange.shade700),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'أدخل رقم واتساب ${widget.debt.debtorAdminUsername ?? "المدير الفرعي"} الذي يستقبل التذكير.',
                      style: TextStyle(fontSize: 12, color: Colors.orange.shade900),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              textDirection: TextDirection.ltr,
              decoration: const InputDecoration(
                labelText: 'رقم الواتساب',
                hintText: '07801234567 أو 9647801234567',
                prefixIcon: Icon(Icons.phone_outlined),
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'سيُرسل من حساب واتساب الخاص بك.',
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, null),
          child: const Text('إلغاء'),
        ),
        FilledButton.icon(
          onPressed: () {
            final v = _phone.text.trim();
            if (v.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('أدخل رقم الواتساب'))
              );
              return;
            }
            Navigator.pop(context, v);
          },
          icon: const Icon(Icons.send_rounded, size: 18),
          label: const Text('إرسال'),
          style: FilledButton.styleFrom(
            backgroundColor: Colors.green.shade700,
          ),
        ),
      ],
    );
  }
}

// ─── Payment AlertDialog ───────────────────────────────────────────────

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
