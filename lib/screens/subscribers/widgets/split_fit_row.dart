import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// صفٌّ بطرفين **لا يخرج من عرضه أبداً** — صفّ الباقة في كرت المشترك (المالك ١٤ نوفمبر: «بوضع المعلومات الهواي جاي الكتابه
/// تطلع من الكارتات»).
///
/// بدايته [lead] (يضيق: نصٌّ يُقصّ بـ«…») ثمّ [tail] الملاصق له (ثابت: السعر)، ونهايته [end] (زرّ الموقع وقياسات الجهاز).
/// - يتّسع الثلاثة على سطرٍ واحد — ولو بعد تضييق [lead] حتى [minLead] — ⇒ سطرٌ واحد تماماً كالـ`Row`.
/// - وإلّا ينزل [end] لسطرٍ ثانٍ تحته بعرض الصفّ كلّه (وهو يلتفّ داخله إن كان `Wrap`)، ويأخذ [lead] و[tail] السطر الأوّل.
///
/// كان `Row` فيه [end] ابناً غير مرن: يُقاس بعرضٍ غير محدود ويأخذ ما يشاء، فإذا كثرت قراءاته («وضع VPN»: إشارة + CCQ +
/// الكيبل + شارة VPN) أو كبُر الخطّ أو ضاق الهاتف خرج النصّ من الكرت. القياس هنا بالتخطيط نفسه (لا بتقدير عرض النصوص).
class SplitFitRow extends MultiChildRenderObjectWidget {
  SplitFitRow({
    super.key,
    required Widget lead,
    required Widget tail,
    required Widget end,
    required this.minLead,
    this.gap = 6,
    this.runGap = 6,
  }) : super(children: [lead, tail, end]);

  /// أقلّ عرضٍ يبقى لـ[lead] على السطر المشترك (أيقونته + بضعة أحرف)؛ أضيق منه ⇒ ينزل [end]. ومن كان عرضه الطبيعيّ أقلّ
  /// فحدّه عرضه الطبيعيّ.
  final double minLead;

  /// أقلّ فراغٍ بين طرف البداية و[end] على السطر الواحد.
  final double gap;

  /// الفراغ الرأسيّ بين السطرين حين ينزل [end].
  final double runGap;

  @override
  RenderSplitFitRow createRenderObject(BuildContext context) => RenderSplitFitRow(
        minLead: minLead,
        gap: gap,
        runGap: runGap,
        textDirection: Directionality.of(context),
      );

  @override
  void updateRenderObject(BuildContext context, RenderSplitFitRow renderObject) {
    renderObject
      ..minLead = minLead
      ..gap = gap
      ..runGap = runGap
      ..textDirection = Directionality.of(context);
  }
}

class SplitFitParentData extends ContainerBoxParentData<RenderBox> {}

typedef _Fit = ({Size size, Size lead, Size tail, Size end, bool split, double line1});

class RenderSplitFitRow extends RenderBox
    with ContainerRenderObjectMixin<RenderBox, SplitFitParentData>, RenderBoxContainerDefaultsMixin<RenderBox, SplitFitParentData> {
  RenderSplitFitRow({
    required double minLead,
    required double gap,
    required double runGap,
    required TextDirection textDirection,
  })  : _minLead = minLead,
        _gap = gap,
        _runGap = runGap,
        _textDirection = textDirection;

  double _minLead;
  double get minLead => _minLead;
  set minLead(double v) {
    if (v == _minLead) return;
    _minLead = v;
    markNeedsLayout();
  }

  double _gap;
  double get gap => _gap;
  set gap(double v) {
    if (v == _gap) return;
    _gap = v;
    markNeedsLayout();
  }

  double _runGap;
  double get runGap => _runGap;
  set runGap(double v) {
    if (v == _runGap) return;
    _runGap = v;
    markNeedsLayout();
  }

  TextDirection _textDirection;
  TextDirection get textDirection => _textDirection;
  set textDirection(TextDirection v) {
    if (v == _textDirection) return;
    _textDirection = v;
    markNeedsLayout();
  }

  /// هل نزل [SplitFitRow.end] لسطرٍ ثانٍ في آخر تخطيط؟ (للاختبار.)
  bool get debugSplit => _split;
  bool _split = false;

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! SplitFitParentData) child.parentData = SplitFitParentData();
  }

  RenderBox get _lead => firstChild!;
  RenderBox get _tail => childAfter(_lead)!;
  RenderBox get _end => childAfter(_tail)!;

  _Fit _fit(BoxConstraints constraints, ChildLayouter layoutChild) {
    const free = BoxConstraints();
    final w = constraints.maxWidth;
    // العرض الطبيعيّ لكلّ طرف: بلا قيد (النهاية سطرٌ واحد، والبداية بلا قصّ).
    var end = layoutChild(_end, free);
    var lead = layoutChild(_lead, free);
    final tail = layoutChild(_tail, w.isFinite ? BoxConstraints(maxWidth: w) : free);
    final hasEnd = end.width > 0;
    final between = hasEnd ? gap : 0.0;
    if (!w.isFinite) {
      final h = math.max(lead.height, math.max(tail.height, end.height));
      return (size: Size(lead.width + tail.width + between + end.width, h), lead: lead, tail: tail, end: end, split: false, line1: h);
    }
    final need = math.min(lead.width, minLead) + tail.width + between + end.width;
    if (!hasEnd || need <= w + 0.01) {
      final room = math.max(0.0, w - tail.width - between - end.width);
      if (lead.width > room) lead = layoutChild(_lead, BoxConstraints(maxWidth: room));
      final h = math.max(lead.height, math.max(tail.height, end.height));
      return (size: Size(w, h), lead: lead, tail: tail, end: end, split: false, line1: h);
    }
    // لا يتّسع: السطر الأوّل للبداية كلّها، والنهاية تحتها بعرض الصفّ.
    final room = math.max(0.0, w - tail.width);
    if (lead.width > room) lead = layoutChild(_lead, BoxConstraints(maxWidth: room));
    end = layoutChild(_end, BoxConstraints(maxWidth: w));
    final line1 = math.max(lead.height, tail.height);
    return (size: Size(w, line1 + runGap + end.height), lead: lead, tail: tail, end: end, split: true, line1: line1);
  }

  @override
  void performLayout() {
    final f = _fit(constraints, ChildLayoutHelper.layoutChild);
    _split = f.split;
    size = constraints.constrain(f.size);
    final w = f.size.width;
    final rtl = textDirection == TextDirection.rtl;
    double mid(double h, double of) => (of - h) / 2;
    (_lead.parentData! as SplitFitParentData).offset =
        Offset(rtl ? w - f.lead.width : 0, mid(f.lead.height, f.line1));
    (_tail.parentData! as SplitFitParentData).offset =
        Offset(rtl ? w - f.lead.width - f.tail.width : f.lead.width, mid(f.tail.height, f.line1));
    (_end.parentData! as SplitFitParentData).offset = Offset(
      rtl ? 0 : w - f.end.width,
      f.split ? f.line1 + runGap : mid(f.end.height, f.line1),
    );
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) =>
      constraints.constrain(_fit(constraints, ChildLayoutHelper.dryLayoutChild).size);

  @override
  double computeMinIntrinsicWidth(double height) => _tail.getMinIntrinsicWidth(double.infinity);

  @override
  double computeMaxIntrinsicWidth(double height) {
    final end = _end.getMaxIntrinsicWidth(double.infinity);
    return _lead.getMaxIntrinsicWidth(double.infinity) + _tail.getMaxIntrinsicWidth(double.infinity) + (end > 0 ? gap + end : 0);
  }

  @override
  double computeMinIntrinsicHeight(double width) => computeMaxIntrinsicHeight(width);

  @override
  double computeMaxIntrinsicHeight(double width) =>
      _fit(BoxConstraints(maxWidth: width), ChildLayoutHelper.dryLayoutChild).size.height;

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) => defaultComputeDistanceToFirstActualBaseline(baseline);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);

  @override
  void paint(PaintingContext context, Offset offset) => defaultPaint(context, offset);
}
