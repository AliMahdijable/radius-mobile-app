import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../api/manager_movements_api.dart';
import '../../api/managers_api.dart';
import '../../core/util/format.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';

/// Unified manager movements timeline — مطابق v1
/// mobile-app/lib/screens/managers/manager_movements_screen.dart.
///
/// The backend stitches three row types into one descending feed:
/// `balance` (deposits, withdraws, points, sas pay-debt), `debt_created`
/// (parent recorded a new custom debt), `debt_payment` (any payment
/// against a custom debt). Each row is editable / deletable depending
/// on its type.
class ManagerMovementsScreen extends StatefulWidget {
  const ManagerMovementsScreen({super.key, required this.manager});
  final Manager manager;

  @override
  State<ManagerMovementsScreen> createState() => _ManagerMovementsScreenState();
}

class _ManagerMovementsScreenState extends State<ManagerMovementsScreen> {
  bool _loading = true;
  List<ManagerMovement> _rows = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final list =
        await ManagerMovementsApi.list(targetAdminId: widget.manager.id);
    if (!mounted) return;
    setState(() {
      _rows = list;
      _loading = false;
    });
  }

  Future<void> _editBalance(ManagerMovement m) async {
    final noteCtrl = TextEditingController(text: m.note ?? '');
    final amountCtrl = TextEditingController(
      text: m.amount > 0 ? m.amount.toInt().toString() : '',
    );
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('تعديل ${m.arabicLabel}',
            style: AppType.title(color: AppColors.textHi)
                .copyWith(fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: amountCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'المبلغ',
                helperText: 'تعديل المبلغ يحدّث السجل فقط — لا يُعكَس على الساس',
                helperMaxLines: 2,
              ),
            ),
            const SizedBox(height: Sp.sm),
            TextField(
              controller: noteCtrl,
              decoration: const InputDecoration(labelText: 'الملاحظة'),
              minLines: 1,
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
    if (saved != true || !mounted) return;
    final newAmt =
        num.tryParse(amountCtrl.text.replaceAll(',', '').trim()) ?? m.amount;
    final r = await ManagerMovementsApi.update(
      id: m.id,
      note: noteCtrl.text.trim(),
      amount: newAmt == m.amount ? null : newAmt,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(r.ok ? 'تم التعديل' : (r.message ?? 'تعذّر التعديل')),
        backgroundColor: r.ok ? AppColors.brand : AppColors.error,
      ),
    );
    if (r.ok) _load();
  }

  Future<void> _confirmDelete(ManagerMovement m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('حذف من السجل'),
        content: Text(
          'حذف ${m.arabicLabel} بقيمة ${formatIQD(m.amount)} د.ع؟\n\n'
          'هذا يحذف القيد من سجل التطبيق فقط — لا يُعيد المبلغ على SAS4. '
          'استعمل عملية معاكسة (إيداع/سحب) لتصحيح الرصيد الفعلي.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final r = await ManagerMovementsApi.delete(m.id);
    if (!mounted) return;
    if (r.ok) _load();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(r.ok ? 'تم الحذف' : (r.message ?? 'تعذّر الحذف')),
        backgroundColor: r.ok ? AppColors.brand : AppColors.error,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        foregroundColor: AppColors.textHi,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        iconTheme: IconThemeData(color: AppColors.textHi),
        title: Text(
          'حركات ${widget.manager.username}',
          style: AppType.title(color: AppColors.textHi)
              .copyWith(fontSize: 16),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _rows.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(Sp.huge),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(LucideIcons.activity,
                              size: 36, color: AppColors.textLow),
                          const SizedBox(height: 10),
                          Text(
                            'لا توجد حركات بعد',
                            style: AppType.label(color: AppColors.textMid),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(Sp.lg),
                    itemCount: _rows.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) => _MovementCard(
                      movement: _rows[i],
                      onEdit: _rows[i].rowType == 'balance'
                          ? () => _editBalance(_rows[i])
                          : null,
                      onDelete: () => _confirmDelete(_rows[i]),
                    ),
                  ),
      ),
    );
  }
}

class _MovementCard extends StatelessWidget {
  const _MovementCard({
    required this.movement,
    required this.onDelete,
    this.onEdit,
  });
  final ManagerMovement movement;
  final VoidCallback onDelete;
  final VoidCallback? onEdit;

  ({IconData icon, Color color}) get _style {
    if (movement.rowType == 'debt_created') {
      return (icon: LucideIcons.receipt, color: const Color(0xFF0EA5E9));
    }
    if (movement.rowType == 'debt_payment') {
      return (icon: LucideIcons.banknote, color: const Color(0xFF0EA5E9));
    }
    switch (movement.subKind) {
      case 'deposit_cash':
        return (icon: LucideIcons.plus, color: const Color(0xFF14B8A6));
      case 'deposit_loan':
        return (icon: LucideIcons.plus, color: const Color(0xFFE08F2D));
      case 'withdraw':
        return (icon: LucideIcons.circleMinus, color: AppColors.error);
      case 'points':
        return (icon: LucideIcons.star, color: const Color(0xFF8B5CF6));
      case 'sas_pay_debt':
        return (icon: LucideIcons.banknote, color: const Color(0xFFE08F2D));
      default:
        return (icon: LucideIcons.activity, color: AppColors.textMid);
    }
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final style = _style;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.md),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.symmetric(
          horizontal: Sp.md, vertical: Sp.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: style.color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: Icon(style.icon, color: style.color, size: 18),
          ),
          const SizedBox(width: Sp.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        movement.arabicLabel,
                        style: AppType.label(color: AppColors.textHi)
                            .copyWith(fontWeight: FontWeight.w800),
                      ),
                    ),
                    Text(
                      '${movement.signLabel}${formatIQD(movement.amount)}',
                      style: TextStyle(
                        color: style.color,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  _fmtTime(movement.eventAt),
                  style: AppType.muted(color: AppColors.textLow)
                      .copyWith(fontSize: 11),
                ),
                if ((movement.note ?? '').trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    movement.note!.trim(),
                    style: AppType.muted(color: AppColors.textMid)
                        .copyWith(fontSize: 12),
                  ),
                ],
                if (movement.source != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceInput,
                        borderRadius: BorderRadius.circular(R.sm),
                      ),
                      child: Text(
                        movement.source == MovementSource.sas4
                            ? 'الساس'
                            : 'يدوي',
                        style: AppType.muted(color: AppColors.textMid)
                            .copyWith(fontSize: 10),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            icon: Icon(LucideIcons.ellipsisVertical,
                size: 16, color: AppColors.textMid),
            onSelected: (v) {
              if (v == 'edit' && onEdit != null) onEdit!();
              if (v == 'delete') onDelete();
            },
            itemBuilder: (_) => [
              if (onEdit != null)
                const PopupMenuItem(
                  value: 'edit',
                  child: Row(children: [
                    Icon(LucideIcons.pencil, size: 14),
                    SizedBox(width: 6),
                    Text('تعديل'),
                  ]),
                ),
              const PopupMenuItem(
                value: 'delete',
                child: Row(children: [
                  Icon(LucideIcons.trash2, size: 14),
                  SizedBox(width: 6),
                  Text('حذف من السجل'),
                ]),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Baghdad-time DateTime → "yyyy-MM-dd HH:mm". The API already added
/// +3h so the value lands on the correct civil time; we just need to
/// strip the timezone marker and format.
String _fmtTime(DateTime t) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
}
