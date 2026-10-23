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

/// رأس الرئيسيّة على الحاسبة — صفّ أرقامٍ رئيسيّة (stat tiles) ثمّ شريط حالات المشتركين.
///
/// قواعده (مهارة dataviz): الرقم بلون النصّ لا بلون الحالة — الحالة أيقونةٌ وتسميةٌ بجانبه؛ لا شريطٌ
/// مقسَّمٌ بألوان الحالة (الأحمر/الكهرمانيّ متقاربان لضعاف تمييز الألوان: فحصٌ ΔE 4.5)؛ النسبة الوحيدة
/// «نشط من الإجمالي» مؤشّرٌ بلونٍ واحد على مسارٍ من درجته. كلّ بلاطةٍ تفتح المشتركين بفلترها.
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
    final kpis = <Widget>[
      if (showSubscribers) ...[
      _StatTile(
        label: 'dashboard.total_subscribers'.tr(),
        icon: LucideIcons.users,
        tone: AppTone.brand,
        value: subsLocked ? null : s == null ? '…' : formatIQD(s.total),
        locked: subsLocked,
        footer: subsLocked || s == null
            ? null
            : _Meter(
                ratio: s.total > 0 ? s.active / s.total : 0,
                caption: 'desktop.active_of'.tr(args: [formatIQD(s.active), formatIQD(s.total)]),
              ),
        onTap: () => onOpen?.call(SubscriberFilter.all),
      ),
      _StatTile(
        label: 'dashboard.online'.tr(),
        icon: LucideIcons.wifi,
        tone: AppTone.success,
        value: subsLocked ? null : s == null ? '…' : formatIQD(s.online),
        locked: subsLocked,
        footer: subsLocked || s == null
            ? null
            : _Meter(
                ratio: s.active > 0 ? s.online / s.active : 0,
                caption: 'desktop.online_of'.tr(args: [formatIQD(s.active)]),
              ),
        onTap: () => onOpen?.call(SubscriberFilter.online),
      ),
      ],
      if (showWallet) ...[
      _StatTile(
        label: 'dashboard.balance'.tr(),
        icon: LucideIcons.wallet,
        tone: AppTone.brand,
        value: balanceLocked ? null : wallet == null ? '…' : formatIQD(wallet!.balance.round()),
        unit: currency,
        locked: balanceLocked,
        footer: balanceLocked || wallet == null
            ? null
            : _Caption('${formatIQD(wallet!.points.round())} ${'dashboard.points_singular'.tr()}'),
      ),
      _StatTile(
        label: 'dashboard.debtors'.tr(),
        icon: LucideIcons.creditCard,
        tone: AppTone.warning,
        value: debtLocked
            ? null
            : debtors == null
                ? '…'
                : debtors!.debtsUnknown
                    ? (debtors!.debtsPending ? '…' : '—')
                    : formatIQD(debtors!.total),
        unit: debtors == null || debtors!.debtsUnknown ? null : currency,
        locked: debtLocked,
        footer: debtLocked || debtors == null
            ? null
            : _Caption(debtors!.debtsUnknown
                ? (debtors!.debtsPending ? 'dashboard.debts_counting' : 'dashboard.debts_big_list').tr()
                : '${formatIQD(debtors!.count)} ${'dashboard.subscriber_singular'.tr()}'),
        onTap: () => onOpen?.call(SubscriberFilter.debtors),
      ),
      ],
    ];
    final statuses = <Widget>[
      _StatusTile(LucideIcons.circleCheck, AppTone.brand, 'dashboard.active'.tr(), s?.active,
          subsLocked, () => onOpen?.call(SubscriberFilter.active)),
      _StatusTile(LucideIcons.wifiOff, AppTone.neutral, 'dashboard.offline'.tr(), s?.offline,
          subsLocked, () => onOpen?.call(SubscriberFilter.offline)),
      _StatusTile(LucideIcons.timerOff, AppTone.danger, 'dashboard.expired'.tr(), s?.expired,
          subsLocked, () => onOpen?.call(SubscriberFilter.expired)),
      _StatusTile(LucideIcons.triangleAlert, AppTone.warning, 'dashboard.near_expiry'.tr(),
          s?.nearExpiry, subsLocked, () => onOpen?.call(SubscriberFilter.nearExpiry)),
      _StatusTile(LucideIcons.wifi, AppTone.anomaly, 'dashboard.online_no_plan'.tr(),
          s?.onlineNoPlan, subsLocked, () => onOpen?.call(SubscriberFilter.onlineNoPlan)),
      _StatusTile(LucideIcons.ban, AppTone.neutral, 'dashboard.disabled'.tr(), s?.disabled,
          subsLocked, () => onOpen?.call(SubscriberFilter.disabled)),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (kpis.isNotEmpty) _row(kpis, gap: Sp.md),
        if (kpis.isNotEmpty && showSubscribers) const SizedBox(height: Sp.md),
        if (showSubscribers) _row(statuses, gap: Sp.sm),
      ],
    );
  }

  static Widget _row(List<Widget> children, {required double gap}) => IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) SizedBox(width: gap),
              Expanded(child: children[i]),
            ],
          ],
        ),
      );
}

/// بلاطةٌ قابلة للنقر بإبراز المرور (الفأرة) — إطار البلاطات كلّها.
class _HoverCard extends StatefulWidget {
  const _HoverCard({required this.child, this.onTap, this.padding = const EdgeInsets.all(Sp.lg)});

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsets padding;

  @override
  State<_HoverCard> createState() => _HoverCardState();
}

class _HoverCardState extends State<_HoverCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final tappable = widget.onTap != null;
    return MouseRegion(
      cursor: tappable ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: widget.padding,
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(R.lg),
            border: Border.all(
              color: _hover && tappable ? AppColors.borderStrong : AppColors.border,
            ),
          ),
          child: widget.child,
        ),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.label,
    required this.icon,
    required this.tone,
    required this.value,
    required this.locked,
    this.unit,
    this.footer,
    this.onTap,
  });

  final String label;
  final IconData icon;
  final AppTone tone;

  /// null = مقفل (بلا صلاحيّة).
  final String? value;
  final String? unit;
  final bool locked;
  final Widget? footer;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return _HoverCard(
      onTap: locked ? () => showNoPermission(context) : onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.muted(color: AppColors.textMid).copyWith(fontSize: 13),
                ),
              ),
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: locked ? LockedStyle.box : tone.softBg,
                  borderRadius: BorderRadius.circular(R.sm),
                ),
                child: Icon(locked ? LucideIcons.lock : icon,
                    size: 16, color: locked ? LockedStyle.glyph : tone.fill),
              ),
            ],
          ),
          const SizedBox(height: Sp.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: Text(
                  locked ? '—' : value ?? '…',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.statValue(color: locked ? LockedStyle.title : AppColors.textHi)
                      .copyWith(fontSize: 24, fontWeight: FontWeight.w700),
                ),
              ),
              if (unit != null && !locked) ...[
                const SizedBox(width: 6),
                Text(unit!, style: AppType.muted(color: AppColors.textLow).copyWith(fontSize: 12.5)),
              ],
            ],
          ),
          if (footer != null) ...[
            const SizedBox(height: Sp.sm),
            footer!,
          ],
        ],
      ),
    );
  }
}

class _Caption extends StatelessWidget {
  const _Caption(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: AppType.muted(color: AppColors.textMid).copyWith(fontSize: 12.5),
    );
  }
}

/// نسبةٌ واحدة إلى حدّ: تعبئةٌ بلون الحالة الجيّدة على مسارٍ من درجتها الفاتحة (لا لونان متجاوران).
class _Meter extends StatelessWidget {
  const _Meter({required this.ratio, required this.caption});

  final double ratio;
  final String caption;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final r = ratio.isNaN ? 0.0 : ratio.clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(R.sm),
          child: SizedBox(
            height: 6,
            child: Stack(
              children: [
                Positioned.fill(child: ColoredBox(color: AppColors.successSoftBg)),
                Positioned.fill(
                  child: FractionallySizedBox(
                    alignment: AlignmentDirectional.centerStart,
                    widthFactor: r,
                    heightFactor: 1,
                    child: ColoredBox(color: AppColors.success),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          caption,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppType.muted(color: AppColors.textMid).copyWith(fontSize: 12.5),
        ),
      ],
    );
  }
}

class _StatusTile extends StatelessWidget {
  const _StatusTile(this.icon, this.tone, this.label, this.value, this.locked, this.onTap);

  final IconData icon;
  final AppTone tone;
  final String label;
  final int? value;
  final bool locked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return _HoverCard(
      padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: Sp.md),
      onTap: locked ? () => showNoPermission(context) : onTap,
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: locked ? LockedStyle.box : tone.softBg,
              borderRadius: BorderRadius.circular(R.sm),
            ),
            child: Icon(icon, size: 17, color: locked ? LockedStyle.glyph : tone.fill),
          ),
          const SizedBox(width: Sp.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  locked ? '—' : value == null ? '…' : formatIQD(value!),
                  maxLines: 1,
                  style: AppType.statValue(color: locked ? LockedStyle.title : AppColors.textHi)
                      .copyWith(fontSize: 19, fontWeight: FontWeight.w700),
                ),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.muted(color: AppColors.textMid).copyWith(fontSize: 12.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
