import 'package:flutter/foundation.dart';

import '../../models/fiber_network.dart';
import 'fiber_onu.dart';

/// شجرة منفذ PON واحد: موزّعاته وصناديقه (من تخطيط الوكيل) والـONU تحت كلٍّ منها (من الأولت الحيّ).
///
/// الأولت لا يعرف الصناديق: الربط بين الـONU والصندوق من [FiberLayout] (بهويّتها أوّلاً — [FiberLayout.recordFor]).
@immutable
class FiberPonTree {
  const FiberPonTree._({
    required this.oltId,
    required this.pon,
    required this.nodes,
    required this.roots,
    required this.children,
    required this.onusOf,
    required this.unassigned,
    required this.all,
    required this.boxOfKey,
  });

  final int oltId;
  final String pon;

  /// كلّ صناديق/موزّعات هذا المنفذ بالرقم.
  final Map<int, FiberBox> nodes;

  /// ما يتّصل بالمنفذ مباشرةً (بلا أبٍ، أو أبوه على منفذٍ آخر/محذوف).
  final List<FiberBox> roots;
  final Map<int, List<FiberBox>> children;

  /// الـONU المسنَدة مباشرةً لكلّ صندوق.
  final Map<int, List<FiberOnuLive>> onusOf;
  final List<FiberOnuLive> unassigned;
  final List<FiberOnuLive> all;

  /// مفتاح الـONU ← رقم صندوقه.
  final Map<String, int> boxOfKey;

  static FiberPonTree build({
    required int oltId,
    required String pon,
    required FiberLayout layout,
    required Iterable<FiberOnuLive> onus,
  }) {
    final nodes = {for (final b in layout.boxesOf(oltId, pon: pon)) b.id: b};
    final children = <int, List<FiberBox>>{};
    final roots = <FiberBox>[];
    for (final b in nodes.values) {
      final p = b.parentId;
      if (p != null && nodes.containsKey(p) && !_isAncestor(nodes, b.id, p)) {
        children.putIfAbsent(p, () => []).add(b);
      } else {
        roots.add(b);
      }
    }
    int byName(FiberBox a, FiberBox b) => a.name.compareTo(b.name);
    roots.sort(byName);
    for (final l in children.values) {
      l.sort(byName);
    }
    final mine = [
      for (final o in onus)
        if (o.pon == pon) o,
    ]..sort((a, b) => a.onu.onuId.compareTo(b.onu.onuId));
    final onusOf = <int, List<FiberOnuLive>>{};
    final unassigned = <FiberOnuLive>[];
    final boxOfKey = <String, int>{};
    for (final o in mine) {
      final rec = layout.recordFor(oltId, o.key, o.ident);
      final box = rec?.boxId;
      if (box != null && nodes.containsKey(box)) {
        onusOf.putIfAbsent(box, () => []).add(o);
        boxOfKey[o.key] = box;
      } else {
        unassigned.add(o);
      }
    }
    return FiberPonTree._(
      oltId: oltId,
      pon: pon,
      nodes: Map.unmodifiable(nodes),
      roots: List.unmodifiable(roots),
      children: Map.unmodifiable({for (final e in children.entries) e.key: List<FiberBox>.unmodifiable(e.value)}),
      onusOf: Map.unmodifiable({for (final e in onusOf.entries) e.key: List<FiberOnuLive>.unmodifiable(e.value)}),
      unassigned: List.unmodifiable(unassigned),
      all: List.unmodifiable(mine),
      boxOfKey: Map.unmodifiable(boxOfKey),
    );
  }

  /// هل [maybeAncestor] جدٌّ لـ[id]؟ (حمايةٌ من حلقةٍ أبويّة في بياناتٍ قديمة.)
  static bool _isAncestor(Map<int, FiberBox> nodes, int maybeAncestor, int id) {
    var cur = nodes[id];
    final seen = <int>{};
    while (cur != null && seen.add(cur.id)) {
      if (cur.id == maybeAncestor) return true;
      final p = cur.parentId;
      cur = p == null ? null : nodes[p];
    }
    return false;
  }

  List<FiberBox> childrenOf(int id) => children[id] ?? const [];

  /// كلّ الـONU تحت الصندوق وما تحته.
  List<FiberOnuLive> onusUnder(int id) {
    final out = <FiberOnuLive>[...?onusOf[id]];
    for (final c in childrenOf(id)) {
      out.addAll(onusUnder(c.id));
    }
    return out;
  }

  /// سلسلة الآباء من المنفذ إلى الصندوق (الأعلى أوّلاً).
  List<FiberBox> pathTo(int id) {
    final out = <FiberBox>[];
    var cur = nodes[id];
    final seen = <int>{};
    while (cur != null && seen.add(cur.id)) {
      out.insert(0, cur);
      final p = cur.parentId;
      cur = p == null ? null : nodes[p];
    }
    return out;
  }

  /// منافذ الصندوق: مستعملٌ بالـONU المسنَدة مباشرةً وبالفروع تحته (كلّ فرعٍ يأخذ مخرجاً). الفارغ = النسبة − المستعمل.
  int usedPorts(int id) => (onusOf[id]?.length ?? 0) + childrenOf(id).length;
  int freePorts(int id) {
    final b = nodes[id];
    if (b == null) return 0;
    final free = b.ratio - usedPorts(id);
    return free < 0 ? 0 : free;
  }

  /// يتّسع الصندوق لهذه الأجهزة؟ (المالك ٢٨ أكتوبر: «من احدد بوكس ١:٨ مفروض ميتقبل اكثر من هلشي».) ما كان فيه أصلاً لا
  /// يأخذ منفذاً جديداً؛ والمنقول من صندوقٍ آخر يأخذ.
  ({int free, int needed, bool ok}) fit(int boxId, Iterable<String> onuKeys) {
    final needed = {for (final k in onuKeys) if (boxOfKey[k] != boxId) k}.length;
    final free = freePorts(boxId);
    return (free: free, needed: needed, ok: nodes.containsKey(boxId) && needed <= free);
  }

  /// يتّسع الموزّع [parentId] لفرعٍ جديد ([movingId] فرعٌ موجود: إن كان تحته أصلاً فلا يأخذ منفذاً جديداً)؟
  bool canHang(int parentId, {int? movingId}) {
    if (!nodes.containsKey(parentId)) return false;
    if (movingId != null && nodes[movingId]?.parentId == parentId) return true;
    return freePorts(parentId) > 0;
  }

  /// مخارج الموزّعات/الصناديق الفارغة على هذا المنفذ (الصناديق النهائيّة وحدها — مخرج الموزّع الفارغ لا يخدم بيتاً).
  int get freeBoxPorts => [
        for (final b in nodes.values)
          if (b.kind == FiberNodeKind.box) freePorts(b.id),
      ].fold(0, (a, b) => a + b);

  int get boxCount => nodes.values.where((b) => b.kind == FiberNodeKind.box).length;
  int get onlineCount => all.where((o) => o.online).length;
}
