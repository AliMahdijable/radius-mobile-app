import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/api/employee_ledger_api.dart';
import 'package:rad_mysvcs/api/employees_api.dart';
import 'package:rad_mysvcs/screens/employees/employee_account_screen.dart';
import 'package:rad_mysvcs/screens/employees/employee_ledger_widgets.dart';
import 'package:rad_mysvcs/screens/employees/employee_my_ledger_screen.dart';
import 'package:rad_mysvcs/screens/employees/employees_screen.dart';
import 'package:rad_mysvcs/screens/employees/sheets/employee_editor_sheet.dart';
import 'package:rad_mysvcs/screens/expenses/expenses_screen.dart';
import 'package:rad_mysvcs/screens/reports/financial_report_screen.dart';
import 'package:rad_mysvcs/screens/settlements/settlements_screen.dart';
import 'package:rad_mysvcs/services/permissions_service.dart';

import 'employee_ledger/ledger_fixture.dart';
import 'visual_perm/visual_perm_harness.dart';

/// «حركات الموظف» وراتبه — لقطاتٌ للمراجعة (١٣ نوفمبر): قسم الموظفين، حساب الموظف، «حركة جديدة»، «كشف الراتب»، حقول الراتب،
/// منتقي الإضافة السريعة، «سلفي وراتبي»، وأثرها في الصندوق والتقرير الماليّ والصرفيات — بعرض ٣٢٠/٣٦٠/٣٩٠ فاتحاً وداكناً.
/// بياناتٌ تجريبيّة وحدها. المخرجات: VISUAL_OUT (أو build/visual_perm المُتجاهَل بgit).
const _devices = [
  VisualDevice('320', Size(320, 760), 3),
  VisualDevice('360', Size(360, 800), 3),
  VisualDevice('390_dark', Size(390, 844), 3, dark: true),
];

Future<void> _shot(WidgetTester t, String name, VisualDevice d) async {
  final boundary = t.renderObject<RenderRepaintBoundary>(find.byKey(visualRootKey));
  final png = await t.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: d.dpr);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return data!.buffer.asUint8List();
  });
  final f = File('${visualOutDir()}/ledger_${name}_${d.tag}.png');
  f.parent.createSync(recursive: true);
  f.writeAsBytesSync(png!, flush: true);
  final ex = t.takeException();
  expect(ex, isNull, reason: 'استثناء في $name ${d.tag}:\n$ex');
}

void main() {
  setUpAll(visualSetUpAll);

  late LedgerServer server;

  Future<void> up({bool employee = false}) async {
    await visualSetUp(s1bSasOwner);
    server = LedgerServer();
    ApiClient.dio.httpClientAdapter = server;
    PermissionsService.debugSet(isEmployee: employee, permissions: employee ? {'employees.view': true, 'employees.payroll': true} : const {});
    EmployeeLedgerState.reset();
  }

  Future<void> down(WidgetTester t) async {
    await t.pumpWidget(const SizedBox.shrink());
    await t.pump(const Duration(seconds: 4));
    EmployeeLedgerState.reset();
    await visualTearDown();
  }

  Finder field(String key) => find.descendant(of: find.byKey(ValueKey(key)), matching: find.byType(TextField));

  for (final d in _devices) {
    testWidgets('قسم الموظفين ${d.tag}', (t) async {
      await up();
      await pumpVisual(t, d, home: (_) => const EmployeesScreen());
      await settle(t, seconds: 2);
      await _shot(t, '01_employees', d);
      await down(t);
    });

    testWidgets('حساب الموظف ${d.tag}', (t) async {
      await up();
      await pumpVisual(t, d, home: (_) => const EmployeeAccountScreen(employeeId: 7, title: 'أحمد', ledger: (canWrite: true, canVoid: true)));
      await settle(t, seconds: 2);
      await _shot(t, '02_account', d);
      await t.drag(find.byType(ListView), const Offset(0, -520));
      await settle(t, seconds: 1);
      await _shot(t, '02_account_b', d);
      await t.drag(find.byType(ListView), const Offset(0, -620));
      await settle(t, seconds: 1);
      await _shot(t, '02_account_c', d);
      await down(t);
    });

    testWidgets('حركة جديدة ${d.tag}', (t) async {
      await up();
      await pumpVisual(
        t,
        d,
        home: (c) => Scaffold(body: Center(child: TextButton(onPressed: () => showEmployeeMoveSheet(c, employeeId: 7, name: 'أحمد', owes: 500000), child: const Text('افتح')))),
      );
      await settle(t, seconds: 1);
      await t.tap(find.text('افتح'));
      await settle(t, seconds: 1);
      await _shot(t, '03_move_empty', d);
      await t.tap(find.byKey(const ValueKey('emp-move-kind-loan')));
      await t.pump();
      await t.enterText(field('emp-move-amount'), '600');
      await t.pump();
      await t.enterText(field('emp-move-installment'), '100000');
      await settle(t, seconds: 1);
      await _shot(t, '03_move_loan', d);
      await down(t);
    });

    testWidgets('كشف الراتب ${d.tag}', (t) async {
      await up();
      server.preview = ledgerPreviewJson()
        ..['periods'] = [
          {'key': '2026-10', 'label': 'تشرين الأوّل 2026', 'due_date': '2026-10-28', 'due': true, 'amount': 500000, 'selected': false},
          {'key': '2026-11', 'label': 'تشرين الثاني 2026', 'due_date': '2026-11-28', 'due': true, 'amount': 500000, 'selected': true},
        ]
        ..['commission'] = {'enabled': true, 'ops': 12, 'sum': 60000, 'unavailable': false}
        ..['gross'] = 585000
        ..['net'] = 435000
        ..['expected'] = {'gross': 585000, 'net': 435000};
      await pumpVisual(
        t,
        d,
        home: (c) => Scaffold(body: Center(child: TextButton(onPressed: () => showEmployeePayslipSheet(c, employeeId: 7, name: 'أحمد', canSkip: true), child: const Text('افتح')))),
      );
      await settle(t, seconds: 1);
      await t.tap(find.text('افتح'));
      await settle(t, seconds: 1);
      await _shot(t, '04_payslip', d);
      await down(t);
    });

    testWidgets('حقول الراتب بالمحرّر ${d.tag}', (t) async {
      await up();
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
      await pumpVisual(
        t,
        d,
        home: (c) => Scaffold(body: Center(child: TextButton(onPressed: () => showEmployeeEditorSheet(c, catalog: catalog, employee: emp), child: const Text('افتح')))),
      );
      await settle(t, seconds: 1);
      await t.tap(find.text('افتح'));
      await settle(t, seconds: 2);
      // القائمة كسولة: حقول الراتب أسفل تبويب البيانات — تُسحب حتى تُبنى
      final list = find.byType(ListView).first;
      for (var i = 0; i < 12 && find.byKey(const ValueKey('emp-salary-mode')).evaluate().isEmpty; i++) {
        await t.drag(list, const Offset(0, -260));
        await settle(t, seconds: 1);
      }
      await t.drag(list, const Offset(0, -400));
      await settle(t, seconds: 1);
      await _shot(t, '05_editor_salary', d);
      await down(t);
    });

    testWidgets('منتقي الموظف ${d.tag}', (t) async {
      await up();
      await pumpVisual(
        t,
        d,
        home: (c) => Scaffold(body: Center(child: TextButton(onPressed: () => showEmployeePickSheet(c), child: const Text('افتح')))),
      );
      await settle(t, seconds: 1);
      await t.tap(find.text('افتح'));
      await settle(t, seconds: 1);
      await _shot(t, '06_pick', d);
      await down(t);
    });

    testWidgets('سلفي وراتبي ${d.tag}', (t) async {
      await up(employee: true);
      final a = LedgerAccount.fromJson(ledgerAccountJson())!;
      await pumpVisual(
        t,
        d,
        home: (_) => Scaffold(
          body: SafeArea(child: Padding(padding: const EdgeInsets.all(16), child: Column(children: [EmployeeLedgerCard(loader: () async => a)]))),
        ),
      );
      await settle(t, seconds: 1);
      await _shot(t, '07_my_card', d);
      await pumpVisual(t, d, home: (_) => EmployeeMyLedgerScreen(initial: a, loader: () async => a));
      await settle(t, seconds: 1);
      await _shot(t, '07_my_screen', d);
      await down(t);
    });

    testWidgets('الصندوق ${d.tag}', (t) async {
      await up();
      await pumpVisual(t, d, home: (_) => const SettlementsScreen());
      await settle(t, seconds: 2);
      await _shot(t, '08_box', d);
      await down(t);
    });

    testWidgets('الصرفيات ${d.tag}', (t) async {
      await up();
      await pumpVisual(t, d, home: (_) => const ExpensesScreen());
      await settle(t, seconds: 2);
      await _shot(t, '09_expenses', d);
      await down(t);
    });

    testWidgets('التقرير الماليّ ${d.tag}', (t) async {
      await up();
      await pumpVisual(t, d, home: (_) => const FinancialReportScreen());
      await settle(t, seconds: 2);
      await _shot(t, '10_finance', d);
      await down(t);
    });
  }
}
