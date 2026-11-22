import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/employees_api.dart';
import 'package:rad_mysvcs/screens/employees/sheets/employee_editor_sheet.dart';
import 'package:rad_mysvcs/services/active_company.dart';
import 'package:rad_mysvcs/services/provider_service.dart';

import 'sim_harness.dart';

/// «موظّف ايرث لنك تابع لمدير فرعي» (٢٢ نوفمبر — المالك: «اضافة موظف لايرثلنك ليش مايظهر جوة ليا صفحه اريد اضيفه مثل بقيه
/// الساسات» ثمّ «… نكدر نخلي تابع اله»). الخادم 521d86b: النطاق `earthlink:<رقم الحساب التابع>` والموظّف يعمل بجلسته ورصيده.
/// ما يُحرس هنا (بلا لقطاتٍ ذهبيّة — نصوصٌ وأجسام طلبات):
///   • مالك ايرث لنك (`elScope`): الحقل بحسابات «المدراء» (`/api/v2/el/managers`) لا مدراء الساس، والإنشاء يُرسل
///     `scope_admin_id: earthlink:<رقمه>`، وبلا اختيار لا حقل يُرسَل، والتعديل بـ«بلا قيد» يمسحه (null) وبلا لمس لا يُرسله.
///   • قيدٌ محفوظ لحسابٍ لم يعد في القائمة يبقى ظاهراً باسمه (لا يُمسح صامتاً ولا يتعطّل الـdropdown).
///   • تعذّر القائمة/الميزة مطفأة ⇒ لا حقل (لا «جارٍ التحميل» دائم) والإنشاء يمضي بلا قيد.
///   • فايبر اكس/المُضافة (`isEarthlink` بلا `elScope`): لا حقل ولا طلب قائمة — كما كانت.
const _screen = 'el_employee_scope';
const _list = '/api/v2/el/managers';
const _hintFree = 'الموظّف يعمل بحسابك أنت: كلّ مشتركيك ورصيدك.';
const _hintScoped = 'الموظّف تابع — يعمل بحساب المدير الفرعي المختار: مشتركوه ورصيده فقط.';

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

Map<String, dynamic> _managers({bool enabled = true}) => enabled
    ? {
        'success': true,
        'enabled': true,
        'data': {
          'balance': 250000,
          'deposit_saved': true,
          'managers': [
            {'index': 153574, 'name': 'T-Akrm', 'other_debt': 0, 'has_app': true},
            {'index': 153085, 'name': 'T-Aboj-very-long-sub-account-name', 'other_debt': 0, 'has_app': false},
          ],
        },
      }
    : {'success': true, 'enabled': false};

Employee _scoped({String scope = 'earthlink:153574', String? name = 'admin@T-Akrm'}) => Employee.fromJson({
      'id': 41,
      'username': 'emp.tabi',
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
    ProviderService.debugSet('earthlink');
    await ActiveCompany.saveFromLogin(
      sasUrl: '',
      adminId: 'earthlink:153357',
      loginUsername: 'admin@T-Zs',
      adminUsername: 'admin@T-Zs',
      isEmployee: false,
      label: 'ايرث لنك (Earthlink)',
      sasCode: 'earthlink',
    );
    server.reply('POST', '/api/v2/employees', 200, {
      'success': true,
      'data': {'id': 77, 'username': 'emp.new', 'is_active': 1, 'permissions': {'subscribers.view': true}},
    });
    server.reply('PUT', '/api/v2/employees/41', 200, {
      'success': true,
      'data': {'id': 41, 'username': 'emp.tabi', 'is_active': 1, 'permissions': {'subscribers.view': true}},
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

  Future<void> open(WidgetTester t, SimVariant v, {Employee? employee, bool elScope = true}) async {
    await pumpSim(t, v,
        home: (_) => simLauncher((c) => showEmployeeEditorSheet(c,
            catalog: _catalog, employee: employee, isEarthlink: true, elScope: elScope)));
    await simOpen(t);
  }

  Finder dropdown() => find.byWidgetPredicate((w) => w is DropdownButton<String?>);

  Future<void> choose(WidgetTester t, String label) async {
    await t.ensureVisible(dropdown());
    await t.pumpAndSettle();
    await t.tap(dropdown());
    await t.pumpAndSettle();
    await t.tap(find.text(label).last);
    await t.pumpAndSettle();
  }

  Future<void> fillAndSave(WidgetTester t) async {
    await t.enterText(find.widgetWithText(TextField, 'اسم المستخدم — يستعمله الموظف للدخول'), 'emp.new');
    await t.enterText(find.widgetWithText(TextField, 'كلمة المرور (6 أحرف على الأقل)'), 'secret-12');
    await t.pumpAndSettle();
    await t.tap(find.text('حفظ'));
    await t.pumpAndSettle();
  }

  simCase(_screen, 'create_scoped', (t, v) => tolerate(() async {
        server.reply('GET', _list, 200, _managers());
        await open(t, v);
        expect(server.calls('GET', _list), hasLength(1), reason: 'القائمة من «المدراء»');
        expect(server.calls('GET', '/api/v2/managers'), isEmpty, reason: 'لا مدراء ساس لايرث لنك');
        expect(find.text(_hintFree), findsOneWidget);
        await choose(t, 'T-Akrm');
        expect(find.text(_hintScoped), findsOneWidget);
        await fillAndSave(t);
        final body = server.bodies('POST', '/api/v2/employees').single;
        expect(body['scope_admin_id'], 'earthlink:153574');
        expect(body['perms_shown_only'], isTrue);
        await simDrain(t);
      }));

  simCase(_screen, 'long_name_fits', (t, v) => tolerate(() async {
        server.reply('GET', _list, 200, _managers());
        await open(t, v);
        await choose(t, 'T-Aboj-very-long-sub-account-name');
        // الاسم الطويل بسطرٍ واحد مقصوصٍ بنقاط داخل الحقل — لا فيضان (الإطار يُفشل الاختبار على أيّ RenderFlex overflow)
        expect(find.text(_hintScoped), findsOneWidget);
        await fillAndSave(t);
        expect(server.bodies('POST', '/api/v2/employees').single['scope_admin_id'], 'earthlink:153085');
        await simDrain(t);
      }));

  simCase(_screen, 'create_free', (t, v) => tolerate(() async {
        server.reply('GET', _list, 200, _managers());
        await open(t, v);
        await fillAndSave(t);
        final body = server.bodies('POST', '/api/v2/employees').single;
        expect(body.containsKey('scope_admin_id'), isFalse, reason: 'بلا اختيار لا قيد يُرسَل');
        await simDrain(t);
      }));

  simCase(_screen, 'edit_clear', (t, v) => tolerate(() async {
        server.reply('GET', _list, 200, _managers());
        await open(t, v, employee: _scoped());
        expect(find.text('T-Akrm'), findsOneWidget, reason: 'الحقل يعرض حسابه الحاليّ');
        expect(find.text(_hintScoped), findsOneWidget);
        await choose(t, 'بلا قيد — يشاهد كل بياناتك');
        await t.tap(find.text('حفظ'));
        await t.pumpAndSettle();
        final body = server.bodies('PUT', '/api/v2/employees/41').single;
        expect(body.containsKey('scope_admin_id'), isTrue);
        expect(body['scope_admin_id'], isNull, reason: '«بلا قيد» يمسح القيد');
        await simDrain(t);
      }));

  simCase(_screen, 'edit_untouched', (t, v) => tolerate(() async {
        server.reply('GET', _list, 200, _managers());
        await open(t, v, employee: _scoped());
        await t.tap(find.text('حفظ'));
        await t.pumpAndSettle();
        final body = server.bodies('PUT', '/api/v2/employees/41').single;
        expect(body.containsKey('scope_admin_id'), isFalse, reason: 'بلا لمس لا يُرسَل فلا يُمسح القيد صامتاً');
        await simDrain(t);
      }));

  simCase(_screen, 'edit_gone_kept', (t, v) => tolerate(() async {
        server.reply('GET', _list, 200, _managers());
        await open(t, v, employee: _scoped(scope: 'earthlink:999', name: 'admin@old-sub'));
        expect(find.text('admin@old-sub'), findsOneWidget, reason: 'حسابٌ لم يعد في القائمة يبقى ظاهراً باسمه');
        await t.tap(find.text('حفظ'));
        await t.pumpAndSettle();
        expect(server.bodies('PUT', '/api/v2/employees/41').single.containsKey('scope_admin_id'), isFalse);
        await simDrain(t);
      }));

  simCase(_screen, 'list_failed', (t, v) => tolerate(() async {
        server.reply('GET', _list, 409, {'success': false, 'code': 'EL_UNAVAILABLE', 'message': 'تعذّر'});
        await open(t, v);
        expect(dropdown(), findsNothing);
        expect(find.text('جارٍ تحميل المدراء...'), findsNothing, reason: 'لا تحميلٌ دائم');
        await fillAndSave(t);
        expect(server.bodies('POST', '/api/v2/employees').single.containsKey('scope_admin_id'), isFalse);
        await simDrain(t);
      }));

  simCase(_screen, 'feature_off', (t, v) => tolerate(() async {
        server.reply('GET', _list, 200, _managers(enabled: false));
        await open(t, v);
        expect(dropdown(), findsNothing);
        expect(find.text('جارٍ تحميل المدراء...'), findsNothing);
        await simDrain(t);
      }));

  simCase(_screen, 'fiberx_or_kit_no_field', (t, v) => tolerate(() async {
        server.reply('GET', _list, 200, _managers());
        await open(t, v, elScope: false);
        expect(dropdown(), findsNothing);
        expect(find.textContaining('مدير فرعي'), findsNothing);
        expect(server.calls('GET', _list), isEmpty);
        expect(server.calls('GET', '/api/v2/managers'), isEmpty);
        await fillAndSave(t);
        expect(server.bodies('POST', '/api/v2/employees').single.containsKey('scope_admin_id'), isFalse);
        await simDrain(t);
      }));
}
