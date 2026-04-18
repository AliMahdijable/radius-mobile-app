import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' as intl;
import '../../core/theme/app_theme.dart';
import '../../core/utils/helpers.dart';
import '../../core/utils/bottom_sheet_utils.dart';
import '../../core/utils/csv_export.dart';
import '../../providers/reports_provider.dart';
import '../../widgets/app_snackbar.dart';
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
  }


  Future<void> _load() async {
    await ref.read(reportsProvider.notifier).fetchFinancialReport(
          _dateFrom, _dateTo,
          managerId: _managerId,
          actionTypes: _selectedActionTypes.isNotEmpty ? _selectedActionTypes.toList() : null,
          userManager: _userManagerId != 'all' ? _userManagerId : null,
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
    final netProfit = collections - debts;
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
              prefixIcon: const Icon(Icons.search, size: 20),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 18),
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
                    Icon(Icons.date_range, size: 14, color: theme.colorScheme.primary),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text('$_dateFrom — $_dateTo',
                          style: const TextStyle(fontSize: 11),
                          overflow: TextOverflow.ellipsis),
                    ),
                    Icon(Icons.tune, size: 14,
                        color: theme.colorScheme.onSurface.withValues(alpha: .4)),
                  ]),
                ),
              ),
            ),
            const SizedBox(width: 6),
            _ActionBtn(Icons.download_rounded, 'تصدير', _exportCsv),
            const SizedBox(width: 4),
            _ActionBtn(Icons.refresh_rounded, 'تحديث', _load),
          ]),
          const SizedBox(height: 8),

          // Active filter chips
          if (_managerId != 'all' || _userManagerId != 'all' || _selectedActionTypes.isNotEmpty)
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
                ..._selectedActionTypes.map((t) {
                  final lbl = _actionTypeOptions.firstWhere((o) => o['value'] == t, orElse: () => {'label': t})['label']!;
                  return _RemovableChip(
                    label: lbl,
                    onRemove: () { setState(() => _selectedActionTypes.remove(t)); _load(); },
                  );
                }),
              ]),
            ),

          // KPI cards
          Row(children: [
            _KpiCard(
              label: 'إجمالي التحصيلات',
              value: AppHelpers.formatMoney(collections),
              icon: Icons.trending_up_rounded,
              colors: const [Color(0xFF10b981), Color(0xFF059669)],
            ),
            const SizedBox(width: 10),
            _KpiCard(
              label: 'تفعيل + تمديد',
              value: activationsTotal.toInt().toString(),
              icon: Icons.check_circle_rounded,
              colors: const [Color(0xFFf59e0b), Color(0xFFd97706)],
            ),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            _KpiCard(
              label: 'إجمالي الديون',
              value: AppHelpers.formatMoney(debts),
              icon: Icons.payments_rounded,
              colors: const [Color(0xFF16a34a), Color(0xFF0f9d58)],
            ),
            const SizedBox(width: 10),
            _KpiCard(
              label: 'صافي الربح',
              value: AppHelpers.formatMoney(netProfit),
              icon: Icons.account_balance_wallet_rounded,
              colors: const [Color(0xFF0ea5e9), Color(0xFF0284c7)],
            ),
          ]),
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

                  SizedBox(height: AppTheme.actionButtonHeight, child: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      setState(() {
                        _dateFrom = from;
                        _dateTo = to;
                        _managerId = mgr;
                        _userManagerId = userMgr;
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

class _KpiCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final List<Color> colors;

  const _KpiCard({required this.label, required this.value, required this.icon, required this.colors});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: colors, begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(icon, size: 18, color: Colors.white70),
              const SizedBox(width: 6),
              Expanded(child: Text(label, style: const TextStyle(fontSize: 11, color: Colors.white70), overflow: TextOverflow.ellipsis)),
            ]),
            const SizedBox(height: 8),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }
}

class _AdminRow extends StatelessWidget {
  final Map<String, dynamic> admin;
  const _AdminRow({required this.admin});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = admin['admin_username']?.toString() ?? '—';
    final revenue = _toDouble(admin['revenue_total']);
    final debt = _toDouble(admin['debt_total']);
    final net = revenue - debt;
    final activations = _toInt(admin['activations_count']);
    final extends_ = _toInt(admin['extend_count']);

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.cardTheme.color ?? Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.onSurface.withValues(alpha: .06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Row(children: [
            _MiniStat('إيرادات', AppHelpers.formatMoney(revenue), Colors.green),
            const SizedBox(width: 4),
            _MiniStat('ديون', AppHelpers.formatMoney(debt), Colors.red),
            const SizedBox(width: 4),
            _MiniStat('صافي', AppHelpers.formatMoney(net), Colors.blue),
          ]),
          const SizedBox(height: 6),
          Row(children: [
            _MiniStat('تفعيل', '$activations', AppTheme.successColor),
            const SizedBox(width: 4),
            _MiniStat('تمديد', '$extends_', AppTheme.warningColor),
            const Spacer(flex: 3),
          ]),
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

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _MiniStat(this.label, this.value, this.color);

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .06),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Column(children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(value,
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color)),
          ),
          const SizedBox(height: 1),
          Text(label,
              style: TextStyle(fontSize: 9,
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .4))),
        ]),
      ),
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
    final target = log['user_username']?.toString() ?? log['target_name']?.toString() ?? '';
    final desc = AppHelpers.formatNumbersInText(log['action_description']?.toString() ?? '');
    final amount = _parseAmount(log);
    final time = log['created_at']?.toString() ?? '';
    final isDebt = type == 'BALANCE_ADD' || (type == 'SUBSCRIBER_ACTIVATE' && (desc.toLowerCase().contains('غير نقدي')));

    String formattedTime = '';
    final dt = DateTime.tryParse(time);
    if (dt != null) formattedTime = intl.DateFormat('MM/dd HH:mm').format(dt.toLocal());

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
              Text(target, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
              if (desc.isNotEmpty)
                Text(desc, style: TextStyle(fontSize: 10, color: theme.colorScheme.onSurface.withValues(alpha: .4)),
                    maxLines: 3, overflow: TextOverflow.ellipsis),
            ]),
          ),
          Expanded(
            flex: 2,
            child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('${isDebt ? "-" : "+"}${AppHelpers.formatMoney(amount)}',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: isDebt ? Colors.red : Colors.green)),
              Text(formattedTime, style: TextStyle(fontSize: 9, color: theme.colorScheme.onSurface.withValues(alpha: .4))),
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
      deleteIcon: const Icon(Icons.close, size: 14),
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
