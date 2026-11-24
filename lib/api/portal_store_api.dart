import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../core/util/error_text.dart';
import 'api_client.dart';
import 'company_route.dart';

/// «متجر الوكيل» (٢٣ نوفمبر — الخادم server/portalStore.js `80796b3`، الويب W28 `f16bb3b`، بوّابة المشترك `79cd47f`). المالك: «الوكيل
/// يختار منتجات من مخزونه الي بالمبيعات يعرضهن ويحطلهن صور ووصف ويظهرن بتطبيق المتشرك ويكدر المشترك يطلب شراء ايضا».
///
/// الوكيل («المبيعات» ⇐ «المتجر»): يعرض موادّ مخزونه بوصفٍ وحتى ٣ صور وسعر عرض (فارغ = سعر البيع)، ويرى طلبات مشتركيه فيقبل أو
/// يرفض بسبب، و«بيع» يفتح نافذة البيع المعتادة معبّأةً — فإذا سُجّل البيع صار الطلب «تمّ» برقمه. **لا مال من المتجر**: البيع والمخزون
/// والدين من «المبيعات» نفسها. الصلاحيّات: العرض `sales.view`، الموادّ `sales.items`، الطلبات `sales.sell`. الصفحة المفتوحة وحدها
/// (لا «كل الشركات»): كلّ نداءٍ يحمل `CompanyRoute.explicit(null)`.

/// صورة مادّةٍ بالمتجر — [url] على خادمنا (`/api/portal/store-img/<id>-<بصمة>.<امتداد>`).
class StoreImage {
  const StoreImage({required this.id, required this.url});
  final int id;
  final String url;

  /// العنوان كاملاً للتحميل (الخادم يعطيه نسبيّاً).
  String get absoluteUrl => url.startsWith('/') ? '${ApiClient.baseUrl}$url' : url;

  static final _re = RegExp(r'^/api/portal/store-img/[1-9][0-9]{0,15}-[0-9a-f]{12}\.(?:webp|png|jpg)$');

  static StoreImage? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = _int(raw['id']);
    final url = _str(raw['url']);
    if (id == null || id <= 0 || url == null || !_re.hasMatch(url)) return null;
    return StoreImage(id: id, url: url);
  }
}

/// المادّة معروضةً بالمتجر (null = لم تُعرض بعد).
class StoreListing {
  const StoreListing({
    required this.id,
    required this.visible,
    required this.description,
    required this.price,
    required this.shownPrice,
    required this.images,
  });
  final int id;
  final bool visible;
  final String description;

  /// سعر العرض — null = سعر البيع بالمخزون.
  final int? price;

  /// ما يراه المشترك الآن.
  final int shownPrice;
  final List<StoreImage> images;

  static StoreListing? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = _int(raw['id']);
    if (id == null || id <= 0) return null;
    final imgs = raw['images'];
    return StoreListing(
      id: id,
      visible: raw['visible'] == true,
      description: _str(raw['description']) ?? '',
      price: _int(raw['price']),
      shownPrice: _int(raw['shown_price']) ?? 0,
      images: imgs is List ? imgs.map(StoreImage.fromJson).whereType<StoreImage>().toList() : const [],
    );
  }
}

/// مادّةٌ من «الموادّ والمخزون» كما يراها قسم المتجر.
class StoreItem {
  const StoreItem({
    required this.itemId,
    required this.name,
    required this.unit,
    required this.salePrice,
    required this.qtyOnHand,
    required this.active,
    this.listing,
  });
  final int itemId;
  final String name;

  /// الوحدة بالعربيّة («قطعة»، «متر»…).
  final String unit;
  final int salePrice;
  final num qtyOnHand;
  final bool active;
  final StoreListing? listing;

  bool get visible => listing?.visible == true;
  int get shownPrice => listing?.shownPrice ?? salePrice;

  /// كما يراها المشترك: «متوفّر» أو «نفد».
  bool get availableToSubscriber => active && qtyOnHand > 0;

  static StoreItem? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = _int(raw['item_id']);
    final name = _str(raw['name']);
    if (id == null || id <= 0 || name == null) return null;
    return StoreItem(
      itemId: id,
      name: name,
      unit: _str(raw['unit']) ?? 'قطعة',
      salePrice: _int(raw['sale_price']) ?? 0,
      qtyOnHand: _num(raw['qty_on_hand']) ?? 0,
      active: raw['active'] == true,
      listing: StoreListing.fromJson(raw['listing']),
    );
  }
}

/// حال المادّة بالمتجر بكلمة (كالويب `listingState`).
enum StoreListingState { notListed, hidden, inactive, soldOut, listed }

StoreListingState storeListingState(StoreItem it) {
  final l = it.listing;
  if (l == null) return StoreListingState.notListed;
  if (!l.visible) return StoreListingState.hidden;
  if (!it.active) return StoreListingState.inactive;
  if (!(it.qtyOnHand > 0)) return StoreListingState.soldOut;
  return StoreListingState.listed;
}

class StoreCounts {
  const StoreCounts({this.pending = 0, this.accepted = 0});
  final int pending;
  final int accepted;
  int get open => pending + accepted;

  static StoreCounts fromJson(Object? raw) {
    if (raw is! Map) return const StoreCounts();
    return StoreCounts(pending: _int(raw['pending']) ?? 0, accepted: _int(raw['accepted']) ?? 0);
  }
}

class StoreView {
  const StoreView({
    required this.available,
    required this.items,
    required this.counts,
    this.imagesMax = 3,
    this.descMax = 500,
  });

  /// المفتاح `portal_store` مفتوحٌ لهذه الصفحة والمبيعات مفعّلة — وإلّا ما يُرى للعرض.
  final bool available;
  final List<StoreItem> items;
  final StoreCounts counts;
  final int imagesMax;
  final int descMax;

  /// التبويب يظهر: المتجر متاح، أو للصفحة معروضٌ سابق (يُرى وتُدار طلباته).
  bool get showTab => available || items.any((i) => i.listing != null);
  int get listedCount => items.where((i) => i.visible).length;

  static StoreView fromJson(Map<String, dynamic> j) {
    final items = j['items'];
    final lim = j['limits'] is Map ? j['limits'] as Map : const {};
    return StoreView(
      available: j['available'] == true,
      items: items is List ? items.map(StoreItem.fromJson).whereType<StoreItem>().toList() : const [],
      counts: StoreCounts.fromJson(j['counts']),
      imagesMax: (_int(lim['images']) ?? 3).clamp(1, 10),
      descMax: (_int(lim['desc']) ?? 500).clamp(1, 5000),
    );
  }

  StoreView withItem(StoreItem it) => StoreView(
        available: available,
        items: [for (final x in items) x.itemId == it.itemId ? it : x],
        counts: counts,
        imagesMax: imagesMax,
        descMax: descMax,
      );
}

/// `pending` · `accepted` · `rejected` · `done` · `cancelled` · `expired`
class StoreOrder {
  const StoreOrder({
    required this.id,
    required this.salesItemId,
    required this.name,
    required this.qty,
    required this.unitPrice,
    required this.total,
    required this.status,
    required this.subIdx,
    this.subUsername,
    this.subName,
    this.subPhone,
    this.note,
    this.reason,
    this.createdAt,
    this.saleId,
    this.decidedBy,
    this.via,
    this.payMethod,
    this.hasReceipt = false,
  });
  final int id;
  final int salesItemId;
  final String name;
  final int qty;
  final int unitPrice;
  final int total;
  final String status;
  final String subIdx;
  final String? subUsername;
  final String? subName;
  final String? subPhone;
  final String? note;
  final String? reason;
  final DateTime? createdAt;
  final int? saleId;
  final String? decidedBy;
  final String? via;

  /// «المتجر: الدفع» (٢٥ نوفمبر): cash | zaincash | master — null لطلبٍ من نسخة مشتركٍ قبلها.
  final String? payMethod;

  /// أرفق المشترك صورة الحوالة ([PortalStoreApi.receipt]).
  final bool hasReceipt;

  bool get isTransfer => payMethod == 'zaincash' || payMethod == 'master';

  /// «كاش عند الاستلام» / «حوالة زين كاش» / «حوالة ماستر» — null بلا طريقة.
  String? get payLabel => switch (payMethod) {
        'cash' => 'كاش عند الاستلام',
        'zaincash' => 'حوالة زين كاش',
        'master' => 'حوالة ماستر',
        _ => null,
      };

  bool get isOpen => status == 'pending' || status == 'accepted';
  bool get isPending => status == 'pending';
  bool get isAccepted => status == 'accepted';

  /// اسم المشترك كما يُعرض: الاسم، وإلّا اليوزر، وإلّا رقمه.
  String get who {
    final n = (subName ?? '').trim();
    if (n.isNotEmpty) return n;
    final u = (subUsername ?? '').trim();
    return u.isNotEmpty ? u : 'مشترك $subIdx';
  }

  static const statuses = {'pending', 'accepted', 'rejected', 'done', 'cancelled', 'expired'};

  static StoreOrder? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = _int(raw['id']);
    final status = _str(raw['status']);
    final sub = raw['subscriber'] is Map ? raw['subscriber'] as Map : const {};
    final idx = _str(sub['idx']);
    if (id == null || id <= 0 || status == null || !statuses.contains(status) || idx == null) return null;
    return StoreOrder(
      id: id,
      salesItemId: _int(raw['sales_item_id']) ?? 0,
      name: _str(raw['name']) ?? '—',
      qty: _int(raw['qty']) ?? 1,
      unitPrice: _int(raw['unit_price']) ?? 0,
      total: _int(raw['total']) ?? 0,
      status: status,
      subIdx: idx,
      subUsername: _str(sub['username']),
      subName: _str(sub['name']),
      subPhone: _str(sub['phone']),
      note: _str(raw['note']),
      reason: _str(raw['reason']),
      createdAt: _date(raw['created_at']),
      saleId: _int(raw['sale_id']),
      decidedBy: _str(raw['decided_by']),
      via: _str(raw['via']),
      payMethod: switch (raw['pay_method']) { final String m when const {'cash', 'zaincash', 'master'}.contains(m) => m, _ => null },
      hasReceipt: raw['has_receipt'] == true,
    );
  }
}

/// نتيجة كتابة: نجحت؟ ورسالة الخادم العربيّة، والمادّة/الطلب كما صارا.
typedef StoreWrite = ({bool ok, String? message, String? code, StoreItem? item, StoreOrder? order});

class PortalStoreApi {
  PortalStoreApi._();

  static const _base = '/api/v2/portal/store';
  static const _fallback = 'تعذّر الاتّصال — أعد المحاولة';

  /// الصفحة المفتوحة وحدها.
  static Options get _open => CompanyRoute.explicit(null);

  /// null = تعذّر (لا تبويب ولا خطأ يُعرض — «المبيعات» كما كانت).
  static Future<({StoreView? view, String? error})> view() async {
    try {
      final r = await ApiClient.dio.get<Object?>(_base, options: _open);
      final body = _map(r.data);
      if (body['success'] != true) return (view: null, error: _str(body['message']) ?? _fallback);
      return (view: StoreView.fromJson(body), error: null);
    } catch (e) {
      _log('view', e);
      return (view: null, error: _msg(e));
    }
  }

  /// [all] = طلبات الشهرين الماضيين كلّها؛ وإلّا المفتوحة (الجديدة والمقبولة).
  static Future<({List<StoreOrder>? orders, StoreCounts? counts, String? error})> orders({required bool all}) async {
    try {
      final r = await ApiClient.dio.get<Object?>('$_base/orders', queryParameters: {'status': all ? 'all' : 'open'}, options: _open);
      final body = _map(r.data);
      if (body['success'] != true) return (orders: null, counts: null, error: _str(body['message']) ?? 'تعذّر جلب الطلبات');
      final list = body['orders'];
      return (
        orders: list is List ? list.map(StoreOrder.fromJson).whereType<StoreOrder>().toList() : <StoreOrder>[],
        counts: StoreCounts.fromJson(body['counts']),
        error: null,
      );
    } catch (e) {
      _log('orders', e);
      return (orders: null, counts: null, error: _msg(e, 'تعذّر جلب الطلبات'));
    }
  }

  static final Map<int, Uint8List> _receipts = {};

  /// «المتجر: الدفع» (٢٥ نوفمبر): صورة حوالة الطلب (ذاكرة الجلسة — لا قرص). gone = لا صورة أو حُذفت بعد ٦٠ يوماً (٤٠٤).
  static Future<({Uint8List? bytes, bool gone})> receipt(int orderId) async {
    final hit = _receipts[orderId];
    if (hit != null) return (bytes: hit, gone: false);
    try {
      final r = await ApiClient.dio.get<List<int>>('$_base/orders/$orderId/receipt',
          options: _open.copyWith(responseType: ResponseType.bytes, validateStatus: (s) => s != null && s < 500));
      final d = r.data;
      if (r.statusCode == 200 && d != null && d.isNotEmpty) {
        final b = Uint8List.fromList(d);
        if (_receipts.length >= 12) _receipts.remove(_receipts.keys.first);
        _receipts[orderId] = b;
        return (bytes: b, gone: false);
      }
      if (r.statusCode == 404 || r.statusCode == 410) return (bytes: null, gone: true);
    } catch (e) {
      _log('receipt', e);
    }
    return (bytes: null, gone: false);
  }

  /// عرض المادّة/إخفاؤها ووصفها وسعر عرضها ([price] null = سعر البيع). الحقل الغائب لا يتغيّر.
  static Future<StoreWrite> saveItem(int itemId, {bool? visible, String? description, bool setPrice = false, int? price}) =>
      _write(() => ApiClient.dio.put<Object?>('$_base/items/$itemId', data: {
            if (visible != null) 'visible': visible,
            if (description != null) 'description': description,
            if (setPrice) 'price': price,
          }, options: _open));

  /// صورةٌ مضغوطة (data URL) — حتى [StoreView.imagesMax].
  static Future<StoreWrite> addImage(int itemId, String dataUrl) => _write(
      () => ApiClient.dio.post<Object?>('$_base/items/$itemId/images',
          data: {'image': dataUrl}, options: _open.copyWith(sendTimeout: const Duration(seconds: 60))));

  static Future<StoreWrite> removeImage(int imageId) =>
      _write(() => ApiClient.dio.delete<Object?>('$_base/images/$imageId', options: _open));

  static Future<StoreWrite> accept(int orderId) =>
      _write(() => ApiClient.dio.post<Object?>('$_base/orders/$orderId/accept', data: const {}, options: _open));

  static Future<StoreWrite> reject(int orderId, String reason) =>
      _write(() => ApiClient.dio.post<Object?>('$_base/orders/$orderId/reject', data: {'reason': reason}, options: _open));

  /// «تمّ»: بلا [saleId] = «تمّ التسليم» بيد الوكيل؛ وبه = البيع الذي سُجّل لهذا الطلب (يتحقّق منه الخادم).
  static Future<StoreWrite> done(int orderId, {int? saleId}) => _write(() => ApiClient.dio
      .post<Object?>('$_base/orders/$orderId/done', data: {if (saleId != null) 'sale_id': saleId}, options: _open));

  static Future<StoreWrite> _write(Future<Response<Object?>> Function() call) async {
    try {
      final r = await call();
      final body = _map(r.data);
      final ok = body['success'] == true;
      return (
        ok: ok,
        message: _str(body['message']) ?? (ok ? null : _fallback),
        code: _str(body['code']),
        item: StoreItem.fromJson(body['item']),
        order: StoreOrder.fromJson(body['order']),
      );
    } catch (e) {
      _log('write', e);
      final ours = _ourReply(e);
      if (ours != null) {
        return (
          ok: false,
          message: _str(ours['message']) ?? _fallback,
          code: _str(ours['code']),
          item: null,
          order: StoreOrder.fromJson(ours['order']),
        );
      }
      return (ok: false, message: humanError(e, fallback: _fallback), code: null, item: null, order: null);
    }
  }

  static String _msg(Object e, [String fallback = _fallback]) {
    final ours = _ourReply(e);
    return _str(ours?['message']) ?? humanError(e, fallback: fallback);
  }

  /// ردٌّ من **خادمنا** (JSON بكلامه) داخل استثناء ٤xx/٥xx — حكمٌ يُقرأ لا عطل.
  static Map<String, dynamic>? _ourReply(Object e) {
    if (e is! DioException) return null;
    final data = e.response?.data;
    if (data is! Map) return null;
    final body = Map<String, dynamic>.from(data);
    return body.containsKey('success') ? body : null;
  }

  static void _log(String what, Object e) {
    if (kDebugMode) debugPrint('🔴 store/$what: $e');
  }
}

Map<String, dynamic> _map(Object? v) => v is Map ? Map<String, dynamic>.from(v) : const {};

String? _str(Object? v) {
  if (v == null) return null;
  final s = v.toString().trim();
  return s.isEmpty ? null : s;
}

num? _num(Object? v) {
  if (v is num) return v.isFinite ? v : null;
  if (v is String) return num.tryParse(v.trim());
  return null;
}

int? _int(Object? v) => _num(v)?.round();

DateTime? _date(Object? v) {
  final s = _str(v);
  if (s == null) return null;
  return DateTime.tryParse(s)?.toLocal();
}
