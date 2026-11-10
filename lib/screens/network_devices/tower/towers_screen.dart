import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../api/network_devices_api.dart';
import '../../../core/widgets/permission_locked.dart';
import '../../../core/widgets/sheet_scaffold.dart';
import '../../../models/device_region.dart';
import '../../../models/network_device.dart';
import '../../../services/device_events.dart';
import '../../../services/permissions_service.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';
import '../regions_screen.dart';
import 'tower_assign_screen.dart';
import 'tower_logic.dart';
import 'tower_screen.dart';
import 'tower_topology_logic.dart';
import 'tower_topology_screen.dart';

/// «أبراجي» — المالك ١١ نوفمبر: «واحد سوه ٤ مناطق كل منطقة بيها اجهزه خاصه بيها، بالمحصله النظرة ع البرج رح تصير ٤ ابراج
/// القسم ينتقل بينهم» + «القسم الجديد الترابط».
///
/// شريطٌ واحد تحت العنوان: «الترابط» ثمّ برجٌ لكلّ منطقة (و«بلا منطقة» إن بقيت أجهزةٌ بلا برج) و«برج جديد». النقرة تبدّل
/// المعروض في مكانه: [TowerScreen] للبرج المختار أو [TowerTopologyScreen] للترابط — بلا رجوعٍ لقائمة.
class TowersScreen extends StatefulWidget {
  const TowersScreen({super.key, required this.devices, required this.regions, this.openRegionId});

  /// أجهزة الشركة المفتوحة.
  final List<NetworkDevice> devices;
  final List<DeviceRegion> regions;

  /// برجٌ يُفتح مباشرةً (المنطقة المصفّاة في قائمة الأجهزة؛ 0 = بلا منطقة) — null: آخر ما فُتح بهذه الجلسة، ثمّ «الترابط»
  /// حين تتعدّد الأبراج، ثمّ البرج الوحيد.
  final int? openRegionId;

  /// معرّف «الترابط» بين اختيارات الشريط.
  static const topology = -1;

  /// آخر ما فُتح بهذه الجلسة — العودة للقسم تُكمل من حيث تُرك.
  static int? _last;

  @visibleForTesting
  static void debugResetLast() => _last = null;

  @override
  State<TowersScreen> createState() => _TowersScreenState();
}

class _TowersScreenState extends State<TowersScreen> {
  late List<NetworkDevice> _devices = widget.devices;
  late List<DeviceRegion> _regions = widget.regions;
  late int _sel = _initial();

  /// أين وصل تمرير الشريط — كلّ شاشةٍ تبني شريطها، فيبدأ من حيث تُرك لا من أوّله.
  double _barOffset = 0;
  Timer? _poll;
  int _gen = 0;

  bool get _canEdit => Perms.has('devices.manage');

  Map<int, int> get _counts {
    final m = <int, int>{};
    for (final d in _devices) {
      m[d.regionId ?? 0] = (m[d.regionId ?? 0] ?? 0) + 1;
    }
    return m;
  }

  /// أبراج الشريط: كلّ المناطق (والفارغة — لتُسند لها أجهزة) بترتيب أسمائها، ثمّ «بلا منطقة» إن فيها أجهزة.
  List<({int id, String name, String? color, int count})> get _towers {
    final c = _counts;
    final sorted = [..._regions]..sort((a, b) => naturalCompare(a.name, b.name));
    return [
      for (final r in sorted) (id: r.id, name: r.name, color: r.color, count: c[r.id] ?? 0),
      if ((c[0] ?? 0) > 0) (id: 0, name: 'بلا منطقة', color: null, count: c[0]!),
    ];
  }

  int _initial() {
    final towers = _towers;
    bool has(int? id) => id != null && (id == TowersScreen.topology || towers.any((t) => t.id == id));
    if (has(widget.openRegionId)) return widget.openRegionId!;
    if (has(TowersScreen._last)) return TowersScreen._last!;
    final withDevices = towers.where((t) => t.count > 0).toList();
    return withDevices.length == 1 ? withDevices.single.id : TowersScreen.topology;
  }

  @override
  void initState() {
    super.initState();
    DeviceEvents.changes.addListener(_reload);
    // القائمتان من الخادم للشركة المفتوحة نفسها — ما سُلِّم عند الفتح قد يحمل مناطق شركةٍ أخرى («كل الشركات») أو حالاً أقدم
    _reload();
    // لقطة حال الأجهزة على رسم الترابط («N لا يردّ») تتجدّد من جولات القسم
    _poll = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_sel == TowersScreen.topology) _reload();
    });
  }

  @override
  void dispose() {
    DeviceEvents.changes.removeListener(_reload);
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _reload() async {
    final gen = ++_gen;
    try {
      final r = await Future.wait([NetworkDevicesApi.list(), NetworkDevicesApi.listRegions()]);
      if (!mounted || gen != _gen) return;
      setState(() {
        _devices = r[0] as List<NetworkDevice>;
        _regions = r[1] as List<DeviceRegion>;
        // البرج المفتوح حُذفت منطقته (من شاشة المناطق) ⇒ الترابط
        if (_sel != TowersScreen.topology && !_towers.any((t) => t.id == _sel)) _sel = TowersScreen.topology;
      });
    } catch (_) {
      // فشل الجلب لا يُسقط اللقطة الحاليّة
    }
  }

  void _select(int id) {
    if (id == _sel) return;
    HapticFeedback.selectionClick();
    setState(() => _sel = id);
    TowersScreen._last = id;
  }

  String _name(int id) => id == 0 ? 'بلا منطقة' : (_regions.where((r) => r.id == id).firstOrNull?.name ?? 'برج');

  Future<void> _assign(int regionId) async {
    if (!_canEdit) {
      showNoPermission(context, action: true);
      return;
    }
    final moved = await Navigator.of(context).push<int>(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => TowerAssignScreen(
        regionId: regionId,
        regionName: _name(regionId),
        devices: _devices,
        towerName: _name,
      ),
    ));
    if (moved == null || !mounted) return;
    showSheetSnack(context, moved == 0 ? 'لا تغيير' : 'حُفظت أجهزة «${_name(regionId)}»');
  }

  Future<void> _newTower() async {
    if (!_canEdit) {
      showNoPermission(context, action: true);
      return;
    }
    final region = await showRegionForm(context, title: 'برج جديد');
    if (region == null || !mounted) return;
    setState(() {
      if (!_regions.any((r) => r.id == region.id)) _regions = [..._regions, region];
      _sel = region.id;
    });
    TowersScreen._last = region.id;
    // برجٌ بلا أجهزة لا معنى له — تُسند له فوراً
    await _assign(region.id);
  }

  @override
  Widget build(BuildContext context) {
    final towers = _towers;
    final bar = TowerSwitcher(
      towers: towers,
      selected: _sel,
      canEdit: _canEdit,
      onSelect: _select,
      onNew: _newTower,
      initialOffset: _barOffset,
      onOffset: (v) => _barOffset = v,
    );
    if (_sel == TowersScreen.topology) {
      return TowerTopologyScreen(
        key: const ValueKey('towers-topology'),
        devices: _devices,
        regions: _regions,
        switcher: bar,
        onOpenTower: _select,
        onNewTower: _newTower,
      );
    }
    final id = _sel;
    return TowerScreen(
      key: ValueKey('towers-tower-$id'),
      regionId: id,
      regionName: _name(id),
      devices: [
        for (final d in _devices)
          if ((d.regionId ?? 0) == id) d,
      ],
      switcher: bar,
      onAssign: id == 0 ? null : () => _assign(id),
    );
  }
}

/// شريط التنقّل بين «الترابط» والأبراج — تحت عنوان الشاشة، يتمرّر أفقيّاً ويُبقي المختار ظاهراً.
class TowerSwitcher extends StatefulWidget implements PreferredSizeWidget {
  const TowerSwitcher({
    super.key,
    required this.towers,
    required this.selected,
    required this.canEdit,
    required this.onSelect,
    required this.onNew,
    this.initialOffset = 0,
    this.onOffset,
  });

  final List<({int id, String name, String? color, int count})> towers;
  final int selected;
  final bool canEdit;
  final ValueChanged<int> onSelect;
  final VoidCallback onNew;

  /// من أين يبدأ تمرير الأبراج، ومن يُبلَّغ بتغيّره ([TowersScreen] يحفظه بين شاشةٍ وأخرى).
  final double initialOffset;
  final ValueChanged<double>? onOffset;

  static const height = 52.0;

  @override
  Size get preferredSize => const Size.fromHeight(height);

  @override
  State<TowerSwitcher> createState() => _TowerSwitcherState();
}

class _TowerSwitcherState extends State<TowerSwitcher> {
  final _keys = <int, GlobalKey>{};
  late final ScrollController _scroll = ScrollController(initialScrollOffset: widget.initialOffset)
    ..addListener(() => widget.onOffset?.call(_scroll.offset));

  GlobalKey _keyOf(int id) => _keys[id] ??= GlobalKey();

  @override
  void initState() {
    super.initState();
    _reveal();
  }

  @override
  void didUpdateWidget(TowerSwitcher old) {
    super.didUpdateWidget(old);
    if (old.selected != widget.selected) _reveal();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// المختار يبقى ظاهراً (برجٌ فُتح من رسم الترابط قد يكون خارج الظاهر من الشريط) — بأقلّ تمرير: الظاهر كلّه لا يتحرّك.
  void _reveal() {
    // «الترابط» ثابتةٌ خارج المتمرّر — لا شيء يُكشف لها
    if (widget.selected == TowersScreen.topology) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _keys[widget.selected]?.currentContext;
      if (ctx == null || !mounted || !_scroll.hasClients) return;
      // متمرّر الشريط نفسه لا متمرّرٌ يحويه
      if (Scrollable.maybeOf(ctx)?.position != _scroll.position) return;
      final box = ctx.findRenderObject();
      if (box == null || !box.attached) return;
      final viewport = RenderAbstractViewport.maybeOf(box);
      if (viewport == null) return;
      final a = viewport.getOffsetToReveal(box, 0).offset;
      final b = viewport.getOffsetToReveal(box, 1).offset;
      final pos = _scroll.position;
      final lo = (a < b ? a : b).clamp(pos.minScrollExtent, pos.maxScrollExtent);
      final hi = (a < b ? b : a).clamp(pos.minScrollExtent, pos.maxScrollExtent);
      final target = pos.pixels.clamp(lo, hi);
      if ((target - pos.pixels).abs() < 1) return;
      final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
      if (still) {
        _scroll.jumpTo(target);
      } else {
        _scroll.animateTo(target, duration: const Duration(milliseconds: 220), curve: Curves.easeOutCubic);
      }
    });
  }

  static Color? _color(String? hex) {
    final h = (hex ?? '').replaceAll('#', '');
    if (h.length != 6) return null;
    final v = int.tryParse(h, radix: 16);
    return v == null ? null : Color(0xFF000000 | v);
  }

  @override
  Widget build(BuildContext context) {
    // «الترابط» ثابتةٌ في أوّل الشريط (بيت القسم — لا تغيب بتمرير الأبراج)، والأبراج تتمرّر بجانبها. كلّ الحبّات مبنيّة
    // (لا قائمة كسولة): المختار يُمرَّر إليه أينما كان.
    return SizedBox(
      height: TowerSwitcher.height,
      child: Padding(
        padding: const EdgeInsets.only(top: 6, bottom: 10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const SizedBox(width: Sp.md),
          _chip(id: TowersScreen.topology, label: 'الترابط', icon: LucideIcons.network, pinned: true),
          Container(
            width: 1,
            margin: const EdgeInsetsDirectional.only(start: 8, top: 6, bottom: 6),
            color: AppColors.border,
          ),
          Expanded(
            child: SingleChildScrollView(
              controller: _scroll,
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsetsDirectional.only(start: 8, end: Sp.md),
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                for (final t in widget.towers) _chip(id: t.id, label: t.name, count: t.count, dot: _color(t.color)),
                Padding(
                  padding: const EdgeInsetsDirectional.only(start: 2),
                  child: Semantics(
                    button: true,
                    label: 'برج جديد',
                    excludeSemantics: true,
                    child: Material(
                      key: const ValueKey('towers-new'),
                      color: Colors.transparent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(R.chip),
                        side: BorderSide(color: AppColors.border),
                      ),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(R.chip),
                        onTap: widget.onNew,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 11),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(widget.canEdit ? LucideIcons.plus : LucideIcons.lock, size: 15, color: AppColors.brand),
                            const SizedBox(width: 4),
                            Text('برج', style: AppType.bodyBold(color: AppColors.brand)),
                          ]),
                        ),
                      ),
                    ),
                  ),
                ),
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _chip({required int id, required String label, int? count, IconData? icon, Color? dot, bool pinned = false}) {
    final on = widget.selected == id;
    return Padding(
      key: _keyOf(id),
      padding: EdgeInsetsDirectional.only(end: pinned ? 0 : 6),
      child: Semantics(
        button: true,
        selected: on,
        label: count == null ? label : 'برج $label — ${TopoText.devices(count)}',
        excludeSemantics: true,
        child: Material(
          key: ValueKey('towers-chip-$id'),
          color: on ? AppColors.brand : AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(R.chip),
            side: BorderSide(color: on ? AppColors.brand : AppColors.border),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(R.chip),
            onTap: () => widget.onSelect(id),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 190),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  if (icon != null) ...[
                    Icon(icon, size: 15, color: on ? AppColors.onBrand : AppColors.brand),
                    const SizedBox(width: 6),
                  ],
                  if (dot != null) ...[
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: dot,
                        shape: BoxShape.circle,
                        border: on ? Border.all(color: AppColors.onBrand, width: 1) : null,
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                  Flexible(
                    child: Text(label,
                        style: AppType.bodyBold(color: on ? AppColors.onBrand : AppColors.textHi),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ),
                  if (count != null) ...[
                    const SizedBox(width: 6),
                    Text('$count', style: AppType.muted(color: on ? AppColors.onBrand : AppColors.textMid)),
                  ],
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
