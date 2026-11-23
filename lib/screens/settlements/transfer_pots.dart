import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../api/transfer_pay_api.dart';
import '../../core/util/amount_input.dart';
import '../../core/util/format.dart';
import '../../core/util/server_time.dart';
import '../../core/widgets/app_sheet.dart';
import '../../core/widgets/design_sheet.dart';
import '../../core/widgets/sheet_scaffold.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import '../reports/v2/report_kit.dart';

/// «رصيد الحوالات» (٢٣ نوفمبر — المالك: «بعدها بالماستر مالته، الى ان المدير يسحبها يلا يعلم الحركة انه نزلت للكاش»): ما وصل
/// حوالةً لكلّ طريقة (زين كاش، ماستر، وأخرى باسمها) — خارج الصندوق حتى «سحب للصندوق». لا عمولة (المالك: «هو يصفرها من يمه»).
/// البيانات من GET /api/v2/transfer-pots ([TransferPayApi.pots])؛ السحب وإلغاؤه للمدير وحده ([TransferPotsData.canWithdraw]).
IconData transferViaIcon(String via) => switch (via) {
      'zaincash' => LucideIcons.smartphone,
      'master' => LucideIcons.landmark,
      _ => LucideIcons.arrowLeftRight,
    };

/// بطاقة «رصيد الحوالات» — سطرٌ لكلّ طريقة بباقيها وزرّ «سحب للصندوق»، ومجموعها، و«آخر السحوبات» بإلغائها.
class TransferPotsCard extends StatefulWidget {
  const TransferPotsCard({super.key, required this.data, this.onWithdraw, this.onVoid});

  final TransferPotsData data;
  final ValueChanged<TransferPotData>? onWithdraw;
  final ValueChanged<TransferWithdrawalData>? onVoid;

  @override
  State<TransferPotsCard> createState() => _TransferPotsCardState();
}

class _TransferPotsCardState extends State<TransferPotsCard> {
  bool _log = false;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final d = widget.data;
    final pots = d.pots.where((p) => p.balance != 0 || p.received != 0 || p.withdrawn != 0).toList();
    final cur = 'common.currency'.tr();
    final withdrawals = d.withdrawals.where((w) => !w.isVoidRow).length;
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
          if (pots.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: Sp.sm),
              child: Text('لا حوالات بعد — حين تستلم مبلغاً بزين كاش أو ماستر يظهر رصيده هنا.',
                  key: const ValueKey('transfer-pots-empty'), style: AppType.muted(color: AppColors.textMid)),
            ),
          for (final p in pots) ...[
            _PotRow(
              pot: p,
              onWithdraw: !d.canWithdraw || widget.onWithdraw == null || p.balance <= 0 ? null : () => widget.onWithdraw!(p),
            ),
            if (p != pots.last) Divider(height: Sp.lg, color: AppColors.border),
          ],
          if (pots.isNotEmpty) ...[
            const SizedBox(height: Sp.md),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: Sp.sm),
              decoration: BoxDecoration(color: AppColors.brandSoftBg, borderRadius: BorderRadius.circular(R.md)),
              child: Row(children: [
                Expanded(
                  child: Text('المجموع خارج الصندوق',
                      maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.body(color: AppColors.textMid)),
                ),
                Text('${formatIQD(d.total.round())} $cur',
                    key: const ValueKey('transfer-pots-total'), style: AppType.bodyBold(color: AppColors.textHi)),
              ]),
            ),
          ],
          if (!d.canWithdraw && pots.any((p) => p.balance > 0)) ...[
            const SizedBox(height: Sp.x6),
            Text('السحب للصندوق للمدير وحده.',
                key: const ValueKey('transfer-pots-owner-only'), style: AppType.micro(color: AppColors.textMid)),
          ],
          if (d.withdrawals.isNotEmpty) ...[
            const SizedBox(height: Sp.sm),
            Divider(height: 1, color: AppColors.border),
            InkWell(
              key: const ValueKey('transfer-pots-log-toggle'),
              onTap: () => setState(() => _log = !_log),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: Sp.sm),
                child: Row(children: [
                  Icon(LucideIcons.history, size: 16, color: AppColors.textMid),
                  const SizedBox(width: Sp.x6),
                  Expanded(
                    child: Text('آخر السحوبات ($withdrawals)', style: AppType.label(color: AppColors.textMid)),
                  ),
                  Icon(_log ? LucideIcons.chevronUp : LucideIcons.chevronDown, size: 16, color: AppColors.textLow),
                ]),
              ),
            ),
            if (_log)
              for (final w in d.withdrawals)
                _WithdrawalRow(
                  w: w,
                  onVoid: d.canWithdraw && widget.onVoid != null && !w.isVoidRow && !w.voided ? () => widget.onVoid!(w) : null,
                ),
          ],
        ],
      ),
    );
  }
}

class _PotRow extends StatelessWidget {
  const _PotRow({required this.pot, this.onWithdraw});
  final TransferPotData pot;
  final VoidCallback? onWithdraw;

  @override
  Widget build(BuildContext context) {
    final cur = 'common.currency'.tr();
    return Row(key: ValueKey('transfer-pot-${pot.key}'), children: [
      Icon(transferViaIcon(pot.via), size: 20, color: AppColors.textMid),
      const SizedBox(width: Sp.sm),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(pot.label, style: AppType.bodyStrong(color: AppColors.textHi)),
          Text('${formatIQD(pot.balance.round())} $cur',
              style: AppType.bodyBold(color: pot.balance < 0 ? AppColors.error : AppColors.brand)),
          if (pot.withdrawn != 0)
            // «وصل» و«· سُحب» قطعتان لا تنكسران — النقطة تنزل مع ما بعدها على الشاشة الضيّقة
            Wrap(children: [
              Text('وصل ${formatIQD(pot.received.round())} ', style: AppType.micro(color: AppColors.textLow)),
              Text('· سُحب ${formatIQD(pot.withdrawn.round())}', style: AppType.micro(color: AppColors.textLow)),
            ]),
        ]),
      ),
      if (onWithdraw != null)
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

class _WithdrawalRow extends StatelessWidget {
  const _WithdrawalRow({required this.w, this.onVoid});
  final TransferWithdrawalData w;
  final VoidCallback? onVoid;

  @override
  Widget build(BuildContext context) {
    final cur = 'common.currency'.tr();
    final at = w.createdAt?.toLocal();
    final when = at == null ? '' : '${at.year}/${at.month.toString().padLeft(2, '0')}/${at.day.toString().padLeft(2, '0')} · ${clock12Ar(at)}';
    final amountColor = w.isVoidRow ? AppColors.error : (w.voided ? AppColors.textLow : AppColors.success);
    return Padding(
      key: ValueKey('transfer-withdrawal-${w.id}'),
      padding: const EdgeInsets.symmetric(vertical: Sp.x6),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${w.isVoidRow ? 'إلغاء سحب من' : 'سحب من'} ${w.label}${w.voided ? ' · أُلغي' : ''}',
                style: AppType.body(color: AppColors.textHi)),
            if (when.isNotEmpty || w.note != null)
              Text([if (when.isNotEmpty) when, if (w.note != null) w.note!].join(' · '), style: AppType.micro(color: AppColors.textLow)),
          ]),
        ),
        const SizedBox(width: Sp.sm),
        Text('${formatIQD(w.amount.abs().round())} $cur',
            style: AppType.bodyStrong(color: amountColor).copyWith(
              decoration: w.voided ? TextDecoration.lineThrough : null,
              decorationColor: AppColors.textLow,
            )),
        if (onVoid != null)
          IconButton(
            key: ValueKey('transfer-void-${w.id}'),
            tooltip: 'إلغاء السحب',
            onPressed: onVoid,
            visualDensity: VisualDensity.compact,
            icon: Icon(LucideIcons.undo2, size: 18, color: AppColors.textMid),
          ),
      ]),
    );
  }
}

/// «سحب للصندوق» من رصيد طريقة — المبلغ الذي أنزله نقداً (بلا عمولة: الوكيل يصفّرها من عنده). true = سُحب (أو كان مسجَّلاً).
Future<bool?> showTransferWithdrawSheet(BuildContext context, TransferPotData pot) {
  return showAppSheet<bool>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: AppColors.scrim,
    isScrollControlled: true,
    builder: (_) => _WithdrawSheet(pot: pot),
  );
}

class _WithdrawSheet extends StatefulWidget {
  const _WithdrawSheet({required this.pot});
  final TransferPotData pot;

  @override
  State<_WithdrawSheet> createState() => _WithdrawSheetState();
}

class _WithdrawSheetState extends State<_WithdrawSheet> {
  final _amountCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  late num _amount = widget.pot.balance > 0 ? widget.pot.balance.floor() : 0;
  bool _busy = false;

  /// مفتاح الطلب لهذا الشيت: الإعادة بعد انقطاعٍ تردّ السحب نفسه ولا تسحب مرّتين.
  final String _clientRef = TransferPayApi.newClientRef();

  @override
  void initState() {
    super.initState();
    if (_amount > 0) _amountCtrl.text = formatIQD(_amount.round());
  }

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

  Future<void> _submit() async {
    final p = widget.pot;
    if (_busy || _amount <= 0 || _amount > p.balance) return;
    setState(() => _busy = true);
    final r = await TransferPayApi.withdraw(via: p.via, name: p.name, amount: _amount, note: _noteCtrl.text, clientRef: _clientRef);
    if (!mounted) return;
    setState(() => _busy = false);
    final cur = 'common.currency'.tr();
    if (r.ok) {
      // الإشعار قبل الإغلاق (على الطبقة العليا) فيبقى بعده
      showSheetSnack(context, r.duplicate ? 'هذا السحب مسجَّلٌ من قبل — لم يُسحب مرّتين' : 'سُحب ${formatIQD(_amount.round())} $cur من ${p.label} إلى الصندوق');
      Navigator.of(context).pop(true);
      return;
    }
    if (r.unknown) {
      // قد يكون نُفّذ: الشيت يبقى بمفتاحه نفسه فالإعادة لا تسحب مرّتين
      showSheetSnack(context, 'لم نتأكّد من السحب — حدّث رصيد الحوالات وتأكّد، والإعادة من هنا لا تسحب مرّتين', isError: true);
      return;
    }
    showSheetSnack(context, r.message ?? 'تعذّر السحب — لم يُنفَّذ شيء', isError: true);
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final p = widget.pot;
    final cur = 'common.currency'.tr();
    final over = _amount > p.balance;
    final left = p.balance - _amount;
    final full = p.balance.floor();
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
                child: AmountTextField(
                  key: const ValueKey('transfer-withdraw-amount'),
                  controller: _amountCtrl,
                  currency: cur,
                  onValue: (v) => setState(() => _amount = v),
                ),
              ),
              const SizedBox(height: 9),
              Wrap(spacing: 7, runSpacing: 7, children: [
                SheetQuickChip(
                  key: const ValueKey('transfer-withdraw-full'),
                  label: 'كامل الرصيد',
                  icon: LucideIcons.checkCheck,
                  suggested: true,
                  selected: _amount == full,
                  onTap: () => _setAmount(full),
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
              key: const ValueKey('transfer-withdraw-note'),
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
        busy: _busy,
        enabled: _amount > 0 && !over && !_busy,
        onPressed: _submit,
      ),
    );
  }
}

/// إلغاء سحب (مرّةً واحدة): يرجع المبلغ لرصيد طريقته ويخرج من الصندوق. true = أُلغي.
Future<bool?> showTransferVoidSheet(BuildContext context, TransferWithdrawalData w) async {
  final cur = 'common.currency'.tr();
  final ok = await showConfirmSheet(
    context,
    title: 'إلغاء السحب',
    message: 'يرجع ${formatIQD(w.amount.abs().round())} $cur لرصيد «${w.label}» ويخرج من الصندوق. لا يُلغى السحب إلّا مرّةً واحدة.',
    confirmLabel: 'تأكيد الإلغاء',
    icon: LucideIcons.undo2,
    tone: AppTone.danger,
  );
  if (ok != true || !context.mounted) return false;
  final r = await TransferPayApi.voidWithdrawal(w.id);
  if (!context.mounted) return r.ok;
  if (r.ok) {
    showSheetSnack(context, r.duplicate ? 'هذا السحب ملغى من قبل' : 'أُلغي السحب — رجع ${formatIQD(w.amount.abs().round())} $cur لرصيد ${w.label}');
  } else if (r.unknown) {
    showSheetSnack(context, 'لم نتأكّد من الإلغاء — حدّث رصيد الحوالات وتأكّد قبل أن تعيده', isError: true);
  } else {
    showSheetSnack(context, r.message ?? 'تعذّر الإلغاء — لم يُنفَّذ شيء', isError: true);
  }
  return r.ok || r.unknown;
}
