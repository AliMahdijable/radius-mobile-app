import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../providers/auth_provider.dart';
import '../../providers/subscribers_provider.dart';
import '../../providers/dashboard_provider.dart';
import '../../models/subscriber_model.dart';
import '../../widgets/subscriber_card.dart';
import '../../widgets/loading_overlay.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/add_subscriber_sheet.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/helpers.dart';
import '../../core/utils/bottom_sheet_utils.dart';
import '../../core/services/fcm_service.dart';

class SubscribersScreen extends ConsumerStatefulWidget {
  const SubscribersScreen({super.key});

  @override
  ConsumerState<SubscribersScreen> createState() => _SubscribersScreenState();
}

class _SubscribersScreenState extends ConsumerState<SubscribersScreen> {
  final _searchController = TextEditingController();
  // Horizontal scroll controller for the filter chip bar so we can scroll
  // the currently-selected chip into view when the user lands here via a
  // dashboard KPI tap. The chips bar has 7 items and the nearExpiry /
  // debtors ones sit off-screen on narrow phones, so a freshly activated
  // filter looked like nothing changed.
  final _chipScrollController = ScrollController();
  final Map<String, GlobalKey> _chipKeys = {};
  Timer? _debounce;
  bool _isSearchMode = false;
  int _pageSize = 25;
  int _currentPage = 0;
  String? _lastScrolledFilter;

  static const _pageSizes = [10, 25, 50, 100, 250, 500];

  static const _sortFields = [
    _SortFieldDef('username', 'اسم المستخدم', Icons.person_rounded),
    _SortFieldDef('firstname', 'الاسم', Icons.badge_rounded),
    _SortFieldDef('name', 'الباقة', Icons.inventory_2_rounded),
    _SortFieldDef('mobile', 'رقم الهاتف', Icons.phone_rounded),
    _SortFieldDef('expiration', 'تاريخ الانتهاء', Icons.event_rounded),
    _SortFieldDef('remaining_days', 'الأيام المتبقية', Icons.schedule_rounded),
    _SortFieldDef('notes', 'الديون', Icons.account_balance_wallet_rounded),
    _SortFieldDef('parent_username', 'تابع إلى', Icons.supervisor_account_rounded),
  ];

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(subscribersProvider.notifier).loadSubscribers();
    });
    FcmService.pendingSubscriberSearch.addListener(_consumePendingSearch);
    if (FcmService.pendingSubscriberSearch.value != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _consumePendingSearch();
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _chipScrollController.dispose();
    _debounce?.cancel();
    FcmService.pendingSubscriberSearch.removeListener(_consumePendingSearch);
    super.dispose();
  }

  void _consumePendingSearch() {
    final username = FcmService.pendingSubscriberSearch.value;
    if (username == null || username.isEmpty || !mounted) return;
    setState(() {
      _searchController.text = username;
      _isSearchMode = true;
      _currentPage = 0;
    });
    ref.read(subscribersProvider.notifier).searchSubscribers(username);
    FcmService.pendingSubscriberSearch.value = null;
  }

  void _onSearch(String query) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      ref.read(subscribersProvider.notifier).searchSubscribers(query);
    });
  }

  void _showSortSheet(BuildContext context, String currentSort, String currentDir) {
    final theme = Theme.of(context);
    showModalBottomSheet(
      useSafeArea: true,
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        String selectedField = currentSort;
        String selectedDir = currentDir;
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                12,
                20,
                bottomSheetBottomInset(ctx, extra: 24),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40, height: 4,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.onSurface.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Icon(Icons.sort_rounded, size: 20, color: theme.colorScheme.primary),
                      const SizedBox(width: 8),
                      Text('ترتيب حسب', style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700,
                        color: theme.colorScheme.onSurface,
                      )),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8, runSpacing: 8,
                    children: _sortFields.map((f) {
                      final isSelected = selectedField == f.key;
                      return GestureDetector(
                        onTap: () {
                          setSheetState(() => selectedField = f.key);
                          ref.read(subscribersProvider.notifier)
                              .setSort(f.key, selectedDir);
                          setState(() => _currentPage = 0);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? theme.colorScheme.primary.withOpacity(0.12)
                                : theme.colorScheme.surfaceContainerHighest.withOpacity(0.5),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isSelected
                                  ? theme.colorScheme.primary.withOpacity(0.4)
                                  : Colors.transparent,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(f.icon, size: 15, color: isSelected
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.onSurface.withOpacity(0.5)),
                              const SizedBox(width: 6),
                              Text(f.label, style: TextStyle(
                                fontSize: 12,
                                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                                color: isSelected
                                    ? theme.colorScheme.primary
                                    : theme.colorScheme.onSurface.withOpacity(0.7),
                              )),
                              if (isSelected) ...[
                                const SizedBox(width: 4),
                                Icon(Icons.check_rounded, size: 14,
                                    color: theme.colorScheme.primary),
                              ],
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Icon(Icons.swap_vert_rounded, size: 20, color: theme.colorScheme.primary),
                      const SizedBox(width: 8),
                      Text('الاتجاه', style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700,
                        color: theme.colorScheme.onSurface,
                      )),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _DirectionBtn(
                          icon: Icons.arrow_upward_rounded,
                          label: 'تصاعدي',
                          selected: selectedDir == 'asc',
                          onTap: () {
                            setSheetState(() => selectedDir = 'asc');
                            ref.read(subscribersProvider.notifier)
                                .setSort(selectedField, 'asc');
                            setState(() => _currentPage = 0);
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _DirectionBtn(
                          icon: Icons.arrow_downward_rounded,
                          label: 'تنازلي',
                          selected: selectedDir == 'desc',
                          onTap: () {
                            setSheetState(() => selectedDir = 'desc');
                            ref.read(subscribersProvider.notifier)
                                .setSort(selectedField, 'desc');
                            setState(() => _currentPage = 0);
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showOnlineUserSheet(BuildContext context, SubscriberModel sub) {
    final theme = Theme.of(context);
    showModalBottomSheet(
      useSafeArea: true,
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.75,
          ),
          decoration: BoxDecoration(
            color: theme.scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),
              Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: theme.colorScheme.onSurface.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),

              // Header: avatar + name
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Container(
                      width: 44, height: 44,
                      decoration: BoxDecoration(
                        color: AppTheme.teal600.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Stack(
                        children: [
                          Center(
                            child: Text(
                              sub.firstname.isNotEmpty ? sub.firstname[0] : '?',
                              style: const TextStyle(
                                color: AppTheme.teal600,
                                fontWeight: FontWeight.w800,
                                fontSize: 18,
                              ),
                            ),
                          ),
                          Positioned(
                            bottom: 0, left: 0,
                            child: Container(
                              width: 12, height: 12,
                              decoration: BoxDecoration(
                                color: AppTheme.whatsappGreen,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: theme.scaffoldBackgroundColor,
                                  width: 2,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            sub.fullName.isNotEmpty ? sub.fullName : sub.username,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                            ),
                          ),
                          if (sub.fullName.isNotEmpty)
                            Text(
                              sub.username,
                              style: TextStyle(
                                fontSize: 12,
                                color: theme.colorScheme.onSurface.withOpacity(0.5),
                              ),
                            ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(ctx),
                      icon: Icon(Icons.close, color: theme.colorScheme.onSurface.withOpacity(0.4)),
                      style: IconButton.styleFrom(
                        backgroundColor: theme.colorScheme.onSurface.withOpacity(0.06),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Divider(height: 1, color: theme.colorScheme.onSurface.withOpacity(0.06)),

              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: EdgeInsets.fromLTRB(
                    20,
                    12,
                    20,
                    bottomSheetBottomInset(ctx, extra: 8),
                  ),
                  children: [
                    // Connection info section
                    _sheetSection(theme, 'معلومات الاتصال', Icons.wifi_rounded),
                    const SizedBox(height: 8),
                    _sheetInfoTile(
                      theme,
                      icon: Icons.lan_rounded,
                      label: 'عنوان IP',
                      value: sub.ipAddress ?? '—',
                      valueColor: AppTheme.teal600,
                      onTap: sub.ipAddress != null && sub.ipAddress!.isNotEmpty
                          ? () => launchUrl(
                              Uri.parse('http://${sub.ipAddress}'),
                              mode: LaunchMode.externalApplication,
                            )
                          : null,
                      trailing: sub.ipAddress != null && sub.ipAddress!.isNotEmpty
                          ? const Icon(Icons.open_in_new_rounded, size: 14, color: AppTheme.teal400)
                          : null,
                    ),
                    _sheetInfoTile(
                      theme,
                      icon: Icons.router_rounded,
                      label: 'MAC Address',
                      value: sub.macAddress ?? '—',
                      isLtr: true,
                      onLongPress: sub.macAddress != null
                          ? () {
                              Clipboard.setData(ClipboardData(text: sub.macAddress!));
                              if (context.mounted) {
                                AppSnackBar.success(context, 'تم نسخ MAC');
                              }
                            }
                          : null,
                    ),
                    _sheetInfoTile(
                      theme,
                      icon: Icons.timer_outlined,
                      label: 'مدة الجلسة',
                      value: SubscriberCard.formatDuration(sub.sessionTime),
                    ),

                    const SizedBox(height: 16),
                    _sheetSection(theme, 'الاستهلاك', Icons.data_usage_rounded),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: _sheetStatCard(
                            theme,
                            icon: Icons.download_rounded,
                            label: 'التحميل',
                            value: SubscriberCard.formatBytes(sub.downloadBytes),
                            color: AppTheme.teal600,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _sheetStatCard(
                            theme,
                            icon: Icons.upload_rounded,
                            label: 'الرفع',
                            value: SubscriberCard.formatBytes(sub.uploadBytes),
                            color: AppTheme.infoColor,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),
                    _sheetSection(theme, 'معلومات الاشتراك', Icons.inventory_2_rounded),
                    const SizedBox(height: 8),
                    if (sub.profileName != null && sub.profileName!.isNotEmpty)
                      _sheetInfoTile(
                        theme,
                        icon: Icons.card_membership_rounded,
                        label: 'الباقة',
                        value: sub.profileName!,
                        valueColor: theme.colorScheme.primary,
                      ),
                    if (sub.expiration != null && sub.expiration!.isNotEmpty)
                      _sheetInfoTile(
                        theme,
                        icon: Icons.event_rounded,
                        label: 'تاريخ الانتهاء',
                        value: AppHelpers.formatExpiration(sub.expiration),
                        isLtr: true,
                      ),
                    _sheetInfoTile(
                      theme,
                      icon: Icons.schedule_rounded,
                      label: 'الأيام المتبقية',
                      value: sub.isExpired
                          ? 'منتهي'
                          : '${sub.remainingDays ?? 0} يوم',
                      valueColor: sub.isExpired ? Colors.red : AppHelpers.getRemainingDaysColor(sub.remainingDays),
                    ),
                    if (sub.deviceVendor != null && sub.deviceVendor != 'unknown' && sub.deviceVendor!.isNotEmpty)
                      _sheetInfoTile(
                        theme,
                        icon: Icons.devices_rounded,
                        label: 'اسم الجهاز',
                        value: sub.deviceVendor!,
                      ),

                    // Disconnect button
                    if (sub.idx != null) ...[
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        height: 46,
                        child: ElevatedButton.icon(
                          onPressed: () async {
                            final confirm = await showDialog<bool>(
                              context: ctx,
                              builder: (dlg) => AlertDialog(
                                title: const Text('فصل المستخدم'),
                                content: Text('هل تريد فصل ${sub.fullName.isNotEmpty ? sub.fullName : sub.username}؟'),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(dlg, false),
                                    child: const Text('إلغاء'),
                                  ),
                                  ElevatedButton(
                                    onPressed: () => Navigator.pop(dlg, true),
                                    style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                                    child: const Text('فصل', style: TextStyle(color: Colors.white)),
                                  ),
                                ],
                              ),
                            );
                            if (confirm == true) {
                              if (ctx.mounted) Navigator.pop(ctx);
                              final ok = await ref.read(subscribersProvider.notifier).disconnectUser(sub.idx!);
                              if (context.mounted) {
                                if (ok) {
                                  AppSnackBar.success(context, 'تم فصل ${sub.fullName.isNotEmpty ? sub.fullName : sub.username}');
                                } else {
                                  AppSnackBar.error(context, 'فشل فصل المستخدم');
                                }
                              }
                            }
                          },
                          icon: const Icon(Icons.power_settings_new_rounded, size: 18),
                          label: const Text('فصل المستخدم', style: TextStyle(fontWeight: FontWeight.w700)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  static Widget _sheetSection(ThemeData theme, String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 16, color: theme.colorScheme.primary),
        const SizedBox(width: 6),
        Text(title, style: TextStyle(
          fontSize: 13, fontWeight: FontWeight.w700,
          color: theme.colorScheme.primary,
        )),
      ],
    );
  }

  static Widget _sheetInfoTile(
    ThemeData theme, {
    required IconData icon,
    required String label,
    required String value,
    Color? valueColor,
    bool isLtr = false,
    VoidCallback? onTap,
    VoidCallback? onLongPress,
    Widget? trailing,
  }) {
    final tile = Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 16, color: theme.colorScheme.onSurface.withOpacity(0.4)),
          const SizedBox(width: 10),
          SizedBox(
            width: 95,
            child: Text(label, style: TextStyle(
              fontSize: 12, fontWeight: FontWeight.w500,
              color: theme.colorScheme.onSurface.withOpacity(0.5),
            )),
          ),
          Expanded(
            child: Text(
              value,
              textDirection: isLtr ? TextDirection.ltr : null,
              style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600,
                color: valueColor ?? theme.colorScheme.onSurface.withOpacity(0.85),
              ),
            ),
          ),
          if (trailing != null) trailing,
        ],
      ),
    );
    if (onTap != null || onLongPress != null) {
      return GestureDetector(onTap: onTap, onLongPress: onLongPress, child: tile);
    }
    return tile;
  }

  static Widget _sheetStatCard(
    ThemeData theme, {
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.12)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(
                  fontSize: 10, fontWeight: FontWeight.w500,
                  color: theme.colorScheme.onSurface.withOpacity(0.5),
                )),
                const SizedBox(height: 2),
                Text(value, style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w700, color: color,
                )),
              ],
            ),
          ),
        ],
      ),
    );
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
    final canAccessManagers =
        ref.watch(authProvider).user?.canAccessManagers ?? false;
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

    // When the filter changes (dashboard KPI tap while on another tab,
    // or any setFilter call), scroll the chip bar so the newly selected
    // chip is visible. Scrollable.ensureVisible handles RTL correctly on
    // its own, unlike my earlier manual offset math which assumed LTR
    // and left the chip pinned outside the viewport.
    if (!_isSearchMode && _lastScrolledFilter != currentFilter) {
      _lastScrolledFilter = currentFilter;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final chipContext = _chipKeys[currentFilter]?.currentContext;
        if (chipContext == null) return;
        Scrollable.ensureVisible(
          chipContext,
          duration: const Duration(milliseconds: 300),
          alignment: 0.5, // center in the viewport
          alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
        );
      });
    }

    String _getCount(_FilterDef f) {
      switch (f.key) {
        case 'all': return '${state.allCount}';
        case 'active': return '${state.activeCount}';
        case 'online': return '${state.onlineCount}';
        case 'offline': return '${state.offlineCount}';
        case 'expired': return '${state.expiredCount}';
        case 'debtors': return '${state.debtorsCount}';
        case 'nearExpiry': return '${state.nearExpiryCount}';
        default: return '0';
      }
    }

    final currentSort = state.sortBy;
    final currentDirection = state.sortDirection;
    final sortLabel = _sortFields
        .firstWhere((f) => f.key == currentSort, orElse: () => _sortFields[0])
        .label;

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  textDirection: TextDirection.ltr,
                  textAlign: TextAlign.left,
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
              const SizedBox(width: 8),
              _SortButton(
                label: sortLabel,
                isAsc: currentDirection == 'asc',
                onTap: () => _showSortSheet(context, currentSort, currentDirection),
              ),
            ],
          ),
        ),

        // Manager filter (per-sub-manager dropdown) only for managers who
        // can actually see sub-managers. A sub-manager without that
        // permission has nothing to pick from.
        if (!_isSearchMode && canAccessManagers)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                Icon(Icons.admin_panel_settings_rounded, size: 16,
                    color: theme.colorScheme.onSurface.withOpacity(0.4)),
                const SizedBox(width: 6),
                Expanded(
                  child: Container(
                    height: 32,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      color: state.managerFilter != null
                          ? AppTheme.primary.withOpacity(0.08)
                          : theme.colorScheme.surfaceContainerLowest,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: state.managerFilter != null
                            ? AppTheme.primary.withOpacity(0.3)
                            : theme.colorScheme.onSurface.withOpacity(0.1),
                      ),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: state.managerFilter,
                        hint: Text('كل المدراء',
                            style: TextStyle(fontSize: 12,
                                color: theme.colorScheme.onSurface.withOpacity(0.5))),
                        isExpanded: true,
                        icon: Icon(Icons.keyboard_arrow_down, size: 18,
                            color: theme.colorScheme.onSurface.withOpacity(0.4)),
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                            color: theme.colorScheme.onSurface,
                            fontFamily: 'Cairo'),
                        items: [
                          DropdownMenuItem<String>(
                            value: null,
                            child: Text('كل المدراء', style: TextStyle(fontSize: 12,
                                color: theme.colorScheme.onSurface.withOpacity(0.5))),
                          ),
                          ...state.availableManagers.map((m) =>
                            DropdownMenuItem(value: m,
                              child: Text(m, style: const TextStyle(fontSize: 12))),
                          ),
                        ],
                        onChanged: (v) {
                          ref.read(subscribersProvider.notifier).setManagerFilter(v);
                          setState(() => _currentPage = 0);
                        },
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

        // Category chips (الكل / الفعالين / متصل / المنتهي / …). Previously
        // they were nested inside the canAccessManagers branch, so managers
        // without that permission — and, worse, the chip highlight when a
        // user tapped a dashboard KPI card — simply never rendered. Moved
        // out so every role sees them, and the tap from the dashboard now
        // visibly shifts the selected chip to the chosen filter. The chip
        // bar auto-scrolls (see _scrollSelectedChipIntoView below) so the
        // selected chip is visible even when it sits past the edge of the
        // viewport (nearExpiry/debtors commonly do).
        if (!_isSearchMode)
          SingleChildScrollView(
            controller: _chipScrollController,
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: _filters.map((f) {
                final count = _getCount(f);
                final key = _chipKeys.putIfAbsent(f.key, () => GlobalKey());
                return Padding(
                  key: key,
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

        // Debt summary banner — only on the Debtors tab. Reacts to the
        // manager-filter dropdown above: when the admin picks a specific
        // sub-manager, the total recomputes for that scope. Hidden while
        // searching because the count wouldn't line up with the filtered
        // search results.
        if (!_isSearchMode && currentFilter == 'debtors' && state.debtorsCount > 0)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 2),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFFF57F17).withOpacity(0.12),
                    const Color(0xFFF57F17).withOpacity(0.03),
                  ],
                  begin: Alignment.topRight,
                  end: Alignment.bottomLeft,
                ),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFF57F17).withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF57F17).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.credit_card_off_rounded,
                        size: 18, color: Color(0xFFF57F17)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'إجمالي الديون',
                          style: TextStyle(
                            fontSize: 11,
                            color: theme.colorScheme.onSurface.withOpacity(0.65),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: AlignmentDirectional.centerStart,
                          child: Text(
                            '${AppHelpers.formatMoney(state.totalDebtAmount)}'
                            ' من ${state.debtorsCount} مشترك',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFFE65100),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
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
                          final sub = displayList[index];
                          return SubscriberCard(
                            subscriber: sub,
                            showOnlineDetails: isOnlineFilter,
                            lastPayment: state.lastPayments[sub.username],
                            // The online filter used to disable onTap so
                            // the disconnect button could own the row.
                            // Per user request, mirror every other tab:
                            // tapping a row opens the subscriber details.
                            // The disconnect button still works as its
                            // own tap target inside the card.
                            onTap: () {
                              context.push(
                                '/subscriber/${sub.username}',
                                extra: sub,
                              );
                            },
                            onDisconnect: isOnlineFilter && sub.idx != null
                                ? () async {
                                    final confirm = await showDialog<bool>(
                                      context: context,
                                      builder: (ctx) => AlertDialog(
                                        title: const Text('فصل المستخدم'),
                                        content: Text('هل تريد فصل ${sub.fullName.isNotEmpty ? sub.fullName : sub.username}؟'),
                                        actions: [
                                          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
                                          ElevatedButton(
                                            onPressed: () => Navigator.pop(ctx, true),
                                            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                                            child: const Text('فصل'),
                                          ),
                                        ],
                                      ),
                                    );
                                    if (confirm == true) {
                                      final ok = await ref.read(subscribersProvider.notifier).disconnectUser(sub.idx!);
                                      if (context.mounted) {
                                        if (ok) {
                                          AppSnackBar.success(context, 'تم فصل ${sub.fullName.isNotEmpty ? sub.fullName : sub.username}');
                                        } else {
                                          AppSnackBar.error(context, 'فشل فصل المستخدم');
                                        }
                                      }
                                    }
                                  }
                                : null,
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

class _SortFieldDef {
  final String key;
  final String label;
  final IconData icon;
  const _SortFieldDef(this.key, this.label, this.icon);
}

class _SortButton extends StatelessWidget {
  final String label;
  final bool isAsc;
  final VoidCallback onTap;
  const _SortButton({required this.label, required this.isAsc, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: theme.colorScheme.primary.withOpacity(0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: theme.colorScheme.primary.withOpacity(0.2)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.sort_rounded, size: 18, color: theme.colorScheme.primary),
            const SizedBox(width: 4),
            Icon(
              isAsc ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
              size: 14, color: theme.colorScheme.primary,
            ),
          ],
        ),
      ),
    );
  }
}

class _DirectionBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _DirectionBtn({
    required this.icon, required this.label,
    required this.selected, required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: selected
              ? theme.colorScheme.primary.withOpacity(0.12)
              : theme.colorScheme.surfaceContainerHighest.withOpacity(0.5),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected
                ? theme.colorScheme.primary.withOpacity(0.4)
                : Colors.transparent,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: selected
                ? theme.colorScheme.primary
                : theme.colorScheme.onSurface.withOpacity(0.5)),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(
              fontSize: 13,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurface.withOpacity(0.7),
            )),
          ],
        ),
      ),
    );
  }
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
          // Clearer selected styling so the chip for the current category
          // stands out obviously when the user lands here from a dashboard
          // KPI tap or changes filter via the bar.
          color: selected
              ? activeColor.withOpacity(0.18)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected
                ? activeColor
                : theme.colorScheme.onSurface.withOpacity(0.1),
            width: selected ? 1.5 : 1,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: activeColor.withOpacity(0.25),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
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
                fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
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
