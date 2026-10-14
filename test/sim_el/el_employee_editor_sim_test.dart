import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/employees_api.dart';
import 'package:rad_mysvcs/screens/employees/sheets/employee_editor_sheet.dart';
import 'package:rad_mysvcs/services/active_company.dart';
import 'package:rad_mysvcs/services/provider_service.dart';

import 'sim_harness.dart';

/// محاكاة محرّر موظّف ايرث لنك (`employee_editor_sheet.dart`، `isEarthlink`):
/// سطر «سيعمل الموظف على»، تبويب الصلاحيّات بمفاتيح ايرث لنك وحدها، وصفّ
/// `subscribers.add` بتسميته وتلميحه، والأدوار الجاهزة، ولوحة بيانات الدخول.
const _screen = 'el_employee';

const _addLabel = 'إضافة مشترك';
const _addHint =
    'بالرصيد (بباسورد الإيداع — يُخصم من رصيد الوكيل) أو بكارت أو تجريبي';

/// كتالوج الخادم: مفاتيح ايرث لنك ومعها ما لا يخصّها (مدراء، أجهزة، إعدادات،
/// واتساب عامّ) — يجب ألّا يظهر هذا الأخير في محرّر ايرث لنك.
final _catalog = PermissionsCatalog.fromJson({
  'permissions': {
    'subscribers.view': {'label': 'عرض المشتركين', 'category': 'subscribers'},
    'subscribers.add': {'label': _addLabel, 'category': 'subscribers'},
    'subscribers.activate': {'label': 'تفعيل/تجديد', 'category': 'subscribers'},
    'subscribers.extend': {'label': 'تمديد', 'category': 'subscribers'},
    'subscribers.toggle': {'label': 'تعطيل/تفعيل الحساب', 'category': 'subscribers'},
    'subscribers.edit': {'label': 'تعديل بيانات المشترك', 'category': 'subscribers'},
    'subscribers.view_credentials': {
      'label': 'عرض كلمة مرور المشترك',
      'category': 'subscribers'
    },
    'subscribers.add_debt': {'label': 'إضافة دين', 'category': 'subscribers'},
    'subscribers.pay_debt': {'label': 'تسديد دين', 'category': 'subscribers'},
    'subscribers.send_whatsapp': {'label': 'إرسال واتساب', 'category': 'subscribers'},
    'subscribers.view_activity': {'label': 'سجلّ حركات المشترك', 'category': 'subscribers'},
    'packages.view': {'label': 'عرض الباقات', 'category': 'packages'},
    'packages.edit_prices': {'label': 'تعديل أسعار البيع', 'category': 'packages'},
    'discounts.view': {'label': 'عرض الخصومات', 'category': 'discounts'},
    'discounts.manage': {'label': 'إدارة الخصومات', 'category': 'discounts'},
    'subscriber_prices.view': {'label': 'عرض أسعار المشتركين', 'category': 'discounts'},
    'subscriber_prices.manage': {'label': 'إدارة أسعار المشتركين', 'category': 'discounts'},
    'reports.financial': {'label': 'التقارير الماليّة', 'category': 'reports'},
    'reports.activations': {'label': 'تقرير التفعيلات', 'category': 'reports'},
    'reports.daily_activations': {'label': 'تفعيلات اليوم', 'category': 'reports'},
    'reports.expenses': {'label': 'الصرفيات', 'category': 'reports'},
    'reports.account_statement': {'label': 'كشف الحساب', 'category': 'reports'},
    'reports.sessions': {'label': 'الجلسات', 'category': 'reports'},
    'reports.activity_log': {'label': 'سجلّ النشاط', 'category': 'reports'},
    'settlements.view': {'label': 'عرض التسويات', 'category': 'settlements'},
    'settlements.create': {'label': 'إنشاء تسوية', 'category': 'settlements'},
    // ليست لموظّفي ايرث لنك:
    'managers.view': {'label': 'عرض المدراء الفرعيّين', 'category': 'managers'},
    'devices.view': {'label': 'عرض الأجهزة', 'category': 'devices'},
    'settings.manage': {'label': 'إدارة الإعدادات', 'category': 'settings'},
    'whatsapp.send': {'label': 'إرسال رسائل واتساب عامّة', 'category': 'whatsapp'},
  },
  'categories': {
    'subscribers': {'label': 'المشتركون'},
    'packages': {'label': 'الباقات'},
    'discounts': {'label': 'الخصومات والأسعار'},
    'reports': {'label': 'التقارير'},
    'settlements': {'label': 'التسويات'},
    'managers': {'label': 'المدراء'},
    'devices': {'label': 'الأجهزة'},
    'settings': {'label': 'الإعدادات'},
    'whatsapp': {'label': 'واتساب'},
  },
  'defaults': {'subscribers.view': true, 'whatsapp.send': true},
  'presets': <String, Object>{},
});

/// مفاتيح الصلاحيّات تُعرض تحت كلّ تسمية — قرارٌ قائمٌ في المحرّر (SAS4
/// أيضاً)، تُستثنى من فحص النصّ الخام في الحالات العاديّة ولها حالتها
/// المستقلّة [perm_keys_visible].
final _permKey = RegExp(r'^[a-z_]+\.[a-z_]+$');

/// خطأ Flutter المعروف في تبويب المعلومات: `SwitchListTile` («الحساب مفعّل»)
/// داخل `DecoratedBox` ملوّن (سطح DesignSheet) — يُبلَّغ مع كلّ بناء. حالة
/// [create_info] تُفشل عليه (العطل نفسه)، وبقيّة الحالات تتجاوزه وحده كي
/// تفحص ما يخصّها.
const _listTileError = 'ListTile background color or ink splashes may be invisible';

Future<void> _tolerateListTile(Future<void> Function() body) async {
  final prev = FlutterError.onError;
  FlutterError.onError = (d) {
    if (d.exceptionAsString().contains(_listTileError)) return;
    prev?.call(d);
  };
  try {
    await body();
  } finally {
    FlutterError.onError = prev;
  }
}

/// [simCase] لحالةٍ تتجاوز خطأ ListTile المعروف وحده.
void _case(String state, Future<void> Function(WidgetTester t, SimVariant v) body) =>
    simCase(_screen, state, (t, v) => _tolerateListTile(() => body(t, v)));

void main() {
  late SimServer server;

  setUpAll(simSetUpAll);

  setUp(() async {
    server = await simSetUp();
    ProviderService.debugSet('earthlink');
    await ActiveCompany.saveFromLogin(
      sasUrl: '',
      adminId: 'earthlink:5',
      loginUsername: 'mahdi.el',
      adminUsername: 'mahdi.el',
      isEmployee: false,
      label: 'ايرث لنك (Earthlink)',
      sasCode: 'earthlink',
    );
  });

  tearDown(ActiveCompany.clear);

  Future<void> open(WidgetTester t, SimVariant v, {Employee? employee}) async {
    await pumpSim(t, v,
        home: (_) => simLauncher((c) => showEmployeeEditorSheet(c,
            catalog: _catalog, employee: employee, isEarthlink: true)));
    await simOpen(t);
  }

  Future<void> permsTab(WidgetTester t) async {
    await t.tap(find.textContaining('الصلاحيات ('));
    await t.pumpAndSettle();
  }

  Finder addRow() => find.ancestor(
      of: find.text(_addLabel), matching: find.byType(Container)).first;

  Switch addSwitch(WidgetTester t) => t.widget<Switch>(
      find.descendant(of: addRow(), matching: find.byType(Switch)));

  /// يعيد تبويب الصلاحيّات إلى أعلاه (الأدوار الجاهزة).
  Future<void> permsTop(WidgetTester t) async {
    final list = find
        .ancestor(of: find.text(_addLabel), matching: find.byType(Scrollable))
        .first;
    t.state<ScrollableState>(list).position.jumpTo(0);
    await t.pumpAndSettle();
  }

  Future<void> reveal(WidgetTester t, Finder f) async {
    await t.ensureVisible(f);
    await t.pumpAndSettle();
  }

  simCase(_screen, 'create_info', (t, v) async {
    await open(t, v);
    expect(find.text('موظف جديد'), findsOneWidget);
    expect(simText('سيعمل الموظف على: ايرث لنك (Earthlink) · mahdi.el'),
        findsOneWidget);
    expect(find.text('كلمة المرور (6 أحرف على الأقل)'), findsOneWidget);
    expect(find.textContaining('مدير فرعي'), findsNothing, reason: 'لا قيد بمدير');
    await simCheck(t, v, _screen, 'create_info');
  });

  // تبويب المعلومات نفسه بلا خطأ ListTile المعروف — أيّ عطلٍ آخر (فيضان،
  // نصّ خام) يظهر هنا لا خلفه.
  _case('info_layout', (t, v) async {
    await open(t, v);
    await t.enterText(find.widgetWithText(TextField,
        'اسم المستخدم — يستعمله الموظف للدخول'), 'sara.el');
    await t.pumpAndSettle();
    await reveal(t, find.text('الحساب مفعّل'));
    await simCheck(t, v, _screen, 'info_layout');
  });

  _case('perms_add_row', (t, v) async {
    await open(t, v);
    await permsTab(t);
    expect(find.text(_addLabel), findsOneWidget);
    expect(find.text(_addHint), findsOneWidget);
    expect(find.text('subscribers.add'), findsOneWidget);
    // ما ليس لموظّفي ايرث لنك لا يُعرض.
    for (final hidden in [
      'عرض المدراء الفرعيّين',
      'عرض الأجهزة',
      'إدارة الإعدادات',
      'إرسال رسائل واتساب عامّة',
    ]) {
      expect(find.text(hidden), findsNothing, reason: hidden);
    }
    expect(addSwitch(t).value, isFalse);
    await reveal(t, find.text(_addHint));
    await simCheck(t, v, _screen, 'perms_add_row', allow: [_permKey]);
    final before = find.textContaining('الصلاحيات (1)');
    expect(before, findsOneWidget, reason: 'subscribers.view افتراضاً');
    await t.tap(find.descendant(of: addRow(), matching: find.byType(Switch)));
    await t.pumpAndSettle();
    expect(addSwitch(t).value, isTrue);
    expect(find.textContaining('الصلاحيات (2)'), findsOneWidget);
  });

  _case('preset_general_then_collect', (t, v) async {
    await open(t, v);
    await permsTab(t);
    await t.tap(find.text('موظّف عام'));
    await t.pumpAndSettle();
    expect(find.text('يرى ويعمل كلّ ما يُسمح به لموظّف'), findsOneWidget);
    expect(find.textContaining('الصلاحيات (26)'), findsOneWidget);
    await reveal(t, find.text(_addHint));
    expect(addSwitch(t).value, isTrue, reason: 'العامّ يشمل الإضافة');
    await simCheck(t, v, _screen, 'preset_general', allow: [_permKey]);
    await permsTop(t);
    await t.tap(find.text('تفعيل وتحصيل'));
    await t.pumpAndSettle();
    expect(find.text('تفعيل وتمديد وتسديد ديون وواتساب'), findsOneWidget);
    await reveal(t, find.text(_addHint));
    expect(addSwitch(t).value, isFalse, reason: 'التحصيل بلا إضافة');
    await simCheck(t, v, _screen, 'preset_collect', allow: [_permKey]);
  });

  _case('edit_employee', (t, v) async {
    final emp = Employee.fromJson({
      'id': 31,
      'username': 'ahmed.cashier',
      'full_name': 'أحمد الكاشير',
      'phone': '07701112233',
      'is_active': 1,
      'permissions': {
        'subscribers.view': true,
        'subscribers.add': true,
        'subscribers.activate': true,
      },
    });
    await open(t, v, employee: emp);
    expect(find.text('تعديل موظف'), findsOneWidget);
    await permsTab(t);
    expect(find.textContaining('الصلاحيات (3)'), findsOneWidget);
    expect(find.text('مخصّص — عدّلت الصلاحيّات يدويّاً'), findsOneWidget);
    await reveal(t, find.text(_addHint));
    expect(addSwitch(t).value, isTrue);
    await simCheck(t, v, _screen, 'edit_employee', allow: [_permKey]);
  });

  _case('create_success_credentials', (t, v) async {
    server.on('POST', '/api/v2/employees', (o) {
      final b = o.data as Map;
      return SimReply(200, {
        'success': true,
        'data': {
          'id': 77,
          'username': '${b['username']}'.toLowerCase(),
          'full_name': b['full_name'],
          'is_active': 1,
          'permissions': b['permissions'],
        },
      });
    });
    await open(t, v);
    await t.enterText(find.widgetWithText(TextField,
        'اسم المستخدم — يستعمله الموظف للدخول'), 'Sara.EL');
    await t.enterText(find.widgetWithText(TextField,
        'كلمة المرور (6 أحرف على الأقل)'), 'sara-2026');
    await t.enterText(find.widgetWithText(TextField, 'الاسم الكامل'), 'سارة');
    await permsTab(t);
    await reveal(t, find.text(_addHint));
    await t.tap(find.descendant(of: addRow(), matching: find.byType(Switch)));
    await t.pumpAndSettle();
    await t.tap(find.text('حفظ'));
    await t.pumpAndSettle();
    final perms = Map<String, dynamic>.from(
        server.bodies('POST', '/api/v2/employees').single['permissions'] as Map);
    expect(perms['subscribers.add'], isTrue);
    expect(perms['subscribers.view'], isTrue);
    expect(perms['managers.view'], isFalse, reason: 'ما لم يره المالك لا يُمنح');
    expect(perms['devices.view'], isFalse);
    expect(perms['whatsapp.send'], isFalse,
        reason: 'يتبع «إرسال واتساب» — والمالك لم يمنحه');
    expect(find.text('تمّ إنشاء الموظف'), findsOneWidget);
    expect(find.text('sara.el'), findsWidgets, reason: 'اليوزر كما حفظه الخادم');
    await simCheck(t, v, _screen, 'create_success_credentials');
  });

  _case('perm_keys_visible', (t, v) async {
    await open(t, v);
    await permsTab(t);
    await reveal(t, find.text(_addHint));
    await simCheck(t, v, _screen, 'perm_keys_visible', allow: [_permKey]);
    // مفاتيح الصلاحيّات تُعرض تحت كلّ تسمية عمداً — قرارٌ قائمٌ في المحرّر
    // (SAS4 أيضاً)، لا عطلٌ يُخفى. فنتأكّد أنّها ظاهرةٌ فعلاً.
    final keys = simVisibleTexts().where(_permKey.hasMatch).toList();
    expect(keys, isNotEmpty,
        reason: 'مفاتيح الصلاحيّات يجب أن تظهر تحت كلّ تسمية (قرارٌ مقصود)');
    expect(keys, contains('subscribers.add'));
  });
}
