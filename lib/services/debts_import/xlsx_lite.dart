import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

// ملفّ Excel (xlsx = zip + XML) — قراءة الورقة الأولى وكتابة ورقةٍ واحدة، لاستيراد/تصدير الديون (٢٣ نوفمبر). القراءة كما يقرؤها
// الموقع (SheetJS `sheet_to_json(ws, {header: 1, raw: true, defval: ''})` ثمّ `readSpreadsheetRows` في pages/DebtsImport.tsx):
// الأرقام قيماً لا نصّاً منسَّقاً («IQD 1.000» المنسَّق كان يصير 1)، الصحيح بلا كسور، والخلايا الفارغة '' بمواضعها، والصفوف الفارغة
// تُهمل. .xls/.ods لا تُقرأ هنا (يُقال للوكيل: احفظه xlsx أو csv).

/// نوع الملفّ من بايتاته الأولى لا من امتداده (`looksLikeSpreadsheet`).
enum SheetKind { xlsx, xls, ods, other }

SheetKind sheetKindOf(Uint8List bytes) {
  if (bytes.length >= 4 && bytes[0] == 0x50 && bytes[1] == 0x4b && bytes[2] == 0x03 && bytes[3] == 0x04) {
    // zip: xlsx أو ods — ods فيه «mimetype» أوّلاً
    try {
      final zip = ZipDecoder().decodeBytes(bytes);
      if (zip.findFile('xl/workbook.xml') != null) return SheetKind.xlsx;
      if (zip.findFile('content.xml') != null) return SheetKind.ods;
    } catch (_) {
      return SheetKind.other;
    }
    return SheetKind.other;
  }
  if (bytes.length >= 4 && bytes[0] == 0xd0 && bytes[1] == 0xcf && bytes[2] == 0x11 && bytes[3] == 0xe0) return SheetKind.xls;
  return SheetKind.other;
}

class XlsxReadError implements Exception {
  const XlsxReadError(this.message);
  final String message;
  @override
  String toString() => message;
}

String _text(ArchiveFile f) => utf8.decode(f.content as List<int>, allowMalformed: true);

/// عمود الخليّة من مرجعها («AB12» ⇒ 27) وصفّها (11) — من الصفر.
({int col, int row})? _ref(String r) {
  final m = RegExp(r'^\$?([A-Za-z]+)\$?(\d+)$').firstMatch(r.trim());
  if (m == null) return null;
  var c = 0;
  for (final ch in m[1]!.toUpperCase().codeUnits) {
    c = c * 26 + (ch - 64);
  }
  return (col: c - 1, row: int.parse(m[2]!) - 1);
}

/// نصّ عنصرٍ غنيّ (<si> / <is>): كلّ <t> فيه بالترتيب (بلا نصوص النطق <rPh>).
String _richText(XmlElement e) {
  final b = StringBuffer();
  void walk(XmlElement n) {
    for (final c in n.childElements) {
      if (c.name.local == 'rPh' || c.name.local == 'phoneticPr') continue;
      if (c.name.local == 't') {
        b.write(c.innerText);
      } else {
        walk(c);
      }
    }
  }

  walk(e);
  return b.toString();
}

/// رقمٌ كما يكتبه الموقع: صحيحٌ بلا كسور (`toFixed(0)`)، وغيره نصّه (`String(n)`).
String _numText(String v) {
  final n = double.tryParse(v.trim());
  if (n == null) return v.trim();
  if (n.isFinite && n == n.truncateToDouble() && n.abs() < 1e21) return n.toStringAsFixed(0);
  return n.toString();
}

/// صفوف الورقة الأولى نصوصاً — بمواضع أعمدتها من بداية مدى الورقة، والفارغة تُهمل.
List<List<String>> readXlsxRows(Uint8List bytes) {
  final Archive zip;
  try {
    zip = ZipDecoder().decodeBytes(bytes);
  } catch (_) {
    throw const XlsxReadError('الملف ليس Excel صالحاً');
  }
  final wbFile = zip.findFile('xl/workbook.xml');
  if (wbFile == null) throw const XlsxReadError('الملف ليس Excel (xlsx)');
  final wb = XmlDocument.parse(_text(wbFile));
  final sheet = wb.findAllElements('sheet').firstOrNull;
  if (sheet == null) return const [];
  // مسار الورقة الأولى من علاقات الكتاب (لا «sheet1.xml» افتراضاً)
  String? target;
  final rid = sheet.attributes.where((a) => a.name.local == 'id').firstOrNull?.value;
  final relsFile = zip.findFile('xl/_rels/workbook.xml.rels');
  if (rid != null && relsFile != null) {
    for (final r in XmlDocument.parse(_text(relsFile)).findAllElements('Relationship')) {
      if (r.getAttribute('Id') == rid) target = r.getAttribute('Target');
    }
  }
  target ??= 'worksheets/sheet1.xml';
  final path = target.startsWith('/') ? target.substring(1) : 'xl/${target.replaceFirst(RegExp(r'^\./'), '')}';
  final wsFile = zip.findFile(path);
  if (wsFile == null) throw const XlsxReadError('تعذّرت قراءة ورقة الملف');

  final sst = <String>[];
  final sstFile = zip.findFile('xl/sharedStrings.xml');
  if (sstFile != null) {
    for (final si in XmlDocument.parse(_text(sstFile)).findAllElements('si')) {
      sst.add(_richText(si));
    }
  }

  final ws = XmlDocument.parse(_text(wsFile));
  final cells = <int, Map<int, String>>{};
  var minCol = 1 << 30, minRow = 1 << 30, maxCol = -1, maxRow = -1;
  var nextRow = 0;
  for (final row in ws.findAllElements('row')) {
    final rAttr = int.tryParse(row.getAttribute('r') ?? '');
    final r = rAttr == null ? nextRow : rAttr - 1;
    nextRow = r + 1;
    var nextCol = 0;
    for (final c in row.findElements('c')) {
      final ref = _ref(c.getAttribute('r') ?? '');
      final col = ref?.col ?? nextCol;
      nextCol = col + 1;
      final t = c.getAttribute('t');
      final v = c.findElements('v').firstOrNull?.innerText;
      String? value;
      switch (t) {
        case 's':
          final i = int.tryParse(v ?? '');
          value = i != null && i >= 0 && i < sst.length ? sst[i] : '';
        case 'inlineStr':
          final isEl = c.findElements('is').firstOrNull;
          value = isEl == null ? '' : _richText(isEl);
        case 'str':
          value = v ?? '';
        case 'b':
          value = v == null ? '' : (v.trim() == '1' ? 'true' : 'false');
        case 'e':
          value = v ?? '';
        case 'd':
          value = v ?? '';
        default:
          value = v == null ? null : _numText(v);
      }
      if (value == null) continue; // خليّةٌ بلا قيمة (تنسيقٌ وحده)
      (cells[r] ??= {})[col] = value;
      if (col < minCol) minCol = col;
      if (col > maxCol) maxCol = col;
      if (r < minRow) minRow = r;
      if (r > maxRow) maxRow = r;
    }
  }
  if (maxCol < 0) return const [];
  // بداية المدى من <dimension> كما يأخذها SheetJS (وإلّا أوّل خليّةٍ مستعملة)
  final dim = ws.findAllElements('dimension').firstOrNull?.getAttribute('ref');
  if (dim != null) {
    final start = _ref(dim.split(':').first);
    if (start != null) {
      if (start.col < minCol) minCol = start.col;
      if (start.row < minRow) minRow = start.row;
    }
  }
  String cellText(String s) => s.trim();
  final out = <List<String>>[];
  for (var r = minRow; r <= maxRow; r++) {
    final row = cells[r];
    final line = [for (var c = minCol; c <= maxCol; c++) cellText(row?[c] ?? '')];
    if (line.any((c) => c.isNotEmpty)) out.add(line);
  }
  return out;
}

// ═══════════════════════════════ الكتابة ═══════════════════════════════

String _esc(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll(RegExp('[\u0000-\u0008\u000B\u000C\u000E-\u001F]'), '');

String _colName(int i) {
  var n = i + 1;
  final b = <int>[];
  while (n > 0) {
    final m = (n - 1) % 26;
    b.insert(0, 65 + m);
    n = (n - 1) ~/ 26;
  }
  return String.fromCharCodes(b);
}

/// ورقةٌ واحدة باسم [sheetName]: العناوين ثمّ الصفوف — الأرقام أرقامٌ (num) والباقي نصّ. ما يقرؤه Excel وجوجل شيتس والموقع.
Uint8List writeXlsx({required String sheetName, required List<String> headers, required List<List<Object?>> rows}) {
  final all = <List<Object?>>[headers, ...rows];
  final width = all.fold<int>(0, (a, r) => r.length > a ? r.length : a);
  final sheet = StringBuffer()
    ..write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
    ..write('<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">')
    ..write('<dimension ref="A1:${_colName(width == 0 ? 0 : width - 1)}${all.length}"/>')
    ..write('<sheetViews><sheetView workbookViewId="0" rightToLeft="1"/></sheetViews>')
    ..write('<sheetData>');
  for (var r = 0; r < all.length; r++) {
    sheet.write('<row r="${r + 1}">');
    final row = all[r];
    for (var c = 0; c < row.length; c++) {
      final v = row[c];
      final ref = '${_colName(c)}${r + 1}';
      if (v == null || (v is String && v.isEmpty)) continue;
      if (v is num && v.isFinite) {
        sheet.write('<c r="$ref"><v>${v == v.truncate() ? v.truncate() : v}</v></c>');
      } else {
        sheet.write('<c r="$ref" t="inlineStr"><is><t xml:space="preserve">${_esc('$v')}</t></is></c>');
      }
    }
    sheet.write('</row>');
  }
  sheet.write('</sheetData></worksheet>');

  final name = _esc(sheetName.length > 31 ? sheetName.substring(0, 31) : sheetName);
  final files = <String, String>{
    '[Content_Types].xml': '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
        '<Default Extension="xml" ContentType="application/xml"/>'
        '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
        '<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'
        '</Types>',
    '_rels/.rels': '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>'
        '</Relationships>',
    'xl/workbook.xml': '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
        '<sheets><sheet name="$name" sheetId="1" r:id="rId1"/></sheets></workbook>',
    'xl/_rels/workbook.xml.rels': '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>'
        '</Relationships>',
    'xl/worksheets/sheet1.xml': sheet.toString(),
  };
  final archive = Archive();
  for (final e in files.entries) {
    final data = utf8.encode(e.value);
    archive.addFile(ArchiveFile(e.key, data.length, data));
  }
  return Uint8List.fromList(ZipEncoder().encode(archive));
}
