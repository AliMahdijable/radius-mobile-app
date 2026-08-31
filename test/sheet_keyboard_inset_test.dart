import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/core/widgets/design_sheet.dart';
import 'package:rad_mysvcs/theme/colors.dart';

/// كلّ شيت يحترم لوحة المفاتيح — لا المتمرّر منه فقط.
///
/// 🐛 بلاغ 2026-08-31: «فورم تعديل الأجهزة أكو أجزاء ما يكدر يرفع
/// المحتوى من يكتب أو يضيف».
///
/// السبب أنّ حشوة `viewInsets.bottom` كانت **داخل شرط `scrollable`**
/// وحده. فالشيت الذي يدير تمريره بنفسه يبقى بارتفاعه الكامل، وتُرسَم
/// لوحة المفاتيح فوق ثلثه السفلي، والحقل تحتها بلا حيلة.
///
/// وعشرون شيتاً في التطبيق تمرّر `scrollable: false` وتحمل حقولاً.
void main() {
  Future<double> bottomOfBody(WidgetTester t, {required bool scrollable}) async {
    AppColors.setDarkMode(false);
    const kb = 300.0;
    await t.pumpWidget(MaterialApp(
      home: MediaQuery(
        // نحاكي لوحة مفاتيح مفتوحة بـ300 نقطة.
        data: const MediaQueryData(
          size: Size(400, 800),
          viewInsets: EdgeInsets.only(bottom: kb),
        ),
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: Align(
            alignment: Alignment.bottomCenter,
            child: DesignSheet(
              scrollable: scrollable,
              header: const SizedBox(height: 40),
              body: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 100),
                  Container(key: const Key('field'), height: 40, color: Colors.red),
                ],
              ),
            ),
          ),
        ),
      ),
    ));
    await t.pump();
    final box = t.getRect(find.byKey(const Key('field')));
    return 800 - box.bottom; // المسافة من أسفل الشاشة
  }

  testWidgets('scrollable: true — الحقل فوق لوحة المفاتيح', (t) async {
    final gap = await bottomOfBody(t, scrollable: true);
    expect(gap, greaterThanOrEqualTo(300.0),
        reason: 'الحقل يجب أن يبقى فوق الـ300 نقطة التي تشغلها اللوحة');
  });

  testWidgets('scrollable: false — الحقل فوق لوحة المفاتيح أيضاً', (t) async {
    // هذا هو الاختبار الذي كان يسقط قبل الإصلاح: الحقل كان يقع داخل
    // منطقة لوحة المفاتيح فلا يراه المستخدم ولا يستطيع تمريره.
    final gap = await bottomOfBody(t, scrollable: false);
    expect(gap, greaterThanOrEqualTo(300.0),
        reason: 'الشيت غير المتمرّر لا يعلم بلوحة المفاتيح — العطل عاد');
  });

  testWidgets('الفرق يأتي من لوحة المفاتيح لا من حشوة دائمة', (t) async {
    // ⚠️ حكمٌ نسبيّ لا رقم مطلق: الشيت محاذٍ للأسفل وارتفاعه `min`،
    // فالمسافة من قاع الشاشة تعكس ارتفاعه هو — لا الحشوة وحدها.
    // المهمّ أن يكون الفارق **بقدر لوحة المفاتيح**: لا أقلّ (فتغطّي
    // الحقل) ولا أكثر (ففراغ ميّت دائم).
    AppColors.setDarkMode(false);

    Future<double> gapWith(EdgeInsets insets) async {
      await t.pumpWidget(MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(size: const Size(400, 800), viewInsets: insets),
          child: const Directionality(
            textDirection: TextDirection.rtl,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: DesignSheet(
                scrollable: false,
                header: SizedBox(height: 40),
                body: SizedBox(key: Key('field'), height: 40),
              ),
            ),
          ),
        ),
      ));
      await t.pump();
      return 800 - t.getRect(find.byKey(const Key('field'))).bottom;
    }

    final without = await gapWith(EdgeInsets.zero);
    final with300 = await gapWith(const EdgeInsets.only(bottom: 300));
    expect(with300 - without, closeTo(300, 1),
        reason: 'الإزاحة يجب أن تساوي ارتفاع اللوحة تماماً — '
            'بلا لوحة $without ومعها $with300');
  });
}
