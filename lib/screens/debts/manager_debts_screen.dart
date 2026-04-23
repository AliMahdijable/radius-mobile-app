import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/helpers.dart';
import '../../models/manager_debt.dart';
import '../../providers/manager_debts_provider.dart';
import '../../widgets/app_snackbar.dart';
import 'manager_debt_detail_screen.dart';

/// Parent-admin ledger of debts owed BY sub-admins. Only rendered if
/// the /access gate returned hasSubAdmins=true — the drawer already
/// hides the entry when it's false, but we also guard here in case
/// someone navigates directly.
class ManagerDebtsScreen extends ConsumerStatefulWidget {
  const ManagerDebtsScreen({super.key});

  @override
  ConsumerState<ManagerDebtsScreen> createState() => _ManagerDebtsScreenState();
}

class _ManagerDebtsScreenState extends ConsumerState<ManagerDebtsScreen> {
  String? _statusFilter; // null = all
  int? _debtorFilter;    // null = all sub-admins

  DebtsFilterArgs get _args =>
      DebtsFilterArgs(status: _statusFilter, debtorAdminId: _debtorFilter);

  @override
  Widget build(BuildContext context) {
    final access = ref.watch(managerDebtsAccessProvider);
    final summary = ref.watch(managerDebtsSummaryProvider);
    final list = ref.watch(managerDebtsListProvider(_args));
    final cs = Theme.of(context).colorScheme;

    // Access gate — wait for check, then show empty state if no sub-admins.
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
          appBar: AppBar(title: const Text('ديون المدراء')),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _openCreateSheet(context, acc.subAdmins),
            icon: const Icon(Icons.add),
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
                SliverToBoxAdapter(child: _SummaryStrip(asyncSummary: summary)),
                SliverToBoxAdapter(
                  child: _FilterBar(
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
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.inbox_outlined,
                                  size: 48, color: cs.onSurfaceVariant),
                              const SizedBox(height: 8),
                              const Text('لا توجد ديون بالفلتر الحالي'),
                            ],
                          ),
                        ),
                      );
                    }
                    return SliverPadding(
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 96),
                      sliver: SliverList.separated(
                        itemCount: debts.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (_, i) => _DebtCard(
                          debt: debts[i],
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => ManagerDebtDetailScreen(
                                debt: debts[i],
                              ),
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

  Future<void> _openCreateSheet(
      BuildContext context, List<SubAdminRef> subAdmins) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _DebtFormSheet(subAdmins: subAdmins),
    );
    if (saved == true && mounted) {
      AppSnackBar.success(context, 'تم إضافة الدين');
    }
  }
}

// ─── Summary strip (4 chips) ───────────────────────────────────────────

class _SummaryStrip extends StatelessWidget {
  final AsyncValue<ManagerDebtsSummary> asyncSummary;
  const _SummaryStrip({required this.asyncSummary});

  @override
  Widget build(BuildContext context) {
    final s = asyncSummary.asData?.value ?? ManagerDebtsSummary.empty;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Row(
        children: [
          _Stat(label: 'المتبقي', value: s.totalRemaining, color: Colors.redAccent),
          _Stat(label: 'المسدّد', value: s.totalPaid, color: Colors.green),
          _Stat(label: 'الأصلي', value: s.totalAmount, color: Colors.blueAccent),
          _Stat(
            label: 'عدد المدراء',
            valueText: s.debtorsCount.toString(),
            color: Colors.purple,
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final double? value;
  final String? valueText;
  final Color color;
  const _Stat({required this.label, this.value, this.valueText, required this.color});

  @override
  Widget build(BuildContext context) {
    final text = valueText ??
        (value == null ? '0' : AppHelpers.formatMoney(value));
    return Container(
      margin: const EdgeInsets.only(left: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
          Text(
            text,
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: color),
          ),
        ],
      ),
    );
  }
}

// ─── Filter bar (status chips + debtor dropdown) ───────────────────────

class _FilterBar extends StatelessWidget {
  final String? statusFilter;
  final int? debtorFilter;
  final List<SubAdminRef> subAdmins;
  final ValueChanged<String?> onStatus;
  final ValueChanged<int?> onDebtor;
  const _FilterBar({
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
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _chip(context, 'الكل', statusFilter == null,
                    () => onStatus(null)),
                _chip(context, 'مفتوح', statusFilter == 'open',
                    () => onStatus('open')),
                _chip(context, 'جزئي', statusFilter == 'partial',
                    () => onStatus('partial')),
                _chip(context, 'مسدّد', statusFilter == 'paid',
                    () => onStatus('paid')),
              ],
            ),
          ),
          if (subAdmins.isNotEmpty) ...[
            const SizedBox(height: 6),
            DropdownButtonFormField<int?>(
              value: debtorFilter,
              isDense: true,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.person_outline, size: 18),
                hintText: 'فلترة حسب المدير الفرعي',
                contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                filled: true,
                fillColor: cs.surfaceContainerHighest.withOpacity(0.3),
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
      ),
    );
  }
}

// ─── 2-line debt card ──────────────────────────────────────────────────

class _DebtCard extends StatelessWidget {
  final ManagerDebt debt;
  final VoidCallback onTap;
  const _DebtCard({required this.debt, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final statusColor = _statusColor(debt.status);
    final statusLabel = debtStatusLabel(debt.status);
    final dateText = _shortDate(debt.debtDate);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withOpacity(0.3),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: cs.outlineVariant.withOpacity(0.5)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Line 1: name + status chip
            Row(
              children: [
                Expanded(
                  child: Text(
                    debt.debtorAdminUsername ?? 'مدير #${debt.debtorAdminId}',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    statusLabel,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: statusColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            // Line 2: amounts + date
            DefaultTextStyle(
              style: TextStyle(
                fontSize: 12.5,
                color: cs.onSurfaceVariant,
              ),
              child: Row(
                children: [
                  Text(
                    'متبقي ',
                    style: TextStyle(color: cs.onSurfaceVariant),
                  ),
                  Text(
                    AppHelpers.formatMoney(debt.remainingAmount),
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: debt.remainingAmount > 0 ? Colors.redAccent : Colors.green,
                    ),
                  ),
                  Text(' من ${AppHelpers.formatMoney(debt.amount)}'),
                  const Spacer(),
                  Icon(Icons.event, size: 13, color: cs.onSurfaceVariant),
                  const SizedBox(width: 3),
                  Text(dateText),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

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

  String _shortDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

// ─── Add-debt bottom sheet ─────────────────────────────────────────────

class _DebtFormSheet extends ConsumerStatefulWidget {
  final List<SubAdminRef> subAdmins;
  const _DebtFormSheet({required this.subAdmins});

  @override
  ConsumerState<_DebtFormSheet> createState() => _DebtFormSheetState();
}

class _DebtFormSheetState extends ConsumerState<_DebtFormSheet> {
  final _formKey = GlobalKey<FormState>();
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
                        'إضافة دين جديد',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  value: _debtorId,
                  decoration: const InputDecoration(
                    labelText: 'المدير الفرعي',
                    prefixIcon: Icon(Icons.person_outline),
                    border: OutlineInputBorder(),
                  ),
                  items: widget.subAdmins
                      .map((s) => DropdownMenuItem<int>(
                            value: s.id,
                            child: Text(s.username),
                          ))
                      .toList(),
                  validator: (v) => v == null ? 'اختر المدير الفرعي' : null,
                  onChanged: (v) => setState(() => _debtorId = v),
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
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save_outlined),
                    label: Text(_saving ? 'جاري الحفظ...' : 'حفظ'),
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
    final ok = await createManagerDebt(
      ref,
      debtorAdminId: _debtorId!,
      amount: double.parse(_amountCtrl.text.trim()),
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
}
