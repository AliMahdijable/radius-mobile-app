import 'dart:math' as math;

import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';

import '../../../core/util/ar_date.dart';
import '../../../core/widgets/desk_pressable.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';
import '../../subscribers/widgets/filter_chips_bar.dart';

/// «التجديدات القادمة» — العنصر الذي لا يملكه إلّا وكيل الإنترنت: من ينتهي اشتراكه في كلّ يومٍ من الأيّام الـ١٤
/// القادمة، عموداً لكلّ يوم (اليوم أوّلاً). الأيّام الثلاثة الأولى بأخضر التطبيق (تحتاج تجديداً الآن) والباقي
/// بدرجته الفاتحة — اللون على البيانات لا على الإطار. النقر على يومٍ عاجل يفتح «قربوا الانتهاء».
///
/// [days] = ١٤ عدداً من الحلقة نفسها على قائمة المشتركين (`DebtorsResult.expiringByDay`)؛ `null` حين لا قائمة
/// (الحسابات الكبيرة، «كل الشركات») — فيُعرض عدد «قربوا الانتهاء» وحده بلا تفصيلٍ يوميٍّ مخترَع.
class DeskRenewalsRunway extends StatelessWidget {
  const DeskRenewalsRunway({
    super.key,
    required this.days,
    required this.nearExpiry,
    this.onOpen,
    this.today,
  });

  final List<int>? days;
  final int? nearExpiry;
  final ValueChanged<SubscriberFilter?>? onOpen;

  /// للاختبار — اليوم الذي تبدأ منه الخانات.
  final DateTime? today;

  /// الأيّام التي تُعدّ عاجلة (كفلتر «قربوا الانتهاء»: ٣ أيّام).
  static const urgentDays = 4;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final d = days;
    // العدد في الجملة عدد فلتر «قربوا الانتهاء» نفسه (بالساعات) — ما يفتحه الزرّ؛ والأعمدة صورةٌ بالتقويم.
    final soon = nearExpiry ?? d?.take(urgentDays).fold<int>(0, (a, b) => a + b);
    final all = d?.fold<int>(0, (a, b) => a + b);
    return Container(
      padding: const EdgeInsets.fromLTRB(Sp.xl, Sp.lg, Sp.xl, Sp.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.card),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'desktop.runway_title'.tr(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.label(color: AppColors.textHi).copyWith(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
              if (onOpen != null)
                TextButton(
                  onPressed: () => onOpen!(SubscriberFilter.nearExpiry),
                  style: TextButton.styleFrom(foregroundColor: AppColors.brand),
                  child: Text('desktop.runway_open'.tr(), style: AppType.bodyBold(color: AppColors.brand)),
                ),
            ],
          ),
          Text(
            d == null
                ? 'desktop.runway_sub_soon'.tr(args: ['${soon ?? '—'}'])
                : (all == 0
                    ? 'desktop.runway_empty'.tr()
                    : 'desktop.runway_sub'.tr(args: ['$soon', '$all'])),
            style: AppType.muted(color: AppColors.textMid).copyWith(fontSize: 13),
          ),
          const SizedBox(height: Sp.lg),
          if (d == null)
            _Unavailable(soon: soon)
          else
            _Columns(days: d, today: today ?? DateTime.now(), onUrgentTap: onOpen == null ? null : () => onOpen!(SubscriberFilter.nearExpiry)),
        ],
      ),
    );
  }
}

class _Columns extends StatelessWidget {
  const _Columns({required this.days, required this.today, this.onUrgentTap});

  final List<int> days;
  final DateTime today;
  final VoidCallback? onUrgentTap;

  @override
  Widget build(BuildContext context) {
    final max = math.max(1, days.fold<int>(0, math.max));
    final narrow = MaterialLocalizations.of(context).narrowWeekdays; // [ح ن ث ر خ ج س] من الأحد
    final base = DateTime(today.year, today.month, today.day);
    return SizedBox(
      height: 168,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < days.length; i++)
            Expanded(
              child: _DayColumn(
                count: days[i],
                ratio: days[i] / max,
                urgent: i < DeskRenewalsRunway.urgentDays,
                today: i == 0,
                day: base.add(Duration(days: i)),
                weekday: narrow[base.add(Duration(days: i)).weekday % 7],
                onTap: i < DeskRenewalsRunway.urgentDays && days[i] > 0 ? onUrgentTap : null,
              ),
            ),
        ],
      ),
    );
  }
}

class _DayColumn extends StatefulWidget {
  const _DayColumn({
    required this.count,
    required this.ratio,
    required this.urgent,
    required this.today,
    required this.day,
    required this.weekday,
    this.onTap,
  });

  final int count;
  final double ratio;
  final bool urgent;
  final bool today;
  final DateTime day;
  final String weekday;
  final VoidCallback? onTap;

  @override
  State<_DayColumn> createState() => _DayColumnState();
}

class _DayColumnState extends State<_DayColumn> {
  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final bar = widget.urgent ? AppColors.brand : AppColors.brandSoftBorder;
    final zero = widget.count == 0;
    // الجمعة عطلة الأسبوع بالعراق: تاريخها في حبّةٍ خفيفة تفصل الأسبوعين — لا عمودٌ مظلَّلٌ يُقرأ عموداً فارغاً.
    final friday = widget.day.weekday == DateTime.friday;
    return Tooltip(
      message: 'desktop.runway_tip'.tr(args: [iqDateOf(widget.day), '${widget.count}']),
      waitDuration: const Duration(milliseconds: 300),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: DeskPressable(
          onTap: widget.onTap,
          radius: BorderRadius.circular(R.sm),
          builder: (context, hover) => AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: const EdgeInsets.only(top: Sp.xs),
            decoration: BoxDecoration(
              color: hover ? AppColors.surfaceSunken : null,
              borderRadius: BorderRadius.circular(R.sm),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                // «0» فوق كلّ يومٍ فارغ ضجيجٌ يغطّي الأيّام المهمّة: الخطّ الرفيع يكفي، والمكان محفوظٌ لتبقى الأعمدة بمستوى واحد.
                Opacity(
                  opacity: zero ? 0 : 1,
                  child: Text(
                    '${widget.count}',
                    style: AppType.label(color: AppColors.textHi)
                        .copyWith(fontSize: 13, fontWeight: FontWeight.w700, fontFeatures: const [FontFeature.tabularFigures()]),
                  ),
                ),
                const SizedBox(height: 4),
                LayoutBuilder(builder: (context, c) {
                  const maxH = 96.0;
                  final h = zero ? 2.0 : math.max(6.0, maxH * widget.ratio);
                  return Container(
                    height: h,
                    width: math.min(28, c.maxWidth - 6),
                    decoration: BoxDecoration(
                      color: zero ? AppColors.border : bar,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                    ),
                  );
                }),
                Container(height: 1, color: AppColors.border),
                const SizedBox(height: 4),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
                  decoration: friday
                      ? BoxDecoration(
                          color: AppColors.isDark ? AppColors.surfaceSunken : AppColors.bg,
                          borderRadius: BorderRadius.circular(R.sm),
                        )
                      : null,
                  child: Column(
                    children: [
                      Text(
                        widget.today ? 'desktop.runway_today'.tr() : '${widget.day.day}',
                        maxLines: 1,
                        overflow: TextOverflow.clip,
                        style: AppType.label(color: widget.today ? AppColors.textHi : AppColors.textMid).copyWith(
                          fontSize: 12.5,
                          fontWeight: widget.today ? FontWeight.w700 : FontWeight.w500,
                        ),
                      ),
                      Text(
                        widget.weekday,
                        style: AppType.muted(color: friday ? AppColors.textMid : AppColors.textLow)
                            .copyWith(fontSize: 11.5),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 2),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Unavailable extends StatelessWidget {
  const _Unavailable({required this.soon});

  final int? soon;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Container(
      height: 168,
      alignment: AlignmentDirectional.centerStart,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            soon == null ? '—' : '$soon',
            style: AppType.statValue(color: AppColors.textHi).copyWith(fontSize: 28, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text('desktop.runway_soon_label'.tr(), style: AppType.body(color: AppColors.textMid)),
          const SizedBox(height: Sp.md),
          Text('desktop.runway_unavailable'.tr(), style: AppType.muted(color: AppColors.textLow).copyWith(fontSize: 12.5)),
        ],
      ),
    );
  }
}
