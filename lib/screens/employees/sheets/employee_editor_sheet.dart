import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../api/employees_api.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';
import '../../../core/widgets/sheet_scaffold.dart';

/// Sheet إنشاء/تعديل موظف. tab1 = معلومات، tab2 = صلاحيات. الـpresets
/// (3 افتراضية من backend: cashier/assistant_manager/viewer) تطبّق
/// مجموعة جاهزة بضغطة واحدة.
Future<bool?> showEmployeeEditorSheet(
  BuildContext context, {
  required PermissionsCatalog catalog,
  Employee? employee,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) =>
        _EmployeeEditorSheet(catalog: catalog, employee: employee),
  );
}

class _EmployeeEditorSheet extends StatefulWidget {
  const _EmployeeEditorSheet({required this.catalog, this.employee});
  final PermissionsCatalog catalog;
  final Employee? employee;

  @override
  State<_EmployeeEditorSheet> createState() => _EmployeeEditorSheetState();
}

class _EmployeeEditorSheetState extends State<_EmployeeEditorSheet>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  late TextEditingController _userCtrl;
  late TextEditingController _fullNameCtrl;
  late TextEditingController _phoneCtrl;
  late TextEditingController _passCtrl;
  late bool _isActive;
  late Map<String, bool> _perms;
  bool _saving = false;

  /// رسالة الخطأ المعروضة بأعلى الـsheet. تنمسح عند بدء الكتابة في
  /// أي حقل عشان المستخدم ما يشوف خطأ قديم بعد ما يصحّح. لو null لا
  /// banner.
  String? _error;

  bool get _isEdit => widget.employee != null;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    final e = widget.employee;
    _userCtrl = TextEditingController(text: e?.username ?? '');
    _fullNameCtrl = TextEditingController(text: e?.fullName ?? '');
    _phoneCtrl = TextEditingController(text: e?.phone ?? '');
    _passCtrl = TextEditingController();
    _isActive = e?.isActive ?? true;
    _perms = {
      ...widget.catalog.defaults,
      if (e != null) ...e.permissions,
    };
    // مسح الـerror banner تلقائياً لما المستخدم يبدأ يصحّح أي حقل.
    void clearOnEdit() {
      if (_error != null) setState(() => _error = null);
    }
    _userCtrl.addListener(clearOnEdit);
    _passCtrl.addListener(clearOnEdit);
    _fullNameCtrl.addListener(clearOnEdit);
    _phoneCtrl.addListener(clearOnEdit);
  }

  @override
  void dispose() {
    _tab.dispose();
    _userCtrl.dispose();
    _fullNameCtrl.dispose();
    _phoneCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  void _applyPreset(PermPreset p) {
    setState(() => _perms = Map<String, bool>.from(p.permissions));
    showSheetSnack(context, 'تم تطبيق ${p.label}', isError: false);
  }

  void _setAll(bool v) {
    setState(() {
      for (final k in _perms.keys) {
        _perms[k] = v;
      }
    });
  }

  /// يعرض الخطأ في الـbanner أعلى الـsheet ويرجع الـadmin للـtab
  /// المعلوم للحقل المتأثّر.
  void _showError(String msg, {int tabIndex = 0}) {
    setState(() => _error = msg);
    if (_tab.index != tabIndex) _tab.animateTo(tabIndex);
  }

  Future<void> _save() async {
    final username = _userCtrl.text.trim();
    if (username.isEmpty) {
      _showError('اسم المستخدم مطلوب');
      return;
    }
    if (!_isEdit && _passCtrl.text.length < 4) {
      _showError('كلمة المرور ٤ أحرف على الأقل');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    // مطلب 2026-06-11: الـrecords في Dart لا تُكسر cast عبر dynamic،
    // فنحلّ كل فرع بنفسه ونستخرج ok/message محلياً.
    bool ok;
    String? message;
    if (_isEdit) {
      final r = await EmployeesApi.update(
        id: widget.employee!.id,
        fullName: _fullNameCtrl.text.trim(),
        phone: _phoneCtrl.text.trim(),
        password: _passCtrl.text.isEmpty ? null : _passCtrl.text,
        isActive: _isActive,
        permissions: _perms,
      );
      ok = r.ok;
      message = r.message;
    } else {
      final r = await EmployeesApi.create(
        username: username,
        password: _passCtrl.text,
        fullName: _fullNameCtrl.text.trim().isEmpty
            ? null
            : _fullNameCtrl.text.trim(),
        phone: _phoneCtrl.text.trim().isEmpty
            ? null
            : _phoneCtrl.text.trim(),
        isActive: _isActive,
        permissions: _perms,
      );
      ok = r.ok;
      message = r.message;
    }
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) {
      _snack(_isEdit ? 'تم حفظ التعديلات' : 'تم إنشاء الموظف');
      Navigator.of(context).pop(true);
    } else {
      _showError(message ?? 'فشل الحفظ');
    }
  }

  void _snack(String msg, {bool warn = false}) {
    // 2026-08-25 (bug fix): كان isError مُثبَّت true دائماً حتى للنجاح
    // ("تم حفظ التعديلات" كان يظهر بأحمر). الآن يحترم warn.
    showSheetSnack(context, msg, isError: warn);
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final activeCount = _perms.values.where((v) => v).length;
    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, controller) {
        return Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius:
                BorderRadius.vertical(top: Radius.circular(R.xl)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 8),
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Padding(
                padding:
                    const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, 0),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: const Color(0xFF8B5CF6)
                            .withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(R.md),
                      ),
                      child: Icon(
                        _isEdit ? LucideIcons.userCog : LucideIcons.userPlus,
                        size: 16,
                        color: const Color(0xFF8B5CF6),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _isEdit ? 'تعديل موظف' : 'موظف جديد',
                        style: AppType.title(color: AppColors.textHi)
                            .copyWith(fontSize: 16),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(LucideIcons.x, size: 18),
                      onPressed: _saving
                          ? null
                          : () => Navigator.of(context).pop(false),
                      color: AppColors.textMid,
                    ),
                  ],
                ),
              ),
              TabBar(
                controller: _tab,
                labelColor: const Color(0xFF8B5CF6),
                unselectedLabelColor: AppColors.textMid,
                indicatorColor: const Color(0xFF8B5CF6),
                tabs: [
                  const Tab(text: 'المعلومات'),
                  Tab(text: 'الصلاحيات ($activeCount)'),
                ],
              ),
              // مطلب 2026-06-11: banner أخطاء أعلى الـsheet (ما يطلع
              // snackbar — الـadmin لازم يشوف السبب قبل الإضافة).
              // يختفي تلقائياً مع أول حرف يكتبه أو عند إعادة المحاولة.
              if (_error != null)
                Container(
                  width: double.infinity,
                  margin:
                      const EdgeInsets.fromLTRB(Sp.lg, Sp.sm, Sp.lg, 0),
                  padding: const EdgeInsets.symmetric(
                      horizontal: Sp.md, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(R.md),
                    border: Border.all(
                        color: AppColors.error.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(LucideIcons.circleAlert,
                          size: 14, color: AppColors.error),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _error!,
                          style: TextStyle(
                            color: AppColors.error,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            height: 1.4,
                          ),
                        ),
                      ),
                      InkWell(
                        onTap: () => setState(() => _error = null),
                        borderRadius: BorderRadius.circular(R.pill),
                        child: Padding(
                          padding: const EdgeInsets.all(2),
                          child: Icon(LucideIcons.x,
                              size: 14, color: AppColors.error),
                        ),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: TabBarView(
                  controller: _tab,
                  children: [
                    _infoTab(controller),
                    _permsTab(controller),
                  ],
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding:
                      const EdgeInsets.fromLTRB(Sp.lg, 0, Sp.lg, Sp.sm),
                  child: SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: FilledButton.icon(
                      onPressed: _saving ? null : _save,
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF8B5CF6),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(R.md),
                        ),
                      ),
                      icon: _saving
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(LucideIcons.save, size: 16),
                      label: Text(_saving ? 'جاري الحفظ...' : 'حفظ',
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w800)),
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

  Widget _infoTab(ScrollController controller) {
    return ListView(
      controller: controller,
      padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, Sp.huge),
      children: [
        _field(
          ctrl: _userCtrl,
          hint: _isEdit
              ? _userCtrl.text
              : 'اسم المستخدم — يستعمله الموظف للدخول',
          icon: LucideIcons.atSign,
          enabled: !_isEdit, // username غير قابل للتعديل بعد الإنشاء
        ),
        const SizedBox(height: Sp.md),
        _field(
          ctrl: _passCtrl,
          hint: _isEdit
              ? 'كلمة مرور جديدة (اتركها فارغة لإبقائها)'
              : 'كلمة المرور (4 أحرف على الأقل)',
          icon: LucideIcons.key,
          obscure: true,
        ),
        const SizedBox(height: Sp.md),
        _field(
          ctrl: _fullNameCtrl,
          hint: 'الاسم الكامل',
          icon: LucideIcons.user,
        ),
        const SizedBox(height: Sp.md),
        _field(
          ctrl: _phoneCtrl,
          hint: 'الهاتف',
          icon: LucideIcons.phone,
          keyboard: TextInputType.phone,
          formatters: [FilteringTextInputFormatter.digitsOnly],
        ),
        const SizedBox(height: Sp.md),
        SwitchListTile(
          value: _isActive,
          onChanged: (v) => setState(() => _isActive = v),
          title: Text('الحساب مفعّل',
              style: AppType.label(color: AppColors.textHi)
                  .copyWith(fontWeight: FontWeight.w700)),
          subtitle: Text(
            _isActive
                ? 'يقدر يسجّل دخول وينفّذ الصلاحيات المُمنوحة'
                : 'الموظف لا يقدر يسجّل دخول حالياً',
            style: AppType.muted().copyWith(fontSize: 11),
          ),
          contentPadding: EdgeInsets.zero,
          activeColor: AppColors.brand,
        ),
      ],
    );
  }

  Widget _permsTab(ScrollController controller) {
    final presets = widget.catalog.presets.values.toList();
    final byCat = widget.catalog.permsByCategory;
    final cats = widget.catalog.categories;
    return ListView(
      controller: controller,
      padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, Sp.huge),
      children: [
        // Presets
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(
            'أدوار جاهزة',
            style: AppType.muted(color: AppColors.textMid).copyWith(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
            ),
          ),
        ),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final p in presets)
              _PresetChip(
                preset: p,
                onTap: () => _applyPreset(p),
              ),
            _ActionChip(
              icon: LucideIcons.checkCheck,
              label: 'تفعيل الكل',
              onTap: () => _setAll(true),
              color: AppColors.brand,
            ),
            _ActionChip(
              icon: LucideIcons.eraser,
              label: 'إلغاء الكل',
              onTap: () => _setAll(false),
              color: AppColors.error,
            ),
          ],
        ),
        const SizedBox(height: Sp.lg),
        // الصلاحيات بحسب الفئة
        for (final entry in byCat.entries) ...[
          _categoryHeader(
              cats[entry.key]?.label ?? entry.key, entry.value),
          for (final p in entry.value) _permRow(p),
          const SizedBox(height: Sp.md),
        ],
      ],
    );
  }

  Widget _categoryHeader(String label, List<PermissionDef> perms) {
    final activeInCat = perms
        .where((p) => _perms[p.key] == true)
        .length;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4, top: 4),
      child: Row(
        children: [
          Icon(LucideIcons.folder, size: 12, color: AppColors.textMid),
          const SizedBox(width: 4),
          Text(
            label,
            style: AppType.label(color: AppColors.textHi)
                .copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(width: 6),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: AppColors.surfaceInput,
              borderRadius: BorderRadius.circular(R.pill),
            ),
            child: Text(
              '$activeInCat / ${perms.length}',
              style: AppType.muted(color: AppColors.textMid).copyWith(
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _permRow(PermissionDef p) {
    final value = _perms[p.key] == true;
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(
          horizontal: Sp.md, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.sm),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  p.label,
                  style: AppType.label(color: AppColors.textHi)
                      .copyWith(fontSize: 12.5),
                ),
                Text(
                  p.key,
                  style: TextStyle(
                    color: AppColors.textLow,
                    fontSize: 10,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
          Switch.adaptive(
            value: value,
            onChanged: (v) => setState(() => _perms[p.key] = v),
          ),
        ],
      ),
    );
  }

  Widget _field({
    required TextEditingController ctrl,
    required String hint,
    required IconData icon,
    bool obscure = false,
    bool enabled = true,
    TextInputType? keyboard,
    List<TextInputFormatter>? formatters,
  }) {
    return TextField(
      controller: ctrl,
      obscureText: obscure,
      enabled: enabled,
      keyboardType: keyboard,
      inputFormatters: formatters,
      style: AppType.input(color: AppColors.textHi),
      decoration: InputDecoration(
        // مطلب 2026-06-11: hint فقط، لا label عائم. التصميم أنظف
        // والـplaceholder يختفي تلقائياً لما تكتب.
        hintText: hint,
        hintStyle: AppType.input(color: AppColors.textLow),
        prefixIcon: Icon(icon, size: 16),
        filled: true,
        fillColor: AppColors.surface,
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(R.sm),
          borderSide: BorderSide(
              color: AppColors.border.withValues(alpha: 0.5)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(R.sm),
          borderSide: BorderSide(
              color: AppColors.border.withValues(alpha: 0.5)),
        ),
      ),
    );
  }
}

class _PresetChip extends StatelessWidget {
  const _PresetChip({required this.preset, required this.onTap});
  final PermPreset preset;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Material(
      color: const Color(0xFF8B5CF6).withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(R.sm),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(R.sm),
            border: Border.all(
                color: const Color(0xFF8B5CF6).withValues(alpha: 0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(LucideIcons.sparkles,
                  size: 11, color: Color(0xFF8B5CF6)),
              const SizedBox(width: 4),
              Text(
                preset.label,
                style: const TextStyle(
                  color: Color(0xFF8B5CF6),
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionChip extends StatelessWidget {
  const _ActionChip({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.color,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Material(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(R.sm),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(R.sm),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 11, color: color),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
