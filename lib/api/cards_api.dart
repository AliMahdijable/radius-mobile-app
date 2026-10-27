import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../core/util/error_text.dart';
import '../core/util/server_time.dart';
import 'api_client.dart';

/// «الكارتات» — التفعيل التلقائيّ بالكارت ومخزون الوكيل (البند ٤ §١٢).
///
/// الخادم وحده يلمس الكارتات: يختار كارتاً غير مستعمل من مخزون الوكيل
/// يطابق باقة المشترك ويفعّل به. التطبيق لا يحسب ولا يختار — يقرأ ما يعيده
/// الخادم في activation-data و`/api/v2/cards/*` و`admin-widgets`.
///
/// ⚠️ **لا سرّ في هذا الملفّ.** رقم الـPIN لا يصل الموبايل أبداً، ولا الرقم
/// التسلسليّ الكامل — آخر أربع خانات (`serial_tail`) فقط، وحتّى هذه تُقصّ
/// هنا لو وصلت أطول (دفاعٌ ثانٍ لا يفترض أنّ الخادم لا يخطئ). ولا يُطبع
/// جسم أيّ ردٍّ من مسارات الكارتات في السجلّ.

num _num(Object? v) =>
    v is num ? v : num.tryParse(v?.toString().replaceAll(',', '') ?? '') ?? 0;

/// رقمٌ أو `null` — والـ`null` هنا معنى لا عطل: «تعذّرت القراءة».
int? _intOrNull(Object? v) {
  if (v == null || v is bool) return null;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return num.tryParse(v.toString().replaceAll(',', '').trim())?.toInt();
}

int _int(Object? v) => _intOrNull(v) ?? 0;

/// عددٌ لا يكون سالباً — السالب خطأ بيانات، فيُقرأ «غير معروف» لا صفراً.
int? _countOrNull(Object? v) {
  final n = _intOrNull(v);
  return (n == null || n < 0) ? null : n;
}

String? _str(Object? v) {
  final s = v?.toString().trim();
  return (s == null || s.isEmpty) ? null : s;
}

/// الساس يرسل 0/1 والخادم true/false — كلاهما مقبول.
bool _bool(Object? v) => v == true || v == 1 || v == '1' || v == 'true';

Map<String, dynamic> _map(Object? v) =>
    v is Map ? Map<String, dynamic>.from(v) : const <String, dynamic>{};

List<T> _rows<T>(Object? v, T? Function(Map<String, dynamic>) parse) =>
    v is List
        ? v
            .whereType<Map>()
            .map((m) => parse(Map<String, dynamic>.from(m)))
            .whereType<T>()
            .toList(growable: false)
        : List<T>.empty();

/// آخر أربع خانات لا أكثر — مهما وصل من الخادم.
String? _tail(Object? v) {
  final s = _str(v);
  if (s == null) return null;
  return s.length > 4 ? s.substring(s.length - 4) : s;
}

/// الرقم التسلسليّ الكامل (أرقام/حروف مطبوعة) — طلب المالك ٢٧ أكتوبر: «عرض الأرقام لكلّ سلسلة». يُعرض لصاحب صلاحيّة
/// عرض الكارتات؛ ليس سرّاً كالـPIN. فارغٌ أو غير صالح ⇒ null.
String? _serial(Object? v) {
  final s = _str(v)?.trim();
  if (s == null || s.isEmpty) return null;
  return RegExp(r'^[0-9A-Za-z-]{1,40}$').hasMatch(s) ? s : null;
}

// ═════════════════════════ activation-data ═════════════════════════

/// طرق التفعيل المسموحة للمدير — `activation_methods` في activation-data.
///
/// ⚠️ الافتراض حين يغيب الحقل هو **سلوك اليوم حرفيّاً**: خادمٌ لا يعرف
/// الكارت لا يرسله، فيبقى التفعيل بالرصيد ولا يظهر خيار الكارت. والكارت
/// لا يظهر إلّا بـ`true` صريحة — مالٌ حقيقيّ لا يُستنتَج من غياب.
class ActivationMethods {
  const ActivationMethods({required this.credit, required this.card});

  /// `prm_users_activate_credit` — الخصم من رصيد المدير في الساس.
  final bool credit;

  /// `prm_users_activate_card` ومعها سلاسل كارتات — السحب من المخزون.
  final bool card;

  /// خادمٌ أقدم أو ردٌّ بلا الحقل: رصيدٌ بلا خيار.
  static const legacy = ActivationMethods(credit: true, card: false);

  /// الطريقان مسموحان ⇒ بلاطتا «رصيد | كارت» والرصيد مختار.
  bool get canChoose => credit && card;

  /// الكارت وحده ⇒ يُختار تلقائيّاً بلا بلاطات.
  bool get cardOnly => card && !credit;

  static ActivationMethods fromJson(Object? raw) {
    if (raw is! Map) return legacy;
    return ActivationMethods(
      // غياب الرصيد أو null = كما اليوم (مسموح). `false` الصريحة وحدها
      // تمنعه — فلا يُفرض «الكارت وحده» من حقلٍ ناقص.
      credit: raw['credit'] == null || _bool(raw['credit']),
      card: _bool(raw['card']),
    );
  }

  static ActivationMethods fromActivationData(Map<String, dynamic>? data) =>
      fromJson(data?['activation_methods']);
}

/// حال مخزون الكارتات لباقة المشترك — ما يقرّر سطر الكارت في الشيت.
enum CardStockLevel {
  /// كارتٌ واحد على الأقلّ.
  available,

  /// الخادم قرأ المخزون ووجده صفراً — التفعيل بالكارت يُمنع.
  empty,

  /// تعذّرت القراءة — **ليس صفراً**؛ التفعيل مسموح والخادم يعيد القراءة.
  unknown,
}

/// مخزون كارتات الوكيل **لباقة هذا المشترك** — `cards` في activation-data.
class CardStockInfo {
  const CardStockInfo({
    required this.enabled,
    this.profileId,
    this.profileName,
    this.available,
  });

  final bool enabled;
  final int? profileId;
  final String? profileName;

  /// غير المستعمل لهذه الباقة (من السلاسل غير المعلّقة وغير المنتهية).
  /// `null` = تعذّرت القراءة — **لا صفر كاذب**: الخادم يرسل null حين لا
  /// يعرف، والتطبيق لا يحوّله صفراً.
  final int? available;

  static const none = CardStockInfo(enabled: false);

  CardStockLevel get level => switch (available) {
        null => CardStockLevel.unknown,
        0 => CardStockLevel.empty,
        _ => CardStockLevel.available,
      };

  /// نسخةٌ بعددٍ جديد — بعد رفض `NO_CARDS` يصير صفراً بلا إعادة قراءة.
  CardStockInfo withAvailable(int? n) => CardStockInfo(
        enabled: enabled,
        profileId: profileId,
        profileName: profileName,
        available: n,
      );

  static CardStockInfo fromJson(Object? raw) {
    if (raw is! Map) return none;
    return CardStockInfo(
      enabled: _bool(raw['enabled']),
      profileId: _intOrNull(raw['profile_id']),
      profileName: _str(raw['profile_name']),
      available: _countOrNull(raw['available']),
    );
  }

  static CardStockInfo fromActivationData(Map<String, dynamic>? data) =>
      fromJson(data?['cards']);
}

/// الكارت الذي فعّل به الخادم — `card` في ردّ activate الناجح.
class ActivationCard {
  const ActivationCard({
    this.series,
    this.serialTail,
    this.profileName,
    this.remaining,
  });

  final String? series;

  /// آخر أربع خانات من الرقم التسلسليّ — للتعرّف عليه لا لاستعماله.
  final String? serialTail;
  final String? profileName;

  /// ما بقي لهذه الباقة بعد السحب. `null` = غير معروف.
  final int? remaining;

  static ActivationCard? fromJson(Object? raw) {
    if (raw is! Map) return null;
    return ActivationCard(
      series: _str(raw['series']),
      serialTail: _tail(raw['serial_tail']),
      profileName: _str(raw['profile_name']),
      remaining: _countOrNull(raw['remaining']),
    );
  }
}

// ═════════════════════════ قسم «الكارتات» ═════════════════════════

/// مجاميع المخزون كلّه — `totals` في /cards/summary.
class CardsTotals {
  const CardsTotals({
    this.remaining = 0,
    this.used = 0,
    this.qty = 0,
    this.series = 0,
  });

  final int remaining;
  final int used;
  final int qty;

  /// عدد السلاسل.
  final int series;

  static const zero = CardsTotals();

  static CardsTotals fromJson(Object? raw) {
    final m = _map(raw);
    return CardsTotals(
      remaining: _int(m['remaining']),
      used: _int(m['used']),
      qty: _int(m['qty']),
      series: _int(m['series']),
    );
  }
}

/// مخزون باقةٍ واحدة — صفٌّ في `profiles` (المتبقّي تنازليّاً ثمّ الاسم).
class CardProfileStock {
  const CardProfileStock({
    required this.profileId,
    required this.profileName,
    required this.value,
    required this.remaining,
    required this.qty,
    required this.used,
    required this.series,
  });

  final int profileId;
  final String profileName;

  /// قيمة الكارت بالدينار.
  final num value;
  final int remaining;
  final int qty;
  final int used;

  /// عدد السلاسل لهذه الباقة.
  final int series;

  static CardProfileStock? fromJson(Map<String, dynamic> j) {
    final id = _intOrNull(j['profile_id']);
    if (id == null) return null;
    return CardProfileStock(
      profileId: id,
      profileName: _str(j['profile_name']) ?? '#$id',
      value: _num(j['value']),
      remaining: _int(j['remaining']),
      qty: _int(j['qty']),
      used: _int(j['used']),
      series: _int(j['series']),
    );
  }
}

/// سلسلة كارتات — صفٌّ في `series` (الأحدث أوّلاً)، ورأس صفحة كارتاتها.
class CardSeries {
  const CardSeries({
    required this.series,
    required this.type,
    required this.profileId,
    required this.profileName,
    required this.value,
    required this.qty,
    required this.used,
    required this.remaining,
    required this.expiration,
    required this.expired,
    required this.suspended,
    required this.createdAt,
  });

  /// رقم السلسلة كما في الساس — «2026-52224».
  final String series;

  /// 0 = كارت تعبئة، 1 = مستخدم مسبق الدفع.
  final int type;
  final int? profileId;
  final String? profileName;
  final num value;
  final int qty;
  final int used;

  /// الساس لا يرسل «متبقٍّ»: الخادم يحسبه qty − used، ونحسبه نحن إن غاب.
  final int remaining;

  /// تاريخ الانتهاء نصّاً كما في الساس — «2027-09-01».
  final String? expiration;
  final bool expired;
  final bool suspended;

  /// تاريخ إنشاء السلسلة نصّاً بتوقيت الساس — «2026-10-01 23:31:35».
  final String? createdAt;

  bool get isRefill => type == 0;

  /// يُسحب منها؟ لا المعلّقة ولا المنتهية ولا الفارغة.
  bool get usable => !expired && !suspended && remaining > 0;

  /// تواريخ الساس بتوقيت بغداد — تُقرأ محلّيّةً (انظر `server_time.dart`).
  DateTime? get expirationDate => parseSasLocal(expiration);
  DateTime? get createdAtDate => parseSasLocal(createdAt);

  static CardSeries? fromJson(Map<String, dynamic> j) {
    final series = _str(j['series']);
    if (series == null) return null;
    final qty = _int(j['qty']);
    final used = _int(j['used']);
    return CardSeries(
      series: series,
      type: _int(j['type']),
      profileId: _intOrNull(j['profile_id']),
      profileName: _str(j['profile_name']),
      value: _num(j['value']),
      qty: qty,
      used: used,
      remaining: _countOrNull(j['remaining']) ?? math.max(0, qty - used),
      expiration: _str(j['expiration']),
      expired: _bool(j['expired']),
      suspended: _bool(j['suspended']),
      createdAt: _str(j['created_at']),
    );
  }
}

/// كارتٌ في سلسلة — **بلا PIN وبلا رقمٍ تسلسليّ كامل**، والنموذج لا يملك
/// حقلاً لأيٍّ منهما أصلاً.
class CardItem {
  const CardItem({
    required this.id,
    required this.serial,
    required this.serialTail,
    required this.used,
    required this.usedAt,
    required this.subscriberId,
    required this.subscriberUsername,
  });

  final int id;

  /// الرقم التسلسليّ الكامل (قرار المالك: يُعرض)، أو null حين لا يُرسله الخادم (إصدارٌ أقدم).
  final String? serial;

  /// آخر أربع خانات — بديلٌ حين يغيب الكامل.
  final String? serialTail;
  final bool used;

  /// متى استُعمل — نصّاً بتوقيت الساس.
  final String? usedAt;

  /// رقم المشترك في الساس (= `idx` في التطبيق) — لمن ذهب الكارت.
  final String? subscriberId;
  final String? subscriberUsername;

  DateTime? get usedAtDate => parseSasLocal(usedAt);

  static CardItem? fromJson(Map<String, dynamic> j) {
    final id = _intOrNull(j['id']);
    if (id == null) return null;
    final sub = _map(j['subscriber']);
    final usedAt = _str(j['used_at']);
    final subscriberId = _str(sub['id']);
    return CardItem(
      id: id,
      serial: _serial(j['serial']),
      serialTail: _tail(j['serial_tail']),
      // غير المستعمل في الساس: used_at فارغ ولا مشترك. والخادم يحسم
      // بـ`used` — نقرؤه أوّلاً ونستنتج فقط حين يغيب.
      used: j.containsKey('used')
          ? _bool(j['used'])
          : (usedAt != null || subscriberId != null),
      usedAt: usedAt,
      subscriberId: subscriberId,
      subscriberUsername: _str(sub['username']),
    );
  }
}

/// صفحةٌ من كارتات سلسلة — غير المستعمل أوّلاً.
class CardsPage {
  const CardsPage({
    required this.series,
    required this.cards,
    required this.total,
    required this.page,
    required this.count,
  });

  final CardSeries? series;
  final List<CardItem> cards;
  final int total;
  final int page;

  /// حجم الصفحة.
  final int count;

  bool get hasMore => count > 0 && page * count < total;

  static CardsPage fromJson(Map<String, dynamic> body, {int page = 1}) {
    final cards = _rows(body['cards'], CardItem.fromJson);
    return CardsPage(
      series: body['series'] is Map
          ? CardSeries.fromJson(_map(body['series']))
          : null,
      cards: cards,
      total: _intOrNull(body['total']) ?? cards.length,
      page: _intOrNull(body['page']) ?? page,
      count: _intOrNull(body['count']) ?? cards.length,
    );
  }
}

/// ملخّص المخزون — /api/v2/cards/summary (كارتات التعبئة ملك المدير الفعّال).
class CardsSummary {
  const CardsSummary({
    required this.enabled,
    required this.totals,
    required this.profiles,
    required this.series,
    this.updatedAt,
    this.source,
    this.unsupportedMessage,
    this.partial = false,
    this.transferEnabled = false,
  });

  /// `false` = لا صلاحيّة كارت أو لا سلاسل له إطلاقاً (والمصفوفتان فارغتان).
  final bool enabled;

  /// نقل الكارتات لمديرٍ فرعيّ مفعّلٌ لهذا الحساب (`transfer_enabled` — مفتاح الخادم cards_transfer، ٢٧ أكتوبر).
  /// خادمٌ أقدم لا يرسله ⇒ false: لا زرّ نقل.
  final bool transferEnabled;
  final CardsTotals totals;
  final List<CardProfileStock> profiles;
  final List<CardSeries> series;

  /// متى قرأ الخادم الساس — من قاعدتنا (موسومٌ بـZ).
  final DateTime? updatedAt;

  /// مصدر المخزون: `earthlink` لموزّعي ايرث لنك (prepaycard/all — المجموعة ②
  /// ١٨ أكتوبر)، و`null` لـSAS4 (لا يرسله).
  final String? source;

  /// ايرث لنك لا تعرض مخزون الكروت لهذا الحساب (`unsupported:true` من الخادم)
  /// — نصّه العربيّ يُعرض مكان «هذا الحساب ما يستعمل كارتات».
  final String? unsupportedMessage;

  /// ايرث لنك: المخزون أكبر ممّا قرأه الخادم (سقف الكروت أو مهلة القراءة) —
  /// الأرقام لأوّل [CardsTotals.qty] كارت، فيُقال ذلك لا يُعرض جزءٌ كأنّه الكلّ.
  final bool partial;

  /// «السلسلة» عند ايرث لنك هي **الباقة** (ايرث لنك لا تُصدر سلاسل): قائمة
  /// الباقات والسلاسل واحدة، فتُعرض مرّةً باسم الباقة لا برمزها.
  bool get seriesArePackages => source == 'earthlink';

  static CardsSummary fromJson(Map<String, dynamic> body) => CardsSummary(
        enabled: _bool(body['enabled']),
        totals: CardsTotals.fromJson(body['totals']),
        profiles: _rows(body['profiles'], CardProfileStock.fromJson),
        series: _rows(body['series'], CardSeries.fromJson),
        updatedAt: parseServerUtc(_str(body['updated_at'])),
        source: _str(body['source']),
        unsupportedMessage:
            _bool(body['unsupported']) ? _str(body['message']) : null,
        partial: _bool(body['partial']),
        transferEnabled: _bool(body['transfer_enabled']),
      );
}

// ═════════════════════════ نقل الكارتات لمديرٍ فرعيّ (٢٧ أكتوبر) ═════════════════════════

/// مديرٌ فرعيّ تُنقل له الكارتات — كما يراه الساس (`GET /api/v2/cards/transfer-targets`).
class CardTransferTarget {
  const CardTransferTarget({required this.id, required this.username});

  /// رقم المدير في الساس — نصّاً كما يرسله الخادم.
  final String id;
  final String username;

  static CardTransferTarget? fromJson(Map<String, dynamic> j) {
    final id = _str(j['id']);
    final username = _str(j['username']);
    if (id == null || username == null) return null;
    return CardTransferTarget(id: id, username: username);
  }
}

/// ما بقي للنقل في سلسلة (`GET …/series/:series/range`): أرقام الكارتات من [start] إلى [end].
/// [length] صفر = لا شيء يُنقل (والطرفان `null`).
class CardSeriesRange {
  const CardSeriesRange({required this.start, required this.end, required this.length});

  final int? start;
  final int? end;
  final int length;

  static CardSeriesRange fromJson(Map<String, dynamic> j) {
    final start = _intOrNull(j['start']);
    final end = _intOrNull(j['end']);
    final length = _countOrNull(j['length']) ?? 0;
    if (start == null || end == null || end < start || length == 0) {
      return const CardSeriesRange(start: null, end: null, length: 0);
    }
    return CardSeriesRange(start: start, end: end, length: length);
  }
}

/// طريقة النقل — كواجهة الساس: أوّل N كارتاً، أو من أوّل كارتٍ متبقٍّ حتى رقمٍ تختاره، أو المجموعة كاملة.
enum CardTransferMode {
  count('count'),
  range('range'),
  all('all');

  const CardTransferMode(this.wire);
  final String wire;
}

/// نتيجة نقلٍ نجح: كم نُقل، ورسالة الخادم العربيّة، وهل كان طلباً مكرّراً (لم يُنقل ثانيةً).
class CardTransferResult {
  const CardTransferResult({required this.moved, this.message, this.repeated = false});

  final int moved;
  final String? message;
  final bool repeated;
}

// ═════════════════════════ الحالة العامّة ═════════════════════════

/// شارة «الكارتات المتبقّية» — ما تعرضه اللوحة و«قوائم أخرى» بلا طلبٍ خاصّ.
class CardsBadge {
  const CardsBadge({required this.enabled, this.remaining});

  final bool enabled;

  /// مجموع غير المستعمل في كلّ السلاسل. `null` = تعذّرت القراءة.
  final int? remaining;

  /// `cards` في /api/v2/admin-widgets. `null` = خادمٌ لا يعرف الحقل، **أو** حالةٌ
  /// لم تُعرف بعد (`enabled` غائب: أوّل قراءةٍ لمخزون ايرث لنك لم تكتمل خلال
  /// ثانيتها) — فلا تُقرأ «غير متاح» ويُخفى قسم «الكارتات»؛ يبقى ما نعرفه
  /// (و[CardsState.ensureKnown] يسأل الملخّص). الساس يرسل `enabled` دائماً.
  static CardsBadge? fromJson(Object? raw) {
    if (raw is! Map || raw['enabled'] == null) return null;
    return CardsBadge(
      enabled: _bool(raw['enabled']),
      remaining: _countOrNull(raw['remaining']),
    );
  }

  /// بشكل admin-widgets نفسه — فيقرؤه [fromJson] من كاش اللوحة كما من الخادم.
  /// و`remaining: null` يبقى null («تعذّر») لا صفراً.
  Map<String, dynamic> toJson() => {'enabled': enabled, 'remaining': remaining};

  @override
  bool operator ==(Object other) =>
      other is CardsBadge &&
      other.enabled == enabled &&
      other.remaining == remaining;

  @override
  int get hashCode => Object.hash(enabled, remaining);
}

/// مصدرٌ واحد لشارة الكارتات على مستوى التطبيق — تستمع له أيّ شاشة.
///
/// يُحدَّث من أربعة مواضع: ردّ admin-widgets (`DashboardApi.fetchWallet`)،
/// و[CardsApi.summary]، وتفعيلٌ ناجح بكارت ([consumeOne])، وكاش اللوحة عند
/// الإقلاع البارد ([seed]). ويُمسح عند الخروج (`SessionManager`) فلا يرى
/// المدير التالي عدّاد سابقه.
///
/// ⚠️ **الحقبة ([epoch])**: ردٌّ طلبه مديرٌ ثمّ خرج قبل وصوله لا يُكتب فوق
/// جلسة من بعده. الطلب يأخذ الحقبة قبل انتظاره ويمرّرها مع نتيجته،
/// و[reset] يرفعها — فيُهمَل المتأخّر.
class CardsState {
  CardsState._();

  static final ValueNotifier<CardsBadge?> badge =
      ValueNotifier<CardsBadge?>(null);

  static int _epoch = 0;

  /// تُؤخذ قبل الطلب وتُمرَّر مع نتيجته إلى [applyAdminWidgets]/[applySummary].
  static int get epoch => _epoch;

  static bool _stale(int? epoch) => epoch != null && epoch != _epoch;

  static CardsSummary? _summary;

  /// القيمة الحاليّة جاءت من نداءٍ حيّ في هذه الجلسة (admin-widgets أو الملخّص)
  /// لا من كاش اللوحة — المبذورة وحدها قد تكون قديمة (قسم المحفظة مخفيّ فلا
  /// يُطلب admin-widgets)، فتبقى [ensureKnown] تطلب حتى يصل الحيّ.
  static bool _live = false;

  /// خادمٌ بلا مسارات الكارتات (404): لا نطرقه ثانيةً في هذه الجلسة.
  static bool _unsupported = false;

  /// آخر ملخّصٍ وصل في هذه الجلسة — ترسمه شاشة «الكارتات» فور فتحها ثمّ
  /// تجدّده. ويسقط حين تخالفه الشارة (سُحب كارتٌ، أو وصل عددٌ أحدث) فلا
  /// تُرسم أرقامٌ تناقض ما في اللوحة.
  static CardsSummary? get lastSummary => _summary;

  static void set(CardsBadge? value) {
    if (_summary?.totals.remaining != value?.remaining) _summary = null;
    badge.value = value;
  }

  /// من ردّ admin-widgets — غياب الحقل (خادمٌ أقدم) لا يمسح ما نعرفه.
  static void applyAdminWidgets(Object? raw, {int? epoch}) {
    if (_stale(epoch)) return;
    final b = CardsBadge.fromJson(raw);
    if (b != null) {
      set(b);
      _live = true;
    }
  }

  static void applySummary(CardsSummary s, {int? epoch}) {
    if (_stale(epoch)) return;
    set(CardsBadge(enabled: s.enabled, remaining: s.totals.remaining));
    _summary = s;
    _live = true;
  }

  /// نتيجة تفعيلٍ بكارت غير مؤكّدة: لا نعرف إن سُحب الكارت — العدد الحاليّ لم
  /// يعد حيّاً، فيُعاد طلبه في أوّل فرصة بدل رسم رقمٍ قد يكون كاذباً.
  static void invalidate() {
    _live = false;
    _ensureFailedAt = null;
  }

  /// الخادم بلا مسارات الكارتات — يُسجَّل مرّةً فلا يُطرق كلّ دقيقة.
  static void markUnsupported() => _unsupported = true;

  @visibleForTesting
  static bool get isLive => _live;

  @visibleForTesting
  static bool get isUnsupported => _unsupported;

  /// من كاش اللوحة عند الإقلاع البارد: آخر عددٍ معروف يُرسم حتّى يردّ النداء
  /// الحيّ — ولا يغلب قيمةً أحدث سبقته.
  static void seed(CardsBadge? value) {
    if (value != null && badge.value == null) set(value);
  }

  /// كارتٌ سُحب للتوّ: ننقص واحداً إن كان العدد معروفاً، ولا نخترع رقماً
  /// إن لم يكن. الرقم الصحيح يصل مع تحديث اللوحة التالي.
  static void consumeOne() {
    final b = badge.value;
    final n = b?.remaining;
    if (b == null || n == null) return;
    set(CardsBadge(enabled: b.enabled, remaining: math.max(0, n - 1)));
  }

  static Future<void>? _ensuring;
  static DateTime? _ensureFailedAt;
  static const _ensureCooldown = Duration(seconds: 30);

  /// شارةٌ مجهولة ولا أحد يطلبها ⇒ نداء الملخّص مرّةً.
  ///
  /// الشارة تركب admin-widgets، واللوحة لا تطلبه حين يُخفى قسم المحفظة من
  /// «نطاق العرض» — فتبقى مجهولةً وتغيب «الكارتات» عن «قوائم أخرى» لمن يعمل
  /// بها. طلبٌ واحدٌ جارٍ على الأكثر، وبعد الفشل تبريدٌ فلا يُطرق الخادم مع
  /// كلّ تحديثٍ للوحة. والمعروفة لا تكلّف شيئاً.
  static Future<void> ensureKnown() {
    if (_live || _unsupported) return Future<void>.value();
    final running = _ensuring;
    if (running != null) return running;
    final failedAt = _ensureFailedAt;
    if (failedAt != null &&
        DateTime.now().difference(failedAt) < _ensureCooldown) {
      return Future<void>.value();
    }
    late final Future<void> run;
    run = CardsApi.summary().then((r) {
      if (r.data == null && identical(_ensuring, run)) {
        _ensureFailedAt = DateTime.now();
      }
    }).whenComplete(() {
      if (identical(_ensuring, run)) _ensuring = null;
    });
    _ensuring = run;
    return run;
  }

  static void reset() {
    _epoch++;
    _summary = null;
    _ensuring = null;
    _ensureFailedAt = null;
    _live = false;
    _unsupported = false;
    badge.value = null;
  }
}

// ═════════════════════════ الطلبات ═════════════════════════

class CardsApi {
  CardsApi._();

  /// رفض التفعيل بالكارت (409): لا كارت غير مستعمل لباقة المشترك.
  static const codeNoCards = 'NO_CARDS';

  /// رفض التفعيل بالكارت (403): حساب الساس بلا صلاحيّة الكارت.
  static const codeCardNotAllowed = 'CARD_NOT_ALLOWED';

  /// GET /api/v2/cards/summary — مخزون الوكيل: المجاميع والباقات والسلاسل.
  /// النجاح يحدّث [CardsState] أيضاً. [fresh] (التحديث الصريح من الشاشة فقط)
  /// يتخطّى كاش الخادم (٦٠ث) فيرى الوكيل كارتاتٍ أُضيفت للتوّ.
  static Future<({CardsSummary? data, String? message, String? code})>
      summary({bool fresh = false}) async {
    // قبل الانتظار: ردٌّ يصل بعد خروج صاحبه لا يُكتب في الشارة.
    final epoch = CardsState.epoch;
    try {
      final r = await ApiClient.dio.get<Map<String, dynamic>>(
        '/api/v2/cards/summary',
        queryParameters: fresh ? const {'fresh': 1} : null,
      );
      final body = r.data ?? const {};
      if (r.statusCode == 404 && !body.containsKey('enabled')) {
        CardsState.markUnsupported(); // خادمٌ أقدم بلا الميزة
      }
      // ⚠️ **الرفض يصل ردّاً لا رميةً** — `validateStatus: s < 500`.
      if (body['success'] != true) {
        return (
          data: null,
          message: _str(body['message']) ?? 'تعذّر جلب الكارتات',
          code: _str(body['code']),
        );
      }
      final s = CardsSummary.fromJson(body);
      CardsState.applySummary(s, epoch: epoch);
      return (data: s, message: null, code: null);
    } catch (e) {
      _log('summary', e);
      return (
        data: null,
        message: humanError(e, fallback: 'تعذّر جلب الكارتات'),
        code: null,
      );
    }
  }

  /// GET /api/v2/cards/series/:series?page=N — كارتات سلسلة، غير المستعمل
  /// أوّلاً. سلسلةٌ ليست للمدير الفعّال ← 404 برسالة «السلسلة غير موجودة».
  static Future<({CardsPage? data, String? message, String? code})> seriesCards(
      String series,
      {int page = 1}) async {
    try {
      final r = await ApiClient.dio.get<Map<String, dynamic>>(
        '/api/v2/cards/series/${Uri.encodeComponent(series)}',
        queryParameters: {'page': page},
      );
      final body = r.data ?? const {};
      if (body['success'] != true) {
        return (
          data: null,
          message: _str(body['message']) ?? 'تعذّر جلب كارتات السلسلة',
          code: _str(body['code']),
        );
      }
      return (
        data: CardsPage.fromJson(body, page: page),
        message: null,
        code: null
      );
    } catch (e) {
      _log('series', e);
      return (
        data: null,
        message: humanError(e, fallback: 'تعذّر جلب كارتات السلسلة'),
        code: null,
      );
    }
  }

  // ── نقل الكارتات لمديرٍ فرعيّ (٢٧ أكتوبر — صاحب الحساب وحده، خلف مفتاح الخادم cards_transfer) ──

  /// GET /api/v2/cards/transfer-targets — مدراؤك الفرعيّون كما يراهم الساس.
  static Future<({List<CardTransferTarget>? data, String? message, String? code})> transferTargets() async {
    try {
      final r = await ApiClient.dio.get<Map<String, dynamic>>('/api/v2/cards/transfer-targets');
      final body = r.data ?? const {};
      if (body['success'] != true) {
        return (
          data: null,
          message: _str(body['message']) ?? 'تعذّرت قراءة المدراء أو المجموعة — أعد المحاولة',
          code: _str(body['code']),
        );
      }
      return (data: _rows(body['targets'], CardTransferTarget.fromJson), message: null, code: null);
    } catch (e) {
      _log('transfer-targets', e);
      return (data: null, message: humanError(e, fallback: 'تعذّرت قراءة المدراء أو المجموعة — أعد المحاولة'), code: null);
    }
  }

  /// GET /api/v2/cards/series/:series/range — ما بقي للنقل في السلسلة الآن.
  static Future<({CardSeriesRange? data, String? message, String? code})> seriesRange(String series) async {
    try {
      final r = await ApiClient.dio.get<Map<String, dynamic>>(
        '/api/v2/cards/series/${Uri.encodeComponent(series)}/range',
      );
      final body = r.data ?? const {};
      if (body['success'] != true) {
        return (
          data: null,
          message: _str(body['message']) ?? 'تعذّرت قراءة المدراء أو المجموعة — أعد المحاولة',
          code: _str(body['code']),
        );
      }
      return (data: CardSeriesRange.fromJson(body), message: null, code: null);
    } catch (e) {
      _log('series-range', e);
      return (data: null, message: humanError(e, fallback: 'تعذّرت قراءة المدراء أو المجموعة — أعد المحاولة'), code: null);
    }
  }

  /// POST /api/v2/cards/series/:series/transfer — [requestId] ثابتٌ للنيّة الواحدة: إعادةٌ بعد انقطاعٍ (أو نقرةٌ
  /// مكرّرة) بالمعرّف نفسه تأخذ النتيجة نفسها بلا نقلٍ ثانٍ. [answered] = ردّ الخادم فعلاً (حكمه نهائيّ)؛ `false` =
  /// انقطاعٌ قبل الردّ — يُعاد بالمعرّف نفسه.
  static Future<({CardTransferResult? data, String? message, String? code, bool answered})> transfer(
    String series, {
    required CardTransferMode mode,
    required String to,
    int? count,
    int? toCard,
    required String requestId,
  }) async {
    try {
      final r = await ApiClient.dio.post<Map<String, dynamic>>(
        '/api/v2/cards/series/${Uri.encodeComponent(series)}/transfer',
        data: {
          'mode': mode.wire,
          'to': to,
          if (mode == CardTransferMode.count) 'count': count,
          if (mode == CardTransferMode.range) 'to_card': toCard,
          'request_id': requestId,
        },
      );
      final body = r.data ?? const {};
      if (body['success'] != true) {
        return (
          data: null,
          message: _str(body['message']) ?? 'تعذّر النقل — تأكّد من الاتّصال وأعد',
          code: _str(body['code']),
          answered: true,
        );
      }
      // نُقل شيءٌ أو لم يُنقل: الشارة والملخّص يُقرآن طازجين.
      CardsState.invalidate();
      return (
        data: CardTransferResult(
          moved: _int(body['moved']),
          message: _str(body['message']),
          repeated: _bool(body['repeated']),
        ),
        message: null,
        code: null,
        answered: true,
      );
    } catch (e) {
      _log('transfer', e);
      // رميةٌ = انقطاعٌ أو 5xx (نشرٌ/بوّابةٌ عابرة — خادمنا لا يردّ النقل بـ5xx): لا حكم، فالمعرّف نفسه للإعادة.
      return (
        data: null,
        message: humanError(e, fallback: 'تعذّر النقل — تأكّد من الاتّصال وأعد'),
        code: null,
        answered: false,
      );
    }
  }

  /// معرّف طلب نقلٍ جديد (نيّةٌ واحدة) — ٣٢ خانة سداسيّة عشوائيّة.
  static String newTransferRequestId() {
    final rnd = math.Random.secure();
    return List.generate(16, (_) => rnd.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  }

  /// ⚠️ الحالة ونوع الخطأ فقط — لا جسم الردّ ولا نصّ الاستثناء.
  static void _log(String what, Object e) {
    if (kReleaseMode) return;
    final detail = e is DioException
        ? 'status=${e.response?.statusCode} type=${e.type.name}'
        : e.runtimeType.toString();
    debugPrint('🔴 cards/$what: $detail');
  }
}
