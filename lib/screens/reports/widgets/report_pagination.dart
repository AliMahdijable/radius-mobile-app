import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';

/// نمط pagination موحّد للتقارير — مطابق نمط شاشة المشتركين.
///
/// يتضمّن ثلاث عناصر جنباً إلى جنب:
///  * `ReportStatsBar` — عدّاد "X-Y / N" + منتقي حجم الصفحة (chevronDown)
///  * `ReportPager` — أسهم يمين/يسار + "صفحة X من Y"
///
/// استخدام مبسّط: افّ فيه المتغيّرات `_page`، `_pageSize` في الـState،
/// وأدخِل الـ list الكاملة (filtered) والـ page slice المحسوب.
///
/// الاختيارات المدعومة: 10 / 25 / 50 / 100 / 250 / 500 (مطابق subscribers).
const List<int> kReportPageSizeOptions = [10, 25, 50, 100, 250, 500];

class ReportStatsBar extends StatelessWidget {
  const ReportStatsBar({
    super.key,
    required this.totalItems,
    required this.pageStart,
    required this.pageEnd,
    required this.pageSize,
    required this.onPageSizeChange,
  });

  final int totalItems;
  final int pageStart; // 0-based, inclusive (نعرضه +1)
  final int pageEnd; // 0-based, exclusive
  final int pageSize;
  final ValueChanged<int> onPageSizeChange;

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 4),
      child: Row(
        children: [
          Text(
            '${totalItems == 0 ? 0 : pageStart + 1}-$pageEnd / $totalItems',
            style: AppType.muted(color: AppColors.textLow)
                .copyWith(fontSize: 11, fontWeight: FontWeight.w500),
          ),
          const Spacer(),
          _PageSizePicker(
            current: pageSize,
            options: kReportPageSizeOptions,
            onChange: onPageSizeChange,
          ),
        ],
      ),
    );
  }
}

class ReportPager extends StatelessWidget {
  const ReportPager({
    super.key,
    required this.page,
    required this.totalPages,
    required this.onPrev,
    required this.onNext,
  });

  final int page; // 0-based
  final int totalPages;
  final VoidCallback onPrev;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Sp.sm),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _ArrowBtn(
            icon: LucideIcons.chevronRight,
            enabled: page > 0,
            onTap: onPrev,
          ),
          const SizedBox(width: Sp.md),
          Text(
            'subscribers.page_of'
                .tr(namedArgs: {'page': '${page + 1}', 'total': '$totalPages'}),
            style: AppType.label(color: AppColors.textHi).copyWith(
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: Sp.md),
          _ArrowBtn(
            icon: LucideIcons.chevronLeft,
            enabled: page < totalPages - 1,
            onTap: onNext,
          ),
        ],
      ),
    );
  }
}

class _PageSizePicker extends StatelessWidget {
  const _PageSizePicker({
    required this.current,
    required this.options,
    required this.onChange,
  });
  final int current;
  final List<int> options;
  final ValueChanged<int> onChange;

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return PopupMenuButton<int>(
      tooltip: 'subscribers.page_size'.tr(),
      onSelected: onChange,
      itemBuilder: (_) => [
        for (final o in options)
          PopupMenuItem(value: o, child: Text('$o / صفحة')),
      ],
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$current/صفحة',
              style: AppType.muted(color: AppColors.textLow)
                  .copyWith(fontSize: 11, fontWeight: FontWeight.w600)),
          const SizedBox(width: 2),
          Icon(LucideIcons.chevronDown, size: 11, color: AppColors.textLow),
        ],
      ),
    );
  }
}

class _ArrowBtn extends StatelessWidget {
  const _ArrowBtn({
    required this.icon,
    required this.enabled,
    required this.onTap,
  });
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final color = enabled ? AppColors.brand : AppColors.textLow;
    return InkResponse(
      onTap: enabled ? onTap : null,
      radius: 22,
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: enabled ? AppColors.brandSoftBg : AppColors.surface,
          borderRadius: BorderRadius.circular(R.sm),
          border: Border.all(
            color: enabled ? AppColors.brandSoftBorder : AppColors.border,
          ),
        ),
        alignment: Alignment.center,
        child: Icon(icon, size: 18, color: color),
      ),
    );
  }
}
