import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:share_plus/share_plus.dart';

import '../../../api/bdcom_epon.dart';
import '../../../api/vsol_olt_api.dart';
import '../../../core/platform/desktop_layout.dart';
import '../../../core/util/bidi.dart';
import '../../../core/widgets/app_sheet.dart';
import '../../../core/widgets/design_sheet.dart';
import '../../../core/widgets/sheet_scaffold.dart';
import '../../../services/fiber/fiber_band.dart';
import '../../../services/fiber/fiber_monitor.dart';
import '../../../services/fiber/fiber_onu.dart';
import '../../../services/fiber/fiber_store.dart';
import '../../../services/fiber/fiber_text.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';
import '../../desktop/desk_widgets.dart';
import 'fiber_search_screen.dart';
import 'fiber_sheets.dart';
import 'fiber_widgets.dart';

/// «وضع الفنّي» عند الصندوق: ضوء جهازٍ واحد كلّ ثانيتين، وقبل/بعد التنظيف، ورسم آخر دقيقتين، وصفّارةٌ تسرع كلّما قوي
/// الضوء — الفنّي يشتغل وعينه على الوصلة لا على الشاشة.
class FiberTechScreen extends StatefulWidget {
  const FiberTechScreen({super.key, required this.monitor, this.onuKey});

  final FiberMonitor monitor;
  final String? onuKey;

  /// للاختبار: صوت/اهتزاز الصفّارة.
  @visibleForTesting
  static void Function() tick = _systemTick;

  static void _systemTick() {
    SystemSound.play(SystemSoundType.click);
    HapticFeedback.selectionClick();
  }

  /// للاختبار: المشاركة (لا قناة منصّة في `flutter test`). [origin] لآيباد.
  @visibleForTesting
  static Future<void> Function(String text, Rect origin) shareText = _systemShare;

  static Future<void> _systemShare(String text, Rect origin) =>
      // ignore: deprecated_member_use
      Share.share(text, sharePositionOrigin: origin);

  /// مدى المقياس: ‎-32 يساراً إلى ‎-12 يميناً (ما فوقه قويّ زيادة ويقف بآخره).
  static const gaugeLo = -32.0, gaugeHi = -12.0;

  /// فترة الصفّارة: كلّما قوي الضوء قصرت — ‎-32 ⇒ 1.4ث، ‎-12 ⇒ 0.15ث.
  static Duration beepGap(double rx) {
    final t = ((rx - gaugeLo) / (gaugeHi - gaugeLo)).clamp(0.0, 1.0);
    return Duration(milliseconds: (1400 - 1250 * t).round());
  }

  @override
  State<FiberTechScreen> createState() => _FiberTechScreenState();
}

class _Sample {
  const _Sample(this.at, this.rx, {this.offline = false});
  final DateTime at;
  final double? rx;
  final bool offline;
}

class _FiberTechScreenState extends State<FiberTechScreen> with SingleTickerProviderStateMixin {
  static const _every = Duration(seconds: 2);
  static const _window = Duration(minutes: 2);

  FiberMonitor get _m => widget.monitor;
  String? _key;
  final List<_Sample> _samples = [];
  ({double rx, DateTime at})? _before;
  bool? _online;
  BdcomOnuReading? _last;
  DateTime? _lastAt;
  DateTime? _offlineSince;
  int _fails = 0;
  bool _polling = false;
  Timer? _timer;
  bool _beep = false;
  Timer? _beepTimer;
  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600));

  @override
  void initState() {
    super.initState();
    _m
      ..addListener(_changed)
      ..acquire();
    FiberStore.layout.addListener(_changed);
    _select(widget.onuKey);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _beepTimer?.cancel();
    _pulse.dispose();
    _m
      ..removeListener(_changed)
      ..release();
    FiberStore.layout.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (!mounted) return;
    // الجهاز وصل من أوّل قراءةٍ للأولت بعد الفتح: ضوءه الآن هو «قبل»، والقراءة الحيّة تبدأ بلا انتظار.
    final o = _onu;
    if (o != null) {
      _online ??= o.online;
      if (_before == null && o.rx != null) _before = (rx: o.rx!, at: o.onu.readingAt ?? FiberMonitor.clock());
      if (_samples.isEmpty && !_polling) unawaited(_poll());
    }
    setState(() {});
  }

  FiberOnuLive? get _onu {
    final k = _key;
    if (k == null) return null;
    for (final o in _m.onus) {
      if (o.key == k) return o;
    }
    return null;
  }

  /// [before] = ضوءه قبل أن يُفصل («التقط بالفصل») — المراقب لا يعرفه بعد السقوط.
  void _select(String? key, {({double rx, DateTime at})? before}) {
    _timer?.cancel();
    _samples.clear();
    _before = null;
    _online = null;
    _last = null;
    _lastAt = null;
    _offlineSince = null;
    _fails = 0;
    _key = key;
    if (key == null) return;
    _m.techRecent
      ..remove(key)
      ..insert(0, key);
    if (_m.techRecent.length > 6) _m.techRecent.removeRange(6, _m.techRecent.length);
    // البذرة: آخر ضوءٍ قرأه المراقب — «قبل» من أوّل لحظة.
    final o = _onu;
    if (o != null) {
      _online = o.online;
      if (!o.online) _offlineSince = o.changedAt;
      if (o.rx != null) _before = (rx: o.rx!, at: o.onu.readingAt ?? FiberMonitor.clock());
    }
    if (before != null) _before = before;
    _timer = Timer.periodic(_every, (_) => _poll());
    unawaited(_poll());
  }

  Future<void> _poll() async {
    final o = _onu;
    if (o == null || _polling || !mounted) return;
    _polling = true;
    try {
      final r = await _m.probeOne(o.onu);
      final now = FiberMonitor.clock();
      final rx = r.reading?.rxDbm;
      final ok = FiberBands.plausible(rx);
      if (r.online == false && _online != false) _offlineSince = now;
      if (r.online == true) _offlineSince = null;
      if (r.online != null) _online = r.online;
      if (r.reading != null) {
        _last = r.reading;
        _lastAt = now;
      }
      _fails = r.online == null && r.reading == null ? _fails + 1 : 0;
      _samples.add(_Sample(now, r.online == false ? null : (ok ? rx : null), offline: r.online == false));
      _samples.removeWhere((s) => now.difference(s.at) > _window);
      if (_before == null && ok) _before = (rx: rx!, at: now);
    } catch (_) {
      _fails++;
    } finally {
      _polling = false;
      if (mounted) setState(() {});
    }
  }

  /// آخر ضوءٍ صالح خلال ٦ ثوانٍ — أقدم منه لا يُعرض «الآن».
  double? get _now {
    if (_online == false) return null;
    for (final s in _samples.reversed) {
      if (FiberMonitor.clock().difference(s.at) > const Duration(seconds: 6)) break;
      if (s.rx != null) return s.rx;
    }
    final o = _onu;
    return _samples.isEmpty && o != null && o.online ? o.rx : null;
  }

  void _toggleBeep() {
    setState(() => _beep = !_beep);
    _beepTimer?.cancel();
    if (_beep) _beepLoop();
  }

  void _beepLoop() {
    _beepTimer?.cancel();
    if (!_beep || !mounted) return;
    final v = _now;
    if (v == null) {
      // بلا ضوء ⇒ صامتة، وتعود وحدها أوّل ما يرجع.
      _beepTimer = Timer(const Duration(seconds: 1), _beepLoop);
      return;
    }
    FiberTechScreen.tick();
    _beepTimer = Timer(FiberTechScreen.beepGap(v), _beepLoop);
  }

  Future<void> _pick() async {
    final key = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => FiberSearchScreen(monitor: _m, pick: true)),
    );
    if (key != null && mounted) setState(() => _select(key));
  }

  /// «التقط بالفصل»: الفنّي يفصل ليف الجهاز اللي قدّامه ونختاره وحدنا — وضوءه قبل الفصل يصير «قبل».
  Future<void> _catch() async {
    // اللقطة قبل الفصل: بعده يصير الجهاز مفصولاً بلا ضوء.
    final snap = {
      for (final o in _m.onus)
        if (o.rx != null) o.key: (rx: o.rx!, at: o.onu.readingAt ?? FiberMonitor.clock()),
    };
    final key = await showAppSheet<String>(
      barrierColor: AppColors.scrim,
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(R.card))),
      builder: (_) => _CatchSheet(monitor: _m),
    );
    if (key != null && mounted) setState(() => _select(key, before: snap[key]));
  }

  String _shareText(FiberOnuLive o) {
    final layout = FiberStore.layout.value;
    final rec = layout.recordFor(_m.oltId, o.key, o.ident);
    final box = rec?.boxId == null ? null : layout.boxes[rec!.boxId];
    final now = _now;
    String line(String label, double v, DateTime at) =>
        '$label ${FiberText.clock(at)}: ${v.toStringAsFixed(1)} dBm (${FiberBands.label(FiberBands.of(v)!)})';
    final b = _before;
    return [
      '${fiberOnuTitle(layout, _m.oltId, o)} · ${o.display}${box == null ? '' : ' · ${box.name}'}',
      if (b != null) line('قبل', b.rx, b.at),
      if (now != null) line('الآن', now, FiberMonitor.clock()) else 'الآن: مفصول',
      if (b != null && now != null) _deltaWords(now - b.rx, now),
      _m.device.name,
    ].join('\n');
  }

  static String _deltaWords(double d, double now) {
    final band = FiberBands.label(FiberBands.of(now)!);
    if (d.abs() < 0.3) return 'بنفس مستواه ($band)';
    // «4.5 dB» معزولةً — داخل الجملة العربيّة تنقلب «dB 4.5» بلا عزل.
    return d > 0 ? 'تحسّن ${iso('${d.toStringAsFixed(1)} dB')}، صار $band' : 'نزل ${iso('${(-d).toStringAsFixed(1)} dB')}، صار $band';
  }

  Future<void> _share(FiberOnuLive o) async {
    final text = _shareText(o);
    if (DesktopScope.of(context)) {
      await Clipboard.setData(ClipboardData(text: text));
      if (mounted) showSheetSnack(context, 'نُسخت القراءة — الصقها بالمحادثة');
      return;
    }
    Rect origin = Rect.zero;
    final box = context.findRenderObject() as RenderBox?;
    if (box != null && box.hasSize) origin = box.localToGlobal(Offset.zero) & box.size;
    await FiberTechScreen.shareText(text, origin);
  }

  bool get _phone => !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

  @override
  Widget build(BuildContext context) {
    final o = _onu;
    final layout = FiberStore.layout.value;
    final rec = o == null ? null : layout.recordFor(_m.oltId, o.key, o.ident);
    final box = rec?.boxId == null ? null : layout.boxes[rec!.boxId];
    final sub = o == null
        ? 'اختر الجهاز اللي تشتغل عليه'
        : {fiberOnuTitle(layout, _m.oltId, o), o.display, if (box != null) box.name}.join(' · ');
    final wide = fiberWide(context);
    final live = o != null && _online != false && _fails < 3;
    if (live && !MediaQuery.of(context).disableAnimations) {
      if (!_pulse.isAnimating) _pulse.repeat();
    } else if (_pulse.isAnimating) {
      _pulse.stop();
    }
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: deskPageBar(
        context,
        title: 'وضع الفنّي',
        subtitle: sub,
        actions: [if (o != null) Padding(padding: const EdgeInsetsDirectional.only(end: Sp.md), child: Center(child: _status(o)))],
        mobile: AppBar(
          backgroundColor: AppColors.surface,
          foregroundColor: AppColors.textHi,
          elevation: 0,
          leading: IconButton(icon: const Icon(LucideIcons.arrowRight, size: 20), onPressed: () => Navigator.pop(context)),
          title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('وضع الفنّي'),
            Text(iso(sub), style: AppType.muted(color: AppColors.textMid), maxLines: 1, overflow: TextOverflow.ellipsis),
          ]),
          actions: [if (o != null) Padding(padding: const EdgeInsetsDirectional.only(end: Sp.md), child: Center(child: _status(o)))],
        ),
      ),
      body: FiberPage(
        maxWidth: 980,
        children: [
          _picker(),
          if (_key != null && o == null)
            const FiberNotice(text: 'هذا الجهاز ما عاد يظهر على الأولت — اختر غيره.', tone: AppTone.warning),
          if (o == null && _key == null) _empty(),
          if (o != null && _fails >= 3)
            FiberNotice(text: 'الأولت ما يجاوب على القراءة — نعيد كلّ ثانيتين.', tone: AppTone.danger, icon: LucideIcons.wifiOff, onRetry: _poll),
          if (o != null)
            if (wide)
              Padding(
                padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, 0),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(child: Column(children: [_gaugeCard(o), const SizedBox(height: Sp.md), _beforeAfter()])),
                  const SizedBox(width: Sp.md),
                  Expanded(
                    child: Column(children: [
                      _chartCard(),
                      const SizedBox(height: Sp.md),
                      _tiles(o),
                      const SizedBox(height: Sp.md),
                      _actions(o),
                    ]),
                  ),
                ]),
              )
            else ...[
              _pad(_gaugeCard(o)),
              _pad(_beforeAfter()),
              _pad(_chartCard()),
              _pad(_tiles(o)),
              _pad(_actions(o)),
            ],
        ],
      ),
    );
  }

  Widget _pad(Widget w) => Padding(padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, 0), child: w);

  Widget _status(FiberOnuLive o) {
    if (_online == false) return const FiberPill('مفصول', tone: AppTone.danger, dot: true);
    if (_fails >= 3) return const FiberPill('ما يجاوب', tone: AppTone.warning, dot: true);
    return Semantics(
      label: 'مباشر',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: Sp.sm, vertical: 3),
        decoration: BoxDecoration(color: AppTone.success.softBg, borderRadius: BorderRadius.circular(R.pill)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          AnimatedBuilder(
            animation: _pulse,
            builder: (_, __) => Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: AppColors.success,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.success.withValues(alpha: 0.5 * (1 - _pulse.value)),
                    spreadRadius: 7 * _pulse.value,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text('مباشر', style: AppType.pillBold(color: AppTone.success.onSoft)),
        ]),
      ),
    );
  }

  Widget _picker() {
    final layout = FiberStore.layout.value;
    final byKey = {for (final o in _m.onus) o.key: o};
    final recent = [
      for (final k in _m.techRecent)
        if (k != _key && byKey[k] != null) byKey[k]!,
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            child: Material(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(R.md),
              child: InkWell(
                borderRadius: BorderRadius.circular(R.md),
                onTap: _pick,
                child: Container(
                  height: 46,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(R.md), border: Border.all(color: AppColors.borderStrong)),
                  child: Row(children: [
                    Icon(LucideIcons.search, size: 18, color: AppColors.textMid),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        iso(_key == null ? 'اختر الجهاز: يوزر، اسم، ماك أو SN' : 'غيّر الجهاز: يوزر، اسم، ماك أو SN'),
                        style: AppType.body(color: AppColors.textMid),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ]),
                ),
              ),
            ),
          ),
          const SizedBox(width: Sp.sm),
          Tooltip(
            message: 'التقط بالفصل: افصل ليف الجهاز ونعرفه',
            child: SizedBox(
              width: 46,
              height: 46,
              child: IconButton.filled(
                onPressed: _m.stats == null ? null : _catch,
                style: IconButton.styleFrom(
                  backgroundColor: AppColors.brand,
                  foregroundColor: AppColors.onBrand,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(R.md)),
                ),
                icon: const Icon(LucideIcons.unplug, size: 20),
              ),
            ),
          ),
        ]),
        if (recent.isNotEmpty) ...[
          const SizedBox(height: Sp.sm),
          SizedBox(
            height: 36,
            child: ListView(scrollDirection: Axis.horizontal, children: [
              Center(child: Text('آخر الأجهزة', style: AppType.muted(color: AppColors.textMid))),
              const SizedBox(width: Sp.sm),
              for (final o in recent)
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 6),
                  child: ActionChip(
                    avatar: Container(width: 8, height: 8, decoration: BoxDecoration(color: fiberOnuDot(o), shape: BoxShape.circle)),
                    label: Text(iso({fiberOnuTitle(layout, _m.oltId, o), o.display}.join(' · ')), maxLines: 1, overflow: TextOverflow.ellipsis),
                    labelStyle: AppType.body(color: AppColors.textBody),
                    backgroundColor: AppColors.surface,
                    side: BorderSide(color: AppColors.border),
                    onPressed: () => setState(() => _select(o.key)),
                  ),
                ),
            ]),
          ),
        ],
      ]),
    );
  }

  Widget _empty() => Padding(
        padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, 0),
        child: FiberCard(
          padding: const EdgeInsets.all(Sp.xl),
          child: Column(children: [
            const FiberIconBox(LucideIcons.wrench, size: 48),
            const SizedBox(height: Sp.md),
            Text('ضوءٌ حيّ لجهازٍ واحد', style: AppType.cardTitleBold(color: AppColors.textHi)),
            const SizedBox(height: Sp.xs),
            Text(
              'اختر جهاز المشترك اللي تشتغل عليه، أو دوس «التقط بالفصل» وافصل ليفه — ونقرأ ضوءه كلّ ثانيتين وأنت عند الصندوق: قبل التنظيف وبعده، وصفّارة تسرع كلّما قوي.',
              textAlign: TextAlign.center,
              style: AppType.body(color: AppColors.textMid),
            ),
          ]),
        ),
      );

  Widget _gaugeCard(FiberOnuLive o) {
    final v = _now;
    final band = FiberBands.of(v);
    final b = _before?.rx;
    final aria = v == null
        ? (_online == false ? 'الجهاز مفصول الآن' : 'يقرأ الضوء')
        : 'الضوء الآن سالب ${v.abs().toStringAsFixed(1)}، ${FiberBands.label(band!)}${b == null ? '' : '، وكان قبل سالب ${b.abs().toStringAsFixed(1)}'}';
    return FiberCard(
      padding: const EdgeInsets.all(Sp.lg),
      child: Column(children: [
        Semantics(
          label: aria,
          excludeSemantics: true,
          child: SizedBox(
            width: 300,
            height: 170,
            child: CustomPaint(
              painter: _GaugePainter(
                value: v,
                before: b,
                red: AppColors.errorFill,
                amber: AppTone.warning.fill,
                green: AppColors.chartLine,
                needle: AppColors.textHi,
                label: AppColors.textMid,
                surface: AppColors.surface,
              ),
            ),
          ),
        ),
        Transform.translate(
          offset: const Offset(0, -6),
          child: v == null
              ? Text(_online == false ? 'مفصول' : 'يقرأ…',
                  style: _big(_online == false ? AppColors.error : AppColors.textMid))
              : Directionality(
                  textDirection: TextDirection.ltr,
                  child: Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
                    Text(v.toStringAsFixed(1), style: _big(AppColors.textHi)),
                    const SizedBox(width: 6),
                    Text('dBm', style: AppType.cardTitle(color: AppColors.textMid)),
                  ]),
                ),
        ),
        Wrap(alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center, spacing: Sp.sm, runSpacing: 4, children: [
          if (band != null) FiberPill(FiberBands.label(band), tone: FiberBands.tone(v)),
          Text(
            _online == false
                ? (_offlineSince == null ? 'ننتظر يرجع — نقرأ كلّ ثانيتين' : 'مفصول من ${FiberText.clock(_offlineSince!, seconds: true)} — ننتظر يرجع')
                : 'يتحدّث كلّ ثانيتين${b == null ? '' : ' · الدائرة = قبل'}',
            style: AppType.muted(color: AppColors.textMid),
          ),
        ]),
      ]),
    );
  }

  static TextStyle _big(Color c) =>
      TextStyle(fontFamily: AppType.family, fontSize: 30, fontWeight: FontWeight.w700, height: 1.15, color: c);

  Widget _beforeAfter() {
    final b = _before;
    final v = _now;
    if (b == null) return const SizedBox.shrink();
    Widget cell(String label, double? val, {required bool after}) {
      final tone = val == null ? AppTone.neutral : FiberBands.tone(val);
      return Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: 10),
          decoration: BoxDecoration(color: tone.softBg, borderRadius: BorderRadius.circular(R.md)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(iso(label), style: AppType.label(color: tone.onSoft), maxLines: 1, overflow: TextOverflow.ellipsis),
            Text(iso(val == null ? (after && _online == false ? 'مفصول' : '—') : val.toStringAsFixed(1)),
                style: AppType.title(color: val == null ? AppColors.textMid : tone.onSoft), maxLines: 1),
          ]),
        ),
      );
    }

    final d = v == null ? null : v - b.rx;
    final dTone = d == null || d.abs() < 0.3 ? AppTone.neutral : (d > 0 ? AppTone.success : AppTone.danger);
    return FiberCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          cell('قبل · ${FiberText.clock(b.at)}', b.rx, after: false),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Sp.sm),
            child: Icon(LucideIcons.arrowLeft, size: 22, color: AppColors.textMid),
          ),
          cell('الآن', v, after: true),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: Text(
              iso(d == null ? (_online == false ? 'الجهاز مفصول — نقارن أوّل ما يرجع' : 'ننتظر قراءة') : _deltaWords(d, v!)),
              style: AppType.bodyBold(color: dTone == AppTone.neutral ? AppColors.textBody : dTone.onSoft),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: Sp.sm),
          OutlinedButton(
            onPressed: v == null ? null : () => setState(() => _before = (rx: v, at: FiberMonitor.clock())),
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
            child: const Text('ثبّت الحالي كـ«قبل»'),
          ),
        ]),
      ]),
    );
  }

  Widget _chartCard() {
    final now = FiberMonitor.clock();
    final gap = _samples.where((s) => s.offline).toList();
    final gapLabel = gap.isEmpty ? null : 'انفصل ${FiberText.clock(gap.first.at, seconds: true)}';
    final first = _samples.where((s) => s.rx != null).map((s) => s.rx!).toList();
    return FiberCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('آخر دقيقتين', style: AppType.cardTitleBold(color: AppColors.textHi)),
        const SizedBox(height: Sp.sm),
        Semantics(
          label: first.isEmpty
              ? 'لا قراءات بعد'
              : 'الضوء بآخر دقيقتين بين سالب ${first.reduce(math.max).abs().toStringAsFixed(1)} وسالب ${first.reduce(math.min).abs().toStringAsFixed(1)}${gap.isEmpty ? '' : '، وانفصل بينها'}',
          excludeSemantics: true,
          child: SizedBox(
            height: 90,
            child: CustomPaint(
              size: Size.infinite,
              painter: _TracePainter(
                samples: List.of(_samples),
                now: now,
                window: _window,
                red: AppColors.errorFill,
                amber: AppTone.warning.fill,
                green: AppColors.chartLine,
                gap: AppColors.surfaceSunken,
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Directionality(
          textDirection: TextDirection.ltr,
          child: Row(children: [
            Text('قبل دقيقتين', style: AppType.muted(color: AppColors.textMid)),
            const Spacer(),
            if (gapLabel != null) Text(gapLabel, style: AppType.muted(color: AppColors.textMid)),
            const Spacer(),
            Text('الآن', style: AppType.muted(color: AppColors.textMid)),
          ]),
        ),
      ]),
    );
  }

  Widget _tiles(FiberOnuLive o) {
    final r = _online == false ? null : (_last ?? o.onu.reading);
    String fmt(double? v, String unit, int digits) => v == null ? '—' : '${v.toStringAsFixed(digits)}$unit';
    final since = _online == false ? _offlineSince : o.changedAt;
    final tiles = <(String, String)>[
      ('الإرسال', fmt(r?.txDbm, ' dBm', 1)),
      ('الحرارة', fmt(r?.tempC, '°', 0)),
      ('الفولتية', fmt(r?.voltV, ' V', 2)),
      if (o.distanceM != null)
        ('المسافة من الأولت', o.distanceM! >= 1000 ? '${(o.distanceM! / 1000).toStringAsFixed(1)} كم' : '${o.distanceM} م')
      else
        (_online == false ? 'مفصول منذ' : 'متّصل منذ', since == null ? '—' : FiberText.duration(FiberMonitor.clock().difference(since))),
    ];
    Widget tile((String, String) t) => Container(
          padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(R.md),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(t.$1, style: AppType.label(color: AppColors.textMid), maxLines: 1, overflow: TextOverflow.ellipsis),
            Text(iso(t.$2), style: AppType.cardTitleBold(color: AppColors.textHi), maxLines: 1, overflow: TextOverflow.ellipsis),
          ]),
        );
    return Column(children: [
      Row(children: [Expanded(child: tile(tiles[0])), const SizedBox(width: Sp.sm), Expanded(child: tile(tiles[1]))]),
      const SizedBox(height: Sp.sm),
      Row(children: [Expanded(child: tile(tiles[2])), const SizedBox(width: Sp.sm), Expanded(child: tile(tiles[3]))]),
      if (_lastAt != null && r != null)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(iso('آخر قراءة ${FiberText.clock(_lastAt!, seconds: true)}'),
              style: AppType.micro(color: AppColors.textMid), textAlign: TextAlign.end),
        ),
    ]);
  }

  Widget _actions(FiberOnuLive o) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (_phone) ...[
          Semantics(
            button: true,
            toggled: _beep,
            child: Material(
              color: _beep ? AppTone.brand.softBg : AppColors.surface,
              borderRadius: BorderRadius.circular(R.lg),
              child: InkWell(
                borderRadius: BorderRadius.circular(R.lg),
                onTap: _toggleBeep,
                child: Container(
                  constraints: const BoxConstraints(minHeight: 60),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(R.lg),
                    border: Border.all(color: _beep ? AppTone.brand.softBorder : AppColors.border),
                  ),
                  child: Row(children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(color: _beep ? AppColors.brand : AppTone.brand.softBg, borderRadius: BorderRadius.circular(R.sm)),
                      child: Icon(_beep ? LucideIcons.volume2 : LucideIcons.volumeX, size: 19, color: _beep ? AppColors.onBrand : AppColors.brandOnSoft),
                    ),
                    const SizedBox(width: Sp.md),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('صفّارة حسب الضوء · ${_beep ? 'شغّالة' : 'مطفأة'}', style: AppType.rowValue(color: AppColors.textHi)),
                        Text('تسرع كلّما قوي الضوء، تشتغل وعينك على الوصلة', style: AppType.muted(color: AppColors.textMid)),
                      ]),
                    ),
                  ]),
                ),
              ),
            ),
          ),
          const SizedBox(height: Sp.sm),
        ],
        FilledButton.icon(
          onPressed: _before == null && _now == null ? null : () => _share(o),
          icon: Icon(DesktopScope.of(context) ? LucideIcons.copy : LucideIcons.messageCircle, size: 17),
          label: Text(DesktopScope.of(context) ? 'انسخ القراءة: قبل وبعد' : 'شارك القراءة: قبل وبعد'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
        ),
      ]);
}

/// نافذة «التقط بالفصل»: تراقب حالة كلّ أجهزة الأولت دقيقةً ونصفاً، وأوّل جهازٍ ينفصل (أو يرجع) يُختار؛ أكثر من جهاز
/// بنفس اللحظة ⇒ يختار الفنّي.
class _CatchSheet extends StatefulWidget {
  const _CatchSheet({required this.monitor});
  final FiberMonitor monitor;

  @override
  State<_CatchSheet> createState() => _CatchSheetState();
}

class _CatchSheetState extends State<_CatchSheet> {
  static const _window = Duration(seconds: 90);
  int? _watched;
  List<({VsolOnu onu, bool nowOnline})>? _found;
  bool _timedOut = false;
  bool _closed = false;
  late DateTime _started;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _run();
  }

  @override
  void dispose() {
    _closed = true;
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _run() async {
    setState(() {
      _found = null;
      _timedOut = false;
      _watched = null;
      _started = FiberMonitor.clock();
    });
    _tick?.cancel();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    final r = await widget.monitor.catchChange(
      window: _window,
      cancelled: () => _closed,
      onStart: (n) {
        if (mounted) setState(() => _watched = n);
      },
    );
    _tick?.cancel();
    if (!mounted) return;
    if (r.length == 1) {
      Navigator.of(context).pop(widget.monitor.onus.where((o) => o.onu.ifIndex == r.first.onu.ifIndex).firstOrNull?.key ?? r.first.onu.label);
      return;
    }
    setState(() {
      _found = r;
      // بدأت المراقبة ولم يتغيّر شيء — لا «تعذّرت القراءة».
      _timedOut = r.isEmpty && _watched != null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final found = _found;
    final left = _window - FiberMonitor.clock().difference(_started);
    final m = widget.monitor;
    return DesignSheet(
      header: SheetHeaderBar(
        icon: LucideIcons.unplug,
        title: 'التقط بالفصل',
        subtitle: _watched == null ? 'يقرأ حالة أجهزة الأولت…' : 'نراقب ${FiberText.devices(_watched!)} على ${m.device.name}',
        onClose: () => Navigator.of(context).pop(),
      ),
      body: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (found == null) ...[
          Text('افصل ليف الجهاز اللي قدّامك (أو كهرباءه)', style: AppType.cardTitleBold(color: AppColors.textHi)),
          const SizedBox(height: Sp.xs),
          Text(
            'أوّل جهازٍ ينفصل نختاره وحدنا، وضوءه قبل الفصل يصير «قبل». بعدها نظّف الوصلة ورجّعها وشوف الفرق.',
            style: AppType.body(color: AppColors.textMid),
          ),
          const SizedBox(height: Sp.lg),
          ClipRRect(
            borderRadius: BorderRadius.circular(R.check),
            child: LinearProgressIndicator(
              minHeight: 6,
              value: _watched == null ? null : (1 - left.inMilliseconds / _window.inMilliseconds).clamp(0.0, 1.0),
            ),
          ),
          const SizedBox(height: Sp.sm),
          Text(
            iso(_watched == null ? 'نجهّز…' : 'ننتظر الفصل · باقي ${FiberText.duration(left.isNegative ? Duration.zero : left)}'),
            style: AppType.muted(color: AppColors.textMid),
          ),
        ] else if (found.isEmpty) ...[
          Text('ما انفصل أيّ جهاز', style: AppType.cardTitleBold(color: AppColors.textHi)),
          const SizedBox(height: Sp.xs),
          Text(
            _timedOut
                ? 'راقبنا دقيقة ونصف وما تغيّر شي. تأكّد إنّ الليف مفصول من الجهاز نفسه، أو إنّ التلفون يوصل للأولت، وأعد.'
                : 'ما قدرنا نقرأ حالة الأجهزة من الأولت الآن.',
            style: AppType.body(color: AppColors.textMid),
          ),
          const SizedBox(height: Sp.md),
          FilledButton.icon(
            onPressed: _run,
            icon: const Icon(LucideIcons.rotateCcw, size: 16),
            label: const Text('أعد المحاولة'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(46)),
          ),
        ] else ...[
          Text('تغيّرت ${FiberText.devices(found.length)} بنفس اللحظة', style: AppType.cardTitleBold(color: AppColors.textHi)),
          const SizedBox(height: Sp.xs),
          Text('إذا انقطعت هواي سوا فهذا عطل مو جهازك — اختر جهازك من بينها.', style: AppType.body(color: AppColors.textMid)),
          const SizedBox(height: Sp.sm),
          for (final f in found.take(30))
            if (m.onus.where((o) => o.onu.ifIndex == f.onu.ifIndex).firstOrNull case final o?)
              FiberOnuRow(
                oltId: m.oltId,
                onu: o,
                sub: '${o.display} · ${f.nowOnline ? 'رجع' : 'انفصل'}',
                onTap: () => Navigator.of(context).pop(o.key),
                trailing: Icon(LucideIcons.chevronLeft, size: 18, color: AppColors.textMid),
              )
            else
              Material(
                type: MaterialType.transparency,
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(iso(fiberOnuDisplay(f.onu)), style: AppType.bodyStrong(color: AppColors.textHi)),
                  subtitle: Text(f.nowOnline ? 'رجع' : 'انفصل', style: AppType.muted(color: AppColors.textMid)),
                  onTap: () => Navigator.of(context).pop(f.onu.label),
                ),
              ),
        ],
      ]),
    );
  }
}

/// نصف دائرة: أحمر حتى ‎-27، كهرمانيّ حتى ‎-25، أخضر بعده؛ والدائرة = «قبل»، والإبرة = الآن.
class _GaugePainter extends CustomPainter {
  _GaugePainter({
    required this.value,
    required this.before,
    required this.red,
    required this.amber,
    required this.green,
    required this.needle,
    required this.label,
    required this.surface,
  });

  final double? value, before;
  final Color red, amber, green, needle, label, surface;

  static double _t(double v) =>
      ((v - FiberTechScreen.gaugeLo) / (FiberTechScreen.gaugeHi - FiberTechScreen.gaugeLo)).clamp(0.0, 1.0);

  /// الزاوية من اليسار (π) إلى اليمين (0) فوق المركز.
  static double _angle(double v) => math.pi - _t(v) * math.pi;

  @override
  void paint(Canvas c, Size s) {
    final center = Offset(s.width / 2, s.height - 20);
    final r = math.min(s.width / 2 - 30, s.height - 34);
    final rect = Rect.fromCircle(center: center, radius: r);
    void arc(double from, double to, Color col) {
      final a1 = _angle(from), a2 = _angle(to);
      // canvas: الزاوية موجبة باتّجاه عقارب الساعة، وفوق المركز سالبة.
      c.drawArc(rect, -a1, a1 - a2, false, Paint()
        ..color = col
        ..style = PaintingStyle.stroke
        ..strokeWidth = 16);
    }

    arc(FiberTechScreen.gaugeLo, -27, red);
    arc(-27, -25, amber);
    arc(-25, FiberTechScreen.gaugeHi, green);

    for (final t in const [-30, -25, -20, -15]) {
      final a = _angle(t.toDouble());
      final p = center + Offset(math.cos(a), -math.sin(a)) * (r + 22);
      final tp = TextPainter(
        text: TextSpan(text: '$t', style: AppType.label(color: label)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(c, p - Offset(tp.width / 2, tp.height / 2));
    }

    final b = before;
    if (b != null) {
      final a = _angle(b);
      final p = center + Offset(math.cos(a), -math.sin(a)) * r;
      final col = b <= -27 ? red : (b <= -25 ? amber : green);
      c.drawCircle(p, 6, Paint()..color = surface);
      c.drawCircle(p, 6, Paint()
        ..color = col
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5);
    }

    final v = value;
    if (v != null) {
      final a = _angle(v);
      final tip = center + Offset(math.cos(a), -math.sin(a)) * (r * 0.8);
      c.drawLine(center, tip, Paint()
        ..color = needle
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round);
    }
    c.drawCircle(center, 8, Paint()..color = v == null ? label : needle);
  }

  @override
  bool shouldRepaint(_GaugePainter o) => o.value != value || o.before != before || o.green != green || o.needle != needle;
}

/// خطّ آخر دقيقتين: كلّ قطعةٍ بلون رتبتها، والفصل مساحةٌ غاطسة، وخطّا ‎-27/‎-25 متقطّعان.
class _TracePainter extends CustomPainter {
  _TracePainter({
    required this.samples,
    required this.now,
    required this.window,
    required this.red,
    required this.amber,
    required this.green,
    required this.gap,
  });

  final List<_Sample> samples;
  final DateTime now;
  final Duration window;
  final Color red, amber, green, gap;

  @override
  void paint(Canvas c, Size s) {
    final vals = [for (final x in samples) if (x.rx != null) x.rx!];
    final lo = math.min(-30.0, vals.isEmpty ? -30.0 : vals.reduce(math.min) - 1);
    var hi = math.max(-18.0, vals.isEmpty ? -18.0 : vals.reduce(math.max) + 1);
    if (hi - lo < 4) hi = lo + 4;
    double x(DateTime t) => s.width * (1 - now.difference(t).inMilliseconds / window.inMilliseconds).clamp(0.0, 1.0);
    double y(double v) => 4 + (s.height - 8) * (1 - (v - lo) / (hi - lo));

    // الفصل: من أوّل عيّنةٍ مفصولة إلى أوّل عيّنةٍ بعدها.
    for (var i = 0; i < samples.length; i++) {
      if (!samples[i].offline) continue;
      var j = i;
      while (j + 1 < samples.length && samples[j + 1].offline) {
        j++;
      }
      final end = j + 1 < samples.length ? samples[j + 1].at : now;
      c.drawRect(Rect.fromLTRB(x(samples[i].at), 0, x(end), s.height), Paint()..color = gap);
      i = j;
    }

    void dashed(double v, Color col) {
      final yy = y(v);
      final p = Paint()
        ..color = col
        ..strokeWidth = 1;
      for (var xx = 0.0; xx < s.width; xx += 8) {
        c.drawLine(Offset(xx, yy), Offset(math.min(xx + 4, s.width), yy), p);
      }
    }

    dashed(-27, amber);
    dashed(-25, green);

    Color col(double v) => v <= -27 ? red : (v <= -25 ? amber : green);
    for (var i = 1; i < samples.length; i++) {
      final a = samples[i - 1], b = samples[i];
      if (a.rx == null || b.rx == null) continue;
      c.drawLine(Offset(x(a.at), y(a.rx!)), Offset(x(b.at), y(b.rx!)), Paint()
        ..color = col(b.rx!)
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round);
    }
    // عيّنةٌ وحيدة بين فراغين: نقطة.
    for (var i = 0; i < samples.length; i++) {
      final v = samples[i].rx;
      if (v == null) continue;
      final lone = (i == 0 || samples[i - 1].rx == null) && (i == samples.length - 1 || samples[i + 1].rx == null);
      if (lone) c.drawCircle(Offset(x(samples[i].at), y(v)), 2.5, Paint()..color = col(v));
    }
  }

  @override
  bool shouldRepaint(_TracePainter o) => true;
}
