import 'package:flutter/material.dart';

/// أطول تلميحٍ من [candidates] (مرتّبةً من الأطول للأقصر) يتّسع في [maxWidth]
/// بخطّ [style] وسلّم الخطّ الحاليّ — وإلّا آخرها.
///
/// حقل البحث صار يتشارك سطره مع أزرار القائمة (رأس المشتركين والأجهزة — ٢٠
/// أكتوبر، حين انتقلت أزرار الأعلى المشتركة إلى سطر العنوان)، فضاق على الشاشات
/// الصغيرة. والتلميح الطويل يُبتر حينها بـ«…» في منتصف جملته؛ فنختار أطول صيغةٍ
/// تُقرأ كاملةً بدل أن نبتر الطويلة.
///
/// ⚠️ يُقاس بالنمط الذي يرسمه `InputDecorator` فعلاً لا بـ[style] وحده:
/// `bodyLarge` (M3) ← نمط الحقل [fieldStyle] ← [style]. وما لا يحدّده نمطنا
/// يُورث من `bodyLarge` — تباعد الحروف ‎0.5 — فبدونه يُقاس التلميح أقصر من رسمه
/// بنصف نقطةٍ لكلّ حرف، فيُختار ما «يتّسع» ثمّ يُبتر («اسم أو I…» على ‎360).
String fittingHint(
  BuildContext context, {
  required double maxWidth,
  required TextStyle style,
  TextStyle? fieldStyle,
  required List<String> candidates,
}) {
  assert(candidates.isNotEmpty);
  if (!maxWidth.isFinite) return candidates.first;
  final theme = Theme.of(context);
  final base = theme.useMaterial3
      ? theme.textTheme.bodyLarge
      : theme.textTheme.titleMedium;
  final painted = (base ?? const TextStyle()).merge(fieldStyle).merge(style);
  final scaler = MediaQuery.textScalerOf(context);
  final direction = Directionality.of(context);
  for (final c in candidates) {
    final tp = TextPainter(
      text: TextSpan(text: c, style: painted),
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
