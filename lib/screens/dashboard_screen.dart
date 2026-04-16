import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/dashboard_provider.dart';
import '../providers/whatsapp_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/subscribers_provider.dart';
import '../widgets/stat_card.dart';
import '../widgets/status_badge.dart';
import '../widgets/loading_overlay.dart';
import '../core/utils/helpers.dart';
import '../core/theme/app_theme.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  final void Function(String filter)? onCardTapped;

  const DashboardScreen({super.key, this.onCardTapped});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  bool _hasTriedLoad = false;
  Timer? _autoRefresh;

  @override
  void initState() {
    super.initState();
    _autoRefresh = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) _refresh();
    });
  }

  @override
  void dispose() {
    _autoRefresh?.cancel();
    super.dispose();
  }

  void _tryLoad() {
    final user = ref.read(authProvider).user;
    if (user == null) return;
    _hasTriedLoad = true;
    ref
        .read(dashboardProvider.notifier)
        .loadDashboard(adminId: user.id, token: user.token);
    ref.read(whatsappProvider.notifier).fetchStatus();
    ref.read(subscribersProvider.notifier).loadPackages();
  }

  Future<void> _refresh() async {
    final user = ref.read(authProvider).user;
    if (user == null) return;
    await ref
        .read(dashboardProvider.notifier)
        .loadDashboard(adminId: user.id, token: user.token);
    if (!mounted) return;
    await ref.read(whatsappProvider.notifier).fetchStatus();
  }

  static String _formatDebt(double amount) {
    if (amount >= 1000000) {
      return '${(amount / 1000000).toStringAsFixed(1)}M';
    } else if (amount >= 1000) {
      return '${(amount / 1000).toStringAsFixed(0)}K';
    }
    return amount.toStringAsFixed(0);
  }

  void _onCardTap(String filter) {
    ref.read(subscribersProvider.notifier).setFilter(filter);
    widget.onCardTapped?.call(filter);
  }

  void _ensureSubscribersLoaded() {
    final subsState = ref.read(subscribersProvider);
    if (subsState.subscribers.isEmpty && !subsState.isLoading) {
      ref.read(subscribersProvider.notifier).loadSubscribers();
    }
  }

  @override
  Widget build(BuildContext context) {
    final dash = ref.watch(dashboardProvider);
    final wa = ref.watch(whatsappProvider);
    final authState = ref.watch(authProvider);
    final theme = Theme.of(context);

    if (authState.status == AuthStatus.authenticated &&
        !_hasTriedLoad &&
        !dash.isLoading) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _tryLoad();
      });
    }

    return RefreshIndicator(
      onRefresh: _refresh,
      child: dash.isLoading && dash.totalSubscribers == 0
          ? const ShimmerList(itemCount: 4)
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
              children: [
                if (dash.error != null)
                  Container(
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.error_outline,
                            color: Colors.red.shade600, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(dash.error!,
                              style: TextStyle(
                                  color: Colors.red.shade700, fontSize: 12)),
                        ),
                        IconButton(
                          icon: const Icon(Icons.refresh, size: 20),
                          onPressed: _refresh,
                        ),
                      ],
                    ),
                  ),

                // Subscribers Ring Card
                _SubscribersRingCard(
                  total: dash.totalSubscribers,
                  active: dash.activeSubscribers,
                  expired: dash.expiredSubscribers,
                  online: dash.onlineCount,
                  offline: dash.offlineCount < 0 ? 0 : dash.offlineCount,
                  onTapActive: () { _ensureSubscribersLoaded(); _onCardTap('active'); },
                  onTapExpired: () { _ensureSubscribersLoaded(); _onCardTap('expired'); },
                  onTapOnline: () { _ensureSubscribersLoaded(); _onCardTap('online'); },
                  onTapOffline: () { _ensureSubscribersLoaded(); _onCardTap('offline'); },
                  onTapTotal: () { _ensureSubscribersLoaded(); _onCardTap('all'); },
                  onTapDebtors: () { _ensureSubscribersLoaded(); _onCardTap('debtors'); },
                  onTapNearExpiry: () { _ensureSubscribersLoaded(); _onCardTap('nearExpiry'); },
                  debtors: dash.debtors,
                  totalDebt: dash.totalDebt,
                  nearExpiry: dash.nearExpiryCount,
                ),
                const SizedBox(height: 12),

                Row(
                  children: [
                    if (dash.managerBalance.isNotEmpty && dash.managerBalance != '0')
                      Expanded(
                        child: _BalancePointsCard(
                          balance: dash.managerBalance,
                          points: dash.managerPoints,
                        ),
                      ),
                    if (dash.managerBalance.isNotEmpty && dash.managerBalance != '0' &&
                        (dash.debtors > 0 || dash.totalDebt > 0))
                      const SizedBox(width: 10),
                    if (dash.debtors > 0 || dash.totalDebt > 0)
                      Expanded(
                        child: _DebtCard(
                          debtors: dash.debtors,
                          totalDebt: dash.totalDebt,
                          onTap: () { _ensureSubscribersLoaded(); _onCardTap('debtors'); },
                        ),
                      ),
                  ],
                ),

                const SizedBox(height: 14),

                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: theme.cardTheme.color,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: AppTheme.infoColor.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.today_rounded,
                                color: AppTheme.infoColor, size: 20),
                          ),
                          const SizedBox(width: 10),
                          Text('نشاط اليوم',
                              style: theme.textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w700)),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: _TodayStatItem(
                              label: 'تفعيلات',
                              value: '${dash.todayActivations}',
                              icon: Icons.add_circle_outline,
                              color: AppTheme.successColor,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _TodayStatItem(
                              label: 'تمديدات',
                              value: '${dash.todayExtensions}',
                              icon: Icons.autorenew_rounded,
                              color: AppTheme.infoColor,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                if (dash.recentActivities.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Text('آخر العمليات',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 10),
                  ...dash.recentActivities.take(8).map((activity) {
                    final actionType =
                        activity['action_type']?.toString() ?? '';
                    final isActivation = actionType.contains('ACTIVATE');
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: theme.cardTheme.color,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: (isActivation
                                      ? AppTheme.successColor
                                      : AppTheme.infoColor)
                                  .withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              isActivation
                                  ? Icons.person_add_alt_1
                                  : Icons.autorenew,
                              size: 18,
                              color: isActivation
                                  ? AppTheme.successColor
                                  : AppTheme.infoColor,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  activity['target_name']?.toString() ?? '—',
                                  style: theme.textTheme.bodyMedium
                                      ?.copyWith(fontWeight: FontWeight.w600),
                                ),
                                Text(
                                  isActivation ? 'تفعيل' : 'تمديد',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurface
                                        .withValues(alpha: 0.5),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            AppHelpers.formatRelative(
                                activity['created_at']?.toString()),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: 0.4),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ],
            ),
    );
  }
}

// ---------------------------------------------------------------------------
//  Subscribers Ring Card
// ---------------------------------------------------------------------------

class _SubscribersRingCard extends StatelessWidget {
  final int total, active, expired, online, offline, debtors, nearExpiry;
  final double totalDebt;
  final VoidCallback onTapActive, onTapExpired, onTapOnline, onTapOffline,
      onTapTotal, onTapDebtors, onTapNearExpiry;

  const _SubscribersRingCard({
    required this.total,
    required this.active,
    required this.expired,
    required this.online,
    required this.offline,
    required this.debtors,
    required this.totalDebt,
    required this.nearExpiry,
    required this.onTapActive,
    required this.onTapExpired,
    required this.onTapOnline,
    required this.onTapOffline,
    required this.onTapTotal,
    required this.onTapDebtors,
    required this.onTapNearExpiry,
  });

  static String _fmtDebt(double v) {
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(0)}K';
    return v.toStringAsFixed(0);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final activeRatio = total > 0 ? active / total : 0.0;
    final expiredRatio = total > 0 ? expired / total : 0.0;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.08)),
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              GestureDetector(
                onTap: onTapTotal,
                child: SizedBox(
                  width: 130,
                  height: 130,
                  child: CustomPaint(
                    painter: _RingPainter(
                      activeRatio: activeRatio,
                      expiredRatio: expiredRatio,
                      isDark: isDark,
                    ),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '$total',
                            style: const TextStyle(
                              fontSize: 30,
                              fontWeight: FontWeight.w900,
                              color: AppTheme.primary,
                              height: 1,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'مشترك',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: 0.45),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              const SizedBox(width: 16),

              Expanded(
                child: Column(
                  children: [
                    _RingStatRow(
                      color: AppTheme.teal600,
                      icon: Icons.check_circle_rounded,
                      label: 'الفعالين',
                      value: active,
                      onTap: onTapActive,
                    ),
                    const SizedBox(height: 7),
                    _RingStatRow(
                      color: AppTheme.teal400,
                      icon: Icons.wifi_rounded,
                      label: 'متصل الآن',
                      value: online,
                      onTap: onTapOnline,
                    ),
                    const SizedBox(height: 7),
                    _RingStatRow(
                      color: const Color(0xFF90A4AE),
                      icon: Icons.wifi_off_rounded,
                      label: 'غير متصل',
                      value: offline,
                      onTap: onTapOffline,
                    ),
                    const SizedBox(height: 7),
                    _RingStatRow(
                      color: const Color(0xFFEF5350),
                      icon: Icons.timer_off_rounded,
                      label: 'منتهي',
                      value: expired,
                      onTap: onTapExpired,
                    ),
                    const SizedBox(height: 7),
                    _RingStatRow(
                      color: Colors.deepOrange,
                      icon: Icons.warning_amber_rounded,
                      label: 'قريب الانتهاء',
                      value: nearExpiry,
                      onTap: onTapNearExpiry,
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              height: 6,
              child: Row(
                children: [
                  Expanded(
                    flex: active > 0 ? active : 1,
                    child: Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [AppTheme.teal700, AppTheme.teal400],
                        ),
                      ),
                    ),
                  ),
                  if (expired > 0)
                    Expanded(
                      flex: expired,
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Colors.red.shade400, Colors.red.shade700],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String value;
  final String? sub;
  final VoidCallback onTap;

  const _MiniStat({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
    this.sub,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.12)),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 18),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(label,
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.5))),
                ),
                Text(value, style: TextStyle(fontSize: 20,
                    fontWeight: FontWeight.w800, color: color)),
              ],
            ),
            if (sub != null) ...[
              const SizedBox(height: 4),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 6),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(sub!,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 10,
                        fontWeight: FontWeight.w700, color: color)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RingStatRow extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String label;
  final int value;
  final VoidCallback onTap;

  const _RingStatRow({
    required this.color,
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 15),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ),
          Text(
            '$value',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          const SizedBox(width: 4),
          Icon(Icons.chevron_left, size: 16,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.2)),
        ],
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8, height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
          ),
        ),
      ],
    );
  }
}

class _RingPainter extends CustomPainter {
  final double activeRatio;
  final double expiredRatio;
  final bool isDark;

  _RingPainter({
    required this.activeRatio,
    required this.expiredRatio,
    required this.isDark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 10;
    const strokeWidth = 14.0;
    const startAngle = -math.pi / 2;

    final bgPaint = Paint()
      ..color = AppTheme.teal100.withValues(alpha: isDark ? 0.15 : 0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, bgPaint);

    if (activeRatio > 0) {
      final activeSweep = 2 * math.pi * activeRatio;

      final rect = Rect.fromCircle(center: center, radius: radius);
      final activeGradient = SweepGradient(
        startAngle: startAngle,
        endAngle: startAngle + activeSweep,
        colors: const [AppTheme.teal300, AppTheme.teal600, AppTheme.teal800],
        stops: const [0.0, 0.5, 1.0],
      );

      final activePaint = Paint()
        ..shader = activeGradient.createShader(rect)
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;

      canvas.drawArc(rect, startAngle, activeSweep, false, activePaint);

      if (expiredRatio > 0) {
        final expiredSweep = 2 * math.pi * expiredRatio;
        const gap = 0.04;

        final expiredGradient = SweepGradient(
          startAngle: startAngle + activeSweep + gap,
          endAngle: startAngle + activeSweep + expiredSweep,
          colors: const [Color(0xFFEF9A9A), Color(0xFFE53935), Color(0xFFB71C1C)],
          stops: const [0.0, 0.5, 1.0],
        );

        final expiredPaint = Paint()
          ..shader = expiredGradient.createShader(rect)
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..strokeCap = StrokeCap.round;

        canvas.drawArc(
          rect,
          startAngle + activeSweep + gap,
          expiredSweep - gap,
          false,
          expiredPaint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) {
    return oldDelegate.activeRatio != activeRatio ||
        oldDelegate.expiredRatio != expiredRatio ||
        oldDelegate.isDark != isDark;
  }
}

// ---------------------------------------------------------------------------
//  Other Widgets
// ---------------------------------------------------------------------------

class _BalancePointsCard extends StatelessWidget {
  final String balance;
  final String points;
  const _BalancePointsCard({required this.balance, required this.points});

  static String _cleanBalance(String b) {
    var clean = b.replaceAll(RegExp(r'\.0+$'), '');
    final num = int.tryParse(clean.replaceAll(',', ''));
    if (num != null) {
      return num.toString().replaceAllMapped(
          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');
    }
    return clean;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: AppTheme.primaryGradient,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.account_balance_wallet_rounded,
                  color: Colors.white, size: 18),
              const SizedBox(width: 6),
              Text('الرصيد',
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: 11, fontWeight: FontWeight.w500)),
            ],
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              '${_cleanBalance(balance)} IQD',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15, fontWeight: FontWeight.w800),
            ),
          ),
          if (points.isNotEmpty && points != '0') ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.stars_rounded, color: Colors.amber.shade300, size: 14),
                const SizedBox(width: 4),
                Text('$points نقطة',
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.8),
                        fontSize: 11, fontWeight: FontWeight.w600)),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _DebtCard extends StatelessWidget {
  final int debtors;
  final double totalDebt;
  final VoidCallback onTap;
  const _DebtCard({required this.debtors, required this.totalDebt, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.orange.shade700, Colors.orange.shade900],
            begin: Alignment.topLeft, end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.credit_card_off_rounded,
                    color: Colors.white, size: 18),
                const SizedBox(width: 6),
                Text('المديونين',
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.7),
                        fontSize: 11, fontWeight: FontWeight.w500)),
              ],
            ),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                '${_fmtFull(totalDebt)} IQD',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15, fontWeight: FontWeight.w800),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.people_rounded,
                    color: Colors.white.withValues(alpha: 0.6), size: 14),
                const SizedBox(width: 4),
                Text('$debtors مشترك',
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.8),
                        fontSize: 11, fontWeight: FontWeight.w600)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _fmtFull(double v) {
    final intVal = v.toInt();
    final formatted = intVal.toString().replaceAllMapped(
        RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');
    return formatted;
  }
}

class _WhatsAppCompactBar extends StatelessWidget {
  final bool isConnected;
  final String? phone;

  const _WhatsAppCompactBar({required this.isConnected, this.phone});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isConnected
            ? AppTheme.whatsappGreen.withValues(alpha: 0.08)
            : Colors.grey.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isConnected
              ? AppTheme.whatsappGreen.withValues(alpha: 0.2)
              : Colors.grey.withValues(alpha: 0.15),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.chat_rounded,
              color: isConnected ? AppTheme.whatsappGreen : Colors.grey,
              size: 18),
          const SizedBox(width: 8),
          Text(
            'واتساب',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: isConnected ? AppTheme.whatsappGreen : Colors.grey,
            ),
          ),
          const SizedBox(width: 8),
          ConnectionStatusDot(isConnected: isConnected, size: 7),
          const SizedBox(width: 6),
          Text(
            isConnected ? (phone ?? 'متصل') : 'غير متصل',
            style: TextStyle(
              fontSize: 11,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _AlertsSummaryCard extends StatelessWidget {
  final int nearExpiryCount;
  final int expiredTodayCount;
  final List<Map<String, dynamic>> nearExpiryList;
  final List<Map<String, dynamic>> expiredTodayList;

  const _AlertsSummaryCard({
    required this.nearExpiryCount,
    required this.expiredTodayCount,
    required this.nearExpiryList,
    required this.expiredTodayList,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.notifications_active,
                    color: Colors.orange, size: 20),
              ),
              const SizedBox(width: 10),
              Text('تنبيهات الاشتراك',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${nearExpiryCount + expiredTodayCount}',
                  style: const TextStyle(
                    color: Colors.orange,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (expiredTodayCount > 0)
            _AlertRow(
              icon: Icons.error_outline,
              color: Colors.red,
              label: 'انتهى اليوم',
              count: expiredTodayCount,
              names: expiredTodayList.take(3).map((s) {
                final name =
                    '${s['firstname'] ?? ''} ${s['lastname'] ?? ''}'.trim();
                return name.isNotEmpty ? name : s['username']?.toString() ?? '';
              }).toList(),
            ),
          if (expiredTodayCount > 0 && nearExpiryCount > 0)
            Divider(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.08),
                height: 16),
          if (nearExpiryCount > 0)
            _AlertRow(
              icon: Icons.warning_amber_rounded,
              color: Colors.orange,
              label: 'قريب الانتهاء',
              count: nearExpiryCount,
              names: nearExpiryList.take(3).map((s) {
                final name =
                    '${s['firstname'] ?? ''} ${s['lastname'] ?? ''}'.trim();
                return name.isNotEmpty ? name : s['username']?.toString() ?? '';
              }).toList(),
            ),
        ],
      ),
    );
  }
}

class _AlertRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final int count;
  final List<String> names;

  const _AlertRow({
    required this.icon,
    required this.color,
    required this.label,
    required this.count,
    required this.names,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$label ($count)',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                names.join('، ') + (count > 3 ? ' و ${count - 3} آخرين' : ''),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TodayStatItem extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _TodayStatItem({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value,
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: color)),
                Text(label,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.5),
                          fontSize: 11,
                        ),
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
