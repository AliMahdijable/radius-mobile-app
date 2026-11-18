import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/api/employees_api.dart';
import 'package:rad_mysvcs/api/op_voids_api.dart';
import 'package:rad_mysvcs/api/payment_voids_api.dart';
import 'package:rad_mysvcs/api/reports_api.dart';
import 'package:rad_mysvcs/models/subscriber.dart';
import 'package:rad_mysvcs/screens/subscribers/sheets/movements_sheet.dart';
import 'package:rad_mysvcs/widgets/payment_void_bits.dart';

import 'visual_perm/visual_perm_harness.dart';

/// «إلغاء إضافة دين/رصيد» بالتطبيق (١٧ نوفمبر ٢٠٢٦ — الخادم 1ee5c47 + 39761f0، والويب 1cf8c73).
///   • النموذج: الحال وزرّ السطر لكلّ نوع (يفتح · مقفل «لا صلاحيّة» · لا شيء)، والملغاة بلا زرّ.
///   • سجل حركات المشترك: الزرّ على «إضافة دين/رصيد» وحدها، وسطر الإلغاء باسمه، والنافذة: «الآن ⇒ بعد»، ثمّ الطلب بما رآه.
///   • الموظّف بلا صلاحيّة نوعٍ: زرّه بمكانه مقفلاً؛ والميزة مطفأة ⇒ لا زرّ.
///   • نتيجةٌ لم يؤكّدها الساس تُحسم من النافذة نفسها.
class _OvServer implements HttpClientAdapter {
  _OvServer(this.inner);
  final HttpClientAdapter inner;

  Map<String, dynamic> status = {'enabled': true, 'can_void_debt': true, 'can_void_credit': true, 'own_only': false, 'items': []};
  (int, Map<String, dynamic>)? nextRun;
  final statusCalls = <String>[];
  final previews = <int>[];
  final posts = <(String, Map<String, dynamic>)>[];
  int statementGets = 0;

  List<Map<String, dynamic>> statement = [
    {
      'id': 901, 'created_at': '2026-11-17 09:30:00', 'action_type': 'BALANCE_ADD', 'description': 'إضافة دين 20000 د.ع للمشترك ali.kareem',
      'amount': 20000, 'balance_after': -45000, 'admin_name': 'page2', 'op_activity_id': 901, 'op_kind': 'add_debt',
    },
    {
      'id': 902, 'created_at': '2026-11-17 09:00:00', 'action_type': 'BALANCE_ADD',
      'description': 'إضافة رصيد 15000 د.ع (مقدّم نقداً) للمشترك ali.kareem', 'amount': -15000, 'balance_after': -25000,
      'admin_name': 'page2', 'op_activity_id': 902, 'op_kind': 'add_credit', 'op_credit_kind': 'cash',
    },
    {
      'id': 903, 'created_at': '2026-11-16 12:00:00', 'action_type': 'BALANCE_ADD',
      'description': 'إلغاء إضافة دين 5,000 د.ع للمشترك ali.kareem — ألغاه المدير page2', 'amount': -5000, 'balance_after': -40000,
      'admin_name': 'page2', 'op_void': true, 'void_kind': 'add_debt',
    },
    {
      'id': 900, 'created_at': '2026-11-15 12:00:00', 'action_type': 'BALANCE_DEDUCT', 'description': 'تسديد دين 10000 د.ع',
      'amount': 10000, 'balance_after': -35000, 'admin_name': 'page2', 'payment_activity_id': 900,
    },
    {
      'id': 899, 'created_at': '2026-11-14 22:30:00', 'action_type': 'BALANCE_ADD',
      'description': 'إضافة دين 12000 د.ع للمشترك ali.kareem - بيع #41: راوتر', 'amount': 12000, 'balance_after': -45000,
      'admin_name': 'page2', 'sale_id': 41,
    },
  ];
  final salesAsks = <Map<String, dynamic>>[];

  static ResponseBody _json(int status, Object body) =>
      ResponseBody.fromString(jsonEncode(body), status, headers: {
        Headers.contentTypeHeader: ['application/json; charset=utf-8'],
      });

  Map<String, dynamic> _preview(int id) {
    final debt = id == 901;
    return {
      'op': {
        'id': id, 'kind': debt ? 'add_debt' : 'add_credit', 'credit_kind': debt ? null : 'cash', 'amount': debt ? 20000 : 15000,
        'subscriber': 'ali.kareem', 'idx': '132076', 'at': '2026-11-17T06:30:00Z',
        'origin': debt ? {'employee_id': 7, 'username': 'hosny'} : {'employee_id': null, 'username': null},
      },
      'balance_delta': debt ? 20000 : -15000,
      'effects': {'new_debts': debt ? -20000 : 0, 'cash': debt ? 0 : -15000, 'profit': 0},
      'can_void': true,
      'void': null,
      'settlement_number': debt ? null : 3,
    };
  }

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    final p = o.path;
    final get = o.method == 'GET';
    if (get && p == '/api/reports/account-statement') {
      statementGets += 1;
      return _json(200, {'success': true, 'data': {'subscriber': {'username': 'ali.kareem'}, 'transactions': statement}});
    }
    if (get && p == '/api/v2/sales') {
      salesAsks.add(Map<String, dynamic>.from(o.queryParameters));
      return _json(200, {'success': true, 'enabled': true, 'data': [], 'totals': {'count': 0, 'revenue': 0, 'cost': 0, 'profit': 0, 'cash': 0}});
    }
    if (get && p == '/api/v2/payment-voids/status') {
      return _json(200, {'success': true, 'enabled': false, 'can_void': false, 'can_link': false, 'own_only': false, 'items': []});
    }
    if (get && p == '/api/v2/op-voids/status') {
      statusCalls.add((o.queryParameters['ids'] ?? '').toString());
      return _json(200, {'success': true, ...status});
    }
    final pm = RegExp(r'^/api/v2/op-voids/preview/(\d+)$').firstMatch(p);
    if (get && pm != null) {
      final id = int.parse(pm.group(1)!);
      previews.add(id);
      return _json(200, {'success': true, 'data': _preview(id)});
    }
    if (o.method == 'POST' && p.startsWith('/api/v2/op-voids')) {
      final body = Map<String, dynamic>.from(o.data as Map);
      posts.add((p, body));
      if (p == '/api/v2/op-voids') {
        final r = nextRun;
        nextRun = null;
        if (r != null) return _json(r.$1, r.$2);
        return _json(200, {
          'success': true,
          'data': {'void_id': 1, 'op_id': body['op_id'], 'kind': body['expect_kind'], 'status': 'done', 'amount': body['expect_amount'],
            'previous_balance': -45000, 'new_balance': -25000},
        });
      }
      return _json(200, {'success': true, 'data': {'void_id': 77, 'op_id': 901, 'kind': 'add_debt', 'status': 'done', 'amount': 20000}});
    }
    return inner.fetch(o, requestStream, cancelFuture);
  }

  @override
  void close({bool force = false}) => inner.close(force: force);
}

/// أضيق هاتفٍ ندعمه — لا فيض.
const _narrow = VisualDevice('_320', Size(320, 1100), 2);

final _sub = Subscriber(idx: '132076', username: 'ali.kareem', firstname: 'علي', lastname: 'كريم');

Finder _rowButtons(PaymentVoidAction a) =>
    find.byWidgetPredicate((w) => w is PaymentVoidRowButton && w.action == a && w.tipOpen == 'إلغاء الحركة');

void main() {
  setUpAll(visualSetUpAll);

  group('النموذج', () {
    test('الحال: enabled شرط، والنوعان كلٌّ بصلاحيّته، والملغاة بلا زرّ، ومقفلٌ لمن لا يملكها', () {
      expect(OpVoidStatus.fromJson({'success': false}), isNull);
      final off = OpVoidStatus.fromJson({'enabled': false, 'can_void_debt': true, 'can_void_credit': true})!;
      expect((off.canVoidDebt, off.canVoidCredit), (false, false));
      expect(off.actionFor(5, OpKind.addDebt), PaymentVoidAction.none);
      final st = OpVoidStatus.fromJson({
        'enabled': true,
        'can_void_debt': true,
        'can_void_credit': false,
        'own_only': true,
        'items': [
          {'void_id': 1, 'op_id': 5, 'kind': 'add_debt', 'status': 'done', 'amount': 20000},
          {'void_id': 2, 'op_id': 6, 'kind': 'add_credit', 'credit_kind': 'cash', 'status': 'unknown', 'amount': 15000},
          {'void_id': 3, 'op_id': 7, 'kind': 'pay', 'status': 'done', 'amount': 1},
        ],
      })!;
      expect(st.items.keys.toSet(), {5, 6}, reason: 'نوعٌ غير معروف يُسقط');
      expect(st.actionFor(5, OpKind.addDebt), PaymentVoidAction.none, reason: 'ملغاة');
      expect(st.actionFor(8, OpKind.addDebt), PaymentVoidAction.open);
      expect(st.actionFor(9, OpKind.addCredit), PaymentVoidAction.locked, reason: 'بلا صلاحيّة الرصيد');
      expect(st.actionFor(6, OpKind.addCredit), PaymentVoidAction.none, reason: 'قيدٌ قائم وبلا صلاحيّة ⇒ لا زرّ');
      expect(st.actionFor(10, null), PaymentVoidAction.none);
    });

    test('المعاينة والأسماء والوسم', () {
      final p = OpVoidPreview.fromJson({
        'op': {'id': 9, 'kind': 'add_credit', 'credit_kind': 'comp', 'amount': 5000, 'origin': {'employee_id': 3, 'username': 'h'}},
        'balance_delta': -5000,
        'effects': {'new_debts': 0, 'cash': 0, 'profit': 5000},
        'can_void': false,
        'blocked': {'code': 'NOT_YOUR_OP', 'message': 'تلغي الحركات التي سجّلتها أنت فقط'},
      })!;
      expect((p.kind, p.creditKind, p.balanceDelta, p.profitEffect, p.canVoid, p.blockedMessage),
          (OpKind.addCredit, 'comp', -5000, 5000, false, 'تلغي الحركات التي سجّلتها أنت فقط'));
      expect(opName(OpKind.addCredit, 'cash'), 'إضافة رصيد (نقداً)');
      expect(opName(OpKind.addDebt), 'إضافة دين');
      expect(opVoidLabel('add_credit'), 'إلغاء إضافة رصيد');
      expect(PaymentVoidsApi.cleanNote('إلغاء إضافة دين 1 د.ع — حركة #5 [ov:5]'), 'إلغاء إضافة دين 1 د.ع — حركة #5');
      expect(voidedByManager({'op_void': true, 'voided_by_employee_id': null}), isTrue);
      expect(voidedByManager({'op_void': true, 'voided_by_employee_id': 4}), isFalse);
    });

    test('محرّر الموظّفين: الصلاحيّتان بقوائم الشركات الثلاث وتلميحهما', () {
      for (final k in [ElEmployeePerms.voidAddDebtKey, ElEmployeePerms.voidAddCreditKey]) {
        expect(ElEmployeePerms.hints[k], isNotNull, reason: k);
      }
    });
  });

  group('سجل حركات المشترك', () {
    tearDown(visualTearDown);

    Future<_OvServer> open(WidgetTester t, {void Function(_OvServer)? prep}) async {
      final server = _OvServer(await visualSetUp(s1bSasOwner));
      prep?.call(server);
      ApiClient.dio.httpClientAdapter = server;
      await pumpVisual(t, phone,
          home: (_) => Builder(
              builder: (c) => Scaffold(
                  body: Center(child: TextButton(onPressed: () => showMovementsSheet(c, _sub), child: const Text('افتح'))))));
      await settle(t, seconds: 1);
      await t.tap(find.text('افتح'));
      await settle(t, seconds: 2);
      return server;
    }

    testWidgets('الزرّ على الإضافتين وحدهما وسطر الإلغاء باسمه — ثمّ إلغاء إضافة الدين بالمعاينة والطلب بما رآه', (t) async {
      final server = await open(t);
      expect(server.statusCalls.single.split(',').toSet(), {'901', '902'});
      expect(_rowButtons(PaymentVoidAction.open), findsNWidgets(2));
      expect(find.text('إلغاء إضافة دين'), findsOneWidget, reason: 'السطر المقابل باسمه');
      await shoot(t, s1bSasOwner, 'op_void_movements', phone, server.inner as VisualServer);

      await t.tap(_rowButtons(PaymentVoidAction.open).first);
      await settle(t, seconds: 1);
      expect(server.previews, [901]);
      expect(find.text('عليه 45,000 د.ع'), findsOneWidget);
      expect(find.text('عليه 25,000 د.ع'), findsOneWidget);
      expect(find.text('hosny'), findsOneWidget);
      expect(find.textContaining('«الديون الجديدة» في التقرير تنقص'), findsOneWidget);
      await shoot(t, s1bSasOwner, 'op_void_sheet_debt', phone, server.inner as VisualServer);
      await t.tap(find.text('تأكيد الإلغاء'));
      await settle(t, seconds: 2);
      expect(server.posts.single.$2, {'op_id': 901, 'expect_kind': 'add_debt', 'expect_amount': 20000, 'expect_subscriber': 'ali.kareem'});
      expect(find.textContaining('رصيد المشترك الآن: عليه 25,000 د.ع'), findsOneWidget);
      expect(server.statementGets, 2, reason: 'الكشف من جديد بعد الإلغاء');
      await settle(t, seconds: 4);
    });

    testWidgets('إضافة رصيدٍ نقداً: الصندوق من حساب من استلم والتسوية المحفوظة، و«بعد» دينٌ أكبر', (t) async {
      final server = await open(t);
      await t.tap(_rowButtons(PaymentVoidAction.open).at(1));
      await settle(t, seconds: 1);
      expect(server.previews, [902]);
      expect(find.text('عليه 60,000 د.ع'), findsOneWidget);
      expect(find.textContaining('ينقص المبلغ من الصندوق'), findsOneWidget);
      expect(find.textContaining('ضمن تسوية #3'), findsOneWidget);
      await shoot(t, s1bSasOwner, 'op_void_sheet_credit', _narrow, server.inner as VisualServer);
    });

    testWidgets('موظّفٌ بصلاحيّة الدين وحدها: زرٌّ للدين وقفلٌ للرصيد · الميزة مطفأة ⇒ لا زرّ', (t) async {
      await open(t, prep: (s) => s.status = {'enabled': true, 'can_void_debt': true, 'can_void_credit': false, 'own_only': true, 'items': []});
      expect(_rowButtons(PaymentVoidAction.open), findsOneWidget);
      expect(_rowButtons(PaymentVoidAction.locked), findsOneWidget);
    });

    testWidgets('«شراء»: باسمه وزرّ «إلغاء البيع»، والزرّ يقرأ مبيعات يومه بتوقيت بغداد (22:30 UTC ⇒ اليوم التالي)', (t) async {
      final server = await open(t);
      expect(find.text('شراء'), findsOneWidget);
      final sale = find.byWidgetPredicate((w) => w is PaymentVoidRowButton && w.tipOpen == 'إلغاء البيع');
      expect(sale, findsOneWidget);
      await t.tap(sale);
      await settle(t, seconds: 2);
      expect(server.salesAsks.single, {'from': '2026-11-15', 'to': '2026-11-15'});
      expect(find.textContaining('تعذّر العثور على البيع #41'), findsOneWidget, reason: 'غير موجودٍ بيومه ⇒ رسالة لا نافذة فارغة');
      await settle(t, seconds: 4);
    });

    testWidgets('الميزة مطفأة ⇒ لا زرّ ولا قفل', (t) async {
      await open(t, prep: (s) => s.status = {'enabled': false, 'can_void_debt': false, 'can_void_credit': false, 'own_only': false, 'items': []});
      expect(find.byWidgetPredicate((w) => w is PaymentVoidRowButton && w.tipOpen == 'إلغاء الحركة'), findsNothing);
    });

    testWidgets('نتيجةٌ لم يؤكّدها الساس ⇒ الحسم «تعدّل الرصيد» من النافذة نفسها', (t) async {
      final server = await open(t, prep: (s) => s.nextRun = (409, {'success': false, 'code': 'OUTCOME_UNKNOWN', 'message': 'لم يتأكّد', 'void_id': 77}));
      await t.tap(_rowButtons(PaymentVoidAction.open).first);
      await settle(t, seconds: 1);
      await t.tap(find.text('تأكيد الإلغاء'));
      await settle(t, seconds: 2);
      expect(find.text('تعدّل الرصيد — سجّل الإلغاء'), findsOneWidget);
      await t.tap(find.text('تعدّل الرصيد — سجّل الإلغاء'));
      await settle(t, seconds: 2);
      expect(server.posts.last.$1, '/api/v2/op-voids/77/resolve');
      expect(server.posts.last.$2, {'applied': true});
      await settle(t, seconds: 4);
    });
  });
}
