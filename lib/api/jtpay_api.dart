import 'dart:async';
import 'history_page.dart';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../core/platform/app_platform.dart';
import '../core/util/error_text.dart';
import '../services/active_company.dart';
import '../services/auth_storage.dart';
import 'api_client.dart';

/// «شحن من pay الجزيرة» — `/api/v2/jtpay/*` (الخادم 1a66d93، ٣٠ أكتوبر).
///
/// المالك: «مخصص لوكلاء شركه الجزيرة… اليوزر نيم والباسورد موجود عدنا مخزون… الصفحه ال pay هي الي رح
/// تنشحن ومنها يحول المبلغ للساس… نكله تريد تحويل للصفحه نفسها او نخيره لصفحه ثانيه».
///
/// • لوكلاء الجزيرة وحدهم (شركة `jt` لاسلكي، `ftth` فايبر) — الخادم يحكم، والتطبيق لا يسأل غيرهم أصلاً.
/// • التعبئة (زين كاش/بطاقة) من الهاتف وحده: صفحة البوّابة داخل التطبيق، وأوّل انتقالٍ إلى موقع الشحن
///   (`return_host`) هو رجوع الدفع — يُلتقط **ولا يُحمَّل** ويُسلَّم للخادم ([JtpayApi.deliverReturn]).
/// • لا إعادة تلقائيّة لطلب مال: البدء والتحويل مرّةً، والتسليم آمنٌ للتكرار (الخادم يمنع الرابط نفسه مرّتين).
/// • لا يُطبع جسم طلبٍ ولا ردّ: فيها رابط الدفع ورابط الرجوع (رموز البوّابة).

// ═════════════════════════ أدوات القراءة ═════════════════════════

String? _str(Object? v) {
  final s = v?.toString().trim();
  return (s == null || s.isEmpty || s == 'null') ? null : s;
}

num? _num(Object? v) {
  if (v == null || v is bool) return null;
  if (v is num) return v;
  return num.tryParse(v.toString().replaceAll(',', '').trim());
}

int? _int(Object? v) => _num(v)?.round();

Map<String, dynamic> _map(Object? v) => v is Map ? Map<String, dynamic>.from(v) : const <String, dynamic>{};

List<Map<String, dynamic>> _maps(Object? v) => v is List ? [for (final e in v) if (e is Map) Map<String, dynamic>.from(e)] : const [];

DateTime? _date(Object? v) => DateTime.tryParse(_str(v) ?? '')?.toLocal();

void _log(String what, Object e) {
  if (kDebugMode) debugPrint('🔴 [Jtpay] $what: ${e.runtimeType}');
}

/// رموز شركة الجزيرة في التطبيق: `jt` (sas.jt.iq — لاسلكي) و`ftth` (ftth.jt.iq — فايبر الجزيرة، لا المشروع الوطنيّ).
const jtpaySasCodes = {'jt', 'ftth'};

// ═════════════════════════ النماذج ═════════════════════════

/// «مفعّلة لهذا الحساب؟» — للقائمة.
@immutable
class JtpayProbe {
  const JtpayProbe({required this.enabled, this.supported = false, this.reason, this.message, this.section, this.openCount = 0});

  static const off = JtpayProbe(enabled: false);

  final bool enabled;
  final bool supported;

  /// `owner_only` (موظّف) · `paused` (أُوقفت وله عمليّاتٌ مفتوحة).
  final String? reason;
  final String? message;
  final String? section;
  final int openCount;

  bool get ownerOnly => reason == 'owner_only';
  bool get paused => reason == 'paused';

  factory JtpayProbe.fromJson(Map<String, dynamic> j) => JtpayProbe(
        enabled: j['enabled'] == true,
        supported: j['supported'] == true,
        reason: _str(j['reason']),
        message: _str(j['message']),
        section: _str(j['section']),
        openCount: _int(j['open_count']) ?? 0,
      );
}

@immutable
class JtpayMethod {
  const JtpayMethod(this.id, this.label);
  final String id;
  final String label;
}

/// حالة العمليّة للعميل (أسماء الخادم الثابتة).
enum JtpayStatus { processing, awaitingPayment, success, failed, pending, expired, unknown }

JtpayStatus _status(Object? v) => switch (_str(v)) {
      'processing' => JtpayStatus.processing,
      'awaiting_payment' => JtpayStatus.awaitingPayment,
      'success' => JtpayStatus.success,
      'failed' => JtpayStatus.failed,
      'pending' => JtpayStatus.pending,
      'expired' => JtpayStatus.expired,
      _ => JtpayStatus.unknown,
    };

@immutable
class JtpayOp {
  const JtpayOp({
    required this.id,
    required this.kind,
    required this.status,
    this.kindLabel,
    this.method,
    this.methodLabel,
    this.amount,
    this.fee,
    this.total,
    this.target,
    this.statusLabel,
    this.siteStatus,
    this.orderNo,
    this.balanceBefore,
    this.balanceAfter,
    this.sasBefore,
    this.sasAfter,
    this.code,
    this.message,
    this.received = false,
    this.canCheck = false,
    this.createdAt,
    this.completedAt,
  });

  final String id;

  /// `topup` · `to_sas` · `to_page`
  final String kind;
  final JtpayStatus status;
  final String? kindLabel;
  final String? method;
  final String? methodLabel;
  final num? amount;
  final num? fee;
  final num? total;
  final String? target;
  final String? statusLabel;
  final String? siteStatus;
  final String? orderNo;
  final num? balanceBefore;
  final num? balanceAfter;
  final num? sasBefore;
  final num? sasAfter;
  final String? code;
  final String? message;

  /// الخادم استلم رجوع الدفع وصار حامله — تُمحى نسخة الهاتف.
  final bool received;
  final bool canCheck;
  final DateTime? createdAt;
  final DateTime? completedAt;

  bool get isTopup => kind == 'topup';
  bool get isTransfer => kind == 'to_sas' || kind == 'to_page';
  bool get succeeded => status == JtpayStatus.success;

  static JtpayOp? fromJson(Object? raw) {
    final j = _map(raw);
    final id = _str(j['id']);
    final kind = _str(j['kind']);
    if (id == null || kind == null) return null;
    return JtpayOp(
      id: id,
      kind: kind,
      status: _status(j['status']),
      kindLabel: _str(j['kind_label']),
      method: _str(j['method']),
      methodLabel: _str(j['method_label']),
      amount: _num(j['amount']),
      fee: _num(j['fee']),
      total: _num(j['total']),
      target: _str(j['target']),
      statusLabel: _str(j['status_label']),
      siteStatus: _str(j['site_status']),
      orderNo: _str(j['order_no']),
      balanceBefore: _num(j['balance_before']),
      balanceAfter: _num(j['balance_after']),
      sasBefore: _num(j['sas_before']),
      sasAfter: _num(j['sas_after']),
      code: _str(j['code']),
      message: _str(j['message']),
      received: j['received'] == true,
      canCheck: j['can_check'] == true,
      createdAt: _date(j['created_at']),
      completedAt: _date(j['completed_at']),
    );
  }
}

@immutable
class JtpayOverview {
  const JtpayOverview({
    required this.section,
    required this.sectionLabel,
    required this.minAmount,
    required this.maxAmount,
    this.balance,
    this.notice,
    this.quickAmounts = const [],
    this.methods = const [],
    this.feeRate,
    this.open = const [],
    this.recent = const [],
  });

  final String section;
  final String sectionLabel;

  /// رصيد pay — `null` = لم يُقرأ (لا صفر كاذب).
  final num? balance;
  final String? notice;
  final int minAmount;
  final int maxAmount;
  final List<int> quickAmounts;
  final List<JtpayMethod> methods;
  final num? feeRate;
  final List<JtpayOp> open;
  final List<JtpayOp> recent;

  factory JtpayOverview.fromJson(Map<String, dynamic> j) => JtpayOverview(
        section: _str(j['section']) ?? 'wireless',
        sectionLabel: _str(j['section_label']) ?? 'الجزيرة',
        balance: _num(j['balance']),
        notice: _str(j['notice']),
        minAmount: _int(j['min_amount']) ?? 1000,
        maxAmount: _int(j['max_amount']) ?? 5000000,
        quickAmounts: [for (final v in (j['quick_amounts'] is List ? j['quick_amounts'] as List : const [])) if (_int(v) != null) _int(v)!],
        methods: [
          for (final m in _maps(j['methods']))
            if (_str(m['id']) != null) JtpayMethod(_str(m['id'])!, _str(m['label']) ?? _str(m['id'])!),
        ],
        feeRate: _num(j['fee_rate']),
        open: [for (final o in _maps(j['open'])) if (JtpayOp.fromJson(o) != null) JtpayOp.fromJson(o)!],
        recent: [for (final o in _maps(j['recent'])) if (JtpayOp.fromJson(o) != null) JtpayOp.fromJson(o)!],
      );
}

@immutable
class JtpayQuote {
  const JtpayQuote({required this.amount, required this.fee, required this.total});
  final num amount;
  final num fee;
  final num total;
}

@immutable
class JtpayTopupStart {
  const JtpayTopupStart({required this.op, required this.payUrl, required this.returnHost});
  final JtpayOp op;
  final Uri payUrl;

  /// مضيف موقع الشحن — أوّل انتقالٍ إليه رجوع الدفع.
  final String returnHost;
}

/// صفٌّ من سجلّ موقع الشحن (تبويبات «العمليات»).
@immutable
class JtpaySiteRow {
  const JtpaySiteRow({this.no, this.amount, this.status, this.method, this.at, this.op, this.kind, this.party});
  final String? no;
  final num? amount;
  final String? status;
  final String? method;
  final String? at;
  final String? op;
  final String? kind;
  final String? party;

  factory JtpaySiteRow.fromJson(Map<String, dynamic> j) => JtpaySiteRow(
        no: _str(j['no']),
        amount: _num(j['amount']),
        status: _str(j['status']),
        method: _str(j['method']),
        at: _str(j['at']),
        op: _str(j['op']),
        kind: _str(j['kind']),
        party: _str(j['party']),
      );
}

/// ردّ طلب: البيانات، أو رسالةٌ ورمز (ومعها العمليّة إن كانت لها صفّ).
@immutable
class JtpayReply<T> {
  const JtpayReply({this.data, this.op, this.message, this.code, this.status, this.notSent = false, this.noVerdict = false});

  final T? data;
  final JtpayOp? op;
  final String? message;
  final String? code;
  final int? status;

  /// الطلب لم يغادر الهاتف — لا شيء نُفِّذ.
  final bool notSent;

  /// وصل الطلب ولم يصل الحكم (انقطاع) — لا «فشل»: راجع العمليّة قبل الإعادة.
  final bool noVerdict;

  bool get ok => data != null;
}

// ═════════════════════════ الطلبات ═════════════════════════

class JtpayApi {
  JtpayApi._();

  static const _base = '/api/v2/jtpay';

  /// طلبات المال: الخادم يقرأ موقع الشحن قبل النداء وبعده (ثوانٍ) — مهلةٌ أطول من العامّة.
  static Options get _money => Options(receiveTimeout: const Duration(seconds: 90));

  static bool _notSent(Object e) =>
      e is DioException && (e.type == DioExceptionType.connectionError || e.type == DioExceptionType.connectionTimeout);

  /// ردٌّ من خادمنا (JSON بكلامه) داخل استثناء ٤xx — حكمٌ يُقرأ لا عطل.
  static (int, Map<String, dynamic>)? _ourReply(Object e) {
    if (e is! DioException) return null;
    final r = e.response;
    final data = r?.data;
    if (r == null || data is! Map) return null;
    final body = Map<String, dynamic>.from(data);
    if (!body.containsKey('success')) return null;
    return (r.statusCode ?? 0, body);
  }

  static Future<JtpayReply<T>> _run<T>(
    String what,
    Future<Response<Object?>> Function() send,
    T? Function(Map<String, dynamic> body) read, {
    required String fallback,
  }) async {
    int code = 0;
    Map<String, dynamic> body;
    try {
      final r = await send();
      code = r.statusCode ?? 0;
      body = _map(r.data);
    } catch (e) {
      _log(what, e);
      final ours = _ourReply(e);
      if (ours == null) {
        return JtpayReply<T>(
          message: humanError(e, fallback: fallback),
          notSent: _notSent(e),
          noVerdict: !_notSent(e),
        );
      }
      code = ours.$1;
      body = ours.$2;
    }
    final op = JtpayOp.fromJson(body['op']);
    if (body['success'] == true) {
      final data = read(body);
      if (data != null) return JtpayReply<T>(data: data, op: op, status: code);
    }
    return JtpayReply<T>(
      op: op,
      status: code,
      code: _str(body['code']),
      message: _str(body['message']) ?? fallback,
    );
  }

  /// GET options?probe=1 — `null` = تعذّر الوصول (لا يُمسح ما نعرفه).
  static Future<JtpayProbe?> probe() async {
    String? token;
    try {
      token = await AuthStorage.readToken();
    } catch (_) {
      token = null;
    }
    if (token == null || token.isEmpty) return null;
    try {
      final r = await ApiClient.dio.get<Object?>('$_base/options', queryParameters: const {'probe': 1});
      return JtpayProbe.fromJson(_map(r.data));
    } catch (e) {
      _log('options', e);
      final ours = _ourReply(e);
      if (ours == null) return null;
      // ٤٠٤ (خادمٌ أقدم) أو رفضٌ بلا كلام الميزة ⇒ لا شيء يظهر.
      return ours.$2.containsKey('enabled') ? JtpayProbe.fromJson(ours.$2) : JtpayProbe.off;
    }
  }

  static Future<JtpayReply<JtpayOverview>> overview() => _run(
        'overview',
        () => ApiClient.dio.get<Object?>('$_base/overview', options: _money),
        JtpayOverview.fromJson,
        fallback: 'تعذّر جلب رصيد pay',
      );

  static Future<JtpayReply<JtpayQuote>> quote({required int amount, required String method}) => _run(
        'quote',
        () => ApiClient.dio.post<Object?>('$_base/quote', options: _money, data: {'amount': amount, 'method': method}),
        (b) {
          final a = _num(b['amount']);
          final f = _num(b['fee']);
          final t = _num(b['total']);
          return a == null || f == null || t == null ? null : JtpayQuote(amount: a, fee: f, total: t);
        },
        fallback: 'تعذّر حساب الرسوم',
      );

  /// يبدأ التعبئة — **لا يُعاد تلقائيّاً**. بلا رابطٍ لا دفع (لا مال يتحرّك).
  static Future<JtpayReply<JtpayTopupStart>> topup({required int amount, required String method}) => _run(
        'topup',
        () => ApiClient.dio.post<Object?>('$_base/topup', options: _money, data: {'amount': amount, 'method': method}),
        (b) {
          final op = JtpayOp.fromJson(b['op']);
          final pay = Uri.tryParse(_str(b['pay_url']) ?? '');
          final host = _str(b['return_host']);
          // رابطٌ غير مشفَّر أو بلا مضيف رجوع: لا يُفتح — لا التقاط بلا مضيف.
          if (op == null || pay == null || pay.scheme != 'https' || pay.host.isEmpty || host == null) return null;
          return JtpayTopupStart(op: op, payUrl: pay, returnHost: host.toLowerCase());
        },
        fallback: 'تعذّر بدء الدفع — ما انسحب شيء، أعد المحاولة',
      );

  /// يسلّم رابط الرجوع الملتقَط — آمنٌ للتكرار (الخادم لا يسلّم الرابط نفسه مرّتين).
  static Future<JtpayReply<JtpayOp>> deliverReturn({required String opId, required String returnUrl}) => _run(
        'return',
        () => ApiClient.dio.post<Object?>('$_base/topup/$opId/return', options: _money, data: {'return_url': returnUrl}),
        (b) => JtpayOp.fromJson(b['op']),
        fallback: 'تعذّر تسليم الدفع لموقع الشحن — نعيد المحاولة',
      );

  static Future<JtpayReply<JtpayOp>> status(String opId, {bool check = false}) => _run(
        'status',
        () => ApiClient.dio.get<Object?>('$_base/ops/$opId', options: _money, queryParameters: check ? const {'check': 1} : null),
        (b) => JtpayOp.fromJson(b['op']),
        fallback: 'تعذّر جلب حالة العمليّة',
      );

  /// تحويلٌ من رصيد pay: [to] = `sas` (صفحتك نفسها) أو `page` (صفحة باسمها [target]). مرّةً، بلا إعادة.
  static Future<JtpayReply<JtpayOp>> transfer({
    required String to,
    required int amount,
    String? target,
    bool confirmRepeat = false,
  }) =>
      _run(
        'transfer',
        () => ApiClient.dio.post<Object?>('$_base/transfer', options: _money, data: {
          'to': to,
          'amount': amount,
          if (target != null) 'target': target,
          if (confirmRepeat) 'confirm_repeat': true,
        }),
        (b) => JtpayOp.fromJson(b['op']),
        fallback: 'ما تأكّدنا من التحويل — راجع رصيدك وسجلّ العمليّات قبل ما تعيد',
      );

  /// سجلّ عمليّاتنا (`ops`) أو تبويبات الموقع (`recharge` · `credit` · `transfer`).
  static Future<JtpayReply<List<JtpayOp>>> ops() => _run(
        'history',
        () => ApiClient.dio.get<Object?>('$_base/history', queryParameters: const {'tab': 'ops'}),
        (b) => [for (final o in _maps(b['rows'])) if (JtpayOp.fromJson(o) != null) JtpayOp.fromJson(o)!],
        fallback: 'تعذّر جلب السجلّ',
      );

  /// عمليّاتنا بصفحات: `before` = معرّف آخر صفٍّ معروض، `query` = رقم الطلب عند الموقع (الخادم 824b597).
  static Future<JtpayReply<HistoryPage<JtpayOp>>> opsPage({int limit = 10, String? before, String? query}) => _run(
        'history',
        () => ApiClient.dio.get<Object?>('$_base/history', queryParameters: {
          'tab': 'ops',
          'limit': limit,
          if (before != null) 'before': before,
          if (query != null) 'q': query,
        }),
        (b) => HistoryPage(
          [for (final o in _maps(b['rows'])) if (JtpayOp.fromJson(o) case final op?) op],
          hasMore: b['has_more'] == true,
        ),
        fallback: 'تعذّر جلب السجلّ',
      );

  static Future<JtpayReply<List<JtpaySiteRow>>> siteHistory(String tab) => _run(
        'site-history',
        () => ApiClient.dio.get<Object?>('$_base/history', options: _money, queryParameters: {'tab': tab}),
        (b) => [for (final r in _maps(b['rows'])) JtpaySiteRow.fromJson(r)],
        fallback: 'تعذّر جلب سجلّ موقع الشحن',
      );
}

// ═════════════════════════ حالة القائمة ═════════════════════════

/// ما يُرسم في «قوائم أخرى»: يُسأل الخادم مرّةً لكلّ جلسة (٥ دقائق) — ولشركات الجزيرة وحدها.
/// ويندوز: مخفيّة — صفحة الدفع تحتاج WebView يلتقط الرجوع (كشحن رصيد الصفحة).
class JtpayState {
  JtpayState._();

  static final ValueNotifier<JtpayProbe?> gate = _JtpayGate();

  static int _epoch = 0;
  static DateTime? _fetchedAt;
  static DateTime? _failedAt;
  static Future<void>? _inflight;

  static const ttl = Duration(minutes: 5);
  static const _cooldown = Duration(seconds: 30);

  static bool get visible => !AppPlatform.isDesktop && (gate.value?.enabled ?? false);

  /// شركةٌ معروفة ليست الجزيرة ⇒ لا سؤال أصلاً.
  static bool get _foreignCompany {
    final code = ActiveCompany.current?.sasCode.trim().toLowerCase();
    return code != null && code.isNotEmpty && !jtpaySasCodes.contains(code);
  }

  static Future<void> ensureFresh({bool force = false}) {
    if (AppPlatform.isDesktop || _foreignCompany) return Future<void>.value();
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
    run = JtpayApi.probe().then((p) {
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
  static void debugSet(JtpayProbe? p) {
    _epoch++;
    _inflight = null;
    _failedAt = null;
    _fetchedAt = p == null ? null : DateTime.now();
    gate.value = p;
  }
}

class _JtpayGate extends ValueNotifier<JtpayProbe?> {
  _JtpayGate() : super(null);

  @override
  void addListener(VoidCallback listener) {
    super.addListener(listener);
    scheduleMicrotask(JtpayState.ensureFresh);
  }
}
