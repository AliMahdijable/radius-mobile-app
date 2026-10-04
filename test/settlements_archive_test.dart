import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/archive_info.dart';
import 'package:rad_mysvcs/api/settlements_api.dart';

/// حرّاس عقد «تسوية الحساب» — على حمولاتٍ **منسوخةٍ حرفيّاً** من الخادم
/// الحيّ (`admin@poox`، ‏2026-10-04).
///
/// العقد في `docs/settlements-prompt.md` §٣ و§٤، والخادم في مستودعٍ آخر
/// لا نملك تغييره. فأيّ انحرافٍ في التحليل يظهر هنا لا على جهاز المدير.
void main() {
  group('معاينة البداية', () {
    // منسوخةٌ من GET /api/v2/settlements/preview-start?start=2026-09-01
    const live = '''
{"start": "2026-09-01", "start_at": "2026-08-31T21:00:00.000Z",
 "totals": {"cash_activations": {"sum": 0, "count": 0},
            "debt_payments": {"sum": 190000, "count": 8},
            "cash_in": 190000,
            "expenses": {"sum": 0, "count": 0},
            "new_debts": {"sum": 105000, "count": 3},
            "expected_amount": 190000},
 "collectors": [{"employee_id": null, "username": null, "name": null,
                 "cash_activations": {"sum": 0, "count": 0},
                 "debt_payments": {"sum": 190000, "count": 8},
                 "expenses": {"sum": 0, "count": 0},
                 "net_amount": 190000}]}''';

    final p = StartPreview.fromJson(jsonDecode(live))!;

    test('المجاميع تُقرأ من totals لا من الجذر', () {
      expect(p.expected, 190000);
      expect(p.cashIn, 190000);
      expect(p.debtPayments.sum, 190000);
      expect(p.debtPayments.count, 8);
      expect(p.newDebts.sum, 105000);
    });

    test('🚨 expected بلا الرصيد الافتتاحيّ', () {
      // ⚠️ الخادم لا يعرف الرصيد بعدُ — يكتبه المستخدم في الحقل.
      // فالمعروض `expected + opening`، وجمعُه هنا يَعُدّه مرّتين.
      expect(p.expected, p.cashIn - p.expenses.sum);
    });

    test('التسمية من ردّ الخادم لا من حالة الشاشة', () {
      // الردّ المتأخّر يحمل اختياره معه، فلا يُسمّى باسمٍ أحدث منه.
      expect(p.start, '2026-09-01');
    });

    test('المنفّذ بلا employee_id هو المدير', () {
      expect(p.collectors.single.isManager, isTrue);
      expect(p.collectors.single.net, 190000);
    });

    test('عدّ الحركات يجمع الثلاثة', () {
      expect(p.moveCount, 8);
    });

    test('فترةٌ خالية تُقرأ أصفاراً لا null', () {
      const empty = '''
{"start": "now", "start_at": "2026-10-04T05:49:23.393Z",
 "totals": {"cash_activations": {"sum": 0, "count": 0},
            "debt_payments": {"sum": 0, "count": 0}, "cash_in": 0,
            "expenses": {"sum": 0, "count": 0},
            "new_debts": {"sum": 0, "count": 0}, "expected_amount": 0},
 "collectors": []}''';
      final e = StartPreview.fromJson(jsonDecode(empty))!;
      expect(e.moveCount, 0);
      expect(e.expected, 0);
      expect(e.collectors, isEmpty);
    });

    test('جسمٌ غريب يرجع null ولا يرمي', () {
      expect(StartPreview.fromJson(null), isNull);
      expect(StartPreview.fromJson('nope'), isNull);
    });
  });

  group('وصف الأرشيف', () {
    test('الصرفيات: archive على الجذر', () {
      // منسوخةٌ من GET /api/admin/expenses?limit=2
      const live = '''
{"hidden": true, "included": false, "settlements": 1,
 "last_number": 2, "last_cut_at": "2026-10-03T18:27:50.000Z"}''';
      final a = ArchiveInfo.fromJson(jsonDecode(live))!;
      expect(a.hidden, isTrue);
      expect(a.included, isFalse);
      expect(a.settlements, 1);
      expect(a.lastNumber, 2);
      expect(a.lastCutAt, isNotNull);
      expect(a.show, isTrue);
    });

    test('🚨 صفر تسوياتٍ لا يُعرض شريطٌ أصلاً', () {
      final a = ArchiveInfo.fromJson(
          jsonDecode('{"hidden":false,"included":false,"settlements":0}'))!;
      expect(a.show, isFalse);
    });

    test('وغيابه كلّه لا يرمي', () {
      expect(ArchiveInfo.fromJson(null), isNull);
    });

    test('التوقيت يُقرأ UTC لا محلّيّاً', () {
      // 🐛 `DateTime.tryParse` العارية تُقدّم ثلاث ساعات على توقيتات
      // جدولنا — بلاغ ٢٠٢٦-٠٩-٠٤ المثبَّت في رأس `server_time.dart`.
      final a = ArchiveInfo.fromJson(jsonDecode(
          '{"hidden":true,"included":false,"settlements":1,'
          '"last_cut_at":"2026-10-03T18:27:50.000Z"}'))!;
      expect(a.lastCutAt!.toUtc().hour, 18);
      expect(a.lastCutAt!.toUtc().minute, 27);
    });
  });
}
