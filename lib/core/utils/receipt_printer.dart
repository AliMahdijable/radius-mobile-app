import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart' as intl;
import '../../models/print_template_model.dart';
import 'helpers.dart';

class ReceiptData {
  final String subscriberName;
  final String phoneNumber;
  final String packageName;
  final double packagePrice;
  final double paidAmount;
  final double remainingAmount;
  final double debtAmount;
  final String expiryDate;
  final String operationType; // 'activation', 'debt_payment', 'debt_add'

  const ReceiptData({
    required this.subscriberName,
    this.phoneNumber = '',
    this.packageName = '',
    this.packagePrice = 0,
    this.paidAmount = 0,
    this.remainingAmount = 0,
    this.debtAmount = 0,
    this.expiryDate = '',
    this.operationType = 'activation',
  });
}

class ReceiptPrinter {
  static pw.Font? _cairoFont;

  static Future<void> _loadFonts() async {
    if (_cairoFont != null) return;
    final fontData = await rootBundle.load('assets/fonts/Cairo-Variable.ttf');
    _cairoFont = pw.Font.ttf(fontData);
  }

  /// رقم الوصل المنسّق "No. 00000" — لو [no] null يستخدم INV-{timestamp}
  /// كـfallback مؤقت (يحدث فقط لما تفشل الأرشفة).
  static String _formatReceiptNo(int? no) {
    if (no == null || no < 0) {
      return 'INV-${DateTime.now().millisecondsSinceEpoch}';
    }
    return 'No. ${no.toString().padLeft(5, '0')}';
  }

  /// Public façade for [_fillTemplate] — used by the live-preview widget
  /// to render the exact same string the production printer renders.
  /// Keeps the live preview 1:1 with what comes out of the printer.
  static String testFillTemplate(
    String template,
    ReceiptData data, {
    int? receiptNo,
  }) =>
      _fillTemplate(template, data, receiptNo: receiptNo);

  static String _fillTemplate(String template, ReceiptData data, {int? receiptNo}) {
    final receiptLabel = _formatReceiptNo(receiptNo);
    final date = intl.DateFormat('yyyy/MM/dd HH:mm', 'ar').format(DateTime.now());

    return template
        // كلا الـplaceholders يأخذان نفس القيمة الموحّدة. الـlegacy
        // {invoice_number} يبقى مدعوماً للقوالب القديمة، والـ{receipt_no}
        // الجديد للقوالب الحديثة المنشأة من v2 أو الموبايل.
        .replaceAll('{receipt_no}', receiptLabel)
        .replaceAll('{invoice_number}', receiptLabel)
        .replaceAll('{date}', date)
        .replaceAll('{subscriber_name}', data.subscriberName)
        .replaceAll('{phone_number}', data.phoneNumber.isNotEmpty ? data.phoneNumber : '-')
        .replaceAll('{package_name}', data.packageName.isNotEmpty ? data.packageName : '-')
        .replaceAll('{package_price}', AppHelpers.formatMoney(data.packagePrice))
        .replaceAll('{paid_amount}', AppHelpers.formatMoney(data.paidAmount))
        .replaceAll('{remaining_amount}', AppHelpers.formatMoney(data.remainingAmount))
        .replaceAll(
          '{expiry_date}',
          data.expiryDate.isNotEmpty
              ? AppHelpers.formatExpiration(data.expiryDate)
              : '-',
        )
        .replaceAll('{debt_amount}', AppHelpers.formatMoney(data.debtAmount));
  }

  /// Print using a stored HTML template.
  ///
  /// [receiptNo] رقم الوصل من الـbackend (per-admin counter). null → fallback.
  /// [design] إعدادات التصميم (margins, fonts, colors) المُخزَّنة في
  ///   template_data. تُطبَّق كـCSS على wrapper الـbody قبل تمرير القالب.
  static Future<void> printWithTemplate({
    required String htmlTemplate,
    required ReceiptData data,
    int? receiptNo,
    ReceiptDesign? design,
  }) async {
    final filledHtml = _fillTemplate(htmlTemplate, data, receiptNo: receiptNo);
    final d = design ?? ReceiptDesign();

    // تحويل قيم mm إلى padding CSS. الـconvertHtml يستعمل DPI افتراضي،
    // فالـmm تطابق صحياً عند العرض.
    final pad = '${d.marginTopMm}mm ${d.marginRightMm}mm '
        '${d.marginBottomMm}mm ${d.marginLeftMm}mm';
    final fullHtml = '''
<!DOCTYPE html>
<html dir="rtl" lang="ar">
<head>
  <meta charset="UTF-8">
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    :root {
      --accent: ${d.accentColor};
      --text:   ${d.textColor};
    }
    body {
      font-family: '${d.fontFamily}', sans-serif;
      direction: rtl;
      padding: $pad;
      font-size: ${d.fontSizeBase}px;
      font-weight: ${d.fontWeight};
      color: ${d.textColor};
      line-height: ${d.lineHeight};
    }
    h1, h2, h3 { color: var(--accent); font-size: ${d.fontSizeTitle}px; }
    @media print { body { padding: 0; } }
  </style>
</head>
<body>
$filledHtml
</body>
</html>
''';

    await Printing.layoutPdf(
      onLayout: (format) async {
        return await Printing.convertHtml(
          html: fullHtml,
          format: format,
        );
      },
    );
  }

  /// Print using a built-in default receipt (when no template exists)
  static Future<void> printDefaultReceipt({
    required ReceiptData data,
    int? receiptNo,
  }) async {
    await _loadFonts();

    final pdf = pw.Document();
    final font = _cairoFont!;
    final baseStyle = pw.TextStyle(font: font, fontSize: 11);
    final boldStyle = pw.TextStyle(font: font, fontSize: 12, fontWeight: pw.FontWeight.bold);
    final titleStyle = pw.TextStyle(font: font, fontSize: 16, fontWeight: pw.FontWeight.bold,
        color: PdfColor.fromHex('#1a7f64'));
    final smallStyle = pw.TextStyle(font: font, fontSize: 9, color: PdfColors.grey700);

    final invoiceNumber = _formatReceiptNo(receiptNo);
    final date = intl.DateFormat('yyyy/MM/dd HH:mm').format(DateTime.now());

    String opTitle;
    switch (data.operationType) {
      case 'debt_payment':
        opTitle = 'وصل تسديد دين';
        break;
      case 'debt_add':
        opTitle = 'وصل إضافة دين';
        break;
      default:
        opTitle = 'وصل تفعيل';
    }

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        textDirection: pw.TextDirection.rtl,
        build: (ctx) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              pw.Center(child: pw.Text(opTitle, style: titleStyle)),
              pw.SizedBox(height: 6),
              pw.Divider(color: PdfColor.fromHex('#1a7f64'), thickness: 2),
              pw.SizedBox(height: 10),

              _receiptRow('رقم الوصل', invoiceNumber, boldStyle, baseStyle),
              _receiptRow('التاريخ', date, boldStyle, baseStyle),
              pw.Divider(color: PdfColors.grey300),
              pw.SizedBox(height: 6),

              _receiptRow('اسم المشترك', data.subscriberName, boldStyle, baseStyle),
              if (data.phoneNumber.isNotEmpty)
                _receiptRow('رقم الهاتف', data.phoneNumber, boldStyle, baseStyle),
              if (data.packageName.isNotEmpty)
                _receiptRow('الباقة', data.packageName, boldStyle, baseStyle),
              if (data.packagePrice > 0)
                _receiptRow('سعر الباقة', AppHelpers.formatMoney(data.packagePrice), boldStyle, baseStyle),
              if (data.expiryDate.isNotEmpty)
                _receiptRow(
                  'تاريخ الانتهاء',
                  AppHelpers.formatExpiration(data.expiryDate),
                  boldStyle,
                  baseStyle,
                ),

              pw.SizedBox(height: 6),
              pw.Divider(color: PdfColors.grey300),
              pw.SizedBox(height: 6),

              if (data.paidAmount > 0)
                _receiptRow('المبلغ المدفوع', AppHelpers.formatMoney(data.paidAmount), boldStyle, baseStyle),
              if (data.debtAmount > 0)
                _receiptRow('مبلغ الدين', AppHelpers.formatMoney(data.debtAmount), boldStyle, baseStyle),
              if (data.remainingAmount > 0)
                _receiptRow('المتبقي', AppHelpers.formatMoney(data.remainingAmount), boldStyle, baseStyle),

              pw.SizedBox(height: 20),
              pw.Divider(color: PdfColor.fromHex('#1a7f64'), thickness: 1),
              pw.SizedBox(height: 6),
              pw.Center(child: pw.Text('شكراً لكم', style: smallStyle)),
            ],
          );
        },
      ),
    );

    await Printing.layoutPdf(
      onLayout: (_) async => pdf.save(),
    );
  }

  static pw.Widget _receiptRow(
      String label, String value, pw.TextStyle labelStyle, pw.TextStyle valueStyle) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 3),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label, style: labelStyle),
          pw.Text(value, style: valueStyle),
        ],
      ),
    );
  }

  /// Quick print: tries active template first, falls back to default.
  ///
  /// [receiptNo] رقم الوصل من الـbackend (null → fallback INV-timestamp).
  /// [design] إعدادات التصميم من template_data — تُطبَّق على HTML wrapper.
  static Future<void> printReceipt({
    required ReceiptData data,
    String? htmlTemplate,
    int? receiptNo,
    ReceiptDesign? design,
  }) async {
    if (htmlTemplate != null && htmlTemplate.isNotEmpty) {
      await printWithTemplate(
        htmlTemplate: htmlTemplate,
        data: data,
        receiptNo: receiptNo,
        design: design,
      );
    } else {
      await printDefaultReceipt(data: data, receiptNo: receiptNo);
    }
  }
}
