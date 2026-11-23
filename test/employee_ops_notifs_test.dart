import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:rad_mysvcs/api/notifications_api.dart';
import 'package:rad_mysvcs/core/widgets/design_sheet.dart';
import 'package:rad_mysvcs/models/app_notification.dart';
import 'package:rad_mysvcs/screens/my_alerts/employee_ops_pick_sheet.dart';
import 'package:rad_mysvcs/screens/notifications_settings_screen.dart';
import 'package:rad_mysvcs/screens/reports/v2/activity_log_v2_screen.dart';
import 'package:rad_mysvcs/services/notification_router.dart';
import 'package:rad_mysvcs/services/permissions_service.dart';
import 'package:rad_mysvcs/services/provider_service.dart';

import 'sim_el/sim_harness.dart';

/// «عمليّات الموظّفين» (المالك ٢٣ نوفمبر: «اي موظف يسوي عمليه يذهب اشعار للمدير بهاي العمليه» — الخادم server/employeeOps.js):
/// مفتاح push_employee_ops في «إشعاراتي» حين يتيحه الخادم (employee_ops.available)، مقفلٌ للموظّف (can_edit=false) كالموقع،
/// والحفظ لا يُسقط الإتاحة (ردّ PUT بلا employee_ops) ولا يرسل المفتاح من شاشةٍ لم تعرضه؛ ونقر الإشعار ⇒ «سجلّ الحركات» بفلتره.
/// «من موظّفيك» (المالك ٢٣ نوفمبر: «يحدد اكثر من واحد او واحد مستقل او الكل» — الخادم 10b5bfb): صفٌّ تحت المفتاح لصاحب الصفحة
/// وورقته (الكلّ / موظّفون أختارهم)، ويُحفظ بطلبه وحده PUT {employeeOpsIds}.
const _v = SimVariant(390, dark: false);
const _owner = 'supernet:12';

const _staff = [
  {'id': 7, 'name': 'زينب'},
  {'id': 9, 'name': 'علي حسين'},
  {'id': 12, 'name': 'نور الهدى عبد الرحمن الموسوي'},
];

Map<String, Object?> _prefs({Object? push = true, Object? ids}) => {
      'push_near_expiry': true,
      'push_expired_today': true,
      'push_manager_debt': true,
      'quiet_hours_enabled': true,
      'quiet_hours_start': '23:00:00',
      'quiet_hours_end': '07:00:00',
      if (push != null) 'push_employee_ops': push,
      'employee_ops_ids': ids,
    };

Map<String, Object?> _get({bool? available = true, bool canEdit = true, Object? push = true, Object? ids, Object? employees = _staff}) => {
      'success': true,
      'prefs': _prefs(push: push, ids: ids),
      if (available != null)
        'employee_ops': {
          'available': available,
          'can_edit': canEdit,
          if (canEdit && employees != null) 'employees': employees,
        },
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
    // شجرةٌ فارغة أوّلاً: الفتح الثاني بالنوع نفسه يعيد استعمال الحالة القديمة بلا تحميلٍ جديد (فتمرّ التوقّعات زوراً)
    await t.pumpWidget(const SizedBox.shrink());
    await t.pump();
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

  // ═══════════════ «من موظّفيك» ═══════════════

  test('من موظّفيك — القراءة: [9,7,7] ⇒ [7,9]، والغائب/الفارغ/التالف ⇒ null (الكلّ)؛ والموظّفون بأسمائهم بلا التالف', () {
    final p = NotificationPrefs.fromJson(_prefs(ids: [9, '7', 7, 0, 'x']), employeeOps: {
      'available': true,
      'employees': [
        ..._staff,
        {'id': 'x', 'name': 'بلا رقم'},
        {'id': 15, 'name': '  '},
        'ليس كائناً',
      ],
    });
    expect(p.employeeOpsIds, [7, 9]);
    expect([for (final e in p.employeeOpsEmployees!) '${e.id}:${e.name}'], ['7:زينب', '9:علي حسين', '12:نور الهدى عبد الرحمن الموسوي']);
    for (final v in [null, <int>[], 'x', 7]) {
      expect(NotificationPrefs.fromJson(_prefs(ids: v)).employeeOpsIds, isNull, reason: '$v');
    }
    expect(NotificationPrefs.fromJson(_prefs()).employeeOpsEmployees, isNull, reason: 'لم تصل القائمة');
    expect(p.copyWith(quietHoursEnabled: false).employeeOpsIds, [7, 9], reason: 'copyWith يحمل الاختيار');
    expect(p.copyWith(quietHoursEnabled: false).employeeOpsEmployees, hasLength(3));
    expect(p.withEmployeeOpsIds(null).employeeOpsIds, isNull);
    expect(p.withEmployeeOpsIds(const []).employeeOpsIds, isNull, reason: '[] = الكلّ');
    expect(p.withEmployeeOpsIds(const [12, 7, 12]).employeeOpsIds, [7, 12]);
    expect(p.withEmployeeOpsIds(const [7]).employeeOpsEmployees, hasLength(3), reason: 'القائمة باقية');
  });

  test('من موظّفيك — نصّ الصفّ: الكلّ، الاسم، موظّفان، 3 موظّفين، 11 موظّفاً، والمحذوفون', () {
    final staff = [for (var i = 1; i <= 12; i++) EmployeeOpsPerson(i, 'م$i')];
    expect(employeeOpsPickText(null, staff), 'كلّ الموظّفين');
    expect(employeeOpsPickText(const [3], staff), 'م3');
    expect(employeeOpsPickText(const [3, 4], staff), 'موظّفان');
    expect(employeeOpsPickText(const [1, 2, 3], staff), '3 موظّفين');
    expect(employeeOpsPickText(const [1, 2, 3, 4, 5, 6, 7, 8, 9, 10], staff), '10 موظّفين');
    expect(employeeOpsPickText(const [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11], staff), '11 موظّفاً');
    expect(employeeOpsPickText(const [99], staff), 'المختارون لم يعودوا موجودين');
    expect(employeeOpsPickText(const [3, 99], staff), 'م3', reason: 'المحذوف لا يُعدّ');
  });

  test('من موظّفيك — الحفظ بطلبه وحده: {employeeOpsIds: [..]} أو null للكلّ؛ والرفض برسالة الخادم؛ والحفظ العامّ لا يرسله', () async {
    server.reply('PUT', '/api/admin/notification-prefs', 200, {'success': true, 'prefs': _prefs(ids: [7])});
    final r = await NotificationsApi.saveEmployeeOpsIds(const [7]);
    expect(lastPut(), {'employeeOpsIds': [7]}, reason: 'الاختيار وحده — لا يكتب فوق بقيّة الإعدادات');
    expect(r.ok, isTrue);
    expect(r.ids, [7]);

    server.reply('PUT', '/api/admin/notification-prefs', 200, {'success': true, 'prefs': _prefs()});
    final all = await NotificationsApi.saveEmployeeOpsIds(null);
    expect(lastPut().containsKey('employeeOpsIds') && lastPut()['employeeOpsIds'] == null, isTrue);
    expect((all.ok, all.ids), (true, null));
    await NotificationsApi.saveEmployeeOpsIds(const []);
    expect(lastPut()['employeeOpsIds'], isNull, reason: '[] يُرسل null = الكلّ');

    server.reply('PUT', '/api/admin/notification-prefs', 400,
        {'success': false, 'code': 'EMPLOYEE_NOT_FOUND', 'message': 'الموظّفون المختارون ليسوا من موظّفي هذه الصفحة'});
    final bad = await NotificationsApi.saveEmployeeOpsIds(const [99]);
    expect(bad.ok, isFalse);
    expect(bad.message, 'الموظّفون المختارون ليسوا من موظّفي هذه الصفحة');

    server.reply('PUT', '/api/admin/notification-prefs', 200, {'success': true, 'prefs': _prefs(ids: [9])});
    final base = NotificationPrefs.fromJson(_prefs(ids: [9]), employeeOps: {'available': true, 'can_edit': true, 'employees': _staff});
    final g = await NotificationsApi.save(base.copyWith(quietHoursEnabled: false));
    expect(lastPut().containsKey('employeeOpsIds'), isFalse, reason: 'الحفظ العامّ لا يرسل الاختيار');
    expect(g.prefs!.employeeOpsIds, [9]);
    expect(g.prefs!.employeeOpsEmployees, hasLength(3), reason: 'ردّ الحفظ بلا القائمة ⇒ من الطلب');
  });

  Finder pickRow() => find.byKey(const ValueKey('notifs-employee-ops-pick'));
  SheetFooterBar saveBar(WidgetTester t) => t.widget<SheetFooterBar>(find.byKey(const ValueKey('emp-ops-pick-save')));

  Future<void> openPick(WidgetTester t) async {
    await t.ensureVisible(pickRow());
    await t.tap(pickRow());
    await t.pumpAndSettle();
  }

  testWidgets('من موظّفيك — الصفّ «كلّ الموظّفين» ⇒ الورقة ⇒ «أختارهم» (الحفظ معطّلٌ بلا اختيار) ⇒ زينب ⇒ يُحفظ ويظهر اسمها', (t) async {
    server.reply('GET', '/api/admin/notification-prefs', 200, _get());
    server.reply('PUT', '/api/admin/notification-prefs', 200, {'success': true, 'prefs': _prefs(ids: [7])});
    await openSettings(t);
    expect(pickRow(), findsOneWidget);
    expect(find.descendant(of: pickRow(), matching: find.text('كلّ الموظّفين')), findsOneWidget);
    await openPick(t);
    expect(find.text('من موظّفيك'), findsWidgets);
    expect(saveBar(t).enabled, isTrue, reason: '«الكلّ» مختارٌ من قبل');
    await t.tap(find.byKey(const ValueKey('emp-ops-pick-some')));
    await t.pump();
    expect(saveBar(t).enabled, isFalse);
    expect(find.text('اختر موظّفاً واحداً على الأقلّ'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('emp-ops-pick-7')));
    await t.pump();
    expect(saveBar(t).enabled, isTrue);
    await t.tap(find.text('حفظ'));
    await t.pumpAndSettle();
    expect(lastPut(), {'employeeOpsIds': [7]});
    expect(find.descendant(of: pickRow(), matching: find.text('زينب')), findsOneWidget);
    await simDrain(t);
  });

  testWidgets('من موظّفيك — من موظّفَين إلى «الكلّ» ⇒ null؛ والرفض يبقي القديم ويقول السبب', (t) async {
    server.reply('GET', '/api/admin/notification-prefs', 200, _get(ids: [7, 9]));
    server.reply('PUT', '/api/admin/notification-prefs', 200, {'success': true, 'prefs': _prefs()});
    await openSettings(t);
    expect(find.descendant(of: pickRow(), matching: find.text('موظّفان')), findsOneWidget);
    await openPick(t);
    // المختاران معلَّمان من قبل
    expect(find.descendant(of: find.byKey(const ValueKey('emp-ops-pick-7')), matching: find.byIcon(LucideIcons.squareCheck)), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('emp-ops-pick-all')));
    await t.pump();
    await t.tap(find.text('حفظ'));
    await t.pumpAndSettle();
    expect(lastPut().containsKey('employeeOpsIds') && lastPut()['employeeOpsIds'] == null, isTrue);
    expect(find.descendant(of: pickRow(), matching: find.text('كلّ الموظّفين')), findsOneWidget);

    server.reply('PUT', '/api/admin/notification-prefs', 400,
        {'success': false, 'code': 'EMPLOYEE_NOT_FOUND', 'message': 'الموظّفون المختارون ليسوا من موظّفي هذه الصفحة'});
    await openPick(t);
    await t.tap(find.byKey(const ValueKey('emp-ops-pick-some')));
    await t.pump();
    await t.tap(find.byKey(const ValueKey('emp-ops-pick-12')));
    await t.pump();
    await t.tap(find.text('حفظ'));
    await t.pumpAndSettle();
    expect(find.text('الموظّفون المختارون ليسوا من موظّفي هذه الصفحة'), findsOneWidget);
    expect(find.descendant(of: pickRow(), matching: find.text('كلّ الموظّفين')), findsOneWidget, reason: 'القديم باقٍ');
    await simDrain(t);
  });

  testWidgets('من موظّفيك — بلا صفّ: للموظّف، ولقائمةٍ لم تصل أو فارغة، ولغير المتاح؛ وخافتٌ والمفتاح مطفأ', (t) async {
    for (final (name, get) in [
      ('الموظّف', _get(canEdit: false)),
      // خادمٌ أرسل القائمة للموظّف أيضاً ⇒ العميل لا يعرض الاختيار لمن لا يعدّل
      (
        'الموظّف ومعه قائمة',
        {
          'success': true,
          'prefs': _prefs(),
          'employee_ops': {'available': true, 'can_edit': false, 'employees': _staff},
        }
      ),
      ('بلا قائمة', _get(employees: null)),
      ('قائمة فارغة', _get(employees: const <Object>[])),
      ('غير متاح', _get(available: false)),
    ]) {
      if (name.startsWith('الموظّف')) PermissionsService.debugSet(isEmployee: true);
      server.reply('GET', '/api/admin/notification-prefs', 200, get);
      await openSettings(t);
      expect(pickRow(), findsNothing, reason: name);
      PermissionsService.debugSet(isEmployee: false);
      await simDrain(t);
    }
    server.reply('GET', '/api/admin/notification-prefs', 200, _get(push: false, ids: [12]));
    await openSettings(t);
    expect(pickRow(), findsOneWidget);
    final op = t.widget<Opacity>(find.ancestor(of: pickRow(), matching: find.byType(Opacity)).first);
    expect(op.opacity, lessThan(1));
    expect(find.descendant(of: pickRow(), matching: find.text('نور الهدى عبد الرحمن الموسوي')), findsOneWidget);
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
