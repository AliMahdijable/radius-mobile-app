import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../api/subscribers_api.dart';
import '../../../core/util/format.dart';
import '../../../models/subscriber.dart';
import '../../../core/widgets/design_sheet.dart';
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
    barrierColor: AppColors.scrim,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _PickerSheet(title: title, debtorsOnly: debtorsOnly),
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
        final phone = (s.phone ?? s.mobile ?? '').replaceAll(RegExp(r'\D'), '');
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
    return DesignSheet(
      header: SheetHeaderBar(
        icon: LucideIcons.userSearch,
        title: widget.title,
        subtitle: widget.debtorsOnly ? 'اختر مشتركاً عليه دين' : 'اختر مشتركاً',
        onClose: () => Navigator.of(context).pop(),
      ),
      scrollable: false,
      bodyPadding: EdgeInsets.zero,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Sp.xl, Sp.md, Sp.xl, Sp.md),
            child: SheetBox(
              icon: LucideIcons.search,
              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 4),
              child: TextField(
                controller: _searchCtrl,
                focusNode: _focusNode,
                style: AppType.input(),
                decoration: InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  hintText: 'ابحث بالاسم أو اليوزر أو الهاتف…',
                  hintStyle: AppType.input(color: AppColors.textPlaceholder),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(LucideIcons.x, size: 16),
                          color: AppColors.textMid,
                          visualDensity: VisualDensity.compact,
                          onPressed: () => _searchCtrl.clear(),
                        ),
                ),
              ),
            ),
          ),
          Divider(height: 1, color: AppColors.divider),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return Center(
        child: CircularProgressIndicator(color: AppColors.brand),
      );
    }
    if (_all == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(LucideIcons.circleAlert, color: AppColors.error, size: 32),
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
              Icon(LucideIcons.searchX, size: 36, color: AppColors.textLow),
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
          padding:
              const EdgeInsets.symmetric(horizontal: Sp.sm, vertical: Sp.sm),
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
                  border: Border.all(color: statusColor.withValues(alpha: 0.3)),
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
                        // الاسم يبتلع الباقي، والمعرّف يأخذ مقاسه.
                        // مرنان بالوزن نفسه يقتسمان مناصفةً ولا يتنازل
                        // أحدهما لأخيه — راجع `report_log_tile`.
                        Expanded(
                          child: Text(
                            sub.fullName,
                            style:
                                AppType.label(color: AppColors.textHi).copyWith(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (sub.username != sub.fullName) ...[
                          const SizedBox(width: 4),
                          Text(
                            '(${sub.username})',
                            style: AppType.muted(color: AppColors.textLow)
                                .copyWith(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
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
                                style: AppType.muted(color: AppColors.textMid)
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
                                color: AppColors.dangerSoftBg,
                                borderRadius: BorderRadius.circular(R.pill),
                                border: Border.all(
                                  color: AppColors.dangerSoftBorder,
                                ),
                              ),
                              child: Text(
                                'دين ${formatIQD(sub.debtAbs.round())}',
                                style: AppType.muted(color: AppColors.error)
                                    .copyWith(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w700,
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
              Icon(LucideIcons.chevronLeft, size: 16, color: AppColors.textLow),
            ],
          ),
        ),
      ),
    );
  }

  static Color _statusColor(Subscriber s) {
    if (s.isDisabled) return AppColors.textLabel;
    if (s.isOnline) {
      if (s.isExpired) return AppColors.brandAccent;
      if (s.isNearExpiry) return AppColors.warning;
      return AppColors.brandAccent;
    }
    if (s.isExpired) return AppColors.error;
    if (s.isNearExpiry) return AppColors.warning;
    return AppColors.success;
  }
}
