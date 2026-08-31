import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/core/widgets/design_sheet.dart';
import 'package:rad_mysvcs/theme/colors.dart';

/// الشيت كلّه يعلو فوق لوحة المفاتيح، والنقر في أيّ فراغ يُغلقها.
///
/// 🐛 بلاغان في يوم واحد (2026-08-31):
///
/// 1. «فورم تعديل الأجهزة أكو أجزاء ما يكدر يرفع المحتوى من يكتب» —
///    حشوة `viewInsets` كانت داخل شرط `scrollable` وحده، فالشيت الذي
///    يدير تمريره بنفسه لا يعلم بلوحة المفاتيح إطلاقاً. عشرون شيتاً.
///
/// 2. «المودل من أنقر سعر ما أكدر أخرج منه أو أزر ماكو» — وهذا كشف أنّ
///    إصلاحي الأوّل ناقص: رفعتُ **الجسم** وتركتُ الزرّ. والزرّ شقيقٌ
///    أسفل الجسم في عمود الشيت، والشيت ملتصق بقاع الشاشة — فبقي تحت
///    اللوحة. الحكم أدناه يقيس **الزرّ** لهذا السبب: هو ما يراه
///    المستخدم، والجسم وحده كان يمرّ في الاختبار القديم بينما العطل قائم.
///
/// 3. «كل المودلات الي بيها الكيبورد رقم ما تكدر تخرج بالنقر ع أي
///    مكان» — لوحة الأرقام بلا زرّ «تمّ» في النظامين.
void main() {
  const kb = 300.0;
  const screenH = 800.0;

  // ⚠️ سطح الاختبار الافتراضيّ 800×600 — لا 400×800 كما تُوهم
  // `MediaQueryData`. تلك تغيّر ما **تقرأه** الودجات لا حجم اللوحة
  // الفعليّ، فحسابٌ من 800 كان يمرّ لسببٍ خاطئ ويُخفي العطل نفسه الذي
  // وُجد ليمسكه.

  /// تُستدعى داخل كلّ اختبار — `setSurfaceSize` تشترط `inTest`.
  Future<void> useRealSurface(WidgetTester t) async {
    await t.binding.setSurfaceSize(const Size(400, screenH));
    addTearDown(() => t.binding.setSurfaceSize(null));
  }

  Future<void> pumpSheet(
    WidgetTester t, {
    required bool scrollable,
    required double inset,
    TextEditingController? ctrl,
  }) async {
    await useRealSurface(t);
    AppColors.setDarkMode(false);
    await t.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(
          size: const Size(400, screenH),
          viewInsets: EdgeInsets.only(bottom: inset),
        ),
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: Material(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: DesignSheet(
                scrollable: scrollable,
                header: const SizedBox(height: 40),
                body: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(key: Key('gap'), height: 80),
                    if (ctrl != null)
                      TextField(key: const Key('field'), controller: ctrl),
                  ],
                ),
                footer: Container(
                  key: const Key('footer'),
                  height: 50,
                  color: Colors.green,
                ),
              ),
            ),
          ),
        ),
      ),
    ));
    await t.pump();
  }

  for (final scrollable in [true, false]) {
    testWidgets('الزرّ فوق لوحة المفاتيح — scrollable: $scrollable', (t) async {
      await pumpSheet(t, scrollable: scrollable, inset: kb);
      final footer = t.getRect(find.byKey(const Key('footer')));
      expect(screenH - footer.bottom, greaterThanOrEqualTo(kb),
          reason: 'زرّ الإجراء تحت لوحة المفاتيح — المستخدم يكتب ولا يجد '
              'ما يضغطه. أسفل الزرّ عند ${footer.bottom}');
    });
  }

  testWidgets('بلا لوحة مفاتيح يلتصق الشيت بالقاع — لا فراغ ميّت', (t) async {
    await pumpSheet(t, scrollable: false, inset: 0);
    final footer = t.getRect(find.byKey(const Key('footer')));
    expect(screenH - footer.bottom, lessThan(2.0),
        reason: 'الإصلاح يجب ألّا يرفع الشيت حين لا لوحة');
  });

  testWidgets('الإزاحة تساوي ارتفاع اللوحة تماماً', (t) async {
    await pumpSheet(t, scrollable: false, inset: 0);
    final a = t.getRect(find.byKey(const Key('footer'))).bottom;
    await pumpSheet(t, scrollable: false, inset: kb);
    final b = t.getRect(find.byKey(const Key('footer'))).bottom;
    expect(a - b, closeTo(kb, 1),
        reason: 'لا أقلّ (فتغطّي الزرّ) ولا أكثر (ففراغ ميّت)');
  });

  testWidgets('النقر في الفراغ يُغلق لوحة المفاتيح', (t) async {
    final ctrl = TextEditingController();
    await pumpSheet(t, scrollable: false, inset: 0, ctrl: ctrl);
    await t.tap(find.byKey(const Key('field')));
    await t.pump();
    expect(t.binding.focusManager.primaryFocus?.hasFocus, isTrue,
        reason: 'الحقل يجب أن يتلقّى التركيز أوّلاً');

    // لوحة الأرقام بلا زرّ «تمّ» — فالنقر في الفراغ هو المخرج الوحيد.
    await t.tap(find.byKey(const Key('gap')));
    await t.pump();
    final f = t.binding.focusManager.primaryFocus;
    expect(
        f == null || !f.hasFocus || f.context?.widget is! EditableText, isTrue,
        reason: 'النقر في الفراغ لم يُلغِ التركيز — المستخدم يعلق');
  });

  testWidgets('النقر على الزرّ يصله ولا يبتلعه كاشف الإغلاق', (t) async {
    var tapped = false;
    await useRealSurface(t);
    AppColors.setDarkMode(false);
    await t.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(size: Size(400, screenH)),
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: Align(
            alignment: Alignment.bottomCenter,
            child: DesignSheet(
              scrollable: false,
              header: const SizedBox(height: 40),
              body: const SizedBox(height: 60),
              footer: SizedBox(
                height: 50,
                child: ElevatedButton(
                  key: const Key('btn'),
                  onPressed: () => tapped = true,
                  child: const Text('تطبيق'),
                ),
              ),
            ),
          ),
        ),
      ),
    ));
    await t.pump();
    await t.tap(find.byKey(const Key('btn')));
    await t.pump();
    expect(tapped, isTrue,
        reason: 'كاشف الإغلاق ابتلع نقرة الزرّ — الشيت صار بلا إجراء');
  });
}
