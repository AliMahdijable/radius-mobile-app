import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../api/discounts_api.dart';
import '../../../core/util/format.dart';
import '../../../core/widgets/design_sheet.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';
import '../../../core/widgets/sheet_scaffold.dart';
import '../../../core/util/amount_input.dart';

Future<bool?> showEditDiscountSheet(BuildContext context, Discount d) {
  return showModalBottomSheet<bool>(
    barrierColor: AppColors.scrim,
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _EditDiscountSheet(discount: d),
  );
}

class _EditDiscountSheet extends StatefulWidget {
  const _EditDiscountSheet({required this.discount});
  final Discount discount;

  @override
  State<_EditDiscountSheet> createState() => _EditDiscountSheetState();
}

class _EditDiscountSheetState extends State<_EditDiscountSheet> {
  late final TextEditingController _amountCtrl;
  late int _amount;
  bool _submitting = false;
  bool _suppressFormat = false;

  @override
  void initState() {
    super.initState();
    _amount = widget.discount.discountAmount.toInt();
    _amountCtrl = TextEditingController(text: _amount > 0 ? _fmt(_amount) : '');
    _amountCtrl.addListener(_onAmount);
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    super.dispose();
  }

  void _onAmount() {
    if (_suppressFormat) return;
    final digits = _amountCtrl.text.replaceAll(RegExp(r'[^0-9]'), '');
    final parsed = int.tryParse(digits) ?? 0;
    final formatted = _fmt(parsed);
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

  static String _fmt(int v) {
    if (v == 0) return '';
    final s = v.toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return buf.toString();
  }

  Future<void> _submit() async {
    if (_submitting || _amount < 0) return;
    setState(() => _submitting = true);
    final r = await DiscountsApi.update(
      id: widget.discount.id,
      discountAmount: _amount,
    );
    if (!mounted) return;
    setState(() => _submitting = false);
    showSheetSnack(
        context, r.ok ? 'تم التعديل' : (r.message ?? 'تعذّر التعديل'),
        isError: (r.ok) ? false : true);
    if (r.ok) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final accent = AppColors.success;
    final d = widget.discount;
    return DesignSheet(
      header: SheetHeaderBar(
        icon: LucideIcons.tag,
        title: 'تعديل الخصم',
        subtitle: '',
        onClose: _submitting ? () {} : () => Navigator.of(context).pop(),
      ),
      footer: SheetFooterBar(
        label: _submitting ? 'جاري التعديل...' : 'حفظ التعديل',
        icon: LucideIcons.save,
        enabled: !_submitting && _amount >= 0,
        busy: _submitting,
        onPressed: _submit,
      ),
      scrollable: false,
      bodyPadding: EdgeInsets.zero,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Sp.xl, Sp.lg, Sp.xl, Sp.xxl),
        children: [
          if (d.packagePrice != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.surfaceInput,
                borderRadius: BorderRadius.circular(R.md),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  Icon(LucideIcons.tag, size: 13, color: AppColors.textMid),
                  const SizedBox(width: 6),
                  Text(
                    'السعر الأصلي ',
                    style: AppType.muted().copyWith(fontSize: 11),
                  ),
                  Text(
                    '${formatIQD(d.packagePrice!)} د.ع',
                    style: AppType.label(color: AppColors.textHi)
                        .copyWith(fontSize: 13, fontWeight: FontWeight.w700),
                  ),
                  const Spacer(),
                  if (_amount > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.brandSoftBg,
                        borderRadius: BorderRadius.circular(R.sm),
                        border: Border.all(
                            color: AppColors.brand.withValues(alpha: 0.3)),
                      ),
                      child: Text(
                        'بعد الخصم ${formatIQD((d.packagePrice! - _amount).clamp(0, double.infinity))}',
                        style: AppType.label(color: AppColors.brand).copyWith(
                            fontSize: 11, fontWeight: FontWeight.w700),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: Sp.md),
          ],
          Padding(
            padding: const EdgeInsets.only(bottom: 4, right: 2),
            child: Text(
              'قيمة الخصم *',
              style: AppType.muted(color: AppColors.textMid).copyWith(
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          AmountShorthandBox(
              controller: _amountCtrl,
              child: TextField(
                controller: _amountCtrl,
                keyboardType: TextInputType.number,
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
                ),
              )),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final v in const [1000, 2500, 5000, 10000])
                _quick(v, accent),
            ],
          ),
        ],
      ),
    );
  }

  Widget _quick(int v, Color accent) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          final next = _amount + v;
          final f = _fmt(next);
          _suppressFormat = true;
          _amountCtrl.value = TextEditingValue(
              text: f, selection: TextSelection.collapsed(offset: f.length));
          _suppressFormat = false;
          setState(() => _amount = next);
        },
        borderRadius: BorderRadius.circular(R.sm),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(R.sm),
            border: Border.all(color: accent.withValues(alpha: 0.3)),
          ),
          child: Text(
            '+${_fmt(v)}',
            style: TextStyle(
              color: accent,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}
