import 'package:easy_localization/easy_localization.dart';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../api/reports_api.dart';
import '../../core/util/format.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import 'widgets/action_labels.dart';
import 'widgets/date_range_chip.dart';
import 'widgets/report_export.dart';
import 'widgets/report_filters.dart';
import 'widgets/report_log_tile.dart';
import 'widgets/report_pagination.dart';
import 'widgets/report_permission_gate.dart';

/// كشف حساب مشترك — الحركات المالية (تفعيل/تمديد/تسديد/إضافة دين) في
/// فترة محدّدة + summary لإجمالي المدفوع/الدين/الرصيد.
class AccountStatementScreen extends StatefulWidget {
  const AccountStatementScreen({
    super.key,
    required this.username,
    this.displayName,
    this.phone,
  });
  final String username;
  final String? displayName;
  final String? phone;

  @override
  State<AccountStatementScreen> createState() => _AccountStatementScreenState();
}

class _AccountStatementScreenState extends State<AccountStatementScreen> {
  DateRange _range = DateRange.last3Months();
  StatementResponse? _data;
  bool _loading = true;
  String? _error;
  int _page = 0;
  int _pageSize = 25;

  /// فلتر الأنواع فقط (المشترك محدّد سلفاً — لا حاجة لفلاتر مدير/موظف).
  ReportFilters _filters = const ReportFilters();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final r = await ReportsApi.accountStatement(
      username: widget.username,
      from: _range.from,
      to: _range.to,
      actionTypes: _filters.actionTypes,
    );
    if (!mounted) return;
    setState(() {
      _loading = false;
      _data = r.data;
      _error = r.ok ? null : (r.error ?? 'common.load_failed'.tr());
      _page = 0;
    });
  }

  List<List<String>> _exportRows(List<StatementRow> rows) {
    // كشف الحساب scoped لمشترك واحد — الاسم يُكتب مرّة واحدة بأول عمودين
    // (اتّساقاً مع بقية التقارير 2026-07-12) ثم مبلغ/تاريخ/وصف/نوع/منفّذ.
    // النوع يُترجَم لعربي بدل SUBSCRIBER_ACTIVATE الإنجليزي.
    final displayName = widget.displayName ?? widget.username;
    return rows
        .map((r) => [
              displayName,
              widget.username,
              r.amount == 0 ? '' : r.amount.toString(),
              r.createdAt,
              (r.description ?? '').replaceAll('\n', ' '),
              arabicActionLabel(r.actionType ?? '', r.description ?? ''),
              r.adminName ?? '',
            ])
        .toList();
  }

  static const List<double> _pdfWeights = [2.2, 1.4, 1.2, 1.4, 2.6, 1.1, 1.3];

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final rows = _data?.rows ?? const <StatementRow>[];
    final summary = _data?.summary ?? const StatementSummary();
    final totalPages = (rows.length / _pageSize).ceil().clamp(1, 99999);
    final pageStart = _page * _pageSize;
    final pageEnd = (pageStart + _pageSize).clamp(0, rows.length);
    final pageRows = rows.isEmpty
        ? const <StatementRow>[]
        : rows.sublist(pageStart, pageEnd);

    return ReportPermissionGate(
      permission: 'reports.account_statement',
      title: 'reports.account_statement'.tr(),
      child: Scaffold(
        backgroundColor: AppColors.bg,
        appBar: AppBar(
          backgroundColor: AppColors.surface,
          elevation: 0,
          scrolledUnderElevation: 0,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'reports.account_statement'.tr(),
                style: AppType.title(color: AppColors.textHi)
                    .copyWith(fontSize: 15, fontWeight: FontWeight.w800),
              ),
              Text(
                widget.displayName ?? widget.username,
                style: AppType.muted().copyWith(fontSize: 11),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
          iconTheme: IconThemeData(color: AppColors.textHi),
        ),
        body: SafeArea(
          child: RefreshIndicator(
            onRefresh: _load,
            color: AppColors.brand,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, Sp.huge),
              children: [
                DateRangeChipBar(
                  value: _range,
                  onChanged: (r) {
                    setState(() => _range = r);
                    _load();
                  },
                ),
                const SizedBox(height: Sp.sm),
                ReportFiltersPanel(
                  value: _filters,
                  actionTypeOptions: kAccountStatementActionTypes,
                  // المشترك محدّد سلفاً — لا نحتاج مدير/موظف.
                  includeActionManager: false,
                  includeUserManager: false,
                  includeEmployee: false,
                  onChanged: (v) {
                    setState(() {
                      _filters = v;
                      _page = 0;
                    });
                    _load();
                  },
                ),
                const SizedBox(height: Sp.md),
                _summaryCard(summary),
                const SizedBox(height: Sp.md),
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: Sp.huge),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_error != null)
                  _errorBlock()
                else if (rows.isEmpty)
                  _emptyBlock()
                else ...[
                  Row(
                    children: [
                      Expanded(
                        child: ReportStatsBar(
                          totalItems: rows.length,
                          pageStart: pageStart,
                          pageEnd: pageEnd,
                          pageSize: _pageSize,
                          onPageSizeChange: (s) => setState(() {
                            _pageSize = s;
                            _page = 0;
                          }),
                        ),
                      ),
                      ReportExportBar(
                        title:
                            '${'reports.account_statement'.tr()} — ${widget.displayName ?? widget.username}',
                        subtitle:
                            '${_dateStr(_range.from)} → ${_dateStr(_range.to)}',
                        fileNameBase:
                            'account_statement_${widget.username.replaceAll(RegExp(r"[^a-zA-Z0-9_]"), "_")}',
                        columns: [
                          'reports.col_subscriber'.tr(),
                          'reports.col_username'.tr(),
                          'reports.col_amount'.tr(),
                          'reports.col_date'.tr(),
                          'reports.col_description'.tr(),
                          'reports.col_type'.tr(),
                          'reports.col_executor'.tr(),
                        ],
                        columnWeights: _pdfWeights,
                        rows: _exportRows(rows),
                      ),
                    ],
                  ),
                  const SizedBox(height: Sp.sm),
                  for (final r in pageRows) ...[
                    ReportLogTile(
                      actionType: r.actionType ?? '',
                      description: r.description ?? '',
                      amount: r.amount,
                      adminUsername: r.adminName,
                      targetName: widget.displayName ?? widget.username,
                      createdAt: r.createdAt,
                    ),
                    const SizedBox(height: 4),
                  ],
                  if (totalPages > 1)
                    ReportPager(
                      page: _page,
                      totalPages: totalPages,
                      onPrev: () => setState(() => _page--),
                      onNext: () => setState(() => _page++),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// بطاقة الملخّص — المخطّط يجعلها بطاقة براند داكنة r22 لا كارتاً
  /// أبيض: الرصيد بارز 24/w700 مع حبّة المدى في الطرف، وتحته صفّ
  /// إحصاءات غاطس بفواصل شعريّة.
  ///
  /// طبقاتها `onBrand*` ثابتة في الوضعين — لا تحتاج تعديلاً في الوضع
  /// الداكن.
  Widget _summaryCard(StatementSummary s) {
    final balance = s.balance;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.brandSurface,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      balance < 0
                          ? 'reports.owes_manager'.tr()
                          : 'reports.has_credit'.tr(),
                      style: AppType.muted(color: AppColors.onBrandSecondary)
                          .copyWith(fontSize: 11.5),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${balance < 0 ? '-' : ''}${formatIQD(balance.abs())} د.ع',
                      textDirection: ui.TextDirection.ltr,
                      style: AppType.amount(
                        color: balance < 0
                            ? AppColors.onBrandDanger
                            : AppColors.onBrand,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: Sp.sm),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 11, vertical: Sp.x6),
                decoration: BoxDecoration(
                  color: AppColors.onBrandFill2,
                  borderRadius: BorderRadius.circular(R.pill),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      balance < 0
                          ? LucideIcons.trendingDown
                          : LucideIcons.trendingUp,
                      size: 15,
                      color: AppColors.onBrand,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      '${_dateStr(_range.from)} → ${_dateStr(_range.to)}',
                      textDirection: ui.TextDirection.ltr,
                      style: AppType.bodyStrong(color: AppColors.onBrand)
                          .copyWith(fontSize: 11.5),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: Sp.lg),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: Sp.xs, vertical: Sp.md),
            decoration: BoxDecoration(
              color: AppColors.onBrandFill1,
              borderRadius: BorderRadius.circular(R.lg),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _miniStat(
                    label: 'reports.paid'.tr(),
                    value: formatIQD(s.totalPayments),
                  ),
                ),
                _hair(),
                Expanded(
                  child: _miniStat(
                    label: 'subscribers.debt_short'.tr(),
                    value: formatIQD(s.totalDebt),
                    color: AppColors.onBrandDanger,
                  ),
                ),
                _hair(),
                Expanded(
                  child: _miniStat(
                    label: 'reports.activations_count'.tr(),
                    value: '${s.totalActivations}',
                  ),
                ),
                _hair(),
                Expanded(
                  child: _miniStat(
                    label: 'reports.movements_count'.tr(),
                    value: '${s.totalTransactions}',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _hair() =>
      Container(width: 1, height: 30, color: AppColors.onBrandFill2);

  Widget _miniStat({
    required String label,
    required String value,
    Color? color,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          textDirection: ui.TextDirection.ltr,
          style: AppType.cardTitle(color: color ?? AppColors.onBrand)
              .copyWith(fontWeight: FontWeight.w700),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: Sp.xxs),
        Text(
          label,
          style: AppType.micro(color: AppColors.onBrandSecondary),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  Widget _emptyBlock() => Padding(
        padding: const EdgeInsets.symmetric(vertical: Sp.huge),
        child: Center(
          child: Column(
            children: [
              Icon(LucideIcons.fileText, size: 36, color: AppColors.textLow),
              const SizedBox(height: 10),
              Text('reports.no_movements_period'.tr(),
                  style: AppType.label(color: AppColors.textMid)),
            ],
          ),
        ),
      );

  Widget _errorBlock() => Padding(
        padding: const EdgeInsets.symmetric(vertical: Sp.xl),
        child: Center(
          child: Column(
            children: [
              Icon(LucideIcons.triangleAlert, size: 32, color: AppColors.error),
              const SizedBox(height: 8),
              Text(_error!, style: AppType.subtitle(color: AppColors.textMid)),
              const SizedBox(height: Sp.md),
              ElevatedButton.icon(
                onPressed: _load,
                icon: const Icon(LucideIcons.refreshCw, size: 16),
                label: Text('common.retry'.tr()),
              ),
            ],
          ),
        ),
      );

  static String _dateStr(DateTime? d) {
    if (d == null) return '';
    String p(int v) => v.toString().padLeft(2, '0');
    return '${d.year}-${p(d.month)}-${p(d.day)}';
  }
}
