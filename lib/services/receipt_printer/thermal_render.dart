import 'package:flutter/foundation.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

import '../print_output.dart';
import 'escpos.dart';
import 'receipt_printer_prefs.dart';

/// صفحةٌ مرسومة: بكسلات RGBA كما يرسمها أندرويد وآيفون (ألفا مضروبة مسبقاً، وما حول الحبر شفّاف).
@immutable
class RgbaPage {
  const RgbaPage(this.width, this.height, this.pixels);

  final int width;
  final int height;
  final Uint8List pixels;
}

/// الوصل ⇒ نقاطٌ بعرض رأس الطابعة الحراريّة.
///
/// المصدر **PDF الوصل نفسه** (التصميم والبيانات كما في نافذة الطباعة و«صورة»)، مُعاد بناؤه لفّةً على ورق الطابعة
/// ([PrintDoc.roll]: ٥٨ أو ٨٠ ملم بحافّتيه غير المطبوعتين)، ثمّ يُرسم بدقّة الرأس (٨ نقاط لكلّ ملم) ويُقصّ منه
/// المطبوع وحده (٣٨٤ / ٥٧٦ نقطة). الحروف العربيّة متّصلة والاتّجاه والأرقام كما رُسمت — لا ترميز نصٍّ في الطابعة.
class ThermalRender {
  ThermalRender._();

  /// PDF ⇒ صفحته الأولى بكسلاتٍ بدقّة [dpi] — يُستبدل في الاختبارات (لا مكتبة رسمٍ هناك).
  @visibleForTesting
  static Future<RgbaPage> Function(Uint8List pdf, double dpi) rasterizer = _raster;

  /// أطول وصلٍ يُقبل (٣ أمتار) — حمايةٌ من صفحةٍ بلا نهاية.
  static const int maxRows = 24000;

  static Future<MonoImage> receipt(PrintDoc doc, ReceiptPaper paper) async {
    final roll = doc.roll;
    final Uint8List pdf;
    final double dpi;
    final int left;
    if (roll != null) {
      pdf = await roll(paper.pageFormat);
      dpi = ReceiptPaper.dpi;
      left = paper.leftDots;
    } else {
      // مستندٌ بلا إعادة بناء: الصفحة كلّها تصغر لعرض الرأس.
      pdf = doc.bytes;
      final w = doc.format.width;
      dpi = paper.dots * PdfPageFormat.inch / (w.isFinite && w > 0 ? w : PdfPageFormat.roll80.width);
      left = 0;
    }
    final page = await rasterizer(pdf, dpi);
    if (page.width <= 0 || page.height <= 0) throw StateError('raster: empty page');
    if (page.height > maxRows) throw StateError('raster: ${page.height} rows');
    // ملايين البكسلات خارج خيط الواجهة — لا تجمّد الشاشة.
    return compute(_toMono, _MonoJob(page.pixels, page.width, page.height, paper.dots, left));
  }

  static Future<RgbaPage> _raster(Uint8List pdf, double dpi) async {
    await for (final p in Printing.raster(pdf, pages: const [0], dpi: dpi)) {
      return RgbaPage(p.width, p.height, p.pixels);
    }
    throw StateError('raster: no pages');
  }
}

@immutable
class _MonoJob {
  const _MonoJob(this.pixels, this.width, this.height, this.dots, this.left);

  final Uint8List pixels;
  final int width;
  final int height;
  final int dots;
  final int left;
}

MonoImage _toMono(_MonoJob j) =>
    MonoImage.fromRgba(j.pixels, j.width, j.height, targetWidth: j.dots, left: j.left).trimBottom();
