import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../api/reports_api.dart';
import '../../../core/util/ar_date.dart';
import '../../../core/util/format.dart';
import '../../../core/util/order_rules.dart';
import '../../../core/util/server_time.dart';
import '../../../services/merged_mode.dart';
import '../../../services/pay_kinds.dart';
import '../../../services/transfer_pay.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';
import '../../../widgets/company_tag.dart';
import '../../desktop/desk_widgets.dart';
import '../widgets/action_labels.dart';
import '../widgets/report_export.dart';
import '../widgets/report_filters.dart';
import '../widgets/report_permission_gate.dart';
import 'report_kit.dart';
import 'report_period.dart';
import 'report_prefs.dart';
import 'report_sheets.dart';
import '../../../services/employee_visibility.dart';

/// «كشف حساب المشترك» على الشكل الموحّد (٢٢ نوفمبر — «كمل بقية التقارير»). الأرقام كما كانت حرفاً ([StatementSummary]: المدفوع
/// بالفترة، والدين من دفتره/ملاحظاته، والصافي = المدفوع − الدين — معناها قرار المالك لا الشكل)؛ يتغيّر الشكل: الفترات الجاهزة (آخر
/// 90 يوماً أوّل مرّة كما كان)، ورقة الأنواع، الحركات يوماً يوماً بـ«الدين بعدها»، وبحث، والتصدير بالفلاتر حرفاً.
class AccountStatementV2Screen extends StatefulWidget {
  const AccountStatementV2Screen({
    super.key,
    required this.username,
    required this.companyKey,
    this.displayName,
    this.phone,
  });
  final String username;
  final String? displayName;
  final String? phone;

  /// شركة المشترك («كل الشركات»): مفتاح صفّه ⇒ الكشف من شركته، وبلاه في الوضع ⇒ المفتوحة صراحةً ([MergedOps.pinned]).
  final String? companyKey;

  @visibleForTesting
  static DateTime Function() clock = DateTime.now;

  /// بطاقات الكشف في رأس الـPDF حين تصف السطور المصدَّرة نفسها: الملخّص حساب المشترك كلّه (من الخادم) ⇒ لا بحث ولا «طريقة الدفع»
  /// تحصر الحركات، وإلّا قال الرأس رقماً غير ما في الجدول.
  @visibleForTesting
  static bool summaryFits({required String query, required Set<String> pays}) => query.trim().isEmpty && pays.isEmpty;

  @override
  State<AccountStatementV2Screen> createState() => _StatementV2State();
}

class _StatementV2State extends State<AccountStatementV2Screen> {
  static const _id = 'account_statement';
  static const _page = 40;

  RpFilterValue? _f;
  StatementResponse? _data;
  bool _loading = true;
  String? _error;
  int _seq = 0;
  String _q = '';
  int _visible = _page;

  /// «رتّب حسب» فوق الحركات (المالك ٢٣ نوفمبر) — القواعد كالموقع حرفاً (core/util/order_rules.dart)، والمفتاح نفسه.
  static const _rowFields = [
    rpDateField,
    OrderField('amount', 'المبلغ', OrderKind.number),
    OrderField('type', 'النوع', OrderKind.text),
  ];
  OrderValue _rowSort = rpDateDesc;

  DateTime get _now => AccountStatementV2Screen.clock();
  // «ما يراه الموظّف»: اليوزر مخفيّ ⇒ الاسم وإلّا «بلا اسم»، ولا يوزر بالرأس ولا بالتصدير
  String get _name => Sees.usernames ? (widget.displayName ?? widget.username) : Sees.nameOf(widget.displayName, widget.username);

  @override
  void initState() {
    super.initState();
    unawaited(OrderPrefs.load(OrderPrefs.rowsKey(_id), _rowFields, rpDateDesc).then((v) {
      if (mounted && v != _rowSort) setState(() => _rowSort = v);
    }));
    // «طريقة الدفع» (٢٤ نوفمبر): الورقة تعرضها حين تُفتح «الحوالات» للصفحة (الفلتر محلّيّ — بلا طلب)
    TransferPay.available.addListener(_onTp);
    unawaited(TransferPay.refresh());
    unawaited(_start());
  }

  @override
  void dispose() {
    TransferPay.available.removeListener(_onTp);
    super.dispose();
  }

  void _onTp() {
    if (mounted) setState(() {});
  }

  /// لكشف الشركة المفتوحة حين فُتحت لها «الحوالات».
  List<(String, String)> get _payKinds => widget.companyKey == null && TransferPay.available.value ? PayKinds.options() : const [];
  Set<String> get _paysSet => _payKinds.isEmpty ? const {} : (_f?.pays ?? const {});

  /// «رتّب حسب»: نقرة حقل — يرتّب أو يقلب، ويرجع لأوّل الصفحة، ويُحفظ للتقرير.
  void _pickSort(String key) {
    for (final f in _rowFields) {
      if (f.key != key) continue;
      final next = nextOrder(_rowSort, f);
      setState(() {
        _rowSort = next;
        _visible = _page;
      });
      unawaited(OrderPrefs.save(OrderPrefs.rowsKey(_id), next));
      return;
    }
  }

  static Object? _rowValue(StatementRow r, String k) => switch (k) {
        'amount' => r.amount == 0 ? null : r.amount.abs(),
        'type' => arabicActionLabel(r.actionType ?? '', r.description ?? ''),
        _ => null,
      };

  static String? _dateOf(StatementRow r) {
    final t = _time(r);
    return t == null ? null : iqDateOf(t);
  }

  Future<void> _start() async {
    // فترة الكشف وأنواعه تُحفظ (لا مدراء فيه ولا شركات)
    final f = await RpPrefs.load(_id, now: _now, fallback: RpPreset.last90);
    if (!mounted) return;
    setState(() => _f = f.copyWith(compare: false, managers: const {}, employees: const {}, companies: const {}));
    _load();
  }

  Future<void> _load() async {
    final seq = ++_seq;
    final f = _f!;
    setState(() {
      _loading = true;
      _error = null;
    });
    final r = await MergedOps.pinned(
      widget.companyKey,
      () => ReportsApi.accountStatement(
        username: widget.username,
        from: f.range.from,
        to: f.range.to,
        actionTypes: f.types.isEmpty ? null : f.types,
      ),
    );
    if (!mounted || seq != _seq) return;
    setState(() {
      _loading = false;
      _data = r.data;
      _error = r.ok ? null : (r.error ?? 'common.load_failed'.tr());
      _visible = _page;
    });
  }

  void _apply(RpFilterValue v) {
    final f = v.copyWith(compare: false, managers: const {}, employees: const {}, companies: const {});
    setState(() => _f = f);
    unawaited(RpPrefs.save(_id, f));
    _load();
  }

  Future<void> _openFilters() async {
    final f = _f!;
    final v = await showModalBottomSheet<RpFilterValue>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: AppColors.scrim,
      builder: (ctx) => RpFilterSheet(
        subtitle: 'كشف حساب · $_name',
        initial: f,
        now: _now,
        people: const [],
        showPeople: false,
        showCompare: false,
        types: [for (final t in kAccountStatementActionTypes) (t.key, t.displayLabel)],
        payKinds: _payKinds,
      ),
    );
    if (v != null && mounted) _apply(v);
  }

  List<RpChip> _chips() {
    final f = _f!;
    final labels = [
      for (final t in kAccountStatementActionTypes)
        if (f.types.contains(t.key)) t.displayLabel,
    ];
    final pays = _paysSet;
    return [
      if (f.types.isNotEmpty) RpChip('النوع: ${labels.join('، ')}', onRemove: () => _apply(f.copyWith(types: const []))),
      if (pays.isNotEmpty) RpChip(PayKinds.chip(pays), onRemove: () => _apply(f.copyWith(pays: const {}))),
    ];
  }

  // ═══════════════ السطور ═══════════════

  static DateTime? _time(StatementRow r) => parseServerUtc(r.createdAt);

  RpRow _row(StatementRow r) {
    final at = (r.actionType ?? '').toUpperCase().trim();
    final desc = (r.description ?? '').trim();
    final label = arabicActionLabel(r.actionType ?? '', desc);
    final (icon, tone) = switch (at) {
      'SUBSCRIBER_ACTIVATE' || 'SUBSCRIBER_ADD' => desc.contains('غير نقدي') ? (LucideIcons.creditCard, RpTone.debt) : (LucideIcons.zap, RpTone.money),
      'SUBSCRIBER_EXTEND' => (LucideIcons.repeat, RpTone.info),
      'DEBT_PAY' || 'BALANCE_DEDUCT' || 'PAYMENT_ADD' => (LucideIcons.banknote, RpTone.money),
      'BALANCE_ADD' => (LucideIcons.plus, RpTone.debt),
      _ => (LucideIcons.activity, RpTone.neutral),
    };
    final t = _time(r);
    return RpRow(
      icon: icon,
      tone: tone,
      title: label,
      detail: [if (desc.isNotEmpty && desc != label) desc, if ((r.adminName ?? '').isNotEmpty) r.adminName!].join(' · '),
      amount: r.amount == 0 ? null : r.amount.abs(),
      time: t == null ? '' : clock12Ar(t),
      balanceAfter: r.balanceAfter,
    );
  }

  List<StatementRow> _search(List<StatementRow> rows) {
    // «طريقة الدفع» قبل البحث — سطوره بطريقتها (pay_kind)
    final pays = _paysSet;
    if (pays.isNotEmpty) rows = rows.where((r) => pays.contains(r.payKind)).toList();
    final needle = (normalizeDigits(_q) ?? '').trim().toLowerCase();
    if (needle.isEmpty) return rows;
    bool hit(String? s) => (normalizeDigits(s) ?? '').toLowerCase().contains(needle);
    return rows.where((r) => hit(r.description) || hit(r.adminName) || hit(arabicActionLabel(r.actionType ?? '', r.description ?? ''))).toList();
  }

  List<RpDay> _days(List<StatementRow> rows, {int? limit}) {
    final byDay = <String, List<StatementRow>>{};
    final order = <String>[];
    for (final r in rows) {
      final t = _time(r);
      final key = t == null ? '' : iqDateOf(t);
      if (!byDay.containsKey(key)) order.add(key);
      (byDay[key] ??= []).add(r);
    }
    num paid(StatementRow r) {
      final at = (r.actionType ?? '').toUpperCase().trim();
      return at == 'DEBT_PAY' || at == 'BALANCE_DEDUCT' || at == 'PAYMENT_ADD' ? r.amount.abs() : 0;
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
        sum: all.fold<num>(0, (a, r) => a + paid(r)),
        rows: [for (final r in shown) _row(r)],
      ));
    }
    return out;
  }

  /// الرقم الكبير وبطاقات الكشف — نفسها على الشاشة وفي رأس الـPDF.
  RpKpi _heroKpi(StatementResponse d) {
    final b = d.summary.balance;
    return RpKpi(
      label: b < 0 ? 'reports.owes_manager'.tr() : 'reports.has_credit'.tr(),
      value: b.abs(),
      icon: b < 0 ? LucideIcons.trendingDown : LucideIcons.trendingUp,
      tone: b < 0 ? RpTone.loss : RpTone.money,
    );
  }

  List<RpKpi> _gridKpis(StatementResponse d) {
    final s = d.summary;
    return [
      RpKpi(label: 'reports.paid'.tr(), value: s.totalPayments, icon: LucideIcons.banknote, tone: RpTone.money),
      RpKpi(label: 'subscribers.debt_short'.tr(), value: s.totalDebt, icon: LucideIcons.creditCard, tone: RpTone.debt, upIsGood: false),
      RpKpi(label: 'reports.activations_count'.tr(), value: s.totalActivations, icon: LucideIcons.zap, tone: RpTone.brand, isCount: true),
      RpKpi(label: 'reports.movements_count'.tr(), value: s.totalTransactions, icon: LucideIcons.history, tone: RpTone.info, isCount: true),
    ];
  }

  // ═══════════════ التصدير ═══════════════

  Future<void> _export(String how) async {
    final d = _data;
    if (d == null || _loading) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('انتظر حتى يكتمل الكشف ثمّ صدّر')));
      return;
    }
    // الملفّ بترتيب الشاشة («رتّب حسب»)
    final rows = sortList(_search(d.rows), _rowSort, _rowFields, _rowValue);
    // ترتيب الأعمدة (2026-07-12): الاسم ثمّ اليوزر ثمّ المبلغ/التاريخ/الوصف/النوع/المنفّذ — ومعها «الدين بعدها»
    final data = [
      for (final r in rows)
        [
          _name,
          Sees.usernames ? widget.username : kHiddenWord,
          r.amount == 0 ? '' : '${r.amount}',
          exportTimeAr(r.createdAt),
          (r.description ?? '').replaceAll('\n', ' '),
          arabicActionLabel(r.actionType ?? '', r.description ?? ''),
          r.adminName ?? '',
          r.balanceAfter == null ? '' : rpBalanceText(r.balanceAfter!),
        ],
    ];
    final columns = [
      'reports.col_subscriber'.tr(),
      'reports.col_username'.tr(),
      'reports.col_amount'.tr(),
      'reports.col_date'.tr(),
      'reports.col_description'.tr(),
      'reports.col_type'.tr(),
      'reports.col_executor'.tr(),
      'الرصيد بعدها',
    ];
    final company = MergedMode.rowCompanyName(widget.companyKey);
    final details = [
      Sees.usernames ? 'المشترك: $_name (${widget.username})' : 'المشترك: $_name',
      if (company != null) 'الشركة: $company',
      for (final c in _chips()) c.label,
      if (_q.trim().isNotEmpty) 'بحث: «${_q.trim()}»',
      if (_rowSort != rpDateDesc) orderLine(_rowFields, _rowSort) ?? '',
      'عدد الحركات: ${data.length}',
    ];
    final title = 'reports.account_statement'.tr();
    final subtitle = '${_f!.range.name} · ${_f!.range.rangeText}';
    const weights = [2.0, 1.3, 1.1, 1.4, 2.6, 1.1, 1.2, 1.6];
    final summary = AccountStatementV2Screen.summaryFits(query: _q, pays: _paysSet) ? rpPdfSummary([_heroKpi(d), ..._gridKpis(d)]) : const <PdfStat>[];
    switch (how) {
      case 'pdf':
        return ReportExportActions.pdf(context,
            title: title, subtitle: subtitle, details: details, columns: columns, rows: data, columnWeights: weights, fileNameBase: 'statement',
            summary: summary);
      case 'excel':
        return ReportExportActions.csv(context,
            title: title, subtitle: subtitle, details: details, columns: columns, rows: data, fileNameBase: 'statement');
      default:
        return ReportExportActions.sharePdf(context,
            title: title, subtitle: subtitle, details: details, columns: columns, rows: data, columnWeights: weights, fileNameBase: 'statement',
            summary: summary);
    }
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return ReportPermissionGate(
      permission: 'reports.account_statement',
      title: 'reports.account_statement'.tr(),
      companyKey: widget.companyKey,
      child: Scaffold(
        backgroundColor: AppColors.bg,
        appBar: deskPageBar(
          context,
          mobile: AppBar(
            backgroundColor: AppColors.surface,
            elevation: 0,
            scrolledUnderElevation: 0,
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('reports.account_statement'.tr(), style: AppType.title(color: AppColors.textHi).copyWith(fontSize: 16)),
                Text(Sees.usernames ? '$_name · ${widget.username}' : _name,
                    style: AppType.micro(color: AppColors.textMid), maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
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
      if (widget.companyKey != null && MergedMode.active.value) CompanyTag(companyKey: widget.companyKey!, fontSize: 11),
      // الرأس بسطرٍ واحد (المالك ٢٢ نوفمبر): الفترة و«الفلاتر»، وشاراتها تحته
      RpHeader(
        period: RpPeriod(name: f.range.name, range: f.range.rangeText),
        onPeriod: _openFilters,
        chips: _chips(),
        onFilters: _openFilters,
        onClear: () => _apply(f.cleared()),
      ),
    ];
    final d = _data;
    if (_loading && d == null) {
      parts.add(const Padding(padding: EdgeInsets.symmetric(vertical: Sp.huge), child: Center(child: CircularProgressIndicator())));
      return _gapped(parts);
    }
    if (d == null) {
      parts.add(RpCard(
        child: Column(
          children: [
            Icon(LucideIcons.triangleAlert, size: 28, color: AppColors.error),
            const SizedBox(height: Sp.sm),
            Text(_error ?? 'common.load_failed'.tr(), textAlign: TextAlign.center, style: AppType.body(color: AppColors.textMid)),
            const SizedBox(height: Sp.md),
            OutlinedButton.icon(onPressed: _load, icon: const Icon(LucideIcons.refreshCw, size: 16), label: Text('common.retry'.tr())),
          ],
        ),
      ));
      return _gapped(parts);
    }
    parts.add(RpHeroKpi(
      kpi: _heroKpi(d),
      compareWith: '',
      spark: const [],
      note: 'المدفوع بالفترة − الدين الحاليّ (كما كان الكشف يحسبه)',
    ));
    parts.add(RpKpiGrid(compareWith: '', kpis: _gridKpis(d)));
    final rows = sortList(_search(d.rows), _rowSort, _rowFields, _rowValue);
    parts.add(RpRowsCard(
      query: _q,
      total: rows.length,
      // بالتاريخ يوماً بيوم كما كانت؛ وبغيره قائمةٌ واحدة وتاريخ كلّ سطرٍ عليه
      days: _rowSort.key == 'date' ? _days(rows, limit: _visible) : rpFlat(rows, _visible, _row, _dateOf),
      sort: RpRowsSort(fields: _rowFields, value: _rowSort, onPick: _pickSort),
      more: rows.length > _visible ? 'عرض المزيد (${rows.length - _visible})' : null,
      onMore: () => setState(() => _visible += _page),
      onSearch: (q) => setState(() {
        _q = q;
        _visible = _page;
      }),
      empty: _q.trim().isEmpty ? 'لا حركات بهذه الفترة' : 'لا حركة تطابق «${_q.trim()}»',
    ));
    parts.add(RpExportBar(onPdf: () => _export('pdf'), onExcel: () => _export('excel'), onShare: () => _export('share')));
    return _gapped(parts);
  }

  List<Widget> _gapped(List<Widget> parts) => [
        for (var i = 0; i < parts.length; i++) ...[if (i > 0) const SizedBox(height: Sp.md), parts[i]],
      ];
}
