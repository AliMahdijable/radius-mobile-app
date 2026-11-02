import 'dart:math' as math;

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'receipt_grid.dart';
import 'receipt_layout.dart';
import 'receipt_pdf.dart';
import 'receipt_pdf_v2.dart';

/// وصل v4 «الشبكة» بنقاط PDF (٢ نوفمبر) — يرسم ما يرسمه الموقع (`renderGridReceipt`): صفوفٌ من ١–٣ خانات بعرضٍ نسبيّ، لكلّ
/// خانةٍ نمطها (الحجم بالنقطة، السُمك، اللون، الخلفيّة، الإطار، الزوايا، الحشوة، المحاذاة) والعنوان بنمطه وموضعه. الخطّ خطّ الطباعة
/// المضمَّن (الخطوط الأخرى للموقع وحده)، والألوان كما صمّمها الوكيل (الحراريّة تطبعها أسود). صفٌّ كلّ خاناته فارغة لا يُطبع.
class ReceiptGridBody {
  ReceiptGridBody(this.d, this.layout, {required this.logo, required this.a4, required this.width});

  final ReceiptDoc d;
  final GridLayout layout;
  final pw.MemoryImage? logo;
  final bool a4;

  /// عرض المحتوى بين الحاشيتين (نقطة PDF).
  final double width;

  static const double _mm = PdfPageFormat.mm;

  static PdfColor _color(String hex) => PdfColor.fromInt(0xFF000000 | int.parse(hex.substring(1), radix: 16));

  static pw.TextAlign _ta(String a) => switch (a) {
        'left' => pw.TextAlign.left,
        'right' => pw.TextAlign.right,
        _ => pw.TextAlign.center,
      };

  static pw.Alignment _al(String a) => switch (a) {
        'left' => pw.Alignment.centerLeft,
        'right' => pw.Alignment.centerRight,
        _ => pw.Alignment.center,
      };

  static pw.BorderStyle _bs(String s) => switch (s) {
        'dashed' => pw.BorderStyle.dashed,
        'dotted' => pw.BorderStyle.dotted,
        _ => pw.BorderStyle.solid,
      };

  /// النصّ كما يرسمه وصل v2: بلا تشكيلٍ ولا رموز، واللاتينيّ وحده LTR، والمختلط مقاطع (كـ`<bdi>` في الموقع).
  pw.Widget _txt(String raw, GridResolvedStyle s) {
    final t = ReceiptV2Body.drawn(raw);
    final style = pw.TextStyle(
      fontSize: s.pt,
      fontWeight: s.bold ? pw.FontWeight.bold : pw.FontWeight.normal,
      color: _color(s.color),
      lineSpacing: 1,
    );
    final dir = ReceiptV2Body.directionFor(t);
    final align = _ta(s.align);
    if (dir != null || !t.contains(RegExp(r'[0-9A-Za-z]'))) return pw.Text(t, textAlign: align, textDirection: dir, style: style);
    return pw.RichText(
      textAlign: align,
      text: pw.TextSpan(style: style, children: [for (final r in ReceiptV2Body.runsOf(t)) pw.TextSpan(text: r)]),
    );
  }

  /// صندوق النمط: الخلفيّة والإطار (٠٫٨ نقطة بلون النصّ) والزوايا والحشوة (عموديّة × ٠٫٦).
  pw.Widget _boxed(GridResolvedStyle s, pw.Widget child) {
    if (s.bg == null && s.box == null && s.padMm <= 0) return child;
    return pw.Container(
      padding: pw.EdgeInsets.symmetric(vertical: s.padMm * 0.6 * _mm, horizontal: s.padMm * _mm),
      decoration: pw.BoxDecoration(
        color: s.bg == null ? null : _color(s.bg!),
        border: s.box == null ? null : pw.Border.all(color: _color(s.color), width: 0.8, style: _bs(s.box!)),
        borderRadius: s.radiusMm > 0 ? pw.BorderRadius.circular(math.min(GridLimits.radiusMax, s.radiusMm) * _mm) : null,
      ),
      child: child,
    );
  }

  /// خانةٌ ⇒ ما يُطبع، أو null (فارغة: حقلٌ بلا قيمة، نصٌّ متغيّراته فارغة، شعارٌ/QR غير موجود).
  pw.Widget? _cell(GridCell c, Map<String, String> vars, ({GridResolvedStyle value, GridResolvedStyle label, GridResolvedStyle text}) def) {
    switch (c.type) {
      case 'space':
        final h = (c.h ?? 2).toDouble();
        return pw.SizedBox(height: math.min(GridLimits.spaceMax, math.max(0.5, h == 0 ? 2 : h)) * _mm);
      case 'line':
        final t = math.min(GridLimits.thickMax, math.max(GridLimits.thickMin, (c.thick ?? 1).toDouble()));
        final hex = c.style?.color;
        final color = hex != null && RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(hex) ? hex : def.text.color;
        return pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 0.6 * _mm),
          child: pw.Container(
            height: 0,
            decoration: pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(color: _color(color), width: t, style: _bs(c.line)))),
          ),
        );
      case 'logo':
      case 'qr':
        final size = math.min(GridLimits.sizeMax, math.max(GridLimits.sizeMin, (c.sizeMm ?? 18).toDouble())) * _mm;
        final align = c.style?.align ?? 'center';
        final pw.Widget? img = c.type == 'logo'
            ? (logo == null ? null : pw.Image(logo!, height: size, width: math.min(width, size * 2.5), fit: pw.BoxFit.contain))
            : (d.qrUrl == null || d.qrUrl!.isEmpty
                ? null
                : pw.BarcodeWidget(
                    barcode: pw.Barcode.qrCode(errorCorrectLevel: pw.BarcodeQRCorrectionLevel.medium),
                    data: d.qrUrl!,
                    width: math.min(width, size),
                    height: math.min(width, size),
                    drawText: false,
                  ));
        if (img == null) return null;
        return pw.Align(alignment: _al(align == 'right' ? 'right' : align == 'left' ? 'left' : 'center'), child: img);
      case 'text':
        final f = gridFill(c.text ?? '', vars);
        if (f.hidden) return null;
        final s = GridResolvedStyle.of(c.style, def.text);
        return _boxed(s, pw.SizedBox(width: double.infinity, child: _txt(f.text, s)));
      default: // field
        final value = gridValue(c, vars);
        if (value.isEmpty) return null;
        final vs = GridResolvedStyle.of(c.style, def.value);
        final valueW = _boxed(vs, pw.SizedBox(width: double.infinity, child: _txt(value, vs)));
        final label = c.labelPos == 'none' ? '' : gridFill(c.label ?? gridVarLabel(c.varId), vars).text;
        if (label.isEmpty) return valueW;
        final ls = GridResolvedStyle.of(c.labelStyle, def.label);
        final labelW = _boxed(ls, _txt(label, ls));
        if (c.labelPos == 'top') {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [labelW, pw.SizedBox(height: 0.6 * _mm), valueW],
          );
        }
        // العنوان في البداية (يمين الوصل) والقيمة تملأ الباقي
        return pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [labelW, pw.SizedBox(width: 1.2 * _mm), pw.Expanded(child: valueW)],
        );
    }
  }

  pw.Widget? _row(GridRow r, Map<String, String> vars, ({GridResolvedStyle value, GridResolvedStyle label, GridResolvedStyle text}) def) {
    final cells = [for (final c in r.cells) (c: c, w: _cell(c, vars, def))];
    if (cells.every((x) => x.w == null)) return null;
    final children = <pw.Widget>[];
    for (var i = 0; i < cells.length; i++) {
      if (i > 0) children.add(pw.SizedBox(width: 1.2 * _mm));
      children.add(pw.Expanded(flex: cells[i].c.w, child: cells[i].w ?? pw.SizedBox()));
    }
    final gap = r.gap == null ? 0.8 : math.min(GridLimits.gapMax, math.max(0, r.gap!.toDouble()));
    return pw.Padding(
      padding: pw.EdgeInsets.only(top: gap * _mm),
      child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: children),
    );
  }

  pw.Widget build() {
    final input = receiptInputOf(d, hasLogo: logo != null);
    final vars = gridVars(input, layout.currency ?? receiptDefaultCurrency);
    final def = gridDefaults(d.look.design);
    final rows = <pw.Widget>[];
    for (final r in layout.rows) {
      if (r.only.isNotEmpty && !r.only.contains(input.kind)) continue;
      final w = _row(r, vars, def);
      if (w != null) rows.add(w);
    }
    final body = pw.Directionality(
      textDirection: pw.TextDirection.rtl,
      child: pw.Column(mainAxisSize: pw.MainAxisSize.min, crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: rows),
    );
    if (!a4) return body;
    // A4: المحتوى بعرض ١٩٠ ملم أعلى الصفحة (كالموقع .receipt max-width).
    return pw.Align(alignment: pw.Alignment.topCenter, child: pw.SizedBox(width: math.min(width, 190 * _mm), child: body));
  }
}
