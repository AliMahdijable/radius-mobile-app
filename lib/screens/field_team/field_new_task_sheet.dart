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

typedef _Picked = ({String name, String username, String? phone});

/// «مهمّة جديدة» (الموقع NewTaskSheet): صيانة، تركيب، أو زيارة مشترك — تُسند لشخصٍ الآن أو لاحقاً. المشترك من مشتركيه افتراضاً
/// (المالك ٢٣ نوفمبر: «اختيار المشترك يكدر الوكيل يختار من ضمن مشتركينه مو يكتبه كتابه، الافتراضي من مشتركينه او يعطي تفاصيل اخرى»)،
/// والمختار بلا هاتف ⇒ «هاتفه للتواصل». تُرجع true إن أُنشئت.
class FieldNewTaskSheet extends StatefulWidget {
  const FieldNewTaskSheet({super.key});

  @override
  State<FieldNewTaskSheet> createState() => _FieldNewTaskSheetState();
}

class _FieldNewTaskSheetState extends State<FieldNewTaskSheet> {
  final _title = TextEditingController();
  final _address = TextEditingController();
  final _details = TextEditingController();
  final _term = TextEditingController();
  final _pickedPhone = TextEditingController();
  final _subName = TextEditingController();
  final _subUser = TextEditingController();
  final _subPhone = TextEditingController();

  List<FieldType> _types = const [];
  List<FieldStaff> _staff = const [];
  int? _typeId;
  int? _staffId;

  /// 0 من مشتركيك · 1 تفاصيل أخرى.
  int _subMode = 0;
  _Picked? _picked;
  List<_Picked> _hits = const [];
  bool _searching = false;
  String? _searchError;
  Timer? _debounce;
  int _searchSeq = 0;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadLists());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    for (final c in [_title, _address, _details, _term, _pickedPhone, _subName, _subUser, _subPhone]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadLists() async {
    final (types, staff) = await (FieldTeamApi.types(), FieldTeamApi.staff()).wait;
    if (!mounted) return;
    setState(() {
      _types = (types.items ?? const <FieldType>[]).where((t) => t.isActive).toList();
      _staff = (staff.items ?? const <FieldStaff>[]).where((s) => s.isActive).toList();
    });
  }

  void _onTerm(String v) {
    _debounce?.cancel();
    final t = v.trim();
    if (t.length < 2) {
      _searchSeq++;
      setState(() {
        _hits = const [];
        _searching = false;
        _searchError = null;
      });
      return;
    }
    setState(() => _searching = true);
    _debounce = Timer(const Duration(milliseconds: 300), () => unawaited(_search(t)));
  }

  Future<void> _search(String t) async {
    final seq = ++_searchSeq;
    final r = await FieldTeamApi.searchSubscribers(t);
    if (!mounted || seq != _searchSeq) return;
    setState(() {
      _searching = false;
      _searchError = r.items == null ? r.error : null;
      _hits = [
        for (final h in r.items ?? const <({String username, String name, String? phone, String? package})>[])
          (name: h.name, username: h.username, phone: h.phone)
      ];
    });
  }

  FieldSubscriber? _subscriber() {
    if (_subMode == 0) {
      final p = _picked;
      if (p == null) return null;
      final phone = (p.phone ?? '').trim().isNotEmpty ? p.phone!.trim() : _pickedPhone.text.trim();
      return FieldSubscriber(name: p.name, username: p.username, phone: phone.isEmpty ? null : phone);
    }
    final name = _subName.text.trim();
    final user = _subUser.text.trim();
    final phone = _subPhone.text.trim();
    if (name.isEmpty && user.isEmpty && phone.isEmpty) return null;
    return FieldSubscriber(name: name.isEmpty ? null : name, username: user.isEmpty ? null : user, phone: phone.isEmpty ? null : phone);
  }

  bool get _ready => !_busy && (_title.text.trim().isNotEmpty || _typeId != null);

  Future<void> _submit() async {
    if (!_ready) return;
    setState(() => _busy = true);
    final staffId = _staffId;
    final r = await FieldTeamApi.createTask(
      title: _title.text,
      typeId: _typeId,
      staffId: staffId,
      subscriber: _subscriber(),
      address: _address.text,
      details: _details.text,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (r.error != null) {
      showSheetSnack(context, r.error!, isError: true);
      return;
    }
    showSheetSnack(context, staffId != null ? 'أُنشئت المهمّة وأُسندت — وصل الفنّي إشعارها' : 'أُنشئت المهمّة — بانتظار إسنادك');
    Navigator.of(context).pop(true);
  }

  Future<void> _pickType() async {
    final r = await showFieldPickSheet<int>(
      context,
      title: 'النوع',
      subtitle: 'أنواع المهامّ ومن تُسند له تلقائيّاً — من «الأنواع»',
      icon: LucideIcons.clipboardList,
      selected: _typeId,
      options: [
        const FieldPickOption<int>(value: null, label: 'بلا نوع', icon: LucideIcons.minus),
        for (final t in _types) FieldPickOption<int>(value: t.id, label: t.name, icon: LucideIcons.clipboardList),
      ],
    );
    if (r != null && mounted) setState(() => _typeId = r.value);
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
        for (final s in _staff)
          FieldPickOption<int>(
            value: s.id,
            label: s.fullName,
            sub: s.activeTasks > 0 ? '${s.roleLabel} · عنده ${s.activeTasks} جارية' : s.roleLabel,
            icon: LucideIcons.hardHat,
          ),
      ],
    );
    if (r != null && mounted) setState(() => _staffId = r.value);
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    String? typeName;
    for (final t in _types) {
      if (t.id == _typeId) typeName = t.name;
    }
    String? staffName;
    for (final s in _staff) {
      if (s.id == _staffId) staffName = s.fullName;
    }
    return DesignSheet(
      header: SheetHeaderBar(
        icon: LucideIcons.clipboardPlus,
        title: 'مهمّة جديدة',
        subtitle: 'صيانة، تركيب، أو زيارة مشترك — تُسند لشخصٍ الآن أو لاحقاً',
        subtitleMaxLines: 2,
        onClose: () => Navigator.of(context).pop(),
      ),
      footer: SheetFooterBar(
        key: const ValueKey('field-new-submit'),
        label: 'إنشاء',
        icon: LucideIcons.plus,
        busy: _busy,
        enabled: _ready,
        onPressed: _ready ? _submit : null,
      ),
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SheetSection(
          label: 'المهمّة باختصار',
          child: FieldTextBox(
            key: const ValueKey('field-new-title'),
            controller: _title,
            icon: LucideIcons.clipboardList,
            hint: 'مثلاً: النت مقطوع — بدّل الكونكتر',
            maxLength: 160,
            onChanged: (_) => setState(() {}),
          ),
        ),
        const SizedBox(height: Sp.md),
        SheetSection(
          label: 'النوع',
          child: FieldPickerBox(
            key: const ValueKey('field-new-type'),
            icon: LucideIcons.tag,
            text: typeName,
            placeholder: _types.isEmpty ? 'بلا نوع — أضف الأنواع من «الأنواع»' : 'بلا نوع',
            onTap: _busy ? null : _pickType,
          ),
        ),
        const SizedBox(height: Sp.md),
        SheetSection(
          label: 'إسناد إلى',
          child: FieldPickerBox(
            key: const ValueKey('field-new-staff'),
            icon: LucideIcons.userCheck,
            text: staffName,
            placeholder: 'لاحقاً (بانتظار الإسناد)',
            onTap: _busy ? null : _pickStaff,
          ),
        ),
        const SizedBox(height: Sp.lg),
        _subscriberSection(),
        const SizedBox(height: Sp.lg),
        SheetSection(
          label: 'العنوان السكنيّ',
          child: FieldTextBox(
            key: const ValueKey('field-new-address'),
            controller: _address,
            icon: LucideIcons.mapPin,
            hint: 'الحيّ، الشارع، أقرب دالّة',
            maxLength: 255,
          ),
        ),
        const SizedBox(height: Sp.md),
        SheetSection(
          label: 'التفاصيل',
          child: FieldTextBox(
            key: const ValueKey('field-new-details'),
            controller: _details,
            icon: LucideIcons.fileText,
            hint: 'ما يحتاج الفنّي أن يعرفه قبل أن يصل',
            minLines: 3,
            maxLines: 6,
            maxLength: 2000,
          ),
        ),
      ]),
    );
  }

  Widget _subscriberSection() {
    return Container(
      padding: const EdgeInsets.all(Sp.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceSunken,
        borderRadius: BorderRadius.circular(R.lg),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(LucideIcons.userRound, size: 16, color: AppColors.brand),
          const SizedBox(width: Sp.x6),
          Text('المشترك', style: AppType.labelBold(color: AppColors.textHi)),
        ]),
        const SizedBox(height: Sp.sm),
        SheetSegmented(
          key: const ValueKey('field-new-sub-mode'),
          labels: const ['من مشتركيك', 'تفاصيل أخرى'],
          selectedIndex: _subMode,
          onSelect: (i) => setState(() => _subMode = i),
        ),
        const SizedBox(height: Sp.md),
        if (_subMode == 0) ..._pickMode() else ..._otherMode(),
      ]),
    );
  }

  List<Widget> _pickMode() {
    final p = _picked;
    if (p != null) {
      return [
        Container(
          key: const ValueKey('field-new-picked'),
          padding: const EdgeInsets.all(Sp.md),
          decoration: BoxDecoration(
            color: AppColors.brandSoftBg,
            borderRadius: BorderRadius.circular(R.lg),
            border: Border.all(color: AppColors.brandSoftBorder),
          ),
          child: Row(children: [
            FieldAvatar(name: p.name, size: 40),
            const SizedBox(width: Sp.md),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(iso(p.name), style: AppType.bodyBold(color: AppColors.textHi)),
                Text(isoJoin([p.username, if ((p.phone ?? '').isNotEmpty) p.phone!], ' · '),
                    style: AppType.micro(color: AppColors.textMid)),
              ]),
            ),
            TextButton(
              key: const ValueKey('field-new-picked-change'),
              onPressed: () => setState(() {
                _picked = null;
                _pickedPhone.clear();
              }),
              child: Text('تغيير', style: AppType.label(color: AppColors.brand).copyWith(fontWeight: FontWeight.w700)),
            ),
          ]),
        ),
        if ((p.phone ?? '').isEmpty) ...[
          const SizedBox(height: Sp.md),
          SheetSection(
            label: 'هاتفه للتواصل (اختياريّ)',
            footnote: 'لا رقم له في الساس — يصل الفنّي إن كتبته',
            child: FieldTextBox(
              key: const ValueKey('field-new-picked-phone'),
              controller: _pickedPhone,
              icon: LucideIcons.phone,
              hint: '07XX XXX XXXX',
              ltr: true,
              keyboardType: TextInputType.phone,
              maxLength: 24,
            ),
          ),
        ],
      ];
    }
    final q = _term.text.trim();
    return [
      FieldTextBox(
        key: const ValueKey('field-new-search'),
        controller: _term,
        icon: LucideIcons.search,
        hint: 'الاسم، اسم الدخول، أو الهاتف',
        onChanged: _onTerm,
      ),
      const SizedBox(height: Sp.sm),
      if (q.length < 2)
        Text('اكتب حرفين أو أكثر لتظهر مشتركيك', style: AppType.micro(color: AppColors.textMid))
      else if (_searching)
        Text('جارٍ البحث في مشتركيك…', style: AppType.micro(color: AppColors.textMid))
      else if (_searchError != null)
        Text(_searchError!, style: AppType.micro(color: AppColors.error))
      else if (_hits.isEmpty)
        Text('لا مشترك بهذا البحث — إن لم يكن من مشتركيك اختر «تفاصيل أخرى».',
            style: AppType.micro(color: AppColors.textMid).copyWith(height: 1.55))
      else
        Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(R.lg),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(children: [
            for (final (i, h) in _hits.indexed) ...[
              if (i > 0) Divider(height: 1, color: AppColors.border),
              InkWell(
                key: ValueKey('field-new-hit-${h.username}'),
                onTap: () => setState(() {
                  _picked = h;
                  _hits = const [];
                  _term.clear();
                }),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: Sp.sm + 2),
                  child: Row(children: [
                    FieldAvatar(name: h.name, size: 34),
                    const SizedBox(width: Sp.md),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(iso(h.name), style: AppType.bodyStrong(color: AppColors.textHi)),
                        Text(isoJoin([h.username, if ((h.phone ?? '').isNotEmpty) h.phone!], ' · '),
                            style: AppType.micro(color: AppColors.textMid)),
                      ]),
                    ),
                  ]),
                ),
              ),
            ],
          ]),
        ),
    ];
  }

  List<Widget> _otherMode() => [
        SheetSection(
          label: 'الاسم',
          child: FieldTextBox(
            key: const ValueKey('field-new-sub-name'),
            controller: _subName,
            icon: LucideIcons.userRound,
            hint: 'اسم المشترك أو الزبون',
            maxLength: 190,
          ),
        ),
        const SizedBox(height: Sp.md),
        SheetSection(
          label: 'الهاتف',
          child: FieldTextBox(
            key: const ValueKey('field-new-sub-phone'),
            controller: _subPhone,
            icon: LucideIcons.phone,
            hint: '07XX XXX XXXX',
            ltr: true,
            keyboardType: TextInputType.phone,
            maxLength: 24,
          ),
        ),
        const SizedBox(height: Sp.md),
        SheetSection(
          label: 'اسم الدخول (اختياريّ)',
          child: FieldTextBox(
            key: const ValueKey('field-new-sub-user'),
            controller: _subUser,
            icon: LucideIcons.atSign,
            hint: 'user@sas',
            ltr: true,
            maxLength: 190,
          ),
        ),
      ];
}
