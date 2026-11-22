import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../api/company_route.dart';
import '../../../api/manager_movements_api.dart';
import '../../../api/merged_dashboard_api.dart';
import '../../../core/util/ar_date.dart';
import '../../../models/merged_company.dart';
import '../../../services/merged_manager_debts.dart';
import '../../../services/merged_mode.dart';
import '../../../services/merged_text.dart';
import '../../../services/permissions_service.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';
import '../../desktop/desk_widgets.dart';
import '../widgets/report_export.dart';
import '../widgets/report_permission_gate.dart';
import 'debt_age.dart';
import 'manager_debts_view.dart';
import 'report_kit.dart';
import 'report_period.dart';
import 'report_prefs.dart';
import 'report_sheets.dart';

/// «ديون المدراء» على الشكل الموحّد (٢٢ نوفمبر — «اكمل كلشي»): الفترة («كل الفترات» أوّل مرّة كما كان) ← الشركات ← الفلاتر (النوع)
/// ← «حسب الشركة» ← «إيرادات مستحصَلة» ← المتبقّي (SAS، أخرى، الإجمالي) والمدينون ← «قسّم حسب» المدير/النوع/اليوم ← الحركات يوماً
/// يوماً وبحث المدير (يحصر المجاميع كما كان) ← التصدير بالفلاتر حرفاً. القراءة بالمحمّل الكامل (loadCompanyManagerDebts: 300 مدير ×
/// 500 حركة)، وما لم يُقرأ كاملاً يُسمّى، والمتعذّرة لا تُجمع صفراً. المنطق في [ManagerDebtsView] منقولٌ حرفاً من الشاشة السابقة.
class ManagerDebtsV2Screen extends StatefulWidget {
  const ManagerDebtsV2Screen({super.key});

  @visibleForTesting
  static DateTime Function() clock = DateTime.now;

  @override
  State<ManagerDebtsV2Screen> createState() => _ManagerDebtsV2State();
}

class _Co {
  _Co(this.c, {this.data, this.reason, this.loading = false});
  final MergedCompany? c; // null = المفتوحة
  CompanyManagerDebts? data;
  String? reason;
  bool loading;

  bool get included => !loading && data != null && !data!.noSubAdmins && reason == null;
}

class _ManagerDebtsV2State extends State<ManagerDebtsV2Screen> {
  static const _id = 'manager_debts';
  static const _perm = 'reports.manager_debts';
  static const _page = 40;
  static const _noSubAdmins = 'بلا مدراء فرعيّين';
  static const _open = '·open';

  RpFilterValue? _f;
  bool _requested = false;
  int _seq = 0;
  final _cos = <String, _Co>{};
  String _q = '';
  int _tab = 0;
  bool _tabAll = false;
  int _visible = _page;

  bool get _merged => MergedMode.active.value;
  DateTime get _now => ManagerDebtsV2Screen.clock();
  bool get _all => _f!.range.preset == RpPreset.all;

  /// الأقسام الفرعيّة المطويّة (المالك ٢٢ نوفمبر: «المهمّات تظهر والفرعيّة هو ينقر عليها ويظهرها»).
  late final _folds = RpFolds(_id, const {});
  RpFold _fold(String s) => _folds.fold(s, setState);

  @override
  void initState() {
    super.initState();
    unawaited(_folds.load().then((_) {
      if (mounted) setState(() {});
    }));
    PermissionsService.changes.addListener(_onPerms);
    MergedMode.active.addListener(_onMerged);
    unawaited(_start());
  }

  @override
  void dispose() {
    PermissionsService.changes.removeListener(_onPerms);
    MergedMode.active.removeListener(_onMerged);
    super.dispose();
  }

  Future<void> _start() async {
    final f = await RpPrefs.load(_id, now: _now, fallback: RpPreset.all);
    if (!mounted) return;
    setState(() => _f = f.copyWith(compare: false, managers: const {}, employees: const {}));
    if (Perms.has(_perm)) {
      _requested = true;
      _load();
    }
  }

  void _onPerms() {
    if (!mounted || _requested || _f == null || !Perms.has(_perm)) return;
    _requested = true;
    _load();
  }

  void _onMerged() {
    if (!mounted || _f == null) return;
    setState(() {
      _cos.clear();
      _tab = 0;
    });
    if (_requested) _load();
  }

  void _apply(RpFilterValue v) {
    final f = v.copyWith(compare: false, managers: const {}, employees: const {});
    setState(() {
      _f = f;
      _visible = _page;
    });
    unawaited(RpPrefs.save(_id, f));
    _load();
  }

  String? _day(DateTime d) => _all ? null : '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  List<MergedCompany> get _countable => MergedDashboardApi.countable();

  List<MergedCompany> get _picked {
    final all = _countable;
    final sel = _f!.companies;
    final picked = sel.isEmpty ? all : all.where((c) => sel.contains(c.key)).toList();
    return picked.isEmpty ? all : picked;
  }

  Future<void> _load() async {
    final seq = ++_seq;
    final f = _f!;
    final from = _day(f.range.from), to = _day(f.range.to);
    if (!_merged) {
      setState(() {
        _cos
          ..clear()
          ..[_open] = _Co(null, loading: true);
      });
      // للمفتوحة صراحةً (لا لقسم «المدراء» ظاهرٍ لشركةٍ أخرى ببادئاته)
      final r = await CompanyRoute.runOpen(() => loadCompanyManagerDebts(from: from, to: to));
      if (!mounted || seq != _seq || _merged) return;
      setState(() => _cos[_open] = _Co(null, data: r.data, reason: r.data == null ? (r.error ?? 'تعذّر جلب ديون المدراء الآن') : null));
      return;
    }
    final cs = _picked;
    setState(() {
      _cos.clear();
      for (final c in cs) {
        _cos[c.key] = _Co(c, loading: true);
      }
      _visible = _page;
    });
    await Future.wait([
      for (final c in cs)
        (() async {
          if (c.provider != MergedProvider.sas4) {
            setState(() => _cos[c.key] = _Co(c, reason: _noSubAdmins));
            return;
          }
          if (MergedMode.pagePermAny(c.key, const [_perm]) == false) {
            setState(() => _cos[c.key] = _Co(c, reason: MergedMode.noAccess('ديون مدرائها')));
            return;
          }
          final r = await CompanyRoute.run(c.key, () => loadCompanyManagerDebts(from: from, to: to));
          if (!mounted || seq != _seq) return;
          setState(() => _cos[c.key] = _Co(c, data: r.data, reason: r.data == null ? (r.error ?? 'تعذّر جلب ديون مدرائها الآن') : null));
        })(),
    ]);
  }

  void _retry(String key) {
    final co = _cos[key];
    if (co == null || co.c == null) return;
    setState(() => _cos[key] = _Co(co.c, loading: true));
    final f = _f!;
    final seq = _seq;
    unawaited(() async {
      final r = await CompanyRoute.run(co.c!.key, () => loadCompanyManagerDebts(from: _day(f.range.from), to: _day(f.range.to)));
      if (!mounted || seq != _seq) return; // تغيّرت الفلاتر أثناءها ⇒ قراءتها القديمة لا تدخل
      setState(() => _cos[key] = _Co(co.c, data: r.data, reason: r.data == null ? (r.error ?? 'تعذّر جلب ديون مدرائها الآن') : null));
    }());
  }

  // ═══════════════ ما يُرسم ═══════════════

  List<_Co> get _inc => [for (final co in _cos.values) if (co.included) co];

  /// حركات الشركات المقروءة مرتّبةً — تُبنى مرّةً لكلّ قراءةٍ وفترة (الحساب الكبير: 300 مدير × 500 حركة) لا مع كلّ حرف بحث.
  List<MgrEvent>? _sorted;
  Object? _sortedOf;

  List<MgrEvent> _events() {
    final f = _f!;
    final tag = (f.range.key, [for (final co in _inc) co.data]);
    if (_sorted == null || !_sameTag(_sortedOf, tag)) {
      _sorted = <MgrEvent>[
        for (final co in _inc)
          ...ManagerDebtsView.eventsOf(co.data!.movements, co.data!.debts,
              from: _all ? null : f.range.from, to: _all ? null : f.range.to, companyKey: co.c?.key),
      ]..sort((a, b) => b.date.compareTo(a.date));
      _sortedOf = tag;
    }
    return ManagerDebtsView.filter(_sorted!, f.types, _q);
  }

  static bool _sameTag(Object? a, (String, List<CompanyManagerDebts?>) b) {
    if (a is! (String, List<CompanyManagerDebts?>) || a.$1 != b.$1 || a.$2.length != b.$2.length) return false;
    for (var i = 0; i < b.$2.length; i++) {
      if (!identical(a.$2[i], b.$2[i])) return false;
    }
    return true;
  }

  double get _sas => _inc.fold<double>(0, (a, co) => a + ManagerDebtsView.sasOf(co.data!.managers, _q));
  double get _custom => _inc.fold<double>(0, (a, co) => a + ManagerDebtsView.customOf(co.data!.summary, _q));
  int get _debtors => _inc.fold<int>(0, (a, co) => a + ManagerDebtsView.debtorsOf(co.data!.managers, co.data!.summary, _q));

  /// ما لم يدخل المجموع — باسمه (لا صفرٌ صامت): شركةٌ تعذّرت، دين مديرٍ لم يُقرأ، وما لم يُقرأ كاملاً.
  List<String> get _warnings {
    final out = <String>[];
    final failed = [
      for (final co in _cos.values)
        if (!co.loading && co.reason != null && co.reason != _noSubAdmins && co.c != null) '«${co.c!.name}»',
    ];
    if (failed.isNotEmpty) out.add('merged.not_in_sum'.trm(args: [failed.join('، ')]));
    for (final co in _inc) {
      final n = ManagerDebtsView.unreadOf(co.data!.managers, _q);
      final name = co.c?.name;
      if (n > 0) {
        final text = 'دين $n مدير لم يُقرأ من الساس — خارج «متبقّي SAS»';
        out.add(name == null ? text : '«$name»: $text');
      }
      final d = co.data!;
      final parts = <String>[
        if (d.managersTotal > d.managers.length) 'أوّل ${d.managers.length} مدير من ${d.managersTotal}',
        if (d.managers.length > kManagerMovementsCap) 'حركات أوّل $kManagerMovementsCap مديراً',
        if (d.movementsFailed > 0) 'حركات ${d.movementsFailed} مدير لم تُقرأ',
        if (d.movementsCapped > 0) 'حركات ${d.movementsCapped} مدير بلغت $kManagerMovementsLimit — أقدمها قد تنقص',
      ];
      if (parts.isNotEmpty) out.add('${name == null ? '' : '«$name»: '}لم يُقرأ كاملاً: ${parts.join(' · ')}');
    }
    return out;
  }

  RpCompany _rp(MergedCompany c, {bool selected = true, String? note}) =>
      RpCompany(key: c.key, name: c.name, colorIndex: c.colorIndex, selected: selected, note: note);

  RpCompany? _coOf(MgrEvent e) {
    if (!_merged || e.companyKey == null) return null;
    final c = _cos[e.companyKey!]?.c;
    return c == null ? null : _rp(c);
  }

  // ═══════════════ الأفعال ═══════════════

  Future<void> _openFilters() async {
    final f = _f!;
    final v = await showModalBottomSheet<RpFilterValue>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: AppColors.scrim,
      builder: (ctx) => RpFilterSheet(
        subtitle: 'ديون المدراء · ${f.range.name}',
        initial: f,
        now: _now,
        people: const [],
        showPeople: false,
        showCompare: false,
        presets: const [RpPreset.all, ...RpRange.presets],
        companies: _merged ? [for (final c in _countable) _rp(c, selected: false)] : null,
        types: [for (final e in ManagerDebtsView.kindKeys.entries) (e.key, ManagerDebtsView.kindLabel(e.value))],
      ),
    );
    if (v != null && mounted) _apply(v);
  }

  void _toggleCompany(RpCompany c) {
    final all = [for (final x in _countable) x.key];
    final picked = _f!.companies.isEmpty ? {...all} : {..._f!.companies};
    if (picked.contains(c.key)) {
      if (picked.length == 1) return;
      picked.remove(c.key);
    } else {
      picked.add(c.key);
    }
    _apply(_f!.copyWith(companies: picked.length == all.length ? const {} : picked));
  }

  List<RpChip> _chips() {
    final f = _f!;
    return [
      if (f.types.isNotEmpty)
        RpChip('النوع: ${[for (final t in f.types) ManagerDebtsView.kindLabel(ManagerDebtsView.kindKeys[t] ?? MgrKind.other)].join('، ')}',
            onRemove: () => _apply(f.copyWith(types: const []))),
    ];
  }

  List<String> get _tabs => [if (_merged) 'الشركة', 'المدير', 'النوع', 'اليوم', 'عمر الدين'];

  static const _ageTab = 'عمر الدين';

  /// «عمر الدين» (بند المقترح): المتبقّي من «ديون أخرى» حسب تاريخها — بحث المدير يحصره؛ دين الساس بلا تاريخٍ فلا يدخل.
  List<RpShare> _ages() {
    final q = _q.trim().toLowerCase();
    final open = [
      for (final co in _inc)
        for (final d in co.data!.debts)
          if (d.remainingAmount > 0 && (q.isEmpty || (d.debtorAdminUsername ?? '').toLowerCase().contains(q))) d,
    ];
    return DebtAge.shares(open, at: (d) => d.debtDate, amount: (d) => d.remainingAmount, now: _now);
  }

  List<RpShare> _breakdown(List<MgrEvent> events) {
    final tab = _tabs[_tab.clamp(0, _tabs.length - 1)];
    return switch (tab) {
      'الشركة' => ManagerDebtsView.shares(events, (e) => _coOf(e)?.name ?? '—', companyOf: _coOf),
      'المدير' => ManagerDebtsView.shares(events, (e) => e.managerName, companyOf: _merged ? _coOf : null),
      'النوع' => ManagerDebtsView.shares(events, (e) => e.meta.label),
      _ageTab => _ages(),
      _ => ManagerDebtsView.shares(events, (e) => iqDateOf(e.date.toLocal())),
    };
  }

  // ═══════════════ التصدير ═══════════════

  bool get _busy => _cos.isEmpty || _cos.values.any((c) => c.loading);

  Future<void> _export(String how, {bool Function(MgrEvent)? pick, String? drill}) async {
    if (_busy) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('انتظر حتى تكتمل الأرقام ثمّ صدّر')));
      return;
    }
    var events = _events();
    if (pick != null) events = events.where(pick).toList();
    final rows = [
      for (final e in events)
        [
          if (_merged) MergedMode.companyOf(e.companyKey ?? '')?.name ?? '',
          e.managerName,
          e.manager.username,
          '${e.date.toLocal()}'.substring(0, 16),
          e.meta.label,
          e.amount == 0 ? '' : '${e.amount.abs().round()}',
          e.meta.debit ? '-' : '+',
          e.movement.source == MovementSource.sas4 ? 'الساس' : (e.movement.source != null ? 'يدوي' : ''),
          (e.movement.note ?? '').trim(),
        ],
    ];
    final columns = [
      if (_merged) 'الشركة',
      'المدير',
      'اسم المستخدم',
      'التاريخ',
      'الحركة',
      'المبلغ',
      'الاتجاه',
      'المصدر',
      'الملاحظة',
    ];
    final f = _f!;
    final details = [
      if (_merged) 'الشركات: ${[for (final co in _inc) co.c?.name ?? ''].where((n) => n.isNotEmpty).join('، ')}',
      for (final c in _chips()) c.label,
      if (drill != null) 'الحركات: $drill',
      if (_q.trim().isNotEmpty) 'المدير: «${_q.trim()}»',
      'إيرادات مستحصَلة: ${ManagerDebtsView.money(ManagerDebtsView.incomingOf(events))}',
      'المتبقّي: SAS ${ManagerDebtsView.money(_sas)} · أخرى ${ManagerDebtsView.money(_custom)} · الإجمالي ${ManagerDebtsView.money(_sas + _custom)}',
      'عدد الحركات: ${rows.length}',
      for (final w in _warnings) 'ناقص: $w',
    ];
    final title = 'reports.manager_debts'.tr();
    final subtitle = '${f.range.name} · ${f.range.rangeText}';
    final weights = [if (_merged) 1.2, 1.4, 1.2, 1.2, 1.5, 1.0, 0.6, 0.7, 2.0];
    switch (how) {
      case 'pdf':
        return ReportExportActions.pdf(context,
            title: title, subtitle: subtitle, details: details, columns: columns, rows: rows, columnWeights: weights, fileNameBase: 'manager_debts');
      case 'excel':
        return ReportExportActions.csv(context,
            title: title, subtitle: subtitle, details: details, columns: columns, rows: rows, fileNameBase: 'manager_debts');
      default:
        return ReportExportActions.sharePdf(context,
            title: title, subtitle: subtitle, details: details, columns: columns, rows: rows, columnWeights: weights, fileNameBase: 'manager_debts');
    }
  }

  void _drillIncoming(RpKpi k, List<MgrEvent> events) {
    final rows = events.where((e) => e.incoming).toList();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: AppColors.scrim,
      builder: (ctx) => RpDrillSheet(
        kpi: k,
        scope: _f!.range.name,
        chips: _chips(),
        rows: RpRowsCard(
          total: rows.length,
          days: ManagerDebtsView.days(rows, companyOf: _merged ? _coOf : null, limit: 80),
          more: rows.length > 80 ? 'الأولى 80 — كلّها بالتصدير' : null,
        ),
        onExport: () => _export('share', pick: (e) => e.incoming, drill: k.label),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return ReportPermissionGate(
      permission: _perm,
      title: 'reports.manager_debts'.tr(),
      child: Scaffold(
        backgroundColor: AppColors.bg,
        appBar: deskPageBar(
          context,
          mobile: AppBar(
            backgroundColor: AppColors.surface,
            elevation: 0,
            scrolledUnderElevation: 0,
            title: Text(_merged ? 'ديون المدراء · كل الشركات' : 'reports.manager_debts'.tr(),
                style: AppType.title(color: AppColors.textHi).copyWith(fontSize: 16)),
            iconTheme: IconThemeData(color: AppColors.textHi),
          ),
        ),
        body: SafeArea(
          child: RefreshIndicator(
            onRefresh: _load,
            color: AppColors.brand,
            child: _f == null
                ? const Center(child: CircularProgressIndicator())
                : ListView(padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, Sp.huge), children: _parts()),
          ),
        ),
      ),
    );
  }

  List<Widget> _parts() {
    final f = _f!;
    final parts = <Widget>[
      RpPeriodBar(period: RpPeriod(name: f.range.name, range: f.range.rangeText), compareOn: false, compareWith: '', onPeriod: _openFilters),
    ];
    if (_merged) {
      final picked = {for (final c in _picked) c.key};
      parts.add(RpCompanyChips(
        companies: [for (final c in _countable) _rp(c, selected: f.companies.isNotEmpty && picked.contains(c.key))],
        allSelected: f.companies.isEmpty,
        onAll: () => _apply(f.copyWith(companies: const {})),
        onToggle: _toggleCompany,
      ));
    }
    parts.add(RpFilterBar(chips: _chips(), onOpen: _openFilters, onClear: () => _apply(f.cleared())));
    if (_merged) {
      parts.add(_companyTable());
      final none = [
        for (final co in _cos.values)
          if (co.c != null && !co.loading && (co.reason == _noSubAdmins || co.data?.noSubAdmins == true)) '«${co.c!.name}»',
      ];
      if (none.isNotEmpty) {
        parts.add(Text('بلا مدراء فرعيّين: ${none.join('، ')}', style: AppType.micro(color: AppColors.textLow)));
      }
    }
    if (_busy && _inc.isEmpty) {
      parts.add(const Padding(padding: EdgeInsets.symmetric(vertical: Sp.huge), child: Center(child: CircularProgressIndicator())));
      return _gapped(parts);
    }
    if (_inc.isEmpty) {
      final single = _cos[_open];
      final reason = single != null
          ? (single.data?.noSubAdmins == true ? _noSubAdmins : (single.reason ?? 'تعذّر جلب ديون المدراء الآن'))
          : (_cos.values.any((c) => c.reason != null && c.reason != _noSubAdmins)
              ? 'تعذّر جلب ديون المدراء الآن'
              : mergedWord('لا مدراء فرعيّين في شركاتك', 'لا مدراء فرعيّين في صفحاتك'));
      parts.add(RpCard(
        child: Column(children: [
          Icon(LucideIcons.userCog, size: 28, color: AppColors.textLow),
          const SizedBox(height: Sp.sm),
          Text(reason, textAlign: TextAlign.center, style: AppType.body(color: AppColors.textMid)),
          if (reason != _noSubAdmins) ...[
            const SizedBox(height: Sp.md),
            OutlinedButton.icon(onPressed: _load, icon: const Icon(LucideIcons.refreshCw, size: 16), label: Text('common.retry'.tr())),
          ],
        ]),
      ));
      return _gapped(parts);
    }
    final events = _events();
    final incoming = ManagerDebtsView.incomingOf(events);
    final hero = RpKpi(id: 'incoming', label: 'إيرادات مستحصَلة', value: incoming, icon: LucideIcons.trendingUp, tone: RpTone.money);
    parts.add(RpHeroKpi(
      kpi: hero,
      compareWith: '',
      spark: const [],
      note: 'شحن نقدي + تسديد ديون (SAS + أخرى) — تتبع كلّ الفلاتر',
      notes: _warnings,
      onTap: () => _drillIncoming(hero, events),
    ));
    final total = _sas + _custom;
    parts.add(RpKpiGrid(compareWith: '', kpis: [
      RpKpi(id: 'sas', label: 'متبقّي SAS', value: _sas, icon: LucideIcons.server, tone: RpTone.debt, upIsGood: false),
      RpKpi(id: 'custom', label: 'متبقّي أخرى', value: _custom, icon: LucideIcons.receipt, tone: RpTone.debt, upIsGood: false),
      RpKpi(id: 'total', label: 'إجمالي المتبقّي', value: total, icon: LucideIcons.wallet, tone: total > 0 ? RpTone.loss : RpTone.money, upIsGood: false),
      RpKpi(id: 'debtors', label: 'المدينون', value: _debtors, unit: 'مدين', isCount: true, icon: LucideIcons.userCog, tone: RpTone.info),
    ]));
    final shares = _breakdown(events);
    final cap = _tabAll ? shares.length : 6;
    final age = _tabs[_tab.clamp(0, _tabs.length - 1)] == _ageTab;
    parts.add(RpBreakdownCard(
      fold: _fold('breakdown'),
      tabs: _tabs,
      selected: _tab.clamp(0, _tabs.length - 1),
      tone: age ? RpTone.debt : RpTone.money,
      unit: age ? 'دين' : 'حركة',
      empty: age ? 'لا ديون أخرى متبقّية' : 'لا حركات بهذه الفترة',
      shares: shares.take(cap).toList(),
      onTab: (i) => setState(() {
        _tab = i;
        _tabAll = false;
      }),
      note: age
          ? 'المتبقّي من «ديون أخرى» حسب تاريخها — دين الساس بلا تاريخٍ فلا يدخل'
          : 'المبلغ: ما استُحصل؛ والنسبة: من عدد الحركات',
      more: shares.length > cap ? 'عرض الكلّ (${shares.length})' : null,
      onMore: () => setState(() => _tabAll = true),
    ));
    parts.add(RpRowsCard(
      fold: _fold('rows'),
      query: _q,
      total: events.length,
      days: ManagerDebtsView.days(events, companyOf: _merged ? _coOf : null, limit: _visible),
      more: events.length > _visible ? 'عرض المزيد (${events.length - _visible})' : null,
      onMore: () => setState(() => _visible += _page),
      onSearch: (q) => setState(() {
        _q = q;
        _visible = _page;
      }),
      searchHint: 'ابحث باسم المدير أو يوزره',
      note: _q.trim().isEmpty ? null : 'البحث يحصر المدراء — والمتبقّي والمدينون أعلاه معهم',
      empty: _q.trim().isEmpty ? 'لا حركات بهذه الفترة' : 'لا مدير يطابق «${_q.trim()}»',
    ));
    parts.add(RpExportBar(onPdf: () => _export('pdf'), onExcel: () => _export('excel'), onShare: () => _export('share')));
    return _gapped(parts);
  }

  List<Widget> _gapped(List<Widget> parts) => [
        for (var i = 0; i < parts.length; i++) ...[if (i > 0) const SizedBox(height: Sp.md), parts[i]],
      ];

  Widget _companyTable() {
    final lines = <RpCompanyLine>[];
    final outside = <String>[];
    for (final co in _cos.values) {
      final c = co.c;
      if (c == null) continue;
      if (co.loading) {
        lines.add(RpCompanyLine(company: _rp(c), state: RpCompanyState.loading));
        outside.add('${c.name} (تُقرأ)');
      } else if (co.reason == _noSubAdmins || co.data?.noSubAdmins == true) {
        continue; // بلا مدراء فرعيّين — لا سطر ولا «تعذّرت»
      } else if (!co.included) {
        lines.add(RpCompanyLine(company: _rp(c, note: co.reason), state: RpCompanyState.failed));
        outside.add('${c.name} (${co.reason ?? 'تعذّرت'})');
      } else {
        final sas = ManagerDebtsView.sasOf(co.data!.managers, _q);
        final custom = ManagerDebtsView.customOf(co.data!.summary, _q);
        lines.add(RpCompanyLine(company: _rp(c), a: sas, b: custom, c: sas + custom));
      }
    }
    final inc = [for (final l in lines) if (l.state == RpCompanyState.ok) l];
    return RpCompanyTable(
      fold: _fold('companies'),
      heads: const ['متبقّي SAS', 'متبقّي أخرى', 'الإجمالي'],
      lines: lines,
      total: [
        inc.fold<num>(0, (a, l) => a + (l.a ?? 0)),
        inc.fold<num>(0, (a, l) => a + (l.b ?? 0)),
        inc.fold<num>(0, (a, l) => a + (l.c ?? 0)),
      ],
      outside: outside.isEmpty ? null : 'خارج المجموع الآن: ${outside.join(' · ')}',
      onTap: (c) => _apply(_f!.copyWith(companies: {c.key})),
      onRetry: (c) => _retry(c.key),
    );
  }
}
