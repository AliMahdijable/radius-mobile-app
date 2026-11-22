import 'dart:async';
import 'dart:collection';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../api/company_route.dart';
import '../../../api/merged_dashboard_api.dart';
import '../../../api/report_people_api.dart';
import '../../../api/reports_api.dart';
import '../../../core/util/ar_date.dart';
import '../../../core/util/server_time.dart';
import '../../../models/merged_company.dart';
import '../../../services/merged_mode.dart';
import '../../../services/permissions_service.dart';
import '../../../services/provider_limits.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';
import '../../desktop/desk_widgets.dart';
import '../widgets/report_export.dart';
import '../widgets/report_permission_gate.dart';
import '../widgets/scope_helper.dart';
import 'activations_view.dart';
import 'report_kit.dart';
import 'report_period.dart';
import 'report_prefs.dart';
import 'report_sheets.dart';

/// «التفعيلات» على الشكل الموحّد (٢٢ نوفمبر — المالك: «ادمج التفعيلات واليوميّة وانطلق»): «التفعيلات» و«التفعيلات اليوميّة»
/// تقريرٌ واحد، و«اليوم» فترةٌ فيه. من يملك «التفعيلات اليوميّة» وحدها يرى اليوم وحده كما كان.
///
/// الترتيب كالتقرير الماليّ: الفترة والمقارنة ← الشركات ← الفلاتر ← «حسب الشركة» ← البطاقات بفرقها ← الأعداد ← العدد يوماً بيوم ←
/// «قسّم حسب» (الشركة/الباقة/المدير/الموظّف/اليوم) ← الحركات يوماً يوماً + بحث ← التصدير (بالفلاتر حرفاً وكاملاً — المالك: «من
/// يختار فلاتر … ويطبع أو ينقر إكسل أو PDF يطلع على حسب الفلاتر»).
class ActivationsReportV2Screen extends StatefulWidget {
  const ActivationsReportV2Screen({super.key});

  /// ساعة التقرير (للاختبار).
  @visibleForTesting
  static DateTime Function() clock = DateTime.now;

  @override
  State<ActivationsReportV2Screen> createState() => _ActivationsReportV2State();
}

typedef _Rows = ({bool ok, List<ActivityRow> rows, String? error, bool complete});

/// شركةٌ في «كل الشركات» كما وصلت (أو تنتظر، أو تعذّرت).
class _Co {
  _Co(this.c, {this.rows, this.reason, this.loading = false, this.complete = true});
  final MergedCompany c;
  List<ActivityRow>? rows;
  List<ActivityRow>? prev;
  bool prevDone = false;
  String? reason;
  bool loading;
  bool complete;

  bool get included => !loading && rows != null && reason == null;
}

class _ActivationsReportV2State extends State<ActivationsReportV2Screen> {
  static const _id = 'activations';
  static const _page = 40;
  static const _open = RpPrefs.openGroup;

  RpFilterValue? _f;
  String? _openTag;
  bool _requested = false;
  int _seq = 0;

  // الشركة المفتوحة
  List<ActivityRow>? _rows;
  List<ActivityRow>? _prev;
  bool _complete = true;
  bool _loading = true;
  String? _error;
  List<String>? _scopeIds;

  final _cos = <String, _Co>{};
  final _people = <String, ({List<RpPerson>? managers, List<RpPerson>? employees})>{};

  int _tab = 0;
  bool _tabAll = false;
  String _q = '';
  int _visible = _page;

  bool get _merged => MergedMode.active.value;
  DateTime get _now => ActivationsReportV2Screen.clock();

  bool get _canAll => Perms.has('reports.activations');
  bool get _canToday => Perms.has('reports.daily_activations') && !providerHidesAction('reports.daily_activations');

  /// «التفعيلات اليوميّة» وحدها ⇒ اليوم وحده بلا مقارنة (معنى الصلاحيّة كما كان).
  bool get _todayOnly => !_canAll && _canToday;
  String get _perm => _canAll || !_canToday ? 'reports.activations' : 'reports.daily_activations';

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

  RpFilterValue _lock(RpFilterValue f) =>
      _todayOnly ? f.copyWith(range: RpRange.of(RpPreset.today, now: _now), compare: false) : f;

  Future<void> _start() async {
    _openTag = await MergedMode.openAdminId();
    final f = await RpPrefs.load(_id, now: _now, openTag: _openTag);
    if (!mounted) return;
    setState(() => _f = _lock(f));
    _loadIfAllowed();
  }

  void _onPerms() {
    if (mounted && !_requested) _loadIfAllowed();
  }

  void _onMerged() {
    if (!mounted || _f == null) return;
    setState(() {
      _rows = null;
      _prev = null;
      _cos.clear();
      _tab = 0;
    });
    if (_requested) _load();
  }

  void _loadIfAllowed() {
    if (_f == null || !(_canAll || _canToday)) return;
    _requested = true;
    _load();
  }

  Future<void> _load() => _merged ? _loadMerged() : _loadSingle();

  void _apply(RpFilterValue v) {
    final locked = _lock(v);
    setState(() {
      _f = locked;
      _visible = _page;
    });
    unawaited(RpPrefs.save(_id, locked, openTag: _openTag));
    _load();
  }

  // ═══════════════ الفلاتر ⇒ الطلب ═══════════════

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

  /// سطور الفترة كاملةً لنطاقٍ واحد (المفتوحة أو شركةٌ بمفتاحها): التفعيل والتمديد و«إضافة مشترك» صفحةً صفحة، الأحدث أوّلاً.
  Future<_Rows> _fetch(RpRange r, {required String group, required List<String>? ids}) async {
    final res = await Future.wait([
      for (final t in ActivationsView.types)
        ReportsApi.activitiesAll(
          from: r.from,
          to: r.to,
          activityType: t,
          userIds: ids,
          userManager: _ownerUsername(group),
          employeeId: _employeeId(group),
        ),
    ]);
    final rows = <({ActivityRow r, int at, int order})>[];
    var order = 0;
    for (final x in res) {
      for (final r in x.rows) {
        if (!ActivationsView.relevant(r)) continue;
        rows.add((r: r, at: ActivationsView.timeOf(r)?.millisecondsSinceEpoch ?? 0, order: order++));
      }
    }
    rows.sort((a, b) => a.at != b.at ? b.at.compareTo(a.at) : a.order.compareTo(b.order));
    final failed = res.where((x) => !x.ok).toList();
    return (
      ok: failed.isEmpty,
      rows: [for (final x in rows) x.r],
      error: failed.isEmpty ? null : (failed.first.error ?? 'common.load_failed'.tr()),
      complete: res.every((x) => x.complete),
    );
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
    final ids = _actorIds(_open) ?? _scopeIds;
    final cur = await _fetch(f.range, group: _open, ids: ids);
    if (!mounted || seq != _seq || _merged) return;
    setState(() {
      _loading = false;
      _rows = cur.ok ? cur.rows : null;
      _complete = cur.complete;
      _error = cur.ok ? null : cur.error;
      _visible = _page;
    });
    if (!f.compare || _todayOnly || !cur.ok) return;
    final prev = await _fetch(f.range.previous, group: _open, ids: ids);
    if (!mounted || seq != _seq || _merged) return;
    setState(() => _prev = prev.ok && prev.complete ? prev.rows : null);
  }

  List<MergedCompany> get _countable => MergedDashboardApi.countable();

  List<MergedCompany> get _picked {
    final all = _countable;
    final sel = _f!.companies;
    final picked = sel.isEmpty ? all : all.where((c) => sel.contains(c.key)).toList();
    return picked.isEmpty ? all : picked;
  }

  static bool _supports(MergedCompany c) => c.provider != MergedProvider.ftth && c.provider != MergedProvider.fiberx;

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
    if (!_supports(c)) {
      setState(() => _cos[c.key] = _Co(c, reason: 'لا تفعيلاتٍ تُقرأ لنوعها من هنا'));
      return;
    }
    if (MergedMode.pagePermAny(c.key, const ['reports.activations', 'reports.daily_activations']) == false) {
      setState(() => _cos[c.key] = _Co(c, reason: MergedMode.noAccess('تفعيلاتها')));
      return;
    }
    final ids = _actorIds(c.key) ?? [c.adminId];
    final r = await CompanyRoute.run(c.key, () => _fetch(f.range, group: c.key, ids: ids));
    if (!mounted || seq != _seq) return;
    setState(() => _cos[c.key] = _Co(c, rows: r.ok ? r.rows : null, reason: r.ok ? null : r.error, complete: r.complete));
    if (!f.compare || _todayOnly || !r.ok) return;
    final p = await CompanyRoute.run(c.key, () => _fetch(f.range.previous, group: c.key, ids: ids));
    if (!mounted || seq != _seq) return;
    setState(() {
      final co = _cos[c.key];
      if (co == null) return;
      co.prev = p.ok && p.complete ? p.rows : null;
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

  /// اسم الباقة كما في «قسّم حسب الباقة» — وما بلا باقةٍ اسمٌ صريح يُختار أيضاً.
  static String _pkgName(ActivityRow r) => (r.packageName ?? '').isNotEmpty
      ? r.packageName!
      : (ActivationsView.kindOf(r) == ActKind.extend ? 'تمديد (بلا باقة)' : 'بلا باقة');

  /// فلتر الباقة (بند المقترح ١٢) على سطور شركةٍ واحدة ([company] null = المفتوحة) — السطور كاملةٌ للفترة فالرقم صادق.
  List<ActivityRow> _byPackage(List<ActivityRow> rows, String? company) {
    final want = _f!.packages;
    if (want.isEmpty) return rows;
    return [for (final r in rows) if (want.contains(RpFilterValue.packageKey(company, _pkgName(r)))) r];
  }

  /// باقات الفترة لورقة الفلاتر — من السطور المقروءة (لا باقةٌ بلا حركة)، وفي «كل الشركات» باسم شركتها.
  List<(String, String)> get _packagesInPeriod {
    final out = <String, String>{};
    if (!_merged) {
      for (final r in _rows ?? const <ActivityRow>[]) {
        final n = _pkgName(r);
        out[RpFilterValue.packageKey(null, n)] = n;
      }
    } else {
      for (final co in _cos.values) {
        if (!co.included) continue;
        for (final r in co.rows!) {
          final n = _pkgName(r);
          out[RpFilterValue.packageKey(co.c.key, n)] = '$n · ${co.c.name}';
        }
      }
    }
    // المختارة قبلُ تبقى ظاهرةً ولو غابت عن هذه الفترة — لتُزال
    for (final k in _f!.packages) {
      out.putIfAbsent(k, () => _packageLabel(k));
    }
    final list = [for (final e in out.entries) (e.key, e.value)]..sort((a, b) => a.$2.compareTo(b.$2));
    return list;
  }

  String _packageLabel(String key) {
    final i = key.indexOf('|');
    final company = i <= 0 ? null : MergedMode.companyOf(key.substring(0, i))?.name;
    final name = i < 0 ? key : key.substring(i + 1);
    return company == null ? name : '$name · $company';
  }

  /// سطور الشاشة بعد النوع، وشركة كلّ سطر، والسابقة (null: لا مقارنة)، وهل اكتملت.
  ({List<ActivityRow> rows, Map<ActivityRow, String?> co, List<ActivityRow>? prev, bool complete})? _view() {
    final kinds = _f!.types;
    if (!_merged) {
      final r = _rows;
      if (r == null) return null;
      return (
        rows: _byPackage(ActivationsView.filter(r, kinds), null),
        co: LinkedHashMap<ActivityRow, String?>.identity(),
        prev: _prev == null ? null : _byPackage(ActivationsView.filter(_prev!, kinds), null),
        complete: _complete,
      );
    }
    final inc = [
      for (final co in _cos.values)
        if (co.included) co,
    ];
    if (inc.isEmpty) return null;
    final tagged = <({ActivityRow r, String key, int at, int order})>[];
    var order = 0;
    for (final co in inc) {
      for (final r in _byPackage(co.rows!, co.c.key)) {
        tagged.add((r: r, key: co.c.key, at: ActivationsView.timeOf(r)?.millisecondsSinceEpoch ?? 0, order: order++));
      }
    }
    tagged.sort((a, b) => a.at != b.at ? b.at.compareTo(a.at) : a.order.compareTo(b.order));
    final map = LinkedHashMap<ActivityRow, String?>.identity();
    for (final t in tagged) {
      map[t.r] = t.key;
    }
    final prevReady = inc.every((co) => co.prevDone && co.prev != null);
    return (
      rows: ActivationsView.filter([for (final t in tagged) t.r], kinds),
      co: map,
      prev: prevReady ? ActivationsView.filter([for (final co in inc) ..._byPackage(co.prev!, co.c.key)], kinds) : null,
      complete: inc.every((co) => co.complete),
    );
  }

  RpCompany _rp(MergedCompany c, {bool selected = true, String? note}) =>
      RpCompany(key: c.key, name: c.name, colorIndex: c.colorIndex, selected: selected, note: note);

  RpCompany? _coOf(ActivityRow r, Map<ActivityRow, String?> co) {
    final key = co[r];
    final c = key == null ? null : _cos[key];
    return c == null ? null : _rp(c.c);
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
        _sheetRefresh = () => setSheet(() {});
        return RpFilterSheet(
          subtitle: 'التفعيلات · ${f.range.name}',
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
          types: [for (final e in ActivationsView.kindKeys.entries) (e.key, ActivationsView.kindLabel(e.value))],
          packages: _packagesInPeriod,
        );
      }),
    );
    unawaited(_loadPeople(keys).then((_) => _sheetRefresh?.call()));
    final v = await sheetFuture;
    _sheetRefresh = null;
    if (v != null && mounted) {
      if (_todayOnly && v.range.preset != RpPreset.today) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('صلاحيّتك «التفعيلات اليوميّة» — اليوم وحده')));
      }
      _apply(v);
    }
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

  // ═══════════════ التصدير ═══════════════

  List<String> get _columns => [
        if (_merged) 'الشركة',
        'اسم المشترك',
        'اليوزر',
        'النوع',
        'الباقة',
        'المبلغ',
        'منه بالدين',
        'التاريخ',
        'المنفذ',
      ];

  List<double> get _weights => [if (_merged) 1.4, 2.2, 1.4, 1.2, 1.8, 1.2, 1.1, 1.4, 1.3];

  List<List<String>> _exportRows(List<ActivityRow> rows, Map<ActivityRow, String?> co) => [
        for (final r in rows)
          (() {
            final k = ActivationsView.kindOf(r);
            final m = ActivationsView.moneyOf(r);
            final amount = k == ActKind.debt ? m.debt : (k == ActKind.cash ? m.cash : null);
            return [
              if (_merged) MergedMode.companyOf(co[r])?.name ?? '',
              r.userFullName ?? r.targetName ?? r.userUsername ?? '',
              r.userUsername ?? '',
              ActivationsView.kindLabel(k),
              r.packageName ?? '',
              amount == null || amount == 0 ? '' : '$amount',
              k == ActKind.cash && r.partialUnpaid > 0 ? '${r.partialUnpaid}' : '',
              exportTime(r.createdAt),
              ActivationsView.actorOf(r),
            ];
          })(),
      ];

  List<String> _exportDetails({required int count, String? drill, bool withSearch = true, required bool complete}) {
    final q = _q.trim();
    final inc = [
      for (final co in _cos.values)
        if (co.included) co.c.name,
    ];
    final out = [
      for (final co in _cos.values)
        if (!co.included) '${co.c.name} (${co.reason ?? 'تعذّرت'})',
    ];
    return [
      if (_merged) 'الشركات: ${inc.join('، ')}',
      if (_merged && out.isNotEmpty) 'خارج الملفّ: ${out.join('، ')}',
      for (final c in _chips()) c.label,
      if (drill != null) 'الحركات: $drill',
      if (withSearch && q.isNotEmpty) 'بحث: «$q»',
      'عدد الحركات: $count',
      if (!complete) 'ناقص: الفترة أطول من أن تُجلب كلّها مرّةً واحدة — صدّرها على أجزاء',
    ];
  }

  bool get _busy => _merged ? _cos.values.any((c) => c.loading) || _cos.isEmpty : _loading;

  /// التصدير = ما على الشاشة حرفاً (النوع، ثمّ البطاقة الملموسة، ثمّ البحث)؛ السطور كاملةٌ أصلاً (صفحةً صفحة)، ورأس الملفّ يسمّي الفلاتر.
  Future<void> _exportAll(String how, {String title = '', bool Function(ActivityRow)? pick, String? drill, bool withSearch = true}) async {
    final v = _view();
    if (v == null) return;
    if (_busy) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('انتظر حتى تكتمل الأرقام ثمّ صدّر')));
      return;
    }
    var rows = v.rows;
    if (pick != null) rows = rows.where(pick).toList();
    if (withSearch) rows = ActivationsView.search(rows, _q);
    final t = title.isEmpty ? 'reports.activations'.tr() : title;
    final data = _exportRows(rows, v.co);
    final details = _exportDetails(count: data.length, drill: drill, withSearch: withSearch, complete: v.complete);
    final subtitle = '${_f!.range.name} · ${_f!.range.rangeText}';
    switch (how) {
      case 'pdf':
        return ReportExportActions.pdf(context,
            title: t, subtitle: subtitle, details: details, columns: _columns, rows: data, columnWeights: _weights, fileNameBase: 'activations');
      case 'excel':
        return ReportExportActions.csv(context,
            title: t, subtitle: subtitle, details: details, columns: _columns, rows: data, fileNameBase: 'activations');
      default:
        return ReportExportActions.sharePdf(context,
            title: t, subtitle: subtitle, details: details, columns: _columns, rows: data, columnWeights: _weights, fileNameBase: 'activations');
    }
  }

  void _drill(RpKpi k, ({List<ActivityRow> rows, Map<ActivityRow, String?> co, List<ActivityRow>? prev, bool complete}) v) {
    final pick = ActivationsView.drill(k.id);
    final rows = v.rows.where(pick).toList();
    final scope = [
      _f!.range.name,
      if (_merged) [for (final co in _cos.values) if (co.included) co.c.name].join('، '),
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
          total: rows.length,
          days: ActivationsView.days(rows, companyOf: _merged ? (r) => _coOf(r, v.co) : null, limit: 80),
          more: rows.length > 80 ? 'الأولى 80 — كلّها بالتصدير' : null,
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
        for (final e in ActivationsView.kindKeys.entries)
          if (f.types.contains(e.key)) ActivationsView.kindLabel(e.value),
      ];
      out.add(RpChip('النوع: ${labels.join('، ')}', onRemove: () => _apply(f.copyWith(types: const []))));
    }
    if (f.packages.isNotEmpty) {
      out.add(RpChip('الباقة: ${[for (final k in f.packages) _packageLabel(k)].join('، ')}',
          onRemove: () => _apply(f.copyWith(packages: const {}))));
    }
    return out;
  }

  // ═══════════════ «قسّم حسب» ═══════════════

  List<String> get _tabs => [if (_merged) 'الشركة', 'الباقة', 'المدير', 'الموظّف', 'اليوم'];

  List<RpShare> _breakdown(({List<ActivityRow> rows, Map<ActivityRow, String?> co, List<ActivityRow>? prev, bool complete}) v) {
    final tab = _tabs[_tab.clamp(0, _tabs.length - 1)];
    RpCompany? co(ActivityRow r) => _merged ? _coOf(r, v.co) : null;
    switch (tab) {
      case 'الشركة':
        return ActivationsView.shares(v.rows, (r) => _coOf(r, v.co)?.name ?? '—', companyOf: co);
      case 'الباقة':
        return ActivationsView.shares(
            v.rows,
            (r) => (r.packageName ?? '').isNotEmpty
                ? r.packageName!
                : (ActivationsView.kindOf(r) == ActKind.extend ? 'تمديد (بلا باقة)' : 'بلا باقة'),
            companyOf: co);
      case 'المدير':
        return ActivationsView.shares(v.rows, (r) => (r.adminUsername ?? '—').trim(), companyOf: co);
      case 'الموظّف':
        return ActivationsView.shares(
            v.rows,
            (r) => (r.actingEmployeeFullName ?? '').trim().isNotEmpty ? r.actingEmployeeFullName!.trim() : 'المدير نفسه',
            companyOf: co);
      default:
        return ActivationsView.shares(v.rows, (r) {
          final t = ActivationsView.timeOf(r);
          return t == null ? '—' : iqDateOf(t);
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return ReportPermissionGate(
      permission: _perm,
      title: 'reports.activations'.tr(),
      child: Scaffold(
        backgroundColor: AppColors.bg,
        appBar: deskPageBar(
          context,
          mobile: AppBar(
            backgroundColor: AppColors.surface,
            elevation: 0,
            scrolledUnderElevation: 0,
            title: Text(
              _merged ? 'التفعيلات · كل الشركات' : 'reports.activations'.tr(),
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
        onPeriod: _todayOnly ? null : _openFilters,
        onCompare: _todayOnly ? null : () => _apply(f.copyWith(compare: !f.compare)),
      ),
    ];
    if (_todayOnly) {
      parts.add(Text('صلاحيّتك «التفعيلات اليوميّة» — تُعرض تفعيلات اليوم وحده',
          style: AppType.micro(color: AppColors.textMid), maxLines: 2));
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

    if (!_merged && _loading && _rows == null) {
      parts.add(const Padding(padding: EdgeInsets.symmetric(vertical: Sp.huge), child: Center(child: CircularProgressIndicator())));
      return _gapped(parts);
    }
    if (!_merged && _error != null && _rows == null) {
      parts.add(_errorPanel());
      return _gapped(parts);
    }
    final v = _view();
    if (v == null) {
      if (_merged && _cos.values.any((c) => c.loading)) {
        parts.add(Padding(
          padding: const EdgeInsets.symmetric(vertical: Sp.xl),
          child: Center(child: Text('جارٍ قراءة تفعيلات الشركات…', style: AppType.muted(color: AppColors.textMid))),
        ));
      }
      return _gapped(parts);
    }
    final kpis = ActivationsView.kpis(v.rows, v.prev);
    parts.add(RpKpiGrid(kpis: kpis, compareWith: f.range.vsText, onTap: (k) => _drill(k, v)));
    if (kpis.length < 4) {
      parts.add(Text('مبالغ التفعيل لا تصل من هذا الخادم بعد — الأعداد وحدها', style: AppType.micro(color: AppColors.textMid)));
    }
    parts.add(RpCountsRow(items: ActivationsView.counts(v.rows)));
    final trend = ActivationsView.trend(v.rows, f.range);
    if (trend.length > 1) {
      parts.add(RpTrendCard(
        fold: _fold('trend'),
        title: f.range.days > 62 ? 'العدد شهراً بشهر' : 'العدد يوماً بيوم',
        monthly: f.range.days > 62,
        points: trend,
        aLabel: 'تفعيل',
        bLabel: 'تمديد',
        aTone: RpTone.brand,
        bTone: RpTone.info,
      ));
    }
    final shares = _breakdown(v);
    final cap = _tabAll ? shares.length : 6;
    parts.add(RpBreakdownCard(
      fold: _fold('breakdown'),
      tabs: _tabs,
      selected: _tab.clamp(0, _tabs.length - 1),
      tone: RpTone.brand,
      shares: shares.take(cap).toList(),
      onTab: (i) => setState(() {
        _tab = i;
        _tabAll = false;
      }),
      more: shares.length > cap ? 'عرض الكلّ (${shares.length})' : null,
      onMore: () => setState(() => _tabAll = true),
    ));
    final rows = ActivationsView.search(v.rows, _q);
    parts.add(RpRowsCard(
      fold: _fold('rows'),
      query: _q,
      total: rows.length,
      days: ActivationsView.days(rows, companyOf: _merged ? (r) => _coOf(r, v.co) : null, limit: _visible),
      more: rows.length > _visible ? 'عرض المزيد (${rows.length - _visible})' : null,
      onMore: () => setState(() => _visible += _page),
      onSearch: (q) => setState(() {
        _q = q;
        _visible = _page;
      }),
      note: v.complete ? null : 'الفترة طويلة جدّاً — لم تُجلب كلّ حركاتها، فالأرقام قد تنقص',
      empty: _q.trim().isEmpty ? 'لا تفعيلات بهذه الفترة' : 'لا حركة تطابق «${_q.trim()}»',
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
        final t = ActivationsView.totals(ActivationsView.filter(_byPackage(co.rows!, co.c.key), _f!.types));
        lines.add(RpCompanyLine(
          company: _rp(co.c),
          a: t.known ? t.cash : null,
          b: t.known ? t.debt : null,
          c: t.activations + t.extends_,
        ));
      }
    }
    final inc = [
      for (final l in lines)
        if (l.state == RpCompanyState.ok) l,
    ];
    return RpCompanyTable(
      fold: _fold('companies'),
      heads: const ['نقداً', 'بالدين', 'الحركات'],
      lines: lines,
      // مالٌ مجهولٌ في شركةٍ داخلة ⇒ المجموع «—» لا جمع المعروف وحده
      total: [
        inc.any((l) => l.a == null) ? null : inc.fold<num>(0, (a, l) => a + l.a!),
        inc.any((l) => l.b == null) ? null : inc.fold<num>(0, (a, l) => a + l.b!),
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
