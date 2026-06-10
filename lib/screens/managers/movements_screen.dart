import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../api/manager_movements_api.dart';
import '../../api/managers_api.dart';
import '../../core/util/format.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';

/// شاشة سجل الحركات المالية على المدير الفرعي. مطابق v1
/// manager_movements_screen — قائمة مرتّبة زمنياً بالنوع + المبلغ
/// + الملاحظة + الفاعل + إجراء حذف.
class ManagerMovementsScreen extends StatefulWidget {
  const ManagerMovementsScreen({super.key, required this.manager});
  final Manager manager;

  @override
  State<ManagerMovementsScreen> createState() =>
      _ManagerMovementsScreenState();
}

class _ManagerMovementsScreenState extends State<ManagerMovementsScreen> {
  List<ManagerMovement> _rows = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final list = await ManagerMovementsApi.list(widget.manager.id);
    if (!mounted) return;
    setState(() {
      _rows = list;
      _loading = false;
    });
  }

  Future<void> _confirmDelete(ManagerMovement m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('حذف الحركة'),
        content: Text(
          'حذف ${m.kind.label} (${formatIQD(m.amount)} د.ع) من السجل؟ '
          'هذا لا يعكس العملية في SAS4 — فقط حذف من سجل التطبيق.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('إلغاء')),
          FilledButton(
            style:
                FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final r = await ManagerMovementsApi.delete(m.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(r.ok ? 'تم الحذف' : (r.message ?? 'تعذّر الحذف')),
        backgroundColor: r.ok ? AppColors.brand : AppColors.error,
        behavior: SnackBarBehavior.floating,
      ),
    );
    if (r.ok) _load();
  }

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFF14B8A6);
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          'حركات ${widget.manager.username}',
          style: AppType.title(color: AppColors.textHi)
              .copyWith(fontSize: 16),
        ),
        iconTheme: const IconThemeData(color: AppColors.textHi),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          color: accent,
          child: ListView(
            padding:
                const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, Sp.huge),
            children: [
              if (_loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_rows.isEmpty)
                Container(
                  padding: const EdgeInsets.all(Sp.huge),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(R.lg),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    children: [
                      const Icon(LucideIcons.activity,
                          size: 36, color: AppColors.textLow),
                      const SizedBox(height: 10),
                      Text(
                        'لا توجد حركات مسجَّلة',
                        style: AppType.muted(color: AppColors.textHi)
                            .copyWith(fontSize: 13),
                      ),
                    ],
                  ),
                )
              else
                Column(
                  children: [
                    for (final m in _rows) ...[
                      _MovementTile(
                        movement: m,
                        onDelete: () => _confirmDelete(m),
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
}

class _MovementTile extends StatelessWidget {
  const _MovementTile({required this.movement, required this.onDelete});
  final ManagerMovement movement;
  final VoidCallback onDelete;

  Color get _color {
    switch (movement.kind) {
      case MovementKind.depositCash:
      case MovementKind.debtPayment:
        return AppColors.brand;
      case MovementKind.withdraw:
      case MovementKind.sasPayDebt:
        return const Color(0xFFE08F2D);
      case MovementKind.depositLoan:
      case MovementKind.debtCreated:
        return AppColors.error;
      case MovementKind.addPoints:
        return const Color(0xFF8B5CF6);
      case MovementKind.unknown:
        return AppColors.textMid;
    }
  }

  IconData get _icon {
    switch (movement.kind) {
      case MovementKind.depositCash:
        return LucideIcons.arrowUpToLine;
      case MovementKind.depositLoan:
        return LucideIcons.handCoins;
      case MovementKind.withdraw:
        return LucideIcons.arrowDownToLine;
      case MovementKind.sasPayDebt:
        return LucideIcons.banknote;
      case MovementKind.addPoints:
        return LucideIcons.star;
      case MovementKind.debtCreated:
        return LucideIcons.receipt;
      case MovementKind.debtPayment:
        return LucideIcons.check;
      case MovementKind.unknown:
        return LucideIcons.activity;
    }
  }

  String _humanDate() {
    final iso = movement.createdAt;
    if (iso == null || iso.isEmpty) return '';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return iso;
    String two(int n) => n.toString().padLeft(2, '0');
    return '${dt.year}/${two(dt.month)}/${two(dt.day)} ${two(dt.hour)}:${two(dt.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.lg),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: _color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(R.md),
            ),
            alignment: Alignment.center,
            child: Icon(_icon, size: 16, color: _color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      movement.kind.label,
                      style: AppType.title(color: AppColors.textHi)
                          .copyWith(fontSize: 13),
                    ),
                    const Spacer(),
                    Text(
                      '${movement.isCredit ? '+' : '-'}${formatIQD(movement.amount)}',
                      style: AppType.label(color: _color)
                          .copyWith(
                              fontSize: 14, fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                if (_humanDate().isNotEmpty)
                  Text(
                    _humanDate(),
                    style: AppType.muted().copyWith(fontSize: 10.5),
                  ),
                if ((movement.note ?? '').trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    movement.note!.trim(),
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
            radius: 18,
            child: Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(LucideIcons.trash2,
                  size: 13, color: AppColors.error),
            ),
          ),
        ],
      ),
    );
  }
}
