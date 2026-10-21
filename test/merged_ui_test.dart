import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/account_api.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/api/company_route.dart';
import 'package:rad_mysvcs/api/merged_dashboard_api.dart';
import 'package:rad_mysvcs/api/subscribers_api.dart';
import 'package:rad_mysvcs/models/subscriber.dart';
import 'package:rad_mysvcs/screens/account/company_switch_sheet.dart';
import 'package:rad_mysvcs/screens/subscribers/subscribers_screen.dart';
import 'package:rad_mysvcs/screens/subscribers/widgets/filter_chips_bar.dart';
import 'package:rad_mysvcs/services/merged_mode.dart';

import 'visual_perm/visual_perm_harness.dart';

/// «كل الشركات» في التطبيق — الواجهة (٢١ أكتوبر): خيارٌ في «تبديل الشركة»، والمشتركين من شركتين معاً بشارة كلٍّ منهما،
/// والكبيرة والمتعذّرة تُسمّيان، والكتابة على مشتركٍ مدموج تحمل مفتاح شركته ومرجع نافذته. الخادم وهميّ.
const _kA = 'c0000000000aa';
const _kB = 'c0000000000bb';
const _kC = 'c0000000000cc';

Map<String, Object?> _row(int i, {String parent = 'admin@a', String debt = ''}) => {
      'idx': i,
      'username': 'u$i',
      'firstname': 'مشترك',
      'lastname': '$i',
      'parent_username': parent,
      'profile_name': 'Gold',
      'remaining_days': 10,
      'expiration': '2026-12-01 00:00:00',
      'enabled': 1,
      'online_status': 1,
      if (debt.isNotEmpty) 'notes': debt,
    };

ResponseBody _json(int status, Object body, {Map<String, List<String>> headers = const {}}) =>
    ResponseBody.fromString(jsonEncode(body), status, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
      ...headers,
    });

class _Srv implements HttpClientAdapter {
  _Srv(this.inner);
  final HttpClientAdapter inner;
  final routed = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? rs, Future<void>? cf) async {
    final key = o.headers['x-company-key'] as String?;
    if (key == null) return inner.fetch(o, rs, cf);
    routed.add(o);
    final h = {'x-company-key': [key]};
    final path = o.uri.path;
    if (o.method == 'GET' && path == '/api/v2/subscribers') {
      if (o.queryParameters['page'] != null) {
        return _json(200, {'success': true, 'paged': true, 'total': key == _kC ? 89217 : 3}, headers: h);
      }
      final rows = key == _kA
          ? [_row(1), _row(2, debt: '-5000')]
          : [_row(1, parent: 'admin@b'), _row(9, parent: 'admin@b', debt: '-2500')];
      return _json(200, {'success': true, 'data': rows}, headers: h);
    }
    if (o.method == 'GET' && RegExp(r'^/api/v2/subscribers/\d+$').hasMatch(path)) {
      return _json(200, {'success': true, 'data': {'idx': path.split('/').last}},
          headers: {...h, 'x-company-ref': ['r_${'R' * 22}']});
    }
    if (o.method == 'GET' && path == '/api/v2/admin-widgets') {
      return _json(200, {'success': true, 'balance': key == _kA ? 100000 : 50000, 'points': 0}, headers: h);
    }
    return _json(200, {'success': true, 'message': 'تم'}, headers: h);
  }

  @override
  void close({bool force = false}) {}
}

Map<String, Object?> _companies() => {
      'routing': true,
      'writes': true,
      'companies': [
        {'key': _kA, 'code': 'supernet', 'username': 'admin@a', 'name': 'شركة ألف', 'status': 'ok', 'admin_id': '11', 'ns': 'nA', 'currency': 'IQD', 'color_index': 0},
        {'key': _kB, 'code': 'jt', 'username': 'admin@b', 'name': 'شركة باء', 'status': 'ok', 'admin_id': 'jt:22', 'ns': 'nB', 'currency': 'IQD', 'color_index': 1},
        {'key': _kC, 'code': 'full', 'username': 'admin@full', 'name': 'شركة كبيرة', 'status': 'ok', 'admin_id': '33', 'ns': 'nC', 'currency': 'IQD', 'color_index': 2},
        {'key': 'c0000000000dd', 'code': 'x', 'username': 'u', 'name': 'شركة تحتاج دخول', 'status': 'needs_login', 'admin_id': '44', 'ns': 'nD'},
      ],
    };

void main() {
  setUpAll(visualSetUpAll);

  late _Srv srv;
  Future<void> up() async {
    final inner = await visualSetUp(s1bSasOwner);
    srv = _Srv(inner);
    ApiClient.dio.httpClientAdapter = srv;
    AccountApi.tokenSource = ({bool force = false}) async => 'acct';
    MergedMode.reset();
    MergedMode.fetchRaw = () async => Map<String, dynamic>.from(_companies());
    SubscribersApi.clearAllCaches();
  }

  Future<void> down(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 6));
    MergedMode.reset();
    await visualTearDown();
  }

  testWidgets('«تبديل الشركة»: «كل الشركات» أعلى الورقة، والنقر يدخله بلا تسجيل', (t) async {
    await up();
    await pumpVisual(t, phone, home: (_) => const CompanySwitchSheet());
    await settle(t, seconds: 2);
    expect(find.text('كل الشركات'), findsOneWidget);
    expect(find.textContaining('3 شركات معاً'), findsOneWidget, reason: 'الصالحة وحدها (لا التي تحتاج دخول)');
    await t.tap(find.text('كل الشركات'));
    await settle(t, seconds: 2);
    expect(MergedMode.active.value, isTrue);
    await down(t);
  });

  testWidgets('المشتركين في «كل الشركات»: صفوف الشركتين بشارة كلٍّ منهما، والكبيرة والتي تحتاج دخول مسمّاتان', (t) async {
    await up();
    await t.runAsync(() => MergedMode.enter());
    expect(MergedMode.active.value, isTrue);
    final cmd = ValueNotifier<SubscriberFilter?>(SubscriberFilter.all);
    await pumpVisual(t, phone, home: (_) => SubscribersScreen(filterCmd: cmd));
    await settle(t, seconds: 3);
    expect(find.text('شركة ألف'), findsWidgets);
    expect(find.text('شركة باء'), findsWidgets);
    expect(find.textContaining('كل الشركات · 3 شركات • 4 مشترك'), findsOneWidget,
        reason: 'idx 1 في ساسين مختلفين ⇒ صفّان، والكبيرة خارجها');
    expect(find.textContaining('«شركة كبيرة» كبيرة'), findsOneWidget, reason: 'الكبيرة تُفتح منفردة');
    expect(find.textContaining('شركة تحتاج دخول'), findsOneWidget);
    final full = srv.routed.where((o) => o.uri.path == '/api/v2/subscribers' && o.queryParameters['page'] == null);
    expect(full.map((o) => o.headers['x-company-key']).toSet(), {_kA, _kB}, reason: 'الكبيرة لا تُجلب كاملة');
    await down(t);
  });

  testWidgets('كتابةٌ على مشتركٍ مدموج: مفتاح شركته ومرجع نافذته (هويّته أوّلاً)، والقائمة العاديّة بلا توجيه', (t) async {
    await up();
    await t.runAsync(() => MergedMode.load(fresh: true));
    final sub = Subscriber(idx: '9', username: 'u9', firstname: 'x', lastname: 'y', companyKey: _kB);
    await t.runAsync(() => MergedOps.write(sub, () => SubscribersApi.payDebt(idx: '9', amount: 2500, skipAutoWa: true)));
    final get = srv.routed.firstWhere((o) => o.method == 'GET' && o.uri.path == '/api/v2/subscribers/9');
    expect(get.headers['x-company-key'], _kB);
    final pay = srv.routed.firstWhere((o) => o.method == 'POST' && o.uri.path == '/api/v2/subscribers/9/pay-debt');
    expect(pay.headers['x-company-key'], _kB);
    expect(pay.headers['x-company-ref'], 'r_${'R' * 22}');
    expect(pay.headers.containsKey('Authorization'), isFalse);
    expect(CompanyRefs.lookup(_kB, '9', CompanyRefKind.subject), isNotNull);
    // الوضع العاديّ: المسار نفسه بلا توجيه
    final before = srv.routed.length;
    final plain = Subscriber(idx: '9', username: 'u9', firstname: 'x', lastname: 'y');
    await t.runAsync(() => MergedOps.write(plain, () => SubscribersApi.payDebt(idx: '9', amount: 1, skipAutoWa: true)));
    expect(srv.routed.length, before, reason: 'بلا شركة ⇒ الطلب العاديّ');
    await down(t);
  });

  testWidgets('الرئيسية: الرصيد مجموع الشركات بالدينار، والكبيرة داخل الرصيد (لا قائمتها)', (t) async {
    await up();
    await t.runAsync(() => MergedMode.load(fresh: true));
    final w = await t.runAsync(MergedDashboardApi.wallet);
    expect(w!.value!.balance, 100000 + 50000 + 50000, reason: 'الثلاث الصالحة (الكبيرة رصيدها يُقرأ)');
    expect(w.excluded, isEmpty);
    final rows = await t.runAsync(() => MergedSubscribers.load(fresh: true));
    final d = MergedDashboardApi.debtorsFrom(rows!.rows);
    expect(d.totalSubs, 4, reason: 'idx 1 في ساسين مختلفين ⇒ صفّان');
    expect(d.count, 2);
    expect(d.total, 7500);
    await down(t);
  });
}
