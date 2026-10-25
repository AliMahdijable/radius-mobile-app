import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../api/package_report_api.dart';
import '../../core/util/format.dart';
import '../../services/merged_mode.dart';
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
/// النطاق نطاق تقارير التطبيق (المدير المسجّل، loadScopeUserIds)؛ «كل الشركات»: الشركة المختارة في الشريط موجَّهاً.
class PackageDistributionScreen extends StatefulWidget {
  const PackageDistributionScreen({super.key});

  @override
  State<PackageDistributionScreen> createState() =>
      _PackageDistributionScreenState();
}

class _PackageDistributionScreenState extends State<PackageDistributionScreen> {
  static const _perm = 'reports.financial';

  late DateRange _range = _last30();
  ReportFilters _filters = const ReportFilters();
  PackageReport? _data;
  String? _error;
  bool _loading = false;
  bool _requested = false;
  int _gen = 0;

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
    _maybeLoad();
  }

  @override
  void dispose() {
    PermissionsService.changes.removeListener(_maybeLoad);
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
    final focused = MergedMode.active.value ? MergedMode.focused : null;
    final ids = focused == null ? await loadScopeUserIds() : null;
    final r = await PackageReportApi.fetch(
      from: _range.from,
      to: _range.to,
      userIds: ids,
      employeeId: _filters.employeeId,
      companyKey: focused?.key,
    );
    if (!mounted || gen != _gen) return;
    setState(() {
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
        'pkgdist.card_title'.tr(),
        'pkgdist.subscribers_now'.tr(),
        'pkgdist.active'.tr(),
        'pkgdist.activations'.tr(),
        'pkgdist.extensions'.tr(),
        'pkgdist.price'.tr(),
        'pkgdist.revenue'.tr(),
        if (_data?.owner == true) ...[
          'pkgdist.unit_cost'.tr(),
          'pkgdist.cost'.tr(),
          'pkgdist.profit_total'.tr(),
          'pkgdist.profit_est'.tr(),
        ],
      ];

  List<List<String>> get _exportRows => [
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
                DateRangeChipBar(
                  value: _range,
                  onChanged: (r) {
                    setState(() => _range = r);
                    _load();
                  },
                ),
                const SizedBox(height: Sp.sm),
                // الموظّف المنفِّذ وحده: لا نوع حركة (التقرير تفعيلٌ وتمديد) ولا مدير (النطاق من الخادم).
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
            maxSubs: _maxSubs(d)),
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
      if (d.owner &&
          !d.costExempt &&
          t.cost != null &&
          t.costComplete == false &&
          (t.costRows ?? 0) > 0) ...[
        const SizedBox(height: Sp.sm),
        _Notice(
          icon: LucideIcons.info,
          color: AppColors.info,
          text: 'pkgdist.cost_partial'.tr(namedArgs: {
            'known': _count(t.costKnownRows),
            'rows': _count(t.costRows)
          }),
        ),
      ],
      if (d.owner && t.estimateMissingPackages > 0) ...[
        const SizedBox(height: Sp.sm),
        _Notice(
          icon: LucideIcons.info,
          color: AppColors.info,
          text: 'pkgdist.estimate_missing'
              .tr(namedArgs: {'n': '${t.estimateMissingPackages}'}),
        ),
      ],
      if (d.subscribersPartial) ...[
        const SizedBox(height: Sp.sm),
        _Notice(
            icon: LucideIcons.info,
            color: AppColors.info,
            text: 'pkgdist.partial'.tr()),
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

class _PackageCard extends StatelessWidget {
  const _PackageCard({
    required this.row,
    required this.owner,
    required this.money,
    required this.signed,
    required this.count,
    required this.profitColor,
    required this.maxSubs,
  });

  final PackageReportRow row;
  final bool owner;
  final String Function(num?) money;
  final String Function(num?) signed;
  final String Function(int?) count;
  final Color Function(num?) profitColor;
  final int maxSubs;

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
            ],
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
          const SizedBox(height: Sp.sm),
          LayoutBuilder(
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
        ],
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.color, required this.text});

  final IconData icon;
  final Color color;
  final String text;

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
        ],
      ),
    );
  }
}
