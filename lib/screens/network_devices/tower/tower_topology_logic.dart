import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../../../core/util/format.dart';
import '../../../models/network_device.dart';
import '../../../models/tower_layout.dart';
import '../../../theme/colors.dart';
import '../widgets/_grade.dart';
import 'tower_logic.dart' show naturalCompare;
import 'tower_reading.dart';

/// «الترابط» بين الأبراج (المالك ١١ نوفمبر: «برج a منطي ٣ لنكات ماستر والابراج الفرعي سليف وياه… يظهر رسم البرج بشكل مصغر حتى
/// يكفي للهاتف ان اكو برج رئيسي وموزع ويبين سير الترفك من الرئيسي للفرعيات»).
///
/// هذا الملفّ منطقٌ نقيّ (مختبَر بلا واجهة): من الأبراج (المناطق) واللنكات بين أجهزتها ⇒ من الرئيسيّ ومن الفرعيّ وبأيّ مستوى،
/// ومكان كلّ برجٍ على رسمٍ بعرض الهاتف، وسير الترافيك وحال كلّ وصلة من قراءات طرفيها، واقتراح الوصلات ممّا تقوله الأجهزة.

/// برجٌ في الرسم — منطقةٌ من مناطق الأجهزة ([id] = رقمها، و0 لأجهزةٍ بلا منطقة).
@immutable
class TopoTower {
  const TopoTower({required this.id, required this.name, this.color, this.devices = 0, this.answering = 0});

  final int id;
  final String name;

  /// `#RRGGBB` لون المنطقة إن اختاره الوكيل.
  final String? color;
  final int devices;

  /// ما يردّ من أجهزته الآن.
  final int answering;
}

/// وصلةٌ بين برجين: كلّ لنكاتهما بهذا الاتّجاه معاً ([from] الرئيسيّ ⇐ [to] الفرعيّ).
@immutable
class TopoEdge {
  const TopoEdge({required this.from, required this.to, required this.links, this.tree = true});

  final int from;
  final int to;
  final List<TowerLink> links;

  /// وصلة الشجرة (منها عُرف مستوى [to])؛ غيرها وصلةٌ إضافيّة لبرجٍ عُرف مستواه (مسارٌ ثانٍ أو حلقة) — تُرسم متقطّعة.
  final bool tree;
}

@immutable
class TopoNode {
  const TopoNode({required this.tower, required this.level, required this.root});

  final TopoTower tower;

  /// 0 = رئيسيّ، 1 = فرعيّ منه، 2 = فرعُ الفرعيّ…
  final int level;

  /// رأس شجرة (لا لنك يدخله).
  final bool root;
}

/// الرسم مرتّباً: صفوفٌ من الأعلى (الرئيسيّ) للأسفل، ثمّ الأبراج غير المربوطة.
@immutable
class TowerTopology {
  const TowerTopology({required this.rows, required this.loose, required this.edges, required this.broken});

  /// صفوف الرسم: كلّ مستوى صفٌّ أو أكثر (يُلفّ حين يزيد عن [build] `maxPerRow`).
  final List<List<TopoNode>> rows;

  /// أبراجٌ بلا أيّ لنك.
  final List<TopoTower> loose;
  final List<TopoEdge> edges;

  /// لنكاتٌ لا تُرسم: أحد جهازيها ليس بين الأجهزة، أو الجهازان صارا في البرج نفسه (نُقل أحدهما).
  final List<TowerLink> broken;

  bool get isEmpty => rows.isEmpty && loose.isEmpty;
  bool get hasLinks => edges.isNotEmpty;

  /// دور البرج [towerId] على الرسم.
  TopoRole roleOf(int towerId) {
    for (final n in nodes) {
      if (n.tower.id != towerId) continue;
      if (n.root) return TopoRole.main;
      return edges.any((e) => e.from == towerId) ? TopoRole.relay : TopoRole.sub;
    }
    return TopoRole.loose;
  }

  Iterable<TopoNode> get nodes => rows.expand((r) => r);

  /// [towerOfDevice]: برج كلّ جهاز (منطقته، و0 بلا منطقة). مستوى يزيد عن [maxPerRow] يُلفّ صفوفاً — وعندها كلّ الصفوف
  /// بـ[wrapPerRow] برجاً على الأكثر (أعمدة الشبكة: بينها ممرّات تنزل فيها الوصلات للصفوف التالية — [TopoLayout]).
  static TowerTopology build({
    required List<TopoTower> towers,
    required Map<int, int> towerOfDevice,
    required List<TowerLink> links,
    int maxPerRow = 4,
    int? wrapPerRow,
  }) {
    final byId = {for (final t in towers) t.id: t};
    final broken = <TowerLink>[];
    // الوصلات مجمّعةً بالاتّجاه
    final grouped = <(int, int), List<TowerLink>>{};
    for (final l in links) {
      final a = towerOfDevice[l.aDeviceId];
      final b = towerOfDevice[l.bDeviceId];
      if (a == null || b == null || a == b || !byId.containsKey(a) || !byId.containsKey(b)) {
        broken.add(l);
        continue;
      }
      grouped.putIfAbsent((a, b), () => []).add(l);
    }
    final out = <int, List<int>>{};
    final indeg = <int, int>{};
    for (final k in grouped.keys) {
      out.putIfAbsent(k.$1, () => []).add(k.$2);
      indeg[k.$2] = (indeg[k.$2] ?? 0) + 1;
      indeg.putIfAbsent(k.$1, () => 0);
    }
    final linked = indeg.keys.toSet();
    int byName(int x, int y) => naturalCompare(byId[x]!.name, byId[y]!.name);
    for (final v in out.values) {
      v.sort(byName);
    }

    final level = <int, int>{};
    final parentOrder = <int, int>{};
    final roots = <int>{};
    final treeEdges = <(int, int)>{};
    void bfs(List<int> starts) {
      var frontier = starts;
      for (final s in starts) {
        level[s] = 0;
        roots.add(s);
      }
      while (frontier.isNotEmpty) {
        final next = <int>[];
        for (final u in frontier) {
          for (final v in out[u] ?? const <int>[]) {
            if (level.containsKey(v)) continue;
            level[v] = level[u]! + 1;
            parentOrder[v] = parentOrder.length;
            treeEdges.add((u, v));
            next.add(v);
          }
        }
        frontier = next;
      }
    }

    bfs(linked.where((t) => indeg[t] == 0).toList()..sort(byName));
    // حلقةٌ بلا رأس: الأكثر تفرّعاً رأسُها
    while (level.length < linked.length) {
      final rest = linked.where((t) => !level.containsKey(t)).toList()
        ..sort((x, y) {
          final d = (out[y]?.length ?? 0) - (out[x]?.length ?? 0);
          return d != 0 ? d : byName(x, y);
        });
      bfs([rest.first]);
    }

    final maxLevel = level.values.fold<int>(-1, math.max);
    final rows = <List<TopoNode>>[];
    final perLevel = <int, int>{};
    for (final lv in level.values) {
      perLevel[lv] = (perLevel[lv] ?? 0) + 1;
    }
    final wraps = perLevel.values.any((n) => n > math.max(1, maxPerRow));
    final per = math.max(1, wraps ? math.min(maxPerRow, wrapPerRow ?? maxPerRow) : maxPerRow);
    for (var lv = 0; lv <= maxLevel; lv++) {
      final ids = level.entries.where((e) => e.value == lv).map((e) => e.key).toList()
        ..sort((x, y) {
          // أبناء الأب الواحد متجاورون وبترتيب آبائهم
          final px = parentOrder[x] ?? -1;
          final py = parentOrder[y] ?? -1;
          if (lv > 0 && px != py) return px - py;
          return byName(x, y);
        });
      for (var i = 0; i < ids.length; i += per) {
        rows.add([
          for (final id in ids.sublist(i, math.min(ids.length, i + per)))
            TopoNode(tower: byId[id]!, level: lv, root: roots.contains(id)),
        ]);
      }
    }
    final edges = [
      for (final e in grouped.entries)
        TopoEdge(from: e.key.$1, to: e.key.$2, links: List.unmodifiable(e.value), tree: treeEdges.contains(e.key)),
    ]..sort((x, y) {
        final d = byName(x.from, y.from);
        return d != 0 ? d : byName(x.to, y.to);
      });
    final loose = towers.where((t) => !linked.contains(t.id)).toList()..sort((x, y) => naturalCompare(x.name, y.name));
    return TowerTopology(rows: rows, loose: loose, edges: edges, broken: broken);
  }
}

/// دور البرج على الرسم — المالك: «يظهر… ان اكو برج رئيسي وموزع».
enum TopoRole {
  /// رأس الشبكة: لا لنك يدخله.
  main,

  /// يدخله لنك ويخرج منه لنك لبرجٍ آخر.
  relay,

  /// طرفٌ: يدخله لنك ولا يخرج منه.
  sub,

  /// بلا لنك.
  loose,
}

/// نصوص «الترابط» (بتمييز العدد العربيّ).
class TopoText {
  TopoText._();

  static String towers(int n) => n == 0 ? 'لا أبراج' : arCount(n, one: 'برج واحد', two: 'برجان', few: 'أبراج', many: 'برجاً');
  static String links(int n) => n == 0 ? 'لا لنكات' : arCount(n, one: 'لنك واحد', two: 'لنكان', few: 'لنكات', many: 'لنكاً');
  static String devices(int n) => n == 0 ? 'بلا أجهزة' : arCount(n, one: 'جهاز واحد', two: 'جهازان', few: 'أجهزة', many: 'جهازاً');

  static String role(TopoRole r) => switch (r) {
        TopoRole.main => 'رئيسي',
        TopoRole.relay => 'موزّع',
        TopoRole.sub => 'فرعي',
        TopoRole.loose => 'غير مربوط',
      };

  /// كلمة الحال — كلمات بطاقة اللنك في برجه نفسها.
  static String state(LinkState s) => switch (s) {
        LinkState.ok => 'ممتاز',
        LinkState.fair => 'متوسّط',
        LinkState.weak => 'ضعيف',
        LinkState.down => 'واقع',
        LinkState.unknown => 'لم يُقرأ',
      };
}

/// مسار وصلةٍ على الرسم: من [from] إلى [to] مباشرةً، أو عبر ممرٍّ عموديّ ([channelX] من [channelTop] إلى [channelBottom])
/// حين يفصل الطرفين صفٌّ أو أكثر — فتنزل الوصلة **بين** أبراج الصفوف الوسطى لا من خلفها.
@immutable
class TopoRoute {
  const TopoRoute({required this.from, required this.to, this.channelX, this.channelTop, this.channelBottom});

  final Offset from;
  final Offset to;
  final double? channelX;
  final double? channelTop;
  final double? channelBottom;

  bool get viaChannel => channelX != null;

  /// من أسفل الرئيسيّ لأعلى الفرعيّ (تاركةً [pillRoom] لحبّة السرعة)، ومن الجانب للجانب حين يتجاوران في صفّ، ومن الأعلى
  /// للأسفل حين يكون الفرعيّ فوق (وصلةٌ راجعة).
  static TopoRoute direct(Rect a, Rect b, {double pillRoom = 0}) {
    if (b.top >= a.bottom - 1) return TopoRoute(from: a.bottomCenter, to: Offset(b.center.dx, b.top - pillRoom));
    if (b.bottom <= a.top + 1) return TopoRoute(from: a.topCenter, to: b.bottomCenter);
    return b.center.dx >= a.center.dx
        ? TopoRoute(from: Offset(a.right, a.top + a.height * 0.3), to: Offset(b.left, b.top + b.height * 0.3))
        : TopoRoute(from: Offset(a.left, a.top + a.height * 0.3), to: Offset(b.right, b.top + b.height * 0.3));
  }

  @override
  bool operator ==(Object other) =>
      other is TopoRoute &&
      other.from == from &&
      other.to == to &&
      other.channelX == channelX &&
      other.channelTop == channelTop &&
      other.channelBottom == channelBottom;

  @override
  int get hashCode => Object.hash(from, to, channelX, channelTop, channelBottom);
}

/// أماكن الأبراج على الرسم بعرضٍ معلوم — الهاتف أوّلاً: الصفّ يتوزّع على العرض، والعمود للأسفل.
///
/// مستوى أكثر من عرض الهاتف يُلفّ صفوفاً ([TowerTopology.build])، ووصلةُ برجٍ في صفٍّ أبعد من التالي كانت تمرّ خلف أبراج
/// الصفّ الأوسط فتبدو خارجةً منها (برجٌ فرعيّ يغذّي فرعيّاً — وهو لا يغذّيه). فالصفوف التي تمرّ بها وصلاتٌ كهذه (أو تنتهي
/// عندها) تُرصّ على **أعمدة شبكة** ثابتة ([slot])، والوصلة تنزل في الممرّ بين عمودين ([routeOf]).
@immutable
class TopoLayout {
  const TopoLayout({
    required this.centers,
    required this.size,
    required this.nodeSize,
    this.looseTop,
    this.rowOf = const {},
    this.rowTops = const [],
    this.pillRoom = const {},
    this.slot,
    this.rtl = false,
  });

  /// مركز رمز كلّ برج (بمعرّفه).
  final Map<int, Offset> centers;
  final Size size;
  final Size nodeSize;

  /// أعلى صفّ «غير المربوطة» (لعنوانه) — null بلا أبراجٍ غير مربوطة أو حين لا شيء غيرها.
  final double? looseTop;

  /// صفّ كلّ برجٍ مربوط، وأعلى كلّ صفّ.
  final Map<int, int> rowOf;
  final List<double> rowTops;

  /// أقصى عرضٍ لحبّة السرعة فوق كلّ برج: لا تتراكب مع حبّة جاره، وعلى الشبكة تترك الممرّ خالياً.
  final Map<int, double> pillRoom;

  /// عرض عمود الشبكة حين تُلفّ المستويات — null: لا وصلة تتخطّى صفّاً.
  final double? slot;
  final bool rtl;

  static const pillWidest = 86.0;

  double pillMaxFor(int towerId) => pillRoom[towerId] ?? pillWidest;

  static const nodeW = 80.0;
  static const nodeH = 100.0;
  static const rowGap = 64.0;
  static const pad = 10.0;

  /// ارتفاع سطر عنوان «غير مربوطة» فوق صفّها، والمسافة بين صفوفها.
  static const looseTitle = 26.0;
  static const looseGap = 14.0;

  /// أقصى عرضٍ للرسم (الحاسبة واللوح) — أوسع منه تتباعد الأبراج بلا معنى.
  static const maxWidth = 640.0;

  /// عرض الممرّ بين عمودين — يسع خطّ الوصلة وهالته.
  static const channel = 12.0;

  /// كم برجاً يسع الصفّ بهذا العرض (٣٦٠ ⇒ ٤).
  static int perRow(double width) => math.max(2, ((width - 2 * pad) / (nodeW + 4)).floor());

  /// كم عموداً حين تُلفّ المستويات: بين كلّ عمودين ممرٌّ ([channel]) (٣٦٠ ⇒ ٣).
  static int perGrid(double width) => math.max(2, ((width - 2 * pad) / (nodeW + channel)).floor());

  /// [rtl]: الأوّل يميناً (ترتيب القراءة بالعربيّ).
  static TopoLayout compute(TowerTopology t, double width, {bool rtl = false}) {
    final centers = <int, Offset>{};
    final usable = width - 2 * pad;
    final rowOf = <int, int>{};
    for (var i = 0; i < t.rows.length; i++) {
      for (final n in t.rows[i]) {
        rowOf[n.tower.id] = i;
      }
    }
    // صفوف الشبكة: كلّ صفٍّ تمرّ به وصلةٌ تتخطّاه أو تنتهي عنده
    final grid = <int>{};
    for (final e in t.edges) {
      if (!e.tree) continue;
      final rp = rowOf[e.from];
      final rc = rowOf[e.to];
      if (rp == null || rc == null || rc <= rp + 1) continue;
      for (var r = rp + 1; r <= rc; r++) {
        grid.add(r);
      }
    }
    final cols = perGrid(width);
    final slot = usable / cols;

    var y = pad + nodeH / 2;
    final rowTops = <double>[];
    final pillRoom = <int, double>{};
    void place(List<int> ids, double gapAfter, {bool onGrid = false}) {
      final k = ids.length;
      final gridded = onGrid && k <= cols;
      for (var i = 0; i < k; i++) {
        // على الشبكة: من أوّل عمود (فالممرّات ثابتة في كلّ الصفوف)؛ وإلّا يتوزّع الصفّ على العرض
        final x = gridded ? pad + slot * (i + 0.5) : pad + usable * (i + 0.5) / k;
        centers[ids[i]] = Offset(rtl ? width - x : x, y);
        pillRoom[ids[i]] = math.min(pillWidest, gridded ? slot - channel : usable / k - 4);
      }
      y += nodeH + gapAfter;
    }

    var lastGap = 0.0;
    for (var i = 0; i < t.rows.length; i++) {
      rowTops.add(y - nodeH / 2);
      place([for (final n in t.rows[i]) n.tower.id], lastGap = rowGap, onGrid: grid.contains(i));
    }
    double? looseTop;
    if (t.loose.isNotEmpty) {
      final per = perRow(width);
      if (t.rows.isNotEmpty) {
        // عنوان «غير مربوطة» يأخذ مكانه فوق صفّها
        looseTop = y - nodeH / 2 - looseTitle;
      }
      for (var i = 0; i < t.loose.length; i += per) {
        // صفوف غير المربوطة متقاربة (لا وصلات بينها)
        place([for (final x in t.loose.sublist(i, math.min(t.loose.length, i + per))) x.id], lastGap = looseGap);
      }
    }
    final height = centers.isEmpty ? 0.0 : y - lastGap - nodeH / 2 + pad;
    return TopoLayout(
      centers: centers,
      size: Size(width, height),
      nodeSize: const Size(nodeW, nodeH),
      looseTop: looseTop,
      rowOf: rowOf,
      rowTops: rowTops,
      pillRoom: pillRoom,
      slot: grid.isEmpty ? null : slot,
      rtl: rtl,
    );
  }

  Rect rectOf(int towerId) {
    final c = centers[towerId]!;
    return Rect.fromCenter(center: c, width: nodeSize.width, height: nodeSize.height);
  }

  /// مسار الوصلة [e]: مباشرٌ لصفٍّ تالٍ (أو لوصلةٍ خارج الشجرة)، وعبر ممرّ عمود الفرعيّ حين يتخطّى صفوفاً.
  /// [pillRoom] مكان حبّة السرعة فوق الفرعيّ (وصلة الشجرة وحدها).
  TopoRoute routeOf(TopoEdge e, {double pillRoom = 0}) {
    final a = rectOf(e.from);
    final b = rectOf(e.to);
    if (!e.tree) return TopoRoute.direct(a, b);
    final rp = rowOf[e.from];
    final rc = rowOf[e.to];
    final s = slot;
    if (rp == null || rc == null || s == null || rc <= rp + 1) return TopoRoute.direct(a, b, pillRoom: pillRoom);
    // الممرّ عند حدّ عمود الفرعيّ من جهة أوّل الصفّ — لكلّ عمودٍ ممرّه، فلا تتشارك وصلتان إلّا لعمودٍ واحد
    final x = (b.center.dx + (rtl ? s / 2 : -s / 2)).clamp(pad / 2, size.width - pad / 2);
    return TopoRoute(
      from: a.bottomCenter,
      to: Offset(b.center.dx, b.top - pillRoom),
      channelX: x,
      channelTop: rowTops[rp + 1] - pillRoom,
      channelBottom: rowTops[rc - 1] + nodeH + 4,
    );
  }
}

/// حال وصلةٍ بين برجين — بألوان القسم نفسها ([Grade]): ما تقوله بطاقة اللنك في برجه يقوله الرسم.
enum LinkState {
  /// تُقرأ وإشارتها وجودتها «ممتاز» (أو لا يعطيهما الطراز).
  ok,

  /// «متوسّط».
  fair,

  /// «ضعيف» — تعمل وتحتاج انتباهاً.
  weak,

  /// أحد طرفيها لا يردّ — بفحصٍ حديثٍ أجريناه نحن، لا بلقطةٍ قديمة.
  down,

  /// لم تُقرأ (بعد، أو خارج شبكتك، أو إعدادات الجهاز) — لا يُقال عنها شيء.
  unknown;

  /// الأسوأ بينهما (الواقع أسوأ الكلّ، والمجهول لا يغلب معلوماً).
  static LinkState worse(LinkState x, LinkState y) {
    const rank = {LinkState.unknown: 0, LinkState.ok: 1, LinkState.fair: 2, LinkState.weak: 3, LinkState.down: 4};
    return rank[x]! >= rank[y]! ? x : y;
  }
}

/// سير الترافيك على لنكٍ واحد وحاله — من قراءة طرفيه.
@immutable
class LinkFlow {
  const LinkFlow({
    this.toSubBps,
    this.toMainBps,
    this.signal,
    this.ccq,
    this.state = LinkState.unknown,
    this.mainDown = false,
    this.subDown = false,
  });

  /// من البرج الرئيسيّ للفرعيّ (ما ينزل للفرع) ومن الفرعيّ للرئيسيّ — null لم يُقرأ.
  final int? toSubBps;
  final int? toMainBps;

  /// أضعف إشارة الطرفين (dBm) وأدنى CCQ.
  final int? signal;
  final int? ccq;
  final LinkState state;

  /// أيّ الطرفين لا يردّ ([LinkState.down]).
  final bool mainDown;
  final bool subDown;

  /// [ra] قراءة طرف الرئيسيّ و[rb] طرف الفرعيّ (null: لم يُقرأ أو قراءته تفشل الآن)، و[aDown]/[bDown] حكم وصولٍ حديث «لا يردّ».
  static LinkFlow of({TowerReading? ra, TowerReading? rb, bool aDown = false, bool bDown = false}) {
    if (aDown || bDown) return LinkFlow(state: LinkState.down, mainDown: aDown, subDown: bDown);
    if (ra == null && rb == null) return const LinkFlow();
    // ما يرسله طرف الرئيسيّ على الهواء = ما يستقبله طرف الفرعيّ؛ الفرعيّ أوّلاً (مستقبِلٌ لوصلةٍ واحدة، وطرف الرئيسيّ قد يخدم
    // غيره). بلا واجهةٍ لاسلكيّة مقروءة (airFiber/ميموزا): «التنزيل» كما يحسبه البرج = الاتّجاه الأكبر.
    final toSub = rb?.radioRxBps ?? ra?.radioTxBps ?? rb?.downBps ?? ra?.downBps;
    final toMain = rb?.radioTxBps ?? ra?.radioRxBps ?? rb?.upBps ?? ra?.upBps;
    final signal = _worst(ra?.signal, rb?.signal);
    final ccq = _worst(ra?.quality, rb?.quality);
    final tone = _worseTone(Grade.signal(signal), ccq == null ? AppTone.neutral : Grade.percentHigherBetter(ccq));
    return LinkFlow(
      toSubBps: toSub,
      toMainBps: toMain,
      signal: signal,
      ccq: ccq,
      state: switch (tone) {
        AppTone.danger => LinkState.weak,
        AppTone.warning => LinkState.fair,
        _ => LinkState.ok,
      },
    );
  }

  static int? _worst(int? x, int? y) => x == null ? y : (y == null ? x : math.min(x, y));

  static AppTone _worseTone(AppTone x, AppTone y) {
    int rank(AppTone t) => switch (t) { AppTone.danger => 3, AppTone.warning => 2, AppTone.success => 1, _ => 0 };
    return rank(x) >= rank(y) ? x : y;
  }

  /// عدّة لنكات بين البرجين نفسيهما: مجموع ما يعبرها، وأسوأ حالها — و«واقع» للوصلة كلّها حين تقع لنكاتها كلّها وحده (لنكٌ
  /// سليم يُبقي الفرع موصولاً؛ الواقع منها يُحسب «ضعيف» للوصلة: تحتاج انتباهاً).
  static LinkFlow merge(Iterable<LinkFlow> flows) {
    final list = flows.toList();
    if (list.isEmpty) return const LinkFlow();
    if (list.length == 1) return list.single;
    int? sum(int? Function(LinkFlow f) of) {
      int? s;
      for (final f in list) {
        final v = of(f);
        if (v != null) s = (s ?? 0) + v;
      }
      return s;
    }

    final allDown = list.every((f) => f.state == LinkState.down);
    var state = allDown ? LinkState.down : LinkState.unknown;
    if (!allDown) {
      for (final f in list) {
        state = LinkState.worse(state, f.state == LinkState.down ? LinkState.weak : f.state);
      }
    }
    return LinkFlow(
      toSubBps: sum((f) => f.toSubBps),
      toMainBps: sum((f) => f.toMainBps),
      signal: list.map((f) => f.signal).fold<int?>(null, _worst),
      ccq: list.map((f) => f.ccq).fold<int?>(null, _worst),
      state: state,
      mainDown: allDown && list.every((f) => f.mainDown),
      subDown: allDown && list.every((f) => f.subDown),
    );
  }
}

/// وصلةٌ يقولها الجهازان ولم يربطها الوكيل بعد.
@immutable
class LinkSuggestion {
  const LinkSuggestion({required this.a, required this.b, required this.why});

  /// طرف الرئيسيّ (نقطة الوصول) والفرعيّ (المستقبِل) — يقلبه الوكيل إن كان العكس.
  final NetworkDevice a;
  final NetworkDevice b;

  /// «يراه بعنوانه» · «يراه باسمه» · «التردّد نفسه».
  final String why;
}

class TowerLinkSuggest {
  TowerLinkSuggest._();

  static String _mac(String? v) => (v ?? '').toLowerCase().replaceAll(RegExp('[^0-9a-f]'), '');
  static String _name(String? v) => (v ?? '').trim().toLowerCase();

  /// عنوانان للجهاز نفسه؟ المسجَّل عندنا عنوان منفذ الشبكة، وما يراه الطرف الآخر عنوان الواجهة اللاسلكيّة — وهما عند
  /// مايكروتك ويوبيكويتي متتاليان (بايتٌ واحد يختلف بقليل) أو يختلفان ببتّ «محلّيّ» في أوّل بايت.
  @visibleForTesting
  static bool macNear(String a, String b) {
    if (a.length != 12 || b.length != 12) return false;
    if (a == b) return true;
    int? at;
    for (var i = 0; i < 6; i++) {
      if (a.substring(i * 2, i * 2 + 2) == b.substring(i * 2, i * 2 + 2)) continue;
      if (at != null) return false;
      at = i;
    }
    final x = int.parse(a.substring(at! * 2, at * 2 + 2), radix: 16);
    final y = int.parse(b.substring(at * 2, at * 2 + 2), radix: 16);
    return (x - y).abs() <= 3 || (at == 0 && (x ^ y) == 0x02);
  }

  /// من قراءات الأجهزة: طرفٌ يرى الآخر بين متّصليه (بالماك ثمّ بالاسم)، أو نقطة وصولٍ بطرفٍ واحد ومستقبِلٌ على تردّدها وحدهما.
  /// لا يُقترح ما بين جهازَي البرج نفسه، ولا ما رُبط، ولا فرعيٌّ مربوط.
  static List<LinkSuggestion> find({
    required List<NetworkDevice> devices,
    required Map<int, TowerReading> readings,
    required List<TowerLink> links,
  }) {
    int tower(NetworkDevice d) => d.regionId ?? 0;
    final linkedPairs = <(int, int)>{
      for (final l in links) ...[(l.aDeviceId, l.bDeviceId), (l.bDeviceId, l.aDeviceId)],
    };
    final subs = {for (final l in links) l.bDeviceId};
    final macs = <(String, NetworkDevice)>[];
    final byName = <String, List<NetworkDevice>>{};
    for (final d in devices) {
      final m = _mac(d.mac);
      if (m.length == 12) macs.add((m, d));
      final n = _name(d.name);
      if (n.isNotEmpty) byName.putIfAbsent(n, () => []).add(d);
    }
    // صاحب العنوان (غير القارئ نفسه [self]): المطابق تماماً، وإلّا القريب منه إن كان واحداً لا غير
    NetworkDevice? ownerOf(String mac, int self) {
      NetworkDevice? near;
      var nearCount = 0;
      for (final (m, d) in macs) {
        if (d.id == self) continue;
        if (m == mac) return d;
        if (macNear(m, mac)) {
          near = d;
          nearCount++;
        }
      }
      return nearCount == 1 ? near : null;
    }
    final out = <LinkSuggestion>[];
    final seen = <(int, int)>{};
    void add(NetworkDevice x, NetworkDevice y, String why) {
      if (x.id == y.id || tower(x) == tower(y)) return;
      final rx = readings[x.id];
      final ry = readings[y.id];
      // المستقبِل فرعيّ؛ وإن لم يُعرف فصاحب قائمة المتّصلين (x) نقطة الوصول
      final xIsSub = (rx?.isStation ?? false) && !(ry?.isStation ?? false);
      final a = xIsSub ? y : x;
      final b = xIsSub ? x : y;
      if (linkedPairs.contains((a.id, b.id)) || subs.contains(b.id)) return;
      if (!seen.add((a.id, b.id)) || seen.contains((b.id, a.id))) return;
      out.add(LinkSuggestion(a: a, b: b, why: why));
    }

    for (final x in devices) {
      final r = readings[x.id];
      if (r == null) continue;
      for (final p in r.peers) {
        final m = _mac(p.mac);
        final hit = m.length == 12 ? ownerOf(m, x.id) : null;
        if (hit != null) {
          add(x, hit, 'يراه بعنوانه');
          continue;
        }
        final named = byName[_name(p.name)];
        if (named != null && named.length == 1) add(x, named.single, 'يراه باسمه');
      }
    }
    // التردّد نفسه: نقطة وصولٍ بطرفٍ واحد على الأكثر ومستقبِلٌ، وحدهما على هذا التردّد والعرض بين كلّ الأجهزة
    final byFreq = <(int, int), List<NetworkDevice>>{};
    for (final d in devices) {
      final r = readings[d.id];
      if (r == null || !r.wireless || r.frequency == null) continue;
      byFreq.putIfAbsent((r.frequency!, r.channelWidth ?? 0), () => []).add(d);
    }
    for (final pair in byFreq.values) {
      if (pair.length != 2) continue;
      final r0 = readings[pair[0].id]!;
      final r1 = readings[pair[1].id]!;
      final ap = r0.isStation ? (r1.isStation ? null : pair[1]) : (r1.isStation ? pair[0] : null);
      if (ap == null) continue;
      final sta = identical(ap, pair[0]) ? pair[1] : pair[0];
      if ((readings[ap.id]!.clients ?? 0) > 1) continue;
      add(ap, sta, 'التردّد نفسه');
    }
    return out;
  }
}
