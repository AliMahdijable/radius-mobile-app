import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/core/net/vpn_pipe.dart';
import 'package:rad_mysvcs/models/merged_company.dart';
import 'package:rad_mysvcs/models/subscriber.dart';
import 'package:rad_mysvcs/screens/subscribers/widgets/subscriber_card_v3.dart';
import 'package:rad_mysvcs/services/merged_mode.dart';
import 'package:rad_mysvcs/services/vpn_now.dart';
import 'package:rad_mysvcs/widgets/vpn_problems_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'visual_perm/visual_perm_harness.dart';

/// «فحص المشتركين» في «كل الشركات» (٧ نوفمبر): فحص الـVPN نفسه (الشريط والزرّ والوضع) لكلّ شركةٍ في النطاق واحدةً بعد واحدة —
/// كلّ طلبٍ بمفتاح شركته، وقراءات كلّ شركةٍ في مكانها (اليوزر نفسه في شركتين لا يختلط)، ومن لم تُفحص تُسمّى بسببها.
const _kA = 'c0000000000aa';
const _kB = 'c0000000000bb';
const _kE = 'c0000000000ee';

class _Srv implements HttpClientAdapter {
  final asked = <String>[];
  final polls = <String, int>{};
  Map<String, Map<String, dynamic>> results = {};
  Map<String, Map<String, dynamic>> limits = {};

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? body, Future<void>? cancel) async {
    final key = o.headers['x-company-key'] as String? ?? '-';
    asked.add('${o.method} ${o.path} $key');
    // الموجَّه يُعاد مفتاحه بالردّ (يتحقّق منه ApiClient)
    ResponseBody _json(int s, Object b) => ResponseBody.fromString(jsonEncode(b), s, headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
          if (key != '-') 'x-company-key': [key],
        });
    if (o.method == 'POST' && o.path.endsWith('/check-now')) {
      return _json(200, {'success': true, 'data': {'check_id': 'chk-$key', 'state': 'running'}});
    }
    if (o.method == 'GET' && o.path.contains('/check-now/')) {
      final id = o.path.split('/').last;
      expect(id, 'chk-$key', reason: 'نتيجة الفحص تُسأل بمفتاح الشركة نفسها');
      final n = polls[key] = (polls[key] ?? 0) + 1;
      if (n == 1) {
        return _json(200, {'success': true, 'data': {'state': 'running', 'progress': {'phase': 'probing', 'done': 5, 'total': 10}}});
      }
      return _json(200, {'success': true, 'data': {'state': 'done', 'result': results[key]}});
    }
    if (o.method == 'GET' && o.path == '/api/v2/connection-alerts/settings' && limits[key] != null) {
      return _json(200, {'success': true, 'data': limits[key]});
    }
    return _json(404, {'success': false});
  }

  @override
  void close({bool force = false}) {}
}

Map<String, dynamic> _ok(List<Map<String, dynamic>> readings, int problems) => {
      'ok': true,
      'message': 'فُحص عبر VPN ✓',
      'detail': problems > 0 ? '$problems بمشكلة' : 'لا مشاكل',
      'problems': problems,
      'readings': readings,
    };

final _companiesRaw = {
  'routing': true,
  'writes': true,
  'companies': [
    {'key': _kA, 'code': 'supernet', 'username': 'u0', 'name': 'سوبرنت', 'status': 'ok', 'admin_id': '2', 'ns': 'a', 'color_index': 0},
    {'key': _kB, 'code': 'jt', 'username': 'u1', 'name': 'الجزيرة', 'status': 'ok', 'admin_id': 'jt:22', 'ns': 'b', 'color_index': 1},
    {'key': _kE, 'code': 'earthlink', 'username': 'u3', 'name': 'ايرث لنك', 'status': 'ok', 'admin_id': 'earthlink:77', 'ns': 'e', 'color_index': 3},
  ],
};

void main() {
  late _Srv srv;
  final scopeAll = <VpnMergedCompany>[(key: _kA, name: 'سوبرنت'), (key: _kB, name: 'الجزيرة'), (key: _kE, name: 'ايرث لنك')];

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    srv = _Srv()
      ..results = {
        _kA: _ok([
          {'u': 'Ali', 'src': 'cpe', 'sig': -82, 'ccq': 40},
          {'u': 'zaid', 'src': 'cpe', 'sig': -55, 'ccq': 95},
        ], 1),
        _kB: _ok([
          {'u': 'ali', 'src': 'cpe', 'sig': -58, 'ccq': 92},
        ], 0),
        _kE: {'ok': false, 'reason': 'no_vpn', 'message': 'لا VPN مربوط لحسابك — اربطه من «ربط VPN»'},
      }
      ..limits = {
        _kA: {'enabled': true, 'signal_dbm': -70, 'ccq_pct': 50},
      };
    ApiClient.dio.httpClientAdapter = srv;
    VpnNow.pollEvery = const Duration(milliseconds: 1);
    VpnNow.pipeRoute = () async => const PipeRoute.ok('company');
    VpnNow.autoHideAfter = const Duration(hours: 1);
    VpnNow.reset();
  });

  tearDown(() {
    VpnNow.mergedScope = null;
    VpnNow.pipeRoute = VpnPipe.route;
    VpnNow.autoHideAfter = const Duration(seconds: 6);
    VpnNow.reset();
  });

  test('كلّ شركةٍ بمفتاحها واحدةً بعد واحدة، والقراءات في مكانها — اليوزر نفسه في شركتين لا يختلط', () async {
    VpnNow.mergedScope = () => scopeAll;
    final job = VpnNow.subscribers;
    final lines = <String>[];
    void l() => lines.add('${job.phase.name}|${job.line}');
    job.addListener(l);
    await job.run();
    job.removeListener(l);
    final starts = srv.asked.where((a) => a.startsWith('POST')).toList();
    expect(starts, [
      'POST /api/v2/conn-vpn/check-now $_kA',
      'POST /api/v2/conn-vpn/check-now $_kB',
      'POST /api/v2/conn-vpn/check-now $_kE',
    ]);
    expect(lines, contains('running|يفحص مشتركي «الجزيرة» (2 من 3)… 5 من 10'));
    expect(VpnNow.readingFor('ali', company: _kA)?.sig, -82);
    expect(VpnNow.readingFor('ALI', company: _kB)?.sig, -58);
    expect(VpnNow.readingFor('zaid', company: _kB), isNull, reason: 'لا يُنسب لغير شركته');
    expect(VpnNow.readingFor('ali'), isNull, reason: 'مخزن المفتوحة لا يُمسّ');
    expect(VpnNow.readingsAtFor(_kA), isNotNull);
    expect(VpnNow.readingsAtFor(_kE), isNull);
    expect(job.phase, VpnBarPhase.done);
    expect(job.line, 'فُحصت 2 من 3 شركات عبر VPN');
    expect(job.sub, '1 بمشكلة · «ايرث لنك» تحتاج VPN');
    // حدود التنبيه تُقرأ لشركةٍ فيها مشكلة وحدها، وبمفتاحها
    expect(srv.asked.where((a) => a.contains('connection-alerts/settings')), ['GET /api/v2/connection-alerts/settings $_kA']);
    expect(VpnNow.limitsOf(_kA)?.signalDbm, -70);
  });

  test('شركةٌ لم تُفحص الآن تُسقط قراءاتها السابقة (لا تبدو حديثة)، والكلّ فشل ⇒ الشريط فشلٌ بأسمائها', () async {
    VpnNow.debugApplyCompany(_kE, VpnNowResult.fromJson(_ok([{'u': 'old', 'src': 'ping', 'ms': 9}], 0)));
    expect(VpnNow.readingFor('old', company: _kE), isNotNull);
    srv.results[_kA] = {'ok': false, 'reason': 'na', 'message': 'x'};
    srv.results[_kB] = {'ok': false, 'reason': 'tunnel_failed', 'message': 'x'};
    VpnNow.mergedScope = () => scopeAll;
    await VpnNow.subscribers.run();
    expect(VpnNow.readingFor('old', company: _kE), isNull);
    expect(VpnNow.subscribers.phase, VpnBarPhase.failed);
    expect(VpnNow.subscribers.line, contains('«سوبرنت»: مشتركوها على شبكة الشركة'));
    expect(VpnNow.subscribers.line, contains('«الجزيرة»: نفق الـVPN لم يتّصل'));
    expect(VpnNow.subscribers.line, contains('«ايرث لنك» تحتاج VPN'));
  });

  test('شركةٌ واحدة مختارة ⇒ فحصها وحدها؛ وخارج الوضع الفحص للمفتوحة كما كان (بلا مفتاح، مخزنها)', () async {
    VpnNow.mergedScope = () => [(key: _kB, name: 'الجزيرة')];
    await VpnNow.subscribers.run();
    expect(srv.asked.where((a) => a.startsWith('POST')), ['POST /api/v2/conn-vpn/check-now $_kB']);
    expect(VpnNow.subscribers.line, 'فُحص مشتركو «الجزيرة» عبر VPN ✓');
    expect(VpnNow.subscribers.sub, 'لا مشاكل');
    // خارج الوضع: كما كان حرفاً
    VpnNow.mergedScope = () => null;
    srv.asked.clear();
    srv.polls.clear();
    srv.results['-'] = _ok([{'u': 'ali', 'src': 'ping', 'ms': 12}], 0);
    await VpnNow.subscribers.run();
    expect(srv.asked.where((a) => a.startsWith('POST')), ['POST /api/v2/conn-vpn/check-now -']);
    expect(VpnNow.readingFor('ali')?.ms, 12);
    expect(VpnNow.readingFor('ali', company: _kB)?.sig, -58, reason: 'قراءة الجزيرة باقية بمكانها');
  });

  test('الإلغاء (الخروج من الوضع) يوقف الجولة ولا يكتب قراءاتٍ بعده', () async {
    VpnNow.mergedScope = () => scopeAll;
    final run = VpnNow.subscribers.run();
    VpnNow.subscribers.cancel();
    await run;
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(VpnNow.companyReadings, isEmpty);
    expect(VpnNow.subscribers.phase, VpnBarPhase.idle);
  });

  group('الواجهة', () {
    setUpAll(visualSetUpAll);

    Subscriber sub(String user, String key) =>
        Subscriber.fromJson({'idx': user.length, 'username': user, 'firstname': user}).withCompany(key);

    testWidgets('كرت المشترك يقرأ من فحص شركته: «ali» سوبرنت ‎-82 و«ali» الجزيرة ‎-58', (t) async {
      await visualSetUp(s1bSasOwner);
      MergedMode.reset();
      MergedMode.data.value = MergedCompaniesData.from(Map<String, dynamic>.from(_companiesRaw));
      VpnNow.debugApplyCompany(_kA, VpnNowResult.fromJson(srv.results[_kA]));
      VpnNow.debugApplyCompany(_kB, VpnNowResult.fromJson(srv.results[_kB]));
      VpnNow.mode.value = true;
      addTearDown(() => VpnNow.mode.value = false);
      await pumpVisual(t, const VisualDevice('', Size(390, 400), 1),
          home: (_) => Scaffold(
                body: Column(children: [
                  KeyedSubtree(key: const ValueKey('a'), child: SubscriberNetworkMetrics(sub: sub('ali', _kA))),
                  KeyedSubtree(key: const ValueKey('b'), child: SubscriberNetworkMetrics(sub: sub('ali', _kB))),
                ]),
              ));
      await settle(t, seconds: 1);
      expect(find.descendant(of: find.byKey(const ValueKey('a')), matching: find.textContaining('-82')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const ValueKey('b')), matching: find.textContaining('-58')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const ValueKey('b')), matching: find.textContaining('-82')), findsNothing);
      await t.pumpWidget(const SizedBox());
      MergedMode.reset();
      await visualTearDown();
    });

    testWidgets('ورقة «المشاكل»: مشكلة كلّ شركةٍ بحدودها وشارتها، والنقر يفتح صفّ شركته لا شبيهه', (t) async {
      await visualSetUp(s1bSasOwner);
      MergedMode.reset();
      MergedMode.data.value = MergedCompaniesData.from(Map<String, dynamic>.from(_companiesRaw));
      VpnNow.debugApplyCompany(_kA, VpnNowResult.fromJson(srv.results[_kA]));
      VpnNow.debugApplyCompany(_kB, VpnNowResult.fromJson(srv.results[_kB]));
      final rows = [sub('ali', _kA), sub('ali', _kB), sub('zaid', _kA)];
      Subscriber? opened;
      await pumpVisual(t, const VisualDevice('', Size(390, 844), 1),
          home: (ctx) => Scaffold(
                body: Builder(
                  builder: (ctx) => TextButton(
                    onPressed: () => showVpnProblemsSheet(ctx, subscribers: rows, onOpen: (s) => opened = s, onSection: () {}),
                    child: const Text('open'),
                  ),
                ),
              ));
      await settle(t, seconds: 1);
      await t.tap(find.text('open'));
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await settle(t, seconds: 1);
      // ali سوبرنت (‎-82، CCQ 40) بمشكلة؛ ali الجزيرة (‎-58) وzaid سليمان
      expect(find.textContaining('1 بمشكلة'), findsOneWidget);
      expect(find.text('سوبرنت'), findsOneWidget);
      await t.tap(find.text('ali').first);
      await settle(t, seconds: 1);
      expect(opened?.companyKey, _kA);
      await t.pumpWidget(const SizedBox());
      MergedMode.reset();
      await visualTearDown();
    });
  });
}
