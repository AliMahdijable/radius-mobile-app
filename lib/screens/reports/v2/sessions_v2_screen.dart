import 'dart:async';
import 'dart:collection';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../api/company_route.dart';
import '../../../api/merged_dashboard_api.dart';
import '../../../api/reports_api.dart';
import '../../../core/util/ar_date.dart';
import '../../../core/util/server_time.dart';
import '../../../core/widgets/design_sheet.dart';
import '../../../models/merged_company.dart';
import '../../../services/merged_mode.dart';
import '../../../services/permissions_service.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';
import '../../desktop/desk_widgets.dart';
import '../widgets/report_export.dart';
import '../widgets/report_permission_gate.dart';
import 'report_kit.dart';
import 'report_prefs.dart';

/// «الجلسات» على الشكل الموحّد (٢٢ نوفمبر — «كمل بقية التقارير»): المتّصلون الآن أو سجلّ الجلسات من الساس (أحدث 2000 صفّ —
/// الساس لا يعطي سجلّاً بفترة)، البحث باليوزر/IP/MAC من الخادم، والشركات و«حسب الشركة»، والأعداد والأحجام، و«قسّم حسب» المدير/اليوم،
/// والجلسات يوماً يوماً، والتصدير بالفلاتر حرفاً و«ناقص» عند 2000. [initialUsername] = «سجلّ الجلسات» من نافذة مشتركٍ بشركته.
class SessionsV2Screen extends StatefulWidget {
  const SessionsV2Screen({super.key, this.initialUsername, this.companyKey});

  final String? initialUsername;

  /// «كل الشركات»: سجلّ مشتركٍ من شركةٍ غير المفتوحة — يُطلب من شركته (موجَّهاً).
  final String? companyKey;

  @override
  State<SessionsV2Screen> createState() => _SessionsV2State();
}

typedef _Res = ({bool ok, List<SessionRow> rows, String? error, String? note});

class _Co {
  _Co(this.c, {this.rows, this.reason, this.loading = false, this.note});
  final MergedCompany c;
  List<SessionRow>? rows;
  String? reason;
  String? note;
  bool loading;

  bool get included => !loading && rows != null && reason == null;
}

class _SessionsV2State extends State<SessionsV2Screen> {
  static const _perm = 'reports.sessions';
  static const _cap = 2000;
  static const _page = 40;

  bool _online = true;
  String _field = 'username'; // username · ip · mac
  String _value = '';
  final _searchCtrl = TextEditingController();
  String? _manager; // مدير المشترك (من الصفوف)

  List<SessionRow>? _rows;
  String? _note;
  bool _loading = true;
  String? _error;
  int _seq = 0;
  final _cos = <String, _Co>{};
  final Set<String> _companies = {};

  int _tab = 0;
  bool _tabAll = false;
  int _visible = _page;

  bool get _merged => MergedMode.active.value && widget.initialUsername == null;

  /// الأقسام الفرعيّة المطويّة (المالك ٢٢ نوفمبر: «المهمّات تظهر والفرعيّة هو ينقر عليها ويظهرها»).
  late final _folds = RpFolds('sessions', const {'rows': true});
  RpFold _fold(String s) => _folds.fold(s, setState);

  @override
  void initState() {
    super.initState();
    unawaited(_folds.load().then((_) {
      if (mounted) setState(() {});
    }));
    final u = widget.initialUsername?.trim() ?? '';
    if (u.isNotEmpty) {
      _online = false;
      _value = u;
      _searchCtrl.text = u;
    }
    MergedMode.active.addListener(_onMerged);
    PermissionsService.changes.addListener(_onPerms);
    _loadIfAllowed();
  }

  @override
  void dispose() {
    MergedMode.active.removeListener(_onMerged);
    PermissionsService.changes.removeListener(_onPerms);
    _searchCtrl.dispose();
    super.dispose();
  }

  bool _requested = false;

  void _onPerms() {
    if (mounted && !_requested) _loadIfAllowed();
  }

  void _onMerged() {
    if (!mounted) return;
    setState(() {
      _rows = null;
      _cos.clear();
      _tab = 0;
    });
    if (_requested) _load();
  }

  void _loadIfAllowed() {
    if (!Perms.has(_perm) && widget.companyKey == null) return;
    _requested = true;
    _load();
  }

  Future<_Res> _fetch() => ReportsApi.sessions(
        onlineOnly: _online,
        limit: _cap,
        username: _field == 'username' && _value.isNotEmpty ? _value : null,
        ip: _field == 'ip' && _value.isNotEmpty ? _value : null,
        mac: _field == 'mac' && _value.isNotEmpty ? _value : null,
      );

  static bool _serves(MergedCompany c) => c.provider == MergedProvider.sas4 || c.provider == MergedProvider.earthlink;

  List<MergedCompany> get _countable => MergedDashboardApi.countable();

  Future<void> _load() async {
    final seq = ++_seq;
    if (_merged) {
      final cs = _companies.isEmpty ? _countable : _countable.where((c) => _companies.contains(c.key)).toList();
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
            if (!_serves(c)) {
              setState(() => _cos[c.key] = _Co(c, reason: 'لا جلساتٍ تُقرأ لنوعها من هنا'));
              return;
            }
            if (MergedMode.pagePermAny(c.key, const [_perm]) == false) {
              setState(() => _cos[c.key] = _Co(c, reason: MergedMode.noAccess('جلساتها')));
              return;
            }
            final r = await CompanyRoute.run(c.key, _fetch);
            if (!mounted || seq != _seq) return;
            setState(() => _cos[c.key] = _Co(c, rows: r.ok ? r.rows : null, reason: r.ok ? null : (r.error ?? 'تعذّرت القراءة'), note: r.note));
          })(),
      ]);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    final r = await CompanyRoute.run(widget.companyKey, _fetch);
    if (!mounted || seq != _seq || _merged) return;
    setState(() {
      _loading = false;
      _rows = r.ok ? r.rows : null;
      _note = r.ok ? r.note : null;
      _error = r.ok ? null : (r.error ?? 'common.load_failed'.tr());
      _visible = _page;
    });
  }

  // ═══════════════ ما يُرسم ═══════════════

  static int _ms(SessionRow s) => parseSasLocal((s.startedAt ?? '').trim())?.millisecondsSinceEpoch ?? 0;

  ({List<SessionRow> rows, Map<SessionRow, String?> co, bool capped})? _view() {
    bool keep(SessionRow s) => _manager == null || s.userManager == _manager;
    if (!_merged) {
      final r = _rows;
      if (r == null) return null;
      return (rows: r.where(keep).toList(), co: LinkedHashMap<SessionRow, String?>.identity(), capped: r.length >= _cap);
    }
    final inc = [
      for (final co in _cos.values)
        if (co.included) co,
    ];
    if (inc.isEmpty) return null;
    final tagged = <({SessionRow s, String key, int at, int order})>[];
    var order = 0;
    for (final co in inc) {
      for (final s in co.rows!) {
        tagged.add((s: s, key: co.c.key, at: _ms(s), order: order++));
      }
    }
    tagged.sort((a, b) => a.at != b.at ? b.at.compareTo(a.at) : a.order.compareTo(b.order));
    final map = LinkedHashMap<SessionRow, String?>.identity();
    for (final t in tagged) {
      map[t.s] = t.key;
    }
    return (rows: [for (final t in tagged) if (keep(t.s)) t.s], co: map, capped: inc.any((co) => co.rows!.length >= _cap));
  }

  RpCompany _rp(MergedCompany c, {bool selected = true, String? note}) =>
      RpCompany(key: c.key, name: c.name, colorIndex: c.colorIndex, selected: selected, note: note);

  RpCompany? _coOf(SessionRow s, Map<SessionRow, String?> co) {
    final key = co[s];
    final c = key == null ? null : _cos[key];
    return c == null ? null : _rp(c.c);
  }

  static String bytes(num b) {
    if (b < 1024) return '${b.round()} B';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} KB';
    if (b < 1024 * 1024 * 1024) return '${(b / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(b / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  RpRow _row(SessionRow s, {RpCompany? company}) {
    final t = parseSasLocal((s.startedAt ?? '').trim());
    return RpRow(
      icon: s.isOnline ? LucideIcons.wifi : LucideIcons.wifiOff,
      tone: s.isOnline ? RpTone.money : RpTone.neutral,
      title: s.username ?? '—',
      detail: [
        if ((s.ipAddress ?? '').isNotEmpty) s.ipAddress!,
        if ((s.mac ?? '').isNotEmpty) s.mac!,
        if ((s.userManager ?? '').isNotEmpty) s.userManager!,
      ].join(' · '),
      amount: null,
      trailing: s.bytesIn > 0 || s.bytesOut > 0 ? '↓${bytes(s.bytesIn)}  ↑${bytes(s.bytesOut)}' : null,
      time: t == null ? '' : clock12Ar(t),
      company: company,
    );
  }

  List<RpDay> _days(List<SessionRow> rows, Map<SessionRow, String?> co, {int? limit}) {
    final byDay = <String, List<SessionRow>>{};
    final order = <String>[];
    for (final s in rows) {
      final t = parseSasLocal((s.startedAt ?? '').trim());
      final key = t == null ? '' : iqDateOf(t);
      if (!byDay.containsKey(key)) order.add(key);
      (byDay[key] ??= []).add(s);
    }
    final out = <RpDay>[];
    var left = limit ?? 1 << 30;
    for (final k in order) {
      if (left <= 0) break;
      final all = byDay[k]!;
      final shown = all.take(left).toList();
      left -= shown.length;
      out.add(RpDay(
        date: k.isEmpty ? 'بلا تاريخ' : k,
        count: all.length,
        sum: 0,
        rows: [for (final s in shown) _row(s, company: _merged ? _coOf(s, co) : null)],
      ));
    }
    return out;
  }

  List<RpShare> _shares(List<SessionRow> rows, String Function(SessionRow) keyOf) {
    final acc = <String, int>{};
    for (final s in rows) {
      acc[keyOf(s)] = (acc[keyOf(s)] ?? 0) + 1;
    }
    final total = rows.length;
    final list = acc.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return [for (final e in list) RpShare(name: e.key, amount: 0, count: e.value, share: total == 0 ? 0 : e.value / total)];
  }

  List<String> get _tabs => [if (_merged) 'الشركة', 'المدير', if (!_online) 'اليوم'];

  // ═══════════════ التصدير ═══════════════

  List<String> _details(int count, bool capped) {
    final inc = [for (final co in _cos.values) if (co.included) co.c.name];
    final out = [for (final co in _cos.values) if (!co.included) '${co.c.name} (${co.reason ?? 'تعذّرت'})'];
    return [
      _online ? 'المتّصلون الآن' : 'سجلّ الجلسات',
      if (_merged) 'الشركات: ${inc.join('، ')}',
      if (_merged && out.isNotEmpty) 'خارج الملفّ: ${out.join('، ')}',
      if (_value.trim().isNotEmpty) 'بحث (${_field == 'ip' ? 'IP' : (_field == 'mac' ? 'MAC' : 'اليوزر')}): «${_value.trim()}»',
      if (_manager != null) 'مدير المشترك: $_manager',
      'عدد الصفوف: $count',
      if (!_online && _note != null) 'ملاحظة: $_note',
      if (capped) 'ناقص: بلغ الحدّ ($_cap صفّ من الساس) — ضيّق البحث لترى الباقي',
    ];
  }

  Future<void> _export(String how) async {
    final v = _view();
    if (v == null || (_merged ? _cos.values.any((c) => c.loading) : _loading)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('انتظر حتى تكتمل الجلسات ثمّ صدّر')));
      return;
    }
    final rows = [
      for (final s in v.rows)
        [
          if (_merged) MergedMode.companyOf(v.co[s])?.name ?? '',
          s.username ?? '',
          s.ipAddress ?? '',
          s.mac ?? '',
          s.userManager ?? '',
          bytes(s.bytesIn),
          bytes(s.bytesOut),
          exportLocalAr(s.startedAt),
          exportLocalAr(s.endedAt),
          s.isOnline ? 'subscribers.status_online'.tr() : 'subscribers.status_expired'.tr(),
        ],
    ];
    final columns = [
      if (_merged) 'الشركة',
      'reports.col_username'.tr(),
      'IP',
      'MAC',
      'reports.col_manager'.tr(),
      'subscribers.label_download'.tr(),
      'subscribers.label_upload'.tr(),
      'reports.col_start'.tr(),
      'reports.col_end'.tr(),
      'subscribers.status'.tr(),
    ];
    final title = _online ? 'reports.online_sessions'.tr() : 'reports.all_sessions'.tr();
    final details = _details(rows.length, v.capped);
    final base = _online ? 'sessions_online' : 'sessions_all';
    switch (how) {
      case 'pdf':
        return ReportExportActions.pdf(context, title: title, details: details, columns: columns, rows: rows, fileNameBase: base);
      case 'excel':
        return ReportExportActions.csv(context, title: title, details: details, columns: columns, rows: rows, fileNameBase: base);
      default:
        return ReportExportActions.sharePdf(context, title: title, details: details, columns: columns, rows: rows, fileNameBase: base);
    }
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return ReportPermissionGate(
      permission: _perm,
      title: 'reports.sessions'.tr(),
      companyKey: widget.companyKey,
      child: Scaffold(
        backgroundColor: AppColors.bg,
        appBar: deskPageBar(
          context,
          mobile: AppBar(
            backgroundColor: AppColors.surface,
            elevation: 0,
            scrolledUnderElevation: 0,
            title: Text(
              widget.initialUsername != null
                  ? 'سجلّ جلسات ${widget.initialUsername}'
                  : (_merged ? 'الجلسات · كل الشركات' : 'reports.sessions'.tr()),
              style: AppType.title(color: AppColors.textHi).copyWith(fontSize: 16),
            ),
            iconTheme: IconThemeData(color: AppColors.textHi),
          ),
        ),
        body: SafeArea(
          child: RefreshIndicator(
            onRefresh: _load,
            color: AppColors.brand,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, Sp.huge),
              children: _parts(),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _parts() {
    final parts = <Widget>[
      SheetSegmented(
        labels: const ['المتّصلون الآن', 'سجلّ الجلسات'],
        selectedIndex: _online ? 0 : 1,
        onSelect: (i) {
          if ((i == 0) == _online) return;
          setState(() {
            _online = i == 0;
            _tab = 0;
            _manager = null;
          });
          _load();
        },
      ),
      _searchBox(),
    ];
    if (_merged) {
      parts.add(RpCompanyChips(
        companies: [for (final c in _countable) _rp(c, selected: _companies.contains(c.key))],
        allSelected: _companies.isEmpty,
        onAll: () {
          setState(_companies.clear);
          _load();
        },
        onToggle: (c) {
          setState(() => _companies.contains(c.key) ? _companies.remove(c.key) : _companies.add(c.key));
          if (_companies.length == _countable.length) _companies.clear();
          _load();
        },
      ));
    }
    if (_manager != null) {
      parts.add(RpFilterBar(chips: [RpChip('مدير المشترك: $_manager', onRemove: () => setState(() => _manager = null))]));
    }
    if (_merged) parts.add(_companyTable());
    if (!_merged && _loading && _rows == null) {
      parts.add(const Padding(padding: EdgeInsets.symmetric(vertical: Sp.huge), child: Center(child: CircularProgressIndicator())));
      return _gapped(parts);
    }
    if (!_merged && _rows == null) {
      parts.add(RpCard(
        child: Column(children: [
          Icon(LucideIcons.triangleAlert, size: 28, color: AppColors.error),
          const SizedBox(height: Sp.sm),
          Text(_error ?? 'common.load_failed'.tr(), textAlign: TextAlign.center, style: AppType.body(color: AppColors.textMid)),
          const SizedBox(height: Sp.md),
          OutlinedButton.icon(onPressed: _load, icon: const Icon(LucideIcons.refreshCw, size: 16), label: Text('common.retry'.tr())),
        ]),
      ));
      return _gapped(parts);
    }
    final v = _view();
    if (v == null) {
      if (_merged && _cos.values.any((c) => c.loading)) {
        parts.add(Padding(
          padding: const EdgeInsets.symmetric(vertical: Sp.xl),
          child: Center(child: Text('جارٍ قراءة جلسات الشركات…', style: AppType.muted(color: AppColors.textMid))),
        ));
      }
      return _gapped(parts);
    }
    final users = {for (final s in v.rows) s.username ?? ''}..remove('');
    final down = v.rows.fold<num>(0, (a, s) => a + s.bytesIn);
    final up = v.rows.fold<num>(0, (a, s) => a + s.bytesOut);
    parts.add(RpKpiGrid(compareWith: '', kpis: [
      RpKpi(label: _online ? 'المتّصلون' : 'الجلسات', value: v.rows.length, isCount: true, icon: LucideIcons.wifi, tone: RpTone.brand),
      RpKpi(label: 'المشتركون', value: users.length, isCount: true, icon: LucideIcons.users, tone: RpTone.info),
      RpKpi(label: 'التحميل', value: down, display: bytes(down), icon: LucideIcons.download, tone: RpTone.money),
      RpKpi(label: 'الرفع', value: up, display: bytes(up), icon: LucideIcons.upload, tone: RpTone.neutral),
    ]));
    if (!_online && _note != null) {
      parts.add(Text(_note!, style: AppType.micro(color: AppColors.textMid), maxLines: 3));
    }
    final tab = _tabs[_tab.clamp(0, _tabs.length - 1)];
    final shares = switch (tab) {
      'الشركة' => _shares(v.rows, (s) => _coOf(s, v.co)?.name ?? '—'),
      'المدير' => _shares(v.rows, (s) => (s.userManager ?? '').trim().isEmpty ? '—' : s.userManager!.trim()),
      _ => _shares(v.rows, (s) {
          final t = parseSasLocal((s.startedAt ?? '').trim());
          return t == null ? '—' : iqDateOf(t);
        }),
    };
    final cap = _tabAll ? shares.length : 6;
    parts.add(RpBreakdownCard(
      fold: _fold('breakdown'),
      tabs: _tabs,
      selected: _tab.clamp(0, _tabs.length - 1),
      tone: RpTone.brand,
      countOnly: true,
      unit: _online ? 'متّصل' : 'جلسة',
      shares: shares.take(cap).toList(),
      onTab: (i) => setState(() {
        _tab = i;
        _tabAll = false;
      }),
      more: shares.length > cap ? 'عرض الكلّ (${shares.length})' : null,
      onMore: () => setState(() => _tabAll = true),
    ));
    if (tab == 'المدير' && shares.isNotEmpty && _manager == null) {
      parts.add(Wrap(spacing: Sp.sm, runSpacing: Sp.sm, children: [
        for (final s in shares.take(8))
          if (s.name != '—') SheetQuickChip(label: 'حصر بـ${s.name}', selected: false, onTap: () => setState(() => _manager = s.name)),
      ]));
    }
    parts.add(RpRowsCard(
      fold: _fold('rows'),
      total: v.rows.length,
      days: _days(v.rows, v.co, limit: _visible),
      more: v.rows.length > _visible ? 'عرض المزيد (${v.rows.length - _visible})' : null,
      onMore: () => setState(() => _visible += _page),
      note: v.capped ? 'بلغ الحدّ ($_cap صفّ من الساس) — ضيّق البحث لترى الباقي' : null,
      empty: _online ? 'لا متّصلين الآن' : 'لا جلسات',
    ));
    parts.add(RpExportBar(onPdf: () => _export('pdf'), onExcel: () => _export('excel'), onShare: () => _export('share')));
    return _gapped(parts);
  }

  Widget _searchBox() {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _searchCtrl,
            textInputAction: TextInputAction.search,
            onSubmitted: (v) {
              setState(() => _value = v.trim());
              _load();
            },
            decoration: InputDecoration(
              isDense: true,
              hintText: _field == 'ip' ? 'ابحث بالـIP' : (_field == 'mac' ? 'ابحث بالـMAC' : 'ابحث باليوزر'),
              prefixIcon: const Icon(LucideIcons.search, size: 18),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(R.md)),
            ),
          ),
        ),
        const SizedBox(width: Sp.sm),
        DropdownButton<String>(
          value: _field,
          underline: const SizedBox.shrink(),
          items: const [
            DropdownMenuItem(value: 'username', child: Text('يوزر')),
            DropdownMenuItem(value: 'ip', child: Text('IP')),
            DropdownMenuItem(value: 'mac', child: Text('MAC')),
          ],
          onChanged: (f) => setState(() => _field = f ?? 'username'),
        ),
      ],
    );
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
        final r = co.rows!;
        lines.add(RpCompanyLine(
          company: _rp(co.c),
          a: r.length,
          b: {for (final s in r) s.username ?? ''}.where((u) => u.isNotEmpty).length,
          c: r.where((s) => s.isOnline).length,
        ));
      }
    }
    final inc = [for (final l in lines) if (l.state == RpCompanyState.ok) l];
    return RpCompanyTable(
      fold: _fold('companies'),
      heads: const ['الجلسات', 'المشتركون', 'متّصل'],
      lines: lines,
      total: [
        inc.fold<num>(0, (a, l) => a + (l.a ?? 0)),
        inc.fold<num>(0, (a, l) => a + (l.b ?? 0)),
        inc.fold<num>(0, (a, l) => a + (l.c ?? 0)),
      ],
      outside: outside.isEmpty ? null : 'خارج المجموع الآن: ${outside.join(' · ')}',
      onTap: (c) {
        setState(() => _companies
          ..clear()
          ..add(c.key));
        _load();
      },
      onRetry: (c) => _load(),
    );
  }
}
