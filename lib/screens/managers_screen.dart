import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' as intl;

import '../core/theme/app_theme.dart';
import '../core/utils/bottom_sheet_utils.dart';
import '../models/manager_model.dart';
import '../providers/auth_provider.dart';
import '../providers/managers_provider.dart';
import '../providers/whatsapp_provider.dart';
import '../widgets/app_snackbar.dart';
import '../widgets/loading_overlay.dart';

enum _ManagerActionType {
  edit,
  deposit,
  withdraw,
  payDebt,
  addPoints,
  delete,
}

enum _ManagerBalanceActionType { deposit, withdraw }

enum _ManagerFinancialNoticeKind { cashDeposit, loanDeposit, debtPayment }

class _ManagerFinancialNoticeData {
  final ManagerModel manager;
  final double amount;
  final _ManagerFinancialNoticeKind kind;
  final String notes;
  final double previousCredit;
  final double previousDebt;
  final double currentCredit;
  final double currentDebt;

  const _ManagerFinancialNoticeData({
    required this.manager,
    required this.amount,
    required this.kind,
    required this.notes,
    required this.previousCredit,
    required this.previousDebt,
    required this.currentCredit,
    required this.currentDebt,
  });

  bool get isLoanDeposit => kind == _ManagerFinancialNoticeKind.loanDeposit;
  bool get isDebtPayment => kind == _ManagerFinancialNoticeKind.debtPayment;

  bool get hasPreviousCredit => previousCredit > 0;
  bool get hasPreviousDebt => previousDebt > 0;

  String get pushActionKind {
    switch (kind) {
      case _ManagerFinancialNoticeKind.cashDeposit:
        return 'cash_deposit';
      case _ManagerFinancialNoticeKind.loanDeposit:
        return 'loan_deposit';
      case _ManagerFinancialNoticeKind.debtPayment:
        return 'debt_payment';
    }
  }

  String get movementDescription =>
      notes.trim().isNotEmpty
          ? notes.trim()
          : switch (kind) {
              _ManagerFinancialNoticeKind.cashDeposit => 'إضافة رصيد نقدي',
              _ManagerFinancialNoticeKind.loanDeposit => 'إضافة رصيد آجل',
              _ManagerFinancialNoticeKind.debtPayment => 'تسديد دين مدير',
            };

  String get previewMessage {
    final managerName =
        manager.fullName.isNotEmpty ? manager.fullName : manager.username;

    switch (kind) {
      case _ManagerFinancialNoticeKind.cashDeposit:
      case _ManagerFinancialNoticeKind.loanDeposit:
        final lines = <String>[
          'عزيزي المدير $managerName،',
          '',
          'تم إيداع مبلغ في حسابك قدره: ${_formatCurrency(amount)}',
          'حالة الحساب: ${isLoanDeposit ? 'دين' : 'نقدي'}',
          if (hasPreviousCredit)
            'الرصيد السابق: ${_formatCurrency(previousCredit)}',
          'إجمالي الرصيد بعد العملية: ${_formatCurrency(currentCredit)}',
          if (hasPreviousDebt) 'ديون سابقة: ${_formatCurrency(previousDebt)}',
          if (isLoanDeposit)
            'إجمالي الدين بعد العملية: ${_formatCurrency(currentDebt)}',
          'وصف الحركة: $movementDescription',
        ];
        return lines.join('\n');
      case _ManagerFinancialNoticeKind.debtPayment:
        final lines = <String>[
          'عزيزي المدير $managerName،',
          '',
          'تم تسديد مبلغ من دينك قدره: ${_formatCurrency(amount)}',
          if (hasPreviousDebt) 'الديون السابقة: ${_formatCurrency(previousDebt)}',
          'إجمالي الدين بعد التسديد: ${_formatCurrency(currentDebt)}',
          'وصف الحركة: $movementDescription',
        ];
        return lines.join('\n');
    }
  }
}

Future<({bool success, String? error})> _sendManagerWhatsAppNotification({
  required WidgetRef ref,
  required ManagerModel manager,
  required String message,
}) async {
  final phone = manager.mobile.trim();
  if (phone.isEmpty) {
    return (success: false, error: 'لا يوجد رقم هاتف محفوظ لهذا المدير');
  }

  try {
    var waState = ref.read(whatsappProvider);
    if (!waState.status.connected) {
      await ref.read(whatsappProvider.notifier).reconnect();
      await Future.delayed(const Duration(seconds: 3));
      await ref.read(whatsappProvider.notifier).fetchStatus();
      waState = ref.read(whatsappProvider);
      if (!waState.status.connected) {
        return (
          success: false,
          error: 'واتساب غير متصل. يرجى الاتصال به أولًا من الإعدادات.',
        );
      }
    }

    return ref.read(whatsappProvider.notifier).sendMessage(phone, message);
  } catch (_) {
    return (success: false, error: 'حدث خطأ غير متوقع أثناء إرسال واتساب');
  }
}

Future<void> _showManagerFinancialNoticeDialog({
  required BuildContext context,
  required WidgetRef ref,
  required _ManagerFinancialNoticeData notice,
}) async {
  var sendingWhatsApp = false;
  var sendingPush = false;
  var whatsappSent = false;
  var pushSent = false;

  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          final canSendWhatsApp = notice.manager.mobile.trim().isNotEmpty;

          return AlertDialog(
            titlePadding: const EdgeInsets.fromLTRB(18, 16, 18, 0),
            contentPadding: const EdgeInsets.fromLTRB(18, 10, 18, 8),
            actionsPadding: const EdgeInsets.fromLTRB(18, 0, 18, 14),
            title: Row(
              children: [
                Icon(
                  Icons.mark_chat_read_rounded,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'إشعار المدير الفرعي',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: 360,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'تم تنفيذ الحركة بنجاح. هل تريد إرسال الإشعار الآن؟',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          height: 1.35,
                        ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'معاينة الرسالة',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    width: double.infinity,
                    constraints: BoxConstraints(
                      maxHeight:
                          MediaQuery.of(dialogContext).size.height * 0.28,
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .surfaceContainerLowest,
                      border: Border.all(
                        color: Theme.of(context)
                            .colorScheme
                            .outline
                            .withValues(alpha: 0.18),
                      ),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: SingleChildScrollView(
                      child: SelectableText(
                        notice.previewMessage,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              height: 1.5,
                              fontSize: 12.5,
                            ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (!canSendWhatsApp)
                    const _InlineInfoBanner(
                      color: AppTheme.warningColor,
                      icon: Icons.phone_disabled_outlined,
                      text: 'لا يمكن إرسال واتساب لأن رقم هاتف المدير غير محفوظ.',
                    )
                  else
                    const SizedBox.shrink(),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: !canSendWhatsApp || sendingWhatsApp || whatsappSent
                          ? null
                          : () async {
                              setDialogState(() => sendingWhatsApp = true);
                              final result =
                                  await _sendManagerWhatsAppNotification(
                                ref: ref,
                                manager: notice.manager,
                                message: notice.previewMessage,
                              );
                              if (!context.mounted) return;
                              setDialogState(() {
                                sendingWhatsApp = false;
                                whatsappSent = result.success;
                              });
                              if (result.success) {
                                AppSnackBar.whatsapp(
                                  context,
                                  'تم إرسال الرسالة إلى المدير',
                                );
                              } else {
                                AppSnackBar.whatsappError(
                                  context,
                                  'فشل إرسال الرسالة',
                                  detail: result.error,
                                );
                              }
                            },
                      icon: sendingWhatsApp
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Icon(
                              whatsappSent
                                  ? Icons.check_circle_rounded
                                  : Icons.message_outlined,
                            ),
                      label: Text(
                        whatsappSent
                            ? 'تم إرسال واتساب'
                            : 'إرسال واتساب للمدير',
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: sendingPush || pushSent
                          ? null
                          : () async {
                              setDialogState(() => sendingPush = true);
                              final result = await ref
                                  .read(managersProvider.notifier)
                                  .sendManagerBalanceUpdateNotification(
                                    manager: notice.manager,
                                    amount: notice.amount,
                                    isLoan: notice.isLoanDeposit,
                                    previousCredit: notice.previousCredit,
                                    previousDebt: notice.previousDebt,
                                    currentCredit: notice.currentCredit,
                                    currentDebt: notice.currentDebt,
                                    actionKind: notice.pushActionKind,
                                    notes: notice.notes,
                                  );
                              if (!context.mounted) return;
                              setDialogState(() {
                                sendingPush = false;
                                pushSent = result.$1;
                              });
                              if (result.$1) {
                                AppSnackBar.success(
                                  context,
                                  result.$2 ?? 'تم إرسال إشعار التطبيق',
                                );
                              } else {
                                AppSnackBar.warning(
                                  context,
                                  result.$2 ??
                                      'المدير لم يفعّل إشعارات التطبيق بعد',
                                );
                              }
                            },
                      icon: sendingPush
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                              ),
                            )
                          : Icon(
                              pushSent
                                  ? Icons.notifications_active_rounded
                                  : Icons.notifications_outlined,
                            ),
                      label: Text(
                        pushSent
                            ? 'تم إرسال إشعار التطبيق'
                            : 'إرسال إشعار التطبيق',
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'إشعار التطبيق يصل فقط إذا كان المدير قد سجّل الدخول في الهاتف وفعّل إشعارات الجهاز.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.65),
                          height: 1.4,
                          fontSize: 11,
                        ),
                  ),
                ],
              ),
            ),
            actions: [
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('إنهاء'),
                ),
              ),
            ],
          );
        },
      );
    },
  );
}

class ManagersScreen extends ConsumerStatefulWidget {
  const ManagersScreen({super.key});

  @override
  ConsumerState<ManagersScreen> createState() => _ManagersScreenState();
}

class _ManagersScreenState extends ConsumerState<ManagersScreen> {
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;
  int? _selectedManagerId;
  bool _showAdvancedFilters = false;
  static const List<(String value, String label, String shortLabel)> _sortItems = [
    ('username', 'اسم المستخدم', 'المستخدم'),
    ('firstname', 'الاسم الأول', 'الأول'),
    ('lastname', 'الاسم الأخير', 'الأخير'),
    ('balance', 'الرصيد', 'الرصيد'),
    ('users_count', 'عدد المشتركين', 'المشتركون'),
  ];

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final canAccessManagers =
          ref.read(authProvider).user?.canAccessManagers ?? false;
      if (!canAccessManagers) return;
      final state = ref.read(managersProvider);
      _searchController.text = state.search;
      _reloadManagers();
    });
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _reloadManagers({
    int? page,
    int? rowsPerPage,
    String? search,
    String? sortBy,
    String? direction,
  }) async {
    final canAccessManagers =
        ref.read(authProvider).user?.canAccessManagers ?? false;
    if (!canAccessManagers) return;
    await ref.read(managersProvider.notifier).loadManagers(
          page: page,
          rowsPerPage: rowsPerPage,
          search: search,
          sortBy: sortBy,
          direction: direction,
        );
    if (!mounted) return;
    final ids = ref.read(managersProvider).managers.map((e) => e.id).toSet();
    if (_selectedManagerId != null && !ids.contains(_selectedManagerId)) {
      setState(() => _selectedManagerId = null);
    }
  }

  void _handleSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      _reloadManagers(page: 1, search: value.trim());
    });
  }

  int _totalPages(ManagersState state) {
    if (state.totalCount <= 0) return 1;
    return (state.totalCount / state.rowsPerPage).ceil();
  }

  List<DropdownMenuItem<String>> _buildSortMenuItems() {
    return _sortItems
        .map(
          (item) => DropdownMenuItem<String>(
            value: item.$1,
            child: Text(
              item.$2,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        )
        .toList();
  }

  List<Widget> _buildSortSelectedItems(bool compact) {
    return _sortItems
        .map(
          (item) => Align(
            alignment: Alignment.centerRight,
            child: Text(
              compact ? item.$3 : item.$2,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        )
        .toList();
  }

  String _labelForSort(String value, {bool compact = false}) {
    for (final item in _sortItems) {
      if (item.$1 == value) {
        return compact ? item.$3 : item.$2;
      }
    }
    return value;
  }

  Future<void> _openManagerForm({ManagerModel? manager}) async {
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _ManagerFormSheet(manager: manager),
    );

    if (created == true && mounted) {
      AppSnackBar.success(
        context,
        manager == null ? 'تم إضافة المدير بنجاح' : 'تم تحديث بيانات المدير',
      );
      await _reloadManagers();
    }
  }

  Future<void> _openBalanceSheet(
    ManagerModel manager,
    _ManagerBalanceActionType action,
  ) async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _ManagerBalanceSheet(manager: manager, action: action),
    );

    if (changed == true && mounted) {
      AppSnackBar.success(
        context,
        action == _ManagerBalanceActionType.deposit
            ? 'تم تنفيذ إضافة الرصيد'
            : 'تم تنفيذ سحب الرصيد',
      );
      await _reloadManagers();
    }
  }

  Future<void> _openDebtSheet(ManagerModel manager) async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _ManagerDebtPaymentSheet(manager: manager),
    );

    if (changed == true && mounted) {
      AppSnackBar.success(context, 'تم تسديد الدين بنجاح');
      await _reloadManagers();
    }
  }

  Future<void> _openPointsSheet(ManagerModel manager) async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _ManagerPointsSheet(manager: manager),
    );

    if (changed == true && mounted) {
      AppSnackBar.success(context, 'تمت إضافة النقاط بنجاح');
      await _reloadManagers();
    }
  }

  Future<void> _confirmDeleteManager(ManagerModel manager) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => _DeleteManagerDialog(manager: manager),
    );

    if (result == true && mounted) {
      setState(() => _selectedManagerId = null);
      AppSnackBar.success(context, 'تم حذف المدير بنجاح');
      await _reloadManagers();
    }
  }

  Future<void> _handleManagerAction(
    ManagerModel manager,
    _ManagerActionType action,
  ) async {
    switch (action) {
      case _ManagerActionType.edit:
        await _openManagerForm(manager: manager);
        break;
      case _ManagerActionType.deposit:
        await _openBalanceSheet(manager, _ManagerBalanceActionType.deposit);
        break;
      case _ManagerActionType.withdraw:
        await _openBalanceSheet(manager, _ManagerBalanceActionType.withdraw);
        break;
      case _ManagerActionType.payDebt:
        await _openDebtSheet(manager);
        break;
      case _ManagerActionType.addPoints:
        await _openPointsSheet(manager);
        break;
      case _ManagerActionType.delete:
        await _confirmDeleteManager(manager);
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final state = ref.watch(managersProvider);
    final canAccessManagers = authState.user?.canAccessManagers ?? false;
    final totalPages = _totalPages(state);
    final visibleCredit = state.managers.fold<double>(
      0,
      (sum, manager) => sum + manager.credit,
    );
    final visibleDebt = state.managers.fold<double>(
      0,
      (sum, manager) => sum + manager.debt,
    );

    if (!canAccessManagers) {
      return Scaffold(
        appBar: AppBar(title: const Text('المدراء الفرعيون')),
        body: const EmptyState(
          icon: Icons.lock_outline,
          title: 'لا تملك صلاحية الوصول',
          subtitle: 'هذا القسم متاح فقط للمدراء الذين لديهم صلاحية إدارة المدراء.',
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('المدراء الفرعيون'),
        actions: [
          IconButton(
            onPressed: state.loading ? null : () => _reloadManagers(),
            tooltip: 'تحديث',
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.small(
        onPressed: () => _openManagerForm(),
        tooltip: 'إضافة مدير',
        child: const Icon(Icons.person_add_alt_1_rounded),
      ),
      body: Column(
        children: [
          if (state.loading && state.managers.isNotEmpty)
            const LinearProgressIndicator(minHeight: 2),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Column(
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final compact = constraints.maxWidth < 380;
                        final ultraCompact = constraints.maxWidth < 330;

                        return Column(
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: _searchController,
                                    onChanged: _handleSearchChanged,
                                    decoration: InputDecoration(
                                      isDense: true,
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 10,
                                      ),
                                      hintText: 'بحث...',
                                      prefixIcon:
                                          const Icon(Icons.search_rounded),
                                      suffixIcon:
                                          _searchController.text.isNotEmpty
                                              ? IconButton(
                                                  onPressed: () {
                                                    _searchController.clear();
                                                    _handleSearchChanged('');
                                                    setState(() {});
                                                  },
                                                  padding: EdgeInsets.zero,
                                                  icon: const Icon(
                                                    Icons.close_rounded,
                                                  ),
                                                )
                                              : null,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                SizedBox.square(
                                  dimension: ultraCompact ? 38 : 40,
                                  child: IconButton.filledTonal(
                                    tooltip: 'الفلاتر',
                                    padding: EdgeInsets.zero,
                                    onPressed: () {
                                      setState(() {
                                        _showAdvancedFilters =
                                            !_showAdvancedFilters;
                                      });
                                    },
                                    icon: Icon(
                                      _showAdvancedFilters
                                          ? Icons.tune_rounded
                                          : Icons.tune_outlined,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                SizedBox.square(
                                  dimension: ultraCompact ? 38 : 40,
                                  child: IconButton.filledTonal(
                                    tooltip: 'تحديث',
                                    padding: EdgeInsets.zero,
                                    onPressed: state.loading
                                        ? null
                                        : () => _reloadManagers(),
                                    icon: const Icon(Icons.sync_rounded),
                                  ),
                                ),
                              ],
                            ),
                            if (_showAdvancedFilters) ...[
                              const SizedBox(height: 8),
                              DropdownButtonFormField<String>(
                                value: state.sortBy,
                                isDense: true,
                                isExpanded: true,
                                selectedItemBuilder: (_) =>
                                    _buildSortSelectedItems(compact),
                                decoration: const InputDecoration(
                                  labelText: 'الفرز',
                                ),
                                items: _buildSortMenuItems(),
                                onChanged: (value) {
                                  if (value == null) return;
                                  _reloadManagers(page: 1, sortBy: value);
                                },
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    child: DropdownButtonFormField<int>(
                                      value: state.rowsPerPage,
                                      isDense: true,
                                      isExpanded: true,
                                      decoration: const InputDecoration(
                                        labelText: 'عدد',
                                      ),
                                      items: const [10, 25, 50, 100, 500]
                                          .map(
                                            (count) => DropdownMenuItem(
                                              value: count,
                                              child: Text('$count'),
                                            ),
                                          )
                                          .toList(),
                                      onChanged: (value) {
                                        if (value == null) return;
                                        _reloadManagers(
                                          page: 1,
                                          rowsPerPage: value,
                                        );
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  SizedBox(
                                    width: ultraCompact ? 36 : 40,
                                    height: ultraCompact ? 36 : 40,
                                    child: IconButton.filledTonal(
                                      tooltip: state.direction == 'asc'
                                          ? 'ترتيب تصاعدي'
                                          : 'ترتيب تنازلي',
                                      padding: EdgeInsets.zero,
                                      onPressed: () {
                                        _reloadManagers(
                                          page: 1,
                                          direction: state.direction == 'asc'
                                              ? 'desc'
                                              : 'asc',
                                        );
                                      },
                                      icon: Icon(
                                        state.direction == 'asc'
                                            ? Icons.arrow_upward_rounded
                                            : Icons.arrow_downward_rounded,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ] else ...[
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: [
                                  _ManagersMiniStatChip(
                                    icon: Icons.sort_rounded,
                                    label:
                                        'فرز: ${_labelForSort(state.sortBy, compact: true)}',
                                    color: AppTheme.infoColor,
                                    neutral: true,
                                  ),
                                  _ManagersMiniStatChip(
                                    icon: state.direction == 'asc'
                                        ? Icons.arrow_upward_rounded
                                        : Icons.arrow_downward_rounded,
                                    label: state.direction == 'asc'
                                        ? 'تصاعدي'
                                        : 'تنازلي',
                                    color: AppTheme.primary,
                                    neutral: true,
                                  ),
                                  _ManagersMiniStatChip(
                                    icon: Icons.format_list_numbered_rounded,
                                    label: '${state.rowsPerPage} عنصر',
                                    color: AppTheme.warningColor,
                                    neutral: true,
                                  ),
                                ],
                              ),
                            ],
                          ],
                        );
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _ManagersMiniStatChip(
                      icon: Icons.admin_panel_settings_outlined,
                      label: 'المدراء ${state.totalCount}',
                      color: AppTheme.infoColor,
                    ),
                    _ManagersMiniStatChip(
                      icon: Icons.account_balance_wallet_outlined,
                      label: 'رصيد ${_formatCurrency(visibleCredit)}',
                      color: AppTheme.successColor,
                    ),
                    _ManagersMiniStatChip(
                      icon: Icons.trending_down_rounded,
                      label: 'دين ${_formatCurrency(visibleDebt)}',
                      color: AppTheme.warningColor,
                    ),
                  ],
                ),
                if (state.error != null) ...[
                  const SizedBox(height: 10),
                  _InlineInfoBanner(
                    color: AppTheme.dangerColor,
                    icon: Icons.error_outline_rounded,
                    text: state.error!,
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            child: state.loading && state.managers.isEmpty
                ? const ShimmerList(itemCount: 6)
                : state.managers.isEmpty
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(12, 18, 12, 96),
                        children: [
                          EmptyState(
                            icon: Icons.manage_accounts_outlined,
                            title: state.search.isNotEmpty
                                ? 'لا توجد نتائج مطابقة'
                                : 'لا يوجد مدراء حاليًا',
                            subtitle: state.search.isNotEmpty
                                ? 'جرّب تغيير عبارة البحث أو امسح الفلاتر الحالية.'
                                : 'يمكنك البدء بإضافة مدير فرعي جديد من زر الإضافة.',
                            action: state.search.isNotEmpty
                                ? FilledButton.tonalIcon(
                                    onPressed: () {
                                      _searchController.clear();
                                      _reloadManagers(page: 1, search: '');
                                      setState(() {});
                                    },
                                    icon:
                                        const Icon(Icons.filter_alt_off_rounded),
                                    label: const Text('مسح الفلاتر'),
                                  )
                                : null,
                          ),
                        ],
                      )
                    : RefreshIndicator(
                        onRefresh: () => _reloadManagers(),
                        child: ListView.separated(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 96),
                          itemCount: state.managers.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final manager = state.managers[index];
                            final selected = manager.id == _selectedManagerId;

                            return _ManagerListCard(
                              manager: manager,
                              selected: selected,
                              onTap: () {
                                setState(() {
                                  _selectedManagerId =
                                      selected ? null : manager.id;
                                });
                              },
                              onActionSelected: (action) =>
                                  _handleManagerAction(manager, action),
                            );
                          },
                        ),
                      ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 2, 12, 10),
              child: Card(
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final compact = constraints.maxWidth < 340;
                      final summary = Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'الصفحة ${state.currentPage} من $totalPages',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'المعروض ${state.managers.length} من أصل ${state.totalCount}',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurface
                                      .withValues(alpha: 0.6),
                                  fontSize: 11,
                                ),
                          ),
                        ],
                      );

                      final pager = Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'السابق',
                            onPressed: state.currentPage > 1 && !state.loading
                                ? () => _reloadManagers(
                                      page: state.currentPage - 1,
                                    )
                                : null,
                            icon: const Icon(Icons.chevron_right_rounded),
                          ),
                          IconButton(
                            tooltip: 'التالي',
                            onPressed:
                                state.currentPage < totalPages && !state.loading
                                    ? () => _reloadManagers(
                                          page: state.currentPage + 1,
                                        )
                                    : null,
                            icon: const Icon(Icons.chevron_left_rounded),
                          ),
                        ],
                      );

                      if (compact) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            summary,
                            const SizedBox(height: 8),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: pager,
                            ),
                          ],
                        );
                      }

                      return Row(
                        children: [
                          Expanded(child: summary),
                          pager,
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ManagerListCard extends StatelessWidget {
  final ManagerModel manager;
  final bool selected;
  final VoidCallback onTap;
  final ValueChanged<_ManagerActionType> onActionSelected;

  const _ManagerListCard({
    required this.manager,
    required this.selected,
    required this.onTap,
    required this.onActionSelected,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final showFullName =
        manager.fullName.isNotEmpty &&
        manager.fullName != manager.username &&
        !manager.fullName.contains(manager.username);
    final compact = MediaQuery.sizeOf(context).width < 390;
    final borderColor = selected
        ? theme.colorScheme.primary
        : theme.colorScheme.outline.withValues(alpha: 0.14);
    final background = selected
        ? theme.colorScheme.primary.withValues(alpha: 0.04)
        : theme.cardTheme.color ?? theme.colorScheme.surface;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor, width: selected ? 1.5 : 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.all(compact ? 10 : 12),
          child: Column(
            children: [
              Row(
                children: [
                  Stack(
                    children: [
                      CircleAvatar(
                        radius: compact ? 18 : 20,
                        backgroundColor:
                            AppTheme.primary.withValues(alpha: 0.12),
                        child: Icon(
                          Icons.admin_panel_settings_outlined,
                          color: AppTheme.primary,
                          size: compact ? 16 : 18,
                        ),
                      ),
                      Positioned(
                        left: 0,
                        bottom: 0,
                        child: Container(
                          width: 11,
                          height: 11,
                          decoration: BoxDecoration(
                            color: manager.isActive
                                ? AppTheme.successColor
                                : AppTheme.dangerColor,
                            shape: BoxShape.circle,
                            border:
                                Border.all(color: Colors.white, width: 2),
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(width: compact ? 8 : 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          manager.username,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            fontSize: compact ? 13 : 14,
                          ),
                        ),
                        if (showFullName) ...[
                          SizedBox(height: compact ? 2 : 4),
                          Text(
                            manager.fullName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: 0.72),
                              fontWeight: FontWeight.w600,
                              fontSize: compact ? 11 : 12,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: EdgeInsets.all(compact ? 4 : 6),
                    decoration: BoxDecoration(
                      color: selected
                          ? theme.colorScheme.primary.withValues(alpha: 0.10)
                          : theme.colorScheme.surfaceContainerHighest
                              .withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: AnimatedRotation(
                      turns: selected ? 0.5 : 0,
                      duration: const Duration(milliseconds: 180),
                      child: Icon(
                        Icons.expand_more_rounded,
                        size: compact ? 18 : 20,
                        color: selected
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurface
                                .withValues(alpha: 0.72),
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: compact ? 8 : 10),
              Wrap(
                spacing: compact ? 6 : 8,
                runSpacing: compact ? 6 : 8,
                children: [
                  _InfoBadge(
                    icon: manager.isActive
                        ? Icons.check_circle_outline_rounded
                        : Icons.block_rounded,
                    label: manager.isActive ? 'مفعّل' : 'معطّل',
                    color: manager.isActive
                        ? AppTheme.successColor
                        : AppTheme.dangerColor,
                  ),
                  if ((manager.aclName ?? '').isNotEmpty)
                    _InfoBadge(
                      icon: Icons.verified_user_outlined,
                      label: manager.aclName!,
                      color: AppTheme.infoColor,
                    ),
                  if (selected && manager.mobile.isNotEmpty)
                    _InfoBadge(
                      icon: Icons.phone_outlined,
                      label: manager.mobile,
                      color: AppTheme.primary,
                    ),
                  if (selected && manager.company.isNotEmpty)
                    _InfoBadge(
                      icon: Icons.business_outlined,
                      label: manager.company,
                      color: AppTheme.warningColor,
                    ),
                ],
              ),
              SizedBox(height: compact ? 8 : 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _ManagersMiniStatChip(
                    icon: Icons.people_outline_rounded,
                    label: 'مشتركون ${manager.usersCount}',
                    color: AppTheme.infoColor,
                  ),
                  _ManagersMiniStatChip(
                    icon: Icons.stars_rounded,
                    label: 'نقاط ${manager.rewardPoints}',
                    color: AppTheme.secondary,
                  ),
                  _ManagersMiniStatChip(
                    icon: Icons.account_balance_wallet_outlined,
                    label: 'رصيد ${_formatCurrency(manager.credit)}',
                    color: AppTheme.successColor,
                  ),
                  _ManagersMiniStatChip(
                    icon: Icons.trending_down_rounded,
                    label: 'دين ${_formatCurrency(manager.debt)}',
                    color: AppTheme.warningColor,
                  ),
                ],
              ),
              AnimatedCrossFade(
                firstChild: const SizedBox.shrink(),
                secondChild: Column(
                  children: [
                    SizedBox(height: compact ? 8 : 10),
                    const Divider(height: 1),
                    SizedBox(height: compact ? 8 : 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _ManagerActionButton(
                          icon: Icons.edit_outlined,
                          label: 'تعديل',
                          color: AppTheme.primary,
                          onPressed: () =>
                              onActionSelected(_ManagerActionType.edit),
                        ),
                        _ManagerActionButton(
                          icon: Icons.add_card_rounded,
                          label: 'رصيد',
                          color: AppTheme.successColor,
                          onPressed: () =>
                              onActionSelected(_ManagerActionType.deposit),
                        ),
                        _ManagerActionButton(
                          icon: Icons.remove_circle_outline_rounded,
                          label: 'سحب',
                          color: AppTheme.warningColor,
                          onPressed: manager.credit > 0
                              ? () => onActionSelected(
                                    _ManagerActionType.withdraw,
                                  )
                              : null,
                        ),
                        _ManagerActionButton(
                          icon: Icons.payments_outlined,
                          label: 'تسديد',
                          color: AppTheme.infoColor,
                          onPressed: manager.debt > 0
                              ? () => onActionSelected(
                                    _ManagerActionType.payDebt,
                                  )
                              : null,
                        ),
                        _ManagerActionButton(
                          icon: Icons.stars_rounded,
                          label: 'نقاط',
                          color: AppTheme.secondary,
                          onPressed: () =>
                              onActionSelected(_ManagerActionType.addPoints),
                        ),
                        _ManagerActionButton(
                          icon: Icons.delete_outline_rounded,
                          label: 'حذف',
                          color: AppTheme.dangerColor,
                          onPressed: () =>
                              onActionSelected(_ManagerActionType.delete),
                        ),
                      ],
                    ),
                  ],
                ),
                crossFadeState: selected
                    ? CrossFadeState.showSecond
                    : CrossFadeState.showFirst,
                duration: const Duration(milliseconds: 180),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ManagerFormSheet extends ConsumerStatefulWidget {
  final ManagerModel? manager;

  const _ManagerFormSheet({this.manager});

  @override
  ConsumerState<_ManagerFormSheet> createState() => _ManagerFormSheetState();
}

class _ManagerFormSheetState extends ConsumerState<_ManagerFormSheet> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _firstnameController = TextEditingController();
  final TextEditingController _lastnameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _mobileController = TextEditingController();
  final TextEditingController _companyController = TextEditingController();
  final TextEditingController _cityController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();

  bool _loadingData = true;
  bool _saving = false;
  bool _enabled = true;
  int? _selectedAclId;
  int? _selectedParentId;
  List<ManagerAclGroup> _aclGroups = const [];
  List<ManagerModel> _parentManagers = const [];

  bool get _isEdit => widget.manager != null;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _firstnameController.dispose();
    _lastnameController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _emailController.dispose();
    _mobileController.dispose();
    _companyController.dispose();
    _cityController.dispose();
    _addressController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    final notifier = ref.read(managersProvider.notifier);
    final aclGroups = await notifier.fetchAclGroups();
    final parentManagers = await notifier.fetchParentManagers();
    final details = _isEdit
        ? await notifier.fetchManagerDetails(widget.manager!.id)
        : null;
    final source = details ?? widget.manager;

    if (!mounted) return;

    _aclGroups = aclGroups;
    _parentManagers = parentManagers
        .where((manager) => manager.id != widget.manager?.id)
        .toList();

    if (source != null) {
      _usernameController.text = source.username;
      _firstnameController.text = source.firstname;
      _lastnameController.text = source.lastname;
      _emailController.text = source.email;
      _mobileController.text = source.mobile;
      _companyController.text = source.company;
      _cityController.text = source.city;
      _addressController.text = source.address;
      _notesController.text = source.notes;
      _enabled = source.isActive;
      _selectedAclId = source.aclId;
      _selectedParentId = source.parentId;
    }

    final aclIds = _aclGroups.map((acl) => acl.id).toSet();
    if (_selectedAclId != null && !aclIds.contains(_selectedAclId)) {
      _selectedAclId = null;
    }

    final parentIds = _parentManagers.map((manager) => manager.id).toSet();
    if (_selectedParentId != null && !parentIds.contains(_selectedParentId)) {
      _selectedParentId = null;
    }

    setState(() => _loadingData = false);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedAclId == null) {
      AppSnackBar.warning(context, 'اختر مجموعة الصلاحيات');
      return;
    }

    setState(() => _saving = true);

    final notifier = ref.read(managersProvider.notifier);
    bool success;

    if (_isEdit) {
      success = await notifier.updateManager(
        managerId: widget.manager!.id,
        original: widget.manager!,
        username: _usernameController.text,
        firstname: _firstnameController.text,
        lastname: _lastnameController.text,
        aclId: _selectedAclId!,
        isActive: _enabled,
        password: _passwordController.text.trim().isEmpty
            ? null
            : _passwordController.text.trim(),
        email: _emailController.text,
        mobile: _mobileController.text,
        company: _companyController.text,
        parentId: _selectedParentId,
      );
    } else {
      success = await notifier.createManager(
        username: _usernameController.text,
        password: _passwordController.text.trim(),
        aclGroupId: _selectedAclId!,
        parentId: _selectedParentId,
        firstname: _firstnameController.text,
        lastname: _lastnameController.text,
        company: _companyController.text,
        email: _emailController.text,
        phone: _mobileController.text,
        city: _cityController.text,
        address: _addressController.text,
        notes: _notesController.text,
        enabled: _enabled,
      );
    }

    if (!mounted) return;

    setState(() => _saving = false);

    if (success) {
      Navigator.of(context).pop(true);
    } else {
      AppSnackBar.error(
        context,
        _isEdit ? 'فشل تحديث المدير' : 'فشل إضافة المدير',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return _SheetScaffold(
      title: _isEdit ? 'تعديل مدير' : 'إضافة مدير جديد',
      icon: _isEdit
          ? Icons.manage_accounts_outlined
          : Icons.person_add_alt_1_rounded,
      subtitle: _isEdit
          ? 'يمكنك تعديل بيانات المدير وصلاحياته وحالته من هنا.'
          : 'أنشئ مديرًا فرعيًا جديدًا وحدد بياناته وصلاحياته الأساسية.',
      isLoading: _saving,
      child: _loadingData
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(child: CircularProgressIndicator()),
            )
          : Form(
              key: _formKey,
              child: Column(
                children: [
                  _SheetSectionCard(
                    title: 'بيانات الحساب',
                    icon: Icons.account_circle_outlined,
                    child: Column(
                      children: [
                        TextFormField(
                          controller: _usernameController,
                          decoration: const InputDecoration(
                            labelText: 'اسم المستخدم',
                            prefixIcon: Icon(Icons.person_outline_rounded),
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'أدخل اسم المستخدم';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<int>(
                          value: _selectedAclId,
                          decoration: const InputDecoration(
                            labelText: 'مجموعة الصلاحيات',
                            prefixIcon: Icon(Icons.verified_user_outlined),
                          ),
                          items: _aclGroups
                              .map(
                                (acl) => DropdownMenuItem(
                                  value: acl.id,
                                  child: Text(acl.name),
                                ),
                              )
                              .toList(),
                          onChanged: (value) {
                            setState(() => _selectedAclId = value);
                          },
                          validator: (value) =>
                              value == null ? 'اختر مجموعة الصلاحيات' : null,
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<int?>(
                          value: _selectedParentId,
                          decoration: const InputDecoration(
                            labelText: 'تابع إلى',
                            prefixIcon: Icon(Icons.account_tree_outlined),
                          ),
                          items: [
                            const DropdownMenuItem<int?>(
                              value: null,
                              child: Text('لا يوجد'),
                            ),
                            ..._parentManagers.map(
                              (manager) => DropdownMenuItem<int?>(
                                value: manager.id,
                                child: Text(
                                  manager.fullName.isNotEmpty
                                      ? '${manager.username} - ${manager.fullName}'
                                      : manager.username,
                                ),
                              ),
                            ),
                          ],
                          onChanged: (value) {
                            setState(() => _selectedParentId = value);
                          },
                        ),
                        const SizedBox(height: 6),
                        SwitchListTile.adaptive(
                          contentPadding: EdgeInsets.zero,
                          value: _enabled,
                          onChanged: (value) {
                            setState(() => _enabled = value);
                          },
                          title: const Text('الحساب مفعّل'),
                          subtitle: Text(
                            _enabled
                                ? 'سيتمكن المدير من تسجيل الدخول مباشرة.'
                                : 'سيُحفظ المدير لكن بدون تفعيل الحساب.',
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  _SheetSectionCard(
                    title: 'البيانات الشخصية',
                    icon: Icons.badge_outlined,
                    child: Column(
                      children: [
                        TextFormField(
                          controller: _firstnameController,
                          decoration: const InputDecoration(
                            labelText: 'الاسم الأول',
                            prefixIcon: Icon(Icons.text_fields_rounded),
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'أدخل الاسم الأول';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _lastnameController,
                          decoration: const InputDecoration(
                            labelText: 'الاسم الأخير',
                            prefixIcon: Icon(Icons.text_fields_rounded),
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'أدخل الاسم الأخير';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          decoration: const InputDecoration(
                            labelText: 'البريد الإلكتروني',
                            prefixIcon: Icon(Icons.email_outlined),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _mobileController,
                          keyboardType: TextInputType.phone,
                          decoration: const InputDecoration(
                            labelText: 'رقم الهاتف',
                            prefixIcon: Icon(Icons.phone_outlined),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _companyController,
                          decoration: const InputDecoration(
                            labelText: 'الشركة',
                            prefixIcon: Icon(Icons.business_outlined),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _cityController,
                          decoration: const InputDecoration(
                            labelText: 'المدينة',
                            prefixIcon: Icon(Icons.location_city_outlined),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _addressController,
                          maxLines: 2,
                          decoration: const InputDecoration(
                            labelText: 'العنوان',
                            prefixIcon: Icon(Icons.home_outlined),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  _SheetSectionCard(
                    title: _isEdit ? 'كلمة المرور والملاحظات' : 'كلمة المرور',
                    icon: Icons.lock_outline_rounded,
                    child: Column(
                      children: [
                        TextFormField(
                          controller: _passwordController,
                          obscureText: true,
                          decoration: InputDecoration(
                            labelText:
                                _isEdit ? 'كلمة مرور جديدة (اختياري)' : 'كلمة المرور',
                            prefixIcon: const Icon(Icons.lock_outline_rounded),
                          ),
                          validator: (value) {
                            final trimmed = value?.trim() ?? '';
                            if (!_isEdit && trimmed.isEmpty) {
                              return 'أدخل كلمة المرور';
                            }
                            if (!_isEdit &&
                                _confirmPasswordController.text.trim() !=
                                    trimmed) {
                              return 'كلمة المرور غير متطابقة';
                            }
                            return null;
                          },
                        ),
                        if (!_isEdit) ...[
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _confirmPasswordController,
                            obscureText: true,
                            decoration: const InputDecoration(
                              labelText: 'تأكيد كلمة المرور',
                              prefixIcon: Icon(Icons.lock_reset_rounded),
                            ),
                            validator: (value) {
                              if ((value ?? '').trim() !=
                                  _passwordController.text.trim()) {
                                return 'تأكيد كلمة المرور غير مطابق';
                              }
                              return null;
                            },
                          ),
                        ],
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _notesController,
                          maxLines: 3,
                          decoration: const InputDecoration(
                            labelText: 'ملاحظات',
                            prefixIcon: Icon(Icons.note_alt_outlined),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(context).pop(false),
                          child: const Text('إلغاء'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _saving ? null : _submit,
                          icon: Icon(
                            _isEdit
                                ? Icons.save_outlined
                                : Icons.person_add_alt_1_rounded,
                          ),
                          label:
                              Text(_isEdit ? 'حفظ التعديلات' : 'إضافة المدير'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
    );
  }
}

class _ManagerBalanceSheet extends ConsumerStatefulWidget {
  final ManagerModel manager;
  final _ManagerBalanceActionType action;

  const _ManagerBalanceSheet({
    required this.manager,
    required this.action,
  });

  @override
  ConsumerState<_ManagerBalanceSheet> createState() =>
      _ManagerBalanceSheetState();
}

class _ManagerBalanceSheetState extends ConsumerState<_ManagerBalanceSheet> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();
  bool _isLoan = false;
  bool _saving = false;

  bool get _isDeposit => widget.action == _ManagerBalanceActionType.deposit;

  @override
  void dispose() {
    _amountController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final amount = _parseFormattedAmount(_amountController.text);
    if (amount == null || amount <= 0) {
      AppSnackBar.warning(context, 'أدخل مبلغًا صحيحًا');
      return;
    }

    if (!_isDeposit && amount > widget.manager.credit) {
      AppSnackBar.warning(context, 'المبلغ أكبر من الرصيد المتاح');
      return;
    }

    setState(() => _saving = true);

    final notifier = ref.read(managersProvider.notifier);
    final success = _isDeposit
        ? await notifier.addBalance(
            manager: widget.manager,
            amount: amount,
            notes: _notesController.text,
            isLoan: _isLoan,
          )
        : await notifier.withdrawBalance(
            manager: widget.manager,
            amount: amount,
            notes: _notesController.text,
          );

    if (!mounted) return;

    setState(() => _saving = false);

    if (success) {
      if (_isDeposit) {
        await _showManagerFinancialNoticeDialog(
          context: context,
          ref: ref,
          notice: _ManagerFinancialNoticeData(
            manager: widget.manager,
            amount: amount,
            kind: _isLoan
                ? _ManagerFinancialNoticeKind.loanDeposit
                : _ManagerFinancialNoticeKind.cashDeposit,
            notes: _notesController.text.trim(),
            previousCredit: widget.manager.credit,
            previousDebt: widget.manager.debt,
            currentCredit: widget.manager.credit + amount,
            currentDebt: widget.manager.debt + (_isLoan ? amount : 0),
          ),
        );
        if (!mounted) return;
      }
      Navigator.of(context).pop(true);
    } else {
      AppSnackBar.error(
        context,
        _isDeposit ? 'فشل إضافة الرصيد' : 'فشل سحب الرصيد',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return _SheetScaffold(
      title: _isDeposit ? 'إضافة رصيد' : 'سحب رصيد',
      icon: _isDeposit
          ? Icons.add_card_rounded
          : Icons.remove_circle_outline_rounded,
      subtitle: _isDeposit
          ? 'أضف رصيدًا نقديًا أو آجلًا للمدير المحدد.'
          : 'اسحب مبلغًا من رصيد المدير الحالي.',
      isLoading: _saving,
      child: Form(
        key: _formKey,
        child: Column(
          children: [
            _SheetSectionCard(
              title: 'ملخص المدير',
              icon: Icons.person_outline_rounded,
              child: Column(
                children: [
                  _SummaryLine(
                    label: 'المدير',
                    value: widget.manager.username,
                  ),
                  _SummaryLine(
                    label: 'الاسم',
                    value: widget.manager.fullName.isNotEmpty
                        ? widget.manager.fullName
                        : 'غير محدد',
                  ),
                  _SummaryLine(
                    label: 'الرصيد الحالي',
                    value: _formatCurrency(widget.manager.credit),
                    accent: AppTheme.successColor,
                  ),
                  _SummaryLine(
                    label: 'الدين الحالي',
                    value: _formatCurrency(widget.manager.debt),
                    accent: AppTheme.warningColor,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _SheetSectionCard(
              title: _isDeposit ? 'بيانات الإضافة' : 'بيانات السحب',
              icon: Icons.payments_outlined,
              child: Column(
                children: [
                  TextFormField(
                    controller: _amountController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      _ThousandsSeparatorInputFormatter(),
                    ],
                    decoration: InputDecoration(
                      labelText: _isDeposit
                          ? 'المبلغ المراد إضافته'
                          : 'المبلغ المراد سحبه',
                      prefixIcon: const Icon(Icons.currency_exchange_rounded),
                    ),
                    validator: (value) {
                      final amount = _parseFormattedAmount(value ?? '');
                      if (amount == null || amount <= 0) {
                        return 'أدخل مبلغًا صحيحًا';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _notesController,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'ملاحظات',
                      prefixIcon: Icon(Icons.note_alt_outlined),
                    ),
                  ),
                  if (_isDeposit) ...[
                    const SizedBox(height: 8),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      value: _isLoan,
                      onChanged: (value) {
                        setState(() => _isLoan = value);
                      },
                      title: const Text('اعتبار المبلغ دينًا على المدير'),
                      subtitle: Text(
                        _isLoan
                            ? 'سيتم تسجيل الإضافة كرصيد آجل.'
                            : 'سيتم تسجيل الإضافة كرصيد نقدي.',
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('إلغاء'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _saving ? null : _submit,
                    icon: Icon(
                      _isDeposit
                          ? Icons.add_card_rounded
                          : Icons.remove_circle_outline_rounded,
                    ),
                    label: Text(
                      _isDeposit ? 'تنفيذ الإضافة' : 'تنفيذ السحب',
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ManagerDebtPaymentSheet extends ConsumerStatefulWidget {
  final ManagerModel manager;

  const _ManagerDebtPaymentSheet({required this.manager});

  @override
  ConsumerState<_ManagerDebtPaymentSheet> createState() =>
      _ManagerDebtPaymentSheetState();
}

class _ManagerDebtPaymentSheetState
    extends ConsumerState<_ManagerDebtPaymentSheet> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();

  ManagerDebtInfo? _debtInfo;
  bool _loadingDebt = true;
  bool _saving = false;
  bool _payAll = false;

  @override
  void initState() {
    super.initState();
    _loadDebtInfo();
  }

  @override
  void dispose() {
    _amountController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _loadDebtInfo() async {
    final debtInfo =
        await ref.read(managersProvider.notifier).fetchDebtInfo(widget.manager.id);
    if (!mounted) return;
    setState(() {
      _debtInfo = debtInfo;
      _loadingDebt = false;
    });
  }

  double get _outstandingDebt =>
      (_debtInfo?.totalDebt.abs() ?? widget.manager.debt).toDouble();

  double get _debtForMe =>
      (_debtInfo?.debtForMe.abs() ?? widget.manager.debt).toDouble();

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final amount = double.tryParse(_amountController.text.trim());
    if (amount == null || amount <= 0) {
      AppSnackBar.warning(context, 'أدخل مبلغًا صحيحًا');
      return;
    }
    if (amount > _outstandingDebt) {
      AppSnackBar.warning(context, 'المبلغ أكبر من الدين المستحق');
      return;
    }

    setState(() => _saving = true);
    final success = await ref.read(managersProvider.notifier).payDebt(
          manager: widget.manager,
          amount: amount,
          debtForMe: _debtForMe,
          totalDebt: _outstandingDebt,
          notes: _notesController.text,
        );

    if (!mounted) return;

    setState(() => _saving = false);

    if (success) {
      await _showManagerFinancialNoticeDialog(
        context: context,
        ref: ref,
        notice: _ManagerFinancialNoticeData(
          manager: widget.manager,
          amount: amount,
          kind: _ManagerFinancialNoticeKind.debtPayment,
          notes: _notesController.text.trim(),
          previousCredit: widget.manager.credit,
          previousDebt: _outstandingDebt,
          currentCredit: widget.manager.credit,
          currentDebt:
              (_outstandingDebt - amount).clamp(0, double.infinity).toDouble(),
        ),
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } else {
      AppSnackBar.error(context, 'فشل تسديد الدين');
    }
  }

  @override
  Widget build(BuildContext context) {
    return _SheetScaffold(
      title: 'تسديد دين',
      icon: Icons.payments_outlined,
      subtitle: 'سدّد كامل الدين أو جزءًا منه للمدير المحدد.',
      isLoading: _saving,
      child: _loadingDebt
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(child: CircularProgressIndicator()),
            )
          : _outstandingDebt <= 0
              ? Column(
                  children: [
                    const _InlineInfoBanner(
                      color: AppTheme.successColor,
                      icon: Icons.check_circle_outline_rounded,
                      text: 'لا يوجد دين مستحق على هذا المدير حاليًا.',
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        child: const Text('إغلاق'),
                      ),
                    ),
                  ],
                )
              : Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      _SheetSectionCard(
                        title: 'ملخص الدين',
                        icon: Icons.account_balance_outlined,
                        child: Column(
                          children: [
                            _SummaryLine(
                              label: 'المدير',
                              value: widget.manager.username,
                            ),
                            _SummaryLine(
                              label: 'الرصيد الحالي',
                              value: _formatCurrency(
                                _debtInfo?.balance ?? widget.manager.credit,
                              ),
                              accent: AppTheme.successColor,
                            ),
                            _SummaryLine(
                              label: 'إجمالي الديون',
                              value: _formatCurrency(_outstandingDebt),
                              accent: AppTheme.warningColor,
                            ),
                            _SummaryLine(
                              label: 'الدين المستحق لي',
                              value: _formatCurrency(_debtForMe),
                              accent: AppTheme.infoColor,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      _SheetSectionCard(
                        title: 'بيانات التسديد',
                        icon: Icons.request_quote_outlined,
                        child: Column(
                          children: [
                            CheckboxListTile.adaptive(
                              contentPadding: EdgeInsets.zero,
                              value: _payAll,
                              onChanged: (value) {
                                final next = value ?? false;
                                setState(() {
                                  _payAll = next;
                                  _amountController.text =
                                      next ? _outstandingDebt.toString() : '';
                                });
                              },
                              title: const Text('تسديد كامل المبلغ'),
                              subtitle: Text(
                                'سيتم تعبئة مبلغ ${_formatCurrency(_outstandingDebt)} تلقائيًا.',
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextFormField(
                              controller: _amountController,
                              enabled: !_payAll,
                              keyboardType: const TextInputType.numberWithOptions(
                                decimal: true,
                              ),
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(
                                  RegExp(r'[\d.]'),
                                ),
                              ],
                              decoration: const InputDecoration(
                                labelText: 'المبلغ المراد تسديده',
                                prefixIcon:
                                    Icon(Icons.currency_exchange_rounded),
                              ),
                              validator: (value) {
                                final amount =
                                    double.tryParse((value ?? '').trim());
                                if (amount == null || amount <= 0) {
                                  return 'أدخل مبلغًا صحيحًا';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _notesController,
                              maxLines: 2,
                              decoration: const InputDecoration(
                                labelText: 'ملاحظات',
                                prefixIcon: Icon(Icons.note_alt_outlined),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => Navigator.of(context).pop(false),
                              child: const Text('إلغاء'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _saving ? null : _submit,
                              icon: const Icon(Icons.payments_outlined),
                              label: const Text('تنفيذ التسديد'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
    );
  }
}

class _ManagerPointsSheet extends ConsumerStatefulWidget {
  final ManagerModel manager;

  const _ManagerPointsSheet({required this.manager});

  @override
  ConsumerState<_ManagerPointsSheet> createState() => _ManagerPointsSheetState();
}

class _ManagerPointsSheetState extends ConsumerState<_ManagerPointsSheet> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _pointsController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _pointsController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final points = int.tryParse(_pointsController.text.trim());
    if (points == null || points <= 0) {
      AppSnackBar.warning(context, 'أدخل عدد نقاط صحيحًا');
      return;
    }

    setState(() => _saving = true);
    final result = await ref.read(managersProvider.notifier).addPoints(
          manager: widget.manager,
          points: points,
          notes: _notesController.text,
        );

    if (!mounted) return;

    setState(() => _saving = false);

    if (result.$1) {
      Navigator.of(context).pop(true);
    } else {
      AppSnackBar.error(
        context,
        result.$2 ?? 'فشل إضافة النقاط',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return _SheetScaffold(
      title: 'إضافة نقاط',
      icon: Icons.stars_rounded,
      subtitle: 'أضف نقاطًا تشجيعية للمدير مع ملاحظة اختيارية.',
      isLoading: _saving,
      child: Form(
        key: _formKey,
        child: Column(
          children: [
            _SheetSectionCard(
              title: 'بيانات العملية',
              icon: Icons.emoji_events_outlined,
              child: Column(
                children: [
                  _SummaryLine(label: 'المدير', value: widget.manager.username),
                  if (widget.manager.fullName.isNotEmpty)
                    _SummaryLine(
                      label: 'الاسم',
                      value: widget.manager.fullName,
                    ),
                  _SummaryLine(
                    label: 'النقاط الحالية',
                    value: '${widget.manager.rewardPoints}',
                    accent: AppTheme.secondary,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _pointsController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      labelText: 'عدد النقاط',
                      prefixIcon: Icon(Icons.stars_rounded),
                    ),
                    validator: (value) {
                      final points = int.tryParse((value ?? '').trim());
                      if (points == null || points <= 0) {
                        return 'أدخل عدد نقاط صحيحًا';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _notesController,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'ملاحظات',
                      prefixIcon: Icon(Icons.note_alt_outlined),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('إلغاء'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _saving ? null : _submit,
                    icon: const Icon(Icons.stars_rounded),
                    label: const Text('إضافة النقاط'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DeleteManagerDialog extends ConsumerStatefulWidget {
  final ManagerModel manager;

  const _DeleteManagerDialog({required this.manager});

  @override
  ConsumerState<_DeleteManagerDialog> createState() =>
      _DeleteManagerDialogState();
}

class _DeleteManagerDialogState extends ConsumerState<_DeleteManagerDialog> {
  final TextEditingController _controller = TextEditingController();
  bool _deleting = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_controller.text.trim() != widget.manager.username) {
      AppSnackBar.warning(context, 'اسم المستخدم غير مطابق للتأكيد');
      return;
    }

    setState(() => _deleting = true);
    final result =
        await ref.read(managersProvider.notifier).deleteManager(widget.manager);

    if (!mounted) return;

    if (result.$1) {
      Navigator.of(context).pop(true);
    } else {
      setState(() => _deleting = false);
      AppSnackBar.error(context, result.$2 ?? 'تعذر حذف المدير');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text(
        'حذف مدير',
        style: TextStyle(fontWeight: FontWeight.w700),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'لحذف المدير `${widget.manager.username}` اكتب اسم المستخدم للتأكيد.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'اسم المستخدم',
                prefixIcon: Icon(Icons.person_outline),
              ),
              onSubmitted: (_) {
                if (!_deleting) {
                  _submit();
                }
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _deleting ? null : () => Navigator.of(context).pop(false),
          child: const Text('إلغاء'),
        ),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: AppTheme.dangerColor,
          ),
          onPressed: _deleting ? null : _submit,
          icon: _deleting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.delete_outline),
          label: Text(_deleting ? 'جارٍ الحذف...' : 'حذف المدير'),
        ),
      ],
    );
  }
}

class _SheetScaffold extends StatelessWidget {
  final String title;
  final IconData icon;
  final String? subtitle;
  final bool isLoading;
  final Widget child;

  const _SheetScaffold({
    required this.title,
    required this.icon,
    this.subtitle,
    this.isLoading = false,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final keyboardInset = MediaQuery.of(context).viewInsets.bottom;
    final systemInset = bottomSheetSystemInset(context);

    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: keyboardInset),
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 10, 16, systemInset + 20),
        child: LoadingOverlay(
          isLoading: isLoading,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 42,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(icon, color: AppTheme.primary),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style:
                                Theme.of(context).textTheme.titleLarge?.copyWith(
                                      fontWeight: FontWeight.w800,
                                    ),
                          ),
                          if (subtitle != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              subtitle!,
                              style:
                                  Theme.of(context).textTheme.bodyMedium?.copyWith(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurface
                                            .withValues(alpha: 0.65),
                                      ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                child,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SheetSectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;

  const _SheetSectionCard({
    required this.title,
    required this.icon,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: AppTheme.primary),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }
}

class _ManagersStatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _ManagersStatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, size: 16, color: color),
                ),
                const Spacer(),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 2,
                    textAlign: TextAlign.end,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.62),
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: color,
                    fontSize: 16,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ManagersMiniStatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final bool neutral;

  const _ManagersMiniStatChip({
    required this.icon,
    required this.label,
    required this.color,
    this.neutral = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final resolvedColor = neutral
        ? theme.colorScheme.onSurface.withValues(alpha: 0.72)
        : color;
    final backgroundColor = neutral
        ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.42)
        : color.withValues(alpha: 0.08);
    final borderColor = neutral
        ? theme.colorScheme.outline.withValues(alpha: 0.16)
        : color.withValues(alpha: 0.12);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: resolvedColor),
          const SizedBox(width: 6),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: resolvedColor,
                  fontSize: 11,
                ),
          ),
        ],
      ),
    );
  }
}

class _ManagerActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onPressed;

  const _ManagerActionButton({
    required this.icon,
    required this.label,
    required this.color,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        foregroundColor: onPressed == null ? Colors.grey : color,
        side: BorderSide(
          color: (onPressed == null ? Colors.grey : color)
              .withValues(alpha: 0.28),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        minimumSize: const Size(68, 32),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
        textStyle: const TextStyle(
          fontFamily: AppTheme.fontFamily,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label),
    );
  }
}

class _InfoBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _InfoBadge({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.15)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 120),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w700,
                    fontSize: 10.5,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InlineInfoBanner extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String text;

  const _InlineInfoBanner({
    required this.color,
    required this.icon,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.15)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryLine extends StatelessWidget {
  final String label;
  final String value;
  final Color? accent;

  const _SummaryLine({
    required this.label,
    required this.value,
    this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final color = accent ??
        Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.82);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.62),
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w800,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

String _formatCurrency(num value) {
  final absolute = value.abs();
  if (absolute == 0) return '0 IQD';
  final formatter = intl.NumberFormat('#,##0.##', 'en_US');
  return '${formatter.format(absolute)} IQD';
}

double? _parseFormattedAmount(String value) {
  final normalized = value.replaceAll(',', '').trim();
  if (normalized.isEmpty) return null;
  return double.tryParse(normalized);
}

class _ThousandsSeparatorInputFormatter extends TextInputFormatter {
  _ThousandsSeparatorInputFormatter()
      : _numberFormatter = intl.NumberFormat('#,##0', 'en_US');

  final intl.NumberFormat _numberFormatter;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digitsOnly = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digitsOnly.isEmpty) {
      return const TextEditingValue(text: '');
    }

    final parsed = int.tryParse(digitsOnly);
    if (parsed == null) {
      return oldValue;
    }

    final formatted = _numberFormatter.format(parsed);
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}
