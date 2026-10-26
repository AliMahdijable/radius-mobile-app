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

/// نقل كارتاتٍ من سلسلةٍ لمديرٍ فرعيّ (٢٧ أكتوبر — كواجهة الساس: بالعدد، أو حتى رقم كارت من أوّل كارتٍ متبقٍّ، أو
/// المجموعة كاملة). صاحب الحساب وحده (الشاشة لا تفتحها لموظّف)، وخلف مفتاح الخادم (`transfer_enabled`).
///
/// المستلمون والمدى يُقرآن من الساس الآن لا من الملخّص، والتأكيد قبل النقل — الكارتات لا ترجع من حساب المرسِل. معرّف
/// الطلب ثابتٌ للنيّة الواحدة: نقرةٌ مكرّرة أو إعادةٌ بعد انقطاعٍ لا تنقل مرّتين، ويتجدّد بتغيّر أيّ حقل.
/// يعيد `true` حين نُقل شيء (فتُحدَّث الشاشة).
Future<bool?> showCardTransferSheet(BuildContext context, CardSeries series) {
  return showAppSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: AppColors.scrim,
    builder: (_) => CardTransferSheet(series: series),
  );
}

/// عددٌ صحيحٌ من الإدخال — أرقامٌ عربيّة أو لاتينيّة، وإلّا `null`.
int? parseCardNumber(String s) {
  const ar = '٠١٢٣٤٥٦٧٨٩';
  final t = s.trim().split('').map((c) {
    final i = ar.indexOf(c);
    return i >= 0 ? '$i' : c;
  }).join();
  return RegExp(r'^\d{1,7}$').hasMatch(t) ? int.parse(t) : null;
}

/// «كارتٌ واحد / كارتان / ٣ كارتات / ١١ كارتاً» — وبالإنجليزيّة «1 card / 3 cards».
String cardsCount(BuildContext context, int n) {
  if (context.locale.languageCode != 'ar') return n == 1 ? '1 card' : '$n cards';
  if (n == 1) return 'كارتٌ واحد';
  if (n == 2) return 'كارتان';
  final r = n % 100;
  return (r >= 3 && r <= 10) ? '$n كارتات' : '$n كارتاً';
}

class CardTransferSheet extends StatefulWidget {
  const CardTransferSheet({super.key, required this.series});
  final CardSeries series;

  @override
  State<CardTransferSheet> createState() => _CardTransferSheetState();
}

class _CardTransferSheetState extends State<CardTransferSheet> {
  bool _loading = true;
  String? _error;
  List<CardTransferTarget> _targets = const [];
  CardSeriesRange _range = const CardSeriesRange(start: null, end: null, length: 0);

  String? _to;
  CardTransferMode _mode = CardTransferMode.count;
  final _countCtrl = TextEditingController();
  final _lastCtrl = TextEditingController();

  bool _confirming = false;
  bool _busy = false;

  /// نيّةٌ واحدة = معرّفٌ واحد (انظر رأس الملفّ).
  String? _requestId;

  @override
  void initState() {
    super.initState();
    _countCtrl.addListener(_changed);
    _lastCtrl.addListener(_changed);
    _load();
  }

  @override
  void dispose() {
    _countCtrl.dispose();
    _lastCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!_loading) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    // معاً: المستلمون والمدى (قراءتا ساسٍ مستقلّتان).
    final tf = CardsApi.transferTargets();
    final rf = CardsApi.seriesRange(widget.series.series);
    final t = await tf;
    final r = await rf;
    if (!mounted) return;
    setState(() {
      _loading = false;
      final targets = t.data;
      final range = r.data;
      if (targets == null || range == null) {
        _error = t.message ?? r.message ?? 'common.load_failed'.tr();
        return;
      }
      _targets = targets;
      _range = range;
      if (_to != null && !_targets.any((x) => x.id == _to)) _to = null;
    });
  }

  /// تغيّر أيّ حقل: نيّةٌ جديدة، ويُطلب التأكيد من جديد.
  void _changed() {
    _requestId = null;
    if (_confirming || mounted) setState(() => _confirming = false);
  }

  CardTransferTarget? get _target {
    for (final t in _targets) {
      if (t.id == _to) return t;
    }
    return null;
  }

  /// كم سيُنقل — `null` حين لا يصلح الإدخال.
  int? get _moving {
    final len = _range.length;
    switch (_mode) {
      case CardTransferMode.all:
        return len > 0 ? len : null;
      case CardTransferMode.count:
        final n = parseCardNumber(_countCtrl.text);
        return (n != null && n >= 1 && n <= len) ? n : null;
      case CardTransferMode.range:
        final last = parseCardNumber(_lastCtrl.text);
        final start = _range.start;
        final end = _range.end;
        if (last == null || start == null || end == null || last < start || last > end) return null;
        return last - start + 1;
    }
  }

  bool get _valid => _target != null && _moving != null && !_busy;

  Future<void> _onFooter() async {
    if (!_valid) return;
    if (!_confirming) {
      setState(() => _confirming = true);
      return;
    }
    await _submit();
  }

  Future<void> _submit() async {
    final target = _target;
    final n = _moving;
    if (target == null || n == null || _busy) return;
    _requestId ??= CardsApi.newTransferRequestId();
    setState(() => _busy = true);
    final r = await CardsApi.transfer(
      widget.series.series,
      mode: _mode,
      to: target.id,
      count: _mode == CardTransferMode.count ? n : null,
      toCard: _mode == CardTransferMode.range ? parseCardNumber(_lastCtrl.text) : null,
      requestId: _requestId!,
    );
    if (!mounted) return;
    final done = r.data;
    if (done != null) {
      showSheetSnack(
        context,
        done.message ??
            'cards.transfer_done'.tr(namedArgs: {'cards': cardsCount(context, done.moved), 'to': target.username}),
      );
      Navigator.of(context).pop(true);
      return;
    }
    // حكمٌ نهائيّ من الخادم ⇒ نيّةٌ جديدة للمحاولة التالية؛ والملتبس/قيد التنفيذ/الانقطاع ⇒ المعرّف نفسه (لا نقل مرّتين).
    if (r.answered && r.code != 'OUTCOME_UNKNOWN' && r.code != 'IN_PROGRESS') _requestId = null;
    setState(() {
      _busy = false;
      _confirming = false;
    });
    showSheetSnack(context, r.message ?? 'common.load_failed'.tr(), isError: true);
    final fresh = await CardsApi.seriesRange(widget.series.series);
    if (mounted && fresh.data != null) setState(() => _range = fresh.data!);
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final s = widget.series;
    final n = _moving;
    final ready = !_loading && _error == null && _targets.isNotEmpty && _range.length > 0;
    return DesignSheet(
      header: SheetHeaderBar(
        icon: LucideIcons.send,
        title: 'cards.transfer_title'.tr(),
        subtitle: isoJoin([
          iso(s.series),
          seriesProfile(s),
          'cards.per_card'.tr(namedArgs: {'value': cardsMoney(s.value)}),
        ], ' · '),
        onClose: _busy ? () {} : () => Navigator.of(context).pop(),
      ),
      footer: ready
          ? SheetFooterBar(
              label: _confirming && n != null
                  ? 'cards.transfer_confirm'.tr(namedArgs: {'cards': cardsCount(context, n)})
                  : 'cards.transfer_submit'.tr(),
              icon: _confirming ? LucideIcons.circleCheck : LucideIcons.send,
              color: _confirming ? AppTone.warning.fill : null,
              enabled: _valid,
              busy: _busy,
              onPressed: _onFooter,
            )
          : null,
      scrollable: false,
      bodyPadding: EdgeInsets.zero,
      body: _body(context, ready),
    );
  }

  Widget _body(BuildContext context, bool ready) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(Sp.xxl),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    final err = _error;
    if (err != null) {
      return _note(
        LucideIcons.circleAlert,
        err,
        tone: AppTone.danger,
        action: TextButton(onPressed: _load, child: Text('common.retry'.tr())),
      );
    }
    if (_range.length < 1) return _note(LucideIcons.inbox, 'cards.transfer_empty'.tr());
    if (_targets.isEmpty) return _note(LucideIcons.users, 'cards.transfer_no_targets'.tr());

    final target = _target;
    final n = _moving;
    final start = _range.start;
    final end = _range.end;
    return ListView(
      padding: const EdgeInsets.fromLTRB(Sp.xl, Sp.lg, Sp.xl, Sp.xxl),
      children: [
        _label('cards.transfer_target'.tr()),
        DropdownButtonFormField<String>(
          initialValue: _to,
          isExpanded: true,
          hint: Text('cards.transfer_pick_target'.tr(), style: AppType.input(color: AppColors.textLow)),
          items: [
            for (final t in _targets)
              DropdownMenuItem(
                value: t.id,
                child: Text(iso(t.username), style: AppType.input(color: AppColors.textHi), overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: _busy
              ? null
              : (v) {
                  setState(() => _to = v);
                  _changed();
                },
          decoration: _decoration(),
        ),
        const SizedBox(height: Sp.md),
        _label('cards.transfer_mode'.tr()),
        Row(
          children: [
            for (final m in CardTransferMode.values) ...[
              Expanded(child: _modeChip(m)),
              if (m != CardTransferMode.values.last) const SizedBox(width: 6),
            ],
          ],
        ),
        const SizedBox(height: Sp.x6),
        Text(
          'cards.transfer_available'.tr(namedArgs: {
            'cards': cardsCount(context, _range.length),
            'from': iso('${start ?? ''}'),
            'to': iso('${end ?? ''}'),
          }),
          style: AppType.muted(),
        ),
        const SizedBox(height: Sp.md),
        if (_mode == CardTransferMode.count) ...[
          _label('cards.transfer_count_label'.tr()),
          TextField(
            key: const ValueKey('transfer-count'),
            controller: _countCtrl,
            enabled: !_busy,
            keyboardType: TextInputType.number,
            style: AppType.input(color: AppColors.textHi),
            decoration: _decoration(hint: 'cards.transfer_count_hint'.tr(namedArgs: {'max': '${_range.length}'})),
          ),
          const SizedBox(height: Sp.x6),
          Text('cards.transfer_count_help'.tr(), style: AppType.muted()),
        ],
        if (_mode == CardTransferMode.range) ...[
          _label('cards.transfer_to_card_label'.tr()),
          TextField(
            key: const ValueKey('transfer-last'),
            controller: _lastCtrl,
            enabled: !_busy,
            keyboardType: TextInputType.number,
            style: AppType.input(color: AppColors.textHi),
            decoration: _decoration(
              hint: 'cards.transfer_to_card_hint'.tr(namedArgs: {'from': '${start ?? ''}', 'to': '${end ?? ''}'}),
            ),
          ),
          const SizedBox(height: Sp.x6),
          Text('cards.transfer_to_card_help'.tr(namedArgs: {'from': iso('${start ?? ''}')}), style: AppType.muted()),
        ],
        if (_mode == CardTransferMode.all) Text('cards.transfer_all_help'.tr(), style: AppType.body(color: AppColors.textHi)),
        if (target != null && n != null) ...[
          const SizedBox(height: Sp.md),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _confirming ? AppTone.warning.softBg : AppColors.surface,
              borderRadius: BorderRadius.circular(R.md),
              border: Border.all(color: _confirming ? AppTone.warning.fill : AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'cards.transfer_preview'.tr(namedArgs: {'cards': cardsCount(context, n), 'to': iso(target.username)}),
                  style: AppType.bodyBold(color: AppColors.textHi),
                ),
                const SizedBox(height: 4),
                Text(
                  'cards.per_card'.tr(namedArgs: {'value': cardsMoney(widget.series.value)}),
                  style: AppType.muted(),
                ),
                const SizedBox(height: 4),
                Text(
                  'cards.transfer_irreversible'.tr(),
                  style: AppType.muted(color: _confirming ? AppTone.warning.fill : null),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _modeChip(CardTransferMode m) {
    final selected = _mode == m;
    final label = switch (m) {
      CardTransferMode.count => 'cards.mode_count'.tr(),
      CardTransferMode.range => 'cards.mode_range'.tr(),
      CardTransferMode.all => 'cards.mode_all'.tr(),
    };
    const tone = AppTone.brand;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _busy
            ? null
            : () {
                setState(() => _mode = m);
                _changed();
              },
        borderRadius: BorderRadius.circular(R.md),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          decoration: BoxDecoration(
            color: selected ? tone.softBg : AppColors.surface,
            borderRadius: BorderRadius.circular(R.md),
            border: Border.all(color: selected ? tone.fill : AppColors.border, width: selected ? 1.5 : 1),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppType.bodyBold(color: selected ? tone.fill : AppColors.textMid),
          ),
        ),
      ),
    );
  }

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

  Widget _note(IconData icon, String text, {AppTone? tone, Widget? action}) {
    return Padding(
      padding: const EdgeInsets.all(Sp.xxl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 28, color: tone?.fill ?? AppColors.textLow),
          const SizedBox(height: Sp.md),
          Text(text, textAlign: TextAlign.center, style: AppType.body(color: AppColors.textMid)),
          if (action != null) ...[const SizedBox(height: Sp.x6), action],
        ],
      ),
    );
  }
}
