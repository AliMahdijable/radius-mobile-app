import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../api/managers_api.dart';
import '../../../core/util/format.dart';
import '../../../services/manager_notice.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';

/// تسديد دين الـSAS4 (الدين المخصوم من رصيد المدير في SAS4).
/// مطابق v1 (managers_screen.dart pay-debt action).
Future<bool?> showSasPayDebtSheet(BuildContext context, Manager m) {
  return showModalBottomSheet<bool>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _SasPayDebtSheet(manager: m),
  );
}

class _SasPayDebtSheet extends StatefulWidget {
  const _SasPayDebtSheet({required this.manager});
  final Manager manager;

  @override
  State<_SasPayDebtSheet> createState() => _SasPayDebtSheetState();
}

class _SasPayDebtSheetState extends State<_SasPayDebtSheet> {
  final _amountCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  int _amount = 0;
  bool _submitting = false;
  bool _suppressFormat = false;
  bool _sendWhatsApp = true;
  bool _sendPush = true;

  @override
  void initState() {
    super.initState();
    _amountCtrl.addListener(_onAmount);
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

  num get _maxDebt => widget.manager.debt ?? 0;

  void _fillFull() {
    final v = _maxDebt.toInt();
    _suppressFormat = true;
    _amountCtrl.value = TextEditingValue(
      text: _fmt(v),
      selection: TextSelection.collapsed(offset: _fmt(v).length),
    );
    _suppressFormat = false;
    setState(() => _amount = v);
  }

  Future<void> _submit() async {
    if (_submitting || _amount <= 0) return;
    if (_amount > _maxDebt) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('المبلغ يتجاوز الدين (${formatIQD(_maxDebt)})'),
          backgroundColor: const Color(0xFFE08F2D),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    setState(() => _submitting = true);
    final note = _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim();
    final previousCredit = widget.manager.balance ?? 0;
    final previousDebt = widget.manager.debt ?? 0;
    final r = await ManagersApi.sasPayDebt(
      id: widget.manager.id,
      amount: _amount,
      note: note,
      debtForMe: previousDebt,
      totalDebt: previousDebt,
    );
    if (!mounted) return;
    if (!r.ok) {
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(r.message ?? 'فشل تسديد الدين'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('تم تسديد الدين'),
        backgroundColor: AppColors.brand,
        behavior: SnackBarBehavior.floating,
      ),
    );
    // الـbackground notifications
    unawaited(_dispatchNotice(
        previousCredit: previousCredit, previousDebt: previousDebt));
    if (mounted) Navigator.of(context).pop(true);
  }

  Future<void> _dispatchNotice({
    required num previousCredit,
    required num previousDebt,
  }) async {
    if (!_sendWhatsApp && !_sendPush) return;
    final newDebt = (previousDebt - _amount).clamp(0, double.infinity);
    final r = await ManagerNoticeService.notify(
      manager: widget.manager,
      amount: _amount,
      isLoan: false,
      previousCredit: previousCredit,
      previousDebt: previousDebt,
      currentCredit: previousCredit,
      currentDebt: newDebt,
      actionKind: 'sas_pay_debt',
      notes: _noteCtrl.text.trim(),
      sendWhatsApp: _sendWhatsApp,
      sendPush: _sendPush,
    );
    if (!mounted) return;
    final failures = <String>[];
    if (_sendWhatsApp && !r.whatsAppOk) {
      failures.add('واتساب: ${r.whatsAppMessage ?? "فشل"}');
    }
    if (_sendPush && !r.pushOk) {
      failures.add('الإشعار: ${r.pushMessage ?? "فشل"}');
    }
    if (failures.isNotEmpty) {
      final rootMessenger = ScaffoldMessenger.maybeOf(context);
      rootMessenger?.showSnackBar(
        SnackBar(
          content: Text(failures.join(' · ')),
          backgroundColor: const Color(0xFFE08F2D),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFF0EA5E9);
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
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
                      child: const Icon(LucideIcons.banknote,
                          size: 16, color: accent),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'تسديد دين SAS',
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
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(R.md),
                        border:
                            Border.all(color: accent.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(LucideIcons.alertTriangle,
                              size: 16, color: Color(0xFFE08F2D)),
                          const SizedBox(width: 8),
                          Text(
                            'الدين الحالي: ',
                            style: AppType.muted().copyWith(fontSize: 12),
                          ),
                          Text(
                            '${formatIQD(_maxDebt)} د.ع',
                            style: AppType.label(
                                    color: const Color(0xFFE08F2D))
                                .copyWith(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800),
                          ),
                        ],
                      ),
                    ),
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
                              onTap: _maxDebt > 0 ? _fillFull : null,
                              borderRadius: BorderRadius.circular(R.sm),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    vertical: 8),
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: accent.withValues(alpha: 0.08),
                                  borderRadius:
                                      BorderRadius.circular(R.sm),
                                  border: Border.all(
                                      color:
                                          accent.withValues(alpha: 0.3)),
                                ),
                                child: Text(
                                  'تسديد كامل الدين',
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
                    _notifyToggles(),
                    const SizedBox(height: Sp.md),
                    _label('ملاحظة (اختياري)'),
                    TextField(
                      controller: _noteCtrl,
                      maxLines: 2,
                      style: AppType.input(color: AppColors.textHi),
                      decoration: _dec(hint: 'سبب التسديد…'),
                    ),
                  ],
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding:
                      const EdgeInsets.fromLTRB(Sp.lg, 0, Sp.lg, Sp.md),
                  child: SizedBox(
                    height: 50,
                    child: ElevatedButton.icon(
                      onPressed:
                          (_amount > 0 && !_submitting) ? _submit : null,
                      icon: _submitting
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(LucideIcons.banknote, size: 16),
                      label: Text(
                        _submitting
                            ? 'جاري التسديد...'
                            : (_amount > 0
                                ? 'تسديد ${formatIQD(_amount)}'
                                : 'تسديد الدين'),
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
    );
  }

  Widget _notifyToggles() {
    final hasPhone = (widget.manager.mobile ?? '').trim().isNotEmpty;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surfaceInput,
        borderRadius: BorderRadius.circular(R.sm),
        border:
            Border.all(color: AppColors.border.withValues(alpha: 0.5)),
      ),
      child: Column(
        children: [
          CheckboxListTile.adaptive(
            dense: true,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: hasPhone ? _sendWhatsApp : false,
            onChanged: hasPhone
                ? (v) => setState(() => _sendWhatsApp = v ?? false)
                : null,
            title: Row(
              children: [
                const Icon(LucideIcons.send,
                    size: 14, color: Color(0xFF25D366)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    hasPhone
                        ? 'إرسال رسالة واتساب للمدير'
                        : 'إرسال واتساب — لا يوجد رقم',
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
          CheckboxListTile.adaptive(
            dense: true,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _sendPush,
            onChanged: (v) => setState(() => _sendPush = v ?? false),
            title: const Row(
              children: [
                Icon(LucideIcons.bell,
                    size: 14, color: Color(0xFF3B82F6)),
                SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'إشعار داخل تطبيق المدير',
                    style: TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
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
