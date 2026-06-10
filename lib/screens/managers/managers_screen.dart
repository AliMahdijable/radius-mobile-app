import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../api/managers_api.dart';
import '../../core/util/format.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import 'sheets/add_manager_sheet.dart';
import 'sheets/balance_op_sheet.dart';
import 'sheets/edit_manager_sheet.dart';

/// مديول "المدراء الفرعيون" — قائمة + بحث + add/edit/delete + عمليات
/// رصيد (شحن/سحب/نقاط). v1 web parity.
class ManagersScreen extends StatefulWidget {
  const ManagersScreen({super.key});

  @override
  State<ManagersScreen> createState() => _ManagersScreenState();
}

class _ManagersScreenState extends State<ManagersScreen> {
  List<Manager> _rows = const [];
  int _total = 0;
  bool _loading = true;
  final _searchCtrl = TextEditingController();
  String _query = '';

  /// مطلب 2026-06-12: sort UI مطابق v1 — 5 خيارات + اتجاه.
  _ManagerSort _sort = _ManagerSort.username;
  bool _sortAsc = true;

  @override
  void initState() {
    super.initState();
    _load();
    _searchCtrl.addListener(() {
      final q = _searchCtrl.text.trim();
      if (q == _query) return;
      setState(() => _query = q);
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final r = await ManagersApi.listFull(page: 1, count: 200);
    if (!mounted) return;
    setState(() {
      _rows = r.rows;
      _total = r.total;
      _loading = false;
    });
  }

  List<Manager> get _filtered {
    Iterable<Manager> it = _rows;
    if (_query.isNotEmpty) {
      final q = _query.toLowerCase();
      it = it.where((m) {
        return m.username.toLowerCase().contains(q) ||
            m.fullName.toLowerCase().contains(q) ||
            (m.mobile ?? '').contains(q);
      });
    }
    final list = it.toList();
    int cmp(Manager a, Manager b) {
      switch (_sort) {
        case _ManagerSort.username:
          return a.username.compareTo(b.username);
        case _ManagerSort.firstname:
          return (a.firstname ?? '').compareTo(b.firstname ?? '');
        case _ManagerSort.lastname:
          return (a.lastname ?? '').compareTo(b.lastname ?? '');
        case _ManagerSort.balance:
          return (a.balance ?? 0).compareTo(b.balance ?? 0);
        case _ManagerSort.usersCount:
          return (a.usersCount ?? 0).compareTo(b.usersCount ?? 0);
      }
    }
    list.sort(_sortAsc ? cmp : (a, b) => -cmp(a, b));
    return list;
  }

  num get _totalBalance =>
      _rows.fold<num>(0, (acc, m) => acc + (m.balance ?? 0));

  Future<void> _openAdd() async {
    final added = await showAddManagerSheet(context);
    if (added == true) _load();
  }

  Future<void> _openEdit(Manager m) async {
    final changed = await showEditManagerSheet(context, m);
    if (changed == true) _load();
  }

  Future<void> _openBalanceOp(Manager m) async {
    final done = await showBalanceOpSheet(context, m);
    if (done == true) _load();
  }

  Future<void> _confirmDelete(Manager m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('حذف المدير'),
        content: Text(
          'هل تريد حذف "${m.fullName.isNotEmpty ? m.fullName : m.username}"؟ '
          'لا يمكن التراجع.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            style:
                FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final result = await ManagersApi.delete(m.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result.ok
            ? 'تم الحذف'
            : (result.message ?? 'تعذّر الحذف')),
        backgroundColor:
            result.ok ? AppColors.brand : AppColors.error,
        behavior: SnackBarBehavior.floating,
      ),
    );
    if (result.ok) _load();
  }

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFF3B82F6);
    final filtered = _filtered;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          'المدراء الفرعيون',
          style: AppType.title(color: AppColors.textHi)
              .copyWith(fontSize: 16),
        ),
        iconTheme: const IconThemeData(color: AppColors.textHi),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: accent,
        foregroundColor: Colors.white,
        onPressed: _openAdd,
        icon: const Icon(LucideIcons.userPlus, size: 16),
        label: const Text('مدير جديد'),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          color: accent,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
                Sp.lg, Sp.md, Sp.lg, Sp.huge + Sp.huge),
            children: [
              _hero(accent),
              const SizedBox(height: Sp.md),
              _searchField(),
              const SizedBox(height: Sp.sm),
              _sortBar(accent),
              const SizedBox(height: Sp.md),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (filtered.isEmpty)
                _empty()
              else
                Column(
                  children: [
                    for (final m in filtered) ...[
                      _ManagerTile(
                        manager: m,
                        onTap: () => _openEdit(m),
                        onBalanceOp: () => _openBalanceOp(m),
                        onDelete: () => _confirmDelete(m),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _hero(Color accent) {
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
            child: Icon(LucideIcons.userCog, color: accent, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$_total مدير',
                  style: AppType.title(color: AppColors.textHi)
                      .copyWith(fontSize: 20, letterSpacing: -0.4),
                ),
                Text(
                  'إجمالي الرصيد ${formatIQD(_totalBalance)} د.ع',
                  style: AppType.muted().copyWith(fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _searchField() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.pill),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.symmetric(horizontal: Sp.md),
      child: Row(
        children: [
          const Icon(LucideIcons.search,
              color: AppColors.textMid, size: 18),
          const SizedBox(width: Sp.sm),
          Expanded(
            child: TextField(
              controller: _searchCtrl,
              style: AppType.input(color: AppColors.textHi),
              decoration: InputDecoration(
                hintText: 'ابحث بالاسم، اليوزر، أو الهاتف…',
                hintStyle: AppType.input(color: AppColors.textLow),
                border: InputBorder.none,
                isCollapsed: true,
                contentPadding:
                    const EdgeInsets.symmetric(vertical: Sp.md),
              ),
            ),
          ),
          if (_searchCtrl.text.isNotEmpty)
            IconButton(
              icon: const Icon(LucideIcons.x, size: 16),
              color: AppColors.textMid,
              visualDensity: VisualDensity.compact,
              onPressed: () {
                _searchCtrl.clear();
                setState(() => _query = '');
              },
            ),
        ],
      ),
    );
  }

  Widget _sortBar(Color accent) {
    return SizedBox(
      height: 30,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (final s in _ManagerSort.values) ...[
            _sortChip(s, accent),
            const SizedBox(width: 6),
          ],
        ],
      ),
    );
  }

  Widget _sortChip(_ManagerSort s, Color accent) {
    final active = _sort == s;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          setState(() {
            if (_sort == s) {
              _sortAsc = !_sortAsc;
            } else {
              _sort = s;
              _sortAsc = true;
            }
          });
        },
        borderRadius: BorderRadius.circular(R.md),
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: active
                ? accent.withValues(alpha: 0.1)
                : AppColors.surfaceInput,
            borderRadius: BorderRadius.circular(R.md),
            border: Border.all(
                color: active
                    ? accent.withValues(alpha: 0.4)
                    : AppColors.border),
          ),
          child: Row(
            children: [
              Icon(s.icon,
                  size: 12,
                  color: active ? accent : AppColors.textMid),
              const SizedBox(width: 4),
              Text(
                s.label,
                style: TextStyle(
                  color: active ? accent : AppColors.textMid,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (active) ...[
                const SizedBox(width: 3),
                Icon(
                  _sortAsc
                      ? LucideIcons.arrowUp
                      : LucideIcons.arrowDown,
                  size: 10,
                  color: accent,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _empty() {
    return Container(
      padding: const EdgeInsets.all(Sp.huge),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.lg),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          const Icon(LucideIcons.userX,
              size: 36, color: AppColors.textLow),
          const SizedBox(height: 10),
          Text(
            _query.isEmpty
                ? 'لا يوجد مدراء فرعيون بعد'
                : 'لا توجد نتائج لـ "$_query"',
            style: AppType.muted(color: AppColors.textHi)
                .copyWith(fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _ManagerTile extends StatelessWidget {
  const _ManagerTile({
    required this.manager,
    required this.onTap,
    required this.onBalanceOp,
    required this.onDelete,
  });
  final Manager manager;
  final VoidCallback onTap;
  final VoidCallback onBalanceOp;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final balance = manager.balance ?? 0;
    final balanceColor = balance > 0
        ? AppColors.brand
        : balance < 0
            ? AppColors.error
            : AppColors.textMid;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(R.lg),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(R.lg),
            border: Border.all(
              color: manager.enabled
                  ? AppColors.border
                  : AppColors.error.withValues(alpha: 0.3),
            ),
          ),
          child: Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: const Color(0xFF3B82F6)
                          .withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(R.md),
                    ),
                    alignment: Alignment.center,
                    child: const Icon(LucideIcons.userCog,
                        size: 16, color: Color(0xFF3B82F6)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          manager.fullName,
                          style: AppType.title(color: AppColors.textHi)
                              .copyWith(fontSize: 14),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            const Icon(LucideIcons.atSign,
                                size: 10, color: AppColors.textLow),
                            const SizedBox(width: 3),
                            Flexible(
                              child: Text(
                                manager.username,
                                style: AppType.muted().copyWith(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (!manager.enabled) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 5, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.error
                                      .withValues(alpha: 0.1),
                                  borderRadius:
                                      BorderRadius.circular(R.sm),
                                  border: Border.all(
                                      color: AppColors.error
                                          .withValues(alpha: 0.3)),
                                ),
                                child: const Text(
                                  'معطّل',
                                  style: TextStyle(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.error,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _stat(
                      icon: LucideIcons.wallet,
                      label: 'الرصيد',
                      value: '${formatIQD(balance)} د.ع',
                      color: balanceColor,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: _stat(
                      icon: LucideIcons.users,
                      label: 'المشتركون',
                      value: '${manager.usersCount ?? 0}',
                      color: AppColors.textHi,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _action(
                      icon: LucideIcons.banknote,
                      label: 'عملية رصيد',
                      color: const Color(0xFF8B5CF6),
                      onTap: onBalanceOp,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: _action(
                      icon: LucideIcons.trash2,
                      label: 'حذف',
                      color: AppColors.error,
                      onTap: onDelete,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _stat({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(R.sm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 11, color: color),
              const SizedBox(width: 4),
              Text(
                label,
                style: AppType.muted().copyWith(fontSize: 10),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: AppType.label(color: color)
                .copyWith(fontSize: 12, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }

  Widget _action({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(R.sm),
        child: Container(
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(R.sm),
            border: Border.all(color: color.withValues(alpha: 0.28)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
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

/// خيارات الترتيب — مطابق v1 (username, firstname, lastname, balance,
/// users_count).
enum _ManagerSort {
  username('اليوزر', LucideIcons.atSign),
  firstname('الاسم', LucideIcons.user),
  lastname('الكنية', LucideIcons.userCheck),
  balance('الرصيد', LucideIcons.wallet),
  usersCount('المشتركون', LucideIcons.users);

  const _ManagerSort(this.label, this.icon);
  final String label;
  final IconData icon;
}
