import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/colors.dart';
import '../theme/spacing.dart';
import '../theme/typography.dart';
import 'dashboard/dashboard_screen.dart';
import 'reports_screen.dart';
import 'settings_screen.dart';
import 'subscribers_screen.dart';

/// Round 5 bottom bar — stuck to the bottom edge (not floating), FAB
/// integrated via a circular notch cut into the bar. This is the classic
/// Material BottomAppBar + FloatingActionButton.centerDocked pattern;
/// reads as a single cohesive surface instead of two separate floating
/// elements like the previous pill design.
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _tab = 0;

  static const _tabs = <Widget>[
    DashboardScreen(),
    SubscribersScreen(),
    ReportsScreen(),
    SettingsScreen(),
  ];

  void _onFabTap() {
    HapticFeedback.selectionClick();
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(R.xl)),
      ),
      builder: (_) => const _QuickAddSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: IndexedStack(index: _tab, children: _tabs),
      floatingActionButton: FloatingActionButton(
        onPressed: _onFabTap,
        backgroundColor: AppColors.brand,
        foregroundColor: Colors.white,
        elevation: 0,
        highlightElevation: 0,
        shape: const CircleBorder(),
        child: const Icon(Icons.add_rounded, size: 28),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: BottomAppBar(
        color: AppColors.surface,
        elevation: 0,
        shape: const CircularNotchedRectangle(),
        notchMargin: 6,
        padding: EdgeInsets.zero,
        height: 64,
        child: Row(
          children: [
            _NavTab(
              icon: Icons.home_rounded,
              label: 'الرئيسية',
              selected: _tab == 0,
              onTap: () => setState(() => _tab = 0),
            ),
            _NavTab(
              icon: Icons.people_alt_rounded,
              label: 'المشتركون',
              selected: _tab == 1,
              onTap: () => setState(() => _tab = 1),
            ),
            // Notch space for the FAB
            const SizedBox(width: 56),
            _NavTab(
              icon: Icons.insert_chart_rounded,
              label: 'التقارير',
              selected: _tab == 2,
              onTap: () => setState(() => _tab = 2),
            ),
            _NavTab(
              icon: Icons.settings_outlined,
              label: 'الضبط',
              selected: _tab == 3,
              onTap: () => setState(() => _tab = 3),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavTab extends StatelessWidget {
  const _NavTab({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.brand : AppColors.textMid;
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedScale(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                scale: selected ? 1.1 : 1.0,
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(height: 3),
              Text(
                label,
                style: AppType.muted(color: color).copyWith(fontSize: 10),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickAddSheet extends StatelessWidget {
  const _QuickAddSheet();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Sp.lg, 0, Sp.lg, Sp.huge),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('إضافة سريعة',
              style: AppType.title(color: AppColors.textHi)
                  .copyWith(fontSize: 18)),
          const SizedBox(height: Sp.lg),
          _QuickItem(
            icon: Icons.bolt_rounded,
            color: AppColors.brand,
            title: 'تفعيل سريع',
            subtitle: 'تفعيل مشترك موجود',
          ),
          _QuickItem(
            icon: Icons.person_add_rounded,
            color: Color(0xFF3B82F6),
            title: 'مشترك جديد',
            subtitle: 'إضافة مشترك للنظام',
          ),
          _QuickItem(
            icon: Icons.payments_rounded,
            color: Color(0xFF8B5CF6),
            title: 'تسديد دين',
            subtitle: 'استلام دفعة من مشترك',
          ),
          _QuickItem(
            icon: Icons.chat_bubble_rounded,
            color: Color(0xFFE08F2D),
            title: 'رسالة واتساب',
            subtitle: 'إرسال رسالة فردية',
          ),
        ],
      ),
    );
  }
}

class _QuickItem extends StatelessWidget {
  const _QuickItem({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => Navigator.of(context).pop(),
        borderRadius: BorderRadius.circular(R.md),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Sp.sm,
            vertical: Sp.md,
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(R.sm),
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(width: Sp.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: AppType.label(color: AppColors.textHi)
                            .copyWith(fontSize: 14)),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: AppType.subtitle(color: AppColors.textMid)
                            .copyWith(fontSize: 12)),
                  ],
                ),
              ),
              Icon(Icons.arrow_back_ios_new_rounded,
                  size: 12, color: AppColors.textLow),
            ],
          ),
        ),
      ),
    );
  }
}
