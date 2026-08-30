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

/// Add new subscriber sheet — focused port of v1's add_subscriber_sheet
/// (mobile-app/lib/widgets/add_subscriber_sheet.dart) into v2's design
/// language. Six fields, all required for SAS4 to accept the create:
///   • اسم المستخدم — username, no @rezz suffix (backend appends)
///   • كلمة السر    — password (also used as confirm_password)
///   • الاسم        — firstname (Arabic)
///   • الكنية       — lastname  (Arabic)
///   • رقم الهاتف   — phone
///   • الباقة       — profile dropdown from cached packages
/// parent_id defaults to the logged-in admin's id (resolved from
/// AuthStorage). expiration is left blank so SAS4 falls back to the
/// package's default duration on first activation — matches v1.
Future<bool?> showAddSubscriberSheet(BuildContext context) {
  return showModalBottomSheet<bool>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: AppColors.scrim,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => const _AddSheet(),
  );
}

class _AddSheet extends StatefulWidget {
  const _AddSheet();

  @override
  State<_AddSheet> createState() => _AddSheetState();
}

class _AddSheetState extends State<_AddSheet> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _firstname = TextEditingController();
  final _lastname = TextEditingController();
  final _phone = TextEditingController();
  int? _profileId;
  Map<String, PackageInfo>? _packages;
  bool _loadingPackages = true;
  bool _saving = false;

  /// Permission gates — mirror v1's add_subscriber_sheet:
  ///   canPickParent     = canAccessManagers (super OR
  ///                       prm_managers_create)
  ///   canEditExpiration = canAccessManagers OR canAccessPackages
  /// Hidden entirely for sub-managers who hold neither, so they
  /// only fill the basic fields and the package picker.
  bool _canPickParent = false;
  bool _canEditExpiration = false;
  DateTime? _expiration;
  int? _parentId;
  List<({int id, String username, String firstname, String lastname})>?
      _managers;
  bool _loadingManagers = false;

  @override
  void initState() {
    super.initState();
    // Seed the expiration with the current moment (date + time down
    // to the second). مطلب 2026-06-10: 'خلي تاريخ اليوم وبنفس
    // الدقيقه والثانيه' بدل ما يطلع 'افتراضي باقة'. The admin can
    // still pick a different date — DatePicker preserves the time.
    _expiration = DateTime.now();
    _loadPackages();
    _resolveSuperAdmin();
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

  String? _validate() {
    if (_username.text.trim().isEmpty) return 'اسم المستخدم مطلوب';
    if (_password.text.isEmpty) return 'كلمة السر مطلوبة';
    if (_profileId == null) return 'اختر الباقة';
    return null;
  }

  Future<void> _submit() async {
    if (_saving) return;
    final err = _validate();
    if (err != null) {
      showSheetSnack(context, err, isError: true);
      return;
    }
    final adminId = await AuthStorage.readAdminId();
    // Permission-aware parent: if the admin can pick parent AND
    // chose one in the dropdown, use it; otherwise fall back to
    // their own admin id (default for sub-managers without the
    // canAccessManagers permission).
    final parentId = _canPickParent && _parentId != null
        ? _parentId
        : int.tryParse(adminId ?? '');
    if (parentId == null) {
      showSheetSnack(context, 'تعذّر تحديد المدير الأصلي — أعد تسجيل الدخول',
          isError: true);
      return;
    }
    setState(() => _saving = true);
    String? expirationStr;
    if (_canEditExpiration && _expiration != null) {
      final d = _expiration!;
      String two(int n) => n.toString().padLeft(2, '0');
      expirationStr =
          '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}:${two(d.second)}';
    }
    final result = await SubscribersApi.createSubscriber(
      username: _username.text.trim(),
      password: _password.text,
      profileId: _profileId!,
      parentId: parentId,
      firstname: _firstname.text.trim(),
      lastname: _lastname.text.trim(),
      phone: _phone.text.trim(),
      expiration: expirationStr,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (result.ok) SubscriberEvents.notifyChange();
    showSheetSnack(
        context,
        result.ok
            ? 'تم إضافة المشترك بنجاح'
            : (result.message ?? 'تعذّر الإضافة'),
        isError: (result.ok) ? false : true);
    if (result.ok) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    // حشوة لوحة المفاتيح صارت داخل DesignSheet.
    return DesignSheet(
      header: SheetHeaderBar(
        icon: LucideIcons.userPlus,
        title: 'مشترك جديد',
        subtitle: 'أدخل بيانات المشترك',
        onClose: _saving ? () {} : () => Navigator.of(context).pop(),
      ),
      footer: SheetFooterBar(
        label: _saving ? 'جاري الحفظ...' : 'إضافة المشترك',
        icon: LucideIcons.userPlus,
        enabled: !_saving,
        busy: _saving,
        onPressed: _submit,
      ),
      scrollable: false,
      bodyPadding: EdgeInsets.zero,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Sp.xl, Sp.lg, Sp.xl, Sp.xxl),
        children: [
          const _Lbl('اسم المستخدم *'),
          _Field(
            controller: _username,
            hint: 'مثال: ahmed@rezz',
            enabled: !_saving,
            icon: LucideIcons.user,
          ),
          const SizedBox(height: Sp.md),
          const _Lbl('كلمة السر *'),
          _Field(
            controller: _password,
            hint: '••••••••',
            enabled: !_saving,
            icon: LucideIcons.lock,
            obscure: true,
          ),
          const SizedBox(height: Sp.md),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const _Lbl('الاسم'),
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
                    const _Lbl('الكنية'),
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
          const _Lbl('رقم الهاتف'),
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
                      if (!mounted) return;
                      if (r.phone != null) {
                        setState(() => _phone.text = r.phone!);
                      } else if (r.error != null) {
                        showSheetSnack(context, r.error!, isError: true);
                      }
                    },
            ),
          ),
          const SizedBox(height: Sp.md),
          const _Lbl('الباقة *'),
          _PackagePicker(
            packages: _packages,
            loading: _loadingPackages,
            selectedId: _profileId,
            enabled: !_saving,
            onSelect: (id) => setState(() => _profileId = id),
          ),
          if (_canEditExpiration) ...[
            const SizedBox(height: Sp.md),
            const _Lbl('تاريخ الانتهاء (اختياري)'),
            _ExpirationPicker(
              value: _expiration,
              enabled: !_saving,
              onPick: (d) => setState(() => _expiration = d),
            ),
          ],
          if (_canPickParent) ...[
            const SizedBox(height: Sp.md),
            const _Lbl('تابع إلى (المدير)'),
            _ManagerPicker(
              managers: _managers,
              loading: _loadingManagers,
              selectedId: _parentId,
              enabled: !_saving,
              onSelect: (id) => setState(() => _parentId = id),
            ),
          ],
          const SizedBox(height: Sp.md),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.brandSoftBg,
              borderRadius: BorderRadius.circular(R.sm),
              border: Border.all(
                color: AppColors.brandSoftBg,
              ),
            ),
            child: Row(
              children: [
                Icon(LucideIcons.info, size: 14, color: AppColors.brand),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'سيُضاف المشترك بدون تفعيل. فعّله من شاشة التفاصيل بعد الإنشاء.',
                    style: AppType.muted(color: AppColors.textMid).copyWith(
                      fontSize: 11,
                      height: 1.45,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Lbl extends StatelessWidget {
  const _Lbl(this.label);
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

  /// Optional trailing widget — used by the phone field for the
  /// contact-picker icon.
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

/// Tap-to-pick expiration date — super-admin only.
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
        ? '—'
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
                final initial = value ?? now.add(const Duration(days: 30));
                final picked = await showDatePicker(
                  context: context,
                  initialDate: initial,
                  firstDate: now.subtract(const Duration(days: 30)),
                  lastDate: DateTime(now.year + 5),
                  helpText: 'اختر تاريخ الانتهاء',
                  cancelText: 'إلغاء',
                  confirmText: 'تأكيد',
                );
                if (picked == null) return;
                if (!context.mounted) return;
                // 2026-07-16: بعد التاريخ، منتقي الوقت — كان المدير
                // يقدر يغيّر التاريخ فقط، الوقت يبقى نفس اللحظة الحالية.
                final src = value ?? DateTime.now();
                final pickedTime = await showTimePicker(
                  context: context,
                  initialTime: TimeOfDay(hour: src.hour, minute: src.minute),
                  helpText: 'اختر وقت الانتهاء',
                  cancelText: 'إلغاء',
                  confirmText: 'تأكيد',
                );
                // لو المدير ألغى منتقي الوقت، نحافظ على الوقت الأصلي.
                final hour = pickedTime?.hour ?? src.hour;
                final minute = pickedTime?.minute ?? src.minute;
                onPick(DateTime(
                  picked.year,
                  picked.month,
                  picked.day,
                  hour,
                  minute,
                  src.second,
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
          'لا يوجد مدراء — يُسجَّل تحت حسابك',
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
            'افتراضي: حسابك',
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

/// 2026-08-26: عرض المدير في dropdown — اسم رئيسي بارز + @username
/// ثانوي بلون مميّز. يُخفى الثانوي لو الاسم == username لتفادي التكرار
/// السابق ("admin@ota6 admin@ota6 (admin@ota6)").
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
    return Row(
      children: [
        Flexible(
          child: Text(
            primary,
            style: AppType.input(color: AppColors.textHi),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (showSecondary) ...[
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              '@$username',
              style: AppType.subtitle(color: AppColors.textLow),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ],
    );
  }
}

// ───────── shared sheet chrome (copy of activate_sheet's) ─────────
