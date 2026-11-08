import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../services/phone_output.dart';
import '../../../services/print_output.dart';
import '../../../theme/spacing.dart';

/// التقرير صورةً للهاتف (٨ نوفمبر — المالك: «الوصولات بالهاتف صوره تكون اختيار افضل من pdf»، مع صورة تقرير التفعيلات PDF
/// بسبعة أعمدة لا يُقرأ على الهاتف): صفحاتٌ بعرض الهاتف، كلّ صفٍّ بطاقة — عموده الأوّل عنوانها والبقيّة «التسمية · القيمة» —
/// بألوان التطبيق وخطّه. كلّ صفحةٍ صورة ([PhoneOutput.sharePdf]). صفوفٌ أكثر ممّا تحمله [PhoneOutput.maxImages] صورة ⇒
/// أوّلها وسطرٌ أخير يقول كم بقي وأين (Excel/PDF) — لا قصٌّ صامت.
class ReportImageDoc {
  ReportImageDoc._();

  /// صفحة الهاتف: ٤٠٠×٧٢٠ نقطة (٩:١٦ تقريباً) ⇒ صورةٌ بعرض ١٠٨٠ بكسل.
  static const PdfPageFormat page = PdfPageFormat(400, 720, marginAll: 18);

  /// أقصى صفوفٍ تُرسم — وتُنقص إن لم تسعها الصور.
  static const int maxRows = 60;

  /// نصٌّ أطول من هذا يُختصر (وصف حركةٍ طويل لا يكبّر البطاقة فوق الصفحة).
  static const int maxValueChars = 180;

  static const _bg = PdfColor.fromInt(0xFFF4F5F2);
  static const _border = PdfColor.fromInt(0xFFE7E9E5);
  static const _brand = PdfColor.fromInt(0xFF103D2E);
  static const _brandSoft = PdfColor.fromInt(0xFFE6EFEA);
  static const _textHi = PdfColor.fromInt(0xFF121614);
  static const _textMid = PdfColor.fromInt(0xFF69716A);
  static const _textLow = PdfColor.fromInt(0xFF909892);

  /// [titleColumn] عمود عنوان البطاقة؛ [tagColumn] عمودٌ يُعرض شارةً فوقه (الشركة في «كل الشركات»). [generatedAt] للاختبار.
  static Future<({Uint8List bytes, int pages, int shownRows})> build({
    required String title,
    String? subtitle,
    required List<String> columns,
    required List<List<String>> rows,
    int titleColumn = 0,
    int? tagColumn,
    DateTime? generatedAt,
  }) async {
    final theme = await PdfFonts.theme();
    var shown = rows.length < maxRows ? rows.length : maxRows;
    for (var attempt = 0; attempt < 4; attempt++) {
      final doc = _doc(theme, title, subtitle, columns, rows, shown, titleColumn, tagColumn, generatedAt ?? DateTime.now());
      final bytes = await doc.save();
      final pages = doc.document.pdfPageList.pages.length;
      if (pages <= PhoneOutput.maxImages || shown <= 1) return (bytes: bytes, pages: pages, shownRows: shown);
      // صفحاتٌ أكثر من الصور ⇒ صفوفٌ أقلّ بالنسبة، والسطر الأخير يقول الباقي
      shown = (shown * PhoneOutput.maxImages / pages).floor() - 1;
      if (shown < 1) shown = 1;
    }
    final doc = _doc(theme, title, subtitle, columns, rows, shown, titleColumn, tagColumn, generatedAt ?? DateTime.now());
    final bytes = await doc.save();
    return (bytes: bytes, pages: doc.document.pdfPageList.pages.length, shownRows: shown);
  }

  /// التشكيل (الشدّة والضمّة…) يُرسم في PDF فوق الحرف المجاور — يُحذف من الصورة (التسميات والقيم).
  static final _harakat = RegExp('[\u064B-\u0652\u0670]');

  static String _plain(String v) => v.replaceAll(_harakat, '');

  static String _clip(String v) {
    final s = _plain(v).replaceAll('\n', ' ').trim();
    return s.length <= maxValueChars ? s : '${s.substring(0, maxValueChars)}…';
  }

  static String _two(int n) => n.toString().padLeft(2, '0');

  static pw.Document _doc(
    pw.ThemeData theme,
    String title,
    String? subtitle,
    List<String> columns,
    List<List<String>> rows,
    int shown,
    int titleColumn,
    int? tagColumn,
    DateTime now,
  ) {
    final doc = pw.Document(title: title, creator: 'MyServices Pro');
    final rest = rows.length - shown;
    final stamp = '${now.year}-${_two(now.month)}-${_two(now.day)} ${_two(now.hour)}:${_two(now.minute)}';
    doc.addPage(
      pw.MultiPage(
        maxPages: 40,
        pageTheme: pw.PageTheme(
          pageFormat: page,
          textDirection: pw.TextDirection.rtl,
          theme: theme,
          buildBackground: (ctx) => pw.FullPage(ignoreMargins: true, child: pw.Container(color: _bg)),
        ),
        header: (ctx) => pw.Container(
          margin: const pw.EdgeInsets.only(bottom: 10),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Expanded(
                child: pw.Text(_plain(title),
                    maxLines: 1, style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold, color: _textHi)),
              ),
              if (ctx.pagesCount > 1)
                pw.Text('${ctx.pageNumber}/${ctx.pagesCount}', style: const pw.TextStyle(fontSize: 9.5, color: _textLow)),
            ],
          ),
        ),
        build: (ctx) => [
          // الفترة وعدد الصفوف ووقت التصدير — مرّةً أعلى الأولى
          pw.Container(
            margin: const pw.EdgeInsets.only(bottom: 10),
            padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: pw.BoxDecoration(color: _brandSoft, borderRadius: pw.BorderRadius.circular(R.sm)),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                if (subtitle != null && subtitle.trim().isNotEmpty)
                  pw.Text(_plain(subtitle.trim()), style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: _brand)),
                pw.SizedBox(height: 2),
                pw.Text('عدد الصفوف: ${rows.length} · وقت التصدير $stamp', style: const pw.TextStyle(fontSize: 9.5, color: _textMid)),
              ],
            ),
          ),
          for (var i = 0; i < shown; i++) _card(columns, rows[i], titleColumn, tagColumn),
          if (rest > 0)
            pw.Container(
              margin: const pw.EdgeInsets.only(top: 2),
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(
                color: PdfColors.white,
                borderRadius: pw.BorderRadius.circular(R.sm),
                border: pw.Border.all(color: _border, width: 0.8),
              ),
              child: pw.Text('بقيّة الصفوف ($rest) في «Excel» أو «PDF» — الصورة لأوّل $shown',
                  style: pw.TextStyle(fontSize: 10.5, fontWeight: pw.FontWeight.bold, color: _textMid)),
            ),
        ],
      ),
    );
    return doc;
  }

  static pw.Widget _card(List<String> columns, List<String> row, int titleColumn, int? tagColumn) {
    String at(int i) => i >= 0 && i < row.length ? row[i].trim() : '';
    final head = at(titleColumn);
    final tag = tagColumn == null ? '' : at(tagColumn);
    final fields = <(String, String)>[
      for (var i = 0; i < columns.length; i++)
        if (i != titleColumn && i != tagColumn && at(i).isNotEmpty) (_plain(columns[i]), _clip(at(i))),
    ];
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 8),
      padding: const pw.EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: pw.BoxDecoration(
        color: PdfColors.white,
        borderRadius: pw.BorderRadius.circular(R.sm),
        border: pw.Border.all(color: _border, width: 0.8),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          if (tag.isNotEmpty) ...[
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: pw.BoxDecoration(color: _brandSoft, borderRadius: pw.BorderRadius.circular(R.check)),
              child: pw.Text(_plain(tag), style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold, color: _brand)),
            ),
            pw.SizedBox(height: 4),
          ],
          if (head.isNotEmpty)
            pw.Text(_clip(head), style: pw.TextStyle(fontSize: 12.5, fontWeight: pw.FontWeight.bold, color: _brand)),
          if (fields.isNotEmpty) pw.SizedBox(height: 5),
          for (final f in fields)
            pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 3),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.SizedBox(
                    width: 92,
                    child: pw.Text(f.$1, style: const pw.TextStyle(fontSize: 9.5, color: _textMid)),
                  ),
                  pw.Expanded(child: pw.Text(f.$2, style: const pw.TextStyle(fontSize: 10.5, color: _textHi))),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
