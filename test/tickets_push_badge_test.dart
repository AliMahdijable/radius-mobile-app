import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/big_subscribers_api.dart';
import 'package:rad_mysvcs/api/renew_requests_api.dart';
import 'package:rad_mysvcs/api/subscribers_api.dart';
import 'package:rad_mysvcs/api/tickets_api.dart';
import 'package:rad_mysvcs/models/app_notification.dart';
import 'package:rad_mysvcs/screens/tickets/ticket_thread_screen.dart';
import 'package:rad_mysvcs/screens/tickets/ticket_widgets.dart';
import 'package:rad_mysvcs/screens/top_actions.dart';
import 'package:rad_mysvcs/services/alerts_service.dart';
import 'package:rad_mysvcs/services/inbox_service.dart';
import 'package:rad_mysvcs/services/permissions_service.dart';
import 'package:rad_mysvcs/services/provider_service.dart';

import 'sim_el/sim_harness.dart';

/// «تذاكر المشتركين» بالجرس — مراجعة 3.0.18+179 الثانية:
///  ٣. نقر إشعار التذكرة (FCM أو اللافتة) يفتح المحادثة فوراً والجرس يُقرأ في الخلفيّة — كان ينتظر الملخّص ثمّ قائمتي الجرس. والحال
///     مجهول ⇒ الملخّص وحده. وقراءةٌ مُجبَرة أثناء أخرى تجري بعدها (المحادثة قرأت التذكرة ⇒ لا يبقى الجرس يعدّها بلقطةٍ أقدم).
///  ٤. رقم الجرس في الرأس: إشعار التذكرة غير المقروء في الصندوق لا يُعدّ مع تذكرته — تذكرةٌ واحدة = ١ لا ٢، وثلاث رسائل منها = ١ لا ٤؛
///     وإشعار تذكرةٍ لشركةٍ أخرى يُعدّ كأيّ إشعار.
const _v = SimVariant(390, dark: false);

const _summaryPath = '/api/v2/portal/tickets/summary';
const _listPath = '/api/v2/portal/tickets';

String _iso(Duration ago) => DateTime.now().toUtc().subtract(ago).toIso8601String();

Map<String, dynamic> _ticket(int id, String status, {String name = 'علي عباس', bool unread = false}) => {
      'id': id,
      'status': status,
      'category': 'internet',
      'subject': null,
      'subscriber': {'idx': '$id', 'username': 'user$id', 'name': name},
      'provider': 'sas4',
      'unread': unread,
      'seen_by_subscriber': true,
      'message_count': 1,
      'last_author': 'subscriber',
      'last_preview': 'النت مقطوع من الصبح',
      'last_activity_at': _iso(const Duration(minutes: 7)),
      'created_at': _iso(const Duration(hours: 1)),
      'updated_at': _iso(const Duration(minutes: 7)),
      'closed_at': ['closed', 'cancelled'].contains(status) ? _iso(const Duration(minutes: 7)) : null,
      'status_by': null,
      'status_at': null,
      'via': 'app',
      'moved': false,
      'image_count': 0,
      'can_reply': !['closed', 'cancelled'].contains(status),
      'can_reopen': ['resolved', 'closed'].contains(status),
      'actions': switch (status) {
        'open' || 'answered' => ['in_progress', 'resolved', 'closed'],
        _ => <String>[],
      },
    };

const _filters = <String, List<String>>{
  'open': ['open', 'in_progress'],
  'answered': ['answered'],
  'closed': ['resolved', 'closed', 'cancelled'],
};

Map<String, dynamic> _countsOf(List<Map<String, dynamic>> all) {
  int n(String f) => all.where((t) => _filters[f]!.contains(t['status'])).length;
  return {
    'open': n('open'),
    'answered': n('answered'),
    'closed': n('closed'),
    'unread': all.where((t) => t['unread'] == true).length,
    'total': all.length,
  };
}

/// خادم التذاكر بعقد server/tickets.js (كاختبار الجرس): الملخّص، والقائمة بفلترها، والمحادثة تُعلَّم مقروءةً لطرف الوكيل.
void _serve(SimServer server, List<Map<String, dynamic>> all) {
  server.on('GET', _summaryPath, (_) => SimReply(200, {
        'success': true,
        'available': true,
        'can_view': true,
        'can_reply': true,
        'counts': _countsOf(all),
      }));
  server.on('GET', _listPath, (req) {
    final f = req.queryParameters['filter']?.toString() ?? 'open';
    final limit = int.tryParse('${req.queryParameters['limit'] ?? 30}') ?? 30;
    final rows = all.where((t) => _filters[f]?.contains(t['status']) ?? true).toList()
      ..sort((a, b) => a['unread'] == b['unread'] ? 0 : (a['unread'] == true ? -1 : 1));
    return SimReply(200, {
      'success': true,
      'filter': f,
      'items': rows.take(limit).toList(),
      'counts': _countsOf(all),
      'has_more': rows.length > limit,
      'next_offset': rows.length > limit ? limit : null,
    });
  });
  for (final id in [6, 9]) {
    server.on('GET', '$_listPath/$id', (_) {
      final i = all.indexWhere((x) => x['id'] == id);
      all[i] = {...all[i], 'unread': false};
      return SimReply(200, {
        'success': true,
        'ticket': all[i],
        'messages': [
          {'id': 1, 'side': 'subscriber', 'kind': 'text', 'body': 'النت مقطوع من الصبح', 'created_at': _iso(const Duration(minutes: 7))},
        ],
      });
    });
  }
}

AppNotification _push(String id, int ticket, {String event = 'reply', String company = 'speed:7'}) =>
    AppNotification.fromFcmPayload(
      messageId: id,
      title: event == 'created' ? 'تذكرة جديدة من مشترك' : 'ردّ جديد على تذكرة',
      body: 'علي عباس: النت مقطوع من الصبح',
      data: {'type': 'portal_ticket', 'ticket_id': '$ticket', 'event': event, 'company_admin_id': company},
    );

void main() {
  late SimServer server;
  setUpAll(() async {
    await simSetUpAll();
    TicketThreadScreen.pollEvery = null;
  });
  setUp(() async {
    TicketsState.reset();
    TicketsState.debugResetInbox();
    TicketsState.debugSetBadgeRule(kTicketsBadgeRule);
    RenewRequestsState.reset();
    ProviderService.debugSet(null);
    PermissionsService.debugSet(isEmployee: false);
    server = await simSetUp(secure: {'auth.admin_id': 'speed:7', 'auth.admin_username': 'boss'});
  });
  tearDown(() {
    TicketsState.reset();
    RenewRequestsState.reset();
    ProviderService.debugSet(null);
    PermissionsService.debugReset();
    SubscribersApi.clearAllCaches();
    BigSubscribersApi.reset();
    AlertsService.reset();
  });

  Widget section() => const Scaffold(body: SingleChildScrollView(child: TicketInboxSection()));

  Future<void> frames(WidgetTester t, [int n = 6]) async {
    for (var i = 0; i < n; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  group('٣ — نقر إشعار التذكرة', () {
    testWidgets('الحال معروف: المحادثة تُفتح فوراً وقائمتا الجرس ممسكتان؛ والجرس يُقرأ بعد قراءتها في الخلفيّة', (t) async {
      final world = [_ticket(9, 'open', unread: true)];
      _serve(server, world);
      final nav = GlobalKey<NavigatorState>();
      await pumpSim(t, _v, navigatorKey: nav, home: (_) => section());
      expect(TicketsState.on, isTrue);
      server.hold('GET', _listPath);
      final f = openTicketPush(nav.currentState!, {'type': 'portal_ticket', 'ticket_id': '9', 'event': 'reply'});
      await frames(t);
      expect(find.byType(TicketThreadScreen), findsOneWidget, reason: 'لا انتظار لقائمتي الجرس');
      expect(find.text('النت مقطوع من الصبح'), findsWidgets, reason: 'المحادثة قُرئت');
      // الجرس يُقرأ في الخلفيّة بعد قراءة المحادثة (التي علّمتها مقروءة)
      server.release('GET', _listPath);
      await t.pumpAndSettle();
      expect(TicketsState.gate.value!.counts!.unread, 0);
      expect(TicketsState.bell.value.items.single.unread, isFalse);
      expect(TicketsState.bellBadge, 1, reason: 'قُرئت وما زالت بانتظارك');
      nav.currentState!.pop();
      await t.pumpAndSettle();
      expect(await f, true);
      expect(t.takeException(), isNull);
      await simDrain(t);
    });

    testWidgets('الحال مجهول: الملخّص وحده ثمّ المحادثة — وقائمتا الجرس تكملان بعده في الخلفيّة', (t) async {
      final world = [_ticket(9, 'open', unread: true)];
      _serve(server, world);
      final nav = GlobalKey<NavigatorState>();
      await pumpSim(t, _v, navigatorKey: nav, home: (_) => const Scaffold(body: SizedBox()));
      expect(TicketsState.gate.value, isNull);
      server.hold('GET', _listPath);
      final f = openTicketPush(nav.currentState!, {'type': 'portal_ticket', 'ticket_id': '9', 'event': 'created'});
      await frames(t);
      expect(server.calls('GET', _summaryPath), isNotEmpty);
      expect(server.calls('GET', _listPath), isNotEmpty, reason: 'قائمة الجرس طُلبت وهي ممسكة');
      expect(find.byType(TicketThreadScreen), findsOneWidget, reason: 'الملخّص قرّر — لا انتظار للقائمة');
      server.release('GET', _listPath);
      await t.pumpAndSettle();
      expect(TicketsState.bell.value.items.map((x) => x.id).toList(), [9]);
      nav.currentState!.pop();
      await t.pumpAndSettle();
      expect(await f, true);
      await simDrain(t);
    });

    testWidgets('قراءةٌ مُجبَرة أثناء أخرى تجري بعدها: المحادثة قرأت الملغاة ⇒ لا يبقى الجرس يعدّها بلقطةٍ أقدم', (t) async {
      final world = [_ticket(6, 'cancelled', unread: true)];
      _serve(server, world);
      final nav = GlobalKey<NavigatorState>();
      await pumpSim(t, _v, navigatorKey: nav, home: (_) => section());
      expect(TicketsState.bellBadge, 1, reason: 'الملغاة غير المقروءة تنتظرك');
      final summaries = server.calls('GET', _summaryPath).length;
      // قراءةٌ جارية (رجوعٌ للتطبيق مثلاً) — ملخّصها قبل أن تُقرأ التذكرة، وقائمتها ممسكة
      server.hold('GET', _listPath);
      unawaited(TicketsState.ensureFresh(force: true));
      await frames(t, 2);
      final f = openTicketPush(nav.currentState!, {'type': 'portal_ticket', 'ticket_id': '6', 'event': 'cancelled'});
      await frames(t);
      expect(find.byType(TicketThreadScreen), findsOneWidget);
      server.release('GET', _listPath);
      await t.pumpAndSettle();
      expect(server.calls('GET', _summaryPath).length, summaries + 2, reason: 'الجارية ثمّ قراءةٌ بعدها لما طلبته المحادثة');
      expect(TicketsState.gate.value!.counts!.unread, 0);
      expect(TicketsState.bellBadge, 0, reason: 'قُرئت الملغاة — لا تنتظرك');
      nav.currentState!.pop();
      await t.pumpAndSettle();
      expect(await f, true);
      await simDrain(t);
    });
  });

  group('٤ — رقم الجرس في الرأس', () {
    Finder badge(String n) => find.descendant(of: find.byKey(const ValueKey('top-actions-notifications')), matching: find.text(n));
    Widget header() => Scaffold(appBar: AppBar(actions: const [TopActions()]));

    testWidgets('تذكرةٌ جديدة وإشعارها في الصندوق ⇒ ١ لا ٢؛ وثلاث رسائل منها ⇒ ١ لا ٤؛ وتذكرة شركةٍ أخرى تُعدّ', (t) async {
      final world = <Map<String, dynamic>>[];
      _serve(server, world);
      await t.runAsync(InboxService.clear);
      addTearDown(() => t.runAsync(InboxService.clear));
      await pumpSim(t, _v, home: (_) => header());
      expect(find.descendant(of: find.byKey(const ValueKey('top-actions-notifications')), matching: find.byType(Text)), findsNothing);
      TicketsState.onInboxChanged(); // أوّل قراءةٍ للصندوق
      // المشترك يفتح تذكرة والتطبيق مفتوح: إشعارها يُحفظ غير مقروء (اللافتة تُغلق نفسها بلا نقر)
      world.add(_ticket(9, 'open', unread: true));
      await t.runAsync(() => InboxService.add(_push('tk-9a', 9, event: 'created')));
      await t.pump();
      expect(badge('1'), findsOneWidget, reason: 'الإشعار يُعدّ حتى تُقرأ أرقام التذاكر — لا تأخير');
      TicketsState.onInboxChanged();
      await t.pumpAndSettle();
      expect(TicketsState.bellBadge, 1);
      expect(badge('1'), findsOneWidget, reason: 'تذكرةٌ واحدة = ١ (إشعارها لا يُعدّ معها)');
      expect(badge('2'), findsNothing);
      // ردّان آخران من المشترك على التذكرة نفسها
      await t.runAsync(() => InboxService.add(_push('tk-9b', 9)));
      await t.runAsync(() => InboxService.add(_push('tk-9c', 9)));
      TicketsState.onInboxChanged();
      await t.pumpAndSettle();
      expect(InboxService.unreadCount, 3);
      expect(badge('1'), findsOneWidget, reason: 'ثلاث رسائل من تذكرةٍ واحدة = ١ لا ٤');
      // «إشعارات كلّ شركاتي»: تذكرةٌ لشركةٍ أخرى — الجرس لتذاكر المفتوحة وحدها، فإشعارها يُعدّ
      await t.runAsync(() => InboxService.add(_push('tk-77', 77, event: 'created', company: 'jt:6836')));
      await t.pump();
      expect(badge('2'), findsOneWidget);
      // الموظّف بلا «التذاكر — العرض»: لا جرس تذاكر ⇒ إشعاراتها كأيّ إشعار
      PermissionsService.debugSet(isEmployee: true, permissions: const {'subscribers.view': true});
      await t.pumpWidget(const SizedBox());
      await pumpSim(t, _v, home: (_) => header());
      expect(TicketsState.inBell, isFalse);
      expect(badge('4'), findsOneWidget, reason: 'الإشعارات الأربعة غير المقروءة');
      await simDrain(t);
    });
  });
}
