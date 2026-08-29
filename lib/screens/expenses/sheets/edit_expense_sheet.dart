import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../api/expenses_api.dart';
import '../../../core/util/format.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';
import '../../../core/widgets/sheet_scaffold.dart';

/// تعديل صرفية قائمة. الـsheet مطابق visually للـadd لكن:
///  • Title 'تعديل صرفية'
///  • الحقول pre-filled من ExpenseRow
///  • Submit يستدعي PUT /api/admin/expenses/:id
///
/// يرجع true عند الحفظ الناجح فالـcaller يعيد تحميل القائمة.
Future<bool?> showEditExpenseSheet(BuildContext context, ExpenseRow row) {
  return showModalBottomSheet<bool>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _EditExpenseSheet(row: row),
  );
}

class _EditExpenseSheet extends StatefulWidget {
  const _EditExpenseSheet({required this.row});
  final ExpenseRow row;

  @override
  State<_EditExpenseSheet> createState() => _EditExpenseSheetState();
}

class _EditExpenseSheetState extends State<_EditExpenseSheet> {
  late final TextEditingController _amountCtrl;
  late final TextEditingController _noteCtrl;
  late int _amount;
  late DateTime _date;
  bool _submitting = false;
  bool _suppressFormat = false;

  @override
  void initState() {
    super.initState();
    _amount = widget.row.amount.toInt();
    _amountCtrl = TextEditingController(
        text: _amount > 0 ? _formatThousands(_amount) : '');
    _noteCtrl = TextEditingController(text: widget.row.note ?? '');
    _date = _parseDate(widget.row.expenseDate) ?? DateTime.now();
    _amountCtrl.addListener(_onAmountChanged);
  }

  static DateTime? _parseDate(String s) {
    if (s.length < 10) return null;
    return DateTime.tryParse(s.substring(0, 10));
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _noteCtrl.dispose();
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

  Future<void> _submit() async {
    if (_submitting) return;
    if (_amount <= 0) {
      showSheetSnack(context, 'أدخل المبلغ', isError: true);
      return;
    }
    setState(() => _submitting = true);
    String two(int n) => n.toString().padLeft(2, '0');
    final dateStr = '${_date.year}-${two(_date.month)}-${two(_date.day)}';
    final result = await ExpensesApi.update(
      id: widget.row.id,
      amount: _amount,
      note: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
      expenseDate: dateStr,
    );
    if (!mounted) return;
    setState(() => _submitting = false);
    showSheetSnack(
        context, result.ok ? 'تم التعديل' : (result.message ?? 'تعذّر التعديل'),
        isError: (result.ok) ? false : true);
    if (result.ok) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final accent = AppColors.brandAccent;
    String two(int n) => n.toString().padLeft(2, '0');
    final dateLabel = '${_date.year}/${two(_date.month)}/${two(_date.day)}';
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, controller) {
        return Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(R.xl)),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 8),
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
                      child:
                          Icon(LucideIcons.fileEdit, size: 16, color: accent),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'تعديل صرفية',
                            style: AppType.title(color: AppColors.textHi)
                                .copyWith(fontSize: 15),
                          ),
                          Text(
                            'تحديث بيانات الصرفية رقم #${widget.row.id}',
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
              const SizedBox(height: 4),
              Expanded(
                child: ListView(
                  controller: controller,
                  padding:
                      const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, Sp.huge),
                  children: [
                    _label('المبلغ *'),
                    TextField(
                      controller: _amountCtrl,
                      keyboardType: TextInputType.number,
                      style: AppType.input(color: AppColors.textHi),
                      decoration: InputDecoration(
                        hintText: 'مثلاً 25,000',
                        hintStyle: AppType.input(color: AppColors.textLow),
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
                    const SizedBox(height: Sp.md),
                    _label('التاريخ'),
                    Material(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(R.sm),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: _submitting
                            ? null
                            : () async {
                                final picked = await showDatePicker(
                                  context: context,
                                  initialDate: _date,
                                  firstDate: DateTime(_date.year - 2, 1, 1),
                                  lastDate: DateTime.now(),
                                  helpText: 'اختر تاريخ الصرفية',
                                  cancelText: 'إلغاء',
                                  confirmText: 'تأكيد',
                                );
                                if (picked != null) {
                                  setState(() => _date = picked);
                                }
                              },
                        borderRadius: BorderRadius.circular(R.sm),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 12),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(R.sm),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Row(
                            children: [
                              Icon(LucideIcons.calendar,
                                  size: 16, color: AppColors.textMid),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  dateLabel,
                                  style: AppType.input(color: AppColors.textHi),
                                ),
                              ),
                              Icon(LucideIcons.chevronDown,
                                  size: 14, color: AppColors.textLow),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: Sp.md),
                    _label('ملاحظة (اختياري)'),
                    TextField(
                      controller: _noteCtrl,
                      maxLines: 2,
                      style: AppType.input(color: AppColors.textHi),
                      decoration: InputDecoration(
                        hintText: 'وصف الصرفية…',
                        hintStyle: AppType.input(color: AppColors.textLow),
                        filled: true,
                        fillColor: AppColors.surface,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(R.sm),
                          borderSide: BorderSide(color: AppColors.border),
                        ),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 10),
                      ),
                    ),
                  ],
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(Sp.lg, 0, Sp.lg, Sp.md),
                  child: SizedBox(
                    height: 50,
                    child: ElevatedButton.icon(
                      onPressed: _submitting || _amount <= 0 ? null : _submit,
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
                            : (_amount > 0
                                ? 'حفظ ${formatIQD(_amount)} د.ع'
                                : 'حفظ التعديل'),
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 14),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: accent,
                        foregroundColor: AppColors.onBrand,
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

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 4, right: 2),
        child: Text(
          text,
          style: AppType.muted(color: AppColors.textMid).copyWith(
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
}
