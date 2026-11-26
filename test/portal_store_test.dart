import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/api/portal_services_api.dart' show ServiceImage;
import 'package:rad_mysvcs/api/portal_store_api.dart';
import 'package:rad_mysvcs/api/sales_api.dart';
import 'package:rad_mysvcs/screens/portal_settings/widgets/package_image.dart';
import 'package:rad_mysvcs/screens/sales/sales_screen.dart';
import 'package:rad_mysvcs/services/fcm_service.dart';

import 'visual_perm/visual_perm_harness.dart';

/// «متجر الوكيل» بتطبيق المدير (٢٣ نوفمبر — الخادم server/portalStore.js، الويب StoreTab.tsx):
///   • النماذج على شكل ردّ الخادم الحقيقيّ (agentView / orderForAgent)، وصورةٌ من غير خادمنا تُهمل.
///   • التبويب: يظهر حين يتاح المتجر أو للصفحة معروض، بعدد المفتوح، وبلا قصٍّ على 320 ×1.2.
///   • «بيع» من الطلب ⇒ نافذة البيع نفسها معبّأةً (المادّة والكمّيّة والسعر والمشترك) ⇒ البيع ثمّ «تمّ» برقمه.
///   • القبول والرفض بسببه و«تمّ التسليم»، والعرض/الإخفاء، والتعديل (الوصف وسعر العرض والصور).
///   • الموظّف بلا مفاتيح البيع والموادّ: كلّ شيءٍ بمكانه مقفلاً ولا طلب كتابة.
///   • إشعار store_order يفتح «المبيعات» على «المتجر»، وهو من الأنواع العاجلة.
class _StoreServer implements HttpClientAdapter {
  _StoreServer(this.inner);
  final HttpClientAdapter inner;

  bool available = true;
  bool listed = true;

  /// لا معروض أبداً (ولا ONU) — متجرٌ لم يُستعمل.
  bool noListings = false;
  final calls = <(String, String, Object?)>[];

  /// ردّ «تمّ» القادم (status, body) — null ⇒ نجاح.
  (int, Object)? nextDone;

  /// «بيعٌ بحوالة» (٢٧ نوفمبر): null ⇒ الفحص لا يُجاب هنا (كما كان)؛ true/false ⇒ probe بـtransfer أو بدونه.
  bool? tw;

  /// ردّ البيع القادم (status, body) — null ⇒ نجاح (النقد بطريقته يُعاد كما أُرسل).
  (int, Object)? nextSale;

  /// الفحص يتعذّر (500) ⇒ SalesApi.probe() == null.
  bool probeFail = false;

  late List<Map<String, dynamic>> orders = [
    order(7, 'pending', item: 1, name: 'راوتر TP-Link C6', qty: 2, price: 45000,
        sub: {'idx': '501', 'username': 'ali.k@sn', 'name': 'علي كريم', 'phone': '07701234567'}, note: 'بعد العصر لو سمحت', pay: 'cash'),
    order(8, 'accepted', item: 2, name: 'كيبل Cat6', qty: 30, price: 500, sub: {'idx': '502', 'username': 'huda@sn', 'name': null, 'phone': null},
        pay: 'zaincash', receipt: true),
  ];

  /// «المتجر: الدفع»: صورة حوالة الطلب 8 (PNG 1×1 صالح) — وغيره 404.
  static final receiptBytes = base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=');
  late List<Map<String, dynamic>> past = [
    order(6, 'done', item: 1, name: 'راوتر TP-Link C6', qty: 1, price: 45000,
        sub: {'idx': '503', 'username': 'zaid@sn', 'name': 'زيد', 'phone': null}, saleId: 77, by: 'المدير'),
    order(5, 'rejected', item: 3, name: 'ONU هواوي', qty: 1, price: 30000,
        sub: {'idx': '504', 'username': 'omar@sn', 'name': 'عمر', 'phone': null}, reason: 'نفدت هذا الأسبوع'),
  ];

  late List<Map<String, dynamic>> images = [
    {'id': 101, 'url': '/api/portal/store-img/101-0123456789ab.webp'},
  ];

  static Map<String, dynamic> order(int id, String status,
          {required int item,
          required String name,
          required int qty,
          required int price,
          required Map<String, dynamic> sub,
          String? note,
          String? reason,
          int? saleId,
          String? by,
          String? pay,
          bool receipt = false}) =>
      {
        'id': id, 'item_id': 30 + item, 'sales_item_id': item, 'name': name, 'qty': qty, 'unit_price': price,
        'total': qty * price, 'note': note, 'status': status, 'reason': reason, 'created_at': '2026-11-23T05:10:00Z',
        'decided_at': null, 'done_at': null,
        'subscriber': {...sub, 'company_code': 'supernet'}, 'via': 'web', 'sale_id': saleId, 'decided_by': by,
        'pay_method': pay, 'has_receipt': receipt,
      };

  Map<String, dynamic> item1() => {
        'item_id': 1, 'name': 'راوتر TP-Link C6', 'unit': 'قطعة', 'sale_price': 45000, 'qty_on_hand': 7, 'active': true,
        'listing': listed
            ? {
                'id': 31, 'visible': true, 'description': 'راوتر ثنائي النطاق\nضمان سنة', 'price': null, 'shown_price': 45000,
                // الثانية ليست من خادمنا ⇒ تُهمل
                'images': [...images, {'id': 102, 'url': 'https://evil.example/x.png'}],
              }
            : null,
      };

  Map<String, dynamic> view() {
    final p = orders.where((o) => o['status'] == 'pending').length;
    final a = orders.where((o) => o['status'] == 'accepted').length;
    return {
      'success': true,
      'available': available,
      'items': [
        item1(),
        {'item_id': 2, 'name': 'كيبل Cat6', 'unit': 'متر', 'sale_price': 500, 'qty_on_hand': 305.5, 'active': true, 'listing': null},
        {
          'item_id': 3, 'name': 'ONU هواوي', 'unit': 'قطعة', 'sale_price': 35000, 'qty_on_hand': 0, 'active': true,
          'listing': noListings ? null : {'id': 33, 'visible': true, 'description': '', 'price': 30000, 'shown_price': 30000, 'images': []},
        },
      ],
      'open_orders': p + a,
      'counts': {'pending': p, 'accepted': a},
      'limits': {'images': 3, 'desc': 500},
    };
  }

  static final saleItems = [
    {
      'id': 1, 'name': 'راوتر TP-Link C6', 'code': 'C6', 'unit': 'piece', 'unit_label': 'قطعة',
      'sale_price': 45000, 'cost_avg': 32000, 'qty': 7, 'stock_value': 224000, 'margin': 13000, 'active': true,
    },
    {
      'id': 2, 'name': 'كيبل Cat6', 'code': null, 'unit': 'meter', 'unit_label': 'متر',
      'sale_price': 500, 'cost_avg': 250, 'qty': 305.5, 'stock_value': 76375, 'margin': 250, 'active': true,
    },
  ];

  static Map<String, dynamic> sale(int id) => {
        'id': id, 'payment': 'debt', 'status': 'done', 'total': 90000, 'cost': 64000, 'profit': 26000,
        'customer': {'kind': 'subscriber', 'idx': '501', 'username': 'ali.k@sn', 'name': 'علي كريم', 'phone': '07701234567'},
        'note': null, 'by': null, 'employee_id': null, 'created_at': '2026-11-23T05:20:00Z', 'voided_at': null, 'void_reason': null,
        'lines': [
          {'item_id': 1, 'name': 'راوتر TP-Link C6', 'unit': 'piece', 'qty': 2, 'unit_price': 45000, 'unit_cost': 32000,
            'total': 90000, 'cost': 64000, 'profit': 26000},
        ],
      };

  static ResponseBody _json(int status, Object body) => ResponseBody.fromString(jsonEncode(body), status, headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      });

  /// كتابات المسار [prefix] بترتيبها: [مسار، جسم] (قوائم لا records — الخرائط تُقارن بعمق).
  List<List<Object?>> writes(String prefix) => [
        for (final c in calls)
          if (c.$1 != 'GET' && c.$2.startsWith(prefix)) [c.$2, c.$3],
      ];

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    final m = o.method.toUpperCase();
    final p = o.path;
    if (p.startsWith('/api/v2/portal/store') || p.startsWith('/api/v2/sales')) {
      calls.add((m, p, o.data is Map ? Map<String, dynamic>.from(o.data as Map) : o.data));
    }
    // ── المبيعات ──
    if (p == '/api/v2/sales/items' && m == 'GET') {
      return _json(200, {
        'success': true, 'enabled': true, 'data': saleItems,
        'totals': {'count': 2, 'stock_value': 300375, 'out_of_stock': 0, 'defective_items': 0, 'defective_value': 0},
      });
    }
    if (p == '/api/v2/sales' && m == 'GET') {
      return _json(200, {
        'success': true, 'enabled': true, 'data': const [],
        'totals': {'count': 0, 'revenue': 0, 'cost': 0, 'profit': 0, 'cash': 0, 'debt': 0}, 'unresolved': 0,
      });
    }
    if (p == '/api/v2/sales/probe' && m == 'GET' && probeFail) return _json(500, {'success': false, 'message': 'Internal error'});
    if (p == '/api/v2/sales/probe' && m == 'GET' && tw != null) {
      return _json(200, {
        'success': true, 'enabled': true, 'can': {'view': true, 'sell': true, 'items': true, 'void': true},
        if (tw!) 'transfer': {'available': true, 'methods': ['cash', 'zaincash', 'master', 'other'], 'names': ['آسيا حوالة']},
      });
    }
    if (p == '/api/v2/sales' && m == 'POST') {
      final r = nextSale;
      if (r != null) {
        nextSale = null;
        return _json(r.$1, r.$2);
      }
      final b = o.data is Map ? Map<String, dynamic>.from(o.data as Map) : const <String, dynamic>{};
      if (b['payment'] == 'cash') {
        return _json(200, {
          'success': true,
          'data': {
            ...sale(14), 'payment': 'cash', 'total': 15000, 'cost': 7500, 'profit': 7500,
            'customer': {'kind': 'subscriber', 'idx': '502', 'username': 'huda@sn', 'name': null, 'phone': null},
            'lines': [
              {'item_id': 2, 'name': 'كيبل Cat6', 'unit': 'meter', 'qty': 30, 'unit_price': 500, 'unit_cost': 250, 'total': 15000, 'cost': 7500, 'profit': 7500},
            ],
            if (b['paid_via'] != null) 'paid_via': b['paid_via'],
            if (b['paid_via_name'] != null) 'paid_via_name': b['paid_via_name'],
          },
        });
      }
      return _json(200, {'success': true, 'data': sale(13)});
    }
    if (p.startsWith('/api/v2/subscribers/')) {
      return _json(200, {'success': true, 'data': {'idx': '501', 'username': 'ali.k@sn', 'firstname': 'علي', 'lastname': 'كريم'}});
    }
    // ── المتجر ──
    if (p == '/api/v2/portal/store' && m == 'GET') return _json(200, view());
    if (p == '/api/v2/portal/store/orders' && m == 'GET') {
      final all = o.queryParameters['status'] == 'all';
      final open = orders.where((x) => x['status'] == 'pending' || x['status'] == 'accepted').toList();
      return _json(200, {
        'success': true,
        'orders': all ? [...orders, ...past] : open,
        'counts': view()['counts'],
      });
    }
    final rc = RegExp(r'^/api/v2/portal/store/orders/(\d+)/receipt$').firstMatch(p);
    if (rc != null && m == 'GET') {
      if (rc.group(1) == '8') return ResponseBody.fromBytes(receiptBytes, 200, headers: {Headers.contentTypeHeader: ['image/jpeg']});
      return _json(404, {'success': false, 'code': 'RECEIPT_NOT_FOUND', 'message': 'لا صورة حوالة لهذا الطلب'});
    }
    final act = RegExp(r'^/api/v2/portal/store/orders/(\d+)/(accept|reject|done)$').firstMatch(p);
    if (act != null && m == 'POST') {
      final id = int.parse(act.group(1)!);
      final kind = act.group(2)!;
      if (kind == 'done' && nextDone != null) {
        final r = nextDone!;
        nextDone = null;
        return _json(r.$1, r.$2);
      }
      final row = orders.firstWhere((x) => x['id'] == id);
      row['status'] = switch (kind) { 'accept' => 'accepted', 'reject' => 'rejected', _ => 'done' };
      if (kind == 'done' && o.data is Map && (o.data as Map)['sale_id'] != null) row['sale_id'] = (o.data as Map)['sale_id'];
      if (kind == 'reject') row['reason'] = (o.data as Map?)?['reason'];
      return _json(200, {'success': true, 'order': row});
    }
    if (p == '/api/v2/portal/store/items/1' && m == 'PUT') return _json(200, {'success': true, 'item': item1()});
    if (p == '/api/v2/portal/store/items/2' && m == 'PUT') {
      return _json(200, {
        'success': true,
        'item': {
          'item_id': 2, 'name': 'كيبل Cat6', 'unit': 'متر', 'sale_price': 500, 'qty_on_hand': 305.5, 'active': true,
          'listing': {'id': 32, 'visible': true, 'description': '', 'price': null, 'shown_price': 500, 'images': []},
        },
      });
    }
    if (p == '/api/v2/portal/store/items/1/images' && m == 'POST') {
      images = [...images, {'id': 103, 'url': '/api/portal/store-img/103-abcdefabcdef.jpg'}];
      return _json(201, {'success': true, 'item': item1()});
    }
    if (p == '/api/v2/portal/store/images/101' && m == 'DELETE') {
      images = images.where((x) => x['id'] != 101).toList();
      return _json(200, {'success': true, 'item': item1()});
    }
    return inner.fetch(o, requestStream, cancelFuture);
  }

  @override
  void close({bool force = false}) => inner.close(force: force);
}

/// موظّف بعرض المبيعات وحده — البيع والموادّ مقفلة.
const _viewOnlyEmployee = Scenario(
  id: 'S_store_emp',
  title: 'موظّف — عرض المبيعات وحده',
  actor: Actor.elEmployee,
  provider: 'earthlink',
  keys: {'sales.view': true},
);

Future<_StoreServer> _open(WidgetTester t, {Scenario s = s1bSasOwner, double width = 430, double scale = 1, void Function(_StoreServer)? setup}) async {
  final server = _StoreServer(await visualSetUp(s));
  setup?.call(server);
  ApiClient.dio.httpClientAdapter = server;
  await pumpVisual(
    t,
    VisualDevice('', Size(width, 2600), 2),
    home: (_) => const SalesScreen(),
    wrap: scale == 1
        ? null
        : (child) => Builder(
              builder: (ctx) => MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(scale)), child: child),
            ),
  );
  await settle(t, seconds: 2);
  return server;
}

Future<void> _toStore(WidgetTester t) async {
  await t.tap(find.textContaining('المتجر'));
  await settle(t, seconds: 2);
}

/// لا نصٌّ مقصوصٌ بنقاط تحت [root].
void _noEllipsis(WidgetTester t, Finder root, String why) {
  for (final e in find.descendant(of: root, matching: find.byType(RichText)).evaluate()) {
    final ro = e.renderObject;
    if (ro is RenderParagraph) {
      expect(ro.didExceedMaxLines, isFalse, reason: '$why: «${ro.text.toPlainText()}» مقصوص');
    }
  }
}

void main() {
  setUpAll(visualSetUpAll);

  group('النماذج (شكل ردّ الخادم)', () {
    test('StoreView: الموادّ والمعروض والأعداد والحدود، وصورةٌ من غير خادمنا تُهمل', () {
      final s = _StoreServer(_NoNet());
      final v = StoreView.fromJson(s.view());
      expect(v.available, isTrue);
      expect(v.items.map((i) => i.itemId), [1, 2, 3]);
      expect(v.counts.open, 2);
      expect((v.imagesMax, v.descMax), (3, 500));
      expect(v.showTab, isTrue);
      expect(v.listedCount, 2);
      final it = v.items.first;
      expect(it.listing!.images.map((i) => i.id), [101], reason: 'https://evil.example لا يُقبل');
      expect(it.listing!.images.single.absoluteUrl, '${ApiClient.baseUrl}/api/portal/store-img/101-0123456789ab.webp');
      expect(storeListingState(v.items[0]), StoreListingState.listed);
      expect(storeListingState(v.items[1]), StoreListingState.notListed);
      expect(storeListingState(v.items[2]), StoreListingState.soldOut);
      expect(v.items[2].shownPrice, 30000);
      expect(v.items[1].shownPrice, 500, reason: 'غير معروضة ⇒ سعر البيع');
      // متجرٌ موقوف بلا معروض ⇒ لا تبويب؛ وبمعروضٍ سابق ⇒ يظهر للعرض
      expect(StoreView.fromJson({...s.view(), 'available': false, 'items': const []}).showTab, isFalse);
      expect(StoreView.fromJson({...s.view(), 'available': false}).showTab, isTrue);
    });

    test('«بيعٌ بحوالة»: probe.transfer والبيع بطريقته ومجموع الحوالات — وغيابها كما كان', () {
      final on = SalesProbe.fromJson({
        'success': true, 'enabled': true,
        'transfer': {'available': true, 'names': [' آسيا حوالة ', '', 3, 'كي كارد', 'a', 'b', 'c', 'd', 'e', 'f', 'g']},
      });
      expect((on.transferAvailable, on.transferNames.length, on.transferNames.first), (true, 8, 'آسيا حوالة'));
      final off = SalesProbe.fromJson({'success': true, 'enabled': true});
      expect((off.transferAvailable, off.transferNames), (false, const <String>[]));
      expect(SalesProbe.fromJson({'enabled': true, 'transfer': {'available': false, 'names': ['x']}}).transferNames, isEmpty);
      Sale sale(Map<String, dynamic> extra) => Sale.fromJson({..._StoreServer.sale(1), ...extra})!;
      expect(sale({'payment': 'cash', 'paid_via': 'master'}).viaLabel, 'حوالة ماستر');
      expect(sale({'payment': 'cash', 'paid_via': 'zaincash'}).viaLabel, 'حوالة زين كاش');
      expect(sale({'payment': 'cash', 'paid_via': 'other', 'paid_via_name': 'آسيا حوالة'}).viaLabel, 'حوالة آسيا حوالة');
      expect(sale({'payment': 'cash', 'paid_via': 'bitcoin'}).viaLabel, isNull, reason: 'طريقةٌ مجهولة تُهمل');
      expect(sale({'payment': 'cash'}).viaLabel, isNull);
      expect(sale({'payment': 'debt', 'paid_via': 'master'}).viaLabel, isNull, reason: 'الدين بلا طريقة');
      expect(SalesTotals.fromJson({'cash': 90000, 'transfers': 45000}).transfers, 45000);
      expect(SalesTotals.fromJson({'cash': 90000}).transfers, 0);
    });

    test('StoreOrder: المشترك والحال، وحالٌ مجهولة تُهمل', () {
      final s = _StoreServer(_NoNet());
      final o = StoreOrder.fromJson(s.orders.first)!;
      expect((o.id, o.salesItemId, o.qty, o.unitPrice, o.total, o.status), (7, 1, 2, 45000, 90000, 'pending'));
      expect((o.subIdx, o.subUsername, o.who, o.subPhone), ('501', 'ali.k@sn', 'علي كريم', '07701234567'));
      expect(o.isOpen && o.isPending, isTrue);
      expect(StoreOrder.fromJson(s.orders[1])!.who, 'huda@sn', reason: 'بلا اسم ⇒ اليوزر');
      expect(StoreOrder.fromJson({...s.orders.first, 'status': 'weird'}), isNull);
      expect(StoreOrder.fromJson({...s.orders.first, 'subscriber': null}), isNull);
    });

    test('«المتجر: الدفع»: الطريقة وصورة الحوالة؛ والطريقة الغريبة أو غيابها ⇒ null', () {
      final s = _StoreServer(_NoNet());
      final cash = StoreOrder.fromJson(s.orders.first)!;
      final zc = StoreOrder.fromJson(s.orders[1])!;
      expect((cash.payMethod, cash.payLabel, cash.isTransfer, cash.hasReceipt), ('cash', 'كاش عند الاستلام', false, false));
      expect((zc.payMethod, zc.payLabel, zc.isTransfer, zc.hasReceipt), ('zaincash', 'حوالة زين كاش', true, true));
      expect(StoreOrder.fromJson({...s.orders.first, 'pay_method': 'master'})!.payLabel, 'حوالة ماستر');
      expect(StoreOrder.fromJson({...s.orders.first, 'pay_method': 'visa'})!.payMethod, isNull);
      expect(StoreOrder.fromJson({...s.orders.first}..remove('pay_method'))!.payLabel, isNull, reason: 'طلبٌ من نسخةٍ قبلها');
    });

    test('إشعار store_order عاجل (صوتٌ ونافذة منبثقة) كطلب التجديد', () {
      expect(FcmService.urgentTypes, containsAll(['portal_ticket', 'renew_request', 'store_order']));
    });
  });

  group('الشاشة', () {
    tearDown(() async {
      SalesState.reset();
      storeImagePickerForTest = null;
      await visualTearDown();
    });

    for (final width in [320.0, 480.0]) {
      testWidgets('التبويب @$width ×1.2: «المتجر (2)» بلا قصّ، الطلبات والموادّ، والزرّ العائم يختفي', (t) async {
        await _open(t, width: width, scale: 1.2);
        expect(t.takeException(), isNull);
        expect(find.byKey(const ValueKey('sales-tabs-store')), findsOneWidget);
        expect(find.text('المتجر (2)'), findsOneWidget);
        expect(find.text('المخزون'), findsOneWidget, reason: 'على الهاتف مع «المتجر»');
        _noEllipsis(t, find.byKey(const ValueKey('sales-tabs-store')), 'التبويبات');
        expect(find.byType(FloatingActionButton), findsOneWidget);
        await _toStore(t);
        expect(t.takeException(), isNull);
        expect(find.byKey(const ValueKey('store-tab')), findsOneWidget);
        expect(find.byType(FloatingActionButton), findsNothing, reason: 'لا «بيع جديد» فوق المتجر');
        expect(find.byKey(const ValueKey('store-order-7')), findsOneWidget);
        expect(find.byKey(const ValueKey('store-order-8')), findsOneWidget);
        expect(find.text('1 جديد · 1 مقبول بانتظار البيع'), findsOneWidget);
        expect(find.textContaining('العدد 2'), findsOneWidget);
        expect(find.text('«بعد العصر لو سمحت»'), findsOneWidget);
        expect(find.byKey(const ValueKey('store-accept-7')), findsOneWidget);
        expect(find.byKey(const ValueKey('store-done-7')), findsNothing, reason: '«تمّ التسليم» للمقبول');
        expect(find.byKey(const ValueKey('store-done-8')), findsOneWidget);
        expect(find.byKey(const ValueKey('store-accept-8')), findsNothing);
        expect(find.text('2 معروضة لمشتركيك'), findsOneWidget);
        expect(find.text('معروضة — نفدت'), findsOneWidget);
        expect(find.text('غير معروضة'), findsOneWidget);
        _noEllipsis(t, find.byKey(const ValueKey('store-tab')), 'المتجر');
        expect(t.takeException(), isNull);
      });
    }

    for (final width in [320.0, 480.0]) {
      testWidgets('«المتجر: الدفع» @$width ×1.2: «الدفع: …» على كلّ طلب، و«صورة الحوالة» للحوالة وحدها تفتحها', (t) async {
        final server = await _open(t, width: width, scale: 1.2);
        await _toStore(t);
        expect(find.byKey(const ValueKey('store-order-pay-7')), findsOneWidget);
        expect(find.text('الدفع: كاش عند الاستلام'), findsOneWidget);
        expect(find.text('الدفع: حوالة زين كاش'), findsOneWidget);
        expect(find.byKey(const ValueKey('store-receipt-7')), findsNothing, reason: 'الكاش بلا صورة');
        expect(find.byKey(const ValueKey('store-receipt-8')), findsOneWidget);
        _noEllipsis(t, find.byKey(const ValueKey('store-tab')), 'الدفع');
        expect(t.takeException(), isNull);
        await t.ensureVisible(find.byKey(const ValueKey('store-receipt-8')));
        await t.tap(find.byKey(const ValueKey('store-receipt-8')));
        await settle(t, seconds: 2);
        // ذاكرة الجلسة: تُجلب مرّةً على الأكثر (الاختبار الثاني يجدها محفوظة)
        expect(server.calls.where((c) => c.$1 == 'GET' && c.$2 == '/api/v2/portal/store/orders/8/receipt').length, lessThanOrEqualTo(1));
        expect(find.text('صورة الحوالة — huda@sn'), findsOneWidget);
      });
    }

    testWidgets('«بيع» من الطلب: نافذة البيع معبّأةً بالمشترك والمادّة والكمّيّة ⇒ البيع ثمّ «تمّ» برقمه', (t) async {
      final server = await _open(t);
      await _toStore(t);
      await t.tap(find.byKey(const ValueKey('store-sell-7')));
      await settle(t, seconds: 2);
      expect(find.text('sales.sell_title'.tr()), findsWidgets);
      expect(find.textContaining('ali.k@sn'), findsWidgets, reason: 'المشترك مختار');
      final sell = 'sales.sell_debt_n'.tr(namedArgs: {'amount': '90,000 د.ع'});
      expect(find.text(sell), findsOneWidget, reason: '٢ × ٤٥٬٠٠٠ على دين المشترك افتراضاً');
      await t.tap(find.text(sell));
      await settle(t, seconds: 1);
      await t.tap(find.text('sales.confirm_n'.tr(namedArgs: {'amount': '90,000 د.ع'})));
      await settle(t, seconds: 3);
      final sale = server.writes('/api/v2/sales').single;
      final body = sale[1]! as Map<String, dynamic>;
      expect(body['payment'], 'debt');
      expect(body['lines'], [
        {'item_id': 1, 'qty': 2, 'unit_price': 45000}
      ]);
      expect((body['customer'] as Map)['idx'], '501');
      expect((body['customer'] as Map)['kind'], 'subscriber');
      expect(server.writes('/api/v2/portal/store/orders'), [
        ['/api/v2/portal/store/orders/7/done', {'sale_id': 13}],
      ]);
      await settle(t, seconds: 4);
      expect(server.orders.first['status'], 'done');
      expect(find.byKey(const ValueKey('store-order-7')), findsNothing, reason: 'خرج من المفتوحة');
      expect(t.takeException(), isNull);
    });

    testWidgets('البيع سُجّل و«تمّ» رُفض ⇒ يُقال بوضوح والطلب يبقى مفتوحاً', (t) async {
      final server = await _open(t);
      server.nextDone = (409, {'success': false, 'code': 'SALE_NOT_DONE', 'message': 'البيع لم يُحسم بعد (دينٌ قيد التأكّد) — احسمه من قائمة المبيعات ثمّ أعد'});
      await _toStore(t);
      await t.tap(find.byKey(const ValueKey('store-sell-7')));
      await settle(t, seconds: 2);
      await t.tap(find.text('sales.sell_debt_n'.tr(namedArgs: {'amount': '90,000 د.ع'})));
      await settle(t, seconds: 1);
      await t.tap(find.text('sales.confirm_n'.tr(namedArgs: {'amount': '90,000 د.ع'})));
      await settle(t, seconds: 2);
      expect(find.textContaining('سُجّل البيع، وتعذّر إغلاق طلب المتجر'), findsOneWidget);
      expect(find.textContaining('البيع لم يُحسم بعد'), findsOneWidget);
      await settle(t, seconds: 9);
      expect(server.orders.first['status'], 'pending');
      expect(find.byKey(const ValueKey('store-order-7')), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('قبول · «تمّ التسليم» · رفضٌ بسببه — كلٌّ بمساره', (t) async {
      final server = await _open(t);
      await _toStore(t);
      await t.tap(find.byKey(const ValueKey('store-accept-7')));
      await settle(t, seconds: 2);
      expect(find.text('قُبل الطلب — أُبلغ المشترك'), findsOneWidget);
      await settle(t, seconds: 4);
      expect(find.byKey(const ValueKey('store-done-7')), findsOneWidget, reason: 'صار مقبولاً');
      await t.ensureVisible(find.byKey(const ValueKey('store-done-8')));
      await t.tap(find.byKey(const ValueKey('store-done-8')));
      await settle(t, seconds: 4);
      await t.ensureVisible(find.byKey(const ValueKey('store-reject-7')));
      await t.tap(find.byKey(const ValueKey('store-reject-7')));
      await settle(t, seconds: 1);
      expect(find.text('رفض الطلب'), findsOneWidget);
      await t.enterText(find.byKey(const ValueKey('store-reject-reason')), 'نفدت الكمّيّة');
      await t.tap(find.text('رفض وإبلاغ المشترك'));
      await settle(t, seconds: 4);
      expect(server.writes('/api/v2/portal/store/orders'), [
        ['/api/v2/portal/store/orders/7/accept', <String, dynamic>{}],
        ['/api/v2/portal/store/orders/8/done', <String, dynamic>{}],
        ['/api/v2/portal/store/orders/7/reject', {'reason': 'نفدت الكمّيّة'}],
      ]);
      expect(find.text('لا طلبات مفتوحة الآن'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('store-orders-all')));
      await settle(t, seconds: 2);
      expect(find.text('السبب: نفدت هذا الأسبوع'), findsOneWidget, reason: '«الكلّ» يعرض ما مضى بسببه');
      expect(find.text('بيع #77 · المدير'), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('الموادّ: عرض مادّة، والتعديل: الوصف وسعر العرض باختصار الألف والصور (إضافةٌ وحذف)', (t) async {
      final server = await _open(t);
      await _toStore(t);
      await t.ensureVisible(find.byKey(const ValueKey('store-visible-2')));
      await t.tap(find.byKey(const ValueKey('store-visible-2')));
      await settle(t, seconds: 2);
      expect(server.writes('/api/v2/portal/store/items'), [
        ['/api/v2/portal/store/items/2', {'visible': true}],
      ]);
      await settle(t, seconds: 3);

      storeImagePickerForTest = () async => PreparedPackageImage(ServiceImage(Uint8List.fromList([1, 2, 3]), 'image/jpeg'), 10, 10);
      await t.ensureVisible(find.byKey(const ValueKey('store-edit-1')));
      await t.tap(find.byKey(const ValueKey('store-edit-1')));
      await settle(t, seconds: 1);
      expect(find.text('المادّة بالمتجر'), findsOneWidget);
      expect(find.byKey(const ValueKey('store-sheet-img-101')), findsOneWidget);
      expect(find.byKey(const ValueKey('store-sheet-img-102')), findsNothing);
      await t.tap(find.byKey(const ValueKey('store-sheet-add-img')));
      await settle(t, seconds: 2);
      expect(find.byKey(const ValueKey('store-sheet-img-103')), findsOneWidget, reason: 'المادّة كما أعادها الخادم');
      final img = server.writes('/api/v2/portal/store/items/1/images').single;
      expect((img[1]! as Map)['image'], 'data:image/jpeg;base64,AQID');
      await t.tap(find.byKey(const ValueKey('store-sheet-img-del-101')));
      await settle(t, seconds: 2);
      expect(server.calls.where((c) => c.$1 == 'DELETE').map((c) => c.$2), ['/api/v2/portal/store/images/101']);
      expect(find.byKey(const ValueKey('store-sheet-img-101')), findsNothing);
      await t.enterText(find.byKey(const ValueKey('store-sheet-desc')), 'راوتر ثنائي النطاق — ضمان سنة');
      await t.enterText(find.descendant(of: find.byKey(const ValueKey('store-sheet-price')), matching: find.byType(TextField)), '40');
      FocusManager.instance.primaryFocus?.unfocus();
      await settle(t, seconds: 1);
      expect(find.textContaining('40,000'), findsWidgets, reason: 'المعاينة بسعر العرض');
      await t.tap(find.text('sales.save'.tr()));
      await settle(t, seconds: 2);
      final put = server.writes('/api/v2/portal/store/items/1').last;
      expect(put[1], {'visible': true, 'description': 'راوتر ثنائي النطاق — ضمان سنة', 'price': 40000});
      expect(find.text('المادّة بالمتجر'), findsNothing, reason: 'أُغلقت بعد الحفظ');
      await settle(t, seconds: 4);
      expect(t.takeException(), isNull);
    });

    testWidgets('موظّفٌ بعرض المبيعات وحده: الأفعال والمفاتيح بمكانها مقفلة، ولا كتابة', (t) async {
      final server = await _open(t, s: _viewOnlyEmployee);
      await _toStore(t);
      expect(find.byKey(const ValueKey('store-tab')), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('store-sell-7')));
      await settle(t, seconds: 1);
      expect(find.text('sales.sell_title'.tr()), findsNothing, reason: 'بلا «بيع» ⇒ لا نافذة بيع');
      await settle(t, seconds: 4);
      await t.tap(find.byKey(const ValueKey('store-accept-7')));
      await settle(t, seconds: 1);
      await t.ensureVisible(find.byKey(const ValueKey('store-edit-1')));
      await t.tap(find.byKey(const ValueKey('store-edit-1')));
      await settle(t, seconds: 1);
      expect(find.text('المادّة بالمتجر'), findsNothing);
      await t.tap(find.byKey(const ValueKey('store-visible-1')), warnIfMissed: false);
      await settle(t, seconds: 1);
      expect(server.calls.where((c) => c.$1 != 'GET'), isEmpty);
      expect(find.byIcon(LucideIcons.lock), findsWidgets, reason: 'القفل بمكان كلّ فعل');
      await settle(t, seconds: 5);
      expect(t.takeException(), isNull);
    });

    testWidgets('متجرٌ موقوف: بلا معروضٍ ⇒ لا تبويب («المبيعات» كما كانت)؛ وبمعروضٍ سابق ⇒ يظهر للعرض بتنبيه', (t) async {
      final server = await _open(t, setup: (s) {
        s.available = false;
        s.listed = false;
        s.noListings = true;
      });
      expect(find.byKey(const ValueKey('sales-tabs-store')), findsNothing);
      expect(find.text('الموادّ والمخزون'), findsOneWidget, reason: 'التبويبان كما كانا');
      expect(server.calls.where((c) => c.$2 == '/api/v2/portal/store/orders'), isEmpty, reason: 'لا طلبات بلا تبويب');
      await visualTearDown();
      SalesState.reset();
      await t.pumpWidget(const SizedBox.shrink());
      await _open(t, setup: (s) => s.available = false);
      expect(find.byKey(const ValueKey('sales-tabs-store')), findsOneWidget, reason: 'معروضٌ سابق ⇒ التبويب للعرض');
      await _toStore(t);
      expect(find.text('«متجر الوكيل» موقوفٌ لحسابك الآن — ما تراه للعرض فقط'), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    for (final d in const [
      VisualDevice('_320', Size(320, 1700), 3),
      VisualDevice('_390dark', Size(390, 1700), 3, dark: true),
      VisualDevice('_480', Size(480, 1700), 3),
    ]) {
      testWidgets('لقطات المتجر ${d.tag}', (t) async {
        final vs = await visualSetUp(s1bSasOwner);
        final server = _StoreServer(vs);
        ApiClient.dio.httpClientAdapter = server;
        await pumpVisual(t, d, home: (_) => const SalesScreen());
        await settle(t, seconds: 2);
        await shoot(t, s1bSasOwner, 'store0_tabs', d, vs);
        await _toStore(t);
        await shoot(t, s1bSasOwner, 'store1_tab', d, vs);
        await t.ensureVisible(find.byKey(const ValueKey('store-edit-1')));
        await t.tap(find.byKey(const ValueKey('store-edit-1')));
        await settle(t, seconds: 2);
        await shoot(t, s1bSasOwner, 'store2_edit', d, vs);
        Navigator.of(t.element(find.text('المادّة بالمتجر'))).pop();
        await settle(t, seconds: 2);
        await t.ensureVisible(find.byKey(const ValueKey('store-sell-7')));
        await t.tap(find.byKey(const ValueKey('store-sell-7')));
        await settle(t, seconds: 2);
        await shoot(t, s1bSasOwner, 'store3_sell', d, vs);
      }, skip: const String.fromEnvironment('VISUAL_OUT').isEmpty);
    }

    group('«بيعٌ بحوالة» (٢٧ نوفمبر — الخادم ceb899a)', () {
      // نصوصٌ تُحسب داخل كلّ فحص (الترجمة تُحمَّل في setUpAll بعد تسجيل المجموعة)
      String sellTwText() => 'sales.sell_tw_n'.tr(namedArgs: {'via': 'حوالة زين كاش', 'amount': '15,000 د.ع'});
      String sellCashText() => 'sales.sell_cash_n'.tr(namedArgs: {'amount': '15,000 د.ع'});
      Map<String, dynamic> body(_StoreServer s, [int i = 0]) => s.writes('/api/v2/sales')[i][1]! as Map<String, dynamic>;

      testWidgets('طلبٌ بزين كاش والخادم يقبل ⇒ «نقداً» و«استلمته» زين كاش ⇒ paid_via ⇒ الإشعار بالطريقة ⇒ «تمّ»', (t) async {
        final server = await _open(t, setup: (s) => s.tw = true);
        await _toStore(t);
        await t.ensureVisible(find.byKey(const ValueKey('store-sell-8')));
        await t.tap(find.byKey(const ValueKey('store-sell-8')));
        await settle(t, seconds: 2);
        expect(find.byKey(const ValueKey('sale-paid-via')), findsOneWidget);
        expect(find.byKey(const ValueKey('sale-tw-off')), findsNothing);
        expect(find.text(sellTwText()), findsOneWidget, reason: 'الدفع «نقداً» والزرّ بالطريقة');
        await t.tap(find.text(sellTwText()));
        await settle(t, seconds: 1);
        expect(find.textContaining('بيع #14 — 15,000 د.ع حوالة زين كاش'), findsWidgets, reason: 'الإشعار بالطريقة');
        await settle(t, seconds: 2);
        final b = body(server);
        expect((b['payment'], b['paid_via'], b.containsKey('paid_via_name')), ('cash', 'zaincash', false));
        expect((b['customer'] as Map)['idx'], '502');
        expect(server.writes('/api/v2/portal/store/orders'), [
          ['/api/v2/portal/store/orders/8/done', {'sale_id': 14}],
        ]);
        await settle(t, seconds: 4);
        expect(t.takeException(), isNull);
      });

      testWidgets('يُغيَّر لكاش ⇒ «بيع نقداً» ولا paid_via (الجسم كما كان)', (t) async {
        final server = await _open(t, setup: (s) => s.tw = true);
        await _toStore(t);
        await t.ensureVisible(find.byKey(const ValueKey('store-sell-8')));
        await t.tap(find.byKey(const ValueKey('store-sell-8')));
        await settle(t, seconds: 2);
        await t.ensureVisible(find.byKey(const ValueKey('paid-via-cash')));
        await t.tap(find.byKey(const ValueKey('paid-via-cash')));
        await settle(t, seconds: 1);
        expect(find.text(sellCashText()), findsOneWidget);
        await t.tap(find.text(sellCashText()));
        await settle(t, seconds: 3);
        final b = body(server);
        expect((b['payment'], b.containsKey('paid_via')), ('cash', false));
        await settle(t, seconds: 4);
        expect(t.takeException(), isNull);
      });

      testWidgets('«أخرى» بلا اسم ⇒ لا بيع؛ باسمها ⇒ paid_via=other + الاسم', (t) async {
        final server = await _open(t, setup: (s) => s.tw = true);
        await _toStore(t);
        await t.ensureVisible(find.byKey(const ValueKey('store-sell-8')));
        await t.tap(find.byKey(const ValueKey('store-sell-8')));
        await settle(t, seconds: 2);
        await t.ensureVisible(find.byKey(const ValueKey('paid-via-other')));
        await t.tap(find.byKey(const ValueKey('paid-via-other')));
        await settle(t, seconds: 1);
        final sellOther = 'sales.sell_tw_n'.tr(namedArgs: {'via': 'حوالة أخرى', 'amount': '15,000 د.ع'});
        await t.tap(find.text(sellOther));
        await settle(t, seconds: 1);
        expect(server.writes('/api/v2/sales'), isEmpty, reason: 'بلا اسم لا يُرسل');
        await t.enterText(find.byKey(const ValueKey('paid-via-other-name')), 'آسيا حوالة');
        await settle(t, seconds: 1);
        await t.tap(find.text('sales.sell_tw_n'.tr(namedArgs: {'via': 'حوالة آسيا حوالة', 'amount': '15,000 د.ع'})));
        await settle(t, seconds: 3);
        final b = body(server);
        expect((b['paid_via'], b['paid_via_name']), ('other', 'آسيا حوالة'));
        await settle(t, seconds: 4);
        expect(t.takeException(), isNull);
      });

      testWidgets('المفتاح مطفأ للصفحة ⇒ لا «استلمته» وملاحظةٌ صادقة، والبيع كاشٌ بلا paid_via', (t) async {
        final server = await _open(t, setup: (s) => s.tw = false);
        await _toStore(t);
        await t.ensureVisible(find.byKey(const ValueKey('store-sell-8')));
        await t.tap(find.byKey(const ValueKey('store-sell-8')));
        await settle(t, seconds: 2);
        expect(find.byKey(const ValueKey('sale-paid-via')), findsNothing);
        expect(find.text('sales.tw_off_note'.tr(namedArgs: {'via': 'زين كاش'})), findsOneWidget);
        await t.tap(find.text(sellCashText()));
        await settle(t, seconds: 3);
        final b = body(server);
        expect((b['payment'], b.containsKey('paid_via')), ('cash', false));
        await settle(t, seconds: 4);
        expect(t.takeException(), isNull);
      });

      testWidgets('الفحص يتعذّر ⇒ كاشٌ كما كان بلا ملاحظة (لا نقول ما لا نعرف)', (t) async {
        final server = await _open(t, setup: (s) => s.probeFail = true);
        await _toStore(t);
        await t.ensureVisible(find.byKey(const ValueKey('store-sell-8')));
        await t.tap(find.byKey(const ValueKey('store-sell-8')));
        await settle(t, seconds: 2);
        expect(find.byKey(const ValueKey('sale-paid-via')), findsNothing);
        expect(find.byKey(const ValueKey('sale-tw-off')), findsNothing);
        await t.tap(find.text(sellCashText()));
        await settle(t, seconds: 3);
        expect(body(server).containsKey('paid_via'), isFalse);
        await settle(t, seconds: 4);
        expect(t.takeException(), isNull);
      });

      testWidgets('الخادم يرفض (أُطفئ بعد الفتح) ⇒ رسالته و«استلمته» يختفي على «بيع نقداً»، والثانية كاشٌ بمرجعٍ جديد', (t) async {
        final server = await _open(t, setup: (s) {
          s.tw = true;
          s.nextSale = (409, {'success': false, 'code': 'SALE_TRANSFER_OFF', 'message': 'البيع بحوالة غير مفعّلٍ لهذه الصفحة بعد — لم يُنفَّذ شيء. اختر «كاش».'});
        });
        await _toStore(t);
        await t.ensureVisible(find.byKey(const ValueKey('store-sell-8')));
        await t.tap(find.byKey(const ValueKey('store-sell-8')));
        await settle(t, seconds: 2);
        await t.tap(find.text(sellTwText()));
        await settle(t, seconds: 2);
        expect(find.textContaining('البيع بحوالة غير مفعّلٍ لهذه الصفحة بعد'), findsOneWidget);
        expect(find.byKey(const ValueKey('sale-paid-via')), findsNothing);
        expect(find.byKey(const ValueKey('sale-tw-off')), findsOneWidget);
        await t.tap(find.text(sellCashText()));
        await settle(t, seconds: 3);
        final first = body(server);
        final second = body(server, 1);
        expect((first['paid_via'], second.containsKey('paid_via')), ('zaincash', false));
        expect(second['client_ref'], isNot(first['client_ref']));
        await settle(t, seconds: 4);
        expect(t.takeException(), isNull);
      });

      testWidgets('طلبٌ كاش ⇒ النافذة كما كانت (على الدين افتراضاً، لا «استلمته» ولا سؤال الفحص)', (t) async {
        final server = await _open(t, setup: (s) => s.tw = true);
        await _toStore(t);
        await t.tap(find.byKey(const ValueKey('store-sell-7')));
        await settle(t, seconds: 2);
        expect(find.byKey(const ValueKey('sale-paid-via')), findsNothing);
        expect(find.text('sales.sell_debt_n'.tr(namedArgs: {'amount': '90,000 د.ع'})), findsOneWidget);
        expect(server.calls.where((c) => c.$2 == '/api/v2/sales/probe'), isEmpty);
        expect(t.takeException(), isNull);
      });
    });

    testWidgets('إشعار store_order ⇒ «المبيعات» على «المتجر»', (t) async {
      final server = _StoreServer(await visualSetUp(s1bSasOwner));
      ApiClient.dio.httpClientAdapter = server;
      final nav = GlobalKey<NavigatorState>();
      await pumpVisual(t, phoneTall, navigatorKey: nav, home: (_) => const Scaffold(body: Text('HOME')));
      await settle(t, seconds: 1);
      bool? other;
      unawaited(openStoreOrderPush(nav.currentState!, const {'type': 'renew_request'}).then((v) => other = v));
      await settle(t, seconds: 1);
      expect(other, isFalse, reason: 'نوعٌ آخر لا يُفتح');
      expect(find.byType(SalesScreen), findsNothing);
      unawaited(openStoreOrderPush(nav.currentState!, const {'type': 'store_order', 'order_id': '7'}));
      await settle(t, seconds: 3);
      expect(find.byKey(const ValueKey('store-tab')), findsOneWidget, reason: 'التبويب مفتوحٌ مباشرة');
      expect(find.byKey(const ValueKey('store-order-7')), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  });
}

/// لا شبكة (للنماذج وحدها).
class _NoNet implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? s, Future<void>? c) => throw UnimplementedError();
  @override
  void close({bool force = false}) {}
}
