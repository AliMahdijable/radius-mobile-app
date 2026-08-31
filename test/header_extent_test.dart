import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// ارتفاع رأس الرئيسيّة ينمو مع سلّم الخطّ — لا كلّه.
///
/// 🐛 كان `static const double _contentHeight = 86;` — ثابتاً مهما
/// كبّر المستخدم خطّ النظام، فالنصّ ينمو داخل علبة لا تنمو ويُقصّ اسم
/// المدير وتُبتر شارة الواتساب.
///
/// ⚠️ والفخّ في الإصلاح لا في العطل: ضربُ الـ86 كلّه في السلّم يحجز
/// 103 نقطة حيث تكفي 94 عند 1.2 — فيعود الفراغ الميّت الذي أزاله
/// 0afcbbe حين شُدَّ الرأس من 108 إلى 86. الحشوات والحدود لا تكبر مع
/// الخطّ، فتُفصَل عن الجزء الذي يكبر.
///
/// حارس مصدريّ لأنّ الصنف خاصّ: لا يستطيع اختبار سلوكيّ بلوغه.
void main() {
  late String src;

  setUpAll(() {
    src = File('lib/screens/dashboard/dashboard_screen.dart').readAsStringSync();
  });

  String delegateBody() {
    final i = src.indexOf('class _PinnedHeaderDelegate');
    expect(i, greaterThan(0), reason: 'رُبّما أُعيدت تسمية الصنف');
    final j = src.indexOf('\nclass ', i + 1);
    return j > 0 ? src.substring(i, j) : src.substring(i);
  }

  test('الارتفاع محسوب لا ثابت', () {
    final body = delegateBody();
    expect(body.contains('static const double _contentHeight'), isFalse,
        reason: 'عاد الارتفاع ثابتاً — النصّ سينمو في علبة لا تنمو');
    expect(body.contains('double get _contentHeight'), isTrue);
    expect(body.contains('textScale'), isTrue);
  });

  test('الجزء الثابت مفصول عن الجزء الذي يكبر', () {
    final body = delegateBody();
    // لو ضُرب المجموع في السلّم لظهر رقمٌ واحد مضروباً بلا مُقابل ثابت.
    expect(body.contains('_fixedChrome'), isTrue,
        reason: 'الحشوات والحدود لا تكبر مع الخطّ — يجب فصلها');
    expect(body.contains('_textHeight * textScale + _fixedChrome'), isTrue);
    expect(body.contains('86 * textScale'), isFalse,
        reason: 'ضرب المجموع كلّه يعيد الفراغ الميّت الذي أزاله 0afcbbe');
  });

  test('shouldRebuild تقارن السلّم والشقّ العلوي', () {
    final body = delegateBody();
    expect(body.contains('old.textScale != textScale'), isTrue,
        reason: 'بلاها يبقى الرأس بارتفاعه القديم بعد تغيير حجم الخطّ');
    expect(body.contains('old.topInset != topInset'), isTrue,
        reason: 'بلاها لا يتكيّف الرأس مع تدوير الجهاز');
  });

  test('textScalerOf تُقرأ عند البناء — وإلّا لا تنشأ التبعيّة', () {
    // `MediaQuery.paddingOf` تبعيّة مقصورة على الحشوة، فتغيّر سلّم
    // الخطّ وحده لا يُعيد بناء الشاشة. قراءة `textScalerOf` في نفس
    // البناء هي ما يُنشئ التبعيّة — حذفها «تحسيناً» يُعيد العطل.
    expect(src.contains('MediaQuery.textScalerOf(context).scale(1)'), isTrue);
  });
}
