import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' as intl;
import '../../core/theme/app_theme.dart';
import '../../providers/reports_provider.dart';

class ActivationsTab extends ConsumerStatefulWidget {
  const ActivationsTab({super.key});

  @override
  ConsumerState<ActivationsTab> createState() => _ActivationsTabState();
}

class _ActivationsTabState extends ConsumerState<ActivationsTab>
    with AutomaticKeepAliveClientMixin {
  late String _dateFrom;
  late String _dateTo;
  String _filter = 'all'; // all | activate | extend
  bool _loaded = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _dateTo = intl.DateFormat('yyyy-MM-dd').format(now);
    _dateFrom =
        intl.DateFormat('yyyy-MM-dd').format(now.subtract(const Duration(days: 30)));
    Future.microtask(() => _load());
  }

  Future<void> _load() async {
    await ref
        .read(reportsProvider.notifier)
        .fetchActivationsReport(_dateFrom, _dateTo);
    if (mounted) setState(() => _loaded = true);
  }

  List<Map<String, dynamic>> get _filtered {
    final all = ref.read(reportsProvider).activations;
    if (_filter == 'all') return all;
    return all.where((a) {
      final type = (a['action_type'] ?? '').toString().toUpperCase();
      if (_filter == 'activate') return type == 'SUBSCRIBER_ACTIVATE';
      return type == 'SUBSCRIBER_EXTEND';
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final state = ref.watch(reportsProvider);
    final theme = Theme.of(context);

    if (state.loading && !_loaded) {
      return const Center(child: CircularProgressIndicator());
    }

    final all = state.activations;
    final activateCount = all
        .where((a) =>
            (a['action_type'] ?? '').toString().toUpperCase() ==
            'SUBSCRIBER_ACTIVATE')
        .length;
    final extendCount = all.length - activateCount;
    final items = _filtered;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Date info
          GestureDetector(
            onTap: _showDateFilter,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest
                    .withValues(alpha: .3),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(children: [
                Icon(Icons.date_range,
                    size: 16, color: theme.colorScheme.primary),
                const SizedBox(width: 6),
                Text('$_dateFrom  —  $_dateTo',
                    style: const TextStyle(fontSize: 12)),
                const Spacer(),
                Icon(Icons.tune,
                    size: 16,
                    color: theme.colorScheme.onSurface.withValues(alpha: .4)),
              ]),
            ),
          ),
          const SizedBox(height: 12),

          // Stats
          Row(children: [
            _StatChip('الإجمالي', '${all.length}', AppTheme.primary),
            const SizedBox(width: 6),
            _StatChip('تفعيل', '$activateCount', AppTheme.successColor),
            const SizedBox(width: 6),
            _StatChip('تمديد', '$extendCount', AppTheme.warningColor),
          ]),
          const SizedBox(height: 12),

          // Filter chips
          Row(children: [
            _FilterChip('الكل', _filter == 'all',
                () => setState(() => _filter = 'all')),
            const SizedBox(width: 6),
            _FilterChip('تفعيل', _filter == 'activate',
                () => setState(() => _filter = 'activate')),
            const SizedBox(width: 6),
            _FilterChip('تمديد', _filter == 'extend',
                () => setState(() => _filter = 'extend')),
          ]),
          const SizedBox(height: 12),

          if (items.isEmpty)
            _emptyWidget(theme)
          else
            ...items.map((a) => _ActivationRow(record: a)),
        ],
      ),
    );
  }

  Widget _emptyWidget(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 60),
      child: Column(children: [
        Icon(Icons.inbox_rounded,
            size: 48,
            color: theme.colorScheme.onSurface.withValues(alpha: .2)),
        const SizedBox(height: 8),
        Text('لا توجد تفعيلات',
            style: TextStyle(
                color: theme.colorScheme.onSurface.withValues(alpha: .4))),
      ]),
    );
  }

  void _showDateFilter() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        String from = _dateFrom;
        String to = _dateTo;
        return StatefulBuilder(builder: (ctx, setSheet) {
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                      child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                              color: Colors.grey.shade300,
                              borderRadius: BorderRadius.circular(2)))),
                  const SizedBox(height: 16),
                  Text('فلتر التاريخ',
                      style: Theme.of(ctx)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 16),
                  Wrap(spacing: 8, children: [
                    ActionChip(
                        label: const Text('اليوم',
                            style: TextStyle(fontSize: 11)),
                        onPressed: () {
                          final today = intl.DateFormat('yyyy-MM-dd')
                              .format(DateTime.now());
                          setSheet(() {
                            from = today;
                            to = today;
                          });
                        }),
                    ActionChip(
                        label: const Text('آخر 7 أيام',
                            style: TextStyle(fontSize: 11)),
                        onPressed: () {
                          final now = DateTime.now();
                          setSheet(() {
                            to = intl.DateFormat('yyyy-MM-dd').format(now);
                            from = intl.DateFormat('yyyy-MM-dd').format(
                                now.subtract(const Duration(days: 7)));
                          });
                        }),
                    ActionChip(
                        label: const Text('آخر 30 يوم',
                            style: TextStyle(fontSize: 11)),
                        onPressed: () {
                          final now = DateTime.now();
                          setSheet(() {
                            to = intl.DateFormat('yyyy-MM-dd').format(now);
                            from = intl.DateFormat('yyyy-MM-dd').format(
                                now.subtract(const Duration(days: 30)));
                          });
                        }),
                  ]),
                  const SizedBox(height: 16),
                  SizedBox(
                      height: 48,
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.pop(ctx);
                          setState(() {
                            _dateFrom = from;
                            _dateTo = to;
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
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _StatChip(this.label, this.value, this.color);

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: .2)),
        ),
        child: Column(children: [
          Text(value,
              style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w800, color: color)),
          Text(label,
              style: TextStyle(
                  fontSize: 10, color: color.withValues(alpha: .7))),
        ]),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _FilterChip(this.label, this.selected, this.onTap);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? AppTheme.primary.withValues(alpha: .1)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: selected
                  ? AppTheme.primary.withValues(alpha: .3)
                  : Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: .15)),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? AppTheme.primary : null)),
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
    final type = (record['action_type'] ?? '').toString().toUpperCase();
    final isExtend = type == 'SUBSCRIBER_EXTEND';
    final label = isExtend ? 'تمديد' : 'تفعيل';
    final color = isExtend ? AppTheme.warningColor : AppTheme.successColor;
    final icon =
        isExtend ? Icons.schedule_rounded : Icons.check_circle_rounded;
    final target = record['target_name']?.toString() ?? '';
    final desc = record['action_description']?.toString() ?? '';
    final admin = record['admin_username']?.toString() ?? '';
    final time = record['created_at']?.toString() ?? '';

    String formattedTime = '';
    final dt = DateTime.tryParse(time);
    if (dt != null) {
      formattedTime =
          intl.DateFormat('MM/dd HH:mm').format(dt.toLocal());
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.cardTheme.color ?? Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: theme.colorScheme.onSurface.withValues(alpha: .06)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: color.withValues(alpha: .1),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, size: 17, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Text(label,
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: color)),
                  const SizedBox(width: 6),
                  Expanded(
                      child: Text(target,
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: .8)),
                          overflow: TextOverflow.ellipsis)),
                  Text(formattedTime,
                      style: TextStyle(
                          fontSize: 10,
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: .4))),
                ]),
                if (desc.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(desc,
                        style: TextStyle(
                            fontSize: 10,
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: .4)),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ),
                if (admin.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Text('المدير: $admin',
                        style: TextStyle(
                            fontSize: 10,
                            color: theme.colorScheme.primary
                                .withValues(alpha: .5))),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
