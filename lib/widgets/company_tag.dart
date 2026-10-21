import 'package:flutter/material.dart';

import '../services/merged_mode.dart';
import '../theme/colors.dart';
import '../theme/typography.dart';

/// «كل الشركات»: نقطة الشركة بلونها واسمها — تحت المشترك في القائمة، وفي رأس تفاصيله.
class CompanyTag extends StatelessWidget {
  const CompanyTag({super.key, required this.companyKey, this.fontSize = 11.5});

  final String companyKey;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final c = MergedMode.companyOf(companyKey);
    if (c == null) return const SizedBox.shrink();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: AppColors.company(c.colorIndex), shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            c.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppType.body(color: AppColors.textMid).copyWith(fontSize: fontSize, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}
