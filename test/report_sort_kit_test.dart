import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:rad_mysvcs/core/util/order_rules.dart';
import 'package:rad_mysvcs/screens/desktop/desk_bulk_picker.dart';
import 'package:rad_mysvcs/screens/reports/v2/report_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// «الترتيب بالنقر» في عُدّة التقارير (المالك ٢٣ نوفمبر): سطر «رتّب حسب» كاملٌ يلتفّ على 320 بخطٍّ مكبّر، والقائمة الواحدة بتاريخ
/// كلّ سطر، و«حسب الشركة» بعناوين تُنقر — الأكبر ثمّ يقلب ثمّ ترتيب الحساب، ويُحفظ.
void main() {
  Widget host(Widget child, {double width = 320, double scale = 1.0}) => MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(size: Size(width, 900), textScaler: TextScaler.linear(scale)),
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(body: SingleChildScrollView(child: SizedBox(width: width, child: child))),
          ),
        ),
      );

  const fields = [
    rpDateField,
    OrderField('amount', 'المبلغ', OrderKind.number),
    OrderField('name', 'الاسم', OrderKind.text),
    OrderField('type', 'النوع', OrderKind.text),
  ];

  RpRow row(String title, num? amount) =>
      RpRow(icon: LucideIcons.zap, tone: RpTone.money, title: title, detail: 'تفعيل نقدي', amount: amount, time: '9:55 صباحاً');

  for (final scale in [1.0, 1.2]) {
    testWidgets('سطر «رتّب حسب» على 320 ×$scale: كلّ الرقائق كاملةً داخل الشاشة، والنقرة تصل', (t) async {
      t.view.physicalSize = const Size(320, 900);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final picked = <String>[];
      await t.pumpWidget(host(
        RpRowsCard(
          total: 2,
          days: [
            RpDay(date: '', count: 2, sum: null, flat: true, rows: [row('أحمد', 5000).withDate('2026/11/21'), row('بشير', null).withDate('2026/11/20')]),
          ],
          sort: RpRowsSort(fields: fields, value: const OrderValue('amount', OrderDir.desc), onPick: picked.add),
        ),
        scale: scale,
      ));
      expect(t.takeException(), isNull, reason: 'لا فيض');
      for (final f in fields) {
        final r = t.getRect(find.byKey(RpSortChips.chipKey(f.key)));
        expect(r.left >= 0 && r.right <= 320, isTrue, reason: '${f.label}: $r');
      }
      await t.tap(find.byKey(RpSortChips.chipKey('name')));
      expect(picked, ['name']);
      expect(find.byIcon(LucideIcons.arrowDown), findsOneWidget, reason: 'السهم على المرتَّب وحده');
      expect(find.text('2026/11/21'), findsOneWidget, reason: 'تاريخ السطر عليه');
      expect(find.byType(RpDayHead), findsNothing, reason: 'لا رأس يوم بالقائمة الواحدة');
    });
  }

  test('rpFlat: الحدّ والعدد والتاريخ على السطر', () {
    final list = List<int>.generate(5, (i) => i);
    final d = rpFlat<int>(list, 3, (i) => row('n$i', i), (i) => '2026/11/0$i');
    expect(d.single.flat, isTrue);
    expect(d.single.count, 5);
    expect([for (final r in d.single.rows) r.date], ['2026/11/00', '2026/11/01', '2026/11/02']);
    expect(rpFlat<int>(const [], 3, (i) => row('x', i), (i) => ''), isEmpty);
  });

  testWidgets('«حسب الشركة»: الأكبر ثمّ يقلب ثمّ ترتيب الحساب، والشركة أ ← ي، والمتعذّرة آخراً، ويُحفظ', (t) async {
    SharedPreferences.setMockInitialValues({});
    final lines = [
      const RpCompanyLine(company: RpCompany(key: 'a', name: 'شركة ألف', colorIndex: 0), a: 100, b: 5, c: 1),
      const RpCompanyLine(company: RpCompany(key: 'e', name: 'ايرث لنك', colorIndex: 1), a: 300, b: 1, c: 2),
      const RpCompanyLine(company: RpCompany(key: 'x', name: 'تالفة', colorIndex: 2), state: RpCompanyState.failed),
      const RpCompanyLine(company: RpCompany(key: 'c', name: 'كلاود ساس', colorIndex: 3), a: 200, b: 9, c: 3),
    ];
    Widget table() => host(RpSortedCompanyTable(sortKey: 'financial', heads: const ['الواصل', 'الدين', 'الربح'], lines: lines, total: const [600, 15, 6]), width: 390);
    List<String> order() => [for (final l in t.widget<RpCompanyTable>(find.byType(RpCompanyTable)).lines) l.company.name];
    await t.pumpWidget(table());
    await t.pump();
    expect(order(), ['شركة ألف', 'ايرث لنك', 'تالفة', 'كلاود ساس'], reason: 'ترتيب الحساب أوّلاً');
    await t.tap(find.byKey(RpCompanyTable.headKey(0)));
    await t.pump();
    expect(order(), ['ايرث لنك', 'كلاود ساس', 'شركة ألف', 'تالفة'], reason: 'الواصل الأكبر أوّلاً والمتعذّرة آخراً');
    await t.tap(find.byKey(RpCompanyTable.headKey(0)));
    await t.pump();
    expect(order(), ['شركة ألف', 'كلاود ساس', 'ايرث لنك', 'تالفة'], reason: 'الثانية تقلب — والمتعذّرة آخراً بالاتّجاهين');
    await t.tap(find.byKey(RpCompanyTable.headKey(0)));
    await t.pump();
    expect(order(), ['شركة ألف', 'ايرث لنك', 'تالفة', 'كلاود ساس'], reason: 'الثالثة ترجع ترتيب الحساب');
    await t.tap(find.byKey(RpCompanyTable.headKey(-1)));
    await t.pump();
    expect(order(), ['ايرث لنك', 'تالفة', 'شركة ألف', 'كلاود ساس'], reason: 'الشركة أ ← ي');
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    final p = await SharedPreferences.getInstance();
    expect(jsonDecode(p.getString('report.v2.financial.cosort')!), {'c': -1, 'd': 'asc'});
    // فتحٌ جديد على المحفوظ
    await t.pumpWidget(const SizedBox());
    await t.pumpWidget(table());
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await t.pump();
    expect(order(), ['ايرث لنك', 'تالفة', 'شركة ألف', 'كلاود ساس']);
    expect(t.takeException(), isNull);
  });

  testWidgets('«حسب الشركة» بلا sortKey: العناوين نصٌّ كما كانت (لا أزرار)', (t) async {
    await t.pumpWidget(host(
      const RpCompanyTable(
        heads: ['الواصل', 'الدين', 'الربح'],
        lines: [RpCompanyLine(company: RpCompany(key: 'a', name: 'أ', colorIndex: 0), a: 1, b: 2, c: 3)],
        total: [1, 2, 3],
      ),
      width: 390,
    ));
    expect(find.byKey(RpCompanyTable.headKey(0)), findsNothing);
    expect(find.text('الشركة'), findsNothing);
    expect(t.takeException(), isNull);
  });

  testWidgets('جدول الحاسبة (DeskBulkPicker): العنوان بـsortKey زرٌّ بسهمه، وبلا onSort نصٌّ كما كان', (t) async {
    t.view.physicalSize = const Size(1280, 800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final picked = <String>[];
    Widget picker({OrderValue? value, ValueChanged<String>? onSort}) => MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: DeskBulkPicker(
                searchController: TextEditingController(),
                searchHint: 'ابحث',
                columns: const [
                  DeskPickColumn('المشترك', flex: 3, sortKey: 'name'),
                  DeskPickColumn('الخصم', width: 110, sortKey: 'discount'),
                  DeskPickColumn('ملاحظة', width: 110),
                ],
                rowCount: 1,
                cellsOf: (_) => const [Text('a'), Text('b'), Text('c')],
                selectedOf: (_) => false,
                onToggle: null,
                allSelected: false,
                onToggleAll: null,
                footer: '1 نتيجة',
                panel: const SizedBox.shrink(),
                sortValue: value,
                onSort: onSort,
              ),
            ),
          ),
        );
    await t.pumpWidget(picker(value: const OrderValue('discount', OrderDir.desc), onSort: picked.add));
    expect(find.byKey(DeskBulkPicker.headKey('name')), findsOneWidget);
    expect(find.byKey(DeskBulkPicker.headKey('discount')), findsOneWidget);
    expect(find.byIcon(LucideIcons.arrowDown), findsOneWidget, reason: 'السهم على المرتَّب به وحده');
    await t.tap(find.byKey(DeskBulkPicker.headKey('name')));
    expect(picked, ['name']);
    await t.pumpWidget(picker());
    expect(find.byKey(DeskBulkPicker.headKey('name')), findsNothing, reason: 'بلا onSort: عناوين للعرض كما كانت');
    expect(t.takeException(), isNull);
  });
}
