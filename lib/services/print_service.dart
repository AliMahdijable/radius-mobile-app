import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

/// خدمة طباعة الوصولات — تستعمل نظام الطباعة الأصلي للـOS
/// (Android Print Framework + iOS AirPrint). النظام:
///   • يكتشف طابعات الشبكة تلقائياً (WiFi/AirPrint/mDNS)
///   • يعرض dialog اختيار
///   • يدعم PDF preview + شير + حفظ
///
/// المدير لا يحتاج إعدادات IP/port — النظام يتكفّل بكل شيء.
class PrintService {
  PrintService._();

  /// المتغيّرات القياسيّة داخل قوالب HTML — يجب مطابقة PrintTemplate.availableVariables.
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

  /// يعبّئ المتغيّرات في HTML template بقيم من data map.
  /// المفاتيح غير الموجودة تُترك كما هي (يفيد لعرض بيانات جزئيّة).
  static String fillTemplate(String htmlTemplate, Map<String, String> data) {
    var result = htmlTemplate;
    for (final entry in data.entries) {
      final token = '{${entry.key}}';
      result = result.replaceAll(token, entry.value);
    }
    return result;
  }

  /// طباعة receipt عبر system print dialog. يحوّل HTML → PDF ثم يفتح
  /// dialog اختيار الطابعة (يعرض تلقائياً كل الطابعات المكتشفة على الشبكة).
  ///
  /// [format]:
  ///   • PdfPageFormat.a4 → للـA4 templates
  ///   • PdfPageFormat.roll80 → للـPOS 80mm (thermal printer)
  ///
  /// [documentName] يظهر في dialog + حفظ PDF.
  static Future<bool> printHtml({
    required String html,
    required PdfPageFormat format,
    String documentName = 'Receipt',
  }) async {
    try {
      // يستعمل Chrome PdfPrinter على Android + WebKit على iOS لتحويل HTML لـPDF.
      // نتيجة أنيقة لأنّ الـHTML لا يُبسَّط.
      final Uint8List pdfBytes = await Printing.convertHtml(
        format: format,
        html: html,
      );
      // Printing.layoutPdf يفتح النظام dialog الأصلي:
      //   - Android: PrintManager → قائمة طابعات مكتشفة تلقائياً
      //   - iOS: UIPrintInteractionController + AirPrint
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

  /// مشاركة PDF بدل الطباعة المباشرة — يفتح Share sheet.
  /// يفيد لو المدير عاوز يحفظ الـPDF أو يرسله بواتساب.
  static Future<bool> sharePdf({
    required String html,
    required PdfPageFormat format,
    String filename = 'receipt.pdf',
  }) async {
    try {
      final Uint8List pdfBytes = await Printing.convertHtml(
        format: format,
        html: html,
      );
      return await Printing.sharePdf(bytes: pdfBytes, filename: filename);
    } catch (e) {
      if (kDebugMode) debugPrint('[PrintService] sharePdf failed: $e');
      return false;
    }
  }

  /// بيانات وهميّة للـpreview/اختبار — تُستعمل من زر "طباعة تجريبية".
  static Map<String, String> get sampleData => const {
        'invoice_number': '00001',
        'date': '2026-07-13',
        'subscriber_name': 'أحمد محمد',
        'phone_number': '07901234567',
        'package_name': 'باقة 20 ميغا',
        'package_price': '35,000',
        'paid_amount': '35,000',
        'remaining_amount': '0',
        'expiry_date': '2026-08-13',
        'debt_amount': '0',
      };

  /// اختصار: PdfPageFormat مناسب لكل type.
  static PdfPageFormat formatForType(String type) {
    if (type == 'pos') {
      // 80mm thermal — طول متغيّر (الطابعة تحدّده)
      return PdfPageFormat.roll80;
    }
    return PdfPageFormat.a4;
  }
}
