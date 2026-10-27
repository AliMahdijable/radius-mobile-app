import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../api/vsol_olt_api.dart';
import '../../../core/util/bidi.dart';
import '../../../models/fiber_network.dart';
import '../../../services/fiber/fiber_monitor.dart';
import '../../../services/fiber/fiber_onu.dart';
import '../../../services/fiber/fiber_outage.dart';
import '../../../services/fiber/fiber_store.dart';
import '../../../services/fiber/fiber_text.dart';
import '../../../services/fiber/fiber_tree.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';
import '../../desktop/desk_widgets.dart';
import 'fiber_diagnosis_screen.dart';
import 'fiber_home_screen.dart';
import 'fiber_link_screen.dart';
import 'fiber_outage_screen.dart';
import 'fiber_sheets.dart';
import 'fiber_tech_screen.dart';
import 'fiber_widgets.dart';

/// منفذ PON وشجرته: المنفذ ← الموزّعات ← الصناديق ← البيوت. الأولت يعطي الأجهزة وحالتها؛ الصناديق يرتّبها الوكيل.
class FiberPonScreen extends StatefulWidget {
  const FiberPonScreen({super.key, required this.monitor, required this.pon});

  final FiberMonitor monitor;
  final String pon;

  @override
  State<FiberPonScreen> createState() => _FiberPonScreenState();
}

class _FiberPonScreenState extends State<FiberPonScreen> {
  late String _pon = widget.pon;
  final Set<int> _open = {};
  bool _openedFirst = false;

  FiberMonitor get _m => widget.monitor;

  @override
  void initState() {
    super.initState();
    _m
      ..addListener(_changed)
      ..acquire();
    FiberStore.layout.addListener(_changed);
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

  bool get _canEdit => fiberCanEdit();

  Future<void> _addBox({int? parent, FiberNodeKind kind = FiberNodeKind.box}) async {
    final b = await showFiberBoxSheet(context, oltId: _m.oltId, pon: _pon, parentId: parent, kind: kind);
    if (b != null && mounted) setState(() => _open.add(b.id));
  }

  Future<void> _onuTap(FiberOnuLive o) async {
    final a = await showFiberOnuSheet(context, oltId: _m.oltId, onu: o, canEdit: _canEdit);
    if (!mounted || a == null) return;
    switch (a) {
      case FiberOnuAction.diagnose:
        await Navigator.of(context).push(MaterialPageRoute(builder: (_) => FiberDiagnosisScreen(monitor: _m, onuKey: o.key)));
      case FiberOnuAction.tech:
        await Navigator.of(context).push(MaterialPageRoute(builder: (_) => FiberTechScreen(monitor: _m, onuKey: o.key)));
      case FiberOnuAction.move:
        final tree = FiberPonTree.build(oltId: _m.oltId, pon: _pon, layout: FiberStore.layout.value, onus: _m.onus);
        await showFiberAssignSheet(context, oltId: _m.oltId, pon: _pon, onus: tree.all, preselect: {o.key});
      case FiberOnuAction.link:
        await showFiberLinkPicker(context, monitor: _m, onu: o);
    }
  }

  @override
  Widget build(BuildContext context) {
    final layout = FiberStore.layout.value;
    final tree = FiberPonTree.build(oltId: _m.oltId, pon: _pon, layout: layout, onus: _m.onus);
    final port = (_m.stats?.ponPorts ?? const <VsolPonPort>[]).where((p) => p.label == _pon).firstOrNull;
    final outages = _m.outages.where((e) => e.pon == _pon).toList();
    final down = {
      for (final e in outages)
        for (final k in e.onuKeys) k: e,
    };
    if (!_openedFirst && tree.nodes.isNotEmpty) {
      _openedFirst = true;
      // افتح الصناديق المعطوبة أوّلاً — هي ما جاء الوكيل ليراه.
      for (final e in outages) {
        if (e.boxId != null) _open.addAll(tree.pathTo(e.boxId!).map((b) => b.id));
      }
    }
    final rxs = [for (final o in tree.all) if (o.rx != null) o.rx!];
    final avg = rxs.isEmpty ? null : rxs.reduce((a, b) => a + b) / rxs.length;
    final pons = (_m.stats?.ponPorts ?? const <VsolPonPort>[]).map((p) => p.label).toList()..sort();
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: deskPageBar(
        context,
        title: fiberPonDisplay(_pon),
        subtitle: '${_m.device.name} · ${FiberText.devices(tree.all.length)} · ${FiberText.boxes(tree.boxCount)}',
        mobile: AppBar(
          title: Text(fiberPonDisplay(_pon)),
          backgroundColor: AppColors.surface,
          foregroundColor: AppColors.textHi,
          elevation: 0,
          leading: IconButton(icon: const Icon(LucideIcons.arrowRight, size: 20), onPressed: () => Navigator.pop(context)),
          actions: [
            if (outages.any((e) => e.kind != FiberEventKind.power))
              const Padding(
                padding: EdgeInsetsDirectional.only(end: Sp.sm),
                child: Center(child: FiberPill('عطل', tone: AppTone.danger, dot: true)),
              ),
            if (_canEdit)
              IconButton(tooltip: 'أضف صندوقاً أو موزّعاً', icon: const Icon(LucideIcons.plus, size: 20), onPressed: () => _addBox()),
          ],
        ),
      ),
      body: FiberPage(
        onRefresh: _m.refreshNow,
        children: [
          FiberStaleNotice(monitor: _m),
          if (pons.length > 1) _ponChips(pons),
          Padding(
            padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, 0),
            child: Row(children: [
              Expanded(
                child: FiberStat(
                  label: 'المتّصلون',
                  value: '${tree.onlineCount}/${tree.all.length}',
                  foot: tree.all.length - tree.onlineCount == 0 ? 'كلّها متّصلة' : '${tree.all.length - tree.onlineCount} مفصول',
                ),
              ),
              const SizedBox(width: Sp.sm),
              Expanded(child: FiberStat(label: 'متوسّط الضوء', value: avg == null ? '—' : avg.toStringAsFixed(1), foot: 'للأجهزة المتّصلة')),
              const SizedBox(width: Sp.sm),
              Expanded(
                child: FiberStat(
                  label: 'منافذ فارغة',
                  value: '${tree.freeBoxPorts}',
                  foot: tree.boxCount == 0 ? 'لا صناديق بعد' : 'بـ${FiberText.boxes(tree.boxCount)}',
                ),
              ),
            ]),
          ),
          FiberSection('من الأولت إلى البيوت', trailing: tree.nodes.isEmpty ? null : 'اضغط صندوقاً لتفتحه'),
          _root(port, tree),
          if (tree.nodes.isEmpty) ...[
            const SizedBox(height: Sp.sm),
            _noBoxes(tree),
          ] else
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Sp.lg),
              child: _rail([for (final b in tree.roots) _node(tree, b, down)]),
            ),
          if (tree.unassigned.isNotEmpty && tree.nodes.isNotEmpty) _unassigned(tree),
          if (_canEdit)
            Padding(
              padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, 0),
              child: OutlinedButton.icon(
                onPressed: () => _addBox(),
                icon: const Icon(LucideIcons.plus, size: 16),
                label: const Text('أضف صندوقاً أو موزّعاً'),
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(44)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _ponChips(List<String> pons) => SizedBox(
        height: 52,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.sm, Sp.lg, 0),
          children: [
            for (final p in pons)
              Padding(
                padding: const EdgeInsetsDirectional.only(end: Sp.sm),
                child: ChoiceChip(
                  label: Text(iso(fiberPonDisplay(p))),
                  selected: p == _pon,
                  onSelected: (_) => setState(() {
                    _pon = p;
                    _openedFirst = false;
                  }),
                  showCheckmark: false,
                  selectedColor: AppColors.brandSoftBg,
                  backgroundColor: AppColors.surface,
                  side: BorderSide(color: p == _pon ? AppColors.brandSoftBorder : AppColors.border),
                  labelStyle: AppType.bodyStrong(color: p == _pon ? AppColors.brandOnSoft : AppColors.textBody),
                ),
              ),
          ],
        ),
      );

  Widget _root(VsolPonPort? port, FiberPonTree tree) {
    final down = _m.ponRates[_pon]?.txBps;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Sp.lg),
      child: Container(
        padding: const EdgeInsets.all(Sp.md),
        decoration: BoxDecoration(color: AppColors.brandSurface, borderRadius: BorderRadius.circular(R.lg)),
        child: Row(children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: AppColors.onBrandFill2, borderRadius: BorderRadius.circular(R.sm)),
            child: const Icon(LucideIcons.server, size: 18, color: AppColors.onBrand),
          ),
          const SizedBox(width: Sp.md),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(iso('منفذ ${fiberPonDisplay(_pon)} على الأولت'),
                  style: AppType.cardTitleBold(color: AppColors.onBrand), maxLines: 1, overflow: TextOverflow.ellipsis),
              Text(
                iso([
                  port == null ? '—' : (port.up ? 'شغّال' : 'مطفأ'),
                  port?.technology == VsolPonTechnology.gpon ? 'GPON' : 'EPON',
                  FiberText.devices(tree.all.length),
                ].join(' · ')),
                style: AppType.muted(color: AppColors.onBrandStrong),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ]),
          ),
          if (down != null) Text(iso('↓ ${(down / 1e6).toStringAsFixed(down >= 1e8 ? 0 : 1)} Mbps'), style: AppType.bodyBold(color: AppColors.onBrand)),
        ]),
      ),
    );
  }

  /// خطّ الشجرة: عموديٌّ على جهة البداية تتدلّى منه العُقد.
  Widget _rail(List<Widget> nodes) => Container(
        margin: const EdgeInsetsDirectional.only(start: 17),
        padding: const EdgeInsetsDirectional.only(start: Sp.sm),
        decoration: BoxDecoration(border: BorderDirectional(start: BorderSide(color: AppColors.borderStrong, width: 2))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (final n in nodes) Padding(padding: const EdgeInsets.only(top: Sp.sm), child: n),
        ]),
      );

  Widget _noBoxes(FiberPonTree tree) => Padding(
        padding: const EdgeInsets.fromLTRB(Sp.lg, 0, Sp.lg, 0),
        child: FiberCard(
          dashed: true,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              const FiberIconBox(LucideIcons.lightbulb, tone: AppTone.info),
              const SizedBox(width: Sp.sm),
              Expanded(
                child: Text('رتّب صناديق هذا المنفذ', style: AppType.cardTitleBold(color: AppColors.textHi), maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            ]),
            const SizedBox(height: Sp.sm),
            Text(
              'الأولت يعرف الأجهزة لا الصناديق. أضف الموزّع والصناديق وأسند لها الأجهزة، فيعرف التطبيق مكان القطع ويحسب المنافذ الفارغة.',
              style: AppType.body(color: AppColors.textBody),
            ),
            const SizedBox(height: Sp.md),
            for (final o in tree.all.take(40))
              FiberOnuRow(oltId: _m.oltId, onu: o, onTap: () => _onuTap(o)),
            if (tree.all.length > 40)
              Text('و${tree.all.length - 40} غيرها', style: AppType.muted(color: AppColors.textMid)),
          ]),
        ),
      );

  /// عقدةٌ وفروعها بخطٍّ عموديّ على جهة البداية.
  Widget _node(FiberPonTree tree, FiberBox b, Map<String, FiberOutage> down) {
    final kids = tree.childrenOf(b.id);
    final under = tree.onusUnder(b.id);
    final mine = tree.onusOf[b.id] ?? const <FiberOnuLive>[];
    final online = under.where((o) => o.online).length;
    final outage = _m.outages.where((e) => e.boxId == b.id || (e.pon == _pon && under.isNotEmpty && under.every((o) => e.onuKeys.contains(o.key)))).firstOrNull;
    final bad = outage != null && outage.kind != FiberEventKind.power;
    final open = _open.contains(b.id);
    final splitter = b.kind == FiberNodeKind.splitter;
    final slots = <FiberSlot>[
      for (final o in mine) o.online ? FiberSlot.up : FiberSlot.down,
      for (final _ in kids) FiberSlot.up,
      for (var i = 0; i < tree.freePorts(b.id); i++) FiberSlot.free,
    ];
    final rxs = [for (final o in under) if (o.rx != null) o.rx!]..sort();
    final card = FiberCard(
      tone: bad ? AppTone.danger : null,
      onTap: () => setState(() => open ? _open.remove(b.id) : _open.add(b.id)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          FiberIconBox(splitter ? LucideIcons.network : LucideIcons.package, tone: bad ? AppTone.danger : AppTone.brand, size: 32),
          const SizedBox(width: Sp.sm),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(iso('${b.name} · 1:${b.ratio}'), style: AppType.cardTitleBold(color: AppColors.textHi), maxLines: 1, overflow: TextOverflow.ellipsis),
              if (b.location != null || b.hasGps)
                Row(children: [
                  Icon(LucideIcons.mapPin, size: 12, color: AppColors.textMid),
                  const SizedBox(width: 3),
                  Flexible(
                    child: Text(b.location ?? 'موقع على الخريطة',
                        style: AppType.muted(color: AppColors.textMid), maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                ]),
            ]),
          ),
          FiberPill(
            '$online/${under.length}${bad ? ' · عطل' : ''}',
            tone: bad ? AppTone.danger : (online == under.length ? AppTone.success : AppTone.warning),
          ),
          if (_canEdit)
            IconButton(
              tooltip: 'تعديل',
              visualDensity: VisualDensity.compact,
              icon: Icon(LucideIcons.pencil, size: 16, color: AppColors.textMid),
              onPressed: () => showFiberBoxSheet(context, oltId: _m.oltId, pon: _pon, initial: b),
            ),
        ]),
        if (!splitter || mine.isNotEmpty) ...[
          const SizedBox(height: Sp.sm),
          FiberSlots(slots: slots),
        ],
        if (bad) ...[
          const SizedBox(height: Sp.sm),
          Material(
            color: AppTone.danger.softBg,
            borderRadius: BorderRadius.circular(R.sm),
            child: InkWell(
              borderRadius: BorderRadius.circular(R.sm),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => FiberOutageScreen(monitor: _m, scopeKey: outage.scopeKey))),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                child: Row(children: [
                  Icon(LucideIcons.scissors, size: 15, color: AppTone.danger.onSoft),
                  const SizedBox(width: Sp.sm),
                  Expanded(
                    child: Text(
                      iso(outage.startedAt == null
                          ? 'كلّها مفصولة الآن · ${FiberText.verdict(outage.kind)}'
                          : 'انقطعت ${FiberText.clock(outage.startedAt!, seconds: true)}'
                              '${outage.lastDropAt != null && outage.lastDropAt != outage.startedAt ? ' – ${FiberText.clock(outage.lastDropAt!, seconds: true)}' : ''}'
                              ' · ${FiberText.verdict(outage.kind)}'),
                      style: AppType.bodyStrong(color: AppTone.danger.onSoft),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Icon(LucideIcons.chevronLeft, size: 16, color: AppTone.danger.onSoft),
                ]),
              ),
            ),
          ),
        ],
        if (!open && under.isNotEmpty) ...[
          const SizedBox(height: Sp.sm),
          Row(children: [
            Expanded(
              child: Text(
                iso(rxs.isEmpty
                    ? (online == 0 ? 'كلّها مفصولة' : 'بلا قراءة ضوء')
                    : 'الضوء من ${rxs.last.toStringAsFixed(1)} إلى ${rxs.first.toStringAsFixed(1)}'),
                style: AppType.muted(color: AppColors.textMid),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Icon(LucideIcons.chevronDown, size: 16, color: AppColors.textLow),
          ]),
        ],
        if (open) ...[
          if (mine.isNotEmpty) Divider(height: Sp.lg, color: AppColors.divider),
          for (final o in mine)
            FiberOnuRow(
              oltId: _m.oltId,
              onu: o,
              onTap: () => _onuTap(o),
              sub: !o.online && down.containsKey(o.key) && o.changedAt != null
                  ? '${o.display} · ${o.reason == null ? 'مفصول' : fiberReasonLabel(o.reason!)} ${FiberText.clock(o.changedAt!, seconds: true)}'
                  : null,
            ),
          if (_canEdit) ...[
            const SizedBox(height: Sp.xs),
            Row(children: [
              if (!splitter)
                Expanded(
                  child: TextButton.icon(
                    onPressed: () => showFiberAssignSheet(context, oltId: _m.oltId, pon: _pon, onus: tree.all, boxId: b.id),
                    icon: const Icon(LucideIcons.packagePlus, size: 16),
                    label: const Text('أسند أجهزة'),
                  ),
                ),
              Expanded(
                child: TextButton.icon(
                  onPressed: () => _addBox(parent: b.id),
                  icon: const Icon(LucideIcons.plus, size: 16),
                  label: const Text('صندوق تحته'),
                ),
              ),
              if (b.hasGps)
                IconButton(
                  tooltip: 'افتح المكان بالخرائط',
                  icon: Icon(LucideIcons.map, size: 18, color: AppColors.brandLight),
                  onPressed: () => launchUrl(
                    Uri.parse('https://www.google.com/maps/search/?api=1&query=${b.lat},${b.lng}'),
                    mode: LaunchMode.externalApplication,
                  ),
                ),
            ]),
          ],
        ],
      ]),
    );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      card,
      if (kids.isNotEmpty) _rail([for (final k in kids) _node(tree, k, down)]),
    ]);
  }

  Widget _unassigned(FiberPonTree tree) {
    final layout = FiberStore.layout.value;
    // مقترح: أجهزةٌ بلا صندوق سقطت مع أجهزة صندوقٍ واحد في عطلٍ سابق ⇒ على الأغلب منه.
    final hints = <int, List<FiberOnuLive>>{};
    for (final e in layout.events.where((e) => e.oltId == _m.oltId && e.pon == _pon && e.boxId != null)) {
      for (final o in tree.unassigned) {
        if (e.onuKeys.contains(o.key)) hints.putIfAbsent(e.boxId!, () => []).add(o);
      }
    }
    final best = hints.entries.where((h) => tree.nodes.containsKey(h.key)).fold<MapEntry<int, List<FiberOnuLive>>?>(
        null, (a, b) => a == null || b.value.length > a.value.length ? b : a);
    return Padding(
      padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.sm, Sp.lg, 0),
      child: FiberCard(
        dashed: true,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            const FiberIconBox(LucideIcons.lightbulb, tone: AppTone.info, size: 32),
            const SizedBox(width: Sp.sm),
            Expanded(
              child: Text('${FiberText.devices(tree.unassigned.length)} بلا صندوق',
                  style: AppType.cardTitleBold(color: AppColors.textHi), maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ]),
          if (best != null) ...[
            const SizedBox(height: Sp.sm),
            Text(
              'انقطعت ${best.value.length == 1 ? '' : 'كلّها '}مع أجهزة ${tree.nodes[best.key]!.name} في عطلٍ سابق، يعني على الأغلب بنفس الصندوق.',
              style: AppType.body(color: AppColors.textBody),
            ),
          ],
          const SizedBox(height: Sp.sm),
          for (final o in tree.unassigned.take(30)) FiberOnuRow(oltId: _m.oltId, onu: o, onTap: () => _onuTap(o)),
          if (tree.unassigned.length > 30) Text('و${tree.unassigned.length - 30} غيرها', style: AppType.muted(color: AppColors.textMid)),
          if (_canEdit) ...[
            const SizedBox(height: Sp.sm),
            Row(children: [
              if (best != null)
                Expanded(
                  child: FilledButton(
                    onPressed: () => FiberStore.assign(_m.oltId, best.value, best.key),
                    style: FilledButton.styleFrom(backgroundColor: AppColors.brand, minimumSize: const Size.fromHeight(44)),
                    child: Text(iso('أضفها لـ${tree.nodes[best.key]!.name}'),
                        style: AppType.bodyStrong(color: AppColors.onBrand), maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                ),
              if (best != null) const SizedBox(width: Sp.sm),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => showFiberAssignSheet(context, oltId: _m.oltId, pon: _pon, onus: tree.all,
                      preselect: {for (final o in tree.unassigned) o.key}),
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(44)),
                  child: const Text('اختر صندوقاً'),
                ),
              ),
            ]),
          ],
          if (!_canEdit) ...[
            const SizedBox(height: Sp.xs),
            Row(children: [
              Icon(LucideIcons.lock, size: 14, color: AppColors.textLow),
              const SizedBox(width: Sp.xs),
              Expanded(child: Text('ترتيب الصناديق بصلاحيّة إدارة الأجهزة', style: AppType.muted(color: AppColors.textLow), maxLines: 1)),
            ]),
          ],
        ]),
      ),
    );
  }
}
