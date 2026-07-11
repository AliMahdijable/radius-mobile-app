import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../models/app_notification.dart';
import '../../services/inbox_service.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';

/// شاشة inbox — قائمة الإشعارات المستلمة، مجمّعة يومياً.
///
/// تصميم مطابق نمط بقية الشاشات (surface + border + typography).
/// - Swipe لحذف صف واحد.
/// - AppBar action لتعليم الكل كمقروء.
class InboxScreen extends StatelessWidget {
  const InboxScreen({super.key, this.onTapNotification});

  /// callback عند tap إشعار — يُترك للـcaller ليقرّر الـrouting.
  /// null = لا نقوم بشيء (بس نُعلّمها كمقروءة).
  final void Function(AppNotification n)? onTapNotification;

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
        child: ValueListenableBuilder<int>(
          valueListenable: InboxService.changes,
          builder: (context, _, __) {
            final items = InboxService.all;
            if (items.isEmpty) return _empty();
            final groups = _groupByDay(items);
            return ListView.builder(
              padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, Sp.huge),
              itemCount: groups.length,
              itemBuilder: (context, gi) {
                final g = groups[gi];
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: EdgeInsets.only(
                          top: gi == 0 ? 0 : Sp.md, bottom: 6, right: 4),
                      child: Text(
                        g.label,
                        style: AppType.label(color: AppColors.textMid)
                            .copyWith(
                                fontSize: 11, fontWeight: FontWeight.w700),
                      ),
                    ),
                    for (final n in g.items) ...[
                      Dismissible(
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
                          onTap: () {
                            InboxService.markRead(n.id);
                            onTapNotification?.call(n);
                          },
                        ),
                      ),
                      const SizedBox(height: 4),
                    ],
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _empty() => Padding(
        padding: const EdgeInsets.symmetric(vertical: Sp.huge * 2),
        child: Center(
          child: Column(
            children: [
              Icon(LucideIcons.bellOff, size: 40, color: AppColors.textLow),
              const SizedBox(height: 12),
              Text('لا توجد إشعارات',
                  style: AppType.label(color: AppColors.textMid)),
              const SizedBox(height: 4),
              Text('ستظهر الإشعارات هنا عند وصولها',
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
