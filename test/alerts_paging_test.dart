import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/agent_alerts_api.dart';
import 'package:rad_mysvcs/api/connection_auto_api.dart';
import 'package:rad_mysvcs/screens/network_devices/agent_alerts_screen.dart';
import 'package:rad_mysvcs/screens/network_devices/device_alerts_screen.dart';
import 'package:rad_mysvcs/screens/whatsapp/connection_auto_widgets.dart';
import 'package:rad_mysvcs/services/device_alerts_service.dart';
import 'package:rad_mysvcs/services/permissions_service.dart';
import 'package:rad_mysvcs/widgets/alerts_pager.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'sim_el/sim_harness.dart';

/// «تنبيهات المشتركين والأجهزة — خلّي بيها ١٠ قراءات وتحميل المزيد» (المالك ٩ نوفمبر): كلّ قائمةٍ عشرةٌ أوّلاً (الأحدث)، و«تحميل
/// المزيد» يجلب العشرة التالية وحدها حتى لا يبقى شيء فيختفي، وفشل «المزيد» يُبقي ما عُرض ويقول «أعد المحاولة». الخادم الوهميّ هنا
/// بعقد الخادم الجديد (page_size/before ⇒ has_more/next_before) ومسار السجلّ القائم لـ«تنبيهات أجهزتي» (limit/before).
const _v = SimVariant(390, dark: false);

int _ago(Duration d) => DateTime.now().subtract(d).millisecondsSinceEpoch;

/* ═════════════════════ خوادم وهميّة بعقد الخادم ═════════════════════ */

/// «تنبيهات المشتركين»: page_size + before (مؤشّرٌ معتم — هنا مفتاح آخر صفّ) ⇒ الصفحة + has_more + next_before، والأولى بالعدد.
SimHandler _pagedServer(List<Map<String, dynamic>> Function(RequestOptions o) rowsOf, {String idKey = 'key', bool Function(RequestOptions o)? fail}) =>
    (o) {
      if (fail?.call(o) ?? false) return const SimReply(500, {'success': false, 'message': 'تعذّر'});
      final all = rowsOf(o);
      final size = int.parse('${o.queryParameters['page_size']}');
      final before = o.queryParameters['before']?.toString();
      final start = before == null ? 0 : all.indexWhere((x) => '${x[idKey]}' == before) + 1;
      final page = all.skip(start).take(size).toList();
      final more = start + size < all.length;
      return SimReply(200, {
        'success': true,
        'data': {
          'available': true,
          'items': page,
          'has_more': more,
          'next_before': more ? '${page.last[idKey]}' : null,
          if (before == null) ...{'total': all.length, 'sendable': all.where((x) => x['muted'] != true).length},
        },
      });
    };

Map<String, dynamic> _case(int i, String state, {bool muted = false}) => {
      'key': 'i:$i', 'idx': '$i', 'username': 'u$i', 'name': 'مشترك $i', 'state': state,
      'problems': [{'kind': 'signal', 'label': 'الإشارة', 'text': '-70 dBm'}],
      'first_bad_ms': _ago(const Duration(hours: 2)), 'confirmed_ms': _ago(Duration(minutes: i)), 'sends': 0, 'muted': muted,
    };

Map<String, dynamic> _autoStatus({int pending = 0, int watching = 0}) => {
      'success': true,
      'data': {
        'available': true, 'dry_run': false, 'alerts_enabled': true,
        'settings': {'mode': 'approval', 'remind_days': 3, 'max_sends': 3, 'daily_cap': 30, 'hour_from': 10, 'hour_to': 20, 'confirm_min': 30,
          'kinds': ['cable', 'signal', 'ccq', 'fiber_rx', 'fiber_temp']},
        'counts': {'pending': pending, 'watching': watching},
        'in_window': true,
      },
    };

Map<String, dynamic> _agentStatus({List<Map<String, dynamic>> down = const []}) => {
      'success': true,
      'data': {
        'available': true, 'dry_run': false, 'enabled': true, 'notify_up': true, 'can_use': true, 'can_edit': true, 'remote': null,
        'devices': 40, 'monitored': 40, 'down': down, 'quiet': <Object>[], 'network_down': false,
        'last_app_ms': _ago(const Duration(minutes: 2)), 'last_vpn_ms': null,
      },
    };

/// مسار سجلّ «تنبيهات أجهزتي» كما في server/agentAlerts.js: الأحدث أوّلاً، id < before، و limit.
SimHandler _agentLogServer(List<Map<String, dynamic>> all, {bool Function(RequestOptions o)? fail}) => (o) {
      if (fail?.call(o) ?? false) return const SimReply(500, {'success': false, 'message': 'تعذّر'});
      final before = int.tryParse('${o.queryParameters['before'] ?? ''}');
      final limit = int.tryParse('${o.queryParameters['limit'] ?? ''}') ?? 50;
      final rows = all.where((x) => before == null || (x['id'] as int) < before).take(limit).toList();
      return SimReply(200, {'success': true, 'data': {'available': true, 'items': rows}});
    };

Map<String, dynamic> _event(int id) => {
      'id': id, 'kind': id.isEven ? 'down' : 'up', 'title': 'حدث رقم $id', 'detail': null, 'push': 'sent', 'at_ms': _ago(Duration(minutes: 100 - id)),
    };

/// يسحب القائمة حتى يظهر [f] — [within]: القائمة نفسها حين يسبقها شريطٌ يُسحب (تبويبات «تنبيهات المشتركين»).
Future<void> _reach(WidgetTester t, Finder f, {Finder? within}) async {
  final s = within == null ? find.byType(Scrollable).first : find.descendant(of: within, matching: find.byType(Scrollable)).first;
  await t.scrollUntilVisible(f, 300, scrollable: s);
  await t.pumpAndSettle();
}

final _list = find.byType(ListView).first;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  /* ═════════════════════ المتحكّم (بلا واجهة) ═════════════════════ */
  group('AlertsPager', () {
    /// خادمٌ بمؤشّر: [n] عنصراً (0 أحدثها)، المؤشّر = آخر رقمٍ أُرسل.
    ({AlertsFetch<int> fetch, List<({String? before, int have, int size})> calls}) cursorServer(int n, {Set<int> failOn = const {}}) {
      final calls = <({String? before, int have, int size})>[];
      Future<AlertsPage<int>?> fetch({String? before, required int have, required int size}) async {
        calls.add((before: before, have: have, size: size));
        if (failOn.contains(calls.length)) return null;
        final start = before == null ? 0 : int.parse(before) + 1;
        final page = [for (var i = start; i < n && i < start + size; i++) i];
        final more = start + size < n;
        return AlertsPage(page, hasMore: more, next: more ? '${page.last}' : null, total: before == null ? n : null);
      }

      return (fetch: fetch, calls: calls);
    }

    test('١٠ ثمّ «المزيد» ١٠ ثمّ ٥ ويختفي — والعدد الحقيقيّ مع الأولى', () async {
      final s = cursorServer(25);
      final p = AlertsPager<int>(fetch: s.fetch, keyOf: (x) => x);
      await p.reload();
      expect(p.items, List.generate(10, (i) => i));
      expect(p.hasMore, isTrue);
      expect(p.total, 25);
      await p.loadMore();
      expect(p.items.length, 20);
      expect(s.calls.last.before, '9');
      await p.loadMore();
      expect(p.items, List.generate(25, (i) => i));
      expect(p.hasMore, isFalse);
      await p.loadMore();
      expect(s.calls.length, 3, reason: 'لا طلب بعد الأخيرة');
    });

    test('فشل «المزيد» يُبقي ما عُرض (moreFailed) والضغطة التالية تكمل من مكانها؛ فشل التحديث يُبقي القائمة', () async {
      final s = cursorServer(25, failOn: {2, 4});
      final p = AlertsPager<int>(fetch: s.fetch, keyOf: (x) => x);
      await p.reload();
      await p.loadMore();
      expect(p.items.length, 10);
      expect(p.moreFailed, isTrue);
      expect(p.hasMore, isTrue);
      await p.loadMore();
      expect(p.moreFailed, isFalse);
      expect(p.items.length, 20);
      await p.reload(); // الطلب الرابع يفشل
      expect(p.failed, isTrue);
      expect(p.items.length, 20, reason: 'ما عُرض باقٍ');
    });

    test('أوّل تحميلٍ يتعذّر ⇒ failed بلا loaded؛ ثمّ يصلح بالسحب', () async {
      final s = cursorServer(5, failOn: {1});
      final p = AlertsPager<int>(fetch: s.fetch, keyOf: (x) => x);
      await p.reload();
      expect(p.loaded, isFalse);
      expect(p.failed, isTrue);
      await p.reload();
      expect(p.loaded, isTrue);
      expect(p.items, [0, 1, 2, 3, 4]);
      expect(p.hasMore, isFalse);
    });

    test('بعد إجراء: التحديث بعمق ما عُرض (١٢٠) على دفعات الخادم (٥٠ · ٥٠ · ٢٠) لا يرجع للعشرة الأولى', () async {
      final s = cursorServer(200);
      final p = AlertsPager<int>(fetch: s.fetch, keyOf: (x) => x);
      await p.reload();
      for (var i = 0; i < 11; i++) {
        await p.loadMore();
      }
      expect(p.items.length, 120);
      s.calls.clear();
      await p.reload(keepDepth: true);
      expect(s.calls.map((c) => c.size).toList(), [50, 50, 20]);
      expect(s.calls.map((c) => c.before).toList(), [null, '49', '99']);
      expect(p.items, List.generate(120, (i) => i));
      expect(p.hasMore, isTrue);
    });

    test('خادمٌ أقدم بلا مؤشّر: التالية بعد ما جاء من الأعلى (have)، وما تكرّر بين صفحتين لا يُعرض مرّتين', () async {
      var list = List.generate(30, (i) => i + 100);
      final calls = <int>[];
      Future<AlertsPage<int>?> fetch({String? before, required int have, required int size}) async {
        calls.add(have);
        final first = list.take(have + size + 1).toList(); // «أوّل limit» كالخادم القديم
        final rest = first.skip(have).toList();
        return AlertsPage(rest.take(size).toList(), hasMore: rest.length > size);
      }

      final p = AlertsPager<int>(fetch: fetch, keyOf: (x) => x);
      await p.reload();
      list = [99, ...list]; // وصل واحدٌ أعلاها بين الصفحتين
      await p.loadMore();
      expect(calls, [0, 10]);
      expect(p.items.length, 19, reason: 'المكرَّر (109) لا يُعرض مرّتين');
      expect(p.items.toSet().length, p.items.length);
      expect(p.items.last, 118);
    });

    test('تحديثٌ أثناء «المزيد» ⇒ ردّ «المزيد» القديم يُسقط (لا تختلط قائمتان)', () async {
      final hold = Completer<void>();
      Future<AlertsPage<int>?> fetch({String? before, required int have, required int size}) async {
        if (before != null) {
          await hold.future;
          return const AlertsPage([1000], hasMore: false);
        }
        return AlertsPage(List.generate(10, (i) => i), hasMore: true, next: '9');
      }

      final p = AlertsPager<int>(fetch: fetch, keyOf: (x) => x);
      await p.reload();
      final more = p.loadMore();
      expect(p.loadingMore, isTrue);
      await p.reload();
      hold.complete();
      await more;
      expect(p.items.contains(1000), isFalse);
      expect(p.hasMore, isTrue);
      expect(p.loadingMore, isFalse);
    });

    test('AlertsReveal: ١٠ ثمّ ٢٠ ثمّ الكلّ', () {
      final r = AlertsReveal();
      final all = List.generate(23, (i) => i);
      expect(r.take(all).length, 10);
      expect(r.hasMore(all), isTrue);
      r.more();
      expect(r.take(all).length, 20);
      r.more();
      expect(r.take(all).length, 23);
      expect(r.hasMore(all), isFalse);
      expect(r.take(const [1, 2]).length, 2);
    });
  });

  /* ═════════════════════ «تنبيهات المشتركين» ═════════════════════ */
  group('تنبيهات المشتركين', () {
    late SimServer server;
    setUpAll(simSetUpAll);
    setUp(() async {
      server = await simSetUp(secure: {'auth.admin_id': '2', 'auth.admin_username': 'owner'});
      ConnectionAutoApi.debugReset();
      PermissionsService.debugSet(isEmployee: false);
    });
    tearDown(PermissionsService.debugReset);

    List<RequestOptions> q(String state) =>
        server.calls('GET', '/api/v2/connection-alerts/queue').where((c) => c.queryParameters['state'] == state).toList();

    testWidgets('١٠ أوّلاً؛ «تحميل المزيد» يجلب العشرة التالية وحدها بمؤشّر الخادم؛ بعد الأخيرة يختفي', (t) async {
      final rows = [for (var i = 1; i <= 25; i++) _case(i, 'pending')];
      server.reply('GET', '/api/v2/connection-alerts/auto', 200, _autoStatus(pending: 25));
      server.on('GET', '/api/v2/connection-alerts/queue', _pagedServer((o) => o.queryParameters['state'] == 'pending' ? rows : []));
      server.on('GET', '/api/v2/connection-alerts/log', _pagedServer((o) => [], idKey: 'id'));
      ConnectionAutoApi.status.value = ConnAutoStatus.fromJson(Map<String, dynamic>.from(_autoStatus(pending: 25)['data'] as Map));
      await pumpSim(t, _v, home: (_) => const ConnAutoQueueScreen());
      await t.pumpAndSettle();
      expect(q('pending').single.queryParameters['page_size'], 10);
      expect(q('pending').single.queryParameters.containsKey('before'), isFalse);
      expect(find.text('مشترك 1'), findsOneWidget);
      final more = find.byKey(const ValueKey('ca-more-pending'));
      await _reach(t, more, within: _list);
      expect(find.text('مشترك 10'), findsOneWidget);
      expect(find.text('مشترك 11'), findsNothing, reason: 'العشرة الأولى وحدها');
      expect(find.text('تحميل المزيد'), findsOneWidget);
      await t.tap(more);
      await t.pumpAndSettle();
      expect(q('pending').last.queryParameters['before'], 'i:10');
      expect(q('pending').last.queryParameters['page_size'], 10);
      await _reach(t, more, within: _list);
      expect(find.text('مشترك 20'), findsOneWidget);
      expect(find.text('مشترك 21'), findsNothing);
      await t.tap(more);
      await t.pumpAndSettle();
      expect(q('pending').last.queryParameters['before'], 'i:20');
      await _reach(t, find.text('مشترك 25'), within: _list);
      expect(more, findsNothing, reason: 'لا مزيد ⇒ لا زرّ');
      expect(q('pending').length, 3, reason: 'كلّ ضغطةٍ طلبٌ واحد للعشرة التالية — لا إعادة لما عُرض');
      await simDrain(t);
    });

    testWidgets('فشل «المزيد» ⇒ ما عُرض باقٍ والزرّ «تعذّر التحميل — أعد المحاولة»؛ الضغطة التالية تكمل', (t) async {
      final rows = [for (var i = 1; i <= 15; i++) _case(i, 'pending')];
      var failMore = true;
      server.reply('GET', '/api/v2/connection-alerts/auto', 200, _autoStatus(pending: 15));
      server.on('GET', '/api/v2/connection-alerts/queue', _pagedServer((o) => o.queryParameters['state'] == 'pending' ? rows : [],
          fail: (o) => failMore && o.queryParameters['before'] != null));
      server.on('GET', '/api/v2/connection-alerts/log', _pagedServer((o) => [], idKey: 'id'));
      ConnectionAutoApi.status.value = ConnAutoStatus.fromJson(Map<String, dynamic>.from(_autoStatus(pending: 15)['data'] as Map));
      await pumpSim(t, _v, home: (_) => const ConnAutoQueueScreen());
      await t.pumpAndSettle();
      final more = find.byKey(const ValueKey('ca-more-pending'));
      await _reach(t, more, within: _list);
      await t.tap(more);
      await t.pumpAndSettle();
      expect(find.text('تعذّر التحميل — أعد المحاولة'), findsOneWidget);
      expect(find.text('مشترك 10'), findsOneWidget, reason: 'ما عُرض باقٍ');
      expect(find.text('مشترك 11'), findsNothing);
      failMore = false;
      await t.tap(more);
      await t.pumpAndSettle();
      await _reach(t, find.text('مشترك 11'), within: _list);
      expect(find.text('مشترك 11'), findsOneWidget, reason: 'أكمل من مكانه بعد الفشل');
      await _reach(t, find.text('مشترك 15'), within: _list);
      expect(more, findsNothing);
      expect(t.takeException(), isNull);
      await simDrain(t);
    });

    testWidgets('«أرسل للكلّ (N)» بعدد الخادم (كلّ من تحت المراقبة إلّا «لا ترسل له») لا بعدد الصفحة', (t) async {
      final rows = [for (var i = 100; i < 125; i++) _case(i, 'watching', muted: i < 102)];
      server.reply('GET', '/api/v2/connection-alerts/auto', 200, _autoStatus(watching: 25));
      server.on('GET', '/api/v2/connection-alerts/queue', _pagedServer((o) => o.queryParameters['state'] == 'watching' ? rows : []));
      server.on('GET', '/api/v2/connection-alerts/log', _pagedServer((o) => [], idKey: 'id'));
      ConnectionAutoApi.status.value = ConnAutoStatus.fromJson(Map<String, dynamic>.from(_autoStatus(watching: 25)['data'] as Map));
      await pumpSim(t, _v, home: (_) => const ConnAutoQueueScreen(initialTab: 'watching'));
      await t.pumpAndSettle();
      expect(find.text('أرسل للكلّ (23)'), findsOneWidget);
      await simDrain(t);
    });

    testWidgets('السجلّ: ١٠ ثمّ ١٠ ثمّ ٣ برقم السطر، وفشل «المزيد» يُبقيها', (t) async {
      final log = [
        for (var i = 1; i <= 23; i++)
          {'id': 100 - i, 'key': 'i:$i', 'name': 'مشترك $i', 'action': 'sent', 'kinds': ['signal'], 'dry': false, 'at_ms': _ago(Duration(minutes: i))},
      ];
      var fail = false;
      server.reply('GET', '/api/v2/connection-alerts/auto', 200, _autoStatus());
      server.on('GET', '/api/v2/connection-alerts/queue', _pagedServer((o) => []));
      server.on('GET', '/api/v2/connection-alerts/log', _pagedServer((o) => log, idKey: 'id', fail: (o) => fail));
      ConnectionAutoApi.status.value = ConnAutoStatus.fromJson(Map<String, dynamic>.from(_autoStatus()['data'] as Map));
      await pumpSim(t, _v, home: (_) => const ConnAutoQueueScreen(initialTab: 'log'));
      await t.pumpAndSettle();
      final calls = server.calls('GET', '/api/v2/connection-alerts/log');
      expect(calls.single.queryParameters['page_size'], 10);
      final more = find.byKey(const ValueKey('ca-more-log'));
      await _reach(t, more, within: _list);
      expect(find.text('أُرسلت رسالة — مشترك 10'), findsOneWidget);
      expect(find.text('أُرسلت رسالة — مشترك 11'), findsNothing);
      fail = true;
      await t.tap(more);
      await t.pumpAndSettle();
      expect(find.text('تعذّر التحميل — أعد المحاولة'), findsOneWidget);
      expect(find.text('أُرسلت رسالة — مشترك 10'), findsOneWidget, reason: 'لا «السجلّ فارغ» بعد فشل');
      fail = false;
      await t.tap(more);
      await t.pumpAndSettle();
      expect(server.calls('GET', '/api/v2/connection-alerts/log').last.queryParameters['before'], '90');
      await _reach(t, more, within: _list);
      await t.tap(more);
      await t.pumpAndSettle();
      await _reach(t, find.text('أُرسلت رسالة — مشترك 23'), within: _list);
      expect(more, findsNothing);
      await simDrain(t);
    });

    test('خادمٌ أقدم (بلا has_more): الصفحة التالية بالعدد (limit = ما جاء + ١١) بلا page_size — كما كان', () async {
      final rows = [for (var i = 1; i <= 25; i++) _case(i, 'pending')];
      server.on('GET', '/api/v2/connection-alerts/queue', (o) {
        final limit = int.parse('${o.queryParameters['limit']}');
        return SimReply(200, {'success': true, 'data': {'available': true, 'items': rows.take(limit).toList()}});
      });
      final p1 = await ConnectionAutoApi.queuePage('pending');
      expect(p1!.items.map((c) => c.key).toList(), [for (var i = 1; i <= 10; i++) 'i:$i']);
      expect(p1.hasMore, isTrue);
      expect(p1.next, isNull);
      final p2 = await ConnectionAutoApi.queuePage('pending', have: 10);
      final last = server.calls('GET', '/api/v2/connection-alerts/queue').last.queryParameters;
      expect(last['limit'], 21);
      expect(last.containsKey('page_size'), isFalse);
      expect(p2!.items.map((c) => c.key).toList(), [for (var i = 11; i <= 20; i++) 'i:$i']);
      expect(p2.hasMore, isTrue);
      final p3 = await ConnectionAutoApi.queuePage('pending', have: 20);
      expect(p3!.items.length, 5);
      expect(p3.hasMore, isFalse);
    });
  });

  /* ═════════════════════ «تنبيهات أجهزتي» ═════════════════════ */
  group('تنبيهات أجهزتي', () {
    late SimServer server;
    setUpAll(simSetUpAll);
    setUp(() async {
      AgentAlertsApi.forget();
      server = await simSetUp(secure: {'auth.admin_id': '2', 'auth.admin_username': 'admin@m'});
    });

    testWidgets('السجلّ ١٠ (limit 11)؛ «تحميل المزيد» ⇒ ما قبل آخرها (before) حتى ينتهي فيختفي؛ وفشله يُبقي ما عُرض', (t) async {
      final events = [for (var id = 25; id >= 1; id--) _event(id)];
      var fail = false;
      server.reply('GET', '/api/v2/agent-alerts/status', 200, _agentStatus());
      server.on('GET', '/api/v2/agent-alerts/log', _agentLogServer(events, fail: (o) => fail));
      await pumpSim(t, _v, home: (_) => const AgentAlertsScreen());
      await t.pumpAndSettle();
      List<RequestOptions> calls() => server.calls('GET', '/api/v2/agent-alerts/log');
      expect(calls().single.queryParameters['limit'], 11);
      expect(calls().single.queryParameters.containsKey('before'), isFalse);
      final more = find.byKey(const ValueKey('aa-more-log'));
      await _reach(t, more);
      expect(find.text('حدث رقم 16'), findsOneWidget);
      expect(find.text('حدث رقم 15'), findsNothing, reason: 'العشرة الأحدث وحدها');
      fail = true;
      await t.tap(more);
      await t.pumpAndSettle();
      expect(find.text('تعذّر التحميل — أعد المحاولة'), findsOneWidget);
      expect(find.text('حدث رقم 16'), findsOneWidget);
      fail = false;
      await t.tap(more);
      await t.pumpAndSettle();
      expect(calls().last.queryParameters['before'], 16);
      expect(calls().last.queryParameters['limit'], 11);
      await _reach(t, more);
      expect(find.text('حدث رقم 6'), findsOneWidget);
      await t.tap(more);
      await t.pumpAndSettle();
      expect(calls().last.queryParameters['before'], 6);
      await _reach(t, find.text('حدث رقم 1'));
      expect(more, findsNothing);
      expect(t.takeException(), isNull);
      await simDrain(t);
    });

    testWidgets('«طافية الآن» ٢٣ جهازاً: العدّاد يقول ٢٣، والقائمة ١٠ ثمّ «تحميل المزيد» ١٠ ثمّ الباقي', (t) async {
      server.reply('GET', '/api/v2/agent-alerts/status', 200, _agentStatus(down: [
        for (var i = 1; i <= 23; i++) {'id': i, 'name': 'جهاز رقم $i', 'since_ms': _ago(Duration(minutes: 30 + i))},
      ]));
      server.on('GET', '/api/v2/agent-alerts/log', _agentLogServer(const []));
      await pumpSim(t, _v, home: (_) => const AgentAlertsScreen());
      await t.pumpAndSettle();
      expect(find.text('23 جهازاً طافياً الآن'), findsOneWidget, reason: 'العدد الحقيقيّ لا عدد المعروض');
      final more = find.byKey(const ValueKey('aa-more-down'));
      await _reach(t, more);
      expect(find.text('جهاز رقم 10'), findsOneWidget);
      expect(find.text('جهاز رقم 11'), findsNothing);
      await t.tap(more);
      await t.pumpAndSettle();
      await _reach(t, more);
      expect(find.text('جهاز رقم 20'), findsOneWidget);
      expect(find.text('جهاز رقم 21'), findsNothing);
      await t.tap(more);
      await t.pumpAndSettle();
      await _reach(t, find.text('جهاز رقم 23'));
      expect(more, findsNothing);
      await simDrain(t);
    });

    for (final v in [const SimVariant(320, dark: true), const SimVariant(320, dark: false)]) {
      testWidgets('الزرّ وحال فشله بلا فيضٍ @${v.tag}', (t) async {
        final events = [for (var id = 30; id >= 1; id--) _event(id)];
        server.reply('GET', '/api/v2/agent-alerts/status', 200, _agentStatus());
        server.on('GET', '/api/v2/agent-alerts/log', _agentLogServer(events, fail: (o) => o.queryParameters['before'] != null));
        await pumpSim(t, v, home: (_) => const AgentAlertsScreen());
        await t.pumpAndSettle();
        final more = find.byKey(const ValueKey('aa-more-log'));
        await _reach(t, more);
        await t.tap(more);
        await t.pumpAndSettle();
        expect(find.text('تعذّر التحميل — أعد المحاولة'), findsOneWidget);
        expect(t.takeException(), isNull);
        await simDrain(t);
      });
    }
  });

  /* ═════════════════════ «تنبيهات الأجهزة» (الموبايل) ═════════════════════ */
  group('تنبيهات الأجهزة على الموبايل', () {
    setUpAll(simSetUpAll);

    testWidgets('٢٥ تنبيهاً محفوظاً: ١٠ ثمّ ٢٠ ثمّ الكلّ، والزرّ يختفي', (t) async {
      await simSetUp();
      final now = DateTime.now();
      final saved = [
        for (var i = 1; i <= 25; i++)
          DeviceAlert(id: i, deviceId: i, deviceName: 'راوتر $i', deviceIp: '10.0.0.$i', kind: DeviceAlertKind.offline,
                  at: now.subtract(Duration(minutes: i)))
              .toJson(),
      ];
      SharedPreferences.setMockInitialValues({'device_alerts_v1': jsonEncode(saved)});
      await t.runAsync(() => DeviceAlertsService.instance.init());
      expect(DeviceAlertsService.instance.all.length, 25);
      await pumpSim(t, _v, home: (_) => const DeviceAlertsScreen());
      await t.pumpAndSettle();
      final more = find.byKey(const ValueKey('da-more'));
      await _reach(t, more);
      expect(find.text('راوتر 10'), findsOneWidget);
      expect(find.text('راوتر 11'), findsNothing);
      await t.tap(more);
      await t.pumpAndSettle();
      await _reach(t, more);
      expect(find.text('راوتر 20'), findsOneWidget);
      await t.tap(more);
      await t.pumpAndSettle();
      await _reach(t, find.text('راوتر 25'));
      expect(more, findsNothing);
      await simDrain(t);
    });
  });
}
