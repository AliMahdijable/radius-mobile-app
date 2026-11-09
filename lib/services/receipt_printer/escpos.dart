import 'package:flutter/foundation.dart';

/// صورةٌ بلونين بعرض رأس الطابعة الحراريّة — ترتيب أمر ESC/POS «GS v 0» نفسه: صفوفٌ متتالية، كلّ صفٍّ
/// `ceil(width / 8)` بايت، البتّ الأعلى أوّل نقطةٍ من اليسار، و١ = نقطةٌ سوداء (تُحرق).
///
/// الوصل يصل الطابعة **صورةً** لا نصّاً: الطابعات الصينيّة لا تعرف تشكيل العربيّ ولا اتّجاهه، فالحروف تخرج
/// منفصلةً مقلوبة. الصورة من PDF الوصل نفسه (الخطّ والتصميم والأرقام كما تُرى) فلا يُعاد تشكيل شيء.
@immutable
class MonoImage {
  MonoImage(this.width, this.height, this.bytes) {
    if (width <= 0 || height < 0 || bytes.length != rowBytesOf(width) * height) {
      throw ArgumentError('MonoImage ${width}x$height needs ${rowBytesOf(width) * height} bytes, got ${bytes.length}');
    }
  }

  final int width;
  final int height;
  final Uint8List bytes;

  static int rowBytesOf(int width) => (width + 7) >> 3;

  int get rowBytes => rowBytesOf(width);

  bool isBlack(int x, int y) => (bytes[y * rowBytes + (x >> 3)] & (0x80 >> (x & 7))) != 0;

  /// صورةٌ بيضاء — للاختبار.
  factory MonoImage.blank(int width, int height) => MonoImage(width, height, Uint8List(rowBytesOf(width) * height));

  /// بكسلات RGBA (كما يرسمها أندرويد وآيفون للـPDF: ألفا مضروبةٌ مسبقاً، وما حول الحبر **شفّاف**) ⇒ نقاطٌ بعرض
  /// [targetWidth] تبدأ من العمود [left] في الصورة. الشفّاف أبيض (الورق)، والأغمق من [threshold] أسود.
  /// ما يقع خارج الصورة أبيض — لا يُخترع حبر.
  static MonoImage fromRgba(
    Uint8List rgba,
    int width,
    int height, {
    required int targetWidth,
    int left = 0,
    int threshold = defaultThreshold,
  }) {
    if (rgba.length < width * height * 4) {
      throw ArgumentError('rgba: ${rgba.length} bytes for ${width}x$height');
    }
    final rb = rowBytesOf(targetWidth);
    final out = Uint8List(rb * height);
    // اللمعان × ١٠٠٠ مقارنةً بالعتبة × ١٠٠٠ — أعدادٌ صحيحة بلا كسور في الحلقة.
    final cut = threshold * 1000;
    for (var y = 0; y < height; y++) {
      final src = y * width * 4;
      final dst = y * rb;
      for (var x = 0; x < targetWidth; x++) {
        final sx = left + x;
        if (sx < 0 || sx >= width) continue;
        final i = src + sx * 4;
        final a = rgba[i + 3];
        if (a == 0) continue;
        // على ورقٍ أبيض: اللون المضروب + (٢٥٥ − ألفا).
        final paper = 255 - a;
        var r = rgba[i] + paper;
        var g = rgba[i + 1] + paper;
        var b = rgba[i + 2] + paper;
        if (r > 255) r = 255;
        if (g > 255) g = 255;
        if (b > 255) b = 255;
        if (299 * r + 587 * g + 114 * b < cut) out[dst + (x >> 3)] |= 0x80 >> (x & 7);
      }
    }
    return MonoImage(targetWidth, height, out);
  }

  /// عتبة الأسود: أغمق قليلاً من المنتصف — حواف الحروف المنعَّمة تُحسب حبراً فلا تنقطع خطوط العربيّ الرفيعة
  /// على الورق الحراريّ، والرماديّ الفاتح (خلفيّات الأقسام) يبقى أبيض.
  static const int defaultThreshold = 150;

  /// بلا الأسطر البيضاء في الذيل (يُبقي [keep] منها) — الطابعة تُخرج الورق بعدها بأمر التغذية.
  MonoImage trimBottom({int keep = 8}) {
    final rb = rowBytes;
    var last = height - 1;
    while (last >= 0) {
      var blank = true;
      for (var i = last * rb; i < (last + 1) * rb; i++) {
        if (bytes[i] != 0) {
          blank = false;
          break;
        }
      }
      if (!blank) break;
      last--;
    }
    final rows = (last + 1 + keep).clamp(0, height);
    if (rows == height) return this;
    return MonoImage(width, rows, Uint8List.sublistView(bytes, 0, rows * rb));
  }
}

/// ما قالته الطابعة عن نفسها حين سُئلت (null = لم تُجب أو لم يُفهم ردّها — كثيرٌ منها لا يجيب).
@immutable
class PrinterSignal {
  const PrinterSignal({
    this.paperOut = false,
    this.paperLow = false,
    this.coverOpen = false,
    this.offline = false,
    this.error = false,
  });

  final bool paperOut;
  final bool paperLow;
  final bool coverOpen;
  final bool offline;
  final bool error;

  @override
  String toString() =>
      'PrinterSignal(paperOut: $paperOut, paperLow: $paperLow, coverOpen: $coverOpen, offline: $offline, error: $error)';
}

/// أوامر ESC/POS التي نحتاجها — الطباعة صورةً («GS v 0» شرائط)، والتغذية والقصّ، وأسئلة الحالة.
class EscPos {
  EscPos._();

  static const int esc = 0x1B;
  static const int gs = 0x1D;
  static const int dle = 0x10;
  static const int eot = 0x04;

  /// «ESC @» — يمسح ما بقي في ذاكرة الطابعة من أمرٍ سابق ويرجع إعداداتها.
  static Uint8List initialize() => Uint8List.fromList(const [esc, 0x40]);

  /// «ESC d n» — يُخرج الورق [lines] أسطراً (يصل الوصل لحافّة القطع).
  static Uint8List feed(int lines) => Uint8List.fromList([esc, 0x64, lines.clamp(0, 255)]);

  /// «GS V B 0» — يغذّي حتى موضع القاطع ويقطع جزئيّاً. الطابعة بلا قاطع تتجاهله.
  static Uint8List cut() => Uint8List.fromList(const [gs, 0x56, 0x42, 0x00]);

  /// «GS v 0» لصفوف [y0] … [y0] + [rows] من [img]: ٨ بايت رأس (m=0 حجمٌ عاديّ، xL xH = بايتات الصفّ،
  /// yL yH = عدد الصفوف) ثمّ البيانات كما هي.
  static Uint8List rasterBand(MonoImage img, int y0, int rows) {
    if (y0 < 0 || rows <= 0 || y0 + rows > img.height) {
      throw RangeError('band $y0+$rows outside 0..${img.height}');
    }
    final xb = img.rowBytes;
    final out = Uint8List(8 + xb * rows);
    out[0] = gs;
    out[1] = 0x76; // v
    out[2] = 0x30; // 0
    out[3] = 0; // m: normal
    out[4] = xb & 0xFF;
    out[5] = (xb >> 8) & 0xFF;
    out[6] = rows & 0xFF;
    out[7] = (rows >> 8) & 0xFF;
    out.setRange(8, out.length, img.bytes, y0 * xb);
    return out;
  }

  /// الصورة شرائط من [bandRows] صفّاً — أمرٌ مستقلّ لكلّ شريط: ذاكرة الطابعات الرخيصة صغيرة، والوصل الطويل
  /// بأمرٍ واحدٍ يفيض منها فيخرج مشوّهاً.
  static List<Uint8List> raster(MonoImage img, {int bandRows = 64}) {
    final band = bandRows.clamp(1, 2048);
    return [
      for (var y = 0; y < img.height; y += band) rasterBand(img, y, (img.height - y).clamp(1, band)),
    ];
  }

  /// المهمّة كاملة: تهيئة، ثمّ الشرائط، ثمّ التغذية (والقصّ إن طُلب) في آخر قطعة.
  static List<Uint8List> job(MonoImage img, {int bandRows = 64, int feedLines = 4, bool cut = false}) => [
        initialize(),
        ...raster(img, bandRows: bandRows),
        Uint8List.fromList([...feed(feedLines), if (cut) ...EscPos.cut()]),
      ];

  /// «DLE EOT n» — سؤالٌ فوريّ عن الحالة (١ الطابعة · ٢ سبب التوقّف · ٣ الأعطال · ٤ حسّاس الورق). يُجاب فوراً
  /// ولو كانت الطابعة مشغولة — فيُسأل **قبل** الوصل لا وسطه (داخل بيانات الصورة قد يُفهم بايتاً من الصورة).
  static Uint8List realtimeStatus(int n) => Uint8List.fromList([dle, eot, n]);

  /// «GS r 1» — حالة حسّاس الورق، لكنّه يُنفَّذ **بالدور** بعد ما سبقه: ردّه بعد الوصل يعني أنّ الطابعة أنهت
  /// ما قبله (طبعت الوصل). لا يُرسل إلّا لطابعةٍ أجابت «DLE EOT» (تفهم أسئلة الحالة).
  static Uint8List paperStatusInSequence() => Uint8List.fromList(const [gs, 0x72, 0x01]);

  /// ردّ «DLE EOT [n]»: بايتٌ بنمطٍ ثابت (البتّ ١ و٤ = ١، والبتّ ٠ و٧ = ٠)؛ يُقرأ آخر بايتٍ يطابقه.
  static PrinterSignal? parseRealtime(int n, List<int> response) {
    for (final b in response.reversed) {
      if ((b & 0x93) != 0x12) continue;
      switch (n) {
        case 1:
          return PrinterSignal(offline: (b & 0x08) != 0);
        case 2:
          return PrinterSignal(coverOpen: (b & 0x04) != 0, paperOut: (b & 0x20) != 0, error: (b & 0x40) != 0);
        case 3:
          return PrinterSignal(error: (b & 0x68) != 0);
        case 4:
          return PrinterSignal(paperLow: (b & 0x0C) != 0, paperOut: (b & 0x60) != 0);
      }
      return const PrinterSignal();
    }
    return null;
  }

  /// ردّ «GS r 1»: البتّ ٤ و٧ صفر؛ البتّان ٠–١ قرب نهاية الورق، و٢–٣ نفاده.
  static PrinterSignal? parsePaperStatus(List<int> response) {
    for (final b in response.reversed) {
      if ((b & 0x90) != 0) continue;
      return PrinterSignal(paperLow: (b & 0x03) != 0, paperOut: (b & 0x0C) != 0);
    }
    return null;
  }
}
