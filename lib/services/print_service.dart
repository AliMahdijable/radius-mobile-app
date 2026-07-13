import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

/// خدمة طباعة الوصولات — تستعمل نظام الطباعة الأصلي للـOS
/// (Android Print Framework + iOS AirPrint). النظام:
///   • يكتشف طابعات الشبكة تلقائياً (WiFi/AirPrint/mDNS)
///   • يعرض dialog اختيار
///   • يدعم PDF preview + شير + حفظ
///
/// المدير لا يحتاج إعدادات IP/port — النظام يتكفّل بكل شيء.
///
/// **ملاحظة تقنيّة 2026-07-13**:
/// كنّا نستعمل Printing.convertHtml() لتحويل HTML → PDF لكن WebView
/// (chromium) على الأندرويد يتعطّل أحياناً — خاصّة على الإيموليتر:
///     E/chromium: Renderer process crash detected (code -1)
/// النتيجة: زر المعاينة ما يظهر شي.
/// الحلّ: نبني PDF **مباشرة** باستعمال pdf package widgets (بدون WebView).
/// نتيجة: يشتغل على كل جهاز/إيموليتر بدون أعطال.
class PrintService {
  PrintService._();

  static const List<String> variables = [
    '{invoice_number}',
    '{date}',
    '{subscriber_name}',
    '{phone_number}',
    '{package_name}',
    '{package_price}',
    '{paid_amount}',
    '{remaining_amount}',
    '{expiry_date}',
    '{debt_amount}',
  ];

  /// يعبّئ المتغيّرات في HTML template بقيم من data map. (لا يزال مفيداً
  /// لعرض HTML على الويب. الموبايل يبني PDF مباشرة من data.)
  static String fillTemplate(String htmlTemplate, Map<String, String> data) {
    var result = htmlTemplate;
    for (final entry in data.entries) {
      final token = '{${entry.key}}';
      result = result.replaceAll(token, entry.value);
    }
    return result;
  }

  /// طباعة receipt عبر system print dialog — يبني PDF مباشرة (بدون HTML).
  /// يفتح Preview + قائمة الطابعات المكتشفة تلقائياً.
  ///
  /// [format]: PdfPageFormat.roll80 للـPOS أو PdfPageFormat.a4.
  /// [data]: خريطة القيم (subscriber_name, package_price, إلخ).
  /// [title]: عنوان الوصل (مثلاً "فاتورة تفعيل" أو "فاتورة تسديد دين").
  /// [documentName]: اسم PDF في dialog.
  static Future<bool> printReceipt({
    required Map<String, String> data,
    required PdfPageFormat format,
    required String title,
    String documentName = 'Receipt',
    String? companyName,
  }) async {
    try {
      return await Printing.layoutPdf(
        name: documentName,
        format: format,
        onLayout: (fmt) async => _buildPdf(
          data: data,
          format: fmt,
          title: title,
          companyName: companyName,
        ),
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[PrintService] printReceipt failed: $e');
      return false;
    }
  }

  /// (احتياطي) طباعة HTML — تعتمد على WebView. تُبقى للاستخدام لاحقاً لو
  /// أردنا rendering HTML من الويب. الافتراضي: printReceipt أعلاه.
  static Future<bool> printHtml({
    required String html,
    required PdfPageFormat format,
    String documentName = 'Receipt',
  }) async {
    try {
      final Uint8List pdfBytes = await Printing.convertHtml(
        format: format,
        html: html,
      );
      return await Printing.layoutPdf(
        name: documentName,
        format: format,
        onLayout: (_) async => pdfBytes,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[PrintService] printHtml failed: $e');
      return false;
    }
  }

  /// بيانات وهميّة للـpreview/اختبار.
  static Map<String, String> get sampleData => const {
        'invoice_number': 'NO-00001',
        'date': '2026-07-13 14:30',
        'subscriber_name': 'أحمد محمد',
        'phone_number': '07901234567',
        'package_name': 'باقة 20 ميغا',
        'package_price': '35,000',
        'paid_amount': '35,000',
        'remaining_amount': '0',
        'expiry_date': '2026-08-13 14:30',
        'debt_amount': '0',
      };

  static PdfPageFormat formatForType(String type) {
    if (type == 'pos') {
      // 80mm thermal — طول متغيّر (الطابعة تحدّده)
      return PdfPageFormat.roll80;
    }
    return PdfPageFormat.a4;
  }

  // ═══════════════════════════════════════════════
  // PDF Builder — pw widgets مباشرة (بدون WebView)
  // ═══════════════════════════════════════════════
  static Future<Uint8List> _buildPdf({
    required Map<String, String> data,
    required PdfPageFormat format,
    required String title,
    String? companyName,
  }) async {
    // تحميل خط Cairo (يدعم العربي). PdfGoogleFonts يجيبه من CDN ويكاش.
    // لو الجهاز offline، pdf package يستعمل fallback (لن يعرض عربي صحيح).
    pw.Font? cairoRegular;
    pw.Font? cairoBold;
    try {
      cairoRegular = await PdfGoogleFonts.cairoRegular();
      cairoBold = await PdfGoogleFonts.cairoBold();
    } catch (e) {
      if (kDebugMode) debugPrint('[PrintService] cairo font fetch failed: $e');
    }

    final theme = pw.ThemeData.withFont(
      base: cairoRegular ?? pw.Font.helvetica(),
      bold: cairoBold ?? pw.Font.helveticaBold(),
    );

    final doc = pw.Document(theme: theme);
    final isPos = format.width <= PdfPageFormat.roll80.width + 5;

    doc.addPage(
      pw.Page(
        pageFormat: format,
        margin: isPos
            ? const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 12)
            : const pw.EdgeInsets.all(32),
        textDirection: pw.TextDirection.rtl,
        build: (context) => isPos
            ? _buildPosLayout(data: data, title: title, companyName: companyName)
            : _buildA4Layout(data: data, title: title, companyName: companyName),
      ),
    );
    return doc.save();
  }

  static pw.Widget _buildPosLayout({
    required Map<String, String> data,
    required String title,
    String? companyName,
  }) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        // Header
        if (companyName != null && companyName.trim().isNotEmpty)
          pw.Center(
            child: pw.Text(
              companyName,
              style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
            ),
          ),
        pw.SizedBox(height: 4),
        pw.Center(
          child: pw.Text(
            title,
            style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
          ),
        ),
        pw.SizedBox(height: 4),
        pw.Center(
          child: pw.Text(
            data['invoice_number'] ?? '',
            style: const pw.TextStyle(fontSize: 9),
          ),
        ),
        pw.Center(
          child: pw.Text(
            data['date'] ?? '',
            style: const pw.TextStyle(fontSize: 9),
          ),
        ),
        pw.SizedBox(height: 6),
        pw.Divider(thickness: 0.5),
        pw.SizedBox(height: 4),
        _posRow('المشترك', data['subscriber_name']),
        _posRow('الهاتف', data['phone_number']),
        _posRow('الباقة', data['package_name']),
        pw.SizedBox(height: 4),
        pw.Divider(thickness: 0.5),
        pw.SizedBox(height: 4),
        _posRow('سعر الباقة', '${data['package_price'] ?? '—'} د.ع'),
        _posRow('المدفوع', '${data['paid_amount'] ?? '—'} د.ع'),
        _posRow('المتبقّي', '${data['remaining_amount'] ?? '—'} د.ع'),
        if ((data['debt_amount'] ?? '0') != '0')
          _posRow('الدين', '${data['debt_amount']} د.ع'),
        _posRow('الانتهاء', data['expiry_date']),
        pw.SizedBox(height: 8),
        pw.Divider(thickness: 0.5),
        pw.SizedBox(height: 4),
        pw.Center(
          child: pw.Text(
            'شكراً لتعاملكم معنا',
            style: pw.TextStyle(fontSize: 9, fontStyle: pw.FontStyle.italic),
          ),
        ),
      ],
    );
  }

  static pw.Widget _posRow(String label, String? value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            '$label:',
            style: const pw.TextStyle(fontSize: 9),
          ),
          pw.Flexible(
            child: pw.Text(
              value ?? '—',
              style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
              textAlign: pw.TextAlign.left,
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildA4Layout({
    required Map<String, String> data,
    required String title,
    String? companyName,
  }) {
    const brand = PdfColor.fromInt(0xFF2D5F47);
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        // Header
        pw.Container(
          padding: const pw.EdgeInsets.only(bottom: 18),
          decoration: const pw.BoxDecoration(
            border: pw.Border(
              bottom: pw.BorderSide(color: brand, width: 2),
            ),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              if (companyName != null && companyName.trim().isNotEmpty)
                pw.Text(
                  companyName,
                  style: pw.TextStyle(
                      fontSize: 22, fontWeight: pw.FontWeight.bold, color: brand),
                  textAlign: pw.TextAlign.center,
                ),
              pw.SizedBox(height: 6),
              pw.Text(
                title,
                style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
                textAlign: pw.TextAlign.center,
              ),
              pw.SizedBox(height: 4),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('رقم الوصل: ${data['invoice_number'] ?? ''}',
                      style: const pw.TextStyle(fontSize: 10)),
                  pw.Text('التاريخ: ${data['date'] ?? ''}',
                      style: const pw.TextStyle(fontSize: 10)),
                ],
              ),
            ],
          ),
        ),
        pw.SizedBox(height: 24),
        // Subscriber block
        _a4SectionTitle('بيانات المشترك'),
        pw.SizedBox(height: 8),
        _a4Table([
          ['اسم المشترك', data['subscriber_name'] ?? '—'],
          ['رقم الهاتف', data['phone_number'] ?? '—'],
          ['اسم الباقة', data['package_name'] ?? '—'],
        ]),
        pw.SizedBox(height: 20),
        // Payment block
        _a4SectionTitle('تفاصيل الفاتورة'),
        pw.SizedBox(height: 8),
        _a4Table([
          ['سعر الباقة', '${data['package_price'] ?? '—'} د.ع'],
          ['المبلغ المدفوع', '${data['paid_amount'] ?? '—'} د.ع'],
          ['المبلغ المتبقّي', '${data['remaining_amount'] ?? '—'} د.ع'],
          if ((data['debt_amount'] ?? '0') != '0')
            ['الدين الحالي', '${data['debt_amount']} د.ع'],
          ['تاريخ الانتهاء', data['expiry_date'] ?? '—'],
        ]),
        pw.Spacer(),
        pw.Divider(color: brand, thickness: 0.5),
        pw.SizedBox(height: 8),
        pw.Center(
          child: pw.Text(
            'شكراً لتعاملكم معنا',
            style: pw.TextStyle(fontSize: 11, color: PdfColors.grey600),
          ),
        ),
      ],
    );
  }

  static pw.Widget _a4SectionTitle(String text) {
    return pw.Text(
      text,
      style: pw.TextStyle(
        fontSize: 13,
        fontWeight: pw.FontWeight.bold,
      ),
    );
  }

  static pw.Widget _a4Table(List<List<String>> rows) {
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
      columnWidths: const {
        0: pw.FlexColumnWidth(1),
        1: pw.FlexColumnWidth(2),
      },
      children: rows
          .map(
            (r) => pw.TableRow(
              children: [
                pw.Container(
                  color: PdfColors.grey100,
                  padding: const pw.EdgeInsets.all(8),
                  child: pw.Text(
                    r[0],
                    style: pw.TextStyle(
                      fontSize: 11,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ),
                pw.Container(
                  padding: const pw.EdgeInsets.all(8),
                  child: pw.Text(
                    r[1],
                    style: const pw.TextStyle(fontSize: 11),
                  ),
                ),
              ],
            ),
          )
          .toList(),
    );
  }
}
