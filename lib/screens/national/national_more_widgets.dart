import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import '../../core/util/bytes_format.dart';

/// أدوات الأقسام الباقية من بوّابة الوطنيّ (١ نوفمبر): القفل الهادئ بسببه (لا «تعذّر» أحمر)، والمدّة والبايتات بكلام التطبيق.

/// القسم مقفلٌ بسببه — مستخدم البوّابة لا يملكه، أو غير مفعّلٍ للحساب بعد: قفلٌ هادئ ونصّ الخادم، بلا «إعادة المحاولة».
class NationalLockedBox extends StatelessWidget {
  const NationalLockedBox({super.key, required this.text, this.title = 'لا صلاحيّة في البوّابة'});
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: Sp.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(color: AppColors.surfaceSunken, borderRadius: BorderRadius.circular(R.icon)),
            child: Icon(LucideIcons.lock, size: 24, color: AppColors.textLow),
          ),
          const SizedBox(height: Sp.md),
          Text(title, textAlign: TextAlign.center, style: AppType.label(color: AppColors.textHi)),
          const SizedBox(height: Sp.xs),
          Text(text, textAlign: TextAlign.center, style: AppType.body(color: AppColors.textMid)),
        ],
      ),
    );
  }
}

/// «11 يوم 6س 28د» — كبطاقة المشترك؛ null ⇒ «—».
String nationalDuration(int? seconds) {
  if (seconds == null || seconds < 0) return '—';
  final d = seconds ~/ 86400;
  final h = (seconds % 86400) ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  if (d > 0) return '$d يوم $hس $mد';
  if (h > 0) return '$hس $mد';
  return '$mد';
}

String _group(String n) {
  final neg = n.startsWith('-');
  final s = neg ? n.substring(1) : n;
  final dot = s.indexOf('.');
  final whole = dot < 0 ? s : s.substring(0, dot);
  final frac = dot < 0 ? '' : s.substring(dot);
  final b = StringBuffer();
  for (var i = 0; i < whole.length; i++) {
    if (i > 0 && (whole.length - i) % 3 == 0) b.write(',');
    b.write(whole[i]);
  }
  return '${neg ? '-' : ''}$b$frac';
}

/// بايتات بوحدتها (لاتينيّة كباقي التطبيق) — null ⇒ «—»؛ الصفر «0».
String nationalBytes(num? b) {
  if (b == null) return '—';
  if (b <= 0) return '0';
  // الوحدة من الدالّة الموحّدة (حتى TB وPB)، والشكل كما كان
  final s = scaleBytes(b);
  if (s.index >= 3) return '${_group(s.value.toStringAsFixed(s.value >= 10 ? 0 : 1))} ${s.unit}';
  return '${_group(s.value.toStringAsFixed(0))} ${s.unit}';
}

/// عددٌ بفواصل، و«—» للمجهول (لا صفرٌ كاذب).
String nationalCount(int? n) => n == null ? '—' : _group('$n');

/// سطرٌ صغير: أيقونةٌ ونصّ (للبطاقات).
Widget nationalMeta(IconData i, String text, {bool ltr = false}) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(i, size: 13, color: AppColors.textMid),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textDirection: ltr ? TextDirection.ltr : null,
            style: AppType.micro(color: AppColors.textMid),
          ),
        ),
      ],
    );

/// إطار البطاقة الموحَّد لأقسام الوطنيّ.
class NationalCard extends StatelessWidget {
  const NationalCard({super.key, required this.child, this.onTap, this.highlight = false});
  final Widget child;
  final VoidCallback? onTap;

  /// إطارٌ بلون العلامة (غير مقروء…).
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep
    final box = Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(R.lg),
        border: Border.all(color: highlight ? AppColors.brandSoftBorder : AppColors.border),
      ),
      child: child,
    );
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(R.lg),
      child: onTap == null ? box : InkWell(onTap: onTap, borderRadius: BorderRadius.circular(R.lg), child: box),
    );
  }
}
