import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/messages_provider.dart';
import '../../core/constants/app_constants.dart';
import '../../core/utils/helpers.dart';
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
    super.dispose();
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
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
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
                children: [
                  _buildFilterOption(
                    'الكل',
                    null,
                    selectedStatus,
                    (v) => setSheetState(() => selectedStatus = v),
                  ),
                  ...['sent', 'failed', 'pending', 'cancelled'].map(
                    (s) => _buildFilterOption(
                      MessageStatuses.getArabicLabel(s),
                      s,
                      selectedStatus,
                      (v) => setSheetState(() => selectedStatus = v),
                    ),
                  ),
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
                  _buildFilterOption(
                    'الكل',
                    null,
                    selectedType,
                    (v) => setSheetState(() => selectedType = v),
                  ),
                  ...['debt_reminder', 'expiry_warning', 'broadcast',
                       'manual', 'activation_notice']
                      .map(
                    (t) => _buildFilterOption(
                      MessageTypes.getArabicLabel(t),
                      t,
                      selectedType,
                      (v) => setSheetState(() => selectedType = v),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () {
                  ref.read(messagesProvider.notifier).setFilters(
                        status: selectedStatus,
                        type: selectedType,
                      );
                  Navigator.pop(ctx);
                },
                child: const Text('تطبيق'),
              ),
              const SizedBox(height: 10),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilterOption(
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

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(messagesProvider);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('سجل الرسائل'),
        actions: [
          IconButton(
            icon: Badge(
              isLabelVisible:
                  state.statusFilter != null || state.typeFilter != null,
              child: const Icon(Icons.filter_list),
            ),
            onPressed: _showFilterSheet,
          ),
        ],
      ),
      body: Column(
        children: [
          // Stats bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _StatChip(
                  label: 'مرسلة',
                  count: state.stats.sent,
                  color: Colors.green,
                ),
                _StatChip(
                  label: 'فاشلة',
                  count: state.stats.failed,
                  color: Colors.red,
                ),
                _StatChip(
                  label: 'معلقة',
                  count: state.stats.pending,
                  color: Colors.orange,
                ),
                _StatChip(
                  label: 'ملغاة',
                  count: state.stats.cancelled,
                  color: Colors.grey,
                ),
              ],
            ),
          ),

          Expanded(
            child: state.isLoading && state.messages.isEmpty
                ? const ShimmerList()
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
                          itemCount: state.messages.length +
                              (state.hasMore ? 1 : 0),
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
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 6,
                                ),
                                leading: Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: AppHelpers.getStatusColor(
                                            msg.status)
                                        .withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(
                                    AppHelpers.getMessageTypeIcon(
                                        msg.messageType),
                                    color: AppHelpers.getStatusColor(
                                        msg.status),
                                    size: 20,
                                  ),
                                ),
                                title: Text(
                                  msg.recipientUsername ?? '—',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                  ),
                                ),
                                subtitle: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
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
                                            color: theme
                                                .colorScheme.onSurface
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
                                              .read(messagesProvider
                                                  .notifier)
                                              .retryMessage(msg.id);
                                          if (mounted) {
                                            if (ok) {
                                              AppSnackBar.success(context, 'تمت إعادة المحاولة');
                                            } else {
                                              AppSnackBar.error(context, 'فشلت إعادة المحاولة');
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
            fontSize: 18,
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
