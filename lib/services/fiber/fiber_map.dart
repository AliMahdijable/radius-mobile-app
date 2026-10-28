import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../api/vsol_olt_api.dart';
import '../../models/fiber_network.dart';
import 'fiber_onu.dart';
import 'fiber_outage.dart';
import 'fiber_text.dart';
import 'fiber_tree.dart';

/// «مخطّط الشبكة» — المالك ٢٨ أكتوبر: «نحتاج رسم خريطة بمسارات الضوئي ٢d… رسم بياني يوضح سيرفر الترفك والربط الشبكه لالياف».
///
/// شجرةٌ من الأعلى للأسفل: السيرفر (الإنترنت) ← الأولت (ترفك الأبلنك) ← منافذ الـPON (ترفك كلّ منفذ) ← الموزّعات ←
/// الصناديق بمنافذها (شغّال/مفصول/فارغ)، و«بلا صندوق» لكلّ منفذ. الحساب هنا نقيّ (يُختبر بلا واجهة)، والرسم في الشاشة.
enum FiberMapKind { core, olt, pon, splitter, box, loose }

/// حالة ما تحت العقدة — لونها ولون خطّها.
enum FiberMapState { ok, partial, down, outage, empty, unknown }

/// منفذٌ واحد بالصندوق للرسم: شغّال/مفصول/فارغ.
enum FiberMapSlot { up, down, free }

class FiberMapNode {
  FiberMapNode({
    required this.id,
    required this.kind,
    required this.title,
    this.sub,
    this.online = 0,
    this.total = 0,
    this.state = FiberMapState.unknown,
    this.slots = const [],
    this.moreSlots = 0,
    this.downBps,
    this.upBps,
    required this.oltId,
    this.pon,
    this.boxId,
    this.hiddenBoxes = 0,
  });

  final String id;
  final FiberMapKind kind;
  final String title;
  final String? sub;
  final int online, total;
  final FiberMapState state;
  final List<FiberMapSlot> slots;

  /// منافذٌ لم تُرسم (صندوقٌ كبير أو «بلا صندوق» بأجهزةٍ كثيرة) — تُكتب «+N».
  final int moreSlots;

  /// الترفك نحو المشتركين ومنهم (بت/ثانية) — للأولت من الأبلنك، وللمنفذ من عدّاداته. `null` = لا نعرف.
  final double? downBps, upBps;
  final int oltId;
  final String? pon;
  final int? boxId;

  /// صناديق مخفيّة تحت الموزّع (إخفاء الصناديق).
  final int hiddenBoxes;
  final List<FiberMapNode> children = [];

  // يملؤها التخطيط:
  double x = 0, y = 0, w = 0, h = 0;
  int depth = 0;

  double get cx => x + w / 2;
  bool contains(double px, double py) => px >= x && px <= x + w && py >= y && py <= y + h;
}

/// أولتٌ واحد كما يحتاجه المخطّط — من [FiberMonitor] وتخطيط الوكيل.
@immutable
class FiberMapOlt {
  const FiberMapOlt({
    required this.oltId,
    required this.name,
    this.model,
    required this.pons,
    required this.onus,
    this.ponRates = const {},
    this.uplinkRates = const {},
    this.outages = const [],
    this.ready = true,
  });

  final int oltId;
  final String name;
  final String? model;
  final List<VsolPonPort> pons;
  final List<FiberOnuLive> onus;
  final Map<String, VsolTraffic> ponRates;
  final Map<String, VsolTraffic> uplinkRates;
  final List<FiberOutage> outages;

  /// قُرئ مرّةً على الأقلّ؟ لا ⇒ عقدة الأولت وحدها «يقرأ…».
  final bool ready;
}

class FiberMapModel {
  FiberMapModel._(this.root, this.nodes, this.width, this.height);

  final FiberMapNode root;
  final List<FiberMapNode> nodes;
  final double width, height;

  // المقاسات (نقاطٌ منطقيّة) — الصندوق ينمو بصفوف منافذه.
  static const nodeW = 156.0;
  static const oltW = 196.0;
  static const baseH = 54.0;

  /// السيرفر والأولت: سطرٌ ثالث لترفك الأبلنك.
  static const headH = 72.0;
  static const slotSize = 11.0;
  static const slotGap = 4.0;

  /// زاوية مربّع المنفذ — مفتاح الألوان تحت اللوحة يرسم بها أيضاً.
  static const slotRadius = 3.0;
  static const slotsPerRow = 8;
  static const maxSlotRows = 4;
  static const hGap = 22.0;
  static const vGap = 46.0;
  static const pad = 24.0;

  static double slotsHeight(int n) {
    if (n <= 0) return 0;
    final rows = math.min(maxSlotRows, (n / slotsPerRow).ceil());
    return rows * slotSize + (rows - 1) * slotGap + 10;
  }

  /// العقدة تحت النقطة (إحداثيّات اللوحة)، الأعمق أوّلاً.
  FiberMapNode? hit(double px, double py) {
    for (final n in nodes.reversed) {
      if (n.contains(px, py)) return n;
    }
    return null;
  }

  /// يبني المخطّط ويرتّبه. [showBoxes]=false ⇒ الموزّعات وحدها بأرقام صناديقها؛ [showLoose]=false ⇒ بلا «بلا صندوق».
  /// [rtl] ⇒ الأوّل يميناً (المنفذ ٠/١ أوّل منفذٍ من اليمين).
  static FiberMapModel build({
    required List<FiberMapOlt> olts,
    required FiberLayout layout,
    bool showBoxes = true,
    bool showLoose = true,
    bool rtl = true,
    String? onlyPon,
  }) {
    final upDown = olts.fold<double?>(null, (a, o) => _sum(a, _uplinkDown(o)));
    final upUp = olts.fold<double?>(null, (a, o) => _sum(a, _uplinkUp(o)));
    final allOnline = olts.fold<int>(0, (a, o) => a + o.onus.where((x) => x.online).length);
    final allTotal = olts.fold<int>(0, (a, o) => a + o.onus.length);
    final core = FiberMapNode(
      id: 'core',
      kind: FiberMapKind.core,
      title: 'السيرفر · الإنترنت',
      sub: olts.length == 1 ? 'يغذّي الأولت' : 'يغذّي ${olts.length} أولت',
      online: allOnline,
      total: allTotal,
      state: _stateOf(allOnline, allTotal, olts.any((o) => o.outages.any((e) => e.kind != FiberEventKind.power))),
      downBps: upDown,
      upBps: upUp,
      oltId: 0,
    );
    for (final o in olts) {
      core.children.add(_olt(o, layout, showBoxes: showBoxes, showLoose: showLoose, onlyPon: onlyPon));
    }
    final nodes = <FiberMapNode>[];
    _size(core, 0, nodes);
    // صفوفٌ بارتفاع أعلى عقدةٍ في كلّ عمق — الشجرة مرتّبة بصريّاً.
    final rowH = <int, double>{};
    for (final n in nodes) {
      rowH[n.depth] = math.max(rowH[n.depth] ?? 0, n.h);
    }
    final rowY = <int, double>{0: pad};
    final depths = rowH.keys.toList()..sort();
    for (final d in depths.skip(1)) {
      rowY[d] = rowY[d - 1]! + rowH[d - 1]! + vGap;
    }
    final totalW = _place(core, pad, rowY);
    final width = totalW + pad * 2;
    final height = rowY[depths.last]! + rowH[depths.last]! + pad;
    if (rtl) {
      for (final n in nodes) {
        n.x = width - n.x - n.w;
      }
    }
    return FiberMapModel._(core, List.unmodifiable(nodes), width, height);
  }

  static double? _sum(double? a, double? b) => a == null ? b : (b == null ? a : a + b);

  static double? _uplinkDown(FiberMapOlt o) {
    double? s;
    for (final v in o.uplinkRates.values) {
      s = _sum(s, v.rxBps);
    }
    return s;
  }

  static double? _uplinkUp(FiberMapOlt o) {
    double? s;
    for (final v in o.uplinkRates.values) {
      s = _sum(s, v.txBps);
    }
    return s;
  }

  static FiberMapState _stateOf(int online, int total, bool outage) {
    if (outage) return FiberMapState.outage;
    if (total == 0) return FiberMapState.empty;
    if (online == total) return FiberMapState.ok;
    if (online == 0) return FiberMapState.down;
    return FiberMapState.partial;
  }

  static FiberMapNode _olt(FiberMapOlt o, FiberLayout layout, {required bool showBoxes, required bool showLoose, String? onlyPon}) {
    final online = o.onus.where((x) => x.online).length;
    final cut = o.outages.any((e) => e.kind != FiberEventKind.power);
    final node = FiberMapNode(
      id: 'olt:${o.oltId}',
      kind: FiberMapKind.olt,
      title: o.name,
      sub: o.ready ? (o.model ?? 'OLT') : 'يقرأ الأولت…',
      online: online,
      total: o.onus.length,
      state: o.ready ? _stateOf(online, o.onus.length, cut) : FiberMapState.unknown,
      downBps: _uplinkDown(o),
      upBps: _uplinkUp(o),
      oltId: o.oltId,
    );
    if (!o.ready) return node;
    final pons = [...o.pons]..sort((a, b) => a.label.compareTo(b.label));
    for (final p in pons) {
      if (onlyPon != null && p.label != onlyPon) continue;
      node.children.add(_pon(o, p, layout, showBoxes: showBoxes, showLoose: showLoose));
    }
    return node;
  }

  static FiberMapNode _pon(FiberMapOlt o, VsolPonPort p, FiberLayout layout, {required bool showBoxes, required bool showLoose}) {
    final tree = FiberPonTree.build(oltId: o.oltId, pon: p.label, layout: layout, onus: o.onus);
    final cut = o.outages.any((e) => e.pon == p.label && e.kind != FiberEventKind.power);
    final rate = o.ponRates[p.label];
    final node = FiberMapNode(
      id: 'pon:${o.oltId}:${p.label}',
      kind: FiberMapKind.pon,
      title: fiberPonDisplay(p.label),
      sub: [
        p.technology == VsolPonTechnology.gpon ? 'GPON' : 'EPON',
        if (!p.up) 'مطفأ',
      ].join(' · '),
      online: tree.onlineCount,
      total: tree.all.length,
      state: !p.up && tree.all.isEmpty ? FiberMapState.empty : _stateOf(tree.onlineCount, tree.all.length, cut),
      downBps: rate?.txBps,
      upBps: rate?.rxBps,
      oltId: o.oltId,
      pon: p.label,
    );
    for (final b in tree.roots) {
      final c = _box(o, tree, b, showBoxes: showBoxes);
      if (c != null) node.children.add(c);
    }
    if (!showBoxes) {
      final hidden = tree.roots.where((b) => b.kind == FiberNodeKind.box).toList();
      if (hidden.isNotEmpty) node.children.add(_hiddenGroup(o, tree, hidden, p.label));
    }
    if (showLoose && tree.unassigned.isNotEmpty) {
      final loose = tree.unassigned;
      final shown = loose.take(slotsPerRow * maxSlotRows).toList();
      final online = loose.where((x) => x.online).length;
      node.children.add(FiberMapNode(
        id: 'loose:${o.oltId}:${p.label}',
        kind: FiberMapKind.loose,
        title: 'بلا صندوق',
        sub: tree.nodes.isEmpty ? 'رتّب صناديق المنفذ' : null,
        online: online,
        total: loose.length,
        state: _stateOf(online, loose.length, false),
        slots: [for (final x in shown) x.online ? FiberMapSlot.up : FiberMapSlot.down],
        moreSlots: loose.length - shown.length,
        oltId: o.oltId,
        pon: p.label,
      ));
    }
    return node;
  }

  static FiberMapNode _hiddenGroup(FiberMapOlt o, FiberPonTree tree, List<FiberBox> hidden, String pon) {
    final under = [for (final b in hidden) ...tree.onusUnder(b.id)];
    final online = under.where((x) => x.online).length;
    return FiberMapNode(
      id: 'hidden:${o.oltId}:$pon',
      kind: FiberMapKind.splitter,
      title: FiberText.boxes(hidden.length),
      sub: 'مخفيّة · على المنفذ مباشرةً',
      online: online,
      total: under.length,
      state: _stateOf(online, under.length, false),
      oltId: o.oltId,
      pon: pon,
      hiddenBoxes: hidden.length,
    );
  }

  static FiberMapNode? _box(FiberMapOlt o, FiberPonTree tree, FiberBox b, {required bool showBoxes}) {
    final splitter = b.kind == FiberNodeKind.splitter;
    if (!showBoxes && !splitter) return null;
    final under = tree.onusUnder(b.id);
    final online = under.where((x) => x.online).length;
    final outage = o.outages.any((e) => e.kind != FiberEventKind.power && (e.boxId == b.id || (under.isNotEmpty && under.every((x) => e.onuKeys.contains(x.key)))));
    final kids = tree.childrenOf(b.id);
    final hidden = showBoxes ? 0 : kids.where((k) => k.kind == FiberNodeKind.box).length;
    final mine = tree.onusOf[b.id] ?? const <FiberOnuLive>[];
    final all = <FiberMapSlot>[
      for (final x in mine) x.online ? FiberMapSlot.up : FiberMapSlot.down,
      for (final _ in kids) FiberMapSlot.up,
      for (var i = 0; i < tree.freePorts(b.id); i++) FiberMapSlot.free,
    ];
    const cap = slotsPerRow * maxSlotRows;
    final node = FiberMapNode(
      id: 'box:${o.oltId}:${b.id}',
      kind: splitter ? FiberMapKind.splitter : FiberMapKind.box,
      title: b.name,
      sub: hidden > 0 ? '1:${b.ratio} · ${FiberText.boxes(hidden)} مخفيّة' : '1:${b.ratio} · ${tree.usedPorts(b.id)}/${b.ratio}',
      online: online,
      total: under.length,
      state: _stateOf(online, under.length, outage),
      slots: splitter && !showBoxes ? const [] : all.take(cap).toList(),
      moreSlots: math.max(0, all.length - cap),
      oltId: o.oltId,
      pon: b.pon,
      boxId: b.id,
      hiddenBoxes: hidden,
    );
    for (final k in kids) {
      final c = _box(o, tree, k, showBoxes: showBoxes);
      if (c != null) node.children.add(c);
    }
    return node;
  }

  static void _size(FiberMapNode n, int depth, List<FiberMapNode> out) {
    n.depth = depth;
    final head = n.kind == FiberMapKind.core || n.kind == FiberMapKind.olt;
    n.w = head ? oltW : nodeW;
    n.h = (head ? headH : baseH) + slotsHeight(n.slots.length);
    out.add(n);
    for (final c in n.children) {
      _size(c, depth + 1, out);
    }
  }

  /// يضع الشجرة بدءاً من [left] ويُرجع عرضها: الأبناء متجاورون، والأب في وسطهم (أو في وسط عرضه إن كان أعرض).
  static double _place(FiberMapNode n, double left, Map<int, double> rowY) {
    n.y = rowY[n.depth]!;
    if (n.children.isEmpty) {
      n.x = left;
      return n.w;
    }
    var cursor = left;
    final widths = <double>[];
    for (final c in n.children) {
      final w = _place(c, cursor, rowY);
      widths.add(w);
      cursor += w + hGap;
    }
    final span = cursor - hGap - left;
    if (span >= n.w) {
      final first = n.children.first;
      final last = n.children.last;
      n.x = (first.cx + last.cx) / 2 - n.w / 2;
      // لا يخرج عن كتلته.
      n.x = n.x.clamp(left, left + span - n.w);
      return span;
    }
    // الأب أعرض من أبنائه: الأبناء في وسطه.
    final shift = (n.w - span) / 2;
    for (final c in n.children) {
      _shift(c, shift);
    }
    n.x = left;
    return n.w;
  }

  static void _shift(FiberMapNode n, double dx) {
    n.x += dx;
    for (final c in n.children) {
      _shift(c, dx);
    }
  }
}
