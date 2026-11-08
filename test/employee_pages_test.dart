import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/account_api.dart';
import 'package:rad_mysvcs/api/auth_api.dart';
import 'package:rad_mysvcs/api/employees_api.dart';
import 'package:rad_mysvcs/screens/employees/sheets/employee_pages_sheet.dart';
import 'package:rad_mysvcs/screens/employees/sheets/link_employee_sheet.dart';
import 'package:rad_mysvcs/screens/top_actions.dart';
import 'package:rad_mysvcs/services/linked_companies.dart';
import 'package:rad_mysvcs/services/permissions_service.dart';

import 'sim_el/sim_harness.dart';

/// ٨ نوفمبر — «موظّفٌ بأكثر من صفحة» (المالك: «نفس الموظف نسنده لاكثر من صفحه… رح يصير نفس المدير بس بصلاحيات هو محددها؟…
/// تمام ابدي بيها»): النماذج، «صفحاتي» في سطر الشركة وورقتها والتنقّل بتوكن الموظّف، وورقة «موظف من صفحة أخرى» للمالك.
void main() {
  late SimServer api;

  setUpAll(simSetUpAll);

  setUp(() async {
    api = await simSetUp(secure: {'auth.token': 'emp-token', 'auth.admin_id': '2251'});
    LinkedCompanies.reset();
    PermissionsService.debugSet(isEmployee: false);
  });

  tearDown(() {
    PermissionsService.debugReset();
    LinkedCompanies.reset();
    EmployeePagesSheet.switchCall = AuthApi.employeeSwitch;
    EmployeePagesSheet.complete = (s, u) async => true;
    LinkEmployeeSheet.load = AccountApi.employees;
    LinkEmployeeSheet.link = AccountApi.linkEmployee;
  });

  const pages = [
    {'employee_id': 1, 'page_id': '2251', 'page_name': 'سوبرنت', 'primary': true, 'current': true, 'active': true, 'login_username': 'ali'},
    {'employee_id': 9, 'page_id': 'earthlink:1025', 'page_name': 'ايرث', 'primary': false, 'current': false, 'active': true, 'login_username': 'ali'},
    {'employee_id': 12, 'page_id': 'watani:5', 'page_name': 'الوطني', 'active': false, 'login_username': 'ali'},
  ];

  group('النماذج', () {
    test('صفحات الموظّف: صفحتان فأكثر، والتالف يسقط، واسم الدخول معها', () {
      final p = EmployeePageRef.listFrom(pages);
      expect(p.map((x) => [x.employeeId, x.pageId, x.pageName, x.primary, x.current, x.active]).toList(), [
        [1, '2251', 'سوبرنت', true, true, true],
        [9, 'earthlink:1025', 'ايرث', false, false, true],
        [12, 'watani:5', 'الوطني', false, false, false],
      ]);
      expect(p.first.loginUsername, 'ali');
      expect(EmployeePageRef.listFrom([pages.first]), isEmpty, reason: 'صفحةٌ واحدة ⇒ لا «صفحاتي»');
      expect(EmployeePageRef.listFrom([{'employee_id': 'x'}, pages[0], {'page_id': ''}]), isEmpty);
      expect(EmployeePageRef.listFrom('x'), isEmpty);
      final round = EmployeePageRef.listFrom([for (final x in EmployeePageRef.listFrom(pages)) x.toJson()]);
      expect(round.map((x) => x.employeeId), [1, 9, 12]);
      final me = CurrentIdentity.fromJson({'is_employee': true, 'employee_id': 9, 'permissions': {}, 'pages': pages});
      expect(me!.pages, hasLength(3));
    });

    test('صفّ الموظّف المربوط: الأصليّ «بأكثر من صفحة»، والنسخة بلا كلمة مرور (isLinkedCopy)', () {
      final copy = Employee.fromJson({'id': 9, 'username': 'ali@earthlink-1025', 'is_active': true, 'linked': {'login_username': 'ali', 'primary': false, 'pages': 2}})!;
      expect([copy.isLinkedCopy, copy.linked!.loginUsername, copy.linked!.pages], [true, 'ali', 2]);
      final orig = Employee.fromJson({'id': 1, 'username': 'ali', 'is_active': true, 'linked': {'login_username': 'ali', 'primary': true, 'pages': 2}})!;
      expect(orig.isLinkedCopy, isFalse);
      expect(Employee.fromJson({'id': 2, 'username': 'x', 'is_active': true})!.linked, isNull);
    });

    test('موظّفو الحساب: من يُضاف لصفحة = من صفحةٍ أخرى، فعّال، صفّه الأصليّ، وليس له صفٌّ فيها', () {
      final d = AccountEmployees.fromJson({
        'pages': [
          {'id': '2251', 'name': 'سوبرنت'},
          {'id': 'earthlink:1025', 'name': 'ايرث'},
        ],
        'employees': [
          {'id': 1, 'username': 'ali', 'login_username': 'ali', 'page_id': '2251', 'is_active': true, 'primary': true, 'pages': ['2251']},
          {'id': 2, 'username': 'off', 'page_id': '2251', 'is_active': false, 'primary': true, 'pages': ['2251']},
          {'id': 3, 'username': 'sara', 'page_id': '2251', 'is_active': true, 'primary': true, 'pages': ['2251', 'earthlink:1025']},
          {'id': 4, 'username': 'el.emp', 'page_id': 'earthlink:1025', 'is_active': true, 'primary': true, 'pages': ['earthlink:1025']},
          {'id': 5, 'username': 'sara@earthlink-1025', 'login_username': 'sara', 'page_id': 'earthlink:1025', 'is_active': true, 'primary': false, 'pages': ['2251', 'earthlink:1025']},
        ],
      });
      expect(d.addableTo('earthlink:1025').map((e) => e.id), [1], reason: 'لا المعطّل ولا من له صفٌّ فيها ولا موظّفوها');
      expect(d.addableTo('2251').map((e) => e.id), [4], reason: 'لا النسخة المضافة');
      expect(d.pageName('earthlink:1025'), 'ايرث');
    });
  });

  group('«صفحاتي» في سطر الشركة', () {
    test('موظّفٌ بصفحتين ⇒ للسطر نقرةٌ باسم «صفحاتي»؛ بصفحةٍ واحدة أو مديرٌ ⇒ لا', () {
      PermissionsService.debugSet(isEmployee: true, pages: EmployeePageRef.listFrom(pages));
      expect([HeaderSwitch.employeePages, HeaderSwitch.available, HeaderSwitch.label], [true, true, 'صفحاتي']);
      PermissionsService.debugSet(isEmployee: true);
      expect(HeaderSwitch.employeePages, isFalse);
      PermissionsService.debugSet(isEmployee: false, pages: EmployeePageRef.listFrom(pages));
      expect(HeaderSwitch.employeePages, isFalse, reason: 'المدير لا «صفحاتي» له');
    });
  });

  group('التنقّل', () {
    test('employeeSwitch: المسار نفسه بـswitch_to وتوكن الموظّف بالترويسة، والردّ كدخول الموظّف', () async {
      api.reply('POST', '/api/auth/employee-login', 200, {
        'success': true,
        'token': 'new-token',
        'expiresAt': '2026-11-09T20:00:00.000Z',
        'user': {
          'id': 'earthlink:1025',
          'username': 'el-a',
          'role': 'employee',
          'provider': 'earthlink',
          'employee': {'id': 9, 'username': 'ali@earthlink-1025', 'permissions': {'subscribers.view': true}, 'pages': pages},
        },
      });
      final r = await AuthApi.employeeSwitch(9, token: 'emp-token');
      expect(r, isA<LoginSuccess>());
      final s = r as LoginSuccess;
      expect([s.token, s.adminId, s.isEmployee, s.provider], ['new-token', 'earthlink:1025', true, 'earthlink']);
      final call = api.calls('POST', '/api/auth/employee-login').single;
      expect(call.data, {'switch_to': 9});
      expect(call.headers['Authorization'], 'Bearer emp-token');
    });

    test('employeeSwitch: رفض الخادم ⇒ رسالته العربيّة كما هي (لا توكن جديد)', () async {
      api.reply('POST', '/api/auth/employee-login', 403, {'success': false, 'code': 'NOT_YOUR_PAGE', 'message': 'هذه الصفحة ليست من صفحاتك'});
      final r = await AuthApi.employeeSwitch(77, token: 'emp-token');
      expect(r, isA<LoginFailure>());
      expect((r as LoginFailure).message, 'هذه الصفحة ليست من صفحاتك');
      expect(r.code, 'NOT_YOUR_PAGE');
    });

    testWidgets('الورقة: الحاليّة معلَّمة ولا تُنقر، والمعطّلة برسالة بلا نداء، والفشل برسالة الخادم والجلسة باقية', (t) async {
      PermissionsService.debugSet(isEmployee: true, pages: EmployeePageRef.listFrom(pages));
      final asked = <int>[];
      EmployeePagesSheet.switchCall = (id) async {
        asked.add(id);
        return const LoginFailure('اشتراك مدير هذه الصفحة منتهٍ — تواصل مع مديرك', code: 'subscription-ended');
      };
      await pumpSim(t, const SimVariant(390, dark: false), home: (_) => simLauncher((c) => showEmployeePagesSheet(c)));
      await simOpen(t);
      expect(find.text('صفحاتي'), findsOneWidget);
      expect(find.text('الصفحة الحاليّة'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('employee-page-1')));
      await t.pumpAndSettle();
      expect(asked, isEmpty, reason: 'الحاليّة لا تُنقر');
      await t.tap(find.byKey(const ValueKey('employee-page-12')));
      await t.pumpAndSettle();
      expect(asked, isEmpty, reason: 'المعطّلة رسالةٌ بلا نداء');
      expect(find.textContaining('معطّل'), findsWidgets);
      await t.tap(find.byKey(const ValueKey('employee-page-9')));
      await t.pumpAndSettle();
      expect(asked, [9]);
      expect(find.text('اشتراك مدير هذه الصفحة منتهٍ — تواصل مع مديرك'), findsOneWidget);
    });
  });

  group('موظف من صفحة أخرى (المالك)', () {
    testWidgets('الورقة: موظّفو الصفحات الأخرى مجمَّعين، والتأكيد ثمّ الربط بالصفحة المفتوحة', (t) async {
      final linked = <List<Object>>[];
      LinkEmployeeSheet.load = () async => AccountEmployees.fromJson({
            'pages': [
              {'id': '2251', 'name': 'سوبرنت'},
              {'id': 'earthlink:1025', 'name': 'ايرث'},
            ],
            'employees': [
              {'id': 1, 'username': 'ali', 'full_name': 'علي', 'login_username': 'ali', 'page_id': '2251', 'is_active': true, 'primary': true, 'pages': ['2251']},
              {'id': 4, 'username': 'el.emp', 'page_id': 'earthlink:1025', 'is_active': true, 'primary': true, 'pages': ['earthlink:1025']},
            ],
          });
      LinkEmployeeSheet.link = ({required int employeeId, required String toPageId}) async {
        linked.add([employeeId, toPageId]);
        return (ok: true, message: null);
      };
      bool? result;
      await pumpSim(t, const SimVariant(390, dark: false),
          home: (_) => simLauncher((c) async => result = await showLinkEmployeeSheet(c, pageId: 'earthlink:1025')));
      await simOpen(t);
      expect(find.text('موظف من صفحة أخرى'), findsOneWidget);
      expect(find.text('سوبرنت'), findsOneWidget, reason: 'مجمَّعون بصفحاتهم');
      expect(find.byKey(const ValueKey('link-employee-1')), findsOneWidget);
      expect(find.byKey(const ValueKey('link-employee-4')), findsNothing, reason: 'موظّف الصفحة المفتوحة نفسها');
      await t.tap(find.byKey(const ValueKey('link-employee-1')));
      await t.pumpAndSettle();
      expect(find.text('إضافة علي لهذه الصفحة؟'), findsOneWidget);
      await t.tap(find.text('إضافة'));
      await t.pumpAndSettle();
      expect(linked, [
        [1, 'earthlink:1025']
      ]);
      expect(result, isTrue);
    });

    testWidgets('الرفض برسالة الخادم وتبقى الورقة', (t) async {
      LinkEmployeeSheet.load = () async => AccountEmployees.fromJson({
            'pages': [
              {'id': '2251', 'name': 'سوبرنت'},
              {'id': 'earthlink:1025', 'name': 'ايرث'},
            ],
            'employees': [
              {'id': 1, 'username': 'ali', 'login_username': 'ali', 'page_id': '2251', 'is_active': true, 'primary': true, 'pages': ['2251']},
            ],
          });
      LinkEmployeeSheet.link = ({required int employeeId, required String toPageId}) async =>
          (ok: false, message: 'بلغت حدّ الموظّفين لهذه الصفحة (5)');
      await pumpSim(t, const SimVariant(360, dark: true),
          home: (_) => simLauncher((c) => showLinkEmployeeSheet(c, pageId: 'earthlink:1025')));
      await simOpen(t);
      await t.tap(find.byKey(const ValueKey('link-employee-1')));
      await t.pumpAndSettle();
      await t.tap(find.text('إضافة'));
      await t.pumpAndSettle();
      expect(find.text('بلغت حدّ الموظّفين لهذه الصفحة (5)'), findsOneWidget);
      expect(find.text('موظف من صفحة أخرى'), findsOneWidget, reason: 'الورقة باقية');
    });

    testWidgets('لا موظّفين يُضافون ⇒ جملةٌ تقول لماذا', (t) async {
      LinkEmployeeSheet.load = () async => AccountEmployees.fromJson({
            'pages': [
              {'id': 'earthlink:1025', 'name': 'ايرث'},
            ],
            'employees': const [],
          });
      await pumpSim(t, const SimVariant(360, dark: false),
          home: (_) => simLauncher((c) => showLinkEmployeeSheet(c, pageId: 'earthlink:1025')));
      await simOpen(t);
      expect(find.textContaining('أضف صفحةً أخرى أوّلاً'), findsOneWidget);
    });
  });
}
