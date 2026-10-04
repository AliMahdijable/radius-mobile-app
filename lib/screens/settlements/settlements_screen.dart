import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../api/settlements_api.dart';
import '../../core/util/amount_input.dart';
import '../../core/util/bidi.dart';
import '../../core/util/format.dart';
import '../../core/widgets/design_sheet.dart';
import '../../core/widgets/sheet_scaffold.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import 'settle_widgets.dart';
import 'sheets/settle_sheet.dart';
import 'sheets/settlement_detail_sheet.dart';

/// «تسوية الحساب» — صندوق المدير (2026-10-02).
///
/// الصندوق = المُرحَّل + الواصل نقداً (تفعيل نقديّ + تسديد ديون) −
/// الصرفيات، منذ آخر تسوية. التسوية لا تحذف حركة: تحفظ سنداً مرقّماً
/// ويبدأ الحساب الحاليّ من الصفر. القواعد كلّها في الخادم
/// (`server/accountSettlements.js`)، والشاشة تعرض وتؤكّد فقط.
class SettlementsScreen extends StatefulWidget {
  const SettlementsScreen({super.key});

  @override
  State<SettlementsScreen> createState() => _SettlementsScreenState();
}

class _SettlementsScreenState extends State<SettlementsScreen> {
  CurrentAccount? _cur;
  bool _loading = true;
  String? _error;
  String? _errorCode;

  List<BoxMovement> _moves = const [];
  bool _movesMore = false;
  bool _movesLoading = false;
  int _movesLimit = 100;
  List<SettlementRecord> _history = const [];
  int _historyTotal = 0;

  /// سبب خلوّ السجلّ أو الحركات — إن كان منعاً أو عطلاً لا فراغاً.
  ///
  /// ⚠️ قائمةٌ فارغة تُقرأ «لا شيء»، وهي أحياناً «لم نستطع القراءة».
  /// فكان يظهر «لا تسويات بعد» بجوار عدّادٍ يقول ٤٧ حركة.
  String? _historyMsg, _movesMsg;

  // بطاقة البداية
  int _startMode = 0; // 0 بداية الشهر · 1 بداية اليوم · 2 الآن · 3 تاريخ
  DateTime? _startDate;
  final _openingCtrl = TextEditingController();
  int _opening = 0;
  bool _starting = false;

  // ── معاينة البداية ──────────────────────────────────────────────
  //
  // 🐛 «التصميم يدوخ… ما أعرف شنو أسوّي»: كان المدير يختار تاريخاً ولا
  // يرى أثره إلّا بعد البدء، فيلغي ويعيد حتّى يفهم. فيرى الآن ما سيكون
  // في الصندوق قبل أن يبدأ. (`docs/settlements-prompt.md` §١)
  StartPreview? _preview;
  bool _previewLoading = false;
  String? _previewError;

  /// عدّاد الطلبات: من عاد بغير آخر رقمٍ فردٌّ متأخّرٌ يخصّ اختياراً
  /// سابقاً، فيُهمَل. «بداية الشهر» أثقل من «الآن»، وبلا العدّاد تكتب
  /// أرقامُ الأوّل نفسها تحت تسمية الثاني.
  int _previewGen = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _openingCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final r = await SettlementsApi.current();
    if (!mounted) return;
    final cur = r.data;
    if (cur == null) {
      setState(() {
        _loading = false;
        _error = r.message ?? 'common.load_failed'.tr();
        _errorCode = r.code;
      });
      return;
    }
    var moves = const <BoxMovement>[];
    var more = false;
    String? histMsg, movMsg;
    var history = const <SettlementRecord>[];
    var total = 0;
    if (cur.started) {
      // متوازيان: يبدآن معاً ويُنتظَران بعد ذلك.
      final movesF = SettlementsApi.movements(limit: _movesLimit);
      final historyF = SettlementsApi.list(limit: 50);
      final m = await movesF;
      final h = await historyF;
      if (!mounted) return;
      moves = m.items;
      more = m.hasMore;
      history = h.items;
      total = h.total;
      histMsg = h.message;
      movMsg = m.message;
    }
    setState(() {
      _cur = cur;
      _error = null;
      _errorCode = null;
      _loading = false;
      _moves = moves;
      _movesMore = more;
      _history = history;
      _historyTotal = total;
      _historyMsg = histMsg;
      _movesMsg = movMsg;
    });
  }

  Future<void> _moreMoves() async {
    if (_movesLoading || _movesLimit >= 500) return;
    setState(() {
      _movesLoading = true;
      _movesLimit = _movesLimit + 100 > 500 ? 500 : _movesLimit + 100;
    });
    final m = await SettlementsApi.movements(limit: _movesLimit);
    if (!mounted) return;
    setState(() {
      _moves = m.items;
      _movesMore = m.hasMore;
      _movesLoading = false;
    });
  }

  /// معاينة البداية — طلبٌ لكلّ قيمةٍ جديدة. النتيجة السابقة تبقى
  /// معروضةً **باهتةً** حتّى يصل الردّ، فلا يرتجف الصندوق بين اختيارين.
  Future<void> _loadPreview(String start) async {
    if (start.isEmpty) {
      // «تاريخ آخر» بلا تاريخ: لا شيء يُعرض، والطلب المعلّق يُبطَل برفع
      // العدّاد.
      _previewGen++;
      if (!mounted) return;
      setState(() {
        _preview = null;
        _previewError = null;
        _previewLoading = false;
      });
      return;
    }
    final gen = ++_previewGen;
    setState(() {
      _previewLoading = true;
      _previewError = null;
    });
    final r = await SettlementsApi.previewStart(start);
    if (!mounted || gen != _previewGen) return;
    setState(() {
      _previewLoading = false;
      // ⚠️ عند الفشل نمحو السابق ولا نُبقيه تحت تاريخٍ جديد: الإبهات
      // وحده لا يقول «هذه أرقام تاريخٍ آخر».
      _preview = r.data;
      _previewError = r.data == null ? r.message : null;
    });
  }

  /// يُستدعى من كلّ ما يغيّر قيمة البداية.
  void _startChanged(CurrentAccount cur) => _loadPreview(_startValue(cur));

  String _ymd(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)}';
  }

  /// `now` أو `YYYY-MM-DD` بتوقيت بغداد — كما يقبلها الخادم.
  String _startValue(CurrentAccount cur) {
    switch (_startMode) {
      case 0:
        return cur.monthStart ?? 'now';
      case 1:
        return cur.today ?? 'now';
      case 2:
        return 'now';
      default:
        return _startDate == null ? '' : _ymd(_startDate!);
    }
  }

  Future<void> _pickStartDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate ?? DateTime(now.year, now.month, 1),
      firstDate: DateTime(2025, 1, 1),
      lastDate: now,
      helpText: 'settle.pick_date'.tr(),
      cancelText: 'common.cancel'.tr(),
      confirmText: 'common.confirm'.tr(),
    );
    if (picked != null && mounted) setState(() => _startDate = picked);
  }

  Future<void> _start() async {
    final cur = _cur;
    if (cur == null || _starting) return;
    final start = _startValue(cur);
    if (start.isEmpty) {
      showSheetSnack(context, 'settle.pick_date'.tr(), isError: true);
      return;
    }
    setState(() => _starting = true);
    final r = await SettlementsApi.open(start: start, openingBalance: _opening);
    if (!mounted) return;
    setState(() => _starting = false);
    showSheetSnack(
      context,
      r.ok ? 'settle.started'.tr() : (r.message ?? 'common.load_failed'.tr()),
      isError: !r.ok,
    );
    if (r.ok) _load();
  }

  Future<void> _openSettle() async {
    final saved = await showSettleSheet(context);
    if (!mounted || saved == null) return;
    await _load();
    if (!mounted) return;
    // السند يُفتح بعد التسوية مباشرةً: منه يطبع المدير ويرى ما سُلِّم.
    _openDetail(saved.id);
  }

  Future<void> _openDetail(int id) async {
    final cur = _cur;
    final changed = await showSettlementDetailSheet(
      context,
      id: id,
      headId: (cur != null && cur.started) ? cur.head?.id : null,
      canVoid: cur?.canVoid ?? false,
    );
    if (changed == true && mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          'settle.title'.tr(),
          style: AppType.title(color: AppColors.textHi).copyWith(fontSize: 16),
        ),
        iconTheme: IconThemeData(color: AppColors.textHi),
        actions: [
          IconButton(
            onPressed: _load,
            tooltip: 'common.refresh'.tr(),
            icon:
                Icon(LucideIcons.refreshCw, size: 18, color: AppColors.textMid),
          ),
        ],
      ),
      bottomNavigationBar: _footer(),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          color: AppColors.brandAccent,
          child: _body(),
        ),
      ),
    );
  }

  /// زرّ الإجراء الأساسي — زرّ النظام نفسه أسفل الشاشة.
  Widget? _footer() {
    final cur = _cur;
    if (cur == null || !cur.canSettle) return null;
    final Widget bar;
    if (!cur.started) {
      bar = SheetFooterBar(
        label: _startMode == 2
            ? 'settle.start_button_now'.tr()
            : 'settle.start_button_date'.tr(),
        icon: LucideIcons.play,
        busy: _starting,
        onPressed: _start,
      );
    } else {
      final any = cur.moveCount > 0 || cur.openingBalance != 0;
      bar = SheetFooterBar(
        label: any ? 'settle.settle_now'.tr() : 'settle.nothing_to_settle'.tr(),
        icon: LucideIcons.handCoins,
        enabled: any,
        onPressed: _openSettle,
      );
    }
    return ColoredBox(
      color: AppColors.surface,
      child: SafeArea(top: false, child: bar),
    );
  }

  Widget _body() {
    final cur = _cur;
    const pad = EdgeInsets.fromLTRB(Sp.lg, Sp.lg, Sp.lg, Sp.huge);
    if (_loading && cur == null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 160),
          Center(child: CircularProgressIndicator()),
        ],
      );
    }
    if (cur == null) {
      final notInstalled = _errorCode == 'NOT_INSTALLED';
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: pad,
        children: [
          _StateCard(
            icon: notInstalled ? LucideIcons.wallet : LucideIcons.circleAlert,
            text: notInstalled
                ? 'settle.not_installed'.tr()
                : (_error ?? 'common.load_failed'.tr()),
            action: notInstalled
                ? null
                : TextButton(
                    onPressed: _load, child: Text('common.retry'.tr())),
          ),
        ],
      );
    }
    if (!cur.started) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: pad,
        children: [
          if (cur.canSettle)
            _startCard(cur)
          else
            _StateCard(
                icon: LucideIcons.wallet, text: 'settle.no_start_perm'.tr()),
        ],
      );
    }
    final head = cur.head;
    final openingLabel = (head == null || head.isOpening)
        ? 'settle.opening_balance'.tr()
        : 'settle.carried_from'.tr(namedArgs: {'n': '${head.number}'});
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: pad,
      children: [
        _BoxCard(cur: cur),
        if (cur.hasEmployees) ...[
          const SizedBox(height: Sp.xl),
          _SectionTitle(text: 'settle.collectors_title'.tr()),
          CollectorsList(collectors: cur.collectors),
          const SizedBox(height: Sp.x6),
          Text('settle.collectors_hint'.tr(), style: AppType.muted()),
        ],
        const SizedBox(height: Sp.xl),
        _SectionTitle(
          text: 'settle.movements_title'.tr(),
          trailing: '${cur.moveCount}',
        ),
        _Panel(
          children: [
            if (_moves.isEmpty && cur.openingBalance == 0)
              Padding(
                padding: const EdgeInsets.all(Sp.lg),
                child: Text(
                  _movesMsg ?? 'settle.no_movements'.tr(),
                  style: _movesMsg == null
                      ? AppType.muted()
                      : AppType.muted(color: AppTone.danger.fill),
                ),
              ),
            for (final m in _moves) MovementTile(m: m),
            if (_movesMore)
              Padding(
                padding: const EdgeInsets.all(Sp.sm),
                child: Center(
                  child: _movesLimit >= 500
                      ? Text(
                          'settle.moves_truncated'.tr(),
                          style: AppType.muted(),
                          textAlign: TextAlign.center,
                        )
                      : TextButton(
                          onPressed: _movesLoading ? null : _moreMoves,
                          child: Text('settle.show_more'.tr()),
                        ),
                ),
              )
            else if (cur.openingBalance != 0)
              OpeningTile(label: openingLabel, amount: cur.openingBalance),
          ],
        ),
        const SizedBox(height: Sp.xl),
        _SectionTitle(
          text: 'settle.history_title'.tr(),
          trailing: _historyTotal > 0 ? '$_historyTotal' : null,
        ),
        _Panel(
          children: [
            if (_history.isEmpty)
              Padding(
                padding: const EdgeInsets.all(Sp.lg),
                // السبب إن وُجد، وإلّا فهو فراغٌ حقيقيّ.
                child: Text(
                  _historyMsg ?? 'settle.history_empty'.tr(),
                  style: _historyMsg == null
                      ? AppType.muted()
                      : AppType.muted(color: AppTone.danger.fill),
                ),
              ),
            for (final r in _history)
              _HistoryTile(record: r, onTap: () => _openDetail(r.id)),
          ],
        ),
      ],
    );
  }

  Widget _startCard(CurrentAccount cur) {
    final start = _startValue(cur);
    final String hint;
    if (_startMode == 2) {
      hint = 'settle.start_hint_now'.tr();
    } else if (start.isEmpty) {
      hint = 'settle.pick_date'.tr();
    } else {
      hint = 'settle.start_hint_date'.tr(namedArgs: {'date': start});
    }
    return Container(
      padding: const EdgeInsets.all(Sp.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.card),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: H.iconBox,
                height: H.iconBox,
                decoration: BoxDecoration(
                  color: AppTone.brand.softBg,
                  borderRadius: BorderRadius.circular(R.icon),
                ),
                child: Icon(LucideIcons.wallet,
                    size: 20, color: AppTone.brand.fill),
              ),
              const SizedBox(width: Sp.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'settle.start_title'.tr(),
                      style: AppType.cardTitleBold(color: AppColors.textHi),
                    ),
                    const SizedBox(height: Sp.xs),
                    Text(
                      'settle.start_body'.tr(),
                      style: AppType.body(color: AppColors.textMid)
                          .copyWith(height: 1.6),
                    ),
                    const SizedBox(height: Sp.sm),
                    for (var i = 1; i <= 3; i++) ...[
                      if (i > 1) const SizedBox(height: Sp.xs),
                      _StepLine(n: i, text: 'settle.start_step$i'.tr()),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: Sp.xl),
          SheetSection(
            label: 'settle.start_from'.tr(),
            footnote: hint,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SheetSegmented(
                  labels: [
                    'settle.start_month'.tr(),
                    'settle.start_today'.tr(),
                    'settle.start_now'.tr(),
                  ],
                  selectedIndex: _startMode < 3 ? _startMode : -1,
                  onSelect: (i) {
                    setState(() => _startMode = i);
                    _startChanged(cur);
                  },
                ),
                const SizedBox(height: Sp.sm),
                // الشريحة بعرض نصّها لا بعرض العمود الممدود.
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: SheetQuickChip(
                    label: _startDate == null
                        ? 'settle.start_date'.tr()
                        : 'settle.start_date_value'
                            .tr(namedArgs: {'date': _ymd(_startDate!)}),
                    icon: LucideIcons.calendar,
                    selected: _startMode == 3,
                    onTap: () async {
                      setState(() => _startMode = 3);
                      await _pickStartDate();
                      if (!mounted) return;
                      _startChanged(cur);
                    },
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: Sp.lg),
          _previewBox(),
          const SizedBox(height: Sp.lg),
          SheetSection(
            label: 'settle.opening_label'.tr(),
            footnote: 'settle.opening_hint'.tr(),
            child: SheetBox(
              padding:
                  const EdgeInsets.symmetric(horizontal: Sp.lg, vertical: 12),
              child: AmountTextField(
                controller: _openingCtrl,
                currency: 'common.currency'.tr(),
                onValue: (v) => setState(() => _opening = v),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// ما سيكون في الصندوق لو بدأ الحساب من القيمة المختارة الآن.
  ///
  /// ⚠️ **الرصيد الافتتاحيّ يُجمَع هنا لا في الخادم.** `expected` من
  /// `preview-start` **بلا** الرصيد، لأنّه لم يُحفَظ بعدُ — يكتبه
  /// المستخدم في الحقل أسفل هذا الصندوق. فالمجموع يتحرّك مع الحقل بلا
  /// طلبٍ جديد، ولا يُجمَع مرّتين. (`docs/settlements-prompt.md` §٣)
  Widget _previewBox() {
    final p = _preview;
    final err = _previewError;

    final Widget body;
    if (err != null) {
      body = Text(err,
          style: AppType.micro(color: AppTone.danger.fill), maxLines: 3);
    } else if (p == null) {
      body = Text(
        _previewLoading
            ? 'settle.preview_loading'.tr()
            : 'settle.preview_pick'.tr(),
        style: AppType.micro(color: AppColors.textLow),
        maxLines: 2,
      );
    } else if (p.moveCount == 0 && _opening == 0) {
      body = Text('settle.preview_empty'.tr(),
          style: AppType.micro(color: AppColors.textLow), maxLines: 3);
    } else {
      final total = p.expected + _opening;
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'settle.preview_title'.tr(namedArgs: {'from': iso(p.start)}),
            style: AppType.micro(color: AppColors.textLow),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: Sp.xs),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: Text(
                settleMoney(total),
                style: AppType.cardTitleBold(
                  color: total < 0 ? AppTone.danger.fill : AppColors.textHi,
                ),
              ),
            ),
          ),
          const SizedBox(height: Sp.sm),
          if (p.cashActivations.sum != 0)
            _Line(
              label: 'settle.cash_activations'.tr(),
              value: '+${formatIQD(p.cashActivations.sum)}',
            ),
          if (p.debtPayments.sum != 0)
            _Line(
              label: 'settle.debt_payments'.tr(),
              value: '+${formatIQD(p.debtPayments.sum)}',
            ),
          if (p.expenses.sum != 0)
            _Line(
              label: 'settle.expenses'.tr(),
              value: '−${formatIQD(p.expenses.sum)}',
            ),
          if (_opening != 0)
            _Line(
              label: 'settle.opening_label'.tr(),
              value: '+${formatIQD(_opening)}',
            ),
        ],
      );
    }

    return SheetBox(
      background: AppColors.surfaceSunken,
      child: AnimatedOpacity(
        // النتيجة السابقة تبقى باهتةً حتّى يصل الردّ، فلا يرتجف الصندوق.
        opacity: _previewLoading && p != null ? 0.45 : 1,
        duration: const Duration(milliseconds: 150),
        child: Align(alignment: AlignmentDirectional.centerStart, child: body),
      ),
    );
  }
}

/// خطوةٌ مرقّمة في شرح البداية.
class _StepLine extends StatelessWidget {
  const _StepLine({required this.n, required this.text});
  final int n;
  final String text;

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ⚠️ `shape: circle` لا `BorderRadius.circular(n)`: الرقم الخامّ
        // يسقط في `design_scales_test`، و`H.checkbox` (٢٠) أقرب توكنٍ
        // لدائرة رقمٍ صغيرة.
        Container(
          width: H.checkbox,
          height: H.checkbox,
          decoration: BoxDecoration(
            color: AppTone.brand.softBg,
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Text('$n', style: AppType.micro(color: AppTone.brand.fill)),
        ),
        const SizedBox(width: Sp.sm),
        // ⚠️ الدائرة `Container` فيَعُدّها حارس `flex_text_guard_test`
        // جاراً ثابتاً، فالنصّ يحتاج `maxLines` و`ellipsis`.
        Expanded(
          child: Text(
            text,
            style:
                AppType.micro(color: AppColors.textMid).copyWith(height: 1.5),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

/// «في الصندوق الآن» — المبلغ بإشارته وتفصيله منذ آخر تسوية.
class _BoxCard extends StatelessWidget {
  const _BoxCard({required this.cur});
  final CurrentAccount cur;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final head = cur.head;
    final when = settleWhen(cur.periodStart, weekday: true);
    final since = (head == null || head.isOpening)
        ? 'settle.since_opening'.tr(namedArgs: {'when': when})
        : 'settle.since_settlement'
            .tr(namedArgs: {'n': '${head.number}', 'when': when});
    final negative = cur.expected < 0;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.card),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(Sp.lg),
            child: Row(
              children: [
                Container(
                  width: H.iconBox,
                  height: H.iconBox,
                  decoration: BoxDecoration(
                    color: AppTone.brand.softBg,
                    borderRadius: BorderRadius.circular(R.icon),
                  ),
                  child: Icon(LucideIcons.wallet,
                      size: 20, color: AppTone.brand.fill),
                ),
                const SizedBox(width: Sp.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('settle.in_box_now'.tr(), style: AppType.label()),
                      const SizedBox(height: Sp.xxs),
                      Text(
                        settleMoney(cur.expected),
                        textDirection: TextDirection.ltr,
                        style: AppType.amount(
                          color: negative ? AppColors.error : AppColors.textHi,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: Sp.xxs),
                      Text(
                        since,
                        style: AppType.muted(),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: AppColors.divider),
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: Sp.lg, vertical: Sp.sm),
            child: Column(
              children: [
                if (cur.openingBalance != 0)
                  _Line(
                    label: (head == null || head.isOpening)
                        ? 'settle.opening_balance'.tr()
                        : 'settle.carried_balance'.tr(),
                    value: settleMoney(cur.openingBalance),
                  ),
                _Line(
                  label:
                      '${'settle.cash_activations'.tr()} · ${cur.cashActivations.count}',
                  value: '+${formatIQD(cur.cashActivations.sum)}',
                  color: AppColors.success,
                ),
                _Line(
                  label:
                      '${'settle.debt_payments'.tr()} · ${cur.debtPayments.count}',
                  value: '+${formatIQD(cur.debtPayments.sum)}',
                  color: AppColors.success,
                ),
                _Line(
                  label: '${'settle.expenses'.tr()} · ${cur.expenses.count}',
                  value: '−${formatIQD(cur.expenses.sum)}',
                  color: AppColors.error,
                ),
              ],
            ),
          ),
          if (negative)
            _Note(
              tone: AppTone.danger,
              icon: LucideIcons.triangleAlert,
              text: 'settle.negative_warning'.tr(),
            ),
          if (cur.newDebts.sum > 0)
            _Note(
              tone: AppTone.neutral,
              icon: LucideIcons.info,
              text: 'settle.new_debts_info'.tr(namedArgs: {
                'amt': settleMoney(cur.newDebts.sum),
                'n': '${cur.newDebts.count}',
              }),
            ),
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.label, required this.value, this.color});
  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Sp.x6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: AppType.body(color: AppColors.textLabel),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: Sp.sm),
          Text(
            value,
            textDirection: TextDirection.ltr,
            style: AppType.bodyBold(color: color ?? AppColors.textHi),
          ),
        ],
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.tone, required this.icon, required this.text});
  final AppTone tone;
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Sp.lg, vertical: Sp.md),
      decoration: BoxDecoration(
        color: tone.softBg,
        border: Border(top: BorderSide(color: tone.softBorder)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 15, color: tone.fill),
          const SizedBox(width: Sp.sm),
          Expanded(
            child: Text(
              text,
              style: AppType.body(color: tone.onSoft).copyWith(height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.text, this.trailing});
  final String text;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Padding(
      padding: const EdgeInsets.only(bottom: Sp.sm),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text,
              style: AppType.cardTitleBold(color: AppColors.textHi),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (trailing != null) ToneChip(label: trailing!, dense: true),
        ],
      ),
    );
  }
}

/// حاوية بيضاء بحدّ — القوائم داخلها بلا حواف لكلّ صفّ.
class _Panel extends StatelessWidget {
  const _Panel({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.lg),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({required this.record, required this.onTap});
  final SettlementRecord record;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final r = record;
    final tone = r.isOpening ? AppTone.neutral : AppTone.brand;
    final title = r.isOpening
        ? 'settle.opening_title'.tr()
        : 'settle.settlement_n'.tr(namedArgs: {'n': '${r.number}'});
    return Material(
      color: AppColors.surface,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            border: Border(
                bottom: BorderSide(color: AppColors.divider, width: 0.5)),
          ),
          child: Opacity(
            opacity: r.isVoided ? 0.6 : 1.0,
            child: Row(
              children: [
                Container(
                  width: H.iconBox,
                  height: H.iconBox,
                  decoration: BoxDecoration(
                    color: tone.softBg,
                    borderRadius: BorderRadius.circular(R.icon),
                  ),
                  child: Center(
                    child: r.isOpening
                        ? Icon(LucideIcons.play, size: 16, color: tone.fill)
                        : Text(
                            '#${r.number}',
                            textDirection: TextDirection.ltr,
                            style: AppType.labelBold(color: tone.onSoft),
                          ),
                  ),
                ),
                const SizedBox(width: Sp.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              title,
                              style: AppType.bodyStrong(color: AppColors.textHi)
                                  .copyWith(
                                decoration: r.isVoided
                                    ? TextDecoration.lineThrough
                                    : null,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (r.isVoided) ...[
                            const SizedBox(width: Sp.x6),
                            ToneChip(
                              label: 'settle.voided'.tr(),
                              tone: AppTone.danger,
                              dense: true,
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: Sp.xxs),
                      Text(
                        settleWhen(r.cutAt, weekday: true),
                        style: AppType.muted(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: Sp.sm),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      settleMoney(r.isOpening ? r.openingBalance : r.received),
                      textDirection: TextDirection.ltr,
                      style: AppType.bodyBold(color: AppColors.textHi),
                    ),
                    if (!r.isOpening && r.carried != 0)
                      Text(
                        'settle.carried_short'
                            .tr(namedArgs: {'amt': settleMoney(r.carried)}),
                        style: AppType.muted(),
                      ),
                  ],
                ),
                const SizedBox(width: Sp.xs),
                Icon(LucideIcons.chevronLeft,
                    size: 16, color: AppColors.textLow),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StateCard extends StatelessWidget {
  const _StateCard({required this.icon, required this.text, this.action});
  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Container(
      padding: const EdgeInsets.all(Sp.huge),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.lg),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Icon(icon, size: 36, color: AppColors.textLow),
          const SizedBox(height: 10),
          Text(
            text,
            textAlign: TextAlign.center,
            style: AppType.body(color: AppColors.textMid).copyWith(height: 1.6),
          ),
          if (action != null) ...[const SizedBox(height: Sp.sm), action!],
        ],
      ),
    );
  }
}
