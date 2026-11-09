import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/api/employee_limits_api.dart';
import 'package:rad_mysvcs/api/employees_api.dart';
import 'package:rad_mysvcs/screens/employees/employee_account_screen.dart';
import 'package:rad_mysvcs/screens/employees/sheets/employee_editor_sheet.dart';
import 'package:rad_mysvcs/services/permissions_service.dart';
import 'package:rad_mysvcs/widgets/employee_limits_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// «حدود الموظّف» (٩ نوفمبر): الحقول الثلاثة للمدير وحده، بطاقة الموظّف، وتسوية المدير مع موظّفه (معاينة ← تأكيدٌ بالحدّ نفسه).
void main() {
  late _Server server;

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    server = _Server();
    ApiClient.dio.httpClientAdapter = server;
    PermissionsService.debugReset();
  });

  tearDown(PermissionsService.debugReset);

  Widget app(Widget child) => EasyLocalization(
        supportedLocales: const [Locale('ar'), Locale('en')],
        path: 'assets/translations',
        startLocale: const Locale('ar'),
        fallbackLocale: const Locale('ar'),
        saveLocale: false,
        assetLoader: const _DiskLoader(),
        child: Builder(
          builder: (c) => MaterialApp(
            locale: c.locale,
            supportedLocales: c.supportedLocales,
            localizationsDelegates: c.localizationDelegates,
            home: Directionality(textDirection: TextDirection.rtl, child: child),
          ),
        ),
      );

  Future<void> phone(WidgetTester t) async {
    t.view.physicalSize = const Size(400, 1000);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
  }

  /// إطاراتٌ بزمنٍ محدود (لا pumpAndSettle: مؤشّر تحميل المدراء بالمحرّر والإشعارات تدور).
  Future<void> settle(WidgetTester t, {int frames = 20}) async {
    for (var i = 0; i < frames; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  group('النماذج', () {
    test('الحال من JSON الخادم: الحدود، المجاميع، المحجوز، التفصيل', () {
      final s = EmployeeLimitStatus.fromJson(_statusJson())!;
      expect(s.employeeId, 7);
      expect(s.limits.cashCap, 500000);
      expect(s.limits.debtCap, 200000);
      expect(s.limits.profitPerOp, 5000);
      expect(s.cashIn, 350000);
      expect(s.openDebt, 90000);
      expect(s.debtUsed, 90000);
      expect(s.openDebtApprox, isFalse);
      expect(s.cashUsed, 385000);
      expect(s.holdsCount, 1);
      expect(s.opsCount, 4);
      expect(s.profit, 20000);
      expect(s.breakdown['cash_activations']!.sum, 280000);
      expect(s.started, isTrue);
    });

    test('الحقول: فارغ/صفر = بلا حدّ، وفواصل الآلاف تُقرأ', () {
      final d = TextEditingController(text: '200,000');
      final c = TextEditingController(text: '');
      final p = TextEditingController(text: '0');
      final l = EmployeeLimitsFields.read(d, c, p);
      expect(l.debtCap, 200000);
      expect(l.cashCap, isNull);
      expect(l.profitPerOp, isNull);
      expect(EmployeeLimitsFields.initialText(500000), '500,000');
      expect(EmployeeLimitsFields.initialText(null), '');
    });

    test('أسماء عمليّات المحجوز بالعربيّ — ومنها «تعبئة محفظة» (الوطنيّ على الدين)', () {
      const ops = {
        'activate': 'تفعيل',
        'activate_card': 'تفعيل',
        'pay_debt': 'تسديد دين',
        'add_debt': 'إضافة دين',
        'sale': 'بيع',
        'create': 'إضافة مشترك',
        'wallet_topup': 'تعبئة محفظة',
      };
      for (final e in ops.entries) {
        final h = EmployeeLimitHold(id: 1, op: e.key, cash: 0, debt: 1000, status: 'unknown');
        expect(h.opLabel, e.value, reason: e.key);
      }
    });
  });

  group('بطاقة الموظّف', () {
    testWidgets('تعرض النقد/السقف والدين والربح، وتحذيراً عند بلوغ السقف', (t) async {
      await phone(t);
      final json = _statusJson()
        ..['cash_used'] = 500000
        ..['cash_blocked'] = true;
      await t.pumpWidget(app(Scaffold(
        body: EmployeeLimitsCard(loader: () async => EmployeeLimitStatus.fromJson(json)),
      )));
      await t.pumpAndSettle();
      expect(find.text('حسابي مع المدير'), findsOneWidget);
      expect(find.textContaining('500,000 / 500,000'), findsOneWidget);
      expect(find.textContaining('200,000'), findsWidgets);
      expect(find.text('20,000 د.ع'), findsOneWidget);
      expect(find.textContaining('سوِّ حسابك مع المدير'), findsOneWidget);
      // الدين = ديونه المفتوحة عند المشتركين (لا ديون الفترة)
      expect(find.text('ديونك المفتوحة عند المشتركين'), findsOneWidget);
      expect(find.textContaining('90,000 / 200,000'), findsOneWidget);
    });

    testWidgets('بلوغ سقف الديون المفتوحة ⇒ «حتى يسدّد المشتركون» لا «سوِّ حسابك»', (t) async {
      await phone(t);
      final json = _statusJson()
        ..['open_debt'] = 200000
        ..['debt_used'] = 200000
        ..['debt_blocked'] = true;
      await t.pumpWidget(app(Scaffold(
        body: EmployeeLimitsCard(loader: () async => EmployeeLimitStatus.fromJson(json)),
      )));
      await t.pumpAndSettle();
      expect(find.textContaining('ديونك المفتوحة بلغت السقف'), findsOneWidget);
      expect(find.textContaining('حتى يسدّد المشتركون'), findsOneWidget);
      expect(find.textContaining('سوِّ حسابك'), findsNothing);
    });

    testWidgets('لم يبدأ العدّ (لا حدود) ⇒ لا شيء ولا مساحة', (t) async {
      await phone(t);
      await t.pumpWidget(app(Scaffold(
        body: EmployeeLimitsCard(loader: () async => EmployeeLimitStatus.fromJson({
          'employee': {'id': 7},
          'feature_enabled': true,
          'limits': {'debt_cap': null, 'cash_cap': null, 'profit_per_op': null},
          'started': false,
        })),
      )));
      await t.pumpAndSettle();
      expect(find.text('حسابي مع المدير'), findsNothing);
    });
  });

  group('المحرّر: الحقول الثلاثة للمدير وحده', () {
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
    final emp = Employee.fromJson({'id': 7, 'username': 'emp1', 'full_name': 'موظف', 'is_active': true, 'permissions': {}})!;

    Future<void> openEditor(WidgetTester t) async {
      await t.pumpWidget(app(Builder(
        builder: (c) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => showEmployeeEditorSheet(c, catalog: catalog, employee: emp),
              child: const Text('افتح'),
            ),
          ),
        ),
      )));
      await t.pumpAndSettle();
      await t.tap(find.text('افتح'));
      await settle(t);
    }

    testWidgets('المدير والميزة مفتوحة ⇒ «حدود الموظف» بقيمها المحفوظة، والحفظ يرسلها', (t) async {
      await phone(t);
      PermissionsService.debugSet(isEmployee: false);
      server.meFeature = true;
      await openEditor(t);
      expect(find.byKey(const ValueKey('emp-limits-section')), findsOneWidget);
      expect(find.text('سقف الديون'), findsOneWidget);
      expect(find.text('سقف الإيرادات النقديّة'), findsOneWidget);
      expect(find.text('ربح الموظف لكلّ عمليّة'), findsOneWidget);
      // القيم المحفوظة مقروءة (500,000 نقداً)
      expect(find.text('500,000'), findsOneWidget);
      // تعديل سقف الديون ثمّ الحفظ
      await t.enterText(find.descendant(of: find.byKey(const ValueKey('emp-limit-debt')), matching: find.byType(TextField)), '300000');
      await t.pump();
      await t.tap(find.text('حفظ'));
      await settle(t, frames: 30);
      final put = server.bodiesOf('PUT', '/api/v2/employee-limits/7');
      expect(put, hasLength(1));
      expect(put.single['debt_cap'], 300000);
      expect(put.single['cash_cap'], 500000);
      expect(put.single['profit_per_op'], 5000);
    });

    testWidgets('الموظّف (ولو مَلَك employees.manage) ⇒ لا حقول ولا نداء', (t) async {
      await phone(t);
      PermissionsService.debugSet(isEmployee: true, permissions: {'employees.manage': true});
      server.meFeature = true;
      await openEditor(t);
      expect(find.byKey(const ValueKey('emp-limits-section')), findsNothing);
      expect(server.paths.where((p) => p.startsWith('/api/v2/employee-limits')), isEmpty);
    });

    testWidgets('الميزة مطفأة لحساب المدير ⇒ لا حقول', (t) async {
      await phone(t);
      PermissionsService.debugSet(isEmployee: false);
      server.meFeature = false;
      await openEditor(t);
      expect(find.byKey(const ValueKey('emp-limits-section')), findsNothing);
      expect(server.paths.contains('/api/v2/employee-limits/7'), isFalse);
    });
  });

  group('تسوية المدير مع الموظّف', () {
    testWidgets('معاينة ← تأكيدٌ بالحدّ والأرقام نفسها (ما تراه هو ما يُسوّى)', (t) async {
      await phone(t);
      EmployeeSettlement? result;
      await t.pumpWidget(app(Builder(
        builder: (c) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () async => result = await showEmployeeSettleSheet(c, employeeId: 7, name: 'موظف'),
              child: const Text('سوِّ'),
            ),
          ),
        ),
      )));
      await t.pumpAndSettle();
      await t.tap(find.text('سوِّ'));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('emp-settle-cash')), findsOneWidget);
      expect(find.text('350,000 د.ع'), findsWidgets);
      // الدين للعلم ولا يُصفَّر (قرار المالك ٩ نوفمبر)
      expect(find.text('ديونه المفتوحة عند المشتركين (لا تُصفَّر)'), findsOneWidget);
      expect(find.textContaining('تصفير الحساب'), findsNothing);
      await t.tap(find.text('تأكيد التسوية — تصفير النقد'));
      await settle(t, frames: 40);
      final posts = server.bodiesOf('POST', '/api/v2/employee-limits/7/settlement');
      expect(posts, hasLength(1));
      final b = posts.single;
      expect(b['cut'], {'head_id': 3, 'activity_id': 900, 'debt_tx_id': 0, 'sale_cash_id': 4, 'sale_id': 2, 'hold_id': 1});
      expect(b['expected'], {'cash_in': 350000, 'debt_out': 120000, 'ops_count': 4, 'profit': 20000});
      expect((b['idempotency_key'] as String).length, greaterThanOrEqualTo(8));
      expect(result?.number, 1);
    });

    testWidgets('STALE ⇒ معاينةٌ جديدة ولا يُغلق الشيت', (t) async {
      await phone(t);
      server.settleReplies.add((409, {'success': false, 'code': 'STALE', 'message': 'تغيّرت الأرقام منذ فتحت المعاينة — راجعها وأكّد من جديد'}));
      await t.pumpWidget(app(Builder(
        builder: (c) => Scaffold(
          body: TextButton(
            onPressed: () => showEmployeeSettleSheet(c, employeeId: 7, name: 'موظف'),
            child: const Text('سوِّ'),
          ),
        ),
      )));
      await t.pumpAndSettle();
      await t.tap(find.text('سوِّ'));
      await t.pumpAndSettle();
      await t.tap(find.text('تأكيد التسوية — تصفير النقد'));
      await settle(t, frames: 40);
      expect(server.paths.where((p) => p == '/api/v2/employee-limits/7/settlement/preview').length, 2);
      expect(find.byKey(const ValueKey('emp-settle-cash')), findsOneWidget);
    });

    testWidgets('شاشة حساب الموظف: الحال والمحجوز وزرّ التسوية والسجلّ', (t) async {
      await phone(t);
      await t.pumpWidget(app(const EmployeeAccountScreen(employeeId: 7, title: 'موظف')));
      await t.pumpAndSettle();
      expect(find.text('الفترة الحاليّة'), findsOneWidget);
      expect(find.byKey(const ValueKey('emp-settle-open')), findsOneWidget);
      expect(find.text('مبالغ محجوزة (غير مؤكَّدة)'), findsOneWidget);
      expect(find.text('التسويات السابقة'), findsOneWidget);
      expect(find.textContaining('سقف الإيرادات النقديّة: 500,000'), findsOneWidget);
    });
  });
}

Map<String, dynamic> _statusJson() => {
      'employee': {'id': 7, 'username': 'emp1', 'name': 'موظف'},
      'feature_enabled': true,
      'enforcement_off': false,
      'limits': {'debt_cap': 200000, 'cash_cap': 500000, 'profit_per_op': 5000},
      'started': true,
      'period': {'start_at': '2026-11-09T05:00:00.000Z', 'head_id': 3},
      'cash_in': 350000,
      'debt_out': 120000,
      'open_debt': 90000,
      'open_debt_approx': false,
      'holds': {'count': 1, 'cash': 35000, 'debt': 0},
      'cash_used': 385000,
      'debt_used': 90000,
      'cash_remaining': 115000,
      'debt_remaining': 80000,
      'cash_blocked': false,
      'debt_blocked': false,
      'ops_count': 4,
      'profit': 20000,
      'breakdown': {
        'cash_activations': {'sum': 280000, 'count': 8},
        'debt_payments': {'sum': 50000, 'count': 2},
        'sales_cash': {'sum': 20000, 'count': 1},
        'credit_activations': {'sum': 100000, 'count': 3},
        'partial_unpaid': {'sum': 10000, 'count': 1},
        'debts_added': {'sum': 10000, 'count': 1},
      },
    };

class _DiskLoader extends AssetLoader {
  const _DiskLoader();
  @override
  Future<Map<String, dynamic>?> load(String path, Locale locale) =>
      Future.value(jsonDecode(File('assets/translations/${locale.languageCode}.json').readAsStringSync()) as Map<String, dynamic>);
}

class _Server implements HttpClientAdapter {
  bool meFeature = true;
  final List<(int, Map<String, dynamic>)> settleReplies = [];
  final _reqs = <RequestOptions>[];

  List<String> get paths => _reqs.map((r) => r.path).toList();
  List<Map<String, dynamic>> bodiesOf(String method, String path) => _reqs
      .where((r) => r.method == method && r.path == path)
      .map((r) => Map<String, dynamic>.from(r.data as Map))
      .toList();

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    _reqs.add(o);
    (int, Map<String, dynamic>) reply = (404, {'success': false});
    if (o.path == '/api/v2/employee-limits/me') {
      reply = (200, {'success': true, 'data': {'is_employee': false, 'feature_enabled': meFeature, 'enforcement_off': false}});
    } else if (o.path == '/api/v2/employee-limits/7' && o.method == 'GET') {
      reply = (200, {
        'success': true,
        'data': {
          ..._statusJson(),
          'holds_list': [
            {'id': 1, 'op': 'activate', 'cash': 35000, 'debt': 0, 'status': 'unknown', 'created_at': '2026-11-09T06:00:00.000Z'},
          ],
          'settlements': [
            {'id': 4, 'number': 1, 'status': 'active', 'cash_in': 100000, 'debt_out': 0, 'ops_count': 2, 'profit': 10000, 'cut_at': '2026-11-08T20:00:00.000Z'},
          ],
        },
      });
    } else if (o.path == '/api/v2/employee-limits/7' && o.method == 'PUT') {
      reply = (200, {'success': true, 'data': _statusJson()});
    } else if (o.path == '/api/v2/employees/7' && o.method == 'PUT') {
      reply = (200, {'success': true, 'data': {'id': 7, 'username': 'emp1'}});
    } else if (o.path == '/api/v2/employee-limits/7/settlement/preview') {
      reply = (200, {
        'success': true,
        'data': {
          'cut': {'head_id': 3, 'activity_id': 900, 'debt_tx_id': 0, 'sale_cash_id': 4, 'sale_id': 2, 'hold_id': 1},
          'period': {'start_at': '2026-11-09T05:00:00.000Z'},
          'cash_in': 350000,
          'debt_out': 120000,
          'open_debt': 90000,
          'settles': ['cash_in', 'ops_count', 'profit'],
          'holds': {'count': 1, 'cash': 35000, 'debt': 0},
          'ops_count': 4,
          'profit': 20000,
          'breakdown': _statusJson()['breakdown'],
        },
      });
    } else if (o.path == '/api/v2/employee-limits/7/settlement' && o.method == 'POST') {
      reply = settleReplies.isNotEmpty
          ? settleReplies.removeAt(0)
          : (200, {'success': true, 'data': {'id': 5, 'number': 1, 'status': 'active', 'cash_in': 350000}});
    }
    return ResponseBody.fromString(jsonEncode(reply.$2), reply.$1, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}
