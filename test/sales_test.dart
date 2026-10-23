import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/api/employees_api.dart';
import 'package:rad_mysvcs/api/merged_finance_api.dart';
import 'package:rad_mysvcs/api/reports_api.dart';
import 'package:rad_mysvcs/api/sales_api.dart';
import 'package:rad_mysvcs/api/settlements_api.dart';
import 'package:rad_mysvcs/screens/more_modules_screen.dart';
import 'package:rad_mysvcs/screens/reports/widgets/action_labels.dart';
import 'package:rad_mysvcs/screens/sales/sales_screen.dart';

import 'visual_perm/visual_perm_harness.dart';

/// قسم «المبيعات» بالتطبيق (٢٣ أكتوبر) — الخادم server/sales.js والويب pages/Sales.tsx.
///   • النموذج: الكمّيّة بثلاث خاناتٍ عشريّة (أرقام عربيّة)، الحالات، «غير مؤكَّد».
///   • البيع: نجاح · تكرار المرجع · «لم يُضَف الدين» · «غير مؤكَّد» · بلا حكمٍ ⇒ إعادةٌ بالمرجع نفسه.
///   • التقرير الماليّ: نقد المواد في الإيراد، كلفتها تُطرح من الصافي النقديّ، ربحها في صافي ما بعد الكلفة،
///     والبيع على الدين لا يُعدّ «إضافة دين» يدويّة. بلا مبيعات ⇒ الأرقام كما كانت حرفيّاً.
///   • التسوية: سطر «بيع مواد» وحدّا المبيعات يُعادان مع التسوية.
///   • موظّف ايرث لنك: العرض والبيع والموادّ في «موظّف عام»، والإلغاء فرادى.
class _SalesServer implements HttpClientAdapter {
  _SalesServer(this.inner);
  final HttpClientAdapter inner;

  bool enabled = true;
  final posts = <(String, Map<String, dynamic>)>[];

  /// إلغاءٌ على الدين «غير مؤكَّد» آخر القائمة (حسمه بمسار resolve-void).
  bool voidUnknown = false;

  static Map<String, dynamic> voidUnknownSale() => {
        ...sale(8, 'debt', 'void_unknown', username: 'zaid@sn', total: 35000, cost: 27500),
        'void_mode': 'cash', 'void_debt': 15000, 'void_refund': 20000, 'void_balance_before': -15000,
        'void_started_at': '2026-10-23T04:00:00Z',
      };

  /// ردّ البيع القادم: (status, body) — null ⇒ نجاحٌ نقديّ.
  (int, Object)? nextSale;

  static final items = [
    {
      'id': 1, 'name': 'راوتر TP-Link C6', 'code': 'C6', 'unit': 'piece', 'unit_label': 'قطعة',
      'sale_price': 45000, 'cost_avg': 32000, 'qty': 7, 'stock_value': 224000, 'margin': 13000, 'active': true,
    },
    {
      'id': 2, 'name': 'كيبل Cat6', 'code': null, 'unit': 'meter', 'unit_label': 'متر',
      'sale_price': 500, 'cost_avg': 250, 'qty': 305.5, 'stock_value': 76375, 'margin': 250, 'active': true,
    },
    {
      'id': 3, 'name': 'ONU هواوي', 'code': null, 'unit': 'piece', 'unit_label': 'قطعة',
      'sale_price': 35000, 'cost_avg': 27500, 'qty': 0, 'stock_value': 0, 'margin': 7500, 'active': true,
    },
  ];

  static Map<String, dynamic> sale(int id, String payment, String status,
          {String? username, String? name, int total = 55000, int cost = 37000, String at = '2026-10-23T04:05:00Z'}) =>
      {
        'id': id, 'payment': payment, 'status': status, 'total': total, 'cost': cost, 'profit': total - cost,
        'customer': {
          'kind': username == null ? 'walkin' : 'subscriber',
          'idx': username == null ? null : '4411',
          'username': username,
          'name': name,
          'phone': null,
        },
        'note': null, 'by': null, 'employee_id': null, 'created_at': at, 'voided_at': null,
        'void_reason': status == 'void' ? 'أرجع الزبون المادّة' : null,
        'lines': [
          {'item_id': 1, 'name': 'راوتر TP-Link C6', 'unit': 'piece', 'qty': 1, 'unit_price': 45000, 'unit_cost': 32000,
            'total': 45000, 'cost': 32000, 'profit': 13000},
        ],
      };

  static ResponseBody _json(int status, Object body) => ResponseBody.fromString(jsonEncode(body), status, headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      });

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    final get = o.method.toUpperCase() == 'GET';
    if (o.path == '/api/v2/sales/probe') {
      return _json(200, {'success': true, 'enabled': enabled, 'can': {'view': true, 'sell': true, 'items': true, 'void': true}});
    }
    if (o.path == '/api/v2/sales/items' && get) {
      return _json(200, {
        'success': true, 'enabled': enabled, 'data': items,
        'totals': {'count': 3, 'stock_value': 300375, 'out_of_stock': 1},
      });
    }
    if (o.path == '/api/v2/sales' && get) {
      return _json(200, {
        'success': true, 'enabled': enabled,
        'data': [
          sale(12, 'cash', 'done', name: 'أبو حسين'),
          sale(11, 'debt', 'done', username: 'ali.k@sn', name: 'علي كريم', total: 35000, cost: 27500),
          sale(10, 'debt', 'unknown', username: 'huda@sn', total: 45000, cost: 32000),
          sale(9, 'cash', 'void', total: 25000, cost: 18000),
          if (voidUnknown) voidUnknownSale(),
        ],
        'totals': {'count': 2, 'revenue': 90000, 'cost': 64500, 'profit': 25500, 'cash': 55000, 'debt': 35000},
        'unresolved': 1,
      });
    }
    if (o.path == '/api/v2/sales/11/void-preview' && get) {
      // بيع الدين #11 (35,000): رصيده الآن −15,000 ⇒ سدّد منه 20,000.
      return _json(200, {
        'success': true,
        'data': {'payment': 'debt', 'total': 35000, 'balance': -15000, 'paid': 20000, 'needs_choice': true,
          'after_credit': 20000, 'after_cash': 0},
      });
    }
    if (o.path.startsWith('/api/v2/sales') && !get) {
      final body = Map<String, dynamic>.from((o.data as Map?) ?? const {});
      posts.add((o.path, body));
      if (o.path == '/api/v2/sales') {
        final r = nextSale;
        nextSale = null;
        if (r != null) return _json(r.$1, r.$2);
        return _json(200, {'success': true, 'data': sale(13, 'cash', 'done')});
      }
      return _json(200, {'success': true, 'data': sale(9, 'cash', 'void')});
    }
    return inner.fetch(o, requestStream, cancelFuture);
  }

  @override
  void close({bool force = false}) => inner.close(force: force);
}

void main() {
  setUpAll(visualSetUpAll);

  group('النموذج', () {
    test('الكمّيّة: كسورٌ بثلاث خانات، أرقامٌ عربيّة، والصفر والسالب مرفوضان إلّا للجرد', () {
      expect(parseSaleQty('2'), 2);
      expect(parseSaleQty('2.5'), 2.5);
      expect(parseSaleQty('٢٫٥'), 2.5);
      expect(parseSaleQty('1,000'), 1000);
      expect(parseSaleQty('0'), isNull);
      expect(parseSaleQty('1.2345'), isNull);
      expect(parseSaleQty('-3'), isNull);
      expect(parseSaleQty('-3', signed: true), -3);
      expect(saleQtyText(305.5, 'meter'), '305.5 متر');
      expect(saleQtyText(7, 'piece'), '7 قطعة');
    });

    test('البيع: الحالات و«غير مؤكَّد» (المجهول، أو «جارٍ» أقدم من دقيقتين) والإلغاء للمكتمل نقداً أو على الدين', () {
      final cash = Sale.fromJson(_SalesServer.sale(1, 'cash', 'done'))!;
      expect(cash.voidable, isTrue);
      expect(cash.resolvable(), isFalse);
      final debt = Sale.fromJson(_SalesServer.sale(2, 'debt', 'done', username: 'u1'))!;
      expect(debt.voidable, isTrue, reason: 'الدين يُلغى بمساره (معاينة الدين ثمّ الاختيار)');
      expect(debt.customerLabel, 'u1');
      expect(Sale.fromJson(_SalesServer.sale(3, 'debt', 'unknown', username: 'u1'))!.resolvable(), isTrue);
      final pending = Sale.fromJson(_SalesServer.sale(4, 'debt', 'pending', username: 'u1', at: '2026-10-23T04:00:00Z'))!;
      expect(pending.resolvable(DateTime.utc(2026, 10, 23, 4, 1)), isFalse, reason: 'جارٍ — لا يُحسم قبل دقيقتين');
      expect(pending.resolvable(DateTime.utc(2026, 10, 23, 4, 3)), isTrue);
      expect(Sale.fromJson(_SalesServer.sale(5, 'cash', 'done'))!.customerLabel, 'زبون');
      expect(Sale.fromJson(const {'payment': 'cash'}), isNull, reason: 'بلا معرّف');
    });

    test('إلغاء البيع على الدين: الحقول، و«غير مؤكَّد» (void_unknown أو voiding أقدم من دقيقتين) بمسار الإلغاء', () {
      final u = Sale.fromJson(_SalesServer.voidUnknownSale())!;
      expect((u.voidMode, u.voidDebt, u.voidRefund, u.voidBalanceBefore), ('cash', 15000, 20000, -15000));
      expect((u.resolvesVoid, u.resolvable(), u.voidable), (true, true, false));
      final voiding = Sale.fromJson({..._SalesServer.voidUnknownSale(), 'status': 'voiding'})!;
      expect(voiding.resolvable(DateTime.utc(2026, 10, 23, 4, 1)), isFalse, reason: 'يُلغى الآن — لا يُحسم قبل دقيقتين');
      expect(voiding.resolvable(DateTime.utc(2026, 10, 23, 4, 3)), isTrue);
      expect(voiding.resolvesVoid, isTrue);
      final done = Sale.fromJson(_SalesServer.sale(2, 'debt', 'done', username: 'u1'))!;
      expect((done.voidMode, done.voidDebt, done.resolvesVoid), (null, null, false));
      final pv = VoidPreview.fromJson(const {'payment': 'debt', 'total': 35000, 'balance': -15000, 'paid': 20000, 'needs_choice': true, 'after_credit': 20000, 'after_cash': 0});
      expect((pv.paid, pv.needsChoice, pv.afterCredit, pv.afterCash, pv.balance), (20000, true, 20000, 0, -15000));
    });

    test('probe: المقيَّد بمديرٍ فرعيّ يُعلَّم، والقدرات تُقرأ', () {
      final p = SalesProbe.fromJson(const {'enabled': true, 'reason': 'scoped', 'can': {'view': true, 'sell': false}});
      expect(p.enabled, isTrue);
      expect(p.scoped, isTrue);
      expect((p.canView, p.canSell, p.canItems), (true, false, false));
      expect(SalesProbe.off.enabled, isFalse);
    });

    test('تسميات سجلّ الحركات', () {
      expect(arabicActionLabel('SALE'), 'بيع مواد');
      expect(arabicActionLabel('SALE_VOID'), 'إلغاء بيع');
      expect(arabicActionLabel('BALANCE_ADD', 'إلغاء بيع #5 — إنقاص دين 35000 د.ع للمشترك u1'), 'إنقاص دين (إلغاء بيع)');
      expect(arabicActionLabel('BALANCE_ADD', 'إضافة دين 35000 د.ع للمشترك u1 - بيع #5: راوتر ×1'), 'إضافة دين');
    });
  });

  group('التقرير الماليّ', () {
    const base = FinanceKPIs(
      activateCashSum: 450000,
      debtPaySum: 120000,
      balanceAddSum: 35000 + 20000,
      activateNonCashSum: 105000,
      expensesSum: 60000,
    );

    test('بلا مبيعات: الأرقام كما كانت حرفيّاً', () {
      final k = FinanceKPIs.fromJson(const {
        'activate_cash_sum': 450000, 'debt_pay_sum': 120000, 'balance_add_sum': 55000, 'activate_non_cash_sum': 105000,
        'expenses_sum': 60000,
      });
      expect(k.hasGoods, isFalse);
      expect(k.totalCashRevenue, 570000);
      expect(k.manualDebtAddSum, 55000);
      expect(k.netCash, 570000 - 60000 - 55000);
    });

    test('بالمبيعات (النقديّ): نقد المواد داخل، كلفتها تُطرح، والبيع على الدين ليس «إضافة دين» يدويّة', () {
      final k = FinanceKPIs.fromJson(const {
        'activate_cash_sum': 450000, 'debt_pay_sum': 120000, 'balance_add_sum': 55000, 'activate_non_cash_sum': 105000,
        'expenses_sum': 60000,
        'sales_count': 2, 'sales_revenue_sum': 90000, 'sales_cost_sum': 64500, 'sales_profit_sum': 25500,
        'sales_debt_sum': 35000, 'sales_cash_sum': 55000, 'sales_cash_count': 1,
      });
      expect(k.hasGoods, isTrue);
      expect(k.totalCashRevenue, 570000 + 55000);
      expect(k.manualDebtAddSum, 20000, reason: '55,000 − 35,000 (ثمن مادّة على الدين)');
      expect(k.netCash, 625000 - 60000 - 20000 - 64500);
    });

    test('دين المبيعات الموسوم (balance_add_sales_sum): البيع وإلغاؤه يخرجان من «اليدويّة» بكلّ فترة', () {
      // فترة البيع (أُلغي لاحقاً): البيع خرج من المكتملة (sales_debt_sum 0) وسطر دينه باقٍ موسوماً ⇒ لا «يدويّ».
      var k = FinanceKPIs.fromJson(const {'balance_add_sum': 55000, 'balance_add_sales_sum': 35000, 'sales_debt_sum': 0});
      expect(k.manualDebtAddSum, 20000);
      // فترة الإلغاء: إنقاصه −35,000 موسوماً ويدويٌّ 20,000 ⇒ اليدويّ 20,000 لا صفر.
      k = FinanceKPIs.fromJson(const {'balance_add_sum': -15000, 'balance_add_sales_sum': -35000});
      expect(k.manualDebtAddSum, 20000);
      // إرجاع جزءٍ نقداً بالفترة نفسها: البيع 35,000 وإنقاصه 15,000 ⇒ الموسوم 20,000 والدين الجديد كلّه منه.
      k = FinanceKPIs.fromJson(const {'balance_add_sum': 20000, 'balance_add_sales_sum': 20000, 'sales_debt_sum': 0});
      expect(k.manualDebtAddSum, 0);
      // خادمٌ أقدم بلا الحقل ⇒ sales_debt_sum كما كان.
      k = FinanceKPIs.fromJson(const {'balance_add_sum': 55000, 'sales_debt_sum': 35000});
      expect((k.balanceAddSalesSum, k.manualDebtAddSum), (null, 20000));
      // «كل الشركات»: شركةٌ بلا الحقل تُحسب بدين مبيعاتها المكتملة.
      final s = MergedFinanceApi.sumKpis(const [
        FinanceKPIs(balanceAddSum: 55000, balanceAddSalesSum: 35000),
        FinanceKPIs(balanceAddSum: 10000, goodsDebtSum: 4000),
      ]);
      expect((s.balanceAddSalesSum, s.manualDebtAddSum), (39000, 26000));
      expect(MergedFinanceApi.sumKpis(const [FinanceKPIs(balanceAddSum: 1000)]).balanceAddSalesSum, isNull);
      // من السطور (فلتر النوع): سطر الدين الموسوم بوصفه.
      FinanceLog l(String d, num a) => FinanceLog.fromJson({'id': 1, 'action_type': 'BALANCE_ADD', 'action_description': d, 'amount': a, 'created_at': '2026-10-23T04:00:00Z'})!;
      expect(l('إضافة دين 35000 د.ع للمشترك u1 - بيع #5: راوتر ×1', 35000).isSaleDebtLine, isTrue);
      expect(l('إلغاء بيع #5 — إنقاص دين 35000 د.ع للمشترك u1', -35000).isSaleDebtLine, isTrue);
      expect(l('إضافة دين 2000 د.ع للمشترك u1', 2000).isSaleDebtLine, isFalse);
    });

    test('بعد كلفة الباقات: + ربح المواد', () {
      final k = FinanceKPIs(
        activateCashSum: base.activateCashSum,
        activateNonCashSum: base.activateNonCashSum,
        expensesSum: base.expensesSum,
        packageCost: const PackageCostKpis(sum: 300000, rows: 10, knownRows: 10, estimatedRows: 0, hasEstimates: false),
        goodsProfitSum: 25500,
        goodsCount: 2,
      );
      expect(k.profitAfterCost, 450000 + 105000 - 60000 - 300000 + 25500);
    });

    test('«كل الشركات»: حقول المواد تُجمع', () {
      final s = MergedFinanceApi.sumKpis(const [
        FinanceKPIs(goodsCashSum: 10000, goodsCostSum: 6000, goodsProfitSum: 4000, goodsCount: 1),
        FinanceKPIs(goodsCashSum: 5000, goodsCostSum: 3000, goodsProfitSum: 2000, goodsCount: 2, goodsDebtSum: 9000),
      ]);
      expect((s.goodsCashSum, s.goodsCostSum, s.goodsProfitSum, s.goodsCount, s.goodsDebtSum), (15000, 9000, 6000, 3, 9000));
    });
  });

  group('التسوية', () {
    test('حدّا المبيعات يُعادان كما وصلا، وخادمٌ قبلهما لا يُرسل شيئاً', () {
      final cut = SettlementCut.fromJson(const {'head_id': 1, 'activity_id': 100, 'expense_id': 10, 'sale_id': 12, 'sale_cash_id': 3})!;
      expect(cut.toJson(), {'head_id': 1, 'activity_id': 100, 'expense_id': 10, 'sale_id': 12, 'sale_cash_id': 3});
      final old = SettlementCut.fromJson(const {'head_id': 1, 'activity_id': 100, 'expense_id': 10})!;
      expect(old.toJson(), {'head_id': 1, 'activity_id': 100, 'expense_id': 10});
    });

    test('الصندوق: «بيع مواد» داخلٌ في عدد الحركات ولكلّ منفّذ', () {
      final cur = CurrentAccount.fromJson(const {
        'started': true,
        'totals': {
          'cash_activations': {'sum': 450000, 'count': 12},
          'debt_payments': {'sum': 120000, 'count': 4},
          'sales_cash': {'sum': 30000, 'count': 2},
          'expenses': {'sum': 60000, 'count': 3},
          'cash_in': 600000,
          'expected_amount': 540000,
        },
        'collectors': [
          {
            'employee_id': null,
            'cash_activations': {'sum': 0, 'count': 0},
            'debt_payments': {'sum': 0, 'count': 0},
            'sales_cash': {'sum': 30000, 'count': 2},
            'expenses': {'sum': 0, 'count': 0},
            'net_amount': 30000,
          },
        ],
      })!;
      expect(cur.salesCash.sum, 30000);
      expect(cur.moveCount, 12 + 4 + 3 + 2);
      expect(cur.collectors.single.inCount, 2);
    });
  });

  group('موظّف ايرث لنك', () {
    test('العرض والبيع والموادّ في «موظّف عام»، والإلغاء فرادى؛ والكاشير يبيع ولا يدير الموادّ', () {
      for (final k in ['sales.view', 'sales.sell', 'sales.items', 'sales.void']) {
        expect(ElEmployeePerms.keys, contains(k));
      }
      final general = ElEmployeePerms.presets.firstWhere((p) => p.id == 'general');
      expect(general.keys, containsAll(['sales.view', 'sales.sell', 'sales.items']));
      expect(general.keys, isNot(contains('sales.void')));
      final collect = ElEmployeePerms.presets.firstWhere((p) => p.id == 'collect');
      expect(collect.keys, containsAll(['sales.view', 'sales.sell']));
      expect(collect.keys, isNot(contains('sales.items')));
    });

    test('كتالوجٌ لا يعرض مفاتيح المبيعات (لم تُفتح للكلّ) لا يجعل «موظّف عام» القديم «مخصّصاً»', () {
      final catalog = ElEmployeePerms.keys.where((k) => !k.startsWith('sales.')).toList();
      final perms = {
        for (final k in ElEmployeePerms.presets.firstWhere((p) => p.id == 'general').keys)
          if (!k.startsWith('sales.')) k: true,
      };
      expect(ElEmployeePerms.matching(perms, catalogKeys: catalog)?.id, 'general');
    });
  });

  group('الـAPI', () {
    tearDown(visualTearDown);

    testWidgets('البيع: نجاح · تكرار · «لم يُضَف الدين» · «غير مؤكَّد» · بلا حكمٍ ⇒ إعادةٌ بالمرجع نفسه', (t) async {
      final server = _SalesServer(await visualSetUp(s1bSasOwner));
      ApiClient.dio.httpClientAdapter = server;
      final lines = [const SaleLineInput(itemId: 1, qty: 1, unitPrice: 45000)];
      Future<SaleResult> sell(String payment) async => (await t.runAsync(() => SalesApi.sell(
            clientRef: 'ref0000001',
            payment: payment,
            lines: lines,
            customer: const {'kind': 'walkin'},
          )))!;

      var r = await sell('cash');
      expect((r.ok, r.sale?.id, r.keepRef), (true, 13, false));
      expect(server.posts.last.$2['lines'], [
        {'item_id': 1, 'qty': 1, 'unit_price': 45000},
      ]);

      server.nextSale = (200, {'success': true, 'duplicate': true, 'data': _SalesServer.sale(13, 'cash', 'done')});
      r = await sell('cash');
      expect((r.ok, r.duplicate), (true, true));

      server.nextSale = (409, {
        'success': false, 'code': 'DEBT_NOT_ADDED', 'message': 'لم يُضَف الدين — لم يُسجَّل البيع وأُعيدت الكمّيّة',
        'data': _SalesServer.sale(14, 'debt', 'failed', username: 'u1'),
      });
      r = await sell('debt');
      expect((r.ok, r.code, r.keepRef), (false, 'DEBT_NOT_ADDED', false));
      expect(r.sale?.status, 'failed');

      server.nextSale = (409, {'success': false, 'code': 'OUTCOME_UNKNOWN', 'message': 'تعذّر التأكّد', 'data': _SalesServer.sale(15, 'debt', 'unknown', username: 'u1')});
      r = await sell('debt');
      expect((r.code, r.keepRef), ('OUTCOME_UNKNOWN', false), reason: 'محفوظٌ «غير مؤكَّد» — يُحسم من القائمة');

      server.nextSale = (409, {'success': false, 'code': 'IN_PROGRESS', 'message': 'البيع نفسه جارٍ الآن'});
      r = await sell('cash');
      expect(r.keepRef, isTrue, reason: 'المرجع نفسه — لا بيعٌ ثانٍ');

      server.nextSale = (502, '<html>Bad gateway</html>');
      r = await sell('cash');
      expect((r.ok, r.ambiguous, r.keepRef), (false, true, true), reason: 'صفحة الوسيط ليست حكماً من خادمنا');
    });
  });

  group('الشاشة', () {
    tearDown(() async {
      SalesState.reset();
      await visualTearDown();
    });

    testWidgets('المبيعات: المجاميع، «لم يُحسم»، الإلغاء للنقديّ و«احسم» للمجهول؛ والموادّ بالمخزون', (t) async {
      final server = _SalesServer(await visualSetUp(s1bSasOwner));
      ApiClient.dio.httpClientAdapter = server;
      await pumpVisual(t, phoneTall, home: (_) => const SalesScreen());
      await settle(t, seconds: 2);
      expect(t.takeException(), isNull);
      expect(find.text('90,000 د.ع'), findsWidgets);
      expect(find.textContaining('لم تُحسم'), findsOneWidget);
      expect(find.text('غير مؤكَّد'), findsOneWidget);
      expect(find.text('احسم'), findsOneWidget);
      expect(find.text('إلغاء'), findsNWidgets(2), reason: 'المكتمل نقداً وعلى الدين');
      expect(find.text('مُلغى'), findsOneWidget);

      await t.tap(find.text('الموادّ والمخزون'));
      await settle(t, seconds: 1);
      expect(find.textContaining('305.5 متر'), findsOneWidget);
      expect(find.textContaining('0 قطعة'), findsOneWidget);
      expect(find.text('300,375 د.ع'), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('إلغاء بيعٍ على الدين: معاينة الدين ثمّ «تُرجَع نقداً» يُرسل refund وexpected_paid', (t) async {
      final server = _SalesServer(await visualSetUp(s1bSasOwner));
      ApiClient.dio.httpClientAdapter = server;
      await pumpVisual(t, phoneTall, home: (_) => const SalesScreen());
      await settle(t, seconds: 2);
      // الثاني = بيع الدين #11 (الترتيب: #12 نقديّ ثمّ #11 دين).
      await t.ensureVisible(find.text('إلغاء').at(1));
      await t.tap(find.text('إلغاء').at(1));
      await settle(t, seconds: 2);
      expect(find.textContaining('سدّد المشترك 20,000 د.ع'), findsOneWidget);
      expect(find.text('تبقى رصيداً له للاشتراك الجاي'), findsOneWidget);
      expect(find.text('دين 15,000 د.ع'), findsOneWidget);
      await t.tap(find.textContaining('تُرجَع له'));
      await settle(t);
      await t.enterText(find.byType(TextField).last, 'أرجع المادّة');
      await settle(t);
      await t.tap(find.text('إلغاء البيع وإرجاع 20,000 د.ع نقداً'));
      await settle(t, seconds: 2);
      final post = server.posts.lastWhere((p) => p.$1 == '/api/v2/sales/11/void');
      expect(post.$2, {'reason': 'أرجع المادّة', 'refund': 'cash', 'expected_paid': 20000});
      await settle(t, seconds: 4); // إشعار النجاح (٣ث)
      expect(t.takeException(), isNull);
    });

    testWidgets('إلغاءٌ «غير مؤكَّد»: «احسم» يفتح حسم الإلغاء ويُرسل لـresolve-void', (t) async {
      final server = _SalesServer(await visualSetUp(s1bSasOwner))..voidUnknown = true;
      ApiClient.dio.httpClientAdapter = server;
      await pumpVisual(t, phoneTall, home: (_) => const SalesScreen());
      await settle(t, seconds: 2);
      expect(find.text('إلغاءٌ غير مؤكَّد'), findsOneWidget);
      await t.ensureVisible(find.text('احسم').last);
      await t.tap(find.text('احسم').last);
      await settle(t, seconds: 1);
      expect(find.text('حسم إلغاء البيع #8'), findsOneWidget);
      expect(find.textContaining('صار رصيده صفر'), findsOneWidget);
      expect(find.textContaining('إرجاع 20,000 د.ع نقداً'), findsOneWidget);
      await t.tap(find.text('نُقص الدين'));
      await settle(t);
      await t.tap(find.text('تأكيد: نُقص'));
      await settle(t, seconds: 1);
      final post = server.posts.lastWhere((p) => p.$1 == '/api/v2/sales/8/resolve-void');
      expect(post.$2, {'applied': true});
      await settle(t, seconds: 4); // إشعار النجاح (٣ث)
      expect(t.takeException(), isNull);
    });

    testWidgets('مطفأةٌ للحساب وبلا بيانات ⇒ «غير مفعّلة»', (t) async {
      final server = _SalesServer(await visualSetUp(s1bSasOwner))..enabled = false;
      ApiClient.dio.httpClientAdapter = _EmptyOff(server);
      await pumpVisual(t, phone, home: (_) => const SalesScreen());
      await settle(t, seconds: 2);
      expect(find.textContaining('غير مفعّلة'), findsOneWidget);
      expect(find.byType(FloatingActionButton), findsNothing);
    });

    testWidgets('«قوائم أخرى»: البطاقة حين يقول الخادم «مفعّلة» وحده', (t) async {
      final server = _SalesServer(await visualSetUp(s1bSasOwner));
      ApiClient.dio.httpClientAdapter = server;
      SalesState.debugSet(const SalesProbe(enabled: true));
      await pumpVisual(t, phoneTall, home: (_) => const MoreModulesScreen());
      await settle(t, seconds: 1);
      expect(find.text('المبيعات', skipOffstage: false), findsOneWidget);
      SalesState.debugSet(SalesProbe.off);
      await settle(t, seconds: 1);
      expect(find.text('المبيعات', skipOffstage: false), findsNothing);
      expect(t.takeException(), isNull);
    });
  });
}

/// القائمتان فارغتان والمفتاح مطفأ — حسابٌ لم تُفتح له الميزة قطّ.
class _EmptyOff implements HttpClientAdapter {
  _EmptyOff(this.inner);
  final HttpClientAdapter inner;

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    ResponseBody j(Object body) => ResponseBody.fromString(jsonEncode(body), 200, headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        });
    if (o.path == '/api/v2/sales/items') {
      return j({'success': true, 'enabled': false, 'data': const [], 'totals': {'count': 0, 'stock_value': 0, 'out_of_stock': 0}});
    }
    if (o.path == '/api/v2/sales') {
      return j({'success': true, 'enabled': false, 'data': const [], 'totals': const {}, 'unresolved': 0});
    }
    return inner.fetch(o, requestStream, cancelFuture);
  }

  @override
  void close({bool force = false}) => inner.close(force: force);
}
