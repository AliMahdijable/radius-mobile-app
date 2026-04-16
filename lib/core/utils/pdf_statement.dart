import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:printing/printing.dart';
import 'helpers.dart';

class PdfStatement {
  static pw.Font? _cairoFont;
  static pw.Font? _cairoBold;

  static Future<void> _loadFonts() async {
    if (_cairoFont != null) return;
    final fontData = await rootBundle.load('assets/fonts/Cairo-Variable.ttf');
    _cairoFont = pw.Font.ttf(fontData);
    _cairoBold = pw.Font.ttf(fontData);
  }

  static Future<Uint8List> buildPdfBytes({
    required String username,
    required String phone,
    required String profileName,
    required String dateFrom,
    required String dateTo,
    required List<Map<String, dynamic>> transactions,
    required Map<String, dynamic> summary,
  }) async {
    await _loadFonts();

    final pdf = pw.Document();
    final baseStyle = pw.TextStyle(font: _cairoFont, fontSize: 10);
    final boldStyle = pw.TextStyle(font: _cairoBold, fontSize: 10, fontWeight: pw.FontWeight.bold);
    final headerStyle = pw.TextStyle(font: _cairoBold, fontSize: 16, fontWeight: pw.FontWeight.bold,
        color: PdfColor.fromHex('#1a7f64'));
    final subStyle = pw.TextStyle(font: _cairoFont, fontSize: 9, color: PdfColors.grey700);

    final totalTxn = _toInt(summary['totalTransactions']);
    final totalDebt = _toDouble(summary['totalDebt']);
    final totalPayments = _toDouble(summary['totalPayments']);
    final totalActivations = _toInt(summary['totalActivations']);

    final rows = transactions.map((t) {
      final type = (t['action_type'] ?? '').toString().toUpperCase();
      final amount = _toDouble(t['amount']).abs();
      final isDebt = type == 'BALANCE_ADD' ||
          (type == 'SUBSCRIBER_ACTIVATE' &&
              (t['description'] ?? t['action_description'] ?? '')
                  .toString()
                  .toLowerCase()
                  .contains('غير نقدي'));
      final time = t['created_at']?.toString() ?? '';
      final dt = DateTime.tryParse(time);
      final fDate = dt != null ? '${dt.day}/${dt.month}/${dt.year}' : time;
      final fTime = dt != null
          ? '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}'
          : '';

      return _TxnRow(
        date: fDate,
        time: fTime,
        type: _typeLabel(type),
        desc: t['description']?.toString() ?? t['action_description']?.toString() ?? '',
        amount: '${isDebt ? "-" : "+"}${AppHelpers.formatMoney(amount)}',
        admin: t['admin_name']?.toString() ?? '',
        isDebt: isDebt,
      );
    }).toList();

    const maxPerPage = 25;
    final pageCount = (rows.length / maxPerPage).ceil().clamp(1, 999);

    for (int p = 0; p < pageCount; p++) {
      final pageRows = rows.skip(p * maxPerPage).take(maxPerPage).toList();
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          textDirection: pw.TextDirection.rtl,
          margin: const pw.EdgeInsets.all(30),
          build: (context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                // Header
                if (p == 0) ...[
                  pw.Center(child: pw.Text('كشف حساب المشترك', style: headerStyle,
                      textDirection: pw.TextDirection.rtl)),
                  pw.SizedBox(height: 4),
                  pw.Center(child: pw.Text('الفترة: $dateFrom — $dateTo', style: subStyle,
                      textDirection: pw.TextDirection.rtl)),
                  pw.SizedBox(height: 12),

                  // Subscriber info
                  pw.Container(
                    padding: const pw.EdgeInsets.all(10),
                    decoration: pw.BoxDecoration(
                      color: PdfColor.fromHex('#f0fdf4'),
                      borderRadius: pw.BorderRadius.circular(6),
                      border: pw.Border.all(color: PdfColor.fromHex('#bbf7d0')),
                    ),
                    child: pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
                      children: [
                        _infoCol('الباقة', profileName.isNotEmpty ? profileName : '—', baseStyle, subStyle),
                        _infoCol('الهاتف', phone.isNotEmpty ? phone : '—', baseStyle, subStyle),
                        _infoCol('المشترك', username, boldStyle, subStyle),
                      ],
                    ),
                  ),
                  pw.SizedBox(height: 10),

                  // Summary
                  pw.Row(children: [
                    _summaryBox('العمليات', '$totalTxn', PdfColor.fromHex('#3b82f6'), baseStyle, boldStyle),
                    pw.SizedBox(width: 8),
                    _summaryBox('الديون', AppHelpers.formatMoney(totalDebt), PdfColor.fromHex('#ef4444'), baseStyle, boldStyle),
                    pw.SizedBox(width: 8),
                    _summaryBox('المدفوعات', AppHelpers.formatMoney(totalPayments), PdfColor.fromHex('#22c55e'), baseStyle, boldStyle),
                    pw.SizedBox(width: 8),
                    _summaryBox('التفعيلات', '$totalActivations', PdfColor.fromHex('#f59e0b'), baseStyle, boldStyle),
                  ]),
                  pw.SizedBox(height: 12),
                ],

                if (p > 0)
                  pw.Padding(
                    padding: const pw.EdgeInsets.only(bottom: 8),
                    child: pw.Text('كشف حساب: $username — صفحة ${p + 1}',
                        style: subStyle, textDirection: pw.TextDirection.rtl),
                  ),

                // Table
                pw.Table(
                  border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
                  columnWidths: {
                    0: const pw.FlexColumnWidth(1.2),
                    1: const pw.FlexColumnWidth(0.7),
                    2: const pw.FlexColumnWidth(1),
                    3: const pw.FlexColumnWidth(2.5),
                    4: const pw.FlexColumnWidth(1.2),
                    5: const pw.FlexColumnWidth(1),
                  },
                  children: [
                    pw.TableRow(
                      decoration: pw.BoxDecoration(color: PdfColor.fromHex('#1a7f64')),
                      children: ['التاريخ', 'الوقت', 'النوع', 'التفاصيل', 'المبلغ', 'المنفذ']
                          .map((h) => pw.Container(
                                padding: const pw.EdgeInsets.symmetric(vertical: 5, horizontal: 4),
                                child: pw.Text(h,
                                    style: pw.TextStyle(font: _cairoBold, fontSize: 8,
                                        color: PdfColors.white, fontWeight: pw.FontWeight.bold),
                                    textDirection: pw.TextDirection.rtl,
                                    textAlign: pw.TextAlign.center),
                              ))
                          .toList(),
                    ),
                    ...pageRows.asMap().entries.map((e) {
                      final i = e.key;
                      final r = e.value;
                      final bg = i % 2 == 0 ? PdfColors.white : PdfColor.fromHex('#f8fafc');
                      final amtColor = r.isDebt ? PdfColor.fromHex('#dc2626') : PdfColor.fromHex('#16a34a');
                      return pw.TableRow(
                        decoration: pw.BoxDecoration(color: bg),
                        children: [
                          _cell(r.date, baseStyle),
                          _cell(r.time, baseStyle),
                          _cell(r.type, baseStyle),
                          _cell(r.desc, pw.TextStyle(font: _cairoFont, fontSize: 8), maxLines: 2),
                          _cell(r.amount, pw.TextStyle(font: _cairoBold, fontSize: 9,
                              color: amtColor, fontWeight: pw.FontWeight.bold)),
                          _cell(r.admin, pw.TextStyle(font: _cairoFont, fontSize: 8)),
                        ],
                      );
                    }),
                  ],
                ),

                pw.Spacer(),
                pw.Divider(color: PdfColors.grey300),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('صفحة ${p + 1} / $pageCount', style: subStyle, textDirection: pw.TextDirection.rtl),
                    pw.Text('نظام إدارة المشتركين — MyServices', style: subStyle, textDirection: pw.TextDirection.rtl),
                  ],
                ),
              ],
            );
          },
        ),
      );
    }

    return await pdf.save();
  }

  static Future<void> generateAndShare({
    required String username,
    required String phone,
    required String profileName,
    required String dateFrom,
    required String dateTo,
    required List<Map<String, dynamic>> transactions,
    required Map<String, dynamic> summary,
  }) async {
    final bytes = await buildPdfBytes(
      username: username, phone: phone, profileName: profileName,
      dateFrom: dateFrom, dateTo: dateTo,
      transactions: transactions, summary: summary,
    );
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/account-statement-$username.pdf');
    await file.writeAsBytes(bytes);

    // ignore: deprecated_member_use
    await Share.shareXFiles(
      [XFile(file.path)],
      text: '📋 كشف حساب المشترك: $username\n📅 الفترة: $dateFrom — $dateTo',
    );
  }

  static String formatPhoneForWa(String phone) {
    String cleaned = phone.replaceAll(RegExp(r'[\s\-\(\)\+]'), '');
    if (cleaned.startsWith('07')) return '964${cleaned.substring(1)}';
    if (cleaned.startsWith('7') && cleaned.length == 10) return '964$cleaned';
    return cleaned;
  }

  static Future<void> printStatement({
    required String username,
    required String phone,
    required String profileName,
    required String dateFrom,
    required String dateTo,
    required List<Map<String, dynamic>> transactions,
    required Map<String, dynamic> summary,
  }) async {
    final bytes = await buildPdfBytes(
      username: username, phone: phone, profileName: profileName,
      dateFrom: dateFrom, dateTo: dateTo,
      transactions: transactions, summary: summary,
    );
    await Printing.layoutPdf(onLayout: (_) async => bytes);
  }

  static pw.Widget _infoCol(String label, String value, pw.TextStyle valStyle, pw.TextStyle lblStyle) {
    return pw.Column(children: [
      pw.Text(value, style: valStyle, textDirection: pw.TextDirection.rtl),
      pw.SizedBox(height: 2),
      pw.Text(label, style: lblStyle, textDirection: pw.TextDirection.rtl),
    ]);
  }

  static pw.Expanded _summaryBox(String label, String value, PdfColor color,
      pw.TextStyle baseStyle, pw.TextStyle boldStyle) {
    return pw.Expanded(
      child: pw.Container(
        padding: const pw.EdgeInsets.symmetric(vertical: 8, horizontal: 6),
        decoration: pw.BoxDecoration(
          color: color,
          borderRadius: pw.BorderRadius.circular(6),
        ),
        child: pw.Column(children: [
          pw.Text(value, style: pw.TextStyle(font: _cairoBold, fontSize: 11,
              color: PdfColors.white, fontWeight: pw.FontWeight.bold),
              textDirection: pw.TextDirection.rtl),
          pw.SizedBox(height: 2),
          pw.Text(label, style: pw.TextStyle(font: _cairoFont, fontSize: 8,
              color: PdfColor(1, 1, 1, 0.85)),
              textDirection: pw.TextDirection.rtl),
        ]),
      ),
    );
  }

  static pw.Widget _cell(String text, pw.TextStyle style, {int maxLines = 1}) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 4),
      child: pw.Text(text, style: style, textDirection: pw.TextDirection.rtl,
          maxLines: maxLines, overflow: pw.TextOverflow.clip),
    );
  }

  static String _typeLabel(String type) {
    switch (type) {
      case 'SUBSCRIBER_ACTIVATE': return 'تفعيل';
      case 'SUBSCRIBER_EXTEND': return 'تمديد';
      case 'BALANCE_DEDUCT': return 'تسديد دين';
      case 'BALANCE_ADD': return 'إضافة دين';
      case 'DEBT_PAY': return 'تسديد دين';
      default: return type;
    }
  }

  static double _toDouble(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0;
    return 0;
  }

  static int _toInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }
}

class _TxnRow {
  final String date, time, type, desc, amount, admin;
  final bool isDebt;
  const _TxnRow({required this.date, required this.time, required this.type,
      required this.desc, required this.amount, required this.admin, required this.isDebt});
}
