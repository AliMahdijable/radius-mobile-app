import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' as intl;
import '../../core/network/dio_client.dart';
import '../../core/theme/app_theme.dart';
import '../../core/services/storage_service.dart';

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

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _dateTo = intl.DateFormat('yyyy-MM-dd').format(now);
    _dateFrom =
        intl.DateFormat('yyyy-MM-dd').format(now.subtract(const Duration(days: 30)));
    Future.microtask(() => _fetchActivities());
  }

  Future<void> _fetchActivities() async {
    setState(() => _loading = true);
    try {
      final dio = ref.read(backendDioProvider);
      final storage = ref.read(storageServiceProvider);
      final adminId = await storage.getAdminId();

      final params = <String, dynamic>{
        'date_from': '$_dateFrom 00:00:00',
        'date_to': '$_dateTo 23:59:59',
        'limit': '500',
      };
      if (_search.isNotEmpty) params['search'] = _search;
      if (adminId != null) params['user_ids'] = adminId;

      final response =
          await dio.get('/api/activities', queryParameters: params);

      if (response.data?['data'] is List) {
        final list = (response.data['data'] as List)
            .where((log) {
              final action = log['action']?.toString() ?? '';
              final url = log['request_url']?.toString() ?? '';
              return !action.contains('verify-token') &&
                  !url.contains('verify-token');
            })
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        setState(() => _activities = list);
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
        return _ActionStyle(
            'تفعيل مشترك', Icons.check_circle_rounded, Colors.green);
      case 'SUBSCRIBER_EXTEND':
        return _ActionStyle(
            'تمديد مشترك', Icons.schedule_rounded, Colors.amber.shade700);
      case 'SUBSCRIBER_ADD':
        return _ActionStyle(
            'إضافة مشترك', Icons.person_add_rounded, Colors.blue);
      case 'SUBSCRIBER_EDIT':
        return _ActionStyle(
            'تعديل مشترك', Icons.edit_rounded, Colors.purple);
      case 'SUBSCRIBER_DELETE':
        return _ActionStyle(
            'حذف مشترك', Icons.person_remove_rounded, Colors.red);
      case 'BALANCE_ADD':
        return _ActionStyle(
            'إضافة دين', Icons.add_circle_rounded, Colors.red);
      case 'BALANCE_DEDUCT':
        return _ActionStyle(
            'تسديد دين', Icons.remove_circle_rounded, Colors.green);
      case 'PAYMENT_ADD':
      case 'DEBT_PAY':
        return _ActionStyle(
            'تسديد دين', Icons.account_balance_wallet_rounded, Colors.green);
      case 'LOGIN':
        return _ActionStyle(
            'تسجيل دخول', Icons.login_rounded, Colors.indigo);
      case 'WHATSAPP_SEND_MESSAGE':
        return _ActionStyle(
            'رسالة واتساب', Icons.chat_rounded, AppTheme.whatsappGreen);
      default:
        return _ActionStyle(
            type.isNotEmpty ? type : 'أخرى', Icons.settings_rounded, Colors.grey);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: TextField(
            onChanged: (v) => _search = v,
            onSubmitted: (_) => _fetchActivities(),
            decoration: InputDecoration(
              hintText: 'بحث في الحركات...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(
                icon: const Icon(Icons.filter_list_rounded),
                onPressed: _showDateFilter,
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(
            children: [
              Icon(Icons.date_range,
                  size: 14,
                  color: theme.colorScheme.onSurface.withValues(alpha: .4)),
              const SizedBox(width: 4),
              Text('$_dateFrom  —  $_dateTo',
                  style: TextStyle(
                      fontSize: 11,
                      color:
                          theme.colorScheme.onSurface.withValues(alpha: .5))),
              const Spacer(),
              Text('${_activities.length} حركة',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color:
                          theme.colorScheme.onSurface.withValues(alpha: .5))),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _activities.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.assessment_outlined,
                              size: 48,
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: .2)),
                          const SizedBox(height: 8),
                          Text('لا توجد حركات',
                              style: TextStyle(
                                  color: theme.colorScheme.onSurface
                                      .withValues(alpha: .4))),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _fetchActivities,
                      child: ListView.builder(
                        padding: const EdgeInsets.only(bottom: 80),
                        itemCount: _activities.length,
                        itemBuilder: (ctx, i) =>
                            _ActivityRow(activity: _activities[i]),
                      ),
                    ),
        ),
      ],
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
                  Row(children: [
                    Expanded(
                        child: _DateBtn(
                      label: 'من',
                      value: from,
                      onTap: () async {
                        final d = await showDatePicker(
                          context: ctx,
                          initialDate:
                              DateTime.tryParse(from) ?? DateTime.now(),
                          firstDate: DateTime(2020),
                          lastDate: DateTime.now(),
                        );
                        if (d != null) {
                          setSheet(() =>
                              from = intl.DateFormat('yyyy-MM-dd').format(d));
                        }
                      },
                    )),
                    const SizedBox(width: 12),
                    Expanded(
                        child: _DateBtn(
                      label: 'إلى',
                      value: to,
                      onTap: () async {
                        final d = await showDatePicker(
                          context: ctx,
                          initialDate:
                              DateTime.tryParse(to) ?? DateTime.now(),
                          firstDate: DateTime(2020),
                          lastDate:
                              DateTime.now().add(const Duration(days: 1)),
                        );
                        if (d != null) {
                          setSheet(() =>
                              to = intl.DateFormat('yyyy-MM-dd').format(d));
                        }
                      },
                    )),
                  ]),
                  const SizedBox(height: 8),
                  Wrap(spacing: 8, children: [
                    _QuickChip('اليوم', () {
                      final today = intl.DateFormat('yyyy-MM-dd')
                          .format(DateTime.now());
                      setSheet(() {
                        from = today;
                        to = today;
                      });
                    }),
                    _QuickChip('آخر 7 أيام', () {
                      final now = DateTime.now();
                      setSheet(() {
                        to = intl.DateFormat('yyyy-MM-dd').format(now);
                        from = intl.DateFormat('yyyy-MM-dd')
                            .format(now.subtract(const Duration(days: 7)));
                      });
                    }),
                    _QuickChip('آخر 30 يوم', () {
                      final now = DateTime.now();
                      setSheet(() {
                        to = intl.DateFormat('yyyy-MM-dd').format(now);
                        from = intl.DateFormat('yyyy-MM-dd')
                            .format(now.subtract(const Duration(days: 30)));
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
    if (dt != null) {
      formattedTime = intl.DateFormat('MM/dd HH:mm').format(dt.toLocal());
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        border: Border(
            bottom: BorderSide(
          color: theme.colorScheme.onSurface.withValues(alpha: .05),
        )),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: style.color.withValues(alpha: .1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(style.icon, size: 18, color: style.color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Text(style.label,
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: style.color)),
                  const Spacer(),
                  Text(formattedTime,
                      style: TextStyle(
                          fontSize: 10,
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: .4))),
                ]),
                if (target.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(target,
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: .7))),
                  ),
                if (desc.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(desc,
                        style: TextStyle(
                            fontSize: 10,
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: .4)),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                  ),
                if (admin.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text('المدير: $admin',
                        style: TextStyle(
                            fontSize: 10,
                            color:
                                theme.colorScheme.primary.withValues(alpha: .6))),
                  ),
              ],
            ),
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

class _DateBtn extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback onTap;
  const _DateBtn(
      {required this.label, required this.value, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color:
                  Theme.of(context).colorScheme.outline.withValues(alpha: .3)),
        ),
        child: Row(children: [
          Icon(Icons.calendar_today,
              size: 14, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 6),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: TextStyle(
                      fontSize: 10,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: .5))),
              Text(value,
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600)),
            ],
          ),
        ]),
      ),
    );
  }
}

class _QuickChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _QuickChip(this.label, this.onTap);

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      label: Text(label, style: const TextStyle(fontSize: 11)),
      onPressed: onTap,
      visualDensity: VisualDensity.compact,
    );
  }
}
