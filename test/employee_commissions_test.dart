import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/api/employee_commissions_api.dart';
import 'package:rad_mysvcs/api/reports_api.dart';
import 'package:rad_mysvcs/screens/employees/employee_commissions_card.dart';
import 'package:rad_mysvcs/screens/reports/v2/activations_view.dart';
import 'package:rad_mysvcs/screens/reports/v2/activity_log_view.dart';
import 'package:rad_mysvcs/screens/reports/v2/finance_report_v2_screen.dart';

import 'visual_perm/visual_perm_harness.dart';

/// «عمولات الموظفين» بالتطبيق (٢٦ نوفمبر — المالك: «شون رح يميز ٥ الالف رحت للموظف» ثمّ «تمام الي تشوف افضل سوي»؛ الخادم 0713445
/// والموقع 120f127): الردّ كما يرسله الخادم، نصّ «عمولة الموظف» على سطور السجلّ والتفعيلات، البطاقة (والـ320)، وظهورها بالتقرير الماليّ.
Map<String, dynamic> commJson({bool on = true}) => {
      'feature_enabled': on,
      'employees': [
        {
          'employee': {'id': 12, 'username': 'ahmed', 'name': 'أحمد علي'},
          'active': true,
          'pay_mode': 'commission',
          'in_payslip': true,
          'ops': 20,
          'amount': 100000,
          'unpaid_ops': 6,
          'unpaid': 30000,
        },
        {
          'employee': {'id': 13, 'username': 'ali.h', 'name': null},
          'active': false,
          'pay_mode': 'salary',
          'in_payslip': false,
          'ops': 4,
          'amount': 12000,
          'unpaid_ops': null,
          'unpaid': null,
        },
        {
          'employee': {'id': 14, 'username': 'sara', 'name': 'سارة'},
          'active': true,
          'pay_mode': 'both',
          'in_payslip': true,
          'ops': 0,
          'amount': 0,
          'unpaid_ops': 0,
          'unpaid': 0,
        },
      ],
      'totals': {'ops': 24, 'amount': 112000, 'payslip_amount': 100000, 'unpaid': 30000, 'paid_in_period': 70000},
      'by_activity': {'501': 5000, '502': 5000, 'x': 1, '503': 0},
    };

/// يجيب `/commissions` ويمرّر غيره لخادم الصور (التقرير الماليّ كما هو).
class _CommOverVisual implements HttpClientAdapter {
  _CommOverVisual(this.inner, this.comm);
  final HttpClientAdapter inner;
  final Map<String, dynamic>? comm;
  final calls = <Map<String, dynamic>>[];

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? s, Future<void>? c) {
    if (o.path == '/api/v2/employee-ledger/commissions') {
      calls.add(o.queryParameters);
      final body = comm == null ? {'success': false} : {'success': true, 'data': comm};
      return Future.value(ResponseBody.fromString(jsonEncode(body), comm == null ? 404 : 200, headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      }));
    }
    return inner.fetch(o, s, c);
  }

  @override
  void close({bool force = false}) {}
}

ActivityRow _act(int id, String desc) =>
    ActivityRow(id: id, actionType: 'SUBSCRIBER_ACTIVATE', actionDescription: desc, createdAt: '2026-11-26 10:15:00');

void main() {
  group('الردّ', () {
    test('يُقرأ كما يرسله الخادم: الصفوف والمجاميع وخريطة السطور (الأرقام وحدها)، والمطفأ ⇒ null', () {
      final c = EmpCommissions.fromJson(commJson())!;
      expect(c.any, isTrue);
      expect([c.ops, c.amount, c.payslipAmount, c.unpaid, c.paidInPeriod], [24, 112000, 100000, 30000, 70000]);
      expect(c.byActivity, {501: 5000.0, 502: 5000.0}, reason: 'مفتاحٌ غير رقميّ وقيمةٌ صفر لا تُقرأ');
      expect(c.of(501), 5000);
      expect(c.of(503), isNull);
      expect(c.of(999), isNull);
      const z = EmpCommissions(employees: [], ops: 0, amount: 0, payslipAmount: 0, unpaid: 0, paidInPeriod: 0, byActivity: {7: 0});
      expect(z.of(7), isNull, reason: 'شارةٌ بصفر لا تُعرض ولو وصلت');
      final a = c.employees.firstWhere((e) => e.employeeId == 12);
      expect([a.name, a.inPayslip, a.ops, a.unpaidOps, a.unpaid], ['أحمد علي', true, 20, 6, 30000.0]);
      final b = c.employees.firstWhere((e) => e.employeeId == 13);
      expect([b.name, b.active, b.inPayslip, b.unpaid], ['ali.h', false, false, null], reason: 'بلا اسم ⇒ اليوزر؛ أجره راتبٌ ⇒ لا «غير مصروف»');
      expect(EmpCommissions.fromJson(commJson(on: false)), isNull);
      expect(EmpCommissions.fromJson('x'), isNull);
      expect(EmpCommissions.fromJson({'feature_enabled': true, 'employees': [], 'totals': {}, 'by_activity': {}})!.any, isFalse);
    });

    test('«صافي الربح بعد العمولات»: الصافي − عمولة عمليّات الفترة لمن تُصرف بكشفه + ما صُرف منها بالفترة (لا عدّ مرّتين)', () {
      final c = EmpCommissions.fromJson(commJson())!;
      expect(c.netAfter(2011000), 1981000);
      expect(c.hasNetAdjust, isTrue);
      final j = commJson();
      j['totals'] = {'ops': 4, 'amount': 12000, 'payslip_amount': 0, 'unpaid': 0, 'paid_in_period': 0};
      expect(EmpCommissions.fromJson(j)!.hasNetAdjust, isFalse, reason: 'أجورٌ براتبٍ وحده ⇒ لا سطر «بعد العمولات»');
    });

    test('الجمع العربيّ ونصّ السطر', () {
      expect([empOpsText(0), empOpsText(1), empOpsText(2), empOpsText(4), empOpsText(10), empOpsText(11), empOpsText(20)],
          ['0 عملية', 'عملية واحدة', 'عمليتان', '4 عمليات', '10 عمليات', '11 عملية', '20 عملية']);
      expect(empCommissionText(5000), 'عمولة الموظف 5,000 د.ع');
      expect(withEmpCommission(null, null), isNull);
      expect(withEmpCommission(null, 0), isNull);
      expect(withEmpCommission('منها بالدين 10,000', 5000), 'منها بالدين 10,000 · عمولة الموظف 5,000 د.ع');
    });
  });

  group('السطور', () {
    test('سجلّ الحركات: «عمولة الموظف» تحت مبلغ العمليّة الكاملة وحدها، ومن days بالدالّة', () {
      final r = _act(501, 'تفعيل نقدي - المستخدم: u1 | السعر: 150000 د.ع');
      expect(ActivityLogView.row(r).cost, isNull, reason: 'بلا عمولة كما كان');
      expect(ActivityLogView.row(r, commission: 5000).cost, 'عمولة الموظف 5,000 د.ع');
      final c = EmpCommissions.fromJson(commJson())!;
      final days = ActivityLogView.days([r, _act(503, 'تفعيل غير نقدي - المستخدم: u3 | السعر: 35000 د.ع | الدين: 35000 د.ع')],
          commissionOf: (x) => c.of(x.id));
      final costs = days.expand((d) => d.rows).map((x) => x.cost).toList();
      expect(costs, ['عمولة الموظف 5,000 د.ع', null]);
    });

    test('التفعيلات: بعد «منها بالدين» إن وُجد، ومن days بالدالّة', () {
      final r = _act(502, 'تفعيل نقدي - المستخدم: u2 | السعر: 35000 د.ع');
      expect(ActivationsView.row(r).cost, isNull);
      expect(ActivationsView.row(r, commission: 5000).cost, 'عمولة الموظف 5,000 د.ع');
      final days = ActivationsView.days([r], commissionOf: (_) => 3000);
      expect(days.single.rows.single.cost, 'عمولة الموظف 3,000 د.ع');
    });
  });

  group('البطاقة', () {
    for (final w in [320.0, 430.0]) {
      testWidgets('الصفوف والمجموع و«بعد العمولات» بلا فيضٍ على $w', (t) async {
        final c = EmpCommissions.fromJson(commJson())!;
        await t.pumpWidget(MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(body: SingleChildScrollView(child: SizedBox(width: w, child: EmployeeCommissionsCard(c: c, net: 2011000)))),
          ),
        ));
        await t.pump();
        expect(find.byKey(const ValueKey('emp-comm-card')), findsOneWidget);
        expect(find.text('عمولات الموظفين (24 عملية)'), findsOneWidget);
        expect(find.byKey(const ValueKey('emp-comm-12')), findsOneWidget);
        expect(find.byKey(const ValueKey('emp-comm-13')), findsOneWidget);
        expect(find.byKey(const ValueKey('emp-comm-14')), findsNothing, reason: 'بلا عمليّاتٍ بالفترة ⇒ لا سطر');
        // «بس يظهر سعر الكلي والحركه» (المالك ٢٦ نوفمبر): الاسم وعدد العمليّات والمبلغ — لا حالة صرفٍ ولا سطر شرح
        expect(find.text('20 عملية'), findsOneWidget);
        expect(find.text('4 عمليات'), findsOneWidget);
        expect(find.text('100,000 د.ع'), findsOneWidget);
        expect(find.textContaining('لم تُصرف'), findsNothing);
        expect(find.textContaining('للعرض'), findsNothing);
        expect(find.textContaining('للعلم'), findsNothing);
        expect(find.byKey(const ValueKey('emp-comm-note')), findsNothing);
        expect(find.text('1,981,000 د.ع'), findsOneWidget);
        expect(t.takeException(), isNull);
      });
    }

    testWidgets('بلا ما يُطرح أو بلا صافٍ ⇒ لا سطر «بعد العمولات»', (t) async {
      final j = commJson();
      j['totals'] = {'ops': 4, 'amount': 12000, 'payslip_amount': 0, 'unpaid': 0, 'paid_in_period': 0};
      for (final args in [(EmpCommissions.fromJson(j)!, 100000), (EmpCommissions.fromJson(commJson())!, null)]) {
        await t.pumpWidget(MaterialApp(home: Scaffold(body: EmployeeCommissionsCard(c: args.$1, net: args.$2))));
        await t.pump();
        expect(find.byKey(const ValueKey('emp-comm-net')), findsNothing);
      }
    });
  });

  group('التقرير الماليّ', () {
    setUpAll(visualSetUpAll);

    testWidgets('البطاقة تحت البطاقات بفترة التقرير، ولا شيء لخادمٍ أقدم أو بلا صلاحيّة', (t) async {
      for (final comm in [commJson(), null]) {
        final a = _CommOverVisual(await visualSetUp(s1bSasOwner), comm);
        ApiClient.dio.httpClientAdapter = a;
        await pumpVisual(t, const VisualDevice('', Size(430, 2400), 2), home: (_) => const FinanceReportV2Screen());
        for (var i = 0; i < 10; i++) {
          await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
          await t.pump(const Duration(milliseconds: 100));
        }
        expect(a.calls, isNotEmpty);
        expect(a.calls.first['date_from'], matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')));
        expect(a.calls.first['date_to'], matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')));
        if (comm != null) {
          await t.scrollUntilVisible(find.byKey(const ValueKey('emp-comm-card')), 300, scrollable: find.byType(Scrollable).first);
          expect(find.byKey(const ValueKey('emp-comm-total')), findsOneWidget);
        } else {
          expect(find.byKey(const ValueKey('emp-comm-card')), findsNothing);
        }
        await t.pumpWidget(const SizedBox());
        await t.pump(const Duration(seconds: 6));
        await visualTearDown();
      }
    });
  });
}
