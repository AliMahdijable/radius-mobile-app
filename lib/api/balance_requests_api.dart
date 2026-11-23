import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../services/auth_storage.dart';
import '../services/transfer_pay.dart';
import 'api_client.dart';
import 'company_route.dart';

/// «طلب رصيد من مديرك» — المرحلة ٢ (المالك ٢٣ نوفمبر: «النظام يكشف المدراء الفرعيين، اللي فوقهم مدير عندنا مسجل… يسوي طلب رصيد
/// من المدير الاعلى… يوصل اشعار… يدز له صورة حوالة»، و«قسم خاص به… اذا ماكو مدير فرعي ينختفي»). الخادم server/balanceRequests.js:
///   الفرعيّ: GET /api/v2/balance-requests/me · POST /api/v2/balance-requests · POST …/:id/cancel
///   الأعلى: GET …/incoming[/count] · GET …/:id/image · POST …/:id/reject · POST …/:id/resolve
///   «قبول وشحن» = نافذة «شحن رصيد» نفسها ومعها balance_request_id (ManagersApi.deposit).
/// كلّ النداءات للشركة المفتوحة وحدها (CompanyRoute.runOpen) — لا يُوجَّه القسم من «كل الشركات».

int? _int(Object? v) => v is int ? v : (v is num ? v.round() : int.tryParse('${v ?? ''}'.split('.').first));
String? _str(Object? v) {
  final s = v?.toString().trim();
  return s == null || s.isEmpty ? null : s;
}

DateTime? _date(Object? v) => v is String ? DateTime.tryParse(v)?.toLocal() : null;

@immutable
class BalanceReqParent {
  const BalanceReqParent({required this.page, this.username, this.network, this.phone, this.whatsapp});
  final String page;
  final String? username;

  /// اسم شبكته كما يعرضه لمشتركيه («شبكة النور») — admin_branding.
  final String? network;
  final String? phone;
  final String? whatsapp;

  /// الاسم الظاهر: اسم شبكته، وإلّا يوزره.
  String get title => network ?? username ?? 'مديرك';

  static BalanceReqParent? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final page = _str(raw['page']);
    if (page == null) return null;
    return BalanceReqParent(
      page: page,
      username: _str(raw['username']),
      network: _str(raw['network']),
      phone: _str(raw['phone']),
      whatsapp: _str(raw['whatsapp']),
    );
  }
}

@immutable
class BalanceReqPay {
  const BalanceReqPay({this.zaincash, this.master, this.note});
  final String? zaincash;
  final String? master;
  final String? note;
  bool get any => zaincash != null || master != null;

  static BalanceReqPay fromJson(Object? raw) => raw is Map
      ? BalanceReqPay(zaincash: _str(raw['zaincash']), master: _str(raw['master']), note: _str(raw['note']))
      : const BalanceReqPay();
}

@immutable
class BalanceReqDone {
  const BalanceReqDone({this.amount, this.isLoan = false, this.paidVia, this.viaName, this.balanceBefore, this.balanceAfter});
  final int? amount;
  final bool isLoan;
  final String? paidVia;
  final String? viaName;
  final int? balanceBefore;
  final int? balanceAfter;

  /// «زين كاش» · «ماستر» · «كاش» · اسم «أخرى» · «آجل».
  String get viaLabel => isLoan ? 'آجل' : balanceViaLabel(paidVia, viaName);

  static BalanceReqDone? fromJson(Object? raw) => raw is Map
      ? BalanceReqDone(
          amount: _int(raw['amount']),
          isLoan: raw['is_loan'] == true,
          paidVia: _str(raw['paid_via']),
          viaName: _str(raw['via_name']),
          balanceBefore: _int(raw['balance_before']),
          balanceAfter: _int(raw['balance_after']),
        )
      : null;
}

String balanceViaLabel(String? via, String? name) => switch (via) {
      'cash' => 'كاش',
      'zaincash' => 'زين كاش',
      'master' => 'ماستر',
      'other' => name ?? 'أخرى',
      _ => '',
    };

@immutable
class BalanceReqAiLine {
  const BalanceReqAiLine(this.level, this.text);
  final String level; // warn · ok · info
  final String text;
}

/// «قراءة الوصل» (receiptAi على الخادم): تنبيهٌ للأعلى لا رفض.
@immutable
class BalanceReqAi {
  const BalanceReqAi({required this.status, this.verdict, this.level, this.amount, this.lines = const []});
  final String status; // pending · done · unavailable
  final String? verdict; // match · less · more · duplicate · not_receipt · unknown
  final String? level;
  final int? amount;
  final List<BalanceReqAiLine> lines;

  static BalanceReqAi? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final st = _str(raw['status']);
    if (st == null) return null;
    return BalanceReqAi(
      status: st,
      verdict: _str(raw['verdict']),
      level: _str(raw['level']),
      amount: _int(raw['amount']),
      lines: [
        for (final l in (raw['lines'] is List ? raw['lines'] as List : const []))
          if (l is Map && _str(l['text']) != null) BalanceReqAiLine(_str(l['level']) ?? 'info', _str(l['text'])!),
      ],
    );
  }
}

@immutable
class BalanceReqSub {
  const BalanceReqSub({required this.page, required this.sasId, this.username, this.name});
  final String page;
  final String sasId;
  final String? username;
  final String? name;
  String get title => name ?? username ?? '#$sasId';
}

@immutable
class BalanceRequest {
  const BalanceRequest({
    required this.id,
    required this.status,
    required this.amount,
    required this.payMethod,
    this.createdAt,
    this.payName,
    this.methodLabel = '',
    this.note,
    this.hasImage = false,
    this.imageLive = false,
    this.decidedAt,
    this.rejectReason,
    this.done,
    this.sub,
    this.ai,
    this.decidedBy,
    this.unverified = false,
    this.attempt,
  });

  final int id;
  final String status; // pending · processing · done · rejected · cancelled · expired
  final DateTime? createdAt;
  final int amount;
  final String payMethod; // zaincash · master · other · cash · loan
  final String? payName;
  final String methodLabel;
  final String? note;
  final bool hasImage;
  final bool imageLive;
  final DateTime? decidedAt;
  final String? rejectReason;
  final BalanceReqDone? done;
  // للأعلى وحده
  final BalanceReqSub? sub;
  final BalanceReqAi? ai;
  final String? decidedBy;
  final bool unverified;
  final BalanceReqDone? attempt;

  bool get isPending => status == 'pending';
  bool get isProcessing => status == 'processing';
  bool get isOpen => isPending || isProcessing;
  bool get isTransfer => payMethod == 'zaincash' || payMethod == 'master' || payMethod == 'other';

  /// طريقة الاستلام المقترحة لنافذة الشحن: ما اختاره هو بالطلب (والكاش والآجل كاش).
  PaidVia get suggestedVia => switch (payMethod) {
        'zaincash' => PaidVia.zaincash,
        'master' => PaidVia.master,
        'other' => PaidVia('other', payName ?? ''),
        _ => PaidVia.cash,
      };

  static BalanceRequest? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = _int(raw['id']);
    final amount = _int(raw['amount']);
    final method = _str(raw['pay_method']);
    if (id == null || amount == null || method == null) return null;
    final sub = raw['sub'];
    final attempt = raw['attempt'];
    return BalanceRequest(
      id: id,
      status: _str(raw['status']) ?? 'pending',
      createdAt: _date(raw['created_at']),
      amount: amount,
      payMethod: method,
      payName: _str(raw['pay_name']),
      methodLabel: _str(raw['method_label']) ?? '',
      note: _str(raw['note']),
      hasImage: raw['has_image'] == true,
      imageLive: raw['image_live'] == true,
      decidedAt: _date(raw['decided_at']),
      rejectReason: _str(raw['reject_reason']),
      done: BalanceReqDone.fromJson(raw['done']),
      sub: sub is Map && _str(sub['page']) != null
          ? BalanceReqSub(page: _str(sub['page'])!, sasId: _str(sub['sas_id']) ?? '', username: _str(sub['username']), name: _str(sub['name']))
          : null,
      ai: BalanceReqAi.fromJson(raw['ai']),
      decidedBy: _str(raw['decided_by']),
      unverified: raw['unverified'] == true,
      attempt: attempt is Map
          ? BalanceReqDone(
              amount: _int(attempt['amount']),
              isLoan: attempt['is_loan'] == true,
              paidVia: _str(attempt['paid_via']),
              viaName: _str(attempt['via_name']))
          : null,
    );
  }
}

/// قسم الفرعيّ كما يقوله الخادم. [enabled] false ⇒ لا بطاقة أصلاً (ليس مديراً فرعيّاً مديره عندنا، أو المفتاح مطفأ).
@immutable
class BalanceReqMe {
  const BalanceReqMe({
    required this.enabled,
    this.canRequest = false,
    this.parent,
    this.pay = const BalanceReqPay(),
    this.pending = 0,
    this.lastDepositAt,
    this.lastDepositAmount,
    this.lastDepositLoan = false,
    this.requests = const [],
  });

  final bool enabled;

  /// المدير وحده يطلب — الموظّف يرى البطاقة مقفلةً بمكانها.
  final bool canRequest;
  final BalanceReqParent? parent;
  final BalanceReqPay pay;
  final int pending;
  final DateTime? lastDepositAt;
  final int? lastDepositAmount;
  final bool lastDepositLoan;
  final List<BalanceRequest> requests;

  static const off = BalanceReqMe(enabled: false);

  static BalanceReqMe fromJson(Object? raw) {
    if (raw is! Map || raw['enabled'] != true) return off;
    final parent = BalanceReqParent.fromJson(raw['parent']);
    if (parent == null) return off;
    final last = raw['last_deposit'];
    return BalanceReqMe(
      enabled: true,
      canRequest: raw['can_request'] == true,
      parent: parent,
      pay: BalanceReqPay.fromJson(raw['pay']),
      pending: _int(raw['pending']) ?? 0,
      lastDepositAt: last is Map ? _date(last['at']) : null,
      lastDepositAmount: last is Map ? _int(last['amount']) : null,
      lastDepositLoan: last is Map && last['is_loan'] == true,
      requests: [
        for (final r in (raw['requests'] is List ? raw['requests'] as List : const []))
          if (BalanceRequest.fromJson(r) case final x?) x,
      ],
    );
  }
}

typedef BalanceReqResult = ({bool ok, String? message, String? code, BalanceRequest? request});

@immutable
class IncomingPage {
  const IncomingPage({required this.items, required this.total, required this.pending, required this.processing, required this.done, required this.rejected});
  final List<BalanceRequest> items;
  final int total;
  final int pending;
  final int processing;
  final int done;
  final int rejected;
}

abstract final class BalanceRequestsApi {
  static const base = '/api/v2/balance-requests';

  static String? _msg(Object? body) => body is Map ? _str(body['message']) : null;
  static String? _code(Object? body) => body is Map ? _str(body['code']) : null;

  /// قسم الفرعيّ. null = تعذّر (شبكة) — لا يُخمَّن «مطفأ».
  static Future<BalanceReqMe?> me() async {
    try {
      final r = await CompanyRoute.runOpen(() => ApiClient.dio.get<Object?>('$base/me'));
      final b = r.data;
      if (b is! Map) return null;
      if (b['success'] != true) return (r.statusCode ?? 0) >= 400 && (r.statusCode ?? 0) < 500 && r.statusCode != 401 ? BalanceReqMe.off : null;
      return BalanceReqMe.fromJson(b['data']);
    } catch (_) {
      return null;
    }
  }

  /// طلبٌ جديد. [imageJpeg] للحوالة وحدها (مضغوطةٌ بلا EXIF). [clientRef] ثابتٌ لإعادة الإرسال (الخادم يعيد الطلب نفسه).
  static Future<BalanceReqResult> create({
    required String clientRef,
    required int amount,
    required String payMethod,
    String? payName,
    String? note,
    Uint8List? imageJpeg,
  }) async {
    try {
      final r = await CompanyRoute.runOpen(() => ApiClient.dio.post<Object?>(base, data: {
            'client_ref': clientRef,
            'amount': amount,
            'pay_method': payMethod,
            if (payName != null && payName.trim().isNotEmpty) 'pay_name': payName.trim(),
            if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
            if (imageJpeg != null) 'image': 'data:image/jpeg;base64,${base64Encode(imageJpeg)}',
          }, options: Options(sendTimeout: const Duration(seconds: 60), receiveTimeout: const Duration(seconds: 60))));
      final b = r.data;
      if (b is Map && b['success'] == true) return (ok: true, message: null, code: null, request: BalanceRequest.fromJson(b['data']));
      return (ok: false, message: _msg(b) ?? 'تعذّر إرسال الطلب — حاول مرّةً أخرى', code: _code(b), request: null);
    } catch (_) {
      return (ok: false, message: 'تعذّر إرسال الطلب — تحقّق من الاتّصال وأعد الإرسال', code: 'NETWORK', request: null);
    }
  }

  static Future<BalanceReqResult> _post(String path, [Map<String, Object?> body = const {}]) async {
    try {
      final r = await CompanyRoute.runOpen(() => ApiClient.dio.post<Object?>(path, data: body));
      final b = r.data;
      if (b is Map && b['success'] == true) return (ok: true, message: null, code: null, request: BalanceRequest.fromJson(b['data']));
      return (ok: false, message: _msg(b) ?? 'تعذّرت العمليّة', code: _code(b), request: null);
    } catch (_) {
      return (ok: false, message: 'تعذّرت العمليّة — تحقّق من الاتّصال', code: 'NETWORK', request: null);
    }
  }

  static Future<BalanceReqResult> cancel(int id) => _post('$base/$id/cancel');
  static Future<BalanceReqResult> reject(int id, String reason) => _post('$base/$id/reject', {'reason': reason});

  /// حسم طلبٍ «قيد التأكّد»: [charged] true = شُحن فعلاً، false = لم يُشحن (يعود للانتظار).
  static Future<BalanceReqResult> resolve(int id, {required bool charged}) =>
      _post('$base/$id/resolve', {'outcome': charged ? 'done' : 'pending'});

  /// طلبات الأعلى. [status] pending (ومعه «قيد التأكّد») · done · closed · all. null = تعذّر.
  static Future<IncomingPage?> incoming({String status = 'pending', int offset = 0, int limit = 30}) async {
    try {
      final r = await CompanyRoute.runOpen(() => ApiClient.dio.get<Object?>('$base/incoming',
          queryParameters: {'status': status, 'offset': offset, 'limit': limit}));
      final b = r.data;
      if (b is! Map || b['success'] != true) return null;
      final c = b['counts'] is Map ? b['counts'] as Map : const {};
      return IncomingPage(
        items: [
          for (final x in (b['data'] is List ? b['data'] as List : const []))
            if (BalanceRequest.fromJson(x) case final r?) r,
        ],
        total: _int(b['total']) ?? 0,
        pending: _int(c['pending']) ?? 0,
        processing: _int(c['processing']) ?? 0,
        done: _int(c['done']) ?? 0,
        rejected: _int(c['rejected']) ?? 0,
      );
    } catch (_) {
      return null;
    }
  }

  /// ما ينتظر الأعلى (بانتظاره + قيد التأكّد). null = تعذّر أو بلا صلاحيّة.
  static Future<int?> count() async {
    try {
      final r = await CompanyRoute.runOpen(() => ApiClient.dio.get<Object?>('$base/incoming/count'));
      final b = r.data;
      if (b is! Map || b['success'] != true || b['data'] is! Map) return null;
      final d = b['data'] as Map;
      return (_int(d['pending']) ?? 0) + (_int(d['processing']) ?? 0);
    } catch (_) {
      return null;
    }
  }

  /// صورة الحوالة (للأعلى بصلاحيّة الشحن أو لصاحبها). null = حُذفت (٧ أيّام) أو تعذّرت.
  static Future<Uint8List?> image(int id) async {
    try {
      final r = await CompanyRoute.runOpen(() => ApiClient.dio.get<List<int>>('$base/$id/image',
          options: Options(responseType: ResponseType.bytes, validateStatus: (s) => s != null && s < 500)));
      if (r.statusCode != 200 || r.data == null || r.data!.isEmpty) return null;
      return Uint8List.fromList(r.data!);
    } catch (_) {
      return null;
    }
  }
}

/// حال القسم لهذه الجلسة: قسم الفرعيّ ([me]) وعدد ما ينتظر الأعلى ([incoming]) — «قوائم أخرى» تبني عليهما بلا انتظار، والاستماع
/// يطلبهما إن قدُما. تبديل الجلسة يصفّرهما ([reset]).
abstract final class BalanceReqState {
  static final ValueNotifier<BalanceReqMe> me = _MeGate();
  static final ValueNotifier<int> incoming = _CountGate();

  static int _epoch = 0;
  static DateTime? _meAt;
  static DateTime? _countAt;
  static Future<void>? _meFlight;
  static Future<void>? _countFlight;
  static const ttl = Duration(minutes: 2);

  static Future<void> refreshMe({bool force = false}) {
    final f = _meFlight;
    if (f != null) return f;
    final at = _meAt;
    if (!force && at != null && DateTime.now().difference(at) < ttl) return Future<void>.value();
    final epoch = _epoch;
    late final Future<void> run;
    run = () async {
      String? token;
      try {
        token = await AuthStorage.readToken();
      } catch (_) {
        token = null;
      }
      if (token == null || token.isEmpty) return;
      final m = await BalanceRequestsApi.me();
      if (epoch != _epoch || m == null) return;
      _meAt = DateTime.now();
      me.value = m;
    }()
        .whenComplete(() {
      if (identical(_meFlight, run)) _meFlight = null;
    });
    _meFlight = run;
    return run;
  }

  static Future<void> refreshCount({bool force = false}) {
    final f = _countFlight;
    if (f != null) return f;
    final at = _countAt;
    if (!force && at != null && DateTime.now().difference(at) < ttl) return Future<void>.value();
    final epoch = _epoch;
    late final Future<void> run;
    run = () async {
      String? token;
      try {
        token = await AuthStorage.readToken();
      } catch (_) {
        token = null;
      }
      if (token == null || token.isEmpty) return;
      final n = await BalanceRequestsApi.count();
      if (epoch != _epoch || n == null) return;
      _countAt = DateTime.now();
      incoming.value = n;
    }()
        .whenComplete(() {
      if (identical(_countFlight, run)) _countFlight = null;
    });
    _countFlight = run;
    return run;
  }

  static void reset() {
    _epoch++;
    _meAt = null;
    _countAt = null;
    _meFlight = null;
    _countFlight = null;
    me.value = BalanceReqMe.off;
    incoming.value = 0;
  }

  @visibleForTesting
  static void debugSet({BalanceReqMe? meValue, int? count}) {
    _epoch++;
    _meFlight = null;
    _countFlight = null;
    if (meValue != null) {
      _meAt = DateTime.now();
      me.value = meValue;
    }
    if (count != null) {
      _countAt = DateTime.now();
      incoming.value = count;
    }
  }
}

class _MeGate extends ValueNotifier<BalanceReqMe> {
  _MeGate() : super(BalanceReqMe.off);

  @override
  void addListener(VoidCallback listener) {
    super.addListener(listener);
    scheduleMicrotask(BalanceReqState.refreshMe);
  }
}

class _CountGate extends ValueNotifier<int> {
  _CountGate() : super(0);

  @override
  void addListener(VoidCallback listener) {
    super.addListener(listener);
    scheduleMicrotask(BalanceReqState.refreshCount);
  }
}
