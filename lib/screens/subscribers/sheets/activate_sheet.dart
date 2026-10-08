import 'package:easy_localization/easy_localization.dart';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../api/cards_api.dart';
import '../../../api/subscribers_api.dart';
import '../../../core/util/bidi.dart';
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
///   6. §١٢ «طريقة التفعيل»: رصيد | كارت لمن يملك صلاحيّة الكارت (الرصيد
///      افتراضيّ). الخادم يسحب الكارت من مخزون الوكيل بنفسه؛ والشيت يعرض
///      كم بقي لباقة المشترك ويمنع الكارت حين لا يبقى شيء.
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

/// من أين يُدفع للساس: رصيد المدير (الافتراض — قرار المستخدم) أو كارتٌ من
/// مخزونه. محورٌ مستقلّ عن [_PayType] الذي يخصّ ما بين المشترك والوكيل.
enum _Method { credit, card }

class _ActivateSheetState extends State<_ActivateSheet> {
  Map<String, dynamic>? _data;
  bool _loading = true;
  bool _submitting = false;
  String? _loadError;

  // §١٢ التفعيل بالكارت — كلّه من activation-data. وحين يغيب الحقل (خادمٌ
  // أقدم) يبقى سلوك اليوم حرفيّاً: رصيدٌ بلا خيار.
  ActivationMethods _methods = ActivationMethods.legacy;
  CardStockInfo _cards = CardStockInfo.none;
  _Method _method = _Method.credit;

  /// الخادم رفض الكارت (`CARD_NOT_ALLOWED`) أو أعادت القراءة أنّه لم يعد
  /// مسموحاً. ⚠️ لا نقلب إلى الرصيد بصمت: مصدر المال لا يتبدّل بلا نقرةٍ
  /// من المدير — يبقى «كارت» مختاراً ومعطّلاً حتّى يختار «رصيد» بنفسه.
  bool _cardDenied = false;

  /// تفعيلٌ نتيجته غير مؤكّدة (مهلة، أو OUTCOME_UNKNOWN/NOT_CONFIRMED من الخادم):
  /// ربّما نُفّذ — فالزرّ يُقفل حتى يراجع المدير انتهاء المشترك، ولا تُغري
  /// ضغطةٌ ثانية بتفعيلٍ (أو كارتٍ) ثانٍ.
  bool _outcomeUnclear = false;
  bool _refreshingCards = false;

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
      if (data == null) {
        _loadError = 'sheets.activate_load_failed'.tr();
      } else {
        _methods = ActivationMethods.fromActivationData(data);
        _cards = CardStockInfo.fromActivationData(data);
        _cardDenied = false;
        // الرصيد افتراضيّ؛ والكارت يُختار وحده حين يكون الطريق الوحيد.
        _method = _methods.cardOnly ? _Method.card : _Method.credit;
      }
    });
  }

  /// «جرّب مجدّداً» على سطر الكارت — يعيد قراءة activation-data بلا دوّارة
  /// ويأخذ منها المخزون وحده: بقيّة الشيت (السعر، وما اختاره المدير، وما
  /// يُعاد إرساله للخادم) لا تتبدّل تحت يده.
  Future<void> _refreshCards() async {
    final idx = widget.sub.idx;
    if (idx == null || _refreshingCards || _submitting) return;
    setState(() => _refreshingCards = true);
    final data = await SubscribersApi.fetchActivationData(idx);
    if (!mounted) return;
    setState(() {
      _refreshingCards = false;
      if (data != null) {
        _cards = CardStockInfo.fromActivationData(data);
        if (!ActivationMethods.fromActivationData(data).card) {
          _cardDenied = true;
        }
      }
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

  /// «أسعار المشتركين»: الخادم طبّق سعراً ثابتاً (`user_price` = الثابت،
  /// والخصم صفر). الطبيعيّ في `base_price` يُعرض مشطوباً بجانبه.
  bool get _isFixedPrice => _data?['price_source'] == 'custom';
  bool get _needsRepricing => _data?['needs_repricing'] == true;
  num get _basePrice => _readNum('base_price');
  num get _effectivePrice => _readNum('price_after_discount');
  // Pro: سعر الشراء (كلفة المدير من الشركة) — يُعرَض كـهِنت ليعرف المدير هامشه.
  // في الساسات العراقيّة سعر البيع محلّيٌّ والشراء مثبّتٌ من الشركة.
  num get _managerCost => _readNum('manager_cost');
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

  bool get _cardMode => _method == _Method.card;

  /// اسم الباقة في جمل الكارت — ما قرأه الخادم مع المخزون أوّلاً، ثمّ باقة
  /// المشترك.
  String get _cardProfileName {
    final fromStock = _cards.profileName ?? '';
    if (fromStock.isNotEmpty) return fromStock;
    return _profileName.isEmpty ? '—' : _profileName;
  }

  /// الكارت مختارٌ ولا يصلح الآن: لا كارت لهذه الباقة، أو رُفضت الصلاحيّة.
  /// «تعذّرت القراءة» ليست منعاً — الخادم يعيد القراءة عند التفعيل نفسه.
  bool get _cardBlocked =>
      _cardMode && (_cardDenied || _cards.level == CardStockLevel.empty);

  /// تسمية الزرّ — وسبب المنع عليه حين يُمنع الكارت (كشيت التمديد).
  String get _footerLabel {
    if (_submitting) return 'sheets.renewing'.tr();
    if (_outcomeUnclear) return 'sheets.activate_check_first'.tr();
    if (!_cardMode) return 'sheets.renew_now'.tr();
    if (_cardDenied) return 'cards.not_allowed_short'.tr();
    if (_cards.level == CardStockLevel.empty) {
      return 'cards.no_card_short'.tr();
    }
    return 'cards.renew_with_card'.tr();
  }

  bool get _canSubmit {
    if (_loading || _submitting || _data == null) return false;
    if (_outcomeUnclear || _cardBlocked) return false;
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
    if (idx == null || _data == null || _cardBlocked || _outcomeUnclear) return;
    final paymentType = switch (_pay) {
      _PayType.cash => 'cash',
      _PayType.partial => 'partial-cash',
      _PayType.debt => 'non-cash',
    };
    // لقطةٌ قبل الانتظار: الردّ يُقرأ بما أُرسل لا بما صار مختاراً بعده.
    final useCard = _cardMode;
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
      method: useCard ? 'card' : 'credit',
    );
    if (!mounted) return;
    setState(() {
      _submitting = false;
      // رفضٌ معروف يُحدّث الشيت نفسه، فلا تتكرّر الضغطة على الرفض نفسه.
      if (useCard && result.code == CardsApi.codeNoCards) {
        _cards = _cards.withAvailable(0);
      } else if (useCard && result.code == CardsApi.codeCardNotAllowed) {
        _cardDenied = true;
      } else if (SubscribersApi.activateUnclearCodes.contains(result.code)) {
        _outcomeUnclear = true;
      }
    });
    if (_outcomeUnclear) {
      // ربّما تفعّل: القوائم تُحدَّث (يظهر الانتهاء الجديد إن نُفّذ)، وعدد
      // الكارتات لم يعد مضموناً فيُعاد طلبه بدل رسم رقمٍ قد يكون كاذباً.
      SubscriberEvents.notifyChange();
      if (useCard) CardsState.invalidate();
    }
    if (!result.ok) {
      showSheetSnack(context, _failureText(result.code, result.message),
          isError: true);
      return;
    }
    if (useCard) CardsState.consumeOne();
    SubscriberEvents.notifyChange();
    showSheetSnack(
      context,
      useCard ? _cardOkText(result.card) : 'sheets.renew_ok'.tr(),
      isError: false,
      duration: Duration(seconds: useCard ? 5 : 3),
    );
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

  /// رفضا الكارت المعروفان بجملتنا (باللغتين)، وما عداهما رسالة الخادم.
  String _failureText(String? code, String? message) => switch (code) {
        CardsApi.codeNoCards => 'cards.err_no_cards'
            .tr(namedArgs: {'profile': iso(_cardProfileName)}),
        // الخادم يميّز السبب (صلاحيّة التفعيل بالكارت أم عرض الكارتات) — رسالته أولى.
        CardsApi.codeCardNotAllowed =>
          (message != null && message.isNotEmpty) ? message : 'cards.err_not_allowed'.tr(),
        _ when SubscribersApi.activateUnclearCodes.contains(code) =>
          (message != null && message.isNotEmpty) ? message : 'sheets.activate_unclear'.tr(),
        _ => message ?? 'common.error'.tr(),
      };

  /// «تم التجديد بكارت ••4821 — باقي 2 لباقة Family».
  /// آخر أربع خانات فقط تصل من الخادم — للتعرّف على الكارت لا أكثر.
  String _cardOkText(ActivationCard? card) {
    final tail = card?.serialTail;
    final head = tail == null
        ? 'sheets.renew_ok'.tr()
        : 'cards.renewed_with'.tr(namedArgs: {'tail': iso('••$tail')});
    final left = card?.remaining;
    if (left == null) return head;
    final leftText = 'cards.left_for'.tr(namedArgs: {
      'n': iso('$left'),
      'profile': iso(card?.profileName ?? _cardProfileName),
    });
    return '$head — $leftText';
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
        label: _footerLabel,
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
  /// → صفوف الحالة → (طريقة التفعيل: رصيد | كارت) → طريقة الدفع →
  /// (المبلغ الجزئي) → بانر النتيجة.
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
        strikethrough: _discount > 0
            ? formatIQD(_userPrice.round())
            : (_isFixedPrice && _basePrice > 0 && _basePrice != price
                ? formatIQD(_basePrice.round())
                : null),
      ),
      const SizedBox(height: 14),
      SheetRowsGroup(
        rows: [
          // Pro: سعر الشراء (كلفة المدير من الشركة) كـهِنت — ليعرف المدير هامشه.
          if (_managerCost > 0)
            SheetRowData(
              label: 'subscribers.purchase_price'.tr(),
              value: '${formatIQD(_managerCost.round())} $cur',
              valueColor: AppColors.textMid,
            ),
          if (_isFixedPrice)
            SheetRowData(
              label: 'sp.fixed_price'.tr(),
              value: 'sp.fixed_for_subscriber'.tr(),
              valueColor: AppColors.brandAccent,
            )
          else if (_needsRepricing)
            SheetRowData(
              label: 'sp.fixed_price'.tr(),
              value: 'sp.needs_repricing_short'.tr(),
              valueColor: AppColors.warning,
            ),
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
      if (_methods.card) ...[
        const SizedBox(height: 14),
        _methodSection(),
      ],
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
        tone: after < 0 ? AppTone.danger : AppTone.brand,
      ),
    ];
  }

  /// سلّم المبالغ الجزئيّة — يُقصّ عند سعر الباقة.
  static List<int> _partialChips(int price) {
    const scale = [5000, 10000, 15000, 20000, 25000, 30000, 40000, 50000];
    final out = scale.where((c) => c < price).toList();
    return out.isEmpty ? [price] : out;
  }

  /// «طريقة التفعيل» — لمن يملك صلاحيّة الكارت وحده. بلاطتا «رصيد | كارت»
  /// حين يُسمح بالاثنين (والرصيد مختار)، ومع الكارت سطر المخزون: كم بقي
  /// لهذه الباقة، أو لماذا لا يصلح. ونوع الدفع تحته مستقلٌّ عنه تماماً.
  Widget _methodSection() {
    final available = _cards.available;
    return SheetSection(
      label: 'cards.activation_method'.tr(),
      gap: Sp.sm,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_methods.canChoose)
            SheetChoiceTiles(
              labels: [
                'cards.method_credit'.tr(),
                available == null
                    ? 'cards.method_card'.tr()
                    : 'cards.method_card_n'.tr(namedArgs: {'n': '$available'}),
              ],
              icons: const [LucideIcons.wallet, LucideIcons.ticket],
              selectedIndex: _cardMode ? 1 : 0,
              enabled: !_submitting,
              onSelect: (i) => setState(
                  () => _method = i == 1 ? _Method.card : _Method.credit),
            ),
          if (_cardMode) ...[
            if (_methods.canChoose) const SizedBox(height: Sp.sm),
            _cardNote(),
          ],
        ],
      ),
    );
  }

  Widget _cardNote() {
    if (_cardDenied) {
      return _CardNote(
        tone: AppTone.danger,
        icon: LucideIcons.ban,
        text: 'cards.err_not_allowed'.tr(),
      );
    }
    final profile = iso(_cardProfileName);
    return switch (_cards.level) {
      CardStockLevel.available => _CardNote(
          tone: AppTone.brand,
          icon: LucideIcons.ticket,
          text: 'cards.auto_pick'.tr(namedArgs: {
            'n': iso('${_cards.available}'),
            'profile': profile,
          }),
        ),
      CardStockLevel.empty => _CardNote(
          tone: AppTone.warning,
          icon: LucideIcons.triangleAlert,
          text: 'cards.none_for'.tr(namedArgs: {'profile': profile}),
        ),
      // ليس صفراً: التفعيل مسموح، والخادم يعيد القراءة داخل التفعيل نفسه.
      CardStockLevel.unknown => _CardNote(
          tone: AppTone.neutral,
          icon: LucideIcons.info,
          text: 'cards.read_failed'.tr(),
          onRetry: _submitting ? null : _refreshCards,
          busy: _refreshingCards,
        ),
    };
  }
}

/// سطر حال الكارت تحت «طريقة التفعيل» — بنغمةٍ من `AppTone` لا بلونٍ خاصّ.
/// ومع [onRetry] يصير السطر كلّه زرّاً («جرّب مجدّداً») بأيقونة تحديث.
class _CardNote extends StatelessWidget {
  const _CardNote({
    required this.tone,
    required this.icon,
    required this.text,
    this.onRetry,
    this.busy = false,
  });

  final AppTone tone;
  final IconData icon;
  final String text;
  final VoidCallback? onRetry;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final retry = onRetry;
    return Material(
      color: tone.softBg,
      borderRadius: BorderRadius.circular(R.lg),
      child: InkWell(
        onTap: busy ? null : retry,
        borderRadius: BorderRadius.circular(R.lg),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(R.lg),
            border: Border.all(color: tone.softBorder),
          ),
          child: Row(
            children: [
              Icon(icon, size: 16, color: tone.fill),
              const SizedBox(width: Sp.sm),
              Expanded(
                child: Text(
                  text,
                  style: AppType.body(color: tone.onSoft),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (retry != null || busy) ...[
                const SizedBox(width: Sp.sm),
                SizedBox(
                  width: 16,
                  height: 16,
                  child: busy
                      ? CircularProgressIndicator(
                          strokeWidth: 2, color: tone.fill)
                      : Icon(LucideIcons.refreshCw, size: 16, color: tone.fill),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ───────── shared sheet chrome ─────────
