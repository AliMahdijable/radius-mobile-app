import 'package:flutter/material.dart';

import 'colors.dart';
import 'spacing.dart';
import 'typography.dart';

/// منتقي التاريخ والفترة بألوان التطبيق وخطّه — يُستدعى داخل بناء الثيم بعد ضبط `AppColors` للوضع (فاتح/داكن).
///
/// بلا هذا كان المنتقي يأخذ ألوان Material الافتراضيّة: الفترة المختارة فيروزيّة (`secondaryContainer` الافتراضيّ
/// لـ`ColorScheme.light`) وزوايا وخطوط غير التطبيق (المالك ٢٤ أكتوبر بصورة «اختر الفترة»).
DatePickerThemeData appDatePickerTheme() {
  WidgetStateProperty<Color?> pick({required Color? selected, Color? normal, Color? disabled}) =>
      WidgetStateProperty.resolveWith((s) {
        if (s.contains(WidgetState.disabled)) return disabled;
        if (s.contains(WidgetState.selected)) return selected;
        return normal;
      });
  final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(R.xl));
  final buttons = TextButton.styleFrom(
    foregroundColor: AppColors.brand,
    textStyle: AppType.button(),
    minimumSize: const Size(0, H.chip),
    padding: const EdgeInsets.symmetric(horizontal: Sp.lg),
  );
  return DatePickerThemeData(
    backgroundColor: AppColors.surfaceSheet,
    surfaceTintColor: Colors.transparent,
    elevation: 0,
    shape: shape,
    headerBackgroundColor: AppColors.surfaceSheet,
    headerForegroundColor: AppColors.textHi,
    headerHeadlineStyle: AppType.title(color: AppColors.textHi).copyWith(fontSize: 22),
    headerHelpStyle: AppType.label(color: AppColors.textMid),
    weekdayStyle: AppType.microBold(color: AppColors.textMid),
    dayStyle: AppType.bodyBold(),
    dayForegroundColor: pick(selected: AppColors.onBrand, normal: AppColors.textHi, disabled: AppColors.textLow),
    dayBackgroundColor: pick(selected: AppColors.brand),
    dayOverlayColor: WidgetStateProperty.all(AppColors.brand.withValues(alpha: 0.08)),
    todayForegroundColor: pick(selected: AppColors.onBrand, normal: AppColors.brand, disabled: AppColors.textLow),
    todayBackgroundColor: pick(selected: AppColors.brand),
    todayBorder: BorderSide(color: AppColors.brand),
    yearStyle: AppType.bodyBold(),
    yearForegroundColor: pick(selected: AppColors.onBrand, normal: AppColors.textHi, disabled: AppColors.textLow),
    yearBackgroundColor: pick(selected: AppColors.brand),
    rangePickerBackgroundColor: AppColors.surfaceSheet,
    rangePickerSurfaceTintColor: Colors.transparent,
    rangePickerElevation: 0,
    rangePickerShape: shape,
    rangePickerHeaderBackgroundColor: AppColors.surfaceSheet,
    rangePickerHeaderForegroundColor: AppColors.textHi,
    // ١٧ لا ٢٢: «1 كانون الثاني – 31 كانون الأوّل» أطول من «1 يناير – 31 ديسمبر»، والنصّ الأوّل في رأس منتقي
    // فلاتر غير مرن — بـ٢٢ فاض عرض الهاتف (٣٢٠–٣٩٠).
    rangePickerHeaderHeadlineStyle: AppType.title(color: AppColors.textHi).copyWith(fontSize: 17),
    rangePickerHeaderHelpStyle: AppType.label(color: AppColors.textMid),
    // الأيّام بين البداية والنهاية: أخضر التطبيق الفاتح لا الفيروزيّ.
    rangeSelectionBackgroundColor: AppColors.brandSoftBg,
    rangeSelectionOverlayColor: WidgetStateProperty.all(AppColors.brand.withValues(alpha: 0.08)),
    dividerColor: AppColors.border,
    cancelButtonStyle: buttons,
    confirmButtonStyle: buttons,
  );
}
