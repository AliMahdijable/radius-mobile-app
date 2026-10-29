import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/api/employees_api.dart';
import 'package:rad_mysvcs/api/merged_finance_api.dart';
import 'package:rad_mysvcs/api/reports_api.dart';
import 'package:rad_mysvcs/api/sales_api.dart';
import 'package:rad_mysvcs/api/settlements_api.dart';
import 'package:rad_mysvcs/core/widgets/design_sheet.dart';
import 'package:rad_mysvcs/screens/more_modules_screen.dart';
import 'package:rad_mysvcs/screens/reports/widgets/action_labels.dart';
import 'package:rad_mysvcs/screens/sales/sales_screen.dart';
import 'package:rad_mysvcs/screens/settlements/settle_widgets.dart';
import 'package:rad_mysvcs/services/receipt_pdf.dart';
import 'package:rad_mysvcs/services/sale_print.dart';
import 'package:rad_mysvcs/services/subscriber_events.dart';
import 'package:pdf/pdf.dart';

import 'visual_perm/visual_perm_harness.dart';

/// قسم «المبيعات» بالتطبيق (٢٣ أكتوبر) — الخادم server/sales.js والويب pages/Sales.tsx.
///   • النموذج: الكمّيّة بثلاث خاناتٍ عشريّة (أرقام عربيّة)، الحالات، «غير مؤكَّد».
///   • البيع: نجاح · تكرار المرجع · «لم يُضَف الدين» · «غير مؤكَّد» · بلا حكمٍ ⇒ إعادةٌ بالمرجع نفسه.
///   • التقرير الماليّ: نقد المواد في الإيراد، كلفتها تُطرح من الصافي النقديّ، ربحها في صافي ما بعد الكلفة،
///     والبيع على الدين لا يُعدّ «إضافة دين» يدويّة. بلا مبيعات ⇒ الأرقام كما كانت حرفيّاً.
///   • التسوية: سطر «بيع مواد» وحدّا المبيعات يُعادان مع التسوية.
///   • موظّف ايرث لنك: العرض والبيع والموادّ في «موظّف عام»، والإلغاء فرادى.
///   • التالف والعطلان: خانة العطلان بقيمتها وحسمها (تصلّحت/ما تتصلّح/رجّعتها للمورّد)، والخسارة تُطرح من
///     الصافيين، وما رجّعه المورّد للصندوق «استرجاع من المورّد»، وإلغاء أيّ حركةٍ يدويّة.
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
      'qty_defective': 1, 'defective_value': 25000,
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

  /// طلبات «حالة التسديد» — المعرّفات المرسلة في كلٍّ منها.
  final debtStatusIds = <List<int>>[];

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    final get = o.method.toUpperCase() == 'GET';
    if (o.path == '/api/v2/sales/probe') {
      return _json(200, {'success': true, 'enabled': enabled, 'can': {'view': true, 'sell': true, 'items': true, 'void': true}});
    }
    if (o.path == '/api/v2/sales/items' && get) {
      return _json(200, {
        'success': true, 'enabled': enabled, 'data': items,
        'totals': {'count': 3, 'stock_value': 300375, 'out_of_stock': 1, 'defective_items': 1, 'defective_value': 25000},
      });
    }
    if (o.path == '/api/v2/sales/debt-status' && !get) {
      final body = o.data is Map ? Map<String, dynamic>.from(o.data as Map) : <String, dynamic>{};
      debtStatusIds.add(List<int>.from(body['ids'] as List? ?? const []));
      return _json(200, {
        'success': true,
        'data': [
          {'id': 11, 'state': 'partial', 'paid': 20000, 'unpaid': 15000, 'balance': -15000},
          {'id': 999, 'state': 'bogus'},
        ],
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
    if (o.path == '/api/v2/sales/items/1/moves' && get) {
      // آخر حركةٍ شراءٌ من الصندوق (يُلغى) ثمّ بيع ثمّ شراءٌ مُلغى.
      return _json(200, {
        'success': true,
        'data': [
          {'id': 40, 'kind': 'purchase', 'qty': 10, 'unit_cost': 27000, 'qty_before': 1, 'qty_after': 11, 'cost_avg_after': 26818.18,
            'sale_id': null, 'note': 'دفعة المورّد', 'by': null, 'employee_id': null, 'at': '2026-10-23T09:10:00Z',
            'paid_from': 'box', 'ref_move_id': null, 'voided': false, 'voidable': true},
          {'id': 39, 'kind': 'sale', 'qty': -3, 'unit_cost': 25000, 'qty_before': 4, 'qty_after': 1, 'cost_avg_after': 25000,
            'sale_id': 17, 'note': null, 'by': null, 'employee_id': null, 'at': '2026-10-23T08:40:00Z',
            'paid_from': null, 'ref_move_id': null, 'voided': false, 'voidable': false},
          {'id': 37, 'kind': 'purchase', 'qty': 5, 'unit_cost': 99000, 'qty_before': 4, 'qty_after': 9, 'cost_avg_after': 66111.11,
            'sale_id': null, 'note': null, 'by': null, 'employee_id': null, 'at': '2026-10-23T08:19:00Z',
            'paid_from': 'box', 'ref_move_id': null, 'voided': true, 'voidable': false},
        ],
      });
    }
    if (o.path == '/api/v2/sales/items/2/moves' && get) {
      // آخر حركةٍ إرجاعٌ للمورّد (رجّع 15,000 للصندوق، الخسارة 5,000) — تُلغى؛ قبلها عطلانٌ على المخزون.
      return _json(200, {
        'success': true,
        'data': [
          {'id': 50, 'kind': 'supplier_return', 'qty': -2, 'unit_cost': 10000, 'qty_before': 305.5, 'qty_after': 305.5,
            'cost_avg_after': 250, 'sale_id': null, 'note': 'المورّد', 'by': null, 'employee_id': null, 'at': '2026-10-23T10:20:00Z',
            'paid_from': 'box', 'ref_move_id': null, 'voided': false, 'voidable': true,
            'defective_after': 0, 'loss': 5000, 'refund': 15000},
          {'id': 49, 'kind': 'defect', 'qty': -2, 'unit_cost': 250, 'qty_before': 307.5, 'qty_after': 305.5,
            'cost_avg_after': 250, 'sale_id': null, 'note': 'مقطوع', 'by': null, 'employee_id': null, 'at': '2026-10-23T10:00:00Z',
            'paid_from': null, 'ref_move_id': null, 'voided': false, 'voidable': false, 'defective_after': 2},
        ],
      });
    }
    if (o.path == '/api/v2/sales/items/2/moves/50/void' && !get) {
      posts.add((o.path, Map<String, dynamic>.from((o.data as Map?) ?? const {})));
      return _json(200, {'success': true, 'data': items[1], 'refund': 0, 'box_delta': -15000, 'kind': 'supplier_return', 'paid_from': 'box'});
    }
    if (o.path.endsWith('/stock') && !get) {
      final body = Map<String, dynamic>.from((o.data as Map?) ?? const {});
      posts.add((o.path, body));
      final loss = switch (body['kind']) { 'damage' => 32000, 'supplier_return' => 10000, _ => null };
      return _json(200, {'success': true, 'data': items[0], if (loss != null) 'loss': loss});
    }
    if (o.path == '/api/v2/sales/items/1/moves/40/void' && !get) {
      posts.add((o.path, Map<String, dynamic>.from((o.data as Map?) ?? const {})));
      return _json(200, {'success': true, 'data': items[0], 'refund': 270000, 'paid_from': 'box'});
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

    test('شراء المخزون: مصدر الثمن والإلغاء بالحركة، و«شراء مواد» بالتسوية (المجموع والمحصِّل والعدد)', () {
      final m = StockMove.fromJson(const {'id': 40, 'kind': 'purchase', 'qty': 10, 'unit_cost': 27000, 'qty_after': 11,
        'paid_from': 'box', 'voided': false, 'voidable': true})!;
      expect((m.paidFrom, m.voided, m.voidable, m.refMoveId), ('box', false, true, null));
      final v = StockMove.fromJson(const {'id': 41, 'kind': 'purchase_void', 'qty': -10, 'qty_after': 1, 'ref_move_id': 40})!;
      expect((v.kind, v.refMoveId, v.voidable), ('purchase_void', 40, false));
      final cur = CurrentAccount.fromJson(const {
        'started': true,
        'totals': {
          'cash_activations': {'sum': 0, 'count': 0},
          'debt_payments': {'sum': 0, 'count': 0},
          'sales_cash': {'sum': 35000, 'count': 1},
          'expenses': {'sum': 0, 'count': 0},
          'goods_purchases': {'sum': 154000, 'count': 2},
          'cash_in': 35000,
          'expected_amount': -119000,
        },
        'collectors': [
          {'employee_id': 42, 'cash_activations': {'sum': 0, 'count': 0}, 'debt_payments': {'sum': 0, 'count': 0},
            'sales_cash': {'sum': 35000, 'count': 1}, 'expenses': {'sum': 0, 'count': 0},
            'goods_purchases': {'sum': 100000, 'count': 1}, 'net_amount': -65000},
        ],
      })!;
      expect((cur.goodsPurchases.sum, cur.goodsPurchases.count, cur.moveCount, cur.expected), (154000, 2, 3, -119000));
      expect((cur.collectors.single.goodsPurchases.sum, cur.collectors.single.outCount), (100000, 1));
      final old = SettlementRecord.fromJson(const {'id': 1, 'kind': 'settlement'})!;
      expect((old.goodsPurchases.sum, old.goodsPurchases.count), (0, 0), reason: 'تسويةٌ قبل القسم ⇒ صفر');
    });

    test('التالف والعطلان: خانة العطلان بقيمتها، وحركاتها بخسارتها وما رجّعه المورّد', () {
      final it = SaleItem.fromJson({..._SalesServer.items[0], 'qty_defective': 3, 'defective_value': 60000})!;
      expect((it.hasDefective, it.qtyDefective, it.defectiveValue), (true, 3, 60000));
      expect(it.defectiveValueOf(3), 60000, reason: 'كلّه ⇒ قيمته كلّها حرفاً');
      expect(it.defectiveValueOf(1), 20000);
      expect(it.defectiveValueOf(0), 0);
      expect(SaleItem.fromJson(_SalesServer.items[1])!.hasDefective, isFalse);
      final w = StockMove.fromJson(const {'id': 44, 'kind': 'defect_writeoff', 'qty': -1, 'qty_before': 8, 'qty_after': 8,
        'defective_after': 1, 'loss': 25833.33, 'voidable': true})!;
      expect((w.defectiveOnly, w.loss, w.defectiveAfter, w.voidable), (true, 25833.33, 1, true));
      final r = StockMove.fromJson(const {'id': 43, 'kind': 'repair', 'qty': 1, 'qty_before': 7, 'qty_after': 8, 'defective_after': 2})!;
      expect(r.defectiveOnly, isFalse, reason: 'التصليح يغيّر المخزون');
      final s = StockMove.fromJson(const {'id': 46, 'kind': 'supplier_return', 'qty': -1, 'qty_before': 8, 'qty_after': 8,
        'defective_after': 1, 'loss': -4000, 'refund': 40000, 'paid_from': 'box'})!;
      expect((s.refund, s.loss, s.paidFrom, s.defectiveOnly), (40000, -4000, 'box', true));
      expect(StockMove.fromJson(const {'id': 1, 'kind': 'sale', 'qty': -1, 'qty_after': 3})!.defectiveOnly, isFalse);
    });

    test('فاتورة البيع: PDF بورقَي الطباعة (حراري وA4) بتصميم الوصل، والزبون كما يُطبع، والمُلغى يُبنى أيضاً', () async {
      final sale = Sale.fromJson(_SalesServer.sale(27, 'cash', 'done', username: 'ali.k@sn', name: 'علي كريم'))!;
      for (final f in [PdfPageFormat.roll80, PdfPageFormat.a4]) {
        final bytes = await SalePrint.build(sale, f, company: 'شركة النور', fonts: false);
        expect(String.fromCharCodes(bytes.take(4)), '%PDF');
      }
      // الفاتورة وصلٌ من نوع «فاتورة بيع» برقم البيع، بالموادّ والمجموع وطريقة الدفع، بلا أرشفة.
      final d = SalePrint.doc(sale, shop: 'شركة النور', issuer: 'admin');
      expect((d.kind, d.kind.archiveOp, d.title, d.sale!.id, d.sale!.total, d.sale!.debt, d.username),
          (ReceiptKind.sale, null, 'فاتورة بيع رقم 27', 27, sale.total, false, 'ali.k@sn'));
      expect(d.sale!.lines.length, sale.lines.length);
      expect(d.issuer, 'admin', reason: 'بيع المدير: «أصدره» المدير');
      final voided = Sale.fromJson(_SalesServer.sale(9, 'cash', 'void', total: 25000, cost: 18000))!;
      expect((await SalePrint.build(voided, PdfPageFormat.roll80, fonts: false)).isNotEmpty, isTrue);
      expect(SalePrint.customerOf(sale), 'علي كريم — ali.k@sn');
      expect(SalePrint.customerOf(Sale.fromJson(_SalesServer.sale(5, 'cash', 'done'))!), 'زبون');
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
      expect(arabicActionLabel('GOODS_LOSS', 'تالف: راوتر ×1 (انكسر)'), 'خسارة مواد');
      expect(arabicActionLabel('GOODS_LOSS', 'إلغاء خسارة: راوتر ×1 (خطأ)'), 'إلغاء خسارة مواد');
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

    test('التالف والعطلان: يُطرح من الصافيين، ويُظهر المواد ولو بلا بيع، ويُجمع لـ«كل الشركات»', () {
      final k = FinanceKPIs.fromJson(const {
        'activate_cash_sum': 450000, 'activate_non_cash_sum': 105000, 'expenses_sum': 60000,
        'sales_loss_sum': 25000, 'sales_loss_count': 2,
      });
      expect((k.hasGoods, k.goodsLossSum, k.goodsLossCount), (true, 25000, 2));
      expect(k.netCash, 450000 - 60000 - 25000);
      const c = FinanceKPIs(
        activateCashSum: 450000,
        activateNonCashSum: 105000,
        expensesSum: 60000,
        packageCost: PackageCostKpis(sum: 300000, rows: 10, knownRows: 10, estimatedRows: 0, hasEstimates: false),
        goodsProfitSum: 25500,
        goodsCount: 2,
        goodsLossSum: 25000,
        goodsLossCount: 2,
      );
      expect(c.profitAfterCost, 450000 + 105000 - 60000 - 300000 + 25500 - 25000);
      // إلغاءٌ بالفترة أكبر من خسارتها ⇒ سالبٌ يُرجع للصافي.
      expect(FinanceKPIs.fromJson(const {'activate_cash_sum': 1000, 'sales_loss_sum': -500, 'sales_loss_count': 1}).netCash, 1500);
      final s = MergedFinanceApi.sumKpis(const [
        FinanceKPIs(goodsLossSum: 25000, goodsLossCount: 2),
        FinanceKPIs(goodsLossSum: -5000, goodsLossCount: 1),
      ]);
      expect((s.goodsLossSum, s.goodsLossCount, s.hasGoods), (20000, 3, true));
      expect(FinanceKPIs.fromJson(const {'activate_cash_sum': 1000}).hasGoods, isFalse, reason: 'بلا خسارة ⇒ كما كان');
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

    test('ما رجّعه المورّد للصندوق: «شراء مواد» صافيه سالب ⇒ «استرجاع من المورّد» داخل', () {
      final cur = CurrentAccount.fromJson(const {
        'started': true,
        'totals': {
          'cash_activations': {'sum': 0, 'count': 0},
          'debt_payments': {'sum': 0, 'count': 0},
          'expenses': {'sum': 0, 'count': 0},
          'goods_purchases': {'sum': -15000, 'count': 1},
          'cash_in': 0,
          'expected_amount': 15000,
        },
        'collectors': [],
      })!;
      final l = goodsBoxLine(cur.goodsPurchases);
      expect((l.label, l.value, l.out), ('settle.supplier_refund'.tr(), '+15,000', false));
      final b = goodsBoxLine(const MoneyCount(270000, 2));
      expect((b.label, b.value, b.out), ('settle.goods_purchases'.tr(), '−270,000', true));
      final mv = BoxMovement.fromJson(const {'source': 'purchase', 'id': 62, 'kind': 'supplier_refund', 'direction': 'in',
        'amount': 15000, 'created_at': '2026-10-23T10:20:00Z', 'description': 'استرجاع من المورّد: راوتر ×1'})!;
      expect((mv.kind, mv.isIn, mv.amount), ('supplier_refund', true, 15000));
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

  group('الـAPI — حالة التسديد', () {
    tearDown(visualTearDown);

    testWidgets('debtStatus: الصالح وحده، وبلا معرّفات لا طلب', (t) async {
      final server = _SalesServer(await visualSetUp(s1bSasOwner));
      ApiClient.dio.httpClientAdapter = server;
      expect((await t.runAsync(() => SalesApi.debtStatus(const [])))!.map, isEmpty);
      expect(server.debtStatusIds, isEmpty);
      final r = (await t.runAsync(() => SalesApi.debtStatus(const [11, 999])))!;
      final m = r.map;
      expect(m.keys, [11], reason: 'حالةٌ غير معروفة تُسقط');
      expect(r.partial, isFalse);
      expect((m[11]!.isPartial, m[11]!.paid, m[11]!.unpaid, m[11]!.balance), (true, 20000, 15000, -15000));
      expect(server.debtStatusIds.single, [11, 999]);
    });
  });

  group('الـAPI — المخزون', () {
    tearDown(visualTearDown);

    testWidgets('حركة المخزون: الإرجاع للمورّد يُرسل المبلغ ووجهته والخسارة تُقرأ، وإلغاء الحركة يقرأ أثر الصندوق', (t) async {
      final server = _SalesServer(await visualSetUp(s1bSasOwner));
      ApiClient.dio.httpClientAdapter = server;
      final r = (await t.runAsync(() => SalesApi.stock(1,
          kind: 'supplier_return', qty: 1, refund: 15000, refundTo: 'box', note: 'المورّد', clientRef: 'ref0000001')))!;
      expect((r.ok, r.loss), (true, 10000));
      expect(server.posts.last.$2, {
        'kind': 'supplier_return', 'qty': 1, 'refund': 15000, 'refund_to': 'box', 'note': 'المورّد', 'client_ref': 'ref0000001',
      });
      await t.runAsync(() => SalesApi.stock(1, kind: 'supplier_return', qty: 1, refund: 0, refundTo: 'box', clientRef: 'ref0000002'));
      expect(server.posts.last.$2.containsKey('refund_to'), isFalse, reason: 'بلا مبلغ لا وجهة');
      expect(server.posts.last.$2['refund'], 0);
      await t.runAsync(() => SalesApi.stock(1, kind: 'damage', qty: 1, note: 'انكسر', clientRef: 'ref0000003'));
      expect(server.posts.last.$2.containsKey('refund'), isFalse, reason: 'المبلغ للإرجاع وحده');
      final v = (await t.runAsync(() => SalesApi.voidMove(2, 50, 'خطأ')))!;
      expect((v.ok, v.boxDelta, v.refund), (true, -15000, 0));
      final p = (await t.runAsync(() => SalesApi.voidMove(1, 40, 'سعرٌ خاطئ')))!;
      expect((p.ok, p.boxDelta, p.refund), (true, 270000, 270000), reason: 'خادمٌ بلا box_delta ⇒ ثمن الشراء العائد');
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
      expect(find.byTooltip('طباعة الفاتورة'), findsNWidgets(3), reason: 'المكتملان والمُلغى — لا «غير المؤكَّد»');

      await t.tap(find.text('الموادّ والمخزون'));
      await settle(t, seconds: 1);
      expect(find.textContaining('305.5 متر'), findsOneWidget);
      // النافدة تقول «نافدة» بدل «0 قطعة» (كالويب) — مع عنوان خانة «نافدة» بالأعلى.
      expect(find.textContaining('0 قطعة'), findsNothing);
      expect(find.text('نافدة'), findsNWidgets(2));
      expect(find.text('ربح الوحدة'), findsWidgets, reason: 'خانات البيع/الكلفة/الربح بكلّ بطاقة');
      expect(find.text('300,375 د.ع'), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('إلغاء بيعٍ على الدين: معاينة الدين ثمّ «تُرجَع نقداً» يُرسل refund وexpected_paid', (t) async {
      final server = _SalesServer(await visualSetUp(s1bSasOwner));
      ApiClient.dio.httpClientAdapter = server;
      await pumpVisual(t, phoneTall, home: (_) => const SalesScreen());
      await settle(t, seconds: 2);
      final changed0 = SubscriberEvents.dataChanged.value;
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
      expect(SubscriberEvents.dataChanged.value, greaterThan(changed0),
          reason: 'دين المشترك والرئيسيّة يتحدّثان بعد العمليّة — لا القسم وحده');
      expect(t.takeException(), isNull);
    });

    testWidgets('حالة التسديد: «مسدّد جزئيّاً» وما بقي — تُسأل للمكتمل على الدين وحده', (t) async {
      final server = _SalesServer(await visualSetUp(s1bSasOwner));
      ApiClient.dio.httpClientAdapter = server;
      await pumpVisual(t, phoneTall, home: (_) => const SalesScreen());
      await settle(t, seconds: 2);
      expect(server.debtStatusIds, [
        [11]
      ], reason: 'النقديّ والمُلغى و«غير المؤكَّد» لا يُسأل عنها');
      expect(find.text('مسدّد جزئيّاً'), findsOneWidget);
      expect(find.text('سُدّد 20,000 د.ع · باقي 15,000 د.ع'), findsOneWidget);
      expect(find.text('على الدين'), findsNothing, reason: 'شارة #11 صارت «مسدّد جزئيّاً»، والمؤشّر «بيع بالدين»');
      expect(find.text('بيع بالدين'), findsOneWidget);
      // #11 وحده على الدين المكتمل وقُرئ ⇒ تحت المؤشّر ما بقي منه.
      expect(find.text('باقي على المشتركين 15,000 د.ع'), findsOneWidget);
      // تسديدٌ من صفحة المشترك (أو أيّ عمليّة عليه) والشاشة مفتوحة ⇒ الحالة تُقرأ من جديد.
      SubscriberEvents.notifyChange();
      await settle(t, seconds: 2);
      expect(server.debtStatusIds, hasLength(2));
      expect(t.takeException(), isNull);
    });

    testWidgets('«بيع مادّة» من صفحة المشترك: المشترك مختار والدفع على دينه، والبيع يُرسل به', (t) async {
      final server = _SalesServer(await visualSetUp(s1bSasOwner));
      ApiClient.dio.httpClientAdapter = server;
      await pumpVisual(t, phoneTall,
          home: (_) => Scaffold(
                body: Builder(
                  builder: (ctx) => Center(
                    child: TextButton(
                      onPressed: () => showSellToSubscriber(ctx, idx: '77', username: 'ali.k@sn', name: 'علي كريم'),
                      child: const Text('SELL'),
                    ),
                  ),
                ),
              ));
      await settle(t, seconds: 1);
      await t.tap(find.text('SELL'));
      await settle(t, seconds: 2);
      expect(find.text('sales.sell_title'.tr()), findsWidgets);
      expect(find.textContaining('ali.k@sn'), findsWidgets);
      expect(find.text('sales.debt_hint'.tr()), findsOneWidget, reason: 'الدفع على دين المشترك افتراضاً');
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

    testWidgets('شراء: «من أين دُفع ثمنها؟» إجباريّ ثمّ «من الصندوق» يُرسل paid_from=box', (t) async {
      final server = _SalesServer(await visualSetUp(s1bSasOwner));
      ApiClient.dio.httpClientAdapter = server;
      await pumpVisual(t, phoneTall, home: (_) => const SalesScreen());
      await settle(t, seconds: 2);
      await t.tap(find.text('الموادّ والمخزون'));
      await settle(t, seconds: 1);
      await t.tap(find.byTooltip('شراء / تالف / فرق عدّ').first);
      await settle(t, seconds: 1);
      expect(find.text('من أين دُفع ثمنها؟ *'), findsOneWidget);
      // حقل الكمّيّة داخل الشيت (لا حقل البحث خلفه).
      await t.enterText(find.descendant(of: find.byType(DesignSheet), matching: find.byType(TextField)).first, '10');
      await settle(t);
      final btn = find.text('إدخال للمخزون');
      await t.tap(btn);
      await settle(t);
      expect(server.posts.where((p) => p.$1.endsWith('/stock')), isEmpty, reason: 'بلا اختيار لا يُرسل');
      await t.tap(find.text('من الصندوق'));
      await settle(t);
      expect(find.textContaining('يخرج ثمنها ('), findsOneWidget);
      await t.tap(btn);
      await settle(t, seconds: 4);
      final post = server.posts.lastWhere((p) => p.$1 == '/api/v2/sales/items/1/stock');
      expect((post.$2['kind'], post.$2['qty'], post.$2['paid_from']), ('purchase', 10, 'box'));
      expect(t.takeException(), isNull);
    });

    testWidgets('حركات المادّة: شارة المصدر والمُلغى، و«إلغاء الشراء» لآخر شراء بسبب ⇒ مسار الإلغاء', (t) async {
      final server = _SalesServer(await visualSetUp(s1bSasOwner));
      ApiClient.dio.httpClientAdapter = server;
      await pumpVisual(t, phoneTall, home: (_) => const SalesScreen());
      await settle(t, seconds: 2);
      await t.tap(find.text('الموادّ والمخزون'));
      await settle(t, seconds: 1);
      await t.tap(find.byTooltip('الحركات').first);
      await settle(t, seconds: 1);
      expect(find.text('من الصندوق'), findsNWidgets(2));
      expect(find.text('مُلغى'), findsOneWidget);
      expect(find.text('إلغاء الشراء'), findsOneWidget, reason: 'آخر شراءٍ وحده');
      await t.tap(find.text('إلغاء الشراء'));
      await settle(t);
      expect(find.textContaining('ويرجع ثمنه (270,000 د.ع) لصندوق من دفعه'), findsOneWidget);
      await t.enterText(find.byType(TextField).last, 'سعرٌ خاطئ');
      await settle(t);
      await t.tap(find.text('إلغاء الشراء').last);
      await settle(t, seconds: 4);
      final post = server.posts.lastWhere((p) => p.$1 == '/api/v2/sales/items/1/moves/40/void');
      expect(post.$2, {'reason': 'سعرٌ خاطئ'});
      expect(t.takeException(), isNull);
    });

    testWidgets('تالف / عطلان: الاختيار إجباريّ، و«تالف» بسببه يُرسل kind=damage مع معاينة الخسارة', (t) async {
      final server = _SalesServer(await visualSetUp(s1bSasOwner));
      ApiClient.dio.httpClientAdapter = server;
      await pumpVisual(t, phoneTall, home: (_) => const SalesScreen());
      await settle(t, seconds: 2);
      await t.tap(find.text('الموادّ والمخزون'));
      await settle(t, seconds: 1);
      await t.tap(find.byTooltip('شراء / تالف / فرق عدّ').first);
      await settle(t, seconds: 1);
      await t.tap(find.text('تالف / عطلان'));
      await settle(t);
      expect(find.text('شنو صار بيها؟ *'), findsOneWidget);
      final fields = find.descendant(of: find.byType(DesignSheet), matching: find.byType(TextField));
      await t.enterText(fields.at(0), '1');
      await t.enterText(fields.at(1), 'انكسر');
      await settle(t);
      await t.tap(find.text('اختر: تالف أو عطلان'));
      await settle(t);
      expect(server.posts.where((p) => p.$1.endsWith('/stock')), isEmpty, reason: 'بلا اختيار لا يُرسل');
      await t.tap(find.text('تالف'));
      await settle(t);
      expect(find.text('الخسارة (بالكلفة المتوسّطة)'), findsOneWidget);
      await t.tap(find.text('تسجيل التالف'));
      await settle(t, seconds: 4);
      final post = server.posts.lastWhere((p) => p.$1 == '/api/v2/sales/items/1/stock');
      expect((post.$2['kind'], post.$2['qty'], post.$2['note']), ('damage', 1, 'انكسر'));
      expect(t.takeException(), isNull);
    });

    testWidgets('العطلان: الشارة تفتح الحسم، و«رجّعتها للمورّد» بمبلغٍ يطلب وجهته ثمّ يُرسل refund وrefund_to', (t) async {
      final server = _SalesServer(await visualSetUp(s1bSasOwner));
      ApiClient.dio.httpClientAdapter = server;
      await pumpVisual(t, phoneTall, home: (_) => const SalesScreen());
      await settle(t, seconds: 2);
      await t.tap(find.text('الموادّ والمخزون'));
      await settle(t, seconds: 1);
      expect(find.textContaining('عطلان في 1 مادّة'), findsOneWidget);
      await t.tap(find.text('عطلان 1 قطعة'));
      await settle(t, seconds: 1);
      expect(find.text('العطلان — راوتر TP-Link C6'), findsOneWidget);
      expect(find.text('اختر ما صار بها'), findsOneWidget);
      await t.tap(find.text('رجّعتها للمورّد'));
      await settle(t);
      // الأوّل الكمّيّة (مُعبّأةٌ بالعطلان كلّه)، والثاني المبلغ المسترجَع.
      final fields = find.descendant(of: find.byType(DesignSheet), matching: find.byType(TextField));
      await t.enterText(fields.at(1), '15000');
      await settle(t);
      expect(find.text('أين دخل المبلغ؟ *'), findsOneWidget);
      expect(find.text('10,000 د.ع'), findsOneWidget, reason: 'الخسارة = 25,000 − 15,000');
      await t.tap(find.text('تسجيل الإرجاع'));
      await settle(t);
      expect(server.posts.where((p) => p.$1.endsWith('/stock')), isEmpty, reason: 'بلا وجهة المبلغ لا يُرسل');
      await t.tap(find.text('الصندوق'));
      await settle(t);
      await t.tap(find.text('تسجيل الإرجاع'));
      await settle(t, seconds: 4);
      final post = server.posts.lastWhere((p) => p.$1 == '/api/v2/sales/items/1/stock');
      expect((post.$2['kind'], post.$2['qty'], post.$2['refund'], post.$2['refund_to']), ('supplier_return', 1, 15000, 'box'));
      expect(t.takeException(), isNull);
    });

    testWidgets('حركات العطلان: الخسارة وما رجّعه المورّد، و«إلغاء الحركة» يشرح ما يرجع ويُرسل لمسار الإلغاء', (t) async {
      final server = _SalesServer(await visualSetUp(s1bSasOwner));
      ApiClient.dio.httpClientAdapter = server;
      await pumpVisual(t, phoneTall, home: (_) => const SalesScreen());
      await settle(t, seconds: 2);
      await t.tap(find.text('الموادّ والمخزون'));
      await settle(t, seconds: 1);
      await t.tap(find.byTooltip('الحركات').at(1));
      await settle(t, seconds: 1);
      expect(find.text('رجّعته للمورّد'), findsOneWidget);
      expect(find.text('خسارة 5,000 د.ع'), findsOneWidget);
      expect(find.textContaining('رجّع المورّد 15,000 د.ع'), findsOneWidget);
      expect(find.text('عطلان ← 0'), findsOneWidget, reason: 'المخزون لم يتغيّر ⇒ العمود يعرض العطلان');
      expect(find.text('العطلان ← 2'), findsOneWidget);
      await t.tap(find.text('إلغاء الحركة'));
      await settle(t);
      expect(find.textContaining('وتُلغى خسارتها (5,000 د.ع)'), findsOneWidget);
      expect(find.textContaining('ويخرج ما رجّعه المورّد (15,000 د.ع)'), findsOneWidget);
      await t.enterText(find.byType(TextField).last, 'سُجّلت بالخطأ');
      await settle(t);
      await t.tap(find.text('إلغاء الحركة').last);
      await settle(t, seconds: 4);
      final post = server.posts.lastWhere((p) => p.$1 == '/api/v2/sales/items/2/moves/50/void');
      expect(post.$2, {'reason': 'سُجّلت بالخطأ'});
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
