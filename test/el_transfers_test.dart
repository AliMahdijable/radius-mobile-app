import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/core/util/amount_input.dart';
import 'package:rad_mysvcs/models/subscriber.dart';
import 'package:rad_mysvcs/screens/subscribers/sheets/activate_sheet.dart';
import 'package:rad_mysvcs/services/transfer_pay.dart';

import 'visual_perm/visual_perm_harness.dart';

/// «الحوالات» لايرث لنك بالتطبيق (٢٤ نوفمبر — الخادم 5fe0e14، الموقع 076bab4): شيت التفعيل بوضع ايرث لنك (provider في
/// activation-data) — «استلمته» كالساس مع رصيد أونلاين (deposit) والباقة. مبنيٌّ على transfers_wiring_test (الخادم الوهميّ نفسه).
/// (الأصل) «الحوالات» بالتطبيق (٢٣ نوفمبر — الخادم abd6761، الموقع 1f51a9a): ما يُرسل فعلاً. خادمٌ وهميّ يسجّل كلّ طلب:
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
      'profile_duration': null,
      'current_balance': -35000,
      'provider': 'earthlink',
      'activation_methods': {'credit': true, 'deposit': true, 'card': true},
      'cards': {'enabled': false, 'profile_id': 7, 'profile_name': 'Plus', 'available': null},
      'packages': [
        {'id': 7, 'name': 'Plus', 'price': 35000, 'cost': 30000},
        {'id': 9, 'name': 'Gold', 'price': 50000, 'cost': 44000},
      ],
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
    if (p == '/api/v2/el/deposit-password') {
      return _json({'success': true, 'data': {'saved': true, 'can_manage': true, 'updated_at': '2026-11-01 10:00:00'}});
    }
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
  testWidgets('ايرث لنك مطفأ: لا «استلمته»، والتفعيل النقديّ deposit بلا paid_via (كما كان حرفاً)', (t) async {
    await _up(on: false);
    await _open(t, (c) => showActivateSheet(c, _hussein()));
    await _tapText(t, 'نقدي');
    expect(find.byKey(const ValueKey('paid-via-picker')), findsNothing);
    await _tapText(t, 'تجديد الآن');
    final b = _only('activate');
    expect(b['paymentType'], 'cash');
    expect(b['method'], 'deposit');
    expect(b.containsKey('paid_via'), isFalse);
    await _down(t);
  });

  testWidgets('ايرث لنك: النقديّ بزين كاش ⇒ paid_via=zaincash مع deposit والباقة', (t) async {
    await _up();
    await _open(t, (c) => showActivateSheet(c, _hussein()));
    await _tapText(t, 'نقدي');
    expect(find.byKey(const ValueKey('paid-via-picker')), findsOneWidget, reason: 'ايرث لنك تُظهرها كالساس');
    await _tapKey(t, 'paid-via-zaincash');
    await _tapText(t, 'تجديد الآن');
    final b = _only('activate');
    expect(b['paymentType'], 'cash');
    expect(b['method'], 'deposit');
    expect(b['profile_id'], 7);
    expect(b['paid_via'], 'zaincash');
    expect(b.containsKey('paid_via_name'), isFalse);
    await _down(t);
  });

  testWidgets('ايرث لنك: الكاش الافتراضيّ لا يُرسل شيئاً', (t) async {
    await _up();
    await _open(t, (c) => showActivateSheet(c, _hussein()));
    await _tapText(t, 'نقدي');
    await _tapText(t, 'تجديد الآن');
    final b = _only('activate');
    expect(b.containsKey('paid_via'), isFalse);
    await _down(t);
  });

  testWidgets('ايرث لنك: الجزئيّ + «أخرى» — بلا اسم لا يُرسل، وبالاسم partial + other + الاسم', (t) async {
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
    expect(b['method'], 'deposit');
    expect(b['paid_via'], 'other');
    expect(b['paid_via_name'], 'آسيا حوالة');
    await _down(t);
  });

  testWidgets('ايرث لنك: زين كاش ثمّ «دين» ⇒ لا «استلمته» ولا paid_via', (t) async {
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

  testWidgets('ايرث لنك: صفّ شركةٍ أخرى («كل الشركات») ⇒ لا «استلمته»', (t) async {
    await _up();
    await _open(t, (c) => showActivateSheet(c, _hussein(companyKey: 'c0123456789ab')));
    await _tapText(t, 'نقدي');
    expect(find.byKey(const ValueKey('paid-via-picker')), findsNothing);
    await _down(t);
  });
}
