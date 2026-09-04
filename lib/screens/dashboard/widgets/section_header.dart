import 'package:flutter/material.dart';

import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';

class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.label,
    this.trailingLabel,
    this.onTrailingTap,
  });

  final String label;
  final String? trailingLabel;
  final VoidCallback? onTrailingTap;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Padding(
      padding: const EdgeInsets.only(bottom: Sp.md, top: Sp.lg),
      child: Row(
        children: [
          // ⚠️ `Expanded` لا `Text` عارياً، و`Spacer` حُذف معه.
          //
          // 🐛 كان العنوان بلا مرونة **وبلا `maxLines`** — فالصفّ بلا
          // مطاطيّة إطلاقاً. و`Spacer` لا يخنقه هنا (يأخذ ما فضل فقط)،
          // لكنّ العنوان يأخذ مقاسه كاملاً فيفيض على الشاشات الضيّقة
          // وعند تكبير الخطّ (`main.dart` يسمح حتّى ١٫٢).
          //
          // و`Expanded` يؤدّي دور `Spacer` أيضاً: يملأ ما بين العنوان
          // والزرّ، فلا حاجة إلى الاثنين.
          Expanded(
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppType.title(color: AppColors.textHi)
                    .copyWith(fontSize: 14, fontWeight: FontWeight.w700)),
          ),
          if (trailingLabel != null)
            TextButton(
              onPressed: onTrailingTap,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: Sp.sm,
                  vertical: Sp.xs,
                ),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                trailingLabel!,
                style: AppType.link(color: AppColors.brand)
                    .copyWith(fontSize: 12.5, fontWeight: FontWeight.w600),
              ),
            ),
        ],
      ),
    );
  }
}
