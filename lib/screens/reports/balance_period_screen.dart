import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../api/balance_reports_api.dart';
import '../../core/util/format.dart';
import '../../core/util/server_time.dart';
import '../../core/widgets/design_sheet.dart';
import '../../services/balance_sub_names.dart';
import '../../services/merged_mode.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import 'balance_reports_screen.dart';
import 'v2/report_kit.dart';

/// تفاصيل فترة من «تقارير الأرصدة»: خلاصتها سطراً سطراً حتى «صافي ربح الفترة»، ثمّ حركاتها — عشرةٌ ثمّ «عرض المزيد» — بفلاترها
/// وبحثها. لكلّ تفعيل آجل حاله بكلمة (المالك: «كون أكو فد شي يبيّن إنّه كان دين وتحوّل إلى نقدي أو إلى دخل»): «كان دين وتسدّد»،
/// «…بعد الإغلاق — صار ربح»، «تسدّد منه … باقي …»، «دين باقي …».

/// رقمٌ بإشارته معزولاً (LTR) فلا تقفز «+» أو «−» بعد الرقم في سطرٍ عربيّ، و«د.ع» بعده.
final String _lri = String.fromCharCode(0x2066);
final String _pdi = String.fromCharCode(0x2069);
String balanceSigned(num v, {String sign = ''}) => '$_lri$sign${formatIQD(v.abs())}$_pdi د.ع';

class BalancePeriodScreen extends StatefulWidget {
  const BalancePeriodScreen({super.key, required this.controller, required this.periodId, this.initialFilter = BalanceFilter.all});
  final BalanceReportsController controller;
  final int periodId;

  /// الفلتر أوّل الفتح — «ديون الفترة» في القائمة تفتح «ديون باقية» (لمس الرقم يفتح حركاته كبقيّة التقارير الموحّدة).
  final BalanceFilter initialFilter;

  @override
  State<BalancePeriodScreen> createState() => _BalancePeriodScreenState();
}

class _BalancePeriodScreenState extends State<BalancePeriodScreen> {
  Timer? _debounce;
  late BalanceFilter _filter = widget.initialFilter;
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

  /// الاسم العربيّ بجانب اليوزر (٢٠ نوفمبر — المالك: «اريد اضيف اسم المشترك الي بالعربي»).
  late final BalanceSubNames _names = BalanceSubNames(companyKey: widget.controller.companyKey);

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
      final r = await BalanceReportsApi.period(widget.periodId, filter: _filter, q: _q, offset: acc.length, companyKey: widget.controller.companyKey);
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
    unawaited(_loadNames());
  }

  /// أسماء ما حُمل من الحركات ممّا لم يُعرف بعد — القائمة تُعرض بلا انتظارها، والاسم يظهر حين يصل.
  Future<void> _loadNames() async {
    if (_items.isEmpty) return;
    if (await _names.fill(BalanceSubNames.usersOf(_items)) && mounted) setState(() {});
  }

  String? _nameOf(BalanceMove m) => switch (m) {
        BalanceActMove() => _names.of(m.username),
        BalancePayMove() => _names.of(m.username),
        _ => null,
      };

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

  PreferredSizeWidget? _companyLine() {
    final key = widget.controller.companyKey;
    final co = key == null ? null : MergedMode.rowCompanyName(key);
    if (co == null) return null;
    return PreferredSize(
      preferredSize: const Size.fromHeight(26),
      child: Padding(
        padding: const EdgeInsetsDirectional.only(start: Sp.lg, end: Sp.lg, bottom: Sp.x6),
        child: Align(
          alignment: AlignmentDirectional.centerStart,
          child: Text('«$co»${widget.controller.canWrite ? '' : ' · للعرض هنا'}',
              key: const ValueKey('bal-detail-company'), maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.micro(color: AppColors.textMid)),
        ),
      ),
    );
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
        // «كل الشركات»: اسم شركة الفترة تحت العنوان (الشاشة مدفوعةٌ فوق القسم بلا شريطه)
        bottom: _companyLine(),
      ),
      body: p == null
          ? const SizedBox.shrink()
          : SafeArea(
              child: ListView(
                key: const ValueKey('bal-detail-list'),
                padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.sm, Sp.lg, Sp.huge * 2),
                children: [
                  // بلا مبلغ شحن بعد: التنبيه نفسه فوق الخلاصة (والزرّ تحتها)
                  if (p.amountPending && !p.isClosed) ...[
                    const BalanceBannerBox(key: ValueKey('bal-banner'), kind: BalanceBannerKind.amount, text: balanceAmountPendingText),
                    const SizedBox(height: Sp.md),
                  ],
                  _summary(p),
                  if (p.adjustments.isNotEmpty) ...[
                    const SizedBox(height: Sp.md),
                    BalanceAdjustmentsList(period: p, controller: c),
                  ],
                  if (c.canWrite) ...[
                    const SizedBox(height: Sp.md),
                    BalanceActions(period: p, controller: c),
                  ],
                  const SizedBox(height: Sp.lg),
                  _movesCard(),
                ],
              ),
            ),
    );
  }

  Widget _summary(BalancePeriod p) {
    final closed = p.isClosed;
    final mg = p.managers;
    Widget rule() => Padding(padding: const EdgeInsets.symmetric(vertical: Sp.xs), child: Divider(height: 1, thickness: 1, color: AppColors.divider));
    // خلاصة الفترة ببطاقة التقارير الموحّدة: عنوانها بمربّع أيقونةٍ بلون حالها وشارة الحال، ثمّ الحساب سطراً سطراً
    return RpCard(
      key: const ValueKey('bal-summary'),
      tint: balanceStateRpTone(p.state).fg,
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            RpTitle(
              icon: LucideIcons.calculator,
              title: 'خلاصة الفترة',
              tone: balanceStateRpTone(p.state),
              trailing: ToneChip(key: const ValueKey('bal-state'), label: p.state.label, tone: balanceStateTone(p.state), dense: true),
            ),
            const SizedBox(height: Sp.x6),
            Text(
              '${balancePeriodRange(p)}${closed && p.closedAtMs != null ? ' · أُغلقت ${balanceDay(p.closedAtMs!)}' : ''}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppType.micro(color: AppColors.textMid),
            ),
            const SizedBox(height: Sp.sm),
            BalanceLine(key: const ValueKey('bal-sum-amount'), label: 'مبلغ الشحن', value: p.amountPending ? 'لم يُكتب بعد' : balanceIqd(p.amount), strong: true),
            // العدد بجانب المبيعات وحدها (كلّ تفعيلات الفترة). النقد والتسديد والديون بلا عدد: أعداد الخادم تشمل ما وقع بعد
            // الإغلاق (صار ربحاً لا «طبّلك») فلا تطابق مبالغها — والأعداد الدقيقة على شرائح الفلاتر تحتها.
            BalanceLine(label: 'مبيعات الفترة (${p.nActivations} تفعيل)', value: balanceIqd(p.sales)),
            BalanceLine(label: 'نقد التفعيلات', value: balanceIqd(p.cashNow), valueColor: AppTone.success.onSoft),
            BalanceLine(label: 'تسديد ديون الفترة', value: balanceIqd(p.paidIn), valueColor: AppTone.success.onSoft),
            if (mg != null && mg.cash > 0)
              BalanceLine(key: const ValueKey('bal-sum-mgr-cash'), label: 'شحن المدراء الفرعيّين نقداً', value: balanceIqd(mg.cash), valueColor: AppTone.success.onSoft),
            // فوائد الشحن النقديّ (٢١ نوفمبر): مستلَمةٌ نقداً مع الشحن — داخلةٌ في «المحصَّل»
            if (mg != null && mg.feesCash > 0)
              BalanceLine(key: const ValueKey('bal-sum-mgr-fees-cash'), label: 'فوائد الشحن النقدي', value: balanceIqd(mg.feesCash), valueColor: AppTone.success.onSoft),
            if (mg != null && mg.paidIn > 0)
              BalanceLine(key: const ValueKey('bal-sum-mgr-paid'), label: 'تسديد ديون المدراء', value: balanceIqd(mg.paidIn), valueColor: AppTone.success.onSoft),
            if (mg != null && mg.withdrawn > 0)
              BalanceLine(key: const ValueKey('bal-sum-mgr-withdrawn'), label: 'سحب رصيد من المدراء', value: balanceSigned(mg.withdrawn, sign: '−'), valueColor: AppTone.danger.onSoft),
            rule(),
            BalanceLine(key: const ValueKey('bal-sum-collected'), label: 'المحصَّل', value: balanceIqd(p.collected), strong: true),
            if (p.adjustmentsSum > 0) BalanceLine(label: 'تسويات الرصيد', value: balanceIqd(p.adjustmentsSum)),
            // بلا مبلغ: المتبقّي والصافي لا يُعرفان قبل المبلغ («—» لا صفر ولا «مكتمل»)
            if (p.amountPending)
              const BalanceLine(key: ValueKey('bal-sum-remaining'), label: 'المتبقّي من مبلغ الشحن', value: '—')
            else
              BalanceLine(
                key: const ValueKey('bal-sum-remaining'),
                label: 'المتبقّي من مبلغ الشحن',
                value: p.remaining > 0 ? balanceIqd(p.remaining) : 'مكتمل',
                valueColor: p.remaining > 0 ? AppTone.danger.onSoft : AppTone.success.onSoft,
              ),
            rule(),
            BalanceLine(label: 'ديون الفترة', value: balanceIqd(p.debtsCreated)),
            BalanceLine(
              label: mg != null && (mg.loans > 0 || mg.fees > 0) ? 'الباقي منها بذمّة المشتركين والمدراء' : 'الباقي منها بذمّة المشتركين',
              value: balanceIqd(p.debtsOpen),
              valueColor: p.debtsOpen > 0 ? AppTone.danger.onSoft : null,
            ),
            if (mg != null && mg.loans > 0) BalanceLine(key: const ValueKey('bal-sum-mgr-loans'), label: 'منها شحن آجل للمدراء', value: balanceIqd(mg.loans)),
            // فوائد الشحن الآجل (٢٠ نوفمبر): ديونٌ في «ديون أخرى» فوق الشحنات، داخلةٌ في ديون الفترة وباقيها في «الباقي على المدراء»
            if (mg != null && mg.fees > 0) BalanceLine(key: const ValueKey('bal-sum-mgr-fees'), label: 'منها فوائد الشحن الآجل', value: balanceIqd(mg.fees)),
            if (mg != null && (mg.loans > 0 || mg.fees > 0))
              BalanceLine(key: const ValueKey('bal-sum-mgr-open'), label: 'الباقي على المدراء', value: balanceIqd(mg.open), valueColor: mg.open > 0 ? AppTone.danger.onSoft : null),
            if (p.writtenOff > 0) BalanceLine(label: 'نقص منها بلا تسديد (تعديل دين)', value: balanceIqd(p.writtenOff)),
            if (p.untracked > 0) BalanceLine(label: 'آجل لم يُسجَّل دينه على المشترك', value: balanceIqd(p.untracked)),
            if (closed || p.lateProfit > 0)
              BalanceLine(key: const ValueKey('bal-sum-late'), label: 'دخل بعد الإغلاق (ربح)', value: balanceIqd(p.lateProfit), valueColor: AppTone.success.onSoft),
            rule(),
            if (p.amountPending)
              const BalanceLine(key: ValueKey('bal-sum-net'), label: 'الصافي (يُحسب بعد كتابة مبلغ الشحن)', value: '—', strong: true)
            else
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
    );
  }

  /// الحركات ببطاقة التقارير الموحّدة: العنوان وعددها، شرائح الفلاتر بأعدادها، البحث، ثمّ الحركات تحت أيّامها.
  Widget _movesCard() {
    final counted = _firstError == null && !(_loading && _items.isEmpty);
    return RpCard(
      key: const ValueKey('bal-moves-card'),
      padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.lg, Sp.lg, Sp.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          RpTitle(
            icon: LucideIcons.listOrdered,
            title: 'الحركات',
            tone: RpTone.neutral,
            trailing: counted ? Text('${formatIQD(_total)} حركة', style: AppType.pillBold(color: AppColors.textMid)) : null,
          ),
          const SizedBox(height: Sp.md),
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
          RpSearchBox(key: const ValueKey('bal-search'), query: _q, hint: 'ابحث باسم المستخدم', onChanged: _onSearch),
          const SizedBox(height: Sp.sm),
          _moves(),
        ],
      ),
    );
  }

  Widget _box(Widget child) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: Sp.sm, vertical: Sp.xl),
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
    // تحت كلّ يومٍ حركاته (كبقيّة التقارير الموحّدة): رأسٌ بالتاريخ وعدد المعروض منه، والوقت بساعة ١٢ بجانب كلّ حركة
    final groups = <({String day, List<BalanceMove> rows})>[];
    for (final m in _items.take(shown)) {
      final day = balanceDay(m.atMs);
      if (groups.isEmpty || groups.last.day != day) {
        groups.add((day: day, rows: [m]));
      } else {
        groups.last.rows.add(m);
      }
    }
    return Column(
      key: const ValueKey('bal-moves'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final g in groups) ...[
          const SizedBox(height: Sp.x6),
          RpDayHead(day: RpDay(date: g.day, count: g.rows.length, sum: null, rows: const [])),
          for (var i = 0; i < g.rows.length; i++) ...[
            if (i > 0) Divider(height: 1, thickness: 1, color: AppColors.divider),
            BalanceMoveRow(key: ValueKey('bal-move-${g.rows[i].key}'), move: g.rows[i], name: _nameOf(g.rows[i])),
          ],
        ],
        if (footer != null) ...[
          const SizedBox(height: Sp.xs),
          Divider(height: 1, thickness: 1, color: AppColors.divider),
          footer,
        ],
      ],
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
  const BalanceMoveRow({super.key, required this.move, this.nowMs, this.name});
  final BalanceMove move;
  final int? nowMs;

  /// اسم المشترك العربيّ (٢٠ نوفمبر) — للتفعيل وتسديد الدين وحدهما: العنوان، واليوزر بعده (المالك ٢٣ نوفمبر: «العربي ومن ثم
  /// اليوزر»)؛ null ⇒ اليوزر عنوانٌ وحده كما كان.
  final String? name;

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
        details = [if (m.advance) 'من دفعةٍ مقدَّمة', if (m.by != null) 'استلمها ${m.by}'];
        status = m.afterClose ? (text: 'بعد الإغلاق — صار ربح', tone: AppTone.brand) : (text: 'أُضيف إلى «المحصَّل»', tone: AppTone.success);
      case BalanceMgrMove():
        // شحنٌ نقديّ وتسديد دين وفائدة الشحن النقديّ: نقدٌ دخل (+). سحب: رصيدٌ رجع ونقدٌ رُدّ (−). شحنٌ آجل وفائدته: دينٌ بحاله كدين التفعيل.
        tone = m.op.debtLike ? AppTone.warning : (m.op == BalanceMgrOp.withdraw ? AppTone.danger : AppTone.success);
        icon = switch (m.op) {
          BalanceMgrOp.pay => LucideIcons.handCoins,
          BalanceMgrOp.withdraw => LucideIcons.undo2,
          BalanceMgrOp.fee || BalanceMgrOp.feeCash => LucideIcons.percent,
          _ => LucideIcons.users,
        };
        title = m.username;
        tags = [(text: m.op.label, tone: tone), if (m.op.debtLike && m.afterClose) (text: 'بعد الإغلاق', tone: AppTone.brand)];
        amount = m.op.debtLike
            ? balanceIqd(m.amount)
            : (m.op == BalanceMgrOp.withdraw ? balanceSigned(m.amount, sign: '−') : balanceSigned(m.amount, sign: '+'));
        amountColor = m.op.debtLike
            ? AppColors.textHi
            : (m.op == BalanceMgrOp.withdraw ? AppTone.danger.onSoft : AppTone.success.onSoft);
        details = ['مدير فرعيّ', balanceMgrFeeDetail(m), if (m.by != null) 'نفّذها ${m.by}'];
        note = m.note;
        if (m.op.debtLike) {
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
        details = const [];
        note = m.note;
    }
    final info = details.whereType<String>().where((x) => x.trim().isNotEmpty).join(' · ');
    final subName = (m is BalanceActMove || m is BalancePayMove) && (name?.trim().isNotEmpty ?? false) ? name!.trim() : null;
    // «7:34 مساءً» بتوقيت بغداد تحت المبلغ (اليوم في رأس مجموعته) — كسطور التقارير الموحّدة
    final time = clock12Ar(balanceBaghdad(m.atMs));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Sp.sm + 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RpIconBox(icon: icon, tone: balanceRpTone(tone), size: 36),
          const SizedBox(width: Sp.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // المبلغ ووقته على سطر الاسم ولو التفّ الاسم؛ ولا يأخذان أكثر من نصف السطر (رقمٌ بعشر خاناتٍ يصغر ولا يفيض)
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
                            // «العربي ومن ثم اليوزر» (المالك ٢٣ نوفمبر): الاسم العربيّ عنواناً كاملاً لا يُقصّ، واليوزر بعده — يلتفّ تحته
                            // كاملاً إن ضاق السطر (LTR وحده: يوزرٌ يبدأ برقمٍ لا ينقلب)؛ بلا اسمٍ اليوزر عنوانٌ كما كان
                            if (subName != null)
                              Text(subName, key: const ValueKey('bal-move-name'), style: AppType.bodyBold(color: AppColors.textHi))
                            else
                              Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.bodyBold(color: AppColors.textHi)),
                            if (subName != null)
                              Text(title,
                                  key: const ValueKey('bal-move-user'),
                                  textDirection: TextDirection.ltr,
                                  style: AppType.body(color: AppColors.textMid).copyWith(fontWeight: FontWeight.w600)),
                            for (final t in tags) ToneChip(label: t.text, tone: t.tone, dense: true),
                          ],
                        ),
                      ),
                      const SizedBox(width: Sp.sm),
                      ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: box.maxWidth * 0.5),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: AlignmentDirectional.centerEnd,
                              child: Text(
                                amount,
                                maxLines: 1,
                                style: AppType.bodyStrong(color: amountColor).copyWith(fontWeight: FontWeight.w700, fontFeatures: const [FontFeature.tabularFigures()]),
                              ),
                            ),
                            Text(time, key: const ValueKey('bal-move-time'), maxLines: 1, style: AppType.micro(color: AppColors.textLow)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (info.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(info, maxLines: 3, overflow: TextOverflow.ellipsis, style: AppType.micro(color: AppColors.textMid)),
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
