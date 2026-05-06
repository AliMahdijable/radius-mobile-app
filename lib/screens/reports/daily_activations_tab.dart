import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' as intl;
import '../../core/theme/app_theme.dart';
import '../../core/utils/helpers.dart';
import '../../core/utils/bottom_sheet_utils.dart';
import '../../providers/reports_provider.dart';
import '../../widgets/employee_filter_dropdown.dart';
import '../../widgets/report_controls.dart';

class DailyActivationsTab extends ConsumerStatefulWidget {
  const DailyActivationsTab({super.key});

  @override
  ConsumerState<DailyActivationsTab> createState() =>
      _DailyActivationsTabState();
}

class _DailyActivationsTabState extends ConsumerState<DailyActivationsTab>
    with AutomaticKeepAliveClientMixin {
  bool _loaded = false;
  String _managerId = 'all';
  String _employeeId = 'all';
  String _searchQuery = '';
  int _page = 1;
  int _perPage = 10;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
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
    await ref.read(reportsProvider.notifier).fetchDailyActivations(
          managerId: _managerId,
          employeeId: _employeeId,
        );
    if (mounted) setState(() { _loaded = true; _page = 1; });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final state = ref.watch(reportsProvider);
    final theme = Theme.of(context);

    if (state.loading && !_loaded) {
      return const Center(child: CircularProgressIndicator());
    }

    final counts = state.dailyCounts;
    final allRecords = state.dailyRecords;
    final records = _searchQuery.isEmpty
        ? allRecords
        : allRecords.where((r) {
            final target = (r['target_name'] ?? '').toString().toLowerCase();
            final desc = (r['action_description'] ?? '').toString().toLowerCase();
            final q = _searchQuery.toLowerCase();
            return target.contains(q) || desc.contains(q);
          }).toList();

    final totalPages = (records.length / _perPage).ceil();
    if (_page > totalPages && totalPages > 0) _page = totalPages;
    final paged = records.skip((_page - 1) * _perPage).take(_perPage).toList();

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Search bar
          TextField(
            textDirection: TextDirection.ltr,
            textAlign: TextAlign.left,
            onChanged: (v) => setState(() { _searchQuery = v; _page = 1; }),
            decoration: InputDecoration(
              hintText: 'بحث باسم المشترك...',
              prefixIcon: const Icon(LucideIcons.search, size: 20),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(LucideIcons.x, size: 18),
                      onPressed: () => setState(() { _searchQuery = ''; _page = 1; }),
                    )
                  : null,
            ),
          ),
          const SizedBox(height: 8),

          // Filter + refresh row
          Row(children: [
            Expanded(
              child: GestureDetector(
                onTap: _showFilterSheet,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: .3),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(children: [
                    Icon(LucideIcons.funnel, size: 14, color: theme.colorScheme.primary),
                    const SizedBox(width: 6),
                    Text('الفلاتر', style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withValues(alpha: .7))),
                    if (_managerId != 'all') ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(color: theme.colorScheme.primary.withValues(alpha: .1), borderRadius: BorderRadius.circular(4)),
                        child: Text('1', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: theme.colorScheme.primary)),
                      ),
                    ],
                    const Spacer(),
                    Icon(LucideIcons.slidersHorizontal, size: 14, color: theme.colorScheme.onSurface.withValues(alpha: .4)),
                  ]),
                ),
              ),
            ),
            const SizedBox(width: 6),
            Material(
              color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: .3),
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: _load,
                child: Padding(padding: const EdgeInsets.all(8),
                    child: Icon(LucideIcons.refreshCw, size: 18, color: theme.colorScheme.primary)),
              ),
            ),
          ]),
          const SizedBox(height: 10),

          // Active filters
          if (_managerId != 'all' || _employeeId != 'all')
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Wrap(spacing: 6, children: [
                if (_managerId != 'all')
                  Chip(
                    label: Text('مدير: ${state.managers.firstWhere((m) => m.id == _managerId, orElse: () => const ManagerOption(id: '', name: '?')).name}',
                        style: const TextStyle(fontSize: 10)),
                    deleteIcon: const Icon(LucideIcons.x, size: 14),
                    onDeleted: () { setState(() => _managerId = 'all'); _load(); },
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                if (_employeeId != 'all')
                  Chip(
                    label: const Text('موظف محدد', style: TextStyle(fontSize: 10)),
                    deleteIcon: const Icon(LucideIcons.x, size: 14),
                    onDeleted: () { setState(() => _employeeId = 'all'); _load(); },
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
              ]),
            ),

          Row(children: [
            _StatMini(label: 'الإجمالي', value: '${counts['total'] ?? 0}', color: AppTheme.primary),
            const SizedBox(width: 8),
            _StatMini(label: 'تفعيل', value: '${counts['activate'] ?? 0}', color: AppTheme.successColor),
            const SizedBox(width: 8),
            _StatMini(label: 'تمديد', value: '${counts['extend'] ?? 0}', color: AppTheme.warningColor),
          ]),
          const SizedBox(height: 8),

          // Pagination
          if (records.isNotEmpty)
            PaginationBar(
              totalItems: records.length,
              currentPage: _page,
              rowsPerPage: _perPage,
              itemLabel: 'تفعيل',
              onPageChanged: (p) => setState(() => _page = p),
              onRowsPerPageChanged: (r) => setState(() { _perPage = r; _page = 1; }),
            ),
          const SizedBox(height: 4),

          if (records.isEmpty)
            _EmptyState(message: 'لا توجد تفعيلات اليوم')
          else
            ...paged.map((r) => _ActivationRow(record: r)),
        ],
      ),
    );
  }

  void _showFilterSheet() {
    final managers = ref.read(reportsProvider).managers;
    showModalBottomSheet(
      useSafeArea: true,
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        String mgr = _managerId;
        String emp = _employeeId;
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

                  if (managers.isNotEmpty) ...[
                    Text('المدير', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                        color: Theme.of(ctx).colorScheme.onSurface.withValues(alpha: .6))),
                    const SizedBox(height: 6),
                    Container(
                      height: 38,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Theme.of(ctx).colorScheme.outline.withValues(alpha: .2)),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: mgr, isExpanded: true, isDense: true,
                          style: TextStyle(fontSize: 12, fontFamily: 'Cairo', color: Theme.of(ctx).colorScheme.onSurface),
                          items: [
                            const DropdownMenuItem(value: 'all', child: Text('جميع المدراء')),
                            ...managers.map((m) => DropdownMenuItem(value: m.id, child: Text(m.name, overflow: TextOverflow.ellipsis))),
                          ],
                          onChanged: (v) { if (v != null) setSheet(() => mgr = v); },
                        ),
                      ),
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
                      setState(() { _managerId = mgr; _employeeId = emp; _page = 1; });
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
}

class _StatMini extends StatelessWidget {
  final String label; final String value; final Color color;
  const _StatMini({required this.label, required this.value, required this.color});
  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [color, color.withValues(alpha: .7)], begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(children: [
          Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white)),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(fontSize: 11, color: Colors.white70)),
        ]),
      ),
    );
  }
}

class _ActivationRow extends StatelessWidget {
  final Map<String, dynamic> record;
  const _ActivationRow({required this.record});
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isExtend = (record['action_type'] ?? '').toString() == 'SUBSCRIBER_EXTEND';
    final label = isExtend ? 'تمديد' : 'تفعيل';
    final color = isExtend ? AppTheme.warningColor : AppTheme.successColor;
    final icon = isExtend ? LucideIcons.clock : LucideIcons.circleCheck;
    final firstname = (record['user_firstname'] ?? '').toString().trim();
    final lastname = (record['user_lastname'] ?? '').toString().trim();
    final fullname = [firstname, lastname].where((s) => s.isNotEmpty).join(' ');
    final username = (record['user_username'] ?? record['target_name'] ?? '')
        .toString()
        .trim();
    final target = fullname.isNotEmpty ? fullname : username;
    final subtitle = (username.isNotEmpty && username != target) ? username : '';
    final desc = AppHelpers.formatNumbersInText(record['action_description']?.toString() ?? '');
    final time = record['created_at']?.toString() ?? '';
    String formattedTime = '';
    final dt = DateTime.tryParse(time);
    if (dt != null) formattedTime = AppHelpers.formatReportTime(dt.toLocal());

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.cardTheme.color ?? Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.onSurface.withValues(alpha: .06)),
      ),
      child: Row(children: [
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(color: color.withValues(alpha: .1), borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, size: 18, color: color),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(label, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: color)),
              const SizedBox(width: 6),
              Expanded(child: Text(target, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700,
                  color: theme.colorScheme.onSurface.withValues(alpha: .9)), overflow: TextOverflow.ellipsis)),
            ]),
            if (subtitle.isNotEmpty)
              Padding(padding: const EdgeInsets.only(top: 2),
                  child: Text(subtitle,
                      textDirection: TextDirection.ltr,
                      style: TextStyle(fontSize: 11,
                          color: theme.colorScheme.onSurface.withValues(alpha: .5),
                          fontWeight: FontWeight.w500),
                      overflow: TextOverflow.ellipsis)),
            if (desc.isNotEmpty)
              Padding(padding: const EdgeInsets.only(top: 3),
                  child: Text(desc, style: TextStyle(fontSize: 11.5, color: theme.colorScheme.onSurface.withValues(alpha: .55)),
                      maxLines: 3, overflow: TextOverflow.ellipsis)),
          ]),
        ),
        Text(formattedTime, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
            color: theme.colorScheme.onSurface.withValues(alpha: .6))),
      ]),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String message;
  const _EmptyState({required this.message});
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 60),
      child: Column(children: [
        Icon(LucideIcons.inbox, size: 48, color: theme.colorScheme.onSurface.withValues(alpha: .2)),
        const SizedBox(height: 8),
        Text(message, style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: .4))),
      ]),
    );
  }
}
