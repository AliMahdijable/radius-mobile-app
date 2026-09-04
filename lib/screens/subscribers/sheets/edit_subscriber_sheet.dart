import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../api/subscribers_api.dart';
import '../../../core/util/contact_picker.dart';
import '../../../models/subscriber.dart';
import '../../../services/auth_storage.dart';
import '../../../services/subscriber_events.dart';
import '../../../core/widgets/design_sheet.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';
import '../../../core/widgets/sheet_scaffold.dart';

/// Edit subscriber sheet — focused port of v1's _showEditSheet from
/// mobile-app/lib/screens/subscribers/subscriber_details_screen.dart.
/// First pass covers the 6 most commonly edited fields:
///   • username (rename — risky, allowed because admins do use it)
///   • password (blank → unchanged; only typed value lands in body)
///   • firstname / lastname (Arabic name)
///   • phone
///   • profile / package (dropdown from cached packages catalogue)
///
/// expiration + parent_id are intentionally omitted from this first
/// cut — both need extra plumbing (date picker / managers fetch)
/// and were permission-gated in v1 anyway. They can layer on later
/// without disturbing this sheet's shape.
///
/// Submit calls SubscribersApi.updateSubscriber with ONLY the fields
/// that changed; backend already diffs internally but sending less
/// keeps the request honest and the logs clearer. On success the
/// sheet pops + notifyChange so the open detail screen re-fetches.
Future<bool?> showEditSubscriberSheet(
  BuildContext context,
  Subscriber sub,
) {
  return showModalBottomSheet<bool>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: AppColors.scrim,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _EditSheet(sub: sub),
  );
}

class _EditSheet extends StatefulWidget {
  const _EditSheet({required this.sub});
  final Subscriber sub;

  @override
  State<_EditSheet> createState() => _EditSheetState();
}

class _EditSheetState extends State<_EditSheet> {
  late final TextEditingController _username =
      TextEditingController(text: widget.sub.username);
  // Pre-fill with the SAS4-stored password so the admin can reveal
  // it (eye toggle) to check / copy / decide whether to change.
  // Falls back to '' when the backend hasn't surfaced the field yet
  // (older client + new backend gap window).
  late final TextEditingController _password =
      TextEditingController(text: widget.sub.password ?? '');
  late final TextEditingController _firstname =
      TextEditingController(text: widget.sub.firstname);
  late final TextEditingController _lastname =
      TextEditingController(text: widget.sub.lastname);
  late final TextEditingController _phone = TextEditingController(
    text: (widget.sub.phone?.isNotEmpty ?? false)
        ? widget.sub.phone!
        : (widget.sub.mobile ?? ''),
  );
  // Set in initState — Dart forbids referencing `widget` at field-
  // initializer level for non-`late` fields, and `late int?` reads
  // awkwardly. Plain field + assignment in initState matches the
  // pattern the other sheets use for nullable mutable state.
  int? _profileId;
  Map<String, PackageInfo>? _packages;
  bool _loadingPackages = true;
  bool _saving = false;

  /// Whether the password field is revealed (eye icon toggled on).
  /// مطلب 2026-06-10: pre-fill + eye toggle so admins can verify
  /// the existing password before deciding to change it.
  bool _showPassword = false;

  /// Whether the admin can change the parent ('تابع إلى'). Mirrors
  /// v1's canPickParent = canAccessManagers — مدير بصلاحية إنشاء
  /// المدراء الفرعيين يقدر يعيد إسناد المشترك لمدير آخر.
  bool _canPickParent = false;

  /// Whether the admin can edit the expiration date. Mirrors v1's
  /// canEditExpiration = canAccessManagers OR canAccessPackages.
  /// الأدمن الفرعي العادي ما يقدر يغيّر تاريخ الانتهاء.
  bool _canEditExpiration = false;

  /// Edited expiration date — null means 'keep original'. Format
  /// matches SAS4: 'YYYY-MM-DD HH:mm:ss'.
  DateTime? _expiration;

  /// Edited parent (تابع إلى) — null means 'keep original'.
  int? _parentId;
  List<({int id, String username, String firstname, String lastname})>?
      _managers;
  bool _loadingManagers = false;

  @override
  void initState() {
    super.initState();
    _profileId = widget.sub.profileId;
    // Listen on every text controller so the 'حفظ التغييرات' button
    // re-evaluates _hasChanges on each keystroke — without these the
    // button was stuck disabled because nothing triggered a rebuild
    // when the admin typed (مطلب 2026-06-10).
    void touch() {
      if (mounted) setState(() {});
    }
    _username.addListener(touch);
    _password.addListener(touch);
    _firstname.addListener(touch);
    _lastname.addListener(touch);
    _phone.addListener(touch);
    _loadPackages();
    // Parse the original expiration so the picker can show it
    // alongside the 'change' control. SAS4 emits both 'YYYY-MM-DD
    // HH:mm:ss' and 'YYYY-MM-DDTHH:mm:ss'; both DateTime.tryParse'able
    // after normalizing the space.
    final exp = widget.sub.expiration?.trim();
    if (exp != null && exp.isNotEmpty) {
      _expiration = DateTime.tryParse(exp.replaceFirst(' ', 'T'));
    }
    _loadDetails(); // pre-fill password + parent_id from SAS4
    _resolveSuperAdmin();
  }

  /// Fire two parallel fetches:
  ///   • /api/v2/subscribers/:idx/password → cleartext password
  ///     (SAS4 hides it from /user/:idx; the dedicated endpoint
  ///     reads /user/overview/:idx which exposes it). Matches the
  ///     v2 web edit modal flow.
  ///   • /api/v2/subscribers/:idx/activation-data → parent_id +
  ///     expiration for the super-admin pickers.
  Future<void> _loadDetails() async {
    final idx = widget.sub.idx;
    if (idx == null) return;
    final pwFuture = SubscribersApi.fetchPassword(idx);
    final dataFuture = SubscribersApi.fetchActivationData(idx);
    final pw = await pwFuture;
    final data = await dataFuture;
    if (!mounted) return;
    setState(() {
      if (pw != null && pw.isNotEmpty && _password.text.isEmpty) {
        _password.text = pw;
      }
      if (data != null) {
        final parent = data['parent_id'];
        final pid =
            parent is int ? parent : int.tryParse(parent?.toString() ?? '');
        if (pid != null) _parentId = pid;
        final rawExp = data['expiration']?.toString().trim();
        if (rawExp != null && rawExp.isNotEmpty) {
          final parsed = DateTime.tryParse(rawExp.replaceFirst(' ', 'T'));
          if (parsed != null) _expiration = parsed;
        }
      }
    });
  }

  Future<void> _resolveSuperAdmin() async {
    final canManagers = await AuthStorage.readCanAccessManagers();
    final canPackages = await AuthStorage.readCanAccessPackages();
    if (!mounted) return;
    setState(() {
      _canPickParent = canManagers;
      _canEditExpiration = canManagers || canPackages;
      _loadingManagers = canManagers;
    });
    if (canManagers) {
      final list = await SubscribersApi.loadManagers();
      if (!mounted) return;
      setState(() {
        _managers = list;
        _loadingManagers = false;
      });
    }
  }

  Future<void> _loadPackages() async {
    final pkgs = await SubscribersApi.loadPackages();
    if (!mounted) return;
    setState(() {
      _packages = pkgs;
      _loadingPackages = false;
    });
  }

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    _firstname.dispose();
    _lastname.dispose();
    _phone.dispose();
    super.dispose();
  }

  Map<String, dynamic> _diff() {
    final original = widget.sub;
    final out = <String, dynamic>{};
    final u = _username.text.trim();
    if (u != original.username) out['username'] = u;
    // Diff vs ORIGINAL password — pre-filling with the current
    // value means an untouched field shouldn't fire an update. Only
    // a genuine change lands in the body.
    final pw = _password.text;
    if (pw.isNotEmpty && pw != (original.password ?? '')) {
      out['password'] = pw;
    }
    final fn = _firstname.text.trim();
    if (fn != original.firstname) out['firstname'] = fn;
    final ln = _lastname.text.trim();
    if (ln != original.lastname) out['lastname'] = ln;
    final ph = _phone.text.trim();
    final originalPh = (original.phone ?? '').isNotEmpty
        ? original.phone!
        : (original.mobile ?? '');
    if (ph != originalPh) out['phone'] = ph;
    if (_profileId != original.profileId && _profileId != null) {
      out['profile_id'] = _profileId;
    }
    // Super-admin fields. Only diff when the picker has actually
    // moved away from the original — empty/no-pick → not in the body.
    // Permission-gated diffs: only include parent_id when the user
    // can actually pick it, same for expiration. Sending them when
    // the field isn't visible would be a silent bug.
    if (_canPickParent && _parentId != null) {
      out['parent_id'] = _parentId;
    }
    if (_canEditExpiration && _expiration != null) {
      final d = _expiration!;
      String two(int n) => n.toString().padLeft(2, '0');
      out['expiration'] =
          '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}:${two(d.second)}';
    }
    return out;
  }

  bool get _hasChanges => _diff().isNotEmpty;

  Future<void> _submit() async {
    if (_saving) return;
    final diff = _diff();
    if (diff.isEmpty) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => _saving = true);
    final result = await SubscribersApi.updateSubscriber(
      idx: widget.sub.idx!,
      username: diff['username'],
      password: diff['password'],
      firstname: diff['firstname'],
      lastname: diff['lastname'],
      phone: diff['phone'],
      profileId: diff['profile_id'],
      parentId: diff['parent_id'],
      expiration: diff['expiration'],
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (result.ok) SubscriberEvents.notifyChange();
    showSheetSnack(
        context,
        result.ok
            ? 'تم تعديل بيانات المشترك'
            : (result.message ?? 'تعذّر التعديل'),
        isError: (result.ok) ? false : true);
    if (result.ok) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    // حشوة لوحة المفاتيح صارت داخل DesignSheet.
    return DesignSheet(
      header: SheetHeaderBar(
        icon: LucideIcons.pencil,
        title: 'تعديل المشترك',
        subtitle: widget.sub.fullName,
        onClose: _saving ? () {} : () => Navigator.of(context).pop(),
      ),
      footer: SheetFooterBar(
        label: _saving
            ? 'جاري الحفظ...'
            : (_hasChanges ? 'حفظ التغييرات' : 'لا توجد تغييرات'),
        icon: LucideIcons.save,
        enabled: !_saving && _hasChanges,
        busy: _saving,
        onPressed: _submit,
      ),
      scrollable: false,
      bodyPadding: EdgeInsets.zero,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Sp.xl, Sp.lg, Sp.xl, Sp.xxl),
        children: [
          const _FieldLabel(label: 'اسم المستخدم'),
          _Field(
            controller: _username,
            hint: 'username@admin',
            enabled: !_saving,
            icon: LucideIcons.user,
          ),
          const SizedBox(height: Sp.md),
          const _FieldLabel(label: 'كلمة السر'),
          _Field(
            controller: _password,
            hint: '••••••••',
            enabled: !_saving,
            icon: LucideIcons.lock,
            obscure: !_showPassword,
            suffix: IconButton(
              icon: Icon(
                _showPassword ? LucideIcons.eyeOff : LucideIcons.eye,
                size: 16,
              ),
              color: AppColors.textMid,
              visualDensity: VisualDensity.compact,
              tooltip: _showPassword ? 'إخفاء' : 'إظهار',
              onPressed: () => setState(() => _showPassword = !_showPassword),
            ),
          ),
          const SizedBox(height: Sp.md),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const _FieldLabel(label: 'الاسم'),
                    _Field(
                      controller: _firstname,
                      hint: 'الاسم',
                      enabled: !_saving,
                      icon: LucideIcons.user,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: Sp.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const _FieldLabel(label: 'الكنية'),
                    _Field(
                      controller: _lastname,
                      hint: 'الكنية',
                      enabled: !_saving,
                      icon: LucideIcons.user,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: Sp.md),
          const _FieldLabel(label: 'رقم الهاتف'),
          _Field(
            controller: _phone,
            hint: '07XX XXX XXXX',
            enabled: !_saving,
            icon: LucideIcons.phone,
            keyboardType: TextInputType.phone,
            suffix: IconButton(
              icon: const Icon(LucideIcons.contact, size: 18),
              color: AppColors.brand,
              visualDensity: VisualDensity.compact,
              tooltip: 'اختر من دليل الأسماء',
              onPressed: _saving
                  ? null
                  : () async {
                      final r = await ContactPicker.pickPhone();
                      if (!mounted || !context.mounted) return;
                      if (r.phone != null) {
                        setState(() => _phone.text = r.phone!);
                      } else if (r.error != null) {
                        showSheetSnack(context, r.error!, isError: true);
                      }
                    },
            ),
          ),
          const SizedBox(height: Sp.md),
          const _FieldLabel(label: 'الباقة'),
          _PackagePicker(
            packages: _packages,
            loading: _loadingPackages,
            selectedId: _profileId,
            enabled: !_saving,
            onSelect: (id) => setState(() => _profileId = id),
          ),
          if (_canEditExpiration) ...[
            const SizedBox(height: Sp.md),
            const _FieldLabel(label: 'تاريخ الانتهاء'),
            _ExpirationPicker(
              value: _expiration,
              enabled: !_saving,
              onPick: (d) => setState(() => _expiration = d),
            ),
          ],
          if (_canPickParent) ...[
            const SizedBox(height: Sp.md),
            const _FieldLabel(label: 'تابع إلى (المدير)'),
            _ManagerPicker(
              managers: _managers,
              loading: _loadingManagers,
              selectedId: _parentId,
              enabled: !_saving,
              onSelect: (id) => setState(() => _parentId = id),
            ),
          ],
        ],
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Padding(
      padding: const EdgeInsets.only(bottom: 4, right: 2),
      child: Text(
        label,
        style: AppType.muted(color: AppColors.textMid).copyWith(
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.hint,
    required this.enabled,
    required this.icon,
    this.obscure = false,
    this.keyboardType,
    this.suffix,
  });
  final TextEditingController controller;
  final String hint;
  final bool enabled;
  final IconData icon;
  final bool obscure;
  final TextInputType? keyboardType;

  /// Optional trailing widget — used by the password field for the
  /// reveal/hide eye toggle.
  final Widget? suffix;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return TextField(
      controller: controller,
      enabled: enabled,
      obscureText: obscure,
      keyboardType: keyboardType,
      style: AppType.input(color: AppColors.textHi),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: AppType.input(color: AppColors.textLow),
        prefixIcon: Icon(icon, size: 16, color: AppColors.textMid),
        suffixIcon: suffix,
        filled: true,
        fillColor: AppColors.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(R.sm),
          borderSide: BorderSide(color: AppColors.border),
        ),
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      ),
    );
  }
}

class _PackagePicker extends StatelessWidget {
  const _PackagePicker({
    required this.packages,
    required this.loading,
    required this.selectedId,
    required this.enabled,
    required this.onSelect,
  });
  final Map<String, PackageInfo>? packages;
  final bool loading;
  final int? selectedId;
  final bool enabled;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    if (loading) {
      return SizedBox(
        height: 38,
        child: Center(
          child: SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppColors.brand,
            ),
          ),
        ),
      );
    }
    final pkgs = packages;
    if (pkgs == null || pkgs.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(R.sm),
          border: Border.all(color: AppColors.border),
        ),
        child: Text(
          'تعذّر جلب الباقات',
          style: AppType.subtitle(color: AppColors.textMid),
        ),
      );
    }
    // Sort by name so the picker reads predictably regardless of map
    // insertion order.
    final entries = pkgs.entries.toList()
      ..sort((a, b) => a.value.name.compareTo(b.value.name));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.sm),
        border: Border.all(color: AppColors.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          value: selectedId,
          hint: Text(
            'اختر الباقة',
            style: AppType.input(color: AppColors.textLow),
          ),
          isExpanded: true,
          icon:
              Icon(LucideIcons.chevronDown, size: 16, color: AppColors.textMid),
          onChanged: enabled
              ? (v) {
                  if (v != null) onSelect(v);
                }
              : null,
          items: [
            for (final e in entries)
              DropdownMenuItem<int>(
                value: int.tryParse(e.key),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        e.value.name,
                        style: AppType.input(color: AppColors.textHi),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (e.value.price != null) ...[
                      const SizedBox(width: 6),
                      Text(
                        '${e.value.price!.round()} د.ع',
                        style: AppType.muted(color: AppColors.warning).copyWith(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Tap-to-pick expiration date — opens the platform date picker.
/// Renders 'YYYY/MM/DD' or 'لم يُختر' when no value. Super-admin
/// only — non-super admins never see this widget (مطلب 2026-06-10).
class _ExpirationPicker extends StatelessWidget {
  const _ExpirationPicker({
    required this.value,
    required this.enabled,
    required this.onPick,
  });
  final DateTime? value;
  final bool enabled;
  final ValueChanged<DateTime> onPick;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    String two(int n) => n.toString().padLeft(2, '0');
    final label = value == null
        ? 'لم يُختر'
        : '${value!.year}/${two(value!.month)}/${two(value!.day)} '
            '${two(value!.hour)}:${two(value!.minute)}:${two(value!.second)}';
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(R.sm),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: enabled
            ? () async {
                final now = DateTime.now();
                final initial = value ?? now;
                final picked = await showDatePicker(
                  context: context,
                  initialDate: initial,
                  firstDate: DateTime(now.year - 1),
                  lastDate: DateTime(now.year + 5),
                  helpText: 'اختر تاريخ الانتهاء',
                  cancelText: 'إلغاء',
                  confirmText: 'تأكيد',
                );
                if (picked == null) return;
                if (!context.mounted) return;
                // 2026-07-16: بعد التاريخ، منتقي الوقت — كان المدير
                // يقدر يغيّر التاريخ فقط، الوقت يبقى ثابت (20:59:59
                // افتراضي) — شكوى المستخدم الحقيقية.
                final src = value;
                final pickedTime = await showTimePicker(
                  context: context,
                  initialTime: TimeOfDay(
                    hour: src?.hour ?? 20,
                    minute: src?.minute ?? 59,
                  ),
                  helpText: 'اختر وقت الانتهاء',
                  cancelText: 'إلغاء',
                  confirmText: 'تأكيد',
                );
                // لو المدير ألغى منتقي الوقت، نحافظ على الوقت الأصلي
                // (لا نخسر معلومات).
                final hour = pickedTime?.hour ?? src?.hour ?? 20;
                final minute = pickedTime?.minute ?? src?.minute ?? 59;
                onPick(DateTime(
                  picked.year,
                  picked.month,
                  picked.day,
                  hour,
                  minute,
                  src?.second ?? 59,
                ));
              }
            : null,
        borderRadius: BorderRadius.circular(R.sm),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(R.sm),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Icon(LucideIcons.calendar, size: 16, color: AppColors.textMid),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: AppType.input(
                    color: value == null ? AppColors.textLow : AppColors.textHi,
                  ),
                ),
              ),
              Icon(LucideIcons.chevronDown, size: 14, color: AppColors.textLow),
            ],
          ),
        ),
      ),
    );
  }
}

/// Dropdown of all sub-managers (from /api/v2/managers). Super-admin
/// only — non-super never see this widget. Null selection → no
/// change to parent.
class _ManagerPicker extends StatelessWidget {
  const _ManagerPicker({
    required this.managers,
    required this.loading,
    required this.selectedId,
    required this.enabled,
    required this.onSelect,
  });
  final List<({int id, String username, String firstname, String lastname})>?
      managers;
  final bool loading;
  final int? selectedId;
  final bool enabled;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    if (loading) {
      return SizedBox(
        height: 38,
        child: Center(
          child: SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppColors.brand,
            ),
          ),
        ),
      );
    }
    final list = managers;
    if (list == null || list.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(R.sm),
          border: Border.all(color: AppColors.border),
        ),
        child: Text(
          'لا يوجد مدراء',
          style: AppType.subtitle(color: AppColors.textMid),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.sm),
        border: Border.all(color: AppColors.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          value: list.any((m) => m.id == selectedId) ? selectedId : null,
          hint: Text(
            'اختر المدير',
            style: AppType.input(color: AppColors.textLow),
          ),
          isExpanded: true,
          icon:
              Icon(LucideIcons.chevronDown, size: 16, color: AppColors.textMid),
          onChanged: enabled
              ? (v) {
                  if (v != null) onSelect(v);
                }
              : null,
          items: [
            for (final m in list)
              DropdownMenuItem<int>(
                value: m.id,
                child: _ManagerItemLabel(
                  firstname: m.firstname,
                  lastname: m.lastname,
                  username: m.username,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 2026-08-26: بديل لعرض displayName المسبَق-التسلسل الذي كان يظهر
/// "admin@ota6 admin@ota6 (admin@ota6)". الآن: اسم رئيسي بارز
/// (Arabic firstname+lastname أو username كـfallback) + @username
/// ثانوي بلون مميّز، ويُخفى الثانوي إذا الاسم == username لتفادي التكرار.
class _ManagerItemLabel extends StatelessWidget {
  const _ManagerItemLabel({
    required this.firstname,
    required this.lastname,
    required this.username,
  });
  final String firstname;
  final String lastname;
  final String username;

  @override
  Widget build(BuildContext context) {
    final full =
        [firstname, lastname].where((s) => s.isNotEmpty).join(' ').trim();
    final primary = full.isNotEmpty ? full : username;
    final showSecondary = full.isNotEmpty && full != username;
    // الاسم `Expanded` والمعرّف بمقاسه: مرنان بالوزن نفسه يقتسمان
    // مناصفةً، فيُقصّ «عبد الرحمن الجبوري» (١٢٨٫٣ نقطة) في حدٍّ قدره
    // ١٢١ بينما «@najaf650» يترك نصفه فارغاً.
    return Row(
      children: [
        Expanded(
          child: Text(
            primary,
            style: AppType.input(color: AppColors.textHi),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (showSecondary) ...[
          const SizedBox(width: 6),
          Text(
            '@$username',
            style: AppType.subtitle(color: AppColors.textLow),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ],
    );
  }
}

// ───────── shared sheet chrome (copy of activate_sheet's) ─────────
