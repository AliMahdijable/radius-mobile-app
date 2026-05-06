import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' as intl;

import '../../core/theme/app_theme.dart';
import '../../core/utils/helpers.dart';
import '../../models/manager_debt.dart';
import '../../models/manager_model.dart';
import '../../models/manager_movement.dart';
import '../../providers/manager_debts_provider.dart';
import '../../providers/manager_movements_provider.dart';
import '../../widgets/app_snackbar.dart';

/// Full-screen movements view per user request — replaces the old
/// bottom sheet, which was too cramped for the timeline + per-row
/// edit/delete affordances. Pushes onto the navigator from the
/// "حركات" action on the manager card.
class ManagerMovementsScreen extends ConsumerWidget {
  final ManagerModel manager;
  const ManagerMovementsScreen({super.key, required this.manager});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(managerMovementsProvider(manager.id));
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('حركات المدير'),
        actions: [
          IconButton(
            tooltip: 'تحديث',
            icon: const Icon(LucideIcons.refreshCw),
            onPressed: () =>
                ref.invalidate(managerMovementsProvider(manager.id)),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async =>
            ref.invalidate(managerMovementsProvider(manager.id)),
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(child: _Header(manager: manager)),
            async.when(
              loading: () => const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (_, __) => SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Text(
                    'تعذّر تحميل الحركات',
                    style: TextStyle(color: cs.onSurfaceVariant),
                  ),
                ),
              ),
              data: (movements) {
                if (movements.isEmpty) {
                  return SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              LucideIcons.inbox,
                              size: 56,
                              color: cs.onSurfaceVariant.withValues(alpha: 0.5),
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              'لا توجد حركات مسجّلة بعد',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }
                return SliverPadding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                  sliver: SliverList.separated(
                    itemCount: movements.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) => _MovementCard(
                      movement: movements[i],
                      targetAdminId: manager.id,
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends ConsumerWidget {
  final ManagerModel manager;
  const _Header({required this.manager});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    // Custom debts remaining for this specific manager — pulled from
    // the shared summary provider so we don't refetch.
    final summary = ref.watch(managerDebtsSummaryProvider);
    final customRemaining = summary.asData?.value.perDebtor
            .where((d) => d.debtorAdminId == manager.id)
            .fold<double>(0, (sum, d) => sum + d.totalRemaining) ??
        0;
    final totalDebt = manager.debt + customRemaining;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: cs.outline.withValues(alpha: 0.18)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: AppTheme.primary.withValues(alpha: 0.12),
                  child: const Icon(
                    LucideIcons.shield,
                    color: AppTheme.primary,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        manager.username,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (manager.fullName.isNotEmpty &&
                          manager.fullName != manager.username)
                        Text(
                          manager.fullName,
                          style: TextStyle(
                            fontSize: 12,
                            color: cs.onSurface.withValues(alpha: 0.65),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // Compact 4-pill grid: balance, SAS debt, other debts, total
            // — laid out as a 2-column wrap so they stay readable on
            // small phones without overflowing.
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _StatPill(
                  icon: LucideIcons.wallet,
                  label: 'الرصيد',
                  amount: manager.credit,
                  color: AppTheme.successColor,
                ),
                _StatPill(
                  icon: LucideIcons.banknote,
                  label: 'دين الساس',
                  amount: manager.debt,
                  color: AppTheme.warningColor,
                ),
                _StatPill(
                  icon: LucideIcons.receipt,
                  label: 'ديون أخرى',
                  amount: customRemaining,
                  color: AppTheme.infoColor,
                ),
                _StatPill(
                  icon: LucideIcons.fileText,
                  label: 'مجموع الديون',
                  amount: totalDebt,
                  color: AppTheme.dangerColor,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final double amount;
  final Color color;
  const _StatPill({
    required this.icon,
    required this.label,
    required this.amount,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.30)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            _money(amount),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// One row in the timeline. Same content as the bottom-sheet row but
/// with more breathing room and an inline action menu.
class _MovementCard extends ConsumerWidget {
  final ManagerMovement movement;
  final int targetAdminId;
  const _MovementCard({required this.movement, required this.targetAdminId});

  ({String title, IconData icon, Color color, String sign}) _decorate() {
    switch (movement.rowType) {
      case 'balance':
        switch (movement.subKind) {
          case 'deposit_cash':
            return (
              title: 'إضافة رصيد نقدي',
              icon: LucideIcons.plus,
              color: AppTheme.successColor,
              sign: '+',
            );
          case 'deposit_loan':
            return (
              title: 'إضافة رصيد آجل',
              icon: LucideIcons.plus,
              color: AppTheme.warningColor,
              sign: '+',
            );
          case 'withdraw':
            return (
              title: 'سحب رصيد',
              icon: LucideIcons.circleMinus,
              color: AppTheme.dangerColor,
              sign: '-',
            );
          case 'points':
            return (
              title: 'نقاط',
              icon: LucideIcons.star,
              color: AppTheme.secondary,
              sign: '+',
            );
          case 'sas_pay_debt':
            return (
              title: 'تسديد دين الساس',
              icon: LucideIcons.banknote,
              color: AppTheme.warningColor,
              sign: '-',
            );
        }
        return (
          title: 'حركة',
          icon: LucideIcons.zap,
          color: AppTheme.primary,
          sign: '',
        );
      case 'debt_created':
        return (
          title: 'دين جديد',
          icon: LucideIcons.receipt,
          color: AppTheme.infoColor,
          sign: '+',
        );
      case 'debt_payment':
        return (
          title: 'تسديد دين آخر',
          icon: LucideIcons.banknote,
          color: AppTheme.infoColor,
          sign: '-',
        );
      default:
        return (
          title: movement.rowType,
          icon: LucideIcons.circleQuestionMark,
          color: AppTheme.primary,
          sign: '',
        );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final d = _decorate();
    final dateFmt = intl.DateFormat('yyyy-MM-dd  HH:mm');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: d.color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: d.color.withValues(alpha: 0.20)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: d.color.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(d.icon, size: 20, color: d.color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        d.title,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      '${d.sign}${_money(movement.amount)}',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: d.color,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(
                      LucideIcons.clock,
                      size: 12,
                      color: cs.onSurface.withValues(alpha: 0.55),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      dateFmt.format(movement.eventAt),
                      style: TextStyle(
                        fontSize: 11,
                        color: cs.onSurface.withValues(alpha: 0.65),
                      ),
                    ),
                    if (movement.source != null) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerHighest
                              .withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          movement.source == 'sas4' ? 'الساس' : 'يدوي',
                          style: TextStyle(
                            fontSize: 10,
                            color: cs.onSurface.withValues(alpha: 0.65),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                if (movement.note != null && movement.note!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      movement.note!,
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurface.withValues(alpha: 0.75),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          _MovementMenu(
            movement: movement,
            targetAdminId: targetAdminId,
            color: d.color,
          ),
        ],
      ),
    );
  }
}

/// Three-dot menu identical to the old sheet version but now used on
/// the full screen. Edit-amount support added for balance rows so the
/// admin can fix a typo without leaving the timeline.
class _MovementMenu extends ConsumerWidget {
  final ManagerMovement movement;
  final int targetAdminId;
  final Color color;
  const _MovementMenu({
    required this.movement,
    required this.targetAdminId,
    required this.color,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<String>(
      tooltip: 'خيارات',
      icon: Icon(
        LucideIcons.ellipsisVertical,
        size: 20,
        color: color.withValues(alpha: 0.7),
      ),
      onSelected: (action) => _handle(context, ref, action),
      itemBuilder: (_) {
        switch (movement.rowType) {
          case 'balance':
            return const [
              PopupMenuItem(
                value: 'edit_balance',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(LucideIcons.pencil, size: 18),
                  title: Text('تعديل المبلغ والملاحظة'),
                ),
              ),
              PopupMenuItem(
                value: 'delete_balance',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(LucideIcons.trash2, size: 18),
                  title: Text('حذف من السجل'),
                ),
              ),
            ];
          case 'debt_created':
            return const [
              PopupMenuItem(
                value: 'edit_debt',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(LucideIcons.pencil, size: 18),
                  title: Text('تعديل الدين'),
                ),
              ),
              PopupMenuItem(
                value: 'delete_debt',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(LucideIcons.trash2, size: 18),
                  title: Text('حذف الدين'),
                ),
              ),
            ];
          case 'debt_payment':
            return const [
              PopupMenuItem(
                value: 'delete_payment',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(LucideIcons.trash2, size: 18),
                  title: Text('حذف التسديد'),
                ),
              ),
            ];
          default:
            return const [];
        }
      },
    );
  }

  Future<void> _handle(BuildContext context, WidgetRef ref, String action) async {
    switch (action) {
      case 'edit_balance':
        await _editBalance(context, ref);
        break;
      case 'delete_balance':
        await _deleteBalance(context, ref);
        break;
      case 'edit_debt':
        await _editDebt(context, ref);
        break;
      case 'delete_debt':
        await _deleteDebt(context, ref);
        break;
      case 'delete_payment':
        await _deletePayment(context, ref);
        break;
    }
  }

  Future<void> _editBalance(BuildContext context, WidgetRef ref) async {
    final amountCtrl = TextEditingController(
      text: movement.amount.toStringAsFixed(0),
    );
    final noteCtrl = TextEditingController(text: movement.note ?? '');
    final saved = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        title: const Text('تعديل الحركة'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: amountCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: 'المبلغ',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: noteCtrl,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'ملاحظة',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'ملاحظة: تعديل المبلغ هنا يُحدّث سجل التطبيق فقط ولا يغيّر رصيد المدير على نظام الساس.',
                style: TextStyle(fontSize: 11, color: Colors.redAccent),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dctx).pop(false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dctx).pop(true),
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
    if (saved != true) return;
    final amt = double.tryParse(amountCtrl.text.trim());
    if (amt == null || amt < 0) {
      if (context.mounted) AppSnackBar.warning(context, 'مبلغ غير صالح');
      return;
    }
    final ok = await updateBalanceMovement(
      ref,
      movement.id,
      amount: amt,
      note: noteCtrl.text,
    );
    if (!context.mounted) return;
    if (ok) {
      ref.invalidate(managerMovementsProvider(targetAdminId));
      AppSnackBar.success(context, 'تم التعديل');
    } else {
      AppSnackBar.error(context, 'تعذّر التعديل');
    }
  }

  Future<void> _deleteBalance(BuildContext context, WidgetRef ref) async {
    final confirmed = await _confirmDelete(
      context,
      title: 'حذف من السجل',
      message:
          'هذا الحذف يزيل الحركة من سجل التطبيق فقط — لا يُعيد المبلغ على نظام الساس.',
    );
    if (confirmed != true) return;
    final ok = await deleteBalanceMovement(ref, movement.id);
    if (!context.mounted) return;
    if (ok) {
      ref.invalidate(managerMovementsProvider(targetAdminId));
      AppSnackBar.success(context, 'تم الحذف من السجل');
    } else {
      AppSnackBar.error(context, 'تعذّر الحذف');
    }
  }

  Future<void> _editDebt(BuildContext context, WidgetRef ref) async {
    if (movement.debtId == null) return;
    final amountCtrl = TextEditingController(
      text: movement.amount.toStringAsFixed(0),
    );
    final noteCtrl = TextEditingController(text: movement.note ?? '');
    final saved = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        title: const Text('تعديل الدين'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: amountCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: 'المبلغ',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: noteCtrl,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'الملاحظة',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dctx).pop(false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dctx).pop(true),
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
    if (saved != true) return;
    final amt = double.tryParse(amountCtrl.text.trim());
    final ok = await updateManagerDebt(
      ref,
      movement.debtId!,
      amount: amt,
      note: noteCtrl.text,
    );
    if (!context.mounted) return;
    if (ok) {
      ref.invalidate(managerMovementsProvider(targetAdminId));
      AppSnackBar.success(context, 'تم التعديل');
    } else {
      AppSnackBar.error(context, 'تعذّر التعديل');
    }
  }

  Future<void> _deleteDebt(BuildContext context, WidgetRef ref) async {
    if (movement.debtId == null) return;
    final confirmed = await _confirmDelete(
      context,
      title: 'حذف الدين',
      message: 'سيتم حذف الدين وكل تسديداته المرتبطة. لا يمكن التراجع.',
    );
    if (confirmed != true) return;
    final ok = await deleteManagerDebt(ref, movement.debtId!);
    if (!context.mounted) return;
    if (ok) {
      ref.invalidate(managerMovementsProvider(targetAdminId));
      AppSnackBar.success(context, 'تم حذف الدين');
    } else {
      AppSnackBar.error(context, 'تعذّر الحذف');
    }
  }

  Future<void> _deletePayment(BuildContext context, WidgetRef ref) async {
    if (movement.relatedDebtId == null) return;
    final confirmed = await _confirmDelete(
      context,
      title: 'حذف التسديد',
      message: 'سيُعاد احتساب رصيد الدين بدون هذا التسديد. متابعة؟',
    );
    if (confirmed != true) return;
    final ok = await deleteManagerDebtPayment(
      ref,
      movement.id,
      movement.relatedDebtId!,
    );
    if (!context.mounted) return;
    if (ok) {
      ref.invalidate(managerMovementsProvider(targetAdminId));
      AppSnackBar.success(context, 'تم حذف التسديد');
    } else {
      AppSnackBar.error(context, 'تعذّر الحذف');
    }
  }

  Future<bool?> _confirmDelete(
    BuildContext context, {
    required String title,
    required String message,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dctx).pop(false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.dangerColor,
            ),
            onPressed: () => Navigator.of(dctx).pop(true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
  }
}

String _money(num value) => AppHelpers.formatMoney(value);
