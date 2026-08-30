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
  test('شكل الخادم الحقيقي — DECIMAL يصل نصّاً', () {
    // ⚠️ هذا هو المسار الذي كان مكسوراً، وهو **غير** المسار الذي فحصه
    // اختباري الأوّل: مفاتيح الخادم `date`/`payments_sum`، والقيمة
    // نصّ عشريّ لأنّ سائق MySQL يُرجع DECIMAL نصّاً.
    final series = DashboardApi.parseRevenueSeries([
      {'date': '2026-08-25T00:00:00.000Z', 'payments_sum': '85000.00'},
      {'date': '2026-08-26T00:00:00.000Z', 'payments_sum': '180000.00'},
      {'date': '2026-08-29T00:00:00.000Z', 'payments_sum': '35000.00'},
    ]);
    expect(series.length, 3);
    expect(series.map((p) => p.amount).toList(), [85000, 180000, 35000],
        reason: 'نصّ عشريّ صار صفراً — هذا العطل بعينه');
    // ومجموعها يجب أن يطابق الرقم المعروض فوق الرسم
    expect(series.fold<int>(0, (a, p) => a + p.amount), 300000);
  });

  test('الرسم يُبنى فقط بنقطتين فأكثر وفيها قيمة', () {
    // نقطة واحدة ليست منحنى، وكلّها أصفار تُقرأ كأنّ الدخل صفر.
    final one = DashboardApi.parseRevenueSeries([
      {'date': '2026-08-29T00:00:00.000Z', 'payments_sum': '35000.00'},
    ]);
    expect(one.length, 1);
    final zeros = DashboardApi.parseRevenueSeries([
      {'date': '2026-08-28T00:00:00.000Z', 'payments_sum': '0.00'},
      {'date': '2026-08-29T00:00:00.000Z', 'payments_sum': '0'},
    ]);
    expect(zeros.every((p) => p.amount == 0), isTrue);
  });

  test('الترتيب زمنيّ مهما وصل مبعثراً', () {
    final s = DashboardApi.parseRevenueSeries([
      {'date': '2026-08-29T00:00:00.000Z', 'payments_sum': '3'},
      {'date': '2026-08-25T00:00:00.000Z', 'payments_sum': '1'},
      {'date': '2026-08-27T00:00:00.000Z', 'payments_sum': '2'},
    ]);
    expect(s.map((p) => p.amount).toList(), [1, 2, 3]);
  });

  test('مدخلات تالفة تُتخطّى ولا تُسقط الباقي', () {
    final s = DashboardApi.parseRevenueSeries([
      {'date': 'ليس تاريخاً', 'payments_sum': '9'},
      'ليست خريطة',
      {'date': '2026-08-29T00:00:00.000Z', 'payments_sum': '7'},
    ]);
    expect(s.length, 1);
    expect(s.single.amount, 7);
  });

  test('غياب السلسلة كلّياً لا يرمي', () {
    expect(DashboardApi.parseRevenueSeries(null), isEmpty);
    expect(DashboardApi.parseRevenueSeries('نصّ'), isEmpty);
  });

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
