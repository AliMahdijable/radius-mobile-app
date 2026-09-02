import 'package:flutter/foundation.dart';

/// مخزن قراءات الأجهزة — **على مستوى التطبيق لا الشاشة**.
///
/// ── العطل الذي يُصلحه ─────────────────────────────────────────────
/// 🐛 بلاغ ٢٠٢٦-٠٩-٠٢: «بكلّ جهاز أنقر عليه لازم يعيد من جديد إرسال
/// الطلب، وهذا مزعج. هو كلّهن طلب SSH واحد، مفروض بهذا الطلب يجلب كلّ
/// المعلومات ويبقى يحافظها — وقت ما أنقر على الكارت تطلع لي».
///
/// وكان المخزن يعيش في حالة «نظرة عامّة» وحدها. فالخروج منها يمحوه،
/// وصفحةُ التفاصيل تفتح جلستها **من الصفر** — فيُدفع ثمن الجلسة
/// مرّتين لكلّ جهاز، والمستخدم ينتظر مرّتين.
///
/// ── ما يحفظه ──────────────────────────────────────────────────────
/// - [raw]: حمولة العلامة كما جاءت (`MikrotikStats` · `UbntStats` ·
///   `MimosaStats`). منها تُبذَر اللوحة المفردة فتعرض فوراً بدل
///   انتظار جلسة.
/// - [sample]: عدّادات الأوكتِتات ولحظتها — أساس حساب المرور. حفظُها
///   يعني أنّ العودة إلى جهازٍ زرتَه لا تبدأ من «يقيس…».
///
/// ── لماذا لا يُخزَّن على القرص ────────────────────────────────────
/// هذه قراءاتٌ لحظيّة تفسد في ثوانٍ. حفظُها بين تشغيلين يُظهر معالجاً
/// بـ٧٪ من الأمس وكأنّه الآن — والرقم القديم المعروض بثقةٍ أسوأ من
/// غيابه. العمر عمرُ الجلسة.
class DeviceStatsCache {
  DeviceStatsCache._();
  static final DeviceStatsCache instance = DeviceStatsCache._();

  /// كم تبقى الحمولة الخام صالحةً لبذر لوحة.
  ///
  /// أطول من نافذة تجديد البطاقة (٢٠ث) عمداً: البذر يعرض رقماً عمره
  /// دقيقة **ثمّ يُحدّثه فوراً**، وهو أنفع من شاشةٍ فارغة تنتظر ثوانيَ.
  /// أمّا الأقدم من ذلك فيُطرح — الفراغ أصدق منه.
  static const seedTtl = Duration(minutes: 2);

  final Map<int, _Entry> _byId = {};

  /// يحفظ حمولة علامةٍ خام بعد جلسةٍ ناجحة.
  ///
  /// [detailed] تُفرّق بين حمولةٍ خفيفة (ثلاثة أرقام) وأخرى كاملة (مع
  /// المنافذ والعملاء). فالبطاقة المطويّة تكتفي بالأولى، والمفتوحة
  /// واللوحة المفردة تحتاجان الثانية — وبلا هذا التمييز نظنّ الخفيفة
  /// كافيةً فنعرض تفصيلاً فارغاً.
  void putRaw(int deviceId, Object raw, {bool detailed = true}) {
    final e = _byId.putIfAbsent(deviceId, _Entry.new);

    // ⚠️ الخفيفة لا تمحو تفاصيل الكاملة الطازجة — **لكنّها تُحدّث
    // العمر**.
    //
    // 🐛 تجميدٌ أدخلتُه ثمّ كشفه تحذير المستخدم «المعلومات الحيّة ما
    // تتغيّر»: كان الفرع يعود صامتاً فلا يمسّ `rawAt`. فتُجدّد البطاقة
    // المطويّة أرقامها كلّ نبضة، والمخزن يحمل لقطةً تشيخ حتّى تُطرح بعد
    // دقيقتين — ومن يُبذَر منها يرى رقماً ميّتاً.
    //
    // فنُبقي الحمولة الغنيّة ونُقرّ بأنّ الجهاز رُئي الآن: البذرة تبقى
    // كاملة، وعمرُها يقول الحقيقة.
    if (e.detailed && !detailed && e.raw != null && _fresh(e.rawAt)) {
      e.rawAt = DateTime.now();
      return;
    }
    e.raw = raw;
    e.rawAt = DateTime.now();
    e.detailed = detailed;
  }

  static bool _fresh(DateTime? at) =>
      at != null && DateTime.now().difference(at) <= seedTtl;

  /// هل الحمولة المحفوظة تحمل التفاصيل (منافذ · عملاء)؟
  bool isDetailed(int deviceId) {
    final e = _byId[deviceId];
    return e != null && e.detailed && _fresh(e.rawAt);
  }

  /// جهازٌ قُرئ خفيفاً وينتظر ترقيةً إلى الكامل.
  bool needsUpgrade(int deviceId) {
    final e = _byId[deviceId];
    return e != null && e.raw != null && !e.detailed && _fresh(e.rawAt);
  }

  /// حمولةٌ خام صالحة للبذر، أو `null`.
  ///
  /// [T] نوع العلامة المتوقَّع — جهازٌ غُيّرت علامته يحمل حمولةً من
  /// النوع القديم، وبذرُها في لوحةٍ أخرى يرمي. الفحص هنا لا عند
  /// المستدعي.
  T? seedFor<T>(int deviceId) {
    final e = _byId[deviceId];
    if (e == null || e.raw == null || e.rawAt == null) return null;
    if (DateTime.now().difference(e.rawAt!) > seedTtl) return null;
    final r = e.raw;
    return r is T ? r : null;
  }

  /// عمر الحمولة المحفوظة — لعرض «آخر قراءة قبل…».
  Duration? ageOf(int deviceId) {
    final at = _byId[deviceId]?.rawAt;
    return at == null ? null : DateTime.now().difference(at);
  }

  /// عيّنة عدّادات لحساب المرور.
  void putSample(int deviceId, Map<String, ({int rx, int tx})> counters) {
    if (counters.isEmpty) return;
    final e = _byId.putIfAbsent(deviceId, _Entry.new);
    e.counters = counters;
    e.countersAt = DateTime.now();
  }

  ({Map<String, ({int rx, int tx})> counters, DateTime at})? sampleOf(
      int deviceId) {
    final e = _byId[deviceId];
    if (e == null || e.counters == null || e.countersAt == null) return null;
    return (counters: e.counters!, at: e.countersAt!);
  }

  /// يُفرَغ عند الخروج من الحساب — قراءاتُ مديرٍ لا تُعرض لغيره.
  void clear() => _byId.clear();

  @visibleForTesting
  int get size => _byId.length;
}

class _Entry {
  Object? raw;
  DateTime? rawAt;

  /// هل تحمل المنافذ والعملاء، أم ثلاثة أرقام فقط؟
  bool detailed = false;
  Map<String, ({int rx, int tx})>? counters;
  DateTime? countersAt;
}
