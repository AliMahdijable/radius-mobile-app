import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../api/vsol_olt_api.dart';
import '../../../core/util/bidi.dart';
import '../../../models/network_device.dart';
import '../../../services/fiber/fiber_map.dart';
import '../../../services/fiber/fiber_monitor.dart';
import '../../../services/fiber/fiber_onu.dart';
import '../../../services/fiber/fiber_store.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';
import '../../desktop/desk_widgets.dart';
import '../device_vitals.dart';
import 'fiber_pon_screen.dart';

/// «مخطّط الشبكة» — المالك ٢٨ أكتوبر: «نحتاج رسم خريطة بمسارات الضوئي ٢d… رسم بياني يوضح سيرفر الترفك والربط الشبكه لالياف».
///
/// لوحةٌ تُسحب وتُكبَّر: السيرفر ⇐ الأولت (ترفك الأبلنك) ⇐ منافذ الـPON (ترفك كلّ منفذ) ⇐ الموزّعات ⇐ الصناديق بمنافذها.
/// لوكيلٍ بأكثر من أولت: «كلّ الأولتات» تحت سيرفرٍ واحد، أو أولتٌ واحد. الضغط على منفذٍ/صندوق يفتح شاشة المنفذ.
class FiberMapScreen extends StatefulWidget {
  const FiberMapScreen({super.key, required this.olts, this.initialOltId, this.focusPon});

  final List<NetworkDevice> olts;
  final int? initialOltId;

  /// من شاشة منفذ: يُفتح على ذلك المنفذ وحده (والـ«كلّ المنافذ» بزرّ).
  final String? focusPon;

  @override
  State<FiberMapScreen> createState() => _FiberMapScreenState();
}

class _FiberMapScreenState extends State<FiberMapScreen> {
  /// `null` = كلّ الأولتات.
  late int? _oltId = widget.olts.length > 1 && widget.initialOltId == null ? null : (widget.initialOltId ?? widget.olts.first.id);
  late String? _pon = widget.focusPon;
  bool _showBoxes = true;
  bool _showLoose = true;
  final TransformationController _tc = TransformationController();
  Size? _viewport;
  String? _fittedFor;
  final Map<int, FiberMonitor> _held = {};

  static const _prefBoxes = 'fiber.map.showBoxes.v1';
  static const _prefLoose = 'fiber.map.showLoose.v1';

  @override
  void initState() {
    super.initState();
    bridgeFiberVitals();
    _holdScope();
    FiberStore.layout.addListener(_changed);
    FiberStore.ensureLoaded().then((_) => _changed());
    SharedPreferences.getInstance().then((p) {
      if (!mounted) return;
      setState(() {
        _showBoxes = p.getBool(_prefBoxes) ?? true;
        _showLoose = p.getBool(_prefLoose) ?? true;
      });
    }).catchError((_) {});
  }

  @override
  void dispose() {
    for (final m in _held.values) {
      m
        ..removeListener(_changed)
        ..release();
    }
    _held.clear();
    FiberStore.layout.removeListener(_changed);
    _tc.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  /// يمسك مراقب كلّ أولتٍ في النطاق (شاشةٌ مفتوحة ⇒ قراءة بإيقاع الشاشة، ومعها ترفك المنافذ)، ويُفلت ما خرج منه.
  void _holdScope() {
    final want = {for (final d in widget.olts) if (_oltId == null || d.id == _oltId) d.id: d};
    for (final id in _held.keys.toList()) {
      if (want.containsKey(id)) continue;
      _held.remove(id)!
        ..removeListener(_changed)
        ..release();
    }
    for (final e in want.entries) {
      if (_held.containsKey(e.key)) continue;
      final m = FiberMonitor.of(e.value)
        ..addListener(_changed)
        ..acquire();
      _held[e.key] = m;
    }
  }

  void _scope(int? oltId) {
    setState(() {
      _oltId = oltId;
      _pon = null;
      _fittedFor = null;
      _holdScope();
    });
  }

  void _toggle(String key, bool v) {
    setState(() {
      if (key == _prefBoxes) _showBoxes = v;
      if (key == _prefLoose) _showLoose = v;
      _fittedFor = null;
    });
    SharedPreferences.getInstance().then((p) => p.setBool(key, v)).catchError((_) => false);
  }

  FiberMapModel _model() {
    final olts = [
      for (final d in widget.olts)
        if (_oltId == null || d.id == _oltId)
          () {
            final m = _held[d.id];
            final stats = m?.stats;
            return FiberMapOlt(
              oltId: d.id,
              name: d.name,
              model: m?.profile.model ?? m?.profile.label,
              pons: stats?.ponPorts.toList() ?? const <VsolPonPort>[],
              onus: m?.onus ?? const [],
              ponRates: m == null ? const {} : Map.of(m.ponRates),
              uplinkRates: m == null ? const {} : Map.of(m.uplinkRates),
              outages: m?.outages ?? const [],
              ready: stats != null,
            );
          }(),
    ];
    return FiberMapModel.build(
      olts: olts,
      layout: FiberStore.layout.value,
      showBoxes: _showBoxes,
      showLoose: _showLoose,
      rtl: Directionality.of(context) == TextDirection.rtl,
      onlyPon: _oltId == null ? null : _pon,
    );
  }

  void _fit(FiberMapModel model, Size view) {
    final sx = view.width / model.width;
    final sy = view.height / model.height;
    final s = (sx < sy ? sx : sy).clamp(0.25, 1.4);
    final dx = (view.width - model.width * s) / 2;
    final dy = sy < sx ? 0.0 : (view.height - model.height * s) / 2;
    _tc.value = Matrix4.identity()
      ..translateByDouble(dx < 0 ? 0 : dx, dy < 0 ? 0 : dy, 0, 1)
      ..scaleByDouble(s, s, 1, 1);
  }

  void _onTap(FiberMapModel model, Offset p) {
    final n = model.hit(p.dx, p.dy);
    if (n == null) return;
    final m = _held[n.oltId];
    if (m == null) return;
    switch (n.kind) {
      case FiberMapKind.olt:
        if (_oltId == null && widget.olts.length > 1) _scope(n.oltId);
      case FiberMapKind.pon:
      case FiberMapKind.splitter:
      case FiberMapKind.box:
      case FiberMapKind.loose:
        final pon = n.pon;
        if (pon != null) {
          Navigator.of(context).push(MaterialPageRoute(builder: (_) => FiberPonScreen(monitor: m, pon: pon)));
        }
      case FiberMapKind.core:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final model = _model();
    final colors = FiberMapColors.of();
    final busy = _held.values.any((m) => m.busy);
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: deskPageBar(
        context,
        title: 'مخطّط الشبكة',
        subtitle: _oltId == null ? 'كلّ الأولتات' : widget.olts.firstWhere((d) => d.id == _oltId, orElse: () => widget.olts.first).name,
        mobile: AppBar(
          title: const Text('مخطّط الشبكة'),
          backgroundColor: AppColors.surface,
          foregroundColor: AppColors.textHi,
          elevation: 0,
          leading: IconButton(icon: const Icon(LucideIcons.arrowRight, size: 20), onPressed: () => Navigator.pop(context)),
          actions: [
            IconButton(
              tooltip: 'ملاءمة الشاشة',
              icon: const Icon(LucideIcons.maximize2, size: 20),
              onPressed: _viewport == null ? null : () => setState(() => _fit(model, _viewport!)),
            ),
            IconButton(
              tooltip: 'تحديث الآن',
              icon: busy
                  ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.brand))
                  : const Icon(LucideIcons.refreshCw, size: 20),
              onPressed: busy
                  ? null
                  : () {
                      for (final m in _held.values) {
                        m.refreshNow();
                      }
                    },
            ),
            const SizedBox(width: 4),
          ],
        ),
      ),
      body: Column(children: [
        _controls(),
        Expanded(
          child: LayoutBuilder(builder: (context, c) {
            final view = Size(c.maxWidth, c.maxHeight);
            _viewport = view;
            final key = '${_oltId ?? 'all'}|$_pon|$_showBoxes|$_showLoose|${model.width.round()}x${model.height.round()}';
            if (_fittedFor != key && model.width > 0) {
              _fittedFor = key;
              _fit(model, view);
            }
            return ClipRect(
              child: InteractiveViewer(
                transformationController: _tc,
                constrained: false,
                minScale: 0.2,
                maxScale: 3,
                boundaryMargin: const EdgeInsets.all(400),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapUp: (d) => _onTap(model, d.localPosition),
                  child: CustomPaint(
                    size: Size(model.width, model.height),
                    painter: FiberMapPainter(model, colors, Directionality.of(context)),
                  ),
                ),
              ),
            );
          }),
        ),
        _legend(),
      ]),
    );
  }

  Widget _controls() {
    Widget chip(String label, bool selected, VoidCallback onTap, {IconData? icon}) => Padding(
          padding: const EdgeInsetsDirectional.only(end: Sp.sm),
          child: ChoiceChip(
            avatar: icon == null ? null : Icon(icon, size: 15, color: selected ? AppColors.brandOnSoft : AppColors.textMid),
            label: Text(iso(label), maxLines: 1, overflow: TextOverflow.ellipsis),
            selected: selected,
            onSelected: (_) => onTap(),
            showCheckmark: false,
            selectedColor: AppColors.brandSoftBg,
            backgroundColor: AppColors.surface,
            side: BorderSide(color: selected ? AppColors.brandSoftBorder : AppColors.border),
            labelStyle: AppType.bodyStrong(color: selected ? AppColors.brandOnSoft : AppColors.textBody),
          ),
        );
    return Container(
      color: AppColors.surface,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.sm, Sp.lg, Sp.sm),
        child: Row(children: [
          if (widget.olts.length > 1) ...[
            chip('كلّ الأولتات', _oltId == null, () => _scope(null), icon: LucideIcons.layers),
            for (final d in widget.olts) chip(d.name, _oltId == d.id, () => _scope(d.id), icon: LucideIcons.server),
            Container(width: 1, height: 24, color: AppColors.border, margin: const EdgeInsetsDirectional.only(end: Sp.sm)),
          ],
          if (_pon != null && _oltId != null) chip('${fiberPonDisplay(_pon!)} وحده', true, () => setState(() {
                _pon = null;
                _fittedFor = null;
              }), icon: LucideIcons.x),
          chip('الصناديق', _showBoxes, () => _toggle(_prefBoxes, !_showBoxes), icon: LucideIcons.package),
          chip('بلا صندوق', _showLoose, () => _toggle(_prefLoose, !_showLoose), icon: LucideIcons.circleDashed),
        ]),
      ),
    );
  }

  Widget _legend() {
    Widget dot(Color c, String t, {bool ring = false}) => Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: ring ? Colors.transparent : c,
              borderRadius: BorderRadius.circular(FiberMapModel.slotRadius),
              border: ring ? Border.all(color: c, width: 1.5) : null,
            ),
          ),
          const SizedBox(width: 4),
          Text(t, style: AppType.micro(color: AppColors.textMid)),
        ]);
    final c = FiberMapColors.of();
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.sm, Sp.lg, Sp.sm),
      child: SafeArea(
        top: false,
        child: Wrap(spacing: Sp.md, runSpacing: 4, alignment: WrapAlignment.center, children: [
          dot(c.ok, 'متّصل'),
          dot(c.down, 'مفصول'),
          dot(c.free, 'منفذ فارغ', ring: true),
          dot(c.outage, 'عطل'),
          Text('اسحب وكبّر · اضغط منفذاً أو صندوقاً لتفتحه', style: AppType.micro(color: AppColors.textLow)),
        ]),
      ),
    );
  }
}

/// ألوان الرسم من سمة التطبيق الحاليّة (نهاريّ/ليليّ).
class FiberMapColors {
  const FiberMapColors({
    required this.surface,
    required this.border,
    required this.text,
    required this.muted,
    required this.ok,
    required this.down,
    required this.warn,
    required this.outage,
    required this.free,
    required this.line,
    required this.brand,
    required this.onBrand,
  });

  final Color surface, border, text, muted, ok, down, warn, outage, free, line, brand, onBrand;

  factory FiberMapColors.of() => FiberMapColors(
        surface: AppColors.surface,
        border: AppColors.border,
        text: AppColors.textHi,
        muted: AppColors.textMid,
        ok: AppColors.successFill,
        down: AppColors.errorFill,
        warn: AppTone.warning.fill,
        outage: AppColors.error,
        free: AppColors.borderStrong,
        line: AppColors.borderStrong,
        brand: AppColors.brand,
        onBrand: AppColors.onBrand,
      );

  Color stateColor(FiberMapState s) => switch (s) {
        FiberMapState.ok => ok,
        FiberMapState.partial => warn,
        FiberMapState.down => down,
        FiberMapState.outage => outage,
        FiberMapState.empty || FiberMapState.unknown => line,
      };
}

/// يرسم المخطّط: الخطوط أوّلاً (بلون حالة ما تحتها، والأسمك للأعلى)، ثمّ العقد بعناوينها وأرقامها ومنافذها.
class FiberMapPainter extends CustomPainter {
  FiberMapPainter(this.model, this.c, this.dir);

  final FiberMapModel model;
  final FiberMapColors c;
  final TextDirection dir;

  @override
  void paint(Canvas canvas, Size size) {
    for (final n in model.nodes) {
      if (n.children.isNotEmpty) _edges(canvas, n);
    }
    for (final n in model.nodes) {
      _node(canvas, n);
    }
  }

  Color _edgeColor(FiberMapState s) => s == FiberMapState.empty || s == FiberMapState.unknown ? c.line : c.stateColor(s);

  /// جذعٌ من الأب بلونه ⇐ مسطرةٌ محايدة بعرض أبنائه ⇐ نزلةٌ لكلّ ابنٍ بلون حاله. (خطوطٌ متراكبة بألوانٍ مختلفة كانت تأخذ لون
  /// آخر فرعٍ يُرسم — رماديّ منفذٍ مطفأ فوق منفذٍ شغّال.)
  void _edges(Canvas canvas, FiberMapNode a) {
    Paint pen(Color color, double w) => Paint()
      ..color = color
      ..strokeWidth = w
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final kids = a.children;
    final top = a.y + a.h;
    final midY = top + (kids.first.y - top) / 2;
    final w = switch (kids.first.kind) { FiberMapKind.olt => 4.0, FiberMapKind.pon => 3.0, _ => 2.0 };
    canvas.drawLine(Offset(a.cx, top), Offset(a.cx, midY), pen(_edgeColor(a.state), w));
    if (kids.length > 1) {
      final xs = [for (final k in kids) k.cx]..sort();
      canvas.drawLine(Offset(xs.first, midY), Offset(xs.last, midY), pen(c.line, w - 0.5));
    }
    for (final k in kids) {
      canvas.drawLine(Offset(k.cx, midY), Offset(k.cx, k.y), pen(_edgeColor(k.state), w));
      // الترفك على نزلة الأولت/المنفذ: ↓ نحو المشتركين.
      if ((k.kind == FiberMapKind.olt || k.kind == FiberMapKind.pon) && k.downBps != null) {
        _label(canvas, '↓ ${_bps(k.downBps!)}', Offset(k.cx, midY + (k.y - midY) / 2), c.muted, 10.5, bold: true, bg: c.surface, ltr: true);
      }
    }
  }

  void _node(Canvas canvas, FiberMapNode n) {
    final r = RRect.fromRectAndRadius(Rect.fromLTWH(n.x, n.y, n.w, n.h), const Radius.circular(R.md));
    final core = n.kind == FiberMapKind.core;
    final olt = n.kind == FiberMapKind.olt;
    final fill = Paint()..color = core || olt ? c.brand : c.surface;
    canvas.drawRRect(r, fill);
    final stroke = Paint()
      ..color = core || olt ? c.brand : c.stateColor(n.state)
      ..style = PaintingStyle.stroke
      ..strokeWidth = n.state == FiberMapState.outage ? 2.4 : 1.4;
    if (n.kind == FiberMapKind.loose) {
      _dashed(canvas, r, stroke);
    } else {
      canvas.drawRRect(r, stroke);
    }
    final ink = core || olt ? c.onBrand : c.text;
    final soft = core || olt ? c.onBrand.withValues(alpha: 0.82) : c.muted;
    const padX = 10.0;
    // السطر الأوّل: العنوان + «متّصل/الكلّ».
    final count = n.total == 0 && n.kind != FiberMapKind.core ? '' : '${n.online}/${n.total}';
    final countW = count.isEmpty ? 0.0 : _measure(count, 11.5, bold: true) + 12;
    // العنوان من جهة البداية، والرقم عند النهاية — لا يتراكبان.
    final rtl = dir == TextDirection.rtl;
    final titleW = n.w - padX * 2 - (countW == 0 ? 0 : countW + 6);
    final titleLeft = rtl ? n.x + n.w - padX - titleW : n.x + padX;
    _text(canvas, n.title, Rect.fromLTWH(titleLeft, n.y + 8, titleW, 18), ink, 12.5, bold: true);
    if (count.isNotEmpty) {
      final pill = Rect.fromLTWH(rtl ? n.x + 8 : n.x + n.w - 8 - countW, n.y + 8, countW, 18);
      canvas.drawRRect(RRect.fromRectAndRadius(pill, Radius.circular(pill.height / 2)),
          Paint()..color = (core || olt ? c.onBrand.withValues(alpha: 0.18) : c.stateColor(n.state).withValues(alpha: 0.16)));
      _text(canvas, count, pill, core || olt ? c.onBrand : c.text, 11.5, bold: true, center: true, ltr: true);
    }
    // السطر الثاني: الوصف.
    if (n.sub != null) _text(canvas, n.sub!, Rect.fromLTWH(n.x + padX, n.y + 29, n.w - padX * 2, 16), soft, 10.5);
    // السطر الثالث للسيرفر/الأولت: ترفك الأبلنك، من اليسار لليمين كما يُقرأ.
    if ((core || olt) && n.downBps != null) {
      final t = '↓ ${_bps(n.downBps!)}${n.upBps != null ? '    ↑ ${_bps(n.upBps!)}' : ''}';
      _text(canvas, t, Rect.fromLTWH(n.x + padX, n.y + 48, n.w - padX * 2, 16), ink, 11, bold: true, center: true, ltr: true);
    }
    // المنافذ: صفوفٌ من ٨.
    if (n.slots.isNotEmpty) {
      const s = FiberMapModel.slotSize;
      const g = FiberMapModel.slotGap;
      const per = FiberMapModel.slotsPerRow;
      const rowW = per * s + (per - 1) * g;
      final startX = n.x + (n.w - rowW) / 2;
      final startY = n.y + (core || olt ? FiberMapModel.headH : FiberMapModel.baseH) - 4;
      for (var i = 0; i < n.slots.length; i++) {
        final row = i ~/ per;
        final col = i % per;
        final x = dir == TextDirection.rtl ? startX + rowW - (col + 1) * s - col * g : startX + col * (s + g);
        final rect = RRect.fromRectAndRadius(Rect.fromLTWH(x, startY + row * (s + g), s, s), const Radius.circular(FiberMapModel.slotRadius));
        switch (n.slots[i]) {
          case FiberMapSlot.up:
            canvas.drawRRect(rect, Paint()..color = c.ok);
          case FiberMapSlot.down:
            canvas.drawRRect(rect, Paint()..color = c.down);
          case FiberMapSlot.free:
            canvas.drawRRect(rect, Paint()
              ..color = c.free
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.2);
        }
      }
      if (n.moreSlots > 0) {
        _label(canvas, '+${n.moreSlots}', Offset(n.cx, n.y + n.h - 6), c.muted, 10, bg: c.surface, ltr: true);
      }
    }
  }

  void _dashed(Canvas canvas, RRect r, Paint p) {
    final path = Path()..addRRect(r);
    for (final m in path.computeMetrics()) {
      var d = 0.0;
      while (d < m.length) {
        canvas.drawPath(m.extractPath(d, d + 6), p);
        d += 11;
      }
    }
  }

  TextPainter _tp(String t, double size, Color color, {bool bold = false, double? maxW, bool ltr = false}) {
    final tp = TextPainter(
      text: TextSpan(
        text: t,
        style: TextStyle(fontFamily: AppType.family, fontSize: size, color: color, fontWeight: bold ? FontWeight.w700 : FontWeight.w500, height: 1.2),
      ),
      // الأرقام بوحداتها (Mbps، ↓/↑، ٣/٨) من اليسار لليمين — في سياقٍ عربيّ تنقلب («Mbps 118 ↓»).
      textDirection: ltr ? TextDirection.ltr : dir,
      maxLines: 1,
      ellipsis: '…',
    );
    tp.layout(maxWidth: maxW ?? double.infinity);
    return tp;
  }

  double _measure(String t, double size, {bool bold = false}) => _tp(t, size, c.text, bold: bold).width;

  void _text(Canvas canvas, String t, Rect box, Color color, double size, {bool bold = false, bool center = false, bool ltr = false}) {
    final tp = _tp(t, size, color, bold: bold, maxW: box.width, ltr: ltr);
    final dx = center ? box.left + (box.width - tp.width) / 2 : (dir == TextDirection.rtl && !ltr ? box.right - tp.width : box.left);
    tp.paint(canvas, Offset(dx, box.top + (box.height - tp.height) / 2));
  }

  void _label(Canvas canvas, String t, Offset center, Color color, double size, {bool bold = false, Color? bg, bool ltr = false}) {
    final tp = _tp(t, size, color, bold: bold, ltr: ltr);
    final rect = Rect.fromCenter(center: center, width: tp.width + 10, height: tp.height + 4);
    if (bg != null) canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(6)), Paint()..color = bg);
    tp.paint(canvas, Offset(rect.left + 5, rect.top + 2));
  }

  static String _bps(double v) {
    if (v >= 1e9) return '${(v / 1e9).toStringAsFixed(1)} Gbps';
    if (v >= 1e6) return '${(v / 1e6).toStringAsFixed(v >= 1e8 ? 0 : 1)} Mbps';
    if (v >= 1e3) return '${(v / 1e3).round()} Kbps';
    return '${v.round()} bps';
  }

  @override
  bool shouldRepaint(covariant FiberMapPainter old) => true;
}
