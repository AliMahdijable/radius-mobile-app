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
import 'package:rad_mysvcs/screens/el/el_reports.dart';
import 'package:rad_mysvcs/screens/reports/activations_report_screen.dart';
import 'package:rad_mysvcs/screens/reports/activity_log_report_screen.dart';
import 'package:rad_mysvcs/screens/reports/daily_activations_report_screen.dart';
import 'package:rad_mysvcs/screens/reports/package_distribution_screen.dart';
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
const _kU = 'c0000000000ff'; // ساسٌ بعيد لم تُقرأ عملته (currency null)
const _kL1 = 'c00000000e101'; // ايرث لنك (حسابان)
const _kL2 = 'c00000000e102';

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
    asked.add('${o.method} $path ${key ?? '-'}${o.queryParameters['username'] != null ? ' u=${o.queryParameters['username']}' : ''}'
        '${o.queryParameters['user_ids'] != null ? ' ids=${o.queryParameters['user_ids']}' : ''}');
    if (key == null) {
      if (path == '/api/v2/online-users' || path == '/api/v2/sessions') {
        return _json(200, {'success': true, 'data': [_session('open1', '2026-11-07 10:00:00')]});
      }
      return inner.fetch(o, rs, cf);
    }
    final h = {'x-company-key': [key]};
    if (path == '/api/v2/el/by-package') {
      final rows = key == _kL1
          ? [{'name': 'FTTH 50M', 'count': 30}, {'name': 'FTTH 100M', 'count': 5}]
          : [{'name': 'FTTH 50M', 'count': 12}];
      return _json(200, {'success': true, 'data': rows}, headers: h);
    }
    if (path == '/api/v2/el/test-usage') {
      final rows = key == _kL1 ? [{'name': 'تجربة ١', 'username': 't1@el'}] : [{'name': 'تجربة ٢', 'username': 't2@el'}];
      return _json(200, {'success': true, 'data': rows}, headers: h);
    }
    if (path == '/api/reports/finance/packages') {
      Map<String, Object?> rep(String name, int acts, int revenue, {int? cost, bool exempt = false, bool unknown = false}) {
        final profit = unknown ? null : (exempt ? revenue : revenue - (cost ?? 0));
        return {
          'success': true,
          'data': {
            'owner': true,
            'cost_exempt': exempt,
            'rows': [
              {'key': 'p-$name', 'name': name, 'activations': acts, 'revenue': revenue, 'subscribers_total': acts * 10,
                'subscribers_active': acts * 8, 'cost': unknown ? null : cost, 'profit_total': profit, 'cost_exempt': exempt},
            ],
            'totals': {'packages': 1, 'activations': acts, 'extensions': 0, 'revenue': revenue, 'subscribers_total': acts * 10,
              'subscribers_active': acts * 8, 'cost': unknown ? null : cost, 'profit_total': profit},
          },
        };
      }
      final body = switch (key) {
        _kA => rep('Gold 50M', 4, 100000, exempt: true),
        _kB => rep('JT 40M', 2, 60000, cost: 40000),
        _kU => rep('XS 20M', 1, 15000, unknown: true),
        _ => {'success': false, 'message': 'لا تقرير'},
      };
      return _json(200, body, headers: h);
    }
    if (path == '/api/activities') {
      final today = DateTime.now().toIso8601String().substring(0, 10);
      var seq = 0;
      Map<String, Object?> act(String desc, int price, {String type = 'SUBSCRIBER_ACTIVATE'}) => {
            'id': '${key.hashCode % 1000}${seq++}',
            'action_type': type,
            'action_description': desc,
            'action_data': jsonEncode({'final_price': price}),
            'amount': price,
            'user_username': 'u$seq',
            'created_at': '$today 1$seq:00:00',
          };
      final rows = switch (key) {
        _kA => [act('تفعيل نقدي', 10000), act('تفعيل نقدي', 15000), act('تفعيل غير نقدي', 30000), act('دخول المدير', 0, type: 'ADMIN_LOGIN')],
        _kB => [act('تفعيل نقدي', 20000)],
        _kU => [act('تفعيل نقدي', 5000)],
        _ => <Map<String, Object?>>[],
      };
      return _json(200, {'success': true, 'data': rows}, headers: h);
    }
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

Map<String, Object?> _companies({bool twin = false, bool unknownCurrency = false, bool earthlink = false}) => {
      'routing': true,
      'writes': true,
      'companies': [
        {'key': _kA, 'code': 'supernet', 'username': 'mahdi', 'name': 'سوبرنت', 'status': 'ok', 'admin_id': '2', 'ns': 'nA', 'currency': 'IQD', 'color_index': 0},
        {'key': _kB, 'code': 'jt', 'username': 'admin@b', 'name': 'الجزيرة', 'status': 'ok', 'admin_id': 'jt:22', 'ns': 'nB', 'currency': 'IQD', 'color_index': 1},
        {'key': _kN, 'code': 'nabd', 'username': 'n', 'name': 'نبض', 'provider': 'kit', 'status': 'ok', 'admin_id': 'nabd:5', 'ns': 'nN', 'currency': 'IQD', 'color_index': 2},
        if (earthlink) {'key': _kL1, 'code': 'earthlink', 'provider': 'earthlink', 'username': 'el1', 'name': 'ايرث لنك ١', 'status': 'ok', 'admin_id': 'earthlink:31', 'ns': 'nL1', 'currency': 'IQD', 'color_index': 6},
        if (earthlink) {'key': _kL2, 'code': 'earthlink', 'provider': 'earthlink', 'username': 'el2', 'name': 'ايرث لنك ٢', 'status': 'ok', 'admin_id': 'earthlink:32', 'ns': 'nL2', 'currency': 'IQD', 'color_index': 7},
        if (unknownCurrency) {'key': _kU, 'code': 'xs', 'username': 'x', 'name': 'اكس نت', 'status': 'ok', 'admin_id': 'xs:9', 'ns': 'nU', 'currency': null, 'color_index': 5},
        if (twin) {'key': _kA2, 'code': 'supernet', 'username': 'mahdi2', 'name': 'سوبرنت ٢', 'status': 'ok', 'admin_id': '2', 'ns': 'nA', 'currency': 'IQD', 'color_index': 4},
        {'key': 'c0000000000dd', 'code': 'hs', 'username': 'u', 'name': 'هلا سات', 'status': 'needs_login', 'admin_id': 'hs:44', 'ns': 'nD'},
      ],
    };

void main() {
  setUpAll(visualSetUpAll);
  late _Srv srv;

  Future<void> up({bool twin = false, bool unknownCurrency = false, bool earthlink = false}) async {
    final inner = await visualSetUp(s1bSasOwner);
    srv = _Srv(inner);
    ApiClient.dio.httpClientAdapter = srv;
    AccountApi.tokenSource = ({bool force = false}) async => 'acct';
    MergedMode.reset();
    MergedMode.fetchRaw = () async =>
        Map<String, dynamic>.from(_companies(twin: twin, unknownCurrency: unknownCurrency, earthlink: earthlink));
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

  testWidgets('التفعيلات اليومية: كلّ شركةٍ بنطاقها، سطرٌ لكلّ شركة، والنقد بالدينار وحده (المجهولة تُسمّى خارج المجموع)', (t) async {
    await up(unknownCurrency: true);
    await t.runAsync(() => MergedMode.enter());
    await pumpVisual(t, const VisualDevice('', Size(390, 1600), 1), home: (_) => const DailyActivationsReportScreen());
    await settle(t, seconds: 3);
    final acts = srv.asked.where((a) => a.startsWith('GET /api/activities c')).toList();
    expect(acts.toSet(), {
      'GET /api/activities $_kA ids=2',
      'GET /api/activities $_kB ids=jt:22',
      'GET /api/activities $_kN ids=nabd:5',
      'GET /api/activities $_kU ids=xs:9',
    }, reason: 'كلّ شركةٍ بمفتاحها ونطاقها هي (معرّف مديرها) — لا نطاق المفتوحة');
    // العدد: سوبرنت 3 + الجزيرة 1 + اكس نت 1 = 5؛ النقد: 10,000 + 15,000 + 20,000 = 45,000 (نقد اكس نت 5,000 خارجه)
    expect(find.text('5'), findsWidgets);
    expect(find.text('45,000'), findsOneWidget);
    expect(find.textContaining('نقد «اكس نت»'), findsOneWidget);
    expect(find.byKey(const ValueKey('daily-company-$_kA')), findsOneWidget);
    expect(find.byKey(const ValueKey('daily-company-$_kB')), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('daily-company-$_kB')));
    await settle(t, seconds: 1);
    expect(MergedMode.focus.value, _kB);
    expect(find.text('20,000'), findsOneWidget, reason: 'الجزيرة وحدها');
    await down(t);
  });

  testWidgets('التفعيلات: كلّ شركةٍ بنطاقها، «حسب الشركة»، الإيراد بالدينار وحده، وشارة الشركة فوق الحركة', (t) async {
    await up(unknownCurrency: true);
    await t.runAsync(() => MergedMode.enter());
    await pumpVisual(t, const VisualDevice('', Size(390, 2400), 1), home: (_) => const ActivationsReportScreen());
    await settle(t, seconds: 3);
    expect(srv.asked.where((a) => a.startsWith('GET /api/activities c')).length, 4);
    // سوبرنت 3 (بلا «دخول المدير») + الجزيرة 1 + اكس نت 1 = 5؛ الإيراد النقديّ: 10,000 + 15,000 + 20,000 = 45,000
    expect(find.text('45,000'), findsOneWidget);
    expect(find.byKey(const ValueKey('merged-breakdown')), findsOneWidget);
    expect(find.byKey(const ValueKey('merged-breakdown-$_kU')), findsOneWidget);
    expect(find.textContaining('خارج المجموع'), findsWidgets);
    expect(find.textContaining('إيراد «اكس نت»'), findsOneWidget, reason: 'سطر الشريط يسمّيها');
    await t.tap(find.byKey(const ValueKey('merged-breakdown-$_kB')));
    await settle(t, seconds: 1);
    expect(MergedMode.focus.value, _kB);
    expect(find.text('20,000'), findsWidgets);
    expect(find.byKey(const ValueKey('merged-breakdown')), findsNothing, reason: 'الشركة المختارة وحدها');
    await down(t);
  });

  testWidgets('سجلّ النشاط: الحركات من كلّ شركةٍ بنطاقها، والصرفيات لا تُخلط (ولا تُطلب) ويقول السطر ذلك', (t) async {
    await up();
    await t.runAsync(() => MergedMode.enter());
    await pumpVisual(t, const VisualDevice('', Size(390, 2400), 1), home: (_) => const ActivityLogReportScreen());
    await settle(t, seconds: 3);
    expect(srv.asked.where((a) => a.startsWith('GET /api/activities c')).toSet(), {
      'GET /api/activities $_kA ids=2',
      'GET /api/activities $_kB ids=jt:22',
      'GET /api/activities $_kN ids=nabd:5',
    });
    expect(srv.asked.where((a) => a.contains('/api/admin/expenses')), isEmpty);
    expect(find.textContaining('الصرفيات لا تُخلط هنا'), findsOneWidget);
    expect(find.textContaining('دخول المدير'), findsOneWidget, reason: 'السجلّ كلّه لا التفعيلات وحدها');
    await down(t);
  });

  testWidgets('توزيع الباقات: الربح مجموع ربح كلّ شركةٍ بقاعدتها، ومن لا يُعرف ربحها تُسمّى، والمختارة تقريرها بلا طلبٍ جديد', (t) async {
    await up(unknownCurrency: true);
    await t.runAsync(() => MergedMode.enter());
    await pumpVisual(t, const VisualDevice('', Size(390, 2600), 1), home: (_) => const PackageDistributionScreen());
    await settle(t, seconds: 3);
    final asked = srv.asked.where((a) => a.startsWith('GET /api/reports/finance/packages c')).toList();
    expect(asked.toSet(), {
      'GET /api/reports/finance/packages $_kA ids=2',
      'GET /api/reports/finance/packages $_kB ids=jt:22',
      'GET /api/reports/finance/packages $_kN ids=nabd:5',
      'GET /api/reports/finance/packages $_kU ids=xs:9',
    });
    // الإيراد: سوبرنت 100,000 + الجزيرة 60,000 (اكس نت بعملةٍ مجهولة خارجه)؛ الربح: 100,000 (المعفاة = إيرادها) + 20,000
    expect(find.text('160,000 د.ع'), findsOneWidget);
    expect(find.text('120,000 د.ع'), findsOneWidget);
    expect(find.textContaining('لا يشمل: نبض، اكس نت'), findsWidgets, reason: 'نبض تعذّر تقريرها واكس نت بلا ربحٍ معروف ⇒ تُسمّيان');
    expect(find.byKey(const ValueKey('merged-breakdown')), findsOneWidget);
    expect(find.text('Gold 50M'), findsOneWidget);
    expect(find.text('JT 40M'), findsOneWidget);
    final before = srv.asked.length;
    MergedMode.focus.value = _kB;
    await settle(t, seconds: 1);
    expect(srv.asked.length, before, reason: 'المختارة من الجمع المحفوظ — بلا طلب');
    expect(find.text('Gold 50M'), findsNothing);
    expect(find.text('JT 40M'), findsOneWidget);
    await down(t);
  });

  testWidgets('تقارير ايرث لنك: شركات ايرث لنك وحدها بمفاتيحها، والباقة باسمها مجموعة منها، وغيرها «ليست ايرث لنك»', (t) async {
    await up(earthlink: true);
    await t.runAsync(() => MergedMode.enter());
    await pumpVisual(t, const VisualDevice('', Size(390, 1600), 1), home: (_) => const ElByPackageScreen());
    await settle(t, seconds: 3);
    expect(srv.asked.where((a) => a.startsWith('GET /api/v2/el/by-package')).toSet(),
        {'GET /api/v2/el/by-package $_kL1', 'GET /api/v2/el/by-package $_kL2'});
    expect(find.text('FTTH 50M'), findsOneWidget, reason: 'الباقة نفسها من الحسابين سطرٌ واحد');
    expect(find.text('42 مشترك'), findsOneWidget, reason: '30 + 12');
    expect(find.textContaining('ليست ايرث لنك'), findsWidgets, reason: 'على شارات الشركات الأخرى');
    expect(find.textContaining('«سوبرنت»: ليست ايرث لنك'), findsNothing, reason: 'لا ضجيج في سطر الشريط');
    MergedMode.focus.value = _kL2;
    await settle(t, seconds: 1);
    expect(find.text('12 مشترك'), findsWidgets);
    expect(find.text('FTTH 100M'), findsNothing);
    await down(t);
  });

  testWidgets('استخدام التجريبيّ: مشتركو الحسابين بشارة شركتهم', (t) async {
    await up(earthlink: true);
    await t.runAsync(() => MergedMode.enter());
    await pumpVisual(t, const VisualDevice('', Size(390, 1600), 1), home: (_) => const ElTestUsageScreen());
    await settle(t, seconds: 3);
    expect(find.text('تجربة ١'), findsOneWidget);
    expect(find.text('تجربة ٢'), findsOneWidget);
    expect(find.text('ايرث لنك ١'), findsWidgets);
    await down(t);
  });
}
