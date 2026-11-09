import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../api/discounts_api.dart';
import '../../api/big_subscribers_api.dart';
import '../../api/subscribers_api.dart';
import '../../core/util/amount_input.dart';
import '../../core/util/format.dart';
import '../../models/subscriber.dart';
import '../../services/permissions_service.dart';
import '../../services/subscriber_events.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import 'sheets/existing_discounts_sheet.dart';
import '../desktop/desk_widgets.dart';
import '../../core/platform/desktop_layout.dart';
import '../desktop/desk_bulk_picker.dart';
import '../../widgets/merged_section.dart';
import '../../api/company_route.dart';
import '../../services/merged_mode.dart';
import '../../widgets/list_kit.dart';

/// شاشة الخصومات — مطلب 2026-06-11 (تصميم جديد):
///   • الـscreen الأساسية = browse + apply: قيمة الخصم + بحث + جميع
///     المشتركين كـcards/grid + multi-select + زر تطبيق ثابت أسفل.
///   • زر "📋 عرض الخصومات الحالية" بالأعلى يفتح bottom sheet
///     مخصّص للقائمة (existing_discounts_sheet) مع edit/delete.
///   • زر "🗑 حذف الكل" بالأعلى للحذف الجماعي.
/// المنطق نُقل من bulk_apply_sheet.dart (المرشّح للحذف بعد التحقّق).
class DiscountsScreen extends StatefulWidget {
  const DiscountsScreen({super.key});

  @override
  State<DiscountsScreen> createState() => _DiscountsScreenState();
}

class _DiscountsScreenState extends State<DiscountsScreen> {
  final _amountCtrl = TextEditingController();
  final _searchCtrl = TextEditingController();
  int _amount = 0;
  bool _suppressFormat = false;
  bool _submitting = false;

  bool _loading = true;
  List<Subscriber> _all = const [];

  /// خريطة username (lowercased) → قيمة الخصم. مبنية من
  /// DiscountsApi.list. مستخدمة لـ:
  ///   1. badge "-X" على كارت المشترك إذا عنده خصم سابق.
  ///   2. عداد الـhero (عدد + إجمالي).
  Map<String, num> _existing = const {};
  final Set<String> _selected = {};
  String _query = '';

  /// الحساب الكبير (≥ ٥٠٠٠): المشتركون من بحث الساس (١٠٠ لكلّ بحث) بدل القائمة الكاملة — والاختيار يبقى عبر البحوث.
  bool _big = false;
  final _bigSearch = BigSearch();
  Map<String, PackageInfo> _packages = const {};

  bool get _canManage => Perms.has('discounts.manage');

  /// «كل الشركات» (٨ نوفمبر): شركةٌ غير المفتوحة — للعرض وحده: خصوماتها كما هي (يوزر المشترك وخصمه واسمه من قائمتها هي).
  /// لا شبكة مشتركين للاختيار ولا تطبيق ولا حذف: كانت الشبكة قائمة المفتوحة ومعها خصومات الأخرى مطابقةً باليوزر — شركتان
  /// في صفٍّ واحد.
  bool get _viewOnly => CompanyRoute.sectionKeyFor('/api/discounts') != null;
  List<Discount> _viewRows = const [];
  Map<String, String> _viewNames = const {};

  @override
  void initState() {
    super.initState();
    _amountCtrl.addListener(_onAmount);
    _searchCtrl.addListener(() {
      final q = _searchCtrl.text.trim();
      if (q == _query) return;
      setState(() => _query = q);
      if (_big) _bigSearch.search(q, onRows: _setBigRows);
    });
    _load();
  }

  void _setBigRows(List<Subscriber> rows) {
    if (!mounted) return;
    setState(() => _all = rows.map((s) => s.enrichWithPackages(_packages)).toList());
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
      final seen = {for (final s in _all) s.username.toLowerCase()};
      _all = [
        ..._all,
        for (final s in rows)
          if (seen.add(s.username.toLowerCase())) s.enrichWithPackages(_packages),
      ];
    });
  }

  bool _onGridScroll(ScrollNotification n) {
    if (_big && n.metrics.extentAfter < 600) _bigMore();
    return false;
  }

  @override
  void dispose() {
    _bigSearch.dispose();
    _amountCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    if (_viewOnly) {
      final key = CompanyRoute.sectionKeyFor('/api/discounts');
      final company = MergedMode.companyOf(key);
      final r = await Future.wait([
        DiscountsApi.list(),
        company == null ? Future<MergedCompanyList?>.value(null) : MergedSubscribers.fetchCompany(company),
      ]);
      if (!mounted) return;
      final rows = (r[1] as MergedCompanyList?)?.rows ?? const <Subscriber>[];
      setState(() {
        _viewRows = r[0] as List<Discount>;
        _existing = {for (final d in _viewRows) d.subscriberUsername.toLowerCase(): d.discountAmount};
        _viewNames = {
          for (final s in rows)
            if (s.fullName.trim().isNotEmpty && s.fullName.trim() != s.username) s.username.toLowerCase(): s.fullName.trim(),
        };
        _loading = false;
      });
      return;
    }
    final results = await Future.wait([
      SubscribersApi.loadAll(),
      DiscountsApi.list(),
      // سعر الباقة لكلّ كارت — القائمة لا تحمله دائماً والكتالوج يملؤه
      // (كما تفعل شاشتا المشتركين والأسعار). به يُحسب «سعر البيع الحالي».
      SubscribersApi.loadPackages(),
    ]);
    if (!mounted) return;
    final subs = results[0] as List<Subscriber>?;
    final discounts = results[1] as List<Discount>;
    final packages = results[2] as Map<String, PackageInfo>? ?? const {};
    final map = <String, num>{};
    for (final d in discounts) {
      map[d.subscriberUsername.toLowerCase()] = d.discountAmount;
    }
    _big = subs == null && await BigSubscribersApi.probe() > 0;
    if (!mounted) return;
    setState(() {
      _packages = packages;
      _all = (subs ?? const <Subscriber>[])
          .map((s) => s.enrichWithPackages(packages))
          .toList();
      _existing = map;
      _loading = false;
    });
    if (_big) _bigSearch.search(_query, onRows: _setBigRows, now: true);
  }

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

  void _addQuickAmount(int v) {
    final next = _amount + v;
    final f = _fmt(next);
    _suppressFormat = true;
    _amountCtrl.value = TextEditingValue(
      text: f,
      selection: TextSelection.collapsed(offset: f.length),
    );
    _suppressFormat = false;
    setState(() => _amount = next);
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
    return _all.where((s) {
      return s.username.toLowerCase().contains(q) ||
          s.fullName.toLowerCase().contains(q) ||
          s.displayPhone.contains(q);
    }).toList();
  }

  num get _totalDiscount => _existing.values.fold<num>(0, (acc, v) => acc + v);

  void _toggle(String username) {
    setState(() {
      if (_selected.contains(username)) {
        _selected.remove(username);
      } else {
        _selected.add(username);
      }
    });
  }

  void _selectAllVisible() {
    setState(() {
      for (final s in _filtered) {
        _selected.add(s.username);
      }
    });
  }

  void _clearSelection() => setState(() => _selected.clear());

  Future<void> _submit() async {
    if (_submitting) return;
    if (_amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('أدخل قيمة الخصم'),
          backgroundColor: AppColors.warning,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    if (_selected.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('اختر مشتركاً واحداً على الأقل'),
          backgroundColor: AppColors.warning,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    setState(() => _submitting = true);
    final r = await DiscountsApi.bulkApply(
      usernames: _selected.toList(),
      discountAmount: _amount,
    );
    if (!mounted) return;
    setState(() => _submitting = false);
    final summary = r.ok
        ? 'جديد ${r.applied} · محدّث ${r.updated}'
            '${r.failed > 0 ? ' · فشل ${r.failed}' : ''}'
        : (r.message ?? 'فشل التطبيق');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(summary),
        backgroundColor: r.ok ? AppColors.brand : AppColors.error,
        behavior: SnackBarBehavior.floating,
      ),
    );
    if (r.ok) {
      _selected.clear();
      _amountCtrl.clear();
      _amount = 0;
      // الخصم غيّر سعر البيع للمشتركين — أسقِط كاش القائمة ونبّه الشاشات
      // (قائمة المشتركين · الأسعار · التفاصيل) فتعرض السعر الجديد، كما
      // يفعل شيت الخصم الفرديّ (quick_discount_sheet).
      SubscriberEvents.notifyChange();
      _load();
    }
  }

  Future<void> _openExistingDiscounts() async {
    final changed = await showExistingDiscountsSheet(context);
    // الشيت يرجّع true لو عُدِّل/حُذف خصمٌ فيه — بثٌّ واحدٌ عند الإغلاق
    // يجمع كلّ تعديلاته بدل بثٍّ لكلّ صفٍّ على حدة.
    if (changed == true) {
      SubscriberEvents.notifyChange();
      _load();
    }
  }

  Future<void> _confirmDeleteAll() async {
    if (_existing.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(
          'حذف جميع الخصومات',
          style: AppType.title(color: AppColors.textHi).copyWith(fontSize: 16),
        ),
        content: Text(
          'سيتم حذف ${_existing.length} خصم بإجمالي '
          '${formatIQD(_totalDiscount)} د.ع. لا يمكن التراجع.',
          style:
              AppType.subtitle(color: AppColors.textMid).copyWith(height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.errorFill),
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: const Text('حذف الكل'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final r = await DiscountsApi.deleteAll();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
            r.ok ? 'تم حذف ${r.deleted} خصم' : (r.message ?? 'تعذّر الحذف')),
        backgroundColor: r.ok ? AppColors.brand : AppColors.error,
        behavior: SnackBarBehavior.floating,
      ),
    );
    if (r.ok) {
      // حذف كلّ الخصومات يُعيد أسعار البيع لأصلها — نبّه الشاشات الأخرى.
      SubscriberEvents.notifyChange();
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final accent = AppColors.success;
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
            'الخصومات',
            style: AppType.title(color: AppColors.textHi).copyWith(fontSize: 16),
          ),
          iconTheme: IconThemeData(color: AppColors.textHi),
        ),
      ),
      body: MergedSectionBody(child: _viewOnly
          ? _viewOnlyBody(accent)
          : DesktopScope.of(context)
          ? _desktopBody(filtered, accent)
          : _phoneBody(filtered, accent)),
      // الهاتف (٩ نوفمبر — التصميم الجديد): شريط التحديد يظهر حين يُحدَّد أحد — العدد ومسحٌ و«خصم» يفتح ورقة المبلغ. لمن لا يملك
      // discounts.manage (يشاهد فقط) ولـ«كل الشركات» للعرض وللحاسبة: لا شريط.
      bottomNavigationBar: !_canManage || _viewOnly || DesktopScope.of(context) || _selected.isEmpty
          ? null
          : ListSelectionBar(
              count: _selected.length,
              onClear: _clearSelection,
              actions: [
                ListBarButton(
                  key: const ValueKey('discounts-apply'),
                  label: _submitting ? 'جاري التطبيق...' : 'خصم',
                  icon: LucideIcons.percent,
                  tone: ListTone.success,
                  busy: _submitting,
                  onPressed: _openApplySheet,
                ),
              ],
            ),
    );
  }

  /// ورقة المبلغ ثمّ التطبيق — المنطق نفسه (_submit) بالمبلغ المختار.
  Future<void> _openApplySheet() async {
    if (_selected.isEmpty || _submitting) return;
    final n = _selected.length;
    final picked = _all.where((s) => _selected.contains(s.username)).toList();
    final base = picked.isNotEmpty && picked.every((s) => s.packageSalePrice == picked.first.packageSalePrice)
        ? picked.first.packageSalePrice
        : null;
    final v = await showListAmountSheet(
      context,
      title: 'خصم على $n مشترك',
      subtitle: 'يُطرح من سعر باقة كلٍّ منهم عند كلّ تجديد',
      icon: LucideIcons.percent,
      fieldLabel: 'مبلغ الخصم',
      confirmLabel: 'تطبيق {amount} على $n',
      tone: ListTone.success,
      quickAdds: const [5000, 10000, 15000, 20000, 25000],
      previewOf: base == null || base <= 0 ? null : (a) => 'السعر بعد الخصم: ${formatIQD((base - a).clamp(0, base))} د.ع',
    );
    if (v == null || v <= 0 || !mounted) return;
    _amount = v;
    await _submit();
  }

  /// الهاتف (٩ نوفمبر — المالك: «القائمة الوحيده تصميمها بالهاتف مزعج ورديئ»): بطاقات أرقام، ثمّ «الخصومات الحاليّة» و«حذف الكلّ»،
  /// ثمّ البحث وشرائح «الكلّ · عليهم خصم · بلا خصم»، ثمّ صفٌّ لكلّ مشترك يُلمس للتحديد — بدل شبكة الكرتات الصغيرة.
  Widget _phoneBody(List<Subscriber> filtered, Color accent) {
    final rows = switch (_deskFilter) {
      1 => filtered.where((s) => (_existing[s.username.toLowerCase()] ?? 0) > 0).toList(),
      2 => filtered.where((s) => (_existing[s.username.toLowerCase()] ?? 0) <= 0).toList(),
      _ => filtered,
    };
    final discounted = _all.where((s) => (_existing[s.username.toLowerCase()] ?? 0) > 0).length;
    return RefreshIndicator(
      onRefresh: _load,
      color: accent,
      child: NotificationListener<ScrollNotification>(
        onNotification: _onGridScroll,
        child: CustomScrollView(
          key: const ValueKey('discounts-list'),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, Sp.sm),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  Row(children: [
                    Expanded(
                      child: ListKpiTile(
                        icon: LucideIcons.percent,
                        tone: ListTone.success,
                        label: 'عليهم خصم',
                        value: '${_existing.length}',
                        active: _deskFilter == 1,
                        onTap: () => setState(() => _deskFilter = _deskFilter == 1 ? 0 : 1),
                      ),
                    ),
                    const SizedBox(width: Sp.sm),
                    Expanded(
                      child: ListKpiTile(
                        icon: LucideIcons.wallet,
                        tone: ListTone.warning,
                        label: 'مجموع الخصومات',
                        value: _fmt(_totalDiscount.round()).isEmpty ? '0' : _fmt(_totalDiscount.round()),
                        unit: 'د.ع',
                      ),
                    ),
                  ]),
                  const SizedBox(height: Sp.sm),
                  Row(children: [
                    Expanded(
                      child: _ActionCard(
                        icon: LucideIcons.list,
                        label: 'الخصومات الحالية',
                        sub: '${_existing.length} مطبّق',
                        color: accent,
                        onTap: _openExistingDiscounts,
                      ),
                    ),
                    if (_canManage) ...[
                      const SizedBox(width: Sp.sm),
                      // زرٌّ مربّع بكلمته (لا نصف عرض): «الخصومات الحالية» تأخذ الباقي فلا تُقصّ على ٣٢٠–٣٦٠
                      SizedBox(
                        width: 84,
                        child: Material(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(R.lg),
                          child: InkWell(
                            key: const ValueKey('discounts-delete-all'),
                            onTap: _existing.isNotEmpty ? _confirmDeleteAll : null,
                            borderRadius: BorderRadius.circular(R.lg),
                            child: Container(
                              constraints: const BoxConstraints(minHeight: 60),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(R.lg),
                                border: Border.all(color: _existing.isNotEmpty ? AppColors.dangerSoftBorder : AppColors.border),
                              ),
                              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                                Icon(LucideIcons.trash2, size: 18, color: _existing.isNotEmpty ? AppColors.error : AppColors.textHint),
                                const SizedBox(height: 4),
                                Text('حذف الكل',
                                    maxLines: 1,
                                    style: AppType.labelBold(color: _existing.isNotEmpty ? AppColors.error : AppColors.textHint)),
                              ]),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ]),
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
                      ListSearchField(controller: _searchCtrl, hint: 'ابحث بالاسم أو اليوزر أو الهاتف'),
                      const SizedBox(height: Sp.sm),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(children: [
                          ListFilterChip(label: 'الكلّ', active: _deskFilter == 0, onTap: () => setState(() => _deskFilter = 0)),
                          const SizedBox(width: Sp.x6),
                          ListFilterChip(
                            label: 'عليهم خصم',
                            icon: LucideIcons.percent,
                            tone: ListTone.success,
                            count: discounted,
                            active: _deskFilter == 1,
                            onTap: () => setState(() => _deskFilter = 1),
                          ),
                          const SizedBox(width: Sp.x6),
                          ListFilterChip(label: 'بلا خصم', active: _deskFilter == 2, onTap: () => setState(() => _deskFilter = 2)),
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
                      final d = _existing[s.username.toLowerCase()];
                      final hasName = s.fullName.trim().isNotEmpty && s.fullName != s.username;
                      final sale = s.saleAfter(d ?? 0);
                      final sub = [if (hasName) s.username, if ((s.profileName ?? '').isNotEmpty) s.profileName!].join(' · ');
                      return ListSubscriberRow(
                        key: ValueKey('discount-row-${s.username}'),
                        title: hasName ? s.fullName : s.username,
                        subtitle: sub,
                        selectable: _canManage,
                        selected: _selected.contains(s.username),
                        onTap: _canManage ? () => _toggle(s.username) : null,
                        trailing: ListAmountCell(
                          amount: sale != null && sale > 0 ? _fmt(sale.round()) : '—',
                          // السالب ملاصقٌ لرقمه: معزولٌ LTR (LRI…PDI) داخل السطر العربيّ
                          badge: (d ?? 0) > 0 ? '\u2066−${_fmt(d!.round())}\u2069' : null,
                          badgeTone: ListTone.success,
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

  /// فلتر جدول الحاسبة: الكلّ · عليهم خصم · بلا خصم.
  int _deskFilter = 0;

  Widget _desktopBody(List<Subscriber> filtered, Color accent) {
    final rows = switch (_deskFilter) {
      1 => filtered.where((s) => (_existing[s.username.toLowerCase()] ?? 0) > 0).toList(),
      2 => filtered.where((s) => (_existing[s.username.toLowerCase()] ?? 0) <= 0).toList(),
      _ => filtered,
    };
    final allOn = rows.isNotEmpty && rows.every((s) => _selected.contains(s.username));
    final muted = AppType.muted(color: AppColors.textMid).copyWith(fontSize: 13);
    final money = AppType.label(color: AppColors.textBody).copyWith(fontSize: 13.5, fontWeight: FontWeight.w600);
    return DeskBulkPicker(
      searchController: _searchCtrl,
      searchHint: 'ابحث عن مشترك بالاسم أو اليوزر أو الهاتف…',
      filters: DeskSegmented<int>(
        values: const [0, 1, 2],
        labelOf: (v) => const ['الكلّ', 'عليهم خصم', 'بلا خصم'][v],
        current: _deskFilter,
        onChanged: (v) => setState(() => _deskFilter = v),
      ),
      columns: const [
        DeskPickColumn('المشترك', flex: 3),
        DeskPickColumn('الباقة', flex: 2),
        DeskPickColumn('سعر الباقة', width: 120, align: AlignmentDirectional.centerEnd),
        DeskPickColumn('الخصم', width: 110, align: AlignmentDirectional.center),
        DeskPickColumn('سعر البيع', width: 120, align: AlignmentDirectional.centerEnd),
      ],
      rowCount: rows.length,
      cellsOf: (i) {
        final s = rows[i];
        final d = _existing[s.username.toLowerCase()];
        final hasName = s.fullName.trim().isNotEmpty && s.fullName != s.username;
        final base = s.packageSalePrice;
        final sale = s.saleAfter(d ?? 0);
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
                Text(s.username, maxLines: 1, overflow: TextOverflow.ellipsis, textDirection: TextDirection.ltr, style: muted),
            ],
          ),
          Text(s.profileName ?? '—', maxLines: 1, overflow: TextOverflow.ellipsis, style: muted),
          Text(base == null ? '—' : formatIQD(base), style: money),
          d != null && d > 0
              ? Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: AppColors.warningSoftBg, borderRadius: BorderRadius.circular(R.sm)),
                  child: Text('-${formatIQD(d)}', style: AppType.label(color: AppColors.warningOnSoft).copyWith(fontSize: 12.5, fontWeight: FontWeight.w700)),
                )
              : Text('—', style: muted),
          Text(sale == null ? '—' : formatIQD(sale),
              style: money.copyWith(color: d != null && d > 0 ? AppColors.brandOnSoft : AppColors.textBody, fontWeight: FontWeight.w700)),
        ];
      },
      selectedOf: (i) => _selected.contains(rows[i].username),
      onToggle: _canManage ? (i) => _toggle(rows[i].username) : null,
      allSelected: allOn,
      onToggleAll: () => setState(() {
        if (allOn) {
          for (final s in rows) {
            _selected.remove(s.username);
          }
        } else {
          for (final s in rows) {
            _selected.add(s.username);
          }
        }
      }),
      footer: _big && _bigSearch.total > filtered.length
          ? '${_selected.length} محدد · ${rows.length} من ${_bigSearch.total}${_bigSearch.loadingMore ? ' · جارٍ تحميل المزيد…' : ''}'
          : '${_selected.length} محدد · ${rows.length} نتيجة',
      loading: _loading,
      empty: _emptyState(),
      onNearEnd: _big ? _bigMore : null,
      panel: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_canManage)
            DeskPanelCard(
              title: 'تطبيق خصم',
              icon: LucideIcons.percent,
              accent: accent,
              children: [
                _amountField(accent),
                const SizedBox(height: Sp.md),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _selected.isEmpty ? 'اختر مشتركين من الجدول' : '${_selected.length} مشترك محدّد',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppType.body(color: _selected.isEmpty ? AppColors.textMid : AppColors.textHi)
                            .copyWith(fontSize: 13.5, fontWeight: FontWeight.w600),
                      ),
                    ),
                    if (_selected.isNotEmpty)
                      TextButton(onPressed: _clearSelection, child: const Text('مسح التحديد')),
                  ],
                ),
                const SizedBox(height: Sp.sm),
                DeskWideButton(
                  label: _submitting
                      ? 'جاري التطبيق...'
                      : (_amount > 0 && _selected.isNotEmpty
                          ? 'تطبيق ${_fmt(_amount)} على ${_selected.length}'
                          : 'تطبيق الخصم'),
                  icon: LucideIcons.percent,
                  color: accent,
                  busy: _submitting,
                  onPressed: _amount > 0 && _selected.isNotEmpty ? _submit : null,
                ),
              ],
            ),
          DeskPanelCard(
            title: 'الخصومات المطبّقة',
            icon: LucideIcons.list,
            accent: accent,
            children: [
              Row(
                children: [
                  Expanded(child: DeskStat(value: '${_existing.length}', label: 'مشترك عليه خصم')),
                  Expanded(child: DeskStat(value: formatIQD(_totalDiscount), label: 'إجمالي الخصومات (د.ع)')),
                ],
              ),
              const SizedBox(height: Sp.md),
              DeskWideButton(
                label: 'عرض الخصومات الحالية',
                icon: LucideIcons.list,
                color: accent,
                outlined: true,
                onPressed: _openExistingDiscounts,
              ),
              if (_canManage) ...[
                const SizedBox(height: Sp.sm),
                DeskWideButton(
                  label: 'حذف كلّ الخصومات',
                  icon: LucideIcons.trash2,
                  color: AppColors.error,
                  outlined: true,
                  onPressed: _existing.isNotEmpty ? _confirmDeleteAll : null,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  // ============================================================
  // Sub-widgets
  // ============================================================

  /// للعرض وحده: الملخّص ثمّ خصومات الشركة صفّاً صفّاً (الأكبر أوّلاً).
  Widget _viewOnlyBody(Color accent) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    final rows = [..._viewRows]..sort((a, b) => b.discountAmount.compareTo(a.discountAmount));
    return RefreshIndicator(
      onRefresh: _load,
      color: accent,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, Sp.huge),
        children: [
          _hero(accent),
          const SizedBox(height: Sp.md),
          if (rows.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: Sp.xl),
              child: Text('لا خصومات مطبّقة', textAlign: TextAlign.center, style: AppType.label(color: AppColors.textMid)),
            )
          else
            for (final d in rows)
              Container(
                key: ValueKey('discount-view-${d.id}'),
                margin: const EdgeInsets.only(bottom: Sp.sm),
                padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(R.md),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(_viewNames[d.subscriberUsername.toLowerCase()] ?? d.subscriberUsername,
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.bodyBold(color: AppColors.textHi)),
                      const SizedBox(height: 2),
                      Text(
                        [d.subscriberUsername, if ((d.packageName ?? '').isNotEmpty) d.packageName!].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textDirection: TextDirection.ltr,
                        textAlign: TextAlign.end,
                        style: AppType.micro(color: AppColors.textMid),
                      ),
                    ]),
                  ),
                  const SizedBox(width: Sp.sm),
                  Text('−${_fmt(d.discountAmount.round())}', style: AppType.bodyBold(color: accent)),
                ]),
              ),
        ],
      ),
    );
  }

  Widget _hero(Color accent) {
    return Container(
      padding: const EdgeInsets.all(Sp.md),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            accent.withValues(alpha: 0.18),
            accent.withValues(alpha: 0.05),
          ],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: BorderRadius.circular(R.lg),
        border: Border.all(color: accent.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(R.md),
            ),
            child: Icon(LucideIcons.percent, color: accent, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_existing.length} خصم نشط',
                  style: AppType.title(color: AppColors.textHi)
                      .copyWith(fontSize: 17, letterSpacing: -0.3),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  'إجمالي ${formatIQD(_totalDiscount)} د.ع',
                  style: AppType.muted().copyWith(fontSize: 11),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _amountField(Color accent) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AmountShorthandBox(
            controller: _amountCtrl,
            child: TextField(
              controller: _amountCtrl,
              keyboardType: TextInputType.number,
              style: AppType.input(color: AppColors.textHi),
              decoration: InputDecoration(
                hintText: 'قيمة الخصم (مثلاً 5,000)',
                hintStyle: AppType.input(color: AppColors.textLow),
                filled: true,
                fillColor: AppColors.surface,
                prefixIcon: const Icon(LucideIcons.percent, size: 16),
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
                suffixText: 'د.ع',
              ),
            )),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final v in const [5000, 10000, 15000, 20000, 25000])
              _quickAmountChip(v, accent),
          ],
        ),
      ],
    );
  }

  Widget _quickAmountChip(int v, Color accent) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _addQuickAmount(v),
        borderRadius: BorderRadius.circular(R.sm),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(R.sm),
            border: Border.all(color: accent.withValues(alpha: 0.3)),
          ),
          child: Text(
            '+${_fmt(v)}',
            style: AppType.pillBold(color: accent),
          ),
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
            label: 'اختر المرئيين',
            onTap: filteredCount > 0 ? _selectAllVisible : null,
            color: accent,
          ),
          const SizedBox(width: 6),
          _miniBtn(
            icon: LucideIcons.eraser,
            label: 'مسح',
            onTap: _selected.isEmpty ? null : _clearSelection,
            color: AppColors.textMid,
          ),
        ],
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            // الكبير: المعروض من مجموع الساس (لا «١٠٠ نتيجة» كأنّها كلّ المشتركين)، والباقي بالتمرير أو البحث
            _big && _bigSearch.total > filteredCount
                ? '${_selected.length} محدد · $filteredCount من ${_bigSearch.total}${_bigSearch.loadingMore ? ' · جارٍ تحميل المزيد…' : ''}'
                : '${_selected.length} محدد · $filteredCount نتيجة',
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
            color: disabled
                ? AppColors.surfaceInput
                : color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(R.sm),
            border: Border.all(
              color: disabled ? AppColors.border : color.withValues(alpha: 0.3),
            ),
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
              _query.isEmpty ? 'لا يوجد مشتركون' : 'لا توجد نتائج لـ "$_query"',
              style: AppType.muted().copyWith(fontSize: 12.5),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

/// ============================================================
/// Action card (الـheader buttons)
/// ============================================================
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
    final fg = disabled ? AppColors.textLow : AppColors.textHi;
    final iconBg =
        disabled ? AppColors.surfaceInput : color.withValues(alpha: 0.14);
    final iconFg = disabled ? AppColors.textLow : color;
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(R.md),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: Sp.sm, vertical: Sp.sm),
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
                  color: iconBg,
                  borderRadius: BorderRadius.circular(R.sm),
                ),
                alignment: Alignment.center,
                child: Icon(icon, color: iconFg, size: 16),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: AppType.label(color: fg).copyWith(
                          fontWeight: FontWeight.w700, fontSize: 12.5),
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
                  size: 16,
                  color: disabled ? AppColors.textLow : AppColors.textMid),
            ],
          ),
        ),
      ),
    );
  }
}


