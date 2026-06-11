import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../api/employees_api.dart';
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
    final listResult =
        results[0] as ({List<Employee> rows, String? error});
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
            style: AppType.title(color: AppColors.textHi)
                .copyWith(fontSize: 16)),
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
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
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
        content: Text(r.ok
            ? 'تم حذف الموظف'
            : (r.message ?? 'تعذّر الحذف')),
        backgroundColor: r.ok ? AppColors.brand : AppColors.error,
        behavior: SnackBarBehavior.floating,
      ),
    );
    if (r.ok) _load();
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    const accent = Color(0xFF8B5CF6);
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text('الموظفون',
            style: AppType.title(color: AppColors.textHi)
                .copyWith(fontSize: 16)),
        iconTheme: IconThemeData(color: AppColors.textHi),
      ),
      floatingActionButton: (_catalog == null ||
              !Perms.has('employees.manage'))
          ? null
          : FloatingActionButton.extended(
              backgroundColor: accent,
              foregroundColor: Colors.white,
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
                          padding: const EdgeInsets.fromLTRB(
                              Sp.lg, Sp.md, Sp.lg, Sp.huge + Sp.huge),
                          children: [
                            _hero(accent),
                            const SizedBox(height: Sp.md),
                            for (final e in _rows) ...[
                              _EmployeeTile(
                                emp: e,
                                onTap: Perms.has('employees.manage')
                                    ? () => _openEditor(employee: e)
                                    : () {/* read-only */},
                                onDelete: Perms.has('employees.manage')
                                    ? () => _confirmDelete(e)
                                    : null,
                              ),
                              const SizedBox(height: 8),
                            ],
                          ],
                        ),
        ),
      ),
    );
  }

  Widget _hero(Color accent) {
    final activeCount = _rows.where((e) => e.isActive).length;
    return Container(
      padding: const EdgeInsets.all(Sp.md),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            accent.withValues(alpha: 0.18),
            accent.withValues(alpha: 0.05),
          ],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: BorderRadius.circular(R.lg),
        border: Border.all(color: accent.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(R.md),
            ),
            child: Icon(LucideIcons.users, color: accent, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_rows.length} موظف',
                  style: AppType.title(color: AppColors.textHi)
                      .copyWith(fontSize: 17, letterSpacing: -0.3),
                ),
                Text(
                  '$activeCount مفعّل · ${_rows.length - activeCount} معطّل',
                  style: AppType.muted().copyWith(fontSize: 11),
                ),
              ],
            ),
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
              Icon(LucideIcons.circleAlert,
                  size: 36, color: AppColors.error),
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
                style: AppType.muted().copyWith(fontSize: 12),
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
  });
  final Employee emp;
  final VoidCallback onTap;
  /// null لو الـactor ما عنده صلاحية الحذف — يخفي زر الحذف بدل
  /// تعطيله.
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final display = (emp.fullName?.isNotEmpty == true)
        ? emp.fullName!
        : emp.username;
    final color = emp.isActive
        ? const Color(0xFF14B8A6)
        : AppColors.textLow;
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(R.md),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: Sp.md, vertical: Sp.md),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(R.md),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(R.md),
                ),
                alignment: Alignment.center,
                child: Text(
                  display.characters.isEmpty ? '?' : display.characters.first,
                  style: AppType.title(color: color).copyWith(fontSize: 18),
                ),
              ),
              const SizedBox(width: Sp.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      display,
                      style: AppType.label(color: AppColors.textHi)
                          .copyWith(fontWeight: FontWeight.w800),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      emp.username,
                      style: AppType.muted(color: AppColors.textMid)
                          .copyWith(fontSize: 11),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        _badge(
                          icon: emp.isActive
                              ? LucideIcons.circleCheck
                              : LucideIcons.circleX,
                          label: emp.isActive ? 'مفعّل' : 'معطّل',
                          color: color,
                        ),
                        const SizedBox(width: 6),
                        _badge(
                          icon: LucideIcons.shield,
                          label: '${emp.activePermsCount} صلاحية',
                          color: AppColors.brand,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (onDelete != null)
                IconButton(
                  icon: Icon(LucideIcons.trash2,
                      color: AppColors.error, size: 16),
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

  Widget _badge({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(R.sm),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: color),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
