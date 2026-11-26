import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../api/settlements_api.dart';
import 'auth_storage.dart';
import 'merged_mode.dart';
import 'pdf_kit.dart';
import 'print_output.dart';
import 'print_prefs.dart';

/// سند «تسوية الحساب» المطبوع — PDF مبنيّ مباشرةً بعناصر `pw` كالوصل
/// (انظر [PrintService]: WebView يتعطّل على بعض الأجهزة). الورق من
/// تفضيل الطباعة نفسه (حراري 80mm أو A4)، والخطّ خطّ التطبيق.
class SettlementPrint {
  SettlementPrint._();

  /// [companyKey] («كل الشركات»، ٩ نوفمبر — التحقّق الثاني من 179): صندوق شركةٍ غير المفتوحة ⇒ اسمها ومديرها على السند (كفاتورة
  /// البيع والوصل — [ReceiptService.identityFor])؛ بلاه الجلسة المفتوحة كما كانت. كان سند صندوق شركةٍ أخرى يُطبع باسم المفتوحة.
  static Future<PrintResult> printVoucher(SettlementRecord s, {String? companyKey}) async {
    try {
      final format = PrintPrefs.pageFormat;
      final merged = MergedMode.companyOf(companyKey);
      final company = merged?.name ?? await AuthStorage.readDisplayName();
      final manager = merged?.username ?? await AuthStorage.readAdminUsername();
      final doc = await _build(s, format, company: company, manager: manager);
      // الهاتف: «صورة» للمشاركة أو الطباعة (٨ نوفمبر)
      return PrintOutput.sendOrShare(
        await PrintDoc.of(
          doc,
          name: s.isOpening ? 'Account-Opening' : 'Settlement-${s.number}',
          requested: format,
          // ويندوز: يُعاد رسمه على ورق الطابعة كالوصل ([PrintOutput.bytesFor]).
          refit: (paper) async => (await _build(s, format, company: company, manager: manager, paper: paper)).save(),
          // طابعة الوصولات بالهاتف (٩ نوفمبر): لفّةً على ورقها — ولو كان اختيار الطباعة A4.
          roll: (paper) async =>
              (await _build(s, PdfPageFormat.roll80, company: company, manager: manager, paper: paper)).save(),
        ),
        title: s.isOpening ? 'سند فتح الحساب' : 'سند التسوية',
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[SettlementPrint] failed: $e');
      return PrintResult.failed('$e');
    }
  }

  /// السند نفسه بلا طباعة — للاختبار وصور التصميم.
  @visibleForTesting
  static Future<pw.Document> buildForTest(SettlementRecord s, PdfPageFormat format,
          {String? company, String? manager, DateTime? printedAt}) =>
      _build(s, format, company: company, manager: manager, printedAt: printedAt);

  static String _when(DateTime? d) => d == null ? '—' : PdfKit.stamp(d);

  /// ما دخل الصندوق وما خرج منه — كلّ مجموعٍ بإشارته في الجهة الصحيحة (إلغاءٌ أكبر من أصله ⇒ الجهة الأخرى).
  /// المتوقّع عند الخادم (server/accountSettlements.js) = المدوَّر + الداخل − الخارج.
  @visibleForTesting
  static ({List<SettleLine> ins, List<SettleLine> outs}) flows(SettlementRecord s) {
    final ins = <SettleLine>[
      SettleLine('تفعيلات نقديّة', s.cashActivations.count, s.cashActivations.sum),
      SettleLine('تسديد ديون', s.debtPayments.count, s.debtPayments.sum),
      if (s.salesCash.count > 0) SettleLine('بيع مواد', s.salesCash.count, s.salesCash.sum),
    ];
    final outs = <SettleLine>[SettleLine('مصاريف', s.expenses.count, s.expenses.sum)];
    void signed(MoneyCount m, String inLabel, String outLabel) {
      if (m.count <= 0) return;
      m.sum < 0 ? outs.add(SettleLine(outLabel, m.count, -m.sum)) : ins.add(SettleLine(inLabel, m.count, m.sum));
    }

    // «سحب من الحوالات» (زين كاش/ماستر/أخرى ⇒ الصندوق) — وإلغاؤه أكبر ⇒ خارج
    signed(s.transferWithdrawals, 'سحب من الحوالات', 'إلغاء سحب من الحوالات');
    // «كاش المدراء يدخل الصندوق»: صافي نقد المدراء الفرعيّين — دخل (شحنٌ نقديّ وتسديد) أو أُعيد (سحب رصيد)
    signed(s.managerMoves, 'من المدراء الفرعيّين', 'أعيد للمدراء الفرعيّين');
    // «حركات الموظف»: صافيها على الصندوق — خرج (سلف وقروض) أو عاد (تسديد، استقطاع رواتب)
    signed(s.employeeMoves, 'رجع من سلف الموظفين', 'سلف وقروض الموظفين');
    if (s.goodsPurchases.count > 0) {
      s.goodsPurchases.sum >= 0
          ? outs.add(SettleLine('شراء مواد', s.goodsPurchases.count, s.goodsPurchases.sum))
          : ins.add(SettleLine('استرجاع من المورّد', s.goodsPurchases.count, -s.goodsPurchases.sum));
    }
    return (ins: ins, outs: outs);
  }

  /// معادلة «المدوَّر + دخل − خرج = المتوقّع» تُطبع حين تطابق رقم الخادم وحده — سجلٌّ بحقولٍ ناقصة لا يطبع حساباً خاطئاً
  /// (٢٦ نوفمبر: تطابق كلّ تسويات الإنتاج الـ٩٣).
  @visibleForTesting
  static bool balancedOf(SettlementRecord s) {
    final f = flows(s);
    final inSum = f.ins.fold<num>(0, (a, l) => a + l.amount);
    final outSum = f.outs.fold<num>(0, (a, l) => a + l.amount);
    return (s.openingBalance + inSum - outSum - s.expected).abs() < 1;
  }

  /// [paper] ورق الطابعة كما أرسله النظام (ويندوز): السند بعرضه وحواشٍ لا تقلّ عن حواشيه غير المطبوعة.
  ///
  /// ٢٦ نوفمبر (المالك: «تصميم … التسويه كلش مخزي … حسّن التصميم اكثر ومعلومات اوضح»): A4 بشريط العنوان والفترة، ثلاثة أرقامٍ
  /// كبيرة (المتوقّع، المستلَم، المُرحَّل)، «دخل الصندوق» و«خرج من الصندوق» عمودين بمجموعيهما، ومعادلة المتوقّع حين تطابق رقم
  /// الخادم؛ والكاشير 80mm أبيض وأسود بالترتيب نفسه. العربيّ كلّه عبر [PdfKit.rtl] (كان «مدوَّر» و«المُرحَّل» مربّعاً فارغاً و«ع.د»
  /// مقلوبة).
  static Future<pw.Document> _build(
    SettlementRecord s,
    PdfPageFormat format, {
    String? company,
    String? manager,
    PdfPageFormat? paper,
    DateTime? printedAt,
  }) async {
    final doc = pw.Document(theme: await PdfFonts.theme());
    final pos = format.width <= PdfPageFormat.roll80.width + 5;
    final at = printedAt ?? DateTime.now();
    // الكاشير: ٤٫٥ ملم جانباً — حواشي الطابعة الحراريّة لا تُطبع.
    final own = pos ? const pw.EdgeInsets.symmetric(horizontal: 12.75, vertical: 12) : const pw.EdgeInsets.fromLTRB(30, 28, 30, 22);
    doc.addPage(
      pw.Page(
        pageFormat: paper == null ? format : PdfPageFormat(paper.width, pos ? double.infinity : paper.height),
        margin: paper == null
            ? own
            : pw.EdgeInsets.fromLTRB(
                math.max(own.left, paper.marginLeft),
                math.max(own.top, paper.marginTop),
                math.max(own.right, paper.marginRight),
                math.max(own.bottom, paper.marginBottom),
              ),
        textDirection: pw.TextDirection.rtl,
        build: (context) => pos
            ? _roll(s, company: company, manager: manager, at: at)
            : _a4(s, company: company, manager: manager, at: at),
      ),
    );
    return doc;
  }

  // ═══════════════ A4 ═══════════════

  static pw.Widget _a4(SettlementRecord s, {String? company, String? manager, required DateTime at}) {
    final f = flows(s);
    final inSum = f.ins.fold<num>(0, (a, l) => a + l.amount);
    final outSum = f.outs.fold<num>(0, (a, l) => a + l.amount);
    final balanced = balancedOf(s);
    final employees = s.collectors.where((c) => !c.isManager).isNotEmpty;
    final chips = <String>[
      if ((manager ?? '').isNotEmpty) 'المدير: $manager',
      if ((s.actingEmployeeUsername ?? '').isNotEmpty) 'نفّذها: ${s.actingEmployeeUsername}',
      if (!s.isOpening) 'عدد الحركات: ${s.moveCount}',
    ];
    pw.TextStyle t(double size, {PdfColor color = PdfKit.ink, bool bold = false}) => PdfKit.st(size: size, color: color, bold: bold);

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        PdfKit.band(
          over: company,
          title: s.isOpening ? 'بداية حساب الصندوق' : 'سند تسوية حساب',
          subtitle: s.isOpening ? 'يبدأ من ${_when(s.cutAt)}' : 'من ${_when(s.periodStartAt)}  إلى  ${_when(s.cutAt)}',
          side: [if (!s.isOpening && s.number != null) 'رقم السند ${s.number}', if (!s.isOpening) 'تسوية الصندوق'],
        ),
        if (s.isVoided) ...[pw.SizedBox(height: 8), _voidBanner(s, size: 10.5)],
        if (chips.isNotEmpty) ...[pw.SizedBox(height: 9), PdfKit.chips(chips, size: 9.5)],
        pw.SizedBox(height: 12),
        if (s.isOpening)
          PdfKit.statGrid([PdfStat('الرصيد الافتتاحيّ للصندوق', '${PdfKit.amount(s.openingBalance)} د.ع')], perRow: 1, valueSize: 18)
        else ...[
          PdfKit.statGrid(
            [
              PdfStat('المتوقّع في الصندوق', '${PdfKit.amount(s.expected)} د.ع'),
              PdfStat('المستلَم فعلاً', '${PdfKit.amount(s.received)} د.ع', tone: PdfTone.good),
              PdfStat('المُرحَّل للفترة التالية', '${PdfKit.amount(s.carried)} د.ع',
                  tone: s.carried.round() == 0 ? PdfTone.plain : PdfTone.warn,
                  hint: s.carried.round() == 0 ? null : 'يبقى بالصندوق ويبدأ به الحساب التالي'),
            ],
            perRow: 3,
            valueSize: 16,
          ),
          pw.SizedBox(height: 12),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(child: _flowBox('دخل الصندوق', f.ins, inSum, PdfKit.green)),
              pw.SizedBox(width: 10),
              pw.Expanded(child: _flowBox('خرج من الصندوق', f.outs, outSum, PdfKit.red)),
            ],
          ),
          pw.SizedBox(height: 10),
          if (balanced)
            _equation(s, inSum, outSum)
          else if (s.openingBalance != 0)
            pw.Row(children: [
              PdfKit.rtl('رصيد مدوَّر من التسوية السابقة:', t(10, color: PdfKit.muted)),
              pw.SizedBox(width: 6),
              PdfKit.money(s.openingBalance, size: 10, bold: true),
            ]),
          if (employees) ...[
            pw.SizedBox(height: 14),
            PdfKit.sectionTitle('حصّة المنفّذين'),
            pw.SizedBox(height: 6),
            _collectorsTable(s),
          ],
          if (s.newDebts.sum > 0) ...[
            pw.SizedBox(height: 10),
            _infoBox(
              'ديون جديدة على المشتركين خلال الفترة: ${PdfKit.amount(s.newDebts.sum)} د.ع (${s.newDebts.count}) — لا تدخل الصندوق',
              PdfKit.amberTint,
              PdfKit.amber,
            ),
          ],
        ],
        if ((s.note ?? '').isNotEmpty) ...[
          pw.SizedBox(height: 10),
          _infoBox('ملاحظة: ${s.note}', PdfKit.tintLight, PdfKit.ink),
        ],
        if (!s.isOpening) ...[
          pw.SizedBox(height: 30),
          pw.Row(children: [
            pw.Expanded(child: _signature('المسلِّم', 10)),
            pw.SizedBox(width: 40),
            pw.Expanded(child: _signature('المستلِم', 10)),
          ]),
        ],
        pw.Spacer(),
        pw.Container(
          padding: const pw.EdgeInsets.only(top: 4),
          decoration: const pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(color: PdfKit.rule, width: 0.6))),
          child: pw.Row(children: [
            pw.Text(PdfKit.appName, style: t(8, color: PdfKit.muted, bold: true), textDirection: pw.TextDirection.ltr),
            pw.Spacer(),
            PdfKit.rtl('طبع ${PdfKit.stamp(at)}', t(8, color: PdfKit.muted)),
          ]),
        ),
      ],
    );
  }

  static pw.Widget _flowBox(String title, List<SettleLine> lines, num total, PdfColor accent) => pw.Container(
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfKit.rule, width: 0.7),
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Container(
              padding: const pw.EdgeInsets.fromLTRB(10, 6, 10, 6),
              decoration: const pw.BoxDecoration(
                color: PdfKit.tint,
                borderRadius: pw.BorderRadius.only(topLeft: pw.Radius.circular(6), topRight: pw.Radius.circular(6)),
              ),
              child: pw.Row(children: [
                pw.Container(width: 3, height: 13, color: accent),
                pw.SizedBox(width: 6),
                PdfKit.rtl(title, PdfKit.st(size: 10.5, bold: true)),
                pw.Spacer(),
                PdfKit.money(total, size: 11, bold: true, color: accent),
              ]),
            ),
            for (var i = 0; i < lines.length; i++)
              pw.Container(
                padding: const pw.EdgeInsets.fromLTRB(10, 5, 10, 5),
                decoration: i == 0
                    ? null
                    : const pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(color: PdfKit.rule, width: 0.4))),
                child: pw.Row(children: [
                  pw.Expanded(
                    child: pw.Row(children: [
                      pw.Flexible(child: PdfKit.rtl(lines[i].label, PdfKit.st(size: 9.5))),
                      if (lines[i].count > 0) ...[
                        pw.SizedBox(width: 5),
                        _countPill(lines[i].count),
                      ],
                    ]),
                  ),
                  pw.SizedBox(width: 6),
                  PdfKit.money(lines[i].amount, size: 9.5, unit: false),
                ]),
              ),
          ],
        ),
      );

  static pw.Widget _countPill(int n) => pw.Container(
        padding: const pw.EdgeInsets.fromLTRB(5, 1, 5, 1.5),
        decoration: const pw.BoxDecoration(color: PdfKit.tintLight, borderRadius: pw.BorderRadius.all(pw.Radius.circular(6))),
        child: pw.Text('$n', style: PdfKit.st(size: 7.5, color: PdfKit.muted), textDirection: pw.TextDirection.ltr),
      );

  /// «رصيد مدوَّر + دخل − خرج = المتوقّع» — يُقرأ من اليمين.
  static pw.Widget _equation(SettlementRecord s, num inSum, num outSum) {
    pw.Widget part(String label, num v, {bool strong = false}) => pw.Column(
          mainAxisSize: pw.MainAxisSize.min,
          children: [
            PdfKit.rtl(label, PdfKit.st(size: 8, color: PdfKit.muted), align: pw.TextAlign.center),
            pw.SizedBox(height: 1),
            pw.Text(PdfKit.amount(v), style: PdfKit.st(size: strong ? 11 : 10, bold: true), textDirection: pw.TextDirection.ltr),
          ],
        );
    pw.Widget op(String o) => pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 8),
          child: pw.Text(o, style: PdfKit.st(size: 13, color: PdfKit.muted, bold: true), textDirection: pw.TextDirection.ltr),
        );
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: pw.BoxDecoration(
        color: PdfKit.tintLight,
        border: pw.Border.all(color: PdfKit.rule, width: 0.6),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.center,
        children: [
          if (s.openingBalance != 0) ...[part('رصيد مدوَّر', s.openingBalance), op('+')],
          part('دخل', inSum),
          op('−'),
          part('خرج', outSum),
          op('='),
          part('المتوقّع في الصندوق', s.expected, strong: true),
        ],
      ),
    );
  }

  static String _collectorName(SettleCollector c) => c.isManager ? 'المدير' : (c.name ?? c.username ?? '#${c.employeeId}');

  static String _collectorCounts(SettleCollector c) => [
        if (c.cashActivations.count > 0) 'تفعيلات ${c.cashActivations.count}',
        if (c.debtPayments.count > 0) 'تسديد ${c.debtPayments.count}',
        if (c.salesCash.count > 0) 'بيع ${c.salesCash.count}',
        if (c.expenses.count > 0) 'مصاريف ${c.expenses.count}',
      ].join(' · ');

  static pw.Widget _collectorsTable(SettlementRecord s) => pw.Container(
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfKit.rule, width: 0.7),
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
        ),
        child: pw.Column(children: [
          for (var i = 0; i < s.collectors.length; i++)
            pw.Container(
              padding: const pw.EdgeInsets.fromLTRB(10, 5, 10, 5),
              decoration: pw.BoxDecoration(
                color: i.isOdd ? PdfKit.tintLight : null,
                border: i == 0 ? null : const pw.Border(top: pw.BorderSide(color: PdfKit.rule, width: 0.4)),
              ),
              child: pw.Row(children: [
                pw.Expanded(
                  child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                    PdfKit.text(_collectorName(s.collectors[i]), PdfKit.st(size: 10, bold: true)),
                    if (_collectorCounts(s.collectors[i]).isNotEmpty)
                      PdfKit.rtl(_collectorCounts(s.collectors[i]), PdfKit.st(size: 8, color: PdfKit.muted)),
                  ]),
                ),
                PdfKit.money(s.collectors[i].net, size: 10.5, bold: true),
              ]),
            ),
        ]),
      );

  static pw.Widget _infoBox(String text, PdfColor bg, PdfColor ink) => pw.Container(
        padding: const pw.EdgeInsets.fromLTRB(10, 6, 10, 7),
        decoration: pw.BoxDecoration(
          color: bg,
          border: pw.Border.all(color: PdfKit.rule, width: 0.6),
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
        ),
        child: pw.Align(alignment: pw.Alignment.centerRight, child: PdfKit.text(text, PdfKit.st(size: 9.5, color: ink))),
      );

  static pw.Widget _voidBanner(SettlementRecord s, {required double size}) {
    final by = [if ((s.voidedBy ?? '').isNotEmpty) s.voidedBy!, if (s.voidedAt != null) PdfKit.stamp(s.voidedAt!)].join(' · ');
    return pw.Container(
      padding: const pw.EdgeInsets.fromLTRB(10, 6, 10, 7),
      decoration: pw.BoxDecoration(
        color: PdfKit.redTint,
        border: pw.Border.all(color: PdfKit.red, width: 1.1),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
      ),
      child: pw.Column(children: [
        PdfKit.rtl('تسوية ملغاة${(s.voidReason ?? '').trim().isEmpty ? '' : ' — ${s.voidReason!.trim()}'}',
            PdfKit.st(size: size, bold: true, color: PdfKit.red), align: pw.TextAlign.center),
        if (by.isNotEmpty) PdfKit.text('ألغاها $by', PdfKit.st(size: size - 2, color: PdfKit.red), align: pw.TextAlign.center),
      ]),
    );
  }

  // ═══════════════ الكاشير 80mm ═══════════════

  /// أبيض وأسود (الطابعة الحراريّة) بالترتيب نفسه: الأرقام الثلاثة أوّلاً، ثمّ الداخل والخارج بمجموعيهما.
  static pw.Widget _roll(SettlementRecord s, {String? company, String? manager, required DateTime at}) {
    const size = 9.5;
    final f = flows(s);
    final inSum = f.ins.fold<num>(0, (a, l) => a + l.amount);
    final outSum = f.outs.fold<num>(0, (a, l) => a + l.amount);
    final employees = s.collectors.where((c) => !c.isManager).isNotEmpty;
    pw.TextStyle t({double sz = size, bool bold = false}) => PdfKit.st(size: sz, bold: bold, color: PdfColors.black);
    pw.Widget row(String label, String value, {bool strong = false, double sz = size}) => pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
          child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Expanded(child: PdfKit.text(label, t(sz: sz, bold: strong))),
            pw.SizedBox(width: 6),
            PdfKit.text(value, t(sz: sz, bold: strong)),
          ]),
        );
    pw.Widget rule({double w = 0.7}) => pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 3),
          child: pw.Container(height: w, color: PdfColors.black),
        );
    pw.Widget head(String label, num total) => pw.Padding(
          padding: const pw.EdgeInsets.only(top: 3, bottom: 1),
          child: pw.Row(children: [
            pw.Expanded(child: PdfKit.rtl(label, t(bold: true))),
            pw.Text(PdfKit.amount(total), style: t(bold: true), textDirection: pw.TextDirection.ltr),
          ]),
        );
    String withCount(SettleLine l) => l.count > 0 ? '${l.label} (${l.count})' : l.label;

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        if ((company ?? '').trim().isNotEmpty) PdfKit.text(company!.trim(), t(sz: size + 1.5, bold: true), align: pw.TextAlign.center),
        pw.SizedBox(height: 2),
        PdfKit.rtl(
          s.isOpening ? 'بداية حساب الصندوق' : 'سند تسوية حساب رقم ${s.number ?? ''}',
          t(sz: 12.5, bold: true),
          align: pw.TextAlign.center,
        ),
        if (s.isVoided) ...[
          pw.SizedBox(height: 4),
          pw.Container(
            padding: const pw.EdgeInsets.all(4),
            decoration: pw.BoxDecoration(border: pw.Border.all(width: 1.2)),
            child: PdfKit.rtl('ملغاة${(s.voidReason ?? '').trim().isEmpty ? '' : ' — ${s.voidReason!.trim()}'}', t(bold: true),
                align: pw.TextAlign.center),
          ),
        ],
        rule(w: 1),
        if ((manager ?? '').isNotEmpty) row('المدير', manager!),
        if (!s.isOpening) row('من', _when(s.periodStartAt)),
        row(s.isOpening ? 'يبدأ من' : 'إلى', _when(s.cutAt)),
        if ((s.actingEmployeeUsername ?? '').isNotEmpty) row('نفّذها', s.actingEmployeeUsername!),
        rule(),
        if (s.isOpening)
          row('الرصيد الافتتاحيّ', '${PdfKit.amount(s.openingBalance)} د.ع', strong: true, sz: 11)
        else ...[
          row('المتوقّع في الصندوق', '${PdfKit.amount(s.expected)} د.ع', strong: true, sz: 11),
          row('المستلَم فعلاً', '${PdfKit.amount(s.received)} د.ع', strong: true, sz: 11),
          row('المُرحَّل للفترة التالية', '${PdfKit.amount(s.carried)} د.ع'),
          rule(),
          if (s.openingBalance != 0) row('رصيد مدوَّر', PdfKit.amount(s.openingBalance)),
          head('دخل الصندوق', inSum),
          for (final l in f.ins) row('  ${withCount(l)}', PdfKit.amount(l.amount)),
          head('خرج من الصندوق', outSum),
          for (final l in f.outs) row('  ${withCount(l)}', PdfKit.amount(l.amount)),
        ],
        if (!s.isOpening && employees) ...[
          rule(),
          PdfKit.rtl('حصّة المنفّذين', t(bold: true)),
          for (final c in s.collectors) row(_collectorName(c), PdfKit.amount(c.net)),
        ],
        if (!s.isOpening && s.newDebts.sum > 0) ...[
          rule(),
          PdfKit.rtl('ديون جديدة على المشتركين خلال الفترة (لا تدخل الصندوق): ${PdfKit.amount(s.newDebts.sum)} د.ع', t(sz: size - 0.5)),
        ],
        if ((s.note ?? '').isNotEmpty) ...[
          pw.SizedBox(height: 4),
          PdfKit.text('ملاحظة: ${s.note}', t()),
        ],
        if (!s.isOpening) ...[
          pw.SizedBox(height: 18),
          pw.Row(children: [
            pw.Expanded(child: _signature('المسلِّم', size, color: PdfColors.black)),
            pw.SizedBox(width: 12),
            pw.Expanded(child: _signature('المستلِم', size, color: PdfColors.black)),
          ]),
        ],
        pw.SizedBox(height: 8),
        PdfKit.rtl('طبع ${PdfKit.stamp(at)}', t(sz: size - 1), align: pw.TextAlign.center),
      ],
    );
  }

  static pw.Widget _signature(String label, double size, {PdfColor color = PdfKit.ink}) => pw.Column(
        children: [
          PdfKit.rtl(label, PdfKit.st(size: size, color: color, bold: true), align: pw.TextAlign.center),
          pw.SizedBox(height: 26),
          pw.Container(height: 0.8, color: color),
          pw.SizedBox(height: 2),
          PdfKit.rtl('الاسم والتوقيع', PdfKit.st(size: size - 2, color: color == PdfKit.ink ? PdfKit.muted : color), align: pw.TextAlign.center),
        ],
      );
}

/// سطرٌ من «دخل الصندوق» أو «خرج من الصندوق» في السند.
@immutable
class SettleLine {
  const SettleLine(this.label, this.count, this.amount);
  final String label;
  final int count;
  final num amount;
}
