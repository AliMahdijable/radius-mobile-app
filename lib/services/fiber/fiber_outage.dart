import 'package:flutter/foundation.dart';

import '../../models/fiber_network.dart';
import 'fiber_onu.dart';
import 'fiber_tree.dart';

/// عطلٌ جماعيّ مكتشَف الآن على منفذ PON واحد.
@immutable
class FiberOutage {
  const FiberOutage({
    required this.oltId,
    required this.pon,
    required this.scope,
    required this.scopeKey,
    required this.onuKeys,
    required this.kind,
    required this.reasons,
    required this.ponTotal,
    required this.timed,
    this.boxId,
    this.startedAt,
    this.lastDropAt,
  });

  final int oltId;
  final String pon;
  final FiberEventScope scope;

  /// `box:12` · `splitter:5` · `pon:EPON0/3` · `group:EPON0/3` — هويّة العطل بين القراءات والأجهزة.
  final String scopeKey;

  /// الصندوق/الموزّع الذي تحته العطل (للنطاقين box/splitter).
  final int? boxId;
  final List<String> onuKeys;
  final FiberEventKind kind;
  final Map<FiberDropReason, int> reasons;

  /// عدد أجهزة المنفذ كلّها (للنسبة).
  final int ponTotal;

  /// من لحظات السقوط (عنقودٌ زمنيّ)؛ وإلّا من الحالة وحدها (صندوقٌ كلّه مفصول ولا نعرف متى).
  final bool timed;
  final DateTime? startedAt, lastDropAt;

  int get count => onuKeys.length;

  /// مدّة السقوط من أوّل جهازٍ لآخره.
  Duration? get spread => startedAt == null || lastDropAt == null ? null : lastDropAt!.difference(startedAt!);
}

/// يكتشف الأعطال الجماعيّة من حالة الـONU الحيّة وتخطيط الصناديق.
///
/// القاعدة: أجهزةٌ سقطت **معاً** (خلال دقيقتين) على منفذٍ واحد بعددٍ ≥ حدّ الوكيل = عطلٌ واحد. مكانه أعلى صندوقٍ (أو موزّع)
/// كلّ أجهزته مفصولة وأغلبها من هذا العطل؛ والمنفذ كلّه إن سقط ٩٠٪ منه. سببه من الأولت وحده (≥٧٠٪ من الأجهزة بسببٍ
/// واحد) — بلا سببٍ من الأولت «غير معروف»، لا تخمين.
class FiberOutageDetector {
  FiberOutageDetector._();

  static const clusterWindow = Duration(seconds: 120);

  /// عطلٌ قائم يبقى عطلاً ما دامت أجهزته مفصولة — حتى ثلاثة أيّام؛ بعدها خارج «الآن».
  static const lookback = Duration(days: 3);
  static const ponShare = 0.9;
  static const kindShare = 0.7;
  static const nodeOwnShare = 0.5;

  static List<FiberOutage> detect({
    required int oltId,
    required FiberLayout layout,
    required List<FiberOnuLive> onus,
    required DateTime now,
    int? minOnus,
  }) {
    final min = minOnus ?? layout.settingsOf(oltId).minOnus;
    final out = <FiberOutage>[];
    final pons = <String>{for (final o in onus) o.pon}.toList()..sort();
    for (final pon in pons) {
      final tree = FiberPonTree.build(oltId: oltId, pon: pon, layout: layout, onus: onus);
      final offline = tree.all.where((o) => !o.online).toList();
      if (offline.length < min) continue;
      final used = <String>{};

      // (١) عناقيد زمنيّة: سقوطٌ متقاربٌ بلحظات الأولت نفسه.
      final timed = offline
          .where((o) => o.changedAt != null && !o.changedAt!.isAfter(now.add(const Duration(minutes: 2))) &&
              now.difference(o.changedAt!) <= lookback)
          .toList()
        ..sort((a, b) => a.changedAt!.compareTo(b.changedAt!));
      var i = 0;
      while (i < timed.length) {
        final start = timed[i].changedAt!;
        var j = i;
        while (j + 1 < timed.length && timed[j + 1].changedAt!.difference(start) <= clusterWindow) {
          j++;
        }
        final cluster = timed.sublist(i, j + 1);
        if (cluster.length >= min) {
          out.add(_build(tree, cluster, timedCluster: true));
          used.addAll(cluster.map((o) => o.key));
        }
        i = j + 1;
      }

      // (٢) بلا توقيت: صندوقٌ/موزّعٌ كلّ أجهزته مفصولة (ولم يدخل عنقوداً) — أو المنفذ كلّه.
      final rest = offline.where((o) => !used.contains(o.key) && o.changedAt == null).toList();
      if (rest.length < min) continue;
      final restKeys = rest.map((o) => o.key).toSet();
      if (tree.all.isNotEmpty && offline.length >= (tree.all.length * ponShare).ceil() && used.isEmpty) {
        out.add(_build(tree, rest, timedCluster: false));
        continue;
      }
      for (final node in _maximalDown(tree, (o) => restKeys.contains(o.key))) {
        final members = tree.onusUnder(node.id).where((o) => restKeys.contains(o.key)).toList();
        if (members.length >= min) out.add(_build(tree, members, timedCluster: false));
      }
    }
    return out;
  }

  /// أعلى العُقد التي كلّ أجهزتها مفصولة وأغلبها ([nodeOwnShare]) من هذا العطل ([member]).
  static List<FiberBox> _maximalDown(FiberPonTree tree, bool Function(FiberOnuLive) member) {
    bool down(FiberBox b) {
      final under = tree.onusUnder(b.id);
      if (under.isEmpty || under.any((o) => o.online)) return false;
      final own = under.where(member).length;
      return own > 0 && own >= (under.length * nodeOwnShare).ceil();
    }

    final result = <FiberBox>[];
    void visit(FiberBox b) {
      if (down(b)) {
        result.add(b);
        return;
      }
      for (final c in tree.childrenOf(b.id)) {
        visit(c);
      }
    }

    for (final r in tree.roots) {
      visit(r);
    }
    return result;
  }

  static FiberOutage _build(FiberPonTree tree, List<FiberOnuLive> members, {required bool timedCluster}) {
    final keys = members.map((o) => o.key).toSet();
    final reasons = <FiberDropReason, int>{};
    for (final o in members) {
      final r = o.reason ?? FiberDropReason.unknown;
      reasons[r] = (reasons[r] ?? 0) + 1;
    }
    final n = members.length;
    final power = reasons[FiberDropReason.power] ?? 0;
    final fiber = reasons[FiberDropReason.fiber] ?? 0;
    final kind = power >= n * kindShare
        ? FiberEventKind.power
        : fiber >= n * kindShare
            ? FiberEventKind.cut
            : (power > 0 && fiber > 0 && power + fiber >= n * kindShare)
                ? FiberEventKind.mixed
                : FiberEventKind.unknown;

    // المكان: أعلى عقدةٍ كلّها مفصولة وتحوي ٩٠٪ من الأجهزة، وإلّا المنفذ كلّه، وإلّا مجموعة.
    final nodes = _maximalDown(tree, (o) => keys.contains(o.key));
    FiberBox? where;
    for (final b in nodes) {
      final inside = tree.onusUnder(b.id).where((o) => keys.contains(o.key)).length;
      if (inside >= (n * ponShare).ceil()) {
        where = b;
        break;
      }
    }
    final ponOffline = tree.all.where((o) => !o.online).length;
    final wholePon = tree.all.length >= 3 && ponOffline >= (tree.all.length * ponShare).ceil();
    final FiberEventScope scope;
    final String scopeKey;
    if (wholePon && (where == null || tree.onusUnder(where.id).length < ponOffline)) {
      scope = FiberEventScope.pon;
      scopeKey = 'pon:${tree.pon}';
      where = null;
    } else if (where != null) {
      scope = where.kind == FiberNodeKind.splitter ? FiberEventScope.splitter : FiberEventScope.box;
      scopeKey = '${scope.name}:${where.id}';
    } else {
      scope = FiberEventScope.group;
      scopeKey = 'group:${tree.pon}';
    }
    final times = [
      for (final o in members)
        if (o.changedAt != null) o.changedAt!,
    ]..sort();
    final sortedKeys = keys.toList()..sort(_keyOrder);
    return FiberOutage(
      oltId: tree.oltId,
      pon: tree.pon,
      scope: scope,
      scopeKey: scopeKey,
      boxId: where?.id,
      onuKeys: List.unmodifiable(sortedKeys),
      kind: kind,
      reasons: Map.unmodifiable(reasons),
      ponTotal: tree.all.length,
      timed: timedCluster,
      startedAt: times.isEmpty ? null : times.first,
      lastDropAt: times.isEmpty ? null : times.last,
    );
  }

  /// ترتيب `EPON0/3:2` قبل `EPON0/3:10` (رقميّاً).
  static int _keyOrder(String a, String b) {
    final ra = RegExp(r'(\d+)$').firstMatch(a);
    final rb = RegExp(r'(\d+)$').firstMatch(b);
    final pa = a.substring(0, ra?.start ?? a.length);
    final pb = b.substring(0, rb?.start ?? b.length);
    final c = pa.compareTo(pb);
    if (c != 0 || ra == null || rb == null) return c != 0 ? c : a.compareTo(b);
    return int.parse(ra.group(1)!).compareTo(int.parse(rb.group(1)!));
  }
}
