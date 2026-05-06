import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// شارة حالة إشعار الواتساب لكل عملية بـactivity_logs.
/// مطابقة لـv2 web (`client-v2/src/pages/reports/_shared.tsx::WaStatusBadge`).
///
/// status:
///   sent     → أخضر · واتساب ✓
///   pending  → أصفر · قيد الإرسال
///   skipped  → كهرماني · لم يُرسل [+ سبب]
///   failed   → أحمر · فشل [+ سبب]
///   null/فارغ → ما تظهر شي
class WaStatusBadge extends StatelessWidget {
  final String? status;
  final String? reason;
  final bool compact;

  const WaStatusBadge({
    super.key,
    this.status,
    this.reason,
    this.compact = false,
  });

  static const Map<String, String> _reasonLabels = {
    'no_admin_id': 'مدير غير متاح',
    'not_connected': 'الواتساب غير متصل',
    'no_template': 'لا يوجد قالب',
    'no_phone': 'لا يوجد رقم هاتف',
    'send_failed': 'فشل الإرسال',
    'notifications_disabled': 'التنبيهات موقوفة',
  };

  String? _resolveReason(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    if (_reasonLabels.containsKey(raw)) return _reasonLabels[raw];
    if (raw.startsWith('feature_off:')) return 'الإشعار معطّل بالإعدادات';
    return raw;
  }

  @override
  Widget build(BuildContext context) {
    final s = status;
    if (s == null || s.isEmpty) return const SizedBox.shrink();

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final reasonText = _resolveReason(reason);
    final fontSize = compact ? 8.5 : 10.5;
    final iconSize = compact ? 10.0 : 12.0;
    final hPad = compact ? 4.0 : 6.0;
    final vPad = compact ? 1.0 : 2.0;

    // ألوان مطابقة لـtailwind tokens المستعمَلة بـv2 web.
    const emerald500 = Color(0xFF10B981);
    const emerald400 = Color(0xFF34D399);
    const emerald700 = Color(0xFF047857);
    const amber400 = Color(0xFFFBBF24);
    const amber700 = Color(0xFFB45309);
    const amber300 = Color(0xFFFCD34D);
    const amber800 = Color(0xFF92400E);
    const red400 = Color(0xFFF87171);
    const red700 = Color(0xFFB91C1C);

    Color bg;
    Color fg;
    Color? borderColor;
    IconData icon;
    String label;

    switch (s) {
      case 'sent':
        bg = emerald500.withValues(alpha: 0.15);
        fg = isDark ? emerald400 : emerald700;
        icon = LucideIcons.messageCircle;
        label = 'واتساب ✓';
        break;
      case 'pending':
        bg = const Color(0xFFF59E0B).withValues(alpha: 0.15);
        fg = isDark ? amber400 : amber700;
        icon = LucideIcons.clock;
        label = 'قيد الإرسال';
        break;
      case 'skipped':
        bg = const Color(0xFFF59E0B).withValues(alpha: 0.10);
        fg = isDark ? amber300 : amber800;
        borderColor = const Color(0xFFF59E0B).withValues(alpha: 0.30);
        icon = LucideIcons.messageCircleOff;
        label = reasonText != null ? 'لم يُرسل · $reasonText' : 'لم يُرسل';
        break;
      default: // 'failed' أو أي شي ثاني
        bg = const Color(0xFFEF4444).withValues(alpha: 0.15);
        fg = isDark ? red400 : red700;
        icon = LucideIcons.messageCircleOff;
        label = reasonText != null ? 'فشل · $reasonText' : 'فشل ✗';
    }

    return Container(
      padding: EdgeInsets.symmetric(horizontal: hPad, vertical: vPad),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
        border: borderColor != null ? Border.all(color: borderColor, width: 1) : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: iconSize, color: fg),
          const SizedBox(width: 3),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: fontSize,
                fontWeight: FontWeight.w800,
                color: fg,
                fontFamily: 'Cairo',
                height: 1.0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
