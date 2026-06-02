import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../api/dashboard_api.dart';
import '../../api/sas4_api.dart';
import '../../core/mock/dashboard_data.dart';
import '../../services/auth_storage.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import '../search/quick_search_overlay.dart';
import 'widgets/hero_revenue_card.dart';
import 'widgets/recent_activities.dart';
import 'widgets/section_header.dart';
import 'widgets/stats_grid.dart';
import 'widgets/subscribers_card.dart';

/// Dashboard with a SLIVER-pinned header — header stays on screen while
/// the body scrolls underneath (round 5 request). Data sources:
///   - SAS4 widget endpoints → total / active / expired / online (real).
///   - /api/activities/daily-activations → today's activations (real).
///   - /api/whatsapp/connection-status → WA chip (real).
///   - mock data still backs payments, debtors, net revenue, recent
///     activities until those backend endpoints are added.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  String _displayName = '';
  String _adminUsername = '';
  WhatsAppStatusResult? _waLive;
  DailyActivationsResult? _activationsLive;
  Sas4Stats? _sas4Live;
  DebtorsResult? _debtorsLive;

  @override
  void initState() {
    super.initState();
    _loadIdentity();
    _refreshLive();
  }

  Future<void> _loadIdentity() async {
    final name = await AuthStorage.readDisplayName();
    final id = await AuthStorage.readAdminId();
    if (!mounted) return;
    setState(() {
      _displayName = name ?? '';
      _adminUsername = id ?? '';
    });
  }

  Future<void> _refreshLive() async {
    // Fire all live calls in parallel; each is allowed to fail without
    // taking down the others.
    final results = await Future.wait([
      DashboardApi.fetchWhatsAppStatus(),
      DashboardApi.fetchDailyActivations(),
      Sas4Api.fetchAll(),
      DashboardApi.fetchDebtors(),
    ]);
    if (!mounted) return;
    setState(() {
      _waLive = results[0] as WhatsAppStatusResult?;
      _activationsLive = results[1] as DailyActivationsResult?;
      _sas4Live = results[2] as Sas4Stats?;
      _debtorsLive = results[3] as DebtorsResult?;
    });
  }

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 5) return 'مساء الخير';
    if (h < 12) return 'صباح الخير';
    if (h < 17) return 'مساء النور';
    return 'مساء الخير';
  }

  @override
  Widget build(BuildContext context) {
    // Build live-merged data objects. Each prefers live; falls back to mock.
    final waStatus = _waLive == null
        ? mockWhatsApp
        : WhatsAppStatus(
            connected: _waLive!.connected,
            phone: _waLive!.phone.isNotEmpty
                ? _waLive!.phone
                : mockWhatsApp.phone,
            sentToday: mockWhatsApp.sentToday,
            queuePending: mockWhatsApp.queuePending,
          );

    final dailyStats = DailyStats(
      netToday: mockDailyStats.netToday,
      netDeltaPct: mockDailyStats.netDeltaPct,
      activations: _activationsLive?.activations ?? mockDailyStats.activations,
      activationsDelta: mockDailyStats.activationsDelta,
      payments: mockDailyStats.payments,
      paymentsDeltaPct: mockDailyStats.paymentsDeltaPct,
      debtorsCount: _debtorsLive?.count ?? mockDailyStats.debtorsCount,
      debtorsTotal: _debtorsLive?.total ?? mockDailyStats.debtorsTotal,
      expiredToday: mockDailyStats.expiredToday,
      last7Days: mockDailyStats.last7Days,
    );

    // SubscribersStats from SAS4 when available.
    final subs = SubscribersStats(
      total: _sas4Live?.total ?? mockSubscribers.total,
      active: _sas4Live?.active ?? mockSubscribers.active,
      online: _sas4Live?.online ?? mockSubscribers.online,
      expired: _sas4Live?.expired ?? mockSubscribers.expired,
      nearExpiry: mockSubscribers.nearExpiry,
    );

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: RefreshIndicator(
        color: AppColors.brand,
        onRefresh: () async {
          await Future.wait([_loadIdentity(), _refreshLive()]);
        },
        child: CustomScrollView(
          slivers: [
            // Pinned header — sticks to top while content scrolls.
            // We pass topInset so the delegate can extend over the notch
            // and pad its content below it (fixes the 'BOTTOM OVERFLOWED
            // BY 20 PIXELS' yellow stripe from round 5).
            SliverPersistentHeader(
              pinned: true,
              delegate: _PinnedHeaderDelegate(
                displayName: _displayName,
                greeting: _greeting(),
                whatsApp: waStatus,
                topInset: MediaQuery.paddingOf(context).top,
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                Sp.lg,
                Sp.md,
                Sp.lg,
                Sp.huge * 2,
              ),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  SubscribersCard(stats: subs)
                      .animate()
                      .fadeIn(duration: const Duration(milliseconds: 280))
                      .slideY(begin: 0.03, end: 0),
                  const SizedBox(height: Sp.md),
                  StatsGrid(stats: dailyStats)
                      .animate()
                      .fadeIn(
                        delay: const Duration(milliseconds: 80),
                        duration: const Duration(milliseconds: 280),
                      )
                      .slideY(begin: 0.03, end: 0),
                  const SizedBox(height: Sp.md),
                  HeroRevenueCard(stats: dailyStats)
                      .animate()
                      .fadeIn(
                        delay: const Duration(milliseconds: 160),
                        duration: const Duration(milliseconds: 280),
                      )
                      .slideY(begin: 0.03, end: 0),
                  SectionHeader(
                    label: 'آخر النشاطات',
                    trailingLabel: 'اعرض الكل',
                    onTrailingTap: () {},
                  ),
                  RecentActivities(
                    items: _activationsLive?.recent.isNotEmpty == true
                        ? _activationsLive!.recent
                        : mockActivities,
                  )
                      .animate()
                      .fadeIn(
                        delay: const Duration(milliseconds: 240),
                        duration: const Duration(milliseconds: 280),
                      ),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Delegate for the pinned header. Min and max extent are equal so the
/// header doesn't collapse — it just stays at the top with a subtle
/// hairline divider that appears when content scrolls under it.
class _PinnedHeaderDelegate extends SliverPersistentHeaderDelegate {
  _PinnedHeaderDelegate({
    required this.displayName,
    required this.greeting,
    required this.whatsApp,
    required this.topInset,
  });

  final String displayName;
  final String greeting;
  final WhatsAppStatus whatsApp;

  /// Status-bar / notch padding. Added to the extent so the header
  /// extends UNDER the notch (status bar text stays visible above)
  /// and content lives below it with [topInset] of internal padding.
  final double topInset;

  // Content height (greeting + name + WA chip + padding) is ~108. Plus
  // topInset (notch) gives the total visible extent. Same value for min
  // and max so the header never collapses.
  static const double _contentHeight = 108;

  @override
  double get minExtent => _contentHeight + topInset;

  @override
  double get maxExtent => _contentHeight + topInset;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    // No hairline divider — the line that appeared during scroll near
    // the WA chip felt visually noisy. The header just sits on the bg
    // color and lets the content scroll under it transparently.
    return Container(
      color: AppColors.bg,
      padding: EdgeInsets.fromLTRB(Sp.lg, topInset + Sp.sm, Sp.lg, Sp.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(greeting,
                    style: AppType.subtitle(color: AppColors.textMid)),
                const SizedBox(height: 2),
                Text(
                  displayName.isEmpty ? 'مرحباً' : displayName,
                  style: AppType.title(color: AppColors.textHi)
                      .copyWith(fontSize: 20),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                _WAStatusChip(status: whatsApp),
              ],
            ),
          ),
          _IconChip(
            icon: Icons.search_rounded,
            onTap: () => showQuickSearch(context),
          ),
          const SizedBox(width: Sp.sm),
          _IconChip(
            icon: Icons.notifications_none_rounded,
            badge: 3,
            onTap: () {},
          ),
        ],
      ),
    );
  }

  @override
  bool shouldRebuild(_PinnedHeaderDelegate old) =>
      old.displayName != displayName ||
      old.greeting != greeting ||
      old.whatsApp.connected != whatsApp.connected ||
      old.whatsApp.phone != whatsApp.phone;
}

class _WAStatusChip extends StatelessWidget {
  const _WAStatusChip({required this.status});
  final WhatsAppStatus status;

  @override
  Widget build(BuildContext context) {
    final c = status.connected ? AppColors.brand : AppColors.error;
    return InkWell(
      onTap: () {},
      borderRadius: BorderRadius.circular(R.pill),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: Sp.sm,
          vertical: 4,
        ),
        decoration: BoxDecoration(
          color: c.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(R.pill),
          border: Border.all(color: c.withValues(alpha: 0.25)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(color: c, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Text(
              status.connected ? 'واتساب متصل' : 'واتساب منقطع',
              style: AppType.muted(color: c).copyWith(fontSize: 11),
            ),
            if (!status.connected) ...[
              const SizedBox(width: 6),
              Container(
                width: 1,
                height: 10,
                color: c.withValues(alpha: 0.3),
              ),
              const SizedBox(width: 6),
              Text('ربط', style: AppType.label(color: c).copyWith(fontSize: 11)),
            ],
          ],
        ),
      ),
    );
  }
}

class _IconChip extends StatelessWidget {
  const _IconChip({required this.icon, this.badge = 0, required this.onTap});
  final IconData icon;
  final int badge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        SizedBox(
          width: 42,
          height: 42,
          child: Material(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(R.md),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(R.md),
                  border: Border.all(color: AppColors.border),
                ),
                child: Icon(icon, color: AppColors.textHi, size: 20),
              ),
            ),
          ),
        ),
        if (badge > 0)
          Positioned(
            top: -4,
            left: -4,
            child: Container(
              constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
              padding: const EdgeInsets.symmetric(horizontal: 5),
              decoration: BoxDecoration(
                color: AppColors.error,
                borderRadius: BorderRadius.circular(R.pill),
                border: Border.all(color: AppColors.bg, width: 2),
              ),
              alignment: Alignment.center,
              child: Text(
                '$badge',
                style: AppType.muted(color: Colors.white)
                    .copyWith(fontSize: 10, height: 1),
              ),
            ),
          ),
      ],
    );
  }
}
