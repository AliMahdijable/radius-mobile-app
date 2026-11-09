import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/tickets_api.dart';
import 'package:rad_mysvcs/screens/tickets/ticket_thread_screen.dart';
import 'package:rad_mysvcs/services/permissions_service.dart';
import 'package:rad_mysvcs/services/provider_service.dart';

import 'sim_el/sim_harness.dart';

/// محادثة التذكرة (مراجعة 3.0.18+179): قراءةٌ بدأت قبل ردٍّ أو تغيير حالةٍ نجح لا تمحوه حين تصل بعده — الدوريّة (٣٠ث) تُسقَط،
/// والأولى/اليدويّة تضمّ رسائلها بالمعرّف وتُبقي حال التذكرة من ردّ الكتابة. الخادم وهميّ: قراءةٌ تُمسك لقطتها لحظة طلبها.
const _v = SimVariant(390, dark: false);

String _iso(Duration ago) => DateTime.now().toUtc().subtract(ago).toIso8601String();

Map<String, dynamic> _ticket(String status) => {
      'id': 9,
      'status': status,
      'category': 'internet',
      'subject': null,
      'subscriber': {'idx': '9', 'username': 'ali.abbas', 'name': 'علي عباس'},
      'provider': 'sas4',
      'unread': false,
      'seen_by_subscriber': true,
      'message_count': 1,
      'last_author': 'subscriber',
      'last_preview': 'النت مقطوع',
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

Map<String, dynamic> _msg(int id, String side, String body) =>
    {'id': id, 'side': side, 'author': side == 'manager' ? 'boss' : null, 'kind': 'text', 'event': null, 'body': body,
      'created_at': _iso(Duration(minutes: 30 - id))};

Map<String, dynamic> _event(int id, String event) =>
    {'id': id, 'side': 'manager', 'author': 'boss', 'kind': 'event', 'event': event, 'body': null, 'created_at': _iso(Duration.zero)};

/// خادم المحادثة: [gate] يُمسك ردّ القراءة التالية بلقطتها لحظة طلبها (أقدم ممّا يُكتب بعدها).
class _Thread {
  _Thread(SimServer s) {
    s.on('GET', '/api/v2/portal/tickets/9', (_) {
      final snap = {'success': true, 'ticket': {...current}, 'messages': [...messages]};
      final g = gate;
      gate = null;
      if (g == null) return SimReply(200, snap);
      return g.future.then((_) => SimReply(200, snap));
    });
    s.reply('GET', '/api/v2/portal/tickets/summary', 200, {'success': true, 'available': true, 'can_view': true, 'can_reply': true});
    s.on('POST', '/api/v2/portal/tickets/9/reply', (req) {
      SimReply commit() {
        final m = _msg(20, 'manager', (req.data as Map)['body'] as String);
        messages = [...messages, m];
        current = _ticket('answered');
        return SimReply(200, {'success': true, 'ticket': current, 'message': m});
      }

      final w = writeGate;
      writeGate = null;
      return w == null ? commit() : w.future.then((_) => commit());
    });
    s.on('POST', '/api/v2/portal/tickets/9/status', (req) {
      SimReply commit() {
        final st = (req.data as Map)['status'] as String;
        final e = _event(30, st);
        messages = [...messages, e];
        current = _ticket(st);
        return SimReply(200, {'success': true, 'ticket': current, 'message': e});
      }

      final w = writeGate;
      writeGate = null;
      return w == null ? commit() : w.future.then((_) => commit());
    });
  }

  Map<String, dynamic> current = _ticket('open');
  List<Map<String, dynamic>> messages = [_msg(1, 'subscriber', 'النت مقطوع من الصبح')];
  Completer<void>? gate;

  /// يُمسك الكتابة التالية (ردّاً أو حالة) **قبل** حفظها — قراءةٌ تُطلب أثناءها ترى ما قبلها.
  Completer<void>? writeGate;
}

void main() {
  late SimServer server;
  setUpAll(simSetUpAll);
  setUp(() async {
    TicketsState.reset();
    ProviderService.debugSet(null);
    PermissionsService.debugSet(isEmployee: false);
    server = await simSetUp(secure: {'auth.admin_id': 'speed:7', 'auth.admin_username': 'boss'});
    TicketThreadScreen.pollEvery = const Duration(seconds: 30);
  });
  tearDown(() {
    TicketThreadScreen.pollEvery = const Duration(seconds: 30);
    TicketsState.reset();
    ProviderService.debugSet(null);
    PermissionsService.debugReset();
  });

  Finder status(String label) => find.text(label);
  final composer = find.byKey(const ValueKey('ticket-composer'));

  testWidgets('قراءةٌ دوريّة طُلبت قبل الردّ ووصلت بعده: الردّ يبقى وحال «تمّ الردّ» لا ترجع «بانتظارك»', (t) async {
    final srv = _Thread(server);
    await pumpSim(t, _v, home: (_) => const TicketThreadScreen(ticketId: 9));
    expect(status('بانتظارك'), findsOneWidget);
    await t.enterText(composer, 'تمّ إصلاح الخطّ');
    // الدوريّة تنطلق وتُمسك لقطتها (قبل الردّ)
    final gate = srv.gate = Completer<void>();
    await t.pump(const Duration(seconds: 30));
    await t.pump();
    expect(server.calls('GET', '/api/v2/portal/tickets/9'), hasLength(2));
    // الردّ ينجح أوّلاً
    await t.tap(find.byKey(const ValueKey('ticket-send')));
    await t.pumpAndSettle();
    expect(find.text('تمّ إصلاح الخطّ'), findsOneWidget);
    expect(status('تمّ الردّ'), findsOneWidget);
    // ثمّ تصل اللقطة القديمة
    gate.complete();
    await t.pumpAndSettle();
    expect(find.text('تمّ إصلاح الخطّ'), findsOneWidget, reason: 'الردّ المُرسَل لا يختفي');
    expect(status('تمّ الردّ'), findsOneWidget, reason: 'الحال من ردّ الكتابة لا من اللقطة الأقدم');
    expect(status('بانتظارك'), findsNothing);
    // والقراءة التالية بلا كتابةٍ بينها تُطبَّق كما كانت
    await t.pump(const Duration(seconds: 30));
    await t.pumpAndSettle();
    expect(find.text('تمّ إصلاح الخطّ'), findsOneWidget);
    expect(status('تمّ الردّ'), findsOneWidget);
    expect(t.takeException(), isNull);
    await simDrain(t);
  });

  testWidgets('قراءةٌ دوريّة طُلبت قبل «إغلاق» ووصلت بعده: تبقى مغلقةً بلا حقل ردّ', (t) async {
    final srv = _Thread(server);
    await pumpSim(t, _v, home: (_) => const TicketThreadScreen(ticketId: 9));
    final gate = srv.gate = Completer<void>();
    await t.pump(const Duration(seconds: 30));
    await t.pump();
    await t.tap(find.byKey(const ValueKey('ticket-action-closed')));
    await t.pumpAndSettle();
    await t.tap(find.text('أغلق'));
    await t.pumpAndSettle();
    expect(composer, findsNothing);
    gate.complete();
    await t.pumpAndSettle();
    expect(composer, findsNothing, reason: 'المغلقة لا تعود مفتوحةً بلقطةٍ أقدم');
    expect(find.text('التذكرة مغلقة — أعد فتحها للردّ'), findsOneWidget);
    expect(find.byKey(const ValueKey('ticket-action-reopen')), findsOneWidget);
    expect(t.takeException(), isNull);
    await simDrain(t);
  });

  testWidgets('القراءة الأولى (من القائمة) تصل بعد ردٍّ نجح: رسائلها تُضمّ إلى الردّ بالمعرّف، والحال من الردّ', (t) async {
    final srv = _Thread(server);
    final gate = srv.gate = Completer<void>();
    await pumpSim(t, _v, settle: false, home: (_) => TicketThreadScreen(ticketId: 9, initial: Ticket.fromJson(_ticket('open'))));
    await t.pump(const Duration(milliseconds: 300));
    await t.enterText(composer, 'وصلنا طلبك');
    await t.tap(find.byKey(const ValueKey('ticket-send')));
    for (var i = 0; i < 5; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('وصلنا طلبك'), findsOneWidget);
    gate.complete();
    await t.pumpAndSettle();
    expect(find.text('النت مقطوع من الصبح'), findsOneWidget, reason: 'رسائل القراءة الأولى تظهر');
    expect(find.text('وصلنا طلبك'), findsOneWidget, reason: 'والردّ معها لا يُمحى');
    expect(status('تمّ الردّ'), findsOneWidget);
    expect(t.takeException(), isNull);
    await simDrain(t);
  });

  /// السحب للتحديث بدأ والكتابة جارية (مراجعة 3.0.18 الثانية): الخادم يقرأ قبل حفظها ويصل ردّه بعد ردّها — والعدّاد لم يتغيّر بعد
  /// بدء القراءة، فكانت لقطتها تُطبَّق كاملةً.
  Future<Completer<void>> pullDuring(WidgetTester t, _Thread srv) async {
    final read = srv.gate = Completer<void>();
    final before = server.calls('GET', '/api/v2/portal/tickets/9').length;
    unawaited(t.state<RefreshIndicatorState>(find.byType(RefreshIndicator)).show());
    for (var i = 0; i < 6; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(server.calls('GET', '/api/v2/portal/tickets/9'), hasLength(before + 1), reason: 'السحب قرأ والكتابة جارية');
    return read;
  }

  testWidgets('سحبٌ للتحديث بدأ أثناء الردّ ووصل بعده: الردّ يبقى وحال «تمّ الردّ» لا ترجع «بانتظارك»', (t) async {
    final srv = _Thread(server);
    await pumpSim(t, _v, home: (_) => const TicketThreadScreen(ticketId: 9));
    expect(status('بانتظارك'), findsOneWidget);
    await t.enterText(composer, 'تمّ إصلاح الخطّ');
    final write = srv.writeGate = Completer<void>();
    await t.tap(find.byKey(const ValueKey('ticket-send')));
    await t.pump();
    final read = await pullDuring(t, srv);
    // الردّ يُحفظ ويصل أوّلاً
    write.complete();
    await t.pump();
    await t.pump(const Duration(milliseconds: 100));
    expect(find.text('تمّ إصلاح الخطّ'), findsOneWidget);
    expect(status('تمّ الردّ'), findsOneWidget);
    // ثمّ لقطة السحب (قبل الحفظ)
    read.complete();
    await t.pumpAndSettle();
    expect(find.text('تمّ إصلاح الخطّ'), findsOneWidget, reason: 'الردّ المُرسَل لا يختفي');
    expect(find.text('النت مقطوع من الصبح'), findsOneWidget);
    expect(status('تمّ الردّ'), findsOneWidget, reason: 'الحال من ردّ الكتابة لا من اللقطة الأقدم');
    expect(status('بانتظارك'), findsNothing);
    expect(t.takeException(), isNull);
    await simDrain(t);
  });

  testWidgets('سحبٌ للتحديث بدأ أثناء «إغلاق» ووصل بعده: تبقى مغلقةً بلا حقل ردّ', (t) async {
    final srv = _Thread(server);
    await pumpSim(t, _v, home: (_) => const TicketThreadScreen(ticketId: 9));
    final write = srv.writeGate = Completer<void>();
    await t.tap(find.byKey(const ValueKey('ticket-action-closed')));
    await t.pumpAndSettle();
    await t.tap(find.text('أغلق'));
    await t.pump(const Duration(milliseconds: 600));
    final read = await pullDuring(t, srv);
    write.complete();
    await t.pump();
    await t.pump(const Duration(milliseconds: 100));
    expect(composer, findsNothing);
    read.complete();
    await t.pumpAndSettle();
    expect(composer, findsNothing, reason: 'المغلقة لا تعود مفتوحةً بلقطةٍ أقدم');
    expect(find.text('التذكرة مغلقة — أعد فتحها للردّ'), findsOneWidget);
    expect(find.byKey(const ValueKey('ticket-action-reopen')), findsOneWidget);
    expect(t.takeException(), isNull);
    await simDrain(t);
  });
}
