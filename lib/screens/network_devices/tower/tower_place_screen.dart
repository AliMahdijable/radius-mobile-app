import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../api/tower_api.dart';
import '../../../core/util/bidi.dart';
import '../../../core/widgets/app_sheet.dart';
import '../../../models/network_device.dart';
import '../../../models/tower_layout.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';
import '../../desktop/desk_widgets.dart';
import 'tower_logic.dart';
import 'tower_paint.dart';

/// مكان الجهاز على البرج — «جولة البوصلة»: يقف الوكيل عند البرج ويوجّه أعلى الهاتف نحو كلّ جهاز فيُثبَّت اتّجاهه.
///
/// يرجع ما تغيّر (جهاز ← مكان). كلّ تثبيتٍ يُحفظ فوراً على الخادم ([TowerApi.savePlacement]) فلا تضيع الجولة لو
/// خرج الوكيل في منتصفها. لا بوصلة (حاسبة، أو هاتفٌ بلا مستشعر) ⇒ الضبط بالأزرار وحدها.
class TowerPlaceScreen extends StatefulWidget {
  const TowerPlaceScreen({
    super.key,
    required this.devices,
    required this.arranged,
    this.startDeviceId,
    required this.settings,
    this.serverReady = true,
  });

  final List<NetworkDevice> devices;
  final Map<int, ArrangedDevice> arranged;
  final int? startDeviceId;
  final TowerSettings settings;

  /// تعذّر جلب الترتيب ⇒ لا يُرسل شيءٌ للخادم، والتغيير يبقى على هذا الهاتف.
  final bool serverReady;

  @override
  State<TowerPlaceScreen> createState() => _TowerPlaceScreenState();
}

class _TowerPlaceScreenState extends State<TowerPlaceScreen> {
  late final List<ArrangedDevice> _order;
  late int _sel;
  final Map<int, TowerPlacement> _edits = {};
  final Map<int, Timer> _pendingSave = {};
  StreamSubscription<CompassEvent>? _sub;
  double? _heading;
  double? _accuracy;
  String? _toast;

  static bool get _hasCompass => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  @override
  void initState() {
    super.initState();
    _order = widget.arranged.values.toList()
      ..sort((a, b) {
        // الكابينة آخراً، ثمّ من القمّة نزولاً، ثمّ بالاتّجاه — ترتيب الدوران حول البرج.
        final c = a.level.index.compareTo(b.level.index);
        return c != 0 ? c : (a.azimuth ?? 0).compareTo(b.azimuth ?? 0);
      });
    final start = widget.startDeviceId;
    _sel = start != null && widget.arranged.containsKey(start)
        ? start
        : (_order.where((a) => a.onTower && !a.fixed).firstOrNull ?? _order.firstOrNull)?.device.id ?? 0;
    _listen();
  }

  @override
  void dispose() {
    _sub?.cancel();
    for (final e in _pendingSave.entries.toList()) {
      e.value.cancel();
      _save(e.key);
    }
    super.dispose();
  }

  void _listen() {
    if (!_hasCompass) return;
    try {
      _sub = FlutterCompass.events?.listen((e) {
        final h = e.heading;
        if (h == null || !mounted) return;
        // أندرويد قد يُرجع −180..180 — يُطبَّع 0..360 (الشمال صفر).
        final now = (h % 360 + 360) % 360;
        setState(() {
          // تنعيمٌ دائريّ: المستشعر يرتجف بضع درجات، والقفز بين 359 و0 ليس دوراناً كاملاً.
          final prev = _heading;
          if (prev == null) {
            _heading = now;
          } else {
            var d = now - prev;
            if (d > 180) d -= 360;
            if (d < -180) d += 360;
            _heading = ((prev + d * 0.3) % 360 + 360) % 360;
          }
          _accuracy = e.accuracy;
        });
      }, onError: (_) {});
    } catch (_) {/* لا مستشعر — الضبط بالأزرار */}
  }

  ArrangedDevice get _cur => widget.arranged[_sel]!;

  TowerPlacement _placeOf(ArrangedDevice a) => _edits[a.device.id] ?? a.placement;

  bool _isFixed(ArrangedDevice a) => _placeOf(a).fixed;

  TowerLevel _levelOf(ArrangedDevice a) => _placeOf(a).level ?? a.level;

  bool _inCabinet(ArrangedDevice a) => _levelOf(a) == TowerLevel.base;

  int get _fixedCount => _order.where((a) => !_inCabinet(a) && _isFixed(a)).length;

  int get _towerCount => _order.where((a) => !_inCabinet(a)).length;

  void _patch(TowerPlacement p, {bool now = false}) {
    setState(() => _edits[p.deviceId] = p);
    _pendingSave[p.deviceId]?.cancel();
    if (now) {
      _pendingSave.remove(p.deviceId);
      _save(p.deviceId);
    } else {
      // ±1° متتالية تُحفظ مرّةً واحدة.
      _pendingSave[p.deviceId] = Timer(const Duration(milliseconds: 700), () {
        _pendingSave.remove(p.deviceId);
        _save(p.deviceId);
      });
    }
  }

  Future<void> _save(int id) async {
    final p = _edits[id];
    if (p == null || !widget.serverReady) return;
    final r = await TowerApi.savePlacement(p);
    if (!r.ok && mounted) {
      setState(() => _toast = r.message ?? 'تعذّر حفظ مكان الجهاز');
    }
  }

  ArrangedDevice? _nextUnfixed() {
    final i = _order.indexWhere((a) => a.device.id == _sel);
    for (var k = 1; k <= _order.length; k++) {
      final a = _order[(i + k) % _order.length];
      if (!_inCabinet(a) && !_isFixed(a)) return a;
    }
    return null;
  }

  void _pin() {
    final h = _heading;
    if (h == null) return;
    final a = _cur;
    final az = normDeg(h.round());
    HapticFeedback.mediumImpact();
    _patch(_placeOf(a).copyWith(azimuth: az, fixed: true, level: _levelOf(a)), now: true);
    final next = _nextUnfixed();
    setState(() {
      _toast = 'ثُبّت «${a.device.name}» على $az°${next == null ? ' · اكتملت الجولة' : ' · التالي: ${next.device.name}'}';
      if (next != null) _sel = next.device.id;
    });
  }

  void _nudge(int deg) {
    final a = _cur;
    final from = _placeOf(a).azimuth ?? a.azimuth ?? 0;
    HapticFeedback.selectionClick();
    _patch(_placeOf(a).copyWith(azimuth: from + deg, fixed: true, level: _levelOf(a)));
  }

  void _skip() {
    final next = _nextUnfixed();
    final i = _order.indexWhere((a) => a.device.id == _sel);
    setState(() {
      _toast = null;
      _sel = (next ?? _order[(i + 1) % _order.length]).device.id;
    });
  }

  Future<void> _pickShape() async {
    final a = _cur;
    final picked = await showAppSheet<Object>(
      context: context,
      barrierColor: AppColors.scrim,
      backgroundColor: AppColors.surface,
      builder: (ctx) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          ListTile(
            leading: const Icon(LucideIcons.sparkles),
            title: const Text('من الموديل (تلقائيّ)'),
            onTap: () => Navigator.pop(ctx, 'auto'),
          ),
          for (final s in TowerShape.values)
            ListTile(
              leading: SizedBox(width: 32, child: Center(child: DeviceGlyph(shape: s, size: 24, color: AppColors.brand))),
              title: Text(TowerText.shape(s)),
              selected: _placeOf(a).shape == s,
              onTap: () => Navigator.pop(ctx, s),
            ),
        ]),
      ),
    );
    if (picked == null || !mounted) return;
    final p = _placeOf(a);
    _patch(picked is TowerShape ? p.copyWith(shape: picked) : p.copyWith(clearShape: true), now: true);
  }

  // ── البناء ─────────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final a = _cur;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(Map<int, TowerPlacement>.of(_edits));
      },
      child: Scaffold(
        backgroundColor: AppColors.bg,
        appBar: deskPageBar(
          context,
          mobile: AppBar(
            backgroundColor: AppColors.surface,
            foregroundColor: AppColors.textHi,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(LucideIcons.arrowRight, size: 20),
              onPressed: () => Navigator.of(context).pop(Map<int, TowerPlacement>.of(_edits)),
            ),
            title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('مكان الجهاز'),
              Text('جولة البوصلة · $_fixedCount من $_towerCount مثبّتة', style: AppType.muted(color: AppColors.textMid)),
            ]),
          ),
        ),
        body: ListView(
          padding: EdgeInsets.only(bottom: Inset.route(context) + Sp.lg),
          children: [
            _chips(),
            Padding(
              padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.sm, Sp.lg, 0),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                _deviceHead(a),
                const SizedBox(height: Sp.md),
                if (_inCabinet(a)) _cabinetNote(a) else _direction(a),
                const SizedBox(height: Sp.md),
                _levels(a),
                const SizedBox(height: Sp.lg),
                Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _order.length < 2 ? null : _skip,
                      icon: const Icon(LucideIcons.skipForward, size: 18),
                      label: const Text('الجهاز التالي'),
                      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(46)),
                    ),
                  ),
                  const SizedBox(width: Sp.sm),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.of(context).pop(Map<int, TowerPlacement>.of(_edits)),
                      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(46)),
                      child: const Text('حفظ وإنهاء'),
                    ),
                  ),
                ]),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chips() {
    return SizedBox(
      height: 52,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: Sp.lg, vertical: 6),
        itemCount: _order.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (_, i) {
          final a = _order[i];
          final on = a.device.id == _sel;
          final cab = _inCabinet(a);
          final dot = cab ? AppColors.textLow : (_isFixed(a) ? AppColors.success : AppColors.warning);
          return Semantics(
            button: true,
            selected: on,
            label: '${a.device.name}، ${cab ? 'في الكابينة' : (_isFixed(a) ? 'مثبّت' : 'تقريبيّ')}',
            child: InkWell(
              onTap: () => setState(() {
                _sel = a.device.id;
                _toast = null;
              }),
              borderRadius: BorderRadius.circular(R.pill),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: on ? AppColors.brand : AppColors.surface,
                  borderRadius: BorderRadius.circular(R.pill),
                  border: Border.all(color: on ? AppColors.brand : AppColors.border),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(width: 8, height: 8, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
                  const SizedBox(width: 6),
                  Text(a.device.name, style: AppType.bodyStrong(color: on ? AppColors.onBrand : AppColors.textHi)),
                ]),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _deviceHead(ArrangedDevice a) {
    final p = _placeOf(a);
    final shape = p.shape ?? a.shape;
    final from = p.shape != null ? 'اخترته أنت' : 'عُرف من الموديل';
    return Container(
      padding: const EdgeInsets.all(Sp.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.lg),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(children: [
        Container(
          width: 48,
          height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: AppColors.brandSoftBg, borderRadius: BorderRadius.circular(R.md)),
          child: DeviceGlyph(shape: shape, size: 28, color: AppColors.brand),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(a.device.name,
                style: AppType.cardTitleBold(color: AppColors.textHi), maxLines: 1, overflow: TextOverflow.ellipsis),
            if ((a.device.model ?? '').isNotEmpty)
              Text(iso(a.device.model!), style: AppType.muted(color: AppColors.textMid), maxLines: 1),
            Text('الشكل: ${TowerText.shape(shape)} · $from', style: AppType.muted(color: AppColors.textMid)),
          ]),
        ),
        TextButton(onPressed: _pickShape, child: const Text('تغيير الشكل')),
      ]),
    );
  }

  Widget _cabinetNote(ArrangedDevice a) => Container(
        padding: const EdgeInsets.all(Sp.md),
        decoration: BoxDecoration(color: AppColors.surfaceSunken, borderRadius: BorderRadius.circular(R.md)),
        child: Row(children: [
          Icon(LucideIcons.server, size: 18, color: AppColors.textMid),
          const SizedBox(width: Sp.sm),
          Expanded(
            child: Text('«${a.device.name}» في الكابينة — لا يحتاج اتّجاهاً.',
                style: AppType.body(color: AppColors.textBody)),
          ),
        ]),
      );

  Widget _direction(ArrangedDevice a) {
    final p = _placeOf(a);
    final saved = p.azimuth ?? a.azimuth;
    final fixed = p.fixed;
    final beam = p.beamwidth ?? a.beamwidth;
    final h = _heading;
    final weak = _accuracy != null && _accuracy! > 15;
    final status = !_hasCompass
        ? 'لا بوصلة على هذا الجهاز — اضبط الاتّجاه بالأزرار'
        : h == null
            ? 'ينتظر البوصلة…'
            : weak
                ? 'البوصلة غير دقيقة الآن — حرّك الهاتف بشكل 8 ثمّ وجّهه'
                : saved == null
                    ? 'وجّه أعلى الهاتف نحو الجهاز ثمّ ثبّت'
                    : 'يختلف عن المحفوظ بـ${angleGap(h.round(), saved)}°';
    String deg(int? v) => v == null ? '—' : '$v° ${TowerText.dir(v)}';
    return Container(
      padding: const EdgeInsets.all(Sp.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.lg),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('الاتّجاه', style: AppType.bodyStrong(color: AppColors.textHi)),
        Text('قف عند البرج، ووجّه أعلى الهاتف نحو «${a.device.name}».', style: AppType.muted(color: AppColors.textMid)),
        const SizedBox(height: Sp.sm),
        Center(
          child: Semantics(
            label: 'البوصلة: ${h == null ? 'غير متاحة' : '${h.round()} درجة'}، المحفوظ ${saved ?? 'لا شيء'}',
            child: SizedBox(
              width: 220,
              height: 220,
              child: CustomPaint(
                painter: CompassDialPainter(
                  savedAzimuth: saved,
                  half: (beam / 2).round(),
                  heading: h,
                  fixed: fixed,
                  textDirection: Directionality.of(context),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: Sp.sm),
        Row(children: [
          Expanded(child: _fact('البوصلة الآن', h == null ? '—' : deg(h.round()))),
          const SizedBox(width: Sp.sm),
          Expanded(child: _fact('المحفوظ', '${deg(saved)} · ${fixed ? 'مثبّت' : 'تقريبيّ'}')),
        ]),
        const SizedBox(height: 6),
        Text(iso(status), textAlign: TextAlign.center, style: AppType.muted(color: weak ? AppColors.warning : AppColors.textMid)),
        const SizedBox(height: Sp.sm),
        FilledButton.icon(
          onPressed: h == null ? null : _pin,
          icon: const Icon(LucideIcons.locateFixed, size: 18),
          label: const Text('ثبّت الاتّجاه هنا'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(46)),
        ),
        if (_toast != null) ...[
          const SizedBox(height: 6),
          Text(iso(_toast!), textAlign: TextAlign.center, style: AppType.body(color: AppColors.success)),
        ],
        const SizedBox(height: Sp.sm),
        Row(children: [
          for (final (i, v) in const [-5, -1, 1, 5].indexed) ...[
            if (i > 0) const SizedBox(width: 6),
            Expanded(
              child: OutlinedButton(
                onPressed: () => _nudge(v),
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(40), padding: EdgeInsets.zero),
                child: Text(iso('${v > 0 ? '+' : '−'}${v.abs()}°'), semanticsLabel: '${v > 0 ? 'زِد' : 'نقّص'} ${v.abs()} درجة'),
              ),
            ),
          ],
        ]),
        if (_cur.shape == TowerShape.sector || _cur.shape == TowerShape.panel) ...[
          const SizedBox(height: Sp.md),
          Text('عرض الحزمة', style: AppType.bodyStrong(color: AppColors.textHi)),
          const SizedBox(height: 6),
          Row(children: [
            for (final (i, w) in const [60, 90, 120].indexed) ...[
              if (i > 0) const SizedBox(width: 6),
              Expanded(child: _choice('$w°', beam == w, () => _patch(p.copyWith(beamwidth: w, level: _levelOf(a))))),
            ],
          ]),
        ],
      ]),
    );
  }

  Widget _levels(ArrangedDevice a) {
    final cur = _levelOf(a);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('المستوى على البرج', style: AppType.bodyStrong(color: AppColors.textHi)),
      const SizedBox(height: 6),
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final l in TowerLevel.values)
          SizedBox(
            width: 96,
            child: _choice(TowerText.levelShort(l), cur == l, () {
              HapticFeedback.selectionClick();
              _patch(_placeOf(a).copyWith(level: l), now: true);
            }),
          ),
      ]),
    ]);
  }

  Widget _fact(String label, String value) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(color: AppColors.surfaceSunken, borderRadius: BorderRadius.circular(R.md)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: AppType.muted(color: AppColors.textMid)),
          Text(iso(value), style: AppType.bodyStrong(color: AppColors.textHi), maxLines: 1, overflow: TextOverflow.ellipsis),
        ]),
      );

  Widget _choice(String label, bool on, VoidCallback onTap) => Semantics(
        button: true,
        selected: on,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(R.sm),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: on ? AppColors.brand : AppColors.surface,
              borderRadius: BorderRadius.circular(R.sm),
              border: Border.all(color: on ? AppColors.brand : AppColors.border),
            ),
            child: Text(iso(label), style: AppType.bodyStrong(color: on ? AppColors.onBrand : AppColors.textHi)),
          ),
        ),
      );
}
