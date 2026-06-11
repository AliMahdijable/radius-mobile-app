import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../api/discounts_api.dart';
import '../../../core/util/format.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';
import 'edit_discount_sheet.dart';

/// عرض الخصومات الحالية فقط (المشتركون الذين لديهم خصم). الـscreen
/// الأساسية لقسم الخصومات صارت تطبيق + browse؛ هذه الـsheet تجاوب
/// على "عرضلي وين الخصومات الموجودة" — مع edit/delete لكل صف.
///
/// يرجّع `true` لو تم تعديل/حذف شيء (الـcaller يعيد التحميل).
Future<bool?> showExistingDiscountsSheet(BuildContext context) {
  return showModalBottomSheet<bool>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => const _ExistingDiscountsSheet(),
  );
}

class _ExistingDiscountsSheet extends StatefulWidget {
  const _ExistingDiscountsSheet();

  @override
  State<_ExistingDiscountsSheet> createState() =>
      _ExistingDiscountsSheetState();
}

class _ExistingDiscountsSheetState extends State<_ExistingDiscountsSheet> {
  List<Discount> _rows = const [];
  bool _loading = true;
  bool _changed = false;
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

  num get _total => _rows.fold<num>(0, (acc, d) => acc + d.discountAmount);

  Future<void> _openEdit(Discount d) async {
    final changed = await showEditDiscountSheet(context, d);
    if (changed == true) {
      _changed = true;
      _load();
    }
  }

  Future<void> _confirmDelete(Discount d) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('حذف الخصم',
            style: AppType.title(color: AppColors.textHi)
                .copyWith(fontSize: 16)),
        content: Text(
          'إزالة خصم ${formatIQD(d.discountAmount)} د.ع للمشترك '
          '${d.subscriberUsername}؟',
          style: AppType.subtitle(color: AppColors.textMid)
              .copyWith(height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
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
    if (r.ok) {
      _changed = true;
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    const accent = Color(0xFF14B8A6);
    final filtered = _filtered;
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        // ما نريد نرجّع true إلا لو تغيّر شي.
      },
      child: DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, controller) {
          return Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius:
                  BorderRadius.vertical(top: Radius.circular(R.xl)),
            ),
            child: Column(
              children: [
                const SizedBox(height: 8),
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Padding(
                  padding:
                      const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, 0),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(R.md),
                        ),
                        child: const Icon(LucideIcons.list,
                            size: 16, color: accent),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'الخصومات الحالية',
                              style: AppType.title(color: AppColors.textHi)
                                  .copyWith(fontSize: 15),
                            ),
                            Text(
                              '${_rows.length} خصم · إجمالي '
                              '${formatIQD(_total)} د.ع',
                              style: AppType.muted().copyWith(fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () =>
                            Navigator.of(context).pop(_changed),
                        icon: const Icon(LucideIcons.x, size: 16),
                        color: AppColors.textMid,
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                      Sp.lg, Sp.md, Sp.lg, Sp.sm),
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(R.pill),
                      border: Border.all(
                          color: AppColors.border.withValues(alpha: 0.5)),
                    ),
                    padding:
                        const EdgeInsets.symmetric(horizontal: Sp.md),
                    child: Row(
                      children: [
                        Icon(LucideIcons.search,
                            size: 16, color: AppColors.textMid),
                        const SizedBox(width: Sp.sm),
                        Expanded(
                          child: TextField(
                            controller: _searchCtrl,
                            style: AppType.input(color: AppColors.textHi),
                            decoration: InputDecoration(
                              hintText: 'بحث في الخصومات…',
                              hintStyle: AppType.input(
                                  color: AppColors.textLow),
                              border: InputBorder.none,
                              isCollapsed: true,
                              contentPadding:
                                  const EdgeInsets.symmetric(vertical: 10),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : filtered.isEmpty
                          ? Padding(
                              padding: const EdgeInsets.all(Sp.huge),
                              child: Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(LucideIcons.percent,
                                        size: 32, color: AppColors.textLow),
                                    const SizedBox(height: 10),
                                    Text(
                                      _query.isEmpty
                                          ? 'لا توجد خصومات مطبّقة بعد'
                                          : 'لا توجد نتائج لـ "$_query"',
                                      style: AppType.muted().copyWith(
                                          fontSize: 12),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          : ListView.separated(
                              controller: controller,
                              padding: const EdgeInsets.fromLTRB(
                                  Sp.lg, 0, Sp.lg, Sp.huge),
                              itemCount: filtered.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 8),
                              itemBuilder: (_, i) => _Tile(
                                discount: filtered[i],
                                onEdit: () => _openEdit(filtered[i]),
                                onDelete: () =>
                                    _confirmDelete(filtered[i]),
                              ),
                            ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.discount,
    required this.onEdit,
    required this.onDelete,
  });
  final Discount discount;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(R.md),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onEdit,
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: Sp.md, vertical: Sp.md),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(R.md),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFF14B8A6).withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(R.md),
                ),
                alignment: Alignment.center,
                child: const Icon(LucideIcons.percent,
                    color: Color(0xFF14B8A6), size: 16),
              ),
              const SizedBox(width: Sp.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      discount.subscriberUsername,
                      style: AppType.label(color: AppColors.textHi)
                          .copyWith(fontWeight: FontWeight.w800),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if ((discount.packageName ?? '').isNotEmpty)
                      Text(
                        discount.packageName!,
                        style: AppType.muted(color: AppColors.textMid)
                            .copyWith(fontSize: 11),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              Text(
                '-${formatIQD(discount.discountAmount)}',
                style: const TextStyle(
                  color: Color(0xFFE08F2D),
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 6),
              IconButton(
                icon: Icon(LucideIcons.trash2,
                    color: AppColors.error, size: 16),
                onPressed: onDelete,
                tooltip: 'حذف',
                splashRadius: 18,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(
                    minWidth: 32, minHeight: 32),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
