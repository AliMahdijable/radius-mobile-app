import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/colors.dart';
import '../../theme/spacing.dart';

/// أدوات جداول الحاسبة (المالك ٢٤ أكتوبر بصورة جدول المشتركين: «الجداول تبين كانها محصورة… لو عرض كل الحقول
/// ماكو امكانية يمرر ويسحب، ولا الجدول بيه صلاحيّة يلگص ويزيد حجم الأعمدة»):
/// - [DeskHScroll] موضع التمرير الأفقيّ لجدولٍ واحد، يشترك فيه الرأس وكلّ الصفوف وشريط التمرير؛
/// - [DeskHViewport] نافذةٌ تعرض جزءاً من محتوىً أعرض منها بحسب الموضع (الصفوف تبقى في القائمة العموديّة نفسها
///   فلا يضيع الرأس المثبَّت ولا البناء الكسول للصفوف)؛
/// - [DeskHScrollbar] شريطٌ يُسحب، و[DeskHScrollInput] عجلة الفأرة مع Shift، والعجلة الأفقيّة، وسحب لوحة اللمس؛
/// - [DeskColResizeHandle] مقبض حافّة العمود: يُسحب فيتّسع العمود أو يضيق، والنقر المزدوج يعيده.
///
/// الاتّجاه: الموضع مسافةٌ من **بداية** الجدول (يمينه بالعربيّ)، فالتمرير يكشف ما بعد آخر عمودٍ ظاهر.

/// موضع التمرير الأفقيّ. المقاسات تُضبط أثناء البناء ([setMetrics]) بلا إخطار — من يقرأها يُبنى في الإطار نفسه.
class DeskHScroll extends ChangeNotifier {
  double _offset = 0;
  double _viewport = 0;
  double _content = 0;

  double get offset => _offset;
  double get viewport => _viewport;
  double get content => _content;
  double get maxOffset => math.max(0, _content - _viewport);
  bool get scrollable => maxOffset > 0.5;

  /// عرض النافذة والمحتوى — يُستدعى من بناء الشاشة. الموضع يُقصّ إلى المدى الجديد (نافذةٌ اتّسعت).
  void setMetrics({required double viewport, required double content}) {
    _viewport = viewport;
    _content = content;
    _offset = _offset.clamp(0, maxOffset).toDouble();
  }

  void jumpTo(double value) {
    final v = value.clamp(0, maxOffset).toDouble();
    if ((v - _offset).abs() < 0.01) return;
    _offset = v;
    notifyListeners();
  }

  void scrollBy(double delta) => jumpTo(_offset + delta);
}

/// يعرض [child] (بعرض [contentWidth]) داخل نافذةٍ بعرض [width] (أو كلّ العرض المتاح)، مزاحاً بموضع [scroll] —
/// المخفيّ لا يُرسم ولا يُنقر. (بلا ظلالٍ ولا خطوطٍ على الحوافّ: الجدول قطعةٌ واحدة تتحرّك — «بدون ما يظهر الصفحة مقسومة».)
class DeskHViewport extends StatelessWidget {
  const DeskHViewport({
    super.key,
    required this.scroll,
    required this.contentWidth,
    required this.child,
    this.width,
  });

  final DeskHScroll scroll;
  final double? width;
  final double contentWidth;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return SizedBox(
      width: width,
      child: ClipRect(
        // الإزاحة **داخل** OverflowBox: هو يرفض النقر خارج حدوده، فلو أُزيح هو نفسه لضاع النقر على ما ظهر بالتمرير
        // (يُرسم ولا يُنقر).
        child: OverflowBox(
          alignment: AlignmentDirectional.centerStart,
          minWidth: contentWidth,
          maxWidth: contentWidth,
          child: AnimatedBuilder(
            animation: scroll,
            builder: (context, inner) => Transform.translate(
              // البداية يمين بالعربيّ: التقدّم يُزيح المحتوى يميناً فيظهر ما على يساره.
              offset: Offset(rtl ? scroll.offset : -scroll.offset, 0),
              child: inner,
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// يحوّل إلى [scroll]: عجلة الفأرة مع Shift، والعجلة الأفقيّة، والسحب الأفقيّ على لوحة اللمس — والعجلة العاديّة
/// تبقى للتمرير العموديّ.
class DeskHScrollInput extends StatelessWidget {
  const DeskHScrollInput({super.key, required this.scroll, required this.child});

  final DeskHScroll scroll;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return Listener(
      onPointerSignal: (e) {
        if (e is! PointerScrollEvent || !scroll.scrollable) return;
        final shift = HardwareKeyboard.instance.isShiftPressed;
        double delta = 0;
        if (shift && e.kind == PointerDeviceKind.mouse) {
          // Shift + العجلة لأسفل ⇒ نحو نهاية الجدول (كالمتصفّح وإكسل).
          delta = e.scrollDelta.dy != 0 ? e.scrollDelta.dy : e.scrollDelta.dx;
        } else if (e.scrollDelta.dx.abs() > e.scrollDelta.dy.abs()) {
          delta = rtl ? -e.scrollDelta.dx : e.scrollDelta.dx;
        }
        if (delta == 0) return;
        GestureBinding.instance.pointerSignalResolver.register(e, (_) => scroll.scrollBy(delta));
      },
      onPointerPanZoomUpdate: (e) {
        if (!scroll.scrollable) return;
        final d = e.localPanDelta;
        if (d.dx.abs() <= d.dy.abs()) return;
        // سحبٌ طبيعيّ: الأصابع يميناً ⇒ المحتوى يميناً.
        scroll.scrollBy(rtl ? d.dx : -d.dx);
      },
      child: child,
    );
  }
}

/// شريط التمرير الأفقيّ تحت الجدول: المقبض بنسبة الظاهر من المحتوى، يُسحب، والنقر على المسار يقلب صفحة.
class DeskHScrollbar extends StatefulWidget {
  const DeskHScrollbar({super.key, required this.scroll});

  final DeskHScroll scroll;

  static const double height = 14;

  @override
  State<DeskHScrollbar> createState() => _DeskHScrollbarState();
}

class _DeskHScrollbarState extends State<DeskHScrollbar> {
  bool _hover = false;
  bool _drag = false;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final s = widget.scroll;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return AnimatedBuilder(
      animation: s,
      builder: (context, _) {
        if (!s.scrollable) return const SizedBox(height: DeskHScrollbar.height);
        return LayoutBuilder(builder: (context, c) {
          final track = c.maxWidth;
          final thumb = math.max(48.0, track * (s.viewport / s.content)).clamp(0.0, track).toDouble();
          final room = math.max(1.0, track - thumb);
          final pos = room * (s.offset / s.maxOffset);
          final active = _hover || _drag;
          // مسافة المقبض على المسار ⇐ موضع التمرير (بعكس الاتّجاه حين تكون البداية يميناً).
          double toOffset(double dx) => (rtl ? -dx : dx) * (s.maxOffset / room);
          return MouseRegion(
            onEnter: (_) => setState(() => _hover = true),
            onExit: (_) => setState(() => _hover = false),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: (d) {
                // النقر على المسار: صفحةٌ نحو مكان النقرة.
                final x = rtl ? track - d.localPosition.dx : d.localPosition.dx;
                if (x < pos) {
                  s.scrollBy(-s.viewport * 0.9);
                } else if (x > pos + thumb) {
                  s.scrollBy(s.viewport * 0.9);
                }
              },
              onHorizontalDragStart: (_) => setState(() => _drag = true),
              onHorizontalDragUpdate: (d) => s.scrollBy(toOffset(d.delta.dx)),
              onHorizontalDragEnd: (_) => setState(() => _drag = false),
              onHorizontalDragCancel: () => setState(() => _drag = false),
              child: SizedBox(
                height: DeskHScrollbar.height,
                child: Stack(
                  children: [
                    Positioned.fill(
                      top: 3,
                      bottom: 3,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: AppColors.surfaceSunken,
                          borderRadius: BorderRadius.circular(R.pill),
                          border: Border.all(color: AppColors.border),
                        ),
                      ),
                    ),
                    PositionedDirectional(
                      start: pos,
                      width: thumb,
                      top: active ? 2 : 3,
                      bottom: active ? 2 : 3,
                      child: MouseRegion(
                        cursor: SystemMouseCursors.grab,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 120),
                          decoration: BoxDecoration(
                            color: active ? AppColors.textLow : AppColors.borderStrong,
                            borderRadius: BorderRadius.circular(R.pill),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        });
      },
    );
  }
}

/// مقبض حافّة العمود في رأس الجدول — يوضع على **نهاية** خليّة العمود. السحب نحو النهاية يوسّعه (يساراً بالعربيّ)،
/// والنقر المزدوج يعيد عرضه الافتراضيّ. [onDrag] يستلم التغيّر بوحدة «عرض العمود» بعد حساب الاتّجاه.
class DeskColResizeHandle extends StatefulWidget {
  const DeskColResizeHandle({
    super.key,
    required this.onDrag,
    this.onEnd,
    this.onReset,
    this.tooltip,
  });

  final ValueChanged<double> onDrag;
  final VoidCallback? onEnd;
  final VoidCallback? onReset;
  final String? tooltip;

  static const double width = 12;

  @override
  State<DeskColResizeHandle> createState() => _DeskColResizeHandleState();
}

class _DeskColResizeHandleState extends State<DeskColResizeHandle> {
  bool _hover = false;
  bool _drag = false;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final active = _hover || _drag;
    Widget handle = MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: (_) => setState(() => _drag = true),
        onHorizontalDragUpdate: (d) => widget.onDrag(rtl ? -d.delta.dx : d.delta.dx),
        onHorizontalDragEnd: (_) {
          setState(() => _drag = false);
          widget.onEnd?.call();
        },
        onHorizontalDragCancel: () => setState(() => _drag = false),
        onDoubleTap: widget.onReset,
        child: SizedBox(
          width: DeskColResizeHandle.width,
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 100),
              width: active ? 3 : 1,
              height: active ? 28 : 18,
              decoration: BoxDecoration(
                color: active ? AppColors.brandAccent : AppColors.borderStrong,
                borderRadius: BorderRadius.circular(R.pill),
              ),
            ),
          ),
        ),
      ),
    );
    if (widget.tooltip != null) {
      handle = Tooltip(message: widget.tooltip!, waitDuration: const Duration(milliseconds: 900), child: handle);
    }
    return handle;
  }
}
