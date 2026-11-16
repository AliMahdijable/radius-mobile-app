import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/core/util/ar_date.dart';
import 'package:rad_mysvcs/screens/reports/widgets/date_range_chip.dart';

import 'visual_perm/visual_perm_harness.dart';

/// تواريخ التقارير أرقامٌ «2026/10/05» لا أسماء أشهر (المالك ١٦ نوفمبر: «بدله من اسم شهر الى رقم شهر اجنبي في جميع
/// التقارير») — نفس قواعد الويب `lib/ar-date.ts`، وشريط الفترات الموحّد للتقارير والمبيعات والصرفيات.
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

  testWidgets('الشهر والتاريخ أرقامٌ لاتينيّة سنة/شهر/يوم — والسنة دائماً، والنصّ الغريب كما هو', (t) async {
    await ar(t);
    final today = DateTime(2026, 10, 24);
    expect(iqPeriodLabel('2026-10'), '2026/10');
    expect(iqPeriodLabel('2027-01'), '2027/01');
    expect(iqPeriodLabel('x'), 'x');
    expect(iqDateLabel('2026-10-05', today: today), '2026/10/05', reason: 'سنة اليوم تُكتب أيضاً: «10/05» بلا سنة يُقرأ بالعكس');
    expect(iqDateLabel('2025-12-31T21:00:00.000Z', today: today), '2025/12/31');
    expect(iqDateLabel('', today: today), '');
    expect(iqDateOf(DateTime(2026, 5, 1), today: today), '2026/05/01');
    expect(iqDateOf(DateTime(2027, 12, 9)), '2027/12/09');
    // لا اسم شهرٍ ولا رقمٌ هنديّ في أيّ تاريخٍ للتقارير.
    for (var m = 1; m <= 12; m++) {
      final s = iqDateOf(DateTime(2026, m, 15));
      expect(RegExp(r'^\d{4}/\d{2}/\d{2}$').hasMatch(s), isTrue, reason: s);
    }
  });

  testWidgets('فترة الراتب من مفتاحها: الشهريّة «2026/11»، والأسبوعيّة «أسبوع 2026/11/10»، وغير المعروف نصّ الخادم', (t) async {
    await ar(t);
    expect(iqPayPeriodLabel('2026-11', 'تشرين الثاني 2026'), '2026/11');
    expect(iqPayPeriodLabel('2026-11-10', 'أسبوع 2026-11-10'), 'أسبوع 2026/11/10');
    expect(iqPayPeriodLabel('x', 'نصّ الخادم'), 'نصّ الخادم');
    expect(iqPayPeriodLabel(null, null), '');
  });

  testWidgets('لاحقة «(ثابتة …)» تُحذف من الملاحظة، وما سواها يبقى', (t) async {
    await ar(t);
    expect(stripRecurringSuffix('إيجار المحل (ثابتة 2026-10)'), 'إيجار المحل');
    expect(stripRecurringSuffix('إيجار — الطابق ٢ (ثابتة تشرين الأوّل 2026)'), 'إيجار — الطابق ٢');
    expect(stripRecurringSuffix('قرطاسية (عاجل)'), 'قرطاسية (عاجل)');
  });

  testWidgets('«الشهر الماضي» من أوّله إلى آخر يومٍ فيه، و«من … إلى …» بالأرقام', (t) async {
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
    expect(c.label, 'من $y/10/01 إلى $y/10/24');
    expect(c.isCustom, isTrue);
    expect(DateRange.rangeText(DateTime(y, 3, 2), DateTime(y, 3, 2)), '$y/03/02');
  });

  testWidgets('الشريط: الفترات الجاهزة، وتحتها الفترة نفسها بالأرقام، واللمس يغيّرها', (t) async {
    final y = DateTime.now().year;
    await ar(t, bar: DateRange.custom(DateTime(y, 10, 1), DateTime(y, 10, 24)));
    for (final l in ['اليوم', 'أمس', 'هذا الأسبوع', 'هذا الشهر', 'الشهر الماضي', '3 شهور']) {
      expect(find.text(l), findsOneWidget, reason: l);
    }
    expect(find.text('من $y/10/01 إلى $y/10/24'), findsOneWidget);
    expect(find.text('اختر الفترة'), findsOneWidget);
    await t.tap(find.text('الشهر الماضي'));
    expect(picked?.label, 'الشهر الماضي');
    expect(t.takeException(), isNull);
  });
}
