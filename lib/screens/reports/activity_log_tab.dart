import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' as intl;
import '../../core/network/dio_client.dart';
import '../../core/theme/app_theme.dart';
import '../../core/services/storage_service.dart';
import '../../core/utils/csv_export.dart';
import '../../providers/reports_provider.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/report_controls.dart';

class ActivityLogTab extends ConsumerStatefulWidget {
  const ActivityLogTab({super.key});

  @override
  ConsumerState<ActivityLogTab> createState() => _ActivityLogTabState();
}

class _ActivityLogTabState extends ConsumerState<ActivityLogTab>
    with AutomaticKeepAliveClientMixin {
  List<Map<String, dynamic>> _activities = [];
  bool _loading = false;
  String _search = '';
  late String _dateFrom;
  late String _dateTo;
  String _managerId = 'all';
  String _activityType = 'all';
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
      _fetchActivities();
    });
  }

  Future<void> _fetchActivities() async {
    setState(() => _loading = true);
    try {
      final dio = ref.read(backendDioProvider);
      final storage = ref.read(storageServiceProvider);
      final adminId = await storage.getAdminId();
      final managers = ref.read(reportsProvider).managers;

      final params = <String, dynamic>{
        'date_from': '$_dateFrom 00:00:00',
        'date_to': '$_dateTo 23:59:59',
        'limit': '500',
      };
      if (_search.isNotEmpty) params['search'] = _search;
      if (_activityType != 'all') params['activity_type'] = _activityType;
      if (_managerId != 'all') {
        params['user_ids'] = _managerId;
      } else if (adminId != null) {
        final allIds = [adminId, ...managers.map((m) => m.id)];
        params['user_ids'] = allIds.toSet().join(',');
      }

      final response = await dio.get('/api/activities', queryParameters: params);

      if (response.data?['data'] is List) {
        final list = (response.data['data'] as List)
            .where((log) {
              final action = log['action']?.toString() ?? '';
              final url = log['request_url']?.toString() ?? '';
              return !action.contains('verify-token') && !url.contains('verify-token');
            })
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        setState(() { _activities = list; _page = 1; });
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  static _ActionStyle _getActionStyle(Map<String, dynamic> log) {
    final type = (log['action_type'] ?? '').toString().toUpperCase().trim();
    switch (type) {
      case 'SUBSCRIBER_ACTIVATE':
        return _ActionStyle('تفعيل مشترك', Icons.check_circle_rounded, Colors.green);
      case 'SUBSCRIBER_EXTEND':
        return _ActionStyle('تمديد مشترك', Icons.schedule_rounded, Colors.amber.shade700);
      case 'SUBSCRIBER_ADD':
        return _ActionStyle('إضافة مشترك', Icons.person_add_rounded, Colors.blue);
      case 'SUBSCRIBER_EDIT':
        return _ActionStyle('تعديل مشترك', Icons.edit_rounded, Colors.purple);
      case 'SUBSCRIBER_DELETE':
        return _ActionStyle('حذف مشترك', Icons.person_remove_rounded, Colors.red);
      case 'BALANCE_ADD':
        return _ActionStyle('إضافة دين', Icons.add_circle_rounded, Colors.red);
      case 'BALANCE_DEDUCT':
        return _ActionStyle('تسديد دين', Icons.remove_circle_rounded, Colors.green);
      case 'PAYMENT_ADD':
      case 'DEBT_PAY':
        return _ActionStyle('تسديد دين', Icons.account_balance_wallet_rounded, Colors.green);
      case 'LOGIN':
        return _ActionStyle('تسجيل دخول', Icons.login_rounded, Colors.indigo);
      case 'WHATSAPP_SEND_MESSAGE':
        return _ActionStyle('رسالة واتساب', Icons.chat_rounded, AppTheme.whatsappGreen);
      default:
        return _ActionStyle(type.isNotEmpty ? type : 'أخرى', Icons.settings_rounded, Colors.grey);
    }
  }

  Future<void> _exportCsv() async {
    if (_activities.isEmpty) {
      AppSnackBar.warning(context, 'لا توجد بيانات للتصدير');
      return;
    }
    try {
      await CsvExport.exportAndShare(
        fileName: 'activity-log-$_dateFrom-$_dateTo.csv',
        headers: ['الوقت', 'نوع الحركة', 'المدير', 'الهدف', 'التفاصيل'],
        rows: _activities.map((a) {
          final style = _getActionStyle(a);
          return [
            a['created_at']?.toString() ?? '',
            style.label,
            a['admin_username']?.toString() ?? '',
            a['target_name']?.toString() ?? '',
            a['action_description']?.toString() ?? '',
          ];
        }).toList(),
      );
    } catch (_) {
      if (mounted) AppSnackBar.error(context, 'فشل تصدير البيانات');
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    final managers = ref.watch(reportsProvider).managers;

    final totalPages = (_activities.length / _perPage).ceil();
    if (_page > totalPages && totalPages > 0) _page = totalPages;
    final paged = _activities.skip((_page - 1) * _perPage).take(_perPage).toList();

    return Column(
      children: [
        // Search + buttons
        Container(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Row(children: [
            Expanded(
              child: TextField(
                textDirection: TextDirection.ltr,
                textAlign: TextAlign.left,
                onChanged: (v) => _search = v,
                onSubmitted: (_) => _fetchActivities(),
                decoration: InputDecoration(
                  hintText: 'بحث في الحركات...',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.filter_list_rounded, size: 20),
                    onPressed: _showDateFilter,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            _SmallBtn(Icons.download_rounded, _exportCsv),
            const SizedBox(width: 4),
            _SmallBtn(Icons.refresh_rounded, _fetchActivities),
          ]),
        ),

        // Active filters indicator
        if (_managerId != 'all' || _activityType != 'all')
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
            child: Wrap(spacing: 6, children: [
              if (_managerId != 'all')
                Chip(
                  label: Text(managers.firstWhere((m) => m.id == _managerId, orElse: () => const ManagerOption(id: '', name: '?')).name,
                      style: const TextStyle(fontSize: 10)),
                  deleteIcon: const Icon(Icons.close, size: 14),
                  onDeleted: () { setState(() => _managerId = 'all'); _fetchActivities(); },
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              if (_activityType != 'all')
                Chip(
                  label: Text(_activityTypeOptions.firstWhere((o) => o['value'] == _activityType, orElse: () => {'label': _activityType})['label']!,
                      style: const TextStyle(fontSize: 10)),
                  deleteIcon: const Icon(Icons.close, size: 14),
                  onDeleted: () { setState(() => _activityType = 'all'); _fetchActivities(); },
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
            ]),
          ),

        // Pagination
        PaginationBar(
          totalItems: _activities.length,
          currentPage: _page,
          rowsPerPage: _perPage,
          itemLabel: 'حركة',
          onPageChanged: (p) => setState(() => _page = p),
          onRowsPerPageChanged: (r) => setState(() { _perPage = r; _page = 1; }),
        ),

        // List
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _activities.isEmpty
                  ? Center(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.assessment_outlined, size: 48,
                            color: theme.colorScheme.onSurface.withValues(alpha: .2)),
                        const SizedBox(height: 8),
                        Text('لا توجد حركات',
                            style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: .4))),
                      ]),
                    )
                  : RefreshIndicator(
                      onRefresh: _fetchActivities,
                      child: ListView.builder(
                        padding: const EdgeInsets.only(bottom: 80),
                        itemCount: paged.length,
                        itemBuilder: (ctx, i) => _ActivityRow(activity: paged[i]),
                      ),
                    ),
        ),
      ],
    );
  }

  static const _activityTypeOptions = [
    {'value': 'all', 'label': 'الكل'},
    {'value': 'users', 'label': 'حركات المشتركين'},
    {'value': 'managers', 'label': 'حركات المدراء'},
    {'value': 'payments', 'label': 'الحركات المالية'},
    {'value': 'system', 'label': 'حركات النظام'},
  ];

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
        String aType = _activityType;
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

                  // Quick date
                  _SectionLabel('فترة سريعة'),
                  const SizedBox(height: 6),
                  Wrap(spacing: 8, children: [
                    _qc('اليوم', () { final t = intl.DateFormat('yyyy-MM-dd').format(DateTime.now()); setSheet(() { from = t; to = t; }); }),
                    _qc('آخر 7 أيام', () { final n = DateTime.now(); setSheet(() { to = intl.DateFormat('yyyy-MM-dd').format(n); from = intl.DateFormat('yyyy-MM-dd').format(n.subtract(const Duration(days: 7))); }); }),
                    _qc('آخر 30 يوم', () { final n = DateTime.now(); setSheet(() { to = intl.DateFormat('yyyy-MM-dd').format(n); from = intl.DateFormat('yyyy-MM-dd').format(n.subtract(const Duration(days: 30))); }); }),
                  ]),
                  const SizedBox(height: 14),

                  // Activity type
                  _SectionLabel('نوع الحركة'),
                  const SizedBox(height: 6),
                  Wrap(spacing: 6, runSpacing: 6, children: _activityTypeOptions.map((opt) {
                    final sel = aType == opt['value'];
                    return FilterChip(
                      label: Text(opt['label']!, style: const TextStyle(fontSize: 11)),
                      selected: sel,
                      onSelected: (_) => setSheet(() => aType = opt['value']!),
                      selectedColor: AppTheme.primary.withValues(alpha: .15),
                      checkmarkColor: AppTheme.primary,
                      visualDensity: VisualDensity.compact,
                    );
                  }).toList()),
                  const SizedBox(height: 14),

                  // Manager
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
                          value: mgr,
                          isExpanded: true,
                          isDense: true,
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
                        _activityType = aType;
                        _page = 1;
                      });
                      _fetchActivities();
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

class _ActivityRow extends StatelessWidget {
  final Map<String, dynamic> activity;
  const _ActivityRow({required this.activity});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = _ActivityLogTabState._getActionStyle(activity);
    final desc = activity['action_description']?.toString() ?? '';
    final target = activity['target_name']?.toString() ?? '';
    final admin = activity['admin_username']?.toString() ?? '';
    final time = activity['created_at']?.toString() ?? '';

    String formattedTime = time;
    final dt = DateTime.tryParse(time);
    if (dt != null) formattedTime = intl.DateFormat('MM/dd HH:mm').format(dt.toLocal());

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: theme.colorScheme.onSurface.withValues(alpha: .05))),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(color: style.color.withValues(alpha: .1), borderRadius: BorderRadius.circular(10)),
            child: Icon(style.icon, size: 18, color: style.color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text(style.label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: style.color)),
                const Spacer(),
                Text(formattedTime, style: TextStyle(fontSize: 10, color: theme.colorScheme.onSurface.withValues(alpha: .4))),
              ]),
              if (target.isNotEmpty)
                Padding(padding: const EdgeInsets.only(top: 2),
                    child: Text(target, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                        color: theme.colorScheme.onSurface.withValues(alpha: .7)))),
              if (desc.isNotEmpty)
                Padding(padding: const EdgeInsets.only(top: 2),
                    child: Text(desc, style: TextStyle(fontSize: 10, color: theme.colorScheme.onSurface.withValues(alpha: .4)),
                        maxLines: 2, overflow: TextOverflow.ellipsis)),
              if (admin.isNotEmpty)
                Padding(padding: const EdgeInsets.only(top: 2),
                    child: Text('المدير: $admin', style: TextStyle(fontSize: 10, color: theme.colorScheme.primary.withValues(alpha: .6)))),
            ]),
          ),
        ],
      ),
    );
  }
}

class _ActionStyle {
  final String label;
  final IconData icon;
  final Color color;
  const _ActionStyle(this.label, this.icon, this.color);
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
  final IconData icon;
  final VoidCallback onTap;
  const _SmallBtn(this.icon, this.onTap);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: .3),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(padding: const EdgeInsets.all(8),
            child: Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary)),
      ),
    );
  }
}
