import 'package:easy_localization/easy_localization.dart';
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
import '../../../core/util/amount_input.dart';
import '../../../core/widgets/design_sheet.dart';
import '../../../core/widgets/sheet_scaffold.dart';

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
    barrierColor: AppColors.scrim,
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

  bool get _canSubmit => !_submitting && widget.sub.idx != null && _amount > 0;

  Future<void> _confirmAndSubmit() async {
    final amount = _amount.toDouble();
    final newDebt = (_currentBalance - amount).abs();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'تأكيد إضافة الدين',
          style: AppType.label(color: AppColors.textHi)
              .copyWith(fontSize: 16, fontWeight: FontWeight.w700),
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
              backgroundColor: AppColors.warning,
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
      comment:
          _commentCtrl.text.trim().isEmpty ? null : _commentCtrl.text.trim(),
    );
    if (!mounted) return;
    setState(() => _submitting = false);
    if (result.ok) SubscriberEvents.notifyChange();
    showSheetSnack(
      context,
      result.ok
          ? 'تم إضافة الدين بنجاح'
          : (result.message ?? 'فشل إضافة الدين'),
      isError: !result.ok,
    );
    if (result.ok) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    // المخطّط يصبغ شيت إضافة الدين بالكهرماني (لا الأخضر) — هو الشيت
    // الوحيد مع الحذف الذي يغيّر لون الرأس والزرّ عن البراند.
    final newBalance = _currentBalance - _amount.toDouble();
    return DesignSheet(
      header: SheetHeaderBar(
        icon: LucideIcons.creditCard,
        title: 'إضافة دين',
        subtitle: widget.sub.fullName,
        tint: AppColors.warningFill,
        tintBg: AppColors.warningSoftBg,
        onClose: () => Navigator.of(context).pop(),
      ),
      footer: SheetFooterBar(
        label: _submitting ? 'جاري الإضافة...' : 'إضافة دين',
        icon: LucideIcons.plus,
        color: AppColors.warningFill,
        enabled: _canSubmit,
        busy: _submitting,
        onPressed: _confirmAndSubmit,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _currentStatus(),
          const SizedBox(height: Sp.lg),
          SheetSection(
            label: 'قيمة الدين المضاف',
            gap: 9,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SheetBox(
                  focused: _amount > 0,
                  radius: 18,
                  padding: const EdgeInsets.symmetric(
                      horizontal: Sp.lg, vertical: 14),
                  child: AmountTextField(
                    controller: _amountCtrl,
                    currency: 'common.currency'.tr(),
                    onValue: (v) => setState(() => _amount = v),
                  ),
                ),
                const SizedBox(height: 9),
                // الشرائح **تُضيف** لا تستبدل — سلوك v1 (نقر 10k مرّتين
                // = 20k). لذلك «المختارة» تعني: المبلغ الحالي يساويها.
                Wrap(
                  spacing: 7,
                  runSpacing: 7,
                  children: [
                    for (final c in _chips)
                      SheetQuickChip(
                        label: _formatThousands(c),
                        selected: _amount == c,
                        onTap: () => _addToAmount(c),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: Sp.lg),
          SheetBox(
            icon: LucideIcons.fileText,
            child: TextField(
              controller: _commentCtrl,
              style: AppType.input(),
              maxLength: 120,
              decoration: InputDecoration(
                isDense: true,
                counterText: '',
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
                hintText: 'سبب إضافة الدين (اختياري)',
                hintStyle: AppType.input(color: AppColors.textPlaceholder),
              ),
            ),
          ),
          if (_amount > 0) ...[
            const SizedBox(height: Sp.lg),
            SheetResultBanner(
              icon: LucideIcons.arrowLeft,
              label: 'الدين بعد الإضافة',
              value: '${formatIQD(newBalance.abs().round())} د.ع',
              tone: SheetTone.warning,
            ),
          ],
        ],
      ),
    );
  }

  static const _chips = [
    5000,
    10000,
    15000,
    20000,
    25000,
    30000,
    35000,
    40000,
    45000,
    50000,
  ];

  /// صندوق الحالة أعلى الشيت. المخطّط يعرض «الدين الحالي» وحده؛ نبقي
  /// حالة الرصيد الدائن لأنّ إضافة دين على رصيد دائن عمليّة واردة.
  Widget _currentStatus() {
    if (_currentDebt > 0) {
      return SheetSummaryBox(
        label: 'الدين الحالي',
        value: '${formatIQD(_currentDebt.round())} د.ع',
        valueColor: AppColors.error,
      );
    }
    if (_currentCredit > 0) {
      return SheetSummaryBox(
        label: 'الرصيد الحالي (له)',
        value: '${formatIQD(_currentCredit.round())} د.ع',
        valueColor: AppColors.brandAccent,
      );
    }
    return SheetSummaryBox(
      label: 'الرصيد الحالي',
      value: 'لا يوجد',
      valueColor: AppColors.textMid,
    );
  }
}
