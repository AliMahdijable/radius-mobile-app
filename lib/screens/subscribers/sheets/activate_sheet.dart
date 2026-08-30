import 'package:easy_localization/easy_localization.dart';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../api/subscribers_api.dart';
import '../../../core/util/format.dart';
import '../../../core/util/amount_input.dart';
import '../../../core/widgets/design_sheet.dart';
import '../../../models/subscriber.dart';
import '../../../services/manual_wa_prefs.dart';
import '../../../services/manual_wa_sender.dart';
import '../../../services/receipt_service.dart';
import '../../../services/subscriber_events.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';
import '_print_receipt_checkbox.dart';
import '../../../core/widgets/sheet_scaffold.dart';

/// Bottom sheet for activating a subscriber's package — direct port of
/// v1's `_activateSubscriber` flow from
/// mobile-app/lib/screens/subscribers/subscriber_details_screen.dart:
///   1. Fetch /api/v2/subscribers/:idx/activation-data on open. Sheet
///      shows a spinner while the round-trip is in flight.
///   2. Display package / duration / original price / discount /
///      effective price + the subscriber's current balance + the
///      manager's wallet.
///   3. Three payment buttons: نقدي (full cash) / دين (non-cash) /
///      جزئي (partial cash). Partial mode unlocks an amount field
///      pre-populated with quick chips (5k / 10k / 15k / 25k / 35k /
///      50k, filtered to < effective price).
///   4. Live 'بعد التفعيل' preview row showing how the subscriber's
///      balance shifts.
///   5. Submit → /api/v2/subscribers/:idx/activate with the cached
///      activation-data echoed back (the backend rejects the call
///      otherwise — see server.js comment about SAS4 session locks).
///
/// Returns true on success so callers (subscribers list, detail screen)
/// can refresh their cached rows.
Future<bool?> showActivateSheet(BuildContext context, Subscriber sub) {
  return showModalBottomSheet<bool>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: AppColors.scrim,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _ActivateSheet(sub: sub),
  );
}

class _ActivateSheet extends StatefulWidget {
  const _ActivateSheet({required this.sub});
  final Subscriber sub;

  @override
  State<_ActivateSheet> createState() => _ActivateSheetState();
}

enum _PayType { cash, partial, debt }

class _ActivateSheetState extends State<_ActivateSheet> {
  Map<String, dynamic>? _data;
  bool _loading = true;
  bool _submitting = false;
  String? _loadError;

  // Default = آجل (dept/deferred). المستخدم صرّح 2026-07-11: أغلب
  // التفعيلات تكون آجلة، فنجعله الافتراضي بدل نقدي.
  _PayType _pay = _PayType.debt;
  bool _printReceiptChecked = false;
  final _partialCtrl = TextEditingController();
  int _partialAmount = 0;
  // True while the controller text is being rewritten by us (e.g. when
  // a chip is tapped). Lets the listener skip re-formatting recursion.
  bool _suppressFormat = false;

  @override
  void initState() {
    super.initState();
    _load();
    _partialCtrl.addListener(_onPartialChanged);
  }

  void _onPartialChanged() {
    if (_suppressFormat) return;
    final raw = _partialCtrl.text;
    final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    final parsed = int.tryParse(digits) ?? 0;
    final formatted = _formatThousands(parsed);
    if (formatted != raw) {
      _suppressFormat = true;
      _partialCtrl.value = TextEditingValue(
        text: formatted,
        selection: TextSelection.collapsed(offset: formatted.length),
      );
      _suppressFormat = false;
    }
    if (parsed != _partialAmount) {
      setState(() => _partialAmount = parsed);
    }
  }

  void _addToPartial(int chipAmount) {
    final next = _partialAmount + chipAmount;
    final formatted = _formatThousands(next);
    _suppressFormat = true;
    _partialCtrl.value = TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
    _suppressFormat = false;
    setState(() => _partialAmount = next);
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

  @override
  void dispose() {
    _partialCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final idx = widget.sub.idx;
    if (idx == null) {
      setState(() {
        _loading = false;
        _loadError = 'sheets.activate_no_idx'.tr();
      });
      return;
    }
    setState(() {
      _loading = true;
      _loadError = null;
    });
    final data = await SubscribersApi.fetchActivationData(idx);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _data = data;
      if (data == null) _loadError = 'sheets.activate_load_failed'.tr();
    });
  }

  num _readNum(String key) {
    final v = _data?[key];
    if (v == null) return 0;
    if (v is num) return v;
    return num.tryParse(v.toString().replaceAll(',', '')) ?? 0;
  }

  num get _userPrice => _readNum('user_price');
  num get _discount => _readNum('discount_amount');
  num get _effectivePrice => _readNum('price_after_discount');
  num get _currentBalance => _readNum('current_balance');
  num get _managerBalance => _readNum('manager_balance');
  num get _rewardPoints => _readNum('reward_points');
  String get _profileName =>
      (_data?['profile_name'] ?? widget.sub.profileName ?? '').toString();
  String? get _duration => _data?['profile_duration']?.toString();

  /// Mirrors v1's newNotes calculation:
  ///   cash    → balance unchanged
  ///   debt    → balance - price
  ///   partial → balance - price + partialAmount
  num get _balanceAfter {
    final price = _effectivePrice > 0 ? _effectivePrice : _userPrice;
    switch (_pay) {
      case _PayType.cash:
        return _currentBalance;
      case _PayType.debt:
        return _currentBalance - price;
      case _PayType.partial:
        return _currentBalance - price + _partialAmount;
    }
  }

  bool get _canSubmit {
    if (_loading || _submitting || _data == null) return false;
    if (_pay == _PayType.partial) {
      // Partial only requires a positive amount. v1 lets the admin
      // pay MORE than the package price and the excess lands as a
      // credit on the subscriber's notes — مطلب المستخدم 2026-06-07.
      // Don't gate on amount >= price.
      if (_partialAmount <= 0) return false;
    }
    return true;
  }

  Future<void> _submit() async {
    final idx = widget.sub.idx;
    if (idx == null || _data == null) return;
    final paymentType = switch (_pay) {
      _PayType.cash => 'cash',
      _PayType.partial => 'partial-cash',
      _PayType.debt => 'non-cash',
    };
    setState(() => _submitting = true);
    // 2026-08-26 (manual WA phase 2): وضع يدوي → backend يبني الرسالة
    // ويعيدها في wa_preview بلا إرسال، ونفتح modal بعد النجاح.
    final manualMode = ManualWaPrefs.enabled.value;
    final result = await SubscribersApi.activate(
      idx: idx,
      paymentType: paymentType,
      activationData: _data!,
      partialAmount: _pay == _PayType.partial ? _partialAmount : null,
      skipAutoWa: manualMode,
    );
    if (!mounted) return;
    setState(() => _submitting = false);
    if (!result.ok) {
      showSheetSnack(context, result.message ?? 'common.error'.tr(),
          isError: true);
      return;
    }
    SubscriberEvents.notifyChange();
    showSheetSnack(context, 'sheets.renew_ok'.tr(), isError: false);
    // 2026-07-13: طباعة تلقائية بعد النجاح لو الـcheckbox مُفعَّل.
    if (_printReceiptChecked) {
      final effPrice = _effectivePrice > 0 ? _effectivePrice : _userPrice;
      final num paidNow = switch (_pay) {
        _PayType.cash => effPrice,
        _PayType.partial => _partialAmount,
        _PayType.debt => 0,
      };
      final durationDays = int.tryParse(_duration ?? '');
      await ReceiptService.printActivationReceipt(
        sub: widget.sub,
        packagePrice: effPrice,
        paidAmount: paidNow,
        durationDays: durationDays,
      );
    }
    if (!mounted) return;
    // 2026-08-26: preview WA بعد نجاح التفعيل.
    if (manualMode) {
      if (result.waPreview != null) {
        await handleWaPreviewAfterOp(
          context: context,
          preview: result.waPreview!,
          opTitle: 'تأكيد التفعيل',
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
              'لم يُبنَ preview: قالب "تفعيل" غير موجود — أضفه من إعدادات الواتساب',
              isError: true);
        }
      }
    }
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    // حشوة لوحة المفاتيح صارت داخل DesignSheet.
    return DesignSheet(
      header: SheetHeaderBar(
        icon: LucideIcons.refreshCw,
        title: 'dashboard.renew_sub'.tr(),
        subtitle: widget.sub.fullName,
        onClose: () => Navigator.of(context).pop(),
      ),
      footer: SheetFooterBar(
        label: _submitting ? 'sheets.renewing'.tr() : 'sheets.renew_now'.tr(),
        icon: LucideIcons.refreshCw,
        enabled: _canSubmit,
        busy: _submitting,
        onPressed: _submit,
        above: PrintReceiptCheckbox(
          value: _printReceiptChecked,
          onChanged: (v) => setState(() => _printReceiptChecked = v),
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: _buildBody(),
      ),
    );
  }

  /// جسم الشيت بلغة المخطّط (2026-08-29). الترتيب: بطاقة الباقة الداكنة
  /// → صفوف الحالة → طريقة الدفع → (المبلغ الجزئي) → بانر النتيجة.
  List<Widget> _buildBody() {
    if (_loading) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: Sp.mega),
          child: Center(
            child: CircularProgressIndicator(
                color: AppColors.brandAccent, strokeWidth: 2.5),
          ),
        ),
      ];
    }
    if (_loadError != null) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: Sp.huge),
          child: Column(
            children: [
              Icon(LucideIcons.triangleAlert, color: AppColors.error, size: 32),
              const SizedBox(height: Sp.sm),
              Text(_loadError!,
                  style: AppType.rowValue(color: AppColors.error),
                  textAlign: TextAlign.center),
              const SizedBox(height: Sp.sm),
              TextButton(onPressed: _load, child: Text('common.retry'.tr())),
            ],
          ),
        ),
      ];
    }
    final price = _effectivePrice > 0 ? _effectivePrice : _userPrice;
    final cur = 'common.currency'.tr();
    final after = _balanceAfter;
    return [
      SheetPlanCard(
        planLabel: 'subscribers.label_package'.tr(),
        planName: _profileName.isEmpty ? '—' : _profileName,
        durationLabel: (_duration ?? '').isEmpty ? null : _duration,
        amountLabel: 'sheets.amount_due'.tr(),
        amount: '${formatIQD(price.round())} $cur',
        // السعر الأصلي مشطوباً بجانب النهائي — أوضح من صفَّي «السعر
        // الأصلي» و«الخصم» المنفصلين اللذين كانا في الكارت الأبيض.
        strikethrough: _discount > 0 ? formatIQD(_userPrice.round()) : null,
      ),
      const SizedBox(height: 14),
      SheetRowsGroup(
        rows: [
          if (_discount > 0)
            SheetRowData(
              label: 'subscribers.label_discount'.tr(),
              value: '-${formatIQD(_discount.round())} $cur',
              valueColor: AppColors.brandAccent,
            ),
          SheetRowData(
            label: _currentBalance < 0
                ? 'sheets.current_debt'.tr()
                : 'sheets.current_credit'.tr(),
            value: '${formatIQD(_currentBalance.abs().round())} $cur',
            valueColor:
                _currentBalance < 0 ? AppColors.error : AppColors.brandAccent,
            strong: true,
          ),
          SheetRowData(
            label: 'dashboard.manager_balance'.tr(),
            value: '${formatIQD(_managerBalance.round())} $cur',
          ),
          if (_rewardPoints > 0)
            SheetRowData(
              label: 'sheets.points'.tr(),
              value: formatIQD(_rewardPoints.round()),
              valueColor: AppColors.warningFill,
            ),
        ],
      ),
      const SizedBox(height: 14),
      SheetSection(
        label: 'sheets.payment_method'.tr(),
        gap: Sp.sm,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SheetChoiceTiles(
              labels: [
                'sheets.pay_cash'.tr(),
                'sheets.pay_debt'.tr(),
                'sheets.pay_partial'.tr(),
              ],
              icons: const [
                LucideIcons.banknote,
                LucideIcons.creditCard,
                LucideIcons.chartPie,
              ],
              selectedIndex: switch (_pay) {
                _PayType.cash => 0,
                _PayType.debt => 1,
                _PayType.partial => 2,
              },
              enabled: !_submitting,
              onSelect: (i) => setState(() => _pay = switch (i) {
                    0 => _PayType.cash,
                    1 => _PayType.debt,
                    _ => _PayType.partial,
                  }),
            ),
            if (_pay == _PayType.partial) ...[
              const SizedBox(height: Sp.md),
              SheetSection(
                label: 'sheets.cash_paid_amount'.tr(),
                gap: 9,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SheetBox(
                      focused: _partialAmount > 0,
                      radius: 18,
                      padding: const EdgeInsets.symmetric(
                          horizontal: Sp.lg, vertical: 14),
                      child: AmountTextField(
                        controller: _partialCtrl,
                        enabled: !_submitting,
                        currency: 'common.currency'.tr(),
                        onValue: (v) => setState(() => _partialAmount = v),
                      ),
                    ),
                    const SizedBox(height: 9),
                    // الشرائح تُضيف (سلوك v1)، ويُقصّ السلّم عند السعر
                    // حتى لا يتجاوز المدفوع جزئيّاً قيمة الباقة.
                    Wrap(
                      spacing: 7,
                      runSpacing: 7,
                      children: [
                        for (final c in _partialChips(price.round()))
                          SheetQuickChip(
                            label: _formatThousands(c),
                            selected: _partialAmount == c,
                            enabled: !_submitting,
                            onTap: () => _addToPartial(c),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      const SizedBox(height: 14),
      SheetResultBanner(
        icon: LucideIcons.arrowLeft,
        label: after < 0
            ? 'sheets.debt_after_activation'.tr()
            : 'sheets.credit_after_activation'.tr(),
        value: '${formatIQD(after.abs().round())} $cur',
        tone: after < 0 ? SheetTone.danger : SheetTone.brand,
      ),
    ];
  }

  /// سلّم المبالغ الجزئيّة — يُقصّ عند سعر الباقة.
  static List<int> _partialChips(int price) {
    const scale = [5000, 10000, 15000, 20000, 25000, 30000, 40000, 50000];
    final out = scale.where((c) => c < price).toList();
    return out.isEmpty ? [price] : out;
  }
}

// ───────── shared sheet chrome ─────────
