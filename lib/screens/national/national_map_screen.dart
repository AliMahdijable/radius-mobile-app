import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../api/national_map_api.dart';
import '../../core/widgets/app_sheet.dart';
import '../../core/widgets/design_sheet.dart';
import '../../core/widgets/sheet_scaffold.dart';
import '../../models/subscriber.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import '../subscribers/subscriber_detail_screen.dart';

/// «خريطة المشتركين» للمشروع الوطنيّ في التطبيق (٢ نوفمبر — نسخة الموقع `pages/ftth/WataniMap.tsx`؛ المالك: «توزيع المشتركين
/// بمخطط جميل على الزونات ثم على الفاتات»، ثمّ «نمط الارضي… نسخ الاحداثيات او ارساله كرابط… البحث… ابحث ع اسمه مشترك او زون او
/// فاته مجاي يظهر»): «المخطّط» (الزونات ← الفاتات ← المشتركون بحالاتهم ومنافذهم) و«الخريطة» (مواقع الزونات والفاتات المستوردة من
/// KML في الموقع، بالخريطة أو القمر الصناعيّ، وبطاقة الموقع: نسخٌ وإرسالٌ وفتح)، وبحثٌ واحدٌ يجد المشترك والزون والفات.

class NationalMapScreen extends StatefulWidget {
  const NationalMapScreen({super.key});

  @override
  State<NationalMapScreen> createState() => _NationalMapScreenState();
}

/// الاسم بلا تشكيلٍ ولا همزاتٍ مختلفة، صغيراً — للبحث (كالموقع fold).
String _fold(String s) => s
    .toLowerCase()
    .replaceAll(RegExp('[ً-ٰٟـ]'), '')
    .replaceAll(RegExp('[أإآ]'), 'ا')
    .replaceAll('ى', 'ي')
    .replaceAll('ة', 'ه')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

class _NationalMapScreenState extends State<NationalMapScreen> {
  bool _loading = true;
  String? _err;
  bool _off = false;
  List<MapRow> _rows = const [];
  Map<String, MapFatInfo>? _items;
  bool _warming = false;
  int _known = 0;
  int _total = 0;
  List<GeoPlace> _gZones = const [];
  List<GeoPlace> _gFats = const [];
  String? _geoErr;
  ({List<MapZone> zones, MapCounts totals, int fatCount})? _tree;
  Timer? _poll;
  int _polls = 0;

  int _tab = 0;
  final _q = TextEditingController();
  String? _openZone;
  bool _sat = false;
  final _map = MapController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _poll?.cancel();
    _q.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    _poll?.cancel();
    setState(() {
      _loading = true;
      _err = null;
    });
    final res = await Future.wait([NationalMapApi.rows(), NationalMapApi.fatMap(), NationalMapApi.geo()]);
    if (!mounted) return;
    final rows = res[0] as NationalMapResult<List<MapRow>>;
    final fat = res[1] as NationalMapResult<({Map<String, MapFatInfo> items, bool warming, int known, int total})>;
    final geo = res[2] as NationalMapResult<({List<GeoPlace> zones, List<GeoPlace> fats})>;
    setState(() {
      _loading = false;
      if (!rows.ok) {
        _err = rows.error;
        _off = rows.off;
        return;
      }
      if (!fat.ok && fat.off) {
        _err = fat.error;
        _off = true;
        return;
      }
      _rows = rows.data!;
      _items = fat.ok ? fat.data!.items : null;
      _warming = fat.ok && fat.data!.warming;
      _known = fat.ok ? fat.data!.known : 0;
      _total = fat.ok ? fat.data!.total : 0;
      _gZones = geo.ok ? geo.data!.zones : const [];
      _gFats = geo.ok ? geo.data!.fats : const [];
      _geoErr = geo.ok ? null : geo.error;
      _tree = buildNationalMap(_rows, _items);
    });
    _schedule();
  }

  /// الفاتات ما زالت تُجمع بالخادم ⇒ تُسأل وحدها كلّ ٨ث (حتى دقيقتين).
  void _schedule() {
    if (!_warming || _polls >= 15) return;
    _poll = Timer(const Duration(seconds: 8), () async {
      _polls++;
      final fat = await NationalMapApi.fatMap();
      if (!mounted || !fat.ok) return;
      setState(() {
        _items = fat.data!.items;
        _warming = fat.data!.warming;
        _known = fat.data!.known;
        _total = fat.data!.total;
        _tree = buildNationalMap(_rows, _items);
      });
      _schedule();
    });
  }

  /* ───────── المساعدات ───────── */

  static Color _statusColor(String s) => switch (s) {
        'expired' => AppColors.error,
        'suspended' => AppColors.warning,
        _ => AppColors.success,
      };
  static String _statusLabel(String s) => switch (s) {
        'expired' => 'منتهٍ',
        'suspended' => 'موقوف',
        _ => 'فعّال',
      };

  /// مكان الفات على الخريطة (مرجعه «FAT7-FBG2251»).
  GeoPlace? _fatPlace(MapFat f, MapZone z) {
    if (f.kind != MapFatKind.fat) return null;
    final ref = geoFatRef(f.name, f.fdt ?? z.name);
    if (ref == null) return null;
    for (final g in _gFats) {
      if (g.ref.toUpperCase() == ref.toUpperCase() && g.hasPoint) return g;
    }
    return null;
  }

  GeoPlace? _zonePlace(MapZone z) {
    final code = geoZoneCode(z.name) ?? geoZoneCode(z.key);
    if (code == null) return null;
    for (final g in _gZones) {
      if (g.ref.toUpperCase() == code && (g.hasPoint || g.polygon.isNotEmpty)) return g;
    }
    return null;
  }

  LatLng? _center(GeoPlace g) {
    if (g.hasPoint) return LatLng(g.lat!, g.lng!);
    if (g.polygon.isEmpty) return null;
    final lat = g.polygon.map((p) => p[0]).reduce((a, b) => a + b) / g.polygon.length;
    final lng = g.polygon.map((p) => p[1]).reduce((a, b) => a + b) / g.polygon.length;
    return LatLng(lat, lng);
  }

  void _openSub(MapRow r) {
    final sub = Subscriber.fromJson(r.raw);
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => SubscriberDetailScreen(sub: sub)));
  }

  Future<void> _showFat(MapFat f, MapZone z) async {
    final place = _fatPlace(f, z);
    await showAppSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: AppColors.scrim,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (c) => DesignSheet(
        header: SheetHeaderBar(
          icon: LucideIcons.network,
          title: f.name,
          subtitle: [z.name, if (f.fdt != null) 'FDT ${f.fdt}', '${f.total} مشترك'].join(' · '),
          onClose: () => Navigator.of(c).pop(),
        ),
        body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (place != null) ...[
            _LocationActions(name: f.name, lat: place.lat!, lng: place.lng!),
            const SizedBox(height: Sp.md),
          ],
          for (final r in f.rows) _SubLine(row: r, port: _items?[r.raw['idx']?.toString() ?? '']?.port, onTap: () {
            Navigator.of(c).pop();
            _openSub(r);
          }),
        ]),
      ),
    );
  }

  /* ───────── البحث ───────── */

  List<Widget> _results() {
    final q = _fold(_q.text);
    final t = _tree;
    if (t == null || q.length < 2) return const [];
    final out = <Widget>[];
    var n = 0;
    for (final z in t.zones) {
      if (_fold(z.name).contains(q) || _fold(z.key).contains(q)) {
        out.add(_ResultLine(icon: LucideIcons.mapPin, title: z.name, subtitle: 'زون · ${z.total} مشترك', onTap: () => setState(() {
              _openZone = z.key;
              _q.clear();
            })));
        n++;
      }
      for (final f in z.fats) {
        if (f.kind == MapFatKind.fat && _fold(f.name).contains(q)) {
          out.add(_ResultLine(icon: LucideIcons.network, title: f.name, subtitle: 'فات · ${z.name} · ${f.total} مشترك', onTap: () => _showFat(f, z)));
          n++;
        }
        for (final r in f.rows) {
          if (n >= 40) break;
          if (_fold(r.name).contains(q) || _fold(r.username).contains(q)) {
            out.add(_ResultLine(
              icon: LucideIcons.user,
              title: r.name,
              subtitle: [z.name, if (f.kind == MapFatKind.fat) f.name, _statusLabel(r.status)].join(' · '),
              onTap: () => _openSub(r),
            ));
            n++;
          }
        }
      }
    }
    if (out.isEmpty) out.add(Padding(padding: const EdgeInsets.all(Sp.lg), child: Text('لا شيء بهذا البحث', style: AppType.muted())));
    return out;
  }

  /* ───────── العرض ───────── */

  Widget _totals(MapCounts c, int fats) => Container(
        padding: const EdgeInsets.all(Sp.md),
        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(R.card), border: Border.all(color: AppColors.border)),
        child: Wrap(spacing: Sp.lg, runSpacing: Sp.sm, children: [
          _stat('المشتركون', c.total, AppColors.textHi),
          _stat('فعّال', c.active, AppColors.success),
          _stat('موقوف', c.suspended, AppColors.warning),
          _stat('منتهٍ', c.expired, AppColors.error),
          _stat('متّصل', c.online, AppColors.brand),
          _stat('الفاتات', fats, AppColors.textMid),
        ]),
      );

  Widget _stat(String l, int v, Color c) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('$v', style: AppType.statValue(color: c)),
        Text(l, style: AppType.micro(color: AppColors.textMid)),
      ]);

  Widget _bar(MapCounts c) {
    if (c.total == 0) return const SizedBox(height: 6);
    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: SizedBox(
        height: 6,
        child: Row(children: [
          if (c.active > 0) Expanded(flex: c.active, child: ColoredBox(color: AppColors.success)),
          if (c.suspended > 0) Expanded(flex: c.suspended, child: ColoredBox(color: AppColors.warning)),
          if (c.expired > 0) Expanded(flex: c.expired, child: ColoredBox(color: AppColors.error)),
        ]),
      ),
    );
  }

  Widget _zoneCard(MapZone z) {
    final open = _openZone == z.key;
    return Container(
      margin: const EdgeInsets.only(bottom: Sp.sm),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(R.card), border: Border.all(color: AppColors.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        InkWell(
          borderRadius: BorderRadius.circular(R.card),
          onTap: () => setState(() => _openZone = open ? null : z.key),
          child: Padding(
            padding: const EdgeInsets.all(Sp.md),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Icon(LucideIcons.mapPin, size: 16, color: AppColors.brandAccent),
                const SizedBox(width: Sp.sm),
                Expanded(child: Text(z.name, textDirection: TextDirection.ltr, textAlign: TextAlign.start, style: AppType.cardTitle(), maxLines: 1, overflow: TextOverflow.ellipsis)),
                if (_zonePlace(z) != null)
                  IconButton(
                    tooltip: 'موقع الزون',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _placeCard(_zonePlace(z)!, 'زون', z.total),
                    icon: Icon(LucideIcons.locateFixed, size: 16, color: AppColors.brand),
                  ),
                Text('${z.total} مشترك', style: AppType.label(color: AppColors.textHi)),
                const SizedBox(width: Sp.xs),
                AnimatedRotation(turns: open ? 0.5 : 0, duration: const Duration(milliseconds: 160), child: Icon(LucideIcons.chevronDown, size: 18, color: AppColors.textLow)),
              ]),
              const SizedBox(height: Sp.sm),
              _bar(z),
              const SizedBox(height: 6),
              Text(
                [
                  'فعّال ${z.active}',
                  if (z.suspended > 0) 'موقوف ${z.suspended}',
                  if (z.expired > 0) 'منتهٍ ${z.expired}',
                  '${z.fatCount} فات',
                  if (z.pending > 0) '${z.pending} لم يُعرف فاتهم بعد',
                ].join(' · '),
                style: AppType.micro(color: AppColors.textMid),
              ),
            ]),
          ),
        ),
        if (open)
          for (final f in z.fats)
            InkWell(
              onTap: () => _showFat(f, z),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: 10),
                decoration: BoxDecoration(border: Border(top: BorderSide(color: AppColors.border))),
                child: Row(children: [
                  Icon(f.kind == MapFatKind.fat ? LucideIcons.network : LucideIcons.circleHelp, size: 15, color: AppColors.textMid),
                  const SizedBox(width: Sp.sm),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(f.name, textDirection: f.kind == MapFatKind.fat ? TextDirection.ltr : null, style: AppType.body(color: AppColors.textHi)),
                      if (f.ports.isNotEmpty)
                        Text('المنافذ: ${f.ports.take(12).join('، ')}${f.ports.length > 12 ? '…' : ''}', style: AppType.micro(color: AppColors.textMid)),
                    ]),
                  ),
                  if (_fatPlace(f, z) != null) ...[Icon(LucideIcons.locateFixed, size: 14, color: AppColors.brand), const SizedBox(width: 6)],
                  Text('${f.total}', style: AppType.labelBold(color: AppColors.textHi)),
                  const SizedBox(width: 4),
                  Icon(LucideIcons.chevronLeft, size: 16, color: AppColors.textLow),
                ]),
              ),
            ),
      ]),
    );
  }

  Widget _chart() {
    final t = _tree!;
    final q = _q.text.trim();
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.sm, Sp.lg, Sp.xl),
        children: [
          if (q.length >= 2) ..._results()
          else ...[
            _totals(t.totals, t.fatCount),
            const SizedBox(height: Sp.md),
            if (t.zones.isEmpty) Text('لا مشتركين بعد', style: AppType.muted()),
            for (final z in t.zones) _zoneCard(z),
          ],
        ],
      ),
    );
  }

  Widget _mapView() {
    final hasGeo = _gZones.any((g) => g.hasPoint || g.polygon.isNotEmpty) || _gFats.any((g) => g.hasPoint);
    if (!hasGeo) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(Sp.xl),
          child: Text(
            _geoErr ?? 'لا مواقع للزونات والفاتات بعد — استوردها من الموقع (ملف KML من كوكل ايرث) فتظهر هنا.',
            textAlign: TextAlign.center,
            style: AppType.muted(),
          ),
        ),
      );
    }
    final pts = <LatLng>[
      for (final g in _gZones)
        if (_center(g) != null) _center(g)!,
      for (final g in _gFats)
        if (g.hasPoint) LatLng(g.lat!, g.lng!),
    ];
    final lat = pts.map((p) => p.latitude).reduce((a, b) => a + b) / pts.length;
    final lng = pts.map((p) => p.longitude).reduce((a, b) => a + b) / pts.length;
    final counts = <String, int>{};
    final t = _tree;
    if (t != null) {
      for (final z in t.zones) {
        final zc = geoZoneCode(z.name) ?? geoZoneCode(z.key);
        if (zc != null) counts[zc] = (counts[zc] ?? 0) + z.total;
        for (final f in z.fats) {
          final ref = f.kind == MapFatKind.fat ? geoFatRef(f.name, f.fdt ?? z.name) : null;
          if (ref != null) counts[ref.toUpperCase()] = (counts[ref.toUpperCase()] ?? 0) + f.total;
        }
      }
    }
    return Stack(children: [
      FlutterMap(
        mapController: _map,
        options: MapOptions(
          initialCenter: LatLng(lat, lng),
          initialZoom: 14,
          interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
        ),
        children: [
          TileLayer(
            urlTemplate: _sat
                ? 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}'
                : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.mysvcs.radMysvcs',
            maxNativeZoom: _sat ? 18 : 19,
            maxZoom: 20,
          ),
          if (_sat)
            TileLayer(
              urlTemplate: 'https://server.arcgisonline.com/ArcGIS/rest/services/Reference/World_Boundaries_and_Places/MapServer/tile/{z}/{y}/{x}',
              userAgentPackageName: 'com.mysvcs.radMysvcs',
              maxNativeZoom: 18,
              maxZoom: 20,
            ),
          PolygonLayer(polygons: [
            for (final g in _gZones)
              if (g.polygon.length >= 3)
                Polygon(
                  points: [for (final p in g.polygon) LatLng(p[0], p[1])],
                  color: AppColors.brand.withValues(alpha: 0.12),
                  borderColor: AppColors.brand,
                  borderStrokeWidth: 1.5,
                ),
          ]),
          MarkerLayer(markers: [
            for (final g in _gZones)
              if (_center(g) != null)
                Marker(
                  point: _center(g)!,
                  width: 120,
                  height: 34,
                  child: GestureDetector(
                    onTap: () => _placeCard(g, 'زون', counts[g.ref.toUpperCase()]),
                    child: _Pin(label: g.ref, zone: true),
                  ),
                ),
            for (final g in _gFats)
              if (g.hasPoint)
                Marker(
                  point: LatLng(g.lat!, g.lng!),
                  width: 92,
                  height: 30,
                  child: GestureDetector(
                    onTap: () => _placeCard(g, 'فات', counts[g.ref.toUpperCase()]),
                    child: _Pin(label: (g.name ?? g.ref).split('-').first, zone: false),
                  ),
                ),
          ]),
        ],
      ),
      PositionedDirectional(
        top: Sp.sm,
        end: Sp.sm,
        child: Material(
          color: AppColors.surface,
          elevation: 2,
          borderRadius: BorderRadius.circular(R.pill),
          child: InkWell(
            borderRadius: BorderRadius.circular(R.pill),
            onTap: () => setState(() => _sat = !_sat),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(_sat ? LucideIcons.map : LucideIcons.satellite, size: 16, color: AppColors.textHi),
                const SizedBox(width: 6),
                Text(_sat ? 'خريطة' : 'قمر صناعي', style: AppType.label(color: AppColors.textHi)),
              ]),
            ),
          ),
        ),
      ),
    ]);
  }

  Future<void> _placeCard(GeoPlace g, String kind, int? subs) async {
    final c = _center(g);
    if (c == null) return;
    await showAppSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: AppColors.scrim,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (s) => DesignSheet(
        header: SheetHeaderBar(
          icon: kind == 'زون' ? LucideIcons.mapPin : LucideIcons.network,
          title: g.name ?? g.ref,
          subtitle: [kind, g.ref, if (subs != null) '$subs مشترك'].join(' · '),
          onClose: () => Navigator.of(s).pop(),
        ),
        body: _LocationActions(name: g.name ?? g.ref, lat: c.latitude, lng: c.longitude),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep
    final Widget body;
    if (_loading && _tree == null) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_err != null && _tree == null) {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(Sp.xl),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(_err!, textAlign: TextAlign.center, style: AppType.body(color: _off ? AppColors.textMid : AppColors.error)),
            if (!_off) ...[const SizedBox(height: Sp.md), OutlinedButton(onPressed: _load, child: const Text('إعادة المحاولة'))],
          ]),
        ),
      );
    } else {
      body = Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.sm, Sp.lg, 0),
          child: SheetSearchField(controller: _q, hint: 'ابحث: اسم مشترك أو زون أو فات', onChanged: (_) => setState(() {
                if (_tab == 1 && _q.text.trim().length >= 2) _tab = 0;
              })),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.sm, Sp.lg, 0),
          child: SheetSegmented(
            labels: const ['المخطّط', 'الخريطة'],
            icons: const [LucideIcons.chartBarBig, LucideIcons.map],
            selectedIndex: _tab,
            onSelect: (i) => setState(() => _tab = i),
          ),
        ),
        if (_warming)
          Padding(
            padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.sm, Sp.lg, 0),
            child: Text('جارٍ جمع فاتات المشتركين من البوّابة… ($_known من $_total)', style: AppType.micro(color: AppColors.textMid)),
          ),
        const SizedBox(height: Sp.sm),
        Expanded(child: _tab == 0 ? _chart() : _mapView()),
      ]);
    }
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        title: Text('خريطة المشتركين', style: AppType.title(color: AppColors.textHi).copyWith(fontSize: 16)),
        iconTheme: IconThemeData(color: AppColors.textHi),
        actions: [
          IconButton(tooltip: 'تحديث', onPressed: _loading ? null : _load, icon: Icon(LucideIcons.refreshCw, size: 18, color: AppColors.textHi)),
        ],
      ),
      body: body,
    );
  }
}

class _Pin extends StatelessWidget {
  const _Pin({required this.label, required this.zone});
  final String label;
  final bool zone;

  @override
  Widget build(BuildContext context) => Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: zone ? AppColors.brand : AppColors.surface,
            borderRadius: BorderRadius.circular(R.pill),
            border: Border.all(color: AppColors.brand, width: 1.2),
            boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 3)],
          ),
          child: Text(label,
              textDirection: TextDirection.ltr,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppType.micro(color: zone ? AppColors.onBrand : AppColors.brand).copyWith(fontWeight: FontWeight.w700)),
        ),
      );
}

class _SubLine extends StatelessWidget {
  const _SubLine({required this.row, this.port, required this.onTap});
  final MapRow row;
  final int? port;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final st = row.status;
    final color = _NationalMapScreenState._statusColor(st);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(R.md),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
        child: Row(children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: Sp.sm),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(row.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.body(color: AppColors.textHi)),
              Text(row.username, textDirection: TextDirection.ltr, maxLines: 1, style: AppType.micro(color: AppColors.textMid)),
            ]),
          ),
          if (row.online) ...[Icon(LucideIcons.wifi, size: 14, color: AppColors.success), const SizedBox(width: 6)],
          Text(_NationalMapScreenState._statusLabel(st), style: AppType.micro(color: color)),
          if (port != null) ...[const SizedBox(width: Sp.sm), Text('منفذ $port', style: AppType.micro(color: AppColors.textMid))],
        ]),
      ),
    );
  }
}

class _ResultLine extends StatelessWidget {
  const _ResultLine({required this.icon, required this.title, required this.subtitle, required this.onTap});
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(R.md),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
          child: Row(children: [
            Icon(icon, size: 16, color: AppColors.textMid),
            const SizedBox(width: Sp.sm),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.body(color: AppColors.textHi)),
                Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.micro(color: AppColors.textMid)),
              ]),
            ),
            Icon(LucideIcons.chevronLeft, size: 16, color: AppColors.textLow),
          ]),
        ),
      );
}

/// نسخ الإحداثيّات، وإرسال الموقع رابطاً، وفتحه بالخرائط (المالك ٢ نوفمبر).
class _LocationActions extends StatelessWidget {
  const _LocationActions({required this.name, required this.lat, required this.lng});
  final String name;
  final double lat;
  final double lng;

  String get _coords => '${lat.toStringAsFixed(6)}, ${lng.toStringAsFixed(6)}';
  String get _link => 'https://www.google.com/maps?q=${lat.toStringAsFixed(6)},${lng.toStringAsFixed(6)}';

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(_coords, textDirection: TextDirection.ltr, textAlign: TextAlign.center, style: AppType.labelBold(color: AppColors.textHi)),
      const SizedBox(height: Sp.sm),
      Row(children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: _coords));
              if (context.mounted) showSheetSnack(context, 'نُسخت الإحداثيّات');
            },
            icon: const Icon(LucideIcons.copy, size: 16),
            label: const Text('نسخ الإحداثيّات'),
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(44)),
          ),
        ),
        const SizedBox(width: Sp.sm),
        Expanded(
          child: Builder(
            builder: (btn) => OutlinedButton.icon(
              onPressed: () async {
                final box = btn.findRenderObject() as RenderBox?;
                final origin = box == null ? const Rect.fromLTWH(0, 0, 1, 1) : box.localToGlobal(Offset.zero) & box.size;
                try {
                  // ignore: deprecated_member_use
                  await Share.share('موقع $name\n$_link', sharePositionOrigin: origin);
                } catch (_) {
                  await Clipboard.setData(ClipboardData(text: _link));
                  if (btn.mounted) showSheetSnack(btn, 'نُسخ رابط الموقع');
                }
              },
              icon: const Icon(LucideIcons.share2, size: 16),
              label: const Text('إرسال الموقع'),
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(44)),
            ),
          ),
        ),
      ]),
      const SizedBox(height: Sp.sm),
      OutlinedButton.icon(
        onPressed: () => launchUrl(Uri.parse(_link), mode: LaunchMode.externalApplication),
        icon: const Icon(LucideIcons.navigation, size: 16),
        label: const Text('افتح على الخريطة'),
        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(44)),
      ),
    ]);
  }
}

