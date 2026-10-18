import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'api_client.dart';
import 'el_deposit_password.dart';

/// ايرث لنك — نقاط البند ٤ المخصّصة لموزِّعي EarthLink وحدهم
/// (`/api/v2/el/*`). محوّلٌ موازٍ على خادم Pro يتفرّع على `kind='earthlink'`
/// في `sas_servers`؛ لا يمسّ مسار supernet. الشاشات:
///   • تحويل الرصيد + كشف الحساب  → [transferTargets] · [transfer] ·
///     [accountStatement].
///   • الكارتات المطلوبة (توقّع الكارتات والرصيد لمدّة) → [prepaidNeeded].
///
/// ⚠️ كلّ النداءات تمرّ على `ApiClient.dio` المشترك: معترضه يلصق توكن
/// الجلسة تلقائيّاً (ليست مساراً تحت `/api/auth/`)، و`validateStatus < 500`
/// يجعل الرفض يصل **ردّاً لا رميةً** — فنقرأ `success` و`message` من الجسم.
/// رسالة الخادم العربيّة الجاهزة تُعرض كما هي عند الفشل.

num _num(Object? v) =>
    v is num ? v : num.tryParse(v?.toString().replaceAll(',', '') ?? '') ?? 0;

int? _intOrNull(Object? v) {
  if (v == null || v is bool) return null;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString().trim());
}

String? _str(Object? v) {
  final s = v?.toString().trim();
  return (s == null || s.isEmpty) ? null : s;
}

/// رقمٌ أو `null` حين يغيب الحقل — لا «0» كاذب لسعرٍ لم يُرسَل.
num? _numOrNull(Object? v) {
  if (v == null || v is bool) return null;
  if (v is num) return v;
  return num.tryParse(v.toString().replaceAll(',', '').trim());
}

List<T> _rows<T>(Object? v, T? Function(Map<String, dynamic>) parse) => v is List
    ? v
        .whereType<Map>()
        .map((m) => parse(Map<String, dynamic>.from(m)))
        .whereType<T>()
        .toList(growable: false)
    : List<T>.empty();

/// القائمة من جسم الردّ: `data` قائمةً مباشرةً، أو خريطةً تحمل القائمة تحت
/// مفتاحٍ شائع — فتبقى الشاشات صامدةً مهما اختلف شكل غلاف نقاط el.
List<dynamic> _pickList(Object? data) {
  if (data is List) return data;
  if (data is Map) {
    for (final k in const [
      'items',
      'rows',
      'list',
      'data',
      'subscribers',
      'packages',
      'accounts',
      'entries',
      'logs',
      'results',
    ]) {
      final v = data[k];
      if (v is List) return v;
    }
  }
  return const [];
}

// ═════════════════════════ النماذج ═════════════════════════

/// وجهة تحويلٍ ممكنة — موزّعٌ آخر يُحوَّل له الرصيد.
class ElTransferTarget {
  const ElTransferTarget({required this.affiliateIndex, required this.affiliateName});

  final int affiliateIndex;
  final String affiliateName;

  static ElTransferTarget? fromJson(Map<String, dynamic> j) {
    final idx = _intOrNull(j['affiliateIndex']);
    if (idx == null) return null;
    return ElTransferTarget(
      affiliateIndex: idx,
      affiliateName: _str(j['affiliateName']) ?? '#$idx',
    );
  }
}

/// حركةٌ في كشف حساب الإيداع — إيداعٌ (أخضر) أو سحبٌ (أحمر) والرصيد بعدها.
class ElStatementEntry {
  const ElStatementEntry({
    required this.id,
    required this.description,
    required this.userId,
    required this.displayName,
    required this.operation,
    required this.deposit,
    required this.withdrawal,
    required this.balance,
    required this.date,
    required this.serials,
    required this.resellerUser,
  });

  final int? id;
  final String? description;
  final String? userId;
  final String? displayName;
  final String? operation;
  final num deposit;
  final num withdrawal;
  final num balance;
  final String? date;
  final String? serials;
  final String? resellerUser;

  /// إيداعٌ موجب ⇒ مالٌ داخل (أخضر).
  bool get isDeposit => deposit > 0;

  /// سحبٌ موجب ⇒ مالٌ خارج (أحمر).
  bool get isWithdrawal => withdrawal > 0;

  /// المشترك/الطرف المعروض: الاسم ثمّ المعرّف ثمّ حساب الموزّع.
  String? get party => displayName ?? userId ?? resellerUser;

  static ElStatementEntry fromJson(Map<String, dynamic> j) => ElStatementEntry(
        id: _intOrNull(j['id']),
        description: _str(j['description']),
        userId: _str(j['user_id']),
        displayName: _str(j['display_name']),
        operation: _str(j['operation']),
        deposit: _num(j['deposit']),
        withdrawal: _num(j['withdrawal']),
        balance: _num(j['balance']),
        date: _str(j['date']),
        serials: _str(j['serials']),
        resellerUser: _str(j['reseller_user']),
      );
}

/// صفّ باقةٍ في «الكارتات المطلوبة»: المتوفّر بالمخزون الآن، المُستهلَك
/// خلال المدّة، المطلوب تزويده، وكلفة الكارت على الشركة. لا أسعار بيع
/// ولا ربح هنا — أسعار البيع بشاشة الباقات.
class ElNeededCard {
  const ElNeededCard({
    required this.profileId,
    required this.name,
    required this.cost,
    required this.available,
    required this.used,
    required this.needed,
    required this.image,
    this.cardPrice,
  });

  final int profileId;
  final String name;

  /// كلفة التفعيل من الرصيد للباقة (د.ع) — `accountCost` من «الكارتات المطلوبة».
  final num cost;

  /// سعر الكارت لدى ايرث لنك (د.ع، `prices/forreseller`) — ما يحسب به «طلب
  /// الكارتات». `null` = لم يُقرأ (خادمٌ أقدم أو تعذّرت الأسعار).
  final num? cardPrice;

  /// المتوفّر بالمخزون الآن.
  final int available;

  /// المُستهلَك خلال المدّة.
  final int used;

  /// المطلوب تزويده لتغطية المدّة.
  final int needed;
  final String? image;

  /// سعر الكارت الواحد لشراء الكارتات: سعر ايرث لنك للكارت، وإلّا كلفة التفعيل.
  num get unitPrice => cardPrice ?? cost;

  /// الرصيد اللازم لشراء كارتات هذه الباقة = المطلوب × سعر الكارت — بالسعر نفسه
  /// الذي يحسب به «طلب الكارتات» (فلا تقول الصفحة رقماً والطلب رقماً آخر).
  num get balanceNeeded => needed * unitPrice;

  static int _count(Object? v) {
    final n = _intOrNull(v) ?? _num(v).round();
    return n < 0 ? 0 : n;
  }

  static ElNeededCard? fromJson(Map<String, dynamic> j) {
    final id = _intOrNull(j['profile_id']);
    final name = _str(j['name']);
    if (id == null && name == null) return null;
    final cost = _num(j['cost']);
    final cardPrice = _numOrNull(j['card_price']);
    return ElNeededCard(
      profileId: id ?? 0,
      name: name ?? 'باقة #$id',
      cost: cost < 0 ? 0 : cost,
      cardPrice: (cardPrice != null && cardPrice > 0) ? cardPrice : null,
      available: _count(j['available']),
      used: _count(j['used']),
      needed: _count(j['needed']),
      image: _str(j['image']),
    );
  }
}

/// باقةٌ في خيارات «إضافة مشترك»: [price] سعرنا للمشترك (به تُسعَّر
/// نقدي/دين/جزئي)، و[costPrice] كلفتها على الوكيل من الشركة.
class ElCreatePackage {
  const ElCreatePackage({
    required this.id,
    required this.name,
    this.price,
    this.costPrice,
  });

  final String id;
  final String name;
  final num? price;
  final num? costPrice;

  static ElCreatePackage? fromJson(Map<String, dynamic> j) {
    final id = _str(j['id']);
    if (id == null) return null;
    return ElCreatePackage(
      id: id,
      name: _str(j['name']) ?? '#$id',
      price: _numOrNull(j['price']),
      costPrice: _numOrNull(j['cost_price']),
    );
  }
}

/// GET /api/v2/el/create-options — ما يحتاجه شيت «مشترك جديد» لايرث لنك:
/// لاحقة اسم الدخول، الباقات بأسعارنا، رصيد الإيداع، حصّة التجريبيّ،
/// والطرق المسموحة لهذا الحساب.
class ElCreateOptions {
  const ElCreateOptions({
    required this.userSuffix,
    required this.packages,
    required this.depositBalance,
    required this.testCount,
    required this.canDeposit,
    required this.canCard,
    required this.canTest,
  });

  /// `@xxx` — تُعرض ثابتةً بعد اسم الدخول. فارغة حين لا يعرفها الخادم.
  final String userSuffix;
  final List<ElCreatePackage> packages;

  /// `null` = غير معروف (لا يُعرض صفّه).
  final num? depositBalance;
  final int testCount;
  final bool canDeposit;
  final bool canCard;
  final bool canTest;

  /// التجريبيّ يُعرض فقط حين يُسمح به **وتبقى** منه حصّة.
  bool get testAvailable => canTest && testCount > 0;

  ElCreatePackage? packageById(String? id) {
    if (id == null || id.isEmpty) return null;
    for (final p in packages) {
      if (p.id == id) return p;
    }
    return null;
  }

  static ElCreateOptions fromJson(Map<String, dynamic> j) {
    var suffix = _str(j['user_suffix']) ?? '';
    if (suffix.isNotEmpty && !suffix.startsWith('@')) suffix = '@$suffix';
    final m = j['methods'];
    // خادمٌ لا يرسل `methods` ⇒ رصيد + كارت (كشيت التفعيل) بلا تجريبيّ.
    final methods = m is Map ? m : null;
    final test = _intOrNull(j['test_count']) ?? 0;
    return ElCreateOptions(
      userSuffix: suffix,
      packages: _rows(j['packages'], ElCreatePackage.fromJson),
      depositBalance: _numOrNull(j['deposit_balance']),
      testCount: test < 0 ? 0 : test,
      canDeposit: methods == null || methods['deposit'] == true,
      canCard: methods == null || methods['card'] == true,
      canTest: methods != null && methods['test'] == true,
    );
  }
}

/// POST /api/v2/el/card-info — قراءة كارتٍ مكتوب (رقم + Pin) قبل استعماله:
/// صالح؟ وما باقته؟ الكارت هو من يحدّد باقة المشترك في طريقة «كارت».
class ElCardInfo {
  const ElCardInfo({
    required this.valid,
    this.profileId,
    this.profileName,
    this.price,
    this.costPrice,
    this.message,
  });

  final bool valid;
  final int? profileId;
  final String? profileName;

  /// سعرنا للمشترك على باقة الكارت، و[costPrice] كلفتها على الوكيل — يرسلهما
  /// الخادم مع قراءة الكارت (الجولة الثانية). يُستعملان حين تكون باقة الكارت
  /// خارج قائمة create-options فلا تُقرأ أسعارها منها — فيظهر السعر وبانر الدين.
  final num? price;
  final num? costPrice;

  /// سبب الرفض كما يكتبه الخادم (حين `valid == false`).
  final String? message;

  static ElCardInfo fromJson(Map<String, dynamic> j) => ElCardInfo(
        valid: j['valid'] == true,
        profileId: _intOrNull(j['profile_id']),
        profileName: _str(j['profile_name']),
        price: _numOrNull(j['price']),
        costPrice: _numOrNull(j['cost_price']),
        message: _str(j['message']),
      );
}

/// نتيجة إضافة مشترك ايرث لنك.
///
/// [unclear] = ربّما أُضيف: لا ردّ (مهلة/انقطاع)، بوّابةٌ بلا ردٍّ صالح
/// (502/504/524)، `CREATE_UNCONFIRMED`، أو `CREATE_LATE_SUSPECTED` من الخادم.
/// الشيت يُقفل الزرّ ولا يُعيد الإرسال أبداً، ويُبقي [message] (رسالة الخادم،
/// وقد تحمل مبلغ الدين الذي يُسجَّل يدويّاً) ظاهرةً داخله.
///
/// [debtWriteFailed] = نجاحٌ ومعه `debt_write.ok == false`: أُنشئ المشترك
/// لكنّ دينه لم يُسجَّل في دفترنا — تنبيهٌ لا يمنع، برسالة الخادم
/// [debtWriteMessage] إن وُجدت.
typedef ElCreateResult = ({
  bool ok,
  String? message,
  String? code,
  bool unclear,
  String? username,
  bool debtWriteFailed,
  String? debtWriteMessage,
});

/// GET /api/v2/el/test-usage — مشترك على الاشتراك التجريبيّ. الحقول تُقرأ
/// بأسماءٍ بديلة لأنّ شكل الخادم لم يُثبَّت بعد (يُحسم عند أوّل ردٍّ حيّ).
class ElTestUsageRow {
  const ElTestUsageRow({
    required this.name,
    this.username,
    this.date,
    this.usage,
  });

  final String name;
  final String? username;
  final String? date;

  /// استهلاكٌ رقميّ إن أرسله الخادم — يُعرَض كما هو (بلا تأويلٍ للوحدة).
  final num? usage;

  static ElTestUsageRow? fromJson(Map<String, dynamic> j) {
    final full = [_str(j['firstname']), _str(j['lastname'])]
        .whereType<String>()
        .join(' ')
        .trim();
    final name = _str(j['name']) ??
        _str(j['display_name']) ??
        (full.isEmpty ? null : full) ??
        _str(j['username']);
    if (name == null) return null;
    return ElTestUsageRow(
      name: name,
      username: _str(j['username']),
      date: _str(j['date']) ??
          _str(j['created_at']) ??
          _str(j['created']) ??
          _str(j['expiration']),
      usage: _numOrNull(j['usage']) ??
          _numOrNull(j['used']) ??
          _numOrNull(j['consumed']),
    );
  }
}

/// GET /api/v2/el/audit — حركةٌ في سجلّ ايرث لنك. النصّ من الخادم (عربيّ
/// جاهز)، والفاعل والتاريخ إن وُجدا.
class ElAuditRow {
  const ElAuditRow({required this.text, this.date, this.actor, this.amount});

  final String text;
  final String? date;
  final String? actor;
  final num? amount;

  static ElAuditRow? fromJson(Map<String, dynamic> j) {
    final text = _str(j['description']) ??
        _str(j['message']) ??
        _str(j['action_description']) ??
        _str(j['action']) ??
        _str(j['operation']) ??
        _str(j['event']);
    if (text == null) return null;
    return ElAuditRow(
      text: text,
      date: _str(j['date']) ??
          _str(j['created_at']) ??
          _str(j['time']) ??
          _str(j['timestamp']),
      actor: _str(j['user']) ??
          _str(j['username']) ??
          _str(j['admin_name']) ??
          _str(j['admin']) ??
          _str(j['actor']),
      amount: _numOrNull(j['amount']),
    );
  }
}

/// GET /api/v2/el/by-package — عدد المشتركين على كلّ باقة.
class ElPackageCount {
  const ElPackageCount({required this.name, required this.count});

  final String name;
  final int count;

  static ElPackageCount? fromJson(Map<String, dynamic> j) {
    final name = _str(j['name']) ??
        _str(j['profile_name']) ??
        _str(j['package']) ??
        _str(j['profile']);
    if (name == null) return null;
    final count = _intOrNull(j['count']) ??
        _intOrNull(j['subscribers']) ??
        _intOrNull(j['subscriber_count']) ??
        _intOrNull(j['total']) ??
        0;
    return ElPackageCount(name: name, count: count < 0 ? 0 : count);
  }
}

/// سطرٌ في طلب كارتات سابق: الباقة، العدد المطلوب، سعرها، وكم كارتاً اعتُمد.
class ElCardOrderLine {
  const ElCardOrderLine({
    required this.name,
    required this.amount,
    required this.price,
    required this.approvedCount,
  });

  final String name;

  /// العدد المطلوب.
  final int amount;

  /// السعر كما يرسله الخادم (لا نُحوّله لمجموعٍ لا نعرف وحدته).
  final num? price;

  /// كم كارتاً اعتمدته ايرث لنك من هذا السطر (عددٌ فقط — لا أرقام ولا PIN).
  final int approvedCount;

  static ElCardOrderLine? fromJson(Map<String, dynamic> j) {
    final name = _str(j['name']) ??
        _str(j['account_name']) ??
        _str(j['profile_name']) ??
        _str(j['package']);
    final amount = _intOrNull(j['amount']) ??
        _intOrNull(j['count']) ??
        _intOrNull(j['cards_count']);
    if (name == null && amount == null) return null;
    final approved = _intOrNull(j['approved_count']) ??
        _intOrNull(j['approved']) ??
        (j['approvedCards'] is List ? (j['approvedCards'] as List).length : 0);
    return ElCardOrderLine(
      name: name ?? '—',
      amount: (amount ?? 0) < 0 ? 0 : (amount ?? 0),
      price: _numOrNull(j['price']),
      approvedCount: approved < 0 ? 0 : approved,
    );
  }
}

/// حال طلب الكارتات كما نفهمها — النصّ الخام من ايرث لنك يُعرض كما هو حين
/// لا نعرفه ([ElCardOrder.statusRaw]).
enum ElCardOrderStatus { pending, approved, rejected, cancelled, unknown }

/// طلب كارتات سابق — GET /api/v2/el/card-orders.
class ElCardOrder {
  const ElCardOrder({
    required this.batchNo,
    required this.statusRaw,
    required this.createdAt,
    required this.canCancel,
    required this.lines,
  });

  final int? batchNo;
  final String? statusRaw;
  final String? createdAt;
  final bool canCancel;
  final List<ElCardOrderLine> lines;

  int get totalCards => lines.fold<int>(0, (s, l) => s + l.amount);
  int get totalApproved => lines.fold<int>(0, (s, l) => s + l.approvedCount);

  ElCardOrderStatus get status {
    final s = (statusRaw ?? '').trim().toLowerCase();
    if (s.isEmpty) return ElCardOrderStatus.unknown;
    if (s.contains('cancel') || s.contains('ملغ')) {
      return ElCardOrderStatus.cancelled;
    }
    if (s.contains('reject') || s.contains('declin') || s.contains('رفض')) {
      return ElCardOrderStatus.rejected;
    }
    if (s.contains('approv') ||
        s.contains('accept') ||
        s.contains('complet') ||
        s.contains('done') ||
        s.contains('deliver') ||
        s.contains('معتمد') ||
        s.contains('مكتمل')) {
      return ElCardOrderStatus.approved;
    }
    if (s.contains('pend') ||
        s.contains('new') ||
        s.contains('wait') ||
        s.contains('process') ||
        s.contains('review') ||
        s.contains('انتظار') ||
        s.contains('مراجعة')) {
      return ElCardOrderStatus.pending;
    }
    return ElCardOrderStatus.unknown;
  }

  static ElCardOrder? fromJson(Map<String, dynamic> j) {
    final lines = _rows(j['cards'] ?? j['lines'] ?? j['items'],
        ElCardOrderLine.fromJson);
    final batch = _intOrNull(j['batch_no']) ?? _intOrNull(j['batchNo']);
    final created = _str(j['created_at']) ?? _str(j['createdAt']);
    if (batch == null && created == null && lines.isEmpty) return null;
    return ElCardOrder(
      batchNo: batch,
      statusRaw: _str(j['status']),
      createdAt: created,
      canCancel: j['can_cancel'] == true || j['canCancel'] == true,
      lines: lines,
    );
  }
}

/// سطرٌ في طلبٍ جديد: الباقة (`profile_id` = accountIndex) والعدد.
typedef ElCardOrderItem = ({int profileId, int count});

/// سطرٌ في تقدير الطلب — سعر الكارت لدى ايرث لنك × العدد (الخادم يحسبه).
class ElCardQuoteLine {
  const ElCardQuoteLine({
    required this.profileId,
    required this.name,
    required this.count,
    this.unitCost,
    this.total,
  });

  final int profileId;
  final String name;
  final int count;

  /// `null` = باقةٌ لا يعرف الخادم سعرها (ليست في قائمة الموزّع).
  final num? unitCost;
  final num? total;

  static ElCardQuoteLine? fromJson(Map<String, dynamic> j) {
    final id = _intOrNull(j['profile_id']);
    if (id == null) return null;
    return ElCardQuoteLine(
      profileId: id,
      name: _str(j['name']) ?? 'باقة #$id',
      count: _intOrNull(j['count']) ?? 0,
      unitCost: _numOrNull(j['unit_cost']),
      total: _numOrNull(j['total']),
    );
  }
}

/// POST /api/v2/el/card-order/quote — خطوة التأكيد: الكلفة المتوقّعة لكلّ
/// باقة والمجموع مقابل رصيد الإيداع، بلا أيّ أثر. [expectedTotal] يُرسَل مع
/// الطلب نفسه فيرفضه الخادم إن تغيّرت الكلفة منذ المراجعة (`COST_CHANGED`).
class ElCardQuote {
  const ElCardQuote({
    required this.lines,
    required this.unknown,
    required this.total,
    required this.expectedTotal,
    required this.count,
    this.balance,
    this.after,
    this.enough,
    this.note,
  });

  final List<ElCardQuoteLine> lines;

  /// باقاتٌ بلا سعرٍ معروف — الخادم لا يقبل طلبها.
  final List<int> unknown;
  final num total;

  /// ما يُرسَل مع الطلب حرفيّاً (= [total] عادةً).
  final num expectedTotal;
  final int count;

  /// رصيد الإيداع الآن (`null` = تعذّرت قراءته)، والرصيد بعد الطلب.
  final num? balance;
  final num? after;

  /// يكفي الرصيد؟ `null` = غير معروف.
  final bool? enough;
  final String? note;

  /// سعر الكارت لكلّ باقة كما حسبه الخادم.
  Map<int, num> get unitCosts => {
        for (final l in lines)
          if (l.unitCost != null) l.profileId: l.unitCost!,
      };

  static ElCardQuote? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final j = Map<String, dynamic>.from(raw);
    final lines = _rows(j['items'], ElCardQuoteLine.fromJson);
    final total = _numOrNull(j['total']);
    if (total == null) return null;
    final unknown = j['unknown'] is List
        ? (j['unknown'] as List)
            .map(_intOrNull)
            .whereType<int>()
            .toList(growable: false)
        : const <int>[];
    final enough = j['enough'];
    return ElCardQuote(
      lines: lines,
      unknown: unknown,
      total: total,
      expectedTotal: _numOrNull(j['expected_total']) ?? total,
      count: _intOrNull(j['count']) ??
          lines.fold<int>(0, (s, l) => s + l.count),
      balance: _numOrNull(j['balance']),
      after: _numOrNull(j['after']),
      enough: enough is bool ? enough : null,
      note: _str(j['note']),
    );
  }
}

/// نتيجة طلب الكارتات.
///
/// [unclear] = **ربّما أُرسل** الطلب (وخُصم الرصيد): لا ردّ (مهلة/انقطاع)،
/// `ORDER_UNCONFIRMED` من الخادم، أو 5xx لا يقول خادمنا فيه صراحةً إنّه لم
/// يُرسَل. الشاشة لا تعيد الإرسال أبداً، وتطلب مراجعة «سجلّ الطلبات» قبل
/// أيّ طلبٍ آخر.
///
/// [duplicate] = الخادم أعاد نتيجة طلبٍ سابقٍ بالمفتاح نفسه (`request_id`)
/// بلا نداءٍ ثانٍ لايرث لنك. [expectedTotal] = الكلفة الجديدة مع
/// `COST_CHANGED`.
typedef ElCardOrderResult = ({
  bool ok,
  bool unclear,
  String? message,
  String? code,
  bool duplicate,
  num? expectedTotal,
});

// ═════════════════════════ الطلبات ═════════════════════════

class EarthlinkApi {
  EarthlinkApi._();

  /// رمز «أُرسلت هذه الإضافة قبل لحظات» من حارس التكرار في الخادم.
  static const codeRecentDuplicate = 'RECENT_DUPLICATE';

  /// 503 «تعذّر تأكيد الإنشاء»: لا ايرث لنك أكّد ولا إعادة الفحص حسمت —
  /// ربّما أُنشئ. رسالة الخادم تقول راجع القائمة (وسجّل الدين يدويّاً إن ظهر).
  static const codeCreateUnconfirmed = 'CREATE_UNCONFIRMED';

  /// 503 «ايرث لنك لم يستجب» وأثبتت إعادة الفحص أنّه **لم** يُنشأ — فشلٌ
  /// عاديّ تُسمح إعادته.
  static const codeElUnavailable = 'EL_UNAVAILABLE';

  /// 200 `success:false` — الاسم نفسه رُدّ قبل قليل بـ`EL_UNAVAILABLE` وصار
  /// الآن «مستخدماً»: الإنشاء السابق مرّ متأخّراً على الأرجح. رسالة الخادم
  /// تحمل مبلغ الدين وتقول لا تُضِفه باسمٍ آخر ⇒ يُعامَل كـ[codeCreateUnconfirmed]
  /// تماماً (قفل + تحديث القائمة + الرسالة باقية) — لا كـ`USERNAME_TAKEN`.
  static const codeCreateLateSuspected = 'CREATE_LATE_SUSPECTED';

  /// رموز «ربّما أُنشئ» التي تحمل رسالة الخادم — غير مؤكّدةٍ أينما وصلت
  /// (ردّاً أو رميةً)، ورسالتها تُعرض كما هي.
  static bool _maybeCreatedCode(String? code) =>
      code == codeCreateUnconfirmed || code == codeCreateLateSuspected;

  /// GET /api/v2/el/create-options — خيارات شيت «مشترك جديد».
  static Future<({ElCreateOptions? data, String? message})>
      createOptions() async {
    try {
      final r = await ApiClient.dio
          .get<Map<String, dynamic>>('/api/v2/el/create-options');
      final body = r.data ?? const {};
      final data = body['data'];
      if (body['success'] != true || data is! Map) {
        return (data: null, message: _bodyMsg(body, 'تعذّر جلب خيارات الإضافة'));
      }
      return (
        data: ElCreateOptions.fromJson(Map<String, dynamic>.from(data)),
        message: null,
      );
    } on DioException catch (e) {
      _log('el/create-options', e);
      return (data: null, message: _message(e, 'تعذّر جلب خيارات الإضافة'));
    } catch (e) {
      _log('el/create-options', e);
      return (data: null, message: 'تعذّر جلب خيارات الإضافة');
    }
  }

  /// POST /api/v2/el/check-username — هل اسم الدخول متاح؟ `available: null`
  /// = تعذّر الفحص (الخادم يتحقّق مجدّداً عند الإضافة نفسها).
  static Future<({bool? available, String? userId, String? message})>
      checkUsername(String username) async {
    try {
      final r = await ApiClient.dio.post<Map<String, dynamic>>(
        '/api/v2/el/check-username',
        data: {'username': username},
      );
      final body = r.data ?? const {};
      final data = body['data'];
      if (body['success'] != true || data is! Map || data['available'] is! bool) {
        return (available: null, userId: null, message: _str(body['message']));
      }
      final available = data['available'] as bool;
      return (
        available: available,
        userId: _str(data['user_id']),
        // اسمٌ «مستخدم» لأنّ محاولةً سابقة غير مؤكّدة أُنشئت متأخّرة (late_create):
        // نصّ الخادم يقول «لا تُضِفه باسمٍ آخر» — يُعرض بدل «اختر اسماً آخر».
        message: available ? null : _str(data['message']),
      );
    } on DioException catch (e) {
      _log('el/check-username', e);
      return (available: null, userId: null, message: _message(e, 'تعذّر الفحص'));
    } catch (e) {
      _log('el/check-username', e);
      return (available: null, userId: null, message: null);
    }
  }

  /// POST /api/v2/el/card-info — `data: null` = تعذّرت القراءة (شبكة/خادم)
  /// و`message` نصّ الخادم إن أرسله (كـRATE_LIMITED «انتظر دقيقة»)، وإلّا
  /// `null` فيعرض الشيت نصّه المترجم. وغير ذلك `data.valid` يقول صلاح الكارت
  /// وباقته أو سبب رفضه.
  static Future<({ElCardInfo? data, String? message})> cardInfo({
    required String identifier,
    required String pin,
  }) async {
    try {
      final r = await ApiClient.dio.post<Map<String, dynamic>>(
        '/api/v2/el/card-info',
        data: {'card_identifier': identifier, 'card_pin': pin},
      );
      final body = r.data ?? const {};
      final data = body['data'];
      if (body['success'] != true || data is! Map) {
        return (data: null, message: _str(body['message']));
      }
      return (
        data: ElCardInfo.fromJson(Map<String, dynamic>.from(data)),
        message: null,
      );
    } on DioException catch (e) {
      _log('el/card-info', e);
      final b = e.response?.data;
      return (data: null, message: b is Map ? _str(b['message']) : null);
    } catch (e) {
      _log('el/card-info', e);
      return (data: null, message: null);
    }
  }

  /// POST /api/v2/subscribers — إضافة مشترك ايرث لنك.
  ///
  /// [method] `deposit` (رصيد أونلاين + [depositPassword]) · `card`
  /// ([cardIdentifier] + [cardPin]، والكارت يحدّد الباقة) · `test` (تجريبيّ).
  /// [paymentType]/[paidAmount] ما بين المشترك والوكيل — للرصيد والكارت وحدهما.
  ///
  /// ⚠️ لا إعادة إرسال تلقائيّة أبداً: بلا ردّ (مهلة/انقطاع) ⇒ `unclear`،
  /// فربّما أُنشئ المشترك وخُصم الرصيد/الكارت.
  static Future<ElCreateResult> createSubscriber({
    required String method,
    required String username,
    required String password,
    required String firstname,
    required String phone,
    String? lastname,
    Object? profileId,
    String? depositPassword, // null ⇒ المحفوظ بالخادم
    bool rememberDepositPassword = false, // «احفظه» — صاحب الحساب وحده
    String? cardIdentifier,
    String? cardPin,
    String? paymentType,
    num? paidAmount,
  }) async {
    try {
      final r = await ApiClient.dio.post<Map<String, dynamic>>(
        '/api/v2/subscribers',
        data: {
          'method': method,
          'username': username,
          'password': password,
          'firstname': firstname,
          if (lastname != null && lastname.isNotEmpty) 'lastname': lastname,
          'phone': phone,
          if (profileId != null) 'profile_id': profileId,
          if (method == 'deposit' && depositPassword != null)
            'deposit_password': depositPassword,
          if (method == 'deposit' &&
              depositPassword != null &&
              rememberDepositPassword)
            'rememberDepositPassword': true,
          if (method == 'card' && cardIdentifier != null)
            'card_identifier': cardIdentifier,
          if (method == 'card' && cardPin != null) 'card_pin': cardPin,
          if (method != 'test' && paymentType != null)
            'payment_type': paymentType,
          if (method != 'test' && paidAmount != null) 'paid_amount': paidAmount,
        },
        // الإنشاء + الشحن عند ايرث لنك قد يطولان (كالتفعيل): مهلة الثلاثين
        // كانت ستقطع طلباً يكمله الخادم بعدها فيقول التطبيق «تعذّر» والمشترك أُنشئ.
        options: Options(receiveTimeout: const Duration(seconds: 200)),
      );
      if (method == 'deposit') ElDepositPassword.observe(r.data);
      return createResultFromBody(r.data ?? const {});
    } on DioException catch (e) {
      _log('subscribers (POST el)', e);
      if (method == 'deposit') ElDepositPassword.observe(e.response?.data);
      return createResultFromError(e);
    } catch (e) {
      _log('subscribers (POST el)', e);
      // خطأٌ بعد الإرسال (قراءة ردٍّ غير متوقّع) — ربّما نُفّذ: غير مؤكّد.
      return (
        ok: false,
        message: null,
        code: null,
        unclear: true,
        username: null,
        debtWriteFailed: false,
        debtWriteMessage: null,
      );
    }
  }

  /// ردّ الإضافة الذي وصل **ردّاً** (`validateStatus < 500`): نجاحٌ — ولو
  /// أكّدته إعادة الفحص بعد مهلة (`confirmed_by: 'recheck'`، و`idx` قد يغيب)
  /// — أو رفضٌ برمزه (409 RECENT_DUPLICATE، 400 تحقّق/APP_UPDATE_REQUIRED،
  /// 200 success:false + code كـPRICE_UNKNOWN/USERNAME_TAKEN). والاستثناء
  /// `CREATE_LATE_SUSPECTED` (200 success:false): ربّما أُنشئ ⇒ [unclear].
  @visibleForTesting
  static ElCreateResult createResultFromBody(Map<String, dynamic> body) {
    final ok = body['success'] == true;
    final data = body['data'];
    final code = _str(body['code']);
    // أُنشئ (وخرج المال) لكنّ دفترنا لم يُكتب: يُبلَّغ ولا يُلغي النجاح.
    final dw = body['debt_write'];
    final debt = dw is Map ? dw : null;
    final debtFailed = ok && debt != null && debt['ok'] == false;
    return (
      ok: ok,
      message: _str(body['message']),
      code: code,
      unclear: !ok && _maybeCreatedCode(code),
      username: data is Map ? _str(data['username']) : null,
      debtWriteFailed: debtFailed,
      debtWriteMessage: debtFailed ? _str(debt['message']) : null,
    );
  }

  /// فشلٌ وصل **رميةً**: 5xx (`validateStatus < 500`) أو بلا ردٍّ أصلاً.
  /// غير المؤكّد بلا رسالة إلّا `CREATE_UNCONFIRMED`/`CREATE_LATE_SUSPECTED`
  /// (رسالة الخادم تقول ما يُفعل)؛ وغيره يعرض الشيت نصّه — لا «تعذّر» يوحي
  /// بفشلٍ مؤكّد والزرّ مقفل.
  @visibleForTesting
  static ElCreateResult createResultFromError(DioException e) {
    final res = e.response;
    final b = res?.data;
    // غلاف خادمنا {success:false, message} — لا صفحة بوّابة (HTML، أو JSON
    // كلاودفلير `origin_bad_gateway`) لا تقول شيئاً عن الإنشاء.
    final env = b is Map && b['success'] == false ? b : null;
    final code = env == null ? null : _str(env['code']);
    final unclear = createUnclear(
      status: res?.statusCode,
      envelope: env != null,
      code: code,
    );
    final serverMsg = env == null ? null : _str(env['message']);
    return (
      ok: false,
      message: unclear && !_maybeCreatedCode(code) ? null : serverMsg,
      code: code,
      unclear: unclear,
      username: null,
      debtWriteFailed: false,
      debtWriteMessage: null,
    );
  }

  /// فشل إضافةٍ وصل رميةً — هل ربّما أُنشئ المشترك؟ الفشل **المؤكّد** حكم
  /// خادمنا الصريح وحده:
  ///   • `EL_UNAVAILABLE` — أثبتت إعادة الفحص أنّه لم يُنشأ.
  ///   • 503 بغلافنا — رفضٌ قبل الإنشاء («لم يُنشأ المشترك، أعد المحاولة»).
  ///   • رفضٌ 4xx صريح (لا يصل رميةً عادةً).
  /// وما سواه غير مؤكّد: بلا ردّ (مهلة/انقطاع)، `CREATE_UNCONFIRMED`
  /// و`CREATE_LATE_SUSPECTED`، 502/504/524 وأيّ 5xx بلا غلافنا (بوّابةٌ قطعت
  /// طلباً ربّما أكمله الخادم)، و500 مجهول (عطلٌ قد يقع بعد الإنشاء).
  @visibleForTesting
  static bool createUnclear({
    required int? status,
    required bool envelope,
    String? code,
  }) {
    if (status == null) return true;
    if (_maybeCreatedCode(code)) return true;
    if (code == codeElUnavailable) return false;
    if (status < 500) return false;
    return !(status == 503 && envelope);
  }

  /// GET /api/v2/el/transfer-targets — الموزّعون الذين يُحوَّل لهم.
  static Future<({List<ElTransferTarget> items, String? message})>
      transferTargets() async {
    try {
      final r = await ApiClient.dio
          .get<Map<String, dynamic>>('/api/v2/el/transfer-targets');
      final body = r.data ?? const {};
      if (body['success'] != true) {
        return (
          items: const <ElTransferTarget>[],
          message: _bodyMsg(body, 'تعذّر جلب وجهات التحويل'),
        );
      }
      return (items: _rows(body['data'], ElTransferTarget.fromJson), message: null);
    } on DioException catch (e) {
      _log('el/transfer-targets', e);
      return (
        items: const <ElTransferTarget>[],
        message: _message(e, 'تعذّر جلب وجهات التحويل'),
      );
    } catch (e) {
      _log('el/transfer-targets', e);
      return (items: const <ElTransferTarget>[], message: 'تعذّر جلب وجهات التحويل');
    }
  }

  /// POST /api/v2/el/transfer — تحويل مبلغٍ لموزّعٍ آخر بكلمة سرّ الإيداع
  /// ([depositPassword] null ⇒ المحفوظ بالخادم).
  static Future<({bool ok, String? message})> transfer({
    required num amount,
    required int targetAffiliateIndex,
    String? depositPassword,
    bool rememberDepositPassword = false,
  }) async {
    try {
      final r = await ApiClient.dio.post<Map<String, dynamic>>(
        '/api/v2/el/transfer',
        data: {
          'amount': amount,
          'targetAffiliateIndex': targetAffiliateIndex,
          if (depositPassword != null && depositPassword.isNotEmpty)
            'depositPassword': depositPassword,
          if (rememberDepositPassword &&
              depositPassword != null &&
              depositPassword.isNotEmpty)
            'rememberDepositPassword': true,
        },
      );
      final body = r.data ?? const {};
      ElDepositPassword.observe(body);
      return (
        ok: body['success'] == true,
        message: _str(body['message']),
      );
    } on DioException catch (e) {
      _log('el/transfer', e);
      ElDepositPassword.observe(e.response?.data);
      return (ok: false, message: _message(e, 'تعذّر إتمام التحويل'));
    } catch (e) {
      _log('el/transfer', e);
      return (ok: false, message: 'تعذّر إتمام التحويل');
    }
  }

  /// POST /api/v2/el/account-statement — كشف حساب الإيداع. POST لا GET: باسورد
  /// الإيداع (يأذن بتحويل الرصيد) في الجسم لا في الرابط — الرابط يُحفظ في سجلّات
  /// الخادم/الوسطاء نصّاً صريحاً.
  static Future<({List<ElStatementEntry> items, int total, String? message})>
      accountStatement({
    String? depositPassword, // null ⇒ المحفوظ بالخادم
    bool rememberDepositPassword = false,
    int startIndex = 0,
    int rowCount = 50,
  }) async {
    try {
      final r = await ApiClient.dio.post<Map<String, dynamic>>(
        '/api/v2/el/account-statement',
        data: {
          if (depositPassword != null && depositPassword.isNotEmpty)
            'depositPassword': depositPassword,
          if (rememberDepositPassword &&
              depositPassword != null &&
              depositPassword.isNotEmpty)
            'rememberDepositPassword': true,
          'startIndex': startIndex,
          'rowCount': rowCount,
        },
      );
      final body = r.data ?? const {};
      ElDepositPassword.observe(body);
      if (body['success'] != true) {
        return (
          items: const <ElStatementEntry>[],
          total: 0,
          message: _bodyMsg(body, 'تعذّر جلب كشف الحساب'),
        );
      }
      final items = _rows(body['data'], ElStatementEntry.fromJson);
      return (items: items, total: _intOrNull(body['total']) ?? items.length, message: null);
    } on DioException catch (e) {
      _log('el/account-statement', e);
      ElDepositPassword.observe(e.response?.data);
      return (
        items: const <ElStatementEntry>[],
        total: 0,
        message: _message(e, 'تعذّر جلب كشف الحساب'),
      );
    } catch (e) {
      _log('el/account-statement', e);
      return (items: const <ElStatementEntry>[], total: 0, message: 'تعذّر جلب كشف الحساب');
    }
  }

  /// GET /api/v2/el/prepaid-needed?days=N — الكارتات المطلوبة لكلّ باقة خلال
  /// المدّة (الخادم يحصرها 1..90؛ الشاشة تطلب 1 · 3 · 7 · 30). الفشل يصل
  /// 503 برسالةٍ عربيّة ⇒ رميةٌ نقرأ رسالتها من الجسم.
  static Future<({List<ElNeededCard> items, String? message})> prepaidNeeded({
    required int days,
  }) async {
    try {
      final r = await ApiClient.dio.get<Map<String, dynamic>>(
        '/api/v2/el/prepaid-needed',
        queryParameters: {'days': days},
      );
      final body = r.data ?? const {};
      if (body['success'] != true) {
        return (
          items: const <ElNeededCard>[],
          message: _bodyMsg(body, 'تعذّر جلب الكارتات المطلوبة'),
        );
      }
      return (items: _rows(body['data'], ElNeededCard.fromJson), message: null);
    } on DioException catch (e) {
      _log('el/prepaid-needed', e);
      return (
        items: const <ElNeededCard>[],
        message: _message(e, 'تعذّر جلب الكارتات المطلوبة'),
      );
    } catch (e) {
      _log('el/prepaid-needed', e);
      return (items: const <ElNeededCard>[], message: 'تعذّر جلب الكارتات المطلوبة');
    }
  }

  /// GET /api/v2/subscribers/:idx/account-password — كلمة سرّ حساب البوّابة،
  /// وهي **مميّزةٌ عن كلمة سرّ الخدمة**. ايرث لنك وحدها؛ `null` عند التعذّر
  /// (شبكة/صلاحيّة) فيبقى الحقل فارغاً ويقدر المدير ضبط قيمةٍ جديدة.
  static Future<String?> fetchAccountPassword(String idx) async {
    try {
      final r = await ApiClient.dio.get<Map<String, dynamic>>(
        '/api/v2/subscribers/$idx/account-password',
      );
      final body = r.data ?? const {};
      if (body['success'] != true) return null;
      final data = body['data'];
      if (data is Map) {
        return _str(data['account_password']) ??
            _str(data['password']) ??
            _str(data['accountPassword']);
      }
      return _str(body['account_password']) ?? _str(body['password']);
    } on DioException catch (e) {
      _log('el account-password GET/$idx', e);
      return null;
    } catch (e) {
      _log('el account-password GET/$idx', e);
      return null;
    }
  }

  /// POST /api/v2/subscribers/:idx/account-password — تغيير كلمة سرّ الحساب.
  /// نرسل المفتاحين (`password`/`account_password`) تحصّناً من اختلاف اسم
  /// الحقل المتوقَّع في الخادم؛ المُهمَل منهما لا يضرّ.
  static Future<({bool ok, String? message})> setAccountPassword({
    required String idx,
    required String password,
  }) async {
    try {
      final r = await ApiClient.dio.post<Map<String, dynamic>>(
        '/api/v2/subscribers/$idx/account-password',
        data: {'password': password, 'account_password': password},
      );
      final body = r.data ?? const {};
      return (ok: body['success'] == true, message: _str(body['message']));
    } on DioException catch (e) {
      _log('el account-password POST/$idx', e);
      return (ok: false, message: _message(e, 'تعذّر تغيير كلمة سرّ الحساب'));
    } catch (e) {
      _log('el account-password POST/$idx', e);
      return (ok: false, message: 'تعذّر تغيير كلمة سرّ الحساب');
    }
  }

  /// GET /api/v2/el/test-usage — المشتركون على التجريبيّ واستهلاكهم (قراءة فقط).
  static Future<({List<ElTestUsageRow> items, String? message})>
      testUsage() async {
    try {
      final r = await ApiClient.dio
          .get<Map<String, dynamic>>('/api/v2/el/test-usage');
      final body = r.data ?? const {};
      if (body['success'] != true) {
        return (
          items: const <ElTestUsageRow>[],
          message: _bodyMsg(body, 'تعذّر جلب استخدام التجريبيّ'),
        );
      }
      return (
        items: _rows(_pickList(body['data']), ElTestUsageRow.fromJson),
        message: null,
      );
    } on DioException catch (e) {
      _log('el/test-usage', e);
      return (
        items: const <ElTestUsageRow>[],
        message: _message(e, 'تعذّر جلب استخدام التجريبيّ'),
      );
    } catch (e) {
      _log('el/test-usage', e);
      return (
        items: const <ElTestUsageRow>[],
        message: 'تعذّر جلب استخدام التجريبيّ',
      );
    }
  }

  /// GET /api/v2/el/audit?rowcount=N — آخر حركات حساب ايرث لنك (قراءة فقط).
  static Future<({List<ElAuditRow> items, String? message})> audit({
    int rowCount = 100,
  }) async {
    try {
      final r = await ApiClient.dio.get<Map<String, dynamic>>(
        '/api/v2/el/audit',
        queryParameters: {'rowcount': rowCount},
      );
      final body = r.data ?? const {};
      if (body['success'] != true) {
        return (
          items: const <ElAuditRow>[],
          message: _bodyMsg(body, 'تعذّر جلب السجلّ'),
        );
      }
      return (
        items: _rows(_pickList(body['data']), ElAuditRow.fromJson),
        message: null,
      );
    } on DioException catch (e) {
      _log('el/audit', e);
      return (
        items: const <ElAuditRow>[],
        message: _message(e, 'تعذّر جلب السجلّ'),
      );
    } catch (e) {
      _log('el/audit', e);
      return (items: const <ElAuditRow>[], message: 'تعذّر جلب السجلّ');
    }
  }

  /// GET /api/v2/el/by-package — توزيع المشتركين على الباقات (قراءة فقط).
  /// يُرتَّب تنازليّاً بالعدد — الأكثر اشتراكاً أوّلاً.
  static Future<({List<ElPackageCount> items, String? message})>
      byPackage() async {
    try {
      final r = await ApiClient.dio
          .get<Map<String, dynamic>>('/api/v2/el/by-package');
      final body = r.data ?? const {};
      if (body['success'] != true) {
        return (
          items: const <ElPackageCount>[],
          message: _bodyMsg(body, 'تعذّر جلب المشتركين حسب الباقة'),
        );
      }
      final items = _rows(_pickList(body['data']), ElPackageCount.fromJson);
      final sorted = [...items]..sort((a, b) => b.count.compareTo(a.count));
      return (items: List<ElPackageCount>.unmodifiable(sorted), message: null);
    } on DioException catch (e) {
      _log('el/by-package', e);
      return (
        items: const <ElPackageCount>[],
        message: _message(e, 'تعذّر جلب المشتركين حسب الباقة'),
      );
    } catch (e) {
      _log('el/by-package', e);
      return (
        items: const <ElPackageCount>[],
        message: 'تعذّر جلب المشتركين حسب الباقة',
      );
    }
  }

  /// سجلّ طلبات الكارتات (صاحب الحساب وحده؛ الموظّف يُردّ بـ403) — قراءةٌ
  /// فقط، والأحدث أوّلاً كما يرسله الخادم.
  ///
  /// الخادم يقرؤه بباسورد الإيداع المحفوظ (كتطبيق ايرث لنك الرسميّ)؛ وحين لا
  /// محفوظ يردّ `DEPOSIT_PASSWORD_REQUIRED` فيُكتب في حقل الشاشة ويُعاد:
  /// [depositPassword] المكتوب يُرسَل في **جسم** POST لا في الرابط (كـكشف
  /// الحساب)، وبلاه GET كما كان.
  static Future<({List<ElCardOrder> items, String? message})> cardOrders({
    String? depositPassword,
  }) async {
    try {
      final pw = depositPassword?.trim() ?? '';
      final r = pw.isEmpty
          ? await ApiClient.dio
              .get<Map<String, dynamic>>('/api/v2/el/card-orders')
          : await ApiClient.dio.post<Map<String, dynamic>>(
              '/api/v2/el/card-orders',
              data: {'depositPassword': pw},
            );
      final body = r.data ?? const {};
      // محفوظٌ رفضته ايرث لنك ⇒ مُسح عند الخادم؛ الحقل يعود يطلبه.
      ElDepositPassword.observe(body);
      if (body['success'] != true) {
        return (
          items: const <ElCardOrder>[],
          message: _bodyMsg(body, 'تعذّر جلب سجلّ طلبات الكارتات'),
        );
      }
      return (
        items: _rows(_pickList(body['data']), ElCardOrder.fromJson),
        message: null,
      );
    } on DioException catch (e) {
      _log('el/card-orders', e);
      return (
        items: const <ElCardOrder>[],
        message: _message(e, 'تعذّر جلب سجلّ طلبات الكارتات'),
      );
    } catch (e) {
      _log('el/card-orders', e);
      return (
        items: const <ElCardOrder>[],
        message: 'تعذّر جلب سجلّ طلبات الكارتات',
      );
    }
  }

  /// GET /api/v2/packages — باقات الموزّع كلّها (مصدر «طلب الكارتات»: ما يقبله
  /// تقدير الخادم وطلبه — قائمة ايرث لنك نفسها). الاسم والمعرّف وحدهما.
  static Future<({List<({int id, String name})> items, String? message})>
      orderPackages() async {
    try {
      final r = await ApiClient.dio.get<Map<String, dynamic>>('/api/v2/packages');
      final body = r.data ?? const {};
      if (body['success'] != true) {
        return (
          items: const <({int id, String name})>[],
          message: _bodyMsg(body, 'تعذّر جلب الباقات'),
        );
      }
      final out = <({int id, String name})>[];
      for (final m in _pickList(body['data']).whereType<Map>()) {
        final id = _intOrNull(m['id'] ?? m['profile_id']);
        if (id == null || id <= 0) continue;
        out.add((id: id, name: _str(m['name']) ?? 'باقة #$id'));
      }
      return (items: List<({int id, String name})>.unmodifiable(out), message: null);
    } on DioException catch (e) {
      _log('v2/packages (el order)', e);
      return (
        items: const <({int id, String name})>[],
        message: _message(e, 'تعذّر جلب الباقات'),
      );
    } catch (e) {
      _log('v2/packages (el order)', e);
      return (items: const <({int id, String name})>[], message: 'تعذّر جلب الباقات');
    }
  }

  /// رمز «طلبتَ الكارتات نفسها قبل قليل» (409) — لم يُرسَل؛ يُعاد بـ`confirmRepeat`.
  static const codeOrderRepeat = 'RECENT_DUPLICATE';

  /// رمز «تغيّرت الكلفة منذ المراجعة» (409) — لم يُرسَل؛ يُعاد التقدير.
  static const codeCostChanged = 'COST_CHANGED';

  /// رمز «لم يصل ردّ ايرث لنك — ربّما أُرسل» (502).
  static const codeOrderUnconfirmed = 'ORDER_UNCONFIRMED';

  /// رمز «المفتاح نفسه بعد نتيجةٍ غامضة» (409) — **لم يُرسَل** هذا الطلب، والسابق
  /// ربّما وصل. طلبٌ جديدٌ فعلاً = إقرارٌ صريح بمفتاحٍ جديد.
  static const codeOrderUnresolved = 'ORDER_UNRESOLVED';

  /// رمز «في سجلّ ايرث لنك طلبٌ بعد المحاولة الغامضة (أو لم يُجزم)» (409) — لم
  /// يُرسَل طلبٌ ثانٍ.
  static const codeOrderMaybePlaced = 'ORDER_MAYBE_PLACED';

  /// رمز «طلب الكروت موقوفٌ مؤقّتاً» (503) — مفتاح الإيقاف عند الخادم
  /// (`pro_settings` «el_card_order»)، للتقدير والطلب معاً: لم يُرسَل شيء.
  /// الباب يتبعه (`ElCardOrderGate`).
  static const codeCardOrderOff = 'CARD_ORDER_OFF';

  /// POST /api/v2/el/card-order/quote — تقدير الطلب قبل تأكيده (قراءةٌ بلا أثر،
  /// صاحب الحساب وحده). `PACKAGE_UNKNOWN` يصل 400 ومعه التقدير الجزئيّ في
  /// `data` — فيُقرأ منه ما عُرف سعره.
  static Future<({ElCardQuote? data, String? message, String? code})>
      quoteCardOrder(List<ElCardOrderItem> items) async {
    try {
      final r = await ApiClient.dio.post<Map<String, dynamic>>(
        '/api/v2/el/card-order/quote',
        data: {
          'cards': [
            for (final i in items)
              if (i.count > 0) {'profile_id': i.profileId, 'count': i.count},
          ],
        },
      );
      final body = r.data ?? const {};
      final q = ElCardQuote.fromJson(body['data']);
      if (body['success'] != true) {
        return (
          data: q,
          message: _bodyMsg(body, 'تعذّر حساب كلفة الطلب'),
          code: _str(body['code']),
        );
      }
      if (q == null) {
        return (data: null, message: 'تعذّر حساب كلفة الطلب', code: null);
      }
      return (data: q, message: null, code: null);
    } on DioException catch (e) {
      _log('el/card-order/quote', e);
      final b = e.response?.data;
      return (
        data: null,
        message: _message(e, 'تعذّر حساب كلفة الطلب'),
        code: b is Map ? _str(b['code']) : null,
      );
    } catch (e) {
      _log('el/card-order/quote', e);
      return (data: null, message: 'تعذّر حساب كلفة الطلب', code: null);
    }
  }

  /// POST /api/v2/el/card-order — طلب كارتات من ايرث لنك **يُخصم من رصيد
  /// الإيداع** (صاحب الحساب وحده).
  ///
  /// ⚠️ مالٌ حقيقيّ: نداءٌ واحد بلا أيّ إعادة تلقائيّة، ومهلةٌ طويلة (الخادم
  /// يتحقّق من الكلفة ثمّ ينتظر ايرث لنك حتى ٩٠ث) فلا يقطع التطبيق طلباً يكمله
  /// الخادم بعده.
  ///  • [expectedTotal] إلزاميّ: مجموع التقدير الذي راجعه المالك — الخادم يرفض
  ///    إن تغيّرت الكلفة (`COST_CHANGED`).
  ///  • [requestId] مفتاح الطلب = طلبٌ واحد: إعادته بعد نجاحٍ تُرجع النتيجة الأولى
  ///    (`duplicate:true`)، وبعد نتيجةٍ غامضة يرفضه الخادم (`ORDER_UNRESOLVED`)
  ///    ولو مع [confirmRepeat] — بلا طلبٍ ثانٍ في الحالين.
  ///  • [confirmRepeat] إقرار المالك بطلبٍ ثانٍ للكارتات نفسها (١٠ دقائق بعد نجاح،
  ///    ساعة بعد غموض) — **بمفتاحٍ جديد** دائماً.
  static Future<ElCardOrderResult> placeCardOrder({
    required List<ElCardOrderItem> items,
    required String requestId,
    required num expectedTotal,
    bool confirmRepeat = false,
    String? depositPassword, // null ⇒ المحفوظ بالخادم
    bool rememberDepositPassword = false,
  }) async {
    try {
      final r = await ApiClient.dio.post<Map<String, dynamic>>(
        '/api/v2/el/card-order',
        data: {
          'cards': [
            for (final i in items)
              if (i.count > 0) {'profile_id': i.profileId, 'count': i.count},
          ],
          'expected_total': expectedTotal,
          'request_id': requestId,
          if (confirmRepeat) 'confirmRepeat': true,
          if (depositPassword != null && depositPassword.isNotEmpty)
            'depositPassword': depositPassword,
          if (rememberDepositPassword &&
              depositPassword != null &&
              depositPassword.isNotEmpty)
            'rememberDepositPassword': true,
        },
        options: Options(receiveTimeout: const Duration(seconds: 150)),
      );
      final body = r.data ?? const {};
      ElDepositPassword.observe(body);
      return cardOrderResultFromBody(body);
    } on DioException catch (e) {
      _log('el/card-order', e);
      ElDepositPassword.observe(e.response?.data);
      return cardOrderResultFromError(e);
    } catch (e) {
      _log('el/card-order', e);
      // خطأٌ بعد الإرسال (قراءة ردٍّ غير متوقّع) — ربّما نُفّذ: غير مؤكّد.
      return (
        ok: false,
        unclear: true,
        message: null,
        code: null,
        duplicate: false,
        expectedTotal: null,
      );
    }
  }

  /// رموزٌ تعني «ربّما أُرسل» حين يصوغها الخادم صراحةً.
  static bool _orderMaybeSentCode(String? code) =>
      code == codeOrderUnconfirmed || code == 'CARD_ORDER_UNCONFIRMED';

  static num? _costChangedTotal(Object? body) {
    if (body is! Map) return null;
    final d = body['data'];
    return d is Map ? _numOrNull(d['expected_total']) : null;
  }

  /// ردّ الطلب الذي وصل **ردّاً** (`validateStatus < 500`): نجاحٌ (أو نتيجة
  /// طلبٍ سابقٍ بالمفتاح نفسه)، أو رفضٌ صريحٌ قبل الإرسال لايرث لنك (تحقّق ·
  /// باسورد · تكرار · كلفةٌ تغيّرت · طلبٌ جارٍ · رفض ايرث لنك بلا خصم).
  @visibleForTesting
  static ElCardOrderResult cardOrderResultFromBody(Map<String, dynamic> body) {
    final ok = body['success'] == true;
    final code = _str(body['code']);
    return (
      ok: ok,
      unclear: !ok && _orderMaybeSentCode(code),
      message: _str(body['message']),
      code: code,
      duplicate: ok && body['duplicate'] == true,
      expectedTotal: code == codeCostChanged ? _costChangedTotal(body) : null,
    );
  }

  /// فشلٌ وصل **رميةً**: 5xx أو بلا ردٍّ أصلاً. الفشل المؤكَّد حكم خادمنا
  /// الصريح وحده: 503 بغلافنا (رفضٌ **قبل** نداء المال — توكنٌ غير متوفّر أو
  /// تعذّر التحقّق من الكلفة)، و`EL_UNAVAILABLE`. وما سواه ربّما أُرسل:
  /// `ORDER_UNCONFIRMED` (502)، مهلةٌ أو انقطاع، بوّابةٌ بلا غلافنا
  /// (502/504/524)، أو 500 مجهول.
  @visibleForTesting
  static ElCardOrderResult cardOrderResultFromError(DioException e) {
    final res = e.response;
    final b = res?.data;
    final env = b is Map && b['success'] == false ? b : null;
    final code = env == null ? null : _str(env['code']);
    final status = res?.statusCode;
    final bool unclear;
    if (status == null) {
      unclear = true; // لا ردّ: مهلة/انقطاع
    } else if (_orderMaybeSentCode(code)) {
      unclear = true;
    } else if (code == codeElUnavailable) {
      unclear = false;
    } else if (status < 500) {
      unclear = false;
    } else {
      unclear = !(status == 503 && env != null);
    }
    return (
      ok: false,
      unclear: unclear,
      message: env == null ? null : _str(env['message']),
      code: code,
      duplicate: false,
      expectedTotal: code == codeCostChanged ? _costChangedTotal(env) : null,
    );
  }

  static String _bodyMsg(Map<String, dynamic> body, String fallback) =>
      _str(body['message']) ?? fallback;

  static String _message(DioException e, String fallback) {
    final b = e.response?.data;
    final m = b is Map ? _str(b['message']) : null;
    return m ?? fallback;
  }

  static void _log(String endpoint, Object err) {
    if (kReleaseMode) return;
    if (err is DioException) {
      debugPrint('🔴 $endpoint: status=${err.response?.statusCode} type=${err.type.name}');
    } else {
      debugPrint('🔴 $endpoint: $err');
    }
  }
}
