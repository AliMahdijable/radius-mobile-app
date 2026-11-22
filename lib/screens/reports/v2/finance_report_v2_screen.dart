import 'dart:async';
import 'dart:collection';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../api/merged_dashboard_api.dart';
import '../../../api/merged_finance_api.dart';
import '../../../api/report_people_api.dart';
import '../../../api/reports_api.dart';
import '../../../core/util/ar_date.dart';
import '../../../core/util/server_time.dart';
import '../../../models/merged_company.dart';
import '../../../services/merged_mode.dart';
import '../../../services/permissions_service.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';
import '../../desktop/desk_widgets.dart';
import '../../settlements/widgets/archive_bar.dart';
import '../widgets/action_labels.dart';
import '../widgets/finance_logs.dart';
import '../widgets/report_export.dart';
import '../widgets/report_filters.dart';
import '../widgets/report_permission_gate.dart';
import '../widgets/scope_helper.dart';
import 'finance_export.dart';
import 'finance_view.dart';
import 'report_kit.dart';
import 'report_period.dart';
import 'report_prefs.dart';
import 'report_sheets.dart';

/// التقرير الماليّ على الشكل الموحّد (٢٢ نوفمبر — المالك: «اي التطبيق أوّلاً … وانطلق» بعد صور المقترح).
///
/// الترتيب: الفترة والمقارنة ← الشركات (بكل الشركات، أكثر من واحدة) ← الفلاتر الفعّالة ← «حسب الشركة» (كلّ شركةٍ حين تصل، والمتعذّرة
/// تُسمّى وتُستثنى مع «أعد») ← البطاقة الكبرى ← البطاقات بفرقها ← الأعداد ← يوماً بيوم ← «قسّم حسب» ← الحركات (يوماً يوماً، وبحث) ←
/// التصدير. الأرقام من الخادم نفسه وبقواعد الشاشة السابقة حرفاً ([FinanceView]، [FinanceLogs])؛ فلتر النوع يُحسب من السطور كما كان.
class FinanceReportV2Screen extends StatefulWidget {
  const FinanceReportV2Screen({super.key});

  /// ساعة التقرير (للاختبار).
  @visibleForTesting
  static DateTime Function() clock = DateTime.now;

  @override
  State<FinanceReportV2Screen> createState() => _FinanceReportV2State();
}

/// تقرير شركةٍ واحدة في «كل الشركات» كما وصل (أو ينتظر، أو تعذّر).
class _Co {
  _Co(this.c, {this.cur, this.reason, this.loading = false});
  final MergedCompany c;
  FinanceReport? cur;
  FinanceReport? prev;
  bool prevDone = false;
  String? reason;
  bool loading;

  bool get included => !loading && cur != null && reason == null;
}

/// ما يُرسم: أرقامٌ (بفلتر النوع إن وُجد) والسطور والتقسيمات — للشركة المنفردة أو لمجموع الشركات.
class _View {
  const _View({
    required this.kpis,
    required this.prev,
    required this.logs,
    required this.allLogs,
    required this.series,
    required this.admins,
    required this.types,
    required this.truncated,
    required this.costNeedsAllTypes,
    required this.mixedRules,
    required this.showCost,
  });
  final FinanceKPIs kpis;
  final FinanceKPIs? prev;

  /// السطور بعد فلتر النوع.
  final List<FinanceLog> logs;
  final List<FinanceLog> allLogs;
  final List<FinanceDayRow> series;
  final List<(FinanceAdminRow, MergedCompany?)> admins;
  final List<FinanceTypeRow> types;
  final bool truncated;
  final bool costNeedsAllTypes;
  final bool mixedRules;
  final bool showCost;
}

class _FinanceReportV2State extends State<FinanceReportV2Screen> {
  static const _id = 'finance';
  static const _perm = 'reports.financial';
  static const _page = 40;
  static const _open = RpPrefs.openGroup;

  RpFilterValue? _f;

  /// بصمة الشركة المفتوحة لحفظ مدرائها ([RpPrefs]).
  String? _openTag;
  bool _withArchive = false;
  bool _requested = false;
  int _seq = 0;

  FinanceReport? _cur;
  FinanceReport? _prev;
  bool _loading = true;
  String? _error;
  List<String>? _scopeIds;

  final _cos = <String, _Co>{};

  /// مدراء وموظّفو كلّ شركة («open» للمفتوحة) — null في أيٍّ منهما = تعذّر.
  final _people = <String, ({List<RpPerson>? managers, List<RpPerson>? employees})>{};

  int _tab = 0;
  bool _tabAll = false;
  String _q = '';
  int _visible = _page;

  bool get _merged => MergedMode.active.value;
  DateTime get _now => FinanceReportV2Screen.clock();

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
    _openTag = await MergedMode.openAdminId();
    final f = await RpPrefs.load(_id, now: _now, openTag: _openTag);
    if (!mounted) return;
    setState(() => _f = f);
    _loadIfAllowed();
  }

  void _onPerms() {
    if (mounted && !_requested) _loadIfAllowed();
  }

  void _onMerged() {
    if (!mounted || _f == null) return;
    setState(() {
      _cur = null;
      _prev = null;
      _cos.clear();
      _tab = 0;
    });
    if (_requested) _load();
  }

  void _loadIfAllowed() {
    if (_f == null || !Perms.has(_perm)) return;
    _requested = true;
    _load();
  }

  Future<void> _load() => _merged ? _loadMerged() : _loadSingle();

  void _apply(RpFilterValue v) {
    setState(() {
      _f = v;
      _visible = _page;
    });
    unawaited(RpPrefs.save(_id, v, openTag: _openTag));
    _load();
  }

  // ═══════════════ الفلاتر ⇒ الطلب ═══════════════

  /// مدراءٌ اختارهم (مع فرعيّيهم حين يُطلب وتُعرف الشجرة) — null بلا اختيار.
  List<String>? _actorIds(String group) {
    final f = _f!;
    if (f.managerMode != RpManagerMode.actor) return null;
    final picked = f.managers[group];
    if (picked == null || picked.isEmpty) return null;
    final ids = {...picked};
    if (f.withSubs) {
      final kids = <String, List<String>>{};
      for (final m in _people[group]?.managers ?? const <RpPerson>[]) {
        if (m.parentId != null) (kids[m.parentId!] ??= []).add(m.id);
      }
      final stack = [...picked];
      while (stack.isNotEmpty) {
        for (final k in kids[stack.removeLast()] ?? const <String>[]) {
          if (ids.add(k)) stack.add(k);
        }
      }
    }
    return ids.toList();
  }

  /// «مدير المشترك»: يوزر المختار (الخادم يسأل بواحد) — null بلا اختيار أو قبل وصول القائمة.
  String? _ownerUsername(String group) {
    final f = _f!;
    if (f.managerMode != RpManagerMode.owner) return null;
    final id = f.managers[group]?.firstOrNull;
    if (id == null) return null;
    for (final m in _people[group]?.managers ?? const <RpPerson>[]) {
      if (m.id == id) return m.username;
    }
    return null;
  }

  int? _employeeId(String group) => int.tryParse(_f!.employees[group] ?? '');

  Future<void> _loadPeople(List<String?> keys) async {
    final want = [
      for (final k in keys)
        if (!_people.containsKey(k ?? _open)) k,
    ];
    if (want.isEmpty) return;
    final res = await Future.wait([for (final k in want) ReportPeopleApi.of(k)]);
    if (!mounted) return;
    setState(() {
      for (var i = 0; i < want.length; i++) {
        _people[want[i] ?? _open] = res[i];
      }
    });
  }

  // ═══════════════ الجلب ═══════════════

  Future<void> _loadSingle() async {
    final seq = ++_seq;
    final f = _f!;
    setState(() {
      _loading = true;
      _error = null;
      _prev = null;
    });
    _scopeIds ??= await loadScopeUserIds();
    if (f.managers.isNotEmpty) await _loadPeople([null]);
    if (!mounted || seq != _seq || _merged) return;
    Future<({bool ok, FinanceReport? data, String? error})> fetch(RpRange r, int limit) => _fetchSingle(r.from, r.to, limit);
    final cur = await fetch(f.range, 2000);
    if (!mounted || seq != _seq || _merged) return;
    setState(() {
      _loading = false;
      _cur = cur.data;
      _error = cur.ok ? null : (cur.error ?? 'common.load_failed'.tr());
      _visible = _page;
    });
    // فلتر النوع يُحسب من السطور ولا مقارنة له ([_view]) ⇒ لا طلب للسابقة
    if (!f.compare || f.types.isNotEmpty || !cur.ok) return;
    final prev = await fetch(f.range.previous, 1);
    if (!mounted || seq != _seq || _merged) return;
    setState(() => _prev = prev.ok ? prev.data : null);
  }

  /// طلب الشركة المفتوحة بفلاترها الحاليّة — للفترة، ولمقارنتها، ولأجزاء التصدير الكامل ([_exportAll]).
  Future<({bool ok, FinanceReport? data, String? error})> _fetchSingle(DateTime from, DateTime to, int limit) => ReportsApi.finance(
        from: from,
        to: to,
        userIds: _actorIds(_open) ?? _scopeIds,
        userManager: _ownerUsername(_open),
        employeeId: _employeeId(_open),
        recentLimit: limit,
        includeArchived: _withArchive,
        // كلفة الباقات (قرار ٢٠٢٦-١٠-١٨): لمالك الحساب وحده، ولساسٍ بعيد أو ايرث لنك — كالشاشة السابقة.
        withPackageCost: !Perms.isEmployee && isCostBearingAdminId((_scopeIds?.isNotEmpty ?? false) ? _scopeIds!.first : null),
      );

  /// فلاتر شركةٍ في «كل الشركات» — طلبها وطلب مقارنتها وأجزاء تصديرها.
  FinanceCompanyFilter _companyFilter(String key) =>
      FinanceCompanyFilter(userIds: _actorIds(key), userManager: _ownerUsername(key), employeeId: _employeeId(key));

  List<MergedCompany> get _countable => MergedDashboardApi.countable();

  List<MergedCompany> get _picked {
    final all = _countable;
    final sel = _f!.companies;
    final picked = sel.isEmpty ? all : all.where((c) => sel.contains(c.key)).toList();
    return picked.isEmpty ? all : picked;
  }

  Future<void> _loadMerged() async {
    final seq = ++_seq;
    final f = _f!;
    final cs = _picked;
    setState(() {
      _cos.clear();
      for (final c in cs) {
        _cos[c.key] = _Co(c, loading: true);
      }
      _visible = _page;
    });
    if (f.managers.isNotEmpty) await _loadPeople([for (final c in cs) c.key]);
    if (!mounted || seq != _seq) return;
    await Future.wait([for (final c in cs) _loadCo(c, seq)]);
  }

  Future<void> _loadCo(MergedCompany c, int seq) async {
    final f = _f!;
    // «كل الصفحات»: صفحةٌ لا يملك فيها الموظّف التقرير ⇒ لا يُطلب، وتُسمّى خارج المجموع
    if (MergedMode.pagePerm(c.key, _perm) == false) {
      setState(() => _cos[c.key] = _Co(c, reason: MergedMode.noAccess('تقريرها')));
      return;
    }
    final filter = _companyFilter(c.key);
    final r = await MergedFinanceApi.one(c, from: f.range.from, to: f.range.to, includeArchived: _withArchive, filter: filter);
    if (!mounted || seq != _seq) return;
    final reason = (!r.ok || r.data == null) ? (r.error ?? 'تعذّر جلب تقريرها') : MergedFinanceApi.gapReason(c, r.data!);
    setState(() => _cos[c.key] = _Co(c, cur: r.data, reason: reason));
    if (!f.compare || f.types.isNotEmpty || reason != null) return;
    final p = await MergedFinanceApi.one(c,
        from: f.range.previous.from, to: f.range.previous.to, includeArchived: _withArchive, filter: filter, recentLimit: 1);
    if (!mounted || seq != _seq) return;
    setState(() {
      final co = _cos[c.key];
      if (co == null) return;
      co.prev = p.ok ? p.data : null;
      co.prevDone = true;
    });
  }

  void _retry(String key) {
    final co = _cos[key];
    if (co == null) return;
    setState(() => _cos[key] = _Co(co.c, loading: true));
    unawaited(_loadCo(co.c, _seq));
  }

  // ═══════════════ ما يُرسم ═══════════════

  MergedFinanceResult get _combined => MergedFinanceApi.combine([
        for (final co in _cos.values)
          if (!co.loading) MergedFinancePart(company: co.c, report: co.cur, reason: co.reason),
      ]);

  _View? _view() {
    final types = _f!.types;
    final hasType = types.isNotEmpty;
    if (!_merged) {
      final r = _cur;
      if (r == null) return null;
      final filtered = FinanceLogs.filter(r.recentLogs, types);
      final cost = hasType
          ? PackageCostKpis.forFilteredLogs(period: r.kpis.packageCost, allLogs: r.recentLogs, filtered: filtered)
          : null;
      return _View(
        kpis: hasType ? FinanceLogs.kpisFromLogs(filtered, packageCost: cost?.cost) : r.kpis,
        prev: hasType ? null : _prev?.kpis,
        logs: filtered,
        allLogs: r.recentLogs,
        series: r.series,
        admins: [for (final a in r.perAdmin) (a, null)],
        types: r.byType,
        truncated: FinanceView.truncated(r),
        costNeedsAllTypes: cost?.unavailable ?? false,
        mixedRules: false,
        showCost: r.kpis.packageCost != null,
      );
    }
    final m = _combined;
    final rep = m.report;
    if (rep == null) return null;
    final filtered = FinanceLogs.filter(rep.recentLogs, types);
    FinanceKPIs kpis = rep.kpis;
    var costUnavailable = false;
    if (hasType) {
      // كلّ شركةٍ من سطورها (وكلفتها من سطورها) ثمّ المجموع — لا سطور شركةٍ بكلفة أخرى (كالشاشة السابقة).
      final parts = <FinanceKPIs>[];
      for (final p in m.included) {
        final mine = [
          for (final l in filtered)
            if (m.logCompany[l] == p.company.key) l,
        ];
        final cost = PackageCostKpis.forFilteredLogs(period: p.report!.kpis.packageCost, allLogs: p.report!.recentLogs, filtered: mine);
        costUnavailable = costUnavailable || cost.unavailable;
        parts.add(FinanceLogs.kpisFromLogs(mine, packageCost: cost.cost));
      }
      kpis = MergedFinanceApi.sumKpis(parts);
    }
    final inc = [
      for (final co in _cos.values)
        if (co.included) co,
    ];
    final prevReady = !hasType && inc.isNotEmpty && inc.every((co) => co.prevDone && co.prev != null);
    // «الدين» يوماً بيوم: من كلّ شركةٍ داخلة أو لا يُرسم — شركةٌ لا يرسله خادمها (ايرث لنك، فايبر اكس) كان يجعل الخطّ مجموع غيرها
    // وحدها كأنّه الكلّ.
    final debtFromAll = inc.every((co) => co.cur!.series.isEmpty || co.cur!.series.any((d) => d.debt != null));
    final series = <String, FinanceDayRow>{};
    for (final co in inc) {
      for (final d in co.cur!.series) {
        final k = iqDateOf(d.day);
        final o = series[k];
        series[k] = FinanceDayRow(
          day: d.day,
          revenue: (o?.revenue ?? 0) + d.revenue,
          count: (o?.count ?? 0) + d.count,
          debt: !debtFromAll ? null : (o?.debt ?? 0) + (d.debt ?? 0),
        );
      }
    }
    final byType = <String, FinanceTypeRow>{};
    for (final co in inc) {
      for (final t in co.cur!.byType) {
        final o = byType[t.type];
        byType[t.type] = FinanceTypeRow(type: t.type, count: (o?.count ?? 0) + t.count, amount: (o?.amount ?? 0) + t.amount);
      }
    }
    return _View(
      kpis: kpis,
      prev: prevReady ? MergedFinanceApi.sumKpis([for (final co in inc) co.prev!.kpis]) : null,
      logs: filtered,
      allLogs: rep.recentLogs,
      series: series.values.toList()..sort((a, b) => a.day.compareTo(b.day)),
      admins: [
        for (final co in inc)
          for (final a in co.cur!.perAdmin) (a, co.c),
      ],
      types: byType.values.toList(),
      truncated: inc.any((co) => FinanceView.truncated(co.cur!)),
      costNeedsAllTypes: costUnavailable,
      mixedRules: m.mixedProfitRules,
      showCost: rep.kpis.packageCost != null,
    );
  }

  RpCompany _rp(MergedCompany c, {bool selected = true, String? note}) =>
      RpCompany(key: c.key, name: c.name, colorIndex: c.colorIndex, selected: selected, note: note);

  RpCompany? _coOf(FinanceLog l, MergedFinanceResult m) {
    final key = m.logCompany[l];
    final co = key == null ? null : _cos[key];
    return co == null ? null : _rp(co.c);
  }

  // ═══════════════ الأفعال ═══════════════

  Future<void> _openFilters() async {
    final f = _f!;
    final merged = _merged;
    final keys = merged ? [for (final c in _countable) c.key] : [null];
    final sheetFuture = showModalBottomSheet<RpFilterValue>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: AppColors.scrim,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSheet) {
        // القوائم تصل والورقة مفتوحة ⇒ تُرسم حين تصل
        _sheetRefresh = () => setSheet(() {});
        return RpFilterSheet(
          subtitle: 'التقرير الماليّ · ${f.range.name}',
          initial: f,
          now: _now,
          loadingPeople: keys.any((k) => !_people.containsKey(k ?? _open)),
          companies: merged ? [for (final c in _countable) _rp(c, selected: false)] : null,
          people: [
            for (final k in keys)
              RpPeopleGroup(
                key: k ?? _open,
                company: k == null ? null : _rp(MergedMode.companyOf(k)!, selected: false),
                managers: _people[k ?? _open]?.managers ?? const [],
                employees: _people[k ?? _open]?.employees ?? const [],
                error: _people.containsKey(k ?? _open) && _people[k ?? _open]!.managers == null && _people[k ?? _open]!.employees == null
                    ? 'تعذّر جلب مدرائها وموظّفيها'
                    : null,
              ),
          ],
          types: [for (final t in kFinancialActionTypes) (t.key, t.displayLabel)],
          payments: const [
            RpPayShortcut('نقد', ['SUBSCRIBER_ACTIVATE_CASH', 'BALANCE_DEDUCT']),
            RpPayShortcut('بالدين', ['SUBSCRIBER_ACTIVATE_NON_CASH', 'BALANCE_ADD']),
          ],
        );
      }),
    );
    unawaited(_loadPeople(keys).then((_) => _sheetRefresh?.call()));
    final v = await sheetFuture;
    _sheetRefresh = null;
    if (v != null && mounted) _apply(v);
  }

  VoidCallback? _sheetRefresh;

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

  List<String> get _columns => [
        if (_merged) 'merged.col_company'.tr(),
        'reports.col_subscriber'.tr(),
        'reports.col_username'.tr(),
        'reports.col_amount'.tr(),
        if (_view()?.showCost ?? false) 'reports.col_package_cost'.tr(),
        'reports.col_date'.tr(),
        'reports.col_description'.tr(),
        'reports.col_type'.tr(),
        'reports.col_executor'.tr(),
      ];

  /// أوزان أعمدة الـPDF (مطلب 2026-07-12 كالشاشة السابقة): الاسم والوصف أعرض، النوع والمنفّذ أضيق.
  List<double> _weights(bool showCost) => [
        if (_merged) 1.4,
        ...(showCost ? const [2.2, 1.4, 1.2, 1.2, 1.4, 2.6, 1.1, 1.3] : const [2.2, 1.4, 1.2, 1.4, 2.6, 1.1, 1.3]),
      ];

  List<List<String>> _exportRows(List<FinanceLog> logs, bool showCost, String? Function(FinanceLog) companyOf) => [
        for (final l in logs)
          [
            if (_merged) MergedMode.companyOf(companyOf(l))?.name ?? '',
            l.userFullName ?? l.targetName ?? l.userUsername ?? '',
            l.userUsername ?? '',
            l.amount == 0 ? '' : l.amount.toString(),
            if (showCost) l.packageCost == null ? '' : FinanceLogs.plainNumber(l.packageCost!),
            exportTimeAr(l.createdAt),
            (l.actionDescription ?? '').replaceAll('\n', ' '),
            arabicActionLabel(l.actionType, l.actionDescription ?? ''),
            l.actingEmployeeFullName ?? l.adminUsername ?? '',
          ],
      ];

  String get _exportSubtitle {
    final r = _f!.range;
    return '${r.name} · ${r.rangeText}';
  }

  /// رأس الملفّ: كلّ فلترٍ مختار سطراً (الشركات، المدير، الموظّف، النوع، البحث، الحركة الملموسة)، وعدد الحركات، وما لم يكتمل.
  List<String> _exportDetails({required int count, String? drill, bool withSearch = true, List<String> gaps = const []}) {
    final m = _merged ? _combined : null;
    final q = _q.trim();
    return [
      if (m != null) 'الشركات: ${m.included.map((p) => p.company.name).join('، ')}',
      if (m != null && m.parts.any((p) => !p.included))
        'خارج الملفّ: ${[for (final p in m.parts) if (!p.included) '${p.company.name} (${p.reason ?? 'تعذّرت'})'].join('، ')}',
      for (final c in _chips()) c.label,
      if (drill != null) 'الحركات: $drill',
      if (withSearch && q.isNotEmpty) 'بحث: «$q»',
      'عدد الحركات: $count',
      if (gaps.isNotEmpty) 'ناقص: ${gaps.join('؛ ')}',
    ];
  }

  bool get _busy => _merged ? _cos.values.any((c) => c.loading) || _cos.isEmpty : _loading;

  /// التصدير بالفلاتر المختارة حرفاً (المالك ٢٢ نوفمبر: «من يختار فلاتر … ويطبع أو ينقر إكسل أو PDF يطلع على حسب الفلاتر … وملف
  /// الPDF جاي يظهر مرات مقصوص مو كامل»): كلّ حركات الفترة — ما قصّه سقف الخادم (1000 لكلّ طلب) يُجلب مقسوماً
  /// ([FinanceExportLoader]) — ثمّ النوع، ثمّ حركات البطاقة الملموسة ([pick])، ثمّ البحث كما على الشاشة؛ ورأس الملفّ يسمّي الفلاتر.
  Future<void> _exportAll(String how, {String title = '', bool Function(FinanceLog)? pick, String? drill, bool withSearch = true}) async {
    final v = _view();
    if (v == null) return;
    if (_busy) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('انتظر حتى تكتمل الأرقام ثمّ صدّر')));
      return;
    }
    final f = _f!;
    final m = _merged ? _combined : null;
    var all = v.allLogs;
    String? Function(FinanceLog) companyOf = (l) => m?.logCompany[l];
    final gaps = <String>[];
    if (v.truncated) {
      final full = await _loadFullLogs(f, m);
      if (full == null || !mounted) return;
      all = full.logs;
      companyOf = (l) => full.companyOf[l];
      gaps.addAll(full.gaps);
    }
    var logs = FinanceLogs.filter(all, f.types);
    if (pick != null) logs = logs.where(pick).toList();
    if (withSearch) logs = FinanceView.search(logs, _q);
    final t = title.isEmpty ? 'reports.financial'.tr() : title;
    final rows = _exportRows(logs, v.showCost, companyOf);
    final details = _exportDetails(count: rows.length, drill: drill, withSearch: withSearch, gaps: gaps);
    switch (how) {
      case 'pdf':
        return ReportExportActions.pdf(context,
            title: t, subtitle: _exportSubtitle, details: details, columns: _columns, rows: rows, columnWeights: _weights(v.showCost), fileNameBase: 'financial');
      case 'excel':
        return ReportExportActions.csv(context,
            title: t, subtitle: _exportSubtitle, details: details, columns: _columns, rows: rows, fileNameBase: 'financial');
      default:
        return ReportExportActions.sharePdf(context,
            title: t, subtitle: _exportSubtitle, details: details, columns: _columns, rows: rows, columnWeights: _weights(v.showCost), fileNameBase: 'financial');
    }
  }

  /// كلّ حركات الفترة لكلّ شركةٍ داخلة (المقصوصة وحدها تُطلب مقسومة) بنافذة تقدّمٍ تُلغى — null: أُلغي.
  Future<({List<FinanceLog> logs, Map<FinanceLog, String?> companyOf, List<String> gaps})?> _loadFullLogs(
      RpFilterValue f, MergedFinanceResult? m) async {
    final progress = ValueNotifier<int>(0);
    var cancel = false;
    final dialog = showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        content: Row(
          children: [
            const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4)),
            const SizedBox(width: Sp.md),
            Expanded(
              child: ValueListenableBuilder<int>(
                valueListenable: progress,
                builder: (_, n, __) => Text(
                  'الفترة فيها أكثر من ${PackageCostKpis.recentLogsServerCap} حركة — أجلبها كاملةً على أجزاء${n > 0 ? ' ($n)' : ''}…',
                  style: AppType.body(color: AppColors.textHi),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              cancel = true;
              Navigator.of(ctx).pop();
            },
            child: const Text('إلغاء'),
          ),
        ],
      ),
    );
    var closed = false;
    unawaited(dialog.then((_) => closed = true));
    try {
      final logs = <FinanceLog>[];
      final companyOf = LinkedHashMap<FinanceLog, String?>.identity();
      final gaps = <String>[];
      var requests = 0;
      void tick(int _) => progress.value = ++requests;
      if (m == null) {
        final full = await FinanceExportLoader.load(
          from: f.range.from,
          to: f.range.to,
          first: _cur!,
          fetch: (a, b) => _fetchSingle(a, b, 2000),
          onProgress: tick,
          cancelled: () => cancel,
        );
        logs.addAll(full.logs);
        gaps.addAll(full.gaps);
      } else {
        final tagged = <({FinanceLog log, int at, int order})>[];
        var order = 0;
        for (final p in m.included) {
          final c = MergedMode.companyOf(p.company.key) ?? p.company;
          final rep = p.report!;
          final full = FinanceExportLoader.capped(rep) || rep.unavailableParts.contains('recent_logs')
              ? await FinanceExportLoader.load(
                  from: f.range.from,
                  to: f.range.to,
                  first: rep,
                  fetch: (a, b) => MergedFinanceApi.one(c,
                      from: a, to: b, includeArchived: _withArchive, filter: _companyFilter(c.key), recentLimit: 2000),
                  onProgress: tick,
                  cancelled: () => cancel,
                )
              : FinanceFullLogs(logs: rep.recentLogs, gaps: const [], requests: 0);
          for (final l in full.logs) {
            companyOf[l] = c.key;
            tagged.add((log: l, at: FinanceView.timeOf(l)?.millisecondsSinceEpoch ?? 0, order: order++));
          }
          gaps.addAll([for (final g in full.gaps) '${c.name} $g']);
        }
        // الأحدث أوّلاً بين الشركات — والتعادل بترتيب الشركات ثمّ الخادم (كمجموع الشاشة)
        tagged.sort((a, b) => a.at != b.at ? b.at.compareTo(a.at) : a.order.compareTo(b.order));
        logs.addAll([for (final t in tagged) t.log]);
      }
      if (cancel) return null;
      return (logs: logs, companyOf: companyOf, gaps: gaps);
    } finally {
      if (!closed && mounted) Navigator.of(context, rootNavigator: true).pop();
      progress.dispose();
    }
  }

  void _drill(RpKpi k, _View v) {
    final pick = FinanceView.drill(k.id);
    final logs = v.logs.where(pick).toList();
    final m = _merged ? _combined : null;
    final scope = [
      _f!.range.name,
      if (m != null) m.included.map((p) => p.company.name).join('، '),
    ].join(' · ');
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: AppColors.scrim,
      builder: (ctx) => RpDrillSheet(
        kpi: k,
        scope: scope,
        chips: [for (final c in _chips()) RpChip(c.label)],
        rows: RpRowsCard(
          total: logs.length,
          days: FinanceView.days(logs, companyOf: m == null ? null : (l) => _coOf(l, m), showCost: v.showCost, limit: 80),
          more: logs.length > 80 ? 'الأولى 80 — كلّها بالتصدير' : null,
          note: v.truncated ? 'من آخر ${PackageCostKpis.recentLogsServerCap} حركة بالفترة' : null,
        ),
        onExport: () => _exportAll('share', title: k.label, pick: pick, drill: k.label, withSearch: false),
      ),
    );
  }

  // ═══════════════ الرقائق ═══════════════

  String _nameOf(String group, String id, {required bool manager}) {
    final list = manager ? _people[group]?.managers : _people[group]?.employees;
    for (final p in list ?? const <RpPerson>[]) {
      if (p.id == id) return p.name;
    }
    return manager ? 'مدير' : 'موظّف';
  }

  String _groupName(String group) => group == _open ? '' : ' (${MergedMode.companyOf(group)?.name ?? ''})';

  List<RpChip> _chips() {
    final f = _f!;
    final out = <RpChip>[];
    final owner = f.managerMode == RpManagerMode.owner;
    for (final e in f.managers.entries) {
      if (e.value.isEmpty) continue;
      final names = [for (final id in e.value) _nameOf(e.key, id, manager: true)].join('، ');
      // «+ الفرعيّين» حين ضُمّوا فعلاً (الشجرة معروفة ولمن اختاره فرعيّون) — لا قبل أن يرسل الخادم parent_id
      final subs = !owner && f.withSubs && (_actorIds(e.key)?.length ?? 0) > e.value.length ? ' + الفرعيّين' : '';
      out.add(RpChip('${owner ? 'مدير المشترك' : 'المدير'}: $names$subs${_groupName(e.key)}', onRemove: () {
        final m = {...f.managers}..remove(e.key);
        _apply(f.copyWith(managers: m));
      }));
    }
    for (final e in f.employees.entries) {
      out.add(RpChip('الموظّف: ${_nameOf(e.key, e.value, manager: false)}${_groupName(e.key)}', onRemove: () {
        final m = {...f.employees}..remove(e.key);
        _apply(f.copyWith(employees: m));
      }));
    }
    if (f.types.isNotEmpty) {
      final labels = [
        for (final t in kFinancialActionTypes)
          if (f.types.contains(t.key)) t.displayLabel,
      ];
      out.add(RpChip('النوع: ${labels.join('، ')}', onRemove: () => _apply(f.copyWith(types: const []))));
    }
    return out;
  }

  // ═══════════════ «قسّم حسب» ═══════════════

  List<String> get _tabs => [if (_merged) 'الشركة', 'المدير', 'الموظّف', 'النوع', 'اليوم'];

  ({List<RpShare> shares, String? note}) _breakdown(_View v) {
    final tab = _tabs[_tab.clamp(0, _tabs.length - 1)];
    final hasType = _f!.types.isNotEmpty;
    final fromLogsNote = v.truncated ? 'محسوبٌ من آخر ${PackageCostKpis.recentLogsServerCap} حركة بالفترة' : null;
    List<RpShare> shares(List<(String, num, int, RpCompany?, String?)> rows) {
      final total = rows.fold<num>(0, (a, r) => a + (r.$2 > 0 ? r.$2 : 0));
      final sorted = [...rows]..sort((a, b) => b.$2.compareTo(a.$2));
      return [
        for (final r in sorted)
          RpShare(name: r.$1, amount: r.$2, count: r.$3, share: total > 0 && r.$2 > 0 ? r.$2 / total : 0, company: r.$4, sub: r.$5),
      ];
    }

    List<(String, num, int, RpCompany?, String?)> byLogs(String Function(FinanceLog) key, {RpCompany? Function(FinanceLog)? co}) {
      final acc = <String, (String, num, int, RpCompany?, String?)>{};
      for (final l in v.logs) {
        final c = co?.call(l);
        final k = '${c?.key ?? ''}|${key(l)}';
        final o = acc[k];
        acc[k] = (key(l), (o?.$2 ?? 0) + FinanceLogs.cashOf(l), (o?.$3 ?? 0) + 1, c, null);
      }
      return acc.values.toList();
    }

    final m = _merged ? _combined : null;
    RpCompany? co(FinanceLog l) => m == null ? null : _coOf(l, m);
    switch (tab) {
      case 'الشركة':
        return (
          shares: shares([
            for (final p in m?.included ?? const <MergedFinancePart>[])
              (
                p.company.name,
                hasType
                    ? FinanceLogs.kpisFromLogs([
                        for (final l in v.logs)
                          if (m!.logCompany[l] == p.company.key) l,
                      ]).totalCashRevenue
                    : p.report!.kpis.totalCashRevenue,
                p.report!.kpis.activationsCount + p.report!.kpis.extendCount,
                _rp(p.company),
                null,
              ),
          ]),
          note: hasType ? fromLogsNote : null,
        );
      case 'المدير':
        if (hasType || v.admins.isEmpty) {
          return (shares: shares(byLogs((l) => (l.adminUsername ?? '—').trim(), co: co)), note: fromLogsNote);
        }
        return (
          shares: shares([
            for (final (a, c) in v.admins) (a.username, a.revenue, a.activations + a.extends_, c == null ? null : _rp(c), null),
          ]),
          note: null,
        );
      case 'الموظّف':
        return (
          shares: shares(byLogs(
              (l) => (l.actingEmployeeFullName ?? '').trim().isNotEmpty ? l.actingEmployeeFullName!.trim() : 'المدير نفسه',
              co: co)),
          note: fromLogsNote,
        );
      case 'النوع':
        if (hasType || v.types.isEmpty) {
          return (shares: shares(byLogs((l) => arabicActionLabel(l.actionType, l.actionDescription ?? ''))), note: fromLogsNote);
        }
        return (
          shares: shares([
            for (final t in v.types)
              if (!FinanceLogs.excludedTypes.contains(t.type.toUpperCase())) (arabicActionLabel(t.type), t.amount, t.count, null, null),
          ]),
          note: null,
        );
      default:
        if (hasType || v.series.isEmpty) {
          return (shares: shares(byLogs((l) => FinanceView.timeOf(l) == null ? '—' : iqDateOf(FinanceView.timeOf(l)!))), note: fromLogsNote);
        }
        final days = [...v.series]..sort((a, b) => b.day.compareTo(a.day));
        final total = days.fold<num>(0, (a, d) => a + (d.revenue > 0 ? d.revenue : 0));
        return (
          shares: [
            for (final d in days)
              RpShare(name: iqDateOf(d.day), amount: d.revenue, count: d.count, share: total > 0 && d.revenue > 0 ? d.revenue / total : 0),
          ],
          note: null,
        );
    }
  }

  // ═══════════════ الرسم ═══════════════

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return ReportPermissionGate(
      permission: _perm,
      title: 'reports.financial'.tr(),
      child: Scaffold(
        backgroundColor: AppColors.bg,
        appBar: deskPageBar(
          context,
          mobile: AppBar(
            backgroundColor: AppColors.surface,
            elevation: 0,
            scrolledUnderElevation: 0,
            title: Text(
              _merged ? 'التقرير الماليّ · كل الشركات' : 'reports.financial'.tr(),
              style: AppType.title(color: AppColors.textHi).copyWith(fontSize: 16),
            ),
            iconTheme: IconThemeData(color: AppColors.textHi),
          ),
        ),
        body: SafeArea(
          child: RefreshIndicator(
            onRefresh: _load,
            color: AppColors.brand,
            child: _f == null
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, Sp.huge),
                    children: _parts(),
                  ),
          ),
        ),
      ),
    );
  }

  List<Widget> _parts() {
    final f = _f!;
    final parts = <Widget>[
      RpPeriodBar(
        period: RpPeriod(name: f.range.name, range: f.range.rangeText),
        compareOn: f.compare,
        compareWith: f.range.compareText,
        onPeriod: _openFilters,
        onCompare: () => _apply(f.copyWith(compare: !f.compare)),
      ),
    ];
    final archive = _merged ? _combined.report?.archive : _cur?.archive;
    if (archive != null) {
      parts.add(ArchiveBar(
        archive: archive,
        includeArchived: _withArchive,
        onChanged: (v) {
          setState(() => _withArchive = v);
          _load();
        },
      ));
    }
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

    if (_merged) parts.add(_companyTable());

    if (!_merged && _loading && _cur == null) {
      parts.add(const Padding(padding: EdgeInsets.symmetric(vertical: Sp.huge), child: Center(child: CircularProgressIndicator())));
      return _gapped(parts);
    }
    if (!_merged && _error != null && _cur == null) {
      parts.add(_errorPanel());
      return _gapped(parts);
    }
    final v = _view();
    if (v == null) {
      if (_merged && _cos.values.any((c) => c.loading)) {
        parts.add(Padding(
          padding: const EdgeInsets.symmetric(vertical: Sp.xl),
          child: Center(child: Text('جارٍ قراءة أرقام الشركات…', style: AppType.muted(color: AppColors.textMid))),
        ));
      }
      return _gapped(parts);
    }
    final hero = FinanceView.hero(v.kpis, v.prev);
    final spark = [for (final p in FinanceView.trend(v.series, f.range)) p.a];
    parts.add(RpHeroKpi(
      kpi: hero,
      compareWith: f.range.vsText,
      spark: spark,
      note: FinanceView.heroNote(v.kpis, mergedRule: v.mixedRules),
      notes: FinanceView.heroNotes(v.kpis, costNeedsAllTypes: v.costNeedsAllTypes),
      onTap: () => _drill(hero, v),
    ));
    parts.add(RpKpiGrid(kpis: FinanceView.kpis(v.kpis, v.prev), compareWith: f.range.vsText, onTap: (k) => _drill(k, v)));
    parts.add(RpCountsRow(items: FinanceView.counts(v.kpis)));
    // «يوماً بيوم» (الرسم) أُلغي من التقرير الماليّ (المالك ٢٢ نوفمبر: «اكو قسم بالتقارير المالية يوما بيوم هذا الغي»)
    final b = _breakdown(v);
    final cap = _tabAll ? b.shares.length : 6;
    parts.add(RpBreakdownCard(
      fold: _fold('breakdown'),
      tabs: _tabs,
      selected: _tab.clamp(0, _tabs.length - 1),
      shares: b.shares.take(cap).toList(),
      note: b.note,
      onTab: (i) => setState(() {
        _tab = i;
        _tabAll = false;
      }),
      more: b.shares.length > cap ? 'عرض الكلّ (${b.shares.length})' : null,
      onMore: () => setState(() => _tabAll = true),
    ));
    final m = _merged ? _combined : null;
    final rows = FinanceView.search(v.logs, _q);
    parts.add(RpRowsCard(
      fold: _fold('rows'),
      query: _q,
      total: rows.length,
      days: FinanceView.days(rows, companyOf: m == null ? null : (l) => _coOf(l, m), showCost: v.showCost, limit: _visible),
      more: rows.length > _visible ? 'عرض المزيد (${rows.length - _visible})' : null,
      onMore: () => setState(() => _visible += _page),
      onSearch: (q) => setState(() {
        _q = q;
        _visible = _page;
      }),
      note: v.truncated
          ? 'تُعرض آخر ${PackageCostKpis.recentLogsServerCap} حركة بالفترة — الأرقام أعلاه للفترة كلّها، والتصدير يجلبها كلّها'
          : null,
      empty: _q.trim().isEmpty ? 'لا حركات بهذه الفترة' : 'لا حركة تطابق «${_q.trim()}»',
    ));
    parts.add(RpExportBar(
      onPdf: () => _exportAll('pdf'),
      onExcel: () => _exportAll('excel'),
      onShare: () => _exportAll('share'),
    ));
    return _gapped(parts);
  }

  List<Widget> _gapped(List<Widget> parts) => [
        for (var i = 0; i < parts.length; i++) ...[if (i > 0) const SizedBox(height: Sp.md), parts[i]],
      ];

  Widget _companyTable() {
    final lines = <RpCompanyLine>[];
    final outside = <String>[];
    for (final co in _cos.values) {
      if (co.loading) {
        lines.add(RpCompanyLine(company: _rp(co.c), state: RpCompanyState.loading));
        outside.add('${co.c.name} (تُقرأ)');
      } else if (!co.included) {
        lines.add(RpCompanyLine(company: _rp(co.c, note: co.reason), state: RpCompanyState.failed));
        outside.add('${co.c.name} (${co.reason ?? 'تعذّرت'})');
      } else {
        final k = co.cur!.kpis;
        final h = FinanceView.hero(k, null);
        lines.add(RpCompanyLine(company: _rp(co.c), a: k.totalCashRevenue, b: k.activateNonCashSum + k.manualDebtAddSum, c: h.value));
      }
    }
    final inc = [
      for (final l in lines)
        if (l.state == RpCompanyState.ok) l,
    ];
    return RpCompanyTable(
      fold: _fold('companies'),
      heads: const ['الواصل', 'الدين', 'الصافي'],
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

  Widget _errorPanel() => RpCard(
        child: Column(
          children: [
            Icon(LucideIcons.triangleAlert, size: 28, color: AppColors.error),
            const SizedBox(height: Sp.sm),
            Text(_error ?? 'common.load_failed'.tr(), textAlign: TextAlign.center, style: AppType.body(color: AppColors.textMid)),
            const SizedBox(height: Sp.md),
            OutlinedButton.icon(
              onPressed: _load,
              icon: const Icon(LucideIcons.refreshCw, size: 16),
              label: Text('common.retry'.tr()),
            ),
          ],
        ),
      );
}
