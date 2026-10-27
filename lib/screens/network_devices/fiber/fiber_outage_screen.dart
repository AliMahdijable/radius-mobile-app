import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../api/broadcast_api.dart';
import '../../../api/fiber_api.dart';
import '../../../core/platform/desktop_layout.dart';
import '../../../core/util/bidi.dart';
import '../../../core/util/format.dart';
import '../../../core/widgets/app_sheet.dart';
import '../../../core/widgets/sheet_scaffold.dart';
import '../../../models/fiber_network.dart';
import '../../../models/subscriber.dart';
import '../../../services/fiber/fiber_monitor.dart';
import '../../../services/fiber/fiber_onu.dart';
import '../../../services/fiber/fiber_outage.dart';
import '../../../services/fiber/fiber_store.dart';
import '../../../services/fiber/fiber_subs.dart';
import '../../../services/fiber/fiber_text.dart';
import '../../../services/fiber/fiber_tree.dart';
import '../../../services/manual_wa_sender.dart';
import '../../../services/permissions_service.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';
import '../../desktop/desk_widgets.dart';
import 'fiber_settings_sheet.dart';
import 'fiber_sheets.dart';
import 'fiber_widgets.dart';

/// «العطل الآن»: أين القطع ولماذا نقول ذلك، وتبليغ المتأثرين بالواتساب، و«رجع النت» تلقائيّاً.
///
/// يعمل من قراءة الأولت الحيّة، أو من سجلّ الخادم وحده (هاتفٌ بعيدٌ عن الشبكة فتح إشعار العطل).
class FiberOutageScreen extends StatefulWidget {
  const FiberOutageScreen({super.key, required this.monitor, required this.scopeKey, this.focusNotify = false});

  final FiberMonitor monitor;
  final String scopeKey;
  final bool focusNotify;

  @override
  State<FiberOutageScreen> createState() => _FiberOutageScreenState();
}

class _FiberOutageScreenState extends State<FiberOutageScreen> {
  FiberMonitor get _m => widget.monitor;
  Map<String, Subscriber> _subs = const {};
  bool _subsLoaded = false;
  bool _excludeExpired = true;
  bool _sending = false;
  String? _message;
  final _notifyKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _m
      ..addListener(_changed)
      ..acquire();
    FiberStore.layout.addListener(_changed);
    _loadSubs();
    if (widget.focusNotify) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final c = _notifyKey.currentContext;
        if (c != null) Scrollable.ensureVisible(c, duration: const Duration(milliseconds: 300));
      });
    }
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

  FiberOutage? get _live => _m.outages.where((e) => e.scopeKey == widget.scopeKey).firstOrNull;

  FiberEventRecord? get _record => FiberStore.layout.value.events
      .where((e) => e.oltId == _m.oltId && e.scopeKey == widget.scopeKey)
      .fold<FiberEventRecord?>(null, (a, b) => a == null || b.startedAt.isAfter(a.startedAt) ? b : a);

  List<String> get _keys => _live?.onuKeys ?? _record?.onuKeys ?? const [];

  Future<void> _loadSubs() async {
    final users = FiberText.linkedUsers(FiberStore.layout.value, _m.oltId, _keys, _m.onus);
    final got = await FiberSubs.byUsernames(users);
    if (!mounted) return;
    setState(() {
      _subs = got;
      _subsLoaded = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final layout = FiberStore.layout.value;
    final live = _live;
    final rec = _record;
    if (live == null && rec == null) {
      return Scaffold(
        backgroundColor: AppColors.bg,
        appBar: AppBar(title: const Text('العطل'), backgroundColor: AppColors.surface, foregroundColor: AppColors.textHi, elevation: 0),
        body: Center(child: Text('هذا العطل انتهى أو لم يعد ظاهراً.', style: AppType.body(color: AppColors.textMid))),
      );
    }
    final scope = live?.scope ?? rec!.scope;
    final kind = live?.kind ?? rec!.kind;
    final pon = live?.pon ?? rec!.pon;
    final boxId = live?.boxId ?? rec?.boxId;
    final keys = _keys;
    final started = live?.startedAt ?? rec?.startedAt;
    final ended = live == null ? rec?.endedAt : null;
    final tree = FiberPonTree.build(oltId: _m.oltId, pon: pon, layout: layout, onus: _m.onus);
    final title = FiberText.outageTitle(scope: scope, pon: pon, count: keys.length, boxId: boxId, layout: layout);
    final power = kind == FiberEventKind.power;
    final wide = fiberWide(context);
    final sub = [
      fiberPonDisplay(pon),
      if (started != null) 'من ${FiberText.clock(started)}',
      if (started != null) (ended == null ? 'صار له ${FiberText.duration(DateTime.now().difference(started))}' : 'دام ${FiberText.duration(ended.difference(started))}'),
    ].join(' · ');
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: deskPageBar(
        context,
        title: title,
        subtitle: sub,
        mobile: AppBar(
          title: Text(iso(title), maxLines: 1, overflow: TextOverflow.ellipsis),
          backgroundColor: AppColors.surface,
          foregroundColor: AppColors.textHi,
          elevation: 0,
          leading: IconButton(icon: const Icon(LucideIcons.arrowRight, size: 20), onPressed: () => Navigator.pop(context)),
          actions: [
            Padding(
              padding: const EdgeInsetsDirectional.only(end: Sp.md),
              child: Center(
                child: FiberPill(ended == null ? (live == null ? 'من الخادم' : 'مستمرّ') : 'انتهى',
                    tone: ended == null ? (power ? AppTone.warning : AppTone.danger) : AppTone.success, dot: ended == null),
              ),
            ),
          ],
        ),
      ),
      body: FiberPage(
        maxWidth: wide ? 1180 : 820,
        children: [
          if (live == null && ended == null && _m.error != null)
            const FiberNotice(text: 'ما نقدر نقرأ الأولت من هنا الآن — نعرض ما سجّله الخادم.', tone: AppTone.info, icon: LucideIcons.cloud),
          // الحاسبة: السطر نفسه في رأس الصفحة.
          if (!DesktopScope.of(context))
            Padding(
              padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, 0),
              child: Text(iso(sub), style: AppType.body(color: AppColors.textMid)),
            ),
          if (wide)
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Column(children: [
                  _verdict(live, kind, scope, boxId, tree, keys),
                  if (scope != FiberEventScope.group && !power) _path(scope, boxId, tree, pon),
                  _timeline(live, rec, keys),
                ]),
              ),
              Expanded(
                child: Column(children: [
                  KeyedSubtree(key: _notifyKey, child: _notify(rec, keys, ended != null)),
                  _affected(keys),
                ]),
              ),
            ])
          else ...[
            _verdict(live, kind, scope, boxId, tree, keys),
            if (scope != FiberEventScope.group && !power) _path(scope, boxId, tree, pon),
            KeyedSubtree(key: _notifyKey, child: _notify(rec, keys, ended != null)),
            _timeline(live, rec, keys),
            _affected(keys),
          ],
        ],
      ),
    );
  }

  // ── الحكم ─────────────────────────────────────────────────────────────────────────────

  Widget _verdict(FiberOutage? live, FiberEventKind kind, FiberEventScope scope, int? boxId, FiberPonTree tree, List<String> keys) {
    final layout = FiberStore.layout.value;
    final power = kind == FiberEventKind.power;
    final tone = power ? AppTone.warning : AppTone.danger;
    final reasons = <String>[];
    if (live != null && live.timed && live.startedAt != null && live.lastDropAt != null) {
      final spread = live.lastDropAt!.difference(live.startedAt!);
      reasons.add('${FiberText.devices(keys.length)} انقطعت خلال ${FiberText.duration(spread)}، '
          'من ${FiberText.clock(live.startedAt!, seconds: true)} إلى ${FiberText.clock(live.lastDropAt!, seconds: true)}');
    } else {
      reasons.add('${FiberText.devices(keys.length)} مفصولة معاً${live == null ? '' : ' الآن'}');
    }
    final r = live?.reasons ?? const {};
    final fiber = r[FiberDropReason.fiber] ?? 0;
    final pwr = r[FiberDropReason.power] ?? 0;
    switch (kind) {
      case FiberEventKind.cut:
        reasons.add('الأولت يقول «فقدان ضوء»${fiber > 0 && fiber < keys.length ? ' لـ$fiber منها' : ''}، ولو كانت كهرباء لبعثت الأجهزة إشارة انطفاء');
      case FiberEventKind.power:
        reasons.add('بعثت إشارة انطفاء (Dying Gasp)${pwr > 0 && pwr < keys.length ? ' $pwr منها' : ''} — الأجهزة طفت، والليف سليم');
      case FiberEventKind.mixed:
        reasons.add('$fiber «فقدان ضوء» و$pwr انطفاء كهرباء — قد يكون الاثنين معاً');
      case FiberEventKind.unknown:
        reasons.add('الأولت ما يعطي سبب السقوط، فنعرف المكان من الصناديق لا السبب');
    }
    if (scope == FiberEventScope.box || scope == FiberEventScope.splitter) {
      final path = boxId == null ? const <FiberBox>[] : tree.pathTo(boxId);
      final parentId = path.length >= 2 ? path[path.length - 2].id : null;
      final siblings = (parentId == null ? tree.roots : tree.childrenOf(parentId)).where((s) => s.id != boxId).toList();
      final upSiblings = siblings.where((s) => tree.onusUnder(s.id).any((o) => o.online)).toList();
      if (upSiblings.isNotEmpty) {
        final names = upSiblings.take(3).map((s) => s.name).join(' و');
        reasons.add('${upSiblings.length == 1 ? names : names} على نفس ${parentId == null ? 'المنفذ' : 'الموزّع'} '
            '${upSiblings.length == 1 ? 'شغّال' : 'شغّالة'}، ف${parentId == null ? 'المنفذ' : 'الموزّع والمنفذ'} سليم');
      }
    } else if (scope == FiberEventScope.pon) {
      reasons.add('كلّ أجهزة ${fiberPonDisplay(tree.pon)} مفصولة — الخلل قبل أوّل موزّع');
    } else {
      reasons.add('صناديق هذه الأجهزة غير محدّدة — رتّبها من شاشة المنفذ ليعرف التطبيق المكان');
    }
    final settings = FiberStore.layout.value.settingsOf(_m.oltId);
    final box = boxId == null ? null : layout.boxes[boxId];
    return Padding(
      padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, 0),
      child: FiberCard(
        tone: tone,
        padding: const EdgeInsets.all(Sp.lg),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            FiberIconBox(power ? LucideIcons.plug : LucideIcons.scissors, tone: tone, size: 44),
            const SizedBox(width: Sp.md),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(FiberText.verdict(kind), style: AppType.sheetTitle(color: AppColors.textHi), maxLines: 2, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(iso(FiberText.outageWhere(scope: scope, kind: kind, boxId: boxId, layout: layout, tree: tree)),
                    style: AppType.body(color: AppColors.textMid), maxLines: 3, overflow: TextOverflow.ellipsis),
              ]),
            ),
          ]),
          const SizedBox(height: Sp.md),
          Text('ليش نقول هيج؟', style: AppType.label(color: AppColors.textMid)),
          const SizedBox(height: Sp.sm),
          for (var i = 0; i < reasons.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: Sp.sm),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  width: 22,
                  height: 22,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: AppColors.bg, shape: BoxShape.circle),
                  child: Text('${i + 1}', style: AppType.microBold(color: AppColors.brandOnSoft)),
                ),
                const SizedBox(width: Sp.sm),
                Expanded(child: Text(iso(reasons[i]), style: AppType.body(color: AppColors.textBody), maxLines: 4, overflow: TextOverflow.ellipsis)),
              ]),
            ),
          if (!power) ...[
            const SizedBox(height: Sp.xs),
            Row(children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => _sendToTech(box),
                  icon: const Icon(LucideIcons.mapPin, size: 16),
                  label: Text(settings.techPhone == null ? 'حدّد فنّي المنطقة' : 'أرسل الموقع للفنّي',
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  // حشوةٌ أضيق من الافتراضيّة: الزرّان جنباً لجنب على ٣٦٠ بلا قصّ النصّ.
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.brand,
                    minimumSize: const Size.fromHeight(44),
                    padding: const EdgeInsets.symmetric(horizontal: Sp.md),
                  ),
                ),
              ),
              if (settings.techPhone != null) ...[
                const SizedBox(width: Sp.sm),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => launchUrl(Uri(scheme: 'tel', path: settings.techPhone)),
                    icon: const Icon(LucideIcons.phone, size: 16),
                    label: const Text('اتصل بالفنّي', maxLines: 1, overflow: TextOverflow.ellipsis),
                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(44), padding: const EdgeInsets.symmetric(horizontal: Sp.md)),
                  ),
                ),
              ],
            ]),
          ],
        ]),
      ),
    );
  }

  Future<void> _sendToTech(FiberBox? box) async {
    final s = FiberStore.layout.value.settingsOf(_m.oltId);
    if (s.techPhone == null) {
      await showFiberSettingsSheet(context, oltId: _m.oltId, oltName: _m.device.name);
      return;
    }
    final live = _live;
    final rec = _record;
    final layout = FiberStore.layout.value;
    final title = FiberText.outageTitle(
      scope: live?.scope ?? rec!.scope,
      pon: live?.pon ?? rec!.pon,
      count: _keys.length,
      boxId: live?.boxId ?? rec?.boxId,
      layout: layout,
    );
    final lines = [
      title,
      '${FiberText.devices(_keys.length)} مفصولة على ${fiberPonDisplay(live?.pon ?? rec!.pon)} (${_m.device.name})',
      if (box?.location != null) 'المكان: ${box!.location}',
      if (box?.hasGps ?? false) 'https://www.google.com/maps/search/?api=1&query=${box!.lat},${box.lng}',
    ];
    final ok = await openManualWa(phone: s.techPhone!, message: lines.join('\n'), context: context);
    if (!ok && mounted) showSheetSnack(context, 'تعذّر فتح واتساب', isError: true);
  }

  // ── المسار ─────────────────────────────────────────────────────────────────────────────

  Widget _path(FiberEventScope scope, int? boxId, FiberPonTree tree, String pon) {
    final nodes = <({String name, String sub, bool ok, IconData icon})>[];
    if (scope == FiberEventScope.pon) {
      nodes.add((name: 'الأولت', sub: 'يجيب', ok: true, icon: LucideIcons.server));
      nodes.add((name: fiberPonDisplay(pon), sub: 'كلّه مفصول', ok: false, icon: LucideIcons.x));
    } else {
      nodes.add((name: fiberPonDisplay(pon), sub: 'شغّال', ok: true, icon: LucideIcons.check));
      final path = boxId == null ? const <FiberBox>[] : tree.pathTo(boxId);
      for (var i = 0; i < path.length; i++) {
        final b = path[i];
        final last = i == path.length - 1;
        final under = tree.onusUnder(b.id);
        nodes.add((
          name: b.name,
          sub: last ? '${under.where((o) => o.online).length}/${under.length} متّصل' : (b.location ?? 'شغّال'),
          ok: !last,
          icon: last ? LucideIcons.x : LucideIcons.check,
        ));
      }
    }
    final cutBefore = nodes.length - 1;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, 0),
      child: FiberCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('وين القطع؟', style: AppType.cardTitleBold(color: AppColors.textHi)),
          const SizedBox(height: Sp.md),
          Semantics(
            label: 'المسار: ${nodes.map((n) => '${n.name} ${n.ok ? 'سليم' : 'مقطوع'}').join('، ثمّ ')}',
            excludeSemantics: true,
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              for (var i = 0; i < nodes.length; i++) ...[
                if (i > 0)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 19),
                      child: i == cutBefore
                          ? Row(children: [
                              Expanded(child: Container(height: 2, color: AppColors.errorFill)),
                              Icon(LucideIcons.scissors, size: 16, color: AppColors.error),
                              Expanded(child: Container(height: 2, color: AppColors.errorFill)),
                            ])
                          : Container(height: 2, color: AppColors.successFill),
                    ),
                  ),
                SizedBox(
                  width: 78,
                  child: Column(children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: nodes[i].ok ? AppTone.success.softBg : AppTone.danger.softBg,
                        borderRadius: BorderRadius.circular(R.md),
                      ),
                      child: Icon(nodes[i].icon, size: 18, color: nodes[i].ok ? AppTone.success.fill : AppTone.danger.fill),
                    ),
                    const SizedBox(height: 5),
                    Text(iso(nodes[i].name), style: AppType.microBold(color: AppColors.textHi), maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center),
                    Text(iso(nodes[i].sub), style: AppType.micro(color: AppColors.textMid), maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center),
                  ]),
                ),
              ],
            ]),
          ),
        ]),
      ),
    );
  }

  // ── التبليغ ───────────────────────────────────────────────────────────────────────────

  Widget _notify(FiberEventRecord? rec, List<String> keys, bool ended) {
    final settings = FiberStore.layout.value.settingsOf(_m.oltId);
    final users = FiberText.linkedUsers(FiberStore.layout.value, _m.oltId, keys, _m.onus);
    final expired = users.where((u) => _subs[u.toLowerCase()]?.isExpired ?? false).toList();
    final targets = _excludeExpired ? users.where((u) => !expired.contains(u)).toList() : users;
    final canSend = Perms.has('whatsapp.broadcast');
    final message = _message ?? (ended ? settings.backMessage : settings.outageMessage);
    return Padding(
      padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, 0),
      child: FiberCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            const FiberIconBox(LucideIcons.messageCircle, tone: AppTone.whatsapp, size: 32),
            const SizedBox(width: Sp.sm),
            Expanded(
              child: Text(ended ? 'بلّغهم إنّه رجع' : 'بلّغ المتأثرين بالواتساب',
                  style: AppType.cardTitleBold(color: AppColors.textHi), maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            IconButton(
              tooltip: 'تعديل الرسالة',
              icon: Icon(LucideIcons.pencil, size: 17, color: AppColors.textMid),
              onPressed: () => _editMessage(message),
            ),
          ]),
          const SizedBox(height: Sp.sm),
          Container(
            padding: const EdgeInsets.all(Sp.md),
            decoration: BoxDecoration(
              color: AppTone.whatsapp.softBg,
              borderRadius: BorderRadius.circular(R.md),
              border: Border.all(color: AppTone.whatsapp.softBorder),
            ),
            child: Text(message, style: AppType.body(color: AppColors.textBody)),
          ),
          const SizedBox(height: Sp.sm),
          if (users.isEmpty)
            Text('ما في مشتركين مربوطين بهاي الأجهزة — اربطهم من «ربط المشتركين» حتى يوصلهم التبليغ.',
                style: AppType.muted(color: AppColors.textMid))
          else ...[
            // داخل بطاقةٍ ملوّنة: Material شفّاف تحتها حتى يظهر أثر النقر.
            if (expired.isNotEmpty)
              Material(
                type: MaterialType.transparency,
                child: CheckboxListTile(
                  value: _excludeExpired,
                  onChanged: (v) => setState(() => _excludeExpired = v ?? true),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text('استثنِ المنتهي اشتراكهم (${expired.length})', style: AppType.body(color: AppColors.textHi)),
                ),
              ),
            if (!ended && rec != null)
              Material(
                type: MaterialType.transparency,
                child: SwitchListTile(
                  value: rec.autoBack,
                  onChanged: canSend ? (v) => _setAutoBack(rec, v) : null,
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text('لمّا يرجع النت أرسل لهم «رجع النت» تلقائيّاً', style: AppType.body(color: AppColors.textHi)),
                  subtitle: Text('يرسلها أوّل جهاز يرى الرجوع — هاتفك أو الحاسبة', style: AppType.muted(color: AppColors.textMid)),
                ),
              ),
            if (!_subsLoaded) Text('يقرأ حالة اشتراكاتهم…', style: AppType.muted(color: AppColors.textMid)),
            const SizedBox(height: Sp.sm),
            FilledButton.icon(
              onPressed: !canSend || _sending || targets.isEmpty ? null : () => _send(rec, targets, message),
              icon: _sending
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.onBrand))
                  : Icon(canSend ? LucideIcons.send : LucideIcons.lock, size: 16),
              label: Text(canSend ? 'أرسل لـ${FiberText.subscribers(targets.length)}' : 'الإرسال بصلاحيّة الرسائل الجماعيّة'),
              style: FilledButton.styleFrom(backgroundColor: AppColors.brand, minimumSize: const Size.fromHeight(48)),
            ),
            if (rec?.notifiedAt != null)
              Padding(
                padding: const EdgeInsets.only(top: Sp.xs),
                child: Text('بُلِّغوا ${FiberText.clock(rec!.notifiedAt!)}', style: AppType.muted(color: AppColors.textMid), textAlign: TextAlign.center),
              ),
          ],
        ]),
      ),
    );
  }

  Future<void> _editMessage(String current) async {
    final ctrl = TextEditingController(text: current);
    final out = await showAppSheet<String>(
      context: context,
      barrierColor: AppColors.scrim,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(Sp.xl, Sp.xl, Sp.xl, MediaQuery.viewInsetsOf(ctx).bottom + Sp.xl),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('نصّ الرسالة', style: AppType.sheetTitle(color: AppColors.textHi)),
          const SizedBox(height: Sp.md),
          TextField(
            controller: ctrl,
            maxLines: 5,
            maxLength: 500,
            decoration: InputDecoration(
              filled: true,
              fillColor: AppColors.surfaceInput,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(R.sm), borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: Sp.sm),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(ctrl.text.trim()),
            style: FilledButton.styleFrom(backgroundColor: AppColors.brand, minimumSize: const Size.fromHeight(H.button)),
            child: const Text('استعمل هذا النصّ'),
          ),
        ]),
      ),
    );
    ctrl.dispose();
    if (out != null && out.isNotEmpty && mounted) setState(() => _message = out);
  }

  Future<void> _setAutoBack(FiberEventRecord rec, bool v) async {
    FiberStore.applyEvent(rec.copyWith(autoBack: v));
    final r = await FiberApi.updateEvent(rec.id, autoBack: v);
    if (r.event != null) FiberStore.applyEvent(r.event!);
    if (!r.ok && mounted) {
      FiberStore.applyEvent(rec);
      showSheetSnack(context, r.message ?? 'تعذّر الحفظ', isError: true);
    }
  }

  Future<void> _send(FiberEventRecord? rec, List<String> targets, String message) async {
    setState(() => _sending = true);
    final r = await BroadcastApi.broadcast(intent: MessageIntent.general, message: message, targetUsernames: targets);
    if (!mounted) return;
    setState(() => _sending = false);
    if (!r.ok) {
      showSheetSnack(context, r.message ?? 'تعذّر الإرسال', isError: true);
      return;
    }
    showSheetSnack(context, r.message ?? 'دخلت ${FiberText.subscribers(r.queued ?? targets.length)} طابور الإرسال');
    if (rec != null) {
      final u = await FiberApi.updateEvent(rec.id, notified: true);
      if (u.event != null) FiberStore.applyEvent(u.event!);
    }
  }

  // ── التسلسل والمتأثرون ────────────────────────────────────────────────────────────────

  Widget _timeline(FiberOutage? live, FiberEventRecord? rec, List<String> keys) {
    final layout = FiberStore.layout.value;
    final byKey = {for (final o in _m.onus) o.key: o};
    final dropped = [
      for (final k in keys)
        if (byKey[k]?.changedAt != null && !(byKey[k]!.online)) byKey[k]!,
    ]..sort((a, b) => a.changedAt!.compareTo(b.changedAt!));
    final items = <({String title, String sub, AppTone tone, bool pulse})>[];
    if (dropped.isNotEmpty) {
      final first = dropped.first;
      items.add((
        title: '${FiberText.clock(first.changedAt!, seconds: true)} · أوّل جهاز انقطع',
        sub: '${fiberOnuTitle(layout, _m.oltId, first)}${dropped.length > 1 ? '، وبعده ${FiberText.devices(dropped.length - 1)}' : ''}',
        tone: AppTone.danger,
        pulse: false,
      ));
      if (dropped.length > 1) {
        items.add((
          title: '${FiberText.clock(dropped.last.changedAt!, seconds: true)} · آخر جهاز',
          sub: 'خلال ${FiberText.duration(dropped.last.changedAt!.difference(first.changedAt!))}',
          tone: AppTone.danger,
          pulse: false,
        ));
      }
    } else if (rec != null) {
      items.add((title: '${FiberText.clock(rec.startedAt)} · بدأ العطل', sub: FiberText.devices(keys.length), tone: AppTone.danger, pulse: false));
    }
    if (rec != null) {
      items.add((title: 'وصل التنبيه لأجهزة الحساب', sub: 'الهاتف والحاسبة', tone: AppTone.brand, pulse: false));
    }
    if (rec?.notifiedAt != null) {
      items.add((title: '${FiberText.clock(rec!.notifiedAt!)} · بُلِّغ المشتركون', sub: 'بالواتساب', tone: AppTone.whatsapp, pulse: false));
    }
    final ended = live == null ? rec?.endedAt : null;
    items.add(ended == null
        ? (title: 'الآن ${FiberText.clock(DateTime.now())} · بانتظار الإصلاح', sub: 'نبلّغك أوّل ما يرجع الضوء', tone: AppTone.danger, pulse: true)
        : (title: '${FiberText.clock(ended)} · رجع النت', sub: 'دام ${FiberText.duration(ended.difference(rec!.startedAt))}', tone: AppTone.success, pulse: false));
    return Padding(
      padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, 0),
      child: FiberCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('التسلسل', style: AppType.cardTitleBold(color: AppColors.textHi)),
          const SizedBox(height: Sp.md),
          for (var i = 0; i < items.length; i++)
            IntrinsicHeight(
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                SizedBox(
                  width: 12,
                  child: Column(children: [
                    const SizedBox(height: 5),
                    Container(width: 10, height: 10, decoration: BoxDecoration(color: items[i].tone.fill, shape: BoxShape.circle)),
                    if (i < items.length - 1) Expanded(child: Container(width: 2, margin: const EdgeInsets.only(top: 3), color: AppColors.border)),
                  ]),
                ),
                const SizedBox(width: Sp.md),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(bottom: i < items.length - 1 ? Sp.md : 0),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(iso(items[i].title), style: AppType.bodyStrong(color: AppColors.textHi), maxLines: 2, overflow: TextOverflow.ellipsis),
                      Text(iso(items[i].sub), style: AppType.muted(color: AppColors.textMid), maxLines: 2, overflow: TextOverflow.ellipsis),
                    ]),
                  ),
                ),
              ]),
            ),
        ]),
      ),
    );
  }

  Widget _affected(List<String> keys) {
    final layout = FiberStore.layout.value;
    final byKey = {for (final o in _m.onus) o.key: o};
    var active = 0, expired = 0, debtors = 0;
    for (final k in keys) {
      final u = layout.recordFor(_m.oltId, k, byKey[k]?.ident)?.username;
      final s = u == null ? null : _subs[u.toLowerCase()];
      if (s == null) continue;
      if (s.isExpired) {
        expired++;
      } else {
        active++;
      }
      if (s.hasDebt) debtors++;
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, 0),
      child: FiberCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('المتأثرون · ${keys.length}', style: AppType.cardTitleBold(color: AppColors.textHi)),
          if (_subsLoaded && active + expired > 0) ...[
            const SizedBox(height: Sp.sm),
            Wrap(spacing: 6, runSpacing: 6, children: [
              FiberPill('$active فعّال', tone: AppTone.success),
              if (expired > 0) FiberPill('$expired منتهي', tone: AppTone.warning),
              if (debtors > 0) FiberPill('$debtors مديون', tone: AppTone.danger),
            ]),
          ],
          const SizedBox(height: Sp.xs),
          for (final k in keys)
            if (byKey[k] != null) _affectedRow(byKey[k]!) else _ghostRow(k),
        ]),
      ),
    );
  }

  Widget _affectedRow(FiberOnuLive o) {
    final layout = FiberStore.layout.value;
    final u = layout.recordFor(_m.oltId, o.key, o.ident)?.username;
    final s = u == null ? null : _subs[u.toLowerCase()];
    final phone = s?.mobile ?? s?.phone;
    final status = s == null
        ? (u == null ? 'غير مربوط' : null)
        : s.isExpired
            ? 'منتهي'
            : (s.hasDebt ? 'مديون ${formatIQD(s.debtAbs)}' : 'فعّال');
    final name = s?.fullName.trim();
    final named = name != null && name.isNotEmpty;
    // الرقم تحت الاسم — إلّا إن كان الرقم هو العنوان نفسه.
    final showNumber = named || fiberOnuTitle(layout, _m.oltId, o) != o.display;
    return FiberOnuRow(
      oltId: _m.oltId,
      onu: o,
      title: named ? name : null,
      sub: [if (showNumber) o.display, if (status != null) status, if (o.online) 'رجع'].join(' · '),
      trailing: phone == null || phone.trim().isEmpty
          ? null
          : IconButton(
              tooltip: 'اتصل بـ${s!.fullName.trim().isEmpty ? s.username : s.fullName}',
              icon: Icon(LucideIcons.phone, size: 17, color: AppColors.brandLight),
              onPressed: () => launchUrl(Uri(scheme: 'tel', path: phone.trim())),
            ),
    );
  }

  Widget _ghostRow(String key) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Text(iso(key), style: AppType.muted(color: AppColors.textMid)),
      );
}
