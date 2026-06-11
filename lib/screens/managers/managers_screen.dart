import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../api/managers_api.dart';
import '../../core/util/format.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import 'custom_debts_screen.dart';
import 'movements_screen.dart';
import 'sheets/add_manager_sheet.dart';
import 'sheets/balance_op_sheet.dart';
import 'sheets/edit_manager_sheet.dart';
import 'sheets/manager_actions_sheet.dart';
import 'sheets/pay_debt_sheet.dart';
import 'sheets/send_info_sheet.dart';
import '../../services/subscriber_events.dart';

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

  Future<void> _openBalanceOp(Manager m, {BalanceOpKind? preselected}) async {
    final done = await showBalanceOpSheet(context, m, preselected: preselected);
    if (done == true) _load();
  }

  /// مطلب 2026-06-12: نقر الـtile يفتح actions sheet مطابق v1.
  /// 9 عمليات يتعامل معها بحسب القيمة المرجعة.
  Future<void> _openActions(Manager m) async {
    final action = await showManagerActionsSheet(context, m);
    if (action == null || !mounted) return;
    switch (action) {
      case ManagerAction.edit:
        await _openEdit(m);
      case ManagerAction.deposit:
        await _openBalanceOp(m, preselected: BalanceOpKind.deposit);
      case ManagerAction.withdraw:
        await _openBalanceOp(m, preselected: BalanceOpKind.withdraw);
      case ManagerAction.addPoints:
        await _openBalanceOp(m, preselected: BalanceOpKind.addPoints);
      case ManagerAction.payDebt:
        final ok = await showPayDebtSheet(context, m);
        if (ok == true) _load();
      case ManagerAction.otherDebts:
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ManagerCustomDebtsScreen(manager: m),
          ),
        );
        _load();
      case ManagerAction.movements:
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ManagerMovementsScreen(manager: m),
          ),
        );
      case ManagerAction.sendInfo:
        await showSendInfoSheet(context, m);
      case ManagerAction.delete:
        await _confirmDelete(m);
    }
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
    if (result.ok) {
      SubscriberEvents.notifyChange();
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
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
        iconTheme: IconThemeData(color: AppColors.textHi),
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
                        onTap: () => _openActions(m),
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
          Icon(LucideIcons.search,
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
          Icon(LucideIcons.userX,
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
  });
  final Manager manager;
  /// مطلب 2026-06-12: نقر الـtile يفتح actions sheet ضامناً 9 عمليات
  /// مطابقة v1 (تعديل / شحن / سحب / تسديد / نقاط / ديون أخرى / حركات
  /// / إرسال معلومات / حذف). الـtile نفسه ما عاد فيه أزرار.
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final balance = manager.balance ?? 0;
    final debt = manager.debt ?? 0;
    final points = manager.rewardPoints ?? 0;
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
              color: manager.isActive
                  ? AppColors.border
                  : AppColors.error.withValues(alpha: 0.3),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header — avatar + name + username + enabled dot
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Stack(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: const Color(0xFF3B82F6)
                              .withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(R.md),
                        ),
                        alignment: Alignment.center,
                        child: const Icon(LucideIcons.shield,
                            size: 18, color: Color(0xFF3B82F6)),
                      ),
                      Positioned(
                        right: -1,
                        bottom: -1,
                        child: Container(
                          width: 11,
                          height: 11,
                          decoration: BoxDecoration(
                            color: manager.isActive
                                ? AppColors.brand
                                : AppColors.error,
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: AppColors.surface, width: 2),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          manager.username,
                          style: AppType.title(color: AppColors.textHi)
                              .copyWith(fontSize: 14),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (manager.fullName != manager.username) ...[
                          const SizedBox(height: 1),
                          Text(
                            manager.fullName,
                            style: AppType.muted().copyWith(
                                fontSize: 11,
                                fontWeight: FontWeight.w600),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                  Icon(LucideIcons.chevronLeft,
                      size: 16, color: AppColors.textLow),
                ],
              ),
              // Info badges (ACL / phone / company / enabled status)
              if (_hasInfoBadges) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 5,
                  runSpacing: 5,
                  children: [
                    _badge(
                      icon: manager.isActive
                          ? LucideIcons.circleCheck
                          : LucideIcons.circleX,
                      label: manager.isActive ? 'مفعّل' : 'معطّل',
                      color: manager.isActive
                          ? AppColors.brand
                          : AppColors.error,
                    ),
                    if ((manager.aclName ?? '').isNotEmpty)
                      _badge(
                        icon: LucideIcons.shieldCheck,
                        label: manager.aclName!,
                        color: const Color(0xFF3B82F6),
                      ),
                    if ((manager.mobile ?? '').isNotEmpty)
                      _badge(
                        icon: LucideIcons.phone,
                        label: manager.mobile!,
                        color: const Color(0xFF14B8A6),
                      ),
                    if ((manager.company ?? '').isNotEmpty)
                      _badge(
                        icon: LucideIcons.briefcase,
                        label: manager.company!,
                        color: const Color(0xFFE08F2D),
                      ),
                  ],
                ),
              ],
              // Stats chips — رصيد / دين الساس / نقاط / مشتركون
              const SizedBox(height: 8),
              Wrap(
                spacing: 5,
                runSpacing: 5,
                children: [
                  _statChip(
                    icon: LucideIcons.wallet,
                    label: 'رصيد',
                    value: '${formatIQD(balance)} د.ع',
                    color: balance > 0
                        ? AppColors.brand
                        : AppColors.textMid,
                  ),
                  _statChip(
                    icon: LucideIcons.users,
                    label: 'مشتركون',
                    value: '${manager.usersCount ?? 0}',
                    color: const Color(0xFF3B82F6),
                  ),
                  if (points > 0)
                    _statChip(
                      icon: LucideIcons.star,
                      label: 'نقاط',
                      value: '${points.toInt()}',
                      color: const Color(0xFF8B5CF6),
                    ),
                  if (debt > 0)
                    _statChip(
                      icon: LucideIcons.alertTriangle,
                      label: 'دين الساس',
                      value: '${formatIQD(debt)} د.ع',
                      color: const Color(0xFFE08F2D),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool get _hasInfoBadges =>
      (manager.aclName ?? '').isNotEmpty ||
      (manager.mobile ?? '').isNotEmpty ||
      (manager.company ?? '').isNotEmpty;

  Widget _badge({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(R.sm),
        border: Border.all(color: color.withValues(alpha: 0.28)),
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
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _statChip({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(R.sm),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 4),
          Text(
            '$label ',
            style: AppType.muted().copyWith(fontSize: 10.5),
          ),
          Text(
            value,
            style: AppType.label(color: color)
                .copyWith(fontSize: 11.5, fontWeight: FontWeight.w800),
          ),
        ],
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
