import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../api/subscribers_api.dart';
import '../../../core/util/format.dart';
import '../../../models/subscriber.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';

/// Bottom sheet that lets the admin pick a subscriber to operate on.
/// Used by the FAB → 'إضافة سريعة' shortcuts for تفعيل / تجديد /
/// تسديد دين / إضافة دين — same flow as the quick search overlay
/// but returns the picked Subscriber via Navigator.pop so the
/// caller can route to the relevant operation sheet.
///
/// [debtorsOnly] hides any subscriber without debt — used by the
/// 'تسديد دين' shortcut so the admin can't pick a sub with nothing
/// to pay.
Future<Subscriber?> showSubscriberPickerSheet(
  BuildContext context, {
  required String title,
  bool debtorsOnly = false,
}) {
  return showModalBottomSheet<Subscriber>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) =>
        _PickerSheet(title: title, debtorsOnly: debtorsOnly),
  );
}

class _PickerSheet extends StatefulWidget {
  const _PickerSheet({required this.title, required this.debtorsOnly});
  final String title;
  final bool debtorsOnly;

  @override
  State<_PickerSheet> createState() => _PickerSheetState();
}

class _PickerSheetState extends State<_PickerSheet> {
  final _searchCtrl = TextEditingController();
  final _focusNode = FocusNode();
  List<Subscriber>? _all;
  bool _loading = true;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() {
      if (mounted) setState(() => _query = _searchCtrl.text);
    });
    _load();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final list = await SubscribersApi.loadAll();
    if (!mounted) return;
    setState(() {
      _all = list;
      _loading = false;
    });
  }

  List<Subscriber> get _filtered {
    final list = _all ?? const [];
    Iterable<Subscriber> it = list;
    if (widget.debtorsOnly) it = it.where((s) => s.hasDebt);
    if (_query.trim().isEmpty) return it.take(50).toList();
    final q = _query.toLowerCase().trim();
    final qDigits = q.replaceAll(RegExp(r'\D'), '');
    final scored = <(int, Subscriber)>[];
    for (final s in it) {
      var score = 0;
      final username = s.username.toLowerCase();
      if (username == q) {
        score += 100;
      } else if (username.startsWith(q)) {
        score += 60;
      } else if (username.contains(q)) {
        score += 30;
      }
      if (s.firstname.contains(_query) ||
          s.lastname.contains(_query) ||
          s.fullName.contains(_query)) {
        score += 40;
      }
      if (qDigits.isNotEmpty && qDigits.length >= 3) {
        final phone =
            (s.phone ?? s.mobile ?? '').replaceAll(RegExp(r'\D'), '');
        if (phone.contains(qDigits)) score += 35;
      }
      if (score > 0) scored.add((score, s));
    }
    scored.sort((a, b) => b.$1.compareTo(a.$1));
    return scored.map((e) => e.$2).take(50).toList();
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return DraggableScrollableSheet(
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
              _SheetHandle(),
              _SheetHeader(
                icon: LucideIcons.userSearch,
                title: widget.title,
                subtitle: widget.debtorsOnly
                    ? 'اختر مشتركاً عليه دين'
                    : 'اختر مشتركاً',
                color: AppColors.brand,
                onClose: () => Navigator.of(context).pop(),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    Sp.lg, Sp.sm, Sp.lg, Sp.sm),
                child: TextField(
                  controller: _searchCtrl,
                  focusNode: _focusNode,
                  style: AppType.input(color: AppColors.textHi),
                  decoration: InputDecoration(
                    hintText: 'ابحث بالاسم أو اليوزر أو الهاتف…',
                    hintStyle: AppType.input(color: AppColors.textLow),
                    prefixIcon: Icon(LucideIcons.search,
                        size: 16, color: AppColors.textMid),
                    suffixIcon: _query.isNotEmpty
                        ? IconButton(
                            icon: const Icon(LucideIcons.x, size: 16),
                            color: AppColors.textMid,
                            visualDensity: VisualDensity.compact,
                            onPressed: () => _searchCtrl.clear(),
                          )
                        : null,
                    filled: true,
                    fillColor: AppColors.surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(R.sm),
                      borderSide: BorderSide(color: AppColors.border),
                    ),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 12),
                  ),
                ),
              ),
              Divider(height: 1, color: AppColors.border),
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
    if (_all == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(LucideIcons.circleAlert,
                color: AppColors.error, size: 32),
            const SizedBox(height: Sp.sm),
            Text(
              'تعذّر جلب المشتركين',
              style: AppType.subtitle(color: AppColors.error),
            ),
            const SizedBox(height: Sp.sm),
            OutlinedButton.icon(
              onPressed: () {
                setState(() => _loading = true);
                _load();
              },
              icon: const Icon(LucideIcons.refreshCw, size: 14),
              label: const Text('إعادة المحاولة'),
            ),
          ],
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
              Icon(LucideIcons.searchX,
                  size: 36, color: AppColors.textLow),
              const SizedBox(height: Sp.sm),
              Text(
                widget.debtorsOnly && _query.trim().isEmpty
                    ? 'لا يوجد مشترك عليه دين'
                    : 'لا توجد نتائج',
                style: AppType.subtitle(color: AppColors.textMid),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }
    return ListView.separated(
      controller: controller,
      padding: const EdgeInsets.fromLTRB(Sp.md, Sp.sm, Sp.md, Sp.md),
      itemCount: list.length,
      separatorBuilder: (_, __) => const SizedBox(height: 4),
      itemBuilder: (_, i) {
        final s = list[i];
        return _Row(
          sub: s,
          onTap: () {
            HapticFeedback.selectionClick();
            Navigator.of(context).pop(s);
          },
        );
      },
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.sub, required this.onTap});
  final Subscriber sub;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final statusColor = _statusColor(sub);
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(R.md),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(R.md),
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: Sp.sm, vertical: Sp.sm),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(R.md),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: statusColor.withValues(alpha: 0.3)),
                ),
                alignment: Alignment.center,
                child: Icon(
                  sub.isOnline ? LucideIcons.wifi : LucideIcons.wifiOff,
                  color: statusColor,
                  size: 14,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            sub.fullName,
                            style: AppType.label(color: AppColors.textHi)
                                .copyWith(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (sub.username != sub.fullName) ...[
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              '(${sub.username})',
                              style:
                                  AppType.muted(color: AppColors.textLow)
                                      .copyWith(
                                fontSize: 10,
                                fontWeight: FontWeight.w500,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (sub.profileName != null || sub.hasDebt) ...[
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          if (sub.profileName?.isNotEmpty ?? false)
                            Flexible(
                              child: Text(
                                sub.profileName!,
                                style:
                                    AppType.muted(color: AppColors.textMid)
                                        .copyWith(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          if (sub.hasDebt) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color: AppColors.error
                                    .withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(R.pill),
                                border: Border.all(
                                  color: AppColors.error
                                      .withValues(alpha: 0.25),
                                ),
                              ),
                              child: Text(
                                'دين ${formatIQD(sub.debtAbs.round())}',
                                style: AppType.muted(color: AppColors.error)
                                    .copyWith(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              Icon(LucideIcons.chevronLeft,
                  size: 16, color: AppColors.textLow),
            ],
          ),
        ),
      ),
    );
  }

  static Color _statusColor(Subscriber s) {
    if (s.isDisabled) return const Color(0xFF94A3B8);
    if (s.isOnline) {
      if (s.isExpired) return const Color(0xFF8B5CF6);
      if (s.isNearExpiry) return const Color(0xFFF59E0B);
      return const Color(0xFF2563EB);
    }
    if (s.isExpired) return AppColors.error;
    if (s.isNearExpiry) return const Color(0xFFF59E0B);
    return const Color(0xFF10B981);
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

class _SheetHeader extends StatelessWidget {
  const _SheetHeader({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onClose,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Container(
      padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.sm, Sp.sm, Sp.md),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(R.sm),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: Sp.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title,
                    style: AppType.label(color: AppColors.textHi).copyWith(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        height: 1.2)),
                const SizedBox(height: 3),
                Text(subtitle,
                    style: AppType.muted(color: AppColors.textMid).copyWith(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        height: 1.2),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ],
            ),
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
