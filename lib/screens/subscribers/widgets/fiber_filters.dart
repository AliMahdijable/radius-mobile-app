import '../../../models/subscriber.dart';

/// فلاتر «المنطقة / FDT / FAT» لساسات الوطني (١٩ نوفمبر — البصرة/الناصريّة؛ المالك: «اي هم ابنيها»): كموقع الساس
/// (users/ftth-*) وكالموقع (/v2 — `?zone/fdt/fat`). الخادم يرسل `ftth_zone/fdt/fat` على صفوف ساسات الوطني وحدها، فالخيارات
/// من الصفوف نفسها، متسلسلة: المنطقة ⇐ FDT ⇐ FAT (تغيير ما فوق يمسح ما تحته). منطقٌ خالص — يُختبر وحده.
class FiberFilter {
  const FiberFilter({this.zone, this.fdt, this.fat});

  final String? zone;
  final String? fdt;
  final String? fat;

  static const none = FiberFilter();

  bool get isActive => zone != null || fdt != null || fat != null;

  bool matches(Subscriber s) =>
      (zone == null || s.ftthZone == zone) && (fdt == null || s.ftthFdt == fdt) && (fat == null || s.ftthFat == fat);

  /// اختيار منطقة يمسح FDT وFAT؛ واختيار FDT يمسح FAT (لا تبقى قيمةٌ من منطقةٍ أخرى بلا صفوف).
  FiberFilter withZone(String? v) => FiberFilter(zone: _norm(v));
  FiberFilter withFdt(String? v) => FiberFilter(zone: zone, fdt: _norm(v));
  FiberFilter withFat(String? v) => FiberFilter(zone: zone, fdt: fdt, fat: _norm(v));

  static String? _norm(String? v) {
    final t = v?.trim();
    return t == null || t.isEmpty ? null : t;
  }

  @override
  bool operator ==(Object other) => other is FiberFilter && other.zone == zone && other.fdt == fdt && other.fat == fat;

  @override
  int get hashCode => Object.hash(zone, fdt, fat);
}

/// خيارات القوائم الثلاث بأعدادها، كلٌّ مقيَّدٌ بما فوقه.
class FiberOptions {
  const FiberOptions({required this.zones, required this.fdts, required this.fats});

  final List<(String, int)> zones;
  final List<(String, int)> fdts;
  final List<(String, int)> fats;

  /// صفوفٌ تحمل الحقول ⇒ الفلاتر تظهر (شركةٌ بلا حقول الوطني ⇒ لا قوائم).
  static bool available(Iterable<Subscriber> rows) =>
      rows.any((s) => s.ftthZone != null || s.ftthFdt != null || s.ftthFat != null);

  static FiberOptions of(Iterable<Subscriber> rows, FiberFilter f) {
    final all = rows.toList();
    final inZone = f.zone == null ? all : all.where((s) => s.ftthZone == f.zone).toList();
    final inFdt = f.fdt == null ? inZone : inZone.where((s) => s.ftthFdt == f.fdt).toList();
    return FiberOptions(
      zones: _tally(all.map((s) => s.ftthZone)),
      fdts: _tally(inZone.map((s) => s.ftthFdt)),
      fats: _tally(inFdt.map((s) => s.ftthFat)),
    );
  }

  static List<(String, int)> _tally(Iterable<String?> values) {
    final m = <String, int>{};
    for (final v in values) {
      if (v == null || v.trim().isEmpty) continue;
      m[v] = (m[v] ?? 0) + 1;
    }
    final keys = m.keys.toList()..sort(naturalCompare);
    return [for (final k in keys) (k, m[k]!)];
  }
}

/// ترتيبٌ طبيعيّ: «BSR-2» قبل «BSR-10» (الأرقام تُقارَن بقيمتها) — كالموقع (`localeCompare` بـnumeric).
int naturalCompare(String a, String b) {
  final re = RegExp(r'(\d+)|(\D+)');
  final pa = re.allMatches(a).map((m) => m.group(0)!).toList();
  final pb = re.allMatches(b).map((m) => m.group(0)!).toList();
  for (var i = 0; i < pa.length && i < pb.length; i++) {
    final x = pa[i];
    final y = pb[i];
    final nx = int.tryParse(x);
    final ny = int.tryParse(y);
    final c = (nx != null && ny != null) ? (nx == ny ? x.length.compareTo(y.length) : nx.compareTo(ny)) : x.toLowerCase().compareTo(y.toLowerCase());
    if (c != 0) return c;
  }
  return pa.length.compareTo(pb.length);
}
