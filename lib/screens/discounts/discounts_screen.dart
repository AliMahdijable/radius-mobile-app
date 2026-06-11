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
        iconTheme: IconThemeData(color: AppColors.textHi),
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
          Icon(LucideIcons.search,
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
          Icon(LucideIcons.percent,
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

/// مطلب 2026-06-12 (تحديث): التايل مطابق v1 (discounts_screen.dart:825+).
///   • Header: user-icon + username + packageName + edit/delete أزرار
///   • Price breakdown: 3 أعمدة (السعر الأصلي | الخصم | بعد الخصم)
///     بـdividers بين الأعمدة + خلفية teal فاتحة.
///   • Footer: clock icon + created_at مُنسّق.
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header row
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color:
                          const Color(0xFF14B8A6).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(R.md),
                    ),
                    alignment: Alignment.center,
                    child: const Icon(LucideIcons.user,
                        size: 16, color: Color(0xFF14B8A6)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          discount.subscriberUsername,
                          style: AppType.title(color: AppColors.textHi)
                              .copyWith(fontSize: 13),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if ((discount.packageName ?? '').isNotEmpty)
                          Text(
                            discount.packageName!,
                            style: AppType.muted().copyWith(
                                fontSize: 11, fontWeight: FontWeight.w600),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                  InkResponse(
                    onTap: onDelete,
                    radius: 18,
                    child: Container(
                      width: 30,
                      height: 30,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppColors.error.withValues(alpha: 0.08),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(LucideIcons.trash2,
                          size: 13, color: AppColors.error),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Price breakdown — 3 cols
              _priceBreakdown(),
              if ((discount.createdAt ?? '').isNotEmpty) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(LucideIcons.clock,
                        size: 10, color: AppColors.textLow),
                    const SizedBox(width: 4),
                    Text(
                      _humanDate(discount.createdAt!),
                      style: AppType.muted().copyWith(fontSize: 10.5),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _priceBreakdown() {
    final original = discount.packagePrice;
    final effective = discount.effectivePrice;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF14B8A6).withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(R.sm),
        border: Border.all(
            color: const Color(0xFF14B8A6).withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          _priceCol(
            'السعر الأصلي',
            original != null ? '${formatIQD(original)} د.ع' : '—',
            AppColors.textHi,
          ),
          _divider(),
          _priceCol(
            'الخصم',
            '${formatIQD(discount.discountAmount)} د.ع',
            AppColors.error,
          ),
          _divider(),
          _priceCol(
            'بعد الخصم',
            effective != null ? '${formatIQD(effective)} د.ع' : '—',
            AppColors.brand,
          ),
        ],
      ),
    );
  }

  Widget _priceCol(String label, String value, Color valueColor) {
    return Expanded(
      child: Column(
        children: [
          Text(label,
              style: AppType.muted().copyWith(fontSize: 9.5)),
          const SizedBox(height: 2),
          Text(value,
              style: AppType.label(color: valueColor).copyWith(
                  fontSize: 11.5, fontWeight: FontWeight.w800),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }

  Widget _divider() => Container(
        width: 1,
        height: 26,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        color: const Color(0xFF14B8A6).withValues(alpha: 0.18),
      );

  static String _humanDate(String iso) {
    final dt = DateTime.tryParse(iso);
    if (dt == null) return iso;
    String two(int n) => n.toString().padLeft(2, '0');
    return '${dt.year}/${two(dt.month)}/${two(dt.day)} ${two(dt.hour)}:${two(dt.minute)}';
  }
}
