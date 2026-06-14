import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';

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
      label: 'اليوم',
    );
  }

  static DateRange yesterday() {
    final n = DateTime.now().subtract(const Duration(days: 1));
    return DateRange(
      DateTime(n.year, n.month, n.day),
      DateTime(n.year, n.month, n.day, 23, 59, 59),
      label: 'أمس',
    );
  }

  static DateRange thisWeek() {
    final n = DateTime.now();
    final start = n.subtract(Duration(days: n.weekday - 1));
    return DateRange(
      DateTime(start.year, start.month, start.day),
      DateTime(n.year, n.month, n.day, 23, 59, 59),
      label: 'هذا الأسبوع',
    );
  }

  static DateRange thisMonth() {
    final n = DateTime.now();
    return DateRange(
      DateTime(n.year, n.month, 1),
      DateTime(n.year, n.month, n.day, 23, 59, 59),
      label: 'هذا الشهر',
    );
  }

  static DateRange custom(DateTime from, DateTime to) => DateRange(
        DateTime(from.year, from.month, from.day),
        DateTime(to.year, to.month, to.day, 23, 59, 59),
        label: '${_d(from)} → ${_d(to)}',
      );

  static String _d(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  @override
  String toString() => 'DateRange($label)';
}

/// شريط فلتر فترة — chips أفقية + زر تخصيص. مطابق نمط رؤوس
/// التقارير في الـclient-v2.
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
    final presets = <DateRange>[
      DateRange.today(),
      DateRange.yesterday(),
      DateRange.thisWeek(),
      DateRange.thisMonth(),
    ];
    final isCustom = !presets.any((p) => p.label == value.label);
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final p in presets)
          _chip(
            context,
            label: p.label,
            selected: value.label == p.label,
            onTap: () => onChanged(p),
          ),
        _chip(
          context,
          icon: LucideIcons.calendar,
          label: isCustom ? value.label : 'تخصيص',
          selected: isCustom,
          onTap: () => _openCustomPicker(context),
        ),
      ],
    );
  }

  Widget _chip(
    BuildContext ctx, {
    required String label,
    required bool selected,
    required VoidCallback onTap,
    IconData? icon,
  }) {
    final c = selected ? AppColors.brand : AppColors.textMid;
    return Material(
      color: selected ? AppColors.brand.withValues(alpha: 0.12) : AppColors.surface,
      borderRadius: BorderRadius.circular(R.lg),
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        borderRadius: BorderRadius.circular(R.lg),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(R.lg),
            border: Border.all(
              color: selected
                  ? AppColors.brand.withValues(alpha: 0.4)
                  : AppColors.border,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 12, color: c),
                const SizedBox(width: 4),
              ],
              Text(
                label,
                style: TextStyle(
                  color: c,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openCustomPicker(BuildContext context) async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDateRange: DateTimeRange(start: value.from, end: value.to),
      locale: const Locale('ar'),
    );
    if (picked != null) {
      onChanged(DateRange.custom(picked.start, picked.end));
    }
  }
}
