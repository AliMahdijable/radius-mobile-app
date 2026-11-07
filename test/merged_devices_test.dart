import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:rad_mysvcs/api/account_api.dart';
import 'package:rad_mysvcs/api/agent_alerts_api.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/api/merged_devices_api.dart';
import 'package:rad_mysvcs/api/network_devices_api.dart';
import 'package:rad_mysvcs/api/subscribers_api.dart';
import 'package:rad_mysvcs/models/merged_company.dart';
import 'package:rad_mysvcs/screens/network_devices/network_devices_screen.dart';
import 'package:rad_mysvcs/services/merged_mode.dart';

import 'visual_perm/visual_perm_harness.dart';

/// «كل الشركات» في قسم الأجهزة (٧ نوفمبر): القسم نفسه بشريط الشركات، وكلّ شركةٍ بطلبٍ موجَّه لها، والجهاز يبقى لشركته —
/// أجهزة الشركة المفتوحة تُدار كما هي، وجهاز غيرها لا يفتح صفحةً تطلب كلمات سرّه ولا يُحفظ حاله باسم المفتوحة.
const _kA = 'c0000000000aa'; // المفتوحة (معرّف الجلسة في الحاضنة supernet:12)
const _kB = 'c0000000000bb';
const _kC = 'c0000000000cc';
const _kA2 = 'c0000000000ee'; // صفحةٌ ثانية للمدير نفسه (المعرّف نفسه) ⇒ قائمتها قائمة الأولى

ResponseBody _json(int status, Object body, {Map<String, List<String>> headers = const {}}) =>
    ResponseBody.fromString(jsonEncode(body), status, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
      ...headers,
    });

Map<String, Object?> _dev(int id, String admin, String name, String ip, {String status = 'online'}) => {
      'id': id,
      'admin_id': admin,
      'name': name,
      'type': 'router',
      'brand': 'mikrotik',
      'ip': ip,
      'port': 8728,
      'protocol': 'api',
      'last_status': status,
      'has_credentials': true,
      'created_at': '2026-10-01 10:00:00',
    };

MergedCompany _co(String key, String admin, {String name = 'ش', int i = 0}) => MergedCompany(
      key: key,
      code: 'x',
      username: 'u',
      name: name,
      provider: MergedProvider.sas4,
      colorIndex: i,
      adminId: admin,
      ns: key,
      currency: 'IQD',
      home: false,
      status: MergedStatus.ok,
      index: i,
    );

/// خادمٌ وهميّ: الشركة المفتوحة بلا مفتاح، وغيرها بمفتاحها؛ ويسجّل كلّ طلب (الطريقة · المسار · المفتاح · الجسم).
class _Srv implements HttpClientAdapter {
  _Srv(this.inner);
  final HttpClientAdapter inner;
  final log = <({String method, String path, String? key, Object? data})>[];
  List<Map<String, Object?>> open = [
    _dev(101, 'supernet:12', 'راوتر المركز', '10.10.1.1'),
    _dev(102, 'supernet:12', 'سكتر الشمال', '10.10.1.21'),
  ];
  List<Map<String, Object?>> b = [
    _dev(201, 'jt:22', 'راوتر الجزيرة', '192.168.88.1'),
    _dev(202, 'jt:22', 'سكتر الجزيرة', '192.168.88.20'),
  ];

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? rs, Future<void>? cf) async {
    final key = o.headers['x-company-key'] as String?;
    final path = o.uri.path;
    log.add((method: o.method, path: path, key: key, data: o.data));
    if (key == null) {
      if (path == '/api/v2/admin/devices') return _json(200, {'success': true, 'data': open});
      if (path == '/api/v2/admin/devices/regions') return _json(200, {'success': true, 'data': []});
      if (path == '/api/v2/admin/devices/probe-results') return _json(200, {'success': true});
      return inner.fetch(o, rs, cf);
    }
    final h = {'x-company-key': [key]};
    if (o.method == 'GET' && path == '/api/v2/admin/devices') {
      if (key == _kB) return _json(200, {'success': true, 'data': b}, headers: h);
      if (key == _kA || key == _kA2) return _json(200, {'success': true, 'data': open}, headers: h);
      return _json(409, {'success': false, 'message': 'انتهت جلسة الشركة — افتحها من «شركاتي»'}, headers: h);
    }
    return _json(409, {'success': false, 'code': 'COMPANY_ROUTE_NOT_ALLOWED'}, headers: h);
  }

  @override
  void close({bool force = false}) {}
}

Map<String, Object?> _companies({bool twin = false}) => {
      'routing': true,
      'writes': true,
      'companies': [
        {'key': _kA, 'code': 'supernet', 'username': 'mahdi', 'name': 'سوبرنت', 'status': 'ok', 'admin_id': 'supernet:12', 'ns': 'nA', 'currency': 'IQD', 'color_index': 0},
        {'key': _kB, 'code': 'jt', 'username': 'admin@b', 'name': 'الجزيرة', 'status': 'ok', 'admin_id': 'jt:22', 'ns': 'nB', 'currency': 'IQD', 'color_index': 1},
        {'key': _kC, 'code': 'nbtel', 'username': 'admin@c', 'name': 'نور البداية', 'status': 'ok', 'admin_id': 'nbtel:33', 'ns': 'nC', 'currency': 'IQD', 'color_index': 2},
        if (twin) {'key': _kA2, 'code': 'supernet', 'username': 'mahdi2', 'name': 'سوبرنت ٢', 'status': 'ok', 'admin_id': 'supernet:12', 'ns': 'nA', 'currency': 'IQD', 'color_index': 4},
        {'key': 'c0000000000dd', 'code': 'hs', 'username': 'u', 'name': 'هلا سات', 'status': 'needs_login', 'admin_id': 'hs:44', 'ns': 'nD'},
      ],
    };

void main() {
  group('MergedDevicesApi.parse — الصفّ لشركته أو لا قائمة', () {
    final c = _co(_kB, 'jt:22');
    test('قائمةٌ صالحة', () {
      final rows = MergedDevicesApi.parse(c, {
        'success': true,
        'data': [_dev(1, 'jt:22', 'أ', '10.0.0.1'), _dev(2, 'jt:22', 'ب', '10.0.0.2')],
      });
      expect(rows?.map((d) => d.id), [1, 2]);
    });
    test('صفٌّ لمديرٍ آخر ⇒ القائمة كلّها مرفوضة (لا يُنسب جهازٌ لغير شركته)', () {
      expect(
          MergedDevicesApi.parse(c, {
            'success': true,
            'data': [_dev(1, 'jt:22', 'أ', '10.0.0.1'), _dev(2, 'jt:99', 'ب', '10.0.0.2')],
          }),
          isNull);
    });
    test('معرّفٌ مكرّر أو صفر ⇒ مرفوضة', () {
      expect(
          MergedDevicesApi.parse(c, {
            'success': true,
            'data': [_dev(1, 'jt:22', 'أ', '10.0.0.1'), _dev(1, 'jt:22', 'ب', '10.0.0.2')],
          }),
          isNull);
      expect(MergedDevicesApi.parse(c, {'success': true, 'data': [_dev(0, 'jt:22', 'أ', '10.0.0.1')]}), isNull);
    });
    test('ردٌّ بلا success:true أو بلا قائمة ⇒ تعذّر لا «صفر أجهزة»', () {
      expect(MergedDevicesApi.parse(c, {'success': false, 'data': []}), isNull);
      expect(MergedDevicesApi.parse(c, {'success': true}), isNull);
      expect(MergedDevicesApi.parse(c, {'success': true, 'data': ['x']}), isNull);
      expect(MergedDevicesApi.parse(c, null), isNull);
      expect(MergedDevicesApi.parse(c, {'success': true, 'data': []}), isEmpty);
    });
    test('شركةٌ بلا معرّف مدير ⇒ لا قائمة', () {
      expect(MergedDevicesApi.parse(_co(_kB, ''), {'success': true, 'data': []}), isNull);
    });
  });

  group('القسم في «كل الشركات»', () {
    setUpAll(visualSetUpAll);
    late _Srv srv;

    Future<void> open(WidgetTester t, {bool twin = false}) async {
      NetworkDevicesScreen.debugResetView();
      AgentAlertsApi.forget();
      final inner = await visualSetUp(s1bSasOwner);
      srv = _Srv(inner);
      ApiClient.dio.httpClientAdapter = srv;
      AccountApi.tokenSource = ({bool force = false}) async => 'acct';
      MergedMode.reset();
      MergedMode.fetchRaw = () async => Map<String, dynamic>.from(_companies(twin: twin));
      SubscribersApi.clearAllCaches();
      NetworkDevicesApi.debugService = (d) async => (status: 'online', responseMs: 5, packetLoss: 0.0);
      await t.runAsync(() => MergedMode.enter());
      await pumpVisual(t, const VisualDevice('', Size(390, 1600), 1),
          home: (_) => NetworkDevicesScreen(isActive: ValueNotifier<bool>(true)));
      await settle(t, seconds: 3);
    }

    Future<void> close(WidgetTester t) async {
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 25));
      NetworkDevicesApi.debugService = null;
      MergedMode.reset();
      await visualTearDown();
    }

    testWidgets('كلّ شركةٍ بطلبٍ موجَّه لها، والمفتوحة بطلبها العاديّ؛ والأجهزة معاً بشارة شركتها', (t) async {
      await open(t);
      final lists = srv.log.where((r) => r.method == 'GET' && r.path == '/api/v2/admin/devices').toList();
      expect(lists.map((r) => r.key).toSet(), {null, _kB, _kC}, reason: 'المفتوحة بلا مفتاح، والجزيرة ونور البداية بمفتاحيهما');
      for (final n in ['راوتر المركز', 'سكتر الشمال', 'راوتر الجزيرة', 'سكتر الجزيرة']) {
        expect(find.text(n), findsOneWidget, reason: n);
      }
      // الشريط: الكلّ ٤، وكلّ شركةٍ بعددها، والمتعذّرة تُسمّى والتي تحتاج دخولاً تُذكر
      expect(find.text('كل الشركات · 3'), findsOneWidget);
      expect(find.textContaining('انتهت جلسة الشركة'), findsOneWidget);
      expect(find.textContaining('هلا سات'), findsWidgets);
      expect(find.text('الجزيرة'), findsWidgets);
      await close(t);
    });

    testWidgets('صفحتان لمديرٍ واحد ⇒ قائمته مرّةً واحدة (لا تكرار للأجهزة)', (t) async {
      await open(t, twin: true);
      final lists = srv.log.where((r) => r.method == 'GET' && r.path == '/api/v2/admin/devices').toList();
      expect(lists.where((r) => r.key == _kA2), isEmpty);
      expect(find.text('راوتر المركز'), findsOneWidget);
      await close(t);
    });

    testWidgets('اختيار شركةٍ أخرى يعرض أجهزتها وحدها و«+» يختفي (الإضافة للمفتوحة وحدها)', (t) async {
      await open(t);
      expect(find.byIcon(LucideIcons.plus), findsOneWidget);
      MergedMode.focus.value = _kB;
      await settle(t, seconds: 1);
      expect(find.text('راوتر الجزيرة'), findsOneWidget);
      expect(find.text('راوتر المركز'), findsNothing);
      expect(find.byIcon(LucideIcons.plus), findsNothing);
      MergedMode.focus.value = _kA;
      await settle(t, seconds: 1);
      expect(find.text('راوتر المركز'), findsOneWidget);
      expect(find.text('راوتر الجزيرة'), findsNothing);
      expect(find.byIcon(LucideIcons.plus), findsOneWidget);
      await close(t);
    });

    testWidgets('جهاز شركةٍ أخرى: ورقته لا صفحته الحيّة، ولا طلب كلمات سرّ، ولا تحديد للحذف', (t) async {
      await open(t);
      final before = srv.log.length;
      await t.tap(find.text('سكتر الجزيرة'));
      await settle(t, seconds: 1);
      expect(find.byKey(const ValueKey('merged-device-sheet')), findsOneWidget);
      expect(find.text('فتح «الجزيرة»'), findsOneWidget);
      // أجهزة المفتوحة يسخّنها القسم بكلمات سرّها كما كان؛ جهاز الجزيرة لا يُطلب له شيءٌ منها أبداً
      expect(srv.log.where((r) => r.path.contains('/credentials') && (r.path.contains('/201/') || r.path.contains('/202/'))),
          isEmpty);
      expect(srv.log.skip(before).where((r) => r.path.contains('/202')), isEmpty);
      Navigator.of(t.element(find.byKey(const ValueKey('merged-device-sheet')))).pop();
      await settle(t, seconds: 1);
      await t.longPress(find.text('راوتر الجزيرة'));
      await settle(t, seconds: 1);
      expect(find.textContaining('مُحدَّد'), findsNothing, reason: 'جهاز شركةٍ أخرى لا يدخل الحذف الجماعيّ');
      // الضغط المطوّل بلا إدارةٍ له = ضغطةٌ عاديّة (كموظّف العرض): ورقته من جديد
      expect(find.byKey(const ValueKey('merged-device-sheet')), findsOneWidget);
      Navigator.of(t.element(find.byKey(const ValueKey('merged-device-sheet')))).pop();
      await settle(t, seconds: 1);
      await t.longPress(find.text('راوتر المركز'));
      await settle(t, seconds: 1);
      expect(find.textContaining('مُحدَّد'), findsOneWidget, reason: 'جهاز المفتوحة كما كان');
      await close(t);
    });

    testWidgets('حال الجولة يُحفظ لأجهزة الشركة المفتوحة وحدها', (t) async {
      await open(t);
      final saves = srv.log.where((r) => r.path == '/api/v2/admin/devices/probe-results').toList();
      expect(saves, isNotEmpty);
      final ids = <int>{};
      for (final s in saves) {
        final data = s.data is String ? jsonDecode(s.data as String) : s.data;
        final rows = (data as Map)['results'] as List;
        for (final r in rows) {
          ids.add(((r as Map)['id'] ?? r['device_id']) as int);
        }
      }
      expect(ids, {101, 102});
      expect(saves.every((s) => s.key == null), isTrue);
      await close(t);
    });

    testWidgets('خارج الوضع: القسم كما كان — بلا مفتاح شركة ولا شريط', (t) async {
      NetworkDevicesScreen.debugResetView();
      AgentAlertsApi.forget();
      final inner = await visualSetUp(s1bSasOwner);
      srv = _Srv(inner);
      ApiClient.dio.httpClientAdapter = srv;
      MergedMode.reset();
      NetworkDevicesApi.debugService = (d) async => (status: 'online', responseMs: 5, packetLoss: 0.0);
      await pumpVisual(t, const VisualDevice('', Size(390, 1200), 1),
          home: (_) => NetworkDevicesScreen(isActive: ValueNotifier<bool>(true)));
      await settle(t, seconds: 3);
      expect(srv.log.where((r) => r.key != null), isEmpty);
      expect(find.textContaining('كل الشركات'), findsNothing);
      expect(find.text('راوتر المركز'), findsOneWidget);
      expect(find.text('راوتر الجزيرة'), findsNothing);
      await close(t);
    });
  });
}
