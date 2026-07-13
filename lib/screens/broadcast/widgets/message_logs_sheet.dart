import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../api/broadcast_api.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';

/// Bottom sheet: يعرض آخر ~100 رسالة (queue + send_logs) لآخر 24 ساعة
/// مع فلتر حسب intent وحالة (sent/pending/failed/cancelled).
Future<void> showMessageLogsSheet(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => const _LogsSheet(),
  );
}

class _LogsSheet extends StatefulWidget {
  const _LogsSheet();

  @override
  State<_LogsSheet> createState() => _LogsSheetState();
}

class _LogsSheetState extends State<_LogsSheet> {
  String _typeFilter = 'all';
  String _statusFilter = 'all';
  bool _loading = true;
  List<MessageLog> _messages = const [];
  LogsStats? _stats;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final r = await BroadcastApi.messageLogs(typeFilter: _typeFilter);
    if (!mounted) return;
    setState(() {
      _messages = r.messages;
      _stats = r.stats;
      _loading = false;
    });
  }

  List<MessageLog> get _visible {
    if (_statusFilter == 'all') return _messages;
    return _messages.where((m) => m.status == _statusFilter).toList();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (_, scrollController) => Column(
        children: [
          _grabber(),
          _header(),
          _statsRow(),
          _statusFilterBar(),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _visible.isEmpty
                    ? _empty()
                    : ListView.separated(
                        controller: scrollController,
                        padding: const EdgeInsets.symmetric(
                            horizontal: Sp.lg, vertical: Sp.md),
                        itemCount: _visible.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (_, i) => _tile(_visible[i]),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _grabber() => Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 4),
        child: Container(
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: AppColors.borderStrong,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      );

  Widget _header() => Padding(
        padding: const EdgeInsets.fromLTRB(Sp.lg, 6, Sp.lg, 6),
        child: Row(
          children: [
            Icon(LucideIcons.history, size: 16, color: AppColors.brand),
            const SizedBox(width: 8),
            Text(
              'حالة الإرسال (آخر 24 ساعة)',
              style: AppType.title(color: AppColors.textHi)
                  .copyWith(fontSize: 14),
            ),
            const Spacer(),
            IconButton(
              tooltip: 'تحديث',
              onPressed: _loading ? null : _load,
              icon: Icon(LucideIcons.refreshCw,
                  size: 16, color: AppColors.textMid),
            ),
            IconButton(
              tooltip: 'إغلاق',
              onPressed: () => Navigator.of(context).pop(),
              icon: Icon(LucideIcons.x, size: 18, color: AppColors.textMid),
            ),
          ],
        ),
      );

  Widget _statsRow() {
    final s = _stats;
    if (s == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Sp.lg, vertical: 4),
      child: Row(
        children: [
          _statCell('الكل', s.total, AppColors.textHi),
          const SizedBox(width: 6),
          _statCell('مرسلة', s.sent, const Color(0xFF14B8A6)),
          const SizedBox(width: 6),
          _statCell('انتظار', s.pending + s.processing,
              const Color(0xFFE08F2D)),
          const SizedBox(width: 6),
          _statCell('فاشلة', s.failed, AppColors.error),
        ],
      ),
    );
  }

  Widget _statCell(String label, int value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(R.sm),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$value',
              style: AppType.title(color: color).copyWith(
                  fontSize: 15, fontWeight: FontWeight.w800, height: 1.1),
            ),
            const SizedBox(height: 1),
            Text(
              label,
              style: AppType.muted().copyWith(fontSize: 9.5),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusFilterBar() {
    const filters = <(String, String)>[
      ('all', 'الكل'),
      ('sent', 'مرسل'),
      ('pending', 'انتظار'),
      ('failed', 'فشل'),
      ('cancelled', 'مُلغى'),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Sp.lg, vertical: 6),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final (key, label) in filters) ...[
              _chip(key, label),
              const SizedBox(width: 6),
            ],
          ],
        ),
      ),
    );
  }

  Widget _chip(String key, String label) {
    final active = _statusFilter == key;
    return Material(
      color: active
          ? AppColors.brand.withValues(alpha: 0.12)
          : AppColors.surfaceInput,
      borderRadius: BorderRadius.circular(R.pill),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => setState(() => _statusFilter = key),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Text(
            label,
            style: AppType.button(
              color: active ? AppColors.brand : AppColors.textMid,
            ).copyWith(fontSize: 11.5),
          ),
        ),
      ),
    );
  }

  Widget _empty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.inbox, size: 48, color: AppColors.textLow),
          const SizedBox(height: 12),
          Text('لا توجد رسائل مطابقة',
              style: AppType.subtitle(color: AppColors.textMid)),
        ],
      ),
    );
  }

  Widget _tile(MessageLog m) {
    final (color, icon, statusText) = _statusVisual(m);
    return Container(
      padding: const EdgeInsets.all(Sp.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(R.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 12, color: color),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      m.recipientName ?? m.recipientUsername ?? '—',
                      style: AppType.title(color: AppColors.textHi)
                          .copyWith(fontSize: 12.5),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 1),
                    Text(
                      m.recipientPhone ?? '',
                      style: AppType.muted().copyWith(
                          fontSize: 10.5, fontFamily: 'monospace'),
                      textDirection: TextDirection.ltr,
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(R.sm),
                  border: Border.all(
                      color: color.withValues(alpha: 0.25), width: 0.5),
                ),
                child: Text(statusText,
                    style: AppType.button(color: color)
                        .copyWith(fontSize: 10)),
              ),
            ],
          ),
          if ((m.messagePreview ?? '').isNotEmpty) ...[
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                  horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.surfaceInput,
                borderRadius: BorderRadius.circular(R.sm),
              ),
              child: Text(
                m.messagePreview!,
                style: AppType.subtitle(color: AppColors.textMid)
                    .copyWith(fontSize: 11.5, height: 1.4),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
          if (m.isFailed && (m.errorMessage ?? '').isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(LucideIcons.triangleAlert,
                    size: 11, color: AppColors.error),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    m.errorMessage!,
                    style: AppType.muted(color: AppColors.error)
                        .copyWith(fontSize: 10.5),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(LucideIcons.clock, size: 10, color: AppColors.textLow),
              const SizedBox(width: 3),
              Text(
                _formatTime(m.createdAt),
                style: AppType.muted().copyWith(fontSize: 10),
              ),
              if ((m.messageType ?? '').isNotEmpty) ...[
                const SizedBox(width: 8),
                Icon(LucideIcons.tag, size: 10, color: AppColors.textLow),
                const SizedBox(width: 3),
                Text(
                  _typeLabel(m.messageType!),
                  style: AppType.muted().copyWith(fontSize: 10),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  (Color, IconData, String) _statusVisual(MessageLog m) {
    switch (m.status) {
      case 'sent':
        return (const Color(0xFF14B8A6), LucideIcons.check, 'أُرسلت');
      case 'pending':
      case 'processing':
        return (const Color(0xFFE08F2D), LucideIcons.clock, 'انتظار');
      case 'failed':
        return (AppColors.error, LucideIcons.x, 'فشل');
      case 'cancelled':
        return (AppColors.textLow, LucideIcons.ban, 'مُلغى');
      default:
        return (AppColors.textLow, LucideIcons.circleHelp, m.status);
    }
  }

  String _typeLabel(String t) {
    switch (t) {
      case 'general':
      case 'broadcast':
        return 'عامة';
      case 'debtors':
      case 'debt_reminder':
        return 'ديون';
      case 'expired':
        return 'منتهي';
      case 'expiring':
        return 'قرب انتهاء';
      case 'activation':
        return 'تفعيل';
      case 'extension':
        return 'تمديد';
      case 'payment_receipt':
        return 'وصل دفع';
      default:
        return t;
    }
  }

  String _formatTime(String raw) {
    final dt = DateTime.tryParse(raw)?.toLocal();
    if (dt == null) return raw;
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'الآن';
    if (diff.inMinutes < 60) return 'قبل ${diff.inMinutes}د';
    if (diff.inHours < 24) return 'قبل ${diff.inHours}س';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${dt.year}/${two(dt.month)}/${two(dt.day)} ${two(dt.hour)}:${two(dt.minute)}';
  }
}
