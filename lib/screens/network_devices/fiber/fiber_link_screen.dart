import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/util/bidi.dart';
import '../../../core/widgets/app_sheet.dart';
import '../../../core/widgets/design_sheet.dart';
import '../../../core/widgets/sheet_scaffold.dart';
import '../../../models/fiber_network.dart';
import '../../../models/subscriber.dart';
import '../../../services/fiber/fiber_linker.dart';
import '../../../services/fiber/fiber_monitor.dart';
import '../../../services/fiber/fiber_onu.dart';
import '../../../services/fiber/fiber_store.dart';
import '../../../services/fiber/fiber_subs.dart';
import '../../../services/fiber/fiber_text.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';
import '../../desktop/desk_widgets.dart';
import 'fiber_home_screen.dart';
import 'fiber_sheets.dart';
import 'fiber_widgets.dart';

/// بيانات الربط من الساس: الجلسات الحيّة (يوزر ← ماك) ودليل الحساب العاديّ — مشتركةٌ بين الشاشة والنافذة (٤٥ث).
class _LinkData {
  static Map<String, String> sessions = const {};
  static Map<String, Subscriber> directory = const {};
  static DateTime? at;
  static Future<void>? _loading;

  static Future<void> ensure({bool force = false}) {
    if (!force && at != null && DateTime.now().difference(at!) < const Duration(seconds: 45)) return Future.value();
    return _loading ??= () async {
      try {
        final r = await Future.wait([FiberSubs.sessionMacs(), FiberSubs.directory()]);
        sessions = r[0] as Map<String, String>;
        directory = r[1] as Map<String, Subscriber>;
        at = DateTime.now();
      } finally {
        _loading = null;
      }
    }();
  }

  static Map<String, String> get known => {for (final e in directory.entries) e.key: e.value.username};

  static String? nameOf(String username) {
    final s = directory[username.toLowerCase()];
    if (s == null) return null;
    final n = s.fullName.trim();
    return n.isEmpty || n == s.username ? null : n;
  }
}

/// «ربط الأجهزة بالمشتركين»: كم مربوط، والمقترح بسببه (أكيد/محتمل) مع «ثبّت الأكيدة»، وما بقي بلا ربط ولماذا.
class FiberLinkScreen extends StatefulWidget {
  const FiberLinkScreen({super.key, required this.monitor});

  final FiberMonitor monitor;

  /// للاختبار: جلسات الساس ودليل الحساب جاهزان (بلا شبكة).
  @visibleForTesting
  static void debugSeed({Map<String, String> sessions = const {}, Map<String, Subscriber> directory = const {}}) {
    _LinkData.sessions = sessions;
    _LinkData.directory = directory;
    _LinkData.at = DateTime.now();
  }

  /// للاختبار: تُنسى البيانات المحمّلة.
  @visibleForTesting
  static void debugReset() {
    _LinkData.sessions = const {};
    _LinkData.directory = const {};
    _LinkData.at = null;
  }

  @override
  State<FiberLinkScreen> createState() => _FiberLinkScreenState();
}

class _FiberLinkScreenState extends State<FiberLinkScreen> {
  FiberMonitor get _m => widget.monitor;
  late final bool _prevWant;
  bool _loading = true;
  bool _saving = false;
  bool _all = false;
  FiberUnlinkedReason? _open;
  final Set<String> _done = {};

  /// آخر ما عُرض من المقترح — ما ثُبّت بهذه الجلسة يبقى بمكانه بحبّة «مربوط» لا يختفي من تحت إصبع الوكيل.
  List<FiberLinkSuggestion> _shown = const [];

  @override
  void initState() {
    super.initState();
    _prevWant = _m.wantDevices;
    _m
      ..wantDevices = true
      ..addListener(_changed)
      ..acquire();
    FiberStore.layout.addListener(_changed);
    unawaited(_load());
  }

  @override
  void dispose() {
    _m
      ..wantDevices = _prevWant
      ..removeListener(_changed)
      ..release();
    FiberStore.layout.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _load({bool force = false}) async {
    setState(() => _loading = true);
    await Future.wait([_LinkData.ensure(force: force), if (force) _m.refreshNow()]);
    if (mounted) setState(() => _loading = false);
  }

  FiberLinkPlan _plan() => FiberLinker.plan(
        oltId: _m.oltId,
        onus: _m.onus,
        layout: FiberStore.layout.value,
        sessionMacByUser: _LinkData.sessions,
        knownUsernames: _LinkData.known,
      );

  Future<void> _confirm(List<FiberLinkSuggestion> list) async {
    if (list.isEmpty || _saving) return;
    setState(() => _saving = true);
    final r = await FiberStore.linkMany(_m.oltId, list);
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (r.ok) _done.addAll(list.map((s) => s.key));
    });
    if (!r.ok) {
      showSheetSnack(context, r.message ?? 'تعذّر الحفظ', isError: true);
    } else if (list.length > 1) {
      showSheetSnack(context, 'ثُبّت ربط ${FiberText.devices(list.length)}');
    }
  }

  Future<void> _manual(FiberOnuLive o) async {
    await showFiberLinkPicker(context, monitor: _m, onu: o);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final plan = _plan();
    final total = _m.onus.length;
    final byKey = {for (final o in _m.onus) o.key: o};
    final canEdit = fiberCanEdit();
    final wide = fiberWide(context);
    final sub = '${FiberText.devices(total)} على ${_m.device.name}';
    final summary = _summary(plan, total);
    final suggested = _suggested(plan, byKey, canEdit);
    final unlinked = _unlinked(plan, byKey, canEdit);
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: deskPageBar(
        context,
        subtitle: sub,
        mobile: AppBar(
          backgroundColor: AppColors.surface,
          foregroundColor: AppColors.textHi,
          elevation: 0,
          leading: IconButton(icon: const Icon(LucideIcons.arrowRight, size: 20), onPressed: () => Navigator.pop(context)),
          title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('ربط الأجهزة بالمشتركين'),
            Text(iso(sub), style: AppType.muted(color: AppColors.textMid), maxLines: 1, overflow: TextOverflow.ellipsis),
          ]),
        ),
      ),
      body: FiberPage(
        onRefresh: () => _load(force: true),
        children: [
          FiberStaleNotice(monitor: _m),
          if (_loading) const FiberNotice(text: 'يقرأ جلسات المشتركين من الساس والأجهزة خلف كلّ ONU…', tone: AppTone.info),
          if (_m.error != null) FiberNotice(text: _m.error!, tone: AppTone.danger, onRetry: _m.refreshNow, icon: LucideIcons.wifiOff),
          if (!_loading && _LinkData.sessions.isEmpty)
            const FiberNotice(
              text: 'ما وصلتنا جلسات المشتركين المتّصلين من الساس، فالربط بالماك متوقّف — يبقى الربط باسم الجهاز واليدويّ.',
              tone: AppTone.warning,
            ),
          if (wide)
            Padding(
              padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, 0),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(flex: 3, child: suggested),
                const SizedBox(width: Sp.md),
                Expanded(flex: 2, child: Column(children: [summary, const SizedBox(height: Sp.md), unlinked, _after()])),
              ]),
            )
          else ...[
            _pad(summary),
            _pad(suggested),
            _pad(unlinked),
            _after(),
          ],
        ],
      ),
    );
  }

  Widget _pad(Widget w) => Padding(padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, 0), child: w);

  Widget _summary(FiberLinkPlan plan, int total) {
    final linked = plan.linkedCount;
    final sug = plan.suggestions.length;
    final none = (total - linked - sug).clamp(0, total);
    Widget legend(Color c, String t) => Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 9, height: 9, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(R.check - 3))),
          const SizedBox(width: 6),
          Text(t, style: AppType.muted(color: AppColors.textBody)),
        ]);
    return FiberCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
          Text(iso('$linked'), style: TextStyle(fontFamily: AppType.family, fontSize: 28, fontWeight: FontWeight.w700, height: 1.2, color: AppColors.textHi)),
          const SizedBox(width: Sp.sm),
          Expanded(child: Text('من ${FiberText.devices(total)} مربوط بمشترك', style: AppType.bodyStrong(color: AppColors.textHi), maxLines: 2, overflow: TextOverflow.ellipsis)),
        ]),
        const SizedBox(height: 10),
        Semantics(
          label: '$linked مربوط، $sug مقترح، $none بلا ربط',
          excludeSemantics: true,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(R.check - 1),
            child: SizedBox(
              height: 10,
              child: total == 0
                  ? Container(color: AppColors.border)
                  : Row(children: [
                      if (linked > 0) Expanded(flex: linked, child: Container(color: AppColors.chartLine)),
                      if (linked > 0 && sug + none > 0) const SizedBox(width: 2),
                      if (sug > 0) Expanded(flex: sug, child: Container(color: AppColors.info)),
                      if (sug > 0 && none > 0) const SizedBox(width: 2),
                      if (none > 0) Expanded(flex: none, child: Container(color: AppColors.borderStrong)),
                    ]),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(spacing: 14, runSpacing: 6, children: [
          legend(AppColors.chartLine, 'مربوط $linked'),
          legend(AppColors.info, 'مقترح $sug'),
          legend(AppColors.borderStrong, 'بلا ربط $none'),
        ]),
        const SizedBox(height: 10),
        Text(
          iso('نقترح الربط بثلاث طرق: ماك الراوتر اللي خلف الـONU نفس ماك جلسة المشترك بالساس، أو اسم الجهاز على الأولت نفس يوزره، '
              'أو ماك الـONU نفسها حين تتّصل هي بالنت. ولا يُحفظ شي إلّا لمّا تثبّته.'),
          style: AppType.body(color: AppColors.textMid),
        ),
      ]),
    );
  }

  Widget _suggested(FiberLinkPlan plan, Map<String, FiberOnuLive> byKey, bool canEdit) {
    final layout = FiberStore.layout.value;
    final fresh = {for (final s in plan.suggestions) s.key};
    final all = [
      ...plan.suggestions,
      for (final s in _shown)
        if (_done.contains(s.key) && !fresh.contains(s.key)) s,
    ];
    _shown = all;
    final open = all.where((s) => !_done.contains(s.key)).toList();
    final sure = open.where((s) => s.sure).toList();
    final shown = _all ? all : all.take(6).toList();
    final more = all.length - shown.length;
    return FiberCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text('مقترح · ${open.length}', style: AppType.cardTitleBold(color: AppColors.textHi), maxLines: 1, overflow: TextOverflow.ellipsis)),
          if (sure.isNotEmpty)
            FilledButton.icon(
              onPressed: !canEdit || _saving ? null : () => _confirm(sure),
              icon: Icon(canEdit ? LucideIcons.checkCheck : LucideIcons.lock, size: 16),
              label: Text(canEdit ? 'ثبّت الأكيدة (${sure.length})' : 'لا صلاحيّة'),
              style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
            )
          else if (all.any((s) => s.sure))
            Text('ثُبّتت كلّ الأكيدة', style: AppType.bodyBold(color: AppTone.success.onSoft)),
        ]),
        if (all.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: Sp.md),
            child: Text(
              _loading ? 'يحسب الاقتراحات…' : 'ما عندنا اقتراحات الآن — كلّ جهازٍ بقي بلا ربط مكتوب سببه تحت.',
              style: AppType.body(color: AppColors.textMid),
            ),
          ),
        for (final s in shown) _suggestionRow(s, byKey[s.key], layout, canEdit),
        if (more > 0)
          Padding(
            padding: const EdgeInsets.only(top: Sp.xs),
            child: OutlinedButton(
              onPressed: () => setState(() => _all = true),
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(44)),
              child: Text('و$more مقترحات غيرها'),
            ),
          ),
      ]),
    );
  }

  Widget _suggestionRow(FiberLinkSuggestion s, FiberOnuLive? o, FiberLayout layout, bool canEdit) {
    final done = _done.contains(s.key) || layout.recordFor(_m.oltId, s.key, s.ident)?.username != null;
    final rec = layout.recordFor(_m.oltId, s.key, s.ident);
    final box = rec?.boxId == null ? null : layout.boxes[rec!.boxId];
    final name = _LinkData.nameOf(s.username);
    final tone = done || s.sure ? AppTone.success : AppTone.warning;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: Sp.md),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: AppColors.border))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: Sp.sm, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.surfaceSunken,
              borderRadius: BorderRadius.circular(R.sm),
              border: Border.all(color: AppColors.border),
            ),
            child: Text(iso(o?.display ?? fiberOnuKeyDisplay(s.key)), style: AppType.labelBold(color: AppColors.textHi)),
          ),
          const SizedBox(width: 6),
          Icon(LucideIcons.arrowLeft, size: 14, color: AppColors.textMid),
          const SizedBox(width: 6),
          Expanded(
            child: Text.rich(
              TextSpan(children: [
                TextSpan(text: iso(name ?? s.username), style: AppType.rowValue(color: AppColors.textHi)),
                if (name != null) ...[
                  TextSpan(text: ' · ', style: AppType.body(color: AppColors.textMid)),
                  TextSpan(text: iso(s.username), style: AppType.body(color: AppColors.textMid)),
                ],
              ]),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 6),
          FiberPill(done ? 'مربوط' : (s.sure ? 'أكيد' : 'محتمل'), tone: tone),
        ]),
        const SizedBox(height: 6),
        Row(children: [
          Expanded(
            child: Text(
              iso([if (box != null) box.name, s.why].join(' · ')),
              style: AppType.muted(color: AppColors.textMid),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (!done) ...[
            const SizedBox(width: Sp.sm),
            Tooltip(
              message: canEdit ? 'ثبّت ربط ${o?.display ?? fiberOnuKeyDisplay(s.key)} بـ${name ?? s.username}' : 'لا صلاحيّة',
              child: SizedBox(
                width: 44,
                height: 44,
                child: IconButton.filled(
                  onPressed: !canEdit || _saving ? null : () => _confirm([s]),
                  style: IconButton.styleFrom(
                    backgroundColor: AppTone.success.softBg,
                    foregroundColor: AppTone.success.onSoft,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(R.md)),
                  ),
                  icon: Icon(canEdit ? LucideIcons.check : LucideIcons.lock, size: 18),
                ),
              ),
            ),
            const SizedBox(width: 6),
            Tooltip(
              message: canEdit ? 'اختر مشتركاً غير ${name ?? s.username}' : 'لا صلاحيّة',
              child: SizedBox(
                width: 44,
                height: 44,
                child: IconButton.outlined(
                  onPressed: !canEdit || o == null ? null : () => _manual(o),
                  style: IconButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(R.md))),
                  icon: const Icon(LucideIcons.pencil, size: 17),
                ),
              ),
            ),
          ],
        ]),
      ]),
    );
  }

  Widget _unlinked(FiberLinkPlan plan, Map<String, FiberOnuLive> byKey, bool canEdit) {
    const order = [FiberUnlinkedReason.noSession, FiberUnlinkedReason.offline, FiberUnlinkedReason.unknownDevices];
    const titles = {
      FiberUnlinkedReason.noSession: ('شغّالة بس ماكو جلسة تطابقها', 'غالباً راوتر المشترك مطفي، أو جهاز تجربة'),
      FiberUnlinkedReason.offline: ('طافية الآن', 'ما نقدر نقرأ الأجهزة اللي خلفها وهي طافية'),
      FiberUnlinkedReason.unknownDevices: ('الأجهزة اللي خلفها ما انقرأت بعد', 'الأولت ما كشف جدولها — نعيد القراءة كلّ 5 دقائق'),
    };
    final n = plan.unlinkedCount;
    return FiberCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text('بلا ربط · $n', style: AppType.cardTitleBold(color: AppColors.textHi), maxLines: 1, overflow: TextOverflow.ellipsis)),
          OutlinedButton.icon(
            onPressed: !canEdit || _m.onus.isEmpty ? null : _manualAny,
            icon: Icon(canEdit ? LucideIcons.link : LucideIcons.lock, size: 15),
            label: Text(canEdit ? 'اربط يدويّاً' : 'لا صلاحيّة'),
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
          ),
        ]),
        if (n == 0)
          Padding(
            padding: const EdgeInsets.only(top: Sp.sm),
            child: Text(
              plan.suggestions.isEmpty && plan.linkedCount > 0 ? 'كلّ الأجهزة مربوطة.' : 'كلّ جهازٍ إمّا مربوط أو له اقتراح.',
              style: AppType.body(color: AppColors.textMid),
            ),
          ),
        for (final r in order)
          if ((plan.unlinked[r] ?? const []).isNotEmpty) ...[
            InkWell(
              onTap: () => setState(() => _open = _open == r ? null : r),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(border: Border(top: BorderSide(color: AppColors.border))),
                child: Row(children: [
                  Container(
                    width: 34,
                    height: 34,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: AppColors.surfaceSunken, borderRadius: BorderRadius.circular(R.sm)),
                    child: Text(iso('${plan.unlinked[r]!.length}'), style: AppType.cardTitleBold(color: AppColors.textHi)),
                  ),
                  const SizedBox(width: Sp.md),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(titles[r]!.$1, style: AppType.bodyStrong(color: AppColors.textHi)),
                      Text(titles[r]!.$2, style: AppType.muted(color: AppColors.textMid)),
                    ]),
                  ),
                  Icon(_open == r ? LucideIcons.chevronUp : LucideIcons.chevronDown, size: 18, color: AppColors.textMid),
                ]),
              ),
            ),
            if (_open == r)
              for (final k in plan.unlinked[r]!.take(60))
                if (byKey[k] != null)
                  FiberOnuRow(
                    oltId: _m.oltId,
                    onu: byKey[k]!,
                    onTap: canEdit ? () => _manual(byKey[k]!) : null,
                    trailing: canEdit ? Icon(LucideIcons.link, size: 16, color: AppColors.brandLight) : null,
                  ),
          ],
      ]),
    );
  }

  Future<void> _manualAny() async {
    final layout = FiberStore.layout.value;
    final free = _m.onus.where((o) => layout.recordFor(_m.oltId, o.key, o.ident)?.username == null).toList();
    final o = await showFiberOnuPicker(context, oltId: _m.oltId, onus: free.isEmpty ? _m.onus : free);
    if (o != null && mounted) await _manual(o);
  }

  Widget _after() => Padding(
        padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, 0),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(padding: const EdgeInsets.only(top: 3), child: Icon(LucideIcons.info, size: 16, color: AppColors.brandLight)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'بعد الربط: صفحة كلّ مشترك تبيّن جهازه وضوءه، والعطل يعرف منو تأثّر فيبلّغه بالواتساب.',
              style: AppType.body(color: AppColors.textBody),
            ),
          ),
        ]),
      );
}

Future<T?> _sheet<T>(BuildContext context, WidgetBuilder b) => showAppSheet<T>(
      barrierColor: AppColors.scrim,
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(R.card))),
      builder: b,
    );

/// اختيار جهازٍ من القائمة («اربط يدويّاً»).
Future<FiberOnuLive?> showFiberOnuPicker(BuildContext context, {required int oltId, required List<FiberOnuLive> onus}) =>
    _sheet(context, (ctx) => _OnuPicker(oltId: oltId, onus: onus));

class _OnuPicker extends StatefulWidget {
  const _OnuPicker({required this.oltId, required this.onus});
  final int oltId;
  final List<FiberOnuLive> onus;

  @override
  State<_OnuPicker> createState() => _OnuPickerState();
}

class _OnuPickerState extends State<_OnuPicker> {
  final _q = TextEditingController();

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = _q.text.trim().toLowerCase();
    final list = widget.onus
        .where((o) => q.isEmpty || o.display.toLowerCase().contains(q) || '${o.onu.ponPort}:${o.onu.onuId}'.contains(q) || (o.onu.name?.toLowerCase().contains(q) ?? false))
        .take(80)
        .toList();
    return DesignSheet(
      header: SheetHeaderBar(icon: LucideIcons.router, title: 'أيّ جهاز تربط؟', subtitle: FiberText.devices(widget.onus.length), onClose: () => Navigator.pop(context)),
      body: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        TextField(
          controller: _q,
          onChanged: (_) => setState(() {}),
          style: AppType.input(color: AppColors.textHi),
          decoration: InputDecoration(
            hintText: 'رقمه مثل 3:7 أو اسمه على الأولت',
            prefixIcon: const Icon(LucideIcons.search, size: 18),
            filled: true,
            fillColor: AppColors.surfaceInput,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(R.sm), borderSide: BorderSide.none),
          ),
        ),
        const SizedBox(height: Sp.sm),
        ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.5),
          child: ListView(shrinkWrap: true, children: [
            for (final o in list) FiberOnuRow(oltId: widget.oltId, onu: o, onTap: () => Navigator.pop(context, o)),
          ]),
        ),
      ]),
    );
  }
}

/// ربط جهازٍ بمشترك: الاقتراح أوّلاً (إن وُجد)، ثمّ بحثٌ بيوزر/اسم من دليل الحساب (العاديّ)، أو يوزرٌ مكتوب يُتحقَّق منه
/// بالساس (الكبير). يُرجع `true` إن حُفظ ربطٌ أو فُكّ.
Future<bool?> showFiberLinkPicker(BuildContext context, {required FiberMonitor monitor, required FiberOnuLive onu}) =>
    _sheet(context, (ctx) => _LinkPicker(monitor: monitor, onu: onu));

class _LinkPicker extends StatefulWidget {
  const _LinkPicker({required this.monitor, required this.onu});
  final FiberMonitor monitor;
  final FiberOnuLive onu;

  @override
  State<_LinkPicker> createState() => _LinkPickerState();
}

class _LinkPickerState extends State<_LinkPicker> {
  final _q = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  bool _checking = false;
  String? _error;
  Subscriber? _found;
  FiberLinkSuggestion? _suggestion;

  FiberOnuLive get _onu => widget.onu;
  int get _oltId => widget.monitor.oltId;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    await _LinkData.ensure();
    if (!mounted) return;
    final plan = FiberLinker.plan(
      oltId: _oltId,
      onus: [_onu],
      layout: FiberStore.layout.value,
      sessionMacByUser: _LinkData.sessions,
      knownUsernames: _LinkData.known,
    );
    setState(() {
      _loading = false;
      _suggestion = plan.suggestions.isEmpty ? null : plan.suggestions.first;
    });
  }

  /// الحساب الكبير: اليوزر المكتوب يُفحص بالساس قبل الربط.
  Future<void> _check() async {
    final u = _q.text.trim();
    if (u.isEmpty) return;
    setState(() {
      _checking = true;
      _error = null;
      _found = null;
    });
    final got = await FiberSubs.byUsernames([u]);
    if (!mounted) return;
    setState(() {
      _checking = false;
      _found = got[u.toLowerCase()];
      if (_found == null) _error = 'ما لقينا اليوزر «$u» بالساس';
    });
  }

  Future<void> _save(String? username, FiberLinkSource source) async {
    if (username != null) {
      final other = FiberStore.linkedTo(_oltId, username, exceptKey: _onu.key);
      if (other != null) {
        final was = widget.monitor.onus.where((o) => o.key == other.key).firstOrNull?.display ?? fiberOnuKeyDisplay(other.key);
        final ok = await showConfirmSheet(
          context,
          title: 'اليوزر مربوط بجهازٍ ثاني',
          message: '«$username» مربوط الآن بـ$was. ننقله لـ${_onu.display} ونفكّه من هناك؟',
          confirmLabel: 'انقله',
          icon: LucideIcons.link,
          tone: AppTone.warning,
        );
        if (ok != true || !mounted) return;
      }
    }
    setState(() => _saving = true);
    final r = await FiberStore.link(_oltId, _onu, username, source: source);
    if (!mounted) return;
    setState(() => _saving = false);
    if (!r.ok) {
      showSheetSnack(context, r.message ?? 'تعذّر الحفظ', isError: true);
      return;
    }
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final rec = FiberStore.layout.value.recordFor(_oltId, _onu.key, _onu.ident);
    final big = !_loading && _LinkData.directory.isEmpty;
    final q = _q.text.trim().toLowerCase();
    final hits = big || q.length < 2
        ? const <Subscriber>[]
        : _LinkData.directory.values
            .where((s) => s.username.toLowerCase().contains(q) || s.fullName.toLowerCase().contains(q))
            .take(30)
            .toList();
    final s = _suggestion;
    return DesignSheet(
      header: SheetHeaderBar(
        icon: LucideIcons.link,
        title: 'اربط ${_onu.display} بمشترك',
        subtitle: rec?.username == null ? (_onu.onu.name ?? fiberPonDisplay(_onu.pon)) : 'مربوط الآن بـ${rec!.username}',
        onClose: () => Navigator.pop(context),
      ),
      body: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (_loading) const LinearProgressIndicator(minHeight: 2),
        if (s != null) ...[
          Text('مقترح', style: AppType.label(color: AppColors.textMid)),
          const SizedBox(height: 4),
          _candidate(
            title: _LinkData.nameOf(s.username) ?? s.username,
            sub: [if (_LinkData.nameOf(s.username) != null) s.username, s.why].join(' · '),
            pill: FiberPill(s.sure ? 'أكيد' : 'محتمل', tone: s.sure ? AppTone.success : AppTone.warning),
            onTap: () => _save(s.username, s.source),
          ),
          const SizedBox(height: Sp.md),
        ],
        TextField(
          controller: _q,
          autofocus: s == null,
          onChanged: (_) => setState(() {
            _found = null;
            _error = null;
          }),
          onSubmitted: big ? (_) => _check() : null,
          style: AppType.input(color: AppColors.textHi),
          decoration: InputDecoration(
            hintText: big ? 'اكتب يوزر المشترك كما بالساس' : 'يوزر المشترك أو اسمه',
            prefixIcon: const Icon(LucideIcons.search, size: 18),
            suffixIcon: big
                ? IconButton(
                    tooltip: 'افحص بالساس',
                    onPressed: _checking ? null : _check,
                    icon: _checking
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(LucideIcons.arrowLeft, size: 18),
                  )
                : null,
            filled: true,
            fillColor: AppColors.surfaceInput,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(R.sm), borderSide: BorderSide.none),
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: Sp.sm),
            child: Text(iso(_error!), style: AppType.body(color: AppColors.error)),
          ),
        if (_found != null) ...[
          const SizedBox(height: Sp.sm),
          _candidate(
            title: _found!.fullName,
            sub: _found!.username,
            onTap: () => _save(_found!.username, FiberLinkSource.manual),
          ),
        ],
        if (hits.isNotEmpty)
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.4),
            child: ListView(shrinkWrap: true, children: [
              for (final h in hits)
                _candidate(title: h.fullName, sub: h.username, onTap: () => _save(h.username, FiberLinkSource.manual)),
            ]),
          )
        else if (!big && q.length >= 2 && !_loading)
          Padding(
            padding: const EdgeInsets.only(top: Sp.sm),
            child: Text('ما لقينا مشتركاً بهذا الاسم أو اليوزر', style: AppType.body(color: AppColors.textMid)),
          ),
        if (rec?.username != null) ...[
          const SizedBox(height: Sp.md),
          OutlinedButton.icon(
            onPressed: _saving ? null : () => _save(null, FiberLinkSource.manual),
            icon: const Icon(LucideIcons.unlink, size: 16),
            label: const Text('فكّ الربط'),
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(44), foregroundColor: AppColors.error),
          ),
        ],
        if (_saving) const Padding(padding: EdgeInsets.only(top: Sp.sm), child: LinearProgressIndicator(minHeight: 2)),
      ]),
    );
  }

  Widget _candidate({required String title, required String sub, Widget? pill, required VoidCallback onTap}) => InkWell(
        onTap: _saving ? null : onTap,
        borderRadius: BorderRadius.circular(R.md),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: 10),
          margin: const EdgeInsets.only(top: 6),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(R.md),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(children: [
            Icon(LucideIcons.user, size: 18, color: AppColors.brandLight),
            const SizedBox(width: Sp.sm),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(iso(title), style: AppType.bodyStrong(color: AppColors.textHi), maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(iso(sub), style: AppType.muted(color: AppColors.textMid), maxLines: 2, overflow: TextOverflow.ellipsis),
              ]),
            ),
            if (pill != null) ...[const SizedBox(width: Sp.sm), pill],
            const SizedBox(width: Sp.sm),
            Icon(LucideIcons.check, size: 18, color: AppTone.success.onSoft),
          ]),
        ),
      );
}
