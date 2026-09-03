import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' as intl;

import '../../core/utils/helpers.dart';
import '../../models/manager_debt.dart';
import '../../providers/manager_debts_provider.dart';
import '../../widgets/app_snackbar.dart';
import 'manager_debt_detail_screen.dart';

/// Parent-admin ledger: lists debts owed BY sub-admins. Gated by the
/// /access endpoint so sub-admins who don't manage anyone get an empty
/// state even if they deep-link into the route.
class ManagerDebtsScreen extends ConsumerStatefulWidget {
  const ManagerDebtsScreen({super.key});

  @override
  ConsumerState<ManagerDebtsScreen> createState() => _ManagerDebtsScreenState();
}

class _ManagerDebtsScreenState extends ConsumerState<ManagerDebtsScreen> {
  String? _statusFilter;
  int? _debtorFilter;

  DebtsFilterArgs get _args =>
      DebtsFilterArgs(status: _statusFilter, debtorAdminId: _debtorFilter);

  @override
  Widget build(BuildContext context) {
    final access = ref.watch(managerDebtsAccessProvider);
    final summary = ref.watch(managerDebtsSummaryProvider);
    final list = ref.watch(managerDebtsListProvider(_args));
    final cs = Theme.of(context).colorScheme;

    return access.when(
      loading: () => Scaffold(
        appBar: AppBar(title: const Text('ديون المدراء')),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (_, __) => Scaffold(
        appBar: AppBar(title: const Text('ديون المدراء')),
        body: const Center(child: Text('تعذّر التحقق من الصلاحية')),
      ),
      data: (acc) {
        if (!acc.hasSubAdmins) {
          return Scaffold(
            appBar: AppBar(title: const Text('ديون المدراء')),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.lock_outline, size: 48, color: cs.onSurfaceVariant),
                    const SizedBox(height: 12),
                    const Text(
                      'هذه الخاصية متاحة فقط للمدراء الذين لديهم مدراء فرعيون.',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        return Scaffold(
          appBar: AppBar(
            title: const Text('ديون المدراء'),
            elevation: 0,
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _openCreate(context, acc.subAdmins),
            icon: const Icon(Icons.add_rounded),
            label: const Text('إضافة دين'),
          ),
          body: RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(managerDebtsAccessProvider);
              ref.invalidate(managerDebtsSummaryProvider);
              ref.invalidate(managerDebtsListProvider);
            },
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(child: _SummaryGrid(asyncSummary: summary)),
                SliverToBoxAdapter(
                  child: _Filters(
                    statusFilter: _statusFilter,
                    debtorFilter: _debtorFilter,
                    subAdmins: acc.subAdmins,
                    onStatus: (s) => setState(() => _statusFilter = s),
                    onDebtor: (id) => setState(() => _debtorFilter = id),
                  ),
                ),
                list.when(
                  loading: () => const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  error: (e, _) => SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(child: Text('خطأ: $e')),
                  ),
                  data: (debts) {
                    if (debts.isEmpty) {
                      return SliverFillRemaining(
                        hasScrollBody: false,
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.inbox_outlined,
                                  size: 64, color: cs.onSurfaceVariant.withOpacity(0.5)),
                              const SizedBox(height: 12),
                              const Text(
                                'لا توجد ديون بالفلتر الحالي',
                                style: TextStyle(fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'اضغط "إضافة دين" لتسجيل أول دين',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }
                    return SliverPadding(
                      padding: const EdgeInsets.fromLTRB(14, 4, 14, 100),
                      sliver: SliverList.separated(
                        itemCount: debts.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (_, i) => _DebtCard(
                          debt: debts[i],
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  ManagerDebtDetailScreen(debt: debts[i]),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _openCreate(
      BuildContext context, List<SubAdminRef> subAdmins) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _CreateDebtDialog(subAdmins: subAdmins),
    );
    if (saved == true && mounted) {
      AppSnackBar.success(context, 'تم إضافة الدين');
    }
  }
}

// ─── Summary grid (2x2 on phones) ──────────────────────────────────────

class _SummaryGrid extends StatelessWidget {
  final AsyncValue<ManagerDebtsSummary> asyncSummary;
  const _SummaryGrid({required this.asyncSummary});

  @override
  Widget build(BuildContext context) {
    final s = asyncSummary.asData?.value ?? ManagerDebtsSummary.empty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _StatCard(
                  icon: Icons.hourglass_bottom_rounded,
                  label: 'المتبقي',
                  valueText: AppHelpers.formatMoney(s.totalRemaining),
                  color: Colors.redAccent,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _StatCard(
                  icon: Icons.savings_outlined,
                  label: 'المسدّد',
                  valueText: AppHelpers.formatMoney(s.totalPaid),
                  color: Colors.green.shade700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _StatCard(
                  icon: Icons.request_quote_outlined,
                  label: 'إجمالي الديون',
                  valueText: AppHelpers.formatMoney(s.totalAmount),
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _StatCard(
                  icon: Icons.people_alt_outlined,
                  label: 'عدد المدراء',
                  valueText: s.debtorsCount.toString(),
                  color: Colors.deepPurple,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String valueText;
  final Color color;
  const _StatCard({
    required this.icon,
    required this.label,
    required this.valueText,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color.withOpacity(0.12), color.withOpacity(0.03)],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 14, color: color),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    color: color,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              valueText,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w900,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Filters ───────────────────────────────────────────────────────────

class _Filters extends StatelessWidget {
  final String? statusFilter;
  final int? debtorFilter;
  final List<SubAdminRef> subAdmins;
  final ValueChanged<String?> onStatus;
  final ValueChanged<int?> onDebtor;
  const _Filters({
    required this.statusFilter,
    required this.debtorFilter,
    required this.subAdmins,
    required this.onStatus,
    required this.onDebtor,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _chip(context, 'الكل', statusFilter == null, () => onStatus(null)),
                _chip(context, 'مفتوح', statusFilter == 'open', () => onStatus('open')),
                _chip(context, 'جزئي', statusFilter == 'partial', () => onStatus('partial')),
                _chip(context, 'مسدّد', statusFilter == 'paid', () => onStatus('paid')),
              ],
            ),
          ),
          if (subAdmins.isNotEmpty) ...[
            const SizedBox(height: 8),
            DropdownButtonFormField<int?>(
              value: debtorFilter,
              isDense: true,
              icon: const Icon(Icons.expand_more_rounded),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.person_search_rounded, size: 18),
                hintText: 'فلترة بمدير فرعي',
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                filled: true,
                fillColor: cs.surfaceContainerHighest.withOpacity(0.25),
              ),
              items: [
                const DropdownMenuItem<int?>(value: null, child: Text('الكل')),
                ...subAdmins.map((s) => DropdownMenuItem<int?>(
                      value: s.id,
                      child: Text(s.username, overflow: TextOverflow.ellipsis),
                    )),
              ],
              onChanged: onDebtor,
            ),
          ],
        ],
      ),
    );
  }

  Widget _chip(BuildContext ctx, String label, bool selected, VoidCallback onTap) {
    final cs = Theme.of(ctx).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
        selectedColor: cs.primary.withOpacity(0.25),
        visualDensity: VisualDensity.compact,
        labelStyle: TextStyle(
          fontSize: 12,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
    );
  }
}

// ─── Debt card (list row) ──────────────────────────────────────────────

class _DebtCard extends StatelessWidget {
  final ManagerDebt debt;
  final VoidCallback onTap;
  const _DebtCard({required this.debt, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final statusColor = _statusColor(debt.status);
    final progress = debt.amount > 0
        ? (debt.paidAmount / debt.amount).clamp(0.0, 1.0)
        : 0.0;
    final dateStr = intl.DateFormat('y/MM/dd').format(debt.debtDate);
    final firstLetter = (debt.debtorAdminUsername ?? '?').trim().isNotEmpty
        ? debt.debtorAdminUsername!.substring(0, 1).toUpperCase()
        : '?';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: cs.outlineVariant.withOpacity(0.4)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.03),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top row: avatar + username + status pill
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          statusColor.withOpacity(0.25),
                          statusColor.withOpacity(0.08),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      firstLetter,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: statusColor,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          debt.debtorAdminUsername ?? 'مدير #${debt.debtorAdminId}',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Icon(Icons.calendar_month_rounded,
                                size: 11, color: cs.onSurfaceVariant),
                            const SizedBox(width: 3),
                            Text(
                              dateStr,
                              style: TextStyle(
                                fontSize: 11,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: statusColor.withOpacity(0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 6, height: 6,
                          decoration: BoxDecoration(
                            color: statusColor,
                            shape: BoxShape.circle,
                          ),
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
              const SizedBox(height: 12),
              // Progress bar
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 5,
                  backgroundColor: statusColor.withOpacity(0.12),
                  color: statusColor,
                ),
              ),
              const SizedBox(height: 8),
              // Amounts row
              Row(
                children: [
                  _InlineStat(
                    label: 'متبقي',
                    value: debt.remainingAmount,
                    color: debt.remainingAmount > 0 ? Colors.redAccent : Colors.green,
                  ),
                  const SizedBox(width: 12),
                  Container(width: 1, height: 16, color: cs.outlineVariant.withOpacity(0.4)),
                  const SizedBox(width: 12),
                  _InlineStat(
                    label: 'مسدّد',
                    value: debt.paidAmount,
                    color: Colors.green.shade700,
                  ),
                  const SizedBox(width: 12),
                  Container(width: 1, height: 16, color: cs.outlineVariant.withOpacity(0.4)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _InlineStat(
                      label: 'الأصلي',
                      value: debt.amount,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InlineStat extends StatelessWidget {
  final String label;
  final double value;
  final Color color;
  const _InlineStat({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: color.withOpacity(0.8),
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 1),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: AlignmentDirectional.centerStart,
          child: Text(
            AppHelpers.formatMoney(value),
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Create Debt Dialog (AlertDialog style) ────────────────────────────

class _CreateDebtDialog extends ConsumerStatefulWidget {
  final List<SubAdminRef> subAdmins;
  const _CreateDebtDialog({required this.subAdmins});

  @override
  ConsumerState<_CreateDebtDialog> createState() => _CreateDebtDialogState();
}

class _CreateDebtDialogState extends ConsumerState<_CreateDebtDialog> {
  int? _debtorId;
  final _amountCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  DateTime _date = DateTime.now();
  bool _saving = false;

  @override
  void dispose() {
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  double _parseAmount(String s) =>
      double.tryParse(s.replaceAll(',', '').trim()) ?? 0;

  void _addQuick(int delta) {
    final current = _parseAmount(_amountCtrl.text);
    final next = (current + delta).toStringAsFixed(0);
    _amountCtrl.text = _formatThousands(next);
    setState(() {});
  }

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
    if (_debtorId == null) {
      AppSnackBar.error(context, 'اختر المدير الفرعي');
      return;
    }
    final amt = _parseAmount(_amountCtrl.text);
    if (!amt.isFinite || amt <= 0) {
      AppSnackBar.error(context, 'أدخل مبلغ صحيح');
      return;
    }
    setState(() => _saving = true);
    final ok = await createManagerDebt(
      ref,
      debtorAdminId: _debtorId!,
      amount: amt,
      note: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
      debtDate: _date,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) {
      Navigator.pop(context, true);
    } else {
      AppSnackBar.error(context, 'تعذّر حفظ الدين');
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateStr = intl.DateFormat('y-MM-dd').format(_date);

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
      scrollable: true,
      title: const Text('إضافة دين جديد'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownButtonFormField<int>(
              value: _debtorId,
              decoration: const InputDecoration(
                labelText: 'المدير الفرعي',
                prefixIcon: Icon(Icons.person_outline),
                isDense: true,
                border: OutlineInputBorder(),
              ),
              items: widget.subAdmins
                  .map((s) => DropdownMenuItem<int>(
                        value: s.id,
                        child: Text(s.username),
                      ))
                  .toList(),
              onChanged: (v) => setState(() => _debtorId = v),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _amountCtrl,
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
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final v in const [5000, 10000, 25000, 50000, 100000, 250000])
                  ActionChip(
                    label: Text('+${_formatThousands(v.toString())}',
                        style: const TextStyle(fontSize: 12)),
                    onPressed: () => _addQuick(v),
                    visualDensity: VisualDensity.compact,
                  ),
                ActionChip(
                  label: const Text('مسح', style: TextStyle(fontSize: 12)),
                  onPressed: () { _amountCtrl.clear(); setState(() {}); },
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _noteCtrl,
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

// ─── Helpers (local duplicates kept minimal) ───────────────────────────

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
