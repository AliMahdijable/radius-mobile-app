import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../api/dashboard_api.dart';
import '../../../core/util/format.dart';
import '../../../core/widgets/desk_pressable.dart';
import '../../../core/widgets/permission_locked.dart';
import '../../../models/dashboard.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';
import '../../desktop/desk_widgets.dart';
import '../../subscribers/widgets/filter_chips_bar.dart';

/// رأس الرئيسيّة على الحاسبة — أربع بطاقات أرقام: المشتركون، المتّصلون، الرصيد، ديون المشتركين.
///
/// المالك ٢٤ أكتوبر رفض الأرقام نصّاً على الخلفيّة («بدون أي تأثيرات وحدود وألوان تبين كأنها كتابة نصّيّة جامدة»):
/// كلّ بطاقةٍ بحدّها وظلّها ([DeskCard])، ولونٍ يعرّفها (أيقونةٌ في مربّعٍ ملوّن)، وشريط نسبةٍ بلونها حيث للرقم
/// نسبة (النشطون من الكلّ، المتّصلون من النشطين، المدينون من الكلّ) — مرجع ui-ux-pro-max لبطاقات المؤشّرات: الرقم
/// مع ما يُقاس عليه. وفي المرور ترتفع البطاقة وظلّها بلونها؛ النقر يفتح المشتركين بفلتر البطاقة، والمقفل بمكانه بقفله.
/// ومكان الرقم قبل وصوله خطٌّ ثابت لا «…».
class DesktopOverview extends StatelessWidget {
  const DesktopOverview({
    super.key,
    required this.stats,
    required this.wallet,
    required this.debtors,
    required this.subsLocked,
    required this.balanceLocked,
    required this.debtLocked,
    this.showSubscribers = true,
    this.showWallet = true,
    this.onOpen,
  });

  /// «نطاق العرض»: ما أخفاه المدير من الرئيسيّة لا يظهر هنا أيضاً.
  final bool showSubscribers;
  final bool showWallet;

  final SubscribersStats? stats;
  final WalletResult? wallet;
  final DebtorsResult? debtors;
  final bool subsLocked;
  final bool balanceLocked;
  final bool debtLocked;
  final ValueChanged<SubscriberFilter?>? onOpen;

  static double? _ratio(int part, int whole) => whole > 0 ? (part / whole).clamp(0.0, 1.0).toDouble() : null;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final s = stats;
    final d = debtors;
    final currency = 'common.currency'.tr();
    final cards = <Widget>[
      if (showSubscribers) ...[
        _KpiCard(
          icon: LucideIcons.users,
          accent: AppColors.brand,
          soft: AppColors.brandSoftBg,
          label: 'dashboard.total_subscribers'.tr(),
          value: subsLocked ? null : s == null ? '…' : formatIQD(s.total),
          locked: subsLocked,
          caption: subsLocked || s == null ? null : 'desktop.kpi_active_n'.tr(args: [formatIQD(s.active)]),
          ratio: subsLocked || s == null ? null : _ratio(s.active, s.total),
          onTap: () => onOpen?.call(SubscriberFilter.all),
        ),
        _KpiCard(
          icon: LucideIcons.wifi,
          accent: AppColors.info,
          soft: AppColors.infoSoftBg,
          label: 'dashboard.online'.tr(),
          value: subsLocked ? null : s == null ? '…' : formatIQD(s.online),
          locked: subsLocked,
          caption: subsLocked || s == null ? null : 'desktop.online_of'.tr(args: [formatIQD(s.active)]),
          ratio: subsLocked || s == null ? null : _ratio(s.online, s.active),
          // الرقم الذي يتغيّر أمام العين: نقطة «حيّ» بجانب التسمية.
          live: !subsLocked && s != null,
          onTap: () => onOpen?.call(SubscriberFilter.online),
        ),
      ],
      if (showWallet) ...[
        _KpiCard(
          icon: LucideIcons.wallet,
          accent: AppColors.warning,
          soft: AppColors.warningSoftBg,
          label: 'dashboard.balance'.tr(),
          value: balanceLocked ? null : wallet == null ? '…' : formatIQD(wallet!.balance.round()),
          unit: currency,
          locked: balanceLocked,
          caption: balanceLocked || wallet == null
              ? null
              : '${formatIQD(wallet!.points.round())} ${'dashboard.points_singular'.tr()}',
        ),
        _KpiCard(
          icon: LucideIcons.creditCard,
          accent: AppColors.error,
          soft: AppColors.dangerSoftBg,
          label: 'dashboard.debtors'.tr(),
          value: debtLocked
              ? null
              : d == null
                  ? '…'
                  : d.debtsUnknown
                      ? (d.debtsPending ? '…' : '—')
                      : formatIQD(d.total),
          unit: d == null || d.debtsUnknown ? null : currency,
          locked: debtLocked,
          caption: debtLocked || d == null
              ? null
              : d.debtsUnknown
                  ? (d.debtsPending ? 'dashboard.debts_counting' : 'dashboard.debts_big_list').tr()
                  : 'desktop.kpi_debtors_n'.tr(args: [formatIQD(d.count)]),
          ratio: debtLocked || d == null || d.debtsUnknown ? null : _ratio(d.count, d.totalSubs),
          onTap: () => onOpen?.call(SubscriberFilter.debtors),
        ),
      ],
    ];
    if (cards.isEmpty) return const SizedBox.shrink();
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < cards.length; i++) ...[
            if (i > 0) const SizedBox(width: Sp.md),
            Expanded(child: cards[i]),
          ],
        ],
      ),
    );
  }
}

/// بطاقة رقم: أيقونةٌ في مربّعٍ بلون البطاقة والتسمية، الرقم كبيراً (المال بوحدته الصغيرة)، ثمّ سطرٌ يفسّره
/// وشريط نسبته.
class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.icon,
    required this.accent,
    required this.soft,
    required this.label,
    required this.value,
    required this.locked,
    this.unit,
    this.caption,
    this.ratio,
    this.live = false,
    this.onTap,
  });

  final IconData icon;
  final Color accent;
  final Color soft;
  final String label;

  /// null = مقفل (بلا صلاحيّة)؛ «…» = لم يصل بعد.
  final String? value;
  final String? unit;
  final bool locked;
  final String? caption;

  /// ما يُقاس عليه الرقم (٠–١) — شريطٌ بلون البطاقة ونسبته.
  final double? ratio;
  final bool live;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final tap = locked ? () => showNoPermission(context) : onTap;
    final loading = !locked && value == '…';
    final tone = locked ? LockedStyle.glyph : accent;
    return DeskPressable(
      onTap: tap,
      radius: BorderRadius.circular(R.card),
      semanticLabel: label,
      builder: (context, hover) => AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
        // يرتفع قليلاً في المرور (ما يُنقر وحده) — والظلّ يتعمّق بلون البطاقة.
        transform: Matrix4.translationValues(0, hover && tap != null ? -2 : 0, 0),
        decoration: DeskCard.decoration(hover: hover && tap != null, accent: tone),
        padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.lg, Sp.lg, Sp.md + 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: locked ? LockedStyle.box : soft,
                    borderRadius: BorderRadius.circular(R.md),
                  ),
                  child: Icon(locked ? LucideIcons.lock : icon, size: 20, color: tone),
                ),
                const SizedBox(width: Sp.md),
                // التسمية تأخذ ما بقي كلّه (ونقطة «حيّ» بجانبها)، والسهم في الطرف.
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppType.label(color: AppColors.textMid)
                              .copyWith(fontSize: 14, fontWeight: FontWeight.w600),
                        ),
                      ),
                      if (live) ...[const SizedBox(width: Sp.sm), const _LiveDot()],
                    ],
                  ),
                ),
                if (tap != null && !locked)
                  AnimatedOpacity(
                    opacity: hover ? 1 : 0,
                    duration: const Duration(milliseconds: 160),
                    child: Padding(
                      padding: const EdgeInsetsDirectional.only(start: Sp.xs),
                      child: Icon(
                        Directionality.of(context) == TextDirection.rtl
                            ? LucideIcons.chevronLeft
                            : LucideIcons.chevronRight,
                        size: 18,
                        color: accent,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: Sp.md),
            if (loading)
              const _Skeleton(width: 120, height: 28, top: 4, bottom: 4)
            else
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(
                        locked ? '—' : value ?? '…',
                        maxLines: 1,
                        style: AppType.statValue(color: locked ? LockedStyle.title : AppColors.textHi).copyWith(
                          fontSize: 30,
                          fontWeight: FontWeight.w700,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ),
                  if (unit != null && !locked) ...[
                    const SizedBox(width: 6),
                    Text(unit!, style: AppType.muted(color: AppColors.textLow).copyWith(fontSize: 13)),
                  ],
                ],
              ),
            const SizedBox(height: Sp.sm),
            if (caption != null)
              Row(
                children: [
                  Expanded(
                    child: Text(
                      caption!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.muted(color: AppColors.textMid).copyWith(fontSize: 12.5),
                    ),
                  ),
                  if (ratio != null)
                    Text(
                      '${(ratio! * 100).round()}%',
                      style: AppType.label(color: accent).copyWith(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                ],
              )
            else if (loading)
              const _Skeleton(width: 72, height: 10, top: 3, bottom: 3),
            if (ratio != null) ...[
              const SizedBox(height: 6),
              _Bar(ratio: ratio!, color: accent),
            ],
          ],
        ),
      ),
    );
  }
}

/// شريط النسبة: مسارٌ خافت بلون البطاقة الفاتح، والملء بلونها.
class _Bar extends StatelessWidget {
  const _Bar({required this.ratio, required this.color});

  final double ratio;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(R.pill),
      child: SizedBox(
        height: 6,
        width: double.infinity,
        child: Stack(
          children: [
            Positioned.fill(child: ColoredBox(color: color.withValues(alpha: 0.14))),
            FractionallySizedBox(
              alignment: AlignmentDirectional.centerStart,
              widthFactor: ratio == 0 ? 0 : ratio.clamp(0.03, 1.0),
              heightFactor: 1,
              child: DecoratedBox(
                decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(R.pill)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// «حيّ»: نقطةٌ خضراء بهالةٍ خفيفة (ثابتة — لا حركة تُبقي الإطار يُرسم).
class _LiveDot extends StatelessWidget {
  const _LiveDot();

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'desktop.live'.tr(),
      child: Container(
        width: 14,
        height: 14,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: AppColors.success.withValues(alpha: 0.18), shape: BoxShape.circle),
        child: Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: AppColors.success, shape: BoxShape.circle),
        ),
      ),
    );
  }
}

/// مكان رقمٍ لم يصل بعد: خطٌّ ثابتٌ بلون الحدود بحجم الرقم تقريباً — فلا تقفز البطاقة حين يصل، ولا حركة تُبقي
/// الإطار يُرسم بلا توقّف (ولا تعلق اختبارات «انتظر حتى تهدأ»).
class _Skeleton extends StatelessWidget {
  const _Skeleton({required this.width, required this.height, this.top = 0, this.bottom = 0});

  final double width;
  final double height;
  final double top;
  final double bottom;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Padding(
      padding: EdgeInsets.only(top: top, bottom: bottom),
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(R.sm)),
      ),
    );
  }
}
