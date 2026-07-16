import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../api/subscribers_api.dart';
import '../../models/app_notification.dart';
import '../../models/subscriber.dart';
import '../../services/alerts_service.dart';
import '../../services/inbox_service.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import '../subscribers/subscriber_detail_screen.dart';

/// شاشة inbox — تعرض 3 أقسام (نفس منطق v1 mobile-app):
///   1. **إشعارات التطبيق** — FCM inbox items (المستلمة).
///   2. **انتهى اليوم** — قائمة مشتركين انتهى اشتراكهم اليوم (name+detail،
///      tap يفتح كارت المشترك).
///   3. **قريب الانتهاء** — قائمة مشتركين متبقّي لهم 0..3 أيام
///      (مطلوب من المستخدم 2026-07-11: يظهروا لغاية ما ينتهي اشتراكهم).
/// كل صف مشترك قابل للنقر ويفتح SubscriberDetailScreen مثل v1.
class InboxScreen extends StatefulWidget {
  const InboxScreen({super.key, this.onTapNotification});

  /// callback خارجي عند النقر على إشعار FCM: يُستدعى فقط لو ما نعرف
  /// مشترك محدد من payload (لو نعرفه، نفتح كارته مباشرة).
  final void Function(AppNotification n)? onTapNotification;

  @override
  State<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends State<InboxScreen> {
  List<Subscriber> _expiredToday = const [];
  List<Subscriber> _nearExpiry = const [];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _loadLists();
  }

  Future<void> _loadLists() async {
    final list = await SubscribersApi.loadAllWithOnline();
    if (!mounted) return;
    if (list == null) {
      setState(() => _loaded = true);
      return;
    }
    // منطق 2026-07-11:
    // • expiredToday = expDay == today && expDate.isBefore(now)
    // • nearExpiry = متبقّي < 24 ساعة (حتى دقيقة/ثانية) && لم ينتهِ بعد.
    //   المستخدم يريد بالضبط < 24h — يختفي فور الانتهاء.
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final expiredToday = <Subscriber>[];
    final nearExpiry = <Subscriber>[];
    for (final s in list) {
      final exp = s.parsedExpiration;
      if (exp == null) continue;
      final expDay = DateTime(exp.year, exp.month, exp.day);
      if (expDay == today && exp.isBefore(now)) {
        expiredToday.add(s);
        continue;
      }
      if (exp.isAfter(now) && exp.difference(now).inHours < 24) {
        nearExpiry.add(s);
      }
    }
    // فرز تصاعدي حسب المتبقّي الفعلي (بالثواني) — أقرب مشترك للانتهاء
    // يظهر أوّلاً.
    nearExpiry.sort((a, b) {
      final ea = a.parsedExpiration!;
      final eb = b.parsedExpiration!;
      return ea.compareTo(eb);
    });
    // اتّفاق مع الجرس فوق الـDashboard على نفس العدّاد.
    AlertsService.updateFrom(list);
    setState(() {
      _expiredToday = expiredToday;
      _nearExpiry = nearExpiry;
      _loaded = true;
    });
  }

  void _openSubscriber(Subscriber s) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SubscriberDetailScreen(sub: s),
        fullscreenDialog: true,
      ),
    );
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
    final list = await SubscribersApi.loadAllWithOnline();
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
          'notifications.title'.tr(),
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
                  'notifications.mark_all_read'.tr(),
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
          onRefresh: _loadLists,
          color: AppColors.brand,
          child: ValueListenableBuilder<int>(
            valueListenable: InboxService.changes,
            builder: (context, _, __) {
              final items = InboxService.all;
              final hasApp = items.isNotEmpty;
              final hasExpiredToday = _expiredToday.isNotEmpty;
              final hasNearExpiry = _nearExpiry.isNotEmpty;
              final allEmpty =
                  _loaded && !hasApp && !hasExpiredToday && !hasNearExpiry;
              return ListView(
                padding:
                    const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, Sp.huge),
                children: [
                  if (hasApp) ...[
                    _SectionHeader(
                      title: 'notifications.app_notifications'.tr(),
                      count: items.length,
                      color: AppColors.brand,
                      icon: LucideIcons.bell,
                    ),
                    ..._buildGroups(items),
                    const SizedBox(height: Sp.md),
                  ],
                  if (hasExpiredToday) ...[
                    _SectionHeader(
                      title: 'notifications.expired_today'.tr(),
                      count: _expiredToday.length,
                      color: AppColors.error,
                      icon: LucideIcons.circleAlert,
                    ),
                    for (final s in _expiredToday) ...[
                      _SubscriberAlertRow(
                        sub: s,
                        detail: 'notifications.sub_expired_today'.tr(),
                        color: AppColors.error,
                        icon: LucideIcons.timerOff,
                        onTap: () => _openSubscriber(s),
                      ),
                      const SizedBox(height: 4),
                    ],
                    const SizedBox(height: Sp.md),
                  ],
                  if (hasNearExpiry) ...[
                    _SectionHeader(
                      title: 'notifications.near_expiry_section'.tr(),
                      count: _nearExpiry.length,
                      color: const Color(0xFFE08F2D),
                      icon: LucideIcons.triangleAlert,
                    ),
                    for (final s in _nearExpiry) ...[
                      _SubscriberAlertRow(
                        sub: s,
                        detail: _formatRemaining(s.parsedExpiration),
                        color: const Color(0xFFE08F2D),
                        icon: LucideIcons.clock,
                        onTap: () => _openSubscriber(s),
                      ),
                      const SizedBox(height: 4),
                    ],
                  ],
                  if (!_loaded && !hasApp)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: Sp.huge),
                      child: Center(
                        child: SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    ),
                  if (allEmpty) _empty(),
                ],
              );
            },
          ),
        ),
      ),
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
              Text('notifications.empty_title'.tr(),
                  style: AppType.label(color: AppColors.textMid)),
              const SizedBox(height: 4),
              Text('notifications.empty_hint'.tr(),
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
        label = 'reports.today'.tr();
      } else if (at.isAfter(yStart) || at.isAtSameMomentAs(yStart)) {
        label = 'reports.yesterday'.tr();
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
// v1 helper: صياغة "متبقّي X يوم و Y ساعة" لصف قريب الانتهاء.
String _formatRemaining(DateTime? exp) {
  if (exp == null) return 'notifications.expires_soon'.tr();
  final diff = exp.difference(DateTime.now());
  if (diff.isNegative) return 'notifications.remaining_expired'.tr();
  final days = diff.inDays;
  final hours = diff.inHours % 24;
  final minutes = diff.inMinutes % 60;
  final remaining = 'notifications.remaining'.tr();
  final andWord = 'notifications.and'.tr();
  final dayU = 'subscribers.day_unit'.tr();
  final hrU = 'subscribers.hour_unit'.tr();
  final minU = 'subscribers.minute_unit'.tr();
  if (days > 0) {
    return '$remaining $days $dayU${hours > 0 ? ' $andWord $hours $hrU' : ''}';
  }
  if (hours > 0) {
    return '$remaining $hours $hrU${minutes > 0 ? ' $andWord $minutes $minU' : ''}';
  }
  if (minutes > 0) return '$remaining $minutes $minU';
  return 'notifications.expires_now'.tr();
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.count,
    required this.color,
    required this.icon,
  });
  final String title;
  final int count;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(right: 2, bottom: 8, top: 4),
      child: Row(
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            title,
            style: AppType.label(color: AppColors.textHi)
                .copyWith(fontSize: 12, fontWeight: FontWeight.w800),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '$count',
              style: TextStyle(
                color: color,
                fontSize: 10.5,
                fontWeight: FontWeight.w900,
                height: 1.2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SubscriberAlertRow extends StatelessWidget {
  const _SubscriberAlertRow({
    required this.sub,
    required this.detail,
    required this.color,
    required this.icon,
    required this.onTap,
  });
  final Subscriber sub;
  final String detail;
  final Color color;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final fullName =
        '${sub.firstname} ${sub.lastname}'.trim();
    final displayName = fullName.isEmpty ? sub.username : fullName;
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
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(R.sm),
                ),
                child: Icon(icon, size: 16, color: color),
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
                            displayName,
                            style: AppType.label(color: AppColors.textHi)
                                .copyWith(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        // شارة حالة الاتصال — كانت مفقودة كلياً قبل
                        // 2026-07-14 فالمدير ما يعرف من الـInbox هل
                        // المشترك متصل أم لا بدون فتح البطاقة.
                        _OnlineDot(isOnline: sub.isOnline),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      sub.username,
                      style: AppType.muted(color: AppColors.textMid)
                          .copyWith(fontSize: 11.5),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      detail,
                      style: TextStyle(
                        color: color,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        height: 1.2,
                      ),
                    ),
                    // 2026-07-16: آخر اتصال للأوف لاين فقط (SAS4).
                    if (!sub.isOnline &&
                        (sub.lastOnline?.isNotEmpty ?? false)) ...[
                      const SizedBox(height: 4),
                      _InboxInfoChip(
                        icon: LucideIcons.history,
                        text: 'آخر اتصال: ${_formatLastOnlineInbox(sub.lastOnline!)}',
                      ),
                    ],
                    // معلومات الجلسة الحيّة (تظهر فقط لو المشترك online).
                    if (sub.isOnline &&
                        ((sub.downloadBytes ?? 0) > 0 ||
                            (sub.uploadBytes ?? 0) > 0 ||
                            (sub.ipAddress?.isNotEmpty ?? false) ||
                            (sub.deviceVendor?.isNotEmpty ?? false))) ...[
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 6,
                        runSpacing: 2,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          if ((sub.downloadBytes ?? 0) > 0 ||
                              (sub.uploadBytes ?? 0) > 0)
                            _InboxInfoChip(
                              icon: LucideIcons.arrowDownUp,
                              text:
                                  '${_fmtBytesInbox(sub.downloadBytes ?? 0)} ↓ / ${_fmtBytesInbox(sub.uploadBytes ?? 0)} ↑',
                            ),
                          if (sub.ipAddress?.isNotEmpty ?? false)
                            _InboxInfoChip(
                              icon: LucideIcons.globe,
                              text: sub.ipAddress!,
                            ),
                          if (sub.deviceVendor?.isNotEmpty ?? false)
                            _InboxInfoChip(
                              icon: LucideIcons.router,
                              text: sub.deviceVendor!,
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              Icon(LucideIcons.chevronLeft,
                  size: 16, color: AppColors.textLow),
            ],
          ),
        ),
      ),
    );
  }
}

class _OnlineDot extends StatelessWidget {
  const _OnlineDot({required this.isOnline});
  final bool isOnline;

  @override
  Widget build(BuildContext context) {
    final color = isOnline ? AppColors.brand : AppColors.textLow;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(R.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 4),
          Text(
            isOnline ? 'متصل' : 'غير متصل',
            style: AppType.muted(color: color).copyWith(
              fontSize: 9.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _InboxInfoChip extends StatelessWidget {
  const _InboxInfoChip({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: AppColors.brand.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(R.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 9, color: AppColors.brand),
          const SizedBox(width: 3),
          Text(
            text,
            style: AppType.muted(color: AppColors.brand).copyWith(
              fontSize: 9.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// 2026-07-16: تنسيق last_online مختصر للـInbox.
String _formatLastOnlineInbox(String raw) {
  final t = DateTime.tryParse(raw) ?? DateTime.tryParse(raw.split(' ').first);
  if (t == null) return raw.split(' ').first;
  final diff = DateTime.now().difference(t);
  if (diff.inMinutes < 1) return 'الآن';
  if (diff.inMinutes < 60) return 'قبل ${diff.inMinutes} د';
  if (diff.inHours < 24) return 'قبل ${diff.inHours} س';
  if (diff.inDays < 30) return 'قبل ${diff.inDays} يوم';
  if (diff.inDays < 365) return 'قبل ${(diff.inDays / 30).round()} شهر';
  return 'قبل سنة+';
}

String _fmtBytesInbox(int bytes) {
  if (bytes <= 0) return '0 B';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var i = 0;
  var v = bytes.toDouble();
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024;
    i++;
  }
  return '${v.toStringAsFixed(v >= 100 ? 0 : 1)} ${units[i]}';
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
          fallbackTitle: 'notifications.digest_near_expiry'.tr(),
        );
      case NotificationKind.expiredTodayDigest:
        return _KindMeta(
          icon: LucideIcons.circleAlert,
          color: AppColors.error,
          fallbackTitle: 'notifications.digest_expired_today'.tr(),
        );
      case NotificationKind.managerDebt:
        return _KindMeta(
          icon: LucideIcons.creditCard,
          color: AppColors.error,
          fallbackTitle: 'notifications.mgr_debt'.tr(),
        );
      case NotificationKind.managerBalance:
        return _KindMeta(
          icon: LucideIcons.banknote,
          color: const Color(0xFF14B8A6),
          fallbackTitle: 'notifications.mgr_balance_update'.tr(),
        );
      case NotificationKind.other:
        return _KindMeta(
          icon: LucideIcons.bell,
          color: AppColors.brand,
          fallbackTitle: 'notifications.other'.tr(),
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
