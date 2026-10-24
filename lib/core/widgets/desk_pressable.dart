import 'package:flutter/material.dart';

import '../../theme/colors.dart';

/// عنصرٌ يُنقر بالفأر **ويصله الكيبورد**: Tab إليه ثمّ Enter أو Space — بإطار تركيزٍ لا يظهر إلّا مع الكيبورد
/// (لا مع الفأر)، ومؤشّر اليد وحالة المرور كما كانت.
///
/// قبله كانت عناصر الحاسبة المرسومة يدويّاً (القائمة الجانبيّة، أرقام الرئيسيّة، أيّام «التجديدات القادمة»،
/// صفوف الجدول) `MouseRegion` + `GestureDetector` لا يصلها Tab أصلاً — والتركيز الظاهر وتشغيل كلّ شيءٍ
/// بالكيبورد قاعدةٌ أولى في إرشادات الواجهات (ui-ux-pro-max: focus-states · keyboard-nav).
///
/// [builder] يرسم العنصر بحالة المرور؛ والإطار يُرسم فوقه بشكل [radius] فلا يغيّر حجمه (لا قفزة).
class DeskPressable extends StatefulWidget {
  const DeskPressable({
    super.key,
    required this.onTap,
    required this.builder,
    this.radius = BorderRadius.zero,
    this.onSecondaryTapUp,
    this.onLongPressStart,
    this.semanticLabel,
    this.selected,
  });

  /// `null` = غير قابلٍ للنقر (لا مؤشّر يد ولا تركيز).
  final VoidCallback? onTap;
  final Widget Function(BuildContext context, bool hovered) builder;
  final BorderRadius radius;
  final GestureTapUpCallback? onSecondaryTapUp;
  final GestureLongPressStartCallback? onLongPressStart;
  final String? semanticLabel;

  /// للقارئ الصوتيّ: العنصر المختار (القسم الحاليّ، الصفّ المفتوح).
  final bool? selected;

  @override
  State<DeskPressable> createState() => _DeskPressableState();
}

class _DeskPressableState extends State<DeskPressable> {
  bool _hover = false;
  bool _focus = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    return Semantics(
      button: enabled,
      selected: widget.selected,
      label: widget.semanticLabel,
      child: FocusableActionDetector(
        enabled: enabled,
        mouseCursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
        onShowHoverHighlight: (v) {
          if (v != _hover) setState(() => _hover = v);
        },
        onShowFocusHighlight: (v) {
          if (v != _focus) setState(() => _focus = v);
        },
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) {
            widget.onTap?.call();
            return null;
          }),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          onSecondaryTapUp: widget.onSecondaryTapUp,
          onLongPressStart: widget.onLongPressStart,
          child: DecoratedBox(
            position: DecorationPosition.foreground,
            decoration: BoxDecoration(
              borderRadius: widget.radius,
              border: _focus ? Border.all(color: AppColors.brandAccent, width: 2) : null,
            ),
            child: widget.builder(context, _hover && enabled),
          ),
        ),
      ),
    );
  }
}
