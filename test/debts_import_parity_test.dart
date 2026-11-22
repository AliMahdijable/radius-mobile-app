import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/services/debts_import/debts_match.dart';
import 'package:rad_mysvcs/services/debts_import/xlsx_lite.dart';

/// «استيراد / تصدير الديون» بالتطبيق = منطق الموقع حرفاً (٢٣ نوفمبر). `test/debts_import/parity_cases.json` يولّده كود الموقع نفسه
/// (client-v2 debts-pdf.ts + debts-match.ts + الدوالّ الخاصّة في pages/DebtsImport.tsx، مترجَمةً بـtypescript، وSheetJS 0.18.5 للـExcel)
/// على حالاتٍ مولَّدة: كلّ اختلافٍ هنا = مشتركٌ قد يُكتب عليه دينٌ غير ما يكتبه الموقع. المولِّد: scratchpad/dimp/h/gen.cjs
/// (`WEB=<client-v2> OUT=<json> node gen.cjs`).
class _Sub implements DebtMatchSub {
  _Sub(this.username, this.phone, this.firstname, this.lastname);
  @override
  final String username;
  @override
  final String? phone;
  @override
  final String? firstname;
  @override
  final String? lastname;
}

const _kindName = {
  DebtMatchKind.username: 'username',
  DebtMatchKind.phone: 'phone',
  DebtMatchKind.review: 'review',
  DebtMatchKind.ambiguous: 'ambiguous',
  DebtMatchKind.notFound: 'not_found',
  DebtMatchKind.invalid: 'invalid',
};

const _colName = {
  DebtCol.seq: 'seq',
  DebtCol.username: 'username',
  DebtCol.name: 'name',
  DebtCol.debt: 'debt',
  DebtCol.phone: 'phone',
  DebtCol.pkg: 'pkg',
  DebtCol.price: 'price',
  DebtCol.expiry: 'expiry',
};

double _num(Object? v) => v == null ? double.nan : (v as num).toDouble();

void main() {
  final j = jsonDecode(File('test/debts_import/parity_cases.json').readAsStringSync()) as Map<String, dynamic>;

  test('التطبيع: cleanText وfoldArabic وكلمات الاسم = الموقع (${(j['normalize'] as List).length} نصّاً)', () {
    final bad = <String>[];
    for (final c in (j['normalize'] as List).cast<Map<String, dynamic>>()) {
      final s = c['in'] as String;
      if (cleanText(s) != c['clean']) bad.add('clean ${jsonEncode(s)}: ${jsonEncode(cleanText(s))} ≠ ${jsonEncode(c['clean'])}');
      if (foldArabic(s) != c['fold']) bad.add('fold ${jsonEncode(s)}: ${jsonEncode(foldArabic(s))} ≠ ${jsonEncode(c['fold'])}');
      if (jsonEncode(nameWords(s)) != jsonEncode(c['words'])) bad.add('words ${jsonEncode(s)}: ${nameWords(s)} ≠ ${c['words']}');
    }
    expect(bad, isEmpty, reason: bad.take(10).join('\n'));
  });

  test('الهاتف: normalizePhone = الموقع (${(j['phones'] as List).length})', () {
    final bad = [
      for (final c in (j['phones'] as List).cast<Map<String, dynamic>>())
        if (normalizePhone(c['in'] as String) != c['out']) '${jsonEncode(c['in'])}: ${normalizePhone(c['in'] as String)} ≠ ${c['out']}',
    ];
    expect(bad, isEmpty, reason: bad.take(10).join('\n'));
  });

  test('العناوين: classifyHeader = الموقع (${(j['headers'] as List).length})', () {
    final bad = [
      for (final c in (j['headers'] as List).cast<Map<String, dynamic>>())
        if (_colName[classifyHeader(c['in'] as String)] != c['out']) '${jsonEncode(c['in'])}: ${classifyHeader(c['in'] as String)} ≠ ${c['out']}',
    ];
    expect(bad, isEmpty, reason: bad.join('\n'));
  });

  test('المبالغ: parseAmountCell = الموقع (${(j['amounts'] as List).length})', () {
    final bad = <String>[];
    for (final c in (j['amounts'] as List).cast<Map<String, dynamic>>()) {
      final got = parseAmountCell(c['in'] as String);
      final want = _num(c['out']);
      if (!(got == want || (got.isNaN && want.isNaN))) bad.add('${jsonEncode(c['in'])}: $got ≠ $want');
    }
    expect(bad, isEmpty, reason: bad.join('\n'));
  });

  test('CSV: parseCsv = الموقع (${(j['csv'] as List).length})', () {
    final bad = [
      for (final c in (j['csv'] as List).cast<Map<String, dynamic>>())
        if (jsonEncode(parseCsv(c['in'] as String)) != jsonEncode(c['out'])) '${jsonEncode(c['in'])}: ${jsonEncode(parseCsv(c['in'] as String))} ≠ ${jsonEncode(c['out'])}',
    ];
    expect(bad, isEmpty, reason: bad.join('\n'));
  });

  test('الجدول ⇒ صفوف (العناوين ومواضع اليوزر والمبلغ والهاتف والاسم) = الموقع (${(j['tables'] as List).length})', () {
    final bad = <String>[];
    for (final c in (j['tables'] as List).cast<Map<String, dynamic>>()) {
      final table = [for (final r in c['in'] as List) [for (final x in r as List) x as String]];
      final got = debtRowsOfTable(table);
      final want = (c['out'] as List).cast<Map<String, dynamic>>();
      if (got.length != want.length) {
        bad.add('${jsonEncode(table)}: ${got.length} صفّ ≠ ${want.length}');
        continue;
      }
      for (var i = 0; i < got.length; i++) {
        final g = got[i], w = want[i];
        final wa = _num(w['amount']);
        if (g.username != w['username'] || g.phone != w['phone'] || g.name != w['name'] || !(g.amount == wa || (g.amount.isNaN && wa.isNaN))) {
          bad.add('${jsonEncode(table)}[$i]: ${g.username}|${g.amount}|${g.phone}|${g.name} ≠ $w');
        }
      }
    }
    expect(bad, isEmpty, reason: bad.join('\n'));
  });

  test('المطابقة: matchDebtRows = الموقع صفّاً صفّاً — النوع والمشترك والملاحظة (${(j['scenarios'] as List).length} حالة)', () {
    final bad = <String>[];
    var rows = 0;
    for (final (si, c) in (j['scenarios'] as List).cast<Map<String, dynamic>>().indexed) {
      final subs = [
        for (final s in (c['subs'] as List).cast<Map<String, dynamic>>())
          _Sub(s['username'] as String, s['phone'] as String?, s['firstname'] as String?, s['lastname'] as String?),
      ];
      final input = [
        for (final r in (c['rows'] as List).cast<Map<String, dynamic>>())
          DebtMatchInput(username: r['username'] as String, phone: r['phone'] as String, name: r['name'] as String, amount: _num(r['amount'])),
      ];
      final got = matchDebtRows(input, subs);
      final want = (c['out'] as List).cast<Map<String, dynamic>>();
      expect(got.length, want.length);
      for (var i = 0; i < got.length; i++) {
        rows++;
        final g = got[i], w = want[i];
        final gs = g.sub == null ? null : subs.indexOf(g.sub!);
        if (_kindName[g.kind] != w['kind'] || gs != w['sub'] || g.note != w['note']) {
          bad.add('#$si/$i ${jsonEncode(input[i].username)} ${jsonEncode(input[i].phone)} ${jsonEncode(input[i].name)}: '
              '${_kindName[g.kind]}/$gs/${g.note} ≠ ${w['kind']}/${w['sub']}/${w['note']}');
        }
      }
    }
    expect(rows, greaterThan(1500));
    expect(bad, isEmpty, reason: '${bad.length} مختلفة:\n${bad.take(12).join('\n')}');
  });

  test('Excel: ما يكتبه SheetJS يقرؤه التطبيق صفوفاً كما يقرؤها الموقع (أرقامٌ قيماً، فارغة بمواضعها، ومدى يبدأ من B)', () {
    for (final (i, c) in (j['xlsx'] as List).cast<Map<String, dynamic>>().indexed) {
      final rows = readXlsxRows(Uint8List.fromList(base64Decode(c['b64'] as String)));
      final want = [for (final r in c['rows'] as List) [for (final x in r as List) x as String]];
      // الأعمدة الفارغة في آخر الصفّ لا تؤثّر (المواضع من البداية) — المقارنة بعد قصّها
      List<List<String>> trim(List<List<String>> t) => [
            for (final r in t) [...r]..length = (r.lastIndexWhere((x) => x.isNotEmpty) + 1),
          ];
      expect(trim(rows), trim(want), reason: 'ملفّ #$i');
    }
  });

  test('Excel: ما يكتبه التطبيق يُقرأ ثانيةً كما هو (عربيّ، أرقام، فارغ، أحرفٌ تُهرَّب)', () {
    final bytes = writeXlsx(sheetName: 'Debts', headers: const ['username', 'amount', 'الاسم', 'رقم الهاتف'], rows: const [
      ['ali1', 25000, 'علي <حسن> & "أخوه"', '07701234567'],
      ['zainab', 30000.5, '', null],
      ['mo', 0, 'مو', '٠٧٧٠'],
    ]);
    expect(sheetKindOf(bytes), SheetKind.xlsx);
    expect(readXlsxRows(bytes), [
      ['username', 'amount', 'الاسم', 'رقم الهاتف'],
      ['ali1', '25000', 'علي <حسن> & "أخوه"', '07701234567'],
      ['zainab', '30000.5', '', ''],
      ['mo', '0', 'مو', '٠٧٧٠'],
    ]);
    final rows = debtRowsOfTable(readXlsxRows(bytes));
    expect([for (final r in rows) (r.username, r.amount, r.phone, r.name)], [
      ('ali1', 25000.0, '07701234567', 'علي <حسن> & "أخوه"'),
      ('zainab', 30000.5, '', ''),
      ('mo', 0.0, '٠٧٧٠', 'مو'),
    ]);
  });
}
