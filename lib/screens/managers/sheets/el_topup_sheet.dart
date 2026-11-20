import 'dart:math';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../api/el_managers_api.dart';
import '../../../core/util/amount_input.dart';
import '../../../core/util/format.dart';
import '../../../core/widgets/app_sheet.dart';
import '../../../core/widgets/design_sheet.dart';
import '../../../services/permissions_service.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';
import '../../../widgets/el_deposit_password_field.dart';

/// «شحن رصيد» لمديرٍ تابع في ايرث لنك (٢٠ نوفمبر ٢٠٢٦): تحويلٌ من رصيد إيداع الوكيل عبر ايرث لنك نفسها — نقداً (استلام كاش الآن) أو
/// آجلاً (يُسجَّل المبلغ ديناً عليه في «ديون أخرى» بالعمليّة نفسها). أدنى مبلغ ٥٬٠٠٠ (شرط ايرث لنك)، وكلمة مرور الإيداع المحفوظة أو
/// تُكتب (الموظّف: المحفوظة وحدها — الخادم). تأكيدٌ قبل الإرسال؛ لا سحب ولا نقاط (ايرث لنك لا تسمح).
///
/// المال (مهارة money-change-review): مفتاح تكرارٍ لهذه النافذة — «غير مؤكَّد» أو انقطاع الردّ يقفل المدخلات ويصير الزرّ «تحقّق من
/// الشحن» بالمفتاح نفسه (الخادم يقرأ كشف الحساب ولا يشحن ثانيةً)؛ «المبلغ نفسه خلال ٥ دقائق» يسأل قبل أن يُعاد؛ ولا منع بالرصيد
/// (ايرث لنك تحكم — تنبيهٌ وحده). النجاح يُرجع النتيجة (رسالتها وسطر الإشعار) للشاشة.
Future<ElTopupResult?> showElTopupSheet(BuildContext context,
    {required ElManagerRow manager, num? balance, bool depositSaved = false}) {
  return showAppSheet<ElTopupResult>(
    barrierColor: AppColors.scrim,
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    useSafeArea: true,
    // عمليّة مالٍ قد تبقى «غير مؤكَّدة»: لا تُغلق بلمسةٍ خارجها ولا بسحبٍ — الإغلاق من زرّه وحده
    isDismissible: false,
    enableDrag: false,
    builder: (_) => _ElTopupSheet(manager: manager, balance: balance, depositSaved: depositSaved),
  );
}

class _ElTopupSheet extends StatefulWidget {
  const _ElTopupSheet({required this.manager, this.balance, this.depositSaved = false});
  final ElManagerRow manager;
  final num? balance;
  final bool depositSaved;

  @override
  State<_ElTopupSheet> createState() => _ElTopupSheetState();
}

class _ElTopupSheetState extends State<_ElTopupSheet> {
  final _amountCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  final _deposit = ElDepositPasswordController();
  int _amount = 0;
  bool _asDebt = false;
  bool _submitting = false;
  // إشعار المدير (المالك: «اشعار الوكيل الفرعي بالتطبيق والواتساب مثل ماعدنا بقيه الشركات») — مفعّلان حين يمكن
  late bool _notifyApp = widget.manager.hasApp;
  late bool _notifyWa = widget.manager.waPhone != null;
  // مفتاح تكرارٍ لهذه النافذة: إعادة الضغط أو انقطاعٌ بعد الإرسال لا يشحن مرّتين. يتجدّد بعد فشلٍ يقينيّ وحده (قد تتغيّر المدخلات).
  String _idem = _newKey();
  static String _newKey() => 'eltop-${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(1 << 30)}';
  // لم يُعرف إن تمّ الشحن (OUTCOME_UNKNOWN/IN_PROGRESS أو لا ردّ): المدخلات مقفلة والزرّ «تحقّق» بالمفتاح نفسه
  bool _uncertain = false;
  String? _uncertainMsg;
  // أكّد «اشحن ثانيةً» بعد RECENT_DUPLICATE — يبقى لهذه النافذة (إعادة «تحقّق» تحمله)
  bool _confirmedRepeat = false;
  final bool _employee = Perms.isEmployee;

  @override
  void initState() {
    super.initState();
    _amountCtrl.addListener(() {
      final v = int.tryParse(_amountCtrl.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
      if (v != _amount) setState(() => _amount = v);
    });
    _deposit.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    _deposit.dispose();
    super.dispose();
  }

  bool get _willApp => _notifyApp && widget.manager.hasApp;
  bool get _willWa => _notifyWa && widget.manager.waPhone != null;

  // تنبيهٌ لا منع (M5): ايرث لنك تحكم على الرصيد
  bool get _overBalance => widget.balance != null && _amount > widget.balance!;
  bool get _locked => _submitting || _uncertain;
  bool get _canSubmit =>
      !_submitting && (_uncertain || (_amount >= ElManagersApi.minTopup && (_employee || _deposit.ready)));

  /// [skipConfirm]: إعادةٌ بعد «نعم، اشحن ثانيةً» (سؤال التكرار) — أكّد للتوّ، فلا تأكيدٌ ثانٍ.
  Future<void> _submit({bool skipConfirm = false}) async {
    if (!_canSubmit) return;
    final name = widget.manager.name;
    if (!_uncertain && !skipConfirm && !await _confirm(name)) return;
    if (!mounted) return;
    setState(() => _submitting = true);
    final r = await ElManagersApi.topup(
      index: widget.manager.index,
      amount: _amount,
      asDebt: _asDebt,
      idempotencyKey: _idem,
      notifyApp: _willApp,
      notifyWhatsapp: _willWa,
      depositPassword: _employee ? null : _deposit.passwordToSend,
      rememberDepositPassword: !_employee && _deposit.rememberToSend,
      note: _noteCtrl.text,
      confirmRepeat: _confirmedRepeat,
    );
    if (!mounted) return;
    setState(() => _submitting = false);
    if (r.ok) {
      Navigator.of(context).pop(r);
      return;
    }
    if (r.repeatPrompt) {
      final again = await _askRepeat(r.message);
      if (again == true && mounted) {
        _confirmedRepeat = true;
        await _submit(skipConfirm: true);
      }
      return;
    }
    if (r.uncertain) {
      setState(() {
        _uncertain = true;
        _uncertainMsg = r.message;
      });
      return;
    }
    // فشلٌ يقيناً (رفض ايرث لنك، الجلسة، المدخلات…): مفتاحٌ جديد للمحاولة التالية
    _idem = _newKey();
    _confirmedRepeat = false;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
      content: Text(r.message ?? 'تعذّر الشحن'),
      backgroundColor: AppColors.errorFill,
      behavior: SnackBarBehavior.floating,
    ));
  }

  Future<bool?> _askRepeat(String? message) => showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('شحنٌ مكرَّر؟'),
          content: Text(message ?? 'شحنت المبلغ نفسه لهذا المدير قبل قليل — تشحنه مرّةً ثانية؟',
              style: const TextStyle(height: 1.6)),
          actions: [
            TextButton(onPressed: () => Navigator.of(c).pop(false), child: const Text('لا')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.brand),
              onPressed: () => Navigator.of(c).pop(true),
              child: const Text('نعم، اشحن ثانيةً'),
            ),
          ],
        ),
      );

  Future<bool> _confirm(String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('تأكيد الشحن'),
        content: Text(
          'تحويل ${formatIQD(_amount)} د.ع من رصيد إيداعك إلى «$name».'
          '${_asDebt ? '\n\nآجل: يُسجَّل ${formatIQD(_amount)} د.ع ديناً عليه في «ديون أخرى».' : '\n\nنقداً: استلمتَ المبلغ منه الآن.'}'
          '${_willApp || _willWa ? '\n\nيصله ${[if (_willApp) 'إشعارٌ بالتطبيق', if (_willWa) 'رسالة واتساب'].join(' و')}.' : ''}',
          style: const TextStyle(height: 1.6),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(c).pop(false), child: const Text('إلغاء')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.brand),
            onPressed: () => Navigator.of(c).pop(true),
            child: const Text('شحن'),
          ),
        ],
      ),
    );
    return ok == true;
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final bal = widget.balance;
    final after = bal == null ? null : bal - _amount;
    return DesignSheet(
      header: SheetHeaderBar(
        icon: LucideIcons.arrowUpToLine,
        title: 'شحن رصيد',
        subtitle: widget.manager.name,
        tint: AppColors.brand,
        tintBg: AppColors.brandSoftBg,
        onClose: _submitting ? () {} : () => Navigator.of(context).pop(),
      ),
      footer: SheetFooterBar(
        label: _submitting
            ? (_uncertain ? 'جارٍ التحقّق…' : 'جارٍ الشحن…')
            : _uncertain
                ? 'تحقّق من الشحن'
                : (_amount >= ElManagersApi.minTopup ? 'شحن ${formatIQD(_amount)} د.ع' : 'شحن'),
        icon: _uncertain ? LucideIcons.searchCheck : LucideIcons.arrowUpToLine,
        color: AppColors.brand,
        enabled: _canSubmit,
        busy: _submitting,
        onPressed: _submit,
      ),
      scrollable: false,
      bodyPadding: EdgeInsets.zero,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Sp.xl, Sp.lg, Sp.xl, Sp.xxl),
        children: [
          if (_uncertain) ...[
            _uncertainBanner(),
            const SizedBox(height: Sp.md),
          ],
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [
                AppColors.brand.withValues(alpha: 0.16),
                AppColors.brand.withValues(alpha: 0.04),
              ]),
              borderRadius: BorderRadius.circular(R.md),
              border: Border.all(color: AppColors.brand.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Icon(LucideIcons.wallet, size: 16, color: AppColors.textMid),
                const SizedBox(width: 8),
                Text('رصيد إيداعك ', style: AppType.muted().copyWith(fontSize: 12.5)),
                Text(bal == null ? '—' : '${formatIQDSigned(bal)} د.ع',
                    style: AppType.label(color: AppColors.textHi).copyWith(fontSize: 14, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
          const SizedBox(height: Sp.md),
          _label('طريقة الدفع'),
          Row(
            children: [
              Expanded(child: _payChip(debt: false)),
              const SizedBox(width: 8),
              Expanded(child: _payChip(debt: true)),
            ],
          ),
          const SizedBox(height: Sp.md),
          _label('المبلغ *'),
          AmountShorthandBox(
            controller: _amountCtrl,
            child: TextField(
              controller: _amountCtrl,
              enabled: !_locked,
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
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                suffixText: 'د.ع',
              ),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [for (final v in const [25000, 50000, 100000, 250000]) _quickChip(v)],
          ),
          const SizedBox(height: 6),
          Text(
            _overBalance
                ? 'المبلغ أكبر من رصيد إيداعك — ايرث لنك سترفضه على الأرجح'
                : 'أدنى مبلغ ${formatIQD(ElManagersApi.minTopup)} د.ع — شرط ايرث لنك',
            style: AppType.muted(color: _overBalance ? AppColors.warning : AppColors.textMid).copyWith(fontSize: 11),
          ),
          const SizedBox(height: Sp.md),
          _label('إشعار المدير'),
          _notifyBox(),
          // الموظّف يشحن بكلمة الإيداع المحفوظة وحدها (الخادم) — لا حقل له
          if (!_employee) ...[
            const SizedBox(height: Sp.md),
            _label('كلمة مرور الإيداع'),
            ElDepositPasswordField(controller: _deposit, enabled: !_locked, hint: '••••••'),
          ],
          const SizedBox(height: Sp.md),
          _label('ملاحظة (اختياري)'),
          TextField(
            controller: _noteCtrl,
            enabled: !_locked,
            maxLines: 2,
            style: AppType.input(color: AppColors.textHi),
            decoration: InputDecoration(
              hintText: 'سبب الشحن…',
              hintStyle: AppType.input(color: AppColors.textLow),
              filled: true,
              fillColor: AppColors.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(R.sm),
                borderSide: BorderSide(color: AppColors.border),
              ),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            ),
          ),
          if (after != null && _amount > 0) ...[
            const SizedBox(height: Sp.md),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.surfaceInput,
                borderRadius: BorderRadius.circular(R.sm),
                border: Border.all(color: AppColors.borderSoft),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sumRow('رصيدك بعد الشحن', '${formatIQDSigned(after)} د.ع'),
                  if (_asDebt) ...[
                    const SizedBox(height: 6),
                    _sumRow('ديون أخرى عليه بعدها',
                        '${formatIQD(widget.manager.otherDebt + _amount)} د.ع',
                        color: AppColors.warning),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// «لم يتأكّد»: لا تُعِد بمفتاحٍ جديد — «تحقّق» يسأل الخادم عن هذه العمليّة نفسها (يقرأ كشف الحساب ولا يشحن).
  Widget _uncertainBanner() => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.warning.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(R.md),
          border: Border.all(color: AppColors.warning.withValues(alpha: 0.45)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(LucideIcons.triangleAlert, size: 16, color: AppColors.warning),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${_uncertainMsg ?? 'لم يتأكّد الشحن من ايرث لنك'}\nاضغط «تحقّق من الشحن» — لا يُشحن مرّةً ثانية.',
                style: AppType.body(color: AppColors.textHi).copyWith(fontSize: 12.5, height: 1.55),
              ),
            ),
          ],
        ),
      );

  Widget _label(String s) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(s, style: AppType.label(color: AppColors.textHi).copyWith(fontSize: 12.5, fontWeight: FontWeight.w700)),
      );

  Widget _sumRow(String k, String v, {Color? color}) => Row(
        children: [
          // التسمية سطران عند الحاجة (لا «…» تقصّ نصّاً — 320 بخطٍّ مكبَّر)
          Expanded(child: Text(k, maxLines: 2, style: AppType.muted().copyWith(fontSize: 12.5))),
          Text(v,
              style: TextStyle(
                  fontSize: 13,
                  height: 1.35,
                  fontWeight: FontWeight.w700,
                  color: color ?? AppColors.textHi,
                  fontFeatures: const [FontFeature.tabularFigures()])),
        ],
      );

  /// كتوجّه شيت مدراء الساس (balance_op_sheet _notifyToggles): Material بحدٍّ يحمل البلاطات فيظهر حبر النقر.
  Widget _notifyBox() {
    final m = widget.manager;
    final hasWa = m.waPhone != null;
    return Material(
      color: AppColors.surfaceInput,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(R.sm), side: BorderSide(color: AppColors.borderSoft)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Column(
          children: [
            CheckboxListTile.adaptive(
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: m.hasApp && _notifyApp,
              onChanged: m.hasApp && !_locked ? (v) => setState(() => _notifyApp = v ?? false) : null,
              title: _notifyTitle(LucideIcons.bell, AppColors.brandAccent,
                  m.hasApp ? 'إشعار بتطبيقه' : 'إشعار بالتطبيق — لا يستعمل التطبيق بحسابه'),
            ),
            CheckboxListTile.adaptive(
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: hasWa && _notifyWa,
              onChanged: hasWa && !_locked ? (v) => setState(() => _notifyWa = v ?? false) : null,
              title: _notifyTitle(LucideIcons.send, AppColors.channelWhatsApp,
                  hasWa ? 'رسالة واتساب — ${m.waPhone}' : 'رسالة واتساب — لا رقم له (أضفه من بطاقته)'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _notifyTitle(IconData icon, Color color, String text) => Row(
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12.5, height: 1.4, fontWeight: FontWeight.w600)),
          ),
        ],
      );

  Widget _payChip({required bool debt}) {
    final active = _asDebt == debt;
    final color = debt ? AppColors.warning : AppColors.brand;
    return Material(
      color: active ? color.withValues(alpha: 0.10) : AppColors.surfaceInput,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(R.sm),
        side: BorderSide(color: active ? color.withValues(alpha: 0.5) : AppColors.borderSoft),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(R.sm),
        onTap: _locked ? null : () => setState(() => _asDebt = debt),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          child: Row(
            children: [
              Icon(debt ? LucideIcons.handCoins : LucideIcons.banknote, size: 15, color: active ? color : AppColors.textMid),
              const SizedBox(width: 7),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(debt ? 'شحن آجل' : 'شحن نقدي',
                        style: AppType.label(color: AppColors.textHi).copyWith(fontSize: 12.5, fontWeight: FontWeight.w700)),
                    Text(debt ? 'يُسجَّل ديناً عليه' : 'استلام كاش الآن',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppType.muted().copyWith(fontSize: 10.5, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _quickChip(int v) {
    return ActionChip(
      label: Text(formatIQD(v), style: AppType.pillBold(color: AppColors.textHi)),
      backgroundColor: AppColors.surfaceInput,
      side: BorderSide(color: AppColors.border),
      onPressed: _locked ? null : () => _amountCtrl.text = formatIQD(v),
    );
  }
}
