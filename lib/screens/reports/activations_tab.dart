import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' as intl;
import '../../core/theme/app_theme.dart';
import '../../core/utils/csv_export.dart';
import '../../providers/reports_provider.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/report_controls.dart';

class ActivationsTab extends ConsumerStatefulWidget {
  const ActivationsTab({super.key});

  @override
  ConsumerState<ActivationsTab> createState() => _ActivationsTabState();
}

class _ActivationsTabState extends ConsumerState<ActivationsTab>
    with AutomaticKeepAliveClientMixin {
  late String _dateFrom;
  late String _dateTo;
  String _filter = 'all';
  String _managerId = 'all';
  String _searchQuery = '';
  bool _loaded = false;
  int _page = 1;
  int _perPage = 10;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _dateTo = intl.DateFormat('yyyy-MM-dd').format(now);
    _dateFrom = intl.DateFormat('yyyy-MM-dd').format(now.subtract(const Duration(days: 30)));
    Future.microtask(() async {
      await ref.read(reportsProvider.notifier).fetchManagers();
      _load();
    });
  }

  Future<void> _load() async {
    await ref.read(reportsProvider.notifier).fetchActivationsReport(
          _dateFrom, _dateTo,
          managerId: _managerId,
        );
    if (mounted) setState(() { _loaded = true; _page = 1; });
  }

  List<Map<String, dynamic>> get _filtered {
    final all = ref.read(reportsProvider).activations;
    var list = all;
    if (_filter != 'all') {
      list = list.where((a) {
        final type = (a['action_type'] ?? '').toString().toUpperCase();
        if (_filter == 'activate') return type == 'SUBSCRIBER_ACTIVATE';
        return type == 'SUBSCRIBER_EXTEND';
      }).toList();
    }
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      list = list.where((a) {
        final target = (a['target_name'] ?? '').toString().toLowerCase();
        final desc = (a['action_description'] ?? '').toString().toLowerCase();
        final admin = (a['admin_username'] ?? '').toString().toLowerCase();
        return target.contains(q) || desc.contains(q) || admin.contains(q);
      }).toList();
    }
    return list;
  }

  Future<void> _exportCsv() async {
    final items = _filtered;
    if (items.isEmpty) {
      AppSnackBar.warning(context, 'لا توجد بيانات للتصدير');
      return;
    }
    try {
      await CsvExport.exportAndShare(
        fileName: 'activations-$_dateFrom-$_dateTo.csv',
        headers: ['المشترك', 'نوع الحركة', 'الوقت', 'الوصف', 'المدير'],
        rows: items.map((a) => [
          a['target_name']?.toString() ?? '',
          (a['action_type'] ?? '').toString().toUpperCase() == 'SUBSCRIBER_EXTEND' ? 'تمديد' : 'تفعيل',
          a['created_at']?.toString() ?? '',
          a['action_description']?.toString() ?? '',
          a['admin_username']?.toString() ?? '',
        ]).toList(),
      );
    } catch (_) {
      if (mounted) AppSnackBar.error(context, 'فشل تصدير البيانات');
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

    final all = state.activations;
    final activateCount = all.where((a) =>
        (a['action_type'] ?? '').toString().toUpperCase() == 'SUBSCRIBER_ACTIVATE').length;
    final extendCount = all.length - activateCount;
    final items = _filtered;

    final totalPages = (items.length / _perPage).ceil();
    if (_page > totalPages && totalPages > 0) _page = totalPages;
    final paged = items.skip((_page - 1) * _perPage).take(_perPage).toList();

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
              prefixIcon: const Icon(Icons.search, size: 20),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () => setState(() { _searchQuery = ''; _page = 1; }),
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
                    Expanded(child: Text('$_dateFrom — $_dateTo',
                        style: const TextStyle(fontSize: 11), overflow: TextOverflow.ellipsis)),
                    Icon(Icons.tune, size: 14, color: theme.colorScheme.onSurface.withValues(alpha: .4)),
                  ]),
                ),
              ),
            ),
            const SizedBox(width: 6),
            _SmallBtn(Icons.download_rounded, _exportCsv),
            const SizedBox(width: 4),
            _SmallBtn(Icons.refresh_rounded, _load),
          ]),
          const SizedBox(height: 8),

          // Active filter chips
          if (_managerId != 'all')
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Wrap(spacing: 6, children: [
                Chip(
                  label: Text('مدير: ${state.managers.firstWhere((m) => m.id == _managerId, orElse: () => const ManagerOption(id: '', name: '?')).name}',
                      style: const TextStyle(fontSize: 10)),
                  deleteIcon: const Icon(Icons.close, size: 14),
                  onDeleted: () { setState(() => _managerId = 'all'); _load(); },
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ]),
            ),

          // Stats
          Row(children: [
            _StatChip('الإجمالي', '${all.length}', AppTheme.primary),
            const SizedBox(width: 6),
            _StatChip('تفعيل', '$activateCount', AppTheme.successColor),
            const SizedBox(width: 6),
            _StatChip('تمديد', '$extendCount', AppTheme.warningColor),
          ]),
          const SizedBox(height: 10),

          const SizedBox(height: 4),

          // Pagination
          PaginationBar(
            totalItems: items.length,
            currentPage: _page,
            rowsPerPage: _perPage,
            itemLabel: 'تفعيل',
            onPageChanged: (p) => setState(() => _page = p),
            onRowsPerPageChanged: (r) => setState(() { _perPage = r; _page = 1; }),
          ),
          const SizedBox(height: 4),

          if (paged.isEmpty)
            _emptyWidget(theme)
          else
            ...paged.map((a) => _ActivationRow(record: a)),
        ],
      ),
    );
  }

  Widget _emptyWidget(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 60),
      child: Column(children: [
        Icon(Icons.inbox_rounded, size: 48, color: theme.colorScheme.onSurface.withValues(alpha: .2)),
        const SizedBox(height: 8),
        Text('لا توجد تفعيلات', style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: .4))),
      ]),
    );
  }

  void _showDateFilter() {
    final managers = ref.read(reportsProvider).managers;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        String from = _dateFrom;
        String to = _dateTo;
        String mgr = _managerId;
        String flt = _filter;
        return StatefulBuilder(builder: (ctx, setSheet) {
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(20),
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
                    _qc('شهر', () { final n = DateTime.now(); setSheet(() { to = intl.DateFormat('yyyy-MM-dd').format(n); from = intl.DateFormat('yyyy-MM-dd').format(n.subtract(const Duration(days: 30))); }); }),
                  ]),
                  const SizedBox(height: 14),

                  _SectionLabel('نوع الحركة'),
                  const SizedBox(height: 6),
                  Wrap(spacing: 6, runSpacing: 6, children: [
                    FilterChip(label: const Text('الكل', style: TextStyle(fontSize: 11)), selected: flt == 'all',
                        onSelected: (_) => setSheet(() => flt = 'all'), selectedColor: AppTheme.primary.withValues(alpha: .15), checkmarkColor: AppTheme.primary, visualDensity: VisualDensity.compact),
                    FilterChip(label: const Text('تفعيل', style: TextStyle(fontSize: 11)), selected: flt == 'activate',
                        onSelected: (_) => setSheet(() => flt = 'activate'), selectedColor: AppTheme.successColor.withValues(alpha: .15), checkmarkColor: AppTheme.successColor, visualDensity: VisualDensity.compact),
                    FilterChip(label: const Text('تمديد', style: TextStyle(fontSize: 11)), selected: flt == 'extend',
                        onSelected: (_) => setSheet(() => flt = 'extend'), selectedColor: AppTheme.warningColor.withValues(alpha: .15), checkmarkColor: AppTheme.warningColor, visualDensity: VisualDensity.compact),
                  ]),
                  const SizedBox(height: 14),

                  if (managers.isNotEmpty) ...[
                    _SectionLabel('المدير'),
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

                  SizedBox(height: 48, child: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      setState(() {
                        _dateFrom = from;
                        _dateTo = to;
                        _managerId = mgr;
                        _filter = flt;
                        _page = 1;
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

class _StatChip extends StatelessWidget {
  final String label; final String value; final Color color;
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
          Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: color)),
          Text(label, style: TextStyle(fontSize: 10, color: color.withValues(alpha: .7))),
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
    final type = (record['action_type'] ?? '').toString().toUpperCase();
    final isExtend = type == 'SUBSCRIBER_EXTEND';
    final label = isExtend ? 'تمديد' : 'تفعيل';
    final color = isExtend ? AppTheme.warningColor : AppTheme.successColor;
    final icon = isExtend ? Icons.schedule_rounded : Icons.check_circle_rounded;
    final target = record['target_name']?.toString() ?? '';
    final desc = record['action_description']?.toString() ?? '';
    final admin = record['admin_username']?.toString() ?? '';
    final time = record['created_at']?.toString() ?? '';
    String formattedTime = '';
    final dt = DateTime.tryParse(time);
    if (dt != null) formattedTime = intl.DateFormat('MM/dd HH:mm').format(dt.toLocal());

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.cardTheme.color ?? Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.onSurface.withValues(alpha: .06)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 34, height: 34,
          decoration: BoxDecoration(color: color.withValues(alpha: .1), borderRadius: BorderRadius.circular(9)),
          child: Icon(icon, size: 17, color: color),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color)),
              const SizedBox(width: 6),
              Expanded(child: Text(target, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurface.withValues(alpha: .8)), overflow: TextOverflow.ellipsis)),
              Text(formattedTime, style: TextStyle(fontSize: 10, color: theme.colorScheme.onSurface.withValues(alpha: .4))),
            ]),
            if (desc.isNotEmpty)
              Padding(padding: const EdgeInsets.only(top: 2),
                  child: Text(desc, style: TextStyle(fontSize: 10, color: theme.colorScheme.onSurface.withValues(alpha: .4)),
                      maxLines: 1, overflow: TextOverflow.ellipsis)),
            if (admin.isNotEmpty)
              Padding(padding: const EdgeInsets.only(top: 1),
                  child: Text('المدير: $admin', style: TextStyle(fontSize: 10, color: theme.colorScheme.primary.withValues(alpha: .5)))),
          ]),
        ),
      ]),
    );
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

class _SmallBtn extends StatelessWidget {
  final IconData icon; final VoidCallback onTap;
  const _SmallBtn(this.icon, this.onTap);
  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: .3),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10), onTap: onTap,
        child: Padding(padding: const EdgeInsets.all(8),
            child: Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary)),
      ),
    );
  }
}
