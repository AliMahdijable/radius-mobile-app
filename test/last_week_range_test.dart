import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/screens/dashboard/widgets/packages_summary_card.dart';
import 'package:rad_mysvcs/screens/dashboard/widgets/pill_tabs.dart';
import 'package:rad_mysvcs/screens/reports/widgets/date_range_chip.dart';

/// «الأسبوع الماضي» في اختصارات بطاقة توزيع الباقات (المالك ٢٥ أكتوبر): الأسبوع الذي قبل «هذا الأسبوع» كاملاً — من الاثنين
/// إلى الأحد كبدايته — لا آخر سبعة أيّامٍ متحرّكة. والاختصارات الأربعة بترتيب المالك.
void main() {
  test('الأسبوع الماضي: من الاثنين إلى الأحد، ينتهي قبل بداية هذا الأسبوع بيوم', () {
    final last = DateRange.lastWeek();
    final week = DateRange.thisWeek();
    expect(last.from.weekday, DateTime.monday);
    expect(last.to.weekday, DateTime.sunday);
    expect(week.from.difference(DateTime(last.from.year, last.from.month, last.from.day)).inDays, 7);
    final dayBefore = week.from.subtract(const Duration(days: 1));
    expect(DateTime(last.to.year, last.to.month, last.to.day), DateTime(dayBefore.year, dayBefore.month, dayBefore.day));
    expect([last.to.hour, last.to.minute, last.to.second], [23, 59, 59], reason: 'نهاية اليوم كبقيّة الفترات');
  });

  test('اختصارات البطاقة: اليوم · أمس · الأسبوع الماضي · الشهر الماضي — والمجهول يرجع لليوم', () {
    expect(PackagesSummaryCard.periods, ['today', 'yesterday', 'last_week', 'last_month']);
    final today = DateRange.today();
    final unknown = PackagesSummaryCard.rangeOf('?');
    expect(unknown.from, today.from);
    expect(PackagesSummaryCard.rangeOf('last_month').from.day, 1);
  });

  testWidgets('شريط الفترات بشكل الإيرادات لا يفيض على عرضٍ ضيّق، والنقر يبقى يعمل', (t) async {
    String? picked;
    const labels = ['اليوم', 'أمس', 'الأسبوع الماضي', 'الشهر الماضي'];
    await t.pumpWidget(MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Center(
          child: SizedBox(
            width: 240,
            child: Align(
              alignment: AlignmentDirectional.centerEnd,
              child: PillTabs<String>(
                options: [for (final l in labels) (l, l)],
                current: labels.first,
                onSelect: (v) => picked = v,
              ),
            ),
          ),
        ),
      ),
    ));
    expect(t.takeException(), isNull, reason: 'لا فيض بالأربع على ٢٤٠');
    for (final l in labels) {
      expect(find.text(l), findsOneWidget);
    }
    expect(t.getSize(find.byType(PillTabs<String>)).width, lessThanOrEqualTo(240));
    await t.tap(find.text('الشهر الماضي'));
    expect(picked, 'الشهر الماضي');
  });
}
