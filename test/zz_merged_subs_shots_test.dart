import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/account_api.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/api/subscribers_api.dart';
import 'package:rad_mysvcs/core/net/vpn_pipe.dart';
import 'package:rad_mysvcs/screens/subscribers/subscribers_screen.dart';
import 'package:rad_mysvcs/screens/subscribers/widgets/filter_chips_bar.dart';
import 'package:rad_mysvcs/services/merged_mode.dart';
import 'package:rad_mysvcs/services/vpn_now.dart';

import 'visual_perm/visual_perm_harness.dart';

// لقطات «فحص المشتركين» في «كل الشركات» عبر الـVPN (مؤقّت للمراجعة — لا يُحفظ في المستودع).
const _kA = 'c0000000000aa';
const _kB = 'c0000000000bb';
const _kE = 'c0000000000ee';

ResponseBody _json(int status, Object body, {Map<String, List<String>> headers = const {}}) =>
    ResponseBody.fromString(jsonEncode(body), status, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
      ...headers,
    });

Map<String, Object?> _row(int i, String user, String first, String last, String parent, {String profile = 'Gold 50M', int days = 12}) => {
      'idx': i,
      'username': user,
      'firstname': first,
      'lastname': last,
      'parent_username': parent,
      'profile_name': profile,
      'remaining_days': days,
      'expiration': '2026-11-${(7 + days).clamp(1, 28)} 00:00:00',
      'enabled': 1,
      'online_status': 1,
    };

final _rows = {
  _kA: [
    _row(1, 'ali.hassan', 'علي', 'حسن', 'mahdi'),
    _row(2, 'zaid.k', 'زيد', 'كاظم', 'mahdi', profile: 'Silver 30M', days: 5),
    _row(3, 'noor.m', 'نور', 'محمد', 'mahdi', days: 21),
  ],
  _kB: [
    _row(1, 'ali.hassan', 'علي', 'حسن الجزيرة', 'admin@b', profile: 'JT 40M', days: 9),
    _row(7, 'sara.j', 'سارة', 'جاسم', 'admin@b', profile: 'JT 40M', days: 2),
  ],
  _kE: [
    _row(4, 'mustafa.a', 'مصطفى', 'عادل', 'admin@e', profile: 'EL 60M', days: 17),
  ],
};

final _results = {
  _kA: {
    'ok': true,
    'message': 'فُحص عبر VPN ✓',
    'detail': '2 بمشكلة',
    'problems': 2,
    'readings': [
      {'u': 'ali.hassan', 'src': 'cpe', 'sig': -82, 'ccq': 41, 'lan': 'ok'},
      {'u': 'zaid.k', 'src': 'cpe', 'sig': -56, 'ccq': 94, 'lan': 'ok'},
      {'u': 'noor.m', 'src': 'cpe', 'sig': -61, 'ccq': 90, 'lan': 'unplugged'},
    ],
  },
  _kB: {
    'ok': true,
    'message': 'فُحص عبر VPN ✓',
    'detail': 'لا مشاكل',
    'problems': 0,
    'readings': [
      {'u': 'ali.hassan', 'src': 'cpe', 'sig': -58, 'ccq': 92, 'lan': 'ok'},
      {'u': 'sara.j', 'src': 'olt', 'rx': -21.4, 't': 46},
    ],
  },
  _kE: {'ok': false, 'reason': 'no_vpn', 'message': 'لا VPN مربوط لحسابك — اربطه من «ربط VPN»'},
};

class _Srv implements HttpClientAdapter {
  _Srv(this.inner);
  final HttpClientAdapter inner;
  final polls = <String, int>{};

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? rs, Future<void>? cf) async {
    final key = o.headers['x-company-key'] as String?;
    final path = o.uri.path;
    if (key == null) {
      if (path == '/api/v2/conn-vpn/route') {
        return _json(200, {'success': true, 'data': {'linked': true, 'via': 'company', 'subscribers': true}});
      }
      return inner.fetch(o, rs, cf);
    }
    final h = {'x-company-key': [key]};
    if (o.method == 'GET' && path == '/api/v2/subscribers') {
      if (o.queryParameters['page'] != null) {
        return _json(200, {'success': true, 'paged': true, 'total': _rows[key]!.length}, headers: h);
      }
      return _json(200, {'success': true, 'data': _rows[key]}, headers: h);
    }
    if (o.method == 'POST' && path == '/api/v2/conn-vpn/check-now') {
      return _json(200, {'success': true, 'data': {'check_id': 'chk-$key'}}, headers: h);
    }
    if (o.method == 'GET' && path.startsWith('/api/v2/conn-vpn/check-now/')) {
      final n = polls[key] = (polls[key] ?? 0) + 1;
      if (n == 1) {
        return _json(200, {'success': true, 'data': {'state': 'running', 'progress': {'phase': 'probing', 'done': 1, 'total': 3}}},
            headers: h);
      }
      return _json(200, {'success': true, 'data': {'state': 'done', 'result': _results[key]}}, headers: h);
    }
    if (o.method == 'GET' && path == '/api/v2/connection-alerts/settings') {
      return _json(200, {'success': true, 'data': {'enabled': true, 'signal_dbm': -70, 'ccq_pct': 50}}, headers: h);
    }
    return _json(200, {'success': true, 'data': []}, headers: h);
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
        {'key': _kE, 'code': 'earthlink', 'username': 'admin@e', 'name': 'ايرث لنك', 'status': 'ok', 'admin_id': 'earthlink:77', 'ns': 'nE', 'currency': 'IQD', 'color_index': 3},
      ],
    };

void main() {
  setUpAll(visualSetUpAll);
  const devs = [
    VisualDevice('', Size(390, 844), 3),
    VisualDevice('_dark', Size(390, 844), 3, dark: true),
  ];
  late VisualServer inner;

  Future<void> open(WidgetTester t, VisualDevice d) async {
    inner = await visualSetUp(s1bSasOwner);
    ApiClient.dio.httpClientAdapter = _Srv(inner);
    AccountApi.tokenSource = ({bool force = false}) async => 'acct';
    MergedMode.reset();
    MergedMode.fetchRaw = () async => Map<String, dynamic>.from(_companies());
    SubscribersApi.clearAllCaches();
    VpnNow.reset();
    VpnNow.pollEvery = const Duration(milliseconds: 5);
    VpnNow.pipeRoute = () async => const PipeRoute.ok('company');
    VpnNow.autoHideAfter = const Duration(hours: 1);
    await t.runAsync(() => MergedMode.enter());
    final cmd = ValueNotifier<SubscriberFilter?>(SubscriberFilter.all);
    await pumpVisual(t, d, home: (_) => SubscribersScreen(filterCmd: cmd));
    await settle(t, seconds: 3);
    // «وضع VPN» شغّال، والفحص (زرّ الرادار) لكلّ الشركات
    VpnNow.mode.value = true;
    await t.runAsync(() => VpnNow.subscribers.run());
    await settle(t, seconds: 2);
  }

  Future<void> down(WidgetTester t) async {
    VpnNow.mode.value = false;
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 6));
    VpnNow.pipeRoute = VpnPipe.route;
    VpnNow.autoHideAfter = const Duration(seconds: 6);
    VpnNow.reset();
    MergedMode.reset();
    await visualTearDown();
  }

  for (final d in devs) {
    testWidgets('subs vpn ${d.tag}', (t) async {
      await open(t, d);
      await shoot(t, s1bSasOwner, 'subs_merged_vpn', d, inner);
      await down(t);
    });

    testWidgets('subs problems ${d.tag}', (t) async {
      await open(t, d);
      await t.tap(find.text('المشاكل'));
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await settle(t, seconds: 1);
      await shoot(t, s1bSasOwner, 'subs_merged_problems', d, inner);
      await down(t);
    });
  }
}
