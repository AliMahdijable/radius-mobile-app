import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/notifications_api.dart';
import 'package:rad_mysvcs/models/app_notification.dart';
import 'package:rad_mysvcs/screens/national/national_ticket_push.dart';
import 'package:rad_mysvcs/screens/national/national_tickets_screen.dart';
import 'package:rad_mysvcs/screens/notifications_settings_screen.dart';
import 'package:rad_mysvcs/services/notification_router.dart';
import 'package:rad_mysvcs/services/permissions_service.dart';
import 'package:rad_mysvcs/services/provider_service.dart';

import 'sim_el/sim_harness.dart';

/// تنبيه «تذكرة جديدة من المشروع الوطني» (الخادم server/watani/wataniTicketAlerts.js، ١ نوفمبر — المالك: «نحتاج fmc بالبرنامج
/// يقره التكتات الي دزها الشركه ع الصفحه ينرسل تنبيه للتطبيق»): النوع من data.type، والحمولة لا تفتح كرت مشترك، والنقرة تفتح
/// «التذاكر» وفوقها ورقة التذكرة — لحساب الجلسة نفسه وبصلاحيّة العرض — ومفتاح «تذاكر المشروع الوطني» في الإعدادات للوطنيّ وحده.
const _v = SimVariant(390, dark: false);
const _uuid = '0a1b2c3d-0002-4222-8333-944455556666';
const _owner = 'watani:2963757';

Map<String, String> _payload({String? ticket = _uuid, String admin = _owner}) => {
      'type': 'watani_ticket',
      'admin_id': admin,
      'count': ticket == null ? '3' : '1',
      if (ticket != null) 'ticket_id': ticket,
      if (ticket != null) 'display_id': 'cc-26112',
      'ts': '1761987600000',
    };

void main() {
  late SimServer server;

  setUpAll(simSetUpAll);

  setUp(() async {
    server = await simSetUp(secure: {'auth.admin_id': _owner, 'auth.admin_username': 'owner'});
    PermissionsService.debugSet(isEmployee: false);
    ProviderService.debugSet('watani', label: 'المشروع الوطني');
    server.reply('GET', '/api/v2/ftth/lookups', 200, {'success': true, 'data': {'can_write': false}});
  });

  tearDown(() {
    PermissionsService.debugReset();
    ProviderService.debugSet(null);
  });

  test('النوع: watani_ticket ⇒ nationalTicket ذهاباً وإياباً، والحمولة لا تحمل مشتركاً ولا وجهةً عامّة', () {
    expect(NotificationKind.fromString('watani_ticket'), NotificationKind.nationalTicket);
    expect(NotificationKind.nationalTicket.rawKey, 'watani_ticket');
    final n = AppNotification.fromFcmPayload(
      messageId: 'm1',
      title: 'تذكرة جديدة من المشروع الوطني',
      body: 'انقطاع خدمة — مريم عبد الله · FBG1',
      data: _payload(),
    );
    expect(n.kind, NotificationKind.nationalTicket);
    expect(NotificationRouter.extractUsername(n), isNull, reason: 'لا يُفتح كرت مشترك');
    expect(NotificationRouter.destinationFor(n.kind), isNull);
  });

  test('القرار: لحسابٍ آخر ⇒ رسالة، ليس الوطنيّ ⇒ رسالة، بلا صلاحيّة ⇒ قفل، وإلّا الفتح؛ والمعرّف الصالح وحده للورقة', () {
    NationalPushTarget t(Map<String, String> d, {String? cur = _owner, bool nat = true, bool view = true}) =>
        nationalPushTarget(d, currentAdminId: cur, isNational: nat, canView: view);
    expect(t({'type': 'fiber_outage'}), NationalPushTarget.notTicket);
    expect(t(_payload(), cur: 'supernet:1146'), NationalPushTarget.otherAccount);
    expect(t(_payload(), nat: false), NationalPushTarget.notNational);
    expect(t(_payload(), view: false), NationalPushTarget.noPermission);
    expect(t(_payload()), NationalPushTarget.open);
    expect(nationalPushTicketId(_payload()), _uuid);
    expect(nationalPushTicketId(_payload(ticket: null)), isNull, reason: 'ملخّص ⇒ القائمة وحدها');
    expect(nationalPushTicketId({'ticket_id': '../x'}), isNull);
  });

  testWidgets('الشاشة بمعرّف تذكرة ⇒ القائمة وفوقها ورقة التذكرة بتفاصيلها', (t) async {
    server.reply('GET', '/api/v2/ftth/tickets', 200, {
      'success': true,
      'data': [
        {'id': _uuid, 'display_id': 'cc-26112', 'source': 'call_center', 'title': 'انقطاع خدمة', 'status': 'New', 'created_at': '2026-11-01 11:57:00'},
      ],
      'total': 1,
      'page': 1,
      'page_count': 1,
    });
    server.reply('GET', '/api/v2/ftth/tickets/$_uuid', 200, {
      'success': true,
      'data': {
        'id': _uuid,
        'display_id': 'cc-26112',
        'title': 'انقطاع خدمة — ضوء أحمر',
        'status': 'New',
        'details': 'الزبون بلا خدمة منذ الصباح',
        'customer': {'id': '7', 'name': 'مريم عبد الله'},
        'zone': {'id': 'FBG1', 'name': 'FBG1'},
        'created_at': '2026-11-01 11:57:00',
        'comments': [],
        'can': {'comment': false, 'schedule': false},
      },
    });
    await pumpSim(t, _v, home: (_) => const NationalTicketsScreen(openTicketId: _uuid, openDisplayId: 'cc-26112'));
    expect(find.text('انقطاع خدمة — ضوء أحمر'), findsOneWidget, reason: 'رأس الورقة من التفاصيل');
    expect(find.text('الزبون بلا خدمة منذ الصباح'), findsOneWidget);
    expect(server.calls('GET', '/api/v2/ftth/tickets/$_uuid'), hasLength(1));
    await simDrain(t);
  });

  testWidgets('الموجِّه: نقرة التنبيه تفتح «التذاكر» وورقتها؛ ولحسابٍ آخر رسالةٌ بلا فتح', (t) async {
    server.reply('GET', '/api/v2/ftth/tickets', 200, {'success': true, 'data': [], 'total': 0, 'page': 1, 'page_count': 1});
    server.reply('GET', '/api/v2/ftth/tickets/$_uuid', 200, {
      'success': true,
      'data': {'id': _uuid, 'display_id': 'cc-26112', 'title': 'بور عالي', 'status': 'New', 'details': '', 'comments': [], 'can': {}},
    });
    final nav = GlobalKey<NavigatorState>();
    await pumpSim(t, _v, navigatorKey: nav, home: (_) => const Scaffold(body: SizedBox.shrink()));
    // الدالّة تنتظر إغلاق الشاشة (كـopenFiberPush) — النتيجة بعد الرجوع.
    final open = openNationalTicketPush(nav.currentState!, _payload());
    await t.pumpAndSettle();
    expect(find.byType(NationalTicketsScreen), findsOneWidget);
    expect(find.text('بور عالي'), findsOneWidget, reason: 'ورقة التذكرة فوق القائمة');

    nav.currentState!.popUntil((r) => r.isFirst);
    await t.pumpAndSettle();
    expect(await open, isTrue);
    final other = openNationalTicketPush(nav.currentState!, _payload(admin: 'watani:3403184'));
    await t.pumpAndSettle();
    expect(await other, isTrue);
    expect(find.byType(NationalTicketsScreen), findsNothing);
    expect(find.text(nationalPushOtherAccount), findsOneWidget);
    expect(await openNationalTicketPush(nav.currentState!, {'type': 'other'}), isFalse);
    await simDrain(t);
  });

  test('التفضيلات: push_watani_ticket غائبٌ ⇒ مفعّل، 0 ⇒ مطفأ، والحفظ يرسل pushWataniTicket', () async {
    expect(NotificationPrefs.fromJson({'push_near_expiry': 1}).pushWataniTicket, isTrue);
    expect(NotificationPrefs.fromJson({'push_watani_ticket': 0}).pushWataniTicket, isFalse);
    server.reply('PUT', '/api/admin/notification-prefs', 200, {'success': true});
    await NotificationsApi.save(NotificationPrefs.defaults.copyWith(pushWataniTicket: false));
    final body = server.calls('PUT', '/api/admin/notification-prefs').single.data as Map;
    expect(body['pushWataniTicket'], isFalse);
  });

  testWidgets('الإعدادات: «تذاكر المشروع الوطني» للوطنيّ وحده', (t) async {
    server.reply('GET', '/api/admin/notification-prefs', 200, {
      'success': true,
      'prefs': {'push_near_expiry': true, 'push_expired_today': true, 'push_manager_debt': true, 'push_watani_ticket': true},
    });
    await pumpSim(t, _v, home: (_) => const NotificationsSettingsScreen());
    expect(find.text('تذاكر المشروع الوطني'), findsOneWidget);
    expect(showNationalTicketToggle(), isTrue);
    ProviderService.debugSet('sas4');
    expect(showNationalTicketToggle(), isFalse);
    ProviderService.debugSet('ftth');
    expect(showNationalTicketToggle(), isFalse, reason: 'FTTH القديم بلا هذا التنبيه');
    await simDrain(t);
  });
}
