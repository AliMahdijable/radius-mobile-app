import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/notifications_api.dart';
import 'package:rad_mysvcs/models/app_notification.dart';
import 'package:rad_mysvcs/screens/notifications_settings_screen.dart';
import 'package:rad_mysvcs/screens/reports/v2/activity_log_v2_screen.dart';
import 'package:rad_mysvcs/services/notification_router.dart';
import 'package:rad_mysvcs/services/permissions_service.dart';
import 'package:rad_mysvcs/services/provider_service.dart';

import 'sim_el/sim_harness.dart';

/// «عمليّات الموظّفين» (المالك ٢٣ نوفمبر: «اي موظف يسوي عمليه يذهب اشعار للمدير بهاي العمليه» — الخادم server/employeeOps.js):
/// مفتاح push_employee_ops في «إشعاراتي» حين يتيحه الخادم (employee_ops.available)، مقفلٌ للموظّف (can_edit=false) كالموقع،
/// والحفظ لا يُسقط الإتاحة (ردّ PUT بلا employee_ops) ولا يرسل المفتاح من شاشةٍ لم تعرضه؛ ونقر الإشعار ⇒ «سجلّ الحركات» بفلتره.
const _v = SimVariant(390, dark: false);
const _owner = 'supernet:12';

Map<String, Object?> _prefs({Object? push = true}) => {
      'push_near_expiry': true,
      'push_expired_today': true,
      'push_manager_debt': true,
      'quiet_hours_enabled': true,
      'quiet_hours_start': '23:00:00',
      'quiet_hours_end': '07:00:00',
      if (push != null) 'push_employee_ops': push,
    };

Map<String, Object?> _get({bool? available = true, bool canEdit = true, Object? push = true}) => {
      'success': true,
      'prefs': _prefs(push: push),
      if (available != null) 'employee_ops': {'available': available, 'can_edit': canEdit},
    };

void main() {
  late SimServer server;

  setUpAll(simSetUpAll);

  setUp(() async {
    server = await simSetUp(secure: {'auth.admin_id': _owner, 'auth.admin_username': 'owner'});
    PermissionsService.debugSet(isEmployee: false);
    ProviderService.debugSet('sas4');
  });

  tearDown(() {
    PermissionsService.debugReset();
    ProviderService.debugSet(null);
  });

  // الموجِّه يقرأ هويّة الجلسة (تخزينٌ حقيقيّ اللاتزامن) قبل أن يفتح — دوراتٌ حقيقيّةٌ قصيرة بين الإطارات
  Future<void> settle(WidgetTester t) async {
    for (var i = 0; i < 10; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  Map<String, dynamic> lastPut() => Map<String, dynamic>.from(server.calls('PUT', '/api/admin/notification-prefs').last.data as Map);

  test('القراءة: push_employee_ops غائبٌ ⇒ مفعّل، 0 ⇒ مطفأ؛ employee_ops غائبٌ ⇒ غير متاح، can_edit غائبٌ ⇒ يعدّل', () {
    final absent = NotificationPrefs.fromJson(_prefs(push: null));
    expect(absent.pushEmployeeOps, isTrue);
    expect(absent.employeeOpsAvailable, isFalse, reason: 'خادمٌ أقدم أو صفحةٌ بلا المفتاح ⇒ لا مفتاح بالشاشة');
    expect(absent.employeeOpsCanEdit, isTrue);
    expect(NotificationPrefs.fromJson(_prefs(push: 0)).pushEmployeeOps, isFalse);
    expect(NotificationPrefs.fromJson(_prefs(push: '1')).pushEmployeeOps, isTrue);
    final emp = NotificationPrefs.fromJson(_prefs(), employeeOps: {'available': true, 'can_edit': false});
    expect(emp.employeeOpsAvailable, isTrue);
    expect(emp.employeeOpsCanEdit, isFalse);
    expect(NotificationPrefs.fromJson(_prefs(), employeeOps: {'available': 'yes'}).employeeOpsAvailable, isFalse,
        reason: 'true وحده يتيح');
    final c = emp.copyWith(quietHoursEnabled: false);
    expect((c.employeeOpsAvailable, c.employeeOpsCanEdit, c.pushEmployeeOps), (true, false, true),
        reason: 'copyWith يحمل الإتاحة');
  });

  test('التحميل يقرأ employee_ops من ردّ GET', () async {
    server.reply('GET', '/api/admin/notification-prefs', 200, _get(push: 0));
    final p = await NotificationsApi.load();
    expect(p!.pushEmployeeOps, isFalse);
    expect(p.employeeOpsAvailable, isTrue);
    expect(p.employeeOpsCanEdit, isTrue);
  });

  test('الحفظ: pushEmployeeOps لصاحب الصفحة حين عُرض وحده، وردّ الحفظ (بلا employee_ops) لا يُسقط الإتاحة', () async {
    server.reply('PUT', '/api/admin/notification-prefs', 200, {'success': true, 'prefs': _prefs(push: 0)});
    final base = NotificationPrefs.fromJson(_prefs(), employeeOps: {'available': true, 'can_edit': true});

    final r = await NotificationsApi.save(base.copyWith(pushEmployeeOps: false));
    expect(lastPut()['pushEmployeeOps'], isFalse);
    expect(r.ok, isTrue);
    expect(r.prefs!.pushEmployeeOps, isFalse);
    expect(r.prefs!.employeeOpsAvailable, isTrue, reason: 'وإلّا يختفي المفتاح بعد أوّل حفظ');
    expect(r.prefs!.employeeOpsCanEdit, isTrue);

    await NotificationsApi.save(NotificationPrefs.fromJson(_prefs()));
    expect(lastPut().containsKey('pushEmployeeOps'), isFalse, reason: 'غير متاح ⇒ المحفوظ بالخادم يبقى');

    final empR = await NotificationsApi.save(
        NotificationPrefs.fromJson(_prefs(), employeeOps: {'available': true, 'can_edit': false}).copyWith(quietHoursEnabled: false));
    expect(lastPut().containsKey('pushEmployeeOps'), isFalse, reason: 'الموظّف لا يرسله (والخادم يهمله منه)');
    expect(lastPut()['quietHoursEnabled'], isFalse);
    expect(empR.prefs!.employeeOpsCanEdit, isFalse);
  });

  Future<void> openSettings(WidgetTester t) async {
    await pumpSim(t, _v, home: (_) => const NotificationsSettingsScreen());
    await t.pump(const Duration(milliseconds: 300));
  }

  Finder toggle() => find.byKey(const ValueKey('notifs-employee-ops'));
  Switch switchOf(WidgetTester t) => t.widget<Switch>(find.descendant(of: toggle(), matching: find.byType(Switch)));

  testWidgets('الإعدادات: المفتاح حين يتيحه الخادم، ولمسه يحفظ ويبقى ظاهراً بحاله الجديد', (t) async {
    server.reply('GET', '/api/admin/notification-prefs', 200, _get());
    server.reply('PUT', '/api/admin/notification-prefs', 200, {'success': true, 'prefs': _prefs(push: false)});
    await openSettings(t);
    expect(toggle(), findsOneWidget);
    expect(find.text(kEmployeeOpsLabel), findsOneWidget);
    expect(find.text(kEmployeeOpsHint), findsOneWidget);
    expect(switchOf(t).value, isTrue);
    await t.ensureVisible(toggle());
    await t.tap(find.descendant(of: toggle(), matching: find.byType(Switch)));
    await t.pump(const Duration(milliseconds: 300));
    expect(lastPut()['pushEmployeeOps'], isFalse);
    expect(lastPut()['quietHoursStart'], '23:00', reason: 'بقيّة الإعدادات كما قُرئت');
    expect(toggle(), findsOneWidget, reason: 'الإتاحة باقية بعد الحفظ');
    expect(switchOf(t).value, isFalse);
    await simDrain(t);
  });

  testWidgets('الإعدادات: غير متاح ⇒ لا مفتاح؛ وخادمٌ أقدم بلا employee_ops ⇒ لا مفتاح', (t) async {
    server.reply('GET', '/api/admin/notification-prefs', 200, _get(available: false));
    await openSettings(t);
    expect(toggle(), findsNothing);
    expect(find.text(kEmployeeOpsLabel), findsNothing);
    await simDrain(t);

    server.reply('GET', '/api/admin/notification-prefs', 200, _get(available: null, push: null));
    await openSettings(t);
    expect(toggle(), findsNothing);
    await simDrain(t);
  });

  testWidgets('الإعدادات: الموظّف يراه بمكانه مقفلاً — لا يتغيّر ولا يُحفظ، ولمسه يقول السبب', (t) async {
    PermissionsService.debugSet(isEmployee: true);
    server.reply('GET', '/api/admin/notification-prefs', 200, _get(canEdit: false));
    await openSettings(t);
    expect(toggle(), findsOneWidget);
    expect(find.text(kEmployeeOpsLocked), findsWidgets);
    expect(switchOf(t).onChanged, isNull);
    expect(switchOf(t).value, isTrue);
    await t.ensureVisible(toggle());
    await t.tap(toggle());
    await t.pump(const Duration(milliseconds: 300));
    expect(server.calls('PUT', '/api/admin/notification-prefs'), isEmpty);
    expect(find.text(kEmployeeOpsLocked), findsNWidgets(2), reason: 'سطره + رسالة القفل');
    await t.pump(const Duration(seconds: 3));
    await simDrain(t);
  });

  test('الحمولة: النوع «أخرى» بلا مشترك ولا وجهةٍ عامّة (لا يُفتح كرت ولا قائمة)', () {
    final n = AppNotification.fromFcmPayload(
      messageId: 'm1',
      title: 'زينب — 3 عمليّات',
      body: 'تفعيلان وتسديد · آخرها: تسديد دين 25,000 د.ع',
      data: {'type': 'employee_ops', 'employee_id': '7', 'employee_name': 'زينب', 'count': '3', 'company_admin_id': _owner},
    );
    expect(n.kind, NotificationKind.other);
    expect(NotificationRouter.extractUsername(n), isNull);
    expect(NotificationRouter.destinationFor(n.kind), isNull);
  });

  testWidgets('الموجِّه: النقرة ⇒ «سجلّ الحركات» بموظّفه؛ ملخّص السكون بلا موظّف؛ وغيره لا يُلمس', (t) async {
    final nav = GlobalKey<NavigatorState>();
    await pumpSim(t, _v, navigatorKey: nav, home: (_) => const Scaffold(body: SizedBox.shrink()));
    NotificationRouter.attach(nav);
    NotificationRouter.markReady();
    addTearDown(NotificationRouter.reset);

    final n = AppNotification.fromFcmPayload(
      messageId: 'm2',
      title: 'زينب — تفعيل',
      body: 'تفعيل نقدي — FTTH 50',
      data: {'type': 'employee_ops', 'employee_id': '7', 'employee_name': 'زينب', 'count': '1'},
    );
    final h = NotificationRouter.handle(n);
    await settle(t);
    expect(find.byType(ActivityLogV2Screen), findsOneWidget);
    expect(t.widget<ActivityLogV2Screen>(find.byType(ActivityLogV2Screen)).push?.employeeId, '7');
    nav.currentState!.popUntil((r) => r.isFirst);
    await settle(t);
    await h;

    final d = openEmployeeOpsPush(nav.currentState!, {'type': 'employee_ops', 'employee_id': '', 'digest': 'quiet'});
    await settle(t);
    final s = t.widget<ActivityLogV2Screen>(find.byType(ActivityLogV2Screen));
    expect(s.push, isNotNull);
    expect(s.push!.employeeId, isNull, reason: 'الملخّص لكلّ الموظّفين');
    nav.currentState!.popUntil((r) => r.isFirst);
    await settle(t);
    expect(await d, isTrue);

    final bad = openEmployeeOpsPush(nav.currentState!, {'type': 'employee_ops', 'employee_id': '../7'});
    await settle(t);
    expect(t.widget<ActivityLogV2Screen>(find.byType(ActivityLogV2Screen)).push!.employeeId, isNull,
        reason: 'رقمٌ غير صالح لا يصير فلتراً');
    nav.currentState!.popUntil((r) => r.isFirst);
    await settle(t);
    await bad;

    expect(await openEmployeeOpsPush(nav.currentState!, {'type': 'agent_alert'}), isFalse);
    expect(find.byType(ActivityLogV2Screen), findsNothing);
    await simDrain(t);
  });
}
