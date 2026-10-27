import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/util/bidi.dart';
import '../../../models/subscriber.dart';
import '../../../services/fiber/fiber_diagnosis.dart';
import '../../../services/fiber/fiber_light.dart';
import '../../../services/fiber/fiber_monitor.dart';
import '../../../services/fiber/fiber_onu.dart';
import '../../../services/fiber/fiber_store.dart';
import '../../../services/fiber/fiber_subs.dart';
import '../../../services/fiber/fiber_text.dart';
import '../../../services/fiber/fiber_tree.dart';
import '../../../services/manual_wa_sender.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';
import '../../desktop/desk_widgets.dart';
import '../../subscribers/subscriber_detail_screen.dart';
import 'fiber_home_screen.dart';
import 'fiber_link_screen.dart';
import 'fiber_outage_screen.dart';
import 'fiber_sheets.dart';
import 'fiber_tech_screen.dart';
import 'fiber_widgets.dart';

/// «تشخيص المشترك» — المشترك يتّصل «النت طافي»: بنظرةٍ واحدة الاشتراك ثمّ جهاز الألياف ثمّ الضوء ثمّ الراوتر.
class FiberDiagnosisScreen extends StatefulWidget {
  const FiberDiagnosisScreen({super.key, required this.monitor, this.onuKey, this.subscriber});

  final FiberMonitor monitor;
  final String? onuKey;
  final Subscriber? subscriber;

  @override
  State<FiberDiagnosisScreen> createState() => _FiberDiagnosisScreenState();
}

class _FiberDiagnosisScreenState extends State<FiberDiagnosisScreen> {
  FiberMonitor get _m => widget.monitor;
  Subscriber? _sub;
  bool _subLoading = false;

  @override
  void initState() {
    super.initState();
    _sub = widget.subscriber;
    _m
      ..addListener(_changed)
      ..acquire();
    FiberStore.layout.addListener(_changed);
    _loadSub();
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

  String? get _username {
    if (widget.subscriber != null) return widget.subscriber!.username;
    final o = _onu;
    if (o == null) return null;
    return FiberStore.layout.value.recordFor(_m.oltId, o.key, o.ident)?.username;
  }

  FiberOnuLive? get _onu {
    final layout = FiberStore.layout.value;
    if (widget.onuKey != null) {
      return _m.onus.where((o) => o.key == widget.onuKey).firstOrNull;
    }
    final u = widget.subscriber?.username.toLowerCase();
    if (u == null) return null;
    for (final o in _m.onus) {
      if (layout.recordFor(_m.oltId, o.key, o.ident)?.username?.toLowerCase() == u) return o;
    }
    return null;
  }

  Future<void> _loadSub() async {
    final u = _username;
    if (u == null) return;
    setState(() => _subLoading = true);
    final got = await FiberSubs.byUsernames([u]);
    if (!mounted) return;
    setState(() {
      _sub = got[u.toLowerCase()] ?? _sub;
      _subLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final layout = FiberStore.layout.value;
    final onu = _onu;
    final sub = _sub;
    final rec = onu == null ? null : layout.recordFor(_m.oltId, onu.key, onu.ident);
    final tree = onu == null ? null : FiberPonTree.build(oltId: _m.oltId, pon: onu.pon, layout: layout, onus: _m.onus);
    final boxId = onu == null ? null : tree!.boxOfKey[onu.key];
    final neighbours = boxId == null ? const <FiberOnuLive>[] : tree!.onusUnder(boxId).where((o) => o.key != onu!.key).toList();
    final inOutage = onu != null && _m.outages.any((e) => e.onuKeys.contains(onu.key));
    final d = FiberDiagnose.of(
      sub: sub == null ? null : FiberSubs.facts(sub),
      subUnknown: _username == null
          ? 'غير مربوط بمشترك'
          : (_subLoading ? 'يقرأ حسابه من الساس…' : 'ما قدرنا نقرأ حسابه من الساس'),
      onu: onu,
      inOutage: inOutage,
      boxOnline: neighbours.where((o) => o.online).length,
      boxTotal: neighbours.length,
    );
    final title = sub == null
        ? (onu == null ? 'تشخيص' : fiberOnuTitle(layout, _m.oltId, onu))
        : (sub.fullName.trim().isEmpty ? sub.username : sub.fullName.trim());
    final subtitle = [
      if (sub != null) sub.username,
      if (boxId != null) layout.boxes[boxId]!.name,
      if (onu != null) fiberPonDisplay(onu.pon),
    ].join(' · ');
    final phone = (sub?.mobile ?? sub?.phone)?.trim();
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: deskPageBar(
        context,
        title: title,
        subtitle: subtitle,
        mobile: AppBar(
          title: Text(iso(title), maxLines: 1, overflow: TextOverflow.ellipsis),
          backgroundColor: AppColors.surface,
          foregroundColor: AppColors.textHi,
          elevation: 0,
          leading: IconButton(icon: const Icon(LucideIcons.arrowRight, size: 20), onPressed: () => Navigator.pop(context)),
          actions: [
            if (phone != null && phone.isNotEmpty) ...[
              IconButton(
                tooltip: 'اتصل',
                icon: const Icon(LucideIcons.phone, size: 20),
                onPressed: () => launchUrl(Uri(scheme: 'tel', path: phone)),
              ),
              IconButton(
                tooltip: 'واتساب',
                icon: const Icon(LucideIcons.messageCircle, size: 20, color: AppColors.channelWhatsApp),
                onPressed: () => openManualWa(phone: phone, message: '', context: context),
              ),
            ],
          ],
        ),
      ),
      body: FiberPage(
        maxWidth: 820,
        onRefresh: () async {
          await _m.refreshNow();
          await _loadSub();
        },
        children: [
          if (subtitle.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, 0),
              child: Text(iso(subtitle), style: AppType.body(color: AppColors.textMid), maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          if (_m.error != null) FiberNotice(text: _m.error!, tone: AppTone.danger, onRetry: _m.refreshNow, icon: LucideIcons.wifiOff),
          if (_subLoading && sub == null) const FiberNotice(text: 'يقرأ حساب المشترك من الساس…', tone: AppTone.info),
          _verdict(d, onu, sub, boxId),
          _chain(d),
          if (onu != null) _fiberCard(onu, boxId),
          if (onu != null && boxId != null) _neighbours(layout.boxes[boxId]!.name, onu, neighbours),
          if (onu != null && rec?.username == null && fiberCanEdit())
            Padding(
              padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, 0),
              child: OutlinedButton.icon(
                onPressed: () async {
                  await showFiberLinkPicker(context, monitor: _m, onu: onu);
                  await _loadSub();
                },
                icon: const Icon(LucideIcons.link, size: 16),
                label: const Text('اربط هذا الجهاز بمشترك'),
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(44)),
              ),
            ),
        ],
      ),
    );
  }

  AppTone _tone(FiberVerdictKind k) => switch (k) {
        FiberVerdictKind.fiberHome || FiberVerdictKind.outage || FiberVerdictKind.onuDown => AppTone.danger,
        FiberVerdictKind.power || FiberVerdictKind.subscription || FiberVerdictKind.weakLight => AppTone.warning,
        FiberVerdictKind.router || FiberVerdictKind.noOnu || FiberVerdictKind.onuOnly => AppTone.info,
        FiberVerdictKind.allGood => AppTone.success,
      };

  IconData _icon(FiberVerdictKind k) => switch (k) {
        FiberVerdictKind.power => LucideIcons.plug,
        FiberVerdictKind.fiberHome || FiberVerdictKind.outage => LucideIcons.scissors,
        FiberVerdictKind.onuDown => LucideIcons.unplug,
        FiberVerdictKind.subscription => LucideIcons.clock,
        FiberVerdictKind.weakLight => LucideIcons.sunDim,
        FiberVerdictKind.router => LucideIcons.router,
        FiberVerdictKind.allGood => LucideIcons.circleCheck,
        FiberVerdictKind.noOnu => LucideIcons.link2Off,
        FiberVerdictKind.onuOnly => LucideIcons.cable,
      };

  Widget _verdict(FiberDiagnosis d, FiberOnuLive? onu, Subscriber? sub, int? boxId) {
    final tone = _tone(d.kind);
    final phone = (sub?.mobile ?? sub?.phone)?.trim();
    final hasPhone = phone != null && phone.isNotEmpty;
    final actions = <(String, IconData, VoidCallback)>[];
    void tech() => Navigator.of(context).push(MaterialPageRoute(builder: (_) => FiberTechScreen(monitor: _m, onuKey: onu?.key)));
    void wa(String msg) => openManualWa(phone: phone!, message: msg, context: context);
    switch (d.kind) {
      case FiberVerdictKind.router:
        if (hasPhone) {
          actions.add(('أرسل له خطوات إعادة التشغيل', LucideIcons.messageCircle, () => wa(
              'مشتركنا العزيز، الخطّ عندك سليم. رجاءً طفّي الراوتر دقيقة وشغّله، وإذا ما رجع النت تأكّد من سلك الراوتر وابلغنا.')));
        }
        actions.add(('افتح وضع الفنّي', LucideIcons.wrench, tech));
      case FiberVerdictKind.fiberHome:
      case FiberVerdictKind.onuDown:
        actions.add(('وضع الفنّي', LucideIcons.wrench, tech));
        if (hasPhone) actions.add(('طمّن المشترك', LucideIcons.messageCircle, () => wa('مشتركنا العزيز، شفنا الخلل بخطّك والفنّي راح يتواصل وياك قريباً.')));
      case FiberVerdictKind.power:
        if (hasPhone) actions.add(('طمّنه بالواتساب', LucideIcons.messageCircle, () => wa('مشتركنا العزيز، جهاز الإنترنت عندك طافي لانقطاع الكهرباء. يرجع النت وحده لمّا ترجع الكهرباء.')));
      case FiberVerdictKind.outage:
        final e = _m.outages.where((x) => onu != null && x.onuKeys.contains(onu.key)).firstOrNull;
        if (e != null) {
          actions.add(('افتح العطل', LucideIcons.scissors,
              () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => FiberOutageScreen(monitor: _m, scopeKey: e.scopeKey)))));
        }
        if (hasPhone) actions.add(('طمّن المشترك', LucideIcons.messageCircle, () => wa('مشتركنا العزيز، صار عطل بخطّ الألياف بمنطقتكم والفنّي يشتغل عليه.')));
      case FiberVerdictKind.subscription:
        if (sub != null) {
          actions.add(('افتح صفحة المشترك', LucideIcons.userRound,
              () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => SubscriberDetailScreen(sub: sub)))));
        }
        if (hasPhone) actions.add(('أرسل له تذكيراً', LucideIcons.messageCircle, () => wa('مشتركنا العزيز، اشتراكك منتهي. جدّده حتى يرجع النت.')));
      case FiberVerdictKind.weakLight:
        actions.add(('افتح وضع الفنّي', LucideIcons.wrench, tech));
      case FiberVerdictKind.allGood:
      case FiberVerdictKind.onuOnly:
        if (onu != null) actions.add(('وضع الفنّي', LucideIcons.wrench, tech));
      case FiberVerdictKind.noOnu:
        break;
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, 0),
      child: Container(
        padding: const EdgeInsets.all(Sp.lg),
        decoration: BoxDecoration(
          color: tone.softBg,
          borderRadius: BorderRadius.circular(R.lg),
          border: Border.all(color: tone.softBorder),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(R.md)),
              child: Icon(_icon(d.kind), size: 22, color: tone.fill),
            ),
            const SizedBox(width: Sp.md),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('التشخيص', style: AppType.labelBold(color: tone.onSoft)),
                Text(d.title, style: AppType.sheetTitle(color: AppColors.textHi), maxLines: 2, overflow: TextOverflow.ellipsis),
              ]),
            ),
          ]),
          const SizedBox(height: Sp.sm),
          Text(iso(d.body), style: AppType.body(color: AppColors.textBody)),
          if (actions.isNotEmpty) ...[
            const SizedBox(height: Sp.md),
            Row(children: [
              for (var i = 0; i < actions.length && i < 2; i++) ...[
                if (i > 0) const SizedBox(width: Sp.sm),
                Expanded(
                  child: i == 0
                      ? FilledButton.icon(
                          onPressed: actions[i].$3,
                          icon: Icon(actions[i].$2, size: 16),
                          label: Text(actions[i].$1, maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center),
                          style: FilledButton.styleFrom(backgroundColor: AppColors.brand, minimumSize: const Size.fromHeight(44)),
                        )
                      : OutlinedButton.icon(
                          onPressed: actions[i].$3,
                          icon: Icon(actions[i].$2, size: 16),
                          label: Text(actions[i].$1, maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center),
                          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(44), backgroundColor: AppColors.surface),
                        ),
                ),
              ],
            ]),
          ],
        ]),
      ),
    );
  }

  Widget _chain(FiberDiagnosis d) => Padding(
        padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, 0),
        child: FiberCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('الفحص خطوة بخطوة', style: AppType.cardTitleBold(color: AppColors.textHi)),
            const SizedBox(height: Sp.md),
            for (var i = 0; i < d.steps.length; i++) _step(d.steps[i], last: i == d.steps.length - 1),
          ]),
        ),
      );

  Widget _step(FiberDiagStep s, {required bool last}) {
    final (AppTone tone, IconData icon, String word) = switch (s.state) {
      FiberStepState.ok => (AppTone.success, LucideIcons.check, 'سليم'),
      FiberStepState.bad => (AppTone.danger, LucideIcons.x, 'فيه مشكلة'),
      FiberStepState.warn => (AppTone.warning, LucideIcons.triangleAlert, 'انتبه'),
      FiberStepState.skip => (AppTone.neutral, LucideIcons.minus, 'ما ينفحص الآن'),
    };
    return Semantics(
      label: '${s.title}، $word، ${s.detail}',
      excludeSemantics: true,
      child: IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SizedBox(
            width: 30,
            child: Column(children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(color: tone.softBg, shape: BoxShape.circle),
                child: Icon(icon, size: 15, color: tone == AppTone.neutral ? AppColors.textMid : tone.fill),
              ),
              if (!last) Expanded(child: Container(width: 2, margin: const EdgeInsets.symmetric(vertical: 3), color: AppColors.border)),
            ]),
          ),
          const SizedBox(width: Sp.md),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(top: 4, bottom: last ? 0 : Sp.lg),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(s.title, style: AppType.rowValue(color: AppColors.textHi)),
                Text(iso(s.detail),
                    style: AppType.body(color: s.state == FiberStepState.bad ? AppTone.danger.onSoft : AppColors.textMid),
                    maxLines: 2, overflow: TextOverflow.ellipsis),
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _fiberCard(FiberOnuLive onu, int? boxId) {
    final layout = FiberStore.layout.value;
    final book = FiberStore.bookOf(_m.oltId);
    final days = book.series(onu.key, today: fiberDay(DateTime.now()));
    final online = onu.online;
    String v(double? x, int digits, String unit) => x == null ? '—' : '${x.toStringAsFixed(digits)}$unit';
    final facts = <(String, String)>[
      ('الضوء', online ? v(onu.rx, 1, ' dBm') : '—'),
      ('الإرسال', online ? v(onu.tx, 1, ' dBm') : '—'),
      ('الحرارة', online ? v(onu.tempC, 0, '°') : '—'),
      ('الفولتية', online ? v(onu.voltV, 2, ' V') : '—'),
      (online ? 'متّصل منذ' : 'منقطع منذ', onu.changedAt == null ? '—' : FiberText.clock(onu.changedAt!)),
      ('الحالة', online ? 'متّصل' : (onu.reason == null ? 'مفصول' : fiberReasonLabel(onu.reason!))),
    ];
    final cols = fiberWide(context) ? 6 : 3;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, 0),
      child: FiberCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('جهاز الألياف', style: AppType.cardTitleBold(color: AppColors.textHi)),
                Text(
                  iso([onu.display, if (onu.onu.vendor != null) onu.onu.vendor!, if (boxId != null) layout.boxes[boxId]!.name].join(' · ')),
                  style: AppType.muted(color: AppColors.textMid),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ]),
            ),
            FiberPill(online ? 'متّصل' : 'منقطع', tone: online ? AppTone.success : AppTone.danger),
          ]),
          const SizedBox(height: Sp.md),
          LayoutBuilder(builder: (context, c) {
            final w = (c.maxWidth - Sp.sm * (cols - 1)) / cols;
            return Wrap(spacing: Sp.sm, runSpacing: Sp.sm, children: [
              for (final f in facts)
                Container(
                  width: w,
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
                  decoration: BoxDecoration(color: AppColors.surfaceSunken, borderRadius: BorderRadius.circular(R.sm)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(f.$1, style: AppType.muted(color: AppColors.textMid), maxLines: 1, overflow: TextOverflow.ellipsis),
                    Text(iso(f.$2), style: AppType.rowValue(color: AppColors.textHi), maxLines: 1, overflow: TextOverflow.ellipsis),
                  ]),
                ),
            ]);
          }),
          const SizedBox(height: Sp.md),
          Row(children: [
            Expanded(child: Text('الضوء آخر 7 أيّام', style: AppType.muted(color: AppColors.textMid), maxLines: 1, overflow: TextOverflow.ellipsis)),
            FiberSpark(days: days, width: 120, height: 28),
            const SizedBox(width: Sp.sm),
            Text(_trendWord(days), style: AppType.pillBold(color: AppColors.textHi)),
          ]),
          if (onu.onu.serial != null || onu.onu.mac != null) ...[
            Divider(height: Sp.xl, color: AppColors.divider),
            Row(children: [
              Expanded(child: Text(onu.onu.serial != null ? 'SN' : 'ماك الجهاز', style: AppType.muted(color: AppColors.textMid), maxLines: 1)),
              Text(iso(onu.onu.serial ?? onu.onu.mac!), style: AppType.password(color: AppColors.textHi)),
            ]),
          ],
        ]),
      ),
    );
  }

  String _trendWord(List<RxDay> days) {
    if (days.length < 3) return 'يتجمّع';
    final d = days.last.avg - days.first.avg;
    if (d <= -2) return 'نازل';
    if (d >= 2) return 'صاعد';
    return 'ثابت';
  }

  Widget _neighbours(String boxName, FiberOnuLive me, List<FiberOnuLive> others) {
    final up = others.where((o) => o.online).length;
    final slots = [
      me.online ? FiberSlot.up : FiberSlot.down,
      for (final o in others) o.online ? FiberSlot.up : FiberSlot.down,
    ];
    final text = others.isEmpty
        ? 'ما في أجهزة ثانية مسندة لهذا الصندوق.'
        : (!me.online && up == others.length
            ? '${FiberText.devices(up)} من ${others.length} شغّالة وجهازه وحده منقطع، يعني المشكلة عنده مو بالصندوق.'
            : (!me.online && up == 0
                ? 'كلّ أجهزة الصندوق منقطعة، يعني الخلل بالصندوق أو قبله.'
                : (me.online && up == others.length ? 'كلّ أجهزة الصندوق شغّالة، فالشبكة لحدّ بيته سليمة.' : '$up من ${others.length} من جيرانه شغّالة.')));
    return Padding(
      padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, 0),
      child: FiberCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(iso('جيرانه على $boxName'), style: AppType.cardTitleBold(color: AppColors.textHi)),
          const SizedBox(height: Sp.sm),
          FiberSlots(slots: slots),
          const SizedBox(height: Sp.sm),
          Text(text, style: AppType.body(color: AppColors.textBody)),
        ]),
      ),
    );
  }
}

/// يفتح التشخيص لمشتركٍ من صفحته: يجد أولته وجهازه من الربط المحفوظ.
Future<void> openFiberDiagnosisFor(BuildContext context, {required FiberMonitor monitor, required Subscriber sub}) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => FiberDiagnosisScreen(monitor: monitor, subscriber: sub)));
