import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../api/subscribers_api.dart';
import '../../../services/auth_storage.dart';
import '../../../services/subscriber_events.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';

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

  @override
  void initState() {
    super.initState();
    _loadPackages();
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(err),
          backgroundColor: const Color(0xFFE08F2D),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    final adminId = await AuthStorage.readAdminId();
    final parentId = int.tryParse(adminId ?? '');
    if (parentId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تعذّر تحديد المدير الأصلي — أعد تسجيل الدخول'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    setState(() => _saving = true);
    final result = await SubscribersApi.createSubscriber(
      username: _username.text.trim(),
      password: _password.text,
      profileId: _profileId!,
      parentId: parentId,
      firstname: _firstname.text.trim(),
      lastname: _lastname.text.trim(),
      phone: _phone.text.trim(),
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (result.ok) SubscriberEvents.notifyChange();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result.ok
              ? 'تم إضافة المشترك بنجاح'
              : (result.message ?? 'تعذّر الإضافة'),
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
                icon: LucideIcons.userPlus,
                title: 'مشترك جديد',
                subtitle: 'أدخل بيانات المشترك',
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
                    _Lbl('اسم المستخدم *'),
                    _Field(
                      controller: _username,
                      hint: 'مثال: ahmed@rezz',
                      enabled: !_saving,
                      icon: LucideIcons.user,
                    ),
                    const SizedBox(height: Sp.md),
                    _Lbl('كلمة السر *'),
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
                              _Lbl('الاسم'),
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
                              _Lbl('الكنية'),
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
                    _Lbl('رقم الهاتف'),
                    _Field(
                      controller: _phone,
                      hint: '07XX XXX XXXX',
                      enabled: !_saving,
                      icon: LucideIcons.phone,
                      keyboardType: TextInputType.phone,
                    ),
                    const SizedBox(height: Sp.md),
                    _Lbl('الباقة *'),
                    _PackagePicker(
                      packages: _packages,
                      loading: _loadingPackages,
                      selectedId: _profileId,
                      enabled: !_saving,
                      onSelect: (id) => setState(() => _profileId = id),
                    ),
                    const SizedBox(height: Sp.md),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppColors.brand.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(R.sm),
                        border: Border.all(
                          color: AppColors.brand.withValues(alpha: 0.15),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(LucideIcons.info,
                              size: 14, color: AppColors.brand),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'سيُضاف المشترك بدون تفعيل. فعّله من شاشة التفاصيل بعد الإنشاء.',
                              style: AppType.muted(color: AppColors.textMid)
                                  .copyWith(
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
              ),
              _SubmitBar(
                label: _saving ? 'جاري الحفظ...' : 'إضافة المشترك',
                color: AppColors.brand,
                icon: LucideIcons.userPlus,
                enabled: !_saving,
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

class _Lbl extends StatelessWidget {
  const _Lbl(this.label);
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
  });
  final TextEditingController controller;
  final String hint;
  final bool enabled;
  final IconData icon;
  final bool obscure;
  final TextInputType? keyboardType;

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
        padding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
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
                        style: AppType.input(color: AppColors.textHi),
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
