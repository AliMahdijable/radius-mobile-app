import 'dart:io';

import 'package:csv/csv.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../../../core/util/format.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../core/widgets/print_feedback.dart';
import '../../../services/pdf_kit.dart';
import '../../../services/print_output.dart';

export '../../../services/pdf_kit.dart' show PdfStat, PdfTone;

/// ================================================================
/// Report export — CSV/Excel + PDF/Print للتقارير.
///
/// النمط: كل شاشة تقرير تُعطي:
///   * عنوان (للـPDF)
///   * تسميات الأعمدة (List<String>)
///   * صفوف كـ List<List<String>> (كل صف قيم بنفس ترتيب الأعمدة)
///
/// الأزرار تولّد الملف مؤقتاً وتفتح shareSheet — Excel يفتح CSV مباشرة.
/// الطباعة تفتح نافذة الطباعة عبر [PrintOutput] (A4، بلا الطابعة المباشرة).
///
/// نُبقي حد أعلى معقول (5000 صف) — الصفحة تعرض ضمن pagination لكن
/// التصدير يشمل الـfiltered set كامل.
/// ================================================================

class ReportExportBar extends StatefulWidget {
  const ReportExportBar({
    super.key,
    required this.title,
    required this.columns,
    required this.rows,
    this.fileNameBase = 'report',
    this.subtitle,
    this.columnWeights,
    this.details = const [],
  });

  /// سطور الفلاتر المختارة تحت العنوان (٢٢ نوفمبر — المالك: «من يختار فلاتر … ويطبع أو ينقر إكسل أو PDF يطلع على حسب الفلاتر»):
  /// الملفّ يقول ما فيه وما نقص منه.
  final List<String> details;

  /// يُستعمل في رأس PDF + اسم الملف.
  final String title;
  final String? subtitle;
  final List<String> columns;
  final List<List<String>> rows;

  /// اسم الملف (بدون امتداد + بدون timestamp — نضيفه تلقائياً).
  final String fileNameBase;

  /// أوزان عرض أعمدة PDF (اختياري). طوله يساوي عدد الأعمدة، ومجموعه غير
  /// ملزَم يتساوى مع أي رقم — الأوزان نسبية. لو null، كل الأعمدة تأخذ
  /// نفس العرض (flex=1). المطلب 2026-07-12: اسم/يوزر/وصف أوسع، نوع/منفّذ أضيق.
  final List<double>? columnWeights;

  @override
  State<ReportExportBar> createState() => _ReportExportBarState();
}

class _ReportExportBarState extends State<ReportExportBar> {
  String get title => widget.title;
  String? get subtitle => widget.subtitle;
  List<String> get columns => widget.columns;
  List<List<String>> get rows => widget.rows;
  String get fileNameBase => widget.fileNameBase;
  List<double>? get columnWeights => widget.columnWeights;
  List<String> get details => widget.details;

  bool get _hasData => rows.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _IconBtn(
          icon: LucideIcons.fileSpreadsheet,
          tooltip: 'تصدير Excel',
          color: const Color(0xFF14B8A6),
          enabled: _hasData,
          onTap: () => _exportCsv(context),
        ),
        const SizedBox(width: 6),
        _IconBtn(
          icon: LucideIcons.printer,
          tooltip: 'طباعة PDF',
          color: const Color(0xFF3B82F6),
          enabled: _hasData,
          onTap: () => _printPdf(context),
        ),
      ],
    );
  }

  Future<void> _exportCsv(BuildContext context) => ReportExportActions.csv(
        context,
        title: title,
        subtitle: subtitle,
        details: details,
        columns: columns,
        rows: rows,
        fileNameBase: fileNameBase,
      );

  Future<void> _printPdf(BuildContext context) => ReportExportActions.pdf(
        context,
        title: title,
        subtitle: subtitle,
        details: details,
        columns: columns,
        rows: rows,
        columnWeights: columnWeights,
        fileNameBase: fileNameBase,
      );
}

/// أفعال التصدير نفسها لكلّ زرّ — شريط [ReportExportBar] وأزرار التقرير الموحّد (PDF · Excel · واتساب).
/// ما يُصدَّر بالضبط — يلتقطه [ReportExportActions.debugSink] في الاختبار.
@immutable
class ReportExportRequest {
  const ReportExportRequest({
    required this.how,
    required this.title,
    this.subtitle,
    this.details = const [],
    required this.columns,
    required this.rows,
    this.columnWeights,
    this.summary = const [],
  });

  /// `csv` · `pdf` (طباعة) · `share` (الملفّ PDF للمشاركة).
  final String how;
  final String title;
  final String? subtitle;

  /// سطور الفلاتر تحت العنوان («المدير: علي»، «بحث: …»، «ناقص: …»).
  final List<String> details;
  final List<String> columns;
  final List<List<String>> rows;
  final List<double>? columnWeights;

  /// بطاقات ملخّص الشاشة في رأس الـPDF — أرقامها كما على الشاشة (فارغةٌ حين لا تصف الصفوف نفسها: بحثٌ أو حركات بطاقة).
  final List<PdfStat> summary;
}

class ReportExportActions {
  ReportExportActions._();

  /// الاختبار: يُلتقط الطلب بدل المشاركة/الطباعة (لا منصّة في flutter test).
  @visibleForTesting
  static Future<void> Function(ReportExportRequest r)? debugSink;

  /// سطور الرأس في ملفّ Excel: كلّ سطرٍ خليّةٌ وحده، ثمّ سطرٌ فارغ قبل الجدول — الملفّ يقول فلاتره.
  static List<List<String>> csvTable({
    required String title,
    String? subtitle,
    List<String> details = const [],
    required List<String> columns,
    required List<List<String>> rows,
  }) =>
      [
        if (details.isNotEmpty) ...[
          [title],
          if (subtitle != null && subtitle.isNotEmpty) [subtitle],
          for (final d in details) [d],
          const <String>[],
        ],
        columns,
        ...rows,
      ];

  static Future<void> csv(
    BuildContext context, {
    required String title,
    String? subtitle,
    List<String> details = const [],
    required List<String> columns,
    required List<List<String>> rows,
    String fileNameBase = 'report',
  }) async {
    final sink = debugSink;
    if (sink != null) {
      return sink(ReportExportRequest(how: 'csv', title: title, subtitle: subtitle, details: details, columns: columns, rows: rows));
    }
    // CSV مع BOM لإجبار Excel يفتحه Unicode/UTF-8 (يعرض العربية صح).
    final data = csvTable(title: title, subtitle: subtitle, details: details, columns: columns, rows: rows);
    final csvString = const ListToCsvConverter().convert(data);
    final withBom = '\uFEFF$csvString';

    try {
      final dir = await getTemporaryDirectory();
      final ts = DateTime.now().millisecondsSinceEpoch;
      final file = File('${dir.path}/${fileNameBase}_$ts.csv');
      await file.writeAsString(withBom);
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'text/csv')],
        subject: title,
        text: subtitle ?? title,
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل تصدير CSV: $e')),
        );
      }
    }
  }

  static Future<void> pdf(
    BuildContext context, {
    required String title,
    String? subtitle,
    List<String> details = const [],
    required List<String> columns,
    required List<List<String>> rows,
    List<double>? columnWeights,
    String fileNameBase = 'report',
    List<PdfStat> summary = const [],
  }) async {
    final sink = debugSink;
    if (sink != null) {
      return sink(ReportExportRequest(
          how: 'pdf', title: title, subtitle: subtitle, details: details, columns: columns, rows: rows, columnWeights: columnWeights,
          summary: summary));
    }
    try {
      final doc = await ReportPdf.build(
        title: title,
        subtitle: subtitle,
        details: details,
        columns: columns,
        rows: rows,
        columnWeights: columnWeights,
        summary: summary,
      );
      // A4 دائماً (أفقيّاً حين تكثر الأعمدة)، فلا يذهب لطابعة الكاشير المباشرة.
      final r = await PrintOutput.send(
        await PrintDoc.of(doc, name: '$fileNameBase.pdf', requested: ReportPdf.formatFor(columns.length)),
        allowDirect: false,
      );
      if (context.mounted) showPrintResult(context, r);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل الطباعة: $e')),
        );
      }
    }
  }

  /// الملفّ نفسه (PDF) إلى ورقة المشاركة — واتساب أو غيره، بلا طباعة.
  static Future<void> sharePdf(
    BuildContext context, {
    required String title,
    String? subtitle,
    List<String> details = const [],
    required List<String> columns,
    required List<List<String>> rows,
    List<double>? columnWeights,
    String fileNameBase = 'report',
    List<PdfStat> summary = const [],
  }) async {
    final sink = debugSink;
    if (sink != null) {
      return sink(ReportExportRequest(
          how: 'share', title: title, subtitle: subtitle, details: details, columns: columns, rows: rows, columnWeights: columnWeights,
          summary: summary));
    }
    try {
      final doc = await ReportPdf.build(
        title: title,
        subtitle: subtitle,
        details: details,
        columns: columns,
        rows: rows,
        columnWeights: columnWeights,
        summary: summary,
      );
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/${fileNameBase}_${DateTime.now().millisecondsSinceEpoch}.pdf');
      await file.writeAsBytes(await doc.save());
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'application/pdf')],
        subject: title,
        text: subtitle ?? title,
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل إرسال الملفّ: $e')),
        );
      }
    }
  }
}

/// PDF التقرير — مستقلٌّ عن الزرّ ليُختبر.
///
/// 🐛 ٨ نوفمبر (المالك مع صورة «التقرير المالي»: «هذا ال pdf بي مشكله بالتنسيق الحروف والكتابات»): الجدول كان داخل
/// اتّجاهٍ LTR (لترتيب الأعمدة كـExcel — مطلب 2026-07-12) فورثت الخلايا LTR، ومكتبة pdf لا تشكّل العربيّ ولا ترتّبه إلّا في
/// RTL ⇒ حروفٌ منفصلة معكوسة. الآن: ترتيب الأعمدة كما كان، وكلّ خليّةٍ باتّجاه نصّها (العربيّ RTL، والتاريخ واليوزر والأرقام
/// LTR كي لا يتبادل «2026-11-05 22:47» موضعيه)؛ «45000.0» ⇒ «45,000» بأعمدة المال؛ وA4 أفقيّ حين تكثر الأعمدة فلا يُقطع
/// «admin@x» ولا «تسديد دين» حرفاً حرفاً.
///
/// ٢٦ نوفمبر (المالك: «تصميم كلش مخزي … حسّن التصميم اكثر ومعلومات اوضح»): التصميم من [PdfKit] — شريط العنوان والفترة،
/// الفلاتر رقائق، ملخّص الشاشة بطاقاتٍ ([summary] — أرقام الشاشة نفسها، لا يُجمع هنا عمود: «المبلغ» في الماليّ يخلط الدين
/// بتسديده)، رأس الجدول بلون الهويّة يتكرّر بكلّ صفحة، أسطرٌ متناوبة، السالب أحمر، وتذييلٌ «صفحة X من Y» ووقت الطباعة.
class ReportPdf {
  ReportPdf._();

  static final _wholeDecimal = RegExp(r'^-?\d+\.0+$');
  static final _int = RegExp(r'^-?\d+$');

  /// كلماتٌ في رأس العمود تجعله عمود مال (فواصل الآلاف).
  static const _moneyWords = ['مبلغ', 'كلفة', 'سعر', 'رصيد', 'دين', 'ديون', 'مدفوع', 'ربح', 'مجموع', 'إجمالي', 'صافي', 'مصروف', 'محصّل', 'المحصل', 'تحصيل', 'دائن'];

  /// الأعمدة من هذا العدد فصاعداً ⇒ A4 أفقيّ.
  static const wideFrom = 6;

  static bool isArabic(String s) => PdfKit.isArabic(s);

  static bool moneyColumn(String header) => _moneyWords.any(header.contains);

  static PdfPageFormat formatFor(int columns) => columns >= wideFrom ? PdfPageFormat.a4.landscape : PdfPageFormat.a4;

  /// قيمة الخليّة كما تُطبع: «45000.0» ⇒ «45000»، وبعمود المال «45,000».
  static String cellText(String v, {bool money = false}) {
    var s = v.trim();
    if (_wholeDecimal.hasMatch(s)) s = s.substring(0, s.indexOf('.'));
    if (money && _int.hasMatch(s)) {
      final n = int.tryParse(s);
      if (n != null) s = '${n < 0 ? '-' : ''}${formatIQD(n)}';
    }
    return s;
  }

  /// اتّجاه نصّ الخليّة: العربيّ RTL (يُشكَّل ويُرتَّب)، وما سواه LTR.
  static pw.TextDirection directionOf(String s) => isArabic(s) ? pw.TextDirection.rtl : pw.TextDirection.ltr;

  /// النصّ مشكَّلاً بترتيبه المرئيّ — انظر [PdfKit.visual].
  static String visual(String logical) => PdfKit.visual(logical);

  /// نصّ الخليّة: العربيّ عبر [rtl]، وما سواه نصٌّ LTR عاديّ.
  static pw.Widget text(String s, pw.TextStyle style, {pw.TextAlign align = pw.TextAlign.right}) => PdfKit.text(s, style, align: align);

  /// نصٌّ عربيّ بلا عيب المسافات في مكتبة pdf — انظر [PdfKit.rtl].
  static pw.Widget rtl(String s, pw.TextStyle style, {pw.TextAlign align = pw.TextAlign.right}) => PdfKit.rtl(s, style, align: align);

  static Future<pw.Document> build({
    required String title,
    String? subtitle,
    List<String> details = const [],
    required List<String> columns,
    required List<List<String>> rows,
    List<double>? columnWeights,
    List<PdfStat> summary = const [],
    DateTime? printedAt,
  }) async {
    // خطّ التطبيق المضمَّن — كان Cairo من خطوط Google عند كلّ طباعة: حاسبةٌ بلا إنترنت لحظتها لا تطبع التقرير أصلاً.
    final theme = await PdfFonts.theme();
    final at = printedAt ?? DateTime.now();
    final format = formatFor(columns.length);
    final wide = format.width > format.height;
    final money = [for (final c in columns) moneyColumn(c)];
    final dense = columns.length >= 8;
    final size = dense ? 8.6 : 9.6;
    final cellStyle = PdfKit.st(size: size, lineSpacing: 1.4);
    final negStyle = PdfKit.st(size: size, color: PdfKit.red, lineSpacing: 1.4);
    final headerStyle = PdfKit.st(size: dense ? 8.8 : 9.8, color: PdfColors.white, bold: true);
    const side = pw.BorderSide(color: PdfKit.rule, width: 0.6);
    const inner = pw.BorderSide(color: PdfKit.rule, width: 0.45);

    pw.Widget cell(List<String> row, int i) {
      final v = cellText(i < row.length ? row[i] : '', money: money[i]);
      final neg = money[i] && (v.startsWith('-') || v.startsWith('−'));
      return pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 4),
        alignment: pw.Alignment.centerRight,
        child: v.isEmpty ? pw.SizedBox() : PdfKit.text(v, neg ? negStyle : cellStyle),
      );
    }

    final doc = pw.Document(theme: theme);
    doc.addPage(
      pw.MultiPage(
        pageFormat: format,
        // الافتراضيّ ٢٠ صفحة ⇒ تقريرٌ بأكثر من ~٤٠٠ صفّ كان «فشل الطباعة» (TooManyPagesException) — التصدير حتى ٥٠٠٠ صفّ
        maxPages: 600,
        textDirection: pw.TextDirection.rtl,
        theme: theme,
        margin: const pw.EdgeInsets.fromLTRB(22, 20, 22, 14),
        header: (ctx) => ctx.pageNumber == 1 ? pw.SizedBox() : PdfKit.runningHeader(title, subtitle: subtitle),
        footer: (ctx) => PdfKit.footer(ctx, printedAt: at),
        build: (ctx) => [
          PdfKit.band(title: title, subtitle: subtitle, side: [PdfKit.stamp(at), 'وقت الطباعة']),
          // الفلاتر المختارة — الملفّ المطبوع يقول ما فيه وما نقص منه
          if (details.any((d) => d.trim().isNotEmpty)) ...[
            pw.SizedBox(height: 9),
            PdfKit.chips(details),
          ],
          if (summary.isNotEmpty) ...[
            pw.SizedBox(height: 10),
            PdfKit.statGrid(summary, perRow: summary.length < (wide ? 5 : 4) ? summary.length : (wide ? 5 : 4)),
          ],
          pw.SizedBox(height: 12),
          if (rows.isEmpty)
            pw.Container(
              padding: const pw.EdgeInsets.all(16),
              decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfKit.rule, width: 0.6)),
              child: pw.Center(child: PdfKit.rtl('لا بيانات بهذه الفلاتر', PdfKit.st(size: 11, color: PdfKit.muted))),
            )
          else
            // ترتيب الأعمدة كـExcel (مطلب 2026-07-12): العمود[0] على أقصى اليسار — والنصّ داخل كلّ خليّةٍ باتّجاهه هو.
            pw.Directionality(
              textDirection: pw.TextDirection.ltr,
              child: pw.Table(
                border: const pw.TableBorder(
                  left: side,
                  right: side,
                  top: side,
                  bottom: side,
                  horizontalInside: inner,
                  verticalInside: inner,
                ),
                defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
                columnWidths: {
                  for (int i = 0; i < columns.length; i++)
                    i: pw.FlexColumnWidth(columnWeights != null && i < columnWeights.length ? columnWeights[i] : 1.0),
                },
                children: [
                  // رأس الجدول يتكرّر أعلى كلّ صفحة
                  pw.TableRow(
                    repeat: true,
                    decoration: const pw.BoxDecoration(color: PdfKit.brand),
                    children: [
                      for (final c in columns)
                        pw.Container(
                          padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                          alignment: pw.Alignment.center,
                          child: PdfKit.text(c, headerStyle, align: pw.TextAlign.center),
                        ),
                    ],
                  ),
                  for (var r = 0; r < rows.length; r++)
                    pw.TableRow(
                      decoration: r.isOdd ? const pw.BoxDecoration(color: PdfKit.tintLight) : null,
                      children: [for (var i = 0; i < columns.length; i++) cell(rows[r], i)],
                    ),
                ],
              ),
            ),
          pw.SizedBox(height: 6),
          pw.Row(children: [
            PdfKit.rtl('عدد الصفوف: ${rows.length}', PdfKit.st(size: 9, color: PdfKit.muted)),
            pw.Spacer(),
          ]),
        ],
      ),
    );
    return doc;
  }
}

class _IconBtn extends StatelessWidget {
  const _IconBtn({
    required this.icon,
    required this.tooltip,
    required this.color,
    required this.enabled,
    required this.onTap,
  });
  final IconData icon;
  final String tooltip;
  final Color color;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final active = enabled;
    return Tooltip(
      message: tooltip,
      child: InkResponse(
        onTap: active ? onTap : null,
        radius: 22,
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: active ? color.withValues(alpha: 0.10) : AppColors.surface,
            borderRadius: BorderRadius.circular(R.sm),
            border: Border.all(
              color: active ? color.withValues(alpha: 0.30) : AppColors.border,
            ),
          ),
          alignment: Alignment.center,
          child: Icon(icon, size: 17, color: active ? color : AppColors.textLow),
        ),
      ),
    );
  }
}
