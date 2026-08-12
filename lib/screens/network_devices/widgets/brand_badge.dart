import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Brand badge — أيقونة أصليّة مرسومة يدوياً لكل brand.
///
/// **لماذا رسم يدوي وليس logos الشركات؟**
/// استعمال شعارات الشركات (Mikrotik/UBNT/Cisco…) يعرّض التطبيق للرفض
/// من App Store/Play Store بسبب انتهاك trademark. الحل: أشكال هندسيّة
/// أصليّة تُوحي بالبراند بدون نسخ الشعار الفعلي.
///
/// **التصميم** — كل brand له:
/// - لون توقيعي (color) — الألوان بحدّ ذاتها ليست trademark
/// - شكل هندسي مميّز (custom painter) — 100% أصلي
/// - gradient خفيف للعمق
///
/// **الأشكال**:
/// - Mikrotik: قمّتان مثلّثتان (توحي بالحرف M وبراج البثّ)
/// - UBNT:     أقواس متحدة المركز (موجات wifi)
/// - Mimosa:   زهرة سداسيّة (mimosa = زهرة النبات)
/// - Cisco:    3 أعمدة رأسيّة متدرّجة (توحي بجسر الشبكة)
/// - Roji:     دائرة مع نقطة مركزيّة (نمط بسيط)
/// - Other:    شبكة نقاط (generic device)
class BrandBadge extends StatelessWidget {
  final String brand;
  final double size;

  const BrandBadge({
    super.key,
    required this.brand,
    this.size = 44,
  });

  static const _brands = {
    'mikrotik': (color: Color(0xFF293251), accent: Color(0xFFED2E38)),
    'ubnt':     (color: Color(0xFF0559C9), accent: Color(0xFF00A2E1)),
    'mimosa':   (color: Color(0xFFEA580C), accent: Color(0xFFFB923C)),
    'cisco':    (color: Color(0xFF049FD9), accent: Color(0xFF00BCEB)),
    'roji':     (color: Color(0xFF1F7A3D), accent: Color(0xFF34C759)),
    'other':    (color: Color(0xFF6B7280), accent: Color(0xFF9CA3AF)),
  };

  @override
  Widget build(BuildContext context) {
    final info = _brands[brand] ?? _brands['other']!;
    return Container(
      width: size, height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [info.color, info.accent],
        ),
        borderRadius: BorderRadius.circular(size * 0.24),
        boxShadow: [
          BoxShadow(
            color: info.color.withValues(alpha: 0.25),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: CustomPaint(
        painter: _BrandGlyphPainter(brand: brand),
      ),
    );
  }

  /// اللون الأساسي للـbrand — للاستعمال في أماكن أخرى (chips, borders)
  static Color colorFor(String brand) {
    return _brands[brand]?.color ?? _brands['other']!.color;
  }
}

/// يرسم الشكل الهندسي المميّز لكل brand داخل حدود الـContainer.
class _BrandGlyphPainter extends CustomPainter {
  final String brand;
  const _BrandGlyphPainter({required this.brand});

  @override
  void paint(Canvas canvas, Size size) {
    final white = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.09
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final whiteFill = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    switch (brand) {
      case 'mikrotik':
        _paintMikrotik(canvas, size, white);
        break;
      case 'ubnt':
        _paintUbnt(canvas, size, white);
        break;
      case 'mimosa':
        _paintMimosa(canvas, size, whiteFill);
        break;
      case 'cisco':
        _paintCisco(canvas, size, white);
        break;
      case 'roji':
        _paintRoji(canvas, size, white, whiteFill);
        break;
      default:
        _paintOther(canvas, size, whiteFill);
    }
  }

  /// Mikrotik: قمّتان مثلّثتان — توحي بالحرف M وبراج البثّ.
  /// شكل هندسي أصلي، لا يشبه اللوقو الفعلي.
  void _paintMikrotik(Canvas canvas, Size size, Paint p) {
    final w = size.width;
    final h = size.height;
    final path = Path()
      ..moveTo(w * 0.20, h * 0.75)
      ..lineTo(w * 0.35, h * 0.30)
      ..lineTo(w * 0.50, h * 0.55)
      ..lineTo(w * 0.65, h * 0.30)
      ..lineTo(w * 0.80, h * 0.75);
    canvas.drawPath(path, p);
    // dot صغير فوق للتأكيد على "قمّة"
    final dotPaint = Paint()..color = Colors.white..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(w * 0.35, h * 0.22), w * 0.05, dotPaint);
    canvas.drawCircle(Offset(w * 0.65, h * 0.22), w * 0.05, dotPaint);
  }

  /// UBNT: 3 أقواس متّحدة المركز (موجات wifi) — يوحي بالبثّ اللاسلكي.
  void _paintUbnt(Canvas canvas, Size size, Paint p) {
    final w = size.width;
    final h = size.height;
    final center = Offset(w * 0.5, h * 0.72);
    final radii = [w * 0.16, w * 0.28, w * 0.40];
    for (final r in radii) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: r),
        math.pi + math.pi * 0.15,     // start slightly before top
        math.pi - math.pi * 0.30,     // sweep about 150 degrees
        false, p,
      );
    }
    // dot عند القاعدة
    final dot = Paint()..color = Colors.white..style = PaintingStyle.fill;
    canvas.drawCircle(center, w * 0.05, dot);
  }

  /// Mimosa: زهرة سداسيّة — mimosa هو اسم نبات، هذا الشكل يذكّر بالزهرة.
  void _paintMimosa(Canvas canvas, Size size, Paint fill) {
    final w = size.width;
    final h = size.height;
    final center = Offset(w * 0.5, h * 0.5);
    final petalRadius = w * 0.18;
    final orbitRadius = w * 0.22;
    // 6 بتلات دائريّة
    for (int i = 0; i < 6; i++) {
      final angle = (math.pi * 2 * i / 6) - math.pi / 2;
      final pos = Offset(
        center.dx + math.cos(angle) * orbitRadius,
        center.dy + math.sin(angle) * orbitRadius,
      );
      canvas.drawCircle(pos, petalRadius, fill);
    }
    // مركز أغمق قليلاً للتباين
    final centerPaint = Paint()..color = const Color(0xFFEA580C);
    canvas.drawCircle(center, w * 0.13, centerPaint);
  }

  /// Cisco: 4 أعمدة رأسيّة متدرّجة (توحي بمعمار جسر — بدون نسخ).
  void _paintCisco(Canvas canvas, Size size, Paint p) {
    final w = size.width;
    final h = size.height;
    final baseY = h * 0.80;
    final barWidth = w * 0.06;
    final gap = w * 0.06;
    final startX = w * 0.5 - (barWidth * 4 + gap * 3) / 2;
    // ارتفاعات متدرّجة (ملحوظة تصميميّة: تبدأ منخفضة → عالية → منخفضة)
    final heights = [h * 0.35, h * 0.55, h * 0.55, h * 0.35];
    for (int i = 0; i < 4; i++) {
      final x = startX + i * (barWidth + gap);
      final rect = Rect.fromLTRB(x, baseY - heights[i], x + barWidth, baseY);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(barWidth * 0.4)),
        Paint()..color = Colors.white,
      );
    }
  }

  /// Roji: دائرة كبيرة بحدود + نقطة مركزيّة (نمط بسيط لبراند صغير).
  void _paintRoji(Canvas canvas, Size size, Paint stroke, Paint fill) {
    final w = size.width;
    final h = size.height;
    final center = Offset(w * 0.5, h * 0.5);
    canvas.drawCircle(center, w * 0.32, stroke);
    canvas.drawCircle(center, w * 0.10, fill);
  }

  /// Other: 3x3 شبكة نقاط — generic device grid.
  void _paintOther(Canvas canvas, Size size, Paint fill) {
    final w = size.width;
    final h = size.height;
    final startX = w * 0.28;
    final startY = h * 0.28;
    final step = w * 0.22;
    final radius = w * 0.055;
    for (int i = 0; i < 3; i++) {
      for (int j = 0; j < 3; j++) {
        canvas.drawCircle(
          Offset(startX + j * step, startY + i * step),
          radius, fill,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _BrandGlyphPainter old) => old.brand != brand;
}

/// Type icon — أيقونة صغيرة تدلّ على نوع الجهاز (router/switch/link/sector/ap)
/// تُعرض إلى جانب brand badge أو داخله.
class TypeIcon extends StatelessWidget {
  final String type;
  final double size;
  final Color color;

  const TypeIcon({
    super.key,
    required this.type,
    this.size = 14,
    this.color = Colors.white,
  });

  static IconData iconFor(String type) {
    return switch (type) {
      'link' => LucideIcons.satellite,
      'switch' => LucideIcons.network,
      'sector' => LucideIcons.radioTower,
      'router' => LucideIcons.router,
      'ap' => LucideIcons.wifi,
      'camera' => LucideIcons.video,
      _ => LucideIcons.circuitBoard,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Icon(iconFor(type), size: size, color: color);
  }
}
