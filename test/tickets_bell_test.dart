import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/account_api.dart';
import 'package:rad_mysvcs/api/big_subscribers_api.dart';
import 'package:rad_mysvcs/api/company_route.dart';
import 'package:rad_mysvcs/api/renew_requests_api.dart';
import 'package:rad_mysvcs/api/subscribers_api.dart';
import 'package:rad_mysvcs/api/tickets_api.dart';
import 'package:rad_mysvcs/models/app_notification.dart';
import 'package:rad_mysvcs/screens/notifications/in_app_notification_banner.dart';
import 'package:rad_mysvcs/screens/notifications/inbox_screen.dart';
import 'package:rad_mysvcs/screens/tickets/ticket_thread_screen.dart';
import 'package:rad_mysvcs/screens/tickets/ticket_widgets.dart';
import 'package:rad_mysvcs/screens/tickets/tickets_screen.dart';
import 'package:rad_mysvcs/screens/top_actions.dart';
import 'package:rad_mysvcs/services/alerts_service.dart';
import 'package:rad_mysvcs/services/inbox_service.dart';
import 'package:rad_mysvcs/services/merged_mode.dart';
import 'package:rad_mysvcs/services/notification_router.dart';
import 'package:rad_mysvcs/services/permissions_service.dart';
import 'package:rad_mysvcs/services/provider_service.dart';

import 'sim_el/sim_harness.dart';

/// «تذاكر المشتركين» في جرس تطبيق المدير (٩ نوفمبر — المالك: «نعم» للتذاكر بالجرس مثل طلبات التفعيل؛ كجرس الويب 2e6f9a4):
/// قاعدة الرقم بوجهيها (سطرٌ واحد يقلبها)، ما يُعرض (غير المقروءة أوّلاً ثمّ «بانتظارك»، ٥ على الأكثر، وغير المقروءة الملغاة)، المتاح
/// وغير المتاح والوطنيّ، الموظّف بلا «التذاكر — العرض» والمقيَّد، النقر يفتح المحادثة والرجوع يقرأ الجرس، «الكلّ»، رقم الجرس في الرأس،
/// «كل الشركات» (الشركة المفتوحة وحدها ولو بقي قسمٌ موجَّهٌ لغيرها تحته)، إشعار التذكرة، صندوق الإشعارات، والرسم على ٣٢٠–٣٩٠.
///
/// لقطات المراجعة (لا تُحفظ في المستودع): `TICKETS_BELL_OUT=<dir> flutter test test/tickets_bell_test.dart`.
const _v = SimVariant(390, dark: false);

/// شركةٌ أخرى من شركات الحساب بـ«كل الشركات».
const _kOther = 'c0000000000e1';

const _summaryPath = '/api/v2/portal/tickets/summary';
const _listPath = '/api/v2/portal/tickets';

/// صورةٌ صالحة ١×١ (PNG) — Image.memory يفكّها.
final _png = base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==');

class _BytesReply extends SimReply {
  const _BytesReply(this.bytes) : super(200);
  final Uint8List bytes;

  @override
  ResponseBody toBody() => ResponseBody(Stream.value(bytes), 200, headers: {
        Headers.contentTypeHeader: ['image/jpeg'],
      });
}

String _iso(Duration ago) => DateTime.now().toUtc().subtract(ago).toIso8601String();

Map<String, dynamic> _ticket(
  int id,
  String status, {
  String name = 'علي عباس',
  String user = 'ali.abbas',
  bool unread = false,
  String category = 'internet',
  String? preview = 'النت مقطوع من الصبح',
  String author = 'subscriber',
  Duration ago = const Duration(minutes: 7),
}) =>
    {
      'id': id,
      'status': status,
      'category': category,
      'subject': null,
      'subscriber': {'idx': '$id', 'username': user, 'name': name},
      'provider': 'sas4',
      'unread': unread,
      'seen_by_subscriber': true,
      'message_count': 2,
      'last_author': author,
      'last_preview': preview,
      'last_activity_at': _iso(ago),
      'created_at': _iso(ago + const Duration(hours: 1)),
      'updated_at': _iso(ago),
      'closed_at': ['closed', 'cancelled'].contains(status) ? _iso(ago) : null,
      'status_by': null,
      'status_at': null,
      'via': 'app',
      'moved': false,
      'image_count': 0,
      'can_reply': !['closed', 'cancelled'].contains(status),
      'can_reopen': ['resolved', 'closed'].contains(status),
      'actions': switch (status) {
        'open' || 'answered' => ['in_progress', 'resolved', 'closed'],
        'in_progress' => ['resolved', 'closed'],
        'resolved' => ['in_progress', 'closed'],
        _ => <String>[],
      },
    };

const _filters = <String, List<String>>{
  'open': ['open', 'in_progress'],
  'answered': ['answered'],
  'closed': ['resolved', 'closed', 'cancelled'],
};

/// أعداد الخادم من التذاكر نفسها (countsFrom في server/tickets.js).
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

/// خادم تذاكر صغير بعقد server/tickets.js: الملخّص بأعداده، والقائمة بفلترها وحدّها مرتّبةً كالخادم (غير المقروءة أوّلاً ثمّ الأحدث
/// نشاطاً). [all] تُقرأ عند كلّ طلب — يغيّرها الاختبار ليحاكي تذكرةً جديدة أو ردّاً.
void _serve(SimServer server, List<Map<String, dynamic>> all, {bool available = true, bool canView = true, bool scoped = false}) {
  server.on('GET', _summaryPath, (_) => SimReply(200, {
        'success': true,
        'available': available,
        'can_view': canView,
        'can_reply': canView,
        if (scoped) 'scoped': true,
        if (available && canView) 'counts': _countsOf(all),
      }));
  server.on('GET', _listPath, (req) {
    final f = req.queryParameters['filter']?.toString() ?? 'open';
    final limit = int.tryParse('${req.queryParameters['limit'] ?? 30}') ?? 30;
    final rows = all.where((t) => _filters[f]?.contains(t['status']) ?? true).toList()
      ..sort((a, b) {
        if (a['unread'] != b['unread']) return a['unread'] == true ? -1 : 1;
        return (b['last_activity_at'] as String).compareTo(a['last_activity_at'] as String);
      });
    return SimReply(200, {
      'success': true,
      'filter': f,
      'items': rows.take(limit).toList(),
      'counts': _countsOf(all),
      'has_more': rows.length > limit,
      'next_offset': rows.length > limit ? limit : null,
    });
  });
}

String _sas(DateTime t) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}:00';
}

/// قائمتا الجرس الأخريان (انتهى اليوم / قريب الانتهاء) من قائمة المشتركين — بلا شبكةٍ تسقط فيُقرأ القرص.
void _serveSubscribers(SimServer server, {List<({String user, String name, Duration left})> rows = const []}) {
  final now = DateTime.now();
  server.on('GET', '/api/v2/subscribers', (req) {
    if (req.queryParameters['page'] != null) {
      return const SimReply(200, {'success': true, 'paged': false, 'total': 0, 'data': []});
    }
    return SimReply(200, {
      'success': true,
      'data': [
        for (final r in rows) {'username': r.user, 'firstname': r.name, 'lastname': '', 'expiration': _sas(now.add(r.left))},
      ],
    });
  });
  server.reply('GET', '/api/v2/online-users', 200, {'success': true, 'data': []});
}

Widget _section() => const Scaffold(body: SingleChildScrollView(padding: EdgeInsets.all(16), child: TicketInboxSection()));

/// نصٌّ يبدأ بـ[prefix] بعد نزع محارف العزل الاتّجاهيّ (isoJoin).
Finder _textStarting(String prefix) => find.byWidgetPredicate(
    (w) => w is Text && (w.data ?? '').replaceAll(RegExp('[\u2066-\u2069]'), '').startsWith(prefix),
    description: 'نصٌّ يبدأ بـ«$prefix»');

void main() {
  setUpAll(() {
    TicketThreadScreen.pollEvery = null;
  });

  group('القاعدة والترتيب', () {
    test('رقم الجرس بوجهيه — كلّ ما ينتظرك مرّةً واحدة (قرار المالك) أو غير المقروءة وحدها — والقاعدة سطرٌ واحد', () {
      expect(kTicketsBadgeRule, TicketsBadgeRule.waiting, reason: 'قرار المالك ٩ نوفمبر — كطلبات التجديد حتى تُعالَج، وكجرس الويب');
      // تذكرةٌ جديدة: غير مقروءة و«بانتظارك» معاً ⇒ تُعدّ مرّةً واحدة لا مرّتين
      const one = TicketCounts(open: 1, unread: 1, total: 1);
      expect(ticketsBadgeCount(one), 1, reason: 'غير مقروءة وبانتظارك = واحدة');
      expect(ticketsBadgeCount(one, rule: TicketsBadgeRule.unread), 1);
      // أربعٌ بانتظارك (واحدةٌ منها جديدة) + ملغاةٌ لم تُقرأ خارجها
      const c = TicketCounts(open: 4, answered: 2, closed: 9, unread: 2, total: 15);
      expect(ticketsBadgeCount(c, outside: 1), 5, reason: '«بانتظارك» + غير المقروءة خارجها — لا open + unread (٦)');
      expect(ticketsBadgeCount(c, outside: 1, rule: TicketsBadgeRule.unread), 2);
      expect(ticketsBadgeCount(const TicketCounts(answered: 3, closed: 4, total: 7)), 0, reason: '«تمّ الردّ» والمنتهية المقروءة لا تنتظرك');
      expect(ticketsBadgeLabel(1), 'تذكرةٌ بانتظارك');
      expect(ticketsBadgeLabel(2), 'تذكرتان بانتظارك');
      expect(ticketsBadgeLabel(11), '11 تذكرة بانتظارك', reason: 'تمييز العدد بالعربيّة');
      expect(ticketsBadgeLabel(1, TicketsBadgeRule.unread), 'تذكرةٌ فيها جديدٌ لم تقرأه');
      expect(ticketsBadgeLabel(3, TicketsBadgeRule.unread), '3 تذاكر فيها جديدٌ لم تقرأه');
    });

    test('ترتيب الجرس كالخادم: غير المقروءة أوّلاً ثمّ الأحدث نشاطاً؛ و«و N غيرها» ممّا لم يُعرض', () {
      final list = [
        Ticket.fromJson(_ticket(1, 'in_progress', ago: const Duration(minutes: 1)))!,
        Ticket.fromJson(_ticket(2, 'open', unread: true, ago: const Duration(hours: 3)))!,
        Ticket.fromJson(_ticket(3, 'cancelled', unread: true, ago: const Duration(minutes: 30)))!,
        Ticket.fromJson(_ticket(4, 'open', ago: const Duration(hours: 1)))!,
      ];
      expect(sortBellFirst(list).map((t) => t.id).toList(), [3, 2, 1, 4]);
      const c = TicketCounts(open: 6, unread: 3, total: 6);
      final b = TicketsBell(items: list.take(2).toList(), outside: 1);
      expect(b.waitingOf(c), 7, reason: 'ستٌّ بانتظارك + ملغاةٌ لم تُقرأ');
      expect(b.moreOf(c), 5);
      expect(TicketsBell.empty.moreOf(const TicketCounts()), 0);
    });
  });

  group('الجرس', () {
    late SimServer server;
    setUpAll(simSetUpAll);
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
      TicketsState.debugSetBadgeRule(kTicketsBadgeRule);
      RenewRequestsState.reset();
      ProviderService.debugSet(null);
      PermissionsService.debugReset();
      SubscribersApi.clearAllCaches();
      BigSubscribersApi.reset();
      AlertsService.reset();
    });

    testWidgets('متاحة وفيها ما ينتظر: «بانتظارك» كلّها (غير المقروءة أوّلاً)، والرقم كلّ ما ينتظرك مرّةً واحدة — وبالوجه الآخر غير المقروءة',
        (t) async {
      _serve(server, [
        _ticket(9, 'open', unread: true),
        _ticket(8, 'in_progress', name: 'مصطفى كريم', preview: 'سنرسل فنّيّاً اليوم', author: 'manager', ago: const Duration(minutes: 40)),
        _ticket(5, 'answered', name: 'سارة محمد', ago: const Duration(minutes: 2)),
        _ticket(4, 'closed', name: 'زيد علي'),
      ]);
      await pumpSim(t, _v, home: (_) => _section());
      final lists = server.calls('GET', _listPath);
      expect(lists, hasLength(1), reason: 'غير المقروءة كلّها في «بانتظارك» ⇒ لا نداء «المنتهية»');
      expect(lists.single.queryParameters, {'filter': 'open', 'offset': '0', 'limit': '50'}, reason: '«بانتظارك» كلّها لعدٍّ دقيق');
      expect(TicketsState.bell.value.items.map((x) => x.id).toList(), [9, 8]);
      expect(TicketsState.bellBadge, 2, reason: 'الجديدة (غير مقروءة وبانتظارك) مرّةً + قيد المعالجة — لا ٣');
      expect(find.text('تذاكر المشتركين'), findsOneWidget);
      expect(find.text('علي عباس'), findsOneWidget);
      expect(find.text('مصطفى كريم'), findsOneWidget);
      expect(find.text('سارة محمد'), findsNothing, reason: '«تمّ الردّ» لا تنتظرك');
      expect(find.text('أنت: سنرسل فنّيّاً اليوم'), findsOneWidget, reason: 'آخر ما كتبته أنت');
      expect(find.text('النت مقطوع من الصبح'), findsOneWidget);
      expect(_textStarting('انقطاع أو بطء · منذ'), findsNWidgets(2), reason: 'النوع مع الوقت في سطرٍ واحد');
      expect(find.byKey(const ValueKey('ticket-unread-9')), findsOneWidget);
      expect(find.byKey(const ValueKey('ticket-unread-8')), findsNothing);
      expect(find.descendant(of: find.byKey(const ValueKey('tickets-inbox-count')), matching: find.text('2')), findsOneWidget,
          reason: 'رأس القسم بالرقم نفسه = ما يعرضه');
      expect(find.byKey(const ValueKey('tickets-inbox-more')), findsNothing);
      expect(find.text('الكلّ'), findsOneWidget);
      // الوجه الآخر: غير المقروءة وحدها
      TicketsState.debugSetBadgeRule(TicketsBadgeRule.unread);
      expect(TicketsState.bellBadge, 1);
      await t.pumpWidget(const SizedBox());
      await pumpSim(t, _v, home: (_) => _section());
      expect(find.descendant(of: find.byKey(const ValueKey('tickets-inbox-count')), matching: find.text('1')), findsOneWidget);
      expect(find.text('مصطفى كريم'), findsOneWidget, reason: 'القسم يعرض ما ينتظر أيّاً كانت قاعدة الرقم');
      expect(server.calls('GET', _listPath), hasLength(1), reason: 'إعادة الرسم لا تطلب ما لم تنتهِ مهلته');
      expect(t.takeException(), isNull);
      await simDrain(t);
    });

    testWidgets('غير المقروءة خارج «بانتظارك» (ألغاها المشترك) تُجلب من «المنتهية» وتُعرض أوّلاً وتُعدّ مرّة؛ وأكثر من خمسٍ ⇒ «و N غيرها…»',
        (t) async {
      final world = [
        _ticket(7, 'in_progress', name: 'مصطفى كريم', ago: const Duration(hours: 2)),
        _ticket(6, 'cancelled', unread: true, name: 'زيد علي', ago: const Duration(minutes: 10)),
        _ticket(3, 'closed', name: 'سارة محمد', ago: const Duration(days: 1)),
      ];
      _serve(server, world);
      await pumpSim(t, _v, home: (_) => _section());
      expect(server.calls('GET', _listPath).map((r) => r.queryParameters['filter']).toList(), ['open', 'closed']);
      expect(TicketsState.bell.value.items.map((x) => x.id).toList(), [6, 7]);
      expect(TicketsState.bell.value.outside, 1);
      expect(TicketsState.bellWaiting, 2);
      expect(find.text('زيد علي'), findsOneWidget);
      expect(find.text('ألغاها المشترك'), findsOneWidget);
      expect(find.byKey(const ValueKey('ticket-unread-6')), findsOneWidget);
      expect(find.text('سارة محمد'), findsNothing, reason: 'المنتهية المقروءة لا تنتظرك');
      expect(TicketsState.bellBadge, 2, reason: 'قيد المعالجة + الملغاة التي لم تُقرأ');
      expect(find.descendant(of: find.byKey(const ValueKey('tickets-inbox-count')), matching: find.text('2')), findsOneWidget);
      TicketsState.debugSetBadgeRule(TicketsBadgeRule.unread);
      expect(TicketsState.bellBadge, 1, reason: 'الوجه الآخر: الملغاة وحدها غير مقروءة');
      TicketsState.debugSetBadgeRule(kTicketsBadgeRule);
      // ستّ جديدةٌ غير مقروءة + الملغاة: سبعٌ تنتظرك (كلٌّ مرّة)، خمسٌ معروضة و«و N غيرها…» بالباقي
      world
        ..clear()
        ..addAll([
          for (var i = 0; i < 6; i++) _ticket(20 + i, 'open', unread: true, name: 'مشترك ${i + 1}', ago: Duration(minutes: 5 + i)),
          _ticket(6, 'cancelled', unread: true, name: 'زيد علي'),
        ]);
      server.requests.clear();
      await t.runAsync(() => TicketsState.ensureFresh(force: true));
      await t.pumpAndSettle();
      expect(server.calls('GET', _listPath).map((r) => r.queryParameters['filter']).toList(), ['open', 'closed']);
      expect(TicketsState.bell.value.items, hasLength(TicketsState.bellMax));
      expect(TicketsState.bellBadge, 7, reason: 'ستٌّ بانتظارك + الملغاة — لا open + unread (١٣)');
      expect(find.text('و2 غيرها…'), findsOneWidget, reason: 'سبعٌ تنتظرك وخمسٌ معروضة');
      expect(find.descendant(of: find.byKey(const ValueKey('tickets-inbox-count')), matching: find.text('7')), findsOneWidget);
      expect(t.takeException(), isNull);
      await simDrain(t);
    });

    testWidgets('لا شيء ينتظر: الملخّص وحده (بلا نداء قائمة) ولا قسم ولا رقم', (t) async {
      _serve(server, [
        _ticket(5, 'answered', name: 'سارة محمد'),
        _ticket(4, 'closed', name: 'زيد علي'),
      ]);
      await pumpSim(t, _v, home: (_) => _section());
      expect(server.calls('GET', _summaryPath), hasLength(1));
      expect(server.calls('GET', _listPath), isEmpty);
      expect(TicketsState.inBell, true);
      expect(TicketsState.bellBadge, 0);
      expect(find.text('تذاكر المشتركين'), findsNothing);
      await simDrain(t);
    });

    testWidgets('قائمة الجرس تعذّرت: الرقم من الملخّص، والسؤال التالي لا يُحبس بتبريد الفشل، وتعود القائمة مع أوّل قراءةٍ تنجح', (t) async {
      final world = [_ticket(9, 'open', unread: true)];
      _serve(server, world);
      server.reply('GET', _listPath, 500, {'success': false, 'message': 'تعذّر'});
      await pumpSim(t, _v, home: (_) => _section());
      expect(TicketsState.bellBadge, 1, reason: 'الرقم من الملخّص');
      expect(TicketsState.bell.value.items, isEmpty);
      expect(find.text('تذاكر المشتركين'), findsNothing);
      // تغيّر الحال (الموظّف فقد القسم مثلاً): السؤال المُجبَر يقرأ الملخّص فوراً — تعذّر القائمة لا يحبسه
      final before = server.calls('GET', _summaryPath).length;
      _serve(server, world, canView: false);
      await t.runAsync(() => TicketsState.ensureFresh(force: true));
      expect(server.calls('GET', _summaryPath).length, before + 1);
      expect(TicketsState.inBell, false);
      // عادت القائمة
      _serve(server, world);
      await t.runAsync(() => TicketsState.ensureFresh(force: true));
      await t.pumpAndSettle();
      expect(TicketsState.bell.value.items.map((x) => x.id).toList(), [9]);
      expect(find.text('علي عباس'), findsOneWidget);
      await simDrain(t);
    });

    testWidgets('غير متاحةٍ لحسابه، أو الوطنيّ: لا قائمة ولا رقم ولا قسم', (t) async {
      _serve(server, [_ticket(9, 'open', unread: true)], available: false);
      await pumpSim(t, _v, home: (_) => _section());
      expect(server.calls('GET', _summaryPath), hasLength(1));
      expect(server.calls('GET', _listPath), isEmpty);
      expect([TicketsState.on, TicketsState.inBell, TicketsState.bellBadge], [false, false, 0]);
      expect(find.text('تذاكر المشتركين'), findsNothing);
      await t.pumpWidget(const SizedBox());
      TicketsState.reset();
      server.requests.clear();
      _serve(server, [_ticket(9, 'open', unread: true)]);
      ProviderService.debugSet('watani', label: 'المشروع الوطني');
      await pumpSim(t, _v, home: (_) => _section());
      expect(server.requests.where((r) => r.path.startsWith(_listPath)), isEmpty, reason: 'الوطنيّ بلا تذاكر ولا سؤال');
      expect(find.text('تذاكر المشتركين'), findsNothing);
      await simDrain(t);
    });

    testWidgets('الموظّف بلا «التذاكر — العرض»: لا شيء بالجرس ولا طلب قائمة (ولو قال الخادم غير ذلك)؛ والمقيَّد كذلك؛ وبالصلاحيّة يراها',
        (t) async {
      final world = [_ticket(9, 'open', unread: true)];
      Future<void> fresh(Map<String, bool> perms, {bool canView = true, bool scoped = false}) async {
        await t.pumpWidget(const SizedBox());
        TicketsState.reset();
        server.requests.clear();
        PermissionsService.debugSet(isEmployee: true, permissions: perms);
        _serve(server, world, canView: canView, scoped: scoped);
        await pumpSim(t, _v, home: (_) => _section());
      }

      // الخادم يقول «لا تملكها»
      await fresh({'subscribers.view': true}, canView: false);
      expect(server.calls('GET', _listPath), isEmpty);
      expect([TicketsState.inBell, TicketsState.bellBadge], [false, 0]);
      expect(find.text('تذاكر المشتركين'), findsNothing);
      // صلاحيّاتٌ محفوظة تقول «لا» والخادم «نعم» (لم يُحدَّث بعد): القفل عندنا يكفي
      await fresh({'subscribers.view': true});
      expect(server.calls('GET', _listPath), isEmpty);
      expect([TicketsState.inBell, TicketsState.bellBadge], [false, 0]);
      expect(find.text('علي عباس'), findsNothing);
      // المقيَّد بمديرٍ فرعيّ
      await fresh({'tickets.view': true}, canView: false, scoped: true);
      expect(server.calls('GET', _listPath), isEmpty);
      expect(find.text('تذاكر المشتركين'), findsNothing);
      await fresh({'tickets.view': true}, scoped: true);
      expect(TicketsState.inBell, false, reason: 'المقيَّد لا يأخذ القسم ولو جاء العرض');
      expect(server.calls('GET', _listPath), isEmpty);
      // بالصلاحيّة
      await fresh({'tickets.view': true});
      expect(find.text('تذاكر المشتركين'), findsOneWidget);
      expect(find.text('علي عباس'), findsOneWidget);
      expect(TicketsState.bellBadge, 1);
      await simDrain(t);
    });

    testWidgets('النقر يفتح المحادثة نفسها؛ والرجوع يقرأ الجرس (ردٌّ أخرجها من «بانتظارك»)؛ و«الكلّ» قسم التذاكر', (t) async {
      final world = [_ticket(9, 'open', unread: true)];
      _serve(server, world);
      server.on('GET', '/api/v2/portal/tickets/9', (_) => SimReply(200, {
            'success': true,
            'ticket': {...world.first, 'unread': false},
            'messages': [
              {'id': 1, 'side': 'subscriber', 'kind': 'text', 'body': 'النت مقطوع من الصبح', 'created_at': _iso(const Duration(minutes: 7))},
            ],
          }));
      server.on('POST', '/api/v2/portal/tickets/9/reply', (req) {
        world[0] = _ticket(9, 'answered', preview: 'جرّب الآن', author: 'manager');
        return SimReply(200, {
          'success': true,
          'ticket': world[0],
          'message': {'id': 2, 'side': 'manager', 'author': 'boss', 'kind': 'text', 'body': (req.data as Map)['body'], 'created_at': _iso(Duration.zero)},
        });
      });
      final nav = GlobalKey<NavigatorState>();
      await pumpSim(t, _v, navigatorKey: nav, home: (_) => _section());
      final summaries = server.calls('GET', _summaryPath).length;
      await t.tap(find.byKey(const ValueKey('ticket-tile-9')));
      await t.pumpAndSettle();
      expect(find.byType(TicketThreadScreen), findsOneWidget);
      expect(server.calls('GET', '/api/v2/portal/tickets/9'), hasLength(1));
      expect(find.text('النت مقطوع من الصبح'), findsOneWidget, reason: 'رسالة المشترك في المحادثة');
      await t.enterText(find.byKey(const ValueKey('ticket-composer')), 'جرّب الآن');
      await t.tap(find.byKey(const ValueKey('ticket-send')));
      await t.pumpAndSettle();
      expect(server.bodies('POST', '/api/v2/portal/tickets/9/reply').single, {'body': 'جرّب الآن'});
      nav.currentState!.pop();
      await t.pumpAndSettle();
      expect(server.calls('GET', _summaryPath).length, greaterThan(summaries), reason: 'الرجوع يقرأ الجرس');
      expect(TicketsState.bell.value.items, isEmpty);
      expect(find.text('تذاكر المشتركين'), findsNothing, reason: 'لم يعد شيءٌ ينتظرك');
      // «الكلّ»
      world.add(_ticket(11, 'open', unread: true, name: 'حسين جاسم'));
      await t.runAsync(() => TicketsState.ensureFresh(force: true));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('tickets-inbox-all')));
      await t.pumpAndSettle();
      expect(find.byType(TicketsScreen), findsOneWidget);
      expect(find.text('حسين جاسم'), findsOneWidget, reason: 'القائمة بفلترها «بانتظارك»');
      expect(t.takeException(), isNull);
      await simDrain(t);
    });

    testWidgets('رقم الجرس في الرأس: كلّ ما ينتظرك مرّةً واحدة (الجديدة لا تُعدّ مرّتين)، وغير المقروءة بالوجه الآخر؛ والموظّف بلا العرض بلا رقم',
        (t) async {
      final world = [
        _ticket(9, 'open', unread: true),
        _ticket(8, 'in_progress', name: 'مصطفى كريم'),
        _ticket(7, 'open', name: 'زيد علي'),
      ];
      _serve(server, world);
      Finder badge(String n) =>
          find.descendant(of: find.byKey(const ValueKey('top-actions-notifications')), matching: find.text(n));
      Widget header() => Scaffold(appBar: AppBar(actions: const [TopActions()]));
      await pumpSim(t, _v, home: (_) => header());
      expect(badge('3'), findsOneWidget, reason: 'ثلاثٌ بانتظارك، والجديدة منها مرّةً واحدة (لا ٤)');
      TicketsState.debugSetBadgeRule(TicketsBadgeRule.unread);
      await t.pumpWidget(const SizedBox());
      await pumpSim(t, _v, home: (_) => header());
      expect(badge('1'), findsOneWidget, reason: 'الوجه الآخر: غير المقروءة وحدها');
      TicketsState.debugSetBadgeRule(kTicketsBadgeRule);
      // تذكرةٌ جديدةٌ واحدة وحدها ⇒ ١ (غير مقروءة و«بانتظارك» معاً)
      await t.pumpWidget(const SizedBox());
      TicketsState.reset();
      _serve(server, [_ticket(9, 'open', unread: true)]);
      await pumpSim(t, _v, home: (_) => header());
      expect(badge('1'), findsOneWidget);
      expect(badge('2'), findsNothing);
      await t.pumpWidget(const SizedBox());
      TicketsState.reset();
      PermissionsService.debugSet(isEmployee: true, permissions: {'subscribers.view': true});
      _serve(server, world, canView: false);
      await pumpSim(t, _v, home: (_) => header());
      expect(badge('1'), findsNothing);
      expect(find.descendant(of: find.byKey(const ValueKey('top-actions-notifications')), matching: find.byType(Text)), findsNothing,
          reason: 'لا رقم أصلاً');
      await simDrain(t);
    });

    testWidgets('«كل الشركات»: الجرس والمحادثة وصورها للشركة المفتوحة ولو بقي تحتها قسمٌ موجَّهٌ لغيرها ببادئةٍ تطابق', (t) async {
      final prevToken = AccountApi.tokenSource;
      AccountApi.tokenSource = ({bool force = false}) async => 'acct';
      addTearDown(() => AccountApi.tokenSource = prevToken);
      final owner = Object();
      // كقسم «بوابة المشترك» لشركةٍ أخرى مفتوحٍ على الحاسبة تحت الجرس (بادئته /api/v2/portal تشمل التذاكر)
      CompanyRoute.enterSection(owner, _kOther, const ['/api/v2/portal']);
      addTearDown(() => CompanyRoute.leaveSection(owner));
      final world = [_ticket(9, 'open', unread: true)];
      _serve(server, world);
      server.on('GET', '/api/v2/portal/tickets/9', (_) => SimReply(200, {
            'success': true,
            'ticket': {...world.first, 'unread': false},
            'messages': [
              {
                'id': 2,
                'side': 'subscriber',
                'kind': 'text',
                'body': 'هذه صورة الراوتر',
                'image': const {'available': true, 'mime': 'image/jpeg', 'width': 1, 'height': 1, 'bytes': 70},
                'created_at': _iso(const Duration(minutes: 7)),
              },
            ],
          }));
      server.on('GET', '/api/v2/portal/tickets/9/messages/2/image', (_) => _BytesReply(_png));
      TicketsApi.debugClearImages();
      final nav = GlobalKey<NavigatorState>();
      await pumpSim(t, _v, navigatorKey: nav, home: (_) => _section());
      String? keyOf(RequestOptions r) => r.headers['x-company-key'] as String?;
      final bellAsked = server.requests.where((r) => r.path.startsWith(_listPath)).toList();
      expect(bellAsked.map((r) => r.path).toSet(), {_summaryPath, _listPath});
      expect(bellAsked.map(keyOf).toSet(), {null}, reason: 'الملخّص وقائمة الجرس للمفتوحة');
      expect(find.text('علي عباس'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('ticket-tile-9')));
      await t.pumpAndSettle();
      final thread = server.calls('GET', '/api/v2/portal/tickets/9');
      expect(thread, hasLength(1));
      expect(keyOf(thread.single), isNull, reason: 'المحادثة لشركتها المفتوحة');
      final img = server.calls('GET', '/api/v2/portal/tickets/9/messages/2/image');
      expect(img, hasLength(1));
      expect(keyOf(img.single), isNull, reason: 'وصورتها كذلك');
      // الضابط: الطلب نفسه بلا تثبيتٍ يذهب للقسم الموجَّه — فالتثبيت هو الذي أبقاها للمفتوحة
      await t.runAsync(() => TicketsApi.summary());
      expect(keyOf(server.calls('GET', _summaryPath).last), _kOther);
      nav.currentState!.pop();
      await t.pumpAndSettle();
      expect(server.calls('GET', _summaryPath).where((r) => keyOf(r) == null).length, greaterThanOrEqualTo(2),
          reason: 'قراءة الرجوع للمفتوحة أيضاً');
      // ونقر إشعار التذكرة كذلك (الموجِّه يبدّل لشركته المفتوحة أوّلاً — CompanyPush)
      final f = openTicketPush(nav.currentState!, {'type': 'portal_ticket', 'ticket_id': '9', 'event': 'reply'});
      await t.pumpAndSettle();
      expect(server.calls('GET', '/api/v2/portal/tickets/9').map(keyOf).toList(), [null, null]);
      nav.currentState!.pop();
      await t.pumpAndSettle();
      expect(await f, true);
      expect(t.takeException(), isNull);
      await simDrain(t);
    });

    testWidgets('«كل الشركات»: «الكلّ» وإشعارٌ بلا تذكرة ⇒ تذاكر المفتوحة التي يعرضها الجرس مثبَّتةً لها — والشريط لا يتبدّل', (t) async {
      final prevToken = AccountApi.tokenSource;
      AccountApi.tokenSource = ({bool force = false}) async => 'acct';
      addTearDown(() => AccountApi.tokenSource = prevToken);
      const kOpen = 'c0000000000a1';
      MergedMode.reset();
      MergedMode.fetchRaw = () async => {
            'routing': true,
            'writes': true,
            'companies': [
              {'key': kOpen, 'code': 'speed', 'username': 'u0', 'name': 'سبيد', 'status': 'ok', 'admin_id': 'speed:7', 'ns': 'a', 'currency': 'IQD', 'color_index': 0},
              {'key': _kOther, 'code': 'jt', 'username': 'u1', 'name': 'الجزيرة', 'status': 'ok', 'admin_id': 'jt:6836', 'ns': 'j', 'currency': 'IQD', 'color_index': 1},
            ],
          };
      addTearDown(MergedMode.reset);
      expect(await t.runAsync(MergedMode.enter), isTrue);
      MergedMode.focus.value = _kOther;
      final world = [_ticket(9, 'open', unread: true)];
      _serve(server, world);
      final nav = GlobalKey<NavigatorState>();
      await pumpSim(t, _v, navigatorKey: nav, home: (_) => _section());
      String? keyOf(RequestOptions r) => r.headers['x-company-key'] as String?;
      expect(server.requests.where((r) => r.path.startsWith(_listPath)).map(keyOf).toSet(), {null}, reason: 'الجرس للمفتوحة');
      final before = server.requests.length;
      await t.tap(find.byKey(const ValueKey('tickets-inbox-all')));
      await t.pumpAndSettle();
      expect(find.byType(TicketsScreen), findsOneWidget);
      // مراجعة 179: الشريط لا يتبدّل — القائمة مثبَّتةٌ للمفتوحة
      expect(MergedMode.focus.value, _kOther, reason: 'الشريط كما اختاره');
      final asked = server.requests.skip(before).where((r) => r.path.startsWith(_listPath)).toList();
      expect(asked, isNotEmpty);
      expect(asked.map(keyOf).toSet(), {null}, reason: 'قائمة المفتوحة لا الجزيرة');
      expect(find.text('علي عباس'), findsOneWidget);
      nav.currentState!.pop();
      await t.pumpAndSettle();
      // إشعار تذكرةٍ بلا رقمها ⇒ القائمة للمفتوحة كذلك
      MergedMode.focus.value = _kOther;
      await t.pumpAndSettle();
      final before2 = server.requests.length;
      final f = openTicketPush(nav.currentState!, {'type': 'portal_ticket', 'event': 'new'});
      await t.pumpAndSettle();
      expect(find.byType(TicketsScreen), findsOneWidget);
      expect(MergedMode.focus.value, _kOther);
      expect(server.requests.skip(before2).where((r) => r.path.startsWith(_listPath)).map(keyOf).toSet(), {null});
      nav.currentState!.pop();
      await t.pumpAndSettle();
      expect(await f, true);
      expect(t.takeException(), isNull);
      await simDrain(t);
    });

    testWidgets('إشعار تذكرةٍ وصل ⇒ الجرس يُقرأ فوراً ويعرضها بأعلاه', (t) async {
      final world = [_ticket(8, 'in_progress', name: 'مصطفى كريم', ago: const Duration(hours: 1))];
      _serve(server, world);
      await pumpSim(t, _v, home: (_) => _section());
      expect(find.text('مصطفى كريم'), findsOneWidget);
      expect(find.descendant(of: find.byKey(const ValueKey('tickets-inbox-count')), matching: find.text('1')), findsOneWidget,
          reason: 'قيد المعالجة تنتظرك حتى تُعالَج');
      world.add(_ticket(12, 'open', unread: true, name: 'حسين جاسم', ago: Duration.zero));
      await t.runAsync(InboxService.clear);
      TicketsState.onInboxChanged(); // أوّل قراءةٍ للصندوق: لا تذكرة فيه
      await t.runAsync(() => InboxService.add(AppNotification.fromFcmPayload(
            messageId: 'tk-12',
            title: 'تذكرة جديدة من مشترك',
            body: 'حسين جاسم — انقطاع أو بطء',
            data: {'type': 'portal_ticket', 'ticket_id': '12', 'event': 'created'},
          )));
      TicketsState.onInboxChanged();
      await t.pumpAndSettle();
      expect(find.text('حسين جاسم'), findsOneWidget);
      expect(TicketsState.bell.value.items.first.id, 12, reason: 'غير المقروءة أوّلاً');
      expect(find.descendant(of: find.byKey(const ValueKey('tickets-inbox-count')), matching: find.text('2')), findsOneWidget);
      await t.runAsync(InboxService.clear);
      await simDrain(t);
    });

    testWidgets('لافتة إشعار التذكرة والتطبيق مفتوح: نقرها يفتح المحادثة نفسها (للشركة المفتوحة) لا صندوق الإشعارات', (t) async {
      final world = [_ticket(9, 'open', unread: true)];
      _serve(server, world);
      server.on('GET', '/api/v2/portal/tickets/9', (_) => SimReply(200, {
            'success': true,
            'ticket': {...world.first, 'unread': false},
            'messages': [
              {'id': 1, 'side': 'subscriber', 'kind': 'text', 'body': 'النت مقطوع من الصبح', 'created_at': _iso(const Duration(minutes: 7))},
            ],
          }));
      await t.runAsync(InboxService.clear);
      final nav = GlobalKey<NavigatorState>();
      await pumpSim(t, _v, navigatorKey: nav, home: (_) => const Scaffold(body: SizedBox()));
      NotificationRouter.attach(nav);
      NotificationRouter.markReady();
      addTearDown(NotificationRouter.reset);
      InAppNotificationBanner.show(t.element(find.byType(Scaffold)),
          notification: AppNotification.fromFcmPayload(
            messageId: 'tk-banner',
            title: 'تذكرة جديدة من مشترك',
            body: 'علي عباس — انقطاع أو بطء: النت مقطوع من الصبح',
            data: {'type': 'portal_ticket', 'ticket_id': '9', 'event': 'created', 'subscriber_username': 'ali.abbas'},
          ));
      await t.pump();
      await t.pump(const Duration(milliseconds: 400)); // انزلاق اللافتة
      await t.tap(find.text('تذكرة جديدة من مشترك'));
      await t.pumpAndSettle();
      expect(find.byType(TicketThreadScreen), findsOneWidget, reason: 'المحادثة نفسها');
      expect(find.text('النت مقطوع من الصبح'), findsOneWidget);
      expect(find.byType(InboxScreen), findsNothing, reason: 'لا صندوق الإشعارات');
      final thread = server.calls('GET', '/api/v2/portal/tickets/9');
      expect(thread, hasLength(1));
      expect(thread.single.headers['x-company-key'], isNull, reason: 'للشركة المفتوحة');
      nav.currentState!.pop();
      await t.pumpAndSettle();
      await t.runAsync(InboxService.clear);
      await simDrain(t);
    });

    testWidgets('صندوق الإشعارات (الجرس): القسم فيه ولا «لا توجد إشعارات» معه؛ وبلا ما ينتظر تعود الرسالة', (t) async {
      final world = [_ticket(9, 'open', unread: true)];
      _serve(server, world);
      _serveSubscribers(server);
      await pumpSim(t, _v, home: (_) => const InboxScreen());
      await t.pumpAndSettle();
      expect(find.text('تذاكر المشتركين'), findsOneWidget);
      expect(find.text('علي عباس'), findsOneWidget);
      expect(find.text('لا توجد إشعارات جديدة'), findsNothing);
      // رُدّ عليها من مكانٍ آخر ⇒ السحب يقرأ الجرس فيختفي القسم وتعود الرسالة
      world[0] = _ticket(9, 'answered', author: 'manager');
      await t.fling(find.byType(ListView).first, const Offset(0, 400), 1200);
      await t.pumpAndSettle();
      expect(find.text('تذاكر المشتركين'), findsNothing);
      expect(find.text('لا توجد إشعارات جديدة'), findsOneWidget);
      expect(t.takeException(), isNull);
      await simDrain(t);
    });

    for (final v in simVariants) {
      testWidgets('بلا فيضٍ ولا أخطاء @${v.tag}: الجرس بطلب تجديدٍ وتذاكر بأسماءٍ طويلة', (t) async {
        _serve(server, [
          _ticket(9, 'open',
              unread: true,
              name: 'علي عباس حسين الجبوري الطويل جدّاً',
              user: 'very.long.username.example',
              preview: 'النت يقطع كلّ ساعة تقريباً من يوم الخميس — جرّبت إطفاء الراوتر وما صار شي'),
          _ticket(8, 'in_progress', name: 'مصطفى كريم', category: 'device', preview: 'سنرسل فنّيّاً اليوم', author: 'manager',
              ago: const Duration(hours: 2)),
          _ticket(6, 'cancelled', unread: true, name: 'زيد علي', category: 'account', preview: null, ago: const Duration(minutes: 25)),
        ]);
        server.reply('GET', '/api/v2/portal/renew-settings', 200, {'success': true, 'available': true, 'can_use': true, 'can_edit': true, 'enabled': true});
        server.reply('GET', '/api/v2/portal/renew-requests', 200, {
          'success': true,
          'items': [
            {
              'id': 41,
              'status': 'pending',
              'months': 1,
              'amount': 35000,
              'package': {'id': '12', 'name': 'Fiber 50', 'same': true},
              'pay_method': 'zaincash',
              'created_at': _iso(const Duration(minutes: 12)),
              'subscriber': {'idx': '41', 'username': 'sara.m', 'name': 'سارة محمد'},
              'image': {'available': false},
            },
          ],
          'counts': {'pending': 1, 'accepted': 0},
        });
        _serveSubscribers(server, rows: const [
          (user: 'hasan77', name: 'حسن كاظم', left: Duration(hours: 5)),
          (user: 'noor12', name: 'نور الهدى', left: Duration(hours: 11)),
        ]);
        await pumpSim(t, v, home: (_) => const InboxScreen());
        await t.pumpAndSettle();
        expect(find.text('طلبات التجديد'), findsOneWidget);
        expect(find.text('تذاكر المشتركين'), findsOneWidget);
        expect(t.takeException(), isNull);
        expect(simRawTextViolations(), isEmpty);
        final out = Platform.environment['TICKETS_BELL_OUT'] ?? '';
        if (out.isNotEmpty) {
          final boundary = t.renderObject<RenderRepaintBoundary>(find.byKey(simRootKey));
          final png = await t.runAsync(() async {
            final image = await boundary.toImage(pixelRatio: 2);
            final data = await image.toByteData(format: ui.ImageByteFormat.png);
            image.dispose();
            return data!.buffer.asUint8List();
          });
          File('$out/bell_${v.tag}.png')
            ..parent.createSync(recursive: true)
            ..writeAsBytesSync(png!, flush: true);
        }
        await simDrain(t);
      });
    }
  });
}
