import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';

/// عرض تدريجي موحّد للتقارير — بديل ترقيم الصفحات.
///
/// الترقيم كان يفترض أنّ المستخدم يتنقّل في فهرس ثابت، والتقرير ليس
/// كذلك: مداه الزمني وفلاتره تتغيّر، فيتبدّل ترتيب كلّ شيء و«الصفحة
/// الرابعة» تصير سطراً مختلفاً. ومنتقي حجم الصفحة كان يفرض قراراً
/// لا يملك المستخدم أساساً لاتّخاذه قبل أن يرى النتائج.
///
/// البديل: عدّاد ظاهر يكبر `kReportPageStep` عند كل ضغطة.
const int kReportPageStep = 25;

/// سطر العدّ فوق النتائج — «عرض 25 من 412».
class ReportStatsBar extends StatelessWidget {
  const ReportStatsBar({
    super.key,
    required this.totalItems,
    required this.shown,
  });

  final int totalItems;
  final int shown;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 4),
      child: Text(
        totalItems == 0
            ? '—'
            : shown >= totalItems
                ? '$totalItems نتيجة'
                : 'عرض $shown من $totalItems',
        style: AppType.muted(color: AppColors.textLow),
      ),
    );
  }
}

/// زرّ «تحميل المزيد» في ذيل نتائج التقرير.
///
/// لا يُبنى إطلاقاً حين لا يبقى شيء — فلا يحجز ارتفاعاً في الحالة
/// الشائعة (تقرير أقصر من خطوة واحدة).
class ReportLoadMore extends StatelessWidget {
  const ReportLoadMore({
    super.key,
    required this.remaining,
    required this.onTap,
  });

  final int remaining;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, Sp.md, 0, Sp.sm),
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.card),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(R.card),
          child: Container(
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(R.card),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(LucideIcons.chevronDown,
                    size: 15, color: AppColors.brandAccent),
                const SizedBox(width: 7),
                Text('تحميل المزيد',
                    style: AppType.button(color: AppColors.brandAccent)),
                const SizedBox(width: 6),
                Text('($remaining)',
                    style: AppType.muted(color: AppColors.textLow)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
