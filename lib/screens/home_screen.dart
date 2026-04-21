import 'package:flutter/material.dart';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_app_badger/flutter_app_badger.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dashboard_screen.dart';
import 'subscribers/subscribers_screen.dart';
import '../widgets/add_subscriber_sheet.dart';
import '../core/utils/bottom_sheet_utils.dart';
import 'managers_screen.dart';
import 'reports_screen.dart';
import 'settings_screen.dart';
import '../providers/whatsapp_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/app_notifications_provider.dart';
import '../providers/dashboard_provider.dart';
import '../providers/subscribers_provider.dart';
import '../providers/messages_provider.dart';
import '../providers/reports_provider.dart';
import '../core/services/storage_service.dart';
import '../core/services/fcm_service.dart';
import '../models/app_notification_model.dart';
import '../widgets/status_badge.dart';
import '../widgets/app_snackbar.dart';
import '../widgets/subscriber_search_sheet.dart';
import '../core/theme/app_theme.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

String _formatRemaining(String? expiration) {
  if (expiration == null || expiration.isEmpty) return 'ينتهي قريباً';
  try {
    final s = expiration.trim();
    DateTime? exp;
    if (s.contains('T') || s.contains('+')) {
      exp = DateTime.tryParse(s);
    } else {
      exp = DateTime.tryParse('${s.replaceAll(' ', 'T')}+03:00');
    }
    if (exp == null) return 'ينتهي قريباً';
    final diff = exp.difference(DateTime.now());
    if (diff.isNegative) return 'انتهى';
    final days = diff.inDays;
    final hours = diff.inHours % 24;
    final minutes = diff.inMinutes % 60;
    if (days > 0) return 'متبقي $days يوم ${hours > 0 ? 'و $hours ساعة' : ''}';
    if (hours > 0) return 'متبقي $hours ساعة ${minutes > 0 ? 'و $minutes دقيقة' : ''}';
    if (minutes > 0) return 'متبقي $minutes دقيقة';
    return 'ينتهي الآن';
  } catch (_) {
    return 'ينتهي قريباً';
  }
}

class _HomeScreenState extends ConsumerState<HomeScreen> with WidgetsBindingObserver {
  int _currentIndex = 0;
  DateTime? _lastBackPress;
  bool _alertsEnabled = true;
  bool _alertsDismissed = false;
  String? _lastBroadcastEvent;
  int _lastBadgeCount = -1;

  Future<void> _syncAppIconBadge(int count) async {
    if (count == _lastBadgeCount) return;
    _lastBadgeCount = count;
    try {
      final supported = await FlutterAppBadger.isAppBadgeSupported();
      if (!supported) return;
      if (count > 0) {
        FlutterAppBadger.updateBadgeCount(count);
      } else {
        FlutterAppBadger.removeBadge();
      }
    } catch (_) { /* launcher may not support — ignore */ }
  }

  final _titles = const [
    'لوحة المعلومات',
    'المشتركين',
    'إضافة مشترك',
    'التقارير',
    'الإعدادات',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadAlertsPref();
    Future.microtask(() {
      ref.read(appNotificationsProvider.notifier).loadNotifications();
    });
    FcmService.pendingSubscriberSearch.addListener(_onPendingSubscriberSearch);
    if (FcmService.pendingSubscriberSearch.value != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _onPendingSubscriberSearch();
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    FcmService.pendingSubscriberSearch.removeListener(_onPendingSubscriberSearch);
    super.dispose();
  }

  void _onPendingSubscriberSearch() {
    if (!mounted) return;
    if (FcmService.pendingSubscriberSearch.value == null) return;
    if (_currentIndex != 1) {
      setState(() => _currentIndex = 1);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      Future.microtask(() {
        if (!mounted) return;
        ref.read(dashboardProvider.notifier).refreshCountsOnly();
        ref.read(appNotificationsProvider.notifier).loadNotifications(silent: true);
        final subs = ref.read(subscribersProvider);
        if (subs.subscribers.isNotEmpty && !subs.isLoading) {
          ref.read(subscribersProvider.notifier).loadSubscribers();
        }
      });
    }
  }

  Future<void> _loadAlertsPref() async {
    final storage = ref.read(storageServiceProvider);
    final enabled = await storage.getAlertsEnabled();
    if (mounted) setState(() => _alertsEnabled = enabled);
  }

  void _toggleAlerts(bool enabled, void Function(void Function()) rebuildSheet) {
    _alertsEnabled = enabled;
    rebuildSheet(() {});
    setState(() {});
    ref.read(storageServiceProvider).setAlertsEnabled(enabled);
  }

  void _clearAlerts(BuildContext sheetCtx) {
    _alertsDismissed = true;
    setState(() {});
    Navigator.pop(sheetCtx);
  }

  void _navigateToSubscribers(String filter) {
    setState(() => _currentIndex = 1);
  }

  Future<void> _openAddSubscriberSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) {
        // bottomSheetBottomInset already includes MediaQuery.viewInsets.bottom
        // (i.e. the keyboard height). Previously we added viewInsets.bottom a
        // second time on top of it, which doubled the keyboard offset and
        // squeezed the form into a tiny strip when the user started typing.
        return Padding(
          padding: EdgeInsets.only(
            bottom: bottomSheetBottomInset(sheetCtx, extra: 0),
            top: 10,
            left: 16,
            right: 16,
          ),
          child: SingleChildScrollView(
            child: const AddSubscriberSheet(),
          ),
        );
      },
    );
  }

  void _showAlertsSheet() {
    final dash = ref.read(dashboardProvider);
    ref.read(appNotificationsProvider.notifier).markAllSeen();
    showModalBottomSheet(
      useSafeArea: true,
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return Consumer(
          builder: (ctx, ref, _) {
            final appNotifications = ref.watch(appNotificationsProvider);
            final appNotificationCount = appNotifications.notifications.length;
            return StatefulBuilder(
              builder: (ctx, setSheetState) {
                final theme = Theme.of(ctx);
                final showSubscriptionAlerts = _alertsEnabled;
                final hasAppNotifications = appNotificationCount > 0;

                return DraggableScrollableSheet(
                  initialChildSize: 0.6,
                  maxChildSize: 0.9,
                  minChildSize: 0.3,
                  expand: false,
                  builder: (_, scrollController) {
                    return Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
                          decoration: BoxDecoration(
                            color: theme.cardTheme.color ?? Colors.white,
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(24),
                            ),
                          ),
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: AppTheme.primary.withValues(
                                        alpha: 0.1,
                                      ),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: const Icon(
                                      Icons.notifications_active,
                                      color: AppTheme.primary,
                                      size: 22,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'الإشعارات',
                                          style: theme.textTheme.titleMedium
                                              ?.copyWith(
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        Text(
                                          'تطبيق $appNotificationCount · اشتراك ${dash.totalAlerts}',
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(
                                            color: theme.colorScheme.onSurface
                                                .withValues(alpha: 0.5),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  IconButton(
                                    icon: const Icon(Icons.close, size: 20),
                                    onPressed: () => Navigator.pop(ctx),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    child: GestureDetector(
                                      onTap: () => _toggleAlerts(
                                        !_alertsEnabled,
                                        setSheetState,
                                      ),
                                      child: Row(
                                        children: [
                                          Switch(
                                            value: _alertsEnabled,
                                            onChanged: (v) => _toggleAlerts(
                                              v,
                                              setSheetState,
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            _alertsEnabled
                                                ? 'تنبيهات الاشتراك مفعلة'
                                                : 'تنبيهات الاشتراك معطلة',
                                            style: theme.textTheme.bodySmall
                                                ?.copyWith(
                                              fontWeight: FontWeight.w600,
                                              color: _alertsEnabled
                                                  ? Colors.orange
                                                  : theme.colorScheme.onSurface
                                                      .withValues(alpha: 0.4),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  if (dash.totalAlerts > 0)
                                    TextButton.icon(
                                      onPressed: () => _clearAlerts(ctx),
                                      icon: const Icon(
                                        Icons.clear_all,
                                        size: 18,
                                      ),
                                      label: const Text(
                                        'مسح تنبيهات الاشتراك',
                                        style: TextStyle(fontSize: 12),
                                      ),
                                      style: TextButton.styleFrom(
                                        foregroundColor: theme
                                            .colorScheme.onSurface
                                            .withValues(alpha: 0.5),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                        ),
                                        visualDensity: VisualDensity.compact,
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 4),
                            ],
                          ),
                        ),
                        Expanded(
                          child: ListView(
                            controller: scrollController,
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            children: [
                              if (hasAppNotifications) ...[
                                _AlertSectionHeader(
                                  title: 'إشعارات التطبيق',
                                  count: appNotificationCount,
                                  color: AppTheme.primary,
                                  icon: Icons.notifications_rounded,
                                ),
                                ...appNotifications.notifications.map(
                                  (notification) => _AppNotificationItem(
                                    notification: notification,
                                  ),
                                ),
                                const SizedBox(height: 12),
                              ],
                              if (showSubscriptionAlerts &&
                                  dash.expiredTodayList.isNotEmpty) ...[
                                _AlertSectionHeader(
                                  title: 'انتهى اليوم',
                                  count: dash.expiredTodayCount,
                                  color: Colors.red,
                                  icon: Icons.error_outline,
                                ),
                                ...dash.expiredTodayList.map(
                                  (sub) => _AlertItem(
                                    name:
                                        '${sub['firstname'] ?? ''} ${sub['lastname'] ?? ''}'
                                            .trim(),
                                    username:
                                        sub['username']?.toString() ?? '',
                                    detail: 'انتهى الاشتراك اليوم',
                                    color: Colors.red,
                                    icon: Icons.timer_off_rounded,
                                  ),
                                ),
                                const SizedBox(height: 12),
                              ],
                              if (showSubscriptionAlerts &&
                                  dash.nearExpiryList.isNotEmpty) ...[
                                _AlertSectionHeader(
                                  title: 'قريب الانتهاء',
                                  count: dash.nearExpiryCount,
                                  color: Colors.orange,
                                  icon: Icons.warning_amber_rounded,
                                ),
                                ...dash.nearExpiryList.map((sub) {
                                  final detail = _formatRemaining(
                                    sub['expiration']?.toString(),
                                  );
                                  return _AlertItem(
                                    name:
                                        '${sub['firstname'] ?? ''} ${sub['lastname'] ?? ''}'
                                            .trim(),
                                    username:
                                        sub['username']?.toString() ?? '',
                                    detail: detail,
                                    color: Colors.orange,
                                    icon: Icons.schedule,
                                  );
                                }),
                                const SizedBox(height: 12),
                              ],
                              if (!hasAppNotifications &&
                                  !showSubscriptionAlerts)
                                Padding(
                                  padding: const EdgeInsets.all(40),
                                  child: Column(
                                    children: [
                                      Icon(
                                        Icons.notifications_off_outlined,
                                        size: 48,
                                        color: theme.colorScheme.onSurface
                                            .withValues(alpha: 0.3),
                                      ),
                                      const SizedBox(height: 12),
                                      Text(
                                        'تنبيهات الاشتراك معطلة',
                                        style: theme.textTheme.titleSmall
                                            ?.copyWith(
                                          color: theme.colorScheme.onSurface
                                              .withValues(alpha: 0.5),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              if (!hasAppNotifications &&
                                  showSubscriptionAlerts &&
                                  dash.totalAlerts == 0)
                                Padding(
                                  padding: const EdgeInsets.all(40),
                                  child: Column(
                                    children: [
                                      Icon(
                                        Icons.check_circle_outline,
                                        size: 48,
                                        color: Colors.green.withValues(
                                          alpha: 0.5,
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      Text(
                                        'لا توجد إشعارات جديدة',
                                        style: theme.textTheme.titleSmall
                                            ?.copyWith(
                                          color: theme.colorScheme.onSurface
                                              .withValues(alpha: 0.5),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              const SizedBox(height: 20),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final wa = ref.watch(whatsappProvider);
    final authState = ref.watch(authProvider);
    final appNotifications = ref.watch(appNotificationsProvider);
    final dash = ref.watch(dashboardProvider);
    final msgState = ref.watch(messagesProvider);
    final theme = Theme.of(context);

    final broadcast = msgState.broadcast;
    if (broadcast != null && broadcast.event.isNotEmpty && broadcast.event != _lastBroadcastEvent) {
      _lastBroadcastEvent = broadcast.event;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        switch (broadcast.event) {
          case 'start':
            AppSnackBar.info(context, 'بدأ البث',
                detail: 'إرسال إلى ${broadcast.total} مشترك');
            break;
          case 'complete':
            AppSnackBar.success(context, 'اكتمل البث',
                detail: 'مرسلة: ${broadcast.sent} | فاشلة: ${broadcast.failed}');
            break;
        }
      });
    }

    final managerName = authState.user?.username ?? '';
    final totalBellCount =
        appNotifications.unreadCount +
        (_alertsEnabled && !_alertsDismissed ? dash.totalAlerts : 0);
    final showAlertBadge = totalBellCount > 0;

    // Keep the launcher-icon badge in sync with the in-app bell count.
    // fire-and-forget: the plugin silently no-ops on launchers that
    // don't support numeric badges (stock AOSP, some Chinese ROMs).
    _syncAppIconBadge(totalBellCount);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (_currentIndex != 0) {
          setState(() => _currentIndex = 0);
          return;
        }
        // نمط "اضغط مرة أخرى للخروج" — ضغطتان خلال ثانيتين للخروج
        final now = DateTime.now();
        final last = _lastBackPress;
        if (last == null ||
            now.difference(last) > const Duration(seconds: 2)) {
          _lastBackPress = now;
          if (mounted) {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('اضغط مرة أخرى للخروج'),
                duration: Duration(milliseconds: 1800),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
          return;
        }
        // ضغطة ثانية خلال النافذة → خروج نظيف
        WidgetsBinding.instance.removeObserver(this);
        Future.delayed(const Duration(milliseconds: 150), () {
          SystemNavigator.pop();
        });
      },
      child: Scaffold(
      appBar: AppBar(
        title: Text(_titles[_currentIndex]),
        leading: Padding(
          padding: const EdgeInsets.all(8),
          child: Container(
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            padding: const EdgeInsets.all(4),
            child: Image.asset(
              'assets/images/myservice_raduis.png',
              fit: BoxFit.contain,
            ),
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: IconButton(
              onPressed: _showAlertsSheet,
              icon: showAlertBadge
                  ? Badge(
                      label: Text('$totalBellCount',
                          style: const TextStyle(fontSize: 9)),
                      child: Icon(Icons.notifications_outlined,
                          color: Colors.orange.shade700, size: 22),
                    )
                  : Icon(Icons.notifications_none,
                      color: theme.colorScheme.onSurface
                          .withValues(alpha: 0.4),
                      size: 22),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 16),
            child: Row(
              children: [
                ConnectionStatusDot(
                    isConnected: wa.status.connected, size: 8),
                const SizedBox(width: 6),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      managerName.isNotEmpty ? managerName : '—',
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.onSurface
                            .withValues(alpha: 0.7),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.chat_rounded,
                          size: 10,
                          color: wa.status.connected
                              ? AppTheme.whatsappGreen
                              : Colors.grey,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          wa.status.connected
                              ? 'واتساب متصل'
                              : 'واتساب غير متصل',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                            color: wa.status.connected
                                ? AppTheme.whatsappGreen
                                : Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(width: 8),
              ],
            ),
          ),
        ],
      ),
      body: IndexedStack(
        index: _currentIndex,
        children: [
          DashboardScreen(onCardTapped: _navigateToSubscribers),
          const SubscribersScreen(),
          const SizedBox.shrink(), // الفهرس 2 مخصص كـ "إضافة" عبر bottom sheet
          const ReportsScreen(),
          const SettingsScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (i) {
          if (i != 0) _alertsDismissed = false;
          if (i == 2) {
            // بدل التنقل لصفحة "إضافة"، نفتح bottom sheet مثل مودل التعديل
            _openAddSubscriberSheet();
            return;
          }
          if (i == 0) {
            final auth = ref.read(authProvider);
            if (auth.user != null) {
              ref.read(dashboardProvider.notifier).loadDashboard(
                adminId: auth.user!.id,
                token: auth.user!.token,
              );
            }
          }
          if (i == 3) {
            ref.read(reportsProvider.notifier).triggerRefresh();
          }
          setState(() => _currentIndex = i);
        },
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'الرئيسية',
          ),
          const NavigationDestination(
            icon: Icon(Icons.people_outline),
            selectedIcon: Icon(Icons.people),
            label: 'المشتركين',
          ),
          NavigationDestination(
            icon: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppTheme.primary,
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.person_add_alt_1,
                  color: Colors.white, size: 22),
            ),
            selectedIcon: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppTheme.teal800,
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.person_add_alt_1,
                  color: Colors.white, size: 22),
            ),
            label: 'إضافة',
          ),
          const NavigationDestination(
            icon: Icon(Icons.assessment_outlined),
            selectedIcon: Icon(Icons.assessment),
            label: 'التقارير',
          ),
          const NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'الإعدادات',
          ),
        ],
      ),
      floatingActionButton: _currentIndex == 0
          ? FloatingActionButton(
              heroTag: 'dashboard_search',
              backgroundColor: theme.colorScheme.primary,
              onPressed: () => showSubscriberSearchSheet(context),
              tooltip: 'بحث عن مشترك',
              child: const Icon(Icons.search_rounded, color: Colors.white),
            )
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.startFloat,
    ),
    );
  }
}

String _formatNotificationTime(String? value) {
  if (value == null || value.isEmpty) return 'الآن';
  final parsed = DateTime.tryParse(value);
  if (parsed == null) return 'الآن';
  final now = DateTime.now().toUtc();
  final diff = now.difference(parsed.toUtc());
  if (diff.inMinutes < 1) return 'الآن';
  if (diff.inMinutes < 60) return 'منذ ${diff.inMinutes} دقيقة';
  if (diff.inHours < 24) return 'منذ ${diff.inHours} ساعة';
  if (diff.inDays < 7) return 'منذ ${diff.inDays} يوم';
  return '${parsed.year}/${parsed.month.toString().padLeft(2, '0')}/${parsed.day.toString().padLeft(2, '0')}';
}

class _AlertSectionHeader extends StatelessWidget {
  final String title;
  final int count;
  final Color color;
  final IconData icon;

  const _AlertSectionHeader({
    required this.title,
    required this.count,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 8),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 6),
          Text(
            '$title ($count)',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
          ),
        ],
      ),
    );
  }
}

class _AppNotificationItem extends StatelessWidget {
  final AppNotificationModel notification;

  const _AppNotificationItem({required this.notification});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = switch (notification.type) {
      'cash_deposit' => AppTheme.successColor,
      'loan_deposit' => Colors.orange,
      'withdraw_balance' => Colors.red,
      'pay_debt' => AppTheme.infoColor,
      'add_points' => Colors.purple,
      _ => AppTheme.primary,
    };
    final icon = switch (notification.type) {
      'cash_deposit' => Icons.account_balance_wallet_rounded,
      'loan_deposit' => Icons.request_quote_rounded,
      'withdraw_balance' => Icons.remove_circle_outline_rounded,
      'pay_debt' => Icons.paid_rounded,
      'add_points' => Icons.stars_rounded,
      _ => Icons.notifications_rounded,
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 5),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: accent.withValues(alpha: 0.12)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(7),
            ),
            child: Icon(icon, color: accent, size: 13),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        notification.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _formatNotificationTime(notification.createdAt),
                      style: TextStyle(
                        fontSize: 9.5,
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.45),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  notification.body,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.35,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.70),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AlertItem extends StatelessWidget {
  final String name;
  final String username;
  final String detail;
  final Color color;
  final IconData icon;

  const _AlertItem({
    required this.name,
    required this.username,
    required this.detail,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.15)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 16),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name.isNotEmpty ? name : username,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                Text(
                  detail,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w600,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          Text(
            username,
            style: theme.textTheme.bodySmall?.copyWith(
              color:
                  theme.colorScheme.onSurface.withValues(alpha: 0.4),
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }
}
