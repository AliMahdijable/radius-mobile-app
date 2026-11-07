import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/account_api.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/api/company_route.dart';
import 'package:rad_mysvcs/api/subscribers_api.dart';
import 'package:rad_mysvcs/models/merged_company.dart';
import 'package:rad_mysvcs/screens/reports/sessions_report_screen.dart';
import 'package:rad_mysvcs/services/merged_mode.dart';
import 'package:rad_mysvcs/services/merged_report_loader.dart';

import 'visual_perm/visual_perm_harness.dart';

/// «كل الشركات» في تقارير القوائم (٧ نوفمبر): تقرير كلّ شركةٍ بطلبٍ موجَّه لها، وفشلها يُسمّى لا صفرٌ صامت، ونوعٌ لا يخدمه التقرير
/// لا يُطلب ويُسمّى، وربطان للمدير نفسه يُطلبان مرّة.
const _kA = 'c0000000000aa';
const _kB = 'c0000000000bb';
const _kN = 'c0000000000cc'; // شركة مُضافة (kit) — لا جلسات تُوجَّه لها
const _kA2 = 'c0000000000ee'; // ربطٌ ثانٍ لمدير سوبرنت نفسه

ResponseBody _json(int status, Object body, {Map<String, List<String>> headers = const {}}) =>
    ResponseBody.fromString(jsonEncode(body), status, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
      ...headers,
    });

Map<String, Object?> _session(String user, String start, {bool online = true}) => {
      'username': user,
      'framedipaddress': '10.0.0.${user.length}',
      'callingstationid': 'AA:BB:CC:00:00:0${user.length}',
      'acctstarttime': start,
      if (!online) 'acctstoptime': '2026-11-07 23:00:00',
      'acctinputoctets': 1000000,
      'acctoutputoctets': 5000000,
    };

class _Srv implements HttpClientAdapter {
  _Srv(this.inner);
  final HttpClientAdapter inner;
  final asked = <String>[];
  bool failB = false;

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? rs, Future<void>? cf) async {
    final key = o.headers['x-company-key'] as String?;
    final path = o.uri.path;
    asked.add('${o.method} $path ${key ?? '-'}${o.queryParameters['username'] != null ? ' u=${o.queryParameters['username']}' : ''}');
    if (key == null) {
      if (path == '/api/v2/online-users' || path == '/api/v2/sessions') {
        return _json(200, {'success': true, 'data': [_session('open1', '2026-11-07 10:00:00')]});
      }
      return inner.fetch(o, rs, cf);
    }
    final h = {'x-company-key': [key]};
    if (path == '/api/v2/online-users' || path == '/api/v2/sessions') {
      if (key == _kB && failB) return _json(409, {'success': false, 'message': 'انتهت جلسة «الجزيرة» — افتحها من «شركاتي»'}, headers: h);
      final rows = key == _kA
          ? [_session('ali', '2026-11-07 09:00:00'), _session('zaid', '2026-11-07 12:00:00')]
          : [_session('ali', '2026-11-07 11:00:00')];
      return _json(200, {'success': true, 'data': rows}, headers: h);
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
        {'key': _kA, 'code': 'supernet', 'username': 'mahdi', 'name': 'سوبرنت', 'status': 'ok', 'admin_id': '2', 'ns': 'nA', 'currency': 'IQD', 'color_index': 0},
        {'key': _kB, 'code': 'jt', 'username': 'admin@b', 'name': 'الجزيرة', 'status': 'ok', 'admin_id': 'jt:22', 'ns': 'nB', 'currency': 'IQD', 'color_index': 1},
        {'key': _kN, 'code': 'nabd', 'username': 'n', 'name': 'نبض', 'provider': 'kit', 'status': 'ok', 'admin_id': 'nabd:5', 'ns': 'nN', 'currency': 'IQD', 'color_index': 2},
        if (twin) {'key': _kA2, 'code': 'supernet', 'username': 'mahdi2', 'name': 'سوبرنت ٢', 'status': 'ok', 'admin_id': '2', 'ns': 'nA', 'currency': 'IQD', 'color_index': 4},
        {'key': 'c0000000000dd', 'code': 'hs', 'username': 'u', 'name': 'هلا سات', 'status': 'needs_login', 'admin_id': 'hs:44', 'ns': 'nD'},
      ],
    };

void main() {
  setUpAll(visualSetUpAll);
  late _Srv srv;

  Future<void> up({bool twin = false}) async {
    final inner = await visualSetUp(s1bSasOwner);
    srv = _Srv(inner);
    ApiClient.dio.httpClientAdapter = srv;
    AccountApi.tokenSource = ({bool force = false}) async => 'acct';
    MergedMode.reset();
    MergedMode.fetchRaw = () async => Map<String, dynamic>.from(_companies(twin: twin));
    SubscribersApi.clearAllCaches();
  }

  Future<void> down(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 3));
    MergedMode.reset();
    await visualTearDown();
  }

  testWidgets('المحمّل: كلّ شركةٍ بمفتاحها، المتعذّرة تُسمّى بسببها، والتي لا يخدمها التقرير لا تُطلب، والربط الثاني مرّة', (t) async {
    await up(twin: true);
    srv.failB = true;
    await t.runAsync(() => MergedMode.enter());
    late MergedReport<String> r;
    await t.runAsync(() async {
      r = await loadMergedReport<String>(
        supports: (c) => c.provider == MergedProvider.sas4,
        fetch: (c) async {
          expect(CompanyRoute.currentKey, c.key, reason: 'كلّ نداءٍ داخل نطاق شركته');
          if (c.key == _kB) return (ok: false, rows: const <String>[], error: 'انتهت جلسة «الجزيرة»', note: null);
          return (ok: true, rows: ['${c.name}-1', '${c.name}-2'], error: null, note: c.key == _kA ? 'سجلٌّ ناقص' : null);
        },
      );
    });
    expect(r.parts.map((p) => p.company.key), [_kA, _kB, _kN], reason: 'الربط الثاني لمدير سوبرنت لا يُطلب');
    expect(r.partOf(_kA2)?.company.key, _kA, reason: 'ويُقرأ من أصله');
    expect(r.partOf(_kB)?.ok, isFalse);
    expect(r.partOf(_kN)?.unsupported, isTrue);
    expect(r.total, 2);
    expect(r.rowsFor(null).map((e) => e.key), [_kA, _kA]);
    expect(r.rowsFor(_kB), isEmpty);
    final note = r.noteFor(null, unsupportedText: 'لا تقرير لنوعها', missingText: 'لا تظهر هنا: هلا سات')!;
    expect(note, contains('«سوبرنت»: سجلٌّ ناقص'));
    expect(note, contains('«الجزيرة»: انتهت جلسة «الجزيرة»'));
    expect(note, contains('«نبض»: لا تقرير لنوعها'));
    expect(note, contains('لا تظهر هنا: هلا سات'));
    expect(r.noteFor(_kB, unsupportedText: '-', missingText: '-'), '«الجزيرة»: انتهت جلسة «الجزيرة»');
    await down(t);
  });

  testWidgets('الجلسات في «كل الشركات»: الشاشة نفسها بشريط الشركات، وكلّ جلسةٍ بشركتها، والمختارة وحدها', (t) async {
    await up();
    await t.runAsync(() => MergedMode.enter());
    await pumpVisual(t, const VisualDevice('', Size(390, 1400), 1), home: (_) => const SessionsReportScreen());
    await settle(t, seconds: 3);
    final routed = srv.asked.where((a) => a.startsWith('GET /api/v2/online-users c')).toList();
    expect(routed, ['GET /api/v2/online-users $_kA', 'GET /api/v2/online-users $_kB'], reason: 'نبض لا تُطلب');
    expect(find.text('كل الشركات · 3'), findsOneWidget);
    expect(find.text('ali'), findsNWidgets(2), reason: 'اليوزر نفسه من شركتين ⇒ صفّان');
    expect(find.text('zaid'), findsOneWidget);
    expect(find.textContaining('«نبض»: لا تقرير جلساتٍ لنوعها'), findsOneWidget);
    expect(find.text('open1'), findsNothing, reason: 'لا طلبٌ للمفتوحة بلا مفتاح في الوضع');
    MergedMode.focus.value = _kB;
    await settle(t, seconds: 1);
    expect(find.text('ali'), findsOneWidget);
    expect(find.text('zaid'), findsNothing);
    await down(t);
  });

  testWidgets('«سجلّ الجلسات» لمشتركٍ من شركةٍ أخرى: يُطلب من شركته وحدها بمفتاحها', (t) async {
    await up();
    await t.runAsync(() => MergedMode.enter());
    await pumpVisual(t, const VisualDevice('', Size(390, 1000), 1),
        home: (_) => const SessionsReportScreen(initialUsername: 'ali', companyKey: _kB));
    await settle(t, seconds: 3);
    expect(srv.asked.where((a) => a.contains('/api/v2/sessions')), ['GET /api/v2/sessions $_kB u=ali']);
    expect(find.text('كل الشركات · 3'), findsNothing, reason: 'سجلّ مشتركٍ واحد — لا شريط');
    await down(t);
  });
}
