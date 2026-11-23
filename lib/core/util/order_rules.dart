import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// «الترتيب بالنقر» (المالك ٢٣ نوفمبر: «ترتيب تصاعدي تنازلي عند النقر عالحقل… فكر بيها بجميع المنصات») — القواعد نفسها بالموقع
/// (client-v2 src/lib/sort.ts) حرفاً، وجدول الحالات نفسه (test/fixtures/sort_cases.json) يمرّ على الاثنين:
/// • النقرة على حقلٍ غير مرتَّبٍ به ترتّب به بـ«الأنفع» (الأسماء أ ← ي، المبالغ والأعداد الأكبر، التواريخ الأحدث)، والنقرة على
///   المرتَّب به تقلبه.
/// • الفارغ و«—» آخراً بالاتّجاهين، والتعادل بترتيب القائمة الأصليّ.
/// • العربيّ مطبَّع (أشكال الألف = ا، ى ئ = ي، ة = ه، ؤ = و، والكرديّة/الفارسيّة لأصولها)، والأرقام بقيمتها (user2 قبل user10).
/// الفرق الوحيد عن الموقع: لا NFKC لحروف العرض (FBxx/FExx) — لا تأتي من لوحات المفاتيح.

enum OrderDir { asc, desc }

enum OrderKind { text, number, date }

class OrderField {
  const OrderField(this.key, this.label, this.kind, {this.first, this.natural});
  final String key;
  final String label;
  final OrderKind kind;

  /// اتّجاه أوّل نقرة — null ⇒ «الأنفع» لنوعه.
  final OrderDir? first;

  /// القائمة تصل مرتّبةً بهذا الحقل أصلاً بهذا الاتّجاه (حركات التقارير: الأحدث أوّلاً) ⇒ تبقى كما هي، والاتّجاه الآخر عكسها حرفاً —
  /// فالترتيب الافتراضيّ هو نفسه ما كان قبل الميزة.
  final OrderDir? natural;
}

class OrderValue {
  const OrderValue(this.key, this.dir);
  final String key;
  final OrderDir dir;

  @override
  bool operator ==(Object other) => other is OrderValue && other.key == key && other.dir == dir;

  @override
  int get hashCode => Object.hash(key, dir);

  @override
  String toString() => '$key:${dir.name}';
}

/// اتّجاه أوّل نقرة على الحقل.
OrderDir firstDir(OrderField f) => f.first ?? (f.kind == OrderKind.text ? OrderDir.asc : OrderDir.desc);

/// النقرة: على الحقل المرتَّب به ⇒ يقلب؛ على غيره ⇒ يرتّب به باتّجاه أوّل نقرة.
OrderValue nextOrder(OrderValue cur, OrderField f) => cur.key == f.key
    ? OrderValue(f.key, cur.dir == OrderDir.asc ? OrderDir.desc : OrderDir.asc)
    : OrderValue(f.key, firstDir(f));

/// «الأكبر أوّلاً» · «من أ إلى ي» · «الأحدث أوّلاً».
String orderDirText(OrderKind kind, OrderDir dir) {
  switch (kind) {
    case OrderKind.text:
      return dir == OrderDir.asc ? 'من أ إلى ي' : 'من ي إلى أ';
    case OrderKind.date:
      return dir == OrderDir.desc ? 'الأحدث أوّلاً' : 'الأقدم أوّلاً';
    case OrderKind.number:
      return dir == OrderDir.desc ? 'الأكبر أوّلاً' : 'الأصغر أوّلاً';
  }
}

/// «مرتّب حسب: المبلغ — الأكبر أوّلاً» — سطر رأس التصدير؛ null لحقلٍ غير معروف.
String? orderLine(List<OrderField> fields, OrderValue v) {
  for (final f in fields) {
    if (f.key == v.key) return 'مرتّب حسب: ${f.label} — ${orderDirText(f.kind, v.dir)}';
  }
  return null;
}

// ═══════════════ مفتاح النصّ ═══════════════

final _strip = RegExp('[\u064B-\u065F\u0670\u06D6-\u06ED\u0640\u200B-\u200F\u202A-\u202E\u2066-\u2069\uFEFF]');
final _spaces = RegExp(r'\s+');
const _map = <int, int>{
  // الألف بأشكالها
  0x0622: 0x0627, 0x0623: 0x0627, 0x0625: 0x0627, 0x0671: 0x0627, 0x0672: 0x0627, 0x0673: 0x0627, 0x0675: 0x0627,
  // الياء والألف المقصورة والهمزة على نبرة
  0x0649: 0x064A, 0x06CC: 0x064A, 0x06D0: 0x064A, 0x0626: 0x064A, 0x06CE: 0x064A,
  // التاء المربوطة والهاء الكرديّة
  0x0629: 0x0647, 0x06D5: 0x0647, 0x06BE: 0x0647, 0x06C1: 0x0647,
  // الواو بهمزة والواو الكرديّة
  0x0624: 0x0648, 0x06C6: 0x0648, 0x06C7: 0x0648, 0x06C8: 0x0648,
  // الكاف الفارسيّة وأخواتها مع أصولها
  0x06A9: 0x0643, 0x06AF: 0x0643, 0x067E: 0x0628, 0x0686: 0x062C, 0x0698: 0x0632, 0x06A4: 0x0641, 0x06B5: 0x0644, 0x0695: 0x0631,
};

/// النصّ مفتاحاً للترتيب: بلا تشكيلٍ ولا تطويلٍ ولا علامات اتّجاه، الحروف بأصولها، الأرقام العربيّة لاتينيّة، واللاتينيّة صغيرة.
String sortText(Object? v) {
  final s = (v ?? '').toString().replaceAll(_strip, '');
  final b = StringBuffer();
  for (final r in s.runes) {
    if (r >= 0x0660 && r <= 0x0669) {
      b.writeCharCode(0x30 + r - 0x0660);
    } else if (r >= 0x06F0 && r <= 0x06F9) {
      b.writeCharCode(0x30 + r - 0x06F0);
    } else {
      b.writeCharCode(_map[r] ?? r);
    }
  }
  return b.toString().toLowerCase().replaceAll(_spaces, ' ').trim();
}

bool _digit(int c) => c >= 0x30 && c <= 0x39;
final _leadZeros = RegExp(r'^0+(?=\d)');

/// مقارنة مفتاحَي نصّ: حرفاً حرفاً بترتيب الأبجديّة، والأرقام المتتالية بقيمتها (user2 قبل user10، و007 = 7).
int compareText(String a, String b) {
  var i = 0;
  var j = 0;
  while (i < a.length && j < b.length) {
    final ca = a.codeUnitAt(i);
    final cb = b.codeUnitAt(j);
    if (_digit(ca) && _digit(cb)) {
      var i2 = i;
      while (i2 < a.length && _digit(a.codeUnitAt(i2))) {
        i2++;
      }
      var j2 = j;
      while (j2 < b.length && _digit(b.codeUnitAt(j2))) {
        j2++;
      }
      final ra = a.substring(i, i2).replaceFirst(_leadZeros, '');
      final rb = b.substring(j, j2).replaceFirst(_leadZeros, '');
      if (ra.length != rb.length) return ra.length - rb.length;
      final c = ra.compareTo(rb);
      if (c != 0) return c;
      i = i2;
      j = j2;
      continue;
    }
    if (ca != cb) return ca - cb;
    i++;
    j++;
  }
  return (a.length - i) - (b.length - j);
}

// ═══════════════ القيم ═══════════════

final _numShape = RegExp(r'^[-+]?\d*\.?\d+(e[-+]?\d+)?$');
final _numNoise = RegExp(r'[,\s]');
final _dateShape = RegExp(r'^(\d{4})-(\d{2})-(\d{2})(?:[ T](\d{2}):(\d{2})(?::(\d{2}))?)?');

/// قيمةٌ قابلة للترتيب (نصٌّ مطبَّع أو رقم) أو null (فارغ ⇒ آخر القائمة بالاتّجاهين).
Object? sortValueOf(Object? v, OrderKind kind) {
  if (v == null) return null;
  switch (kind) {
    case OrderKind.text:
      final s = sortText(v);
      return s.isEmpty || s == '—' || s == '-' ? null : s;
    case OrderKind.number:
      if (v is num) return v.isFinite ? v : null;
      final s = sortText(v).replaceAll(_numNoise, '');
      if (s.isEmpty || !_numShape.hasMatch(s)) return null;
      final n = num.tryParse(s);
      return n != null && n.isFinite ? n : null;
    case OrderKind.date:
      if (v is num) return v.isFinite ? v : null;
      if (v is DateTime) return v.millisecondsSinceEpoch;
      final m = _dateShape.firstMatch(v.toString().trim());
      if (m == null) return null;
      int g(int k) => int.parse(m.group(k) ?? '0');
      return DateTime.utc(g(1), g(2), g(3), g(4), g(5), g(6)).millisecondsSinceEpoch;
  }
}

/// القائمة مرتّبةً بـ[value] (نسخةٌ — الأصل لا يُمسّ). حقلٌ له [OrderField.natural]: القائمة كما وصلت أو عكسها حرفاً. غيره: بقيمته
/// من [get]، الفارغ آخراً بالاتّجاهين، والتعادل بترتيب القائمة الأصليّ. حقلٌ غير معروف ⇒ القائمة كما هي.
List<T> sortList<T>(List<T> list, OrderValue value, List<OrderField> fields, Object? Function(T item, String key) get) {
  OrderField? f;
  for (final x in fields) {
    if (x.key == value.key) f = x;
  }
  if (f == null) return [...list];
  final natural = f.natural;
  if (natural != null) return value.dir == natural ? [...list] : list.reversed.toList();
  final kind = f.kind;
  final keyed = [for (var i = 0; i < list.length; i++) (item: list[i], i: i, v: sortValueOf(get(list[i], f.key), kind))];
  final sign = value.dir == OrderDir.asc ? 1 : -1;
  keyed.sort((a, b) {
    final av = a.v;
    final bv = b.v;
    if (av == null || bv == null) return av == null && bv == null ? a.i - b.i : (av == null ? 1 : -1);
    final c = kind == OrderKind.text ? compareText(av as String, bv as String) : (av as num).compareTo(bv as num);
    return c != 0 ? sign * c.sign : a.i - b.i;
  });
  return [for (final k in keyed) k.item];
}

// ═══════════════ جدولٌ بلا عمودٍ افتراضيّ («حسب الشركة») ═══════════════

/// عمودٌ مرتَّبٌ به (-1 = الاسم) — null في الحالة = ترتيب القائمة كما وصلت.
class ColOrder {
  const ColOrder(this.col, this.dir);
  final int col;
  final OrderDir dir;

  @override
  bool operator ==(Object other) => other is ColOrder && other.col == col && other.dir == dir;

  @override
  int get hashCode => Object.hash(col, dir);
}

/// نقرة عنوان عمودٍ في جدولٍ ترتيبه الافتراضيّ ليس عموداً: أوّل نقرة باتّجاهه الأنفع، الثانية تقلبه، الثالثة ترجع الأصل.
ColOrder? nextColOrder(ColOrder? cur, int col, OrderDir first) {
  if (cur == null || cur.col != col) return ColOrder(col, first);
  if (cur.dir == first) return ColOrder(col, first == OrderDir.asc ? OrderDir.desc : OrderDir.asc);
  return null;
}

// ═══════════════ الحفظ (المفاتيح نفسها بالموقع) ═══════════════

class OrderPrefs {
  OrderPrefs._();

  /// مفتاح ترتيب حركات التقرير — كالموقع «report.v2.<id>.sort».
  static String rowsKey(String report) => 'report.v2.$report.sort';

  /// مفتاح ترتيب «حسب الشركة» — كالموقع «report.v2.<id>.cosort».
  static String companiesKey(String report) => 'report.v2.$report.cosort';

  /// المحفوظ لهذه الشاشة على هذا الجهاز — حقلٌ لم يعد موجوداً أو اتّجاهٌ غريب أو تخزينٌ تعذّر ⇒ [initial].
  static Future<OrderValue> load(String key, List<OrderField> fields, OrderValue initial) async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(key);
      if (raw == null) return initial;
      final j = jsonDecode(raw);
      if (j is! Map) return initial;
      final k = j['k'];
      final d = j['d'];
      if (d != 'asc' && d != 'desc') return initial;
      for (final f in fields) {
        if (f.key == k) return OrderValue(f.key, d == 'asc' ? OrderDir.asc : OrderDir.desc);
      }
      return initial;
    } catch (_) {
      return initial;
    }
  }

  static Future<void> save(String key, OrderValue v) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(key, jsonEncode({'k': v.key, 'd': v.dir.name}));
    } catch (_) {
      // تفضيلٌ لا أكثر
    }
  }

  /// عمود «حسب الشركة» المحفوظ — خارج الجدول ([cols] أعمدة الأرقام، و-1 الاسم) أو تالفٌ ⇒ null.
  static Future<ColOrder?> loadCol(String key, int cols) async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(key);
      if (raw == null) return null;
      final j = jsonDecode(raw);
      if (j is! Map) return null;
      final c = j['c'];
      final d = j['d'];
      if (c is! int || c < -1 || c >= cols || (d != 'asc' && d != 'desc')) return null;
      return ColOrder(c, d == 'asc' ? OrderDir.asc : OrderDir.desc);
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveCol(String key, ColOrder? v) async {
    try {
      final p = await SharedPreferences.getInstance();
      if (v == null) {
        await p.remove(key);
      } else {
        await p.setString(key, jsonEncode({'c': v.col, 'd': v.dir.name}));
      }
    } catch (_) {
      // تفضيلٌ لا أكثر
    }
  }
}
