import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../api/discounts_api.dart';
import '../../core/util/format.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import 'sheets/bulk_apply_sheet.dart';
import 'sheets/edit_discount_sheet.dart';

/// مديول الخصومات. شاشة قراءة + edit/delete. الـadd الفردي يحصل من
/// شاشة المشترك ('خصم سريع') — هذي شاشة الإدارة الشاملة لكل
/// الخصومات النشطة، مع total قيمتها.
class DiscountsScreen extends StatefulWidget {
  const DiscountsScreen({super.key});

  @override
  State<DiscountsScreen> createState() => _DiscountsScreenState();
}

class _DiscountsScreenState extends State<DiscountsScreen> {
  List<Discount> _rows = const [];
  bool _loading = true;
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
    _searchCtrl.addListener(() {
      final q = _searchCtrl.text.trim();
      if (q == _query) return;
      setState(() => _query = q);
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final rows = await DiscountsApi.list();
    if (!mounted) return;
    setState(() {
      _rows = rows;
      _loading = false;
    });
  }

  List<Discount> get _filtered {
    if (_query.isEmpty) return _rows;
    final q = _query.toLowerCase();
    return _rows.where((d) {
      return d.subscriberUsername.toLowerCase().contains(q) ||
          (d.packageName ?? '').toLowerCase().contains(q);
    }).toList();
  }

  num get _totalDiscount =>
      _rows.fold<num>(0, (acc, d) => acc + d.discountAmount);

  Future<void> _openEdit(Discount d) async {
    final changed = await showEditDiscountSheet(context, d);
    if (changed == true) _load();
  }

  Future<void> _confirmDelete(Discount d) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('حذف الخصم'),
        content: Text(
          'إزالة خصم ${formatIQD(d.discountAmount)} د.ع للمشترك '
          '${d.subscriberUsername}؟',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            style:
                FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final r = await DiscountsApi.delete(d.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(r.ok ? 'تم الحذف' : (r.message ?? 'تعذّر الحذف')),
        backgroundColor: r.ok ? AppColors.brand : AppColors.error,
        behavior: SnackBarBehavior.floating,
      ),
    );
    if (r.ok) _load();
  }

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFF14B8A6);
    final filtered = _filtered;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          'الخصومات',
          style: AppType.title(color: AppColors.textHi)
              .copyWith(fontSize: 16),
        ),
        iconTheme: const IconThemeData(color: AppColors.textHi),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: accent,
        foregroundColor: Colors.white,
        onPressed: () async {
          final r = await showBulkApplyDiscountSheet(context);
          if (r == true) _load();
        },
        icon: const Icon(LucideIcons.plus, size: 16),
        label: const Text('تطبيق دفعة'),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          color: accent,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
                Sp.lg, Sp.md, Sp.lg, Sp.huge),
            children: [
              _hero(accent),
              const SizedBox(height: Sp.md),
              _searchField(),
              const SizedBox(height: Sp.md),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (filtered.isEmpty)
                _empty()
              else
                Column(
                  children: [
                    for (final d in filtered) ...[
                      _DiscountTile(
                        discount: d,
                        onTap: () => _openEdit(d),
                        onDelete: () => _confirmDelete(d),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ],
                ),
            ],
          ),
        ),
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
                  '${_rows.length} خصم نشط',
                  style: AppType.title(color: AppColors.textHi)
                      .copyWith(fontSize: 18, letterSpacing: -0.4),
                ),
                Text(
                  'إجمالي الخصومات ${formatIQD(_totalDiscount)} د.ع',
                  style: AppType.muted().copyWith(fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _searchField() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.pill),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.symmetric(horizontal: Sp.md),
      child: Row(
        children: [
          const Icon(LucideIcons.search,
              color: AppColors.textMid, size: 18),
          const SizedBox(width: Sp.sm),
          Expanded(
            child: TextField(
              controller: _searchCtrl,
              style: AppType.input(color: AppColors.textHi),
              decoration: InputDecoration(
                hintText: 'ابحث باليوزر أو الباقة…',
                hintStyle: AppType.input(color: AppColors.textLow),
                border: InputBorder.none,
                isCollapsed: true,
                contentPadding:
                    const EdgeInsets.symmetric(vertical: Sp.md),
              ),
            ),
          ),
          if (_searchCtrl.text.isNotEmpty)
            IconButton(
              icon: const Icon(LucideIcons.x, size: 16),
              color: AppColors.textMid,
              visualDensity: VisualDensity.compact,
              onPressed: () {
                _searchCtrl.clear();
                setState(() => _query = '');
              },
            ),
        ],
      ),
    );
  }

  Widget _empty() {
    return Container(
      padding: const EdgeInsets.all(Sp.huge),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.lg),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          const Icon(LucideIcons.percent,
              size: 36, color: AppColors.textLow),
          const SizedBox(height: 10),
          Text(
            _query.isEmpty
                ? 'لا توجد خصومات نشطة'
                : 'لا توجد نتائج لـ "$_query"',
            style: AppType.muted(color: AppColors.textHi)
                .copyWith(fontSize: 13),
          ),
          const SizedBox(height: 4),
          Text(
            'تضاف الخصومات من شاشة كل مشترك',
            style: AppType.muted().copyWith(fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _DiscountTile extends StatelessWidget {
  const _DiscountTile({
    required this.discount,
    required this.onTap,
    required this.onDelete,
  });
  final Discount discount;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final effective = discount.effectivePrice;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(R.lg),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(R.lg),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: const Color(0xFF14B8A6).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(R.md),
                ),
                alignment: Alignment.center,
                child: const Icon(
                  LucideIcons.percent,
                  size: 16,
                  color: Color(0xFF14B8A6),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            discount.subscriberUsername,
                            style: AppType.label(color: AppColors.textHi)
                                .copyWith(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if ((discount.packageName ?? '').isNotEmpty) ...[
                          const SizedBox(width: 6),
                          Container(
                            width: 2,
                            height: 10,
                            color: AppColors.border,
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              discount.packageName!,
                              style: AppType.muted().copyWith(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(
                          'خصم ',
                          style: AppType.muted().copyWith(fontSize: 11),
                        ),
                        Text(
                          '${formatIQD(discount.discountAmount)} د.ع',
                          style: AppType.label(
                                  color: const Color(0xFF14B8A6))
                              .copyWith(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800),
                        ),
                        if (discount.packagePrice != null &&
                            effective != null) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.brand.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(R.sm),
                            ),
                            child: Text(
                              '${formatIQD(effective)} د.ع',
                              style: AppType.label(color: AppColors.brand)
                                  .copyWith(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              InkResponse(
                onTap: onDelete,
                radius: 22,
                child: Container(
                  width: 32,
                  height: 32,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.08),
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: AppColors.error.withValues(alpha: 0.3)),
                  ),
                  child: const Icon(
                    LucideIcons.trash2,
                    size: 14,
                    color: AppColors.error,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
