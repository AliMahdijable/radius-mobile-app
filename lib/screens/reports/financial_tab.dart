import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' as intl;
import '../../core/theme/app_theme.dart';
import '../../core/utils/helpers.dart';
import '../../core/utils/bottom_sheet_utils.dart';
import '../../core/utils/csv_export.dart';
import '../../providers/reports_provider.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/date_range_picker_row.dart';
import '../../widgets/employee_filter_dropdown.dart';
import '../../widgets/kpi_card.dart';
import '../../widgets/report_controls.dart';

class FinancialTab extends ConsumerStatefulWidget {
  const FinancialTab({super.key});

  @override
  ConsumerState<FinancialTab> createState() => _FinancialTabState();
}

class _FinancialTabState extends ConsumerState<FinancialTab>
    with AutomaticKeepAliveClientMixin {
  late String _dateFrom;
  late String _dateTo;
  bool _loaded = false;
  String _managerId = 'all';
  String _userManagerId = 'all';
  String _employeeId = 'all';
  String _searchQuery = '';
  final Set<String> _selectedActionTypes = {};
  int _logsPage = 1;
  int _logsPerPage = 10;

  static const _actionTypeOptions = [
    {'value': 'BALANCE_DEDUCT', 'label': 'تسديد دين'},
    {'value': 'SUBSCRIBER_ACTIVATE_CASH', 'label': 'تفعيل نقدي'},
    {'value': 'SUBSCRIBER_ACTIVATE_NON_CASH', 'label': 'تفعيل غير نقدي'},
    {'value': 'BALANCE_ADD', 'label': 'إضافة دين'},
    {'value': 'SUBSCRIBER_EXTEND', 'label': 'تمديد اشتراك'},
  ];

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _dateTo = intl.DateFormat('yyyy-MM-dd').format(now);
    _dateFrom =
        intl.DateFormat('yyyy-MM-dd').format(now.subtract(const Duration(days: 30)));
    Future.microtask(() async {
      await ref.read(reportsProvider.notifier).fetchManagers();
      _load();
    });
    ref.listenManual(
      reportsProvider.select((s) => s.refreshEpoch),
      (prev, next) {
        if (prev == null || prev == next) return;
        if (!mounted) return;
        _load();
      },
    );
  }


  Future<void> _load() async {
    await ref.read(reportsProvider.notifier).fetchFinancialReport(
          _dateFrom, _dateTo,
          managerId: _managerId,
          actionTypes: _selectedActionTypes.isNotEmpty ? _selectedActionTypes.toList() : null,
          userManager: _userManagerId != 'all' ? _userManagerId : null,
          employeeId: _employeeId,
        );
    if (mounted) setState(() => _loaded = true);
  }

  double _num(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0;
    return 0;
  }

  Future<void> _exportCsv() async {
    final logs = ref.read(reportsProvider).recentLogs;
    if (logs.isEmpty) {
      AppSnackBar.warning(context, 'لا توجد بيانات للتصدير');
      return;
    }
    try {
      await CsvExport.exportAndShare(
        fileName: 'financial-report-$_dateFrom-$_dateTo.csv',
        headers: ['الاسم', 'اسم المستخدم', 'نوع الحركة', 'المبلغ', 'التاريخ', 'الوصف', 'المدير'],
        rows: logs.map((log) => [
          log['user_firstname']?.toString() ?? '',
          log['user_username']?.toString() ?? log['target_name']?.toString() ?? '',
          log['action_type_ar']?.toString() ?? log['action_type']?.toString() ?? '',
          (log['amount'] ?? 0).toString(),
          log['created_at']?.toString() ?? '',
          log['action_description']?.toString() ?? '',
          log['admin_username']?.toString() ?? '',
        ]).toList(),
      );
    } catch (_) {
      if (mounted) AppSnackBar.error(context, 'فشل تصدير التقرير');
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final state = ref.watch(reportsProvider);
    final theme = Theme.of(context);

    if (state.loading && !_loaded) {
      return const Center(child: CircularProgressIndicator());
    }

    final kpis = state.kpis;
    final collections = _num(kpis['payments_sum']) +
        _num(kpis['debt_pay_sum']) +
        _num(kpis['balance_deduct_sum']) +
        _num(kpis['activate_cash_sum']);
    final debts =
        _num(kpis['balance_add_sum']) + _num(kpis['activate_non_cash_sum']);
    final expenses = _num(kpis['expenses_sum']);
    // Outstanding inter-admin debts. The KPI returned by the server
    // covers ONLY the custom manager_debts ledger; SAS-side debt
    // (manager.debt) lives behind the SAS4 API and isn't visible to
    // the finance controller. Sum it client-side from the manager-tree
    // we already fetch via reportsProvider.fetchManagers so the card
    // matches the per-manager breakdown shown on the managers screen
    // (دين الساس + ديون أخرى).
    final managerDebtsCustom = _num(kpis['manager_debts_outstanding']);
    final sasManagerDebtSum = state.managers.fold<double>(
      0,
      (sum, m) => sum + (m.debt > 0 ? m.debt : 0),
    );
    final managerDebtsOutstanding = managerDebtsCustom + sasManagerDebtSum;
    final netProfit = collections - debts - expenses - managerDebtsOutstanding;
    final activationsTotal =
        _num(kpis['activations_count']) + _num(kpis['extend_count']);

    final rawLogs = state.recentLogs;
    final allLogs = _searchQuery.isEmpty
        ? rawLogs
        : rawLogs.where((log) {
            final q = _searchQuery.toLowerCase();
            final target = (log['user_username'] ?? log['target_name'] ?? '').toString().toLowerCase();
            final name = (log['user_firstname'] ?? '').toString().toLowerCase();
            final desc = (log['action_description'] ?? '').toString().toLowerCase();
            final admin = (log['admin_username'] ?? '').toString().toLowerCase();
            return target.contains(q) || name.contains(q) || desc.contains(q) || admin.contains(q);
          }).toList();
    final logsTotal = allLogs.length;
    final totalLogPages = (logsTotal / _logsPerPage).ceil();
    if (_logsPage > totalLogPages && totalLogPages > 0) _logsPage = totalLogPages;
    final pagedLogs = allLogs.skip((_logsPage - 1) * _logsPerPage).take(_logsPerPage).toList();

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Search bar
          TextField(
            textDirection: TextDirection.ltr,
            textAlign: TextAlign.left,
            onChanged: (v) => setState(() { _searchQuery = v; _logsPage = 1; }),
            decoration: InputDecoration(
              hintText: 'بحث باسم المشترك أو المدير...',
              prefixIcon: const Icon(LucideIcons.search, size: 20),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(LucideIcons.x, size: 18),
                      onPressed: () => setState(() { _searchQuery = ''; _logsPage = 1; }),
                    )
                  : null,
            ),
          ),
          const SizedBox(height: 8),

          // Action bar
          Row(children: [
            Expanded(
              child: GestureDetector(
                onTap: _showDateFilter,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: .3),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(children: [
                    Icon(LucideIcons.calendarRange, size: 14, color: theme.colorScheme.primary),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text('$_dateFrom — $_dateTo',
                          style: const TextStyle(fontSize: 11),
                          overflow: TextOverflow.ellipsis),
                    ),
                    Icon(LucideIcons.slidersHorizontal, size: 14,
                        color: theme.colorScheme.onSurface.withValues(alpha: .4)),
                  ]),
                ),
              ),
            ),
            const SizedBox(width: 6),
            _ActionBtn(LucideIcons.download, 'تصدير', _exportCsv),
            const SizedBox(width: 4),
            _ActionBtn(LucideIcons.refreshCw, 'تحديث', _load),
          ]),
          const SizedBox(height: 8),

          // Active filter chips
          if (_managerId != 'all' || _userManagerId != 'all' || _employeeId != 'all' || _selectedActionTypes.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Wrap(spacing: 6, runSpacing: 4, children: [
                if (_managerId != 'all')
                  _RemovableChip(
                    label: 'مدير: ${state.managers.firstWhere((m) => m.id == _managerId, orElse: () => const ManagerOption(id: '', name: '?')).name}',
                    onRemove: () { setState(() => _managerId = 'all'); _load(); },
                  ),
                if (_userManagerId != 'all')
                  _RemovableChip(
                    label: 'مدير المستخدم: $_userManagerId',
                    onRemove: () { setState(() => _userManagerId = 'all'); _load(); },
                  ),
                if (_employeeId != 'all')
                  _RemovableChip(
                    label: 'موظف محدد',
                    onRemove: () { setState(() => _employeeId = 'all'); _load(); },
                  ),
                ..._selectedActionTypes.map((t) {
                  final lbl = _actionTypeOptions.firstWhere((o) => o['value'] == t, orElse: () => {'label': t})['label']!;
                  return _RemovableChip(
                    label: lbl,
                    onRemove: () { setState(() => _selectedActionTypes.remove(t)); _load(); },
                  );
                }),
              ]),
            ),

          // KPI cards — built dynamically so we only render rows that
          // have meaningful data. Empty categories stay hidden instead
          // of taking grid space with "0 IQD" cards. Net profit is
          // always present as the hero summary.
          _KpiGrid(
            items: [
              if (collections > 0)
                _KpiItem(
                  label: 'إجمالي التحصيلات',
                  value: AppHelpers.formatMoney(collections),
                  icon: LucideIcons.trendingUp,
                  accent: KpiAccent.emerald,
                ),
              if (activationsTotal > 0)
                _KpiItem(
                  label: 'تفعيل + تمديد',
                  value: activationsTotal.toInt().toString(),
                  icon: LucideIcons.circleCheck,
                  accent: KpiAccent.amber,
                ),
              if (debts > 0)
                _KpiItem(
                  label: 'إجمالي الديون',
                  value: AppHelpers.formatMoney(debts),
                  icon: LucideIcons.banknote,
                  accent: KpiAccent.rose,
                ),
              if (expenses > 0)
                _KpiItem(
                  label: 'الصرفيات',
                  value: AppHelpers.formatMoney(expenses),
                  icon: LucideIcons.wallet,
                  accent: KpiAccent.amber,
                ),
              if (managerDebtsOutstanding > 0)
                _KpiItem(
                  label: 'ديون المدراء',
                  value: AppHelpers.formatMoney(managerDebtsOutstanding),
                  icon: LucideIcons.userCheck,
                  accent: KpiAccent.amber,
                ),
            ],
          ),
          const SizedBox(height: 12),
          // Net profit hero — يظهر دائماً حتى لو 0 لأنه الرقم الأهم
          // اللي المدير يفتح الشاشة عشانه. tinted blue يميّزه عن
          // الـtiles فوقه بدون ما يصير صارخ.
          KpiCard(
            label: 'صافي الربح',
            value: AppHelpers.formatMoney(netProfit),
            icon: LucideIcons.piggyBank,
            accent: KpiAccent.blue,
            hero: true,
          ),
          const SizedBox(height: 20),

          // Per-admin table
          if (state.perAdmin.isNotEmpty) ...[
            Text('تقرير حسب المدير',
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            ...state.perAdmin.map((admin) => _AdminRow(admin: admin)),
            const SizedBox(height: 20),
          ],

          // Recent logs with pagination
          if (allLogs.isNotEmpty) ...[
            Text('آخر العمليات',
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            PaginationBar(
              totalItems: logsTotal,
              currentPage: _logsPage,
              rowsPerPage: _logsPerPage,
              itemLabel: 'عملية',
              onPageChanged: (p) => setState(() => _logsPage = p),
              onRowsPerPageChanged: (r) => setState(() {
                _logsPerPage = r;
                _logsPage = 1;
              }),
            ),
            const SizedBox(height: 4),
            ...pagedLogs.map((log) => _LogRow(log: log)),
          ],
        ],
      ),
    );
  }

  void _showDateFilter() {
    final managers = ref.read(reportsProvider).managers;
    showModalBottomSheet(
      useSafeArea: true,
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        String from = _dateFrom;
        String to = _dateTo;
        String mgr = _managerId;
        String userMgr = _userManagerId;
        String emp = _employeeId;
        final types = Set<String>.from(_selectedActionTypes);
        return StatefulBuilder(builder: (ctx, setSheet) {
          return SafeArea(
            child: Padding(
              padding: bottomSheetContentPadding(
                ctx,
                horizontal: 20,
                top: 20,
                extraBottom: 16,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(child: Container(width: 40, height: 4,
                      decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
                  const SizedBox(height: 16),
                  Text('الفلاتر', style: Theme.of(ctx).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 14),

                  _SectionLabel('فترة سريعة'),
                  const SizedBox(height: 6),
                  Wrap(spacing: 8, children: [
                    _qc('اليوم', () { final t = intl.DateFormat('yyyy-MM-dd').format(DateTime.now()); setSheet(() { from = t; to = t; }); }),
                    _qc('آخر 7 أيام', () { final n = DateTime.now(); setSheet(() { to = intl.DateFormat('yyyy-MM-dd').format(n); from = intl.DateFormat('yyyy-MM-dd').format(n.subtract(const Duration(days: 7))); }); }),
                    _qc('آخر 30 يوم', () { final n = DateTime.now(); setSheet(() { to = intl.DateFormat('yyyy-MM-dd').format(n); from = intl.DateFormat('yyyy-MM-dd').format(n.subtract(const Duration(days: 30))); }); }),
                    _qc('3 أشهر', () { final n = DateTime.now(); setSheet(() { to = intl.DateFormat('yyyy-MM-dd').format(n); from = intl.DateFormat('yyyy-MM-dd').format(n.subtract(const Duration(days: 90))); }); }),
                  ]),
                  const SizedBox(height: 10),
                  DateRangePickerRow(
                    fromDate: from,
                    toDate: to,
                    onFromChanged: (v) => setSheet(() => from = v),
                    onToChanged: (v) => setSheet(() => to = v),
                  ),
                  const SizedBox(height: 14),

                  _SectionLabel('نوع الحركة'),
                  const SizedBox(height: 6),
                  Wrap(spacing: 6, runSpacing: 6, children: _actionTypeOptions.map((opt) {
                    final v = opt['value']!;
                    final active = types.contains(v);
                    return FilterChip(
                      label: Text(opt['label']!, style: const TextStyle(fontSize: 11)),
                      selected: active,
                      onSelected: (sel) => setSheet(() { sel ? types.add(v) : types.remove(v); }),
                      selectedColor: AppTheme.primary.withValues(alpha: .15),
                      checkmarkColor: AppTheme.primary,
                      visualDensity: VisualDensity.compact,
                    );
                  }).toList()),
                  const SizedBox(height: 14),

                  if (managers.isNotEmpty) ...[
                    _SectionLabel('مدير الحركة'),
                    const SizedBox(height: 6),
                    _FilterDropdown(
                      value: mgr,
                      items: [
                        const DropdownMenuItem(value: 'all', child: Text('الكل (المدير + الفرعيين)')),
                        ...managers.map((m) => DropdownMenuItem(value: m.id, child: Text(m.name, overflow: TextOverflow.ellipsis))),
                      ],
                      onChanged: (v) => setSheet(() => mgr = v),
                    ),
                    const SizedBox(height: 10),
                    _SectionLabel('مدير المستخدم'),
                    const SizedBox(height: 6),
                    _FilterDropdown(
                      value: userMgr,
                      items: [
                        const DropdownMenuItem(value: 'all', child: Text('الكل')),
                        ...managers.map((m) => DropdownMenuItem(value: m.name, child: Text(m.name, overflow: TextOverflow.ellipsis))),
                      ],
                      onChanged: (v) => setSheet(() => userMgr = v),
                    ),
                    const SizedBox(height: 14),
                  ],

                  EmployeeFilterDropdown(
                    value: emp,
                    padding: EdgeInsets.zero,
                    onChanged: (v) => setSheet(() => emp = v),
                  ),
                  const SizedBox(height: 14),

                  SizedBox(height: AppTheme.actionButtonHeight, child: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      setState(() {
                        _dateFrom = from;
                        _dateTo = to;
                        _managerId = mgr;
                        _userManagerId = userMgr;
                        _employeeId = emp;
                        _selectedActionTypes..clear()..addAll(types);
                        _logsPage = 1;
                      });
                      _load();
                    },
                    child: const Text('تطبيق'),
                  )),
                ],
              ),
            ),
          );
        });
      },
    );
  }

  Widget _qc(String label, VoidCallback onTap) =>
      ActionChip(label: Text(label, style: const TextStyle(fontSize: 11)), onPressed: onTap, visualDensity: VisualDensity.compact);
}

/// Plain data for a KPI card — no widgets. Kept as a tiny value type so
/// the grid builder can conditionally skip empty categories without
/// managing widget lifecycle.
class _KpiItem {
  final String label;
  final String value;
  final IconData icon;
  final KpiAccent accent;
  const _KpiItem({
    required this.label,
    required this.value,
    required this.icon,
    required this.accent,
  });
}

/// Responsive grid of KPI tiles.
///
/// We drop any card whose category has no data (amount == 0, count == 0)
/// so the admin doesn't see a wall of "0 IQD" boxes. Remaining tiles
/// flow into a 2-column grid on phones, widening to 3 columns on
/// tablets (> 600 px) via LayoutBuilder. Tile heights are fixed via
/// a `childAspectRatio` so the grid stays uniform regardless of whether
/// a row ends up odd.
class _KpiGrid extends StatelessWidget {
  final List<_KpiItem> items;
  const _KpiGrid({required this.items});

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return _EmptyKpis();
    }
    return LayoutBuilder(
      builder: (ctx, constraints) {
        final cols = constraints.maxWidth >= 600 ? 3 : 2;
        const spacing = 10.0;
        final tileWidth = (constraints.maxWidth - spacing * (cols - 1)) / cols;
        // الـKpiCard أفقي (icon يسار + label فوق value)، الارتفاع
        // يتحدد ذاتياً حسب المحتوى — ما نقفله بـSizedBox عشان الكلام
        // ما ينقص. نقفل العرض بس.
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: items.map((it) => SizedBox(
            width: tileWidth,
            child: _KpiTile(item: it),
          )).toList(),
        );
      },
    );
  }
}

class _EmptyKpis extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withOpacity(0.3),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.4)),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.chartBar, size: 22, color: cs.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'لا توجد حركات مالية ضمن الفلتر الحالي.',
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

/// تيلة الـKPI الفردية — wrapper نحيف على KpiCard المشترك.
class _KpiTile extends StatelessWidget {
  final _KpiItem item;
  const _KpiTile({required this.item});

  @override
  Widget build(BuildContext context) {
    return KpiCard(
      label: item.label,
      value: item.value,
      icon: item.icon,
      accent: item.accent,
    );
  }
}

/// كرت "تقرير حسب المدير" — هرمية بصرية واضحة:
///   1. اسم المدير (header) + شارة "ربح/خسارة" حسب إشارة الصافي.
///   2. الصافي كعنوان كبير ملوّن (أخضر للموجب، أحمر للسالب).
///   3. الأرقام المالية الثانوية (إيرادات/ديون/صرفيات) بسطر افقي.
///   4. الـcounters (تفعيل/تمديد) كنص مضغوط بسطر واحد بالأسفل.
class _AdminRow extends StatelessWidget {
  final Map<String, dynamic> admin;
  const _AdminRow({required this.admin});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final name = admin['admin_username']?.toString() ?? '—';
    final revenue = _toDouble(admin['revenue_total']);
    final debt = _toDouble(admin['debt_total']);
    final expenses = _toDouble(admin['expenses_total']);
    final net = revenue - debt - expenses;
    final activations = _toInt(admin['activations_count']);
    final extends_ = _toInt(admin['extend_count']);

    // اللون يدلّ على الإشارة: أخضر للموجب، أحمر للسالب — يغني عن
    // أي label نصي ("ربح/خسارة").
    final netColor = net >= 0
        ? (isDark ? const Color(0xFF34D399) : const Color(0xFF047857))
        : (isDark ? const Color(0xFFFB7185) : const Color(0xFFBE123C));

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: theme.cardTheme.color ?? Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.onSurface.withValues(alpha: .07)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header: اسم المدير فقط — لون "صافي الفترة" أدناه يكفي
          // للدلالة على ربح/خسارة (أخضر vs أحمر).
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
            child: Row(
              children: [
                Container(
                  width: 30, height: 30,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(LucideIcons.userCog,
                      size: 16, color: theme.colorScheme.primary),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    name,
                    style: const TextStyle(
                      fontSize: 13.5, fontWeight: FontWeight.w800,
                      fontFamily: 'Cairo',
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),

          // الصافي — العنوان الرئيسي
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  'صافي الفترة',
                  style: TextStyle(
                    fontSize: 11.5, fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    fontFamily: 'Cairo',
                  ),
                ),
                const Spacer(),
                Text(
                  AppHelpers.formatMoney(net),
                  style: TextStyle(
                    fontSize: 19, fontWeight: FontWeight.w900,
                    color: netColor, fontFamily: 'Cairo',
                    letterSpacing: -0.3, height: 1.0,
                  ),
                ),
              ],
            ),
          ),

          // فاصل خفيف
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
            child: Container(
              height: 1,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.06),
            ),
          ),

          // الأرقام الثانوية: 3 أعمدة بسطر واحد
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
            child: Row(
              children: [
                _MiniMetric(
                  label: 'إيرادات',
                  value: AppHelpers.formatMoney(revenue),
                  color: isDark ? const Color(0xFF34D399) : const Color(0xFF047857),
                ),
                _Divider(),
                _MiniMetric(
                  label: 'ديون',
                  value: AppHelpers.formatMoney(debt),
                  color: isDark ? const Color(0xFFA78BFA) : const Color(0xFF6D28D9),
                ),
                _Divider(),
                _MiniMetric(
                  label: 'صرفيات',
                  value: AppHelpers.formatMoney(expenses),
                  color: isDark ? const Color(0xFFFB7185) : const Color(0xFFBE123C),
                ),
              ],
            ),
          ),

          // counters — سطر مضغوط بأسفل
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.025),
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(12),
                bottomRight: Radius.circular(12),
              ),
            ),
            child: Row(
              children: [
                Icon(LucideIcons.circleCheck, size: 12,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.55)),
                const SizedBox(width: 4),
                Text('تفعيل: ',
                    style: TextStyle(fontSize: 11,
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                        fontFamily: 'Cairo')),
                Text('$activations',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800,
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.85),
                        fontFamily: 'Cairo')),
                const SizedBox(width: 14),
                Icon(LucideIcons.repeat, size: 12,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.55)),
                const SizedBox(width: 4),
                Text('تمديد: ',
                    style: TextStyle(fontSize: 11,
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                        fontFamily: 'Cairo')),
                Text('$extends_',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800,
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.85),
                        fontFamily: 'Cairo')),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static double _toDouble(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0;
    return 0;
  }

  static int _toInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }
}

class _MiniMetric extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _MiniMetric({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 10.5, fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
              fontFamily: 'Cairo',
            ),
          ),
          const SizedBox(height: 3),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w800,
                color: color, fontFamily: 'Cairo',
                letterSpacing: -0.2, height: 1.0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1, height: 28,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.07),
    );
  }
}

class _LogRow extends StatelessWidget {
  final Map<String, dynamic> log;
  const _LogRow({required this.log});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final type = (log['action_type'] ?? log['action_type_ar'] ?? '').toString().toUpperCase();
    final firstname = log['user_firstname']?.toString().trim() ?? '';
    final lastname = log['user_lastname']?.toString().trim() ?? '';
    final fullname = [firstname, lastname].where((s) => s.isNotEmpty).join(' ');
    final username = log['user_username']?.toString().trim() ?? '';
    final targetName = log['target_name']?.toString().trim() ?? '';
    final title = fullname.isNotEmpty ? fullname : (username.isNotEmpty ? username : targetName);
    // عرض اسم المستخدم تحت العنوان فقط إن اختلف عن العنوان
    final subtitle = (username.isNotEmpty && username != title) ? username : '';
    final desc = AppHelpers.formatNumbersInText(log['action_description']?.toString() ?? '');
    final amount = _parseAmount(log);
    final time = log['created_at']?.toString() ?? '';
    final isDebt = type == 'BALANCE_ADD' || (type == 'SUBSCRIBER_ACTIVATE' && (desc.toLowerCase().contains('غير نقدي')));

    String formattedTime = '';
    final dt = DateTime.tryParse(time);
    if (dt != null) formattedTime = AppHelpers.formatReportDateTime(time);

    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: theme.colorScheme.onSurface.withValues(alpha: .05))),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis),
              if (subtitle.isNotEmpty)
                Text(subtitle,
                    style: TextStyle(
                      fontSize: 11,
                      color: theme.colorScheme.onSurface.withValues(alpha: .5),
                      fontWeight: FontWeight.w500,
                    ),
                    textDirection: TextDirection.ltr,
                    overflow: TextOverflow.ellipsis),
              if (desc.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(desc, style: TextStyle(fontSize: 11.5, color: theme.colorScheme.onSurface.withValues(alpha: .55)),
                      maxLines: 3, overflow: TextOverflow.ellipsis),
                ),
            ]),
          ),
          Expanded(
            flex: 2,
            child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('${isDebt ? "-" : "+"}${AppHelpers.formatMoney(amount)}',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: isDebt ? Colors.red : Colors.green)),
              Text(formattedTime, style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurface.withValues(alpha: .55))),
            ]),
          ),
        ],
      ),
    );
  }

  static double _parseAmount(Map<String, dynamic> log) {
    final raw = log['amount'];
    if (raw is num && raw != 0) return raw.toDouble().abs();
    if (raw is String && raw.isNotEmpty) {
      final cleaned = raw.replaceAll(RegExp(r'[^0-9.\-]'), '');
      final parsed = double.tryParse(cleaned);
      if (parsed != null && parsed != 0) return parsed.abs();
    }
    final desc = (log['action_description'] ?? '').toString();
    final match = RegExp(r'[\d,]+').firstMatch(desc.replaceAll(RegExp(r'[^\d,]'), ' '));
    if (match != null) {
      final val = double.tryParse(match.group(0)!.replaceAll(',', ''));
      if (val != null && val > 0) return val;
    }
    return 0;
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);
  @override
  Widget build(BuildContext context) {
    return Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .6)));
  }
}

class _FilterDropdown extends StatelessWidget {
  final String value;
  final List<DropdownMenuItem<String>> items;
  final ValueChanged<String> onChanged;
  const _FilterDropdown({required this.value, required this.items, required this.onChanged});
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Theme.of(context).colorScheme.outline.withValues(alpha: .2)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          isDense: true,
          style: TextStyle(fontSize: 12, fontFamily: 'Cairo', color: Theme.of(context).colorScheme.onSurface),
          items: items,
          onChanged: (v) { if (v != null) onChanged(v); },
        ),
      ),
    );
  }
}

class _RemovableChip extends StatelessWidget {
  final String label;
  final VoidCallback onRemove;
  const _RemovableChip({required this.label, required this.onRemove});
  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text(label, style: const TextStyle(fontSize: 10)),
      deleteIcon: const Icon(LucideIcons.x, size: 14),
      onDeleted: onRemove,
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  const _ActionBtn(this.icon, this.tooltip, this.onTap);

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: .3),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(padding: const EdgeInsets.all(8),
              child: Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary)),
        ),
      ),
    );
  }
}
