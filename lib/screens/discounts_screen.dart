import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/discounts_provider.dart';
import '../providers/subscribers_provider.dart';
import '../core/theme/app_theme.dart';
import '../core/utils/helpers.dart';
import '../widgets/app_snackbar.dart';
import '../models/discount_model.dart';

class DiscountsScreen extends ConsumerStatefulWidget {
  const DiscountsScreen({super.key});

  @override
  ConsumerState<DiscountsScreen> createState() => _DiscountsScreenState();
}

class _DiscountsScreenState extends ConsumerState<DiscountsScreen> {
  final _subscriberSearchController = TextEditingController();
  final _discountSearchController = TextEditingController();
  final _customAmountController = TextEditingController();

  final Set<String> _selectedSubscribers = {};
  double? _selectedAmount;
  bool _isCustomAmount = false;
  String _subscriberSearchQuery = '';
  String _discountSearchQuery = '';
  bool _isAdding = false;

  static const _presetAmounts = [5000.0, 10000.0, 15000.0, 20000.0, 25000.0];

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(discountsProvider.notifier).loadDiscounts();
      final subs = ref.read(subscribersProvider).subscribers;
      if (subs.isEmpty) {
        ref.read(subscribersProvider.notifier).loadSubscribers();
      }
    });
  }

  @override
  void dispose() {
    _subscriberSearchController.dispose();
    _discountSearchController.dispose();
    _customAmountController.dispose();
    super.dispose();
  }

  double? get _effectiveAmount {
    if (_isCustomAmount) {
      return double.tryParse(_customAmountController.text);
    }
    return _selectedAmount;
  }

  Future<void> _applyDiscounts() async {
    final amount = _effectiveAmount;
    if (amount == null || amount <= 0) {
      AppSnackBar.warning(context, 'الرجاء تحديد مبلغ الخصم');
      return;
    }
    if (_selectedSubscribers.isEmpty) {
      AppSnackBar.warning(context, 'الرجاء تحديد مشتركين');
      return;
    }

    setState(() => _isAdding = true);

    final subscribers = ref.read(subscribersProvider).subscribers;
    int successCount = 0;
    int failCount = 0;

    for (final username in _selectedSubscribers) {
      final sub = subscribers.firstWhere(
        (s) => s.username == username,
        orElse: () => subscribers.first,
      );
      if (sub.username != username) continue;

      final ok = await ref.read(discountsProvider.notifier).addDiscount(
            subscriberUsername: username,
            subscriberId: int.tryParse(sub.idx ?? '0') ?? 0,
            discountAmount: amount,
            packageName: sub.profileName,
            packagePrice: sub.price != null ? double.tryParse(sub.price!) : null,
          );

      if (ok) {
        successCount++;
      } else {
        failCount++;
      }
    }

    if (!mounted) return;
    setState(() {
      _isAdding = false;
      _selectedSubscribers.clear();
    });

    if (successCount > 0) {
      AppSnackBar.success(context, 'تم إضافة الخصم لـ $successCount مشترك');
    }
    if (failCount > 0) {
      AppSnackBar.error(context, 'فشل إضافة الخصم لـ $failCount مشترك');
    }
  }

  void _showEditDialog(DiscountModel discount) {
    final controller = TextEditingController(
      text: discount.discountAmount.toStringAsFixed(0),
    );

    showDialog(
      context: context,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return AlertDialog(
          title: const Text('تعديل الخصم', textAlign: TextAlign.center),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                discount.subscriberUsername,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppTheme.primary,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                keyboardType: TextInputType.number,
                textDirection: TextDirection.ltr,
                textAlign: TextAlign.left,
                decoration: const InputDecoration(
                  labelText: 'مبلغ الخصم',
                  suffixText: 'IQD',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () async {
                final newAmount = double.tryParse(controller.text);
                if (newAmount == null || newAmount <= 0) {
                  AppSnackBar.warning(context, 'الرجاء إدخال مبلغ صحيح');
                  return;
                }
                Navigator.pop(ctx);
                final ok = await ref
                    .read(discountsProvider.notifier)
                    .updateDiscount(discount.id, newAmount);
                if (!mounted) return;
                if (ok) {
                  AppSnackBar.success(context, 'تم تعديل الخصم');
                } else {
                  AppSnackBar.error(context, 'فشل تعديل الخصم');
                }
              },
              child: const Text('حفظ'),
            ),
          ],
        );
      },
    );
  }

  void _confirmDeleteAll() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تأكيد الحذف', textAlign: TextAlign.center),
        content: const Text(
          'هل أنت متأكد من حذف جميع الخصومات؟\nلا يمكن التراجع عن هذا الإجراء.',
          textAlign: TextAlign.center,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.dangerColor,
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              await ref.read(discountsProvider.notifier).deleteAll();
              if (!mounted) return;
              AppSnackBar.success(context, 'تم حذف جميع الخصومات');
            },
            child: const Text('حذف الكل'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final discountsState = ref.watch(discountsProvider);
    final subscribersState = ref.watch(subscribersProvider);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('إدارة الخصومات'),
        actions: [
          IconButton(
            onPressed: () {
              ref.read(discountsProvider.notifier).loadDiscounts();
            },
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'تحديث',
          ),
        ],
      ),
      body: discountsState.isLoading && discountsState.discounts.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () => ref.read(discountsProvider.notifier).loadDiscounts(),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildAddSection(theme, isDark, subscribersState),
                  const SizedBox(height: 24),
                  _buildCurrentDiscountsSection(theme, isDark, discountsState),
                ],
              ),
            ),
    );
  }

  Widget _buildAddSection(ThemeData theme, bool isDark, SubscribersState subsState) {
    final cardColor = isDark ? const Color(0xFF1A1A1A) : Colors.white;

    return Container(
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.06),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.teal50,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.add_circle_outline_rounded,
                    color: AppTheme.primary, size: 22),
              ),
              const SizedBox(width: 10),
              Text(
                'إضافة خصم',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          Text(
            'مبلغ الخصم',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ..._presetAmounts.map((amount) => _AmountChip(
                    amount: amount,
                    isSelected: !_isCustomAmount && _selectedAmount == amount,
                    onTap: () => setState(() {
                      _isCustomAmount = false;
                      _selectedAmount = amount;
                    }),
                  )),
              ChoiceChip(
                label: const Text('مخصص'),
                selected: _isCustomAmount,
                selectedColor: AppTheme.light,
                labelStyle: TextStyle(
                  fontFamily: 'Cairo',
                  fontWeight: FontWeight.w600,
                  color: _isCustomAmount ? AppTheme.primary : null,
                ),
                onSelected: (_) => setState(() {
                  _isCustomAmount = true;
                  _selectedAmount = null;
                }),
              ),
            ],
          ),

          if (_isCustomAmount) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _customAmountController,
              keyboardType: TextInputType.number,
              textDirection: TextDirection.ltr,
              textAlign: TextAlign.left,
              decoration: const InputDecoration(
                labelText: 'مبلغ مخصص',
                suffixText: 'IQD',
                prefixIcon: Icon(Icons.edit_rounded),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ],

          const SizedBox(height: 20),
          TextField(
            controller: _subscriberSearchController,
            textDirection: TextDirection.ltr,
            textAlign: TextAlign.left,
            decoration: const InputDecoration(
              labelText: 'بحث عن مشترك...',
              prefixIcon: Icon(Icons.search_rounded),
            ),
            onChanged: (v) => setState(() => _subscriberSearchQuery = v.toLowerCase()),
          ),
          const SizedBox(height: 12),

          _buildSelectionControls(subsState),
          const SizedBox(height: 12),

          _buildSubscribersGrid(theme, isDark, subsState),

          if (_selectedSubscribers.isNotEmpty) ...[
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isAdding ? null : _applyDiscounts,
                icon: _isAdding
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.discount_rounded),
                label: Text(
                  'إضافة الخصم (${_selectedSubscribers.length})',
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSelectionControls(SubscribersState subsState) {
    final filteredSubs = _filterSubscribers(subsState);

    return Row(
      children: [
        Text(
          '${_selectedSubscribers.length} محدد',
          style: const TextStyle(
            fontFamily: 'Cairo',
            color: AppTheme.primary,
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
        const Spacer(),
        TextButton.icon(
          onPressed: () {
            setState(() {
              _selectedSubscribers.addAll(
                filteredSubs.map((s) => s.username),
              );
            });
          },
          icon: const Icon(Icons.select_all_rounded, size: 18),
          label: const Text('تحديد الكل'),
          style: TextButton.styleFrom(
            foregroundColor: AppTheme.primary,
            textStyle: const TextStyle(fontFamily: 'Cairo', fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(width: 4),
        TextButton.icon(
          onPressed: () => setState(() => _selectedSubscribers.clear()),
          icon: const Icon(Icons.deselect_rounded, size: 18),
          label: const Text('إلغاء التحديد'),
          style: TextButton.styleFrom(
            foregroundColor: Colors.grey,
            textStyle: const TextStyle(fontFamily: 'Cairo', fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }

  List<dynamic> _filterSubscribers(SubscribersState subsState) {
    if (_subscriberSearchQuery.isEmpty) return subsState.subscribers;
    return subsState.subscribers.where((s) {
      return s.username.toLowerCase().contains(_subscriberSearchQuery) ||
          s.fullName.toLowerCase().contains(_subscriberSearchQuery) ||
          (s.profileName ?? '').toLowerCase().contains(_subscriberSearchQuery);
    }).toList();
  }

  Widget _buildSubscribersGrid(ThemeData theme, bool isDark, SubscribersState subsState) {
    final filtered = _filterSubscribers(subsState);
    final discountsState = ref.read(discountsProvider);
    final existingUsernames = discountsState.discounts
        .map((d) => d.subscriberUsername)
        .toSet();

    if (subsState.isLoading) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (filtered.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Text(
            _subscriberSearchQuery.isEmpty ? 'لا يوجد مشتركين' : 'لا توجد نتائج',
            style: TextStyle(color: Colors.grey.shade500),
          ),
        ),
      );
    }

    const maxVisible = 50;
    final visibleSubs = filtered.length > maxVisible
        ? filtered.sublist(0, maxVisible)
        : filtered;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (filtered.length > maxVisible)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'عرض أول $maxVisible من ${filtered.length} — استخدم البحث للتصفية',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
            ),
          ),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 1.6,
          ),
          itemCount: visibleSubs.length,
          itemBuilder: (ctx, i) {
            final sub = visibleSubs[i];
            final isSelected = _selectedSubscribers.contains(sub.username);
            final hasExisting = existingUsernames.contains(sub.username);

            return _SubscriberSelectCard(
              username: sub.username,
              fullName: sub.fullName,
              packageName: sub.profileName,
              hasExistingDiscount: hasExisting,
              isSelected: isSelected,
              isDark: isDark,
              onTap: () {
                setState(() {
                  if (isSelected) {
                    _selectedSubscribers.remove(sub.username);
                  } else {
                    _selectedSubscribers.add(sub.username);
                  }
                });
              },
            );
          },
        ),
      ],
    );
  }

  Widget _buildCurrentDiscountsSection(
      ThemeData theme, bool isDark, DiscountsState discountsState) {
    final cardColor = isDark ? const Color(0xFF1A1A1A) : Colors.white;
    final allDiscounts = discountsState.discounts;

    final filteredDiscounts = _discountSearchQuery.isEmpty
        ? allDiscounts
        : allDiscounts.where((d) {
            return d.subscriberUsername
                    .toLowerCase()
                    .contains(_discountSearchQuery) ||
                (d.packageName ?? '')
                    .toLowerCase()
                    .contains(_discountSearchQuery);
          }).toList();

    return Container(
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.06),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.teal50,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.discount_rounded,
                    color: AppTheme.primary, size: 22),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'الخصومات الحالية (${allDiscounts.length})',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (allDiscounts.isNotEmpty)
                TextButton.icon(
                  onPressed: _confirmDeleteAll,
                  icon: const Icon(Icons.delete_sweep_rounded, size: 18),
                  label: const Text('إزالة الكل'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppTheme.dangerColor,
                    textStyle:
                        const TextStyle(fontFamily: 'Cairo', fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),

          if (allDiscounts.isNotEmpty) ...[
            TextField(
              controller: _discountSearchController,
              textDirection: TextDirection.ltr,
              textAlign: TextAlign.left,
              decoration: const InputDecoration(
                labelText: 'بحث في الخصومات...',
                prefixIcon: Icon(Icons.search_rounded),
              ),
              onChanged: (v) =>
                  setState(() => _discountSearchQuery = v.toLowerCase()),
            ),
            const SizedBox(height: 12),
          ],

          if (allDiscounts.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.discount_outlined,
                        size: 48, color: Colors.grey.shade400),
                    const SizedBox(height: 8),
                    Text(
                      'لا توجد خصومات حالية',
                      style: TextStyle(
                        color: Colors.grey.shade500,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else if (filteredDiscounts.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  'لا توجد نتائج',
                  style: TextStyle(color: Colors.grey.shade500),
                ),
              ),
            )
          else
            ...filteredDiscounts.map(
              (d) => _DiscountCard(
                discount: d,
                isDark: isDark,
                onEdit: () => _showEditDialog(d),
                onDelete: () async {
                  final ok = await ref
                      .read(discountsProvider.notifier)
                      .deleteDiscount(d.id);
                  if (!mounted) return;
                  if (ok) {
                    AppSnackBar.success(context, 'تم حذف الخصم');
                  } else {
                    AppSnackBar.error(context, 'فشل حذف الخصم');
                  }
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _AmountChip extends StatelessWidget {
  final double amount;
  final bool isSelected;
  final VoidCallback onTap;

  const _AmountChip({
    required this.amount,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(AppHelpers.formatMoney(amount)),
      selected: isSelected,
      selectedColor: AppTheme.light,
      labelStyle: TextStyle(
        fontFamily: 'Cairo',
        fontWeight: FontWeight.w600,
        fontSize: 13,
        color: isSelected ? AppTheme.primary : null,
      ),
      onSelected: (_) => onTap(),
    );
  }
}

class _SubscriberSelectCard extends StatelessWidget {
  final String username;
  final String fullName;
  final String? packageName;
  final bool hasExistingDiscount;
  final bool isSelected;
  final bool isDark;
  final VoidCallback onTap;

  const _SubscriberSelectCard({
    required this.username,
    required this.fullName,
    this.packageName,
    required this.hasExistingDiscount,
    required this.isSelected,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final borderColor = isSelected
        ? AppTheme.primary
        : (isDark ? Colors.grey.shade800 : Colors.grey.shade200);
    final bgColor = isSelected
        ? (isDark ? AppTheme.teal900.withValues(alpha: 0.3) : AppTheme.teal50)
        : (isDark ? const Color(0xFF252525) : const Color(0xFFF8FAFA));

    return Material(
      color: bgColor,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: borderColor, width: isSelected ? 2 : 1),
          ),
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      username,
                      style: const TextStyle(
                        fontFamily: 'Cairo',
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (isSelected)
                    const Icon(Icons.check_circle_rounded,
                        color: AppTheme.primary, size: 18),
                ],
              ),
              if (fullName.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  fullName,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              if (packageName != null && packageName!.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  packageName!,
                  style: TextStyle(
                    fontSize: 11,
                    color: AppTheme.teal600,
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              if (hasExistingDiscount) ...[
                const SizedBox(height: 4),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppTheme.warningColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'خصم موجود',
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 10,
                      color: AppTheme.warningColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _DiscountCard extends StatelessWidget {
  final DiscountModel discount;
  final bool isDark;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _DiscountCard({
    required this.discount,
    required this.isDark,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final discountedPrice = (discount.packagePrice ?? 0) - discount.discountAmount;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF252525) : const Color(0xFFF8FAFA),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
        ),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.person_rounded,
                    color: AppTheme.primary, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      discount.subscriberUsername,
                      style: const TextStyle(
                        fontFamily: 'Cairo',
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    if (discount.packageName != null &&
                        discount.packageName!.isNotEmpty)
                      Text(
                        discount.packageName!,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade500,
                        ),
                      ),
                  ],
                ),
              ),
              IconButton(
                onPressed: onEdit,
                icon: const Icon(Icons.edit_rounded, size: 20),
                color: AppTheme.infoColor,
                tooltip: 'تعديل',
                visualDensity: VisualDensity.compact,
              ),
              IconButton(
                onPressed: onDelete,
                icon: const Icon(Icons.delete_rounded, size: 20),
                color: AppTheme.dangerColor,
                tooltip: 'حذف',
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.black.withValues(alpha: 0.2)
                  : AppTheme.teal50.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                _PriceColumn(
                  label: 'السعر الأصلي',
                  value: discount.packagePrice != null
                      ? AppHelpers.formatMoney(discount.packagePrice)
                      : '—',
                ),
                Container(
                  width: 1,
                  height: 30,
                  color: isDark ? Colors.grey.shade700 : Colors.grey.shade300,
                ),
                _PriceColumn(
                  label: 'الخصم',
                  value: AppHelpers.formatMoney(discount.discountAmount),
                  valueColor: AppTheme.dangerColor,
                ),
                Container(
                  width: 1,
                  height: 30,
                  color: isDark ? Colors.grey.shade700 : Colors.grey.shade300,
                ),
                _PriceColumn(
                  label: 'بعد الخصم',
                  value: discount.packagePrice != null
                      ? AppHelpers.formatMoney(discountedPrice)
                      : '—',
                  valueColor: AppTheme.successColor,
                ),
              ],
            ),
          ),
          if (discount.createdAt != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.access_time_rounded,
                    size: 14, color: Colors.grey.shade400),
                const SizedBox(width: 4),
                Text(
                  AppHelpers.formatDate(discount.createdAt),
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade500,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _PriceColumn extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const _PriceColumn({
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: Colors.grey.shade500,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: valueColor,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
