// `hide TextDirection`: الحزمة تصدّر نوع intl الذي يحجب نوع dart:ui.
import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../api/payment_voids_api.dart';
import '../core/widgets/permission_locked.dart';
import '../theme/colors.dart';
import '../theme/spacing.dart';
import '../theme/typography.dart';

/// «إلغاء تسديد» على سطر التسديد — في حركات «تسوية الحساب» و«سجل الحركات» للمشترك: شارة الحال وزرّ الإلغاء.
/// القواعد في الخادم؛ هذه تعرض ما قاله ([PaymentVoidStatus]).

/// شارة حال التسديد في قيد الإلغاء: «ملغى» · «بانتظار حسم» · «قيد الإلغاء».
///
/// صغيرةٌ عمداً (أقصر من سطر العنوان): لا يكبر الكرت بها.
class PaymentVoidBadge extends StatelessWidget {
  const PaymentVoidBadge({super.key, required this.item});
  final PaymentVoidItem item;

  static String labelOf(PaymentVoidItem v) => v.isDone
      ? 'settle.pay_void_done'.tr()
      : v.isUnknown
          ? 'settle.pay_void_unknown'.tr()
          : 'settle.pay_void_pending'.tr();

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final tone = item.isDone ? AppTone.danger : AppTone.warning;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: tone.softBg,
        borderRadius: BorderRadius.circular(R.pill),
      ),
      child: Text(
        labelOf(item),
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.ellipsis,
        style: AppType.microBold(color: tone.onSoft),
      ),
    );
  }
}

/// زرّ «إلغاء التسديد» على سطر تسديد: يفتح النافذة · مقفلٌ بمكانه «لا صلاحيّة» (موظّفٌ بلا الصلاحيّة يراه ولا يُخفى عنه) ·
/// أو لا شيء ([PaymentVoidAction.none] — يأخذ صفراً من المساحة).
class PaymentVoidRowButton extends StatelessWidget {
  const PaymentVoidRowButton({
    super.key,
    required this.action,
    required this.onOpen,
    this.resume = false,
    this.size = 32,
  });

  final PaymentVoidAction action;
  final VoidCallback onOpen;

  /// إلغاءٌ بدأ ولم يكتمل (بانتظار حسم، أو عمليّةٌ انقطعت) — الزرّ يُكمله أو يحسمه.
  final bool resume;

  /// ضلع مساحة اللمس.
  final double size;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    if (action == PaymentVoidAction.none) return const SizedBox.shrink();
    final locked = action == PaymentVoidAction.locked;
    final tip = locked
        ? 'settle.pay_void_locked'.tr()
        : (resume ? 'settle.pay_void_continue'.tr() : 'settle.pay_void_action'.tr());
    return Tooltip(
      message: tip,
      child: InkResponse(
        onTap: locked ? () => showNoPermission(context, action: true) : onOpen,
        radius: size / 2,
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(
            locked ? LucideIcons.lock : LucideIcons.undo2,
            size: locked ? 13 : 16,
            color: locked
                ? LockedStyle.glyph
                : (resume ? AppTone.warning.fill : AppColors.textMid),
          ),
        ),
      ),
    );
  }
}
