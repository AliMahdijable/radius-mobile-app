import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../api/manager_debts_api.dart';
import '../../../api/managers_api.dart';
import '../../../core/util/format.dart';
import '../../../core/widgets/design_sheet.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';
import '../../../services/subscriber_events.dart';
import '../../../core/widgets/sheet_scaffold.dart';
import '../../../core/util/amount_input.dart';

/// إضافة دين خارجي على مدير فرعي. مطابق v1 add-debt sheet
/// (managers_screen.dart:3007). الـbackend يقوم بإرسال إشعار
/// FCM للمدير تلقائياً عند الإضافة الناجحة.
Future<bool?> showAddCustomDebtSheet(
  BuildContext context,
  Manager manager,
) {
  return showModalBottomSheet<bool>(
    barrierColor: AppColors.scrim,
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _AddDebtSheet(manager: manager),
  );
}

class _AddDebtSheet extends StatefulWidget {
  const _AddDebtSheet({required this.manager});
  final Manager manager;

  @override
  State<_AddDebtSheet> createState() => _AddDebtSheetState();
}

class _AddDebtSheetState extends State<_AddDebtSheet> {
  final _amountCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  int _amount = 0;
  DateTime _date = DateTime.now();
  bool _submitting = false;
  bool _suppressFormat = false;

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

  Future<void> _submit() async {
    if (_submitting || _amount <= 0) return;
    setState(() => _submitting = true);
    String two(int n) => n.toString().padLeft(2, '0');
    final dateStr = '${_date.year}-${two(_date.month)}-${two(_date.day)}';
    final r = await ManagerDebtsApi.create(
      debtorAdminId: widget.manager.id,
      amount: _amount,
      note: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
      debtDate: dateStr,
    );
    if (!mounted) return;
    setState(() => _submitting = false);
    showSheetSnack(
        context, r.ok ? 'تم تسجيل الدين' : (r.message ?? 'تعذّر التسجيل'),
        isError: (r.ok) ? false : true);
    if (r.ok) {
      SubscriberEvents.notifyChange();
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final accent = AppColors.brandAccent;
    String two(int n) => n.toString().padLeft(2, '0');
    final dateLabel = '${_date.year}/${two(_date.month)}/${two(_date.day)}';
    // iOS keyboard-avoidance: push the sheet up so amount + note +
    // submit button stay visible when the keyboard opens.
    return DesignSheet(
      header: SheetHeaderBar(
        icon: LucideIcons.receipt,
        title: 'إضافة دين',
        subtitle: widget.manager.username,
        subtitleLtr: true,
        tint: AppColors.warningFill,
        tintBg: AppColors.warningSoftBg,
        onClose: _submitting ? () {} : () => Navigator.of(context).pop(),
      ),
      footer: SheetFooterBar(
        label: _submitting ? 'جارٍ الإضافة...' : 'إضافة الدين',
        icon: LucideIcons.plus,
        color: AppColors.warningFill,
        enabled: _amount > 0 && !_submitting,
        busy: _submitting,
        onPressed: _submit,
      ),
      scrollable: false,
      bodyPadding: EdgeInsets.zero,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Sp.xl, Sp.lg, Sp.xl, Sp.xxl),
        children: [
          _label('المبلغ *'),
          AmountShorthandBox(
              controller: _amountCtrl,
              child: TextField(
                controller: _amountCtrl,
                keyboardType: TextInputType.number,
                style: AppType.input(color: AppColors.textHi),
                decoration: _dec(suffix: 'د.ع'),
              )),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final v in const [
                10000,
                25000,
                50000,
                100000,
                250000,
                500000
              ])
                _quick(v, accent),
            ],
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
          _label('ملاحظة (اختياري)'),
          TextField(
            controller: _noteCtrl,
            maxLines: 2,
            style: AppType.input(color: AppColors.textHi),
            decoration: _dec(hint: 'سبب الدين…'),
          ),
        ],
      ),
    );
  }

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 4, right: 2),
        child: Text(t,
            style: AppType.muted(color: AppColors.textMid)
                .copyWith(fontSize: 11, fontWeight: FontWeight.w700)),
      );

  InputDecoration _dec({String? hint, String? suffix}) => InputDecoration(
        hintText: hint,
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
        suffixText: suffix,
      );

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
