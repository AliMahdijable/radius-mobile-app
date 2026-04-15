import 'dart:async';
import 'package:flutter/material.dart';
import '../core/theme/app_theme.dart';

enum _SnackType { success, error, warning, info, whatsapp, whatsappError }

class AppSnackBar {
  AppSnackBar._();

  static OverlayEntry? _currentEntry;
  static Timer? _dismissTimer;

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

  static void dismiss() {
    _dismissTimer?.cancel();
    _dismissTimer = null;
    _currentEntry?.remove();
    _currentEntry = null;
  }

  static void _show(
    BuildContext context,
    String message,
    _SnackType type, {
    String? detail,
  }) {
    dismiss();

    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;

    final isDark = Theme.of(context).brightness == Brightness.dark;

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

    final duration = type == _SnackType.error ||
            type == _SnackType.whatsappError ||
            detail != null
        ? const Duration(seconds: 4)
        : const Duration(seconds: 3);

    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _TopNotification(
        message: message,
        detail: detail,
        accent: accent,
        bg: isDark ? const Color(0xFF2A2A2A) : bg,
        icon: icon,
        textColor: isDark ? Colors.white : const Color(0xFF1A1A1A),
        detailColor: isDark
            ? Colors.white70
            : const Color(0xFF1A1A1A).withValues(alpha: .7),
        duration: duration,
        onDismiss: () {
          _dismissTimer?.cancel();
          _dismissTimer = null;
          if (_currentEntry == entry) {
            entry.remove();
            _currentEntry = null;
          }
        },
      ),
    );

    _currentEntry = entry;
    overlay.insert(entry);

    _dismissTimer = Timer(duration + const Duration(milliseconds: 400), () {
      if (_currentEntry == entry) {
        _currentEntry = null;
      }
    });
  }
}

class _TopNotification extends StatefulWidget {
  final String message;
  final String? detail;
  final Color accent;
  final Color bg;
  final IconData icon;
  final Color textColor;
  final Color detailColor;
  final Duration duration;
  final VoidCallback onDismiss;

  const _TopNotification({
    required this.message,
    this.detail,
    required this.accent,
    required this.bg,
    required this.icon,
    required this.textColor,
    required this.detailColor,
    required this.duration,
    required this.onDismiss,
  });

  @override
  State<_TopNotification> createState() => _TopNotificationState();
}

class _TopNotificationState extends State<_TopNotification>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<Offset> _slideAnim;
  late final Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
      reverseDuration: const Duration(milliseconds: 250),
    );

    _slideAnim = Tween<Offset>(
      begin: const Offset(0, -1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));

    _fadeAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOut),
    );

    _ctrl.forward();

    Future.delayed(widget.duration, () {
      if (mounted) {
        _ctrl.reverse().then((_) {
          if (mounted) widget.onDismiss();
        });
      }
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _swipeDismiss() {
    _ctrl.reverse().then((_) {
      if (mounted) widget.onDismiss();
    });
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SlideTransition(
        position: _slideAnim,
        child: FadeTransition(
          opacity: _fadeAnim,
          child: GestureDetector(
            onVerticalDragEnd: (d) {
              if (d.primaryVelocity != null && d.primaryVelocity! < -100) {
                _swipeDismiss();
              }
            },
            onTap: _swipeDismiss,
            child: Material(
              color: Colors.transparent,
              child: Container(
                margin: EdgeInsets.only(
                  top: topPadding + 8,
                  left: 12,
                  right: 12,
                ),
                decoration: BoxDecoration(
                  color: widget.bg,
                  borderRadius: BorderRadius.circular(14),
                  border:
                      Border(top: BorderSide(color: widget.accent, width: 3)),
                  boxShadow: [
                    BoxShadow(
                      color: widget.accent.withValues(alpha: .18),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                    BoxShadow(
                      color: Colors.black.withValues(alpha: .08),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: widget.accent.withValues(alpha: .12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child:
                          Icon(widget.icon, color: widget.accent, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.message,
                            style: TextStyle(
                              color: widget.textColor,
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                              fontFamily: 'Cairo',
                            ),
                          ),
                          if (widget.detail != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              widget.detail!,
                              style: TextStyle(
                                color: widget.detailColor,
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
                    Icon(Icons.close, size: 18,
                        color: widget.textColor.withValues(alpha: .4)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
