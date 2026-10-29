import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../models/tower_layout.dart';
import '../../../theme/colors.dart';
import '../../../theme/typography.dart';

/// رسم البرج — كلّه بتوكنات اللوحة (لا لون خام): الهيكل بألوان النصّ الهادئة، والحالة بـ[AppTone].
///
/// المنظر الجانبيّ «شبه ثلاثيّ الأبعاد»: كلّ جهازٍ على حلقة مستواه، ودوران البرج زاويةُ نظر ([view])؛ الجهاز
/// الذي يواجهنا أكبر وأوضح، والذي خلف البرج أصغر وباهت. والمنظر من الأعلى بوصلةٌ واتّجاه كلّ جهاز.

/// نسبة تسطيح الأرض في المنظر الجانبيّ (الكاميرا أعلى قليلاً من الأفق).
const double kTowerSquash = 0.22;

/// هندسة المنظر الجانبيّ لمقاسٍ وشكل برجٍ معيّنين — تُحسب مرّةً ويقرؤها الرسم والأجهزة فوقه.
@immutable
class TowerGeometry {
  TowerGeometry(this.size, this.settings) {
    final w = size.width;
    final h = size.height;
    cx = w / 2;
    groundY = h - 30;
    final usable = h - 74;
    final f = 0.5 + 0.5 * ((settings.heightM - 6) / 54).clamp(0.0, 1.0);
    towerH = usable * f;
    topY = groundY - towerH;
    baseHalf = math.min(w * 0.11, 42.0);
    topHalf = settings.type == TowerType.lattice ? 7.0 : 2.6;
    buildingH = settings.type == TowerType.roof ? math.min(usable * 0.3, 92.0) : 0.0;
    final n = settings.rings.clamp(1, 8);
    final firstY = settings.type == TowerType.roof ? topY + 8 : topY + towerH * 0.08;
    final lastY = settings.type == TowerType.roof ? groundY - buildingH - 12 : topY + towerH * 0.8;
    ringYs = [for (var i = 0; i < n; i++) n == 1 ? firstY : firstY + i * (lastY - firstY) / (n - 1)];
  }

  final Size size;
  final TowerSettings settings;
  late final double cx;
  late final double groundY;
  late final double towerH;
  late final double topY;
  late final double baseHalf;
  late final double topHalf;
  late final double buildingH;
  late final List<double> ringYs;

  /// نصف عرض الهيكل عند ارتفاعٍ ما (الأرجل تقترب نحو القمّة).
  double halfAt(double y) {
    if (settings.type == TowerType.roof) return 3;
    final bottom = groundY;
    final t = ((bottom - y) / towerH).clamp(0.0, 1.0);
    final base = settings.type == TowerType.lattice ? baseHalf : 5.0;
    return base - (base - topHalf) * t;
  }

  /// رقم الحلقة لكلّ مستوى (بعدد الحلقات المختار).
  int ringOf(TowerLevel level) {
    final n = ringYs.length;
    return switch (level) {
      TowerLevel.top => 0,
      TowerLevel.upper => n >= 3 ? math.max(1, (n * 0.3).round()) : 0,
      TowerLevel.mid => n >= 3 ? (n * 0.55).round().clamp(1, n - 1) : (n - 1),
      TowerLevel.lower => n - 1,
      TowerLevel.base => n - 1,
    };
  }

  double ringRadius(int i) => halfAt(ringYs[i]) + 14;

  /// نصف قطر الحلقة بأجهزتها — المالك ٢٩ أكتوبر: «حل مشكلة تزاحم الأجهزة». كانت الحلقة بعرض الهيكل نفسه (~٣٠px)
  /// فتتكدّس تسعة سكاتر فوق الأرجل وفوق بعضها؛ صارت تتّسع بعدد أجهزتها (كأذرع البرج الحقيقيّة) حتى حدّ المنظر.
  double armRadius(int i, int crowd) {
    final base = ringRadius(i) + 8;
    if (crowd <= 1) return base;
    final maxR = math.max(base, size.width / 2 - 48);
    return (22.0 + crowd * 15.0).clamp(base, maxR);
  }

  /// ارتفاع الحلقة على المنظر (القمّة فوق أولى الحلقات قليلاً).
  double ringY(TowerLevel level) => level == TowerLevel.top ? ringYs[0] - 6 : ringYs[ringOf(level)];

  /// مكان جهازٍ على حلقته من زاوية النظر — `cz > -0.25` يعني أمام البرج. [crowd] = أجهزة حلقته.
  ({double x, double y, double sx, double cz}) place(TowerLevel level, int azimuth, double view, {int crowd = 1}) {
    final i = ringOf(level);
    final r = armRadius(i, crowd);
    final rel = (azimuth - view) * math.pi / 180;
    final sx = math.sin(rel);
    final cz = math.cos(rel);
    final y = ringY(level);
    return (x: cx + r * sx, y: y + r * kTowerSquash * cz, sx: sx, cz: cz);
  }

  /// منبت ذراع الجهاز على سطح الهيكل عند حلقته — منه يمتدّ الذراع إلى الجهاز.
  Offset armRoot(TowerLevel level, double sx, double cz) {
    final y = ringY(level);
    final h = halfAt(y);
    return Offset(cx + h * sx, y + h * kTowerSquash * cz);
  }

  /// الكابينة على يمين قاعدة البرج: مستطيلٌ يتّسع لأجهزتها.
  Rect cabinet(int count) {
    final slots = count.clamp(1, 4);
    final width = 34.0 + 22.0 * math.min(slots, 2);
    final height = 22.0 + 20.0 * ((slots + 1) ~/ 2);
    final left = math.min(cx + baseHalf + 26, size.width - width - 10);
    return Rect.fromLTWH(left, groundY - height, width, height);
  }
}

/// هيكل البرج بالمنظر الجانبيّ: الأرض والأرجل والتقاطعات والحلقات والكابينة والضوء الأحمر في القمّة.
class SideTowerPainter extends CustomPainter {
  SideTowerPainter({required this.geo, required this.cabinetCount});

  final TowerGeometry geo;
  final int cabinetCount;

  @override
  void paint(Canvas canvas, Size size) {
    final g = geo;
    final strong = Paint()
      ..color = AppColors.textBody
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    final soft = Paint()
      ..color = AppColors.textLow
      ..strokeWidth = 1.2;
    final ringPaint = Paint()
      ..color = AppColors.textMid
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    // الظلّ على الأرض.
    canvas.drawOval(
      Rect.fromCenter(center: Offset(g.cx, g.groundY + 6), width: g.baseHalf * 6, height: 14),
      Paint()..color = AppColors.surfaceSunken,
    );

    switch (g.settings.type) {
      case TowerType.lattice:
        _lattice(canvas, strong, soft);
      case TowerType.pole:
        _pole(canvas);
      case TowerType.roof:
        _roof(canvas, strong, soft);
    }

    for (var i = 0; i < g.ringYs.length; i++) {
      final y = g.ringYs[i];
      final rx = g.ringRadius(i);
      canvas.drawOval(Rect.fromCenter(center: Offset(g.cx, y), width: rx * 2, height: rx * 2 * kTowerSquash), ringPaint);
    }

    // القمّة: عمود الهوائيّ والضوء الأحمر.
    final tipTop = g.topY - 20;
    canvas.drawLine(Offset(g.cx, g.topY), Offset(g.cx, tipTop), Paint()
      ..color = AppColors.textBody
      ..strokeWidth = 2);
    canvas.drawCircle(Offset(g.cx, tipTop - 2), 3.6, Paint()..color = AppColors.error);

    // الكابينة والكيبل إليها.
    final cab = g.cabinet(cabinetCount);
    final cable = Path()
      ..moveTo(g.cx + g.halfAt(g.groundY - 12), g.groundY - 12)
      ..cubicTo(cab.left - 14, g.groundY - 12, cab.left - 8, cab.top + 12, cab.left, cab.top + 12);
    canvas.drawPath(cable, Paint()
      ..color = AppColors.textMid
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6);
    final r = RRect.fromRectAndRadius(cab, const Radius.circular(5));
    canvas.drawRRect(r, Paint()..color = AppColors.surfaceSunken);
    canvas.drawRRect(r, Paint()
      ..color = AppColors.textMid
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4);
  }

  void _lattice(Canvas canvas, Paint strong, Paint soft) {
    final g = geo;
    // العمود الخلفيّ (الرِّجل الثالثة) — أهدأ.
    canvas.drawLine(Offset(g.cx, g.groundY - 8), Offset(g.cx, g.topY + 4), Paint()
      ..color = AppColors.textLow
      ..strokeWidth = 2);
    final steps = math.max(4, (g.towerH / 26).round());
    final zig = Path();
    for (var j = 0; j <= steps; j++) {
      final y = g.groundY - j * g.towerH / steps;
      final half = g.halfAt(y);
      final x = j.isEven ? g.cx - half : g.cx + half;
      if (j == 0) {
        zig.moveTo(x, y);
      } else {
        zig.lineTo(x, y);
      }
      if (j > 0 && j < steps) {
        canvas.drawLine(Offset(g.cx - half, y), Offset(g.cx + half, y), soft);
      }
    }
    canvas.drawPath(zig, Paint()
      ..color = AppColors.textMid
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5);
    canvas.drawLine(Offset(g.cx - g.baseHalf, g.groundY), Offset(g.cx - g.topHalf, g.topY), strong);
    canvas.drawLine(Offset(g.cx + g.baseHalf, g.groundY), Offset(g.cx + g.topHalf, g.topY), strong);
  }

  void _pole(Canvas canvas) {
    final g = geo;
    final path = Path()
      ..moveTo(g.cx - 5.5, g.groundY)
      ..lineTo(g.cx - g.topHalf, g.topY)
      ..lineTo(g.cx + g.topHalf, g.topY)
      ..lineTo(g.cx + 5.5, g.groundY)
      ..close();
    canvas.drawPath(path, Paint()..color = AppColors.surfaceSunken);
    canvas.drawPath(path, Paint()
      ..color = AppColors.textBody
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeJoin = StrokeJoin.round);
    canvas.drawLine(Offset(g.cx - 18, g.groundY), Offset(g.cx + 18, g.groundY), Paint()
      ..color = AppColors.textMid
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round);
  }

  void _roof(Canvas canvas, Paint strong, Paint soft) {
    final g = geo;
    final roofY = g.groundY - g.buildingH;
    final bw = math.min(g.size.width * 0.42, 170.0);
    final body = Rect.fromLTWH(g.cx - bw / 2, roofY, bw, g.buildingH);
    canvas.drawRect(body, Paint()..color = AppColors.surfaceSunken);
    canvas.drawRect(body, Paint()
      ..color = AppColors.textMid
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4);
    // شبابيك.
    final win = Paint()
      ..color = AppColors.textLow
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final cols = math.max(2, (bw / 42).floor());
    for (var c = 0; c < cols; c++) {
      final x = body.left + (c + 0.5) * bw / cols - 8;
      for (var r = 0; r < 2; r++) {
        final y = roofY + 12 + r * (g.buildingH - 24) / 2;
        if (y + 14 > g.groundY - 4) continue;
        canvas.drawRect(Rect.fromLTWH(x, y, 16, 12), win);
      }
    }
    canvas.drawLine(Offset(body.left - 6, roofY), Offset(body.right + 6, roofY), Paint()
      ..color = AppColors.textBody
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round);
    // الصاري وحبال الشدّ.
    canvas.drawLine(Offset(g.cx, roofY), Offset(g.cx, g.topY), strong);
    final guyY = g.topY + (roofY - g.topY) * 0.45;
    canvas.drawLine(Offset(g.cx, guyY), Offset(g.cx - bw * 0.32, roofY), soft);
    canvas.drawLine(Offset(g.cx, guyY), Offset(g.cx + bw * 0.32, roofY), soft);
  }

  @override
  bool shouldRepaint(SideTowerPainter old) =>
      old.geo.size != geo.size || old.geo.settings != geo.settings || old.cabinetCount != cabinetCount;
}

/// الطبقة المتحرّكة فوق الهيكل: حزمة الجهاز المختار، وخطّ كلّ لنك وسير بياناته (شرطاتٌ تتحرّك نحو البرج).
class SideOverlayPainter extends CustomPainter {
  SideOverlayPainter({
    required this.beam,
    required this.beamColor,
    required this.links,
    required this.phase,
    required this.front,
    this.arms = const [],
  });

  /// أذرع الأجهزة: من سطح الهيكل إلى الجهاز (تُظهر لأيّ حلقةٍ ينتمي حين تتباعد الأجهزة).
  final List<({Offset from, Offset to})> arms;

  /// نقاط مخروط الحزمة (الأولى رأسه عند الجهاز)، أو فارغة.
  final List<Offset> beam;
  final Color beamColor;

  /// كلّ لنك: من الجهاز إلى خارج المنظر باتّجاهه.
  final List<({Offset from, Offset to})> links;

  /// طور الشرطات 0..1 (يتحرّك مع الوقت).
  final double phase;

  /// أيّ الطبقتين هذه (أمام البرج أم خلفه) — للتعليق فقط، والرسم واحد.
  final bool front;

  @override
  void paint(Canvas canvas, Size size) {
    if (arms.isNotEmpty) {
      final arm = Paint()
        ..color = AppColors.textMid.withValues(alpha: front ? 0.55 : 0.28)
        ..strokeWidth = front ? 1.6 : 1.2
        ..strokeCap = StrokeCap.round;
      for (final a in arms) {
        canvas.drawLine(a.from, a.to, arm);
      }
    }
    if (beam.length >= 3) {
      final p = Path()..addPolygon(beam, true);
      canvas.drawPath(p, Paint()..color = beamColor.withValues(alpha: 0.14));
      canvas.drawPath(p, Paint()
        ..color = beamColor.withValues(alpha: 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..strokeJoin = StrokeJoin.round);
    }
    for (final l in links) {
      canvas.drawLine(l.from, l.to, Paint()
        ..color = AppColors.brand.withValues(alpha: 0.12)
        ..strokeWidth = 7
        ..strokeCap = StrokeCap.round);
      _dashed(canvas, l.to, l.from, Paint()
        ..color = AppColors.brand
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round);
    }
  }

  // شرطاتٌ من [a] إلى [b] تتقدّم مع [phase] — سير البيانات نحو الجهاز.
  void _dashed(Canvas canvas, Offset a, Offset b, Paint paint) {
    const dash = 8.0;
    const gap = 5.0;
    final total = (b - a).distance;
    if (total < 1) return;
    final dir = (b - a) / total;
    var d = -((1 - phase) * (dash + gap));
    while (d < total) {
      final s = math.max(0.0, d);
      final e = math.min(total, d + dash);
      if (e > s) canvas.drawLine(a + dir * s, a + dir * e, paint);
      d += dash + gap;
    }
  }

  @override
  bool shouldRepaint(SideOverlayPainter old) =>
      old.phase != phase || old.beam != beam || old.links != links || old.beamColor != beamColor || old.arms != arms;
}

/// المنظر من الأعلى: بوصلةٌ ودوائر، وقوسٌ لكلّ سكتر بلون حالته، وخطٌّ لكلّ لنك نحو وجهته.
class TopViewPainter extends CustomPainter {
  TopViewPainter({required this.wedges, required this.links, required this.phase, required this.textDirection});

  final List<({int azimuth, int half, double radius, Color color, bool selected, bool approx})> wedges;
  final List<({int azimuth, bool selected})> links;
  final double phase;
  final TextDirection textDirection;

  static Offset polar(Offset c, double r, num azimuth) {
    final a = azimuth * math.pi / 180;
    return Offset(c.dx + r * math.sin(a), c.dy - r * math.cos(a));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final rMax = math.min(size.width, size.height) / 2 - 26;
    canvas.drawCircle(c, rMax, Paint()..color = AppColors.surfaceSunken);
    final grid = Paint()
      ..color = AppColors.border
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawCircle(c, rMax, grid);
    canvas.drawCircle(c, rMax * 0.66, grid);
    canvas.drawCircle(c, rMax * 0.33, grid);
    canvas.drawLine(Offset(c.dx, c.dy - rMax), Offset(c.dx, c.dy + rMax), grid);
    canvas.drawLine(Offset(c.dx - rMax, c.dy), Offset(c.dx + rMax, c.dy), grid);

    for (final w in wedges.where((w) => !w.selected)) {
      _wedge(canvas, c, w);
    }
    for (final w in wedges.where((w) => w.selected)) {
      _wedge(canvas, c, w);
    }

    for (final l in links) {
      final end = polar(c, rMax + 4, l.azimuth);
      canvas.drawLine(end, c, Paint()
        ..color = AppColors.brand.withValues(alpha: l.selected ? 0.22 : 0.12)
        ..strokeWidth = 7
        ..strokeCap = StrokeCap.round);
      const dash = 8.0;
      const gap = 5.0;
      final total = (c - end).distance;
      final dir = (c - end) / total;
      var d = -((1 - phase) * (dash + gap));
      final paint = Paint()
        ..color = AppColors.brand
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round;
      while (d < total) {
        final s = math.max(0.0, d);
        final e = math.min(total, d + dash);
        if (e > s) canvas.drawLine(end + dir * s, end + dir * e, paint);
        d += dash + gap;
      }
    }

    canvas.drawCircle(c, 8, Paint()..color = AppColors.brand);
    canvas.drawCircle(c, 8, Paint()
      ..color = AppColors.surface
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5);

    for (final (label, az) in const [('شمال', 0), ('شرق', 90), ('جنوب', 180), ('غرب', 270)]) {
      final tp = TextPainter(
        text: TextSpan(text: label, style: AppType.micro(color: AppColors.textMid)),
        textDirection: textDirection,
      )..layout();
      final p = polar(c, rMax + 15, az);
      tp.paint(canvas, p - Offset(tp.width / 2, tp.height / 2));
    }
  }

  void _wedge(
    Canvas canvas,
    Offset c,
    ({int azimuth, int half, double radius, Color color, bool selected, bool approx}) w,
  ) {
    final rect = Rect.fromCircle(center: c, radius: w.radius);
    final start = (w.azimuth - w.half - 90) * math.pi / 180;
    final sweep = (w.half * 2) * math.pi / 180;
    final path = Path()
      ..moveTo(c.dx, c.dy)
      ..arcTo(rect, start, sweep, false)
      ..close();
    canvas.drawPath(path, Paint()..color = w.color.withValues(alpha: w.selected ? 0.3 : 0.14));
    final stroke = Paint()
      ..color = w.color.withValues(alpha: w.selected ? 1 : 0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = w.selected ? 2.4 : 1.2;
    if (w.approx && !w.selected) {
      // التقريبيّ بخطٍّ متقطّع حتى يُثبَّت.
      final metric = path.computeMetrics();
      for (final m in metric) {
        var d = 0.0;
        while (d < m.length) {
          canvas.drawPath(m.extractPath(d, math.min(m.length, d + 5)), stroke);
          d += 9;
        }
      }
    } else {
      canvas.drawPath(path, stroke);
    }
  }

  @override
  bool shouldRepaint(TopViewPainter old) => true;
}

/// أيقونة الجهاز بشكله — نفسها بالبرج والقوائم ولوحة اختيار الشكل.
class DeviceGlyph extends StatelessWidget {
  const DeviceGlyph({
    super.key,
    required this.shape,
    this.size = 34,
    this.color,
    this.flip = false,
    this.dashed = false,
  });

  final TowerShape shape;
  final double size;

  /// لون الخطّ (الافتراضيّ لون النصّ الهادئ).
  final Color? color;

  /// مرآةٌ أفقيّة — الجهاز على يمين البرج يواجه اليمين.
  final bool flip;

  /// إطارٌ متقطّع (اتّجاهٌ تقريبيّ).
  final bool dashed;

  static Size aspect(TowerShape s) => switch (s) {
        TowerShape.sector => const Size(0.6, 1),
        TowerShape.dish => const Size(1.2, 1),
        TowerShape.panel => const Size(1, 1),
        TowerShape.omni => const Size(0.36, 1),
        TowerShape.router => const Size(1.7, 1),
        TowerShape.sw => const Size(2.2, 1),
        TowerShape.olt => const Size(1.6, 1),
        TowerShape.other => const Size(1, 1),
      };

  /// المقاس الفعليّ: [size] للضلع الأطول، والآخر بنسبة الشكل.
  static Size boxFor(TowerShape shape, double size) {
    final a = aspect(shape);
    final ratio = a.width / a.height;
    return ratio >= 1 ? Size(size, size / ratio) : Size(size * ratio, size);
  }

  @override
  Widget build(BuildContext context) {
    final box = boxFor(shape, size);
    final painter = _GlyphPainter(shape: shape, ink: color ?? AppColors.textBody, dashed: dashed);
    final child = SizedBox(width: box.width, height: box.height, child: CustomPaint(painter: painter));
    return flip ? Transform.flip(flipX: true, child: child) : child;
  }
}

class _GlyphPainter extends CustomPainter {
  _GlyphPainter({required this.shape, required this.ink, required this.dashed});

  final TowerShape shape;
  final Color ink;
  final bool dashed;

  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width;
    final h = s.height;
    final line = Paint()
      ..color = ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.2, h / 26)
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    final fill = Paint()..color = AppColors.surface;
    final shade = Paint()..color = AppColors.surfaceSunken;
    final fine = Paint()
      ..color = AppColors.textLow
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    void box(Rect r, double radius, {Paint? paint}) {
      final rr = RRect.fromRectAndRadius(r, Radius.circular(radius));
      canvas.drawRRect(rr, paint ?? fill);
      canvas.drawRRect(rr, line);
    }

    switch (shape) {
      case TowerShape.sector:
        // لوحة الهوائيّ الطويلة وعلبة الراديو خلفها.
        box(Rect.fromLTWH(w * 0.08, h * 0.02, w * 0.56, h * 0.86), w * 0.24);
        canvas.drawLine(Offset(w * 0.36, h * 0.14), Offset(w * 0.36, h * 0.76), fine);
        box(Rect.fromLTWH(w * 0.52, h * 0.52, w * 0.44, h * 0.32), w * 0.08, paint: shade);
      case TowerShape.dish:
        final dish = Rect.fromLTWH(w * 0.02, h * 0.04, w * 0.42, h * 0.92);
        canvas.drawOval(dish, fill);
        canvas.drawOval(dish, line);
        canvas.drawOval(Rect.fromLTWH(w * 0.12, h * 0.24, w * 0.22, h * 0.52), fine);
        canvas.drawLine(Offset(w * 0.3, h * 0.5), Offset(w * 0.8, h * 0.5), line);
        box(Rect.fromLTWH(w * 0.76, h * 0.38, w * 0.2, h * 0.24), 2, paint: shade);
      case TowerShape.panel:
        box(Rect.fromLTWH(w * 0.1, h * 0.08, w * 0.8, h * 0.8), w * 0.18);
        box(Rect.fromLTWH(w * 0.24, h * 0.2, w * 0.52, h * 0.42), 2, paint: shade);
        canvas.drawLine(Offset(w * 0.3, h * 0.74), Offset(w * 0.7, h * 0.74), fine);
      case TowerShape.omni:
        box(Rect.fromLTWH(w * 0.18, h * 0.0, w * 0.64, h * 0.74), w * 0.3);
        canvas.drawLine(Offset(w * 0.18, h * 0.26), Offset(w * 0.82, h * 0.26), fine);
        canvas.drawLine(Offset(w * 0.18, h * 0.5), Offset(w * 0.82, h * 0.5), fine);
        box(Rect.fromLTWH(w * 0.02, h * 0.74, w * 0.96, h * 0.24), 2, paint: shade);
      case TowerShape.router:
        box(Rect.fromLTWH(w * 0.03, h * 0.18, w * 0.94, h * 0.64), h * 0.12, paint: shade);
        for (var i = 0; i < 4; i++) {
          canvas.drawRect(Rect.fromLTWH(w * (0.1 + i * 0.12), h * 0.4, w * 0.08, h * 0.22), fine);
        }
        final led = Paint()..color = AppColors.success;
        canvas.drawCircle(Offset(w * 0.74, h * 0.38), h * 0.07, led);
        canvas.drawCircle(Offset(w * 0.86, h * 0.38), h * 0.07, led);
      case TowerShape.sw:
        box(Rect.fromLTWH(w * 0.02, h * 0.24, w * 0.96, h * 0.52), h * 0.1, paint: shade);
        for (var i = 0; i < 7; i++) {
          canvas.drawRect(Rect.fromLTWH(w * (0.07 + i * 0.11), h * 0.38, w * 0.07, h * 0.22), fine);
        }
      case TowerShape.olt:
        box(Rect.fromLTWH(w * 0.03, h * 0.2, w * 0.66, h * 0.6), h * 0.1, paint: shade);
        for (var i = 0; i < 4; i++) {
          canvas.drawCircle(Offset(w * (0.14 + i * 0.13), h * 0.5), h * 0.08, fine);
        }
        final fiber = Paint()
          ..color = AppColors.warning
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.3;
        for (final dy in [0.32, 0.5, 0.68]) {
          canvas.drawPath(
            Path()
              ..moveTo(w * 0.69, h * dy)
              ..quadraticBezierTo(w * 0.84, h * dy, w * 0.98, h * (dy + (dy - 0.5) * 0.9)),
            fiber,
          );
        }
      case TowerShape.other:
        box(Rect.fromLTWH(w * 0.12, h * 0.12, w * 0.76, h * 0.76), w * 0.2);
        final dot = Paint()..color = AppColors.textLow;
        for (var i = 0; i < 3; i++) {
          canvas.drawCircle(Offset(w * (0.32 + i * 0.18), h * 0.5), h * 0.06, dot);
        }
    }

    if (dashed) {
      final r = Rect.fromLTWH(-3, -3, w + 6, h + 6);
      final p = Path()..addRRect(RRect.fromRectAndRadius(r, const Radius.circular(6)));
      final dash = Paint()
        ..color = AppColors.warning
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2;
      for (final m in p.computeMetrics()) {
        var d = 0.0;
        while (d < m.length) {
          canvas.drawPath(m.extractPath(d, math.min(m.length, d + 4)), dash);
          d += 7;
        }
      }
    }
  }

  @override
  bool shouldRepaint(_GlyphPainter old) => old.shape != shape || old.ink != ink || old.dashed != dashed;
}

/// بوصلة شاشة «مكان الجهاز»: الاتّجاه المحفوظ قوسٌ (متقطّعٌ إن كان تقريبيّاً)، والإبرة اتّجاه الهاتف الآن.
class CompassDialPainter extends CustomPainter {
  CompassDialPainter({
    required this.savedAzimuth,
    required this.half,
    required this.heading,
    required this.fixed,
    required this.textDirection,
  });

  final int? savedAzimuth;
  final int half;

  /// اتّجاه الهاتف الآن، أو `null` بلا بوصلة.
  final double? heading;
  final bool fixed;
  final TextDirection textDirection;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = math.min(size.width, size.height) / 2 - 4;
    canvas.drawCircle(c, r, Paint()..color = AppColors.surfaceSunken);
    canvas.drawCircle(c, r, Paint()
      ..color = AppColors.border
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1);
    final tick = Paint()
      ..color = AppColors.textLow
      ..strokeWidth = 1.4;
    for (var a = 0; a < 360; a += 30) {
      canvas.drawLine(TopViewPainter.polar(c, r - 10, a), TopViewPainter.polar(c, r - 2, a), tick);
    }
    for (final (label, az) in const [('شمال', 0), ('شرق', 90), ('جنوب', 180), ('غرب', 270)]) {
      final tp = TextPainter(
        text: TextSpan(text: label, style: AppType.microBold(color: AppColors.textMid)),
        textDirection: textDirection,
      )..layout();
      final p = TopViewPainter.polar(c, r - 28, az);
      tp.paint(canvas, p - Offset(tp.width / 2, tp.height / 2));
    }
    if (savedAzimuth != null) {
      final color = fixed ? AppColors.success : AppColors.warning;
      final rect = Rect.fromCircle(center: c, radius: r - 14);
      final start = (savedAzimuth! - half - 90) * math.pi / 180;
      final path = Path()
        ..moveTo(c.dx, c.dy)
        ..arcTo(rect, start, half * 2 * math.pi / 180, false)
        ..close();
      canvas.drawPath(path, Paint()..color = color.withValues(alpha: 0.18));
      final stroke = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6;
      if (fixed) {
        canvas.drawPath(path, stroke);
      } else {
        for (final m in path.computeMetrics()) {
          var d = 0.0;
          while (d < m.length) {
            canvas.drawPath(m.extractPath(d, math.min(m.length, d + 5)), stroke);
            d += 9;
          }
        }
      }
    }
    if (heading != null) {
      final tip = TopViewPainter.polar(c, r - 16, heading!);
      canvas.drawLine(c, tip, Paint()
        ..color = AppColors.brand
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round);
      canvas.drawCircle(tip, 5.5, Paint()..color = AppColors.brand);
      canvas.drawCircle(tip, 5.5, Paint()
        ..color = AppColors.surface
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2);
    }
    canvas.drawCircle(c, 6, Paint()..color = AppColors.brand);
  }

  @override
  bool shouldRepaint(CompassDialPainter old) =>
      old.savedAzimuth != savedAzimuth || old.half != half || old.heading != heading || old.fixed != fixed;
}
