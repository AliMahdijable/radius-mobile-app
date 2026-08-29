import 'dart:ui' as ui;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';

/// Filter chips for the subscribers list — minimalist pill row. The
/// active chip expands to show its label + count on a brand-colored
/// pill; inactive chips collapse to a tiny icon-only circle with the
/// count next to it. This keeps the row visually quiet until the user
/// has picked something, then makes the active choice obvious.
enum SubscriberFilter {
  all,
  active,
  online,
  offline,
  disabled,
  expired,
  debtors,
  nearExpiry,
  onlineNoPlan
}

class FilterChipsBar extends StatefulWidget {
  const FilterChipsBar({
    super.key,
    required this.current,
    required this.counts,
    required this.onSelect,
  });

  final SubscriberFilter current;
  final Map<SubscriberFilter, int> counts;
  final ValueChanged<SubscriberFilter> onSelect;

  @override
  State<FilterChipsBar> createState() => _FilterChipsBarState();
}

class _FilterChipsBarState extends State<FilterChipsBar> {
  final ScrollController _scroll = ScrollController();

  /// 2026-07-15: يحرّك القائمة تلقائياً حتى الـchip النشط يظهر في
  /// النافذة. بدون هذا، لو المستخدم يختار فلتراً بعيداً (مثل onlineNoPlan
  /// من الداشبورد)، الـchip موجود لكن مدفون خارج الشاشة يميناً — يشعر
  /// أن الفلتر ما اشتغل.
  void _scrollToActive() {
    final idx = _defs.indexWhere((d) => d.key == widget.current);
    if (idx < 0 || !_scroll.hasClients) return;
    // تقدير موقع الـchip: عرض تقريبي 90px + spacing 6px.
    const chipStride = 112.0;
    final target =
        (idx * chipStride) - 40; // 40px offset ليضل جزء من السابق مرئي
    final max = _scroll.position.maxScrollExtent;
    final clamped = target.clamp(0.0, max);
    _scroll.animateTo(
      clamped,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToActive());
  }

  @override
  void didUpdateWidget(covariant FilterChipsBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.current != widget.current) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToActive());
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// الـlabel هنا مفتاح ترجمة — الـ_Chip يستدعي .tr() عند البناء.
  /// 2026-07-15: onlineNoPlan نُقل من آخر القائمة إلى موضع بين expired
  /// و debtors. في RTL كان يختفي لليمين خارج الشاشة، فالمستخدم يشوف
  /// الفلتر مطبَّق على البطاقات لكن الـchip المُظلَّل غير مرئي. مطابق
  /// لموضعه في الويب — علاقة دلاليّة مع "منتهي".
  static final _defs = <_ChipDef>[
    _ChipDef(SubscriberFilter.all, 'subscribers.filter_all', LucideIcons.users,
        AppColors.brand),
    _ChipDef(SubscriberFilter.active, 'subscribers.filter_active',
        LucideIcons.circleCheck, Color(0xFF14B8A6)),
    _ChipDef(SubscriberFilter.online, 'subscribers.filter_online',
        LucideIcons.wifi, Color(0xFF3B82F6)),
    _ChipDef(SubscriberFilter.offline, 'subscribers.filter_offline',
        LucideIcons.wifiOff, Color(0xFF90A4AE)),
    _ChipDef(SubscriberFilter.disabled, 'subscribers.filter_disabled',
        LucideIcons.ban, Color(0xFF6D4C41)),
    _ChipDef(SubscriberFilter.expired, 'subscribers.filter_expired',
        LucideIcons.timerOff, Color(0xFFC62828)),
    // "بدون نت" — متصل + منتهي. لون بنفسجي يطابق status_online_expired
    // في الويب حتى الإدمن يربط الـchip بالحالة اللونية للصف.
    _ChipDef(SubscriberFilter.onlineNoPlan, 'subscribers.filter_online_no_plan',
        LucideIcons.wifiOff, Color(0xFF9333EA)),
    _ChipDef(SubscriberFilter.debtors, 'subscribers.filter_debtors',
        LucideIcons.creditCard, Color(0xFFF57F17)),
    _ChipDef(SubscriberFilter.nearExpiry, 'subscribers.filter_near_expiry',
        LucideIcons.triangleAlert, Color(0xFFE08F2D)),
  ];

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return SizedBox(
      height: H.chipSm,
      child: ListView.separated(
        controller: _scroll,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: Sp.lg),
        itemCount: _defs.length,
        separatorBuilder: (_, __) => const SizedBox(width: Sp.sm),
        itemBuilder: (_, i) {
          final d = _defs[i];
          final selected = widget.current == d.key;
          final count = widget.counts[d.key] ?? 0;
          return _Chip(
            label: d.label.tr(),
            icon: d.icon,
            color: d.color,
            count: count,
            selected: selected,
            onTap: () => widget.onSelect(d.key),
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

  /// لون دلالي للعدّاد حين تكون الشريحة خاملة (أخضر للمتصل، أحمر
  /// للمنتهي…) — تماماً كما في المخطّط.
  final Color color;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Material(
      color: selected ? AppColors.brand : AppColors.surface,
      borderRadius: BorderRadius.circular(R.md),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(R.md),
        child: Container(
          height: H.chipSm,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(R.md),
            border: Border.all(
              color: selected ? AppColors.brand : AppColors.borderSoft,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 14,
                color: selected ? AppColors.onBrand : AppColors.textHint,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: AppType.body(
                  color: selected ? AppColors.onBrand : AppColors.textBody,
                ).copyWith(
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '$count',
                textDirection: ui.TextDirection.ltr,
                style: AppType.body(
                  color: selected
                      ? AppColors.onBrand.withValues(alpha: 0.65)
                      : color,
                ).copyWith(fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
