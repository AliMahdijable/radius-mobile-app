import 'package:flutter/material.dart';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dashboard_screen.dart';
import 'subscribers/subscribers_screen.dart';
import 'add_subscriber_screen.dart';
import 'managers_screen.dart';
import 'reports_screen.dart';
import 'settings_screen.dart';
import '../providers/whatsapp_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/dashboard_provider.dart';
import '../providers/subscribers_provider.dart';
import '../providers/messages_provider.dart';
import '../providers/reports_provider.dart';
import '../core/services/storage_service.dart';
import '../widgets/status_badge.dart';
import '../widgets/app_snackbar.dart';
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
  bool _alertsEnabled = true;
  bool _alertsDismissed = false;
  String? _lastBroadcastEvent;

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
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      Future.microtask(() {
        if (!mounted) return;
        ref.read(dashboardProvider.notifier).refreshCountsOnly();
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

  void _showAlertsSheet() {
    final dash = ref.read(dashboardProvider);
    showModalBottomSheet(
      useSafeArea: true,
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final theme = Theme.of(ctx);
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
                            top: Radius.circular(24)),
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.orange.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(
                                    Icons.notifications_active,
                                    color: Colors.orange,
                                    size: 22),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'تنبيهات الاشتراك (${dash.totalAlerts})',
                                      style: theme.textTheme.titleMedium
                                          ?.copyWith(fontWeight: FontWeight.w700),
                                    ),
                                    Text(
                                      'قريب الانتهاء · انتهى اليوم',
                                      style: theme.textTheme.bodySmall?.copyWith(
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
                                      !_alertsEnabled, setSheetState),
                                  child: Row(
                                    children: [
                                      Switch(
                                        value: _alertsEnabled,
                                        onChanged: (v) => _toggleAlerts(
                                            v, setSheetState),
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        _alertsEnabled
                                            ? 'التنبيهات مفعلة'
                                            : 'التنبيهات معطلة',
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
                                  icon: const Icon(Icons.clear_all,
                                      size: 18),
                                  label: const Text('مسح الكل',
                                      style: TextStyle(fontSize: 12)),
                                  style: TextButton.styleFrom(
                                    foregroundColor: theme
                                        .colorScheme.onSurface
                                        .withValues(alpha: 0.5),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8),
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
                      child: !_alertsEnabled
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(40),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.notifications_off_outlined,
                                        size: 48,
                                        color: theme.colorScheme.onSurface
                                            .withValues(alpha: 0.3)),
                                    const SizedBox(height: 12),
                                    Text('التنبيهات معطلة',
                                        style: theme.textTheme.titleSmall
                                            ?.copyWith(
                                              color: theme
                                                  .colorScheme.onSurface
                                                  .withValues(alpha: 0.5),
                                            )),
                                    const SizedBox(height: 4),
                                    Text(
                                        'تنبيهات قرب انتهاء الاشتراك وانتهائه اليوم',
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(
                                              color: theme
                                                  .colorScheme.onSurface
                                                  .withValues(alpha: 0.3),
                                            )),
                                  ],
                                ),
                              ),
                            )
                          : ListView(
                              controller: scrollController,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16),
                              children: [
                                if (dash
                                    .expiredTodayList.isNotEmpty) ...[
                                  _AlertSectionHeader(
                                    title: 'انتهى اليوم',
                                    count: dash.expiredTodayCount,
                                    color: Colors.red,
                                    icon: Icons.error_outline,
                                  ),
                                  ...dash.expiredTodayList
                                      .map((sub) => _AlertItem(
                                            name:
                                                '${sub['firstname'] ?? ''} ${sub['lastname'] ?? ''}'
                                                    .trim(),
                                            username:
                                                sub['username']
                                                        ?.toString() ??
                                                    '',
                                            detail:
                                                'انتهى الاشتراك اليوم',
                                            color: Colors.red,
                                            icon:
                                                Icons.timer_off_rounded,
                                          )),
                                  const SizedBox(height: 12),
                                ],
                                if (dash
                                    .nearExpiryList.isNotEmpty) ...[
                                  _AlertSectionHeader(
                                    title: 'قريب الانتهاء',
                                    count: dash.nearExpiryCount,
                                    color: Colors.orange,
                                    icon: Icons.warning_amber_rounded,
                                  ),
                                  ...dash.nearExpiryList.map((sub) {
                                    final detail = _formatRemaining(
                                        sub['expiration']?.toString());
                                    return _AlertItem(
                                      name:
                                          '${sub['firstname'] ?? ''} ${sub['lastname'] ?? ''}'
                                              .trim(),
                                      username:
                                          sub['username']
                                                  ?.toString() ??
                                              '',
                                      detail: detail,
                                      color: Colors.orange,
                                      icon: Icons.schedule,
                                    );
                                  }),
                                  const SizedBox(height: 12),
                                ],
                                if (dash.totalAlerts == 0)
                                  Padding(
                                    padding: const EdgeInsets.all(40),
                                    child: Column(
                                      children: [
                                        Icon(
                                            Icons.check_circle_outline,
                                            size: 48,
                                            color: Colors.green
                                                .withValues(alpha: 0.5)),
                                        const SizedBox(height: 12),
                                        Text('لا توجد تنبيهات',
                                            style: theme
                                                .textTheme.titleSmall
                                                ?.copyWith(
                                              color: theme.colorScheme
                                                  .onSurface
                                                  .withValues(
                                                      alpha: 0.5),
                                            )),
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
  }

  @override
  Widget build(BuildContext context) {
    final wa = ref.watch(whatsappProvider);
    final authState = ref.watch(authProvider);
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
    final showAlertBadge =
        _alertsEnabled && !_alertsDismissed && dash.totalAlerts > 0;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (_currentIndex != 0) {
          setState(() => _currentIndex = 0);
          return;
        }
        final shouldExit = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('الخروج من التطبيق'),
            content: const Text('هل تريد الخروج؟'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('لا'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                child: const Text('خروج', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        );
        if (shouldExit == true) {
          // Clean exit: close all resources and exit cleanly
          WidgetsBinding.instance.removeObserver(this);
          Future.delayed(const Duration(milliseconds: 200), () {
            SystemNavigator.pop();
          });
        }
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
                      label: Text('${dash.totalAlerts}',
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
          const AddSubscriberScreen(),
          const ReportsScreen(),
          const SettingsScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (i) {
          if (i != 0) _alertsDismissed = false;
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
            ref.invalidate(reportsProvider);
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
    ),
    );
  }
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
