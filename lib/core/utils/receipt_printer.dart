import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart' as intl;
import '../../models/print_template_model.dart';
import 'helpers.dart';

/// بيانات الوصل المطبوع (sample أو حقيقية).
class ReceiptData {
  final String subscriberName; // {subscriber_name} → username (لاتيني)
  final String firstName;      // {firstname} → الاسم العربي
  final String phoneNumber;
  final String packageName;
  final double packagePrice;
  final double paidAmount;
  final double remainingAmount;
  final double debtAmount;
  final String expiryDate;
  final String operationType; // 'activation' | 'debt_payment' | 'debt_add'
  final String shopName;
  final String shopAddress;
  final String shopPhone;
  final String managerName;

  const ReceiptData({
    required this.subscriberName,
    this.firstName = '',
    this.phoneNumber = '',
    this.packageName = '',
    this.packagePrice = 0,
    this.paidAmount = 0,
    this.remainingAmount = 0,
    this.debtAmount = 0,
    this.expiryDate = '',
    this.operationType = 'activation',
    this.shopName = 'MyServices',
    this.shopAddress = '',
    this.shopPhone = '',
    this.managerName = '',
  });
}

/// مُصمِّم/طابع الوصل — يبني PDF **native** بمكتبة `pdf` (لا HTML→PDF).
///
/// السبب: `Printing.convertHtml` على أندرويد يُهنّ/يفشل لصفحات A4 (يستعمل
/// webview داخلي محدود). الـnative render موثوق لـ A4 وPOS، سريع، ويحترم
/// كل قيم [ReceiptDesign] (الهوامش، الخطوط، الألوان، إظهار/إخفاء الأقسام).
/// نفس الـPDF يُستخدم للطباعة والمعاينة → ما تشوفه هو ما يطبع.
class ReceiptPrinter {
  static pw.Font? _cairoRegular;
  static pw.Font? _cairoBold;

  static Future<void> _loadFonts() async {
    if (_cairoRegular != null) return;
    final data = await rootBundle.load('assets/fonts/Cairo-Variable.ttf');
    _cairoRegular = pw.Font.ttf(data);
    _cairoBold = pw.Font.ttf(data); // variable font؛ نستعمل fontWeight
  }

  static String _formatReceiptNo(int? no) {
    if (no == null || no < 0) {
      return 'INV-${DateTime.now().millisecondsSinceEpoch}';
    }
    return 'No. ${no.toString().padLeft(5, '0')}';
  }

  static PdfColor _hex(String h, [PdfColor fallback = PdfColors.black]) {
    try {
      final s = h.replaceAll('#', '').trim();
      if (s.length == 6) return PdfColor.fromHex(s);
    } catch (_) {}
    return fallback;
  }

  static String _opTitle(String op) {
    switch (op) {
      case 'debt_payment': return 'وصل تسديد دين';
      case 'debt_add':     return 'وصل إضافة دين';
      default:             return 'وصل تفعيل';
    }
  }

  // ─────────────────────────────────────────────────────────────────
  // البناء الأساسي — يرجع bytes الـPDF.
  // ─────────────────────────────────────────────────────────────────

  static Future<Uint8List> buildReceiptPdf({
    required ReceiptData data,
    ReceiptDesign? design,
    String type = 'pos', // 'pos' | 'a4'
    int? receiptNo,
  }) async {
    await _loadFonts();
    final d = design ?? ReceiptDesign();
    final reg = _cairoRegular!;
    final bold = _cairoBold!;

    // ── أبعاد الصفحة + الهوامش من التصميم ──
    final mL = d.marginLeftMm * PdfPageFormat.mm;
    final mT = d.marginTopMm * PdfPageFormat.mm;
    final mR = d.marginRightMm * PdfPageFormat.mm;
    final mB = d.marginBottomMm * PdfPageFormat.mm;
    final marginPts = pw.EdgeInsets.fromLTRB(mL, mT, mR, mB);

    late final PdfPageFormat pageFormat;
    if (type == 'a4') {
      final landscape = d.a4Orientation == 'landscape';
      final w = landscape ? PdfPageFormat.a4.height : PdfPageFormat.a4.width;
      final h = landscape ? PdfPageFormat.a4.width : PdfPageFormat.a4.height;
      pageFormat = PdfPageFormat(w, h,
          marginLeft: mL, marginTop: mT, marginRight: mR, marginBottom: mB);
    } else {
      // POS roll — pw.Page يحتاج ارتفاعاً محدوداً؛ نستعمل 297mm (طول A4)
      // كحدّ أعلى. المحتوى الأقصر يترك بياضاً يُقصّ بصرياً في المعاينة،
      // وعلى الطابعة الحرارية الورقة الزائدة تتغذّى طبيعياً.
      pageFormat = PdfPageFormat(d.paperWidthMm * PdfPageFormat.mm,
          297 * PdfPageFormat.mm,
          marginLeft: mL, marginTop: mT, marginRight: mR, marginBottom: mB);
    }

    // ── أنماط نصّية مشتقّة من التصميم ──
    final accent = _hex(d.accentColor, PdfColor.fromHex('0d9488'));
    final textColor = _hex(d.textColor, PdfColors.black);
    final baseSize = d.fontSizeBase.toDouble();
    final titleSize = d.fontSizeTitle.toDouble();
    final lh = d.lineHeight.toDouble();

    final styleBase = pw.TextStyle(
        font: reg, fontSize: baseSize, color: textColor, lineSpacing: (lh - 1) * baseSize);
    final styleLabel = pw.TextStyle(
        font: reg, fontSize: baseSize * 0.9, color: PdfColor(0.4, 0.4, 0.45));
    final styleValue = pw.TextStyle(
        font: bold, fontSize: baseSize, color: textColor, fontWeight: pw.FontWeight.bold);
    final styleTitle = pw.TextStyle(
        font: bold, fontSize: titleSize, color: accent, fontWeight: pw.FontWeight.bold);
    final styleSection = pw.TextStyle(
        font: bold, fontSize: baseSize * 0.95, color: accent, fontWeight: pw.FontWeight.bold);
    final styleFooter = pw.TextStyle(
        font: reg, fontSize: baseSize * 0.82, color: PdfColor(0.45, 0.45, 0.5));

    final gap = d.sectionGapMm * PdfPageFormat.mm;
    final invoiceNumber = _formatReceiptNo(receiptNo);
    final date = templateHelper_formatDate(DateTime.now());

    pw.MainAxisAlignment headerAlign() {
      switch (d.headerAlign) {
        case 'left': return pw.MainAxisAlignment.start;
        case 'right': return pw.MainAxisAlignment.end;
        default: return pw.MainAxisAlignment.center;
      }
    }

    pw.Widget kv(String label, String value) => pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 2),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(label, style: styleLabel),
              pw.Flexible(
                  child: pw.Text(value,
                      style: styleValue,
                      textAlign: pw.TextAlign.left,
                      maxLines: 2)),
            ],
          ),
        );

    pw.Widget sectionTitle(String t) {
      final txt = d.sectionTitleUppercase ? t : t;
      return pw.Padding(
        padding: pw.EdgeInsets.only(top: gap, bottom: 4),
        child: d.sectionTitleUnderline
            ? pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                pw.Text(txt, style: styleSection),
                pw.SizedBox(height: 2),
                pw.Container(
                    height: 1.2,
                    width: 60,
                    color: PdfColor(accent.red, accent.green, accent.blue, 0.5)),
              ])
            : pw.Text(txt, style: styleSection),
      );
    }

    final borderColor = PdfColor(0.78, 0.78, 0.8);
    pw.Widget divider() => pw.Padding(
          padding: pw.EdgeInsets.symmetric(vertical: gap * 0.4),
          child: d.borderStyle == 'none'
              ? pw.SizedBox.shrink()
              : pw.Container(height: 0.7, color: borderColor),
        );

    final pdf = pw.Document();
    pdf.addPage(
      pw.Page(
        pageFormat: pageFormat,
        textDirection: pw.TextDirection.rtl,
        margin: marginPts,
        build: (ctx) {
          final children = <pw.Widget>[];

          // ── رأس المتجر ──
          if (d.showShopInfo) {
            children.add(pw.Row(
              mainAxisAlignment: headerAlign(),
              children: [pw.Text(data.shopName, style: styleTitle)],
            ));
            if (data.shopAddress.isNotEmpty || data.shopPhone.isNotEmpty) {
              children.add(pw.SizedBox(height: 2));
              children.add(pw.Row(
                mainAxisAlignment: headerAlign(),
                children: [
                  pw.Text(
                    [
                      if (data.shopAddress.isNotEmpty) '📍 ${data.shopAddress}',
                      if (data.shopPhone.isNotEmpty) '📞 ${data.shopPhone}',
                    ].join('   '),
                    style: styleFooter,
                  ),
                ],
              ));
            }
            children.add(pw.SizedBox(height: gap * 0.6));
          }

          // ── عنوان الوصل ──
          children.add(pw.Row(
            mainAxisAlignment: headerAlign(),
            children: [pw.Text(_opTitle(data.operationType), style: styleTitle)],
          ));
          children.add(divider());

          // ── رقم الوصل + التاريخ ──
          if (d.showReceiptId) children.add(kv('رقم الوصل', invoiceNumber));
          if (d.showDatetime) children.add(kv('التاريخ', date));
          if (d.showReceiptId || d.showDatetime) children.add(divider());

          // ── المشترك ──
          if (d.showSubscriberInfo) {
            children.add(sectionTitle('المشترك'));
            if (data.firstName.isNotEmpty) children.add(kv('الاسم', data.firstName));
            children.add(kv('اسم المستخدم', data.subscriberName));
            if (data.phoneNumber.isNotEmpty) children.add(kv('الهاتف', data.phoneNumber));
          }

          // ── الباقة ──
          if (d.showPackageInfo) {
            children.add(sectionTitle('الباقة'));
            if (data.packageName.isNotEmpty) children.add(kv('الباقة', data.packageName));
            if (d.showPackagePrice && data.packagePrice > 0) {
              children.add(kv('سعر الباقة', AppHelpers.formatMoney(data.packagePrice)));
            }
            if (data.expiryDate.isNotEmpty) {
              children.add(kv('تاريخ الانتهاء',
                  AppHelpers.formatExpiration(data.expiryDate)));
            }
          }

          // ── العملية ──
          if (d.showTransactionInfo) {
            children.add(sectionTitle('المعاملة'));
            if (data.paidAmount > 0) {
              children.add(kv('المبلغ المدفوع', AppHelpers.formatMoney(data.paidAmount)));
            }
            if (data.debtAmount > 0) {
              children.add(kv('مبلغ الدين', AppHelpers.formatMoney(data.debtAmount)));
            }
            if (data.remainingAmount > 0) {
              children.add(kv('المتبقي', AppHelpers.formatMoney(data.remainingAmount)));
            }
          }

          // ── توقيع المدير ──
          if (d.showManagerSignature && data.managerName.isNotEmpty) {
            children.add(pw.SizedBox(height: gap));
            children.add(kv('أصدره', data.managerName));
          }

          // ── الذيل ──
          if (d.showFooter) {
            children.add(divider());
            children.add(pw.Row(
              mainAxisAlignment: d.footerAlign == 'left'
                  ? pw.MainAxisAlignment.start
                  : (d.footerAlign == 'right'
                      ? pw.MainAxisAlignment.end
                      : pw.MainAxisAlignment.center),
              children: [pw.Text('شكراً لاختياركم خدماتنا', style: styleFooter)],
            ));
          }

          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: children,
          );
        },
      ),
    );
    return pdf.save();
  }

  // ─────────────────────────────────────────────────────────────────
  // الطباعة (يفتح حوار الطباعة) — يستعمل نفس الـbuilder.
  // ─────────────────────────────────────────────────────────────────

  static Future<void> printReceipt({
    required ReceiptData data,
    ReceiptDesign? design,
    String type = 'pos',
    int? receiptNo,
    // ملاحظة: htmlTemplate لم يعد مستعملاً — أبقيناه للتوافق العكسي مع
    // الـcallers القديمين. الـnative renderer هو المسار الوحيد الآن.
    @Deprecated('htmlTemplate is ignored; native renderer is used') String? htmlTemplate,
  }) async {
    final bytes = await buildReceiptPdf(
      data: data, design: design, type: type, receiptNo: receiptNo);
    await Printing.layoutPdf(onLayout: (_) async => bytes);
  }

  // backward-compat shim — كان يأخذ htmlTemplate؛ الآن يتجاهله.
  static Future<void> printWithTemplate({
    required String htmlTemplate,
    required ReceiptData data,
    int? receiptNo,
    ReceiptDesign? design,
    String type = 'pos',
  }) =>
      printReceipt(data: data, design: design, type: type, receiptNo: receiptNo);

  // ─────────────────────────────────────────────────────────────────
  // أداة تنسيق تاريخ بسيطة (yyyy-MM-dd H:MM صباحاً/مساءً، بغداد).
  // ─────────────────────────────────────────────────────────────────
  static String templateHelper_formatDate(DateTime now) {
    final fmt = intl.DateFormat('yyyy-MM-dd', 'en');
    final h24 = int.parse(intl.DateFormat('HH').format(now));
    final mm = intl.DateFormat('mm').format(now);
    final ampm = h24 >= 12 ? 'مساءً' : 'صباحاً';
    final h12 = h24 % 12 == 0 ? 12 : h24 % 12;
    return '${fmt.format(now)} $h12:$mm $ampm';
  }
}
