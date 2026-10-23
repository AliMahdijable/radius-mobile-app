import 'dart:async';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../core/util/error_text.dart';
import '../services/auth_storage.dart';
import 'api_client.dart';

/// قسم «المبيعات» (٢٣ أكتوبر) — عقد `/api/v2/sales/*` (الخادم server/sales.js،
/// الويب pages/Sales.tsx). المالك: «وكيل انترنت عنده مواد يبيعها ويعرف شكد
/// سعرها يسعره وشكد يبيعها وربح الها».
///
/// كلّ وكيلٍ مخزونه وحده. البيع نقداً (يدخل الصندوق والمحصَّل) أو على دين
/// المشترك (مسار إضافة الدين نفسه بالخادم). الكلفة المتوسّطة المرجّحة يحسبها
/// الخادم لحظة البيع — الشاشة تعرض تقديرها فقط. المفاتيح: `sales.view` ·
/// `sales.sell` · `sales.items` · `sales.void`. الكتابة خلف مفتاح الخادم
/// `pro_settings.sales` (مطفأ ⇒ 409 `SALES_OFF`).

/// «مفعّلة لهذا الحساب؟» — GET /api/v2/sales/probe (بلا بيانات).
class SalesProbe {
  const SalesProbe({
    required this.enabled,
    this.reason,
    this.canView = false,
    this.canSell = false,
    this.canItems = false,
    this.canVoid = false,
  });

  static const off = SalesProbe(enabled: false);

  final bool enabled;

  /// `provider` = المشروع الوطنيّ · `scoped` = موظّفٌ مقيَّدٌ بمديرٍ فرعيّ.
  final String? reason;
  final bool canView;
  final bool canSell;
  final bool canItems;
  final bool canVoid;

  bool get scoped => reason == 'scoped';

  static SalesProbe fromJson(Map<String, dynamic> j) {
    final can = j['can'] is Map ? Map<String, dynamic>.from(j['can'] as Map) : const <String, dynamic>{};
    return SalesProbe(
      enabled: j['enabled'] == true,
      reason: _str(j['reason']),
      canView: can['view'] == true,
      canSell: can['sell'] == true,
      canItems: can['items'] == true,
      canVoid: can['void'] == true,
    );
  }
}

/// وحدات المادّة كما يعرفها الخادم (`sales.UNITS`).
const kSaleUnits = <String, String>{
  'piece': 'قطعة',
  'meter': 'متر',
  'box': 'كارتون',
  'roll': 'لفّة',
};

String saleUnitLabel(String? unit) => kSaleUnits[unit ?? 'piece'] ?? (unit ?? '');

class SaleItem {
  const SaleItem({
    required this.id,
    required this.name,
    required this.unit,
    required this.salePrice,
    required this.costAvg,
    required this.qty,
    required this.stockValue,
    required this.margin,
    required this.active,
    this.code,
    this.note,
  });

  final int id;
  final String name;
  final String? code;
  final String unit;
  final num salePrice;
  final num costAvg;
  final num qty;
  final num stockValue;
  final num margin;
  final bool active;
  final String? note;

  String get unitLabel => saleUnitLabel(unit);
  bool get outOfStock => qty <= 0;

  static SaleItem? fromJson(Map<String, dynamic> j) {
    final id = _int(j['id']);
    final name = _str(j['name']);
    if (id == null || name == null) return null;
    return SaleItem(
      id: id,
      name: name,
      code: _str(j['code']),
      unit: _str(j['unit']) ?? 'piece',
      salePrice: _num(j['sale_price']),
      costAvg: _num(j['cost_avg']),
      qty: _num(j['qty']),
      stockValue: _num(j['stock_value']),
      margin: _num(j['margin']),
      active: j['active'] != false,
      note: _str(j['note']),
    );
  }
}

class SaleLine {
  const SaleLine({
    required this.itemId,
    required this.name,
    required this.unit,
    required this.qty,
    required this.unitPrice,
    required this.unitCost,
    required this.total,
    required this.profit,
  });
  final int itemId;
  final String name;
  final String unit;
  final num qty;
  final num unitPrice;
  final num unitCost;
  final num total;
  final num profit;

  static SaleLine fromJson(Map<String, dynamic> j) => SaleLine(
        itemId: _int(j['item_id']) ?? 0,
        name: _str(j['name']) ?? '—',
        unit: _str(j['unit']) ?? 'piece',
        qty: _num(j['qty']),
        unitPrice: _num(j['unit_price']),
        unitCost: _num(j['unit_cost']),
        total: _num(j['total']),
        profit: _num(j['profit']),
      );
}

class Sale {
  const Sale({
    required this.id,
    required this.payment,
    required this.status,
    required this.total,
    required this.cost,
    required this.profit,
    required this.customerKind,
    required this.lines,
    this.idx,
    this.username,
    this.customerName,
    this.phone,
    this.note,
    this.by,
    this.employeeId,
    this.createdAt,
    this.voidReason,
    this.voidMode,
    this.voidDebt,
    this.voidRefund,
    this.voidBalanceBefore,
    this.voidStartedAt,
  });

  final int id;

  /// `cash` · `debt`
  final String payment;

  /// `pending` · `done` · `failed` · `unknown` · `void` · `voiding` (إلغاءٌ على الدين
  /// محجوزٌ قبل إنقاص الدين) · `void_unknown` (لم يتأكّد إنقاصه — يحسمه الوكيل)
  final String status;
  final num total;
  final num cost;
  final num profit;

  /// `subscriber` · `walkin`
  final String customerKind;
  final String? idx;
  final String? username;
  final String? customerName;
  final String? phone;
  final String? note;
  final String? by;
  final int? employeeId;
  final DateTime? createdAt;
  final String? voidReason;

  /// إلغاء البيع على الدين: `none` (لم يُسدَّد منه شيء) · `credit` (ما سدّده بقي
  /// رصيداً له) · `cash` (أُرجع له نقداً)، وإنقاص الدين، والنقد المُرجَع، ورصيده
  /// قبله (حسم «غير مؤكَّد» يعرض المتوقَّع بعده).
  final String? voidMode;
  final num? voidDebt;
  final num? voidRefund;
  final num? voidBalanceBefore;
  final DateTime? voidStartedAt;
  final List<SaleLine> lines;

  bool get isDebt => payment == 'debt';
  bool get isDone => status == 'done';
  bool get isVoid => status == 'void';
  bool get isFailed => status == 'failed';

  /// إلغاءٌ من القسم: المكتمل نقداً أو على الدين (الدين بمساره: معاينة دين
  /// المشترك ثمّ اختيار ما سدّده منه).
  bool get voidable => isDone;

  /// الحسم يخصّ الإلغاء (`resolve-void`) لا البيع.
  bool get resolvesVoid => status == 'void_unknown' || status == 'voiding';

  /// «غير مؤكَّد»: نتيجة الدين مجهولة، أو «جارٍ» أقدم من دقيقتين (انقطع الخادم
  /// بين البيع ونتيجة الدين) — يُحسم بعد فحص دين المشترك. الإلغاء على الدين مثله.
  bool resolvable([DateTime? now]) {
    final n = now ?? DateTime.now();
    if (status == 'unknown' || status == 'void_unknown') return true;
    final at = status == 'pending' ? createdAt : status == 'voiding' ? voidStartedAt : null;
    return at != null && n.difference(at) > const Duration(minutes: 2);
  }

  String get customerLabel {
    if (customerKind == 'subscriber') return customerName ?? username ?? 'مشترك';
    return customerName ?? 'زبون';
  }

  static Sale? fromJson(Map<String, dynamic> j) {
    final id = _int(j['id']);
    if (id == null) return null;
    final c = j['customer'] is Map ? Map<String, dynamic>.from(j['customer'] as Map) : const <String, dynamic>{};
    final raw = j['lines'];
    return Sale(
      id: id,
      payment: _str(j['payment']) ?? 'cash',
      status: _str(j['status']) ?? 'done',
      total: _num(j['total']),
      cost: _num(j['cost']),
      profit: _num(j['profit']),
      customerKind: _str(c['kind']) ?? 'walkin',
      idx: _str(c['idx']),
      username: _str(c['username']),
      customerName: _str(c['name']),
      phone: _str(c['phone']),
      note: _str(j['note']),
      by: _str(j['by']),
      employeeId: _int(j['employee_id']),
      createdAt: _date(j['created_at']),
      voidReason: _str(j['void_reason']),
      voidMode: _str(j['void_mode']),
      voidDebt: j['void_debt'] == null ? null : _num(j['void_debt']),
      voidRefund: j['void_refund'] == null ? null : _num(j['void_refund']),
      voidBalanceBefore: j['void_balance_before'] == null ? null : _num(j['void_balance_before']),
      voidStartedAt: _date(j['void_started_at']),
      lines: raw is List
          ? raw.whereType<Map>().map((m) => SaleLine.fromJson(Map<String, dynamic>.from(m))).toList()
          : const <SaleLine>[],
    );
  }
}

/// قبل إلغاء بيعٍ على الدين: رصيد المشترك الآن (سالب = دين) وما سُدّد من البيع
/// ونتيجة كلّ اختيار — `GET /api/v2/sales/:id/void-preview`.
class VoidPreview {
  const VoidPreview({
    required this.payment,
    required this.total,
    this.balance = 0,
    this.paid = 0,
    this.needsChoice = false,
    this.afterCredit = 0,
    this.afterCash = 0,
  });
  final String payment;
  final num total;
  final num balance;
  final num paid;
  final bool needsChoice;
  final num afterCredit;
  final num afterCash;

  static VoidPreview fromJson(Map<String, dynamic> j) => VoidPreview(
        payment: _str(j['payment']) ?? 'debt',
        total: _num(j['total']),
        balance: _num(j['balance']),
        paid: _num(j['paid']),
        needsChoice: j['needs_choice'] == true,
        afterCredit: _num(j['after_credit']),
        afterCash: _num(j['after_cash']),
      );
}

class SalesTotals {
  const SalesTotals({
    this.count = 0,
    this.revenue = 0,
    this.cost = 0,
    this.profit = 0,
    this.cash = 0,
    this.debt = 0,
  });
  final int count;
  final num revenue;
  final num cost;
  final num profit;
  final num cash;
  final num debt;

  static SalesTotals fromJson(Map<String, dynamic> j) => SalesTotals(
        count: _int(j['count']) ?? 0,
        revenue: _num(j['revenue']),
        cost: _num(j['cost']),
        profit: _num(j['profit']),
        cash: _num(j['cash']),
        debt: _num(j['debt']),
      );
}

class SalesPage {
  const SalesPage({
    required this.enabled,
    required this.sales,
    required this.totals,
    this.unresolved = 0,
    this.truncated = false,
  });
  final bool enabled;
  final List<Sale> sales;
  final SalesTotals totals;

  /// مبيعاتٌ على الدين لم تُحسم — للحساب كلّه لا للفترة.
  final int unresolved;
  final bool truncated;
}

class SaleItemsPage {
  const SaleItemsPage({
    required this.enabled,
    required this.items,
    this.count = 0,
    this.stockValue = 0,
    this.outOfStock = 0,
  });
  final bool enabled;
  final List<SaleItem> items;
  final int count;
  final num stockValue;
  final int outOfStock;

  List<SaleItem> get active => items.where((i) => i.active).toList();
}

class StockMove {
  const StockMove({
    required this.id,
    required this.kind,
    required this.qty,
    required this.qtyAfter,
    this.unitCost,
    this.saleId,
    this.note,
    this.by,
    this.employeeId,
    this.at,
  });

  final int id;

  /// `purchase` · `sale` · `return` (رجوع للمخزون) · `adjust` (جرد)
  final String kind;
  final num qty;
  final num qtyAfter;
  final num? unitCost;
  final int? saleId;
  final String? note;
  final String? by;
  final int? employeeId;
  final DateTime? at;

  static StockMove? fromJson(Map<String, dynamic> j) {
    final id = _int(j['id']);
    if (id == null) return null;
    return StockMove(
      id: id,
      kind: _str(j['kind']) ?? 'adjust',
      qty: _num(j['qty']),
      qtyAfter: _num(j['qty_after']),
      unitCost: j['unit_cost'] == null ? null : _num(j['unit_cost']),
      saleId: _int(j['sale_id']),
      note: _str(j['note']),
      by: _str(j['by']),
      employeeId: _int(j['employee_id']),
      at: _date(j['at']),
    );
  }
}

/// نتيجة طلب بيع. [ambiguous] = لم يصل حكمٌ من خادمنا (مهلة، انقطاعٌ بعد
/// الإرسال، ٥xx بلا كلامه): البيع ربّما سُجّل ⇒ أعد الإرسال **بالمرجع نفسه**
/// (لا يتكرّر البيع ولا الدين). [code] `OUTCOME_UNKNOWN` = البيع محفوظٌ
/// «غير مؤكَّد» يُحسم من القائمة؛ `DEBT_NOT_ADDED` = لم يُضَف الدين وأُعيدت
/// الكمّيّة.
class SaleResult {
  const SaleResult({
    required this.ok,
    this.sale,
    this.duplicate = false,
    this.code,
    this.message,
    this.ambiguous = false,
  });
  final bool ok;
  final Sale? sale;
  final bool duplicate;
  final String? code;
  final String? message;
  final bool ambiguous;

  /// إعادة الإرسال بالمرجع نفسه آمنة ومطلوبة (لا مرجعٌ جديد).
  bool get keepRef => ambiguous || code == 'IN_PROGRESS';
}

/// سطر بيعٍ يُرسَل: الكمّيّة بثلاث خاناتٍ عشريّة على الأكثر، والسعر صحيحٌ بالدينار.
class SaleLineInput {
  const SaleLineInput({required this.itemId, required this.qty, required this.unitPrice});
  final int itemId;
  final num qty;
  final int unitPrice;

  Map<String, dynamic> toJson() => {'item_id': itemId, 'qty': qty, 'unit_price': unitPrice};
}

class SalesApi {
  SalesApi._();

  static const _base = '/api/v2/sales';

  /// البيع على الدين ينتظر مسار الدين بالخادم (حتّى ٤٥ث) — مهلةٌ أطول من العامّة.
  static Options get _sell => Options(receiveTimeout: const Duration(seconds: 70));

  /// مرجع النيّة الواحدة (client_ref): ضغطتان أو انقطاعٌ بعد الحفظ = بيعٌ واحد.
  static String newClientRef() {
    final r = Random.secure();
    return List.generate(32, (_) => r.nextInt(16).toRadixString(16)).join();
  }

  /// `null` = تعذّر الوصول (يُعاد لاحقاً) — لا شيء يظهر بلا تأكيد.
  static Future<SalesProbe?> probe() async {
    String? token;
    try {
      token = await AuthStorage.readToken();
    } catch (_) {
      token = null;
    }
    if (token == null || token.isEmpty) return null;
    try {
      final r = await ApiClient.dio.get<Object?>('$_base/probe');
      final code = r.statusCode ?? 0;
      // ٤٠٤ = خادمٌ أقدم بلا المسار ⇒ مطفأة.
      if (code == 404) return SalesProbe.off;
      final body = _map(r.data);
      if (code >= 400 || body['success'] != true) return code == 403 ? SalesProbe.off : null;
      return SalesProbe.fromJson(body);
    } catch (e) {
      _log('probe', e);
      return null;
    }
  }

  static Future<({SaleItemsPage? page, String? error})> items({bool includeInactive = false}) async {
    try {
      final r = await ApiClient.dio.get<Object?>(
        '$_base/items',
        queryParameters: includeInactive ? const {'all': 1} : null,
      );
      final body = _map(r.data);
      if (body['success'] != true) {
        return (page: null, error: _str(body['message']) ?? 'تعذّر جلب الموادّ');
      }
      final raw = body['data'];
      final items = raw is List
          ? raw.whereType<Map>().map((m) => SaleItem.fromJson(Map<String, dynamic>.from(m))).whereType<SaleItem>().toList()
          : const <SaleItem>[];
      final t = _map(body['totals']);
      return (
        page: SaleItemsPage(
          enabled: body['enabled'] == true,
          items: items,
          count: _int(t['count']) ?? items.where((i) => i.active).length,
          stockValue: _num(t['stock_value']),
          outOfStock: _int(t['out_of_stock']) ?? 0,
        ),
        error: null,
      );
    } catch (e) {
      _log('items', e);
      return (page: null, error: humanError(e, fallback: 'تعذّر جلب الموادّ'));
    }
  }

  /// [from]/[to] بصيغة YYYY-MM-DD (بتوقيت بغداد كالخادم).
  static Future<({SalesPage? page, String? error})> list({
    required String from,
    required String to,
    int? employeeId,
  }) async {
    try {
      final r = await ApiClient.dio.get<Object?>(_base, queryParameters: {
        'from': from,
        'to': to,
        if (employeeId != null) 'employee_id': employeeId,
      });
      final body = _map(r.data);
      if (body['success'] != true) {
        return (page: null, error: _str(body['message']) ?? 'تعذّر جلب المبيعات');
      }
      final raw = body['data'];
      final sales = raw is List
          ? raw.whereType<Map>().map((m) => Sale.fromJson(Map<String, dynamic>.from(m))).whereType<Sale>().toList()
          : const <Sale>[];
      return (
        page: SalesPage(
          enabled: body['enabled'] == true,
          sales: sales,
          totals: SalesTotals.fromJson(_map(body['totals'])),
          unresolved: _int(body['unresolved']) ?? 0,
          truncated: body['truncated'] == true,
        ),
        error: null,
      );
    } catch (e) {
      _log('list', e);
      return (page: null, error: humanError(e, fallback: 'تعذّر جلب المبيعات'));
    }
  }

  /// مادّة جديدة — ومعها مخزونٌ افتتاحيّ اختياريّ ([qty] + [unitCost] معاً).
  static Future<({bool ok, String? message})> createItem({
    required String name,
    required int salePrice,
    String unit = 'piece',
    String? code,
    String? note,
    num? qty,
    int? unitCost,
  }) {
    return _write(() => ApiClient.dio.post<Object?>('$_base/items', data: {
          'name': name,
          'sale_price': salePrice,
          'unit': unit,
          if (code != null && code.isNotEmpty) 'code': code,
          if (note != null && note.isNotEmpty) 'note': note,
          if (qty != null) 'qty': qty,
          if (qty != null) 'unit_cost': unitCost ?? 0,
        }), 'تعذّر الحفظ');
  }

  /// تعديل: الحقول المتغيّرة وحدها (الاسم/السعر/الوحدة/الرمز/الملاحظة/الإيقاف).
  static Future<({bool ok, String? message})> updateItem(int id, Map<String, dynamic> patch) {
    return _write(() => ApiClient.dio.put<Object?>('$_base/items/$id', data: patch), 'تعذّر الحفظ');
  }

  /// شراء (`purchase`: كمّيّة موجبة + كلفة الوحدة) أو جرد (`adjust`: ± + سبب).
  /// [clientRef] يمنع تكرار الحركة نفسها.
  static Future<({bool ok, String? message, String? code, bool ambiguous})> stock(
    int id, {
    required String kind,
    required num qty,
    int? unitCost,
    String? note,
    required String clientRef,
  }) async {
    try {
      final r = await ApiClient.dio.post<Object?>('$_base/items/$id/stock', data: {
        'kind': kind,
        'qty': qty,
        if (kind == 'purchase') 'unit_cost': unitCost ?? 0,
        if (note != null && note.isNotEmpty) 'note': note,
        'client_ref': clientRef,
      });
      final body = _map(r.data);
      final ok = body['success'] == true;
      return (ok: ok, message: _str(body['message']), code: ok ? null : _str(body['code']), ambiguous: false);
    } catch (e) {
      _log('stock', e);
      final ours = _ourReply(e);
      if (ours != null) {
        return (ok: false, message: _str(ours['message']), code: _str(ours['code']), ambiguous: false);
      }
      return (ok: false, message: humanError(e, fallback: 'تعذّر الحفظ'), code: null, ambiguous: true);
    }
  }

  static Future<({List<StockMove>? rows, String? error})> moves(int id) async {
    try {
      final r = await ApiClient.dio.get<Object?>('$_base/items/$id/moves', queryParameters: const {'limit': 200});
      final body = _map(r.data);
      if (body['success'] != true) return (rows: null, error: _str(body['message']) ?? 'تعذّر جلب الحركات');
      final raw = body['data'];
      return (
        rows: raw is List
            ? raw.whereType<Map>().map((m) => StockMove.fromJson(Map<String, dynamic>.from(m))).whereType<StockMove>().toList()
            : const <StockMove>[],
        error: null,
      );
    } catch (e) {
      _log('moves', e);
      return (rows: null, error: humanError(e, fallback: 'تعذّر جلب الحركات'));
    }
  }

  /// بيع. **لا يُعاد تلقائيّاً** — الشاشة تعيد بالمرجع نفسه حين [SaleResult.keepRef].
  static Future<SaleResult> sell({
    required String clientRef,
    required String payment,
    required List<SaleLineInput> lines,
    required Map<String, dynamic> customer,
    String? note,
  }) async {
    try {
      final r = await ApiClient.dio.post<Object?>(
        _base,
        options: _sell,
        data: {
          'client_ref': clientRef,
          'payment': payment,
          'lines': lines.map((l) => l.toJson()).toList(),
          'customer': customer,
          if (note != null && note.isNotEmpty) 'note': note,
        },
      );
      return _saleFrom(_map(r.data));
    } catch (e) {
      _log('sell', e);
      final ours = _ourReply(e);
      if (ours != null) return _saleFrom(ours);
      return SaleResult(
        ok: false,
        ambiguous: true,
        message: humanError(e, fallback: 'تعذّر التأكّد من النتيجة'),
      );
    }
  }

  static SaleResult _saleFrom(Map<String, dynamic> body) {
    final d = body['data'];
    final sale = d is Map ? Sale.fromJson(Map<String, dynamic>.from(d)) : null;
    if (body['success'] == true) {
      return SaleResult(ok: true, sale: sale, duplicate: body['duplicate'] == true);
    }
    return SaleResult(ok: false, sale: sale, code: _str(body['code']), message: _str(body['message']));
  }

  /// بحث مشتركٍ للبيع على الدين — GET /api/subscribers/search (SAS4 وايرث لنك،
  /// والحساب الكبير يبحث في الساس نفسه لا في القائمة). فشلٌ ⇒ قائمةٌ فارغة.
  static Future<List<({String idx, String username, String name, String? phone})>> searchSubscribers(
      String term) async {
    try {
      final r = await ApiClient.dio.get<Object?>(
        '/api/subscribers/search',
        queryParameters: {'search': term, 'count': 10},
      );
      final raw = _map(r.data)['data'];
      if (raw is! List) return const [];
      final out = <({String idx, String username, String name, String? phone})>[];
      for (final m in raw.whereType<Map>()) {
        final j = Map<String, dynamic>.from(m);
        final idx = _str(j['idx']) ?? _str(j['id']);
        final username = _str(j['username']);
        if (idx == null || username == null) continue;
        final name = [_str(j['firstname']), _str(j['lastname'])].whereType<String>().join(' ').trim();
        out.add((idx: idx, username: username, name: name, phone: _str(j['phone'])));
      }
      return out;
    } catch (e) {
      _log('search', e);
      return const [];
    }
  }

  /// الإلغاء على الدين يقرأ دين المشترك ثمّ يُنقصه بمسار الدين (نداءان حتّى ٤٥ث لكلٍّ).
  static Options get _void => Options(receiveTimeout: const Duration(seconds: 100));

  /// قبل إلغاء بيعٍ على الدين: رصيد المشترك وما سُدّد من البيع — بمسار الدين نفسه
  /// (بصلاحيّته)، بلا كتابة.
  static Future<({VoidPreview? preview, String? error})> voidPreview(int id) async {
    try {
      final r = await ApiClient.dio.get<Object?>('$_base/$id/void-preview', options: _sell);
      final body = _map(r.data);
      if (body['success'] != true) {
        return (preview: null, error: _str(body['message']) ?? 'تعذّرت قراءة دين المشترك');
      }
      return (preview: VoidPreview.fromJson(_map(body['data'])), error: null);
    } catch (e) {
      _log('void-preview', e);
      final ours = _ourReply(e);
      return (
        preview: null,
        error: (ours != null ? _str(ours['message']) : null) ?? humanError(e, fallback: 'تعذّرت قراءة دين المشترك'),
      );
    }
  }

  /// إلغاء بيع ([reason] إجباريّ). النقديّ: ترجع الكمّيّة ويُسجَّل إرجاع المبلغ.
  /// على الدين: [refund] `credit`/`cash` حين سُدّد منه جزء، و[expectedPaid] ما
  /// عُرض على الوكيل. الرموز: `SALE_PAID_PART`/`PAID_CHANGED`/`BALANCE_CHANGED`
  /// (أعد المعاينة) · `OUTCOME_UNKNOWN` (محجوزٌ «غير مؤكَّد» يُحسم من القائمة) ·
  /// `AMBIGUOUS` (لم يصل حكم الخادم — حدّث القائمة، لا إعادة عمياء).
  static Future<({bool ok, String? message, String? code})> voidSale(
    int id,
    String reason, {
    String? refund,
    num? expectedPaid,
  }) async {
    try {
      final r = await ApiClient.dio.post<Object?>('$_base/$id/void', options: _void, data: {
        'reason': reason,
        if (refund != null) 'refund': refund,
        if (expectedPaid != null) 'expected_paid': expectedPaid,
      });
      final body = _map(r.data);
      final ok = body['success'] == true;
      return (ok: ok, message: _str(body['message']) ?? (ok ? null : 'تعذّر الإلغاء'), code: ok ? null : _str(body['code']));
    } catch (e) {
      _log('void', e);
      final ours = _ourReply(e);
      if (ours != null) return (ok: false, message: _str(ours['message']) ?? 'تعذّر الإلغاء', code: _str(ours['code']));
      return (ok: false, message: humanError(e, fallback: 'تعذّر التأكّد من نتيجة الإلغاء'), code: 'AMBIGUOUS');
    }
  }

  /// حسم بيعٍ على الدين بنتيجةٍ مجهولة بعد فحص دين المشترك.
  static Future<({bool ok, String? message})> resolve(int id, {required bool applied}) {
    return _write(() => ApiClient.dio.post<Object?>('$_base/$id/resolve', data: {'applied': applied}), 'تعذّر الحسم');
  }

  /// حسم إلغاء بيعٍ على الدين لم يتأكّد إنقاص دينه — بعد فحص دين المشترك.
  static Future<({bool ok, String? message})> resolveVoid(int id, {required bool applied}) {
    return _write(() => ApiClient.dio.post<Object?>('$_base/$id/resolve-void', data: {'applied': applied}), 'تعذّر الحسم');
  }

  static Future<({bool ok, String? message})> _write(Future<Response<Object?>> Function() call, String fallback) async {
    try {
      final r = await call();
      final body = _map(r.data);
      final ok = body['success'] == true;
      return (ok: ok, message: _str(body['message']) ?? (ok ? null : fallback));
    } catch (e) {
      _log('write', e);
      final ours = _ourReply(e);
      if (ours != null) return (ok: false, message: _str(ours['message']) ?? fallback);
      return (ok: false, message: humanError(e, fallback: fallback));
    }
  }

  /// ردٌّ من **خادمنا** (JSON بكلامه) داخل استثناء ٥xx — حكمٌ يُقرأ لا عطل.
  static Map<String, dynamic>? _ourReply(Object e) {
    if (e is! DioException) return null;
    final data = e.response?.data;
    if (data is! Map) return null;
    final body = Map<String, dynamic>.from(data);
    return body.containsKey('success') ? body : null;
  }

  static void _log(String what, Object e) {
    if (kDebugMode) debugPrint('🔴 sales/$what: $e');
  }
}

/// حالة القسم للبطاقة في «قوائم أخرى» — مثل [SelfDepositState]: الاستماع يطلب
/// الحالة إن كانت قديمة، ولا شيء يظهر ما لم يقل الخادم `enabled` صراحةً.
class SalesState {
  SalesState._();

  static final ValueNotifier<SalesProbe?> gate = _SalesGate();

  static int _epoch = 0;
  static DateTime? _fetchedAt;
  static DateTime? _failedAt;
  static Future<void>? _inflight;

  static const ttl = Duration(minutes: 5);
  static const _cooldown = Duration(seconds: 30);

  static bool get visible => gate.value?.enabled ?? false;

  static Future<void> ensureFresh({bool force = false}) {
    final running = _inflight;
    if (running != null) return running;
    if (!force) {
      final now = DateTime.now();
      final at = _fetchedAt;
      if (at != null && now.difference(at) < ttl) return Future<void>.value();
      final failed = _failedAt;
      if (failed != null && now.difference(failed) < _cooldown) return Future<void>.value();
    }
    final epoch = _epoch;
    late final Future<void> run;
    run = SalesApi.probe().then((p) {
      if (epoch != _epoch) return;
      if (p == null) {
        _failedAt = DateTime.now();
        return;
      }
      _fetchedAt = DateTime.now();
      _failedAt = null;
      gate.value = p;
    }).whenComplete(() {
      if (identical(_inflight, run)) _inflight = null;
    });
    _inflight = run;
    return run;
  }

  /// تبديل الجلسة: لا يرى المدير التالي حال سابقه.
  static void reset() {
    _epoch++;
    _fetchedAt = null;
    _failedAt = null;
    _inflight = null;
    gate.value = null;
  }

  @visibleForTesting
  static void debugSet(SalesProbe? p) {
    _epoch++;
    _inflight = null;
    _failedAt = null;
    _fetchedAt = p == null ? null : DateTime.now();
    gate.value = p;
  }
}

class _SalesGate extends ValueNotifier<SalesProbe?> {
  _SalesGate() : super(null);

  @override
  void addListener(VoidCallback listener) {
    super.addListener(listener);
    // بعد البناء لا أثناءه: الجلب يكتب القيمة فيُعيد بناء المستمعين.
    scheduleMicrotask(SalesState.ensureFresh);
  }
}

/// كمّيّةٌ من الإدخال (أرقام عربيّة/فاصلة عربيّة) بثلاث خاناتٍ عشريّة على الأكثر
/// — `null` إن لم تكن. [signed]: الجرد يقبل السالب. الصفر مرفوض (كالخادم).
num? parseSaleQty(String s, {bool signed = false}) {
  final t = _latin(s).trim().replaceAll(RegExp(r'[\s,٬،]'), '').replaceAll('٫', '.');
  final m = RegExp(r'^([-−])?(\d{1,6})(?:\.(\d{1,3}))?$').firstMatch(t);
  if (m == null) return null;
  if (m.group(1) != null && !signed) return null;
  final milli = int.parse(m.group(2)!) * 1000 + int.parse((m.group(3) ?? '').padRight(3, '0'));
  if (milli == 0 || milli > 100000000) return null;
  final v = milli / 1000;
  final n = v == v.roundToDouble() ? v.round() : v;
  return m.group(1) != null ? -n : n;
}

/// «3 قطعة» · «12.5 متر».
String saleQtyText(num qty, String? unit) {
  final v = qty == qty.roundToDouble() ? qty.round().toString() : _trimDecimals(qty);
  return '$v ${saleUnitLabel(unit)}';
}

String _trimDecimals(num v) {
  var s = v.toStringAsFixed(3);
  while (s.contains('.') && (s.endsWith('0') || s.endsWith('.'))) {
    s = s.substring(0, s.length - 1);
  }
  return s;
}

String _latin(String s) => s
    .replaceAllMapped(RegExp('[٠-٩]'), (m) => '${'٠١٢٣٤٥٦٧٨٩'.indexOf(m[0]!)}')
    .replaceAllMapped(RegExp('[۰-۹]'), (m) => '${'۰۱۲۳۴۵۶۷۸۹'.indexOf(m[0]!)}');

String? _str(Object? v) {
  final t = v?.toString().trim() ?? '';
  return t.isEmpty ? null : t;
}

int? _int(Object? v) => v is int ? v : int.tryParse(v?.toString() ?? '');

num _num(Object? v) => v is num ? v : num.tryParse(v?.toString() ?? '') ?? 0;

DateTime? _date(Object? v) => DateTime.tryParse(v?.toString() ?? '')?.toLocal();

Map<String, dynamic> _map(Object? v) => v is Map ? Map<String, dynamic>.from(v) : const <String, dynamic>{};
