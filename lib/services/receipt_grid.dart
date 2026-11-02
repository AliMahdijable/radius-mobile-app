import 'receipt_layout.dart';

/// «تصميم الوصل» v4 «الشبكة» في التطبيق (٢ نوفمبر — المالك: «اريد شي احترافي بحيث الوكيل سحب وتحريك يصمم الوصل وخط سمه
/// ولونه كل متغير وعنوانه» ثمّ «الطباعه… عممها ع الكل»). التصميم يُصنع في الموقع (`/print-templates/designer`) ويُحفظ في
/// `design.layout` = `{v:4, grid:{rows:[{cells:[…]}]}, currency}`؛ هنا قراءته وقيمه — نسخةٌ حرفيّة من
/// `client-v2/src/lib/receipt-grid.ts` (gridVars · gridFill · amountWords · الحدود)، والرسم PDF في `receipt_pdf_grid.dart`.
/// نقيّ: لا ساعة ولا شبكة؛ ما لا يُفهم افتراضيّ (لا رمي).

const List<int> gridPt = [6, 7, 8, 9, 10, 11, 12, 13, 14, 16, 18, 20, 22, 24, 28];
const List<String> gridWeights = ['400', '700', '800'];
const List<String> gridBoxes = ['none', 'solid', 'dashed', 'dotted'];
const List<String> gridAligns = ['right', 'center', 'left'];
const List<String> gridCellTypes = ['field', 'text', 'logo', 'qr', 'line', 'space'];

/// = الخادم LIMITS4 والموقع GRID_LIMITS.
abstract final class GridLimits {
  static const int wMin = 1;
  static const int wMax = 12;
  static const double sizeMin = 6;
  static const double sizeMax = 50;
  static const double gapMax = 10;
  static const double spaceMax = 20;
  static const double radiusMax = 3;
  static const double padMax = 3;
  static const double thickMin = 0.5;
  static const double thickMax = 2;
}

const List<String> _moneyKinds = ['activation', 'extension', 'payment'];

/// متغيّرات الشبكة: متغيّرات الوصل المعتادة + التاريخ والوقت، من أصل، المتبقّي، المبلغ كتابةً.
final List<ReceiptVarDef> gridVariables = [
  ...receiptVariables,
  const ReceiptVarDef('datetime', 'التاريخ والوقت', receiptKinds, 'receipt'),
  const ReceiptVarDef('total_amount', 'من أصل (المبلغ الكلّي)', _moneyKinds, 'money'),
  const ReceiptVarDef('remaining_amount', 'المتبقّي', _moneyKinds, 'money'),
  const ReceiptVarDef('amount_words', 'المبلغ المستلم كتابةً', _moneyKinds, 'money'),
];
final Set<String> _gridVarIds = {for (final v in gridVariables) v.id};

String gridVarLabel(String? id) {
  for (final v in gridVariables) {
    if (v.id == id) return v.label;
  }
  return id ?? '';
}

final RegExp _hex = RegExp(r'^#[0-9a-fA-F]{6}$');
num? _n(Object? v) => v is num && v.isFinite ? v : null;
String? _s(Object? v) => v is String ? v : null;

/// نمط خانة/عنوان — كلّ مفتاحٍ اختياريّ (الغائب ⇒ الافتراضيّ).
class GridStyle {
  const GridStyle({this.font, this.pt, this.weight, this.color, this.bg, this.box, this.radius, this.pad, this.align});
  final String? font;
  final num? pt;
  final String? weight;
  final String? color;
  final String? bg;
  final String? box;
  final num? radius;
  final num? pad;
  final String? align;

  static GridStyle? from(Object? raw) {
    if (raw is! Map) return null;
    return GridStyle(
      font: _s(raw['font']),
      pt: _n(raw['pt']),
      weight: _s(raw['weight']),
      color: _s(raw['color']),
      bg: _s(raw['bg']),
      box: _s(raw['box']),
      radius: _n(raw['radius']),
      pad: _n(raw['pad']),
      align: _s(raw['align']),
    );
  }
}

/// النمط بعد الافتراضيّ (= styleDecls في الموقع).
class GridResolvedStyle {
  const GridResolvedStyle({
    required this.pt,
    required this.weight,
    required this.color,
    required this.align,
    this.bg,
    this.box,
    this.radiusMm = 0,
    this.padMm = 0,
  });
  final double pt;
  final String weight;
  final String color;
  final String align;
  final String? bg;

  /// solid · dashed · dotted — null = بلا إطار.
  final String? box;
  final double radiusMm;

  /// الحشوة الأفقيّة بالملّيمتر (العموديّة × ٠٫٦).
  final double padMm;

  bool get bold => weight != '400';

  static GridResolvedStyle of(GridStyle? s, GridResolvedStyle def) {
    final pt = s?.pt != null && gridPt.contains(s!.pt) ? s.pt!.toDouble() : def.pt;
    final weight = s?.weight != null && gridWeights.contains(s!.weight) ? s.weight! : def.weight;
    final color = s?.color != null && _hex.hasMatch(s!.color!) ? s.color! : def.color;
    final align = s?.align != null && gridAligns.contains(s!.align) ? s.align! : def.align;
    final bg = s?.bg != null && _hex.hasMatch(s!.bg!) ? s.bg : null;
    final box = s?.box != null && s!.box != 'none' && gridBoxes.contains(s.box) ? s.box : null;
    final radius = s?.radius != null && s!.radius! > 0 ? s.radius!.toDouble() : 0.0;
    final pad = s?.pad != null ? s!.pad!.toDouble() : (box != null ? 0.8 : (bg != null ? 1.0 : 0.0));
    return GridResolvedStyle(pt: pt, weight: weight, color: color, align: align, bg: bg, box: box, radiusMm: radius, padMm: pad);
  }
}

/// افتراضيّات القيمة والعنوان والنصّ (= gridDefaults): لون النصّ من مفاتيح v1.
({GridResolvedStyle value, GridResolvedStyle label, GridResolvedStyle text}) gridDefaults(Map<String, dynamic>? design) {
  final tc = design?['text_color'];
  final color = tc is String && _hex.hasMatch(tc) ? tc : '#000000';
  return (
    value: GridResolvedStyle(pt: 11, weight: '700', color: color, align: 'center'),
    label: GridResolvedStyle(pt: 10, weight: '700', color: color, align: 'right'),
    text: GridResolvedStyle(pt: 11, weight: '700', color: color, align: 'center'),
  );
}

class GridCell {
  const GridCell({
    required this.type,
    this.w = 1,
    this.varId,
    this.label,
    this.labelPos = 'start',
    this.text,
    this.sizeMm,
    this.line = 'solid',
    this.thick,
    this.h,
    this.style,
    this.labelStyle,
  });
  final String type;
  final int w;
  final String? varId;

  /// null ⇒ اسم المتغيّر.
  final String? label;

  /// start · top · none.
  final String labelPos;
  final String? text;
  final num? sizeMm;
  final String line;
  final num? thick;
  final num? h;
  final GridStyle? style;
  final GridStyle? labelStyle;

  static GridCell? from(Object? raw) {
    if (raw is! Map) return null;
    final type = raw['type'];
    if (type is! String || !gridCellTypes.contains(type)) return null;
    final w = _n(raw['w']);
    final pos = raw['label_pos'];
    final line = raw['line'];
    return GridCell(
      type: type,
      w: w == null ? 1 : w.round().clamp(GridLimits.wMin, GridLimits.wMax),
      varId: _s(raw['var']),
      label: _s(raw['label']),
      labelPos: pos is String && const ['start', 'top', 'none'].contains(pos) ? pos : 'start',
      text: _s(raw['text']),
      sizeMm: _n(raw['size_mm']),
      line: line is String && const ['solid', 'dashed', 'dotted'].contains(line) ? line : 'solid',
      thick: _n(raw['thick']),
      h: _n(raw['h']),
      style: GridStyle.from(raw['style']),
      labelStyle: GridStyle.from(raw['label_style']),
    );
  }
}

class GridRow {
  const GridRow({required this.cells, this.gap, this.only = const []});
  final List<GridCell> cells;

  /// مسافةٌ قبل الصفّ بالملّيمتر (الغائب ⇒ ٠٫٨).
  final num? gap;

  /// يظهر في هذه الأنواع وحدها (الفارغ = كلّها).
  final List<String> only;

  static GridRow? from(Object? raw) {
    if (raw is! Map) return null;
    final cells = raw['cells'];
    final only = raw['only'];
    return GridRow(
      cells: cells is List ? cells.map(GridCell.from).whereType<GridCell>().toList() : const [],
      gap: _n(raw['gap']),
      only: only is List ? only.whereType<String>().toList() : const [],
    );
  }
}

class GridLayout {
  const GridLayout({required this.rows, this.currency});
  final List<GridRow> rows;
  final String? currency;

  /// `{v:4, grid:{rows:[…]}}` وحده (= isGridLayout في الموقع)؛ غيره null (يُطبع بطريقه القديم).
  static GridLayout? from(Object? raw) {
    if (raw is! Map || raw['v'] != 4) return null;
    final grid = raw['grid'];
    if (grid is! Map || grid['rows'] is! List) return null;
    return GridLayout(
      rows: (grid['rows'] as List).map(GridRow.from).whereType<GridRow>().toList(),
      currency: raw['currency'] is String ? raw['currency'] as String : null,
    );
  }
}

// ── التفقيط: «فقط خمسة وثلاثون ألف دينار عراقي لا غير» ──
const _ones = [
  '', 'واحد', 'اثنان', 'ثلاثة', 'أربعة', 'خمسة', 'ستة', 'سبعة', 'ثمانية', 'تسعة', 'عشرة', 'أحد عشر', 'اثنا عشر', //
  'ثلاثة عشر', 'أربعة عشر', 'خمسة عشر', 'ستة عشر', 'سبعة عشر', 'ثمانية عشر', 'تسعة عشر',
];
const _tens = ['', '', 'عشرون', 'ثلاثون', 'أربعون', 'خمسون', 'ستون', 'سبعون', 'ثمانون', 'تسعون'];
const _hundreds = ['', 'مئة', 'مئتان', 'ثلاثمئة', 'أربعمئة', 'خمسمئة', 'ستمئة', 'سبعمئة', 'ثمانمئة', 'تسعمئة'];
const _scales = [
  ['', '', '', ''],
  ['ألف', 'ألفان', 'آلاف', 'ألف'],
  ['مليون', 'مليونان', 'ملايين', 'مليون'],
  ['مليار', 'ملياران', 'مليارات', 'مليار'],
];

String _under1000(int n) {
  final h = n ~/ 100;
  final r = n % 100;
  final parts = <String>[];
  if (h > 0) parts.add(_hundreds[h]);
  if (r > 0) {
    if (r < 20) {
      parts.add(_ones[r]);
    } else {
      final t = r ~/ 10;
      final o = r % 10;
      parts.add(o > 0 ? '${_ones[o]} و${_tens[t]}' : _tens[t]);
    }
  }
  return parts.join(' و');
}

String _groupWords(int n, int scale) {
  if (scale == 0) return _under1000(n);
  final s = _scales[scale];
  if (n == 1) return s[0];
  if (n == 2) return s[1];
  if (n >= 3 && n <= 10) return '${_under1000(n)} ${s[2]}';
  return '${_under1000(n)} ${s[3]}';
}

/// عددٌ صحيح ⇒ كلماتٌ عربيّة (حتى ٩٩٩ مليار): 35000 ⇒ «خمسة وثلاثون ألف».
String numberWords(num value) {
  var n = value.abs().round();
  if (n == 0) return 'صفر';
  final groups = <String>[];
  var scale = 0;
  while (n > 0 && scale < _scales.length) {
    final g = n % 1000;
    if (g > 0) groups.insert(0, _groupWords(g, scale));
    n ~/= 1000;
    scale += 1;
  }
  return groups.join(' و');
}

/// المبلغ كتابةً بعملة الوصل: الدينار (أو بلا وحدة) ⇒ «دينار عراقي».
String amountWords(num value, [String currency = receiptDefaultCurrency]) {
  final c = currency.trim();
  final unit = c.isEmpty || RegExp(r'^(د\.?ع|دينار.*|IQD)$', caseSensitive: false).hasMatch(c) ? 'دينار عراقي' : c;
  return 'فقط ${numberWords(value)} $unit لا غير';
}

String _money(num n, String currency) {
  final v = n.abs().round();
  final grouped = v.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
  return currency.isEmpty ? grouped : '$grouped $currency';
}

/// المدفوع في هذا الوصل: الدفع ⇒ المبلغ · نقداً ⇒ المبلغ · جزئيّ ⇒ الجزء · آجل ⇒ ٠.
num? _paidOf(ReceiptInput input) {
  final amount = input.amount;
  if (input.kind == 'payment') return amount;
  if (input.paymentType == 'cash') return amount;
  if (input.paymentType == 'partial-cash') return input.partialAmount;
  if (input.paymentType == 'non-cash') return 0;
  return null;
}

/// قيم متغيّرات الشبكة (= gridVars في الموقع).
Map<String, String> gridVars(ReceiptInput input, [String currency = receiptDefaultCurrency]) {
  final out = Map<String, String>.from(receiptVars(input, currency));
  final kind = input.kind;
  final amount = input.amount;
  final paid = _paidOf(input);
  final nb = input.newBalance;
  num? total;
  num? remaining;
  if (kind == 'payment') {
    // الدين قبل الدفع = بعده − المدفوع (سالبٌ = دين)
    total = amount != null && nb != null ? (nb - amount < 0 ? (nb - amount).abs() : 0) : amount;
    remaining = nb != null ? (nb < 0 ? nb.abs() : 0) : null;
  } else if (kind == 'activation' || kind == 'extension') {
    total = amount;
    remaining = amount != null && paid != null ? (amount - paid < 0 ? 0 : amount - paid) : null;
  }
  out['datetime'] = input.issuedText.trim();
  out['total_amount'] = total != null ? _money(total, currency) : '';
  out['remaining_amount'] = remaining != null ? _money(remaining, currency) : '';
  out['amount_words'] = paid != null && paid > 0 ? amountWords(paid, currency) : '';
  for (final v in gridVariables) {
    if (!v.kinds.contains(kind)) out[v.id] = '';
  }
  return out;
}

/// يملأ {متغيّر}: المجهول يبقى حرفيّاً، والمعروف الفارغ ''، ثمّ تُطوى المسافات وتُحذف الأسطر الفارغة. hidden = النصّ فارغ،
/// أو فيه متغيّرٌ معروفٌ واحدٌ على الأقلّ وكلّها فارغة (لا يُطبع نصٌّ نصفه فراغ). (= gridFill في الموقع)
({String text, bool hidden}) gridFill(String text, Map<String, String> vars) {
  var known = 0;
  var filled = 0;
  final out = text.replaceAllMapped(RegExp(r'\{([a-z_]+)\}'), (m) {
    final name = m.group(1)!;
    if (!_gridVarIds.contains(name)) return m.group(0)!;
    known += 1;
    final v = vars[name] ?? '';
    if (v.isNotEmpty) filled += 1;
    return v;
  });
  final lines = out
      .split(RegExp(r'\r?\n'))
      .map((l) => l.replaceAll(RegExp(r'[ \t ]+'), ' ').trim())
      .where((l) => l.isNotEmpty)
      .toList();
  final res = lines.join('\n');
  return (text: res, hidden: res.isEmpty || (known > 0 && filled == 0));
}

/// قيمة حقلٍ بمتغيّره (المجهول ⇒ '').
String gridValue(GridCell c, Map<String, String> vars) => c.varId != null && _gridVarIds.contains(c.varId) ? (vars[c.varId] ?? '') : '';
