import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:rad_mysvcs/core/widgets/design_sheet.dart';
import 'package:rad_mysvcs/theme/colors.dart';

/// حبّة [ToneChip] بنصٍّ أطول من مكانها (ميزةٌ ذات صلة من المساعد حتى ٤٠ حرفاً
/// بعرض ٣٢٠ أو بخطٍّ مكبَّر) تُختصر «…» بدل الفيضان — وبمكانٍ واسع حجمها كما
/// كان، وفي صفٍّ أفقيّ بلا حدّ لا تنهار.
void main() {
  const long = 'شلون أستعمل التفعيل بالكارت لمشترك منتهي من زمان';

  Widget host(Widget child) => MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(body: Center(child: child)),
        ),
      );

  testWidgets('ضيّق ⇒ «…» بلا فيضان', (t) async {
    await t.pumpWidget(host(const SizedBox(
      width: 140,
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: ToneChip(
            label: long,
            tone: AppTone.brand,
            icon: LucideIcons.messageCircleQuestion),
      ),
    )));
    expect(t.takeException(), isNull);
    expect(t.getSize(find.byType(ToneChip)).width, lessThanOrEqualTo(140));
  });

  testWidgets('واسع ⇒ بحجم نصّه (لا يتمدّد)', (t) async {
    await t.pumpWidget(host(const SizedBox(
      width: 400,
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: ToneChip(label: 'قصير', tone: AppTone.brand),
      ),
    )));
    expect(t.takeException(), isNull);
    expect(t.getSize(find.byType(ToneChip)).width, lessThan(120));
  });

  testWidgets('في صفٍّ أفقيّ قابلٍ للتمرير (عرضٌ بلا حدّ) ⇒ بلا استثناء',
      (t) async {
    await t.pumpWidget(host(const SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [
        ToneChip(label: long, tone: AppTone.neutral, dense: true),
        ToneChip(label: 'قصير', tone: AppTone.brand),
      ]),
    )));
    expect(t.takeException(), isNull);
  });
}
