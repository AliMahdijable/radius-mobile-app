import 'nfkc_table.dart';

// «استيراد / تصدير الديون» بالتطبيق (٢٣ نوفمبر — المالك: «قسم استيراد وتصدير الديون اريد ينضاف مثل الويب للهاتف»).
//
// هذا الملفّ منقولٌ **حرفاً** من الموقع: client-v2 `lib/debts-match.ts` (المطابقة) + `lib/debts-pdf.ts` (التطبيع وتصنيف العناوين)
// + `pages/DebtsImport.tsx` (مبلغ الخليّة، CSV، العناوين). هو مسار مال: يقرّر أيّ مشتركٍ يُكتب عليه أيّ دين — فأيّ تغييرٍ في قواعده
// يمرّ بمراجعة المال، ويبقى مطابقاً للموقع (test/debts_import_parity_test.dart يقارنه بالـTS نفسه على حالاتٍ مولَّدة).

/// أرقامٌ عربيّة/فارسيّة ⇒ ASCII (`asciiDigits`).
String asciiDigits(String s) =>
    s.replaceAllMapped(RegExp('[٠-٩۰-۹]'), (m) => String.fromCharCode(0x30 + (m[0]!.codeUnitAt(0) & 0xf)));

/// NFKC كما يفعله `String.prototype.normalize('NFKC')`: المحارف المنفردة من [kNfkcTable] (مولَّدٌ من Node)، ثمّ للعربيّ ترتيب الحركات
/// القانونيّ وتركيب الهمزة والمدّة على حرفها («ا»+«ٓ» ⇒ «آ») كما يركّبها NFKC. التركيب اللاتينيّ (e+◌́) لا يُعاد — لا أثر له في
/// المطابقة (كلمات الاسم العربيّة وحدها).
String nfkc(String s) {
  final cps = <int>[];
  for (final r in s.runes) {
    final m = r <= 0xFFFF ? kNfkcTable[r] : null;
    if (m != null) {
      cps.addAll(m.runes);
    } else {
      cps.add(r);
    }
  }
  return String.fromCharCodes(_composeArabic(cps));
}

/// صنف التركيب (ccc) لعلامات العربيّة U+0610–U+06FF — من UnicodeData. غيرها 0.
const _ccc = <int, int>{
  0x610: 230, 0x611: 230, 0x612: 230, 0x613: 230, 0x614: 230, 0x615: 230, 0x616: 230, 0x617: 230, 0x618: 30, 0x619: 31,
  0x61A: 32, 0x64B: 27, 0x64C: 28, 0x64D: 29, 0x64E: 30, 0x64F: 31, 0x650: 32, 0x651: 33, 0x652: 34, 0x653: 230, 0x654: 230,
  0x655: 220, 0x656: 220, 0x657: 230, 0x658: 230, 0x659: 230, 0x65A: 230, 0x65B: 230, 0x65C: 220, 0x65D: 230, 0x65E: 230,
  0x65F: 220, 0x670: 35, 0x6D6: 230, 0x6D7: 230, 0x6D8: 230, 0x6D9: 230, 0x6DA: 230, 0x6DB: 230, 0x6DC: 230, 0x6DF: 230,
  0x6E0: 230, 0x6E1: 230, 0x6E2: 230, 0x6E3: 220, 0x6E4: 230, 0x6E7: 230, 0x6E8: 230, 0x6EA: 220, 0x6EB: 230, 0x6EC: 230,
  0x6ED: 220,
};

/// التركيبات القانونيّة العربيّة (UnicodeData): حرف + علامة ⇒ مركّب.
const _compose = <int, int>{
  0x0627 << 16 | 0x0653: 0x0622, 0x0627 << 16 | 0x0654: 0x0623, 0x0648 << 16 | 0x0654: 0x0624, 0x0627 << 16 | 0x0655: 0x0625,
  0x064A << 16 | 0x0654: 0x0626, 0x06D5 << 16 | 0x0654: 0x06C0, 0x06C1 << 16 | 0x0654: 0x06C2, 0x06D2 << 16 | 0x0654: 0x06D3,
};
final _decompose = {for (final e in _compose.entries) e.value: [e.key >> 16, e.key & 0xFFFF]};

List<int> _composeArabic(List<int> input) {
  // ١) فكّ المركّب العربيّ (ثمّ يُركَّب ثانيةً بعد الترتيب) ٢) ترتيب العلامات المتتالية بصنفها (ترتيبٌ مستقرّ) ٣) التركيب
  final d = <int>[];
  for (final c in input) {
    final x = _decompose[c];
    if (x != null) {
      d.addAll(x);
    } else {
      d.add(c);
    }
  }
  var i = 0;
  while (i < d.length) {
    if ((_ccc[d[i]] ?? 0) == 0) {
      i++;
      continue;
    }
    var j = i;
    while (j < d.length && (_ccc[d[j]] ?? 0) != 0) {
      j++;
    }
    final run = d.sublist(i, j);
    // إدراجٌ مستقرّ بالصنف
    for (var a = 1; a < run.length; a++) {
      final v = run[a];
      var b = a - 1;
      while (b >= 0 && _ccc[run[b]]! > _ccc[v]!) {
        run[b + 1] = run[b];
        b--;
      }
      run[b + 1] = v;
    }
    d.setRange(i, j, run);
    i = j;
  }
  final out = <int>[];
  var starter = -1; // موضع آخر حرفٍ بادئ في [out]
  var lastCcc = 0;
  for (final c in d) {
    final cc = _ccc[c] ?? 0;
    if (starter >= 0 && cc != 0) {
      final blocked = out.length - 1 != starter && lastCcc >= cc;
      final comp = blocked ? null : _compose[out[starter] << 16 | c];
      if (comp != null) {
        out[starter] = comp;
        continue;
      }
      lastCcc = cc;
      out.add(c);
      continue;
    }
    out.add(c);
    if (cc == 0) {
      starter = out.length - 1;
      lastCcc = 0;
    }
  }
  return out;
}

final _bidi = RegExp('[\u200E\u200F\u202A-\u202E\u2066-\u2069]');
final _spaces = RegExp(r'\s+');

/// نصٌّ ⇒ عربيٌّ قياسيّ (`cleanText`): أشكال العرض ⇒ حروفها، بلا تطويلٍ ولا علامات اتّجاه، ومسافاتٌ مفردة.
String cleanText(String s) => nfkc(s).replaceAll('ـ', '').replaceAll(_bidi, '').replaceAll(_spaces, ' ').trim();

final _harakat = RegExp('[\u064B-\u0670\u065F]');
final _alefs = RegExp('[أإآٱ]');
final _yehs = RegExp('[ىئ]');

/// للمقارنة وحدها (`foldArabic`): همزات الألف ⇒ ا، ة ⇒ ه، ى/ئ ⇒ ي، ؤ ⇒ و، بلا تشكيل، حروفٌ لاتينيّة صغيرة.
String foldArabic(String s) => cleanText(s)
    .toLowerCase()
    .replaceAll(_harakat, '')
    .replaceAll(_alefs, 'ا')
    .replaceAll('ة', 'ه')
    .replaceAll(_yehs, 'ي')
    .replaceAll('ؤ', 'و');

final _nonDigit = RegExp(r'\D');

/// هاتف (`normalizePhone`): أرقامٌ فقط، و٩٦٤/٠٠٩٦٤ ⇒ 0 (07XXXXXXXXX)؛ أقلّ من ٧ أرقام ⇒ ''.
String normalizePhone(String? s) {
  var d = asciiDigits(s ?? '').replaceAll(_nonDigit, '');
  if (d.startsWith('00964')) {
    d = d.substring(5);
  } else if (d.startsWith('964') && d.length >= 12) {
    d = d.substring(3);
  }
  if (d.length == 10 && d.startsWith('7')) d = '0$d';
  return d.length >= 7 ? d : '';
}

/// نوع عمود (`DebtCol`).
enum DebtCol { seq, username, name, debt, phone, pkg, price, expiry }

final _hSeq = RegExp(r'^(#|ت|م|no\.?|n|ر\.?م|تسلسل|التسلسل)$');
final _hPaid = RegExp(r'مدفوع|مسدد|تسديد|paid');
final _hUser = RegExp(r'مستخدم|يوزر|اسم الدخول|user|login');
final _hPhone = RegExp(r'هاتف|موبايل|جوال|phone|mobile|^tel');
final _hExpiry = RegExp(r'انتهاء|نفاذ|expir');
final _hPrice = RegExp(r'سعر|price');
final _hPkg = RegExp(r'باقه|خدمه|profile|package|plan');
final _hDebt = RegExp(r'دين|ديون|مديونيه|مبلغ|متبقي|debt|amount|due');
final _hName = RegExp(r'اسم|مشترك|name|customer');

/// عنوان عمود ⇒ نوعه (`classifyHeader`) — المدفوع/المسدَّد لا يُعدّ ديناً أبداً.
DebtCol? classifyHeader(String h) {
  final t = foldArabic(h);
  if (t.isEmpty) return null;
  if (_hSeq.hasMatch(t)) return DebtCol.seq;
  if (_hPaid.hasMatch(t)) return null;
  if (_hUser.hasMatch(t)) return DebtCol.username;
  if (_hPhone.hasMatch(t)) return DebtCol.phone;
  if (_hExpiry.hasMatch(t)) return DebtCol.expiry;
  if (_hPrice.hasMatch(t)) return DebtCol.price;
  if (_hPkg.hasMatch(t)) return DebtCol.pkg;
  if (_hDebt.hasMatch(t)) return DebtCol.debt;
  if (_hName.hasMatch(t)) return DebtCol.name;
  return null;
}

final _amountSeps = RegExp('[,،٬\\s]');
final _firstNumber = RegExp(r'-?\d+(?:\.\d+)?');

/// مبلغٌ من خليّة (`parseAmountCell`): أرقام عربيّة/فارسيّة، وفواصل آلاف، وأوّل رقمٍ فيها — بلا رقمٍ ⇒ 0 (ثمّ «بلا دين»).
/// الساس يخزّن الدين سالباً؛ الملفّ قد يحمله سالباً أو موجباً ⇒ القيمة المطلقة.
double parseAmountCell(String rawCell) {
  final ascii = rawCell
      .replaceAllMapped(RegExp('[٠-٩]'), (m) => '${m[0]!.codeUnitAt(0) - 0x0660}')
      .replaceAllMapped(RegExp('[۰-۹]'), (m) => '${m[0]!.codeUnitAt(0) - 0x06f0}')
      .replaceAll(_amountSeps, '');
  final m = _firstNumber.firstMatch(ascii);
  final n = m == null ? double.nan : double.parse(m[0]!);
  return n.isFinite ? n.abs() : 0;
}

// ═══════════════════════════════ المطابقة ═══════════════════════════════

/// نوع المطابقة (`MatchKind`): username | phone يُطبَّقان، review باختيارٍ صريح، والباقي لا.
enum DebtMatchKind { username, phone, review, ambiguous, notFound, invalid }

/// ما يحتاجه المطابِق من المشترك (`MatchSub`).
abstract class DebtMatchSub {
  String get username;
  String? get phone;
  String? get firstname;
  String? get lastname;
}

/// صفٌّ من الملفّ (`MatchInput`) — [amount] NaN = غير مقروء.
class DebtMatchInput {
  const DebtMatchInput({required this.username, required this.phone, required this.name, required this.amount});
  final String username;
  final String phone;
  final String name;
  final double amount;
}

/// ناتج صفّ (`MatchOut`).
class DebtMatchOut<S> {
  const DebtMatchOut(this.kind, {this.sub, this.note});
  final DebtMatchKind kind;
  final S? sub;
  final String? note;
}

/// كلماتٌ لا تكفي وحدها لتطابق اسمين.
const _weak = {'عبد', 'ابو', 'ام', 'بن', 'ابن', 'ال', 'سيد', 'حجي', 'الحاج', 'حاج'};
final _wordSplit = RegExp(r'[\s\-_.]+');
final _arabicLetter = RegExp('[ء-ي]');

/// كلمات الاسم العربيّة (حرفان فأكثر، بلا الضعيفة) — للمقارنة وحدها (`nameWords`).
List<String> nameWords(String name) => [
      for (final w in foldArabic(name).split(_wordSplit))
        if (w.length >= 2 && _arabicLetter.hasMatch(w) && !_weak.contains(w)) w,
    ];

String _subName(DebtMatchSub s) => '${s.firstname ?? ''} ${s.lastname ?? ''}'.trim();

/// يشتركان بكلمة؟ null = لا يُقارَن (أحدهما بلا كلماتٍ عربيّة) — `namesAgree`.
bool? namesAgree(String a, String b) {
  final wa = nameWords(a);
  final wb = nameWords(b).toSet();
  if (wa.isEmpty || wb.isEmpty) return null;
  return wa.any(wb.contains);
}

/// صفوف الملفّ ⇒ مشتركو الحساب (`matchDebtRows`):
///   • اليوزر أوّلاً.
///   • صفٌّ بلا يوزر ⇒ رقم الهاتف، ورقمٌ لمشتركٍ واحدٍ فقط. رقمٌ لأكثر من مشترك ⇒ الاسم يحسم إن طابق واحداً وحده، وإلّا «غير محسوم».
///   • مشتركٌ يصله صفّان ⇒ الاثنان «غير محسوم» (إلّا ما طابق باليوزر).
///   • اسمٌ عربيّ في الملف لا يشترك بكلمةٍ مع اسم المشترك ⇒ «راجِع» (لا يُطبَّق إلّا باختيارٍ صريح).
List<DebtMatchOut<S>> matchDebtRows<S extends DebtMatchSub>(List<DebtMatchInput> rows, List<S> subs) {
  final byUser = <String, S>{};
  final byPhone = <String, List<S>>{};
  for (final s in subs) {
    if (s.username.isNotEmpty) byUser[s.username.toLowerCase()] = s;
    final p = normalizePhone(s.phone ?? '');
    if (p.isNotEmpty) (byPhone[p] ??= []).add(s);
  }

  final out = <DebtMatchOut<S>>[
    for (final r in rows)
      () {
        if (!r.amount.isFinite || r.amount < 1) {
          return DebtMatchOut<S>(DebtMatchKind.invalid, note: r.amount == 0 ? 'بلا دين' : 'مبلغٌ غير صالح');
        }
        final u = r.username.trim();
        if (u.isNotEmpty) {
          final sub = byUser[u.toLowerCase()];
          return sub != null ? DebtMatchOut<S>(DebtMatchKind.username, sub: sub) : DebtMatchOut<S>(DebtMatchKind.notFound);
        }
        final phone = normalizePhone(r.phone);
        if (phone.isEmpty) return DebtMatchOut<S>(DebtMatchKind.invalid, note: 'بلا اسم مستخدم ولا هاتف');
        final cands = byPhone[phone] ?? <S>[];
        if (cands.isEmpty) return DebtMatchOut<S>(DebtMatchKind.notFound, note: 'الرقم غير مسجّل لأيّ مشترك');
        var sub = cands.first;
        if (cands.length > 1) {
          final agree = [for (final s in cands) if (namesAgree(r.name, _subName(s)) == true) s];
          if (agree.length != 1) return DebtMatchOut<S>(DebtMatchKind.ambiguous, note: 'الرقم نفسه لـ${cands.length} مشتركين');
          sub = agree.first;
        }
        final same = namesAgree(r.name, _subName(sub));
        if (same == false) return DebtMatchOut<S>(DebtMatchKind.review, sub: sub, note: 'الاسم مختلف — راجِع');
        return DebtMatchOut<S>(DebtMatchKind.phone, sub: sub);
      }(),
  ];

  // مشتركٌ يصله أكثر من صفّ ⇒ لا يُحسَم أيٌّ منها (بهويّة الكائن — كـMap بالكائن في TS)
  final hits = Map<S, int>.identity();
  for (final m in out) {
    final s = m.sub;
    if (s != null && m.kind != DebtMatchKind.notFound) hits[s] = (hits[s] ?? 0) + 1;
  }
  return [
    for (final m in out)
      m.sub != null && (hits[m.sub as S] ?? 0) > 1 && m.kind != DebtMatchKind.username
          ? DebtMatchOut<S>(DebtMatchKind.ambiguous, sub: m.sub, note: 'المشترك نفسه بأكثر من صفّ')
          : m,
  ];
}

// ═══════════════════════════════ CSV ═══════════════════════════════

final _sepLine = RegExp('^\uFEFF?sep=(.)\r?\n', caseSensitive: false);

/// الفاصل (`detectCsvSeparator`): سطر «sep=;» إن وُجد، وإلّا الأكثر في السطر الأوّل خارج الاقتباس (`,` عند التعادل الصفريّ).
({String sep, String body}) detectCsvSeparator(String text) {
  final sepLine = _sepLine.firstMatch(text);
  if (sepLine != null) return (sep: sepLine[1]!, body: text.substring(sepLine[0]!.length));
  final first = text.split(RegExp(r'\r?\n')).first;
  var inQ = false;
  final count = <String, int>{',': 0, ';': 0, '\t': 0};
  for (final ch in first.split('')) {
    if (ch == '"') {
      inQ = !inQ;
    } else if (!inQ && count.containsKey(ch)) {
      count[ch] = count[ch]! + 1;
    }
  }
  // ترتيبٌ مستقرّ تنازليّاً كـArray.sort في JS (التعادل يبقي ترتيب الإدراج: , ثمّ ; ثمّ \t)
  final sorted = count.entries.toList();
  for (var i = 1; i < sorted.length; i++) {
    final e = sorted[i];
    var j = i - 1;
    while (j >= 0 && sorted[j].value < e.value) {
      sorted[j + 1] = sorted[j];
      j--;
    }
    sorted[j + 1] = e;
  }
  final sep = sorted.first.value > 0 ? sorted.first.key : ',';
  return (sep: sep, body: text);
}

/// CSV بسيط (`parseCsv`) — فاصلٌ واحد للملفّ، و"" داخل الخلايا، والصفوف الفارغة تُهمل.
List<List<String>> parseCsv(String input) {
  final d = detectCsvSeparator(input);
  final sep = d.sep;
  final text = d.body;
  final rows = <List<String>>[];
  var row = <String>[];
  final cell = StringBuffer();
  var inQuotes = false;
  final units = text.split('');
  for (var i = 0; i < units.length; i++) {
    final c = units[i];
    if (inQuotes) {
      if (c == '"') {
        if (i + 1 < units.length && units[i + 1] == '"') {
          cell.write('"');
          i++;
        } else {
          inQuotes = false;
        }
      } else {
        cell.write(c);
      }
    } else {
      if (c == '"') {
        inQuotes = true;
      } else if (c == sep) {
        row.add(cell.toString().trim());
        cell.clear();
      } else if (c == '\n' || c == '\r') {
        if (cell.isNotEmpty || row.isNotEmpty) {
          row.add(cell.toString().trim());
          rows.add(row);
          row = <String>[];
          cell.clear();
        }
        if (c == '\r' && i + 1 < units.length && units[i + 1] == '\n') i++;
      } else {
        cell.write(c);
      }
    }
  }
  if (cell.isNotEmpty || row.isNotEmpty) {
    row.add(cell.toString().trim());
    rows.add(row);
  }
  return [for (final r in rows) if (r.isNotEmpty && r.any((c) => c.isNotEmpty)) r];
}

// ═══════════════════════════════ الجدول ⇒ صفوف ═══════════════════════════════

/// صفٌّ مقروء من الملفّ قبل المطابقة.
class DebtFileRow {
  const DebtFileRow({required this.username, required this.amount, required this.raw, required this.phone, required this.name});
  final String username;
  final double amount;
  final String raw;
  final String phone;
  final String name;

  DebtMatchInput get input => DebtMatchInput(username: username, phone: phone, name: name, amount: amount);
}

/// صفوف الجدول (Excel/CSV) ⇒ صفوف ديون بالقاعدة نفسها: العناوين بمصنِّف الـPDF («الاسم» اسمٌ لا يوزر، و«المدفوع» لا يُعدّ ديناً)؛
/// بلا عنوانٍ مفهوم ⇒ العمود الأوّل يوزر والثاني مبلغ.
List<DebtFileRow> debtRowsOfTable(List<List<String>> rows) {
  if (rows.isEmpty) return const [];
  final kinds = [for (final c in rows.first) classifyHeader(c)];
  final userIdx = kinds.indexOf(DebtCol.username);
  final amountIdx = kinds.indexOf(DebtCol.debt);
  final phoneIdx = kinds.indexOf(DebtCol.phone);
  final nameIdx = kinds.indexOf(DebtCol.name);
  final hasHeader = amountIdx >= 0 && (userIdx >= 0 || phoneIdx >= 0);
  final dataRows = hasHeader ? rows.sublist(1) : rows;
  final uIdx = hasHeader ? userIdx : 0;
  final aIdx = hasHeader ? amountIdx : 1;
  String cell(List<String> cells, int i) => i >= 0 && i < cells.length ? cells[i].trim() : '';
  return [
    for (final cells in dataRows)
      DebtFileRow(
        username: cell(cells, uIdx),
        amount: parseAmountCell(cell(cells, aIdx)),
        raw: cells.join(' | '),
        phone: hasHeader ? cell(cells, phoneIdx) : '',
        name: hasHeader ? cell(cells, nameIdx) : '',
      ),
  ];
}
