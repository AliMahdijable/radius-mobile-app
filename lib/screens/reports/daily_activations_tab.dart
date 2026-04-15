import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' as intl;
import '../../core/theme/app_theme.dart';
import '../../providers/reports_provider.dart';
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
  }

  Future<void> _load() async {
    await ref.read(reportsProvider.notifier).fetchDailyActivations(
          managerId: _managerId,
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
    final records = state.dailyRecords;

    final totalPages = (records.length / _perPage).ceil();
    if (_page > totalPages && totalPages > 0) _page = totalPages;
    final paged = records.skip((_page - 1) * _perPage).take(_perPage).toList();

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Manager filter
          if (state.managers.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: ManagerFilter(
                managers: state.managers,
                selectedId: _managerId,
                onChanged: (v) {
                  setState(() => _managerId = v);
                  _load();
                },
              ),
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
    final icon = isExtend ? Icons.schedule_rounded : Icons.check_circle_rounded;
    final target = record['target_name']?.toString() ?? '';
    final desc = record['action_description']?.toString() ?? '';
    final time = record['created_at']?.toString() ?? '';
    String formattedTime = '';
    final dt = DateTime.tryParse(time);
    if (dt != null) formattedTime = intl.DateFormat('HH:mm').format(dt.toLocal());

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
              Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color)),
              const SizedBox(width: 6),
              Expanded(child: Text(target, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurface.withValues(alpha: .8)), overflow: TextOverflow.ellipsis)),
            ]),
            if (desc.isNotEmpty)
              Text(desc, style: TextStyle(fontSize: 10, color: theme.colorScheme.onSurface.withValues(alpha: .4)),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
          ]),
        ),
        Text(formattedTime, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
            color: theme.colorScheme.onSurface.withValues(alpha: .4))),
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
        Icon(Icons.inbox_rounded, size: 48, color: theme.colorScheme.onSurface.withValues(alpha: .2)),
        const SizedBox(height: 8),
        Text(message, style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: .4))),
      ]),
    );
  }
}
