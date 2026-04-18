import 'dart:math' as math;

import 'package:flutter/widgets.dart';

double bottomSheetBottomInset(
  BuildContext context, {
  double extra = 16,
}) {
  final mediaQuery = MediaQuery.of(context);
  final systemBottom = math.max(
    mediaQuery.viewPadding.bottom,
    mediaQuery.padding.bottom,
  );
  return mediaQuery.viewInsets.bottom + systemBottom + extra;
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
