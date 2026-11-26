import 'package:flutter/foundation.dart';
import 'package:pdf/pdf.dart';
// ignore: implementation_imports
import 'package:pdf/src/pdf/font/bidi_utils.dart' as pdf_bidi;
import 'package:pdf/widgets.dart' as pw;

import '../core/util/format.dart';

/// رقمٌ في ملخّص ملفّ PDF (بطاقة): عنوانه وقيمته كما على الشاشة — لا يُحسب هنا شيء.
@immutable
class PdfStat {
  const PdfStat(this.label, this.value, {this.tone = PdfTone.plain, this.hint});
  final String label;
  final String value;
  final PdfTone tone;
  final String? hint;
}

enum PdfTone { plain, good, bad, warn }

/// تصميم ملفّات PDF المشترك — التقارير ([ReportPdf]) وسند التسوية ([SettlementPrint]).
///
/// ٢٦ نوفمبر — المالك: «تصميم التقارير بملف pdf حاليا تصميم كلش مخزي بجميع التقارير والتسويه … حسّن التصميم اكثر ومعلومات
/// اوضح»: شريط هويّة بالعنوان والفترة، الفلاتر رقائق، بطاقات ملخّص، جدولٌ برأسٍ يتكرّر بكلّ صفحة وأسطرٍ متناوبة، وتذييلٌ برقم
/// الصفحة ووقت الطباعة. النصّ داكنٌ على أرضيّةٍ فاتحة فيبقى مقروءاً بطابعةٍ أبيض وأسود.
///
/// العربيّ كلّه عبر [rtl]: اتّجاه RTL في مكتبة pdf يضيّع المسافة بعد «ر» و«د»، وخطّ التطبيق بلا أشكال الشدّة مع الحركة
/// (U+FC5E–FC63 ⇒ مربّعٌ فارغ في «يُحصَّل» و«المُرحَّل»)، والتنوين يُرسم علامةً منفصلة («نقداً» ⇒ «نقدا!»)، والتاريخ داخل
/// جملةٍ عربيّة تنقلب أجزاؤه («2026-11-01» ⇒ «01-11-2026»).
class PdfKit {
  PdfKit._();

  // ── الألوان: هويّة التطبيق (#103D2E) وظلالها.
  static const brand = PdfColor.fromInt(0xFF103D2E);
  static const brandSoft = PdfColor.fromInt(0xFFBFD8CA);
  static const tint = PdfColor.fromInt(0xFFE6F1EB);
  static const tintLight = PdfColor.fromInt(0xFFF4F8F6);
  static const ink = PdfColor.fromInt(0xFF15201A);
  static const muted = PdfColor.fromInt(0xFF5A6861);
  static const rule = PdfColor.fromInt(0xFFD3DDD7);
  static const red = PdfColor.fromInt(0xFFB42318);
  static const redTint = PdfColor.fromInt(0xFFFDECEA);
  static const amber = PdfColor.fromInt(0xFF8A5300);
  static const amberTint = PdfColor.fromInt(0xFFFFF4DE);
  static const green = PdfColor.fromInt(0xFF12704A);
  static const greenTint = PdfColor.fromInt(0xFFE5F3EB);

  static const appName = 'MyServices Pro';

  static final _arabic = RegExp(r'[\u0600-\u06FF\u0750-\u077F\u08A0-\u08FF\uFB50-\uFDFF\uFE70-\uFEFF]');

  /// الحركات (عدا الشدّة وحدها — لها شكلٌ في الخطّ): الشدّة مع الحركة ⇒ رمزٌ لا يملكه الخطّ، والتنوين ⇒ علامةٌ منفصلة.
  static final _marks = RegExp(r'[\u064B-\u0650\u0652-\u065F\u0670\u06D6-\u06ED]');

  /// رقمٌ بفواصل أو إشارة («2026-11-01»، «22:47»، «2,031,000»، «-5,000») — يُحمى من قلب أجزائه.
  static final _ltrNumber = RegExp(r'[-\u2212+]?\d+(?:[-/:.,]\d+)+|[-\u2212]\d+');

  /// فواصل الرقم وإشارته ⇒ أرقامٌ فارسيّة (اتّجاهها EN كالأرقام، بلا تفكيكٍ توافقيّ — مكتبة الاتّجاه تحوّل الأرقام السفليّة
  /// إلى «0») أثناء الترتيب، ثمّ تُعاد كما كانت. نصٌّ فيه رقمٌ فارسيّ أصلاً لا يُحمى (يبقى كما كان قبل الحماية).
  static const _sepIn = '-\u2212+/:.,';
  static const _sepOut = '\u06F0\u06F1\u06F2\u06F3\u06F4\u06F5\u06F6';
  static final _sepBack = RegExp('[\u06F0-\u06F6]');

  /// محارف الاتّجاه (العزل FSI/PDI حول الأرقام السالبة في التطبيق، LRM/RLM): لا شكل لها في الخطّ ⇒ تُحذف قبل الرسم.
  static final _controls = RegExp('[\u200E\u200F\u202A-\u202E\u2066-\u2069]');

  static String plain(String s) => s.replaceAll(_controls, '');

  static bool isArabic(String s) => _arabic.hasMatch(s);

  /// النصّ مشكَّلاً بترتيبه المرئيّ من اليسار — يُرسم LTR كما هو. مخبّأ: «تسديد دين» يتكرّر آلاف المرّات في التقرير الواحد.
  ///
  /// مكتبة الاتّجاه لا تطبّق قاعدة W4 (الفاصل بين رقمين جزءٌ من الرقم) فكانت تقلب أجزاء التاريخ والوقت («2026-11-01» ⇒
  /// «01-11-2026»): فواصل الرقم تُستبدل أثناء الترتيب بأرقامٍ فارسيّة فيبقى رقماً واحداً، ثمّ تُعاد — والأرقام المتتالية تُقرأ من
  /// اليمين كما على شاشة التطبيق («من 2026-11-01 ← 2026-11-26»). وعلامة RLM في أوّله تجعل الفقرة عربيّةً ولو بدأت بكلمةٍ لاتينيّة.
  static String visual(String logical) {
    final hit = _visual[logical];
    if (hit != null) return hit;
    if (_visual.length > 20000) _visual.clear();
    var guarded = false;
    final clean = plain(logical).replaceAll(_marks, '');
    final s = _sepBack.hasMatch(clean) ? clean : clean.replaceAllMapped(_ltrNumber, (m) {
      guarded = true;
      return m[0]!.split('').map((ch) {
        final i = _sepIn.indexOf(ch);
        return i < 0 ? ch : _sepOut[i];
      }).join();
    });
    var v = pdf_bidi.logicalToVisual('\u200F$s').split(' ').reversed.join(' ').replaceAll('\u200F', '');
    if (guarded) v = v.replaceAllMapped(_sepBack, (m) => _sepIn[_sepOut.indexOf(m[0]!)]);
    return _visual[logical] = v;
  }

  static final _visual = <String, String>{};

  /// نمط نصّ (الخطّ من سمة المستند).
  static pw.TextStyle st({double size = 10, PdfColor color = ink, bool bold = false, double? lineSpacing}) => pw.TextStyle(
        fontSize: size,
        color: color,
        fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
        lineSpacing: lineSpacing,
      );

  /// نصّ: العربيّ عبر [rtl]، وما سواه (تاريخ، يوزر، رقم) LTR كما هو.
  static pw.Widget text(String s, pw.TextStyle style, {pw.TextAlign align = pw.TextAlign.right}) =>
      isArabic(s) ? rtl(s, style, align: align) : pw.Text(plain(s), style: style, textAlign: align, textDirection: pw.TextDirection.ltr);

  /// نصٌّ عربيّ بلا عيوب مكتبة pdf: الأسطر تُقسَّم بالكلمات المنطقيّة على العرض المتاح، وكلّ سطرٍ يُشكَّل ويُرتَّب مرّةً
  /// ([visual]) ثمّ يُرسم LTR — المسافة مسافةٌ حقيقيّة. [align] بمعناه المرئيّ (اليمين يمين) أيّاً كان اتّجاه الصفحة.
  static pw.Widget rtl(String s, pw.TextStyle style, {pw.TextAlign align = pw.TextAlign.right}) {
    final words = s.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    return pw.LayoutBuilder(builder: (ctx, c) {
      final merged = pw.Theme.of(ctx).defaultTextStyle.merge(style);
      final font = merged.font!.getFont(ctx);
      final size = merged.fontSize!;
      double width(String v) => v.isEmpty ? 0 : font.stringMetrics(v).advanceWidth * size;
      final maxW = c == null || !c.maxWidth.isFinite ? double.infinity : c.maxWidth - 0.5;
      final lines = <String>[];
      final whole = visual(words.join(' '));
      if (width(whole) <= maxW) {
        lines.add(whole);
      } else {
        final space = width(' ');
        var cur = <String>[];
        var curW = 0.0;
        for (final w in words) {
          final ww = width(visual(w));
          if (cur.isNotEmpty && curW + space + ww > maxW) {
            lines.add(visual(cur.join(' ')));
            cur = [w];
            curW = ww;
          } else {
            curW += (cur.isEmpty ? 0 : space) + ww;
            cur.add(w);
          }
        }
        if (cur.isNotEmpty) lines.add(visual(cur.join(' ')));
      }
      return pw.Directionality(
        textDirection: pw.TextDirection.ltr,
        child: pw.Column(
          mainAxisSize: pw.MainAxisSize.min,
          crossAxisAlignment: align == pw.TextAlign.center
              ? pw.CrossAxisAlignment.center
              : (align == pw.TextAlign.left ? pw.CrossAxisAlignment.start : pw.CrossAxisAlignment.end),
          children: [
            for (final l in lines) pw.Text(l, style: style, textAlign: align, textDirection: pw.TextDirection.ltr),
          ],
        ),
      );
    });
  }

  static String stamp(DateTime d) {
    final l = d.toLocal();
    String p(int v) => v.toString().padLeft(2, '0');
    return '${l.year}-${p(l.month)}-${p(l.day)} ${p(l.hour)}:${p(l.minute)}';
  }

  /// المبلغ بفواصل وإشارة السالب («-125,000») — يُرسم LTR. التقريب قبل الإشارة: −0.4 يُطبع «0» لا «-0».
  static String amount(num n) {
    final r = n.round();
    return '${r < 0 ? '-' : ''}${formatIQD(r)}';
  }

  /// رقمٌ بعملته: الرقم LTR والعملة بعده (يساره) — «2,031,000 د.ع» مقروءةً من اليمين.
  static pw.Widget money(num n, {double size = 10, PdfColor color = ink, bool bold = false, bool unit = true}) => pw.Row(
        mainAxisSize: pw.MainAxisSize.min,
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          pw.Text(amount(n), style: st(size: size, color: color, bold: bold), textDirection: pw.TextDirection.ltr),
          if (unit) ...[
            pw.SizedBox(width: size * 0.3),
            pw.Padding(
              padding: pw.EdgeInsets.only(bottom: size * 0.08),
              child: rtl('د.ع', st(size: size * 0.72, color: color == ink ? muted : color)),
            ),
          ],
        ],
      );

  // ═══════════════ قطع التصميم ═══════════════

  /// شريط الرأس: [over] سطرٌ صغيرٌ فوق العنوان (الشركة)، والعنوان، و[subtitle] (الفترة)؛ و[side] أسطرٌ على اليسار.
  static pw.Widget band({required String title, String? over, String? subtitle, List<String> side = const [], bool compact = false}) {
    const white = PdfColors.white;
    return pw.Container(
      padding: compact ? const pw.EdgeInsets.fromLTRB(12, 8, 12, 8) : const pw.EdgeInsets.fromLTRB(16, 12, 16, 13),
      decoration: const pw.BoxDecoration(color: brand, borderRadius: pw.BorderRadius.all(pw.Radius.circular(8))),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              mainAxisSize: pw.MainAxisSize.min,
              children: [
                if ((over ?? '').trim().isNotEmpty) ...[
                  text(over!.trim(), st(size: compact ? 8.5 : 9.5, color: brandSoft, bold: true)),
                  pw.SizedBox(height: 2),
                ],
                text(title, st(size: compact ? 13 : 18, color: white, bold: true)),
                if ((subtitle ?? '').trim().isNotEmpty) ...[
                  pw.SizedBox(height: 3),
                  text(subtitle!.trim(), st(size: compact ? 9 : 10.5, color: brandSoft)),
                ],
              ],
            ),
          ),
          if (side.isNotEmpty) ...[
            pw.SizedBox(width: 12),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              mainAxisSize: pw.MainAxisSize.min,
              children: [
                for (var i = 0; i < side.length; i++) ...[
                  if (i > 0) pw.SizedBox(height: 3),
                  text(side[i], st(size: 9, color: i == 0 ? white : brandSoft, bold: i == 0)),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// الفلاتر المختارة رقائق: «المفتاح: القيمة» ⇒ المفتاح باهتاً والقيمة بارزة.
  static pw.Widget chips(List<String> items, {double size = 9}) => pw.Wrap(
        spacing: 6,
        runSpacing: 5,
        children: [
          for (final d in items)
            if (d.trim().isNotEmpty) chip(d.trim(), size: size),
        ],
      );

  static pw.Widget chip(String d, {double size = 9}) {
    final i = d.indexOf(': ');
    final label = i > 0 && i < 40 ? d.substring(0, i).trim() : null;
    final value = label == null ? d : d.substring(i + 2).trim();
    return pw.Container(
      padding: const pw.EdgeInsets.fromLTRB(8, 3, 8, 4),
      decoration: pw.BoxDecoration(
        color: tintLight,
        border: pw.Border.all(color: rule, width: 0.6),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(9)),
      ),
      child: pw.Row(
        mainAxisSize: pw.MainAxisSize.min,
        children: [
          if (label != null) ...[
            text('$label:', st(size: size, color: muted)),
            pw.SizedBox(width: 4),
          ],
          // القيمة بترتيب الجملة العربيّة ولو بلا حرفٍ عربيّ: «2026-08-01 ← 2026-11-26» يُقرأ من اليمين كما على الشاشة
          pw.Flexible(child: rtl(value, st(size: size, bold: label != null))),
        ],
      ),
    );
  }

  static PdfColor toneInk(PdfTone t) => switch (t) {
        PdfTone.good => green,
        PdfTone.bad => red,
        PdfTone.warn => amber,
        PdfTone.plain => ink,
      };

  static PdfColor toneBg(PdfTone t) => switch (t) {
        PdfTone.good => greenTint,
        PdfTone.bad => redTint,
        PdfTone.warn => amberTint,
        PdfTone.plain => tintLight,
      };

  /// بطاقة ملخّص: العنوان صغيراً والقيمة كبيرة.
  static pw.Widget statCard(PdfStat s, {double valueSize = 13}) => pw.Container(
        padding: const pw.EdgeInsets.fromLTRB(10, 7, 10, 8),
        decoration: pw.BoxDecoration(
          color: toneBg(s.tone),
          border: pw.Border.all(color: rule, width: 0.6),
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          mainAxisSize: pw.MainAxisSize.min,
          children: [
            text(s.label, st(size: 8.5, color: muted)),
            pw.SizedBox(height: 3),
            text(s.value, st(size: valueSize, bold: true, color: toneInk(s.tone))),
            if ((s.hint ?? '').trim().isNotEmpty) ...[
              pw.SizedBox(height: 2),
              text(s.hint!.trim(), st(size: 7.5, color: muted)),
            ],
          ],
        ),
      );

  /// بطاقات الملخّص أسطراً متساوية العرض ([perRow] في السطر).
  static pw.Widget statGrid(List<PdfStat> stats, {int perRow = 4, double valueSize = 13}) {
    final rows = <pw.Widget>[];
    for (var i = 0; i < stats.length; i += perRow) {
      final chunk = stats.sublist(i, i + perRow > stats.length ? stats.length : i + perRow);
      rows.add(pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          for (var j = 0; j < perRow; j++) ...[
            if (j > 0) pw.SizedBox(width: 6),
            pw.Expanded(child: j < chunk.length ? statCard(chunk[j], valueSize: valueSize) : pw.SizedBox()),
          ],
        ],
      ));
    }
    return pw.Column(children: [
      for (var i = 0; i < rows.length; i++) ...[
        if (i > 0) pw.SizedBox(height: 6),
        rows[i],
      ],
    ]);
  }

  /// عنوان قسم: خطٌّ رأسيّ بلون الهويّة ثمّ الاسم، و[trailing] على اليسار.
  static pw.Widget sectionTitle(String title, {pw.Widget? trailing, double size = 11}) => pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.Container(width: 3, height: size + 3, color: brand),
          pw.SizedBox(width: 6),
          pw.Expanded(child: pw.Align(alignment: pw.Alignment.centerRight, child: text(title, st(size: size, bold: true)))),
          if (trailing != null) trailing,
        ],
      );

  /// رأس الصفحات بعد الأولى: العنوان والفترة بسطرٍ واحد.
  static pw.Widget runningHeader(String title, {String? subtitle}) => pw.Container(
        margin: const pw.EdgeInsets.only(bottom: 8),
        padding: const pw.EdgeInsets.only(bottom: 4),
        decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: brand, width: 1))),
        child: pw.Row(children: [
          text(title, st(size: 10, bold: true, color: brand)),
          if ((subtitle ?? '').trim().isNotEmpty) ...[
            pw.SizedBox(width: 8),
            pw.Expanded(child: pw.Align(alignment: pw.Alignment.centerRight, child: text(subtitle!.trim(), st(size: 9, color: muted)))),
          ] else
            pw.Spacer(),
        ]),
      );

  /// التذييل: اسم التطبيق، رقم الصفحة، ووقت الطباعة.
  static pw.Widget footer(pw.Context ctx, {required DateTime printedAt}) => pw.Container(
        margin: const pw.EdgeInsets.only(top: 8),
        padding: const pw.EdgeInsets.only(top: 4),
        decoration: const pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(color: rule, width: 0.6))),
        child: pw.Row(children: [
          pw.Text(appName, style: st(size: 8, color: muted, bold: true), textDirection: pw.TextDirection.ltr),
          pw.Expanded(
            child: pw.Center(child: rtl('صفحة ${ctx.pageNumber} من ${ctx.pagesCount}', st(size: 8, color: muted), align: pw.TextAlign.center)),
          ),
          rtl('طبع ${stamp(printedAt)}', st(size: 8, color: muted)),
        ]),
      );
}
