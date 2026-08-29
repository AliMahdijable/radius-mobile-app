import 'package:flutter/material.dart';

import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';

/// بلاطة القياس الغاطسة — العنصر الأكثر تكراراً في التطبيق: بلاطات
/// التحميل/الرفع/IP في كارت الاتصال، والإشارة/SNR/CCQ في لوحات الأجهزة،
/// وRX/TX/الفولتيّة/الحرارة لـONT.
///
/// كانت مكرّرة بأربع نسخ خاصّة (`_valueCard` · `_percentCard` ·
/// `_MetricTile` · `_chainMetric`) بواجهة `Color` — وواجهة اللون تسمح
/// بتمرير لون خام فتُعيد المشكلة التي حلّها الترحيل. الواجهة هنا
/// [AppTone] فيستحيل تمرير خام.
class MetricTile extends StatelessWidget {
  const MetricTile({
    super.key,
    required this.label,
    required this.value,
    this.tone = AppTone.neutral,
    this.icon,
    this.onTap,
    this.valueLtr = true,
  });

  final String label;
  final String value;

  /// النغمة الدلاليّة — `fill` للقيمة و`softBg` للخلفيّة حين `emphasis`.
  final AppTone tone;
  final IconData? icon;
  final VoidCallback? onTap;

  /// القيم التقنيّة (dBm · Mbps · IP) تُقرأ يساراً حتى في واجهة عربيّة.
  final bool valueLtr;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final body = Container(
      padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: Sp.sm),
      decoration: BoxDecoration(
        color: AppColors.surfaceSunken,
        borderRadius: BorderRadius.circular(R.icon),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 13, color: AppColors.textLabel),
                const SizedBox(width: Sp.xs),
              ],
              Flexible(
                child: Text(label,
                    style: AppType.micro(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
          const SizedBox(height: Sp.xxs),
          Text(
            value,
            textDirection: valueLtr ? TextDirection.ltr : null,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppType.cardTitle(
              color: tone == AppTone.neutral ? AppColors.textHi : tone.fill,
            ).copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
    if (onTap == null) return body;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(R.icon),
      child: body,
    );
  }
}

/// صفّ بلاطات متساوية العرض — يلفّ [MetricTile] بالتباعد الصحيح.
///
/// ⚠️ `IntrinsicHeight` ضروري لا تجميلي: الصفّ يعيش داخل `ListView`
/// غالباً، و`stretch` وحده يمرّر ارتفاعاً لا نهائيّاً فيسقط تخطيط
/// الـsliver ويختفي كلّ ما بعده. حادثة 2026-08-29.
class MetricTileRow extends StatelessWidget {
  const MetricTileRow({super.key, required this.tiles});
  final List<Widget> tiles;

  @override
  Widget build(BuildContext context) {
    if (tiles.isEmpty) return const SizedBox.shrink();
    final children = <Widget>[];
    for (var i = 0; i < tiles.length; i++) {
      if (i > 0) children.add(const SizedBox(width: Sp.sm));
      children.add(Expanded(child: tiles[i]));
    }
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }
}
