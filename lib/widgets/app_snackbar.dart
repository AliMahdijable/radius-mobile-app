import 'package:flutter/material.dart';
import '../core/theme/app_theme.dart';

enum _SnackType { success, error, warning, info, whatsapp, whatsappError }

class AppSnackBar {
  AppSnackBar._();

  static void success(BuildContext context, String message, {String? detail}) =>
      _show(context, message, _SnackType.success, detail: detail);

  static void error(BuildContext context, String message, {String? detail}) =>
      _show(context, message, _SnackType.error, detail: detail);

  static void warning(BuildContext context, String message, {String? detail}) =>
      _show(context, message, _SnackType.warning, detail: detail);

  static void info(BuildContext context, String message, {String? detail}) =>
      _show(context, message, _SnackType.info, detail: detail);

  static void whatsapp(BuildContext context, String message,
          {String? detail}) =>
      _show(context, message, _SnackType.whatsapp, detail: detail);

  static void whatsappError(BuildContext context, String message,
          {String? detail}) =>
      _show(context, message, _SnackType.whatsappError, detail: detail);

  static void _show(
    BuildContext context,
    String message,
    _SnackType type, {
    String? detail,
  }) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;

    messenger.clearSnackBars();

    final (Color accent, Color bg, IconData icon) = switch (type) {
      _SnackType.success => (
          AppTheme.successColor,
          const Color(0xFFE8F5E9),
          Icons.check_circle_rounded,
        ),
      _SnackType.error => (
          AppTheme.dangerColor,
          const Color(0xFFFFEBEE),
          Icons.error_rounded,
        ),
      _SnackType.warning => (
          AppTheme.warningColor,
          const Color(0xFFFFF8E1),
          Icons.warning_amber_rounded,
        ),
      _SnackType.info => (
          AppTheme.infoColor,
          const Color(0xFFE3F2FD),
          Icons.info_rounded,
        ),
      _SnackType.whatsapp => (
          AppTheme.whatsappGreen,
          const Color(0xFFE8F5E9),
          Icons.chat_rounded,
        ),
      _SnackType.whatsappError => (
          AppTheme.dangerColor,
          const Color(0xFFFFEBEE),
          Icons.chat_rounded,
        ),
    };

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final effectiveBg = isDark ? const Color(0xFF2A2A2A) : bg;
    final textColor = isDark ? Colors.white : const Color(0xFF1A1A1A);
    final detailColor =
        isDark ? Colors.white70 : const Color(0xFF1A1A1A).withValues(alpha: .7);

    final duration = type == _SnackType.error ||
            type == _SnackType.whatsappError ||
            detail != null
        ? const Duration(seconds: 4)
        : const Duration(seconds: 3);

    messenger.showSnackBar(SnackBar(
      content: Container(
        decoration: BoxDecoration(
          color: effectiveBg,
          borderRadius: BorderRadius.circular(14),
          border: Border(top: BorderSide(color: accent, width: 3)),
          boxShadow: [
            BoxShadow(
              color: accent.withValues(alpha: .15),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: accent, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    message,
                    style: TextStyle(
                      color: textColor,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      fontFamily: 'Cairo',
                    ),
                  ),
                  if (detail != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      detail,
                      style: TextStyle(
                        color: detailColor,
                        fontSize: 12,
                        fontFamily: 'Cairo',
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
      backgroundColor: Colors.transparent,
      elevation: 0,
      behavior: SnackBarBehavior.floating,
      padding: EdgeInsets.zero,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      duration: duration,
      dismissDirection: DismissDirection.horizontal,
    ));
  }
}
