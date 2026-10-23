import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/core/util/ar_date.dart';
import 'package:rad_mysvcs/screens/reports/widgets/date_range_chip.dart';

import 'visual_perm/visual_perm_harness.dart';

/// التواريخ بأسماء الأشهر (المالك ٢٤ أكتوبر: «الاشهر تكتب رقم انكليزي») — نفس قواعد الويب `lib/ar-date.ts`،
/// وشريط الفترات الموحّد للتقارير والمبيعات والصرفيات.
void main() {
  setUpAll(visualSetUpAll);

  DateRange? picked;
  Future<void> ar(WidgetTester t, {DateRange? bar}) async {
    await visualSetUp(s1bSasOwner);
    await pumpVisual(t, phone,
        home: (_) => Scaffold(
              body: bar == null ? const SizedBox() : DateRangeChipBar(value: bar, onChanged: (r) => picked = r),
            ));
    await t.pumpAndSettle();
  }

  testWidgets('الشهر والتاريخ: السنة حين لا تكون سنة اليوم، والنصّ الغريب كما هو', (t) async {
    await ar(t);
    final today = DateTime(2026, 10, 24);
    expect(iqPeriodLabel('2026-10'), 'تشرين الأوّل 2026');
    expect(iqPeriodLabel('2027-01'), 'كانون الثاني 2027');
    expect(iqPeriodLabel('x'), 'x');
    expect(iqDateLabel('2026-10-05', today: today), '5 تشرين الأوّل');
    expect(iqDateLabel('2025-12-31T21:00:00.000Z', today: today), '31 كانون الأوّل 2025');
    expect(iqDateLabel('', today: today), '');
    expect(iqDateOf(DateTime(2026, 5, 1), today: today), '1 أيّار');
  });

  testWidgets('لاحقة «(ثابتة …)» تُحذف من الملاحظة، وما سواها يبقى', (t) async {
    await ar(t);
    expect(stripRecurringSuffix('إيجار المحل (ثابتة 2026-10)'), 'إيجار المحل');
    expect(stripRecurringSuffix('إيجار — الطابق ٢ (ثابتة تشرين الأوّل 2026)'), 'إيجار — الطابق ٢');
    expect(stripRecurringSuffix('قرطاسية (عاجل)'), 'قرطاسية (عاجل)');
  });

  testWidgets('«الشهر الماضي» من أوّله إلى آخر يومٍ فيه، و«من … إلى …» بأسماء الأشهر', (t) async {
    await ar(t);
    final r = DateRange.lastMonth();
    final n = DateTime.now();
    final first = DateTime(n.year, n.month - 1, 1);
    expect(r.from, first);
    expect(r.to.day, DateTime(n.year, n.month, 0).day);
    expect(r.to.month, first.month);
    expect((r.to.hour, r.to.minute), (23, 59));
    expect(r.isCustom, isFalse);
    expect(DateRange.presets().map((p) => p.label).toList(),
        ['اليوم', 'أمس', 'هذا الأسبوع', 'هذا الشهر', 'الشهر الماضي', '3 شهور']);
    final y = n.year;
    final c = DateRange.custom(DateTime(y, 10, 1), DateTime(y, 10, 24));
    expect(c.label, 'من 1 تشرين الأوّل إلى 24 تشرين الأوّل');
    expect(c.isCustom, isTrue);
    expect(DateRange.rangeText(DateTime(y, 3, 2), DateTime(y, 3, 2)), '2 آذار');
  });

  testWidgets('الشريط: الفترات الجاهزة، وتحتها الفترة نفسها بأسماء الأشهر، واللمس يغيّرها', (t) async {
    final y = DateTime.now().year;
    await ar(t, bar: DateRange.custom(DateTime(y, 10, 1), DateTime(y, 10, 24)));
    for (final l in ['اليوم', 'أمس', 'هذا الأسبوع', 'هذا الشهر', 'الشهر الماضي', '3 شهور']) {
      expect(find.text(l), findsOneWidget, reason: l);
    }
    expect(find.text('من 1 تشرين الأوّل إلى 24 تشرين الأوّل'), findsOneWidget);
    expect(find.text('اختر الفترة'), findsOneWidget);
    await t.tap(find.text('الشهر الماضي'));
    expect(picked?.label, 'الشهر الماضي');
    expect(t.takeException(), isNull);
  });
}
