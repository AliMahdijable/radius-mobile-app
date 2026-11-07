import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/account_api.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/api/subscribers_api.dart';
import 'package:rad_mysvcs/screens/reports/all_managers_debts_screen.dart';
import 'package:rad_mysvcs/screens/reports/deleted_debts_screen.dart';
import 'package:rad_mysvcs/services/merged_mode.dart';

import 'visual_perm/visual_perm_harness.dart';

/// «كل الشركات» في ديون المدراء وديون المحذوفين (٨ نوفمبر — المالك: «نعم لازم نسوي كلشي»): كلّ شركةٍ بطلباتٍ موجَّهة لها، والمجموع
/// للمقروء وحده — المتعذّرة تُسمّى، ودين مديرٍ لم يُقرأ يُسمّى ولا يُجمع، ومعرّف المدير الفرعيّ نفسه في شركتين مدينان لا واحد.
const _kA = 'c0000000000aa'; // سوبرنت (المفتوحة: معرّف الجلسة في الحاضنة supernet:12) — مديران: m5 مدين، m6 دينه لم يُقرأ
const _kB = 'c0000000000bb'; // الجزيرة — مديرها b5 بالمعرّف 5 نفسه
const _kC = 'c0000000000cc'; // ساس بلا مدراء فرعيّين
const _kF = 'c0000000000ff'; // ساس تتعذّر قائمة مدرائه
const _kN = 'c0000000000ee'; // شركة مُضافة — لا مدراء فرعيّين بنوعها (لا تُطلب)

ResponseBody _json(int status, Object body, {Map<String, List<String>> headers = const {}}) =>
    ResponseBody.fromString(jsonEncode(body), status, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
      ...headers,
    });

String _today(int hour) {
  final d = DateTime.now();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${d.year}-${two(d.month)}-${two(d.day)} ${two(hour)}:00:00';
}

Map<String, Object?> _move(int id, String sub, int amount, int hour) =>
    {'row_type': 'balance', 'id': id, 'sub_kind': sub, 'amount': amount, 'source': 'sas4', 'event_at': _today(hour)};

class _Srv implements HttpClientAdapter {
  _Srv(this.inner);
  final HttpClientAdapter inner;
  final asked = <String>[];

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? rs, Future<void>? cf) async {
    final key = o.headers['x-company-key'] as String?;
    final path = o.uri.path;
    if (path.startsWith('/api/admin/') || path.startsWith('/api/v2/managers') || path.startsWith('/api/v2/deleted-debts')) {
      asked.add('${o.method} $path ${key ?? '-'}');
    }
    if (key == null) return inner.fetch(o, rs, cf);
    final h = {'x-company-key': [key]};
    Future<ResponseBody> ok(Map<String, Object?> body) async => _json(200, {'success': true, ...body}, headers: h);
    if (path == '/api/admin/manager-debts/access') {
      return ok({'hasSubAdmins': key != _kC, 'subAdmins': const []});
    }
    if (path == '/api/v2/managers/full') {
      if (key == _kF) return _json(409, {'success': false, 'message': 'انتهت جلسة «فاشلة» — افتحها من «شركاتي»'}, headers: h);
      final rows = key == _kA
          ? [
              {'id': 5, 'username': 'm5', 'total_debt': 100000},
              {'id': 6, 'username': 'm6', 'total_debt': 0, 'debt_unavailable': true},
            ]
          : [
              {'id': 5, 'username': 'b5', 'total_debt': 30000},
            ];
      return ok({'data': rows, 'total': rows.length});
    }
    if (path == '/api/admin/manager-debts/summary') {
      return ok(key == _kA
          ? {
              'totals': {'total_remaining': 20000, 'debts_count': 1},
              'perDebtor': [
                {'debtor_admin_id': 5, 'debtor_admin_username': 'm5', 'debts_count': 1, 'total_remaining': 20000},
              ],
            }
          : {'totals': {'total_remaining': 0}, 'perDebtor': const []});
    }
    if (path == '/api/admin/manager-debts') return ok({'debts': const []});
    if (path == '/api/v2/deleted-debts') {
      if (key == _kF) return _json(409, {'success': false, 'message': 'تعذّرت قراءة ديون المحذوفين — حاول بعد قليل'}, headers: h);
      if (key == _kC) return ok({'enabled': false, 'data': const [], 'totals': {'count': 0, 'debt': 0}});
      Map<String, Object?> row(String k, String name, int debt, String origin) =>
          {'key': k, 'origin': origin, 'name': name, 'debt': debt, 'username': 'u$k'};
      return ok(switch (key) {
        _kA => {'enabled': true, 'data': [row('a1', 'علي المحذوف', 25000, 'auto')], 'totals': {'count': 1, 'debt': 25000}},
        _kB => {
            'enabled': true,
            'data': [row('a2', 'زيد المحذوف', 15000, 'manual')],
            'totals': {'count': 1, 'debt': 15000},
            'twins_api': 2,
            'pending_twins': [
              {'manual_key': 'm9', 'auto_key': 'a7', 'manual': {'name': 'سعد', 'debt': 5000}, 'auto': {'debt': 5000}},
            ],
          },
        _ => {'enabled': true, 'data': const [], 'totals': {'count': 0, 'debt': 0}},
      });
    }
    final mv = RegExp(r'^/api/admin/managers/(\d+)/movements$').firstMatch(path);
    if (mv != null) {
      final id = mv.group(1);
      final rows = switch ((key, id)) {
        (_kA, '5') => [_move(11, 'deposit_cash', 50000, 9), _move(12, 'sas_pay_debt', 10000, 11)],
        (_kB, '5') => [_move(11, 'withdraw', 7000, 10)],
        _ => const <Map<String, Object?>>[],
      };
      return ok({'movements': rows});
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
        {'key': _kC, 'code': 'kr', 'username': 'k', 'name': 'كربلاء', 'status': 'ok', 'admin_id': 'kr:3', 'ns': 'nC', 'currency': 'IQD', 'color_index': 2},
        {'key': _kF, 'code': 'fx', 'username': 'f', 'name': 'فاشلة', 'status': 'ok', 'admin_id': 'fx:4', 'ns': 'nF', 'currency': 'IQD', 'color_index': 3},
        {'key': _kN, 'code': 'nabd', 'username': 'n', 'name': 'نبض', 'provider': 'kit', 'status': 'ok', 'admin_id': 'nabd:5', 'ns': 'nN', 'currency': 'IQD', 'color_index': 4},
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
    await t.pump(const Duration(seconds: 3));
    MergedMode.reset();
    await visualTearDown();
  }

  testWidgets('ديون المدراء: كلّ شركة ساس بطلباتها، المجموع للمقروء وحده، والمعرّف نفسه في شركتين مدينان', (t) async {
    await up();
    await t.runAsync(() => MergedMode.enter());
    await pumpVisual(t, const VisualDevice('', Size(390, 2400), 1), home: (_) => const AllManagersDebtsScreen());
    await settle(t, seconds: 3);

    // كلّ طلبٍ بمفتاح شركته؛ المُضافة لا تُطلب؛ وشركةٌ بلا مدراء فرعيّين لا يُطلب منها غير الوصول
    expect(srv.asked.where((a) => a.endsWith(' -')), isEmpty, reason: 'لا طلبٌ بلا مفتاح في الوضع');
    expect(srv.asked.where((a) => a.contains(_kN)), isEmpty);
    expect(srv.asked.where((a) => a.contains(_kC)), ['GET /api/admin/manager-debts/access $_kC']);
    expect(srv.asked, contains('GET /api/admin/managers/5/movements $_kA'));
    expect(srv.asked, contains('GET /api/admin/managers/5/movements $_kB'));

    // متبقّي الساس: m5 (100,000) + b5 (30,000) — m6 لم يُقرأ دينه فلا يُجمع؛ الأخرى 20,000؛ الإجمالي 150,000
    expect(find.text('130,000'), findsOneWidget);
    expect(find.text('20,000'), findsWidgets);
    expect(find.text('150,000'), findsOneWidget);
    // المستحصَل: شحن نقدي 50,000 + تسديد ساس 10,000 (السحب لا يُعدّ)
    expect(find.text('60,000'), findsOneWidget);
    expect(find.text('2 مدين'), findsOneWidget, reason: 'المدير 5 في سوبرنت غير المدير 5 في الجزيرة');
    expect(find.textContaining('خارج المجموع: «فاشلة»'), findsOneWidget);
    expect(find.textContaining('«سوبرنت»: دين 1 مدير لم يُقرأ من الساس'), findsOneWidget);
    // الشريط: بلا مدراء فرعيّين للمُضافة ولكربلاء، وسبب الفاشلة
    expect(find.text('· بلا مدراء فرعيّين'), findsNWidgets(2));
    expect(find.textContaining('«فاشلة»: انتهت جلسة «فاشلة»'), findsWidgets);
    // «حسب الشركة» وكلّ حركةٍ بشركتها
    expect(find.byKey(const ValueKey('merged-breakdown-$_kA')), findsOneWidget);
    expect(find.byKey(const ValueKey('merged-breakdown-$_kB')), findsOneWidget);
    expect(find.byKey(const ValueKey('merged-breakdown-$_kF')), findsOneWidget);
    expect(find.byKey(const ValueKey('merged-breakdown-$_kC')), findsNothing);
    expect(find.text('3 حركة'), findsNWidgets(2), reason: 'الملخّص وعنوان القائمة');
    expect(find.text('b5'), findsOneWidget);

    // الجزيرة وحدها
    await t.tap(find.byKey(const ValueKey('merged-breakdown-$_kB')));
    await settle(t, seconds: 1);
    expect(MergedMode.focus.value, _kB);
    expect(find.text('1 حركة'), findsNWidgets(2));
    expect(find.text('30,000'), findsWidgets);
    expect(find.text('m5'), findsNothing);
    expect(find.textContaining('خارج المجموع'), findsNothing);

    // الفاشلة وحدها: سببها لا أصفار
    MergedMode.focus.value = _kF;
    await settle(t, seconds: 1);
    expect(find.text('إجمالي المتبقّي'), findsNothing);
    expect(find.textContaining('«فاشلة»: انتهت جلسة «فاشلة»'), findsWidgets);
    await down(t);
  });

  testWidgets('ديون المحذوفين: كلّ شركةٍ بطلبٍ موجَّه، المجموع للمقروء وحده، والتسديد للمفتوحة وغيرها من داخلها', (t) async {
    await up();
    await t.runAsync(() => MergedMode.enter());
    await pumpVisual(t, const VisualDevice('', Size(390, 2400), 1), home: (_) => const DeletedDebtsScreen());
    await settle(t, seconds: 3);

    final dd = srv.asked.where((a) => a.startsWith('GET /api/v2/deleted-debts')).toSet();
    expect(dd, {
      'GET /api/v2/deleted-debts $_kA',
      'GET /api/v2/deleted-debts $_kB',
      'GET /api/v2/deleted-debts $_kC',
      'GET /api/v2/deleted-debts $_kF',
      'GET /api/v2/deleted-debts $_kN',
    }, reason: 'كلّ شركةٍ بمفتاحها — والمُضافة تخدمها (لا بلا مفتاح)');
    // العدد 2 والمجموع 40,000 (علي 25,000 + زيد 15,000) — الفاشلة خارجه باسمها، وكربلاء غير مفعّلة
    expect(find.text('40,000 د.ع'), findsOneWidget);
    expect(find.textContaining('خارج المجموع: «فاشلة»'), findsOneWidget);
    expect(find.text('· غير مفعّلة'), findsOneWidget);
    expect(find.text('علي المحذوف'), findsOneWidget);
    expect(find.text('زيد المحذوف'), findsOneWidget);
    expect(find.byKey(const ValueKey('merged-breakdown-$_kF')), findsOneWidget);
    // ديون الجزيرة المكرّرة: قرارها من داخلها
    expect(find.byKey(const ValueKey('dd-other-twins-$_kB')), findsOneWidget);
    expect(find.text('نفس الدين'), findsNothing, reason: 'لا زرّ قرارٍ لشركةٍ غير المفتوحة');
    // الإضافة للمفتوحة باسمها
    expect(find.text('إضافة دين · سوبرنت'), findsOneWidget);

    // تسديد دين الجزيرة ⇒ «افتحها»، ولا طلب تسديد
    await t.tap(find.text('تسديد').last);
    await settle(t, seconds: 1);
    expect(find.text('هذا الدين في «الجزيرة»'), findsOneWidget);
    expect(srv.asked.where((a) => a.contains('/pay')), isEmpty);
    await t.tap(find.text('إلغاء'));
    await settle(t, seconds: 1);

    // الجزيرة وحدها: لا زرّ إضافة (للمفتوحة)، وأرقامها وحدها
    MergedMode.focus.value = _kB;
    await settle(t, seconds: 1);
    expect(find.text('15,000 د.ع'), findsWidgets);
    expect(find.text('علي المحذوف'), findsNothing);
    expect(find.text('إضافة دين · سوبرنت'), findsNothing);
    await down(t);
  });
}
