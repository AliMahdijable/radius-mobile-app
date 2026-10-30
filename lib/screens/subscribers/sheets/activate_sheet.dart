import 'dart:async';
import 'dart:ui' as ui;

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
import '../../../services/merged_mode.dart';
import '../../../services/manual_wa_prefs.dart';
import '../../../services/manual_wa_sender.dart';
import '../../../services/provider_service.dart';
import '../../../services/receipt_service.dart';
import '../../../services/subscriber_events.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';
import '../../../widgets/el_deposit_password_field.dart';
import '../../../widgets/package_picker_field.dart';
import '_print_receipt_checkbox.dart';
import '../../../core/widgets/sheet_scaffold.dart';
import '../../../core/widgets/app_sheet.dart';
import '../../../core/widgets/print_feedback.dart';
import '../../../services/receipt_pdf.dart';

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
  return showAppSheet<bool>(
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

/// ايرث لنك: طريقة الدفع للمزوّد — رصيد أونلاين (newrefilldeposit + باسورد)
/// أو كارت مسبق الدفع (newrefillprepay + Identifier/Pin مكتوبان لا من مخزون).
/// مستقلّة عن [_Method] (SAS4) وعن [_PayType] (ما بين المشترك والوكيل).
enum _ElMethod { deposit, card }

/// فايبر اكس: متى تبدأ باقةٌ غير الحاليّة (change_type) — لا افتراض، يختار الوكيل صراحةً.
enum _FxTiming { now, expiry }

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

  // ── ايرث لنك (البند ٤) — كلّه من provider=='earthlink' في activation-data ──
  _ElMethod _elMethod = _ElMethod.deposit;         // الافتراض: رصيد أونلاين (كالويب)
  String _selectedPackageId = '';                  // id الباقة المختارة من المبدّل
  // باسورد الإيداع (deposit): المحفوظ على الخادم («محفوظ · تغيير») أو يُكتب.
  final _deposit = ElDepositPasswordController();
  final _identifierCtrl = TextEditingController();  // رقم الكارت (card)
  final _pinCtrl = TextEditingController();         // Pin الكارت (card)
  // RECENT_DUPLICATE (409) من خادم البرو: يُؤكَّد ويُعاد مع confirmRepeat=true.
  bool _confirmRepeat = false;
  // فايبر اكس: «تفعيلٌ مكرّر» عندهم (FIBERX_COOLOFF) يُعاد بتأكيدٍ صريح وحده؛ وتوقيت باقةٍ غير الحاليّة.
  bool _confirmCooloff = false;
  _FxTiming? _fxTiming;

  @override
  void initState() {
    super.initState();
    _load();
    _partialCtrl.addListener(_onPartialChanged);
    _deposit.addListener(_onDepositChanged);
    _loadAutoPrint();
  }

  /// «الطباعة التلقائيّة» في مصمّم وصل الموقع ⇒ الخانة معلَّمة من البداية (الموقع يطبع بلا سؤال).
  Future<void> _loadAutoPrint() async {
    final on = await ReceiptService.autoPrintFor(widget.sub.companyKey);
    if (on && mounted && !_printTouched) setState(() => _printReceiptChecked = true);
  }

  /// المستخدم غيّر الخانة بنفسه قبل وصول الإعداد — قراره يبقى.
  bool _printTouched = false;

  ReceiptPay get _receiptPay => switch (_pay) {
        _PayType.cash => ReceiptPay.cash,
        _PayType.partial => ReceiptPay.partial,
        _PayType.debt => ReceiptPay.credit,
      };

  void _onDepositChanged() {
    if (mounted) setState(() {}); // كي يتحدّث تفعيل الزرّ
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
    _deposit.removeListener(_onDepositChanged);
    _deposit.dispose();
    _identifierCtrl.dispose();
    _pinCtrl.dispose();
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
    final data = await MergedOps.run(widget.sub, () => SubscribersApi.fetchActivationData(idx));
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
        // ايرث لنك: افتح المبدّل على الباقة الحاليّة (أو أوّل باقة)، والافتراض رصيد أونلاين.
        final prov = data['provider']?.toString();
        if (prov == 'earthlink' || prov == 'fiberx' || ProviderService.isKitName(prov)) {
          final pid = data['profile_id']?.toString();
          final pkgIds = ((data['packages'] as List?) ?? const [])
              .whereType<Map>()
              .map((e) => e['id']?.toString())
              .toList();
          // الفعّال لا تتغيّر باقته (الخادم يرفض) — الاختيار يُثبَّت على الحاليّة ولو غابت عن القائمة.
          if (pid != null && pid.isNotEmpty && (pkgIds.contains(pid) || _elPackageLocked)) {
            _selectedPackageId = pid;
          } else if (pkgIds.isNotEmpty) {
            _selectedPackageId = pkgIds.first ?? '';
          }
          _elMethod = _ElMethod.deposit;
          _confirmRepeat = false;
          _confirmCooloff = false;
          _fxTiming = null;
        }
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
    final data = await MergedOps.run(widget.sub, () => SubscribersApi.fetchActivationData(idx));
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

  /// رقم [_profileName] من الكائن نفسه (عرض التفعيل وإلّا المشترك) — لاسمها في «بوابة المشترك» على الوصل.
  int? get _profileId => _data?['profile_name'] != null
      ? int.tryParse('${_data?['profile_id'] ?? ''}')
      : widget.sub.profileId;
  String? get _duration => _data?['profile_duration']?.toString();

  // ───────────────────── ايرث لنك (البند ٤) ─────────────────────
  /// مبدّل باقة + رصيد أونلاين/كارت بدل مصدر مال SAS4. يُكتشَف من provider
  /// في ردّ activation-data (كشيت التمديد).
  bool get _isEarthlink => _data?['provider']?.toString() == 'earthlink';

  // ───────────────────── فايبر اكس (٢٩ أكتوبر) ─────────────────────
  /// مبدّل الباقة نفسه (packages بشكل ايرث لنك: id/name/price/cost)، والدفع من محفظة الوكيل بلا «طريقة»؛ باقةٌ غير الحاليّة
  /// ⇒ «حالاً / عند الانتهاء» صريحاً (change_type)، و«تفعيلٌ مكرّر» عندهم ⇒ تأكيدٌ صريح (confirmCooloff) — كالويب.
  bool get _isFiberx => _data?['provider']?.toString() == 'fiberx';

  // ───────────────────── الشركات المُضافة (providerKit، ٣٠ أكتوبر) ─────────────────────
  /// نبض، AccessGate…: وضع فايبر اكس نفسه — مبدّل الباقة والدفع نقديّ/دين/جزئيّ والمبالغ من الخادم — بلا «عند الانتهاء» (الخادم
  /// يقول `package_change_timing: ['now']`: الباقة الأخرى تبدأ حالاً) ولا «تفعيلٌ مكرّر» فايبر اكس. كالموقع (ActivationModal isKit).
  bool get _isKit => ProviderService.isKitName(_data?['provider']?.toString());

  /// اسم الشركة المُضافة كما يقوله الخادم (`provider_label`).
  String get _kitName {
    final l = _data?['provider_label']?.toString().trim() ?? '';
    return l.isNotEmpty ? l : ProviderService.label;
  }

  /// وضع «المزوّد»: فايبر اكس أو شركةٌ مُضافة — فرعٌ مستقلّ لا يمسّ SAS4 ولا ايرث لنك.
  bool get _fxMode => _isFiberx || _isKit;

  /// مبدّل الباقة (ايرث لنك وفايبر اكس والشركات المُضافة) بدل باقة SAS4 الواحدة.
  bool get _pkgSwitcher => _isEarthlink || _fxMode;

  List<Map<String, dynamic>> get _elPackages =>
      ((_data?['packages'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => e.cast<String, dynamic>())
          .toList();

  Map<String, dynamic>? get _elSelectedPkg {
    for (final p in _elPackages) {
      if (p['id']?.toString() == _selectedPackageId) return p;
    }
    return null;
  }

  num _readNumOf(Map<String, dynamic>? m, String key) {
    final v = m?[key];
    if (v == null) return 0;
    if (v is num) return v;
    return num.tryParse(v.toString().replaceAll(',', '')) ?? 0;
  }

  bool get _elIsCurrentPkg {
    final pid = _data?['profile_id']?.toString();
    final sel = _elSelectedPkg?['id']?.toString();
    return sel != null && pid != null && sel == pid;
  }

  /// السعر الخام (قبل الخصم) — يُرسَل في base_price/user_price، والخادم يخصم
  /// **مرّةً** (مضادّ للتلاعب / منع الخصم المزدوج). الحاليّة: base_price←user_price←سعر الباقة.
  num get _elRawPrice {
    final pkg = _elSelectedPkg;
    if (pkg == null) return _userPrice;
    if (_elIsCurrentPkg) {
      if (_basePrice > 0) return _basePrice;
      if (_userPrice > 0) return _userPrice;
      return _readNumOf(pkg, 'price');
    }
    return _readNumOf(pkg, 'price');
  }

  /// السعر المعروض (بعد الخصم): الحاليّة ⇒ price_after_discount (يراعي الثابت)؛
  /// المُغيَّرة ⇒ سعرها − الخصم (تقريبيّ؛ الخادم يحسب الدقيق).
  num get _elChargePrice {
    final pkg = _elSelectedPkg;
    if (pkg == null) return _effectivePrice;
    if (_elIsCurrentPkg) {
      return _effectivePrice > 0 ? _effectivePrice : _elRawPrice;
    }
    // فايبر اكس: الثابت يلغي الخصم لباقته وحدها — لباقةٍ أخرى يعود الخصم (overridden_discount) كما يحسبه الخادم.
    final d = _fxMode && _discount <= 0 ? _readNum('overridden_discount') : _discount;
    final v = _readNumOf(pkg, 'price') - d;
    return v < 0 ? 0 : v;
  }

  num get _elSelectedPkgCost => _readNumOf(_elSelectedPkg, 'cost');

  /// السعر المعروض في البطاقة/البانر: ايرث لنك ⇒ elChargePrice، وإلّا منطق SAS4.
  num get _displayPrice => _pkgSwitcher
      ? _elChargePrice
      : (_effectivePrice > 0 ? _effectivePrice : _userPrice);

  /// Mirrors v1's newNotes calculation:
  ///   cash    → balance unchanged
  ///   debt    → balance - price
  ///   partial → balance - price + partialAmount
  num get _balanceAfter {
    final price = _displayPrice;
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
    if (_pkgSwitcher) return 'sheets.renew_now'.tr(); // «تفعيل/تجديد الآن» (كارت ايرث لنك لا مخزون، وفايبر اكس من المحفظة)
    if (!_cardMode) return 'sheets.renew_now'.tr();
    if (_cardDenied) return 'cards.not_allowed_short'.tr();
    if (_cards.level == CardStockLevel.empty) {
      return 'cards.no_card_short'.tr();
    }
    return 'cards.renew_with_card'.tr();
  }

  bool get _canSubmit {
    if (_loading || _submitting || _data == null) return false;
    if (_outcomeUnclear) return false;
    if (_fxMode) {
      if (_selectedPackageId.isEmpty) return false;
      // فايبر اكس: باقةٌ أخرى ⇒ التوقيت صريحاً. الشركة المُضافة: «حالاً» وحدها فلا اختيار.
      if (_isFiberx && !_elIsCurrentPkg && _fxTiming == null) return false;
      if (_pay == _PayType.partial && _partialAmount <= 0) return false;
      return true;
    }
    if (_isEarthlink) {
      if (_selectedPackageId.isEmpty) return false;
      if (_elMethod == _ElMethod.deposit && !_deposit.ready) return false;
      if (_elMethod == _ElMethod.card &&
          (_identifierCtrl.text.trim().isEmpty || _pinCtrl.text.trim().isEmpty)) {
        return false;
      }
      if (_pay == _PayType.partial && _partialAmount <= 0) return false;
      return true;
    }
    if (_cardBlocked) return false; // SAS4 فقط
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
    // ── مسار فايبر اكس (٢٩ أكتوبر) والشركات المُضافة (٣٠ أكتوبر) — فرعٌ مستقلّ كايرث لنك ──
    if (_fxMode) return _submitFiberx(idx, paymentType);
    // ── مسار ايرث لنك (البند ٤) — فرعٌ مستقلّ لا يمسّ منطق SAS4 أدناه ──
    if (_isEarthlink) {
      final profileId = int.tryParse(_selectedPackageId);
      // لقطةٌ من activation-data مع تجاوز base_price/user_price للسعر الخام للباقة
      // المختارة — فيخصم الخادم مرّةً واحدة (منع الخصم المزدوج).
      final elData = Map<String, dynamic>.from(_data!);
      elData['profile_id'] = profileId;
      elData['base_price'] = _elRawPrice;
      elData['user_price'] = _elRawPrice;

      setState(() => _submitting = true);
      final manualMode = ManualWaPrefs.enabled.value;
      final result = await MergedOps.run(widget.sub, () => SubscribersApi.activate(
        idx: idx,
        paymentType: paymentType,
        activationData: elData,
        partialAmount: _pay == _PayType.partial ? _partialAmount : null,
        skipAutoWa: manualMode,
        method: _elMethod == _ElMethod.deposit ? 'deposit' : 'card',
        // null مع المحفوظ — الخادم يضيفه بنفسه.
        depositPassword:
            _elMethod == _ElMethod.deposit ? _deposit.passwordToSend : null,
        rememberDepositPassword:
            _elMethod == _ElMethod.deposit && _deposit.rememberToSend,
        identifier:
            _elMethod == _ElMethod.card ? _identifierCtrl.text.trim() : null,
        pin: _elMethod == _ElMethod.card ? _pinCtrl.text.trim() : null,
        profileId: profileId,
        confirmRepeat: _confirmRepeat,
      ));
      if (!mounted) return;
      setState(() {
        _submitting = false;
        if (SubscribersApi.activateUnclearCodes.contains(result.code)) {
          _outcomeUnclear = true;
        }
      });
      if (_outcomeUnclear) SubscriberEvents.notifyChange();

      // حارس التكرار (٩٠ث) من خادم البرو — أكّد الإعادة ثمّ أعِد الإرسال.
      if (!result.ok && result.code == 'RECENT_DUPLICATE' && !_confirmRepeat) {
        final again = await showConfirmSheet(
          context,
          title: 'تفعيل مكرّر',
          message: result.message ??
              'فعّلت هذا المشترك قبل لحظات — أكّد الإعادة إن أردت تفعيلاً آخر',
          confirmLabel: 'أكّد التفعيل',
        );
        if (again == true) {
          _confirmRepeat = true;
          return _submit(); // إعادة مع confirmRepeat=true
        }
        return;
      }
      _confirmRepeat = false;
      if (!result.ok) {
        // مهلة/نتيجةٌ غير مؤكّدة ⇒ `_failureText` يعرض «ربّما تفعّل… راجع
        // الانتهاء» لا «خطأ» عارياً (كشيت «مشترك جديد»)، والزرّ يبقى مقفلاً.
        showSheetSnack(context, _failureText(result.code, result.message),
            isError: true);
        return;
      }
      SubscriberEvents.notifyChange();
      // تنبيه «لم يُسجَّل الدين» بعد إشعار النجاح — على الطبقة العليا (تُلتقط
      // قبل الإغلاق) فيبقى بعد إغلاق الشيت، تِلو النجاح لا فوقه (كشيت الإضافة).
      final rootOverlay = Overlay.maybeOf(context, rootOverlay: true);
      final okShown = showSheetSnack(context, 'sheets.renew_ok'.tr(), isError: false);
      if (result.debtWriteFailed && rootOverlay != null) {
        final warn = result.debtWriteMessage ??
            'sheets.activate_debt_not_recorded'.tr();
        unawaited(okShown.then((_) => showSheetSnackOn(rootOverlay, warn,
            isError: true, duration: const Duration(seconds: 8))));
      }
      if (_printReceiptChecked) {
        final printed = await ReceiptService.printActivation(
          sub: widget.sub,
          price: _elChargePrice,
          pay: _receiptPay,
          partialAmount: _partialAmount,
          packageName: _elSelectedPkg?['name']?.toString() ?? _profileName,
          packageId: _elSelectedPkg?['name'] != null
              ? int.tryParse('${_elSelectedPkg?['id'] ?? ''}')
              : _profileId,
        );
        if (mounted) showPrintResult(context, printed);
      }
      if (!mounted) return;
      if (manualMode && result.waPreview != null) {
        await handleWaPreviewAfterOp(
          context: context,
          preview: result.waPreview!,
          opTitle: 'تأكيد التفعيل',
          sas4Idx: widget.sub.idx,
        );
        if (!mounted) return;
      }
      Navigator.of(context).pop(true);
      return;
    }
    // لقطةٌ قبل الانتظار: الردّ يُقرأ بما أُرسل لا بما صار مختاراً بعده.
    final useCard = _cardMode;
    setState(() => _submitting = true);
    // 2026-08-26 (manual WA phase 2): وضع يدوي → backend يبني الرسالة
    // ويعيدها في wa_preview بلا إرسال، ونفتح modal بعد النجاح.
    final manualMode = ManualWaPrefs.enabled.value;
    final result = await MergedOps.run(widget.sub, () => SubscribersApi.activate(
      idx: idx,
      paymentType: paymentType,
      activationData: _data!,
      partialAmount: _pay == _PayType.partial ? _partialAmount : null,
      skipAutoWa: manualMode,
      method: useCard ? 'card' : 'credit',
    ));
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
      final printed = await ReceiptService.printActivation(
        sub: widget.sub,
        price: effPrice,
        pay: _receiptPay,
        partialAmount: _partialAmount,
        packageName: _profileName,
        packageId: _profileId,
      );
      if (mounted) showPrintResult(context, printed);
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
          onChanged: (v) => setState(() {
            _printTouched = true;
            _printReceiptChecked = v;
          }),
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
    final price = _displayPrice;
    final cur = 'common.currency'.tr();
    final after = _balanceAfter;
    final planName = _pkgSwitcher
        ? (_elSelectedPkg?['name']?.toString() ??
            (_profileName.isEmpty ? '—' : _profileName))
        : (_profileName.isEmpty ? '—' : _profileName);
    // السعر الأصلي مشطوباً: ايرث لنك ⇒ elRawPrice حين يختلف عن المعروض (خصم)؛ وإلّا منطق SAS4.
    final strike = _pkgSwitcher
        ? (_elRawPrice > 0 && _elRawPrice != price
            ? formatIQD(_elRawPrice.round())
            : null)
        : (_discount > 0
            ? formatIQD(_userPrice.round())
            : (_isFixedPrice && _basePrice > 0 && _basePrice != price
                ? formatIQD(_basePrice.round())
                : null));
    return [
      SheetPlanCard(
        planLabel: 'subscribers.label_package'.tr(),
        planName: planName,
        durationLabel: (_duration ?? '').isEmpty ? null : _duration,
        amountLabel: 'sheets.amount_due'.tr(),
        amount: '${formatIQD(price.round())} $cur',
        // السعر الأصلي مشطوباً بجانب النهائي — أوضح من صفَّي «السعر
        // الأصلي» و«الخصم» المنفصلين اللذين كانا في الكارت الأبيض.
        strikethrough: strike,
      ),
      const SizedBox(height: 14),
      SheetRowsGroup(
        rows: _pkgSwitcher
            ? [
                // ايرث لنك: كلفة الباقة المختارة (كلفة الوكيل) + الخصم + الدين/الرصيد + رصيد الإيداع.
                // فايبر اكس: كلفتها = ما تخصمه فايبر اكس من المحفظة، والسعر الثابت لباقته (كالساس).
                if (_elSelectedPkgCost > 0)
                  SheetRowData(
                    label: _isFiberx
                        ? 'sheets.fx_pkg_cost'.tr()
                        : _isKit
                            ? 'sheets.kit_pkg_cost'.tr(namedArgs: {'name': _kitName})
                            : 'كلفة الباقة المختارة',
                    value: '${formatIQD(_elSelectedPkgCost.round())} $cur',
                    valueColor: AppColors.textMid,
                  ),
                if (_fxMode && _elIsCurrentPkg && _isFixedPrice)
                  SheetRowData(
                    label: 'sp.fixed_price'.tr(),
                    value: 'sp.fixed_for_subscriber'.tr(),
                    valueColor: AppColors.brandAccent,
                  )
                else if (_fxMode && _elIsCurrentPkg && _needsRepricing)
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
                  valueColor: _currentBalance < 0
                      ? AppColors.error
                      : AppColors.brandAccent,
                  strong: true,
                ),
                SheetRowData(
                  label: 'dashboard.manager_balance'.tr(),
                  value: '${formatIQD(_managerBalance.round())} $cur',
                ),
              ]
            : [
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
      if (_isEarthlink) ...[
        const SizedBox(height: 14),
        _elPackageSection(),
        const SizedBox(height: 14),
        _elMethodSection(),
      ] else if (_fxMode) ...[
        const SizedBox(height: 14),
        _elPackageSection(),
        if (!_elIsCurrentPkg && _isFiberx) ...[
          const SizedBox(height: 14),
          _fxTimingSection(),
        ] else if (!_elIsCurrentPkg) ...[
          // الشركة المُضافة: الباقة الأخرى تبدأ حالاً وحدها — سطرٌ يقوله بدل اختيارٍ لا يوجد.
          const SizedBox(height: Sp.sm),
          Text(
            'sheets.kit_timing_now_note'.tr(namedArgs: {'name': _kitName}),
            style: AppType.muted(color: AppColors.textMid).copyWith(fontSize: 12.5, height: 1.4),
          ),
        ],
      ] else if (_methods.card) ...[
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

  /// فايبر اكس: باقةٌ غير الحاليّة ⇒ متى تبدأ — «حالاً» (الآن، ومدّتها من اليوم) أو «عند الانتهاء» (بعد الحاليّة). لا اختيار
  /// افتراضيّ: الزرّ مقفلٌ حتى يختار (الخادم يرفض بلاه CHANGE_TYPE_REQUIRED).
  Widget _fxTimingSection() {
    return SheetSection(
      label: 'sheets.fx_timing'.tr(),
      gap: Sp.sm,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SheetChoiceTiles(
            labels: ['sheets.fx_timing_now'.tr(), 'sheets.fx_timing_expiry'.tr()],
            icons: const [LucideIcons.zap, LucideIcons.calendarClock],
            selectedIndex: switch (_fxTiming) {
              _FxTiming.now => 0,
              _FxTiming.expiry => 1,
              null => -1,
            },
            enabled: !_submitting,
            onSelect: (i) => setState(() => _fxTiming = i == 1 ? _FxTiming.expiry : _FxTiming.now),
          ),
          const SizedBox(height: Sp.xs),
          Text(
            switch (_fxTiming) {
              _FxTiming.now => 'sheets.fx_timing_now_note'.tr(),
              _FxTiming.expiry => 'sheets.fx_timing_expiry_note'.tr(),
              null => 'sheets.fx_timing_pick'.tr(),
            },
            style: AppType.muted(color: AppColors.textMid).copyWith(fontSize: 12.5, height: 1.4),
          ),
        ],
      ),
    );
  }

  /// فايبر اكس (٢٩ أكتوبر) — كالويب (ActivationModal): الباقة الحاليّة تجديد، وغيرها بـchange_type صريح؛ الدفع من محفظة الوكيل
  /// والدين بدفترنا بسعر المشترك (يحسبه الخادم). «تفعيلٌ مكرّر» عندهم يُعاد بتأكيدٍ صريح وحده، والمجهول يقفل الزرّ (لا إعادة).
  Future<void> _submitFiberx(String idx, String paymentType) async {
    final change = !_elIsCurrentPkg;
    setState(() => _submitting = true);
    final manualMode = ManualWaPrefs.enabled.value;
    final result = await MergedOps.run(widget.sub, () => SubscribersApi.activate(
      idx: idx,
      paymentType: paymentType,
      activationData: _data!,
      partialAmount: _pay == _PayType.partial ? _partialAmount : null,
      skipAutoWa: manualMode,
      profileId: change ? int.tryParse(_selectedPackageId) : null,
      // الشركة المُضافة: «حالاً» وحدها (package_change_timing) — والخادم يرفض غيرها قبل أيّ نداء.
      changeType: change ? (_isFiberx && _fxTiming == _FxTiming.expiry ? 'expiry' : 'now') : null,
      confirmRepeat: _confirmRepeat,
      confirmCooloff: _confirmCooloff,
    ));
    if (!mounted) return;
    setState(() {
      _submitting = false;
      if (SubscribersApi.activateUnclearCodes.contains(result.code)) _outcomeUnclear = true;
    });
    if (_outcomeUnclear) SubscriberEvents.notifyChange();
    if (!result.ok && result.code == 'RECENT_DUPLICATE' && !_confirmRepeat) {
      final again = await showConfirmSheet(
        context,
        title: 'تفعيل مكرّر',
        message: result.message ?? 'فعّلت هذا المشترك قبل لحظات — أكّد الإعادة إن أردت تفعيلاً آخر',
        confirmLabel: 'أكّد التفعيل',
      );
      if (again == true) {
        _confirmRepeat = true;
        return _submitFiberx(idx, paymentType);
      }
      return;
    }
    if (!result.ok && result.code == 'FIBERX_COOLOFF' && !_confirmCooloff) {
      final again = await showConfirmSheet(
        context,
        title: 'sheets.fx_cooloff_title'.tr(),
        message: [result.message ?? '', 'sheets.fx_cooloff_extra'.tr()].where((x) => x.isNotEmpty).join('\n\n'),
        confirmLabel: 'sheets.fx_cooloff_confirm'.tr(),
      );
      if (!mounted) return;
      if (again == true) {
        _confirmCooloff = true;
        return _submitFiberx(idx, paymentType);
      }
      showSheetSnack(context, 'sheets.nothing_done'.tr(), isError: false);
      return;
    }
    _confirmRepeat = false;
    _confirmCooloff = false;
    if (!result.ok) {
      showSheetSnack(context, _failureText(result.code, result.message), isError: true);
      return;
    }
    SubscriberEvents.notifyChange();
    final rootOverlay = Overlay.maybeOf(context, rootOverlay: true);
    final okShown = showSheetSnack(context, 'sheets.renew_ok'.tr(), isError: false);
    if (result.debtWriteFailed && rootOverlay != null) {
      final warn = result.debtWriteMessage ?? 'sheets.activate_debt_not_recorded'.tr();
      unawaited(okShown.then((_) => showSheetSnackOn(rootOverlay, warn,
          isError: true, duration: const Duration(seconds: 8))));
    }
    if (_printReceiptChecked) {
      final printed = await ReceiptService.printActivation(
        sub: widget.sub,
        price: _elChargePrice,
        pay: _receiptPay,
        partialAmount: _partialAmount,
        packageName: _elSelectedPkg?['name']?.toString() ?? _profileName,
      );
      if (mounted) showPrintResult(context, printed);
    }
    if (!mounted) return;
    if (manualMode && result.waPreview != null) {
      await handleWaPreviewAfterOp(
        context: context,
        preview: result.waPreview!,
        opTitle: 'تأكيد التفعيل',
        sas4Idx: widget.sub.idx,
      );
      if (!mounted) return;
    }
    Navigator.of(context).pop(true);
  }

  /// مبدّل باقة ايرث لنك — حقلٌ واحد يفتح قائمة الباقات (بلاغ ٢٠٢٦-١٠-١٣:
  /// صفوف الاختيار كانت تطيل المودل بكلّ الباقات). الترتيب والاختيار
  /// الافتراضيّ والسعر كما كانت — العرض وحده تغيّر.
  Widget _elPackageSection() {
    final pkgs = _elPackages;
    final locked = _elPackageLocked;
    return SheetSection(
      label: 'الباقة',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PackagePickerField(
            options: [
              for (final p in pkgs)
                PackageOption(
                  id: p['id']?.toString() ?? '',
                  name: p['name']?.toString() ?? '',
                  price: _readNumOf(p, 'price'),
                ),
            ],
            selectedId: _selectedPackageId,
            currentId: _data?['profile_id']?.toString(),
            enabled: !_submitting && !locked,
            onSelected: (id) => setState(() => _selectedPackageId = id),
          ),
          if (locked) ...[
            const SizedBox(height: Sp.xs),
            Text(
              _elPackageNote,
              style: AppType.muted(color: AppColors.textMid).copyWith(fontSize: 12.5, height: 1.4),
            ),
          ],
        ],
      ),
    );
  }

  /// ايرث لنك: تتغيّر الباقة للمنتهي أو لمن بقي له يومٌ فأقلّ، و«More» لا تتغيّر (قاعدة المالك = ايرث لنك).
  /// المرجع حكم الخادم (canChangeAccount): بيانات التفعيل ← صفّ المشترك ← نافذة ٢٤ ساعة (خادمٌ أقدم).
  bool get _elPackageLocked {
    final flag = _data?['package_change_allowed'];
    if (flag is bool) return !flag;
    final rowFlag = widget.sub.canChangePackage;
    if (rowFlag != null) return !rowFlag;
    final exp = widget.sub.parsedExpiration;
    return exp != null && exp.difference(DateTime.now()) > const Duration(hours: 24);
  }

  String get _elPackageNote =>
      (_data?['package_change_note'] ?? widget.sub.packageChangeNote)?.toString() ??
      'تتغيّر الباقة للمنتهي أو لمن بقي له يومٌ فأقلّ — هذا المشترك ما زال فعّالاً';

  /// طريقة الدفع لايرث لنك: رصيد أونلاين (باسورد الإيداع) | كارت (رقم + Pin).
  Widget _elMethodSection() {
    final isDeposit = _elMethod == _ElMethod.deposit;
    return SheetSection(
      label: 'طريقة الدفع لايرث لنك',
      gap: Sp.sm,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SheetChoiceTiles(
            labels: const ['رصيد أونلاين', 'كارت'],
            icons: const [LucideIcons.wallet, LucideIcons.creditCard],
            selectedIndex: isDeposit ? 0 : 1,
            enabled: !_submitting,
            onSelect: (i) => setState(
                () => _elMethod = i == 0 ? _ElMethod.deposit : _ElMethod.card),
          ),
          const SizedBox(height: Sp.md),
          if (isDeposit)
            ElDepositPasswordField(controller: _deposit, enabled: !_submitting)
          else
            Row(
              children: [
                Expanded(
                  child: SheetBox(
                    focused: _identifierCtrl.text.isNotEmpty,
                    child: TextField(
                      controller: _identifierCtrl,
                      enabled: !_submitting,
                      keyboardType: TextInputType.number,
                      textDirection: ui.TextDirection.ltr,
                      onChanged: (_) => setState(() {}),
                      style: AppType.input(),
                      decoration: InputDecoration(
                        isDense: true,
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                        hintText: 'رقم الكارت',
                        hintStyle:
                            AppType.input(color: AppColors.textPlaceholder),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: Sp.sm),
                Expanded(
                  child: SheetBox(
                    focused: _pinCtrl.text.isNotEmpty,
                    child: TextField(
                      controller: _pinCtrl,
                      enabled: !_submitting,
                      keyboardType: TextInputType.number,
                      textDirection: ui.TextDirection.ltr,
                      onChanged: (_) => setState(() {}),
                      style: AppType.input(),
                      decoration: InputDecoration(
                        isDense: true,
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                        hintText: 'Pin',
                        hintStyle:
                            AppType.input(color: AppColors.textPlaceholder),
                      ),
                    ),
                  ),
                ),
              ],
            ),
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
