import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../api/subscribers_api.dart';
import '../../../core/util/format.dart';
import '../../../core/widgets/design_sheet.dart';
import '../../../models/subscriber.dart';
import '../../../services/subscriber_events.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';
import '../../../core/widgets/sheet_scaffold.dart';

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
    barrierColor: AppColors.scrim,
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
    showSheetSnack(
      context,
      result.ok
          ? (_isRemoval
              ? 'تم حذف الخصم'
              : (_amount > 0
                  ? 'تم حفظ خصم ${formatIQD(_amount)} د.ع'
                  : 'تم الحفظ'))
          : (result.message ?? 'فشل حفظ الخصم'),
      isError: !result.ok,
    );
    if (result.ok) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    // الحذف يصبغ الزرّ أحمر؛ ما عداه أخضر accent كما في المخطّط.
    final accent = _isRemoval ? AppColors.error : AppColors.brandAccent;
    final finalPrice = _originalPrice > 0
        ? (_originalPrice - _amount).clamp(0.0, double.infinity)
        : 0.0;
    final overshoot =
        _amount > 0 && _originalPrice > 0 && _amount >= _originalPrice;
    return DesignSheet(
      header: SheetHeaderBar(
        icon: LucideIcons.tag,
        title: 'خصم سريع',
        subtitle: widget.sub.fullName,
        tint: AppColors.brandAccent,
        onClose: () => Navigator.of(context).pop(),
      ),
      footer: SheetFooterBar(
        label: _submitting
            ? 'جارٍ الحفظ...'
            : (_isRemoval ? 'حذف الخصم' : (_amount > 0 ? 'حفظ الخصم' : 'حفظ')),
        icon: _isRemoval ? LucideIcons.trash2 : LucideIcons.tag,
        color: accent,
        enabled: _canSubmit,
        busy: _submitting,
        onPressed: _submit,
      ),
      body: _loading
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: Sp.mega),
              child: Center(
                child: CircularProgressIndicator(
                    color: AppColors.brandAccent, strokeWidth: 2.5),
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SheetSummaryBox(
                  label: 'السعر الأصلي',
                  value: '${formatIQD(_originalPrice.round())} د.ع',
                ),
                if (_currentDiscount > 0) ...[
                  const SizedBox(height: Sp.sm),
                  SheetSummaryBox(
                    label: 'الخصم الحالي',
                    value: '${formatIQD(_currentDiscount.round())} د.ع',
                    valueColor: AppColors.brandAccent,
                  ),
                ],
                const SizedBox(height: Sp.lg),
                SheetSection(
                  label: 'قيمة الخصم',
                  hint: '0 = إلغاء الخصم',
                  gap: 9,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SheetBox(
                        focused: _amount > 0,
                        radius: 18,
                        padding: const EdgeInsets.symmetric(
                            horizontal: Sp.lg, vertical: 14),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _amountCtrl,
                                keyboardType: TextInputType.number,
                                inputFormatters: [
                                  FilteringTextInputFormatter.allow(
                                      RegExp(r'[0-9,]')),
                                ],
                                textDirection: ui.TextDirection.ltr,
                                textAlign: TextAlign.right,
                                style: AppType.amount(),
                                decoration: InputDecoration(
                                  isDense: true,
                                  border: InputBorder.none,
                                  contentPadding: EdgeInsets.zero,
                                  hintText: '0',
                                  hintStyle: AppType.amount(
                                      color: AppColors.textPlaceholder),
                                ),
                              ),
                            ),
                            const SizedBox(width: Sp.sm),
                            Text('د.ع',
                                style: AppType.input(color: AppColors.textLabel)
                                    .copyWith(fontSize: 13)),
                            if (_amount > 0) ...[
                              const SizedBox(width: Sp.sm),
                              InkWell(
                                onTap: () {
                                  _suppressFormat = true;
                                  _amountCtrl.clear();
                                  _suppressFormat = false;
                                  setState(() => _amount = 0);
                                },
                                borderRadius: BorderRadius.circular(R.pill),
                                child: Icon(LucideIcons.x,
                                    size: 16, color: AppColors.textHint),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 9),
                      // شرائح الخصم **تضبط** لا تُضيف (خلافاً لشيت الدين)
                      // — الخصم قيمة نهائيّة لا تراكميّة. سلوك v1.
                      Wrap(
                        spacing: 7,
                        runSpacing: 7,
                        children: [
                          for (final c in _chipScale)
                            SheetQuickChip(
                              label: _formatThousands(c),
                              selected: _amount == c,
                              onTap: () => _setAmount(c),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (_originalPrice > 0) ...[
                  const SizedBox(height: Sp.lg),
                  SheetBrandResultCard(
                    label: 'السعر بعد الخصم',
                    strikethrough:
                        _amount > 0 ? formatIQD(_originalPrice.round()) : null,
                    value: '${formatIQD(finalPrice.round())} د.ع',
                  ),
                ],
                if (overshoot) ...[
                  const SizedBox(height: Sp.md),
                  SheetResultBanner(
                    icon: LucideIcons.triangleAlert,
                    label: 'الخصم يساوي السعر أو يتجاوزه',
                    value: 'السعر النهائي 0',
                    tone: SheetTone.warning,
                  ),
                ],
              ],
            ),
    );
  }

  static const _chipScale = [1000, 2500, 5000, 10000, 15000, 20000];
}
