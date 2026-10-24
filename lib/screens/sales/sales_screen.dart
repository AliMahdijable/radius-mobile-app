import 'dart:async';

import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../api/sales_api.dart';
import '../../core/platform/desktop_layout.dart';
import '../../core/util/ar_date.dart';
import '../../core/util/amount_input.dart';
import '../../core/util/bidi.dart';
import '../../core/util/format.dart';
import '../../core/widgets/app_sheet.dart';
import '../../core/widgets/design_sheet.dart';
import '../../core/widgets/permission_locked.dart';
import '../../core/widgets/sheet_scaffold.dart';
import '../../services/permissions_service.dart';
import '../../services/sale_print.dart';
import '../../services/subscriber_events.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import '../../widgets/merged_company_strip.dart';
import '../desktop/desk_widgets.dart';
import '../reports/widgets/date_range_chip.dart';
import '../reports/widgets/report_permission_gate.dart';
import '../../core/widgets/print_feedback.dart';

/// «المبيعات» (٢٣ أكتوبر) — `/api/v2/sales/*` (الخادم server/sales.js، الويب
/// pages/Sales.tsx). المالك: «وكيل انترنت عنده مواد يبيعها ويعرف شكد سعرها
/// يسعره وشكد يبيعها وربح الها».
///
/// تبويبان: «المبيعات» (الفترة، الربح، الإلغاء والحسم) و«الموادّ والمخزون»
/// (الشراء، الجرد، الحركات). البيع نقداً يدخل الصندوق والمحصَّل، وعلى دين
/// المشترك عبر مسار إضافة الدين نفسه بالخادم. الكلفة المتوسّطة يحسبها الخادم
/// لحظة البيع — الشاشة تعرض تقديرها فقط. المفاتيح `sales.view/sell/items/void`
/// — ما لا يملكه الموظّف يبقى بمكانه مقفلاً. «كل الشركات»: للشركة المفتوحة.
class SalesScreen extends StatefulWidget {
  const SalesScreen({super.key});

  @override
  State<SalesScreen> createState() => _SalesScreenState();
}

class _SalesScreenState extends State<SalesScreen> {
  final _search = TextEditingController();
  int _tab = 0;
  DateRange _range = DateRange.thisMonth();
  bool _showInactive = false;

  SaleItemsPage? _items;
  SalesPage? _sales;

  /// حالة تسديد المبيعات على الدين الظاهرة (بعد القائمة) — بلاها «على الدين» كما كان.
  Map<int, SaleDebtStatus> _debts = const {};

  /// قُرئت حالات كلّ المبيعات على الدين بالفترة (بلا سقفٍ ولا قائمةٍ مقصوصة) ⇒ يُعرض «الباقي» تحت «بيع بالدين».
  bool _debtsComplete = false;

  /// تغييرٌ صدر من هذه الشاشة نفسها ([_after]) — تحديثه بيدها، فلا يُعاد الجلب مرّتين.
  bool _selfChange = false;
  String? _itemsError;
  String? _salesError;
  bool _loadingItems = true;
  bool _loadingSales = true;

  @override
  void initState() {
    super.initState();
    if (Perms.has('sales.view')) {
      _loadItems();
      _loadSales();
    } else {
      _loadingItems = false;
      _loadingSales = false;
    }
    // تسديد دين مشترك (أو أيّ عمليّة عليه) من صفحته والشاشة مفتوحة تحتها ⇒ حالة بيعه («مسدّد») تُقرأ من جديد.
    SubscriberEvents.dataChanged.addListener(_onDataChanged);
  }

  @override
  void dispose() {
    SubscriberEvents.dataChanged.removeListener(_onDataChanged);
    _search.dispose();
    super.dispose();
  }

  void _onDataChanged() {
    if (!mounted || _selfChange || !Perms.has('sales.view')) return;
    _loadSales();
  }

  /// مفعّلة؟ من ردّ القائمة نفسها (المفتاح يُقرأ بالخادم).
  bool get _enabled => (_sales?.enabled ?? _items?.enabled) ?? false;

  bool get _hasData =>
      (_items?.items.isNotEmpty ?? false) || (_sales?.sales.isNotEmpty ?? false);

  Future<void> _loadItems() async {
    final r = await SalesApi.items(includeInactive: _showInactive);
    if (!mounted) return;
    setState(() {
      _loadingItems = false;
      if (r.page != null) {
        _items = r.page;
        _itemsError = null;
      } else if (_items == null) {
        _itemsError = r.error;
      }
    });
    if (r.page == null && _items != null) {
      showSheetSnack(context, r.error ?? 'sales.load_failed'.tr(), isError: true);
    }
  }

  Future<void> _loadSales() async {
    final r = await SalesApi.list(from: _day(_range.from), to: _day(_range.to));
    if (!mounted) return;
    setState(() {
      _loadingSales = false;
      if (r.page != null) {
        _sales = r.page;
        _salesError = null;
      } else if (_sales == null) {
        _salesError = r.error;
      }
    });
    if (r.page == null && _sales != null) {
      showSheetSnack(context, r.error ?? 'sales.load_failed'.tr(), isError: true);
    }
    if (r.page != null) unawaited(_loadDebts(r.page!));
  }

  /// «مسدّد» للبيع على الدين (المالك ٢٣ أكتوبر: «اسدد دين كيبل بيعت … يبقى معروض اجل») — رصيد المشترك الآن، طلبٌ واحد.
  Future<void> _loadDebts(SalesPage page) async {
    final ids = [
      for (final s in page.sales)
        if (s.isDebt && s.isDone && (s.idx ?? '').isNotEmpty) s.id,
    ];
    final r = await SalesApi.debtStatus(ids);
    if (!mounted || !identical(_sales, page)) return;
    setState(() {
      _debts = r.map;
      _debtsComplete = !r.partial && !page.truncated && ids.every(r.map.containsKey);
    });
  }

  Future<void> _refresh() => Future.wait([_loadItems(), _loadSales()]);

  /// تحت «بيع بالدين»: ما بقي منه على المشتركين الآن — حين قُرئت حالات المبيعات كلّها، وإلّا «على المشتركين» كما كان.
  String _debtSub(num sold) {
    if (sold <= 0 || !_debtsComplete) return 'sales.kpi_debt_hint'.tr();
    final left = _debts.values.fold<num>(0, (a, d) => a + d.unpaid);
    return left > 0 ? 'sales.kpi_debt_left_n'.tr(namedArgs: {'amount': _money(left)}) : 'sales.kpi_debt_paid_all'.tr();
  }

  Future<void> _after(Future<bool?> sheet) async {
    if (await sheet == true && mounted) {
      // دين المشترك والرئيسيّة يتغيّران بالبيع وإلغائه — كان يتحدّث القسم وحده فيبقى الباقي حتى سحب التحديث.
      _selfChange = true;
      SubscriberEvents.notifyChange();
      _selfChange = false;
      await _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return ReportPermissionGate(
      permission: 'sales.view',
      title: 'sales.title'.tr(),
      child: Scaffold(
        backgroundColor: AppColors.bg,
        // على الحاسبة: رأس الصفحة بزرّها (بيع جديد / مادّة جديدة) مكان الزرّ العائم — كبقيّة صفحات الأقسام.
        appBar: deskPageBar(
          context,
          mobile: AppBar(
            backgroundColor: AppColors.surface,
            elevation: 0,
            scrolledUnderElevation: 0,
            title: Text(
              'sales.title'.tr(),
              style: AppType.title(color: AppColors.textHi).copyWith(fontSize: 16),
            ),
            iconTheme: IconThemeData(color: AppColors.textHi),
          ),
          primary: _enabled ? _deskPrimary() : null,
        ),
        floatingActionButton: _enabled && !DesktopScope.of(context) ? _fab() : null,
        body: SafeArea(
          child: RefreshIndicator(
            onRefresh: _refresh,
            color: AppColors.brand,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, Sp.huge + Sp.huge),
              children: [
                const MergedOpenCompanyNote(
                  textKey: 'merged.sales_note',
                  padding: EdgeInsets.only(bottom: Sp.md),
                ),
                ..._content(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// زرّ الحاسبة: نفس فعل الزرّ العائم للتبويب المفتوح.
  Widget _deskPrimary() {
    if (_tab == 1) {
      final can = Perms.has('sales.items');
      return DeskPrimaryButton(
        icon: LucideIcons.plus,
        label: 'sales.new_item'.tr(),
        locked: !can,
        onTap: can
            ? () => _after(_showSheet(context, const _ItemSheet()))
            : () => showNoPermission(context, action: true),
      );
    }
    final can = Perms.has('sales.sell');
    final items = _items?.active ?? const <SaleItem>[];
    return DeskPrimaryButton(
      icon: LucideIcons.shoppingCart,
      label: 'sales.new'.tr(),
      locked: !can,
      onTap: !can
          ? () => showNoPermission(context, action: true)
          : items.isEmpty
              ? () => showSheetSnack(context, 'sales.add_item_first'.tr())
              : () => _after(_showSheet(context, _NewSaleSheet(items: items))),
    );
  }

  /// على الحاسبة: البطاقات عمودين بدل عمودٍ طويل بعرض الصفحة؛ على الهاتف كما هي واحدةً تحت الأخرى.
  List<Widget> _cards(List<Widget> cards) {
    if (DesktopScope.of(context)) {
      return [DeskGrid(minTileWidth: 420, maxColumns: 2, spacing: Sp.sm, children: cards)];
    }
    return [
      for (int i = 0; i < cards.length; i++) ...[
        if (i > 0) const SizedBox(height: Sp.sm),
        cards[i],
      ],
    ];
  }

  /// أرقام المبيعات: على الحاسبة الأربعة بصفٍّ واحد، وعلى الهاتف صفّان من اثنين.
  List<Widget> _kpiRows(List<Widget> kpis) {
    Widget row(List<Widget> ks) => Row(
          children: [
            for (int i = 0; i < ks.length; i++) ...[
              if (i > 0) const SizedBox(width: Sp.sm),
              Expanded(child: ks[i]),
            ],
          ],
        );
    if (DesktopScope.of(context)) return [row(kpis)];
    return [row(kpis.sublist(0, 2)), const SizedBox(height: Sp.sm), row(kpis.sublist(2))];
  }

  Widget _fab() {
    if (_tab == 1) {
      final can = Perms.has('sales.items');
      return FloatingActionButton.extended(
        heroTag: 'sales-fab-item',
        backgroundColor: can ? AppColors.brand : LockedStyle.box,
        foregroundColor: can ? AppColors.onBrand : LockedStyle.glyph,
        onPressed: can
            ? () => _after(_showSheet(context, const _ItemSheet()))
            : () => showNoPermission(context, action: true),
        icon: Icon(can ? LucideIcons.plus : LucideIcons.lock, size: 16),
        label: Text('sales.new_item'.tr()),
      );
    }
    final can = Perms.has('sales.sell');
    final items = _items?.active ?? const <SaleItem>[];
    return FloatingActionButton.extended(
      heroTag: 'sales-fab-sell',
      backgroundColor: can ? AppColors.brand : LockedStyle.box,
      foregroundColor: can ? AppColors.onBrand : LockedStyle.glyph,
      onPressed: !can
          ? () => showNoPermission(context, action: true)
          : items.isEmpty
              ? () => showSheetSnack(context, 'sales.add_item_first'.tr())
              : () => _after(_showSheet(context, _NewSaleSheet(items: items))),
      icon: Icon(can ? LucideIcons.shoppingCart : LucideIcons.lock, size: 16),
      label: Text('sales.new'.tr()),
    );
  }

  List<Widget> _content() {
    if (_loadingItems && _loadingSales) {
      return const [
        Padding(
          padding: EdgeInsets.symmetric(vertical: 48),
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    }
    if (_items == null && _sales == null) {
      return [
        _Notice(
          icon: LucideIcons.shoppingCart,
          text: _salesError ?? _itemsError ?? 'sales.load_failed'.tr(),
          action: TextButton.icon(
            onPressed: _refresh,
            icon: const Icon(LucideIcons.refreshCw, size: 16),
            label: Text('common.retry'.tr()),
          ),
        ),
      ];
    }
    if (!_enabled && !_hasData) {
      return [_Notice(icon: LucideIcons.shoppingCart, text: 'sales.off'.tr())];
    }
    return [
      if (!_enabled) ...[
        _Banner(icon: LucideIcons.info, text: 'sales.paused'.tr()),
        const SizedBox(height: Sp.md),
      ],
      SheetSegmented(
        labels: ['sales.tab_sales'.tr(), 'sales.tab_items'.tr()],
        icons: const [LucideIcons.shoppingCart, LucideIcons.boxes],
        selectedIndex: _tab,
        onSelect: (i) => setState(() => _tab = i),
      ),
      const SizedBox(height: Sp.md),
      ...(_tab == 0 ? _salesTab() : _itemsTab()),
    ];
  }

  // ─────────────────────────── المبيعات ───────────────────────────
  List<Widget> _salesTab() {
    final page = _sales;
    final t = page?.totals ?? const SalesTotals();
    final canVoid = Perms.has('sales.void') && _enabled;
    final canResolve = Perms.has('sales.sell') && _enabled;
    return [
      DateRangeChipBar(
        value: _range,
        onChanged: (r) {
          setState(() {
            _range = r;
            _loadingSales = true;
          });
          _loadSales();
        },
      ),
      const SizedBox(height: Sp.md),
      if (page == null)
        _Notice(icon: LucideIcons.shoppingCart, text: _salesError ?? 'sales.load_failed'.tr())
      else ...[
        ..._kpiRows([
          _Kpi(
            icon: LucideIcons.shoppingCart,
            label: 'sales.kpi_revenue'.tr(),
            value: _money(t.revenue),
            sub: 'sales.count_n'.tr(namedArgs: {'n': '${t.count}'}),
            tone: AppTone.brand,
          ),
          _Kpi(
            icon: LucideIcons.trendingUp,
            label: 'sales.kpi_profit'.tr(),
            value: _signedMoney(t.profit),
            sub: 'sales.cost_n'.tr(namedArgs: {'amount': _money(t.cost)}),
            tone: t.profit < 0 ? AppTone.danger : AppTone.success,
          ),
          _Kpi(
            icon: LucideIcons.wallet,
            label: 'sales.kpi_cash'.tr(),
            value: _money(t.cash),
            sub: 'sales.kpi_cash_hint'.tr(),
            tone: AppTone.info,
          ),
          // «بيع بالدين» = ما بيع على الدين بالفترة (لا يتغيّر بالتسديد)، وتحته ما بقي منه على المشتركين الآن — كان
          // «على الدين 40,000» يبقى بعد التسديد فيُربك (المالك ٢٣ أكتوبر: «٤٠ مافهمت هاي»).
          _Kpi(
            icon: LucideIcons.handCoins,
            label: 'sales.kpi_debt'.tr(),
            value: _money(t.debt),
            sub: _debtSub(t.debt),
            tone: AppTone.warning,
          ),
        ]),
        if (page.unresolved > 0) ...[
          const SizedBox(height: Sp.md),
          _Banner(
            icon: LucideIcons.triangleAlert,
            text: page.unresolved == 1
                ? 'sales.unresolved'.tr()
                : 'sales.unresolved_n'.tr(namedArgs: {'n': '${page.unresolved}'}),
          ),
        ],
        const SizedBox(height: Sp.md),
        if (_loadingSales)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: Sp.xl),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (page.sales.isEmpty)
          _Notice(icon: LucideIcons.shoppingCart, text: 'sales.empty'.tr())
        else
          ..._cards([
            for (final sale in page.sales)
              _SaleTile(
                sale: sale,
                debt: _debts[sale.id],
                canVoid: canVoid,
                canResolve: canResolve,
                onVoid: () => _after(_showSheet(context, _VoidSheet(sale: sale))),
                onResolve: () => _after(_showSheet(context, _ResolveSheet(sale: sale))),
              ),
          ]),
        if (page.truncated) ...[
          const SizedBox(height: Sp.md),
          Text(
            'sales.truncated'.tr(),
            textAlign: TextAlign.center,
            style: AppType.muted().copyWith(fontSize: 11.5),
          ),
        ],
      ],
    ];
  }

  // ─────────────────────────── الموادّ ───────────────────────────
  List<Widget> _itemsTab() {
    final page = _items;
    if (page == null) {
      return [_Notice(icon: LucideIcons.boxes, text: _itemsError ?? 'sales.load_failed'.tr())];
    }
    final canItems = Perms.has('sales.items') && _enabled;
    final s = _search.text.trim().toLowerCase();
    final shown = s.isEmpty
        ? page.items
        : page.items
            .where((i) => i.name.toLowerCase().contains(s) || (i.code ?? '').toLowerCase().contains(s))
            .toList();
    return [
      Row(
        children: [
          Expanded(
            child: _Kpi(
              icon: LucideIcons.boxes,
              label: 'sales.kpi_stock_value'.tr(),
              value: _money(page.stockValue),
              sub: 'sales.kpi_stock_value_hint'.tr(),
              tone: AppTone.brand,
            ),
          ),
          const SizedBox(width: Sp.sm),
          Expanded(
            child: _Kpi(
              icon: LucideIcons.triangleAlert,
              label: 'sales.kpi_out'.tr(),
              value: '${page.outOfStock}',
              sub: 'sales.kpi_items_n'.tr(namedArgs: {'n': '${page.count}'}),
              tone: page.outOfStock > 0 ? AppTone.danger : AppTone.success,
            ),
          ),
        ],
      ),
      // خانة العطلان (لا تُباع ولا خسارة حتى تُحسم) — تنبيهٌ حين توجد وحدها.
      if (page.defectiveItems > 0) ...[
        const SizedBox(height: Sp.sm),
        _Banner(
          icon: LucideIcons.wrench,
          text: 'sales.defective_banner_n'.tr(namedArgs: {'n': '${page.defectiveItems}', 'amount': _money(page.defectiveValue)}),
        ),
      ],
      const SizedBox(height: Sp.md),
      if (page.items.isNotEmpty) ...[
        SheetSearchField(
          controller: _search,
          hint: 'sales.search_items'.tr(),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: Sp.sm),
      ],
      Row(
        children: [
          Switch(
            value: _showInactive,
            activeThumbColor: AppColors.brand,
            onChanged: (v) {
              setState(() => _showInactive = v);
              _loadItems();
            },
          ),
          const SizedBox(width: Sp.xs),
          Expanded(
            child: Text(
              'sales.show_inactive'.tr(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppType.muted(color: AppColors.textMid).copyWith(fontSize: 12.5),
            ),
          ),
        ],
      ),
      const SizedBox(height: Sp.sm),
      if (page.items.isEmpty)
        _Notice(icon: LucideIcons.boxes, text: 'sales.items_empty'.tr())
      else if (shown.isEmpty)
        _Notice(icon: LucideIcons.search, text: 'sales.no_results'.tr())
      else
        ..._cards([
          for (final item in shown)
            _ItemTile(
              item: item,
              locked: !canItems,
              onStock: () => _after(_showSheet(context, _StockSheet(item: item))),
              onDefect: () => _after(_showSheet(context, _DefectSheet(item: item))),
              onEdit: () => _after(_showSheet(context, _ItemSheet(item: item))),
              onMoves: () => _showSheet(context, _MovesSheet(item: item, canItems: canItems, onChanged: _refresh)),
            ),
        ]),
    ];
  }
}

// ═══════════════════════════ مساعدات ═══════════════════════════

String _money(num v) => '${formatIQD(v)} ${'common.currency'.tr()}';

/// «دين 15,000» · «رصيد له 20,000» · «صفر» — رصيد المشترك سالبٌ للدين.
String _balanceText(num b) {
  if (b < 0) return 'sales.bal_debt'.tr(namedArgs: {'amount': _money(-b)});
  if (b > 0) return 'sales.bal_credit'.tr(namedArgs: {'amount': _money(b)});
  return 'sales.bal_zero'.tr();
}

/// ما جرى بإلغاء بيعٍ على الدين: النقد المُرجَع أو بقاؤه رصيداً، وإنقاص الدين.
String _voidDoneText(Sale s) => [
      if (s.voidMode == 'cash') 'sales.void_done_cash'.tr(namedArgs: {'amount': _money(s.voidRefund ?? 0)}),
      if (s.voidMode == 'credit') 'sales.void_done_credit'.tr(),
      (s.voidDebt ?? 0) > 0
          ? 'sales.void_done_debt'.tr(namedArgs: {'amount': _money(s.voidDebt ?? 0)})
          : 'sales.void_done_nodebt'.tr(),
    ].join(' · ');

String _signedMoney(num v) => '${v < 0 ? '-' : ''}${_money(v)}';

String _day(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// «راوتر ×2، كيبل ×10» — كلّ اسمٍ معزولٌ باتّجاهه، والكمّيّة وحدها (أسماءٌ
/// لاتينيّة مثل «ONU هواوي» لا تقلب السطر).
String _linesText(List<SaleLine> lines) => lines.isEmpty
    ? '—'
    : lines.map((l) => '${iso(l.name)} ${iso('×${_qty(l.qty)}')}').join('، ');

String _qty(num q) {
  if (q == q.roundToDouble()) return q.round().toString();
  var s = q.toStringAsFixed(3);
  while (s.endsWith('0')) {
    s = s.substring(0, s.length - 1);
  }
  return s.endsWith('.') ? s.substring(0, s.length - 1) : s;
}

/// «23 تشرين الأوّل · 18:05» لا «2026/10/23 18:05» (المالك ٢٤ أكتوبر).
String _time(DateTime? at) => at == null ? '' : '${iqDateOf(at)} · ${DateFormat('HH:mm').format(at)}';

Future<bool?> _showSheet(BuildContext context, Widget sheet) {
  return showAppSheet<bool>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: AppColors.scrim,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => sheet,
  );
}

class _Kpi extends StatelessWidget {
  const _Kpi({
    required this.icon,
    required this.label,
    required this.value,
    required this.tone,
    this.sub,
  });
  final IconData icon;
  final String label;
  final String value;
  final String? sub;
  final AppTone tone;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Container(
      padding: const EdgeInsets.all(Sp.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.lg),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: tone.fill),
              const SizedBox(width: Sp.xs),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.micro(),
                ),
              ),
            ],
          ),
          const SizedBox(height: Sp.x6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              value,
              style: AppType.label(color: tone.fill).copyWith(fontSize: 17, fontWeight: FontWeight.w700),
            ),
          ),
          if (sub != null) ...[
            const SizedBox(height: 2),
            Text(
              sub!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppType.muted(color: AppColors.textMid).copyWith(fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.text, this.action});
  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Sp.huge),
      child: Column(
        children: [
          Icon(icon, size: 34, color: AppColors.textLow),
          const SizedBox(height: 10),
          Text(
            text,
            textAlign: TextAlign.center,
            style: AppType.label(color: AppColors.textMid).copyWith(height: 1.6),
          ),
          if (action != null) ...[
            const SizedBox(height: Sp.sm),
            action!,
          ],
        ],
      ),
    );
  }
}

/// تنبيهٌ بلون التحذير — «لم يُحسم» و«موقوفة».
class _Banner extends StatelessWidget {
  const _Banner({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.warningSoftBg,
        borderRadius: BorderRadius.circular(R.md),
        border: Border.all(color: AppTone.warning.fill.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, size: 15, color: AppTone.warning.onSoft),
          ),
          const SizedBox(width: Sp.sm),
          Expanded(
            child: Text(
              text,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: AppType.muted(color: AppTone.warning.onSoft).copyWith(fontSize: 12.5, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}

/// شارة حالة صغيرة.
class _Chip extends StatelessWidget {
  const _Chip(this.text, this.tone);
  final String text;
  final AppTone tone;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Sp.x6, vertical: 2),
      decoration: BoxDecoration(
        color: tone.softBg,
        borderRadius: BorderRadius.circular(R.sm),
      ),
      child: Text(text, style: AppType.micro(color: tone.onSoft).copyWith(fontWeight: FontWeight.w700)),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.icon,
    required this.tone,
    required this.locked,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final AppTone tone;
  final bool locked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final fg = locked ? LockedStyle.glyph : tone.fill;
    final button = Material(
      color: locked ? LockedStyle.box : tone.softBg,
      borderRadius: BorderRadius.circular(R.md),
      child: InkWell(
        borderRadius: BorderRadius.circular(R.md),
        onTap: locked ? () => showNoPermission(context, action: true) : onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Sp.md),
          child: SizedBox(
            height: 36,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(locked ? LucideIcons.lock : icon, size: 15, color: fg),
                const SizedBox(width: Sp.x6),
                Text(
                  label,
                  style: AppType.label(color: fg).copyWith(fontSize: 13, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (!locked) return button;
    return Semantics(
      button: true,
      label: 'locked.a11y'.tr(args: [label]),
      excludeSemantics: true,
      child: button,
    );
  }
}

({String label, AppTone tone}) _saleState(Sale s, [SaleDebtStatus? debt]) {
  switch (s.status) {
    case 'done':
      if (s.isDebt && debt != null && debt.isPaid) return (label: 'sales.st_paid'.tr(), tone: AppTone.success);
      if (s.isDebt && debt != null && debt.isPartial) return (label: 'sales.st_partial'.tr(), tone: AppTone.warning);
      return s.isDebt
          ? (label: 'sales.st_debt'.tr(), tone: AppTone.info)
          : (label: 'sales.st_cash'.tr(), tone: AppTone.success);
    case 'void':
      return (label: 'sales.st_void'.tr(), tone: AppTone.brand);
    case 'failed':
      return (label: 'sales.st_failed'.tr(), tone: AppTone.danger);
    case 'unknown':
      return (label: 'sales.st_unknown'.tr(), tone: AppTone.warning);
    case 'void_unknown':
      return (label: 'sales.st_void_unknown'.tr(), tone: AppTone.warning);
    case 'voiding':
      return s.resolvable()
          ? (label: 'sales.st_void_unknown'.tr(), tone: AppTone.warning)
          : (label: 'sales.st_voiding'.tr(), tone: AppTone.warning);
    default:
      return s.resolvable()
          ? (label: 'sales.st_unknown'.tr(), tone: AppTone.warning)
          : (label: 'sales.st_pending'.tr(), tone: AppTone.warning);
  }
}

class _SaleTile extends StatelessWidget {
  const _SaleTile({
    required this.sale,
    required this.canVoid,
    required this.canResolve,
    required this.onVoid,
    required this.onResolve,
    this.debt,
  });
  final Sale sale;

  /// حالة تسديده إن كان على الدين ومكتملاً.
  final SaleDebtStatus? debt;
  final bool canVoid;
  final bool canResolve;
  final VoidCallback onVoid;
  final VoidCallback onResolve;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final debtNow = sale.isDone && sale.isDebt ? debt : null;
    final st = _saleState(sale, debtNow);
    final dim = sale.isVoid || sale.isFailed;
    final who = sale.employeeId == null ? 'sales.manager'.tr() : (sale.by ?? 'settle.employee'.tr());
    const dimStyle = TextDecoration.lineThrough;
    return Container(
      padding: const EdgeInsets.all(Sp.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.lg),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text('#${sale.id}', style: AppType.micro(color: AppColors.textLow).copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(width: Sp.x6),
              Expanded(
                child: Text(
                  iso(sale.customerLabel),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.label(color: dim ? AppColors.textMid : AppColors.textHi)
                      .copyWith(fontSize: 14, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: Sp.x6),
              _Chip(st.label, st.tone),
            ],
          ),
          const SizedBox(height: Sp.x6),
          Text(
            _linesText(sale.lines),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppType.muted(color: dim ? AppColors.textLow : AppColors.textBody)
                .copyWith(fontSize: 13, height: 1.5, decoration: dim ? dimStyle : null),
          ),
          const SizedBox(height: Sp.xs),
          Text(
            [
              if (sale.customerKind == 'subscriber' && sale.username != null && sale.customerName != null)
                iso(sale.username!),
              who,
              iso(_time(sale.createdAt)),
            ].join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppType.muted(color: AppColors.textMid).copyWith(fontSize: 11.5),
          ),
          if (debtNow != null && !debtNow.isPaid) ...[
            const SizedBox(height: Sp.xs),
            Text(
              debtNow.isPartial
                  ? 'sales.debt_partial_n'.tr(namedArgs: {'paid': _money(debtNow.paid), 'left': _money(debtNow.unpaid)})
                  : 'sales.debt_now_n'.tr(namedArgs: {'amount': _money(debtNow.balance.abs())}),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppType.muted(color: debtNow.isPartial ? AppColors.warningFill : AppColors.textMid).copyWith(fontSize: 11.5),
            ),
          ],
          if (sale.isVoid && sale.voidReason != null) ...[
            const SizedBox(height: Sp.xs),
            Text(
              'sales.void_reason_n'.tr(namedArgs: {'reason': sale.voidReason!}),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppType.muted(color: AppColors.textMid).copyWith(fontSize: 11.5),
            ),
          ],
          if (sale.isVoid && sale.isDebt && sale.voidMode != null) ...[
            const SizedBox(height: Sp.xxs),
            Text(
              _voidDoneText(sale),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppType.muted(color: AppColors.textMid).copyWith(fontSize: 11.5),
            ),
          ],
          const SizedBox(height: Sp.sm),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _money(sale.total),
                      style: AppType.label(color: dim ? AppColors.textLow : AppColors.textHi).copyWith(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        decoration: dim ? dimStyle : null,
                      ),
                    ),
                    if (!dim)
                      Text(
                        'sales.profit_n'.tr(namedArgs: {'amount': _signedMoney(sale.profit)}),
                        style: AppType.muted(color: sale.profit < 0 ? AppColors.error : AppColors.success)
                            .copyWith(fontSize: 11.5),
                      ),
                  ],
                ),
              ),
              // وصل البيع (PDF بورق الطباعة نفسه) — للمكتمل والمُلغى (بختمه).
              if (sale.isDone || sale.isVoid)
                IconButton(
                  tooltip: 'sales.print_receipt'.tr(),
                  onPressed: () async {
                    final r = await SalePrint.printReceipt(sale);
                    if (context.mounted) showPrintResult(context, r);
                  },
                  icon: Icon(LucideIcons.printer, size: 17, color: AppColors.textBody),
                  visualDensity: VisualDensity.compact,
                ),
              if (sale.voidable)
                _ActionButton(
                  label: 'sales.void'.tr(),
                  icon: LucideIcons.undo2,
                  tone: AppTone.danger,
                  locked: !canVoid,
                  onTap: onVoid,
                ),
              if (sale.resolvable())
                _ActionButton(
                  label: 'sales.resolve'.tr(),
                  icon: LucideIcons.triangleAlert,
                  tone: AppTone.warning,
                  // حسم إلغاءٍ «غير مؤكَّد» بصلاحيّة الإلغاء، وحسم بيعٍ بصلاحيّة البيع.
                  locked: sale.resolvesVoid ? !canVoid : !canResolve,
                  onTap: onResolve,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ItemTile extends StatelessWidget {
  const _ItemTile({
    required this.item,
    required this.locked,
    required this.onStock,
    required this.onDefect,
    required this.onEdit,
    required this.onMoves,
  });
  final SaleItem item;
  final bool locked;
  final VoidCallback onStock;

  /// حسم العطلان (تصلّحت / ما تتصلّح / رجّعتها للمورّد) — شارةٌ حين يوجد.
  final VoidCallback onDefect;
  final VoidCallback onEdit;
  final VoidCallback onMoves;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    // بطاقةٌ كالويب (المالك ٢٤ أكتوبر: «المخزون … الاعتناء بالتصميم»): الاسم ورمزه، ثمّ الكمّيّة بارزةً
    // (أو «نافدة») وقيمتها، ثمّ ثلاث خانات البيع/الكلفة/ربح الوحدة، ثمّ ثلاثة أزرار بأسمائها لا أيقوناتٌ وحدها.
    return Opacity(
      opacity: item.active ? 1 : 0.6,
      child: Container(
        padding: const EdgeInsets.all(Sp.md),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(R.lg),
          border: Border.all(color: item.outOfStock && item.active ? AppColors.dangerSoftBorder : AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    iso(item.name),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.label(color: AppColors.textHi).copyWith(fontSize: 14, fontWeight: FontWeight.w700),
                  ),
                ),
                if (item.code != null) ...[
                  const SizedBox(width: Sp.x6),
                  _Chip(item.code!, AppTone.brand),
                ],
                if (!item.active) ...[
                  const SizedBox(width: Sp.x6),
                  _Chip('sales.inactive'.tr(), AppTone.warning),
                ],
              ],
            ),
            if (item.hasDefective) ...[
              const SizedBox(height: Sp.x6),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: _DefectiveChip(item: item, locked: locked, onTap: onDefect),
              ),
            ],
            const SizedBox(height: Sp.sm),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  item.outOfStock ? 'sales.kpi_out'.tr() : saleQtyText(item.qty, item.unit),
                  style: AppType.label(color: item.outOfStock ? AppColors.error : AppColors.textHi)
                      .copyWith(fontSize: 19, fontWeight: FontWeight.w700, height: 1.1),
                ),
                const SizedBox(width: Sp.sm),
                Expanded(
                  child: Text(
                    'sales.stock_value_n'.tr(namedArgs: {'amount': _money(item.stockValue)}),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.end,
                    style: AppType.muted(color: AppColors.textMid).copyWith(fontSize: 11.5),
                  ),
                ),
              ],
            ),
            const SizedBox(height: Sp.sm),
            Row(
              children: [
                Expanded(child: _Stat(label: 'sales.stat_price'.tr(), value: _money(item.salePrice))),
                const SizedBox(width: Sp.x6),
                Expanded(child: _Stat(label: 'sales.stat_cost'.tr(), value: _money(item.costAvg))),
                const SizedBox(width: Sp.x6),
                Expanded(
                  child: _Stat(
                    label: 'sales.stat_margin'.tr(),
                    value: _signedMoney(item.margin),
                    color: item.margin < 0 ? AppColors.error : AppColors.success,
                  ),
                ),
              ],
            ),
            const SizedBox(height: Sp.sm),
            Row(
              children: [
                Expanded(
                  child: _TileButton(
                    icon: LucideIcons.packagePlus,
                    label: 'sales.stock_btn'.tr(),
                    tooltip: 'sales.stock'.tr(),
                    locked: locked,
                    onTap: onStock,
                  ),
                ),
                const SizedBox(width: Sp.x6),
                Expanded(
                  child: _TileButton(
                    icon: LucideIcons.pencil,
                    label: 'sales.edit'.tr(),
                    tooltip: 'sales.edit'.tr(),
                    locked: locked,
                    onTap: onEdit,
                  ),
                ),
                const SizedBox(width: Sp.x6),
                Expanded(
                  child: _TileButton(
                    icon: LucideIcons.history,
                    label: 'sales.moves'.tr(),
                    tooltip: 'sales.moves'.tr(),
                    locked: false,
                    onTap: onMoves,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// خانة رقمٍ صغيرة بالبطاقة: العنوان فوق، والمبلغ تحته بسطرٍ واحد يصغر ولا يُقصّ.
class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, this.color});
  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Sp.sm, vertical: Sp.x6),
      decoration: BoxDecoration(
        color: AppColors.surfaceSunken,
        borderRadius: BorderRadius.circular(R.sm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppType.micro(color: AppColors.textMid),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              value,
              maxLines: 1,
              style: AppType.labelBold(color: color ?? AppColors.textHi),
            ),
          ),
        ],
      ),
    );
  }
}

/// زرّ البطاقة بأيقونته واسمه — مقفلٌ بمكانه بلا صلاحيّة الموادّ.
class _TileButton extends StatelessWidget {
  const _TileButton({
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.locked,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final String tooltip;
  final bool locked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final fg = locked ? LockedStyle.glyph : AppColors.textBody;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: locked ? LockedStyle.box : AppColors.surface,
        borderRadius: BorderRadius.circular(R.md),
        child: InkWell(
          borderRadius: BorderRadius.circular(R.md),
          onTap: locked ? () => showNoPermission(context, action: true) : onTap,
          child: Container(
            height: 38,
            padding: const EdgeInsets.symmetric(horizontal: Sp.x6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(R.md),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(locked ? LucideIcons.lock : icon, size: 15, color: fg),
                const SizedBox(width: Sp.xs),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.labelBold(color: fg),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// شارة «عطلان N» على المادّة — تفتح حسمها، ومقفلةٌ بمكانها بلا صلاحيّة الموادّ.
class _DefectiveChip extends StatelessWidget {
  const _DefectiveChip({required this.item, required this.locked, required this.onTap});
  final SaleItem item;
  final bool locked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    const tone = AppTone.warning;
    return Material(
      color: tone.softBg,
      borderRadius: BorderRadius.circular(R.sm),
      child: InkWell(
        borderRadius: BorderRadius.circular(R.sm),
        onTap: locked ? () => showNoPermission(context, action: true) : onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Sp.x6, vertical: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(locked ? LucideIcons.lock : LucideIcons.wrench, size: 12, color: tone.onSoft),
              const SizedBox(width: Sp.xxs),
              Text(
                'sales.defective_chip_n'.tr(namedArgs: {'qty': saleQtyText(item.qtyDefective, item.unit)}),
                style: AppType.micro(color: tone.onSoft).copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// حقلٌ نصّيّ بصندوق الشيت.
class _SheetText extends StatelessWidget {
  const _SheetText({
    required this.controller,
    required this.icon,
    this.hint,
    this.maxLength = 100,
    this.keyboardType,
    this.ltr = false,
    this.onChanged,
    this.enabled = true,
  });
  final TextEditingController controller;
  final IconData icon;
  final String? hint;
  final int maxLength;
  final TextInputType? keyboardType;
  final bool ltr;
  final ValueChanged<String>? onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return SheetBox(
      icon: icon,
      child: TextField(
        controller: controller,
        enabled: enabled,
        style: AppType.input(),
        maxLength: maxLength,
        keyboardType: keyboardType,
        textDirection: ltr ? TextDirection.ltr : null,
        onChanged: onChanged,
        decoration: InputDecoration(
          isDense: true,
          counterText: '',
          border: InputBorder.none,
          contentPadding: EdgeInsets.zero,
          hintText: hint,
          hintStyle: AppType.input(color: AppColors.textPlaceholder),
        ),
      ),
    );
  }
}

/// حقل مبلغٍ صحيح بالدينار — باختصار الآلاف كبقيّة حقول المال (٢٥ ⇒ ٢٥,٠٠٠ عند الخروج؛ المالك ٢٣ أكتوبر: «ماتتقبل قيم
/// الالف … يطلع رقم بدون اصفار»)، إلّا [shorthand] = false (المتر: سعره دون الألف شائع)؛ و«خلّيه 250» لمبلغٍ حقيقيّ دون الألف.
/// بخطّ الحقول العاديّة وإطارها ([SheetBox] بأيقونة) — فيتساوى ارتفاعه مع الكمّيّة والاسم جنبه («غير متناسق بالحجم»).
class _MoneyField extends StatelessWidget {
  const _MoneyField({required this.controller, required this.onValue, this.enabled = true, this.shorthand = true});
  final TextEditingController controller;
  final ValueChanged<int> onValue;
  final bool enabled;
  final bool shorthand;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return SheetBox(
      icon: LucideIcons.banknote,
      child: AmountTextField(
        controller: controller,
        currency: 'common.currency'.tr(),
        shorthand: shorthand,
        allowExact: true,
        compact: true,
        enabled: enabled,
        onValue: onValue,
      ),
    );
  }
}

// ═══════════════════════════ بيع جديد ═══════════════════════════

class _CartLine {
  _CartLine(this.item)
      : qty = TextEditingController(text: '1'),
        price = TextEditingController(text: AmountShorthand.format(item.salePrice.round()));
  final SaleItem item;
  final TextEditingController qty;
  final TextEditingController price;
  int priceValue = 0;

  void dispose() {
    qty.dispose();
    price.dispose();
  }
}

/// «بيع مادّة» للمشترك من صفحته (المالك ٢٣ أكتوبر: «من صفحه المشتركين … الكه زر بيع ماده للمشترك»): «بيع جديد» نفسه
/// والمشترك مختارٌ مسبقاً. الموادّ تُجلب هنا؛ بلا مادّةٍ فعّالة (أو المبيعات مطفأة) يقول ذلك ولا يفتح. بعد البيع: دين المشترك
/// والرئيسيّة يتحدّثان ([SubscriberEvents.notifyChange]). ⇒ `true` إن سُجّل بيع.
Future<bool> showSellToSubscriber(
  BuildContext context, {
  required String idx,
  required String username,
  String name = '',
  String? phone,
}) async {
  final r = await SalesApi.items();
  if (!context.mounted) return false;
  final page = r.page;
  if (page == null) {
    showSheetSnack(context, r.error ?? 'sales.load_failed'.tr(), isError: true);
    return false;
  }
  if (!page.enabled) {
    showSheetSnack(context, 'sales.off'.tr());
    return false;
  }
  if (page.active.isEmpty) {
    showSheetSnack(context, 'sales.add_item_first'.tr());
    return false;
  }
  final done = await _showSheet(
    context,
    _NewSaleSheet(
      items: page.active,
      initial: _Hit(idx: idx, username: username, name: name, phone: phone),
    ),
  );
  if (done == true) SubscriberEvents.notifyChange();
  return done == true;
}

class _Hit {
  const _Hit({required this.idx, required this.username, required this.name, this.phone});
  final String idx;
  final String username;
  final String name;
  final String? phone;
}

class _NewSaleSheet extends StatefulWidget {
  const _NewSaleSheet({required this.items, this.initial});
  final List<SaleItem> items;

  /// «بيع مادّة» من صفحة المشترك: الزبون مختارٌ مسبقاً، والدفع على دينه إن ملك «إضافة دين» (والتأكيد قبل الإرسال كما هو).
  final _Hit? initial;

  @override
  State<_NewSaleSheet> createState() => _NewSaleSheetState();
}

class _NewSaleSheetState extends State<_NewSaleSheet> {
  final _lines = <_CartLine>[];
  final _walkName = TextEditingController();
  final _walkPhone = TextEditingController();
  final _note = TextEditingController();
  final _term = TextEditingController();
  String _ref = SalesApi.newClientRef();
  late bool _subscriber = widget.initial != null;
  late bool _debt = widget.initial != null && _canDebt;
  late _Hit? _picked = widget.initial;
  List<_Hit> _hits = const [];
  bool _searching = false;
  Timer? _debounce;
  bool _busy = false;
  bool _confirmDebt = false;

  /// آخر إرسالٍ بلا حكمٍ من الخادم: البيع ربّما سُجّل ⇒ السلّة مقفلة و«أعد
  /// الإرسال» بالمرجع نفسه (لا يتكرّر البيع ولا الدين).
  String? _ambiguous;

  bool get _canDebt => Perms.has('subscribers.add_debt');
  bool get _locked => _busy || _ambiguous != null;

  @override
  void dispose() {
    _debounce?.cancel();
    for (final l in _lines) {
      l.dispose();
    }
    _walkName.dispose();
    _walkPhone.dispose();
    _note.dispose();
    _term.dispose();
    super.dispose();
  }

  num? _qtyOf(_CartLine l) => parseSaleQty(l.qty.text);

  bool _over(_CartLine l) {
    final q = _qtyOf(l);
    return q != null && q > l.item.qty;
  }

  bool _lineOk(_CartLine l) => _qtyOf(l) != null && l.priceValue > 0 && !_over(l);

  /// كالخادم: مجموع السطر = round(السعر × الكمّيّة) بالدينار.
  int get _total => _lines.fold<int>(0, (s, l) => s + (_lineOk(l) ? (_qtyOf(l)! * l.priceValue).round() : 0));

  num get _estProfit =>
      _lines.fold<num>(0, (s, l) => s + (_lineOk(l) ? _qtyOf(l)! * (l.priceValue - l.item.costAvg) : 0));

  bool get _ready =>
      !_busy &&
      _lines.isNotEmpty &&
      _lines.every(_lineOk) &&
      _total > 0 &&
      (!_subscriber || _picked != null) &&
      (!_debt || (_subscriber && _picked != null && _canDebt));

  void _addItem(SaleItem it) {
    if (_lines.any((l) => l.item.id == it.id)) return;
    setState(() {
      _lines.add(_CartLine(it)..priceValue = it.salePrice.round());
      _confirmDebt = false;
    });
  }

  void _onTerm(String v) {
    _debounce?.cancel();
    final t = v.trim();
    if (t.length < 2) {
      setState(() {
        _hits = const [];
        _searching = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () => _search(t));
  }

  Future<void> _search(String t) async {
    setState(() => _searching = true);
    final rows = await SalesApi.searchSubscribers(t);
    if (!mounted || _term.text.trim() != t) return;
    setState(() {
      _searching = false;
      _hits = rows
          .map((r) => _Hit(idx: r.idx, username: r.username, name: r.name, phone: r.phone))
          .toList();
    });
  }

  Future<void> _submit() async {
    if (!_ready) return;
    if (_debt && !_confirmDebt) {
      setState(() => _confirmDebt = true);
      return;
    }
    setState(() => _busy = true);
    final picked = _picked;
    final r = await SalesApi.sell(
      clientRef: _ref,
      payment: _debt ? 'debt' : 'cash',
      lines: [
        for (final l in _lines) SaleLineInput(itemId: l.item.id, qty: _qtyOf(l)!, unitPrice: l.priceValue),
      ],
      customer: _subscriber && picked != null
          ? {
              'kind': 'subscriber',
              'idx': picked.idx,
              'username': picked.username,
              if (picked.name.isNotEmpty) 'name': picked.name,
              if (picked.phone != null) 'phone': picked.phone,
            }
          : {
              'kind': 'walkin',
              if (_walkName.text.trim().isNotEmpty) 'name': _walkName.text.trim(),
              if (_walkPhone.text.trim().isNotEmpty) 'phone': _walkPhone.text.trim(),
            },
      note: _note.text.trim(),
    );
    if (!mounted) return;
    setState(() => _busy = false);
    final s = r.sale;
    if (r.ok && s != null) {
      final msg = r.duplicate
          ? 'sales.duplicate'.tr(namedArgs: {'id': '${s.id}'})
          : s.isDebt
              ? 'sales.sold_debt'.tr(namedArgs: {
                  'id': '${s.id}',
                  'amount': _money(s.total),
                  'user': s.username ?? s.customerLabel,
                })
              : 'sales.sold_cash'.tr(namedArgs: {
                  'id': '${s.id}',
                  'amount': _money(s.total),
                  'profit': _signedMoney(s.profit),
                });
      showSheetSnack(context, msg);
      Navigator.of(context).pop(true);
      return;
    }
    if (r.keepRef) {
      // المرجع يبقى: إعادة الإرسال تُرجع البيع المحفوظ إن سُجّل.
      setState(() => _ambiguous = r.code == 'IN_PROGRESS' ? (r.message ?? 'sales.ambiguous'.tr()) : 'sales.ambiguous'.tr());
      return;
    }
    if (r.code == 'OUTCOME_UNKNOWN') {
      // البيع محفوظٌ «غير مؤكَّد» والكمّيّة محجوزة: يُحسم من القائمة.
      showSheetSnack(context, r.message ?? 'sales.ambiguous'.tr(), isError: true, duration: const Duration(seconds: 8));
      Navigator.of(context).pop(true);
      return;
    }
    // حكمٌ واضح (لم يُسجَّل، أو «لم يُضَف الدين» وأُعيدت الكمّيّة) ⇒ مرجعٌ جديد.
    setState(() {
      _ref = SalesApi.newClientRef();
      _confirmDebt = false;
    });
    showSheetSnack(context, r.message ?? 'sales.not_saved'.tr(), isError: true);
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final available = widget.items.where((i) => !_lines.any((l) => l.item.id == i.id)).toList();
    final total = _total;
    final String label;
    if (_ambiguous != null) {
      label = 'sales.resend'.tr();
    } else if (_debt) {
      label = _confirmDebt
          ? 'sales.confirm_n'.tr(namedArgs: {'amount': _money(total)})
          : 'sales.sell_debt_n'.tr(namedArgs: {'amount': total > 0 ? _money(total) : ''});
    } else {
      label = 'sales.sell_cash_n'.tr(namedArgs: {'amount': total > 0 ? _money(total) : ''});
    }
    return DesignSheet(
      header: SheetHeaderBar(
        icon: LucideIcons.shoppingCart,
        title: 'sales.sell_title'.tr(),
        subtitle: 'sales.sell_subtitle'.tr(),
        onClose: () {
          if (!_busy) Navigator.of(context).pop();
        },
      ),
      footer: SheetFooterBar(
        label: label.trim(),
        icon: LucideIcons.shoppingCart,
        color: _debt ? AppColors.warningFill : null,
        enabled: _ready,
        busy: _busy,
        onPressed: _submit,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SheetSection(
            label: 'sales.f_items'.tr(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final l in _lines) ...[
                  _cartLine(l),
                  const SizedBox(height: Sp.sm),
                ],
                if (available.isNotEmpty && !_locked) _itemPicker(available, more: _lines.isNotEmpty),
              ],
            ),
          ),
          const SizedBox(height: Sp.lg),
          SheetSection(
            label: 'sales.f_customer'.tr(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SheetSegmented(
                  labels: ['sales.walkin_tab'.tr(), 'sales.subscriber_tab'.tr()],
                  selectedIndex: _subscriber ? 1 : 0,
                  onSelect: (i) {
                    if (_locked) return;
                    setState(() {
                      _subscriber = i == 1;
                      if (!_subscriber) _debt = false;
                      _confirmDebt = false;
                    });
                  },
                ),
                const SizedBox(height: Sp.sm),
                if (!_subscriber) ...[
                  _SheetText(controller: _walkName, icon: LucideIcons.user, hint: 'sales.f_name_opt'.tr(), enabled: !_locked),
                  const SizedBox(height: Sp.sm),
                  _SheetText(
                    controller: _walkPhone,
                    icon: LucideIcons.phone,
                    hint: 'sales.f_phone_opt'.tr(),
                    maxLength: 20,
                    keyboardType: TextInputType.phone,
                    ltr: true,
                    enabled: !_locked,
                  ),
                ] else if (_picked != null)
                  _pickedBox(_picked!)
                else
                  _subscriberSearch(),
              ],
            ),
          ),
          const SizedBox(height: Sp.lg),
          SheetSection(
            label: 'sales.f_payment'.tr(),
            footnote: !_subscriber
                ? 'sales.debt_needs_sub'.tr()
                : !_canDebt
                    ? 'sales.debt_needs_perm'.tr()
                    : _debt
                        ? 'sales.debt_hint'.tr()
                        : null,
            child: SheetSegmented(
              labels: ['sales.pay_cash'.tr(), 'sales.pay_debt'.tr()],
              icons: [LucideIcons.wallet, _canDebt ? LucideIcons.handCoins : LucideIcons.lock],
              selectedIndex: _debt ? 1 : 0,
              onSelect: (i) {
                if (_locked) return;
                if (i == 1 && (!_subscriber || !_canDebt)) return;
                setState(() {
                  _debt = i == 1;
                  _confirmDebt = false;
                });
              },
            ),
          ),
          const SizedBox(height: Sp.lg),
          _SheetText(controller: _note, icon: LucideIcons.fileText, hint: 'sales.f_note_opt'.tr(), maxLength: 200, enabled: !_locked),
          const SizedBox(height: Sp.lg),
          SheetSummaryBox(label: 'sales.total'.tr(), value: _money(total)),
          const SizedBox(height: Sp.sm),
          SheetSummaryBox(
            label: 'sales.est_profit'.tr(),
            value: _signedMoney(_estProfit),
            valueColor: _estProfit < 0 ? AppColors.error : AppColors.success,
          ),
          if (_confirmDebt && _picked != null) ...[
            const SizedBox(height: Sp.md),
            _Banner(
              icon: LucideIcons.triangleAlert,
              text: 'sales.confirm_debt'.tr(namedArgs: {'amount': _money(total), 'user': iso(_picked!.username)}),
            ),
          ],
          if (_ambiguous != null) ...[
            const SizedBox(height: Sp.md),
            _Banner(icon: LucideIcons.triangleAlert, text: _ambiguous!),
          ],
        ],
      ),
    );
  }

  Widget _cartLine(_CartLine l) {
    final over = _over(l);
    final q = _qtyOf(l);
    return Container(
      padding: const EdgeInsets.all(Sp.sm),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.lg),
        border: Border.all(color: over ? AppColors.error : AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  iso(l.item.name),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.label(color: AppColors.textHi).copyWith(fontSize: 13.5, fontWeight: FontWeight.w700),
                ),
              ),
              Text(
                'sales.available_n'.tr(namedArgs: {'qty': saleQtyText(l.item.qty, l.item.unit)}),
                style: AppType.muted(color: over ? AppColors.error : AppColors.textMid).copyWith(fontSize: 11),
              ),
              if (!_locked)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: Icon(LucideIcons.x, size: 16, color: AppColors.textMid),
                  onPressed: () => setState(() {
                    _lines.remove(l);
                    l.dispose();
                    _confirmDebt = false;
                  }),
                ),
            ],
          ),
          const SizedBox(height: Sp.xs),
          Row(
            children: [
              Expanded(
                flex: 2,
                child: _SheetText(
                  controller: l.qty,
                  icon: LucideIcons.hash,
                  hint: saleUnitLabel(l.item.unit),
                  maxLength: 12,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  ltr: true,
                  enabled: !_locked,
                  onChanged: (_) => setState(() => _confirmDebt = false),
                ),
              ),
              const SizedBox(width: Sp.sm),
              Expanded(
                flex: 3,
                child: _MoneyField(
                  controller: l.price,
                  enabled: !_locked,
                  shorthand: l.item.unit != 'meter',
                  onValue: (v) => setState(() {
                    l.priceValue = v;
                    _confirmDebt = false;
                  }),
                ),
              ),
            ],
          ),
          if (over)
            Padding(
              padding: const EdgeInsets.only(top: Sp.xs),
              child: Text('sales.over_stock'.tr(), style: AppType.muted(color: AppColors.error).copyWith(fontSize: 11.5)),
            )
          else if (q != null && l.priceValue > 0)
            Padding(
              padding: const EdgeInsets.only(top: Sp.xs),
              child: Text(
                '${'sales.total'.tr()} ${_money((q * l.priceValue).round())} · ${'sales.cost_avg_n'.tr(namedArgs: {'amount': _money(l.item.costAvg)})}',
                style: AppType.muted(color: l.priceValue < l.item.costAvg ? AppColors.error : AppColors.textMid)
                    .copyWith(fontSize: 11),
              ),
            ),
        ],
      ),
    );
  }

  Widget _itemPicker(List<SaleItem> available, {required bool more}) {
    return Material(
      color: AppColors.brandSoftBg,
      borderRadius: BorderRadius.circular(R.lg),
      child: InkWell(
        borderRadius: BorderRadius.circular(R.lg),
        onTap: () async {
          final it = await showAppSheet<SaleItem>(
            context: context,
            backgroundColor: Colors.transparent,
            barrierColor: AppColors.scrim,
            isScrollControlled: true,
            useSafeArea: true,
            builder: (_) => _ItemPickSheet(items: available),
          );
          if (it != null && mounted) _addItem(it);
        },
        child: SizedBox(
          height: 46,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(LucideIcons.plus, size: 16, color: AppColors.brand),
              const SizedBox(width: Sp.x6),
              Text(
                (more ? 'sales.pick_more' : 'sales.pick_item').tr(),
                style: AppType.label(color: AppColors.brand).copyWith(fontSize: 13.5, fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _pickedBox(_Hit h) {
    return SheetBox(
      icon: LucideIcons.user,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  iso(h.name.isNotEmpty ? h.name : h.username),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.input(),
                ),
                Text(
                  h.username,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textDirection: TextDirection.ltr,
                  style: AppType.muted(color: AppColors.textMid).copyWith(fontSize: 11.5),
                ),
              ],
            ),
          ),
          if (!_locked)
            TextButton(
              onPressed: () => setState(() {
                _picked = null;
                _confirmDebt = false;
              }),
              child: Text('sales.change'.tr()),
            ),
        ],
      ),
    );
  }

  Widget _subscriberSearch() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SheetSearchField(controller: _term, hint: 'sales.search_sub'.tr(), onChanged: _onTerm),
        if (_searching)
          const Padding(
            padding: EdgeInsets.all(Sp.md),
            child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
          )
        else if (_hits.isNotEmpty) ...[
          const SizedBox(height: Sp.xs),
          for (final h in _hits)
            _PickRow(
              icon: LucideIcons.user,
              title: iso(h.name.isNotEmpty ? h.name : h.username),
              subtitle: h.username,
              subtitleLtr: true,
              onTap: () => setState(() {
                _picked = h;
                _hits = const [];
                _term.clear();
              }),
            ),
        ] else if (_term.text.trim().length >= 2)
          Padding(
            padding: const EdgeInsets.only(top: Sp.sm),
            child: Text('sales.no_sub'.tr(), style: AppType.muted(color: AppColors.textMid).copyWith(fontSize: 12.5)),
          ),
      ],
    );
  }
}

/// صفٌّ قابلٌ للنقر داخل شيت — Material شفّاف تحته ليظهر أثر اللمس فوق خلفيّة الشيت
/// (ListTile يرسم على أقرب Material، وخلفيّة الشيت تحجبه).
class _PickRow extends StatelessWidget {
  const _PickRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.subtitleLtr = false,
    this.subtitleColor,
    this.enabled = true,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool subtitleLtr;
  final Color? subtitleColor;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        borderRadius: BorderRadius.circular(R.md),
        onTap: enabled ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Sp.sm, vertical: 10),
          child: Row(
            children: [
              Icon(icon, size: 16, color: enabled ? AppColors.textMid : AppColors.textLow),
              const SizedBox(width: Sp.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.label(color: enabled ? AppColors.textHi : AppColors.textLow)
                          .copyWith(fontSize: 13.5, fontWeight: FontWeight.w700),
                    ),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textDirection: subtitleLtr ? TextDirection.ltr : null,
                      style: AppType.muted(color: subtitleColor ?? AppColors.textMid).copyWith(fontSize: 11.5),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// اختيار مادّة للبيع — النافدة لا تُختار.
class _ItemPickSheet extends StatefulWidget {
  const _ItemPickSheet({required this.items});
  final List<SaleItem> items;

  @override
  State<_ItemPickSheet> createState() => _ItemPickSheetState();
}

class _ItemPickSheetState extends State<_ItemPickSheet> {
  final _q = TextEditingController();

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final s = _q.text.trim().toLowerCase();
    final shown = s.isEmpty
        ? widget.items
        : widget.items.where((i) => i.name.toLowerCase().contains(s) || (i.code ?? '').toLowerCase().contains(s)).toList();
    return DesignSheet(
      header: SheetHeaderBar(
        icon: LucideIcons.boxes,
        title: 'sales.pick_item_title'.tr(),
        subtitle: 'sales.pick_item_sub'.tr(),
        onClose: () => Navigator.of(context).pop(),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SheetSearchField(controller: _q, hint: 'sales.search_items'.tr(), onChanged: (_) => setState(() {})),
          const SizedBox(height: Sp.sm),
          for (final it in shown)
            _PickRow(
              icon: LucideIcons.package,
              title: iso(it.name),
              subtitle: '${_money(it.salePrice)} · ${it.outOfStock ? 'sales.kpi_out'.tr() : saleQtyText(it.qty, it.unit)}',
              subtitleColor: it.outOfStock ? AppColors.error : null,
              enabled: !it.outOfStock,
              onTap: () => Navigator.of(context).pop(it),
            ),
          if (shown.isEmpty) _Notice(icon: LucideIcons.search, text: 'sales.no_results'.tr()),
        ],
      ),
    );
  }
}

// ═══════════════════════════ الإلغاء والحسم ═══════════════════════════

class _VoidSheet extends StatefulWidget {
  const _VoidSheet({required this.sale});
  final Sale sale;

  @override
  State<_VoidSheet> createState() => _VoidSheetState();
}

class _VoidSheetState extends State<_VoidSheet> {
  final _reason = TextEditingController();
  bool _busy = false;

  /// على الدين: رصيد المشترك وما سُدّد من البيع (بمسار الدين نفسه) — يُقرأ عند الفتح.
  VoidPreview? _pv;
  String? _pvError;
  bool _pvLoading = false;

  /// ما يصير بما سدّده المشترك: `credit` (رصيدٌ له) · `cash` (يُرجَع نقداً).
  String? _refund;

  Sale get _s => widget.sale;
  bool get _needsChoice => _pv != null && _pv!.needsChoice && _pv!.paid > 0;

  @override
  void initState() {
    super.initState();
    if (_s.isDebt) _loadPreview();
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _loadPreview() async {
    setState(() {
      _pvLoading = true;
      _pvError = null;
    });
    final r = await SalesApi.voidPreview(_s.id);
    if (!mounted) return;
    setState(() {
      _pvLoading = false;
      _pv = r.preview;
      _pvError = r.error;
      _refund = null;
    });
  }

  Future<void> _submit() async {
    setState(() => _busy = true);
    final choice = _s.isDebt && _needsChoice;
    final r = await SalesApi.voidSale(
      _s.id,
      _reason.text.trim(),
      refund: choice ? _refund : null,
      expectedPaid: choice ? _pv!.paid : null,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (r.ok) {
      final id = '${_s.id}';
      final msg = !_s.isDebt
          ? 'sales.voided'.tr(namedArgs: {'id': id})
          : choice && _refund == 'cash'
              ? 'sales.voided_cash'.tr(namedArgs: {'id': id, 'amount': _money(_pv!.paid)})
              : choice
                  ? 'sales.voided_credit'.tr(namedArgs: {'id': id, 'amount': _money(_pv!.paid)})
                  : 'sales.voided_debt'.tr(namedArgs: {'id': id});
      showSheetSnack(context, msg);
      Navigator.of(context).pop(true);
      return;
    }
    // محجوزٌ «غير مؤكَّد» بالقائمة، أو لم يصل حكم الخادم — لا إعادة عمياء: تُحدَّث القائمة.
    if (r.code == 'OUTCOME_UNKNOWN' || r.code == 'AMBIGUOUS') {
      showSheetSnack(context, r.message ?? 'sales.not_saved'.tr(), isError: true);
      Navigator.of(context).pop(true);
      return;
    }
    showSheetSnack(context, r.message ?? 'sales.not_saved'.tr(), isError: true);
    if (const {'SALE_PAID_PART', 'PAID_CHANGED', 'BALANCE_CHANGED'}.contains(r.code)) _loadPreview();
  }

  Widget _debtBody() {
    final pv = _pv;
    if (_pvError != null) {
      return Row(
        children: [
          Expanded(child: _Banner(icon: LucideIcons.triangleAlert, text: _pvError!)),
          const SizedBox(width: Sp.sm),
          TextButton(onPressed: _loadPreview, child: Text('sales.void_retry'.tr())),
        ],
      );
    }
    if (pv == null || _pvLoading) {
      return Row(
        children: [
          const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
          const SizedBox(width: Sp.sm),
          Text('sales.void_reading'.tr(), style: AppType.muted(color: AppColors.textMid).copyWith(fontSize: 12.5)),
        ],
      );
    }
    final remain = pv.total - pv.paid < 0 ? 0 : pv.total - pv.paid;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(R.md),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'sales.void_balance_now'.tr(namedArgs: {'user': iso(_s.username ?? _s.customerName ?? '—')}),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.muted(color: AppColors.textMid).copyWith(fontSize: 12.5),
                ),
              ),
              const SizedBox(width: Sp.sm),
              Text(
                _balanceText(pv.balance),
                style: AppType.label(color: AppColors.textHi).copyWith(fontSize: 13.5, fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
        const SizedBox(height: Sp.md),
        if (_needsChoice) ...[
          Text(
            'sales.void_paid'.tr(namedArgs: {'amount': _money(pv.paid)}),
            style: AppType.label(color: AppColors.textHi).copyWith(fontSize: 13.5, height: 1.6),
          ),
          const SizedBox(height: Sp.sm),
          _ChoiceCard(
            selected: _refund == 'credit',
            icon: LucideIcons.handCoins,
            title: 'sales.void_credit'.tr(),
            subtitle: 'sales.void_credit_sub'.tr(namedArgs: {'amount': _money(pv.total), 'after': _balanceText(pv.afterCredit)}),
            onTap: () => setState(() => _refund = 'credit'),
          ),
          const SizedBox(height: Sp.sm),
          _ChoiceCard(
            selected: _refund == 'cash',
            icon: LucideIcons.wallet,
            title: 'sales.void_cash'.tr(namedArgs: {'amount': _money(pv.paid)}),
            subtitle: 'sales.void_cash_sub'.tr(namedArgs: {'amount': _money(remain), 'after': _balanceText(pv.afterCash)}),
            onTap: () => setState(() => _refund = 'cash'),
          ),
        ] else
          Text(
            'sales.void_unpaid'.tr(namedArgs: {'amount': _money(pv.total), 'after': _balanceText(pv.afterCredit)}),
            style: AppType.muted(color: AppColors.textMid).copyWith(fontSize: 12.5, height: 1.6),
          ),
        const SizedBox(height: Sp.sm),
        Text(
          'sales.void_debt_info'.tr(),
          style: AppType.muted(color: AppColors.textMid).copyWith(fontSize: 12.5, height: 1.6),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final s = _s;
    final ready = !s.isDebt || (_pv != null && !_pvLoading);
    final canSubmit = _reason.text.trim().length >= 2 && ready && (!_needsChoice || _refund != null);
    final label = !s.isDebt
        ? 'sales.void_btn'.tr(namedArgs: {'amount': _money(s.total)})
        : _needsChoice && _refund == 'cash'
            ? 'sales.void_btn_refund'.tr(namedArgs: {'amount': _money(_pv!.paid)})
            : 'sales.void_btn_debt'.tr();
    return DesignSheet(
      header: SheetHeaderBar(
        icon: LucideIcons.undo2,
        title: 'sales.void_title'.tr(namedArgs: {'id': '${s.id}'}),
        subtitle: '${_linesText(s.lines)} — ${_money(s.total)}${s.isDebt ? ' ${'sales.on_debt'.tr()}' : ''}',
        tint: AppColors.error,
        tintBg: AppColors.dangerSoftBg,
        onClose: () => Navigator.of(context).pop(),
      ),
      footer: SheetFooterBar(
        label: label,
        icon: LucideIcons.undo2,
        color: AppColors.error,
        enabled: canSubmit,
        busy: _busy,
        onPressed: _submit,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (s.isDebt)
            _debtBody()
          else
            Text(
              'sales.void_info'.tr(),
              style: AppType.muted(color: AppColors.textMid).copyWith(fontSize: 12.5, height: 1.6),
            ),
          const SizedBox(height: Sp.lg),
          SheetSection(
            label: '${'sales.f_void_reason'.tr()} *',
            child: _SheetText(
              controller: _reason,
              icon: LucideIcons.fileText,
              hint: 'sales.void_hint'.tr(),
              maxLength: 200,
              onChanged: (_) => setState(() {}),
            ),
          ),
        ],
      ),
    );
  }
}

/// مصدر ثمن الشراء — إجباريّ بلا اختيارٍ مسبق (قرار المالك ٢٣ أكتوبر): من الصندوق يُنقص صندوق التسوية
/// بثمنه، ومن خارجه لا. [amount] ثمن الكمّيّة إن عُرف.
class _PaidFromChoice extends StatelessWidget {
  const _PaidFromChoice({required this.value, required this.onChanged, this.amount});
  final String? value;
  final ValueChanged<String> onChanged;
  final num? amount;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final a = amount;
    return SheetSection(
      label: '${'sales.paid_from'.tr()} *',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ChoiceCard(
            selected: value == 'box',
            icon: LucideIcons.wallet,
            title: 'sales.paid_box'.tr(),
            subtitle: a != null && a > 0
                ? 'sales.paid_box_sub_n'.tr(namedArgs: {'amount': _money(a)})
                : 'sales.paid_box_sub'.tr(),
            onTap: () => onChanged('box'),
          ),
          const SizedBox(height: Sp.sm),
          _ChoiceCard(
            selected: value == 'outside',
            icon: LucideIcons.boxes,
            title: 'sales.paid_outside'.tr(),
            subtitle: 'sales.paid_outside_sub'.tr(),
            onTap: () => onChanged('outside'),
          ),
        ],
      ),
    );
  }
}

/// اختيارٌ واحد من بطاقات (ما يصير بما سدّده المشترك عند إلغاء البيع، مصدر ثمن الشراء، تالفٌ أم عطلان، وحسم العطلان).
class _ChoiceCard extends StatelessWidget {
  const _ChoiceCard({
    required this.selected,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  final bool selected;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    const tone = AppTone.brand;
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        borderRadius: BorderRadius.circular(R.lg),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? tone.softBg : null,
            borderRadius: BorderRadius.circular(R.lg),
            border: Border.all(color: selected ? tone.fill : AppColors.border, width: selected ? 1.5 : 1),
          ),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: selected ? tone.fill : AppColors.surfaceSunken,
                  borderRadius: BorderRadius.circular(R.sm),
                ),
                child: Icon(icon, size: 16, color: selected ? AppColors.surface : AppColors.textMid),
              ),
              const SizedBox(width: Sp.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppType.label(color: AppColors.textHi).copyWith(fontSize: 13.5, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: Sp.xxs),
                    Text(
                      subtitle,
                      style: AppType.muted(color: AppColors.textMid).copyWith(fontSize: 11.5, height: 1.5),
                    ),
                  ],
                ),
              ),
              if (selected) ...[
                const SizedBox(width: Sp.sm),
                Icon(LucideIcons.circleCheck, size: 18, color: tone.fill),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ResolveSheet extends StatefulWidget {
  const _ResolveSheet({required this.sale});
  final Sale sale;

  @override
  State<_ResolveSheet> createState() => _ResolveSheetState();
}

class _ResolveSheetState extends State<_ResolveSheet> {
  bool? _armed;
  bool _busy = false;

  Future<void> _submit(bool applied) async {
    if (_armed != applied) {
      setState(() => _armed = applied);
      return;
    }
    setState(() => _busy = true);
    // إلغاءٌ على الدين لم يتأكّد إنقاص دينه ⇒ مساره (resolve-void)؛ وإلّا بيعٌ لم يتأكّد إضافة دينه.
    final isVoid = widget.sale.resolvesVoid;
    final r = isVoid
        ? await SalesApi.resolveVoid(widget.sale.id, applied: applied)
        : await SalesApi.resolve(widget.sale.id, applied: applied);
    if (!mounted) return;
    setState(() => _busy = false);
    if (r.ok) {
      final key = isVoid
          ? (applied ? 'sales.resolved_void_yes' : 'sales.resolved_void_no')
          : (applied ? 'sales.resolved_yes' : 'sales.resolved_no');
      showSheetSnack(context, key.tr(namedArgs: {'id': '${widget.sale.id}'}));
      Navigator.of(context).pop(true);
      return;
    }
    showSheetSnack(context, r.message ?? 'sales.not_saved'.tr(), isError: true);
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final s = widget.sale;
    final isVoid = s.resolvesVoid;
    final before = s.voidBalanceBefore ?? 0;
    final vDebt = s.voidDebt ?? 0;
    final vRefund = s.voidMode == 'cash' ? (s.voidRefund ?? 0) : 0;
    final info = isVoid
        ? 'sales.resolve_void_info'.tr(namedArgs: {'amount': _money(vDebt), 'user': iso(s.username ?? '—')})
        : 'sales.resolve_info'.tr(namedArgs: {'amount': _money(s.total), 'user': iso(s.username ?? '—')});
    final hints = isVoid
        ? '• ${'sales.resolve_void_yes_hint'.tr(namedArgs: {
            'after': _balanceText(before + vDebt),
            'refund': vRefund > 0 ? 'sales.resolve_void_refund'.tr(namedArgs: {'amount': _money(vRefund)}) : '',
          })}\n• ${'sales.resolve_void_no_hint'.tr(namedArgs: {'before': _balanceText(before)})}'
        : '• ${'sales.resolve_yes_hint'.tr()}\n• ${'sales.resolve_no_hint'.tr()}';
    final yes = isVoid ? 'sales.resolve_void_yes' : 'sales.resolve_yes';
    final no = isVoid ? 'sales.resolve_void_no' : 'sales.resolve_no';
    return DesignSheet(
      header: SheetHeaderBar(
        icon: LucideIcons.triangleAlert,
        title: (isVoid ? 'sales.resolve_void_title' : 'sales.resolve_title').tr(namedArgs: {'id': '${s.id}'}),
        subtitle: '${_linesText(s.lines)} — ${_money(s.total)}',
        tint: AppColors.warningFill,
        tintBg: AppColors.warningSoftBg,
        onClose: () => Navigator.of(context).pop(),
      ),
      footer: SheetFooterBar(
        label: _armed == true ? '${yes}_confirm'.tr() : yes.tr(),
        icon: LucideIcons.circleCheck,
        color: AppColors.successFill,
        busy: _busy && _armed == true,
        enabled: !_busy,
        onPressed: () => _submit(true),
        above: Padding(
          padding: const EdgeInsets.only(bottom: Sp.sm),
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _busy ? null : () => _submit(false),
              icon: Icon(LucideIcons.circleX, size: 16, color: AppColors.error),
              label: Text(
                _armed == false ? '${no}_confirm'.tr() : no.tr(),
                style: AppType.label(color: AppColors.error).copyWith(fontSize: 13.5, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            info,
            style: AppType.label(color: AppColors.textHi).copyWith(fontSize: 13.5, height: 1.6),
          ),
          const SizedBox(height: Sp.md),
          Text(
            hints,
            style: AppType.muted(color: AppColors.textMid).copyWith(fontSize: 12.5, height: 1.7),
          ),
          if (_armed != null) ...[
            const SizedBox(height: Sp.md),
            _Banner(icon: LucideIcons.info, text: 'sales.resolve_confirm'.tr()),
          ],
        ],
      ),
    );
  }
}

// ═══════════════════════════ الموادّ ═══════════════════════════

class _ItemSheet extends StatefulWidget {
  const _ItemSheet({this.item});
  final SaleItem? item;

  @override
  State<_ItemSheet> createState() => _ItemSheetState();
}

class _ItemSheetState extends State<_ItemSheet> {
  late final _name = TextEditingController(text: widget.item?.name ?? '');
  late final _price =
      TextEditingController(text: widget.item == null ? '' : AmountShorthand.format(widget.item!.salePrice.round()));
  late final _code = TextEditingController(text: widget.item?.code ?? '');
  late final _note = TextEditingController(text: widget.item?.note ?? '');
  final _qty = TextEditingController();
  final _cost = TextEditingController();
  late String _unit = widget.item?.unit ?? 'piece';
  late bool _active = widget.item?.active ?? true;
  late int _priceValue = widget.item?.salePrice.round() ?? 0;
  int _costValue = 0;
  String? _paidFrom;
  bool _busy = false;

  bool get _isNew => widget.item == null;

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    _code.dispose();
    _note.dispose();
    _qty.dispose();
    _cost.dispose();
    super.dispose();
  }

  num? get _qtyValue => _qty.text.trim().isEmpty ? null : parseSaleQty(_qty.text);
  // المخزون الافتتاحيّ شراءٌ أيضاً: يُسأل من أين دُفع ثمنه.
  bool get _openingOk =>
      _qty.text.trim().isEmpty || (_qtyValue != null && _cost.text.trim().isNotEmpty && _paidFrom != null);
  bool get _ok => !_busy && _name.text.trim().length >= 2 && _priceValue > 0 && (!_isNew || _openingOk);

  Future<void> _submit() async {
    setState(() => _busy = true);
    final name = _name.text.trim();
    final ({bool ok, String? message}) r;
    final it = widget.item;
    if (it == null) {
      r = await SalesApi.createItem(
        name: name,
        salePrice: _priceValue,
        unit: _unit,
        code: _code.text.trim(),
        note: _note.text.trim(),
        qty: _qtyValue,
        unitCost: _qtyValue == null ? null : _costValue,
        paidFrom: _qtyValue == null ? null : _paidFrom,
      );
    } else {
      final patch = <String, dynamic>{
        if (name != it.name) 'name': name,
        if (_priceValue != it.salePrice.round()) 'sale_price': _priceValue,
        if (_unit != it.unit) 'unit': _unit,
        if (_code.text.trim() != (it.code ?? '')) 'code': _code.text.trim(),
        if (_note.text.trim() != (it.note ?? '')) 'note': _note.text.trim(),
        if (_active != it.active) 'active': _active,
      };
      if (patch.isEmpty) {
        Navigator.of(context).pop(false);
        return;
      }
      r = await SalesApi.updateItem(it.id, patch);
    }
    if (!mounted) return;
    setState(() => _busy = false);
    if (r.ok) {
      showSheetSnack(context, (_isNew ? 'sales.item_added' : 'sales.item_saved').tr(namedArgs: {'name': name}));
      Navigator.of(context).pop(true);
      return;
    }
    showSheetSnack(context, r.message ?? 'sales.not_saved'.tr(), isError: true);
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return DesignSheet(
      header: SheetHeaderBar(
        icon: LucideIcons.package,
        title: _isNew ? 'sales.item_new'.tr() : 'sales.item_edit_n'.tr(namedArgs: {'name': widget.item!.name}),
        subtitle: (_isNew ? 'sales.item_new_sub' : 'sales.item_edit_sub').tr(),
        onClose: () => Navigator.of(context).pop(),
      ),
      footer: SheetFooterBar(
        label: (_isNew ? 'sales.add_item_btn' : 'sales.save').tr(),
        icon: _isNew ? LucideIcons.plus : LucideIcons.check,
        enabled: _ok,
        busy: _busy,
        onPressed: _submit,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SheetSection(
            label: '${'sales.f_item_name'.tr()} *',
            child: _SheetText(
              controller: _name,
              icon: LucideIcons.package,
              hint: 'sales.item_name_hint'.tr(),
              onChanged: (_) => setState(() {}),
            ),
          ),
          const SizedBox(height: Sp.lg),
          SheetSection(
            label: '${'sales.f_sale_price'.tr()} *',
            child: _MoneyField(controller: _price, shorthand: _unit != 'meter', onValue: (v) => setState(() => _priceValue = v)),
          ),
          const SizedBox(height: Sp.lg),
          SheetSection(
            label: 'sales.f_unit'.tr(),
            child: Wrap(
              spacing: Sp.sm,
              runSpacing: Sp.sm,
              children: [
                for (final e in kSaleUnits.entries)
                  SheetQuickChip(
                    label: e.value,
                    selected: _unit == e.key,
                    onTap: () => setState(() => _unit = e.key),
                  ),
              ],
            ),
          ),
          if (_isNew) ...[
            const SizedBox(height: Sp.lg),
            SheetSection(
              label: 'sales.opening'.tr(),
              footnote: _qty.text.trim().isNotEmpty && _cost.text.trim().isEmpty
                  ? 'sales.cost_required'.tr()
                  : 'sales.cost_hint'.tr(),
              child: Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: _SheetText(
                      controller: _qty,
                      icon: LucideIcons.hash,
                      hint: 'sales.f_qty'.tr(),
                      maxLength: 12,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      ltr: true,
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: Sp.sm),
                  Expanded(
                    flex: 3,
                    child: _MoneyField(controller: _cost, shorthand: _unit != 'meter', onValue: (v) => setState(() => _costValue = v)),
                  ),
                ],
              ),
            ),
            if (_qtyValue != null) ...[
              const SizedBox(height: Sp.md),
              _PaidFromChoice(
                value: _paidFrom,
                onChanged: (v) => setState(() => _paidFrom = v),
                amount: _cost.text.trim().isEmpty ? null : (_qtyValue! * _costValue).round(),
              ),
            ],
          ],
          const SizedBox(height: Sp.lg),
          SheetSection(
            label: 'sales.f_code'.tr(),
            child: _SheetText(controller: _code, icon: LucideIcons.scanBarcode, maxLength: 64, ltr: true),
          ),
          const SizedBox(height: Sp.lg),
          SheetSection(
            label: 'sales.f_note'.tr(),
            child: _SheetText(controller: _note, icon: LucideIcons.fileText, maxLength: 200),
          ),
          if (!_isNew) ...[
            const SizedBox(height: Sp.lg),
            // صفٌّ بمفتاح — لا SwitchListTile: ListTile داخل شيتٍ بخلفيّة يُخفي أثر اللمس (تنبيه Flutter).
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('sales.active_label'.tr(), style: AppType.label(color: AppColors.textHi)),
                      Text(
                        'sales.active_hint'.tr(),
                        style: AppType.muted(color: AppColors.textMid).copyWith(fontSize: 11.5),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: Sp.sm),
                Switch(
                  value: _active,
                  activeThumbColor: AppColors.brand,
                  onChanged: (v) => setState(() => _active = v),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _StockSheet extends StatefulWidget {
  const _StockSheet({required this.item});
  final SaleItem item;

  @override
  State<_StockSheet> createState() => _StockSheetState();
}

/// حركة مخزون (قرار المالك ٢٣ أكتوبر): شراء (مصدر ثمنه إجباريّ) · تالف أو عطلان (الاختيار إجباريّ:
/// التالف خسارةٌ الآن، والعطلان خانةٌ تُحسم لاحقاً) · فرق عدّ (± بلا مال).
class _StockSheetState extends State<_StockSheet> {
  final _qty = TextEditingController();
  late final _cost = TextEditingController(text: AmountShorthand.format(widget.item.costAvg.round()));
  final _note = TextEditingController();

  /// 0 شراء · 1 تالف / عطلان · 2 فرق عدّ.
  int _mode = 0;

  /// `damage` (تالف) أو `defect` (عطلان) — بلا اختيارٍ مسبق.
  String? _outKind;
  bool _down = true;
  late int _costValue = widget.item.costAvg.round();
  String? _paidFrom;
  bool _busy = false;

  /// مرجع الحركة: ضغطتان أو انقطاعٌ بعد الحفظ = حركةٌ واحدة (ولا ثمنٌ مرّتين)؛ يتجدّد بعد كلّ حكمٍ وكلّ تغييرٍ للنوع.
  String _ref = SalesApi.newClientRef();

  @override
  void dispose() {
    _qty.dispose();
    _cost.dispose();
    _note.dispose();
    super.dispose();
  }

  bool get _buy => _mode == 0;
  bool get _out => _mode == 1;
  bool get _count => _mode == 2;

  num? get _q => parseSaleQty(_qty.text);

  /// تغيّر المخزون: الشراء والزيادة موجبان، والتالف/العطلان والنقص سالبان.
  num? get _delta => _q == null ? null : (_buy || (_count && !_down) ? _q! : -_q!);
  num? get _after => _delta == null ? null : widget.item.qty + _delta!;
  num? get _newAvg {
    final q = _q;
    if (!_buy || q == null) return null;
    final it = widget.item;
    return it.qty > 0 ? (it.qty * it.costAvg + q * _costValue) / (it.qty + q) : _costValue;
  }

  num? get _amount => !_buy || _q == null || _cost.text.trim().isEmpty ? null : (_q! * _costValue).round();

  /// التالف/العطلان بالكلفة المتوسّطة الآن (الخادم يحسبها لحظة الحفظ).
  num? get _outValue => _out && _q != null ? widget.item.costAvg * _q! : null;
  String? get _kind => _buy ? 'purchase' : (_count ? 'adjust' : _outKind);

  bool get _ok =>
      !_busy &&
      _q != null &&
      _kind != null &&
      (_after ?? -1) >= 0 &&
      (_buy ? _cost.text.trim().isNotEmpty && _paidFrom != null : _note.text.trim().length >= 2);

  void _setOut(String k) => setState(() {
        _outKind = k;
        _ref = SalesApi.newClientRef();
      });

  Future<void> _submit() async {
    final kind = _kind;
    final q = _q;
    if (kind == null || q == null) return;
    setState(() => _busy = true);
    final r = await SalesApi.stock(
      widget.item.id,
      kind: kind,
      qty: _count ? _delta! : q,
      unitCost: _buy ? _costValue : null,
      note: _note.text.trim(),
      paidFrom: _buy ? _paidFrom : null,
      clientRef: _ref,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (r.ok) {
      final it = widget.item;
      final qty = saleQtyText(q, it.unit);
      final loss = r.loss ?? 0;
      showSheetSnack(
        context,
        switch (kind) {
          'adjust' => 'sales.adjusted'.tr(namedArgs: {'name': it.name, 'qty': saleQtyText(_after!, it.unit)}),
          'damage' => loss > 0
              ? 'sales.damaged_loss'.tr(namedArgs: {'name': it.name, 'qty': qty, 'amount': _money(loss)})
              : 'sales.damaged'.tr(namedArgs: {'name': it.name, 'qty': qty}),
          'defect' => 'sales.defected'.tr(namedArgs: {'name': it.name, 'qty': qty}),
          _ => _paidFrom == 'box' && (_amount ?? 0) > 0
              ? 'sales.purchased_box'.tr(namedArgs: {'name': it.name, 'qty': qty, 'amount': _money(_amount!)})
              : 'sales.purchased'.tr(namedArgs: {'name': it.name, 'qty': qty}),
        },
      );
      Navigator.of(context).pop(true);
      return;
    }
    if (!r.ambiguous && r.code != 'IN_PROGRESS') setState(() => _ref = SalesApi.newClientRef());
    showSheetSnack(context, r.message ?? 'sales.not_saved'.tr(), isError: true);
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final it = widget.item;
    final q = _q;
    final after = _after;
    final avg = _newAvg;
    final outValue = _outValue;
    final noteLabel = _buy
        ? 'sales.f_supplier_note'.tr()
        : '${(_count ? 'sales.f_reason' : _outKind == 'defect' ? 'sales.f_defect' : 'sales.f_damage_reason').tr()} *';
    return DesignSheet(
      header: SheetHeaderBar(
        icon: _buy ? LucideIcons.packagePlus : (_out ? LucideIcons.packageX : LucideIcons.clipboardCheck),
        title: it.name,
        subtitle: [
          'sales.stock_sub'.tr(namedArgs: {'qty': saleQtyText(it.qty, it.unit), 'amount': _money(it.costAvg)}),
          if (it.hasDefective) 'sales.defective_chip_n'.tr(namedArgs: {'qty': saleQtyText(it.qtyDefective, it.unit)}),
        ].join(' · '),
        onClose: () => Navigator.of(context).pop(),
      ),
      footer: SheetFooterBar(
        label: (_buy
                ? 'sales.purchase_btn'
                : _count
                    ? 'sales.count_btn'
                    : switch (_outKind) {
                        'damage' => 'sales.damage_btn',
                        'defect' => 'sales.defect_btn',
                        _ => 'sales.out_pick_btn',
                      })
            .tr(),
        icon: LucideIcons.check,
        enabled: _ok,
        busy: _busy,
        onPressed: _submit,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SheetSegmented(
            labels: ['sales.mode_purchase'.tr(), 'sales.mode_out'.tr(), 'sales.mode_count'.tr()],
            selectedIndex: _mode,
            onSelect: (i) => setState(() {
              _mode = i;
              _ref = SalesApi.newClientRef();
            }),
          ),
          if (_out) ...[
            const SizedBox(height: Sp.lg),
            SheetSection(
              label: '${'sales.out_q'.tr()} *',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _ChoiceCard(
                    selected: _outKind == 'damage',
                    icon: LucideIcons.packageX,
                    title: 'sales.damage_title'.tr(),
                    subtitle: 'sales.damage_sub'.tr(),
                    onTap: () => _setOut('damage'),
                  ),
                  const SizedBox(height: Sp.sm),
                  _ChoiceCard(
                    selected: _outKind == 'defect',
                    icon: LucideIcons.wrench,
                    title: 'sales.defect_title'.tr(),
                    subtitle: 'sales.defect_sub'.tr(),
                    onTap: () => _setOut('defect'),
                  ),
                ],
              ),
            ),
          ],
          if (_count) ...[
            const SizedBox(height: Sp.sm),
            SheetSegmented(
              labels: ['sales.dir_down'.tr(), 'sales.dir_up'.tr()],
              selectedIndex: _down ? 0 : 1,
              onSelect: (i) => setState(() {
                _down = i == 0;
                _ref = SalesApi.newClientRef();
              }),
            ),
          ],
          const SizedBox(height: Sp.lg),
          SheetSection(
            label: '${'sales.f_qty'.tr()} (${saleUnitLabel(it.unit)}) *',
            child: _SheetText(
              controller: _qty,
              icon: LucideIcons.hash,
              maxLength: 12,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              ltr: true,
              onChanged: (_) => setState(() {}),
            ),
          ),
          if (_buy) ...[
            const SizedBox(height: Sp.lg),
            SheetSection(
              label: '${'sales.f_unit_cost'.tr()} *',
              child: _MoneyField(controller: _cost, shorthand: widget.item.unit != 'meter', onValue: (v) => setState(() => _costValue = v)),
            ),
            const SizedBox(height: Sp.lg),
            _PaidFromChoice(value: _paidFrom, onChanged: (v) => setState(() => _paidFrom = v), amount: _amount),
          ],
          const SizedBox(height: Sp.lg),
          SheetSection(
            label: noteLabel,
            child: _SheetText(
              controller: _note,
              icon: LucideIcons.fileText,
              maxLength: 200,
              onChanged: (_) => setState(() {}),
            ),
          ),
          if (after != null) ...[
            const SizedBox(height: Sp.lg),
            SheetSummaryBox(
              label: 'sales.qty_after'.tr(),
              value: saleQtyText(after, it.unit),
              valueColor: after < 0 ? AppColors.error : null,
            ),
            if (avg != null) ...[
              const SizedBox(height: Sp.sm),
              SheetSummaryBox(label: 'sales.avg_after'.tr(), value: _money(avg)),
            ],
            if (after >= 0 && outValue != null && _outKind == 'damage') ...[
              const SizedBox(height: Sp.sm),
              SheetSummaryBox(label: 'sales.loss_preview'.tr(), value: _money(outValue), valueColor: AppColors.error),
            ],
            if (after >= 0 && outValue != null && q != null && _outKind == 'defect') ...[
              const SizedBox(height: Sp.sm),
              SheetSummaryBox(
                label: 'sales.defective_after'.tr(),
                value: '${saleQtyText(it.qtyDefective + q, it.unit)} · ${_money(it.defectiveValue + outValue)}',
              ),
            ],
            if (after < 0)
              Padding(
                padding: const EdgeInsets.only(top: Sp.xs),
                child: Text(
                  _out ? 'sales.out_over_n'.tr(namedArgs: {'qty': saleQtyText(it.qty, it.unit)}) : 'sales.below_zero'.tr(),
                  style: AppType.muted(color: AppColors.error).copyWith(fontSize: 11.5),
                ),
              ),
          ],
          const SizedBox(height: Sp.md),
          Text(
            (_buy ? 'sales.purchase_info' : (_out ? 'sales.out_info' : 'sales.count_info')).tr(),
            style: AppType.muted(color: AppColors.textMid).copyWith(fontSize: 11.5, height: 1.6),
          ),
        ],
      ),
    );
  }
}

/// أين دخل ما رجّعه المورّد — إجباريّ حين يرجّع مبلغاً: الصندوق يزيد صندوق التسوية بالمبلغ، وخارجه لا.
class _RefundToChoice extends StatelessWidget {
  const _RefundToChoice({required this.value, required this.onChanged, required this.amount});
  final String? value;
  final ValueChanged<String> onChanged;
  final num amount;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return SheetSection(
      label: '${'sales.refund_to'.tr()} *',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ChoiceCard(
            selected: value == 'box',
            icon: LucideIcons.wallet,
            title: 'sales.refund_box'.tr(),
            subtitle: 'sales.refund_box_sub_n'.tr(namedArgs: {'amount': _money(amount)}),
            onTap: () => onChanged('box'),
          ),
          const SizedBox(height: Sp.sm),
          _ChoiceCard(
            selected: value == 'outside',
            icon: LucideIcons.boxes,
            title: 'sales.refund_outside'.tr(),
            subtitle: 'sales.refund_outside_sub'.tr(),
            onTap: () => onChanged('outside'),
          ),
        ],
      ),
    );
  }
}

class _DefectSheet extends StatefulWidget {
  const _DefectSheet({required this.item});
  final SaleItem item;

  @override
  State<_DefectSheet> createState() => _DefectSheetState();
}

/// حسم خانة «العطلان» (قرار المالك ٢٣ أكتوبر): تصلّحت ⇒ للمخزون بكلفتها · ما تتصلّح ⇒ قيمتها خسارة ·
/// رجّعتها للمورّد ⇒ الخسارة قيمتها ناقص ما رجّعه (ومبلغه للصندوق أو خارجه). القيمة تقديرٌ بنسبة الكمّيّة —
/// الخادم يحسم.
class _DefectSheetState extends State<_DefectSheet> {
  late final _qtyCtl = TextEditingController(text: _qty3(widget.item.qtyDefective));
  final _refund = TextEditingController();
  final _note = TextEditingController();

  /// `repair` · `defect_writeoff` · `supplier_return` — بلا اختيارٍ مسبق.
  String? _action;
  int _refundValue = 0;
  String? _refundTo;
  bool _busy = false;
  String _ref = SalesApi.newClientRef();

  @override
  void dispose() {
    _qtyCtl.dispose();
    _refund.dispose();
    _note.dispose();
    super.dispose();
  }

  static String _qty3(num q) => q > 0 ? _qty(q) : '';

  num? get _q => parseSaleQty(_qtyCtl.text);
  bool get _over => (_q ?? 0) > widget.item.qtyDefective + 1e-9;
  num? get _value => _q == null || _over ? null : widget.item.defectiveValueOf(_q!);
  num? get _loss {
    final v = _value;
    if (v == null) return null;
    return switch (_action) {
      'defect_writeoff' => v,
      'supplier_return' => ((v - _refundValue) * 100).round() / 100,
      _ => null,
    };
  }

  num? get _after => _action == 'repair' && _q != null && !_over ? widget.item.qty + _q! : null;
  num? get _newAvg {
    final q = _q;
    final v = _value;
    if (_action != 'repair' || q == null || v == null) return null;
    final it = widget.item;
    return it.qty > 0 ? (it.qty * it.costAvg + v) / (it.qty + q) : v / q;
  }

  bool get _ok =>
      !_busy &&
      _action != null &&
      _q != null &&
      !_over &&
      (_action != 'defect_writeoff' || _note.text.trim().length >= 2) &&
      (_action != 'supplier_return' || _refundValue == 0 || _refundTo != null);

  void _pick(String a) => setState(() {
        _action = a;
        _ref = SalesApi.newClientRef();
      });

  Future<void> _submit() async {
    final a = _action;
    final q = _q;
    if (a == null || q == null) return;
    setState(() => _busy = true);
    final r = await SalesApi.stock(
      widget.item.id,
      kind: a,
      qty: q,
      note: _note.text.trim(),
      refund: a == 'supplier_return' ? _refundValue : null,
      refundTo: a == 'supplier_return' && _refundValue > 0 ? _refundTo : null,
      clientRef: _ref,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (r.ok) {
      final it = widget.item;
      final args = {'name': it.name, 'qty': saleQtyText(q, it.unit)};
      final l = r.loss ?? 0;
      showSheetSnack(
        context,
        [
          switch (a) {
            'repair' => 'sales.repaired'.tr(namedArgs: args),
            'defect_writeoff' => 'sales.written_off'.tr(namedArgs: args),
            _ => 'sales.returned'.tr(namedArgs: args),
          },
          if (a == 'supplier_return' && _refundValue > 0)
            (_refundTo == 'box' ? 'sales.returned_box_n' : 'sales.returned_out_n')
                .tr(namedArgs: {'amount': _money(_refundValue)}),
          if (l > 0) 'sales.mv_loss_n'.tr(namedArgs: {'amount': _money(l)}),
          if (l < 0) 'sales.mv_gain_n'.tr(namedArgs: {'amount': _money(-l)}),
        ].join(' · '),
      );
      Navigator.of(context).pop(true);
      return;
    }
    if (!r.ambiguous && r.code != 'IN_PROGRESS') setState(() => _ref = SalesApi.newClientRef());
    showSheetSnack(context, r.message ?? 'sales.not_saved'.tr(), isError: true);
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final it = widget.item;
    final a = _action;
    final value = _value;
    final loss = _loss;
    final after = _after;
    final avg = _newAvg;
    return DesignSheet(
      header: SheetHeaderBar(
        icon: LucideIcons.wrench,
        title: 'sales.defect_sheet_title_n'.tr(namedArgs: {'name': it.name}),
        subtitle: 'sales.defect_sheet_sub'.tr(
          namedArgs: {'qty': saleQtyText(it.qtyDefective, it.unit), 'amount': _money(it.defectiveValue)},
        ),
        onClose: () => Navigator.of(context).pop(),
      ),
      footer: SheetFooterBar(
        label: switch (a) {
          'repair' => 'sales.repair_btn',
          'defect_writeoff' => 'sales.writeoff_btn',
          'supplier_return' => 'sales.return_btn',
          _ => 'sales.defect_pick_btn',
        }
            .tr(),
        icon: LucideIcons.check,
        enabled: _ok,
        busy: _busy,
        onPressed: _submit,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SheetSection(
            label: '${'sales.out_q'.tr()} *',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _ChoiceCard(
                  selected: a == 'repair',
                  icon: LucideIcons.wrench,
                  title: 'sales.repair_title'.tr(),
                  subtitle: 'sales.repair_sub'.tr(),
                  onTap: () => _pick('repair'),
                ),
                const SizedBox(height: Sp.sm),
                _ChoiceCard(
                  selected: a == 'defect_writeoff',
                  icon: LucideIcons.trash2,
                  title: 'sales.writeoff_title'.tr(),
                  subtitle: 'sales.writeoff_sub'.tr(),
                  onTap: () => _pick('defect_writeoff'),
                ),
                const SizedBox(height: Sp.sm),
                _ChoiceCard(
                  selected: a == 'supplier_return',
                  icon: LucideIcons.truck,
                  title: 'sales.return_title'.tr(),
                  subtitle: 'sales.return_sub'.tr(),
                  onTap: () => _pick('supplier_return'),
                ),
              ],
            ),
          ),
          const SizedBox(height: Sp.lg),
          SheetSection(
            label: '${'sales.f_qty'.tr()} (${saleUnitLabel(it.unit)}) *',
            child: _SheetText(
              controller: _qtyCtl,
              icon: LucideIcons.hash,
              maxLength: 12,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              ltr: true,
              onChanged: (_) => setState(() {}),
            ),
          ),
          if (a == 'supplier_return') ...[
            const SizedBox(height: Sp.lg),
            SheetSection(
              label: 'sales.f_refund'.tr(),
              child: _MoneyField(controller: _refund, onValue: (v) => setState(() => _refundValue = v)),
            ),
            Padding(
              padding: const EdgeInsets.only(top: Sp.xs),
              child: Text('sales.f_refund_hint'.tr(), style: AppType.muted(color: AppColors.textMid).copyWith(fontSize: 11.5)),
            ),
            if (_refundValue > 0) ...[
              const SizedBox(height: Sp.lg),
              _RefundToChoice(value: _refundTo, onChanged: (v) => setState(() => _refundTo = v), amount: _refundValue),
            ],
          ],
          const SizedBox(height: Sp.lg),
          SheetSection(
            label: a == 'defect_writeoff' ? '${'sales.f_reason'.tr()} *' : 'sales.f_note_opt'.tr(),
            child: _SheetText(
              controller: _note,
              icon: LucideIcons.fileText,
              maxLength: 200,
              onChanged: (_) => setState(() {}),
            ),
          ),
          if (_over)
            Padding(
              padding: const EdgeInsets.only(top: Sp.sm),
              child: Text(
                'sales.defective_over_n'.tr(namedArgs: {'qty': saleQtyText(it.qtyDefective, it.unit)}),
                style: AppType.muted(color: AppColors.error).copyWith(fontSize: 11.5),
              ),
            )
          else if (a != null && value != null) ...[
            const SizedBox(height: Sp.lg),
            SheetSummaryBox(label: 'sales.value_at_cost'.tr(), value: _money(value)),
            if (after != null) ...[
              const SizedBox(height: Sp.sm),
              SheetSummaryBox(label: 'sales.qty_stock_after'.tr(), value: saleQtyText(after, it.unit)),
            ],
            if (avg != null) ...[
              const SizedBox(height: Sp.sm),
              SheetSummaryBox(label: 'sales.avg_after'.tr(), value: _money(avg)),
            ],
            if (loss != null) ...[
              const SizedBox(height: Sp.sm),
              SheetSummaryBox(
                label: (loss >= 0 ? 'sales.loss' : 'sales.gain').tr(),
                value: _money(loss.abs()),
                valueColor: loss > 0 ? AppColors.error : AppColors.success,
              ),
            ],
          ],
          const SizedBox(height: Sp.md),
          Text(
            'sales.defect_info'.tr(),
            style: AppType.muted(color: AppColors.textMid).copyWith(fontSize: 11.5, height: 1.6),
          ),
        ],
      ),
    );
  }
}

class _MovesSheet extends StatefulWidget {
  const _MovesSheet({required this.item, this.canItems = false, this.onChanged});
  final SaleItem item;

  /// إلغاء الحركة اليدويّة الخاطئة بصلاحيّة الموادّ (والقسم مفعّل).
  final bool canItems;

  /// بعد إلغاء حركة: تُحدَّث الموادّ خلف الشيت فوراً (مهما أُغلق بعدها).
  final Future<void> Function()? onChanged;

  @override
  State<_MovesSheet> createState() => _MovesSheetState();
}

class _MovesSheetState extends State<_MovesSheet> {
  List<StockMove>? _rows;
  String? _error;

  /// إلغاء حركةٍ يدويّة خاطئة (شراء، فرق عدّ، تالف، عطلان، تصليح، شطب، إرجاعٌ للمورّد) — آخر حركةٍ على
  /// المادّة وحدها: يرجع كلّ شيءٍ كما كان، والخسارة تُلغى، والنقد بعكسه.
  StockMove? _voiding;
  final _reason = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  void _load() {
    SalesApi.moves(widget.item.id).then((r) {
      if (!mounted) return;
      setState(() {
        _rows = r.rows;
        _error = r.error;
      });
    });
  }

  Future<void> _submitVoid() async {
    final m = _voiding;
    if (m == null) return;
    setState(() => _busy = true);
    final r = await SalesApi.voidMove(widget.item.id, m.id, _reason.text.trim());
    if (!mounted) return;
    setState(() => _busy = false);
    if (r.ok) {
      showSheetSnack(
        context,
        m.kind == 'purchase'
            ? (r.refund > 0
                ? 'sales.purchase_voided_box'.tr(namedArgs: {'amount': _money(r.refund)})
                : 'sales.purchase_voided'.tr())
            : [
                'sales.move_voided'.tr(namedArgs: {'kind': _kind(m.kind)}),
                if ((m.loss ?? 0) != 0) 'sales.move_voided_loss'.tr(),
                if (r.boxDelta > 0) 'sales.move_voided_box_in_n'.tr(namedArgs: {'amount': _money(r.boxDelta)}),
                if (r.boxDelta < 0) 'sales.move_voided_box_out_n'.tr(namedArgs: {'amount': _money(-r.boxDelta)}),
              ].join(' · '),
      );
      setState(() {
        _voiding = null;
        _reason.clear();
        _rows = null;
      });
      _load();
      widget.onChanged?.call();
      return;
    }
    showSheetSnack(context, r.message ?? 'sales.not_saved'.tr(), isError: true);
    _load();
  }

  static String _kind(String k) => switch (k) {
        'purchase' => 'sales.mv_purchase'.tr(),
        'sale' => 'sales.mv_sale'.tr(),
        'return' => 'sales.mv_return'.tr(),
        'purchase_void' => 'sales.mv_purchase_void'.tr(),
        'damage' => 'sales.mv_damage'.tr(),
        'defect' => 'sales.mv_defect'.tr(),
        'repair' => 'sales.mv_repair'.tr(),
        'defect_writeoff' => 'sales.mv_defect_writeoff'.tr(),
        'supplier_return' => 'sales.mv_supplier_return'.tr(),
        'void' => 'sales.mv_void'.tr(),
        _ => 'sales.mv_adjust'.tr(),
      };

  /// أثر الحركة بالمال: خسارتها (موجبة) أو ربحها، وسطر الإلغاء يُلغيهما — الموجب سيّئٌ دائماً.
  static String? _lossText(StockMove m) {
    final l = m.loss ?? 0;
    if (l == 0) return null;
    final amount = {'amount': _money(l.abs())};
    if (m.kind == 'void') return (l < 0 ? 'sales.mv_loss_undone_n' : 'sales.mv_gain_undone_n').tr(namedArgs: amount);
    return (l > 0 ? 'sales.mv_loss_n' : 'sales.mv_gain_n').tr(namedArgs: amount);
  }

  /// ما يرجع بالضبط عند إلغاء الحركة.
  static String _voidInfo(StockMove v) {
    final q = _qty(v.qty.abs());
    if (v.kind == 'purchase') {
      return v.paidFrom == 'box' && v.unitCost != null
          ? 'sales.purchase_void_info_box'.tr(namedArgs: {'qty': q, 'amount': _money((v.qty * v.unitCost!).round())})
          : 'sales.purchase_void_info'.tr(namedArgs: {'qty': q});
    }
    final base = switch (v.kind) {
      'adjust' => 'sales.void_info_adjust'.tr(namedArgs: {'qty': '${v.qty > 0 ? '+' : '−'}$q'}),
      'damage' => 'sales.void_info_damage'.tr(namedArgs: {'qty': q}),
      'defect' => 'sales.void_info_defect'.tr(namedArgs: {'qty': q}),
      'repair' => 'sales.void_info_repair'.tr(namedArgs: {'qty': q}),
      'defect_writeoff' => 'sales.void_info_writeoff'.tr(namedArgs: {'qty': q}),
      'supplier_return' => 'sales.void_info_return'.tr(namedArgs: {'qty': q}),
      _ => 'sales.void_info_other'.tr(namedArgs: {'kind': _kind(v.kind)}),
    };
    return '${[
      base,
      if ((v.loss ?? 0) != 0) 'sales.void_info_loss_n'.tr(namedArgs: {'amount': _money(v.loss!.abs())}),
      if (v.kind == 'supplier_return' && v.paidFrom == 'box' && (v.refund ?? 0) > 0)
        'sales.void_info_box_n'.tr(namedArgs: {'amount': _money(v.refund!)}),
    ].join('sales.void_info_sep'.tr())}.';
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final it = widget.item;
    final rows = _rows;
    final v = _voiding;
    return PopScope(
      canPop: !_busy,
      child: DesignSheet(
        header: SheetHeaderBar(
          icon: LucideIcons.history,
          title: 'sales.moves_title_n'.tr(namedArgs: {'name': it.name}),
          subtitle: [
            'sales.available_n'.tr(namedArgs: {'qty': saleQtyText(it.qty, it.unit)}),
            if (it.hasDefective) 'sales.defective_chip_n'.tr(namedArgs: {'qty': saleQtyText(it.qtyDefective, it.unit)}),
          ].join(' · '),
          onClose: () => Navigator.of(context).pop(),
        ),
        footer: v == null
            ? null
            : SheetFooterBar(
                label: (v.kind == 'purchase' ? 'sales.purchase_void_btn' : 'sales.move_void_btn').tr(),
                icon: LucideIcons.undo2,
                color: AppColors.error,
                enabled: _reason.text.trim().length >= 2 && !_busy,
                busy: _busy,
                onPressed: _submitVoid,
                above: Padding(
                  padding: const EdgeInsets.only(bottom: Sp.sm),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        _voidInfo(v),
                        style: AppType.muted(color: AppColors.textMid).copyWith(fontSize: 12.5, height: 1.6),
                      ),
                      const SizedBox(height: Sp.sm),
                      _SheetText(
                        controller: _reason,
                        icon: LucideIcons.fileText,
                        hint: (v.kind == 'purchase' ? 'sales.purchase_void_hint' : 'sales.move_void_hint').tr(),
                        maxLength: 200,
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: Sp.xs),
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: TextButton(
                          onPressed: _busy
                              ? null
                              : () => setState(() {
                                    _voiding = null;
                                    _reason.clear();
                                  }),
                          child: Text('sales.purchase_void_cancel'.tr()),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
        body: rows == null
            ? (_error != null
                ? _Notice(icon: LucideIcons.history, text: _error!)
                : const Padding(
                    padding: EdgeInsets.symmetric(vertical: Sp.huge),
                    child: Center(child: CircularProgressIndicator()),
                  ))
            : rows.isEmpty
                ? _Notice(icon: LucideIcons.history, text: 'sales.no_moves'.tr())
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final m in rows)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: Sp.x6),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Wrap(
                                      spacing: Sp.x6,
                                      runSpacing: Sp.xxs,
                                      crossAxisAlignment: WrapCrossAlignment.center,
                                      children: [
                                        Text(
                                          m.saleId == null ? _kind(m.kind) : '${_kind(m.kind)} #${m.saleId}',
                                          style: AppType.label(color: m.voided ? AppColors.textLow : AppColors.textHi)
                                              .copyWith(fontSize: 13.5, decoration: m.voided ? TextDecoration.lineThrough : null),
                                        ),
                                        if (m.kind == 'purchase' && m.paidFrom != null)
                                          _Chip(
                                            (m.paidFrom == 'box' ? 'sales.paid_box' : 'sales.paid_outside').tr(),
                                            m.paidFrom == 'box' ? AppTone.warning : AppTone.neutral,
                                          ),
                                        if (m.voided) _Chip('sales.st_void'.tr(), AppTone.neutral),
                                      ],
                                    ),
                                    Text(
                                      [
                                        if ((m.kind == 'purchase' || m.kind == 'purchase_void') && m.unitCost != null)
                                          'sales.mv_cost_n'.tr(namedArgs: {'amount': _money(m.unitCost!)}),
                                        if (m.note != null) m.note!,
                                        m.employeeId == null ? 'sales.manager'.tr() : (m.by ?? 'settle.employee'.tr()),
                                        iso(_time(m.at)),
                                      ].join(' · '),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: AppType.muted(color: AppColors.textMid).copyWith(fontSize: 11.5),
                                    ),
                                    // أثر الحركة: الخسارة أو إلغاؤها، وما رجّعه المورّد وأين دخل، والعطلان بعدها.
                                    if (_lossText(m) != null || (m.refund ?? 0) != 0 || (m.defectiveAfter != null && !m.defectiveOnly))
                                      Wrap(
                                        spacing: Sp.sm,
                                        children: [
                                          if (_lossText(m) != null)
                                            Text(
                                              _lossText(m)!,
                                              style: AppType.muted(color: (m.loss ?? 0) > 0 ? AppColors.error : AppColors.success)
                                                  .copyWith(fontSize: 11.5),
                                            ),
                                          if ((m.refund ?? 0) != 0)
                                            Text(
                                              [
                                                ((m.refund ?? 0) > 0 ? 'sales.mv_refund_n' : 'sales.mv_refund_undone_n')
                                                    .tr(namedArgs: {'amount': _money(m.refund!.abs())}),
                                                if (m.paidFrom == 'box') 'sales.refund_box'.tr(),
                                                if (m.paidFrom == 'outside') 'sales.refund_outside'.tr(),
                                              ].join(' · '),
                                              style: AppType.muted(color: AppColors.textMid).copyWith(fontSize: 11.5),
                                            ),
                                          if (m.defectiveAfter != null && !m.defectiveOnly)
                                            Text(
                                              'sales.mv_def_after_n'.tr(namedArgs: {'qty': _qty(m.defectiveAfter!)}),
                                              style: AppType.muted(color: AppColors.textMid).copyWith(fontSize: 11.5),
                                            ),
                                        ],
                                      ),
                                    if (m.voidable && widget.canItems && v == null)
                                      Padding(
                                        padding: const EdgeInsets.only(top: Sp.xxs),
                                        child: TextButton.icon(
                                          onPressed: () => setState(() => _voiding = m),
                                          icon: Icon(LucideIcons.undo2, size: 14, color: AppColors.error),
                                          label: Text(
                                            (m.kind == 'purchase' ? 'sales.purchase_void_btn' : 'sales.move_void_btn').tr(),
                                            style: AppType.label(color: AppColors.error).copyWith(fontSize: 12.5),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: Sp.sm),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    '${m.qty > 0 ? '+' : '-'}${_qty(m.qty.abs())}',
                                    textDirection: TextDirection.ltr,
                                    style: AppType.label(color: m.qty < 0 ? AppColors.error : AppColors.success)
                                        .copyWith(fontSize: 14, fontWeight: FontWeight.w700),
                                  ),
                                  // حركةٌ على خانة العطلان وحدها: المخزون لم يتغيّر ⇒ العمود يعرض العطلان بعدها.
                                  Text(
                                    m.defectiveOnly
                                        ? 'sales.def_after_short_n'.tr(namedArgs: {'qty': _qty(m.defectiveAfter!)})
                                        : '← ${_qty(m.qtyAfter)}',
                                    style: AppType.muted(color: AppColors.textMid).copyWith(fontSize: 11),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
      ),
    );
  }
}
