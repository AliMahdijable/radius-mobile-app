import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' as intl;
import '../../core/theme/app_theme.dart';
import '../../core/utils/helpers.dart';
import '../../core/utils/pdf_statement.dart';
import '../../providers/reports_provider.dart';
import '../../providers/whatsapp_provider.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/report_controls.dart';

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
  int _txnPage = 1;
  int _txnPerPage = 10;

  final Set<String> _selectedActionTypes = {
    'SUBSCRIBER_ACTIVATE',
    'SUBSCRIBER_EXTEND',
    'BALANCE_DEDUCT',
    'BALANCE_ADD',
  };

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
    await _reload();
  }

  Future<void> _reload() async {
    if (_selectedSub == null) return;
    await ref.read(reportsProvider.notifier).fetchAccountStatement(
          username: _selectedSub!['username']?.toString() ?? '',
          userId:
              (_selectedSub!['id'] ?? _selectedSub!['idx'] ?? '').toString(),
          dateFrom: _dateFrom,
          dateTo: _dateTo,
          actionTypes: _selectedActionTypes.toList(),
        );
  }

  double _num(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0;
    return 0;
  }

  // ── PDF Share ──────────────────────────────────────────────────────
  Future<void> _handleSharePdf() async {
    final state = ref.read(reportsProvider);
    if (state.transactions.isEmpty) {
      AppSnackBar.warning(context, 'لا توجد بيانات');
      return;
    }
    try {
      final sub = state.subscriberInfo ?? _selectedSub ?? {};
      await PdfStatement.generateAndShare(
        username: sub['username']?.toString() ?? '',
        phone: sub['phone']?.toString() ?? '',
        profileName: sub['profile_name']?.toString() ?? '',
        dateFrom: _dateFrom,
        dateTo: _dateTo,
        transactions: state.transactions,
        summary: state.statementSummary,
      );
    } catch (_) {
      if (mounted) AppSnackBar.error(context, 'فشل إنشاء الملف');
    }
  }

  // ── PDF Print ──────────────────────────────────────────────────────
  Future<void> _handlePrint() async {
    final state = ref.read(reportsProvider);
    if (state.transactions.isEmpty) {
      AppSnackBar.warning(context, 'لا توجد بيانات للطباعة');
      return;
    }
    try {
      final sub = state.subscriberInfo ?? _selectedSub ?? {};
      await PdfStatement.printStatement(
        username: sub['username']?.toString() ?? '',
        phone: sub['phone']?.toString() ?? '',
        profileName: sub['profile_name']?.toString() ?? '',
        dateFrom: _dateFrom,
        dateTo: _dateTo,
        transactions: state.transactions,
        summary: state.statementSummary,
      );
    } catch (_) {
      if (mounted) AppSnackBar.error(context, 'فشل الطباعة');
    }
  }

  // ── WhatsApp send (PDF) ──────────────────────────────────────────
  bool _waSending = false;
  Future<void> _handleSendWhatsApp() async {
    final state = ref.read(reportsProvider);
    if (_selectedSub == null || state.transactions.isEmpty) {
      AppSnackBar.warning(context, 'لا توجد بيانات للإرسال');
      return;
    }

    final waState = ref.read(whatsappProvider);
    if (!waState.status.connected) {
      AppSnackBar.error(context, 'واتساب غير متصل');
      return;
    }

    final sub = state.subscriberInfo ?? _selectedSub ?? {};
    final rawPhone = sub['phone']?.toString() ?? _selectedSub!['phone']?.toString() ?? '';
    if (rawPhone.isEmpty) {
      AppSnackBar.error(context, 'لا يوجد رقم هاتف للمشترك');
      return;
    }

    setState(() => _waSending = true);
    try {
      final username = sub['username']?.toString() ?? '';
      final profileName = sub['profile_name']?.toString() ?? '';
      final phone = PdfStatement.formatPhoneForWa(rawPhone);

      final pdfBytes = await PdfStatement.buildPdfBytes(
        username: username,
        phone: rawPhone,
        profileName: profileName,
        dateFrom: _dateFrom,
        dateTo: _dateTo,
        transactions: state.transactions,
        summary: state.statementSummary,
      );

      final base64Pdf = base64Encode(pdfBytes);
      final caption =
          '📋 *كشف حساب المشترك*\n\n'
          '👤 المشترك: $username\n'
          '📅 الفترة: $_dateFrom — $_dateTo\n'
          '📊 عدد الحركات: ${state.transactions.length}\n'
          '💰 الدين الحالي: ${AppHelpers.formatMoney(double.tryParse(state.statementSummary['totalDebt']?.toString() ?? '0') ?? 0)}';

      final result = await ref.read(whatsappProvider.notifier).sendMedia(
        to: phone,
        base64Data: base64Pdf,
        mimetype: 'application/pdf',
        filename: 'account-statement-$username.pdf',
        caption: caption,
      );

      if (!mounted) return;
      if (result.success) {
        AppSnackBar.whatsapp(context, 'تم إرسال كشف الحساب عبر واتساب');
      } else {
        AppSnackBar.whatsappError(context, 'فشل إرسال كشف الحساب', detail: result.error);
      }
    } catch (e) {
      if (mounted) AppSnackBar.error(context, 'فشل إنشاء ملف PDF', detail: e.toString());
    } finally {
      if (mounted) setState(() => _waSending = false);
    }
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

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final state = ref.watch(reportsProvider);
    final theme = Theme.of(context);
    final hasData = _selectedSub != null && state.transactions.isNotEmpty;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Action buttons
        Row(children: [
          Expanded(
            child: TextField(
              controller: _searchCtrl,
              textDirection: TextDirection.ltr,
              textAlign: TextAlign.left,
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                hintText: 'بحث عن مشترك...',
                prefixIcon: const Icon(Icons.person_search_rounded, size: 20),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                suffixIcon: _selectedSub != null
                    ? IconButton(
                        icon: const Icon(Icons.close, size: 16),
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
          ),
          const SizedBox(width: 6),
          _SmallBtn(
            Icons.picture_as_pdf_rounded,
            hasData ? _handleSharePdf : null,
            tooltip: 'مشاركة PDF',
          ),
          const SizedBox(width: 4),
          _SmallBtn(
            Icons.print_rounded,
            hasData ? _handlePrint : null,
            tooltip: 'طباعة',
          ),
          const SizedBox(width: 4),
          _waSending
              ? const SizedBox(width: 32, height: 32,
                  child: Padding(padding: EdgeInsets.all(6),
                    child: CircularProgressIndicator(strokeWidth: 2)))
              : _SmallBtn(
                  Icons.send_rounded,
                  hasData ? _handleSendWhatsApp : null,
                  color: const Color(0xFF25D366),
                  tooltip: 'إرسال واتساب',
                ),
        ]),

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

          // Date + action type filter
          GestureDetector(
            onTap: _showFilterSheet,
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
                    size: 14, color: theme.colorScheme.primary),
                const SizedBox(width: 4),
                Expanded(
                  child: Text('$_dateFrom — $_dateTo',
                      style: const TextStyle(fontSize: 11),
                      overflow: TextOverflow.ellipsis),
                ),
                Icon(Icons.filter_list_rounded,
                    size: 14,
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
            else ...[
              PaginationBar(
                totalItems: state.transactions.length,
                currentPage: _txnPage,
                rowsPerPage: _txnPerPage,
                itemLabel: 'عملية',
                onPageChanged: (p) => setState(() => _txnPage = p),
                onRowsPerPageChanged: (r) => setState(() { _txnPerPage = r; _txnPage = 1; }),
              ),
              const SizedBox(height: 4),
              ...state.transactions
                  .skip((_txnPage - 1) * _txnPerPage)
                  .take(_txnPerPage)
                  .map((t) => _TransactionRow(txn: t)),
            ],
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

  void _showFilterSheet() {
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
        final types = Set<String>.from(_selectedActionTypes);

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
                          width: 40, height: 4,
                          decoration: BoxDecoration(
                              color: Colors.grey.shade300,
                              borderRadius: BorderRadius.circular(2)))),
                  const SizedBox(height: 16),
                  Text('الفلاتر',
                      style: Theme.of(ctx)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 12),

                  // Quick date ranges
                  Text('فترة سريعة',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                          color: Theme.of(ctx).colorScheme.onSurface.withValues(alpha: .6))),
                  const SizedBox(height: 6),
                  Wrap(spacing: 8, children: [
                    _QuickChip('آخر 7 أيام', () {
                      final now = DateTime.now();
                      setSheet(() {
                        to = intl.DateFormat('yyyy-MM-dd').format(now);
                        from = intl.DateFormat('yyyy-MM-dd').format(
                            now.subtract(const Duration(days: 7)));
                      });
                    }),
                    _QuickChip('آخر 30 يوم', () {
                      final now = DateTime.now();
                      setSheet(() {
                        to = intl.DateFormat('yyyy-MM-dd').format(now);
                        from = intl.DateFormat('yyyy-MM-dd').format(
                            now.subtract(const Duration(days: 30)));
                      });
                    }),
                    _QuickChip('آخر 3 أشهر', () {
                      final now = DateTime.now();
                      setSheet(() {
                        to = intl.DateFormat('yyyy-MM-dd').format(now);
                        from = intl.DateFormat('yyyy-MM-dd').format(
                            now.subtract(const Duration(days: 90)));
                      });
                    }),
                  ]),
                  const SizedBox(height: 14),

                  // Action type filter
                  Text('نوع الحركة',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                          color: Theme.of(ctx).colorScheme.onSurface.withValues(alpha: .6))),
                  const SizedBox(height: 6),
                  Wrap(spacing: 6, runSpacing: 6, children: [
                    _TypeChip('تفعيل', 'SUBSCRIBER_ACTIVATE', types, setSheet),
                    _TypeChip('تمديد', 'SUBSCRIBER_EXTEND', types, setSheet),
                    _TypeChip('تسديد دين', 'BALANCE_DEDUCT', types, setSheet),
                    _TypeChip('إضافة دين', 'BALANCE_ADD', types, setSheet),
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
                            _selectedActionTypes
                              ..clear()
                              ..addAll(types);
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

class _TypeChip extends StatelessWidget {
  final String label;
  final String type;
  final Set<String> selected;
  final StateSetter setSheet;
  const _TypeChip(this.label, this.type, this.selected, this.setSheet);

  @override
  Widget build(BuildContext context) {
    final active = selected.contains(type);
    return FilterChip(
      label: Text(label, style: const TextStyle(fontSize: 11)),
      selected: active,
      onSelected: (v) {
        setSheet(() {
          if (v) {
            selected.add(type);
          } else {
            selected.remove(type);
          }
        });
      },
      visualDensity: VisualDensity.compact,
      selectedColor: AppTheme.primary.withValues(alpha: .15),
      checkmarkColor: AppTheme.primary,
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
    final desc = AppHelpers.formatNumbersInText(
        txn['description']?.toString() ??
        txn['action_description']?.toString() ??
        '');
    final admin = txn['admin_name']?.toString() ?? '';
    final time = txn['created_at']?.toString() ?? '';
    final rawAmt = txn['amount'];
    final amount = (rawAmt is num)
        ? rawAmt.toDouble().abs()
        : double.tryParse((rawAmt?.toString() ?? '').replaceAll(RegExp(r'[^0-9.\-]'), ''))?.abs() ?? 0;

    final isDebt = type == 'BALANCE_ADD' ||
        (type == 'SUBSCRIBER_ACTIVATE' &&
            desc.toLowerCase().contains('غير نقدي'));

    String formattedTime = '';
    final dt = DateTime.tryParse(time);
    if (dt != null) {
      formattedTime = intl.DateFormat('MM/dd HH:mm').format(dt.toLocal());
    }

    String typeLabel = _typeLabelStatic(type);

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

  static String _typeLabelStatic(String type) {
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

class _SmallBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final Color? color;
  final String? tooltip;
  const _SmallBtn(this.icon, this.onTap, {this.color, this.tooltip});

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final c = color ?? Theme.of(context).colorScheme.primary;
    final btn = Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest
          .withValues(alpha: enabled ? .3 : .15),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(icon, size: 18,
              color: enabled
                  ? c
                  : Theme.of(context).colorScheme.onSurface.withValues(alpha: .2)),
        ),
      ),
    );
    if (tooltip != null) return Tooltip(message: tooltip!, child: btn);
    return btn;
  }
}

