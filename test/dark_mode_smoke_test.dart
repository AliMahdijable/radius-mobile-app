import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/core/widgets/design_sheet.dart';
import 'package:rad_mysvcs/core/widgets/metric_tile.dart';
import 'package:rad_mysvcs/screens/network_devices/widgets/brand_badge.dart';
import 'package:rad_mysvcs/theme/colors.dart';
import 'package:rad_mysvcs/widgets/skeleton.dart';

/// اختبار تدخين للوضع الليلي.
///
/// اختبارات اللوحة تتحقّق من التوكنات في معزل: هل يقرأ هذا اللون على
/// ذاك السطح. لكنّها لا ترسم شيئاً، فلا تمسك ما يحدث حين **يُركَّب**
/// التوكن — لونٌ يُشتقّ من آخر، أو `AppTone` يُحلّ قبل ضبط الوضع،
/// أو رسّامٌ مخصّص يفترض خلفيّة فاتحة.
///
/// هنا نرسم كلّ عنصر من الطقم في الوضعين ونتأكّد أنّه لا يرمي ولا
/// يفيض. الوضع الليلي لم يُراجَع بصريّاً بعد، فهذه أضعف تغطية ممكنة
/// له — لكنّها ليست صفراً.
void main() {
  Future<void> pumpBoth(
    WidgetTester t,
    String name,
    Widget Function() build, {
    Size size = const Size(360, 640),
  }) async {
    for (final dark in [false, true]) {
      AppColors.setDarkMode(dark);
      addTearDown(() => AppColors.setDarkMode(false));
      t.view.physicalSize = size;
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          backgroundColor: AppColors.bg,
          body: SingleChildScrollView(child: build()),
        ),
      ));
      await t.pump();
      expect(t.takeException(), isNull,
          reason: '$name رمى في الوضع ${dark ? "الليلي" : "النهاري"}');
    }
  }

  testWidgets('حبّات النغمة — الأنغام الثمانية', (t) async {
    await pumpBoth(t, 'ToneChip', () {
      return Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final tone in AppTone.values)
            ToneChip(label: tone.name, tone: tone, icon: Icons.circle),
        ],
      );
    });
  });

  testWidgets('بلاطات القياس — الأنغام الثمانية', (t) async {
    await pumpBoth(t, 'MetricTile', () {
      return Column(
        children: [
          for (final tone in AppTone.values)
            MetricTile(label: tone.name, value: '42', tone: tone),
        ],
      );
    });
  });

  testWidgets('صندوق الملخّص واللافتة والبطاقة', (t) async {
    await pumpBoth(t, 'Summary/Banner/Card', () {
      return Column(
        children: [
          const SheetSummaryBox(label: 'المجموع', value: '25,000 د.ع'),
          const SizedBox(height: 8),
          for (final tone in AppTone.values)
            SheetResultBanner(
              icon: Icons.check_rounded,
              label: 'النتيجة',
              value: tone.name,
              tone: tone,
            ),
          const SizedBox(height: 8),
          const SheetBrandResultCard(label: 'الرصيد', value: '120,000'),
        ],
      );
    });
  });

  testWidgets('بطاقة الباقة وصفوف المعلومات', (t) async {
    await pumpBoth(t, 'PlanCard/RowsGroup', () {
      return const Column(
        children: [
          SheetPlanCard(
            planLabel: 'الباقة',
            planName: 'باقة 10 ميغا',
            durationLabel: '30 يوم',
            amountLabel: 'المبلغ',
            amount: '25,000',
          ),
          SizedBox(height: 8),
          SheetRowsGroup(rows: [
            SheetRowData(label: 'المستخدم', value: 'ali'),
            SheetRowData(label: 'الحالة', value: 'فعّال', strong: true),
          ]),
        ],
      );
    });
  });

  testWidgets('الحبّات السريعة والمقسّم', (t) async {
    await pumpBoth(t, 'QuickChip/Segmented', () {
      return Column(
        children: [
          Wrap(children: [
            SheetQuickChip(label: '25,000', selected: true, onTap: () {}),
            SheetQuickChip(label: '50,000', selected: false, onTap: () {}),
          ]),
          const SizedBox(height: 8),
          SheetSegmented(
            labels: const ['المعلومات', 'الصلاحيات'],
            selectedIndex: 0,
            onSelect: (_) {},
          ),
        ],
      );
    });
  });

  testWidgets('الهيكل العظمي — الوميض يرسم في الوضعين', (t) async {
    await pumpBoth(t, 'Skeleton', () {
      return const Column(children: [
        SkeletonDeviceCard(),
        SizedBox(height: 8),
        SkeletonBox(width: 140, height: 14),
      ]);
    });
  });

  testWidgets('شارات المصنّعين — رسّام مخصّص فوق تدرّج ثابت', (t) async {
    await pumpBoth(t, 'BrandBadge', () {
      return Wrap(
        spacing: 8,
        children: [
          for (final b in ['mikrotik', 'ubnt', 'mimosa', 'cisco', 'ruijie', 'other'])
            BrandBadge(brand: b),
        ],
      );
    });
  });

  testWidgets('الأسطح الأربعة متمايزة فعليّاً وقت الرسم', (t) async {
    // ليس فحص توكنات: نتأكّد أنّ `setDarkMode` أثّر فعلاً وقت البناء،
    // لا أنّ قيمةً التُقطت مبكّراً في `const`.
    AppColors.setDarkMode(true);
    addTearDown(() => AppColors.setDarkMode(false));
    late Color bg, surface, sheet, sunken;
    await t.pumpWidget(MaterialApp(
      home: Builder(builder: (_) {
        bg = AppColors.bg;
        surface = AppColors.surface;
        sheet = AppColors.surfaceSheet;
        sunken = AppColors.surfaceSunken;
        return const SizedBox();
      }),
    ));
    final all = {bg, surface, sheet, sunken};
    expect(all.length, 4, reason: 'سطحان أو أكثر متطابقان ليلاً — تختفي الحدود');
    // ليلاً يجب أن تكون داكنة فعلاً لا مقلوبة
    for (final c in all) {
      final lum = (0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b);
      expect(lum, lessThan(0.35), reason: 'سطح فاتح في الوضع الليلي');
    }
  });
}
