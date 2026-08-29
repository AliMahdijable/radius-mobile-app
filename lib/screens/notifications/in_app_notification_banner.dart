import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../models/app_notification.dart';
import '../../services/inbox_service.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import 'inbox_screen.dart';

/// Toast علوي بسيط لعرض إشعار FCM foreground.
///
/// * يُعرض في overlay الـtop-level (Navigator/rootNavigator) عشان
///   يظهر فوق كل الـcontent.
/// * auto-dismiss بعد 4 ثواني.
/// * tap → يفتح InboxScreen + يعلّم الإشعار كمقروء.
///
/// **الاستخدام:**
///   InAppNotificationBanner.show(context, notification: n);
///
/// **الأمان:** يفحص Overlay.of(context) ولو null (context قبل النافبكيتور)
/// يتجاهل بصمت.
class InAppNotificationBanner {
  InAppNotificationBanner._();

  static OverlayEntry? _current;
  static Timer? _timer;

  static void show(BuildContext context,
      {required AppNotification notification}) {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;

    // احذف الـcurrent لو موجود عشان banner جديد يظهر فوراً.
    _dismiss();

    final entry = OverlayEntry(
      builder: (ctx) => _BannerCard(
        notification: notification,
        onDismiss: _dismiss,
      ),
    );
    _current = entry;
    overlay.insert(entry);
    HapticFeedback.lightImpact();

    _timer = Timer(const Duration(seconds: 4), _dismiss);
  }

  static void _dismiss() {
    _timer?.cancel();
    _timer = null;
    _current?.remove();
    _current = null;
  }
}

class _BannerCard extends StatefulWidget {
  const _BannerCard({required this.notification, required this.onDismiss});
  final AppNotification notification;
  final VoidCallback onDismiss;

  @override
  State<_BannerCard> createState() => _BannerCardState();
}

class _BannerCardState extends State<_BannerCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final Animation<Offset> _slide;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    )..forward();
    _slide = Tween<Offset>(begin: const Offset(0, -0.4), end: Offset.zero)
        .animate(CurvedAnimation(parent: _c, curve: Curves.easeOutCubic));
    _fade = CurvedAnimation(parent: _c, curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Future<void> _handleTap() async {
    // علّمها كمقروءة + افتح Inbox.
    await InboxService.markRead(widget.notification.id);
    if (!mounted) return;
    widget.onDismiss();
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(builder: (_) => const InboxScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final top = MediaQuery.paddingOf(context).top;
    final n = widget.notification;
    final meta = _metaFor(n.kind);
    return Positioned(
      top: top + 6,
      left: Sp.md,
      right: Sp.md,
      child: SafeArea(
        top: false,
        child: SlideTransition(
          position: _slide,
          child: FadeTransition(
            opacity: _fade,
            child: Material(
              color: Colors.transparent,
              child: Dismissible(
                key: ValueKey('banner_${n.id}'),
                direction: DismissDirection.up,
                onDismissed: (_) => widget.onDismiss(),
                child: GestureDetector(
                  onTap: _handleTap,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(R.md),
                      border: Border.all(color: AppColors.border),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.08),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: meta.color.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(R.sm),
                          ),
                          child: Icon(meta.icon, size: 16, color: meta.color),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                n.title.isEmpty ? meta.fallback : n.title,
                                style: AppType.label(color: AppColors.textHi)
                                    .copyWith(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w900),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (n.body.isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(
                                  n.body,
                                  style: AppType.muted(color: AppColors.textMid)
                                      .copyWith(fontSize: 11.5, height: 1.4),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        InkResponse(
                          onTap: widget.onDismiss,
                          radius: 18,
                          child: Padding(
                            padding: const EdgeInsets.all(4),
                            child: Icon(LucideIcons.x,
                                size: 14, color: AppColors.textMid),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  static _M _metaFor(NotificationKind k) {
    switch (k) {
      case NotificationKind.nearExpiryDigest:
        return _M(LucideIcons.alarmClock, AppColors.warning,
            'اقتراب انتهاء اشتراكات');
      case NotificationKind.expiredTodayDigest:
        return _M(
            LucideIcons.circleAlert, AppColors.error, 'اشتراكات منتهية اليوم');
      case NotificationKind.managerDebt:
        return _M(LucideIcons.creditCard, AppColors.error, 'دين مدير فرعي');
      case NotificationKind.managerBalance:
        return _M(LucideIcons.banknote, AppColors.success, 'تحديث رصيد مدير');
      case NotificationKind.other:
        return _M(LucideIcons.bell, AppColors.brand, 'إشعار');
    }
  }
}

class _M {
  const _M(this.icon, this.color, this.fallback);
  final IconData icon;
  final Color color;
  final String fallback;
}
