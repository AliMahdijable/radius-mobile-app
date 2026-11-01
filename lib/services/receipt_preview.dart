import 'dart:async';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'receipt_pdf.dart';

/// بايتات المعاينة وطول الصفحة (نقاط PDF) — لا [PrintDoc] (فيه دالّة إعادة البناء، لا تعبر بين الخيوط).
typedef ReceiptPreviewBytes = ({Uint8List bytes, double widthPt, double heightPt});

/// يبني PDF المعاينة: الخطّ من بايتاته داخل الخيط نفسه، وبلا ضغط — رسم الطباعة حرفاً (عدا إعادة بناء ويندوز على ورق
/// الطابعة). يُستدعى داخل [Isolate.run] فلا يحجز واجهة التطبيق.
Future<ReceiptPreviewBytes> buildPreviewBytes(ReceiptDoc doc, bool a4, ByteData regular, ByteData bold) async {
  final theme = pw.ThemeData.withFont(base: pw.Font.ttf(regular), bold: pw.Font.ttf(bold));
  final pdf = await ReceiptPdf.build(doc, a4: a4, theme: theme, compress: false);
  return (bytes: pdf.bytes, widthPt: pdf.format.width, heightPt: pdf.format.height);
}

/// صورة الصفحة الأولى بدقّة [dpi] — `Printing.raster` ثمّ `toImage` (بلا PNG).
typedef ReceiptRasterizer = Future<ui.Image> Function(Uint8List bytes, double dpi);

/// بناء البايتات (في خيطٍ آخر افتراضاً).
typedef ReceiptPreviewBuilder = Future<ReceiptPreviewBytes> Function(ReceiptDoc doc, bool a4);

/// المعاينة الحيّة (spec §4.5): انتظار ٢٠٠ ملّي ثانية بعد آخر تعديل، ثمّ بناءٌ في خيطٍ آخر وتحويلٌ لصورة. عدّاد أجيالٍ
/// يُسقط نتيجةً قديمة، وتعديلٌ وصل أثناء البناء يُعاد بناؤه بعده (لا يبقى الوصل المعروض قديماً) — ما يُسقطه
/// `PdfPreview` الجاهز.
class ReceiptPreviewController extends ChangeNotifier {
  ReceiptPreviewController({
    ReceiptPreviewBuilder? builder,
    ReceiptRasterizer? rasterizer,
    this.debounce = const Duration(milliseconds: 200),
  })  : _builder = builder ?? _isolateBuild,
        _raster = rasterizer ?? _printingRaster;

  final ReceiptPreviewBuilder _builder;
  final ReceiptRasterizer _raster;
  final Duration debounce;

  Timer? _timer;
  ({ReceiptDoc doc, bool a4, double dpi})? _pending;
  bool _running = false;
  bool _disposed = false;
  int _generation = 0;

  ui.Image? _image;
  double? _heightMm;
  double? _widthMm;
  String? _error;
  Duration? _lastRender;

  ui.Image? get image => _image;

  /// طول الوصل بالملّيمتر (من مقاس الصفحة المبنيّة) — «الطول ≈ N ملم».
  double? get heightMm => _heightMm;
  double? get widthMm => _widthMm;
  String? get error => _error;

  /// زمن آخر معاينة (بناء + تحويل) — للقياس على هاتف المالك (الحدّ ٦٠٠ ملّي ثانية).
  Duration? get lastRender => _lastRender;

  /// يعمل الآن (أو ينتظر مهلة التعديل).
  bool get busy => _running || _timer != null;

  /// جيل آخر طلب — نتيجةٌ بُنيت لجيلٍ أقدم تُسقط (للاختبار).
  @visibleForTesting
  int get generation => _generation;

  /// كم بناءً جرى (للاختبار).
  @visibleForTesting
  int builds = 0;

  /// طلب معاينة: آخر طلبٍ يفوز.
  void request(ReceiptDoc doc, {required bool a4, required double dpi}) {
    _pending = (doc: doc, a4: a4, dpi: dpi);
    _generation++;
    _timer?.cancel();
    _timer = Timer(debounce, _kick);
    _notify();
  }

  void _kick() {
    _timer = null;
    unawaited(_run());
  }

  Future<void> _run() async {
    if (_running || _disposed) return;
    final job = _pending;
    if (job == null) return;
    _pending = null;
    final gen = _generation;
    _running = true;
    builds++;
    final sw = Stopwatch()..start();
    try {
      final built = await _builder(job.doc, job.a4);
      // تعديلٌ أحدث وصل أثناء البناء ⇒ هذه النتيجة قديمة: لا تُحوَّل صورةً، ويُبنى الأحدث بعدها.
      if (!_disposed && gen == _generation) {
        final img = await _raster(built.bytes, job.dpi);
        if (_disposed || gen != _generation) {
          img.dispose();
        } else {
          _image?.dispose();
          _image = img;
          _heightMm = built.heightPt / PdfPageFormat.mm;
          _widthMm = built.widthPt / PdfPageFormat.mm;
          _error = null;
          _lastRender = sw.elapsed;
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[ReceiptPreview] $e');
      if (!_disposed && gen == _generation) _error = 'تعذّرت المعاينة';
    } finally {
      _running = false;
    }
    if (_disposed) return;
    _notify();
    if (_pending != null && _timer == null) unawaited(_run());
  }

  static Future<ReceiptPreviewBytes> _isolateBuild(ReceiptDoc doc, bool a4) async {
    final fonts = await _fonts();
    return Isolate.run(() => buildPreviewBytes(doc, a4, fonts.$1, fonts.$2));
  }

  static Future<(ByteData, ByteData)>? _fontsF;
  static Future<(ByteData, ByteData)> _fonts() => _fontsF ??= () async {
        final r = await rootBundle.load('assets/fonts/IBMPlexSansArabic-400.ttf');
        final b = await rootBundle.load('assets/fonts/IBMPlexSansArabic-700.ttf');
        return (r, b);
      }();

  static Future<ui.Image> _printingRaster(Uint8List bytes, double dpi) async {
    await for (final page in Printing.raster(bytes, pages: const [0], dpi: dpi)) {
      return page.toImage();
    }
    throw StateError('no page');
  }

  /// الدقّة: لا تتجاوز ٢٠٠ نقطة في البوصة، وتكفي عرض اللوحة بكثافة الشاشة.
  static double dpiFor({required double paneWidthDp, required double devicePixelRatio, required double paperMm}) {
    final need = devicePixelRatio * paneWidthDp * 25.4 / math.max(paperMm, 1);
    return need.clamp(72, 200).toDouble();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _image?.dispose();
    _image = null;
    super.dispose();
  }
}

/// هل يرسم هذا النظام PDF صورةً؟ (أندرويد ٥+، iOS، ماك، ويندوز) — وإلّا زرّ «اطبع تجربة».
Future<bool> receiptCanRaster() async {
  try {
    return (await Printing.info()).canRaster;
  } catch (_) {
    return false;
  }
}
