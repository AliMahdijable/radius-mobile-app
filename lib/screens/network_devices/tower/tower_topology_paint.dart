import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../models/tower_layout.dart';
import '../../../theme/colors.dart';
import 'tower_topology_logic.dart';

/// رسم «الترابط» — بلغة رسم البرج نفسها (tower_paint.dart): الهيكل بألوان النصّ الهادئة، الضوء الأحمر في القمّة، وسير
/// البيانات شرطاتٌ تتحرّك؛ وكلّه بتوكنات اللوحة فيصحّ بالفاتح والداكن.

/// برجٌ مصغّر بنوعه (شبكيّ · عمود · سطح بناية) — رمز البرج على رسم الترابط. [waves] موجتا بثٍّ عند القمّة للبرج الرئيسيّ.
class MiniTowerPainter extends CustomPainter {
  MiniTowerPainter({required this.type, required this.strong, required this.soft, this.waves});

  final TowerType type;
  final Color strong;
  final Color soft;
  final Color? waves;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final cx = w / 2;
    final ground = h - 3.0;
    const top = 13.0;
    final legs = Paint()
      ..color = strong
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final brace = Paint()
      ..color = soft
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    // الأرض
    canvas.drawLine(Offset(cx - w * 0.36, ground + 1), Offset(cx + w * 0.36, ground + 1), brace);

    switch (type) {
      case TowerType.lattice:
        final baseHalf = w * 0.25;
        const topHalf = 2.6;
        double halfAt(double y) => baseHalf - (baseHalf - topHalf) * ((ground - y) / (ground - top));
        const steps = 4;
        final zig = Path();
        for (var j = 0; j <= steps; j++) {
          final y = ground - j * (ground - top) / steps;
          final half = halfAt(y);
          final x = j.isEven ? cx - half : cx + half;
          j == 0 ? zig.moveTo(x, y) : zig.lineTo(x, y);
          if (j > 0 && j < steps) canvas.drawLine(Offset(cx - half, y), Offset(cx + half, y), brace);
        }
        canvas.drawPath(zig, brace);
        canvas.drawLine(Offset(cx - baseHalf, ground), Offset(cx - topHalf, top), legs);
        canvas.drawLine(Offset(cx + baseHalf, ground), Offset(cx + topHalf, top), legs);
      case TowerType.pole:
        final body = Path()
          ..moveTo(cx - 3.4, ground)
          ..lineTo(cx - 1.5, top)
          ..lineTo(cx + 1.5, top)
          ..lineTo(cx + 3.4, ground)
          ..close();
        canvas.drawPath(body, Paint()..color = strong);
        // ذراعان صغيران — يُعرف أنّه عمود أجهزة لا خطّاً
        canvas.drawLine(Offset(cx - 7, top + 9), Offset(cx + 7, top + 9), brace);
        canvas.drawLine(Offset(cx - 5.5, top + 17), Offset(cx + 5.5, top + 17), brace);
      case TowerType.roof:
        final bh = (ground - top) * 0.46;
        final bw = w * 0.56;
        final box = Rect.fromLTWH(cx - bw / 2, ground - bh, bw, bh);
        canvas.drawRect(box, Paint()..color = soft.withValues(alpha: 0.18));
        canvas.drawRect(box, brace);
        // شبّاكان
        final win = Paint()..color = soft;
        canvas.drawRect(Rect.fromLTWH(box.left + bw * 0.18, box.top + bh * 0.3, bw * 0.2, bh * 0.28), win);
        canvas.drawRect(Rect.fromLTWH(box.right - bw * 0.38, box.top + bh * 0.3, bw * 0.2, bh * 0.28), win);
        canvas.drawLine(Offset(box.left - 2, box.top), Offset(box.right + 2, box.top), legs);
        canvas.drawLine(Offset(cx, box.top), Offset(cx, top), legs);
        canvas.drawLine(Offset(cx, top + (box.top - top) * 0.4), Offset(cx - bw * 0.36, box.top), brace);
        canvas.drawLine(Offset(cx, top + (box.top - top) * 0.4), Offset(cx + bw * 0.36, box.top), brace);
    }

    // عمود الهوائيّ والضوء الأحمر — كالبرج الكبير
    canvas.drawLine(Offset(cx, top), Offset(cx, top - 6), Paint()
      ..color = strong
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round);
    canvas.drawCircle(Offset(cx, top - 8), 2.3, Paint()..color = AppColors.error);

    final wave = waves;
    if (wave != null) {
      final p = Paint()
        ..color = wave
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;
      final c = Offset(cx, top - 8);
      for (final r in const [6.5, 10.5]) {
        final rect = Rect.fromCircle(center: c, radius: r);
        canvas.drawArc(rect, -math.pi / 5, math.pi * 2 / 5, false, p..color = wave.withValues(alpha: r > 8 ? 0.55 : 1));
        canvas.drawArc(rect, math.pi - math.pi / 5, math.pi * 2 / 5, false, p);
      }
    }
  }

  @override
  bool shouldRepaint(MiniTowerPainter old) =>
      old.type != type || old.strong != strong || old.soft != soft || old.waves != waves;
}

/// وصلةٌ جاهزة للرسم: مسارها ([TopoRoute]) وحالها ونوعها.
@immutable
class TopoEdgeShape {
  const TopoEdgeShape({required this.route, required this.state, this.tree = true, this.hasPill = true, this.fiber = false});

  final TopoRoute route;
  final LinkState state;
  final bool tree;

  /// كيبلٌ ضوئيّ: خطٌّ متّصل تسير عليه نبضات — واللنك اللاسلكيّ شرطاتٌ بلا خطّ.
  final bool fiber;

  /// رأس الوصلة يدخل حبّة السرعة فوق البرج الفرعيّ (وصلة الشجرة) — وإلّا سهمٌ عند البرج نفسه.
  final bool hasPill;

  /// منحنى عموديّ الطرفين (كمخطّطات الهيكل) حين ينزل الفرعيّ عن الرئيسيّ، وخطٌّ مستقيم حين يتجاوران؛ وعبر الممرّ: منحنى
  /// إليه، ثمّ نزولٌ مستقيم بين الأبراج، ثمّ منحنى إلى الفرعيّ.
  Path path() {
    final from = route.from;
    final to = route.to;
    final p = Path()..moveTo(from.dx, from.dy);
    void curve(Offset a, Offset b) {
      final dy = b.dy - a.dy;
      if (dy.abs() < 8 || (b.dx - a.dx).abs() < 1) {
        p.lineTo(b.dx, b.dy);
      } else {
        final mid = a.dy + dy * 0.5;
        p.cubicTo(a.dx, mid, b.dx, mid, b.dx, b.dy);
      }
    }

    final x = route.channelX;
    if (x == null) {
      curve(from, to);
    } else {
      final top = Offset(x, route.channelTop!);
      final bottom = Offset(x, route.channelBottom!);
      curve(from, top);
      p.lineTo(bottom.dx, bottom.dy);
      curve(bottom, to);
    }
    return p;
  }

  /// منتصف المسار — مكان حبّة وصلةٍ ليست فوق برجها.
  Offset get middle {
    final m = path().computeMetrics().firstOrNull;
    if (m == null) return route.from;
    return m.getTangentForOffset(m.length / 2)?.position ?? route.from;
  }

  @override
  bool operator ==(Object other) =>
      other is TopoEdgeShape &&
      other.route == route &&
      other.state == state &&
      other.tree == tree &&
      other.hasPill == hasPill &&
      other.fiber == fiber;

  @override
  int get hashCode => Object.hash(route, state, tree, hasPill, fiber);
}

/// لون حال الوصلة.
Color linkStateColor(LinkState s) => switch (s) {
      LinkState.ok => AppColors.success,
      LinkState.fair => AppColors.warningFill,
      LinkState.weak => AppColors.error,
      LinkState.down => AppColors.error,
      LinkState.unknown => AppColors.textLow,
    };

/// وصلات الأبراج بلون حالها وسيرها من الرئيسيّ للفرعيّ — وكلّ نوعٍ برسمه:
///   • اللنك اللاسلكيّ: شرطاتٌ تسير (بلا خطٍّ تحتها)؛ الواقع منقّطٌ ساكن، وما لم يُقرأ شرطاتٌ رماديّة ساكنة.
///   • الكيبل الضوئيّ: خطٌّ متّصل تسير عليه نبضات؛ الواقع وما لم يُقرأ خطٌّ رماديّ ساكن.
/// والواقع من النوعين عليه ✕.
class TopoEdgesPainter extends CustomPainter {
  TopoEdgesPainter({required this.edges, required this.flow}) : super(repaint: flow);

  final List<TopoEdgeShape> edges;

  /// طور الشرطات 0..1 — الرسّام يُعاد رسمه معه وحده (لا إعادة بناءٍ للشجرة كلّ إطار).
  final Animation<double> flow;

  static const _dash = 7.0;
  static const _gap = 5.0;

  /// نبضة الكيبل: خرزةٌ قصيرة على الخطّ بدورة شرطات اللنك نفسها (١٢) — فتسير بسرعته وتُعاد بلا قفزة.
  static const _pulse = 3.0;
  static const _pulseGap = 9.0;

  /// مسار كلّ وصلة — يُحسب مرّةً لهذا الرسّام (يُعاد رسمه كلّ إطارٍ مع [flow]، ولا يُعاد إنشاؤه إلّا بتغيّر الوصلات).
  late final List<Path> _paths = [for (final e in edges) e.path()];

  @override
  void paint(Canvas canvas, Size size) {
    final phase = flow.value;
    for (var i = 0; i < edges.length; i++) {
      final e = edges[i];
      final path = _paths[i];
      final color = linkStateColor(e.state);
      final flowing = e.state == LinkState.ok || e.state == LinkState.fair || e.state == LinkState.weak;
      Paint stroke(Color c, double w) => Paint()
        ..color = c
        ..style = PaintingStyle.stroke
        ..strokeWidth = w
        ..strokeCap = StrokeCap.round;
      if (e.fiber) {
        if (flowing) {
          canvas.drawPath(path, stroke(color.withValues(alpha: 0.13), e.tree ? 8 : 6));
          canvas.drawPath(path, stroke(color.withValues(alpha: 0.55), e.tree ? 2.4 : 1.9));
          _dashed(canvas, path, _pulse, _pulseGap, phase, stroke(color, e.tree ? 4.2 : 3.4));
        } else {
          canvas.drawPath(path, stroke(e.state == LinkState.down ? AppColors.textLow : AppColors.border, 2));
        }
      } else if (flowing) {
        canvas.drawPath(path, stroke(color.withValues(alpha: 0.13), e.tree ? 7 : 5));
        _dashed(canvas, path, _dash, _gap, phase, stroke(color, e.tree ? 2.3 : 1.8));
      } else if (e.state == LinkState.down) {
        _dashed(canvas, path, 2, 5, 0, stroke(AppColors.textLow, 2));
      } else {
        _dashed(canvas, path, _dash, _gap, 0, stroke(AppColors.border, 2));
      }
      if (!e.hasPill) _arrow(canvas, path, flowing ? color : AppColors.textLow);
      if (e.state == LinkState.down) _cross(canvas, path);
    }
  }

  /// شرطاتٌ على المسار تتقدّم مع [phase] من أوّله لآخره — تُجمع مساراً واحداً فتُرسم بنداءٍ واحد.
  static void _dashed(Canvas canvas, Path path, double dash, double gap, double phase, Paint paint) {
    final out = Path();
    for (final m in path.computeMetrics()) {
      var d = -((1 - phase) * (dash + gap));
      while (d < m.length) {
        final s = math.max(0.0, d);
        final e = math.min(m.length, d + dash);
        if (e > s) out.addPath(m.extractPath(s, e), Offset.zero);
        d += dash + gap;
      }
    }
    canvas.drawPath(out, paint);
  }

  /// رأس سهمٍ عند نهاية المسار باتّجاهه.
  static void _arrow(Canvas canvas, Path path, Color color) {
    final m = path.computeMetrics().firstOrNull;
    final t = m?.getTangentForOffset(m.length);
    if (t == null) return;
    final dir = t.vector / (t.vector.distance == 0 ? 1 : t.vector.distance);
    final n = Offset(-dir.dy, dir.dx);
    final tip = t.position;
    final back = tip - dir * 7;
    canvas.drawPath(
      Path()
        ..moveTo(tip.dx, tip.dy)
        ..lineTo(back.dx + n.dx * 4, back.dy + n.dy * 4)
        ..lineTo(back.dx - n.dx * 4, back.dy - n.dy * 4)
        ..close(),
      Paint()..color = color,
    );
  }

  /// ✕ في منتصف وصلةٍ واقعة.
  static void _cross(Canvas canvas, Path path) {
    final m = path.computeMetrics().firstOrNull;
    final c = m?.getTangentForOffset(m.length * 0.42)?.position;
    if (c == null) return;
    canvas.drawCircle(c, 8, Paint()..color = AppColors.surface);
    canvas.drawCircle(c, 8, Paint()
      ..color = AppColors.error
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6);
    final p = Paint()
      ..color = AppColors.error
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(c + const Offset(-3, -3), c + const Offset(3, 3), p);
    canvas.drawLine(c + const Offset(3, -3), c + const Offset(-3, 3), p);
  }

  @override
  bool shouldRepaint(TopoEdgesPainter old) => old.flow != flow || !_same(old.edges, edges);

  static bool _same(List<TopoEdgeShape> a, List<TopoEdgeShape> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// لـ[ui.PathMetric] — أوّل مقياسٍ أو لا شيء.
extension on ui.PathMetrics {
  ui.PathMetric? get firstOrNull {
    final it = iterator;
    return it.moveNext() ? it.current : null;
  }
}
