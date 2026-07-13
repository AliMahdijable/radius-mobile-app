import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';

/// Dialog يُعرض بعد نجاح التفعيل/التسديد. يعطي المدير خيار طباعة الوصل
/// أو تجاهله. لا يُطبع تلقائياً — الاختيار للمدير.
///
/// يرجع `true` لو المدير ضغط "طباعة"، false لو ضغط "تم".
Future<bool> showPrintReceiptDialog(
  BuildContext context, {
  required String title,
  required String message,
  Color? accentColor,
}) async {
  final accent = accentColor ?? AppColors.brand;
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(R.lg)),
      contentPadding: const EdgeInsets.fromLTRB(Sp.lg, Sp.xl, Sp.lg, Sp.md),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Circle check icon
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: accent.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Icon(LucideIcons.circleCheck, size: 32, color: accent),
          ),
          const SizedBox(height: Sp.md),
          Text(
            title,
            textAlign: TextAlign.center,
            style: AppType.title(color: AppColors.textHi).copyWith(fontSize: 16),
          ),
          const SizedBox(height: Sp.sm),
          Text(
            message,
            textAlign: TextAlign.center,
            style: AppType.subtitle(color: AppColors.textMid)
                .copyWith(fontSize: 13, height: 1.5),
          ),
        ],
      ),
      actionsPadding:
          const EdgeInsets.only(left: Sp.md, right: Sp.md, bottom: Sp.md),
      actions: [
        // زر "تم" — يغلق بلا طباعة
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(
                horizontal: Sp.lg, vertical: Sp.sm),
          ),
          child: Text(
            'common.done'.tr(),
            style: AppType.button(color: AppColors.textMid),
          ),
        ),
        // زر "طباعة الوصل" — primary action
        ElevatedButton.icon(
          onPressed: () => Navigator.of(ctx).pop(true),
          style: ElevatedButton.styleFrom(
            backgroundColor: accent,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(
                horizontal: Sp.lg, vertical: Sp.md),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(R.sm)),
            textStyle: const TextStyle(
              fontFamily: 'Cairo',
              fontSize: 13,
              fontWeight: FontWeight.w900,
            ),
          ),
          icon: const Icon(LucideIcons.printer, size: 16),
          label: Text('sheets.print_receipt'.tr()),
        ),
      ],
    ),
  );
  return result ?? false;
}
