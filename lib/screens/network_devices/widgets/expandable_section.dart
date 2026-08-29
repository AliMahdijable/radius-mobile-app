import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';

/// قسم قابل للطيّ — الـheader دائماً ظاهر مع سهم، والمحتوى يظهر/يختفي.
/// يُستعمل في details screen لتنظيم الأقسام الطويلة (interfaces/stations/etc).
class ExpandableSection extends StatefulWidget {
  final Widget header;
  final Widget content;
  final bool initiallyExpanded;
  final EdgeInsetsGeometry? contentPadding;
  final Color? backgroundColor;
  final Color? borderColor;

  const ExpandableSection({
    super.key,
    required this.header,
    required this.content,
    this.initiallyExpanded = true,
    this.contentPadding,
    this.backgroundColor,
    this.borderColor,
  });

  @override
  State<ExpandableSection> createState() => _ExpandableSectionState();
}

class _ExpandableSectionState extends State<ExpandableSection>
    with SingleTickerProviderStateMixin {
  late bool _expanded;
  late final AnimationController _ctrl;
  late final Animation<double> _iconTurns;

  @override
  void initState() {
    super.initState();
    // 2026-08-18: لو الـwidget عنده PageStorageKey → استعِد expanded من
    // PageStorage (يحفظ الحالة عبر rebuilds حتى لو الـwidget موقعه تغيّر).
    // بدون هذا: refresh يعيد الأقسام إلى initiallyExpanded الافتراضيّة.
    _expanded = widget.initiallyExpanded;
    _ctrl = AnimationController(
      duration: const Duration(milliseconds: 200),
      value: _expanded ? 1.0 : 0.0,
      vsync: this,
    );
    _iconTurns = Tween<double>(begin: 0, end: 0.5).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // نقرأ PageStorage هنا (وليس في initState) لأن context لا يزال ما
    // ينفع في initState. mounted بعد أول build.
    if (widget.key is PageStorageKey) {
      final stored = PageStorage.of(context).readState(context) as bool?;
      if (stored != null && stored != _expanded) {
        _expanded = stored;
        _ctrl.value = stored ? 1.0 : 0.0;
      }
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() => _expanded = !_expanded);
    if (_expanded) {
      _ctrl.forward();
    } else {
      _ctrl.reverse();
    }
    // احفظ الحالة في PageStorage لو الـwidget عنده PageStorageKey.
    if (widget.key is PageStorageKey) {
      PageStorage.of(context).writeState(context, _expanded);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: widget.backgroundColor ?? AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: widget.borderColor ?? AppColors.border),
      ),
      child: Column(children: [
        InkWell(
          onTap: _toggle,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(Sp.md),
            child: Row(children: [
              Expanded(child: widget.header),
              const SizedBox(width: 8),
              RotationTransition(
                turns: _iconTurns,
                child: Icon(
                  LucideIcons.chevronDown,
                  size: 18,
                  color: AppColors.textMid,
                ),
              ),
            ]),
          ),
        ),
        ClipRect(
          child: AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            alignment: Alignment.topCenter,
            child: _expanded
                ? Column(children: [
                    const _DottedDivider(),
                    Padding(
                      padding:
                          widget.contentPadding ?? const EdgeInsets.all(Sp.md),
                      child: widget.content,
                    ),
                  ])
                : const SizedBox.shrink(),
          ),
        ),
      ]),
    );
  }
}

/// خط فصل منقّط رصاصي واضح — شرطات ظاهرة بلون رصاصي خفيف.
class _DottedDivider extends StatelessWidget {
  const _DottedDivider();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Sp.md),
      child: SizedBox(
        height: 2,
        child: CustomPaint(
          painter: _DottedLinePainter(
            color: AppColors.textLow.withValues(alpha: 0.55),
          ),
        ),
      ),
    );
  }
}

class _DottedLinePainter extends CustomPainter {
  final Color color;
  const _DottedLinePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    const dashWidth = 6.0;
    const dashGap = 5.0;
    double x = 0;
    final y = size.height / 2;
    while (x < size.width) {
      final end = (x + dashWidth).clamp(0.0, size.width);
      canvas.drawLine(Offset(x, y), Offset(end, y), paint);
      x += dashWidth + dashGap;
    }
  }

  @override
  bool shouldRepaint(covariant _DottedLinePainter old) => old.color != color;
}
