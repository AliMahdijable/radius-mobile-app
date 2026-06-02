import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../core/mock/dashboard_data.dart';
import '../../services/auth_storage.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import 'widgets/hero_revenue_card.dart';
import 'widgets/recent_activities.dart';
import 'widgets/section_header.dart';
import 'widgets/stats_grid.dart';
import 'widgets/subscribers_card.dart';

/// Dashboard order (per user feedback round 2):
///   1. Header: greeting + admin name + WA status chip + bell + settings.
///   2. Subscribers card (was 3rd — moved to top, it's the highest-value
///      info for an ISP operator opening the app).
///   3. Quick actions (4 buttons).
///   4. 2×2 stats grid.
///   5. Hero revenue card — shrunk and demoted; it's nice to see but not
///      the most-actionable piece of info.
///   6. Recent activities feed.
///
/// WhatsApp standalone card removed — its status now lives inline next to
/// the admin name in the header so a glance at the top reveals everything.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  String _displayName = '';
  String _adminUsername = '';

  @override
  void initState() {
    super.initState();
    _loadIdentity();
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

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 5) return 'مساء الخير';
    if (h < 12) return 'صباح الخير';
    if (h < 17) return 'مساء النور';
    return 'مساء الخير';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: AppColors.brand,
          onRefresh: () async => _loadIdentity(),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, Sp.huge),
            children: [
              _Header(
                displayName: _displayName,
                greeting: _greeting(),
                whatsApp: mockWhatsApp,
              ),
              const SizedBox(height: Sp.lg),
              const SubscribersCard(stats: mockSubscribers)
                  .animate()
                  .fadeIn(duration: const Duration(milliseconds: 300))
                  .slideY(begin: 0.03, end: 0),
              const SizedBox(height: Sp.md),
              StatsGrid(stats: mockDailyStats)
                  .animate()
                  .fadeIn(
                    delay: const Duration(milliseconds: 80),
                    duration: const Duration(milliseconds: 300),
                  )
                  .slideY(begin: 0.03, end: 0),
              const SizedBox(height: Sp.md),
              HeroRevenueCard(stats: mockDailyStats)
                  .animate()
                  .fadeIn(
                    delay: const Duration(milliseconds: 160),
                    duration: const Duration(milliseconds: 300),
                  )
                  .slideY(begin: 0.03, end: 0),
              SectionHeader(
                label: 'آخر النشاطات',
                trailingLabel: 'اعرض الكل',
                onTrailingTap: () {},
              ),
              const RecentActivities(items: mockActivities).animate().fadeIn(
                    delay: const Duration(milliseconds: 320),
                    duration: const Duration(milliseconds: 300),
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.displayName,
    required this.greeting,
    required this.whatsApp,
  });
  final String displayName;
  final String greeting;
  final WhatsAppStatus whatsApp;

  @override
  Widget build(BuildContext context) {
    return Row(
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
                    .copyWith(fontSize: 22),
              ),
              const SizedBox(height: 6),
              _WAStatusChip(status: whatsApp),
            ],
          ),
        ),
        _IconChip(
          icon: Icons.notifications_none_rounded,
          badge: 3,
          onTap: () {},
        ),
        const SizedBox(width: Sp.sm),
        _IconChip(
          icon: Icons.settings_outlined,
          onTap: () {},
        ),
      ],
    );
  }
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
            if (status.connected) ...[
              const SizedBox(width: 4),
              Text(
                '• ${status.sentToday} اليوم',
                style: AppType.muted(color: c.withValues(alpha: 0.7))
                    .copyWith(fontSize: 11),
              ),
            ] else ...[
              const SizedBox(width: 6),
              Container(
                width: 1,
                height: 10,
                color: c.withValues(alpha: 0.3),
              ),
              const SizedBox(width: 6),
              Text(
                'ربط',
                style: AppType.label(color: c).copyWith(fontSize: 11),
              ),
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
