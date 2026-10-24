import 'package:flutter/widgets.dart';

/// تكبيرٌ كتكبير المتصفّح لقسمٍ كامل على الحاسبة: الابن يُبنى بعرضٍ منطقيّ أصغر (العرض ÷ [scale]) ثمّ يُرسم
/// مكبَّراً ليملأ المكان — النصوص والأيقونات والصور والمسافات كلّها أكبر بالنسبة نفسها، والنقر والتمرير يمرّان
/// عبر التحويل. لقسم الأجهزة (المالك ٢٤ أكتوبر: «عرض المعلومات بعده ناعم وزغير») حيث لوحاتٌ كثيرة مقاساتها ثابتة.
/// MediaQuery بالداخل بالمقاس المنطقيّ، فالشاشات التي تقيس العرض تقرّر على ما تراه فعلاً.
class DeskZoom extends StatelessWidget {
  const DeskZoom({super.key, required this.scale, required this.child});

  final double scale;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (scale == 1) return child;
    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth / scale;
      final h = c.maxHeight / scale;
      final mq = MediaQuery.of(context);
      return SizedBox(
        width: c.maxWidth,
        height: c.maxHeight,
        child: FittedBox(
          fit: BoxFit.fill,
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: w,
            height: h,
            child: MediaQuery(data: mq.copyWith(size: Size(w, h)), child: child),
          ),
        ),
      );
    });
  }
}
