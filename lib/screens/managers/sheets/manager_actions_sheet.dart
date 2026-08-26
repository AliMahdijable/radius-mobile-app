import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../api/managers_api.dart';
import '../../../core/util/format.dart';
import '../../../services/permissions_service.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';

/// نوع العملية المختارة من actions sheet. الـcaller (managers_screen)
/// يفتح الـsheet المناسب بناءً على القيمة المرجعة. مطابق v1
/// _ManagerActionType.
///
/// 2026-07-13: `labelKey` بدل `label` — النص يُترجم عند العرض عبر
/// `.tr()` (easy_localization) حتى يتبدّل مع اللغة.
enum ManagerAction {
  edit('managers.action_edit', LucideIcons.pencil, Color(0xFF3B82F6)),
  deposit('managers.action_deposit', LucideIcons.plus, Color(0xFF14B8A6)),
  withdraw('managers.action_withdraw', LucideIcons.circleMinus, Color(0xFFE08F2D)),
  payDebt('managers.action_pay_debt', LucideIcons.banknote, Color(0xFF0EA5E9)),
  addPoints('managers.action_add_points', LucideIcons.star, Color(0xFF8B5CF6)),
  otherDebts('managers.action_other_debts', LucideIcons.receipt, Color(0xFF0EA5E9)),
  movements('managers.action_movements', LucideIcons.activity, Color(0xFF14B8A6)),
  sendInfo('managers.action_send_info', LucideIcons.smartphone, Color(0xFF25D366)),
  delete('managers.action_delete', LucideIcons.trash2, Color(0xFFDC2626));

  const ManagerAction(this.labelKey, this.icon, this.color);
  final String labelKey;
  final IconData icon;
  final Color color;

  String get label => labelKey.tr();
}

/// مطلب 2026-06-12: actions sheet مطابق v1 (managers_screen.dart:880).
/// 9 عمليات مرئية كـgrid 4 أعمدة. الـsheet يرجع ManagerAction المختارة
/// والـcaller يفتح الـsheet المناسب.
Future<ManagerAction?> showManagerActionsSheet(
  BuildContext context,
  Manager manager, {
  double customDebt = 0,
}) {
  return showModalBottomSheet<ManagerAction>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => _ActionsSheet(manager: manager, customDebt: customDebt),
  );
}

class _ActionsSheet extends StatelessWidget {
  const _ActionsSheet({required this.manager, this.customDebt = 0});
  final Manager manager;
  /// دين تطبيقي (manager_debts) — يُدمج مع دين SAS4 لقرار "تسديد دين".
  /// 2026-08-26: bug-fix — مدير عليه دين تطبيقي فقط كان يفقد الزر.
  final double customDebt;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final totalDebt = (manager.debt ?? 0) + customDebt;
    final hasDebt = totalDebt > 0;
    final hasBalance = (manager.balance ?? 0) > 0;
    final hasPhone = (manager.mobile ?? '').isNotEmpty;
    // 9 actions — ترتيب مطابق v1.
    // مطلب 2026-06-11: كل action يختفي إذا الموظف ما عنده الصلاحية.
    // payDebt يستعمل managers.deposit (نفس الدور — تحويل من الـbalance
    // لتغطية الـdebt). otherDebts + movements + sendInfo افتراضياً
    // مرئية لو الـactor يقدر يشوف المدير أصلاً.
    final actions = <ManagerAction>[
      if (Perms.has('managers.edit')) ManagerAction.edit,
      if (Perms.has('managers.deposit')) ManagerAction.deposit,
      if (hasBalance && Perms.has('managers.withdraw'))
        ManagerAction.withdraw,
      if (hasDebt && Perms.has('managers.deposit')) ManagerAction.payDebt,
      if (Perms.has('managers.add_points')) ManagerAction.addPoints,
      if (Perms.has('reports.manager_debts')) ManagerAction.otherDebts,
      ManagerAction.movements,
      if (hasDebt && hasPhone && Perms.has('subscribers.send_whatsapp'))
        ManagerAction.sendInfo,
      if (Perms.has('managers.delete')) ManagerAction.delete,
    ];
    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
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
                          'managers.operations'.tr(),
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
                    'managers.chip_balance'.tr(
                        namedArgs: {'amount': formatIQD(manager.balance ?? 0)}),
                    AppColors.brand,
                  ),
                  if (hasDebt)
                    _summaryChip(
                      LucideIcons.alertTriangle,
                      'managers.chip_debt'.tr(
                          namedArgs: {'amount': formatIQD(totalDebt)}),
                      const Color(0xFFE08F2D),
                    ),
                  _summaryChip(
                    LucideIcons.users,
                    'managers.chip_subs'
                        .tr(namedArgs: {'n': '${manager.usersCount ?? 0}'}),
                    const Color(0xFF3B82F6),
                  ),
                ],
              ),
            ),
            const SizedBox(height: Sp.lg),
            // Actions grid — 4 cols. مطلب 2026-06-11: نفس تنسيق
            // عمليات المشتركين الجديد (subscriber_detail_screen
            // _OpCard) — دائرة ملوّنة 52dp + أيقونة بيضاء + ظل ناعم
            // بلون الدائرة + label تحت الزر بلون النص العادي.
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  Sp.lg, 0, Sp.lg, Sp.md),
              child: GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 4,
                crossAxisSpacing: 12,
                mainAxisSpacing: 14,
                childAspectRatio: 0.82,
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
    // مطابق subscriber_detail_screen _OpCard:
    //   دائرة ملوّنة 52dp + أيقونة بيضاء 22 + label تحتها بـtextHi.
    return InkResponse(
      onTap: () {
        HapticFeedback.selectionClick();
        Navigator.of(context).pop(action);
      },
      radius: 36,
      highlightShape: BoxShape.circle,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: action.color,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: action.color.withValues(alpha: 0.35),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            alignment: Alignment.center,
            child: Icon(action.icon, color: Colors.white, size: 22),
          ),
          const SizedBox(height: 7),
          Flexible(
            child: Text(
              action.label,
              style: AppType.label(color: AppColors.textHi).copyWith(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                height: 1.1,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}
