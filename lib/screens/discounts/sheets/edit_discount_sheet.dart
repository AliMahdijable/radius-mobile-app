import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../api/discounts_api.dart';
import '../../../core/util/format.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';
import '../../../core/widgets/sheet_scaffold.dart';

Future<bool?> showEditDiscountSheet(BuildContext context, Discount d) {
  return showModalBottomSheet<bool>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => SheetScaffold(child: _EditDiscountSheet(discount: d)),
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
    _amountCtrl = TextEditingController(
        text: _amount > 0 ? _fmt(_amount) : '');
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(r.ok
            ? 'تم التعديل'
            : (r.message ?? 'تعذّر التعديل')),
        backgroundColor: r.ok ? AppColors.brand : AppColors.error,
        behavior: SnackBarBehavior.floating,
      ),
    );
    if (r.ok) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    const accent = Color(0xFF14B8A6);
    final d = widget.discount;
    return DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize: 0.4,
      maxChildSize: 0.85,
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
              const SizedBox(height: 8),
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, 0),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(R.md),
                      ),
                      child: const Icon(LucideIcons.percent,
                          size: 16, color: accent),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'تعديل خصم',
                            style: AppType.title(color: AppColors.textHi)
                                .copyWith(fontSize: 15),
                          ),
                          Text(
                            d.subscriberUsername,
                            style: AppType.muted().copyWith(fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: _submitting
                          ? null
                          : () => Navigator.of(context).pop(),
                      icon: const Icon(LucideIcons.x, size: 16),
                      color: AppColors.textMid,
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  controller: controller,
                  padding: const EdgeInsets.fromLTRB(
                      Sp.lg, Sp.md, Sp.lg, Sp.huge),
                  children: [
                    if (d.packagePrice != null) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceInput,
                          borderRadius: BorderRadius.circular(R.md),
                          border:
                              Border.all(color: AppColors.border),
                        ),
                        child: Row(
                          children: [
                            Icon(LucideIcons.tag,
                                size: 13, color: AppColors.textMid),
                            const SizedBox(width: 6),
                            Text(
                              'السعر الأصلي ',
                              style:
                                  AppType.muted().copyWith(fontSize: 11),
                            ),
                            Text(
                              '${formatIQD(d.packagePrice!)} د.ع',
                              style: AppType.label(color: AppColors.textHi)
                                  .copyWith(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w800),
                            ),
                            const Spacer(),
                            if (_amount > 0)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: AppColors.brand
                                      .withValues(alpha: 0.1),
                                  borderRadius:
                                      BorderRadius.circular(R.sm),
                                  border: Border.all(
                                      color: AppColors.brand
                                          .withValues(alpha: 0.3)),
                                ),
                                child: Text(
                                  'بعد الخصم ${formatIQD((d.packagePrice! - _amount).clamp(0, double.infinity))}',
                                  style: AppType.label(
                                          color: AppColors.brand)
                                      .copyWith(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w800),
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
                        style:
                            AppType.muted(color: AppColors.textMid).copyWith(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    TextField(
                      controller: _amountCtrl,
                      keyboardType: TextInputType.number,
                      style: AppType.input(color: AppColors.textHi),
                      decoration: InputDecoration(
                        hintText: 'مثلاً 5,000',
                        hintStyle:
                            AppType.input(color: AppColors.textLow),
                        filled: true,
                        fillColor: AppColors.surface,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(R.sm),
                          borderSide: BorderSide(color: AppColors.border),
                        ),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 10),
                        suffixText: 'د.ع',
                      ),
                    ),
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
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                      Sp.lg, 0, Sp.lg, Sp.md),
                  child: SizedBox(
                    height: 50,
                    child: ElevatedButton.icon(
                      onPressed:
                          _submitting || _amount < 0 ? null : _submit,
                      icon: _submitting
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(LucideIcons.save, size: 16),
                      label: Text(
                        _submitting
                            ? 'جاري الحفظ...'
                            : (_amount == 0
                                ? 'إزالة الخصم'
                                : 'حفظ ${formatIQD(_amount)}'),
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 14),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                            _amount == 0 ? AppColors.error : accent,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(R.md),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
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
              text: f,
              selection: TextSelection.collapsed(offset: f.length));
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
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }
}
