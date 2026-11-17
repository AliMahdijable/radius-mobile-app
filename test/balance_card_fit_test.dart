import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/models/subscriber.dart';
import 'package:rad_mysvcs/screens/subscribers/subscriber_detail_screen.dart';
import 'package:rad_mysvcs/screens/subscribers/widgets/balance_card.dart';

import 'visual_perm/visual_perm_harness.dart';

/// أزرار بطاقة الرصيد لا تُقصّ كلمتها (١٧ نوفمبر — المالك: «صلحه»).
///
/// 🐛 «إضافة دين» كانت «إضاف…» في صفحة المشترك: ثلاثة أزرارٍ بأثلاثٍ متساوية، وكلمتان قصيرتان بجانب عبارةٍ أطول. قِيس على
/// الصفحة الحقيقيّة قبل الإصلاح: تُقصّ على عرض ٣٢٠ حتى بالخطّ العاديّ، وعلى ٣٦٠ بخطّ 1.1 فما فوق، وعلى ٣٧٥ بـ1.2.
///
/// ما يحرسه هذا الملفّ — بالرسم الفعليّ وخطّ التطبيق، لا بنصّ الكود:
///   • لا كلمة زرٍّ تُقصّ ولا تصغر، بكلّ عرض (٣٢٠–٤٨٠) وحجم خطّ (١–١٫٢) — على البطاقة وحدها وعلى صفحة المشترك الحقيقيّة؛
///   • حيث كانت تتّسع يبقى الشكل كما كان حرفاً (أثلاثٌ متساوية، صفٌّ واحد)؛
///   • حيث لا تتّسع متساويةً ويتّسع مجموعها: صفٌّ واحد بعروضٍ على قدر الكلمات (البطاقة لا تطول)؛
///   • وحيث لا يتّسع المجموع (٣٢٠ بخطّ 1.2): صفّان — «تسديد» تحت بعرض البطاقة؛
///   • والأزرار تُنقر كلّها في كلّ شكل، والمقفلة تبقى بمكانها.
const _widths = [320.0, 340.0, 360.0, 375.0, 390.0, 412.0, 430.0, 480.0];
const _scales = [1.0, 1.1, 1.2];
const _labels = ['إضافة دين', 'تذكير', 'تسديد'];

Subscriber _debtor() => Subscriber(
      username: 'u1',
      firstname: 'علي',
      lastname: 'حسن',
      mobile: '9647700000000',
      hasDebtFlag: true,
      debt: 5000,
    );

/// زرّ الكلمة [label]: إطاره (InkWell) وفقرته وهل قُصّت أو صغرت.
({Rect button, bool cut, double scale}) _button(WidgetTester t, String label) {
  final f = find.text(label);
  expect(f, findsOneWidget, reason: 'الزرّ «$label» ظاهر');
  final p = t.renderObject<RenderParagraph>(f);
  final fitted = t.renderObject<RenderBox>(find.ancestor(of: f, matching: find.byType(FittedBox)).first);
  final ink = t.renderObject<RenderBox>(find.ancestor(of: f, matching: find.byType(InkWell)).first);
  return (
    button: ink.localToGlobal(Offset.zero) & ink.size,
    cut: p.didExceedMaxLines,
    scale: p.size.width <= 0 ? 1.0 : (fitted.size.width / p.size.width).clamp(0.0, 1.0),
  );
}

/// لا كلمة مقصوصة ولا مصغَّرة، وكلّ زرٍّ داخل البطاقة.
void _expectAllWhole(WidgetTester t, String where, {Iterable<String> labels = _labels}) {
  for (final l in labels) {
    final b = _button(t, l);
    expect(b.cut, isFalse, reason: '«$l» مقصوصة — $where');
    expect(b.scale, greaterThan(0.999), reason: '«$l» صغرت (${b.scale.toStringAsFixed(3)}) — $where');
    expect(b.button.height, moreOrLessEquals(36, epsilon: 0.01), reason: 'ارتفاع الزرّ — $where');
  }
}

void main() {
  setUpAll(visualSetUpAll);

  group('توزيع الأزرار على الصفوف (حسابٌ صرف)', () {
    test('يملأ الصفّ ما دام يتّسع ثمّ ينزل؛ والحدّ بالضبط يتّسع', () {
      expect(debtButtonRows(const [], 258, 7), isEmpty);
      expect(debtButtonRows(const [93, 65, 72], 258, 7), [
        [0, 1, 2]
      ]);
      expect(debtButtonRows(const [102, 76, 80], 258, 7), [
        [0, 1],
        [2]
      ], reason: '٢٧٢ > ٢٥٨ ⇒ الأخير (تسديد) ينزل وحده');
      expect(debtButtonRows(const [86, 86, 86], 272, 7), [
        [0, 1, 2]
      ], reason: '٨٦×٣ + ١٤ = ٢٧٢ بالضبط');
      expect(debtButtonRows(const [86, 86, 86.5], 272, 7), [
        [0, 1],
        [2]
      ]);
      expect(debtButtonRows(const [200, 200], 258, 7), [
        [0],
        [1]
      ]);
      expect(debtButtonRows(const [300], 258, 7), [
        [0]
      ], reason: 'زرٌّ أعرض من الصفّ يأخذ صفّاً وحده');
      expect(debtButtonRows(const [100, 100, 100, 100], 258, 7), [
        [0, 1],
        [2, 3]
      ]);
      expect(debtButtonRows(const [150, 76, 80], 258, 7), [
        [0, 1],
        [2]
      ]);
      expect(debtButtonRows(const [200, 76, 80], 258, 7), [
        [0],
        [1, 2]
      ]);
    });
  });

  group('البطاقة وحدها', () {
    var taps = <String>[];

    Future<void> pumpCard(
      WidgetTester t,
      double width,
      double scale, {
      bool remind = true,
      bool pay = true,
      bool locked = false,
      Subscriber? sub,
      TextStyle? ambient,
    }) async {
      taps = <String>[];
      t.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
      await visualSetUp(s1bSasOwner);
      await pumpVisual(
        t,
        VisualDevice('fit', Size(width, 700), 1),
        home: (_) => Scaffold(
          body: Padding(
            // حشوة صفحة المشترك (١٦ من كلّ جهة)
            padding: const EdgeInsets.fromLTRB(16, 60, 16, 16),
            child: DefaultTextStyle.merge(
              style: ambient,
              child: BalanceCard(
                sub: sub ?? _debtor(),
                onAddDebt: locked ? null : () => taps.add('add'),
                onRemind: locked || !remind ? null : () => taps.add('remind'),
                onPay: locked || !pay ? null : () => taps.add('pay'),
                addDebtLocked: locked,
                remindLocked: locked && remind,
                payLocked: locked && pay,
              ),
            ),
          ),
        ),
      );
      await settle(t, seconds: 1);
    }

    Future<void> done(WidgetTester t) async {
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox.shrink());
      await t.pump(const Duration(seconds: 4));
      await visualTearDown();
    }

    testWidgets('لا كلمة تُقصّ ولا تصغر بأيّ عرضٍ وحجم خطّ — وصفّان على الأكثر', (t) async {
      for (final w in _widths) {
        for (final sc in _scales) {
          await pumpCard(t, w, sc);
          final where = 'عرض ${w.toInt()} × خطّ $sc';
          _expectAllWhole(t, where);
          final rows = {for (final l in _labels) _button(t, l).button.top.round()};
          expect(rows.length, lessThanOrEqualTo(2), reason: where);
          // الأزرار لا تتراكب ولا تخرج من البطاقة، ومجموع كلّ صفٍّ يملأ عرضها (٢٥٨ على ٣٢٠)
          final inner = w - 32 - 28 - 2; // حشوة الصفحة + حشوة البطاقة + حدّها
          for (final top in rows) {
            final rs = [for (final l in _labels) _button(t, l).button].where((r) => r.top.round() == top).toList()
              ..sort((a, b) => a.left.compareTo(b.left));
            final total = rs.fold<double>(0, (a, r) => a + r.width) + 7 * (rs.length - 1);
            expect(total, moreOrLessEquals(inner, epsilon: 0.5), reason: 'الصفّ يملأ البطاقة — $where');
            for (var i = 1; i < rs.length; i++) {
              expect(rs[i].left, moreOrLessEquals(rs[i - 1].right + 7, epsilon: 0.5), reason: 'الفاصل ٧ — $where');
            }
          }
          await done(t);
        }
      }
    });

    testWidgets('حيث كانت تتّسع: أثلاثٌ متساوية في صفٍّ واحد كما كانت (٣٦٠ بالخطّ العاديّ، و٣٩٠ فما فوق بأيّ خطّ)', (t) async {
      for (final (w, sc) in [(360.0, 1.0), (390.0, 1.0), (390.0, 1.2), (430.0, 1.2), (480.0, 1.0), (480.0, 1.2)]) {
        await pumpCard(t, w, sc);
        final rs = [for (final l in _labels) _button(t, l).button];
        expect({for (final r in rs) r.top.round()}.length, 1, reason: 'صفٌّ واحد — $w×$sc');
        final third = (w - 32 - 28 - 2 - 14) / 3;
        for (final r in rs) {
          expect(r.width, moreOrLessEquals(third, epsilon: 0.05), reason: 'ثلثٌ متساوٍ — $w×$sc');
        }
        // والبطاقة بارتفاعها كما كانت: سطر المبلغ ثمّ صفّ أزرارٍ واحد
        expect(t.getSize(find.byType(BalanceCard)).height, lessThan(sc > 1 ? 140 : 125), reason: 'لا تطول — $w×$sc');
        await done(t);
      }
    });

    testWidgets('لا تتّسع متساويةً ويتّسع مجموعها: صفٌّ واحد بعروضٍ على قدر الكلمات — البطاقة لا تطول', (t) async {
      for (final (w, sc) in [(320.0, 1.0), (320.0, 1.1), (360.0, 1.1), (360.0, 1.2), (375.0, 1.2)]) {
        await pumpCard(t, w, sc);
        final add = _button(t, 'إضافة دين').button;
        final remind = _button(t, 'تذكير').button;
        final pay = _button(t, 'تسديد').button;
        expect({add.top.round(), remind.top.round(), pay.top.round()}.length, 1, reason: 'صفٌّ واحد — $w×$sc');
        expect(add.width, greaterThan(remind.width + 10), reason: 'العبارة الأطول تأخذ أكثر — $w×$sc');
        expect(add.width, greaterThan(pay.width + 10), reason: '$w×$sc');
        _expectAllWhole(t, '$w×$sc');
        await done(t);
      }
    });

    testWidgets('لا يتّسع المجموع (٣٢٠ بخطّ 1.2): صفّان — «إضافة دين» و«تذكير» نصفان، و«تسديد» تحت بعرض البطاقة', (t) async {
      await pumpCard(t, 320, 1.2);
      final add = _button(t, 'إضافة دين').button;
      final remind = _button(t, 'تذكير').button;
      final pay = _button(t, 'تسديد').button;
      expect(add.top, moreOrLessEquals(remind.top, epsilon: 0.01));
      expect(pay.top, moreOrLessEquals(add.bottom + 7, epsilon: 0.5), reason: '«تسديد» في الصفّ التالي');
      expect(add.width, moreOrLessEquals(remind.width, epsilon: 0.05), reason: 'نصفان متساويان');
      expect(pay.width, moreOrLessEquals(258, epsilon: 0.5), reason: 'بعرض البطاقة كاملاً');
      expect(add.left, greaterThan(remind.left), reason: 'العربيّة: الأوّل إلى اليمين');
      // تطول بصفّ أزرارٍ واحد لا أكثر (٣٦ + ٧)
      expect(t.getSize(find.byType(BalanceCard)).height, lessThan(140 + 36 + 7 + 6));
      _expectAllWhole(t, '320×1.2');
      // تُنقر كلّها في الشكل الجديد
      for (final l in _labels) {
        await t.tap(find.text(l));
        await t.pump();
      }
      expect(taps, ['add', 'remind', 'pay']);
      await done(t);
    });

    testWidgets('النقر يصل زرّه في الصفّ الواحد غير المتساوي أيضاً', (t) async {
      await pumpCard(t, 320, 1.0);
      for (final l in _labels.reversed) {
        await t.tap(find.text(l));
        await t.pump();
      }
      expect(taps, ['pay', 'remind', 'add']);
      await done(t);
    });

    testWidgets('زرّان (بلا تذكير) وزرٌّ واحد (لا دين): صفٌّ واحد كاملاً بأضيق شاشةٍ وأكبر خطّ', (t) async {
      await pumpCard(t, 320, 1.2, remind: false);
      final add = _button(t, 'إضافة دين').button;
      final pay = _button(t, 'تسديد').button;
      expect(add.top, moreOrLessEquals(pay.top, epsilon: 0.01));
      expect(add.width, moreOrLessEquals(pay.width, epsilon: 0.05), reason: 'نصفان متساويان كما كانا');
      _expectAllWhole(t, 'زرّان 320×1.2', labels: const ['إضافة دين', 'تسديد']);
      await done(t);

      await pumpCard(t, 320, 1.2, remind: false, pay: false, sub: Subscriber(username: 'u2', firstname: 'نور', lastname: 'علي'));
      expect(find.text('تسديد'), findsNothing);
      expect(_button(t, 'إضافة دين').button.width, moreOrLessEquals(258, epsilon: 0.5));
      _expectAllWhole(t, 'زرٌّ واحد 320×1.2', labels: const ['إضافة دين']);
      await done(t);
    });

    testWidgets('المقفلة (موظّفٌ بلا صلاحيّة): بمكانها وبكلمتها كاملةً', (t) async {
      for (final (w, sc) in [(320.0, 1.0), (320.0, 1.2), (360.0, 1.2), (390.0, 1.0)]) {
        await pumpCard(t, w, sc, locked: true);
        _expectAllWhole(t, 'مقفلة $w×$sc');
        await t.tap(find.text('تسديد'));
        await t.pump();
        expect(taps, isEmpty, reason: 'المقفل لا يفتح شيئاً');
        await t.pump(const Duration(seconds: 3));
        await done(t);
      }
    });

    testWidgets('أضيق من أيّ هاتف (زرٌّ وحده لا يتّسع): كلّ زرٍّ بصفّه، والكلمة تصغر قليلاً ولا تُقصّ بـ«…»', (t) async {
      await pumpCard(t, 150, 1.2); // داخل البطاقة ٨٨ نقطة — أقلّ من حاجة «إضافة دين» وحدها
      final tops = [for (final l in _labels) _button(t, l).button.top];
      expect(tops[1], greaterThan(tops[0]), reason: 'كلّ زرٍّ بصفّه');
      expect(tops[2], greaterThan(tops[1]));
      final add = _button(t, 'إضافة دين');
      expect(add.cut, isFalse, reason: 'لا «…» أبداً');
      expect(add.scale, lessThan(1), reason: 'صغرت لتظهر كاملة');
      expect(add.scale, greaterThan(0.6));
      await done(t);
    });

    testWidgets('مسحٌ لكلّ عرضٍ بين ٣٠٠ و٤٢٠ (كلّ نقطتين) — بالخطّ العاديّ والعريض وبكلّ حجم: لا قصّ ولا تصغير عند أيّ حدّ', (t) async {
      for (final bold in [false, true]) {
        t.platformDispatcher.accessibilityFeaturesTestValue = FakeAccessibilityFeatures(boldText: bold);
        addTearDown(t.platformDispatcher.clearAccessibilityFeaturesTestValue);
        for (var w = 300.0; w <= 420; w += 2) {
          for (final sc in _scales) {
            await pumpCard(t, w, sc);
            _expectAllWhole(t, 'عرض ${w.toInt()} × خطّ $sc${bold ? ' عريض' : ''}');
            await done(t);
          }
        }
      }
    });

    testWidgets('نمط نصٍّ غريب فوق البطاقة لا يغيّر القرار: الكلمة تُقاس بنمط زرّها هو', (t) async {
      // الزرّ يرسم كلمته تحت `Material` خاصّ به (نمطه `bodyMedium`)، فتباعد كلماتٍ أو حجمٌ في ما فوق البطاقة لا يصلها —
      // والقياس يجب ألّا يتأثّر به: لا نزول لصفّين حيث تتّسع، ولا صفٌّ واحد حيث لا تتّسع.
      // (تباعد الكلمات لا الحروف: العربيّة المتّصلة لا يتغيّر عرضها بتباعد الحروف، و«إضافة دين» كلمتان.)
      for (final ambient in const [TextStyle(wordSpacing: 24), TextStyle(wordSpacing: -4)]) {
        await pumpCard(t, 390, 1.0, ambient: ambient);
        final rs = [for (final l in _labels) _button(t, l).button];
        expect({for (final r in rs) r.top.round()}.length, 1, reason: 'صفٌّ واحد كما بلا النمط الغريب — $ambient');
        expect(rs[0].width, moreOrLessEquals(rs[1].width, epsilon: 0.05), reason: 'أثلاثٌ متساوية — $ambient');
        _expectAllWhole(t, 'نمط محيط 390 — $ambient');
        await done(t);

        await pumpCard(t, 320, 1.2, ambient: ambient);
        _expectAllWhole(t, 'نمط محيط 320×1.2 — $ambient');
        expect({for (final l in _labels) _button(t, l).button.top.round()}.length, 2, reason: 'صفّان كما بلا النمط الغريب — $ambient');
        await done(t);
      }
    });

    testWidgets('«خطّ عريض» من إعدادات الهاتف: القياس يحسبه فلا تُقصّ', (t) async {
      t.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(boldText: true);
      addTearDown(t.platformDispatcher.clearAccessibilityFeaturesTestValue);
      for (final (w, sc) in [(320.0, 1.0), (320.0, 1.2), (360.0, 1.2)]) {
        await pumpCard(t, w, sc);
        _expectAllWhole(t, 'عريض $w×$sc');
        await done(t);
      }
    });
  });

  group('صفحة المشترك الحقيقيّة', () {
    testWidgets('أزرار الرصيد كاملة الكلمات بكلّ عرضٍ وحجم خطّ', (t) async {
      for (final w in const [320.0, 360.0, 375.0, 390.0, 480.0]) {
        for (final sc in _scales) {
          t.platformDispatcher.textScaleFactorTestValue = sc;
          addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
          await visualSetUp(s1bSasOwner);
          final sub = Subscriber.fromJson(Map<String, dynamic>.from(fixtureSubscribers[6])); // مدينٌ وله هاتف ⇒ الأزرار الثلاثة
          await pumpVisual(t, VisualDevice('page', Size(w, 2400), 1), home: (_) => SubscriberDetailScreen(sub: sub));
          await settle(t, seconds: 3);
          final where = 'الصفحة: عرض ${w.toInt()} × خطّ $sc';
          final card = find.byType(BalanceCard);
          expect(card, findsOneWidget, reason: where);
          for (final l in _labels) {
            final f = find.descendant(of: card, matching: find.text(l));
            expect(f, findsOneWidget, reason: '«$l» — $where');
            final p = t.renderObject<RenderParagraph>(f);
            expect(p.didExceedMaxLines, isFalse, reason: '«$l» مقصوصة — $where');
            final fitted = t.renderObject<RenderBox>(find.ancestor(of: f, matching: find.byType(FittedBox)).first);
            expect(fitted.size.width, greaterThanOrEqualTo(p.size.width - 0.01), reason: '«$l» صغرت — $where');
          }
          expect(t.takeException(), isNull, reason: where);
          await t.pumpWidget(const SizedBox.shrink());
          await t.pump(const Duration(seconds: 6));
          await visualTearDown();
        }
      }
    });
  });
}
