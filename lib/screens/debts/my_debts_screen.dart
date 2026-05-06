import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/helpers.dart';
import '../../models/manager_debt.dart';
import '../../providers/manager_debts_provider.dart';

/// Read-only view for any admin to see debts a parent admin has recorded
/// against them. Product decision: sub-admins don't record payments from
/// the app — they pay the parent in person, parent records it, push
/// notification confirms. So this screen is purely informational.
class MyDebtsScreen extends ConsumerWidget {
  const MyDebtsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncList = ref.watch(myDebtsProvider);
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('ديون عليّ')),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(myDebtsProvider),
        child: asyncList.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ListView(
            children: [
              const SizedBox(height: 80),
              Center(child: Text('خطأ: $e')),
            ],
          ),
          data: (list) {
            final open = list.where((d) => d.status != ManagerDebtStatus.paid).toList();
            final paid = list.where((d) => d.status == ManagerDebtStatus.paid).toList();

            if (list.isEmpty) {
              return ListView(
                children: [
                  const SizedBox(height: 80),
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(LucideIcons.circleCheck, size: 64, color: Colors.green.shade400),
                        const SizedBox(height: 12),
                        const Text('لا توجد ديون عليك',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 6),
                        Text(
                          'كل الديون المسجّلة عليك مسدّدة.',
                          style: TextStyle(color: cs.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            }

            final totalRemaining =
                open.fold<double>(0, (s, d) => s + d.remainingAmount);

            return ListView(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
              children: [
                // Summary card
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.redAccent.withOpacity(0.12), Colors.redAccent.withOpacity(0.02)],
                      begin: Alignment.topRight,
                      end: Alignment.bottomLeft,
                    ),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.redAccent.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      Icon(LucideIcons.wallet,
                          size: 32, color: Colors.redAccent),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('إجمالي المتبقي',
                                style: TextStyle(fontSize: 12, color: Colors.redAccent)),
                            const SizedBox(height: 4),
                            Text(
                              AppHelpers.formatMoney(totalRemaining),
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                color: Colors.redAccent,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text('${open.length} دين مفتوح',
                                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                if (open.isNotEmpty) ...[
                  Row(
                    children: [
                      const Text('مفتوح',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                      const SizedBox(width: 8),
                      Text('(${open.length})',
                          style: TextStyle(color: cs.onSurfaceVariant)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  for (final d in open)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _MyDebtCard(debt: d),
                    ),
                ],

                if (paid.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Text('مسدّد',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                      const SizedBox(width: 8),
                      Text('(${paid.length})',
                          style: TextStyle(color: cs.onSurfaceVariant)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  for (final d in paid)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _MyDebtCard(debt: d, faded: true),
                    ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _MyDebtCard extends StatelessWidget {
  final ManagerDebt debt;
  final bool faded;
  const _MyDebtCard({required this.debt, this.faded = false});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final statusColor = debt.status == ManagerDebtStatus.paid
        ? Colors.green
        : debt.status == ManagerDebtStatus.partial
            ? Colors.orange
            : Colors.redAccent;
    final opacity = faded ? 0.6 : 1.0;
    return Opacity(
      opacity: opacity,
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
            Row(
              children: [
                Expanded(
                  child: Text(
                    'من ${debt.parentAdminUsername ?? 'مدير #${debt.parentAdminId}'}',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
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
                    debtStatusLabel(debt.status),
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
            Row(
              children: [
                Text('متبقي ', style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
                Text(
                  AppHelpers.formatMoney(debt.remainingAmount),
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: debt.remainingAmount > 0 ? Colors.redAccent : Colors.green,
                  ),
                ),
                Text(
                  ' من ${AppHelpers.formatMoney(debt.amount)}',
                  style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant),
                ),
                const Spacer(),
                Text(
                  _shortDate(debt.debtDate),
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                ),
              ],
            ),
            if (debt.note != null) ...[
              const SizedBox(height: 4),
              Text(
                debt.note!,
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant, fontStyle: FontStyle.italic),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _shortDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
