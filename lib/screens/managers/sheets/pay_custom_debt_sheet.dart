import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../api/manager_debts_api.dart';
import '../../../api/managers_api.dart';
import '../../../core/util/format.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';
import '../../../services/subscriber_events.dart';
import '../../../core/widgets/sheet_scaffold.dart';

/// تسديد جزئي/كلي لدين خارجي + عرض الدفعات السابقة. مطابق v1
/// _PayDebtUnifiedSheet (لمصدر custom debt).
Future<bool?> showPayCustomDebtSheet(
  BuildContext context,
  Manager manager,
  ManagerDebt debt,
) {
  return showModalBottomSheet<bool>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _PayDebtSheet(manager: manager, debt: debt),
  );
}

class _PayDebtSheet extends StatefulWidget {
  const _PayDebtSheet({required this.manager, required this.debt});
  final Manager manager;
  final ManagerDebt debt;

  @override
  State<_PayDebtSheet> createState() => _PayDebtSheetState();
}

class _PayDebtSheetState extends State<_PayDebtSheet> {
  final _amountCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  int _amount = 0;
  bool _submitting = false;
  bool _suppressFormat = false;
  bool _loadingPayments = true;
  List<ManagerDebtPayment> _payments = const [];
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    _amountCtrl.addListener(_onAmount);
    _loadPayments();
  }

  Future<void> _loadPayments() async {
    final list = await ManagerDebtsApi.payments(widget.debt.id);
    if (!mounted) return;
    setState(() {
      _payments = list;
      _loadingPayments = false;
    });
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _noteCtrl.dispose();
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

  num get _remaining {
    final paid = _payments.fold<num>(0, (a, p) => a + p.amountPaid);
    final r = widget.debt.amount - paid;
    return r < 0 ? 0 : r;
  }

  void _fillFull() {
    final max = _remaining.toInt();
    _suppressFormat = true;
    _amountCtrl.value = TextEditingValue(
      text: _fmt(max),
      selection: TextSelection.collapsed(offset: _fmt(max).length),
    );
    _suppressFormat = false;
    setState(() => _amount = max);
  }

  Future<void> _submit() async {
    if (_submitting || _amount <= 0) return;
    if (_amount > _remaining) {
      showSheetSnack(context, 'المبلغ يتجاوز المتبقي (${formatIQD(_remaining)})', isError: true);
      return;
    }
    setState(() => _submitting = true);
    final r = await ManagerDebtsApi.addPayment(
        debtId: widget.debt.id,
        amountPaid: _amount,
      note: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
    );
    if (!mounted) return;
    setState(() => _submitting = false);
    showSheetSnack(context, r.ok ? 'تم التسديد' : (r.errorMessage ?? 'تعذّر التسديد'), isError: (r.ok) ? false : true);
    if (r.ok) {
      SubscriberEvents.notifyChange();
      _changed = true;
      _amountCtrl.clear();
      _noteCtrl.clear();
      setState(() => _amount = 0);
      _loadPayments();
    }
  }

  Future<void> _deletePayment(ManagerDebtPayment p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('حذف التسديد'),
        content: Text('حذف تسديد ${formatIQD(p.amountPaid)} د.ع؟'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('إلغاء')),
          FilledButton(
            style:
                FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final r = await ManagerDebtsApi.deletePayment(p.id);
    if (!mounted) return;
    if (r.ok) {
      _changed = true;
      _loadPayments();
    }
    showSheetSnack(context, r.ok ? 'تم الحذف' : (r.message ?? 'تعذّر الحذف'), isError: (r.ok) ? false : true);
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    const accent = Color(0xFF0EA5E9);
    // iOS keyboard-avoidance: push the sheet up so amount + note +
    // submit button stay visible when the keyboard opens.
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (_, __) {
        // ما نريد نرجع نتيجة 'true' إلا إذا انتقل شيء — بس
        // الـmodal تسمح pop عادي.
      },
      child: DraggableScrollableSheet(
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
            padding: EdgeInsets.only(bottom: bottomInset),
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
                  padding:
                      const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, 0),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(R.md),
                        ),
                        child: const Icon(LucideIcons.banknote,
                            size: 16, color: accent),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'تسديد دين',
                              style: AppType.title(color: AppColors.textHi)
                                  .copyWith(fontSize: 15),
                            ),
                            Text(
                              widget.manager.username,
                              style: AppType.muted().copyWith(fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: _submitting
                            ? null
                            : () => Navigator.of(context).pop(_changed),
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
                      _statBlock(accent),
                      const SizedBox(height: Sp.md),
                      _label('مبلغ التسديد *'),
                      TextField(
                        controller: _amountCtrl,
                        keyboardType: TextInputType.number,
                        style: AppType.input(color: AppColors.textHi),
                        decoration: _dec(suffix: 'د.ع'),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap:
                                    _remaining > 0 ? _fillFull : null,
                                borderRadius: BorderRadius.circular(R.sm),
                                child: Container(
                                  padding:
                                      const EdgeInsets.symmetric(
                                          vertical: 8),
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: accent.withValues(alpha: 0.08),
                                    borderRadius:
                                        BorderRadius.circular(R.sm),
                                    border: Border.all(
                                        color: accent
                                            .withValues(alpha: 0.3)),
                                  ),
                                  child: Text(
                                    'تسديد كامل المتبقي',
                                    style: TextStyle(
                                      color: accent,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: Sp.md),
                      _label('ملاحظة (اختياري)'),
                      TextField(
                        controller: _noteCtrl,
                        maxLines: 2,
                        style: AppType.input(color: AppColors.textHi),
                        decoration: _dec(hint: 'وصف الدفعة…'),
                      ),
                      const SizedBox(height: Sp.lg),
                      _label('سجل الدفعات'),
                      _paymentsList(),
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
                        onPressed: (_amount > 0 && !_submitting)
                            ? _submit
                            : null,
                        icon: _submitting
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(LucideIcons.check, size: 16),
                        label: Text(
                          _submitting
                              ? 'جاري التسديد...'
                              : (_amount > 0
                                  ? 'تسديد ${formatIQD(_amount)}'
                                  : 'تسديد'),
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 14),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: accent,
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
      ),
    );
  }

  Widget _statBlock(Color accent) {
    return Container(
      padding: const EdgeInsets.all(Sp.md),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(R.md),
        border: Border.all(color: accent.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Expanded(child: _statLine('الإجمالي', widget.debt.amount, AppColors.textHi)),
          _statDivider(),
          Expanded(
              child: _statLine(
                  'المسدّد',
                  widget.debt.amount - _remaining,
                  AppColors.brand)),
          _statDivider(),
          Expanded(child: _statLine('المتبقي', _remaining, AppColors.error)),
        ],
      ),
    );
  }

  Widget _statLine(String label, num value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(label, style: AppType.muted().copyWith(fontSize: 10)),
        const SizedBox(height: 2),
        Text(
          '${formatIQD(value)}',
          style: AppType.label(color: color)
              .copyWith(fontSize: 12.5, fontWeight: FontWeight.w800),
        ),
      ],
    );
  }

  Widget _statDivider() => Container(
        width: 1,
        height: 24,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        color: AppColors.border,
      );

  Widget _paymentsList() {
    if (_loadingPayments) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_payments.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(
          'لا يوجد دفعات سابقة',
          style: AppType.muted().copyWith(fontSize: 11.5),
        ),
      );
    }
    return Column(
      children: [
        for (final p in _payments) ...[
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.surfaceInput,
              borderRadius: BorderRadius.circular(R.sm),
            ),
            child: Row(
              children: [
                Icon(LucideIcons.circleCheck,
                    size: 13, color: AppColors.brand),
                const SizedBox(width: 6),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${formatIQD(p.amountPaid)} د.ع',
                        style: AppType.label(color: AppColors.brand)
                            .copyWith(
                                fontSize: 12,
                                fontWeight: FontWeight.w800),
                      ),
                      Text(
                        _fmtIsoDate(p.paymentDate),
                        style:
                            AppType.muted().copyWith(fontSize: 10.5),
                      ),
                      if ((p.note ?? '').isNotEmpty)
                        Text(
                          p.note!,
                          style:
                              AppType.muted().copyWith(fontSize: 10.5),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
                InkResponse(
                  onTap: () => _deletePayment(p),
                  radius: 16,
                  child: Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(LucideIcons.x,
                        size: 13, color: AppColors.error),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
        ],
      ],
    );
  }

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 4, right: 2),
        child: Text(t,
            style: AppType.muted(color: AppColors.textMid).copyWith(
                fontSize: 11, fontWeight: FontWeight.w700)),
      );

  InputDecoration _dec({String? hint, String? suffix}) => InputDecoration(
        hintText: hint,
        hintStyle: AppType.input(color: AppColors.textLow),
        filled: true,
        fillColor: AppColors.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(R.sm),
          borderSide:
              BorderSide(color: AppColors.border.withValues(alpha: 0.5)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(R.sm),
          borderSide:
              BorderSide(color: AppColors.border.withValues(alpha: 0.5)),
        ),
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        suffixText: suffix,
      );
}

/// "yyyy-MM-dd" — used in the payment-history list to render the
/// payment date next to the amount.
String _fmtIsoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
