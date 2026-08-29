import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../api/discounts_api.dart';
import '../../api/subscribers_api.dart';
import '../../core/util/format.dart';
import '../../models/subscriber.dart';
import '../../services/permissions_service.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import 'sheets/existing_discounts_sheet.dart';
import '../../core/util/amount_input.dart';

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

  @override
  void initState() {
    super.initState();
    _amountCtrl.addListener(_onAmount);
    _searchCtrl.addListener(() {
      final q = _searchCtrl.text.trim();
      if (q == _query) return;
      setState(() => _query = q);
    });
    _load();
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final results = await Future.wait([
      SubscribersApi.loadAll(),
      DiscountsApi.list(),
    ]);
    if (!mounted) return;
    final subs = results[0] as List<Subscriber>?;
    final discounts = results[1] as List<Discount>;
    final map = <String, num>{};
    for (final d in discounts) {
      map[d.subscriberUsername.toLowerCase()] = d.discountAmount;
    }
    setState(() {
      _all = subs ?? const [];
      _existing = map;
      _loading = false;
    });
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
    if (_query.isEmpty) return _all;
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
          content: Text('أدخل قيمة الخصم'),
          backgroundColor: AppColors.warning,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    if (_selected.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('اختر مشتركاً واحداً على الأقل'),
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
      _load();
    }
  }

  Future<void> _openExistingDiscounts() async {
    final changed = await showExistingDiscountsSheet(context);
    if (changed == true) _load();
  }

  Future<void> _confirmDeleteAll() async {
    if (_existing.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
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
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.errorFill),
            onPressed: () => Navigator.of(context).pop(true),
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
    if (r.ok) _load();
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final accent = AppColors.success;
    final filtered = _filtered;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          'الخصومات',
          style: AppType.title(color: AppColors.textHi).copyWith(fontSize: 16),
        ),
        iconTheme: IconThemeData(color: AppColors.textHi),
      ),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // ---------- HEADER (hero + actions + amount + search) ----------
            Padding(
              padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, Sp.sm),
              child: Column(
                children: [
                  _hero(accent),
                  const SizedBox(height: Sp.sm),
                  // مطلب 2026-06-11: زر "حذف الكل" يختفي إذا الموظف
                  // ما عنده discounts.manage. لو الاثنين ما متوفرة
                  // (نادر — discounts.view بس)، الـRow كله يختفي.
                  if (Perms.has('discounts.manage'))
                    Row(
                      children: [
                        Expanded(
                          child: _ActionCard(
                            icon: LucideIcons.list,
                            label: 'الخصومات الحالية',
                            sub: '${_existing.length} مطبّق',
                            color: accent,
                            onTap: _openExistingDiscounts,
                          ),
                        ),
                        const SizedBox(width: Sp.sm),
                        Expanded(
                          child: _ActionCard(
                            icon: LucideIcons.trash2,
                            label: 'حذف الكل',
                            sub: _existing.isNotEmpty
                                ? 'إزالة الجميع'
                                : 'لا يوجد',
                            color: AppColors.error,
                            onTap:
                                _existing.isNotEmpty ? _confirmDeleteAll : null,
                          ),
                        ),
                      ],
                    )
                  else
                    _ActionCard(
                      icon: LucideIcons.list,
                      label: 'الخصومات الحالية',
                      sub: '${_existing.length} مطبّق',
                      color: accent,
                      onTap: _openExistingDiscounts,
                    ),
                  const SizedBox(height: Sp.md),
                  _amountField(accent),
                  const SizedBox(height: Sp.sm),
                  _searchField(),
                  const SizedBox(height: 8),
                  _selectionBar(accent, filtered.length),
                ],
              ),
            ),
            // ---------- GRID ----------
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : filtered.isEmpty
                      ? _emptyState()
                      : RefreshIndicator(
                          onRefresh: _load,
                          color: accent,
                          child: GridView.builder(
                            padding:
                                const EdgeInsets.fromLTRB(Sp.lg, 0, Sp.lg, 90),
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                              // مطلب 2026-06-11: cards أصغر — 3
                              // أعمدة + childAspectRatio أعلى = خلايا
                              // قصيرة، أكثر مشتركاً مرئياً في الشاشة.
                              crossAxisCount: 3,
                              childAspectRatio: 1.7,
                              crossAxisSpacing: 6,
                              mainAxisSpacing: 6,
                            ),
                            itemCount: filtered.length,
                            itemBuilder: (_, i) {
                              final s = filtered[i];
                              return _SubscriberCard(
                                sub: s,
                                selected: _selected.contains(s.username),
                                accent: accent,
                                existingDiscount:
                                    _existing[s.username.toLowerCase()],
                                onTap: () => _toggle(s.username),
                              );
                            },
                          ),
                        ),
            ),
          ],
        ),
      ),
      // زر التطبيق ثابت أسفل الشاشة. يتفعّل لما يكون في amount + في
      // مشتركون مختارون. مطلب 2026-06-11: يختفي بالكامل لو الموظف
      // ما عنده discounts.manage (يقدر بس يشوف).
      bottomNavigationBar: !Perms.has('discounts.manage')
          ? null
          : SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(Sp.lg, 0, Sp.lg, Sp.md),
                child: SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton.icon(
                    onPressed:
                        (_amount > 0 && _selected.isNotEmpty && !_submitting)
                            ? _submit
                            : null,
                    icon: _submitting
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(LucideIcons.percent, size: 16),
                    label: Text(
                      _submitting
                          ? 'جاري التطبيق...'
                          : (_amount > 0 && _selected.isNotEmpty
                              ? 'تطبيق ${_fmt(_amount)} على ${_selected.length}'
                              : 'تطبيق الخصم'),
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 14),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accent,
                      foregroundColor: AppColors.onBrand,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(R.md),
                      ),
                    ),
                  ),
                ),
              ),
            ),
    );
  }

  // ============================================================
  // Sub-widgets
  // ============================================================

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
                ),
                Text(
                  'إجمالي ${formatIQD(_totalDiscount)} د.ع',
                  style: AppType.muted().copyWith(fontSize: 11),
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
            style: TextStyle(
              color: accent,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }

  Widget _searchField() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.pill),
        border: Border.all(color: AppColors.borderSoft),
      ),
      padding: const EdgeInsets.symmetric(horizontal: Sp.md),
      child: Row(
        children: [
          Icon(LucideIcons.search, size: 16, color: AppColors.textMid),
          const SizedBox(width: Sp.sm),
          Expanded(
            child: TextField(
              controller: _searchCtrl,
              style: AppType.input(color: AppColors.textHi),
              decoration: InputDecoration(
                hintText: 'ابحث عن مشترك…',
                hintStyle: AppType.input(color: AppColors.textLow),
                border: InputBorder.none,
                isCollapsed: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _selectionBar(Color accent, int filteredCount) {
    return Row(
      children: [
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
          color: AppColors.error,
        ),
        const Spacer(),
        Text(
          '${_selected.length} محدد · $filteredCount نتيجة',
          style: AppType.muted().copyWith(fontSize: 11),
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
                style: TextStyle(
                  color: disabled ? AppColors.textLow : color,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                ),
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
              style: AppType.muted().copyWith(fontSize: 12),
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
                          fontWeight: FontWeight.w800, fontSize: 12.5),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      sub,
                      style: AppType.muted(color: AppColors.textMid)
                          .copyWith(fontSize: 10),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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

/// ============================================================
/// Subscriber select card — مطابق v1 _SubscriberSelectCard.
/// ============================================================
class _SubscriberCard extends StatelessWidget {
  const _SubscriberCard({
    required this.sub,
    required this.selected,
    required this.accent,
    required this.existingDiscount,
    required this.onTap,
  });

  final Subscriber sub;
  final bool selected;
  final Color accent;
  final num? existingDiscount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final hasName =
        sub.fullName.trim().isNotEmpty && sub.fullName != sub.username;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(R.sm),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
          decoration: BoxDecoration(
            color:
                selected ? accent.withValues(alpha: 0.10) : AppColors.surface,
            borderRadius: BorderRadius.circular(R.sm),
            border: Border.all(
              color: selected ? accent : AppColors.borderSoft,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            mainAxisSize: MainAxisSize.max,
            children: [
              // الـheader: checkbox + اسم (عربي إن وُجد، وإلا username).
              Row(
                children: [
                  Icon(
                    selected ? LucideIcons.squareCheck : LucideIcons.square,
                    size: 11,
                    color: selected ? accent : AppColors.textLow,
                  ),
                  const SizedBox(width: 3),
                  Expanded(
                    child: Text(
                      hasName ? sub.fullName : sub.username,
                      style: AppType.label(color: AppColors.textHi).copyWith(
                          fontSize: 10.5, fontWeight: FontWeight.w800),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              // sub-line: username لو الـheader فيه الاسم العربي،
              // أو الباقة لو ما في اسم عربي.
              if (hasName)
                Text(
                  sub.username,
                  style: AppType.muted().copyWith(fontSize: 9),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              // الـfooter: الباقة + badge الخصم الموجود.
              Row(
                children: [
                  if ((sub.profileName ?? '').isNotEmpty)
                    Expanded(
                      child: Text(
                        sub.profileName!,
                        style: AppType.label(color: AppColors.success)
                            .copyWith(fontSize: 9, fontWeight: FontWeight.w700),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    )
                  else
                    const Spacer(),
                  if (existingDiscount != null && existingDiscount! > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: AppColors.warning.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(R.sm),
                      ),
                      child: Text(
                        '-${formatIQD(existingDiscount!)}',
                        style: TextStyle(
                          color: AppColors.warning,
                          fontSize: 8.5,
                          fontWeight: FontWeight.w800,
                        ),
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
