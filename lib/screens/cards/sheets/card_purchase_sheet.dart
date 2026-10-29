import 'dart:async';

import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../api/cards_api.dart';
import '../../../core/util/bidi.dart';
import '../../../core/widgets/app_sheet.dart';
import '../../../core/widgets/design_sheet.dart';
import '../../../core/widgets/sheet_scaffold.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';
import '../cards_widgets.dart';
import 'card_transfer_sheet.dart' show cardsCount, parseCardNumber;

/// شراء كارتاتٍ من رصيد الوكيل (٢٩ أكتوبر — المالك: «اكو ساسات … تدعم شراء كارتات يستقطع من الرصيد»): إضافة «شراء كروت»
/// في الساس — فئاتها بأسعارها من صفحتها، والشراء طلبٌ تولّد له وظيفةٌ سلسلةً جديدة خلال ثوانٍ فتظهر في الكارتات. صاحب الحساب
/// وحده (الشاشة لا تفتحها لموظّف)، وخلف مفتاح الخادم (`cards_purchase`).
///
/// المال: تأكيدٌ بالمجموع قبل الشراء، ومعرّف الطلب ثابتٌ للنيّة الواحدة (كالنقل) — نقرةٌ مكرّرة أو إعادةٌ بعد انقطاعٍ لا تشتري
/// مرّتين، ويتجدّد بتغيّر أيّ حقل أو بحكمٍ نهائيّ؛ وتكرارٌ خلال ٥ دقائق يطلب «نعم، اشترِ مرّةً ثانية» صريحاً. غير المحسوم يُقال كما
/// هو مع سجلّ الشراء — لا «فشل». بعد القبول يُتابَع السجلّ حتى تصل الكارتات. [onPurchased] مع كلّ شراءٍ قُبل (فتُحدَّث الشاشة
/// بعد الإغلاق مهما أُغلقت النافذة — زرّ، رجوع، سحب).
Future<void> showCardPurchaseSheet(BuildContext context, CardPurchaseOptions options, {VoidCallback? onPurchased}) {
  return showAppSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: AppColors.scrim,
    builder: (_) => CardPurchaseSheet(options: options, onPurchased: onPurchased),
  );
}

class CardPurchaseSheet extends StatefulWidget {
  const CardPurchaseSheet({
    super.key,
    required this.options,
    this.onPurchased,
    this.watchEvery = const Duration(seconds: 3),
  });
  final CardPurchaseOptions options;
  final VoidCallback? onPurchased;

  /// كم بين قراءتي السجلّ وهو يتابع طلباً قُبل (حتى تصل الكارتات) — الاختبار يقصّره.
  final Duration watchEvery;

  @override
  State<CardPurchaseSheet> createState() => _CardPurchaseSheetState();
}

class _CardPurchaseSheetState extends State<CardPurchaseSheet> {
  static const _watchMax = 10;

  late CardPurchaseOptions _options = widget.options;
  int? _value;
  final _qtyCtrl = TextEditingController(text: '1');

  bool _confirming = false;
  bool _busy = false;

  /// آخر ردٍّ «طلبتَ الشراء نفسه قبل دقائق»: الزرّ يصير «نعم، اشترِ مرّةً ثانية» (والمعرّف نفسه — لم يُرسَل شيء).
  bool _repeatPrompt = false;

  /// نيّةٌ واحدة = معرّفٌ واحد (انظر رأس الملفّ).
  String? _requestId;

  String? _success;

  /// الطلب المقبول الذي نتابعه في السجلّ: برقمه إن عُرف، وإلّا أحدث صفٍّ بقيمته وعدده.
  ({int? id, int value, int qty})? _watch;
  Timer? _watchTimer;

  List<CardPurchaseRow>? _history;
  List<CardPurchasePending> _pending = const [];
  String? _historyError;
  bool _historyLoading = true;

  @override
  void initState() {
    super.initState();
    _qtyCtrl.addListener(_changed);
    if (_options.values.length == 1) _value = _options.values.first.value;
    _loadHistory();
    _refreshOptions();
  }

  @override
  void dispose() {
    _watchTimer?.cancel();
    _qtyCtrl.dispose();
    super.dispose();
  }

  /// الرصيد والفئات طازجان عند الفتح (الشاشة قرأتهما قبل قليل — قد يكون الرصيد تغيّر بتفعيل).
  Future<void> _refreshOptions() async {
    final o = await CardsApi.purchaseOptions();
    if (!mounted || !o.enabled) return;
    setState(() {
      _options = o;
      if (_value != null && !o.values.any((v) => v.value == _value)) _value = null;
    });
  }

  Future<void> _loadHistory({bool quiet = false}) async {
    if (!quiet && mounted) setState(() => _historyLoading = true);
    final h = await CardsApi.purchaseHistory();
    if (!mounted) return;
    setState(() {
      _historyLoading = false;
      if (h.rows != null) {
        _history = h.rows;
        _pending = h.pending;
        _historyError = null;
      } else if (!quiet) {
        _historyError = h.message;
      }
    });
  }

  /// تغيّر أيّ حقل: نيّةٌ جديدة، ويُطلب التأكيد من جديد.
  void _changed() {
    _requestId = null;
    if (mounted) {
      setState(() {
        _confirming = false;
        _repeatPrompt = false;
      });
    }
  }

  int? get _qty {
    final n = parseCardNumber(_qtyCtrl.text);
    return (n != null && n >= 1) ? n : null;
  }

  int? get _total {
    final v = _value;
    final q = _qty;
    return (v == null || q == null) ? null : v * q;
  }

  bool get _overQty => (_qty ?? 0) > _options.maxQty;
  bool get _overTotal => _options.maxTotal > 0 && (_total ?? 0) > _options.maxTotal;
  bool get _valid => _value != null && _qty != null && !_overQty && !_overTotal && !_busy;

  CardPurchaseValue? get _selected {
    for (final v in _options.values) {
      if (v.value == _value) return v;
    }
    return null;
  }

  Future<void> _onFooter() async {
    if (!_valid) return;
    if (_repeatPrompt) return _submit(confirmRepeat: true);
    if (!_confirming) {
      setState(() => _confirming = true);
      return;
    }
    await _submit();
  }

  Future<void> _submit({bool confirmRepeat = false}) async {
    final value = _value;
    final qty = _qty;
    if (value == null || qty == null || _busy) return;
    _requestId ??= CardsApi.newTransferRequestId();
    setState(() => _busy = true);
    final r = await CardsApi.purchase(
      cardValue: value,
      quantity: qty,
      requestId: _requestId!,
      confirmRepeat: confirmRepeat,
    );
    if (!mounted) return;
    final done = r.data;
    if (done != null) {
      final msg = done.message ?? 'cards.purchase_done'.tr(namedArgs: {'cards': cardsCount(context, qty)});
      widget.onPurchased?.call();
      setState(() {
        _requestId = null;
        _busy = false;
        _confirming = false;
        _repeatPrompt = false;
        _success = msg;
        _watch = (id: done.purchaseId, value: value, qty: qty);
      });
      showSheetSnack(context, msg);
      _startWatch();
      unawaited(_refreshOptions());
      return;
    }
    if (r.code == CardsApi.codeRecentDuplicate) {
      // لم يُرسَل شيء: النيّة نفسها تنتظر تأكيداً صريحاً — المعرّف يبقى. السبب في صندوق المعاينة فوق الزرّ (لا إشعار يغطّيه).
      setState(() {
        _busy = false;
        _confirming = false;
        _repeatPrompt = true;
      });
      return;
    }
    // حكمٌ نهائيّ ⇒ نيّةٌ جديدة للمحاولة التالية؛ والملتبس/الجاري/الانقطاع ⇒ المعرّف نفسه (لا شراء مرّتين).
    final ambiguous = !r.answered || r.code == CardsApi.codeOutcomeUnknown || r.code == CardsApi.codeInProgress;
    if (!ambiguous) _requestId = null;
    setState(() {
      _busy = false;
      _confirming = false;
      _repeatPrompt = false;
    });
    showSheetSnack(context, r.message ?? 'common.load_failed'.tr(), isError: true);
    unawaited(_loadHistory(quiet: true));
  }

  /// متابعة الطلب المقبول في سجلّ الشراء حتى «تمّ» (أو ٣٠ ثانية) — الكارتات تظهر بعدها في القائمة.
  void _startWatch() {
    _watchTimer?.cancel();
    var n = 0;
    unawaited(_loadHistory(quiet: true));
    _watchTimer = Timer.periodic(widget.watchEvery, (t) async {
      n++;
      await _loadHistory(quiet: true);
      final row = _watchedRow;
      final settled = row != null && (row.state == CardPurchaseState.finished || row.state == CardPurchaseState.canceled);
      if (!mounted || settled || n >= _watchMax) t.cancel();
    });
  }

  CardPurchaseRow? get _watchedRow {
    final w = _watch;
    final h = _history;
    if (w == null || h == null) return null;
    for (final r in h) {
      if (w.id != null ? r.id == w.id : (r.value == w.value && r.qty == w.qty)) return r;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final total = _total;
    // طلبٌ جارٍ: لا إغلاق (الحكم يصل والنافذة مفتوحة).
    return PopScope(
      canPop: !_busy,
      child: DesignSheet(
        header: SheetHeaderBar(
          icon: LucideIcons.shoppingCart,
          // كلمة التطبيق «كارتات» لا عنوان الساس («شراء كروت») — اسمٌ واحد للقسم كلّه.
          title: 'cards.purchase_title'.tr(),
          subtitle: 'cards.purchase_subtitle'.tr(),
          onClose: _busy ? () {} : () => Navigator.of(context).pop(),
        ),
        footer: SheetFooterBar(
          label: _repeatPrompt
              ? 'cards.purchase_repeat'.tr()
              : _confirming && total != null
                  ? 'cards.purchase_confirm'.tr(namedArgs: {'total': cardsMoney(total)})
                  : 'cards.purchase_submit'.tr(),
          icon: _confirming || _repeatPrompt ? LucideIcons.circleCheck : LucideIcons.shoppingCart,
          color: _confirming || _repeatPrompt ? AppTone.warning.fill : null,
          enabled: _valid,
          busy: _busy,
          onPressed: _onFooter,
        ),
        scrollable: false,
        bodyPadding: EdgeInsets.zero,
        body: _body(context),
      ),
    );
  }

  Widget _body(BuildContext context) {
    final sel = _selected;
    final qty = _qty;
    final total = _total;
    final balance = _options.balance;
    return ListView(
      padding: const EdgeInsets.fromLTRB(Sp.xl, Sp.lg, Sp.xl, Sp.xxl),
      children: [
        _balanceLine(balance),
        const SizedBox(height: Sp.md),
        _label('cards.purchase_value'.tr()),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [for (final v in _options.values) _valueChip(v)],
        ),
        const SizedBox(height: Sp.md),
        _label('cards.purchase_qty'.tr()),
        Row(
          children: [
            _stepButton(LucideIcons.minus, (qty ?? 1) > 1 ? () => _setQty((qty ?? 1) - 1) : null),
            const SizedBox(width: 6),
            Expanded(
              child: TextField(
                key: const ValueKey('purchase-qty'),
                controller: _qtyCtrl,
                enabled: !_busy,
                textAlign: TextAlign.center,
                keyboardType: TextInputType.number,
                style: AppType.input(color: AppColors.textHi),
                decoration: _decoration(hint: 'cards.purchase_qty_hint'.tr(namedArgs: {'max': '${_options.maxQty}'})),
              ),
            ),
            const SizedBox(width: 6),
            _stepButton(LucideIcons.plus, (qty ?? 0) < _options.maxQty ? () => _setQty((qty ?? 0) + 1) : null),
          ],
        ),
        if (_overQty) ...[
          const SizedBox(height: Sp.x6),
          Text('cards.purchase_over_qty'.tr(namedArgs: {'max': cardsCount(context, _options.maxQty)}),
              style: AppType.muted(color: AppTone.danger.fill)),
        ],
        if (sel != null && qty != null && total != null) ...[
          const SizedBox(height: Sp.md),
          _preview(context, sel, qty, total, balance),
        ],
        if (_success != null) ...[
          const SizedBox(height: Sp.md),
          _successBox(),
        ],
        for (final p in _pending) ...[
          const SizedBox(height: Sp.sm),
          _notice(
            LucideIcons.circleHelp,
            'cards.purchase_unconfirmed'.tr(namedArgs: {
              'cards': cardsCount(context, p.qty),
              'price': cardsMoney(p.value),
            }),
            AppTone.warning,
          ),
        ],
        const SizedBox(height: Sp.xl),
        _historySection(context),
      ],
    );
  }

  void _setQty(int n) {
    _qtyCtrl.text = '$n';
    _qtyCtrl.selection = TextSelection.collapsed(offset: _qtyCtrl.text.length);
  }

  Widget _balanceLine(num? balance) {
    final known = balance != null;
    return Row(
      children: [
        Icon(LucideIcons.wallet, size: 16, color: known ? AppColors.textMid : AppTone.warning.fill),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            known
                ? 'cards.purchase_balance'.tr(namedArgs: {'amount': cardsMoney(balance)})
                : 'cards.purchase_balance_unknown'.tr(),
            style: known ? AppType.bodyBold(color: AppColors.textHi) : AppType.muted(color: AppTone.warning.fill),
          ),
        ),
      ],
    );
  }

  Widget _valueChip(CardPurchaseValue v) {
    final selected = _value == v.value;
    const tone = AppTone.brand;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: ValueKey('purchase-value-${v.value}'),
        onTap: _busy
            ? null
            : () {
                setState(() => _value = v.value);
                _changed();
              },
        borderRadius: BorderRadius.circular(R.md),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
          decoration: BoxDecoration(
            color: selected ? tone.softBg : AppColors.surface,
            borderRadius: BorderRadius.circular(R.md),
            border: Border.all(color: selected ? tone.fill : AppColors.border, width: selected ? 1.5 : 1),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                iso(v.name ?? v.label),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppType.bodyBold(color: selected ? tone.fill : AppColors.textHi),
              ),
              const SizedBox(height: 2),
              Text(cardsMoney(v.value), style: AppType.muted(color: selected ? tone.fill : AppColors.textMid)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _stepButton(IconData icon, VoidCallback? onTap) => SizedBox(
        width: 40,
        height: 40,
        child: OutlinedButton(
          onPressed: _busy ? null : onTap,
          style: OutlinedButton.styleFrom(
            padding: EdgeInsets.zero,
            side: BorderSide(color: AppColors.border),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(R.sm)),
          ),
          child: Icon(icon, size: 16, color: onTap == null ? AppColors.textLow : AppColors.textHi),
        ),
      );

  Widget _preview(BuildContext context, CardPurchaseValue sel, int qty, int total, num? balance) {
    final warn = _confirming || _repeatPrompt;
    final overBalance = balance != null && total > balance;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: warn ? AppTone.warning.softBg : AppColors.surface,
        borderRadius: BorderRadius.circular(R.md),
        border: Border.all(color: warn ? AppTone.warning.fill : AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'cards.purchase_preview'.tr(namedArgs: {
              'cards': cardsCount(context, qty),
              'name': iso(sel.name ?? sel.label),
              'price': cardsMoney(sel.value),
            }),
            style: AppType.bodyBold(color: AppColors.textHi),
          ),
          const SizedBox(height: 4),
          Text('cards.purchase_total'.tr(namedArgs: {'total': cardsMoney(total)}),
              style: AppType.bodyBold(color: warn ? AppTone.warning.fill : AppColors.textHi)),
          if (balance != null && !overBalance) ...[
            const SizedBox(height: 4),
            Text('cards.purchase_after'.tr(namedArgs: {'amount': cardsMoney(balance - total)}), style: AppType.muted()),
          ],
          if (overBalance) ...[
            const SizedBox(height: 4),
            Text('cards.purchase_over_balance'.tr(), style: AppType.muted(color: AppTone.warning.fill)),
          ],
          if (_overTotal) ...[
            const SizedBox(height: 4),
            Text('cards.purchase_over_total'.tr(namedArgs: {'max': cardsMoney(_options.maxTotal)}),
                style: AppType.muted(color: AppTone.danger.fill)),
          ],
          if (_repeatPrompt) ...[
            const SizedBox(height: 4),
            Text('cards.purchase_repeat_note'.tr(), style: AppType.muted(color: AppTone.warning.fill)),
          ] else ...[
            const SizedBox(height: 4),
            Text('cards.purchase_irreversible'.tr(), style: AppType.muted(color: warn ? AppTone.warning.fill : null)),
          ],
        ],
      ),
    );
  }

  Widget _successBox() {
    final row = _watchedRow;
    final arrived = row?.state == CardPurchaseState.finished;
    final canceled = row?.state == CardPurchaseState.canceled;
    final tone = canceled ? AppTone.danger : AppTone.success;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tone.softBg,
        borderRadius: BorderRadius.circular(R.md),
        border: Border.all(color: tone.softBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_success!, style: AppType.bodyBold(color: tone.onSoft)),
          const SizedBox(height: 4),
          Row(
            children: [
              if (!arrived && !canceled) ...[
                SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.6, color: tone.fill)),
                const SizedBox(width: 6),
              ] else
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 6),
                  child: Icon(arrived ? LucideIcons.circleCheck : LucideIcons.circleX, size: 14, color: tone.fill),
                ),
              Expanded(
                child: Text(
                  arrived
                      ? 'cards.purchase_watch_done'.tr()
                      : canceled
                          ? 'cards.purchase_watch_canceled'.tr()
                          : 'cards.purchase_watch_pending'.tr(),
                  style: AppType.muted(color: tone.onSoft),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _historySection(BuildContext context) {
    final h = _history;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: _label('cards.purchase_history'.tr())),
            IconButton(
              tooltip: 'common.refresh'.tr(),
              visualDensity: VisualDensity.compact,
              onPressed: _historyLoading ? null : () => _loadHistory(),
              icon: Icon(LucideIcons.refreshCw, size: 15, color: AppColors.textMid),
            ),
          ],
        ),
        if (h == null && _historyLoading)
          const Padding(
            padding: EdgeInsets.all(Sp.md),
            child: Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))),
          )
        else if (h == null)
          Text(_historyError ?? 'common.load_failed'.tr(), style: AppType.muted(color: AppTone.danger.fill))
        else if (h.isEmpty)
          Text('cards.purchase_history_empty'.tr(), style: AppType.muted())
        else
          for (final r in h.take(10)) _historyRow(context, r),
      ],
    );
  }

  Widget _historyRow(BuildContext context, CardPurchaseRow r) {
    final (tone, label) = switch (r.state) {
      CardPurchaseState.finished => (AppTone.success, 'cards.purchase_state_finished'.tr()),
      CardPurchaseState.pending => (AppTone.warning, 'cards.purchase_state_pending'.tr()),
      CardPurchaseState.processing => (AppTone.warning, 'cards.purchase_state_processing'.tr()),
      CardPurchaseState.canceled => (AppTone.danger, 'cards.purchase_state_canceled'.tr()),
      CardPurchaseState.unknown => (AppTone.neutral, 'cards.purchase_state_unknown'.tr()),
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.sm),
        border: Border.all(color: AppColors.borderSoft),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isoJoin([cardsCount(context, r.qty), cardsMoney(r.value)], ' × '),
                  style: AppType.bodyBold(color: AppColors.textHi),
                ),
                const SizedBox(height: 2),
                Text(
                  isoJoin([if (r.createdAt != null) iso(r.createdAt!), cardsMoney(r.total)], ' · '),
                  style: AppType.muted(),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: tone.softBg,
              borderRadius: BorderRadius.circular(R.pill),
              border: Border.all(color: tone.softBorder),
            ),
            child: Text(label, style: AppType.muted(color: tone.onSoft).copyWith(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Widget _notice(IconData icon, String text, AppTone tone) => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: tone.softBg,
          borderRadius: BorderRadius.circular(R.md),
          border: Border.all(color: tone.softBorder),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 16, color: tone.fill),
            const SizedBox(width: 8),
            Expanded(child: Text(text, style: AppType.muted(color: tone.onSoft))),
          ],
        ),
      );

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 4, right: 2),
        child: Text(t, style: AppType.muted(color: AppColors.textMid).copyWith(fontSize: 11, fontWeight: FontWeight.w700)),
      );

  InputDecoration _decoration({String? hint}) => InputDecoration(
        hintText: hint,
        hintStyle: AppType.input(color: AppColors.textLow),
        filled: true,
        fillColor: AppColors.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(R.sm),
          borderSide: BorderSide(color: AppColors.border),
        ),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      );
}
