import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../api/managers_api.dart';
import '../../../core/widgets/sheet_scaffold.dart';
import '../../../services/subscriber_events.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';

/// Pre-fill payload for the edit case. null على add — كل الحقول
/// تبدأ فاضية.
class ManagerFormInitial {
  const ManagerFormInitial({
    this.username,
    this.firstname,
    this.lastname,
    this.mobile,
    this.email,
    this.aclGroupId,
    this.parentId,
    this.enabled = true,
  });
  final String? username;
  final String? firstname;
  final String? lastname;
  final String? mobile;
  final String? email;
  final int? aclGroupId;
  final int? parentId;
  final bool enabled;
}

/// الـpayload اللي الـcaller يستلمه عند الـsubmit.
typedef ManagerFormData = ({
  String username,
  String password,
  String firstname,
  String lastname,
  String mobile,
  String email,
  int? aclGroupId,
  int? parentId,
  bool enabled,
});

typedef ManagerSubmitResult = ({bool ok, String? message});

/// Shared form sheet for add/edit manager. حقول: username, password
/// (optional in edit), firstname, lastname, mobile, email, acl group
/// picker, enabled toggle.
class ManagerFormSheet extends StatefulWidget {
  const ManagerFormSheet({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accent,
    required this.submitLabel,
    required this.requirePassword,
    required this.onSubmit,
    this.initial,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color accent;
  final String submitLabel;
  final bool requirePassword;
  final Future<ManagerSubmitResult> Function(ManagerFormData) onSubmit;
  final ManagerFormInitial? initial;

  @override
  State<ManagerFormSheet> createState() => _ManagerFormSheetState();
}

class _ManagerFormSheetState extends State<ManagerFormSheet> {
  late final TextEditingController _user;
  late final TextEditingController _pass;
  late final TextEditingController _first;
  late final TextEditingController _last;
  late final TextEditingController _mobile;
  late final TextEditingController _email;
  late bool _enabled;
  int? _aclGroupId;
  int? _parentId;
  List<AclGroup> _aclGroups = const [];

  /// قائمة المدراء الفرعيين للـparent picker (مطلب 2026-06-12 مطابق v1).
  /// null = لم تُحمَّل بعد، [] = الـbackend ما رجّع أحد فنخفي الـpicker.
  List<({int id, String username, String displayName})>? _parents;
  bool _loadingAcl = true;
  bool _submitting = false;
  bool _obscurePass = true;

  @override
  void initState() {
    super.initState();
    final i = widget.initial;
    _user = TextEditingController(text: i?.username ?? '');
    _pass = TextEditingController();
    _first = TextEditingController(text: i?.firstname ?? '');
    _last = TextEditingController(text: i?.lastname ?? '');
    _mobile = TextEditingController(text: i?.mobile ?? '');
    _email = TextEditingController(text: i?.email ?? '');
    _enabled = i?.enabled ?? true;
    _aclGroupId = i?.aclGroupId;
    _parentId = i?.parentId;
    _loadAcl();
    _loadParents();
  }

  Future<void> _loadAcl() async {
    final groups = await ManagersApi.aclGroups();
    if (!mounted) return;
    setState(() {
      _aclGroups = groups;
      _loadingAcl = false;
    });
  }

  Future<void> _loadParents() async {
    final parents = await ManagersApi.lite();
    if (!mounted) return;
    setState(() => _parents = parents ?? const []);
  }

  @override
  void dispose() {
    _user.dispose();
    _pass.dispose();
    _first.dispose();
    _last.dispose();
    _mobile.dispose();
    _email.dispose();
    super.dispose();
  }

  String _trim(TextEditingController c) => c.text.trim();

  bool get _canSubmit {
    if (_submitting) return false;
    if (_trim(_user).isEmpty) return false;
    if (widget.requirePassword && _pass.text.isEmpty) return false;
    if (_aclGroupId == null) return false;
    return true;
  }

  Future<void> _doSubmit() async {
    if (!_canSubmit) return;
    setState(() => _submitting = true);
    final data = (
      username: _trim(_user),
      password: _pass.text,
      firstname: _trim(_first),
      lastname: _trim(_last),
      mobile: _trim(_mobile),
      email: _trim(_email),
      aclGroupId: _aclGroupId,
      parentId: _parentId,
      enabled: _enabled,
    );
    final r = await widget.onSubmit(data);
    if (!mounted) return;
    setState(() => _submitting = false);
    showSheetSnack(
      context,
      r.ok ? 'تم الحفظ' : (r.message ?? 'تعذّر الحفظ'),
      isError: !r.ok,
    );
    if (r.ok) {
      SubscriberEvents.notifyChange();
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    // iOS keyboard-avoidance: push the sheet up so the text fields +
    // save button stay visible when the keyboard opens.
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, controller) {
        return Container(
          decoration: BoxDecoration(
            // سطح الشيت لا سطح الكارت: الفرق نهاراً طفيف (#FBFBF9 مقابل
            // أبيض) وبنيويّ ليلاً (#1B231F مقابل #161D19) — الشيت يجب
            // أن يعلو الشاشة لا أن يغرق فيها.
            color: AppColors.surfaceSheet,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(R.sheet)),
          ),
          padding: EdgeInsets.only(bottom: bottomInset),
          child: Column(
            children: [
              const SizedBox(height: 8),
              Center(
                child: Container(
                  width: 42,
                  height: H.grabber,
                  decoration: BoxDecoration(
                    color: AppColors.grabber,
                    borderRadius: BorderRadius.circular(R.pill),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, 0),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: widget.accent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(R.md),
                      ),
                      child: Icon(widget.icon, size: 16, color: widget.accent),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(widget.title,
                              style: AppType.title(color: AppColors.textHi)
                                  .copyWith(fontSize: 15)),
                          Text(widget.subtitle,
                              style: AppType.muted().copyWith(fontSize: 11),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: _submitting
                          ? null
                          : () => Navigator.of(context).pop(),
                      icon: const Icon(LucideIcons.x, size: 16),
                      color: AppColors.textMid,
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  controller: controller,
                  padding: const EdgeInsets.fromLTRB(Sp.lg, 0, Sp.lg, Sp.huge),
                  children: [
                    _label('اسم المستخدم *'),
                    _field(_user, hint: 'manager_xxx'),
                    const SizedBox(height: Sp.md),
                    _label(widget.requirePassword
                        ? 'كلمة السر *'
                        : 'كلمة السر (اتركها فاضية لعدم التغيير)'),
                    _field(
                      _pass,
                      hint: '••••••••',
                      obscure: _obscurePass,
                      suffix: IconButton(
                        icon: Icon(
                          _obscurePass ? LucideIcons.eye : LucideIcons.eyeOff,
                          size: 16,
                          color: AppColors.textMid,
                        ),
                        onPressed: () =>
                            setState(() => _obscurePass = !_obscurePass),
                      ),
                    ),
                    const SizedBox(height: Sp.md),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _label('الاسم الأول'),
                              _field(_first, hint: 'محمد'),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _label('الكنية'),
                              _field(_last, hint: 'علي'),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: Sp.md),
                    _label('الهاتف'),
                    _field(_mobile,
                        hint: '07XXXXXXXXX', keyboard: TextInputType.phone),
                    const SizedBox(height: Sp.md),
                    _label('البريد الإلكتروني'),
                    _field(_email,
                        hint: 'example@mail.com',
                        keyboard: TextInputType.emailAddress),
                    const SizedBox(height: Sp.md),
                    _label('مجموعة الصلاحيات *'),
                    _aclPicker(),
                    // مطلب 2026-06-12: parent picker مطابق v1 — يظهر
                    // فقط لما الـbackend يرجّع قائمة مدراء (السوبر أو
                    // المدير اللي عنده فرعيين). لو فاضي = مدير عادي بدون
                    // tree، يخفى الـpicker (السيرفر يفترض الـadmin
                    // الحالي parent تلقائياً).
                    if ((_parents ?? []).isNotEmpty) ...[
                      const SizedBox(height: Sp.md),
                      _label('تابع إلى'),
                      _parentPicker(),
                    ],
                    const SizedBox(height: Sp.md),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        'الحساب مفعّل',
                        style: AppType.label(color: AppColors.textHi).copyWith(
                            fontSize: 13, fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(
                        _enabled
                            ? 'يستطيع المدير تسجيل الدخول'
                            : 'الحساب معطّل — لا يستطيع الدخول',
                        style: AppType.muted().copyWith(fontSize: 11),
                      ),
                      value: _enabled,
                      activeColor: AppColors.brand,
                      onChanged: (v) => setState(() => _enabled = v),
                    ),
                  ],
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(Sp.lg, 0, Sp.lg, Sp.md),
                  child: SizedBox(
                    height: 50,
                    child: ElevatedButton.icon(
                      onPressed: _canSubmit ? _doSubmit : null,
                      icon: _submitting
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.onBrand,
                              ),
                            )
                          : const Icon(LucideIcons.save, size: 16),
                      label: Text(
                        _submitting ? 'جاري الحفظ...' : widget.submitLabel,
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 14),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: widget.accent,
                        foregroundColor: AppColors.onBrand,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(R.md),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 4, right: 2),
        child: Text(t,
            style: AppType.muted(color: AppColors.textMid)
                .copyWith(fontSize: 11, fontWeight: FontWeight.w700)),
      );

  Widget _field(
    TextEditingController c, {
    String? hint,
    bool obscure = false,
    Widget? suffix,
    TextInputType keyboard = TextInputType.text,
  }) {
    return TextField(
      controller: c,
      obscureText: obscure,
      keyboardType: keyboard,
      onChanged: (_) => setState(() {}),
      style: AppType.input(color: AppColors.textHi),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: AppType.input(color: AppColors.textLow),
        filled: true,
        fillColor: AppColors.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(R.sm),
          borderSide: BorderSide(color: AppColors.border),
        ),
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        suffixIcon: suffix,
      ),
    );
  }

  Widget _parentPicker() {
    final parents = _parents ?? const [];
    return DropdownButtonFormField<int?>(
      value: _parentId,
      isExpanded: true,
      decoration: InputDecoration(
        filled: true,
        fillColor: AppColors.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(R.sm),
          borderSide: BorderSide(color: AppColors.borderSoft),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(R.sm),
          borderSide: BorderSide(color: AppColors.borderSoft),
        ),
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      ),
      hint: Text('افتراضي — أنا', style: TextStyle(color: AppColors.textLow)),
      items: [
        const DropdownMenuItem<int?>(
          value: null,
          child: Text('— أنا (افتراضي) —'),
        ),
        for (final p in parents)
          DropdownMenuItem<int?>(value: p.id, child: Text(p.displayName)),
      ],
      onChanged: (v) => setState(() => _parentId = v),
    );
  }

  Widget _aclPicker() {
    if (_loadingAcl) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(R.sm),
          border: Border.all(color: AppColors.border),
        ),
        alignment: Alignment.center,
        child: const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    if (_aclGroups.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.error.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(R.sm),
          border: Border.all(color: AppColors.dangerSoftBorder),
        ),
        child: Text(
          'لا توجد مجموعات صلاحيات متاحة',
          style: AppType.muted(color: AppColors.error).copyWith(fontSize: 12.5),
        ),
      );
    }
    return DropdownButtonFormField<int>(
      value: _aclGroupId,
      isExpanded: true,
      decoration: InputDecoration(
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
      hint: Text('اختر مجموعة', style: TextStyle(color: AppColors.textLow)),
      items: [
        for (final g in _aclGroups)
          DropdownMenuItem(value: g.id, child: Text(g.name)),
      ],
      onChanged: (v) => setState(() => _aclGroupId = v),
    );
  }
}
