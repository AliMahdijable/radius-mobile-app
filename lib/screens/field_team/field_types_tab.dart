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
import 'field_team_widgets.dart';

/// «الأنواع والإسناد» (الموقع TypesTab — المالك: «المدير يحدد نوع التذكره والى من تسند حيث تحول تلقائي او يدوي»): كلّ نوع مهمّةٍ
/// يربط أنواعاً من تذاكر المشتركين فتصير كلّ تذكرةٍ منها مهمّة — تُسند فوراً لشخصه (تلقائيّ) أو تنتظر إسنادك (يدويّ). كلّ نوع تذكرةٍ
/// يُربط بنوعٍ واحد: المأخوذ بنوعٍ آخر يظهر مقفلاً باسم صاحبه.
class FieldTypesTab extends StatefulWidget {
  const FieldTypesTab({super.key, required this.tick, required this.onChanged, required this.onRefresh, this.canAdmin = true});
  final int tick;
  final VoidCallback onChanged;
  final Future<void> Function() onRefresh;

  /// إضافة الأنواع وتعديلها وحذفها — مدير الصفحة وحده (٢٦ نوفمبر: الموظّف يراها مقفلةً بمكانها).
  final bool canAdmin;

  @override
  State<FieldTypesTab> createState() => _FieldTypesTabState();
}

class _FieldTypesTabState extends State<FieldTypesTab> {
  List<FieldType>? _types;
  List<FieldTicketCategory> _cats = const [];
  List<FieldStaff> _staff = const [];
  String? _error;
  bool _loading = true;
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(covariant FieldTypesTab old) {
    super.didUpdateWidget(old);
    if (old.tick != widget.tick) unawaited(_load(quiet: true));
  }

  Future<void> _load({bool quiet = false}) async {
    final seq = ++_seq;
    if (!quiet && _types == null) setState(() => _loading = true);
    final (types, staff) = await (FieldTeamApi.types(), FieldTeamApi.staff()).wait;
    if (!mounted || seq != _seq) return;
    setState(() {
      _loading = false;
      if (types.items != null) {
        _types = types.items;
        _cats = types.categories;
        _error = null;
      } else if (_types == null) {
        _error = types.error;
      }
      if (staff.items != null) _staff = staff.items!;
    });
  }

  String _catLabel(String key) {
    for (final c in _cats) {
      if (c.key == key) return c.label;
    }
    return key;
  }

  FieldStaff? _staffById(int? id) {
    for (final s in _staff) {
      if (s.id == id) return s;
    }
    return null;
  }

  Future<void> _edit(FieldType? t) async {
    final all = _types ?? const <FieldType>[];
    final done = await showFieldSheet<bool>(
      context,
      FieldTypeSheet(edit: t, categories: _cats, staff: _staff, others: [
        for (final x in all)
          if (t == null || x.id != t.id) x
      ]),
    );
    if (mounted && done == true) widget.onChanged();
  }

  Future<void> _delete(FieldType t) async {
    final ok = await showConfirmSheet(
      context,
      title: 'حذف النوع «${t.name}»؟',
      message: 'المهامّ السابقة تبقى بسجلّها، وتذاكره الجديدة تبقى تذاكر حتى تربطها بنوعٍ آخر. لا يمكن التراجع.',
      confirmLabel: 'حذف',
      icon: LucideIcons.trash2,
      tone: AppTone.danger,
    );
    if (ok != true || !mounted) return;
    final r = await FieldTeamApi.deleteType(t.id);
    if (!mounted) return;
    if (!r.ok) {
      showSheetSnack(context, r.error ?? 'تعذّر الحذف', isError: true);
      return;
    }
    showSheetSnack(context, 'حُذف النوع «${t.name}»');
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final items = _types ?? const <FieldType>[];
    return RefreshIndicator(
      onRefresh: () => Future.wait([widget.onRefresh(), _load(quiet: true)]),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.sm, Sp.lg, Sp.huge),
        children: [
          FieldCard(
            key: const ValueKey('field-types-flow'),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const FieldSectionHead(
                icon: LucideIcons.workflow,
                tone: AppTone.info,
                title: 'من التذكرة إلى الفنّي',
                desc:
                    'اربط أنواع تذاكر المشتركين بنوع مهمّة، فتصير كلّ تذكرةٍ منها مهمّةً بنفسها. نوع التذكرة غير المربوط يبقى تذكرةً كما هو.',
              ),
              const SizedBox(height: Sp.md),
              Wrap(spacing: Sp.x6, runSpacing: Sp.x6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                const FieldPill(label: 'تذكرة من المشترك', icon: LucideIcons.ticket),
                Icon(LucideIcons.arrowLeft, size: 15, color: AppColors.textLow),
                const FieldPill(label: 'نوع المهمّة', tone: AppTone.brand, icon: LucideIcons.clipboardList),
                Icon(LucideIcons.arrowLeft, size: 15, color: AppColors.textLow),
                const FieldPill(label: 'تلقائيّ: لفنّيّك فوراً', tone: AppTone.success, icon: LucideIcons.zap),
                Text('أو', style: AppType.micro(color: AppColors.textMid)),
                const FieldPill(label: 'يدويّ: تختار أنت', tone: AppTone.warning, icon: LucideIcons.hand),
              ]),
            ]),
          ),
          const SizedBox(height: Sp.lg),
          Row(children: [
            Expanded(
              child: Text.rich(TextSpan(children: [
                TextSpan(text: 'الأنواع', style: AppType.bodyBold(color: AppColors.textHi)),
                if (items.isNotEmpty) TextSpan(text: ' (${items.length})', style: AppType.body(color: AppColors.textMid)),
              ])),
            ),
            if (widget.canAdmin)
              FieldFilledButton(
                key: const ValueKey('field-type-add'),
                icon: LucideIcons.plus,
                label: 'نوع جديد',
                onTap: _types == null ? null : () => unawaited(_edit(null)),
              )
            else
              FieldOutlineButton(
                key: const ValueKey('field-type-add-locked'),
                icon: LucideIcons.lock,
                label: 'نوع جديد',
                onTap: () => fieldLockedTap(context, kFieldNeedAdmin),
              ),
          ]),
          const SizedBox(height: Sp.md),
          if (_loading && _types == null)
            const Padding(padding: EdgeInsets.only(top: Sp.huge), child: Center(child: CircularProgressIndicator()))
          else if (_types == null)
            FieldCenterState(
              key: const ValueKey('field-types-error'),
              icon: LucideIcons.circleX,
              tone: AppTone.danger,
              title: 'تعذّر جلب الأنواع',
              sub: _error ?? 'اسحب للأسفل لإعادة المحاولة',
            )
          else if (items.isEmpty)
            const FieldCenterState(
              key: ValueKey('field-types-empty'),
              icon: LucideIcons.clipboardList,
              title: 'لا أنواع بعد',
              sub: 'مثلاً: «صيانة الشبكة» تربط «انقطاع أو بطء» و«الراوتر والجهاز» وتُسند تلقائيّاً لفنّيّك',
            )
          else
            for (final t in items) ...[
              _TypeCard(
                type: t,
                catLabel: _catLabel,
                person: t.isAuto ? _staffById(t.defaultStaffId) : null,
                canAdmin: widget.canAdmin,
                onEdit: () => unawaited(_edit(t)),
                onDelete: () => unawaited(_delete(t)),
              ),
              const SizedBox(height: Sp.sm),
            ],
        ],
      ),
    );
  }
}

class _TypeCard extends StatelessWidget {
  const _TypeCard({
    required this.type,
    required this.catLabel,
    required this.person,
    required this.onEdit,
    required this.onDelete,
    this.canAdmin = true,
  });
  final bool canAdmin;
  final FieldType type;
  final String Function(String key) catLabel;
  final FieldStaff? person;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final t = type;
    return FieldCard(
      key: ValueKey('field-type-${t.id}'),
      dim: !t.isActive,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          FieldIconBox(icon: LucideIcons.clipboardList, tone: t.isActive ? AppTone.brand : AppTone.neutral),
          const SizedBox(width: Sp.md),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(iso(t.name), style: AppType.bodyBold(color: AppColors.textHi)),
              Text(
                t.ticketCategories.isNotEmpty ? '${t.ticketCategories.length} من أنواع التذاكر' : 'بلا تذاكر مربوطة — للمهامّ اليدويّة',
                style: AppType.micro(color: AppColors.textMid),
              ),
            ]),
          ),
          if (!t.isActive) ...[const SizedBox(width: Sp.sm), const FieldPill(label: 'موقوف')],
        ]),
        if (t.ticketCategories.isNotEmpty) ...[
          const SizedBox(height: Sp.md),
          Wrap(spacing: Sp.x6, runSpacing: Sp.x6, children: [
            for (final k in t.ticketCategories) FieldPill(label: catLabel(k), tone: AppTone.info, icon: LucideIcons.ticket),
          ]),
        ],
        const SizedBox(height: Sp.md),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: Sp.sm + 2),
          decoration: BoxDecoration(color: AppColors.surfaceSunken, borderRadius: BorderRadius.circular(R.md)),
          child: t.isAuto
              ? Wrap(spacing: Sp.x6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  Icon(LucideIcons.zap, size: 15, color: AppColors.success),
                  Text('تلقائيّ', style: AppType.label(color: AppColors.textMid)),
                  Icon(LucideIcons.arrowLeft, size: 13, color: AppColors.textLow),
                  if (person != null) ...[
                    FieldAvatar(name: person!.fullName, size: 22),
                    Text(iso(person!.fullName), style: AppType.label(color: AppColors.textHi).copyWith(fontWeight: FontWeight.w700)),
                    if (!person!.isActive) Text('(موقوف — تنتظر إسنادك)', style: AppType.micro(color: AppColors.warningOnSoft)),
                  ] else
                    Text('لم يعد في الفريق — تنتظر إسنادك',
                        style: AppType.label(color: AppColors.warningOnSoft).copyWith(fontWeight: FontWeight.w700)),
                ])
              : Row(children: [
                  Icon(LucideIcons.hand, size: 15, color: AppColors.warningOnSoft),
                  const SizedBox(width: Sp.x6),
                  Expanded(child: Text('يدويّ — تظهر في «بانتظار الإسناد»', style: AppType.label(color: AppColors.textHi))),
                ]),
        ),
        const SizedBox(height: Sp.md),
        Divider(height: 1, color: AppColors.border),
        const SizedBox(height: Sp.md),
        Wrap(spacing: Sp.sm, runSpacing: Sp.sm, children: [
          if (canAdmin) ...[
            FieldOutlineButton(key: ValueKey('field-type-edit-${t.id}'), icon: LucideIcons.pencil, label: 'تعديل', onTap: onEdit),
            FieldOutlineButton(
              key: ValueKey('field-type-del-${t.id}'),
              icon: LucideIcons.trash2,
              tone: AppTone.danger,
              label: 'حذف',
              onTap: onDelete,
            ),
          ] else
            FieldOutlineButton(
              key: ValueKey('field-type-locked-${t.id}'),
              icon: LucideIcons.lock,
              label: 'تعديل',
              onTap: () => fieldLockedTap(context, kFieldNeedAdmin),
            ),
        ]),
      ]),
    );
  }
}

/// «نوع جديد» / «تعديل»: الاسم، وتذاكر المشتركين المربوطة (المأخوذ بنوعٍ آخر مقفلٌ باسم صاحبه)، والإسناد تلقائيّاً لشخصٍ أو يدويّاً،
/// وفعّال/موقوف. تُرجع true إن حُفظ.
class FieldTypeSheet extends StatefulWidget {
  const FieldTypeSheet({super.key, this.edit, required this.categories, required this.staff, required this.others});
  final FieldType? edit;
  final List<FieldTicketCategory> categories;
  final List<FieldStaff> staff;
  final List<FieldType> others;

  @override
  State<FieldTypeSheet> createState() => _FieldTypeSheetState();
}

class _FieldTypeSheetState extends State<FieldTypeSheet> {
  late final _name = TextEditingController(text: widget.edit?.name ?? '');
  late final Set<String> _picked = {...?widget.edit?.ticketCategories};
  late String _mode = widget.edit?.assignMode ?? 'manual';
  late int? _staffId = widget.edit?.defaultStaffId;
  late bool _active = widget.edit?.isActive ?? true;
  bool _busy = false;

  /// نوع التذكرة ⇒ اسم النوع الذي أخذه.
  late final Map<String, String> _takenBy = {
    for (final o in widget.others)
      for (final k in o.ticketCategories) k: o.name,
  };

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  bool get _ok => !_busy && _name.text.trim().isNotEmpty && (_mode == 'manual' || _staffId != null);

  Future<void> _save() async {
    if (!_ok) return;
    setState(() => _busy = true);
    final r = await FieldTeamApi.saveType(
      id: widget.edit?.id,
      name: _name.text.trim(),
      ticketCategories: [
        for (final c in widget.categories)
          if (_picked.contains(c.key)) c.key
      ],
      assignMode: _mode,
      defaultStaffId: _staffId,
      isActive: _active,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (!r.ok) {
      showSheetSnack(context, r.error ?? 'تعذّر حفظ النوع', isError: true);
      return;
    }
    showSheetSnack(context, 'حُفظ النوع');
    Navigator.of(context).pop(true);
  }

  Future<void> _pickStaff() async {
    final r = await showFieldPickSheet<int>(
      context,
      title: 'لمن تُسند تلقائيّاً',
      subtitle: 'يصله إشعار كلّ مهمّةٍ من هذا النوع فوراً',
      icon: LucideIcons.zap,
      selected: _staffId,
      empty: 'لا أحد في الفريق بعد — أضفه من «الفريق»',
      options: [
        for (final s in widget.staff.where((s) => s.isActive))
          FieldPickOption<int>(value: s.id, label: s.fullName, sub: s.roleLabel, icon: LucideIcons.hardHat),
      ],
    );
    if (r?.value != null && mounted) setState(() => _staffId = r!.value);
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final e = widget.edit;
    String? staffName;
    for (final s in widget.staff) {
      if (s.id == _staffId) staffName = s.fullName;
    }
    return DesignSheet(
      header: SheetHeaderBar(
        icon: e == null ? LucideIcons.plus : LucideIcons.pencil,
        title: e == null ? 'نوع جديد' : 'تعديل: ${e.name}',
        subtitle: 'تذاكر المشتركين المربوطة ومن تُسند له',
        onClose: () => Navigator.of(context).pop(),
      ),
      footer: SheetFooterBar(
        key: const ValueKey('field-type-save'),
        label: 'حفظ',
        icon: LucideIcons.check,
        busy: _busy,
        enabled: _ok,
        onPressed: _ok ? _save : null,
      ),
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SheetSection(
          label: 'الاسم',
          child: FieldTextBox(
            key: const ValueKey('field-type-name'),
            controller: _name,
            icon: LucideIcons.clipboardList,
            hint: 'مثلاً: صيانة الشبكة',
            maxLength: 80,
            onChanged: (_) => setState(() {}),
          ),
        ),
        const SizedBox(height: Sp.lg),
        SheetSection(
          label: 'تذاكر المشتركين المربوطة',
          footnote: 'كلّ نوع تذكرةٍ يُربط بنوعٍ واحد${_takenBy.isNotEmpty ? ' — المقفل مربوطٌ بنوعٍ آخر' : ''}',
          child: Wrap(spacing: Sp.sm, runSpacing: Sp.sm, children: [
            for (final c in widget.categories)
              _CategoryChip(
                key: ValueKey('field-type-cat-${c.key}'),
                label: c.label,
                on: _picked.contains(c.key),
                owner: _picked.contains(c.key) ? null : _takenBy[c.key],
                onTap: () => setState(() => _picked.contains(c.key) ? _picked.remove(c.key) : _picked.add(c.key)),
              ),
          ]),
        ),
        const SizedBox(height: Sp.lg),
        SheetSection(
          label: 'الإسناد',
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _ModeCard(
              key: const ValueKey('field-type-auto'),
              on: _mode == 'auto',
              icon: LucideIcons.zap,
              tone: AppTone.success,
              title: 'تلقائيّ',
              desc: 'تُسند فوراً لمن تختاره ويصله إشعارها',
              onTap: () => setState(() => _mode = 'auto'),
            ),
            const SizedBox(height: Sp.sm),
            _ModeCard(
              key: const ValueKey('field-type-manual'),
              on: _mode == 'manual',
              icon: LucideIcons.hand,
              tone: AppTone.warning,
              title: 'يدويّ',
              desc: 'تنتظر في «بانتظار الإسناد» لتختار أنت',
              onTap: () => setState(() => _mode = 'manual'),
            ),
            if (_mode == 'auto') ...[
              const SizedBox(height: Sp.sm),
              FieldPickerBox(
                key: const ValueKey('field-type-staff'),
                icon: LucideIcons.userCheck,
                text: staffName,
                placeholder: 'لمن تُسند تلقائيّاً',
                onTap: _busy ? null : _pickStaff,
              ),
            ],
          ]),
        ),
        const SizedBox(height: Sp.lg),
        SheetSwitchRow(
          key: const ValueKey('field-type-active'),
          label: 'النوع فعّال',
          value: _active,
          onChanged: (v) => setState(() => _active = v),
        ),
      ]),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({super.key, required this.label, required this.on, required this.onTap, this.owner});
  final String label;
  final bool on;

  /// مأخوذٌ بنوعٍ آخر ⇒ مقفلٌ باسمه.
  final String? owner;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final taken = owner != null;
    final fg = on ? AppColors.brand : (taken ? AppColors.textLow : AppColors.textMid);
    return Material(
      color: on ? AppColors.brandSoftBg : AppColors.surface,
      borderRadius: BorderRadius.circular(R.pill),
      child: InkWell(
        borderRadius: BorderRadius.circular(R.pill),
        onTap: taken ? null : onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 36),
          padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: Sp.x6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(R.pill),
            border: Border.all(color: on ? AppColors.brand : AppColors.border, width: on ? BW.selected : BW.normal),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (on) ...[Icon(LucideIcons.check, size: 14, color: fg), const SizedBox(width: 4)],
            if (taken) ...[Icon(LucideIcons.lock, size: 13, color: fg), const SizedBox(width: 4)],
            Flexible(
              child: Text(
                taken ? '$label · $owner' : label,
                maxLines: 2,
                style: AppType.label(color: fg).copyWith(fontWeight: FontWeight.w600),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    super.key,
    required this.on,
    required this.icon,
    required this.tone,
    required this.title,
    required this.desc,
    required this.onTap,
  });
  final bool on;
  final IconData icon;
  final AppTone tone;
  final String title;
  final String desc;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Semantics(
      selected: on,
      button: true,
      child: Material(
        color: on ? AppColors.brandSoftBg : AppColors.surface,
        borderRadius: BorderRadius.circular(R.lg),
        child: InkWell(
          borderRadius: BorderRadius.circular(R.lg),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(Sp.md),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(R.lg),
              border: Border.all(color: on ? AppColors.brand : AppColors.border, width: on ? BW.selected : BW.normal),
            ),
            child: Row(children: [
              FieldIconBox(icon: icon, tone: tone, size: 36),
              const SizedBox(width: Sp.md),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: AppType.bodyStrong(color: AppColors.textHi)),
                  Text(desc, style: AppType.micro(color: AppColors.textMid).copyWith(height: 1.5)),
                ]),
              ),
              Icon(on ? LucideIcons.circleCheck : LucideIcons.circle, size: 20, color: on ? AppColors.brand : AppColors.textLow),
            ]),
          ),
        ),
      ),
    );
  }
}
