import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/util/ar_date.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';
import '../../../core/widgets/app_date_picker.dart';

/// نطاق تاريخ موحَّد لكل تقارير الموبايل. الـto حصراً نهاية اليوم
/// (23:59:59) — يطابق سلوك v1 web reports.
class DateRange {
  const DateRange(this.from, this.to, {required this.label});
  final DateTime from;
  final DateTime to;
  final String label;

  static DateRange today() {
    final n = DateTime.now();
    return DateRange(
      DateTime(n.year, n.month, n.day),
      DateTime(n.year, n.month, n.day, 23, 59, 59),
      label: 'reports.today'.tr(),
    );
  }

  static DateRange yesterday() {
    final n = DateTime.now().subtract(const Duration(days: 1));
    return DateRange(
      DateTime(n.year, n.month, n.day),
      DateTime(n.year, n.month, n.day, 23, 59, 59),
      label: 'reports.yesterday'.tr(),
    );
  }

  static DateRange thisWeek() {
    final n = DateTime.now();
    final start = n.subtract(Duration(days: n.weekday - 1));
    return DateRange(
      DateTime(start.year, start.month, start.day),
      DateTime(n.year, n.month, n.day, 23, 59, 59),
      label: 'reports.this_week'.tr(),
    );
  }

  static DateRange thisMonth() {
    final n = DateTime.now();
    return DateRange(
      DateTime(n.year, n.month, 1),
      DateTime(n.year, n.month, n.day, 23, 59, 59),
      label: 'reports.this_month'.tr(),
    );
  }

  /// الشهر الماضي كاملاً (أوّله إلى آخر يومٍ فيه).
  static DateRange lastMonth() {
    final n = DateTime.now();
    final start = DateTime(n.year, n.month - 1, 1);
    final end = DateTime(n.year, n.month, 0); // اليوم 0 = آخر يومٍ في الشهر الذي قبله
    return DateRange(
      start,
      DateTime(end.year, end.month, end.day, 23, 59, 59),
      label: 'reports.last_month'.tr(),
    );
  }

  /// آخر 3 شهور — تبدأ من أول اليوم قبل 90 يوم وتنتهي عند اليوم الحالي.
  static DateRange last3Months() {
    final n = DateTime.now();
    final start = n.subtract(const Duration(days: 90));
    return DateRange(
      DateTime(start.year, start.month, start.day),
      DateTime(n.year, n.month, n.day, 23, 59, 59),
      label: 'reports.last_3_months'.tr(),
    );
  }

  static DateRange custom(DateTime from, DateTime to) => DateRange(
        DateTime(from.year, from.month, from.day),
        DateTime(to.year, to.month, to.day, 23, 59, 59),
        label: rangeText(from, to),
      );

  /// «من 1 تشرين الأوّل إلى 24 تشرين الأوّل»، ويومٌ واحد بتاريخه وحده — بأسماء الأشهر لا «2026-10-01»
  /// (المالك ٢٤ أكتوبر: «الاشهر تكتب رقم انكليزي»).
  static String rangeText(DateTime from, DateTime to) {
    final a = iqDateOf(from), b = iqDateOf(to);
    return a == b ? a : 'reports.range_text'.tr(namedArgs: {'from': a, 'to': b});
  }

  bool get isCustom => !presets().any((p) => p.label == label);

  /// الفترات الجاهزة بترتيبها في الشريط.
  static List<DateRange> presets() => [
        DateRange.today(),
        DateRange.yesterday(),
        DateRange.thisWeek(),
        DateRange.thisMonth(),
        DateRange.lastMonth(),
        DateRange.last3Months(),
      ];

  @override
  String toString() => 'DateRange($label)';
}

/// شريط فلتر الفترة لكلّ التقارير والمبيعات والصرفيات: الفترات الجاهزة سطراً، وتحتها حقل الفترة نفسها
/// بأسماء الأشهر («من 1 تشرين الأوّل إلى 24 تشرين الأوّل») — يُلمس فيفتح المنتقي. مطابق شريط الويب
/// (`pages/reports/_shared.tsx` DateRangeFields): نفس الفترات والارتفاع والشكل في كلّ نافذة (المالك ٢٤ أكتوبر).
class DateRangeChipBar extends StatelessWidget {
  const DateRangeChipBar({
    super.key,
    required this.value,
    required this.onChanged,
  });
  final DateRange value;
  final ValueChanged<DateRange> onChanged;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep
    final custom = value.isCustom;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final p in DateRange.presets())
              _chip(
                label: p.label,
                selected: value.label == p.label,
                onTap: () => onChanged(p),
              ),
          ],
        ),
        const SizedBox(height: Sp.sm),
        _field(context, custom: custom),
      ],
    );
  }

  /// الفترة المختارة نفسها — بارتفاع حقول الإدخال (40)، وحدّها بلون العلامة حين تكون مخصّصة.
  Widget _field(BuildContext context, {required bool custom}) {
    final text = DateRange.rangeText(value.from, value.to);
    return Material(
      color: custom ? AppColors.brandSoftBg : AppColors.surfaceInput,
      borderRadius: BorderRadius.circular(R.sm),
      child: InkWell(
        onTap: () => _openCustomPicker(context),
        borderRadius: BorderRadius.circular(R.sm),
        child: Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(R.sm),
            border: Border.all(
              color: custom ? AppColors.brandSoftBorder : AppColors.border,
            ),
          ),
          child: Row(
            children: [
              Icon(LucideIcons.calendarDays, size: 15, color: AppColors.brand),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  text,
                  style: AppType.bodyBold(color: AppColors.textHi),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 6),
              Text('reports.range_pick'.tr(), style: AppType.labelBold(color: AppColors.brand)),
              const SizedBox(width: 2),
              Icon(LucideIcons.chevronDown, size: 13, color: AppColors.brand),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final c = selected ? AppColors.onBrand : AppColors.textMid;
    return Material(
      color: selected ? AppColors.brand : AppColors.surface,
      borderRadius: BorderRadius.circular(R.pill),
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        borderRadius: BorderRadius.circular(R.pill),
        // ⚠️ بلا `alignment` على الحاوية: تتمدّد بها لكامل العرض فتصير كلّ شريحةٍ سطراً. الصفّ الأدنى
        // يتوسّط عموديّاً داخل الارتفاع الثابت ويبقى بعرض نصّه.
        child: Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(R.pill),
            border: Border.all(
              color: selected ? AppColors.brand : AppColors.border,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: AppType.labelBold(color: c),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openCustomPicker(BuildContext context) async {
    // نافذةٌ بالوسط على الحاسبة، وأسماء الأشهر العراقيّة وألوان التطبيق (showAppDateRangePicker).
    final picked = await showAppDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDateRange: DateTimeRange(start: value.from, end: value.to),
    );
    if (picked != null) {
      onChanged(DateRange.custom(picked.start, picked.end));
    }
  }
}
