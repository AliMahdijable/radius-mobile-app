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

/// Bottom sheet for paying down a subscriber's debt — port of v1's
/// `_showPayDebtSheet` from mobile-app/lib/screens/subscribers/
/// subscriber_details_screen.dart. Layout:
///   1. Current-debt hero box with a progress bar that fills as the
///      amount field grows (so the admin sees how close they are to
///      clearing the debt at a glance).
///   2. Amount field + thousands formatter.
///   3. Quick chips (5k / 10k / 15k / 25k / 50k) filtered to < debt.
///      Chips ADD to the field (tap 25k twice → 50k) — matches v1.
///   4. 'تسديد كامل الدين' toggle that locks the field to debtAbs.
///   5. Optional notes — appended to the activity log + receipt.
///   6. Live 'بعد التسديد' preview row.
///   7. Submit → /api/v2/subscribers/:idx/pay-debt.
///
/// Returns true on success so the caller can refresh local state.
Future<bool?> showPayDebtSheet(BuildContext context, Subscriber sub) {
  return showModalBottomSheet<bool>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _PayDebtSheet(sub: sub),
  );
}

class _PayDebtSheet extends StatefulWidget {
  const _PayDebtSheet({required this.sub});
  final Subscriber sub;

  @override
  State<_PayDebtSheet> createState() => _PayDebtSheetState();
}

class _PayDebtSheetState extends State<_PayDebtSheet> {
  final _amountCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  int _amount = 0;
  bool _payAll = false;
  bool _submitting = false;
  bool _suppressFormat = false;

  late final double _currentDebt = widget.sub.debtAbs;
  // Signed current balance (negative=debt, positive=credit). The live
  // preview adds the payment to it so the displayed "after" reflects
  // whether the balance flips to a credit.
  late final double _currentBalance = widget.sub.balanceAmount;

  @override
  void initState() {
    super.initState();
    _amountCtrl.addListener(_onAmountChanged);
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _notesCtrl.dispose();
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

  void _togglePayAll() {
    setState(() {
      _payAll = !_payAll;
      if (_payAll) {
        final whole = _currentDebt.round();
        final formatted = _formatThousands(whole);
        _suppressFormat = true;
        _amountCtrl.value = TextEditingValue(
          text: formatted,
          selection: TextSelection.collapsed(offset: formatted.length),
        );
        _suppressFormat = false;
        _amount = whole;
      } else {
        _suppressFormat = true;
        _amountCtrl.clear();
        _suppressFormat = false;
        _amount = 0;
      }
    });
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

  double get _effectiveAmount =>
      _payAll ? _currentDebt : _amount.toDouble();

  bool get _canSubmit {
    if (_submitting) return false;
    if (widget.sub.idx == null) return false;
    if (_currentDebt <= 0) return false;
    return _effectiveAmount > 0;
  }

  Future<void> _submit() async {
    final idx = widget.sub.idx;
    if (idx == null) return;
    setState(() => _submitting = true);
    final result = await SubscribersApi.payDebt(
      idx: idx,
      amount: _effectiveAmount,
      comment: _notesCtrl.text.trim().isEmpty
          ? null
          : _notesCtrl.text.trim(),
    );
    if (!mounted) return;
    setState(() => _submitting = false);
    if (result.ok) SubscriberEvents.notifyChange();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result.ok ? 'تم التسديد بنجاح' : (result.message ?? 'فشل التسديد'),
        ),
        backgroundColor:
            result.ok ? const Color(0xFF14B8A6) : AppColors.error,
        behavior: SnackBarBehavior.floating,
      ),
    );
    if (result.ok) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFF14B8A6); // teal — pay/credit
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, controller) {
        return Container(
          decoration: const BoxDecoration(
            color: AppColors.surface,
            borderRadius:
                BorderRadius.vertical(top: Radius.circular(R.xl)),
          ),
          child: Column(
            children: [
              _SheetHandle(),
              _SheetHeader(
                icon: LucideIcons.banknote,
                title: 'تسديد دين',
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
                label: _submitting ? 'جاري التسديد...' : 'تسديد الآن',
                color: accent,
                icon: LucideIcons.banknote,
                enabled: _canSubmit,
                busy: _submitting,
                onPressed: _submit,
              ),
            ],
          ),
        );
      },
    );
  }

  List<Widget> _buildBody(Color accent) {
    if (_currentDebt <= 0) {
      return const [
        Padding(
          padding: EdgeInsets.symmetric(vertical: Sp.huge),
          child: Center(
            child: Text(
              'لا يوجد دين على هذا المشترك',
              style: TextStyle(
                color: AppColors.textMid,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ];
    }
    final payRatio = _currentDebt > 0
        ? (_effectiveAmount / _currentDebt).clamp(0.0, 1.0)
        : 0.0;
    final livePreview = _currentBalance + _effectiveAmount;
    final chips = const [5000, 10000, 15000, 25000, 50000]
        .where((c) => c < _currentDebt)
        .toList();

    return [
      _DebtHeroCard(
        debt: _currentDebt,
        payRatio: payRatio,
        showRatio: _effectiveAmount > 0,
      ),
      const SizedBox(height: Sp.md),
      _AmountField(
        controller: _amountCtrl,
        enabled: !_payAll,
        accent: accent,
        onClear: () {
          _suppressFormat = true;
          _amountCtrl.clear();
          _suppressFormat = false;
          setState(() => _amount = 0);
        },
        chips: chips,
        onChipTap: _addToAmount,
        chipsEnabled: !_payAll,
        chipsHidden: chips.isEmpty,
      ),
      const SizedBox(height: Sp.sm),
      _PayAllToggle(
        value: _payAll,
        debt: _currentDebt,
        onTap: _togglePayAll,
      ),
      const SizedBox(height: Sp.sm),
      _NotesField(controller: _notesCtrl),
      if (_effectiveAmount > 0) ...[
        const SizedBox(height: Sp.md),
        _AfterCard(balanceAfter: livePreview),
      ],
    ];
  }
}

class _DebtHeroCard extends StatelessWidget {
  const _DebtHeroCard({
    required this.debt,
    required this.payRatio,
    required this.showRatio,
  });
  final double debt;
  final double payRatio;
  final bool showRatio;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(R.lg),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.18)),
      ),
      child: Column(
        children: [
          Text(
            'الدين الحالي',
            style: AppType.muted(color: AppColors.textMid).copyWith(
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${formatIQD(debt.round())} د.ع',
            style: AppType.title(color: AppColors.error).copyWith(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            ),
          ),
          if (showRatio) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(R.pill),
              child: LinearProgressIndicator(
                value: payRatio,
                minHeight: 6,
                backgroundColor: AppColors.error.withValues(alpha: 0.15),
                valueColor:
                    const AlwaysStoppedAnimation(Color(0xFF14B8A6)),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${(payRatio * 100).toStringAsFixed(0)}% من الدين',
              style: AppType.muted(color: AppColors.textMid).copyWith(
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _AmountField extends StatelessWidget {
  const _AmountField({
    required this.controller,
    required this.enabled,
    required this.accent,
    required this.onClear,
    required this.chips,
    required this.onChipTap,
    required this.chipsEnabled,
    required this.chipsHidden,
  });
  final TextEditingController controller;
  final bool enabled;
  final Color accent;
  final VoidCallback onClear;
  final List<int> chips;
  final ValueChanged<int> onChipTap;
  final bool chipsEnabled;
  final bool chipsHidden;

  @override
  Widget build(BuildContext context) {
    // No tinted outer container — مطلب 2026-06-10: 'تكدر تلغي او
    // تخفيف تاطير التيكست بوكس لان صاير حددود قوية'. The TextField
    // keeps its single OutlinedInputBorder so the field still reads
    // as a field but the wrapping box no longer doubles the frame.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'المبلغ المسدد',
          style: AppType.label(color: AppColors.textHi).copyWith(
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
          TextField(
            controller: controller,
            enabled: enabled,
            keyboardType: TextInputType.number,
            style: AppType.input(color: AppColors.textHi),
            decoration: InputDecoration(
              hintText: 'مثلاً 10,000',
              hintStyle: AppType.input(color: AppColors.textLow),
              filled: true,
              fillColor: AppColors.surface,
              // Softer border so the field doesn't read as a stark
              // black frame against the white sheet (مطلب 2026-06-10).
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
              suffixIcon: enabled && controller.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(LucideIcons.x, size: 16),
                      onPressed: onClear,
                      visualDensity: VisualDensity.compact,
                    )
                  : null,
            ),
          ),
          if (!chipsHidden) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final amount in chips)
                  InkWell(
                    onTap: chipsEnabled ? () => onChipTap(amount) : null,
                    borderRadius: BorderRadius.circular(R.pill),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: accent.withValues(
                            alpha: chipsEnabled ? 0.12 : 0.06),
                        borderRadius: BorderRadius.circular(R.pill),
                        border: Border.all(
                          color: accent.withValues(
                              alpha: chipsEnabled ? 0.25 : 0.12),
                        ),
                      ),
                      child: Text(
                        formatIQD(amount),
                        style: AppType.muted(
                          color: chipsEnabled
                              ? accent
                              : AppColors.textLow,
                        ).copyWith(
                            fontSize: 11, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
    );
  }
}

class _PayAllToggle extends StatelessWidget {
  const _PayAllToggle({
    required this.value,
    required this.debt,
    required this.onTap,
  });
  final bool value;
  final double debt;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const teal = Color(0xFF14B8A6);
    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      borderRadius: BorderRadius.circular(R.sm),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: value
              ? teal.withValues(alpha: 0.08)
              : AppColors.surface,
          borderRadius: BorderRadius.circular(R.sm),
          border: Border.all(
            color: value
                ? teal.withValues(alpha: 0.3)
                : AppColors.border.withValues(alpha: 0.5),
          ),
        ),
        child: Row(
          children: [
            Icon(
              value ? LucideIcons.squareCheck : LucideIcons.square,
              color: value ? teal : AppColors.textMid,
              size: 18,
            ),
            const SizedBox(width: 8),
            Text(
              'تسديد كامل الدين',
              style: AppType.label(color: AppColors.textHi).copyWith(
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            const Spacer(),
            if (value)
              Text(
                '${formatIQD(debt.round())} د.ع',
                style: AppType.label(color: teal).copyWith(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _NotesField extends StatelessWidget {
  const _NotesField({required this.controller});
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      maxLines: 2,
      style: AppType.input(color: AppColors.textHi),
      decoration: InputDecoration(
        hintText: 'ملاحظات (اختياري)',
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
        prefixIcon: const Padding(
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
  const _AfterCard({required this.balanceAfter});
  final double balanceAfter;

  @override
  Widget build(BuildContext context) {
    final isCredit = balanceAfter >= 0;
    final color =
        isCredit ? const Color(0xFF14B8A6) : const Color(0xFFE08F2D);
    final label = isCredit ? 'بعد التسديد' : 'الدين المتبقي';
    final prefix = isCredit ? 'رصيد ' : '';
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(R.sm),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Row(
        children: [
          Icon(
            isCredit ? LucideIcons.circleCheck : LucideIcons.timer,
            color: color,
            size: 14,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: AppType.label(color: AppColors.textHi).copyWith(
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          const Spacer(),
          if (prefix.isNotEmpty)
            Text(
              prefix,
              style: AppType.muted(color: color).copyWith(
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          Text(
            '${formatIQD(balanceAfter.abs().round())} د.ع',
            style: AppType.label(color: color).copyWith(
              fontSize: 13,
              fontWeight: FontWeight.w800,
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
