import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../api/subscribers_api.dart';
import '../../models/subscriber.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import 'widgets/filter_chips_bar.dart';
import 'widgets/sort_sheet.dart';
import 'widgets/subscriber_card.dart';

/// Subscribers list — v2 port of v1's screen with a modernized look.
/// Phase 1 covers: load, search (debounced), 8 filter chips with counts,
/// sort sheet, pagination, multi-select via long-press, bulk action bar
/// (toggle/delete wired to backend, renew deferred to Phase 5).
class SubscribersScreen extends StatefulWidget {
  const SubscribersScreen({super.key});

  @override
  State<SubscribersScreen> createState() => _SubscribersScreenState();
}

class _SubscribersScreenState extends State<SubscribersScreen> {
  final _searchCtrl = TextEditingController();
  Timer? _debounce;

  List<Subscriber> _all = [];
  Map<String, Map<String, dynamic>> _lastPayments = {};
  bool _loading = true;
  bool _refreshing = false;

  String _query = '';
  SubscriberFilter _filter = SubscriberFilter.all;
  SortField _sortField = SortField.remainingDays;
  SortDirection _sortDir = SortDirection.desc;
  int _page = 0;
  int _pageSize = 25;

  bool _selectionMode = false;
  final Set<String> _selected = {};

  static const _pageSizeOptions = [10, 25, 50, 100, 250, 500];

  @override
  void initState() {
    super.initState();
    _load();
    _searchCtrl.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    await _fetchAndMerge();
    if (!mounted) return;
    setState(() => _loading = false);
  }

  Future<void> _refresh() async {
    setState(() => _refreshing = true);
    await _fetchAndMerge();
    if (!mounted) return;
    setState(() => _refreshing = false);
  }

  /// Pulls the 3 sources in parallel (subscribers + online list + last
  /// payments) then merges: online flag is set per username, payments
  /// land in a separate map keyed by username. Mirrors v1's
  /// loadSubscribers → loadOnlineUsers → loadLastPayments sequence but
  /// runs them concurrently to cut wall time.
  Future<void> _fetchAndMerge() async {
    final results = await Future.wait([
      SubscribersApi.loadAll(),
      SubscribersApi.loadOnline(),
      SubscribersApi.loadLastPayments(),
      SubscribersApi.loadPackages(),
    ]);
    final list = results[0] as List<Subscriber>?;
    final online = results[1] as Set<String>?;
    final payments = results[2] as Map<String, Map<String, dynamic>>?;
    final packages = results[3] as Map<String, String>?;

    if (list == null) return;
    final onlineSet = online ?? const <String>{};
    final packagesById = packages ?? const <String, String>{};
    final merged = list.map((s) {
      final isOn = onlineSet.contains(s.username.toLowerCase());
      // Enrich profileName from the packages list (v1's _enrichWithPackage
      // pattern) THEN flip the online flag if it changed.
      var enriched = s.enrichWithPackages(packagesById);
      if (isOn != enriched.isOnlineFlag) {
        enriched = enriched.copyWithOnline(online: isOn);
      }
      return enriched;
    }).toList();
    _all = merged;
    _lastPayments = payments ?? {};
  }

  void _onSearchChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      if (!mounted) return;
      setState(() {
        _query = _searchCtrl.text.trim();
        _page = 0;
      });
    });
  }

  // ───────── filtering / sorting (matches v1 predicates exactly) ─────────
  List<Subscriber> get _filteredAll {
    Iterable<Subscriber> it = _all;
    switch (_filter) {
      case SubscriberFilter.all:
        break;
      case SubscriberFilter.active:
        it = it.where((s) => s.isActive); // not-expired (disabled included)
      case SubscriberFilter.online:
        it = it.where((s) => s.isOnline);
      case SubscriberFilter.offline:
        it = it.where((s) => s.isOffline); // not-online AND not-expired
      case SubscriberFilter.disabled:
        it = it.where((s) => s.isDisabled);
      case SubscriberFilter.expired:
        it = it.where((s) => s.isExpired);
      case SubscriberFilter.debtors:
        it = it.where((s) => s.hasDebt);
      case SubscriberFilter.nearExpiry:
        it = it.where((s) => s.isNearExpiry);
    }
    if (_query.isNotEmpty) {
      final q = _query.toLowerCase();
      final digits = q.replaceAll(RegExp(r'\D'), '');
      it = it.where((s) {
        if (s.username.toLowerCase().contains(q)) return true;
        if (s.fullName.toLowerCase().contains(q)) return true;
        if (digits.isNotEmpty && s.displayPhone.contains(digits)) return true;
        return false;
      });
    }
    final list = it.toList();
    _applySort(list);
    return list;
  }

  void _applySort(List<Subscriber> list) {
    int cmp(Subscriber a, Subscriber b) {
      switch (_sortField) {
        case SortField.username:
          return a.username.compareTo(b.username);
        case SortField.firstname:
          return a.fullName.compareTo(b.fullName);
        case SortField.profileName:
          return (a.profileName ?? '').compareTo(b.profileName ?? '');
        case SortField.phone:
          return a.displayPhone.compareTo(b.displayPhone);
        case SortField.expiration:
          return (a.expiration ?? '').compareTo(b.expiration ?? '');
        case SortField.remainingDays:
          return (a.remainingDays ?? 99999)
              .compareTo(b.remainingDays ?? 99999);
        case SortField.notes:
          return a.balanceAmount.compareTo(b.balanceAmount);
        case SortField.parentUsername:
          return (a.parentUsername ?? '').compareTo(b.parentUsername ?? '');
      }
    }
    list.sort(_sortDir == SortDirection.asc
        ? cmp
        : (a, b) => -cmp(a, b));
  }

  Map<SubscriberFilter, int> _counts() {
    return {
      SubscriberFilter.all: _all.length,
      SubscriberFilter.active: _all.where((s) => s.isActive).length,
      SubscriberFilter.online: _all.where((s) => s.isOnline).length,
      SubscriberFilter.offline: _all.where((s) => s.isOffline).length,
      SubscriberFilter.disabled: _all.where((s) => s.isDisabled).length,
      SubscriberFilter.expired: _all.where((s) => s.isExpired).length,
      SubscriberFilter.debtors: _all.where((s) => s.hasDebt).length,
      SubscriberFilter.nearExpiry: _all.where((s) => s.isNearExpiry).length,
    };
  }

  // ───────── selection ─────────
  void _toggleSelect(Subscriber s) {
    final id = s.idx;
    if (id == null) return;
    HapticFeedback.selectionClick();
    setState(() {
      if (_selected.contains(id)) {
        _selected.remove(id);
        if (_selected.isEmpty) _selectionMode = false;
      } else {
        _selected.add(id);
        _selectionMode = true;
      }
    });
  }

  void _enterSelectionWith(Subscriber s) {
    final id = s.idx;
    if (id == null) return;
    HapticFeedback.selectionClick();
    setState(() {
      _selectionMode = true;
      _selected.add(id);
    });
  }

  void _exitSelection() {
    setState(() {
      _selectionMode = false;
      _selected.clear();
    });
  }

  void _selectAllOnPage(List<Subscriber> page) {
    setState(() {
      final selectable = page.where((s) => s.idx != null).toList();
      final allOn = selectable.every((s) => _selected.contains(s.idx));
      if (allOn) {
        for (final s in selectable) {
          _selected.remove(s.idx);
        }
        if (_selected.isEmpty) _selectionMode = false;
      } else {
        for (final s in selectable) {
          _selected.add(s.idx!);
        }
      }
    });
  }

  Future<void> _bulk(_BulkAction action) async {
    final ids = _selected.toList();
    if (ids.isEmpty) return;
    final confirm = await _confirmBulk(action, ids.length);
    if (!confirm || !mounted) return;

    _showProgress(action.label);
    var ok = 0, fail = 0;
    for (final id in ids) {
      final success = switch (action) {
        _BulkAction.disable => await SubscribersApi.toggle(id, enable: false),
        _BulkAction.enable => await SubscribersApi.toggle(id, enable: true),
        _BulkAction.delete => await SubscribersApi.delete(id),
      };
      success ? ok++ : fail++;
    }
    if (!mounted) return;
    Navigator.of(context).pop(); // close progress
    _exitSelection();
    await _refresh();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('تم: $ok ${fail > 0 ? '— فشل: $fail' : ''}'),
        backgroundColor: fail == 0 ? AppColors.brand : AppColors.error,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<bool> _confirmBulk(_BulkAction action, int count) async {
    final res = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('تأكيد ${action.label} $count مشترك'),
        content: Text(action == _BulkAction.delete
            ? 'سيتم حذف $count مشترك نهائياً. لا يمكن التراجع.'
            : 'هل أنت متأكد من ${action.label} $count مشترك؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: action == _BulkAction.delete
                  ? AppColors.error
                  : AppColors.brand,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(action.label),
          ),
        ],
      ),
    );
    return res ?? false;
  }

  void _showProgress(String label) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => Dialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(R.lg),
        ),
        child: Padding(
          padding: const EdgeInsets.all(Sp.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: AppColors.brand),
              const SizedBox(height: Sp.md),
              Text('جارٍ $label...',
                  style: AppType.label(color: AppColors.textHi)),
            ],
          ),
        ),
      ),
    );
  }

  // ───────── build ─────────
  @override
  Widget build(BuildContext context) {
    final filtered = _filteredAll;
    final totalPages = (filtered.length / _pageSize).ceil().clamp(1, 99999);
    final pageStart = _page * _pageSize;
    final pageEnd = (pageStart + _pageSize).clamp(0, filtered.length);
    final page = filtered.sublist(pageStart, pageEnd);

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // Header (search or selection)
            Padding(
              padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, Sp.sm),
              child: _selectionMode
                  ? _SelectionHeader(
                      count: _selected.length,
                      total: page.length,
                      onExit: _exitSelection,
                      onSelectAll: () => _selectAllOnPage(page),
                    )
                  : _SearchHeader(
                      controller: _searchCtrl,
                      onSort: () async {
                        final r = await showSortSheet(
                          context,
                          currentField: _sortField,
                          currentDirection: _sortDir,
                        );
                        if (r != null) {
                          setState(() {
                            _sortField = r.field;
                            _sortDir = r.direction;
                            _page = 0;
                          });
                        }
                      },
                    ),
            ),
            FilterChipsBar(
              current: _filter,
              counts: _counts(),
              onSelect: (f) => setState(() {
                _filter = f;
                _page = 0;
              }),
            ),
            const SizedBox(height: Sp.sm),
            // Stats bar — keep the row tight; the page-size picker is a
            // plain text link.
            Padding(
              padding: const EdgeInsets.fromLTRB(Sp.lg, 4, Sp.lg, 4),
              child: Row(
                children: [
                  Text(
                    '${filtered.isEmpty ? 0 : pageStart + 1}-$pageEnd / ${filtered.length}',
                    style: AppType.muted(color: AppColors.textLow)
                        .copyWith(fontSize: 10),
                  ),
                  const Spacer(),
                  _PageSizePicker(
                    current: _pageSize,
                    options: _pageSizeOptions,
                    onChange: (s) =>
                        setState(() {
                          _pageSize = s;
                          _page = 0;
                        }),
                  ),
                ],
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                color: AppColors.brand,
                onRefresh: _refresh,
                child: _loading
                    ? const Center(
                        child: CircularProgressIndicator(
                            color: AppColors.brand))
                    : page.isEmpty
                        ? _EmptyState(filter: _filter, query: _query)
                        : ListView.separated(
                            padding: EdgeInsets.fromLTRB(
                              Sp.lg,
                              0,
                              Sp.lg,
                              Sp.huge * 3 +
                                  MediaQuery.paddingOf(context).bottom,
                            ),
                            itemCount: page.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: Sp.sm),
                            itemBuilder: (_, i) {
                              final s = page[i];
                              final isSelected = s.idx != null &&
                                  _selected.contains(s.idx);
                              return SubscriberCardV2(
                                sub: s,
                                selected: isSelected,
                                lastPayment: _lastPayments[s.username],
                                onTap: () {
                                  if (_selectionMode) {
                                    _toggleSelect(s);
                                  } else {
                                    _openDetail(s);
                                  }
                                },
                                onLongPress: () => _enterSelectionWith(s),
                              );
                            },
                          ),
              ),
            ),
            // Pagination footer
            if (!_loading && totalPages > 1)
              _Pager(
                page: _page,
                totalPages: totalPages,
                onPrev: () => setState(() => _page--),
                onNext: () => setState(() => _page++),
              ),
            if (_refreshing)
              const LinearProgressIndicator(
                color: AppColors.brand,
                backgroundColor: Colors.transparent,
                minHeight: 2,
              ),
          ],
        ),
      ),
      // Selection bottom action bar
      bottomNavigationBar: _selectionMode
          ? _BulkActionBar(
              selectedCount: _selected.length,
              onRenew: () => _showSnack('تجديد جماعي — قيد التطوير (مرحلة 5)'),
              onDisable: () => _bulk(_BulkAction.disable),
              onEnable: () => _bulk(_BulkAction.enable),
              onDelete: () => _bulk(_BulkAction.delete),
            )
          : null,
    );
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: AppColors.textHi,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _openDetail(Subscriber s) {
    // Phase 2: navigate to detail sheet/screen.
    _showSnack('تفاصيل ${s.fullName} — قيد التطوير (مرحلة 2)');
  }
}

enum _BulkAction {
  disable('تعطيل'),
  enable('تفعيل'),
  delete('حذف');

  const _BulkAction(this.label);
  final String label;
}

class _SearchHeader extends StatelessWidget {
  const _SearchHeader({required this.controller, required this.onSort});
  final TextEditingController controller;
  final VoidCallback onSort;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Container(
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
                    controller: controller,
                    style: AppType.input(color: AppColors.textHi),
                    decoration: InputDecoration(
                      hintText: 'ابحث بالاسم أو المعرّف أو رقم الهاتف...',
                      hintStyle: AppType.input(color: AppColors.textLow),
                      border: InputBorder.none,
                      isCollapsed: true,
                      contentPadding:
                          const EdgeInsets.symmetric(vertical: Sp.md),
                    ),
                  ),
                ),
                if (controller.text.isNotEmpty)
                  IconButton(
                    icon: const Icon(LucideIcons.x, size: 16),
                    color: AppColors.textMid,
                    visualDensity: VisualDensity.compact,
                    onPressed: () => controller.clear(),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(width: Sp.sm),
        Material(
          color: AppColors.surface,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onSort,
            child: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.border),
              ),
              child: const Icon(LucideIcons.arrowDownUp,
                  color: AppColors.brand, size: 18),
            ),
          ),
        ),
      ],
    );
  }
}

class _SelectionHeader extends StatelessWidget {
  const _SelectionHeader({
    required this.count,
    required this.total,
    required this.onExit,
    required this.onSelectAll,
  });

  final int count;
  final int total;
  final VoidCallback onExit;
  final VoidCallback onSelectAll;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 42,
      decoration: BoxDecoration(
        color: AppColors.brand.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(R.pill),
        border: Border.all(color: AppColors.brand.withValues(alpha: 0.3)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(LucideIcons.x, size: 18),
            color: AppColors.brand,
            visualDensity: VisualDensity.compact,
            onPressed: onExit,
          ),
          const SizedBox(width: 4),
          Text(
            '$count محدد',
            style: AppType.label(color: AppColors.brand)
                .copyWith(fontSize: 13, fontWeight: FontWeight.w800),
          ),
          const Spacer(),
          TextButton(
            onPressed: onSelectAll,
            child: Text(
              'تحديد الكل ($total)',
              style: AppType.label(color: AppColors.brand)
                  .copyWith(fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _PageSizePicker extends StatelessWidget {
  const _PageSizePicker({
    required this.current,
    required this.options,
    required this.onChange,
  });

  final int current;
  final List<int> options;
  final ValueChanged<int> onChange;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<int>(
      tooltip: 'حجم الصفحة',
      onSelected: onChange,
      itemBuilder: (_) => [
        for (final o in options)
          PopupMenuItem(value: o, child: Text('$o / صفحة')),
      ],
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$current/صفحة',
              style: AppType.muted(color: AppColors.textLow)
                  .copyWith(fontSize: 10, fontWeight: FontWeight.w600)),
          const SizedBox(width: 2),
          const Icon(LucideIcons.chevronDown,
              size: 10, color: AppColors.textLow),
        ],
      ),
    );
  }
}

class _Pager extends StatelessWidget {
  const _Pager({
    required this.page,
    required this.totalPages,
    required this.onPrev,
    required this.onNext,
  });
  final int page;
  final int totalPages;
  final VoidCallback onPrev;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        Sp.lg,
        Sp.sm,
        Sp.lg,
        Sp.sm + MediaQuery.paddingOf(context).bottom,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _ArrowBtn(
            icon: LucideIcons.chevronRight,
            enabled: page > 0,
            onTap: onPrev,
          ),
          const SizedBox(width: Sp.md),
          Text(
            'صفحة ${page + 1} من $totalPages',
            style: AppType.label(color: AppColors.textHi).copyWith(
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: Sp.md),
          _ArrowBtn(
            icon: LucideIcons.chevronLeft,
            enabled: page < totalPages - 1,
            onTap: onNext,
          ),
        ],
      ),
    );
  }
}

class _ArrowBtn extends StatelessWidget {
  const _ArrowBtn({
    required this.icon,
    required this.enabled,
    required this.onTap,
  });
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = enabled ? AppColors.brand : AppColors.textLow;
    return Material(
      color: enabled
          ? AppColors.brand.withValues(alpha: 0.08)
          : AppColors.surfaceInput,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: enabled ? onTap : null,
        child: SizedBox(
          width: 36,
          height: 36,
          child: Icon(icon, color: color, size: 18),
        ),
      ),
    );
  }
}

class _BulkActionBar extends StatelessWidget {
  const _BulkActionBar({
    required this.selectedCount,
    required this.onRenew,
    required this.onDisable,
    required this.onEnable,
    required this.onDelete,
  });
  final int selectedCount;
  final VoidCallback onRenew;
  final VoidCallback onDisable;
  final VoidCallback onEnable;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border(
            top: BorderSide(color: AppColors.border),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, Sp.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.brand,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(R.md),
                  ),
                ),
                onPressed: onRenew,
                icon: const Icon(LucideIcons.calendarPlus, size: 18),
                label: Text(
                  'تجديد الاشتراك ($selectedCount)',
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 14),
                ),
              ),
            ),
            const SizedBox(height: Sp.sm),
            Row(
              children: [
                Expanded(
                  child: _SecondaryBtn(
                    icon: LucideIcons.ban,
                    label: 'تعطيل',
                    color: const Color(0xFFCD8B00),
                    onTap: onDisable,
                  ),
                ),
                const SizedBox(width: Sp.sm),
                Expanded(
                  child: _SecondaryBtn(
                    icon: LucideIcons.circleCheck,
                    label: 'تفعيل',
                    color: AppColors.brand,
                    onTap: onEnable,
                  ),
                ),
                const SizedBox(width: Sp.sm),
                Expanded(
                  child: _SecondaryBtn(
                    icon: LucideIcons.trash2,
                    label: 'حذف',
                    color: AppColors.error,
                    onTap: onDelete,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SecondaryBtn extends StatelessWidget {
  const _SecondaryBtn({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        side: BorderSide(color: color.withValues(alpha: 0.4)),
        padding: const EdgeInsets.symmetric(vertical: 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(R.md),
        ),
      ),
      onPressed: onTap,
      icon: Icon(icon, size: 14),
      label: Text(label,
          style:
              const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.filter, required this.query});
  final SubscriberFilter filter;
  final String query;

  @override
  Widget build(BuildContext context) {
    final msg = query.isNotEmpty
        ? 'لا توجد نتائج بحث "$query"'
        : 'لا يوجد مشترك في هذا الفلتر';
    return ListView(
      // ListView so RefreshIndicator can still pull-to-refresh.
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(height: MediaQuery.sizeOf(context).height * 0.2),
        const Icon(LucideIcons.inbox,
            size: 40, color: AppColors.textLow),
        const SizedBox(height: Sp.sm),
        Text(
          msg,
          textAlign: TextAlign.center,
          style: AppType.label(color: AppColors.textMid)
              .copyWith(fontSize: 14),
        ),
      ],
    );
  }
}
