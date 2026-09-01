import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/screens/subscribers/sheets/consumption_sheet.dart';

/// وحدة الاستهلاك تُعلَن ولا تُخمَّن.
///
/// 🐛 بلاغ 2026-09-01: «القيم ليش بس أرقام بدون وحدات — شمعرّفه هو
/// كيغا ميغا كيلو بايت تيرا؟». كنتُ أقصّ الوحدة لتوفير عرض العمود،
/// فصار الرقم بلا معنى: «23» قد تكون 23 كيلو أو 23 تيرا.
void main() {
  const gb = 1000 * 1000 * 1000;
  const mb = 1000 * 1000;
  const kb = 1000;

  test('الوحدة تُشتقّ من أعلى عمود', () {
    expect(unitForTest(20 * gb).name, 'GB');
    expect(unitForTest(500 * mb).name, 'MB');
    expect(unitForTest(700 * kb).name, 'KB');
    expect(unitForTest(400).name, 'B');
  });

  test('العتبة تماماً عند الحدّ', () {
    expect(unitForTest(gb).name, 'GB');
    expect(unitForTest(gb - 1).name, 'MB');
  });

  test('كلّ الأعمدة بنفس الوحدة — وإلّا فسدت المقارنة', () {
    // ⚠️ هذا جوهر الإصلاح: عمود 500 ميغا وآخر 20 غيغا لا يُقارَنان
    // برقمين بوحدتين مختلفتين، رغم أنّ العمودين نفسيهما يُقارَنان.
    final u = unitForTest(20 * gb);
    expect(scaledForTest(20 * gb, u.div), '20');
    expect(scaledForTest(500 * mb, u.div), '0.50');
    // الاثنان بالغيغا: 20 مقابل 0.50 — نسبةٌ تُقرأ بالنظر.
  });

  test('الصفر لا يُكتب — العمود الفارغ لا يحمل رقماً', () {
    expect(scaledForTest(0, gb), '');
  });

  test('الدقّة تتناسب مع الحجم فلا تُقصّ في عمود ضيّق', () {
    const d = gb;
    expect(scaledForTest(660 * gb, d), '660'); // ثلاث خانات بلا كسر
    expect(scaledForTest(23 * gb, d), '23');
    expect(scaledForTest((1.5 * gb).round(), d), '1.5');
    expect(scaledForTest((0.25 * gb).round(), d), '0.25');
  });

  test('أطول نصّ عمود يتّسع في 58 نقطة', () {
    // ⚠️ الفاصلة غيّرت الحساب: «1,200GB» ثمانية محارف لا سبعة. العمود
    // وُسّع من 46 إلى 58 لأجلها، وهذا الحكم يحرس الاثنين معاً — من
    // يضيّق العمود أو يُطيل التنسيق يصطدم به.
    const u = (div: 1000 * 1000, name: 'MB');
    // أسوأ حالة واقعيّة: 4 خانات + فاصلة + وحدة.
    final longest = scaledForTest(1200 * u.div, u.div) + u.name;
    expect(longest, '1,200MB');
    expect(longest.length, lessThanOrEqualTo(8),
        reason: 'نصّ أطول من 8 محارف يُقصّ في عمود 58 نقطة: «$longest»');
  });

  group('فاصلة الآلاف', () {
    test('تُدرَج كلّ ثلاث خانات', () {
      expect(groupForTest('600'), '600');
      expect(groupForTest('1200'), '1,200');
      expect(groupForTest('4896'), '4,896');
      expect(groupForTest('12345'), '12,345');
      expect(groupForTest('1234567'), '1,234,567');
    });

    test('الكسر لا يُقسَّم', () {
      // ⚠️ التجميع على الجزء الصحيح وحده — «1.500» ليست ألفاً ونصفاً.
      expect(groupForTest('1.5'), '1.5');
      expect(groupForTest('1234.5'), '1,234.5');
      expect(groupForTest('0.25'), '0.25');
    });

    test('الحدود', () {
      expect(groupForTest(''), '');
      expect(groupForTest('1'), '1');
      expect(groupForTest('999'), '999');
      expect(groupForTest('1000'), '1,000');
    });
  });

  test('عمود كبير يحمل فاصلة', () {
    const mb = 1000 * 1000;
    // 1200 ميغا بوحدة MB → «1,200»
    expect(scaledForTest(1200 * mb, mb), '1,200');
  });

  test('التنسيق الكامل يحمل وحدته — للإجماليّات لا للأعمدة', () {
    expect(fmtBytes(660 * gb), contains('GB'));
    expect(fmtBytes(500 * mb), contains('MB'));
    expect(fmtBytes(0), '0');
  });
}
