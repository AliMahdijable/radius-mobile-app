import 'route_scan.dart';

// ═══════════════════════════════════════════════════════════════════════
// «كل الشركات» — الفحوص الثابتة نفسها دوالّاً تأخذ المصدر (مراجعة 179، للإصدار 180 — route3_verify.json البنود ٥–١١):
// test/merged_route_invariant_test.dart يمرّر lib الحقيقيّ وقوائمه المراجَعة، وtest/merged_route_proof_test.dart يمرّر مصدراً
// بالذاكرة زُرع فيه النمط السيّئ ويثبت أنّ كلّ فحصٍ يفشل عليه. كلّ دالّةٍ تُرجع المخالفات (فارغة = سليم) أو جرداً يُقارَن بالمراجَع.
// ═══════════════════════════════════════════════════════════════════════

bool subscriberPath(String p) => p == '/api/v2/subscribers' || p.startsWith('/api/v2/subscribers/');

const moneyPrefixes = ['/api/v2/sales', '/api/v2/settlements', '/api/admin/expenses', '/api/v2/expenses'];

/// ملفّات واجهات المال واسم صنفها.
const moneyApiFiles = {
  'lib/api/sales_api.dart': 'SalesApi',
  'lib/api/settlements_api.dart': 'SettlementsApi',
  'lib/api/expenses_api.dart': 'ExpensesApi',
  'lib/api/recurring_expenses_api.dart': 'RecurringExpensesApi',
};

/// مجلّدات أقسام المال (شيتاتها تحمل شركتها معامل companyKey).
const moneyDirs = ['lib/screens/sales/', 'lib/screens/settlements/', 'lib/screens/expenses/'];

String _norm(String s) => s.replaceAll(RegExp(r'\s+'), '');

// ─────────────────────────── ١١. dio: كتابات المال، والمسارات غير المحلولة ───────────────────────────

/// كتابات المال في كلّ lib (أيّ مستقبِل Dio، أيّ صيغة): كلّ نداءٍ على مسار مالٍ (أو في ملفّ مال) يحمل شركته صراحةً من معامل
/// companyKey. يُرجع المخالفات وعدد ما فُحص لكلّ ملفّ.
({List<String> bad, Map<String, int> perFile}) moneyDioWrites(Lib lib, {required Set<String> readsByPost}) {
  const markers = ['CompanyRoute.explicit(companyKey', '_routed(companyKey'];
  final bad = <String>[];
  final perFile = <String, int>{};
  for (final w in dioWrites(lib, dioWriteRe(serverDioAliases(lib)))) {
    final s = lib[w.file]!;
    final paths = w.uses.map((u) => u.path).toList();
    if (paths.isNotEmpty && paths.every((p) => p != null && readsByPost.contains(p))) continue;
    final money = moneyApiFiles.containsKey(w.file) || paths.any((p) => p != null && moneyPrefixes.any(p.startsWith));
    if (!money) continue;
    perFile[w.file] = (perFile[w.file] ?? 0) + 1;
    final args = _norm(s.code.substring(w.open, closeOf(s.code, w.open)));
    if (!markers.any((m) => args.contains(_norm(m)))) {
      bad.add('${w.file}:${lineOf(s.code, w.at)} ${w.verb} ${paths.firstWhere((p) => p != null, orElse: () => '(مسارٌ غير حرفيّ)')}');
    }
  }
  return (bad: bad, perFile: perFile);
}

/// كتابات Dio خادمنا (ApiClient.dio/pipe وأسماؤهما) بمسارٍ لم يُحلّ (لا حرفيّ ولا ثابت ولا محلّيّ ولا دالّةٌ مساعدة، ولا حرفيٌّ عند
/// كلّ من يمرّره) — `ملفّ الدالّة` لكلٍّ، تُقارَن بقائمةٍ مراجَعة: مسارٌ لا يُعرف لا يُعرف أهو مال أو مشترك.
Set<String> unresolvedServerWrites(Lib lib) => {
      for (final w in dioWrites(lib, serverDioWriteRe(serverDioAliases(lib))))
        if (w.uses.any((u) => u.path == null))
          '${w.file} ${w.forwardedBy ?? enclosingFn(lib[w.file]!.code, w.at)?.name ?? '?'}',
    };

// ─────────────────────────── كتّاب المشترك (مشتقّون من lib/api) ───────────────────────────

/// الطرق في lib/api: `صنف.اسم` ⇒ (ملفّها، موضعها، معاملاتها، جسمها).
Map<String, ({String file, int at, String params, String body})> apiMembers(Lib lib) {
  final out = <String, ({String file, int at, String params, String body})>{};
  final decl = RegExp(r'\n  static ');
  for (final e in lib.entries) {
    if (!e.key.startsWith('lib/api/')) continue;
    final code = e.value.code;
    final classes = [
      for (final m in RegExp(r'\n(?:abstract\s+|final\s+|sealed\s+)?class\s+(\w+)').allMatches(code)) (at: m.start, name: m.group(1)!),
    ];
    final members = <({int at, String cls, String name, String params})>[];
    for (final d in decl.allMatches(code)) {
      // اسم الدالّة: آخر معرّفٍ قبل أوّل `(` خارج <> — حقلٌ أو جالبٌ (`=`، `;`، `=>` قبله) ليس دالّة
      var k = d.end;
      var angle = 0;
      var stop = -1;
      while (k < code.length) {
        final ch = code[k];
        if (ch == '<') angle++;
        if (ch == '>') angle--;
        if (angle == 0 && (ch == '(' || ch == '=' || ch == ';' || ch == '{')) {
          stop = ch == '(' ? k : -1;
          break;
        }
        k++;
      }
      if (stop < 0) continue;
      final name = RegExp(r'(\w+)\s*(?:<[^()]*>)?\s*$').firstMatch(code.substring(d.end, stop))?.group(1);
      final cls = classes.lastWhere((c) => c.at < d.start, orElse: () => (at: 0, name: '')).name;
      if (name != null && cls.isNotEmpty) {
        members.add((at: d.start, cls: cls, name: name, params: code.substring(stop, closeOf(code, stop) + 1)));
      }
    }
    for (var i = 0; i < members.length; i++) {
      final end = i + 1 < members.length ? members[i + 1].at : code.length;
      out['${members[i].cls}.${members[i].name}'] =
          (file: e.key, at: members[i].at, params: members[i].params, body: code.substring(members[i].at, end));
    }
  }
  return out;
}

/// الطريقة التي تحوي [pos] من ملفّ [file] — `صنف.اسم` أو null.
String? memberAt(Map<String, ({String file, int at, String params, String body})> members, String file, int pos) {
  String? best;
  var bestAt = -1;
  for (final m in members.entries) {
    if (m.value.file != file || m.value.at > pos || m.value.at + m.value.body.length <= pos) continue;
    if (m.value.at > bestAt) {
      best = m.key;
      bestAt = m.value.at;
    }
  }
  return best;
}

/// واجهات الكتابة على مسار مشترك، مشتقّةٌ من lib/api: نداء dio يكتب على /api/v2/subscribers… (أيّ مستقبِل، حرفيّاً أو بثابتٍ أو
/// بدالّةٍ مساعدة، أو بدالّةٍ تمرّر مساره — حينها من يناديها بمسار مشترك)، أو طريقةٌ تنادي واحدةً منها. قراءات [readsByPost] مستثناة.
Set<String> subscriberWriters(Lib lib, {required Set<String> readsByPost}) {
  final members = apiMembers(lib);
  final writers = <String>{};
  final api = {for (final e in lib.entries) if (e.key.startsWith('lib/api/')) e.key: e.value};
  for (final w in dioWrites(api, dioWriteRe(serverDioAliases(lib)))) {
    for (final u in w.uses) {
      final p = u.path;
      if (p == null || !subscriberPath(p) || readsByPost.contains(p)) continue;
      final m = memberAt(members, w.file, u.at);
      if (m != null) writers.add(m);
    }
  }
  // من ينادي كاتبةً كاتب
  for (var changed = true; changed;) {
    changed = false;
    for (final b in members.entries) {
      if (writers.contains(b.key)) continue;
      final cls = b.key.split('.').first;
      final body = b.value.body;
      final calls = writers.any((w) {
        final (wc, wn) = (w.split('.').first, w.split('.').last);
        return RegExp('\\b$wc\\s*\\.\\s*$wn\\s*\\(').hasMatch(body) ||
            (wc == cls && RegExp('(?<![.\\w])$wn\\s*\\(').hasMatch(body.substring(body.indexOf('(') + 1)));
      });
      if (calls) {
        writers.add(b.key);
        changed = true;
      }
    }
  }
  return writers;
}

// ─────────────────────────── ٦/٨/١١. مواضع كتّاب المشترك خارج lib/api ───────────────────────────

/// كلّ نداءٍ لكاتب [writers] من خارج lib/api: إمّا جماعيّ مراجَع ([bulk]: `ملفّ#دالّة كاتب`) — يُفحص حارسه بـ[bulkGuardViolations] —
/// وإمّا داخل غلافٍ يحدّد شركته. يُرجع بادئة غلاف كلّ موضع (`ملفّ كاتب` ⇒ البادئات بترتيبها) لتُقارَن بالمراجَعة حرفاً، والمخالفات:
/// بلا غلاف (ضمنيّ)، أو داخل إغلاقٍ مؤجَّل (onTap:، builder:… — يُنفَّذ خارج نطاق الغلاف).
({List<String> bad, Map<String, List<String>> prefixes, Set<String> bulkSeen}) writerSites(
    Lib lib, Set<String> writers, {required Set<String> bulk}) {
  final bad = <String>[];
  final prefixes = <String, List<String>>{};
  final bulkSeen = <String>{};
  for (final e in lib.entries) {
    if (e.key.startsWith('lib/api/')) continue;
    final code = e.value.code;
    for (final w in writers) {
      final (wc, wn) = (w.split('.').first, w.split('.').last);
      for (final m in RegExp('\\b$wc\\s*\\.\\s*$wn\\b').allMatches(code)) {
        final site = '${e.key} $w';
        final where = '$site (سطر ${lineOf(code, m.start)})';
        final fn = enclosingFn(code, m.start);
        final bulkKey = '${e.key}#${fn?.name} $w';
        if (bulk.contains(bulkKey)) {
          bulkSeen.add(bulkKey);
          continue;
        }
        final wr = wrapperOf(code, m.start);
        if (wr == null) {
          bad.add('$where: ضمنيّ — بلا غلافٍ يحدّد شركته');
          continue;
        }
        if (wr.deferred) bad.add('$where: داخل إغلاقٍ مؤجَّل (onTap:/builder:…) في ${wr.prefix} — يُنفَّذ خارج نطاقه');
        (prefixes[site] ??= []).add(wr.prefix);
      }
    }
  }
  return (bad: bad, prefixes: prefixes, bulkSeen: bulkSeen);
}

/// حارس الجماعيّ لكلّ موضعٍ مراجَع — بالدالّة نفسها لا بالملفّ:
/// * `rows` (شاشة المشتركين): قبل النداء في دالّته نفسها `final X = _bulkRowsOrRefuse(…);` ثمّ `if (X == null…) return`، و
///   `_bulkRowsOrRefuse` يسأل `MergedOps.bulkRefusal` ويعيد null.
/// * `show:<دالّة العرض>:<صنف الشيت>` (الشيتان الجماعيّان): دالّة العرض ترفض بـ`MergedOps.bulkRefusal` قبل أن تبني الشيت، والشيت
///   لا يُبنى إلّا فيها.
List<String> bulkGuardViolations(Lib lib, Map<String, String> bulk) {
  final bad = <String>[];
  for (final b in bulk.entries) {
    final file = b.key.split('#').first;
    final fnName = b.key.split('#').last.split(' ').first;
    final writer = b.key.split(' ').last;
    final s = lib[file];
    if (s == null) {
      bad.add('${b.key}: الملفّ غير موجود');
      continue;
    }
    final code = s.code;
    final (wc, wn) = (writer.split('.').first, writer.split('.').last);
    final calls = [
      for (final m in RegExp('\\b$wc\\s*\\.\\s*$wn\\b').allMatches(code))
        if (enclosingFn(code, m.start)?.name == fnName) m.start,
    ];
    if (calls.isEmpty) {
      bad.add('${b.key}: لا نداء في الدالّة');
      continue;
    }
    final rule = b.value;
    if (rule == 'rows') {
      final def = RegExp(r'List<Subscriber>\?\s+_bulkRowsOrRefuse\s*\(').firstMatch(code);
      final defBody = def == null ? '' : code.substring(def.end, braceCloseOf(code, code.indexOf('{', def.end)));
      if (!RegExp(r'MergedOps\s*\.\s*bulkRefusal\s*\(').hasMatch(defBody) || !defBody.contains('return null')) {
        bad.add('${b.key}: _bulkRowsOrRefuse لا يرفض بـMergedOps.bulkRefusal');
      }
      for (final at in calls) {
        final fn = enclosingFn(code, at)!;
        final before = code.substring(fn.bodyOpen, at);
        final g = RegExp(r'final\s+(\w+)\s*=\s*_bulkRowsOrRefuse\s*\(').firstMatch(before);
        final ret = g == null ? null : RegExp('if\\s*\\(\\s*${g.group(1)}\\s*==\\s*null[^)]*\\)\\s*return\\b').firstMatch(before);
        if (ret == null || ret.start < g!.end) {
          bad.add('${b.key} (سطر ${lineOf(code, at)}): بلا `_bulkRowsOrRefuse` ثمّ عودةٍ قبله في دالّته');
        }
      }
    } else if (rule.startsWith('show:')) {
      final parts = rule.split(':');
      final (showFn, sheet) = (parts[1], parts[2]);
      final show = RegExp('\\b$showFn\\s*\\(').allMatches(code).where((m) => _isDef(code, m)).firstOrNull;
      if (show == null) {
        bad.add('${b.key}: دالّة العرض $showFn غير موجودة');
        continue;
      }
      final bodyOpen = code.indexOf('{', closeOf(code, show.end - 1));
      final body = code.substring(bodyOpen, braceCloseOf(code, bodyOpen));
      final g = RegExp(r'final\s+(\w+)\s*=\s*MergedOps\s*\.\s*bulkRefusal\s*\(').firstMatch(body);
      final ret = g == null ? null : RegExp('if\\s*\\(\\s*${g.group(1)}\\s*!=\\s*null\\s*\\)\\s*\\{[^{}]*\\breturn\\b').firstMatch(body);
      final build = RegExp('(?<![\\w.])$sheet\\s*\\(').firstMatch(body);
      if (ret == null || build == null || build.start < ret.end) {
        bad.add('${b.key}: $showFn لا يرفض بـMergedOps.bulkRefusal قبل أن يبني $sheet');
      }
      // الشيت لا يُبنى إلّا في دالّة العرض
      for (final f in lib.entries) {
        for (final m in RegExp('(?<![\\w.])$sheet\\s*\\(').allMatches(f.value.code)) {
          if (_isDef(f.value.code, m) || _isCtorDecl(f.value.code, m)) continue;
          final inShow = f.key == file && m.start > bodyOpen && m.start < braceCloseOf(code, bodyOpen);
          if (!inShow) bad.add('${f.key} (سطر ${lineOf(f.value.code, m.start)}): $sheet يُبنى خارج $showFn — بلا حارسه');
        }
      }
    } else {
      bad.add('${b.key}: قاعدةٌ مجهولة $rule');
    }
  }
  return bad;
}

bool _isDef(String code, RegExpMatch m) {
  final close = closeOf(code, m.end - 1);
  return RegExp(r'^\s*(?:async\s*\*?|sync\s*\*)?\s*(?:\{|=>)').hasMatch(code.substring(close + 1));
}

/// تعريف المُنشئ (`const _Sheet({…});` أو `_Sheet(this.x);`) لا نداؤه.
bool _isCtorDecl(String code, RegExpMatch m) {
  final close = closeOf(code, m.end - 1);
  final after = code.substring(close + 1).trimLeft();
  if (after.startsWith(';') || after.startsWith(':')) {
    var b = m.start - 1;
    while (b >= 0 && (code[b] == ' ' || code[b] == '\n')) {
      b--;
    }
    final before = code.substring(b - 4 < 0 ? 0 : b - 4, b + 1);
    return before.endsWith('const') || code[b] == ';' || code[b] == '{' || code[b] == '}';
  }
  return false;
}

// ─────────────────────────── ٥. شركة كتابات المال في الشاشات ───────────────────────────

/// طرق الكتابة في واجهات المال: طريقةٌ بمعامل companyKey تكتب على dio (لا قراءة بـPOST من [readsByPost]).
Set<String> moneyWriters(Lib lib, {required Set<String> readsByPost}) {
  final members = apiMembers(lib);
  final out = <String>{};
  final aliases = serverDioAliases(lib);
  final money = {for (final f in moneyApiFiles.keys) if (lib[f] != null) f: lib[f]!};
  for (final w in dioWrites(money, dioWriteRe(aliases))) {
    for (final u in w.uses) {
      if (u.path != null && readsByPost.contains(u.path)) continue;
      final m = memberAt(members, w.file, u.at);
      if (m != null && RegExp(r'\bcompanyKey\b').hasMatch(members[m]!.params)) out.add(m);
    }
  }
  return out;
}

/// شيتات المال وما يفتحها: صنفٌ أو دالّةٌ في مجلّدات أقسام المال ([moneyDirs]) تأخذ companyKey معاملاً.
Set<String> moneySheets(Lib lib) {
  final out = <String>{};
  for (final e in lib.entries) {
    if (!moneyDirs.any(e.key.startsWith)) continue;
    final code = e.value.code;
    for (final m in RegExp(r'(?:const\s+)?([A-Za-z_]\w*)\s*\(\s*\{[^{}]*\bthis\.companyKey\b').allMatches(code)) {
      out.add(m.group(1)!);
    }
    for (final m in RegExp(r'\n(?:Future<[^\n]*?>|void|Widget)\s+(\w+)\s*\(').allMatches(code)) {
      final open = m.end - 1;
      if (RegExp(r'\bcompanyKey\b').hasMatch(code.substring(open, closeOf(code, open)))) out.add(m.group(1)!);
    }
  }
  return out;
}

/// مصادر مقبولة لـcompanyKey في نداء كتابة مال: شركة القسم من شجرته (`_companyKey`، `MergedSection.routeKeyOf(context)`)، أو
/// شركة القسم المعروضة لحظة الضغط (`_co` في المبيعات — حاله تُمسح بتبدّل الشريط)، أو ما حمله الشيت من فاتحه (`widget.companyKey`،
/// معامل `companyKey`)، أو محلّيٌّ نُسخ منها. `null` (المفتوحة صراحةً) و`sub.companyKey` في مواضع مراجَعة وحدها.
const approvedKeySources = {'_co', '_companyKey', 'widget.companyKey', 'companyKey', 'key', 'MergedSection.routeKeyOf(context)'};

/// كلّ نداءٍ لكاتبة مال ([moneyWriters]) أو شيت مال ([moneySheets]) خارج lib/api ووسيط companyKey فيه: الجرد (`ملفّ مستدعى
/// companyKey: تعبير` ⇒ عدد) يُقارَن بالمراجَع، والمخالفات بالقواعد — لا قراءة للشريط (MergedMode.focus/focused)، المصدر من
/// [approvedKeySources] (null وغيره في [reviewedLiteral] وحده)، `_co`/`_companyKey` بتعريفهما المراجَع، والمحلّيّ منسوخٌ من مصدرٍ
/// مقبول (من `_co` قبل أوّل await — الشريط قد يتبدّل وشيتٌ مفتوح).
({List<String> bad, Map<String, int> inventory}) moneyKeySites(
  Lib lib, {
  required Set<String> writers,
  required Set<String> sheets,
  required Map<String, String> reviewedLiteral,
}) {
  final bad = <String>[];
  final inventory = <String, int>{};
  final callees = <RegExp, String>{
    for (final w in writers) RegExp('\\b${w.split('.').first}\\s*\\.\\s*${w.split('.').last}\\s*\\('): w,
    for (final s in sheets) RegExp('(?<![\\w.])${RegExp.escape(s)}\\s*\\('): s,
  };
  for (final e in lib.entries) {
    if (e.key.startsWith('lib/api/')) continue;
    final code = e.value.code;
    for (final c in callees.entries) {
      for (final m in c.key.allMatches(code)) {
        if (_isDef(code, m) || _isCtorDecl(code, m)) continue;
        final open = m.end - 1;
        final arg = argsOf(code, open).where((a) => a.name == 'companyKey').firstOrNull;
        final where = '${e.key}:${lineOf(code, m.start)} ${c.value}';
        if (arg == null) {
          // شيتٌ يُبنى بلا companyKey يأخذ قيمته الافتراضيّة — المفتوحة: لا يجوز
          bad.add('$where: بلا companyKey');
          continue;
        }
        final expr = _norm(code.substring(arg.at, argEnd(code, arg.at)));
        inventory['${e.key} ${c.value} companyKey: $expr'] = (inventory['${e.key} ${c.value} companyKey: $expr'] ?? 0) + 1;
        if (RegExp(r'MergedMode\.(?:focus|focused)|\bfocused\b').hasMatch(expr)) {
          bad.add('$where: companyKey من الشريط ($expr) — يتبدّل وشيتٌ مفتوح');
          continue;
        }
        final reviewed = reviewedLiteral['${e.key} ${c.value}'];
        if (!approvedKeySources.contains(expr)) {
          if (reviewed != expr) bad.add('$where: companyKey: $expr — مصدرٌ غير مراجَع');
          continue;
        }
        if (expr == '_co' && !RegExp(r'String\?\s+get\s+_co\s*=>\s*_routedCompany\s*\?\.\s*key\s*;').hasMatch(code)) {
          bad.add('$where: _co بتعريفٍ غير المراجَع');
        }
        if (expr == '_companyKey' &&
            !RegExp(r'String\?\s+get\s+_companyKey\s*=>\s*MergedSection\s*\.\s*routeKeyOf\s*\(\s*context\s*\)\s*;').hasMatch(code)) {
          bad.add('$where: _companyKey بتعريفٍ غير شجرة القسم');
        }
        if (expr == 'companyKey' || expr == 'key') {
          final fn = enclosingFn(code, m.start);
          final local = fn == null
              ? null
              : RegExp('\\b(?:final|var|String\\??)\\s+$expr\\s*=\\s*([^;]+);')
                  .allMatches(code.substring(fn.bodyOpen, m.start))
                  .lastOrNull;
          if (local != null) {
            final rhs = _norm(local.group(1)!);
            if (!approvedKeySources.contains(rhs) || rhs == expr) {
              bad.add('$where: $expr محلّيٌّ من $rhs — مصدرٌ غير مراجَع');
            } else if (rhs == '_co' && code.substring(fn!.bodyOpen, fn.bodyOpen + local.start).contains(RegExp(r'\bawait\b'))) {
              bad.add('$where: $expr نُسخ من _co بعد await — الشريط قد تبدّل');
            }
          } else if (expr == 'key' || (fn != null && !fn.params.contains('companyKey') && !_isField(code, m.start, 'companyKey'))) {
            bad.add('$where: $expr ليس معاملاً ولا حقلاً ولا محلّيّاً من مصدرٍ مراجَع');
          }
        }
      }
    }
  }
  return (bad: bad, inventory: inventory);
}

/// [name] حقلٌ في الصنف الذي يحوي [pos] (`final String? companyKey;`).
bool _isField(String code, int pos, String name) {
  final cls = RegExp(r'\nclass\s+\w+').allMatches(code).where((m) => m.start < pos).lastOrNull;
  if (cls == null) return false;
  final open = code.indexOf('{', cls.end);
  final body = code.substring(open, braceCloseOf(code, open));
  return RegExp('\\bfinal\\s+String\\?\\s+$name\\s*;').hasMatch(body);
}

// ─────────────────────────── ٩. واجهات الأقسام من خارجها ───────────────────────────

/// `open`: داخل `CompanyRoute.runOpen(` أو `CompanyRoute.pin(null,` وحدهما. `row`: `MergedOps.run/write(<صفّ>,` أو
/// `MergedOps.writeAt/pinned(<…>.companyKey,` أو `CompanyRoute.pin/run(<…>.companyKey,` — لا يقبل أحدهما غلاف الآخر.
bool openWrapper(String prefix) => prefix == 'CompanyRoute.runOpen(' || prefix == 'CompanyRoute.pin(null,';

bool rowWrapper(String prefix) =>
    RegExp(r'^MergedOps\.(?:run|write)\((?:widget\.)?[a-z]\w*,$').hasMatch(prefix) && !prefix.contains('(null,') ||
    RegExp(r'^MergedOps\.(?:writeAt|pinned)\((?:widget\.)?(?:\w+\.)?companyKey,$').hasMatch(prefix) ||
    RegExp(r'^CompanyRoute\.(?:pin|run)\((?:\w+=)?(?:widget\.)?\w+\.companyKey,$').hasMatch(prefix);

/// نداءات واجهات الأقسام ([apis]: صنف ⇒ ملفّه في lib/api) من خارج مجلّداتها ([sectionDirs]): الجرد (`ملفّ صنف.طريقة` ⇒ مواضع)،
/// ومخالفات الطريقة المراجَعة ([reviewed]: الموضع ⇒ (طريقة، سبب)).
({Map<String, List<int>> found, List<String> bad}) sectionApiSites(
  Lib lib, {
  required Map<String, String> apis,
  required List<String> sectionDirs,
  required Map<String, (String, String)> reviewed,
}) {
  final found = <String, List<int>>{};
  for (final e in lib.entries) {
    if (sectionDirs.any(e.key.startsWith)) continue;
    for (final a in apis.entries) {
      if (e.key == 'lib/api/${a.value}.dart') continue;
      for (final m in RegExp('\\b${a.key}\\s*\\.\\s*([a-z]\\w*)\\b').allMatches(e.value.code)) {
        (found['${e.key} ${a.key}.${m.group(1)}'] ??= []).add(m.start);
      }
    }
  }
  final bad = <String>[];
  for (final r in reviewed.entries) {
    final file = r.key.split(' ').first;
    final code = lib[file]?.code;
    if (code == null) continue;
    for (final at in found[r.key] ?? const <int>[]) {
      final where = '${r.key} (سطر ${lineOf(code, at)})';
      final wr = wrapperOf(code, at);
      switch (r.value.$1) {
        case 'open':
          if (wr == null || !openWrapper(wr.prefix)) bad.add('$where: ليس داخل CompanyRoute.runOpen(/pin(null, (${wr?.prefix})');
          if (wr != null && wr.deferred) bad.add('$where: داخل إغلاقٍ مؤجَّل في ${wr.prefix}');
        case 'row':
          if (wr == null || !rowWrapper(wr.prefix)) bad.add('$where: ليس بشركة صفّه (${wr?.prefix})');
          if (wr != null && wr.deferred) bad.add('$where: داخل إغلاقٍ مؤجَّل في ${wr.prefix}');
        case 'value':
          final after = code.substring(at).replaceFirst(RegExp(r'^\w+\s*\.\s*\w+'), '').trimLeft();
          if (after.startsWith('(')) bad.add('$where: نداءٌ لا قيمة');
        case 'implicit':
          break;
        default:
          bad.add('$where: طريقةٌ مجهولة ${r.value.$1}');
      }
    }
  }
  return (found: found, bad: bad);
}

/// أيّ غلافٍ وسيطه الأوّل يقرأ الشريط (`MergedMode.focus`/`focused`) خارج ودجات الشريط نفسه ([stripFiles]) — شركةٌ تتبدّل تحت
/// ما فُتح لها.
List<String> focusInWrappers(Lib lib, {required Set<String> stripFiles}) => [
      for (final e in lib.entries)
        if (!stripFiles.contains(e.key))
          for (final w in wrapperRe.allMatches(e.value.code))
            if (RegExp(r'MergedMode\.(?:focus|focused)|\bfocused\b').hasMatch(wrapperPrefix(e.value.code, w)))
              '${e.key}:${lineOf(e.value.code, w.start)} ${wrapperPrefix(e.value.code, w)}',
    ];

// ─────────────────────────── ٧. كتّابٌ لكلّ مشتركٍ على غير /api/v2/subscribers ───────────────────────────

/// رسائل المشترك وإعداد جهازه ووصله المؤرشف وتلغرامه وإشعار فايبر اكس — مساراتها خارج /api/v2/subscribers فلا يرفض المعترض
/// ضمنيّها في «كل الشركات».
const sideWriters = [
  'WhatsAppApi.sendMessage', 'WhatsAppApi.sendTemplateForSubscriber', 'WhatsAppApi.sendTemplateWithPreview',
  'DeviceConfigApi.saveConfig', 'DeviceConfigApi.resetConfig', 'PrintedReceiptsApi.archive',
  'TelegramApi.unbind', 'TelegramApi.sendLinkViaWa', 'SubscribersApi.fiberxExtendNotice',
];

/// حارس «للشركة وحدها» قبل النداء في دالّته: `final X = MergedOps.unsupported(…)` (أو `unsupportedAt`/`autoWaBlockedFor`) ثمّ
/// `if (X != null) { … return … }`.
bool _guardedBefore(String code, int bodyOpen, int at) {
  final before = code.substring(bodyOpen, at);
  for (final g in RegExp(r'final\s+(\w+)\s*=\s*(?:await\s+)?(?:MergedOps\s*\.\s*unsupported(?:At)?|autoWaBlockedFor)\s*\(')
      .allMatches(before)) {
    if (RegExp('if\\s*\\([^(){}]*\\b${g.group(1)}\\s*!=\\s*null[^(){}]*\\)\\s*\\{[^{}]*\\breturn\\b')
        .hasMatch(before.substring(g.end))) {
      return true;
    }
  }
  return false;
}

/// كلّ نداءٍ لـ[sideWriters] في lib (خارج lib/api) مراجَعٌ بطريقته ([reviewed]: `ملفّ#دالّة كاتب` ⇒ (طريقة، تفصيل، سبب)):
/// * `open` داخل CompanyRoute.runOpen · `row` بشركة صفّه ([rowWrapper]) · `guard` حارس «للشركة وحدها» قبله في دالّته
/// * `entry` (تفصيل `ملفّ#دالّة صنف`): يقع في صنفٍ لا يُبنى إلّا في تلك الدالّة وحارسها قبل بنائه
/// * `gate` (تفصيل نمط): كلّ إشارةٍ لدالّته (في lib) يسبقها النمط — زرٌّ لا يظهر إلّا له (صفٌّ بلا مفتاح، خارج الوضع، غير «للعرض»)
/// * `manager` لمديرٍ لا لمشترك (مجلّد المدراء أو إشعارهم) · `section` في قسمٍ يرفض المعترض كتابته الضمنيّة تحت شركةٍ أخرى
({List<String> bad, Set<String> seen}) sideWriterSites(Lib lib, Map<String, (String, String, String)> reviewed) {
  final bad = <String>[];
  final seen = <String>{};
  for (final e in lib.entries) {
    if (e.key.startsWith('lib/api/')) continue;
    final code = e.value.code;
    for (final w in sideWriters) {
      final (wc, wn) = (w.split('.').first, w.split('.').last);
      for (final m in RegExp('\\b$wc\\s*\\.\\s*$wn\\s*\\(').allMatches(code)) {
        final fn = enclosingFn(code, m.start);
        final key = '${e.key}#${fn?.name} $w';
        final where = '$key (سطر ${lineOf(code, m.start)})';
        seen.add(key);
        final r = reviewed[key];
        if (r == null) {
          bad.add('$where: موضعٌ غير مراجَع — ثبّته للمفتوحة أو بشركة صفّه أو بحارس «للشركة وحدها»، ثمّ أضفه بطريقته');
          continue;
        }
        final wr = wrapperOf(code, m.start);
        switch (r.$1) {
          case 'open':
            if (wr == null || wr.prefix != 'CompanyRoute.runOpen(' || wr.deferred) bad.add('$where: ليس داخل CompanyRoute.runOpen');
          case 'open-guard':
            if (wr == null || wr.prefix != 'CompanyRoute.runOpen(' || wr.deferred) bad.add('$where: ليس داخل CompanyRoute.runOpen');
            if (fn == null || !_guardedBefore(code, fn.bodyOpen, m.start)) bad.add('$where: بلا حارس «للشركة وحدها» قبله في دالّته');
          case 'row':
            if (wr == null || !rowWrapper(wr.prefix) || wr.deferred) bad.add('$where: ليس بشركة صفّه (${wr?.prefix})');
          case 'guard':
            if (fn == null || !_guardedBefore(code, fn.bodyOpen, m.start)) bad.add('$where: بلا حارس «للشركة وحدها» قبله في دالّته');
          case 'entry':
            final (entryRef, cls) = (r.$2.split(' ').first, r.$2.split(' ').last);
            final (entryFile, entryFn) = (entryRef.split('#').first, entryRef.split('#').last);
            final builds = <String>[];
            for (final f in lib.entries) {
              for (final b in RegExp('(?<![\\w.])$cls\\s*\\(').allMatches(f.value.code)) {
                if (_isDef(f.value.code, b) || _isCtorDecl(f.value.code, b)) continue;
                final bf = enclosingFn(f.value.code, b.start);
                if (f.key != entryFile || bf?.name != entryFn || !_guardedBefore(f.value.code, bf!.bodyOpen, b.start)) {
                  builds.add('${f.key}:${lineOf(f.value.code, b.start)}');
                }
              }
            }
            if (builds.isNotEmpty) bad.add('$where: $cls يُبنى بلا حارس $entryRef: $builds');
          case 'gate':
            final gate = RegExp(r.$2);
            final name = fn?.name ?? '';
            var refs = 0;
            for (final f in lib.entries) {
              for (final ref in RegExp('(?<![\\w.])$name\\b').allMatches(f.value.code)) {
                if (f.key == e.key && ref.start == fn!.start) continue;
                if (f.key == e.key && ref.start > fn!.bodyOpen && ref.start < fn.end) continue;
                refs++;
                if (!gatedRef(f.value.code, ref.start, gate)) {
                  bad.add('$where: $name يُستدعى في ${f.key}:${lineOf(f.value.code, ref.start)} بلا البوّابة ${r.$2}');
                }
              }
            }
            if (refs == 0) bad.add('$where: لا مستدعٍ لـ$name (تغيّرت الصيغة؟)');
          case 'manager':
            if (!e.key.startsWith('lib/screens/managers/') && e.key != 'lib/services/manager_notice.dart') {
              bad.add('$where: «لمدير» خارج المدراء');
            }
          case 'section':
            if (!e.key.startsWith(r.$2)) bad.add('$where: خارج القسم ${r.$2}');
          default:
            bad.add('$where: طريقةٌ مجهولة ${r.$1}');
        }
      }
    }
  }
  return (bad: bad, seen: seen);
}
