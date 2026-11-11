import 'dart:math' as math;

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../api/receipt_settings_api.dart';
import 'receipt_layout.dart';
import 'receipt_pdf.dart';

/// زوايا بطاقة A4 وختم «مُلغاة» وإطار النصّ (نقطة PDF) — ورقٌ مطبوع خارج توكنات الواجهة، كوصل v1.
const double _cardRadius = 8;
const double _boxRadius = 4;

/// بيانات [ReceiptDoc] بشكل المحلِّل ([ReceiptInput]) — المصدر نفسه لطريق v1 (الوقت والرقم والرصيد كما هي).
ReceiptInput receiptInputOf(ReceiptDoc d, {required bool hasLogo}) {
  final s = d.sale;
  return ReceiptInput(
    kind: d.kind.name,
    shopName: d.shopName,
    shopAddress: d.look.shopAddress,
    shopPhone: d.look.shopPhone,
    footerText: d.look.footerText,
    issuedText: d.issuedText,
    receiptId: d.receiptId,
    // {receipt_no}: رقم الفاتورة للبيع، ورقم الأرشيف بخمس خانات، وإلّا المرجع الزمنيّ.
    receiptNoText: s != null
        ? '${s.id}'
        : d.receiptNo != null
            ? '${d.receiptNo.toString().padLeft(5, '0')}${d.copy ? ' (${ReceiptDoc.copyWord})' : ''}'
            : d.receiptId,
    issuer: d.issuer,
    hasLogo: hasLogo,
    hasQr: d.qrUrl != null,
    subscriber: ReceiptInputSubscriber(
      name: d.subscriberName,
      username: d.username,
      phone: d.phone,
      packageName: d.packageName,
      sasPackageName: d.packageName,
      packagePrice: d.packagePrice,
      expiration: d.expiration,
      remainingDays: d.remainingDays,
    ),
    paymentType: switch (d.pay) {
      ReceiptPay.cash => 'cash',
      ReceiptPay.partial => 'partial-cash',
      ReceiptPay.credit => 'non-cash',
      ReceiptPay.wallet => 'wallet',
      null => null,
    },
    amount: d.amount,
    partialAmount: d.partialAmount,
    newBalance: d.newBalance,
    sale: s == null
        ? null
        : ReceiptInputSale(
            lines: [
              for (final l in s.lines)
                ReceiptInputSaleLine(name: l.name, qtyText: l.qty, unitPrice: l.unitPrice, total: l.total),
            ],
            total: s.total,
            debt: s.debt,
            note: s.note,
            voided: s.voided,
            voidReason: s.voidReason,
          ),
  );
}

/// وصل v2 ([ReceiptLayout]) بنقاط PDF: يرسم كتل المحلِّل وحدها — الموقع يرسم الكتل نفسها HTML.
///
/// الكاشير: أحجام الموقع بكسلاً × ٠٫٧٥ (round(الأساس × النسبة × الحجم))، ورموز الضغط، وفاصل الصفوف، وخطّ عنوان القسم،
/// والمحاذاة؛ أسود دائماً (الحراريّة لا تطبع لوناً). A4: ثوابت بطاقة v1 (١١ / ٩٫٥ / ١٤ / ١٩) × الحجم، وبلون المصمّم ما لم
/// يكن «أسود فقط». بلا تشكيل ولا رموزٍ تعبيريّة (خطّ الطباعة لا يرسمها في مواضعها).
class ReceiptV2Body {
  ReceiptV2Body(this.d, {required this.logo, required this.a4, required this.width})
      : r = ReceiptResolver.resolve(d.look.design, receiptInputOf(d, hasLogo: logo != null));

  final ReceiptDoc d;
  final pw.MemoryImage? logo;
  final bool a4;

  /// عرض المحتوى بين الحاشيتين (نقطة PDF).
  final double width;

  /// الكتل المحلَّلة.
  final ResolvedReceipt r;

  ReceiptSettings get _look => d.look;
  ReceiptDensityTokens get _tok => ReceiptDensityTokens.of(r.density);
  bool get _mono => r.mono;

  /// رموز الضغط بكسلاً ⇒ نقاط (A4 أصغر قليلاً كبطاقة v1: حشوة الصفّ ٣ نقاط).
  double _k(double px) => px * (a4 ? 0.6 : 0.75);
  static double _pt(num px) => px * 0.75;

  PdfColor get _accent => !a4 || _mono
      ? PdfColors.black
      : (_look.accent != null ? PdfColor.fromInt(_look.accent!) : const PdfColor.fromInt(0xFF0D9488));
  PdfColor get _muted => a4 && !_mono ? PdfColors.grey700 : PdfColors.black;
  double get _gap => a4 ? 10 : _look.sectionGapMm * PdfPageFormat.mm;

  /// حجم الخطّ: الكاشير round(الأساس × النسبة × الحجم) بكسلاً كالموقع (اسم المحلّ = العنوان × الحجم)، وA4 ثوابت بطاقة v1
  /// × الحجم.
  double _size(String kind, num scale, [num? pt]) {
    // v3: حجمٌ مثبّت بالنقطة — نقطة PDF = نقطة CSS، فالموقع والتطبيق يطبعان الحجم نفسه (كاشير وA4).
    if (pt != null) return pt.toDouble();
    if (a4) {
      final c = switch (kind) { 'caption' => 9.5, 'subtitle' => 14.0, 'h1' => 19.0, _ => 11.0 };
      return c * scale;
    }
    return switch (kind) {
      'h1' => _pt((_look.fontTitlePx * scale).round()),
      'subtitle' => _pt((_look.fontTitlePx * receiptRatios['subtitle']! * scale).round()),
      _ => _pt((_look.fontBasePx * receiptRatios[kind]! * scale).round()),
    };
  }

  static final RegExp _emoji = RegExp('[\u{1F000}-\u{1FAFF}\u{2600}-\u{27BF}\u{FE0F}\u{200D}]', unicode: true);

  /// ما يُرسم: بلا تشكيل (مكتبة PDF لا تضعه في موضعه) ولا رموزٍ تعبيريّة (خطّ الطباعة بلاها) — المحلِّل يُبقيهما.
  static String drawn(String s) => ReceiptPdf.plain(s).replaceAll(_emoji, '').replaceAll(RegExp(r'[ \t]{2,}'), ' ');

  static final RegExp _arabic = RegExp('[\u0600-\u06FF\u0750-\u077F\u08A0-\u08FF\uFB50-\uFDFF\uFE70-\uFEFF]');

  /// مقطعٌ لاتينيّ: رقمٌ، تاريخٌ ووقت، هاتفٌ بمسافات، «No. 00012»، اسمٌ لاتينيّ — وحدةٌ واحدة كـ`<bdi>` في الموقع.
  static final RegExp _latinRun = RegExp(r'[#+@]?[0-9A-Za-z](?:[0-9A-Za-z@#.,:/_+\- ]*[0-9A-Za-z])?');

  /// سطرٌ بلا عربيّ ⇒ LTR كلّه؛ وفيه عربيّ ⇒ RTL (مكتبة PDF لا تشكّل العربيّ في سطرٍ LTR — حروفٌ منفصلة معكوسة).
  static pw.TextDirection? directionFor(String text) => _arabic.hasMatch(text) ? null : pw.TextDirection.ltr;

  /// السطر المختلط مقاطع: كلّ مقطعٍ لاتينيّ وحده — مكتبة PDF في سطرٍ RTL تفكّ المقطع متعدّد الأجزاء («2026-11-01 10:05»
  /// تخرج «10:05 01-11-2026»، و«0780 000 0000» بأجزاءٍ معكوسة)، ومقطعاً يبقى بترتيبه كما يرسمه الموقع بـ`<bdi>`. ما سوى
  /// ذلك (المبالغ، «31 يوم»، «أصدره: …») يُرسم كما يرسمه النصّ العاديّ حرفاً بحرف.
  static List<String> runsOf(String text) {
    final out = <String>[];
    var i = 0;
    for (final m in _latinRun.allMatches(text)) {
      if (m.start > i) out.add(text.substring(i, m.start));
      out.add(m.group(0)!);
      i = m.end;
    }
    if (i < text.length) out.add(text.substring(i));
    return out;
  }

  /// كلّ نصٍّ في وصل v2 يُرسم من هنا: بلا تشكيلٍ ولا رموز، واللاتينيّ وحده LTR، والمختلط مقاطع.
  pw.Widget _txt(String raw, {required pw.TextStyle style, pw.TextAlign align = pw.TextAlign.right}) {
    final t = drawn(raw);
    final dir = directionFor(t);
    if (dir != null || !_latinRun.hasMatch(t)) return pw.Text(t, textAlign: align, textDirection: dir, style: style);
    return pw.RichText(
      textAlign: align,
      text: pw.TextSpan(style: style, children: [for (final r in runsOf(t)) pw.TextSpan(text: r)]),
    );
  }

  static pw.TextAlign _ta(String a) => switch (a) {
        'left' => pw.TextAlign.left,
        'right' => pw.TextAlign.right,
        'justify' => pw.TextAlign.justify,
        _ => pw.TextAlign.center,
      };

  static pw.Alignment _al(String a) => switch (a) {
        'left' => pw.Alignment.centerLeft,
        'right' => pw.Alignment.centerRight,
        _ => pw.Alignment.center,
      };

  pw.BorderStyle? get _separator => switch (_look.rowSeparator) {
        'solid' => pw.BorderStyle.solid,
        'dashed' => pw.BorderStyle.dashed,
        'dotted' => pw.BorderStyle.dotted,
        _ => null,
      };

  pw.FontWeight _w(bool bold) => bold ? pw.FontWeight.bold : pw.FontWeight.normal;

  static const double _mm = PdfPageFormat.mm;

  static pw.BorderStyle? _sepStyle(String? sep) => switch (sep) {
        'solid' => pw.BorderStyle.solid,
        'dashed' => pw.BorderStyle.dashed,
        'dotted' => pw.BorderStyle.dotted,
        _ => null,
      };

  /// لون «خطّ تحته» (v3): أسود على الكاشير و«أسود فقط»، ورماديّ على A4.
  PdfColor get _sepColor => !a4 || _mono ? PdfColors.black : PdfColors.grey500;

  /// «خطّ تحته» لكتلة/سطر (v3): حشوة ١ ملم ثمّ خطّ ٠٫٧٥ نقطة — يزيد الطول بهما معاً كحدّ CSS في الموقع (إطار مكتبة PDF
  /// يُرسم داخل الحشوة فيُضاف سُمكه إليها). null/none ⇒ العنصر كما هو.
  pw.Widget _underline(String? sep, pw.Widget child) {
    final style = _sepStyle(sep);
    if (style == null) return child;
    return pw.Container(
      padding: const pw.EdgeInsets.only(bottom: 1 * _mm + 0.75),
      decoration: pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(color: _sepColor, width: 0.75, style: style)),
      ),
      child: child,
    );
  }

  /// مسافتا سطرٍ داخل كتلة (v3): حشوةٌ فوق/تحت بالملّيمتر — بلاهما السطر كما هو.
  static pw.Widget _gapped(num before, num after, pw.Widget child) => before > 0 || after > 0
      ? pw.Padding(padding: pw.EdgeInsets.only(top: before * _mm, bottom: after * _mm), child: child)
      : child;

  pw.Widget build() {
    final children = <pw.Widget>[];
    RBlock? prev;
    for (final b in r.blocks) {
      // v3: مسافة الكتلة السابقة بعدها + مسافة هذه قبلها، فوق المسافة الطبيعيّة (لا تبتلع إحداهما الأخرى).
      final space = prev == null ? 0.0 : _spaceBefore(b, prev) + (prev.gapAfter + b.gapBefore) * _mm;
      // الأقسام والعنوان بلا خطّ كتلة، و«الرقم والتاريخ» خطّه يحلّ محلّ خطّ الكتلة نفسه (_meta).
      var w = b is RSection || b is RTitle || b is RMeta ? _block(b) : _underline(b.sep, _block(b));
      if (prev == null && b.gapBefore > 0) {
        w = pw.Padding(padding: pw.EdgeInsets.only(top: b.gapBefore * _mm), child: w);
      }
      children.add(space > 0 ? pw.Padding(padding: pw.EdgeInsets.only(top: space), child: w) : w);
      prev = b;
    }
    if (prev != null && prev.gapAfter > 0) {
      children.add(pw.SizedBox(height: prev.gapAfter * _mm));
    }
    final body = pw.Column(
      mainAxisSize: pw.MainAxisSize.min,
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: children,
    );
    if (!a4) return body;
    // A4: بطاقةٌ في أعلى الصفحة كوصل v1.
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

  /// المسافة فوق الكتلة: الترويسة متلاصقة كالموقع، والأقسام وQR والذيل بـ«المسافة بين الأقسام».
  double _spaceBefore(RBlock b, RBlock prev) {
    if (prev is RLogo) return _k(_tok.logoGap);
    return switch (b) {
      RShopLines() => prev is RShopName ? _k(4) : _gap / 2,
      RTitle() => prev is RShopName || prev is RShopLines ? (a4 ? _gap * 0.8 : _gap) : _gap / 2,
      RMeta() => a4 ? 4 : (prev is RTitle ? _gap : _gap / 2),
      RSection() || RSaleItems() || RSaleVoid() || RSaleNote() => math.max(_gap, _k(_tok.tableGap)),
      RQr() || RFooter() => _gap,
      _ => _gap / 2,
    };
  }

  pw.Widget _block(RBlock b) => switch (b) {
        RLogo() => _logo(b),
        RShopName() => _txt(
            b.text,
            align: _ta(b.align),
            style: pw.TextStyle(fontSize: _size('h1', b.scale, b.pt), fontWeight: _w(b.bold), color: _accent),
          ),
        RShopLines() => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              for (final l in b.lines)
                _gapped(
                  l.gapBefore,
                  l.gapAfter,
                  _underline(
                    l.sep,
                    _txt(
                      l.text,
                      align: _ta(l.align),
                      style: pw.TextStyle(fontSize: _size('caption', l.scale, l.pt), fontWeight: _w(l.bold), color: _muted),
                    ),
                  ),
                ),
            ],
          ),
        RTitle() => _title(b),
        RMeta() => _meta(b),
        RSection() => _section(
            b.title,
            [for (final row in b.rows) _row(row)],
            seps: [for (final row in b.rows) row.sep],
            titlePt: b.titlePt,
            titleAlign: b.titleAlign,
          ),
        RSaleVoid() => _stamp(b.text),
        RSaleItems() => _section(
            b.title,
            [for (final l in b.lines) _itemRow(l)],
            titlePt: b.titlePt,
            titleAlign: b.titleAlign,
          ),
        RSaleNote() => _boxed(
            _txt(b.text, style: pw.TextStyle(fontSize: _size('label', 1))),
            dashed: true,
          ),
        RText() => _text(b),
        RQr() => _qr(b),
        RFooter() => _footer(b),
      };

  pw.Widget _logo(RLogo b) => pw.Align(
        alignment: _al(b.align),
        child: a4
            ? pw.Image(logo!, height: 56, fit: pw.BoxFit.contain)
            : pw.Image(
                logo!,
                height: _look.logoSizeMm * PdfPageFormat.mm,
                width: math.min(width, _look.logoSizeMm * 2.5 * PdfPageFormat.mm),
                fit: pw.BoxFit.contain,
              ),
      );

  /// مزيج اللون الأساسيّ بالأبيض (تعبئة صندوق العنوان في A4) — تعبئةٌ معتمة بدل الشفافيّة.
  PdfColor _tint(PdfColor c, double a) => PdfColor(1 - a + a * c.red, 1 - a + a * c.green, 1 - a + a * c.blue);

  pw.Widget _title(RTitle b) => pw.Container(
        padding: pw.EdgeInsets.symmetric(vertical: _k(_tok.titlePadV), horizontal: _k(_tok.titlePadH)),
        decoration: pw.BoxDecoration(
          color: a4 && !_mono && _tok.titleFill ? _tint(_accent, 0.08) : null,
          border: pw.Border.all(color: _accent, width: a4 ? 1 : 0.8),
          borderRadius: pw.BorderRadius.circular(a4 ? 6 : 4),
        ),
        child: _txt(
          b.text,
          align: _ta(b.align),
          style: pw.TextStyle(fontSize: _size('subtitle', b.scale, b.pt), fontWeight: _w(b.bold), color: _accent),
        ),
      );

  pw.Widget _meta(RMeta b) {
    final style = pw.TextStyle(fontSize: a4 ? _size('caption', 1) : _size('label', 1), color: _muted);
    // v3: حجم كلّ جزءٍ ووزنه — بلاهما النمط نفسه كما كان.
    pw.TextStyle part(num? pt, bool bold) =>
        pt == null && !bold ? style : style.copyWith(fontSize: pt?.toDouble(), fontWeight: bold ? pw.FontWeight.bold : null);
    final noStyle = part(b.noPt, b.noBold);
    final atStyle = part(b.atPt, b.atBold);
    final both = b.no != null && b.at != null;
    // «خطّ تحته» للرقم والتاريخ يحلّ محلّ خطّهما (none يزيله).
    final sepStyle = _sepStyle(b.sep);
    final pw.BoxDecoration? line = b.sep == null
        ? (_tok.metaLine
            ? const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey300, width: 0.5)))
            : null)
        : (sepStyle == null
            ? null
            : pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: _sepColor, width: 0.75, style: sepStyle))));
    final pw.Widget child = b.split
        ? pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              if (b.no != null)
                _gapped(b.noGapBefore, b.noGapAfter, _txt(b.no!, align: _ta(b.noAlign ?? 'center'), style: noStyle)),
              if (b.at != null)
                _gapped(b.atGapBefore, b.atGapAfter, _txt(b.at!, align: _ta(b.atAlign ?? 'center'), style: atStyle)),
            ],
          )
        : pw.Row(
            mainAxisAlignment: both ? pw.MainAxisAlignment.spaceBetween : pw.MainAxisAlignment.center,
            children: [
              if (b.no != null) _txt(b.no!, style: noStyle),
              if (b.at != null) _txt(b.at!, style: atStyle),
            ],
          );
    return pw.Container(
      padding: pw.EdgeInsets.only(bottom: _k(_tok.metaPad)),
      decoration: line,
      child: child,
    );
  }

  /// [seps] «خطّ تحته» لكلّ صفّ (v3): المحدَّد يحلّ محلّ فاصل الصفوف — حتى في آخر صفّ — بـ٠٫٧٥ نقطة، و`none` يزيله.
  pw.Widget _section(
    String? title,
    List<pw.Widget> rows, {
    List<String?>? seps,
    num? titlePt,
    String? titleAlign,
  }) {
    final sep = _separator;
    pw.BoxDecoration? lineOf(int i) {
      final own = seps == null ? null : seps[i];
      if (own != null) {
        final st = _sepStyle(own);
        return st == null
            ? null
            : pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: _sepColor, width: 0.75, style: st)));
      }
      return i == rows.length - 1 || sep == null
          ? null
          : pw.BoxDecoration(
              border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey500, width: 0.5, style: sep)),
            );
    }

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        if (title != null)
          pw.Container(
            padding: const pw.EdgeInsets.only(bottom: 2),
            margin: pw.EdgeInsets.only(bottom: _k(_tok.sectionTitleGap)),
            decoration: _look.sectionTitleUnderline
                ? pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: _accent, width: 0.8)))
                : null,
            child: _txt(
              title,
              align: _ta(titleAlign ?? r.labelAlign),
              style: pw.TextStyle(fontSize: _size('label', 1, titlePt), fontWeight: pw.FontWeight.bold, color: _accent),
            ),
          ),
        for (var i = 0; i < rows.length; i++)
          pw.Container(
            decoration: lineOf(i),
            child: rows[i],
          ),
      ],
    );
  }

  /// التسمية بمحاذاة النصوص الأساسيّة (لا تتجاوز ٤٥٪ من العرض) والقيمة بعكسها؛ بلا تسمية ⇒ القيمة وحدها بجهة التسمية.
  /// «المجموع» (tone total) بحجم العنوان الفرعيّ.
  pw.Widget _row(RRow row) {
    var color = PdfColors.black;
    if (a4 && !_mono && (row.tone == 'debt' || row.tone == 'credit')) {
      color = row.tone == 'debt' ? const PdfColor.fromInt(0xFFDC2626) : const PdfColor.fromInt(0xFF059669);
    }
    final total = row.tone == 'total';
    // v3: مسافتا الصفّ فوق حشوته وتحتها.
    final pad = row.gapBefore > 0 || row.gapAfter > 0
        ? pw.EdgeInsets.only(top: _k(_tok.rowPad) + row.gapBefore * _mm, bottom: _k(_tok.rowPad) + row.gapAfter * _mm)
        : pw.EdgeInsets.symmetric(vertical: _k(_tok.rowPad));
    final valueStyle = pw.TextStyle(
      fontSize: total ? _size('subtitle', row.scale) : _size('value', row.scale, row.pt),
      color: color,
      fontWeight: _w(row.bold || row.tone != null),
    );
    final label = row.label;
    if (label == null) {
      return pw.Padding(padding: pad, child: _txt(row.value, align: _ta(row.align ?? r.labelAlign), style: valueStyle));
    }
    final labelStyle = total
        ? pw.TextStyle(fontSize: _size('subtitle', row.scale), fontWeight: pw.FontWeight.bold)
        : pw.TextStyle(fontSize: _size('label', row.scale, row.labelPt), color: _muted);
    if (row.stack) {
      // «تحت بعض»: التسمية سطرٌ خافت فوق القيمة، بمحاذاة الصفّ.
      final a = _ta(row.align ?? r.labelAlign);
      return pw.Padding(
        padding: pad,
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            _txt(label, align: a, style: labelStyle),
            _txt(row.value, align: a, style: valueStyle),
          ],
        ),
      );
    }
    return pw.Padding(
      padding: pad,
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.ConstrainedBox(
            constraints: pw.BoxConstraints(maxWidth: width * 0.45),
            child: _txt(label, align: _ta(r.labelAlign), style: labelStyle),
          ),
          pw.SizedBox(width: 8),
          pw.Expanded(
            child: _txt(row.value, align: _ta(row.align ?? r.valueAlign), style: valueStyle),
          ),
        ],
      ),
    );
  }

  /// مادّة: اسمها وتحته «الكمّيّة × سعر الوحدة»، ومجموعها في الجهة الأخرى.
  pw.Widget _itemRow(RSaleLine l) => pw.Padding(
        padding: pw.EdgeInsets.symmetric(vertical: _k(_tok.rowPad)),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  _txt(l.name, style: pw.TextStyle(fontSize: _size('value', 1), fontWeight: pw.FontWeight.bold)),
                  _txt(l.detail, style: pw.TextStyle(fontSize: _size('caption', 1), color: _muted)),
                ],
              ),
            ),
            pw.SizedBox(width: 8),
            _txt(l.total, style: pw.TextStyle(fontSize: _size('value', 1), fontWeight: pw.FontWeight.bold)),
          ],
        ),
      );

  pw.Widget _stamp(String text) {
    final red = a4 && !_mono ? const PdfColor.fromInt(0xFFB00020) : PdfColors.black;
    return pw.Container(
      padding: const pw.EdgeInsets.all(4),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: red, width: 1.4),
        borderRadius: pw.BorderRadius.circular(_boxRadius),
      ),
      child: _txt(
        text,
        align: pw.TextAlign.center,
        style: pw.TextStyle(fontSize: _size('value', 1), fontWeight: pw.FontWeight.bold, color: red),
      ),
    );
  }

  pw.Widget _boxed(pw.Widget child, {bool dashed = false}) => pw.Container(
        padding: const pw.EdgeInsets.all(4),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(
            color: dashed ? PdfColors.grey500 : _accent,
            width: dashed ? 0.6 : 0.8,
            style: dashed ? pw.BorderStyle.dashed : pw.BorderStyle.solid,
          ),
          borderRadius: pw.BorderRadius.circular(_boxRadius),
        ),
        child: child,
      );

  pw.Widget _text(RText b) {
    final t = _txt(
      b.text,
      align: _ta(b.align),
      style: pw.TextStyle(fontSize: _size('value', b.scale, b.pt), fontWeight: _w(b.bold)),
    );
    return b.boxed ? _boxed(t) : t;
  }

  pw.Widget _qr(RQr b) {
    final size = a4 ? 30 * PdfPageFormat.mm : math.min(width, _look.qrSizeMm * PdfPageFormat.mm);
    return pw.Container(
      padding: pw.EdgeInsets.only(top: _k(_tok.qrPad)),
      decoration: _tok.qrLine
          ? const pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(color: PdfColors.grey300, width: 0.5)))
          : null,
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Align(
            alignment: _al(b.align),
            child: pw.BarcodeWidget(
              barcode: pw.Barcode.qrCode(errorCorrectLevel: pw.BarcodeQRCorrectionLevel.medium),
              data: d.qrUrl ?? '',
              width: size,
              height: size,
              drawText: false,
            ),
          ),
          if (b.caption != null) ...[
            pw.SizedBox(height: _k(_tok.qrGap)),
            _txt(
              b.caption!,
              align: _ta(b.captionAlign),
              style: b.captionBold
                  ? pw.TextStyle(fontSize: _size('caption', 1, b.captionPt), color: _muted, fontWeight: pw.FontWeight.bold)
                  : pw.TextStyle(fontSize: _size('caption', 1, b.captionPt), color: _muted),
            ),
          ],
        ],
      ),
    );
  }

  pw.Widget _footer(RFooter b) => pw.Container(
        padding: pw.EdgeInsets.only(top: _k(_tok.footerPad)),
        decoration: const pw.BoxDecoration(
          border: pw.Border(top: pw.BorderSide(color: PdfColors.grey500, width: 0.6, style: pw.BorderStyle.dashed)),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            for (final l in b.lines)
              _gapped(
                l.gapBefore,
                l.gapAfter,
                _underline(
                  l.sep,
                  _txt(
                    l.text,
                    align: _ta(l.align),
                    style: l.id == 'issuer'
                        ? pw.TextStyle(fontSize: _size('caption', l.scale, l.pt), fontWeight: _w(l.bold), color: _muted)
                        // نصّ الذيل نصف نقطةٍ أكبر — إلّا حين يُثبَّت حجمه (المثبّت يُطبع كما هو، كالموقع).
                        : pw.TextStyle(
                            fontSize: l.pt != null ? l.pt!.toDouble() : _size('caption', l.scale) + 0.5,
                            fontWeight: _w(l.bold),
                          ),
                  ),
                ),
              ),
          ],
        ),
      );
}
