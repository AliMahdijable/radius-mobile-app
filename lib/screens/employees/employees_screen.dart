import 'package:flutter/material.dart';
import 'dart:ui' show FontFeature;
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../widgets/reveal_password_sheet.dart';

import '../../api/employees_api.dart';
import '../../core/util/clipboard_helper.dart';
import '../../services/permissions_service.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import 'sheets/employee_editor_sheet.dart';

/// شاشة الموظفين — مديرو الفرع يدخلون عبر حساب رئيسي، والموظفون
/// الفرعيون يحصلون على صلاحيات محددة. القائمة + add/edit/delete.
class EmployeesScreen extends StatefulWidget {
  const EmployeesScreen({super.key});

  @override
  State<EmployeesScreen> createState() => _EmployeesScreenState();
}

class _EmployeesScreenState extends State<EmployeesScreen> {
  List<Employee> _rows = const [];
  PermissionsCatalog? _catalog;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    // الـcatalog مهم للـeditor؛ نحمّله مع القائمة. لو الـcatalog فشل
    // الـeditor ما يفتح (يحتاج presets لرسم الـUI).
    final results = await Future.wait([
      EmployeesApi.list(),
      EmployeesApi.catalog(),
    ]);
    if (!mounted) return;
    final listResult = results[0] as ({List<Employee> rows, String? error});
    final cat = results[1] as PermissionsCatalog?;
    setState(() {
      _rows = listResult.rows;
      _catalog = cat;
      _error = listResult.error ??
          (cat == null ? 'تعذّر تحميل كتالوج الصلاحيات' : null);
      _loading = false;
    });
  }

  Future<void> _openEditor({Employee? employee}) async {
    final cat = _catalog;
    if (cat == null) return;
    final changed = await showEmployeeEditorSheet(
      context,
      catalog: cat,
      employee: employee,
    );
    if (changed == true) _load();
  }

  Future<void> _confirmDelete(Employee emp) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('حذف الموظف',
            style:
                AppType.title(color: AppColors.textHi).copyWith(fontSize: 16)),
        content: Text(
          'حذف "${emp.fullName?.isNotEmpty == true ? emp.fullName : emp.username}"؟ '
          'لا يمكن التراجع.',
          style:
              AppType.subtitle(color: AppColors.textMid).copyWith(height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.errorFill),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final r = await EmployeesApi.delete(emp.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(r.ok ? 'تم حذف الموظف' : (r.message ?? 'تعذّر الحذف')),
        backgroundColor: r.ok ? AppColors.brand : AppColors.error,
        behavior: SnackBarBehavior.floating,
      ),
    );
    if (r.ok) _load();
  }

  /// 2026-08-26: عرض كلمة سرّ الموظّف من `employees.password_encrypted`.
  Future<void> _showEmployeePassword(Employee emp) async {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: const Text('جارٍ الجلب...'),
      duration: const Duration(seconds: 1),
      behavior: SnackBarBehavior.floating,
    ));
    final res = await EmployeesApi.fetchPassword(emp.id);
    if (!mounted) return;
    if (res.password == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(res.message ?? 'تعذّر جلب كلمة السر'),
        backgroundColor: AppColors.errorFill,
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }
    await showRevealPasswordSheet(
      context,
      title: emp.fullName?.isNotEmpty == true ? emp.fullName! : emp.username,
      subtitle: 'كلمة سرّ الموظّف',
      password: res.password!,
      accentColor: AppColors.brandAccent,
    );
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final accent = AppColors.brandAccent;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text('الموظفون',
            style:
                AppType.title(color: AppColors.textHi).copyWith(fontSize: 16)),
        iconTheme: IconThemeData(color: AppColors.textHi),
      ),
      floatingActionButton: (_catalog == null || !Perms.has('employees.manage'))
          ? null
          : FloatingActionButton.extended(
              backgroundColor: accent,
              foregroundColor: AppColors.onBrand,
              onPressed: () => _openEditor(),
              icon: const Icon(LucideIcons.userPlus, size: 16),
              label: const Text('موظف جديد'),
            ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          color: accent,
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? _errorState(_error!)
                  : _rows.isEmpty
                      ? _emptyState()
                      : ListView(
                          padding: EdgeInsets.only(
                              bottom:
                                  MediaQuery.paddingOf(context).bottom + 96),
                          children: [
                            _compactHero(accent),
                            for (final e in _rows)
                              _EmployeeTile(
                                emp: e,
                                onTap: Perms.has('employees.manage')
                                    ? () => _openEditor(employee: e)
                                    : null,
                                onDelete: Perms.has('employees.manage')
                                    ? () => _confirmDelete(e)
                                    : null,
                                onShowPassword: Perms.has('employees.manage')
                                    ? () => _showEmployeePassword(e)
                                    : null,
                              ),
                          ],
                        ),
        ),
      ),
    );
  }

  /// 2026-08-26 redesign: header compact بلا gradient بلا حواف ثقيلة.
  /// سطر واحد ينظم العدد الكلّي + الحالة (مفعّل/معطّل) على اليمين.
  Widget _compactHero(Color accent) {
    final activeCount = _rows.where((e) => e.isActive).length;
    final disabledCount = _rows.length - activeCount;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(
          bottom: BorderSide(color: AppColors.border, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'عدد الموظفين',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textMid,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${_rows.length}',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textHi,
                    letterSpacing: -0.4,
                    height: 1.1,
                  ),
                ),
              ],
            ),
          ),
          _statBadge(
              label: 'مفعّل', count: activeCount, color: AppColors.success),
          if (disabledCount > 0) ...[
            const SizedBox(width: 6),
            _statBadge(
                label: 'معطّل', count: disabledCount, color: AppColors.textLow),
          ],
        ],
      ),
    );
  }

  Widget _statBadge({
    required String label,
    required int count,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(R.sm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$count',
            style: TextStyle(
              fontSize: 12.5, height: 1.4,
              fontWeight: FontWeight.w700,
              color: color,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: AppType.pillBold(color: color),
          ),
        ],
      ),
    );
  }

  Widget _errorState(String msg) {
    return ListView(
      padding: const EdgeInsets.all(Sp.huge),
      children: [
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(LucideIcons.circleAlert, size: 36, color: AppColors.error),
              const SizedBox(height: 10),
              Text(msg,
                  style: AppType.label(color: AppColors.textMid),
                  textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _load,
                icon: const Icon(LucideIcons.refreshCw, size: 14),
                label: const Text('إعادة المحاولة'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _emptyState() {
    return ListView(
      padding: const EdgeInsets.all(Sp.huge),
      children: [
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(LucideIcons.userX, size: 36, color: AppColors.textLow),
              const SizedBox(height: 10),
              Text(
                'لا يوجد موظفون.',
                style: AppType.label(color: AppColors.textMid),
              ),
              const SizedBox(height: 4),
              Text(
                'اضغط "موظف جديد" لإضافة أول موظف.',
                style: AppType.muted().copyWith(fontSize: 12.5),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _EmployeeTile extends StatelessWidget {
  const _EmployeeTile({
    required this.emp,
    required this.onTap,
    this.onDelete,
    this.onShowPassword,
  });
  final Employee emp;

  /// null لو الـactor ما عنده صلاحية التعديل — InkWell يصير inert
  /// (لا ripple، لا فعل) بدل ما يفتح editor فاضي.
  final VoidCallback? onTap;

  /// null لو الـactor ما عنده صلاحية الحذف — يخفي زر الحذف بدل
  /// تعطيله.
  final VoidCallback? onDelete;

  /// 2026-08-26: إظهار كلمة سرّ الموظّف الحاليّة (طلب المستخدم).
  final VoidCallback? onShowPassword;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final display =
        (emp.fullName?.isNotEmpty == true) ? emp.fullName! : emp.username;
    final accentColor = emp.isActive ? AppColors.success : AppColors.textLow;
    return Material(
      color: AppColors.surface,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsetsDirectional.only(
              start: 12, end: 4, top: 10, bottom: 10),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: AppColors.border, width: 0.5),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // 3dp rail — نفس النمط بكارت المشتركين. مفعّل = teal، معطّل = رمادي.
              Container(
                width: 3,
                height: 36,
                decoration: BoxDecoration(
                  color: accentColor,
                  borderRadius: BorderRadius.circular(R.pill),
                ),
              ),
              const SizedBox(width: 12),
              // Small avatar 36dp (بدل 40 السابق)
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(R.card),
                ),
                alignment: Alignment.center,
                child: Text(
                  display.characters.isEmpty ? '?' : display.characters.first,
                  style: AppType.buttonBold(color: accentColor),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            display,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textHi,
                              height: 1.15,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (!emp.isActive) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: AppColors.textLow.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(R.pill),
                            ),
                            child: Text(
                              'معطّل',
                              style: AppType.daysWordBold(color: AppColors.textLow),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Text(
                          emp.username,
                          style: TextStyle(
                            fontSize: 11, height: 1.25,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textMid,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text('  ·  ',
                            style: TextStyle(
                              fontSize: 11, height: 1.35,
                              color: AppColors.textLow,
                            )),
                        Icon(LucideIcons.shield,
                            size: 10, color: AppColors.brand),
                        const SizedBox(width: 3),
                        Text(
                          '${emp.activePermsCount} صلاحية',
                          style: AppType.pillBold(color: AppColors.brand),
                        ),
                      ],
                    ),
                    // 2026-08-26: شارة قيد الـscope — الموظّف مقيَّد بمدير فرعي.
                    if (emp.isScoped) ...[
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Icon(LucideIcons.userCheck,
                              size: 10, color: AppColors.brandAccent),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              'مقيَّد بـ@${emp.scopeAdminUsername ?? emp.scopeAdminId}',
                              style: AppType.microBold(color: AppColors.brandAccent),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              // Actions — flat icon buttons، بلا حواف.
              // 2026-08-26: زر نسخ اليوزر — يتوفّر لأي حساب مصادَق (بلا
              // perm gating لأن الـusername ليس بيانات حسّاسة).
              IconButton(
                icon:
                    Icon(LucideIcons.copy, color: AppColors.textMid, size: 15),
                onPressed: () => copyToClipboard(context, emp.username,
                    label: 'اسم المستخدم'),
                tooltip: 'نسخ اسم المستخدم',
                splashRadius: 18,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
              if (onShowPassword != null)
                IconButton(
                  icon: Icon(LucideIcons.keyRound,
                      color: AppColors.brandAccent, size: 16),
                  onPressed: onShowPassword,
                  tooltip: 'إظهار كلمة السر',
                  splashRadius: 18,
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 32, minHeight: 32),
                ),
              if (onDelete != null)
                IconButton(
                  icon: Icon(LucideIcons.trash2,
                      color: AppColors.error, size: 15),
                  onPressed: onDelete,
                  tooltip: 'حذف',
                  splashRadius: 18,
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 32, minHeight: 32),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @Deprecated('unused — old badge helper')
  // ignore: unused_element
  Widget _badge({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return const SizedBox.shrink();
  }
}
