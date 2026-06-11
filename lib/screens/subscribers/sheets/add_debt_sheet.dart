import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../api/subscribers_api.dart';
import '../../../core/util/format.dart';
import '../../../models/subscriber.dart';
import '../../../services/subscriber_events.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';

/// Bottom sheet for adding to a subscriber's debt — port of v1's
/// `_showAddDebtSheet` from mobile-app/lib/screens/subscribers/
/// subscriber_details_screen.dart. Layout:
///   1. Side-by-side info chips for current debt + current credit
///      (each only renders when non-zero; if both zero a single
///      'no balance' chip takes the row).
///   2. Amount field + thousands formatter.
///   3. Quick chips (5k / 10k / 15k / 25k / 35k / 50k) that ADD to
///      the field — matches v1 (tap 10k twice → 20k).
///   4. Optional comment that flows into the activity log.
///   5. Live 'الدين بعد الإضافة' preview showing the new debt total
///      with the old debt struck through.
///   6. Confirm dialog before submit — keeps admins from accidentally
///      saddling a subscriber.
///   7. Submit → /api/v2/subscribers/:idx/add-debt.
Future<bool?> showAddDebtSheet(BuildContext context, Subscriber sub) {
  return showModalBottomSheet<bool>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _AddDebtSheet(sub: sub),
  );
}

class _AddDebtSheet extends StatefulWidget {
  const _AddDebtSheet({required this.sub});
  final Subscriber sub;

  @override
  State<_AddDebtSheet> createState() => _AddDebtSheetState();
}

class _AddDebtSheetState extends State<_AddDebtSheet> {
  final _amountCtrl = TextEditingController();
  final _commentCtrl = TextEditingController();
  int _amount = 0;
  bool _submitting = false;
  bool _suppressFormat = false;

  late final double _currentBalance = widget.sub.balanceAmount;
  late final double _currentDebt =
      _currentBalance < 0 ? _currentBalance.abs() : 0.0;
  late final double _currentCredit =
      _currentBalance > 0 ? _currentBalance : 0.0;

  @override
  void initState() {
    super.initState();
    _amountCtrl.addListener(_onAmountChanged);
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _commentCtrl.dispose();
    super.dispose();
  }

  void _onAmountChanged() {
    if (_suppressFormat) return;
    final digits = _amountCtrl.text.replaceAll(RegExp(r'[^0-9]'), '');
    final parsed = int.tryParse(digits) ?? 0;
    final formatted = _formatThousands(parsed);
    if (formatted != _amountCtrl.text) {
      _suppressFormat = true;
      _amountCtrl.value = TextEditingValue(
        text: formatted,
        selection: TextSelection.collapsed(offset: formatted.length),
      );
      _suppressFormat = false;
    }
    if (parsed != _amount) setState(() => _amount = parsed);
  }

  void _addToAmount(int chip) {
    final next = _amount + chip;
    final formatted = _formatThousands(next);
    _suppressFormat = true;
    _amountCtrl.value = TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
    _suppressFormat = false;
    setState(() => _amount = next);
  }

  static String _formatThousands(int v) {
    if (v == 0) return '';
    final s = v.toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return buf.toString();
  }

  bool get _canSubmit =>
      !_submitting && widget.sub.idx != null && _amount > 0;

  Future<void> _confirmAndSubmit() async {
    final amount = _amount.toDouble();
    final newDebt = (_currentBalance - amount).abs();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'تأكيد إضافة الدين',
          style: AppType.label(color: AppColors.textHi)
              .copyWith(fontSize: 16, fontWeight: FontWeight.w800),
        ),
        content: Text(
          'سيتم إضافة ${formatIQD(amount.round())} د.ع كدين على '
          '"${widget.sub.fullName}".\n'
          'الدين الجديد: ${formatIQD(newDebt.round())} د.ع',
          style: AppType.subtitle(color: AppColors.textMid),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFE08F2D),
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('تأكيد'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _submit();
  }

  Future<void> _submit() async {
    final idx = widget.sub.idx;
    if (idx == null) return;
    setState(() => _submitting = true);
    final result = await SubscribersApi.addDebt(
      idx: idx,
      amount: _amount.toDouble(),
      comment: _commentCtrl.text.trim().isEmpty
          ? null
          : _commentCtrl.text.trim(),
    );
    if (!mounted) return;
    setState(() => _submitting = false);
    if (result.ok) SubscriberEvents.notifyChange();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result.ok
              ? 'تم إضافة الدين بنجاح'
              : (result.message ?? 'فشل إضافة الدين'),
        ),
        backgroundColor:
            result.ok ? const Color(0xFFE08F2D) : AppColors.error,
        behavior: SnackBarBehavior.floating,
      ),
    );
    if (result.ok) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    const accent = Color(0xFFE08F2D); // amber — debt addition
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, controller) {
        return Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius:
                BorderRadius.vertical(top: Radius.circular(R.xl)),
          ),
          child: Column(
            children: [
              _SheetHandle(),
              _SheetHeader(
                icon: LucideIcons.plus,
                title: 'إضافة دين',
                subtitle: widget.sub.fullName,
                color: accent,
                onClose: () => Navigator.of(context).pop(),
              ),
              Expanded(
                child: ListView(
                  controller: controller,
                  padding: const EdgeInsets.fromLTRB(
                      Sp.lg, Sp.sm, Sp.lg, Sp.huge),
                  children: _buildBody(accent),
                ),
              ),
              _SubmitBar(
                label: _submitting ? 'جاري الإضافة...' : 'إضافة دين',
                color: accent,
                icon: LucideIcons.plus,
                enabled: _canSubmit,
                busy: _submitting,
                onPressed: _confirmAndSubmit,
              ),
            ],
          ),
        );
      },
    );
  }

  List<Widget> _buildBody(Color accent) {
    final newBalance = _currentBalance - _amount.toDouble();
    return [
      _CurrentStatusRow(
        debt: _currentDebt,
        credit: _currentCredit,
      ),
      const SizedBox(height: Sp.md),
      _AmountField(
        controller: _amountCtrl,
        accent: accent,
        onClear: () {
          _suppressFormat = true;
          _amountCtrl.clear();
          _suppressFormat = false;
          setState(() => _amount = 0);
        },
        chips: const [5000, 10000, 15000, 25000, 35000, 50000],
        onChipTap: _addToAmount,
      ),
      const SizedBox(height: Sp.sm),
      _CommentField(controller: _commentCtrl),
      if (_amount > 0) ...[
        const SizedBox(height: Sp.md),
        _AfterCard(
          oldDebt: _currentDebt,
          newDebt: newBalance.abs(),
        ),
      ],
    ];
  }
}

class _CurrentStatusRow extends StatelessWidget {
  const _CurrentStatusRow({required this.debt, required this.credit});
  final double debt;
  final double credit;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    if (debt <= 0 && credit <= 0) {
      return _StatusChip(
        icon: LucideIcons.circleCheck,
        label: 'الرصيد',
        value: 'لا يوجد دين أو رصيد',
        color: AppColors.textMid,
      );
    }
    return Row(
      children: [
        if (debt > 0)
          Expanded(
            child: _StatusChip(
              icon: LucideIcons.trendingDown,
              label: 'الدين الحالي',
              value: '${formatIQD(debt.round())} د.ع',
              color: AppColors.error,
            ),
          ),
        if (debt > 0 && credit > 0) const SizedBox(width: 6),
        if (credit > 0)
          Expanded(
            child: _StatusChip(
              icon: LucideIcons.wallet,
              label: 'الرصيد الحالي',
              value: '${formatIQD(credit.round())} د.ع',
              color: AppColors.brand,
            ),
          ),
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(R.sm),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 13),
              const SizedBox(width: 5),
              Text(
                label,
                style: AppType.muted(color: AppColors.textMid).copyWith(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: AppType.label(color: color).copyWith(
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _AmountField extends StatelessWidget {
  const _AmountField({
    required this.controller,
    required this.accent,
    required this.onClear,
    required this.chips,
    required this.onChipTap,
  });
  final TextEditingController controller;
  final Color accent;
  final VoidCallback onClear;
  final List<int> chips;
  final ValueChanged<int> onChipTap;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    // مطلب 2026-06-10: no tinted outer container — TextField's own
    // OutlinedInputBorder is enough; the wrapping box was reading as
    // a double frame.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'قيمة الدين المضاف',
          style: AppType.label(color: AppColors.textHi).copyWith(
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
          const SizedBox(height: 4),
          TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            style: AppType.input(color: AppColors.textHi),
            decoration: InputDecoration(
              hintText: 'مثلاً 10,000',
              hintStyle: AppType.input(color: AppColors.textLow),
              filled: true,
              fillColor: AppColors.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(R.sm),
                borderSide: BorderSide(
                    color: AppColors.border.withValues(alpha: 0.5)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(R.sm),
                borderSide: BorderSide(
                    color: AppColors.border.withValues(alpha: 0.5)),
              ),
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              suffixText: 'د.ع',
              suffixIcon: controller.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(LucideIcons.x, size: 16),
                      onPressed: onClear,
                      visualDensity: VisualDensity.compact,
                    )
                  : null,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final amount in chips)
                InkWell(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    onChipTap(amount);
                  },
                  borderRadius: BorderRadius.circular(R.pill),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(R.pill),
                      border: Border.all(
                        color: accent.withValues(alpha: 0.25),
                      ),
                    ),
                    child: Text(
                      formatIQD(amount),
                      style: AppType.muted(color: accent)
                          .copyWith(fontSize: 11, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
            ],
          ),
        ],
    );
  }
}

class _CommentField extends StatelessWidget {
  const _CommentField({required this.controller});
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return TextField(
      controller: controller,
      maxLines: 2,
      style: AppType.input(color: AppColors.textHi),
      decoration: InputDecoration(
        hintText: 'سبب إضافة الدين (اختياري)',
        hintStyle: AppType.input(color: AppColors.textLow),
        filled: true,
        fillColor: AppColors.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(R.sm),
          borderSide: BorderSide(
              color: AppColors.border.withValues(alpha: 0.5)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(R.sm),
          borderSide: BorderSide(
              color: AppColors.border.withValues(alpha: 0.5)),
        ),
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        prefixIcon: Padding(
          padding: EdgeInsets.only(left: 8, right: 4, bottom: 16),
          child:
              Icon(LucideIcons.fileText, size: 16, color: AppColors.textMid),
        ),
        prefixIconConstraints:
            const BoxConstraints(minWidth: 28, minHeight: 28),
      ),
    );
  }
}

class _AfterCard extends StatelessWidget {
  const _AfterCard({required this.oldDebt, required this.newDebt});
  final double oldDebt;
  final double newDebt;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(R.sm),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.triangleAlert, color: AppColors.error, size: 14),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'الدين بعد الإضافة',
                  style: AppType.muted(color: AppColors.textMid).copyWith(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    if (oldDebt > 0) ...[
                      Text(
                        '${formatIQD(oldDebt.round())} د.ع',
                        style: AppType.muted(color: AppColors.textLow)
                            .copyWith(
                          fontSize: 11,
                          decoration: TextDecoration.lineThrough,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        LucideIcons.arrowLeft,
                        size: 12,
                        color: AppColors.error,
                      ),
                      const SizedBox(width: 4),
                    ],
                    Text(
                      '${formatIQD(newDebt.round())} د.ع',
                      style: AppType.label(color: AppColors.error).copyWith(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ───────── shared sheet chrome (copy of activate_sheet's) ─────────

class _SheetHandle extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 6),
        child: Container(
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: AppColors.border,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      );
}

class _SheetHeader extends StatelessWidget {
  const _SheetHeader({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onClose,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Container(
      padding: const EdgeInsets.fromLTRB(Sp.lg, 4, Sp.sm, Sp.md),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(R.sm),
            ),
            child: Icon(icon, color: color, size: 16),
          ),
          const SizedBox(width: Sp.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title,
                    style: AppType.label(color: AppColors.textHi).copyWith(
                        fontSize: 14, fontWeight: FontWeight.w800)),
                const SizedBox(height: 1),
                Text(subtitle,
                    style: AppType.muted(color: AppColors.textMid).copyWith(
                        fontSize: 11, fontWeight: FontWeight.w500),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(LucideIcons.x, size: 20),
            color: AppColors.textMid,
            visualDensity: VisualDensity.compact,
            onPressed: onClose,
          ),
        ],
      ),
    );
  }
}

class _SubmitBar extends StatelessWidget {
  const _SubmitBar({
    required this.label,
    required this.color,
    required this.icon,
    required this.enabled,
    required this.busy,
    required this.onPressed,
  });
  final String label;
  final Color color;
  final IconData icon;
  final bool enabled;
  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.sm, Sp.lg, Sp.md),
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        child: SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: color,
              disabledBackgroundColor: color.withValues(alpha: 0.35),
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(R.md),
              ),
            ),
            onPressed: enabled ? onPressed : null,
            icon: busy
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Icon(icon, size: 16),
            label: Text(label,
                style: const TextStyle(
                    fontWeight: FontWeight.w800, fontSize: 14)),
          ),
        ),
      ),
    );
  }
}
