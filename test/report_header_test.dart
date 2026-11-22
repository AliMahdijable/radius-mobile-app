import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/archive_info.dart';
import 'package:rad_mysvcs/screens/reports/v2/report_kit.dart';
import 'package:rad_mysvcs/screens/settlements/widgets/archive_bar.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// رأس التقرير الموحّد بسطرٍ واحد (المالك ٢٢ نوفمبر على لقطة الماليّ: «الفلاتر والشهر وذني كلّهن يصيرون بسطر واحد حتى لا تاخذ هو من
/// مساحة التصميم، كلّ التقارير لازم» + «الأرشيف يصير فوق وصورة مختصرة»).
void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  Widget app(double width, double scale, Widget child) => MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(size: Size(width, 900), textScaler: TextScaler.linear(scale)),
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: Align(
                alignment: Alignment.topCenter,
                child: SizedBox(width: width - 32, child: child),
              ),
            ),
          ),
        ),
      );

  RpHeader header({bool archive = true, bool compare = true, List<RpChip> chips = const []}) => RpHeader(
        period: const RpPeriod(name: 'هذا الشهر', range: '2026/11/01 – 2026/11/22'),
        onPeriod: () {},
        compareOn: compare,
        onCompare: compare ? () {} : null,
        chips: chips,
        onFilters: () {},
        onClear: () {},
        top: archive
            ? ArchiveBar(
                compact: true,
                archive: ArchiveInfo(hidden: true, included: false, settlements: 9, lastNumber: 9, lastCutAt: DateTime.utc(2026, 11, 16, 19, 16)),
                includeArchived: false,
                onChanged: (_) {},
              )
            : null,
      );

  for (final width in [320.0, 360.0, 480.0]) {
    for (final scale in [1.0, 1.2]) {
      testWidgets('@$width ×$scale: الفترة و«قارن» و«الفلاتر» صفٌّ واحد، والأرشيف سطرٌ فوقه، والشارات تحته — بلا فيض', (t) async {
        await t.pumpWidget(app(width, scale, header(chips: [RpChip('النوع: تفعيل نقدي', onRemove: () {}), RpChip('الموظّف: أحمد', onRemove: () {})])));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        final period = t.getRect(find.byKey(const ValueKey('rp-head-period')));
        final compare = t.getRect(find.byKey(const ValueKey('rp-head-compare')));
        final filters = t.getRect(find.byKey(const ValueKey('rp-head-filters')));
        // صفٌّ واحد: الأعلى نفسه والارتفاع نفسه
        expect({period.top, compare.top, filters.top}.length, 1, reason: '$period $compare $filters');
        expect(period.height, 44);
        // الترتيب RTL: الفترة يميناً، ثمّ «قارن»، ثمّ «الفلاتر» يساراً
        expect(period.left > compare.right - 1 && compare.left > filters.right - 1, isTrue);
        // الأرشيف سطرٌ مختصر فوق الصفّ — لا صندوقٌ بثلاث حبّات
        final arch = t.getRect(find.byKey(const ValueKey('archive-compact')));
        expect(arch.bottom <= period.top, isTrue);
        expect(arch.height, lessThan(44), reason: 'سطرٌ مختصر');
        expect(find.text('تسوية الحساب'), findsNothing);
        expect(find.textContaining('ما بعد آخر تسوية #9'), findsOneWidget);
        // الشارات الفعّالة تحت الصفّ
        final chip = t.getRect(find.text('النوع: تفعيل نقدي'));
        expect(chip.top >= period.bottom, isTrue);
        // «الفلاتر» نصّاً على الواسع وأيقونةً وعدداً على الضيّق
        expect(find.text('الفلاتر'), width - 32 < 380 ? findsNothing : findsOneWidget);
        expect(find.descendant(of: find.byKey(const ValueKey('rp-head-filters')), matching: find.text('2')), findsOneWidget);
        // الفترة: اسمها ومداها كاملين (يصغران ولا يُقصّان)
        expect(find.text('هذا الشهر'), findsOneWidget);
        expect(find.text('2026/11/01 – 2026/11/22'), findsOneWidget);
      });
    }
  }

  testWidgets('بلا أرشيفٍ ولا مقارنةٍ ولا شارات: صفٌّ واحد وحده (الفترة و«الفلاتر»)', (t) async {
    await t.pumpWidget(app(360, 1.0, header(archive: false, compare: false)));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    expect(find.byKey(const ValueKey('rp-head-compare')), findsNothing);
    expect(find.byKey(const ValueKey('archive-compact')), findsNothing);
    expect(t.getSize(find.byType(RpHeader)).height, 44);
  });
}
