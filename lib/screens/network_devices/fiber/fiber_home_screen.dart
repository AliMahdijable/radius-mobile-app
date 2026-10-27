import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../api/vsol_olt_api.dart';
import '../../../core/platform/desktop_layout.dart';
import '../../../core/util/bidi.dart';
import '../../../models/fiber_network.dart';
import '../../../models/network_device.dart';
import '../../../services/fiber/fiber_band.dart';
import '../../../services/fiber/fiber_monitor.dart';
import '../../../services/fiber/fiber_onu.dart';
import '../../../services/fiber/fiber_outage.dart';
import '../../../services/fiber/fiber_store.dart';
import '../../../services/fiber/fiber_text.dart';
import '../../../services/fiber/fiber_tree.dart';
import '../../../services/permissions_service.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';
import '../../desktop/desk_widgets.dart';
import 'fiber_light_screen.dart';
import 'fiber_link_screen.dart';
import 'fiber_outage_screen.dart';
import 'fiber_pon_screen.dart';
import 'fiber_search_screen.dart';
import 'fiber_settings_sheet.dart';
import 'fiber_tech_screen.dart';
import 'fiber_widgets.dart';

/// «شبكة الألياف» — المالك ٢٧ أكتوبر: «نكدر نضيف تصميم كذلك لاهل ال olt والوضوئي… كلشي عجبني بي… ابنيها ع تطبيق الهاتف
/// والحاسوب بدقة». المصدر: [FiberMonitor] (الأولت مباشرةً) و[FiberStore] (ما رتّبه الوكيل على خادمنا).
class FiberHomeScreen extends StatefulWidget {
  const FiberHomeScreen({super.key, required this.olts, this.initialOltId});

  final List<NetworkDevice> olts;
  final int? initialOltId;

  @override
  State<FiberHomeScreen> createState() => _FiberHomeScreenState();
}

class _FiberHomeScreenState extends State<FiberHomeScreen> {
  late NetworkDevice _olt = widget.olts.firstWhere((d) => d.id == widget.initialOltId, orElse: () => widget.olts.first);
  late FiberMonitor _m = FiberMonitor.of(_olt);

  @override
  void initState() {
    super.initState();
    _m
      ..addListener(_changed)
      ..acquire();
    FiberStore.layout.addListener(_changed);
    FiberStore.ensureLoaded().then((_) => _changed());
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

  void _switch(NetworkDevice d) {
    if (d.id == _olt.id) return;
    _m
      ..removeListener(_changed)
      ..release();
    setState(() {
      _olt = d;
      _m = FiberMonitor.of(d)
        ..addListener(_changed)
        ..acquire();
    });
  }

  Future<T?> _push<T>(Widget w) => Navigator.of(context).push<T>(MaterialPageRoute(builder: (_) => w));

  @override
  Widget build(BuildContext context) {
    final layout = FiberStore.layout.value;
    final onus = _m.onus;
    final online = onus.where((o) => o.online).length;
    final pons = (_m.stats?.ponPorts ?? const <VsolPonPort>[]).toList()..sort((a, b) => a.label.compareTo(b.label));
    final trees = {
      for (final p in pons) p.label: FiberPonTree.build(oltId: _olt.id, pon: p.label, layout: layout, onus: onus),
    };
    final attention = onus.where((o) => FiberBands.needsAttention(o.rx)).toList();
    final weak = attention.where((o) => FiberBands.of(o.rx) == FiberBand.weak).length;
    final inOutage = {for (final e in _m.outages) ...e.onuKeys};
    final powerOff = onus.where((o) => !o.online && o.reason == FiberDropReason.power && !inOutage.contains(o.key)).toList();
    final lightLost = onus.where((o) => !o.online && o.reason == FiberDropReason.fiber && !inOutage.contains(o.key)).toList();
    final unlinked = onus.where((o) => layout.recordFor(_olt.id, o.key, o.ident)?.username == null).length;
    final freePorts = trees.values.fold<int>(0, (a, t) => a + t.freeBoxPorts);
    final caps = FiberStore.caps.value[_olt.id] ?? _m.caps?.toJson();
    final noOptics = caps != null && _m.caps != null && !_m.caps!.hasOptics;

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: deskPageBar(
        context,
        subtitle: '${_olt.name} · ${_m.profile.label}',
        mobile: AppBar(
          title: const Text('شبكة الألياف'),
          backgroundColor: AppColors.surface,
          foregroundColor: AppColors.textHi,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(LucideIcons.arrowRight, size: 20),
            onPressed: () => Navigator.pop(context),
          ),
          actions: [
            IconButton(
              tooltip: 'تحديث الآن',
              icon: _m.busy
                  ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.brand))
                  : const Icon(LucideIcons.refreshCw, size: 20),
              onPressed: _m.busy ? null : _m.refreshNow,
            ),
            IconButton(
              tooltip: 'إعدادات الألياف',
              icon: const Icon(LucideIcons.settings2, size: 20),
              onPressed: () => showFiberSettingsSheet(context, oltId: _olt.id, oltName: _olt.name),
            ),
            const SizedBox(width: 4),
          ],
        ),
      ),
      body: FiberPage(
        onRefresh: _m.refreshNow,
        children: [
          _oltLine(),
          if (_m.error != null) FiberNotice(text: _m.error!, tone: AppTone.danger, onRetry: _m.refreshNow, icon: LucideIcons.wifiOff),
          if (!FiberStore.serverReady)
            const FiberNotice(text: 'الحفظ على هذا الجهاز فقط الآن — يتزامن مع الخادم حين يتوفّر.', icon: LucideIcons.cloudOff),
          if (_m.stats == null && _m.error == null) _loading(),
          if (_m.stats != null) ...[
            _search(),
            _kpis(onus.length, online, attention.length, weak),
            for (final e in _m.outages) _outageCard(e, layout, trees[e.pon]),
            if (powerOff.isNotEmpty)
              _noteCard(
                icon: LucideIcons.plug,
                tone: AppTone.warning,
                title: '${FiberText.devices(powerOff.length)} طافية من كهرباء البيت',
                body: 'بعثت إشارة انطفاء${_ponsOf(powerOff)}، ما تحتاج فنّياً.',
              ),
            if (lightLost.isNotEmpty)
              _noteCard(
                icon: LucideIcons.unplug,
                tone: AppTone.danger,
                title: '${FiberText.devices(lightLost.length)} انقطع عنها الضوء',
                body: 'كلّ واحدٍ بمكانه${_ponsOf(lightLost)} — سلك البيت أو وصلة الصندوق.',
                onTap: () => _push(FiberPonScreen(monitor: _m, pon: lightLost.first.pon)),
              ),
            if (noOptics)
              const FiberNotice(
                text: 'هذا الأولت ما يعطي قراءة الضوء عبر SNMP — الحالة والأعطال تعمل، وشاشات الضوء تحتاج أولتاً يعطيها.',
                tone: AppTone.info,
              ),
            FiberSection('منافذ الـPON', trailing: _trafficLine(pons)),
            _ponGrid(pons, trees),
            const FiberSection('أدوات'),
            _tools(attention.length, unlinked, freePorts),
            _footer(),
          ],
        ],
      ),
    );
  }

  String _ponsOf(List<FiberOnuLive> l) {
    final pons = {for (final o in l) fiberPonDisplay(o.pon)}.toList()..sort();
    return pons.isEmpty ? '' : ' على ${pons.join('، ')}';
  }

  Widget _oltLine() {
    final live = _m.error == null && _m.lastOkAt != null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, Sp.xs),
      child: Wrap(spacing: Sp.sm, runSpacing: Sp.sm, crossAxisAlignment: WrapCrossAlignment.center, children: [
        if (widget.olts.length > 1)
          for (final d in widget.olts)
            ChoiceChip(
              label: Text(d.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              selected: d.id == _olt.id,
              onSelected: (_) => _switch(d),
              labelStyle: AppType.bodyStrong(color: d.id == _olt.id ? AppColors.brandOnSoft : AppColors.textBody),
              selectedColor: AppColors.brandSoftBg,
              backgroundColor: AppColors.surface,
              side: BorderSide(color: d.id == _olt.id ? AppColors.brandSoftBorder : AppColors.border),
              showCheckmark: false,
            )
        else
          // الحاسبة: اسم الأولت في رأس الصفحة أصلاً — هنا الطراز وحده.
          Text(DesktopScope.of(context) ? (_m.profile.model ?? _m.profile.label) : '${_olt.name} · ${_m.profile.model ?? _m.profile.label}',
              style: AppType.body(color: AppColors.textMid), maxLines: 1, overflow: TextOverflow.ellipsis),
        FiberPill(live ? 'مباشر' : (_m.busy ? 'يقرأ…' : 'متوقّف'), tone: live ? AppTone.success : AppTone.neutral, dot: live),
      ]),
    );
  }

  Widget _loading() => Padding(
        padding: const EdgeInsets.all(Sp.xxl),
        child: Column(children: [
          SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: AppColors.brand)),
          const SizedBox(height: Sp.md),
          Text('يقرأ الأولت…', style: AppType.body(color: AppColors.textMid)),
        ]),
      );

  Widget _search() => Padding(
        padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.sm, Sp.lg, 0),
        child: Material(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(R.md),
          child: InkWell(
            borderRadius: BorderRadius.circular(R.md),
            onTap: () => _push(FiberSearchScreen(monitor: _m)),
            child: Container(
              height: H.search,
              padding: const EdgeInsets.symmetric(horizontal: Sp.md),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(R.md), border: Border.all(color: AppColors.borderSoft)),
              child: Row(children: [
                Icon(LucideIcons.search, size: 18, color: AppColors.textHint),
                const SizedBox(width: Sp.sm),
                Expanded(
                  child: Text('ابحث بالاسم أو الماك أو رقم الجهاز',
                      style: AppType.input(color: AppColors.textMid), maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ]),
            ),
          ),
        ),
      );

  Widget _kpis(int total, int online, int attention, int weak) {
    final outage = _m.outages.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, 0),
      child: Row(children: [
        Expanded(
          child: FiberStat(
            label: 'المتّصلون',
            value: '$online/$total',
            foot: total - online == 0 ? 'كلّها متّصلة' : '${total - online} مفصول',
          ),
        ),
        const SizedBox(width: Sp.sm),
        Expanded(
          child: FiberStat(
            label: 'ضوء يحتاج انتباهاً',
            value: '$attention',
            foot: weak > 0 ? '$weak ضعيفة' : (attention > 0 ? 'كلّها حدّيّة' : 'الكلّ جيّد'),
            valueColor: attention > 0 ? AppTone.warning.fill : null,
            onTap: () => _push(FiberLightScreen(monitor: _m)),
          ),
        ),
        const SizedBox(width: Sp.sm),
        Expanded(
          child: FiberStat(
            label: 'أعطال الآن',
            value: '$outage',
            foot: outage == 0 ? 'لا عطل جماعيّ' : FiberText.devices(_m.outages.fold(0, (a, e) => a + e.count)),
            valueColor: outage > 0 ? AppColors.error : null,
            onTap: outage == 0 ? null : () => _push(FiberOutageScreen(monitor: _m, scopeKey: _m.outages.first.scopeKey)),
          ),
        ),
      ]),
    );
  }

  Widget _outageCard(FiberOutage e, FiberLayout layout, FiberPonTree? tree) {
    final power = e.kind == FiberEventKind.power;
    final tone = power ? AppTone.warning : AppTone.danger;
    final title = FiberText.outageTitle(scope: e.scope, pon: e.pon, count: e.count, boxId: e.boxId, layout: layout);
    final since = e.startedAt;
    final sub = [
      fiberPonDisplay(e.pon),
      if (since != null) 'من ${FiberText.clock(since)}',
      if (since != null) 'صار له ${FiberText.duration(DateTime.now().difference(since))}',
      if (since == null) 'منذ وقتٍ غير معروف',
    ].join(' · ');
    final spread = e.spread;
    final body = [
      e.timed && spread != null
          ? '${FiberText.devices(e.count)} انقطعت معاً خلال ${FiberText.duration(spread)}'
          : '${FiberText.devices(e.count)} مفصولة معاً الآن',
      switch (e.kind) {
        FiberEventKind.cut => 'والأولت يقول «فقدان ضوء». يعني على الأغلب قطع بالليف، مو انقطاع كهرباء.',
        FiberEventKind.power => 'وبعثت إشارة انطفاء. يعني انقطاع كهرباء بالمنطقة، ما يحتاج فنّياً.',
        FiberEventKind.mixed => 'بعضها «فقدان ضوء» وبعضها انطفاء كهرباء.',
        FiberEventKind.unknown => 'والأولت ما يقول السبب — افتح العطل لترى مكانه.',
      },
    ].join('، ');
    void open() => _push(FiberOutageScreen(monitor: _m, scopeKey: e.scopeKey));
    return Padding(
      padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, 0),
      child: FiberCard(
        tone: tone,
        onTap: open,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            FiberIconBox(power ? LucideIcons.plug : LucideIcons.scissors, tone: tone, size: 40),
            const SizedBox(width: Sp.md),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(iso(power ? title.replaceFirst('عطل', 'انطفاء') : title),
                    style: AppType.cardTitleBold(color: AppColors.textHi), maxLines: 2, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(iso(sub), style: AppType.muted(color: AppColors.textMid), maxLines: 2, overflow: TextOverflow.ellipsis),
              ]),
            ),
          ]),
          const SizedBox(height: Sp.sm),
          Text(body, style: AppType.body(color: AppColors.textBody), maxLines: 4, overflow: TextOverflow.ellipsis),
          if (!power) ...[
            const SizedBox(height: Sp.md),
            Row(children: [
              Expanded(
                child: FilledButton(
                  onPressed: open,
                  style: FilledButton.styleFrom(backgroundColor: AppColors.brand, minimumSize: const Size.fromHeight(44)),
                  child: Text('شوف العطل', style: AppType.bodyStrong(color: AppColors.onBrand)),
                ),
              ),
              const SizedBox(width: Sp.sm),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _push(FiberOutageScreen(monitor: _m, scopeKey: e.scopeKey, focusNotify: true)),
                  icon: Icon(LucideIcons.messageCircle, size: 16, color: AppColors.brandLight),
                  label: Text('بلّغهم بالواتساب', style: AppType.bodyStrong(color: AppColors.brandLight), maxLines: 1, overflow: TextOverflow.ellipsis),
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(44), side: BorderSide(color: AppColors.brandSoftBorder)),
                ),
              ),
            ]),
          ],
        ]),
      ),
    );
  }

  Widget _noteCard({required IconData icon, required AppTone tone, required String title, required String body, VoidCallback? onTap}) =>
      Padding(
        padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, 0),
        child: FiberCard(
          onTap: onTap,
          child: Row(children: [
            FiberIconBox(icon, tone: tone),
            const SizedBox(width: Sp.md),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(iso(title), style: AppType.bodyStrong(color: AppColors.textHi), maxLines: 2, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(iso(body), style: AppType.muted(color: AppColors.textMid), maxLines: 3, overflow: TextOverflow.ellipsis),
              ]),
            ),
            if (onTap != null) Icon(LucideIcons.chevronLeft, size: 18, color: AppColors.textLow),
          ]),
        ),
      );

  String? _trafficLine(List<VsolPonPort> pons) {
    double? down;
    for (final p in pons) {
      final v = _m.ponRates[p.label]?.txBps;
      if (v != null) down = (down ?? 0) + v;
    }
    return down == null ? null : 'الترافك الآن ↓ ${_mbps(down)}';
  }

  static String _mbps(double bps) {
    final m = bps / 1e6;
    if (m >= 1000) return '${(m / 1000).toStringAsFixed(2)} Gbps';
    if (m >= 100) return '${m.round()} Mbps';
    return '${m.toStringAsFixed(1)} Mbps';
  }

  Widget _ponGrid(List<VsolPonPort> pons, Map<String, FiberPonTree> trees) {
    if (pons.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: Sp.lg),
        child: Text('الأولت ما أعطى منافذ PON بعد.', style: AppType.body(color: AppColors.textMid)),
      );
    }
    final cols = fiberWide(context) ? 4 : 2;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Sp.lg),
      child: LayoutBuilder(builder: (context, c) {
        final w = (c.maxWidth - Sp.sm * (cols - 1)) / cols;
        return Wrap(spacing: Sp.sm, runSpacing: Sp.sm, children: [
          for (final p in pons) SizedBox(width: w, child: _ponCard(p, trees[p.label]!)),
        ]);
      }),
    );
  }

  Widget _ponCard(VsolPonPort p, FiberPonTree t) {
    final total = t.all.length;
    final online = t.onlineCount;
    final outage = _m.outages.where((e) => e.pon == p.label && e.kind != FiberEventKind.power).isNotEmpty;
    final weak = t.all.where((o) => FiberBands.needsAttention(o.rx)).length;
    final rxs = [for (final o in t.all) if (o.rx != null) o.rx!];
    final avg = rxs.isEmpty ? null : rxs.reduce((a, b) => a + b) / rxs.length;
    final (String state, AppTone tone) = !p.up
        ? ('مطفأ', AppTone.neutral)
        : outage
            ? ('عطل', AppTone.danger)
            : weak > 0
                ? ('$weak ضعيفة', AppTone.warning)
                : ('سليم', AppTone.success);
    final pct = total == 0 ? 0.0 : online / total;
    final down = _m.ponRates[p.label]?.txBps;
    return FiberCard(
      tone: outage ? AppTone.danger : null,
      onTap: () => _push(FiberPonScreen(monitor: _m, pon: p.label)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(iso(fiberPonDisplay(p.label)),
                style: AppType.cardTitleBold(color: AppColors.textHi), maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          FiberPill(state, tone: tone, dot: outage),
        ]),
        const SizedBox(height: Sp.sm),
        Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
          Text(iso('$online/$total'), style: AppType.amount(color: AppColors.textHi), maxLines: 1),
          const SizedBox(width: 6),
          Flexible(child: Text('متّصل', style: AppType.muted(color: AppColors.textMid), maxLines: 1, overflow: TextOverflow.ellipsis)),
        ]),
        const SizedBox(height: Sp.sm),
        ClipRRect(
          borderRadius: BorderRadius.circular(R.pill),
          child: LinearProgressIndicator(
            value: pct,
            minHeight: 6,
            backgroundColor: AppColors.surfaceSunken,
            color: outage ? AppColors.errorFill : AppColors.successFill,
          ),
        ),
        const SizedBox(height: Sp.sm),
        _factLine('متوسّط الضوء', avg == null ? '—' : avg.toStringAsFixed(1)),
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(
            t.boxCount == 0 ? 'بلا صناديق بعد — رتّبها' : '${FiberText.boxes(t.boxCount)} · ${FiberText.freePorts(t.freeBoxPorts)}',
            style: AppType.muted(color: AppColors.textMid),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        _factLine('الترافك', down == null ? '—' : '↓ ${_mbps(down)}'),
      ]),
    );
  }

  Widget _factLine(String label, String value) => Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Row(children: [
          Expanded(child: Text(label, style: AppType.muted(color: AppColors.textMid), maxLines: 1, overflow: TextOverflow.ellipsis)),
          Text(iso(value), style: AppType.pillBold(color: AppColors.textHi), maxLines: 1),
        ]),
      );

  Widget _tools(int attention, int unlinked, int freePorts) {
    Widget tool(IconData icon, String title, String foot, VoidCallback onTap) => FiberCard(
          onTap: onTap,
          child: Row(children: [
            FiberIconBox(icon),
            const SizedBox(width: Sp.sm),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: AppType.bodyStrong(color: AppColors.textHi), maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(iso(foot), style: AppType.muted(color: AppColors.textMid), maxLines: 1, overflow: TextOverflow.ellipsis),
              ]),
            ),
          ]),
        );
    final cols = fiberWide(context) ? 4 : 2;
    final firstPon = _m.stats?.ponPorts.isNotEmpty == true ? _m.stats!.ponPorts.first.label : null;
    final items = [
      tool(LucideIcons.sun, 'صحّة الضوء', attention == 0 ? 'الكلّ جيّد' : '${FiberText.devices(attention)} تحتاج انتباهاً',
          () => _push(FiberLightScreen(monitor: _m))),
      tool(LucideIcons.wrench, 'وضع الفنّي', 'ضوءٌ حيّ بالموقع', () => _push(FiberTechScreen(monitor: _m))),
      tool(LucideIcons.link, 'ربط المشتركين', unlinked == 0 ? 'كلّها مربوطة' : '${FiberText.devices(unlinked)} بلا ربط',
          () => _push(FiberLinkScreen(monitor: _m))),
      tool(LucideIcons.package, 'الصناديق', '${FiberText.ports(freePorts)} فارغة',
          firstPon == null ? () {} : () => _push(FiberPonScreen(monitor: _m, pon: firstPon))),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Sp.lg),
      child: LayoutBuilder(builder: (context, c) {
        final w = (c.maxWidth - Sp.sm * (cols - 1)) / cols;
        return Wrap(spacing: Sp.sm, runSpacing: Sp.sm, children: [for (final i in items) SizedBox(width: w, child: i)]);
      }),
    );
  }

  Widget _footer() {
    final at = _m.lastOkAt;
    final every = _m.background ? 30 : 15;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.lg, Sp.lg, 0),
      child: Text(
        at == null ? 'تتحدّث كلّ $every ثانية' : 'آخر قراءة ${FiberText.clock(at, seconds: true)} · تتحدّث كلّ $every ثانية',
        textAlign: TextAlign.center,
        style: AppType.muted(color: AppColors.textMid),
      ),
    );
  }
}

/// يفتح شبكة الألياف لأولتات الحساب (من قسم الأجهزة).
Future<void> openFiberHome(BuildContext context, List<NetworkDevice> olts, {int? oltId}) async {
  if (olts.isEmpty) return;
  await Navigator.of(context).push(MaterialPageRoute(builder: (_) => FiberHomeScreen(olts: olts, initialOltId: oltId)));
}

/// الوكيل يرتّب الصناديق ويربط المشتركين بصلاحيّة «إدارة الأجهزة»؛ القراءة بصلاحيّة العرض.
bool fiberCanEdit() => Perms.has('devices.manage');
