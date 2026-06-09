import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../api/subscribers_api.dart';
import '../../../core/util/contact_picker.dart';
import '../../../models/subscriber.dart';
import '../../../services/auth_storage.dart';
import '../../../services/subscriber_events.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';

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
  List<({int id, String username, String displayName})>? _managers;
  bool _loadingManagers = false;

  @override
  void initState() {
    super.initState();
    _profileId = widget.sub.profileId;
    // Listen on every text controller so the 'حفظ التغييرات' button
    // re-evaluates _hasChanges on each keystroke — without these the
    // button was stuck disabled because nothing triggered a rebuild
    // when the admin typed (مطلب 2026-06-10).
    final touch = () {
      if (mounted) setState(() {});
    };
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
        final pid = parent is int
            ? parent
            : int.tryParse(parent?.toString() ?? '');
        if (pid != null) _parentId = pid;
        final rawExp = data['expiration']?.toString().trim();
        if (rawExp != null && rawExp.isNotEmpty) {
          final parsed =
              DateTime.tryParse(rawExp.replaceFirst(' ', 'T'));
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result.ok
              ? 'تم تعديل بيانات المشترك'
              : (result.message ?? 'تعذّر التعديل'),
        ),
        backgroundColor: result.ok ? AppColors.brand : AppColors.error,
        behavior: SnackBarBehavior.floating,
      ),
    );
    if (result.ok) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, controller) {
        return Container(
          decoration: const BoxDecoration(
            color: AppColors.surface,
            borderRadius:
                BorderRadius.vertical(top: Radius.circular(R.xl)),
          ),
          child: Column(
            children: [
              _SheetHandle(),
              _SheetHeader(
                icon: LucideIcons.pencil,
                title: 'تعديل المشترك',
                subtitle: widget.sub.fullName,
                color: AppColors.brand,
                onClose:
                    _saving ? null : () => Navigator.of(context).pop(),
              ),
              Expanded(
                child: ListView(
                  controller: controller,
                  padding: const EdgeInsets.fromLTRB(
                      Sp.lg, Sp.md, Sp.lg, Sp.huge),
                  children: [
                    _FieldLabel(label: 'اسم المستخدم'),
                    _Field(
                      controller: _username,
                      hint: 'username@admin',
                      enabled: !_saving,
                      icon: LucideIcons.user,
                    ),
                    const SizedBox(height: Sp.md),
                    _FieldLabel(label: 'كلمة السر'),
                    _Field(
                      controller: _password,
                      hint: '••••••••',
                      enabled: !_saving,
                      icon: LucideIcons.lock,
                      obscure: !_showPassword,
                      suffix: IconButton(
                        icon: Icon(
                          _showPassword
                              ? LucideIcons.eyeOff
                              : LucideIcons.eye,
                          size: 16,
                        ),
                        color: AppColors.textMid,
                        visualDensity: VisualDensity.compact,
                        tooltip:
                            _showPassword ? 'إخفاء' : 'إظهار',
                        onPressed: () => setState(
                            () => _showPassword = !_showPassword),
                      ),
                    ),
                    const SizedBox(height: Sp.md),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _FieldLabel(label: 'الاسم'),
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
                              _FieldLabel(label: 'الكنية'),
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
                    _FieldLabel(label: 'رقم الهاتف'),
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
                                final picked =
                                    await ContactPicker.pickPhone();
                                if (picked != null && mounted) {
                                  setState(() => _phone.text = picked);
                                }
                              },
                      ),
                    ),
                    const SizedBox(height: Sp.md),
                    _FieldLabel(label: 'الباقة'),
                    _PackagePicker(
                      packages: _packages,
                      loading: _loadingPackages,
                      selectedId: _profileId,
                      enabled: !_saving,
                      onSelect: (id) => setState(() => _profileId = id),
                    ),
                    if (_canEditExpiration) ...[
                      const SizedBox(height: Sp.md),
                      _FieldLabel(label: 'تاريخ الانتهاء'),
                      _ExpirationPicker(
                        value: _expiration,
                        enabled: !_saving,
                        onPick: (d) => setState(() => _expiration = d),
                      ),
                    ],
                    if (_canPickParent) ...[
                      const SizedBox(height: Sp.md),
                      _FieldLabel(label: 'تابع إلى (المدير)'),
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
              ),
              _SubmitBar(
                label: _saving
                    ? 'جاري الحفظ...'
                    : (_hasChanges ? 'حفظ التغييرات' : 'لا توجد تغييرات'),
                color: AppColors.brand,
                icon: LucideIcons.save,
                enabled: !_saving && _hasChanges,
                busy: _saving,
                onPressed: _submit,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
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
    if (loading) {
      return const SizedBox(
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
        padding: const EdgeInsets.symmetric(
            horizontal: 10, vertical: 10),
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
          icon: const Icon(LucideIcons.chevronDown,
              size: 16, color: AppColors.textMid),
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
                        style:
                            AppType.input(color: AppColors.textHi),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (e.value.price != null) ...[
                      const SizedBox(width: 6),
                      Text(
                        '${e.value.price!.round()} د.ع',
                        style: AppType.muted(
                                color: const Color(0xFFE08F2D))
                            .copyWith(
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
                if (picked != null) {
                  // Preserve any time-of-day already in the original
                  // value so a date-only pick doesn't truncate the
                  // expiration to midnight (loses ~16h of service).
                  final src = value;
                  onPick(DateTime(
                    picked.year,
                    picked.month,
                    picked.day,
                    src?.hour ?? 20,
                    src?.minute ?? 59,
                    src?.second ?? 59,
                  ));
                }
              }
            : null,
        borderRadius: BorderRadius.circular(R.sm),
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: 10, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(R.sm),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              const Icon(LucideIcons.calendar,
                  size: 16, color: AppColors.textMid),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: AppType.input(
                    color: value == null
                        ? AppColors.textLow
                        : AppColors.textHi,
                  ),
                ),
              ),
              const Icon(LucideIcons.chevronDown,
                  size: 14, color: AppColors.textLow),
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
  final List<({int id, String username, String displayName})>?
      managers;
  final bool loading;
  final int? selectedId;
  final bool enabled;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const SizedBox(
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
        padding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
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
          icon: const Icon(LucideIcons.chevronDown,
              size: 16, color: AppColors.textMid),
          onChanged: enabled
              ? (v) {
                  if (v != null) onSelect(v);
                }
              : null,
          items: [
            for (final m in list)
              DropdownMenuItem<int>(
                value: m.id,
                child: Text(
                  m.displayName,
                  style: AppType.input(color: AppColors.textHi),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ───────── shared sheet chrome (copy of activate_sheet's) ─────────

class _SheetHandle extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 6),
        child: Container(
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: AppColors.border,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      );
}

class _SheetHeader extends StatelessWidget {
  const _SheetHeader({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onClose,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.sm, Sp.sm, Sp.md),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(R.sm),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: Sp.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title,
                    style: AppType.label(color: AppColors.textHi).copyWith(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        height: 1.2)),
                const SizedBox(height: 3),
                Text(subtitle,
                    style: AppType.muted(color: AppColors.textMid).copyWith(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        height: 1.2),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(LucideIcons.x, size: 20),
            color: AppColors.textMid,
            visualDensity: VisualDensity.compact,
            onPressed: onClose,
          ),
        ],
      ),
    );
  }
}

class _SubmitBar extends StatelessWidget {
  const _SubmitBar({
    required this.label,
    required this.color,
    required this.icon,
    required this.enabled,
    required this.busy,
    required this.onPressed,
  });
  final String label;
  final Color color;
  final IconData icon;
  final bool enabled;
  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.sm, Sp.lg, Sp.md),
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        child: SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: color,
              disabledBackgroundColor: color.withValues(alpha: 0.35),
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(R.md),
              ),
            ),
            onPressed: enabled ? onPressed : null,
            icon: busy
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Icon(icon, size: 16),
            label: Text(label,
                style: const TextStyle(
                    fontWeight: FontWeight.w800, fontSize: 14)),
          ),
        ),
      ),
    );
  }
}
