import 'dart:async';
import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../theme/colors.dart';
import '../theme/spacing.dart';

/// كشف كلمة السرّ — bottom sheet احترافي (2026-08-26).
///
/// **الميّزات**:
/// - إخفاء الكلمة افتراضياً (dots)، الضغط على 👁 يكشف
/// - نسخ سريع للحافظة + haptic + toast
/// - عدّاد تنازلي 15 ثانية — تُخفى تلقائياً وتُغلق الشيت
/// - Cairo للأرقام وكلمة السرّ (قابلة للنسخ)
/// - avatar دائري ملوّن بالمبادرات + عنوان + subtitle
/// - Dark-mode aware
///
/// **الاستدعاء**:
/// ```
/// await showRevealPasswordSheet(
///   context,
///   title: 'admin@popq',
///   subtitle: 'كلمة سرّ المدير الفرعي',
///   password: 'hneen1995',
///   accentColor: AppColors.brandAccent,
/// );
/// ```
Future<void> showRevealPasswordSheet(
  BuildContext context, {
  required String title,
  required String subtitle,
  required String password,
  Color? accentColor,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: AppColors.scrim,
    builder: (_) => _RevealSheet(
      title: title,
      subtitle: subtitle,
      password: password,
      accent: accentColor ?? AppColors.brandAccent,
    ),
  );
}

class _RevealSheet extends StatefulWidget {
  const _RevealSheet({
    required this.title,
    required this.subtitle,
    required this.password,
    required this.accent,
  });
  final String title;
  final String subtitle;
  final String password;
  final Color accent;

  @override
  State<_RevealSheet> createState() => _RevealSheetState();
}

class _RevealSheetState extends State<_RevealSheet>
    with SingleTickerProviderStateMixin {
  bool _visible = false;
  int _remaining = 15;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _reveal() {
    HapticFeedback.selectionClick();
    setState(() => _visible = true);
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() => _remaining -= 1);
      if (_remaining <= 0) {
        t.cancel();
        setState(() => _visible = false);
      }
    });
  }

  Future<void> _copy() async {
    HapticFeedback.mediumImpact();
    await Clipboard.setData(ClipboardData(text: widget.password));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: const Text('تمّ نسخ كلمة السرّ للحافظة'),
      backgroundColor: AppColors.brand,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(R.sm)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep
    final firstChar =
        widget.title.trim().isEmpty ? '?' : widget.title.characters.first;

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 12,
          bottom: MediaQuery.paddingOf(context).bottom + 16,
        ),
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          decoration: BoxDecoration(
            // سطح الشيت لا سطح الكارت: ليلاً يفصلهما درجة كاملة،
            // وبدونها يذوب الشيت في الخلفيّة خلفه.
            color: AppColors.surfaceSheet,
            borderRadius: BorderRadius.circular(R.xl),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // المقبض بمقاس الطقم نفسه (42 × H.grabber) — يظهر مع
              // شيتات أخرى في الجلسة الواحدة، فاختلافه يُلاحَظ.
              Container(
                width: 42,
                height: H.grabber,
                decoration: BoxDecoration(
                  color: AppColors.grabber,
                  borderRadius: BorderRadius.circular(R.pill),
                ),
              ),
              const SizedBox(height: 16),
              // Avatar + title/subtitle
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          widget.accent,
                          widget.accent.withValues(alpha: 0.7),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(R.icon),
                      boxShadow: [
                        BoxShadow(
                          color: widget.accent.withValues(alpha: 0.28),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      firstChar,
                      style: const TextStyle(
                        fontSize: 20, height: 1.25,
                        fontWeight: FontWeight.w700,
                        color: AppColors.onBrand,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.title,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textHi,
                            height: 1.2,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          widget.subtitle,
                          style: TextStyle(
                            fontSize: 11.5, height: 1.35,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textMid,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon:
                        Icon(LucideIcons.x, size: 20, color: AppColors.textMid),
                    onPressed: () => Navigator.of(context).pop(),
                    splashRadius: 20,
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 32, minHeight: 32),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              // Password display card
              _PasswordDisplay(
                password: widget.password,
                visible: _visible,
                onReveal: _reveal,
                accent: widget.accent,
                remaining: _remaining,
              ),
              const SizedBox(height: 14),
              // Action buttons
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 46,
                      child: OutlinedButton.icon(
                        onPressed: _copy,
                        icon: const Icon(LucideIcons.copy, size: 16),
                        label: const Text(
                          'نسخ',
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 13, height: 1.35,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: widget.accent,
                          side: BorderSide(
                            color: widget.accent.withValues(alpha: 0.5),
                            width: 1,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(R.md),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: SizedBox(
                      height: 46,
                      child: FilledButton.icon(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(LucideIcons.check, size: 16),
                        label: const Text(
                          'تم',
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 13, height: 1.35,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: widget.accent,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(R.md),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(LucideIcons.shieldCheck,
                      size: 12, color: AppColors.textLow),
                  const SizedBox(width: 5),
                  Text(
                    'كلمة السرّ مخزَّنة بتشفير AES.',
                    style: TextStyle(
                      fontSize: 10.5, height: 1.3,
                      color: AppColors.textLow,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PasswordDisplay extends StatelessWidget {
  const _PasswordDisplay({
    required this.password,
    required this.visible,
    required this.onReveal,
    required this.accent,
    required this.remaining,
  });
  final String password;
  final bool visible;
  final VoidCallback onReveal;
  final Color accent;
  final int remaining;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
      decoration: BoxDecoration(
        color: AppColors.surfaceInput,
        borderRadius: BorderRadius.circular(R.icon),
        border: Border.all(
          color: AppColors.border,
          width: 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'كلمة السرّ',
                style: TextStyle(
                  fontSize: 10.5, height: 1.3,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textLow,
                  letterSpacing: 0.5,
                ),
              ),
              const Spacer(),
              if (visible && remaining > 0)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(R.pill),
                  ),
                  child: Text(
                    'يُخفى بعد ${remaining}s',
                    style: TextStyle(
                      fontSize: 10.5, height: 1.3,
                      fontWeight: FontWeight.w700,
                      color: accent,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: visible
                    ? SelectableText(
                        password,
                        textDirection: TextDirection.ltr,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textHi,
                          fontFeatures: const [FontFeature.tabularFigures()],
                          height: 1.2,
                          letterSpacing: 1.0,
                        ),
                      )
                    : Text(
                        '•' * password.length.clamp(6, 16),
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textMid,
                          height: 1.2,
                          letterSpacing: 3,
                        ),
                      ),
              ),
              IconButton(
                icon: Icon(
                  visible ? LucideIcons.eyeOff : LucideIcons.eye,
                  size: 18,
                  color: accent,
                ),
                onPressed: onReveal,
                tooltip: visible ? 'إخفاء' : 'إظهار',
                splashRadius: 20,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
