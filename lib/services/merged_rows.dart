import '../models/merged_company.dart';
import '../models/subscriber.dart';

/// «كل الشركات»: دمج قوائم الشركات بلا تكرار — منقولٌ حرفاً من الويب (client-v2 lib/merged.ts mergeRows/sameManagerOf، وهو من
/// chooseRows في server/accountOverview.js) فتطابق أرقام التطبيق الويبَ ولوحةَ حسابي.
///
/// المفتاح `${ns}|${idx}`؛ مشتركٌ تراه صفحتان مربوطتان فأكثر يُؤخذ مرّةً تحت **الصفحة الأقرب إليه** (قرار المالك ٢٠ أكتوبر):
///   ① صفحته المباشرة (parent_username = يوزر مديرها)؛
///   ② وإلّا أعمق الصفحات التي تراه — صفحةٌ لا صفحةَ أخرى منها داخل شجرتها (Y ترى مشتركاً مديره المباشر X، أو القائمتان
///      كاملتان وقائمة X أصغر)؛
///   ③ وإلّا الأقدم ربطاً.
/// ربطان للمدير نفسه (المجال والمعرّف نفسه) قائمةٌ واحدة: الثاني يُطوى في الأقدم ربطاً. صفٌّ بلا idx لا يُطوى. الترتيب: أوّل
/// ظهورٍ لكلّ مفتاح (بترتيب الربط) ثمّ الصفوف بلا idx.
class MergePart {
  const MergePart({required this.company, required this.rows, this.partial = false});
  final MergedCompany company;
  final List<Subscriber> rows;
  final bool partial;
}

String _lc(Object? v) => '${v ?? ''}'.trim().toLowerCase();

String _bareId(Object? id) {
  final s = '${id ?? ''}'.trim();
  final i = s.lastIndexOf(':');
  return (i >= 0 ? s.substring(i + 1) : s).toLowerCase();
}

/// هويّة المدير: المجال (ns) والمعرّف العاري.
String? managerIdentity(MergedCompany c) {
  final b = _bareId(c.adminId);
  return b.isNotEmpty && b != 'null' && b != 'undefined' && c.ns.isNotEmpty ? '${c.ns}|$b' : null;
}

/// ربطان فأكثر للمدير نفسه: مفتاح المكرّر ← الأصل (الأقدم ربطاً ممّن يحقّق [prefer]، وإلّا الأقدم مطلقاً).
Map<String, MergedCompany> sameManagerOf(List<MergedCompany> companies, {bool Function(MergedCompany c)? prefer}) {
  final groups = <String, List<MergedCompany>>{};
  for (final c in companies) {
    final id = managerIdentity(c);
    if (id == null) continue;
    final g = groups.putIfAbsent(id, () => []);
    if (!g.any((x) => x.key == c.key)) g.add(c);
  }
  final out = <String, MergedCompany>{};
  for (final g in groups.values) {
    if (g.length < 2) continue;
    final sorted = [...g]..sort((a, b) => a.index.compareTo(b.index));
    MergedCompany primary = sorted.first;
    if (prefer != null) {
      for (final c in sorted) {
        if (prefer(c)) {
          primary = c;
          break;
        }
      }
    }
    for (final c in sorted) {
      if (c.key != primary.key) out[c.key] = primary;
    }
  }
  return out;
}

class _Meta {
  _Meta(this.key, this.userLc, this.partial);
  final String key;
  final String userLc;
  final bool partial;
  final Set<String> pars = {};
  int size = 0;
}

class _Cand {
  _Cand(this.pi, this.r);
  final int pi;
  final Subscriber r;
}

/// الصفوف مدموجةً، وكلٌّ منها مربوطٌ بشركته (Subscriber.companyKey) — الصفوف نفسها لا تُعدَّل غير ذلك.
List<Subscriber> mergeRows(List<MergePart> parts) {
  final same = sameManagerOf(parts.map((p) => p.company).toList());
  final ordered = parts.where((p) => !same.containsKey(p.company.key)).toList()
    ..sort((a, b) => a.company.index.compareTo(b.company.index));
  final meta = [for (final p in ordered) _Meta(p.company.key, _lc(p.company.username), p.partial)];
  final byKey = <String, List<_Cand>>{};
  final order = <String>[];
  final loose = <Subscriber>[];
  for (var pi = 0; pi < ordered.length; pi++) {
    final p = ordered[pi];
    final ns = p.company.ns.isNotEmpty ? p.company.ns : p.company.key;
    final m = meta[pi];
    for (final r in p.rows) {
      final par = _lc(r.parentUsername);
      if (par.isNotEmpty) m.pars.add(par);
      final idx = r.idx;
      if (idx == null || idx.isEmpty) {
        loose.add(r.withCompany(m.key));
        continue;
      }
      final k = '$ns|$idx';
      final cur = byKey[k];
      if (cur == null) {
        byKey[k] = [_Cand(pi, r)];
        order.add(k);
      } else {
        // الصفّ نفسه مرّتين في قائمةٍ واحدة يُعدّ مرّة
        if (cur.any((x) => x.pi == pi)) continue;
        cur.add(_Cand(pi, r));
      }
      m.size++;
    }
  }
  bool inside(int x, int y) =>
      x != y &&
      (meta[y].pars.contains(meta[x].userLc) ||
          (!meta[x].partial && !meta[y].partial && meta[x].size < meta[y].size));
  final out = <Subscriber>[];
  for (final k in order) {
    final cur = byKey[k]!;
    if (cur.length == 1) {
      out.add(cur.first.r.withCompany(meta[cur.first.pi].key));
      continue;
    }
    _Cand? pick;
    for (final c in cur) {
      final u = meta[c.pi].userLc;
      if (u.isNotEmpty && u == _lc(c.r.parentUsername)) {
        pick = c;
        break;
      }
    }
    if (pick == null) {
      final deepest = cur.where((d) => !cur.any((e) => inside(e.pi, d.pi))).toList();
      pick = (deepest.isNotEmpty ? deepest : cur).first;
    }
    out.add(pick.r.withCompany(meta[pick.pi].key));
  }
  out.addAll(loose);
  return out;
}
