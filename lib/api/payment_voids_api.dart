import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../core/util/server_time.dart';
import 'api_client.dart';
import 'company_route.dart';

/// «إلغاء تسديد» (١١ نوفمبر ٢٠٢٦ — المالك: «مهمّة لأنّ هسه سبّبت لي مشاكل» + «أعطيها صلاحيّة للمدير يخصّصها للموظّف أو لا»).
///
/// تسديد دينٍ سُجّل خطأً يُلغى: يرجع دين المشترك وينقص المبلغ من الصندوق والتقرير — من حساب من استلمه. القواعد كلّها في الخادم
/// (`server/paymentVoids.js`): المبلغ من سطر التسديد لا من هنا، مرّةً واحدة لكلّ تسديد، وصلاحيّة الموظّف
/// (`subscribers.void_payment` — لتسديداته هو فقط). هذا الملفّ الأنواع ونداءاتها، والويب يقرأ الشكل نفسه في
/// `client-v2/src/lib/payment-voids.ts`.
///
/// ⚠️ كلّ نداءٍ هنا **للشركة المفتوحة صراحةً** ([CompanyRoute.explicit] بلا مفتاح): الخادم لا يوجّه الإلغاء في «كل الشركات»،
/// فالشاشات لا تعرض الزرّ لصفٍّ من شركةٍ أخرى — ولو طُلب من داخل قسمٍ موجَّه لما ذهب لغير المفتوحة.

num _num(Object? v) => v is num ? v : num.tryParse(v?.toString() ?? '') ?? 0;

int? _intOrNull(Object? v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString());
}

String? _str(Object? v) {
  final s = v?.toString();
  return (s == null || s.isEmpty) ? null : s;
}

Map<String, dynamic> _map(Object? v) => v is Map ? Map<String, dynamic>.from(v) : const <String, dynamic>{};

/// حال تسديدٍ في قيد الإلغاء.
class PaymentVoidItem {
  const PaymentVoidItem({
    required this.voidId,
    required this.paymentId,
    required this.mode,
    required this.status,
    required this.amount,
    this.by,
    this.reason,
    this.at,
  });

  final int voidId;

  /// رقم سطر التسديد في السجلّ.
  final int paymentId;

  /// `restore` (رجع الدين) · `link` (الدين أُعيد سابقاً بإضافة دينٍ يدويّة).
  final String mode;

  /// `done` ملغى · `unknown` لم يتأكّد إرجاع الدين (يحسمه المدير) · `pending`/`restored` قيد الإتمام.
  final String status;
  final num amount;
  final String? by;
  final String? reason;
  final DateTime? at;

  bool get isDone => status == 'done';
  bool get isUnknown => status == 'unknown';

  static PaymentVoidItem? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final j = Map<String, dynamic>.from(raw);
    final voidId = _intOrNull(j['void_id']);
    final paymentId = _intOrNull(j['payment_id']);
    if (voidId == null || paymentId == null) return null;
    return PaymentVoidItem(
      voidId: voidId,
      paymentId: paymentId,
      mode: j['mode']?.toString() ?? 'restore',
      status: j['status']?.toString() ?? 'pending',
      amount: _num(j['amount']),
      by: _str(j['by']),
      reason: _str(j['reason']),
      at: parseServerUtc(_str(j['at'])),
    );
  }
}

/// ما يُعرض على سطر التسديد.
enum PaymentVoidAction {
  /// لا زرّ: الميزة مطفأةٌ للصفحة، أو السطر بلا رقم تسديد، أو التسديد ملغى.
  none,

  /// الزرّ يفتح نافذة الإلغاء (أو إكمال/حسم إلغاءٍ لم يكتمل).
  open,

  /// موظّفٌ بلا الصلاحيّة: الزرّ بمكانه مقفلاً «لا صلاحيّة» (لا إخفاء).
  locked,
}

/// حال التسديدات المعروضة + ما يحقّ لهذا الفاعل.
class PaymentVoidStatus {
  const PaymentVoidStatus({
    required this.enabled,
    required this.canVoid,
    required this.canLink,
    required this.ownOnly,
    required this.items,
  });

  /// مطفأة (أو لم تُقرأ): لا زرّ ولا شارة.
  static const off = PaymentVoidStatus(
    enabled: false,
    canVoid: false,
    canLink: false,
    ownOnly: false,
    items: <int, PaymentVoidItem>{},
  );

  /// الميزة مفتوحةٌ لهذه الصفحة.
  final bool enabled;

  /// هذا الفاعل يلغي (صاحب الصفحة، أو موظّفٌ بصلاحيّته).
  final bool canVoid;

  /// ربط التسديد بإضافة دينٍ سابقة — لصاحب الصفحة وحده.
  final bool canLink;

  /// موظّف: يلغي تسديداته هو فقط.
  final bool ownOnly;

  /// بأرقام سطور التسديد.
  final Map<int, PaymentVoidItem> items;

  PaymentVoidItem? of(int? paymentId) => paymentId == null ? null : items[paymentId];

  /// زرّ السطر [paymentId]: الملغى بلا زرّ؛ وما لم يكتمل (بانتظار حسم، أو عمليّةٌ انقطعت) يُفتح ليُكمَل أو يُحسم.
  PaymentVoidAction actionFor(int? paymentId) {
    if (!enabled || paymentId == null || paymentId <= 0) return PaymentVoidAction.none;
    final v = items[paymentId];
    if (v != null && v.isDone) return PaymentVoidAction.none;
    if (canVoid) return PaymentVoidAction.open;
    return v == null ? PaymentVoidAction.locked : PaymentVoidAction.none;
  }

  PaymentVoidStatus _merge(PaymentVoidStatus o) => PaymentVoidStatus(
        enabled: enabled && o.enabled,
        canVoid: canVoid && o.canVoid,
        canLink: canLink && o.canLink,
        ownOnly: ownOnly || o.ownOnly,
        items: {...items, ...o.items},
      );

  static PaymentVoidStatus? fromJson(Map<String, dynamic> j) {
    // ردٌّ بلا `enabled` منطقيّة ليس حالاً (رفضٌ أو خادمٌ أقدم) ⇒ لا شيء.
    if (j['enabled'] is! bool) return null;
    final enabled = j['enabled'] == true;
    final items = <int, PaymentVoidItem>{};
    final list = j['items'];
    if (list is List) {
      for (final raw in list) {
        final it = PaymentVoidItem.fromJson(raw);
        if (it != null) items[it.paymentId] = it;
      }
    }
    return PaymentVoidStatus(
      enabled: enabled,
      canVoid: enabled && j['can_void'] == true,
      canLink: enabled && j['can_link'] == true,
      ownOnly: j['own_only'] == true,
      items: items,
    );
  }
}

/// إضافة دينٍ يدويّة بالمبلغ نفسه بعد التسديد — قد تكون هي إرجاع دينه.
class PaymentVoidCandidate {
  const PaymentVoidCandidate({required this.id, required this.amount, this.at, this.by, this.comment});
  final int id;
  final num amount;
  final DateTime? at;
  final String? by;
  final String? comment;

  static PaymentVoidCandidate? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = _intOrNull(raw['id']);
    if (id == null) return null;
    return PaymentVoidCandidate(
      id: id,
      amount: _num(raw['amount']),
      at: parseServerUtc(_str(raw['at'])),
      by: _str(raw['by']),
      comment: _str(raw['comment']),
    );
  }
}

/// ما يراه المدير قبل التأكيد.
class PaymentVoidPreview {
  const PaymentVoidPreview({
    required this.paymentId,
    required this.amount,
    required this.subscriber,
    required this.at,
    required this.collectorEmployeeId,
    required this.collectorUsername,
    required this.canVoid,
    required this.blockedMessage,
    required this.existing,
    required this.settlementNumber,
    required this.candidates,
    required this.canLink,
  });

  final int paymentId;

  /// مبلغ التسديد من سطره — null إن لم يكن السطر تسديداً يُلغى.
  final num? amount;
  final String? subscriber;
  final DateTime? at;

  /// من استلم التسديد: موظّفٌ (برقمه واسمه) أو المدير (null).
  final int? collectorEmployeeId;
  final String? collectorUsername;

  final bool canVoid;

  /// سبب المنع بنصّ الخادم — حين [canVoid] false.
  final String? blockedMessage;

  /// قيد إلغاءٍ قائم لهذا التسديد (ملغى، بانتظار حسم، أو لم يكتمل).
  final PaymentVoidItem? existing;

  /// التسديد ضمن تسويةٍ محفوظة بهذا الرقم — الإلغاء يقع في الحساب الحاليّ.
  final int? settlementNumber;
  final List<PaymentVoidCandidate> candidates;
  final bool canLink;

  static PaymentVoidPreview? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final j = Map<String, dynamic>.from(raw);
    final pay = _map(j['payment']);
    final id = _intOrNull(pay['id']);
    if (id == null) return null;
    final collector = _map(pay['collector']);
    final blocked = _map(j['blocked']);
    final cands = j['candidates'];
    final canVoid = j['can_void'] == true;
    return PaymentVoidPreview(
      paymentId: id,
      amount: pay['amount'] == null ? null : _num(pay['amount']),
      subscriber: _str(pay['subscriber']),
      at: parseServerUtc(_str(pay['at'])),
      collectorEmployeeId: _intOrNull(collector['employee_id']),
      collectorUsername: _str(collector['username']),
      canVoid: canVoid,
      blockedMessage: canVoid ? null : _str(blocked['message']),
      existing: PaymentVoidItem.fromJson(j['void']),
      settlementNumber: _intOrNull(j['settlement_number']),
      candidates: cands is List
          ? cands.map(PaymentVoidCandidate.fromJson).whereType<PaymentVoidCandidate>().toList()
          : const <PaymentVoidCandidate>[],
      canLink: j['can_link'] == true,
    );
  }
}

/// نتيجة الإلغاء أو الحسم. [code] `OUTCOME_UNKNOWN` ومعه [voidId]: الساس لم يؤكّد إرجاع الدين — يُحسم بـ[PaymentVoidsApi.resolve].
/// [sent] false: الطلب لم يصل الخادم بيقين (أو لم نعرف) — يُقرأ الحال من جديد قبل أيّ إعادة.
typedef PaymentVoidResult = ({bool ok, bool duplicate, bool corrected, String? message, String? code, int? voidId});

class PaymentVoidsApi {
  PaymentVoidsApi._();

  /// سقف الخادم لأرقام طلب الحال الواحد (STATUS_MAX_IDS).
  static const maxIds = 300;

  /// سطر كشفٍ/سجلٍّ هو «إلغاء تسديد»: تسديدٌ بمبلغٍ سالب، أو معلَّمٌ `pay_void` (دفتر ايرث لنك يعرضه «إضافة دين» بمبلغه).
  static bool isVoidRow(Map<String, dynamic> txn) {
    if (txn['pay_void'] == true) return true;
    final t = (txn['action_type'] ?? '').toString().toUpperCase();
    if (t != 'BALANCE_DEDUCT' && t != 'DEBT_PAY' && t != 'PAYMENT_ADD') return false;
    final raw = txn['amount'];
    final n = raw is num ? raw : num.tryParse((raw ?? '').toString().replaceAll(RegExp(r'[^0-9.\-]'), ''));
    return n != null && n < 0;
  }

  static final RegExp _marker = RegExp(r'\s*\[pv:\d+\]');

  /// وصف حركةٍ بلا وسم الإلغاء الداخليّ (`[pv:رقم]` — يُكتب في ملاحظة حركة الدفتر ليُعرف بها الإرجاع إن ضاع ردّه؛ كشف دفتر
  /// ايرث لنك يعرض الملاحظة كما هي). للعرض وحده.
  static String cleanNote(String s) => s.contains('[pv:') ? s.replaceAll(_marker, '').trim() : s;

  /// رقم سطر التسديد في سطر كشف المشترك — الخادم يرسله لسطور التسديد وحدها.
  static int? paymentIdOf(Map<String, dynamic> txn) {
    final id = _intOrNull(txn['payment_activity_id']);
    return id != null && id > 0 ? id : null;
  }

  /// GET /api/v2/payment-voids/status?ids= — حال التسديدات المعروضة. تعذّرها ⇒ [PaymentVoidStatus.off] (لا زرّ ولا شارة).
  /// الأحدث أوّلاً، وما زاد على سقف الخادم بطلبٍ ثانٍ.
  static Future<PaymentVoidStatus> status(Iterable<int> ids) async {
    final list = ids.where((n) => n > 0).toSet().toList()..sort((a, b) => b.compareTo(a));
    if (list.isEmpty) return PaymentVoidStatus.off;
    PaymentVoidStatus? out;
    for (var i = 0; i < list.length; i += maxIds) {
      final part = list.sublist(i, min(i + maxIds, list.length));
      final r = await _statusOnce(part);
      if (r == null) return PaymentVoidStatus.off;
      out = out == null ? r : out._merge(r);
      if (!r.enabled) break;
    }
    return out ?? PaymentVoidStatus.off;
  }

  static Future<PaymentVoidStatus?> _statusOnce(List<int> ids) async {
    try {
      final r = await ApiClient.dio.get<Map<String, dynamic>>(
        '/api/v2/payment-voids/status',
        queryParameters: {'ids': ids.join(',')},
        options: CompanyRoute.explicit(null),
      );
      return PaymentVoidStatus.fromJson(r.data ?? const {});
    } on DioException catch (e) {
      _log('payment-voids/status', e);
      return null;
    } catch (e) {
      _log('payment-voids/status', e);
      return null;
    }
  }

  /// GET /api/v2/payment-voids/preview/:id — قراءةٌ بلا كتابة.
  static Future<({PaymentVoidPreview? data, String? message, String? code})> preview(int paymentId) async {
    try {
      final r = await ApiClient.dio.get<Map<String, dynamic>>(
        '/api/v2/payment-voids/preview/$paymentId',
        options: CompanyRoute.explicit(null),
      );
      final body = r.data ?? const {};
      // ⚠️ الرفض يصل ردّاً لا رميةً (`validateStatus: s < 500`) — رسالة الخادم العربيّة في الجسم.
      final data = body['success'] == true ? PaymentVoidPreview.fromJson(body['data']) : null;
      if (data == null) {
        return (
          data: null,
          message: _str(body['message']) ?? 'تعذّرت قراءة التسديد',
          code: _str(body['code']),
        );
      }
      return (data: data, message: null, code: null);
    } on DioException catch (e) {
      _log('payment-voids/preview', e);
      return (data: null, message: _message(e, 'تعذّرت قراءة التسديد — تحقّق من الاتصال'), code: _code(e));
    } catch (e) {
      _log('payment-voids/preview', e);
      return (data: null, message: 'تعذّرت قراءة التسديد', code: null);
    }
  }

  /// POST /api/v2/payment-voids — يلغي التسديد [paymentId].
  ///
  /// [expectAmount] و[expectSubscriber]: ما عُرض في القائمة — الخادم يطابقهما بسطر التسديد قبل أيّ شيء (رقمٌ من قائمةٍ أخرى أو
  /// صفحةٌ قديمة لا يلغيان تسديداً غير المقصود). المبلغ الملغى مبلغ السطر، لا هذا.
  /// [linkAddId]: إضافة الدين التي كانت إرجاعاً لهذا التسديد ⇒ الربط (دين المشترك لا يتغيّر)؛ null ⇒ إرجاع الدين الآن.
  static Future<PaymentVoidResult> run({
    required int paymentId,
    required num expectAmount,
    required String expectSubscriber,
    int? linkAddId,
    String? reason,
  }) {
    final why = (reason ?? '').trim();
    return _post('/api/v2/payment-voids', {
      'payment_id': paymentId,
      'expect_amount': expectAmount == expectAmount.roundToDouble() ? expectAmount.round() : expectAmount,
      'expect_subscriber': expectSubscriber,
      if (linkAddId != null) ...{'mode': 'link', 'add_id': linkAddId},
      if (why.isNotEmpty) 'reason': why,
    }, 'تعذّر إلغاء التسديد');
  }

  /// POST /api/v2/payment-voids/:id/resolve — حسم إلغاءٍ لم تتأكّد نتيجته: [applied] true «الدين رجع» (يُسجَّل الإلغاء بلا
  /// إرجاعٍ ثانٍ) · false «ما رجع» (يُسقط القيد والتسديد كما كان).
  static Future<PaymentVoidResult> resolve(int voidId, {required bool applied}) =>
      _post('/api/v2/payment-voids/$voidId/resolve', {'applied': applied}, 'تعذّر الحسم');

  static Future<PaymentVoidResult> _post(String path, Map<String, dynamic> data, String fallback) async {
    try {
      final r = await ApiClient.dio.post<Map<String, dynamic>>(
        path,
        data: data,
        options: CompanyRoute.explicit(null),
      );
      final body = r.data ?? const {};
      final ok = body['success'] == true;
      final d = _map(body['data']);
      return (
        ok: ok,
        duplicate: ok && body['duplicate'] == true,
        corrected: ok && d['corrected'] == true,
        message: ok ? null : (_str(body['message']) ?? fallback),
        code: ok ? null : _str(body['code']),
        voidId: _intOrNull(ok ? d['void_id'] : body['void_id']),
      );
    } on DioException catch (e) {
      _log(path, e);
      // انقطع أو ردّ 5xx: لا نعرف هل نُفّذ — الخادم لا يكرّر (قيدٌ واحد لكلّ تسديد)، والحال يُقرأ من جديد قبل أيّ إعادة.
      return (
        ok: false,
        duplicate: false,
        corrected: false,
        message: _message(e, 'انقطع الاتصال — حدّث القائمة لترى حال التسديد قبل أن تعيد'),
        code: _code(e) ?? 'NETWORK',
        voidId: null,
      );
    } catch (e) {
      _log(path, e);
      return (ok: false, duplicate: false, corrected: false, message: fallback, code: null, voidId: null);
    }
  }

  static String _message(DioException e, String fallback) {
    final b = e.response?.data;
    final m = b is Map ? b['message']?.toString() : null;
    return (m == null || m.isEmpty) ? fallback : m;
  }

  static String? _code(DioException e) {
    final b = e.response?.data;
    return b is Map ? b['code']?.toString() : null;
  }

  static void _log(String endpoint, Object err) {
    if (kReleaseMode) return;
    if (err is DioException) {
      debugPrint('🔴 $endpoint: status=${err.response?.statusCode} body=${err.response?.data}');
    } else {
      debugPrint('🔴 $endpoint: $err');
    }
  }
}
