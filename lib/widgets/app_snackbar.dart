import 'package:flutter/material.dart';
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

    toastification.show(
      type: spec.toastType,
      style: ToastificationStyle.flatColored,
      title: Text(
        message,
        style: const TextStyle(
          fontFamily: 'Cairo',
          fontWeight: FontWeight.w700,
          fontSize: 14,
          height: 1.35,
        ),
      ),
      description: (detail != null && detail.isNotEmpty)
          ? Text(
              detail,
              style: const TextStyle(
                fontFamily: 'Cairo',
                fontWeight: FontWeight.w500,
                fontSize: 12,
                height: 1.35,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            )
          : null,
      icon: Icon(spec.icon, color: spec.iconColor, size: 22),
      primaryColor: spec.accent,
      backgroundColor: spec.bg,
      foregroundColor: spec.fg,
      alignment: Alignment.topCenter,
      direction: TextDirection.rtl,
      autoCloseDuration: duration,
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: spec.accent.withValues(alpha: 0.35), width: 1),
      boxShadow: [
        BoxShadow(
          color: spec.accent.withValues(alpha: 0.18),
          blurRadius: 16,
          offset: const Offset(0, 6),
        ),
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.06),
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
      ],
      // Stacking: toastification بشكل افتراضي يكدّس الـtoasts الجديدة فوق
      // الموجودة (stack تلقائي). كل toast يبقى مدّته ثم ينزاح.
      showProgressBar: true,
      pauseOnHover: true,
      dragToClose: true,
      applyBlurEffect: false,
      closeButtonShowType: CloseButtonShowType.onHover,
      closeOnClick: true,
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
          icon: Icons.check_circle_rounded,
        );
      case _Kind.error:
        return _Spec(
          toastType: ToastificationType.error,
          accent: AppTheme.dangerColor,
          bg: const Color(0xFFFFEBEE),
          fg: const Color(0xFFB71C1C),
          iconColor: AppTheme.dangerColor,
          icon: Icons.error_rounded,
        );
      case _Kind.warning:
        return _Spec(
          toastType: ToastificationType.warning,
          accent: AppTheme.warningColor,
          bg: const Color(0xFFFFF8E1),
          fg: const Color(0xFFE65100),
          iconColor: AppTheme.warningColor,
          icon: Icons.warning_amber_rounded,
        );
      case _Kind.info:
        return _Spec(
          toastType: ToastificationType.info,
          accent: AppTheme.infoColor,
          bg: const Color(0xFFE3F2FD),
          fg: const Color(0xFF0D47A1),
          iconColor: AppTheme.infoColor,
          icon: Icons.info_rounded,
        );
      case _Kind.whatsapp:
        return _Spec(
          toastType: ToastificationType.success,
          accent: AppTheme.whatsappGreen,
          bg: const Color(0xFFE8F5E9),
          fg: const Color(0xFF1B5E20),
          iconColor: AppTheme.whatsappGreen,
          icon: Icons.chat_rounded,
        );
      case _Kind.whatsappError:
        return _Spec(
          toastType: ToastificationType.error,
          accent: AppTheme.dangerColor,
          bg: const Color(0xFFFFEBEE),
          fg: const Color(0xFFB71C1C),
          iconColor: AppTheme.dangerColor,
          icon: Icons.chat_rounded,
        );
    }
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
