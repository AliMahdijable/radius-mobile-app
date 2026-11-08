// «الفحص الشامل» — تقريرٌ منفصل لكلّ جهاز (المالك ٦ نوفمبر: «من يكون الجهاز ع شكل سكتر يفحص الجهاز نفسه ويفحص المشتركين الي
// بداخلة ويعطي تقرير منفصل لكل جهاز» · «كذلك السوجات من حيث المتغيرات الحيوية»). من شبكتك مباشرةً أو عبر الـVPN.
// الذوق: كروت بحدّ وأيقونة بمربّعٍ ملوّن، والقوائم الطويلة تنطوي (لا كرت يكبر بلا داعٍ).
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/util/clipboard_helper.dart';
import '../../../models/network_device.dart';
import '../../../services/devices_check.dart';
import '../../../services/devices_check_runner.dart';
import '../../../services/merged_devices_check.dart';
import '../../../widgets/company_tag.dart';
import '../../../services/notification_router.dart';
import '../../subscribers/subscriber_detail_screen.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';
import '../widgets/_grade.dart';

class DevicesCheckScreen extends StatefulWidget {
  const DevicesCheckScreen({super.key, required this.devices, required this.viaVpn, this.onOpenFull, this.runner});

  final List<NetworkDevice> devices;
  final bool viaVpn;

  /// «كل الشركات»: الفاحص المدموج (MergedDevicesCheckRunner) — أجهزة كلّ شركةٍ بطريقها، وبطاقة «الشركات» بحال كلٍّ منها. الشاشة
  /// تملكه وتتخلّص منه.
  final DevicesCheckRunner? runner;

  /// جهازٌ واحد بوضع VPN (٧ نوفمبر — المالك: «بوضع vpn… من يفوت لكارت الجهاز كلشي ميظهر»): الضغط على الجهاز بالقائمة يفتح تقريره
  /// عبر الـVPN هنا بدل صفحته الحيّة (تتّصل بالجهاز من الهاتف فلا تصله خارج الشبكة) — و«الصفحة الكاملة» لتعديله.
  final VoidCallback? onOpenFull;

  /// «صفحة الجهاز عبر الـVPN» (فُتحت من الجهاز نفسه) — لا الفحص الشامل لحسابٍ له جهازٌ واحد.
  bool get single => onOpenFull != null && devices.length == 1;

  @override
  State<DevicesCheckScreen> createState() => _DevicesCheckScreenState();
}

class _DevicesCheckScreenState extends State<DevicesCheckScreen> {
  late final DevicesCheckRunner _run = widget.runner ?? DevicesCheckRunner(widget.devices, viaVpn: widget.viaVpn);

  /// «كل الشركات» — null خارجها.
  MergedDevicesCheckRunner? get _merged {
    final r = _run;
    return r is MergedDevicesCheckRunner ? r : null;
  }
  CheckState? _filter;

  /// «كل الشركات»: شركةٌ مختارة من بطاقة «الشركات» ⇒ أجهزتها وحدها وعدّاداتها (٨ نوفمبر — المالك: «خلي امكانيه ان ينقر ع الشركه
  /// ويعرض بس الاجهزه بعد نتيجه الفحص»). الضغط ثانيةً يعيد الكلّ.
  String? _company;

  /// تقارير الشركة المختارة وحدها (أو الكلّ).
  List<DeviceCheckReport> _scoped(List<DeviceCheckReport> rs) {
    final m = _merged;
    final k = _company;
    if (m == null || k == null) return rs;
    return [for (final r in rs) if (m.companyOf[r.device.id] == k) r];
  }

  void _pickCompany(String key) => setState(() {
        _company = _company == key ? null : key;
        _filter = null;
      });

  /// القسم المفتوح بعينه: `<المعرّف>:subs` أو `<المعرّف>:ports` — المالك ٦ نوفمبر: «من انقر توكل ع اي قسم يفتح كل الاقسام».
  final _open = <String>{};

  void _toggle(String key) => setState(() => _open.contains(key) ? _open.remove(key) : _open.add(key));

  @override
  void initState() {
    super.initState();
    // جهازٌ واحد: أقسامه مفتوحة (لا قائمة أجهزةٍ يُختصر لها)
    if (widget.single) _open.addAll(['${widget.devices.first.id}:subs', '${widget.devices.first.id}:ports']);
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
    final m = _merged;
    if (m == null) {
      await copyToClipboard(context, DevicesCheck.reportText(rs, viaVpn: widget.viaVpn), label: 'تقرير الفحص');
      return;
    }
    // «كل الشركات»: تقرير كلّ شركةٍ تحت اسمها، وسطر من لم تُفحص ولماذا — والمختارة وحدها إن اختيرت
    final parts = <String>[];
    for (final s in m.states.values) {
      if (_company != null && s.part.company.key != _company) continue;
      final mine = [for (final r in rs) if (m.companyOf[r.device.id] == s.part.company.key) r];
      final head = '— ${s.part.company.name} —';
      if (mine.isEmpty) {
        if (s.message != null) parts.add('$head\n${s.message}');
        continue;
      }
      parts.add('$head\n${DevicesCheck.reportText(mine, viaVpn: s.viaVpn)}');
    }
    if (!mounted) return;
    await copyToClipboard(context, parts.join('\n\n'), label: 'تقرير الفحص');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: Text(widget.single ? widget.devices.first.name : 'الفحص الشامل', maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          if (widget.onOpenFull != null)
            IconButton(
              key: const ValueKey('check-open-full'),
              tooltip: 'الصفحة الكاملة (التعديل)',
              onPressed: widget.onOpenFull,
              icon: const Icon(LucideIcons.settings2, size: 20),
            ),
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
          final scoped = _scoped(rs);
          final shown = _filter == null ? scoped : scoped.where((r) => r.state == _filter).toList();
          return ListView(
            padding: const EdgeInsets.fromLTRB(Sp.md, Sp.md, Sp.md, Sp.xxl),
            children: [
              _head(rs),
              if (_merged != null) ...[const SizedBox(height: Sp.sm), _companies(_merged!, rs)],
              if (_run.error != null && !_run.running) ...[const SizedBox(height: Sp.sm), _errorBox()],
              if (rs.isNotEmpty && !widget.single) ...[const SizedBox(height: Sp.md), _counts(scoped)],
              for (final r in shown) ...[const SizedBox(height: Sp.sm), _card(r)],
              // يردّ عبر الـVPN ولا معلومات: السبب بكلمة (لا صفحةٌ فارغة بلا تفسير)
              if (widget.single && widget.viaVpn && !_run.running && rs.length == 1 && rs.first.vitals.isEmpty &&
                  rs.first.state != CheckState.down) ...[
                const SizedBox(height: Sp.sm),
                Text(
                  'عبر الـVPN وصلنا الجهاز ويردّ، بس معلوماته الحيّة ما انقرت — للمايكروتك تحتاج خدمة API مفعّلة بالراوتر، ولليوبيكويتي '
                  'يوزر وباسورد الويب الصحيحين (من «الصفحة الكاملة» ⇐ التعديل).',
                  key: const ValueKey('check-no-vitals'),
                  style: AppType.muted(color: AppColors.textMid),
                ),
              ],
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
        decoration:
            BoxDecoration(color: tone.softBg, borderRadius: BorderRadius.circular(R.icon), border: Border.all(color: tone.softBorder)),
        child: Icon(icon, size: size * 0.5, color: tone.fill),
      );

  BoxDecoration _cardDeco({Color? border}) => BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.card),
        border: Border.all(color: border ?? AppColors.border),
        boxShadow: [BoxShadow(color: AppColors.scrim.withValues(alpha: 0.06), blurRadius: 10, offset: const Offset(0, 3))],
      );

  Widget _head(List<DeviceCheckReport> rs) {
    final merged = _merged != null;
    final vpn = widget.viaVpn && !merged;
    final running = _run.running;
    final total = _run.total;
    final title = running
        ? (widget.single ? 'يقرأ الجهاز…' : 'يفحص أجهزتك…')
        : _run.error != null
            ? 'ما اكتمل الفحص'
            : widget.single
                ? 'قُرئ الجهاز'
                : 'فُحصت ${rs.length} ${rs.length == 1 ? 'جهاز' : 'أجهزة'}';
    return Container(
      key: const ValueKey('check-head'),
      padding: const EdgeInsets.all(Sp.md),
      decoration: _cardDeco(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          _iconBox(merged ? LucideIcons.layers : (vpn ? LucideIcons.shieldCheck : LucideIcons.wifi),
              vpn || merged ? AppTone.brand : AppTone.success),
          const SizedBox(width: Sp.sm),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: AppType.bodyStrong(color: AppColors.textHi)),
              const SizedBox(height: 2),
              Text(
                merged
                    ? 'كل الشركات — كلّ شركةٍ بطريقها'
                    : vpn
                        ? (widget.single ? 'عبر الـVPN — الخادم يقرؤه وأنت بعيد' : 'عبر الـVPN — الخادم يفحصها وأنت بعيد')
                        : 'من شبكتك — الجهاز نفسه، ومشتركو السكترات، ومنافذ السويجات',
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
              value: (vpn && !merged) || total == 0 ? null : _run.done / total,
              backgroundColor: AppColors.surfaceInput,
              color: AppColors.brand,
            ),
          ),
          const SizedBox(height: Sp.xs),
          Text(
              merged
                  ? (_run.line ?? 'يفحص ${_run.done} من $total…')
                  : vpn
                      ? (_run.line ?? 'يتّصل بالـVPN…')
                      : 'يفحص ${_run.done} من $total…',
              style: AppType.micro(color: AppColors.textMid)),
        ],
      ]),
    );
  }

  /// «كل الشركات»: سطرٌ لكلّ شركة — طريقها وعدد أجهزتها، أو لماذا لم تُفحص (بلا VPN تُسمّى، لا «طافية»). شركةٌ لها نتائج تُضغط
  /// فتُعرض أجهزتها وحدها.
  Widget _companies(MergedDevicesCheckRunner m, List<DeviceCheckReport> rs) {
    final withResults = <String>{for (final r in rs) if (m.companyOf[r.device.id] != null) m.companyOf[r.device.id]!};
    final picked = _company == null ? null : m.states[_company]?.part.company;
    final hint = picked != null
        ? '«${picked.name}» وحدها — اضغطها ثانيةً لعرض الكلّ'
        : (withResults.length > 1 ? 'اضغط شركةً لعرض أجهزتها وحدها' : null);
    return Container(
      key: const ValueKey('check-companies'),
      padding: const EdgeInsets.symmetric(horizontal: Sp.sm, vertical: Sp.sm),
      decoration: _cardDeco(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final s in m.states.values) _companyRow(s, tappable: withResults.contains(s.part.company.key)),
        if (hint != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(Sp.sm, Sp.xs, Sp.sm, 0),
            child: Row(children: [
              Icon(picked != null ? LucideIcons.filter : LucideIcons.mousePointerClick, size: 13, color: AppColors.textLow),
              const SizedBox(width: Sp.x6),
              Expanded(
                child: Text(hint,
                    key: const ValueKey('check-companies-hint'),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.micro(color: AppColors.textMid)),
              ),
            ]),
          ),
      ]),
    );
  }

  Widget _companyRow(MergedCheckCompanyState s, {bool tappable = false}) {
    final c = s.part.company;
    final on = _company == c.key;
    final n = s.part.devices.length;
    final count = '$n ${n == 1 ? 'جهاز' : 'أجهزة'}';
    final (IconData icon, AppTone tone, String text) = switch (s.status) {
      MergedCheckStatus.waiting => (LucideIcons.hourglass, AppTone.neutral, 'بانتظار دورها · $count'),
      MergedCheckStatus.running => (LucideIcons.loader, AppTone.brand, '${s.viaVpn ? 'تُفحص عبر VPN الشركة' : 'تُفحص من شبكتك'}… · $count'),
      MergedCheckStatus.done => (
          LucideIcons.circleCheck,
          AppTone.success,
          '${s.viaVpn ? 'عبر VPN الشركة' : 'من شبكتك'} · $count${s.defaultLimits ? ' · بالحدود الافتراضيّة (تعذّرت قراءة إعداداتها)' : ''}'
        ),
      MergedCheckStatus.noVpn => (LucideIcons.shieldOff, AppTone.warning, s.message ?? 'تحتاج VPN للفحص الشامل'),
      MergedCheckStatus.failed => (LucideIcons.triangleAlert, AppTone.danger, s.message ?? 'تعذّر الفحص'),
    };
    return Material(
      key: ValueKey('check-company-${c.key}'),
      color: on ? AppTone.brand.softBg : Colors.transparent,
      borderRadius: BorderRadius.circular(R.md),
      child: InkWell(
        borderRadius: BorderRadius.circular(R.md),
        onTap: tappable || on ? () => _pickCompany(c.key) : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: Sp.sm, vertical: Sp.xs + 2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(R.md),
            border: Border.all(color: on ? AppTone.brand.softBorder : Colors.transparent),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Container(
                  width: 8, height: 8, decoration: BoxDecoration(color: AppColors.company(c.colorIndex), shape: BoxShape.circle)),
            ),
            const SizedBox(width: Sp.sm),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(c.name, style: AppType.bodyStrong(color: AppColors.textHi)),
                const SizedBox(height: 2),
                Text(text, style: AppType.micro(color: s.status == MergedCheckStatus.done ? AppColors.textMid : tone.onSoft)),
              ]),
            ),
            const SizedBox(width: Sp.sm),
            if (on) ...[
              _pill('معروضة', AppTone.brand),
              const SizedBox(width: Sp.x6),
            ],
            Icon(icon, size: 18, color: s.status == MergedCheckStatus.waiting ? AppColors.textLow : tone.fill),
          ]),
        ),
      ),
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
        decoration:
            BoxDecoration(color: tone.softBg, borderRadius: BorderRadius.circular(R.pill), border: Border.all(color: tone.softBorder)),
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
                    // «كل الشركات»: شركة الجهاز
                    if (_merged?.companyOf[r.device.id] case final key?) ...[
                      const SizedBox(height: 3),
                      CompanyTag(companyKey: key),
                    ],
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
      for (final s in shown) _subRow(s, r.device.id),
      if (r.subs.length > shown.length || open) _more(key, open, r.subs.length - shown.length, 'كلّ المشتركين'),
    ]);
  }

  /// النقر: صفحة المشترك المطابق بماك جلسته، وإلّا نسخ الماك؛ والضغط المطوّل ينسخ الماك دائماً — المالك ٦ نوفمبر: «لازم تفعل
  /// امكانيه نسخ الماك حتى يعرف وين يحدد او النقر عليه يفتحله اليوزر المشابه ونفس الشي للسكاتر».
  Future<void> _tapSub(CheckSub s, int deviceId) async {
    final user = s.user;
    if (user == null) return _copyMac(s);
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    // «كل الشركات»: مشترك جهاز شركةٍ أخرى من قائمة شركته (موجَّهاً لها) — لا بحث في المفتوحة: اليوزر نفسه قد يكون فيها لغيره
    final sub = _run.subscriberOn(deviceId, user) ??
        (_run.isRemote(deviceId) ? null : await NotificationRouter.findSubscriber(user));
    if (sub == null) {
      messenger?.showSnackBar(SnackBar(content: Text('تعذّر فتح «$user» الآن — ابحث عنه من «المشتركين»')));
      return;
    }
    await nav.push(MaterialPageRoute<void>(builder: (_) => SubscriberDetailScreen(sub: sub), fullscreenDialog: true));
  }

  Future<void> _copyMac(CheckSub s) async {
    final m = s.mac;
    await copyToClipboard(context, m == null ? s.title : DevicesCheck.fmtMac(m), label: m == null ? 'الاسم' : 'الماك');
  }

  Widget _subRow(CheckSub s, int deviceId) {
    final sigTone = s.weak ? AppTone.warning : (s.light != null ? AppTone.success : Grade.signal(s.signal));
    final mac = s.mac == null ? null : DevicesCheck.fmtMac(s.mac!);
    final showMac = mac != null && mac.toLowerCase() != s.title.toLowerCase();
    return Container(
      margin: const EdgeInsets.only(bottom: Sp.xs),
      decoration: BoxDecoration(
        color: s.bad ? AppTone.warning.softBg : AppColors.surfaceSunken,
        borderRadius: BorderRadius.circular(R.sm),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: ValueKey('check-sub-${s.mac ?? s.name}'),
          onTap: () => _tapSub(s, deviceId),
          onLongPress: () => _copyMac(s),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Sp.sm, vertical: Sp.xs + 2),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Row(children: [
                    if (s.user != null) ...[
                      Icon(LucideIcons.userCheck, size: 13, color: s.approx ? AppColors.warning : AppColors.success),
                      const SizedBox(width: 3),
                    ],
                    Flexible(
                      child: Text(s.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.body(color: AppColors.textHi)),
                    ),
                  ]),
                  if (showMac)
                    Text(
                      '\u2066$mac\u2069${s.approx ? ' · ماكٌ مشابه' : ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.micro(color: AppColors.textMid),
                    ),
                ]),
              ),
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
          ),
        ),
      ),
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
          Container(
              width: 8, height: 8, decoration: BoxDecoration(color: p.up ? AppColors.success : AppColors.textLow, shape: BoxShape.circle)),
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
