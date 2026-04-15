import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' as intl;
import '../../core/theme/app_theme.dart';
import '../../core/utils/helpers.dart';
import '../../providers/reports_provider.dart';

class AccountStatementTab extends ConsumerStatefulWidget {
  const AccountStatementTab({super.key});

  @override
  ConsumerState<AccountStatementTab> createState() =>
      _AccountStatementTabState();
}

class _AccountStatementTabState extends ConsumerState<AccountStatementTab>
    with AutomaticKeepAliveClientMixin {
  final _searchCtrl = TextEditingController();
  List<Map<String, dynamic>> _searchResults = [];
  bool _searchLoading = false;
  Map<String, dynamic>? _selectedSub;
  Timer? _debounce;

  late String _dateFrom;
  late String _dateTo;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _dateTo = intl.DateFormat('yyyy-MM-dd').format(now);
    _dateFrom = intl.DateFormat('yyyy-MM-dd')
        .format(now.subtract(const Duration(days: 30)));
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      _doSearch(query);
    });
  }

  Future<void> _doSearch(String query) async {
    if (query.length < 2) {
      setState(() => _searchResults = []);
      return;
    }
    setState(() => _searchLoading = true);
    final results =
        await ref.read(reportsProvider.notifier).searchSubscribers(query);
    if (mounted) {
      setState(() {
        _searchResults = results;
        _searchLoading = false;
      });
    }
  }

  Future<void> _selectSubscriber(Map<String, dynamic> sub) async {
    setState(() {
      _selectedSub = sub;
      _searchResults = [];
      _searchCtrl.text = sub['username']?.toString() ?? '';
    });

    await ref.read(reportsProvider.notifier).fetchAccountStatement(
          username: sub['username']?.toString() ?? '',
          userId: (sub['id'] ?? sub['idx'] ?? '').toString(),
          dateFrom: _dateFrom,
          dateTo: _dateTo,
        );
  }

  Future<void> _reload() async {
    if (_selectedSub == null) return;
    await ref.read(reportsProvider.notifier).fetchAccountStatement(
          username: _selectedSub!['username']?.toString() ?? '',
          userId:
              (_selectedSub!['id'] ?? _selectedSub!['idx'] ?? '').toString(),
          dateFrom: _dateFrom,
          dateTo: _dateTo,
        );
  }

  double _num(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final state = ref.watch(reportsProvider);
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Search subscriber
        TextField(
          controller: _searchCtrl,
          textDirection: TextDirection.ltr,
          textAlign: TextAlign.left,
          onChanged: _onSearchChanged,
          decoration: InputDecoration(
            hintText: 'بحث عن مشترك (اسم مستخدم / هاتف)...',
            prefixIcon: const Icon(Icons.person_search_rounded),
            suffixIcon: _selectedSub != null
                ? IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () {
                      _searchCtrl.clear();
                      ref.read(reportsProvider.notifier).clearStatement();
                      setState(() {
                        _selectedSub = null;
                        _searchResults = [];
                      });
                    },
                  )
                : null,
          ),
        ),

        // Search dropdown
        if (_searchLoading)
          const Padding(
            padding: EdgeInsets.all(12),
            child: Center(
                child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))),
          )
        else if (_searchResults.isNotEmpty)
          Container(
            constraints: const BoxConstraints(maxHeight: 200),
            margin: const EdgeInsets.only(top: 4),
            decoration: BoxDecoration(
              color: theme.cardTheme.color ?? Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color:
                      theme.colorScheme.onSurface.withValues(alpha: .1)),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withValues(alpha: .08),
                    blurRadius: 8,
                    offset: const Offset(0, 4)),
              ],
            ),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _searchResults.length,
              itemBuilder: (ctx, i) {
                final sub = _searchResults[i];
                final name =
                    '${sub['firstname'] ?? ''} ${sub['lastname'] ?? ''}'
                        .trim();
                final username = sub['username']?.toString() ?? '';
                return ListTile(
                  dense: true,
                  title: Text(name.isNotEmpty ? name : username,
                      style: const TextStyle(fontSize: 13)),
                  subtitle: Text(username,
                      style: TextStyle(
                          fontSize: 11,
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: .5))),
                  leading: CircleAvatar(
                    radius: 16,
                    backgroundColor: AppTheme.primary.withValues(alpha: .1),
                    child: Icon(Icons.person,
                        size: 16, color: AppTheme.primary),
                  ),
                  onTap: () => _selectSubscriber(sub),
                );
              },
            ),
          ),

        if (_selectedSub != null) ...[
          const SizedBox(height: 12),

          // Date filter
          GestureDetector(
            onTap: _showDateFilter,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                    color: theme.colorScheme.onSurface
                        .withValues(alpha: .4)),
              ]),
            ),
          ),
          const SizedBox(height: 12),

          if (state.loading)
            const Center(
                child: Padding(
                    padding: EdgeInsets.all(40),
                    child: CircularProgressIndicator()))
          else ...[
            // Summary cards
            Row(children: [
              _SummaryCard('العمليات',
                  '${_num(state.statementSummary['totalTransactions']).toInt()}',
                  AppTheme.primary),
              const SizedBox(width: 8),
              _SummaryCard('الديون',
                  AppHelpers.formatMoney(_num(state.statementSummary['totalDebt'])),
                  Colors.red),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              _SummaryCard('المدفوعات',
                  AppHelpers.formatMoney(_num(state.statementSummary['totalPayments'])),
                  Colors.green),
              const SizedBox(width: 8),
              _SummaryCard('التفعيلات',
                  '${_num(state.statementSummary['totalActivations']).toInt()}',
                  AppTheme.warningColor),
            ]),
            const SizedBox(height: 16),

            // Transactions
            if (state.transactions.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 40),
                child: Column(children: [
                  Icon(Icons.receipt_long_rounded,
                      size: 48,
                      color: theme.colorScheme.onSurface
                          .withValues(alpha: .2)),
                  const SizedBox(height: 8),
                  Text('لا توجد عمليات',
                      style: TextStyle(
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: .4))),
                ]),
              )
            else
              ...state.transactions.map((t) => _TransactionRow(txn: t)),
          ],
        ] else ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 80),
            child: Column(children: [
              Icon(Icons.person_search_rounded,
                  size: 56,
                  color:
                      theme.colorScheme.onSurface.withValues(alpha: .15)),
              const SizedBox(height: 12),
              Text('ابحث عن مشترك لعرض كشف الحساب',
                  style: TextStyle(
                      color: theme.colorScheme.onSurface
                          .withValues(alpha: .4))),
            ]),
          ),
        ],
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
                  Wrap(spacing: 8, children: [
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
                    ActionChip(
                        label: const Text('آخر 3 أشهر',
                            style: TextStyle(fontSize: 11)),
                        onPressed: () {
                          final now = DateTime.now();
                          setSheet(() {
                            to = intl.DateFormat('yyyy-MM-dd').format(now);
                            from = intl.DateFormat('yyyy-MM-dd').format(
                                now.subtract(const Duration(days: 90)));
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
                          _reload();
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

class _SummaryCard extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _SummaryCard(this.label, this.value, this.color);

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: .15)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: TextStyle(
                    fontSize: 10, color: color.withValues(alpha: .7))),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: Text(value,
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: color)),
            ),
          ],
        ),
      ),
    );
  }
}

class _TransactionRow extends StatelessWidget {
  final Map<String, dynamic> txn;
  const _TransactionRow({required this.txn});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final type = (txn['action_type'] ?? '').toString().toUpperCase();
    final desc = txn['description']?.toString() ??
        txn['action_description']?.toString() ??
        '';
    final notes = txn['notes']?.toString() ?? '';
    final admin = txn['admin_name']?.toString() ?? '';
    final time = txn['created_at']?.toString() ?? '';
    final amount = (txn['amount'] is num)
        ? (txn['amount'] as num).toDouble().abs()
        : double.tryParse(txn['amount']?.toString() ?? '')?.abs() ?? 0;

    final isDebt = type == 'BALANCE_ADD' ||
        (type == 'SUBSCRIBER_ACTIVATE' &&
            desc.toLowerCase().contains('غير نقدي'));

    String formattedTime = '';
    final dt = DateTime.tryParse(time);
    if (dt != null) {
      formattedTime = intl.DateFormat('MM/dd HH:mm').format(dt.toLocal());
    }

    String typeLabel = _typeLabel(type);

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.cardTheme.color ?? Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: theme.colorScheme.onSurface.withValues(alpha: .06)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: (isDebt ? Colors.red : Colors.green)
                          .withValues(alpha: .1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(typeLabel,
                        style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: isDebt ? Colors.red : Colors.green)),
                  ),
                  const Spacer(),
                  Text(formattedTime,
                      style: TextStyle(
                          fontSize: 10,
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: .4))),
                ]),
                if (desc.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(desc,
                        style: const TextStyle(fontSize: 11),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                  ),
                if (admin.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text('المنفذ: $admin',
                        style: TextStyle(
                            fontSize: 10,
                            color: theme.colorScheme.primary
                                .withValues(alpha: .5))),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            '${isDebt ? "-" : "+"}${AppHelpers.formatMoney(amount)}',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: isDebt ? Colors.red : Colors.green,
            ),
          ),
        ],
      ),
    );
  }

  String _typeLabel(String type) {
    switch (type) {
      case 'SUBSCRIBER_ACTIVATE':
        return 'تفعيل';
      case 'SUBSCRIBER_EXTEND':
        return 'تمديد';
      case 'BALANCE_DEDUCT':
        return 'تسديد دين';
      case 'BALANCE_ADD':
        return 'إضافة دين';
      default:
        return type;
    }
  }
}
