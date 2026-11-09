import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/employees_api.dart';
import 'package:rad_mysvcs/api/tickets_api.dart';
import 'package:rad_mysvcs/models/merged_company.dart';
import 'package:rad_mysvcs/screens/app_modules.dart';
import 'package:rad_mysvcs/screens/more_modules_screen.dart';
import 'package:rad_mysvcs/screens/tickets/ticket_thread_screen.dart';
import 'package:rad_mysvcs/screens/tickets/ticket_widgets.dart';
import 'package:rad_mysvcs/screens/tickets/tickets_screen.dart';
import 'package:rad_mysvcs/services/permissions_service.dart';
import 'package:rad_mysvcs/services/provider_service.dart';
import 'package:rad_mysvcs/widgets/merged_section.dart';

import 'sim_el/sim_harness.dart';

/// «التذاكر» بتطبيق المدير (٩ نوفمبر — الخادم server/tickets.js): النماذج، مفاتيح الموظّفين لكلّ مزوّد (لا الوطنيّ)، بطاقة «قوائم
/// أخرى» (متاحة/مقفلة/المقيَّد/الرقم)، القائمة (الفلاتر والمزيد)، المحادثة (الردّ والحالة والإغلاق بتأكيد وإعادة الفتح)، الموظّف
/// بلا الردّ، العرض وحده («كل الشركات»)، ونقر الإشعار.
const _v = SimVariant(390, dark: false);

String _iso(Duration ago) => DateTime.now().toUtc().subtract(ago).toIso8601String();

Map<String, dynamic> _ticket(int id, String status,
        {String name = 'علي عباس', String user = 'ali.abbas', bool unread = false, String category = 'internet', String preview = 'النت مقطوع'}) =>
    {
      'id': id,
      'status': status,
      'category': category,
      'subject': null,
      'subscriber': {'idx': '$id', 'username': user, 'name': name},
      'provider': 'sas4',
      'unread': unread,
      'seen_by_subscriber': true,
      'message_count': 1,
      'last_author': 'subscriber',
      'last_preview': preview,
      'last_activity_at': _iso(const Duration(minutes: 7)),
      'created_at': _iso(const Duration(minutes: 30)),
      'updated_at': _iso(const Duration(minutes: 7)),
      'closed_at': status == 'closed' ? _iso(const Duration(minutes: 1)) : null,
      'status_by': null,
      'status_at': null,
      'via': 'app',
      'can_reply': !['closed', 'cancelled'].contains(status),
      'can_reopen': ['resolved', 'closed'].contains(status),
      'actions': switch (status) {
        'open' || 'answered' => ['in_progress', 'resolved', 'closed'],
        'in_progress' => ['resolved', 'closed'],
        'resolved' => ['in_progress', 'closed'],
        _ => <String>[],
      },
    };

Map<String, dynamic> _summary({bool available = true, bool canView = true, bool canReply = true, bool scoped = false, int unread = 0}) => {
      'success': true,
      'available': available,
      'can_view': canView,
      'can_reply': canReply,
      if (scoped) 'scoped': true,
      if (available && canView) 'counts': {'open': 2, 'answered': 1, 'closed': 0, 'unread': unread, 'total': 3},
    };

Map<String, dynamic> _page(List<Map<String, dynamic>> items, {bool more = false}) => {
      'success': true,
      'filter': 'open',
      'items': items,
      'counts': {'open': 2, 'answered': 1, 'closed': 0, 'unread': items.where((x) => x['unread'] == true).length, 'total': 3},
      'has_more': more,
      'next_offset': more ? items.length : null,
    };

Map<String, dynamic> _msg(int id, String side, String body, {String? author}) =>
    {'id': id, 'side': side, 'author': author, 'kind': 'text', 'event': null, 'body': body, 'created_at': _iso(Duration(minutes: 30 - id))};

Map<String, dynamic> _event(int id, String event, {String? author = 'boss'}) =>
    {'id': id, 'side': 'manager', 'author': author, 'kind': 'event', 'event': event, 'body': null, 'created_at': _iso(const Duration(minutes: 1))};

void main() {
  setUpAll(() {
    TicketThreadScreen.pollEvery = null;
  });

  test('النماذج: التذكرة والرسالة والأعداد والوصول', () {
    final t = Ticket.fromJson(_ticket(7, 'open', unread: true))!;
    expect([t.id, t.status, t.category, t.subscriber.title, t.unread, t.canReply, t.canReopen], [7, 'open', 'internet', 'علي عباس', true, true, false]);
    expect(t.actions, ['in_progress', 'resolved', 'closed']);
    expect(t.waitingForAgent, true);
    expect(Ticket.fromJson(_ticket(8, 'closed', name: ''))!.subscriber.title, 'ali.abbas', reason: 'بلا اسم ⇒ اليوزر');
    expect(Ticket.fromJson({'id': 1}), isNull);
    final m = TicketMessage.fromJson(_msg(3, 'employee', 'جاري الفحص', author: 'emp41'))!;
    expect([m.fromSubscriber, m.isEvent, m.author, m.body], [false, false, 'emp41', 'جاري الفحص']);
    expect(TicketMessage.fromJson(_event(4, 'closed'))!.isEvent, true);
    final c = TicketCounts.fromJson({'open': 2, 'answered': 1, 'closed': 5, 'unread': 1, 'total': 8});
    expect([c.of(TicketFilter.open), c.of(TicketFilter.answered), c.of(TicketFilter.closed), c.of(TicketFilter.all)], [2, 1, 5, 8]);
    final a = TicketsAccess.fromJson(_summary(scoped: true, canView: false, canReply: false));
    expect([a.available, a.canView, a.scoped, a.on, a.counts], [true, false, true, false, null]);
    expect(ticketCategoryLabel('device'), 'الراوتر والجهاز');
    expect(ticketCategoryLabel('zzz'), 'أخرى');
    expect(ticketStatusMeta('open').label, 'بانتظارك');
    expect(ticketStatusMeta('cancelled').label, 'ألغاها المشترك');
  });

  test('«كل الشركات»: القسم قراءةٌ موجَّهة بمساره، والوطنيّ لا يخدمه', () {
    final w = TicketsScreen.mergedPage() as MergedSection;
    expect(w.readOnly, true, reason: 'الردّ والحالة من صفحة الشركة');
    expect(w.prefixes, ['/api/v2/portal/tickets']);
    MergedCompany co(String code, MergedProvider p) => MergedCompany(
          key: 'c0000000000a1', code: code, username: 'u', name: code, provider: p, colorIndex: 0, adminId: '$code:1', ns: code,
          currency: 'IQD', home: false, status: MergedStatus.ok, index: 0);
    expect(w.serves!(co('speed', MergedProvider.sas4)), true);
    expect(w.serves!(co('earthlink', MergedProvider.earthlink)), true);
    expect(w.serves!(co('nabd', MergedProvider.kit)), true);
    expect(w.serves!(co('watani', MergedProvider.kit)), false);
    expect(w.serves!(co('ftth-iq', MergedProvider.ftth)), false);
  });

  group('المزوّدون ومفاتيح الموظّفين', () {
    tearDown(() {
      ProviderService.debugSet(null);
      PermissionsService.debugReset();
    });

    test('ايرث لنك وفايبر اكس والمُضافة يعرضون مفتاحي التذاكر لموظّفيهم، والوطنيّ لا؛ و«موظّف عام» بلاهما', () {
      PermissionsService.debugSet(isEmployee: true);
      for (final p in ['earthlink', 'fiberx', 'nabd']) {
        ProviderService.debugSet(p);
        expect(ElEmployeePerms.keys, containsAll(ElEmployeePerms.ticketKeys), reason: p);
        expect(TicketsApi.servedByProvider, true, reason: p);
      }
      for (final p in ElEmployeePerms.presets) {
        expect(p.keys.toSet().intersection(ElEmployeePerms.ticketKeys), isEmpty, reason: '${p.id}: تُمنح وحدها');
      }
      ProviderService.debugSet('watani', label: 'المشروع الوطني');
      expect(ElEmployeePerms.keys.intersection(ElEmployeePerms.ticketKeys), isEmpty, reason: 'الوطنيّ بلا تذاكر');
      expect(TicketsApi.servedByProvider, false);
      ProviderService.debugSet('ftth');
      expect(TicketsApi.servedByProvider, false);
      ProviderService.debugSet(null);
      expect(TicketsApi.servedByProvider, true, reason: 'SAS4');
    });
  });

  group('الواجهة', () {
    late SimServer server;
    setUpAll(simSetUpAll);
    setUp(() async {
      TicketsState.reset();
      TicketsState.debugResetInbox();
      ProviderService.debugSet(null);
      PermissionsService.debugSet(isEmployee: false);
      server = await simSetUp(secure: {'auth.admin_id': 'speed:7', 'auth.admin_username': 'boss'});
    });
    tearDown(() {
      TicketsState.reset();
      ProviderService.debugSet(null);
      PermissionsService.debugReset();
    });

    testWidgets('«قوائم أخرى»: البطاقة حين يقول الخادم «متاحة» وحده، برقم غير المقروءة؛ مقفلةٌ للموظّف بلا العرض، وبسببها للمقيَّد؛ والوطنيّ بلا بطاقة',
        (t) async {
      await pumpSim(t, _v, home: (_) => const Scaffold(body: SizedBox()));
      AppModule? card() {
        for (final m in buildAppModules()) {
          if (m.id == 'tickets') return m;
        }
        return null;
      }

      TicketsState.debugSet(null);
      expect(card(), isNull, reason: 'لم يُعرف بعد');
      TicketsState.debugSet(TicketsAccess.off);
      expect(card(), isNull, reason: 'غير متاحة لحسابه');
      TicketsState.debugSet(TicketsAccess.fromJson(_summary(unread: 3)));
      final c = card()!;
      expect([c.locked, c.unavailable, c.badge, c.group], [false, null, 3, AppModuleGroup.comms]);
      expect(c.subtitle, contains('3'));
      PermissionsService.debugSet(isEmployee: true, permissions: {'subscribers.view': true});
      TicketsState.debugSet(TicketsAccess.fromJson(_summary(canView: false, canReply: false)));
      expect(card()!.locked, true, reason: 'بمكانها مقفلة لا مخفيّة');
      expect(card()!.badge, 0, reason: 'المقفل بلا رقم');
      TicketsState.debugSet(TicketsAccess.fromJson(_summary(canView: false, canReply: false, scoped: true)));
      expect(card()!.unavailable, 'لموظّفي الحساب كلّه');
      ProviderService.debugSet('earthlink');
      expect(card(), isNotNull, reason: 'موظّف ايرث لنك يراها (مفتاحها في محرّره)');
      ProviderService.debugSet('watani', label: 'المشروع الوطني');
      TicketsState.debugSet(TicketsAccess.fromJson(_summary()));
      expect(card(), isNull, reason: 'الوطنيّ بلا تذاكر');
    });

    testWidgets('«قوائم أخرى» بالرسم: الرقم بجانب البطاقة', (t) async {
      TicketsState.debugSet(TicketsAccess.fromJson(_summary(unread: 4)));
      await pumpSim(t, const SimVariant(390, dark: false), home: (_) => const MoreModulesScreen());
      await t.pump(const Duration(seconds: 1));
      expect(find.text('التذاكر', skipOffstage: false), findsOneWidget);
      expect(find.text('4 تذاكر فيها جديدٌ لم تقرأه', skipOffstage: false), findsOneWidget);
      expect(find.descendant(of: find.byKey(const ValueKey('module-badge'), skipOffstage: false), matching: find.text('4', skipOffstage: false)),
          findsOneWidget);
      await simDrain(t);
    });

    testWidgets('القائمة: التذاكر بالفلتر «بانتظارك» وأرقامها، غير المقروءة بنقطة، «تمّ الردّ» يطلب فلتره، و«عرض المزيد» بالإزاحة', (t) async {
      server.reply('GET', '/api/v2/portal/tickets/summary', 200, _summary(unread: 1));
      server.on('GET', '/api/v2/portal/tickets', (req) {
        final f = req.queryParameters['filter'];
        final off = req.queryParameters['offset'];
        if (f == 'answered') return SimReply(200, _page([_ticket(5, 'answered', name: 'سارة محمد')]));
        if (off == '2') return SimReply(200, _page([_ticket(3, 'in_progress', name: 'زيد علي')]));
        return SimReply(200, _page([_ticket(9, 'open', unread: true), _ticket(8, 'in_progress', name: 'مصطفى كريم')], more: true));
      });
      await pumpSim(t, _v, home: (_) => const TicketsScreen());
      await t.pumpAndSettle();
      expect(find.text('علي عباس'), findsOneWidget);
      expect(find.text('مصطفى كريم'), findsOneWidget);
      expect(find.byKey(const ValueKey('ticket-unread-9')), findsOneWidget);
      expect(find.byKey(const ValueKey('ticket-unread-8')), findsNothing);
      expect(find.text('بانتظارك (2)'), findsOneWidget);
      expect(find.text('تمّ الردّ (1)'), findsOneWidget);
      expect(server.calls('GET', '/api/v2/portal/tickets').first.queryParameters['filter'], 'open');
      await t.tap(find.byKey(const ValueKey('tickets-more')));
      await t.pumpAndSettle();
      expect(find.text('زيد علي'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('tickets-filter-answered')));
      await t.pumpAndSettle();
      expect(find.text('سارة محمد'), findsOneWidget);
      expect(find.text('علي عباس'), findsNothing);
      expect(t.takeException(), isNull);
      await simDrain(t);
    });

    testWidgets('الموظّف بلا «التذاكر — العرض»: «لا صلاحيّة» بمكانها بلا طلب قائمة', (t) async {
      PermissionsService.debugSet(isEmployee: true, permissions: {'subscribers.view': true});
      server.reply('GET', '/api/v2/portal/tickets/summary', 200, _summary(canView: false, canReply: false));
      await pumpSim(t, _v, home: (_) => const TicketsScreen());
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('tickets-locked')), findsOneWidget);
      expect(find.text('لا صلاحيّة'), findsOneWidget);
      expect(server.calls('GET', '/api/v2/portal/tickets'), isEmpty);
      await simDrain(t);
    });

    testWidgets('المحادثة: الرسائل والأحداث، الردّ يُرسل ويُضاف، «تمّ الحلّ» ثمّ «إغلاق» بتأكيد ثمّ «إعادة فتح»', (t) async {
      var current = _ticket(9, 'open', unread: true);
      server.on('GET', '/api/v2/portal/tickets/9', (_) => SimReply(200, {
            'success': true,
            'ticket': {...current, 'unread': false},
            'messages': [_msg(1, 'subscriber', 'النت مقطوع من الصبح'), _msg(2, 'manager', 'سنفحص الخطّ', author: 'boss'), _event(3, 'in_progress')],
          }));
      server.reply('GET', '/api/v2/portal/tickets/summary', 200, _summary());
      server.on('POST', '/api/v2/portal/tickets/9/reply', (req) {
        current = {..._ticket(9, 'answered')};
        return SimReply(200, {'success': true, 'ticket': current, 'message': _msg(20, 'manager', (req.data as Map)['body'] as String, author: 'boss')});
      });
      server.on('POST', '/api/v2/portal/tickets/9/status', (req) {
        final s = (req.data as Map)['status'] as String;
        current = _ticket(9, s);
        return SimReply(200, {'success': true, 'ticket': current, 'message': _event(30 + s.length, s)});
      });
      server.on('POST', '/api/v2/portal/tickets/9/reopen', (_) {
        current = _ticket(9, 'open');
        return SimReply(200, {'success': true, 'ticket': current, 'message': _event(50, 'reopened')});
      });
      await pumpSim(t, _v, home: (_) => const TicketThreadScreen(ticketId: 9));
      await t.pumpAndSettle();
      expect(find.text('علي عباس'), findsOneWidget, reason: 'العنوان');
      expect(find.text('النت مقطوع من الصبح'), findsOneWidget);
      expect(find.text('سنفحص الخطّ'), findsOneWidget);
      expect(find.textContaining('صارت قيد المعالجة'), findsOneWidget, reason: 'سطر الحدث بمن فعله');
      expect(find.textContaining('boss'), findsWidgets);
      expect(find.byKey(const ValueKey('ticket-action-in_progress')), findsOneWidget);
      // الردّ
      await t.enterText(find.byKey(const ValueKey('ticket-composer')), '  تمّ إصلاح الخطّ — جرّب الآن  ');
      await t.tap(find.byKey(const ValueKey('ticket-send')));
      await t.pumpAndSettle();
      expect(server.bodies('POST', '/api/v2/portal/tickets/9/reply').single, {'body': 'تمّ إصلاح الخطّ — جرّب الآن'});
      expect(find.text('تمّ إصلاح الخطّ — جرّب الآن'), findsOneWidget);
      expect(find.text('تمّ الردّ'), findsOneWidget, reason: 'الحالة كما قالها الخادم');
      // تمّ الحلّ
      await t.tap(find.byKey(const ValueKey('ticket-action-resolved')));
      await t.pumpAndSettle();
      expect(server.bodies('POST', '/api/v2/portal/tickets/9/status').single, {'status': 'resolved'});
      expect(find.byKey(const ValueKey('ticket-action-reopen')), findsOneWidget);
      // إغلاق بتأكيد
      await t.tap(find.byKey(const ValueKey('ticket-action-closed')));
      await t.pumpAndSettle();
      expect(find.text('إغلاق التذكرة؟'), findsOneWidget);
      await t.tap(find.text('أغلق'));
      await t.pumpAndSettle();
      expect(server.bodies('POST', '/api/v2/portal/tickets/9/status').last, {'status': 'closed'});
      expect(find.byKey(const ValueKey('ticket-composer')), findsNothing, reason: 'المغلقة بلا ردّ');
      expect(find.text('التذكرة مغلقة — أعد فتحها للردّ'), findsOneWidget);
      // إعادة فتح
      await t.tap(find.byKey(const ValueKey('ticket-action-reopen')));
      await t.pumpAndSettle();
      expect(server.calls('POST', '/api/v2/portal/tickets/9/reopen'), hasLength(1));
      expect(find.byKey(const ValueKey('ticket-composer')), findsOneWidget);
      expect(t.takeException(), isNull);
      await simDrain(t);
    });

    testWidgets('ردٌّ رُفض (٤٠٩ مغلقة): الرسالة تُقال والحال من الخادم (لا ردّ بعدها)', (t) async {
      server.reply('GET', '/api/v2/portal/tickets/9', 200, {'success': true, 'ticket': _ticket(9, 'open'), 'messages': [_msg(1, 'subscriber', 'مرحبا')]});
      server.reply('POST', '/api/v2/portal/tickets/9/reply', 409,
          {'success': false, 'code': 'TICKET_CLOSED_AGENT', 'message': 'التذكرة مغلقة — أعد فتحها أوّلاً', 'ticket': _ticket(9, 'closed')});
      await pumpSim(t, _v, home: (_) => const TicketThreadScreen(ticketId: 9));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const ValueKey('ticket-composer')), 'ردٌّ متأخّر');
      await t.tap(find.byKey(const ValueKey('ticket-send')));
      await t.pumpAndSettle();
      expect(find.text('التذكرة مغلقة — أعد فتحها أوّلاً'), findsOneWidget);
      expect(find.text('التذكرة مغلقة — أعد فتحها للردّ'), findsOneWidget, reason: 'الحال الجديدة من الخادم');
      await simDrain(t);
    });

    testWidgets('الموظّف بالعرض وحده: لا حقل ردّ ولا أزرار حالة، وسطرٌ يقول لماذا؛ والعرض وحده («كل الشركات») بلا صفحة مشترك', (t) async {
      PermissionsService.debugSet(isEmployee: true, permissions: {'tickets.view': true});
      server.reply('GET', '/api/v2/portal/tickets/9', 200, {'success': true, 'ticket': _ticket(9, 'open'), 'messages': [_msg(1, 'subscriber', 'مرحبا')]});
      await pumpSim(t, _v, home: (_) => const TicketThreadScreen(ticketId: 9));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('ticket-composer')), findsNothing);
      expect(find.byKey(const ValueKey('ticket-action-closed')), findsNothing);
      expect(find.textContaining('الردّ يحتاج صلاحيّة'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
      PermissionsService.debugSet(isEmployee: false);
      await pumpSim(t, _v, home: (_) => const TicketThreadScreen(ticketId: 9, viewOnly: true));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('ticket-composer')), findsNothing);
      expect(find.byKey(const ValueKey('ticket-action-closed')), findsNothing);
      expect(find.byKey(const ValueKey('ticket-open-subscriber')), findsNothing);
      expect(find.textContaining('للعرض هنا'), findsOneWidget);
      expect(server.calls('POST', '/api/v2/portal/tickets/9/reply'), isEmpty);
      await simDrain(t);
    });

    testWidgets('نقر الإشعار portal_ticket يفتح المحادثة؛ وغيره false؛ والقسم المقفل ⇒ القائمة بسببها', (t) async {
      server.reply('GET', '/api/v2/portal/tickets/summary', 200, _summary());
      server.reply('GET', '/api/v2/portal/tickets/9', 200, {'success': true, 'ticket': _ticket(9, 'open'), 'messages': [_msg(1, 'subscriber', 'النت مقطوع')]});
      final nav = GlobalKey<NavigatorState>();
      await pumpSim(t, _v, navigatorKey: nav, home: (_) => const Scaffold(body: SizedBox()));
      expect(await openTicketPush(nav.currentState!, {'type': 'renew_request'}), false);
      final f = openTicketPush(nav.currentState!, {'type': 'portal_ticket', 'ticket_id': '9', 'event': 'created'});
      await t.pumpAndSettle();
      expect(find.text('النت مقطوع'), findsOneWidget);
      nav.currentState!.pop();
      await t.pumpAndSettle();
      expect(await f, true);
      server.reply('GET', '/api/v2/portal/tickets/summary', 200, _summary(canView: false, canReply: false));
      PermissionsService.debugSet(isEmployee: true, permissions: {'subscribers.view': true});
      final g = openTicketPush(nav.currentState!, {'type': 'portal_ticket', 'ticket_id': '9'});
      await t.pumpAndSettle();
      expect(find.text('لا صلاحيّة'), findsOneWidget);
      nav.currentState!.pop();
      await t.pumpAndSettle();
      expect(await g, true);
      await simDrain(t);
    });
  });
}
