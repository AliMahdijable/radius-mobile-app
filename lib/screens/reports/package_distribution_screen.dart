import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../api/package_report_api.dart';
import '../../core/util/format.dart';
import '../../models/merged_company.dart';
import '../../services/merged_mode.dart';
import '../../services/merged_report_loader.dart';
import '../../widgets/company_tag.dart';
import '../../widgets/merged_breakdown.dart';
import '../../widgets/merged_company_strip.dart';
import '../../services/permissions_service.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import '../desktop/desk_widgets.dart';
import '../../core/platform/desktop_layout.dart';
import 'widgets/date_range_chip.dart';
import 'widgets/report_export.dart';
import 'widgets/report_filters.dart';
import 'widgets/report_permission_gate.dart';
import 'widgets/scope_helper.dart';
import '../../services/merged_text.dart';

/// نصّ ما تعذّر من التقرير — جزءاً جزءاً، لا صفر (كالويب: client-v2 package-report.ts).
String packagePartText(String part) {
  const known = {'activity', 'package_cost', 'packages', 'subscribers'};
  return known.contains(part)
      ? 'pkgdist.part_$part'.tr()
      : 'pkgdist.part_other'.tr();
}

/// «توزيع الباقات والأرباح» (#٥، ٢٥ أكتوبر) — `GET /api/reports/finance/packages`، كصفحة الويب `/v2/reports/packages`.
///
/// لكلّ باقة: المشتركون الآن (الكلّ/الفعّال — للحساب كلّه بعد «نطاق العرض») · تفعيلات الفترة وتمديداتها · الإيراد (سعر البيع)
/// · ولصاحب الحساب وحده الكلفة والربح الكلّي والمقدَّر (قرار الخادم). بصلاحيّة «التقرير الماليّ» — المقفل لا يطلب شيئاً.
/// النطاق نطاق تقارير التطبيق (المدير المسجّل، loadScopeUserIds).
///
/// «كل الشركات» (٧ نوفمبر — المالك: «التقارير… بنفس فكرة عرض المشتركين والاختيار بين الكل وشركة»): الشاشة نفسها وشريط الشركات
/// أعلاها. تقرير كلّ شركةٍ بطلبٍ موجَّه بنطاقها هي (معرّف مديرها — كما تراه وحدها)؛ «الكل»: البطاقات مجموعة (المشتركون والتفعيلات من
/// كلّ شركةٍ قُرئت، والإيراد بالدينار وحده، والربح مجموع ربح كلّ شركةٍ بقاعدتها — المعفاة بلا كلفة — ومن لا يُعرف ربحها تُسمّى)،
/// و«حسب الشركة» (الضغط يعرضها وحدها)، وباقات الشركات معاً بشارة شركتها. الشركة المختارة: تقريرها كما هو من الجمع المحفوظ (بلا
/// طلبٍ جديد). كان «الكل» يعرض الشركة المفتوحة وحدها بلا ذكرٍ لذلك.
class PackageDistributionScreen extends StatefulWidget {
  const PackageDistributionScreen({super.key});

  @override
  State<PackageDistributionScreen> createState() =>
      _PackageDistributionScreenState();
}

class _PackageDistributionScreenState extends State<PackageDistributionScreen> {
  // «توزيع الباقات» بمفتاحه منذ ٢٥ أكتوبر (كان «تقرير مالي») — الخادم يفرضه (54b6dba).
  static const _perm = 'reports.packages';

  late DateRange _range = _last30();
  ReportFilters _filters = const ReportFilters();
  PackageReport? _data;
  String? _error;
  bool _loading = false;
  bool _requested = false;
  int _gen = 0;

  /// الباقات المفتوحة — كلّها مطويّة أوّلاً، والنقر على عنوانها يفتح تفاصيلها (المالك ٢٥ أكتوبر). «كل الشركات»: «مفتاح الشركة|الباقة».
  final Set<String> _open = {};

  // ── «كل الشركات» ──
  bool get _mergedOn => MergedMode.active.value;
  MergedReport<PackageReport>? _merged;

  void _onMergedMode() {
    if (!mounted) return;
    _merged = null;
    _data = null;
    _open.clear();
    _filters = const ReportFilters();
    if (_requested) _load();
  }

  void _onMergedFocus() {
    if (!mounted || !_mergedOn || _merged == null) return;
    setState(_applyMergedFocus);
  }

  /// الشركة المختارة من الجمع المحفوظ (بلا طلب)، أو «الكل» (_data فارغ).
  void _applyMergedFocus() {
    final m = _merged;
    if (m == null) return;
    final f = MergedMode.focused;
    if (f == null) {
      _data = null;
      _error = m.parts.any((p) => p.ok) ? null : 'pkgdist.fetch_failed'.tr();
      return;
    }
    final p = m.partOf(f.key);
    _data = p?.rows?.firstOrNull;
    _error = _data != null
        ? null
        : (p?.unsupported == true ? 'لا تقرير باقاتٍ لنوعها' : (p?.error ?? 'pkgdist.fetch_failed'.tr()));
  }

  /// أرقام شركةٍ بعملتها: الدينار بـ«د.ع»، وغيره برمزه.
  String _moneyOf(MergedCompany c, num? v) =>
      v == null ? '—' : '${formatIQD(v)} ${c.currency == 'IQD' ? 'common.currency'.tr() : (c.currency ?? '')}';
  String _signedOf(MergedCompany c, num? v) => v == null ? '—' : '${v < 0 ? '-' : ''}${_moneyOf(c, v.abs())}';

  /// التنبيهات الزرقاء التي أخفاها المستخدم — على هذا الجهاز، لا تعود.
  Set<String> _dismissed = {};
  static const _dismissedKey = 'pkg_report_dismissed_hints';

  /// كبطاقة الرئيسيّة: آخر ٣٠ يوماً — فالرقمان واحدٌ حين تفتحه منها.
  static DateRange _last30() {
    final n = DateTime.now();
    final from = n.subtract(const Duration(days: 29));
    return DateRange(
      DateTime(from.year, from.month, from.day),
      DateTime(n.year, n.month, n.day, 23, 59, 59),
      label: 'pkgdist.last_30'.tr(),
    );
  }

  @override
  void initState() {
    super.initState();
    PermissionsService.changes.addListener(_maybeLoad);
    MergedMode.active.addListener(_onMergedMode);
    MergedMode.focus.addListener(_onMergedFocus);
    _maybeLoad();
    _loadDismissed();
  }

  Future<void> _loadDismissed() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final v = prefs.getStringList(_dismissedKey) ?? const [];
      if (mounted && v.isNotEmpty) setState(() => _dismissed = v.toSet());
    } catch (_) {/* تبقى ظاهرة */}
  }

  Future<void> _dismiss(String hint) async {
    setState(() => _dismissed = {..._dismissed, hint});
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_dismissedKey, _dismissed.toList());
    } catch (_) {/* أُخفيت لهذه الجلسة على الأقلّ */}
  }

  @override
  void dispose() {
    _gen++;
    PermissionsService.changes.removeListener(_maybeLoad);
    MergedMode.active.removeListener(_onMergedMode);
    MergedMode.focus.removeListener(_onMergedFocus);
    super.dispose();
  }

  /// المقفل لا يطلب (الخادم يردّ ٤٠٣ خلف «لا صلاحيّة»)؛ وصلاحيّةٌ تصل والشاشة مفتوحة تطلبه حينها.
  void _maybeLoad() {
    if (_requested || !Perms.has(_perm)) return;
    _requested = true;
    _load();
  }

  Future<void> _load() async {
    final gen = ++_gen;
    setState(() {
      _loading = true;
      _error = null;
    });
    if (_mergedOn) {
      // كلّ شركةٍ بنطاقها هي (معرّف مديرها) — طلبٌ موجَّه لكلٍّ منها
      final m = await loadMergedReport<PackageReport>(
        perms: const [_perm],
        supports: (c) => c.provider != MergedProvider.ftth && c.provider != MergedProvider.fiberx,
        fetch: (c) async {
          final r = await PackageReportApi.fetch(from: _range.from, to: _range.to, userIds: [c.adminId]);
          return (ok: r.data != null, rows: r.data == null ? const <PackageReport>[] : [r.data!], error: r.error, note: null);
        },
      );
      if (!mounted || gen != _gen || !_mergedOn) return;
      setState(() {
        _loading = false;
        _merged = m;
        _applyMergedFocus();
      });
      return;
    }
    final ids = await loadScopeUserIds();
    final r = await PackageReportApi.fetch(
      from: _range.from,
      to: _range.to,
      userIds: ids,
      employeeId: _filters.employeeId,
    );
    if (!mounted || gen != _gen || _mergedOn) return;
    setState(() {
      _merged = null;
      _loading = false;
      _data = r.data;
      _error = r.data == null ? (r.error ?? 'pkgdist.fetch_failed'.tr()) : null;
    });
  }

  String _money(num? v) =>
      v == null ? '—' : '${formatIQD(v)} ${'common.currency'.tr()}';
  String _signed(num? v) => v == null
      ? '—'
      : '${v < 0 ? '-' : ''}${formatIQD(v)} ${'common.currency'.tr()}';
  String _count(int? v) => v == null ? '—' : formatIQD(v);
  Color _profitColor(num? v) => v == null
      ? AppColors.textLow
      : (v < 0 ? AppColors.error : AppColors.success);

  List<String> get _exportColumns => [
        if (_mergedAllRows != null) 'merged.col_company'.trm(),
        'pkgdist.card_title'.tr(),
        'pkgdist.subscribers_now'.tr(),
        'pkgdist.active'.tr(),
        'pkgdist.activations'.tr(),
        'pkgdist.extensions'.tr(),
        'pkgdist.price'.tr(),
        'pkgdist.revenue'.tr(),
        if (_data?.owner == true || _mergedAllRows != null) ...[
          'pkgdist.unit_cost'.tr(),
          'pkgdist.cost'.tr(),
          'pkgdist.profit_total'.tr(),
          'pkgdist.profit_est'.tr(),
        ],
      ];

  List<List<String>> get _exportRows => [
        // «كل الشركات» (الكلّ): باقات كلّ شركةٍ بعمودها أوّلاً
        if (_mergedAllRows case final rows?)
          for (final e in rows)
            [
              e.c.name,
              e.r.name,
              _count(e.r.subscribersTotal),
              _count(e.r.subscribersActive),
              '${e.r.activations}',
              '${e.r.extensions}',
              e.r.price == null ? '' : formatIQD(e.r.price!),
              formatIQD(e.r.revenue),
              ...[
                e.r.unitCost == null ? '' : formatIQD(e.r.unitCost!),
                e.r.cost == null ? '' : formatIQD(e.r.cost!),
                e.r.profitTotal == null ? '' : '${e.r.profitTotal! < 0 ? '-' : ''}${formatIQD(e.r.profitTotal!)}',
                e.r.profitEstimated == null ? '' : '${e.r.profitEstimated! < 0 ? '-' : ''}${formatIQD(e.r.profitEstimated!)}',
              ],
            ]
        else
        for (final r in _data?.rows ?? const <PackageReportRow>[])
          [
            r.name,
            _count(r.subscribersTotal),
            _count(r.subscribersActive),
            '${r.activations}',
            '${r.extensions}',
            r.price == null ? '' : formatIQD(r.price!),
            formatIQD(r.revenue),
            if (_data?.owner == true) ...[
              r.unitCost == null ? '' : formatIQD(r.unitCost!),
              r.cost == null ? '' : formatIQD(r.cost!),
              r.profitTotal == null
                  ? ''
                  : '${r.profitTotal! < 0 ? '-' : ''}${formatIQD(r.profitTotal!)}',
              r.profitEstimated == null
                  ? ''
                  : '${r.profitEstimated! < 0 ? '-' : ''}${formatIQD(r.profitEstimated!)}',
            ],
          ],
      ];

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final desk = DesktopScope.of(context);
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
            title: Text(
              'pkgdist.title'.tr(),
              style:
                  AppType.title(color: AppColors.textHi).copyWith(fontSize: 16),
            ),
            iconTheme: IconThemeData(color: AppColors.textHi),
          ),
        ),
        body: SafeArea(
          child: RefreshIndicator(
            onRefresh: _load,
            color: AppColors.brand,
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                  Sp.lg, desk ? Sp.xs : Sp.md, Sp.lg, Sp.huge),
              children: [
                // «كل الشركات»: الشركات بعدد تفعيلات كلٍّ منها في الفترة، ومن لم يُقرأ ولماذا
                if (_mergedOn && _merged != null) ...[
                  MergedCompanyStrip(
                    countOf: (c) => _merged!.partOf(c.key)?.rows?.firstOrNull?.totals.activations,
                    total: [for (final p in _merged!.parts) ...?p.rows].fold<int>(0, (s, r) => s + r.totals.activations),
                    problemOf: (c) => _merged!.problemOf(c,
                        failedLabel: 'merged.chip_failed'.trm(), unsupportedLabel: 'merged.web_only'.trm()),
                    note: _mergedNote(_merged!),
                  ),
                  const SizedBox(height: Sp.md),
                ],
                DateRangeChipBar(
                  value: _range,
                  onChanged: (r) {
                    setState(() => _range = r);
                    _load();
                  },
                ),
                const SizedBox(height: Sp.sm),
                // الموظّف المنفِّذ وحده: لا نوع حركة (التقرير تفعيلٌ وتمديد) ولا مدير (النطاق من الخادم).
                // «كل الشركات»: قائمة الموظّفين للشركة المفتوحة وحدها — يُخفى
                if (!_mergedOn)
                ReportFiltersPanel(
                  value: _filters,
                  includeActionTypes: false,
                  includeActionManager: false,
                  includeUserManager: false,
                  onChanged: (v) {
                    setState(() => _filters = v);
                    _load();
                  },
                ),
                const SizedBox(height: Sp.md),
                ..._content(desk),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _content(bool desk) {
    if (_loading && _data == null) {
      return [
        const Padding(
          padding: EdgeInsets.symmetric(vertical: Sp.huge),
          child: Center(child: CircularProgressIndicator()),
        ),
        Center(
            child: Text('pkgdist.loading_counts'.tr(),
                style: AppType.micro(color: AppColors.textLow))),
      ];
    }
    // «كل الشركات» (الكلّ): المجموع وحسب الشركة وباقات الشركات معاً
    if (_mergedOn && _merged != null && MergedMode.focused == null) return _mergedContent(desk);
    final d = _data;
    if (d == null) {
      return [
        _Notice(
            icon: LucideIcons.triangleAlert,
            color: AppColors.error,
            text: _error ?? 'pkgdist.fetch_failed'.tr()),
        const SizedBox(height: Sp.sm),
        Center(
          child: OutlinedButton.icon(
            onPressed: _load,
            icon: const Icon(LucideIcons.refreshCw, size: 16),
            label: Text('pkgdist.retry'.tr()),
          ),
        ),
      ];
    }
    final t = d.totals;
    final kpis = <Widget>[
      _Kpi(
        icon: LucideIcons.users,
        color: AppColors.brand,
        label: 'pkgdist.subscribers_now'.tr(),
        value: _count(t.subscribersTotal),
        hint: t.subscribersActive == null
            ? null
            : 'pkgdist.active_n'
                .tr(namedArgs: {'n': _count(t.subscribersActive)}),
      ),
      _Kpi(
        icon: LucideIcons.zap,
        color: AppColors.info,
        label: 'pkgdist.activations'.tr(),
        value: _count(t.activations),
        hint: 'pkgdist.extensions_n'.tr(namedArgs: {'n': _count(t.extensions)}),
      ),
      _Kpi(
        icon: LucideIcons.coins,
        color: AppColors.anomaly,
        label: 'pkgdist.revenue'.tr(),
        value: _money(t.revenue),
        hint: 'pkgdist.revenue_hint'.tr(),
      ),
      if (d.owner)
        _Kpi(
          icon: LucideIcons.trendingUp,
          color: AppColors.success,
          label: 'pkgdist.profit_total'.tr(),
          value: _signed(t.profitTotal),
          valueColor: _profitColor(t.profitTotal),
          hint: d.costExempt
              ? 'pkgdist.profit_exempt'.tr()
              : t.cost != null
                  ? 'pkgdist.profit_after_cost'
                      .tr(namedArgs: {'cost': _money(t.cost)})
                  : 'pkgdist.cost_unavailable'.tr(),
        ),
      if (d.owner)
        _Kpi(
          icon: LucideIcons.sparkles,
          color: AppColors.warning,
          label: 'pkgdist.profit_est'.tr(),
          value: _signed(t.profitEstimated),
          valueColor: _profitColor(t.profitEstimated),
          hint: 'pkgdist.profit_est_hint'.tr(),
        ),
    ];
    final cards = [
      for (final r in d.rows)
        _PackageCard(
            row: r,
            owner: d.owner,
            money: _money,
            signed: _signed,
            count: _count,
            profitColor: _profitColor,
            maxSubs: _maxSubs(d),
            expanded: _open.contains(r.key),
            onToggle: () => setState(() {
                  if (!_open.remove(r.key)) _open.add(r.key);
                })),
    ];
    return [
      // صفّان على الهاتف (والخامس بعرض السطر)، وصفٌّ واحد على الحاسبة.
      if (desk)
        DeskGrid(minTileWidth: 200, spacing: Sp.md, children: kpis)
      else
        _KpiGrid(children: kpis),
      for (final p in d.unavailableParts) ...[
        const SizedBox(height: Sp.sm),
        _Notice(
            icon: LucideIcons.triangleAlert,
            color: AppColors.warning,
            text: packagePartText(p)),
      ],
      // التنبيهات الزرقاء تُخفى بـ× ولا تعود على هذا الجهاز (المالك ٢٥ أكتوبر: «الهنت هذا اجعله قابل للالغاء»).
      // التحذيرات (جزءٌ تعذّر) تبقى — هي ما يقول إنّ رقماً ناقص.
      if (d.owner &&
          !d.costExempt &&
          t.cost != null &&
          t.costComplete == false &&
          (t.costRows ?? 0) > 0 &&
          !_dismissed.contains('cost_partial')) ...[
        const SizedBox(height: Sp.sm),
        _Notice(
          icon: LucideIcons.info,
          color: AppColors.info,
          text: 'pkgdist.cost_partial'.tr(namedArgs: {
            'known': _count(t.costKnownRows),
            'rows': _count(t.costRows)
          }),
          onDismiss: () => _dismiss('cost_partial'),
        ),
      ],
      if (d.owner && t.estimateMissingPackages > 0 && !_dismissed.contains('estimate_missing')) ...[
        const SizedBox(height: Sp.sm),
        _Notice(
          icon: LucideIcons.info,
          color: AppColors.info,
          text: 'pkgdist.estimate_missing'
              .tr(namedArgs: {'n': '${t.estimateMissingPackages}'}),
          onDismiss: () => _dismiss('estimate_missing'),
        ),
      ],
      if (d.subscribersPartial && !_dismissed.contains('partial')) ...[
        const SizedBox(height: Sp.sm),
        _Notice(
          icon: LucideIcons.info,
          color: AppColors.info,
          text: 'pkgdist.partial'.tr(),
          onDismiss: () => _dismiss('partial'),
        ),
      ],
      const SizedBox(height: Sp.md),
      if (d.rows.isEmpty)
        _Notice(
            icon: LucideIcons.package,
            color: AppColors.textLow,
            text: 'pkgdist.empty_period'.tr())
      else ...[
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: ReportExportBar(
            title: 'pkgdist.title'.tr(),
            subtitle: _range.label,
            fileNameBase: 'package-distribution',
            columns: _exportColumns,
            rows: _exportRows,
          ),
        ),
        const SizedBox(height: Sp.sm),
        if (desk)
          DeskGrid(minTileWidth: 320, spacing: Sp.md, children: cards)
        else
          for (final c in cards) ...[c, const SizedBox(height: Sp.sm)],
      ],
      const SizedBox(height: Sp.md),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(LucideIcons.info, size: 14, color: AppColors.textLow),
          ),
          const SizedBox(width: 6),
          Expanded(
              child: Text('pkgdist.footnote'.tr(),
                  style: AppType.micro(color: AppColors.textLow))),
        ],
      ),
    ];
  }

  int _maxSubs(PackageReport d) => d.rows.fold<int>(0, (m, r) {
        final v = r.subscribersTotal ?? 0;
        return v > m ? v : m;
      });

  // ═══════════════ «كل الشركات» (الكلّ) ═══════════════

  /// شركاتٌ قُرئ تقريرها، بترتيب الشريط.
  List<({MergedCompany c, PackageReport r})> get _mergedOk => [
        for (final p in _merged?.parts ?? const <MergedReportPart<PackageReport>>[])
          if (p.ok && p.rows!.isNotEmpty) (c: p.company, r: p.rows!.first),
      ];

  /// باقات الشركات معاً (الأكثر تفعيلاً أوّلاً) — null خارج «الكل».
  List<({MergedCompany c, PackageReportRow r})>? get _mergedAllRows {
    if (!_mergedOn || _merged == null || MergedMode.focused != null) return null;
    final rows = [
      for (final e in _mergedOk)
        for (final r in e.r.rows) (c: e.c, r: r),
    ];
    rows.sort((a, b) {
      final x = b.r.activations.compareTo(a.r.activations);
      return x != 0 ? x : b.r.revenue.compareTo(a.r.revenue);
    });
    return rows;
  }

  /// سطر الشريط: من لم يُقرأ ولماذا، وشركاتٌ بعملةٍ أخرى إيرادها خارج المجموع.
  String? _mergedNote(MergedReport<PackageReport> m) {
    final focus = MergedMode.focused;
    final lines = <String>[
      if (m.noteFor(focus?.key,
              unsupportedText: 'لا تقرير باقاتٍ لنوعها',
              missingText: 'merged.missing'.trm(args: [m.missing.map((c) => c.name).join('، ')]))
          case final n?)
        n,
      if (focus == null)
        for (final e in _mergedOk)
          if (e.c.currency != 'IQD')
            'merged.not_in_sum'.trm(args: ['إيراد «${e.c.name}» وربحها (${e.c.currency ?? 'عملةٌ غير معروفة'})']),
    ];
    return lines.isEmpty ? null : lines.join('\n');
  }

  List<Widget> _mergedContent(bool desk) {
    final ok = _mergedOk;
    if (ok.isEmpty) {
      return [
        _Notice(icon: LucideIcons.triangleAlert, color: AppColors.error, text: 'pkgdist.fetch_failed'.tr()),
        const SizedBox(height: Sp.sm),
        Center(
          child: OutlinedButton.icon(
            onPressed: _load,
            icon: const Icon(LucideIcons.refreshCw, size: 16),
            label: Text('pkgdist.retry'.tr()),
          ),
        ),
      ];
    }
    final iqd = ok.where((e) => e.c.currency == 'IQD').toList();
    // شركاتٌ لم يُقرأ تقريرها — تُسمّى تحت كلّ رقمٍ مجموع (لا صفرٌ صامت)
    final unread = [for (final p in _merged!.parts) if (!p.ok || p.rows!.isEmpty) p.company.name];
    int sumOf(int? Function(PackageReport r) f) => ok.fold<int>(0, (s, e) => s + (f(e.r) ?? 0));
    final subsMissing = [...unread, for (final e in ok) if (e.r.totals.subscribersTotal == null) e.c.name];
    final revenue = iqd.fold<num>(0, (s, e) => s + e.r.totals.revenue);
    final revenueOut = [...unread, for (final e in ok) if (e.c.currency != 'IQD') e.c.name];
    // الربح: مجموع ربح كلّ شركةٍ بقاعدتها (المعفاة = إيرادها، وغيرها بعد كلفتها) — من لا يُعرف ربحها أو عملتها أخرى تُسمّى
    final withProfit = [for (final e in iqd) if (e.r.owner && e.r.totals.profitTotal != null) e];
    final profitOut = [...unread, for (final e in ok) if (!withProfit.contains(e)) e.c.name];
    final profit = withProfit.isEmpty ? null : withProfit.fold<num>(0, (s, e) => s + e.r.totals.profitTotal!);
    final withEst = [for (final e in iqd) if (e.r.owner && e.r.totals.profitEstimated != null) e];
    final estOut = [...unread, for (final e in ok) if (!withEst.contains(e)) e.c.name];
    final est = withEst.isEmpty ? null : withEst.fold<num>(0, (s, e) => s + e.r.totals.profitEstimated!);
    final anyExempt = withProfit.any((e) => e.r.costExempt);
    final owner = ok.any((e) => e.r.owner);
    String notIn(List<String> names) => 'لا يشمل: ${names.join('، ')}';
    final kpis = <Widget>[
      _Kpi(
        icon: LucideIcons.users,
        color: AppColors.brand,
        label: 'pkgdist.subscribers_now'.tr(),
        value: _count(sumOf((r) => r.totals.subscribersTotal)),
        hint: subsMissing.isNotEmpty
            ? notIn(subsMissing)
            : 'pkgdist.active_n'.tr(namedArgs: {'n': _count(sumOf((r) => r.totals.subscribersActive))}),
      ),
      _Kpi(
        icon: LucideIcons.zap,
        color: AppColors.info,
        label: 'pkgdist.activations'.tr(),
        value: _count(sumOf((r) => r.totals.activations)),
        hint: unread.isNotEmpty
            ? notIn(unread)
            : 'pkgdist.extensions_n'.tr(namedArgs: {'n': _count(sumOf((r) => r.totals.extensions))}),
      ),
      _Kpi(
        icon: LucideIcons.coins,
        color: AppColors.anomaly,
        label: 'pkgdist.revenue'.tr(),
        value: _money(revenue),
        hint: revenueOut.isEmpty ? 'pkgdist.revenue_hint'.tr() : notIn(revenueOut),
      ),
      if (owner)
        _Kpi(
          icon: LucideIcons.trendingUp,
          color: AppColors.success,
          label: 'pkgdist.profit_total'.tr(),
          value: _signed(profit),
          valueColor: _profitColor(profit),
          hint: profitOut.isNotEmpty
              ? notIn(profitOut)
              : (anyExempt ? mergedWord('كلّ شركةٍ بقاعدتها — المعفاة بلا كلفة', 'كلّ صفحةٍ بقاعدتها — المعفاة بلا كلفة') : 'pkgdist.profit_after_cost'.tr(namedArgs: {
                  'cost': _money(withProfit.fold<num>(0, (s, e) => s + (e.r.totals.cost ?? 0))),
                })),
        ),
      if (owner)
        _Kpi(
          icon: LucideIcons.sparkles,
          color: AppColors.warning,
          label: 'pkgdist.profit_est'.tr(),
          value: _signed(est),
          valueColor: _profitColor(est),
          hint: estOut.isEmpty ? 'pkgdist.profit_est_hint'.tr() : notIn(estOut),
        ),
    ];
    final rows = _mergedAllRows ?? const [];
    final maxSubs = rows.fold<int>(0, (m, e) => (e.r.subscribersTotal ?? 0) > m ? e.r.subscribersTotal! : m);
    final cards = [
      for (final e in rows)
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 4, bottom: 4),
            child: CompanyTag(companyKey: e.c.key, fontSize: 11),
          ),
          _PackageCard(
              row: e.r,
              owner: _mergedOk.firstWhere((x) => x.c.key == e.c.key).r.owner,
              money: (v) => _moneyOf(e.c, v),
              signed: (v) => _signedOf(e.c, v),
              count: _count,
              profitColor: _profitColor,
              maxSubs: maxSubs,
              expanded: _open.contains('${e.c.key}|${e.r.key}'),
              onToggle: () => setState(() {
                    final k = '${e.c.key}|${e.r.key}';
                    if (!_open.remove(k)) _open.add(k);
                  })),
        ]),
    ];
    final breakdown = <MergedBreakdownRow>[
      for (final p in _merged!.parts)
        if (p.ok && p.rows!.isNotEmpty)
          (() {
            final t = p.rows!.first.totals;
            final profitText = p.rows!.first.owner && t.profitTotal != null
                ? ' · ${'pkgdist.profit_total'.tr()}: ${_signedOf(p.company, t.profitTotal)}'
                : '';
            return (
              key: p.company.key,
              value: '${_count(t.activations)} ${'pkgdist.activations'.tr()}',
              sub: '${_moneyOf(p.company, t.revenue)}$profitText',
              reason: null,
            );
          })()
        else
          (
            key: p.company.key,
            value: null,
            sub: null,
            reason: p.unsupported ? 'لا تقرير باقاتٍ لنوعها' : (p.error ?? 'pkgdist.fetch_failed'.tr()),
          ),
    ];
    return [
      if (desk) DeskGrid(minTileWidth: 200, spacing: Sp.md, children: kpis) else _KpiGrid(children: kpis),
      // ما تعذّر من تقرير كلّ شركة — باسمها (لا صفر)
      for (final e in ok)
        for (final part in e.r.unavailableParts) ...[
          const SizedBox(height: Sp.sm),
          _Notice(icon: LucideIcons.triangleAlert, color: AppColors.warning, text: '«${e.c.name}»: ${packagePartText(part)}'),
        ],
      for (final e in ok)
        if (e.r.subscribersPartial) ...[
          const SizedBox(height: Sp.sm),
          _Notice(icon: LucideIcons.info, color: AppColors.info, text: '«${e.c.name}»: ${'pkgdist.partial'.tr()}'),
        ],
      const SizedBox(height: Sp.md),
      MergedBreakdownCard(rows: breakdown),
      const SizedBox(height: Sp.md),
      if (rows.isEmpty)
        _Notice(icon: LucideIcons.package, color: AppColors.textLow, text: 'pkgdist.empty_period'.tr())
      else ...[
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: ReportExportBar(
            title: 'pkgdist.title'.tr(),
            subtitle: _range.label,
            fileNameBase: 'package-distribution',
            columns: _exportColumns,
            rows: _exportRows,
          ),
        ),
        const SizedBox(height: Sp.sm),
        if (desk)
          DeskGrid(minTileWidth: 320, spacing: Sp.md, children: cards)
        else
          for (final c in cards) ...[c, const SizedBox(height: Sp.sm)],
      ],
      const SizedBox(height: Sp.md),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(LucideIcons.info, size: 14, color: AppColors.textLow),
          ),
          const SizedBox(width: 6),
          Expanded(child: Text('pkgdist.footnote'.tr(), style: AppType.micro(color: AppColors.textLow))),
        ],
      ),
    ];
  }
}

class _KpiGrid extends StatelessWidget {
  const _KpiGrid({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i += 2) {
      final pair = children.sublist(
          i, i + 2 > children.length ? children.length : i + 2);
      rows.add(Padding(
        padding: EdgeInsets.only(top: i == 0 ? 0 : Sp.sm),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: pair[0]),
              if (pair.length > 1) ...[
                const SizedBox(width: Sp.sm),
                Expanded(child: pair[1])
              ],
            ],
          ),
        ),
      ));
    }
    return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch, children: rows);
  }
}

class _Kpi extends StatelessWidget {
  const _Kpi({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
    this.hint,
    this.valueColor,
  });

  final IconData icon;
  final Color color;
  final String label;
  final String value;
  final String? hint;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(Sp.md),
      decoration: DesktopScope.of(context)
          ? DeskCard.decoration(radius: R.md)
          : BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(R.md),
              border: Border.all(color: AppColors.border),
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(R.sm)),
                child: Icon(icon, size: 15, color: color),
              ),
              const SizedBox(width: Sp.sm),
              Expanded(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.micro(color: AppColors.textMid)),
              ),
            ],
          ),
          const SizedBox(height: Sp.sm),
          // يتقلّص ولا يُقصّ: مبلغٌ مبتورٌ يُقرأ خطأً.
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              value,
              maxLines: 1,
              style: AppType.title(color: valueColor ?? AppColors.textHi)
                  .copyWith(fontSize: 17, fontWeight: FontWeight.w700),
            ),
          ),
          if (hint != null) ...[
            const SizedBox(height: 2),
            Text(hint!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppType.micro(color: AppColors.textLow)),
          ],
        ],
      ),
    );
  }
}

/// باقةٌ مطويّة: العنوان اسمها وعدد مشتركيها وتحته حركاتها (فعّال · تفعيل · تمديد) وشريط حصّتها؛ النقر يفتح تفاصيلها.
class _PackageCard extends StatelessWidget {
  const _PackageCard({
    required this.row,
    required this.owner,
    required this.money,
    required this.signed,
    required this.count,
    required this.profitColor,
    required this.maxSubs,
    required this.expanded,
    required this.onToggle,
  });

  final PackageReportRow row;
  final bool owner;
  final String Function(num?) money;
  final String Function(num?) signed;
  final String Function(int?) count;
  final Color Function(num?) profitColor;
  final int maxSubs;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final r = row;
    final cells = <({String label, String value, Color? color})>[
      (
        label: 'pkgdist.active'.tr(),
        value: count(r.subscribersActive),
        color: null
      ),
      (
        label: 'pkgdist.activations'.tr(),
        value: count(r.activations),
        color: null
      ),
      (
        label: 'pkgdist.extensions'.tr(),
        value: count(r.extensions),
        color: null
      ),
      (label: 'pkgdist.price'.tr(), value: money(r.price), color: null),
      (label: 'pkgdist.revenue'.tr(), value: money(r.revenue), color: null),
      if (owner)
        (label: 'pkgdist.cost'.tr(), value: money(r.cost), color: null),
      if (owner)
        (
          label: 'pkgdist.profit_total'.tr(),
          value: signed(r.profitTotal),
          color: profitColor(r.profitTotal)
        ),
      if (owner)
        (
          label: 'pkgdist.profit_est'.tr(),
          value: signed(r.profitEstimated),
          color: profitColor(r.profitEstimated)
        ),
    ];
    final moves = r.extensions > 0
        ? 'pkgdist.row_head_ext'.tr(namedArgs: {
            'active': count(r.subscribersActive),
            'acts': count(r.activations),
            'ext': count(r.extensions),
          })
        : 'pkgdist.row_head'.tr(namedArgs: {
            'active': count(r.subscribersActive),
            'acts': count(r.activations),
          });
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: DesktopScope.of(context)
          ? DeskCard.decoration(radius: R.md)
          : BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(R.md),
              border: Border.all(color: AppColors.border),
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: onToggle,
              child: Padding(
                padding: const EdgeInsets.all(Sp.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            r.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppType.label(
                                    color: r.isAggregate
                                        ? AppColors.textLow
                                        : AppColors.textHi)
                                .copyWith(fontSize: 14, fontWeight: FontWeight.w700),
                          ),
                        ),
                        const SizedBox(width: Sp.sm),
                        Text(
                          'pkgdist.subscriber_n'
                              .tr(namedArgs: {'n': count(r.subscribersTotal)}),
                          style: AppType.label(color: AppColors.textMid)
                              .copyWith(fontSize: 12.5, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(width: Sp.xs),
                        AnimatedRotation(
                          turns: expanded ? 0.5 : 0,
                          duration: const Duration(milliseconds: 180),
                          child: Icon(LucideIcons.chevronDown, size: 18, color: AppColors.textMid),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      moves,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.micro(color: AppColors.textMid),
                    ),
                    const SizedBox(height: Sp.xs),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(R.pill),
                      child: LinearProgressIndicator(
                        value: maxSubs > 0
                            ? ((r.subscribersTotal ?? 0) / maxSubs).clamp(0, 1).toDouble()
                            : 0,
                        minHeight: 5,
                        backgroundColor: AppColors.border,
                        color: AppColors.brand,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeInOut,
            alignment: Alignment.topCenter,
            child: !expanded
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.fromLTRB(Sp.md, 0, Sp.md, Sp.md),
                    child: LayoutBuilder(
            builder: (context, c) {
              final cols = c.maxWidth >= 420 ? 4 : 3;
              final w = (c.maxWidth - (cols - 1) * Sp.sm) / cols;
              return Wrap(
                spacing: Sp.sm,
                runSpacing: Sp.sm,
                children: [
                  for (final cell in cells)
                    SizedBox(
                      width: w,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(cell.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppType.micro(color: AppColors.textLow)),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: AlignmentDirectional.centerStart,
                            child: Text(
                              cell.value,
                              maxLines: 1,
                              style: AppType.label(
                                      color: cell.color ?? AppColors.textHi)
                                  .copyWith(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              );
            },
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.color, required this.text, this.onDismiss});

  final IconData icon;
  final Color color;
  final String text;

  /// تنبيهٌ يُخفى بـ× (الأزرق) — بلا هذا ثابت (التحذيرات).
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: Sp.sm),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(R.md),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(icon, size: 15, color: color)),
          const SizedBox(width: Sp.sm),
          Expanded(
              child: Text(text,
                  style: AppType.label(color: AppColors.textHi)
                      .copyWith(fontSize: 12.5))),
          if (onDismiss != null)
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
