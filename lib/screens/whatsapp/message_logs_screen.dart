import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' as intl;
import '../../providers/messages_provider.dart';
import '../../models/message_log_model.dart';
import '../../core/constants/app_constants.dart';
import '../../core/utils/helpers.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/status_badge.dart';
import '../../widgets/loading_overlay.dart';
import '../../widgets/app_snackbar.dart';

class MessageLogsScreen extends ConsumerStatefulWidget {
  const MessageLogsScreen({super.key});

  @override
  ConsumerState<MessageLogsScreen> createState() => _MessageLogsScreenState();
}

class _MessageLogsScreenState extends ConsumerState<MessageLogsScreen> {
  final _scrollController = ScrollController();
  final _searchController = TextEditingController();
  Timer? _autoRefreshTimer;
  String? _dateFrom;
  String? _dateTo;

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(messagesProvider.notifier).loadMessages(refresh: true);
    });
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    _autoRefreshTimer?.cancel();
    super.dispose();
  }

  void _startAutoRefresh() {
    _autoRefreshTimer?.cancel();
    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      final state = ref.read(messagesProvider);
      if (state.stats.pending > 0) {
        ref.read(messagesProvider.notifier).loadMessages(refresh: true);
      } else {
        _autoRefreshTimer?.cancel();
      }
    });
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      final state = ref.read(messagesProvider);
      if (!state.isLoading && state.hasMore) {
        ref.read(messagesProvider.notifier).loadMessages();
      }
    }
  }

  void _showFilterSheet() {
    final state = ref.read(messagesProvider);
    String? selectedStatus = state.statusFilter;
    String? selectedType = state.typeFilter;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
            left: 20,
            right: 20,
            top: 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Theme.of(ctx).colorScheme.onSurface.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Text(
                'تصفية الرسائل',
                style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 16),
              Text('حالة الرسالة',
                  style: Theme.of(ctx).textTheme.titleSmall),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _buildFilterChip('الكل', null, selectedStatus,
                      (v) => setSheetState(() => selectedStatus = v)),
                  ...['sent', 'failed', 'pending', 'processing', 'cancelled']
                      .map((s) => _buildFilterChip(
                            MessageStatuses.getArabicLabel(s),
                            s,
                            selectedStatus,
                            (v) => setSheetState(() => selectedStatus = v),
                          )),
                ],
              ),
              const SizedBox(height: 16),
              Text('نوع الرسالة',
                  style: Theme.of(ctx).textTheme.titleSmall),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _buildFilterChip('الكل', null, selectedType,
                      (v) => setSheetState(() => selectedType = v)),
                  ...[
                    'debt_reminder',
                    'expiry_warning',
                    'service_end',
                    'broadcast',
                    'manual',
                    'activation_notice',
                  ].map((t) => _buildFilterChip(
                        MessageTypes.getArabicLabel(t),
                        t,
                        selectedType,
                        (v) => setSheetState(() => selectedType = v),
                      )),
                ],
              ),
              const SizedBox(height: 16),
              Text('الفترة الزمنية',
                  style: Theme.of(ctx).textTheme.titleSmall),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _DateButton(
                      label: 'من',
                      value: _dateFrom,
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: ctx,
                          initialDate: DateTime.now().subtract(const Duration(days: 7)),
                          firstDate: DateTime(2024),
                          lastDate: DateTime.now(),
                        );
                        if (picked != null) {
                          setSheetState(() {
                            _dateFrom = intl.DateFormat('yyyy-MM-dd').format(picked);
                          });
                        }
                      },
                      onClear: () => setSheetState(() => _dateFrom = null),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _DateButton(
                      label: 'إلى',
                      value: _dateTo,
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: ctx,
                          initialDate: DateTime.now(),
                          firstDate: DateTime(2024),
                          lastDate: DateTime.now(),
                        );
                        if (picked != null) {
                          setSheetState(() {
                            _dateTo = intl.DateFormat('yyyy-MM-dd').format(picked);
                          });
                        }
                      },
                      onClear: () => setSheetState(() => _dateTo = null),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        setSheetState(() {
                          selectedStatus = null;
                          selectedType = null;
                          _dateFrom = null;
                          _dateTo = null;
                        });
                      },
                      child: const Text('إعادة تعيين'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        ref.read(messagesProvider.notifier).setFilters(
                              status: selectedStatus,
                              type: selectedType,
                              search: _searchController.text.isNotEmpty
                                  ? _searchController.text
                                  : null,
                              dateFrom: _dateFrom,
                              dateTo: _dateTo,
                            );
                        Navigator.pop(ctx);
                      },
                      child: const Text('تطبيق'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilterChip(
    String label,
    String? value,
    String? selected,
    ValueChanged<String?> onSelect,
  ) {
    final isSelected = value == selected;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) => onSelect(value),
    );
  }

  void _showClearDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('مسح السجل'),
        content: const Text('اختر نوع الرسائل المراد مسحها'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              ref.read(messagesProvider.notifier).clearLogs(status: 'sent');
              AppSnackBar.success(context, 'تم مسح الرسائل المرسلة');
            },
            child: const Text('المرسلة فقط'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              ref.read(messagesProvider.notifier).clearLogs(status: 'failed');
              AppSnackBar.success(context, 'تم مسح الرسائل الفاشلة');
            },
            child: const Text('الفاشلة فقط'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              ref.read(messagesProvider.notifier).clearLogs();
              AppSnackBar.success(context, 'تم مسح جميع الرسائل');
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.dangerColor),
            child: const Text('مسح الكل'),
          ),
        ],
      ),
    );
  }

  void _showMessageDetail(MessageLogModel msg) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: theme.colorScheme.onSurface.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppHelpers.getStatusColor(msg.status)
                          .withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      AppHelpers.getMessageTypeIcon(msg.messageType),
                      color: AppHelpers.getStatusColor(msg.status),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          msg.recipientUsername ?? '—',
                          style: const TextStyle(
                            fontFamily: 'Cairo',
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                        if (msg.recipientPhone != null)
                          Text(
                            msg.recipientPhone!,
                            style: TextStyle(
                              fontSize: 13,
                              color: theme.colorScheme.onSurface.withOpacity(0.5),
                            ),
                          ),
                      ],
                    ),
                  ),
                  StatusBadge(status: msg.status),
                ],
              ),
              const SizedBox(height: 16),
              _DetailRow(
                label: 'النوع',
                value: MessageTypes.getArabicLabel(msg.messageType),
              ),
              _DetailRow(
                label: 'التاريخ',
                value: AppHelpers.formatDate(msg.createdAt),
              ),
              if (msg.processedAt != null)
                _DetailRow(
                  label: 'تاريخ المعالجة',
                  value: AppHelpers.formatDate(msg.processedAt),
                ),
              const Divider(height: 24),
              Text(
                'نص الرسالة',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest
                      .withOpacity(0.3),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: SelectableText(
                  msg.messageContent ?? 'لا يوجد محتوى',
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.6,
                    color: theme.colorScheme.onSurface.withOpacity(0.8),
                  ),
                ),
              ),
              if (msg.errorMessage != null && msg.errorMessage!.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.dangerColor.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: AppTheme.dangerColor.withOpacity(0.2)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.error_outline,
                          color: AppTheme.dangerColor, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _friendlyError(msg.errorMessage!),
                          style: const TextStyle(
                            fontFamily: 'Cairo',
                            color: AppTheme.dangerColor,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 16),
              if (msg.canRetry)
                ElevatedButton.icon(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    final ok = await ref
                        .read(messagesProvider.notifier)
                        .retryMessage(msg.id);
                    if (mounted) {
                      if (ok) {
                        AppSnackBar.success(context, 'تمت إعادة المحاولة');
                      } else {
                        AppSnackBar.error(context, 'فشلت إعادة المحاولة');
                      }
                    }
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text('إعادة المحاولة'),
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  String _friendlyError(String error) {
    final lower = error.toLowerCase();
    if (lower.contains('not registered') || lower.contains('not on whatsapp')) {
      return 'الرقم غير مسجّل على واتساب';
    }
    if (lower.contains('timeout') || lower.contains('timed out')) {
      return 'انتهت مهلة الإرسال';
    }
    if (lower.contains('no lid found')) {
      return 'لم يتم العثور على معرف الرقم - أعد ربط الجلسة';
    }
    if (lower.contains('disconnected') || lower.contains('not connected')) {
      return 'واتساب غير متصل';
    }
    if (lower.contains('rate limit')) {
      return 'تم تجاوز حد الإرسال - انتظر قليلاً';
    }
    return error;
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(messagesProvider);
    final theme = Theme.of(context);

    if (state.stats.pending > 0 && _autoRefreshTimer == null) {
      _startAutoRefresh();
    }

    final hasActiveFilters = state.statusFilter != null ||
        state.typeFilter != null ||
        _dateFrom != null ||
        _dateTo != null ||
        _searchController.text.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('سجل الرسائل'),
            if (state.stats.pending > 0) ...[
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.infoColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 10,
                      height: 10,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        color: AppTheme.infoColor,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'تحديث',
                      style: TextStyle(
                        fontSize: 10,
                        color: AppTheme.infoColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined),
            onPressed: _showClearDialog,
            tooltip: 'مسح السجل',
          ),
          IconButton(
            icon: Badge(
              isLabelVisible: hasActiveFilters,
              child: const Icon(Icons.filter_list),
            ),
            onPressed: _showFilterSheet,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: TextField(
              controller: _searchController,
              textDirection: TextDirection.ltr,
              textAlign: TextAlign.left,
              decoration: InputDecoration(
                hintText: 'بحث بالاسم أو الرقم أو نص الرسالة...',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          ref.read(messagesProvider.notifier).setFilters(
                                status: state.statusFilter,
                                type: state.typeFilter,
                                search: null,
                                dateFrom: _dateFrom,
                                dateTo: _dateTo,
                              );
                        },
                      )
                    : null,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onSubmitted: (val) {
                ref.read(messagesProvider.notifier).setFilters(
                      status: state.statusFilter,
                      type: state.typeFilter,
                      search: val.isNotEmpty ? val : null,
                      dateFrom: _dateFrom,
                      dateTo: _dateTo,
                    );
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _StatChip(label: 'مرسلة', count: state.stats.sent, color: Colors.green),
                _StatChip(label: 'فاشلة', count: state.stats.failed, color: Colors.red),
                _StatChip(label: 'معلقة', count: state.stats.pending, color: Colors.orange),
                _StatChip(label: 'ملغاة', count: state.stats.cancelled, color: Colors.grey),
                _StatChip(
                  label: 'الإجمالي',
                  count: state.stats.total,
                  color: theme.colorScheme.primary,
                ),
              ],
            ),
          ),
          Expanded(
            child: state.isLoading && state.messages.isEmpty
                ? const ShimmerList()
                : state.error != null && state.messages.isEmpty
                    ? EmptyState(
                        icon: Icons.error_outline,
                        title: 'حدث خطأ',
                        subtitle: state.error,
                        action: ElevatedButton.icon(
                          onPressed: () => ref.read(messagesProvider.notifier).loadMessages(refresh: true),
                          icon: const Icon(Icons.refresh),
                          label: const Text('إعادة المحاولة'),
                        ),
                      )
                    : state.messages.isEmpty
                        ? const EmptyState(
                            icon: Icons.message_outlined,
                            title: 'لا توجد رسائل',
                          )
                    : RefreshIndicator(
                        onRefresh: () => ref
                            .read(messagesProvider.notifier)
                            .loadMessages(refresh: true),
                        child: ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.only(bottom: 80),
                          itemCount:
                              state.messages.length + (state.hasMore ? 1 : 0),
                          itemBuilder: (context, index) {
                            if (index >= state.messages.length) {
                              return const Center(
                                child: Padding(
                                  padding: EdgeInsets.all(16),
                                  child: CircularProgressIndicator(),
                                ),
                              );
                            }

                            final msg = state.messages[index];
                            return Container(
                              margin: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: theme.cardTheme.color,
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: ListTile(
                                onTap: () => _showMessageDetail(msg),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 6,
                                ),
                                leading: Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: AppHelpers.getStatusColor(msg.status)
                                        .withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(
                                    AppHelpers.getMessageTypeIcon(
                                        msg.messageType),
                                    color:
                                        AppHelpers.getStatusColor(msg.status),
                                    size: 20,
                                  ),
                                ),
                                title: Text(
                                  msg.recipientUsername ?? '—',
                                  style: const TextStyle(
                                    fontFamily: 'Cairo',
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                  ),
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const SizedBox(height: 4),
                                    Text(
                                      msg.messageContent ?? '',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: theme.colorScheme.onSurface
                                            .withOpacity(0.5),
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Row(
                                      children: [
                                        StatusBadge(status: msg.status),
                                        const SizedBox(width: 8),
                                        Text(
                                          AppHelpers.formatRelative(
                                              msg.createdAt),
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: theme.colorScheme.onSurface
                                                .withOpacity(0.4),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                                trailing: msg.canRetry
                                    ? IconButton(
                                        icon: const Icon(
                                          Icons.refresh,
                                          color: Colors.orange,
                                          size: 20,
                                        ),
                                        onPressed: () async {
                                          final ok = await ref
                                              .read(messagesProvider.notifier)
                                              .retryMessage(msg.id);
                                          if (mounted) {
                                            if (ok) {
                                              AppSnackBar.success(
                                                  context, 'تمت إعادة المحاولة');
                                            } else {
                                              AppSnackBar.error(
                                                  context, 'فشلت إعادة المحاولة');
                                            }
                                          }
                                        },
                                      )
                                    : null,
                              ),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final int count;
  final Color color;

  const _StatChip({
    required this.label,
    required this.count,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          '$count',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
          ),
        ),
      ],
    );
  }
}

class _DateButton extends StatelessWidget {
  final String label;
  final String? value;
  final VoidCallback onTap;
  final VoidCallback onClear;

  const _DateButton({
    required this.label,
    this.value,
    required this.onTap,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          suffixIcon: value != null
              ? IconButton(
                  icon: const Icon(Icons.clear, size: 18),
                  onPressed: onClear,
                )
              : const Icon(Icons.calendar_today, size: 18),
        ),
        child: Text(
          value ?? '—',
          style: TextStyle(
            fontSize: 14,
            color: value != null
                ? null
                : Theme.of(context).colorScheme.onSurface.withOpacity(0.4),
          ),
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Text(
            '$label: ',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontFamily: 'Cairo', fontSize: 13, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}

