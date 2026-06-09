import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../api/subscribers_api.dart';
import '../../models/subscriber.dart';
import '../../services/subscriber_events.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import 'sheets/bulk_activate_sheet.dart';
import 'sheets/bulk_pay_debt_sheet.dart';
import 'subscriber_detail_screen.dart';
import 'widgets/filter_chips_bar.dart';
import 'widgets/sort_sheet.dart';
import 'widgets/subscriber_card.dart';

/// Default sort field + direction per filter — mirrors v1's
/// `_defaultSortByFilter`. Without this the 'قارب الانتهاء' chip
/// surfaced subscribers in random order; now it shows least-time-left
/// first, which is what admins actually want when triaging expiries.
const _defaultSortByFilter = <SubscriberFilter, (SortField, SortDirection)>{
  SubscriberFilter.all: (SortField.remainingDays, SortDirection.desc),
  SubscriberFilter.active: (SortField.remainingDays, SortDirection.desc),
  // Online filter: shortest session time first (just-connected → at
  // top). Subscribers without a session_time fall to the bottom via
  // the comparator's null handling.
  SubscriberFilter.online: (SortField.sessionTime, SortDirection.asc),
  SubscriberFilter.offline: (SortField.remainingDays, SortDirection.desc),
  SubscriberFilter.disabled: (SortField.username, SortDirection.asc),
  SubscriberFilter.expired: (SortField.expiration, SortDirection.desc),
  SubscriberFilter.debtors: (SortField.notes, SortDirection.asc),
  SubscriberFilter.nearExpiry: (SortField.remainingDays, SortDirection.asc),
};

/// Subscribers list — v2 port of v1's screen with a modernized look.
/// Phase 1 covers: load, search (debounced), 8 filter chips with counts,
/// sort sheet, pagination, multi-select via long-press, bulk action bar
/// (toggle/delete wired to backend, renew deferred to Phase 5).
class SubscribersScreen extends StatefulWidget {
  const SubscribersScreen({super.key, this.filterCmd});

  /// Filter command from MainShell. When dashboard KPIs are tapped the
  /// ValueNotifier fires with the desired filter and this screen
  /// applies it WITHOUT re-fetching — the list stays cached in memory
  /// so the tab switch feels instant.
  final ValueListenable<SubscriberFilter?>? filterCmd;

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
    _filter = widget.filterCmd?.value ?? SubscriberFilter.all;
    _applyDefaultSortFor(_filter);
    widget.filterCmd?.addListener(_onFilterCmd);
    // Re-fetch whenever any operation anywhere in the app mutates a
    // subscriber (activate / extend / disconnect / toggle / delete /
    // bulk action). Mirrors v1's notifier pattern.
    SubscriberEvents.dataChanged.addListener(_onDataChanged);
    _load();
    _searchCtrl.addListener(_onSearchChanged);
  }

  void _onDataChanged() {
    if (!mounted) return;
    _refresh();
  }

  /// Called when MainShell pushes a new filter via the notifier. Reset
  /// paging + apply v1's default sort for the new filter so the user
  /// sees the relevant rows up top (e.g. tapping the dashboard's
  /// 'قارب الانتهاء' KPI surfaces least-time-left first).
  void _onFilterCmd() {
    final next = widget.filterCmd?.value;
    if (next == null || next == _filter) return;
    setState(() {
      _filter = next;
      _applyDefaultSortFor(next);
      _page = 0;
    });
  }

  void _applyDefaultSortFor(SubscriberFilter f) {
    final d = _defaultSortByFilter[f];
    if (d == null) return;
    _sortField = d.$1;
    _sortDir = d.$2;
  }

  @override
  void dispose() {
    widget.filterCmd?.removeListener(_onFilterCmd);
    SubscriberEvents.dataChanged.removeListener(_onDataChanged);
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
    // Bypass the process-wide cache so pull-to-refresh always returns
    // fresh server data even if the cached entry is still warm.
    await SubscribersApi.refreshAll();
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
    final online = results[1] as Map<String, OnlineSessionInfo>?;
    final payments = results[2] as Map<String, Map<String, dynamic>>?;
    final packages = results[3] as Map<String, PackageInfo>?;

    if (list == null) return;
    final onlineMap = online ?? const <String, OnlineSessionInfo>{};
    final packagesById = packages ?? const <String, PackageInfo>{};
    final merged = list.map((s) {
      // Match v1 (subscribers_provider.dart:455-489) exactly:
      // /api/v2/subscribers IS the source of truth for the online flag —
      // it reads online_status / is_online directly from SAS4. The
      // separate /api/v2/online-users call only EXISTS to enrich the
      // live session row (IP / session time / DL / UL bytes) so the
      // detail screen can show them. We never demote a subscriber to
      // offline based on the online-users map missing them — doing so
      // earlier silently zeroed out 'متصل' for the whole admin tree
      // when the merge ran before /online-users finished.
      var enriched = s.enrichWithPackages(packagesById);
      final session = onlineMap[enriched.username.toLowerCase()];
      if (session != null) {
        enriched = enriched.copyWithOnline(
          online: true,
          ip: session.ip,
          session: session.sessionTime,
          dl: session.downloadBytes,
          ul: session.uploadBytes,
          device: session.device,
        );
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

  /// Manager filter — when set, the list is restricted to subscribers
  /// whose parent_username matches. Drives _managerScoped which is the
  /// pre-filter source for both _filteredAll AND _counts so the chip
  /// counters on the bar reflect the manager subset (e.g. 'متصل (3)'
  /// when looking at one manager, not the whole tenant).
  String? _managerFilter;

  /// Distinct parent_username values from the loaded list, sorted.
  /// Empty when no subscriber has a parent (single-tenant admins).
  List<String> get _availableManagers {
    final set = <String>{};
    for (final s in _all) {
      final p = s.parentUsername;
      if (p != null && p.isNotEmpty) set.add(p);
    }
    final list = set.toList()..sort();
    return list;
  }

  /// Pre-filter source — apply the manager filter first so chip counts
  /// AND the main filter pipeline both work off the same subset.
  List<Subscriber> get _managerScoped {
    if (_managerFilter == null) return _all;
    return _all.where((s) => s.parentUsername == _managerFilter).toList();
  }

  // ───────── filtering / sorting (matches v1 predicates exactly) ─────────
  List<Subscriber> get _filteredAll {
    Iterable<Subscriber> it = _managerScoped;
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
        case SortField.sessionTime:
          // Null sessionTime sinks to the bottom regardless of asc/desc
          // so offline rows don't clutter the head of the online list.
          final aHas = a.sessionTime != null;
          final bHas = b.sessionTime != null;
          if (!aHas && !bHas) return 0;
          if (!aHas) return _sortDir == SortDirection.asc ? 1 : -1;
          if (!bHas) return _sortDir == SortDirection.asc ? -1 : 1;
          return a.sessionTime!.compareTo(b.sessionTime!);
      }
    }
    list.sort(_sortDir == SortDirection.asc
        ? cmp
        : (a, b) => -cmp(a, b));
  }

  Map<SubscriberFilter, int> _counts() {
    // Manager-scoped so chip counters reflect the current sub-manager
    // pick: 'متصل (3)' means 3 online subs UNDER that manager, not 3
    // across the whole tenant. Matches v1 behaviour.
    final src = _managerScoped;
    return {
      SubscriberFilter.all: src.length,
      SubscriberFilter.active: src.where((s) => s.isActive).length,
      SubscriberFilter.online: src.where((s) => s.isOnline).length,
      SubscriberFilter.offline: src.where((s) => s.isOffline).length,
      SubscriberFilter.disabled: src.where((s) => s.isDisabled).length,
      SubscriberFilter.expired: src.where((s) => s.isExpired).length,
      SubscriberFilter.debtors: src.where((s) => s.hasDebt).length,
      SubscriberFilter.nearExpiry: src.where((s) => s.isNearExpiry).length,
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

  /// How many selected rows currently carry debt. Powers the bulk
  /// pay-debt button — hidden when zero so the bar doesn't offer an
  /// action that would open an empty sheet.
  int get _selectedDebtorCount =>
      _filteredSubscribersForBulk().where((s) => s.hasDebt).length;

  /// Per-action counts for the bulk bar. The disable button only
  /// affects rows currently enabled; the enable button only affects
  /// rows currently disabled. Showing the count next to each button
  /// (مطلب 2026-06-07) lets the admin see e.g. "تعطيل (1)" + "تفعيل (2)"
  /// when the selection mixes states, so they pick the right action
  /// without unstacking the selection.
  int get _enabledInSelection =>
      _filteredSubscribersForBulk().where((s) => !s.isDisabled).length;
  int get _disabledInSelection =>
      _filteredSubscribersForBulk().where((s) => s.isDisabled).length;
  /// Rows currently online — the disconnect button affects only
  /// these. Subscribers who aren't connected have no session to
  /// kick, so we skip them in the loop AND hide the count when zero.
  int get _onlineInSelection =>
      _filteredSubscribersForBulk().where((s) => s.isOnline).length;

  Future<void> _openBulkDisconnect() async {
    final online = _filteredSubscribersForBulk()
        .where((s) => s.isOnline && s.idx != null)
        .toList();
    if (online.isEmpty) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('فصل المستخدمين'),
        content: Text(
          'سيتم قطع جلسة ${online.length} مشترك الآن. سيحتاجون إلى '
          'إعادة الاتصال يدوياً.',
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
            child: const Text('فصل'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    _showProgress('فصل المستخدمين');
    var ok = 0, fail = 0;
    for (final s in online) {
      final success = await SubscribersApi.disconnect(s.idx!);
      success ? ok++ : fail++;
    }
    if (!mounted) return;
    Navigator.of(context).pop(); // close progress
    _exitSelection();
    // Disconnect doesn't change DB state (just kicks the live
    // session), but the online overlay should refresh so the rows
    // stop showing the connected badge. notifyChange triggers the
    // shared dataChanged → screens re-fetch.
    if (ok > 0) SubscriberEvents.notifyChange();
    await _refresh();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('تم فصل $ok ${fail > 0 ? '— فشل: $fail' : ''}'),
        backgroundColor: fail == 0 ? AppColors.brand : AppColors.error,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// Resolve the selected idx set back to the live Subscriber objects
  /// the bulk sheets need (debt, name, balance). The full list comes
  /// from the same _subs we render — we just filter by idx membership.
  List<Subscriber> _filteredSubscribersForBulk() {
    if (_selected.isEmpty) return const [];
    return _all
        .where((s) => s.idx != null && _selected.contains(s.idx!))
        .toList();
  }

  Future<void> _openBulkPayDebt() async {
    final debtors = _filteredSubscribersForBulk()
        .where((s) => s.hasDebt)
        .toList();
    if (debtors.isEmpty) return;
    await showBulkPayDebtSheet(context, subs: debtors);
    if (!mounted) return;
    _exitSelection();
    // The sheet itself fires SubscriberEvents.notifyChange on any
    // success, which triggers _onDataChanged → _refresh. We still
    // exit selection mode here so the bulk bar collapses regardless.
  }

  Future<void> _openBulkActivate() async {
    final selected = _filteredSubscribersForBulk();
    if (selected.isEmpty) return;
    await showBulkActivateSheet(context, subs: selected);
    if (!mounted) return;
    _exitSelection();
  }

  Future<void> _bulk(_BulkAction action) async {
    // For toggle actions filter the selection to rows that actually
    // need the flip — disabling an already-disabled row is a no-op
    // that wastes a network call AND inflates the failure count when
    // the backend rejects it. Delete affects the whole selection.
    final selectedSubs = _filteredSubscribersForBulk();
    final eligible = switch (action) {
      _BulkAction.disable =>
        selectedSubs.where((s) => !s.isDisabled).toList(),
      _BulkAction.enable =>
        selectedSubs.where((s) => s.isDisabled).toList(),
      _BulkAction.delete => selectedSubs,
    };
    final ids = eligible.map((s) => s.idx).whereType<String>().toList();
    if (ids.isEmpty) return;
    final confirm = await _confirmBulk(action, ids.length);
    if (!confirm || !mounted) return;

    _showProgress(action.label);
    var ok = 0, fail = 0;
    for (final id in ids) {
      final success = await switch (action) {
        _BulkAction.disable =>
          SubscribersApi.toggle(id, enable: false),
        _BulkAction.enable => SubscribersApi.toggle(id, enable: true),
        // delete now returns a structured result so we map to bool
        // before tallying. The error message is already surfaced via
        // the per-row tracking in the single-delete confirm flow;
        // bulk just counts ok/fail and shows a summary snackbar.
        _BulkAction.delete =>
          SubscribersApi.delete(id).then((r) => r.ok),
      };
      success ? ok++ : fail++;
    }
    if (!mounted) return;
    Navigator.of(context).pop(); // close progress
    _exitSelection();
    if (ok > 0) SubscriberEvents.notifyChange();
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
            // Sub-manager (parent) filter — sits right under the
            // search bar like v1's "كل المدراء" dropdown. Shown
            // whenever at least one subscriber has a parent_username
            // set (مطلب 2026-06-10: discoverability — admins want
            // to see the filter exists even with a single parent).
            // Hidden only for tenants where NO subscriber has a
            // parent (zero sub-managers, nothing to scope to).
            if (!_selectionMode && _availableManagers.isNotEmpty)
              _ManagerFilterBar(
                current: _managerFilter,
                managers: _availableManagers,
                onSelect: (m) => setState(() {
                  _managerFilter = m;
                  _page = 0;
                }),
              ),
            FilterChipsBar(
              current: _filter,
              counts: _counts(),
              onSelect: (f) => setState(() {
                _filter = f;
                _applyDefaultSortFor(f);
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
                        .copyWith(fontSize: 11, fontWeight: FontWeight.w500),
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
                                showLiveSession:
                                    _filter == SubscriberFilter.online,
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
              debtorCount: _selectedDebtorCount,
              enabledCount: _enabledInSelection,
              disabledCount: _disabledInSelection,
              onlineCount: _onlineInSelection,
              onRenew: _openBulkActivate,
              onPayDebt: _selectedDebtorCount > 0 ? _openBulkPayDebt : null,
              onDisconnect:
                  _onlineInSelection > 0 ? _openBulkDisconnect : null,
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
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SubscriberDetailScreen(sub: s),
        fullscreenDialog: true,
      ),
    );
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
                  .copyWith(fontSize: 11, fontWeight: FontWeight.w600)),
          const SizedBox(width: 2),
          const Icon(LucideIcons.chevronDown,
              size: 11, color: AppColors.textLow),
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
              fontSize: 12, // Card title tier — secondary nav text
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

/// Sub-manager (parent) filter strip — horizontal chip row matching
/// the FilterChipsBar visual language. Leading shield icon + 'كل
/// المدراء' chip + one chip per parent_username found in the loaded
/// list. Tap a chip to scope the whole screen to that sub-manager;
/// tap الكل to clear. Mirrors v1's "كل المدراء" dropdown but the
/// chip row reads at a glance instead of hiding the choices behind
/// a tap (مطلب 2026-06-09).
class _ManagerFilterBar extends StatelessWidget {
  const _ManagerFilterBar({
    required this.current,
    required this.managers,
    required this.onSelect,
  });
  final String? current;
  final List<String> managers;
  final ValueChanged<String?> onSelect;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Sp.lg, 0, Sp.lg, 4),
      child: Row(
        children: [
          const Icon(LucideIcons.shield,
              size: 14, color: AppColors.textMid),
          const SizedBox(width: 6),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _ManagerChip(
                    label: 'كل المدراء',
                    selected: current == null,
                    onTap: () => onSelect(null),
                  ),
                  for (final m in managers) ...[
                    const SizedBox(width: 6),
                    _ManagerChip(
                      label: m,
                      selected: current == m,
                      onTap: () => onSelect(m),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ManagerChip extends StatelessWidget {
  const _ManagerChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      borderRadius: BorderRadius.circular(R.pill),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
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
        child: Text(
          label,
          style: AppType.label(
            color: selected ? AppColors.brand : AppColors.textMid,
          ).copyWith(
            fontSize: 11,
            fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
            height: 1.2,
          ),
        ),
      ),
    );
  }
}

class _BulkActionBar extends StatelessWidget {
  const _BulkActionBar({
    required this.selectedCount,
    required this.debtorCount,
    required this.enabledCount,
    required this.disabledCount,
    required this.onlineCount,
    required this.onRenew,
    required this.onPayDebt,
    required this.onDisconnect,
    required this.onDisable,
    required this.onEnable,
    required this.onDelete,
  });
  final int selectedCount;
  final int debtorCount;
  /// Selected rows currently enabled — these are the ones a tap on
  /// 'تعطيل' will actually affect. Shown as '(N)' next to the label
  /// so the admin sees how many will flip even when the selection
  /// mixes states (مطلب 2026-06-07).
  final int enabledCount;
  final int disabledCount;
  /// Rows currently online — the disconnect button only affects
  /// these. Hidden when zero so the bar doesn't show an empty action.
  final int onlineCount;
  final VoidCallback onRenew;
  /// null = no debtors in selection → button disabled. Non-null →
  /// opens the bulk pay-debt sheet against the debtor subset.
  final VoidCallback? onPayDebt;
  /// null = no online rows in selection → button hidden entirely
  /// (no greyed-out state — disconnect is a hot action and the row
  /// is otherwise reserved for the toggle/delete trio).
  final VoidCallback? onDisconnect;
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
            // Bulk pay-debt — shows only when the selection contains at
            // least one subscriber with debt. Counter in the label tells
            // the admin exactly how many rows will participate.
            if (debtorCount > 0) ...[
              const SizedBox(height: Sp.sm),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF14B8A6),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(R.md),
                    ),
                  ),
                  onPressed: onPayDebt,
                  icon: const Icon(LucideIcons.banknote, size: 16),
                  label: Text(
                    'تسديد دين ($debtorCount)',
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 13),
                  ),
                ),
              ),
            ],
            // Bulk disconnect — kicks online sessions off the network
            // without touching the enabled flag. Hidden when nobody in
            // the selection is online (no point showing 'فصل (0)').
            if (onlineCount > 0) ...[
              const SizedBox(height: Sp.sm),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.error,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(R.md),
                    ),
                  ),
                  onPressed: onDisconnect,
                  icon: const Icon(LucideIcons.power, size: 16),
                  label: Text(
                    'فصل المتصلين ($onlineCount)',
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 13),
                  ),
                ),
              ),
            ],
            const SizedBox(height: Sp.sm),
            Row(
              children: [
                Expanded(
                  child: _SecondaryBtn(
                    icon: LucideIcons.ban,
                    label: enabledCount > 0
                        ? 'تعطيل ($enabledCount)'
                        : 'تعطيل',
                    color: const Color(0xFFCD8B00),
                    enabled: enabledCount > 0,
                    onTap: onDisable,
                  ),
                ),
                const SizedBox(width: Sp.sm),
                Expanded(
                  child: _SecondaryBtn(
                    icon: LucideIcons.circleCheck,
                    label: disabledCount > 0
                        ? 'تفعيل ($disabledCount)'
                        : 'تفعيل',
                    color: AppColors.brand,
                    enabled: disabledCount > 0,
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
    this.enabled = true,
  });
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  /// When false the button greys out — used by the bulk bar to signal
  /// that no rows in the current selection are eligible for this
  /// action (e.g. all rows already disabled → 'تعطيل' has nothing
  /// to do).
  final bool enabled;

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
      onPressed: enabled ? onTap : null,
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
              .copyWith(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}
