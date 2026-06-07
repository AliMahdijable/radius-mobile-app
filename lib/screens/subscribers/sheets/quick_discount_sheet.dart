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

/// Bottom sheet for setting/removing a subscriber's package discount —
/// port of v1's `_showQuickDiscountSheet`. Layout:
///   1. Original price + current discount row pulled from
///      /api/v2/subscribers/:idx/activation-data (falls back to
///      sub.price + sub.discount if the call fails).
///   2. Amount field pre-populated with the current discount (so the
///      admin sees what's already set and can edit it in place).
///   3. Quick chips (1k / 2.5k / 5k / 10k / 15k / 20k) that REPLACE
///      the field — not accumulate (matches v1 — a discount preset
///      is a whole value, not a delta).
///   4. Live preview of the post-discount price with the original
///      price struck through.
///   5. Warning when amount >= price (final price would be zero).
///   6. Submit → /api/v2/subscribers/:idx/discount with `{amount}`.
///      amount=0 removes the discount; the submit button flips to
///      a red 'حذف الخصم' when the field is cleared on a sub that
///      already has a discount set.
Future<bool?> showQuickDiscountSheet(BuildContext context, Subscriber sub) {
  return showModalBottomSheet<bool>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _QuickDiscountSheet(sub: sub),
  );
}

class _QuickDiscountSheet extends StatefulWidget {
  const _QuickDiscountSheet({required this.sub});
  final Subscriber sub;

  @override
  State<_QuickDiscountSheet> createState() => _QuickDiscountSheetState();
}

class _QuickDiscountSheetState extends State<_QuickDiscountSheet> {
  final _amountCtrl = TextEditingController();
  int _amount = 0;
  bool _loading = true;
  bool _submitting = false;
  bool _suppressFormat = false;

  double _originalPrice = 0;
  double _currentDiscount = 0;

  @override
  void initState() {
    super.initState();
    _amountCtrl.addListener(_onAmountChanged);
    _load();
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    // Seed from the in-memory subscriber so the sheet has *something*
    // to render immediately while we wait for the activation-data
    // round-trip to refine the numbers.
    _originalPrice = (widget.sub.price ?? 0).toDouble();
    _currentDiscount = widget.sub.discount ?? 0;

    final idx = widget.sub.idx;
    if (idx != null) {
      final data = await SubscribersApi.fetchActivationData(idx);
      if (data != null) {
        num readNum(String key) {
          final v = data[key];
          if (v == null) return 0;
          if (v is num) return v;
          return num.tryParse(v.toString().replaceAll(',', '')) ?? 0;
        }

        final p = readNum('user_price');
        if (p > 0) _originalPrice = p.toDouble();
        final d = readNum('discount_amount');
        if (d > 0) _currentDiscount = d.toDouble();
      }
    }

    if (!mounted) return;
    // Pre-populate amount with the existing discount so the sheet
    // shows what's already in place.
    if (_currentDiscount > 0) {
      final whole = _currentDiscount.round();
      final formatted = _formatThousands(whole);
      _suppressFormat = true;
      _amountCtrl.value = TextEditingValue(
        text: formatted,
        selection: TextSelection.collapsed(offset: formatted.length),
      );
      _suppressFormat = false;
      _amount = whole;
    }
    setState(() => _loading = false);
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

  /// Chip REPLACES (not adds) — a discount preset is a full value, not
  /// a delta. Mirrors v1 behaviour.
  void _setAmount(int chip) {
    final formatted = _formatThousands(chip);
    _suppressFormat = true;
    _amountCtrl.value = TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
    _suppressFormat = false;
    setState(() => _amount = chip);
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

  /// True when the sub already has a discount and the admin cleared
  /// the field to remove it.
  bool get _isRemoval => _currentDiscount > 0 && _amount == 0;

  bool get _canSubmit {
    if (_loading || _submitting) return false;
    if (widget.sub.idx == null) return false;
    if (_isRemoval) return true; // remove the existing discount
    if (_amount > 0) return true;
    return false;
  }

  Future<void> _submit() async {
    final idx = widget.sub.idx;
    if (idx == null) return;
    setState(() => _submitting = true);
    final result = await SubscribersApi.setDiscount(
      idx: idx,
      amount: _amount.toDouble(),
    );
    if (!mounted) return;
    setState(() => _submitting = false);
    if (result.ok) SubscriberEvents.notifyChange();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result.ok
              ? (_isRemoval
                  ? 'تم حذف الخصم'
                  : (_amount > 0
                      ? 'تم حفظ خصم ${formatIQD(_amount)} د.ع'
                      : 'تم الحفظ'))
              : (result.message ?? 'فشل حفظ الخصم'),
        ),
        backgroundColor: result.ok
            ? (_isRemoval ? AppColors.error : const Color(0xFF14B8A6))
            : AppColors.error,
        behavior: SnackBarBehavior.floating,
      ),
    );
    if (result.ok) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final accent =
        _isRemoval ? AppColors.error : const Color(0xFF14B8A6);
    return DraggableScrollableSheet(
      initialChildSize: 0.8,
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
                icon: LucideIcons.tag,
                title: 'خصم سريع',
                subtitle: widget.sub.fullName,
                color: const Color(0xFF14B8A6),
                onClose: () => Navigator.of(context).pop(),
              ),
              Expanded(
                child: ListView(
                  controller: controller,
                  padding: const EdgeInsets.fromLTRB(
                      Sp.lg, Sp.sm, Sp.lg, Sp.huge),
                  children: _buildBody(),
                ),
              ),
              _SubmitBar(
                label: _submitting
                    ? 'جارٍ الحفظ...'
                    : (_isRemoval
                        ? 'حذف الخصم'
                        : (_amount > 0 ? 'حفظ الخصم' : 'حفظ')),
                color: accent,
                icon: _isRemoval ? LucideIcons.trash2 : LucideIcons.tag,
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

  List<Widget> _buildBody() {
    if (_loading) {
      return const [
        Padding(
          padding: EdgeInsets.symmetric(vertical: Sp.huge),
          child: Center(
            child: CircularProgressIndicator(color: Color(0xFF14B8A6)),
          ),
        ),
      ];
    }
    final finalPrice = _originalPrice > 0
        ? (_originalPrice - _amount).clamp(0.0, double.infinity)
        : 0.0;
    final overshoot =
        _amount > 0 && _originalPrice > 0 && _amount >= _originalPrice;
    return [
      _PriceBox(
        originalPrice: _originalPrice,
        currentDiscount: _currentDiscount,
      ),
      const SizedBox(height: Sp.md),
      _AmountField(
        controller: _amountCtrl,
        accent: const Color(0xFF14B8A6),
        onClear: () {
          _suppressFormat = true;
          _amountCtrl.clear();
          _suppressFormat = false;
          setState(() => _amount = 0);
        },
        chips: const [1000, 2500, 5000, 10000, 15000, 20000],
        onChipTap: _setAmount,
      ),
      if (_originalPrice > 0) ...[
        const SizedBox(height: Sp.md),
        _FinalPriceCard(
          originalPrice: _originalPrice,
          discount: _amount.toDouble(),
          finalPrice: finalPrice,
        ),
      ],
      if (overshoot) ...[
        const SizedBox(height: Sp.sm),
        Row(
          children: [
            const Icon(LucideIcons.triangleAlert,
                size: 14, color: Color(0xFFE08F2D)),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'الخصم يساوي أو يتجاوز السعر — السعر النهائي صفر',
                style: AppType.muted(color: const Color(0xFFE08F2D))
                    .copyWith(
                        fontSize: 11, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ],
    ];
  }
}

class _PriceBox extends StatelessWidget {
  const _PriceBox({
    required this.originalPrice,
    required this.currentDiscount,
  });
  final double originalPrice;
  final double currentDiscount;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.sm),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(LucideIcons.tag, color: AppColors.textMid, size: 13),
              const SizedBox(width: 6),
              Text(
                'السعر الأصلي',
                style: AppType.muted(color: AppColors.textMid).copyWith(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                originalPrice > 0
                    ? '${formatIQD(originalPrice.round())} د.ع'
                    : '—',
                style: AppType.label(color: AppColors.textHi).copyWith(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          if (currentDiscount > 0) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(LucideIcons.percent,
                    color: const Color(0xFF14B8A6), size: 13),
                const SizedBox(width: 6),
                Text(
                  'الخصم الحالي',
                  style: AppType.muted(color: AppColors.textMid).copyWith(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Text(
                  '-${formatIQD(currentDiscount.round())} د.ع',
                  style: AppType.label(color: const Color(0xFF14B8A6))
                      .copyWith(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
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
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(R.sm),
        border: Border.all(color: accent.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'قيمة الخصم (0 = إلغاء)',
            style: AppType.label(color: AppColors.textHi).copyWith(
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            autofocus: true,
            style: AppType.input(color: AppColors.textHi),
            decoration: InputDecoration(
              hintText: 'مثلاً 5,000',
              hintStyle: AppType.input(color: AppColors.textLow),
              filled: true,
              fillColor: AppColors.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(R.sm),
                borderSide: BorderSide(color: AppColors.border),
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
                      style: AppType.muted(color: accent).copyWith(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FinalPriceCard extends StatelessWidget {
  const _FinalPriceCard({
    required this.originalPrice,
    required this.discount,
    required this.finalPrice,
  });
  final double originalPrice;
  final double discount;
  final double finalPrice;

  @override
  Widget build(BuildContext context) {
    final hasDiscount = discount > 0 && discount < originalPrice;
    final color = discount > 0 ? const Color(0xFF14B8A6) : AppColors.textHi;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: discount > 0
            ? const Color(0xFF14B8A6).withValues(alpha: 0.07)
            : AppColors.surface,
        borderRadius: BorderRadius.circular(R.sm),
        border: Border.all(
          color: discount > 0
              ? const Color(0xFF14B8A6).withValues(alpha: 0.25)
              : AppColors.border,
        ),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.arrowRight, color: color, size: 14),
          const SizedBox(width: 6),
          Text(
            'السعر بعد الخصم',
            style: AppType.label(color: AppColors.textHi).copyWith(
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          const Spacer(),
          if (hasDiscount) ...[
            Text(
              '${formatIQD(originalPrice.round())} د.ع',
              style: AppType.muted(color: AppColors.textLow).copyWith(
                fontSize: 11,
                decoration: TextDecoration.lineThrough,
              ),
            ),
            const SizedBox(width: 6),
          ],
          Text(
            '${formatIQD(finalPrice.round())} د.ع',
            style: AppType.label(color: color).copyWith(
              fontSize: 14,
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
