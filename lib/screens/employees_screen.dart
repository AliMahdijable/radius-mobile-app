import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../widgets/app_snackbar.dart';

import '../core/network/dio_client.dart';
import '../core/theme/app_theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// EmployeesScreen — قائمة موظفي المدير الحالي + add/edit/delete.
// الصفحة تستهلك:
//   GET    /api/v2/employees                 → القائمة
//   GET    /api/v2/employees/permissions-catalog → كتالوج الـ40 صلاحية + presets
//   POST   /api/v2/employees                 → إنشاء
//   PUT    /api/v2/employees/:id             → تعديل (info / perms / كلمة مرور)
//   DELETE /api/v2/employees/:id             → حذف
// الـUI Mobile-first: كرت لكل موظف، FAB للإضافة، Sheet للتحرير.
// ─────────────────────────────────────────────────────────────────────────────

class EmployeesScreen extends ConsumerStatefulWidget {
  const EmployeesScreen({super.key});

  @override
  ConsumerState<EmployeesScreen> createState() => _EmployeesScreenState();
}

class _EmployeesScreenState extends ConsumerState<EmployeesScreen> {
  List<_Employee> _employees = [];
  _PermsCatalog? _catalog;
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
    try {
      final dio = ref.read(backendDioProvider);
      final results = await Future.wait([
        dio.get('/api/v2/employees'),
        dio.get('/api/v2/employees/permissions-catalog'),
      ]);
      final list = results[0].data['data'] as List? ?? [];
      _employees = list.map((e) => _Employee.fromJson(e)).toList();
      final cat = results[1].data['data'] as Map<String, dynamic>? ?? {};
      _catalog = _PermsCatalog.fromJson(cat);
    } on DioException catch (e) {
      _error = e.response?.data is Map
          ? (e.response?.data['message']?.toString() ?? 'فشل تحميل البيانات')
          : 'فشل تحميل البيانات';
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _delete(_Employee emp) async {
    final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('تأكيد الحذف'),
            content: Text(
              'حذف الموظف "${emp.fullName ?? emp.username}"؟ لا يمكن التراجع.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('إلغاء'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style:
                    ElevatedButton.styleFrom(backgroundColor: AppTheme.dangerColor),
                child: const Text('حذف'),
              ),
            ],
          ),
        ) ??
        false;
    if (!ok) return;
    try {
      final dio = ref.read(backendDioProvider);
      await dio.delete('/api/v2/employees/${emp.id}');
      if (mounted) AppSnackBar.success(context, 'تم حذف الموظف');
      await _load();
    } on DioException catch (e) {
      if (!mounted) return;
      final msg = e.response?.data is Map
          ? (e.response?.data['message']?.toString() ?? 'فشل الحذف')
          : 'فشل الحذف';
      AppSnackBar.error(context, msg);
    }
  }

  void _openEditor({_Employee? employee}) {
    if (_catalog == null) return;
    showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _EmployeeEditor(
        catalog: _catalog!,
        existing: employee,
      ),
    ).then((saved) {
      if (saved == true) _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('الموظفون'),
        actions: [
          IconButton(
            tooltip: 'تحديث',
            icon: const Icon(LucideIcons.refreshCw),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _loading || _catalog == null ? null : () => _openEditor(),
        icon: const Icon(LucideIcons.userPlus),
        label: const Text('موظف جديد'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(LucideIcons.circleAlert,
                            size: 48,
                            color: theme.colorScheme.error.withOpacity(0.6)),
                        const SizedBox(height: 12),
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        ElevatedButton(
                          onPressed: _load,
                          child: const Text('إعادة المحاولة'),
                        ),
                      ],
                    ),
                  ),
                )
              : _employees.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'لا يوجد موظفون.\nاضغط "موظف جديد" للإضافة.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 14),
                        ),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 80),
                        itemCount: _employees.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (_, i) => _EmployeeCard(
                          emp: _employees[i],
                          onTap: () => _openEditor(employee: _employees[i]),
                          onDelete: () => _delete(_employees[i]),
                        ),
                      ),
                    ),
    );
  }
}

class _EmployeeCard extends StatelessWidget {
  final _Employee emp;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  const _EmployeeCard({
    required this.emp,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final activePerms = emp.permissions.values.where((v) => v).length;
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: theme.colorScheme.primary.withOpacity(0.12),
                child: Icon(LucideIcons.user, color: theme.colorScheme.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            emp.fullName?.isNotEmpty == true
                                ? emp.fullName!
                                : emp.username,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (!emp.isActive)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppTheme.dangerColor.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'معطّل',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                                color: AppTheme.dangerColor,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '@${emp.username}',
                      style: TextStyle(
                        fontSize: 11,
                        color: theme.colorScheme.onSurface.withOpacity(0.6),
                        fontFamily: 'monospace',
                      ),
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: [
                        _Chip(
                          icon: LucideIcons.shieldCheck,
                          text: '$activePerms صلاحية',
                          color: theme.colorScheme.primary,
                        ),
                        if (emp.phone?.isNotEmpty == true)
                          _Chip(
                            icon: LucideIcons.phone,
                            text: emp.phone!,
                            color: Colors.grey,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(LucideIcons.trash2, size: 20),
                color: AppTheme.dangerColor,
                onPressed: onDelete,
                tooltip: 'حذف',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;
  const _Chip({required this.icon, required this.text, required this.color});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 3),
          Text(
            text,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _EmployeeEditor — bottom sheet لإنشاء/تعديل موظف.
// تبويبان: المعلومات (username/full_name/phone/is_active/password) +
// الصلاحيات (40 toggle مجمّعة بـ10 categories، مع 3 presets).
// ─────────────────────────────────────────────────────────────────────────────
class _EmployeeEditor extends ConsumerStatefulWidget {
  final _PermsCatalog catalog;
  final _Employee? existing;
  const _EmployeeEditor({required this.catalog, this.existing});

  @override
  ConsumerState<_EmployeeEditor> createState() => _EmployeeEditorState();
}

class _EmployeeEditorState extends ConsumerState<_EmployeeEditor>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;
  late final TextEditingController _userCtrl;
  late final TextEditingController _fullNameCtrl;
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _passCtrl;
  late bool _isActive;
  late Map<String, bool> _perms;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    final e = widget.existing;
    _userCtrl = TextEditingController(text: e?.username ?? '');
    _fullNameCtrl = TextEditingController(text: e?.fullName ?? '');
    _phoneCtrl = TextEditingController(text: e?.phone ?? '');
    _passCtrl = TextEditingController();
    _isActive = e?.isActive ?? true;
    _perms = {
      ...widget.catalog.defaults,
      if (e != null) ...e.permissions,
    };
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _userCtrl.dispose();
    _fullNameCtrl.dispose();
    _phoneCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  void _applyPreset(String key) {
    final preset = widget.catalog.presets[key];
    if (preset == null) return;
    setState(() {
      _perms = Map<String, bool>.from(preset.permissions);
    });
    AppSnackBar.info(context, 'تم تطبيق ${preset.label}');
  }

  Future<void> _save() async {
    if (_userCtrl.text.trim().isEmpty) {
      AppSnackBar.warning(context, 'اسم المستخدم مطلوب');
      return;
    }
    if (widget.existing == null && _passCtrl.text.length < 4) {
      AppSnackBar.warning(context, 'كلمة مرور ٤ أحرف على الأقل');
      return;
    }
    setState(() => _saving = true);
    try {
      final dio = ref.read(backendDioProvider);
      final body = <String, dynamic>{
        'username': _userCtrl.text.trim(),
        'full_name': _fullNameCtrl.text.trim(),
        'phone': _phoneCtrl.text.trim(),
        'is_active': _isActive,
        'permissions': _perms,
      };
      if (_passCtrl.text.isNotEmpty) {
        body['password'] = _passCtrl.text;
      }
      if (widget.existing == null) {
        await dio.post('/api/v2/employees', data: body);
        if (mounted) AppSnackBar.success(context, 'تم إنشاء الموظف');
      } else {
        await dio.put('/api/v2/employees/${widget.existing!.id}', data: body);
        if (mounted) AppSnackBar.success(context, 'تم حفظ التعديلات');
      }
      if (mounted) Navigator.of(context).pop(true);
    } on DioException catch (e) {
      final msg = e.response?.data is Map
          ? (e.response?.data['message']?.toString() ?? 'فشل الحفظ')
          : 'فشل الحفظ';
      if (mounted) AppSnackBar.error(context, msg);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final activeCount = _perms.values.where((v) => v).length;
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      expand: false,
      builder: (_, controller) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: Colors.grey.shade400,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                children: [
                  Text(
                    widget.existing == null ? 'موظف جديد' : 'تعديل موظف',
                    style: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.w700),
                  ),
                  const Spacer(),
                  if (_saving) const SizedBox(
                    width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ],
              ),
            ),
            TabBar(
              controller: _tabCtrl,
              tabs: [
                const Tab(text: 'المعلومات'),
                Tab(text: 'الصلاحيات ($activeCount)'),
              ],
              labelColor: theme.colorScheme.primary,
              indicatorColor: theme.colorScheme.primary,
            ),
            Expanded(
              child: TabBarView(
                controller: _tabCtrl,
                children: [
                  _buildInfoTab(controller),
                  _buildPermsTab(controller, theme),
                ],
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _saving
                            ? null
                            : () => Navigator.of(context).pop(false),
                        child: const Text('إلغاء'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton.icon(
                        onPressed: _saving ? null : _save,
                        icon: const Icon(LucideIcons.save),
                        label: Text(_saving ? 'جاري الحفظ...' : 'حفظ'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoTab(ScrollController controller) {
    return ListView(
      controller: controller,
      padding: const EdgeInsets.all(16),
      children: [
        TextField(
          controller: _userCtrl,
          enabled: widget.existing == null, // username غير قابل للتعديل
          decoration: const InputDecoration(
            labelText: 'اسم المستخدم *',
            prefixIcon: Icon(LucideIcons.user),
            helperText: 'يستعمله الموظف لتسجيل الدخول',
          ),
          textDirection: TextDirection.ltr,
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _fullNameCtrl,
          decoration: const InputDecoration(
            labelText: 'الاسم العربي',
            prefixIcon: Icon(LucideIcons.badgeCheck),
            helperText: 'يظهر بالتقارير ووصل الطباعة',
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _phoneCtrl,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(
            labelText: 'الهاتف',
            prefixIcon: Icon(LucideIcons.phone),
          ),
          textDirection: TextDirection.ltr,
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _passCtrl,
          obscureText: true,
          decoration: InputDecoration(
            labelText: widget.existing == null
                ? 'كلمة المرور *'
                : 'كلمة مرور جديدة (اختياري)',
            prefixIcon: const Icon(LucideIcons.lock),
            helperText: widget.existing == null
                ? 'الموظف يستعملها مع اسم المستخدم'
                : 'اتركه فارغاً إذا لا تريد تغييرها',
          ),
        ),
        const SizedBox(height: 12),
        SwitchListTile(
          value: _isActive,
          onChanged: (v) => setState(() => _isActive = v),
          title: const Text('الحساب نشط'),
          subtitle: Text(
            _isActive
                ? 'الموظف يقدر يسجّل دخول'
                : 'تسجيل الدخول معطّل (لا يحذف البيانات)',
            style: const TextStyle(fontSize: 11),
          ),
        ),
      ],
    );
  }

  Widget _buildPermsTab(ScrollController controller, ThemeData theme) {
    return ListView(
      controller: controller,
      padding: const EdgeInsets.all(12),
      children: [
        // Presets
        Text(
          'قوالب جاهزة',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: theme.colorScheme.onSurface.withOpacity(0.6),
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: widget.catalog.presets.entries.map((e) {
            return ActionChip(
              avatar: const Icon(LucideIcons.zap, size: 14),
              label: Text(e.value.label),
              onPressed: () => _applyPreset(e.key),
            );
          }).toList()
            ..add(ActionChip(
              avatar: const Icon(LucideIcons.refreshCw, size: 14),
              label: const Text('استعادة الافتراضي'),
              onPressed: () => setState(() {
                _perms = Map<String, bool>.from(widget.catalog.defaults);
              }),
            )),
        ),
        const SizedBox(height: 16),
        // Categories
        ...widget.catalog.categories.entries.map((cat) {
          final perms = widget.catalog.permsByCategory[cat.key] ?? [];
          if (perms.isEmpty) return const SizedBox.shrink();
          final activeInCat = perms.where((p) => _perms[p.key] == true).length;
          return Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          cat.value.label,
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w800),
                        ),
                      ),
                      Text(
                        '$activeInCat/${perms.length}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(LucideIcons.checkCheck, size: 18),
                        tooltip: 'الكل',
                        onPressed: () => setState(() {
                          for (final p in perms) {
                            _perms[p.key] = activeInCat < perms.length;
                          }
                        }),
                      ),
                    ],
                  ),
                  const Divider(height: 8),
                  ...perms.map((p) => SwitchListTile.adaptive(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        value: _perms[p.key] ?? false,
                        onChanged: (v) =>
                            setState(() => _perms[p.key] = v),
                        title: Text(p.label,
                            style: const TextStyle(fontSize: 13)),
                      )),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Models
// ─────────────────────────────────────────────────────────────────────────────
class _Employee {
  final int id;
  final String username;
  final String? fullName;
  final String? phone;
  final bool isActive;
  final Map<String, bool> permissions;
  const _Employee({
    required this.id,
    required this.username,
    this.fullName,
    this.phone,
    required this.isActive,
    required this.permissions,
  });
  factory _Employee.fromJson(Map j) {
    final raw = j['permissions'];
    final m = <String, bool>{};
    if (raw is Map) {
      raw.forEach((k, v) => m[k.toString()] = v == true);
    }
    return _Employee(
      id: int.tryParse(j['id']?.toString() ?? '') ?? 0,
      username: j['username']?.toString() ?? '',
      fullName: j['full_name']?.toString(),
      phone: j['phone']?.toString(),
      isActive: j['is_active'] == true || j['is_active'] == 1,
      permissions: m,
    );
  }
}

class _PermDef {
  final String key;
  final String label;
  final String category;
  const _PermDef(this.key, this.label, this.category);
}

class _Category {
  final String key;
  final String label;
  const _Category(this.key, this.label);
}

class _Preset {
  final String key;
  final String label;
  final Map<String, bool> permissions;
  const _Preset(this.key, this.label, this.permissions);
}

class _PermsCatalog {
  /// كل الـ40 صلاحية: key → meta
  final Map<String, _PermDef> permissions;
  /// 10 categories: key → meta
  final Map<String, _Category> categories;
  /// permissions منظّمة بكل category (لتسهيل الـrender)
  final Map<String, List<_PermDef>> permsByCategory;
  /// قيم افتراضية لموظف جديد
  final Map<String, bool> defaults;
  /// presets: cashier / assistant_manager / viewer
  final Map<String, _Preset> presets;

  _PermsCatalog({
    required this.permissions,
    required this.categories,
    required this.permsByCategory,
    required this.defaults,
    required this.presets,
  });

  factory _PermsCatalog.fromJson(Map j) {
    final permsRaw = j['permissions'] as Map? ?? {};
    final perms = <String, _PermDef>{};
    permsRaw.forEach((k, v) {
      if (v is Map) {
        perms[k.toString()] = _PermDef(
          k.toString(),
          v['label']?.toString() ?? k.toString(),
          v['category']?.toString() ?? 'other',
        );
      }
    });
    final catsRaw = j['categories'] as Map? ?? {};
    final cats = <String, _Category>{};
    catsRaw.forEach((k, v) {
      if (v is Map) {
        cats[k.toString()] =
            _Category(k.toString(), v['label']?.toString() ?? k.toString());
      }
    });
    final byCat = <String, List<_PermDef>>{};
    for (final p in perms.values) {
      byCat.putIfAbsent(p.category, () => []).add(p);
    }
    final defaultsRaw = j['defaults'] as Map? ?? {};
    final defaults = <String, bool>{};
    defaultsRaw.forEach((k, v) => defaults[k.toString()] = v == true);
    final presetsRaw = j['presets'] as Map? ?? {};
    final presets = <String, _Preset>{};
    presetsRaw.forEach((k, v) {
      if (v is Map) {
        final p = <String, bool>{};
        (v['permissions'] as Map?)
            ?.forEach((pk, pv) => p[pk.toString()] = pv == true);
        presets[k.toString()] = _Preset(
          k.toString(),
          v['label']?.toString() ?? k.toString(),
          p,
        );
      }
    });
    return _PermsCatalog(
      permissions: perms,
      categories: cats,
      permsByCategory: byCat,
      defaults: defaults,
      presets: presets,
    );
  }
}
