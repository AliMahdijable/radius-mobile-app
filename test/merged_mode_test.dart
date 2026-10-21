import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/account_api.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/api/archive_info.dart';
import 'package:rad_mysvcs/api/company_route.dart';
import 'package:rad_mysvcs/api/merged_finance_api.dart';
import 'package:rad_mysvcs/api/reports_api.dart';
import 'package:rad_mysvcs/models/merged_company.dart';
import 'package:rad_mysvcs/models/subscriber.dart';
import 'package:rad_mysvcs/services/merged_mode.dart';
import 'package:rad_mysvcs/services/merged_rows.dart';
import 'package:rad_mysvcs/services/subscriber_usage_store.dart';

import 'visual_perm/visual_perm_harness.dart';

/// «كل الشركات» في التطبيق (٢١ أكتوبر): النداء الموجَّه (توكن الحساب وحده + x-company-key + صدى + مراجع)، والدمج بقاعدة الويب
/// حرفاً، وقوائم الشركات (الكبيرة لا تُجلب، والمتعذّرة تُسمّى). الخادم وهميّ.
const _kA = 'c0000000000aa';
const _kB = 'c0000000000bb';
const _kC = 'c0000000000cc';

MergedCompany _co(String key, {String user = 'admin@a', String ns = 'nsA', String adminId = '1', int index = 0, String name = 'A'}) =>
    MergedCompany(
      key: key,
      code: 'supernet',
      username: user,
      name: name,
      provider: MergedProvider.sas4,
      colorIndex: index,
      adminId: adminId,
      ns: ns,
      currency: 'IQD',
      home: index == 0,
      status: MergedStatus.ok,
      index: index,
    );

Subscriber _s(String idx, {String parent = 'admin@a', String user = 'u'}) =>
    Subscriber(idx: idx, username: '$user$idx', firstname: 'F', lastname: 'L', parentUsername: parent);

ResponseBody _json(int status, Object body, {Map<String, List<String>> headers = const {}}) =>
    ResponseBody.fromString(jsonEncode(body), status, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
      ...headers,
    });

/// خادمٌ يسجّل الطلبات ويصدي المفتاح (إلّا إن طُلب غير ذلك) ويسكّ المراجع كما يفعل الخادم.
class _RouteServer implements HttpClientAdapter {
  _RouteServer(this.inner);
  final HttpClientAdapter inner;
  final requests = <RequestOptions>[];
  bool echo = true;
  int acctExpiredOnce = 0;
  final Map<String, Object> lists = {};
  final Map<String, int> totals = {};

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    final key = o.headers['x-company-key'] as String?;
    if (key == null) return inner.fetch(o, requestStream, cancelFuture);
    requests.add(o);
    if (acctExpiredOnce > 0) {
      acctExpiredOnce--;
      return _json(401, {'error': 'account-token-expired'});
    }
    final h = <String, List<String>>{if (echo) 'x-company-key': [key]};
    final path = o.uri.path;
    if (o.method == 'GET' && path == '/api/v2/subscribers') {
      if (o.queryParameters['page'] != null) {
        return _json(200, {'success': true, 'paged': true, 'total': totals[key] ?? 3, 'data': const []}, headers: h);
      }
      final l = lists[key];
      if (l is int) return _json(l, {'success': false, 'message': 'تعذّر جلب بيانات الشركة الآن', 'code': 'COMPANY_UPSTREAM_UNAVAILABLE'}, headers: h);
      return _json(200, {'success': true, 'data': l ?? const []}, headers: h);
    }
    if (o.method == 'GET' && RegExp(r'^/api/v2/subscribers/\d+$').hasMatch(path)) {
      return _json(200, {'success': true, 'data': {'idx': path.split('/').last}},
          headers: {...h, 'x-company-ref': ['r_SSSSSSSSSSSSSSSSSSSSSS']});
    }
    if (o.method == 'GET' && path == '/api/v2/subscribers-usage') {
      final ids = '${o.queryParameters['ids']}'.split(',');
      return _json(200, {
        'success': true,
        'data': {for (final id in ids) id: {'today': key == _kB ? 222 : 111, 'month': 1000}},
      }, headers: h);
    }
    if (o.method == 'GET' && path.endsWith('/activation-data')) {
      return _json(200, {'success': true, 'data': {}}, headers: {...h, 'x-company-ref': ['r_AAAAAAAAAAAAAAAAAAAAAA']});
    }
    return _json(200, {'success': true}, headers: h);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  setUpAll(visualSetUpAll);

  late _RouteServer srv;
  Future<void> up() async {
    final inner = await visualSetUp(s1bSasOwner);
    srv = _RouteServer(inner);
    ApiClient.dio.httpClientAdapter = srv;
    AccountApi.tokenSource = ({bool force = false}) async => force ? 'acct-fresh' : 'acct-1';
    CompanyRefs.reset();
    MergedSubscribers.reset();
  }

  Future<void> down() async {
    await visualTearDown();
    CompanyRefs.reset();
    MergedSubscribers.reset();
  }

  group('النداء الموجَّه', () {
    testWidgets('داخل CompanyRoute.run: توكن الحساب ومفتاح الشركة، بلا Bearer الشركة المفتوحة', (t) async {
      await up();
      await t.runAsync(() => CompanyRoute.run(_kA, () => ApiClient.dio.get<dynamic>('/api/v2/admin-widgets')));
      final o = srv.requests.single;
      expect(o.headers['x-company-key'], _kA);
      expect(o.headers['x-account-token'], 'acct-1');
      expect(o.headers.containsKey('Authorization'), isFalse);
      expect(o.headers.containsKey('x-auth-token'), isFalse);
      // وخارجه: الطلب عاديّ (لا يصل الخادم الموجَّه)
      await t.runAsync(() => ApiClient.dio.get<dynamic>('/api/v2/admin-widgets'));
      expect(srv.requests, hasLength(1));
      await down();
    });

    testWidgets('extra[companyKey] صراحةً يوجّه بلا نطاق', (t) async {
      await up();
      await t.runAsync(() => ApiClient.dio.get<dynamic>('/api/v2/packages', options: Options(extra: {'companyKey': _kB})));
      expect(srv.requests.single.headers['x-company-key'], _kB);
      await down();
    });

    testWidgets('بلا صدى المفتاح ⇒ لا يُقبل الردّ (409 COMPANY_ROUTE_ECHO)', (t) async {
      await up();
      srv.echo = false;
      final r = await t.runAsync(() => CompanyRoute.run(_kA, () => ApiClient.dio.get<dynamic>('/api/v2/admin-widgets')));
      expect(r!.statusCode, 409);
      expect((r.data as Map)['code'], CompanyRouteCodes.echo);
      await down();
    });

    testWidgets('توكن الحساب انتهى ⇒ تجديده وإعادةٌ واحدة', (t) async {
      await up();
      srv.acctExpiredOnce = 1;
      final r = await t.runAsync(() => CompanyRoute.run(_kA, () => ApiClient.dio.get<dynamic>('/api/v2/admin-widgets')));
      expect(r!.statusCode, 200);
      expect(srv.requests, hasLength(2));
      expect(srv.requests.last.headers['x-account-token'], 'acct-fresh');
      await down();
    });

    testWidgets('المراجع: تُسكّ على هويّة المشترك وبيانات التفعيل وتُرفق بالكتابة لشركتها ومشتركها وحدهما', (t) async {
      await up();
      await t.runAsync(() => CompanyRoute.run(_kA, () async {
            await ApiClient.dio.get<dynamic>('/api/v2/subscribers/1520');
            await ApiClient.dio.get<dynamic>('/api/v2/subscribers/1520/activation-data');
            await ApiClient.dio.post<dynamic>('/api/v2/subscribers/1520/pay-debt', data: {'amount': 1000});
            await ApiClient.dio.post<dynamic>('/api/v2/subscribers/1520/activate', data: {});
            await ApiClient.dio.post<dynamic>('/api/v2/subscribers/1521/pay-debt', data: {});
          }));
      await t.runAsync(() => CompanyRoute.run(_kB, () => ApiClient.dio.post<dynamic>('/api/v2/subscribers/1520/pay-debt', data: {})));
      final pay = srv.requests.firstWhere((r) => r.uri.path.endsWith('1520/pay-debt'));
      expect(pay.headers['x-company-ref'], 'r_SSSSSSSSSSSSSSSSSSSSSS');
      final act = srv.requests.firstWhere((r) => r.uri.path.endsWith('1520/activate'));
      expect(act.headers['x-company-ref'], 'r_AAAAAAAAAAAAAAAAAAAAAA');
      expect(srv.requests.firstWhere((r) => r.uri.path.endsWith('1521/pay-debt')).headers.containsKey('x-company-ref'), isFalse,
          reason: 'مشتركٌ آخر بلا مرجع');
      expect(srv.requests.last.headers.containsKey('x-company-ref'), isFalse, reason: 'الشركة الأخرى بلا مرجع');
      expect(CompanyRefs.lookup(_kA, '1520', CompanyRefKind.activate), isNull, reason: 'عرض السعر استُهلك بالنجاح');
      expect(CompanyRefs.lookup(_kA, '1520', CompanyRefKind.subject), isNotNull, reason: 'مرجع النافذة يبقى');
      await down();
    });
  });

  group('الدمج (قاعدة الويب)', () {
    test('idx نفسه في ساسين مختلفين ⇒ صفّان، كلٌّ بشركته', () {
      final out = mergeRows([
        MergePart(company: _co(_kA, ns: 'nsA'), rows: [_s('1520')]),
        MergePart(company: _co(_kB, ns: 'nsB', user: 'admin@b', adminId: '2', index: 1), rows: [_s('1520', parent: 'admin@b')]),
      ]);
      expect(out.map((s) => s.companyKey), [_kA, _kB]);
    });

    test('صفحتان على ساسٍ واحد تريان المشترك ⇒ مرّةً تحت صفحته المباشرة', () {
      final out = mergeRows([
        MergePart(company: _co(_kA, user: 'admin@top'), rows: [_s('7', parent: 'sub@b'), _s('8', parent: 'admin@top')]),
        MergePart(company: _co(_kB, user: 'sub@b', adminId: '5', index: 1), rows: [_s('7', parent: 'sub@b')]),
      ]);
      expect(out, hasLength(2));
      expect(out.firstWhere((s) => s.idx == '7').companyKey, _kB, reason: 'المباشر يحسم');
      expect(out.firstWhere((s) => s.idx == '8').companyKey, _kA);
    });

    test('مديرٌ غير مربوط تحت صفحتين ⇒ الأعمق (القائمة الأصغر)', () {
      final out = mergeRows([
        MergePart(company: _co(_kA, user: 'top'), rows: [_s('1', parent: 'x'), _s('2', parent: 'x'), _s('3', parent: 'y')]),
        MergePart(company: _co(_kB, user: 'mid', adminId: '9', index: 1), rows: [_s('1', parent: 'x'), _s('2', parent: 'x')]),
      ]);
      expect(out.where((s) => s.companyKey == _kB).map((s) => s.idx), ['1', '2']);
      expect(out.where((s) => s.companyKey == _kA).map((s) => s.idx), ['3']);
    });

    test('ربطان للمدير نفسه ⇒ قائمةٌ واحدة (الأقدم ربطاً)', () {
      final a = _co(_kA, ns: 'n1', adminId: '44');
      final b = _co(_kB, ns: 'n1', adminId: 'jt:44', user: 'other', index: 1);
      expect(sameManagerOf([a, b])[_kB]?.key, _kA);
      final out = mergeRows([MergePart(company: a, rows: [_s('1')]), MergePart(company: b, rows: [_s('1'), _s('2')])]);
      expect(out.map((s) => s.companyKey).toSet(), {_kA});
      expect(out, hasLength(1));
    });

    test('صفٌّ بلا idx لا يُطوى ويأتي آخراً', () {
      final out = mergeRows([
        MergePart(company: _co(_kA), rows: [Subscriber(username: 'x', firstname: '', lastname: ''), _s('1')]),
      ]);
      expect(out.map((s) => s.username), ['u1', 'x']);
    });

    test('قراءة الشركات: مفتاحٌ بلا صيغته يُسقط، والمكرّر، والعملة المجهولة null', () {
      final d = MergedCompaniesData.from({
        'routing': true,
        'writes': true,
        'companies': [
          {'key': _kA, 'code': 'supernet', 'status': 'ok', 'admin_id': '1146', 'ns': 'n', 'currency': 'iqd'},
          {'key': _kA, 'code': 'dup', 'status': 'ok'},
          {'key': 'bad', 'status': 'ok'},
          {'key': _kB, 'code': 'jt', 'status': 'needs_login'},
          {'key': _kC, 'code': 'ftth-iq', 'provider': 'ftth', 'status': 'ok'},
        ],
      });
      expect(d.companies.map((c) => c.key), [_kA, _kB, _kC]);
      expect(d.companies.first.currency, 'IQD');
      expect(d.companies[1].currency, isNull);
      expect(d.usable.map((c) => c.key), [_kA], reason: 'تحتاج دخول وFTTH (الويب وحده) لا تدخل');
      expect(d.writes, isTrue);
    });
  });

  group('قوائم الشركات', () {
    testWidgets('الكبيرة لا تُجلب كاملة، والمتعذّرة تُسمّى، والصفوف مربوطةٌ بشركتها', (t) async {
      await up();
      MergedMode.fetchRaw = () async => {
            'routing': true,
            'writes': true,
            'companies': [
              {'key': _kA, 'code': 'supernet', 'username': 'admin@a', 'name': 'A', 'status': 'ok', 'admin_id': '1', 'ns': 'nA'},
              {'key': _kB, 'code': 'jt', 'username': 'admin@b', 'name': 'B', 'status': 'ok', 'admin_id': 'jt:2', 'ns': 'nB'},
              {'key': _kC, 'code': 'full', 'username': 'admin@full', 'name': 'C', 'status': 'ok', 'admin_id': '3', 'ns': 'nC'},
            ],
          };
      srv.lists[_kA] = [
        {'idx': 1, 'username': 'a1', 'firstname': 'x', 'lastname': 'y', 'parent_username': 'admin@a'},
      ];
      srv.lists[_kB] = 409; // الخادم يردّ تعذّر الشركة 409 لا 5xx (COMPANY_UPSTREAM_UNAVAILABLE)
      srv.totals[_kC] = 89217;
      final r = await t.runAsync(() => MergedSubscribers.load(fresh: true));
      expect(r!.rows.map((s) => '${s.companyKey}:${s.username}'), ['$_kA:a1']);
      expect(r.big.single.company.key, _kC);
      expect(r.big.single.bigTotal, 89217);
      expect(r.failed.single.company.key, _kB);
      expect(r.failed.single.error, contains('تعذّر'));
      final fulls = srv.requests.where((o) => o.uri.path == '/api/v2/subscribers' && o.queryParameters['page'] == null);
      expect(fulls.map((o) => o.headers['x-company-key']).toSet(), {_kA, _kB}, reason: 'الكبيرة: صفٌّ واحد لا القائمة');
      MergedMode.reset();
      await down();
    });
  });

  group('الشركة المختارة والعدّ (الشريط)', () {
    Subscriber row(String idx, String parent, {bool abandoned = false, String? co}) => Subscriber(
          idx: idx,
          username: 'u$idx',
          firstname: 'F',
          lastname: 'L',
          parentUsername: parent,
          profileName: abandoned ? null : 'Gold',
          expiration: abandoned ? null : '2026-12-01 00:00:00',
          companyKey: co,
        );

    test('الكلّ مدموجٌ بلا تكرار، والشركة المختارة قائمتها كما وصلت، والعدد بلا المهمَل، والمطويّ يُسمّى', () {
      final a = _co(_kA, user: 'admin@a', ns: 'n1', adminId: '1', index: 0, name: 'A');
      final b = _co(_kB, user: 'admin@b', ns: 'n1', adminId: '2', index: 1, name: 'B');
      final aRows = [row('1', 'admin@a', co: _kA), row('2', 'admin@b', co: _kA), row('3', 'admin@a', abandoned: true, co: _kA)];
      final bRows = [row('2', 'admin@b', co: _kB)];
      final merged = mergeRows([MergePart(company: a, rows: aRows), MergePart(company: b, rows: bRows)]);
      final r = MergedListResult(
        rows: merged,
        parts: [MergedCompanyList(company: a, rows: aRows), MergedCompanyList(company: b, rows: bRows)],
        missing: const [],
      );
      expect(r.total, 2, reason: '1 تحت A و2 تحت B (صفحته المباشرة)، والمهمَل خارج العدّ');
      expect(r.countOf(_kA), 2, reason: 'قائمة A كما وصلت: 1 و2 (بلا المهمَل)');
      expect(r.countOf(_kB), 1);
      expect(r.folded, 1, reason: '2 تراه الصفحتان فيُعدّ مرّةً في «الكل»');
      expect(r.rowsFor(_kB).map((s) => s.idx), ['2']);
      expect(r.rowsFor(null).map((s) => '${s.companyKey}:${s.idx}'), containsAll(['$_kA:1', '$_kB:2']));
      expect(r.countOf('c0000000000ee'), isNull, reason: 'شركةٌ بلا قائمة ⇒ لا عدد (لا صفر)');
    });

    testWidgets('focused: الصالحة وحدها، والخروج والتبديل يمسحانها', (t) async {
      await up();
      MergedMode.fetchRaw = () async => {
            'routing': true,
            'writes': true,
            'companies': [
              {'key': _kA, 'code': 'supernet', 'username': 'admin@a', 'name': 'A', 'status': 'ok', 'admin_id': '1', 'ns': 'nA'},
              {'key': _kB, 'code': 'jt', 'username': 'admin@b', 'name': 'B', 'status': 'needs_login', 'admin_id': 'jt:2', 'ns': 'nB'},
            ],
          };
      await t.runAsync(() => MergedMode.load(fresh: true));
      MergedMode.focus.value = _kA;
      expect(MergedMode.focused?.key, _kA);
      MergedMode.focus.value = _kB;
      expect(MergedMode.focused, isNull, reason: 'تحتاج دخول ⇒ لا تُختار (الكلّ)');
      MergedMode.focus.value = _kA;
      await t.runAsync(MergedMode.exit);
      expect(MergedMode.focus.value, isNull);
      MergedMode.focus.value = _kA;
      MergedMode.reset();
      expect(MergedMode.focus.value, isNull);
      await down();
    });
  });

  group('الاستهلاك في «كل الشركات»', () {
    testWidgets('صفٌّ مدموج يُسأل استهلاكه من شركته (موجَّهاً)، والعاديّ من المفتوحة — والمفتاح الشركة|idx', (t) async {
      await up();
      final prev = UsagePrefs.enabled.value;
      UsagePrefs.enabled.value = true;
      SubscriberUsageStore.reset();
      // المؤقّت والطلب حقيقيّان (لا وقت الاختبار المزيّف)
      await t.runAsync(() async {
        SubscriberUsageStore.want('9', company: _kB);
        SubscriberUsageStore.want('9');
        await Future<void>.delayed(const Duration(milliseconds: 800));
      });
      final routed = srv.requests.where((o) => o.uri.path == '/api/v2/subscribers-usage').toList();
      expect(routed.length, 1, reason: 'دفعة الشركة وحدها موجَّهة؛ دفعة المفتوحة بلا توجيه');
      expect(routed.single.headers['x-company-key'], _kB);
      expect(routed.single.queryParameters['ids'], '9');
      expect(SubscriberUsageStore.get('9', company: _kB)?.v?.today, 222);
      expect(SubscriberUsageStore.get('9', company: _kA), isNull, reason: 'الرقم نفسه في شركةٍ أخرى مفتاحٌ آخر');
      UsagePrefs.enabled.value = prev;
      SubscriberUsageStore.reset();
      await down();
    });
  });

  group('التقرير الماليّ في «كل الشركات»', () {
    MergedCompany co(String key, String adminId, {String? currency = 'IQD', int index = 0, String name = 'X'}) => MergedCompany(
          key: key,
          code: 'x',
          username: 'admin@$name',
          name: name,
          provider: MergedProvider.sas4,
          colorIndex: index,
          adminId: adminId,
          ns: 'ns$index',
          currency: currency,
          home: false,
          status: MergedStatus.ok,
          index: index,
        );
    FinanceLog log(int id, String at, {num amount = 0}) =>
        FinanceLog(id: id, actionType: 'DEBT_PAY', createdAt: at, amount: amount);

    test('المجموع بقاعدة كلّ شركة، والخارج يُسمّى، والحركات الأحدث أوّلاً بشركتها، والأرشيف مجموع', () {
      final a = co(_kA, '1', name: 'A');
      final b = co(_kB, 'jt:2', index: 1, name: 'B');
      final c = co(_kC, 'jt:3', index: 2, name: 'C');
      final d = co('c0000000000dd', 'jt:4', currency: 'USD', index: 3, name: 'D');
      final e = co('c0000000000ee', 'jt:5', index: 4, name: 'E');
      final aLogs = [log(1, '2026-10-21 12:00:00'), log(2, '2026-10-21 10:00:00')];
      final bLogs = [log(1, '2026-10-21 11:00:00')];
      final parts = [
        MergedFinancePart(
          company: a,
          report: FinanceReport(
            kpis: const FinanceKPIs(activateCashSum: 10000, debtPaySum: 5000, expensesSum: 2000, balanceAddSum: 1000),
            recentLogs: aLogs,
            archive: ArchiveInfo(hidden: false, included: false, settlements: 1, lastNumber: 3, lastCutAt: DateTime(2026, 10, 1)),
            unavailableParts: const ['recent_logs'],
          ),
        ),
        MergedFinancePart(
          company: b,
          report: FinanceReport(
            kpis: const FinanceKPIs(
              activateCashSum: 20000,
              activateNonCashSum: 5000,
              expensesSum: 1000,
              packageCost: PackageCostKpis(sum: 15000, rows: 2, knownRows: 2),
            ),
            recentLogs: bLogs,
            archive: ArchiveInfo(hidden: true, included: false, settlements: 2, lastNumber: 7, lastCutAt: DateTime(2026, 10, 10)),
          ),
        ),
      ];
      final cRep = FinanceReport(kpis: const FinanceKPIs(activateCashSum: 999999), recentLogs: [log(9, '2026-10-21 13:00:00')], unavailableParts: const ['expenses']);
      parts.add(MergedFinancePart(company: c, report: cRep, reason: MergedFinanceApi.gapReason(c, cRep)));
      const dRep = FinanceReport(kpis: FinanceKPIs(activateCashSum: 5), recentLogs: []);
      parts.add(MergedFinancePart(company: d, report: dRep, reason: MergedFinanceApi.gapReason(d, dRep)));
      parts.add(MergedFinancePart(company: e, reason: 'تعذّر جلب تقريرها'));

      final m = MergedFinanceApi.combine(parts);
      final k = m.report!.kpis;
      expect(k.totalCashRevenue, 35000);
      expect(k.netCash, 12000 + 19000, reason: 'صافي كلّ شركةٍ بقاعدة التطبيق (المصاريف وإضافة الدين تُطرح)');
      expect(k.packageCost!.sum, 15000, reason: 'كلفة من تُطرح عنده وحده');
      expect(k.profitAfterCost, 12000 + 9000, reason: 'A بلا كلفة: صافيها النقديّ؛ B: مبيعات − مصاريف − كلفة');
      expect(m.mixedProfitRules, isTrue);
      expect(m.excluded, ['C: تعذّرت قراءة صرفياتها', 'D: USD', 'E: تعذّر جلب تقريرها']);
      expect(m.logsPartial, ['A']);
      expect([for (final l in m.report!.recentLogs) '${m.logCompany[l]}:${l.id}'], ['$_kA:1', '$_kB:1', '$_kA:2'],
          reason: 'الأحدث أوّلاً، والخارجة من المجموع لا تُعرض حركاتها تحته');
      final ar = m.report!.archive!;
      expect(ar.settlements, 3);
      expect(ar.lastNumber, 7);
      expect(ar.hidden, isTrue);
    });

    test('moneyGap: التقرير كلّه، والتفعيلات، والصرفيات، وجزءٌ مجهول — وrecent_logs وحده عرض', () {
      FinanceReport r({bool un = false, List<String> parts = const []}) =>
          FinanceReport(kpis: const FinanceKPIs(), recentLogs: const [], unavailable: un, unavailableParts: parts);
      expect(r(un: true).moneyGap, 'reply');
      expect(r(parts: ['activations', 'expenses']).moneyGap, 'activations');
      expect(r(parts: ['expenses']).moneyGap, 'expenses');
      expect(r(parts: ['package_cost']).moneyGap, 'other');
      expect(r(parts: ['recent_logs']).moneyGap, isNull);
      expect(r().moneyGap, isNull);
    });
  });
}
