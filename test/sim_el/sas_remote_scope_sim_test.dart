import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/employees_api.dart';
import 'package:rad_mysvcs/screens/employees/sheets/employee_editor_sheet.dart';
import 'package:rad_mysvcs/services/active_company.dart';
import 'package:rad_mysvcs/services/provider_service.dart';

import 'sim_harness.dart';

/// «مقيَّد بمدير فرعي» على ساسٍ غير الأصليّ (٢٣ نوفمبر — المالك: «الموظف مرات من يضيفه لمدير جوه مدير جواه يكله هذا مو تابع الك
/// المدير»). الخادم 4e46ed9 يحفظ القيد مؤهَّلاً بساس الصفحة (`super-xwifi:5`) وقائمة «المدراء» (`/api/v2/managers`) عارية (`5`).
/// ما يُحرس هنا (نصوصٌ وأجسام طلبات):
///   • المحفوظ المؤهَّل يُعرض باسمه من القائمة مرّةً واحدة (لا عنصر «محفوظ» ثانٍ لنفس المدير).
///   • الحفظ بلا لمس، أو باختيار المدير نفسه من القائمة، لا يُرسل `scope_admin_id` (لا تحقّقٌ جديد ولا مسحٌ صامت).
///   • مديرٌ آخر ⇒ رقمه كما في القائمة (الخادم يؤهّله)، و«بلا قيد» ⇒ null.
///   • مديرٌ خرج من القائمة يبقى ظاهراً باسمه، والأصليّ (عارٍ = عارٍ) كما كان.
const _screen = 'sas_remote_scope';
const _list = '/api/v2/managers';
const _five = 'علي حسن · sub.five';
const _seven = 'sub.seven';
const _none = 'بلا قيد — يشاهد كل بياناتك';

final _catalog = PermissionsCatalog.fromJson({
  'permissions': {
    'subscribers.view': {'label': 'عرض المشتركين', 'category': 'subscribers'},
    'subscribers.activate': {'label': 'تفعيل/تجديد', 'category': 'subscribers'},
  },
  'categories': {
    'subscribers': {'label': 'المشتركون'},
  },
  'defaults': {'subscribers.view': true},
  'presets': <String, Object>{},
});

final _managers = {
  'success': true,
  'data': [
    {'id': 5, 'username': 'sub.five', 'firstname': 'علي', 'lastname': 'حسن'},
    {'id': 7, 'username': 'sub.seven', 'firstname': '', 'lastname': ''},
  ],
};

Employee _scoped(String scope, {String? name = 'sub.five'}) => Employee.fromJson({
      'id': 42,
      'username': 'emp.remote',
      'full_name': 'موظف تابع',
      'is_active': 1,
      'permissions': {'subscribers.view': true},
      'scope_admin_id': scope,
      'scope_admin_username': name,
    })!;

void main() {
  late SimServer server;

  setUpAll(simSetUpAll);

  setUp(() async {
    server = await simSetUp();
    ProviderService.debugSet('sas4');
    await ActiveCompany.saveFromLogin(
      sasUrl: '',
      adminId: 'super-xwifi:9',
      loginUsername: 'owner.x',
      adminUsername: 'owner.x',
      isEmployee: false,
      label: 'شبكة النور',
      sasCode: 'super-xwifi',
    );
    server.reply('GET', _list, 200, _managers);
    server.reply('PUT', '/api/v2/employees/42', 200, {
      'success': true,
      'data': {'id': 42, 'username': 'emp.remote', 'is_active': 1, 'permissions': {'subscribers.view': true}},
    });
  });

  tearDown(ActiveCompany.clear);

  // خطأ ListTile المعروف في تبويب المعلومات (SwitchListTile على سطح DesignSheet الملوّن) — لا يخصّ هذا الاختبار.
  Future<void> tolerate(Future<void> Function() body) async {
    final prev = FlutterError.onError;
    FlutterError.onError = (d) {
      if (d.exceptionAsString().contains('ListTile background color or ink splashes may be invisible')) return;
      prev?.call(d);
    };
    try {
      await body();
    } finally {
      FlutterError.onError = prev;
    }
  }

  Future<void> open(WidgetTester t, SimVariant v, Employee employee) async {
    await pumpSim(t, v, home: (_) => simLauncher((c) => showEmployeeEditorSheet(c, catalog: _catalog, employee: employee)));
    await simOpen(t);
  }

  Finder dropdown() => find.byWidgetPredicate((w) => w is DropdownButton<String?>);
  DropdownButton<String?> field(WidgetTester t) => t.widget<DropdownButton<String?>>(dropdown());

  Future<void> choose(WidgetTester t, String label) async {
    await t.ensureVisible(dropdown());
    await t.pumpAndSettle();
    await t.tap(dropdown());
    await t.pumpAndSettle();
    await t.tap(find.text(label).last);
    await t.pumpAndSettle();
  }

  Future<Map<String, dynamic>> save(WidgetTester t) async {
    await t.tap(find.text('حفظ'));
    await t.pumpAndSettle();
    return server.bodies('PUT', '/api/v2/employees/42').single;
  }

  simCase(_screen, 'qualified_untouched', (t, v) => tolerate(() async {
        await open(t, v, _scoped('super-xwifi:5'));
        expect(server.calls('GET', _list), hasLength(1));
        expect(find.text(_five), findsOneWidget, reason: 'المحفوظ المؤهَّل يُعرض باسمه من القائمة');
        expect(field(t).value, '5', reason: 'القيمة = خيار القائمة لنفس المدير');
        expect(field(t).items, hasLength(3), reason: '«بلا قيد» + المديران — لا عنصر محفوظ ثانٍ لنفس المدير');
        final body = await save(t);
        expect(body.containsKey('scope_admin_id'), isFalse, reason: 'بلا لمس لا يُرسَل');
        await simDrain(t);
      }));

  simCase(_screen, 'qualified_pick_same', (t, v) => tolerate(() async {
        await open(t, v, _scoped('super-xwifi:5'));
        await choose(t, _five);
        final body = await save(t);
        expect(body.containsKey('scope_admin_id'), isFalse, reason: 'المدير نفسه بصيغته العارية ليس تغييراً');
        await simDrain(t);
      }));

  simCase(_screen, 'qualified_change', (t, v) => tolerate(() async {
        await open(t, v, _scoped('super-xwifi:5'));
        await choose(t, _seven);
        final body = await save(t);
        expect(body['scope_admin_id'], '7', reason: 'رقمه كما في القائمة — الخادم يؤهّله');
        await simDrain(t);
      }));

  simCase(_screen, 'qualified_clear', (t, v) => tolerate(() async {
        await open(t, v, _scoped('super-xwifi:5'));
        await choose(t, _none);
        final body = await save(t);
        expect(body.containsKey('scope_admin_id'), isTrue);
        expect(body['scope_admin_id'], isNull, reason: '«بلا قيد» يمسح القيد');
        await simDrain(t);
      }));

  simCase(_screen, 'qualified_gone_kept', (t, v) => tolerate(() async {
        await open(t, v, _scoped('super-xwifi:11', name: 'sub.gone'));
        expect(find.text('sub.gone'), findsOneWidget, reason: 'مديرٌ خرج من القائمة يبقى ظاهراً باسمه');
        expect(field(t).value, 'super-xwifi:11');
        expect(field(t).items, hasLength(4));
        final body = await save(t);
        expect(body.containsKey('scope_admin_id'), isFalse);
        await simDrain(t);
      }));

  simCase(_screen, 'home_bare_untouched', (t, v) => tolerate(() async {
        await open(t, v, _scoped('5'));
        expect(find.text(_five), findsOneWidget);
        expect(field(t).value, '5');
        expect(field(t).items, hasLength(3));
        final body = await save(t);
        expect(body.containsKey('scope_admin_id'), isFalse);
        await simDrain(t);
      }));

  test('sameScopeId: الرقم المحلّيّ داخل الصفحة، وايرث لنك حرفاً، وبلا قيد = بلا قيد', () {
    expect(sameScopeId('5', 'super-xwifi:5'), isTrue);
    expect(sameScopeId('super-xwifi:5', '5'), isTrue);
    expect(sameScopeId('5', '5'), isTrue);
    expect(sameScopeId('super-xwifi:5', 'super-xwifi:5'), isTrue);
    expect(sameScopeId('5', 'super-xwifi:7'), isFalse);
    expect(sameScopeId('15', 'super-xwifi:5'), isFalse);
    expect(sameScopeId('earthlink:5', 'earthlink:5'), isTrue);
    expect(sameScopeId('earthlink:5', '5'), isFalse);
    expect(sameScopeId('5', 'earthlink:5'), isFalse);
    expect(sameScopeId(null, ''), isTrue);
    expect(sameScopeId(null, null), isTrue);
    expect(sameScopeId(null, '5'), isFalse);
    expect(sameScopeId('', 'super-xwifi:5'), isFalse);
  });
}
