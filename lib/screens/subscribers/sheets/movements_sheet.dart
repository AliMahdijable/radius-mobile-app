import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../api/subscribers_api.dart';
import '../../../core/util/format.dart';
import '../../../models/subscriber.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';

/// Subscriber movements / account-statement sheet — direct port of
/// v1's _SubscriberMovementsSheetContent from
/// mobile-app/lib/screens/subscribers/subscriber_details_screen.dart.
///
/// Pulls the financial transaction history (activations / extensions
/// / debt-pay / balance-add / balance-deduct) through
/// /api/reports/account-statement for a 5-year window, groups by date
/// (اليوم / أمس / يyyy-mm-dd) and renders each row as an icon + type
/// badge + description + admin + time + signed amount.
///
/// Horizontally-scrollable filter chips at the top mirror v1: الكل /
/// تفعيل / تمديد / تسديد / إضافة دين. Refresh icon retries the same
/// fetch (no pagination — the window is wide enough by design).
Future<void> showMovementsSheet(BuildContext context, Subscriber sub) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _MovementsSheet(sub: sub),
  );
}

class _MovementsSheet extends StatefulWidget {
  const _MovementsSheet({required this.sub});
  final Subscriber sub;

  @override
  State<_MovementsSheet> createState() => _MovementsSheetState();
}

class _MovementsSheetState extends State<_MovementsSheet> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _all = const [];
  String _typeFilter = 'all';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final txs = await SubscribersApi.loadMovements(
      username: widget.sub.username,
      idx: widget.sub.idx,
    );
    if (!mounted) return;
    setState(() {
      if (txs == null) {
        _error = 'تعذّر جلب الحركات — تحقّق من الاتصال';
      } else {
        _all = txs;
      }
      _loading = false;
    });
  }

  List<Map<String, dynamic>> get _filtered {
    if (_typeFilter == 'all') return _all;
    return _all
        .where((t) =>
            (t['action_type'] ?? '').toString().toUpperCase() ==
            _typeFilter)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, controller) {
        return Container(
          decoration: const BoxDecoration(
            color: AppColors.surface,
            borderRadius:
                BorderRadius.vertical(top: Radius.circular(R.xl)),
          ),
          child: Column(
            children: [
              _SheetHandle(),
              _Header(
                sub: widget.sub,
                loading: _loading,
                onRefresh: _loading ? null : _load,
                onClose: () => Navigator.of(context).pop(),
              ),
              _FilterChips(
                current: _typeFilter,
                onChange: (v) => setState(() => _typeFilter = v),
              ),
              const Divider(height: 1, color: AppColors.border),
              Expanded(child: _buildBody(controller)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBody(ScrollController controller) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.brand),
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(Sp.lg),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(LucideIcons.circleAlert,
                  size: 36, color: AppColors.error),
              const SizedBox(height: Sp.sm),
              Text(
                _error!,
                style: AppType.subtitle(color: AppColors.error),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: Sp.md),
              OutlinedButton.icon(
                onPressed: _load,
                icon: const Icon(LucideIcons.refreshCw, size: 14),
                label: const Text('إعادة المحاولة'),
              ),
            ],
          ),
        ),
      );
    }
    final list = _filtered;
    if (list.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(Sp.lg),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(LucideIcons.inbox,
                  size: 40, color: AppColors.textLow),
              const SizedBox(height: Sp.sm),
              Text(
                _typeFilter == 'all'
                    ? 'لا توجد حركات لعرضها'
                    : 'لا توجد حركات بهذا النوع',
                style: AppType.subtitle(color: AppColors.textMid),
              ),
            ],
          ),
        ),
      );
    }

    // Group by date label. Server returns DESC so we preserve insertion
    // order while building the group map.
    final grouped = <String, List<Map<String, dynamic>>>{};
    final order = <String>[];
    for (final t in list) {
      final key = _dateGroupKey(t['created_at']?.toString() ?? '');
      grouped.putIfAbsent(key, () {
        order.add(key);
        return [];
      }).add(t);
    }

    return ListView.builder(
      controller: controller,
      padding: const EdgeInsets.fromLTRB(Sp.md, Sp.sm, Sp.md, Sp.huge),
      itemCount: order.fold<int>(
          0, (sum, key) => sum + 1 + grouped[key]!.length),
      itemBuilder: (_, index) {
        var i = index;
        for (final key in order) {
          if (i == 0) return _DateHeader(label: key);
          i--;
          final group = grouped[key]!;
          if (i < group.length) return _MovementTile(txn: group[i]);
          i -= group.length;
        }
        return const SizedBox.shrink();
      },
    );
  }

  String _dateGroupKey(String iso) {
    final dt = DateTime.tryParse(iso);
    if (dt == null) return '—';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final d = DateTime(dt.year, dt.month, dt.day);
    final diff = today.difference(d).inDays;
    if (diff == 0) return 'اليوم';
    if (diff == 1) return 'أمس';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)}';
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.sub,
    required this.loading,
    required this.onRefresh,
    required this.onClose,
  });
  final Subscriber sub;
  final bool loading;
  final VoidCallback? onRefresh;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(Sp.lg, 4, Sp.sm, Sp.md),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: AppColors.brand.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(R.sm),
            ),
            child: const Icon(LucideIcons.history,
                color: AppColors.brand, size: 16),
          ),
          const SizedBox(width: Sp.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'سجل الحركات',
                  style: AppType.label(color: AppColors.textHi).copyWith(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  sub.fullName,
                  style: AppType.muted(color: AppColors.textMid).copyWith(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'تحديث',
            icon: loading
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.brand,
                    ),
                  )
                : const Icon(LucideIcons.refreshCw, size: 18),
            color: AppColors.textMid,
            visualDensity: VisualDensity.compact,
            onPressed: onRefresh,
          ),
          IconButton(
            icon: const Icon(LucideIcons.x, size: 20),
            color: AppColors.textMid,
            visualDensity: VisualDensity.compact,
            onPressed: onClose,
          ),
        ],
      ),
    );
  }
}

/// Horizontally-scrollable filter chips — 5 entries match v1.
class _FilterChips extends StatelessWidget {
  const _FilterChips({required this.current, required this.onChange});
  final String current;
  final ValueChanged<String> onChange;

  static const _filters = [
    ('all', 'الكل'),
    ('SUBSCRIBER_ACTIVATE', 'تفعيل'),
    ('SUBSCRIBER_EXTEND', 'تمديد'),
    ('BALANCE_DEDUCT', 'تسديد'),
    ('BALANCE_ADD', 'إضافة دين'),
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: 6),
        itemCount: _filters.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (_, i) {
          final (value, label) = _filters[i];
          final selected = value == current;
          return InkWell(
            onTap: () {
              HapticFeedback.selectionClick();
              onChange(value);
            },
            borderRadius: BorderRadius.circular(R.pill),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
              decoration: BoxDecoration(
                color: selected
                    ? AppColors.brand.withValues(alpha: 0.12)
                    : AppColors.surface,
                borderRadius: BorderRadius.circular(R.pill),
                border: Border.all(
                  color: selected
                      ? AppColors.brand.withValues(alpha: 0.4)
                      : AppColors.border,
                ),
              ),
              alignment: Alignment.center,
              child: Text(
                label,
                style: AppType.label(
                  color: selected ? AppColors.brand : AppColors.textMid,
                ).copyWith(
                  fontSize: 12,
                  fontWeight:
                      selected ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _DateHeader extends StatelessWidget {
  const _DateHeader({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, Sp.sm, 4, 4),
      child: Row(
        children: [
          Text(
            label,
            style: AppType.muted(color: AppColors.brand).copyWith(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              height: 1,
              color: AppColors.border,
            ),
          ),
        ],
      ),
    );
  }
}

class _MovementTile extends StatelessWidget {
  const _MovementTile({required this.txn});
  final Map<String, dynamic> txn;

  @override
  Widget build(BuildContext context) {
    final type = (txn['action_type'] ?? '').toString().toUpperCase();
    final desc =
        (txn['description'] ?? txn['action_description'] ?? '').toString();
    final admin = (txn['admin_name'] ??
            txn['admin_username'] ??
            '')
        .toString();
    final createdAt = txn['created_at']?.toString() ?? '';
    final rawAmt = txn['amount'];
    final amount = _readAmount(rawAmt);

    final (icon, color, label) = _visualFor(type, desc);

    final dt = DateTime.tryParse(createdAt);
    final timeStr = dt != null
        ? '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}'
        : '';

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      // Bottom padding generous (12) so Arabic descenders (ع، ج، ق)
      // in the description text don't get clipped by the card border.
      // The user reported lines 'المدفوع: 175,000 د.ع | الدين: 65,000'
      // visibly cut at the bottom in the movements sheet.
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.md),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 16, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(R.sm),
                      ),
                      child: Text(
                        label,
                        style: AppType.label(color: color).copyWith(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    if (timeStr.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Text(
                        timeStr,
                        style: AppType.muted(color: AppColors.textLow)
                            .copyWith(
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                    const Spacer(),
                    if (amount != 0)
                      Text(
                        '${formatIQD(amount.round())} د.ع',
                        style: AppType.label(color: color).copyWith(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                  ],
                ),
                if (desc.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    desc,
                    style: AppType.subtitle(color: AppColors.textHi)
                        .copyWith(fontSize: 12, height: 1.55),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                if (admin.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(LucideIcons.user,
                          size: 10, color: AppColors.textLow),
                      const SizedBox(width: 4),
                      Text(
                        admin,
                        style: AppType.muted(color: AppColors.textLow)
                            .copyWith(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  static (IconData, Color, String) _visualFor(String type, String desc) {
    switch (type) {
      case 'SUBSCRIBER_ACTIVATE':
        // Cash vs non-cash differs in the description text only.
        final isNonCash = desc.contains('غير نقدي');
        return (
          LucideIcons.zap,
          AppColors.brand,
          isNonCash ? 'تفعيل أجل' : 'تفعيل'
        );
      case 'SUBSCRIBER_EXTEND':
        return (LucideIcons.repeat, const Color(0xFF3B82F6), 'تمديد');
      case 'BALANCE_DEDUCT':
      case 'DEBT_PAY':
        return (LucideIcons.banknote, const Color(0xFF14B8A6), 'تسديد دين');
      case 'BALANCE_ADD':
        return (
          LucideIcons.plus,
          const Color(0xFFE08F2D),
          'إضافة دين'
        );
      case 'PAYMENT_ADD':
        return (LucideIcons.wallet, AppColors.brand, 'إيراد');
      default:
        return (LucideIcons.receipt, AppColors.textMid, type);
    }
  }

  static double _readAmount(dynamic raw) {
    if (raw == null) return 0;
    if (raw is num) return raw.toDouble().abs();
    final s = raw.toString().replaceAll(RegExp(r'[^0-9.\-]'), '');
    final v = double.tryParse(s);
    return v?.abs() ?? 0;
  }
}

class _SheetHandle extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 6),
        child: Container(
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: AppColors.border,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      );
}
