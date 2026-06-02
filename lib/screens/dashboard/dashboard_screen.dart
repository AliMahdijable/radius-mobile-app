import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../core/mock/dashboard_data.dart';
import '../../services/auth_storage.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import 'widgets/hero_revenue_card.dart';
import 'widgets/quick_actions_row.dart';
import 'widgets/recent_activities.dart';
import 'widgets/section_header.dart';
import 'widgets/stats_grid.dart';
import 'widgets/subscribers_card.dart';
import 'widgets/whatsapp_card.dart';

/// Main home dashboard. Greeting + hero revenue + 4 quick stats + subscribers
/// summary + WhatsApp status + recent activity feed.
///
/// All data is mock for now (see lib/core/mock/dashboard_data.dart). Real
/// API wiring comes in the next iteration, screen-by-screen so we can
/// verify each integration.
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
            padding: const EdgeInsets.fromLTRB(
              Sp.lg,
              Sp.md,
              Sp.lg,
              // Leave room for the bottom nav + FAB notch.
              Sp.huge + Sp.huge,
            ),
            children: [
              _Header(displayName: _displayName, greeting: _greeting()),
              const SizedBox(height: Sp.lg),
              HeroRevenueCard(stats: mockDailyStats)
                  .animate()
                  .fadeIn(duration: const Duration(milliseconds: 300))
                  .slideY(begin: 0.03, end: 0),
              const SizedBox(height: Sp.md),
              const QuickActionsRow()
                  .animate()
                  .fadeIn(
                    delay: const Duration(milliseconds: 60),
                    duration: const Duration(milliseconds: 300),
                  )
                  .slideY(begin: 0.03, end: 0),
              const SizedBox(height: Sp.md),
              StatsGrid(stats: mockDailyStats)
                  .animate()
                  .fadeIn(
                    delay: const Duration(milliseconds: 120),
                    duration: const Duration(milliseconds: 300),
                  )
                  .slideY(begin: 0.03, end: 0),
              const SizedBox(height: Sp.md),
              const SubscribersCard(stats: mockSubscribers)
                  .animate()
                  .fadeIn(
                    delay: const Duration(milliseconds: 160),
                    duration: const Duration(milliseconds: 300),
                  )
                  .slideY(begin: 0.03, end: 0),
              const SizedBox(height: Sp.md),
              const WhatsAppCard(status: mockWhatsApp)
                  .animate()
                  .fadeIn(
                    delay: const Duration(milliseconds: 220),
                    duration: const Duration(milliseconds: 300),
                  )
                  .slideY(begin: 0.03, end: 0),
              SectionHeader(
                label: 'آخر النشاطات',
                trailingLabel: 'اعرض الكل',
                onTrailingTap: () {},
              ),
              const RecentActivities(items: mockActivities).animate().fadeIn(
                    delay: const Duration(milliseconds: 300),
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
  const _Header({required this.displayName, required this.greeting});
  final String displayName;
  final String greeting;

  @override
  Widget build(BuildContext context) {
    return Row(
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
