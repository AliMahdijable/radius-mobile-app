import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../api/company_route.dart';
import '../../../api/merged_dashboard_api.dart';
import '../../../api/package_report_api.dart';
import '../../../api/report_people_api.dart';
import '../../../core/util/format.dart';
import '../../../core/widgets/design_sheet.dart';
import '../../../models/merged_company.dart';
import '../../../services/merged_mode.dart';
import '../../../services/merged_text.dart';
import '../../../services/permissions_service.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';
import '../../desktop/desk_widgets.dart';
import '../package_distribution_screen.dart' show packagePartText;
import '../widgets/report_export.dart';
import '../widgets/report_permission_gate.dart';
import '../widgets/scope_helper.dart';
import 'package_dist_view.dart';
import 'report_kit.dart';
import 'report_period.dart';
import 'report_prefs.dart';
import 'report_sheets.dart';

/// «توزيع الباقات والأرباح» على الشكل الموحّد (٢٢ نوفمبر — «اكمل كلشي»): الفترة (آخر 30 يوماً أوّل مرّة — كبطاقة الرئيسيّة) ←
/// الشركات ← الفلاتر (الموظّف المنفِّذ لكلّ شركة) ← «حسب الشركة» ← «الإيراد» ← المشتركون والتفعيلات (ولصاحب الحساب الربحان) ←
/// «الباقات» حسب المشتركين/الحركة/الإيراد/الربح، ولمسة باقةٍ تفتح أرقامها كلّها ← التصدير بالفلاتر حرفاً وكاملاً.
/// القواعد في [PackageDistView] منقولةٌ من الشاشة السابقة: الإيراد بالدينار وحده، والربح مجموع ربح كلّ شركةٍ بقاعدتها، ومن لا يُعرف
/// رقمها تُسمّى («لا يشمل»). التنبيهات الزرقاء تُخفى بـ× ولا تعود (المالك ٢٥ أكتوبر) — بالمفتاح نفسه، فما أُخفي قبلُ يبقى مخفيّاً.
class PackageDistV2Screen extends StatefulWidget {
  const PackageDistV2Screen({super.key, this.initialPreset});

  /// فترةٌ لهذا الفتح وحده (لا تُحفظ): بطاقة الرئيسيّة تفتحه على «آخر 30 يوماً» فالرقمان واحد.
  final RpPreset? initialPreset;

  @visibleForTesting
  static DateTime Function() clock = DateTime.now;

  @override
  State<PackageDistV2Screen> createState() => _PackageDistV2State();
}

class _Co {
  _Co(this.c, {this.data, this.reason, this.loading = false, this.unsupported = false});
  final MergedCompany? c; // null = المفتوحة
  final PackageReport? data;
  final String? reason;
  final bool loading;
  final bool unsupported;

  bool get ok => !loading && data != null && reason == null;
}

class _PackageDistV2State extends State<PackageDistV2Screen> {
  static const _id = 'packages';
  // «توزيع الباقات» بمفتاحه منذ ٢٥ أكتوبر (كان «تقرير مالي») — الخادم يفرضه (54b6dba).
  static const _perm = 'reports.packages';
  static const _open = RpPrefs.openGroup;
  static const _unsupported = 'لا تقرير باقاتٍ لنوعها';
  static const _hintsKey = 'pkg_report_dismissed_hints';
  static const _cap = 8;

  RpFilterValue? _f;
  String? _openTag;
  bool _requested = false;
  int _seq = 0;
  final _cos = <String, _Co>{};
  final _people = <String, ({List<RpPerson>? managers, List<RpPerson>? employees})>{};
  List<String>? _scopeIds;
  int _tab = 0;
  bool _tabAll = false;
  Set<String> _dismissed = {};
  VoidCallback? _sheetRefresh;

  bool get _merged => MergedMode.active.value;
  DateTime get _now => PackageDistV2Screen.clock();

  @override
  void initState() {
    super.initState();
    PermissionsService.changes.addListener(_onPerms);
    MergedMode.active.addListener(_onMerged);
    unawaited(_start());
    unawaited(_loadDismissed());
  }

  @override
  void dispose() {
    PermissionsService.changes.removeListener(_onPerms);
    MergedMode.active.removeListener(_onMerged);
    super.dispose();
  }

  Future<void> _start() async {
    _openTag = await MergedMode.openAdminId();
    var f = await RpPrefs.load(_id, now: _now, openTag: _openTag, fallback: RpPreset.last30);
    if (!mounted) return;
    if (widget.initialPreset case final p?) f = f.copyWith(range: RpRange.of(p, now: _now));
    // مقارنةٌ ونوعٌ ومدير لا معنى لها هنا: الموظّف وحده (والنطاق من الخادم)
    setState(() => _f = f.copyWith(compare: false, managers: const {}, types: const []));
    _loadIfAllowed();
  }

  /// المقفل لا يطلب (الخادم يردّ ٤٠٣ خلف «لا صلاحيّة»)؛ وصلاحيّةٌ تصل والشاشة مفتوحة تطلبه حينها.
  void _loadIfAllowed() {
    if (_requested || _f == null || !Perms.has(_perm)) return;
    _requested = true;
    _load();
  }

  void _onPerms() {
    if (mounted) _loadIfAllowed();
  }

  void _onMerged() {
    if (!mounted || _f == null) return;
    setState(() {
      _cos.clear();
      _tab = 0;
      _tabAll = false;
    });
    if (_requested) _load();
  }

  Future<void> _loadDismissed() async {
    try {
      final p = await SharedPreferences.getInstance();
      final v = p.getStringList(_hintsKey) ?? const [];
      if (mounted && v.isNotEmpty) setState(() => _dismissed = v.toSet());
    } catch (_) {/* تبقى ظاهرة */}
  }

  Future<void> _dismiss(String hint) async {
    setState(() => _dismissed = {..._dismissed, hint});
    try {
      final p = await SharedPreferences.getInstance();
      await p.setStringList(_hintsKey, _dismissed.toList());
    } catch (_) {/* أُخفيت لهذه الجلسة على الأقلّ */}
  }

  void _apply(RpFilterValue v) {
    final f = v.copyWith(compare: false, managers: const {}, types: const []);
    setState(() {
      _f = f;
      _tabAll = false;
    });
    unawaited(RpPrefs.save(_id, f, openTag: _openTag));
    _load();
  }

  int? _employeeId(String group) => int.tryParse(_f!.employees[group] ?? '');

  List<MergedCompany> get _countable => MergedDashboardApi.countable();

  List<MergedCompany> get _picked {
    final all = _countable;
    final sel = _f!.companies;
    final picked = sel.isEmpty ? all : all.where((c) => sel.contains(c.key)).toList();
    return picked.isEmpty ? all : picked;
  }

  static bool _supports(MergedCompany c) => c.provider != MergedProvider.ftth && c.provider != MergedProvider.fiberx;

  Future<void> _load() async {
    final seq = ++_seq;
    final f = _f!;
    // موظّفٌ محفوظ ⇒ اسمه للشارة ورأس الملفّ (بالخلفيّة — لا يؤخّر التقرير)
    if (f.employees.isNotEmpty) unawaited(_loadPeople([for (final k in f.employees.keys) k == _open ? null : k]));
    if (!_merged) {
      setState(() {
        _cos
          ..clear()
          ..[_open] = _Co(null, loading: true);
      });
      _scopeIds ??= await loadScopeUserIds();
      if (!mounted || seq != _seq || _merged) return;
      // للمفتوحة صراحةً، بنطاق تقارير التطبيق (المدير المسجّل) كالشاشة السابقة
      final r = await CompanyRoute.runOpen(() => PackageReportApi.fetch(
            from: f.range.from,
            to: f.range.to,
            userIds: _scopeIds,
            employeeId: _employeeId(_open),
          ));
      if (!mounted || seq != _seq || _merged) return;
      setState(() => _cos[_open] = _Co(null, data: r.data, reason: r.data == null ? (r.error ?? 'pkgdist.fetch_failed'.tr()) : null));
      return;
    }
    final cs = _picked;
    setState(() {
      _cos.clear();
      for (final c in cs) {
        _cos[c.key] = _Co(c, loading: true);
      }
    });
    // اثنتين اثنتين كالشاشة السابقة — عدّ مشتركي كلّ باقة ثقيلٌ على الخادم أوّل مرّة
    var next = 0;
    Future<void> worker() async {
      while (next < cs.length) {
        final c = cs[next++];
        await _loadCo(c, seq);
        if (!mounted || seq != _seq) return;
      }
    }

    await Future.wait([for (var w = 0; w < 2 && w < cs.length; w++) worker()]);
  }

  Future<void> _loadCo(MergedCompany c, int seq) async {
    if (!_supports(c)) {
      setState(() => _cos[c.key] = _Co(c, reason: _unsupported, unsupported: true));
      return;
    }
    if (MergedMode.pagePermAny(c.key, const [_perm]) == false) {
      setState(() => _cos[c.key] = _Co(c, reason: MergedMode.noAccess('تقرير باقاتها')));
      return;
    }
    final f = _f!;
    // كلّ شركةٍ بنطاقها هي (معرّف مديرها) — طلبٌ موجَّه لها
    final r = await CompanyRoute.run(c.key, () => PackageReportApi.fetch(
          from: f.range.from,
          to: f.range.to,
          userIds: [c.adminId],
          employeeId: _employeeId(c.key),
        ));
    if (!mounted || seq != _seq) return;
    setState(() => _cos[c.key] = _Co(c, data: r.data, reason: r.data == null ? (r.error ?? 'pkgdist.fetch_failed'.tr()) : null));
  }

  void _retry(String key) {
    final co = _cos[key];
    if (co == null || co.c == null) return;
    setState(() => _cos[key] = _Co(co.c, loading: true));
    unawaited(_loadCo(co.c!, _seq));
  }

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

  // ═══════════════ ما يُرسم ═══════════════

  List<_Co> get _ok => [for (final co in _cos.values) if (co.ok) co];

  List<PkgPart> get _parts => [
        for (final co in _ok)
          PkgPart(report: co.data!, key: co.c?.key, name: co.c?.name, currency: co.c == null ? 'IQD' : co.c!.currency),
      ];

  /// شركاتٌ تعذّرت (لا غير المدعومة) — تُسمّى خارج كلّ مجموع.
  List<String> get _failed => [
        for (final co in _cos.values)
          if (!co.loading && !co.ok && !co.unsupported && co.c != null) co.c!.name,
      ];

  bool get _busy => _cos.isEmpty || _cos.values.any((c) => c.loading);

  RpCompany _rp(MergedCompany c, {bool selected = true, String? note}) =>
      RpCompany(key: c.key, name: c.name, colorIndex: c.colorIndex, selected: selected, note: note);

  RpCompany? _coOf(PkgPart p) {
    if (!_merged || p.key == null) return null;
    final c = _cos[p.key!]?.c;
    return c == null ? null : _rp(c);
  }

  String _nameOf(String group, String id) {
    for (final p in _people[group]?.employees ?? const <RpPerson>[]) {
      if (p.id == id) return p.name;
    }
    return 'موظّف';
  }

  String _groupName(String group) => group == _open ? '' : ' (${MergedMode.companyOf(group)?.name ?? ''})';

  List<RpChip> _chips() {
    final f = _f!;
    return [
      for (final e in f.employees.entries)
        RpChip('الموظّف: ${_nameOf(e.key, e.value)}${_groupName(e.key)}', onRemove: () {
          final m = {...f.employees}..remove(e.key);
          _apply(f.copyWith(employees: m));
        }),
    ];
  }

  List<PkgTab> _tabsOf(PkgTotals t) => [PkgTab.subscribers, PkgTab.moves, PkgTab.revenue, if (t.owner) PkgTab.profit];

  static String _tabLabel(PkgTab t) => switch (t) {
        PkgTab.subscribers => 'المشتركون',
        PkgTab.moves => 'الحركة',
        PkgTab.revenue => 'الإيراد',
        PkgTab.profit => 'الربح',
      };

  String _notIn(List<String> names) => 'لا يشمل: ${names.join('، ')}';

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
          subtitle: 'توزيع الباقات · ${f.range.name}',
          initial: f,
          now: _now,
          showCompare: false,
          showManagers: false,
          loadingPeople: keys.any((k) => !_people.containsKey(k ?? _open)),
          companies: merged ? [for (final c in _countable) _rp(c, selected: false)] : null,
          people: [
            for (final k in keys)
              RpPeopleGroup(
                key: k ?? _open,
                company: k == null ? null : _rp(MergedMode.companyOf(k)!, selected: false),
                employees: _people[k ?? _open]?.employees ?? const [],
                error: _people.containsKey(k ?? _open) && _people[k ?? _open]!.employees == null ? 'تعذّر جلب موظّفيها' : null,
              ),
          ],
          types: const [],
        );
      }),
    );
    unawaited(_loadPeople(keys).then((_) => _sheetRefresh?.call()));
    final v = await sheetFuture;
    _sheetRefresh = null;
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

  void _openPackage(PkgRow r) {
    final row = r.row;
    final owner = r.part.report.owner;
    final cur = r.part.iqd ? 'د.ع' : (r.part.currency ?? '');
    String money(num? v) => v == null ? '—' : '${rpNum(v)} $cur';
    final cells = <(String, String, RpTone)>[
      ('المشتركون الآن', PackageDistView.countText(row.subscribersTotal), RpTone.brand),
      ('الفعّالون', PackageDistView.countText(row.subscribersActive), RpTone.money),
      ('التفعيلات', formatIQD(row.activations), RpTone.info),
      ('التمديدات', formatIQD(row.extensions), RpTone.info),
      ('سعر البيع', money(row.price), RpTone.neutral),
      ('الإيراد', money(row.revenue), RpTone.money),
      if (owner) ...[
        ('كلفة الباقة', money(row.unitCost), RpTone.neutral),
        ('الكلفة', money(row.cost), RpTone.debt),
        ('الربح المتحقّق', money(row.profitTotal), (row.profitTotal ?? 0) < 0 ? RpTone.loss : RpTone.brand),
        ('الربح المقدَّر', money(row.profitEstimated), (row.profitEstimated ?? 0) < 0 ? RpTone.loss : RpTone.brand),
      ],
    ];
    final co = _coOf(r.part);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: AppColors.scrim,
      builder: (ctx) => DesignSheet(
        header: SheetHeaderBar(
          icon: LucideIcons.package,
          title: row.name,
          subtitle: [if (co != null) co.name, _f!.range.name].join(' · '),
          onClose: () => Navigator.of(ctx).maybePop(),
          tint: RpTone.brand.fg,
          tintBg: RpTone.brand.soft,
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            RpCard(
              child: LayoutBuilder(builder: (context, c) {
                final w = (c.maxWidth - Sp.md) / 2;
                return Wrap(
                  spacing: Sp.md,
                  runSpacing: Sp.md,
                  children: [
                    for (final cell in cells)
                      SizedBox(
                        width: w,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(cell.$1, style: AppType.micro(color: AppColors.textMid)),
                            RpFitText(cell.$2, style: AppType.rowValue(color: cell.$3 == RpTone.neutral ? AppColors.textHi : cell.$3.fg)),
                          ],
                        ),
                      ),
                  ],
                );
              }),
            ),
            if (row.isAggregate) ...[
              const SizedBox(height: Sp.md),
              Text(
                row.key == 'other' ? 'مجموع الباقات الصغيرة التي لم تُعرض وحدها' : 'حركاتٌ لم تُعرف باقتها',
                style: AppType.micro(color: AppColors.textMid),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ═══════════════ التصدير ═══════════════

  Future<void> _export(String how) async {
    if (_busy) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('انتظر حتى تكتمل الأرقام ثمّ صدّر')));
      return;
    }
    final parts = _parts;
    final t = PackageDistView.totals(parts, unread: _failed);
    final tabs = _tabsOf(t);
    final tab = tabs[_tab.clamp(0, tabs.length - 1)];
    // كلّ الباقات بترتيب التبويب المعروض — والإيراد/الربح بلا ما خارج المجموع (عملةٌ أخرى، ربحٌ غير معروف) يُلحق آخر الملفّ
    final all = PackageDistView.rows(parts);
    final shown = PackageDistView.ordered(all, tab);
    final rest = [for (final r in all) if (!shown.contains(r)) r];
    final owner = t.owner;
    String n(num? v) => v == null ? '' : '${v < 0 ? '-' : ''}${formatIQD(v)}';
    final rows = [
      for (final r in [...shown, ...rest])
        [
          if (_merged) r.part.name ?? '',
          r.row.name,
          PackageDistView.countText(r.row.subscribersTotal),
          PackageDistView.countText(r.row.subscribersActive),
          '${r.row.activations}',
          '${r.row.extensions}',
          n(r.row.price),
          n(r.row.revenue),
          if (owner) ...[
            r.part.report.owner ? n(r.row.unitCost) : '',
            r.part.report.owner ? n(r.row.cost) : '',
            r.part.report.owner ? n(r.row.profitTotal) : '',
            r.part.report.owner ? n(r.row.profitEstimated) : '',
          ],
        ],
    ];
    final columns = [
      if (_merged) 'merged.col_company'.trm(),
      'pkgdist.card_title'.tr(),
      'pkgdist.subscribers_now'.tr(),
      'pkgdist.active'.tr(),
      'pkgdist.activations'.tr(),
      'pkgdist.extensions'.tr(),
      'pkgdist.price'.tr(),
      'pkgdist.revenue'.tr(),
      if (owner) ...['pkgdist.unit_cost'.tr(), 'pkgdist.cost'.tr(), 'pkgdist.profit_total'.tr(), 'pkgdist.profit_est'.tr()],
    ];
    final f = _f!;
    final details = [
      if (_merged) 'الشركات: ${[for (final p in parts) p.name ?? ''].where((x) => x.isNotEmpty).join('، ')}',
      for (final c in _chips()) c.label,
      'الترتيب: ${_tabLabel(tab)}',
      'الإيراد: ${rpMoney(t.revenue)}${t.revenueOut.isEmpty ? '' : ' (${_notIn(t.revenueOut)})'}',
      if (owner && t.profit != null) 'الربح المتحقّق: ${n(t.profit)} د.ع${t.profitOut.isEmpty ? '' : ' (${_notIn(t.profitOut)})'}',
      'عدد الباقات: ${rows.length}',
      for (final w in _warnings(parts)) 'ناقص: $w',
    ];
    final title = 'pkgdist.title'.tr();
    final subtitle = '${f.range.name} · ${f.range.rangeText}';
    switch (how) {
      case 'pdf':
        return ReportExportActions.pdf(context,
            title: title, subtitle: subtitle, details: details, columns: columns, rows: rows, fileNameBase: 'package-distribution');
      case 'excel':
        return ReportExportActions.csv(context,
            title: title, subtitle: subtitle, details: details, columns: columns, rows: rows, fileNameBase: 'package-distribution');
      default:
        return ReportExportActions.sharePdf(context,
            title: title, subtitle: subtitle, details: details, columns: columns, rows: rows, fileNameBase: 'package-distribution');
    }
  }

  /// ما يُعرف أنّه ناقص — باسمه: شركةٌ تعذّرت، جزءٌ من تقريرٍ تعذّر، وقائمة مشتركين ناقصة ([screen]: للمفتوحة تنبيهٌ أزرق يُخفى
  /// كما كان، وفي الملفّ دائماً).
  List<String> _warnings(List<PkgPart> parts, {bool screen = false}) {
    String pre(PkgPart p) => p.name == null ? '' : '«${p.name}»: ';
    return [
      if (_failed.isNotEmpty) 'merged.not_in_sum'.trm(args: [_failed.map((n) => '«$n»').join('، ')]),
      for (final p in parts)
        for (final part in p.report.unavailableParts) '${pre(p)}${packagePartText(part)}',
      for (final p in parts)
        if (p.report.subscribersPartial && !(screen && p.key == null)) '${pre(p)}${'pkgdist.partial'.tr()}',
      for (final p in parts)
        if (!p.iqd) 'merged.not_in_sum'.trm(args: ['إيراد «${p.name}» وربحها (${p.currency ?? 'عملةٌ غير معروفة'})']),
    ];
  }

  // ═══════════════ البناء ═══════════════

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return ReportPermissionGate(
      permission: _perm,
      title: 'pkgdist.title'.tr(),
      child: Scaffold(
        backgroundColor: AppColors.bg,
        appBar: deskPageBar(
          context,
          mobile: AppBar(
            backgroundColor: AppColors.surface,
            elevation: 0,
            scrolledUnderElevation: 0,
            title: Text(_merged ? 'توزيع الباقات · كل الشركات' : 'pkgdist.title'.tr(),
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
                : ListView(padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, Sp.huge), children: _gapped(_body())),
          ),
        ),
      ),
    );
  }

  List<Widget> _gapped(List<Widget> parts) => [
        for (var i = 0; i < parts.length; i++) ...[if (i > 0) const SizedBox(height: Sp.md), parts[i]],
      ];

  List<Widget> _body() {
    final f = _f!;
    final out = <Widget>[
      RpPeriodBar(period: RpPeriod(name: f.range.name, range: f.range.rangeText), compareOn: false, compareWith: '', onPeriod: _openFilters),
    ];
    if (_merged) {
      final picked = {for (final c in _picked) c.key};
      out.add(RpCompanyChips(
        companies: [for (final c in _countable) _rp(c, selected: f.companies.isNotEmpty && picked.contains(c.key))],
        allSelected: f.companies.isEmpty,
        onAll: () => _apply(f.copyWith(companies: const {})),
        onToggle: _toggleCompany,
      ));
    }
    out.add(RpFilterBar(chips: _chips(), onOpen: _openFilters, onClear: () => _apply(f.cleared())));
    final parts = _parts;
    final t = PackageDistView.totals(parts, unread: _failed);
    if (_merged) {
      out.add(_companyTable(t));
      final none = [for (final co in _cos.values) if (co.unsupported && co.c != null) '«${co.c!.name}»'];
      if (none.isNotEmpty) out.add(Text('$_unsupported: ${none.join('، ')}', style: AppType.micro(color: AppColors.textLow)));
    }
    if (_busy && parts.isEmpty) {
      out
        ..add(const Padding(padding: EdgeInsets.symmetric(vertical: Sp.xl), child: Center(child: CircularProgressIndicator())))
        ..add(Center(child: Text('pkgdist.loading_counts'.tr(), style: AppType.micro(color: AppColors.textLow))));
      return out;
    }
    if (parts.isEmpty) {
      final single = _cos[_open];
      final reason = single?.reason ??
          (_cos.values.every((c) => c.unsupported) ? _unsupported : 'pkgdist.fetch_failed'.tr());
      out.add(RpCard(
        child: Column(children: [
          Icon(LucideIcons.package, size: 28, color: AppColors.textLow),
          const SizedBox(height: Sp.sm),
          Text(reason, textAlign: TextAlign.center, style: AppType.body(color: AppColors.textMid)),
          const SizedBox(height: Sp.md),
          OutlinedButton.icon(onPressed: _load, icon: const Icon(LucideIcons.refreshCw, size: 16), label: Text('pkgdist.retry'.tr())),
        ]),
      ));
      return out;
    }
    // ── الإيراد ──
    out.add(RpHeroKpi(
      kpi: RpKpi(id: 'revenue', label: 'pkgdist.revenue'.tr(), value: t.revenue, icon: LucideIcons.coins, tone: RpTone.money),
      compareWith: '',
      spark: const [],
      note: t.revenueOut.isEmpty ? 'pkgdist.revenue_hint'.tr() : _notIn(t.revenueOut),
      notes: _warnings(parts, screen: true),
    ));
    // ── المشتركون والتفعيلات، ولصاحب الحساب الربحان ──
    final single = !_merged && parts.length == 1 ? parts.single.report : null;
    out.add(RpKpiGrid(compareWith: '', kpis: [
      RpKpi(
        id: 'subs',
        label: 'pkgdist.subscribers_now'.tr(),
        value: t.subscribers ?? 0,
        display: PackageDistView.countText(t.subscribers),
        icon: LucideIcons.users,
        tone: RpTone.brand,
        hint: t.subsOut.isNotEmpty
            ? _notIn(t.subsOut)
            : (t.active == null ? null : 'pkgdist.active_n'.tr(namedArgs: {'n': PackageDistView.countText(t.active)})),
      ),
      RpKpi(
        id: 'acts',
        label: 'pkgdist.activations'.tr(),
        value: t.activations,
        isCount: true,
        icon: LucideIcons.zap,
        tone: RpTone.info,
        hint: t.movesOut.isNotEmpty ? _notIn(t.movesOut) : 'pkgdist.extensions_n'.tr(namedArgs: {'n': formatIQD(t.extensions)}),
      ),
      if (t.owner) ...[
        RpKpi(
          id: 'profit',
          label: 'pkgdist.profit_total'.tr(),
          value: t.profit ?? 0,
          display: t.profit == null ? '—' : null,
          icon: (t.profit ?? 0) < 0 ? LucideIcons.trendingDown : LucideIcons.trendingUp,
          tone: (t.profit ?? 0) < 0 ? RpTone.loss : RpTone.brand,
          hint: t.profitOut.isNotEmpty
              ? _notIn(t.profitOut)
              : single != null
                  ? (single.costExempt
                      ? 'pkgdist.profit_exempt'.tr()
                      : single.totals.cost != null
                          ? 'pkgdist.profit_after_cost'.tr(namedArgs: {'cost': rpMoney(single.totals.cost!)})
                          : 'pkgdist.cost_unavailable'.tr())
                  : (t.anyExempt
                      ? mergedWord('كلّ شركةٍ بقاعدتها — المعفاة بلا كلفة', 'كلّ صفحةٍ بقاعدتها — المعفاة بلا كلفة')
                      : (t.cost == null ? 'pkgdist.cost_unavailable'.tr() : 'pkgdist.profit_after_cost'.tr(namedArgs: {'cost': rpMoney(t.cost!)}))),
        ),
        RpKpi(
          id: 'est',
          label: 'pkgdist.profit_est'.tr(),
          value: t.estimated ?? 0,
          display: t.estimated == null ? '—' : null,
          icon: LucideIcons.sparkles,
          tone: (t.estimated ?? 0) < 0 ? RpTone.loss : RpTone.debt,
          hint: t.estOut.isNotEmpty ? _notIn(t.estOut) : 'pkgdist.profit_est_hint'.tr(),
        ),
      ],
    ]));
    out.addAll(_hints(parts));
    // ── الباقات ──
    final tabs = _tabsOf(t);
    final tab = tabs[_tab.clamp(0, tabs.length - 1)];
    final ordered = PackageDistView.ordered(PackageDistView.rows(parts), tab);
    final total = PackageDistView.totalOf(ordered, tab);
    final cap = _tabAll ? ordered.length : _cap;
    final shown = ordered.take(cap).toList();
    out.add(RpBreakdownCard(
      title: 'pkgdist.packages'.tr(),
      icon: LucideIcons.package,
      tabs: [for (final x in tabs) _tabLabel(x)],
      selected: tabs.indexOf(tab),
      tone: tab == PkgTab.profit ? RpTone.brand : (tab == PkgTab.revenue ? RpTone.money : RpTone.info),
      countOnly: tab == PkgTab.subscribers || tab == PkgTab.moves,
      unit: tab == PkgTab.subscribers ? 'مشترك' : 'حركة',
      shares: [for (final r in shown) PackageDistView.share(r, tab, total, company: _coOf(r.part))],
      onTab: (i) => setState(() {
        _tab = i;
        _tabAll = false;
      }),
      onShare: (i) => _openPackage(shown[i]),
      note: switch (tab) {
        PkgTab.subscribers => 'للحساب كلّه الآن — لا تتأثّر بالفترة ولا بالموظّف',
        PkgTab.revenue when _merged && parts.any((p) => !p.iqd) => 'بالدينار وحده',
        PkgTab.profit => 'لصاحب الحساب: الإيراد − كلفة الباقات',
        _ => null,
      },
      more: ordered.length > cap ? 'عرض الكلّ (${ordered.length})' : null,
      onMore: () => setState(() => _tabAll = true),
    ));
    out.add(RpExportBar(onPdf: () => _export('pdf'), onExcel: () => _export('excel'), onShare: () => _export('share')));
    out.add(Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(padding: const EdgeInsets.only(top: 2), child: Icon(LucideIcons.info, size: 14, color: AppColors.textLow)),
        const SizedBox(width: Sp.x6),
        Expanded(child: Text('pkgdist.footnote'.tr(), style: AppType.micro(color: AppColors.textLow))),
      ],
    ));
    return out;
  }

  /// التنبيهات الزرقاء (تُخفى بـ× ولا تعود): الكلفة معروفةٌ لبعض العمليّات، والمقدَّر لا يشمل باقات — للمفتوحة كالشاشة السابقة.
  List<Widget> _hints(List<PkgPart> parts) {
    if (_merged || parts.length != 1) return const [];
    final d = parts.single.report;
    final t = d.totals;
    return [
      if (d.owner && !d.costExempt && t.cost != null && t.costComplete == false && (t.costRows ?? 0) > 0 && !_dismissed.contains('cost_partial'))
        _Hint(
          text: 'pkgdist.cost_partial'.tr(namedArgs: {
            'known': PackageDistView.countText(t.costKnownRows),
            'rows': PackageDistView.countText(t.costRows),
          }),
          onDismiss: () => _dismiss('cost_partial'),
        ),
      if (d.owner && t.estimateMissingPackages > 0 && !_dismissed.contains('estimate_missing'))
        _Hint(
          text: 'pkgdist.estimate_missing'.tr(namedArgs: {'n': '${t.estimateMissingPackages}'}),
          onDismiss: () => _dismiss('estimate_missing'),
        ),
      if (d.subscribersPartial && !_dismissed.contains('partial'))
        _Hint(text: 'pkgdist.partial'.tr(), onDismiss: () => _dismiss('partial')),
    ];
  }

  Widget _companyTable(PkgTotals t) {
    final lines = <RpCompanyLine>[];
    final outside = <String>[];
    for (final co in _cos.values) {
      final c = co.c;
      if (c == null || co.unsupported) continue;
      if (co.loading) {
        lines.add(RpCompanyLine(company: _rp(c), state: RpCompanyState.loading));
        outside.add('${c.name} (تُقرأ)');
      } else if (!co.ok) {
        lines.add(RpCompanyLine(company: _rp(c, note: co.reason), state: RpCompanyState.failed));
        outside.add('${c.name} (${co.reason ?? 'تعذّرت'})');
      } else {
        final r = co.data!;
        final iqd = c.currency == 'IQD';
        final noActivity = r.unavailableParts.contains('activity');
        lines.add(RpCompanyLine(
          company: _rp(c),
          a: noActivity ? null : r.totals.activations,
          b: iqd && !noActivity ? r.totals.revenue : null,
          c: iqd && r.owner && !noActivity ? r.totals.profitTotal : null,
        ));
      }
    }
    return RpCompanyTable(
      heads: const ['التفعيلات', 'الإيراد', 'الربح'],
      tones: const [RpTone.info, RpTone.money, RpTone.brand],
      lines: lines,
      total: [t.activations, t.revenue, t.owner ? t.profit : null],
      outside: outside.isEmpty ? null : 'خارج المجموع الآن: ${outside.join(' · ')}',
      onTap: (c) => _apply(_f!.copyWith(companies: {c.key})),
      onRetry: (c) => _retry(c.key),
    );
  }
}

/// تنبيهٌ أزرق يُخفى بـ× (لا يعود على هذا الجهاز).
class _Hint extends StatelessWidget {
  const _Hint({required this.text, required this.onDismiss});
  final String text;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: Sp.sm),
      decoration: BoxDecoration(
        color: RpTone.info.soft,
        borderRadius: BorderRadius.circular(R.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(padding: const EdgeInsets.only(top: 1), child: Icon(LucideIcons.info, size: 15, color: RpTone.info.fg)),
          const SizedBox(width: Sp.sm),
          Expanded(child: Text(text, style: AppType.micro(color: AppColors.textHi))),
          InkWell(
            onTap: onDismiss,
            borderRadius: BorderRadius.circular(R.sm),
            child: Tooltip(
              message: 'pkgdist.dismiss'.tr(),
              child: Padding(
                padding: const EdgeInsetsDirectional.only(start: Sp.sm, top: 1, bottom: 1),
                child: Icon(LucideIcons.x, size: 16, color: AppColors.textMid),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
