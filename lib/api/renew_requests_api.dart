import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../services/auth_storage.dart';
import '../services/inbox_service.dart';
import 'api_client.dart';
import 'company_route.dart';

/// «طلبات التفعيل» (٤ نوفمبر — الخادم server/portalRenew.js): المشترك يطلب تجديد اشتراكه من تطبيقه (أو /mysub) مع صورة التحويل
/// (زين كاش/ماستر)، والمدير يقبل أو يرفض، وأوّل تفعيلٍ للمشترك بعد الطلب (أو «تمّ التفعيل») يبلّغه «تم تفعيل اشتراكك بنجاح».
/// المبلغ للعرض وحده — لا تفعيل ولا مال من هنا. الصورة تُحذف من الخادم بعد ٢٤ ساعة.
///   GET  /api/v2/portal/renew-settings              ⇒ available · can_use · can_edit · scoped · enabled · zaincash · master · note
///   GET  /api/v2/portal/renew-requests?status=open|all ⇒ items · counts {pending, accepted}
///   GET  /api/v2/portal/renew-requests/:id/image    ⇒ JPEG (٤١٠ بعد الحذف)
///   POST /api/v2/portal/renew-requests/:id/accept | reject {reason} | done
///   PUT  /api/v2/portal/renew-settings              { enabled?, zaincash?, master?, note? }

DateTime? _time(Object? v) => v is String && v.isNotEmpty ? DateTime.tryParse(v)?.toLocal() : null;
int? _int(Object? v) => v is num ? v.round() : null;
String? _str(Object? v) {
  final s = v?.toString().trim();
  return s == null || s.isEmpty ? null : s;
}

class RenewRequest {
  const RenewRequest({
    required this.id,
    required this.status,
    required this.subscriberIdx,
    this.months,
    this.packageId,
    this.packageName,
    this.samePackage = true,
    this.unitPrice,
    this.amount,
    this.payMethod,
    this.createdAt,
    this.decidedAt,
    this.doneAt,
    this.rejectReason,
    this.username,
    this.name,
    this.currentPackage,
    this.note,
    this.via = 'app',
    this.imageAvailable = false,
    this.imageExpiresAt,
    this.decidedBy,
    this.doneSource,
  });

  final int id;

  /// pending · accepted · rejected · done · cancelled · expired
  final String status;
  final String subscriberIdx;
  final int? months;
  final String? packageId;
  final String? packageName;
  final bool samePackage;
  final int? unitPrice;
  final int? amount;

  /// zaincash · master · other
  final String? payMethod;
  final DateTime? createdAt;
  final DateTime? decidedAt;
  final DateTime? doneAt;
  final String? rejectReason;
  final String? username;
  final String? name;
  final String? currentPackage;
  final String? note;

  /// app · web
  final String via;
  final bool imageAvailable;
  final DateTime? imageExpiresAt;
  final String? decidedBy;

  /// detected (سجلّ النشاط) · marked (زرّ المدير)
  final String? doneSource;

  bool get isPending => status == 'pending';
  bool get isOpen => status == 'pending' || status == 'accepted';

  /// اسمه وإلّا يوزره.
  String get title => (name ?? '').trim().isNotEmpty ? name!.trim() : (username ?? '#$subscriberIdx');

  static RenewRequest? fromJson(Object? j) {
    if (j is! Map) return null;
    final id = _int(j['id']);
    final status = _str(j['status']);
    final sub = j['subscriber'];
    final idx = sub is Map ? _str(sub['idx']) : null;
    if (id == null || status == null || idx == null) return null;
    final pkg = j['package'];
    final img = j['image'];
    return RenewRequest(
      id: id,
      status: status,
      subscriberIdx: idx,
      months: _int(j['months']),
      packageId: pkg is Map ? _str(pkg['id']) : null,
      packageName: pkg is Map ? _str(pkg['name']) : null,
      samePackage: pkg is Map ? pkg['same'] != false : true,
      unitPrice: _int(j['unit_price']),
      amount: _int(j['amount']),
      payMethod: _str(j['pay_method']),
      createdAt: _time(j['created_at']),
      decidedAt: _time(j['decided_at']),
      doneAt: _time(j['done_at']),
      rejectReason: _str(j['reject_reason']),
      username: sub is Map ? _str(sub['username']) : null,
      name: sub is Map ? _str(sub['name']) : null,
      currentPackage: _str(j['current_package']),
      note: _str(j['note']),
      via: _str(j['via']) ?? 'app',
      imageAvailable: img is Map && img['available'] == true,
      imageExpiresAt: img is Map ? _time(img['expires_at']) : null,
      decidedBy: _str(j['decided_by']),
      doneSource: _str(j['done_source']),
    );
  }
}

/// ما يملكه المستخدم من الميزة — يُقرأ لكلّ مستخدمٍ للحساب (الموظّف بلا صلاحيّة يرى القسم مقفلاً لا مخفيّاً).
class RenewAccess {
  const RenewAccess({
    required this.available,
    this.canUse = false,
    this.canEdit = false,
    this.scoped = false,
    this.enabled = false,
    this.zaincash,
    this.master,
    this.note,
  });

  /// المفتاح العامّ portal_renew مفتوحٌ لهذا الحساب.
  final bool available;
  final bool canUse;
  final bool canEdit;

  /// موظّفٌ مقيَّدٌ بمديرٍ فرعيّ — القسم يشمل كلّ مشتركي الحساب فلا يُفتح له.
  final bool scoped;

  /// مفتاح الوكيل: مشتركوه يرون «طلب التجديد».
  final bool enabled;
  final String? zaincash;
  final String? master;
  final String? note;

  static const off = RenewAccess(available: false);

  static RenewAccess fromJson(Map j) => RenewAccess(
        available: j['available'] == true,
        canUse: j['can_use'] == true,
        canEdit: j['can_edit'] == true,
        scoped: j['scoped'] == true,
        enabled: j['enabled'] == true,
        zaincash: _str(j['zaincash']),
        master: _str(j['master']),
        note: _str(j['note']),
      );
}

/// صورة الحال للجرس والقائمة: المتاح وما يملكه المستخدم + الطلبات المفتوحة (بانتظارك أوّلاً).
class RenewSnapshot {
  const RenewSnapshot({required this.access, this.items = const [], this.pending = 0, this.accepted = 0});
  final RenewAccess access;
  final List<RenewRequest> items;
  final int pending;
  final int accepted;

  /// القسم متاحٌ لهذا المستخدم (المفتاح مفتوح ويملك القسم).
  bool get on => access.available && access.canUse;
}

/// المفتوحة: «بانتظارك» أوّلاً ثمّ المقبولة، والأحدث أوّلاً في كلٍّ.
List<RenewRequest> sortOpenFirst(Iterable<RenewRequest> list) {
  final out = list.toList();
  out.sort((a, b) {
    if (a.status == b.status) return b.id.compareTo(a.id);
    return a.isPending ? -1 : (b.isPending ? 1 : b.id.compareTo(a.id));
  });
  return out;
}

class RenewRequestsApi {
  RenewRequestsApi._();

  static String? _msg(Object? data) => data is Map ? _str(data['message']) : null;

  /// null = تعذّر (شبكة/خادم)؛ [RenewAccess.off] = غير مفتوحٍ لحسابه.
  static Future<RenewAccess?> access() async {
    // بلا جلسة (قبل الدخول، أو اختبارٌ بلا خادم) لا نداء — كمسبار «المبيعات»
    String? token;
    try {
      token = await AuthStorage.readToken();
    } catch (_) {
      token = null;
    }
    if (token == null || token.isEmpty) return null;
    try {
      final r = await ApiClient.dio.get<Map<String, dynamic>>('/api/v2/portal/renew-settings');
      final d = r.data;
      if (r.statusCode == 200 && d != null && d['success'] == true) return RenewAccess.fromJson(d);
      // مسارٌ غير موجود (خادمٌ أقدم) أو بلا هويّة ⇒ لا ميزة
      if (r.statusCode == 404) return RenewAccess.off;
    } catch (e) {
      if (kDebugMode) debugPrint('⚠️ renew access: $e');
    }
    return null;
  }

  /// null = تعذّر.
  static Future<({List<RenewRequest> items, int pending, int accepted})?> list({bool all = false}) async {
    try {
      final r = await ApiClient.dio.get<Map<String, dynamic>>('/api/v2/portal/renew-requests',
          queryParameters: {'status': all ? 'all' : 'open'});
      final d = r.data;
      if (r.statusCode == 200 && d != null && d['success'] == true) {
        final items = d['items'];
        final counts = d['counts'];
        return (
          items: items is List ? items.map(RenewRequest.fromJson).whereType<RenewRequest>().toList() : <RenewRequest>[],
          pending: counts is Map ? _int(counts['pending']) ?? 0 : 0,
          accepted: counts is Map ? _int(counts['accepted']) ?? 0 : 0,
        );
      }
    } catch (e) {
      if (kDebugMode) debugPrint('⚠️ renew list: $e');
    }
    return null;
  }

  static final Map<int, Uint8List> _images = {};

  /// صورة التحويل (تُحفظ بالذاكرة للجلسة — لا قرص). gone = حُذفت بعد ٢٤ ساعة (٤١٠/٤٠٤).
  static Future<({Uint8List? bytes, bool gone})> image(int id) async {
    final hit = _images[id];
    if (hit != null) return (bytes: hit, gone: false);
    try {
      final r = await ApiClient.dio.get<List<int>>('/api/v2/portal/renew-requests/$id/image',
          options: Options(responseType: ResponseType.bytes));
      if (r.statusCode == 200 && r.data != null && r.data!.isNotEmpty) {
        final b = Uint8List.fromList(r.data!);
        if (_images.length >= 12) _images.remove(_images.keys.first);
        _images[id] = b;
        return (bytes: b, gone: false);
      }
      if (r.statusCode == 410 || r.statusCode == 404) return (bytes: null, gone: true);
    } catch (e) {
      if (kDebugMode) debugPrint('⚠️ renew image: $e');
    }
    return (bytes: null, gone: false);
  }

  /// accept · reject · done. request = الطلب كما صار (أو كما هو حين تغيّرت حاله — ٤٠٩).
  static Future<({bool ok, String? message, RenewRequest? request})> act(int id, String action, {String? reason}) async {
    try {
      final r = await ApiClient.dio.post<Map<String, dynamic>>('/api/v2/portal/renew-requests/$id/$action',
          data: {if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim()});
      final d = r.data;
      final req = RenewRequest.fromJson(d?['request']);
      if (r.statusCode == 200 && d?['success'] == true) return (ok: true, message: null, request: req);
      return (ok: false, message: _msg(d) ?? 'تعذّر الآن — حاول مرّة ثانية', request: req);
    } catch (e) {
      return (ok: false, message: e is DioException ? _msg(e.response?.data) ?? 'تعذّر الاتصال' : 'تعذّر الآن', request: null);
    }
  }

  static Future<({bool ok, String? message, RenewAccess? settings})> saveSettings({
    bool? enabled,
    String? zaincash,
    String? master,
    String? note,
  }) async {
    try {
      final r = await ApiClient.dio.put<Map<String, dynamic>>('/api/v2/portal/renew-settings', data: {
        if (enabled != null) 'enabled': enabled,
        if (zaincash != null) 'zaincash': zaincash,
        if (master != null) 'master': master,
        if (note != null) 'note': note,
      });
      final d = r.data;
      if (r.statusCode == 200 && d != null && d['success'] == true) {
        return (ok: true, message: null, settings: RenewAccess.fromJson(d));
      }
      return (ok: false, message: _msg(d) ?? 'تعذّر الحفظ', settings: null);
    } catch (e) {
      return (ok: false, message: e is DioException ? _msg(e.response?.data) ?? 'تعذّر الاتصال' : 'تعذّر الحفظ', settings: null);
    }
  }

  @visibleForTesting
  static void clearImages() => _images.clear();
}

/// حال «طلبات التفعيل» للجلسة — الجرس وصندوق الإشعارات و«قوائم أخرى» يستمعون له. يُقرأ عند أوّل مستمع، وعند العودة للتطبيق،
/// وحين يصل إشعار طلبٍ جديد (FCM أو تغذية الحاسبة — كلاهما يمرّ بصندوق الإشعارات)، وبعد كلّ إجراء.
class RenewRequestsState {
  RenewRequestsState._();

  /// null = لم يُعرف بعد.
  static final ValueNotifier<RenewSnapshot?> gate = _RenewGate();

  static int _epoch = 0;
  static DateTime? _fetchedAt;
  static DateTime? _failedAt;
  static RenewAccess? _access;
  static DateTime? _accessAt;
  static Future<void>? _inflight;
  static String? _lastInboxId;

  /// متى سُئلت القائمة المنشورة — ما وصل الصندوقَ قبله من إشعارات الطلبات حالُه فيها ([inboxDuplicates]).
  static DateTime? _countsAsOf;

  /// الشركة التي تعرض الحال طلباتها (المفتوحة، كما في بيانات دفعها `company_admin_id`).
  static String? _adminId;

  static const ttl = Duration(minutes: 2);
  static const _accessTtl = Duration(minutes: 10);
  static const _cooldown = Duration(seconds: 20);

  static bool get on => gate.value?.on ?? false;
  static int get pending => on ? gate.value!.pending : 0;

  /// إشعارات طلبات تجديدٍ غير مقروءة في الصندوق يعدّها [pending] أصلاً — تُطرح من رقم الجرس (`TopActions`) فيُعدّ كلّ طلبٍ مرّةً واحدة
  /// (مراجعة 3.0.18 — قاعدة التذاكر نفسها، `TicketsState.inboxDuplicates`: طلبٌ جديد والتطبيق مفتوح كان ٢ — إشعاره غير المقروء
  /// والطلب). المعدود: إشعارٌ لطلبٍ بانتظارك الآن، أو وصل قبل آخر سؤالٍ للقائمة فحاله فيها (بانتظارك ⇒ معدود، قُبل أو رُفض أو
  /// فُعّل ⇒ لا ينتظرك). وما سواه يُعدّ كأيّ إشعار: طلبٌ جديد لم تُقرأ القائمة بعده (حتى تُقرأ — فلا يتأخّر الرقم ولا يتضاعف)، أو
  /// لشركةٍ أخرى («إشعارات كلّ شركاتي» — الجرس لطلبات المفتوحة وحدها)، أو والقسم مقفلٌ له.
  static int get inboxDuplicates {
    if (!on) return 0;
    final waiting = {for (final r in gate.value!.items) if (r.isPending) r.id};
    final asOf = _countsAsOf;
    var n = 0;
    for (final x in InboxService.all) {
      if (x.isRead || x.data['type'] != 'renew_request') continue;
      final company = (x.data['company_admin_id'] ?? '').trim();
      if (company.isNotEmpty && company != _adminId) continue;
      final id = int.tryParse(x.data['request_id'] ?? '');
      if ((id != null && waiting.contains(id)) || (asOf != null && !x.receivedAt.isAfter(asOf))) n++;
    }
    return n;
  }

  static Future<void> ensureFresh({bool force = false}) {
    final running = _inflight;
    if (running != null) return running;
    final now = DateTime.now();
    if (!force) {
      final at = _fetchedAt;
      if (at != null && now.difference(at) < ttl) return Future<void>.value();
    }
    final failed = _failedAt;
    if (failed != null && now.difference(failed) < _cooldown) return Future<void>.value();
    final epoch = _epoch;
    late final Future<void> run;
    run = CompanyRoute.runOpen(() => _fetch(epoch, force)).whenComplete(() {
      if (identical(_inflight, run)) _inflight = null;
    });
    _inflight = run;
    return run;
  }

  static Future<void> _fetch(int epoch, bool force) async {
    final now = DateTime.now();
    String? adminId;
    try {
      adminId = (await AuthStorage.readAdminId())?.trim();
    } catch (_) {
      adminId = null;
    }
    if (epoch != _epoch) return;
    var acc = _access;
    final accAt = _accessAt;
    if (force || acc == null || accAt == null || now.difference(accAt) >= _accessTtl) {
      final a = await RenewRequestsApi.access();
      if (epoch != _epoch) return;
      if (a == null) {
        _failedAt = DateTime.now();
        return;
      }
      acc = a;
      _access = a;
      _accessAt = DateTime.now();
    }
    if (!acc.available || !acc.canUse) {
      _fetchedAt = DateTime.now();
      _failedAt = null;
      gate.value = RenewSnapshot(access: acc);
      return;
    }
    final asked = DateTime.now();
    final l = await RenewRequestsApi.list();
    if (epoch != _epoch) return;
    if (l == null) {
      _failedAt = DateTime.now();
      return;
    }
    _fetchedAt = DateTime.now();
    _failedAt = null;
    _countsAsOf = asked;
    _adminId = adminId;
    gate.value = RenewSnapshot(access: acc, items: sortOpenFirst(l.items), pending: l.pending, accepted: l.accepted);
  }

  /// العودة للتطبيق: إشعارٌ وصل والتطبيق بالخلفيّة لم يمرّ هنا — يُقرأ ثانيةً (بمهلةٍ قصيرة لا كلّ رجوع).
  static Future<void> onResume() {
    final at = _fetchedAt;
    if (at != null && DateTime.now().difference(at) < const Duration(seconds: 20)) return Future<void>.value();
    return ensureFresh(force: true);
  }

  /// صندوق الإشعارات تغيّر: إشعار طلب تجديدٍ لم نره ⇒ القائمة من جديد (الجرس يعدّه فوراً).
  static void onInboxChanged() {
    String? id;
    for (final x in InboxService.all) {
      if (x.data['type'] == 'renew_request') {
        id = x.id;
        break;
      }
    }
    if (id == null || id == _lastInboxId) return;
    final first = _lastInboxId == null;
    _lastInboxId = id;
    // أوّل قراءةٍ للصندوق تعرّفنا بآخر إشعارٍ قائم ولا تعني طلباً جديداً — إلّا والحال معروفٌ أصلاً.
    if (first && gate.value == null) return;
    unawaited(ensureFresh(force: true));
  }

  /// تبديل الجلسة: لا يرى المدير التالي طلبات سابقه ولا صوره.
  static void reset() {
    _epoch++;
    _fetchedAt = null;
    _failedAt = null;
    _access = null;
    _accessAt = null;
    _inflight = null;
    _countsAsOf = null;
    _adminId = null;
    gate.value = null;
    RenewRequestsApi.clearImages();
  }

  @visibleForTesting
  static void debugSet(RenewSnapshot? s, {String? adminId}) {
    _epoch++;
    _inflight = null;
    _failedAt = null;
    _access = s?.access;
    _accessAt = s == null ? null : DateTime.now();
    _fetchedAt = s == null ? null : DateTime.now();
    _countsAsOf = _fetchedAt;
    _adminId = adminId;
    gate.value = s;
  }

  @visibleForTesting
  static void debugResetInbox() => _lastInboxId = null;
}

class _RenewGate extends ValueNotifier<RenewSnapshot?> {
  _RenewGate() : super(null);

  @override
  void addListener(VoidCallback listener) {
    super.addListener(listener);
    // بعد البناء لا أثناءه: الجلب يكتب القيمة فيُعيد بناء المستمعين.
    scheduleMicrotask(RenewRequestsState.ensureFresh);
  }
}
