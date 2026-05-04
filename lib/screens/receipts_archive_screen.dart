import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' as intl;

import '../core/theme/app_theme.dart';
import '../core/utils/helpers.dart';
import '../core/utils/receipt_printer.dart';
import '../providers/print_templates_provider.dart';
import '../providers/receipt_archive_provider.dart';
import '../widgets/app_snackbar.dart';

/// أرشيف الوصولات. يعرض كل ما تم طباعته من تفعيل/تمديد/تسديد دين/إضافة دين
/// مع زر إعادة طباعة (يبني الوصل من snapshot المحفوظ).
class ReceiptsArchiveScreen extends ConsumerStatefulWidget {
  const ReceiptsArchiveScreen({super.key});

  @override
  ConsumerState<ReceiptsArchiveScreen> createState() =>
      _ReceiptsArchiveScreenState();
}

class _ReceiptsArchiveScreenState extends ConsumerState<ReceiptsArchiveScreen> {
  DateTime? _from;
  DateTime? _to;
  String _type = 'all';
  final _searchCtrl = TextEditingController();
  String _query = '';

  ArchiveListArgs get _args => ArchiveListArgs(
        from: _from,
        to: _to,
        type: _type == 'all' ? null : _type,
        query: _query.isEmpty ? null : _query,
        limit: 200,
      );

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Color _opColor(String op) {
    switch (op) {
      case 'activate': return AppTheme.successColor;
      case 'extend':   return AppTheme.warningColor;
      case 'pay_debt': return Colors.green.shade700;
      case 'add_debt': return Colors.red.shade700;
      default:         return AppTheme.primary;
    }
  }

  IconData _opIcon(String op) {
    switch (op) {
      case 'activate': return Icons.bolt_rounded;
      case 'extend':   return Icons.autorenew_rounded;
      case 'pay_debt': return Icons.payments_rounded;
      case 'add_debt': return Icons.add_card_rounded;
      default:         return Icons.receipt_long_rounded;
    }
  }

  String _opLabel(String op) {
    switch (op) {
      case 'activate': return 'تفعيل';
      case 'extend':   return 'تمديد';
      case 'pay_debt': return 'تسديد دين';
      case 'add_debt': return 'إضافة دين';
      default:         return op;
    }
  }

  String _methodLabel(String m) {
    switch (m) {
      case 'cash':    return 'نقدي';
      case 'partial': return 'جزئي';
      case 'credit':  return 'آجل';
      default:        return m;
    }
  }

  Future<void> _reprint(ArchivedReceipt row) async {
    // جلب الـpayload الكامل (الـlist endpoint ما يرجعه لتقليل الحجم)
    final full = await fetchArchivedReceipt(ref, row.id);
    final payload = full?.payload ?? row.payload ?? const {};
    final data = ReceiptData(
      subscriberName: (payload['subscriber_name'] as String?) ??
          row.subscriberName ?? '—',
      phoneNumber: (payload['phone_number'] as String?) ??
          row.subscriberPhone ?? '',
      packageName: (payload['package_name'] as String?) ?? row.packageName ?? '',
      packagePrice: (payload['package_price'] as num?)?.toDouble() ??
          row.packagePrice,
      paidAmount: (payload['paid_amount'] as num?)?.toDouble() ?? row.amount,
      remainingAmount:
          (payload['remaining_amount'] as num?)?.toDouble() ?? 0,
      debtAmount: (payload['debt_amount'] as num?)?.toDouble() ?? 0,
      expiryDate:
          (payload['expiry_date'] as String?) ?? row.expiryDate ?? '',
      operationType: (payload['operation_type'] as String?) ?? row.operationType,
    );
    try {
      // نستعمل نفس القالب النشط الحالي (لو القالب الأصلي انحذف).
      final ptState = ref.read(printTemplatesProvider);
      if (ptState.templates.isEmpty) {
        await ref.read(printTemplatesProvider.notifier).loadTemplates();
      }
      final activeTemplate = ref.read(printTemplatesProvider).activeTemplate;
      await ReceiptPrinter.printReceipt(
        data: data,
        htmlTemplate: activeTemplate?.content,
      );
    } catch (_) {
      if (mounted) AppSnackBar.error(context, 'فشل في إعادة الطباعة');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final asyncList = ref.watch(receiptsArchiveProvider(_args));

    return Scaffold(
      appBar: AppBar(
        title: const Text('أرشيف الوصولات',
            style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w700)),
        centerTitle: true,
      ),
      body: Column(
        children: [
          // search
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (v) => setState(() => _query = v.trim()),
              textDirection: TextDirection.ltr,
              decoration: InputDecoration(
                hintText: 'بحث (اسم/يوزر/تليفون)',
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                suffixIcon: _query.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() => _query = '');
                        },
                      )
                    : null,
              ),
            ),
          ),
          // type filter chips
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                _typeChip('الكل', 'all'),
                _typeChip('تفعيل', 'activate'),
                _typeChip('تمديد', 'extend'),
                _typeChip('تسديد دين', 'pay_debt'),
                _typeChip('إضافة دين', 'add_debt'),
              ],
            ),
          ),
          if (_from != null || _to != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Wrap(spacing: 6, children: [
                if (_from != null || _to != null)
                  Chip(
                    label: Text(
                      '${_from != null ? intl.DateFormat('y-MM-dd').format(_from!) : '...'} — ${_to != null ? intl.DateFormat('y-MM-dd').format(_to!) : '...'}',
                      style: const TextStyle(fontSize: 10),
                    ),
                    deleteIcon: const Icon(Icons.close, size: 14),
                    onDeleted: () => setState(() {
                      _from = null;
                      _to = null;
                    }),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
              ]),
            ),
          // date range button
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
            child: Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.date_range, size: 16),
                  label: Text(
                    _from == null && _to == null
                        ? 'اختر فترة زمنية'
                        : '${_from != null ? intl.DateFormat('y-MM-dd').format(_from!) : '...'} → ${_to != null ? intl.DateFormat('y-MM-dd').format(_to!) : '...'}',
                    style: const TextStyle(fontSize: 12),
                  ),
                  onPressed: _pickDateRange,
                ),
              ),
            ]),
          ),
          const Divider(height: 1),
          Expanded(
            child: asyncList.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text('خطأ في جلب الأرشيف: $e',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontFamily: 'Cairo')),
                ),
              ),
              data: (list) {
                if (list.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.receipt_long_outlined, size: 56,
                            color: theme.colorScheme.onSurface.withValues(alpha: .25)),
                        const SizedBox(height: 12),
                        Text('لا توجد وصولات',
                            style: TextStyle(
                                fontFamily: 'Cairo',
                                color: theme.colorScheme.onSurface
                                    .withValues(alpha: .5))),
                      ],
                    ),
                  );
                }
                return RefreshIndicator(
                  onRefresh: () async =>
                      ref.invalidate(receiptsArchiveProvider(_args)),
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                    itemCount: list.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 6),
                    itemBuilder: (_, i) => _ReceiptRow(
                      row: list[i],
                      color: _opColor(list[i].operationType),
                      icon: _opIcon(list[i].operationType),
                      label: _opLabel(list[i].operationType),
                      methodLabel: _methodLabel(list[i].paymentMethod),
                      onReprint: () => _reprint(list[i]),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _typeChip(String label, String value) {
    final selected = _type == value;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        label: Text(label, style: const TextStyle(fontSize: 11)),
        selected: selected,
        onSelected: (_) => setState(() => _type = value),
        visualDensity: VisualDensity.compact,
      ),
    );
  }

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(now.year + 1),
      initialDateRange: _from != null && _to != null
          ? DateTimeRange(start: _from!, end: _to!)
          : null,
    );
    if (picked != null) {
      setState(() {
        _from = DateTime(picked.start.year, picked.start.month, picked.start.day);
        _to = DateTime(picked.end.year, picked.end.month, picked.end.day, 23, 59, 59);
      });
    }
  }
}

class _ReceiptRow extends StatelessWidget {
  final ArchivedReceipt row;
  final Color color;
  final IconData icon;
  final String label;
  final String methodLabel;
  final VoidCallback onReprint;
  const _ReceiptRow({
    required this.row,
    required this.color,
    required this.icon,
    required this.label,
    required this.methodLabel,
    required this.onReprint,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final printedAtLocal = row.printedAt.toLocal();
    final timeStr = intl.DateFormat('y-MM-dd HH:mm').format(printedAtLocal);
    final subTitle = row.subscriberName?.trim().isNotEmpty == true
        ? row.subscriberName!.trim()
        : (row.subscriberUsername?.trim().isNotEmpty == true
            ? row.subscriberUsername!.trim()
            : '—');
    final subtitleSecondary = row.subscriberUsername?.trim().isNotEmpty == true &&
            row.subscriberUsername != row.subscriberName
        ? row.subscriberUsername
        : null;

    return Material(
      color: theme.cardTheme.color ?? Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onReprint,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 20, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Text(label,
                          style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800,
                              color: color)),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: .08),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(methodLabel,
                            style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w700,
                                color: color.withValues(alpha: .75))),
                      ),
                      const Spacer(),
                      Text(timeStr,
                          style: TextStyle(
                              fontSize: 10.5,
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: .55))),
                    ]),
                    const SizedBox(height: 4),
                    Text(subTitle,
                        style: const TextStyle(
                            fontSize: 13.5, fontWeight: FontWeight.w700),
                        overflow: TextOverflow.ellipsis),
                    if (subtitleSecondary != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 1),
                        child: Text(
                          subtitleSecondary!,
                          textDirection: TextDirection.ltr,
                          style: TextStyle(
                              fontSize: 11,
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: .5)),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    const SizedBox(height: 4),
                    Row(children: [
                      if (row.amount > 0)
                        Text(AppHelpers.formatMoney(row.amount),
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w800)),
                      if (row.packageName?.isNotEmpty == true) ...[
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(row.packageName!,
                              style: TextStyle(
                                  fontSize: 11,
                                  color: theme.colorScheme.onSurface
                                      .withValues(alpha: .55)),
                              overflow: TextOverflow.ellipsis),
                        ),
                      ],
                    ]),
                    if (row.printedByEmployeeUsername?.isNotEmpty == true)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text('بواسطة: ${row.printedByEmployeeUsername}',
                            style: TextStyle(
                                fontSize: 10.5,
                                color: theme.colorScheme.primary
                                    .withValues(alpha: .65))),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: Icon(Icons.print_rounded,
                    size: 20, color: theme.colorScheme.primary),
                onPressed: onReprint,
                tooltip: 'إعادة طباعة',
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
