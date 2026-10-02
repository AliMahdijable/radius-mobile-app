import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../api/settlements_api.dart';
import '../core/util/format.dart';
import 'auth_storage.dart';
import 'print_prefs.dart';
import 'print_service.dart';

/// سند «تسوية الحساب» المطبوع — PDF مبنيّ مباشرةً بعناصر `pw` كالوصل
/// (انظر [PrintService]: WebView يتعطّل على بعض الأجهزة). الورق من
/// تفضيل الطباعة نفسه (حراري 80mm أو A4)، والخطّ خطّ التطبيق.
class SettlementPrint {
  SettlementPrint._();

  static Future<bool> printVoucher(SettlementRecord s) async {
    try {
      final format = PrintService.formatForType(PrintPrefs.currentTemplateType);
      final company = await AuthStorage.readDisplayName();
      final manager = await AuthStorage.readAdminUsername();
      return await Printing.layoutPdf(
        name: s.isOpening ? 'Account-Opening' : 'Settlement-${s.number}',
        format: format,
        onLayout: (fmt) => _build(s, fmt, company: company, manager: manager),
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[SettlementPrint] failed: $e');
      return false;
    }
  }

  static String _money(num n) => '${n < 0 ? '−' : ''}${formatIQD(n)} د.ع';

  static String _when(DateTime? d) {
    if (d == null) return '—';
    final l = d.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${l.year}-${two(l.month)}-${two(l.day)} ${two(l.hour)}:${two(l.minute)}';
  }

  static Future<Uint8List> _build(
    SettlementRecord s,
    PdfPageFormat format, {
    String? company,
    String? manager,
  }) async {
    pw.Font? regular;
    pw.Font? bold;
    try {
      regular = await PdfGoogleFonts.iBMPlexSansArabicRegular();
      bold = await PdfGoogleFonts.iBMPlexSansArabicBold();
    } catch (e) {
      if (kDebugMode) debugPrint('[SettlementPrint] font fetch failed: $e');
    }
    final doc = pw.Document(
      theme: pw.ThemeData.withFont(
        base: regular ?? pw.Font.helvetica(),
        bold: bold ?? pw.Font.helveticaBold(),
      ),
    );
    final pos = format.width <= PdfPageFormat.roll80.width + 5;
    final size = pos ? 9.5 : 11.0;
    final titleSize = pos ? 12.5 : 16.0;
    final employees = s.collectors.where((c) => !c.isManager).isNotEmpty;

    pw.Widget row(String label, String value, {bool strong = false}) {
      final style = pw.TextStyle(
        fontSize: size,
        fontWeight: strong ? pw.FontWeight.bold : pw.FontWeight.normal,
      );
      return pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 2),
        child: pw.Row(
          children: [
            pw.Expanded(child: pw.Text(label, style: style)),
            pw.SizedBox(width: 8),
            pw.Text(value, style: style, textDirection: pw.TextDirection.ltr),
          ],
        ),
      );
    }

    final children = <pw.Widget>[
      if ((company ?? '').trim().isNotEmpty)
        pw.Center(
          child: pw.Text(
            company!.trim(),
            style: pw.TextStyle(fontSize: size + 2, fontWeight: pw.FontWeight.bold),
          ),
        ),
      pw.SizedBox(height: 4),
      pw.Center(
        child: pw.Text(
          s.isOpening ? 'بداية حساب الصندوق' : 'سند تسوية حساب رقم ${s.number}',
          style: pw.TextStyle(fontSize: titleSize, fontWeight: pw.FontWeight.bold),
        ),
      ),
      if (s.isVoided) ...[
        pw.SizedBox(height: 4),
        pw.Container(
          padding: const pw.EdgeInsets.all(4),
          decoration: pw.BoxDecoration(border: pw.Border.all(width: 1.2)),
          child: pw.Center(
            child: pw.Text(
              'ملغاة — ${s.voidReason ?? ''}',
              style: pw.TextStyle(fontSize: size, fontWeight: pw.FontWeight.bold),
            ),
          ),
        ),
      ],
      pw.SizedBox(height: 6),
      pw.Divider(thickness: 0.8),
      if ((manager ?? '').isNotEmpty) row('المدير', manager!),
      if (!s.isOpening) row('من', _when(s.periodStartAt)),
      row(s.isOpening ? 'يبدأ من' : 'إلى', _when(s.cutAt)),
      if ((s.actingEmployeeUsername ?? '').isNotEmpty)
        row('نفّذها', s.actingEmployeeUsername!),
      pw.Divider(thickness: 0.8),
      if (s.isOpening)
        row('الرصيد الافتتاحيّ', _money(s.openingBalance), strong: true)
      else ...[
        if (s.openingBalance != 0) row('رصيد مدوَّر', _money(s.openingBalance)),
        row('+ تفعيلات نقديّة (${s.cashActivations.count})', _money(s.cashActivations.sum)),
        row('+ تسديد ديون (${s.debtPayments.count})', _money(s.debtPayments.sum)),
        row('− صرفيات (${s.expenses.count})', _money(s.expenses.sum)),
        pw.Divider(thickness: 0.8),
        row('المتوقّع في الصندوق', _money(s.expected), strong: true),
        row('المستلَم فعلاً', _money(s.received), strong: true),
        row('المُرحَّل للفترة التالية', _money(s.carried)),
      ],
      if (!s.isOpening && employees) ...[
        pw.SizedBox(height: 6),
        pw.Text(
          'حصّة المنفّذين',
          style: pw.TextStyle(fontSize: size, fontWeight: pw.FontWeight.bold),
        ),
        for (final c in s.collectors)
          row(
            c.isManager ? 'المدير' : (c.name ?? c.username ?? '#${c.employeeId}'),
            _money(c.net),
          ),
      ],
      if (!s.isOpening && s.newDebts.sum > 0) ...[
        pw.SizedBox(height: 6),
        pw.Text(
          'ديون جديدة على المشتركين خلال الفترة (لا تدخل الصندوق): ${_money(s.newDebts.sum)}',
          style: pw.TextStyle(fontSize: size),
        ),
      ],
      if ((s.note ?? '').isNotEmpty) ...[
        pw.SizedBox(height: 6),
        pw.Text('ملاحظة: ${s.note}', style: pw.TextStyle(fontSize: size)),
      ],
      if (!s.isOpening) ...[
        pw.SizedBox(height: pos ? 18 : 36),
        pw.Row(
          children: [
            pw.Expanded(child: _signature('المسلِّم', size)),
            pw.SizedBox(width: 12),
            pw.Expanded(child: _signature('المستلِم', size)),
          ],
        ),
      ],
      pw.SizedBox(height: 10),
      pw.Center(
        child: pw.Text('طُبع ${_when(DateTime.now())}', style: pw.TextStyle(fontSize: size)),
      ),
    ];

    doc.addPage(
      pw.Page(
        pageFormat: format,
        margin: pos
            ? const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 12)
            : const pw.EdgeInsets.all(32),
        textDirection: pw.TextDirection.rtl,
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    );
    return doc.save();
  }

  static pw.Widget _signature(String label, double size) => pw.Column(
        children: [
          pw.SizedBox(height: 22),
          pw.Divider(thickness: 0.8),
          pw.Text(label, style: pw.TextStyle(fontSize: size)),
        ],
      );
}
