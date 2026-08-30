import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../api/subscribers_api.dart';
import '../../../core/util/format.dart';
import '../../../core/util/amount_input.dart';
import '../../../core/widgets/design_sheet.dart';
import '../../../core/widgets/sheet_scaffold.dart';
import '../../../models/subscriber.dart';
import '../../../services/manual_wa_prefs.dart';
import '../../../services/manual_wa_sender.dart';
import '../../../services/receipt_service.dart';
import '../../../services/subscriber_events.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';
import '_print_receipt_checkbox.dart';

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
    barrierColor: AppColors.scrim,
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
  // 2026-07-13: checkbox داخل المودل — الافتراضي false
  bool _printReceiptChecked = false;
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

  double get _effectiveAmount => _payAll ? _currentDebt : _amount.toDouble();

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
    // 2026-08-26 (manual WA phase 2): لو المدير مفعّل الوضع اليدوي، backend
    // ما يرسل WA تلقائياً — يرجع wa_preview بالنصّ الجاهز، ونفتح modal بعد
    // النجاح ليختار المدير: إرسال يدوي من واتسابه أو تلقائي من السيرفر.
    final manualMode = ManualWaPrefs.enabled.value;
    final result = await SubscribersApi.payDebt(
      idx: idx,
      amount: _effectiveAmount,
      comment: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
      skipAutoWa: manualMode,
    );
    if (!mounted) return;
    setState(() => _submitting = false);
    if (!result.ok) {
      showSheetSnack(context, result.message ?? 'فشل التسديد', isError: true);
      return;
    }
    SubscriberEvents.notifyChange();
    showSheetSnack(context, 'تم التسديد بنجاح');
    // مطلب 2026-06-11: لو الإرسال (التلقائي) فشل لسبب فني، أظهر تحذير.
    if (result.wa != null && result.wa!.shouldShowFailure) {
      showSheetSnack(
        context,
        'لم يُرسل واتساب: ${result.wa!.arabicReason}',
        isError: true,
      );
    }
    // 2026-07-13: طباعة تلقائية بعد النجاح لو الـcheckbox داخل المودل مُفعَّل.
    if (_printReceiptChecked) {
      final paidAmount = _effectiveAmount;
      final remainingDebt =
          (_currentDebt - paidAmount).clamp(0, double.infinity);
      await ReceiptService.printDebtPaymentReceipt(
        sub: widget.sub,
        paidAmount: paidAmount,
        remainingDebt: remainingDebt,
      );
    }
    if (!mounted) return;
    // 2026-08-26: preview WA بعد النجاح.
    // لو manualMode مفعّل والـbackend نجح ببناء الرسالة → افتح modal.
    // لو manualMode مفعّل لكن preview=null → snackbar يوضح السبب.
    if (manualMode) {
      if (result.waPreview != null) {
        await handleWaPreviewAfterOp(
          context: context,
          preview: result.waPreview!,
          opTitle: 'تأكيد التسديد',
          sas4Idx: widget.sub.idx,
        );
        if (!mounted) return;
      } else {
        final reason = result.wa?.reason;
        if (reason == 'no_phone') {
          showSheetSnack(context, 'لم يُبنَ preview: لا رقم هاتف للمشترك',
              isError: true);
        } else if (reason == 'no_template') {
          showSheetSnack(context,
              'لم يُبنَ preview: قالب "تسديد" غير موجود — أضفه من إعدادات الواتساب',
              isError: true);
        }
        // reasons أخرى (feature_off/notifications_disabled ما تصير مع
        // previewOnly) → صامتة كما كان الأدمن يريد الإخفاء.
      }
    }
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final livePreview = _currentBalance + _effectiveAmount;
    // سلّم المبالغ يُقصّ عند الدين — عرض شريحة 50,000 لدين 20,000
    // يدفع المدير لتجاوز المبلغ ثمّ تصحيحه.
    final chips = _chipScale.where((c) => c < _currentDebt).toList();
    final hasDebt = _currentDebt > 0;
    return DesignSheet(
      header: SheetHeaderBar(
        icon: LucideIcons.banknote,
        title: 'تسديد دين',
        subtitle: widget.sub.fullName,
        tint: AppColors.brandAccent,
        onClose: () => Navigator.of(context).pop(),
      ),
      footer: SheetFooterBar(
        label: _submitting ? 'جاري التسديد...' : 'تسديد الآن',
        icon: LucideIcons.banknote,
        color: AppColors.brandAccent,
        enabled: _canSubmit,
        busy: _submitting,
        onPressed: _submit,
        // المخطّط يضع خانة الطباعة داخل الشريط السفلي فوق الزرّ —
        // آخر ما تقع عليه العين قبل التأكيد.
        above: hasDebt
            ? PrintReceiptCheckbox(
                value: _printReceiptChecked,
                onChanged: (v) => setState(() => _printReceiptChecked = v),
              )
            : null,
      ),
      body: !hasDebt
          ? _noDebtState()
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SheetSummaryBox(
                  label: 'الدين الحالي',
                  value: '${formatIQD(_currentDebt.round())} د.ع',
                  valueColor: AppColors.error,
                ),
                const SizedBox(height: Sp.lg),
                SheetSection(
                  label: 'المبلغ المسدد',
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
                          enabled: !_payAll,
                          currency: 'common.currency'.tr(),
                          onValue: (v) => setState(() => _amount = v),
                        ),
                      ),
                      const SizedBox(height: 9),
                      Wrap(
                        spacing: 7,
                        runSpacing: 7,
                        children: [
                          for (final c in chips)
                            SheetQuickChip(
                              label: _formatThousands(c),
                              selected: !_payAll && _amount == c,
                              enabled: !_payAll,
                              onTap: () => _addToAmount(c),
                            ),
                          // «كامل الدين» بديل عن مفتاح منفصل — المخطّط
                          // يجعلها شريحة في نفس السطر لا صفّاً مستقلّاً.
                          SheetQuickChip(
                            label: 'كامل الدين',
                            icon: LucideIcons.checkCheck,
                            suggested: true,
                            selected: _payAll,
                            onTap: _togglePayAll,
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
                    controller: _notesCtrl,
                    style: AppType.input(),
                    maxLength: 120,
                    decoration: InputDecoration(
                      isDense: true,
                      counterText: '',
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                      hintText: 'ملاحظات (اختياري)',
                      hintStyle:
                          AppType.input(color: AppColors.textPlaceholder),
                    ),
                  ),
                ),
                if (_effectiveAmount > 0) ...[
                  const SizedBox(height: Sp.lg),
                  // القيمة قد تنقلب إلى رصيد دائن حين يتجاوز المسدَّد
                  // الدين — البانر يبدّل التسمية بدل عرض سالب.
                  SheetResultBanner(
                    icon: LucideIcons.arrowLeft,
                    label: livePreview >= 0
                        ? 'الرصيد للمشترك بعد التسديد'
                        : 'الدين المتبقي',
                    value: '${formatIQD(livePreview.abs().round())} د.ع',
                    tone: SheetTone.brand,
                  ),
                ],
              ],
            ),
    );
  }

  static const _chipScale = [
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

  Widget _noDebtState() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Sp.huge),
      child: Column(
        children: [
          Icon(LucideIcons.circleCheck, size: 34, color: AppColors.textHint),
          const SizedBox(height: Sp.md),
          Text('لا يوجد دين على هذا المشترك',
              style: AppType.rowValue(color: AppColors.textMid)),
        ],
      ),
    );
  }
}
