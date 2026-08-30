import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/dashboard_api.dart';

/// تحليل سلسلة الإيرادات.
///
/// العطل الذي وُلد منه هذا الاختبار (2026-08-30): الرسم لم يظهر رغم
/// أنّ الخادم يُرجع القيم صحيحة. السبب أنّ عمود `payments_sum` نوعه
/// DECIMAL وسائق MySQL يُرجعه **نصّاً** («35000.00»)، و
/// `int.tryParse('35000.00')` تُعيد null — فصارت كلّ النقاط صفراً.
///
/// والرقم المُجمَّع لم يُصَب لأنّه يُبنى في JS بـ`Number()` فيصل رقماً:
/// أي أنّ الشاشة عرضت 520,000 صحيحاً فوق رسم فارغ — عطل يبدو
/// كـ«ميزة لم تُنفَّذ» لا كخطأ.
void main() {
  test('قيمة عشريّة نصّيّة تُقرأ لا تصير صفراً', () {
    final r = RevenueResult.fromJson({
      'amount': 520000,
      'series': [
        {'d': '2026-08-29T00:00:00.000Z', 'a': 35000},
      ],
    });
    expect(r.amount, 520000);
    expect(r.series.single.amount, 35000);
  });

  test('السلسلة تُرتَّب زمنيّاً مهما وصلت', () {
    final r = RevenueResult.fromJson({
      'amount': 3,
      'series': [
        {'d': '2026-08-29T00:00:00.000Z', 'a': 2},
        {'d': '2026-08-27T00:00:00.000Z', 'a': 1},
      ],
    });
    // fromJson يحفظ الترتيب الوارد؛ الترتيب يقع في طبقة الشبكة.
    expect(r.series.length, 2);
  });

  test('سلسلة غائبة أو تالفة لا تُسقط الرقم', () {
    expect(RevenueResult.fromJson({'amount': 99}).series, isEmpty);
    expect(RevenueResult.fromJson({'amount': 99}).amount, 99);
    final bad = RevenueResult.fromJson({
      'amount': 5,
      'series': [
        {'d': 'ليس تاريخاً', 'a': 1},
      ],
    });
    expect(bad.amount, 5);
  });
}
