import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/api/employee_ledger_api.dart';
import 'package:rad_mysvcs/api/employee_limits_api.dart' hide MoneyCount;
import 'package:rad_mysvcs/api/employees_api.dart';
import 'package:rad_mysvcs/api/expenses_api.dart';
import 'package:rad_mysvcs/api/reports_api.dart';
import 'package:rad_mysvcs/api/settlements_api.dart';
import 'package:rad_mysvcs/core/util/format.dart';
import 'package:rad_mysvcs/screens/employees/employee_account_screen.dart';
import 'package:rad_mysvcs/screens/employees/employee_ledger_widgets.dart';
import 'package:rad_mysvcs/screens/employees/employee_my_ledger_screen.dart';
import 'package:rad_mysvcs/screens/employees/employees_screen.dart';
import 'package:rad_mysvcs/screens/employees/sheets/employee_editor_sheet.dart';
import 'package:rad_mysvcs/screens/reports/widgets/action_labels.dart';
import 'package:rad_mysvcs/screens/reports/widgets/report_log_tile.dart';
import 'package:rad_mysvcs/screens/settlements/settle_widgets.dart';
import 'package:rad_mysvcs/services/permissions_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'employee_ledger/ledger_fixture.dart';

/// «حركات الموظف» وراتبه (١٣ نوفمبر): النماذج، لوحة «له / عليه»، «حركة جديدة»، «كشف الراتب» (ما تراه هو ما يُصرف)، حقول الراتب
/// في المحرّر، منتقي الإضافة السريعة، بطاقة الموظّف، وأثرها في الصندوق والتقرير الماليّ والصرفيات والتسوية مع الموظف.
void main() {
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
    t.view.physicalSize = Size(width, 1400);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
  }

  /// إطاراتٌ بزمنٍ محدود (لا pumpAndSettle حين تدور دوّارةٌ أو إشعار).
  Future<void> settle(WidgetTester t, {int frames = 20}) async {
    for (var i = 0; i < frames; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  /// زرٌّ يفتح ورقةً ويحفظ ما أعادته.
  Future<void> opener(WidgetTester t, Future<Object?> Function(BuildContext c) open, void Function(Object? r) onResult) async {
    await t.pumpWidget(app(Builder(
      builder: (c) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () async => onResult(await open(c)),
            child: const Text('افتح'),
          ),
        ),
      ),
    )));
    await t.pumpAndSettle();
    await t.tap(find.text('افتح'));
    await settle(t);
  }

  Finder field(String key) => find.descendant(of: find.byKey(ValueKey(key)), matching: find.byType(TextField));

  group('النماذج', () {
    test('الحساب من JSON الخادم: له/عليه، القروض، الحركات، الكشوف، الراتب', () {
      final a = LedgerAccount.fromJson(ledgerAccountJson())!;
      expect(a.summary.employeeId, 7);
      expect(a.summary.displayName, 'أحمد');
      expect(a.summary.owed, 100000);
      expect(a.summary.loansTotal, 400000);
      expect(a.summary.owesTotal, 500000);
      expect(a.summary.duePending, 25000);
      expect(a.summary.salary.amount, 500000);
      expect(a.summary.salary.payDay, 28);
      expect(a.summary.salary.dueCount, 1);
      expect(a.summary.salaryDue, isTrue);
      expect(a.loans.single.remaining, 400000);
      expect(a.movements, hasLength(3));
      expect(a.movements.first.kind, 'advance');
      expect(a.movements.first.fromHand, isTrue);
      expect(a.movements.first.isMinus, isTrue);
      expect(a.movements[1].byEmployee, 'cashier');
      expect(a.movements[2].voided, isTrue);
      expect(a.movements[2].voidReason, 'سُجّلت خطأً');
      expect(a.payslips, hasLength(2));
      expect(a.latestPaid!.id, 3, reason: 'آخر كشفٍ مصروف — الملغى لا يُحسب');
      expect(a.payslips.first.periodLabels, ['تشرين الأوّل 2026']);
      expect(a.payslips.first.deducted, 150000);
      expect(a.featureEnabled, isTrue);
    });

    test('ردٌّ بلا موظّف ⇒ null (لا حساب بأصفار)', () {
      expect(LedgerAccount.fromJson({'owed': 0}), isNull);
      expect(LedgerAccount.fromJson(null), isNull);
      expect(LedgerSummary.fromJson({'employee': {'id': 0}}), isNull);
    });

    test('وصف الراتب: شهريّ، أسبوعيّ، عمولة، الاثنان، وغير المضبوط', () {
      String money(num v) => v.round().toString();
      expect(const LedgerSalary(amount: 500000, payDay: 28, configured: true).describe(money), '500000 شهريّاً — يوم 28');
      expect(const LedgerSalary(amount: 100000, weekly: true, payDay: 4, configured: true).describe(money), '100000 أسبوعيّاً — الخميس');
      expect(const LedgerSalary(mode: 'commission', configured: true).describe(money), 'عمولة العمليّات');
      expect(const LedgerSalary(amount: 300000, payDay: 1, mode: 'both', configured: true).describe(money), '300000 شهريّاً — يوم 1 + عمولة العمليّات');
      expect(const LedgerSalary(amount: 500000).describe(money), isNull, reason: 'غير مضبوط ⇒ لا سطر');
    });

    test('«عليه / له / خصم» للقائمة', () {
      LedgerSummary s({double owes = 0, double due = 0}) => LedgerSummary(employeeId: 1, owesTotal: owes, duePending: due);
      expect(ledgerBalanceText(s(owes: 100000, due: 25000))!.text, 'عليه 100,000');
      expect(ledgerBalanceText(s(owes: 100000))!.owes, isTrue);
      expect(ledgerBalanceText(s(due: 25000))!.text, 'له 25,000');
      expect(ledgerBalanceText(s(due: 25000))!.owes, isFalse);
      expect(ledgerBalanceText(s(due: -10000))!.text, 'خصم 10,000');
      expect(ledgerBalanceText(s()), isNull);
      expect(ledgerBalanceText(null), isNull);
    });

    test('المعاينة: لا تُصرف بلا expected، وأقساط القروض المستقطعة وحدها', () {
      final p = PayslipPreview.fromJson(ledgerPreviewJson())!;
      expect(p.canPay, isTrue);
      expect(p.selectedKeys, ['2026-11']);
      expect(p.gross, 525000);
      expect(p.net, 375000);
      expect(p.recover, 100000);
      expect(p.loanTakes, hasLength(1));
      expect(p.loanTakes.single.take, 50000);
      expect(p.bonusCount, 1);
      expect(p.cut['ledger_id'], 42);
      final no = PayslipPreview.fromJson(ledgerPreviewJson()
        ..['can_pay'] = true
        ..['expected'] = null)!;
      expect(no.canPay, isFalse, reason: 'بلا أرقامٍ يُؤكَّد بها لا «صرف»');
      expect(PayslipPreview.fromJson({'gross': 1}), isNull, reason: 'بلا cut ليست معاينة');
    });

    test('مفتاح منع التكرار بصيغة الخادم، ويتجدّد', () {
      final re = RegExp(r'^[A-Za-z0-9_-]{8,64}$');
      final a = EmployeeLedgerApi.newRef('m');
      final b = EmployeeLedgerApi.newRef('m');
      expect(re.hasMatch(a), isTrue, reason: a);
      expect(a, isNot(b));
    });

    test('المبلغ كما سيُحفظ: اختصار الآلاف يُطبَّق ولو لم يخرج المؤشّر', () {
      expect(ledgerAmountOf(TextEditingController(text: '25')), 25000);
      expect(ledgerAmountOf(TextEditingController(text: '100,000')), 100000);
      expect(ledgerAmountOf(TextEditingController(text: '')), 0);
    });

    test('من أنا: المدير يدير، الموظّف بالصلاحيّة يدير ولا يُعدّ مديراً، والمطفأة لا أحد', () {
      const mgr = LedgerMe(isEmployee: false, featureEnabled: true, canManage: true);
      expect(mgr.manages, isTrue);
      expect(mgr.isManager, isTrue);
      const payroll = LedgerMe(isEmployee: true, featureEnabled: true, canManage: true);
      expect(payroll.manages, isTrue);
      expect(payroll.isManager, isFalse);
      const plain = LedgerMe(isEmployee: true, featureEnabled: true, canManage: false);
      expect(plain.manages, isFalse);
      const off = LedgerMe(isEmployee: false, featureEnabled: false, canManage: true);
      expect(off.manages, isFalse);
      expect(off.isManager, isFalse);
    });
  });

  group('لوحة «له / عليه»', () {
    testWidgets('المدير: الأرقام والراتب المستحقّ والقروض والحركات والكشوف — والإلغاء لما يُلغى وحده', (t) async {
      await phone(t);
      final voided = <int>[];
      final voidedSlips = <int>[];
      await t.pumpWidget(app(Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: EmployeeLedgerPanel(
            account: LedgerAccount.fromJson(ledgerAccountJson())!,
            onMove: () {},
            onPayslip: () {},
            onVoidMove: (m) => voided.add(m.id),
            onVoidPayslip: (p) => voidedSlips.add(p.id),
          ),
        ),
      )));
      await t.pumpAndSettle();
      expect(find.text('عليه (سلف وقروض)'), findsOneWidget);
      expect(t.widget<Text>(find.byKey(const ValueKey('emp-ledger-owes'))).data, '500,000 د.ع');
      expect(find.text('له في كشفه القادم'), findsOneWidget);
      expect(t.widget<Text>(find.byKey(const ValueKey('emp-ledger-due'))).data, '25,000 د.ع');
      expect(find.text('سلف وسحوبات 100,000 · قروض 400,000'), findsOneWidget);
      expect(find.text('الراتب: 500,000 شهريّاً — يوم 28'), findsOneWidget);
      expect(find.text('راتبٌ مستحقّ'), findsOneWidget);
      expect(find.byKey(const ValueKey('emp-ledger-move')), findsOneWidget);
      expect(find.byKey(const ValueKey('emp-ledger-slip')), findsOneWidget);
      expect(find.text('القروض'), findsOneWidget);
      expect(find.text('المتبقّي 400,000 د.ع'), findsOneWidget);
      expect(find.text('سلفة — من النقد الذي بيده'), findsOneWidget);
      expect(find.textContaining('سجّلها cashier'), findsOneWidget);
      expect(find.text('خصم (ملغاة)'), findsOneWidget);
      expect(find.textContaining('سُجّلت خطأً'), findsOneWidget);
      expect(find.text('كشف 2 — تشرين الأوّل 2026'), findsOneWidget);
      expect(find.text('كشف 1 (ملغى)'), findsOneWidget);
      // الإلغاء: حركتان فعّالتان + آخر كشفٍ مصروف — لا الملغاة ولا الكشف الملغى
      expect(find.text('إلغاء'), findsNWidgets(3));
      await t.tap(find.descendant(of: find.byKey(const ValueKey('emp-ledger-move-11')), matching: find.text('إلغاء')));
      await t.tap(find.descendant(of: find.byKey(const ValueKey('emp-ledger-slip-3')), matching: find.text('إلغاء')));
      expect(voided, [11]);
      expect(voidedSlips, [3]);
      expect(find.descendant(of: find.byKey(const ValueKey('emp-ledger-move-13')), matching: find.text('إلغاء')), findsNothing);
      expect(find.descendant(of: find.byKey(const ValueKey('emp-ledger-slip-2')), matching: find.text('إلغاء')), findsNothing);
    });

    testWidgets('الموظّف يرى حسابه قراءةً فقط: بصيغته، وبلا أزرار', (t) async {
      await phone(t);
      await t.pumpWidget(app(Scaffold(
        body: SingleChildScrollView(child: EmployeeLedgerPanel(account: LedgerAccount.fromJson(ledgerAccountJson())!, selfView: true)),
      )));
      await t.pumpAndSettle();
      expect(find.text('عليك (سلف وقروض)'), findsOneWidget);
      expect(find.text('لك في كشفك القادم'), findsOneWidget);
      expect(find.text('راتبك: 500,000 شهريّاً — يوم 28'), findsOneWidget);
      expect(find.byKey(const ValueKey('emp-ledger-move')), findsNothing);
      expect(find.byKey(const ValueKey('emp-ledger-slip')), findsNothing);
      expect(find.text('إلغاء'), findsNothing);
    });

    testWidgets('بعرض ٣٢٠: لا فيضان (أرقامٌ كبيرة وأسماء طويلة)', (t) async {
      await phone(t, width: 320);
      final json = ledgerAccountJson()
        ..['owes_total'] = 123456789
        ..['due_pending'] = -98765432;
      await t.pumpWidget(app(Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: EmployeeLedgerPanel(account: LedgerAccount.fromJson(json)!, onMove: () {}, onPayslip: () {}, onVoidMove: (_) {}, onVoidPayslip: (_) {}),
        ),
      )));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      expect(find.text('خصومات لكشفه القادم'), findsOneWidget);
    });
  });

  group('حركة جديدة', () {
    testWidgets('سلفة: المبلغ بالاختصار، من الصندوق، ومفتاح منع التكرار — وتُرجع نصّ النجاح', (t) async {
      await phone(t);
      Object? result;
      await opener(t, (c) => showEmployeeMoveSheet(c, employeeId: 7, name: 'أحمد'), (r) => result = r);
      expect(find.text('حركة موظف'), findsOneWidget);
      expect(find.text('اكتب المبلغ'), findsOneWidget, reason: 'الزرّ يقول ما ينقص');
      expect(find.byKey(const ValueKey('emp-move-source')), findsOneWidget);
      // الزرّ معطَّل بلا مبلغ
      await t.tap(find.text('اكتب المبلغ'));
      await settle(t, frames: 3);
      expect(server.bodiesOf('POST', '/api/v2/employee-ledger/7/movements'), isEmpty);
      await t.enterText(field('emp-move-amount'), '100');
      await t.pump();
      expect(find.text('تسجيل سلفة — 100,000 د.ع'), findsOneWidget, reason: 'ما سيُحفظ هو ما يقوله الزرّ');
      await t.tap(find.text('تسجيل سلفة — 100,000 د.ع'));
      await settle(t);
      final posts = server.bodiesOf('POST', '/api/v2/employee-ledger/7/movements');
      expect(posts, hasLength(1));
      expect(posts.single['kind'], 'advance');
      expect(posts.single['amount'], 100000);
      expect(posts.single['source'], 'box');
      expect(posts.single.containsKey('installment'), isFalse);
      expect(RegExp(r'^[A-Za-z0-9_-]{8,64}$').hasMatch(posts.single['client_ref'] as String), isTrue);
      expect(result, 'سُجّلت: سلفة 100,000 د.ع');
    });

    testWidgets('قرض: القسط إلزاميّ ولا يتجاوز المبلغ، ومن النقد الذي بيده', (t) async {
      await phone(t);
      Object? result;
      await opener(t, (c) => showEmployeeMoveSheet(c, employeeId: 7, name: 'أحمد'), (r) => result = r);
      await t.tap(find.byKey(const ValueKey('emp-move-kind-loan')));
      await t.pump();
      expect(find.text('يُسدَّد بقسطٍ يُستقطع مع كلّ راتب'), findsOneWidget);
      await t.enterText(field('emp-move-amount'), '600');
      await t.pump();
      expect(find.text('اكتب قسط القرض'), findsOneWidget);
      await t.enterText(field('emp-move-installment'), '700');
      await t.pump();
      expect(find.text('القسط أكبر من مبلغ القرض'), findsOneWidget);
      await t.enterText(field('emp-move-installment'), '100');
      await t.pump();
      await t.tap(find.text('من النقد الذي بيده'));
      await t.pump();
      await t.tap(find.text('تسجيل قرض — 600,000 د.ع'));
      await settle(t);
      final b = server.bodiesOf('POST', '/api/v2/employee-ledger/7/movements').single;
      expect(b['kind'], 'loan');
      expect(b['amount'], 600000);
      expect(b['installment'], 100000);
      expect(b['source'], 'hand');
      expect(result, 'سُجّلت: قرض 600,000 د.ع');
    });

    testWidgets('سحب ومكافأة: بلا «من أين يُدفع؟» ولا مصدرٍ في الطلب', (t) async {
      await phone(t);
      await opener(t, (c) => showEmployeeMoveSheet(c, employeeId: 7, name: 'أحمد', initialKind: LedgerKind.withdraw), (_) {});
      expect(find.byKey(const ValueKey('emp-move-source')), findsNothing);
      await t.tap(find.byKey(const ValueKey('emp-move-kind-bonus')));
      await t.pump();
      expect(find.byKey(const ValueKey('emp-move-source')), findsNothing);
      await t.enterText(field('emp-move-amount'), '25');
      await t.pump();
      await t.tap(find.text('تسجيل مكافأة — 25,000 د.ع'));
      await settle(t);
      final b = server.bodiesOf('POST', '/api/v2/employee-ledger/7/movements').single;
      expect(b['kind'], 'bonus');
      expect(b.containsKey('source'), isFalse);
    });

    testWidgets('تسديد: لا يتجاوز ما عليه', (t) async {
      await phone(t);
      await opener(t, (c) => showEmployeeMoveSheet(c, employeeId: 7, name: 'أحمد', owes: 100000, initialKind: LedgerKind.repayment), (_) {});
      expect(find.text('عليه الآن: 100,000 د.ع'), findsOneWidget);
      await t.enterText(field('emp-move-amount'), '150');
      await t.pump();
      expect(find.text('المبلغ أكبر ممّا عليه (100,000 د.ع)'), findsOneWidget);
      await t.enterText(field('emp-move-amount'), '100');
      await t.pump();
      expect(find.text('تسجيل تسديد — 100,000 د.ع'), findsOneWidget);
    });

    testWidgets('رفض الخادم يُعرض برسالته والورقة تبقى — وإعادة الضغط بالمفتاح نفسه (لا حركتان)', (t) async {
      await phone(t);
      Object? result = 'x';
      server.moveReplies.add((409, {'success': false, 'code': 'BUSY', 'message': 'عمليّةٌ أخرى جارية على هذا الموظف — أعد المحاولة'}));
      await opener(t, (c) => showEmployeeMoveSheet(c, employeeId: 7, name: 'أحمد'), (r) => result = r);
      await t.enterText(field('emp-move-amount'), '50');
      await t.pump();
      await t.tap(find.text('تسجيل سلفة — 50,000 د.ع'));
      await settle(t, frames: 40);
      expect(find.text('حركة موظف'), findsOneWidget, reason: 'لم تُغلق');
      expect(result, 'x');
      await t.tap(find.text('تسجيل سلفة — 50,000 د.ع'));
      await settle(t);
      final posts = server.bodiesOf('POST', '/api/v2/employee-ledger/7/movements');
      expect(posts, hasLength(2));
      expect(posts[0]['client_ref'], posts[1]['client_ref'], reason: 'النيّة الواحدة مفتاحٌ واحد');
      expect(result, 'سُجّلت: سلفة 50,000 د.ع');
    });
  });

  group('كشف الراتب', () {
    testWidgets('ما تراه هو ما يُصرف: الفترات والحدّ والأرقام تعود للخادم كما عُرضت', (t) async {
      await phone(t);
      Object? result;
      await opener(t, (c) => showEmployeePayslipSheet(c, employeeId: 7, name: 'أحمد'), (r) => result = r);
      expect(find.text('كشف الراتب'), findsOneWidget);
      expect(find.text('تشرين الثاني 2026'), findsOneWidget);
      expect(find.text('الراتب'), findsOneWidget);
      expect(find.text('مكافآت (1)'), findsOneWidget);
      expect(find.text('المستحقّ — ينزل في المصاريف'), findsOneWidget);
      expect(t.widget<Text>(find.byKey(const ValueKey('emp-payslip-gross'))).data, '525,000 د.ع');
      expect(find.text('استقطاع السلف والسحوبات'), findsOneWidget);
      expect(find.text('قسط قرض (المتبقّي 400,000)'), findsOneWidget);
      expect(t.widget<Text>(find.byKey(const ValueKey('emp-payslip-net'))).data, '375,000 د.ع');
      await t.tap(find.text('صرف — يستلم 375,000 د.ع'));
      await settle(t);
      final b = server.bodiesOf('POST', '/api/v2/employee-ledger/7/payslip').single;
      expect(b['periods'], ['2026-11']);
      expect(b['cut'], {'ledger_id': 42, 'comm_to': null});
      expect(b['expected'], {'gross': 525000, 'net': 375000});
      expect(b['source'], 'box');
      expect(RegExp(r'^[A-Za-z0-9_-]{8,64}$').hasMatch(b['client_ref'] as String), isTrue);
      expect(result, 'صُرف كشف أحمد — 375,000 د.ع');
    });

    testWidgets('تبديل فترة ⇒ معاينةٌ جديدة من الخادم بالاختيار نفسه (لا حساب هنا)', (t) async {
      await phone(t);
      await opener(t, (c) => showEmployeePayslipSheet(c, employeeId: 7, name: 'أحمد'), (_) {});
      expect(server.previewQueries, [null], reason: 'الأولى: ما يختاره الخادم');
      await t.tap(find.byKey(const ValueKey('emp-payslip-period-2026-11')));
      await settle(t);
      expect(server.previewQueries, [null, ''], reason: 'أُلغي اختيار الوحيدة ⇒ قائمةٌ فارغة صريحة');
    });

    testWidgets('STALE ⇒ معاينةٌ جديدة بمفتاحٍ جديد، والورقة تبقى', (t) async {
      await phone(t);
      Object? result = 'x';
      server.payReplies.add((409, {'success': false, 'code': 'STALE', 'message': 'تغيّرت الأرقام منذ فتحت الكشف — راجعها واصرف من جديد'}));
      await opener(t, (c) => showEmployeePayslipSheet(c, employeeId: 7, name: 'أحمد'), (r) => result = r);
      await t.tap(find.text('صرف — يستلم 375,000 د.ع'));
      await settle(t, frames: 40);
      expect(server.previewQueries, [null, '2026-11'], reason: 'الاختيار نفسه يُعاد صريحاً');
      expect(find.text('كشف الراتب'), findsOneWidget);
      expect(result, 'x');
      await t.tap(find.text('صرف — يستلم 375,000 د.ع'));
      await settle(t);
      final posts = server.bodiesOf('POST', '/api/v2/employee-ledger/7/payslip');
      expect(posts, hasLength(2));
      expect(posts[0]['client_ref'], isNot(posts[1]['client_ref']), reason: 'أرقامٌ جديدة ⇒ نيّةٌ جديدة');
      expect(result, 'صُرف كشف أحمد — 375,000 د.ع');
    });

    testWidgets('لا شيء يُصرف: سبب الخادم يُعرض والزرّ معطَّل', (t) async {
      await phone(t);
      server.preview = ledgerPreviewJson()
        ..['can_pay'] = false
        ..['expected'] = null
        ..['problem'] = {'code': 'NOTHING_TO_PAY', 'message': 'لا شيء يُصرف لهذا الموظف الآن'};
      await opener(t, (c) => showEmployeePayslipSheet(c, employeeId: 7, name: 'أحمد'), (_) {});
      expect(find.byKey(const ValueKey('emp-payslip-problem')), findsOneWidget);
      await t.tap(find.text('لا شيء يُصرف الآن'));
      await settle(t, frames: 3);
      expect(server.bodiesOf('POST', '/api/v2/employee-ledger/7/payslip'), isEmpty);
    });

    testWidgets('«تخطٍّ» للمدير وحده، لراتبٍ استحقّ ولم يُختر', (t) async {
      await phone(t);
      server.preview = ledgerPreviewJson()
        ..['periods'] = [
          {'key': '2026-10', 'label': 'تشرين الأوّل 2026', 'due_date': '2026-10-28', 'due': true, 'amount': 500000, 'selected': false},
          {'key': '2026-11', 'label': 'تشرين الثاني 2026', 'due_date': '2026-11-28', 'due': true, 'amount': 500000, 'selected': true},
        ];
      await opener(t, (c) => showEmployeePayslipSheet(c, employeeId: 7, name: 'أحمد', canSkip: true), (_) {});
      expect(find.byKey(const ValueKey('emp-payslip-skip-2026-10')), findsOneWidget);
      expect(find.byKey(const ValueKey('emp-payslip-skip-2026-11')), findsNothing, reason: 'المختار يُصرف لا يُتخطّى');
      await t.tap(find.byKey(const ValueKey('emp-payslip-skip-2026-10')));
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(TextButton, 'تخطٍّ').last);
      await settle(t);
      expect(server.paths, contains('/api/v2/employee-ledger/7/periods/2026-10/skip'));
    });

    testWidgets('صاحب الصلاحيّة (لا المدير): لا «تخطٍّ»', (t) async {
      await phone(t);
      server.preview = ledgerPreviewJson()
        ..['periods'] = [
          {'key': '2026-10', 'label': 'تشرين الأوّل 2026', 'due_date': '2026-10-28', 'due': true, 'amount': 500000, 'selected': false},
        ];
      await opener(t, (c) => showEmployeePayslipSheet(c, employeeId: 7, name: 'أحمد'), (_) {});
      expect(find.byKey(const ValueKey('emp-payslip-skip-2026-10')), findsNothing);
    });

    testWidgets('تعذّرت المعاينة ⇒ السبب و«إعادة المحاولة» بلا زرّ صرف', (t) async {
      await phone(t);
      server.previewFails = true;
      await opener(t, (c) => showEmployeePayslipSheet(c, employeeId: 7, name: 'أحمد'), (_) {});
      expect(find.text('إعادة المحاولة'), findsOneWidget);
      expect(find.textContaining('صرف —'), findsNothing);
      server.previewFails = false;
      await t.tap(find.text('إعادة المحاولة'));
      await settle(t);
      expect(find.text('صرف — يستلم 375,000 د.ع'), findsOneWidget);
    });
  });

  group('شاشة حساب الموظف', () {
    testWidgets('الميزة مفتوحة ⇒ «له / عليه» فوق حدوده وتسويته', (t) async {
      await phone(t);
      await t.pumpWidget(app(const EmployeeAccountScreen(employeeId: 7, title: 'أحمد', ledger: (canWrite: true, canVoid: true))));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('emp-ledger-panel')), findsOneWidget);
      expect(find.text('حدوده وتسويته معك'), findsOneWidget);
      expect(find.text('الفترة الحاليّة'), findsOneWidget);
      expect(find.byKey(const ValueKey('emp-ledger-move')), findsOneWidget);
    });

    testWidgets('بلا الميزة ⇒ الشاشة كما كانت، ولا نداء للدفتر', (t) async {
      await phone(t);
      await t.pumpWidget(app(const EmployeeAccountScreen(employeeId: 7, title: 'أحمد')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('emp-ledger-panel')), findsNothing);
      expect(find.text('حدوده وتسويته معك'), findsNothing);
      expect(find.text('الفترة الحاليّة'), findsOneWidget);
      expect(server.paths.where((p) => p.startsWith('/api/v2/employee-ledger')), isEmpty);
    });

    testWidgets('صاحب الصلاحيّة: اللوحة وحدها — لا حدود ولا تسوية ولا إلغاء، ولا نداء للحدود', (t) async {
      await phone(t);
      await t.pumpWidget(app(const EmployeeAccountScreen(employeeId: 7, title: 'أحمد', limitsOn: false, ledger: (canWrite: true, canVoid: false))));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('emp-ledger-panel')), findsOneWidget);
      expect(find.byKey(const ValueKey('emp-ledger-move')), findsOneWidget);
      expect(find.text('إلغاء'), findsNothing);
      expect(find.text('حدوده وتسويته معك'), findsNothing);
      expect(find.byKey(const ValueKey('emp-settle-open')), findsNothing);
      expect(server.paths.where((p) => p.startsWith('/api/v2/employee-limits')), isEmpty);
    });

    testWidgets('نفسه (صاحب الصلاحيّة على حسابه): قراءةٌ بلا أزرار', (t) async {
      await phone(t);
      await t.pumpWidget(app(const EmployeeAccountScreen(employeeId: 7, title: 'أحمد', limitsOn: false, ledger: (canWrite: false, canVoid: false))));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('emp-ledger-panel')), findsOneWidget);
      expect(find.byKey(const ValueKey('emp-ledger-move')), findsNothing);
      expect(find.byKey(const ValueKey('emp-ledger-slip')), findsNothing);
    });

    testWidgets('إلغاء حركة: بسببٍ مكتوب ثمّ يُحدَّث الحساب', (t) async {
      await phone(t);
      await t.pumpWidget(app(const EmployeeAccountScreen(employeeId: 7, title: 'أحمد', limitsOn: false, ledger: (canWrite: true, canVoid: true))));
      await t.pumpAndSettle();
      final before = server.paths.where((p) => p == '/api/v2/employee-ledger/7').length;
      await t.tap(find.descendant(of: find.byKey(const ValueKey('emp-ledger-move-11')), matching: find.text('إلغاء')));
      await t.pumpAndSettle();
      expect(find.text('إلغاء سلفة'), findsOneWidget);
      // بلا سبب ⇒ لا نداء
      await t.tap(find.byKey(const ValueKey('emp-ledger-void-confirm')));
      await settle(t, frames: 40);
      expect(server.bodiesOf('POST', '/api/v2/employee-ledger/7/movements/11/void'), isEmpty);
      await t.tap(find.descendant(of: find.byKey(const ValueKey('emp-ledger-move-11')), matching: find.text('إلغاء')));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const ValueKey('emp-ledger-void-reason')), 'سُجّلت مرّتين');
      await t.tap(find.byKey(const ValueKey('emp-ledger-void-confirm')));
      await settle(t, frames: 40);
      expect(server.bodiesOf('POST', '/api/v2/employee-ledger/7/movements/11/void').single['reason'], 'سُجّلت مرّتين');
      expect(server.paths.where((p) => p == '/api/v2/employee-ledger/7').length, before + 1, reason: 'يُعاد التحميل بعد الإلغاء');
    });

    testWidgets('إلغاء آخر كشف: بسببٍ مكتوب', (t) async {
      await phone(t);
      await t.pumpWidget(app(const EmployeeAccountScreen(employeeId: 7, title: 'أحمد', limitsOn: false, ledger: (canWrite: true, canVoid: true))));
      await t.pumpAndSettle();
      final btn = find.descendant(of: find.byKey(const ValueKey('emp-ledger-slip-3')), matching: find.text('إلغاء'));
      await t.ensureVisible(btn);
      await t.pumpAndSettle();
      await t.tap(btn);
      await t.pumpAndSettle();
      expect(find.text('إلغاء كشف الراتب 2'), findsOneWidget);
      await t.enterText(find.byKey(const ValueKey('emp-ledger-void-reason')), 'صُرف خطأً');
      await t.tap(find.byKey(const ValueKey('emp-ledger-void-confirm')));
      await settle(t, frames: 40);
      expect(server.bodiesOf('POST', '/api/v2/employee-ledger/7/payslips/3/void').single['reason'], 'صُرف خطأً');
    });

    testWidgets('تعذّر الدفتر والحدود وصلت ⇒ السبب مكانه، والحدود كما هي', (t) async {
      await phone(t);
      server.accountFails = true;
      await t.pumpWidget(app(const EmployeeAccountScreen(employeeId: 7, title: 'أحمد', ledger: (canWrite: true, canVoid: true))));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('emp-ledger-unavailable')), findsOneWidget);
      expect(find.text('الفترة الحاليّة'), findsOneWidget);
    });
  });

  group('التسوية مع الموظف: ما أخذه من النقد الذي بيده', () {
    test('النماذج: hand_taken/to_hand_over — وغيابهما (خادمٌ قبله) null لا صفر', () {
      final p = SettlementPreview.fromJson({
        'cut': {'head_id': 3},
        'cash_in': 350000,
        'hand_taken': 50000,
        'to_hand_over': 300000,
      })!;
      expect(p.handTaken, 50000);
      expect(p.toHandOver, 300000);
      final old = SettlementPreview.fromJson({'cut': {'head_id': 3}, 'cash_in': 350000})!;
      expect(old.handTaken, isNull);
      expect(old.toHandOver, isNull);
      final s = EmployeeLimitStatus.fromJson({'employee': {'id': 7}, 'hand_taken': 50000, 'to_hand_over': 300000})!;
      expect(s.handTaken, 50000);
      expect(s.toHandOver, 300000);
      expect(EmployeeLimitStatus.fromJson({'employee': {'id': 7}})!.handTaken, 0);
    });

    testWidgets('المعاينة تعرض ما يسلّمه فعلاً، والتأكيد يعيد hand_taken للخادم', (t) async {
      await phone(t);
      server.settlePreviewExtra = {'hand_taken': 50000, 'to_hand_over': 300000};
      await opener(t, (c) => showEmployeeSettleSheet(c, employeeId: 7, name: 'أحمد'), (_) {});
      await t.pumpAndSettle();
      expect(t.widget<Text>(find.byKey(const ValueKey('emp-settle-cash'))).data, '300,000 د.ع');
      expect(find.text('النقد الذي استلمه'), findsOneWidget);
      expect(t.widget<Text>(find.byKey(const ValueKey('emp-settle-hand-taken'))).data, '-50,000 د.ع');
      await t.tap(find.text('تأكيد التسوية — تصفير النقد'));
      await settle(t, frames: 40);
      final b = server.bodiesOf('POST', '/api/v2/employee-limits/7/settlement').single;
      expect((b['expected'] as Map)['hand_taken'], 50000);
      expect((b['expected'] as Map)['cash_in'], 350000);
    });

    testWidgets('بلا الحقل ⇒ الورقة والطلب كما كانا حرفاً', (t) async {
      await phone(t);
      await opener(t, (c) => showEmployeeSettleSheet(c, employeeId: 7, name: 'أحمد'), (_) {});
      await t.pumpAndSettle();
      expect(t.widget<Text>(find.byKey(const ValueKey('emp-settle-cash'))).data, '350,000 د.ع');
      expect(find.byKey(const ValueKey('emp-settle-hand-taken')), findsNothing);
      await t.tap(find.text('تأكيد التسوية — تصفير النقد'));
      await settle(t, frames: 40);
      final b = server.bodiesOf('POST', '/api/v2/employee-limits/7/settlement').single;
      expect(b['expected'], {'cash_in': 350000, 'debt_out': 120000, 'ops_count': 4, 'profit': 20000});
    });
  });

  group('المحرّر: راتب الموظف للمدير وحده', () {
    final catalog = PermissionsCatalog.fromJson({
      'permissions': {
        'subscribers.view': {'label': 'عرض المشتركين', 'category': 'subscribers'},
      },
      'categories': {
        'subscribers': {'label': 'المشتركون'},
      },
      'defaults': {'subscribers.view': true},
      'presets': <String, Object>{},
    });
    final emp = Employee.fromJson({'id': 7, 'username': 'emp1', 'full_name': 'أحمد', 'is_active': true, 'permissions': {}})!;

    Future<void> openEditor(WidgetTester t) => opener(t, (c) => showEmployeeEditorSheet(c, catalog: catalog, employee: emp), (_) {});

    testWidgets('الميزة مفتوحة ⇒ «راتب الموظف» بقيمه المحفوظة، والحفظ يرسل ما تغيّر', (t) async {
      await phone(t);
      PermissionsService.debugSet(isEmployee: false);
      await openEditor(t);
      expect(find.byKey(const ValueKey('emp-salary-section')), findsOneWidget);
      expect(find.text('الراتب الشهريّ'), findsOneWidget);
      expect(find.text('طريقة الأجر'), findsOneWidget);
      expect(t.widget<TextField>(field('emp-salary-amount')).controller!.text, '500,000');
      await t.enterText(field('emp-salary-amount'), '600');
      await t.pump();
      await t.ensureVisible(find.text('عمولة'));
      await settle(t, frames: 5);
      await t.tap(find.text('الاثنان'));
      await t.pump();
      await t.tap(find.text('حفظ'));
      await settle(t, frames: 40);
      final put = server.bodiesOf('PUT', '/api/v2/employee-ledger/7/salary');
      expect(put, hasLength(1));
      expect(put.single, {'amount': 600000, 'cycle': 'monthly', 'pay_day': 28, 'comp_mode': 'both'});
    });

    testWidgets('لم يتغيّر الراتب ⇒ لا نداء', (t) async {
      await phone(t);
      PermissionsService.debugSet(isEmployee: false);
      await openEditor(t);
      expect(find.byKey(const ValueKey('emp-salary-section')), findsOneWidget);
      await t.tap(find.text('حفظ'));
      await settle(t, frames: 40);
      expect(server.bodiesOf('PUT', '/api/v2/employee-ledger/7/salary'), isEmpty);
    });

    testWidgets('أسبوعيّ ⇒ يومٌ من أيّام الأسبوع', (t) async {
      await phone(t);
      PermissionsService.debugSet(isEmployee: false);
      await openEditor(t);
      await t.ensureVisible(find.text('أسبوعيّ'));
      await settle(t, frames: 5);
      await t.tap(find.text('أسبوعيّ'));
      await t.pump();
      expect(find.text('الراتب الأسبوعيّ'), findsOneWidget);
      expect(find.text('الخميس'), findsOneWidget, reason: 'يوم 28 ليس يوم أسبوع ⇒ الخميس');
      await t.tap(find.text('حفظ'));
      await settle(t, frames: 40);
      expect(server.bodiesOf('PUT', '/api/v2/employee-ledger/7/salary').single, {'amount': 500000, 'cycle': 'weekly', 'pay_day': 4, 'comp_mode': 'salary'});
    });

    testWidgets('الميزة مطفأة ⇒ لا حقول ولا قراءة حساب', (t) async {
      await phone(t);
      PermissionsService.debugSet(isEmployee: false);
      server.ledgerFeature = false;
      await openEditor(t);
      expect(find.byKey(const ValueKey('emp-salary-section')), findsNothing);
      expect(server.paths.contains('/api/v2/employee-ledger/7'), isFalse);
    });

    testWidgets('الموظّف (ولو بصلاحيّة الرواتب) ⇒ لا حقول ولا نداء', (t) async {
      await phone(t);
      PermissionsService.debugSet(isEmployee: true, permissions: {'employees.manage': true, 'employees.payroll': true});
      await openEditor(t);
      expect(find.byKey(const ValueKey('emp-salary-section')), findsNothing);
      expect(server.paths.where((p) => p.startsWith('/api/v2/employee-ledger')), isEmpty);
    });

    test('رفض الخادم يعود برسالته، ولم تُقرأ القيم ⇒ لا حفظ', () async {
      final form = EmployeeSalaryForm();
      addTearDown(form.dispose);
      expect(await form.save(7), isNull, reason: 'لم تُعرض ⇒ لا نداء');
      expect(server.bodiesOf('PUT', '/api/v2/employee-ledger/7/salary'), isEmpty);
      expect(await form.load(7), isTrue);
      form.amountCtrl.text = '700,000';
      server.salaryReply = (409, {'success': false, 'code': 'DUE_PENDING', 'message': 'له رواتب مستحقّة لم تُصرف — اصرفها أو تخطَّها قبل تغيير يوم الصرف'});
      expect(await form.save(7), contains('رواتب مستحقّة'));
    });
  });

  group('الإضافة السريعة: «على أيّ موظف؟»', () {
    testWidgets('المنتقي يجلب القائمة، يستثني المستعمل نفسه، ثمّ تُسجَّل الحركة', (t) async {
      await phone(t);
      EmployeeLedgerState.debugSet(LedgerMe(
        isEmployee: true,
        featureEnabled: true,
        canManage: true,
        account: LedgerAccount.fromJson(ledgerAccountJson()
          ..['employee'] = {'id': 9, 'username': 'cashier', 'name': 'صراف'}),
      ));
      Object? result;
      await opener(t, (c) => quickEmployeeMove(c), (r) => result = r);
      expect(find.text('اختر الموظف'), findsOneWidget);
      expect(find.byKey(const ValueKey('emp-pick-7')), findsOneWidget);
      expect(find.byKey(const ValueKey('emp-pick-8')), findsOneWidget);
      expect(find.byKey(const ValueKey('emp-pick-9')), findsNothing, reason: 'لا يسجّل على نفسه');
      expect(find.text('عليه 500,000'), findsOneWidget);
      expect(find.text('راتبٌ مستحقّ'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('emp-pick-7')));
      await settle(t);
      expect(find.text('حركة موظف'), findsOneWidget);
      await t.enterText(field('emp-move-amount'), '30');
      await t.pump();
      await t.tap(find.text('تسجيل سلفة — 30,000 د.ع'));
      await settle(t, frames: 40);
      expect(server.bodiesOf('POST', '/api/v2/employee-ledger/7/movements').single['amount'], 30000);
      expect(result, isTrue);
    });

    testWidgets('تعذّرت القائمة ⇒ «إعادة المحاولة» لا قائمةٌ فارغة', (t) async {
      await phone(t);
      server.listFails = true;
      await opener(t, (c) => showEmployeePickSheet(c), (_) {});
      expect(find.text('تعذّر تحميل الموظفين الآن'), findsOneWidget);
      expect(find.text('لا موظفين في هذه الصفحة بعد'), findsNothing);
      server.listFails = false;
      await t.tap(find.text('إعادة المحاولة'));
      await settle(t);
      expect(find.byKey(const ValueKey('emp-pick-7')), findsOneWidget);
    });

    test('الحال: بلا جلسة لا نداء؛ و«يدير» من ردّ الخادم وحده', () async {
      await EmployeeLedgerState.ensureFresh(force: true);
      expect(EmployeeLedgerState.manages, isFalse);
      expect(server.paths, isEmpty, reason: 'بلا توكن لا يُسأل الخادم');
      EmployeeLedgerState.note(const LedgerMe(isEmployee: false, featureEnabled: true, canManage: true));
      expect(EmployeeLedgerState.manages, isTrue);
      EmployeeLedgerState.reset();
      expect(EmployeeLedgerState.manages, isFalse, reason: 'تبديل الجلسة يصفّرها');
    });
  });

  group('قسم الموظفين', () {
    testWidgets('المدير والميزة مفتوحة ⇒ زرّ الحساب لكلّ موظف، نقطةٌ لمن له راتبٌ مستحقّ، و«حركة موظف» بالرأس', (t) async {
      // خطّ الاختبار عريض (كلّ حرفٍ مربّع): عرضٌ يسع سطر البطاقة بأزرارها الأربعة
      await phone(t, width: 640);
      PermissionsService.debugSet(isEmployee: false);
      await t.pumpWidget(app(const EmployeesScreen()));
      await settle(t);
      expect(find.byKey(const ValueKey('employee-account-7')), findsOneWidget);
      expect(find.byKey(const ValueKey('employee-account-8')), findsOneWidget);
      expect(find.byKey(const ValueKey('employee-ledger-dot-7')), findsOneWidget, reason: 'راتبٌ مستحقّ');
      expect(find.byKey(const ValueKey('employee-ledger-dot-8')), findsNothing, reason: 'لا شيء له ولا عليه');
      expect(t.takeException(), isNull);
      // «حركة موظف» من الرأس ⇒ «على أيّ موظف؟»
      await t.tap(find.byKey(const ValueKey('employees-ledger-move')));
      await settle(t);
      expect(find.text('اختر الموظف'), findsOneWidget);
      expect(find.byKey(const ValueKey('emp-pick-7')), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('emp-pick-8')));
      await settle(t);
      expect(find.text('حركة موظف'), findsOneWidget);
      expect(find.text('سارة'), findsWidgets);
    });

    testWidgets('زرّ الحساب يفتح «له / عليه» فوق حدوده', (t) async {
      // خطّ الاختبار عريض (كلّ حرفٍ مربّع): عرضٌ يسع سطر البطاقة بأزرارها الأربعة
      await phone(t, width: 640);
      PermissionsService.debugSet(isEmployee: false);
      await t.pumpWidget(app(const EmployeesScreen()));
      await settle(t);
      await t.tap(find.byKey(const ValueKey('employee-account-7')));
      await settle(t);
      expect(find.byKey(const ValueKey('emp-ledger-panel')), findsOneWidget);
      expect(find.text('حدوده وتسويته معك'), findsOneWidget);
      expect(find.byKey(const ValueKey('emp-ledger-move')), findsOneWidget);
    });

    testWidgets('الميزة مطفأة لهذه الصفحة ⇒ القسم كما كان (زرّ الحساب للحدود وحدها، بلا نقاط ولا بند الرأس)', (t) async {
      // خطّ الاختبار عريض (كلّ حرفٍ مربّع): عرضٌ يسع سطر البطاقة بأزرارها الأربعة
      await phone(t, width: 640);
      PermissionsService.debugSet(isEmployee: false);
      server.ledgerFeature = false;
      await t.pumpWidget(app(const EmployeesScreen()));
      await settle(t);
      expect(find.byKey(const ValueKey('employee-account-7')), findsOneWidget, reason: 'حدود الموظّف مفتوحة');
      expect(find.byKey(const ValueKey('employee-ledger-dot-7')), findsNothing);
      expect(find.byKey(const ValueKey('employees-ledger-move')), findsNothing);
      expect(server.paths.contains('/api/v2/employee-ledger'), isFalse, reason: 'لا قائمة تُطلب');
      await t.tap(find.byKey(const ValueKey('employee-account-7')));
      await settle(t);
      expect(find.byKey(const ValueKey('emp-ledger-panel')), findsNothing);
      expect(find.text('الفترة الحاليّة'), findsOneWidget);
    });

    testWidgets('موظّفٌ بصلاحيّة الرواتب: يفتح حساب زميله للتسجيل بلا حدودٍ ولا إلغاء، وحسابه هو قراءةً', (t) async {
      // خطّ الاختبار عريض (كلّ حرفٍ مربّع): عرضٌ يسع سطر البطاقة بأزرارها الأربعة
      await phone(t, width: 640);
      PermissionsService.debugSet(isEmployee: true, permissions: {'employees.view': true, 'employees.payroll': true});
      server.meAsEmployee = 9;
      await t.pumpWidget(app(const EmployeesScreen()));
      await settle(t);
      expect(find.byKey(const ValueKey('employee-account-7')), findsOneWidget);
      expect(server.paths.where((p) => p.startsWith('/api/v2/employee-limits/')).where((p) => !p.endsWith('/me')), isEmpty);
      await t.tap(find.byKey(const ValueKey('employee-account-7')));
      await settle(t);
      expect(find.byKey(const ValueKey('emp-ledger-move')), findsOneWidget);
      expect(find.text('إلغاء'), findsNothing, reason: 'الإلغاء للمدير وحده');
      expect(find.text('حدوده وتسويته معك'), findsNothing);
      expect(server.paths.contains('/api/v2/employee-limits/7'), isFalse);
      t.state<NavigatorState>(find.byType(Navigator)).pop();
      await settle(t);
      // حسابه هو: بلا أزرار (الخادم يرفض تسجيله على نفسه)
      await t.tap(find.byKey(const ValueKey('employee-account-9')));
      await settle(t);
      expect(find.byKey(const ValueKey('emp-ledger-panel')), findsOneWidget);
      expect(find.byKey(const ValueKey('emp-ledger-move')), findsNothing);
    });

    testWidgets('موظّفٌ بلا الصلاحيّة ⇒ لا زرّ حساب ولا بند', (t) async {
      // خطّ الاختبار عريض (كلّ حرفٍ مربّع): عرضٌ يسع سطر البطاقة بأزرارها الأربعة
      await phone(t, width: 640);
      PermissionsService.debugSet(isEmployee: true, permissions: {'employees.view': true});
      server.meAsEmployee = 9;
      server.meCanManage = false;
      await t.pumpWidget(app(const EmployeesScreen()));
      await settle(t);
      expect(find.byKey(const ValueKey('employee-account-7')), findsNothing);
      expect(find.byKey(const ValueKey('employees-ledger-move')), findsNothing);
      expect(server.paths.contains('/api/v2/employee-ledger'), isFalse);
    });
  });

  group('بطاقة الموظّف «سلفي وراتبي»', () {
    testWidgets('عليه شيء ⇒ سطرٌ واحد بما عليه، والنقر يفتح حسابه قراءةً', (t) async {
      await phone(t);
      final a = LedgerAccount.fromJson(ledgerAccountJson())!;
      await t.pumpWidget(app(Scaffold(body: EmployeeLedgerCard(loader: () async => a))));
      await t.pumpAndSettle();
      expect(find.text('سلفي وراتبي'), findsOneWidget);
      expect(t.widget<Text>(find.byKey(const ValueKey('emp-ledger-card-headline'))).data, 'عليك 500,000');
    });

    testWidgets('لا شيء له (لا راتب ولا حركة) ⇒ لا بطاقة ولا مساحة', (t) async {
      await phone(t);
      final empty = LedgerAccount.fromJson({
        'employee': {'id': 7, 'username': 'emp1', 'name': 'أحمد'},
        'owed': 0,
        'loans_total': 0,
        'owes_total': 0,
        'due_pending': 0,
        'salary': {'amount': null, 'cycle': 'monthly', 'pay_day': 1, 'comp_mode': 'salary', 'configured': false},
        'loans': [],
        'movements': [],
        'payslips': [],
      })!;
      await t.pumpWidget(app(Scaffold(body: EmployeeLedgerCard(loader: () async => empty))));
      await t.pumpAndSettle();
      expect(find.text('سلفي وراتبي'), findsNothing);
    });

    testWidgets('راتبٌ مضبوط بلا حركات ⇒ البطاقة براتبه', (t) async {
      await phone(t);
      final a = LedgerAccount.fromJson({
        'employee': {'id': 7, 'username': 'emp1'},
        'salary': {'amount': 500000, 'cycle': 'monthly', 'pay_day': 28, 'comp_mode': 'salary', 'configured': true},
      })!;
      await t.pumpWidget(app(Scaffold(body: EmployeeLedgerCard(loader: () async => a))));
      await t.pumpAndSettle();
      expect(t.widget<Text>(find.byKey(const ValueKey('emp-ledger-card-headline'))).data, '500,000 شهريّاً — يوم 28');
    });

    testWidgets('شاشة حسابه: قراءةٌ فقط', (t) async {
      await phone(t);
      final a = LedgerAccount.fromJson(ledgerAccountJson())!;
      await t.pumpWidget(app(EmployeeMyLedgerScreen(initial: a, loader: () async => a)));
      await t.pumpAndSettle();
      expect(find.text('عليك (سلف وقروض)'), findsOneWidget);
      expect(find.byKey(const ValueKey('emp-ledger-move')), findsNothing);
      expect(find.text('إلغاء'), findsNothing);
    });
  });

  group('أثرها في الصندوق', () {
    test('النماذج تقرأ employee_moves — وغيابه (خادمٌ قبله) صفر', () {
      final s = SettlementRecord.fromJson({
        'id': 5,
        'kind': 'settlement',
        'number': 2,
        'status': 'active',
        'expected_amount': 250000,
        'employee_moves': {'sum': -150000, 'count': 2},
        'collectors': [
          {'employee_id': null, 'net_amount': 250000, 'employee_moves': {'sum': -150000, 'count': 2}},
        ],
      })!;
      expect(s.employeeMoves.sum, -150000);
      expect(s.employeeMoves.count, 2);
      expect(s.collectors.single.employeeMoves.count, 2);
      expect(s.moveCount, 2);
      final old = SettlementRecord.fromJson({'id': 5, 'kind': 'settlement', 'status': 'active'})!;
      expect(old.employeeMoves.count, 0);
      final cur = CurrentAccount.fromJson({
        'started': true,
        'totals': {'expected_amount': 100000, 'employee_moves': {'sum': 50000, 'count': 1}},
      })!;
      expect(cur.employeeMoves.sum, 50000);
    });

    testWidgets('سطر الصندوق: خرج (سلف وقروض) / عاد (تسديد واستقطاع)', (t) async {
      late ({String label, String value, bool out}) out, back, zero;
      await t.pumpWidget(app(Builder(builder: (c) {
        out = employeeBoxLine(const MoneyCount(-150000, 2));
        back = employeeBoxLine(const MoneyCount(50000, 1));
        zero = employeeBoxLine(const MoneyCount(0, 2));
        return const SizedBox();
      })));
      await t.pumpAndSettle();
      expect(out.label, 'سلف وقروض الموظفين');
      expect(out.value, '−150,000');
      expect(out.out, isTrue);
      expect(back.label, 'رجع من سلف الموظفين');
      expect(back.value, '+50,000');
      expect(back.out, isFalse);
      expect(zero.label, 'حركات الموظفين (صافيها صفر)');
    });

    testWidgets('حركة الصندوق: نوعها واسم الموظف (لا «تسديد دين —»)', (t) async {
      await phone(t);
      final m = BoxMovement.fromJson({
        'source': 'employee',
        'id': 11,
        'kind': 'emp_advance',
        'direction': 'out',
        'amount': 100000,
        'created_at': '2026-11-13T10:00:00.000Z',
        'subscriber': null,
        'description': 'سلفة: أحمد — عيد',
        'employee_id': null,
      })!;
      final back = BoxMovement.fromJson({
        'source': 'employee',
        'id': 3,
        'kind': 'emp_payslip_recover',
        'direction': 'in',
        'amount': 150000,
        'created_at': '2026-11-13T11:00:00.000Z',
        'description': 'استقطاع سلف وأقساط من كشف راتب رقم 2: أحمد',
      })!;
      await t.pumpWidget(app(Scaffold(body: Column(children: [MovementTile(m: m), MovementTile(m: back)]))));
      await t.pumpAndSettle();
      expect(m.isIn, isFalse);
      expect(find.textContaining('أحمد — عيد'), findsOneWidget);
      expect(find.textContaining('سلفة موظف'), findsOneWidget);
      expect(find.textContaining('استقطاع من راتب'), findsOneWidget);
      expect(find.textContaining('تسديد دين'), findsNothing);
      expect(t.takeException(), isNull);
    });
  });

  group('أثرها في التقرير الماليّ والصرفيات', () {
    test('أرقام الموظفين للعرض وحده: لا تمسّ صافي النقد', () {
      Map<String, dynamic> base() => {'activate_cash_sum': 1000000, 'expenses_sum': 525000, 'expenses_count': 1};
      final plain = FinanceKPIs.fromJson(base());
      expect(plain.hasEmployeeMoves, isFalse);
      expect(plain.showEmployeeReceivable, isFalse);
      final k = FinanceKPIs.fromJson(base()
        ..addAll({
          'emp_salaries_sum': 525000,
          'emp_given_sum': 200000,
          'emp_recovered_sum': 150000,
          'emp_repaid_sum': 20000,
          'emp_receivable_outstanding': 30000,
        }));
      expect(k.hasEmployeeMoves, isTrue);
      expect(k.empSalariesSum, 525000);
      expect(k.empGivenSum, 200000);
      expect(k.empBackSum, 170000);
      expect(k.empOutstanding, 30000);
      expect(k.showEmployeeReceivable, isTrue);
      expect(k.netCash, plain.netCash, reason: 'السلف ليست مصروفاً — الصافي كما كان');
      expect(k.totalCashRevenue, plain.totalCashRevenue);
    });

    test('تسمية سطر «حركة موظف» من أوّل وصفه', () {
      expect(employeeMoveLabel('سلفة: أحمد — عيد'), 'سلفة موظف');
      expect(employeeMoveLabel('قرض: أحمد'), 'قرض موظف');
      expect(employeeMoveLabel('تسديد: أحمد'), 'تسديد موظف');
      expect(employeeMoveLabel('شيءٌ آخر'), 'حركة موظف');
      expect(arabicActionLabel('EMPLOYEE_MOVE', 'مكافأة: أحمد'), 'مكافأة موظف');
    });

    testWidgets('سطر التقرير: السلفة خارجة بالأحمر، التسديد داخل، والمكافأة بلا إشارة نقد', (t) async {
      await phone(t);
      Widget tile(String desc) => ReportLogTile(actionType: 'EMPLOYEE_MOVE', description: desc, amount: 100000, targetName: 'أحمد', createdAt: '2026-11-13T10:00:00.000Z');
      await t.pumpWidget(app(Scaffold(body: Column(children: [tile('سلفة: أحمد'), tile('تسديد: أحمد'), tile('مكافأة: أحمد')]))));
      await t.pumpAndSettle();
      expect(find.text('سلفة موظف'), findsOneWidget);
      expect(find.text('تسديد موظف'), findsOneWidget);
      expect(find.text('مكافأة موظف'), findsOneWidget);
      expect(find.text('-100,000 د.ع'), findsOneWidget, reason: 'السلفة وحدها خارجة');
      expect(find.text('100,000 د.ع'), findsNWidgets(2));
    });

    test('صرفيّة كشف الراتب تُعرَّف برقم كشفها واسم الموظف', () {
      final r = ExpenseRow.fromJson({
        'id': 90,
        'amount': 525000,
        'expense_date': '2026-11-13',
        'note': 'راتب أحمد',
        'payslip': {'id': 3, 'number': 2, 'employee_id': 7, 'employee_name': 'أحمد'},
      })!;
      expect(r.isPayslip, isTrue);
      expect(r.payslipNumber, 2);
      expect(r.payslipEmployee, 'أحمد');
      expect(ExpenseRow.fromJson({'id': 91, 'amount': 1000, 'expense_date': '2026-11-13'})!.isPayslip, isFalse);
    });
  });

  group('راتبٌ واحد للموظف في كلّ صفحاته (المالك ١٤ نوفمبر)', () {
    test('العقد: salary.elsewhere ⇒ أين وكم؛ بلا مبلغٍ ⇒ لا شيء؛ بلا اسمٍ ⇒ «في صفحةٍ أخرى»', () {
      final s = LedgerSalary.fromJson(elsewhereSalaryJson());
      expect(s.configured, isFalse);
      expect(s.describe((n) => '$n'), isNull);
      final e = s.elsewhere!;
      expect(e.pageName, 'صفحة الراتب');
      expect(e.where, 'في صفحة «صفحة الراتب»');
      expect(e.salary.describe(formatIQD), '400,000 شهريّاً — يوم 25');
      expect(LedgerSalaryElsewhere.fromJson({'amount': null, 'cycle': 'monthly'}), isNull);
      expect(LedgerSalaryElsewhere.fromJson({'amount': 100000, 'cycle': 'weekly', 'pay_day': 4})!.where, 'في صفحةٍ أخرى');
      expect(LedgerSalary.fromJson(ledgerAccountJson()['salary']).elsewhere, isNull, reason: 'العقد القديم كما هو');
    });

    testWidgets('اللوحة: «الراتب في صفحة «…»: المبلغ» للمدير و«راتبك …» للموظف', (t) async {
      await phone(t);
      Widget panel(bool selfView) => app(Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: EmployeeLedgerPanel(
                account: LedgerAccount.fromJson(ledgerAccountJson()..['salary'] = elsewhereSalaryJson())!,
                selfView: selfView,
              ),
            ),
          ));
      await t.pumpWidget(panel(false));
      await t.pumpAndSettle();
      expect(t.widget<Text>(find.byKey(const ValueKey('emp-ledger-salary'))).data, 'الراتب في صفحة «صفحة الراتب»: 400,000 شهريّاً — يوم 25');
      expect(find.byKey(const ValueKey('emp-ledger-salary-due')), findsNothing);
      await t.pumpWidget(panel(true));
      await t.pumpAndSettle();
      expect(t.widget<Text>(find.byKey(const ValueKey('emp-ledger-salary'))).data, 'راتبك في صفحة «صفحة الراتب»: 400,000 شهريّاً — يوم 25');
    });

    testWidgets('بطاقة «سلفي وراتبي»: لا شيء عليه ولا له ⇒ «راتبك في صفحة «…»»', (t) async {
      await phone(t);
      final a = LedgerAccount.fromJson(ledgerAccountJson()
        ..['owed'] = 0
        ..['loans_total'] = 0
        ..['owes_total'] = 0
        ..['due_pending'] = 0
        ..['loans'] = []
        ..['salary'] = elsewhereSalaryJson())!;
      await t.pumpWidget(app(Scaffold(body: EmployeeLedgerCard(loader: () async => a))));
      await t.pumpAndSettle();
      expect(t.widget<Text>(find.byKey(const ValueKey('emp-ledger-card-headline'))).data, 'راتبك في صفحة «صفحة الراتب»');
    });

    testWidgets('المحرّر: راتبه في صفحةٍ أخرى ⇒ سطرٌ يقول أين بدل الحقول، والحفظ لا يرسل راتباً', (t) async {
      await phone(t);
      PermissionsService.debugSet(isEmployee: false);
      server.salaryElsewhere = true;
      final catalog = PermissionsCatalog.fromJson({
        'permissions': {
          'subscribers.view': {'label': 'عرض المشتركين', 'category': 'subscribers'},
        },
        'categories': {
          'subscribers': {'label': 'المشتركون'},
        },
        'defaults': {'subscribers.view': true},
        'presets': <String, Object>{},
      });
      final emp = Employee.fromJson({'id': 7, 'username': 'emp1', 'full_name': 'أحمد', 'is_active': true, 'permissions': {}})!;
      await opener(t, (c) => showEmployeeEditorSheet(c, catalog: catalog, employee: emp), (_) {});
      expect(find.byKey(const ValueKey('emp-salary-section')), findsOneWidget);
      await t.ensureVisible(find.byKey(const ValueKey('emp-salary-elsewhere')));
      await settle(t, frames: 5);
      expect(find.text('400,000 شهريّاً — يوم 25 — في صفحة «صفحة الراتب»'), findsOneWidget);
      expect(find.text('للموظف راتبٌ واحد لكلّ صفحاته — يُعدَّل ويُصرف من تلك الصفحة.'), findsOneWidget);
      expect(find.byKey(const ValueKey('emp-salary-amount')), findsNothing);
      expect(find.text('طريقة الأجر'), findsNothing);
      await t.tap(find.text('حفظ'));
      await settle(t, frames: 40);
      expect(server.bodiesOf('PUT', '/api/v2/employee-ledger/7/salary'), isEmpty);
    });
  });
}
