import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';

/// Checkbox صفّي "طباعة وصل بعد التأكيد" يُوضع فوق زر الحفظ في sheets
/// التفعيل/التجديد/التسديد. الافتراضي **مطفَّأ** — المدير يفعّله لو أراد
/// طباعة، فبعد نجاح العمليّة يُطبَع الوصل تلقائياً.
class PrintReceiptCheckbox extends StatelessWidget {
  const PrintReceiptCheckbox({
    super.key,
    required this.value,
    required this.onChanged,
  });
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: value ? AppColors.brand.withOpacity(0.08) : AppColors.surface,
      borderRadius: BorderRadius.circular(R.sm),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => onChanged(!value),
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: Sp.md, vertical: Sp.sm),
          decoration: BoxDecoration(
            border: Border.all(
              color:
                  value ? AppColors.brand.withOpacity(0.35) : AppColors.border,
              width: value ? 1.2 : 1,
            ),
            borderRadius: BorderRadius.circular(R.sm),
          ),
          child: Row(
            children: [
              Icon(
                LucideIcons.printer,
                size: 16,
                color: value ? AppColors.brand : AppColors.textMid,
              ),
              const SizedBox(width: Sp.sm),
              Expanded(
                child: Text(
                  'sheets.print_receipt_after'.tr(),
                  style: AppType.subtitle(color: AppColors.textHi).copyWith(
                    fontSize: 12.5,
                    fontWeight: value ? FontWeight.w800 : FontWeight.w600,
                  ),
                ),
              ),
              // Checkbox visual (native lookalike + brand accent)
              SizedBox(
                width: 20,
                height: 20,
                child: Checkbox(
                  value: value,
                  onChanged: (v) => onChanged(v ?? false),
                  activeColor: AppColors.brand,
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
