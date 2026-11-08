import 'dart:io';

import 'package:csv/csv.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
// ignore: implementation_imports
import 'package:pdf/src/pdf/font/bidi_utils.dart' as pdf_bidi;
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../../../core/util/format.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../core/widgets/print_feedback.dart';
import '../../../services/print_output.dart';

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
  });

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

  Future<void> _exportCsv(BuildContext context) async {
    // CSV مع BOM لإجبار Excel يفتحه Unicode/UTF-8 (يعرض العربية صح).
    final data = <List<String>>[columns, ...rows];
    final csvString = const ListToCsvConverter().convert(data);
    final withBom = '﻿$csvString';

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

  Future<void> _printPdf(BuildContext context) async {
    try {
      final doc = await ReportPdf.build(
        title: title,
        subtitle: subtitle,
        columns: columns,
        rows: rows,
        columnWeights: columnWeights,
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
}

/// PDF التقرير — مستقلٌّ عن الزرّ ليُختبر.
///
/// 🐛 ٨ نوفمبر (المالك مع صورة «التقرير المالي»: «هذا ال pdf بي مشكله بالتنسيق الحروف والكتابات»): الجدول كان داخل
/// اتّجاهٍ LTR (لترتيب الأعمدة كـExcel — مطلب 2026-07-12) فورثت الخلايا LTR، ومكتبة pdf لا تشكّل العربيّ ولا ترتّبه إلّا في
/// RTL ⇒ حروفٌ منفصلة معكوسة. الآن: ترتيب الأعمدة كما كان، وكلّ خليّةٍ باتّجاه نصّها (العربيّ RTL، والتاريخ واليوزر والأرقام
/// LTR كي لا يتبادل «2026-11-05 22:47» موضعيه)؛ «45000.0» ⇒ «45,000» بأعمدة المال؛ وA4 أفقيّ حين تكثر الأعمدة فلا يُقطع
/// «admin@poox» ولا «تسديد دين» حرفاً حرفاً.
class ReportPdf {
  ReportPdf._();

  static final _arabic = RegExp(r'[\u0600-\u06FF\u0750-\u077F\u08A0-\u08FF\uFB50-\uFDFF\uFE70-\uFEFF]');
  static final _wholeDecimal = RegExp(r'^-?\d+\.0+$');
  static final _int = RegExp(r'^-?\d+$');

  /// كلماتٌ في رأس العمود تجعله عمود مال (فواصل الآلاف).
  static const _moneyWords = ['مبلغ', 'كلفة', 'سعر', 'رصيد', 'دين', 'ديون', 'مدفوع', 'ربح', 'مجموع', 'إجمالي', 'صافي', 'مصروف', 'محصّل', 'المحصل', 'تحصيل'];

  /// الأعمدة من هذا العدد فصاعداً ⇒ A4 أفقيّ.
  static const wideFrom = 6;

  static bool isArabic(String s) => _arabic.hasMatch(s);

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

  /// النصّ مشكَّلاً بترتيبه المرئيّ من اليسار — يُرسم LTR كما هو. مخبّأ: «تسديد دين» يتكرّر آلاف المرّات في التقرير الواحد.
  static String visual(String logical) {
    final hit = _visual[logical];
    if (hit != null) return hit;
    if (_visual.length > 20000) _visual.clear();
    return _visual[logical] = pdf_bidi.logicalToVisual(logical).split(' ').reversed.join(' ');
  }

  static final _visual = <String, String>{};

  /// نصّ الخليّة: العربيّ عبر [rtl]، وما سواه نصٌّ LTR عاديّ.
  static pw.Widget text(String s, pw.TextStyle style, {pw.TextAlign align = pw.TextAlign.right}) =>
      isArabic(s) ? rtl(s, style, align: align) : pw.Text(s, style: style, textAlign: align, textDirection: pw.TextDirection.ltr);

  /// نصٌّ عربيّ بلا عيب المسافات في مكتبة pdf: اتّجاه RTL فيها يعكس موضع كلّ كلمةٍ بعرض حبرها لا بعرض تقدّمها، فتضيع
  /// المسافة بعد «ر» و«د» وتتضاعف بعد «:» («عددالصفوف»، «غيرنقدي»، «موظف:  كرار»). هنا: الأسطر تُقسَّم بالكلمات المنطقيّة
  /// على عرض الخليّة، وكلّ سطرٍ يُشكَّل ويُرتَّب مرّةً ([visual]) ثمّ يُرسم LTR — المسافة مسافةٌ حقيقيّة.
  static pw.Widget rtl(String s, pw.TextStyle style, {pw.TextAlign align = pw.TextAlign.right}) {
    final words = s.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    return pw.LayoutBuilder(builder: (ctx, c) {
      final font = style.font!.getFont(ctx);
      final size = style.fontSize!;
      double width(String v) => v.isEmpty ? 0 : font.stringMetrics(v).advanceWidth * size;
      final maxW = c == null || !c.maxWidth.isFinite ? double.infinity : c.maxWidth - 0.5;
      final lines = <String>[];
      final whole = visual(words.join(' '));
      if (width(whole) <= maxW) {
        lines.add(whole);
      } else {
        final space = width(' ');
        var cur = <String>[];
        var curW = 0.0;
        for (final w in words) {
          final ww = width(visual(w));
          if (cur.isNotEmpty && curW + space + ww > maxW) {
            lines.add(visual(cur.join(' ')));
            cur = [w];
            curW = ww;
          } else {
            curW += (cur.isEmpty ? 0 : space) + ww;
            cur.add(w);
          }
        }
        if (cur.isNotEmpty) lines.add(visual(cur.join(' ')));
      }
      return pw.Column(
        mainAxisSize: pw.MainAxisSize.min,
        crossAxisAlignment: align == pw.TextAlign.center
            ? pw.CrossAxisAlignment.center
            : (align == pw.TextAlign.left ? pw.CrossAxisAlignment.start : pw.CrossAxisAlignment.end),
        children: [
          for (final l in lines) pw.Text(l, style: style, textAlign: align, textDirection: pw.TextDirection.ltr),
        ],
      );
    });
  }

  static String _now() {
    final n = DateTime.now();
    String p(int v) => v.toString().padLeft(2, '0');
    return '${n.year}-${p(n.month)}-${p(n.day)} ${p(n.hour)}:${p(n.minute)}';
  }

  static Future<pw.Document> build({
    required String title,
    String? subtitle,
    required List<String> columns,
    required List<List<String>> rows,
    List<double>? columnWeights,
  }) async {
    // خطّ التطبيق المضمَّن — كان Cairo من خطوط Google عند كلّ طباعة: حاسبةٌ بلا إنترنت لحظتها لا تطبع التقرير أصلاً.
    final theme = await PdfFonts.theme();
    final font = theme.defaultTextStyle.font!;
    final fontBold = theme.defaultTextStyle.fontBold!;
    final money = [for (final c in columns) moneyColumn(c)];
    final dense = columns.length >= 8;
    final cellStyle = pw.TextStyle(font: font, fontSize: dense ? 9 : 10, lineSpacing: 1.5);
    final headerStyle = pw.TextStyle(font: fontBold, fontSize: dense ? 9.5 : 10.5, color: PdfColors.white);
    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageFormat: formatFor(columns.length),
        // الافتراضيّ ٢٠ صفحة ⇒ تقريرٌ بأكثر من ~٤٠٠ صفّ كان «فشل الطباعة» (TooManyPagesException) — التصدير حتى ٥٠٠٠ صفّ
        maxPages: 600,
        textDirection: pw.TextDirection.rtl,
        theme: pw.ThemeData.withFont(base: font, bold: fontBold),
        margin: const pw.EdgeInsets.all(24),
        build: (ctx) => [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              text(title, pw.TextStyle(fontSize: 17, font: fontBold)),
              pw.Text(_now(),
                  textDirection: pw.TextDirection.ltr,
                  style: const pw.TextStyle(fontSize: 10.5, color: PdfColors.grey700)),
            ],
          ),
          if (subtitle != null && subtitle.isNotEmpty) ...[
            pw.SizedBox(height: 4),
            pw.Align(
              alignment: pw.Alignment.centerRight,
              child: text(subtitle, pw.TextStyle(font: font, fontSize: 11, color: PdfColors.grey700)),
            ),
          ],
          pw.SizedBox(height: 12),
          // ترتيب الأعمدة كـExcel (مطلب 2026-07-12): العمود[0] على أقصى اليسار — والنصّ داخل كلّ خليّةٍ باتّجاهه هو.
          pw.Directionality(
            textDirection: pw.TextDirection.ltr,
            child: pw.TableHelper.fromTextArray(
              headers: [
                for (final c in columns) text(c, headerStyle, align: pw.TextAlign.center),
              ],
              data: rows,
              cellBuilder: (i, data, rowNum) {
                final v = cellText('${data ?? ''}', money: i < money.length && money[i]);
                return text(v, cellStyle);
              },
              headerDecoration: const pw.BoxDecoration(color: PdfColors.teal600),
              oddRowDecoration: const pw.BoxDecoration(color: PdfColors.grey100),
              cellAlignment: pw.Alignment.centerRight,
              headerAlignment: pw.Alignment.center,
              cellPadding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 4),
              headerPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 5),
              border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.4),
              columnWidths: {
                for (int i = 0; i < columns.length; i++)
                  i: pw.FlexColumnWidth(
                    columnWeights != null && i < columnWeights.length ? columnWeights[i] : 1.0,
                  ),
              },
            ),
          ),
          pw.SizedBox(height: 6),
          pw.Align(
            alignment: pw.Alignment.centerLeft,
            child: text('عدد الصفوف: ${rows.length}', pw.TextStyle(fontSize: 9.5, color: PdfColors.grey700, font: font)),
          ),
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
