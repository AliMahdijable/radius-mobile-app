import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../services/inbox_service.dart';
import '../../theme/colors.dart';
import 'inbox_screen.dart';
import '../../theme/spacing.dart';

/// أيقونة الإشعارات — تُوضع في AppBar لأي شاشة (Dashboard/MainShell).
/// * أيقونة bell قياسية.
/// * badge أحمر بعدد غير المقروء (يُخفى لو 0).
/// * Tap → InboxScreen (نمرّر onTapNotification لو الـcaller أعطاه).
class NotificationBell extends StatelessWidget {
  const NotificationBell({super.key, this.color, this.onTapNotification});

  /// لون الأيقونة الأساسي.
  final Color? color;

  /// callback يُمرَّر إلى InboxScreen للـrouting.
  /// null = InboxScreen يعرض بس (بدون routing).
  final void Function(dynamic n)? onTapNotification;

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return ValueListenableBuilder<int>(
      valueListenable: InboxService.changes,
      builder: (context, _, __) {
        final unread = InboxService.unreadCount;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            IconButton(
              tooltip: 'الإشعارات',
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => InboxScreen(
                      onTapNotification: (n) => onTapNotification?.call(n),
                    ),
                  ),
                );
              },
              icon: Icon(
                LucideIcons.bell,
                color: color ?? AppColors.textHi,
              ),
            ),
            if (unread > 0)
              Positioned(
                right: 4,
                top: 4,
                child: IgnorePointer(
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: AppColors.error,
                      borderRadius: BorderRadius.circular(R.sm),
                      border: Border.all(color: AppColors.surface, width: 1.5),
                    ),
                    constraints:
                        const BoxConstraints(minWidth: 16, minHeight: 16),
                    child: Text(
                      unread > 99 ? '99+' : '$unread',
                      style: const TextStyle(
                        color: AppColors.onBrand,
                        fontSize: 9.5,
                        fontWeight: FontWeight.w700,
                        height: 1,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
