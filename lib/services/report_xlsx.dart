import 'dart:typed_data';

import 'package:archive/archive.dart';

import 'pdf_kit.dart';

/// ملفّ Excel حقيقيّ (xlsx) للتقارير — ٢٦ نوفمبر (المالك بعد تصميم الـPDF: «والاكسل هم رتبته بالتقارير؟»).
///
/// كان زرّ «Excel» يكتب CSV: يفتحه Excel من اليسار بلا تنسيق، والمبالغ بلا فواصل، والهاتف «07701234567» يفقد صفره الأوّل. الآن ورقةٌ
/// من اليمين لليسار بنفس ترتيب الـPDF: العنوان والفترة ووقت الطباعة، الفلاتر سطراً سطراً («ناقص» بلون التنبيه)، بطاقات الشاشة
/// ([PdfStat] كما هي — لا يُجمع عمود)، رأس الجدول بلون الهويّة وفلترته، أعمدة المال أرقامٌ حقيقيّة بفواصل (السالب أحمر)، والعدّ أرقام،
/// وما سواهما نصٌّ كما هو. والطباعة منه: أفقيّ من ستّة أعمدة، بعرض الصفحة، ورأس الجدول يتكرّر.
///
/// المحتوى نفسه ما على الشاشة حرفاً ([ReportExportActions] تمرّر الصفوف المفلترة كاملة) — التصميم وحده تغيّر.
class ReportXlsx {
  ReportXlsx._();

  static const mime = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';

  // أنماط الخلايا — فهارس cellXfs في [_stylesXml] بالترتيب نفسه.
  static const sTitle = 1, sMuted = 2, sWarn = 3, sHead = 4, sText = 5, sTextZ = 6, sMoney = 7, sMoneyZ = 8, sMoneyDec = 9,
      sMoneyDecZ = 10, sCount = 11, sCountZ = 12, sSumLabel = 13, sSumPlain = 14, sSumGood = 15, sSumBad = 16, sSumWarn = 17, sFoot = 18,
      sTextLtr = 19, sTextLtrZ = 20;

  static final _int = RegExp(r'^-?\d+$');
  static final _num = RegExp(r'^-?\d+(\.\d+)?$');
  static final _count = RegExp(r'^(0|-?[1-9]\d{0,8})$');
  static final _minus = String.fromCharCode(0x2212);
  static final _isoDate = RegExp(r'\b(\d{4})-(\d{2})-(\d{2})\b');

  /// سطور الرأس (العنوان، الفترة، الفلاتر، البطاقات): التاريخ بشرطةٍ بعد حرفٍ عربيّ تنقلب أجزاؤه في Excel كما في المتصفّح (قاعدة
  /// W2: «2026-11-01» ⇒ «01-11-2026») — بالشرطة المائلة يبقى رقماً واحداً («2026/11/01»)، كما يكتبه الموقع. خلايا الجدول كما هي.
  static String headText(String s) => PdfKit.isArabic(s) ? s.replaceAllMapped(_isoDate, (m) => '${m[1]}/${m[2]}/${m[3]}') : s;

  /// اسم العمود: 0 ⇒ A، 25 ⇒ Z، 26 ⇒ AA.
  static String colName(int i) {
    var n = i + 1;
    var s = '';
    while (n > 0) {
      final r = (n - 1) % 26;
      s = String.fromCharCode(65 + r) + s;
      n = (n - 1) ~/ 26;
    }
    return s;
  }

  /// نصٌّ صالحٌ داخل XML: بلا محارف الاتّجاه (لا شكل لها) ولا محارف التحكّم الممنوعة في XML.
  static String clean(String s) => String.fromCharCodes(PdfKit.plain(s).runes.where((r) =>
      r == 9 || r == 10 || r == 13 || (r >= 32 && r != 0xFFFE && r != 0xFFFF && (r < 0xD800 || r > 0xDFFF))));

  static String _esc(String s) =>
      clean(s).replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;');

  /// قيمة عمود المال رقماً — «45000.0» و«-125,000» و«−5000» ⇒ رقم؛ غير ذلك (نصّ، فارغ) ⇒ null فيبقى نصّاً كما هو.
  static num? moneyValue(String raw) {
    final s = PdfKit.plain(raw).trim().replaceAll(',', '').replaceAll(_minus, '-');
    if (s.isEmpty || !_num.hasMatch(s)) return null;
    if (_int.hasMatch(s)) return int.tryParse(s);
    final d = double.tryParse(s);
    if (d == null) return null;
    return d == d.roundToDouble() && d.abs() < 9e15 ? d.toInt() : d;
  }

  /// عمود عدٍّ: كلّ قيمه أعدادٌ صحيحة بلا صفرٍ أوّل (لا هاتف «0770…» ولا رمزٌ طويل) ⇒ أرقامٌ تُجمع في Excel.
  static bool countColumn(List<List<String>> rows, int i) {
    var any = false;
    for (final r in rows) {
      final v = i < r.length ? PdfKit.plain(r[i]).trim() : '';
      if (v.isEmpty) continue;
      if (!_count.hasMatch(v)) return false;
      any = true;
    }
    return any;
  }

  static int _len(String s) => clean(s).runes.length;

  static Uint8List build({
    required String title,
    String? subtitle,
    List<String> details = const [],
    required List<String> columns,
    required List<List<String>> rows,
    List<bool>? money,
    List<PdfStat> summary = const [],
    DateTime? printedAt,
    String sheetName = 'التقرير',
  }) {
    final at = printedAt ?? DateTime.now();
    final n = columns.isEmpty ? 1 : columns.length;
    final isMoney = [for (var i = 0; i < columns.length; i++) money != null && i < money.length && money[i]];
    final isCount = [for (var i = 0; i < columns.length; i++) !isMoney[i] && countColumn(rows, i)];
    final out = StringBuffer();
    final widths = List<double>.filled(n, 8);
    void fit(int c, int chars, {double cap = 50}) {
      if (c >= widths.length) return;
      final w = (chars * 1.1 + 2).clamp(8, cap).toDouble();
      if (w > widths[c]) widths[c] = w;
    }

    var r = 0;
    String cellText(int c, String v, int s) => '<c r="${colName(c)}$r" s="$s" t="inlineStr"><is><t xml:space="preserve">${_esc(v)}</t></is></c>';
    String cellNum(int c, num v, int s) => '<c r="${colName(c)}$r" s="$s"><v>$v</v></c>';
    void row(String cells, {double? ht}) {
      out.write('<row r="$r"${ht == null ? '' : ' ht="$ht" customHeight="1"'}>$cells</row>');
    }

    // ── الرأس: العنوان، ثمّ الفترة ووقت الطباعة، ثمّ الفلاتر سطراً سطراً
    r++;
    row(cellText(0, headText(title), sTitle), ht: 26);
    r++;
    row(cellText(0, headText([if ((subtitle ?? '').trim().isNotEmpty) subtitle!.trim(), 'طبع ${PdfKit.stamp(at)}', PdfKit.appName].join('  ·  ')), sMuted));
    for (final d in details) {
      if (d.trim().isEmpty) continue;
      r++;
      row(cellText(0, headText(d.trim()), RegExp(r'^(ناقص|خارج)').hasMatch(d.trim()) ? sWarn : sMuted));
    }
    // ── بطاقات الشاشة: صفّ العناوين ثمّ صفّ القيم، [n] بطاقةً في الصفّ
    if (summary.isNotEmpty) {
      r++;
      row('');
      for (var i = 0; i < summary.length; i += n) {
        final chunk = summary.sublist(i, i + n > summary.length ? summary.length : i + n);
        r++;
        row([for (var j = 0; j < chunk.length; j++) cellText(j, headText(chunk[j].label), sSumLabel)].join(), ht: 20);
        r++;
        row([
          for (var j = 0; j < chunk.length; j++)
            cellText(
                j,
                headText(chunk[j].value),
                switch (chunk[j].tone) {
                  PdfTone.good => sSumGood,
                  PdfTone.bad => sSumBad,
                  PdfTone.warn => sSumWarn,
                  PdfTone.plain => sSumPlain,
                }),
        ].join(), ht: 24);
        for (var j = 0; j < chunk.length; j++) {
          fit(j, _len(chunk[j].label), cap: 30);
          fit(j, _len(chunk[j].value) + 2, cap: 30);
        }
      }
    }
    r++;
    row('');
    // ── الجدول: الرأس بلون الهويّة، ثمّ الصفوف بتناوب
    r++;
    final head = r;
    row([for (var c = 0; c < columns.length; c++) cellText(c, columns[c], sHead)].join(), ht: 30);
    for (var c = 0; c < columns.length; c++) {
      fit(c, (_len(columns[c]) * 0.9).round() + 2, cap: 24);
    }
    for (var i = 0; i < rows.length; i++) {
      final z = i.isOdd;
      final cells = StringBuffer();
      r++;
      for (var c = 0; c < columns.length; c++) {
        final raw = c < rows[i].length ? rows[i][c] : '';
        if (PdfKit.plain(raw).trim().isEmpty) continue;
        final m = isMoney[c] ? moneyValue(raw) : null;
        if (m != null) {
          final dec = m is double;
          cells.write(cellNum(c, m, dec ? (z ? sMoneyDecZ : sMoneyDec) : (z ? sMoneyZ : sMoney)));
          if (i < 1000) fit(c, PdfKit.amount(m).length + 2);
        } else if (isCount[c]) {
          cells.write(cellNum(c, int.parse(PdfKit.plain(raw).trim()), z ? sCountZ : sCount));
          if (i < 1000) fit(c, raw.trim().length + 2);
        } else {
          // بلا حرفٍ عربيّ (تاريخ، يوزر، هاتف) ⇒ قراءةٌ من اليسار: «2026-11-26 09:00» لا ينقلب في الورقة اليمنى
          final ltr = !PdfKit.isArabic(raw);
          cells.write(cellText(c, raw.trim(), ltr ? (z ? sTextLtrZ : sTextLtr) : (z ? sTextZ : sText)));
          if (i < 1000) fit(c, _len(raw.trim()));
        }
      }
      row(cells.toString());
    }
    final last = r;
    if (rows.isEmpty) {
      r++;
      row(cellText(0, 'لا بيانات بهذه الفلاتر', sMuted));
    }
    r++;
    row('');
    r++;
    row(cellText(0, 'عدد الصفوف: ${rows.length}', sFoot));

    final lastCol = colName(n - 1);
    final filter = rows.isEmpty ? null : 'A$head:$lastCol$last';
    final quoted = "'${sheetName.replaceAll("'", "''")}'";
    final wide = columns.length >= 6;
    final sheet = StringBuffer()
      ..write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
      ..write('<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
          'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">')
      ..write('<sheetPr><pageSetUpPr fitToPage="1"/></sheetPr>')
      ..write('<dimension ref="A1:$lastCol$r"/>')
      ..write('<sheetViews><sheetView rightToLeft="1" workbookViewId="0"><selection activeCell="A${head + 1}" sqref="A${head + 1}"/></sheetView></sheetViews>')
      ..write('<sheetFormatPr defaultRowHeight="18"/>')
      ..write('<cols>${[for (var c = 0; c < n; c++) '<col min="${c + 1}" max="${c + 1}" width="${widths[c].toStringAsFixed(1)}" customWidth="1"/>'].join()}</cols>')
      ..write('<sheetData>$out</sheetData>')
      ..write(filter == null ? '' : '<autoFilter ref="$filter"/>')
      ..write('<pageMargins left="0.4" right="0.4" top="0.5" bottom="0.6" header="0.3" footer="0.3"/>')
      ..write('<pageSetup paperSize="9" orientation="${wide ? 'landscape' : 'portrait'}" fitToWidth="1" fitToHeight="0"/>')
      ..write('<headerFooter><oddFooter>${_esc('&Lصفحة &P من &N&R${PdfKit.appName}')}</oddFooter></headerFooter>')
      ..write('</worksheet>');

    final workbook = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
        '<bookViews><workbookView xWindow="0" yWindow="0" windowWidth="28800" windowHeight="16000"/></bookViews>'
        '<sheets><sheet name="${_esc(sheetName)}" sheetId="1" r:id="rId1"/></sheets>'
        '<definedNames>'
        '${filter == null ? '' : '<definedName name="_xlnm._FilterDatabase" localSheetId="0" hidden="1">${_esc(quoted)}!\$A\$$head:\$$lastCol\$$last</definedName>'}'
        '<definedName name="_xlnm.Print_Titles" localSheetId="0">${_esc(quoted)}!\$$head:\$$head</definedName>'
        '</definedNames>'
        '</workbook>';

    final created = at.toUtc().toIso8601String().split('.').first;
    final parts = <String, String>{
      '[Content_Types].xml': '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
          '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
          '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
          '<Default Extension="xml" ContentType="application/xml"/>'
          '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
          '<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'
          '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>'
          '<Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>'
          '<Override PartName="/docProps/app.xml" ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/>'
          '</Types>',
      '_rels/.rels': '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
          '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
          '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>'
          '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>'
          '<Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties" Target="docProps/app.xml"/>'
          '</Relationships>',
      'docProps/core.xml': '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
          '<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" '
          'xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/" '
          'xmlns:dcmitype="http://purl.org/dc/dcmitype/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">'
          '<dc:title>${_esc(title)}</dc:title><dc:creator>${PdfKit.appName}</dc:creator>'
          '<dcterms:created xsi:type="dcterms:W3CDTF">${created}Z</dcterms:created>'
          '</cp:coreProperties>',
      'docProps/app.xml': '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
          '<Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties">'
          '<Application>${PdfKit.appName}</Application></Properties>',
      'xl/workbook.xml': workbook,
      'xl/_rels/workbook.xml.rels': '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
          '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
          '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>'
          '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>'
          '</Relationships>',
      'xl/styles.xml': _stylesXml,
      'xl/worksheets/sheet1.xml': sheet.toString(),
    };
    final archive = Archive();
    parts.forEach((name, xml) => archive.addFile(ArchiveFile.string(name, xml)));
    return ZipEncoder().encodeBytes(archive);
  }

  static String _font(double sz, String rgb, {bool b = false}) =>
      '<font>${b ? '<b/>' : ''}<sz val="$sz"/><color rgb="$rgb"/><name val="Arial"/><family val="2"/></font>';
  static String _fill(String rgb) => '<fill><patternFill patternType="solid"><fgColor rgb="$rgb"/><bgColor indexed="64"/></patternFill></fill>';
  static String _border(String rgb) => '<border><left style="thin"><color rgb="$rgb"/></left><right style="thin"><color rgb="$rgb"/></right>'
      '<top style="thin"><color rgb="$rgb"/></top><bottom style="thin"><color rgb="$rgb"/></bottom><diagonal/></border>';
  static String _xf(int numFmt, int font, int fill, int border, {String align = ''}) =>
      '<xf numFmtId="$numFmt" fontId="$font" fillId="$fill" borderId="$border" xfId="0"'
      '${numFmt > 0 ? ' applyNumberFormat="1"' : ''}${font > 0 ? ' applyFont="1"' : ''}${fill > 0 ? ' applyFill="1"' : ''}'
      '${border > 0 ? ' applyBorder="1"' : ''}${align.isEmpty ? '/>' : ' applyAlignment="1"><alignment $align/></xf>'}';

  /// الخطوط: 0 عاديّ، 1 العنوان، 2 باهت، 3 رأس الجدول، 4 عنوان البطاقة، 5–8 قيمة البطاقة (عاديّ/جيّد/سيّئ/تنبيه)، 9 «ناقص».
  /// التعبئة: 2 الهويّة، 3 التناوب، 4 أخضر، 5 أحمر، 6 تنبيه. الحدود: 1 فاتح، 2 الهويّة.
  static final _stylesXml = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
      '<numFmts count="2"><numFmt numFmtId="164" formatCode="#,##0;[Red]-#,##0"/><numFmt numFmtId="165" formatCode="#,##0.00;[Red]-#,##0.00"/></numFmts>'
      '<fonts count="10">'
      '${_font(11, 'FF15201A')}${_font(15, 'FF103D2E', b: true)}${_font(10, 'FF5A6861')}${_font(11, 'FFFFFFFF', b: true)}'
      '${_font(10, 'FF5A6861', b: true)}${_font(12, 'FF15201A', b: true)}${_font(12, 'FF12704A', b: true)}${_font(12, 'FFB42318', b: true)}'
      '${_font(12, 'FF8A5300', b: true)}${_font(10, 'FF8A5300', b: true)}'
      '</fonts>'
      '<fills count="7"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill>'
      '${_fill('FF103D2E')}${_fill('FFF4F8F6')}${_fill('FFE5F3EB')}${_fill('FFFDECEA')}${_fill('FFFFF4DE')}</fills>'
      '<borders count="3"><border><left/><right/><top/><bottom/><diagonal/></border>${_border('FFD3DDD7')}${_border('FF103D2E')}</borders>'
      '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>'
      '<cellXfs count="21">'
      '${_xf(0, 0, 0, 0)}' // 0
      '${_xf(0, 1, 0, 0, align: 'vertical="center"')}' // 1 العنوان
      '${_xf(0, 2, 0, 0, align: 'vertical="center"')}' // 2 باهت
      '${_xf(0, 9, 6, 0, align: 'vertical="center"')}' // 3 «ناقص»
      '${_xf(0, 3, 2, 2, align: 'horizontal="center" vertical="center" wrapText="1"')}' // 4 رأس الجدول
      '${_xf(0, 0, 0, 1, align: 'vertical="center"')}' // 5 نصّ
      '${_xf(0, 0, 3, 1, align: 'vertical="center"')}' // 6 نصّ متناوب
      '${_xf(164, 0, 0, 1, align: 'vertical="center"')}' // 7 مال
      '${_xf(164, 0, 3, 1, align: 'vertical="center"')}' // 8 مال متناوب
      '${_xf(165, 0, 0, 1, align: 'vertical="center"')}' // 9 مال بكسور
      '${_xf(165, 0, 3, 1, align: 'vertical="center"')}' // 10 مال بكسور متناوب
      '${_xf(3, 0, 0, 1, align: 'vertical="center"')}' // 11 عدد
      '${_xf(3, 0, 3, 1, align: 'vertical="center"')}' // 12 عدد متناوب
      '${_xf(0, 4, 3, 1, align: 'horizontal="center" vertical="center" wrapText="1"')}' // 13 عنوان البطاقة
      '${_xf(0, 5, 3, 1, align: 'horizontal="center" vertical="center"')}' // 14 قيمة عاديّة
      '${_xf(0, 6, 4, 1, align: 'horizontal="center" vertical="center"')}' // 15 جيّدة
      '${_xf(0, 7, 5, 1, align: 'horizontal="center" vertical="center"')}' // 16 سيّئة
      '${_xf(0, 8, 6, 1, align: 'horizontal="center" vertical="center"')}' // 17 تنبيه
      '${_xf(0, 2, 0, 0)}' // 18 التذييل
      '${_xf(0, 0, 0, 1, align: 'horizontal="right" vertical="center" readingOrder="1"')}' // 19 نصٌّ لاتينيّ (من اليسار)
      '${_xf(0, 0, 3, 1, align: 'horizontal="right" vertical="center" readingOrder="1"')}' // 20 نصٌّ لاتينيّ متناوب
      '</cellXfs>'
      '<cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>'
      '</styleSheet>';
}
