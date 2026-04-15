import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/subscribers_provider.dart';
import '../../providers/dashboard_provider.dart';
import '../../models/subscriber_model.dart';
import '../../widgets/subscriber_card.dart';
import '../../widgets/loading_overlay.dart';
import '../../widgets/add_subscriber_sheet.dart';
import '../../core/theme/app_theme.dart';

class SubscribersScreen extends ConsumerStatefulWidget {
  const SubscribersScreen({super.key});

  @override
  ConsumerState<SubscribersScreen> createState() => _SubscribersScreenState();
}

class _SubscribersScreenState extends ConsumerState<SubscribersScreen> {
  final _searchController = TextEditingController();
  Timer? _debounce;
  bool _isSearchMode = false;
  int _pageSize = 25;
  int _currentPage = 0;

  static const _pageSizes = [10, 25, 50, 100, 250, 500];

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(subscribersProvider.notifier).loadSubscribers();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearch(String query) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      ref.read(subscribersProvider.notifier).searchSubscribers(query);
    });
  }

  static const _filters = [
    _FilterDef('all', 'الكل', Icons.people_alt_rounded, AppTheme.primary),
    _FilterDef('active', 'الفعالين', Icons.check_circle_rounded, AppTheme.teal600),
    _FilterDef('online', 'متصل', Icons.wifi_rounded, AppTheme.teal400),
    _FilterDef('offline', 'غير متصل', Icons.wifi_off_rounded, Color(0xFF90A4AE)),
    _FilterDef('expired', 'المنتهي', Icons.timer_off_rounded, Color(0xFFC62828)),
    _FilterDef('debtors', 'المديونين', Icons.credit_card_off_rounded, Color(0xFFF57F17)),
    _FilterDef('nearExpiry', 'قريب الانتهاء', Icons.warning_amber_rounded, Colors.deepOrange),
  ];

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(subscribersProvider);
    final dash = ref.watch(dashboardProvider);
    final theme = Theme.of(context);

    final fullList =
        _isSearchMode ? state.searchResults : state.filteredSubscribers;

    final totalItems = fullList.length;
    final totalPages = (totalItems / _pageSize).ceil();
    if (_currentPage >= totalPages && totalPages > 0) {
      _currentPage = totalPages - 1;
    }

    final startIdx = _currentPage * _pageSize;
    final endIdx = (startIdx + _pageSize).clamp(0, totalItems);
    final displayList = totalItems > 0
        ? fullList.sublist(startIdx, endIdx)
        : <SubscriberModel>[];

    final currentFilter = state.filter;
    final isOnlineFilter = currentFilter == 'online';

    String _getCount(_FilterDef f) {
      switch (f.key) {
        case 'all': return '${state.subscribers.length}';
        case 'active': return '${state.activeCount}';
        case 'online': return '${state.onlineCount}';
        case 'offline': return '${state.offlineCount}';
        case 'expired': return '${state.expiredCount}';
        case 'debtors': return '${state.debtorsCount}';
        case 'nearExpiry': return '${state.nearExpiryCount}';
        default: return '0';
      }
    }

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: TextField(
            controller: _searchController,
            onChanged: (v) {
              setState(() {
                _isSearchMode = v.isNotEmpty;
                _currentPage = 0;
              });
              _onSearch(v);
            },
            decoration: InputDecoration(
              hintText: 'بحث عن مشترك...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _isSearchMode
                  ? IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        _searchController.clear();
                        setState(() {
                          _isSearchMode = false;
                          _currentPage = 0;
                        });
                        ref
                            .read(subscribersProvider.notifier)
                            .searchSubscribers('');
                      },
                    )
                  : null,
            ),
          ),
        ),

        if (!_isSearchMode)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: _filters.map((f) {
                final count = _getCount(f);
                return Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: _FilterChip(
                    icon: f.icon,
                    label: '${f.label} ($count)',
                    selected: currentFilter == f.key,
                    color: f.color,
                    onTap: () {
                      ref.read(subscribersProvider.notifier).setFilter(f.key);
                      setState(() => _currentPage = 0);
                    },
                  ),
                );
              }).toList(),
            ),
          ),

        const SizedBox(height: 6),

        if (!_isSearchMode && totalItems > 0)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                Text(
                  '${startIdx + 1}-$endIdx من $totalItems',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withOpacity(0.5),
                    fontWeight: FontWeight.w600,
                    fontSize: 11,
                  ),
                ),
                const Spacer(),
                if (totalPages > 1) ...[
                  _NavBtn(
                    icon: Icons.chevron_right,
                    enabled: _currentPage > 0,
                    onTap: () => setState(() => _currentPage--),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Text(
                      '${_currentPage + 1}/$totalPages',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        fontSize: 11,
                      ),
                    ),
                  ),
                  _NavBtn(
                    icon: Icons.chevron_left,
                    enabled: _currentPage < totalPages - 1,
                    onTap: () => setState(() => _currentPage++),
                  ),
                  const SizedBox(width: 8),
                ],
                Container(
                  height: 28,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerLowest,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: theme.colorScheme.onSurface.withOpacity(0.1)),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<int>(
                      value: _pageSize,
                      isDense: true,
                      menuMaxHeight: 200,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        fontSize: 11,
                        color: theme.colorScheme.onSurface,
                      ),
                      items: _pageSizes
                          .map((s) => DropdownMenuItem(
                              value: s, child: Text('$s')))
                          .toList(),
                      onChanged: (v) {
                        if (v != null) {
                          setState(() {
                            _pageSize = v;
                            _currentPage = 0;
                          });
                        }
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),

        Expanded(
          child: state.isLoading && state.subscribers.isEmpty
              ? const ShimmerList()
              : displayList.isEmpty
                  ? EmptyState(
                      icon: _isSearchMode
                          ? Icons.search_off
                          : Icons.people_outline,
                      title: _isSearchMode
                          ? 'لا توجد نتائج'
                          : 'لا يوجد مشتركين',
                      subtitle: _isSearchMode
                          ? 'جرب كلمة بحث مختلفة'
                          : 'اسحب للأسفل لتحديث البيانات',
                    )
                  : RefreshIndicator(
                      onRefresh: () async {
                        await ref
                            .read(subscribersProvider.notifier)
                            .loadSubscribers();
                      },
                      child: ListView.builder(
                        padding: const EdgeInsets.only(bottom: 100),
                        itemCount: displayList.length,
                        itemBuilder: (context, index) {
                          return SubscriberCard(
                            subscriber: displayList[index],
                            showOnlineDetails: isOnlineFilter,
                            onTap: () {
                              context.push(
                                '/subscriber/${displayList[index].username}',
                                extra: displayList[index],
                              );
                            },
                          );
                        },
                      ),
                    ),
        ),
      ],
    );
  }
}

class _NavBtn extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;
  const _NavBtn({required this.icon, required this.enabled, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        width: 28, height: 28,
        decoration: BoxDecoration(
          color: enabled
              ? Theme.of(context).colorScheme.primary.withOpacity(0.1)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(icon, size: 18,
            color: enabled
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.onSurface.withOpacity(0.2)),
      ),
    );
  }
}

class _FilterDef {
  final String key;
  final String label;
  final IconData icon;
  final Color color;
  const _FilterDef(this.key, this.label, this.icon, this.color);
}

class _FilterChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final Color? color;
  final VoidCallback onTap;

  const _FilterChip({
    required this.icon,
    required this.label,
    required this.selected,
    this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final activeColor = color ?? theme.colorScheme.primary;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color:
              selected ? activeColor.withOpacity(0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected
                ? activeColor.withOpacity(0.4)
                : theme.colorScheme.onSurface.withOpacity(0.1),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14,
                color: selected
                    ? activeColor
                    : theme.colorScheme.onSurface.withOpacity(0.4)),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected
                    ? activeColor
                    : theme.colorScheme.onSurface.withOpacity(0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
