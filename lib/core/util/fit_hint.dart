import 'package:flutter/widgets.dart';

/// أطول تلميحٍ من [candidates] (مرتّبةً من الأطول للأقصر) يتّسع في [maxWidth]
/// بخطّ [style] وسلّم الخطّ الحاليّ — وإلّا آخرها.
///
/// حقل البحث صار يتشارك سطره مع أزرار القائمة (رأس المشتركين والأجهزة — ٢٠
/// أكتوبر، حين انتقلت أزرار الأعلى المشتركة إلى سطر العنوان)، فضاق على الشاشات
/// الصغيرة. والتلميح الطويل يُبتر حينها بـ«…» في منتصف جملته؛ فنختار أطول صيغةٍ
/// تُقرأ كاملةً بدل أن نبتر الطويلة.
String fittingHint(
  BuildContext context, {
  required double maxWidth,
  required TextStyle style,
  required List<String> candidates,
}) {
  assert(candidates.isNotEmpty);
  if (!maxWidth.isFinite) return candidates.first;
  final scaler = MediaQuery.textScalerOf(context);
  final direction = Directionality.of(context);
  for (final c in candidates) {
    final tp = TextPainter(
      text: TextSpan(text: c, style: style),
      textDirection: direction,
      textScaler: scaler,
      maxLines: 1,
    )..layout();
    final width = tp.width;
    tp.dispose();
    if (width <= maxWidth) return c;
  }
  return candidates.last;
}
