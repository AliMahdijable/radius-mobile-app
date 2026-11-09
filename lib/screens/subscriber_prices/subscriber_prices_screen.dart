import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../api/subscriber_prices_api.dart';
import '../../api/big_subscribers_api.dart';
import '../../api/subscribers_api.dart';
import '../../core/util/amount_input.dart';
import '../../core/util/format.dart';
import '../../core/widgets/sheet_scaffold.dart';
import '../../models/subscriber.dart';
import '../../services/permissions_service.dart';
import '../../services/subscriber_events.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import '../subscribers/sheets/subscriber_price_sheet.dart';
import '../desktop/desk_widgets.dart';
import '../../core/platform/desktop_layout.dart';
import '../desktop/desk_bulk_picker.dart';
import '../../core/widgets/app_sheet.dart';
import '../../widgets/merged_section.dart';
import '../../widgets/list_kit.dart';

/// «أسعار المشتركين» — على نمط شاشة الخصومات عمداً (طلب المستخدم: «أشبه
/// بقسم الخصومات»): سعرٌ يُكتب، ومشتركون يُحدَّدون، وزرّ تطبيق. ومعها
/// «الأسعار الحاليّة» للتعديل والحذف فرديّاً.
///
/// القواعد في الخادم: الثابت يلغي الخصم، ومربوطٌ بباقة المشترك عند الضبط.
class SubscriberPricesScreen extends StatefulWidget {
  const SubscriberPricesScreen({super.key});

  @override
  State<SubscriberPricesScreen> createState() => _SubscriberPricesScreenState();
}

class _SubscriberPricesScreenState extends State<SubscriberPricesScreen> {
  final _amountCtrl = TextEditingController();
  final _searchCtrl = TextEditingController();
  int _amount = 0;
  bool _suppressFormat = false;
  bool _submitting = false;
  bool _loading = true;
  bool _loadFailed = false;

  List<Subscriber> _all = const [];

  /// idx → السعر الثابت المحفوظ (مما وضعه هذا المدير أو موظّفوه).
  Map<String, SubscriberPrice> _prices = const {};
  final Set<String> _selected = {};
  String _query = '';

  bool get _canManage => Perms.has('subscriber_prices.manage');

  @override
  void initState() {
    super.initState();
    _amountCtrl.addListener(_onAmount);
    _searchCtrl.addListener(() {
      final q = _searchCtrl.text.trim();
      if (q != _query) {
        setState(() => _query = q);
        if (_big) _bigSearch.search(q, onRows: _setBigRows);
      }
    });
    _load();
  }

  @override
  void dispose() {
    _bigSearch.dispose();
    _amountCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  /// الحساب الكبير (≥ ٥٠٠٠): المشتركون من بحث الساس (١٠٠ لكلّ بحث) بدل القائمة الكاملة — والاختيار يبقى عبر البحوث.
  bool _big = false;
  final _bigSearch = BigSearch();
  Map<String, PackageInfo> _packages = const {};

  void _setBigRows(List<Subscriber> rows) {
    if (!mounted) return;
    setState(() => _all = rows.where((s) => s.idx != null).map((s) => s.enrichWithPackages(_packages)).toList());
  }

  /// الحساب الكبير: الصفحة التالية من الساس حين يقترب التمرير من الآخر — تُلحق بلا تكرار.
  Future<void> _bigMore() async {
    if (!_big || !_bigSearch.hasMore || _bigSearch.loadingMore) return;
    final f = _bigSearch.more();
    setState(() {}); // «جارٍ تحميل المزيد…»
    final rows = await f;
    if (!mounted) return;
    setState(() {
      if (rows == null || rows.isEmpty) return;
      final seen = {for (final s in _all) s.idx};
      _all = [
        ..._all,
        for (final s in rows)
          if (s.idx != null && seen.add(s.idx)) s.enrichWithPackages(_packages),
      ];
    });
  }

  bool _onGridScroll(ScrollNotification n) {
    if (_big && n.metrics.extentAfter < 600) _bigMore();
    return false;
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final results = await Future.wait([
      SubscribersApi.loadAll(),
      SubscriberPricesApi.list(),
      // سعر الباقة الأصليّ على كلّ كارت — كما تفعل شاشة المشتركين: القائمة
      // لا تحمله، والكتالوج يملؤه (ولا يكتب فوق الثابت).
      SubscribersApi.loadPackages(),
    ]);
    if (!mounted) return;
    final subs = results[0] as List<Subscriber>?;
    final prices = results[1] as List<SubscriberPrice>?;
    final packages = results[2] as Map<String, PackageInfo>? ?? const {};
    _big = subs == null && await BigSubscribersApi.probe() > 0;
    if (!mounted) return;
    if (_big) _bigSearch.search(_query, onRows: _setBigRows, now: true);
    setState(() {
      _packages = packages;
      _all = (subs ?? const <Subscriber>[])
          .where((s) => s.idx != null)
          .map((s) => s.enrichWithPackages(packages))
          .toList();
      _prices = {for (final p in prices ?? const <SubscriberPrice>[]) p.idx: p};
      _loadFailed = prices == null;
      _loading = false;
    });
  }

  /// تنسيق الآلاف أثناء الكتابة — كحقل شاشة الخصومات حرفيّاً.
  void _onAmount() {
    if (_suppressFormat) return;
    final digits = _amountCtrl.text.replaceAll(RegExp(r'[^0-9]'), '');
    final parsed = int.tryParse(digits) ?? 0;
    final formatted = _fmt(parsed);
    if (formatted != _amountCtrl.text) {
      _suppressFormat = true;
      _amountCtrl.value = TextEditingValue(
        text: formatted,
        selection: TextSelection.collapsed(offset: formatted.length),
      );
      _suppressFormat = false;
    }
    if (parsed != _amount) setState(() => _amount = parsed);
  }

  static String _fmt(int v) {
    if (v == 0) return '';
    final s = v.toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return buf.toString();
  }

  List<Subscriber> get _filtered {
    if (_big || _query.isEmpty) return _all; // الكبير: الساس بحث
    final q = _query.toLowerCase();
    return _all
        .where((s) =>
            s.username.toLowerCase().contains(q) ||
            s.fullName.toLowerCase().contains(q) ||
            s.displayPhone.contains(q))
        .toList();
  }

  int get _selectedWithPrice =>
      _selected.where((idx) => _prices.containsKey(idx)).length;

  void _toggle(String idx) => setState(() {
        if (!_selected.remove(idx)) _selected.add(idx);
      });

  Future<void> _apply() async {
    if (_submitting || _amount <= 0 || _selected.isEmpty) return;
    setState(() => _submitting = true);
    final r = await SubscriberPricesApi.bulkApply(_selected.toList(), _amount);
    if (!mounted) return;
    setState(() => _submitting = false);
    showSheetSnack(
      context,
      r.ok
          ? (r.failed > 0
              ? 'sp.bulk_partial'.tr(args: ['${r.applied}', '${r.failed}'])
              : 'sp.bulk_applied'.tr(args: ['${r.applied}']))
          : (r.message ?? 'sp.save_failed'.tr()),
      isError: !r.ok,
    );
    if (r.ok) {
      _selected.clear();
      _amountCtrl.clear();
      _amount = 0;
      SubscriberEvents.notifyChange();
      _load();
    }
  }

  Future<void> _removeSelected() async {
    final idxs = _selected.where((i) => _prices.containsKey(i)).toList();
    if (idxs.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('sp.remove_title'.tr()),
        content: Text('sp.bulk_remove_body'.tr(args: ['${idxs.length}'])),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(c).pop(false),
            child: Text('common.cancel'.tr()),
          ),
          TextButton(
            onPressed: () => Navigator.of(c).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: Text('common.delete'.tr()),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _submitting = true);
    final r = await SubscriberPricesApi.bulkRemove(idxs);
    if (!mounted) return;
    setState(() => _submitting = false);
    showSheetSnack(
      context,
      r.ok
          ? 'sp.bulk_removed'.tr(args: ['${r.removed}'])
          : (r.message ?? 'sp.remove_failed'.tr()),
      isError: !r.ok,
    );
    if (r.ok) {
      _selected.clear();
      SubscriberEvents.notifyChange();
      _load();
    }
  }

  Future<void> _openExisting() async {
    final byIdx = {for (final s in _all) s.idx!: s};
    final changed = await showAppSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: AppColors.scrim,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _ExistingPricesSheet(
        prices: _prices.values.toList(),
        subsByIdx: byIdx,
      ),
    );
    if (changed == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final accent = AppColors.brandAccent;
    final filtered = _filtered;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: deskPageBar(
        context,
        mobile: AppBar(
          backgroundColor: AppColors.surface,
          elevation: 0,
          scrolledUnderElevation: 0,
          title: Text(
            'sp.title'.tr(),
            style: AppType.title(color: AppColors.textHi).copyWith(fontSize: 16),
          ),
          iconTheme: IconThemeData(color: AppColors.textHi),
        ),
      ),
      body: MergedSectionBody(child: DesktopScope.of(context)
          ? _desktopBody(filtered, accent)
          : _phoneBody(filtered, accent)),
      // الهاتف (٩ نوفمبر — التصميم الجديد): شريط التحديد حين يُحدَّد أحد — العدد ومسحٌ و«إلغاء السعر» و«سعر ثابت» يفتح ورقة المبلغ.
      // (زرّ النظام نفسه في الورقة — كان `FilledButton` بنصٍّ أبيض صراحةً فصار أبيضَ على رماديّ حين يتعطّل.)
      bottomNavigationBar: !_canManage || DesktopScope.of(context) || _selected.isEmpty
          ? null
          : ListSelectionBar(
              count: _selected.length,
              onClear: () => setState(_selected.clear),
              actions: [
                ListBarButton(
                  key: const ValueKey('prices-remove'),
                  label: 'sp.bar_remove'.tr(),
                  icon: LucideIcons.trash2,
                  tone: ListTone.danger,
                  filled: false,
                  onPressed: _selectedWithPrice == 0 || _submitting ? null : _removeSelected,
                ),
                ListBarButton(
                  key: const ValueKey('prices-apply'),
                  label: _submitting ? 'sp.applying'.tr() : 'sp.bar_set'.tr(),
                  icon: LucideIcons.banknote,
                  busy: _submitting,
                  onPressed: _openApplySheet,
                ),
              ],
            ),
    );
  }

  /// ورقة السعر ثمّ التطبيق — المنطق نفسه (_apply) بالسعر المختار.
  Future<void> _openApplySheet() async {
    if (_selected.isEmpty || _submitting) return;
    final n = _selected.length;
    final v = await showListAmountSheet(
      context,
      title: 'sp.sheet_bulk_title'.tr(args: ['$n']),
      subtitle: 'sp.sheet_bulk_sub'.tr(),
      icon: LucideIcons.banknote,
      fieldLabel: 'sp.fixed_price'.tr(),
      confirmLabel: 'sp.apply_n'.tr(args: ['{amount}', '$n']),
      quickSets: const [25000, 30000, 35000, 45000, 50000],
      previewOf: (a) => 'sp.preview_sale'.tr(args: [formatIQD(a)]),
    );
    if (v == null || v <= 0 || !mounted) return;
    _amount = v;
    await _apply();
  }

  /// الهاتف (٩ نوفمبر — المالك: «القائمة الوحيده تصميمها بالهاتف مزعج ورديئ»): بطاقتا «سعرٌ ثابت» و«يحتاج تسعير»، ثمّ «الأسعار
  /// الحاليّة»، ثمّ البحث وشرائح «الكلّ · بسعرٍ ثابت · بلا سعر»، ثمّ صفٌّ لكلّ مشترك يُلمس للتحديد — بدل شبكة الكرتات الصغيرة.
  Widget _phoneBody(List<Subscriber> filtered, Color accent) {
    final rows = switch (_deskFilter) {
      1 => filtered.where((s) => _prices.containsKey(s.idx)).toList(),
      2 => filtered.where((s) => !_prices.containsKey(s.idx)).toList(),
      _ => filtered,
    };
    final reprice = _all.where((s) => s.needsRepricing).length;
    return RefreshIndicator(
      onRefresh: _load,
      color: accent,
      child: NotificationListener<ScrollNotification>(
        onNotification: _onGridScroll,
        child: CustomScrollView(
          key: const ValueKey('prices-list'),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, Sp.sm),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  Row(children: [
                    Expanded(
                      child: ListKpiTile(
                        icon: LucideIcons.banknote,
                        tone: ListTone.success,
                        label: 'sp.fixed_count_label'.tr(),
                        value: '${_prices.length}',
                        active: _deskFilter == 1,
                        onTap: () => setState(() => _deskFilter = _deskFilter == 1 ? 0 : 1),
                      ),
                    ),
                    const SizedBox(width: Sp.sm),
                    Expanded(
                      child: ListKpiTile(
                        icon: LucideIcons.triangleAlert,
                        tone: ListTone.warning,
                        label: 'sp.needs_repricing_short'.tr(),
                        value: _big ? '—' : '$reprice',
                      ),
                    ),
                  ]),
                  if (_loadFailed) ...[
                    const SizedBox(height: Sp.sm),
                    Text('sp.load_failed'.tr(), style: AppType.micro(color: AppColors.error)),
                  ],
                  const SizedBox(height: Sp.sm),
                  _ActionCard(
                    icon: LucideIcons.list,
                    label: 'sp.current_prices'.tr(),
                    sub: 'sp.current_count'.tr(args: ['${_prices.length}']),
                    color: accent,
                    onTap: _prices.isEmpty ? null : _openExisting,
                  ),
                  const SizedBox(height: Sp.xs),
                ]),
              ),
            ),
            // البحث والشرائح والعدّ مثبّتةٌ أعلى القائمة أثناء التمرير (الطويلة خاصّةً)
            PinnedHeaderSliver(
              child: ColoredBox(
                color: AppColors.bg,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.sm, Sp.lg, Sp.sm),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ListSearchField(controller: _searchCtrl, hint: 'sp.search'.tr()),
                      const SizedBox(height: Sp.sm),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(children: [
                          ListFilterChip(label: 'sp.filter_all'.tr(), active: _deskFilter == 0, onTap: () => setState(() => _deskFilter = 0)),
                          const SizedBox(width: Sp.x6),
                          ListFilterChip(
                            label: 'sp.filter_fixed'.tr(),
                            icon: LucideIcons.banknote,
                            tone: ListTone.success,
                            count: _prices.length,
                            active: _deskFilter == 1,
                            onTap: () => setState(() => _deskFilter = 1),
                          ),
                          const SizedBox(width: Sp.x6),
                          ListFilterChip(label: 'sp.filter_none'.tr(), active: _deskFilter == 2, onTap: () => setState(() => _deskFilter = 2)),
                        ]),
                      ),
                      const SizedBox(height: Sp.sm),
                      _selectionBar(accent, filtered.length),
                    ],
                  ),
                ),
              ),
            ),
            if (_loading)
              const SliverFillRemaining(hasScrollBody: false, child: Center(child: CircularProgressIndicator()))
            else if (rows.isEmpty)
              SliverToBoxAdapter(child: _emptyState())
            else
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: Sp.lg),
                sliver: DecoratedSliver(
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(R.lg),
                    border: Border.all(color: AppColors.border),
                  ),
                  sliver: SliverList.separated(
                    itemCount: rows.length,
                    separatorBuilder: (_, __) => Divider(height: 1, thickness: 1, color: AppColors.divider),
                    itemBuilder: (_, i) {
                      final s = rows[i];
                      final fixed = _prices[s.idx]?.price;
                      final hasName = s.fullName.trim().isNotEmpty && s.fullName != s.username;
                      final sale = s.currentSalePrice;
                      final sub = [if (hasName) s.username, if ((s.profileName ?? '').isNotEmpty) s.profileName!].join(' · ');
                      return ListSubscriberRow(
                        key: ValueKey('price-row-${s.idx}'),
                        title: hasName ? s.fullName : s.username,
                        subtitle: sub,
                        selectable: _canManage,
                        selected: _selected.contains(s.idx),
                        onTap: _canManage && s.idx != null ? () => _toggle(s.idx!) : null,
                        trailing: ListAmountCell(
                          amount: sale == null ? '—' : formatIQD(sale),
                          badge: s.needsRepricing ? 'sp.needs_repricing_short'.tr() : (fixed != null ? 'sp.op_fixed_price'.tr() : null),
                          badgeTone: s.needsRepricing ? ListTone.warning : ListTone.success,
                        ),
                      );
                    },
                  ),
                ),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: Sp.huge)),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // الحاسبة: جدولٌ بتحديد + لوحةٌ جانبيّة للتطبيق والملخّص
  // ============================================================

  /// فلتر جدول الحاسبة: الكلّ · بسعرٍ ثابت · بلا سعر.
  int _deskFilter = 0;

  Widget _desktopBody(List<Subscriber> filtered, Color accent) {
    final rows = switch (_deskFilter) {
      1 => filtered.where((s) => _prices.containsKey(s.idx)).toList(),
      2 => filtered.where((s) => !_prices.containsKey(s.idx)).toList(),
      _ => filtered,
    };
    final selectable = rows.where((s) => s.idx != null).toList();
    final allOn = selectable.isNotEmpty && selectable.every((s) => _selected.contains(s.idx));
    final muted = AppType.muted(color: AppColors.textMid).copyWith(fontSize: 13);
    final money = AppType.label(color: AppColors.textBody).copyWith(fontSize: 13.5, fontWeight: FontWeight.w600);
    return DeskBulkPicker(
      searchController: _searchCtrl,
      searchHint: 'sp.search_hint_desk'.tr(),
      filters: DeskSegmented<int>(
        values: const [0, 1, 2],
        labelOf: (v) => ['sp.filter_all'.tr(), 'sp.filter_fixed'.tr(), 'sp.filter_none'.tr()][v],
        current: _deskFilter,
        onChanged: (v) => setState(() => _deskFilter = v),
      ),
      columns: [
        DeskPickColumn('desktop.col_name'.tr(), flex: 3),
        DeskPickColumn('desktop.col_package'.tr(), flex: 2),
        DeskPickColumn('sp.col_package_price'.tr(), width: 120, align: AlignmentDirectional.centerEnd),
        DeskPickColumn('sp.col_fixed'.tr(), width: 120, align: AlignmentDirectional.center),
        DeskPickColumn('sp.col_sale'.tr(), width: 120, align: AlignmentDirectional.centerEnd),
      ],
      rowCount: rows.length,
      cellsOf: (i) {
        final s = rows[i];
        final fixed = _prices[s.idx]?.price;
        final hasName = s.fullName.trim().isNotEmpty && s.fullName != s.username;
        final base = s.packageSalePrice;
        final sale = s.currentSalePrice;
        return [
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(hasName ? s.fullName : s.username,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.label(color: AppColors.textHi).copyWith(fontSize: 14, fontWeight: FontWeight.w700)),
              if (hasName)
                Text(s.username, maxLines: 1, overflow: TextOverflow.ellipsis, style: muted),
            ],
          ),
          Text(s.profileName ?? '—', maxLines: 1, overflow: TextOverflow.ellipsis, style: muted),
          Text(base == null ? '—' : formatIQD(base), style: money),
          s.needsRepricing
              ? Tooltip(
                  message: 'sp.needs_repricing_short'.tr(),
                  child: Icon(LucideIcons.triangleAlert, size: 16, color: AppColors.warning),
                )
              : fixed != null
                  ? Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: AppColors.brandSoftBg, borderRadius: BorderRadius.circular(R.sm)),
                      child: Text(formatIQD(fixed),
                          style: AppType.label(color: AppColors.brandOnSoft).copyWith(fontSize: 12.5, fontWeight: FontWeight.w700)),
                    )
                  : Text('—', style: muted),
          Text(sale == null ? '—' : formatIQD(sale), style: money.copyWith(fontWeight: FontWeight.w700)),
        ];
      },
      selectedOf: (i) => _selected.contains(rows[i].idx),
      onToggle: _canManage ? (i) { if (rows[i].idx != null) _toggle(rows[i].idx!); } : null,
      allSelected: allOn,
      onToggleAll: () => setState(() {
        for (final s in selectable) {
          allOn ? _selected.remove(s.idx) : _selected.add(s.idx!);
        }
      }),
      footer: _big && _bigSearch.total > filtered.length
          ? 'sp.selection_count_big'.tr(args: ['${_selected.length}', '${rows.length}', '${_bigSearch.total}']) +
              (_bigSearch.loadingMore ? ' · ${'sp.loading_more'.tr()}' : '')
          : 'sp.selection_count'.tr(args: ['${_selected.length}', '${rows.length}']),
      loading: _loading,
      empty: _emptyState(),
      onNearEnd: _big ? _bigMore : null,
      panel: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_canManage)
            DeskPanelCard(
              title: 'sp.apply'.tr(),
              icon: LucideIcons.banknote,
              accent: accent,
              children: [
                _amountField(),
                const SizedBox(height: Sp.sm),
                Text('sp.hero_hint'.tr(), style: AppType.muted(color: AppColors.textMid).copyWith(fontSize: 12.5)),
                const SizedBox(height: Sp.md),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        _selected.isEmpty
                            ? 'sp.pick_from_table'.tr()
                            : 'sp.selected_n'.tr(args: ['${_selected.length}']),
                        style: AppType.body(color: _selected.isEmpty ? AppColors.textMid : AppColors.textHi)
                            .copyWith(fontSize: 13.5, fontWeight: FontWeight.w600),
                      ),
                    ),
                    if (_selected.isNotEmpty)
                      TextButton(onPressed: () => setState(_selected.clear), child: Text('sp.clear'.tr())),
                  ],
                ),
                const SizedBox(height: Sp.sm),
                DeskWideButton(
                  label: _submitting
                      ? 'sp.applying'.tr()
                      : (_amount > 0 && _selected.isNotEmpty
                          ? 'sp.apply_n'.tr(args: [formatIQD(_amount), '${_selected.length}'])
                          : 'sp.apply'.tr()),
                  icon: LucideIcons.banknote,
                  color: accent,
                  busy: _submitting,
                  onPressed: _amount > 0 && _selected.isNotEmpty ? _apply : null,
                ),
                const SizedBox(height: Sp.sm),
                DeskWideButton(
                  label: 'sp.remove_price'.tr(),
                  icon: LucideIcons.trash2,
                  color: AppColors.error,
                  outlined: true,
                  onPressed: _selectedWithPrice == 0 || _submitting ? null : _removeSelected,
                ),
              ],
            ),
          DeskPanelCard(
            title: 'sp.current_prices'.tr(),
            icon: LucideIcons.list,
            accent: accent,
            children: [
              DeskStat(
                value: '${_prices.length}',
                label: _loadFailed ? 'sp.load_failed'.tr() : 'sp.fixed_count_label'.tr(),
              ),
              const SizedBox(height: Sp.md),
              DeskWideButton(
                label: 'sp.current_prices'.tr(),
                icon: LucideIcons.list,
                color: accent,
                outlined: true,
                onPressed: _prices.isEmpty ? null : _openExisting,
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// حقلٌ مدمج كحقل شاشة الخصومات. (كان `AmountTextField` — حقل الشيتات
  /// بخطّه الكبير — فظهر التلميح ضخماً في رأس الشاشة.)
  Widget _amountField() {
    return AmountShorthandBox(
      controller: _amountCtrl,
      child: TextField(
        controller: _amountCtrl,
        keyboardType: TextInputType.number,
        style: AppType.input(color: AppColors.textHi),
        decoration: InputDecoration(
          hintText: 'sp.amount_hint'.tr(),
          hintStyle: AppType.input(color: AppColors.textLow),
          filled: true,
          fillColor: AppColors.surface,
          prefixIcon: Icon(LucideIcons.banknote, size: 16, color: AppColors.textMid),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(R.sm),
            borderSide: BorderSide(color: AppColors.borderSoft),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(R.sm),
            borderSide: BorderSide(color: AppColors.borderSoft),
          ),
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          suffixText: 'common.currency'.tr(),
        ),
      ),
    );
  }

  Widget _selectionBar(Color accent, int filteredCount) {
    return Row(
      children: [
        if (_canManage) ...[
          _miniBtn(
            icon: LucideIcons.listChecks,
            label: 'sp.select_visible'.tr(),
            onTap: filteredCount > 0
                ? () => setState(() {
                      for (final s in _filtered) {
                        _selected.add(s.idx!);
                      }
                    })
                : null,
            color: accent,
          ),
          const SizedBox(width: 6),
          _miniBtn(
            icon: LucideIcons.eraser,
            label: 'sp.clear'.tr(),
            onTap: _selected.isEmpty ? null : () => setState(_selected.clear),
            color: AppColors.textMid,
          ),
        ],
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            // الكبير: المعروض من مجموع الساس (لا «١٠٠ نتيجة» كأنّها كلّ المشتركين)، والباقي بالتمرير أو البحث
            _big && _bigSearch.total > filteredCount
                ? 'sp.selection_count_big'.tr(args: ['${_selected.length}', '$filteredCount', '${_bigSearch.total}']) +
                    (_bigSearch.loadingMore ? ' · ${'sp.loading_more'.tr()}' : '')
                : 'sp.selection_count'
                    .tr(args: ['${_selected.length}', '$filteredCount']),
            style: AppType.muted().copyWith(fontSize: 11),
            textAlign: TextAlign.end,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _miniBtn({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
    required Color color,
  }) {
    final disabled = onTap == null;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(R.sm),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            color: disabled ? AppColors.surfaceInput : color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(R.sm),
            border: Border.all(
                color: disabled ? AppColors.border : color.withValues(alpha: 0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 11, color: disabled ? AppColors.textLow : color),
              const SizedBox(width: 4),
              Text(
                label,
                style: AppType.microBold(color: disabled ? AppColors.textLow : color),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _emptyState() {
    return Padding(
      padding: const EdgeInsets.all(Sp.huge),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.users, size: 36, color: AppColors.textLow),
            const SizedBox(height: 10),
            Text(
              _query.isEmpty
                  ? 'sp.no_subscribers'.tr()
                  : 'sp.no_results'.tr(args: [_query]),
              style: AppType.muted().copyWith(fontSize: 12.5),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.label,
    required this.sub,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String sub;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final disabled = onTap == null;
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(R.md),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: Sp.sm, vertical: Sp.sm),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(R.md),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: disabled
                      ? AppColors.surfaceInput
                      : color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(R.sm),
                ),
                alignment: Alignment.center,
                child: Icon(icon,
                    color: disabled ? AppColors.textLow : color, size: 16),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: AppType.label(
                              color: disabled ? AppColors.textLow : AppColors.textHi)
                          .copyWith(fontWeight: FontWeight.w700, fontSize: 12.5),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      sub,
                      style: AppType.muted(color: AppColors.textMid)
                          .copyWith(fontSize: 10.5),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Icon(LucideIcons.chevronLeft,
                  size: 16, color: disabled ? AppColors.textLow : AppColors.textMid),
            ],
          ),
        ),
      ),
    );
  }
}

/// «الأسعار الحاليّة» — كلّ صفٍّ يفتح شيت التعديل/الحذف.
class _ExistingPricesSheet extends StatefulWidget {
  const _ExistingPricesSheet({required this.prices, required this.subsByIdx});
  final List<SubscriberPrice> prices;
  final Map<String, Subscriber> subsByIdx;

  @override
  State<_ExistingPricesSheet> createState() => _ExistingPricesSheetState();
}

class _ExistingPricesSheetState extends State<_ExistingPricesSheet> {
  bool _changed = false;
  late List<SubscriberPrice> _rows = List.of(widget.prices);

  Future<void> _edit(SubscriberPrice p) async {
    final sub = widget.subsByIdx[p.idx];
    final name = (sub?.fullName.trim().isNotEmpty ?? false) ? sub!.fullName : p.username;
    final changed = await showSubscriberPriceSheet(context, idx: p.idx, name: name);
    if (changed != true || !mounted) return;
    _changed = true;
    final fresh = await SubscriberPricesApi.list();
    if (!mounted || fresh == null) return;
    setState(() => _rows = fresh);
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_changed);
      },
      child: Container(
        constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.85),
        decoration: BoxDecoration(
          color: AppColors.surfaceSheet,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(R.sheet)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 42,
              height: H.grabber,
              decoration: BoxDecoration(
                color: AppColors.grabber,
                borderRadius: BorderRadius.circular(R.pill),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, Sp.sm),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'sp.current_prices'.tr(),
                      style: AppType.title(color: AppColors.textHi)
                          .copyWith(fontSize: 16),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: Icon(LucideIcons.x, size: 20, color: AppColors.textMid),
                    onPressed: () => Navigator.of(context).pop(_changed),
                  ),
                ],
              ),
            ),
            Flexible(
              child: _rows.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(Sp.huge),
                      child: Text('sp.none_yet'.tr(),
                          style: AppType.muted(), textAlign: TextAlign.center),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      padding: const EdgeInsets.fromLTRB(Sp.lg, 0, Sp.lg, Sp.xl),
                      itemCount: _rows.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 6),
                      itemBuilder: (_, i) => _row(_rows[i]),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(SubscriberPrice p) {
    final sub = widget.subsByIdx[p.idx];
    final name = (sub?.fullName.trim().isNotEmpty ?? false) ? sub!.fullName : p.username;
    // الباقة تغيّرت منذ التسعير — الطبيعيّ ساري، والتنبيه اختياريّ.
    final moved = sub?.profileId != null &&
        p.profileId != null &&
        sub!.profileId.toString() != p.profileId.toString();
    final normal = p.normalPrice;
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(R.md),
      child: InkWell(
        onTap: () => _edit(p),
        borderRadius: BorderRadius.circular(R.md),
        child: Container(
          padding: const EdgeInsets.all(Sp.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(R.md),
            border: Border.all(
                color: moved ? AppColors.warningSoftBorder : AppColors.border),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        style: AppType.bodyStrong(color: AppColors.textHi),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Text(
                      moved
                          ? 'sp.needs_repricing'.tr()
                          : [p.username, if ((p.profileName ?? '').isNotEmpty) p.profileName!]
                              .join(' · '),
                      style: AppType.muted(
                              color: moved ? AppColors.warning : AppColors.textMid)
                          .copyWith(fontSize: 11),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: Sp.sm),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('${formatIQD(p.price)} ${'common.currency'.tr()}',
                      style: AppType.bodyStrong(color: AppColors.brandAccent)),
                  if (normal != null && normal != p.price)
                    Text(
                      formatIQD(normal),
                      style: AppType.muted(color: AppColors.textLow).copyWith(
                        fontSize: 10.5,
                        decoration: TextDecoration.lineThrough,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
