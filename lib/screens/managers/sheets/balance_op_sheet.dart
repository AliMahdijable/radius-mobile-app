import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../api/managers_api.dart';
import '../../../core/util/format.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';

/// عمليات الرصيد على المدير: شحن / سحب / إضافة نقاط. الـmodal يعرض
/// 3 toggle بأعلى الـsheet، الـadmin يختار نوع العملية ثم يدخل
/// المبلغ + ملاحظة اختيارية. كل عملية لها endpoint منفصل في الـbackend.
Future<bool?> showBalanceOpSheet(BuildContext context, Manager m) {
  return showModalBottomSheet<bool>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _BalanceOpSheet(manager: m),
  );
}

enum _BalanceOp {
  deposit('شحن', Color(0xFF14B8A6), LucideIcons.arrowUpToLine),
  withdraw('سحب', Color(0xFFE08F2D), LucideIcons.arrowDownToLine),
  addPoints('نقاط', Color(0xFF8B5CF6), LucideIcons.star);

  const _BalanceOp(this.label, this.color, this.icon);
  final String label;
  final Color color;
  final IconData icon;
}

class _BalanceOpSheet extends StatefulWidget {
  const _BalanceOpSheet({required this.manager});
  final Manager manager;

  @override
  State<_BalanceOpSheet> createState() => _BalanceOpSheetState();
}

class _BalanceOpSheetState extends State<_BalanceOpSheet> {
  _BalanceOp _op = _BalanceOp.deposit;
  final _amountCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  int _amount = 0;
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
    final id = widget.manager.id;
    final note = _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim();
    late ({bool ok, String? message}) r;
    switch (_op) {
      case _BalanceOp.deposit:
        r = await ManagersApi.deposit(id: id, amount: _amount, note: note);
      case _BalanceOp.withdraw:
        r = await ManagersApi.withdraw(id: id, amount: _amount, note: note);
      case _BalanceOp.addPoints:
        r = await ManagersApi.addPoints(id: id, amount: _amount, note: note);
    }
    if (!mounted) return;
    setState(() => _submitting = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(r.ok
            ? 'تمت العملية'
            : (r.message ?? 'فشلت العملية')),
        backgroundColor:
            r.ok ? AppColors.brand : AppColors.error,
        behavior: SnackBarBehavior.floating,
      ),
    );
    if (r.ok) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, controller) {
        return Container(
          decoration: const BoxDecoration(
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
                        color: _op.color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(R.md),
                      ),
                      child:
                          Icon(_op.icon, size: 16, color: _op.color),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'عملية رصيد',
                            style: AppType.title(color: AppColors.textHi)
                                .copyWith(fontSize: 15),
                          ),
                          Text(
                            widget.manager.fullName.isNotEmpty
                                ? widget.manager.fullName
                                : widget.manager.username,
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
                        gradient: LinearGradient(
                          colors: [
                            _op.color.withValues(alpha: 0.16),
                            _op.color.withValues(alpha: 0.04),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(R.md),
                        border: Border.all(
                            color: _op.color.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(LucideIcons.wallet,
                              size: 16, color: AppColors.textMid),
                          const SizedBox(width: 8),
                          Text(
                            'الرصيد الحالي ',
                            style:
                                AppType.muted().copyWith(fontSize: 12),
                          ),
                          Text(
                            '${formatIQD(widget.manager.balance ?? 0)} د.ع',
                            style: AppType.label(color: AppColors.textHi)
                                .copyWith(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: Sp.md),
                    _label('نوع العملية'),
                    Row(
                      children: [
                        for (final op in _BalanceOp.values) ...[
                          Expanded(child: _opChip(op)),
                          if (op != _BalanceOp.values.last)
                            const SizedBox(width: 6),
                        ],
                      ],
                    ),
                    const SizedBox(height: Sp.md),
                    _label('المبلغ *'),
                    TextField(
                      controller: _amountCtrl,
                      keyboardType: TextInputType.number,
                      style: AppType.input(color: AppColors.textHi),
                      decoration: InputDecoration(
                        hintText: 'مثلاً 50,000',
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
                        suffixText:
                            _op == _BalanceOp.addPoints ? 'نقطة' : 'د.ع',
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final v in const [
                          10000,
                          25000,
                          50000,
                          100000
                        ])
                          _quickChip(v),
                      ],
                    ),
                    const SizedBox(height: Sp.md),
                    _label('ملاحظة (اختياري)'),
                    TextField(
                      controller: _noteCtrl,
                      maxLines: 2,
                      style: AppType.input(color: AppColors.textHi),
                      decoration: InputDecoration(
                        hintText: 'سبب العملية…',
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
                      ),
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
                          : Icon(_op.icon, size: 16),
                      label: Text(
                        _submitting
                            ? 'جاري التنفيذ...'
                            : (_amount > 0
                                ? '${_op.label} ${formatIQD(_amount)}'
                                : _op.label),
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 14),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _op.color,
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

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 4, right: 2),
        child: Text(t,
            style: AppType.muted(color: AppColors.textMid).copyWith(
                fontSize: 11, fontWeight: FontWeight.w700)),
      );

  Widget _opChip(_BalanceOp op) {
    final selected = _op == op;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => setState(() => _op = op),
        borderRadius: BorderRadius.circular(R.md),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected
                ? op.color.withValues(alpha: 0.15)
                : AppColors.surface,
            borderRadius: BorderRadius.circular(R.md),
            border: Border.all(
              color: selected ? op.color : AppColors.border,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(op.icon,
                  size: 13,
                  color: selected ? op.color : AppColors.textMid),
              const SizedBox(width: 5),
              Text(
                op.label,
                style: TextStyle(
                  color: selected ? op.color : AppColors.textMid,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _quickChip(int v) {
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
            color: _op.color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(R.sm),
            border:
                Border.all(color: _op.color.withValues(alpha: 0.25)),
          ),
          child: Text(
            '+${_fmt(v)}',
            style: TextStyle(
              color: _op.color,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }
}
