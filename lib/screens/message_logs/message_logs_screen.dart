import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../api/broadcast_api.dart';
import '../../core/widgets/design_sheet.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';

/// شاشة "حالة الرسائل" — نُقلت من v1 mobile-app/message_logs_screen.
///
/// تعرض كل رسائل WhatsApp (queue + send_logs) بغضّ النظر عن نوعها
/// (broadcast, activation, extension, debt_reminder, expiry_warning, …).
/// المدير يستعملها ليتأكد أن رسالة معيّنة أُرسلت فعلاً + يقرأ نصّها
/// كاملاً + يرى سبب الفشل + يعيد المحاولة.
///
/// الفلاتر:
///   - status: all / sent / pending / failed / cancelled
///   - type:   all / broadcast / debt_reminder / expiry_warning /
///             service_end / activation / renewal / payment
///   - search: username | phone | body
///   - نافذة زمنية اختياريّة (dateFrom/dateTo)
///
/// auto-refresh: كل 15 ثانية إذا في رسائل pending — تلقائياً يوقف
/// لمّا الكل يخلص.
class MessageLogsScreen extends StatefulWidget {
  const MessageLogsScreen({super.key});

  @override
  State<MessageLogsScreen> createState() => _MessageLogsScreenState();
}

class _MessageLogsScreenState extends State<MessageLogsScreen> {
  final _scroll = ScrollController();
  final _searchCtrl = TextEditingController();
  Timer? _autoRefresh;
  Timer? _searchDebounce;

  String _statusFilter = 'all';
  String _typeFilter = 'all';
  String _search = '';

  bool _loading = false;
  bool _hasMore = false;
  int _page = 1;
  List<MessageLog> _messages = const [];
  LogsStats? _stats;
  int _total = 0;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _load(refresh: true);
  }

  @override
  void dispose() {
    _scroll.dispose();
    _searchCtrl.dispose();
    _autoRefresh?.cancel();
    _searchDebounce?.cancel();
    super.dispose();
  }

  void _onScroll() {
    if (!_hasMore || _loading) return;
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 200) {
      _load();
    }
  }

  Future<void> _load({bool refresh = false}) async {
    if (_loading) return;
    // 2026-07-13: عند refresh (تغيير فلتر/بحث) امسح القائمة القديمة فوراً
    // — إبقاؤها ظاهرة يوهم المستخدم أن هذه نتائج الفلتر الجديد بينما هي
    // للفلتر السابق. تفريغ + spinner = feedback صريح "جاري الجلب".
    setState(() {
      _loading = true;
      if (refresh) {
        _messages = const [];
        _hasMore = false;
      }
    });
    final page = refresh ? 1 : _page;
    final r = await BroadcastApi.messageLogs(
      statusFilter: _statusFilter,
      typeFilter: _typeFilter,
      search: _search,
      page: page,
      limit: 50,
    );
    if (!mounted) return;
    setState(() {
      _messages = refresh ? r.messages : [..._messages, ...r.messages];
      _stats = r.stats;
      _total = r.total;
      _hasMore = r.hasMore;
      _page = page + 1;
      _loading = false;
    });
    // شغّل auto-refresh لو في pending
    if ((_stats?.pending ?? 0) + (_stats?.processing ?? 0) > 0) {
      _startAutoRefresh();
    } else {
      _autoRefresh?.cancel();
    }
  }

  void _startAutoRefresh() {
    _autoRefresh?.cancel();
    _autoRefresh = Timer.periodic(const Duration(seconds: 15), (_) {
      final pending = (_stats?.pending ?? 0) + (_stats?.processing ?? 0);
      if (pending > 0) {
        _load(refresh: true);
      } else {
        _autoRefresh?.cancel();
      }
    });
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 400), () {
      if (!mounted) return;
      setState(() => _search = value.trim());
      _load(refresh: true);
    });
  }

  Future<void> _retry(MessageLog m) async {
    // نستعمل نفس endpoint retry-failed مع sinceHours صغير — لو الـmsg
    // موجودة في الطابور بحالة failed رح تجدَّد لـpending.
    HapticFeedback.selectionClick();
    final r = await BroadcastApi.retryFailed(sinceHours: 1);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
            r.ok ? (r.message ?? 'أُعيدت المحاولة') : (r.message ?? 'فشل')),
        backgroundColor: r.ok ? AppColors.brand : AppColors.error,
        behavior: SnackBarBehavior.floating,
      ),
    );
    if (r.ok) _load(refresh: true);
  }

  void _showDetail(MessageLog m) {
    showModalBottomSheet(
      barrierColor: AppColors.scrim,
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(R.card)),
      ),
      builder: (_) => _MessageDetailSheet(message: m, onRetry: _retry),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        title: Text(
          'حالة الرسائل',
          style: AppType.title(color: AppColors.textHi).copyWith(fontSize: 16),
        ),
        iconTheme: IconThemeData(color: AppColors.textHi),
        actions: [
          IconButton(
            tooltip: 'تحديث',
            icon:
                Icon(LucideIcons.refreshCw, size: 18, color: AppColors.textMid),
            onPressed: _loading ? null : () => _load(refresh: true),
          ),
        ],
      ),
      body: Column(
        children: [
          _searchBar(),
          _statsRow(),
          _statusFilters(),
          _typeFilters(),
          Expanded(
            child: RefreshIndicator(
              color: AppColors.brand,
              onRefresh: () => _load(refresh: true),
              child: _messages.isEmpty && !_loading
                  ? _empty()
                  : ListView.separated(
                      controller: _scroll,
                      padding: const EdgeInsets.fromLTRB(
                          Sp.lg, Sp.sm, Sp.lg, Sp.huge),
                      itemCount: _messages.length + (_hasMore ? 1 : 0),
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, i) {
                        if (i >= _messages.length) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 16),
                            child: Center(
                              child: SizedBox(
                                width: 22,
                                height: 22,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              ),
                            ),
                          );
                        }
                        return _tile(_messages[i]);
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── UI parts ──────────────────────────────

  Widget _searchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.sm, Sp.lg, 4),
      child: TextField(
        controller: _searchCtrl,
        onChanged: _onSearchChanged,
        decoration: InputDecoration(
          hintText: 'ابحث بالاسم، رقم الهاتف، أو نصّ الرسالة…',
          hintStyle: AppType.muted().copyWith(fontSize: 12.5),
          prefixIcon:
              Icon(LucideIcons.search, size: 15, color: AppColors.textMid),
          suffixIcon: _searchCtrl.text.isEmpty
              ? null
              : IconButton(
                  icon: Icon(LucideIcons.x, size: 14, color: AppColors.textMid),
                  onPressed: () {
                    _searchCtrl.clear();
                    _onSearchChanged('');
                  },
                ),
          filled: true,
          fillColor: AppColors.surfaceInput,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(R.sm),
            borderSide: BorderSide(color: AppColors.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(R.sm),
            borderSide: BorderSide(color: AppColors.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(R.sm),
            borderSide: BorderSide(color: AppColors.brand),
          ),
        ),
        style: AppType.input(color: AppColors.textHi).copyWith(fontSize: 13),
      ),
    );
  }

  Widget _statsRow() {
    final s = _stats;
    if (s == null && _total == 0) return const SizedBox.shrink();
    final t = s?.total ?? _total;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Sp.lg, vertical: 4),
      child: Row(
        children: [
          _stat('الكل', t, AppColors.textHi),
          const SizedBox(width: 6),
          _stat('مرسلة', s?.sent ?? 0, AppColors.success),
          const SizedBox(width: 6),
          _stat('انتظار', (s?.pending ?? 0) + (s?.processing ?? 0),
              AppColors.warning),
          const SizedBox(width: 6),
          _stat('فاشلة', s?.failed ?? 0, AppColors.error),
        ],
      ),
    );
  }

  Widget _stat(String label, int value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
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
                fontSize: 15,
                fontWeight: FontWeight.w700,
                height: 1.1,
              ),
            ),
            const SizedBox(height: 1),
            Text(label, style: AppType.muted().copyWith(fontSize: 9.5)),
          ],
        ),
      ),
    );
  }

  Widget _statusFilters() {
    const filters = <(String, String)>[
      ('all', 'الكل'),
      ('sent', 'مرسلة'),
      ('pending', 'انتظار'),
      ('failed', 'فاشلة'),
      ('cancelled', 'مُلغاة'),
    ];
    return SizedBox(
      height: 30,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: Sp.lg, vertical: 2),
        children: [
          for (final (k, l) in filters) ...[
            _filterChip(
              active: _statusFilter == k,
              label: l,
              onTap: () {
                setState(() => _statusFilter = k);
                _load(refresh: true);
              },
              color: AppColors.brand,
            ),
            const SizedBox(width: 6),
          ],
        ],
      ),
    );
  }

  Widget _typeFilters() {
    // 2026-07-13: حذفنا "تمديد" (renewal) من الفلاتر بطلب المستخدم.
    // "دفع" → "تسديد" — يعرض فقط رسائل تأكيد تسديد المشترك لدينه
    // (💳 تأكيد تسديد الاشتراك). backend type=payment أصلاً محدود على
    // (%تأكيد تسديد%, %تم تسديد دفعة%) فالنتيجة دقيقة.
    const filters = <(String, String)>[
      ('all', 'كل الأنواع'),
      ('broadcast', 'تبليغ'),
      ('debt_reminder', 'تذكير دين'),
      ('expiry_warning', 'قرب انتهاء'),
      ('service_end', 'انتهاء الخدمة'),
      ('activation', 'تفعيل'),
      ('payment', 'تسديد'),
    ];
    return SizedBox(
      height: 30,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: Sp.lg, vertical: 2),
        children: [
          for (final (k, l) in filters) ...[
            _filterChip(
              active: _typeFilter == k,
              label: l,
              onTap: () {
                setState(() => _typeFilter = k);
                _load(refresh: true);
              },
              color: AppColors.brandAccent,
            ),
            const SizedBox(width: 6),
          ],
        ],
      ),
    );
  }

  Widget _filterChip({
    required bool active,
    required String label,
    required VoidCallback onTap,
    required Color color,
  }) {
    return Material(
      color: active ? color.withValues(alpha: 0.12) : AppColors.surfaceInput,
      borderRadius: BorderRadius.circular(R.pill),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          child: Center(
            child: Text(
              label,
              style: AppType.button(
                color: active ? color : AppColors.textMid,
              ).copyWith(fontSize: 11),
            ),
          ),
        ),
      ),
    );
  }

  Widget _empty() {
    return ListView(
      children: [
        SizedBox(height: MediaQuery.of(context).size.height * 0.2),
        Center(
          child: Column(
            children: [
              Icon(LucideIcons.inbox, size: 56, color: AppColors.textLow),
              const SizedBox(height: 12),
              Text('لا توجد رسائل مطابقة',
                  style: AppType.subtitle(color: AppColors.textMid)),
              const SizedBox(height: 4),
              Text('جرّب تغيير الفلاتر أو إزالة البحث',
                  style: AppType.muted().copyWith(fontSize: 11.5)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _tile(MessageLog m) {
    final (color, icon, statusText) = _statusVisual(m);
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(R.md),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _showDetail(m),
        child: Container(
          padding: const EdgeInsets.all(Sp.md),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(R.md),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(5),
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
                          _displayName(m),
                          style: AppType.title(color: AppColors.textHi)
                              .copyWith(fontSize: 13),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 1),
                        Row(
                          children: [
                            if ((m.recipientPhone ?? '').isNotEmpty)
                              Flexible(
                                child: Text(
                                  m.recipientPhone!,
                                  style: AppType.muted().copyWith(
                                    fontSize: 10.5,
                                    fontFamily: 'Cairo',
                                    fontFeatures: const [
                                      FontFeature.tabularFigures()
                                    ],
                                  ),
                                  textDirection: TextDirection.ltr,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
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
                    child: Text(
                      statusText,
                      style:
                          AppType.button(color: color).copyWith(fontSize: 10.5),
                    ),
                  ),
                ],
              ),
              if ((m.messagePreview ?? '').isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceInput,
                    borderRadius: BorderRadius.circular(R.sm),
                  ),
                  child: Text(
                    m.messagePreview!,
                    style: AppType.subtitle(color: AppColors.textMid)
                        .copyWith(fontSize: 11.5, height: 1.5),
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
                    style: AppType.muted().copyWith(fontSize: 10.5),
                  ),
                  if ((m.messageType ?? '').isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Icon(LucideIcons.tag, size: 10, color: AppColors.textLow),
                    const SizedBox(width: 3),
                    Text(
                      _typeLabel(m.messageType!),
                      style: AppType.muted().copyWith(fontSize: 10.5),
                    ),
                  ],
                  const Spacer(),
                  _channelBadge(m),
                  const SizedBox(width: 4),
                  Icon(LucideIcons.chevronLeft,
                      size: 14, color: AppColors.textLow),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── helpers ──────────────────────────────

  String _displayName(MessageLog m) {
    if ((m.recipientName ?? '').isNotEmpty) return m.recipientName!;
    if ((m.recipientUsername ?? '').isNotEmpty) return m.recipientUsername!;
    if ((m.recipientPhone ?? '').isNotEmpty) return m.recipientPhone!;
    return '—';
  }

  (Color, IconData, String) _statusVisual(MessageLog m) {
    switch (m.status) {
      case 'sent':
        return (AppColors.success, LucideIcons.check, 'أُرسلت');
      case 'pending':
        return (AppColors.warning, LucideIcons.clock, 'انتظار');
      case 'processing':
        return (AppColors.brandAccent, LucideIcons.loader, 'يُرسل الآن');
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
      case 'manual':
        return 'تبليغ';
      case 'debtors':
      case 'debt_reminder':
        return 'تذكير دين';
      case 'expired':
      case 'service_end':
        return 'انتهاء الخدمة';
      case 'expiring':
      case 'expiry_warning':
        return 'قرب انتهاء';
      case 'activation':
      case 'activation_direct':
      case 'activation_notice':
        return 'تفعيل';
      case 'renewal':
      case 'extension':
        return 'تمديد';
      case 'payment_receipt':
      case 'payment':
      case 'payment_confirmation':
        return 'تسديد';
      case 'welcome_message':
        return 'ترحيب';
      case 'subscriber_info':
        return 'معلومات';
      default:
        return t;
    }
  }

  String _formatTime(String raw) {
    final dt = DateTime.tryParse(raw)?.toLocal();
    if (dt == null) return raw;
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.isNegative) return raw;
    if (diff.inMinutes < 1) return 'الآن';
    if (diff.inMinutes < 60) return 'قبل ${diff.inMinutes}د';
    if (diff.inHours < 24) return 'قبل ${diff.inHours}س';
    if (diff.inDays < 7) return 'قبل ${diff.inDays}ي';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${dt.year}/${two(dt.month)}/${two(dt.day)} ${two(dt.hour)}:${two(dt.minute)}';
  }

  // 2026-08-26: شارة القناة (TG/WA) بجنب كل سجل — backend يعطي channel
  // من whatsapp_send_logs.channel (فعليّ) أو whatsapp_message_queue.channel
  // (قد يكون auto لسّه ما اتّحدد).
  Widget _channelBadge(MessageLog m) {
    final ch = (m.channel ?? '').toLowerCase();
    if (ch != 'telegram' && ch != 'whatsapp') {
      return const SizedBox.shrink();
    }
    final isTg = ch == 'telegram';
    final color = isTg ? const Color(0xFF229ED9) : const Color(0xFF25D366);
    final icon = isTg ? LucideIcons.send : LucideIcons.messageCircle;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(R.sm),
        border: Border.all(color: color.withValues(alpha: 0.4), width: 0.5),
      ),
      child: Icon(icon, size: 10, color: color),
    );
  }
}

/// Bottom sheet لعرض الرسالة كاملة + retry + نسخ.
class _MessageDetailSheet extends StatelessWidget {
  const _MessageDetailSheet({required this.message, required this.onRetry});
  final MessageLog message;
  final Future<void> Function(MessageLog) onRetry;

  @override
  Widget build(BuildContext context) {
    return DesignSheet(
      header: SheetHeaderBar(
        icon: LucideIcons.messageSquare,
        title: 'تفاصيل الرسالة',
        subtitle: '',
        onClose: () => Navigator.of(context).pop(),
      ),
      scrollable: false,
      bodyPadding: EdgeInsets.zero,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Sp.xl, Sp.lg, Sp.xl, Sp.xxl),
        children: [
          const SizedBox(height: 12),
          _row('المستلم',
              message.recipientName ?? message.recipientUsername ?? '—'),
          if ((message.recipientPhone ?? '').isNotEmpty)
            _row('الهاتف', message.recipientPhone!, mono: true),
          if ((message.recipientUsername ?? '').isNotEmpty &&
              (message.recipientName ?? '').isNotEmpty)
            _row('اسم المستخدم', message.recipientUsername!, mono: true),
          _row('الحالة', _statusText(message.status)),
          if ((message.messageType ?? '').isNotEmpty)
            _row('النوع', _typeLabel(message.messageType!)),
          _row('التاريخ', _formatFullDateTime(message.createdAt)),
          if (message.isFailed && (message.errorMessage ?? '').isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.dangerSoftBg,
                borderRadius: BorderRadius.circular(R.sm),
                border: Border.all(color: AppColors.dangerSoftBorder),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(LucideIcons.triangleAlert,
                      size: 14, color: AppColors.error),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      message.errorMessage!,
                      style: AppType.subtitle(color: AppColors.error)
                          .copyWith(fontSize: 12.5),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 12),
          Text(
            'نصّ الرسالة',
            style: AppType.label(color: AppColors.textMid)
                .copyWith(fontSize: 12.5),
          ),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.surfaceInput,
              borderRadius: BorderRadius.circular(R.sm),
              border: Border.all(color: AppColors.border),
            ),
            child: SelectableText(
              (message.messagePreview ?? '').isEmpty
                  ? '—'
                  : message.messagePreview!,
              style: AppType.input(color: AppColors.textHi)
                  .copyWith(fontSize: 13, height: 1.6),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    Clipboard.setData(
                        ClipboardData(text: message.messagePreview ?? ''));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: const Text('تمّ نسخ النصّ'),
                        backgroundColor: AppColors.brand,
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
                  icon: const Icon(LucideIcons.copy, size: 14),
                  label: const Text('نسخ النصّ'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textMid,
                    side: BorderSide(color: AppColors.border),
                  ),
                ),
              ),
              if (message.isFailed) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      Navigator.of(context).pop();
                      await onRetry(message);
                    },
                    icon: const Icon(LucideIcons.rotateCw, size: 14),
                    label: const Text('إعادة المحاولة'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.warning,
                      foregroundColor: AppColors.onBrand,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _row(String label, String value, {bool mono = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 82,
            child: Text(label, style: AppType.muted().copyWith(fontSize: 11.5)),
          ),
          Expanded(
            child: Text(
              value,
              style: AppType.subtitle(color: AppColors.textHi).copyWith(
                fontSize: 12.5,
                fontFamily: 'Cairo',
                fontFeatures:
                    mono ? const [FontFeature.tabularFigures()] : null,
              ),
              textDirection: mono ? TextDirection.ltr : null,
            ),
          ),
        ],
      ),
    );
  }

  String _statusText(String s) {
    switch (s) {
      case 'sent':
        return 'أُرسلت';
      case 'pending':
        return 'انتظار';
      case 'processing':
        return 'يُرسل الآن';
      case 'failed':
        return 'فشل';
      case 'cancelled':
        return 'مُلغى';
      default:
        return s;
    }
  }

  // نسخة مطابقة لـ _MessageLogsScreenState._typeLabel — نُكرّرها هنا لأن
  // الأخرى private. تعرض label بدل message_type الخام (payment_confirmation
  // → "تسديد" مثلاً).
  String _typeLabel(String t) {
    switch (t) {
      case 'general':
      case 'broadcast':
      case 'manual':
        return 'تبليغ';
      case 'debtors':
      case 'debt_reminder':
        return 'تذكير دين';
      case 'expired':
      case 'service_end':
        return 'انتهاء الخدمة';
      case 'expiring':
      case 'expiry_warning':
        return 'قرب انتهاء';
      case 'activation':
      case 'activation_direct':
      case 'activation_notice':
        return 'تفعيل';
      case 'renewal':
      case 'extension':
        return 'تمديد';
      case 'payment_receipt':
      case 'payment':
      case 'payment_confirmation':
        return 'تسديد';
      case 'welcome_message':
        return 'ترحيب';
      case 'subscriber_info':
        return 'معلومات';
      default:
        return t;
    }
  }

  /// ISO string → "YYYY/MM/DD HH:mm صباحاً/مساءً" بتوقيت الجهاز.
  /// الـbackend يرسل createdAt بصيغة `2026-07-08T19:08:42.000Z` — العرض
  /// الخام غير مفهوم للمستخدم فنحوّله لتاريخ محلي مع 12h + إشارة ص/م.
  String _formatFullDateTime(String raw) {
    final dt = DateTime.tryParse(raw)?.toLocal();
    if (dt == null) return raw;
    String two(int n) => n.toString().padLeft(2, '0');
    final h24 = dt.hour;
    final h12 = h24 == 0 ? 12 : (h24 > 12 ? h24 - 12 : h24);
    final ampm = h24 >= 12 ? 'مساءً' : 'صباحاً';
    return '${dt.year}/${two(dt.month)}/${two(dt.day)} '
        '${two(h12)}:${two(dt.minute)} $ampm';
  }
}
