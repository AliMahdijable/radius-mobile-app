import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/api/transfer_pay_api.dart';
import 'package:rad_mysvcs/core/util/amount_input.dart';
import 'package:rad_mysvcs/models/subscriber.dart';
import 'package:rad_mysvcs/screens/settlements/transfer_pots.dart';
import 'package:rad_mysvcs/screens/subscribers/sheets/activate_sheet.dart';
import 'package:rad_mysvcs/screens/subscribers/sheets/add_credit_sheet.dart';
import 'package:rad_mysvcs/screens/subscribers/sheets/pay_debt_sheet.dart';
import 'package:rad_mysvcs/services/transfer_pay.dart';

import 'visual_perm/visual_perm_harness.dart';

/// «الحوالات» بالتطبيق (٢٣ نوفمبر — الخادم abd6761، الموقع 1f51a9a): ما يُرسل فعلاً. خادمٌ وهميّ يسجّل كلّ طلب:
/// - الكاش (أو الميزة مطفأة، أو صفّ شركةٍ أخرى) لا يُرسل paid_via أبداً — الطلب كما كان حرفاً.
/// - الحوالة paid_via (+ paid_via_name لـ«أخرى»)، و«أخرى» بلا اسم لا تُرسل؛ الآجل والتعويض بلا paid_via.
/// - «سحب للصندوق» بمفتاحٍ ثابتٍ للشيت: الإعادة بعد انقطاعٍ بالمفتاح نفسه.
const _phone = VisualDevice('390', Size(390, 844), 3);

class _Server implements HttpClientAdapter {
  _Server(this.inner, {this.on = true, this.abortWithdraws = 0});
  final HttpClientAdapter inner;
  final bool on;
  int abortWithdraws;
  final posts = <String, List<Map<String, dynamic>>>{};
  int infoReads = 0;

  static const _activation = {
    'success': true,
    'data': {
      'idx': '3',
      'username': 'hussein77@najaf',
      'firstname': 'حسين',
      'lastname': 'عبد الأمير',
      'user_price': 35000,
      'price_after_discount': 35000,
      'base_price': 35000,
      'profile_name': 'Plus',
      'profile_id': 7,
      'profile_duration': '30',
      'current_balance': -35000,
      'manager_balance': 1505000,
      'reward_points': 2,
      'manager_cost': 21000,
      'phone': '07701000003',
      'activation_methods': {'credit': true, 'card': false},
      'cards': {'enabled': false},
    },
  };

  static const pots = {
    'available': true,
    'pots': [
      {'key': 'zaincash', 'via': 'zaincash', 'name': null, 'label': 'زين كاش', 'received': 175000, 'withdrawn': 50000, 'balance': 125000, 'count': 5},
      {'key': 'other:آسيا حوالة', 'via': 'other', 'name': 'آسيا حوالة', 'label': 'آسيا حوالة', 'received': 25000, 'withdrawn': 0, 'balance': 25000, 'count': 1},
    ],
    'total': 150000,
    'withdrawals': [
      {'id': 7, 'via': 'zaincash', 'name': null, 'label': 'زين كاش', 'amount': 50000, 'kind': 'withdraw', 'ref_id': null, 'voided': false, 'note': null, 'created_at': '2026-11-23 18:10:00'},
    ],
    'can_withdraw': true,
  };

  RequestOptions? _req;

  /// ردٌّ بصدى مفتاح الشركة حين يُطلب موجَّهاً («كل الشركات») — كالخادم الحقيقيّ.
  ResponseBody _json(Object body, [int status = 200]) {
    final key = _req?.headers['x-company-key']?.toString();
    return ResponseBody.fromString(jsonEncode(body), status, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
      if (key != null && key.isNotEmpty) 'x-company-key': [key],
    });
  }

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    final p = o.path;
    _req = o;
    if (p.endsWith('/activation-data')) return _json(_activation);
    if (p == '/api/v2/transfer-pay') {
      infoReads++;
      return _json({'success': true, 'data': {'available': on, 'methods': ['cash', 'zaincash', 'master', 'other'], 'names': on ? ['آسيا حوالة'] : []}});
    }
    if (p == '/api/v2/transfer-pots') return _json({'success': true, 'data': pots});
    if (o.method == 'POST') {
      final body = o.data is Map ? Map<String, dynamic>.from(o.data as Map) : <String, dynamic>{};
      final key = p.endsWith('/activate')
          ? 'activate'
          : p.endsWith('/pay-debt')
              ? 'pay'
              : p.endsWith('/add-credit')
                  ? 'credit'
                  : p.endsWith('/transfer-pots/withdraw')
                      ? 'withdraw'
                      : p.contains('/transfer-pots/withdrawals/')
                          ? 'void'
                          : null;
      if (key != null) {
        (posts[key] ??= []).add({...body, '_path': p});
        if (key == 'withdraw' && abortWithdraws > 0) {
          abortWithdraws--;
          throw DioException.connectionError(requestOptions: o, reason: 'انقطاع (اختبار)');
        }
        return _json({
          'success': true,
          'message': 'تم',
          if (key == 'withdraw') 'duplicate': (posts['withdraw']!.where((b) => b['client_ref'] == body['client_ref']).length > 1),
          'data': {
            'new_balance': 0,
            'remaining_debt': 0,
            'credit': 0,
            'amount_paid': 35000,
            'updated': {'idx': '3', 'username': 'hussein77@najaf', 'expiration': '2026-12-31 00:00:00', 'remaining_days': 30, 'notes': '0'},
            'withdrawal': {'id': 8, 'via': body['paid_via'], 'amount': body['amount'], 'kind': 'withdraw'},
            'pots': const [],
          },
        });
      }
    }
    return inner.fetch(o, requestStream, cancelFuture);
  }

  @override
  void close({bool force = false}) {}
}

late _Server _srv;

Future<void> _up({bool on = true, int abortWithdraws = 0}) async {
  final server = await visualSetUp(s1bSasOwner);
  _srv = _Server(server, on: on, abortWithdraws: abortWithdraws);
  ApiClient.dio.httpClientAdapter = _srv;
  TransferPay.reset();
}

Future<void> _down(WidgetTester t) async {
  await t.pumpWidget(const SizedBox.shrink());
  await t.pump(const Duration(seconds: 4));
  TransferPay.reset();
  await visualTearDown();
}

Subscriber _hussein({String? companyKey}) {
  final s = Subscriber.fromJson(Map<String, dynamic>.from(fixtureSubscribers[2]));
  return companyKey == null ? s : s.withCompany(companyKey);
}

Future<void> _open(WidgetTester t, Future<void> Function(BuildContext c) open) async {
  await pumpVisual(
    t,
    _phone,
    home: (c) => Scaffold(body: Center(child: TextButton(onPressed: () => open(c), child: const Text('افتح')))),
  );
  await settle(t, seconds: 1);
  await t.tap(find.text('افتح'));
  await settle(t, seconds: 3);
}

Future<void> _tapKey(WidgetTester t, String key) async {
  final f = find.byKey(ValueKey(key));
  await t.ensureVisible(f);
  await t.pump();
  await t.tap(f);
  await settle(t, seconds: 1);
}

Future<void> _tapText(WidgetTester t, String text) async {
  final f = find.text(text).last;
  await t.ensureVisible(f);
  await t.pump();
  await t.tap(f);
  await settle(t, seconds: 2);
}

Map<String, dynamic> _only(String key) {
  final l = _srv.posts[key] ?? const [];
  expect(l.length, 1, reason: 'طلب $key واحد: $l');
  return l.single;
}

void main() {
  setUpAll(visualSetUpAll);

  test('PaidVia.toBody: الكاش {} — الحوالة طريقتها — «أخرى» باسمها', () {
    expect(PaidVia.cash.toBody(), isEmpty);
    expect(PaidVia.zaincash.toBody(), {'paid_via': 'zaincash'});
    expect(const PaidVia('other', ' آسيا حوالة ').toBody(), {'paid_via': 'other', 'paid_via_name': 'آسيا حوالة'});
    expect(const PaidVia('other', '').valid, isFalse);
    expect(PaidVia.fromRequest('master'), PaidVia.master);
    expect(PaidVia.fromRequest('other'), const PaidVia('other', ''));
    expect(PaidVia.fromRequest(null), PaidVia.cash);
  });

  test('TransferPotsData.fromJson + CashByViaData.rows (الكاش = المجموع − الحوالات)', () {
    final d = TransferPotsData.fromJson(Map<String, dynamic>.from(_Server.pots));
    expect(d.pots.map((p) => p.key), ['zaincash', 'other:آسيا حوالة']);
    expect(d.pots.last.name, 'آسيا حوالة');
    expect(d.total, 150000);
    expect(d.withdrawals.single.id, 7);
    expect(d.canWithdraw, isTrue);
    expect(TransferPotsData.fromJson(const {'available': false, 'pots': [], 'withdrawals': []}).hidden, isTrue);
    final c = CashByViaData.fromJson({
      'cash': 1250000,
      'transfers_sum': 260000,
      'transfers': [
        {'key': 'zaincash', 'via': 'zaincash', 'label': 'زين كاش', 'sum': 175000, 'count': 5},
        {'key': 'master', 'via': 'master', 'label': 'ماستر', 'sum': 85000, 'count': 2},
      ],
    })!;
    final rows = c.rows(1510000);
    expect(rows.first.label, 'كاش');
    expect(rows.first.sum, 1250000);
    expect(rows.fold<num>(0, (s, r) => s + r.sum), 1510000, reason: 'المجموع نفسه');
    expect(CashByViaData.fromJson({'cash': 1, 'transfers': []}), isNull, reason: 'بلا حوالات ⇒ لا بطاقة');
  });

  testWidgets('مطفأ: لا «استلمته»، والتفعيل النقديّ بلا paid_via (كما كان حرفاً)', (t) async {
    await _up(on: false);
    await _open(t, (c) => showActivateSheet(c, _hussein()));
    await _tapText(t, 'نقدي');
    expect(find.byKey(const ValueKey('paid-via-picker')), findsNothing);
    await _tapText(t, 'تجديد الآن');
    final b = _only('activate');
    expect(b['paymentType'], 'cash');
    expect(b.containsKey('paid_via'), isFalse);
    expect(_srv.infoReads, greaterThanOrEqualTo(1), reason: 'سأل الخادم');
    await _down(t);
  });

  testWidgets('التفعيل النقديّ: الكاش الافتراضيّ لا يُرسل شيئاً', (t) async {
    await _up();
    await _open(t, (c) => showActivateSheet(c, _hussein()));
    await _tapText(t, 'نقدي');
    expect(find.byKey(const ValueKey('paid-via-picker')), findsOneWidget);
    await _tapText(t, 'تجديد الآن');
    final b = _only('activate');
    expect(b['paymentType'], 'cash');
    expect(b.containsKey('paid_via'), isFalse);
    await _down(t);
  });

  testWidgets('التفعيل النقديّ بزين كاش ⇒ paid_via=zaincash بلا اسم', (t) async {
    await _up();
    await _open(t, (c) => showActivateSheet(c, _hussein()));
    await _tapText(t, 'نقدي');
    await _tapKey(t, 'paid-via-zaincash');
    await _tapText(t, 'تجديد الآن');
    final b = _only('activate');
    expect(b['paymentType'], 'cash');
    expect(b['paid_via'], 'zaincash');
    expect(b.containsKey('paid_via_name'), isFalse);
    await _down(t);
  });

  testWidgets('الجزئيّ + «أخرى»: بلا اسم لا يُرسل — وبالاسم partial + other + الاسم', (t) async {
    await _up();
    await _open(t, (c) => showActivateSheet(c, _hussein()));
    await _tapText(t, 'جزئي');
    await t.enterText(find.descendant(of: find.byType(AmountTextField), matching: find.byType(TextField)).first, '20000');
    await settle(t, seconds: 1);
    await _tapKey(t, 'paid-via-other');
    await _tapText(t, 'تجديد الآن');
    expect(_srv.posts['activate'], isNull, reason: '«أخرى» بلا اسم ⇒ الزرّ معطّل');
    await t.enterText(find.byKey(const ValueKey('paid-via-other-name')), 'آسيا حوالة');
    await settle(t, seconds: 1);
    await _tapText(t, 'تجديد الآن');
    final b = _only('activate');
    expect(b['paymentType'], 'partial-cash');
    expect(b['partialAmount'], 20000);
    expect(b['paid_via'], 'other');
    expect(b['paid_via_name'], 'آسيا حوالة');
    await _down(t);
  });

  testWidgets('زين كاش ثمّ «دين» (آجل) ⇒ لا «استلمته» ولا paid_via', (t) async {
    await _up();
    await _open(t, (c) => showActivateSheet(c, _hussein()));
    await _tapText(t, 'نقدي');
    await _tapKey(t, 'paid-via-zaincash');
    await _tapText(t, 'دين');
    expect(find.byKey(const ValueKey('paid-via-picker')), findsNothing);
    await _tapText(t, 'تجديد الآن');
    final b = _only('activate');
    expect(b['paymentType'], 'non-cash');
    expect(b.containsKey('paid_via'), isFalse);
    await _down(t);
  });

  testWidgets('طلب تجديدٍ بماستر ⇒ «استلمته» ماستر مسبقاً', (t) async {
    await _up();
    final sub = _hussein();
    TransferPay.hint(sub.idx, PaidVia.fromRequest('master'));
    await _open(t, (c) => showActivateSheet(c, sub));
    await _tapText(t, 'نقدي');
    await _tapText(t, 'تجديد الآن');
    expect(_only('activate')['paid_via'], 'master');
    TransferPay.clearHint(sub.idx);
    await _down(t);
  });

  testWidgets('صفّ شركةٍ أخرى («كل الشركات») ⇒ لا «استلمته» ولا paid_via', (t) async {
    await _up();
    await _open(t, (c) => showActivateSheet(c, _hussein(companyKey: 'c0123456789ab')));
    await _tapText(t, 'نقدي');
    expect(find.byKey(const ValueKey('paid-via-picker')), findsNothing);
    await _down(t);
  });

  testWidgets('تسديد الدين بماستر ⇒ paid_via=master؛ والكاش الافتراضيّ بلا شيء', (t) async {
    await _up();
    await _open(t, (c) => showPayDebtSheet(c, _hussein()));
    await _tapText(t, 'كامل الدين');
    await _tapKey(t, 'paid-via-master');
    await _tapText(t, 'تسديد الآن');
    final b = _only('pay');
    expect(b['payAll'], isTrue);
    expect(b['paid_via'], 'master');
    await _down(t);

    await _up();
    await _open(t, (c) => showPayDebtSheet(c, _hussein()));
    await _tapText(t, 'كامل الدين');
    await _tapText(t, 'تسديد الآن');
    expect(_only('pay').containsKey('paid_via'), isFalse);
    await _down(t);
  });

  testWidgets('إضافة رصيد: «استلمت المبلغ» بزين كاش ⇒ paid_via؛ والتعويض بلا «استلمته» ولا paid_via', (t) async {
    await _up();
    await _open(t, (c) => showAddCreditSheet(c, _hussein(), initialAmount: 10000));
    await _tapText(t, 'استلمت المبلغ');
    await _tapKey(t, 'paid-via-zaincash');
    await _tapText(t, 'إضافة رصيد');
    await _tapText(t, 'تأكيد');
    final b = _only('credit');
    expect(b['credit_kind'], 'cash');
    expect(b['paid_via'], 'zaincash');
    await _down(t);

    await _up();
    await _open(t, (c) => showAddCreditSheet(c, _hussein(), initialAmount: 7000));
    await _tapText(t, 'تعويض بلا نقد');
    expect(find.byKey(const ValueKey('paid-via-picker')), findsNothing);
    await _tapText(t, 'إضافة رصيد');
    await _tapText(t, 'تأكيد');
    final c = _only('credit');
    expect(c['credit_kind'], 'comp');
    expect(c.containsKey('paid_via'), isFalse);
    await _down(t);
  });

  testWidgets('«سحب للصندوق»: كامل الرصيد افتراضاً، وانقطاعٌ ثمّ إعادة بالمفتاح نفسه', (t) async {
    await _up(abortWithdraws: 1);
    final d = TransferPotsData.fromJson(Map<String, dynamic>.from(_Server.pots));
    await _open(t, (c) => showTransferWithdrawSheet(c, d.pots.first));
    await t.tap(find.byKey(const ValueKey('transfer-withdraw-confirm')));
    await settle(t, seconds: 2);
    expect(find.byKey(const ValueKey('transfer-withdraw-confirm')), findsOneWidget, reason: 'لم نتأكّد ⇒ الشيت باقٍ');
    await t.tap(find.byKey(const ValueKey('transfer-withdraw-confirm')));
    await settle(t, seconds: 2);
    final l = _srv.posts['withdraw']!;
    expect(l.length, 2);
    expect(l.first['paid_via'], 'zaincash');
    expect(l.first['amount'], 125000);
    expect(l.first.containsKey('paid_via_name'), isFalse);
    expect(RegExp(r'^tw[0-9a-f]{32}$').hasMatch('${l.first['client_ref']}'), isTrue);
    expect(l.last['client_ref'], l.first['client_ref'], reason: 'الإعادة بالمفتاح نفسه');
    await _down(t);
  });

  testWidgets('«سحب للصندوق» من «أخرى» يرسل اسمها', (t) async {
    await _up();
    final d = TransferPotsData.fromJson(Map<String, dynamic>.from(_Server.pots));
    await _open(t, (c) => showTransferWithdrawSheet(c, d.pots.last));
    await t.tap(find.byKey(const ValueKey('transfer-withdraw-confirm')));
    await settle(t, seconds: 2);
    final b = _only('withdraw');
    expect(b['paid_via'], 'other');
    expect(b['paid_via_name'], 'آسيا حوالة');
    expect(b['amount'], 25000);
    await _down(t);
  });
}
