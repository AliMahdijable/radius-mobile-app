import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../services/auth_storage.dart';
import '../services/permissions_service.dart';
import 'api_client.dart';
import 'company_route.dart';

/// «اليوزرات الفري» (٢٦ نوفمبر — المالك: «وكلاء الشركة تعطيهم يوزرات فري… الوكلاء يبيعونه لمستخدمين عاديين… جدولة شهري ويفصله
/// ويدز له اشعار انه انتهت الخدمة»، ثمّ «تمام كلشي يعني تطبيق وويب»). الخادم server/freeUsers.js — والموقع /v2/free-users بالعقد نفسه:
///   GET  /api/v2/free-users                   ⇒ enabled · family · items · summary · test · reason
///   POST /api/v2/free-users                   {idx, sub_name, sub_phone, price, confirm_not_free}
///   PUT  /api/v2/free-users/:id               {sub_name, sub_phone, price}
///   POST /api/v2/free-users/:id/sell          {months, paymentType: cash|partial-cash|non-cash, partialAmount, confirmRepeat}
///   POST /api/v2/free-users/:id/release       {enable} — 409 FREE_RELEASE_HAS_DEBT والدين قائم
///   POST /api/v2/free-users/:id/test-shorten  {minutes} — صفحات الفحص وحدها
///   GET  /api/v2/free-users/:id/history       ⇒ sales · events
///   GET  /api/v2/free-users/:id/debt          ⇒ balance (سالب = دين؛ null = دين الشركة بالساس)
/// البيع يُسجَّل تفعيلاً (التقارير والتسوية والديون كما هي)، واسم الحامل على سطوره بالتقارير من الخادم (9e6a2c6).

int _int(Object? v) => v is num ? v.round() : int.tryParse('${v ?? ''}') ?? 0;
int? _intOrNull(Object? v) => v is num ? v.round() : int.tryParse('${v ?? ''}');
String? _str(Object? v) {
  final s = v?.toString().trim();
  return s == null || s.isEmpty ? null : s;
}

/// pending (بانتظار البيع) · active (شغّال) · expired (منتهٍ — مطفأ).
enum FreeState { pending, active, expired }

FreeState _state(Object? v) => switch ('$v') {
      'active' => FreeState.active,
      'expired' => FreeState.expired,
      _ => FreeState.pending,
    };

class FreeItem {
  const FreeItem({
    required this.id,
    required this.idx,
    required this.username,
    this.subName,
    this.subPhone,
    required this.price,
    required this.state,
    this.paidUntil,
    this.minutesLeft,
    this.sasEnabled,
    this.lastError,
    this.failCount = 0,
    this.holderFrom,
  });

  final int id;
  final String idx;
  final String username;

  /// اسم المشترك (الحامل) كما يُسجَّل بالقسم — هو العنوان بالتقارير والرسائل.
  final String? subName;
  final String? subPhone;

  /// السعر الشهريّ (د.ع).
  final int price;
  final FreeState state;

  /// «مدفوع لحدّ» بتوقيت بغداد «YYYY-MM-DD HH:MM».
  final String? paidUntil;
  final int? minutesLeft;
  final int? sasEnabled;
  final String? lastError;
  final int failCount;

  /// بداية الحامل الحاليّ (بغداد) — «كشف حساب» يبدأ منها.
  final String? holderFrom;

  /// الاسم الظاهر: المسجَّل، وإلّا اليوزر.
  String get title => subName ?? username;

  static FreeItem? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = _intOrNull(raw['id']);
    final idx = _str(raw['idx']);
    final username = _str(raw['username']);
    if (id == null || idx == null || username == null) return null;
    return FreeItem(
      id: id,
      idx: idx,
      username: username,
      subName: _str(raw['sub_name']),
      subPhone: _str(raw['sub_phone']),
      price: _int(raw['price']),
      state: _state(raw['state']),
      paidUntil: _str(raw['paid_until']),
      minutesLeft: _intOrNull(raw['minutes_left']),
      sasEnabled: _intOrNull(raw['sas_enabled']),
      lastError: _str(raw['last_error']),
      failCount: _int(raw['fail_count']),
      holderFrom: _str(raw['holder_from']),
    );
  }
}

class FreeSummary {
  const FreeSummary({
    this.active = 0,
    this.expired = 0,
    this.pending = 0,
    this.endingSoon = 0,
    this.sales30 = 0,
    this.total30 = 0,
    this.paid30 = 0,
    this.debt30 = 0,
  });

  final int active, expired, pending, endingSoon;

  /// آخر ٣٠ يوماً: عدد البيوع والمجموع والمستلم والدين.
  final int sales30, total30, paid30, debt30;

  static FreeSummary? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final l = raw['last30'];
    final m = l is Map ? l : const {};
    return FreeSummary(
      active: _int(raw['active']),
      expired: _int(raw['expired']),
      pending: _int(raw['pending']),
      endingSoon: _int(raw['ending_soon']),
      sales30: _int(m['sales']),
      total30: _int(m['total']),
      paid30: _int(m['paid']),
      debt30: _int(m['debt']),
    );
  }
}

class FreeList {
  const FreeList({required this.enabled, this.family, this.reason, this.items = const [], this.summary, this.test = false});

  /// المفتاح مفتوحٌ للصفحة والشركة تخدمه (ساس فور، ايرث لنك، المضافة — لا الوطنيّ ولا فايبر اكس).
  final bool enabled;
  final String? family;

  /// لماذا ليس متاحاً (نصّ الخادم).
  final String? reason;
  final List<FreeItem> items;
  final FreeSummary? summary;

  /// صفحة فحص (المفتاح قائمةٌ لا «*») ⇒ «مدّة فحص» بالدقائق.
  final bool test;

  /// «بالساس» / «في ايرث لنك» / «عند الشركة» — كالموقع (freeWhere).
  String get where => switch (family) {
        'sas4' => 'بالساس',
        'earthlink' => 'في ايرث لنك',
        _ => 'عند الشركة',
      };

  static FreeList? fromJson(Object? raw) {
    if (raw is! Map || raw['success'] != true) return null;
    final items = raw['items'];
    return FreeList(
      enabled: raw['enabled'] == true,
      family: _str(raw['family']),
      reason: _str(raw['reason']),
      items: items is List ? items.map(FreeItem.fromJson).whereType<FreeItem>().toList() : const [],
      summary: FreeSummary.fromJson(raw['summary']),
      test: raw['test'] == true,
    );
  }
}

class FreeSale {
  const FreeSale({
    required this.id,
    required this.months,
    required this.total,
    required this.method,
    this.paid = 0,
    this.debt = 0,
    this.paidUntilAfter,
    this.createdAt,
  });

  final int id;
  final int months;
  final int total;

  /// cash · partial · debt
  final String method;
  final int paid;
  final int debt;
  final String? paidUntilAfter;
  final String? createdAt;

  String get methodLabel => switch (method) {
        'partial' => 'جزئي',
        'debt' => 'دين',
        _ => 'نقدي',
      };

  static FreeSale? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = _intOrNull(raw['id']);
    if (id == null) return null;
    return FreeSale(
      id: id,
      months: _int(raw['months']),
      total: _int(raw['total']),
      method: _str(raw['method']) ?? 'cash',
      paid: _int(raw['paid']),
      debt: _int(raw['debt']),
      paidUntilAfter: _str(raw['paid_until_after']),
      createdAt: _str(raw['created_at']),
    );
  }
}

class FreeEvent {
  const FreeEvent({required this.kind, this.createdAt});
  final String kind;
  final String? createdAt;

  /// كالموقع (EVENT_LABEL).
  String get label => switch (kind) {
        'disable' => 'أُطفئ تلقائيّاً',
        'remind' => 'تذكيرٌ قبل الانتهاء',
        'ended_notice' => 'رسالة «انتهت خدمتك»',
        'drift_enabled' => 'شُغّل يدويّاً بعد انتهائه',
        _ => kind,
      };

  static FreeEvent? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final k = _str(raw['kind']);
    return k == null ? null : FreeEvent(kind: k, createdAt: _str(raw['created_at']));
  }
}

/// نتيجة كتابة: نجاحٌ ببيانات الردّ، أو رمز الخادم ورسالته العربيّة (409/422/404…).
class FreeResult {
  const FreeResult({required this.ok, this.code, this.message, this.data = const {}});
  final bool ok;
  final String? code;
  final String? message;
  final Map<String, dynamic> data;
}

/// تاريخ بغداد «YYYY-MM-DD» من «YYYY-MM-DD HH:MM» (بداية الحامل) — null لغير الصالح.
DateTime? freeDay(String? bag) {
  final s = bag?.trim() ?? '';
  if (s.length < 10) return null;
  return DateTime.tryParse(s.substring(0, 10));
}

/// «باقي ٣ يوم» / «باقي ٥ ساعة» / «انتهى منذ ساعتين» — كالموقع (leftText).
String freeLeftText(int? minutes) {
  if (minutes == null) return '—';
  final m = minutes.abs();
  final unit = m < 60 ? '$m دقيقة' : m < 1440 ? '${(m / 60).round()} ساعة' : '${(m / 1440).round()} يوم';
  return minutes >= 0 ? 'باقي $unit' : 'انتهى منذ $unit';
}

class FreeUsersApi {
  FreeUsersApi._();

  static const _base = '/api/v2/free-users';

  @visibleForTesting
  static void Function(String what, Object e)? onLog;
  static void _log(String what, Object e) {
    onLog?.call(what, e);
    if (kDebugMode) debugPrint('⚠️ free $what: $e');
  }

  static Future<FreeList?> list() async {
    try {
      final r = await ApiClient.dio.get<Map<String, dynamic>>(_base);
      return FreeList.fromJson(r.data);
    } catch (e) {
      _log('list', e);
      return null;
    }
  }

  /// لا ردّ من الخادم (مهلة أو انقطاع) أو ٥xx بلا جسمه ⇒ ربّما نُفّذ — للبيع «لم يتأكّد» لا «تعذّر» (٢٦ نوفمبر، d9 عند دمج 197:
  /// كقاعدة ورقة التفعيل [_outcomeUnclear] — الزرّ يُقفل حتى يراجع المدير «مدفوع لحدّ»، ولا تغري ضغطةٌ ثانية ببيعٍ ثانٍ).
  static const noReply = 'NO_REPLY';

  static FreeResult _fail(Object e, String fallback) {
    if (e is DioException) {
      final b = e.response?.data;
      if (b is Map) {
        return FreeResult(ok: false, code: _str(b['code']), message: _str(b['message']) ?? fallback, data: Map<String, dynamic>.from(b));
      }
      final st = e.response?.statusCode ?? 0;
      if (e.response == null || st >= 500) return FreeResult(ok: false, code: noReply, message: fallback);
    }
    return FreeResult(ok: false, message: fallback);
  }

  static Future<FreeResult> _write(String what, Future<Response<Map<String, dynamic>>> Function() call, String fallback) async {
    try {
      final r = await call();
      final d = r.data ?? const <String, dynamic>{};
      if (d['success'] == true) return FreeResult(ok: true, data: Map<String, dynamic>.from(d));
      return FreeResult(ok: false, code: _str(d['code']), message: _str(d['message']) ?? fallback, data: Map<String, dynamic>.from(d));
    } catch (e) {
      _log(what, e);
      return _fail(e, fallback);
    }
  }

  /// تخصيص يوزرٍ فري لمشترك بسعره الشهريّ. [confirmNotFree]: الخادم قال FREE_NOT_FREE_LOOKING والوكيل أكّد أنّه فري.
  static Future<FreeResult> create({
    required String idx,
    required String subName,
    required String subPhone,
    required int price,
    bool confirmNotFree = false,
  }) =>
      _write(
          'create',
          () => ApiClient.dio.post<Map<String, dynamic>>(_base,
              data: {'idx': idx, 'sub_name': subName, 'sub_phone': subPhone, 'price': price, 'confirm_not_free': confirmNotFree}),
          'تعذّر التخصيص');

  static Future<FreeResult> update(int id, {required String subName, required String subPhone, required int price}) => _write(
      'update',
      () => ApiClient.dio.put<Map<String, dynamic>>('$_base/$id', data: {'sub_name': subName, 'sub_phone': subPhone, 'price': price}),
      'تعذّر الحفظ');

  /// [paymentType]: cash · partial-cash · non-cash (كالتفعيل).
  static Future<FreeResult> sell(int id, {required int months, required String paymentType, int? partialAmount, bool confirmRepeat = false}) =>
      _write(
          'sell',
          () => ApiClient.dio.post<Map<String, dynamic>>('$_base/$id/sell', data: {
                'months': months,
                'paymentType': paymentType,
                if (paymentType == 'partial-cash' && partialAmount != null) 'partialAmount': partialAmount,
                'confirmRepeat': confirmRepeat,
              }),
          'تعذّر البيع');

  static Future<FreeResult> release(int id, {bool enable = false}) =>
      _write('release', () => ApiClient.dio.post<Map<String, dynamic>>('$_base/$id/release', data: {'enable': enable}), 'تعذّر الترك');

  static Future<FreeResult> testShorten(int id, int minutes) => _write(
      'shorten', () => ApiClient.dio.post<Map<String, dynamic>>('$_base/$id/test-shorten', data: {'minutes': minutes}), 'تعذّر تقصير المدّة');

  static Future<({List<FreeSale> sales, List<FreeEvent> events})?> history(int id) async {
    try {
      final r = await ApiClient.dio.get<Map<String, dynamic>>('$_base/$id/history');
      final d = r.data;
      if (d == null || d['success'] != true) return null;
      final s = d['sales'];
      final e = d['events'];
      return (
        sales: s is List ? s.map(FreeSale.fromJson).whereType<FreeSale>().toList() : const <FreeSale>[],
        events: e is List ? e.map(FreeEvent.fromJson).whereType<FreeEvent>().toList() : const <FreeEvent>[],
      );
    } catch (e) {
      _log('history', e);
      return null;
    }
  }

  /// دين اليوزر الآن من دفتر شركته (لنافذتي التسديد وإضافة الدين): ok + balance (سالب = دين؛ null = دين الشركة بالساس)، أو رسالة.
  static Future<({bool ok, num? balance, String? message})> debt(int id) async {
    try {
      final r = await ApiClient.dio.get<Map<String, dynamic>>('$_base/$id/debt');
      final d = r.data;
      if (d != null && d['success'] == true) {
        final b = d['balance'];
        return (ok: true, balance: b is num ? b : null, message: null);
      }
      return (ok: false, balance: null, message: _str(d?['message']) ?? 'تعذّرت قراءة الدين الآن');
    } catch (e) {
      _log('debt', e);
      final f = _fail(e, 'تعذّرت قراءة الدين الآن — أعد المحاولة');
      return (ok: false, balance: null, message: f.message);
    }
  }
}

/// القسم بالقائمة: يظهر حين يقول الخادم إنّه مفعّلٌ للصفحة (كالموقع useFreeNav). الاستماع يطلب الحال إن كانت قديمة.
class FreeUsersState {
  FreeUsersState._();

  /// null = لم يُعرف بعد.
  static final ValueNotifier<FreeList?> gate = _FreeGate();

  static int _epoch = 0;
  static DateTime? _fetchedAt;
  static DateTime? _failedAt;
  static Future<void>? _inflight;

  static const ttl = Duration(minutes: 5);
  static const _cooldown = Duration(seconds: 30);

  static bool get on => gate.value?.enabled ?? false;

  static Future<void> ensureFresh({bool force = false}) {
    // موظّفٌ بلا «عرض اليوزرات الفري» لا يسأل (الخادم 403) — كالموقع
    if (Perms.isEmployee && !Perms.has('free.view')) return Future<void>.value();
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
    run = CompanyRoute.runOpen(() => _fetch(epoch)).whenComplete(() {
      if (identical(_inflight, run)) _inflight = null;
    });
    _inflight = run;
    return run;
  }

  static Future<void> _fetch(int epoch) async {
    // بلا جلسة (قبل الدخول، أو اختبارٌ بلا خادم) لا نداء — كمسبار «طلبات التفعيل» و«المبيعات»
    String? token;
    try {
      token = await AuthStorage.readToken();
    } catch (_) {
      token = null;
    }
    if (epoch != _epoch) return;
    if ((token == null || token.isEmpty) && CompanyRoute.currentKey == null) return;
    final l = await FreeUsersApi.list();
    if (epoch != _epoch) return;
    if (l == null) {
      _failedAt = DateTime.now();
      return;
    }
    _fetchedAt = DateTime.now();
    _failedAt = null;
    gate.value = l;
  }

  /// ما رأته الشاشة نفسها (أحدث من الحال) — بلا نداءٍ ثانٍ.
  static void seen(FreeList l) {
    _fetchedAt = DateTime.now();
    _failedAt = null;
    gate.value = l;
  }

  static void reset() {
    _epoch++;
    _fetchedAt = null;
    _failedAt = null;
    _inflight = null;
    gate.value = null;
  }
}

class _FreeGate extends ValueNotifier<FreeList?> {
  _FreeGate() : super(null);

  @override
  void addListener(VoidCallback listener) {
    super.addListener(listener);
    // بعد البناء لا أثناءه: الجلب يكتب القيمة فيُعيد بناء المستمعين.
    scheduleMicrotask(FreeUsersState.ensureFresh);
  }
}
