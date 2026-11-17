import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../core/util/server_time.dart';
import 'api_client.dart';
import 'company_route.dart';
import 'payment_voids_api.dart' show PaymentVoidAction;

/// «إلغاء إضافة دين» و«إلغاء إضافة رصيد» (١٧ نوفمبر ٢٠٢٦ — المالك: «اضافة رصيد او دين بالخطا… لازم نخلي صلاحيه المدير يكدر
/// يسوي هلشي ونضيفها ضمن صلاحيات الموظفين»).
///
/// حركةٌ سُجّلت خطأً تُلغى: يرجع رصيد المشترك كما كان قبلها، ويصحّ الصندوق (رصيدٌ نقداً) أو الصافي (تعويض) أو «الديون الجديدة»
/// (دين). القواعد كلّها في الخادم (`server/opVoids.js`): المبلغ من سطر الحركة لا من هنا، مرّةً واحدة لكلّ حركة، وصلاحيّة الموظّف
/// لنوعها (`subscribers.void_add_debt` / `subscribers.void_add_credit` — لما سجّله هو وحده). الويب يقرأ الشكل نفسه في
/// `client-v2/src/lib/op-voids.ts`.
///
/// ⚠️ كلّ نداءٍ هنا **للشركة المفتوحة صراحةً** ([CompanyRoute.explicit] بلا مفتاح): الخادم لا يوجّه الإلغاء في «كل الشركات».

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

/// نوع الحركة التي تُلغى.
enum OpKind {
  addDebt('add_debt'),
  addCredit('add_credit');

  const OpKind(this.wire);
  final String wire;

  static OpKind? fromWire(Object? v) => switch (v?.toString()) {
        'add_debt' => OpKind.addDebt,
        'add_credit' => OpKind.addCredit,
        _ => null,
      };
}

/// اسم الحركة كما يُقرأ: «إضافة دين» · «إضافة رصيد (نقداً)» · «إضافة رصيد (تعويض)» · «إضافة رصيد».
String opName(OpKind kind, [String? creditKind]) {
  if (kind == OpKind.addDebt) return 'إضافة دين';
  return 'إضافة رصيد${creditKind == 'comp' ? ' (تعويض)' : creditKind == 'cash' ? ' (نقداً)' : ''}';
}

/// اسم السطر المقابل: «إلغاء إضافة دين» · «إلغاء إضافة رصيد».
String opVoidLabel(String? voidKind) => voidKind == 'add_credit' ? 'إلغاء إضافة رصيد' : 'إلغاء إضافة دين';

/// حال حركةٍ في قيد الإلغاء.
class OpVoidItem {
  const OpVoidItem({
    required this.voidId,
    required this.opId,
    required this.kind,
    required this.status,
    required this.amount,
    this.creditKind,
    this.by,
    this.reason,
    this.at,
  });

  final int voidId;

  /// رقم سطر «إضافة الدين/الرصيد» في السجلّ.
  final int opId;
  final OpKind kind;
  final String? creditKind;

  /// `done` ملغاة · `unknown` لم يتأكّد تعديل الرصيد (يحسمه المدير) · `pending`/`restored` قيد الإتمام.
  final String status;
  final num amount;
  final String? by;
  final String? reason;
  final DateTime? at;

  bool get isDone => status == 'done';
  bool get isUnknown => status == 'unknown';

  static OpVoidItem? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final j = Map<String, dynamic>.from(raw);
    final voidId = _intOrNull(j['void_id']);
    final opId = _intOrNull(j['op_id']);
    final kind = OpKind.fromWire(j['kind']);
    if (voidId == null || opId == null || kind == null) return null;
    return OpVoidItem(
      voidId: voidId,
      opId: opId,
      kind: kind,
      creditKind: _str(j['credit_kind']),
      status: j['status']?.toString() ?? 'pending',
      amount: _num(j['amount']),
      by: _str(j['by']),
      reason: _str(j['reason']),
      at: parseServerUtc(_str(j['at'])),
    );
  }
}

/// حال الحركات المعروضة + ما يحقّ لهذا الفاعل لكلّ نوع.
class OpVoidStatus {
  const OpVoidStatus({
    required this.enabled,
    required this.canVoidDebt,
    required this.canVoidCredit,
    required this.ownOnly,
    required this.items,
  });

  /// مطفأة (أو لم تُقرأ): لا زرّ ولا شارة.
  static const off = OpVoidStatus(enabled: false, canVoidDebt: false, canVoidCredit: false, ownOnly: false, items: <int, OpVoidItem>{});

  final bool enabled;
  final bool canVoidDebt;
  final bool canVoidCredit;

  /// موظّف: يلغي ما سجّله هو فقط.
  final bool ownOnly;

  /// بأرقام سطور الحركات.
  final Map<int, OpVoidItem> items;

  OpVoidItem? of(int? opId) => opId == null ? null : items[opId];

  bool canVoid(OpKind kind) => kind == OpKind.addCredit ? canVoidCredit : canVoidDebt;

  /// زرّ السطر [opId]: الملغاة بلا زرّ؛ وما لم يكتمل يُفتح ليُكمَل أو يُحسم؛ موظّفٌ بلا صلاحيّة النوع ⇒ مقفلٌ بمكانه.
  PaymentVoidAction actionFor(int? opId, OpKind? kind) {
    if (!enabled || opId == null || opId <= 0 || kind == null) return PaymentVoidAction.none;
    final v = items[opId];
    if (v != null && v.isDone) return PaymentVoidAction.none;
    if (canVoid(kind)) return PaymentVoidAction.open;
    return v == null ? PaymentVoidAction.locked : PaymentVoidAction.none;
  }

  OpVoidStatus _merge(OpVoidStatus o) => OpVoidStatus(
        enabled: enabled && o.enabled,
        canVoidDebt: canVoidDebt && o.canVoidDebt,
        canVoidCredit: canVoidCredit && o.canVoidCredit,
        ownOnly: ownOnly || o.ownOnly,
        items: {...items, ...o.items},
      );

  static OpVoidStatus? fromJson(Map<String, dynamic> j) {
    if (j['enabled'] is! bool) return null;
    final enabled = j['enabled'] == true;
    final items = <int, OpVoidItem>{};
    final list = j['items'];
    if (list is List) {
      for (final raw in list) {
        final it = OpVoidItem.fromJson(raw);
        if (it != null) items[it.opId] = it;
      }
    }
    return OpVoidStatus(
      enabled: enabled,
      canVoidDebt: enabled && j['can_void_debt'] == true,
      canVoidCredit: enabled && j['can_void_credit'] == true,
      ownOnly: j['own_only'] == true,
      items: items,
    );
  }
}

/// ما يراه المدير قبل التأكيد.
class OpVoidPreview {
  const OpVoidPreview({
    required this.opId,
    required this.kind,
    required this.creditKind,
    required this.amount,
    required this.subscriber,
    required this.at,
    required this.originEmployeeId,
    required this.originUsername,
    required this.balanceDelta,
    required this.newDebtsEffect,
    required this.cashEffect,
    required this.profitEffect,
    required this.canVoid,
    required this.blockedMessage,
    required this.existing,
    required this.settlementNumber,
  });

  final int opId;
  final OpKind? kind;
  final String? creditKind;
  final num? amount;
  final String? subscriber;
  final DateTime? at;

  /// من سجّل الحركة: موظّفٌ (برقمه واسمه) أو المدير (null).
  final int? originEmployeeId;
  final String? originUsername;

  /// ما يتغيّر به رصيد المشترك (موجبٌ = ينقص دينه).
  final num? balanceDelta;

  /// أثر الإلغاء على «الديون الجديدة» والنقد (الصندوق) وصافي الربح.
  final num newDebtsEffect;
  final num cashEffect;
  final num profitEffect;

  final bool canVoid;
  final String? blockedMessage;
  final OpVoidItem? existing;
  final int? settlementNumber;

  static OpVoidPreview? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final j = Map<String, dynamic>.from(raw);
    final op = _map(j['op']);
    final id = _intOrNull(op['id']);
    if (id == null) return null;
    final origin = _map(op['origin']);
    final blocked = _map(j['blocked']);
    final eff = _map(j['effects']);
    final canVoid = j['can_void'] == true;
    return OpVoidPreview(
      opId: id,
      kind: OpKind.fromWire(op['kind']),
      creditKind: _str(op['credit_kind']),
      amount: op['amount'] == null ? null : _num(op['amount']),
      subscriber: _str(op['subscriber']),
      at: parseServerUtc(_str(op['at'])),
      originEmployeeId: _intOrNull(origin['employee_id']),
      originUsername: _str(origin['username']),
      balanceDelta: j['balance_delta'] == null ? null : _num(j['balance_delta']),
      newDebtsEffect: _num(eff['new_debts']),
      cashEffect: _num(eff['cash']),
      profitEffect: _num(eff['profit']),
      canVoid: canVoid,
      blockedMessage: canVoid ? null : _str(blocked['message']),
      existing: OpVoidItem.fromJson(j['void']),
      settlementNumber: _intOrNull(j['settlement_number']),
    );
  }
}

/// نتيجة الإلغاء أو الحسم. [code] `OUTCOME_UNKNOWN` ومعه [voidId]: الساس لم يؤكّد تعديل الرصيد — يُحسم بـ[OpVoidsApi.resolve].
/// [newBalance]: رصيد المشترك بعد الإلغاء إن عُرف (موقَّع: سالبٌ = دين).
typedef OpVoidResult = ({bool ok, bool duplicate, bool corrected, String? message, String? code, int? voidId, num? newBalance});

class OpVoidsApi {
  OpVoidsApi._();

  /// سقف الخادم لأرقام طلب الحال الواحد (STATUS_MAX_IDS).
  static const maxIds = 300;

  /// رقم سطر «إضافة الدين/الرصيد» في سطر كشف المشترك — الخادم يرسله للإضافات اليدويّة التي تُلغى وحدها.
  static int? opIdOf(Map<String, dynamic> txn) {
    final id = _intOrNull(txn['op_activity_id']);
    return id != null && id > 0 ? id : null;
  }

  static OpKind? opKindOf(Map<String, dynamic> txn) => OpKind.fromWire(txn['op_kind']);

  static String? opCreditKindOf(Map<String, dynamic> txn) => _str(txn['op_credit_kind']);

  /// سطر كشفٍ/سجلٍّ هو «إلغاء إضافة دين/رصيد» (الخادم يعلّمه `op_void`).
  static bool isOpVoidRow(Map<String, dynamic> txn) {
    final v = txn['op_void'];
    return v == true || v == 1 || v == '1' || v == 'true';
  }

  /// نوع ما أُلغي في سطر الإلغاء (`add_debt` / `add_credit`).
  static String? voidKindOf(Map<String, dynamic> txn) => _str(txn['void_kind']);

  /// GET /api/v2/op-voids/status?ids= — تعذّرها ⇒ [OpVoidStatus.off] (لا زرّ ولا شارة).
  static Future<OpVoidStatus> status(Iterable<int> ids) async {
    final list = ids.where((n) => n > 0).toSet().toList()..sort((a, b) => b.compareTo(a));
    if (list.isEmpty) return OpVoidStatus.off;
    OpVoidStatus? out;
    for (var i = 0; i < list.length; i += maxIds) {
      final part = list.sublist(i, min(i + maxIds, list.length));
      final r = await _statusOnce(part);
      if (r == null) return OpVoidStatus.off;
      out = out == null ? r : out._merge(r);
      if (!r.enabled) break;
    }
    return out ?? OpVoidStatus.off;
  }

  static Future<OpVoidStatus?> _statusOnce(List<int> ids) async {
    try {
      final r = await ApiClient.dio.get<Map<String, dynamic>>(
        '/api/v2/op-voids/status',
        queryParameters: {'ids': ids.join(',')},
        options: CompanyRoute.explicit(null),
      );
      return OpVoidStatus.fromJson(r.data ?? const {});
    } catch (e) {
      _log('op-voids/status', e);
      return null;
    }
  }

  /// GET /api/v2/op-voids/preview/:id — قراءةٌ بلا كتابة.
  static Future<({OpVoidPreview? data, String? message, String? code})> preview(int opId) async {
    try {
      final r = await ApiClient.dio.get<Map<String, dynamic>>(
        '/api/v2/op-voids/preview/$opId',
        options: CompanyRoute.explicit(null),
      );
      final body = r.data ?? const {};
      final data = body['success'] == true ? OpVoidPreview.fromJson(body['data']) : null;
      if (data == null) {
        return (data: null, message: _str(body['message']) ?? 'تعذّرت قراءة الحركة', code: _str(body['code']));
      }
      return (data: data, message: null, code: null);
    } on DioException catch (e) {
      _log('op-voids/preview', e);
      return (data: null, message: _message(e, 'تعذّرت قراءة الحركة — تحقّق من الاتصال'), code: _code(e));
    } catch (e) {
      _log('op-voids/preview', e);
      return (data: null, message: 'تعذّرت قراءة الحركة', code: null);
    }
  }

  /// POST /api/v2/op-voids — يلغي الحركة [opId]. [expectKind] و[expectAmount] و[expectSubscriber]: ما عُرض في القائمة — الخادم
  /// يطابقها بسطر الحركة قبل أيّ شيء. المبلغ الملغى مبلغ السطر، لا هذا.
  static Future<OpVoidResult> run({
    required int opId,
    required OpKind expectKind,
    required num expectAmount,
    required String expectSubscriber,
    String? reason,
  }) {
    final why = (reason ?? '').trim();
    return _post('/api/v2/op-voids', {
      'op_id': opId,
      'expect_kind': expectKind.wire,
      'expect_amount': expectAmount == expectAmount.roundToDouble() ? expectAmount.round() : expectAmount,
      'expect_subscriber': expectSubscriber,
      if (why.isNotEmpty) 'reason': why,
    }, 'تعذّر الإلغاء');
  }

  /// POST /api/v2/op-voids/:id/resolve — [applied] true «تعدّل الرصيد» · false «ما تعدّل».
  static Future<OpVoidResult> resolve(int voidId, {required bool applied}) =>
      _post('/api/v2/op-voids/$voidId/resolve', {'applied': applied}, 'تعذّر الحسم');

  static Future<OpVoidResult> _post(String path, Map<String, dynamic> data, String fallback) async {
    try {
      final r = await ApiClient.dio.post<Map<String, dynamic>>(path, data: data, options: CompanyRoute.explicit(null));
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
        newBalance: ok && d['new_balance'] != null ? _num(d['new_balance']) : null,
      );
    } on DioException catch (e) {
      _log(path, e);
      // انقطع أو ردّ 5xx: لا نعرف هل نُفّذ — الخادم لا يكرّر (قيدٌ واحد لكلّ حركة)، والحال يُقرأ من جديد قبل أيّ إعادة.
      return (
        ok: false,
        duplicate: false,
        corrected: false,
        message: _message(e, 'انقطع الاتصال — حدّث القائمة لترى حال الحركة قبل أن تعيد'),
        code: _code(e) ?? 'NETWORK',
        voidId: null,
        newBalance: null,
      );
    } catch (e) {
      _log(path, e);
      return (ok: false, duplicate: false, corrected: false, message: fallback, code: null, voidId: null, newBalance: null);
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
