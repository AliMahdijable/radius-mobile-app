import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../api/managers_api.dart';
import '../../../core/util/format.dart';
import '../../../services/permissions_service.dart';
import '../../../core/widgets/design_sheet.dart';
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
  edit('managers.action_edit', LucideIcons.pencil),
  deposit('managers.action_deposit', LucideIcons.plus),
  withdraw('managers.action_withdraw', LucideIcons.circleMinus),
  payDebt('managers.action_pay_debt', LucideIcons.banknote),
  addPoints('managers.action_add_points', LucideIcons.star),
  otherDebts('managers.action_other_debts', LucideIcons.receipt),
  movements('managers.action_movements', LucideIcons.activity),
  sendInfo('managers.action_send_info', LucideIcons.smartphone),
  // 2026-08-26: إظهار كلمة السرّ الحاليّة (طلب المستخدم).
  // مصدرها whatsapp_sessions.admin_password_encrypted — الأدمن الفرعي
  // يجب يسجّل دخول مرّة أولاً حتى تُخزَّن.
  showPassword('managers.action_show_password', LucideIcons.keyRound),
  // 2026-08-26: نسخ اسم المستخدم — مفيد للـcross-reference بين النظام
  // والأنظمة الأخرى (تذاكر دعم، سجلّات، إلخ).
  copyUsername('managers.action_copy_username', LucideIcons.copy),
  delete('managers.action_delete', LucideIcons.trash2);

  const ManagerAction(this.labelKey, this.icon);
  final String labelKey;
  final IconData icon;

  /// ⚠️ اللون **getter لا حقل `const`**. الحقل الثابت كان يحمل
  /// `AppColors.brandAccent` وأمثاله، وهي أرقام لا تعرف الوضع الليلي —
  /// وenum بحقل const لا يمكنه استدعاء getter مثل `AppColors.brandAccent`.
  /// نقلُه إلى getter هو ما يجعل هذه القائمة تتبدّل مع الوضع.
  ///
  /// التوزيع دلاليّ لا لونيّ: المال الداخل نجاح، والخارج تحذير،
  /// والحذف خطر، وأخضر واتساب يبقى خاماً لأنّه تعريف قناة.
  /// ⚠️ **نغمة لا حقل `const`**. الحقل الثابت كان يحمل
  /// `Color(0xFF3B82F6)` وأمثاله — أرقاماً لا تعرف الوضع الليلي، وenum
  /// بحقل const لا يمكنه استدعاء getter من اللوحة. نقلُه إلى getter هو
  /// ما يجعل هذه القائمة تتبدّل مع الوضع.
  ///
  /// التوزيع دلاليّ لا لونيّ: المال الداخل نجاح، والخارج تحذير،
  /// والحذف خطر.
  AppTone get tone => switch (this) {
        ManagerAction.deposit || ManagerAction.payDebt => AppTone.success,
        ManagerAction.withdraw || ManagerAction.addPoints => AppTone.warning,
        ManagerAction.otherDebts => AppTone.info,
        ManagerAction.copyUsername => AppTone.neutral,
        ManagerAction.delete => AppTone.danger,
        _ => AppTone.brand,
      };

  /// أخضر واتساب للأيقونة وحدها — تعريف قناة لا حالة.
  Color? get brandGlyph =>
      this == ManagerAction.sendInfo ? AppColors.channelWhatsApp : null;

  Color get color => brandGlyph ?? tone.fill;

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
    barrierColor: AppColors.scrim,
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
    final totalDebt = (manager.debt) + customDebt;
    final hasDebt = totalDebt > 0;
    final hasBalance = (manager.balance) > 0;
    final hasPhone = manager.mobile.isNotEmpty;
    // 9 actions — ترتيب مطابق v1.
    // مطلب 2026-06-11: كل action يختفي إذا الموظف ما عنده الصلاحية.
    // payDebt يستعمل managers.deposit (نفس الدور — تحويل من الـbalance
    // لتغطية الـdebt). otherDebts + movements + sendInfo افتراضياً
    // مرئية لو الـactor يقدر يشوف المدير أصلاً.
    final actions = <ManagerAction>[
      if (Perms.has('managers.edit')) ManagerAction.edit,
      if (Perms.has('managers.deposit')) ManagerAction.deposit,
      if (hasBalance && Perms.has('managers.withdraw')) ManagerAction.withdraw,
      if (hasDebt && Perms.has('managers.deposit')) ManagerAction.payDebt,
      if (Perms.has('managers.add_points')) ManagerAction.addPoints,
      if (Perms.has('reports.manager_debts')) ManagerAction.otherDebts,
      ManagerAction.movements,
      if (hasDebt && hasPhone && Perms.has('subscribers.send_whatsapp'))
        ManagerAction.sendInfo,
      // كلمة السرّ متاحة لكل من عنده managers.edit — نفس صلاحيّة
      // التعديل. الـbackend يفحصها كذلك.
      if (Perms.has('managers.edit')) ManagerAction.showPassword,
      // نسخ اليوزر متاح لكل من يشاهد المدير أصلاً (بلا perm خاص).
      ManagerAction.copyUsername,
      if (Perms.has('managers.delete')) ManagerAction.delete,
    ];
    return DesignSheet(
      header: SheetHeaderBar(
        icon: LucideIcons.userCog,
        title: manager.username,
        subtitle: 'managers.operations'.tr(),
        onClose: () => Navigator.of(context).pop(),
      ),
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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
                      namedArgs: {'amount': formatIQD(manager.balance)}),
                  AppTone.brand,
                ),
                if (hasDebt)
                  _summaryChip(
                    LucideIcons.alertTriangle,
                    'managers.chip_debt'
                        .tr(namedArgs: {'amount': formatIQD(totalDebt)}),
                    AppTone.warning,
                  ),
                _summaryChip(
                  LucideIcons.users,
                  'managers.chip_subs'
                      .tr(namedArgs: {'n': '${manager.usersCount}'}),
                  AppTone.brand,
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
            padding: const EdgeInsets.fromLTRB(Sp.lg, 0, Sp.lg, Sp.md),
            // ⚠️ انحدار 2026-08-29: النسبة 0.82 كانت معايرة للدائرة
            // القديمة (52dp + ظلّ + تسمية بسطرين). البلاطة الجديدة
            // مسطّحة وأقصر — أيقونة 22 + فجوة 8 + سطر تسمية + حشوة
            // 12×2 ≈ 66dp — فبقيت ~20dp فراغاً أسفل كلّ زرّ.
            // النسبة 1.0 تطابق ارتفاع المحتوى الفعلي.
            child: GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 4,
              crossAxisSpacing: Sp.sm,
              mainAxisSpacing: Sp.sm,
              // 2026-08-30: 1.0 ما زالت تترك فراغاً — الحشوة الرأسيّة
              // Sp.md×2 كانت معايرة للدائرة. صارت Sp.sm×2 والنسبة
              // 1.15، فالبلاطة تلتصق بمحتواها.
              childAspectRatio: 1.15,
              children: [
                for (final a in actions) _actionTile(context, a),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryChip(IconData icon, String label, AppTone tone) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Sp.sm, vertical: 5),
      decoration: BoxDecoration(
        color: tone.softBg,
        borderRadius: BorderRadius.circular(R.pill),
        border: Border.all(color: tone.softBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: tone.fill),
          const SizedBox(width: Sp.xs),
          Text(label, style: AppType.pillLabel(color: tone.onSoft)),
        ],
      ),
    );
  }

  Widget _actionTile(BuildContext context, ManagerAction action) {
    // مطابق subscriber_detail_screen _OpCard:
    //   دائرة ملوّنة 52dp + أيقونة بيضاء 22 + label تحتها بـtextHi.
    // 2026-08-29: من دائرة 52 ملوّنة بأيقونة بيضاء وظلّ ملوّن (لغة v1)
    // إلى بلاطة المخطّط: سطح أبيض r16 بحدّ، وأيقونة ملوّنة بالنغمة.
    // نفس لغة `SubscriberActionTiles` — الشاشتان صارتا تُقرآن كعائلة.
    final tone = action.tone;
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(R.lg),
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          Navigator.of(context).pop(action);
        },
        borderRadius: BorderRadius.circular(R.lg),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(R.lg),
            border: Border.all(color: AppColors.border),
          ),
          padding:
              const EdgeInsets.symmetric(vertical: Sp.md, horizontal: Sp.x6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(action.icon,
                  color: action.brandGlyph ?? tone.fill, size: 22),
              const SizedBox(height: Sp.x6),
              Text(
                action.label,
                style: AppType.muted(color: AppColors.textBody),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
