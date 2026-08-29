import 'dart:io';

import 'package:csv/csv.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';

/// ================================================================
/// Report export — CSV/Excel + PDF/Print للتقارير.
///
/// النمط: كل شاشة تقرير تُعطي:
///   * عنوان (للـPDF)
///   * تسميات الأعمدة (List<String>)
///   * صفوف كـ List<List<String>> (كل صف قيم بنفس ترتيب الأعمدة)
///
/// الأزرار تولّد الملف مؤقتاً وتفتح shareSheet — Excel يفتح CSV مباشرة.
/// الطباعة تفتح previewPDF عبر printing.Printing.layoutPdf.
///
/// نُبقي حد أعلى معقول (5000 صف) — الصفحة تعرض ضمن pagination لكن
/// التصدير يشمل الـfiltered set كامل.
/// ================================================================

class ReportExportBar extends StatelessWidget {
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
      // خط عربي — نستعمل NotoNaskh من Google Fonts (Cairo نستعملها بالتطبيق
      // لكن NotoNaskh أنقى للـPDF). أو أي خط مضمّن بالمشروع.
      final font = await PdfGoogleFonts.cairoRegular();
      final fontBold = await PdfGoogleFonts.cairoBold();
      final doc = pw.Document();
      doc.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          textDirection: pw.TextDirection.rtl,
          theme: pw.ThemeData.withFont(base: font, bold: fontBold),
          margin: const pw.EdgeInsets.all(24),
          build: (ctx) => [
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(title,
                    style: pw.TextStyle(fontSize: 18, font: fontBold)),
                pw.Text(_nowStr(),
                    style:
                        pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
              ],
            ),
            if (subtitle != null && subtitle!.isNotEmpty) ...[
              pw.SizedBox(height: 4),
              pw.Text(subtitle!,
                  style: pw.TextStyle(fontSize: 11, color: PdfColors.grey700)),
            ],
            pw.SizedBox(height: 12),
            // مطلب 2026-07-12: نُلف الجدول بـLTR Directionality عشان
            // العمود[0] (اسم المشترك) يظهر على أقصى اليسار (Excel
            // column A) والعمود الأخير (المنفّذ) على أقصى اليمين. الـ
            // MultiPage RTL كانت تعكس التخطيط الفيزيائي فتصير اسم المشترك
            // في اليمين والمنفّذ في اليسار — عكس ما يتوقّعه المستخدم من
            // ملف Excel. النص داخل الخلايا يبقى Arabic bidi يعمل صح
            // لأنه محتوى الخلية مستقل.
            pw.Directionality(
              textDirection: pw.TextDirection.ltr,
              child: pw.TableHelper.fromTextArray(
                headers: columns,
                data: rows,
                headerStyle: pw.TextStyle(
                    font: fontBold, fontSize: 11, color: PdfColors.white),
                headerDecoration:
                    const pw.BoxDecoration(color: PdfColors.teal600),
                cellStyle: pw.TextStyle(font: font, fontSize: 9),
                cellAlignment: pw.Alignment.centerRight,
                headerAlignment: pw.Alignment.center,
                border:
                    pw.TableBorder.all(color: PdfColors.grey400, width: 0.4),
                columnWidths: {
                  for (int i = 0; i < columns.length; i++)
                    i: pw.FlexColumnWidth(
                      columnWeights != null && i < columnWeights!.length
                          ? columnWeights![i]
                          : 1.0,
                    ),
                },
              ),
            ),
            pw.SizedBox(height: 6),
            pw.Align(
              alignment: pw.Alignment.centerLeft,
              child: pw.Text('عدد الصفوف: ${rows.length}',
                  style: pw.TextStyle(
                      fontSize: 9, color: PdfColors.grey700, font: font)),
            ),
          ],
        ),
      );
      await Printing.layoutPdf(
        onLayout: (fmt) async => doc.save(),
        name: '$fileNameBase.pdf',
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل الطباعة: $e')),
        );
      }
    }
  }

  static String _nowStr() {
    final n = DateTime.now();
    String p(int v) => v.toString().padLeft(2, '0');
    return '${n.year}-${p(n.month)}-${p(n.day)} ${p(n.hour)}:${p(n.minute)}';
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
          child:
              Icon(icon, size: 17, color: active ? color : AppColors.textLow),
        ),
      ),
    );
  }
}
