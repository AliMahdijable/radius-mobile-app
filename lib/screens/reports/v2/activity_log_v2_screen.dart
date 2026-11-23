import 'dart:async';
import 'dart:collection';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../api/archive_info.dart';
import '../../../api/company_route.dart';
import '../../../api/expenses_api.dart';
import '../../../api/merged_dashboard_api.dart';
import '../../../api/report_people_api.dart';
import '../../../api/reports_api.dart';
import '../../../core/util/ar_date.dart';
import '../../../core/util/server_time.dart';
import '../../../models/merged_company.dart';
import '../../../services/merged_mode.dart';
import '../../../services/provider_service.dart';
import '../../../services/permissions_service.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';
import '../../desktop/desk_widgets.dart';
import '../widgets/action_labels.dart';
import '../widgets/report_export.dart';
import '../widgets/report_permission_gate.dart';
import '../widgets/scope_helper.dart';
import 'activity_log_view.dart';
import 'report_kit.dart';
import 'report_period.dart';
import 'report_prefs.dart';
import 'report_sheets.dart';
import '../../../services/employee_visibility.dart';

/// «سجلّ الحركات» على الشكل الموحّد (٢٢ نوفمبر — «كمل بقية التقارير»): الفترة ← الشركات ← الفلاتر ← «حسب الشركة» ← الأعداد
/// (ولمسها حركاتها) ← العدد يوماً بيوم ← «قسّم حسب» النوع/المدير/الموظّف/اليوم ← الحركات يوماً يوماً + بحث ← التصدير بالفلاتر حرفاً.
/// كلّ حركات الفترة صفحةً صفحة بلا الإشعارات الآليّة (الخادم 9bfabd2)؛ الصرفيّات من قائمتها للشركة المفتوحة كما كانت.
/// إشعار «عمليّات الموظّفين» (data.type = employee_ops — الخادم server/employeeOps.js، ٢٣ نوفمبر) ⇒ «سجلّ الحركات» لهذه الصفحة
/// بفلتر ذلك الموظّف وفترةٍ تضمّ عمليّاته. ملخّص أوقات السكون (employee_id فارغ) ⇒ كلّ الحركات من أوّل أمس.
/// الإشعار لصفحةٍ أخرى من شركات الحساب تفتحها [CompanyPush] قبل هذا، فالمفتوحة هنا صفحته.
Future<bool> openEmployeeOpsPush(NavigatorState nav, Map<String, String> data) async {
  if (data['type'] != 'employee_ops') return false;
  final id = (data['employee_id'] ?? '').trim();
  await nav.push(MaterialPageRoute(
    builder: (_) => ActivityLogV2Screen(push: EmployeeOpsPush(employeeId: int.tryParse(id) != null ? id : null)),
  ));
  return true;
}

/// ما جاء به الإشعار — لهذا الفتح وحده: لا يُحفظ فوق فلاتر السجلّ المحفوظة.
class EmployeeOpsPush {
  const EmployeeOpsPush({this.employeeId});

  /// رقم الموظّف بجدول موظّفينا (acting_employee_id) — null: ملخّص السكون لكلّ الموظّفين.
  final String? employeeId;
}

/// فترة الإشعار: اليوم — إلّا ملخّص السكون (يجمع ما جرى منذ بدايته، وقد بدأ أمس) أو الساعة الأولى بعد منتصف الليل (عمليّاتٌ
/// أُرسلت دفعتُها بعد يومها) ⇒ من أوّل أمس حتى اليوم.
@visibleForTesting
RpRange employeeOpsRange(DateTime now, {required bool digest}) {
  if (!digest && now.hour >= 1) return RpRange.of(RpPreset.today, now: now);
  return RpRange.of(RpPreset.custom, now: now, from: DateTime(now.year, now.month, now.day - 1), to: now);
}

class ActivityLogV2Screen extends StatefulWidget {
  const ActivityLogV2Screen({super.key, this.push});

  /// فُتح من إشعار «عمليّات الموظّفين» ⇒ الصفحة المفتوحة وحدها (لا «كل الشركات») بفلتر الموظّف وفترته ([openEmployeeOpsPush]).
  final EmployeeOpsPush? push;

  @visibleForTesting
  static DateTime Function() clock = DateTime.now;

  @override
  State<ActivityLogV2Screen> createState() => _ActivityLogV2State();
}

typedef _Rows = ({bool ok, List<ActivityRow> rows, String? error, bool complete});

class _Co {
  _Co(this.c, {this.rows, this.reason, this.loading = false, this.complete = true});
  final MergedCompany c;
  List<ActivityRow>? rows;
  String? reason;
  bool loading;
  bool complete;

  bool get included => !loading && rows != null && reason == null;
}

class _ActivityLogV2State extends State<ActivityLogV2Screen> {
  static const _id = 'activity_log';
  static const _perm = 'reports.activity_log';
  static const _page = 40;
  static const _open = RpPrefs.openGroup;

  /// السجلّ أوسع من غيره (كلّ الأنواع): سقف 10 صفحات × 2000 لكلّ نطاق — ما بعده يُقال «ناقص».
  static const _maxPages = 10;

  RpFilterValue? _f;
  String? _openTag;
  bool _requested = false;
  int _seq = 0;

  List<ActivityRow>? _rows;
  bool _complete = true;
  bool _expensesCapped = false;
  bool _loading = true;
  String? _error;
  List<String>? _scopeIds;

  final _cos = <String, _Co>{};
  final _people = <String, ({List<RpPerson>? managers, List<RpPerson>? employees})>{};

  int _tab = 0;
  bool _tabAll = false;
  String _q = '';
  int _visible = _page;

  bool get _merged => widget.push == null && MergedMode.active.value;
  DateTime get _now => ActivityLogV2Screen.clock();

  /// الأقسام الفرعيّة المطويّة (المالك ٢٢ نوفمبر: «المهمّات تظهر والفرعيّة هو ينقر عليها ويظهرها»).
  late final _folds = RpFolds(_id, const {'rows': true});
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
    final push = widget.push;
    final emp = push?.employeeId;
    final f = push != null
        ? RpFilterValue(
            range: employeeOpsRange(_now, digest: emp == null),
            employees: {
              if (emp != null) _open: {emp},
            },
          )
        : await RpPrefs.load(_id, now: _now, openTag: _openTag, fallback: RpPreset.thisWeek);
    if (!mounted) return;
    setState(() => _f = f.copyWith(compare: false));
    _loadIfAllowed();
  }

  void _onPerms() {
    if (mounted && !_requested) _loadIfAllowed();
  }

  void _onMerged() {
    if (!mounted || _f == null) return;
    setState(() {
      _rows = null;
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
    final f = v.copyWith(compare: false);
    setState(() {
      _f = f;
      _visible = _page;
    });
    // فتح الإشعار لا يكتب فوق فلاتر الوكيل المحفوظة (موظّفه وفترته لهذا الفتح وحده)
    if (widget.push == null) unawaited(RpPrefs.save(_id, f, openTag: _openTag));
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

  /// ايرث لنك المفتوحة بفلتر موظّف (واحدٍ أو أكثر).
  bool get _elEmployeeFilter => !_merged && ProviderService.isEarthlink && _employeeIds(_open).isNotEmpty;

  static const _elNote = 'ايرث لنك: الصرفيّات لا تُفرز بالموظّف — لا تُدمج تحت فلتر الموظّف';

  /// موظّفو الشركة المختارون — واحدٌ أو أكثر (lib/api/employee_filter.dart).
  List<int> _employeeIds(String group) => [
        for (final s in _f!.employees[group] ?? const <String>{})
          if (int.tryParse(s) != null) int.parse(s),
      ];

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

  /// أنواع السجلّ المطلوبة من الخادم (بلا الصرفيّات — من قائمتها) — null: كلّ الأنواع عدا الإشعارات.
  List<String>? get _logTypes {
    final t = _f!.types.where((x) => !ActivityLogView.expenseTypes.contains(x)).toList();
    return t.isEmpty ? (_f!.types.isEmpty ? null : const []) : t;
  }

  /// تُدمج الصرفيّات؟ بلا نوعٍ مختار، أو حين يُختار نوع صرفيّة — وصرفيّات صاحب الصفحة وحده: لا تُدمج حين يُحصر السجلّ بمدير
  /// المشترك أو بمديرٍ غير صاحبها (كانت تظهر تحت فلتر مديرٍ فرعيّ وليست له)؛ وبفلتر الموظّف صرفيّاته وحده.
  bool get _wantExpenses {
    final f = _f!;
    // ايرث لنك: صرفيّاتها لا تُفرز بالموظّف (خادمها، بالواحد وبالأكثر — d9 ٢٣ نوفمبر) ⇒ لا تُدمج تحت فلتر موظّف، ويُقال ([_elNote])
    if (_elEmployeeFilter) return false;
    if (f.types.isNotEmpty && !f.types.any(ActivityLogView.expenseTypes.contains)) return false;
    if (_ownerUsername(_open) != null) return false;
    final actors = _actorIds(_open);
    return actors == null || actors.any((id) => _scopeIds?.contains(id) ?? false);
  }

  Future<_Rows> _fetch(RpRange r, {required String group, required List<String>? ids}) async {
    final types = _logTypes;
    if (types != null && types.isEmpty) return (ok: true, rows: const <ActivityRow>[], error: null, complete: true);
    return ReportsApi.activitiesAll(
      from: r.from,
      to: r.to,
      activityTypes: types,
      excludeTypes: types == null ? ActivityLogView.excluded : null,
      userIds: ids,
      userManager: _ownerUsername(group),
      employeeIds: _employeeIds(group),
      maxPages: _maxPages,
    );
  }

  static int _ms(ActivityRow r) => ActivityLogView.timeOf(r)?.millisecondsSinceEpoch ?? 0;

  Future<void> _loadSingle() async {
    final seq = ++_seq;
    final f = _f!;
    setState(() {
      _loading = true;
      _error = null;
    });
    _scopeIds ??= await loadScopeUserIds();
    if (f.managers.isNotEmpty) await _loadPeople([null]);
    // موظّفون محفوظون ⇒ أسماؤهم للشارة ورأس الملفّ (بالخلفيّة — لا تؤخّر التقرير؛ كانت «موظّف، موظّف» حتى تُفتح الورقة)
    if (f.employees.isNotEmpty) unawaited(_loadPeople([for (final k in f.employees.keys) k == _open ? null : k]));
    if (!mounted || seq != _seq || _merged) return;
    final ids = _actorIds(_open) ?? _scopeIds;
    final want = _wantExpenses;
    // سجلّ تدقيق: الصرفيّات ومعها المسوّاة (includeArchived) كما كانت؛ للمفتوحة صراحةً. نوعا الطلبين صريحان (لا Future.wait بتحويل
    // سجلٍّ بشكله — كسر الشاشة السابقة مرّتين حين زاد ExpensesApi.list حقلاً).
    final Future<({List<ExpenseRow> rows, num total, ArchiveInfo? archive, bool? routedWrites})> expF = want
        ? CompanyRoute.runOpen(() => ExpensesApi.list(
              from: _day(f.range.from),
              to: _day(f.range.to),
              limit: 5000,
              includeArchived: true,
              employeeIds: _employeeIds(_open),
            ))
        : Future.value((rows: const <ExpenseRow>[], total: 0, archive: null, routedWrites: null));
    final (acts, exps) = await (_fetch(f.range, group: _open, ids: ids), expF).wait;
    if (!mounted || seq != _seq || _merged) return;
    final expRows = [
      for (final e in exps.rows)
        ActivityLogView.expenseRow(id: e.id, amount: e.amount, date: e.expenseDate, note: e.note, actor: e.actingEmployeeUsername),
    ];
    final all = [...acts.rows, ...expRows]..sort((a, b) => _ms(b).compareTo(_ms(a)));
    setState(() {
      _loading = false;
      _rows = acts.ok ? all : null;
      _complete = acts.complete;
      _expensesCapped = exps.rows.length >= 5000;
      _error = acts.ok ? null : acts.error;
      _visible = _page;
    });
  }

  static String _day(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

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
    // موظّفون محفوظون ⇒ أسماؤهم للشارة ورأس الملفّ (بالخلفيّة — لا تؤخّر التقرير؛ كانت «موظّف، موظّف» حتى تُفتح الورقة)
    if (f.employees.isNotEmpty) unawaited(_loadPeople([for (final k in f.employees.keys) k == _open ? null : k]));
    if (!mounted || seq != _seq) return;
    await Future.wait([for (final c in cs) _loadCo(c, seq)]);
  }

  Future<void> _loadCo(MergedCompany c, int seq) async {
    final f = _f!;
    if (c.provider == MergedProvider.ftth || c.provider == MergedProvider.fiberx) {
      setState(() => _cos[c.key] = _Co(c, reason: 'لا حركاتٍ تُقرأ لنوعها من هنا'));
      return;
    }
    if (MergedMode.pagePermAny(c.key, const [_perm]) == false) {
      setState(() => _cos[c.key] = _Co(c, reason: MergedMode.noAccess('سجلّها')));
      return;
    }
    final ids = _actorIds(c.key) ?? [c.adminId];
    final r = await CompanyRoute.run(c.key, () => _fetch(f.range, group: c.key, ids: ids));
    if (!mounted || seq != _seq) return;
    setState(() => _cos[c.key] = _Co(c, rows: r.ok ? r.rows : null, reason: r.ok ? null : r.error, complete: r.complete));
  }

  void _retry(String key) {
    final co = _cos[key];
    if (co == null) return;
    setState(() => _cos[key] = _Co(co.c, loading: true));
    unawaited(_loadCo(co.c, _seq));
  }

  // ═══════════════ ما يُرسم ═══════════════

  ({List<ActivityRow> rows, Map<ActivityRow, String?> co, bool complete})? _view() {
    final types = _f!.types;
    if (!_merged) {
      final r = _rows;
      if (r == null) return null;
      return (rows: ActivityLogView.filter(r, types), co: LinkedHashMap<ActivityRow, String?>.identity(), complete: _complete && !_expensesCapped);
    }
    final inc = [
      for (final co in _cos.values)
        if (co.included) co,
    ];
    if (inc.isEmpty) return null;
    final tagged = <({ActivityRow r, String key, int at, int order})>[];
    var order = 0;
    for (final co in inc) {
      for (final r in co.rows!) {
        tagged.add((r: r, key: co.c.key, at: _ms(r), order: order++));
      }
    }
    tagged.sort((a, b) => a.at != b.at ? b.at.compareTo(a.at) : a.order.compareTo(b.order));
    final map = LinkedHashMap<ActivityRow, String?>.identity();
    for (final t in tagged) {
      map[t.r] = t.key;
    }
    return (
      rows: ActivityLogView.filter([for (final t in tagged) t.r], types),
      co: map,
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
          subtitle: 'سجلّ الحركات · ${f.range.name}',
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
          types: ActivityLogView.typeOptions,
          showCompare: false,
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

  // ═══════════════ التصدير ═══════════════

  List<String> get _columns => [
        if (_merged) 'الشركة',
        'reports.col_subscriber'.tr(),
        'reports.col_username'.tr(),
        'reports.col_amount'.tr(),
        'reports.col_date'.tr(),
        'reports.col_description'.tr(),
        'reports.col_type'.tr(),
        'reports.col_executor'.tr(),
      ];

  /// أوزان الشاشة السابقة (مطلب 2026-07-12): الاسم والوصف أعرض.
  List<double> get _weights => [if (_merged) 1.4, 2.2, 1.4, 1.2, 1.4, 2.6, 1.1, 1.3];

  List<List<String>> _exportRows(List<ActivityRow> rows, Map<ActivityRow, String?> co) => [
        for (final r in rows)
          [
            if (_merged) MergedMode.companyOf(co[r])?.name ?? '',
            rpSubjectTitle(fullName: r.userFullName, target: r.targetName, username: r.userUsername, fallback: ''),
            Sees.usernames ? (r.userUsername ?? '') : kHiddenWord,
            ActivityLogView.moneyOf(r) == null ? '' : '${ActivityLogView.moneyOf(r)}',
            exportTimeAr(r.createdAt),
            rpHideUser(r.editSummary ?? (r.actionDescription ?? '').replaceAll('\n', ' '), r.userUsername ?? r.targetName),
            arabicActionLabel(r.actionType, r.actionDescription ?? ''),
            ActivityLogView.actorOf(r),
          ],
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
      if (_merged) 'الصرفيّات لا تُخلط هنا — تظهر في سجلّ كلّ شركةٍ حين تُفتح وحدها',
      if (_elEmployeeFilter) _elNote,
      for (final c in _chips()) c.label,
      if (drill != null) 'الحركات: $drill',
      if (withSearch && q.isNotEmpty) 'بحث: «$q»',
      'عدد الحركات: $count',
      if (!complete) 'ناقص: الفترة أطول من أن تُجلب كلّها مرّةً واحدة — صدّرها على أجزاء',
    ];
  }

  bool get _busy => _merged ? _cos.values.any((c) => c.loading) || _cos.isEmpty : _loading;

  Future<void> _exportAll(String how, {String title = '', bool Function(ActivityRow)? pick, String? drill, bool withSearch = true}) async {
    final v = _view();
    if (v == null) return;
    if (_busy) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('انتظر حتى تكتمل الحركات ثمّ صدّر')));
      return;
    }
    var rows = v.rows;
    if (pick != null) rows = rows.where(pick).toList();
    if (withSearch) rows = ActivityLogView.search(rows, _q);
    final t = title.isEmpty ? 'reports.activity_log'.tr() : title;
    final data = _exportRows(rows, v.co);
    final details = _exportDetails(count: data.length, drill: drill, withSearch: withSearch, complete: v.complete);
    final subtitle = '${_f!.range.name} · ${_f!.range.rangeText}';
    switch (how) {
      case 'pdf':
        return ReportExportActions.pdf(context,
            title: t, subtitle: subtitle, details: details, columns: _columns, rows: data, columnWeights: _weights, fileNameBase: 'activity_log');
      case 'excel':
        return ReportExportActions.csv(context,
            title: t, subtitle: subtitle, details: details, columns: _columns, rows: data, fileNameBase: 'activity_log');
      default:
        return ReportExportActions.sharePdf(context,
            title: t, subtitle: subtitle, details: details, columns: _columns, rows: data, columnWeights: _weights, fileNameBase: 'activity_log');
    }
  }

  void _drill(RpKpi k, ({List<ActivityRow> rows, Map<ActivityRow, String?> co, bool complete}) v) {
    final pick = ActivityLogView.drill(k.id);
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
      builder: (ctx) {
        var q = '';
      // بحثٌ داخل حركات الرقم (المالك ٢٢ نوفمبر: «أضف إمكانيّة بحث هنا») — يحصر القائمة والتصدير، ورأس الملفّ يسمّيه
        return StatefulBuilder(builder: (ctx, setLocal) {
          final s = q.trim();
          final shown = s.isEmpty ? rows : ActivityLogView.search(rows, s);
          return RpDrillSheet(
            kpi: k,
            scope: scope,
            chips: [for (final c in _chips()) RpChip(c.label)],
            rows: RpRowsCard(
              query: q,
              total: shown.length,
              days: ActivityLogView.days(shown, companyOf: _merged ? (r) => _coOf(r, v.co) : null, limit: 80),
              more: shown.length > 80 ? 'الأولى 80 — كلّها بالتصدير' : null,
              onSearch: (x) => setLocal(() => q = x),
              empty: s.isEmpty ? null : 'لا حركة تطابق «$s»',
            ),
            onExport: () => _exportAll('share',
                title: k.label,
                pick: s.isEmpty ? pick : (r) => pick(r) && ActivityLogView.search([r], s).isNotEmpty,
                drill: s.isEmpty ? k.label : '${k.label} — بحث «$s»',
                withSearch: false),
          );
        });
      },
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
      if (e.value.isEmpty) continue;
      final names = [for (final id in e.value) _nameOf(e.key, id, manager: false)].join('، ');
      out.add(RpChip('${e.value.length > 1 ? 'الموظّفون' : 'الموظّف'}: $names${_groupName(e.key)}', onRemove: () {
        final m = {...f.employees}..remove(e.key);
        _apply(f.copyWith(employees: m));
      }));
    }
    if (f.types.isNotEmpty) {
      out.add(RpChip('النوع: ${[for (final t in f.types) ActivityLogView.typeLabel(t)].join('، ')}',
          onRemove: () => _apply(f.copyWith(types: const []))));
    }
    return out;
  }

  // ═══════════════ «قسّم حسب» ═══════════════

  List<String> get _tabs => [if (_merged) 'الشركة', 'النوع', 'المدير', 'الموظّف', 'اليوم'];

  List<RpShare> _breakdown(({List<ActivityRow> rows, Map<ActivityRow, String?> co, bool complete}) v) {
    final tab = _tabs[_tab.clamp(0, _tabs.length - 1)];
    RpCompany? co(ActivityRow r) => _merged ? _coOf(r, v.co) : null;
    switch (tab) {
      case 'الشركة':
        return ActivityLogView.shares(v.rows, (r) => _coOf(r, v.co)?.name ?? '—', companyOf: co);
      case 'النوع':
        return ActivityLogView.shares(v.rows, (r) => arabicActionLabel(r.actionType, r.actionDescription ?? ''));
      case 'المدير':
        return ActivityLogView.shares(v.rows, (r) => (r.adminUsername ?? '—').trim(), companyOf: co);
      case 'الموظّف':
        return ActivityLogView.shares(
            v.rows,
            (r) => (r.actingEmployeeFullName ?? '').trim().isNotEmpty ? r.actingEmployeeFullName!.trim() : 'المدير نفسه',
            companyOf: co);
      default:
        return ActivityLogView.shares(v.rows, (r) {
          final t = ActivityLogView.timeOf(r);
          return t == null ? '—' : iqDateOf(t);
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return ReportPermissionGate(
      permission: _perm,
      title: 'reports.activity_log'.tr(),
      child: Scaffold(
        backgroundColor: AppColors.bg,
        appBar: deskPageBar(
          context,
          mobile: AppBar(
            backgroundColor: AppColors.surface,
            elevation: 0,
            scrolledUnderElevation: 0,
            title: Text(
              _merged ? 'سجلّ الحركات · كل الشركات' : 'reports.activity_log'.tr(),
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
      // سجلّ تدقيق: لا مقارنة (أعدادٌ لا أداء) — الفترة و«الفلاتر» بسطرٍ واحد (المالك ٢٢ نوفمبر)، وشاراتها تحته
      RpHeader(
        period: RpPeriod(name: f.range.name, range: f.range.rangeText),
        onPeriod: _openFilters,
        chips: _chips(),
        onFilters: _openFilters,
        onClear: () => _apply(f.cleared()),
      ),
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
          child: Center(child: Text('جارٍ قراءة سجلّات الشركات…', style: AppType.muted(color: AppColors.textMid))),
        ));
      }
      return _gapped(parts);
    }
    parts.add(RpKpiGrid(kpis: ActivityLogView.kpis(v.rows), compareWith: '', onTap: (k) => _drill(k, v)));
    if (_merged) {
      parts.add(Text('الصرفيّات لا تُخلط هنا — تظهر في سجلّ كلّ شركةٍ حين تُفتح وحدها',
          style: AppType.micro(color: AppColors.textMid), maxLines: 2));
    }
    if (_elEmployeeFilter) parts.add(Text(_elNote, style: AppType.micro(color: AppColors.textMid), maxLines: 2));
    // «يوماً بيوم» أُلغي من كلّ التقارير (المالك ٢٢ نوفمبر: «كراف يوماً بيوم من جميع التقارير حذفه»)
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
    final rows = ActivityLogView.search(v.rows, _q);
    parts.add(RpRowsCard(
      fold: _fold('rows'),
      query: _q,
      total: rows.length,
      days: ActivityLogView.days(rows, companyOf: _merged ? (r) => _coOf(r, v.co) : null, limit: _visible),
      more: rows.length > _visible ? 'عرض المزيد (${rows.length - _visible})' : null,
      onMore: () => setState(() => _visible += _page),
      onSearch: (q) => setState(() {
        _q = q;
        _visible = _page;
      }),
      note: v.complete ? null : 'الفترة طويلة جدّاً — لم تُجلب كلّ حركاتها، فالأعداد قد تنقص',
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
        final rows = ActivityLogView.filter(co.rows!, _f!.types);
        final k = {for (final x in ActivityLogView.kpis(rows)) x.id: x.value};
        lines.add(RpCompanyLine(company: _rp(co.c), a: k[LogKpiIds.subs], b: k[LogKpiIds.debts], c: k[LogKpiIds.all]));
      }
    }
    final inc = [
      for (final l in lines)
        if (l.state == RpCompanyState.ok) l,
    ];
    return RpCompanyTable(
      fold: _fold('companies'),
      heads: const ['تفعيل وتمديد', 'تسديد وديون', 'الحركات'],
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
