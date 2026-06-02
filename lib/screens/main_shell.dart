import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/colors.dart';
import '../theme/spacing.dart';
import '../theme/typography.dart';
import 'dashboard/dashboard_screen.dart';
import 'reports_screen.dart';
import 'settings_screen.dart';
import 'subscribers_screen.dart';

/// 4 bottom tabs (Home / Subscribers / Reports / Settings) with a center
/// FAB raised above the bar for quick add actions. Tab state preserved
/// via IndexedStack so the user's scroll position survives switching.
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
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(R.xl)),
      ),
      builder: (_) => const _QuickAddSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    // extendBody:false (default) so the tab content stops at the bar edge.
    // Previous value `true` made the body extend behind a partially-
    // transparent bar — content visibly bled through the bottom gap.
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: IndexedStack(index: _tab, children: _tabs),
      bottomNavigationBar: _BottomBar(
        current: _tab,
        onChanged: (i) => setState(() => _tab = i),
        onFabTap: _onFabTap,
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.current,
    required this.onChanged,
    required this.onFabTap,
  });

  final int current;
  final ValueChanged<int> onChanged;
  final VoidCallback onFabTap;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.topCenter,
        children: [
          Container(
            height: 72,
            decoration: const BoxDecoration(
              color: AppColors.surface,
              border: Border(top: BorderSide(color: AppColors.border)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: Sp.xs),
            child: Row(
              children: [
                _NavItem(
                  icon: Icons.home_rounded,
                  label: 'الرئيسية',
                  selected: current == 0,
                  onTap: () => onChanged(0),
                ),
                _NavItem(
                  icon: Icons.people_alt_rounded,
                  label: 'المشتركون',
                  selected: current == 1,
                  onTap: () => onChanged(1),
                ),
                // Spacer for the floating center FAB
                const SizedBox(width: 64),
                _NavItem(
                  icon: Icons.insert_chart_rounded,
                  label: 'التقارير',
                  selected: current == 2,
                  onTap: () => onChanged(2),
                ),
                _NavItem(
                  icon: Icons.settings_outlined,
                  label: 'الضبط',
                  selected: current == 3,
                  onTap: () => onChanged(3),
                ),
              ],
            ),
          ),
          Positioned(
            top: -18,
            child: GestureDetector(
              onTap: onFabTap,
              child: Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: AppColors.brand,
                  shape: BoxShape.circle,
                  // Thin matching-bg ring + restrained shadow so the FAB
                  // reads as a confident pill, not a glowing emergency button.
                  border: Border.all(color: AppColors.surface, width: 3),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.brand.withValues(alpha: 0.18),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Icon(Icons.add_rounded,
                    color: Colors.white, size: 24),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
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
    final color = selected ? AppColors.brand : AppColors.textLow;
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
                duration: const Duration(milliseconds: 160),
                curve: Curves.easeOutBack,
                scale: selected ? 1.1 : 1.0,
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(height: 4),
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
            color: const Color(0xFF3B82F6),
            title: 'مشترك جديد',
            subtitle: 'إضافة مشترك للنظام',
          ),
          _QuickItem(
            icon: Icons.payments_rounded,
            color: const Color(0xFF8B5CF6),
            title: 'تسديد دين',
            subtitle: 'استلام دفعة من مشترك',
          ),
          _QuickItem(
            icon: Icons.chat_bubble_rounded,
            color: const Color(0xFFE08F2D),
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
              const Icon(Icons.arrow_back_ios_new_rounded,
                  size: 12, color: AppColors.textLow),
            ],
          ),
        ),
      ),
    );
  }
}
