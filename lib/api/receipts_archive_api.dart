import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../services/auth_storage.dart';
import '../services/receipt_pdf.dart';
import 'api_client.dart';
import 'company_route.dart';

/// «أرشيف الوصولات» (١١ نوفمبر ٢٠٢٦ — المالك: «قسم… أرشفة الوصولات… مرّات المدراء ينسون طباعته أو يفقدونه، بحيث يبحث على رقم الوصل
/// أو اسم المشترك ويقدر يعيد طباعته»).
///
/// القائمة = كلّ تفعيلٍ وتمديدٍ وتسديد ومعه وصله: ما طُبع يُعاد برقمه وتاريخه («نسخة»)، وما لم يُطبع يُطبع الآن فيأخذ رقماً
/// ويُحفظ. القواعد كلّها في الخادم (`server/receiptArchive.js`): المبلغ والطريقة من سطر العمليّة لا من هنا، عمليّةٌ واحدة = وصلٌ
/// واحد، تسديدٌ أُلغي لا وصل له، والموظّف بلا «تقرير مالي» يرى عمليّاته وما طبعه وحده. الويب يقرأ الشكل نفسه في
/// `client-v2/src/lib/receipts-archive.ts`.
///
/// كلّ نداءٍ هنا بشركته **صراحةً** من مستدعيه ([CompanyRoute.explicit] — null = المفتوحة): القسم في «كل الشركات» يعرض شركة
/// الشريط، وكتابته (الإصدار وعدّ الإعادة) لا تأخذ وجهةً ضمنيّة.

num? _numOrNull(Object? v) {
  if (v == null || v is bool) return null;
  if (v is num) return v.isFinite ? v : null;
  return num.tryParse(v.toString());
}

int? _intOrNull(Object? v) {
  final n = _numOrNull(v);
  return n?.toInt();
}

String? _str(Object? v) {
  final s = v?.toString().trim();
  return (s == null || s.isEmpty) ? null : s;
}

Map<String, dynamic> _map(Object? v) => v is Map ? Map<String, dynamic>.from(v) : const <String, dynamic>{};

DateTime? _time(Object? ms) {
  final n = _intOrNull(ms);
  return n == null || n <= 0 ? null : DateTime.fromMillisecondsSinceEpoch(n, isUtc: true);
}

/// نوع العمليّة / الوصل كما في الأرشيف.
enum ArchiveOp {
  activate('activate', 'تفعيل'),
  extend('extend', 'تمديد'),
  payDebt('pay_debt', 'تسديد دين'),

  /// نوعٌ قديم (١١ صفّاً) لا يطبعه عميلٌ اليوم — يُعرض ولا يُعاد.
  addDebt('add_debt', 'إضافة دين');

  const ArchiveOp(this.wire, this.label);
  final String wire;
  final String label;

  static ArchiveOp? of(Object? v) {
    final s = v?.toString();
    for (final o in values) {
      if (o.wire == s) return o;
    }
    return null;
  }
}

/// «الكلّ / لم تُطبع / المطبوعة».
enum ArchiveState {
  all('all'),
  unprinted('unprinted'),
  printed('printed');

  const ArchiveState(this.wire);
  final String wire;
}

ReceiptPay? _payOf(Object? v) => switch (v?.toString()) {
      'cash' => ReceiptPay.cash,
      'partial' => ReceiptPay.partial,
      'credit' => ReceiptPay.credit,
      'wallet' => ReceiptPay.wallet,
      _ => null,
    };

/// صفّ القائمة: عمليّةٌ (ووصلها إن طُبع) أو وصلٌ مطبوعٌ بلا عمليّةٍ معروفة.
@immutable
class ArchiveItem {
  const ArchiveItem({
    required this.key,
    required this.type,
    required this.at,
    this.activityId,
    this.receiptId,
    this.receiptNo,
    this.printedAt,
    this.late = false,
    this.username,
    this.idx,
    this.name,
    this.phone,
    this.amount,
    this.pay,
    this.partialAmount,
    this.newBalance,
    this.package,
    this.byUsername,
    this.reprints = 0,
    this.voided = false,
    this.printable = true,
  });

  /// `a:<رقم العمليّة>` أو `r:<رقم الوصل في الأرشيف>`.
  final String key;
  final ArchiveOp type;

  /// وقت العمليّة (أو الطباعة لوصلٍ بلا عمليّة).
  final DateTime at;
  final int? activityId;
  final int? receiptId;
  final int? receiptNo;
  final DateTime? printedAt;

  /// صدر وصله لاحقاً من الأرشيف (لا ساعة العمليّة).
  final bool late;
  final String? username;
  final String? idx;
  final String? name;
  final String? phone;
  final num? amount;
  final ReceiptPay? pay;
  final num? partialAmount;

  /// رصيد المشترك بعد العمليّة: سالبٌ = دين.
  final num? newBalance;
  final String? package;

  /// من نفّذ العمليّة (أو طبع الوصل المنفرد).
  final String? byUsername;
  final int reprints;

  /// تسديدٌ أُلغي («إلغاء تسديد») — لا وصل له.
  final bool voided;
  final bool printable;

  bool get printed => receiptId != null;

  /// سبب منع الطباعة، أو null إن كان يُطبع.
  String? get blockedReason {
    if (voided) return 'أُلغي هذا التسديد — لا وصل له';
    if (!printable) return type == ArchiveOp.addDebt ? 'نوعٌ قديم من الوصولات لا يُعاد طبعه' : 'لا مبلغ مسجَّلاً لهذه العمليّة';
    return null;
  }

  /// الصفّ بعد طباعته (الوصل كما أعاده الخادم) — يُحدَّث بمكانه بلا إعادة جلب القائمة.
  ArchiveItem afterPrint(ArchivedReceipt r) => ArchiveItem(
        key: key,
        type: type,
        at: at,
        activityId: activityId,
        receiptId: r.id,
        receiptNo: r.receiptNo,
        printedAt: r.printedAt,
        late: r.late,
        username: username,
        idx: idx,
        name: name ?? r.name,
        phone: phone ?? r.phone,
        amount: amount,
        pay: pay,
        partialAmount: partialAmount,
        newBalance: newBalance,
        package: package,
        byUsername: byUsername,
        reprints: r.reprints,
        voided: voided,
        printable: printable,
      );

  static ArchiveItem? fromJson(Object? raw) {
    final j = _map(raw);
    final key = _str(j['key']);
    final type = ArchiveOp.of(j['type']);
    final at = _time(j['at']);
    if (key == null || type == null || at == null) return null;
    return ArchiveItem(
      key: key,
      type: type,
      at: at,
      activityId: _intOrNull(j['activity_id']),
      receiptId: _intOrNull(j['receipt_id']),
      receiptNo: _intOrNull(j['receipt_no']),
      printedAt: _time(j['printed_at']),
      late: j['late'] == true,
      username: _str(j['username']),
      idx: _str(j['idx']),
      name: _str(j['name']),
      phone: _str(j['phone']),
      amount: _numOrNull(j['amount']),
      pay: _payOf(j['pay']),
      partialAmount: _numOrNull(j['partial_amount']),
      newBalance: _numOrNull(j['new_balance']),
      package: _str(j['package']),
      byUsername: _str(_map(j['by'])['username']),
      reprints: _intOrNull(j['reprints']) ?? 0,
      voided: j['voided'] == true,
      printable: j['printable'] != false,
    );
  }
}

/// صفحةٌ من القائمة.
@immutable
class ArchivePage {
  const ArchivePage({required this.available, this.items = const [], this.next, this.ownOnly = false});

  /// المفتاح العامّ مفتوحٌ لهذه الصفحة (pro_settings.receipts_archive).
  final bool available;
  final List<ArchiveItem> items;

  /// موضع الصفحة التالية — null: انتهت.
  final String? next;

  /// الموظّف يرى عمليّاته وما طبعه وحده.
  final bool ownOnly;
}

/// الوصل كما يُطبع — شكلٌ واحد لما أُرشف من الموقع أو التطبيق ولما يصدر الآن.
@immutable
class ArchivedReceipt {
  const ArchivedReceipt({
    required this.id,
    required this.kind,
    required this.issuedAt,
    required this.printedAt,
    required this.username,
    this.receiptNo,
    this.late = false,
    this.copy = false,
    this.reprints = 0,
    this.name,
    this.phone,
    this.idx,
    this.packageName,
    this.packagePrice,
    this.expiration,
    this.remainingDays,
    this.pay,
    this.amount,
    this.partialAmount,
    this.newBalance,
    this.issuer,
    this.companyKey,
  });

  final int id;
  final int? receiptNo;

  /// شركة الوصل في «كل الشركات» — مفتاح الطلب الذي أعاده (null: المفتوحة). يسافر مع الوصل: تصميمه ورابط QR لمشتركه يُطلبان
  /// لشركته هي (رقم المشترك فريدٌ داخل شركته وحدها)، لا لما يتبدّل في الشاشة بعد ذلك.
  final String? companyKey;

  /// null = نوعٌ لا يُطبع (القديم).
  final ReceiptKind? kind;

  /// التاريخ المطبوع: وقت الطباعة الأولى، أو وقت العمليّة لوصلٍ صدر لاحقاً.
  final DateTime issuedAt;
  final DateTime printedAt;
  final bool late;

  /// إعادة طباعة ⇒ «نسخة».
  final bool copy;
  final int reprints;
  final String username;
  final String? name;
  final String? phone;
  final String? idx;
  final String? packageName;
  final num? packagePrice;
  final String? expiration;
  final int? remainingDays;
  final ReceiptPay? pay;
  final num? amount;
  final num? partialAmount;
  final num? newBalance;

  /// «أصدره» كما حُفظ: الاسم المختار يومها، ثمّ يوزر الموظّف، ثمّ يوزر المدير.
  final String? issuer;

  static ArchivedReceipt? fromJson(Object? raw, {String? companyKey}) {
    final j = _map(raw);
    final id = _intOrNull(j['id']);
    final issued = _time(j['issued_at']);
    final printed = _time(j['printed_at']);
    final sub = _map(j['subscriber']);
    final username = _str(sub['username']);
    if (id == null || issued == null || printed == null || username == null) return null;
    final pkg = _map(j['package']);
    final iss = _map(j['issuer']);
    return ArchivedReceipt(
      id: id,
      receiptNo: _intOrNull(j['receipt_no']),
      kind: switch (j['kind']?.toString()) {
        'activation' => ReceiptKind.activation,
        'extension' => ReceiptKind.extension,
        'payment' => ReceiptKind.payment,
        _ => null,
      },
      issuedAt: issued,
      printedAt: printed,
      late: j['late'] == true,
      copy: j['copy'] == true,
      reprints: _intOrNull(j['reprints']) ?? 0,
      username: username,
      name: _str(sub['name']),
      phone: _str(sub['phone']),
      idx: _str(sub['idx']),
      packageName: _str(pkg['name']),
      packagePrice: _numOrNull(pkg['price']),
      expiration: _str(j['expiration']),
      remainingDays: _intOrNull(j['remaining_days']),
      pay: _payOf(j['pay']),
      amount: _numOrNull(j['amount']),
      partialAmount: _numOrNull(j['partial_amount']),
      newBalance: _numOrNull(j['new_balance']),
      issuer: _str(iss['name']) ?? _str(iss['employee_username']) ?? _str(iss['manager_username']),
      companyKey: companyKey,
    );
  }
}

/// ما يعرفه التطبيق عن المشترك الآن — للوصل الذي يصدر لاحقاً (نصوصٌ للطباعة وحدها؛ الخادم يقرّر ما يُطبع منها).
@immutable
class ArchiveHint {
  const ArchiveHint({this.name, this.phone, this.expiration, this.packageName});
  final String? name;
  final String? phone;
  final String? expiration;
  final String? packageName;

  Map<String, dynamic> toJson() => {
        if ((name ?? '').isNotEmpty) 'name': name,
        if ((phone ?? '').isNotEmpty) 'phone': phone,
        if ((expiration ?? '').isNotEmpty) 'expiration': expiration,
        if ((packageName ?? '').isNotEmpty) 'package_name': packageName,
      };
}

/// نتيجة الإصدار أو الإعادة: [receipt] حين نجح؛ وإلّا [message] بكلمات الخادم.
typedef ArchivePrintReply = ({ArchivedReceipt? receipt, bool existing, String? message, String? code});

class ReceiptsArchiveApi {
  ReceiptsArchiveApi._();

  static const _base = '/api/printed-receipts';
  static const pageSize = 40;

  /// أقصى ما يُرسل من اليوزرات المطابقة بالاسم (حدّ الخادم ٦٠).
  static const usersMax = 60;

  static void _log(String where, Object e) {
    if (kDebugMode) debugPrint('[ReceiptsArchiveApi] $where: $e');
  }

  /// هل القسم مفتوحٌ للشركة المفتوحة؟ `null` = تعذّر الوصول (يُعاد لاحقاً) — لا شيء يظهر بلا تأكيد.
  static Future<bool?> probe() async {
    String? token;
    try {
      token = await AuthStorage.readToken();
    } catch (_) {
      token = null;
    }
    if (token == null || token.isEmpty) return null;
    try {
      final r = await ApiClient.dio.get<Object?>(
        '$_base/archive',
        queryParameters: const {'probe': '1'},
        options: CompanyRoute.explicit(null),
      );
      final code = r.statusCode ?? 0;
      final body = _map(r.data);
      // خادمٌ أقدم بلا المسار (يلتقطه /:id ⇒ 400) أو مزوّدٌ لا يمرّره (ردّه الآمن بلا available) ⇒ مطفأ.
      if (code == 400 || code == 404) return false;
      if (code >= 400 || body['success'] != true) return code == 403 ? false : null;
      return body['available'] == true;
    } catch (e) {
      _log('probe', e);
      return null;
    }
  }

  /// صفحةٌ من القائمة. [spanDays] null = كلّ المدّة. [users] يوزرات من طابق اسمُه نصَّ البحث (سطر العمليّة بلا اسم).
  static Future<({ArchivePage? page, String? error})> page({
    required String? companyKey,
    String query = '',
    List<String> users = const [],
    ArchiveOp? type,
    ArchiveState state = ArchiveState.all,
    int? spanDays = 30,
    String? cursor,
    DateTime? now,
  }) async {
    try {
      final from = spanDays == null ? 'all' : '${(now ?? DateTime.now()).millisecondsSinceEpoch - spanDays * 86400000}';
      final r = await ApiClient.dio.get<Object?>(
        '$_base/archive',
        queryParameters: {
          'limit': pageSize,
          'from': from,
          if (query.trim().isNotEmpty) 'q': query.trim(),
          if (users.isNotEmpty) 'users': users.take(usersMax).join(','),
          if (type != null) 'type': type.wire,
          if (state != ArchiveState.all) 'state': state.wire,
          if (cursor != null) 'cursor': cursor,
        },
        options: CompanyRoute.explicit(companyKey),
      );
      final body = _map(r.data);
      if ((r.statusCode ?? 0) >= 400 || body['success'] != true) {
        return (page: null, error: _str(body['message']) ?? 'تعذّر تحميل الوصولات الآن');
      }
      final rows = body['data'] is List ? body['data'] as List : const [];
      return (
        page: ArchivePage(
          available: body['available'] == true,
          items: [
            for (final x in rows)
              if (ArchiveItem.fromJson(x) case final ArchiveItem it) it,
          ],
          next: _str(body['next']),
          ownOnly: body['own_only'] == true,
        ),
        error: null,
      );
    } catch (e) {
      _log('page', e);
      return (page: null, error: 'تعذّر تحميل الوصولات الآن');
    }
  }

  /// وصلٌ لعمليّةٍ لم تُطبع — يأخذ الرقم التالي ويُحفظ؛ عمليّةٌ طُبعت سابقاً ⇒ وصلها نفسه (existing).
  static Future<ArchivePrintReply> issue({required String? companyKey, required int activityId, ArchiveHint? hint}) {
    final h = hint?.toJson() ?? const <String, dynamic>{};
    return _post('issue', {'activity_id': activityId, if (h.isNotEmpty) 'subscriber': h}, companyKey, 'تعذّر إصدار الوصل الآن — أعد المحاولة');
  }

  /// إعادة طباعة وصلٍ مؤرشف — تُعدّ في الخادم.
  static Future<ArchivePrintReply> reprint({required String? companyKey, required int receiptId}) =>
      _post('reprint', {'id': receiptId}, companyKey, 'تعذّرت إعادة الطباعة الآن — أعد المحاولة');

  static Future<ArchivePrintReply> _post(String name, Map<String, dynamic> data, String? companyKey, String fallback) async {
    try {
      final r = await ApiClient.dio.post<Object?>('$_base/$name', data: data, options: CompanyRoute.explicit(companyKey));
      final body = _map(r.data);
      final receipt = body['success'] == true ? ArchivedReceipt.fromJson(body['receipt'], companyKey: companyKey) : null;
      if (receipt == null) {
        return (receipt: null, existing: false, message: _str(body['message']) ?? fallback, code: _str(body['code']));
      }
      return (receipt: receipt, existing: body['existing'] == true, message: null, code: null);
    } on DioException catch (e) {
      _log(name, e);
      return (receipt: null, existing: false, message: fallback, code: null);
    } catch (e) {
      _log(name, e);
      return (receipt: null, existing: false, message: fallback, code: null);
    }
  }
}

/// حال القسم لبطاقته في «قوائم أخرى» — كـ[SalesState]: الاستماع يطلب الحال إن كانت قديمة، ولا شيء يظهر ما لم يقل الخادم
/// إنّه مفتوحٌ صراحةً.
class ReceiptsArchiveState {
  ReceiptsArchiveState._();

  /// true مفتوح · false مطفأ · null لم يُعرف بعد.
  static final ValueNotifier<bool?> gate = _ArchiveGate();

  static int _epoch = 0;
  static DateTime? _fetchedAt;
  static DateTime? _failedAt;
  static Future<void>? _inflight;

  static const ttl = Duration(minutes: 5);
  static const _cooldown = Duration(seconds: 30);

  static bool get visible => gate.value ?? false;

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
    run = ReceiptsArchiveApi.probe().then((p) {
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
  static void debugSet(bool? open) {
    _epoch++;
    _inflight = null;
    _failedAt = null;
    _fetchedAt = open == null ? null : DateTime.now();
    gate.value = open;
  }
}

class _ArchiveGate extends ValueNotifier<bool?> {
  _ArchiveGate() : super(null);

  @override
  void addListener(VoidCallback listener) {
    super.addListener(listener);
    // بعد البناء لا أثناءه: الجلب يكتب القيمة فيُعيد بناء المستمعين.
    scheduleMicrotask(ReceiptsArchiveState.ensureFresh);
  }
}

const _arabicDigits = '٠١٢٣٤٥٦٧٨٩';

/// نصّ البحث للمطابقة المحلّيّة: أرقامٌ لاتينيّة، بلا تشكيل، وألف/ياء/تاء موحّدة — «أحمد» = «احمد» (كالموقع).
String foldArchiveSearch(String s) {
  final b = StringBuffer();
  for (final r in s.toLowerCase().runes) {
    final c = String.fromCharCode(r);
    final d = _arabicDigits.indexOf(c);
    if (d >= 0) {
      b.write(d);
    } else if (r >= 0x064B && r <= 0x0652 || r == 0x0640) {
      // تشكيل وتطويل
    } else if (c == 'أ' || c == 'إ' || c == 'آ') {
      b.write('ا');
    } else if (c == 'ى') {
      b.write('ي');
    } else if (c == 'ة') {
      b.write('ه');
    } else {
      b.write(c);
    }
  }
  return b.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// يوزرات من طابق اسمه أو هاتفه نصَّ البحث — تُرسل للخادم فيجد عمليّاتهم غير المطبوعة. اليوزر نفسه يطابقه الخادم.
List<String> archiveUsersMatching(Iterable<({String username, String name, String phone})> known, String query) {
  final needle = foldArchiveSearch(query);
  if (needle.length < 2) return const [];
  final out = <String>[];
  for (final s in known) {
    if (s.username.isEmpty) continue;
    if ((s.name.isNotEmpty && foldArchiveSearch(s.name).contains(needle)) || (s.phone.isNotEmpty && s.phone.contains(needle))) {
      out.add(s.username);
      if (out.length >= ReceiptsArchiveApi.usersMax) break;
    }
  }
  return out;
}
