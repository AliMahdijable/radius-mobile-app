import 'package:flutter/foundation.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../api/sales_api.dart';
import '../core/util/format.dart';
import 'auth_storage.dart';
import 'print_output.dart';
import 'print_prefs.dart';

/// وصل البيع (قسم «المبيعات») — PDF مبنيّ مباشرةً بعناصر `pw` كسند التسوية ([SettlementPrint]): الورق من تفضيل الطباعة
/// نفسه (حراري 80mm أو A4)، والخطّ خطّ التطبيق، واسم الشركة من الجلسة. المُلغى يُطبع بختم «مُلغى» وسببه.
class SalePrint {
  SalePrint._();

  static Future<PrintResult> printReceipt(Sale s) async {
    try {
      final format = PrintPrefs.pageFormat;
      final company = await AuthStorage.readDisplayName();
      final doc = await document(s, format, company: company);
      return PrintOutput.send(await PrintDoc.of(doc, name: 'Sale-${s.id}', requested: format));
    } catch (e) {
      if (kDebugMode) debugPrint('[SalePrint] failed: $e');
      return PrintResult.failed('$e');
    }
  }

  static String _money(num n) => '${formatIQD(n)} د.ع';

  static String _qty(num q) {
    if (q == q.roundToDouble()) return q.round().toString();
    var s = q.toStringAsFixed(3);
    while (s.endsWith('0')) {
      s = s.substring(0, s.length - 1);
    }
    return s.endsWith('.') ? s.substring(0, s.length - 1) : s;
  }

  static String _when(DateTime? d) {
    if (d == null) return '—';
    final l = d.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${l.year}-${two(l.month)}-${two(l.day)} ${two(l.hour)}:${two(l.minute)}';
  }

  static String customerOf(Sale s) {
    if (s.customerKind == 'subscriber') {
      final parts = [s.customerName, s.username].whereType<String>().where((x) => x.trim().isNotEmpty).toList();
      return parts.isEmpty ? 'مشترك' : parts.join(' — ');
    }
    final n = (s.customerName ?? '').trim();
    return n.isEmpty ? 'زبون' : n;
  }

  /// يُبنى منفصلاً عن الطابعة (يُختبر وحده). [fonts] = false في الاختبار: Helvetica بلا تحميل خطّ.
  @visibleForTesting
  static Future<Uint8List> build(Sale s, PdfPageFormat format, {String? company, bool fonts = true, DateTime? printedAt}) async =>
      (await document(s, format, company: company, fonts: fonts, printedAt: printedAt)).save();

  static Future<pw.Document> document(Sale s, PdfPageFormat format, {String? company, bool fonts = true, DateTime? printedAt}) async {
    final doc = pw.Document(
      theme: fonts
          ? await PdfFonts.theme()
          : pw.ThemeData.withFont(base: pw.Font.helvetica(), bold: pw.Font.helveticaBold()),
    );
    final pos = format.width <= PdfPageFormat.roll80.width + 5;
    final size = pos ? 9.5 : 11.0;
    final titleSize = pos ? 12.5 : 16.0;

    pw.Widget row(String label, String value, {bool strong = false, bool ltr = true}) {
      final style = pw.TextStyle(fontSize: size, fontWeight: strong ? pw.FontWeight.bold : pw.FontWeight.normal);
      return pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 2),
        child: pw.Row(
          children: [
            pw.Expanded(child: pw.Text(label, style: style)),
            pw.SizedBox(width: 8),
            pw.Text(value, style: style, textDirection: ltr ? pw.TextDirection.ltr : pw.TextDirection.rtl),
          ],
        ),
      );
    }

    final children = <pw.Widget>[
      if ((company ?? '').trim().isNotEmpty)
        pw.Center(
          child: pw.Text(company!.trim(), style: pw.TextStyle(fontSize: size + 2, fontWeight: pw.FontWeight.bold)),
        ),
      pw.SizedBox(height: 4),
      pw.Center(
        child: pw.Text('وصل بيع رقم ${s.id}', style: pw.TextStyle(fontSize: titleSize, fontWeight: pw.FontWeight.bold)),
      ),
      if (s.isVoid) ...[
        pw.SizedBox(height: 4),
        pw.Container(
          padding: const pw.EdgeInsets.all(4),
          decoration: pw.BoxDecoration(border: pw.Border.all(width: 1.2)),
          child: pw.Center(
            child: pw.Text(
              'مُلغى${(s.voidReason ?? '').isNotEmpty ? ' — ${s.voidReason}' : ''}',
              style: pw.TextStyle(fontSize: size, fontWeight: pw.FontWeight.bold),
            ),
          ),
        ),
      ],
      pw.SizedBox(height: 6),
      pw.Divider(thickness: 0.8),
      row('التاريخ', _when(s.createdAt)),
      row('الزبون', customerOf(s), ltr: false),
      if ((s.phone ?? '').isNotEmpty) row('الهاتف', s.phone!),
      if (s.employeeId != null && (s.by ?? '').isNotEmpty) row('البائع', s.by!),
      pw.Divider(thickness: 0.8),
      for (final l in s.lines)
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 2),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(l.name, style: pw.TextStyle(fontSize: size, fontWeight: pw.FontWeight.bold)),
                    pw.Text('${_qty(l.qty)} ${saleUnitLabel(l.unit)} × ${formatIQD(l.unitPrice)}', style: pw.TextStyle(fontSize: size - 0.5)),
                  ],
                ),
              ),
              pw.SizedBox(width: 8),
              pw.Text(formatIQD(l.total), style: pw.TextStyle(fontSize: size, fontWeight: pw.FontWeight.bold), textDirection: pw.TextDirection.ltr),
            ],
          ),
        ),
      pw.Divider(thickness: 1.2),
      row('المجموع', _money(s.total), strong: true),
      pw.SizedBox(height: 4),
      pw.Center(
        child: pw.Text(
          s.isDebt ? 'على حساب المشترك (دين)' : 'مدفوع نقداً',
          style: pw.TextStyle(fontSize: size, fontWeight: pw.FontWeight.bold),
        ),
      ),
      if ((s.note ?? '').isNotEmpty) ...[
        pw.SizedBox(height: 6),
        pw.Text('ملاحظة: ${s.note}', style: pw.TextStyle(fontSize: size)),
      ],
      pw.SizedBox(height: 10),
      pw.Center(child: pw.Text('شكراً لكم — طُبع ${_when(printedAt ?? DateTime.now())}', style: pw.TextStyle(fontSize: size - 0.5))),
    ];

    doc.addPage(
      pw.Page(
        pageFormat: format,
        // الكاشير: ٤٫٥ ملم جانباً — حواشي الطابعة الحراريّة لا تُطبع.
        margin: pos ? const pw.EdgeInsets.symmetric(horizontal: 12.75, vertical: 12) : const pw.EdgeInsets.all(32),
        textDirection: pw.TextDirection.rtl,
        build: (context) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: children),
      ),
    );
    return doc;
  }
}
