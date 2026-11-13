import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../services/section_fold.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';

/// قسمٌ ينطوي في صفحة المشترك ([SectionFold]): مطويّاً = شريطٌ صغير بعنوانه وسهم (كرته لا يُبنى ⇒ لا فحص ولا نبض)،
/// ومفتوحاً = الكرت نفسه ويأخذ [builder] دالّة الطيّ ليضعها على عنوانه.
class FoldableSection extends StatelessWidget {
  const FoldableSection({super.key, required this.id, required this.title, required this.icon, required this.builder});

  final String id;
  final String title;
  final IconData icon;
  final Widget Function(VoidCallback fold) builder;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: SectionFold.of(id),
      builder: (context, folded, _) {
        Theme.of(context); // theme-dep (dark-mode)
        if (!folded) return builder(() => SectionFold.set(id, true));
        return Padding(
          padding: const EdgeInsets.only(bottom: Sp.sm),
          child: GestureDetector(
            key: ValueKey('fold-open-$id'),
            behavior: HitTestBehavior.opaque,
            onTap: () => SectionFold.set(id, false),
            child: Container(
              constraints: const BoxConstraints(minHeight: H.segment),
              padding: const EdgeInsets.symmetric(horizontal: Sp.lg, vertical: Sp.md),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(R.card),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  Icon(icon, size: 18, color: AppColors.brandAccent),
                  const SizedBox(width: Sp.sm),
                  Expanded(
                    child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.cardTitle()),
                  ),
                  Icon(LucideIcons.chevronDown, size: 18, color: AppColors.textMid),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// عنوان كرتٍ ينطوي: النقر عليه يطوي، وبجانبه سهمٌ صغير. بلا [onFold] = العنوان كما كان.
class FoldTitle extends StatelessWidget {
  const FoldTitle({super.key, required this.icon, required this.title, this.onFold});

  final IconData icon;
  final String title;
  final VoidCallback? onFold;

  @override
  Widget build(BuildContext context) {
    final row = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: AppColors.brandAccent),
        const SizedBox(width: Sp.sm),
        Flexible(
          child: Text(title, style: AppType.cardTitle(), maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
        if (onFold != null) ...[
          const SizedBox(width: Sp.xxs),
          Icon(LucideIcons.chevronUp, size: 16, color: AppColors.textMid),
        ],
      ],
    );
    if (onFold == null) return row;
    return GestureDetector(key: const ValueKey('fold-close'), behavior: HitTestBehavior.opaque, onTap: onFold, child: row);
  }
}
