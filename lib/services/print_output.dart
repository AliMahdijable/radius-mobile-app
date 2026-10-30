import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../core/platform/app_platform.dart';
import 'print_prefs.dart';

/// يعيد بناء المستند على ورق الطابعة كما أرسله النظام قبل الطباعة (عرضه وحواشيه غير المطبوعة).
typedef PrintRefit = Future<Uint8List> Function(PdfPageFormat printerPaper);

/// مستندٌ جاهزٌ للطابعة: بايتات PDF ومقاس صفحته — **محدودٌ دائماً**.
///
/// 🐛 المالك ٢٤ أكتوبر: «زر الطباعة ما يشتغل بكل الحالات» على الحاسبة. ورق الكاشير
/// (`PdfPageFormat.roll80`، الافتراضيّ) طوله لا نهائيّ، ومكتبة الطباعة تمرّر المقاس كما هو:
/// ويندوز يبني منه إعداد ورقٍ بطول صفر فتفشل الطباعة بصمت. [of] يقيس الصفحة بعد بنائها
/// (اللفّة تأخذ طول محتواها) فلا يصل النظامَ طولٌ لا نهائيّ أبداً.
@immutable
class PrintDoc {
  const PrintDoc(this.bytes, this.format, {required this.name, this.refit});

  final Uint8List bytes;
  final PdfPageFormat format;
  final String name;

  /// إعادة البناء على ورق الطابعة ([PrintOutput.bytesFor]) — null = يُطبع كما بُني.
  final PrintRefit? refit;

  /// يحفظ [doc] ويقرأ مقاس صفحته الأولى كما بُنيت.
  static Future<PrintDoc> of(
    pw.Document doc, {
    required String name,
    required PdfPageFormat requested,
    PrintRefit? refit,
  }) async {
    final bytes = await doc.save();
    final pages = doc.document.pdfPageList.pages;
    final built = pages.isEmpty ? requested : pages.first.pageFormat;
    return PrintDoc(bytes, finite(built, requested), name: name, refit: refit);
  }

  /// [f] بلا بُعدٍ لا نهائيّ (ولا هوامش: الصفحة مرسومةٌ سلفاً).
  ///
  /// ⚠️ ولا أقصر من عرضه: مكتبة الطباعة على ويندوز تقلب الورق أفقيّاً متى زاد العرض على الطول،
  /// فيخرج وصلٌ قصير مدوَّراً على ورق الكاشير.
  @visibleForTesting
  static PdfPageFormat finite(PdfPageFormat f, PdfPageFormat requested) {
    double pick(double v, double fallback) => v.isFinite && v > 0 ? v : fallback;
    final w = pick(f.width, pick(requested.width, PdfPageFormat.roll80.width));
    final h = pick(f.height, pick(requested.height, PdfPageFormat.a4.height));
    return PdfPageFormat(w, math.max(h, w + 1));
  }
}

/// خطّ التطبيق نفسه (IBM Plex Sans Arabic المضمَّن) لكلّ ما يُطبع.
///
/// كانت الوصولات تجلبه من خطوط Google عند كلّ طباعة: حاسبةٌ بلا إنترنت لحظتها تُخرج العربيّ
/// مربّعاتٍ (Helvetica)، وأوّل وصلٍ ينتظر التنزيل.
class PdfFonts {
  PdfFonts._();

  static Future<pw.ThemeData>? _theme;

  static Future<pw.ThemeData> theme() async {
    try {
      return await (_theme ??= _load());
    } catch (_) {
      _theme = null;
      rethrow;
    }
  }

  static Future<pw.ThemeData> _load() async {
    final regular = await rootBundle.load('assets/fonts/IBMPlexSansArabic-400.ttf');
    final bold = await rootBundle.load('assets/fonts/IBMPlexSansArabic-700.ttf');
    return pw.ThemeData.withFont(base: pw.Font.ttf(regular), bold: pw.Font.ttf(bold));
  }
}

enum PrintOutcome { printed, cancelled, failed }

@immutable
class PrintResult {
  const PrintResult._(this.outcome, {this.printer, this.error});

  /// [printer] = اسم الطابعة إن أُرسل إليها مباشرةً (بلا نافذة).
  const PrintResult.printed({String? printer}) : this._(PrintOutcome.printed, printer: printer);
  const PrintResult.cancelled() : this._(PrintOutcome.cancelled);
  const PrintResult.failed(String error) : this._(PrintOutcome.failed, error: error);

  final PrintOutcome outcome;
  final String? printer;
  final String? error;

  bool get ok => outcome == PrintOutcome.printed;
}

/// ما يكلّم مكتبة الطباعة — تُستبدل في الاختبارات.
abstract class PrintBackend {
  Future<bool> layout(PrintDoc doc);
  Future<bool> direct(Printer printer, PrintDoc doc);
  Future<List<Printer>> printers();
}

class _PluginBackend implements PrintBackend {
  const _PluginBackend();

  // ثابتٌ لا «ديناميكيّ» في الحالتين: المستند مبنيّ سلفاً بمقاسه، والمسار الديناميكيّ في المكتبة
  // (5.14) يوقف الخيط الرئيسيّ بانتظار دارت على الماك وآيفون — ومع فلاتر الحديثة (الخيطان واحد)
  // لا يعود الردّ أبداً فيتجمّد التطبيق.
  @override
  Future<bool> layout(PrintDoc doc) => Printing.layoutPdf(
        name: doc.name,
        format: doc.format,
        dynamicLayout: false,
        onLayout: (paper) => PrintOutput.bytesFor(doc, paper),
      );

  @override
  Future<bool> direct(Printer printer, PrintDoc doc) async => Printing.directPrintPdf(
        printer: printer,
        name: doc.name,
        format: doc.format,
        dynamicLayout: false,
        onLayout: (paper) => PrintOutput.bytesFor(doc, paper),
      );

  @override
  Future<List<Printer>> printers() => Printing.listPrinters();
}

/// الطريق الوحيد إلى الطابعة: الوصولات وسند التسوية ووصل البيع والتقارير.
class PrintOutput {
  PrintOutput._();

  @visibleForTesting
  static PrintBackend backend = const _PluginBackend();

  /// الطابعة المحفوظة لا تردّ ⇒ نافذة الطباعة بعد هذه المدّة (الوصل لا يضيع).
  static const directTimeout = Duration(seconds: 30);

  /// 🐛 المالك ٣٠ أكتوبر: «تطبيق الويندوز طباعه الوصل الابعاد مجاي تتصح مثل الويب». إضافة الطباعة على
  /// ويندوز (5.14) تطبع الصفحة بمقاسها الحقيقيّ من حافّة الورق، وتُرسل قبلها ورق الطابعة الفعليّ (عرضه
  /// وحواشيه غير المطبوعة) — فوصلٌ بعرض ٨٠ على طابعة ٥٨/٧٢ يُقصّ يمينه (التسميات)، وعلى A4 يصغر في زاويته.
  /// المتصفّح يرسم وصل الموقع على ورق الطابعة نفسه، فالتطبيق على ويندوز مثله: يعيد البناء على ذلك الورق.
  /// غيره كما كان: أندرويد وآيفون يصغّران المستند للورق بأنفسهما.
  @visibleForTesting
  static bool? debugFitToPrinter;

  static bool get fitToPrinter => debugFitToPrinter ?? AppPlatform.isWindows;

  /// بايتات [doc] لورقٍ أرسلته الطابعة [paper]: مُعادٌ بناؤه عليه إن أمكن، وإلّا كما بُني — لا يُسقط الطباعة أبداً.
  static Future<Uint8List> bytesFor(PrintDoc doc, PdfPageFormat paper) async {
    final refit = doc.refit;
    if (!fitToPrinter || refit == null || !usablePaper(paper)) return doc.bytes;
    try {
      return await refit(paper);
    } catch (e) {
      if (kDebugMode) debugPrint('[PrintOutput] refit failed: $e');
      return doc.bytes;
    }
  }

  /// ورقٌ معقول من النظام (٣٠–٦٠٠ ملم، وحواشٍ لا تأكل نصفه) — غيره يُطبع المستند كما بُني.
  @visibleForTesting
  static bool usablePaper(PdfPageFormat p) {
    final w = p.width;
    final side = p.marginLeft + p.marginRight;
    return w.isFinite &&
        w >= 30 * PdfPageFormat.mm &&
        w <= 600 * PdfPageFormat.mm &&
        p.marginLeft >= 0 &&
        p.marginRight >= 0 &&
        side < w / 2;
  }

  /// يرسل [doc] إلى «الطابعة المباشرة» المحفوظة (الحاسبة، [allowDirect]) بلا نافذة، وإلّا نافذة
  /// الطباعة. التقارير (A4 دائماً) تمرّر `allowDirect: false`: طابعة الكاشير ليست لها.
  static Future<PrintResult> send(PrintDoc doc, {bool allowDirect = true}) async {
    if (allowDirect) {
      final target = await directTarget();
      if (target != null) {
        try {
          final ok = await backend.direct(target, doc).timeout(directTimeout);
          if (ok) return PrintResult.printed(printer: target.name);
        } catch (e) {
          if (kDebugMode) debugPrint('[PrintOutput] direct failed: $e');
        }
      }
    }
    try {
      final ok = await backend.layout(doc);
      return ok ? const PrintResult.printed() : const PrintResult.cancelled();
    } catch (e) {
      if (kDebugMode) debugPrint('[PrintOutput] layout failed: $e');
      return PrintResult.failed('$e');
    }
  }

  /// طابعات النظام (للاختيار) — فارغةٌ على أيّ فشل.
  static Future<List<Printer>> printers() async {
    try {
      return await backend.printers().timeout(const Duration(seconds: 8));
    } catch (_) {
      return const [];
    }
  }

  /// الطابعة المحفوظة إن كانت موجودةً ومتاحةً الآن، وإلّا null ⇒ نافذة الطباعة.
  ///
  /// ⚠️ لا يُرسَل لطابعةٍ غير موجودة: إضافة الطباعة على ويندوز (5.14) لا تُكمل الطلب حينها
  /// أبداً (يُحذف بلا ردّ) — فيعلق الزرّ.
  static Future<Printer?> directTarget() async {
    if (!PrintPrefs.directSupported) return null;
    final saved = PrintPrefs.printer.value;
    if (saved == null) return null;
    try {
      final list = await backend.printers().timeout(const Duration(seconds: 8));
      for (final p in list) {
        if (p.url == saved.url) return p.isAvailable ? p : null;
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[PrintOutput] printers failed: $e');
    }
    return null;
  }
}
