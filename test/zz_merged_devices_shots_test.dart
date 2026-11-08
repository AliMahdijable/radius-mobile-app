import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:rad_mysvcs/api/account_api.dart';
import 'package:rad_mysvcs/api/agent_alerts_api.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/api/network_devices_api.dart';
import 'package:rad_mysvcs/api/subscribers_api.dart';
import 'package:rad_mysvcs/screens/network_devices/network_devices_screen.dart';
import 'package:rad_mysvcs/services/merged_mode.dart';
import 'package:rad_mysvcs/services/devices_check.dart';
import 'package:rad_mysvcs/services/devices_check_runner.dart';
import 'package:rad_mysvcs/services/merged_devices_check.dart';
import 'package:rad_mysvcs/api/vpn_now_api.dart';
import 'package:rad_mysvcs/models/subscriber.dart';
import 'package:rad_mysvcs/screens/network_devices/device_vitals.dart';

import 'visual_perm/visual_perm_harness.dart';

// لقطات «كل الشركات» في قسم الأجهزة (مؤقّت للمراجعة — لا يُحفظ في المستودع).
const _kA = 'c0000000000aa';
const _kB = 'c0000000000bb';
const _kC = 'c0000000000cc';
const _kE = 'c0000000000ee';

ResponseBody _json(int status, Object body, {Map<String, List<String>> headers = const {}}) =>
    ResponseBody.fromString(jsonEncode(body), status, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
      ...headers,
    });

Map<String, Object?> _dev(int id, String admin, String name, String type, String brand, String ip,
        {String status = 'online', int? region, String? model, String? location, int ms = 4}) =>
    {
      'id': id,
      'admin_id': admin,
      'name': name,
      'type': type,
      'brand': brand,
      'ip': ip,
      'port': 80,
      'protocol': brand == 'ubnt' ? 'api' : (brand == 'vsol' ? 'snmp' : 'api'),
      'last_status': status,
      'last_response_ms': ms,
      'has_credentials': true,
      if (region != null) 'region_id': region,
      if (model != null) 'model': model,
      if (location != null) 'location': location,
      'created_at': '2026-10-01 10:00:00',
    };

final _devicesA = [
  _dev(101, 'supernet:12', 'راوتر المركز', 'router', 'mikrotik', '10.10.1.1', region: 1, model: 'CCR2004-1G-12S+2XS'),
  _dev(102, 'supernet:12', 'سكتر الشمال 1', 'sector', 'ubnt', '10.10.1.21', region: 1, model: 'PrismStation 5AC'),
  _dev(103, 'supernet:12', 'لنك الحيّ', 'link', 'ubnt', '10.10.2.5', model: 'PowerBeam 5AC Gen2', location: 'سطح العمارة'),
];
final _devicesE = [
  _dev(301, 'earthlink:77', 'برج ايرث لنك', 'sector', 'ubnt', '172.16.4.2', model: 'Rocket Prism 5AC'),
  _dev(302, 'earthlink:77', 'راوتر ايرث لنك', 'router', 'mikrotik', '172.16.4.1', model: 'RB4011'),
];
final _devicesB = [
  _dev(201, 'jt:22', 'راوتر الجزيرة', 'router', 'mikrotik', '192.168.88.1', model: 'hAP ac²'),
  _dev(202, 'jt:22', 'سكتر الجزيرة 2', 'sector', 'mikrotik', '192.168.88.20', model: 'mANTBox 52 15s'),
  _dev(203, 'jt:22', 'سويج التوزيع', 'switch', 'cisco', '192.168.88.2', status: 'offline', model: 'Catalyst 2960'),
];

class _Srv implements HttpClientAdapter {
  _Srv(this.inner);
  final HttpClientAdapter inner;

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? rs, Future<void>? cf) async {
    final key = o.headers['x-company-key'] as String?;
    final path = o.uri.path;
    if (key == null) {
      if (path == '/api/v2/admin/devices') return _json(200, {'success': true, 'data': _devicesA});
      if (path == '/api/v2/admin/devices/regions') {
        return _json(200, {
          'success': true,
          'data': [
            {'id': 1, 'name': 'برج المركز', 'color': '#2563EB', 'device_count': 2},
          ],
        });
      }
      return inner.fetch(o, rs, cf);
    }
    final h = {'x-company-key': [key]};
    if (o.method == 'GET' && path == '/api/v2/admin/devices') {
      if (key == _kB) return _json(200, {'success': true, 'data': _devicesB}, headers: h);
      if (key == _kE) return _json(200, {'success': true, 'data': _devicesE}, headers: h);
      return _json(409, {'success': false}, headers: h);
    }
    return _json(409, {'success': false, 'code': 'COMPANY_ROUTE_NOT_ALLOWED'}, headers: h);
  }

  @override
  void close({bool force = false}) {}
}

Map<String, Object?> _companies() => {
      'routing': true,
      'writes': true,
      'companies': [
        {'key': _kA, 'code': 'supernet', 'username': 'mahdi', 'name': 'سوبرنت', 'status': 'ok', 'admin_id': 'supernet:12', 'ns': 'nA', 'currency': 'IQD', 'color_index': 0},
        {'key': _kB, 'code': 'jt', 'username': 'admin@b', 'name': 'الجزيرة', 'status': 'ok', 'admin_id': 'jt:22', 'ns': 'nB', 'currency': 'IQD', 'color_index': 1},
        {'key': _kC, 'code': 'full', 'username': 'admin@full', 'name': 'نور البداية', 'status': 'ok', 'admin_id': 'nbtel:33', 'ns': 'nC', 'currency': 'IQD', 'color_index': 2},
        {'key': _kE, 'code': 'earthlink', 'username': 'admin@e', 'name': 'ايرث لنك', 'status': 'ok', 'admin_id': 'earthlink:77', 'ns': 'nE', 'currency': 'IQD', 'color_index': 3},
        {'key': 'c0000000000dd', 'code': 'x', 'username': 'u', 'name': 'هلا سات', 'status': 'needs_login', 'admin_id': 'hs:44', 'ns': 'nD'},
      ],
    };

void main() {
  setUpAll(visualSetUpAll);
  const devs = [
    VisualDevice('', Size(390, 844), 3),
    VisualDevice('_dark', Size(390, 844), 3, dark: true),
    VisualDevice('_tall', Size(390, 2600), 2),
  ];
  late VisualServer inner;

  Future<void> up() async {
    NetworkDevicesScreen.debugResetView();
    AgentAlertsApi.forget();
    inner = await visualSetUp(s1bSasOwner);
    ApiClient.dio.httpClientAdapter = _Srv(inner);
    AccountApi.tokenSource = ({bool force = false}) async => 'acct';
    MergedMode.reset();
    MergedMode.fetchRaw = () async => Map<String, dynamic>.from(_companies());
    SubscribersApi.clearAllCaches();
    // الفحص بلا شبكة: كلّ جهازٍ يردّ إلّا سويج الجزيرة (ساقطٌ فعلاً: شركته ردّ منها غيره)
    NetworkDevicesApi.debugService = (d) async => d.id == 203
        ? (status: 'offline', responseMs: null, packetLoss: 100.0)
        : (status: 'online', responseMs: 3 + d.id % 7, packetLoss: 0.0);
  }

  Future<void> down(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 25));
    NetworkDevicesApi.debugService = null;
    MergedMode.reset();
    await visualTearDown();
  }

  Future<void> open(WidgetTester t, VisualDevice d) async {
    await up();
    await t.runAsync(() => MergedMode.enter());
    await pumpVisual(t, d, home: (_) => NetworkDevicesScreen(isActive: ValueNotifier<bool>(true)));
    await settle(t, seconds: 4);
  }

  for (final d in devs) {
    testWidgets('all ${d.tag}', (t) async {
      await open(t, d);
      await shoot(t, s1bSasOwner, 'devices_merged_all', d, inner);
      await down(t);
    });

    testWidgets('focus other ${d.tag}', (t) async {
      await open(t, d);
      MergedMode.focus.value = _kB;
      await settle(t, seconds: 1);
      await shoot(t, s1bSasOwner, 'devices_merged_focus_b', d, inner);
      await down(t);
    });

    testWidgets('other device sheet ${d.tag}', (t) async {
      await open(t, d);
      MergedMode.focus.value = _kB;
      await settle(t, seconds: 1);
      await t.tap(find.text('سكتر الجزيرة 2'));
      await settle(t, seconds: 1);
      await shoot(t, s1bSasOwner, 'devices_merged_sheet', d, inner);
      await down(t);
    });

    testWidgets('big cards ${d.tag}', (t) async {
      await open(t, d);
      await t.tap(find.byIcon(LucideIcons.ellipsisVertical));
      await settle(t, seconds: 1);
      await t.tap(find.byKey(const ValueKey('devices-view-big')));
      await settle(t, seconds: 3);
      await shoot(t, s1bSasOwner, 'devices_merged_big', d, inner);
      await down(t);
    });

    testWidgets('big focus other ${d.tag}', (t) async {
      await open(t, d);
      await t.tap(find.byIcon(LucideIcons.ellipsisVertical));
      await settle(t, seconds: 1);
      await t.tap(find.byKey(const ValueKey('devices-view-big')));
      await settle(t, seconds: 2);
      MergedMode.focus.value = _kB;
      await settle(t, seconds: 2);
      await shoot(t, s1bSasOwner, 'devices_merged_big_b', d, inner);
      await down(t);
    });

    testWidgets('deep check ${d.tag}', (t) async {
      await open(t, d);
      // المفتوحة: فحصها المعتاد بقراءةٍ جاهزة؛ والجزيرة من الخادم عبر نفقها؛ وايرث لنك بلا VPN
      DevicesCheckRunner.debugLimits = () async => const CheckLimits();
      DevicesCheckRunner.debugSubscribers = () async => const [];
      DevicesCheckRunner.debugProbe = (x) async => (status: 'online', responseMs: 4, packetLoss: 0.0, serviceOk: true);
      DevicesCheckRunner.debugFetch = (x) async {
        final st = DeviceVitals.fromVpn(x.id == 101
            ? {'kind': 'ros', 'up': 1728000, 'cpu': 21, 'mem': 44, 'temp': 51, 'ppp': 486, 'fw': '7.16.1',
               'pl': [{'n': 'sfp-sfpplus1', 'r': true, 'sp': '10G'}, {'n': 'ether1', 'r': true, 'sp': '1G'}, {'n': 'ether2', 'r': false}]}
            : {'kind': 'airos', 'up': 950000, 'cpu': 18, 'temp': 49, 'sig': -52,
               'peers': [{'n': 'ahmed', 's': -61, 'q': 93, 'tx': 300, 'rx': 270}, {'n': 'zaid', 's': -77, 'q': 48, 'tx': 54, 'rx': 40}]});
        return ProbeResult(vitals: st.vitals ?? const [], detail: st.detail!, counters: const {});
      };
      MergedDevicesCheckRunner.pollEvery = const Duration(milliseconds: 50);
      MergedDevicesCheckRunner.debugRoute = (c) async => c.key == _kB ? MergedVpnRoute.linked : MergedVpnRoute.missing;
      MergedDevicesCheckRunner.debugLimits = (c) async => (limits: const CheckLimits(), complete: true);
      MergedDevicesCheckRunner.debugSubscribers = (c) async => <Subscriber>[];
      MergedDevicesCheckRunner.debugStart = (c) async => (id: 'chk', error: null);
      MergedDevicesCheckRunner.debugPoll = (c, id) async => (
            done: true,
            progress: null,
            result: const VpnNowResult(ok: true, message: 'تم', devices: [
              VpnDeviceResult(id: 201, alive: true, ms: 11, vitals: {
                'kind': 'ros', 'up': 864000, 'cpu': 14, 'mem': 38, 'temp': 47, 'ppp': 212, 'fw': '7.15.3',
                'pl': [{'n': 'ether1', 'r': true, 'sp': '1G'}, {'n': 'ether2', 'r': true, 'sp': '1G'}, {'n': 'ether3', 'r': false}],
              }),
              VpnDeviceResult(id: 202, alive: true, ms: 14, vitals: {
                'kind': 'ros', 'up': 400000, 'cpu': 9, 'temp': 52,
                'peers': [{'n': 'ali', 's': -58, 'q': 91, 'tx': 130, 'rx': 117}, {'n': 'sara', 's': -81, 'q': 39, 'tx': 26, 'rx': 24}],
              }),
              VpnDeviceResult(id: 203, alive: false),
            ]),
          );
      await t.tap(find.byIcon(LucideIcons.ellipsisVertical));
      await settle(t, seconds: 1);
      await t.tap(find.text('فحص شامل'));
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 600)));
      await settle(t, seconds: 3);
      await shoot(t, s1bSasOwner, 'devices_merged_check', d, inner);
      DevicesCheckRunner.debugLimits = null;
      DevicesCheckRunner.debugSubscribers = null;
      DevicesCheckRunner.debugProbe = null;
      DevicesCheckRunner.debugFetch = null;
      MergedDevicesCheckRunner.debugRoute = null;
      MergedDevicesCheckRunner.debugLimits = null;
      MergedDevicesCheckRunner.debugSubscribers = null;
      MergedDevicesCheckRunner.debugStart = null;
      MergedDevicesCheckRunner.debugPoll = null;
      MergedDevicesCheckRunner.pollEvery = const Duration(seconds: 2);
      await down(t);
    });

    testWidgets('add menu ${d.tag}', (t) async {
      await open(t, d);
      await t.tap(find.byIcon(LucideIcons.plus));
      await settle(t, seconds: 1);
      await shoot(t, s1bSasOwner, 'devices_merged_add', d, inner);
      await down(t);
    });
  }
}
