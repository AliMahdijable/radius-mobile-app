import '../../core/util/format.dart' show normalizeDigits;

/// نطاق «اكتشاف الأجهزة» (مسح النطاق) — عناوين IPv4 متتالية من [first] إلى [last] (شاملةً، قيمٌ ٣٢ بتّاً).
///
/// المالك ١٤ نوفمبر ٢٠٢٦: «بحث نطاق البرج هسه حاليا يريد فقط /24 او اي سبنت نخلي اختياري يختار رينج من الى مثلا
/// 10.10.10.2-10.10.10.20 … هو يكدر يحدد النطاق يعني ما نقيده فقط بسبنت».
/// قبلها: الشبكة ‎/24‎ وحدها — ‎/N‎ أخرى تُحذف فيُمسح ‎/24‎ بصمت (‎10.10.0.0/22‎ ⇒ ‎10.10.0.1–254‎ فقط)، والمدى داخل
/// ‎/24‎ واحدة بصيغة ‎…5-100‎ وحدها.
/// الآن: [parseScanNetwork] لخانة «شبكة» (‎192.168.1‎، ‎10.70.241.0/24‎، أيّ ‎/N‎ بحدّه الحقيقيّ، ‎…5-100‎، ‎A-B‎ كاملين)،
/// و[parseScanFromTo] لخانتي «من – إلى» (آخرٌ كامل أو رقمه الأخير وحده)، ولو عبر أكثر من ‎/24‎.
class ScanRange {
  const ScanRange(this.first, this.last);

  final int first;
  final int last;

  /// أقصى عناوين في مسحةٍ واحدة: ‎/22‎ كاملة (١٠٢٢). أكثر من هذا دقائق طويلة وآلاف المقابس — يُقسَّم.
  static const int maxCount = 1024;

  int get count => last - first + 1;
  String get firstIp => ipOf(first);
  String get lastIp => ipOf(last);

  List<String> get ips => [for (var v = first; v <= last; v++) ipOf(v)];

  static String ipOf(int v) => '${(v >> 24) & 255}.${(v >> 16) & 255}.${(v >> 8) & 255}.${v & 255}';

  /// ‎a.b.c.d‎ ⇒ قيمته، وإلّا null (أربعة أجزاء ٠–٢٥٥ لا غير).
  static int? valueOf(String ip) {
    final m = RegExp(r'^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$').firstMatch(ip);
    if (m == null) return null;
    var v = 0;
    for (var i = 1; i <= 4; i++) {
      final o = int.parse(m.group(i)!);
      if (o > 255) return null;
      v = (v << 8) | o;
    }
    return v;
  }

  /// للمقارنة والترتيب: ‎10.0.1.2‎ قبل ‎10.0.2.1‎ (لا الجزء الأخير وحده).
  static int sortKey(String ip) => valueOf(ip) ?? 0;

  @override
  bool operator ==(Object other) => other is ScanRange && other.first == first && other.last == last;

  @override
  int get hashCode => Object.hash(first, last);

  @override
  String toString() => '$firstIp-$lastIp ($count)';
}

/// نطاقٌ صالح أو سببٌ بالعربيّة يُعرض للمدير كما هو.
typedef ScanRangeResult = ({ScanRange? range, String? error});

const _examples = 'أمثلة: 192.168.1  •  10.70.241.0/24  •  10.10.10.2-10.10.10.20';

ScanRangeResult _err(String e) => (range: null, error: e);

String _clean(String raw) => (normalizeDigits(raw) ?? raw)
    .trim()
    .replaceAll(RegExp(r'\s+'), '')
    .replaceAll(RegExp('[–—~]'), '-')
    .replaceAll(RegExp('[٫,]'), '.') // فاصلة لوحة الأرقام (العربيّة ‎٫‎ أو ‎,‎) — لا فاصلة في عنوان
    .replaceAll(RegExp(r'\.+$'), '');

ScanRangeResult _checked(int first, int last) {
  if (first > last) return _err('أوّل عنوان أكبر من آخره — اكتب الأصغر أوّلاً');
  final r = ScanRange(first, last);
  if (r.count > ScanRange.maxCount) {
    return _err('النطاق ${r.count} عنواناً — الحدّ ${ScanRange.maxCount} بالمرّة الواحدة؛ ضيّقه أو قسّمه');
  }
  return (range: r, error: null);
}

/// خانة «شبكة»: ‎192.168.1‎ و‎192.168.1.7‎ ⇒ ‎.1–.254‎ (كما كان) · ‎10.70.241.0/24‎ وأيّ ‎/N‎ ⇒ مضيفوها الحقيقيّون ·
/// ‎10.70.241.5-100‎ · ‎10.10.10.2-10.10.10.20‎.
ScanRangeResult parseScanNetwork(String raw) {
  final s = _clean(raw);
  if (s.isEmpty) return _err('اكتب الشبكة — $_examples');

  if (s.contains('-')) {
    final parts = s.split('-');
    if (parts.length != 2) return _err('صيغة غير صحيحة — $_examples');
    return parseScanFromTo(parts[0], parts[1]);
  }

  if (s.contains('/')) {
    final m = RegExp(r'^([\d.]+)/(\d{1,2})$').firstMatch(s);
    if (m == null) return _err('صيغة غير صحيحة — $_examples');
    var ip = m.group(1)!;
    if (RegExp(r'^\d{1,3}\.\d{1,3}\.\d{1,3}$').hasMatch(ip)) ip = '$ip.0';
    final v = ScanRange.valueOf(ip);
    final prefix = int.parse(m.group(2)!);
    if (v == null || prefix > 32) return _err('صيغة غير صحيحة — $_examples');
    final size = 1 << (32 - prefix);
    final net = v & ~(size - 1) & 0xFFFFFFFF;
    final bcast = net + size - 1;
    // ‎/31‎ و‎/32‎ بلا عنوان شبكةٍ وبثّ؛ غيرهما بلاهما.
    return prefix >= 31 ? _checked(net, bcast) : _checked(net + 1, bcast - 1);
  }

  final four = ScanRange.valueOf(s);
  if (four != null) {
    final base = four & 0xFFFFFF00;
    return _checked(base + 1, base + 254);
  }
  if (RegExp(r'^\d{1,3}\.\d{1,3}\.\d{1,3}$').hasMatch(s)) {
    final v = ScanRange.valueOf('$s.0');
    if (v != null) return _checked(v + 1, v + 254);
  }
  return _err('صيغة غير صحيحة — $_examples');
}

/// خانتا «من – إلى»: [from] عنوانٌ كامل، و[to] عنوانٌ كامل أو رقمه الأخير وحده (‎20‎ ⇒ أوّل ثلاثة أجزاءٍ من [from]).
ScanRangeResult parseScanFromTo(String from, String to) {
  final f = _clean(from);
  final t = _clean(to);
  if (f.isEmpty) return _err('اكتب أوّل عنوان — مثال 10.10.10.2');
  final a = ScanRange.valueOf(f);
  if (a == null) return _err('أوّل عنوان غير صحيح — اكتبه كاملاً مثل 10.10.10.2');
  if (t.isEmpty) return _err('اكتب آخر عنوان — كاملاً (10.10.10.20) أو رقمه الأخير (20)');
  int? b;
  if (RegExp(r'^\d{1,3}$').hasMatch(t)) {
    final o = int.parse(t);
    if (o <= 255) b = (a & 0xFFFFFF00) | o;
  } else {
    b = ScanRange.valueOf(t);
  }
  if (b == null) return _err('آخر عنوان غير صحيح — كاملاً (10.10.10.20) أو رقمه الأخير (20)');
  return _checked(a, b);
}
