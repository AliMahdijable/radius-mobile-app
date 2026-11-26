import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/api/employee_ledger_api.dart';
import 'package:rad_mysvcs/core/widgets/design_sheet.dart';
import 'package:rad_mysvcs/screens/employees/employee_account_screen.dart';
import 'package:rad_mysvcs/screens/employees/employee_ledger_widgets.dart';
import 'package:rad_mysvcs/screens/employees/salary_due_card.dart';
import 'package:rad_mysvcs/screens/reports/v2/finance_report_v2_screen.dart';
import 'package:rad_mysvcs/screens/settlements/settlements_screen.dart';
import 'package:rad_mysvcs/services/permissions_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'employee_ledger/ledger_fixture.dart';
import 'visual_perm/visual_perm_harness.dart';

/// «الرواتب المستحقّة» بالتطبيق (٢٦ نوفمبر — المالك: «سويهن ال ٣» على اقتراح الراتب المستحقّ بـ«تسوية الحساب» و«تسوية مع الموظف»
/// والتقرير الماليّ وإشعار يوم الراتب؛ الخادم 87574fe والموقع 0006b1a): الردّ كما يرسله الخادم، البطاقة، «اصرفه من النقد الذي بيده»،
/// ونقر الإشعار.
Map<String, dynamic> dueJson({bool on = true}) => {
      'feature_enabled': on,
      'count': 2,
      'amount': 1500000,
      'employees': [
        {
          'employee': {'id': 7, 'username': 'emp1', 'name': 'أحمد'},
          'active': true,
          'due_count': 2,
          'due_amount': 1000000,
          'amount': 500000,
          'cycle': 'monthly',
          'with_commission': false,
          'first_due': {'key': '2026-10', 'label': 'تشرين الأوّل 2026', 'due_date': '2026-10-28'},
          'last_due': {'key': '2026-11', 'label': 'تشرين الثاني 2026', 'due_date': '2026-11-28'},
          'lapsed': 0,
        },
        {
          'employee': {'id': 8, 'username': 'emp2', 'name': null},
          'active': false,
          'due_count': 1,
          'due_amount': 500000,
          'amount': 500000,
          'cycle': 'weekly',
          'with_commission': true,
          'first_due': {'key': '2026-11-24', 'label': 'أسبوع 24 تشرين الثاني', 'due_date': '2026-11-24'},
          'last_due': {'key': '2026-11-24', 'label': 'أسبوع 24 تشرين الثاني', 'due_date': '2026-11-24'},
          'lapsed': 0,
        },
      ],
    };

/// يجيب `/salary-due` ويمرّر غيره لخادم الصور (للتقرير الماليّ — لا يُلمس اختبار التقرير نفسه).
class _DueOverVisual implements HttpClientAdapter {
  _DueOverVisual(this.inner, this.due);
  final HttpClientAdapter inner;
  final Map<String, dynamic>? due;
  int dueCalls = 0;

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? s, Future<void>? c) {
    if (o.path == '/api/v2/employee-ledger/salary-due') {
      dueCalls++;
      final body = due == null ? {'success': false} : {'success': true, 'data': due};
      return Future.value(ResponseBody.fromString(jsonEncode(body), due == null ? 404 : 200, headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      }));
    }
    return inner.fetch(o, s, c);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  group('الردّ', () {
    test('يُقرأ كما يرسله الخادم: المجموع والصفوف، والفترة بأرقامها كبقيّة التطبيق', () {
      final d = SalaryDue.fromJson(dueJson())!;
      expect(d.any, isTrue);
      expect(d.count, 2);
      expect(d.amount, 1500000);
      final a = d.of(7)!;
      expect(a.name, 'أحمد');
      expect(a.dueAmount, 1000000);
      expect(a.when, 'راتبان — من 2026/10', reason: 'الأقدم أوّلاً، بالأرقام لا اسم الشهر (المالك ١٦ نوفمبر)');
      final b = d.of(8)!;
      expect(b.name, 'emp2', reason: 'بلا اسم ⇒ اليوزر');
      expect(b.active, isFalse);
      expect(b.withCommission, isTrue);
      expect(b.when, 'أسبوع 2026/11/24');
      expect(d.of(9), isNull);
    });

    test('ثلاثة رواتب، والاسم الغائب، والميزة المطفأة', () {
      final j = dueJson();
      final rows = (j['employees'] as List).cast<Map<String, dynamic>>();
      rows[0]['due_count'] = 3;
      rows[1]['employee'] = {'id': 8, 'username': null, 'name': null};
      final d = SalaryDue.fromJson(j)!;
      expect(d.of(7)!.when, '3 رواتب — من 2026/10');
      expect(d.of(8)!.name, '#8');
      expect(SalaryDue.fromJson(dueJson(on: false)), isNull, reason: 'مطفأة لهذه الصفحة ⇒ لا بطاقة');
      expect(SalaryDue.fromJson({'feature_enabled': true, 'count': 0, 'amount': 0, 'employees': []})!.any, isFalse);
      expect(SalaryDue.fromJson('x'), isNull);
    });
  });

  group('الشاشات', () {
    late LedgerServer server;

    setUp(() async {
      FlutterSecureStorage.setMockInitialValues({});
      SharedPreferences.setMockInitialValues({});
      await EasyLocalization.ensureInitialized();
      server = LedgerServer();
      ApiClient.dio.httpClientAdapter = server;
      PermissionsService.debugReset();
      EmployeeLedgerState.reset();
    });

    tearDown(() {
      PermissionsService.debugReset();
      EmployeeLedgerState.reset();
    });

    Widget app(Widget child) => EasyLocalization(
          supportedLocales: const [Locale('ar'), Locale('en')],
          path: 'assets/translations',
          startLocale: const Locale('ar'),
          fallbackLocale: const Locale('ar'),
          saveLocale: false,
          assetLoader: const LedgerDiskLoader(),
          child: Builder(
            builder: (c) => MaterialApp(
              locale: c.locale,
              supportedLocales: c.supportedLocales,
              localizationsDelegates: c.localizationDelegates,
              home: Directionality(textDirection: TextDirection.rtl, child: child),
            ),
          ),
        );

    Future<void> phone(WidgetTester t, {double width = 400}) async {
      t.view.physicalSize = Size(width, 1600);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
    }

    Future<void> settle(WidgetTester t, {int frames = 20}) async {
      for (var i = 0; i < frames; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
    }

    Future<void> opener(WidgetTester t, Future<Object?> Function(BuildContext c) open, void Function(Object? r) onResult) async {
      await t.pumpWidget(app(Builder(
        builder: (c) => Scaffold(
          body: Center(child: TextButton(onPressed: () async => onResult(await open(c)), child: const Text('افتح'))),
        ),
      )));
      await t.pumpAndSettle();
      await t.tap(find.text('افتح'));
      await settle(t);
    }

    Finder key(String k) => find.byKey(ValueKey(k));
    final contract = jsonDecode(File('test/employee_ledger/payout_sources_contract.json').readAsStringSync()) as Map<String, dynamic>;

    testWidgets('الطلب هادئ: خادمٌ أقدم بلا المسار أو بلا صلاحيّة الرواتب ⇒ null بلا خطأ', (t) async {
      expect(await t.runAsync(EmployeeLedgerApi.salaryDue), isNull, reason: '404 كخادمٍ أقدم');
      server.salaryDueReply = (403, {'success': false, 'code': 'PERMISSION_DENIED', 'message': 'ليس لديك صلاحيّة'});
      expect(await t.runAsync(EmployeeLedgerApi.salaryDue), isNull);
      server
        ..salaryDueReply = null
        ..salaryDue = dueJson();
      final d = await t.runAsync(EmployeeLedgerApi.salaryDue);
      expect(d?.count, 2);
    });

    testWidgets('البطاقة: العنوان والمجموع وكلّ موظّفٍ بمبلغه وفترته، و«صرف» يفتح كشفه ويصرف ثمّ تُحدَّث الشاشة', (t) async {
      await phone(t, width: 360);
      var paid = 0;
      await t.pumpWidget(app(Scaffold(
        body: ListView(children: [SalaryDueCard(due: SalaryDue.fromJson(dueJson())!, note: 'ملاحظة', onPaid: () => paid++)]),
      )));
      await t.pumpAndSettle();
      expect(find.text('رواتب مستحقّة (2)'), findsOneWidget);
      expect(t.widget<Text>(key('salary-due-total')).data, '1,500,000 د.ع');
      expect(t.widget<Text>(key('salary-due-amount-7')).data, '1,000,000 د.ع');
      expect(t.widget<Text>(key('salary-due-when-7')).data, 'راتبان — من 2026/10');
      expect(find.text('emp2 (موقوف)'), findsOneWidget);
      expect(t.widget<Text>(key('salary-due-when-8')).data, 'أسبوع 2026/11/24 · وعمولته تُحسب عند الصرف');
      expect(find.text('ملاحظة'), findsOneWidget);
      expect(t.takeException(), isNull, reason: 'لا فيض عند 360');

      await t.tap(key('salary-due-pay-7'));
      await settle(t);
      expect(find.text('كشف الراتب'), findsWidgets, reason: 'كشف راتب الموظّف نفسه');
      await t.tap(find.text('صرف — يستلم 375,000 د.ع'));
      await settle(t);
      expect(server.bodiesOf('POST', '/api/v2/employee-ledger/7/payslip'), hasLength(1));
      expect(paid, 1, reason: 'صُرف ⇒ الشاشة تعيد أرقامها والمستحقّات');
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 6));
    });

    testWidgets('320 بخطٍّ 1.2: لا فيض في البطاقة ولا في صندوق التسوية (ذوق المالك: لا نصّ يخرج ولا رقم يُقصّ)', (t) async {
      await phone(t, width: 320);
      final big = SalaryDue.fromJson(dueJson()
        ..['amount'] = 125000000
        ..['employees'] = [
          {
            ...(dueJson()['employees'] as List).first as Map<String, dynamic>,
            'employee': {'id': 7, 'username': 'emp1', 'name': 'أحمد عبد الأمير حسين كاظم الموسوي'},
            'due_amount': 120000000,
          },
        ])!;
      await t.pumpWidget(app(MediaQuery(
        data: const MediaQueryData(size: Size(320, 1600), textScaler: TextScaler.linear(1.2)),
        child: Scaffold(body: ListView(children: [SalaryDueCard(due: big, note: 'ملاحظة طويلة تلتفّ على سطرين أو أكثر حين يضيق العرض')])),
      )));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      expect(t.widget<Text>(key('salary-due-amount-7')).data, '120,000,000 د.ع', reason: 'الرقم كاملاً');
    });

    testWidgets('«تسوية مع الموظف»: «راتبه المستحقّ» و«اصرفه من النقد الذي بيده» يفتح الكشف ومصدره «بيده» مختار، ثمّ معاينةٌ جديدة',
        (t) async {
      await phone(t);
      server
        ..salaryDue = dueJson()
        ..preview = (ledgerPreviewJson()..['sources'] = contract['manager']);
      await opener(t, (c) => showEmployeeSettleSheet(c, employeeId: 7, name: 'أحمد', canPaySalary: true), (_) {});
      expect(key('emp-settle-salary-due'), findsOneWidget);
      expect(find.text('راتبه المستحقّ — راتبان — من 2026/10'), findsOneWidget);
      expect(t.widget<Text>(key('emp-settle-salary-due-amount')).data, '1,000,000 د.ع');
      final previews = server.paths.where((x) => x == '/api/v2/employee-limits/7/settlement/preview').length;

      await t.tap(key('emp-settle-pay-salary'));
      await settle(t);
      await t.tap(find.text('صرف — يستلم 375,000 د.ع'));
      await settle(t, frames: 5);
      expect(key('emp-payslip-step-source'), findsOneWidget);
      // «بيده» مختارٌ سلفاً: «تأكيد الصرف» يعمل بلا اختيارٍ آخر، ويُرسَل «hand»
      expect(t.widget<SheetFooterBar>(key('emp-payslip-confirm')).enabled, isTrue);
      await t.tap(find.text('تأكيد الصرف'));
      await settle(t);
      final bodies = server.bodiesOf('POST', '/api/v2/employee-ledger/7/payslip');
      expect(bodies, hasLength(1));
      expect(bodies.single['source'], 'hand');
      expect(server.paths.where((x) => x == '/api/v2/employee-limits/7/settlement/preview').length, previews + 1,
          reason: 'معاينةٌ جديدة فتكمل التسوية بالباقي');
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 6));
    });

    testWidgets('«بيده» ليس بين مصادر الخادم ⇒ لا اختيار مسبق (يختار المدير بنفسه)', (t) async {
      await phone(t);
      server.preview = ledgerPreviewJson()
        ..['sources'] = [for (final s in contract['manager'] as List) if ((s as Map)['key'] != 'hand') s];
      await opener(t, (c) => showEmployeePayslipSheet(c, employeeId: 7, name: 'أحمد', initialSource: 'hand'), (_) {});
      await t.tap(find.text('صرف — يستلم 375,000 د.ع'));
      await settle(t, frames: 5);
      expect(key('emp-payslip-src-hand'), findsNothing);
      expect(t.widget<SheetFooterBar>(key('emp-payslip-confirm')).enabled, isFalse);
      expect(server.bodiesOf('POST', '/api/v2/employee-ledger/7/payslip'), isEmpty);
    });

    testWidgets('بلا صلاحيّة الصرف ⇒ لا صندوق ولا سؤال عن المستحقّات', (t) async {
      await phone(t);
      server.salaryDue = dueJson();
      await opener(t, (c) => showEmployeeSettleSheet(c, employeeId: 7, name: 'أحمد'), (_) {});
      expect(key('emp-settle-salary-due'), findsNothing);
      expect(server.paths, isNot(contains('/api/v2/employee-ledger/salary-due')));
    });

    testWidgets('موظّفٌ بلا مستحقّ ⇒ لا صندوق', (t) async {
      await phone(t);
      final j = dueJson();
      (j['employees'] as List).removeAt(0);
      server.salaryDue = j;
      await opener(t, (c) => showEmployeeSettleSheet(c, employeeId: 7, name: 'أحمد', canPaySalary: true), (_) {});
      expect(key('emp-settle-salary-due'), findsNothing);
    });

    testWidgets('«تسوية الحساب»: البطاقة بمستحقّ، ولا شيء بلا مستحقّ أو لخادمٍ أقدم', (t) async {
      await phone(t);
      server.salaryDue = dueJson();
      await t.pumpWidget(app(const SettlementsScreen()));
      await settle(t, frames: 30);
      await t.scrollUntilVisible(key('salary-due-card'), 300, scrollable: find.byType(Scrollable).first);
      expect(key('salary-due-card'), findsOneWidget);
      // «بس يظهر سعر الكلي والحركه» (المالك ٢٦ نوفمبر): بلا سطر شرحٍ تحت الموظّفين
      expect(find.byKey(const ValueKey('salary-due-note')), findsNothing);

      for (final none in [null, {'feature_enabled': true, 'count': 0, 'amount': 0, 'employees': <Object>[]}]) {
        server.salaryDue = none;
        await t.pumpWidget(app(const SizedBox()));
        await t.pumpWidget(app(const SettlementsScreen()));
        await settle(t, frames: 30);
        expect(key('salary-due-card'), findsNothing, reason: none == null ? 'خادمٌ أقدم' : 'مفعّلة ولا مستحقّ ⇒ لا بطاقةٌ فارغة');
      }
      expect(t.takeException(), isNull);
    });
  });

  group('التقرير الماليّ', () {
    setUpAll(visualSetUpAll);

    testWidgets('البطاقة تحت البطاقات بلا سطر شرح، ولا شيء لخادمٍ أقدم', (t) async {
      for (final due in [dueJson(), null]) {
        final a = _DueOverVisual(await visualSetUp(s1bSasOwner), due);
        ApiClient.dio.httpClientAdapter = a;
        await pumpVisual(t, const VisualDevice('', Size(430, 2400), 2), home: (_) => const FinanceReportV2Screen());
        for (var i = 0; i < 10; i++) {
          await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
          await t.pump(const Duration(milliseconds: 100));
        }
        expect(a.dueCalls, greaterThan(0));
        if (due != null) {
          await t.scrollUntilVisible(find.byKey(const ValueKey('salary-due-card')), 300, scrollable: find.byType(Scrollable).first);
          expect(find.byKey(const ValueKey('salary-due-card')), findsOneWidget);
          expect(find.byKey(const ValueKey('salary-due-note')), findsNothing, reason: '«بس يظهر سعر الكلي والحركه»');
        } else {
          expect(find.byKey(const ValueKey('salary-due-card')), findsNothing);
        }
        await t.pumpWidget(const SizedBox());
        await t.pump(const Duration(seconds: 6));
        await visualTearDown();
      }
    });
  });

  group('الإشعار', () {
    testWidgets('salary_due ⇒ قسم الموظّفين؛ غيره لا', (t) async {
      final nav = GlobalKey<NavigatorState>();
      final pushed = <Route<dynamic>>[];
      await t.pumpWidget(MaterialApp(navigatorKey: nav, navigatorObservers: [_Obs(pushed)], home: const SizedBox()));
      expect(pushed, hasLength(1), reason: 'الرئيسيّة');
      expect(await openSalaryDuePush(nav.currentState!, const {'type': 'employee_ops'}), isFalse);
      expect(await openSalaryDuePush(nav.currentState!, const {}), isFalse);
      expect(pushed, hasLength(1), reason: 'غير salary_due لا يفتح شيئاً');
      final f = openSalaryDuePush(nav.currentState!, const {'type': 'salary_due', 'screen': 'employees'});
      await t.pump();
      expect(pushed, hasLength(2), reason: 'قسم الموظّفين');
      nav.currentState!.pop();
      await t.pump();
      expect(await f, isTrue);
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 6));
    });
  });
}

class _Obs extends NavigatorObserver {
  _Obs(this.pushed);
  final List<Route<dynamic>> pushed;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => pushed.add(route);
}
