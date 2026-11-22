import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../api/company_route.dart';
import '../../../api/earthlink_api.dart';
import '../../../api/merged_dashboard_api.dart';
import '../../../core/util/format.dart';
import '../../../models/merged_company.dart';
import '../../../services/merged_mode.dart';
import '../../../services/merged_text.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';
import '../../desktop/desk_widgets.dart';
import '../widgets/report_export.dart';
import '../widgets/report_permission_gate.dart';
import 'report_kit.dart';
import 'report_prefs.dart';

// تقريرا ايرث لنك على الشكل الموحّد (٢٢ نوفمبر — بند المقترح: «كشف حساب المشترك، وتقريرا ايرث لنك: نفس الشكل الموحّد»):
// «استخدام التجريبيّ» و«المشتركون حسب الباقة». حالٌ الآن لا فترة (الخادم يحدّده) ⇒ بلا شريط فترة. «كل الشركات»: شركات ايرث لنك
// وحدها في الشريط (المالك ٨ نوفمبر: «ولاشركه يظهر بيها الباقات» — لا شارة «ليست ايرث لنك» لكلّ ساس)، كلٌّ بطلبٍ موجَّه، والمتعذّرة
// تُسمّى ولا تُجمع. التصدير = ما على الشاشة.

/// قراءة شركةٍ من شركات ايرث لنك.
class _ElCo<T> {
  _ElCo(this.c, {this.rows, this.reason, this.loading = false});
  final MergedCompany? c; // null = المفتوحة
  final List<T>? rows;
  final String? reason;
  final bool loading;

  bool get ok => !loading && rows != null && reason == null;
}

/// الجلب المشترك: المفتوحة، أو شركات ايرث لنك المختارة كلٌّ بمفتاحها.
mixin _ElLoad<W extends StatefulWidget, T> on State<W> {
  static const perm = 'reports.activations';
  static const open = '·open';

  final cos = <String, _ElCo<T>>{};
  Set<String> picked = {};
  int _seq = 0;

  bool get merged => MergedMode.active.value;

  /// معرّف التقرير لحفظ ما طُوي من أقسامه (المالك ٢٢ نوفمبر: «الفرعيّة هو ينقر عليها ويظهرها»).
  String get reportId;
  late final folds = RpFolds(reportId, const {});

  /// ({rows, error}) — error غير null ⇒ تعذّرت.
  Future<({List<T> rows, String? error})> fetch();

  List<MergedCompany> get els => [for (final c in MergedDashboardApi.countable()) if (c.provider == MergedProvider.earthlink) c];

  bool isPicked(String key) => picked.isEmpty || picked.contains(key);

  void startLoad() {
    MergedMode.active.addListener(_onMerged);
    unawaited(folds.load().then((_) {
      if (mounted) setState(() {});
    }));
    unawaited(load());
  }

  void stopLoad() => MergedMode.active.removeListener(_onMerged);

  void _onMerged() {
    if (!mounted) return;
    setState(() {
      cos.clear();
      picked = {};
    });
    unawaited(load());
  }

  Future<void> load() async {
    final seq = ++_seq;
    if (!merged) {
      setState(() {
        cos
          ..clear()
          ..[open] = _ElCo<T>(null, loading: true);
      });
      final r = await fetch();
      if (!mounted || seq != _seq || merged) return;
      setState(() => cos[open] = _ElCo<T>(null, rows: r.error == null ? r.rows : null, reason: r.error));
      return;
    }
    final cs = [for (final c in els) if (isPicked(c.key)) c];
    setState(() {
      cos.clear();
      for (final c in cs) {
        cos[c.key] = _ElCo<T>(c, loading: true);
      }
    });
    await Future.wait([for (final c in cs) _loadCo(c, seq)]);
  }

  Future<void> _loadCo(MergedCompany c, int seq) async {
    if (MergedMode.pagePermAny(c.key, const [perm]) == false) {
      setState(() => cos[c.key] = _ElCo<T>(c, reason: MergedMode.noAccess('هذا التقرير فيها')));
      return;
    }
    final r = await CompanyRoute.run(c.key, fetch);
    if (!mounted || seq != _seq) return;
    setState(() => cos[c.key] = _ElCo<T>(c, rows: r.error == null ? r.rows : null, reason: r.error));
  }

  void retry(String key) {
    final co = cos[key];
    if (co?.c == null) return;
    setState(() => cos[key] = _ElCo<T>(co!.c, loading: true));
    unawaited(_loadCo(co!.c!, _seq));
  }

  void toggle(RpCompany c) {
    final all = [for (final x in els) x.key];
    final p = picked.isEmpty ? {...all} : {...picked};
    if (p.contains(c.key)) {
      if (p.length == 1) return;
      p.remove(c.key);
    } else {
      p.add(c.key);
    }
    picked = p.length == all.length ? {} : p;
    unawaited(load());
  }

  bool get busy => cos.isEmpty || cos.values.any((c) => c.loading);
  List<_ElCo<T>> get okCos => [for (final c in cos.values) if (c.ok) c];
  List<String> get failed => [for (final c in cos.values) if (!c.loading && !c.ok && c.c != null) c.c!.name];

  RpCompany rp(MergedCompany c, {bool selected = true, String? note}) =>
      RpCompany(key: c.key, name: c.name, colorIndex: c.colorIndex, selected: selected, note: note);

  RpCompany? coOf(String? key) {
    final c = key == null ? null : cos[key]?.c;
    return c == null ? null : rp(c);
  }

  Widget chips() => RpCompanyChips(
        companies: [for (final c in els) rp(c, selected: picked.isNotEmpty && picked.contains(c.key))],
        allSelected: picked.isEmpty,
        onAll: () {
          picked = {};
          unawaited(load());
        },
        onToggle: toggle,
      );

  /// جدول «حسب الشركة» بعمودٍ أو اثنين.
  Widget table(List<String> heads, List<num?> Function(_ElCo<T> co) cells, {List<RpTone> tones = const [RpTone.brand, RpTone.info, RpTone.info]}) {
    final lines = <RpCompanyLine>[];
    final outside = <String>[];
    for (final co in cos.values) {
      final c = co.c;
      if (c == null) continue;
      if (co.loading) {
        lines.add(RpCompanyLine(company: rp(c), state: RpCompanyState.loading));
        outside.add('${c.name} (تُقرأ)');
      } else if (!co.ok) {
        lines.add(RpCompanyLine(company: rp(c, note: co.reason), state: RpCompanyState.failed));
        outside.add('${c.name} (${co.reason ?? 'تعذّرت'})');
      } else {
        final v = cells(co);
        lines.add(RpCompanyLine(company: rp(c), a: v[0], b: v.length > 1 ? v[1] : null));
      }
    }
    final ok = [for (final l in lines) if (l.state == RpCompanyState.ok) l];
    return RpCompanyTable(
      fold: folds.fold('companies', setState),
      heads: heads,
      tones: tones,
      lines: lines,
      total: [
        ok.fold<num>(0, (a, l) => a + (l.a ?? 0)),
        if (heads.length > 1) ok.fold<num>(0, (a, l) => a + (l.b ?? 0)),
      ],
      outside: outside.isEmpty ? null : 'خارج المجموع الآن: ${outside.join(' · ')}',
      onTap: (c) {
        picked = {c.key};
        unawaited(load());
      },
      onRetry: (c) => retry(c.key),
    );
  }

  /// الحال بلا أرقام: تُقرأ، أو تعذّرت كلّها (بسببها)، أو null حين يوجد ما يُعرض.
  Widget? blank(IconData icon) {
    if (busy && okCos.isEmpty) {
      return const Padding(padding: EdgeInsets.symmetric(vertical: Sp.huge), child: Center(child: CircularProgressIndicator()));
    }
    if (okCos.isNotEmpty) return null;
    final reason = cos[open]?.reason ?? (cos.isEmpty ? 'لا شركات ايرث لنك' : 'تعذّرت القراءة الآن');
    return RpCard(
      child: Column(children: [
        Icon(icon, size: 28, color: AppColors.textLow),
        const SizedBox(height: Sp.sm),
        Text(reason, textAlign: TextAlign.center, style: AppType.body(color: AppColors.textMid)),
        const SizedBox(height: Sp.md),
        OutlinedButton.icon(onPressed: load, icon: const Icon(LucideIcons.refreshCw, size: 16), label: Text('common.retry'.tr())),
      ]),
    );
  }

  Widget page(String title, List<Widget> parts) {
    Theme.of(context); // theme-dep (dark-mode)
    return ReportPermissionGate(
      permission: perm,
      title: title,
      child: Scaffold(
        backgroundColor: AppColors.bg,
        appBar: deskPageBar(
          context,
          mobile: AppBar(
            backgroundColor: AppColors.surface,
            elevation: 0,
            scrolledUnderElevation: 0,
            title: Text(merged ? '$title · كل الشركات' : title, style: AppType.title(color: AppColors.textHi).copyWith(fontSize: 16)),
            iconTheme: IconThemeData(color: AppColors.textHi),
          ),
        ),
        body: SafeArea(
          child: RefreshIndicator(
            onRefresh: load,
            color: AppColors.brand,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, Sp.huge),
              children: [
                for (var i = 0; i < parts.length; i++) ...[if (i > 0) const SizedBox(height: Sp.md), parts[i]],
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// التصدير بما على الشاشة — ملفٌّ واحد بعناوينه ورأسه.
  Future<void> export(String how, {required String title, required String base, required List<String> columns, required List<List<String>> rows, required List<String> details}) {
    if (busy) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('انتظر حتى تكتمل الأرقام ثمّ صدّر')));
      return Future.value();
    }
    const subtitle = 'الآن';
    final all = [
      if (merged) 'الشركات: ${[for (final c in okCos) c.c?.name ?? ''].where((n) => n.isNotEmpty).join('، ')}',
      ...details,
      if (failed.isNotEmpty) 'ناقص: ${'merged.not_in_sum'.trm(args: [failed.map((n) => '«$n»').join('، ')])}',
    ];
    switch (how) {
      case 'pdf':
        return ReportExportActions.pdf(context, title: title, subtitle: subtitle, details: all, columns: columns, rows: rows, fileNameBase: base);
      case 'excel':
        return ReportExportActions.csv(context, title: title, subtitle: subtitle, details: all, columns: columns, rows: rows, fileNameBase: base);
      default:
        return ReportExportActions.sharePdf(context, title: title, subtitle: subtitle, details: all, columns: columns, rows: rows, fileNameBase: base);
    }
  }
}

// ═════════════════ استخدام التجريبيّ ═════════════════

class ElTestUsageV2Screen extends StatefulWidget {
  const ElTestUsageV2Screen({super.key});

  @override
  State<ElTestUsageV2Screen> createState() => _ElTestUsageV2State();
}

class _ElTestUsageV2State extends State<ElTestUsageV2Screen> with _ElLoad<ElTestUsageV2Screen, ElTestUsageRow> {
  static const _pageSize = 40;
  String _q = '';

  @override
  String get reportId => 'el_test_usage';
  int _visible = _pageSize;

  @override
  void initState() {
    super.initState();
    startLoad();
  }

  @override
  void dispose() {
    stopLoad();
    super.dispose();
  }

  @override
  Future<({List<ElTestUsageRow> rows, String? error})> fetch() async {
    final r = await EarthlinkApi.testUsage();
    return (rows: r.items, error: r.message);
  }

  List<({String? key, ElTestUsageRow row})> get _rows {
    final q = _q.trim().toLowerCase();
    return [
      for (final e in cos.entries)
        if (e.value.ok)
          for (final r in e.value.rows!)
            if (q.isEmpty || r.name.toLowerCase().contains(q) || (r.username ?? '').toLowerCase().contains(q))
              (key: e.value.c?.key, row: r),
    ];
  }

  static String _day(String? raw) {
    final s = (raw ?? '').trim().replaceFirst('T', ' ');
    return s.length >= 10 ? s.substring(0, 10).replaceAll('-', '/') : 'بلا تاريخ';
  }

  static String _time(String? raw) {
    final s = (raw ?? '').trim().replaceFirst('T', ' ');
    return s.length >= 16 ? s.substring(11, 16) : '';
  }

  List<RpDay> _days(List<({String? key, ElTestUsageRow row})> rows) {
    final sorted = [...rows]..sort((a, b) => (b.row.date ?? '').compareTo(a.row.date ?? ''));
    final byDay = <String, List<({String? key, ElTestUsageRow row})>>{};
    for (final r in sorted.take(_visible)) {
      (byDay[_day(r.row.date)] ??= []).add(r);
    }
    final counts = <String, int>{};
    for (final r in sorted) {
      counts[_day(r.row.date)] = (counts[_day(r.row.date)] ?? 0) + 1;
    }
    return [
      for (final e in byDay.entries)
        RpDay(
          date: e.key,
          count: counts[e.key] ?? e.value.length,
          sum: null,
          rows: [
            for (final r in e.value)
              RpRow(
                icon: LucideIcons.flaskConical,
                tone: RpTone.info,
                title: r.row.name,
                detail: r.row.username ?? '',
                amount: null,
                trailing: r.row.usage == null ? null : formatIQD(r.row.usage!),
                time: _time(r.row.date),
                company: merged ? coOf(r.key) : null,
              ),
          ],
        ),
    ];
  }

  void _export(String how) {
    final rows = _rows;
    unawaited(export(
      how,
      title: 'el.test_usage_title'.tr(),
      base: 'el-test-usage',
      columns: [if (merged) 'merged.col_company'.trm(), 'الاسم', 'اسم المستخدم', 'التاريخ', 'الاستهلاك'],
      rows: [
        for (final r in rows)
          [
            if (merged) coOf(r.key)?.name ?? '',
            r.row.name,
            r.row.username ?? '',
            (r.row.date ?? '').replaceFirst('T', ' '),
            r.row.usage == null ? '' : '${r.row.usage}',
          ],
      ],
      details: [
        if (_q.trim().isNotEmpty) 'البحث: «${_q.trim()}»',
        'عدد المشتركين: ${rows.length}',
      ],
    ));
  }

  @override
  Widget build(BuildContext context) {
    final title = 'el.test_usage_title'.tr();
    final parts = <Widget>[
      if (merged) ...[chips(), table(const ['المشتركون'], (co) => [co.rows!.length])],
    ];
    final none = blank(LucideIcons.flaskConical);
    if (none != null) return page(title, [...parts, none]);
    final all = [for (final co in okCos) ...co.rows!];
    final rows = _rows;
    parts.add(RpHeroKpi(
      kpi: RpKpi(id: 'count', label: 'el.test_usage_count'.tr(), value: all.length, isCount: true, unit: 'مشترك', icon: LucideIcons.flaskConical, tone: RpTone.info),
      compareWith: '',
      spark: const [],
      note: 'el.test_usage_hint'.tr(),
      notes: [if (failed.isNotEmpty) 'merged.not_in_sum'.trm(args: [failed.map((n) => '«$n»').join('، ')])],
    ));
    parts.add(RpRowsCard(
      query: _q,
      total: rows.length,
      days: _days(rows),
      more: rows.length > _visible ? 'عرض المزيد (${rows.length - _visible})' : null,
      onMore: () => setState(() => _visible += _pageSize),
      onSearch: (q) => setState(() {
        _q = q;
        _visible = _pageSize;
      }),
      searchHint: 'ابحث باسم المشترك أو يوزره',
      title: 'المشتركون',
      unit: 'مشترك',
      empty: all.isEmpty ? 'el.test_usage_empty'.tr() : 'لا نتائج للبحث',
    ));
    if (rows.isNotEmpty) {
      parts.add(RpExportBar(onPdf: () => _export('pdf'), onExcel: () => _export('excel'), onShare: () => _export('share')));
    }
    return page(title, parts);
  }
}

// ═════════════════ المشتركون حسب الباقة ═════════════════

class ElByPackageV2Screen extends StatefulWidget {
  const ElByPackageV2Screen({super.key});

  @override
  State<ElByPackageV2Screen> createState() => _ElByPackageV2State();
}

class _ElByPackageV2State extends State<ElByPackageV2Screen> with _ElLoad<ElByPackageV2Screen, ElPackageCount> {
  static const _cap = 12;
  bool _all = false;

  @override
  String get reportId => 'el_by_package';

  @override
  void initState() {
    super.initState();
    startLoad();
  }

  @override
  void dispose() {
    stopLoad();
    super.dispose();
  }

  @override
  Future<({List<ElPackageCount> rows, String? error})> fetch() async {
    final r = await EarthlinkApi.byPackage();
    return (rows: r.items, error: r.message);
  }

  /// الباقة باسمها مجموعةً من الشركات المقروءة (اسمها في ايرث لنك واحد) — الأكثر أوّلاً، ولكلّ شركةٍ عددها.
  List<({String name, int count, Map<String, int> by})> get _combined {
    final acc = <String, ({int count, Map<String, int> by})>{};
    for (final co in okCos) {
      for (final p in co.rows!) {
        final o = acc[p.name];
        final by = {...?o?.by};
        final k = co.c?.key ?? _ElLoad.open;
        by[k] = (by[k] ?? 0) + p.count;
        acc[p.name] = (count: (o?.count ?? 0) + p.count, by: by);
      }
    }
    final out = [for (final e in acc.entries) (name: e.key, count: e.value.count, by: e.value.by)];
    out.sort((a, b) => b.count != a.count ? b.count.compareTo(a.count) : a.name.compareTo(b.name));
    return out;
  }

  void _export(String how) {
    final rows = _combined;
    final cs = [for (final co in okCos) if (co.c != null) co.c!];
    final total = rows.fold<int>(0, (a, r) => a + r.count);
    unawaited(export(
      how,
      title: 'el.by_package_title'.tr(),
      base: 'el-by-package',
      // «كل الشركات»: المجموع ثمّ عمودٌ لكلّ شركة — ما على الشاشة وتفصيله
      columns: ['الباقة', 'المشتركون', if (merged && cs.length > 1) ...[for (final c in cs) c.name]],
      rows: [
        for (final r in rows)
          [r.name, '${r.count}', if (merged && cs.length > 1) ...[for (final c in cs) '${r.by[c.key] ?? 0}']],
      ],
      details: ['إجمالي المشتركين: ${formatIQD(total)}', 'عدد الباقات: ${rows.length}'],
    ));
  }

  @override
  Widget build(BuildContext context) {
    final title = 'el.by_package_title'.tr();
    final parts = <Widget>[
      if (merged) ...[
        chips(),
        table(const ['المشتركون', 'الباقات'], (co) => [co.rows!.fold<int>(0, (a, p) => a + p.count), co.rows!.length]),
      ],
    ];
    final none = blank(LucideIcons.package);
    if (none != null) return page(title, [...parts, none]);
    final rows = _combined;
    final total = rows.fold<int>(0, (a, r) => a + r.count);
    final several = merged && okCos.length > 1;
    parts.add(RpHeroKpi(
      kpi: RpKpi(id: 'total', label: 'el.by_package_total'.tr(), value: total, isCount: true, unit: 'مشترك', icon: LucideIcons.users, tone: RpTone.brand),
      compareWith: '',
      spark: const [],
      note: '${'el.by_package_count'.tr()}: ${formatIQD(rows.length)}',
      notes: [if (failed.isNotEmpty) 'merged.not_in_sum'.trm(args: [failed.map((n) => '«$n»').join('، ')])],
    ));
    final cap = _all ? rows.length : _cap;
    parts.add(RpBreakdownCard(
      title: 'الباقات',
      icon: LucideIcons.package,
      tabs: const ['المشتركون'],
      selected: 0,
      tone: RpTone.brand,
      countOnly: true,
      unit: 'مشترك',
      empty: 'el.by_package_empty'.tr(),
      note: several ? 'الباقة نفسها من الشركات سطرٌ واحد' : null,
      shares: [
        for (final r in rows.take(cap))
          RpShare(
            name: r.name,
            amount: 0,
            count: r.count,
            share: total == 0 ? 0 : r.count / total,
            sub: several
                ? [for (final co in okCos) if ((r.by[co.c?.key ?? _ElLoad.open] ?? 0) > 0) '${co.c?.name ?? ''} ${formatIQD(r.by[co.c?.key ?? _ElLoad.open]!)}'].join(' · ')
                : null,
          ),
      ],
      more: rows.length > cap ? 'عرض الكلّ (${rows.length})' : null,
      onMore: () => setState(() => _all = true),
    ));
    if (rows.isNotEmpty) {
      parts.add(RpExportBar(onPdf: () => _export('pdf'), onExcel: () => _export('excel'), onShare: () => _export('share')));
    }
    return page(title, parts);
  }
}
