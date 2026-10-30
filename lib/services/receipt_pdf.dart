import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart' as intl;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../api/receipt_settings_api.dart';
import 'print_output.dart';

/// نوع الوصل وعنوانه كما يطبعه الموقع (`client-v2/src/lib/print-receipt.ts`).
enum ReceiptKind {
  activation('وصل تفعيل', 'activate'),
  extension('وصل تمديد', 'extend'),
  payment('وصل تسديد دين', 'pay_debt'),
  info('بطاقة معلومات المشترك', null),

  /// فاتورة البيع (قسم «المبيعات») — لا تُؤرشف: البيع محفوظٌ في جدوله برقمه.
  sale('فاتورة بيع', null);

  const ReceiptKind(this.title, this.archiveOp);

  final String title;

  /// `operation_type` في أرشيف الوصولات — بطاقة المعلومات لا تُؤرشف (كالموقع).
  final String? archiveOp;
}

/// طريقة الدفع بتسمية وصل الموقع، ورمزها في الأرشيف.
enum ReceiptPay {
  cash('نقدي', 'cash'),
  partial('نقدي جزئي', 'partial'),
  credit('غير نقدي', 'credit');

  const ReceiptPay(this.label, this.archiveMethod);

  final String label;
  final String archiveMethod;
}

/// فاتورة البيع — المالك ٢٩ أكتوبر: «الفاتورة… اشبه بفاتورة النظام… نفسه الفاتورة لكن تصير مبيعات»: الموادّ والمجموع
/// وطريقة الدفع بأقسام الوصل وتصميمه نفسه ([ReceiptPdf]).
@immutable
class SaleInvoiceDoc {
  const SaleInvoiceDoc({
    required this.id,
    required this.lines,
    required this.total,
    required this.debt,
    this.note,
    this.voided = false,
    this.voidReason,
  });

  final int id;

  /// كلّ مادّة: اسمها، والكمّيّة بوحدتها («15 متر»)، وسعر الوحدة، ومجموعها.
  final List<({String name, String qty, num unitPrice, num total})> lines;
  final num total;

  /// على حساب المشترك (دين) لا نقداً.
  final bool debt;
  final String? note;
  final bool voided;
  final String? voidReason;
}

/// محتوى وصلٍ واحد — مستقلٌّ عن الشبكة والطابعة (يُبنى ويُختبر وحده).
@immutable
class ReceiptDoc {
  const ReceiptDoc({
    required this.kind,
    required this.issuedAt,
    required this.shopName,
    required this.subscriberName,
    required this.username,
    this.look = const ReceiptSettings(),
    this.receiptNo,
    this.phone,
    this.packageName,
    this.packagePrice,
    this.expiration,
    this.remainingDays,
    this.pay,
    this.amount,
    this.partialAmount,
    this.newBalance,
    this.qrUrl,
    this.issuer,
    this.sale,
  });

  final ReceiptKind kind;
  final DateTime issuedAt;
  final String shopName;
  final String subscriberName;
  final String username;

  /// مصمّم الوصل في الموقع: الترويسة والتذييل وما يظهر من الأقسام وعرض الورق.
  final ReceiptSettings look;

  /// رقم الأرشيف (مرقّمٌ لكلّ مدير)؛ null ⇒ مرجعٌ زمنيّ قصير كالموقع.
  final int? receiptNo;
  final String? phone;
  final String? packageName;
  final num? packagePrice;
  final String? expiration;
  final int? remainingDays;
  final ReceiptPay? pay;
  final num? amount;
  final num? partialAmount;

  /// رصيد المشترك بعد العمليّة: سالبٌ = دين.
  final num? newBalance;
  final String? qrUrl;

  /// «أصدره: …» — اسم الموظّف إن طبع موظّف، وإلّا يوزر المدير.
  final String? issuer;

  /// فاتورة البيع ([ReceiptKind.sale]) — الزبون في [subscriberName]/[username]/[phone]، ووقت البيع في [issuedAt].
  final SaleInvoiceDoc? sale;

  /// العنوان المطبوع: الفاتورة برقمها.
  String get title => sale != null ? '${kind.title} رقم ${sale!.id}' : kind.title;

  String get receiptId => receiptNo != null
      ? 'No. ${receiptNo.toString().padLeft(5, '0')}'
      : 'R-${issuedAt.millisecondsSinceEpoch.toRadixString(36).toUpperCase()}';

  /// وقت الإصدار بتوقيت بغداد مهما كانت منطقة الجهاز (كالموقع). العراق بلا توقيتٍ صيفيّ.
  String get issuedText => intl.DateFormat('yyyy-MM-dd HH:mm', 'en_US')
      .format(issuedAt.toUtc().add(const Duration(hours: 3)));

  /// صفوف «المعاملة» بترتيب الموقع وتسمياته.
  List<(String, String, num?)> get transactionRows {
    final rows = <(String, String, num?)>[];
    if (kind == ReceiptKind.activation || kind == ReceiptKind.extension) {
      if (pay != null) rows.add(('طريقة الدفع', pay!.label, null));
      if (amount != null) rows.add(('المبلغ', ReceiptPdf.money(amount!), null));
      if (pay == ReceiptPay.partial && partialAmount != null) {
        rows.add(('المُدفَع نقداً', ReceiptPdf.money(partialAmount!), null));
      }
    } else if (kind == ReceiptKind.payment && amount != null) {
      rows.add(('المبلغ المسدَّد', ReceiptPdf.money(amount!), null));
    }
    final b = newBalance;
    if (b != null) {
      final label = b < 0 ? 'الدين المتبقّي' : (b > 0 ? 'الرصيد المتبقّي' : 'الرصيد');
      rows.add((label, ReceiptPdf.money(b.abs()), b));
    }
    return rows;
  }
}

/// يرسم [ReceiptDoc] PDF بأقسام وصل الموقع: ورق الكاشير (عرضه من المصمّم، وطوله طول المحتوى) أو A4.
class ReceiptPdf {
  ReceiptPdf._();

  static final _money = intl.NumberFormat('#,###', 'en_US');

  static String money(num v) {
    final n = v.abs().round();
    return '${n == 0 ? '0' : _money.format(n)} د.ع';
  }

  /// بلا تشكيل: مكتبة PDF لا تضع الحركات والتنوين في مواضعها («شكراً» تخرج بتنوينٍ منفصل).
  static String plain(String s) => s.replaceAll(RegExp('[\u064B-\u065F\u0670]'), '');

  /// الانتهاء كما يعرضه الموقع: أوّل ١٦ حرفاً («2026-11-24 18:30»).
  static String expiry(String s) => s.length > 16 ? s.substring(0, 16) : s;

  /// [theme] للاختبار وحده (خطٌّ بلا تحميل أصول)؛ بلاه خطّ التطبيق.
  ///
  /// [paper] ورق الطابعة كما أرسله النظام قبل الطباعة (ويندوز، [PrintOutput.bytesFor]): الوصل يُرسم بعرضه،
  /// وحواشيه لا تقلّ عن حواشي الطابعة غير المطبوعة — كما يرسم المتصفّح وصل الموقع. بلاه عرض المصمّم.
  static Future<PrintDoc> build(ReceiptDoc d, {required bool a4, pw.ThemeData? theme, PdfPageFormat? paper}) async {
    final th = theme ?? await PdfFonts.theme();
    final look = d.look;
    const mm = PdfPageFormat.mm;
    final requested = a4
        ? (paper == null ? PdfPageFormat.a4 : PdfPageFormat(paper.width, paper.height))
        : PdfPageFormat(paper?.width ?? look.paperWidthMm * mm, double.infinity);
    double edge(double own, double? printer) => math.max(own, printer ?? 0);
    final margin = a4
        ? pw.EdgeInsets.fromLTRB(edge(48, paper?.marginLeft), edge(32, paper?.marginTop),
            edge(48, paper?.marginRight), edge(32, paper?.marginBottom))
        // الكاشير: حواشي المصمّم (٤ ملم افتراضاً، كالموقع).
        : pw.EdgeInsets.fromLTRB(
            edge(look.marginLeftMm * mm, paper?.marginLeft),
            edge(look.marginTopMm * mm, paper?.marginTop),
            edge(look.marginRightMm * mm, paper?.marginRight),
            edge(look.marginBottomMm * mm, paper?.marginBottom),
          );
    final name = d.sale != null ? 'Sale-${d.sale!.id}' : '${d.kind.name}-${d.username}';
    Future<PrintDoc> render(bool withLogo) {
      final doc = pw.Document(theme: th, title: d.title, creator: 'MyServices Pro');
      pw.MemoryImage? logo;
      if (withLogo && look.showLogo && look.logo != null) {
        logo = pw.MemoryImage(look.logo!);
      }
      final width = requested.width - margin.horizontal;
      doc.addPage(pw.Page(
        pageFormat: requested,
        textDirection: pw.TextDirection.rtl,
        margin: margin,
        build: (_) => _Body(d, logo: logo, a4: a4, width: width).build(),
      ));
      return PrintDoc.of(
        doc,
        name: name,
        requested: requested,
        refit: paper != null ? null : (printer) async => (await build(d, a4: a4, theme: th, paper: printer)).bytes,
      );
    }

    try {
      return await render(true);
    } catch (e) {
      // شعارٌ لا يُرسم (صورةٌ تالفة رغم ترويستها) لا يُسقط الوصل كلّه.
      if (d.look.logo == null) rethrow;
      if (kDebugMode) debugPrint('[ReceiptPdf] logo dropped: $e');
      return render(false);
    }
  }
}

/// زوايا بطاقة A4 (نقطة PDF) — ورقٌ مطبوع خارج توكنات الواجهة.
const double _cardRadius = 8;

/// زوايا ختم «مُلغاة» وإطار الملاحظة في فاتورة البيع (نقطة PDF).
const double _stampRadius = 4;

class _Body {
  _Body(this.d, {required this.logo, required this.a4, required this.width});

  final ReceiptDoc d;
  final pw.MemoryImage? logo;
  final bool a4;

  /// عرض المحتوى بين الحاشيتين (نقطة PDF) — الشعار ورمز QR لا يتجاوزانه.
  final double width;

  // الكاشير أسود (الحراريّة لا تطبع لوناً)؛ A4 بلون المصمّم.
  PdfColor get _accent => !a4
      ? PdfColors.black
      : (d.look.accent != null ? PdfColor.fromInt(d.look.accent!) : const PdfColor.fromInt(0xFF0D9488));
  PdfColor get _muted => a4 ? PdfColors.grey700 : PdfColors.black;

  // أحجام وصل الموقع (`print-receipt.ts`) من مصمّمه، بنقاط PDF (بكسل الشاشة × ٠٫٧٥): القيمة ٠٫٩٥ من الخطّ
  // الأساسيّ، التسمية وعناوين الأقسام والرقم والوقت ٠٫٨٥، الحاشية ٠٫٧٨، اسم المحلّ خطّ العنوان ونوع الوصل ٠٫٨ منه،
  // والمسافة بين الأقسام والشعار وQR بالملّيمتر. A4 كما كان.
  static double _pt(num px) => px * 0.75;
  ReceiptSettings get _look => d.look;
  double get _value => a4 ? 11 : _pt((_look.fontBasePx * 0.95).round());
  double get _label => a4 ? 11 : _pt((_look.fontBasePx * 0.85).round());
  double get _small => a4 ? 9.5 : _pt((_look.fontBasePx * 0.78).round());
  double get _metaSize => a4 ? _small : _label;
  double get _gap => a4 ? 10 : _look.sectionGapMm * PdfPageFormat.mm;

  /// حشوة الصفّ (الموقع: ‎5px‎ للكاشير).
  double get _rowPad => a4 ? 3 : 3.75;

  static String _p(String s) => ReceiptPdf.plain(s);

  pw.Widget build() {
    final look = d.look;
    final rows = d.transactionRows;
    final body = pw.Column(
      mainAxisSize: pw.MainAxisSize.min,
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        if (logo != null) ...[
          pw.Center(
            child: a4
                ? pw.Image(logo!, height: 56, fit: pw.BoxFit.contain)
                // الموقع: ارتفاعٌ أقصى من المصمّم وعرضٌ أقصى ضعفاه ونصف.
                : pw.Image(
                    logo!,
                    height: _look.logoSizeMm * PdfPageFormat.mm,
                    width: math.min(width, _look.logoSizeMm * 2.5 * PdfPageFormat.mm),
                    fit: pw.BoxFit.contain,
                  ),
          ),
          pw.SizedBox(height: a4 ? 4 : 6),
        ],
        pw.Text(
          _p(d.shopName),
          textAlign: pw.TextAlign.center,
          style: pw.TextStyle(
              fontSize: a4 ? 19 : _pt(_look.fontTitlePx), fontWeight: pw.FontWeight.bold, color: _accent),
        ),
        if (look.showShopInfo) ..._shopMeta(),
        pw.SizedBox(height: a4 ? _gap * 0.8 : _gap),
        _title(),
        if ((look.showReceiptId && d.sale == null) || look.showDateTime) ...[
          pw.SizedBox(height: a4 ? 4 : _gap),
          _meta(),
        ],
        if (d.sale != null) ..._saleSections() else ...[
        if (look.showSubscriberInfo)
          _section('المشترك', [
            _row('الاسم', d.subscriberName, bold: true),
            _row('اسم المستخدم', d.username, ltr: true),
            if ((d.phone ?? '').trim().isNotEmpty) _row('الهاتف', d.phone!.trim(), ltr: true),
          ]),
        if (look.showPackageInfo)
          _section('الباقة', [
            _row('الباقة', (d.packageName ?? '').trim().isEmpty ? '—' : d.packageName!.trim(), bold: true),
            if (look.showPackagePrice && (d.packagePrice ?? 0) > 0)
              _row('سعر الباقة', ReceiptPdf.money(d.packagePrice!), bold: true),
            if ((d.expiration ?? '').trim().isNotEmpty)
              _row('تاريخ الانتهاء', ReceiptPdf.expiry(d.expiration!.trim()), ltr: true),
            if (d.remainingDays != null) _row('الأيام المتبقّية', '${d.remainingDays} يوم', bold: true),
          ]),
        if (look.showTransactionInfo && rows.isNotEmpty)
          _section('المعاملة', [
            for (final (label, value, balance) in rows)
              _row(label, value, bold: true, balance: balance),
          ]),
        if (d.qrUrl != null) _qr(),
        ],
        if (look.showFooter) _footer(),
      ],
    );
    if (!a4) return body;
    // A4: الوصل بطاقةٌ في أعلى الصفحة بعرضٍ مريح للقراءة، لا جدولٌ يملأ الورقة.
    return pw.Align(
      alignment: pw.Alignment.topCenter,
      child: pw.Container(
        width: 400,
        padding: const pw.EdgeInsets.all(22),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.grey400, width: 0.8, style: pw.BorderStyle.dashed),
          borderRadius: pw.BorderRadius.circular(_cardRadius),
        ),
        child: body,
      ),
    );
  }

  List<pw.Widget> _shopMeta() => [
        if ((d.look.shopAddress ?? '').trim().isNotEmpty)
          pw.Text(_p(d.look.shopAddress!.trim()),
              textAlign: pw.TextAlign.center, style: pw.TextStyle(fontSize: _small, color: _muted)),
        if ((d.look.shopPhone ?? '').trim().isNotEmpty)
          pw.Text(d.look.shopPhone!.trim(),
              textAlign: pw.TextAlign.center,
              textDirection: pw.TextDirection.ltr,
              style: pw.TextStyle(fontSize: _small, color: _muted)),
      ];

  pw.Widget _title() => pw.Container(
        padding: pw.EdgeInsets.symmetric(vertical: a4 ? 5 : 3),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: _accent, width: a4 ? 1 : 0.8),
          borderRadius: pw.BorderRadius.circular(a4 ? 6 : 4),
        ),
        child: pw.Text(
          _p(d.title),
          textAlign: pw.TextAlign.center,
          style: pw.TextStyle(
              fontSize: a4 ? 14 : _pt((_look.fontTitlePx * 0.8).round()),
              fontWeight: pw.FontWeight.bold,
              color: _accent),
        ),
      );

  pw.Widget _meta() {
    final style = pw.TextStyle(fontSize: _metaSize, color: _muted);
    return pw.Row(
      mainAxisAlignment: d.look.showReceiptId && d.sale == null && d.look.showDateTime
          ? pw.MainAxisAlignment.spaceBetween
          : pw.MainAxisAlignment.center,
      children: [
        // الفاتورة رقمها في عنوانها.
        if (d.look.showReceiptId && d.sale == null)
          pw.Text('#${d.receiptId}', textDirection: pw.TextDirection.ltr, style: style),
        if (d.look.showDateTime) pw.Text(d.issuedText, textDirection: pw.TextDirection.ltr, style: style),
      ],
    );
  }

  /// الفاتورة: «مُلغاة» إن أُلغيت، والزبون، والموادّ، والمجموع وطريقة الدفع (دائماً — فاتورةٌ بلاهما لا تُقرأ)، والملاحظة.
  List<pw.Widget> _saleSections() {
    final s = d.sale!;
    final red = a4 ? const PdfColor.fromInt(0xFFB00020) : PdfColors.black;
    final reason = (s.voidReason ?? '').trim();
    final note = (s.note ?? '').trim();
    return [
      if (s.voided)
        pw.Padding(
          padding: pw.EdgeInsets.only(top: _gap),
          child: pw.Container(
            padding: const pw.EdgeInsets.all(4),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: red, width: 1.4),
              borderRadius: pw.BorderRadius.circular(_stampRadius),
            ),
            child: pw.Text(
              _p(reason.isEmpty ? 'مُلغاة' : 'مُلغاة — $reason'),
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(fontSize: _value, fontWeight: pw.FontWeight.bold, color: red),
            ),
          ),
        ),
      if (d.look.showSubscriberInfo)
        _section('الزبون', [
          _row('الاسم', d.subscriberName, bold: true),
          if (d.username.trim().isNotEmpty) _row('اسم المستخدم', d.username.trim(), ltr: true),
          if ((d.phone ?? '').trim().isNotEmpty) _row('الهاتف', d.phone!.trim(), ltr: true),
        ]),
      _section('المواد', [for (final l in s.lines) _itemRow(l)]),
      _section('المعاملة', [
        _row('المجموع', ReceiptPdf.money(s.total), bold: true),
        _row('طريقة الدفع', s.debt ? 'على حساب المشترك (دين)' : 'نقداً', bold: true),
      ]),
      if (note.isNotEmpty)
        pw.Padding(
          padding: pw.EdgeInsets.only(top: _gap),
          child: pw.Container(
            padding: const pw.EdgeInsets.all(4),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.grey500, width: 0.6, style: pw.BorderStyle.dashed),
              borderRadius: pw.BorderRadius.circular(_stampRadius),
            ),
            child: pw.Text(_p('ملاحظة: $note'), style: pw.TextStyle(fontSize: _small + 0.5)),
          ),
        ),
    ];
  }

  /// مادّة: اسمها وتحته «الكمّيّة × سعر الوحدة» يميناً، ومجموعها يساراً.
  pw.Widget _itemRow(({String name, String qty, num unitPrice, num total}) l) => pw.Padding(
        padding: pw.EdgeInsets.symmetric(vertical: _rowPad),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(_p(l.name), style: pw.TextStyle(fontSize: _value, fontWeight: pw.FontWeight.bold)),
                  pw.Text(_p('${l.qty} × ${ReceiptPdf.money(l.unitPrice)}'),
                      style: pw.TextStyle(fontSize: _small, color: _muted)),
                ],
              ),
            ),
            pw.SizedBox(width: 8),
            pw.Text(_p(ReceiptPdf.money(l.total)), style: pw.TextStyle(fontSize: _value, fontWeight: pw.FontWeight.bold)),
          ],
        ),
      );

  pw.Widget _section(String title, List<pw.Widget> rows) => pw.Padding(
        padding: pw.EdgeInsets.only(top: _gap),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Container(
              padding: const pw.EdgeInsets.only(bottom: 2),
              margin: const pw.EdgeInsets.only(bottom: 2),
              decoration: pw.BoxDecoration(
                border: pw.Border(bottom: pw.BorderSide(color: _accent, width: 0.8)),
              ),
              child: pw.Text(_p(title),
                  style: pw.TextStyle(fontSize: _label, fontWeight: pw.FontWeight.bold, color: _accent)),
            ),
            for (var i = 0; i < rows.length; i++)
              pw.Container(
                decoration: i == rows.length - 1
                    ? null
                    : const pw.BoxDecoration(
                        border: pw.Border(
                          bottom: pw.BorderSide(color: PdfColors.grey500, width: 0.5, style: pw.BorderStyle.dotted),
                        ),
                      ),
                child: rows[i],
              ),
          ],
        ),
      );

  /// التسمية يميناً والقيمة يساراً. [balance] يلوّن الرصيد في A4 (دين أحمر، رصيد أخضر).
  pw.Widget _row(String label, String value, {bool bold = false, bool ltr = false, num? balance}) {
    var color = PdfColors.black;
    if (a4 && balance != null && balance != 0) {
      color = balance < 0 ? const PdfColor.fromInt(0xFFDC2626) : const PdfColor.fromInt(0xFF059669);
    }
    return pw.Padding(
      padding: pw.EdgeInsets.symmetric(vertical: _rowPad),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(_p(label), style: pw.TextStyle(fontSize: _label, color: _muted)),
          pw.SizedBox(width: 8),
          pw.Expanded(
            child: pw.Text(
              _p(value),
              textAlign: pw.TextAlign.left,
              textDirection: ltr ? pw.TextDirection.ltr : null,
              style: pw.TextStyle(
                fontSize: _value,
                color: color,
                fontWeight: bold || balance != null ? pw.FontWeight.bold : pw.FontWeight.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _qr() {
    final size = a4 ? 30 * PdfPageFormat.mm : math.min(width, _look.qrSizeMm * PdfPageFormat.mm);
    return pw.Padding(
      padding: pw.EdgeInsets.only(top: _gap),
      child: pw.Column(
        children: [
          pw.BarcodeWidget(
            barcode: pw.Barcode.qrCode(errorCorrectLevel: pw.BarcodeQRCorrectionLevel.medium),
            data: d.qrUrl!,
            width: size,
            height: size,
            drawText: false,
          ),
          pw.SizedBox(height: 3),
          pw.Text(_p('امسح للاطلاع على معلومات الاشتراك'),
              textAlign: pw.TextAlign.center, style: pw.TextStyle(fontSize: _small, color: _muted)),
        ],
      ),
    );
  }

  pw.Widget _footer() {
    final issuer = (d.issuer ?? '').trim();
    final note = (d.look.footerText ?? '').trim();
    return pw.Padding(
      padding: pw.EdgeInsets.only(top: _gap),
      child: pw.Container(
        // الموقع: ‎8px‎ تحت خطّ الذيل.
        padding: pw.EdgeInsets.only(top: a4 ? _gap * 0.7 : 6),
        decoration: const pw.BoxDecoration(
          border: pw.Border(top: pw.BorderSide(color: PdfColors.grey500, width: 0.6, style: pw.BorderStyle.dashed)),
        ),
        child: pw.Column(
          children: [
            if (d.look.showSignature && issuer.isNotEmpty)
              pw.Text(_p('أصدره: $issuer'),
                  textAlign: pw.TextAlign.center, style: pw.TextStyle(fontSize: _small, color: _muted)),
            pw.Text(_p(note.isEmpty ? 'شكراً لاختياركم خدماتنا' : note),
                textAlign: pw.TextAlign.center, style: pw.TextStyle(fontSize: _small + 0.5)),
          ],
        ),
      ),
    );
  }
}
