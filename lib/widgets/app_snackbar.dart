import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:toastification/toastification.dart';
import '../core/router/app_router.dart';
import '../core/theme/app_theme.dart';

/// AppSnackBar — واجهة موحّدة لإشعارات in-app.
///
/// تستعمل toastification داخلياً (يدعم stacking + progress bar +
/// flatColored design حديث + RTL + dark mode + auto-dismiss).
///
/// كل callers الكود الموجود تستعمل نفس الـAPI القديم
/// (success/error/warning/info/whatsapp + Global versions للـDio
/// interceptors). فلا تعديل في باقي الكود.
class AppSnackBar {
  AppSnackBar._();

  // ─── الواجهة العامة (مع context) ───
  static void success(BuildContext context, String message, {String? detail}) =>
      _show(context, message, _Kind.success, detail: detail);

  static void error(BuildContext context, String message, {String? detail}) =>
      _show(context, message, _Kind.error, detail: detail);

  static void warning(BuildContext context, String message, {String? detail}) =>
      _show(context, message, _Kind.warning, detail: detail);

  static void info(BuildContext context, String message, {String? detail}) =>
      _show(context, message, _Kind.info, detail: detail);

  static void whatsapp(BuildContext context, String message, {String? detail}) =>
      _show(context, message, _Kind.whatsapp, detail: detail);

  static void whatsappError(BuildContext context, String message,
          {String? detail}) =>
      _show(context, message, _Kind.whatsappError, detail: detail);

  // ─── إصدارات بدون context (Dio interceptors / background) ───
  static void successGlobal(String message, {String? detail}) =>
      _showGlobal(message, _Kind.success, detail: detail);

  static void errorGlobal(String message, {String? detail}) =>
      _showGlobal(message, _Kind.error, detail: detail);

  static void warningGlobal(String message, {String? detail}) =>
      _showGlobal(message, _Kind.warning, detail: detail);

  static void infoGlobal(String message, {String? detail}) =>
      _showGlobal(message, _Kind.info, detail: detail);

  /// مسح كل الإشعارات الظاهرة (نادر — toastification يدير stack تلقائياً).
  static void dismiss() {
    toastification.dismissAll();
  }

  // ─── الداخلي ───
  static void _show(
    BuildContext context,
    String message,
    _Kind kind, {
    String? detail,
  }) {
    _emit(message, kind, detail: detail);
  }

  static void _showGlobal(String message, _Kind kind, {String? detail}) {
    final ctx = appNavigatorKey.currentContext;
    if (ctx == null) return;
    _emit(message, kind, detail: detail);
  }

  static void _emit(String message, _Kind kind, {String? detail}) {
    final spec = _specOf(kind);
    final duration = (kind == _Kind.error || kind == _Kind.whatsappError || detail != null)
        ? const Duration(seconds: 4)
        : const Duration(milliseconds: 2800);

    // showCustom — نبني widget كامل بنفس design الـKpiCard:
    // خلفية بيضاء/card neutral + شريط جانبي ملوّن من الـRTL start فقط
    // (مو border حول الكل) + أيقونة وعنوان ملوّنة + وصف رمادي.
    toastification.showCustom(
      alignment: Alignment.topCenter,
      autoCloseDuration: duration,
      direction: TextDirection.rtl,
      builder: (context, holder) {
        return _SideBarToast(
          accent: spec.accent,
          icon: spec.icon,
          title: message,
          detail: detail,
          onClose: () => toastification.dismiss(holder),
        );
      },
    );
  }

  static _Spec _specOf(_Kind kind) {
    switch (kind) {
      case _Kind.success:
        return _Spec(
          toastType: ToastificationType.success,
          accent: AppTheme.successColor,
          bg: const Color(0xFFE8F5E9),
          fg: const Color(0xFF1B5E20),
          iconColor: AppTheme.successColor,
          icon: LucideIcons.circleCheck,
        );
      case _Kind.error:
        return _Spec(
          toastType: ToastificationType.error,
          accent: AppTheme.dangerColor,
          bg: const Color(0xFFFFEBEE),
          fg: const Color(0xFFB71C1C),
          iconColor: AppTheme.dangerColor,
          icon: LucideIcons.circleAlert,
        );
      case _Kind.warning:
        return _Spec(
          toastType: ToastificationType.warning,
          accent: AppTheme.warningColor,
          bg: const Color(0xFFFFF8E1),
          fg: const Color(0xFFE65100),
          iconColor: AppTheme.warningColor,
          icon: LucideIcons.triangleAlert,
        );
      case _Kind.info:
        return _Spec(
          toastType: ToastificationType.info,
          accent: AppTheme.infoColor,
          bg: const Color(0xFFE3F2FD),
          fg: const Color(0xFF0D47A1),
          iconColor: AppTheme.infoColor,
          icon: LucideIcons.info,
        );
      case _Kind.whatsapp:
        return _Spec(
          toastType: ToastificationType.success,
          accent: AppTheme.whatsappGreen,
          bg: const Color(0xFFE8F5E9),
          fg: const Color(0xFF1B5E20),
          iconColor: AppTheme.whatsappGreen,
          icon: LucideIcons.messageCircle,
        );
      case _Kind.whatsappError:
        return _Spec(
          toastType: ToastificationType.error,
          accent: AppTheme.dangerColor,
          bg: const Color(0xFFFFEBEE),
          fg: const Color(0xFFB71C1C),
          iconColor: AppTheme.dangerColor,
          icon: LucideIcons.messageCircle,
        );
    }
  }
}

/// Toast widget بنفس design الـKpiCard:
///   - خلفية card بيضاء (في light mode) أو surface (في dark mode)
///   - شريط جانبي ملوّن 4px من جهة RTL start فقط (مو border حول الكل)
///   - أيقونة + عنوان بلون الـaccent
///   - وصف رمادي خفيف
class _SideBarToast extends StatelessWidget {
  final Color accent;
  final IconData icon;
  final String title;
  final String? detail;
  final VoidCallback onClose;

  const _SideBarToast({
    required this.accent,
    required this.icon,
    required this.title,
    required this.detail,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cardBg = theme.cardTheme.color ?? theme.colorScheme.surface;
    final divider = theme.colorScheme.onSurface.withValues(alpha: 0.08);
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.65);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: Material(
        color: Colors.transparent,
        child: GestureDetector(
          onTap: onClose,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 420),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: divider, width: 1),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.10),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              children: [
                // الشريط الملوّن — RTL start = right
                PositionedDirectional(
                  start: 0,
                  top: 0,
                  bottom: 0,
                  child: Container(width: 4, color: accent),
                ),
                Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(12, 10, 10, 10),
                  child: Row(
                    crossAxisAlignment: detail != null && detail!.isNotEmpty
                        ? CrossAxisAlignment.start
                        : CrossAxisAlignment.center,
                    children: [
                      Icon(icon, color: accent, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontFamily: 'Cairo',
                                fontWeight: FontWeight.w700,
                                fontSize: 13.5,
                                height: 1.3,
                                color: accent,
                              ),
                            ),
                            if (detail != null && detail!.isNotEmpty) ...[
                              const SizedBox(height: 5),
                              Container(height: 1, color: divider),
                              const SizedBox(height: 5),
                              Text(
                                detail!,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontFamily: 'Cairo',
                                  fontWeight: FontWeight.w500,
                                  fontSize: 11.5,
                                  height: 1.35,
                                  color: muted,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

enum _Kind { success, error, warning, info, whatsapp, whatsappError }

class _Spec {
  final ToastificationType toastType;
  final Color accent;
  final Color bg;
  final Color fg;
  final Color iconColor;
  final IconData icon;
  const _Spec({
    required this.toastType,
    required this.accent,
    required this.bg,
    required this.fg,
    required this.iconColor,
    required this.icon,
  });
}
