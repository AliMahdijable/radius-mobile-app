import 'dart:collection';
import 'dart:io';

// ═══════════════════════════════════════════════════════════════════════
// «كل الشركات» — أدوات الفحص الثابت لكود lib (مراجعة 179، للإصدار 180): الكود مُقنَّعاً (النصوص والتعليقات فراغات بطولها)، ومطابقة
// الأقواس، وحلّ المسارات (حرفيّ، ثابتٌ في الملفّ، متغيّرٌ محلّيّ، دالّةٌ مساعدة، أو معاملٌ يُمرَّر من مواضع النداء)، ومستقبِلات dio
// (كلّ ما يحمل Dio خادمنا: ApiClient.dio/pipe وأسماؤهما الأخرى)، وأعمق غلافٍ لنداء، والإغلاقات المؤجَّلة (onTap:، builder:…)
// داخل غلاف. الفحوص في test/merged_route_invariant_test.dart تقرأ lib بها، وtest/merged_route_proof_test.dart يزرع النمط
// السيّئ في مصدرٍ بالذاكرة ويثبت أنّ كلّ فحصٍ يفشل عليه.
// ═══════════════════════════════════════════════════════════════════════

/// ملفّ: نصّه، ونسخته المُقنَّعة ([mask]).
class Src {
  Src(this.raw) : code = mask(raw);
  final String raw;
  final String code;
}

typedef Lib = Map<String, Src>;

/// ملفّات [dir] (lib عادةً) بمساراتها النسبيّة `lib/...`.
Lib loadLib([String dir = 'lib']) => {
      for (final f in Directory(dir).listSync(recursive: true).whereType<File>())
        if (f.path.endsWith('.dart')) f.path.replaceAll('\\', '/'): Src(f.readAsStringSync()),
    };

/// المصدر مُقنَّعاً: محتوى النصوص والتعليقات فراغاتٌ بطوله (المواضع والأسطر كما هي، وعلامات الاقتباس باقية) — البحث في الكود
/// وحده، ومطابقة الأقواس لا يخدعها قوسٌ في نصّ أو تعليق.
String mask(String s) {
  final out = s.codeUnits.toList();
  final n = s.length;
  void blank(int from, int to) {
    for (var k = from; k < to && k < n; k++) {
      if (out[k] != 0x0A) out[k] = 0x20;
    }
  }

  bool ident(int c) =>
      (c >= 0x30 && c <= 0x39) || (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A) || c == 0x5F || c == 0x24;
  late int Function(int) str;
  int interp(int j) {
    var depth = 1;
    while (j < n) {
      final c = s.codeUnitAt(j);
      if (c == 0x27 || c == 0x22) {
        j = str(j);
        continue;
      }
      if (c == 0x7B) depth++;
      if (c == 0x7D && --depth == 0) return j + 1;
      j++;
    }
    return n;
  }

  str = (int j) {
    final q = s.codeUnitAt(j);
    final raw = j > 0 && s.codeUnitAt(j - 1) == 0x72 && (j < 2 || !ident(s.codeUnitAt(j - 2)));
    final triple = j + 2 < n && s.codeUnitAt(j + 1) == q && s.codeUnitAt(j + 2) == q;
    final ql = triple ? 3 : 1;
    final start = j + ql;
    var k = start;
    while (k < n) {
      final c = s.codeUnitAt(k);
      if (!raw && c == 0x5C) {
        k += 2;
        continue;
      }
      if (!raw && c == 0x24 && k + 1 < n && s.codeUnitAt(k + 1) == 0x7B) {
        k = interp(k + 2);
        continue;
      }
      if (c == q && (!triple || (k + 2 < n && s.codeUnitAt(k + 1) == q && s.codeUnitAt(k + 2) == q))) {
        blank(start, k);
        return k + ql;
      }
      k++;
    }
    blank(start, n);
    return n;
  };
  var i = 0;
  while (i < n) {
    final c = s.codeUnitAt(i);
    if (c == 0x2F && i + 1 < n && s.codeUnitAt(i + 1) == 0x2F) {
      final e = s.indexOf('\n', i);
      final end = e < 0 ? n : e;
      blank(i, end);
      i = end;
    } else if (c == 0x2F && i + 1 < n && s.codeUnitAt(i + 1) == 0x2A) {
      var depth = 1;
      var k = i + 2;
      while (k < n && depth > 0) {
        if (s.startsWith('/*', k)) {
          depth++;
          k += 2;
        } else if (s.startsWith('*/', k)) {
          depth--;
          k += 2;
        } else {
          k++;
        }
      }
      blank(i, k);
      i = k;
    } else if (c == 0x27 || c == 0x22) {
      i = str(i);
    } else {
      i++;
    }
  }
  return String.fromCharCodes(out);
}

/// أزواج الأقواس `()` `[]` `{}` في كودٍ مُقنَّع (فتحٌ ⇒ غلق) — تُحسب مرّةً لكلّ نصّ.
final _pairs = LinkedHashMap<String, Map<int, int>>.identity();

Map<int, int> _pairsOf(String code) => _pairs.putIfAbsent(code, () {
      final out = <int, int>{};
      final stacks = {0x28: <int>[], 0x5B: <int>[], 0x7B: <int>[]};
      const closer = {0x29: 0x28, 0x5D: 0x5B, 0x7D: 0x7B};
      for (var i = 0; i < code.length; i++) {
        final c = code.codeUnitAt(i);
        final st = stacks[c];
        if (st != null) {
          st.add(i);
          continue;
        }
        final o = closer[c];
        if (o != null && stacks[o]!.isNotEmpty) out[stacks[o]!.removeLast()] = i;
      }
      return out;
    });

/// القوس المغلق لـ`(` عند [open] في كودٍ مُقنَّع.
int closeOf(String code, int open) => _pairsOf(code)[open] ?? code.length;

/// القوس المغلق لـ`{` عند [open].
int braceCloseOf(String code, int open) => _pairsOf(code)[open] ?? code.length;

/// نهاية الوسيط الذي يبدأ عند [i]: أوّل `,` أو قوسٍ مغلق (`)` `]` `}`) خارج كلّ قوسٍ فُتح بعده.
int argEnd(String code, int i) {
  var depth = 0;
  for (var k = i; k < code.length; k++) {
    final c = code[k];
    if (c == '(' || c == '[' || c == '{') depth++;
    if (c == ')' || c == ']' || c == '}') {
      if (depth == 0) return k;
      depth--;
    }
    if (c == ',' && depth == 0) return k;
  }
  return code.length;
}

int lineOf(String code, int pos) => '\n'.allMatches(code.substring(0, pos)).length + 1;

/// [pos] بين قوسَي نداءٍ يطابق [opener] (ينتهي بـ`(`).
bool inside(String code, int pos, RegExp opener) => innermost(code, pos, opener) != null;

/// أعمق نداءٍ يطابق [opener] يحوي [pos] بين قوسيه — null إن لم يحوه شيء.
RegExpMatch? innermost(String code, int pos, RegExp opener) {
  RegExpMatch? best;
  for (final o in opener.allMatches(code)) {
    final open = o.end - 1;
    if (open >= pos) break;
    if (closeOf(code, open) > pos) best = o;
  }
  return best;
}

/// الثوابت النصّيّة في الملفّ (`const _base = '/api/v2/sales'`، `static const _path = …`) — لفكّ المسارات.
Map<String, String> constsOf(Src s) => {
      for (final m in RegExp(r'''const\s+(?:String\s+)?(\w+)\s*=\s*(['"])([^'"]*)\2''').allMatches(s.raw))
        if (s.code.startsWith('const', m.start)) m.group(1)!: m.group(3)!,
    };

String _subst(String v, Map<String, String> consts) =>
    v.replaceAllMapped(RegExp(r'\$\{?(\w+)\}?'), (m) => consts[m.group(1)!] ?? m.group(0)!);

/// النصّ الحرفيّ عند [at] (بعد الفراغات؛ بأيّ علامة، وr الخام) والثوابت فيه مفكوكة — وإلّا null.
String? literalAt(Src s, int at, Map<String, String> consts) {
  final code = s.code;
  var i = at;
  while (i < code.length && (code[i] == ' ' || code[i] == '\n')) {
    i++;
  }
  if (i < code.length && code[i] == 'r') i++;
  if (i >= code.length || (code[i] != "'" && code[i] != '"')) return null;
  final e = code.indexOf(code[i], i + 1);
  if (e < 0) return null;
  return _subst(s.raw.substring(i + 1, e), consts);
}

final _identChar = RegExp(r'[\w$]');

typedef FnSpan = ({int start, int bodyOpen, int end, String name, List<String> params});

final _fns = LinkedHashMap<String, List<FnSpan>>.identity();

/// الدالّة (أو الطريقة) التي يقع [pos] في جسمها المحصور بقوسين `{}` — أعمقها باسمها. الإغلاقات بلا اسم (`() {`) لا تُعدّ.
FnSpan? enclosingFn(String code, int pos) {
  FnSpan? best;
  for (final f in _fns.putIfAbsent(code, () => _fnSpans(code))) {
    if (f.bodyOpen >= pos) break;
    if (f.end > pos && (best == null || f.bodyOpen > best.bodyOpen)) best = f;
  }
  return best;
}

/// كلّ دالّةٍ مسمّاةٍ بجسمٍ `{}` في الملفّ، بترتيب أجسامها.
List<FnSpan> _fnSpans(String code) {
  const keywords = {'if', 'for', 'while', 'switch', 'catch', 'on', 'return', 'await', 'assert', 'super', 'this'};
  final out = <FnSpan>[];
  for (final m in RegExp(r'\)\s*(?:async\s*\*?|sync\s*\*)?\s*\{').allMatches(code)) {
    final bodyOpen = m.end - 1;
    final end = braceCloseOf(code, bodyOpen);
    // القوس المفتوح لقائمة المعاملات
    var depth = 0;
    var k = m.start;
    for (; k >= 0; k--) {
      final c = code[k];
      if (c == ')') depth++;
      if (c == '(' && --depth == 0) break;
    }
    if (k <= 0) continue;
    var j = k - 1;
    while (j >= 0 && code[j] == ' ') {
      j--;
    }
    // معاملات نوعٍ عامّة: name<T>(
    if (j >= 0 && code[j] == '>') {
      var d = 0;
      for (; j >= 0; j--) {
        if (code[j] == '>') d++;
        if (code[j] == '<' && --d == 0) break;
      }
      j--;
    }
    final nameEnd = j + 1;
    while (j >= 0 && _identChar.hasMatch(code[j])) {
      j--;
    }
    final name = code.substring(j + 1, nameEnd);
    if (name.isEmpty || keywords.contains(name) || RegExp(r'^\d').hasMatch(name)) continue;
    // نداءٌ لا تعريف (`x.foo(...) {` لا يقع؛ `foo(...) {` بعد نقطة = نداء)
    var b = j;
    while (b >= 0 && (code[b] == ' ' || code[b] == '\n')) {
      b--;
    }
    if (b >= 0 && code[b] == '.') continue;
    final params = [
      for (final p in RegExp(r'(\w+)\s*(?=[,)}\]=]|$)').allMatches(code.substring(k + 1, m.start + 1))) p.group(1)!,
    ];
    out.add((start: j + 1, bodyOpen: bodyOpen, end: end, name: name, params: params));
  }
  return out;
}

/// إغلاقٌ مؤجَّل بين [from] و[pos] يحوي [pos]: وسيطٌ مسمّى (`onTap:`، `onPressed:`، `builder:`…) يُنفَّذ لاحقاً خارج نطاق الغلاف
/// الذي كُتب داخله — `MergedOps.run(sub, () => showX(onTap: () => SubscribersApi.y()))` لا يحمل شركة الصفّ لحظة النقر.
bool deferredAt(String code, int from, int pos) {
  final label = RegExp(r'\b(?:on[A-Z]\w*|builder|itemBuilder|separatorBuilder|pageBuilder)\s*:');
  for (final m in label.allMatches(code, from)) {
    if (m.start >= pos) break;
    if (argEnd(code, m.end) > pos) return true;
  }
  return false;
}

/// الوسيط الأوّل لنداءٍ قوسه المفتوح عند [open] — بلا فراغات.
String firstArg(String code, int open) => code.substring(open + 1, argEnd(code, open + 1)).replaceAll(RegExp(r'\s+'), '');

// ─────────────────────────────── dio خادمنا ───────────────────────────────

const _verbs = r'(post|put|patch|delete|request|postUri|putUri|patchUri|deleteUri)';

/// أسماءٌ أخرى لـDio خادمنا (`Dio get _d => ApiClient.pipe;`، `final dio = ApiClient.dio;`) — نداء كتابةٍ عليها يمرّ بالمعترض نفسه.
Set<String> serverDioAliases(Lib lib) {
  final out = <String>{};
  final decl = RegExp(r'(?:\bget\s+|\b(?:final|var|late|static|const)\s+(?:\w+\s+)?|\bDio\??\s+)(\w+)\s*(?:=>|=)\s*ApiClient\s*\.\s*(?:dio|pipe)\b');
  for (final s in lib.values) {
    for (final m in decl.allMatches(s.code)) {
      out.add(m.group(1)!);
    }
  }
  out.removeWhere((a) => RegExp(r'[dD]io$').hasMatch(a)); // يطابقها النمط العامّ
  return out;
}

String _aliasAlt(Set<String> aliases) => aliases.isEmpty ? '' : '|\\b(?:${aliases.map(RegExp.escape).join('|')})';

/// نداء كتابةٍ على أيّ Dio (`ApiClient.dio.post<…>(`، `_dio.put(`، `ApiClient.pipe.post(`، `_d.post(`…) — حتى القوس المفتوح.
/// المجموعة ١: الفعل.
RegExp dioWriteRe(Set<String> aliases) => RegExp(
    '(?:\\b[A-Za-z_]*[dD]io|\\bpipe${_aliasAlt(aliases)})\\s*\\.\\s*$_verbs\\s*(?:<[^()]*?>)?\\s*\\(');

/// نداء كتابةٍ على Dio خادمنا وحده (يمرّ بمعترض التوجيه): ApiClient.dio/pipe وأسماؤهما الأخرى.
RegExp serverDioWriteRe(Set<String> aliases) => RegExp(
    '(?:\\bApiClient\\s*\\.\\s*(?:dio|pipe)${_aliasAlt(aliases)})\\s*\\.\\s*$_verbs\\s*(?:<[^()]*?>)?\\s*\\(');

/// نداء request بطريقة GET صراحةً — قراءة.
bool requestIsGet(Src s, RegExpMatch c) {
  if (c.group(1) != 'request') return false;
  final open = c.end - 1;
  return RegExp(r'''method:\s*(['"])GET\1''').hasMatch(s.raw.substring(open, closeOf(s.code, open)));
}

/// وسائط نداءٍ قوسه المفتوح عند [open]: لكلٍّ اسمه إن كان مسمّى (`name:`) وبدايته في الكود.
List<({String? name, int at})> argsOf(String code, int open) {
  final close = closeOf(code, open);
  final out = <({String? name, int at})>[];
  var i = open + 1;
  while (i < close) {
    final end = argEnd(code, i);
    final seg = code.substring(i, end);
    if (seg.trim().isNotEmpty) {
      final named = RegExp(r'^\s*(\w+)\s*:(?!:)').firstMatch(seg);
      out.add((name: named?.group(1), at: named == null ? i : i + named.end));
    }
    i = end + 1;
  }
  return out;
}

/// معاملات تعريف دالّةٍ قوس معاملاتها المفتوح عند [open]: اسم كلٍّ وموضعه بين الموضعيّة (null للمسمّاة).
List<({String name, int? index})> paramsOf(String code, int open) {
  final close = closeOf(code, open);
  final out = <({String name, int? index})>[];
  var depth = 0;
  var named = false;
  var start = open + 1;
  var positional = 0;
  void flush(int end) {
    var seg = code.substring(start, end);
    final eq = seg.indexOf('=');
    if (eq >= 0) seg = seg.substring(0, eq);
    final m = RegExp(r'(\w+)\s*$').firstMatch(seg.trim());
    if (m != null) out.add((name: m.group(1)!, index: named ? null : positional++));
  }

  for (var i = open + 1; i < close; i++) {
    final c = code[i];
    if (depth == 0 && (c == '{' || c == '[')) {
      flush(i);
      named = c == '{';
      start = i + 1;
      continue;
    }
    if (depth == 0 && (c == '}' || c == ']')) {
      flush(i);
      start = i + 1;
      continue;
    }
    if (c == '<' || c == '(') depth++;
    if (c == '>' || c == ')') depth--;
    if (c == ',' && depth == 0) {
      flush(i);
      start = i + 1;
    }
  }
  flush(close);
  return out;
}

/// نصٌّ حرفيّ، أو ثابتٌ في الملفّ، عند [at] — وإلّا null.
String? _valueAt(Src s, int at, Map<String, String> consts) {
  final lit = literalAt(s, at, consts);
  if (lit != null) return lit;
  final id = RegExp(r'\s*([A-Za-z_$][\w$]*)\s*(?:[,)]|$)').matchAsPrefix(s.code, at);
  return id == null ? null : consts[id.group(1)!];
}

/// أوّل نصٍّ حرفيٍّ تُرجعه الدالّة المساعدة [name] (`_path(idx) => '/api/…'`) — null إن لم يُعرف.
String? _helperLiteral(Src s, String name, Map<String, String> consts) {
  final def = RegExp('\\b${RegExp.escape(name)}\\s*\\([^)]*\\)\\s*(?:async\\s*)?(?:=>|\\{)').firstMatch(s.code);
  if (def == null) return null;
  final q = RegExp('[\'"]').firstMatch(s.code.substring(def.end));
  if (q == null || q.start > 200) return null;
  return literalAt(s, def.end + q.start, consts);
}

/// مسار نداء dio قوسه المفتوح عند [open]: حرفيّ، أو ثابتٌ في الملفّ، أو متغيّرٌ محلّيٌّ قبله (بنصٍّ حرفيّ أو بدالّةٍ مساعدة)، أو
/// دالّةٌ مساعدة تُرجع نصّاً (`_path(idx)`). معاملٌ للدالّة نفسها ⇒ `param:<اسمه>@<الدالّة>` (يُحلّ من مواضع ندائها —
/// [forwardedPaths]). وإلّا null.
String? pathAt(Src s, int open, Map<String, String> consts) {
  final lit = _valueAt(s, open + 1, consts);
  if (lit != null) return lit;
  final code = s.code;
  final id = RegExp(r'\s*([A-Za-z_$][\w$]*)\s*([,)(])').matchAsPrefix(code, open + 1);
  if (id == null) return null;
  final name = id.group(1)!;
  if (id.group(2) == '(') return _helperLiteral(s, name, consts);
  final fn = enclosingFn(code, open);
  if (fn == null) return null;
  // متغيّرٌ محلّيّ قبل النداء: `final path = '…';` أو `final p = await _path();`
  final local = RegExp('\\b(?:final|var|String\\??)\\s+${RegExp.escape(name)}\\s*=\\s*')
      .allMatches(code.substring(0, open))
      .where((m) => m.start > fn.bodyOpen)
      .toList();
  if (local.isNotEmpty) {
    final at = local.last.end;
    final v = _valueAt(s, at, consts);
    if (v != null) return v;
    final h = RegExp(r'(?:await\s+)?([A-Za-z_$][\w$]*)\s*\(').matchAsPrefix(code, at);
    return h == null ? null : _helperLiteral(s, h.group(1)!, consts);
  }
  if (fn.params.contains(name)) return 'param:$name@${fn.name}';
  return null;
}

/// مواضع نداء الدالّة [fn] في الملفّ وقيمة معاملها [param] عند كلٍّ (حرفيّةً أو ثابتاً؛ null لما سواهما) — لدالّةٍ تمرّر مسارها
/// لـdio (`_write(path, body)`، `_send(mode, method, path)`).
List<({int at, String? path})> forwardedUses(Src s, String fn, String param, Map<String, String> consts) {
  final code = s.code;
  final callRe = RegExp('(?<![\\w\$.])${RegExp.escape(fn)}\\s*(?:<[^()]*?>)?\\s*\\(');
  ({String name, int? index})? p;
  for (final m in callRe.allMatches(code)) {
    if (_isDefinition(code, m)) p ??= paramsOf(code, m.end - 1).where((x) => x.name == param).firstOrNull;
  }
  final uses = <({int at, String? path})>[];
  for (final m in callRe.allMatches(code)) {
    if (_isDefinition(code, m)) continue;
    final args = argsOf(code, m.end - 1);
    final a = p == null
        ? null
        : p.index != null
            ? args.where((x) => x.name == null).elementAtOrNull(p.index!)
            : args.where((x) => x.name == p!.name).firstOrNull;
    uses.add((at: m.start, path: a == null ? null : _valueAt(s, a.at, consts)));
  }
  return uses;
}

bool _isDefinition(String code, RegExpMatch m) {
  final close = closeOf(code, m.end - 1);
  return RegExp(r'^\s*(?:async\s*\*?|sync\s*\*)?\s*(?:\{|=>)').hasMatch(code.substring(close + 1));
}

/// نداء كتابةٍ على dio: ملفّه، وموضعه وقوسه، والفعل، والدالّة التي تمرّر مسارها إليه (إن كان معاملاً لها)، ومواضع الاستعمال
/// بمساراتها (النداء نفسه؛ أو مواضع نداء تلك الدالّة — null = لم يُحلّ).
typedef DioWrite = ({String file, int at, int open, String verb, String? forwardedBy, List<({int at, String? path})> uses});

/// كلّ نداء كتابةٍ على dio في [lib] (المستقبِلات بـ[re]).
List<DioWrite> dioWrites(Lib lib, RegExp re) {
  final out = <DioWrite>[];
  for (final e in lib.entries) {
    final s = e.value;
    final consts = constsOf(s);
    for (final c in re.allMatches(s.code)) {
      if (requestIsGet(s, c)) continue;
      final open = c.end - 1;
      final p = pathAt(s, open, consts);
      if (p != null && p.startsWith('param:')) {
        final param = p.substring(6, p.indexOf('@'));
        final fn = p.substring(p.indexOf('@') + 1);
        var uses = forwardedUses(s, fn, param, consts);
        if (uses.isEmpty) uses = [(at: c.start, path: null)];
        out.add((file: e.key, at: c.start, open: open, verb: c.group(1)!, forwardedBy: fn, uses: uses));
      } else {
        out.add((file: e.key, at: c.start, open: open, verb: c.group(1)!, forwardedBy: null, uses: [(at: c.start, path: p)]));
      }
    }
  }
  return out;
}

// ─────────────────────────────── الأغلفة ───────────────────────────────

/// غلافٌ يحدّد شركة ما بداخله: MergedOps.run/write/writeAt/pinned، CompanyRoute.pin/run/runOpen، و`_co(` شيتَي «مشترك جديد».
final wrapperRe = RegExp(r'(?:MergedOps\s*\.\s*(?:run|write|writeAt|pinned)|CompanyRoute\s*\.\s*(?:pin|run|runOpen)|(?<![.\w])_co)'
    r'\s*(?:<[^()]*?>)?\s*\(');

/// بادئة الغلاف كما كُتبت: اسمه وأوّل وسيطٍ إن لم يكن الجسم — `MergedOps.write(widget.sub,`، `CompanyRoute.runOpen(`، `_co(`.
/// وسيطٌ محلّيٌّ في دالّة الغلاف يُكتب بمصدره: `CompanyRoute.pin(key=sub.companyKey,`.
String wrapperPrefix(String code, RegExpMatch w) {
  final callee = code.substring(w.start, w.end - 1).replaceAll(RegExp(r'\s+'), '').replaceAll(RegExp(r'<.*>$'), '');
  if (callee.endsWith('runOpen') || callee == '_co') return '$callee(';
  final arg = firstArg(code, w.end - 1);
  final local = RegExp(r'^[a-z]\w*$').hasMatch(arg) ? localSource(code, w.start, arg) : null;
  return '$callee(${local == null ? arg : '$arg=$local'},';
}

/// مصدر المتغيّر المحلّيّ [name] في الدالّة التي تحوي [pos] (`final key = sub.companyKey;` ⇒ `sub.companyKey`) — آخر تعريفٍ قبله.
String? localSource(String code, int pos, String name) {
  final fn = enclosingFn(code, pos);
  if (fn == null) return null;
  final m = RegExp('\\b(?:final|var|String\\??)\\s+${RegExp.escape(name)}\\s*=\\s*([^;]+);')
      .allMatches(code.substring(fn.bodyOpen, pos))
      .lastOrNull;
  return m?.group(1)!.replaceAll(RegExp(r'\s+'), '');
}

/// إشارةٌ عند [ref] لا تُبلَغ إلّا من خلف [gate]: النمط في عنصرها نفسه أو في عنصرٍ يحويه — `if (gate) SubAction(… onTap: () =>
/// ref(…))`، `onX: gate && … ? () => ref(…) : null` (حتى ٨ مستويات).
bool gatedRef(String code, int ref, RegExp gate) {
  var pos = ref;
  for (var level = 0; level < 8; level++) {
    final open = _enclosingOpen(code, pos);
    if (open < 0) return false;
    var segStart = open + 1;
    var depth = 0;
    for (var k = open + 1; k < pos; k++) {
      final c = code[k];
      if (c == '(' || c == '[' || c == '{') depth++;
      if (c == ')' || c == ']' || c == '}') depth--;
      if ((c == ',' || c == ';') && depth == 0) segStart = k + 1;
    }
    if (gate.hasMatch(code.substring(segStart, ref))) return true;
    pos = open;
  }
  return false;
}

/// أقرب قوسٍ مفتوح (`(` `[` `{`) يحوي [pos].
int _enclosingOpen(String code, int pos) {
  var depth = 0;
  for (var k = pos - 1; k >= 0; k--) {
    final c = code[k];
    if (c == ')' || c == ']' || c == '}') depth++;
    if (c == '(' || c == '[' || c == '{') {
      if (depth == 0) return k;
      depth--;
    }
  }
  return -1;
}

/// أعمق غلافٍ يحوي [pos] — وهل بينهما إغلاقٌ مؤجَّل ([deferredAt]): حينها لا يحمل الغلافُ شركته لحظة التنفيذ.
({String prefix, bool deferred})? wrapperOf(String code, int pos) {
  final w = innermost(code, pos, wrapperRe);
  if (w == null) return null;
  return (prefix: wrapperPrefix(code, w), deferred: deferredAt(code, w.end, pos));
}
