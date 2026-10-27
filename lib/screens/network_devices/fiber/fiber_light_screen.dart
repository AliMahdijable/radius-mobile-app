import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/util/bidi.dart';
import '../../../services/fiber/fiber_band.dart';
import '../../../services/fiber/fiber_light.dart';
import '../../../services/fiber/fiber_monitor.dart';
import '../../../services/fiber/fiber_onu.dart';
import '../../../services/fiber/fiber_store.dart';
import '../../../services/fiber/fiber_text.dart';
import '../../../services/fiber/fiber_tree.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';
import '../../desktop/desk_widgets.dart';
import 'fiber_pon_screen.dart';
import 'fiber_sheets.dart';
import 'fiber_tech_screen.dart';
import 'fiber_widgets.dart';

/// «صحّة الضوء»: توزيع القراءات، وصندوقٌ نزل كلّه سوا (خلل الصندوق)، وجهازٌ نزل فجأة وحده (وصلته)، وضعيفٌ ثابت (المسافة).
class FiberLightScreen extends StatefulWidget {
  const FiberLightScreen({super.key, required this.monitor});

  final FiberMonitor monitor;

  @override
  State<FiberLightScreen> createState() => _FiberLightScreenState();
}

class _FiberLightScreenState extends State<FiberLightScreen> {
  FiberMonitor get _m => widget.monitor;
  String? _pon;
  bool _bookReady = false;

  @override
  void initState() {
    super.initState();
    _m
      ..addListener(_changed)
      ..acquire();
    FiberStore.layout.addListener(_changed);
    FiberStore.loadBook(_m.oltId).then((_) {
      if (mounted) setState(() => _bookReady = true);
    });
  }

  @override
  void dispose() {
    _m
      ..removeListener(_changed)
      ..release();
    FiberStore.layout.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final layout = FiberStore.layout.value;
    final pons = {for (final o in _m.onus) o.pon}.toList()..sort();
    final onus = _pon == null ? _m.onus : _m.onus.where((o) => o.pon == _pon).toList();
    final trees = [
      for (final p in (_pon == null ? pons : [_pon!])) FiberPonTree.build(oltId: _m.oltId, pon: p, layout: layout, onus: _m.onus),
    ];
    final book = FiberStore.bookOf(_m.oltId);
    final r = FiberLightAnalysis.analyze(onus: onus, book: book, now: DateTime.now(), trees: trees);
    final byKey = {for (final o in _m.onus) o.key: o};
    final readings = r.good + r.marginal + r.weak + r.strong;
    final wide = fiberWide(context);
    final caps = _m.caps;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: deskPageBar(
        context,
        subtitle: '${FiberText.devices(_m.onus.length)} · $readings قراءة',
        mobile: AppBar(
          title: const Text('صحّة الضوء'),
          backgroundColor: AppColors.surface,
          foregroundColor: AppColors.textHi,
          elevation: 0,
          leading: IconButton(icon: const Icon(LucideIcons.arrowRight, size: 20), onPressed: () => Navigator.pop(context)),
        ),
      ),
      body: FiberPage(
        onRefresh: _m.refreshNow,
        children: [
          FiberStaleNotice(monitor: _m),
          Padding(
            padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, 0),
            child: Text(
              iso('$readings قراءة من ${FiberText.devices(_m.onus.length)}${_m.lastOkAt == null ? '' : ' · ${FiberText.clock(_m.lastOkAt!)}'}'),
              style: AppType.body(color: AppColors.textMid),
            ),
          ),
          if (caps != null && !caps.hasOptics)
            const FiberNotice(
              text: 'هذا الأولت ما يعطي قراءة الضوء عبر SNMP، فلا توزيع ولا تاريخ له. الحالة والأعطال تعمل.',
              tone: AppTone.info,
            ),
          if (pons.length > 1) _filter(pons),
          _bands(r),
          if (readings > 0) _histogram(r),
          if (wide)
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: Column(children: [for (final b in r.boxDrops) _boxDrop(b, byKey, layout)])),
              Expanded(child: Column(children: [_sudden(r, byKey), _stable(r, byKey)])),
            ])
          else ...[
            for (final b in r.boxDrops) _boxDrop(b, byKey, layout),
            _sudden(r, byKey),
            _stable(r, byKey),
          ],
          if (_bookReady && r.historyDays < 3)
            const FiberNotice(
              text: 'تاريخ الضوء يتجمّع من الآن — «نزل فجأة» و«ضعيف بس ثابت» يحتاجان أيّاماً من القراءات.',
              tone: AppTone.info,
              icon: LucideIcons.history,
            ),
          _weakList(onus),
        ],
      ),
    );
  }

  Widget _filter(List<String> pons) => SizedBox(
        height: 52,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.sm, Sp.lg, 0),
          children: [
            for (final p in <String?>[null, ...pons])
              Padding(
                padding: const EdgeInsetsDirectional.only(end: Sp.sm),
                child: ChoiceChip(
                  label: Text(p == null ? 'الكلّ' : iso(fiberPonDisplay(p))),
                  selected: _pon == p,
                  onSelected: (_) => setState(() => _pon = p),
                  showCheckmark: false,
                  selectedColor: AppColors.brand,
                  backgroundColor: AppColors.surface,
                  side: BorderSide(color: _pon == p ? AppColors.brand : AppColors.border),
                  labelStyle: AppType.bodyStrong(color: _pon == p ? AppColors.onBrand : AppColors.textBody),
                ),
              ),
          ],
        ),
      );

  Widget _bands(FiberLightReport r) => Padding(
        padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, 0),
        child: Row(children: [
          Expanded(child: FiberStat(label: 'جيّد', value: '${r.good}', foot: 'أعلى من -25', accent: AppColors.chartLine)),
          const SizedBox(width: 6),
          Expanded(
            child: FiberStat(label: 'حدّي', value: '${r.marginal}', foot: '-25 إلى -27', accent: AppTone.warning.fill, valueColor: r.marginal > 0 ? AppTone.warning.fill : null),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: FiberStat(label: 'ضعيف', value: '${r.weak}', foot: '-27 وأقلّ', accent: AppColors.errorFill, valueColor: r.weak > 0 ? AppColors.error : null),
          ),
          const SizedBox(width: 6),
          Expanded(child: FiberStat(label: 'بلا قراءة', value: '${r.noReading}', foot: 'مفصولة', accent: AppColors.borderStrong)),
        ]),
      );

  Widget _histogram(FiberLightReport r) {
    final bins = r.histogram.keys.toList()..sort();
    final lo = bins.isEmpty ? -29 : (bins.first < -29 ? bins.first : -29);
    final hi = bins.isEmpty ? -15 : (bins.last > -15 ? bins.last : -15);
    final all = [for (var k = lo; k <= hi; k++) k];
    final max = r.histogram.values.fold<int>(1, (a, b) => b > a ? b : a);
    Color colorOf(int k) => switch (FiberBands.bandOfBin(k)) {
          FiberBand.good => AppColors.chartLine,
          FiberBand.marginal || FiberBand.strong => AppTone.warning.fill,
          FiberBand.weak => AppColors.errorFill,
        };
    return Padding(
      padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, 0),
      child: FiberCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: Text('توزيع الضوء', style: AppType.cardTitleBold(color: AppColors.textHi), maxLines: 1, overflow: TextOverflow.ellipsis)),
            Text(iso('عدد الأجهزة بكلّ قراءة · dBm'), style: AppType.muted(color: AppColors.textMid)),
          ]),
          const SizedBox(height: Sp.md),
          Semantics(
            label: 'توزيع الضوء: ${r.good} جيّد، ${r.marginal} حدّي، ${r.weak} ضعيف',
            excludeSemantics: true,
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: Column(children: [
                SizedBox(
                  height: 120,
                  child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    for (final k in all)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 1.5),
                          child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                            if ((r.histogram[k] ?? 0) > 0)
                              Text('${r.histogram[k]}', style: AppType.micro(color: AppColors.textMid), maxLines: 1),
                            const SizedBox(height: 2),
                            Container(
                              height: (r.histogram[k] ?? 0) == 0 ? 2 : 96.0 * (r.histogram[k]!) / max,
                              decoration: BoxDecoration(
                                color: (r.histogram[k] ?? 0) == 0 ? AppColors.border : colorOf(k),
                                borderRadius: const BorderRadius.vertical(top: Radius.circular(R.check - 3)),
                              ),
                            ),
                          ]),
                        ),
                      ),
                  ]),
                ),
                Container(height: 1, color: AppColors.borderStrong),
                const SizedBox(height: 4),
                Row(children: [
                  for (final k in all)
                    Expanded(
                      child: Text(k % 2 != 0 ? '$k' : '', textAlign: TextAlign.center, style: AppType.micro(color: AppColors.textMid), maxLines: 1),
                    ),
                ]),
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _boxDrop(RxBoxDrop b, Map<String, FiberOnuLive> byKey, layout) {
    final box = FiberStore.layout.value.boxes[b.boxId];
    if (box == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, 0),
      child: FiberCard(
        tone: AppTone.warning,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            const FiberIconBox(LucideIcons.package, tone: AppTone.warning),
            const SizedBox(width: Sp.sm),
            Expanded(
              child: Text(iso('${box.name}: ${b.drops.length == b.boxOnusWithData ? 'أجهزته كلّها' : FiberText.devices(b.drops.length)} نزلت سوا'),
                  style: AppType.cardTitleBold(color: AppColors.textHi), maxLines: 2, overflow: TextOverflow.ellipsis),
            ),
          ]),
          const SizedBox(height: Sp.sm),
          Text(
            iso('نزل ضوءها ${b.avgDrop.toStringAsFixed(1)} dB عن أيّامها السابقة، يعني المشكلة بالصندوق نفسه — رطوبة أو وصلة الدخول — مو بالبيوت.'),
            style: AppType.body(color: AppColors.textBody),
          ),
          const SizedBox(height: Sp.sm),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final d in b.drops.take(6))
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(color: AppColors.surfaceSunken, borderRadius: BorderRadius.circular(R.sm), border: Border.all(color: AppColors.border)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(iso(byKey[d.key] == null ? fiberOnuKeyDisplay(d.key) : fiberOnuTitle(FiberStore.layout.value, _m.oltId, byKey[d.key]!)),
                      style: AppType.body(color: AppColors.textHi), maxLines: 1),
                  const SizedBox(width: 5),
                  FiberRx(d.current, style: AppType.bodyBold()),
                ]),
              ),
            if (b.drops.length > 6) Text('و${b.drops.length - 6} غيرها', style: AppType.muted(color: AppColors.textMid)),
          ]),
          const SizedBox(height: Sp.md),
          OutlinedButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => FiberPonScreen(monitor: _m, pon: box.pon))),
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(44)),
            child: const Text('افتح الصندوق'),
          ),
        ]),
      ),
    );
  }

  Widget _dropRow(RxDrop d, Map<String, FiberOnuLive> byKey, {String? foot}) {
    final o = byKey[d.key];
    final title = o == null ? fiberOnuKeyDisplay(d.key) : fiberOnuTitle(FiberStore.layout.value, _m.oltId, o);
    final sub = o == null ? '' : '${fiberPonDisplay(o.pon)} · كان ${d.baseline.toStringAsFixed(1)}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(iso(title), style: AppType.bodyStrong(color: AppColors.textHi), maxLines: 1, overflow: TextOverflow.ellipsis),
            Text(iso(foot ?? sub), style: AppType.muted(color: AppColors.textMid), maxLines: 1, overflow: TextOverflow.ellipsis),
          ]),
        ),
        FiberSpark(days: d.series, semantics: 'نازل من ${d.baseline.toStringAsFixed(1)} إلى ${d.current.toStringAsFixed(1)}'),
        const SizedBox(width: Sp.sm),
        SizedBox(
          width: 58,
          child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            FiberRx(d.current, style: AppType.cardTitleBold()),
            Text(iso('نزل ${d.drop.toStringAsFixed(1)}'), style: AppType.micro(color: AppTone.danger.onSoft), maxLines: 1),
          ]),
        ),
        if (o != null)
          IconButton(
            tooltip: 'افحصه بوضع الفنّي',
            icon: Icon(LucideIcons.wrench, size: 17, color: AppColors.brandLight),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => FiberTechScreen(monitor: _m, onuKey: o.key))),
          ),
      ]),
    );
  }

  Widget _sudden(FiberLightReport r, Map<String, FiberOnuLive> byKey) {
    if (r.suddenDrops.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, 0),
      child: FiberCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('نزل فجأة · آخر 7 أيّام', style: AppType.cardTitleBold(color: AppColors.textHi)),
          for (final d in r.suddenDrops.take(12)) _dropRow(d, byKey),
          Text('نزولٌ فجائيّ لجهازٍ واحد غالباً وصلةٌ وسخة أو سلكٌ منثني عنده — يتصلّح قبل ما يشتكي المشترك.',
              style: AppType.muted(color: AppColors.textMid)),
        ]),
      ),
    );
  }

  Widget _stable(FiberLightReport r, Map<String, FiberOnuLive> byKey) {
    if (r.stableWeak.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, 0),
      child: FiberCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('ضعيف بس ثابت', style: AppType.cardTitleBold(color: AppColors.textHi)),
          for (final s in r.stableWeak.take(12))
            _dropRow(
              RxDrop(key: s.key, current: s.current, baseline: s.current, series: s.series),
              byKey,
              foot: '${byKey[s.key] == null ? '' : '${fiberPonDisplay(byKey[s.key]!.pon)} · '}ثابت ${s.days} أيّام',
            ),
          Text('ضعفه من المسافة أو تصميم الخطّ، مو من خللٍ جديد. إذا تكرّر انقطاعه فكّر بموزّعٍ أقرب له.',
              style: AppType.muted(color: AppColors.textMid)),
        ]),
      ),
    );
  }

  Widget _weakList(List<FiberOnuLive> onus) {
    final weak = onus.where((o) => FiberBands.needsAttention(o.rx)).toList()..sort((a, b) => a.rx!.compareTo(b.rx!));
    if (weak.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, 0),
      child: FiberCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('تحتاج انتباهاً الآن · ${weak.length}', style: AppType.cardTitleBold(color: AppColors.textHi)),
          for (final o in weak.take(40))
            FiberOnuRow(
              oltId: _m.oltId,
              onu: o,
              sub: fiberOnuSub(FiberStore.layout.value, _m.oltId, o, [fiberPonDisplay(o.pon), FiberBands.label(FiberBands.of(o.rx)!)]),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => FiberTechScreen(monitor: _m, onuKey: o.key))),
            ),
        ]),
      ),
    );
  }
}
