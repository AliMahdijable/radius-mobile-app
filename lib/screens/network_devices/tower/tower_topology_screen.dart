import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../api/tower_api.dart';
import '../../../core/util/bidi.dart';
import '../../../core/widgets/app_sheet.dart';
import '../../../core/widgets/design_sheet.dart';
import '../../../core/widgets/permission_locked.dart';
import '../../../core/widgets/sheet_scaffold.dart';
import '../../../models/device_region.dart';
import '../../../models/network_device.dart';
import '../../../models/tower_layout.dart';
import '../../../services/permissions_service.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';
import '../../desktop/desk_widgets.dart';
import '../network_device_details_screen.dart';
import 'tower_link_editor.dart';
import 'tower_link_probe.dart';
import 'tower_logic.dart';
import 'tower_paint.dart';
import 'tower_topology_logic.dart';
import 'tower_topology_paint.dart';

/// «الترابط» — المالك ١١ نوفمبر: «يربط لنكات بينهم… برج a منطي ٣ لنكات ماستر والابراج الفرعي سليف وياه بحيث يظهر رسم البرج
/// بشكل مصغر حتى يكفي للهاتف ان اكو برج رئيسي وموزع ويبين سير الترفك من الرئيسي للفرعيات».
///
/// الأبراج (مناطق الأجهزة) مصغّرةً: الرئيسيّ أعلى والفرعيّات تحته، ووصلة كلّ لنك شرطاتٌ تسير من الرئيسيّ للفرعيّ بلون حالها،
/// وفوق كلّ فرعيّ ما ينزل له الآن. الربط يُحفظ على خادمنا ([TowerApi])، والقراءات من طرفَي كلّ لنك مباشرةً ([TowerLinkProbe])
/// — «واقع» لا يُقال إلّا بفحصٍ حديث، وما لم يُقرأ «—» لا صفر.
///
/// والربط نوعان (المالك صباح ١١ نوفمبر: «اكو ابراج ترتبط مع بعضها فايبر… مرات مو لنك يعني مباشر كيبل ضوئي بين سوجات»):
/// لنكٌ لاسلكيّ (شرطات، إشارة وCCQ) وكيبلٌ ضوئيّ بين سويجين (خطٌّ متّصل بنبضات): ما يعبر **منفذه** بعينه، وسرعة المنفذ وضوء
/// الـSFP، و«واقع» حين يقول السويج نفسه إنّ المنفذ طافٍ.
class TowerTopologyScreen extends StatefulWidget {
  const TowerTopologyScreen({
    super.key,
    required this.devices,
    required this.regions,
    required this.onOpenTower,
    this.switcher,
    this.onNewTower,
  });

  /// أجهزة الشركة المفتوحة كلّها (برج كلّ جهازٍ منطقته، و0 بلا منطقة).
  final List<NetworkDevice> devices;
  final List<DeviceRegion> regions;

  /// نقرة برج ⇒ يُفتح (القسم ينتقل إليه).
  final ValueChanged<int> onOpenTower;

  /// شريط التنقّل بين الأبراج (من «أبراجي») تحت العنوان.
  final PreferredSizeWidget? switcher;

  /// «برج جديد» — null: لا يُعرض.
  final VoidCallback? onNewTower;

  /// للاختبار: قارئٌ مزيّف مكان [TowerLinkProbe].
  @visibleForTesting
  static TowerLinkProbe Function()? debugProbe;

  /// لقطة الخادم أقدم من هذا لا تقول «لا يردّ» عن جهاز.
  static const statusFreshFor = Duration(minutes: 5);

  @override
  State<TowerTopologyScreen> createState() => _TowerTopologyScreenState();
}

class _TowerTopologyScreenState extends State<TowerTopologyScreen> with SingleTickerProviderStateMixin {
  late final TowerLinkProbe _probe = TowerTopologyScreen.debugProbe?.call() ?? TowerLinkProbe();
  late final AnimationController _flow = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));

  TowerLayouts _layouts = TowerLayouts.empty;
  List<TowerLink> _links = const [];
  bool _loading = true;
  bool _loadedOk = false;
  final Set<int> _busy = {};

  /// يتغيّر مع كلّ تغييرٍ في اللنكات أو انشغالها — ورقة اللنك المفتوحة (مسارٌ آخر لا يبنيه `setState`) تتبعه.
  final _changed = ValueNotifier<int>(0);

  void _update(VoidCallback fn) {
    setState(fn);
    _changed.value++;
  }

  bool get _canEdit => Perms.has('devices.manage');
  bool get _ready => _loadedOk && _layouts.linksReady;

  /// الخادم يحفظ الكيبل الضوئيّ (الهجرة 087) — وإلّا اللنك اللاسلكيّ وحده.
  bool get _fiberReady => _ready && _layouts.fiberReady;

  /// الجهاز بمعرّفه وبرجه (منطقته، و0 بلا منطقة) — تُحسب مرّةً لكلّ قائمة أجهزة.
  Map<int, NetworkDevice> _byId = const {};
  Map<int, int> _towerOf = const {};

  void _index() {
    _byId = {for (final d in widget.devices) d.id: d};
    _towerOf = {for (final d in widget.devices) d.id: d.regionId ?? 0};
  }

  @override
  void initState() {
    super.initState();
    _index();
    _probe.start();
    _load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (still) {
      _flow.stop();
    } else if (!_flow.isAnimating) {
      _flow.repeat();
    }
  }

  @override
  void didUpdateWidget(TowerTopologyScreen old) {
    super.didUpdateWidget(old);
    if (!identical(old.devices, widget.devices)) {
      _index();
      _syncProbe();
    }
  }

  @override
  void dispose() {
    _probe.dispose();
    _flow.dispose();
    _changed.dispose();
    super.dispose();
  }

  // ── البيانات ────────────────────────────────────────────────────────────────────────────

  Future<void> _load() async {
    final r = await TowerApi.load();
    if (!mounted) return;
    _update(() {
      _loading = false;
      _loadedOk = r.ok;
      if (r.ok) {
        _layouts = r.layouts;
        _links = r.layouts.links;
      }
    });
    _syncProbe();
  }

  /// أطراف اللنكات تُقرأ كلّ دورة؛ وما قد يكون طرف لنكٍ لم يُربط بعد يُقرأ مرّةً (لاقتراح الوصلات) لمن يملك الربط:
  /// الصحون وما سُجّل «لنك» أوّلاً، ثمّ باقي اللاسلكيّ (سكترٌ أو لوحةٌ تُستعمل لنكاً) — حتى [TowerLinkProbe.scanCap].
  void _syncProbe() {
    final ids = {for (final l in _links) ...[l.aDeviceId, l.bDeviceId]};
    final ends = <NetworkDevice>[];
    final others = <NetworkDevice>[];
    for (final d in widget.devices) {
      (ids.contains(d.id) ? ends : others).add(d);
    }
    var scan = const <NetworkDevice>[];
    if (_ready && _canEdit) {
      int? rank(NetworkDevice d) => switch (TowerShapes.detect(d).shape) {
            TowerShape.dish => 0,
            TowerShape.panel || TowerShape.sector || TowerShape.omni => d.type == 'link' ? 0 : 1,
            _ => d.type == 'link' ? 0 : null,
          };
      final ranked = [
        for (final d in others)
          if (rank(d) != null) d,
      ]..sort((x, y) {
          final r = rank(x)! - rank(y)!;
          return r != 0 ? r : x.id - y.id;
        });
      scan = ranked;
    }
    _probe.setDevices(ends: ends, others: others, scanOnce: scan);
  }

  /// أجهزةٌ بلا منطقة — ليست برجاً على الرسم (إلّا إن رُبط أحدها بلنك)، ويُذكر عددها تحته.
  int get _orphans => _towerOf.values.where((t) => t == 0).length;

  List<TopoTower> _towers() {
    final count = <int, int>{};
    for (final t in _towerOf.values) {
      count[t] = (count[t] ?? 0) + 1;
    }
    final linkedOrphan = _links.any((l) => _towerOf[l.aDeviceId] == 0 || _towerOf[l.bDeviceId] == 0);
    return [
      for (final r in widget.regions)
        if ((count[r.id] ?? 0) > 0) TopoTower(id: r.id, name: r.name, color: r.color, devices: count[r.id]!),
      if (linkedOrphan && (count[0] ?? 0) > 0) TopoTower(id: 0, name: 'بلا منطقة', devices: count[0]!),
    ];
  }

  String _towerName(int id) =>
      id == 0 ? 'بلا منطقة' : (widget.regions.where((r) => r.id == id).firstOrNull?.name ?? 'برج');

  /// أجهزة البرج التي «لا تردّ» بلقطةٍ حديثة من جولات القسم — خارج الشبكة لا يُقال شيء.
  int _silentIn(int towerId) {
    if (_probe.offNetwork) return 0;
    final now = DateTime.now();
    var n = 0;
    for (final d in widget.devices) {
      if ((d.regionId ?? 0) != towerId || d.lastStatus != 'offline') continue;
      final at = d.lastProbedAt;
      if (at != null && now.difference(at) <= TowerTopologyScreen.statusFreshFor) n++;
    }
    return n;
  }

  /// طرف رئيسيّ واحد لعدّة لنكات لاسلكيّة (ماستر بعدّة سليفات): ما يعبر واجهته مجموعُها كلّها، لا لنكٌ بعينه — فلا يُنسب
  /// لأيٍّ منها؛ قراءة طرف الفرعيّ وحدها تقول ما يعبر لنكه (وإلّا «—» لا مجموعٌ يُكرَّر على كلّ لنك). الكيبل لا يلزمه هذا:
  /// لكلّ كيبلٍ منفذه وعدّاده.
  bool _sharedMain(TowerLink l) => _links.where((x) => !x.isFiber && x.aDeviceId == l.aDeviceId).length > 1;

  LinkFlow _flowOf(TowerLink l) => l.isFiber
      ? LinkFlow.ofFiber(
          ra: _probe.readingOf(l.aDeviceId),
          rb: _probe.readingOf(l.bDeviceId),
          aPort: l.aPort,
          bPort: l.bPort,
          aDown: _probe.isDown(l.aDeviceId),
          bDown: _probe.isDown(l.bDeviceId),
        )
      : LinkFlow.of(
          ra: _sharedMain(l) ? null : _probe.readingOf(l.aDeviceId),
          rb: _probe.readingOf(l.bDeviceId),
          aDown: _probe.isDown(l.aDeviceId),
          bDown: _probe.isDown(l.bDeviceId),
        );

  // ── الأفعال ─────────────────────────────────────────────────────────────────────────────

  bool _guard() {
    if (!_canEdit) {
      showNoPermission(context, action: true);
      return false;
    }
    if (!_ready) {
      showSheetSnack(context, 'الربط غير متاح الآن — أعد المحاولة بعد قليل', isError: true, autoExplain: false);
      return false;
    }
    return true;
  }

  Future<void> _openEditor({TopoTower? from}) async {
    if (!_guard()) return;
    final link = await Navigator.of(context).push<TowerLink>(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => TowerLinkEditorScreen(
        devices: widget.devices,
        towerName: _towerName,
        links: _links,
        suggestions: _suggestions(),
        fromTower: from?.id,
        fiberReady: _fiberReady,
        readDevice: _probe.readOnce,
        knownReading: (id) => _probe.known[id],
      ),
    ));
    if (link == null || !mounted) return;
    _putLink(link);
    showSheetSnack(context, link.isFiber ? 'رُبط الكيبل' : 'رُبط اللنك');
  }

  /// منفذ الكيبل عند أحد طرفيه — يُختار من منافذ الجهاز كما تُقرأ الآن.
  Future<void> _setPort(TowerLink l, {required bool main}) async {
    if (!_guard() || _busy.contains(l.id)) return;
    final d = _byId[main ? l.aDeviceId : l.bDeviceId];
    if (d == null) return;
    final peer = _probe.readingOf(main ? l.bDeviceId : l.aDeviceId);
    final r = await showTowerPortPicker(
      context,
      device: d,
      main: main,
      current: main ? l.aPort : l.bPort,
      taken: fiberPortsTaken(_links, d.id, except: l.id),
      readDevice: _probe.readOnce,
      known: _probe.known[d.id],
      // منفذ الطرف الآخر كما يُقرأ الآن — به يُعلَّم المنفذ المطابق
      peer: peer?.port(main ? l.bPort : l.aPort),
      peerAt: peer?.at,
    );
    if (r == null || !mounted) return;
    await _saveMedium(l, kind: TowerLinkKind.fiber, aPort: main ? r.port : l.aPort, bPort: main ? l.bPort : r.port);
  }

  /// تحويل النوع من تفاصيل الوصلة. من كيبلٍ اختير منفذه إلى لنك: المنفذان يُمسحان (اللنك بلا منافذ) — فيُسأل أوّلاً.
  Future<void> _convert(TowerLink l, TowerLinkKind kind) async {
    if (!_guard() || _busy.contains(l.id)) return;
    if (kind == TowerLinkKind.radio && (l.aPort != null || l.bPort != null)) {
      final sure = await showConfirmSheet(
        context,
        title: 'تحويله إلى لنك لاسلكي',
        message: 'يُمسح منفذ الكيبل المحدَّد عند الطرفين. إن رجعت للكيبل تختاره من جديد.',
        confirmLabel: 'حوّله',
        icon: LucideIcons.radioTower,
      );
      if (sure != true || !mounted) return;
    }
    await _saveMedium(l, kind: kind, aPort: l.aPort, bPort: l.bPort);
  }

  /// نوع الربط (لنك لاسلكيّ ⇄ كيبل ضوئيّ) ومنفذا الكيبل.
  Future<void> _saveMedium(TowerLink l, {required TowerLinkKind kind, String? aPort, String? bPort}) async {
    if (!_guard() || _busy.contains(l.id)) return;
    if (kind == TowerLinkKind.fiber && !_fiberReady) {
      showSheetSnack(context, 'الربط بالكيبل الضوئيّ غير متاح الآن — أعد المحاولة بعد قليل', isError: true, autoExplain: false);
      return;
    }
    _update(() => _busy.add(l.id));
    final r = await TowerApi.setLinkMedium(l.id, kind: kind, aPort: aPort, bPort: bPort);
    if (!mounted) return;
    _update(() => _busy.remove(l.id));
    if (!r.ok || r.link == null) {
      showSheetSnack(context, r.message ?? 'تعذّر تعديل الربط', isError: true);
      return;
    }
    _putLink(r.link!);
  }

  void _putLink(TowerLink link) {
    _update(() => _links = [for (final l in _links) if (l.id != link.id) l, link]);
    _syncProbe();
  }

  Future<void> _linkSuggested(LinkSuggestion s) async {
    if (!_guard() || _busy.contains(-s.b.id)) return;
    _update(() => _busy.add(-s.b.id));
    final r = await TowerApi.addLink(s.a.id, s.b.id);
    if (!mounted) return;
    _update(() => _busy.remove(-s.b.id));
    if (!r.ok || r.link == null) {
      showSheetSnack(context, r.message ?? 'تعذّر حفظ الربط', isError: true);
      return;
    }
    _putLink(r.link!);
    showSheetSnack(context, 'رُبط «${s.a.name}» بـ«${s.b.name}»');
  }

  Future<bool> _flip(TowerLink l) async {
    if (!_guard() || _busy.contains(l.id)) return false;
    _update(() => _busy.add(l.id));
    final r = await TowerApi.updateLink(l.id, flip: true);
    if (!mounted) return false;
    _update(() => _busy.remove(l.id));
    if (!r.ok || r.link == null) {
      showSheetSnack(context, r.message ?? 'تعذّر قلب الاتّجاه', isError: true);
      return false;
    }
    _putLink(r.link!);
    return true;
  }

  Future<bool> _delete(TowerLink l) async {
    if (!_guard() || _busy.contains(l.id)) return false;
    final a = _byId[l.aDeviceId]?.name ?? 'جهاز';
    final b = _byId[l.bDeviceId]?.name ?? 'جهاز';
    final sure = await showConfirmSheet(
      context,
      title: 'حذف الربط',
      message: 'يُحذف ربط «$a» بـ«$b» من الرسم. الجهازان وأبراجهما لا يتغيّران.',
      confirmLabel: 'احذف الربط',
      icon: LucideIcons.unlink,
      tone: AppTone.danger,
    );
    if (sure != true || !mounted) return false;
    _update(() => _busy.add(l.id));
    final r = await TowerApi.deleteLink(l.id);
    if (!mounted) return false;
    _update(() => _busy.remove(l.id));
    if (!r.ok) {
      showSheetSnack(context, r.message ?? 'تعذّر حذف الربط', isError: true);
      return false;
    }
    _update(() => _links = [for (final x in _links) if (x.id != l.id) x]);
    _syncProbe();
    return true;
  }

  Future<void> _openDevice(NetworkDevice d) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => NetworkDeviceDetailsScreen(device: d)));
    if (mounted) _probe.refreshNow(only: d.id);
  }

  List<LinkSuggestion> _suggestions() => !_ready || !_canEdit
      ? const []
      : TowerLinkSuggest.find(devices: widget.devices, readings: _probe.known, links: _links);

  Future<void> _openLink(TowerLink link) => showAppSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        barrierColor: AppColors.scrim,
        builder: (ctx) => ListenableBuilder(
          listenable: Listenable.merge([_probe, _changed]),
          builder: (ctx, _) {
            // اللنك كما هو الآن (قُلب أو حُذف والورقة مفتوحة)
            final l = _links.where((x) => x.id == link.id).firstOrNull;
            if (l == null) return const SizedBox.shrink();
            final a = _byId[l.aDeviceId];
            final b = _byId[l.bDeviceId];
            return _LinkSheet(
              link: l,
              a: a,
              b: b,
              aTower: a == null ? '—' : _towerName(a.regionId ?? 0),
              bTower: b == null ? '—' : _towerName(b.regionId ?? 0),
              flow: _flowOf(l),
              note: _noteOf(l, _flowOf(l)),
              probe: _probe,
              canEdit: _canEdit,
              fiberReady: _fiberReady,
              busy: _busy.contains(l.id),
              onOpenDevice: (d) {
                Navigator.of(ctx).pop();
                _openDevice(d);
              },
              onPort: (main) => _setPort(l, main: main),
              onKind: (kind) => _convert(l, kind),
              onFlip: () => _flip(l),
              onDelete: () async {
                final nav = Navigator.of(ctx);
                if (await _delete(l) && nav.mounted) nav.pop();
              },
            );
          },
        ),
      );

  /// حبّة وصلةٍ بين برجين: لنكٌ واحد ⇒ تفاصيله، وعدّة لنكات ⇒ قائمتها.
  Future<void> _openEdge(TopoEdge e) async {
    HapticFeedback.selectionClick();
    if (e.links.length == 1) return _openLink(e.links.single);
    final picked = await showAppSheet<TowerLink>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: AppColors.scrim,
      builder: (ctx) => DesignSheet(
        header: SheetHeaderBar(
          icon: e.fiber ? LucideIcons.cable : LucideIcons.link,
          title: '${_towerName(e.from)} ← ${_towerName(e.to)}',
          subtitle: TopoText.linkCounts(
            radio: e.links.where((l) => !l.isFiber).length,
            fiber: e.links.where((l) => l.isFiber).length,
          ),
          onClose: () => Navigator.of(ctx).pop(),
        ),
        body: Column(mainAxisSize: MainAxisSize.min, children: [
          for (final l in e.links) _linkRow(l, _flowOf(l), onTap: () => Navigator.of(ctx).pop(l), inSheet: true),
        ]),
      ),
    );
    if (picked != null && mounted) await _openLink(picked);
  }

  // ── البناء ─────────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: deskPageBar(
        context,
        mobile: AppBar(
          title: const Text('ترابط الأبراج'),
          backgroundColor: AppColors.surface,
          foregroundColor: AppColors.textHi,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(LucideIcons.arrowRight, size: 20),
            onPressed: () => Navigator.pop(context),
          ),
          actions: [
            // لبرجين فأكثر — برجٌ واحد لا يُربط بشيء
            if (_towers().length >= 2)
              IconButton(
                tooltip: 'ربط برجين — لنك أو كيبل',
                icon: Icon(_canEdit ? LucideIcons.link : LucideIcons.lock, size: 20),
                onPressed: _loading ? null : _openEditor,
              ),
            const SizedBox(width: 4),
          ],
          bottom: widget.switcher,
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : LayoutBuilder(
              builder: (context, c) => ListenableBuilder(listenable: _probe, builder: (context, _) => _content(context, c)),
            ),
    );
  }

  Widget _content(BuildContext context, BoxConstraints c) {
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final width = math.max(240.0, math.min(c.maxWidth - 2 * Sp.lg - 2, TopoLayout.maxWidth));
    final towers = _towers();
    final topo = TowerTopology.build(
      towers: towers,
      towerOfDevice: _towerOf,
      links: _links,
      maxPerRow: TopoLayout.perRow(width),
      wrapPerRow: TopoLayout.perGrid(width),
    );
    final layout = TopoLayout.compute(topo, width, rtl: rtl);
    final flows = {for (final l in _links) l.id: _flowOf(l)};
    final suggestions = _suggestions();

    return RefreshIndicator(
      onRefresh: () async {
        await _load();
        _probe.refreshNow();
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.only(bottom: Inset.route(context)),
        children: [
          _headLine(topo),
          if (!_loadedOk)
            _notice(
              AppTone.warning,
              LucideIcons.cloudOff,
              'تعذّر جلب الترابط من الخادم — الأبراج تظهر بلا لنكاتها.',
              action: 'أعد المحاولة',
              onAction: () {
                setState(() => _loading = true);
                _load();
              },
            )
          else if (!_layouts.linksReady)
            _notice(AppTone.neutral, LucideIcons.info, 'الربط بين الأبراج غير متاح الآن.')
          else if (_probe.offNetwork && topo.hasLinks)
            _notice(
              AppTone.neutral,
              LucideIcons.wifiOff,
              'أنت خارج شبكة أجهزتك — سير الترافيك يظهر حين تتّصل بها أو تفعّل «وضع VPN».',
            ),
          if (towers.length < 2 && !topo.hasLinks) ...[
            _emptyTowers(towers),
            if (topo.broken.isNotEmpty) _brokenSection(topo.broken),
          ] else ...[
            if (topo.hasLinks) _kpis(topo, flows),
            _drawing(topo, layout, flows),
            if (_orphans > 0 && !towers.any((t) => t.id == 0)) _orphansLine(),
            // الدعوة للربط حين يمكن الربط — لا مع «تعذّر الجلب» أو خادمٍ لا يحفظه
            if (!topo.hasLinks && _ready) _linkHint(),
            if (topo.hasLinks) _linksSection(topo, flows),
            if (suggestions.isNotEmpty) _suggestSection(suggestions),
            if (topo.broken.isNotEmpty) _brokenSection(topo.broken),
            if (topo.hasLinks)
              Padding(
                padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, 0),
                child: Text(
                  'القراءات من طرفَي كلّ وصلة مباشرةً وتتحدّث كلّ ${_probe.refreshEvery.inSeconds} ثانية.',
                  textAlign: TextAlign.center,
                  style: AppType.muted(color: AppColors.textMid),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _headLine(TowerTopology topo) {
    final n = topo.nodes.length + topo.loose.length;
    final live = topo.hasLinks && !_probe.offNetwork;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, Sp.sm),
      child: Row(children: [
        if (live) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
            decoration: BoxDecoration(color: AppTone.success.softBg, borderRadius: BorderRadius.circular(R.pill)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 7, height: 7, decoration: BoxDecoration(color: AppColors.success, shape: BoxShape.circle)),
              const SizedBox(width: 6),
              Text('مباشر', style: AppType.pillBold(color: AppTone.success.onSoft)),
            ]),
          ),
          const SizedBox(width: Sp.sm),
        ],
        Expanded(
          child: Text(
            '${TopoText.towers(n)} · ${TopoText.linkCounts(radio: _drawn(topo, fiber: false), fiber: _drawn(topo, fiber: true))}',
            style: AppType.body(color: AppColors.textMid),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ]),
    );
  }

  /// ما يُرسم من الوصلات بنوعه (ما لا يُرسم — طرفاه في برجٍ واحد — خارج العدّ).
  int _drawn(TowerTopology topo, {required bool fiber}) =>
      topo.edges.fold<int>(0, (n, e) => n + e.links.where((l) => l.isFiber == fiber).length);

  bool _anyFiber(TowerTopology topo) => topo.edges.any((e) => e.links.any((l) => l.isFiber));

  Widget _notice(AppTone tone, IconData icon, String text, {String? action, VoidCallback? onAction}) => Padding(
        padding: const EdgeInsets.fromLTRB(Sp.lg, 0, Sp.lg, Sp.sm),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(color: tone.softBg, borderRadius: BorderRadius.circular(R.md)),
          // النصّ يلتفّ على أسطره كاملاً، والزرّ (إن وُجد) في سطرٍ تحته — لا يزاحمه فيُسحق على الهاتف الضيّق
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(icon, size: 16, color: tone.onSoft),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(text, style: AppType.body(color: tone.onSoft)),
                if (action != null)
                  TextButton(
                    onPressed: onAction,
                    style: TextButton.styleFrom(
                      minimumSize: const Size(44, 36),
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      foregroundColor: AppColors.brand,
                    ),
                    child: Text(action, style: AppType.bodyBold(color: AppColors.brand)),
                  ),
              ]),
            ),
          ]),
        ),
      );

  Widget _kpis(TowerTopology topo, Map<int, LinkFlow> flows) {
    final roots = {for (final n in topo.nodes) if (n.root) n.tower.id};
    // ما يوزّعه الرئيسيّ: مجموع ما يعبر وصلاته الشغّالة. الواقعة لا يعبرها شيء فلا تُعدّ؛ والتي تعمل ولم يُقرأ ما يعبرها (طرفٌ
    // لم يُقرأ، منفذٌ بلا عدّادات عبر VPN، كيبلٌ بلا منفذ) تجعل المجموع ناقصاً — فيُقال «المقروء N من M» لا «إلى M أبراج».
    int? out;
    var alive = 0, measured = 0;
    final fed = <int>{};
    for (final e in topo.edges) {
      if (!roots.contains(e.from)) continue;
      for (final l in e.links) {
        final f = flows[l.id]!;
        if (f.state == LinkState.down) continue;
        alive++;
        fed.add(e.to);
        final v = f.toSubBps;
        if (v == null) continue;
        out = (out ?? 0) + v;
        measured++;
      }
    }
    final outFoot = alive == 0
        ? 'لا وصلة تعمل'
        : (measured > 0 && measured < alive ? 'المقروء $measured من $alive' : TopoText.toTowers(fed.length));
    final all = [for (final e in topo.edges) ...e.links.map((l) => flows[l.id]!)];
    final working = all.where((f) => f.state == LinkState.ok || f.state == LinkState.fair || f.state == LinkState.weak).length;
    final down = all.where((f) => f.state == LinkState.down).length;
    final weak = all.where((f) => f.state == LinkState.weak).length;
    final linksFoot = down > 0
        ? '$down واقع'
        : (working < all.length
            ? '${all.length - working} لم يُقرأ'
            : (weak > 0 ? '$weak ضعيف' : 'كلّها تعمل'));
    final towers = topo.nodes.length + topo.loose.length;

    Widget tile(String label, String value, String foot, {Color? footColor}) => Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(R.md),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: AppType.muted(color: AppColors.textMid), maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerStart,
                child: Text(iso(value), style: AppType.statValue(color: AppColors.textHi), maxLines: 1),
              ),
              Text(foot, style: AppType.micro(color: footColor ?? AppColors.textMid), maxLines: 1, overflow: TextOverflow.ellipsis),
            ]),
          ),
        );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Sp.lg),
      child: Row(children: [
        tile('يوزّع الرئيسي', TowerText.bps(out), outFoot),
        const SizedBox(width: Sp.sm),
        tile(_anyFiber(topo) ? 'الوصلات' : 'اللنكات', '$working/${all.length}', linksFoot,
            footColor: down > 0 || (weak > 0 && working == all.length) ? AppColors.error : null),
        const SizedBox(width: Sp.sm),
        tile('الأبراج', '$towers', topo.loose.isEmpty ? 'كلّها مربوطة' : '${topo.loose.length} غير مربوط'),
      ]),
    );
  }

  // ── الرسم ──────────────────────────────────────────────────────────────────────────────

  static const _pillRoom = 26.0;

  Widget _drawing(TowerTopology topo, TopoLayout layout, Map<int, LinkFlow> flows) {
    final shapes = <TopoEdgeShape>[];
    final pills = <Widget>[];
    for (final e in topo.edges) {
      final b = layout.rectOf(e.to);
      final flow = LinkFlow.merge(e.links.map((l) => flows[l.id]!));
      final shape = TopoEdgeShape(
        route: layout.routeOf(e, pillRoom: _pillRoom),
        state: flow.state,
        tree: e.tree,
        hasPill: e.tree,
        fiber: e.fiber,
      );
      shapes.add(shape);
      // وصلة الشجرة: ما ينزل للفرعيّ فوقه مباشرةً؛ غيرها حبّتها في منتصفها
      final at = e.tree ? Offset(b.center.dx, b.top - _pillRoom / 2 - 1) : shape.middle;
      // مساحة اللمس أوسع من الحبّة (٢٢ ارتفاعاً لا تكفي إصبعاً): تمتدّ فوقها على طرف الوصلة، لا على البرج تحتها
      pills.add(Positioned(
        left: at.dx - 44,
        top: at.dy - 26,
        width: 88,
        height: 38,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _openEdge(e),
          child: Align(
            alignment: Alignment.bottomCenter,
            child: SizedBox(
              height: 24,
              child: Center(child: _edgePill(e, flow, e.tree ? layout.pillMaxFor(e.to) : TopoLayout.pillWidest)),
            ),
          ),
        ),
      ));
    }
    final types = _layouts.towers;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, 0),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(R.lg),
          border: Border.all(color: AppColors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(children: [
          Center(
            child: SizedBox(
              key: const ValueKey('topo-canvas'),
              width: layout.size.width,
              height: layout.size.height,
              child: Stack(clipBehavior: Clip.none, children: [
                Positioned.fill(
                  child: RepaintBoundary(child: CustomPaint(painter: TopoEdgesPainter(edges: shapes, flow: _flow))),
                ),
                if (layout.looseTop != null)
                  Positioned(
                    top: layout.looseTop,
                    left: 0,
                    right: 0,
                    child: Row(children: [
                      const SizedBox(width: Sp.md),
                      Text('غير مربوطة', style: AppType.microBold(color: AppColors.textMid)),
                      const SizedBox(width: Sp.sm),
                      Expanded(child: Container(height: 1, color: AppColors.divider)),
                      const SizedBox(width: Sp.md),
                    ]),
                  ),
                for (final n in topo.nodes)
                  Positioned.fromRect(
                    rect: layout.rectOf(n.tower.id),
                    child: _node(n.tower, topo.roleOf(n.tower.id), types[n.tower.id]?.type ?? TowerType.lattice),
                  ),
                for (final t in topo.loose)
                  Positioned.fromRect(
                    rect: layout.rectOf(t.id),
                    child: _node(t, TopoRole.loose, types[t.id]?.type ?? TowerType.lattice),
                  ),
                ...pills,
              ]),
            ),
          ),
          if (topo.hasLinks) _legend(mixed: _anyFiber(topo)),
        ]),
      ),
    );
  }

  Widget _node(TopoTower t, TopoRole role, TowerType type) {
    final main = role == TopoRole.main;
    final silent = _silentIn(t.id);
    final (Color roleColor, Color? roleBg) = switch (role) {
      TopoRole.main => (AppColors.onBrand, AppColors.brand),
      TopoRole.relay => (AppTone.info.onSoft, AppTone.info.softBg),
      TopoRole.sub => (AppColors.textMid, AppColors.surfaceSunken),
      TopoRole.loose => (AppColors.textMid, null),
    };
    final sub = role == TopoRole.loose ? TopoText.devices(t.devices) : TopoText.role(role);
    return Semantics(
      button: true,
      label: 'برج ${t.name} — ${TopoText.role(role)} — ${TopoText.devices(t.devices)}'
          '${silent > 0 ? ' — $silent لا يردّ' : ''}',
      excludeSemantics: true,
      child: Material(
        key: ValueKey('topo-node-${t.id}'),
        color: main ? AppColors.brandSoftBg : AppColors.surface,
        borderRadius: BorderRadius.circular(R.md),
        child: InkWell(
          borderRadius: BorderRadius.circular(R.md),
          onTap: () {
            HapticFeedback.selectionClick();
            widget.onOpenTower(t.id);
          },
          child: Padding(
            padding: const EdgeInsets.fromLTRB(3, 4, 3, 4),
            child: Column(children: [
              SizedBox(
                width: 46,
                height: 42,
                child: Stack(clipBehavior: Clip.none, children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: MiniTowerPainter(
                        type: type,
                        strong: main ? AppColors.brand : AppColors.textBody,
                        soft: AppColors.textMid,
                        waves: main ? AppColors.brand : null,
                      ),
                    ),
                  ),
                  if (silent > 0)
                    PositionedDirectional(
                      top: 10,
                      end: -9,
                      child: Container(
                        constraints: const BoxConstraints(minWidth: 17),
                        height: 17,
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: AppColors.error,
                          borderRadius: BorderRadius.circular(R.pill),
                          border: Border.all(color: AppColors.surface, width: 1.5),
                        ),
                        child: Text('$silent', style: AppType.daysWordBold(color: AppColors.onBrand)),
                      ),
                    ),
                ]),
              ),
              const SizedBox(height: 2),
              Expanded(
                child: Center(
                  child: Text(
                    t.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: AppType.pillBold(color: AppColors.textHi),
                  ),
                ),
              ),
              Container(
                padding: EdgeInsets.symmetric(horizontal: roleBg == null ? 0 : 7, vertical: 1),
                decoration: roleBg == null
                    ? null
                    : BoxDecoration(color: roleBg, borderRadius: BorderRadius.circular(R.pill)),
                child: Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.microBold(color: roleColor)),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _edgePill(TopoEdge e, LinkFlow f, double maxWidth) {
    final AppTone tone = switch (f.state) {
      LinkState.ok => AppTone.success,
      LinkState.fair => AppTone.warning,
      LinkState.weak || LinkState.down => AppTone.danger,
      LinkState.unknown => AppTone.neutral,
    };
    final down = f.state == LinkState.down;
    // تعمل ولم يُعرف ما يعبرها بعد (أوّل قراءة، أو قراءةٌ بلا عدّادات كالـVPN) ⇒ «يعمل» لا «—»
    final text = down
        ? 'واقع'
        : (f.toSubBps != null ? TowerText.bps(f.toSubBps) : (f.state == LinkState.unknown ? '—' : 'يعمل'));
    return Semantics(
      button: true,
      label: '${e.fiber ? 'كيبل' : 'لنك'} ${_towerName(e.from)} إلى ${_towerName(e.to)} — '
          '${down ? 'واقع' : (f.toSubBps == null ? (f.state == LinkState.unknown ? 'لم يُقرأ' : 'يعمل') : 'ينزل $text')}',
      excludeSemantics: true,
      child: Material(
        key: ValueKey('topo-pill-${e.from}-${e.to}'),
        color: down ? AppColors.error : tone.softBg,
        borderRadius: BorderRadius.circular(R.pill),
        child: InkWell(
          borderRadius: BorderRadius.circular(R.pill),
          onTap: () => _openEdge(e),
          child: Container(
            height: 22,
            constraints: BoxConstraints(minWidth: 40, maxWidth: maxWidth),
            padding: const EdgeInsets.symmetric(horizontal: 7),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(R.pill),
              border: Border.all(color: AppColors.surface, width: 1.5),
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                if (!down && f.toSubBps != null) ...[
                  Icon(LucideIcons.arrowDown, size: 11, color: tone.onSoft),
                  const SizedBox(width: 2),
                ],
                Text(iso(text), style: AppType.pillBold(color: down ? AppColors.onBrand : tone.onSoft)),
                if (e.links.length > 1) ...[
                  const SizedBox(width: 3),
                  Text('×${e.links.length}',
                      textDirection: TextDirection.ltr,
                      style: AppType.daysWordBold(color: down ? AppColors.onBrand : tone.onSoft)),
                ],
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _legend({bool mixed = false}) {
    // نوعا الوصلة برسمهما — حين يوجد كيبل: خطٌّ متّصل للكيبل وشرطات للّنك
    Widget kind(String label, {required bool solid}) => Row(mainAxisSize: MainAxisSize.min, children: [
          if (solid)
            Container(width: 16, height: 2.4, decoration: BoxDecoration(color: AppColors.textMid, borderRadius: BorderRadius.circular(R.pill)))
          else
            Row(mainAxisSize: MainAxisSize.min, children: [
              for (var i = 0; i < 3; i++)
                Container(
                  width: 4,
                  height: 2.4,
                  margin: EdgeInsetsDirectional.only(end: i == 2 ? 0 : 2),
                  decoration: BoxDecoration(color: AppColors.textMid, borderRadius: BorderRadius.circular(R.pill)),
                ),
            ]),
          const SizedBox(width: 4),
          Text(label, style: AppType.micro(color: AppColors.textMid)),
        ]);
    Widget item(Color c, String label, {bool cross = false}) => Row(mainAxisSize: MainAxisSize.min, children: [
          cross
              ? Icon(LucideIcons.x, size: 11, color: c)
              : Container(width: 8, height: 8, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
          const SizedBox(width: 4),
          Text(label, style: AppType.micro(color: AppColors.textMid)),
        ]);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: 7),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: AppColors.divider))),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (mixed) ...[
          Wrap(alignment: WrapAlignment.center, spacing: 14, runSpacing: 4, children: [
            kind('كيبل ضوئي', solid: true),
            kind('لنك لاسلكي', solid: false),
          ]),
          const SizedBox(height: 5),
        ],
        Wrap(alignment: WrapAlignment.center, spacing: 12, runSpacing: 4, children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(LucideIcons.arrowDown, size: 11, color: AppColors.textMid),
            const SizedBox(width: 3),
            Text('ينزل للفرعي', style: AppType.micro(color: AppColors.textMid)),
          ]),
          item(AppColors.success, 'ممتاز'),
          item(AppColors.warningFill, 'متوسّط'),
          item(AppColors.error, 'ضعيف'),
          item(AppColors.error, 'واقع', cross: true),
        ]),
      ]),
    );
  }

  // ── القوائم ─────────────────────────────────────────────────────────────────────────────

  Widget _sectionTitle(String title, {Widget? trailing}) => Padding(
        padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.lg, Sp.lg, 6),
        child: Row(children: [
          Expanded(child: Text(title, style: AppType.bodyStrong(color: AppColors.textHi))),
          if (trailing != null) trailing,
        ]),
      );

  Widget _addButton() => Semantics(
        button: true,
        child: Material(
          color: AppColors.brand,
          borderRadius: BorderRadius.circular(R.sm),
          child: InkWell(
            borderRadius: BorderRadius.circular(R.sm),
            onTap: _openEditor,
            child: Container(
              height: 36,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(_canEdit ? LucideIcons.plus : LucideIcons.lock, size: 15, color: AppColors.onBrand),
                const SizedBox(width: 5),
                Text('ربط برجين', style: AppType.bodyBold(color: AppColors.onBrand)),
              ]),
            ),
          ),
        ),
      );

  Widget _linksSection(TowerTopology topo, Map<int, LinkFlow> flows) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionTitle('${_anyFiber(topo) ? 'الوصلات' : 'اللنكات'} · ${_links.length - topo.broken.length}', trailing: _addButton()),
          for (final e in topo.edges)
            for (final l in e.links) _linkRow(l, flows[l.id]!, onTap: () => _openLink(l)),
        ],
      );

  Widget _linkRow(TowerLink l, LinkFlow f, {required VoidCallback onTap, bool inSheet = false}) {
    final a = _byId[l.aDeviceId];
    final b = _byId[l.bDeviceId];
    final color = linkStateColor(f.state);
    // الكيبل يُسمّى باسمه في سطره — واللنك كما كان
    final second = l.isFiber ? 'كيبل · ${_noteOf(l, f)}' : _noteOf(l, f);
    return Padding(
      padding: EdgeInsets.fromLTRB(inSheet ? 0 : Sp.lg, 0, inSheet ? 0 : Sp.lg, 6),
      child: Semantics(
        button: true,
        child: Material(
          key: ValueKey('topo-link-${l.id}'),
          color: inSheet ? AppColors.bg : AppColors.surface,
          borderRadius: BorderRadius.circular(R.md),
          child: InkWell(
            borderRadius: BorderRadius.circular(R.md),
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(R.md),
                border: inSheet ? null : Border.all(color: AppColors.border),
              ),
              child: Row(children: [
                Container(width: 4, height: 38, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(R.pill))),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(
                      '${iso(_towerName(_towerOf[l.aDeviceId] ?? 0))} ← ${iso(_towerName(_towerOf[l.bDeviceId] ?? 0))}',
                      style: AppType.bodyBold(color: AppColors.textHi),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      '${iso(a?.name ?? 'جهاز محذوف')} ← ${iso(b?.name ?? 'جهاز محذوف')}',
                      style: AppType.muted(color: AppColors.textMid),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(second,
                        style: AppType.muted(color: f.state == LinkState.down ? AppColors.error : AppColors.textMid),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ]),
                ),
                const SizedBox(width: 8),
                Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(LucideIcons.arrowDown, size: 12, color: AppColors.textMid),
                    const SizedBox(width: 2),
                    Text(iso(TowerText.bps(f.toSubBps)), style: AppType.bodyBold(color: AppColors.textHi)),
                  ]),
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(LucideIcons.arrowUp, size: 12, color: AppColors.textLow),
                    const SizedBox(width: 2),
                    Text(iso(TowerText.bps(f.toMainBps)), style: AppType.muted(color: AppColors.textMid)),
                  ]),
                ]),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  /// سطر حال الوصلة: كلمتها وأرقامها، أو لمَ هي واقعة، أو لمَ لم تُقرأ.
  String _noteOf(TowerLink l, LinkFlow f) {
    if (f.state == LinkState.down) {
      // السويج يردّ ويقول إنّ المنفذ طافٍ — الكيبل نفسه أو وحدة الـSFP أو الطرف الثاني مطفأ
      if (f.mainPortDown || f.subPortDown) {
        return f.mainPortDown && f.subPortDown
            ? 'المنفذان طافيان — الكيبل أو الـSFP'
            : (f.mainPortDown ? 'منفذ الرئيسي طافي — الكيبل أو الـSFP' : 'منفذ الفرعي طافي — الكيبل أو الـSFP');
      }
      return f.mainDown && f.subDown ? 'الطرفان لا يردّان' : (f.mainDown ? 'طرف الرئيسي لا يردّ' : 'طرف الفرعي لا يردّ');
    }
    if (f.state == LinkState.unknown) {
      if (_probe.offNetwork) return 'خارج شبكتك';
      if (f.portIssue == FiberPortIssue.unset) return 'اختر المنفذ ليظهر ما يعبر الكيبل';
      if (f.portIssue == FiberPortIssue.missing) return 'المنفذ «${f.missingPort}» غير موجود بالجهاز — اختره من جديد';
      return _unreadWhy(l);
    }
    final facts = TopoText.facts(f);
    return facts.isEmpty ? TopoText.stateOf(f) : '${TopoText.stateOf(f)} · ${isoJoin(facts, ' · ')}';
  }

  /// لمَ لم يُقرأ اللنك — بسبب أحد طرفيه إن عُرف.
  String _unreadWhy(TowerLink l) {
    for (final id in [l.bDeviceId, l.aDeviceId]) {
      if (_probe.needsSettings(id)) return 'يردّ وتعذّرت قراءته — تحقّق من إعدادات «${_byId[id]?.name ?? 'الجهاز'}»';
      final why = _probe.skipReasonOf(id);
      if (why != null) return '«${_byId[id]?.name ?? 'الجهاز'}»: $why';
    }
    return 'يُقرأ…';
  }

  Widget _suggestSection(List<LinkSuggestion> list) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionTitle('لنكات مقترحة · ${list.length}'),
          Padding(
            padding: const EdgeInsets.fromLTRB(Sp.lg, 0, Sp.lg, 6),
            child: Text('أجهزةٌ ترى بعضها على برجين مختلفين — اربطها بنقرة، وتقدر تقلب الاتّجاه بعدها.',
                style: AppType.muted(color: AppColors.textMid)),
          ),
          for (final s in list.take(6))
            Padding(
              padding: const EdgeInsets.fromLTRB(Sp.lg, 0, Sp.lg, 6),
              child: Container(
                key: ValueKey('topo-suggest-${s.a.id}-${s.b.id}'),
                padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(R.md),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(children: [
                  Icon(LucideIcons.sparkles, size: 16, color: AppColors.brand),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${iso(s.a.name)} ← ${iso(s.b.name)}',
                          style: AppType.bodyBold(color: AppColors.textHi), maxLines: 1, overflow: TextOverflow.ellipsis),
                      Text(
                        '${iso(_towerName(s.a.regionId ?? 0))} ← ${iso(_towerName(s.b.regionId ?? 0))} · ${s.why}',
                        style: AppType.muted(color: AppColors.textMid),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ]),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: _busy.contains(-s.b.id) ? null : () => _linkSuggested(s),
                    style: TextButton.styleFrom(
                      minimumSize: const Size(56, 40),
                      foregroundColor: AppColors.brand,
                      backgroundColor: AppColors.brandSoftBg,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(R.sm)),
                    ),
                    child: Text('اربط', style: AppType.bodyBold(color: AppColors.brand)),
                  ),
                ]),
              ),
            ),
        ],
      );

  Widget _brokenSection(List<TowerLink> broken) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionTitle('لنكات لا تُرسم · ${broken.length}'),
          Padding(
            padding: const EdgeInsets.fromLTRB(Sp.lg, 0, Sp.lg, 6),
            child: Text('طرفاها صارا في البرج نفسه (أو حُذف أحدهما) — انقل أحد الطرفين لبرجٍ آخر أو احذف الربط.',
                style: AppType.muted(color: AppColors.textMid)),
          ),
          for (final l in broken)
            Padding(
              padding: const EdgeInsets.fromLTRB(Sp.lg, 0, Sp.lg, 6),
              child: Container(
                padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(R.md),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(children: [
                  Icon(LucideIcons.unlink, size: 16, color: AppColors.textMid),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '${iso(_byId[l.aDeviceId]?.name ?? 'جهاز محذوف')} ← ${iso(_byId[l.bDeviceId]?.name ?? 'جهاز محذوف')}',
                      style: AppType.body(color: AppColors.textHi),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    tooltip: 'احذف الربط',
                    icon: Icon(_canEdit ? LucideIcons.trash2 : LucideIcons.lock, size: 18, color: AppColors.error),
                    onPressed: _busy.contains(l.id) ? null : () => _delete(l),
                  ),
                ]),
              ),
            ),
        ],
      );

  /// أجهزةٌ لم تُسند لبرج — تُفتح («بلا منطقة») ومنها تُسند.
  Widget _orphansLine() => Padding(
        padding: const EdgeInsets.fromLTRB(Sp.lg, 6, Sp.lg, 0),
        child: Semantics(
          button: true,
          child: InkWell(
            key: const ValueKey('topo-orphans'),
            borderRadius: BorderRadius.circular(R.sm),
            onTap: () => widget.onOpenTower(0),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              child: Row(children: [
                Icon(LucideIcons.mapPinOff, size: 14, color: AppColors.textMid),
                const SizedBox(width: 6),
                Expanded(
                  child: Text('${TopoText.devices(_orphans)} بلا منطقة — أسندها لأبراجها من «أجهزة البرج».',
                      style: AppType.muted(color: AppColors.textMid)),
                ),
                Icon(LucideIcons.chevronLeft, size: 16, color: AppColors.textLow),
              ]),
            ),
          ),
        ),
      );

  Widget _linkHint() => Padding(
        padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, 0),
        child: Container(
          padding: const EdgeInsets.all(Sp.md),
          decoration: BoxDecoration(color: AppColors.brandSoftBg, borderRadius: BorderRadius.circular(R.md)),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('اربط أبراجك', style: AppType.bodyBold(color: AppColors.textHi)),
                const SizedBox(height: 2),
                Text(
                    _fiberReady
                        ? 'لنك لاسلكي (ماستر وسليف) أو كيبل ضوئي بين سويجين — يظهر مسار الترافيك من الرئيسي للفرعيّات.'
                        : 'اختر لنك البرج الرئيسي وطرفه في البرج الفرعي — يظهر مسار الترافيك من الرئيسي للفرعيّات.',
                    style: AppType.muted(color: AppColors.textMid)),
              ]),
            ),
            const SizedBox(width: Sp.sm),
            _addButton(),
          ]),
        ),
      );

  Widget _emptyTowers(List<TopoTower> towers) => Padding(
        padding: const EdgeInsets.fromLTRB(Sp.xxl, Sp.huge, Sp.xxl, 0),
        child: Column(children: [
          SizedBox(
            width: 64,
            height: 60,
            child: CustomPaint(
              painter: MiniTowerPainter(
                type: TowerType.lattice,
                strong: AppColors.textMid,
                soft: AppColors.textLow,
                waves: AppColors.brand,
              ),
            ),
          ),
          const SizedBox(height: Sp.md),
          Text(towers.isEmpty ? 'أجهزتك بلا أبراج بعد' : 'برجٌ واحد حتى الآن',
              style: AppType.cardTitle(color: AppColors.textHi), textAlign: TextAlign.center),
          const SizedBox(height: Sp.xs),
          Text(
            'قسّم أجهزتك على أبراج (كلّ برجٍ منطقة) ثمّ اربطها — لنكات لاسلكيّة أو كيابل ضوئيّة — يظهر هنا الرئيسي والفرعيّات وسير الترافيك بينها.',
            textAlign: TextAlign.center,
            style: AppType.body(color: AppColors.textMid),
          ),
          if (widget.onNewTower != null) ...[
            const SizedBox(height: Sp.lg),
            FilledButton.icon(
              onPressed: widget.onNewTower,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.brand,
                foregroundColor: AppColors.onBrand,
                minimumSize: const Size(160, 46),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(R.md)),
              ),
              icon: Icon(_canEdit ? LucideIcons.plus : LucideIcons.lock, size: 18),
              label: Text('برج جديد', style: AppType.buttonBold(color: AppColors.onBrand)),
            ),
          ],
        ]),
      );
}

/// تفاصيل وصلةٍ واحدة: ما ينزل للفرعيّ وما يصعد منه، وأرقامها بنوعها (اللنك: الإشارة والـCCQ؛ الكيبل: سرعة المنفذ وضوء
/// الـSFP ومنفذه عند كلّ طرف — يُغيَّر من هنا)، طرفاها، وقلب الاتّجاه والحذف وتحويل النوع.
class _LinkSheet extends StatelessWidget {
  const _LinkSheet({
    required this.link,
    required this.a,
    required this.b,
    required this.aTower,
    required this.bTower,
    required this.flow,
    required this.note,
    required this.probe,
    required this.canEdit,
    required this.fiberReady,
    required this.busy,
    required this.onOpenDevice,
    required this.onPort,
    required this.onKind,
    required this.onFlip,
    required this.onDelete,
  });

  final TowerLink link;
  final NetworkDevice? a;
  final NetworkDevice? b;
  final String aTower;
  final String bTower;
  final LinkFlow flow;

  /// سطر الحال كما في القائمة (كلمتها وأرقامها، أو لمَ هي واقعة/لم تُقرأ).
  final String note;
  final TowerLinkProbe probe;
  final bool canEdit;
  final bool fiberReady;
  final bool busy;
  final ValueChanged<NetworkDevice> onOpenDevice;

  /// «غيّر المنفذ» عند طرف الرئيسيّ (true) أو الفرعيّ.
  final ValueChanged<bool> onPort;
  final ValueChanged<TowerLinkKind> onKind;
  final VoidCallback onFlip;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final fiber = link.isFiber;
    final AppTone tone = switch (flow.state) {
      LinkState.ok => AppTone.success,
      LinkState.fair => AppTone.warning,
      LinkState.weak || LinkState.down => AppTone.danger,
      LinkState.unknown => AppTone.neutral,
    };
    Widget cell(String label, String value, {IconData? icon}) => Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 9),
            decoration: BoxDecoration(color: AppColors.bg, borderRadius: BorderRadius.circular(R.sm)),
            child: Column(children: [
              Row(mainAxisSize: MainAxisSize.min, children: [
                if (icon != null) ...[
                  Icon(icon, size: 11, color: AppColors.textMid),
                  const SizedBox(width: 3),
                ],
                Flexible(
                    child: Text(label,
                        style: AppType.micro(color: AppColors.textMid), maxLines: 1, overflow: TextOverflow.ellipsis)),
              ]),
              const SizedBox(height: 2),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(iso(value), style: AppType.rowValue(color: AppColors.textHi), maxLines: 1),
              ),
            ]),
          ),
        );

    Widget end(String caption, NetworkDevice? d, String tower, bool down, {required bool main}) {
      final note = d == null
          ? null
          : (down
              ? 'لا يردّ'
              : (probe.needsSettings(d.id) ? 'يردّ وتعذّرت قراءته — تحقّق من إعداداته' : probe.skipReasonOf(d.id)));
      final portName = main ? link.aPort : link.bPort;
      final reading = d == null ? null : probe.readingOf(d.id);
      final port = reading?.port(portName);
      // الجهاز قُرئ بمنافذه وهذا ليس بينها (غُيّر اسمه أو كُتب خطأً) — يُقال عند طرفه، ولو قُرئ الكيبل من الطرف الآخر
      final gone = portName != null && port == null && reading != null && reading.wiredPorts.isNotEmpty;
      final portFacts = [
        if (gone) 'غير موجود بالجهاز',
        if (port != null && !port.up) 'طافي',
        if (port != null && port.up && (port.linkSpeed ?? '').isNotEmpty) TopoText.speed(port.linkSpeed),
        if (port?.sfpRx != null) TopoText.lightFact(port!.sfpRx),
      ];
      return Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Material(
          color: AppColors.bg,
          borderRadius: BorderRadius.circular(R.md),
          clipBehavior: Clip.antiAlias,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            InkWell(
              onTap: d == null ? null : () => onOpenDevice(d),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                child: Row(children: [
                  Container(
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: AppColors.brandSoftBg, borderRadius: BorderRadius.circular(R.chip)),
                    child: d == null
                        ? Icon(LucideIcons.circleAlert, size: 18, color: AppColors.textMid)
                        : DeviceGlyph(shape: TowerShapes.detect(d).shape, size: 24, color: AppColors.brand),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(caption, style: AppType.micro(color: AppColors.textMid)),
                      Text(d?.name ?? 'جهاز محذوف',
                          style: AppType.bodyBold(color: AppColors.textHi), maxLines: 1, overflow: TextOverflow.ellipsis),
                      Text(d == null ? '—' : isoJoin([tower, d.ip], ' · '),
                          style: AppType.muted(color: AppColors.textMid), maxLines: 1, overflow: TextOverflow.ellipsis),
                      if (note != null)
                        Text(note, style: AppType.muted(color: down ? AppColors.error : AppTone.warning.onSoft), maxLines: 2),
                    ]),
                  ),
                  if (d != null) Icon(LucideIcons.chevronLeft, size: 18, color: AppColors.textLow),
                ]),
              ),
            ),
            // منفذ الكيبل عند هذا الطرف — يُغيَّر من هنا
            if (fiber && d != null) ...[
              Container(height: 1, color: AppColors.divider),
              Semantics(
                button: true,
                child: InkWell(
                  key: ValueKey('link-sheet-port-${main ? 'main' : 'sub'}'),
                  onTap: () => onPort(main),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    child: Row(children: [
                      Icon(LucideIcons.cable, size: 15, color: portName == null ? AppColors.brand : AppColors.textMid),
                      const SizedBox(width: 8),
                      Text('المنفذ', style: AppType.muted(color: AppColors.textMid)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          portName == null ? 'اختر المنفذ' : isoJoin([portName, ...portFacts], ' · '),
                          style: AppType.bodyBold(
                              color: portName == null
                                  ? AppColors.brand
                                  : (port != null && !port.up
                                      ? AppColors.error
                                      : (gone ? AppTone.warning.onSoft : AppColors.textHi))),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Icon(canEdit ? LucideIcons.pencil : LucideIcons.lock, size: 14, color: AppColors.textLow),
                    ]),
                  ),
                ),
              ),
            ],
          ]),
        ),
      );
    }

    return DesignSheet(
      header: SheetHeaderBar(
        icon: fiber ? LucideIcons.cable : LucideIcons.link,
        title: '$aTower ← $bTower',
        subtitle: fiber ? 'كيبل ضوئي · ${TopoText.stateOf(flow)}' : TopoText.stateOf(flow),
        tint: tone == AppTone.neutral ? null : tone.onSoft,
        tintBg: tone == AppTone.neutral ? null : tone.softBg,
        onClose: () => Navigator.of(context).pop(),
      ),
      body: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          cell('ينزل للفرعي', TowerText.bps(flow.toSubBps), icon: LucideIcons.arrowDown),
          const SizedBox(width: 6),
          cell('يصعد للرئيسي', TowerText.bps(flow.toMainBps), icon: LucideIcons.arrowUp),
          const SizedBox(width: 6),
          if (fiber) ...[
            cell('سرعة المنفذ', TopoText.speed(flow.linkSpeed)),
            const SizedBox(width: 6),
            cell('ضوء الـSFP', TopoText.light(flow.light)),
          ] else ...[
            cell('الإشارة', flow.signal == null ? '—' : '${flow.signal} dBm'),
            const SizedBox(width: 6),
            cell('CCQ', flow.ccq == null ? '—' : '${flow.ccq}٪'),
          ],
        ]),
        // الواقع وما لم يُقرأ: السبب بكلماته (منفذٌ طافٍ، طرفٌ لا يردّ، بلا منفذ…)
        if (flow.state == LinkState.down || flow.state == LinkState.unknown)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(note, style: AppType.body(color: flow.state == LinkState.down ? AppColors.error : AppColors.textMid)),
          ),
        const SizedBox(height: 4),
        end(fiber ? 'طرف البرج الرئيسي' : 'طرف البرج الرئيسي (الماستر)', a, aTower, flow.mainDown, main: true),
        end(fiber ? 'طرف البرج الفرعي' : 'طرف البرج الفرعي (السليف)', b, bTower, flow.subDown, main: false),
        // سويجان رُبطا «لنكاً» قبل أن يوجد الكيبل (أو العكس) — النوع يُصحَّح بلا حذفٍ وإعادة
        if (fiberReady)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              key: const ValueKey('link-sheet-kind'),
              onPressed: busy ? null : () => onKind(fiber ? TowerLinkKind.radio : TowerLinkKind.fiber),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.brand,
                minimumSize: const Size(44, 40),
                padding: const EdgeInsets.symmetric(horizontal: 4),
              ),
              icon: Icon(canEdit ? (fiber ? LucideIcons.radioTower : LucideIcons.cable) : LucideIcons.lock, size: 15),
              label: Text(fiber ? 'حوّله إلى لنك لاسلكي' : 'حوّله إلى كيبل ضوئي',
                  style: AppType.bodyStrong(color: AppColors.brand)),
            ),
          ),
      ]),
      footer: SheetFooterBar(
        label: 'اقلب الاتّجاه',
        icon: canEdit ? LucideIcons.arrowUpDown : LucideIcons.lock,
        busy: busy,
        onPressed: onFlip,
        leading: SheetSecondaryButton(label: 'احذف الربط', onTap: onDelete),
      ),
    );
  }
}
