import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/api/national_more_api.dart';
import 'package:rad_mysvcs/api/national_portal_api.dart';
import 'package:rad_mysvcs/core/util/list_orders.dart';
import 'package:rad_mysvcs/core/util/order_rules.dart';
import 'package:rad_mysvcs/screens/national/national_money_screen.dart';
import 'package:rad_mysvcs/screens/national/national_reports_screen.dart';
import 'package:rad_mysvcs/screens/national/national_sessions_screen.dart';
import 'package:rad_mysvcs/screens/national/national_team_screen.dart';
import 'package:rad_mysvcs/screens/national/national_tickets_screen.dart';
import 'package:rad_mysvcs/screens/national/national_wallet_screen.dart';
import 'package:rad_mysvcs/screens/national/national_work_screen.dart';
import 'package:rad_mysvcs/screens/reports/v2/report_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'visual_perm/visual_perm_harness.dart';

/// «رتّب حسب» لقوائم بوّابة الوطنيّ (المالك ٢٤ نوفمبر: «اي طبعا كلها رتبها»): الحقول ومفاتيح الحفظ كالموقع حرفاً
/// (test/fixtures/list_sorts_portal.json مولَّدٌ من client-v2 lib/list-sorts.ts)، والقوائم التي ترتّبها البوّابة ترسل ?sort&sort_dir
/// بغير الافتراضيّ وحده (الافتراضيّ = الطلب كما كان)، و«فريقي» والتقارير تُرتَّب عندنا على القائمة كاملة.

const _names = ['بشير الكبيسي', 'إبراهيم علي', 'ثامر حسن', 'تقي جواد'];
String _iso(int d) => '2026-11-${d.toString().padLeft(2, '0')} 09:00:00';

final _team = <Map<String, dynamic>>[
  {'id': 'm1', 'name': 'زيد كريم', 'username': 'zaid', 'role': {'code': 'ContractorAgent', 'label': 'وكيل'}, 'is_main': false, 'wallet_limit': {'limited': true, 'amount': 50000}, 'last_login_at': _iso(20)},
  {'id': 'm2', 'name': 'إبراهيم علي', 'username': null, 'username_masked': '•••4567', 'role': {'code': 'Admin', 'label': 'مدير'}, 'is_main': false, 'wallet_limit': {'limited': false, 'amount': null}, 'last_login_at': null},
  {'id': 'm3', 'name': 'agent10', 'username': 'agent10', 'role': null, 'is_main': true, 'wallet_limit': null, 'last_login_at': _iso(23)},
  {'id': 'm4', 'name': 'آمنة حسن', 'username': 'amna', 'role': {'code': 'Technician', 'label': 'فنّي'}, 'is_main': false, 'wallet_limit': {'limited': true, 'amount': 10000}, 'last_login_at': _iso(22)},
];

class _Nat implements HttpClientAdapter {
  _Nat(this.inner);
  final HttpClientAdapter inner;
  final log = <RequestOptions>[];

  static ResponseBody _json(Object body, [int status = 200]) =>
      ResponseBody.fromString(jsonEncode(body), status, headers: {Headers.contentTypeHeader: [Headers.jsonContentType]});

  Map<String, dynamic> _page(List<Map<String, dynamic>> rows, int total, int size, Map<String, dynamic> q, [Map<String, dynamic> extra = const {}]) => {
        'success': true, 'data': rows, 'total': total, 'page': int.tryParse('${q['page'] ?? 1}') ?? 1, 'size': size,
        'page_count': (total / size).ceil(), 'filters': <String, dynamic>{}, 'fetched_at': '2026-11-24T09:00:00Z', 'stale': false, ...extra,
      };

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    final p = o.path;
    final q = o.queryParameters;
    if (o.method.toUpperCase() != 'GET') return inner.fetch(o, requestStream, cancelFuture);
    log.add(o);
    if (p == '/api/v2/ftth/lookups') return _json({'success': true, 'beta': true, 'can_write': false, 'zones': [{'id': 'FBG1', 'name': 'FBG1'}]});
    if (p == '/api/v2/ftth/counts') return _json({'success': true, 'beta': true, 'requests_action_required': 1});
    if (p == '/api/v2/ftth/tickets') {
      return _json(_page([
        for (var i = 0; i < 3; i++)
          {'id': 't$i', 'display_id': 'cc-$i', 'source': 'agent', 'title': 'عطل $i', 'summary': 'لا إنترنت', 'status': 'Open', 'customer': {'id': '$i', 'name': _names[i]}, 'zone': {'id': 'FBG1', 'name': 'FBG1'}, 'created_at': _iso(20 - i)},
      ], 40, 12, q));
    }
    if (p == '/api/v2/ftth/requests') {
      return _json(_page([
        for (var i = 0; i < 3; i++)
          {'id': 'r$i', 'title': 'طلب', 'type': 'CustomerOnboardingRequest', 'type_label': 'Customer Onboarding Request', 'status': 'Done', 'created_at': _iso(20 - i), 'customer': {'id': '$i', 'name': _names[i]}, 'username': 'FBG$i', 'zone': 'FBG1'},
      ], 60, 25, q, {'summary': const []}));
    }
    if (p == '/api/v2/ftth/tasks') {
      return _json(_page([
        for (var i = 0; i < 3; i++) {'id': 'k$i', 'title': 'تركيب', 'status': 'Open', 'due_at': _iso(25 - i), 'created_at': _iso(10 + i), 'customer': {'id': '$i', 'name': _names[i]}, 'zone': 'FBG1'},
      ], 60, 25, q, {'summary': {'open': 3, 'completed': 1, 'due_today': 0, 'due_week': 0, 'due_next7': 1, 'total': 4}}));
    }
    if (p == '/api/v2/ftth/sessions') {
      return _json(_page([
        for (var i = 0; i < 3; i++)
          {'username': 'FBG88$i', 'customer': {'id': '$i', 'name': _names[i]}, 'zone': {'id': 'FBG1', 'name': 'FBG1'}, 'subscription': {'id': '$i', 'name': 'BASIC', 'expired': false}, 'started_at': _iso(24), 'session_time': 3600 * (i + 1), 'download_bytes': 1000, 'upload_bytes': 100},
      ], 80, 25, q, {'status': 'online', 'filtered_in_page': false}));
    }
    if (p == '/api/v2/ftth/transactions' || p == '/api/v2/ftth/wallet' || p == '/api/v2/ftth/transfers') {
      return _json(_page([
        for (var i = 0; i < 3; i++)
          {'id': 'w$i', 'at': _iso(24 - i), 'type': 'PLAN_RENEW', 'amount': 35000, 'currency': 'IQD', 'method': 'Wallet', 'paid_by': 'Partner', 'username': 'FBG88$i', 'customer': {'id': '$i', 'name': _names[i]}},
      ], 150, 50, q, {'sum': 105000, 'balance': {'balance': 1000000, 'commission': null, 'currency': 'IQD', 'limit': null}, 'caps': {'transfers': true}}));
    }
    if (p == '/api/v2/ftth/team') return _json(_page(_team, _team.length, 25, q, {'beta': true}));
    if (p == '/api/v2/ftth/reports/zones') {
      return _json({
        'success': true, 'beta': true,
        'data': [
          {'zone_id': 'FBG2', 'zone': 'FBG2', 'total': 120, 'active': 70, 'expired': 50, 'suspended': 3},
          {'zone_id': 'FBG1', 'zone': 'FBG1', 'total': 90, 'active': 85, 'expired': 5, 'suspended': 0},
          {'zone_id': 'AKR1', 'zone': 'AKR1', 'total': 30, 'active': 10, 'expired': 20, 'suspended': 1},
        ],
        'totals': {'total': 240, 'active': 165, 'expired': 75, 'suspended': 4},
      });
    }
    if (p == '/api/v2/ftth/reports/sessions') {
      return _json({
        'success': true, 'beta': true,
        'data': [
          {'zone_id': 'FBG2', 'online': 40, 'offline': 80, 'total': 120},
          {'zone_id': 'FBG1', 'online': 60, 'offline': 30, 'total': 90},
          {'zone_id': 'AKR1', 'online': 5, 'offline': 25, 'total': 30},
        ],
        'totals': {'total': 240, 'online': 105, 'offline': 135},
      });
    }
    return inner.fetch(o, requestStream, cancelFuture);
  }

  /// معاملات الترتيب لآخر طلبٍ إلى [path] («-:-» بلاها، و«none» بلا طلب).
  String sortOf(String path) {
    final l = log.where((o) => o.path == path).toList();
    if (l.isEmpty) return 'none';
    final q = l.last.queryParameters;
    return '${q['sort'] ?? '-'}:${q['sort_dir'] ?? '-'}';
  }

  int count(String path) => log.where((o) => o.path == path).length;

  @override
  void close({bool force = false}) => inner.close(force: force);
}

List<Map<String, Object?>> _shape(List<OrderField> fields) => [
      for (final f in fields)
        {
          'key': f.key,
          'label': f.label,
          'kind': f.kind.name,
          if (f.first != null) 'first': f.first!.name,
          if (f.natural != null) 'natural': f.natural!.name,
        },
    ];

final _bidi = RegExp('[\u2066-\u2069\u200E\u200F]');
List<String> _orderOf(WidgetTester t, List<String> labels) {
  final tops = <String, double>{};
  for (final l in labels) {
    final f = find.byWidgetPredicate((w) => w is Text && (w.data ?? '').replaceAll(_bidi, '').trim() == l);
    if (f.evaluate().isEmpty) continue;
    tops[l] = t.getTopLeft(f.first).dy;
  }
  return tops.keys.toList()..sort((a, b) => tops[a]!.compareTo(tops[b]!));
}

Future<void> _chip(WidgetTester t, String key) async {
  final f = find.byKey(RpSortChips.chipKey(key));
  await t.ensureVisible(f.first);
  await t.tap(f.first);
  await settle(t, seconds: 2);
}

OrderValue? _active(WidgetTester t, [int i = 0]) => t.widgetList<RpSortChips>(find.byType(RpSortChips)).elementAt(i).value;

void main() {
  setUpAll(visualSetUpAll);
  tearDown(visualTearDown);

  group('الحقول كالموقع (lib/list-sorts.ts)', () {
    final web = jsonDecode(File('test/fixtures/list_sorts_portal.json').readAsStringSync()) as Map<String, dynamic>;
    final sets = <String, List<OrderField>>{
      'FTTH_TICKET_SORT': ftthTicketSort,
      'FTTH_REQUEST_SORT': ftthRequestSort,
      'FTTH_TASK_SORT': ftthTaskSort,
      'FTTH_SESSION_SORT': ftthSessionSort,
      'PORTAL_DATE_SORT': portalDateSort,
      'FTTH_TEAM_SORT': ftthTeamSort,
      'ZONE_SUBS_SORT': zoneSubsSort,
      'ZONE_SESS_SORT': zoneSessSort,
    };
    for (final e in sets.entries) {
      test('${e.key}: المفاتيح والأسماء والنوع واتّجاه أوّل نقرة', () => expect(_shape(e.value), web[e.key]));
    }
    test('الافتراضيّ لكلّ قائمة ومفاتيح الحفظ', () {
      for (final e in (web['PORTAL_SORT_INITIAL'] as Map).entries) {
        final v = portalSortInitial[e.key as String]!;
        expect([v.key, v.dir.name], e.value, reason: e.key as String);
      }
      expect(portalSortInitial.keys.toSet(), (web['PORTAL_SORT_INITIAL'] as Map).keys.toSet());
      for (final k in (web['STORAGE_KEYS'] as Map).entries) {
        expect(OrderPrefs.listKey(k.key as String), k.value);
      }
    });
    test('قيم «فريقي» كدالّة الموقع: الاسم أو اليوزر، الرئيسيّ، «غير محدود» أكبر حدّ', () {
      final members = [
        {'name': 'زيد كريم', 'username': 'zaid', 'role': {'label': 'وكيل'}, 'is_main': false, 'wallet_limit': {'limited': true, 'amount': 50000}, 'last_login_at': '2026-11-20 09:00:00'},
        {'name': '', 'username': null, 'username_masked': '•••4567', 'role': null, 'is_main': true, 'wallet_limit': null, 'last_login_at': null},
        {'name': 'إبراهيم علي', 'username': null, 'role': {'label': 'مدير'}, 'is_main': false, 'wallet_limit': {'limited': false, 'amount': null}, 'last_login_at': null},
      ];
      final got = [
        for (final j in members)
          [
            for (final k in ['name', 'role', 'limit', 'login'])
              () {
                final m = NationalTeamMember.fromJson(j);
                return ftthTeamSortValue(k, name: m.name, login: m.login, role: m.role, isMain: m.main, limited: m.limited, walletLimit: m.walletLimit, lastLogin: m.lastLogin);
              }(),
          ],
      ];
      expect(jsonEncode(got), jsonEncode(web['TEAM_VALUES']));
    });
    test('المعاملات: الافتراضيّ لا يرسل شيئاً، وغيره sort/sort_dir', () {
      final d = portalSortInitial['date']!;
      expect(portalSortArgs(d, d), (sort: null, dir: null));
      expect(portalSortArgs(const OrderValue('date', OrderDir.asc), d), (sort: 'date', dir: 'asc'));
      expect(NationalMoreApi.sessionsQuery(online: true, sort: 'zone', sortDir: 'desc')['sort_dir'], 'desc');
      expect(NationalPortalApi.walletQuery(sort: 'date', sortDir: 'asc')['sort'], 'date');
      expect(NationalPortalApi.walletQuery(sort: 'date', sortDir: 'asc')['dir'], isNull, reason: 'dir اتّجاه المبلغ — لا يختلط');
    });
  });

  Future<_Nat> open(WidgetTester t, Widget Function() screen, {double width = 390, double height = 2600, double scale = 1.0, bool dark = false}) async {
    final inner = await visualSetUp(s1bSasOwner);
    final srv = _Nat(inner);
    ApiClient.dio.httpClientAdapter = srv;
    await pumpVisual(
      t,
      VisualDevice(dark ? '_dark' : '', Size(width, height), 2, dark: dark),
      home: (_) => screen(),
      wrap: (child) => Builder(
        builder: (ctx) => MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(scale)), child: child),
      ),
    );
    await settle(t, seconds: 3);
    return srv;
  }

  Future<void> close(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 6));
  }

  /// قائمةٌ ترتّبها البوّابة: الافتراضيّ بلا معاملات، والنقرات ⇒ المعاملات والحالة، ويُحفظ.
  Future<void> flow(WidgetTester t, _Nat srv, String path, OrderValue def, List<(String, String, String)> steps, {int idx = 0, String? prefsKey}) async {
    expect(_active(t, idx), def);
    expect(srv.sortOf(path), '-:-', reason: 'الافتراضيّ = الطلب كما كان');
    for (final (key, active, want) in steps) {
      final before = srv.count(path);
      await _chip(t, key);
      final a = _active(t, idx)!;
      expect('${a.key}:${a.dir.name}', active);
      expect(srv.count(path), greaterThan(before), reason: 'تغيير الترتيب يعيد الجلب من الصفحة الأولى');
      expect(srv.sortOf(path), want);
      final q = srv.log.where((o) => o.path == path).last.queryParameters;
      expect('${q['page']}', '1');
    }
    if (prefsKey != null) {
      final a = _active(t, idx)!;
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(prefsKey), '{"k":"${a.key}","d":"${a.dir.name}"}');
    }
  }

  testWidgets('التذاكر: التاريخ — الأقدم ثمّ يرجع الافتراضيّ بلا معاملات', (t) async {
    final srv = await open(t, () => const NationalTicketsScreen());
    await flow(t, srv, '/api/v2/ftth/tickets', portalSortInitial['tickets']!, [('date', 'date:asc', 'date:asc'), ('date', 'date:desc', '-:-')],
        prefsKey: 'list.v2.ftth-tickets.sort');
    expect(t.takeException(), isNull);
    await close(t);
  });

  testWidgets('الطلبات: الحالة بالاتّجاهين ثمّ التاريخ (الافتراضيّ)', (t) async {
    final srv = await open(t, () => const NationalWorkScreen());
    await flow(t, srv, '/api/v2/ftth/requests', portalSortInitial['requests']!,
        [('status', 'status:asc', 'status:asc'), ('status', 'status:desc', 'status:desc'), ('date', 'date:desc', '-:-')]);
    expect(t.takeException(), isNull);
    await close(t);
  });

  testWidgets('المهامّ: تاريخ الإنشاء ثمّ الموعد، ويُحفظ', (t) async {
    final srv = await open(t, () => const NationalWorkScreen(initialTab: 1));
    await flow(t, srv, '/api/v2/ftth/tasks', portalSortInitial['tasks']!,
        [('created', 'created:desc', 'created:desc'), ('created', 'created:asc', 'created:asc'), ('due', 'due:desc', '-:-'), ('due', 'due:asc', 'due:asc')],
        prefsKey: 'list.v2.ftth-tasks.sort');
    expect(t.takeException(), isNull);
    await close(t);
  });

  testWidgets('الجلسات: الزون ثمّ اليوزر', (t) async {
    final srv = await open(t, () => const NationalSessionsScreen());
    await flow(t, srv, '/api/v2/ftth/sessions', portalSortInitial['sessions']!,
        [('zone', 'zone:asc', 'zone:asc'), ('username', 'username:asc', '-:-'), ('username', 'username:desc', 'username:desc')]);
    expect(t.takeException(), isNull);
    await close(t);
  });

  testWidgets('الإيرادات: الأقدم أوّلاً بالفترة نفسها', (t) async {
    final srv = await open(t, () => const NationalMoneyScreen());
    await flow(t, srv, '/api/v2/ftth/transactions', portalSortInitial['date']!, [('date', 'date:asc', 'date:asc')], prefsKey: 'list.v2.ftth-revenue.sort');
    final q = srv.log.where((o) => o.path == '/api/v2/ftth/transactions').last.queryParameters;
    expect(q['from'], isNotNull);
    expect(t.takeException(), isNull);
    await close(t);
  });

  testWidgets('محفظتي: الأقدم أوّلاً، و«dir» (اتّجاه المبلغ) لا يُرسل معه', (t) async {
    final srv = await open(t, () => const NationalWalletScreen());
    await flow(t, srv, '/api/v2/ftth/wallet', portalSortInitial['date']!, [('date', 'date:asc', 'date:asc')], prefsKey: 'list.v2.ftth-wallet.sort');
    expect(srv.log.where((o) => o.path == '/api/v2/ftth/wallet').last.queryParameters.containsKey('dir'), isFalse);
    expect(t.takeException(), isNull);
    await close(t);
  });

  testWidgets('فريقي: عندنا — الاسم، حد المحفظة (غير محدود أوّلاً والرئيسيّ آخراً)، آخر دخول، والثالثة ترجعها', (t) async {
    final srv = await open(t, () => const NationalTeamScreen());
    final names = ['زيد كريم', 'إبراهيم علي', 'agent10', 'آمنة حسن'];
    expect(_orderOf(t, names), names, reason: 'كما وصلت');
    await _chip(t, 'name');
    expect(_orderOf(t, names), ['agent10', 'إبراهيم علي', 'آمنة حسن', 'زيد كريم']);
    await _chip(t, 'limit');
    expect(_orderOf(t, names), ['إبراهيم علي', 'زيد كريم', 'آمنة حسن', 'agent10']);
    await _chip(t, 'login');
    expect(_orderOf(t, names), ['agent10', 'آمنة حسن', 'زيد كريم', 'إبراهيم علي']);
    await _chip(t, 'login');
    await _chip(t, 'login');
    expect(_orderOf(t, names), names, reason: 'الثالثة ترجعها كما وصلت');
    expect(srv.log.where((o) => o.path == '/api/v2/ftth/team').every((o) => !o.queryParameters.containsKey('sort')), isTrue, reason: 'لا ترتيب عند البوّابة');
    expect(t.takeException(), isNull);
    await close(t);
  });

  testWidgets('تقارير الزونات: فعّال والزون، وتقرير الجلسات منفصل', (t) async {
    await open(t, () => const NationalReportsScreen());
    final zones = ['FBG2', 'FBG1', 'AKR1'];
    // البطاقتان معاً: الأولى للمشتركين — الترتيب يخصّها وحدها (الثانية كما وصلت)
    List<String> firstCard() {
      final tops = <String, List<double>>{};
      for (final z in zones) {
        tops[z] = [for (final e in find.byWidgetPredicate((w) => w is Text && (w.data ?? '').replaceAll(_bidi, '').trim() == z).evaluate()) t.getTopLeft(find.byWidget(e.widget).first).dy];
      }
      final firsts = {for (final z in zones) z: (tops[z]!..sort()).first};
      return zones.toList()..sort((a, b) => firsts[a]!.compareTo(firsts[b]!));
    }

    expect(firstCard(), zones, reason: 'كما وصلت');
    await _chip(t, 'active');
    expect(firstCard(), ['FBG1', 'FBG2', 'AKR1']);
    await _chip(t, 'zone');
    expect(firstCard(), ['AKR1', 'FBG1', 'FBG2']);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('list.v2.ftth-zones.sort'), '{"k":"zone","d":"asc"}');
    expect(prefs.getString('list.v2.ftth-zone-sessions.sort'), isNull);
    expect(t.takeException(), isNull);
    await close(t);
  });

  // ═══════════════ لا فيض ولا قصّ من أضيق هاتف إلى ٤٨٠ بخطٍّ عاديّ ومكبَّر ═══════════════
  final screens = <String, Widget Function()>{
    'tickets': () => const NationalTicketsScreen(),
    'requests': () => const NationalWorkScreen(),
    'tasks': () => const NationalWorkScreen(initialTab: 1),
    'sessions': () => const NationalSessionsScreen(),
    'revenue': () => const NationalMoneyScreen(),
    'wallet': () => const NationalWalletScreen(),
    'team': () => const NationalTeamScreen(),
    'reports': () => const NationalReportsScreen(),
  };
  for (final s in screens.entries) {
    for (final width in [320.0, 480.0]) {
      for (final scale in [1.0, 1.2]) {
        testWidgets('${s.key} @$width ×$scale: «رتّب حسب» بلا فيض', (t) async {
          await open(t, s.value, width: width, height: 1700, scale: scale, dark: width == 320);
          expect(find.byType(RpSortChips), findsWidgets);
          expect(t.takeException(), isNull);
          await close(t);
        });
      }
    }
  }
}
