import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../api/balance_reports_api.dart';
import '../../core/util/format.dart';
import '../../core/widgets/design_sheet.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import 'balance_reports_screen.dart';

/// تفاصيل فترة من «تقارير الأرصدة»: خلاصتها سطراً سطراً حتى «صافي ربح الفترة»، ثمّ حركاتها — عشرةٌ ثمّ «عرض المزيد» — بفلاترها
/// وبحثها. لكلّ تفعيل آجل حاله بكلمة (المالك: «كون أكو فد شي يبيّن إنّه كان دين وتحوّل إلى نقدي أو إلى دخل»): «كان دين وتسدّد»،
/// «…بعد الإغلاق — صار ربح»، «تسدّد منه … باقي …»، «دين باقي …».

/// رقمٌ بإشارته معزولاً (LTR) فلا تقفز «+» أو «−» بعد الرقم في سطرٍ عربيّ، و«د.ع» بعده.
final String _lri = String.fromCharCode(0x2066);
final String _pdi = String.fromCharCode(0x2069);
String balanceSigned(num v, {String sign = ''}) => '$_lri$sign${formatIQD(v.abs())}$_pdi د.ع';

class BalancePeriodScreen extends StatefulWidget {
  const BalancePeriodScreen({super.key, required this.controller, required this.periodId});
  final BalanceReportsController controller;
  final int periodId;

  @override
  State<BalancePeriodScreen> createState() => _BalancePeriodScreenState();
}

class _BalancePeriodScreenState extends State<BalancePeriodScreen> {
  final _searchCtrl = TextEditingController();
  Timer? _debounce;
  BalanceFilter _filter = BalanceFilter.all;
  String _q = '';

  List<BalanceMove> _items = const [];
  int _total = 0;
  Map<BalanceFilter, int>? _counts;
  int _want = BalanceReportsApi.firstShown;
  bool _loading = true;
  bool _busy = false;
  bool _failed = false;
  String? _firstError;

  /// كلّ قراءةٍ بجيلها: ردٌّ يصل بعد فلترٍ أو كتابةٍ أحدث يُهمل.
  int _gen = 0;
  int _seenVersion = 0;

  @override
  void initState() {
    super.initState();
    _seenVersion = widget.controller.version;
    widget.controller.addListener(_onBoard);
    _fill(fromStart: true);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onBoard);
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  /// لوحةٌ جديدة (تسوية، إغلاق، تعديل…): الخلاصة من اللوحة، والحركات تُعاد من الخادم — وما كان معروضاً يبقى معروضاً.
  void _onBoard() {
    if (!mounted) return;
    final c = widget.controller;
    if (c.data?.periodOf(widget.periodId) == null) {
      // حُذفت الفترة
      if (Navigator.of(context).canPop()) Navigator.of(context).pop();
      return;
    }
    if (c.version != _seenVersion) {
      _seenVersion = c.version;
      _fill(fromStart: true);
    } else {
      setState(() {});
    }
  }

  /// يملأ القائمة حتى ما يُعرض ([_want]) — من أوّلها ([fromStart]) أو بعد ما حُمل.
  Future<void> _fill({required bool fromStart}) async {
    final gen = ++_gen;
    setState(() {
      _busy = true;
      _failed = false;
    });
    final acc = fromStart ? <BalanceMove>[] : List<BalanceMove>.of(_items);
    final seen = {for (final m in acc) m.key};
    var total = fromStart ? 0 : _total;
    var counts = _counts;
    String? error;
    while (true) {
      final r = await BalanceReportsApi.period(widget.periodId, filter: _filter, q: _q, offset: acc.length);
      if (!mounted || gen != _gen) return;
      if (!r.ok) {
        error = r.message ?? 'تعذّر تحميل الحركات';
        break;
      }
      final page = r.data!;
      total = page.total;
      counts = page.counts;
      var added = 0;
      for (final m in page.items) {
        if (seen.add(m.key)) {
          acc.add(m);
          added++;
        }
      }
      // صفحةٌ فارغة (أو كلّها مكرّرة) تُنهي القائمة — لا دوران
      if (page.items.isEmpty || added == 0) {
        total = acc.length;
        break;
      }
      if (acc.length >= total || acc.length >= _want) break;
    }
    setState(() {
      _busy = false;
      _loading = false;
      if (error != null && acc.isEmpty) {
        _firstError = error;
        _items = const [];
        _total = 0;
      } else {
        _firstError = null;
        _failed = error != null;
        _items = acc;
        _total = error != null ? (total > acc.length ? total : acc.length + 1) : total;
        _counts = counts;
      }
    });
  }

  void _setFilter(BalanceFilter f) {
    if (f == _filter) return;
    setState(() {
      _filter = f;
      _want = BalanceReportsApi.firstShown;
      _loading = true;
      _items = const [];
    });
    _fill(fromStart: true);
  }

  void _onSearch(String text) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      final q = text.trim();
      if (!mounted || q == _q) return;
      setState(() {
        _q = q;
        _want = BalanceReportsApi.firstShown;
        _loading = true;
        _items = const [];
      });
      _fill(fromStart: true);
    });
  }

  void _more() {
    final next = (_want < _items.length ? _want : _items.length) + BalanceReportsApi.showStep;
    setState(() => _want = next);
    if (_items.length < next && _items.length < _total) _fill(fromStart: false);
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final c = widget.controller;
    final p = c.data?.periodOf(widget.periodId);
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        title: Text(p == null ? 'تفاصيل الفترة' : balancePeriodTitle(p), style: AppType.title(color: AppColors.textHi)),
      ),
      body: p == null
          ? const SizedBox.shrink()
          : SafeArea(
              child: ListView(
                key: const ValueKey('bal-detail-list'),
                padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.sm, Sp.lg, Sp.huge * 2),
                children: [
                  _summary(p),
                  if (p.adjustments.isNotEmpty) ...[
                    const SizedBox(height: Sp.md),
                    BalanceAdjustmentsList(period: p, controller: c),
                  ],
                  const SizedBox(height: Sp.md),
                  BalanceActions(period: p, controller: c),
                  const SizedBox(height: Sp.lg),
                  SingleChildScrollView(
                    key: const ValueKey('bal-filters'),
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        // «المدراء» تظهر حين في الفترة حركاتٌ لهم داخلة بالحساب وحده
                        for (final f in BalanceFilter.values.where((f) => f != BalanceFilter.managers || (_counts?[f] ?? 0) > 0)) ...[
                          if (f != BalanceFilter.values.first) const SizedBox(width: Sp.x6),
                          SheetQuickChip(
                            key: ValueKey('bal-filter-${f.wire}'),
                            label: _counts?[f] == null ? f.label : '${f.label} ${formatIQD(_counts![f]!)}',
                            selected: _filter == f,
                            onTap: () => _setFilter(f),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: Sp.sm),
                  SheetSearchField(key: const ValueKey('bal-search'), controller: _searchCtrl, hint: 'ابحث باسم المستخدم', onChanged: _onSearch),
                  const SizedBox(height: Sp.sm),
                  _moves(),
                ],
              ),
            ),
    );
  }

  Widget _summary(BalancePeriod p) {
    final closed = p.isClosed;
    final mg = p.managers;
    Widget rule() => Padding(padding: const EdgeInsets.symmetric(vertical: Sp.xs), child: Divider(height: 1, thickness: 1, color: AppColors.divider));
    return Material(
      key: const ValueKey('bal-summary'),
      color: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(R.card), side: BorderSide(color: AppColors.border)),
      child: Padding(
        padding: const EdgeInsets.all(Sp.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                ToneChip(key: const ValueKey('bal-state'), label: p.state.label, tone: balanceStateTone(p.state), dense: true),
                const SizedBox(width: Sp.sm),
                Expanded(
                  child: Text(
                    '${balancePeriodRange(p)}${closed && p.closedAtMs != null ? ' · أُغلقت ${balanceDay(p.closedAtMs!)}' : ''}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.micro(color: AppColors.textMid),
                  ),
                ),
              ],
            ),
            const SizedBox(height: Sp.sm),
            BalanceLine(label: 'مبلغ الشحن', value: balanceIqd(p.amount), strong: true),
            // العدد بجانب المبيعات وحدها (كلّ تفعيلات الفترة). النقد والتسديد والديون بلا عدد: أعداد الخادم تشمل ما وقع بعد
            // الإغلاق (صار ربحاً لا «طبّلك») فلا تطابق مبالغها — والأعداد الدقيقة على شرائح الفلاتر تحتها.
            BalanceLine(label: 'مبيعات الفترة (${p.nActivations} تفعيل)', value: balanceIqd(p.sales)),
            BalanceLine(label: 'نقد التفعيلات', value: balanceIqd(p.cashNow), valueColor: AppTone.success.onSoft),
            BalanceLine(label: 'تسديد ديون الفترة', value: balanceIqd(p.paidIn), valueColor: AppTone.success.onSoft),
            if (mg != null && mg.cash > 0)
              BalanceLine(key: const ValueKey('bal-sum-mgr-cash'), label: 'شحن المدراء الفرعيّين نقداً', value: balanceIqd(mg.cash), valueColor: AppTone.success.onSoft),
            if (mg != null && mg.paidIn > 0)
              BalanceLine(key: const ValueKey('bal-sum-mgr-paid'), label: 'تسديد ديون المدراء', value: balanceIqd(mg.paidIn), valueColor: AppTone.success.onSoft),
            if (mg != null && mg.withdrawn > 0)
              BalanceLine(key: const ValueKey('bal-sum-mgr-withdrawn'), label: 'سحب رصيد من المدراء', value: balanceSigned(mg.withdrawn, sign: '−'), valueColor: AppTone.danger.onSoft),
            rule(),
            BalanceLine(key: const ValueKey('bal-sum-collected'), label: 'المحصَّل', value: balanceIqd(p.collected), strong: true),
            if (p.adjustmentsSum > 0) BalanceLine(label: 'تسويات الرصيد', value: balanceIqd(p.adjustmentsSum)),
            BalanceLine(
              key: const ValueKey('bal-sum-remaining'),
              label: 'المتبقّي من مبلغ الشحن',
              value: p.remaining > 0 ? balanceIqd(p.remaining) : 'مكتمل',
              valueColor: p.remaining > 0 ? AppTone.danger.onSoft : AppTone.success.onSoft,
            ),
            rule(),
            BalanceLine(label: 'ديون الفترة', value: balanceIqd(p.debtsCreated)),
            BalanceLine(
              label: mg != null && mg.loans > 0 ? 'الباقي منها بذمّة المشتركين والمدراء' : 'الباقي منها بذمّة المشتركين',
              value: balanceIqd(p.debtsOpen),
              valueColor: p.debtsOpen > 0 ? AppTone.danger.onSoft : null,
            ),
            if (mg != null && mg.loans > 0) BalanceLine(key: const ValueKey('bal-sum-mgr-loans'), label: 'منها شحن آجل للمدراء', value: balanceIqd(mg.loans)),
            if (mg != null && mg.loans > 0)
              BalanceLine(key: const ValueKey('bal-sum-mgr-open'), label: 'الباقي على المدراء', value: balanceIqd(mg.open), valueColor: mg.open > 0 ? AppTone.danger.onSoft : null),
            if (p.writtenOff > 0) BalanceLine(label: 'نقص منها بلا تسديد (تعديل دين)', value: balanceIqd(p.writtenOff)),
            if (p.untracked > 0) BalanceLine(label: 'آجل لم يُسجَّل دينه على المشترك', value: balanceIqd(p.untracked)),
            if (closed || p.lateProfit > 0)
              BalanceLine(key: const ValueKey('bal-sum-late'), label: 'دخل بعد الإغلاق (ربح)', value: balanceIqd(p.lateProfit), valueColor: AppTone.success.onSoft),
            rule(),
            BalanceLine(
              key: const ValueKey('bal-sum-net'),
              label: p.net >= 0 ? 'صافي ربح الفترة' : 'الصافي (لم يعُد مبلغ الشحن بعد)',
              value: balanceSigned(p.net, sign: p.net < 0 ? '−' : ''),
              strong: true,
              valueColor: p.net >= 0 ? AppTone.success.onSoft : AppTone.danger.onSoft,
            ),
            if (p.pocketOutstanding > 0)
              Padding(
                padding: const EdgeInsets.only(top: Sp.xs),
                child: Text('دفعت ${formatIQD(p.pocketOutstanding)} بـ«تسوية الرصيد» وبعدها ما رجعت — ترجع من ديون الفترة.', style: AppType.micro(color: AppColors.textMid)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _box(Widget child) => Container(
        padding: const EdgeInsets.symmetric(horizontal: Sp.lg, vertical: Sp.xxl),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(R.card), border: Border.all(color: AppColors.border), color: AppColors.surface),
        child: Center(child: child),
      );

  Widget _moves() {
    if (_firstError != null) {
      return _box(
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_firstError!, textAlign: TextAlign.center, style: AppType.body(color: AppColors.textMid)),
            const SizedBox(height: Sp.sm),
            TextButton.icon(
              key: const ValueKey('bal-moves-retry'),
              onPressed: () {
                setState(() => _loading = true);
                _fill(fromStart: true);
              },
              icon: const Icon(LucideIcons.refreshCw, size: 16),
              label: const Text('أعد المحاولة'),
            ),
          ],
        ),
      );
    }
    if (_loading && _items.isEmpty) return _box(const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4)));
    if (_items.isEmpty) return _box(Text(_q.isEmpty ? 'لا حركات هنا' : 'لا حركة بهذا الاسم', key: const ValueKey('bal-moves-empty'), style: AppType.body(color: AppColors.textMid)));
    final shown = _want < _items.length ? _want : _items.length;
    final hasMore = shown < _items.length || _items.length < _total;
    Widget? footer;
    if (_busy) {
      footer = _foot(key: const ValueKey('bal-moves-busy'), child: const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.2)));
    } else if (_failed) {
      footer = _foot(
        key: const ValueKey('bal-moves-retry'),
        onTap: () => _fill(fromStart: false),
        icon: LucideIcons.refreshCw,
        label: 'تعذّر تحميل المزيد — أعد المحاولة',
        color: AppTone.danger.onSoft,
      );
    } else if (hasMore) {
      footer = _foot(key: const ValueKey('bal-moves-more'), onTap: _more, icon: LucideIcons.chevronDown, label: 'عرض المزيد ($shown من $_total)', color: AppColors.brand);
    } else if (shown > BalanceReportsApi.firstShown) {
      footer = _foot(
        key: const ValueKey('bal-moves-less'),
        onTap: () => setState(() => _want = BalanceReportsApi.firstShown),
        icon: LucideIcons.chevronUp,
        label: 'عرض أقلّ',
        color: AppColors.textMid,
      );
    }
    return Material(
      key: const ValueKey('bal-moves'),
      color: AppColors.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(R.card), side: BorderSide(color: AppColors.border)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < shown; i++) ...[
            if (i > 0) Divider(height: 1, thickness: 1, indent: Sp.md, endIndent: Sp.md, color: AppColors.divider),
            BalanceMoveRow(key: ValueKey('bal-move-${_items[i].key}'), move: _items[i]),
          ],
          if (footer != null) ...[
            Divider(height: 1, thickness: 1, color: AppColors.divider),
            footer,
          ],
        ],
      ),
    );
  }

  Widget _foot({Key? key, VoidCallback? onTap, IconData? icon, String? label, Color? color, Widget? child}) {
    return InkWell(
      key: key,
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: Sp.sm),
          child: Center(
            child: child ??
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(child: Text(label!, maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: AppType.bodyBold(color: color))),
                    const SizedBox(width: Sp.x6),
                    Icon(icon, size: 16, color: color),
                  ],
                ),
          ),
        ),
      ),
    );
  }
}

/// سطر حركة: مربّع أيقونةٍ بلون نوعها، الاسم وشارته وقبالته المبلغ، التفاصيل بخطٍّ يُقرأ، ثمّ حال الدين بشارته.
class BalanceMoveRow extends StatelessWidget {
  const BalanceMoveRow({super.key, required this.move, this.nowMs});
  final BalanceMove move;
  final int? nowMs;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final m = move;
    late final IconData icon;
    late final AppTone tone;
    late final String title;
    late final List<({String text, AppTone tone})> tags;
    late final String amount;
    Color amountColor = AppColors.textHi;
    late final List<String?> details;
    ({String text, AppTone tone})? status;
    String? note;
    switch (m) {
      case BalanceActMove():
        tone = switch (m.pay) { BalancePay.cash => AppTone.success, BalancePay.credit => AppTone.warning, BalancePay.partial => AppTone.brand };
        icon = switch (m.pay) { BalancePay.cash => LucideIcons.banknote, BalancePay.credit => LucideIcons.clock, BalancePay.partial => LucideIcons.chartPie };
        title = m.username;
        tags = [(text: m.pay.label, tone: tone), if (m.afterClose) (text: 'بعد الإغلاق — ربح', tone: AppTone.brand)];
        amount = balanceIqd(m.price);
        details = [
          balanceDayTime(m.atMs, nowMs: nowMs),
          m.package,
          if (m.pay == BalancePay.partial) 'نقد ${formatIQD(m.cash)} · دين ${formatIQD(m.debt + m.untracked)}',
          if (m.excess > 0) 'وزيادة ${formatIQD(m.excess)} سدّت ديناً أقدم',
          if (m.by != null) 'نفّذها ${m.by}',
        ];
        final n = balanceDebtNote(m, nowMs: nowMs);
        status = n == null ? null : (text: n.text, tone: balanceToneOf(n.tone));
      case BalancePayMove():
        tone = AppTone.success;
        icon = LucideIcons.handCoins;
        title = m.username;
        tags = [(text: 'تسديد دين', tone: AppTone.success)];
        amount = balanceSigned(m.amount, sign: '+');
        amountColor = AppTone.success.onSoft;
        details = [balanceDayTime(m.atMs, nowMs: nowMs), if (m.advance) 'من دفعةٍ مقدَّمة', if (m.by != null) 'استلمها ${m.by}'];
        status = m.afterClose ? (text: 'بعد الإغلاق — صار ربح', tone: AppTone.brand) : (text: 'أُضيف إلى «المحصَّل»', tone: AppTone.success);
      case BalanceMgrMove():
        // شحنٌ نقديّ وتسديد دين: نقدٌ دخل (+). سحب: رصيدٌ رجع ونقدٌ رُدّ (−). شحنٌ آجل: دينٌ بحاله كدين التفعيل.
        tone = switch (m.op) { BalanceMgrOp.loan => AppTone.warning, BalanceMgrOp.withdraw => AppTone.danger, _ => AppTone.success };
        icon = switch (m.op) { BalanceMgrOp.pay => LucideIcons.handCoins, BalanceMgrOp.withdraw => LucideIcons.undo2, _ => LucideIcons.users };
        title = m.username;
        tags = [(text: m.op.label, tone: tone), if (m.op == BalanceMgrOp.loan && m.afterClose) (text: 'بعد الإغلاق', tone: AppTone.brand)];
        amount = switch (m.op) {
          BalanceMgrOp.loan => balanceIqd(m.amount),
          BalanceMgrOp.withdraw => balanceSigned(m.amount, sign: '−'),
          _ => balanceSigned(m.amount, sign: '+'),
        };
        amountColor = switch (m.op) { BalanceMgrOp.withdraw => AppTone.danger.onSoft, BalanceMgrOp.loan => AppColors.textHi, _ => AppTone.success.onSoft };
        details = [balanceDayTime(m.atMs, nowMs: nowMs), 'مدير فرعيّ', if (m.by != null) 'نفّذها ${m.by}'];
        note = m.note;
        if (m.op == BalanceMgrOp.loan) {
          final n = balanceMgrDebtNote(m, nowMs: nowMs);
          status = n == null ? null : (text: n.text, tone: balanceToneOf(n.tone));
        } else if (m.op == BalanceMgrOp.withdraw) {
          status = (text: m.afterClose ? 'بعد الإغلاق — نقص من الربح' : 'خُصم من «المحصَّل»', tone: AppTone.danger);
        } else {
          status = m.afterClose ? (text: 'بعد الإغلاق — صار ربح', tone: AppTone.brand) : (text: 'أُضيف إلى «المحصَّل»', tone: AppTone.success);
        }
      case BalanceAdjustMove():
        tone = AppTone.brand;
        icon = LucideIcons.scale;
        title = 'تسوية الرصيد';
        tags = [(text: m.source.label, tone: AppTone.brand)];
        amount = balanceIqd(m.amount);
        details = [balanceDayTime(m.atMs, nowMs: nowMs)];
        note = m.note;
    }
    final info = details.whereType<String>().where((x) => x.trim().isNotEmpty).join(' · ');
    const pad = Sp.sm + 2;
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: Sp.md, end: Sp.md, top: pad, bottom: pad),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(color: tone.softBg, borderRadius: BorderRadius.circular(R.sm)),
              child: Icon(icon, size: 17, color: tone.fill),
            ),
          ),
          const SizedBox(width: Sp.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // المبلغ على سطر الاسم ولو التفّ الاسم؛ ولا يأخذ أكثر من نصف السطر (رقمٌ بعشر خاناتٍ يصغر ولا يفيض)
                LayoutBuilder(
                  builder: (context, box) => Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Wrap(
                          spacing: Sp.x6,
                          runSpacing: 2,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.rowValue(color: AppColors.textHi).copyWith(fontWeight: FontWeight.w700)),
                            for (final t in tags) ToneChip(label: t.text, tone: t.tone, dense: true),
                          ],
                        ),
                      ),
                      const SizedBox(width: Sp.sm),
                      ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: box.maxWidth * 0.5),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: AlignmentDirectional.centerEnd,
                          child: Text(
                            amount,
                            maxLines: 1,
                            style: AppType.rowValue(color: amountColor).copyWith(fontWeight: FontWeight.w700, fontFeatures: const [FontFeature.tabularFigures()]),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (info.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(info, maxLines: 3, overflow: TextOverflow.ellipsis, style: AppType.body(color: AppColors.textMid)),
                ],
                if (note != null) ...[
                  const SizedBox(height: 2),
                  Text(note, maxLines: 3, overflow: TextOverflow.ellipsis, style: AppType.body(color: AppColors.textBody)),
                ],
                if (status != null) ...[
                  const SizedBox(height: Sp.xs),
                  BalanceMoveStatus(key: const ValueKey('bal-move-status'), text: status.text, tone: status.tone),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// حالة الحركة تحت تفاصيلها («كان دين وتسدّد — 22 آب»، «تسدّد منه … · باقي …»): بنغمتها كالحبّة، لكنّها **تلتفّ** على سطرٍ ثانٍ حين
/// يضيق العرض ولا تُختصر «…» أبداً — التاريخ والمبلغ فيها هما الخبر، و[ToneChip] سطرٌ واحد يقصّهما على هاتفٍ ٣٢٠ أو بخطٍّ مكبَّر.
class BalanceMoveStatus extends StatelessWidget {
  const BalanceMoveStatus({super.key, required this.text, required this.tone});

  final String text;
  final AppTone tone;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Sp.sm, vertical: 3),
      decoration: BoxDecoration(
        color: tone.softBg,
        borderRadius: BorderRadius.circular(R.chip),
        border: Border.all(color: tone.softBorder),
      ),
      child: Text(text, style: AppType.pillLabel(color: tone.onSoft).copyWith(letterSpacing: 0)),
    );
  }
}
