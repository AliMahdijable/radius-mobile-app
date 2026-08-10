import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Brand badge — أيقونة ملوّنة تحمل حرف/رمز الـbrand.
/// كل brand له لون + حرف مميّز، شبيه بلوقو الشركة الفعلي.
///
/// Mikrotik = MK برتقالي (لون شعارهم الرسمي)
/// UBNT     = UI أزرق فاتح (Ubiquiti brand)
/// Mimosa   = MM بنفسجي (لون شعارهم)
/// Cisco    = CS أزرق داكن (لون Cisco الرسمي)
/// Roji     = RJ أخضر (شعار روجي)
/// Other    = ▪ رمادي
class BrandBadge extends StatelessWidget {
  final String brand;
  final double size;
  final bool showText;

  const BrandBadge({
    super.key,
    required this.brand,
    this.size = 44,
    this.showText = true,
  });

  static const _brands = {
    'mikrotik': (color: Color(0xFF293251), accent: Color(0xFFED2E38), text: 'MK'),
    'ubnt':     (color: Color(0xFF0559C9), accent: Color(0xFF00A2E1), text: 'UI'),
    'mimosa':   (color: Color(0xFF7B3FF2), accent: Color(0xFFB794F6), text: 'MM'),
    'cisco':    (color: Color(0xFF049FD9), accent: Color(0xFF00BCEB), text: 'CS'),
    'roji':     (color: Color(0xFF1F7A3D), accent: Color(0xFF34C759), text: 'RJ'),
    'other':    (color: Color(0xFF6B7280), accent: Color(0xFF9CA3AF), text: '?'),
  };

  @override
  Widget build(BuildContext context) {
    final info = _brands[brand] ?? _brands['other']!;
    final fontSize = (size * 0.32).clamp(9.0, 18.0);
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
      alignment: Alignment.center,
      child: showText
          ? Text(
              info.text,
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: fontSize,
                letterSpacing: -0.5,
                fontFamily: 'monospace',
              ),
            )
          : Icon(_brandFallbackIcon(brand),
              color: Colors.white, size: size * 0.5),
    );
  }

  /// أيقونة احتياطيّة (لو showText=false)
  static IconData _brandFallbackIcon(String brand) {
    return switch (brand) {
      'mikrotik' || 'cisco' => LucideIcons.router,
      'ubnt' || 'mimosa' => LucideIcons.radioTower,
      _ => LucideIcons.circuitBoard,
    };
  }

  /// اللون الأساسي للـbrand — للاستعمال في أماكن أخرى (chips, borders)
  static Color colorFor(String brand) {
    return _brands[brand]?.color ?? _brands['other']!.color;
  }
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
