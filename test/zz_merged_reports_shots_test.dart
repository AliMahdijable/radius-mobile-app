import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/account_api.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/api/subscribers_api.dart';
import 'package:rad_mysvcs/screens/el/el_reports.dart';
import 'package:rad_mysvcs/screens/reports/activations_report_screen.dart';
import 'package:rad_mysvcs/screens/reports/activity_log_report_screen.dart';
import 'package:rad_mysvcs/screens/reports/daily_activations_report_screen.dart';
import 'package:rad_mysvcs/screens/reports/package_distribution_screen.dart';
import 'package:rad_mysvcs/screens/reports/reports_hub_screen.dart';
import 'package:rad_mysvcs/screens/reports/sessions_report_screen.dart';
import 'package:rad_mysvcs/services/merged_mode.dart';

import 'visual_perm/visual_perm_harness.dart';

// لقطات تقارير «كل الشركات» (مؤقّت للمراجعة — لا يُحفظ في المستودع).
const _kA = 'c0000000000aa';
const _kB = 'c0000000000bb';
const _kE = 'c0000000000ee';
const _kN = 'c0000000000cc';

ResponseBody _json(int status, Object body, {Map<String, List<String>> headers = const {}}) =>
    ResponseBody.fromString(jsonEncode(body), status, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
      ...headers,
    });

Map<String, Object?> _session(String user, String ip, String start, String manager, {int down = 0, int up = 0}) => {
      'username': user,
      'framedipaddress': ip,
      'callingstationid': 'A4:2B:B0:${user.length.toString().padLeft(2, '0')}:1C:7E',
      'acctstarttime': start,
      'user_manager': manager,
      'acctinputoctets': up,
      'acctoutputoctets': down,
    };

final _sessions = {
  _kA: [
    _session('ali.hassan', '100.64.12.4', '2026-11-07 08:12:00', 'mahdi', down: 2400000000, up: 310000000),
    _session('noor.m', '100.64.12.9', '2026-11-07 19:40:00', 'mahdi', down: 820000000, up: 64000000),
    _session('zaid.k', '100.64.13.21', '2026-11-07 21:05:00', 'mahdi', down: 150000000, up: 9000000),
  ],
  _kB: [
    _session('ali.hassan', '10.70.4.18', '2026-11-07 17:30:00', 'admin@b', down: 3100000000, up: 420000000),
    _session('sara.j', '10.70.4.33', '2026-11-07 20:15:00', 'admin@b', down: 640000000, up: 51000000),
  ],
};

class _Srv implements HttpClientAdapter {
  _Srv(this.inner);
  final HttpClientAdapter inner;

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? rs, Future<void>? cf) async {
    final key = o.headers['x-company-key'] as String?;
    final path = o.uri.path;
    if (key == null) return inner.fetch(o, rs, cf);
    final h = {'x-company-key': [key]};
    if (path == '/api/v2/el/by-package' && key == _kE) {
      return _json(200, {'success': true, 'data': [
        {'name': 'FTTH 35M', 'count': 412}, {'name': 'FTTH 50M', 'count': 268}, {'name': 'FTTH 75M', 'count': 97}, {'name': 'FTTH 100M', 'count': 41},
      ]}, headers: h);
    }
    if (path == '/api/reports/finance/packages') {
      if (key == _kE) return _json(409, {'success': false, 'message': 'انتهت جلسة «ايرث لنك» — افتحها من «شركاتي»'}, headers: h);
      Map<String, Object?> row(String name, int acts, int ext, int price, int subs, int active, {int? unit, bool exempt = false}) {
        final revenue = (acts + ext) * price;
        final cost = exempt || unit == null ? null : (acts + ext) * unit;
        return {
          'key': 'p-$name', 'name': name, 'price': price, 'activations': acts, 'extensions': ext, 'revenue': revenue,
          'subscribers_total': subs, 'subscribers_active': active, 'unit_cost': unit, 'cost': cost, 'cost_exempt': exempt,
          'profit_total': exempt ? revenue : (cost == null ? null : revenue - cost),
          'profit_estimated': exempt ? active * price : (unit == null ? null : active * (price - unit)),
        };
      }
      final exempt = key == _kA;
      final rows = switch (key) {
        _kA => [row('Gold 50M', 38, 12, 25000, 410, 352, exempt: true), row('Silver 30M', 21, 6, 20000, 260, 214, exempt: true)],
        _kB => [row('JT 40M', 17, 4, 30000, 190, 168, unit: 21000), row('JT 80M', 6, 1, 45000, 64, 55, unit: 33000)],
        _kN => [row('NABD 25M', 9, 2, 18000, 88, 71, unit: 12500)],
        _ => <Map<String, Object?>>[],
      };
      num sum(String k) => rows.fold<num>(0, (s, r) => s + ((r[k] as num?) ?? 0));
      return _json(200, {
        'success': true,
        'data': {
          'owner': true,
          'cost_exempt': exempt,
          'rows': rows,
          'totals': {
            'packages': rows.length, 'activations': sum('activations'), 'extensions': sum('extensions'), 'revenue': sum('revenue'),
            'subscribers_total': sum('subscribers_total'), 'subscribers_active': sum('subscribers_active'),
            'cost': exempt ? null : sum('cost'), 'profit_total': sum('profit_total'), 'profit_estimated': sum('profit_estimated'),
            'cost_complete': true,
          },
        },
      }, headers: h);
    }
    if (path == '/api/activities') {
      if (key == _kE) return _json(409, {'success': false, 'message': 'انتهت جلسة «ايرث لنك» — افتحها من «شركاتي»'}, headers: h);
      final today = DateTime.now().toIso8601String().substring(0, 10);
      var seq = 0;
      Map<String, Object?> act(String desc, int price, String hm,
              {String type = 'SUBSCRIBER_ACTIVATE', String user = 'ali.hassan', String name = 'علي حسن'}) =>
          {
            'id': '${key.hashCode % 997}${seq++}',
            'action_type': type,
            'action_description': desc,
            'action_data': jsonEncode({'final_price': price}),
            'amount': price,
            'user_username': user,
            'user_firstname': name.split(' ').first,
            'user_lastname': name.split(' ').skip(1).join(' '),
            'admin_username': key == _kA ? 'mahdi' : 'admin',
            'created_at': '$today $hm:00',
          };
      final rows = switch (key) {
        _kA => [
            act('تفعيل نقدي — Gold 50M', 25000, '09:10'),
            act('تفعيل نقدي — Silver 30M', 20000, '11:45', user: 'zaid.k', name: 'زيد كاظم'),
            act('تسديد دين — 10,000', 10000, '12:30', type: 'DEBT_PAY', user: 'noor.m', name: 'نور محمد'),
            act('تفعيل نقدي — Gold 50M', 25000, '13:20', user: 'noor.m', name: 'نور محمد'),
            act('تفعيل غير نقدي — Gold 50M', 25000, '16:05', user: 'hussein.a', name: 'حسين علي'),
          ],
        _kB => [
            act('تفعيل نقدي — JT 40M', 30000, '10:30', user: 'sara.j', name: 'سارة جاسم'),
            act('تفعيل غير نقدي — JT 40M', 30000, '18:40', user: 'ali.hassan', name: 'علي حسن'),
          ],
        _kN => [act('تفعيل نقدي — NABD 25M', 18000, '12:00', user: 'mustafa.a', name: 'مصطفى عادل')],
        _ => <Map<String, Object?>>[],
      };
      return _json(200, {'success': true, 'data': rows}, headers: h);
    }
    if (path == '/api/v2/online-users' || path == '/api/v2/sessions') {
      if (key == _kE) return _json(409, {'success': false, 'message': 'انتهت جلسة «ايرث لنك» — افتحها من «شركاتي»'}, headers: h);
      return _json(200, {'success': true, 'data': _sessions[key] ?? const []}, headers: h);
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
        {'key': _kE, 'code': 'earthlink', 'provider': 'earthlink', 'username': 'admin@e', 'name': 'ايرث لنك', 'status': 'ok', 'admin_id': 'earthlink:77', 'ns': 'nE', 'currency': 'IQD', 'color_index': 3},
        {'key': _kN, 'code': 'nabd', 'provider': 'kit', 'username': 'n', 'name': 'نبض', 'status': 'ok', 'admin_id': 'nabd:5', 'ns': 'nN', 'currency': 'IQD', 'color_index': 2},
      ],
    };

void main() {
  setUpAll(visualSetUpAll);
  const devs = [
    VisualDevice('', Size(390, 844), 3),
    VisualDevice('_dark', Size(390, 844), 3, dark: true),
    VisualDevice('_tall', Size(390, 2400), 2),
  ];
  late VisualServer inner;

  Future<void> open(WidgetTester t, VisualDevice d, Widget Function() home) async {
    inner = await visualSetUp(s1bSasOwner);
    ApiClient.dio.httpClientAdapter = _Srv(inner);
    AccountApi.tokenSource = ({bool force = false}) async => 'acct';
    MergedMode.reset();
    MergedMode.fetchRaw = () async => Map<String, dynamic>.from(_companies());
    SubscribersApi.clearAllCaches();
    await t.runAsync(() => MergedMode.enter());
    await pumpVisual(t, d, home: (_) => home());
    await settle(t, seconds: 3);
  }

  Future<void> down(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 3));
    MergedMode.reset();
    await visualTearDown();
  }

  for (final d in devs) {
    testWidgets('sessions ${d.tag}', (t) async {
      await open(t, d, () => const SessionsReportScreen());
      await shoot(t, s1bSasOwner, 'rep_sessions', d, inner);
      await down(t);
    });

    testWidgets('daily ${d.tag}', (t) async {
      await open(t, d, () => const DailyActivationsReportScreen());
      await shoot(t, s1bSasOwner, 'rep_daily', d, inner);
      MergedMode.focus.value = _kA;
      await settle(t, seconds: 1);
      await shoot(t, s1bSasOwner, 'rep_daily_focus', d, inner);
      await down(t);
    });

    testWidgets('activations ${d.tag}', (t) async {
      await open(t, d, () => const ActivationsReportScreen());
      await shoot(t, s1bSasOwner, 'rep_acts', d, inner);
      await down(t);
    });

    testWidgets('activity ${d.tag}', (t) async {
      await open(t, d, () => const ActivityLogReportScreen());
      await shoot(t, s1bSasOwner, 'rep_log', d, inner);
      await down(t);
    });

    testWidgets('packages ${d.tag}', (t) async {
      await open(t, d, () => const PackageDistributionScreen());
      await shoot(t, s1bSasOwner, 'rep_pkgs', d, inner);
      await down(t);
    });

    testWidgets('el packages ${d.tag}', (t) async {
      await open(t, d, () => const ElByPackageScreen());
      await shoot(t, s1bSasOwner, 'rep_el_pkgs', d, inner);
      await down(t);
    });

    testWidgets('hub ${d.tag}', (t) async {
      await open(t, d, () => const ReportsHubScreen());
      await shoot(t, s1bSasOwner, 'rep_hub', d, inner);
      await down(t);
    });
  }
}
