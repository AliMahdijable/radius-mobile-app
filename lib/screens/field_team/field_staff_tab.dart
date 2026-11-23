import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../api/field_team_api.dart';
import '../../core/util/bidi.dart';
import '../../core/util/clipboard_helper.dart';
import '../../core/util/phone.dart';
import '../../core/widgets/design_sheet.dart';
import '../../core/widgets/sheet_scaffold.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import 'field_team_qr.dart';
import 'field_team_widgets.dart';

/// «الفريق» (الموقع StaffTab): رمز رابط تطبيق الفريق، والأشخاص بحال كلٍّ منهم (نشِطٌ الآن · آخر ظهور · موقوف) ومهامّه الجارية،
/// والإضافة (حسابٌ ميدانيّ مستقلّ يُحسب من حدّ الموظّفين، أو موظّفٌ موجود بحسابه نفسه)، والتعديل وكلمة المرور والحذف.
class FieldStaffTab extends StatefulWidget {
  const FieldStaffTab({super.key, required this.tick, required this.onChanged, required this.onRefresh});
  final int tick;
  final VoidCallback onChanged;
  final Future<void> Function() onRefresh;

  @override
  State<FieldStaffTab> createState() => _FieldStaffTabState();
}

class _FieldStaffTabState extends State<FieldStaffTab> {
  List<FieldStaff>? _items;
  String? _error;
  bool _loading = true;

  /// شخصٌ يُفعَّل/يُوقف الآن.
  int? _toggling;
  int _seq = 0;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
    // «نشِطٌ الآن» يتبع ظهور الفنّي (كلّ دقيقة)
    _poll = Timer.periodic(const Duration(seconds: 60), (_) => unawaited(_load(quiet: true)));
  }

  @override
  void didUpdateWidget(covariant FieldStaffTab old) {
    super.didUpdateWidget(old);
    if (old.tick != widget.tick) unawaited(_load(quiet: true));
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _load({bool quiet = false}) async {
    final seq = ++_seq;
    if (!quiet && _items == null) setState(() => _loading = true);
    final r = await FieldTeamApi.staff();
    if (!mounted || seq != _seq) return;
    setState(() {
      _loading = false;
      if (r.items != null) {
        _items = r.items;
        _error = null;
      } else if (_items == null) {
        _error = r.error;
      }
    });
  }

  Future<void> _toggle(FieldStaff s, bool on) async {
    if (_toggling != null) return;
    setState(() => _toggling = s.id);
    final r = await FieldTeamApi.updateStaff(s.id, {'is_active': on});
    if (!mounted) return;
    setState(() => _toggling = null);
    if (!r.ok) {
      showSheetSnack(context, r.error ?? 'تعذّر الحفظ', isError: true);
      return;
    }
    showSheetSnack(
      context,
      on ? 'فُعّل ${s.fullName}' : 'أُوقف ${s.fullName}${r.released > 0 ? ' — رجعت ${r.released} مهمّة بانتظار الإسناد' : ''}',
    );
    widget.onChanged();
  }

  Future<void> _add() async {
    final done = await showFieldSheet<bool>(context, FieldStaffSheet(existing: _items ?? const []));
    if (mounted && done == true) widget.onChanged();
  }

  Future<void> _edit(FieldStaff s) async {
    final done = await showFieldSheet<bool>(context, FieldStaffSheet(existing: _items ?? const [], edit: s));
    if (mounted && done == true) widget.onChanged();
  }

  Future<void> _password(FieldStaff s) async {
    final done = await showFieldSheet<bool>(context, FieldPasswordSheet(staff: s));
    if (mounted && done == true) widget.onChanged();
  }

  Future<void> _delete(FieldStaff s) async {
    final ok = await showConfirmSheet(
      context,
      title: 'حذف ${s.fullName} من الفريق؟',
      message: s.isOwn
          ? 'يُحذف حسابه الميدانيّ ويتحرّر مقعده، وتبقى مهامّه السابقة بسجلّها، وما كان جارياً يرجع بانتظار الإسناد. لا يمكن التراجع.'
          : 'يخرج من الفريق وحده — حسابه كموظّف يبقى كما هو. لا يمكن التراجع.',
      confirmLabel: 'حذف',
      icon: LucideIcons.trash2,
      tone: AppTone.danger,
    );
    if (ok != true || !mounted) return;
    final r = await FieldTeamApi.deleteStaff(s.id);
    if (!mounted) return;
    if (!r.ok) {
      showSheetSnack(context, r.error ?? 'تعذّر الحذف', isError: true);
      return;
    }
    showSheetSnack(context, 'حُذف ${s.fullName}${r.released > 0 ? ' — رجعت ${r.released} مهمّة بانتظار الإسناد' : ''}');
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final items = _items ?? const <FieldStaff>[];
    final now = DateTime.now();
    return RefreshIndicator(
      onRefresh: () => Future.wait([widget.onRefresh(), _load(quiet: true)]),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.sm, Sp.lg, Sp.huge),
        children: [
          const FieldTeamLinkCard(),
          const SizedBox(height: Sp.lg),
          Row(children: [
            Expanded(
              child: Text.rich(
                TextSpan(children: [
                  TextSpan(text: 'الفريق', style: AppType.bodyBold(color: AppColors.textHi)),
                  if (items.isNotEmpty) TextSpan(text: ' (${items.length})', style: AppType.body(color: AppColors.textMid)),
                ]),
              ),
            ),
            FieldFilledButton(
              key: const ValueKey('field-staff-add'),
              icon: LucideIcons.userPlus,
              label: 'إضافة للفريق',
              onTap: () => unawaited(_add()),
            ),
          ]),
          const SizedBox(height: Sp.md),
          if (_loading && _items == null)
            const Padding(padding: EdgeInsets.only(top: Sp.huge), child: Center(child: CircularProgressIndicator()))
          else if (_items == null)
            FieldCenterState(
              key: const ValueKey('field-staff-error'),
              icon: LucideIcons.circleX,
              tone: AppTone.danger,
              title: 'تعذّر جلب الفريق',
              sub: _error ?? 'اسحب للأسفل لإعادة المحاولة',
            )
          else if (items.isEmpty)
            const FieldCenterState(
              key: ValueKey('field-staff-empty'),
              icon: LucideIcons.users,
              title: 'لا أحد في الفريق بعد',
              sub: 'أضف حساباً ميدانيّاً جديداً (يُحسب من حدّ الموظّفين في باقتك) أو أحد موظّفيك',
            )
          else
            for (final s in items) ...[
              _StaffCard(
                staff: s,
                now: now,
                toggling: _toggling == s.id,
                onToggle: _toggling != null ? null : (v) => unawaited(_toggle(s, v)),
                onEdit: () => unawaited(_edit(s)),
                onPassword: () => unawaited(_password(s)),
                onDelete: () => unawaited(_delete(s)),
              ),
              const SizedBox(height: Sp.sm),
            ],
        ],
      ),
    );
  }
}

/// رابط تطبيق الفريق: رمز QR يصوّره الفنّي، والرابط بنسخه أو إرساله بالواتساب.
class FieldTeamLinkCard extends StatelessWidget {
  const FieldTeamLinkCard({super.key});

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return FieldCard(
      key: const ValueKey('field-team-link'),
      child: LayoutBuilder(builder: (context, c) {
        final wide = c.maxWidth >= 440;
        final info = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const FieldSectionHead(
            icon: LucideIcons.smartphone,
            title: 'تطبيق الفريق',
            desc:
                'يصوّر الفنّي الرمز بكاميرا هاتفه أو يفتح الرابط، ويدخل باسمه، ثمّ «إضافة إلى الشاشة الرئيسية» فيصير تطبيقاً تصله عليه المهامّ.',
          ),
          const SizedBox(height: Sp.md),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: Sp.sm),
            decoration: BoxDecoration(color: AppColors.surfaceSunken, borderRadius: BorderRadius.circular(R.md)),
            child: SelectableText(
              kFieldTeamAppUrl,
              textDirection: TextDirection.ltr,
              textAlign: TextAlign.left,
              style: AppType.label(color: AppColors.brand).copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: Sp.md),
          Wrap(spacing: Sp.sm, runSpacing: Sp.sm, children: [
            FieldOutlineButton(
              key: const ValueKey('field-link-copy'),
              icon: LucideIcons.copy,
              label: 'نسخ الرابط',
              onTap: () => unawaited(copyToClipboard(context, kFieldTeamAppUrl, message: 'نُسخ الرابط')),
            ),
            FieldOutlineButton(
              key: const ValueKey('field-link-wa'),
              icon: LucideIcons.messageCircle,
              tone: AppTone.success,
              label: 'أرسله بالواتساب',
              onTap: () => unawaited(fieldWhatsApp(context, null, text: 'تطبيق فريق الصيانة والمبيعات: $kFieldTeamAppUrl')),
            ),
          ]),
        ]);
        if (wide) {
          return Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            const FieldTeamQr(data: kFieldTeamAppUrl),
            const SizedBox(width: Sp.lg),
            Expanded(child: info),
          ]);
        }
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Center(child: FieldTeamQr(data: kFieldTeamAppUrl)),
          const SizedBox(height: Sp.md),
          info,
        ]);
      }),
    );
  }
}

class _StaffCard extends StatelessWidget {
  const _StaffCard({
    required this.staff,
    required this.now,
    required this.toggling,
    required this.onToggle,
    required this.onEdit,
    required this.onPassword,
    required this.onDelete,
  });
  final FieldStaff staff;
  final DateTime now;
  final bool toggling;
  final ValueChanged<bool>? onToggle;
  final VoidCallback onEdit;
  final VoidCallback onPassword;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final s = staff;
    final live = s.liveAt(now);
    final seen = !s.isActive
        ? 'موقوف'
        : live
            ? 'نشِطٌ الآن'
            : s.lastSeenAt != null
                ? fieldAgo(s.lastSeenAt)
                : 'لم يدخل بعد';
    return FieldCard(
      key: ValueKey('field-staff-${s.id}'),
      dim: !s.isActive,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          FieldAvatar(name: s.fullName, size: 48, live: s.isActive ? live : null),
          const SizedBox(width: Sp.md),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(iso(s.fullName), style: AppType.bodyBold(color: AppColors.textHi)),
              Text('${s.roleLabel} · ${s.isOwn ? 'حساب ميدانيّ' : 'موظّف'}', style: AppType.micro(color: AppColors.textMid)),
            ]),
          ),
          const SizedBox(width: Sp.sm),
          toggling
              ? const Padding(
                  padding: EdgeInsets.all(Sp.sm),
                  child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                )
              : Switch(
                  key: ValueKey('field-staff-switch-${s.id}'),
                  value: s.isActive,
                  onChanged: onToggle,
                ),
        ]),
        const SizedBox(height: Sp.md),
        Row(children: [
          Expanded(
            child: _MiniStat(
              label: 'مهامّ جارية',
              value: '${s.activeTasks}',
              color: s.activeTasks > 0 ? AppColors.info : AppColors.textHi,
            ),
          ),
          const SizedBox(width: Sp.sm),
          Expanded(child: _MiniStat(label: 'آخر ظهور', value: seen, color: live ? AppColors.success : AppColors.textHi, small: true)),
        ]),
        if ((s.username ?? '').isNotEmpty || (s.phone ?? '').isNotEmpty || (s.address ?? '').isNotEmpty) ...[
          const SizedBox(height: Sp.md),
          if ((s.username ?? '').isNotEmpty) _InfoRow(icon: LucideIcons.atSign, text: s.username!, ltr: true),
          if ((s.phone ?? '').isNotEmpty)
            _InfoRow(icon: LucideIcons.phone, text: s.phone!, ltr: true, onTap: () => unawaited(fieldCall(context, s.phone!))),
          if ((s.address ?? '').isNotEmpty) _InfoRow(icon: LucideIcons.mapPin, text: s.address!),
        ],
        const SizedBox(height: Sp.md),
        Divider(height: 1, color: AppColors.border),
        const SizedBox(height: Sp.md),
        Wrap(spacing: Sp.sm, runSpacing: Sp.sm, children: [
          FieldOutlineButton(key: ValueKey('field-staff-edit-${s.id}'), icon: LucideIcons.pencil, label: 'تعديل', onTap: onEdit),
          if (s.isOwn)
            FieldOutlineButton(
                key: ValueKey('field-staff-pw-${s.id}'), icon: LucideIcons.keyRound, label: 'كلمة المرور', onTap: onPassword),
          FieldOutlineButton(
            key: ValueKey('field-staff-del-${s.id}'),
            icon: LucideIcons.trash2,
            tone: AppTone.danger,
            label: 'حذف',
            onTap: onDelete,
          ),
        ]),
      ]),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.label, required this.value, required this.color, this.small = false});
  final String label;
  final String value;
  final Color color;
  final bool small;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: Sp.sm),
      decoration: BoxDecoration(color: AppColors.surfaceSunken, borderRadius: BorderRadius.circular(R.md)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: AppType.micro(color: AppColors.textMid)),
        const SizedBox(height: 2),
        Text(value, maxLines: 2, style: small ? AppType.bodyBold(color: color) : AppType.statValue(color: color)),
      ]),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.text, this.ltr = false, this.onTap});
  final IconData icon;
  final String text;
  final bool ltr;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(padding: const EdgeInsets.only(top: 2), child: Icon(icon, size: 15, color: AppColors.textMid)),
        const SizedBox(width: Sp.sm),
        Expanded(
          child: Text(
            ltr ? iso(text) : text,
            style: AppType.label(color: onTap != null ? AppColors.brand : AppColors.textHi).copyWith(height: 1.5),
          ),
        ),
      ]),
    );
    if (onTap == null) return row;
    return InkWell(borderRadius: BorderRadius.circular(R.sm), onTap: onTap, child: row);
  }
}

/// بيانات الدخول بعد إنشاء حسابٍ ميدانيّ أو تغيير كلمة مروره: جاهزةٌ للنسخ أو للواتساب — كلمة المرور لا تظهر مرّةً ثانية.
class FieldCredentialsView extends StatelessWidget {
  const FieldCredentialsView({super.key, required this.name, required this.username, required this.password, this.phone});
  final String name;
  final String username;
  final String password;
  final String? phone;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final msg = fieldCredentialsText(name, username, password);
    final hasPhone = waPhone(phone ?? '').isNotEmpty;
    return Column(key: const ValueKey('field-credentials'), crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      FieldNote(
        icon: LucideIcons.circleCheck,
        tone: AppTone.success,
        title: 'حساب $name جاهز',
        text: 'أرسل له بيانات الدخول — كلمة المرور لا تظهر مرّةً ثانية.',
      ),
      const SizedBox(height: Sp.md),
      Container(
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(R.lg), border: Border.all(color: AppColors.border)),
        child: Column(children: [
          for (final (i, row) in [('الرابط', kFieldTeamAppUrl), ('اسم الدخول', username), ('كلمة المرور', password)].indexed) ...[
            if (i > 0) Divider(height: 1, color: AppColors.border),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: Sp.sm + 2),
              child: Row(children: [
                Text(row.$1, style: AppType.label(color: AppColors.textMid)),
                const SizedBox(width: Sp.md),
                Expanded(
                  child: SelectableText(
                    row.$2,
                    key: ValueKey('field-cred-$i'),
                    textDirection: TextDirection.ltr,
                    textAlign: TextAlign.right,
                    style: AppType.bodyBold(color: AppColors.textHi),
                  ),
                ),
              ]),
            ),
          ],
        ]),
      ),
      const SizedBox(height: Sp.md),
      Wrap(spacing: Sp.sm, runSpacing: Sp.sm, children: [
        FieldOutlineButton(
          key: const ValueKey('field-cred-copy'),
          icon: LucideIcons.copy,
          label: 'نسخ البيانات',
          onTap: () => unawaited(copyToClipboard(context, msg, message: 'نُسخت بيانات الدخول')),
        ),
        FieldOutlineButton(
          key: const ValueKey('field-cred-wa'),
          icon: LucideIcons.messageCircle,
          tone: AppTone.success,
          label: hasPhone ? 'أرسلها له بالواتساب' : 'أرسلها بالواتساب',
          onTap: () => unawaited(fieldWhatsApp(context, phone, text: msg)),
        ),
      ]),
    ]);
  }
}

/// «إضافة للفريق» / «تعديل»: حسابٌ جديد (الاسم، اسم الدخول، كلمة المرور) أو موظّفٌ موجود — ثمّ نوع العمل والهاتف والعنوان.
/// بعد إنشاء الحساب المستقلّ: بيانات الدخول للنسخ أو الواتساب. تُرجع true إن تغيّر شيء.
class FieldStaffSheet extends StatefulWidget {
  const FieldStaffSheet({super.key, required this.existing, this.edit});
  final List<FieldStaff> existing;
  final FieldStaff? edit;

  @override
  State<FieldStaffSheet> createState() => _FieldStaffSheetState();
}

class _FieldStaffSheetState extends State<FieldStaffSheet> {
  late final _fullName = TextEditingController(text: widget.edit?.fullName ?? '');
  final _username = TextEditingController();
  final _password = TextEditingController();
  late final _phone = TextEditingController(text: widget.edit?.phone ?? '');
  late final _address = TextEditingController(text: widget.edit?.address ?? '');
  late String _role = widget.edit?.role ?? 'tech';

  /// 0 حساب جديد · 1 موظّف موجود.
  int _mode = 0;
  List<({int id, String username, String name})>? _employees;
  String? _employeesError;
  int? _empId;
  bool _busy = false;
  ({String name, String username, String password, String phone})? _created;

  bool get _editing => widget.edit != null;

  @override
  void dispose() {
    for (final c in [_fullName, _username, _password, _phone, _address]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadEmployees() async {
    if (_employees != null) return;
    final r = await FieldTeamApi.employees();
    if (!mounted) return;
    final linked = {
      for (final s in widget.existing)
        if (s.employeeId != null) s.employeeId
    };
    setState(() {
      _employees = r.items?.where((e) => !linked.contains(e.id)).toList();
      _employeesError = r.items == null ? r.error : null;
    });
  }

  bool get _ok {
    if (_busy) return false;
    if (_editing) return _fullName.text.trim().isNotEmpty;
    if (_mode == 1) return _empId != null;
    return _fullName.text.trim().isNotEmpty && _username.text.trim().length >= 3 && _password.text.length >= 6;
  }

  Future<void> _save() async {
    if (!_ok) return;
    setState(() => _busy = true);
    final phone = _phone.text.trim();
    final address = _address.text.trim();
    if (_editing) {
      final r = await FieldTeamApi.updateStaff(widget.edit!.id, {
        'full_name': _fullName.text.trim(),
        'phone': phone,
        'address': address,
        'role': _role,
      });
      if (!mounted) return;
      setState(() => _busy = false);
      if (!r.ok) {
        showSheetSnack(context, r.error ?? 'تعذّر الحفظ', isError: true);
        return;
      }
      showSheetSnack(context, 'حُفظ');
      Navigator.of(context).pop(true);
      return;
    }
    if (_mode == 1) {
      final r = await FieldTeamApi.linkEmployee(employeeId: _empId!, role: _role, phone: phone, address: address);
      if (!mounted) return;
      setState(() => _busy = false);
      if (r.error != null) {
        showSheetSnack(context, r.error!, isError: true);
        return;
      }
      showSheetSnack(context, 'أُضيف الموظّف للفريق — يدخل التطبيق باسمه وكلمة مروره نفسيهما');
      Navigator.of(context).pop(true);
      return;
    }
    final r = await FieldTeamApi.createOwn(
      fullName: _fullName.text.trim(),
      username: _username.text.trim(),
      password: _password.text,
      role: _role,
      phone: phone,
      address: address,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (r.error != null) {
      showSheetSnack(context, r.error!, isError: true);
      return;
    }
    showSheetSnack(context, 'أُنشئ الحساب');
    setState(() => _created = (name: _fullName.text.trim(), username: _username.text.trim(), password: _password.text, phone: phone));
  }

  Future<void> _pickEmployee() async {
    await _loadEmployees();
    if (!mounted) return;
    final list = _employees ?? const <({int id, String username, String name})>[];
    final r = await showFieldPickSheet<int>(
      context,
      title: 'الموظّف',
      subtitle: 'الموظّفون الفعّالون غير المضافين بعد',
      icon: LucideIcons.users,
      selected: _empId,
      empty: _employeesError ?? 'لا موظّف متاح',
      options: [
        for (final e in list) FieldPickOption<int>(value: e.id, label: e.name, sub: e.username, icon: LucideIcons.userRound),
      ],
    );
    if (r != null && mounted) setState(() => _empId = r.value);
  }

  Future<void> _pickRole() async {
    final r = await showFieldPickSheet<String>(
      context,
      title: 'نوع العمل',
      subtitle: 'ما يُسند له من المهامّ',
      icon: LucideIcons.briefcase,
      selected: _role,
      options: [for (final x in kFieldRoles) FieldPickOption<String>(value: x.key, label: x.label, icon: LucideIcons.hardHat)],
    );
    if (r?.value != null && mounted) setState(() => _role = r!.value!);
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final created = _created;
    if (created != null) {
      return DesignSheet(
        header: SheetHeaderBar(
          icon: LucideIcons.userCheck,
          tint: AppTone.success.fill,
          tintBg: AppTone.success.softBg,
          title: 'أُضيف للفريق',
          subtitle: created.name,
          onClose: () => Navigator.of(context).pop(true),
        ),
        footer: SheetFooterBar(label: 'تمّ', icon: LucideIcons.check, onPressed: () => Navigator.of(context).pop(true)),
        body: FieldCredentialsView(name: created.name, username: created.username, password: created.password, phone: created.phone),
      );
    }
    String? empName;
    for (final e in _employees ?? const <({int id, String username, String name})>[]) {
      if (e.id == _empId) empName = '${e.name} · ${e.username}';
    }
    final e = widget.edit;
    return DesignSheet(
      header: SheetHeaderBar(
        icon: _editing ? LucideIcons.pencil : LucideIcons.userPlus,
        title: _editing ? 'تعديل: ${e!.fullName}' : 'إضافة للفريق',
        subtitle: _editing
            ? e!.roleLabel
            : _mode == 0
                ? 'حسابٌ يدخل تطبيق الفريق وحده — يُحسب من حدّ الموظّفين في باقتك'
                : 'موظّفٌ عندك يدخل تطبيق الفريق بحسابه نفسه — بلا مقعدٍ جديد',
        subtitleMaxLines: 2,
        onClose: () => Navigator.of(context).pop(),
      ),
      footer: SheetFooterBar(
        key: const ValueKey('field-staff-save'),
        label: _editing ? 'حفظ' : 'إضافة',
        icon: _editing ? LucideIcons.check : LucideIcons.userPlus,
        busy: _busy,
        enabled: _ok,
        onPressed: _ok ? _save : null,
      ),
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (!_editing) ...[
          SheetSegmented(
            key: const ValueKey('field-staff-mode'),
            labels: const ['حساب جديد', 'موظّف موجود'],
            icons: const [LucideIcons.userPlus, LucideIcons.users],
            selectedIndex: _mode,
            onSelect: (i) {
              setState(() => _mode = i);
              if (i == 1) unawaited(_loadEmployees());
            },
          ),
          const SizedBox(height: Sp.lg),
        ],
        if (!_editing && _mode == 1)
          SheetSection(
            label: 'الموظّف',
            footnote: 'الموظّفون الفعّالون غير المضافين بعد',
            child: FieldPickerBox(
              key: const ValueKey('field-staff-employee'),
              icon: LucideIcons.userRound,
              text: empName,
              placeholder: _employees == null && _employeesError == null ? 'جارٍ التحميل…' : 'اختر موظّفاً',
              onTap: _busy ? null : _pickEmployee,
            ),
          )
        else
          SheetSection(
            label: 'الاسم الكامل',
            child: FieldTextBox(
              key: const ValueKey('field-staff-name'),
              controller: _fullName,
              icon: LucideIcons.userRound,
              hint: 'مثلاً: أحمد علي',
              maxLength: 190,
              onChanged: (_) => setState(() {}),
            ),
          ),
        if (!_editing && _mode == 0) ...[
          const SizedBox(height: Sp.md),
          SheetSection(
            label: 'اسم الدخول',
            footnote: 'إنكليزيّ: حروف وأرقام و . _ - @',
            child: FieldTextBox(
              key: const ValueKey('field-staff-username'),
              controller: _username,
              icon: LucideIcons.atSign,
              hint: 'ahmed.tech',
              ltr: true,
              lowercase: true,
              maxLength: 100,
              onChanged: (_) => setState(() {}),
            ),
          ),
          const SizedBox(height: Sp.md),
          SheetSection(
            label: 'كلمة المرور',
            footnote: '6 أحرف على الأقلّ، أو اقترح واحدةً بالزرّ',
            child: FieldTextBox(
              key: const ValueKey('field-staff-password'),
              controller: _password,
              icon: LucideIcons.keyRound,
              hint: '••••••',
              ltr: true,
              maxLength: 128,
              onChanged: (_) => setState(() {}),
              trailing: _SuggestButton(onTap: () => setState(() => _password.text = fieldSuggestPassword())),
            ),
          ),
        ],
        const SizedBox(height: Sp.md),
        SheetSection(
          label: 'نوع العمل',
          child: FieldPickerBox(
            key: const ValueKey('field-staff-role'),
            icon: LucideIcons.briefcase,
            text: fieldRoleLabel(_role),
            placeholder: 'نوع العمل',
            onTap: _busy ? null : _pickRole,
          ),
        ),
        const SizedBox(height: Sp.md),
        SheetSection(
          label: 'الهاتف',
          child: FieldTextBox(
            key: const ValueKey('field-staff-phone'),
            controller: _phone,
            icon: LucideIcons.phone,
            hint: '07XX XXX XXXX',
            ltr: true,
            keyboardType: TextInputType.phone,
            maxLength: 24,
          ),
        ),
        const SizedBox(height: Sp.md),
        SheetSection(
          label: 'العنوان',
          child: FieldTextBox(
            key: const ValueKey('field-staff-address'),
            controller: _address,
            icon: LucideIcons.mapPin,
            hint: 'المنطقة أو الحيّ',
            maxLength: 255,
          ),
        ),
      ]),
    );
  }
}

/// «اقترح كلمة مرور».
class _SuggestButton extends StatelessWidget {
  const _SuggestButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Tooltip(
      message: 'اقترح كلمة مرور',
      child: InkWell(
        key: const ValueKey('field-suggest-password'),
        borderRadius: BorderRadius.circular(R.sm),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(LucideIcons.sparkles, size: 18, color: AppColors.brand),
        ),
      ),
    );
  }
}

/// كلمة مرور حسابٍ ميدانيّ: يخرج من كلّ أجهزته ويدخل بالجديدة — ثمّ بياناته للنسخ أو الواتساب.
class FieldPasswordSheet extends StatefulWidget {
  const FieldPasswordSheet({super.key, required this.staff});
  final FieldStaff staff;

  @override
  State<FieldPasswordSheet> createState() => _FieldPasswordSheetState();
}

class _FieldPasswordSheetState extends State<FieldPasswordSheet> {
  final _password = TextEditingController();
  bool _busy = false;
  bool _saved = false;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy || _password.text.length < 6) return;
    setState(() => _busy = true);
    final r = await FieldTeamApi.updateStaff(widget.staff.id, {'password': _password.text});
    if (!mounted) return;
    setState(() => _busy = false);
    if (!r.ok) {
      showSheetSnack(context, r.error ?? 'تعذّر الحفظ', isError: true);
      return;
    }
    showSheetSnack(context, 'تغيّرت كلمة المرور — خرج من أجهزته، ويدخل بالجديدة');
    setState(() => _saved = true);
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final s = widget.staff;
    if (_saved && (s.username ?? '').isNotEmpty) {
      return DesignSheet(
        header: SheetHeaderBar(
          icon: LucideIcons.keyRound,
          tint: AppTone.success.fill,
          tintBg: AppTone.success.softBg,
          title: 'كلمة مرور ${s.fullName}',
          subtitle: 'تغيّرت — أرسلها له',
          onClose: () => Navigator.of(context).pop(true),
        ),
        footer: SheetFooterBar(label: 'تمّ', icon: LucideIcons.check, onPressed: () => Navigator.of(context).pop(true)),
        body: FieldCredentialsView(name: s.fullName, username: s.username!, password: _password.text, phone: s.phone),
      );
    }
    final ok = !_busy && _password.text.length >= 6;
    return DesignSheet(
      header: SheetHeaderBar(
        icon: LucideIcons.keyRound,
        title: 'كلمة مرور ${s.fullName}',
        subtitle: 'يخرج من كلّ أجهزته ويدخل بالجديدة',
        onClose: () => Navigator.of(context).pop(_saved),
      ),
      footer: SheetFooterBar(
        key: const ValueKey('field-password-save'),
        label: 'حفظ',
        icon: LucideIcons.check,
        busy: _busy,
        enabled: ok,
        onPressed: ok ? _save : null,
      ),
      body: SheetSection(
        label: 'كلمة المرور الجديدة',
        footnote: '6 أحرف على الأقلّ',
        child: FieldTextBox(
          key: const ValueKey('field-password-new'),
          controller: _password,
          icon: LucideIcons.keyRound,
          hint: '••••••',
          ltr: true,
          maxLength: 128,
          onChanged: (_) => setState(() {}),
          trailing: _SuggestButton(onTap: () => setState(() => _password.text = fieldSuggestPassword())),
        ),
      ),
    );
  }
}
