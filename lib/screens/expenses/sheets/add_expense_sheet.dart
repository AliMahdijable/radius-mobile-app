import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../api/expenses_api.dart';
import '../../../core/util/format.dart';
import '../../../core/widgets/design_sheet.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';
import '../../../core/widgets/sheet_scaffold.dart';
import '../../../core/util/amount_input.dart';

/// Add admin expense sheet — wired from FAB → 'إضافة سريعة' →
/// 'إضافة صرفية'. Three fields:
///   • المبلغ        — required, accumulating chips
///   • التاريخ      — defaults to today, optional override
///   • ملاحظة       — optional free text
/// Submit → POST /api/admin/expenses.
Future<bool?> showAddExpenseSheet(BuildContext context) {
  return showModalBottomSheet<bool>(
    barrierColor: AppColors.scrim,
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => const _AddExpenseSheet(),
  );
}

class _AddExpenseSheet extends StatefulWidget {
  const _AddExpenseSheet();

  @override
  State<_AddExpenseSheet> createState() => _AddExpenseSheetState();
}

class _AddExpenseSheetState extends State<_AddExpenseSheet> {
  final _amountCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  int _amount = 0;
  DateTime _date = DateTime.now();
  bool _submitting = false;
  bool _suppressFormat = false;

  @override
  void initState() {
    super.initState();
    _amountCtrl.addListener(_onAmountChanged);
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

  Future<void> _submit() async {
    if (_submitting) return;
    if (_amount <= 0) {
      showSheetSnack(context, 'أدخل المبلغ', isError: true);
      return;
    }
    setState(() => _submitting = true);
    String two(int n) => n.toString().padLeft(2, '0');
    final dateStr = '${_date.year}-${two(_date.month)}-${two(_date.day)}';
    final result = await ExpensesApi.create(
      amount: _amount,
      note: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
      expenseDate: dateStr,
    );
    if (!mounted) return;
    setState(() => _submitting = false);
    showSheetSnack(context,
        result.ok ? 'تم تسجيل الصرفية' : (result.message ?? 'تعذّر التسجيل'),
        isError: (result.ok) ? false : true);
    if (result.ok) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final accent = AppColors.brandAccent;
    String two(int n) => n.toString().padLeft(2, '0');
    final dateLabel = '${_date.year}/${two(_date.month)}/${two(_date.day)}';
    return DesignSheet(
      header: SheetHeaderBar(
        icon: LucideIcons.receipt,
        title: 'صرفيّة جديدة',
        subtitle: '',
        onClose: _submitting ? () {} : () => Navigator.of(context).pop(),
      ),
      footer: SheetFooterBar(
        label: _submitting
            ? 'جاري التسجيل...'
            : (_amount > 0
                ? 'تسجيل ${formatIQD(_amount)} د.ع'
                : 'تسجيل الصرفية'),
        icon: LucideIcons.receipt,
        enabled: !_submitting && _amount > 0,
        busy: _submitting,
        onPressed: _submit,
      ),
      scrollable: false,
      bodyPadding: EdgeInsets.zero,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Sp.xl, Sp.lg, Sp.xl, Sp.xxl),
        children: [
          _Lbl('المبلغ *'),
          _AmountField(
            controller: _amountCtrl,
            accent: accent,
            onClear: () {
              _suppressFormat = true;
              _amountCtrl.clear();
              _suppressFormat = false;
              setState(() => _amount = 0);
            },
            chips: const [5000, 10000, 25000, 50000, 100000],
            onChipTap: _addToAmount,
          ),
          const SizedBox(height: Sp.md),
          _Lbl('التاريخ'),
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
                        firstDate: DateTime(_date.year - 1, 1, 1),
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(R.sm),
                  border: Border.all(color: AppColors.borderSoft),
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
          _Lbl('ملاحظة (اختياري)'),
          TextField(
            controller: _noteCtrl,
            maxLines: 2,
            style: AppType.input(color: AppColors.textHi),
            decoration: InputDecoration(
              hintText: 'وصف الصرفية…',
              hintStyle: AppType.input(color: AppColors.textLow),
              prefixIcon: Padding(
                padding: EdgeInsets.only(left: 8, right: 4, bottom: 16),
                child: Icon(LucideIcons.fileText,
                    size: 16, color: AppColors.textMid),
              ),
              prefixIconConstraints:
                  const BoxConstraints(minWidth: 28, minHeight: 28),
              filled: true,
              fillColor: AppColors.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(R.sm),
                borderSide: BorderSide(color: AppColors.borderSoft),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(R.sm),
                borderSide: BorderSide(color: AppColors.borderSoft),
              ),
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            ),
          ),
        ],
      ),
    );
  }
}

class _Lbl extends StatelessWidget {
  const _Lbl(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Padding(
      padding: const EdgeInsets.only(bottom: 4, right: 2),
      child: Text(
        label,
        style: AppType.muted(color: AppColors.textMid).copyWith(
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
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
          AmountShorthandBox(
              controller: controller,
              child: TextField(
                controller: controller,
                keyboardType: TextInputType.number,
                style: AppType.input(color: AppColors.textHi),
                decoration: InputDecoration(
                  hintText: 'مثلاً 25,000',
                  hintStyle: AppType.input(color: AppColors.textLow),
                  filled: true,
                  fillColor: AppColors.surface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(R.sm),
                    borderSide: BorderSide(color: AppColors.borderSoft),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(R.sm),
                    borderSide: BorderSide(color: AppColors.borderSoft),
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
              )),
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
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
