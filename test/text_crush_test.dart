import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/models/subscriber.dart';
import 'package:rad_mysvcs/screens/subscribers/widgets/balance_card.dart';
import 'package:rad_mysvcs/theme/colors.dart';

/// كاشف **سحق النصّ** — صنفُ العطل الذي رآه المستخدم في لقطة
/// ٢٠٢٦-٠٩-٠٣: «دي / ن / عل / ى» حرفاً في كلّ سطر.
///
/// ── لماذا لم يمسكه شيء ─────────────────────────────────────────────
/// `Row` فيه `Expanded` **لا يفيض أبداً**. الفيض الأحمر يظهر حين
/// تتجاوز الأبناء الثابتة الحدّ بلا مرنٍ بينها؛ ومع `Expanded` ينجح
/// التخطيط بسحق المرن إلى الصفر. لا استثناء، ولا خطّ أصفر، ولا شكوى في
/// السجلّ — شاشةٌ مشوّهة واختباراتٌ خضراء.
///
/// واختبارات البطاقة كانت تفتّش **نصّ الملفّ**: هل الزرّ موجود؟ هل
/// الشرط أُزيل؟ كلّها مرّت وهي تصف واجهةً منهارة. الاختبار الذي لا
/// يرسم لا يرى التخطيط.
///
/// ── العلامة الدقيقة ───────────────────────────────────────────────
/// فقرةٌ تلتفّ (بلا `maxLines`) أُعطيت عرضاً **أقلّ من أعرض كلمةٍ
/// فيها** لا تجد مفرّاً من الكسر **داخل الكلمة**. وهذا لا يحدث في
/// تصميمٍ سليم أبداً: أضيق تخطيطٍ مقبول يسع أطول كلمة.
///
/// `getMinIntrinsicWidth` هو بالضبط «أعرض كلمة»، فالمقارنة مباشرة بلا
/// عتبةٍ مخمَّنة ولا نسبةٍ اعتباطيّة.
///
/// ⚠️ والمقصوص عمداً (`maxLines` + `ellipsis`) يُستثنى: هو يضيق
/// بإرادتنا، وقصُّه سلوكٌ مقصود لا انهيار.
List<String> findCrushedText(WidgetTester t) {
  final bad = <String>[];
  void walk(RenderObject o) {
    if (o is RenderParagraph) {
      final wraps = o.maxLines == null &&
          (o.overflow == TextOverflow.clip ||
              o.overflow == TextOverflow.visible);
      if (wraps && o.hasSize) {
        final longestWord = o.getMinIntrinsicWidth(double.infinity);
        // نصف نقطة تسامحاً مع تقريب الفاصلة العائمة.
        if (o.size.width + 0.5 < longestWord) {
          final s = o.text.toPlainText();
          bad.add('«${s.length > 30 ? '${s.substring(0, 30)}…' : s}» '
              'عُرض بـ${o.size.width.toStringAsFixed(1)} '
              'وأطول كلمةٍ فيه ${longestWord.toStringAsFixed(1)}');
        }
      }
    }
    o.visitChildren(walk);
  }

  walk(t.binding.renderViews.first);
  return bad;
}

Subscriber sub({double debt = -5000}) => Subscriber(
      username: 'ali.abbas@popq',
      firstname: 'ابو عباس',
      lastname: 'معامل',
      mobile: '9647707800797',
      hasDebtFlag: debt < 0,
      debt: debt.abs(),
    );

Future<void> pumpAt(WidgetTester t, Widget child, double width) async {
  t.view.devicePixelRatio = 1.0;
  t.view.physicalSize = Size(width, 900);
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: child,
        ),
      ),
    ),
  ));
  await t.pump();
}

void main() {
  setUp(() => AppColors.setDarkMode(false));

  // ── أوّلاً: هل الكاشف نفسه يعمل؟ ─────────────────────────────────
  //
  // كاشفٌ لا يُثبَت أنّه يُطلق النار حارسٌ زائف: يمرّ دائماً فيُطمئن
  // بلا سبب، وهو أسوأ من غيابه لأنّه يبدو كأنّه يحمي.
  testWidgets('🔬 الكاشف يُمسك سحقاً مصنوعاً عمداً', (t) async {
    await pumpAt(
      t,
      Row(children: [
        const Expanded(child: Text('دين على المشترك')),
        Container(width: 300, height: 20, color: Colors.red),
      ]),
      340,
    );
    expect(findCrushedText(t), isNotEmpty,
        reason: 'الكاشف لم يرَ نصّاً مسحوقاً أمامه — فلا قيمة له');
  });

  testWidgets('🔬 والنصّ السليم لا يُبلَّغ عنه', (t) async {
    await pumpAt(t, const Text('دين على المشترك'), 340);
    expect(findCrushedText(t), isEmpty);
  });

  // ── ثمّ: البطاقة التي انهارت فعلاً ───────────────────────────────
  //
  // ٣٢٠ أضيق شاشةٍ حيّة (Galaxy Fold مطويّاً · iPhone SE1)، و٣٧٥ هي
  // شاشة اللقطة نفسها.
  for (final w in [320.0, 360.0, 375.0, 393.0, 430.0]) {
    testWidgets('🚨 بطاقة الرصيد بأزرارها الثلاثة سليمة عند $w', (t) async {
      await pumpAt(
        t,
        BalanceCard(
          sub: sub(),
          onRemind: () {},
          onPay: () {},
          onAddDebt: () {},
        ),
        w,
      );
      expect(t.takeException(), isNull);
      expect(findCrushedText(t), isEmpty);
    });
  }

  testWidgets('البطاقة تبقى منخفضة — لا شريطاً عموديّاً', (t) async {
    // اللقطة أظهرتها بارتفاع ~٤٠٠ نقطة لأنّ المبلغ صار حرفاً في السطر.
    // بطاقةٌ سليمة سطران: المبلغ ثمّ الأزرار.
    await pumpAt(
      t,
      BalanceCard(
          sub: sub(), onRemind: () {}, onPay: () {}, onAddDebt: () {}),
      375,
    );
    final h = t.getSize(find.byType(BalanceCard)).height;
    expect(h, lessThan(140), reason: 'ارتفاع $h — البطاقة انهارت عموديّاً');
  });

  testWidgets('الحالات الثلاث ترسم بلا سحق', (t) async {
    for (final d in [-5000.0, 0.0, 12000.0]) {
      await pumpAt(
        t,
        BalanceCard(
            sub: sub(debt: d), onPay: () {}, onAddDebt: () {}),
        320,
      );
      expect(findCrushedText(t), isEmpty, reason: 'الرصيد $d');
    }
  });

  testWidgets('زرٌّ واحد لا يترك فراغاً ولا يفيض', (t) async {
    await pumpAt(t, BalanceCard(sub: sub(), onAddDebt: () {}), 320);
    expect(t.takeException(), isNull);
    expect(findCrushedText(t), isEmpty);
  });
}
