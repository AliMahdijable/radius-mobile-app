import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../api/network_devices_api.dart';
import '../../../api/tower_api.dart';
import '../../../core/util/bidi.dart';
import '../../../core/widgets/permission_locked.dart';
import '../../../models/network_device.dart';
import '../../../models/tower_layout.dart';
import '../../../services/deep_probe_scheduler.dart';
import '../../../services/device_events.dart';
import '../../../services/device_stats_cache.dart';
import '../../../services/permissions_service.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';
import '../../desktop/desk_widgets.dart';
import '../device_vitals.dart';
import '../network_device_details_screen.dart';
import '../widgets/_grade.dart';
import 'tower_builder_screen.dart';
import 'tower_logic.dart';
import 'tower_paint.dart';
import 'tower_place_screen.dart';
import 'tower_reading.dart';

enum _Mode { side, top, list }

enum _Sort { clients, quality, traffic, signal }

/// عرض البرج — المالك ٢٧ أكتوبر: «نرسم البرج… والوكيل يخلي سكاتره واجهزته وتطلع قراءات: شكد يعبر اللنك،
/// ترفك السكاتر، شكد مشتركين عليه، ومعدل CCQ والإشارات».
///
/// برجٌ لكلّ منطقة أجهزة. القراءات من جلسات قسم الأجهزة نفسها ([DeviceVitals.fetch] + [DeviceStatsCache])،
/// فلا جلسة ثانية ولا انتظار لما قُرئ قبل دقيقتين. المكان من الخادم ([TowerApi])، وما لم يُحفظ يرتّبه
/// [TowerArrange] في الذاكرة — نفس الرسم على كلّ هاتف، ولا يُكتب شيءٌ دون طلب.
class TowerScreen extends StatefulWidget {
  const TowerScreen({
    super.key,
    required this.regionId,
    required this.regionName,
    required this.devices,
  });

  /// المنطقة = البرج، و`0` لأجهزةٍ بلا منطقة.
  final int regionId;
  final String regionName;
  final List<NetworkDevice> devices;

  @override
  State<TowerScreen> createState() => _TowerScreenState();
}

class _TowerScreenState extends State<TowerScreen> with TickerProviderStateMixin {
  static const _refreshEvery = Duration(seconds: 20);
  static const _startView = 100.0;

  late TowerSettings _settings = TowerSettings(regionId: widget.regionId);
  Map<int, TowerPlacement> _saved = const {};
  final Map<int, TowerReading> _readings = {};
  final Set<int> _failed = {};
  final Set<int> _inFlight = {};
  Map<int, ArrangedDevice> _arranged = const {};
  List<TowerAlert> _alerts = const [];

  /// أجهزة البرج — لقطةٌ حيّة تُعاد جلبها عند أيّ تغيير (تعديل اسم/منطقة/حذف)،
  /// لا لقطةٌ مجمَّدة من لحظة الفتح. (المالك ٢٧ أكتوبر — «عرض البرج ما يتحدّث».)
  late List<NetworkDevice> _devices = widget.devices;

  _Mode _mode = _Mode.side;
  _Sort _sort = _Sort.clients;
  double _view = _startView;
  int? _sel;
  bool _loadedLayout = false;

  late final AnimationController _flow =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
  late final AnimationController _spin =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 420));
  Animation<double>? _spinAnim;
  Timer? _timer;
  Timer? _flush;

  bool get _canEdit => Perms.has('devices.manage');

  @override
  void initState() {
    super.initState();
    // أجهزةُ البرج تتغيّر في مكانٍ آخر (تعديل اسم/منطقة/حذف) — أعِد الجلب فوراً.
    DeviceEvents.changes.addListener(_onDevicesChanged);
    _seedFromCache();
    _rearrange();
    _loadLayout();
    _probeAll(first: true);
    _timer = Timer.periodic(_refreshEvery, (_) => _probeAll());
    _spin.addListener(() {
      final a = _spinAnim;
      if (a != null) setState(() => _view = a.value);
    });
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

  /// مالكٌ لكلّ جهاز: المُجدوِل يُبقي مهمّةً منتظرةً واحدة لكلّ مالك. بمالكٍ واحدٍ للشاشة كانت مهامّ الأجهزة
  /// المنتظرة (بعد أوّل ستّة تبدأ فوراً) تُلغي بعضها فلا يُقرأ منها إلّا آخرها.
  final Map<int, Object> _owners = {};
  Object _ownerOf(int id) => _owners[id] ??= Object();

  @override
  void dispose() {
    DeviceEvents.changes.removeListener(_onDevicesChanged);
    for (final o in _owners.values) {
      DeepProbeScheduler.instance.cancel(o);
    }
    _timer?.cancel();
    _flush?.cancel();
    _flow.dispose();
    _spin.dispose();
    super.dispose();
  }

  // ── البيانات ────────────────────────────────────────────────────────────────────────────

  void _seedFromCache() {
    for (final d in _devices) {
      final v = DeviceStatsCache.instance.vitalsOf(d.id, DeviceStatsCache.seedTtl);
      final detail = v?.detail;
      if (detail is! DeviceDetail) continue;
      final raw = DeviceStatsCache.instance.seedFor<Object>(d.id);
      _readings[d.id] = TowerReading.fromProbe(
        ProbeResult(vitals: const [], detail: detail, counters: const {}, raw: raw),
        at: v!.at,
      );
    }
  }

  Future<void> _loadLayout() async {
    final r = await TowerApi.load();
    if (!mounted) return;
    setState(() {
      _loadedLayout = r.ok;
      if (r.ok) {
        _settings = r.layouts.towers[widget.regionId] ?? TowerSettings(regionId: widget.regionId);
        final ids = {for (final d in _devices) d.id};
        _saved = {
          for (final e in r.layouts.placements.entries)
            if (ids.contains(e.key)) e.key: e.value,
        };
      }
      _rearrange();
    });
  }

  void _rearrange() {
    _arranged = TowerArrange.arrange(_devices, readings: _readings, saved: _saved);
    _alerts = TowerAttention.compute(_arranged, _readings);
    if (_sel == null || !_arranged.containsKey(_sel)) {
      final link = _arranged.values.where((a) => a.role == TowerRole.link);
      _sel = link.isNotEmpty ? link.first.device.id : (_arranged.isEmpty ? null : _arranged.keys.first);
    }
  }

  /// تغيّرت الأجهزة في مكانٍ آخر — نافذة البرج ترسمها فوراً.
  void _onDevicesChanged() {
    if (mounted) _reloadTowerDevices();
  }

  /// يُعيد جلب أجهزة هذا البرج (حسب منطقته) ويعيد الترتيب فوراً — فيظهر الاسم
  /// الجديد، وتدخل الأجهزة المنقولة للمنطقة، وتختفي المنقولة منها أو المحذوفة.
  Future<void> _reloadTowerDevices() async {
    try {
      final all = await NetworkDevicesApi.list();
      if (!mounted) return;
      final mine = [
        for (final d in all)
          if (widget.regionId == 0 ? d.regionId == null : d.regionId == widget.regionId) d,
      ];
      setState(() {
        _devices = mine;
        _rearrange();
      });
      _probeAll(); // الأجهزة الجديدة تُقرأ.
    } catch (_) {
      // فشل الجلب لا يُسقط اللقطة الحاليّة.
    }
  }

  void _probeAll({bool first = false}) {
    for (final d in _devices) {
      if (_inFlight.contains(d.id)) continue;
      if (DeviceVitals.skipReason(d) != null) continue;
      _inFlight.add(d.id);
      DeepProbeScheduler.instance.submit(_ownerOf(d.id), first: first && !_readings.containsKey(d.id), () async {
        try {
          final prev = DeviceStatsCache.instance.sampleOf(d.id);
          final r = await DeviceVitals.fetch(
            d,
            prev: prev == null ? null : CounterSample(prev.counters, prev.at),
            detailed: true,
          );
          // المخزن عالميّ: يُكتب حتى لو غادر المستخدم — جلسةٌ دُفع ثمنها لا تُرمى.
          if (r.raw != null) DeviceStatsCache.instance.putRaw(d.id, r.raw!, detailed: true);
          DeviceStatsCache.instance.putVitals(d.id, r.vitals, r.detail);
          DeviceStatsCache.instance.putSample(d.id, r.counters);
          if (!mounted) return;
          _readings[d.id] = TowerReading.fromProbe(r);
          _failed.remove(d.id);
          _scheduleFlush();
        } catch (_) {
          if (!mounted) return;
          _failed.add(d.id);
          _scheduleFlush();
        } finally {
          _inFlight.remove(d.id);
        }
      });
    }
  }

  // دفعةٌ كلّ ٤٠٠ms بدل إعادة بناءٍ لكلّ جهاز (نفس علاج الجدار).
  void _scheduleFlush() {
    if (_flush?.isActive ?? false) return;
    _flush = Timer(const Duration(milliseconds: 400), () {
      if (!mounted) return;
      setState(_rearrange);
    });
  }

  // ── التنقّل ────────────────────────────────────────────────────────────────────────────

  Future<void> _openBuilder() async {
    final res = await Navigator.of(context).push<TowerBuilderResult>(MaterialPageRoute(
      builder: (_) => TowerBuilderScreen(
        regionId: widget.regionId,
        regionName: widget.regionName,
        devices: _devices,
        readings: Map.unmodifiable(_readings),
        saved: _saved,
        settings: _settings,
        canEdit: _canEdit,
        serverReady: _loadedLayout,
      ),
    ));
    if (res == null || !mounted) return;
    setState(() {
      _settings = res.settings;
      _saved = res.saved;
      _rearrange();
    });
    if (res.openTour) _openPlace(null);
  }

  Future<void> _openPlace(int? deviceId) async {
    if (!_canEdit) {
      showNoPermission(context, action: true);
      return;
    }
    final res = await Navigator.of(context).push<Map<int, TowerPlacement>>(MaterialPageRoute(
      builder: (_) => TowerPlaceScreen(
        devices: _devices,
        arranged: _arranged,
        startDeviceId: deviceId,
        settings: _settings,
        serverReady: _loadedLayout,
      ),
    ));
    if (res == null || !mounted) return;
    setState(() {
      _saved = {..._saved, ...res};
      _rearrange();
    });
  }

  void _openDevice(NetworkDevice d) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => NetworkDeviceDetailsScreen(device: d)));
  }

  void _select(int id, {_Mode? mode}) {
    HapticFeedback.selectionClick();
    setState(() {
      _sel = id;
      if (mode != null) _mode = mode;
    });
  }

  void _rotateBy(double deg) {
    final from = _view;
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduce) {
      setState(() => _view = (from + deg) % 360);
      return;
    }
    _spinAnim = Tween<double>(begin: from, end: from + deg)
        .animate(CurvedAnimation(parent: _spin, curve: Curves.easeOutCubic));
    _spin.forward(from: 0);
  }

  // ── البناء ─────────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final online = _devices.where((d) => d.lastStatus != 'offline' && !_failed.contains(d.id)).length;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: deskPageBar(
        context,
        mobile: AppBar(
          title: Text(widget.regionName),
          backgroundColor: AppColors.surface,
          foregroundColor: AppColors.textHi,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(LucideIcons.arrowRight, size: 20),
            onPressed: () => Navigator.pop(context),
          ),
          actions: [
            IconButton(
              tooltip: 'بناء البرج وترتيب الأجهزة',
              icon: const Icon(LucideIcons.slidersHorizontal, size: 20),
              onPressed: _openBuilder,
            ),
            const SizedBox(width: 4),
          ],
        ),
      ),
      body: _arranged.isEmpty
          ? _empty()
          : ListView(
              padding: EdgeInsets.only(bottom: Inset.route(context)),
              children: [
                _liveLine(online),
                _kpis(online),
                if (_alerts.isNotEmpty) _attention(),
                _modeSwitch(),
                const SizedBox(height: Sp.sm),
                _stage(),
                if (_sel != null && _arranged[_sel] != null) _deviceCard(_arranged[_sel]!),
                if (_cabinet.isNotEmpty) _cabinetSection(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, 0),
                  child: Text(
                    'القراءات من أجهزتك مباشرةً وتتحدّث كلّ ${_refreshEvery.inSeconds} ثانية.',
                    textAlign: TextAlign.center,
                    style: AppType.muted(color: AppColors.textMid),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _empty() => Center(
        child: Padding(
          padding: const EdgeInsets.all(Sp.xxl),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(LucideIcons.radioTower, size: 40, color: AppColors.textLow),
            const SizedBox(height: Sp.md),
            Text('لا أجهزة في هذه المنطقة بعد', style: AppType.cardTitle(color: AppColors.textHi)),
            const SizedBox(height: Sp.xs),
            Text('أضف أجهزتك من قسم الأجهزة وتظهر على البرج تلقائيّاً.',
                textAlign: TextAlign.center, style: AppType.body(color: AppColors.textMid)),
          ]),
        ),
      );

  Widget _liveLine(int online) {
    final total = _devices.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, Sp.sm),
      child: Row(children: [
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
        Expanded(
          child: Text('$total جهازاً · $online يردّ',
              style: AppType.body(color: AppColors.textMid), overflow: TextOverflow.ellipsis),
        ),
      ]),
    );
  }

  Widget _kpis(int online) {
    final links = _arranged.values.where((a) => a.role == TowerRole.link).toList();
    final linkDown = links.fold<int?>(null, (s, a) {
      final v = _readings[a.device.id]?.downBps;
      return v == null ? s : (s ?? 0) + v;
    });
    final subs = _arranged.values
        .where((a) => a.role == TowerRole.sector || a.role == TowerRole.ap)
        .fold<int?>(null, (s, a) {
      final v = _readings[a.device.id]?.clients;
      return v == null ? s : (s ?? 0) + v;
    });
    final servers = _arranged.values.where((a) => a.role == TowerRole.sector || a.role == TowerRole.ap).length;
    Widget tile(String label, String value, String foot) => Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(R.md),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: AppType.muted(color: AppColors.textMid)),
              const SizedBox(height: 2),
              Text(iso(value), style: AppType.statValue(color: AppColors.textHi), maxLines: 1, overflow: TextOverflow.ellipsis),
              Text(foot, style: AppType.micro(color: AppColors.textMid), maxLines: 1, overflow: TextOverflow.ellipsis),
            ]),
          ),
        );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Sp.lg),
      child: Row(children: [
        tile('يعبر اللنك', TowerText.bps(linkDown), links.isEmpty ? 'لا لنك' : '${links.length} لنك'),
        const SizedBox(width: Sp.sm),
        tile('المشتركون', subs == null ? '—' : '$subs', 'على $servers جهاز'),
        const SizedBox(width: Sp.sm),
        tile('الأجهزة', '$online/${_devices.length}', online == _devices.length ? 'كلّها تردّ' : 'بعضها لا يردّ'),
      ]),
    );
  }

  Widget _attention() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('يحتاج انتباهاً · ${_alerts.length}', style: AppType.bodyStrong(color: AppColors.textHi)),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final a in _alerts.take(8))
            Semantics(
              button: true,
              selected: _sel == a.deviceId,
              child: InkWell(
                onTap: () => _select(a.deviceId, mode: a.otherId != null ? _Mode.top : _Mode.side),
                borderRadius: BorderRadius.circular(R.sm),
                child: Container(
                  constraints: const BoxConstraints(minHeight: 40),
                  padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                  decoration: BoxDecoration(
                    color: _sel == a.deviceId ? AppColors.brandSoftBg : AppColors.surface,
                    borderRadius: BorderRadius.circular(R.sm),
                    border: Border.all(color: _sel == a.deviceId ? AppColors.brand : AppColors.border),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Container(width: 8, height: 8, decoration: BoxDecoration(color: a.tone.fill, shape: BoxShape.circle)),
                    const SizedBox(width: 7),
                    Flexible(
                        child: Text(iso(a.chip),
                            style: AppType.body(color: AppColors.textHi), maxLines: 2, overflow: TextOverflow.ellipsis)),
                  ]),
                ),
              ),
            ),
        ]),
      ]),
    );
  }

  Widget _modeSwitch() {
    Widget seg(_Mode m, String label) {
      final on = _mode == m;
      return Expanded(
        child: Semantics(
          button: true,
          selected: on,
          child: InkWell(
            onTap: () => setState(() => _mode = m),
            borderRadius: BorderRadius.circular(R.sm),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: on ? AppColors.surface : null,
                borderRadius: BorderRadius.circular(R.sm),
              ),
              child: Text(label, style: AppType.bodyStrong(color: on ? AppColors.brand : AppColors.textMid)),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, 0),
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(color: AppColors.surfaceSunken, borderRadius: BorderRadius.circular(R.md)),
        child: Row(children: [
          seg(_Mode.side, 'جانبي'),
          const SizedBox(width: 3),
          seg(_Mode.top, 'من الأعلى'),
          const SizedBox(width: 3),
          seg(_Mode.list, 'قائمة'),
        ]),
      ),
    );
  }

  Widget _stage() {
    return Container(
      height: 390,
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.symmetric(horizontal: BorderSide(color: AppColors.border)),
      ),
      child: LayoutBuilder(builder: (context, c) {
        final size = Size(c.maxWidth, c.maxHeight);
        return switch (_mode) {
          _Mode.side => _sideView(size),
          _Mode.top => _topView(size),
          _Mode.list => _listView(),
        };
      }),
    );
  }

  // ── المنظر الجانبيّ ──────────────────────────────────────────────────────────────────────

  Color _healthColor(ArrangedDevice a) {
    final r = _readings[a.device.id];
    if (a.device.lastStatus == 'offline' || _failed.contains(a.device.id)) return AppColors.error;
    if (r == null) return AppColors.textMid;
    if (a.role == TowerRole.link) return r.signal == null ? AppColors.brand : Grade.signal(r.signal).fill;
    if (r.quality == null) return AppColors.brand;
    return Grade.percentHigherBetter(r.quality).fill;
  }

  String _badge(ArrangedDevice a) {
    final r = _readings[a.device.id];
    if (a.device.lastStatus == 'offline') return 'لا يردّ';
    if (r == null) return '…';
    if (a.role == TowerRole.link) return r.downBps == null ? '—' : TowerText.bps(r.downBps).replaceAll(' ', '');
    return r.clients == null ? '—' : '${r.clients}';
  }

  Widget _sideView(Size size) {
    final geo = TowerGeometry(size, _settings);
    final onTower = _arranged.values.where((a) => a.onTower && a.azimuth != null).toList();
    final cabinet = _arranged.values.where((a) => !a.onTower || a.azimuth == null).toList();

    final placed = <({ArrangedDevice a, ({double x, double y, double sx, double cz}) p})>[
      for (final a in onTower) (a: a, p: geo.place(a.level, a.azimuth!, _view)),
    ]..sort((x, y) => x.p.cz.compareTo(y.p.cz));

    final sel = _sel == null ? null : _arranged[_sel];
    var beam = <Offset>[];
    var beamFront = true;
    if (sel != null && sel.onTower && sel.azimuth != null && (sel.role == TowerRole.sector || sel.role == TowerRole.ap)) {
      final p = geo.place(sel.level, sel.azimuth!, _view);
      final half = math.min(sel.beamwidth / 2, 45.0);
      beam = [Offset(p.x, p.y)];
      for (var k = -2; k <= 2; k++) {
        final a = (sel.azimuth! + k * half / 2 - _view) * math.pi / 180;
        beam.add(Offset(p.x + math.sin(a) * 150, p.y + math.cos(a) * 150 * kTowerSquash));
      }
      beamFront = p.cz > -0.25;
    }
    final linksFront = <({Offset from, Offset to})>[];
    final linksBack = <({Offset from, Offset to})>[];
    for (final e in placed.where((e) => e.a.role == TowerRole.link)) {
      final from = Offset(e.p.x, e.p.y);
      final to = Offset(e.p.x + e.p.sx * 340, e.p.y + e.p.cz * 340 * kTowerSquash);
      (e.p.cz > -0.25 ? linksFront : linksBack).add((from: from, to: to));
    }

    Widget overlay({required bool front}) => Positioned.fill(
          child: IgnorePointer(
            child: AnimatedBuilder(
              animation: _flow,
              builder: (_, __) => CustomPaint(
                painter: SideOverlayPainter(
                  beam: beamFront == front ? beam : const [],
                  beamColor: sel == null ? AppColors.brand : _healthColor(sel),
                  links: front ? linksFront : linksBack,
                  phase: _flow.value,
                  front: front,
                ),
              ),
            ),
          ),
        );

    final cab = geo.cabinet(cabinet.length);
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragStart: (_) => _spin.stop(),
      onHorizontalDragUpdate: (d) => setState(() => _view = (_view - d.delta.dx * 0.6) % 360),
      child: Stack(clipBehavior: Clip.hardEdge, children: [
        overlay(front: false),
        for (final e in placed.where((e) => e.p.cz <= -0.25)) _sideDevice(e.a, e.p),
        Positioned.fill(
          child: IgnorePointer(
            child: Semantics(
              label: 'رسم البرج من الجانب وعليه ${onTower.length} جهازاً',
              child: CustomPaint(painter: SideTowerPainter(geo: geo, cabinetCount: cabinet.length)),
            ),
          ),
        ),
        overlay(front: true),
        for (final e in placed.where((e) => e.p.cz > -0.25)) _sideDevice(e.a, e.p),
        for (var i = 0; i < cabinet.length && i < 4; i++) _cabinetDevice(cabinet[i], cab, i, cabinet.length),
        Positioned(left: 12, top: 10, child: _legend()),
        PositionedDirectional(
          start: 12,
          top: 10,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _pill('الواجهة: ${TowerText.dir(_view.round())} ${normDeg(_view)}°'),
            if (_arranged.values.any((a) => a.onTower && !a.fixed)) ...[
              const SizedBox(height: 6),
              _approxChip(),
            ],
          ]),
        ),
        Positioned(
          left: 12,
          bottom: 12,
          child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            _pill('اسحب البرج لتدويره'),
            const SizedBox(height: 6),
            Row(children: [
              _roundButton(LucideIcons.rotateCcw, 'تدوير البرج لليسار', () => _rotateBy(45)),
              const SizedBox(width: 8),
              _roundButton(LucideIcons.rotateCw, 'تدوير البرج لليمين', () => _rotateBy(-45)),
            ]),
          ]),
        ),
      ]),
    );
  }

  Widget _sideDevice(ArrangedDevice a, ({double x, double y, double sx, double cz}) p) {
    final front = p.cz > -0.25;
    final scale = 0.8 + 0.2 * (p.cz + 1) / 2;
    const base = 40.0;
    final box = DeviceGlyph.boxFor(a.shape, base * scale);
    final selected = a.device.id == _sel;
    final color = _healthColor(a);
    final flip = switch (a.shape) {
      TowerShape.dish => p.sx < 0,
      TowerShape.sector => p.sx > 0,
      _ => false,
    };
    final alert = _alerts.where((x) => x.deviceId == a.device.id).firstOrNull;
    return Positioned(
      left: p.x - box.width / 2,
      top: p.y - box.height / 2,
      child: Opacity(
        opacity: front ? 1 : 0.55,
        child: Semantics(
          button: true,
          selected: selected,
          label: '${a.device.name}، ${TowerText.role(a.role)}، ${_badge(a)}',
          child: GestureDetector(
            onTap: () => _select(a.device.id),
            child: Stack(clipBehavior: Clip.none, children: [
              Container(
                decoration: selected
                    ? BoxDecoration(
                        borderRadius: BorderRadius.circular(R.check),
                        border: Border.all(color: AppColors.brand, width: 2),
                      )
                    : null,
                padding: const EdgeInsets.all(2),
                child: DeviceGlyph(shape: a.shape, size: base * scale, flip: flip, dashed: !a.fixed && front),
              ),
              // أعرض من الجهاز: السكتر نحيلٌ (٠٫٦ من ارتفاعه) فكان «18» يُقصّ إلى «1».
              Positioned(
                top: box.height + 4,
                left: -28,
                right: -28,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(R.pill)),
                    child: Text(iso(_badge(a)), style: AppType.microBold(color: AppColors.onBrand), maxLines: 1),
                  ),
                ),
              ),
              if (alert != null)
                Positioned(
                  top: -6,
                  left: -6,
                  child: Container(
                    width: 15,
                    height: 15,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: alert.tone.fill,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.surface, width: 2),
                    ),
                    child: Text('!', style: AppType.daysWordBold(color: AppColors.onBrand)),
                  ),
                ),
            ]),
          ),
        ),
      ),
    );
  }

  List<ArrangedDevice> get _cabinet =>
      [for (final a in _arranged.values) if (!a.onTower || a.azimuth == null) a]
        ..sort((x, y) => naturalCompare(x.device.name, y.device.name));

  /// الكابينة قائمةً تحت الرسم — المالك ٢٧ أكتوبر: «اجهزه السويجات ما يظهر بيها شي بعرض البرج». في الرسم رموزٌ
  /// صغيرة بلا أسماء؛ هنا الاسم والحالة وأنشط منفذ والمنافذ والطاقة، والضغط يختاره فتظهر بطاقته.
  Widget _cabinetSection() {
    final list = _cabinet;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, 0),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(R.lg),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Sp.md, Sp.md, Sp.md, Sp.xs),
            child: Row(children: [
              Icon(LucideIcons.server, size: 16, color: AppColors.brand),
              const SizedBox(width: 6),
              Text('الكابينة · ${list.length}', style: AppType.bodyStrong(color: AppColors.textHi)),
              const Spacer(),
              Text('السويجات والراوترات', style: AppType.micro(color: AppColors.textMid)),
            ]),
          ),
          for (final a in list) _cabinetRow(a),
          const SizedBox(height: Sp.xs),
        ]),
      ),
    );
  }

  Widget _cabinetRow(ArrangedDevice a) {
    final r = _readings[a.device.id];
    final selected = a.device.id == _sel;
    final offline = a.device.lastStatus == 'offline' || _failed.contains(a.device.id);
    final facts = <String>[
      if (r?.busiestPort != null) '${r!.busiestPort!.name} ${TowerText.bps(r.downBps)}',
      if (r?.portsTotal != null) 'منافذ ${r!.portsUp}/${r.portsTotal}',
      if (r?.poeWatts != null) 'PoE ${r!.poeWatts!.toStringAsFixed(0)} W',
      if (r?.temperature != null) '${r!.temperature}°',
    ];
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: () => _select(a.device.id),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: 9),
          color: selected ? AppColors.brandSoftBg : null,
          child: Row(children: [
            SizedBox(width: 36, child: Center(child: DeviceGlyph(shape: a.shape, size: 26, color: _healthColor(a)))),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(a.device.name,
                    style: AppType.bodyStrong(color: AppColors.textHi), maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(
                  offline
                      ? 'لا يردّ'
                      : (r == null ? 'يقرأ…' : (facts.isEmpty ? (a.device.model ?? TowerText.shape(a.shape)) : isoJoin(facts, ' · '))),
                  style: AppType.muted(color: offline ? AppColors.error : AppColors.textMid),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ]),
            ),
            Container(width: 8, height: 8, decoration: BoxDecoration(color: _healthColor(a), shape: BoxShape.circle)),
          ]),
        ),
      ),
    );
  }

  Widget _cabinetDevice(ArrangedDevice a, Rect cab, int i, int total) {
    final col = i % 2;
    final row = i ~/ 2;
    final selected = a.device.id == _sel;
    final x = cab.left + 10 + col * 26.0;
    final y = cab.top + 8 + row * 20.0;
    return Positioned(
      left: x,
      top: y,
      child: Semantics(
        button: true,
        selected: selected,
        label: '${a.device.name} في الكابينة',
        child: GestureDetector(
          onTap: () => _select(a.device.id),
          child: Container(
            padding: const EdgeInsets.all(1),
            decoration: selected
                ? BoxDecoration(borderRadius: BorderRadius.circular(R.check), border: Border.all(color: AppColors.brand, width: 2))
                : null,
            child: DeviceGlyph(shape: a.shape, size: 22, color: _healthColor(a)),
          ),
        ),
      ),
    );
  }

  Widget _legend() {
    Widget row(AppTone t, String label) => Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(color: t.fill, shape: BoxShape.circle)),
          const SizedBox(width: 5),
          Text(label, style: AppType.micro(color: AppColors.textMid)),
        ]);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(color: AppColors.bg, borderRadius: BorderRadius.circular(R.sm)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        row(AppTone.success, 'ممتاز'),
        const SizedBox(height: 3),
        row(AppTone.warning, 'متوسّط'),
        const SizedBox(height: 3),
        row(AppTone.danger, 'ضعيف'),
      ]),
    );
  }

  Widget _pill(String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(color: AppColors.bg, borderRadius: BorderRadius.circular(R.sm)),
        child: Text(iso(text), style: AppType.muted(color: AppColors.textHi)),
      );

  Widget _approxChip() => Semantics(
        button: true,
        child: InkWell(
          onTap: () => _openPlace(null),
          borderRadius: BorderRadius.circular(R.sm),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(R.sm),
              border: Border.all(color: AppColors.warning),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(_canEdit ? LucideIcons.compass : LucideIcons.lock, size: 14, color: AppTone.warning.onSoft),
              const SizedBox(width: 5),
              Text('اتّجاهات تقريبيّة · ثبّتها', style: AppType.pillBold(color: AppTone.warning.onSoft)),
            ]),
          ),
        ),
      );

  Widget _roundButton(IconData icon, String label, VoidCallback onTap) => Semantics(
        button: true,
        label: label,
        child: Material(
          color: AppColors.surface,
          shape: CircleBorder(side: BorderSide(color: AppColors.border)),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(width: 44, height: 44, child: Icon(icon, size: 20, color: AppColors.brand)),
          ),
        ),
      );

  // ── من الأعلى ──────────────────────────────────────────────────────────────────────────

  Widget _topView(Size size) {
    final side = math.min(size.width, size.height);
    final c = Offset(size.width / 2, size.height / 2 - 6);
    final rMax = side / 2 - 26;
    double radiusOf(ArrangedDevice a) => switch (a.level) {
          TowerLevel.upper => rMax * 0.94,
          TowerLevel.lower => rMax * 0.8,
          TowerLevel.mid => rMax * 0.58,
          TowerLevel.top => rMax * 0.94,
          TowerLevel.base => rMax * 0.4,
        };
    final radios = _arranged.values
        .where((a) => a.onTower && a.azimuth != null && a.role != TowerRole.link)
        .toList();
    final links = _arranged.values.where((a) => a.role == TowerRole.link && a.azimuth != null).toList();
    final wedges = [
      for (final a in radios)
        (
          azimuth: a.azimuth!,
          half: a.shape == TowerShape.omni ? 180 : math.min(a.beamwidth ~/ 2, a.role == TowerRole.ap ? 40 : 30),
          radius: radiusOf(a),
          color: _healthColor(a),
          selected: a.device.id == _sel,
          approx: !a.fixed,
        ),
    ];
    final cabinet = _arranged.values.where((a) => !a.onTower || a.azimuth == null).toList();
    return Stack(children: [
      Positioned.fill(
        child: Semantics(
          label: 'اتّجاهات الأجهزة من الأعلى',
          child: AnimatedBuilder(
            animation: _flow,
            builder: (_, __) => CustomPaint(
              painter: TopViewPainter(
                wedges: wedges,
                links: [for (final l in links) (azimuth: l.azimuth!, selected: l.device.id == _sel)],
                phase: _flow.value,
                textDirection: Directionality.of(context),
              ),
            ),
          ),
        ),
      ),
      for (final a in radios) _topLabel(a, TopViewPainter.polar(c, radiusOf(a) * 0.64, a.azimuth!)),
      for (final l in links) _topLabel(l, TopViewPainter.polar(c, rMax - 8, l.azimuth!)),
      if (cabinet.isNotEmpty)
        PositionedDirectional(
          end: 12,
          bottom: 12,
          child: Wrap(spacing: 6, children: [
            for (final a in cabinet.take(3))
              _smallButton(a.device.name, a.device.id == _sel, () => _select(a.device.id)),
          ]),
        ),
    ]);
  }

  Widget _topLabel(ArrangedDevice a, Offset at) {
    final selected = a.device.id == _sel;
    final r = _readings[a.device.id];
    final num = RegExp(r'\d+').allMatches(a.device.name).map((m) => m.group(0)).lastOrNull;
    final title = a.role == TowerRole.link ? 'لنك' : (num ?? a.device.name.characters.take(4).toString());
    final value = a.role == TowerRole.link ? (r?.downBps == null ? '—' : '${(r!.downBps! / 1e6).round()}') : (r?.clients?.toString() ?? '—');
    final alert = _alerts.where((x) => x.deviceId == a.device.id || x.otherId == a.device.id).firstOrNull;
    return Positioned(
      left: at.dx - 21,
      top: at.dy - 19,
      child: Semantics(
        button: true,
        selected: selected,
        label: '${a.device.name}، ${_badge(a)}',
        child: GestureDetector(
          onTap: () => _select(a.device.id),
          child: Stack(clipBehavior: Clip.none, children: [
            Container(
              width: 42,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(R.sm),
                border: Border.all(color: selected ? AppColors.brand : AppColors.border, width: selected ? 2 : 1),
                boxShadow: [BoxShadow(color: AppColors.scrim.withValues(alpha: 0.08), blurRadius: 2, offset: const Offset(0, 1))],
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(iso(title), style: AppType.daysWord(color: AppColors.textMid), maxLines: 1),
                Text(iso(value), style: AppType.pillBold(color: _healthColor(a)), maxLines: 1),
              ]),
            ),
            if (alert != null)
              Positioned(
                top: -4,
                left: -4,
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: alert.tone.fill,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.surface, width: 2),
                  ),
                ),
              ),
          ]),
        ),
      ),
    );
  }

  Widget _smallButton(String label, bool selected, VoidCallback onTap) => Semantics(
        button: true,
        selected: selected,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(R.sm),
          child: Container(
            constraints: const BoxConstraints(minHeight: 40),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(R.sm),
              border: Border.all(color: selected ? AppColors.brand : AppColors.border, width: selected ? 2 : 1),
            ),
            child: Text(iso(label), style: AppType.body(color: AppColors.textHi)),
          ),
        ),
      );

  // ── القائمة ────────────────────────────────────────────────────────────────────────────

  Widget _listView() {
    final rows = _arranged.values.where((a) => a.role != TowerRole.cabinet).toList();
    int key(ArrangedDevice a) {
      final r = _readings[a.device.id];
      return switch (_sort) {
        _Sort.clients => -(r?.clients ?? -1),
        _Sort.quality => r?.quality ?? 999,
        _Sort.traffic => -(r?.downBps ?? -1),
        _Sort.signal => r?.signal ?? 999,
      };
    }

    rows.sort((x, y) {
      final c = key(x).compareTo(key(y));
      return c != 0 ? c : naturalCompare(x.device.name, y.device.name);
    });
    Widget sortChip(_Sort s, String label) {
      final on = _sort == s;
      return Padding(
        padding: const EdgeInsetsDirectional.only(end: 6),
        child: Semantics(
          button: true,
          selected: on,
          child: InkWell(
            onTap: () => setState(() => _sort = s),
            borderRadius: BorderRadius.circular(R.pill),
            child: Container(
              height: 34,
              padding: const EdgeInsets.symmetric(horizontal: 11),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: on ? AppColors.brand : AppColors.surface,
                borderRadius: BorderRadius.circular(R.pill),
                border: Border.all(color: on ? AppColors.brand : AppColors.border),
              ),
              child: Text(label, style: AppType.pillBold(color: on ? AppColors.onBrand : AppColors.textHi)),
            ),
          ),
        ),
      );
    }

    final head = AppType.micro(color: AppColors.textMid);
    return Column(children: [
      SizedBox(
        height: 48,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          children: [
            Center(child: Text('رتّب حسب  ', style: AppType.muted(color: AppColors.textMid))),
            sortChip(_Sort.clients, 'المشتركين'),
            sortChip(_Sort.quality, 'CCQ'),
            sortChip(_Sort.traffic, 'الترافك'),
            sortChip(_Sort.signal, 'الإشارة'),
          ],
        ),
      ),
      Container(
        height: 24,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.border))),
        child: Row(children: [
          Expanded(child: Text('الجهاز', style: head)),
          SizedBox(width: 40, child: Text('مشترك', style: head, textAlign: TextAlign.center)),
          SizedBox(width: 44, child: Text('CCQ', style: head, textAlign: TextAlign.center)),
          SizedBox(width: 62, child: Text('ترافك', style: head, textAlign: TextAlign.center)),
          SizedBox(width: 46, child: Text('إشارة', style: head, textAlign: TextAlign.center)),
        ]),
      ),
      Expanded(
        child: ListView.builder(
          itemCount: rows.length,
          itemBuilder: (_, i) {
            final a = rows[i];
            final r = _readings[a.device.id];
            final selected = a.device.id == _sel;
            final q = r?.quality;
            return Semantics(
              button: true,
              selected: selected,
              child: InkWell(
                onTap: () => _select(a.device.id),
                child: Container(
                  height: 40,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: selected ? AppColors.brandSoftBg : null,
                    border: Border(bottom: BorderSide(color: AppColors.divider)),
                  ),
                  child: Row(children: [
                    Expanded(
                      child: Text.rich(
                        TextSpan(children: [
                          TextSpan(text: a.device.name, style: AppType.bodyStrong(color: AppColors.textHi)),
                          TextSpan(
                            text: a.azimuth == null ? '' : ' · ${TowerText.dir(a.azimuth!)}',
                            style: AppType.body(color: AppColors.textMid),
                          ),
                        ]),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    SizedBox(
                      width: 40,
                      child: Text(r?.clients?.toString() ?? '—', textAlign: TextAlign.center, style: AppType.body(color: AppColors.textHi)),
                    ),
                    SizedBox(
                      width: 44,
                      child: Text(
                        q == null ? '—' : '$q٪',
                        textAlign: TextAlign.center,
                        style: AppType.bodyBold(color: q == null ? AppColors.textMid : Grade.percentHigherBetter(q).fill),
                      ),
                    ),
                    SizedBox(
                      width: 62,
                      child: Text(iso(TowerText.bps(r?.downBps)), textAlign: TextAlign.center, style: AppType.body(color: AppColors.textHi)),
                    ),
                    SizedBox(
                      width: 46,
                      child: Text(iso(r?.signal?.toString() ?? '—'), textAlign: TextAlign.center, style: AppType.body(color: AppColors.textMid)),
                    ),
                  ]),
                ),
              ),
            );
          },
        ),
      ),
    ]);
  }

  // ── بطاقة الجهاز المختار ────────────────────────────────────────────────────────────────

  Widget _deviceCard(ArrangedDevice a) {
    final d = a.device;
    final r = _readings[d.id];
    final alert = _alerts.where((x) => x.deviceId == d.id).firstOrNull;
    final offline = d.lastStatus == 'offline';
    final failed = _failed.contains(d.id);
    final AppTone tone = offline || failed
        ? AppTone.danger
        : (a.role == TowerRole.link
            ? Grade.signal(r?.signal)
            : (r?.quality == null ? AppTone.neutral : Grade.percentHigherBetter(r!.quality)));
    final healthText = offline
        ? 'لا يردّ'
        : failed
            ? 'تعذّر الاتّصال'
            : switch (tone) {
                AppTone.success => 'ممتاز',
                AppTone.warning => 'متوسّط',
                AppTone.danger => 'ضعيف',
                _ => r == null ? 'يقرأ…' : 'طبيعي',
              };
    final where = a.azimuth == null
        ? TowerText.level(a.level)
        : '${TowerText.level(a.level)} · ${TowerText.dir(a.azimuth!)} ${a.azimuth}° · ${TowerText.source(a.azimuthSource)}';

    final readings = <(String, String)>[];
    final info = <(String, String, Color?)>[];
    switch (a.role) {
      case TowerRole.link:
        readings.addAll([
          ('يعبر الآن', TowerText.bps(r?.downBps)),
          ('الرفع', TowerText.bps(r?.upBps)),
          ('الإشارة', r?.signal == null ? '—' : '${r!.signal} dBm'),
          ('CCQ', r?.quality == null ? '—' : '${r!.quality}٪'),
        ]);
      case TowerRole.sector:
      case TowerRole.ap:
        readings.addAll([
          ('المشتركون', r?.clients?.toString() ?? '—'),
          ('CCQ', r?.quality == null ? '—' : '${r!.quality}٪'),
          ('الإشارة', r?.signal == null ? '—' : '${r!.signal} dBm'),
          ('الترافك', TowerText.bps(r?.downBps)),
        ]);
      case TowerRole.cabinet:
        readings.addAll([
          ('المعالج', r?.cpu == null ? '—' : '${r!.cpu}٪'),
          ('الحرارة', r?.temperature == null ? '—' : '${r!.temperature}°'),
          ('أنشط منفذ', TowerText.bps(r?.downBps)),
          ('يعمل منذ', TowerText.uptime(r?.uptime)),
        ]);
    }
    if (a.role != TowerRole.cabinet) {
      info.addAll([
        ('التردّد MHz', r?.frequency?.toString() ?? '—', null),
        ('العرض MHz', r?.channelWidth?.toString() ?? '—', null),
        ('المنفذ', r?.linkSpeed ?? '—', r?.linkSpeed == null ? null : Grade.linkSpeedText(r!.linkSpeed!).fill),
        ('يعمل منذ', TowerText.uptime(r?.uptime), null),
      ]);
    } else {
      // السويج والراوتر: المنافذ وأنشطها والطاقة (المالك ٢٧ أكتوبر: «السويجات ما يظهر بيها شي»).
      final bp = r?.busiestPort;
      info.addAll([
        ('المنافذ الشغّالة', r?.portsTotal == null ? '—' : '${r!.portsUp}/${r.portsTotal}', null),
        ('المنفذ الأنشط', bp == null ? '—' : bp.name, null),
        ('استهلاك PoE', r?.poeWatts == null ? '—' : '${r!.poeWatts!.toStringAsFixed(1)} W', null),
        ('الفولتيّة', r?.voltage == null ? '—' : '${r!.voltage!.toStringAsFixed(1)} V',
            r?.voltage == null ? null : Grade.voltage(r!.voltage).fill),
      ]);
    }
    final weakest = [...?r?.peers.where((p) => p.signal != null)]..sort((x, y) => x.signal!.compareTo(y.signal!));

    return Padding(
      padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, 0),
      child: Container(
        padding: const EdgeInsets.all(Sp.md),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(R.lg),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: AppColors.brandSoftBg, borderRadius: BorderRadius.circular(R.chip)),
              child: DeviceGlyph(shape: a.shape, size: 26, color: AppColors.brand),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(d.name, style: AppType.cardTitleBold(color: AppColors.textHi), maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(iso('${d.model ?? NetworkDeviceLabels.brandLabel(d.brand)} · ${TowerText.shape(a.shape)}'),
                    style: AppType.muted(color: AppColors.textMid), maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(iso(where), style: AppType.muted(color: AppColors.textMid), maxLines: 2),
              ]),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
              decoration: BoxDecoration(color: tone.fill, borderRadius: BorderRadius.circular(R.pill)),
              child: Text(healthText, style: AppType.pillBold(color: AppColors.onBrand)),
            ),
          ]),
          if (alert != null) ...[
            const SizedBox(height: Sp.md),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              decoration: BoxDecoration(color: alert.tone.softBg, borderRadius: BorderRadius.circular(R.sm)),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(LucideIcons.triangleAlert, size: 16, color: alert.tone.onSoft),
                const SizedBox(width: 8),
                Expanded(child: Text(iso(alert.detail), style: AppType.bodyStrong(color: alert.tone.onSoft))),
              ]),
            ),
          ],
          if (a.nameSaysSectorButLink) ...[
            const SizedBox(height: Sp.sm),
            Text('اسمه «سكتر» لكن عليه طرفٌ واحد، فرسمناه لنك. تقدر تغيّره من «مكان الجهاز».',
                style: AppType.muted(color: AppColors.textMid)),
          ],
          const SizedBox(height: Sp.md),
          _grid([for (final x in readings) _cell(x.$1, x.$2, filled: true)]),
          if (info.isNotEmpty) ...[
            const SizedBox(height: 6),
            _grid([for (final x in info) _cell(x.$1, x.$2, color: x.$3)]),
          ],
          if (a.role == TowerRole.sector || a.role == TowerRole.ap) ...[
            const SizedBox(height: Sp.md),
            Text('أضعف المشتركين إشارةً', style: AppType.bodyStrong(color: AppColors.textHi)),
            const SizedBox(height: 4),
            if (weakest.isEmpty)
              Text(r == null ? 'نقرأ الجهاز…' : 'لا مشتركين متّصلين الآن', style: AppType.muted(color: AppColors.textMid))
            else
              for (final p in weakest.take(3)) _peerRow(p),
          ],
          const SizedBox(height: Sp.md),
          Row(children: [
            Expanded(
              child: _cardButton(
                _canEdit ? 'عدّل مكانه' : 'عدّل مكانه',
                icon: _canEdit ? LucideIcons.compass : LucideIcons.lock,
                onTap: () => _openPlace(d.id),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(child: _cardButton('صفحة الجهاز', primary: true, onTap: () => _openDevice(d))),
          ]),
        ]),
      ),
    );
  }

  Widget _grid(List<Widget> cells) => Row(children: [
        for (var i = 0; i < cells.length; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          Expanded(child: cells[i]),
        ],
      ]);

  Widget _cell(String label, String value, {bool filled = false, Color? color}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 7),
        decoration: BoxDecoration(
          color: filled ? AppColors.bg : null,
          borderRadius: BorderRadius.circular(R.sm),
          border: filled ? null : Border.all(color: AppColors.border),
        ),
        child: Column(children: [
          Text(label, style: AppType.micro(color: AppColors.textMid), maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(iso(value), style: AppType.rowValue(color: color ?? AppColors.textHi), maxLines: 1),
          ),
        ]),
      );

  Widget _peerRow(PeerLink p) {
    final tone = Grade.signal(p.signal);
    return Container(
      height: 32,
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(color: AppColors.bg, borderRadius: BorderRadius.circular(R.sm)),
      child: Row(children: [
        Expanded(child: Text(iso(p.name), style: AppType.body(color: AppColors.textHi), maxLines: 1, overflow: TextOverflow.ellipsis)),
        Text(iso('${p.signal} dBm'), style: AppType.bodyBold(color: tone.fill)),
        if (p.ccq != null) ...[
          const SizedBox(width: 10),
          Text(iso('CCQ ${p.ccq}٪'), style: AppType.body(color: AppColors.textMid)),
        ],
      ]),
    );
  }

  Widget _cardButton(String label, {IconData? icon, bool primary = false, required VoidCallback onTap}) => Semantics(
        button: true,
        child: Material(
          color: primary ? AppColors.brand : AppColors.surface,
          borderRadius: BorderRadius.circular(R.md),
          child: InkWell(
            borderRadius: BorderRadius.circular(R.md),
            onTap: onTap,
            child: Container(
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(R.md),
                border: Border.all(color: primary ? AppColors.brand : AppColors.border),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                if (icon != null) ...[
                  Icon(icon, size: 16, color: primary ? AppColors.onBrand : AppColors.brand),
                  const SizedBox(width: 6),
                ],
                Text(label, style: AppType.bodyBold(color: primary ? AppColors.onBrand : AppColors.brand)),
              ]),
            ),
          ),
        ),
      );
}
