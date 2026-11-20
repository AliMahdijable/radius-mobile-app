import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/screens/my_alerts/money_alerts_section.dart';

/// «إشعاراتي» — اختصار الآلاف في حقول المبالغ (المالك ٢٠ نوفمبر: «الارقام مال رصيد او اي شي من اكتبه لازم اكتب الالف
/// صصحها مثل البقية هو يكمل الاصفار مال الالف»): «50» ⇒ 50,000 كبقيّة حقول المال (AmountShorthand)، والتلميح «سيُحفظ …»
/// قبل الحفظ، والحفظ يوسّع ولو ضُغط والمؤشّر ما زال في الحقل؛ والمبلغ الكامل يبقى كما هو.
void main() {
  Future<void> phone(WidgetTester t) async {
    // شاشة هاتف (الافتراضيّ 800×600 يُخرج شريط «حفظ» عن الشاشة)
    t.view.physicalSize = const Size(1290, 2796);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
  }

  /// زرٌّ يفتح النافذة ويحفظ نتيجتها.
  Future<List<Object?>> host(WidgetTester t, Future<Object?> Function(BuildContext) open) async {
    final out = <Object?>[];
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (ctx) => Center(
            child: ElevatedButton(
              key: const ValueKey('open'),
              onPressed: () async => out.add(await open(ctx)),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await t.tap(find.byKey(const ValueKey('open')));
    await t.pumpAndSettle();
    return out;
  }

  testWidgets('نافذة المبلغ: «50» ⇒ «سيُحفظ 50,000» ثمّ يُحفظ 50,000 ولو ضُغط «حفظ» والمؤشّر في الحقل', (t) async {
    await phone(t);
    final out = await host(t, (ctx) => showAmountSheet(ctx, title: 'الحدّ الأدنى للرصيد', icon: Icons.wallet));
    await t.enterText(find.byKey(const ValueKey('ma-amount-field')), '50');
    await t.pump();
    expect(find.textContaining('سيُحفظ 50,000'), findsOneWidget, reason: 'التلميح قبل الحفظ');
    await t.tap(find.text('حفظ').last);
    await t.pumpAndSettle();
    expect(out, [50000]);
  });

  testWidgets('نافذة المبلغ: المبلغ الكامل يبقى كما هو، و«تمّ» توسّع الحقل نفسه', (t) async {
    await phone(t);
    var out = await host(t, (ctx) => showAmountSheet(ctx, title: 'سقف ديون المشتركين', icon: Icons.trending_up));
    await t.enterText(find.byKey(const ValueKey('ma-amount-field')), '1000000');
    await t.pump();
    expect(find.textContaining('سيُحفظ'), findsNothing);
    await t.tap(find.text('حفظ').last);
    await t.pumpAndSettle();
    expect(out, [1000000]);

    out = await host(t, (ctx) => showAmountSheet(ctx, title: 'سقف ديون المشتركين', icon: Icons.trending_up));
    await t.enterText(find.byKey(const ValueKey('ma-amount-field')), '750');
    await t.testTextInput.receiveAction(TextInputAction.done);
    await t.pump();
    expect(find.text('750,000'), findsOneWidget, reason: 'الحقل نفسه صار 750,000');
    await t.tap(find.text('حفظ').last);
    await t.pumpAndSettle();
    expect(out, [750000]);
  });

  testWidgets('نافذة المبلغ: القيمة الحاليّة تظهر بفواصلها، وزرّ المبلغ السريع يُحفظ كما هو', (t) async {
    await phone(t);
    final out = await host(
        t,
        (ctx) => showAmountSheet(ctx,
            title: 'الحدّ الأدنى للرصيد', icon: Icons.wallet, initial: 250000, quick: const [50000, 100000]));
    expect(find.text('250,000'), findsOneWidget);
    await t.tap(find.text('100,000'));
    await t.pump();
    await t.tap(find.text('حفظ').last);
    await t.pumpAndSettle();
    expect(out, [100000]);
  });

  testWidgets('«أي مديونين؟»: «من 5» و«إلى 200» ⇒ 5,000 و200,000 بالتلميح، و«من» أكبر من «إلى» بعد التوسيع ⇒ لا حفظ', (t) async {
    await phone(t);
    final out = await host(t, (ctx) => showDebtorsFilterSheet(ctx));
    await t.enterText(find.byKey(const ValueKey('ma-filter-min')), '5');
    await t.pump();
    await t.enterText(find.byKey(const ValueKey('ma-filter-max')), '200');
    await t.pump();
    expect(find.textContaining('سيُحفظ 200,000'), findsOneWidget);
    expect(find.text('5,000'), findsOneWidget, reason: 'الخروج من «من» وسّعها في الحقل نفسه');
    // «حفظ» والمؤشّر ما زال في «إلى» (200 بلا توسيعٍ في الحقل) ⇒ يُحفظ 200,000
    await t.tap(find.text('حفظ').last);
    await t.pumpAndSettle();
    expect(out.single, (minDays: null, minAmount: 5000, maxAmount: 200000));

    // الخروج من «إلى» يوسّعها في الحقل نفسه
    final out3 = await host(t, (ctx) => showDebtorsFilterSheet(ctx));
    await t.enterText(find.byKey(const ValueKey('ma-filter-max')), '300');
    await t.pump();
    await t.tap(find.byKey(const ValueKey('ma-filter-days')));
    await t.pump();
    expect(find.text('300,000'), findsOneWidget);
    await t.tap(find.text('حفظ').last);
    await t.pumpAndSettle();
    expect(out3.single, (minDays: null, minAmount: null, maxAmount: 300000));

    // 6 ⇒ 6,000 أكبر من 5,000 ⇒ «حفظ» معطّل والسبب ظاهر
    final out2 = await host(t, (ctx) => showDebtorsFilterSheet(ctx));
    await t.enterText(find.byKey(const ValueKey('ma-filter-min')), '6');
    await t.pump();
    await t.enterText(find.byKey(const ValueKey('ma-filter-max')), '5000');
    await t.pump();
    expect(find.textContaining('«من» أكبر من «إلى»'), findsOneWidget);
    await t.tap(find.text('حفظ').last);
    await t.pumpAndSettle();
    expect(out2, isEmpty, reason: 'لم يُحفظ');
  });
}
