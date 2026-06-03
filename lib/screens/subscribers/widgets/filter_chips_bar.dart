import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';

/// Filter chips for the subscribers list. 8 chips, each shows its count
/// in a smaller text below the label. Horizontally scrollable so all
/// chips fit on narrow phones.
enum SubscriberFilter { all, active, online, offline, disabled, expired, debtors, nearExpiry }

class FilterChipsBar extends StatelessWidget {
  const FilterChipsBar({
    super.key,
    required this.current,
    required this.counts,
    required this.onSelect,
  });

  final SubscriberFilter current;
  final Map<SubscriberFilter, int> counts;
  final ValueChanged<SubscriberFilter> onSelect;

  static const _defs = <_ChipDef>[
    _ChipDef(SubscriberFilter.all, 'الكل', LucideIcons.users, AppColors.brand),
    _ChipDef(SubscriberFilter.active, 'نشط', LucideIcons.circleCheck, Color(0xFF14B8A6)),
    _ChipDef(SubscriberFilter.online, 'متصل', LucideIcons.wifi, Color(0xFF3B82F6)),
    _ChipDef(SubscriberFilter.offline, 'غير متصل', LucideIcons.wifiOff, Color(0xFF90A4AE)),
    _ChipDef(SubscriberFilter.disabled, 'معطّل', LucideIcons.ban, Color(0xFF6D4C41)),
    _ChipDef(SubscriberFilter.expired, 'منتهي', LucideIcons.timerOff, Color(0xFFC62828)),
    _ChipDef(SubscriberFilter.debtors, 'مدين', LucideIcons.creditCard, Color(0xFFF57F17)),
    _ChipDef(SubscriberFilter.nearExpiry, 'قارب', LucideIcons.triangleAlert, Color(0xFFE08F2D)),
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 64,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: Sp.lg),
        itemCount: _defs.length,
        separatorBuilder: (_, __) => const SizedBox(width: Sp.sm),
        itemBuilder: (_, i) {
          final d = _defs[i];
          final selected = current == d.key;
          final count = counts[d.key] ?? 0;
          return _Chip(
            label: d.label,
            icon: d.icon,
            color: d.color,
            count: count,
            selected: selected,
            onTap: () => onSelect(d.key),
          );
        },
      ),
    );
  }
}

class _ChipDef {
  const _ChipDef(this.key, this.label, this.icon, this.color);
  final SubscriberFilter key;
  final String label;
  final IconData icon;
  final Color color;
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.icon,
    required this.color,
    required this.count,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final Color color;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bg = selected ? color : color.withValues(alpha: 0.08);
    final fg = selected ? Colors.white : color;
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(R.pill),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(R.pill),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(R.pill),
            border: Border.all(
              color: selected
                  ? color
                  : color.withValues(alpha: 0.25),
              width: 1,
            ),
          ),
          child: Row(
            children: [
              Icon(icon, color: fg, size: 14),
              const SizedBox(width: 6),
              Text(
                label,
                style: AppType.label(color: fg).copyWith(
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: selected
                      ? Colors.white.withValues(alpha: 0.22)
                      : color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(R.pill),
                ),
                child: Text(
                  '$count',
                  style: AppType.muted(color: fg).copyWith(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
