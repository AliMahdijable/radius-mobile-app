import 'dart:convert';
import 'dart:io';

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
      final a = ArchiveInfo.fromJson(
          jsonDecode('{"hidden":true,"included":false,"settlements":1,'
              '"last_cut_at":"2026-10-03T18:27:50.000Z"}'))!;
      expect(a.lastCutAt!.toUtc().hour, 18);
      expect(a.lastCutAt!.toUtc().minute, 27);
    });
  });

  group('الرفض يصل على المسار الحيّ لا في DioException', () {
    // 🐛 `validateStatus: s < 500` في `api_client.dart` يجعل الـ409
    // **نجاحاً** في نظر Dio. فكان `settle()` يكتب `code: null` حرفيّاً
    // على مسار الردّ، ويقرأ الرمز في فرع `on DioException` الذي لا
    // يُدخَل إلّا على 5xx — فمعالجة `STALE` و`HEAD_CHANGED` في
    // `settle_sheet.dart` شيفرةٌ ميّتة، والعقد §٣ يَعِد بها.
    //
    // ولأنّ العطل **غير مرئيّ** (يمرّ `analyze` ولا يرمي شيئاً)، الحارس
    // على نصّ المصدر: لا سبيل إلى اختبار 409 بلا حقن Dio.
    final api = File('lib/api/settlements_api.dart').readAsStringSync();

    test('🚨 settle لا تُصفّر code على مسار الردّ', () {
      // النافذة: من توقيع `settle` إلى سطر سجلّ الاستثناء. وما بعدها
      // فرع 5xx، وما قبلها دوالٌّ أخرى تُرجع `code: null` بحقٍّ عند
      // النجاح — فلا يصحّ فحص الملفّ كلّه.
      final from = api.indexOf('})> settle({');
      final to = api.indexOf("_log('settlements (POST)'");
      expect(from, greaterThan(0), reason: 'تغيّر توقيع settle');
      expect(to, greaterThan(from), reason: 'تغيّر اسم السجلّ');
      // ⚠️ تُستبعَد التعليقات: تعليقُ الإصلاح نفسه يذكر العبارة.
      final code = api
          .substring(from, to)
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');
      expect(code.contains('code: null'), isFalse,
          reason: 'عاد التصفير: الرفض 409 يصل ردّاً لا رميةً');
    });

    test('وتقرأ current من الجسم كي يُحدَّث الشيت', () {
      expect(api.contains("CurrentAccount.fromJson(body['current'])"), isTrue);
    });

    test('والشيت ما زال يستهلك الرمزين', () {
      final sheet = File('lib/screens/settlements/sheets/settle_sheet.dart')
          .readAsStringSync();
      expect(sheet.contains("'STALE'"), isTrue);
      expect(sheet.contains("'HEAD_CHANGED'"), isTrue);
    });
  });

  group('حبّة شريط الأرشيف محروسة', () {
    // §٩-٢: موظّفٌ بلا `settlements.view` لا يرى الشاشة. والصرفيات
    // والتقرير الماليّ صلاحيّتهما غير صلاحيّة التسوية، فالحبّة فيهما
    // كانت طريقاً جانبيّاً إلى شاشةٍ أُخفيت بقصد.
    test('🚨 لا دفعَ لـSettlementsScreen بلا فحص الصلاحيّة', () {
      final bar = File('lib/screens/settlements/widgets/archive_bar.dart')
          .readAsStringSync();
      final push = bar.indexOf('SettlementsScreen');
      expect(push, greaterThan(0));
      final guard = bar.indexOf("Perms.has('settlements.view')");
      expect(guard, greaterThan(0), reason: 'الحارس غائب');
      expect(guard, lessThan(push), reason: 'الحارس بعد الدفع لا قبله');
    });
  });

  group('الرفض لا يُقرَأ فراغاً', () {
    // 🐛 مراجعة الصلاحيّات ٢٠٢٦-١٠-٠٤: دوالّ القراءة كانت تُرجع قائمةً
    // فارغةً على 403، فتظهر «لا تسويات بعد» بجوار عدّادٍ يقول ٤٧ حركة.
    // والسبب نفسه في كلّ الملفّ: `validateStatus: s < 500` يجعل الـ4xx
    // ردّاً لا رميةً، فـ`_message(e, …)` لا يُدخَل إلّا على 5xx.
    final api = File('lib/api/settlements_api.dart').readAsStringSync();
    String bodyOf(String marker) {
      final i = api.indexOf(marker);
      expect(i, greaterThan(0), reason: 'تغيّرت العلامة: $marker');
      return api.substring(i, i + 1400);
    }

    for (final m in const [
      'list({',
      'movements({String settlement',
      '})> get(int id) async {',
    ]) {
      test('🚨 ${m.split('(').first} تقرأ success من الجسم', () {
        expect(bodyOf(m).contains("body['success'] != true"), isTrue,
            reason: 'الرفض 4xx يسقط في مسار النجاح بلا رسالة');
      });
    }

    test('وكلّها تحمل قناة رسالة', () {
      expect(api.contains('int total, String? message})'), isTrue,
          reason: 'list بلا قناة رسالة — الفراغ لا يُفرَّق عن المنع');
    });
  });

  group('تبديل الحساب محروسٌ بصلاحيّة التعديل', () {
    // 🚨 التبديل يجلب كلمة سرّ المدير الفرعيّ ويُسجّل الدخول بها، بينما
    // **رؤية** كلمة السرّ محكومةٌ بـ`managers.edit`. فكان الأضعف حرساً
    // هو الأقوى أثراً — والخادم لا يمنعه: الدخول شرعيٌّ بكلمة سرٍّ صحيحة.
    test('مدخل اللوحة يفحص managers.edit لا managers.view', () {
      final dash = File('lib/screens/dashboard/dashboard_screen.dart')
          .readAsStringSync();
      final i = dash.indexOf('AccountsScreen');
      expect(i, greaterThan(0));
      final before = dash.substring(0, i);
      final edit = before.lastIndexOf("Perms.has('managers.edit')");
      final view = before.lastIndexOf("Perms.has('managers.view')");
      expect(edit, greaterThan(0), reason: 'حارس التبديل غائب');
      expect(edit, greaterThan(view),
          reason: 'أقرب حارسٍ للتبديل ما زال managers.view');
    });

    test('والشاشة نفسها تفحص كذلك — لا المدخل وحده', () {
      final acc =
          File('lib/screens/accounts/accounts_screen.dart').readAsStringSync();
      expect(acc.contains("!Perms.has('managers.edit')"), isTrue,
          reason: 'مدخلٌ يُضاف غداً لا يعرف أن يفحص');
    });
  });
}
