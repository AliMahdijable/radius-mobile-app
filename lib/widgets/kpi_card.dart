import 'package:flutter/material.dart';

/// لون مرئي لـKpiCard. يطابق tailwind tokens المستعمَلة بـv2 web
/// (`client-v2/src/pages/reports/_shared.tsx::KPI`).
enum KpiAccent { emerald, amber, rose, primary, blue, violet, slate }

/// كرت إحصائية واحد للتقارير المالية والتفعيلات.
/// تصميم مطابق لـv2 KPI: خلفية tinted خفيفة (10%) + border + أيقونة
/// يسار + label فوق value. تجنّب الـgradients الصارخة عشان يناسب
/// الـtheme بالـlight/dark.
class KpiCard extends StatelessWidget {
  final String label;
  final String value;
  final String? sub;
  final IconData icon;
  final KpiAccent accent;

  /// `compact` للـmobile الضيّق (أيقونة و value أصغر).
  final bool compact;

  /// `hero` للقيمة الرئيسية بالشاشة (مثل "صافي الربح") — full-width
  /// horizontal مع icon أكبر و value أكبر، بنفس روح الـtinted bg.
  final bool hero;

  const KpiCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.accent,
    this.sub,
    this.compact = false,
    this.hero = false,
  });

  /// (bg, fg-light, fg-dark, border)
  /// ألوان مأخوذة من tailwind 500/700/400 بحسب accent.
  ({Color bg, Color fgLight, Color fgDark, Color border}) _palette() {
    switch (accent) {
      case KpiAccent.emerald:
        return (
          bg: const Color(0xFF10B981).withValues(alpha: 0.10),
          fgLight: const Color(0xFF047857), // emerald-700
          fgDark: const Color(0xFF34D399), // emerald-400
          border: const Color(0xFF10B981).withValues(alpha: 0.25),
        );
      case KpiAccent.amber:
        return (
          bg: const Color(0xFFF59E0B).withValues(alpha: 0.10),
          fgLight: const Color(0xFFB45309), // amber-700
          fgDark: const Color(0xFFFBBF24), // amber-400
          border: const Color(0xFFF59E0B).withValues(alpha: 0.25),
        );
      case KpiAccent.rose:
        return (
          bg: const Color(0xFFE11D48).withValues(alpha: 0.10),
          fgLight: const Color(0xFFBE123C), // rose-700
          fgDark: const Color(0xFFFB7185), // rose-400
          border: const Color(0xFFE11D48).withValues(alpha: 0.25),
        );
      case KpiAccent.blue:
        return (
          bg: const Color(0xFF3B82F6).withValues(alpha: 0.10),
          fgLight: const Color(0xFF1D4ED8), // blue-700
          fgDark: const Color(0xFF60A5FA), // blue-400
          border: const Color(0xFF3B82F6).withValues(alpha: 0.25),
        );
      case KpiAccent.violet:
        return (
          bg: const Color(0xFF8B5CF6).withValues(alpha: 0.10),
          fgLight: const Color(0xFF6D28D9), // violet-700
          fgDark: const Color(0xFFA78BFA), // violet-400
          border: const Color(0xFF8B5CF6).withValues(alpha: 0.25),
        );
      case KpiAccent.slate:
        return (
          bg: const Color(0xFF64748B).withValues(alpha: 0.10),
          fgLight: const Color(0xFF334155), // slate-700
          fgDark: const Color(0xFF94A3B8), // slate-400
          border: const Color(0xFF64748B).withValues(alpha: 0.25),
        );
      case KpiAccent.primary:
        // primary نأخذه من الـtheme لكن نتعامل مع dark/light يدوياً.
        return (
          bg: const Color(0xFF0EA5E9).withValues(alpha: 0.10),
          fgLight: const Color(0xFF0369A1),
          fgDark: const Color(0xFF38BDF8),
          border: const Color(0xFF0EA5E9).withValues(alpha: 0.25),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final p = _palette();
    final fg = isDark ? p.fgDark : p.fgLight;
    // اللون الكامل للـside bar (مو نسخة الـbg الشفافة).
    final accentBar = switch (accent) {
      KpiAccent.emerald => const Color(0xFF10B981),
      KpiAccent.amber => const Color(0xFFF59E0B),
      KpiAccent.rose => const Color(0xFFE11D48),
      KpiAccent.blue => const Color(0xFF3B82F6),
      KpiAccent.violet => const Color(0xFF8B5CF6),
      KpiAccent.slate => const Color(0xFF64748B),
      KpiAccent.primary => const Color(0xFF0EA5E9),
    };

    final iconSize = hero ? 22.0 : (compact ? 18.0 : 20.0);
    final labelSize = hero ? 12.0 : 11.5;
    final valueSize = hero ? 20.0 : (compact ? 15.0 : 17.0);
    final subSize = 10.5;
    final barWidth = hero ? 5.0 : 4.0;

    // خلفية محايدة (Card surface). اللون يظهر فقط في:
    // الشريط الجانبي + الأيقونة + الـvalue.
    final cardBg = theme.cardTheme.color ?? theme.colorScheme.surface;
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.6);
    final divider = theme.colorScheme.onSurface.withValues(alpha: 0.08);

    final pad = hero
        ? const EdgeInsetsDirectional.fromSTEB(14, 11, 14, 11)
        : const EdgeInsetsDirectional.fromSTEB(12, 10, 10, 10);

    // ارتفاع أدنى للكارت — يخلّي الكارتات الجارة متساوية حتى لو بعضها
    // بدون sub. compact (التفعيلات/التفعيلات اليومية) أصغر، عادي للتقارير
    // المالية اللي عندها ثلاث سطور (label + value + sub).
    final minHeight = hero
        ? 0.0
        : compact
            ? 56.0
            : 70.0;

    return Container(
      constraints: BoxConstraints(minHeight: minHeight),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: divider, width: 1),
        // hero يأخذ shadow خفيف عشان يميّزه عن الكارتات الإحصائية الفوقه.
        boxShadow: hero
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.05),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          // الشريط الجانبي الملوّن — يستعمل PositionedDirectional.start
          // ليتموضع تلقائياً حسب الـtextDirection (RTL → يمين البصري).
          PositionedDirectional(
            start: 0,
            top: 0,
            bottom: 0,
            child: Container(width: barWidth, color: accentBar),
          ),
          Padding(
            padding: pad,
            child: Row(
              children: [
                Icon(icon, size: iconSize, color: fg),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: labelSize,
                          color: muted,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'Cairo',
                          height: 1.1,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: AlignmentDirectional.centerStart,
                        child: Text(
                          value,
                          style: TextStyle(
                            fontSize: valueSize,
                            color: fg,
                            fontWeight: FontWeight.w800,
                            fontFamily: 'Cairo',
                            letterSpacing: -0.2,
                            height: 1.0,
                          ),
                        ),
                      ),
                      if (sub != null && sub!.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Container(height: 1, color: divider),
                        const SizedBox(height: 5),
                        Text(
                          sub!,
                          style: TextStyle(
                            fontSize: subSize,
                            color: muted.withValues(alpha: 0.85),
                            fontFamily: 'Cairo',
                            height: 1.2,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
