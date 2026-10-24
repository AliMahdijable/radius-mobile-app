import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../models/dashboard.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';
import '../../subscribers/widgets/filter_chips_bar.dart';
import '../../desktop/desk_widgets.dart';

/// «توزيع المشتركين» على رئيسيّة الحاسبة: حصّة كلّ حالةٍ من الإجمالي أشرطةً أفقيّة **بلون حالتها** (المالك ٢٤
/// أكتوبر: الكارتات بلا ألوان «كأنها كتابة نصّيّة جامدة») — وكلّ صفٍّ يحمل أيقونة حالته في مربّعٍ بلونها
/// وتسميتها والعدد والنسبة، فالحالة لا تُقرأ من اللون وحده. والصفّ يفتح المشتركين بفلتره.
class DeskStatusBars extends StatelessWidget {
  const DeskStatusBars({super.key, required this.stats, this.onOpen});

  final SubscribersStats stats;
  final ValueChanged<SubscriberFilter?>? onOpen;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final s = stats;
    final total = s.total;
    final rows = <(IconData, Color, String, int, SubscriberFilter)>[
      (LucideIcons.wifi, AppColors.info, 'subscribers.filter_online'.tr(), s.online, SubscriberFilter.online),
      (LucideIcons.wifiOff, AppColors.warning, 'subscribers.filter_offline'.tr(), s.offline, SubscriberFilter.offline),
      (LucideIcons.timerOff, AppColors.error, 'subscribers.filter_expired'.tr(), s.expired, SubscriberFilter.expired),
      (LucideIcons.ban, AppColors.textLabel, 'subscribers.filter_disabled'.tr(), s.disabled, SubscriberFilter.disabled),
      if (s.onlineNoPlan > 0)
        (LucideIcons.triangleAlert, AppColors.anomaly, 'subscribers.filter_online_no_plan'.tr(), s.onlineNoPlan,
            SubscriberFilter.onlineNoPlan),
    ];
    return Container(
      padding: const EdgeInsets.all(Sp.xl),
      decoration: DeskCard.decoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('desktop.distribution'.tr(),
              style: AppType.label(color: AppColors.textHi).copyWith(fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text('desktop.distribution_hint'.tr(args: ['$total']),
              style: AppType.muted(color: AppColors.textMid).copyWith(fontSize: 13)),
          const SizedBox(height: Sp.lg),
          for (final (icon, tone, label, n, filter) in rows)
            _Row(
              icon: icon,
              tone: tone,
              label: label,
              count: n,
              share: total == 0 ? 0 : n / total,
              onTap: onOpen == null ? null : () => onOpen!(filter),
            ),
        ],
      ),
    );
  }
}

class _Row extends StatefulWidget {
  const _Row({
    required this.icon,
    required this.tone,
    required this.label,
    required this.count,
    required this.share,
    required this.onTap,
  });

  final IconData icon;
  final Color tone;
  final String label;
  final int count;
  final double share;
  final VoidCallback? onTap;

  @override
  State<_Row> createState() => _RowState();
}

class _RowState extends State<_Row> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final pct = (widget.share * 100).round();
    return MouseRegion(
      cursor: widget.onTap == null ? MouseCursor.defer : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: Sp.sm, vertical: Sp.sm),
          decoration: BoxDecoration(
            color: _hover ? AppColors.surfaceSunken : null,
            borderRadius: BorderRadius.circular(R.sm),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: widget.tone.withValues(alpha: 0.13),
                      borderRadius: BorderRadius.circular(R.sm),
                    ),
                    child: Icon(widget.icon, size: 16, color: widget.tone),
                  ),
                  const SizedBox(width: Sp.sm + 2),
                  Expanded(
                    child: Text(widget.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppType.body(color: AppColors.textHi).copyWith(fontSize: 14, fontWeight: FontWeight.w600)),
                  ),
                  Text('${widget.count}',
                      style: AppType.label(color: AppColors.textHi).copyWith(fontSize: 14, fontWeight: FontWeight.w700)),
                  const SizedBox(width: Sp.sm),
                  SizedBox(
                    width: 40,
                    child: Text('$pct%',
                        textAlign: TextAlign.end,
                        style: AppType.muted(color: AppColors.textMid).copyWith(fontSize: 12.5)),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              SizedBox(
                height: 6,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: widget.tone.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(R.pill),
                        ),
                      ),
                    ),
                    if (widget.share > 0)
                      Positioned.fill(
                        child: FractionallySizedBox(
                          alignment: AlignmentDirectional.centerStart,
                          widthFactor: widget.share.clamp(0.02, 1.0),
                          heightFactor: 1,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: widget.tone,
                              borderRadius: BorderRadius.circular(R.pill),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
