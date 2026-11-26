import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/services/pdf_kit.dart';
import 'package:rad_mysvcs/services/report_xlsx.dart';
import 'package:xml/xml.dart';

/// ملفّ Excel للتقارير (٢٦ نوفمبر — المالك: «والاكسل هم رتبته بالتقارير؟»): xlsx حقيقيّ بدل CSV — من اليمين لليسار، رأسٌ ملوّن
/// بفلترة، المال أرقامٌ بفواصل والسالب أحمر، الهاتف نصّاً بصفره، والعدّ أرقام، وبطاقات الشاشة فوق الجدول. المحتوى لا يتغيّر.
void main() {
  Map<String, XmlDocument> parts(List<int> bytes) {
    final a = ZipDecoder().decodeBytes(bytes);
    return {
      for (final f in a.files)
        if (f.isFile) f.name: XmlDocument.parse(utf8.decode(f.content)),
    };
  }

  Map<String, XmlElement> cells(XmlDocument sheet) => {for (final c in sheet.findAllElements('c')) c.getAttribute('r')!: c};
  String? text(XmlElement c) => c.getAttribute('t') == 'inlineStr' ? c.findAllElements('t').first.innerText : null;
  String? num(XmlElement c) => c.getAttribute('t') == null ? c.getElement('v')?.innerText : null;
  int style(XmlElement c) => int.parse(c.getAttribute('s')!);

  final cols = ['اسم المشترك', 'اليوزر', 'الهاتف', 'المبلغ', 'كلفة الباقة', 'التاريخ', 'المشتركون'];
  final rows = [
    ['علي', 'sub1@x', '07701234567', '45000.0', '30,000', '2026-11-26 09:00', '12'],
    ['زينب', '11031', '07809999999', '-125000', '', '2026-11-25 10:00', '7'],
    ['حسن', 'sub3@x', '', '—', '15000', '2026-11-24 11:00', '0'],
  ];
  Map<String, XmlDocument> build({List<List<String>>? data, List<String>? details, List<PdfStat> summary = const [], List<String>? columns}) =>
      parts(ReportXlsx.build(
        title: 'التقرير المالي',
        subtitle: 'هذا الشهر · 2026/11/01 – 2026/11/26',
        details: details ?? const ['الموظف: الكلّ', 'ناقص: تعذّرت شركة'],
        columns: columns ?? cols,
        rows: data ?? rows,
        money: [for (final c in (columns ?? cols)) c == 'المبلغ' || c == 'كلفة الباقة'],
        summary: summary,
        printedAt: DateTime(2026, 11, 26, 5, 9),
      ));

  test('١ ملفّ xlsx صالح: الأجزاء كلّها XML سليم، والورقة من اليمين لليسار بفلترةٍ وطباعة', () {
    final p = build();
    expect(p.keys, containsAll(['[Content_Types].xml', '_rels/.rels', 'xl/workbook.xml', 'xl/_rels/workbook.xml.rels', 'xl/styles.xml',
        'xl/worksheets/sheet1.xml', 'docProps/core.xml', 'docProps/app.xml']));
    final sheet = p['xl/worksheets/sheet1.xml']!;
    expect(sheet.findAllElements('sheetView').single.getAttribute('rightToLeft'), '1');
    final head = cells(sheet).entries.firstWhere((e) => text(e.value) == 'اسم المشترك').key; // A{n}
    final n = int.parse(head.substring(1));
    expect(sheet.findAllElements('autoFilter').single.getAttribute('ref'), 'A$n:G${n + 3}');
    expect(sheet.findAllElements('pageSetup').single.getAttribute('orientation'), 'landscape', reason: 'سبعة أعمدة ⇒ أفقيّ');
    final wb = p['xl/workbook.xml']!;
    expect(wb.findAllElements('sheet').single.getAttribute('name'), 'التقرير');
    final names = {for (final d in wb.findAllElements('definedName')) d.getAttribute('name'): d.innerText};
    expect(names['_xlnm.Print_Titles'], "'التقرير'!\$$n:\$$n", reason: 'رأس الجدول يتكرّر بالطباعة');
    expect(names['_xlnm._FilterDatabase'], "'التقرير'!\$A\$$n:\$G\$${n + 3}");
    final styles = p['xl/styles.xml']!;
    expect(styles.findAllElements('cellXfs').single.findElements('xf').length, 21);
    expect(int.parse(styles.findAllElements('cellXfs').single.getAttribute('count')!), 21);
    expect(styles.findAllElements('fonts').single.findElements('font').length, int.parse(styles.findAllElements('fonts').single.getAttribute('count')!));
    expect(styles.findAllElements('fills').single.findElements('fill').length, int.parse(styles.findAllElements('fills').single.getAttribute('count')!));
  });

  test('٢ المال أرقامٌ حقيقيّة بنمط الفواصل (السالب أحمر)، والهاتف نصٌّ بصفره، والعدّ أرقام', () {
    final c = cells(build()['xl/worksheets/sheet1.xml']!);
    final n = int.parse(c.entries.firstWhere((e) => text(e.value) == 'اسم المشترك').key.substring(1));
    expect(num(c['D${n + 1}']!), '45000', reason: '«45000.0» ⇒ رقم');
    expect(style(c['D${n + 1}']!), ReportXlsx.sMoney);
    expect(num(c['E${n + 1}']!), '30000', reason: '«30,000» ⇒ رقم');
    expect(num(c['D${n + 2}']!), '-125000');
    expect(style(c['D${n + 2}']!), ReportXlsx.sMoneyZ, reason: 'الصفّ الثاني متناوب');
    expect(c.containsKey('E${n + 2}'), isFalse, reason: 'الفارغ بلا خليّة');
    expect(text(c['D${n + 3}']!), '—', reason: 'غير الرقم في عمود المال يبقى نصّاً');
    expect(text(c['C${n + 1}']!), '07701234567', reason: 'الهاتف نصٌّ — لا يفقد صفره');
    expect(text(c['B${n + 2}']!), '11031', reason: 'عمود اليوزر فيه نصوص ⇒ نصٌّ كلّه');
    expect(num(c['G${n + 1}']!), '12');
    expect(style(c['G${n + 1}']!), ReportXlsx.sCount);
    expect(num(c['G${n + 3}']!), '0');
    expect(text(c['F${n + 1}']!), '2026-11-26 09:00', reason: 'التاريخ كما هو');
    expect(style(c['F${n + 1}']!), ReportXlsx.sTextLtr, reason: 'بلا حرفٍ عربيّ ⇒ يُقرأ من اليسار فلا ينقلب الوقت والتاريخ');
    expect(style(c['A${n + 1}']!), ReportXlsx.sText, reason: 'العربيّ باتّجاه سياقه');
    expect(style(c['A$n']!), ReportXlsx.sHead);
  });

  test('٣ الرأس: العنوان والفترة والفلاتر، و«ناقص» بلون التنبيه، وبطاقات الشاشة بنبرتها', () {
    final c = cells(build(summary: const [
      PdfStat('الإيراد النقدي', '2,920,000 د.ع', tone: PdfTone.good),
      PdfStat('المصاريف', '789,000 د.ع', tone: PdfTone.bad),
      PdfStat('تفعيل بالدين', '320,000 د.ع', tone: PdfTone.warn),
      PdfStat('الحركات', '46'),
    ])['xl/worksheets/sheet1.xml']!);
    expect(text(c['A1']!), 'التقرير المالي');
    expect(style(c['A1']!), ReportXlsx.sTitle);
    expect(text(c['A2']!), contains('هذا الشهر · 2026/11/01 – 2026/11/26'));
    expect(text(c['A2']!), contains('طبع 2026/11/26 05:09'), reason: 'بالشرطة المائلة — W2 يقلب «2026-11-26» بعد حرفٍ عربيّ');
    expect(text(c['A3']!), 'الموظف: الكلّ');
    expect(style(c['A4']!), ReportXlsx.sWarn);
    final label = c.entries.firstWhere((e) => text(e.value) == 'الإيراد النقدي');
    expect(style(label.value), ReportXlsx.sSumLabel);
    final row = int.parse(label.key.substring(1));
    expect(text(c['A${row + 1}']!), '2,920,000 د.ع');
    expect(style(c['A${row + 1}']!), ReportXlsx.sSumGood);
    expect(style(c['B${row + 1}']!), ReportXlsx.sSumBad);
    expect(style(c['C${row + 1}']!), ReportXlsx.sSumWarn);
    expect(style(c['D${row + 1}']!), ReportXlsx.sSumPlain);
  });

  test('٤ النصّ آمن: محارف العزل والتحكّم تُحذف، و< & " تُهرَّب وتعود كما هي', () {
    final fsi = String.fromCharCode(0x2068), pdi = String.fromCharCode(0x2069), bell = String.fromCharCode(7);
    final c = cells(build(data: [
      ['<b>&"x"', 'u', '', '$fsi${String.fromCharCode(0x2212)}5,000$pdi', '', 'd$bell', '1'],
    ])['xl/worksheets/sheet1.xml']!);
    final n = int.parse(c.entries.firstWhere((e) => text(e.value) == 'اسم المشترك').key.substring(1));
    expect(text(c['A${n + 1}']!), '<b>&"x"');
    expect(num(c['D${n + 1}']!), '-5000', reason: 'السالب المعزول من الشاشة رقمٌ سالب');
    expect(text(c['F${n + 1}']!), 'd');
  });

  test('٥ تقريرٌ بلا صفوف: لا فلترة، وسطرٌ يقول ذلك؛ وخمسة أعمدة ⇒ طوليّ', () {
    final p = build(data: const [], columns: const ['التاريخ', 'البيان', 'مدين', 'دائن', 'الرصيد']);
    final sheet = p['xl/worksheets/sheet1.xml']!;
    expect(sheet.findAllElements('autoFilter'), isEmpty);
    expect(p['xl/workbook.xml']!.findAllElements('definedName').map((d) => d.getAttribute('name')), isNot(contains('_xlnm._FilterDatabase')));
    expect(cells(sheet).values.map(text), contains('لا بيانات بهذه الفلاتر'));
    expect(sheet.findAllElements('pageSetup').single.getAttribute('orientation'), 'portrait');
  });

  test('٦ أسماء الأعمدة بعد Z', () {
    expect([for (final i in [0, 25, 26, 51, 701, 702]) ReportXlsx.colName(i)], ['A', 'Z', 'AA', 'AZ', 'ZZ', 'AAA']);
  });

  test('٧ قيمة المال: الأرقام وحدها', () {
    expect(ReportXlsx.moneyValue('45000.0'), 45000);
    expect(ReportXlsx.moneyValue('12.5'), 12.5);
    expect(ReportXlsx.moneyValue('1,250,000'), 1250000);
    expect(ReportXlsx.moneyValue('45,000 د.ع'), isNull, reason: 'نصٌّ بعملة ⇒ يبقى نصّاً');
    expect(ReportXlsx.moneyValue(''), isNull);
    expect(ReportXlsx.countColumn(const [['07701'], ['12']], 0), isFalse, reason: 'صفرٌ أوّل ⇒ نصّ');
    expect(ReportXlsx.countColumn(const [[''], ['']], 0), isFalse);
  });
}
