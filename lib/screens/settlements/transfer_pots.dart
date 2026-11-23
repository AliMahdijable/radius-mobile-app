import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/util/amount_input.dart';
import '../../core/util/format.dart';
import '../../core/widgets/app_sheet.dart';
import '../../core/widgets/design_sheet.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import '../reports/v2/report_kit.dart';

/// «رصيد الحوالات» (٢٣ نوفمبر — المالك: «بعدها بالماستر مالته، الى ان المدير يسحبها يلا يعلم الحركة انه نزلت للكاش»): ما وصل
/// حوالةً لكلّ طريقة (زين كاش، ماستر، وأخرى باسمها) — خارج الصندوق حتى «سحب للصندوق». لا عمولة (المالك: «هو يصفرها من يمه»).
class TransferPot {
  const TransferPot({required this.key, required this.label, required this.balance, this.received = 0, this.withdrawn = 0});

  /// zaincash | master | other:<الاسم>
  final String key;
  final String label;

  /// الباقي الآن = ما وصل − ما سُحب.
  final num balance;
  final num received;
  final num withdrawn;

  IconData get icon => switch (key) {
        'zaincash' => LucideIcons.smartphone,
        'master' => LucideIcons.landmark,
        _ => LucideIcons.arrowLeftRight,
      };
}

/// بطاقة «رصيد الحوالات» — سطرٌ لكلّ طريقة بباقيها وزرّ «سحب للصندوق».
class TransferPotsCard extends StatelessWidget {
  const TransferPotsCard({super.key, required this.pots, this.onWithdraw});

  final List<TransferPot> pots;
  final ValueChanged<TransferPot>? onWithdraw;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final total = pots.fold<num>(0, (s, p) => s + p.balance);
    return RpCard(
      key: const ValueKey('transfer-pots-card'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            const RpIconBox(icon: LucideIcons.arrowLeftRight, tone: RpTone.info, size: 36),
            const SizedBox(width: Sp.md),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('رصيد الحوالات', style: AppType.bodyBold(color: AppColors.textHi)),
                Text('وصلتك حوالة — خارج الصندوق حتى تسحبها', style: AppType.micro(color: AppColors.textMid)),
              ]),
            ),
          ]),
          const SizedBox(height: Sp.md),
          for (final p in pots) ...[
            _PotRow(pot: p, onWithdraw: onWithdraw == null || p.balance <= 0 ? null : () => onWithdraw!(p)),
            if (p != pots.last) Divider(height: Sp.lg, color: AppColors.border),
          ],
          const SizedBox(height: Sp.md),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: Sp.sm),
            decoration: BoxDecoration(color: AppColors.brandSoftBg, borderRadius: BorderRadius.circular(R.md)),
            child: Row(children: [
              Expanded(child: Text('المجموع خارج الصندوق', style: AppType.body(color: AppColors.textMid))),
              Text('${formatIQD(total.round())} ${'common.currency'.tr()}', style: AppType.bodyBold(color: AppColors.textHi)),
            ]),
          ),
        ],
      ),
    );
  }
}

class _PotRow extends StatelessWidget {
  const _PotRow({required this.pot, this.onWithdraw});
  final TransferPot pot;
  final VoidCallback? onWithdraw;

  @override
  Widget build(BuildContext context) {
    final cur = 'common.currency'.tr();
    return Row(children: [
      Icon(pot.icon, size: 20, color: AppColors.textMid),
      const SizedBox(width: Sp.sm),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(pot.label, style: AppType.bodyStrong(color: AppColors.textHi)),
          Text('${formatIQD(pot.balance.round())} $cur', style: AppType.bodyBold(color: AppColors.brand)),
          if (pot.withdrawn > 0)
            Text('وصل ${formatIQD(pot.received.round())} · سُحب ${formatIQD(pot.withdrawn.round())}',
                style: AppType.micro(color: AppColors.textLow)),
        ]),
      ),
      OutlinedButton.icon(
        key: ValueKey('transfer-withdraw-${pot.key}'),
        onPressed: onWithdraw,
        icon: const Icon(LucideIcons.arrowDownToLine, size: 16),
        label: const Text('سحب للصندوق'),
        style: OutlinedButton.styleFrom(
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: Sp.md),
          textStyle: AppType.label(),
        ),
      ),
    ]);
  }
}

/// «سحب للصندوق» من رصيد طريقة — المبلغ الذي أنزله نقداً (بلا عمولة: الوكيل يصفّرها من عنده).
Future<void> showTransferWithdrawSheet(BuildContext context, TransferPot pot) {
  return showAppSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: AppColors.scrim,
    isScrollControlled: true,
    builder: (_) => _WithdrawSheet(pot: pot),
  );
}

class _WithdrawSheet extends StatefulWidget {
  const _WithdrawSheet({required this.pot});
  final TransferPot pot;

  @override
  State<_WithdrawSheet> createState() => _WithdrawSheetState();
}

class _WithdrawSheetState extends State<_WithdrawSheet> {
  final _amountCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  num _amount = 0;

  @override
  void dispose() {
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  void _setAmount(num v) {
    _amountCtrl.text = formatIQD(v.round());
    setState(() => _amount = v);
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final p = widget.pot;
    final cur = 'common.currency'.tr();
    final over = _amount > p.balance;
    final left = p.balance - _amount;
    return DesignSheet(
      header: SheetHeaderBar(
        icon: LucideIcons.arrowDownToLine,
        title: 'سحب للصندوق',
        subtitle: 'من رصيد ${p.label} — ${formatIQD(p.balance.round())} $cur',
        onClose: () => Navigator.of(context).pop(),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SheetSection(
            label: 'المبلغ الذي سحبته نقداً',
            gap: 9,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              SheetBox(
                focused: _amount > 0,
                radius: 18,
                padding: const EdgeInsets.symmetric(horizontal: Sp.lg, vertical: 14),
                child: AmountTextField(controller: _amountCtrl, currency: cur, onValue: (v) => setState(() => _amount = v)),
              ),
              const SizedBox(height: 9),
              Wrap(spacing: 7, runSpacing: 7, children: [
                SheetQuickChip(
                  label: 'كامل الرصيد',
                  icon: LucideIcons.checkCheck,
                  suggested: true,
                  selected: _amount == p.balance,
                  onTap: () => _setAmount(p.balance),
                ),
                for (final c in const [50000, 100000, 200000])
                  if (c < p.balance) SheetQuickChip(label: formatIQD(c), selected: _amount == c, onTap: () => _setAmount(c)),
              ]),
            ]),
          ),
          const SizedBox(height: Sp.lg),
          SheetBox(
            icon: LucideIcons.fileText,
            child: TextField(
              controller: _noteCtrl,
              style: AppType.input(),
              maxLength: 120,
              decoration: InputDecoration(
                isDense: true,
                counterText: '',
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
                hintText: 'ملاحظة (اختياري)',
                hintStyle: AppType.input(color: AppColors.textPlaceholder),
              ),
            ),
          ),
          if (_amount > 0) ...[
            const SizedBox(height: Sp.lg),
            SheetResultBanner(
              icon: over ? LucideIcons.triangleAlert : LucideIcons.arrowLeft,
              label: over ? 'أكثر من رصيد ${p.label}' : 'يبقى برصيد ${p.label}',
              value: over ? '${formatIQD(p.balance.round())} $cur فقط' : '${formatIQD(left.round())} $cur',
              tone: over ? AppTone.danger : AppTone.brand,
            ),
            const SizedBox(height: Sp.sm),
            Text('يدخل الصندوق ${formatIQD(_amount.round())} $cur — ويظهر بـ«تسوية الحساب» سطر «سحب من ${p.label}».',
                style: AppType.muted(color: AppColors.textMid)),
          ],
        ],
      ),
      footer: SheetFooterBar(
        key: const ValueKey('transfer-withdraw-confirm'),
        label: _amount > 0 && !over ? 'سحب ${formatIQD(_amount.round())} $cur للصندوق' : 'سحب للصندوق',
        icon: LucideIcons.check,
        enabled: _amount > 0 && !over,
        onPressed: () => Navigator.of(context).pop(),
      ),
    );
  }
}
