import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../api/managers_api.dart';
import '../../../core/util/format.dart';
import '../../../services/manager_notice.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';
import '../../../services/subscriber_events.dart';
import '../../../core/widgets/sheet_scaffold.dart';
import '../../../core/util/amount_input.dart';

/// نوع العملية الافتراضي (لو actions sheet مرّر نوعاً محدّداً).
enum BalanceOpKind { deposit, withdraw, addPoints }

/// عمليات الرصيد على المدير: شحن / سحب / إضافة نقاط. الـmodal يعرض
/// 3 toggle بأعلى الـsheet، الـadmin يختار نوع العملية ثم يدخل
/// المبلغ + ملاحظة اختيارية. كل عملية لها endpoint منفصل في الـbackend.
Future<bool?> showBalanceOpSheet(
  BuildContext context,
  Manager m, {
  BalanceOpKind? preselected,
}) {
  return showModalBottomSheet<bool>(
    barrierColor: AppColors.scrim,
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _BalanceOpSheet(manager: m, preselected: preselected),
  );
}

enum _BalanceOp {
  deposit('شحن', LucideIcons.arrowUpToLine),
  withdraw('سحب', LucideIcons.arrowDownToLine),
  addPoints('نقاط', LucideIcons.star);

  const _BalanceOp(this.label, this.icon);
  final String label;
  final IconData icon;

  /// getter لا حقل const — نفس سبب `ManagerAction.color`: حقل الـenum
  /// الثابت لا يقبل توكناً يعرف الوضع الليلي.
  Color get color => switch (this) {
        _BalanceOp.deposit => AppColors.success,
        _BalanceOp.withdraw => AppColors.warning,
        _BalanceOp.addPoints => AppColors.brandAccent,
      };

  static _BalanceOp fromKind(BalanceOpKind? k) {
    switch (k) {
      case BalanceOpKind.deposit:
        return _BalanceOp.deposit;
      case BalanceOpKind.withdraw:
        return _BalanceOp.withdraw;
      case BalanceOpKind.addPoints:
        return _BalanceOp.addPoints;
      case null:
        return _BalanceOp.deposit;
    }
  }
}

class _BalanceOpSheet extends StatefulWidget {
  const _BalanceOpSheet({required this.manager, this.preselected});
  final Manager manager;
  final BalanceOpKind? preselected;

  @override
  State<_BalanceOpSheet> createState() => _BalanceOpSheetState();
}

class _BalanceOpSheetState extends State<_BalanceOpSheet> {
  late _BalanceOp _op = _BalanceOp.fromKind(widget.preselected);
  final _amountCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  int _amount = 0;
  bool _submitting = false;
  bool _suppressFormat = false;

  /// مطلب 2026-06-12: عند الشحن، إذا فعّل المدير "آجل" يصير الإيداع
  /// كـدين على المدير الفرعي بدل شحن نقدي. مطابق v1 isLoan.
  bool _isLoan = false;

  /// مطلب 2026-06-12 (إشعارات): toggles إرسال واتساب + push للمدير
  /// بعد العملية. الـwhatsapp يقفل تلقائياً لو المدير ما عنده رقم.
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

  Future<void> _submit() async {
    if (_submitting || _amount <= 0) return;
    setState(() => _submitting = true);
    final id = widget.manager.id;
    final note = _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim();
    // التقاط الأرصدة قبل العملية ل passing them للإشعار
    final previousCredit = widget.manager.balance ?? 0;
    final previousDebt = widget.manager.debt ?? 0;
    late ({bool ok, String? message}) r;
    switch (_op) {
      case _BalanceOp.deposit:
        r = await ManagersApi.deposit(
            id: id, amount: _amount, note: note, isLoan: _isLoan);
      case _BalanceOp.withdraw:
        r = await ManagersApi.withdraw(id: id, amount: _amount, note: note);
      case _BalanceOp.addPoints:
        r = await ManagersApi.addPoints(id: id, points: _amount, note: note);
    }
    if (!mounted) return;
    if (!r.ok) {
      setState(() => _submitting = false);
      showSheetSnack(context, r.message ?? 'فشلت العملية', isError: true);
      return;
    }
    // العملية نجحت — أرسل الإشعارات بحسب الـtoggles. الإشعار لا يحدّد
    // نجاح العملية في الـsnackbar الأساسي.
    showSheetSnack(context, 'تمت العملية', isError: false);
    // حساب أرصدة ما بعد العملية (تقديرية — السيرفر قد يدور بـSAS4
    // قيم مختلفة قليلاً، لكن هذا كافٍ للقالب).
    num currentCredit = previousCredit;
    num currentDebt = previousDebt;
    String actionKind = 'deposit_cash';
    switch (_op) {
      case _BalanceOp.deposit:
        if (_isLoan) {
          currentDebt = previousDebt + _amount;
          actionKind = 'deposit_loan';
        } else {
          currentCredit = previousCredit + _amount;
          actionKind = 'deposit_cash';
        }
      case _BalanceOp.withdraw:
        currentCredit = (previousCredit - _amount).clamp(0, double.infinity);
        actionKind = 'withdraw';
      case _BalanceOp.addPoints:
        // النقاط ما تأثر على الرصيد — نمرّر أنواعها للـpush.
        actionKind = 'add_points';
    }
    SubscriberEvents.notifyChange();
    // الإشعار يتم في الخلفية — ما نوقف الـclose للـsheet عليه.
    unawaited(_dispatchNotice(
      previousCredit: previousCredit,
      previousDebt: previousDebt,
      currentCredit: currentCredit,
      currentDebt: currentDebt,
      actionKind: actionKind,
      notes: note,
    ));
    if (mounted) Navigator.of(context).pop(true);
  }

  Future<void> _dispatchNotice({
    required num previousCredit,
    required num previousDebt,
    required num currentCredit,
    required num currentDebt,
    required String actionKind,
    String? notes,
  }) async {
    if (!_sendWhatsApp && !_sendPush) return;
    final r = await ManagerNoticeService.notify(
      manager: widget.manager,
      amount: _amount,
      isLoan: _isLoan && _op == _BalanceOp.deposit,
      previousCredit: previousCredit,
      previousDebt: previousDebt,
      currentCredit: currentCredit,
      currentDebt: currentDebt,
      // شحن/سحب/نقاط تؤثّر فقط على دين الـSAS — الديون الخارجية
      // تبقى كما هي. الكاش هنا لا يعرف الـperDebtor remaining لذا
      // نقدّر sasDebts ≈ currentDebt و otherDebts = 0. كافٍ للقالب.
      sasDebts: currentDebt,
      otherDebts: 0,
      actionKind: actionKind,
      notes: notes,
      sendWhatsApp: _sendWhatsApp,
      sendPush: _sendPush,
    );
    // التغذية الراجعة عن الإشعار تظهر فقط إذا أحدها فشل — نتجنب
    // إغراق الـadmin بـ"تم إرسال الواتساب" snackbars متعدّدة.
    if (!mounted) return;
    final failures = <String>[];
    if (_sendWhatsApp && !r.whatsAppOk) {
      failures.add('واتساب: ${r.whatsAppMessage ?? "فشل"}');
    }
    if (_sendPush && !r.pushOk) {
      failures.add('الإشعار: ${r.pushMessage ?? "فشل"}');
    }
    if (failures.isNotEmpty) {
      // The sheet may be popped already; use the navigator's root
      // messenger so the snackbar still renders.
      final rootMessenger = ScaffoldMessenger.maybeOf(context);
      rootMessenger?.showSnackBar(
        SnackBar(
          content: Text(failures.join(' · ')),
          backgroundColor: AppColors.warning,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    // iOS keyboard-avoidance: push the sheet up so amount + note +
    // submit button stay visible when the keyboard opens.
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
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
                padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, 0),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: _op.color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(R.md),
                      ),
                      child: Icon(_op.icon, size: 16, color: _op.color),
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
                  padding:
                      const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, Sp.huge),
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
                        border:
                            Border.all(color: _op.color.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          Icon(LucideIcons.wallet,
                              size: 16, color: AppColors.textMid),
                          const SizedBox(width: 8),
                          Text(
                            'الرصيد الحالي ',
                            style: AppType.muted().copyWith(fontSize: 12),
                          ),
                          Text(
                            '${formatIQD(widget.manager.balance ?? 0)} د.ع',
                            style: AppType.label(color: AppColors.textHi)
                                .copyWith(
                                    fontSize: 14, fontWeight: FontWeight.w700),
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
                    // مطلب 2026-06-12: toggle "آجل" يظهر فقط في وضع
                    // الشحن — يحوّل الإيداع لـدين على المدير الفرعي
                    // (مطابق v1 loan deposit).
                    if (_op == _BalanceOp.deposit) ...[
                      const SizedBox(height: Sp.md),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: _isLoan
                              ? AppColors.warning.withValues(alpha: 0.08)
                              : AppColors.surfaceInput,
                          borderRadius: BorderRadius.circular(R.sm),
                          border: Border.all(
                              color: _isLoan
                                  ? AppColors.warning.withValues(alpha: 0.4)
                                  : AppColors.border.withValues(alpha: 0.5)),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              _isLoan
                                  ? LucideIcons.handCoins
                                  : LucideIcons.banknote,
                              size: 14,
                              color: _isLoan
                                  ? AppColors.warning
                                  : AppColors.textMid,
                            ),
                            const SizedBox(width: 7),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _isLoan ? 'إيداع آجل' : 'شحن نقدي',
                                    style:
                                        AppType.label(color: AppColors.textHi)
                                            .copyWith(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w700),
                                  ),
                                  Text(
                                    _isLoan
                                        ? 'دين على المدير الفرعي'
                                        : 'استلام كاش الآن',
                                    style: AppType.muted().copyWith(
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                            ),
                            Switch.adaptive(
                              value: _isLoan,
                              activeColor: AppColors.warning,
                              onChanged: (v) => setState(() => _isLoan = v),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: Sp.md),
                    _label('المبلغ *'),
                    AmountShorthandBox(
                        controller: _amountCtrl,
                        child: TextField(
                          controller: _amountCtrl,
                          keyboardType: TextInputType.number,
                          style: AppType.input(color: AppColors.textHi),
                          decoration: InputDecoration(
                            hintText: 'مثلاً 50,000',
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
                            suffixText:
                                _op == _BalanceOp.addPoints ? 'نقطة' : 'د.ع',
                          ),
                        )),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        // مطلب 2026-06-12: chips مطابق v1 — 6 مبالغ
                        // إضافية للوصول السريع، تتراكم على المجموع.
                        for (final v in const [
                          10000,
                          25000,
                          50000,
                          100000,
                          250000,
                          500000
                        ])
                          _quickChip(v),
                      ],
                    ),
                    const SizedBox(height: Sp.md),
                    // مطلب 2026-06-12: toggles إشعار للمدير. مطابق v1
                    // _NotifyToggles. الـWA يقفل تلقائياً لو ما عنده
                    // رقم. الـpush بيشتغل لو المدير عنده FCM token مسجّل.
                    _notifyToggles(),
                    const SizedBox(height: Sp.md),
                    _label('ملاحظة (اختياري)'),
                    TextField(
                      controller: _noteCtrl,
                      maxLines: 2,
                      style: AppType.input(color: AppColors.textHi),
                      decoration: InputDecoration(
                        hintText: 'سبب العملية…',
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
                      onPressed: (_amount > 0 && !_submitting) ? _submit : null,
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

  Widget _notifyToggles() {
    final hasPhone = (widget.manager.mobile ?? '').trim().isNotEmpty;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surfaceInput,
        borderRadius: BorderRadius.circular(R.sm),
        border: Border.all(color: AppColors.borderSoft),
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
            title: Row(
              children: [
                Icon(LucideIcons.bell, size: 14, color: AppColors.brandAccent),
                SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'إشعار داخل تطبيق المدير',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
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
            style: AppType.muted(color: AppColors.textMid)
                .copyWith(fontSize: 11, fontWeight: FontWeight.w700)),
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
            color:
                selected ? op.color.withValues(alpha: 0.15) : AppColors.surface,
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
                  size: 13, color: selected ? op.color : AppColors.textMid),
              const SizedBox(width: 5),
              Text(
                op.label,
                style: TextStyle(
                  color: selected ? op.color : AppColors.textMid,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
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
              text: f, selection: TextSelection.collapsed(offset: f.length));
          _suppressFormat = false;
          setState(() => _amount = next);
        },
        borderRadius: BorderRadius.circular(R.sm),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: _op.color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(R.sm),
            border: Border.all(color: _op.color.withValues(alpha: 0.25)),
          ),
          child: Text(
            '+${_fmt(v)}',
            style: TextStyle(
              color: _op.color,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}
