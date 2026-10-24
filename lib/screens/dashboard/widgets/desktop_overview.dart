import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../api/dashboard_api.dart';
import '../../../core/util/format.dart';
import '../../../core/widgets/permission_locked.dart';
import '../../../models/dashboard.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';
import '../../subscribers/widgets/filter_chips_bar.dart';

/// رأس الرئيسيّة على الحاسبة — شريطُ أرقامٍ واحد مقسومٌ بخطوطٍ رفيعة إلى أعمدة (المشتركون، المتّصلون، الرصيد، ديون
/// المشتركين). الرقم خطٌّ لا بلاطة: لا أيقونة في مربّعٍ ملوّن ولا مؤشّر تحت كلّ رقم — قواعد شاشات العمل المقيسة
/// (مهارة الذوق: «KPIs are type, not tiles»). كلّ عمودٍ يفتح المشتركين بفلتره، والمقفل بمكانه بقفله.
///
/// حالات المشتركين التفصيليّة صارت في «توزيع المشتركين» و«التجديدات القادمة» بجانب بعضهما تحته (المالك ٢٤
/// أكتوبر: «إعادة تصميم النسخة الويندوز بشكلٍ احترافي»).
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

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final s = stats;
    final currency = 'common.currency'.tr();
    final cells = <Widget>[
      if (showSubscribers) ...[
        _KpiCell(
          label: 'dashboard.total_subscribers'.tr(),
          value: subsLocked ? null : s == null ? '…' : formatIQD(s.total),
          locked: subsLocked,
          sub: subsLocked || s == null ? null : 'desktop.kpi_active_n'.tr(args: [formatIQD(s.active)]),
          onTap: () => onOpen?.call(SubscriberFilter.all),
        ),
        _KpiCell(
          label: 'dashboard.online'.tr(),
          value: subsLocked ? null : s == null ? '…' : formatIQD(s.online),
          locked: subsLocked,
          sub: subsLocked || s == null ? null : 'desktop.online_of'.tr(args: [formatIQD(s.active)]),
          // الرقم الذي يتغيّر أمام العين: نقطة «حيّ» بلون الاتّصال قبل التسمية.
          live: !subsLocked && s != null,
          onTap: () => onOpen?.call(SubscriberFilter.online),
        ),
      ],
      if (showWallet) ...[
        _KpiCell(
          label: 'dashboard.balance'.tr(),
          value: balanceLocked ? null : wallet == null ? '…' : formatIQD(wallet!.balance.round()),
          unit: currency,
          locked: balanceLocked,
          sub: balanceLocked || wallet == null
              ? null
              : '${formatIQD(wallet!.points.round())} ${'dashboard.points_singular'.tr()}',
        ),
        _KpiCell(
          label: 'dashboard.debtors'.tr(),
          value: debtLocked
              ? null
              : debtors == null
                  ? '…'
                  : debtors!.debtsUnknown
                      ? (debtors!.debtsPending ? '…' : '—')
                      : formatIQD(debtors!.total),
          unit: debtors == null || debtors!.debtsUnknown ? null : currency,
          locked: debtLocked,
          sub: debtLocked || debtors == null
              ? null
              : debtors!.debtsUnknown
                  ? (debtors!.debtsPending ? 'dashboard.debts_counting' : 'dashboard.debts_big_list').tr()
                  : 'desktop.kpi_debtors_n'.tr(args: [formatIQD(debtors!.count)]),
          onTap: () => onOpen?.call(SubscriberFilter.debtors),
        ),
      ],
    ];
    if (cells.isEmpty) return const SizedBox.shrink();
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.card),
        border: Border.all(color: AppColors.border),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(R.card),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < cells.length; i++) ...[
                if (i > 0) VerticalDivider(width: 1, thickness: 1, color: AppColors.border),
                Expanded(child: cells[i]),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// عمود رقمٍ في الشريط: التسمية رماديّة فوق، الرقم بخطّ النصّ ٢٦ (المال بوحدته الصغيرة الرماديّة)، وسطرٌ يفسّره.
class _KpiCell extends StatefulWidget {
  const _KpiCell({
    required this.label,
    required this.value,
    required this.locked,
    this.unit,
    this.sub,
    this.live = false,
    this.onTap,
  });

  final String label;

  /// null = مقفل (بلا صلاحيّة).
  final String? value;
  final String? unit;
  final bool locked;
  final String? sub;
  final bool live;
  final VoidCallback? onTap;

  @override
  State<_KpiCell> createState() => _KpiCellState();
}

class _KpiCellState extends State<_KpiCell> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final tap = widget.locked ? () => showNoPermission(context) : widget.onTap;
    return MouseRegion(
      cursor: tap != null ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: tap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          color: _hover && tap != null ? AppColors.surfaceSunken : AppColors.surface,
          padding: const EdgeInsets.fromLTRB(Sp.xl, Sp.lg, Sp.xl, Sp.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  if (widget.live) ...[
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(color: AppColors.success, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 6),
                  ],
                  if (widget.locked) ...[
                    Icon(LucideIcons.lock, size: 13, color: LockedStyle.glyph),
                    const SizedBox(width: 6),
                  ],
                  Expanded(
                    child: Text(
                      widget.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.muted(color: AppColors.textMid).copyWith(fontSize: 13),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Sp.sm),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(
                        widget.locked ? '—' : widget.value ?? '…',
                        maxLines: 1,
                        style: AppType.statValue(color: widget.locked ? LockedStyle.title : AppColors.textHi).copyWith(
                          fontSize: 28,
                          fontWeight: FontWeight.w600,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ),
                  if (widget.unit != null && !widget.locked) ...[
                    const SizedBox(width: 6),
                    Text(widget.unit!, style: AppType.muted(color: AppColors.textLow).copyWith(fontSize: 13)),
                  ],
                ],
              ),
              if (widget.sub != null) ...[
                const SizedBox(height: 4),
                Text(
                  widget.sub!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.muted(color: AppColors.textMid).copyWith(fontSize: 12.5),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
