import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../api/dashboard_api.dart';
import '../../api/subscribers_api.dart';
import '../../models/app_notification.dart';
import '../../models/subscriber.dart';
import '../../services/inbox_service.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import '../subscribers/subscriber_detail_screen.dart';
import '../subscribers/widgets/filter_chips_bar.dart';

/// شاشة inbox — الإشعارات الذكية (قريب الانتهاء / منتهي) + قائمة
/// إشعارات FCM المستلمة مجمّعة يومياً.
///
/// - **بطاقات ذكية** بأعلى الشاشة: تعرض عدد المشتركين قربوا للانتهاء
///   والمنتهين، مع tap يفتح شاشة المشتركين بالفلتر المناسب.
/// - **قائمة FCM**: الإشعارات المستلمة من backend عبر Firebase.
/// - Swipe لحذف صف واحد.
/// - AppBar action لتعليم الكل كمقروء.
class InboxScreen extends StatefulWidget {
  const InboxScreen({
    super.key,
    this.onTapNotification,
    this.onOpenSubscribersFilter,
  });

  final void Function(AppNotification n)? onTapNotification;

  /// callback يفتح صفحة المشتركين بفلتر معيّن. لو null، البطاقات
  /// الذكية (قربوا الانتهاء / منتهي) تختفي.
  final void Function(SubscriberFilter)? onOpenSubscribersFilter;

  @override
  State<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends State<InboxScreen> {
  int _nearExpiryCount = 0;
  int _expiredCount = 0;
  bool _countsLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadCounts();
  }

  Future<void> _loadCounts() async {
    final r = await DashboardApi.fetchDebtors();
    if (!mounted) return;
    setState(() {
      // مطلب المستخدم 2026-07-11: "قربوا الانتهاء" هنا يعني كل مشترك
      // متبقّي له أقل من 24 ساعة (دقيقة/ثانية) — حتى ينتهي فيختفي.
      // نستعمل expiringToday (< 24h) بدل nearExpiry (1..3 days).
      _nearExpiryCount = r?.expiringToday ?? 0;
      _expiredCount = r?.expired ?? 0;
      _countsLoaded = true;
    });
  }

  void _openSubscribersFilter(SubscriberFilter f) {
    // نُغلق الـInboxScreen ثم نُنبّه MainShell (عبر callback) لفتح
    // شاشة المشتركين مع الفلتر المطلوب. هيك ما نحتاج route stack عميق.
    Navigator.of(context).pop();
    widget.onOpenSubscribersFilter?.call(f);
  }

  /// عند النقر على إشعار: لو الـpayload يحمل اسم مشترك محدد
  /// (`username` / `subscriber_username` / `subscriber_id`)، نفتح كارت
  /// المشترك مباشرة — كأن المستخدم بحث عنه من overlay البحث. لو ما
  /// عندنا هوية، نستخدم onTapNotification callback الخارجي (fallback).
  Future<void> _handleNotificationTap(AppNotification n) async {
    InboxService.markRead(n.id);
    final username = _extractUsername(n);
    if (username != null && username.isNotEmpty) {
      final sub = await _findSubscriber(username);
      if (!mounted) return;
      if (sub != null) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => SubscriberDetailScreen(sub: sub),
            fullscreenDialog: true,
          ),
        );
        return;
      }
    }
    // Fallback: لا نعرف مشترك محدد → مرّر للـcallback الخارجي (لو موجود).
    widget.onTapNotification?.call(n);
  }

  /// نبحث في payload عن أشهر الـkeys اللي backend يمرّرها لتحديد
  /// المشترك. تُعاد قيمة string غير فارغة أو null.
  String? _extractUsername(AppNotification n) {
    for (final k in const [
      'subscriber_username',
      'username',
      'subscriber',
      'user',
      'subscriber_id',
    ]) {
      final v = n.data[k]?.trim();
      if (v != null && v.isNotEmpty) return v;
    }
    return null;
  }

  Future<Subscriber?> _findSubscriber(String usernameOrId) async {
    final list = await SubscribersApi.loadAll();
    if (list == null) return null;
    final needle = usernameOrId.toLowerCase();
    for (final s in list) {
      if (s.username.toLowerCase() == needle) return s;
    }
    // Fallback بالـidx لو الـpayload id بدل username.
    for (final s in list) {
      if (s.idx == usernameOrId) return s;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          'الإشعارات',
          style: AppType.title(color: AppColors.textHi).copyWith(fontSize: 16),
        ),
        iconTheme: IconThemeData(color: AppColors.textHi),
        actions: [
          ValueListenableBuilder<int>(
            valueListenable: InboxService.changes,
            builder: (context, _, __) {
              final unread = InboxService.unreadCount;
              if (unread == 0) return const SizedBox.shrink();
              return TextButton.icon(
                onPressed: () => InboxService.markAllRead(),
                icon: Icon(LucideIcons.checkCheck,
                    size: 16, color: AppColors.brand),
                label: Text(
                  'الكل مقروء',
                  style: TextStyle(
                    color: AppColors.brand,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadCounts,
          color: AppColors.brand,
          child: ValueListenableBuilder<int>(
            valueListenable: InboxService.changes,
            builder: (context, _, __) {
              final items = InboxService.all;
              return ListView(
                padding:
                    const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, Sp.huge),
                children: [
                  _smartCards(),
                  if (items.isEmpty) ...[
                    const SizedBox(height: Sp.md),
                    _empty(),
                  ] else ...[
                    const SizedBox(height: Sp.lg),
                    Padding(
                      padding:
                          const EdgeInsets.only(right: 4, bottom: 6),
                      child: Text(
                        'الرسائل المستلمة',
                        style: AppType.label(color: AppColors.textMid)
                            .copyWith(
                                fontSize: 11,
                                fontWeight: FontWeight.w700),
                      ),
                    ),
                    ..._buildGroups(items),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  // ────────────────────────────────────────────
  // Smart cards — قربوا للانتهاء + المنتهين
  Widget _smartCards() {
    // لو ما فيه callback للـfilter، نُخفي البطاقات (مؤشّر إن الشاشة
    // ما تعرف كيف تنقل — نمنع confusion).
    if (widget.onOpenSubscribersFilter == null) {
      return const SizedBox.shrink();
    }
    return Row(
      children: [
        Expanded(
          child: _SmartCard(
            icon: LucideIcons.alarmClock,
            label: 'قربوا الانتهاء',
            count: _nearExpiryCount,
            color: const Color(0xFFE08F2D),
            loading: !_countsLoaded,
            onTap: () => _openSubscribersFilter(SubscriberFilter.nearExpiry),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _SmartCard(
            icon: LucideIcons.circleAlert,
            label: 'منتهي',
            count: _expiredCount,
            color: AppColors.error,
            loading: !_countsLoaded,
            onTap: () => _openSubscribersFilter(SubscriberFilter.expired),
          ),
        ),
      ],
    );
  }

  List<Widget> _buildGroups(List<AppNotification> items) {
    final groups = _groupByDay(items);
    final widgets = <Widget>[];
    for (int gi = 0; gi < groups.length; gi++) {
      final g = groups[gi];
      widgets.add(Padding(
        padding: EdgeInsets.only(
            top: gi == 0 ? 0 : Sp.md, bottom: 6, right: 4),
        child: Text(
          g.label,
          style: AppType.label(color: AppColors.textMid)
              .copyWith(fontSize: 11, fontWeight: FontWeight.w700),
        ),
      ));
      for (final n in g.items) {
        widgets.add(Dismissible(
          key: ValueKey(n.id),
          direction: DismissDirection.endToStart,
          onDismissed: (_) => InboxService.remove(n.id),
          background: Container(
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: AppColors.error.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(R.md),
            ),
            child: Icon(LucideIcons.trash2,
                size: 18, color: AppColors.error),
          ),
          child: _NotificationRow(
            n: n,
            onTap: () => _handleNotificationTap(n),
          ),
        ));
        widgets.add(const SizedBox(height: 4));
      }
    }
    return widgets;
  }

  Widget _empty() => Padding(
        padding: const EdgeInsets.symmetric(vertical: Sp.huge),
        child: Center(
          child: Column(
            children: [
              Icon(LucideIcons.bellOff, size: 40, color: AppColors.textLow),
              const SizedBox(height: 12),
              Text('لا توجد إشعارات جديدة',
                  style: AppType.label(color: AppColors.textMid)),
              const SizedBox(height: 4),
              Text('ستظهر الرسائل هنا عند وصولها',
                  style: AppType.muted().copyWith(fontSize: 12)),
            ],
          ),
        ),
      );

  List<_Group> _groupByDay(List<AppNotification> items) {
    final today = DateTime.now();
    final todayStart = DateTime(today.year, today.month, today.day);
    final yStart = todayStart.subtract(const Duration(days: 1));
    final map = <String, List<AppNotification>>{};
    final order = <String>[];
    for (final n in items) {
      final at = n.receivedAt;
      String label;
      if (at.isAfter(todayStart) || at.isAtSameMomentAs(todayStart)) {
        label = 'اليوم';
      } else if (at.isAfter(yStart) || at.isAtSameMomentAs(yStart)) {
        label = 'أمس';
      } else {
        label =
            '${at.year}-${at.month.toString().padLeft(2, '0')}-${at.day.toString().padLeft(2, '0')}';
      }
      if (!map.containsKey(label)) {
        map[label] = <AppNotification>[];
        order.add(label);
      }
      map[label]!.add(n);
    }
    return [
      for (final l in order) _Group(label: l, items: map[l]!),
    ];
  }
}

// ────────────────────────────────────────────
// Smart card widget
class _SmartCard extends StatelessWidget {
  const _SmartCard({
    required this.icon,
    required this.label,
    required this.count,
    required this.color,
    required this.loading,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final int count;
  final Color color;
  final bool loading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(R.md),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(R.md),
        child: Container(
          padding: const EdgeInsets.all(Sp.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(R.md),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(R.sm),
                    ),
                    child: Icon(icon, size: 15, color: color),
                  ),
                  const Spacer(),
                  Icon(LucideIcons.chevronLeft,
                      size: 16, color: AppColors.textLow),
                ],
              ),
              const SizedBox(height: Sp.sm),
              if (loading)
                SizedBox(
                  height: 22,
                  width: 30,
                  child: Center(
                    child: SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation(color),
                      ),
                    ),
                  ),
                )
              else
                Text(
                  '$count',
                  style: TextStyle(
                    color: color,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.5,
                    height: 1,
                  ),
                ),
              const SizedBox(height: 2),
              Text(
                label,
                style: AppType.muted(color: AppColors.textMid)
                    .copyWith(fontSize: 11.5, fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Group {
  const _Group({required this.label, required this.items});
  final String label;
  final List<AppNotification> items;
}

class _NotificationRow extends StatelessWidget {
  const _NotificationRow({required this.n, required this.onTap});
  final AppNotification n;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final meta = _metaFor(n.kind);
    return Material(
      color: n.isRead
          ? AppColors.surface
          : AppColors.brand.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(R.md),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(R.md),
        child: Container(
          padding: const EdgeInsets.all(Sp.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(R.md),
            border: Border.all(
              color: n.isRead
                  ? AppColors.border
                  : AppColors.brand.withValues(alpha: 0.30),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: meta.color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(R.sm),
                ),
                child: Icon(meta.icon, size: 16, color: meta.color),
              ),
              const SizedBox(width: Sp.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            n.title.isEmpty ? meta.fallbackTitle : n.title,
                            style: AppType.label(color: AppColors.textHi)
                                .copyWith(
                                  fontSize: 13,
                                  fontWeight: n.isRead
                                      ? FontWeight.w700
                                      : FontWeight.w900,
                                ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (!n.isRead)
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: AppColors.brand,
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
                    if (n.body.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        n.body,
                        style: AppType.muted(color: AppColors.textMid)
                            .copyWith(fontSize: 12, height: 1.4),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: 6),
                    Text(
                      _formatTime(n.receivedAt),
                      style:
                          AppType.muted().copyWith(fontSize: 10.5, height: 1),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static _KindMeta _metaFor(NotificationKind k) {
    switch (k) {
      case NotificationKind.nearExpiryDigest:
        return _KindMeta(
          icon: LucideIcons.alarmClock,
          color: const Color(0xFFE08F2D),
          fallbackTitle: 'اقتراب انتهاء اشتراكات',
        );
      case NotificationKind.expiredTodayDigest:
        return _KindMeta(
          icon: LucideIcons.circleAlert,
          color: AppColors.error,
          fallbackTitle: 'اشتراكات منتهية اليوم',
        );
      case NotificationKind.managerDebt:
        return _KindMeta(
          icon: LucideIcons.creditCard,
          color: AppColors.error,
          fallbackTitle: 'دين مدير فرعي',
        );
      case NotificationKind.managerBalance:
        return _KindMeta(
          icon: LucideIcons.banknote,
          color: const Color(0xFF14B8A6),
          fallbackTitle: 'تحديث رصيد مدير',
        );
      case NotificationKind.other:
        return _KindMeta(
          icon: LucideIcons.bell,
          color: AppColors.brand,
          fallbackTitle: 'إشعار',
        );
    }
  }

  static String _formatTime(DateTime dt) {
    String p(int v) => v.toString().padLeft(2, '0');
    return '${dt.year}-${p(dt.month)}-${p(dt.day)} ${p(dt.hour)}:${p(dt.minute)}';
  }
}

class _KindMeta {
  const _KindMeta({
    required this.icon,
    required this.color,
    required this.fallbackTitle,
  });
  final IconData icon;
  final Color color;
  final String fallbackTitle;
}
