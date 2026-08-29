import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/core/util/amount_input.dart';

void main() {
  group('قاعدة اختصار الآلاف', () {
    test('ما دون الألف يُضرب في ألف', () {
      expect(AmountShorthand.expand(25), 25000);
      expect(AmountShorthand.expand(1), 1000);
      expect(AmountShorthand.expand(999), 999000);
    });

    test('الألف فما فوق يمرّ كما هو — لا مضاعفة مزدوجة', () {
      expect(AmountShorthand.expand(1000), 1000);
      expect(AmountShorthand.expand(25000), 25000);
      expect(AmountShorthand.expand(135000), 135000);
    });

    test('الصفر والسالب لا يتغيّران', () {
      expect(AmountShorthand.expand(0), 0);
      expect(AmountShorthand.expand(-5), -5);
    });

    test('التنسيق والقراءة متعاكسان', () {
      expect(AmountShorthand.format(25000), '25,000');
      expect(AmountShorthand.format(1915141), '1,915,141');
      expect(AmountShorthand.format(0), '');
      expect(AmountShorthand.parse('1,915,141'), 1915141);
      expect(AmountShorthand.parse('25,000 د.ع'), 25000);
      expect(AmountShorthand.parse(''), 0);
    });
  });

  group('AmountTextField', () {
    Future<void> pump(
        WidgetTester t, TextEditingController c, void Function(int) onValue,
        {bool shorthand = true}) async {
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Column(children: [
            AmountTextField(
                controller: c, onValue: onValue, shorthand: shorthand),
            const TextField(key: Key('other')),
          ]),
        ),
      ));
    }

    testWidgets('الكتابة تنسّق الآلاف حيّاً بلا توسيع', (t) async {
      final c = TextEditingController();
      var last = 0;
      await pump(t, c, (v) => last = v);
      await t.enterText(find.byType(TextField).first, '25000');
      await t.pump();
      expect(c.text, '25,000');
      expect(last, 25000);
    });

    testWidgets('التوسيع يقع عند خروج المؤشّر لا أثناء الكتابة', (t) async {
      final c = TextEditingController();
      var last = 0;
      await pump(t, c, (v) => last = v);
      await t.enterText(find.byType(TextField).first, '25');
      await t.pump();
      // أثناء الكتابة: لا توسيع بعد — وإلّا انكسر إدخال 25000.
      expect(c.text, '25');
      expect(last, 25);
      // التلميح يسبق التحويل
      expect(find.textContaining('سيُحفظ 25,000'), findsOneWidget);
      // الخروج من الحقل
      await t.tap(find.byKey(const Key('other')));
      await t.pumpAndSettle();
      expect(c.text, '25,000');
      expect(last, 25000);
    });

    testWidgets('قيمة ≥ ألف لا تتضاعف عند الخروج', (t) async {
      final c = TextEditingController();
      var last = 0;
      await pump(t, c, (v) => last = v);
      await t.enterText(find.byType(TextField).first, '30000');
      await t.pump();
      await t.tap(find.byKey(const Key('other')));
      await t.pumpAndSettle();
      expect(c.text, '30,000');
      expect(last, 30000);
    });

    testWidgets('shorthand:false يعطّل القاعدة لهذا الحقل', (t) async {
      final c = TextEditingController();
      var last = 0;
      await pump(t, c, (v) => last = v, shorthand: false);
      await t.enterText(find.byType(TextField).first, '25');
      await t.pump();
      expect(find.textContaining('سيُحفظ'), findsNothing);
      await t.tap(find.byKey(const Key('other')));
      await t.pumpAndSettle();
      expect(c.text, '25');
      expect(last, 25);
    });
  });
}
