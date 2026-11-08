import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:rad_mysvcs/api/account_api.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/api/company_route.dart';
import 'package:rad_mysvcs/api/sales_api.dart';
import 'package:rad_mysvcs/screens/sales/sales_screen.dart';
import 'package:rad_mysvcs/services/merged_mode.dart';

import 'visual_perm/visual_perm_harness.dart';

/// «المبيعات» في «كل الشركات» (٨ نوفمبر — المالك: «قسم المبيعات هم من ضمن الاقسام المدموجه هم اريد»):
///   ١. «الكل»: مجموع الفترة من كلّ الشركات، وبطاقةٌ لكلّ شركة؛ المفتوحة بلا توجيه وغيرها موجَّهة لها؛ المتعذّرة تُسمّى ولا
///      تُجمع صفراً؛ لا زرّ بيع (لا يُعرف لأيّ شركة).
///   ٢. شركةٌ غير المفتوحة: مبيعاتها وموادّها في مكانها بطلباتٍ موجَّهة، والبيع والمخزون والإلغاء مقفلةٌ بسببها — لا طلب كتابة.
///   ٣. المفتوحة: القسم كما كان (بلا توجيه، البيع مفتوح)، والخروج من القسم يعيد الطلبات للجلسة المفتوحة.
const _kOpen = 'c0000000000a1';
const _kEl = 'c0000000000e1';
const _kJt = 'c0000000000b1';

ResponseBody _json(int status, Object body, {Map<String, List<String>> headers = const {}}) =>
    ResponseBody.fromString(jsonEncode(body), status, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
      ...headers,
    });

Map<String, dynamic> _sale(int id, {int total = 45000, int cost = 32000}) => {
      'id': id, 'payment': 'cash', 'status': 'done', 'total': total, 'cost': cost, 'profit': total - cost,
      'customer': {'kind': 'walkin', 'idx': null, 'username': null, 'name': 'زبون', 'phone': null},
      'note': null, 'by': null, 'employee_id': null, 'created_at': '2026-11-08T04:05:00Z', 'voided_at': null,
      'void_reason': null,
      'lines': [
        {'item_id': 1, 'name': 'راوتر', 'unit': 'piece', 'qty': 1, 'unit_price': total, 'unit_cost': cost,
          'total': total, 'cost': cost, 'profit': total - cost},
      ],
    };

Map<String, dynamic> _item(int id, String name, {num qty = 5}) => {
      'id': id, 'name': name, 'code': null, 'unit': 'piece', 'unit_label': 'قطعة', 'sale_price': 45000,
      'cost_avg': 32000, 'qty': qty, 'stock_value': qty * 32000, 'margin': 13000, 'active': true,
    };

class _Srv implements HttpClientAdapter {
  final asked = <String>[];
  final writes = <String>[];

  /// الخطوة ٢: الخادم يفتح كتابة ايرث لنك الموجَّهة (routed_writes) — وإلّا للعرض.
  bool elWrites = false;

  /// البيع الموجَّه: ترويسة المرجع مع كلّ POST /api/v2/sales (null = بلا مرجع).
  final saleRefs = <String?>[];
  static const ref = 'r_AbCdEfGhIjKlMnOpQrStUv';

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? rs, Future<void>? cf) async {
    final key = o.headers['x-company-key'] as String?;
    final path = o.uri.path;
    final get = o.method.toUpperCase() == 'GET';
    asked.add('${o.method} $path ${key ?? '-'}');
    if (!get && path != '/api/v2/sales/debt-status') writes.add('${o.method} $path ${key ?? '-'}');
    final h = key == null ? const <String, List<String>>{} : {'x-company-key': [key]};
    // نافذة المشترك (G2): قراءته من شركته تسكّ مرجعاً
    if (path == '/api/v2/subscribers/88' && get) {
      return _json(200, {'success': true, 'data': {'idx': '88', 'username': 'zaid.el', 'firstname': 'زيد'}},
          headers: {...h, if (key != null) 'x-company-ref': [ref]});
    }
    if (path == '/api/v2/sales' && !get) {
      saleRefs.add(o.headers['x-company-ref'] as String?);
      return _json(200, {'success': true, 'data': _sale(30, total: 40000, cost: 30000)}, headers: h);
    }
    if (key == _kJt) {
      return _json(409, {'success': false, 'code': 'COMPANY_SESSION_EXPIRED', 'message': 'انتهت جلسة «الجزيرة»'}, headers: h);
    }
    final el = key == _kEl;
    if (path == '/api/v2/sales' && get) {
      return _json(200, {
        'success': true, 'enabled': true,
        'data': el ? [_sale(21, total: 40000, cost: 30000)] : [_sale(12), _sale(11, total: 45000, cost: 32500)],
        'totals': el
            ? {'count': 1, 'revenue': 40000, 'cost': 30000, 'profit': 10000, 'cash': 40000, 'debt': 0}
            : {'count': 2, 'revenue': 90000, 'cost': 64500, 'profit': 25500, 'cash': 55000, 'debt': 35000},
        'unresolved': 0,
        if (key != null) 'routed_writes': el && elWrites,
      }, headers: h);
    }
    if (path == '/api/v2/sales/items' && get) {
      final items = el ? [_item(7, 'ONU ايرث', qty: 3)] : [_item(1, 'راوتر C6'), _item(2, 'كيبل', qty: 0)];
      return _json(200, {
        'success': true, 'enabled': true, 'data': items,
        'totals': el
            ? {'count': 1, 'stock_value': 96000, 'out_of_stock': 0, 'defective_items': 0, 'defective_value': 0}
            : {'count': 2, 'stock_value': 160000, 'out_of_stock': 1, 'defective_items': 0, 'defective_value': 0},
        if (key != null) 'routed_writes': el && elWrites,
      }, headers: h);
    }
    if (path == '/api/v2/sales/debt-status') return _json(200, {'success': true, 'data': []}, headers: h);
    if (path == '/api/v2/sales/probe') {
      return _json(200, {'success': true, 'enabled': true, 'can': {'view': true, 'sell': true, 'items': true, 'void': true}});
    }
    return _json(404, {'success': false}, headers: h);
  }

  @override
  void close({bool force = false}) {}
}

Map<String, Object?> _companies() => {
      'routing': true,
      'writes': true,
      'companies': [
        // المفتوحة: مدير الجلسة في الحزمة (visualSetUp ⇒ supernet:12)
        {'key': _kOpen, 'code': 'supernet', 'username': 'u0', 'name': 'سوبرنت', 'status': 'ok', 'admin_id': 'supernet:12', 'ns': 'a', 'currency': 'IQD', 'color_index': 0},
        {'key': _kEl, 'code': 'earthlink', 'provider': 'earthlink', 'username': 'u1', 'name': 'ايرث لنك', 'status': 'ok', 'admin_id': 'earthlink:77', 'ns': 'e', 'currency': 'IQD', 'color_index': 3},
        {'key': _kJt, 'code': 'jt', 'username': 'u2', 'name': 'الجزيرة', 'status': 'ok', 'admin_id': 'jt:22', 'ns': 'j', 'currency': 'IQD', 'color_index': 1},
      ],
    };

void main() {
  setUpAll(visualSetUpAll);
  late _Srv srv;

  Future<void> up(WidgetTester t) async {
    await visualSetUp(s1bSasOwner);
    srv = _Srv();
    ApiClient.dio.httpClientAdapter = srv;
    AccountApi.tokenSource = ({bool force = false}) async => 'acct';
    MergedMode.reset();
    MergedMode.fetchRaw = () async => Map<String, dynamic>.from(_companies());
    expect(await t.runAsync(() => MergedMode.enter()), isTrue);
  }

  Future<void> down(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 3));
    SalesState.reset();
    MergedMode.reset();
    await visualTearDown();
  }

  Future<void> settleReal(WidgetTester t) async {
    for (var i = 0; i < 6; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('«الكل»: مجموع الشركات وبطاقةٌ لكلّ شركة — المتعذّرة تُسمّى، والمفتوحة بلا توجيه، ولا زرّ بيع', (t) async {
    await up(t);
    await pumpVisual(t, const VisualDevice('', Size(390, 1600), 1), home: (_) => const SalesScreen());
    await settleReal(t);
    expect(t.takeException(), isNull);

    // المفتوحة بلا مفتاح، وايرث لنك والجزيرة موجَّهتان لهما
    expect(srv.asked, containsAll(['GET /api/v2/sales -', 'GET /api/v2/sales/items -']));
    expect(srv.asked, containsAll(['GET /api/v2/sales $_kEl', 'GET /api/v2/sales/items $_kEl']));
    expect(srv.asked.where((a) => a.startsWith('GET /api/v2/sales $_kJt')), isNotEmpty);

    // المجموع: سوبرنت + ايرث لنك (الجزيرة تعذّرت ⇒ تُسمّى ولا تُجمع صفراً)
    expect(find.text('130,000 د.ع'), findsOneWidget, reason: 'المبيعات 90,000 + 40,000');
    expect(find.text('35,500 د.ع'), findsOneWidget, reason: 'الربح 25,500 + 10,000');
    expect(find.text('95,000 د.ع'), findsOneWidget, reason: 'نقداً 55,000 + 40,000');
    expect(find.textContaining('لم تدخل المجموع: «الجزيرة»'), findsOneWidget);

    // بطاقة كلّ شركة، والمفتوحة بشارتها
    expect(find.byKey(const ValueKey('sales-co-$_kOpen')), findsOneWidget);
    expect(find.byKey(const ValueKey('sales-co-$_kEl')), findsOneWidget);
    expect(find.byKey(const ValueKey('sales-co-$_kJt')), findsOneWidget);
    expect(find.text('المفتوحة'), findsOneWidget);
    expect(find.textContaining('انتهت جلسة «الجزيرة»'), findsOneWidget);
    expect(find.textContaining('نافدة 1'), findsOneWidget, reason: 'مخزون المفتوحة: نافدةٌ واحدة');

    expect(find.byType(FloatingActionButton), findsNothing, reason: '«الكل» لا يُعرف لأيّ شركةٍ يُباع');
    expect(srv.writes, isEmpty);
    expect(SalesApi.routeKey, isNull);
    await down(t);
  });

  testWidgets('شركةٌ غير المفتوحة: مبيعاتها وموادّها موجَّهة لها، والبيع والمخزون والإلغاء مقفلةٌ بسببها', (t) async {
    await up(t);
    await pumpVisual(t, const VisualDevice('', Size(390, 1600), 1), home: (_) => const SalesScreen());
    await settleReal(t);

    srv.asked.clear();
    await t.tap(find.byKey(const ValueKey('sales-co-$_kEl')));
    await settleReal(t);
    expect(t.takeException(), isNull);
    expect(MergedMode.focus.value, _kEl);
    expect(SalesApi.routeKey, _kEl);
    expect(srv.asked, containsAll(['GET /api/v2/sales $_kEl', 'GET /api/v2/sales/items $_kEl']));
    expect(srv.asked.where((a) => a.endsWith(' -') && a.contains('/api/v2/sales')), isEmpty,
        reason: 'لا طلب مبيعاتٍ للمفتوحة وهي غير معروضة');

    // أرقامها هي (لا المفتوحة) وسبب القفل ظاهر
    expect(find.text('40,000 د.ع'), findsWidgets);
    expect(find.text('90,000 د.ع'), findsNothing);
    expect(find.textContaining('«ايرث لنك» للعرض هنا'), findsOneWidget);

    // زرّ البيع مقفلٌ بسببه — لا شيت ولا طلب
    final fab = find.byType(FloatingActionButton);
    expect(fab, findsOneWidget);
    expect(find.descendant(of: fab, matching: find.byIcon(LucideIcons.lock)), findsOneWidget);
    await t.tap(fab);
    await t.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('«ايرث لنك» للعرض هنا'), findsNWidgets(2), reason: 'الشريط + رسالة القفل');

    // الإلغاء مقفل
    await t.tap(find.text('إلغاء').first);
    await t.pump(const Duration(milliseconds: 300));
    expect(srv.asked.where((a) => a.contains('void-preview')), isEmpty);

    // الموادّ: موادّها، والمخزون والتعديل مقفلان
    await t.tap(find.text('الموادّ والمخزون'));
    await settleReal(t);
    expect(find.textContaining('ONU ايرث'), findsOneWidget);
    expect(find.textContaining('راوتر C6'), findsNothing);
    await t.tap(find.text('حركة مخزون').first);
    await t.pump(const Duration(milliseconds: 300));
    expect(srv.writes, isEmpty, reason: 'لا كتابة لشركةٍ معروضةٍ للعرض');
    await t.pump(const Duration(seconds: 3));
    await down(t);
    expect(SalesApi.routeKey, isNull, reason: 'إغلاق القسم يعيد طلباته للجلسة المفتوحة');
  });

  testWidgets('المفتوحة: القسم كما كان — بلا توجيه والبيع مفتوح', (t) async {
    await up(t);
    await pumpVisual(t, const VisualDevice('', Size(390, 1600), 1), home: (_) => const SalesScreen());
    await settleReal(t);

    srv.asked.clear();
    await t.tap(find.byKey(const ValueKey('sales-co-$_kOpen')));
    await settleReal(t);
    expect(t.takeException(), isNull);
    expect(SalesApi.routeKey, isNull);
    expect(srv.asked, containsAll(['GET /api/v2/sales -', 'GET /api/v2/sales/items -']));
    expect(srv.asked.where((a) => !a.endsWith(' -')), isEmpty);
    expect(find.textContaining('للعرض هنا'), findsNothing);
    final fab = find.byType(FloatingActionButton);
    expect(fab, findsOneWidget);
    expect(find.descendant(of: fab, matching: find.byIcon(LucideIcons.shoppingCart)), findsOneWidget);
    expect(find.text('90,000 د.ع'), findsWidgets);

    // «الكل» من الشريط يعيد الملخّص
    await t.tap(find.text('الكل').first);
    await settleReal(t);
    expect(MergedMode.focus.value, isNull);
    expect(find.byKey(const ValueKey('sales-co-$_kEl')), findsOneWidget);
    await down(t);
  });

  testWidgets('الخطوة ٢: الخادم يفتح كتابة شركةٍ موجَّهة (routed_writes) ⇒ الأزرار مفتوحة واسمها فوقها', (t) async {
    await up(t);
    srv.elWrites = true;
    await pumpVisual(t, const VisualDevice('', Size(390, 1600), 1), home: (_) => const SalesScreen());
    await settleReal(t);
    await t.tap(find.byKey(const ValueKey('sales-co-$_kEl')));
    await settleReal(t);
    expect(t.takeException(), isNull);
    expect(SalesApi.routeKey, _kEl);
    expect(find.textContaining('للعرض هنا'), findsNothing);
    expect(find.textContaining('البيع والمخزون هنا لشركة «ايرث لنك»'), findsOneWidget);
    final fab = find.byType(FloatingActionButton);
    expect(find.descendant(of: fab, matching: find.byIcon(LucideIcons.shoppingCart)), findsOneWidget, reason: 'البيع مفتوح');
    expect(find.descendant(of: fab, matching: find.byIcon(LucideIcons.lock)), findsNothing);
    await down(t);
  });

  testWidgets('الخطوة ٢: البيع لمشتركٍ في شركةٍ موجَّهة يقرأ المشترك منها أوّلاً ثمّ يُرسل بمرجعه؛ العابر بلا مرجع؛ العاديّ كما كان', (t) async {
    await up(t);
    addTearDown(() {
      SalesApi.routeKey = null;
      CompanyRefs.reset();
    });
    const lines = [SaleLineInput(itemId: 7, qty: 1, unitPrice: 40000)];
    SalesApi.routeKey = _kEl;
    final r = await t.runAsync(() => SalesApi.sell(
          clientRef: 'a' * 32,
          payment: 'debt',
          lines: lines,
          customer: const {'kind': 'subscriber', 'idx': '88', 'username': 'zaid.el', 'name': 'زيد'},
        ));
    expect(r!.ok, isTrue, reason: r.message);
    final iGet = srv.asked.indexOf('GET /api/v2/subscribers/88 $_kEl');
    final iPost = srv.asked.indexOf('POST /api/v2/sales $_kEl');
    expect(iGet >= 0 && iPost > iGet, isTrue, reason: 'المشترك يُقرأ من شركته قبل البيع: ${srv.asked}');
    expect(srv.saleRefs.last, _Srv.ref, reason: 'البيع بمرجع نافذة المشترك');

    // زبونٌ عابر: لا قراءة مشترك ولا مرجع
    srv.asked.clear();
    final w = await t.runAsync(() => SalesApi.sell(
          clientRef: 'b' * 32, payment: 'cash', lines: lines, customer: const {'kind': 'walkin', 'name': 'زبون'}));
    expect(w!.ok, isTrue);
    expect(srv.asked.where((a) => a.startsWith('GET /api/v2/subscribers/')), isEmpty);
    expect(srv.saleRefs.last, isNull);

    // الوضع العاديّ (المفتوحة): لا قراءة مسبقة ولا مفتاح
    SalesApi.routeKey = null;
    srv.asked.clear();
    final n = await t.runAsync(() => SalesApi.sell(
          clientRef: 'c' * 32,
          payment: 'debt',
          lines: lines,
          customer: const {'kind': 'subscriber', 'idx': '88', 'username': 'zaid.el'},
        ));
    expect(n!.ok, isTrue);
    expect(srv.asked, ['POST /api/v2/sales -']);

    // المطلوب من الجسم كالخادم حرفاً
    expect(CompanyRefs.requireOf('POST', '/api/v2/sales', {'customer': {'kind': 'subscriber', 'idx': ' 88 '}}),
        (idx: '88', kind: CompanyRefKind.subject));
    expect(CompanyRefs.requireOf('POST', '/api/v2/sales', {'customer': {'kind': 'subscriber', 'idx': 88}})?.idx, '88');
    expect(CompanyRefs.requireOf('POST', '/api/v2/sales', {'customer': {'kind': 'walkin', 'idx': '88'}}), isNull);
    expect(CompanyRefs.requireOf('POST', '/api/v2/sales', {'customer': {'kind': 'subscriber', 'idx': 'x1'}}), isNull);
    expect(CompanyRefs.requireOf('POST', '/api/v2/sales'), isNull);
    expect(CompanyRefs.requireOf('POST', '/api/v2/subscribers/88/pay-debt'), (idx: '88', kind: CompanyRefKind.subject));
    await down(t);
  });

  testWidgets('«بيع مادّة» من صفحة مشترك شركةٍ في «كل الشركات»: موادّ شركته وبيعٌ موجَّهٌ لها — مطفأة ⇒ السبب ولا شيت؛ والوجهة تعود', (t) async {
    await up(t);
    late BuildContext ctx;
    await pumpVisual(t, const VisualDevice('', Size(390, 1600), 1), home: (_) => Scaffold(
          body: Builder(builder: (c) {
            ctx = c;
            return const SizedBox.expand();
          }),
        ));
    await settleReal(t);

    // مفتاح الشركة مطفأ (routed_writes false) ⇒ السبب، لا شيت، والوجهة كما كانت
    srv.asked.clear();
    final f1 = showSellToSubscriber(ctx, idx: '88', username: 'zaid.el', companyKey: _kEl);
    await settleReal(t);
    expect(await t.runAsync(() => f1), isFalse);
    expect(srv.asked, contains('GET /api/v2/sales/items $_kEl'), reason: 'موادّ شركته لا المفتوحة');
    expect(find.textContaining('«ايرث لنك» للعرض هنا'), findsOneWidget);
    expect(find.textContaining('البيع لشركة'), findsNothing);
    expect(SalesApi.routeKey, isNull);
    await t.pump(const Duration(seconds: 3));

    // مفتوح ⇒ شيت البيع باسم شركته وموادّها، والمشترك مختار
    srv.elWrites = true;
    srv.asked.clear();
    final f2 = showSellToSubscriber(ctx, idx: '88', username: 'zaid.el', name: 'زيد', companyKey: _kEl);
    await settleReal(t);
    expect(find.textContaining('البيع لشركة «ايرث لنك»'), findsOneWidget);
    expect(SalesApi.routeKey, _kEl, reason: 'طلبات الشيت (البحث والبيع) لشركته ما دام مفتوحاً');
    expect(srv.asked, contains('GET /api/v2/sales/items $_kEl'));
    Navigator.of(ctx).pop();
    await settleReal(t);
    expect(await t.runAsync(() => f2), isFalse);
    expect(SalesApi.routeKey, isNull, reason: 'الوجهة تعود بعد الإغلاق');
    expect(srv.writes, isEmpty);
    await down(t);
  });
}
