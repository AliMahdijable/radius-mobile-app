import 'dart:convert';
import 'dart:io';
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

// لقطات ديون المدراء والمحذوفين في «كل الشركات» (مؤقّت للمراجعة — لا يُحفظ في المستودع). SHOT_TAG=before|after.
const _kA = 'c0000000000aa'; // المفتوحة (supernet:12)
const _kB = 'c0000000000bb';
const _kN = 'c0000000000cc';

ResponseBody _json(int status, Object body, {Map<String, List<String>> headers = const {}}) =>
    ResponseBody.fromString(jsonEncode(body), status, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
      ...headers,
    });

String _day(int back, int hour) {
  final d = DateTime.now().subtract(Duration(days: back));
  String two(int n) => n.toString().padLeft(2, '0');
  return '${d.year}-${two(d.month)}-${two(d.day)} ${two(hour)}:15:00';
}

Map<String, Object?> _mv(int id, String sub, int amount, int back, int hour, {String row = 'balance', String? note}) => {
      'row_type': row,
      'id': id,
      if (row == 'balance') 'sub_kind': sub,
      'amount': amount,
      'source': row == 'balance' ? 'sas4' : 'manual',
      'event_at': _day(back, hour),
      if (note != null) 'note': note,
    };

final _managers = {
  _kA: [
    {'id': 5, 'username': 'ahmed.net', 'firstname': 'أحمد', 'lastname': 'الربيعي', 'total_debt': 450000},
    {'id': 6, 'username': 'hussein.w', 'firstname': 'حسين', 'lastname': 'وائل', 'total_debt': 120000},
    {'id': 7, 'username': 'mustafa.k', 'firstname': 'مصطفى', 'lastname': 'كاظم', 'total_debt': 0},
  ],
  _kB: [
    {'id': 5, 'username': 'ali.jz', 'firstname': 'علي', 'lastname': 'جبار', 'total_debt': 300000},
    {'id': 9, 'username': 'saad.f', 'firstname': 'سعد', 'lastname': 'فاضل', 'total_debt': 0, 'debt_unavailable': true},
  ],
};

final _moves = {
  '$_kA/5': [_mv(41, 'deposit_cash', 250000, 0, 10), _mv(38, 'sas_pay_debt', 100000, 1, 18)],
  '$_kA/6': [_mv(44, 'deposit_loan', 120000, 0, 12)],
  '$_kA/7': [_mv(30, 'points', 500, 2, 9)],
  '$_kB/5': [_mv(17, 'withdraw', 50000, 0, 9), _mv(3, '', 100000, 1, 11, row: 'debt_created', note: 'كارتات 25 ألف')],
};

final _summary = {
  _kA: {
    'totals': {'total_remaining': 75000, 'debts_count': 1},
    'perDebtor': [
      {'debtor_admin_id': 5, 'debtor_admin_username': 'ahmed.net', 'debts_count': 1, 'total_remaining': 75000},
    ],
  },
  _kB: {
    'totals': {'total_remaining': 100000, 'debts_count': 1},
    'perDebtor': [
      {'debtor_admin_id': 5, 'debtor_admin_username': 'ali.jz', 'debts_count': 1, 'total_remaining': 100000},
    ],
  },
};

Map<String, Object?> _dd(String k, String origin, String name, int debt, {String? user, String? phone, int back = 3}) => {
      'key': k,
      'origin': origin,
      'name': name,
      'debt': debt,
      if (user != null) 'username': user,
      if (phone != null) 'phone': phone,
      'at': DateTime.now().subtract(Duration(days: back)).toUtc().toIso8601String(),
    };

final _deleted = {
  _kA: {
    'enabled': true,
    'data': [
      _dd('a11', 'auto', 'حيدر سلمان', 35000, user: 'haider.s', phone: '9647701234567'),
      _dd('m3', 'manual', 'كرار محمد', 20000, back: 6),
    ],
    'totals': {'count': 2, 'debt': 55000},
  },
  _kB: {
    'enabled': true,
    'twins_api': 2,
    'data': [_dd('a24', 'auto', 'زينب علي', 45000, user: 'zainab.a', back: 1)],
    'totals': {'count': 1, 'debt': 45000},
    'pending_twins': [
      {'manual_key': 'm9', 'auto_key': 'a7', 'manual': {'name': 'سعد كريم', 'debt': 15000}, 'auto': {'debt': 15000}},
    ],
  },
  _kN: {'enabled': true, 'data': const [], 'totals': {'count': 0, 'debt': 0}},
};

class _Srv implements HttpClientAdapter {
  _Srv(this.inner);
  final HttpClientAdapter inner;

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? rs, Future<void>? cf) async {
    final routed = o.headers['x-company-key'] as String?;
    final path = o.uri.path;
    // قبل: الشاشة تطلب بلا مفتاح ⇒ المفتوحة (سوبرنت)
    final key = routed ?? _kA;
    final h = {if (routed != null) 'x-company-key': [routed]};
    Future<ResponseBody> ok(Map<String, Object?> body) async => _json(200, {'success': true, ...body}, headers: h);
    if (path == '/api/admin/manager-debts/access') return ok({'hasSubAdmins': key != _kN, 'subAdmins': const []});
    if (path == '/api/v2/managers/full') {
      final rows = _managers[key] ?? const [];
      return ok({'data': rows, 'total': rows.length});
    }
    if (path == '/api/admin/manager-debts/summary') return ok(_summary[key] ?? {'totals': {'total_remaining': 0}});
    if (path == '/api/admin/manager-debts') return ok({'debts': const []});
    final mv = RegExp(r'^/api/admin/managers/(\d+)/movements$').firstMatch(path);
    if (mv != null) return ok({'movements': _moves['$key/${mv.group(1)}'] ?? const []});
    if (path == '/api/v2/deleted-debts') return ok(_deleted[key] ?? {'enabled': false});
    if (routed == null) return inner.fetch(o, rs, cf);
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
        {'key': _kN, 'code': 'nabd', 'username': 'n', 'name': 'نبض', 'provider': 'kit', 'status': 'ok', 'admin_id': 'nabd:5', 'ns': 'nN', 'currency': 'IQD', 'color_index': 2},
      ],
    };

void main() {
  setUpAll(visualSetUpAll);
  final tag = Platform.environment['SHOT_TAG'] ?? 'after';
  const devs = [
    VisualDevice('', Size(390, 844), 3),
    VisualDevice('_dark', Size(390, 844), 3, dark: true),
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
    testWidgets('manager debts ${d.tag}', (t) async {
      await open(t, d, () => const AllManagersDebtsScreen());
      await shoot(t, s1bSasOwner, 'mdebts_$tag', d, inner);
      if (tag == 'after' && d.tag.isEmpty) {
        await t.drag(find.byType(CustomScrollView), const Offset(0, -560));
        await settle(t, seconds: 1);
        await shoot(t, s1bSasOwner, 'mdebts_${tag}_scroll', d, inner);
        MergedMode.focus.value = _kB;
        await settle(t, seconds: 1);
        await t.drag(find.byType(CustomScrollView), const Offset(0, 900));
        await settle(t, seconds: 1);
        await shoot(t, s1bSasOwner, 'mdebts_${tag}_focus', d, inner);
      }
      await down(t);
    });

    testWidgets('deleted debts ${d.tag}', (t) async {
      await open(t, d, () => const DeletedDebtsScreen());
      await shoot(t, s1bSasOwner, 'ddebts_$tag', d, inner);
      if (tag == 'after' && d.tag.isEmpty) {
        await t.drag(find.byType(ListView).first, const Offset(0, -520));
        await settle(t, seconds: 1);
        await shoot(t, s1bSasOwner, 'ddebts_${tag}_scroll', d, inner);
      }
      await down(t);
    });
  }
}
