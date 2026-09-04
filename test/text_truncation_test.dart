import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/models/subscriber.dart';
import 'package:rad_mysvcs/screens/subscribers/widgets/subscriber_card_v3.dart';
import 'package:rad_mysvcs/theme/colors.dart';

/// كاشف **القصّ مع وجود فراغ** — النقطة العمياء التي تركها
/// `text_crush_test.dart` عمداً، فمرّ منها عطلٌ حقيقيّ.
///
/// ── ما رآه المستخدم ───────────────────────────────────────────────
/// 🐛 لقطة ٢٠٢٦-٠٩-٠٤: شريط آخر تسديد يقرأ «تسديد دين قبل 22…» —
/// مقصوصاً عند الرقم، وإلى يمينه فراغٌ واسع ثمّ «35,000 د.ع».
///
/// ── الآليّة ───────────────────────────────────────────────────────
/// `Spacer()` **هو** `Expanded(flex: 1)`. فحين يجاور `Flexible(flex: 1)`
/// يقتسمان الفراغ الحرّ **بالتساوي**:
///
///     Row(children: [
///       Icon(...), SizedBox(width: 8),
///       Flexible(child: Text('تسديد دين قبل 22 س', maxLines: 1)),
///       Spacer(),                    // ← يبتلع نصف الفراغ
///       Text('35,000 د.ع'),
///     ])
///
/// فيُحرم النصّ نصف المساحة المتاحة له، ويُقصّ وإلى جانبه فراغٌ فارغ.
///
/// ── ولماذا لم يمسكه حارسٌ قائم ────────────────────────────────────
/// | الحارس | لماذا فاته |
/// |---|---|
/// | الفيض الأحمر | `Expanded` لا يفيض — يضيق |
/// | `text_crush_test` | يستثني `maxLines`+`ellipsis` صراحةً |
/// | `flex_text_guard_test` | يشترط غياب `maxLines` — وهنا موجود |
///
/// ثلاثتها صحيحةٌ فيما تفحص. والقصّ المتعمَّد **سلوكٌ مشروع** — إلّا
/// حين يوجد فراغٌ غير مستعمَل في الصفّ نفسه. فالفراغ هو الدليل: نصٌّ
/// يُقصّ بينما جاره فراغٌ عرضُه عشرات النقاط ليس تصميماً بل عطل.
///
/// ⚠️ حدّ الكاشف: `maxLines == 1` وحده. لأكثر من سطر يصير «هل قُصّ؟»
/// سؤالاً عن عدد الأسطر لا عن العرض، و`getMaxIntrinsicWidth` تقيس سطراً
/// واحداً فتُنذر كذباً على كلّ نصٍّ يلتفّ التفافاً سليماً.

/// فراغٌ ميّت في الصفّ = `Spacer` بالضبط، لا كلّ ما ارتفاعه صفر.
///
/// ⚠️ التمييز جوهريّ ولا يُستغنى عنه: `SizedBox(width: 8)` — الفاصل
/// المتعمَّد بين أيقونةٍ ونصّ — ارتفاعُه صفرٌ أيضاً في الـ`Row`. فنسخةٌ
/// أولى من الكاشف عدّته «فراغاً ميّتاً» وأنذرت على كلّ صفٍّ فيه فاصل.
///
/// والعلامة الفارقة في `parentData` لا في المقاس: `Spacer` مرن
/// (`flex > 0`) فيبتلع ما تبقّى ويزاحم النصّ؛ والفاصل الثابت يأخذ
/// مقاسه المعلوم ولا يزاحم أحداً.
double _deadSpace(RenderFlex row) {
  if (!row.hasSize) return 0;
  var dead = 0.0;
  row.visitChildren((c) {
    if (c is! RenderBox || !c.hasSize) return;
    final pd = c.parentData;
    final flex = pd is FlexParentData ? (pd.flex ?? 0) : 0;
    // مرنٌ وفارغ = `Spacer`: يأخذ عرضاً ولا يعرض شيئاً.
    if (flex > 0 && c.size.height == 0 && c.size.width > 1) {
      dead += c.size.width;
    }
  });
  return dead;
}

List<String> findTruncatedWithSlack(WidgetTester t) {
  final bad = <String>[];

  void walk(RenderObject o, RenderFlex? row) {
    final here =
        (o is RenderFlex && o.direction == Axis.horizontal) ? o : row;

    if (o is RenderParagraph && o.hasSize && o.maxLines == 1 && here != null) {
      final needed = o.getMaxIntrinsicWidth(double.infinity);
      final truncated = o.size.width + 0.5 < needed;
      if (truncated) {
        final dead = _deadSpace(here);
        if (dead > 1.0) {
          final s = o.text.toPlainText();
          bad.add('«$s» عُرض بـ${o.size.width.toStringAsFixed(1)} '
              'ويحتاج ${needed.toStringAsFixed(1)} '
              '— وفي الصفّ نفسه فراغٌ ميّت ${dead.toStringAsFixed(1)}');
        }
      }
    }

    o.visitChildren((c) => walk(c, here));
  }

  walk(t.binding.renderViews.first, null);
  return bad;
}

Subscriber _sub() => Subscriber(
      username: 'mustafa.ba@popq',
      firstname: 'مصطفى باسم',
      lastname: 'محمود',
      mobile: '9647707800797',
      profileName: 'Economy--2',
      expiration: '2026-10-04 21:34:00',
      isOnlineFlag: true,
      sessionTime: 28740,
      remainingDays: 30,
      price: 35000,
      hasDebtFlag: false,
    );

Future<void> _pump(WidgetTester t, Widget child, double width) async {
  t.view.devicePixelRatio = 1.0;
  t.view.physicalSize = Size(width, 1200);
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SingleChildScrollView(child: child),
        ),
      ),
    ),
  ));
  await t.pump();
}

void main() {
  setUp(() => AppColors.setDarkMode(false));

  // ── الكاشف يجب أن يُطلق النار قبل أن نأتمنه ──────────────────────
  testWidgets('🔬 الكاشف يُمسك قصّاً مصنوعاً بجوار Spacer', (t) async {
    await _pump(
      t,
      Row(children: const [
        Flexible(
          child: Text('تسديد دين قبل 22 س',
              maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
        Spacer(),
        Text('35,000 د.ع'),
      ]),
      360,
    );
    expect(findTruncatedWithSlack(t), isNotEmpty,
        reason: 'الكاشف لم يرَ القصّ الذي صنعتُه له — فلا يُعتمد عليه');
  });

  testWidgets('🔬 ولا يُنذر حين لا فراغ — قصٌّ مشروع', (t) async {
    await _pump(
      t,
      Row(children: const [
        Expanded(
          child: Text(
            'اسمٌ طويلٌ جدّاً لمشتركٍ لا يتّسع له الصفّ مهما وسّعناه أبداً قطعاً',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Text('35,000 د.ع'),
      ]),
      360,
    );
    expect(findTruncatedWithSlack(t), isEmpty,
        reason: 'قصٌّ بلا فراغٍ ميّت سلوكٌ مقصود — الإنذار عليه ضجيج');
  });

  // ── والعطل الحقيقيّ: شريط آخر تسديد ──────────────────────────────
  //
  // ٣٣٨ يوماً و«قبل 22 س» و«35,000 د.ع» — أرقام اللقطة نفسها.
  for (final w in <double>[320, 360, 375, 393, 430]) {
    testWidgets('شريط آخر تسديد لا يُقصّ عند ${w.toInt()}px', (t) async {
      final paidAt = DateTime.now().toUtc().subtract(const Duration(hours: 22));
      await _pump(
        t,
        SubscriberCardV3(
          sub: _sub(),
          selected: false,
          lastPayment: {
            'date': paidAt.toIso8601String(),
            'amount': 35000,
          },
          onTap: () {},
          onLongPress: () {},
        ),
        w,
      );

      final bad = findTruncatedWithSlack(t);
      expect(bad, isEmpty, reason: 'نصٌّ قُصّ وبجانبه فراغ:\n${bad.join('\n')}');
    });
  }

  // ── والتأكيد الصريح: النصّ ينال **كلّ** ما تبقّى ──────────────────
  //
  // ⚠️ ولا يُقاس ذلك بعرضٍ مطلق. `flutter test` يستبدل خطّاً احتياطيّاً
  // كلّ محرفٍ فيه بعرض حجم الخطّ تماماً — قِيس: «تسديد دين قبل 22 س»
  // ١٨ محرفاً × ١٢٫٥ = ٢٢٥٫٥ بالضبط. فالخطّ الحقيقيّ
  // (IBM Plex Sans Arabic) أضيق من ذلك بنحو النصف، وأيّ تأكيدٍ على
  // «يجب أن يتّسع» يقيس الخطّ الاحتياطيّ لا التصميم.
  //
  // فالثابت الصحيح **نسبيّ**: عرض النصّ = عرض الصفّ ناقص الأبناء
  // الثابتة، بلا بقيّة. أي أنّه أخذ كلّ نقطةٍ متاحة. وهذا صحيحٌ مع أيّ
  // خطّ، ويسقط لحظة يعود `Spacer` أو مرنٌ ثانٍ يقتسم معه.
  testWidgets('نصّ «تسديد دين …» ينال كلّ العرض المتبقّي', (t) async {
    final paidAt = DateTime.now().toUtc().subtract(const Duration(hours: 22));
    await _pump(
      t,
      SubscriberCardV3(
        sub: _sub(),
        selected: false,
        lastPayment: {'date': paidAt.toIso8601String(), 'amount': 35000},
        onTap: () {},
        onLongPress: () {},
      ),
      360,
    );

    RenderParagraph? pay;
    RenderFlex? bar;
    void walk(RenderObject o, RenderFlex? row) {
      final here =
          (o is RenderFlex && o.direction == Axis.horizontal) ? o : row;
      if (o is RenderParagraph &&
          o.text.toPlainText().startsWith('تسديد دين') &&
          pay == null) {
        pay = o;
        bar = here;
      }
      o.visitChildren((c) => walk(c, here));
    }

    walk(t.binding.renderViews.first, null);
    expect(pay, isNotNull, reason: 'شريط آخر تسديد لم يُرسم أصلاً');
    expect(bar, isNotNull, reason: 'لم يُعثر على صفّ الشريط');

    // مجموع الأبناء الثابتة (الأيقونة + الفاصلان + المبلغ).
    var fixed = 0.0;
    var flexibles = 0;
    bar!.visitChildren((c) {
      if (c is! RenderBox || !c.hasSize) return;
      final pd = c.parentData;
      final flex = pd is FlexParentData ? (pd.flex ?? 0) : 0;
      if (flex > 0) {
        flexibles++;
      } else {
        fixed += c.size.width;
      }
    });

    expect(flexibles, 1,
        reason: '🚨 مرنٌ واحدٌ فقط في الشريط. اثنان = اقتسامٌ للفراغ '
            'وقصٌّ للنصّ — وهو العطل بعينه.');

    final available = bar!.size.width - fixed;
    expect(
      (pay!.size.width - available).abs() < 0.5,
      isTrue,
      reason: 'النصّ نال ${pay!.size.width.toStringAsFixed(1)} '
          'والمتاح ${available.toStringAsFixed(1)} — ضاعت '
          '${(available - pay!.size.width).toStringAsFixed(1)} نقطة',
    );
  });
}
