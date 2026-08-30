import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../widgets/reveal_password_sheet.dart';

import '../../api/manager_debts_api.dart';
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
import '../../core/util/clipboard_helper.dart';
import '../../services/permissions_service.dart';
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

  /// مطلب 2026-06-11 (مطابق v1 managers_screen.dart:1167): الديون
  /// الخارجية تنضمّ إلى دين الـSAS عند عرضها في الكارت. الـmap يُملأ
  /// من /api/admin/manager-debts/summary ويُستهلَك في chip الدين +
  /// يُمرَّر للـactions sheet + pay-debt sheet.
  Map<int, double> _customDebtByManager = const {};

  @override
  void initState() {
    super.initState();
    _load();
    _searchCtrl.addListener(() {
      final q = _searchCtrl.text.trim();
      if (q == _query) return;
      setState(() => _query = q);
    });
    // أعد التحميل تلقائياً لمّا أيّ شاشة ثانية تُغيّر بيانات (إضافة
    // مدير، تسديد دين، شحن، إلخ.) — مطابق سلوك شاشة المشتركين.
    SubscriberEvents.dataChanged.addListener(_onExternalChange);
  }

  void _onExternalChange() {
    if (!mounted) return;
    _load();
  }

  @override
  void dispose() {
    SubscriberEvents.dataChanged.removeListener(_onExternalChange);
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    // اجلب القائمة + ملخّص الديون الخارجية بالتوازي. أيّاً منهما لو فشل
    // تُكمل الأخرى بشكل طبيعي.
    final results = await Future.wait([
      ManagersApi.listFull(page: 1, count: 200),
      ManagerDebtsApi.summary(),
    ]);
    if (!mounted) return;
    final list = results[0] as ({List<Manager> rows, int total});
    final summary = results[1] as ManagerDebtsSummary?;
    setState(() {
      _rows = list.rows;
      _total = list.total;
      _customDebtByManager = {
        for (final d in summary?.perDebtor ?? const [])
          d.debtorAdminId: d.totalRemaining,
      };
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
            m.mobile.contains(q);
      });
    }
    final list = it.toList();
    int cmp(Manager a, Manager b) {
      switch (_sort) {
        case _ManagerSort.username:
          return a.username.compareTo(b.username);
        case _ManagerSort.firstname:
          return a.firstname.compareTo(b.firstname);
        case _ManagerSort.lastname:
          return a.lastname.compareTo(b.lastname);
        case _ManagerSort.balance:
          return a.balance.compareTo(b.balance);
        case _ManagerSort.usersCount:
          return a.usersCount.compareTo(b.usersCount);
      }
    }

    list.sort(_sortAsc ? cmp : (a, b) => -cmp(a, b));
    return list;
  }

  num get _totalBalance =>
      _rows.fold<num>(0, (acc, m) => acc + (m.balance));

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
    // 2026-08-26: نمرّر الدين التطبيقي (manager_debts) حتى الـsheet يعرض
    // زر "تسديد دين" حتى للمدراء بلا دين SAS. bug-fix: كان يختفي.
    final action = await showManagerActionsSheet(
      context,
      m,
      customDebt: _customDebtByManager[m.id] ?? 0,
    );
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
        // مرّر مجموع الديون الخارجية الحالي حتى الـsheet يعرض الكلتا
        // فوراً بدون انتظار fetch ثاني.
        final ok = await showPayDebtSheet(
          context,
          m,
          initialCustomRemaining: _customDebtByManager[m.id] ?? 0,
        );
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
      case ManagerAction.showPassword:
        await _showManagerPassword(m);
      case ManagerAction.copyUsername:
        await copyToClipboard(context, m.username, label: 'اسم المدير');
      case ManagerAction.delete:
        await _confirmDelete(m);
    }
  }

  /// 2026-08-26: عرض كلمة سرّ المدير الفرعي.
  /// backend يحضرها من whatsapp_sessions.admin_password_encrypted.
  Future<void> _showManagerPassword(Manager m) async {
    final tid = _snack('جارٍ الجلب...', persistent: true);
    final res = await ManagersApi.fetchPassword(m.id);
    tid?.close();
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
      title: m.username,
      subtitle: 'كلمة سرّ المدير الفرعي',
      password: res.password!,
      accentColor: AppColors.brandAccent,
    );
  }

  ScaffoldFeatureController? _snack(String msg, {bool persistent = false}) {
    if (!mounted) return null;
    return ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      duration:
          persistent ? const Duration(seconds: 10) : const Duration(seconds: 3),
      behavior: SnackBarBehavior.floating,
    ));
  }

  Future<void> _confirmDelete(Manager m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('mgr.delete_title'.tr()),
        content: Text(
          'mgr.delete_body'.tr(namedArgs: {
            'name': m.fullName.isNotEmpty ? m.fullName : m.username
          }),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('common.cancel'.tr()),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.errorFill),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('common.delete'.tr()),
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
            ? 'exp.deleted'.tr()
            : (result.message ?? 'subscribers.delete_failed'.tr())),
        backgroundColor: result.ok ? AppColors.brand : AppColors.error,
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
    final accent = AppColors.brandAccent;
    final filtered = _filtered;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          'mgr.title'.tr(),
          style: AppType.title(color: AppColors.textHi).copyWith(fontSize: 16),
        ),
        iconTheme: IconThemeData(color: AppColors.textHi),
      ),
      floatingActionButton: Perms.has('managers.add')
          ? FloatingActionButton.extended(
              backgroundColor: accent,
              foregroundColor: AppColors.onBrand,
              onPressed: _openAdd,
              icon: const Icon(LucideIcons.userPlus, size: 16),
              label: Text('mgr.new'.tr()),
            )
          : null,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          color: accent,
          child: ListView(
            padding: EdgeInsets.only(
                bottom: MediaQuery.paddingOf(context).bottom + 96),
            children: [
              _compactHero(accent),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                child: _searchField(),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: _sortBar(accent),
              ),
              const SizedBox(height: 4),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (filtered.isEmpty)
                _empty()
              else
                for (final m in filtered)
                  _ManagerTile(
                    manager: m,
                    extraDebt: _customDebtByManager[m.id] ?? 0,
                    onTap: () => _openActions(m),
                  ),
            ],
          ),
        ),
      ),
    );
  }

  /// 2026-08-26 redesign: hero compact بلا gradient. عدد المدراء يسار،
  /// إجمالي الرصيد يمين. صفّ واحد.
  Widget _compactHero(Color accent) {
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
                  'إجمالي الأرصدة',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textMid,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${formatIQD(_totalBalance)} د.ع',
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
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(R.sm),
            ),
            child: Text(
              '$_total مدير',
              style: AppType.bodyBold(color: accent),
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
          Icon(LucideIcons.search, color: AppColors.textMid, size: 18),
          const SizedBox(width: Sp.sm),
          Expanded(
            child: TextField(
              controller: _searchCtrl,
              style: AppType.input(color: AppColors.textHi),
              decoration: InputDecoration(
                hintText: 'mgr.search_hint'.tr(),
                hintStyle: AppType.input(color: AppColors.textLow),
                border: InputBorder.none,
                isCollapsed: true,
                contentPadding: const EdgeInsets.symmetric(vertical: Sp.md),
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
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color:
                active ? accent.withValues(alpha: 0.1) : AppColors.surfaceInput,
            borderRadius: BorderRadius.circular(R.md),
            border: Border.all(
                color:
                    active ? accent.withValues(alpha: 0.4) : AppColors.border),
          ),
          child: Row(
            children: [
              Icon(s.icon,
                  size: 12, color: active ? accent : AppColors.textMid),
              const SizedBox(width: 4),
              Text(
                s.label,
                style: AppType.pillBold(color: active ? accent : AppColors.textMid),
              ),
              if (active) ...[
                const SizedBox(width: 3),
                Icon(
                  _sortAsc ? LucideIcons.arrowUp : LucideIcons.arrowDown,
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
          Icon(LucideIcons.userX, size: 36, color: AppColors.textLow),
          const SizedBox(height: 10),
          Text(
            _query.isEmpty
                ? 'mgr.empty_none'.tr()
                : 'subscribers.no_search_results'.tr(namedArgs: {'q': _query}),
            style:
                AppType.muted(color: AppColors.textHi).copyWith(fontSize: 13),
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
    this.extraDebt = 0,
  });
  final Manager manager;

  /// مطلب 2026-06-12: نقر الـtile يفتح actions sheet ضامناً 9 عمليات
  /// مطابقة v1 (تعديل / شحن / سحب / تسديد / نقاط / ديون أخرى / حركات
  /// / إرسال معلومات / حذف). الـtile نفسه ما عاد فيه أزرار.
  final VoidCallback onTap;

  /// مطلب 2026-06-11: مجموع الديون الخارجية (manager-debts) المستحقّة
  /// على هذا المدير. تُجمع مع `manager.debt` لتعرض chip دين موحّد
  /// يطابق v1 (managers_screen.dart:1179).
  final double extraDebt;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final balance = manager.balance;
    // 2026-07-14: نفصل SAS عن الديون الأخرى في العرض بدل الدمج تحت رقم
    // واحد — يخفي الديون الأخرى في الـchip الموحّد.
    final sasDebt = manager.debt;
    final otherDebt = extraDebt;
    final points = manager.rewardPoints;
    return Material(
      color: AppColors.surface,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsetsDirectional.only(
              start: 12, end: 12, top: 10, bottom: 10),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: AppColors.border, width: 0.5),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header — rail + avatar + name/full + status
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // 3dp status rail — أخضر مفعّل / أحمر معطّل
                  Container(
                    width: 3,
                    height: 36,
                    decoration: BoxDecoration(
                      color:
                          manager.isActive ? AppColors.brand : AppColors.error,
                      borderRadius: BorderRadius.circular(R.pill),
                    ),
                  ),
                  const SizedBox(width: 10),
                  // Avatar 36dp (كان 40 + status dot زخرفي)
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppColors.brandSoftBg,
                      borderRadius: BorderRadius.circular(R.card),
                    ),
                    alignment: Alignment.center,
                    child: Icon(LucideIcons.shield,
                        size: 16, color: AppColors.brandAccent),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                manager.username,
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
                            if (!manager.isActive) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 5, vertical: 1),
                                decoration: BoxDecoration(
                                  color: AppColors.dangerSoftBg,
                                  borderRadius: BorderRadius.circular(R.pill),
                                ),
                                child: Text(
                                  'معطّل',
                                  style: AppType.daysWordBold(color: AppColors.error),
                                ),
                              ),
                            ],
                          ],
                        ),
                        if (manager.fullName != manager.username) ...[
                          const SizedBox(height: 2),
                          Text(
                            manager.fullName,
                            style: TextStyle(
                              fontSize: 11, height: 1.25,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textMid,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
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
                      label: manager.isActive
                          ? 'mgr.active'.tr()
                          : 'subscribers.status_disabled'.tr(),
                      color:
                          manager.isActive ? AppColors.brand : AppColors.error,
                    ),
                    if ((manager.aclName ?? '').isNotEmpty)
                      _badge(
                        icon: LucideIcons.shieldCheck,
                        label: manager.aclName!,
                        color: AppColors.brandAccent,
                      ),
                    if (manager.mobile.isNotEmpty)
                      _badge(
                        icon: LucideIcons.phone,
                        label: manager.mobile,
                        color: AppColors.success,
                      ),
                    if (manager.company.isNotEmpty)
                      _badge(
                        icon: LucideIcons.briefcase,
                        label: manager.company,
                        color: AppColors.warning,
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
                    label: 'dashboard.balance'.tr(),
                    value: '${formatIQD(balance)} د.ع',
                    color: balance > 0 ? AppColors.brand : AppColors.textMid,
                  ),
                  _statChip(
                    icon: LucideIcons.users,
                    label: 'nav.subscribers'.tr(),
                    value: '${manager.usersCount}',
                    color: AppColors.brandAccent,
                  ),
                  if (points > 0)
                    _statChip(
                      icon: LucideIcons.star,
                      label: 'sheets.points'.tr(),
                      value: '${points.toInt()}',
                      color: AppColors.brandAccent,
                    ),
                  if (sasDebt > 0)
                    _statChip(
                      icon: LucideIcons.alertTriangle,
                      label: 'mgr.sas_debt'.tr(),
                      value: '${formatIQD(sasDebt)} د.ع',
                      color: AppColors.warning,
                    ),
                  if (otherDebt > 0)
                    _statChip(
                      icon: LucideIcons.receipt,
                      label: 'mgr.other_debts'.tr(),
                      value: '${formatIQD(otherDebt)} د.ع',
                      color: AppColors.brandAccent,
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
      manager.mobile.isNotEmpty ||
      manager.company.isNotEmpty;

  /// 2026-08-26: badge flat (بلا حدود) — لون خلفيّة خفيف + نصّ ملوّن.
  Widget _badge({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(R.sm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: color),
          const SizedBox(width: 3),
          Text(
            label,
            style: AppType.microBold(color: color),
          ),
        ],
      ),
    );
  }

  /// 2026-08-26: chip إحصاء flat. عرض الأرقام tabular للـalignment.
  Widget _statChip({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(R.sm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 10.5, height: 1.3,
              fontWeight: FontWeight.w600,
              color: color.withValues(alpha: 0.85),
            ),
          ),
          const SizedBox(width: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 11.5, height: 1.35,
              fontWeight: FontWeight.w700,
              color: color,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

/// خيارات الترتيب — مطابق v1 (username, firstname, lastname, balance,
/// users_count).
enum _ManagerSort {
  username('sort.username', LucideIcons.atSign),
  firstname('sort.firstname', LucideIcons.user),
  lastname('mgr.lastname', LucideIcons.userCheck),
  balance('dashboard.balance', LucideIcons.wallet),
  usersCount('nav.subscribers', LucideIcons.users);

  const _ManagerSort(this._key, this.icon);
  final String _key;
  String get label => _key.tr();
  final IconData icon;
}
