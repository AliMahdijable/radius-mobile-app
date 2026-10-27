import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/util/bidi.dart';
import '../../../core/widgets/app_sheet.dart';
import '../../../core/widgets/design_sheet.dart';
import '../../../core/widgets/sheet_scaffold.dart';
import '../../../models/fiber_network.dart';
import '../../../services/fiber/fiber_band.dart';
import '../../../services/fiber/fiber_onu.dart';
import '../../../services/fiber/fiber_store.dart';
import '../../../services/fiber/fiber_text.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';
import 'fiber_widgets.dart';

Future<T?> _sheet<T>(BuildContext context, WidgetBuilder b) => showAppSheet<T>(
      barrierColor: AppColors.scrim,
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(R.card))),
      builder: b,
    );

InputDecoration _field(String label, {String? hint}) => InputDecoration(
      labelText: label,
      hintText: hint,
      filled: true,
      fillColor: AppColors.surfaceInput,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(R.sm), borderSide: BorderSide.none),
    );

// ══════════════════════════════ صندوق / موزّع ══════════════════════════════

/// إنشاء صندوقٍ أو موزّع على منفذ، أو تعديله. يُرجع الصندوق المحفوظ (أو `null` لإلغاء/حذف).
Future<FiberBox?> showFiberBoxSheet(
  BuildContext context, {
  required int oltId,
  required String pon,
  FiberBox? initial,
  int? parentId,
  FiberNodeKind kind = FiberNodeKind.box,
}) =>
    _sheet(context, (_) => _BoxSheet(oltId: oltId, pon: pon, initial: initial, parentId: parentId, kind: kind));

class _BoxSheet extends StatefulWidget {
  const _BoxSheet({required this.oltId, required this.pon, this.initial, this.parentId, required this.kind});
  final int oltId;
  final String pon;
  final FiberBox? initial;
  final int? parentId;
  final FiberNodeKind kind;

  @override
  State<_BoxSheet> createState() => _BoxSheetState();
}

class _BoxSheetState extends State<_BoxSheet> {
  late final _name = TextEditingController(text: widget.initial?.name ?? '');
  late final _location = TextEditingController(text: widget.initial?.location ?? '');
  late final _note = TextEditingController(text: widget.initial?.note ?? '');
  late FiberNodeKind _kind = widget.initial?.kind ?? widget.kind;
  late int _ratio = widget.initial?.ratio ?? (widget.kind == FiberNodeKind.splitter ? 4 : 8);
  late int? _parent = widget.initial?.parentId ?? widget.parentId;
  late double? _lat = widget.initial?.lat;
  late double? _lng = widget.initial?.lng;
  bool _busy = false;
  bool _locating = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _location.dispose();
    _note.dispose();
    super.dispose();
  }

  List<FiberBox> get _parents => [
        for (final b in FiberStore.layout.value.boxesOf(widget.oltId, pon: widget.pon))
          if (b.kind == FiberNodeKind.splitter && b.id != widget.initial?.id) b,
      ];

  Future<void> _locate() async {
    setState(() => _locating = true);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) throw 'خدمة الموقع مطفأة';
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) throw 'لا إذن للموقع';
      final pos = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high));
      if (!mounted) return;
      setState(() {
        _lat = double.parse(pos.latitude.toStringAsFixed(6));
        _lng = double.parse(pos.longitude.toStringAsFixed(6));
      });
    } catch (e) {
      if (mounted) showSheetSnack(context, 'تعذّر جلب الموقع: $e', isError: true);
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'اكتب اسماً للصندوق');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final b = FiberBox(
      id: widget.initial?.id ?? 0,
      oltId: widget.oltId,
      pon: widget.pon,
      name: name,
      kind: _kind,
      ratio: _ratio,
      parentId: _parent,
      location: _location.text.trim().isEmpty ? null : _location.text.trim(),
      lat: _lat,
      lng: _lng,
      note: _note.text.trim().isEmpty ? null : _note.text.trim(),
    );
    final r = await FiberStore.saveBox(b);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!r.ok) {
      setState(() => _error = r.message ?? 'تعذّر الحفظ');
      return;
    }
    Navigator.of(context).pop(r.box);
  }

  Future<void> _delete() async {
    final b = widget.initial;
    if (b == null) return;
    final ok = await showConfirmSheet(
      context,
      title: 'حذف ${b.name}؟',
      message: 'أجهزته تصير بلا صندوق، وما تحته يرتفع لما فوقه. المشتركون المربوطون يبقون مربوطين.',
      confirmLabel: 'حذف',
      icon: LucideIcons.trash2,
      tone: AppTone.danger,
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    final r = await FiberStore.deleteBox(b.id);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!r.ok) {
      setState(() => _error = r.message ?? 'تعذّر الحذف');
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final edit = widget.initial != null;
    final splitter = _kind == FiberNodeKind.splitter;
    return DesignSheet(
      header: SheetHeaderBar(
        icon: splitter ? LucideIcons.network : LucideIcons.package,
        title: edit ? 'تعديل ${widget.initial!.name}' : (splitter ? 'إضافة موزّع' : 'إضافة صندوق'),
        subtitle: '${fiberPonDisplay(widget.pon)} — الأولت لا يعرف الصناديق، ترتيبها منك',
        onClose: () => Navigator.of(context).pop(),
      ),
      footer: SheetFooterBar(
        label: edit ? 'حفظ' : 'إضافة',
        icon: LucideIcons.check,
        busy: _busy,
        onPressed: _save,
        leading: edit
            ? IconButton(
                tooltip: 'حذف',
                onPressed: _busy ? null : _delete,
                icon: Icon(LucideIcons.trash2, color: AppColors.error),
              )
            : null,
      ),
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        SegmentedButton<FiberNodeKind>(
          segments: const [
            ButtonSegment(value: FiberNodeKind.box, label: Text('صندوق'), icon: Icon(LucideIcons.package, size: 16)),
            ButtonSegment(value: FiberNodeKind.splitter, label: Text('موزّع'), icon: Icon(LucideIcons.network, size: 16)),
          ],
          selected: {_kind},
          onSelectionChanged: (s) => setState(() => _kind = s.first),
        ),
        const SizedBox(height: Sp.md),
        TextField(
          controller: _name,
          autofocus: !edit,
          decoration: _field(splitter ? 'اسم الموزّع' : 'اسم الصندوق', hint: splitter ? 'مثال: موزّع رئيسي · عمود الساحة' : 'مثال: صندوق 3-أ'),
        ),
        const SizedBox(height: Sp.md),
        Text('النسبة (عدد المخارج)', style: AppType.label(color: AppColors.textMid)),
        const SizedBox(height: Sp.xs),
        Wrap(spacing: Sp.sm, runSpacing: Sp.sm, children: [
          for (final r in FiberBox.ratios)
            ChoiceChip(
              label: Text(iso('1:$r')),
              selected: _ratio == r,
              onSelected: (_) => setState(() => _ratio = r),
              showCheckmark: false,
              selectedColor: AppColors.brandSoftBg,
              backgroundColor: AppColors.surface,
              side: BorderSide(color: _ratio == r ? AppColors.brandSoftBorder : AppColors.border),
              labelStyle: AppType.bodyStrong(color: _ratio == r ? AppColors.brandOnSoft : AppColors.textBody),
            ),
        ]),
        const SizedBox(height: Sp.md),
        DropdownButtonFormField<int?>(
          initialValue: _parents.any((p) => p.id == _parent) ? _parent : null,
          decoration: _field('يتّصل بـ'),
          items: [
            DropdownMenuItem<int?>(value: null, child: Text('المنفذ مباشرةً (${fiberPonDisplay(widget.pon)})')),
            for (final p in _parents) DropdownMenuItem<int?>(value: p.id, child: Text(p.name, overflow: TextOverflow.ellipsis)),
          ],
          onChanged: (v) => setState(() => _parent = v),
        ),
        const SizedBox(height: Sp.md),
        TextField(controller: _location, decoration: _field('المكان', hint: 'مثال: شارع المدارس · قرب الجامع')),
        const SizedBox(height: Sp.sm),
        Row(children: [
          Icon(LucideIcons.mapPin, size: 16, color: _lat == null ? AppColors.textLow : AppColors.brandLight),
          const SizedBox(width: Sp.xs),
          Expanded(
            child: Text(
              _lat == null ? 'بلا موقعٍ على الخريطة' : iso('${_lat!.toStringAsFixed(5)}, ${_lng!.toStringAsFixed(5)}'),
              style: AppType.muted(color: AppColors.textMid),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (_lat != null)
            TextButton(onPressed: () => setState(() => _lat = _lng = null), child: const Text('مسح')),
          TextButton.icon(
            onPressed: _locating ? null : _locate,
            icon: _locating
                ? SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.brand))
                : const Icon(LucideIcons.locateFixed, size: 16),
            label: const Text('موقعي الآن'),
          ),
        ]),
        const SizedBox(height: Sp.sm),
        TextField(controller: _note, maxLines: 2, decoration: _field('ملاحظة (اختياريّ)')),
        if (_error != null) ...[
          const SizedBox(height: Sp.md),
          Text(_error!, style: AppType.body(color: AppColors.error)),
        ],
      ]),
    );
  }
}

// ══════════════════════════════ إسناد أجهزة لصندوق ══════════════════════════════

/// يختار أجهزةً من المنفذ ويُسندها لصندوق — يبدأ بما لا صندوق له.
Future<bool?> showFiberAssignSheet(
  BuildContext context, {
  required int oltId,
  required String pon,
  required List<FiberOnuLive> onus,
  int? boxId,
  Set<String> preselect = const {},
}) =>
    _sheet(context, (_) => _AssignSheet(oltId: oltId, pon: pon, onus: onus, boxId: boxId, preselect: preselect));

class _AssignSheet extends StatefulWidget {
  const _AssignSheet({required this.oltId, required this.pon, required this.onus, this.boxId, required this.preselect});
  final int oltId;
  final String pon;
  final List<FiberOnuLive> onus;
  final int? boxId;
  final Set<String> preselect;

  @override
  State<_AssignSheet> createState() => _AssignSheetState();
}

class _AssignSheetState extends State<_AssignSheet> {
  late int? _box = widget.boxId;
  late final Set<String> _picked = {...widget.preselect};
  bool _busy = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final layout = FiberStore.layout.value;
    final boxes = [
      for (final b in layout.boxesOf(widget.oltId, pon: widget.pon))
        if (b.kind == FiberNodeKind.box) b,
    ];
    int? boxOf(FiberOnuLive o) => layout.recordFor(widget.oltId, o.key, o.ident)?.boxId;
    final list = [...widget.onus]..sort((a, b) {
        final ua = boxOf(a) == null ? 0 : 1;
        final ub = boxOf(b) == null ? 0 : 1;
        if (ua != ub) return ua.compareTo(ub);
        return a.onu.onuId.compareTo(b.onu.onuId);
      });
    final target = boxes.where((b) => b.id == _box).firstOrNull;
    return DesignSheet(
      header: SheetHeaderBar(
        icon: LucideIcons.packagePlus,
        title: target == null ? 'إسناد أجهزة لصندوق' : 'أجهزة ${target.name}',
        subtitle: '${fiberPonDisplay(widget.pon)} · ${FiberText.devices(_picked.length)} مختارة',
        onClose: () => Navigator.of(context).pop(),
      ),
      footer: SheetFooterBar(
        label: _box == null ? 'اختر صندوقاً' : 'إسناد ${FiberText.devices(_picked.length)}',
        icon: LucideIcons.check,
        busy: _busy,
        enabled: _box != null && _picked.isNotEmpty,
        onPressed: () async {
          setState(() => _busy = true);
          final r = await FiberStore.assign(widget.oltId, list.where((o) => _picked.contains(o.key)), _box);
          if (!context.mounted) return;
          setState(() => _busy = false);
          if (!r.ok) {
            setState(() => _error = r.message ?? 'تعذّر الحفظ');
            return;
          }
          Navigator.of(context).pop(true);
        },
      ),
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        if (boxes.isEmpty)
          Text('أضف صندوقاً أوّلاً من شاشة المنفذ.', style: AppType.body(color: AppColors.textMid))
        else
          DropdownButtonFormField<int?>(
            initialValue: _box,
            decoration: _field('الصندوق'),
            items: [for (final b in boxes) DropdownMenuItem<int?>(value: b.id, child: Text(b.name, overflow: TextOverflow.ellipsis))],
            onChanged: (v) => setState(() => _box = v),
          ),
        if (target != null) ...[
          const SizedBox(height: Sp.xs),
          Text('فيه ${FiberText.ports(target.ratio)} — مختار ${_picked.length}',
              style: AppType.muted(color: _picked.length > target.ratio ? AppColors.error : AppColors.textMid)),
        ],
        const SizedBox(height: Sp.md),
        for (final o in list)
          Material(
            type: MaterialType.transparency,
            child: CheckboxListTile(
              value: _picked.contains(o.key),
              onChanged: (v) => setState(() => v == true ? _picked.add(o.key) : _picked.remove(o.key)),
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(iso(_onuTitle(layout, widget.oltId, o)), style: AppType.bodyStrong(color: AppColors.textHi), maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(
                iso([
                  o.display,
                  if (o.rx != null) o.rx!.toStringAsFixed(1) else (o.online ? 'متّصل' : 'مفصول'),
                  if (boxOf(o) != null) 'الآن: ${layout.boxes[boxOf(o)]?.name ?? '—'}' else 'بلا صندوق',
                ].join(' · ')),
                style: AppType.muted(color: AppColors.textMid),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        if (_error != null) Text(_error!, style: AppType.body(color: AppColors.error)),
      ]),
    );
  }
}

/// اسم الجهاز للعرض: يوزر المشترك المربوط، ثمّ اسمه على الأولت، ثمّ رقمه.
String fiberOnuTitle(FiberLayout layout, int oltId, FiberOnuLive o) => _onuTitle(layout, oltId, o);

/// سطر الجهاز تحت اسمه: رقمه (إن لم يكن هو الاسم) ثمّ [rest].
String fiberOnuSub(FiberLayout layout, int oltId, FiberOnuLive o, Iterable<String> rest) =>
    [if (_onuTitle(layout, oltId, o) != o.display) o.display, ...rest].join(' · ');

String _onuTitle(FiberLayout layout, int oltId, FiberOnuLive o) {
  final u = layout.recordFor(oltId, o.key, o.ident)?.username;
  if (u != null) return u;
  final n = o.onu.name?.trim();
  if (n != null && n.isNotEmpty) return n;
  return o.display;
}

// ══════════════════════════════ جهازٌ واحد ══════════════════════════════

enum FiberOnuAction { diagnose, tech, move, link }

/// إجراءات جهازٍ واحد من شجرة المنفذ.
Future<FiberOnuAction?> showFiberOnuSheet(BuildContext context, {required int oltId, required FiberOnuLive onu, required bool canEdit}) =>
    _sheet(context, (ctx) {
      final layout = FiberStore.layout.value;
      final rec = layout.recordFor(oltId, onu.key, onu.ident);
      final box = rec?.boxId == null ? null : layout.boxes[rec!.boxId];
      final facts = <(String, String)>[
        ('الحالة', onu.online ? 'متّصل' : 'مفصول${onu.reason == null ? '' : ' · ${fiberReasonLabel(onu.reason!)}'}'),
        if (onu.changedAt != null) (onu.online ? 'متّصل منذ' : 'انقطع', FiberText.clock(onu.changedAt!, seconds: true)),
        ('الضوء', onu.rx == null ? '—' : '${onu.rx!.toStringAsFixed(1)} dBm · ${FiberBands.label(FiberBands.of(onu.rx)!)}'),
        ('الصندوق', box?.name ?? 'بلا صندوق'),
        ('المشترك', rec?.username ?? 'غير مربوط'),
        if (onu.onu.serial != null) ('SN', onu.onu.serial!),
        if (onu.onu.mac != null) ('ماك الـONU', onu.onu.mac!),
      ];
      Widget action(FiberOnuAction a, IconData icon, String label, {bool locked = false}) => Material(
            type: MaterialType.transparency,
            child: ListTile(
              leading: Icon(icon, color: locked ? AppColors.textLow : AppColors.brandLight),
              title: Text(label, style: AppType.bodyStrong(color: locked ? AppColors.textLow : AppColors.textHi)),
              trailing: locked ? Icon(LucideIcons.lock, size: 16, color: AppColors.textLow) : null,
              onTap: locked ? null : () => Navigator.of(ctx).pop(a),
            ),
          );
      return DesignSheet(
        header: SheetHeaderBar(
          icon: LucideIcons.router,
          title: _onuTitle(layout, oltId, onu),
          subtitle: '${onu.display} · ${fiberPonDisplay(onu.pon)}',
          onClose: () => Navigator.of(ctx).pop(),
        ),
        body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          for (final f in facts)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(children: [
                Expanded(child: Text(f.$1, style: AppType.muted(color: AppColors.textMid), maxLines: 1)),
                Flexible(
                  flex: 2,
                  child: Text(iso(f.$2), style: AppType.rowValue(color: AppColors.textHi), maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.end),
                ),
              ]),
            ),
          const SizedBox(height: Sp.sm),
          action(FiberOnuAction.diagnose, LucideIcons.stethoscope, 'تشخيص'),
          action(FiberOnuAction.tech, LucideIcons.wrench, 'وضع الفنّي — ضوءٌ حيّ'),
          action(FiberOnuAction.move, LucideIcons.packagePlus, box == null ? 'أسنده لصندوق' : 'انقله لصندوقٍ آخر', locked: !canEdit),
          action(FiberOnuAction.link, LucideIcons.link, rec?.username == null ? 'اربطه بمشترك' : 'غيّر المشترك المربوط', locked: !canEdit),
        ]),
      );
    });

/// عنصر قائمةٍ لجهاز (شجرة المنفذ، العطل، البحث).
class FiberOnuRow extends StatelessWidget {
  const FiberOnuRow({super.key, required this.oltId, required this.onu, this.trailing, this.onTap, this.sub, this.title});

  final int oltId;
  final FiberOnuLive onu;
  final Widget? trailing;
  final VoidCallback? onTap;
  final String? sub;

  /// اسمٌ أدقّ من اليوزر حين يُعرف (اسم المشترك من الساس).
  final String? title;

  @override
  Widget build(BuildContext context) {
    final layout = FiberStore.layout.value;
    final title = this.title ?? _onuTitle(layout, oltId, onu);
    final line = sub ??
        [
          if (title != onu.display) onu.display,
          if (onu.online) 'متّصل' else (onu.reason == null ? 'مفصول' : fiberReasonLabel(onu.reason!)),
          if (!onu.online && onu.changedAt != null) 'من ${FiberText.clock(onu.changedAt!)}',
        ].join(' · ');
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Row(children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(color: fiberOnuDot(onu), shape: BoxShape.circle)),
          const SizedBox(width: Sp.sm),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(iso(title), style: AppType.bodyStrong(color: AppColors.textHi), maxLines: 1, overflow: TextOverflow.ellipsis),
              Text(iso(line), style: AppType.muted(color: AppColors.textMid), maxLines: 1, overflow: TextOverflow.ellipsis),
            ]),
          ),
          const SizedBox(width: Sp.sm),
          trailing ??
              (onu.online || onu.rx != null
                  ? FiberRx(onu.rx, style: AppType.rowValue())
                  : Icon(onu.reason == FiberDropReason.power ? LucideIcons.plugZap : LucideIcons.unplug,
                      size: 16, color: fiberOnuDot(onu))),
        ]),
      ),
    );
  }
}
