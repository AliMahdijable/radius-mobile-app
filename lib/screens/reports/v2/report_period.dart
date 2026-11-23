import '../../../core/util/ar_date.dart';

// فترات التقرير الموحّد (٢٢ نوفمبر — بند المقترح ٣ و٤): تسع فتراتٍ جاهزة + مخصّص، ولكلّ فترةٍ «ما قبلها» للمقارنة.
// الأسبوع يبدأ السبت كأسبوع العراق (CLDR IQ: firstDay=sat) — ٢٣ نوفمبر، المالك بسجلّ النشاط: «اختار يوم يقره، سبوع ميقره» (كان يبدأ
// الإثنين فصار «هذا الأسبوع» يوم الإثنين = اليوم وحده). [DateRange.thisWeek] خارج التقارير كما هو. كلّ شيءٍ هنا حسابٌ صرف بساعةٍ تُمرَّر.

/// [all] «كل الفترات» — لتقريرٍ رصيده حالٌ لا فترة (ديون المدراء) وحده؛ ليس في [RpRange.presets].
enum RpPreset { today, yesterday, thisWeek, lastWeek, thisMonth, lastMonth, last30, last90, thisYear, all, custom }

class RpRange {
  const RpRange._(this.preset, this.from, this.to);

  final RpPreset preset;

  /// أوّل يومٍ (00:00).
  final DateTime from;

  /// آخر يومٍ (23:59:59).
  final DateTime to;

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);
  static DateTime _end(DateTime d) => DateTime(d.year, d.month, d.day, 23, 59, 59);
  static int _daysIn(int y, int m) => DateTime(y, m + 1, 0).day;

  /// أيّامٌ منذ السبت: السبت ٠، الأحد ١ … الجمعة ٦.
  static int _sinceSaturday(DateTime d) => (d.weekday - DateTime.saturday + 7) % 7;

  /// يومٌ من شهرٍ مقصوصٌ على طوله (٣١ ⇒ ٣٠ في نوفمبر).
  static DateTime _clampDay(int y, int m, int d) => DateTime(y, m, d > _daysIn(y, m) ? _daysIn(y, m) : d);

  static RpRange of(RpPreset p, {required DateTime now, DateTime? from, DateTime? to}) {
    final t = _day(now);
    switch (p) {
      case RpPreset.today:
        return RpRange._(p, t, _end(t));
      case RpPreset.yesterday:
        final y = t.subtract(const Duration(days: 1));
        return RpRange._(p, y, _end(y));
      case RpPreset.thisWeek:
        return RpRange._(p, DateTime(t.year, t.month, t.day - _sinceSaturday(t)), _end(t));
      case RpPreset.lastWeek:
        // السبت الذي قبل سبت هذا الأسبوع ⇐ حتى الجمعة
        final sat = DateTime(t.year, t.month, t.day - _sinceSaturday(t) - 7);
        return RpRange._(p, sat, _end(DateTime(sat.year, sat.month, sat.day + 6)));
      case RpPreset.thisMonth:
        return RpRange._(p, DateTime(t.year, t.month, 1), _end(t));
      case RpPreset.lastMonth:
        return RpRange._(p, DateTime(t.year, t.month - 1, 1), _end(DateTime(t.year, t.month, 0)));
      case RpPreset.last30:
        return RpRange._(p, t.subtract(const Duration(days: 29)), _end(t));
      case RpPreset.last90:
        // «آخر 90 يوماً» (كشف حساب المشترك: افتراضه القديم ثلاثة أشهر)
        return RpRange._(p, t.subtract(const Duration(days: 89)), _end(t));
      case RpPreset.thisYear:
        return RpRange._(p, DateTime(t.year, 1, 1), _end(t));
      case RpPreset.all:
        return RpRange._(p, DateTime(2000, 1, 1), _end(t));
      case RpPreset.custom:
        final a = _day(from ?? t), b = _day(to ?? t);
        return a.isAfter(b) ? RpRange._(p, b, _end(a)) : RpRange._(p, a, _end(b));
    }
  }

  /// أيّام الفترة (اليوم وحده = ١).
  int get days => _day(to).difference(from).inDays + 1;

  /// الفترة التي تقابلها للمقارنة: الشهر حتى اليوم ⇐ الأيّام نفسها من الشهر الماضي، الأسبوع ⇐ الأيّام نفسها من الماضي، والكاملة
  /// ⇐ الكاملة قبلها، والمخصّصة ⇐ الطول نفسه قبلها مباشرةً.
  RpRange get previous {
    switch (preset) {
      case RpPreset.today:
      case RpPreset.yesterday:
        final d = from.subtract(const Duration(days: 1));
        return RpRange._(RpPreset.custom, d, _end(d));
      case RpPreset.thisWeek:
      case RpPreset.lastWeek:
        final a = from.subtract(const Duration(days: 7));
        return RpRange._(RpPreset.custom, a, _end(_day(to).subtract(const Duration(days: 7))));
      case RpPreset.thisMonth:
        final a = DateTime(from.year, from.month - 1, 1);
        return RpRange._(RpPreset.custom, a, _end(_clampDay(a.year, a.month, to.day)));
      case RpPreset.lastMonth:
        final a = DateTime(from.year, from.month - 1, 1);
        return RpRange._(RpPreset.custom, a, _end(DateTime(from.year, from.month, 0)));
      case RpPreset.thisYear:
        return RpRange._(RpPreset.custom, DateTime(from.year - 1, 1, 1), _end(_clampDay(from.year - 1, to.month, to.day)));
      case RpPreset.all:
        return this; // لا شيء قبل «كلّ ما سُجّل» — لا مقارنة
      case RpPreset.last30:
      case RpPreset.last90:
      case RpPreset.custom:
        final b = from.subtract(const Duration(days: 1));
        return RpRange._(RpPreset.custom, b.subtract(Duration(days: days - 1)), _end(b));
    }
  }

  /// اسمها بالعربيّ («هذا الشهر»).
  String get name => switch (preset) {
        RpPreset.today => 'اليوم',
        RpPreset.yesterday => 'أمس',
        RpPreset.thisWeek => 'هذا الأسبوع',
        RpPreset.lastWeek => 'الأسبوع الماضي',
        RpPreset.thisMonth => 'هذا الشهر',
        RpPreset.lastMonth => 'الشهر الماضي',
        RpPreset.last30 => 'آخر 30 يوماً',
        RpPreset.last90 => 'آخر 90 يوماً',
        RpPreset.thisYear => 'هذه السنة',
        RpPreset.all => 'كل الفترات',
        RpPreset.custom => 'فترة مخصّصة',
      };

  /// تاريخاها أرقاماً («2026/11/01 – 2026/11/22»؛ اليوم الواحد تاريخٌ واحد).
  String get rangeText {
    if (preset == RpPreset.all) return 'كلّ ما سُجّل حتى ${iqDateOf(to)}';
    final a = iqDateOf(from), b = iqDateOf(to);
    return a == b ? a : '$a – $b';
  }

  /// سطر الفرق تحت الرقم («عن الشهر الماضي»).
  String get vsText => switch (preset) {
        RpPreset.today => 'عن أمس',
        RpPreset.yesterday => 'عن اليوم الذي قبله',
        RpPreset.thisWeek => 'عن الأسبوع الماضي',
        RpPreset.lastWeek => 'عن الأسبوع الذي قبله',
        RpPreset.thisMonth => 'عن الشهر الماضي',
        RpPreset.lastMonth => 'عن الشهر الذي قبله',
        RpPreset.last30 => 'عن الـ30 يوماً قبلها',
        RpPreset.last90 => 'عن الـ90 يوماً قبلها',
        RpPreset.thisYear => 'عن السنة الماضية',
        RpPreset.all => '',
        RpPreset.custom => 'عن الفترة السابقة',
      };

  /// سطر مفتاح «قارن» («بالشهر الماضي»).
  String get compareText => switch (preset) {
        RpPreset.today => 'بأمس',
        RpPreset.yesterday => 'باليوم الذي قبله',
        RpPreset.thisWeek => 'بالأسبوع الماضي',
        RpPreset.lastWeek => 'بالأسبوع الذي قبله',
        RpPreset.thisMonth => 'بالشهر الماضي',
        RpPreset.lastMonth => 'بالشهر الذي قبله',
        RpPreset.last30 => 'بالـ30 يوماً قبلها',
        RpPreset.last90 => 'بالـ90 يوماً قبلها',
        RpPreset.thisYear => 'بالسنة الماضية',
        RpPreset.all => '',
        RpPreset.custom => 'بالفترة السابقة',
      };

  /// للحفظ: الجاهزة باسمها (تُحسب من جديد كلّ فتح)، والمخصّصة بتاريخيها.
  String get key => preset == RpPreset.custom ? 'custom:${iqDateOf(from)}:${iqDateOf(to)}' : preset.name;

  static RpRange fromKey(String? key, {required DateTime now}) {
    final k = (key ?? '').trim();
    if (k.startsWith('custom:')) {
      final parts = k.split(':');
      DateTime? d(String s) {
        final m = RegExp(r'^(\d{4})/(\d{2})/(\d{2})$').firstMatch(s);
        return m == null ? null : DateTime(int.parse(m.group(1)!), int.parse(m.group(2)!), int.parse(m.group(3)!));
      }

      final a = parts.length == 3 ? d(parts[1]) : null;
      final b = parts.length == 3 ? d(parts[2]) : null;
      if (a != null && b != null) return of(RpPreset.custom, now: now, from: a, to: b);
    }
    for (final p in RpPreset.values) {
      if (p != RpPreset.custom && p.name == k) return of(p, now: now);
    }
    return of(RpPreset.thisMonth, now: now);
  }

  static const presets = [
    RpPreset.today,
    RpPreset.yesterday,
    RpPreset.thisWeek,
    RpPreset.lastWeek,
    RpPreset.thisMonth,
    RpPreset.lastMonth,
    RpPreset.last30,
    RpPreset.last90,
    RpPreset.thisYear,
  ];

  @override
  bool operator ==(Object other) => other is RpRange && other.preset == preset && other.from == from && other.to == to;

  @override
  int get hashCode => Object.hash(preset, from, to);
}

/// الفرق عن الفترة السابقة نسبةً — null حين لا أساس له (السابقة صفر أو غير معروفة): «جديد» لا «+∞%».
double? rpDelta(num current, num? previous) {
  if (previous == null || previous == 0) return null;
  return (current - previous) / previous.abs();
}
