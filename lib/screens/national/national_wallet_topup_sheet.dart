import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../api/national_sheet_api.dart';
import '../../api/national_wallet_api.dart';
import '../../core/util/amount_input.dart';
import '../../core/util/format.dart';
import '../../core/widgets/app_sheet.dart';
import '../../core/widgets/design_sheet.dart';
import '../../core/widgets/sheet_scaffold.dart';
import '../../services/permissions_service.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import 'national_task_sheet.dart' show NationalPortalLockBox;
import 'national_widgets.dart';

/// «تعبئة محفظة المشترك» — المشروع الوطنيّ (٢ نوفمبر — نسخة الموقع `WataniWalletTopup.tsx`): «من محفظتي» (المبلغ + نقداً/دين/جزئيّ،
/// والباقي ديناً على المشترك بدفترنا) أو «بكارت» الشركة. الرصيدان أعلاها، والمستلم المطابق، وكلّ طريقةٍ مقفلةٌ بسببها حين لا تتاح.
/// كتابةٌ واحدة بلا إعادة؛ «تمّ» و«لم يتأكّد» يُغلقان النافذة ويُرجعان النتيجة لمن فتحها (إشعارٌ وتحديث)، والرفض يبقى فيها بنصّه.

/// يفتح النافذة؛ يرجع النتيجة إن تمّ أو لم يتأكّد (فتُعاد قراءة المحفظة والدين)، وnull إن أُغلقت بلا شيء.
Future<WalletTopupResult?> showNationalWalletTopupSheet(BuildContext context, {required String sid}) {
  return showAppSheet<WalletTopupResult>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: AppColors.scrim,
    isScrollControlled: true,
    useSafeArea: true,
    isDismissible: false,
    builder: (_) => NationalWalletTopupSheet(sid: sid),
  );
}

const _payTypes = ['cash', 'non-cash', 'partial-cash'];
const _arDigits = '٠١٢٣٤٥٦٧٨٩';
const _faDigits = '۰۱۲۳۴۵۶۷۸۹';

/// أرقامٌ عربيّة/فارسيّة ⇒ لاتينيّة، والباقي يُحذف.
String walletDigits(String v) {
  final b = StringBuffer();
  for (final ch in v.split('')) {
    final i = _arDigits.indexOf(ch);
    final j = _faDigits.indexOf(ch);
    b.write(i >= 0 ? '$i' : j >= 0 ? '$j' : ch);
  }
  return b.toString().replaceAll(RegExp(r'\D'), '');
}

class NationalWalletTopupSheet extends StatefulWidget {
  const NationalWalletTopupSheet({super.key, required this.sid});
  final String sid;

  @override
  State<NationalWalletTopupSheet> createState() => _NationalWalletTopupSheetState();
}

class _NationalWalletTopupSheetState extends State<NationalWalletTopupSheet> {
  WalletTopupInfo? _info;
  String? _err;
  NationalLock? _lock;
  Timer? _poll;
  int _polls = 0;

  int _method = 0; // 0 «من محفظتي» · 1 «بكارت»
  final _amount = TextEditingController();
  int _amt = 0;
  int _pay = 0; // 0 نقداً · 1 دين · 2 جزئيّ
  final _partial = TextEditingController();
  int _part = 0;
  final _pin = TextEditingController();
  bool _busy = false;
  String? _repeat; // الخادم يطلب تأكيد تحويلٍ ثانٍ
  String? _error; // آخر رفضٍ بنصّه

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _poll?.cancel();
    _amount.dispose();
    _partial.dispose();
    _pin.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    _poll?.cancel();
    final r = await NationalWalletApi.info(widget.sid);
    if (!mounted) return;
    if (r.ok && r.data == null) {
      if (_polls++ < 12) _poll = Timer(const Duration(milliseconds: 2500), _load);
      return;
    }
    setState(() {
      _lock = r.lock;
      _err = r.locked ? null : r.error;
      if (r.ok) _info = r.data;
    });
  }

  int get _cash => _pay == 0 ? _amt : (_pay == 2 ? _part : 0);
  int get _debt => math.max(0, _amt - _cash);

  String? _amtErr(WalletTopupInfo i) {
    if (_amt <= 0) return null;
    if (_amt < i.min) return 'أقلّ مبلغ ${formatIQD(i.min)}';
    if (_amt > i.max) return 'أكثر مبلغ ${formatIQD(i.max)}';
    if (_amt % i.step != 0) return 'المبلغ من مضاعفات ${i.step}';
    return null;
  }

  String? _partErr(WalletTopupInfo i) {
    if (_pay != 2 || _part <= 0) return null;
    if (_amt > 0 && _part >= _amt) return 'المدفوع أقلّ من المبلغ كلّه — وإلّا فاختر «نقداً»';
    if (_part % i.step != 0) return 'المدفوع من مضاعفات ${i.step}';
    return null;
  }

  String get _pinDigits => walletDigits(_pin.text);

  bool _canSend(WalletTopupInfo i) {
    if (_busy) return false;
    if (_method == 1) return i.cardOk && _pinDigits.length >= 8 && _pinDigits.length <= 24;
    if (!i.transferOk || _amt <= 0 || _amtErr(i) != null) return false;
    return _pay != 2 || (_part > 0 && _partErr(i) == null);
  }

  Future<void> _submit({bool confirm = false}) async {
    final i = _info;
    if (i == null || (!confirm && !_canSend(i))) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    final card = _method == 1;
    final r = card
        ? await NationalWalletApi.card(widget.sid, _pinDigits)
        : await NationalWalletApi.transfer(widget.sid, amount: _amt, payType: _payTypes[_pay], partial: _part, confirmRepeat: confirm);
    if (!mounted) return;
    if (card) _pin.clear();
    switch (r.state) {
      case WalletTopupState.applied:
      case WalletTopupState.unknown:
        Navigator.of(context).pop(r);
      case WalletTopupState.repeat:
        setState(() {
          _busy = false;
          _repeat = r.message ?? 'حُوّل لهذا المشترك قبل دقائق — أكّد إن كان تحويلاً آخر';
        });
      case WalletTopupState.rejected:
        setState(() {
          _busy = false;
          _error = r.message;
        });
    }
  }

  void _close() {
    if (_busy) return;
    Navigator.of(context).pop();
  }

  /* ───────── العرض ───────── */

  Widget _tile(String label, int? v) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: 10),
          decoration: BoxDecoration(color: AppColors.surfaceSunken, borderRadius: BorderRadius.circular(R.md)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.micro(color: AppColors.textMid)),
            const SizedBox(height: Sp.xxs),
            Text(v == null ? '—' : formatIQD(v),
                maxLines: 1, overflow: TextOverflow.ellipsis, textDirection: TextDirection.ltr, style: AppType.amount(color: AppColors.textHi).copyWith(fontSize: 15)),
          ]),
        ),
      );

  Widget _note(String text, {Color? color}) => Text(text, style: AppType.micro(color: color ?? AppColors.textMid).copyWith(height: 1.45));

  Widget _transfer(WalletTopupInfo i) {
    if (!i.transferOk) return NationalPortalLockBox(title: 'التحويل غير متاح', text: i.transferReason ?? 'غير متاحٍ الآن');
    final amtErr = _amtErr(i);
    final partErr = _partErr(i);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (i.targetName != null || i.targetPhone != null) ...[
        Row(children: [
          Icon(LucideIcons.userCheck, size: 16, color: AppColors.textMid),
          const SizedBox(width: Sp.x6),
          Expanded(
            child: Text(
              'إلى محفظة: ${i.targetName ?? 'المشترك'}${i.targetPhone != null ? ' · ${i.targetPhone}' : ''}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppType.muted(color: AppColors.textMid),
            ),
          ),
        ]),
        const SizedBox(height: Sp.md),
      ],
      SheetSection(
        label: 'المبلغ',
        gap: 9,
        footnote: amtErr,
        child: SheetBox(
          focused: _amt > 0,
          radius: 18,
          borderColor: amtErr != null ? AppColors.error : null,
          padding: const EdgeInsets.symmetric(horizontal: Sp.lg, vertical: 14),
          child: AmountTextField(
            controller: _amount,
            enabled: !_busy,
            onValue: (v) => setState(() {
              _amt = v;
              _repeat = null;
            }),
          ),
        ),
      ),
      const SizedBox(height: Sp.md),
      SheetSection(
        label: 'طريقة دفع المشترك',
        gap: Sp.sm,
        child: SheetChoiceTiles(
          labels: const ['نقداً', 'دين', 'جزئيّ'],
          icons: const [LucideIcons.banknote, LucideIcons.creditCard, LucideIcons.chartPie],
          selectedIndex: _pay,
          enabled: !_busy,
          onSelect: (v) => setState(() => _pay = v),
        ),
      ),
      if (_pay == 2) ...[
        const SizedBox(height: Sp.md),
        SheetSection(
          label: 'المدفوع نقداً',
          gap: 9,
          footnote: partErr,
          child: SheetBox(
            focused: _part > 0,
            radius: 18,
            borderColor: partErr != null ? AppColors.error : null,
            padding: const EdgeInsets.symmetric(horizontal: Sp.lg, vertical: 14),
            child: AmountTextField(controller: _partial, enabled: !_busy, onValue: (v) => setState(() => _part = v)),
          ),
        ),
      ],
      if (_amt > 0 && amtErr == null) ...[
        const SizedBox(height: Sp.md),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: 10),
          decoration: BoxDecoration(color: AppColors.surfaceSunken, borderRadius: BorderRadius.circular(R.md)),
          child: Text(
            'يُخصم من محفظتك ${formatIQD(_amt)} ويصل لمحفظة المشترك${_debt > 0 && (_pay != 2 || partErr == null) ? ' — ويُسجَّل عليه دين ${formatIQD(_debt)}' : ''}',
            style: AppType.body(color: AppColors.textBody).copyWith(height: 1.45),
          ),
        ),
      ],
      if (i.recentAmount != null && _repeat == null) ...[
        const SizedBox(height: Sp.sm),
        _note(
          i.recentUnknown
              ? 'تحويلٌ سابق (${formatIQD(i.recentAmount!)}) قبل ${i.recentMinutes ?? 1} د لم يتأكّد — تحقّق من محفظة المشترك أوّلاً'
              : 'حُوّل لهذا المشترك ${formatIQD(i.recentAmount!)} قبل ${i.recentMinutes ?? 1} د',
          color: AppColors.warning,
        ),
      ],
    ]);
  }

  Widget _card(WalletTopupInfo i) {
    if (!i.cardOk) return NationalPortalLockBox(title: 'التعبئة بالكارت غير متاحة', text: i.cardReason ?? 'غير متاحةٍ الآن');
    return SheetSection(
      label: 'رقم الكارت',
      gap: 9,
      footnote: 'يُرسل للبوّابة مرّةً واحدة ولا يُحفظ عندنا',
      child: SheetBox(
        padding: const EdgeInsets.symmetric(horizontal: Sp.lg, vertical: 13),
        child: Semantics(
          label: 'رقم الكارت',
          child: TextField(
            controller: _pin,
            enabled: !_busy,
            autocorrect: false,
            enableSuggestions: false,
            keyboardType: TextInputType.number,
            textDirection: TextDirection.ltr,
            textAlign: TextAlign.left,
            maxLength: 32,
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9٠-٩۰-۹ ]'))],
            onChanged: (_) => setState(() {}),
            style: AppType.input(),
            decoration: InputDecoration(
              isDense: true,
              counterText: '',
              border: InputBorder.none,
              contentPadding: EdgeInsets.zero,
              hintText: '0000 0000 0000',
              hintTextDirection: TextDirection.ltr,
              hintStyle: AppType.input(color: AppColors.textPlaceholder),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep
    final i = _info;
    late final Widget body;
    if (_lock != null) {
      body = NationalPortalLockBox(title: _lock!.title, text: _lock!.message);
    } else if (_err != null && i == null) {
      body = NationalStateBox.error(text: _err!, onRetry: () {
        setState(() => _err = null);
        _polls = 0;
        _load();
      });
    } else if (i == null) {
      body = const NationalStateBox.pending(text: 'جارٍ قراءة المحفظتين من البوّابة…');
    } else {
      body = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // موظّفٌ بلا «التقرير الماليّ» لا يرى رصيد محفظة الحساب (الخادم يحجبه أيضاً — walletHidden)
        Row(children: [
          if (!Perms.isEmployee || Perms.has('reports.financial')) ...[_tile('رصيد محفظتك', i.partnerBalance), const SizedBox(width: Sp.sm)],
          _tile('رصيد محفظة المشترك', i.customerBalance),
        ]),
        const SizedBox(height: Sp.md),
        SheetSegmented(
          labels: const ['من محفظتي', 'بكارت'],
          icons: const [LucideIcons.arrowLeftRight, LucideIcons.creditCard],
          selectedIndex: _method,
          onSelect: (v) {
            if (_busy) return;
            setState(() {
              _method = v;
              _error = null;
              _repeat = null;
            });
          },
        ),
        const SizedBox(height: Sp.lg),
        if (_method == 0) _transfer(i) else _card(i),
        if (_repeat != null) ...[
          const SizedBox(height: Sp.md),
          _note(_repeat!, color: AppColors.warning),
        ],
        if (_error != null) ...[
          const SizedBox(height: Sp.md),
          _note(_error!, color: AppColors.error),
        ],
      ]);
    }
    final ready = i != null && (_method == 0 ? i.transferOk : i.cardOk);
    return PopScope(
      canPop: !_busy,
      child: DesignSheet(
        header: SheetHeaderBar(
          icon: LucideIcons.wallet,
          title: 'تعبئة محفظة المشترك',
          subtitle: 'من محفظتك في بوّابة الوطني أو بكارت الشركة',
          onClose: _close,
        ),
        body: body,
        footer: !ready
            ? null
            : SheetFooterBar(
                label: _method == 1
                    ? 'عبّئ بالكارت'
                    : (_repeat != null ? 'نعم، تحويلٌ آخر' : (_amt > 0 && _amtErr(i) == null ? 'حوّل ${formatIQD(_amt)}' : 'حوّل')),
                icon: _method == 1 ? LucideIcons.creditCard : LucideIcons.arrowLeftRight,
                busy: _busy,
                enabled: _repeat != null ? !_busy : _canSend(i),
                onPressed: () => _submit(confirm: _repeat != null),
              ),
      ),
    );
  }
}

/// نتيجةٌ تمّت أو لم تتأكّد ⇒ إشعارٌ لمن فتح النافذة (والدين غير المسجَّل يُقال وحده).
void nationalWalletSnack(BuildContext context, WalletTopupResult r) {
  if (r.state == WalletTopupState.unknown) {
    showSheetSnack(context, r.message ?? 'لم يتأكّد — افتح محفظة المشترك بعد دقيقة وتحقّق قبل أيّ إعادة',
        isError: true, duration: const Duration(seconds: 12), autoExplain: false);
    return;
  }
  final m = r.credited != null || (r.amount == null && r.debtAdded == null)
      ? 'عُبّئت محفظة المشترك${r.credited != null ? ' — ${formatIQD(r.credited!)}' : ''}'
      : 'حُوّل ${formatIQD(r.amount ?? 0)} إلى محفظة المشترك${(r.debtAdded ?? 0) > 0 ? ' — ${formatIQD(r.debtAdded!)} ديناً عليه' : ' — نقداً'}';
  showSheetSnack(context, r.debtWarning == null ? m : '$m\n${r.debtWarning}', isError: r.debtWarning != null,
      duration: Duration(seconds: r.debtWarning == null ? 4 : 12), autoExplain: false);
}
