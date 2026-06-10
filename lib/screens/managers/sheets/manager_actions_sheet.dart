import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../api/managers_api.dart';
import '../../../core/util/format.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';

/// نوع العملية المختارة من actions sheet. الـcaller (managers_screen)
/// يفتح الـsheet المناسب بناءً على القيمة المرجعة. مطابق v1
/// _ManagerActionType.
enum ManagerAction {
  edit('تعديل', LucideIcons.pencil, Color(0xFF3B82F6)),
  deposit('شحن', LucideIcons.plus, Color(0xFF14B8A6)),
  withdraw('سحب', LucideIcons.circleMinus, Color(0xFFE08F2D)),
  payDebt('تسديد دين', LucideIcons.banknote, Color(0xFF0EA5E9)),
  addPoints('نقاط', LucideIcons.star, Color(0xFF8B5CF6)),
  otherDebts('ديون أخرى', LucideIcons.receipt, Color(0xFF0EA5E9)),
  movements('حركات', LucideIcons.activity, Color(0xFF14B8A6)),
  sendInfo('إرسال معلومات', LucideIcons.smartphone, Color(0xFF25D366)),
  delete('حذف', LucideIcons.trash2, Color(0xFFDC2626));

  const ManagerAction(this.label, this.icon, this.color);
  final String label;
  final IconData icon;
  final Color color;
}

/// مطلب 2026-06-12: actions sheet مطابق v1 (managers_screen.dart:880).
/// 9 عمليات مرئية كـgrid 4 أعمدة. الـsheet يرجع ManagerAction المختارة
/// والـcaller يفتح الـsheet المناسب.
Future<ManagerAction?> showManagerActionsSheet(
  BuildContext context,
  Manager manager,
) {
  return showModalBottomSheet<ManagerAction>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => _ActionsSheet(manager: manager),
  );
}

class _ActionsSheet extends StatelessWidget {
  const _ActionsSheet({required this.manager});
  final Manager manager;

  @override
  Widget build(BuildContext context) {
    final hasDebt = (manager.debt ?? 0) > 0;
    final hasBalance = (manager.balance ?? 0) > 0;
    final hasPhone = (manager.mobile ?? '').isNotEmpty;
    // 9 actions — ترتيب مطابق v1.
    final actions = <ManagerAction>[
      ManagerAction.edit,
      ManagerAction.deposit,
      if (hasBalance) ManagerAction.withdraw,
      if (hasDebt) ManagerAction.payDebt,
      ManagerAction.addPoints,
      ManagerAction.otherDebts,
      ManagerAction.movements,
      if (hasDebt && hasPhone) ManagerAction.sendInfo,
      ManagerAction.delete,
    ];
    return SafeArea(
      top: false,
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Header — name + quick summary
            Padding(
              padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, 0),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: const Color(0xFF3B82F6)
                          .withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(R.md),
                    ),
                    alignment: Alignment.center,
                    child: const Icon(LucideIcons.shield,
                        size: 18, color: Color(0xFF3B82F6)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          manager.username,
                          style: AppType.title(color: AppColors.textHi)
                              .copyWith(fontSize: 15),
                        ),
                        Text(
                          'العمليات',
                          style: AppType.muted().copyWith(fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // Summary chips
            Padding(
              padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, 0),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _summaryChip(
                    LucideIcons.wallet,
                    'رصيد ${formatIQD(manager.balance ?? 0)}',
                    AppColors.brand,
                  ),
                  if (hasDebt)
                    _summaryChip(
                      LucideIcons.alertTriangle,
                      'دين ${formatIQD(manager.debt!)}',
                      const Color(0xFFE08F2D),
                    ),
                  _summaryChip(
                    LucideIcons.users,
                    '${manager.usersCount ?? 0} مشترك',
                    const Color(0xFF3B82F6),
                  ),
                ],
              ),
            ),
            const SizedBox(height: Sp.md),
            // Actions grid — 4 cols. مطلب 2026-06-12: نفس تنسيق
            // عمليات المشتركين (subscriber_detail_screen _OpCard) —
            // خلفية بيضاء + حدود رفيعة + ظل ناعم، بدون tinted box
            // للأيقونة.
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  Sp.lg, 0, Sp.lg, Sp.md),
              child: GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 4,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
                childAspectRatio: 0.92,
                children: [
                  for (final a in actions) _actionTile(context, a),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryChip(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(R.sm),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionTile(BuildContext context, ManagerAction action) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(R.md),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          Navigator.of(context).pop(action);
        },
        borderRadius: BorderRadius.circular(R.md),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(R.md),
            border: Border.all(color: AppColors.border),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.02),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 4),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(action.icon, color: action.color, size: 18),
              const SizedBox(height: 4),
              Flexible(
                child: Text(
                  action.label,
                  style: AppType.label(color: action.color).copyWith(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    height: 1.05,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
