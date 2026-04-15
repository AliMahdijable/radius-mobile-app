import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/messages_provider.dart';
import '../../core/theme/app_theme.dart';

class BroadcastScreen extends ConsumerStatefulWidget {
  const BroadcastScreen({super.key});

  @override
  ConsumerState<BroadcastScreen> createState() => _BroadcastScreenState();
}

class _BroadcastScreenState extends ConsumerState<BroadcastScreen> {
  final _messageController = TextEditingController();
  String _broadcastType = 'general';

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _startBroadcast() async {
    if (_messageController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى كتابة الرسالة')),
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تأكيد البث'),
        content: Text(
          'سيتم إرسال الرسالة إلى ${_getTypeLabel(_broadcastType)}. هل تريد المتابعة؟',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('إرسال'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await ref.read(messagesProvider.notifier).startBroadcast(
            message: _messageController.text.trim(),
            type: _broadcastType,
          );
    }
  }

  String _getTypeLabel(String type) {
    switch (type) {
      case 'general':
        return 'جميع المشتركين';
      case 'debtors':
        return 'المديونين فقط';
      case 'expired':
        return 'المنتهية اشتراكاتهم فقط';
      default:
        return type;
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(messagesProvider);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final broadcast = state.broadcast;

    return Scaffold(
      appBar: AppBar(title: const Text('بث رسائل')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // Broadcast progress overlay
          if (broadcast != null && broadcast.isActive) ...[
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: theme.cardTheme.color,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: AppTheme.infoColor.withOpacity(0.3),
                ),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (broadcast.isPaused)
                        const Icon(Icons.pause_circle,
                            color: Colors.orange, size: 24)
                      else
                        const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      const SizedBox(width: 10),
                      Text(
                        broadcast.isPaused
                            ? 'توقف مؤقت (${broadcast.pauseSeconds ?? 0} ثانية)'
                            : 'جاري البث...',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: broadcast.total > 0
                          ? (broadcast.sent + broadcast.failed) /
                              broadcast.total
                          : 0,
                      minHeight: 8,
                      backgroundColor: Colors.grey.withOpacity(0.2),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _ProgressStat(
                        label: 'مرسلة',
                        value: broadcast.sent,
                        color: Colors.green,
                      ),
                      _ProgressStat(
                        label: 'فاشلة',
                        value: broadcast.failed,
                        color: Colors.red,
                      ),
                      _ProgressStat(
                        label: 'الإجمالي',
                        value: broadcast.total,
                        color: AppTheme.infoColor,
                      ),
                    ],
                  ),
                  if (broadcast.currentUser != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      'الحالي: ${broadcast.currentUser}',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () =>
                        ref.read(messagesProvider.notifier).cancelBroadcast(),
                    icon: const Icon(Icons.stop, color: Colors.red),
                    label: const Text('إيقاف البث',
                        style: TextStyle(color: Colors.red)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.red),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
          ],

          // Broadcast complete summary
          if (broadcast != null &&
              !broadcast.isActive &&
              broadcast.event == 'complete') ...[
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.1),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.green.withOpacity(0.3)),
              ),
              child: Column(
                children: [
                  const Icon(Icons.check_circle,
                      color: Colors.green, size: 40),
                  const SizedBox(height: 10),
                  const Text(
                    'اكتمل البث',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'مرسلة: ${broadcast.sent} | فاشلة: ${broadcast.failed}',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
          ],

          // Broadcast type selector
          Text(
            'نوع البث',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          ...['general', 'debtors', 'expired'].map((type) {
            final isSelected = _broadcastType == type;
            final typeIcons = {
              'general': Icons.people,
              'debtors': Icons.credit_card,
              'expired': Icons.timer_off,
            };
            final typeColors = {
              'general': AppTheme.infoColor,
              'debtors': AppTheme.warningColor,
              'expired': AppTheme.dangerColor,
            };

            return GestureDetector(
              onTap: () => setState(() => _broadcastType = type),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isSelected
                      ? typeColors[type]!.withOpacity(0.1)
                      : theme.cardTheme.color,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isSelected
                        ? typeColors[type]!.withOpacity(0.5)
                        : Colors.transparent,
                    width: 1.5,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      typeIcons[type],
                      color: typeColors[type],
                    ),
                    const SizedBox(width: 12),
                    Text(
                      _getTypeLabel(type),
                      style: TextStyle(
                        fontWeight:
                            isSelected ? FontWeight.w700 : FontWeight.w500,
                        color: isSelected
                            ? typeColors[type]
                            : theme.colorScheme.onSurface,
                      ),
                    ),
                    const Spacer(),
                    if (isSelected)
                      Icon(Icons.check_circle, color: typeColors[type]),
                  ],
                ),
              ),
            );
          }),

          const SizedBox(height: 20),

          // Message input
          Text(
            'نص الرسالة',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _messageController,
            maxLines: 6,
            decoration: const InputDecoration(
              hintText: 'اكتب رسالة البث هنا...',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 24),

          SizedBox(
            height: 52,
            child: ElevatedButton.icon(
              onPressed: (broadcast?.isActive ?? false)
                  ? null
                  : _startBroadcast,
              icon: const Icon(Icons.campaign),
              label: const Text('بدء البث'),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProgressStat extends StatelessWidget {
  final String label;
  final int value;
  final Color color;

  const _ProgressStat({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          '$value',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
          ),
        ),
      ],
    );
  }
}
