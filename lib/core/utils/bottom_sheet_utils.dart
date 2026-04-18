import 'dart:math' as math;

import 'package:flutter/widgets.dart';

double bottomSheetSystemInset(BuildContext context) {
  final rootMediaQuery = MediaQueryData.fromView(View.of(context));
  return math.max(
    rootMediaQuery.viewPadding.bottom,
    rootMediaQuery.padding.bottom,
  );
}

double bottomSheetBottomInset(
  BuildContext context, {
  double extra = 16,
}) {
  return MediaQuery.of(context).viewInsets.bottom +
      bottomSheetSystemInset(context) +
      extra;
}

EdgeInsets bottomSheetContentPadding(
  BuildContext context, {
  double horizontal = 20,
  double top = 16,
  double extraBottom = 16,
}) {
  return EdgeInsets.fromLTRB(
    horizontal,
    top,
    horizontal,
    bottomSheetBottomInset(context, extra: extraBottom),
  );
}
