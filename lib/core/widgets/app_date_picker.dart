import 'dart:math' as math;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../theme/colors.dart';
import '../../theme/spacing.dart';

/// منتقي الفترة للتطبيق كلّه: على الهاتف كما يرسمه Material (صفحةٌ كاملة)، وعلى الشاشة العريضة (الحاسبة،
/// الآيباد) نافذةٌ بالوسط بعرضٍ معقول فوق خلفيّةٍ معتمة — كان يملأ نافذة البرنامج كلّها والأيّام ضائعة في وسطها
/// (المالك ٢٤ أكتوبر بصورة «اختر الفترة»). الألوان من `appDatePickerTheme` وأسماء الأشهر من
/// `IqMaterialLocalizationsDelegate`.
Future<DateTimeRange?> showAppDateRangePicker({
  required BuildContext context,
  required DateTime firstDate,
  required DateTime lastDate,
  DateTimeRange? initialDateRange,
  String? helpText,
}) {
  return showDateRangePicker(
    context: context,
    firstDate: firstDate,
    lastDate: lastDate,
    initialDateRange: initialDateRange,
    helpText: helpText ?? 'reports.range_pick'.tr(),
    saveText: 'common.apply'.tr(),
    cancelText: 'common.cancel'.tr(),
    barrierColor: AppColors.scrim,
    builder: (ctx, child) => AppDateRangeFrame(child: child ?? const SizedBox.shrink()),
  );
}

/// إطار المنتقي على الشاشة العريضة — مكشوفٌ للاختبار.
class AppDateRangeFrame extends StatelessWidget {
  const AppDateRangeFrame({super.key, required this.child});

  final Widget child;

  /// أعرض من هذا ⇒ نافذةٌ بالوسط لا صفحةٌ كاملة.
  static const double wideFrom = 700;
  static const double maxWidth = 440;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    if (size.width < wideFrom) return child;
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth, maxHeight: math.min(720, size.height - 2 * Sp.xxl)),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(R.xl),
          child: child,
        ),
      ),
    );
  }
}
