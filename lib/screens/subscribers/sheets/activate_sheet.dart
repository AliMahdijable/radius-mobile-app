import 'dart:async';
import 'dart:ui' as ui;

import 'package:easy_localization/easy_localization.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../api/cards_api.dart';
import '../../../api/kit_card_api.dart';
import '../../../api/subscribers_api.dart';
import '../../../core/util/bidi.dart';
import '../../../core/util/format.dart';
import '../../../core/util/amount_input.dart';
import '../../../core/widgets/design_sheet.dart';
import '../../../models/subscriber.dart';
import '../../../services/merged_mode.dart';
import '../../../services/manual_wa_prefs.dart';
import '../../../services/manual_wa_sender.dart';
import '../../../services/op_wa_notice.dart';
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
import '../../../api/national_wallet_api.dart' show CustomerWalletInfo;
import '../../national/national_wallet_topup_sheet.dart';
import '../../../widgets/merged_write_lock.dart';
import '../../../services/employee_visibility.dart';

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
Future<bool?> showActivateSheet(BuildContext context, Subscriber sub, {ActivatePrefill? prefill}) {
  if (mergedWriteBlocked(context, sub)) return Future.value(false);
  return showAppSheet<bool>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: AppColors.scrim,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _ActivateSheet(sub: sub, prefill: prefill),
  );
}

/// نوع الدفع كما قاله الوكيل بالأمر الصوتيّ.
enum ActivatePrefillPay { cash, debt, partial }

/// طريقة الدفع للشركة كما قالها: رصيده، كارت تعبئة، أو بطاقة مصرفيّة (الوطنيّ).
enum ActivatePrefillMethod { balance, card, bankCard }

/// «الأمر الصوتي ٢» (١٠ نوفمبر — المالك: «تفعيل جزئي»): ما قاله الوكيل («فعّل علي جزئي ١٠ الاف»، «نقد»، «بالكارت»، «شهرين»)
/// يظهر **مختاراً** بالشاشة حين تُفتح، بسطرٍ أعلاها يقول من أين جاء — ويبقى كلّ شيءٍ بيده: يعدّل ما شاء ثمّ يضغط «تجديد
/// الآن» بنفسه. لا يُرسل شيءٌ هنا، وما لا تعرضه الشاشة لهذا المشترك (كارتٌ بلا صلاحيّته، أشهرٌ لشركةٍ دورتها واحدة) لا يُختار
/// ويُقال له.
class ActivatePrefill {
  const ActivatePrefill({this.pay, this.paid, this.months, this.method});

  final ActivatePrefillPay? pay;

  /// المدفوع نقداً مع [ActivatePrefillPay.partial] — بخانة «المبلغ المدفوع». null ⇒ الخانة فارغة يكتبها.
  final int? paid;
  final int? months;
  final ActivatePrefillMethod? method;

  bool get isEmpty => pay == null && paid == null && months == null && method == null;
}

class _ActivateSheet extends StatefulWidget {
  const _ActivateSheet({required this.sub, this.prefill});
  final Subscriber sub;
  final ActivatePrefill? prefill;

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

  /// قال الخادم «تفعّل» — والشيت يُغلق بعد الوصل والواتساب. من هذه اللحظة لا يُعاد التفعيل بأيّ طريق: الزرّ «تمّ» لا
  /// يُنقر، و[_submit] يرجع (Enter على الحاسبة، أو نقرةٌ بعد إغلاق ورقة الطباعة فوقه). مراجعة 179: الوصل يُنتظر قبل
  /// الإغلاق فكان الزرّ حيّاً تحته طوال الطباعة. الفشل والنتيجة غير المؤكّدة كما كانا.
  bool _done = false;

  /// وصل التفعيل يُطبع الآن (بعد النجاح) ⇒ «تمّ — جارٍ الطباعة…».
  bool _printingReceipt = false;

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
  // ── الشركة المُضافة: التفعيل لعدّة أشهر (المشروع الوطنيّ، ١ نوفمبر — `months_options` من الخادم؛ البطاقة شهرٌ واحد) ──
  int _months = 1;
  Map<String, dynamic>? _quote; // معاينة الشركة للأشهر المختارة (السعر والكلفة والعروض والانتهاء الجديد)
  String? _quoteFor; // مفتاح المعاينة المعروضة: «أشهر|باقة»
  String? _quoteErr;
  bool _quoting = false;
  // باسورد الإيداع (deposit): المحفوظ على الخادم («محفوظ · تغيير») أو يُكتب.
  // «كل الشركات»: باسورد إيداع شركة المشترك نفسها (شركتا ايرث لنك لكلٍّ منهما محفوظها) — null خارج الوضع.
  late final _deposit = ElDepositPasswordController(companyKey: widget.sub.companyKey);
  final _identifierCtrl = TextEditingController();  // رقم الكارت (card)
  final _pinCtrl = TextEditingController();         // Pin الكارت (card)
  // «طريق موقع الشحن» (فايبر الجزيرة): رقم بطاقةٍ خارجيّة (٨ خانات) — يُرسل مع الطلب وحده
  final _railPinCtrl = TextEditingController();
  // «التفعيل برقم البطاقة» (٢٣ نوفمبر — شركات الكارتات، cards.typed): رقمٌ يكتبه الوكيل كصفحة الساس — يُرسل مرّةً مع الطلب ولا يُحفظ
  // ولا يُطبع
  final _typedPinCtrl = TextEditingController();
  // «تأكيد رقم المشترك بالواتساب» (موقع الشحن، ١٤ نوفمبر): الرقم ⇒ «أرسل الرمز» ⇒ الرمز ⇒ «تأكيد» ⇒ تُعاد قراءة النافذة
  late final _otpPhoneCtrl = TextEditingController(text: _otpPhoneOf(widget.sub.phone));
  final _otpCodeCtrl = TextEditingController();
  bool _otpSent = false;
  bool _otpBusy = false;
  String? _otpMsg;
  bool _otpMsgError = false;
  // RECENT_DUPLICATE (409) من خادم البرو: يُؤكَّد ويُعاد مع confirmRepeat=true.
  bool _confirmRepeat = false;
  // فايبر اكس: «تفعيلٌ مكرّر» عندهم (FIBERX_COOLOFF) يُعاد بتأكيدٍ صريح وحده؛ وتوقيت باقةٍ غير الحاليّة.
  bool _confirmCooloff = false;
  _FxTiming? _fxTiming;
  // المشروع الوطنيّ (٣١ أكتوبر): الدفع للشركة من «محفظتي» أو بالبطاقة (card_payment من الخادم — مفتاح watani_card). بالبطاقة:
  // رابط دفعٍ يفتحه الوكيل، والشيت يتابع الطلب حتى يُحسم — الدين يُسجَّل على الخادم حين يظهر التفعيل (لا من هنا).
  bool _payByCard = false;
  _CardOrder? _cardOrder;
  Timer? _cardPoll;
  DateTime? _cardSince;
  // المشروع الوطنيّ (٢ نوفمبر — المالك: «بالتفعيل تظهر زرّ محفظة المشترك إن عنده رصيد، وإن ماعنده تكلّه شحن المحفظة وتظهر مودل
  // الشحن»): الدفع للشركة من محفظة المشترك نفسه (customer_wallet من الخادم — مفتاح <name>_custwallet). لا نقداً ولا ديناً عندنا:
  // المشترك دفع من رصيده، فلا «طريقة الدفع» ولا دين بعده؛ شهرٌ واحد.
  bool _payByCustWallet = false;

  // ── «الأمر الصوتي ٢»: ما قيل وطُبّق على الاختيارات (مرّةً، بعد أوّل تحميل) وما لم تعرضه الشاشة ──
  bool _prefillDone = false;
  bool _voiceMonths = false;
  List<String> _voiceApplied = const [];
  List<String> _voiceSkipped = const [];

  /// يضع ما قاله الوكيل على الاختيارات — داخل setState بعد أوّل تحميلٍ ناجح. لا يرسل ولا يفعّل؛ والزرّ بشروطه كما هو.
  void _applyPrefill() {
    final pf = widget.prefill;
    if (pf == null || pf.isEmpty || _prefillDone) return;
    _prefillDone = true;
    final applied = <String>[];
    final skipped = <String>[];
    switch (pf.method) {
      case ActivatePrefillMethod.card:
        if (_isEarthlink) {
          _elMethod = _ElMethod.card;
          applied.add('كارت');
        } else if (!_pkgSwitcher && _methods.card) {
          _method = _Method.card;
          applied.add('كارت');
        } else {
          skipped.add('الكارت غير متاح لهذا التفعيل');
        }
      case ActivatePrefillMethod.bankCard:
        if (_cardPayAvailable) {
          _payByCard = true;
          _payByCustWallet = false;
          applied.add('بطاقة');
        } else {
          skipped.add('الدفع بالبطاقة غير متاح لهذا التفعيل');
        }
      case ActivatePrefillMethod.balance:
        // الرصيد هو المختار أصلاً — إلّا حين يكون الكارت الطريق الوحيد
        if (!_pkgSwitcher && _methods.cardOnly) skipped.add('الرصيد غير متاح — التفعيل بالكارت وحده');
      case null:
        break;
    }
    final m = pf.months;
    if (m != null && m > 1) {
      if (_isKit && _monthsOpts.contains(m) && !_kitCard && !_kitCust) {
        _months = m;
        _voiceMonths = true;
        applied.add(_monthsLabel(m));
      } else {
        skipped.add('${_monthsLabel(m)} — المدّة هنا دورة الباقة');
      }
    }
    switch (pf.pay) {
      case ActivatePrefillPay.cash:
        _pay = _PayType.cash;
        applied.add('sheets.pay_cash'.tr());
      case ActivatePrefillPay.debt:
        _pay = _PayType.debt;
        applied.add('sheets.pay_debt'.tr());
      case ActivatePrefillPay.partial:
        final paid = pf.paid ?? 0;
        final price = _displayPrice.round();
        if (paid > 0 && price > 0 && paid == price) {
          // المدفوع = السعر كلّه ⇒ نقديّ لا جزئيّ
          _pay = _PayType.cash;
          applied.add('sheets.pay_cash'.tr());
        } else if (paid > 0 && price > 0 && paid > price) {
          // مدفوعٌ مسموعٌ أكبر من السعر كلّه — الأرجح سمعٌ خاطئ لا رصيدٌ مقصود: الجزئيّ مختار والمبلغ يكتبه بيده
          _pay = _PayType.partial;
          applied.add('sheets.pay_partial'.tr());
          skipped.add('المدفوع المسموع ${formatIQD(paid)} أكبر من السعر — اكتبه بيدك');
        } else {
          _pay = _PayType.partial;
          if (paid > 0) {
            final text = _formatThousands(paid);
            _suppressFormat = true;
            _partialCtrl.value = TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));
            _suppressFormat = false;
            _partialAmount = paid;
            applied.add('${'sheets.pay_partial'.tr()} ${formatIQD(paid)}');
          } else {
            applied.add('${'sheets.pay_partial'.tr()} — اكتب المدفوع');
          }
        }
      case null:
        break;
    }
    _voiceApplied = applied;
    _voiceSkipped = skipped;
  }

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
    _cardPoll?.cancel();
    _partialCtrl.dispose();
    _deposit.removeListener(_onDepositChanged);
    _deposit.dispose();
    _identifierCtrl.dispose();
    _pinCtrl.dispose();
    _railPinCtrl.dispose();
    _typedPinCtrl.dispose();
    _otpPhoneCtrl.dispose();
    _otpCodeCtrl.dispose();
    super.dispose();
  }

  /// رقم المشترك من الساس كما يُكتب في موقع الشحن (أرقامٌ وحدها) — فارغٌ إن لم يكن.
  static String _otpPhoneOf(String? raw) => (raw ?? '').replaceAll(RegExp(r'[^0-9+]'), '');

  /// ١) «أرسل الرمز» — الموقع يرسل رمزاً بالواتساب لرقم المشترك.
  Future<void> _otpSend() async {
    final idx = widget.sub.idx;
    if (idx == null || _otpBusy) return;
    setState(() {
      _otpBusy = true;
      _otpMsg = null;
    });
    final r = await MergedOps.run(widget.sub, () => SubscribersApi.payOtp(idx, phone: _otpPhoneCtrl.text.trim()));
    if (!mounted) return;
    setState(() {
      _otpBusy = false;
      _otpSent = r.ok;
      _otpMsgError = !r.ok;
      _otpMsg = r.message ?? (r.ok ? 'أُرسل الرمز لرقم المشترك' : 'تعذّر إرسال الرمز');
    });
  }

  /// ٢) «تأكيد» بالرمز — نجح ⇒ تُعاد قراءة نافذة التفعيل (يسقط طلب التأكيد) فيُفعَّل كالعادة.
  Future<void> _otpConfirm() async {
    final idx = widget.sub.idx;
    final code = _otpCodeCtrl.text.trim();
    if (idx == null || _otpBusy || code.isEmpty) return;
    setState(() {
      _otpBusy = true;
      _otpMsg = null;
    });
    final r = await MergedOps.run(widget.sub, () => SubscribersApi.payOtp(idx, code: code));
    if (!mounted) return;
    setState(() {
      _otpBusy = false;
      _otpMsgError = !r.ok;
      _otpMsg = r.message ?? (r.ok ? 'تمّ تأكيد رقم المشترك' : 'تعذّر تأكيد الرمز');
      if (!r.ok && r.code == 'PAY_OTP_EXPIRED') _otpSent = false; // انتهت المهلة ⇒ يُرسل من جديد
    });
    if (r.ok) {
      _otpSent = false;
      _otpCodeCtrl.clear();
      await _load();
    }
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
    final res = await MergedOps.run(widget.sub, () => SubscribersApi.fetchActivationDataDetailed(idx));
    final data = res.data;
    if (!mounted) return;
    setState(() {
      _loading = false;
      _data = data;
      if (data == null) {
        // رفضٌ مقصود من الخادم (409 برسالةٍ عربيّة — مثل «لا سعر بيع لباقة … حدّده من «الباقات»» للمشروع الوطنيّ) يُعرض نصّه؛
        // وغيره الرسالة العامّة كما كانت.
        final m = res.message?.trim() ?? '';
        _loadError = res.status == 409 && m.isNotEmpty && m.length < 200 ? m : 'sheets.activate_load_failed'.tr();
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
        _applyPrefill();
      }
    });
    // أشهرٌ من الأمر الصوتيّ ⇒ معاينتها من الشركة كما لو اختارها بيده (مرّةً — وبلاها هذا السطر لا يفعل شيئاً)
    if (_voiceMonths) {
      _voiceMonths = false;
      if (data != null && _kitMonths > 1 && _quoteFor != _quoteKey) unawaited(_fetchQuote());
    }
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

  /// الوطنيّ (١٥ نوفمبر): `manager_balance` هنا «حدّ محفظة عضو الفريق» — ما يصرفه هذا المستخدم في البوّابة، لا رصيد الحساب الرئيسيّ
  /// (الخادم يضع العلَم) ⇒ السطر يُسمّى باسمه.
  bool get _managerBalanceIsLimit => _data?['manager_balance_is_limit'] == true;
  String get _managerBalanceLabel => _managerBalanceIsLimit ? 'حدّ محفظتك' : 'dashboard.manager_balance'.tr();
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
  /// الأشهر المسموحة (`months_options`) — أكثر من خيار ⇒ تظهر «مدّة التفعيل».
  List<int> get _monthsOpts {
    final v = _data?['months_options'];
    if (!_isKit || v is! List) return const [];
    return [for (final m in v) if (m is num && m == m.roundToDouble() && m >= 1) m.toInt()];
  }

  /// الأشهر الفعليّة: المختارة إن كانت مسموحة والدفع ليس بالبطاقة، وإلّا شهرٌ واحد.
  int get _kitMonths => _isKit && !_kitCard && !_kitCust && _monthsOpts.contains(_months) ? _months : 1;
  String get _quoteKey => '$_kitMonths|$_selectedPackageId';
  Map<String, dynamic>? get _liveQuote => _kitMonths > 1 && _quoteFor == _quoteKey ? _quote : null;

  /// عدّة أشهرٍ بلا معاينةٍ صالحة ⇒ لا تفعيل (كالموقع monthsBlocked).
  bool get _monthsBlocked {
    if (!_isKit || _kitMonths <= 1) return false;
    final q = _liveQuote;
    if (q == null) return true;
    final price = q['price'];
    return (q['blocked']?.toString().trim().isNotEmpty ?? false) || q['sale_price_missing'] == true || price is! num || price <= 0;
  }

  static String _monthsLabel(int m) => m == 1 ? 'شهر' : m == 2 ? 'شهران' : m <= 10 ? '$m أشهر' : '$m شهراً';

  Future<void> _fetchQuote() async {
    if (_kitMonths <= 1) return;
    final idx = widget.sub.idx;
    if (idx == null) return;
    final key = _quoteKey;
    setState(() {
      _quoting = true;
      _quoteErr = null;
    });
    final r = await MergedOps.run(widget.sub, () => SubscribersApi.activationQuote(idx, months: _kitMonths, profileId: _selectedPackageId));
    if (!mounted || key != _quoteKey) return;
    setState(() {
      _quoting = false;
      _quote = r.data;
      _quoteFor = r.data == null ? null : key;
      _quoteErr = r.data == null ? (r.message ?? 'تعذّرت معاينة ${_monthsLabel(_kitMonths)} — اختر مدّةً أخرى') : null;
    });
  }

  num get _elChargePrice {
    // عدّة أشهر: السعر من معاينة الخادم (الشهريّ × الأشهر) — وحتى تصل صفرٌ والتفعيل ممنوع (_monthsBlocked)
    if (_isKit && _kitMonths > 1) {
      final p = _liveQuote?['price'];
      return p is num && p > 0 ? p : 0;
    }
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

  num get _elSelectedPkgCost {
    if (_isKit && _kitMonths > 1) {
      final c = _liveQuote?['cost'];
      return c is num ? c : 0;
    }
    return _readNumOf(_elSelectedPkg, 'cost');
  }

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
      _cardMode &&
      (_cardDenied || (_cards.level == CardStockLevel.empty && !_railExternal && !_typedExternal) || _railPinBad || _typedPinBad);

  /// «التفعيل برقم البطاقة» (٢٣ نوفمبر — المالك: «هذه الشركات … تجبرهم على الكارتات. فاحنا نخلي العمليتين متاحة»؛ الخادم
  /// 8106977 والموقع cec2570): الخادم يقول `cards.typed` ⇒ «رقم البطاقة» كما في صفحة الساس. بلا مخزونٍ الرقم مطلوب، ومع مخزونٍ اختياريّ
  /// (الفارغ يُسحب كارتٌ من المخزون كما كان). طريق موقع الشحن له بطاقته الخارجيّة ([_rail]) فلا يجتمعان.
  bool get _typedCard => _rail == null && _cards.typed;
  String get _typedPin => _typedPinCtrl.text.trim();
  bool get _typedExternal => _typedCard && _cardMode && _typedPin.isNotEmpty;
  bool get _typedPinBad => _typedExternal && !RegExp(r'^[0-9A-Za-z-]{4,64}$').hasMatch(_typedPin);

  /// «طريق موقع الشحن» (فايبر الجزيرة): الخادم ينفّذ التفعيل عبر pay.jt.iq ويقول ذلك بـ`pay_rail` في بيانات التفعيل —
  /// الرصيد رصيد الموقع، والكارت بطاقات الوكيل فيه أو بطاقةٌ خارجيّة يكتب رقمها (٨ خانات). غيابه = كما كان.
  Map<String, dynamic>? get _rail {
    final r = _data?['pay_rail'];
    return r is Map && r['on'] == true ? Map<String, dynamic>.from(r) : null;
  }

  bool get _railCardField => _cardMode && _rail?['external_card'] == true;
  String get _railPin => _railPinCtrl.text.trim();
  bool get _railExternal => _rail != null && _cardMode && _railPin.isNotEmpty;
  bool get _railPinBad => _railExternal && !RegExp(r'^[A-Za-z0-9]{8}$').hasMatch(_railPin);

  /// موقع الشحن يطلب تأكيد رقم المشترك بالواتساب قبل تفعيله — يُؤكَّد من هنا ([_otpBlock]).
  bool get _railOtp => _rail?['requires_otp'] == true;

  /// سبب منع التفعيل عبر موقع الشحن (يقوله الموقع نفسه) — null بلا منع.
  String? get _railStop {
    final r = _rail;
    if (r == null) return null;
    if (r['requires_otp'] == true) {
      return 'موقع الشحن يطلب تأكيد رقم هاتف هذا المشترك بالواتساب قبل تفعيله.';
    }
    if (r['option'] == null) return 'باقة المشترك ليست بين باقات موقع الشحن — غيّر باقته ثمّ فعّل.';
    return null;
  }

  /// تسمية الزرّ — وسبب المنع عليه حين يُمنع الكارت (كشيت التمديد).
  String get _footerLabel {
    if (_cardOrder != null) return 'common.close'.tr();
    if (_done) return _printingReceipt ? 'sheets.done_printing'.tr() : 'common.done'.tr();
    if (_submitting && _kitCard) return 'جارٍ إنشاء رابط الدفع…';
    if (_submitting) return 'sheets.renewing'.tr();
    if (_kitCard) return 'إنشاء رابط الدفع';
    if (_kitCust) return 'تفعيل من محفظة المشترك';
    if (_outcomeUnclear) return 'sheets.activate_check_first'.tr();
    if (_pkgSwitcher) return 'sheets.renew_now'.tr(); // «تفعيل/تجديد الآن» (كارت ايرث لنك لا مخزون، وفايبر اكس من المحفظة)
    if (_railOtp) return 'أكّد رقم المشترك أوّلاً';
    if (_railStop != null) return 'غير متاح عبر موقع الشحن';
    if (!_cardMode) return 'sheets.renew_now'.tr();
    if (_cardDenied) return 'cards.not_allowed_short'.tr();
    if (_railPinBad) return 'رقم البطاقة ٨ خانات';
    if (_typedPinBad) return 'رقم البطاقة غير صالح';
    if (_cards.level == CardStockLevel.empty && !_railExternal && !_typedExternal) {
      return _typedCard ? 'اكتب رقم البطاقة' : 'cards.no_card_short'.tr();
    }
    return 'cards.renew_with_card'.tr();
  }

  bool get _canSubmit {
    if (_cardOrder != null) return true; // «إغلاق»
    if (_done) return false;
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
    if (_cardBlocked || _railStop != null) return false; // SAS4 فقط
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
    if (_cardOrder != null) {
      _closeCard();
      return;
    }
    // تفعّل للتوّ ⇒ لا تفعيل ثانٍ (الزرّ «تمّ» معطّل؛ وهذا لما يصل غيره — Enter على الحاسبة).
    if (_done) return;
    if (idx == null || _data == null || _cardBlocked || _railStop != null || _outcomeUnclear) return;
    final paymentType = switch (_pay) {
      _PayType.cash => 'cash',
      _PayType.partial => 'partial-cash',
      _PayType.debt => 'non-cash',
    };
    if (_fxMode && _kitCard) return _submitCard(idx, paymentType);
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
      // لحظة الضغط — منها يُسأل الخادم لاحقاً «هل أُرسلت رسالة التفعيل؟» (OpWaNotice).
      final pressedAt = DateTime.now();
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
        _done = result.ok;
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
      // النجاح، ثمّ تنبيه «لم يُسجَّل الدين» إن وقع، ثمّ نتيجة رسالة التفعيل (أُرسلت / لم تُرسل بسببها) — كلٌّ في دوره
      // على الطبقة العليا (تُلتقط قبل الإغلاق) فيبقى بعد إغلاق الشيت، تِلو النجاح لا فوقه (كشيت الإضافة).
      unawaited(OpWaNotice.show(
        context,
        sub: widget.sub,
        op: OpWaKind.activate,
        okText: 'sheets.renew_ok'.tr(),
        pressedAt: pressedAt,
        wa: result.wa,
        manual: manualMode,
        followUps: [
          if (result.debtWriteFailed)
            (
              text: result.debtWriteMessage ?? 'sheets.activate_debt_not_recorded'.tr(),
              duration: const Duration(seconds: 8),
            ),
        ],
      ));
      if (_printReceiptChecked) {
        setState(() => _printingReceipt = true);
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
        // ورقة سبب طابعة الوصولات تُفتح فوق هذه الورقة: تُنتظر قبل pop، وإلّا أغلقها pop بدل هذه (مراجعة 179).
        if (mounted) await showPrintResult(context, printed);
        if (mounted) setState(() => _printingReceipt = false);
      }
      if (!mounted) return;
      if (manualMode && result.waPreview != null) {
        await handleWaPreviewAfterOp(
          context: context,
          preview: result.waPreview!,
          opTitle: 'تأكيد التفعيل',
          sub: widget.sub,
        );
        if (!mounted) return;
      }
      Navigator.of(context).pop(true);
      return;
    }
    // لقطةٌ قبل الانتظار: الردّ يُقرأ بما أُرسل لا بما صار مختاراً بعده.
    final useCard = _cardMode;
    // رقم البطاقة: الخارجيّة (موقع الشحن) أو المكتوبة (شركات الكارتات) — مع «كارت» وحده؛ الفارغ ⇒ لا cardPin (سحبٌ من المخزون كما كان)
    final railPin = useCard && _railExternal && !_railPinBad
        ? _railPin
        : (useCard && _typedExternal && !_typedPinBad ? _typedPin : null);
    setState(() => _submitting = true);
    // لحظة الضغط — منها يُسأل الخادم لاحقاً «هل أُرسلت رسالة التفعيل؟» (OpWaNotice).
    final pressedAt = DateTime.now();
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
      cardPin: railPin,
    ));
    if (!mounted) return;
    setState(() {
      _submitting = false;
      _done = result.ok;
      // رفضٌ معروف يُحدّث الشيت نفسه، فلا تتكرّر الضغطة على الرفض نفسه.
      if (useCard && result.code == CardsApi.codeNoCards) {
        _cards = _cards.withAvailable(0);
      } else if (useCard && result.code == CardsApi.codeCardNotAllowed) {
        _cardDenied = true;
      } else if (SubscribersApi.activateUnclearCodes.contains(result.code)) {
        _outcomeUnclear = true;
      }
    });
    // شارة الكارتات للجلسة المفتوحة وحدها: كارت شركةٍ أخرى («كل الشركات») من مخزونها هي لا ينقص عدد المفتوحة (التحقّق الثاني
    // من 179) — مخزونها يُقرأ من قسمها.
    final openStock = useCard && await MergedMode.isOpenKey(widget.sub.companyKey);
    if (!mounted) return;
    if (_outcomeUnclear) {
      // ربّما تفعّل: القوائم تُحدَّث (يظهر الانتهاء الجديد إن نُفّذ)، وعدد
      // الكارتات لم يعد مضموناً فيُعاد طلبه بدل رسم رقمٍ قد يكون كاذباً.
      SubscriberEvents.notifyChange();
      if (openStock) CardsState.invalidate();
    }
    if (!result.ok) {
      showSheetSnack(context, _failureText(result.code, result.message),
          isError: true);
      return;
    }
    if (openStock) CardsState.consumeOne();
    SubscriberEvents.notifyChange();
    // النجاح ومعه نتيجة رسالة التفعيل (أُرسلت / لم تُرسل بسببها) — يبقى بعد إغلاق الشيت.
    unawaited(OpWaNotice.show(
      context,
      sub: widget.sub,
      op: OpWaKind.activate,
      okText: useCard ? _cardOkText(result.card) : 'sheets.renew_ok'.tr(),
      okDuration: Duration(seconds: useCard ? 5 : 3),
      pressedAt: pressedAt,
      wa: result.wa,
      manual: manualMode,
    ));
    // 2026-07-13: طباعة تلقائية بعد النجاح لو الـcheckbox مُفعَّل.
    if (_printReceiptChecked) {
      setState(() => _printingReceipt = true);
      final effPrice = _effectivePrice > 0 ? _effectivePrice : _userPrice;
      final printed = await ReceiptService.printActivation(
        sub: widget.sub,
        price: effPrice,
        pay: _receiptPay,
        partialAmount: _partialAmount,
        packageName: _profileName,
        packageId: _profileId,
      );
      // ورقة سبب طابعة الوصولات تُفتح فوق هذه الورقة: تُنتظر قبل pop، وإلّا أغلقها pop بدل هذه (مراجعة 179).
      if (mounted) await showPrintResult(context, printed);
      if (mounted) setState(() => _printingReceipt = false);
    }
    if (!mounted) return;
    // 2026-08-26: preview WA بعد نجاح التفعيل.
    if (manualMode) {
      if (result.waPreview != null) {
        await handleWaPreviewAfterOp(
          context: context,
          preview: result.waPreview!,
          opTitle: 'تأكيد التفعيل',
          sub: widget.sub,
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
        // «كل الشركات»: شركته مع اسمه — المال يُكتب لشركةٍ يراها قبل التأكيد
        subtitle: MergedOps.sheetSubtitle(widget.sub),
        onClose: _cardOrder != null ? _closeCard : () => Navigator.of(context).pop(),
      ),
      footer: SheetFooterBar(
        label: _footerLabel,
        icon: _cardOrder != null ? LucideIcons.x : (_kitCard ? LucideIcons.creditCard : LucideIcons.refreshCw),
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
        children: _cardOrder != null ? _cardPayBody(_cardOrder!) : _buildBody(),
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
      if (_voiceApplied.isNotEmpty) ...[
        _CardNote(
          key: const ValueKey('activate-voice-note'),
          tone: AppTone.brand,
          icon: LucideIcons.mic,
          text: 'من الأمر الصوتي: ${_voiceApplied.join(' · ')} — راجِعها قبل التأكيد',
          maxLines: 3,
        ),
        const SizedBox(height: Sp.sm),
      ],
      if (_voiceSkipped.isNotEmpty) ...[
        _CardNote(
          key: const ValueKey('activate-voice-skipped'),
          tone: AppTone.warning,
          icon: LucideIcons.mic,
          text: 'لم يُطبَّق من الأمر الصوتي: ${_voiceSkipped.join('، ')}',
          maxLines: 3,
        ),
        const SizedBox(height: Sp.sm),
      ],
      SheetPlanCard(
        planLabel: 'subscribers.label_package'.tr(),
        planName: planName,
        durationLabel: _isKit && _kitMonths > 1 ? _monthsLabel(_kitMonths) : ((_duration ?? '').isEmpty ? null : _duration),
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
                // «ما يراه الموظّف»: الدين مخفيّ ⇒ «مخفي»؛ رصيد الصفحة ونقاطها مخفيّان ⇒ لا صفّ
                if (Sees.debts)
                  SheetRowData(
                    label: _currentBalance < 0
                        ? 'sheets.current_debt'.tr()
                        : 'sheets.current_credit'.tr(),
                    value: '${formatIQD(_currentBalance.abs().round())} $cur',
                    valueColor: _currentBalance < 0
                        ? AppColors.error
                        : AppColors.brandAccent,
                    strong: true,
                  )
                else
                  SheetRowData(label: 'الدين والرصيد', value: kHiddenWord, valueColor: AppColors.textMid, strong: true),
                if (Sees.balance)
                  SheetRowData(
                    label: _managerBalanceLabel,
                    value: '${formatIQDSigned(_managerBalance.round())} $cur',
                    valueColor: _managerBalance < 0 ? AppColors.error : null,
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
          // «ما يراه الموظّف»: الدين مخفيّ ⇒ «مخفي»؛ رصيد الصفحة ونقاطها مخفيّان ⇒ لا صفّ
          if (Sees.debts)
            SheetRowData(
              label: _currentBalance < 0
                  ? 'sheets.current_debt'.tr()
                  : 'sheets.current_credit'.tr(),
              value: '${formatIQD(_currentBalance.abs().round())} $cur',
              valueColor:
                  _currentBalance < 0 ? AppColors.error : AppColors.brandAccent,
              strong: true,
            )
          else
            SheetRowData(label: 'الدين والرصيد', value: kHiddenWord, valueColor: AppColors.textMid, strong: true),
          if (Sees.balance)
            SheetRowData(
              label: _managerBalanceLabel,
              // بإشارته (١٦ نوفمبر): رصيدٌ سالب في الساس كان يُعرض رصيداً موجوداً — [formatIQD] يُسقط الناقص
              value: '${formatIQDSigned(_managerBalance.round())} $cur',
              valueColor: _managerBalance < 0 ? AppColors.error : null,
            ),
          if (_rewardPoints > 0 && Sees.balance)
            SheetRowData(
              label: 'sheets.points'.tr(),
              value: formatIQD(_rewardPoints.round()),
              valueColor: AppColors.warningFill,
            ),
        ],
      ),
      // تنبيه المزوّد قبل الدفع (المشروع الوطنيّ، ١ نوفمبر): «المشترك موقوف في البوّابة — التفعيل يمدّد اشتراكه لكنّه يبقى
      // موقوفاً حتى تضغط «تشغيل»» — البوّابة نفسها لا ترفع التعليق بالشراء. تنبيهٌ وحده، لا يمسّ المال.
      if (_providerNotice != null) ...[
        const SizedBox(height: 14),
        _CardNote(tone: AppTone.warning, icon: LucideIcons.pause, text: _providerNotice!, maxLines: 4),
      ],
      if (_isEarthlink) ...[
        const SizedBox(height: 14),
        _elPackageSection(),
        const SizedBox(height: 14),
        _elMethodSection(),
      ] else if (_fxMode) ...[
        const SizedBox(height: 14),
        _elPackageSection(),
        if (_cardPayAvailable || _custWallet != null) ...[
          const SizedBox(height: 14),
          _kitPaySection(),
        ],
        if (_isKit && _monthsOpts.length > 1 && !_kitCard && !_kitCust) ...[
          const SizedBox(height: 14),
          _monthsSection(),
        ],
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
      if (_kitCust) ...[
        const SizedBox(height: 14),
        const _CardNote(
          tone: AppTone.brand,
          icon: LucideIcons.walletCards,
          text: 'يُدفع للشركة من محفظة المشترك نفسه — لا نقداً ولا ديناً عندك',
          maxLines: 3,
        ),
      ] else ...[
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
      // «ما يراه الموظّف»: الدين بعد التفعيل يكشف الدين قبله ⇒ يُخفى معه
      if (Sees.debts) ...[
        const SizedBox(height: 14),
        SheetResultBanner(
          icon: LucideIcons.arrowLeft,
          label: after < 0
              ? 'sheets.debt_after_activation'.tr()
              : 'sheets.credit_after_activation'.tr(),
          value: '${formatIQD(after.abs().round())} $cur',
          tone: after < 0 ? AppTone.danger : AppTone.brand,
        ),
      ],
      ],
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
                // شركات الكارتات: «كارت (0)» يوحي بالمنع والرقم يُكتب ⇒ «كارت» وحده حين لا مخزون
                available == null || (_typedCard && available == 0)
                    ? 'cards.method_card'.tr()
                    : 'cards.method_card_n'.tr(namedArgs: {'n': '$available'}),
              ],
              icons: const [LucideIcons.wallet, LucideIcons.ticket],
              selectedIndex: _cardMode ? 1 : 0,
              enabled: !_submitting,
              onSelect: (i) => setState(
                  () => _method = i == 1 ? _Method.card : _Method.credit),
            ),
          if (_cardMode && !_methods.canChoose && _typedCard) ...[
            Text(
              'التفعيل بالبطاقة — اكتب رقمها تحت (حسابك لا يدعم الدفع من الرصيد).',
              key: const ValueKey('typed-card-only'),
              style: AppType.micro(color: AppColors.textMid),
            ),
            const SizedBox(height: Sp.sm),
          ],
          if (_cardMode) ...[
            if (_methods.canChoose) const SizedBox(height: Sp.sm),
            _cardNote(),
          ],
          if (_typedCard && _cardMode) ...[
            const SizedBox(height: Sp.sm),
            Text(
              (available ?? 0) > 0 ? 'رقم البطاقة (اتركه فارغاً ليُسحب كارت من مخزونك)' : 'رقم البطاقة',
              style: AppType.micro(color: AppColors.textMid),
            ),
            const SizedBox(height: Sp.xs),
            SheetBox(
              focused: _typedPinCtrl.text.isNotEmpty,
              child: TextField(
                key: const ValueKey('typed-card-pin'),
                controller: _typedPinCtrl,
                enabled: !_submitting,
                keyboardType: TextInputType.visiblePassword,
                autocorrect: false,
                enableSuggestions: false,
                textDirection: ui.TextDirection.ltr,
                inputFormatters: const [_LatinCardPinFormatter()],
                onChanged: (_) => setState(() {}),
                style: AppType.input(),
                decoration: InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                  hintText: 'كما هو على البطاقة',
                  hintStyle: AppType.input(color: AppColors.textPlaceholder),
                ),
              ),
            ),
          ],
          if (_railCardField) ...[
            const SizedBox(height: Sp.sm),
            SheetBox(
              focused: _railPinCtrl.text.isNotEmpty,
              child: TextField(
                key: const ValueKey('rail-card-pin'),
                controller: _railPinCtrl,
                enabled: !_submitting,
                keyboardType: TextInputType.visiblePassword,
                autocorrect: false,
                enableSuggestions: false,
                maxLength: 8,
                textDirection: ui.TextDirection.ltr,
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]'))],
                onChanged: (_) => setState(() {}),
                style: AppType.input(),
                decoration: InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  counterText: '',
                  contentPadding: EdgeInsets.zero,
                  hintText: 'رقم بطاقة خارجيّة (٨ خانات)',
                  hintStyle: AppType.input(color: AppColors.textPlaceholder),
                ),
              ),
            ),
          ],
          if (_railOtp) ...[
            const SizedBox(height: Sp.sm),
            _otpBlock(),
          ] else if (_railStop != null) ...[
            const SizedBox(height: Sp.sm),
            _CardNote(tone: AppTone.danger, icon: LucideIcons.triangleAlert, text: _railStop!, maxLines: 4),
          ],
        ],
      ),
    );
  }

  /// «تأكيد رقم المشترك بالواتساب» (المالك ١٤ نوفمبر: «تمام سويها»): رقم المشترك (من الساس، يُعدَّل) ⇒ «أرسل الرمز» ⇒ الرمز الذي
  /// وصله ⇒ «تأكيد» ⇒ تُعاد قراءة النافذة فيُفعَّل كالعادة. ما يرفضه الموقع يظهر بنصّه تحت الخانة.
  Widget _otpBlock() {
    final cs = Theme.of(context).colorScheme;
    Widget field({required Key key, required TextEditingController c, required String hint, required bool enabled, required int max}) =>
        SheetBox(
          focused: c.text.isNotEmpty,
          child: TextField(
            key: key,
            controller: c,
            enabled: enabled,
            keyboardType: TextInputType.number,
            textDirection: ui.TextDirection.ltr,
            maxLength: max,
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+٠-٩]'))],
            onChanged: (_) => setState(() {}),
            style: AppType.input(),
            decoration: InputDecoration(
              isDense: true,
              border: InputBorder.none,
              counterText: '',
              contentPadding: EdgeInsets.zero,
              hintText: hint,
              hintStyle: AppType.input(color: AppColors.textPlaceholder),
            ),
          ),
        );
    final busy = _otpBusy || _submitting;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _CardNote(
          tone: AppTone.warning,
          icon: LucideIcons.messageCircle,
          text: 'موقع الشحن يطلب تأكيد رقم هاتف المشترك بالواتساب قبل تفعيله: يُرسل رمزٌ لرقمه، والمشترك يخبرك به.',
          maxLines: 4,
        ),
        const SizedBox(height: Sp.sm),
        field(key: const ValueKey('rail-otp-phone'), c: _otpPhoneCtrl, hint: 'رقم هاتف المشترك 07…', enabled: !busy && !_otpSent, max: 14),
        const SizedBox(height: Sp.sm),
        if (!_otpSent)
          FilledButton.icon(
            key: const ValueKey('rail-otp-send'),
            onPressed: busy || _otpPhoneCtrl.text.trim().isEmpty ? null : _otpSend,
            icon: _otpBusy
                ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: cs.onPrimary))
                : const Icon(LucideIcons.send, size: 18),
            label: const Text('أرسل الرمز'),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.brandAccent,
              foregroundColor: AppColors.onBrand,
              minimumSize: const Size.fromHeight(44),
            ),
          )
        else ...[
          field(key: const ValueKey('rail-otp-code'), c: _otpCodeCtrl, hint: 'الرمز الذي وصل المشترك', enabled: !busy, max: 8),
          const SizedBox(height: Sp.sm),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  key: const ValueKey('rail-otp-confirm'),
                  onPressed: busy || _otpCodeCtrl.text.trim().isEmpty ? null : _otpConfirm,
                  icon: _otpBusy
                      ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: cs.onPrimary))
                      : const Icon(LucideIcons.check, size: 18),
                  label: const Text('تأكيد'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.brandAccent,
                    foregroundColor: AppColors.onBrand,
                    minimumSize: const Size.fromHeight(44),
                  ),
                ),
              ),
              const SizedBox(width: Sp.sm),
              TextButton(
                key: const ValueKey('rail-otp-again'),
                onPressed: busy ? null : () => setState(() { _otpSent = false; _otpMsg = null; }),
                child: const Text('رقمٌ آخر'),
              ),
            ],
          ),
        ],
        if (_otpMsg != null) ...[
          const SizedBox(height: Sp.sm),
          _CardNote(
            tone: _otpMsgError ? AppTone.danger : AppTone.success,
            icon: _otpMsgError ? LucideIcons.triangleAlert : LucideIcons.circleCheck,
            text: _otpMsg!,
            maxLines: 4,
          ),
        ],
      ],
    );
  }

  /// تنبيهٌ من المزوّد يُعرض قبل الدفع (`provider_notice` في بيانات التفعيل) — null بلا تنبيه.
  String? get _providerNotice {
    final n = _data?['provider_notice']?.toString().trim() ?? '';
    return n.isEmpty || n.length > 300 ? null : n;
  }

  /// الدفع بالبطاقة متاحٌ لهذا الحساب (الخادم يقول card_payment) — ومن «كل الشركات» أيضاً (١ نوفمبر، المالك: «بعض وكلاء الوطني
  /// مايطلعلهم التفعيل ماستر كارد»): البدء والحالة بـMergedOps.run الموجَّه، والخادم يوجّه card-orders/:id (08db690) كالموقع (6631f71).
  bool get _cardPayAvailable => _isKit && _data?['card_payment'] == true;
  bool get _kitCard => _cardPayAvailable && _payByCard && !_payByCustWallet;

  /// محفظة المشترك عند الشركة (الخادم يقولها لمن فُتحت له) — null = غير متاحة.
  CustomerWalletInfo? get _custWallet => _isKit ? CustomerWalletInfo.of(_data?['customer_wallet']) : null;
  bool get _kitCust => _custWallet != null && _payByCustWallet;

  /// اختيار «الدفع لـ<الشركة>»: محفظتي · بطاقة · محفظة المشترك — والأخيرة برصيدٍ لا يكفي ⇒ «شحن المحفظة؟» لا اختيارٌ صامت.
  Future<void> _onKitPay(String k) async {
    if (k == 'cust') {
      final cw = _custWallet;
      if (cw == null) return;
      if (cw.enough == false) return _offerCustTopup(cw);
      setState(() {
        _payByCard = false;
        _payByCustWallet = true;
      });
      return;
    }
    setState(() {
      _payByCard = k == 'card';
      _payByCustWallet = false;
    });
    // عائدٌ إلى «محفظتي» بأشهرٍ مختارة ⇒ معاينتها من جديد (البطاقة ومحفظة المشترك شهرٌ واحد)
    if (k == 'mine' && _kitMonths > 1 && _quoteFor != _quoteKey) _fetchQuote();
  }

  /// رصيد محفظة المشترك لا يكفي ⇒ «شحن المحفظة؟» ثمّ نافذة «تعبئة محفظة المشترك» نفسها، وبعدها يُقرأ الرصيد من جديد ويُختار
  /// «محفظة المشترك» إن صار يكفي.
  Future<void> _offerCustTopup(CustomerWalletInfo cw) async {
    final idx = widget.sub.idx;
    final cur = 'common.currency'.tr();
    final short = cw.shortBy;
    if (!cw.topup || idx == null) {
      showSheetSnack(
        context,
        'رصيد محفظة المشترك لا يكفي${short != null ? ' (ينقصه ${formatIQD(short.round())} $cur)' : ''} — وشحن المحفظة غير متاحٍ لحسابك بعد',
        isError: true,
      );
      return;
    }
    final go = await showConfirmSheet(
      context,
      title: 'رصيد محفظة المشترك لا يكفي',
      message: [
        if (cw.balance != null) 'رصيده ${formatIQD(cw.balance!.round())} $cur',
        if (cw.price != null) 'يُخصم للتفعيل ${formatIQD(cw.price!.round())} $cur',
        'شحن المحفظة الآن؟',
      ].join('\n'),
      confirmLabel: 'شحن المحفظة',
      icon: LucideIcons.walletCards,
    );
    if (go != true || !mounted) return;
    // شركة صفّ المشترك (١٥ نوفمبر): النافذة لشركته هو في «كل الشركات» — كانت تسأل الصفحة المفتوحة فتقول «غير موجود»
    final r = await showNationalWalletTopupSheet(context, sid: idx, companyKey: widget.sub.companyKey);
    if (!mounted || r == null) return;
    await _load();
    if (!mounted) return;
    final now = _custWallet;
    if (now != null && now.enough != false) {
      setState(() {
        _payByCard = false;
        _payByCustWallet = true;
      });
    }
  }

  /// «الدفع لـ<الشركة>»: «محفظتي» (من رصيدك في البوّابة) أو «بطاقة» (ماستر كارد/فيزا — صفحة دفع).
  Widget _kitPaySection() {
    final cw = _custWallet;
    final keys = <String>['mine', if (_cardPayAvailable) 'card', if (cw != null) 'cust'];
    final sel = _kitCust ? keys.indexOf('cust') : (_kitCard ? keys.indexOf('card') : 0);
    return SheetSection(
      label: 'الدفع لـ$_kitName',
      gap: Sp.sm,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SheetChoiceTiles(
            labels: [for (final k in keys) switch (k) { 'card' => 'بطاقة', 'cust' => 'محفظة المشترك', _ => 'محفظتي' }],
            icons: [
              for (final k in keys)
                switch (k) { 'card' => LucideIcons.creditCard, 'cust' => LucideIcons.walletCards, _ => LucideIcons.wallet },
            ],
            selectedIndex: sel < 0 ? 0 : sel,
            enabled: !_submitting,
            onSelect: (i) => _onKitPay(keys[i]),
          ),
          if (cw != null) ...[
            const SizedBox(height: Sp.xs),
            Text(
              [
                cw.balance != null
                    ? 'رصيد محفظة المشترك ${formatIQD(cw.balance!.round())} ${'common.currency'.tr()}'
                    : 'تعذّرت قراءة رصيد محفظة المشترك — يُتحقَّق منه عند التفعيل',
                if (cw.enough == false) 'لا يكفي — اضغط «محفظة المشترك» لشحنها',
              ].join(' · '),
              style: AppType.muted(color: cw.enough == false ? AppColors.warningFill : AppColors.textMid)
                  .copyWith(fontSize: 12.5, height: 1.4),
            ),
          ],
          if (_kitCard) ...[
            const SizedBox(height: Sp.xs),
            Text(
              'يُنشأ رابط دفعٍ تفتحه وتدفع منه بالبطاقة؛ يتفعّل المشترك ويُسجَّل الدين عندنا حين يكتمل الدفع.',
              style: AppType.muted(color: AppColors.textMid).copyWith(fontSize: 12.5, height: 1.4),
            ),
          ],
        ],
      ),
    );
  }

  /// «مدّة التفعيل» (الشركة المُضافة، `months_options`): شهرٌ أو أكثر — والسعر والكلفة والانتهاء من معاينة الشركة نفسها.
  Widget _monthsSection() {
    final q = _liveQuote;
    final m = _kitMonths;
    final cur = 'common.currency'.tr();
    Widget line(String text, {Color? color}) => Padding(
          padding: const EdgeInsets.only(top: Sp.xs),
          child: Text(text, style: AppType.muted(color: color ?? AppColors.textMid).copyWith(fontSize: 12.5, height: 1.4)),
        );
    final offers = q?['offers'] is List ? (q!['offers'] as List).whereType<Map>().toList() : const <Map>[];
    final disc = q?['offers_discount'];
    return SheetSection(
      label: 'مدّة التفعيل',
      gap: Sp.sm,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final o in _monthsOpts)
                ChoiceChip(
                  label: Text(_monthsLabel(o)),
                  selected: m == o,
                  onSelected: _submitting
                      ? null
                      : (_) {
                          setState(() => _months = o);
                          if (o > 1 && _quoteFor != _quoteKey) _fetchQuote();
                        },
                  labelStyle: AppType.label(color: m == o ? AppColors.brand : AppColors.textHi),
                  selectedColor: AppColors.brandSoftBg,
                  backgroundColor: AppColors.surface,
                  side: BorderSide(color: m == o ? AppColors.brandSoftBorder : AppColors.border),
                  showCheckmark: false,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(R.pill)),
                ),
            ],
          ),
          if (m > 1) ...[
            if (_quoting && q == null)
              line('جارٍ حساب كلفة ${_monthsLabel(m)} من $_kitName…')
            else if (q == null)
              line(_quoteErr ?? 'تعذّرت معاينة ${_monthsLabel(m)} — اختر مدّةً أخرى', color: AppColors.error)
            else if ((q['blocked']?.toString().trim().isNotEmpty ?? false))
              line(q['blocked'].toString(), color: AppColors.warningOnSoft)
            else if (q['sale_price_missing'] == true)
              line('لا سعر بيعٍ للمشترك لهذه الباقة — حدّده من «الباقات» أوّلاً', color: AppColors.warningOnSoft)
            else ...[
              line('سعر المشترك لـ${_monthsLabel(m)}: ${formatIQD(((q['price'] as num?) ?? 0).round())} $cur'),
              if (q['cost'] is num) line('الكلفة من رصيدك عند $_kitName: ${formatIQD((q['cost'] as num).round())} $cur'),
              if (disc is num && disc > 0) line('خصم عروض الشركة: ${formatIQD(disc.round())} $cur', color: AppColors.success),
              for (final o in offers.take(2))
                if ((o['description']?.toString().trim().isNotEmpty ?? false)) line('• ${o['description']}', color: AppColors.success),
              if (q['new_expiration'] != null && q['new_expiration'].toString().isNotEmpty)
                line('ينتهي في: ${q['new_expiration']}'),
            ],
          ],
        ],
      ),
    );
  }

  /// رابط الدفع: يُنشأ (أو رابط الطلب المفتوح نفسه) ثمّ يُفتح ويُتابع الطلب.
  Future<void> _submitCard(String idx, String paymentType) async {
    setState(() => _submitting = true);
    final r = await MergedOps.run(widget.sub, () => KitCardApi.start(
          idx: idx,
          paymentType: paymentType,
          activationData: _data!,
          partialAmount: _pay == _PayType.partial ? _partialAmount : null,
        ));
    if (!mounted) return;
    setState(() => _submitting = false);
    if (!r.ok) {
      // طلبٌ مفتوح بلا رقمٍ يُتابَع (قيد الإنشاء، أو مدفوعٌ من خادمٍ أقدم): رسالة الخادم كما هي — حالٌ لا خطأ.
      final msg = r.noReply
          ? 'انقطع الاتّصال قبل الردّ — أعد المحاولة: إن كان الرابط أُنشئ يعود نفسه (لا خصم بلا دفع)'
          : (r.message ?? _failureText(r.code, null));
      showSheetSnack(context, msg, isError: !r.open, duration: Duration(seconds: r.open ? 6 : 3));
      return;
    }
    // طلبٌ مفتوح (CARD_ORDER_OPEN) ⇒ لوحته نفسها تقول حاله وجملة الخادم فيها — لا تنبيهٌ فوقها يغطّي «إغلاق»، ولا تُفتح صفحة
    // الدفع وحدها: ربّما دفع الوكيل ولم يرجع رجوعه، والمدفوع (paid) لا رابط له أصلاً — «لا تدفع مرّةً ثانية».
    setState(() {
      _cardOrder = _CardOrder(
        order: r.orderNumber!,
        url: r.paymentUrl,
        status: r.paid ? 'paid' : 'link',
        cost: r.cost,
        price: r.price,
        note: r.open ? r.message : null,
      );
      _cardSince = DateTime.now();
    });
    _startCardPoll();
    if (r.open) {
      unawaited(_pollCard()); // المبلغ والحال الآن — لا بعد ٤ث
    } else {
      unawaited(_openPayPage());
    }
  }

  /// «محاولة جديدة» بعد طلبٍ لم يكتمل (فشل/انتهى/رُفضت بطاقته): يعود الشيت إلى نموذج التفعيل — والخادم يرفض طلباً ثانياً ما دام
  /// الأوّل مفتوحاً.
  void _newCardAttempt() {
    _cardPoll?.cancel();
    setState(() {
      _cardOrder = null;
      _cardSince = null;
    });
  }

  Future<void> _openPayPage() async {
    final url = _cardOrder?.url;
    if (url == null) return;
    var ok = false;
    try {
      ok = await kitCardLauncher(Uri.parse(url));
    } catch (_) {
      ok = false;
    }
    if (!ok && mounted) showSheetSnack(context, 'تعذّر فتح صفحة الدفع — اضغط «افتح صفحة الدفع»', isError: true);
  }

  void _startCardPoll() {
    _cardPoll?.cancel();
    _cardPoll = Timer.periodic(const Duration(seconds: 4), (_) => _pollCard());
  }

  Future<void> _pollCard() async {
    final o = _cardOrder;
    if (o == null || !KitCardApi.live.contains(o.status)) {
      _cardPoll?.cancel();
      return;
    }
    if (_cardSince != null && DateTime.now().difference(_cardSince!) > const Duration(minutes: 70)) {
      _cardPoll?.cancel();
      return;
    }
    final st = await MergedOps.run(widget.sub, () => KitCardApi.status(o.order));
    final cur = _cardOrder;
    // ردٌّ متأخّر بعد «محاولة جديدة» أو بعد حسم الطلب لا يمسّه.
    if (!mounted || st == null || cur == null || cur.order != o.order || !KitCardApi.live.contains(cur.status)) return;
    setState(() => _cardOrder = cur.withStatus(st));
    if (st.status == 'applied') {
      _cardPoll?.cancel();
      await _cardApplied();
    } else if (!KitCardApi.live.contains(st.status)) {
      _cardPoll?.cancel();
    }
  }

  /// إغلاق لوحة الطلب: تفعّل ⇒ true. ودينٌ لم يُكتب عندنا ⇒ تنبيهه يبقى بعد الإغلاق (على الطبقة العليا، كمسار المحفظة) — لا فوق
  /// اللوحة يغطّي «إغلاق».
  void _closeCard() {
    final o = _cardOrder;
    final rootOverlay = Overlay.maybeOf(context, rootOverlay: true);
    Navigator.of(context).pop(o?.status == 'applied');
    if (o != null && o.status == 'applied' && o.debtWriteFailed && rootOverlay != null) {
      unawaited(showSheetSnackOn(rootOverlay, _cardDebtLostText, isError: true, duration: const Duration(seconds: 8)));
    }
  }

  /// حُسم بالتفعيل ⇒ كمسار المحفظة: تحديث القوائم + الوصل (إن طُلب) + إغلاق. والدين الذي لم يُكتب عندنا (`debt_write_failed`)
  /// لا يُقال عنه «سُجّل عندنا»: اللوحة تبقى مفتوحةً بتنبيهها حتى يغلقها الوكيل بنفسه، والتنبيه يبقى بعد الإغلاق ([_closeCard]).
  /// وكذا دينٌ في شكّ (ربّما، تفعيلٌ آخر في سجلّنا، حالٌ لا يعرفها التطبيق — [_CardOrder.debtSure]): لوحته بتنبيهها، بلا «سُجّل عندنا».
  Future<void> _cardApplied() async {
    setState(() => _done = true);
    SubscriberEvents.notifyChange();
    final unsure = !(_cardOrder?.debtSure ?? true);
    final rootOverlay = Overlay.maybeOf(context, rootOverlay: true);
    if (rootOverlay != null && !unsure) {
      unawaited(showSheetSnackOn(rootOverlay, 'تمّ الدفع بالبطاقة وتفعّل المشترك — سُجّل عندنا', isError: false));
    }
    if (_printReceiptChecked) {
      // شروط الطلب نفسه حين يقولها الخادم (طلبٌ مفتوحٌ سابق قد يختلف عن اختيار الشيت الآن)
      final o = _cardOrder;
      final printed = await ReceiptService.printActivation(
        sub: widget.sub,
        price: o?.price ?? _elChargePrice,
        pay: switch (o?.paymentType) {
          'cash' => ReceiptPay.cash,
          'non-cash' => ReceiptPay.credit,
          'partial-cash' => ReceiptPay.partial,
          _ => _receiptPay,
        },
        partialAmount: _partialAmount,
        packageName: _elSelectedPkg?['name']?.toString() ?? _profileName,
      );
      // ورقة سبب طابعة الوصولات تُفتح فوق هذه الورقة: تُنتظر قبل pop، وإلّا أغلقها pop بدل هذه (مراجعة 179).
      if (mounted) await showPrintResult(context, printed);
    }
    if (!mounted || unsure) return;
    Navigator.of(context).pop(true);
  }

  static const _cardDebtLostText = 'تمّ الدفع بالبطاقة وتفعّل المشترك، لكن لم يُسجَّل الدين في دفترنا — سجّله يدويّاً';

  /// لوحة طلب الدفع: الحالة كما يقولها الخادم، وما يُدفع، ورقم الطلب، و«افتح صفحة الدفع» ما دام الرابط قائماً. وما يقوله الخادم عن
  /// الدين عندنا (`debt_state`) يُقال كما هو — لا «سُجّل» لدينٍ لم يُكتب ولا «لم يُسجَّل» لدينٍ ربّما كُتب، ولا «سجّله يدويّاً» لتفعيلٍ
  /// آخر في سجلّنا أو لحالٍ لا يعرفها التطبيق — وانتهاءٌ بلا رجوعٍ من صفحة الدفع (`no_return`) لا يُسمّى «بلا دفع»: تنبيهٌ فوق «محاولة
  /// جديدة» ألّا يدفع ثانيةً قبل أن يفحص. ورابطٌ سحبه الخادم بعد سؤاله (رُفضت البطاقة) «لم يكتمل» بـ«محاولة جديدة»، والمتابعة باقية:
  /// نجاحٌ لاحق من صفحة الدفع نفسها يُحيي الطلب.
  List<Widget> _cardPayBody(_CardOrder o) {
    final cur = 'common.currency'.tr();
    final st = o.status;
    // رجع الدفع مرفوضاً (Status=1): الطلب `link` بلا رابطٍ بعد سؤال الخادم — لا «بانتظار الدفع» ولا «يُسجَّل تلقائيّاً»
    final declined = st == 'link' && o.polled && o.url == null;
    final waiting = !declined && (st == 'link' || st == 'creating');
    final ended = declined || st == 'failed' || st == 'expired';
    final (text, tone, icon) = switch (st) {
      // ٨ نوفمبر: «فشل» البنك لا يُوثَق به (الطلب ١٥ رجع فاشلاً وخُصم وتفعّل بعد ٥ دقائق) — لا «لم يُخصم شيء» فيدفع الوكيل مرّتين.
      'link' when declined => ('البنك لم يؤكّد الدفع — قد يكون خُصم؛ ننتظر ونفعّل تلقائيّاً. لا تدفع مرّةً ثانية قبل ١٠ دقائق',
          AppColors.warning, LucideIcons.triangleAlert),
      'link' || 'creating' => ('بانتظار الدفع بالبطاقة…', AppColors.textMid, LucideIcons.loader),
      'paid' || 'applying' => ('تمّ الدفع — جارٍ تفعيل المشترك…', AppColors.brandAccent, LucideIcons.loader),
      'applied' => ('تمّ التفعيل ✓', AppColors.brandAccent, LucideIcons.circleCheck),
      'failed' => ('لم يكتمل الدفع — لم يظهر خصمٌ خلال ساعة؛ افحص كشف بطاقتك قبل أيّ إعادة', AppColors.error, LucideIcons.triangleAlert),
      'expired' when o.noReturn => ('انتهى رابط الدفع ولم يصلنا رجوعٌ من صفحة الدفع', AppColors.warning, LucideIcons.triangleAlert),
      'expired' => ('انتهى رابط الدفع بلا دفع', AppColors.error, LucideIcons.triangleAlert),
      _ when o.paidSeen => ('وصلنا أنّ الدفع تمّ ولم يظهر التفعيل — افحص المشترك في $_kitName قبل أيّ إعادة', AppColors.warning,
          LucideIcons.triangleAlert),
      _ => ('تعذّر التأكّد من النتيجة — افحص المشترك في $_kitName قبل أيّ إعادة', AppColors.warning, LucideIcons.triangleAlert),
    };
    final payType = switch (o.paymentType) {
      'cash' => 'sheets.pay_cash'.tr(),
      'non-cash' => 'sheets.pay_debt'.tr(),
      'partial-cash' => 'sheets.pay_partial'.tr(),
      _ => null,
    };
    // حال الدين عندنا بعد الحسم — من الخادم وحده. «سجّله يدويّاً» لدينٍ لم يُكتب يقيناً، أو لخادمٍ أقدم لا يقول حاله (النصّ القديم)؛
    // وتفعيلٌ آخر في سجلّنا منذ الطلب (other-recorded) وحالٌ لا يعرفها التطبيق: راجع قبل أيّ تسجيل — لا تسجيلٌ مكرّر.
    final debtNote = switch (st) {
      'applied' when o.debtWriteFailed => (AppTone.danger, 'لم يُسجَّل الدين في دفترنا — سجّله يدويّاً من «إضافة دين»'),
      _ when o.debt == KitCardDebt.otherRecorded && !KitCardApi.live.contains(st) =>
        (AppTone.warning, 'في سجلّنا تفعيلٌ آخر لهذا المشترك منذ الطلب — لا تسجّل ديناً يدويّاً قبل مراجعة حركاته وديونه'),
      'applied' || 'unknown' when o.debt == KitCardDebt.maybe =>
        (AppTone.warning, 'ربّما سُجّل الدين عندنا — افحص كشف المشترك قبل أن تسجّله يدويّاً (لا تسجّله مرّتين)'),
      'applied' || 'unknown' when o.debt == KitCardDebt.unknown =>
        (AppTone.warning, 'ربّما سُجّل الدين — راجع ديون المشترك قبل أيّ تسجيلٍ يدويّ'),
      'unknown' => (AppTone.warning, 'لم يُسجَّل دينٌ لهذا الطلب — إن تفعّل المشترك بهذا الدفع وليس تفعيله في كشفه فسجّله يدويّاً'),
      _ => null,
    };
    final footNote = switch (st) {
      _ when declined => '',
      _ when KitCardApi.live.contains(st) && (st == 'paid' || st == 'applying') =>
        'لا تدفع مرّةً ثانية — يمكنك إغلاق النافذة، يُسجَّل التفعيل والدين عندنا تلقائيّاً حين يتفعّل.',
      _ when KitCardApi.live.contains(st) => 'يمكنك إغلاق النافذة — يُسجَّل التفعيل والدين عندنا تلقائيّاً حين يكتمل الدفع.',
      'applied' when o.debtSure => 'سُجّل عندنا.',
      _ => '',
    };
    return [
      Row(
        children: [
          Icon(icon, color: tone, size: 20),
          const SizedBox(width: Sp.sm),
          Expanded(
            child: Text(text, style: AppType.rowValue(color: tone), maxLines: 3, overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
      // طلبٌ مفتوحٌ سابق: جملة الخادم عنه («مدفوعٌ ينتظر التفعيل — لا تدفع مرّةً ثانية»، «أكمل الدفع من رابطه…») — لا بعد رفض البطاقة
      if ((o.note ?? '').isNotEmpty && KitCardApi.live.contains(st) && !declined) ...[
        const SizedBox(height: Sp.md),
        _CardNote(tone: AppTone.info, icon: LucideIcons.info, text: o.note!, maxLines: 4),
      ],
      const SizedBox(height: 14),
      SheetRowsGroup(rows: [
        SheetRowData(
          label: 'يُدفع بالبطاقة لـ$_kitName',
          value: o.cost != null ? '${formatIQD(o.cost!.round())} $cur' : '—',
          strong: true,
        ),
        if (o.price != null)
          SheetRowData(label: 'سعر المشترك', value: '${formatIQD(o.price!.round())} $cur'),
        if (payType != null) SheetRowData(label: 'يُسجَّل عندنا', value: payType),
        if (st == 'applied' && (o.newExpiration ?? '').isNotEmpty)
          SheetRowData(label: 'ينتهي الاشتراك', value: iso(o.newExpiration!.length > 10 ? o.newExpiration!.substring(0, 10) : o.newExpiration!)),
        SheetRowData(label: 'رقم الطلب', value: iso(o.order)),
      ]),
      if (waiting && o.url != null) ...[
        const SizedBox(height: 14),
        FilledButton.icon(
          onPressed: _openPayPage,
          icon: const Icon(LucideIcons.externalLink, size: 18),
          label: const Text('افتح صفحة الدفع'),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.brandAccent,
            foregroundColor: AppColors.onBrand,
            minimumSize: const Size.fromHeight(48),
          ),
        ),
      ],
      if (debtNote != null) ...[
        const SizedBox(height: Sp.md),
        _CardNote(tone: debtNote.$1, icon: LucideIcons.triangleAlert, text: debtNote.$2, maxLines: 4),
      ],
      if (o.noReturn && !KitCardApi.live.contains(st) && st != 'applied') ...[
        const SizedBox(height: Sp.md),
        _CardNote(
          tone: AppTone.warning,
          icon: LucideIcons.triangleAlert,
          text: 'إن كنت دفعت من صفحة الدفع فلا تدفع مرّةً ثانية — افحص المشترك في $_kitName أوّلاً'
              '${ended ? '، ثمّ «محاولة جديدة» إن لم يتفعّل' : ''}.',
          maxLines: 4,
        ),
      ],
      if (ended) ...[
        const SizedBox(height: Sp.md),
        OutlinedButton.icon(
          onPressed: _newCardAttempt,
          icon: const Icon(LucideIcons.rotateCcw, size: 18),
          label: Text('محاولة جديدة', style: AppType.button(color: AppColors.brand)),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
            side: BorderSide(color: AppColors.brandSoftBorder),
            foregroundColor: AppColors.brand,
          ),
        ),
      ],
      if (footNote.isNotEmpty) ...[
        const SizedBox(height: Sp.md),
        Text(footNote, style: AppType.muted(color: AppColors.textMid).copyWith(fontSize: 12.5, height: 1.4)),
      ],
    ];
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
    if (_monthsBlocked) {
      showSheetSnack(context, 'انتظر معاينة الأشهر من $_kitName — أو اختر شهراً واحداً', isError: true);
      return;
    }
    final months = _isKit ? _kitMonths : 1;
    final num? expectedCost = months > 1 ? (_liveQuote?['cost'] as num?) : null;
    setState(() => _submitting = true);
    // لحظة الضغط — منها يُسأل الخادم لاحقاً «هل أُرسلت رسالة التفعيل؟» (OpWaNotice).
    final pressedAt = DateTime.now();
    final manualMode = ManualWaPrefs.enabled.value;
    final result = await MergedOps.run(widget.sub, () => SubscribersApi.activate(
      idx: idx,
      paymentType: paymentType,
      activationData: _data!,
      partialAmount: _pay == _PayType.partial ? _partialAmount : null,
      skipAutoWa: manualMode,
      profileId: change ? int.tryParse(_selectedPackageId) : null,
      // محفظة المشترك (الوطنيّ، ٢ نوفمبر): الشركة تخصم من رصيده — والخادم لا يسجّل نقداً ولا ديناً
      method: _kitCust ? 'customer_wallet' : 'credit',
      // الشركة المُضافة: «حالاً» وحدها (package_change_timing) — والخادم يرفض غيرها قبل أيّ نداء.
      changeType: change ? (_isFiberx && _fxTiming == _FxTiming.expiry ? 'expiry' : 'now') : null,
      confirmRepeat: _confirmRepeat,
      confirmCooloff: _confirmCooloff,
      months: months > 1 ? months : null,
      expectedCost: expectedCost,
    ));
    if (!mounted) return;
    setState(() {
      _submitting = false;
      _done = result.ok;
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
    // رصيد محفظة المشترك نقص بين القراءة والتفعيل ⇒ يُقرأ من جديد و«شحن المحفظة؟» (لم يُفعَّل شيء)
    if (!result.ok && result.code == 'CUST_WALLET_INSUFFICIENT') {
      await _load();
      final cw = _custWallet;
      if (!mounted) return;
      if (cw != null) return _offerCustTopup(cw);
      showSheetSnack(context, result.message ?? 'رصيد محفظة المشترك لا يكفي — لم يُفعَّل شيء', isError: true);
      return;
    }
    if (!result.ok) {
      showSheetSnack(context, _failureText(result.code, result.message), isError: true);
      return;
    }
    SubscriberEvents.notifyChange();
    // طُلبت أشهرٌ وقال الخادم غيرها (أو لم يقلها: خادمٌ أقدم) ⇒ يُقال لا يُخفى (كالموقع)
    final doneMonths = SubscribersApi.takeActivatedMonths(idx);
    // النجاح، ثمّ تنبيهاته («لم يُسجَّل الدين»، أشهرٌ غير المطلوبة)، ثمّ نتيجة رسالة التفعيل (أُرسلت / لم تُرسل بسببها)
    // — كلٌّ في دوره على الطبقة العليا فيبقى بعد إغلاق الشيت.
    unawaited(OpWaNotice.show(
      context,
      sub: widget.sub,
      op: OpWaKind.activate,
      okText: 'sheets.renew_ok'.tr(),
      pressedAt: pressedAt,
      wa: result.wa,
      manual: manualMode,
      followUps: [
        if (result.debtWriteFailed)
          (
            text: result.debtWriteMessage ?? 'sheets.activate_debt_not_recorded'.tr(),
            duration: const Duration(seconds: 8),
          ),
        if (months > 1 && (doneMonths ?? 1) != months)
          (
            text: 'تفعّل المشترك لـ${_monthsLabel(doneMonths ?? 1)} لا لـ${_monthsLabel(months)} — راجع المشترك',
            duration: const Duration(seconds: 12),
          ),
      ],
    ));
    if (_printReceiptChecked) {
      setState(() => _printingReceipt = true);
      final printed = await ReceiptService.printActivation(
        sub: widget.sub,
        price: _elChargePrice,
        pay: _kitCust ? ReceiptPay.wallet : _receiptPay,
        partialAmount: _kitCust ? null : _partialAmount,
        packageName: _elSelectedPkg?['name']?.toString() ?? _profileName,
      );
      // ورقة سبب طابعة الوصولات تُفتح فوق هذه الورقة: تُنتظر قبل pop، وإلّا أغلقها pop بدل هذه (مراجعة 179).
      if (mounted) await showPrintResult(context, printed);
      if (mounted) setState(() => _printingReceipt = false);
    }
    if (!mounted) return;
    if (manualMode && result.waPreview != null) {
      await handleWaPreviewAfterOp(
        context: context,
        preview: result.waPreview!,
        opTitle: 'تأكيد التفعيل',
        sub: widget.sub,
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
            onSelected: (id) {
              setState(() => _selectedPackageId = id);
              if (_kitMonths > 1) _fetchQuote(); // عدّة أشهر بباقةٍ أخرى ⇒ معاينتها
            },
          ),
          if (locked) ...[
            const SizedBox(height: Sp.xs),
            Text(
              _elPackageNote,
              style: AppType.muted(color: AppColors.textMid).copyWith(fontSize: 12.5, height: 1.4),
            ),
          ] else if (_isKit && !_elIsCurrentPkg && (_data?['package_change_note']?.toString().trim().isNotEmpty ?? false)) ...[
            // «تبديل الباقة» لمشتركٍ فعّال (الوطنيّ): الشركة تقرّر بداية مدّة الباقة الأخرى — تنبيهٌ قبل التأكيد كالموقع
            const SizedBox(height: Sp.xs),
            _CardNote(tone: AppTone.warning, icon: LucideIcons.triangleAlert, text: _data!['package_change_note'].toString(), maxLines: 4),
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
    if (_railExternal) {
      return _CardNote(
        tone: _railPinBad ? AppTone.danger : AppTone.brand,
        icon: LucideIcons.ticket,
        text: _railPinBad ? 'رقم البطاقة الخارجيّة ٨ خانات (أرقام أو حروف إنكليزيّة)' : 'يُفعَّل بالبطاقة الخارجيّة التي كتبتها',
      );
    }
    if (_typedExternal) {
      return _CardNote(
        tone: _typedPinBad ? AppTone.danger : AppTone.brand,
        icon: LucideIcons.ticket,
        text: _typedPinBad ? 'رقم البطاقة أرقامٌ أو حروفٌ إنكليزيّة — ٤ خانات فأكثر' : 'يُفعَّل بالبطاقة التي كتبت رقمها',
      );
    }
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
      // شركات الكارتات بلا مخزون: الرقم يُكتب تحت — لا «ليس لديك كارت»
      CardStockLevel.empty when _typedCard => const _CardNote(
          tone: AppTone.brand,
          icon: LucideIcons.ticket,
          text: 'اكتب رقم البطاقة بالحقل تحته — كما في صفحة الشركة',
        ),
      CardStockLevel.empty => _CardNote(
          tone: AppTone.warning,
          icon: LucideIcons.triangleAlert,
          // على طريق موقع الشحن: البديل بطاقةٌ خارجيّة يكتب رقمها في الحقل تحته
          text: _rail != null
              ? 'ليست لديك بطاقة بموقع الشحن لهذه الباقة — اكتب رقم بطاقة خارجيّة بالحقل تحته'
              : 'cards.none_for'.tr(namedArgs: {'profile': profile}),
          maxLines: _rail != null ? 3 : 2,
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
/// يفتح صفحة الدفع في المتصفّح الخارجيّ — قابلٌ للاستبدال في الاختبار.
@visibleForTesting
Future<bool> Function(Uri url) kitCardLauncher = (url) => launchUrl(url, mode: LaunchMode.externalApplication);

/// طلب دفعٍ بالبطاقة يتابعه الشيت (GET /api/v2/ftth/card-orders/:order).
class _CardOrder {
  const _CardOrder({
    required this.order,
    required this.url,
    required this.status,
    this.cost,
    this.price,
    this.note,
    this.paymentType,
    this.newExpiration,
    this.paidSeen = false,
    this.noReturn = false,
    this.debt,
    this.debtWriteFailed = false,
    this.polled = false,
  });
  final String order;
  final String? url;
  final String status;
  final num? cost;
  final num? price;

  /// جملة الخادم عن طلبٍ مفتوحٍ سابق (CARD_ORDER_OPEN).
  final String? note;
  final String? paymentType;
  final String? newExpiration;
  final bool paidSeen;
  final bool noReturn;
  final KitCardDebt? debt;
  final bool debtWriteFailed;

  /// وصلت حالٌ من الخادم (card-orders) — `link` بلا رابطٍ بعدها رابطٌ سحبه الخادم (رُفضت البطاقة)، لا رابطٌ لم يصل بعد.
  final bool polled;

  /// لا شكّ في الدين عندنا: كُتب، أو لا دين للطلب، أو خادمٌ أقدم لا يقول حاله ولم يقل إنّ كتابته فشلت — وحده يُقال عنه «سُجّل عندنا»
  /// ويُغلق الشيت بعد التفعيل. وما سواه (لم يُكتب، ربّما، تفعيلٌ آخر في سجلّنا، حالٌ لا يعرفها التطبيق) تبقى لوحته بتنبيهها.
  bool get debtSure =>
      !debtWriteFailed && (debt == null || debt == KitCardDebt.written || debt == KitCardDebt.none);

  /// حالٌ جديدة من الخادم: الرابط كما يقوله وحده (يسقط حين يُدفع، أو يرجع الدفع فاشلاً — لا دفعٌ على رابطٍ رُفض)، والمبالغ والشروط
  /// التي لا يقولها تبقى.
  _CardOrder withStatus(KitCardStatus st) => _CardOrder(
        order: order,
        url: st.status == 'link' || st.status == 'creating' ? st.paymentUrl : null,
        status: st.status,
        cost: st.cost ?? cost,
        price: st.price ?? price,
        note: note,
        paymentType: st.paymentType ?? paymentType,
        newExpiration: st.newExpiration ?? newExpiration,
        paidSeen: st.paidSeen,
        noReturn: st.noReturn,
        debt: st.debt,
        debtWriteFailed: st.debtWriteFailed,
        polled: true,
      );
}

class _CardNote extends StatelessWidget {
  const _CardNote({
    super.key,
    required this.tone,
    required this.icon,
    required this.text,
    this.onRetry,
    this.busy = false,
    this.maxLines = 2,
  });

  final AppTone tone;
  final IconData icon;
  final String text;
  final VoidCallback? onRetry;
  final bool busy;
  final int maxLines;

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
                  maxLines: maxLines,
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

/// رقم البطاقة كما يُكتب (كالموقع `latinCardPin` والخادم): الأرقام العربيّة/الفارسيّة لاتينيّة، وما ليس [0-9A-Za-z-] يُحذف (مسافاتٌ
/// ولصق)، وحدّه ٦٤.
class _LatinCardPinFormatter extends TextInputFormatter {
  const _LatinCardPinFormatter();

  static String latin(String v) {
    final b = StringBuffer();
    for (final c in v.runes) {
      if (c >= 0x660 && c <= 0x669) {
        b.writeCharCode(0x30 + c - 0x660);
      } else if (c >= 0x6f0 && c <= 0x6f9) {
        b.writeCharCode(0x30 + c - 0x6f0);
      } else if ((c >= 0x30 && c <= 0x39) || (c >= 0x41 && c <= 0x5a) || (c >= 0x61 && c <= 0x7a) || c == 0x2d) {
        b.writeCharCode(c);
      }
    }
    final s = b.toString();
    return s.length > 64 ? s.substring(0, 64) : s;
  }

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final t = latin(newValue.text);
    if (t == newValue.text) return newValue;
    return TextEditingValue(text: t, selection: TextSelection.collapsed(offset: t.length));
  }
}
