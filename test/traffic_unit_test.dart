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

  test('التنسيق الكامل يحمل وحدته — للإجماليّات لا للأعمدة', () {
    expect(fmtBytes(660 * gb), contains('GB'));
    expect(fmtBytes(500 * mb), contains('MB'));
    expect(fmtBytes(0), '0');
  });
}
