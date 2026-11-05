// «الفحص الشامل» — تقريرٌ منفصل لكلّ جهاز (المالك ٦ نوفمبر: «من يكون الجهاز ع شكل سكتر يفحص الجهاز نفسه ويفحص المشتركين الي
// بداخلة ويعطي تقرير منفصل لكل جهاز» · «كذلك السوجات من حيث المتغيرات الحيوية»). من شبكتك مباشرةً أو عبر الـVPN.
// الذوق: كروت بحدّ وأيقونة بمربّعٍ ملوّن، والقوائم الطويلة تنطوي (لا كرت يكبر بلا داعٍ).
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/util/clipboard_helper.dart';
import '../../../models/network_device.dart';
import '../../../services/devices_check.dart';
import '../../../services/devices_check_runner.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';
import '../widgets/_grade.dart';

class DevicesCheckScreen extends StatefulWidget {
  const DevicesCheckScreen({super.key, required this.devices, required this.viaVpn});

  final List<NetworkDevice> devices;
  final bool viaVpn;

  @override
  State<DevicesCheckScreen> createState() => _DevicesCheckScreenState();
}

class _DevicesCheckScreenState extends State<DevicesCheckScreen> {
  late final DevicesCheckRunner _run = DevicesCheckRunner(widget.devices, viaVpn: widget.viaVpn);
  CheckState? _filter;

  /// القسم المفتوح بعينه: `<المعرّف>:subs` أو `<المعرّف>:ports` — المالك ٦ نوفمبر: «من انقر توكل ع اي قسم يفتح كل الاقسام».
  final _open = <String>{};

  void _toggle(String key) => setState(() => _open.contains(key) ? _open.remove(key) : _open.add(key));

  @override
  void initState() {
    super.initState();
    _run.run();
  }

  @override
  void dispose() {
    _run.dispose();
    super.dispose();
  }

  static AppTone _stateTone(CheckState s) => switch (s) {
        CheckState.down => AppTone.danger,
        CheckState.warn => AppTone.warning,
        CheckState.unread => AppTone.neutral,
        CheckState.ok => AppTone.success,
      };

  static AppTone _levelTone(CheckLevel l) => switch (l) {
        CheckLevel.bad => AppTone.danger,
        CheckLevel.warn => AppTone.warning,
        CheckLevel.info => AppTone.info,
      };

  static IconData _roleIcon(CheckRole r) => switch (r) {
        CheckRole.router => LucideIcons.router,
        CheckRole.switcher => LucideIcons.network,
        CheckRole.sector => LucideIcons.radioTower,
        CheckRole.link => LucideIcons.radio,
        CheckRole.olt => LucideIcons.splitSquareVertical,
        CheckRole.other => LucideIcons.server,
      };

  List<DeviceCheckReport> get _reports => DevicesCheck.sorted(_run.reports.values);

  Future<void> _copyAll() async {
    final rs = _reports;
    if (rs.isEmpty) return;
    await copyToClipboard(context, DevicesCheck.reportText(rs, viaVpn: widget.viaVpn), label: 'تقرير الفحص');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('الفحص الشامل'),
        actions: [
          ListenableBuilder(
            listenable: _run,
            builder: (_, __) => Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(
                key: const ValueKey('check-copy'),
                tooltip: 'نسخ التقرير',
                onPressed: _run.running || _run.reports.isEmpty ? null : _copyAll,
                icon: const Icon(LucideIcons.copy, size: 20),
              ),
              IconButton(
                key: const ValueKey('check-again'),
                tooltip: 'أعد الفحص',
                onPressed: _run.running ? null : _run.run,
                icon: const Icon(LucideIcons.refreshCw, size: 20),
              ),
            ]),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: _run,
        builder: (context, _) {
          final rs = _reports;
          final shown = _filter == null ? rs : rs.where((r) => r.state == _filter).toList();
          return ListView(
            padding: const EdgeInsets.fromLTRB(Sp.md, Sp.md, Sp.md, Sp.xxl),
            children: [
              _head(rs),
              if (_run.error != null && !_run.running) ...[const SizedBox(height: Sp.sm), _errorBox()],
              if (rs.isNotEmpty) ...[const SizedBox(height: Sp.md), _counts(rs)],
              for (final r in shown) ...[const SizedBox(height: Sp.sm), _card(r)],
              if (!_run.running && rs.isEmpty && _run.error == null)
                Padding(
                  padding: const EdgeInsets.all(Sp.xl),
                  child: Text('لا أجهزة للفحص', textAlign: TextAlign.center, style: AppType.body(color: AppColors.textMid)),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _iconBox(IconData icon, AppTone tone, {double size = 40}) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: tone.softBg, borderRadius: BorderRadius.circular(R.icon), border: Border.all(color: tone.softBorder)),
        child: Icon(icon, size: size * 0.5, color: tone.fill),
      );

  BoxDecoration _cardDeco({Color? border}) => BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.card),
        border: Border.all(color: border ?? AppColors.border),
        boxShadow: [BoxShadow(color: AppColors.scrim.withValues(alpha: 0.06), blurRadius: 10, offset: const Offset(0, 3))],
      );

  Widget _head(List<DeviceCheckReport> rs) {
    final vpn = widget.viaVpn;
    final running = _run.running;
    final total = _run.total;
    final title = running
        ? 'يفحص أجهزتك…'
        : _run.error != null
            ? 'ما اكتمل الفحص'
            : 'فُحصت ${rs.length} ${rs.length == 1 ? 'جهاز' : 'أجهزة'}';
    return Container(
      key: const ValueKey('check-head'),
      padding: const EdgeInsets.all(Sp.md),
      decoration: _cardDeco(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          _iconBox(vpn ? LucideIcons.shieldCheck : LucideIcons.wifi, vpn ? AppTone.brand : AppTone.success),
          const SizedBox(width: Sp.sm),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: AppType.bodyStrong(color: AppColors.textHi)),
              const SizedBox(height: 2),
              Text(
                vpn ? 'عبر الـVPN — الخادم يفحصها وأنت بعيد' : 'من شبكتك — الجهاز نفسه، ومشتركو السكترات، ومنافذ السويجات',
                style: AppType.micro(color: AppColors.textMid),
              ),
            ]),
          ),
        ]),
        if (running) ...[
          const SizedBox(height: Sp.sm),
          ClipRRect(
            borderRadius: BorderRadius.circular(R.pill),
            child: LinearProgressIndicator(
              minHeight: 6,
              value: vpn || total == 0 ? null : _run.done / total,
              backgroundColor: AppColors.surfaceInput,
              color: AppColors.brand,
            ),
          ),
          const SizedBox(height: Sp.xs),
          Text(vpn ? (_run.line ?? 'يتّصل بالـVPN…') : 'يفحص ${_run.done} من $total…', style: AppType.micro(color: AppColors.textMid)),
        ],
      ]),
    );
  }

  Widget _errorBox() {
    const tone = AppTone.danger;
    return Container(
      padding: const EdgeInsets.all(Sp.md),
      decoration: BoxDecoration(color: tone.softBg, borderRadius: BorderRadius.circular(R.md), border: Border.all(color: tone.softBorder)),
      child: Row(children: [
        Icon(LucideIcons.triangleAlert, size: 18, color: tone.fill),
        const SizedBox(width: Sp.sm),
        Expanded(child: Text(_run.error!, maxLines: 3, overflow: TextOverflow.ellipsis, style: AppType.body(color: tone.onSoft))),
        TextButton(onPressed: _run.run, child: const Text('أعد المحاولة')),
      ]),
    );
  }

  Widget _counts(List<DeviceCheckReport> rs) {
    Widget chip(CheckState s) {
      final n = rs.where((r) => r.state == s).length;
      final tone = _stateTone(s);
      final on = _filter == s;
      final label = switch (s) {
        CheckState.down => 'طافي',
        CheckState.warn => 'ملاحظات',
        CheckState.unread => 'لم يُقرأ',
        CheckState.ok => 'سليم',
      };
      return InkWell(
        key: ValueKey('check-count-${s.name}'),
        borderRadius: BorderRadius.circular(R.pill),
        onTap: n == 0 && !on ? null : () => setState(() => _filter = on ? null : s),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: Sp.xs + 2),
          decoration: BoxDecoration(
            color: on ? tone.fill : tone.softBg,
            borderRadius: BorderRadius.circular(R.pill),
            border: Border.all(color: on ? tone.fill : tone.softBorder),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text('$n', style: AppType.bodyStrong(color: on ? AppColors.onBrand : tone.onSoft)),
            const SizedBox(width: Sp.xs),
            Text(label, style: AppType.label(color: on ? AppColors.onBrand : tone.onSoft)),
          ]),
        ),
      );
    }

    return Wrap(spacing: Sp.sm, runSpacing: Sp.sm, children: [for (final s in CheckState.values) chip(s)]);
  }

  Widget _pill(String text, AppTone tone) => Container(
        padding: const EdgeInsets.symmetric(horizontal: Sp.sm, vertical: 3),
        decoration: BoxDecoration(color: tone.softBg, borderRadius: BorderRadius.circular(R.pill), border: Border.all(color: tone.softBorder)),
        child: Text(text, style: AppType.label(color: tone.onSoft)),
      );

  Widget _card(DeviceCheckReport r) {
    final tone = _stateTone(r.state);
    final sub = [r.roleLabel, r.device.ip].where((x) => x.isNotEmpty).join(' · ');
    return Container(
      key: ValueKey('check-card-${r.device.id}'),
      decoration: _cardDeco(border: r.state == CheckState.ok ? null : tone.softBorder),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          // الضغط المطوّل ينسخ تقرير الجهاز؛ والفتح لكلّ قسمٍ بزرّه وحده
          onLongPress: () => copyToClipboard(context, r.toText(), label: 'تقرير ${r.device.name}'),
          child: Padding(
            padding: const EdgeInsets.all(Sp.md),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                _iconBox(_roleIcon(r.role), tone),
                const SizedBox(width: Sp.sm),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(r.device.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.bodyStrong(color: AppColors.textHi)),
                    const SizedBox(height: 2),
                    Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.micro(color: AppColors.textMid)),
                  ]),
                ),
                const SizedBox(width: Sp.xs),
                _pill(r.stateLabel, tone),
              ]),
              if (r.vitals.isNotEmpty) ...[
                const SizedBox(height: Sp.sm),
                Wrap(spacing: Sp.xs, runSpacing: Sp.xs, children: [for (final v in r.vitals) _vital(v.k, v.v)]),
              ],
              if (r.findings.isNotEmpty) ...[
                const SizedBox(height: Sp.sm),
                for (final f in r.findings) _finding(f),
              ],
              if ((r.role == CheckRole.sector || r.role == CheckRole.olt) && r.subs.isNotEmpty) _subs(r),
              if (r.ports.isNotEmpty) _ports(r),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _vital(String k, String v) => Container(
        padding: const EdgeInsets.symmetric(horizontal: Sp.sm, vertical: 4),
        decoration: BoxDecoration(color: AppColors.surfaceInput, borderRadius: BorderRadius.circular(R.sm)),
        child: Text.rich(TextSpan(children: [
          TextSpan(text: '$k ', style: AppType.micro(color: AppColors.textMid)),
          TextSpan(text: v, style: AppType.label(color: AppColors.textHi)),
        ])),
      );

  Widget _finding(CheckFinding f) {
    final tone = _levelTone(f.level);
    return Padding(
      padding: const EdgeInsets.only(top: Sp.xs),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Container(width: 8, height: 8, decoration: BoxDecoration(color: tone.fill, shape: BoxShape.circle)),
        ),
        const SizedBox(width: Sp.sm),
        Expanded(child: Text(f.text, maxLines: 3, overflow: TextOverflow.ellipsis, style: AppType.body(color: AppColors.textBody))),
      ]),
    );
  }

  Widget _sectionHead(IconData icon, String text) => Padding(
        padding: const EdgeInsets.only(top: Sp.md, bottom: Sp.xs),
        child: Row(children: [
          Icon(icon, size: 15, color: AppColors.textMid),
          const SizedBox(width: Sp.xs),
          Expanded(child: Text(text, style: AppType.label(color: AppColors.textMid))),
        ]),
      );

  Widget _more(String key, bool open, int hidden, String what) => Align(
        alignment: AlignmentDirectional.centerStart,
        child: TextButton.icon(
          key: ValueKey('check-more-$key'),
          onPressed: () => _toggle(key),
          icon: Icon(open ? LucideIcons.chevronUp : LucideIcons.chevronDown, size: 16),
          label: Text(open ? 'إخفاء' : 'عرض $what ($hidden)'),
        ),
      );

  Widget _subs(DeviceCheckReport r) {
    final key = '${r.device.id}:subs';
    final open = _open.contains(key);
    final bad = r.subs.where((s) => s.bad).toList();
    final shown = open ? r.subs : bad.take(3).toList();
    final olt = r.role == CheckRole.olt;
    final head = olt
        ? 'المشتركون (ONU) ${r.subs.length}${r.subsBad > 0 ? ' — ${r.subsBad} ضوءهم ضعيف' : ' — ضوءهم كلّه جيّد'}'
        : 'المشتركون ${r.subs.length}${r.subsBad > 0 ? ' — ${r.subsBad} فيهم مشكلة' : ' — كلّهم بخير'}';
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _sectionHead(LucideIcons.users, head),
      for (final s in shown) _subRow(s),
      if (r.subs.length > shown.length || open) _more(key, open, r.subs.length - shown.length, 'كلّ المشتركين'),
    ]);
  }

  Widget _subRow(CheckSub s) {
    final sigTone = s.weak ? AppTone.warning : (s.light != null ? AppTone.success : Grade.signal(s.signal));
    return Container(
      margin: const EdgeInsets.only(bottom: Sp.xs),
      padding: const EdgeInsets.symmetric(horizontal: Sp.sm, vertical: Sp.xs + 2),
      decoration: BoxDecoration(
        color: s.bad ? AppTone.warning.softBg : AppColors.surfaceSunken,
        borderRadius: BorderRadius.circular(R.sm),
      ),
      child: Row(children: [
        Expanded(child: Text(s.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.body(color: AppColors.textHi))),
        if (s.light != null) ...[
          const SizedBox(width: Sp.xs),
          Directionality(
            textDirection: TextDirection.ltr,
            child: Text('${s.light!.toStringAsFixed(1)} dBm', style: AppType.label(color: sigTone.fill)),
          ),
        ],
        if (s.signal != null) ...[
          const SizedBox(width: Sp.xs),
          // إشارته من جهتنا (عليها الحكم) وتحتها ما نستقبله منه (rx) — المالك: «او تظهرهن الاثنين»
          Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
            Directionality(
              textDirection: TextDirection.ltr,
              child: Text('${s.signal} dBm', style: AppType.label(color: sigTone.fill)),
            ),
            if (s.rxSignal != null && s.rxSignal != s.signal)
              Directionality(
                textDirection: TextDirection.ltr,
                child: Text('rx ${s.rxSignal}', style: AppType.micro(color: AppColors.textMid)),
              ),
          ]),
        ],
        if (s.ccq != null) ...[
          const SizedBox(width: Sp.xs),
          _pill('CCQ ${s.ccq}٪', s.lowCcq ? AppTone.warning : AppTone.success),
        ],
        if (s.rxRate != null || s.txRate != null) ...[
          const SizedBox(width: Sp.xs),
          // كبطاقة الجهاز الكبيرة: ↓الاستقبال ↑الإرسال ثمّ Mbps (المالك ٦ نوفمبر: «مابيها Mbps بس ارقام») — يصغر على الضيّق
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerEnd,
              child: Directionality(
                textDirection: TextDirection.ltr,
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  if (s.rxRate != null) ...[
                    Icon(LucideIcons.arrowDown, size: 10, color: AppColors.chartLine),
                    Text('${s.rxRate}', style: AppType.microBold(color: AppColors.textHi)),
                  ],
                  if (s.rxRate != null && s.txRate != null) const SizedBox(width: 4),
                  if (s.txRate != null) ...[
                    Icon(LucideIcons.arrowUp, size: 10, color: AppColors.info),
                    Text('${s.txRate}', style: AppType.microBold(color: AppColors.textHi)),
                  ],
                  Text(' Mbps', style: AppType.micro(color: AppColors.textLow)),
                ]),
              ),
            ),
          ),
        ],
      ]),
    );
  }

  Widget _ports(DeviceCheckReport r) {
    final key = '${r.device.id}:ports';
    final open = _open.contains(key);
    final flagged = r.ports.where((p) => p.flagged).toList();
    final shown = open ? r.ports : flagged.take(4).toList();
    final head = 'المنافذ ${r.portsUp ?? 0}/${r.portsTotal ?? r.ports.length} شغّالة'
        '${flagged.isEmpty ? '' : ' — ${flagged.length} فيها ملاحظات'}';
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _sectionHead(LucideIcons.cable, head),
      for (final p in shown) _portRow(p),
      if (r.ports.length > shown.length || open) _more(key, open, r.ports.length - shown.length, 'كلّ المنافذ'),
    ]);
  }

  Widget _portRow(CheckPort p) {
    final tone = p.level == null ? (p.up ? AppTone.success : AppTone.neutral) : _levelTone(p.level!);
    return Container(
      margin: const EdgeInsets.only(bottom: Sp.xs),
      padding: const EdgeInsets.symmetric(horizontal: Sp.sm, vertical: Sp.xs + 2),
      decoration: BoxDecoration(
        color: p.flagged ? tone.softBg : AppColors.surfaceSunken,
        borderRadius: BorderRadius.circular(R.sm),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(color: p.up ? AppColors.success : AppColors.textLow, shape: BoxShape.circle)),
          const SizedBox(width: Sp.sm),
          Directionality(
            textDirection: TextDirection.ltr,
            child: Text(p.name, style: AppType.label(color: AppColors.textHi)),
          ),
          const Spacer(),
          Text(p.up ? (p.speed ?? 'شغّال') : 'طافي', style: AppType.micro(color: AppColors.textMid)),
        ]),
        for (final n in p.notes)
          Padding(
            padding: const EdgeInsetsDirectional.only(start: Sp.md + 4, top: 2),
            child: Text(n, style: AppType.micro(color: tone.onSoft)),
          ),
      ]),
    );
  }
}
