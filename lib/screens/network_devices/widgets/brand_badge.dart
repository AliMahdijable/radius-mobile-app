import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Brand badge — تصميم قريب من هويّة كل براند بدون نسخ اللوقو الفعلي.
///
/// **الآمن قانونياً**:
/// - الحرف الواحد (M/U/R) ليس trademark
/// - الألوان بحدّ ذاتها ليست trademark
/// - الأشكال الهندسيّة العامّة (شرائط، دوائر) generic
///
/// **الخطر**: نسخ الـwordmark الكامل ("MIKROTIK"/"UBIQUITI") أو استعمال
/// نفس الـfont الرسمي أو نفس التركيب الدقيق. نتجنّب كل هذا.
///
/// **الاستراتيجيّة لكل براند**:
/// - Mikrotik  → حرف M عريض + شريط أحمر (يوحي بالبراند بدون نسخ الـwordmark)
/// - Ubiquiti  → حرف U عريض داخل حلقة (نمط مينيمالي مثل هويّتهم)
/// - Mimosa    → حرف M مع نقطة (mimosa = زهرة، نقطة توحي بذلك)
/// - Cisco     → أعمدة رأسيّة متدرّجة (توحي بجسر الشبكة)
/// - Roji      → حرف R نظيف
/// - Other     → 3 نقاط generic
class BrandBadge extends StatelessWidget {
  final String brand;
  final double size;

  const BrandBadge({
    super.key,
    required this.brand,
    this.size = 44,
  });

  static const _brands = {
    'mikrotik': (color: Color(0xFF293251), accent: Color(0xFF3D4A73)),
    'ubnt':     (color: Color(0xFF0559C9), accent: Color(0xFF0074E8)),
    'mimosa':   (color: Color(0xFFEA580C), accent: Color(0xFFF97316)),
    'cisco':    (color: Color(0xFF049FD9), accent: Color(0xFF00BCEB)),
    'roji':     (color: Color(0xFF1F7A3D), accent: Color(0xFF34C759)),
    'other':    (color: Color(0xFF4B5563), accent: Color(0xFF6B7280)),
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
        borderRadius: BorderRadius.circular(size * 0.22),
        boxShadow: [
          BoxShadow(
            color: info.color.withValues(alpha: 0.28),
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

// ═══════════════════════════════════════════════════════════
// Custom painters — رسم بحروف + عناصر تصميم لكل براند
// ═══════════════════════════════════════════════════════════

class _BrandGlyphPainter extends CustomPainter {
  final String brand;
  const _BrandGlyphPainter({required this.brand});

  @override
  void paint(Canvas canvas, Size size) {
    switch (brand) {
      case 'mikrotik':
        _paintMikrotik(canvas, size);
        break;
      case 'ubnt':
        _paintUbnt(canvas, size);
        break;
      case 'mimosa':
        _paintMimosa(canvas, size);
        break;
      case 'cisco':
        _paintCisco(canvas, size);
        break;
      case 'roji':
        _paintLetter(canvas, size, 'R');
        break;
      default:
        _paintOther(canvas, size);
    }
  }

  /// كتابة حرف مركزي (helper مشترك)
  void _paintLetter(Canvas canvas, Size size, String letter,
      {Color color = Colors.white, double sizeFactor = 0.55}) {
    final tp = TextPainter(
      text: TextSpan(
        text: letter,
        style: TextStyle(
          color: color,
          fontSize: size.width * sizeFactor,
          fontWeight: FontWeight.w900,
          letterSpacing: -1,
          height: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    )..layout();
    tp.paint(canvas, Offset(
      (size.width - tp.width) / 2,
      (size.height - tp.height) / 2,
    ));
  }

  /// Mikrotik: M عريض + شريط أحمر تحت (توقيع براندهم — دون نسخ الـwordmark).
  void _paintMikrotik(Canvas canvas, Size size) {
    _paintLetter(canvas, size, 'M', sizeFactor: 0.60);
    // شريط أحمر تحت الحرف
    final barPaint = Paint()..color = const Color(0xFFED2E38);
    final barY = size.height * 0.78;
    final barRect = Rect.fromLTWH(
      size.width * 0.20, barY,
      size.width * 0.60, size.height * 0.08,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(barRect, Radius.circular(size.width * 0.04)),
      barPaint,
    );
  }

  /// UBNT: حرف U داخل حلقة رفيعة (نمط مينيمالي).
  void _paintUbnt(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final ring = Paint()
      ..color = Colors.white.withValues(alpha: 0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.05;
    canvas.drawCircle(Offset(w / 2, h / 2), w * 0.38, ring);
    _paintLetter(canvas, size, 'U', sizeFactor: 0.52);
  }

  /// Mimosa: حرف M + نقطة (mimosa = زهرة، النقطة تُلمّح بذلك).
  void _paintMimosa(Canvas canvas, Size size) {
    _paintLetter(canvas, size, 'M', sizeFactor: 0.55);
    // نقطة صغيرة أعلى-يمين للتمييز
    final dot = Paint()..color = Colors.white;
    canvas.drawCircle(
      Offset(size.width * 0.78, size.height * 0.24),
      size.width * 0.07,
      dot,
    );
  }

  /// Cisco: 5 أعمدة رأسيّة متدرّجة (توحي بجسر — بدون نسخ اللوقو الأصلي).
  void _paintCisco(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final baseY = h * 0.78;
    final barWidth = w * 0.08;
    final gap = w * 0.05;
    final startX = w * 0.5 - (barWidth * 5 + gap * 4) / 2;
    // أعمدة بارتفاع متدرّج: قصير-متوسّط-عالي-متوسّط-قصير (bell curve بسيط)
    final heights = <double>[
      h * 0.28, h * 0.42, h * 0.52, h * 0.42, h * 0.28,
    ];
    final paint = Paint()..color = Colors.white;
    for (int i = 0; i < 5; i++) {
      final x = startX + i * (barWidth + gap);
      final rect = Rect.fromLTRB(x, baseY - heights[i], x + barWidth, baseY);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(barWidth * 0.3)),
        paint,
      );
    }
  }

  /// Other: 3 نقاط أفقيّة generic device.
  void _paintOther(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final paint = Paint()..color = Colors.white;
    for (int i = 0; i < 3; i++) {
      canvas.drawCircle(
        Offset(w * (0.30 + i * 0.20), h * 0.50),
        w * 0.06,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BrandGlyphPainter old) => old.brand != brand;
}

// ═══════════════════════════════════════════════════════════
// Type icon (لم يتغيّر)
// ═══════════════════════════════════════════════════════════

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

