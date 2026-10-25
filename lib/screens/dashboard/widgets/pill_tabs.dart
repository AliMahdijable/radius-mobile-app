import 'package:flutter/material.dart';

import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';

/// شريط فتراتٍ بحبوب — شكل «يومي · أسبوعي · شهري» في بطاقة الإيرادات، مشتركٌ مع بطاقة توزيع الباقات
/// (المالك ٢٥ أكتوبر: «التصميم مال فترات خلي مثل تصميم الايرادات»): مسارٌ واحدٌ مدوّر، والمختارة حبّةٌ بلون العلامة.
class PillTabs<T> extends StatelessWidget {
  const PillTabs({super.key, required this.options, required this.current, required this.onSelect});

  final List<(T, String)> options;
  final T current;
  final ValueChanged<T> onSelect;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: AppColors.surfaceInput,
        borderRadius: BorderRadius.circular(R.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [for (final (value, label) in options) _tab(value, label)],
      ),
    );
  }

  Widget _tab(T value, String label) {
    final selected = current == value;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onSelect(value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? AppColors.brand : Colors.transparent,
          borderRadius: BorderRadius.circular(R.pill),
        ),
        child: Text(
          label,
          style: AppType.muted(
            color: selected ? AppColors.onBrand : AppColors.textMid,
          ).copyWith(
            fontSize: 11,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
