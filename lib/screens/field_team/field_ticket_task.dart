import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../api/field_team_api.dart';
import '../../core/util/bidi.dart';
import '../../core/widgets/design_sheet.dart';
import '../../core/widgets/sheet_scaffold.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import 'field_task_screen.dart';
import 'field_team_widgets.dart';

/// «حوّلها مهمّة» (٢٣ نوفمبر — كالموقع 67f4139): سطرٌ تحت أزرار حالة التذكرة في محادثتها.
///   • للتذكرة مهمّة ⇒ «مهمّة #N · حالتها · الفنّي» و«فتح المهمّة».
///   • لا مهمّة ⇒ «حوّلها مهمّة»: النوع (المربوط بنوع التذكرة افتراضاً) والشخص (شخص النوع التلقائيّ افتراضاً، وإلّا لاحقاً)، والعنوان
///     والمشترك والتفاصيل من التذكرة نفسها.
///   • الموظّف: مقفلٌ بمكانه بلا أيّ طلب (المرحلة الأولى للمدير وحده)، والقسم غير مفعّلٍ للصفحة ⇒ لا شيء.
class FieldTicketTaskRow extends StatefulWidget {
  const FieldTicketTaskRow({super.key, required this.ticketId, required this.category});
  final int ticketId;
  final String category;

  @override
  State<FieldTicketTaskRow> createState() => _FieldTicketTaskRowState();
}

class _FieldTicketTaskRowState extends State<FieldTicketTaskRow> {
  FieldTicketTask? _task;

  /// قُرئت مهمّة التذكرة (أو تعذّرت) — قبلها لا سطر، فلا يتبدّل «حوّلها» بـ«مهمّة» أمام العين.
  bool _known = false;
  bool _failed = false;
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    FieldTeamState.gate.addListener(_onGate);
    unawaited(FieldTeamState.ensureFresh());
    unawaited(_load());
  }

  @override
  void dispose() {
    FieldTeamState.gate.removeListener(_onGate);
    super.dispose();
  }

  void _onGate() {
    if (!mounted) return;
    setState(() {});
    if (!_known) unawaited(_load());
  }

  Future<void> _load() async {
    if (!FieldTeamState.canManage) return;
    final seq = ++_seq;
    final r = await FieldTeamApi.ticketTasks([widget.ticketId]);
    if (!mounted || seq != _seq) return;
    setState(() {
      _known = true;
      _failed = r == null;
      _task = r?[widget.ticketId];
    });
  }

  Future<void> _open(int id) async {
    await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => FieldTaskScreen(taskId: id)));
    if (mounted) unawaited(_load());
  }

  Future<void> _convert() async {
    final done = await showFieldSheet<bool>(context, FieldConvertSheet(ticketId: widget.ticketId, category: widget.category));
    if (mounted && done == true) unawaited(_load());
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final g = FieldTeamState.gate.value;
    if (g == null || !g.available) return const SizedBox.shrink();
    if (!g.canManage) {
      return Padding(
        key: const ValueKey('ticket-field-locked'),
        padding: const EdgeInsets.only(top: Sp.sm),
        child: Row(children: [
          Icon(LucideIcons.lock, size: 14, color: AppColors.textMid),
          const SizedBox(width: Sp.x6),
          Expanded(child: Text('«حوّلها مهمّة» لمدير الصفحة وحده الآن', style: AppType.micro(color: AppColors.textMid))),
        ]),
      );
    }
    if (!_known || _failed) return const SizedBox.shrink();
    final t = _task;
    if (t != null) {
      return Padding(
        padding: const EdgeInsets.only(top: Sp.sm),
        child: Container(
          key: const ValueKey('ticket-field-task'),
          padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: Sp.sm),
          decoration: BoxDecoration(
            color: AppColors.brandSoftBg,
            borderRadius: BorderRadius.circular(R.md),
            border: Border.all(color: AppColors.brandSoftBorder),
          ),
          child: Row(children: [
            Icon(LucideIcons.hardHat, size: 16, color: AppColors.brand),
            const SizedBox(width: Sp.sm),
            Expanded(
              child: Wrap(spacing: Sp.sm, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                Text('مهمّة #${t.id}', style: AppType.label(color: AppColors.textHi).copyWith(fontWeight: FontWeight.w700)),
                FieldStatusPill(status: t.status, label: t.statusLabel),
                Text(iso(t.assignedStaffName ?? 'بلا إسناد'), style: AppType.micro(color: AppColors.textMid)),
              ]),
            ),
            const SizedBox(width: Sp.x6),
            TextButton(
              key: const ValueKey('ticket-field-open'),
              onPressed: () => unawaited(_open(t.id)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text('فتح المهمّة', style: AppType.label(color: AppColors.brand).copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(width: 2),
                Icon(LucideIcons.chevronLeft, size: 15, color: AppColors.brand),
              ]),
            ),
          ]),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: Sp.sm),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: FieldOutlineButton(
          key: const ValueKey('ticket-field-convert'),
          icon: LucideIcons.hardHat,
          label: 'حوّلها مهمّة',
          onTap: () => unawaited(_convert()),
        ),
      ),
    );
  }
}

/// «حوّلها مهمّة»: النوع والشخص فقط — عنوانها وتفاصيلها والمشترك من التذكرة نفسها، ويغيّر الفنّي حالها فيصل المشترك تحديثها.
/// تُرجع true إن أُنشئت (أو وُجدت لها مهمّةٌ أصلاً).
class FieldConvertSheet extends StatefulWidget {
  const FieldConvertSheet({super.key, required this.ticketId, required this.category});
  final int ticketId;
  final String category;

  @override
  State<FieldConvertSheet> createState() => _FieldConvertSheetState();
}

class _FieldConvertSheetState extends State<FieldConvertSheet> {
  List<FieldType>? _types;
  List<FieldStaff>? _staff;
  List<FieldTicketCategory> _cats = const [];

  /// اختيار المدير (null = الافتراض) — `(value: null)` = «بلا نوع» / «لاحقاً» صريحاً.
  ({int? value})? _typePick;
  ({int? value})? _staffPick;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadLists());
  }

  Future<void> _loadLists() async {
    final (types, staff) = await (FieldTeamApi.types(), FieldTeamApi.staff()).wait;
    if (!mounted) return;
    setState(() {
      _types = (types.items ?? const <FieldType>[]).where((t) => t.isActive).toList();
      _cats = types.categories;
      _staff = (staff.items ?? const <FieldStaff>[]).where((s) => s.isActive).toList();
    });
  }

  /// النوع المربوط بنوع التذكرة (أوّل نوعٍ فعّال يحمله).
  FieldType? get _mapped {
    for (final t in _types ?? const <FieldType>[]) {
      if (t.ticketCategories.contains(widget.category)) return t;
    }
    return null;
  }

  int? get _typeId => _typePick != null ? _typePick!.value : _mapped?.id;

  FieldType? get _chosen {
    for (final t in _types ?? const <FieldType>[]) {
      if (t.id == _typeId) return t;
    }
    return null;
  }

  /// شخص النوع التلقائيّ إن كان فعّالاً، وإلّا لاحقاً.
  int? get _autoStaff {
    final c = _chosen;
    if (c == null || !c.isAuto) return null;
    for (final s in _staff ?? const <FieldStaff>[]) {
      if (s.id == c.defaultStaffId) return s.id;
    }
    return null;
  }

  int? get _staffId => _staffPick != null ? _staffPick!.value : _autoStaff;

  bool get _ready => !_busy && _types != null && _staff != null;

  Future<void> _submit() async {
    if (!_ready) return;
    setState(() => _busy = true);
    final staffId = _staffId;
    final r = await FieldTeamApi.createFromTicket(ticketId: widget.ticketId, typeId: _typeId, staffId: staffId);
    if (!mounted) return;
    setState(() => _busy = false);
    if (r.error != null) {
      showSheetSnack(context, r.error!, isError: true);
      if (r.linked) Navigator.of(context).pop(true);
      return;
    }
    final id = r.task?.id;
    final n = id == null ? '' : ' #$id';
    showSheetSnack(context, staffId != null ? 'أُنشئت المهمّة$n وأُسندت — وصل الفنّي إشعارها' : 'أُنشئت المهمّة$n — بانتظار إسنادك');
    Navigator.of(context).pop(true);
  }

  Future<void> _pickType() async {
    final r = await showFieldPickSheet<int>(
      context,
      title: 'النوع',
      subtitle: 'أنواع المهامّ ومن تُسند له تلقائيّاً',
      icon: LucideIcons.clipboardList,
      selected: _typeId,
      options: [
        const FieldPickOption<int>(value: null, label: 'بلا نوع', icon: LucideIcons.minus),
        for (final t in _types ?? const <FieldType>[]) FieldPickOption<int>(value: t.id, label: t.name, icon: LucideIcons.clipboardList),
      ],
    );
    // نوعٌ آخر ⇒ شخصه التلقائيّ يعود افتراضاً (ما لم يختر المدير شخصاً بنفسه)
    if (r != null && mounted) setState(() => _typePick = r);
  }

  Future<void> _pickStaff() async {
    final r = await showFieldPickSheet<int>(
      context,
      title: 'إسناد إلى',
      subtitle: 'يصل الفنّي إشعارها فوراً — أو اتركها بانتظار إسنادك',
      icon: LucideIcons.userCheck,
      selected: _staffId,
      options: [
        const FieldPickOption<int>(value: null, label: 'لاحقاً (بانتظار الإسناد)', icon: LucideIcons.hourglass),
        for (final s in _staff ?? const <FieldStaff>[])
          FieldPickOption<int>(value: s.id, label: s.fullName, sub: s.roleLabel, icon: LucideIcons.hardHat),
      ],
    );
    if (r != null && mounted) setState(() => _staffPick = r);
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    String catLabel = '';
    for (final c in _cats) {
      if (c.key == widget.category) catLabel = c.label;
    }
    final mapped = _mapped;
    final typeNote = mapped != null
        ? 'مربوطٌ بنوع التذكرة${catLabel.isNotEmpty ? ' «$catLabel»' : ''}'
        : catLabel.isNotEmpty
            ? '«$catLabel» غير مربوطٍ بنوع — اربطه من «الأنواع» فتصير تذاكره مهامّاً تلقائيّاً'
            : null;
    String? staffName;
    for (final s in _staff ?? const <FieldStaff>[]) {
      if (s.id == _staffId) staffName = s.fullName;
    }
    final loading = _types == null || _staff == null;
    return DesignSheet(
      header: SheetHeaderBar(
        icon: LucideIcons.hardHat,
        title: 'حوّلها مهمّة',
        subtitle: 'عنوانها وتفاصيلها والمشترك من التذكرة نفسها، ويغيّر الفنّي حالها فيصل المشترك تحديثها',
        subtitleMaxLines: 3,
        onClose: () => Navigator.of(context).pop(),
      ),
      footer: SheetFooterBar(
        key: const ValueKey('ticket-convert-submit'),
        label: 'إنشاء المهمّة',
        icon: LucideIcons.plus,
        busy: _busy,
        enabled: _ready,
        onPressed: _ready ? _submit : null,
      ),
      body: loading
          ? const Padding(padding: EdgeInsets.symmetric(vertical: Sp.huge), child: Center(child: CircularProgressIndicator()))
          : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              SheetSection(
                label: 'النوع',
                footnote: typeNote,
                child: FieldPickerBox(
                  key: const ValueKey('ticket-convert-type'),
                  icon: LucideIcons.tag,
                  text: _chosen?.name,
                  placeholder: 'بلا نوع',
                  onTap: _busy ? null : _pickType,
                ),
              ),
              const SizedBox(height: Sp.md),
              SheetSection(
                label: 'إسناد إلى',
                footnote: _staffPick == null && _autoStaff != null ? 'إسناد النوع التلقائيّ' : null,
                child: FieldPickerBox(
                  key: const ValueKey('ticket-convert-staff'),
                  icon: LucideIcons.userCheck,
                  text: staffName,
                  placeholder: 'لاحقاً (بانتظار الإسناد)',
                  onTap: _busy ? null : _pickStaff,
                ),
              ),
            ]),
    );
  }
}

/// «أنجز الفريق مهمّة» / «تعذّرت مهمّة» (إشعار `field_task`) ⇒ المهمّة نفسها.
Future<bool> openFieldTaskPush(NavigatorState nav, Map<String, String> data) async {
  if (data['type'] != 'field_task') return false;
  final id = int.tryParse(data['task_id'] ?? '');
  if (id == null || id <= 0) return false;
  await nav.push(MaterialPageRoute(builder: (_) => FieldTaskScreen(taskId: id)));
  return true;
}
