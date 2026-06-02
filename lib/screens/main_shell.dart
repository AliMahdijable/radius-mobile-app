import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/colors.dart';
import '../theme/spacing.dart';
import '../theme/typography.dart';
import 'dashboard/dashboard_screen.dart';
import 'reports_screen.dart';
import 'search/quick_search_overlay.dart';
import 'settings_screen.dart';
import 'subscribers_screen.dart';

/// Round 10 redesign — floating pill bar with a brand-green indicator
/// that slides between tabs. The bar is a single cohesive surface
/// (white pill + soft shadow); when the user switches tabs the green
/// pill background AnimatedPositions smoothly to the new slot. The
/// active tab shows icon + label inline (white text); inactive tabs
/// show icon only (brand-tinted). FAB is integrated as the middle
/// tab, always brand-green, slightly larger than the row to draw the
/// eye. Search lives as a separate small pill above the bar on the
/// trailing side.
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
      extendBody: true, // body draws under the floating bar
      body: Stack(
        children: [
          IndexedStack(index: _tab, children: _tabs),
          // Standalone search pill floats above the bar on the right.
          Positioned(
            right: Sp.lg,
            bottom: 96,
            child: _SearchPill(onTap: () => showQuickSearch(context)),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            Sp.lg,
            0,
            Sp.lg,
            Sp.sm,
          ),
          child: _PillBar(
            current: _tab,
            onTabTap: (i) => setState(() => _tab = i),
            onFabTap: _onFabTap,
          ),
        ),
      ),
    );
  }
}

/// Floating pill nav. 4 tabs + a center FAB rendered as a 5th 'slot'.
/// The brand-green indicator pill slides between tab slots via
/// AnimatedAlignment + AnimatedContainer.
class _PillBar extends StatelessWidget {
  const _PillBar({
    required this.current,
    required this.onTabTap,
    required this.onFabTap,
  });

  final int current;
  final ValueChanged<int> onTabTap;
  final VoidCallback onFabTap;

  static const _tabsBefore = 2; // tabs 0,1 sit before the FAB slot
  static const _tabsAfter = 2;  // tabs 2,3 sit after the FAB slot

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        // Each slot is 1/5 of the bar width; the green indicator is a
        // little narrower than a slot so it doesn't touch its neighbors.
        const totalSlots = 5;
        final slotWidth = c.maxWidth / totalSlots;
        // Slot indexes in left-to-right order. RTL flips the visual side
        // but the data order stays logical. We map tab index → slot:
        //   tab 0 (home)        → slot 0
        //   tab 1 (subscribers) → slot 1
        //   FAB                 → slot 2 (center)
        //   tab 2 (reports)     → slot 3
        //   tab 3 (settings)    → slot 4
        final activeSlot = current < _tabsBefore ? current : current + 1;
        final indicatorLeft = slotWidth * activeSlot + 6;
        final indicatorWidth = slotWidth - 12;

        return Container(
          height: 60,
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(30),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 20,
                offset: const Offset(0, 6),
              ),
              BoxShadow(
                color: AppColors.brand.withValues(alpha: 0.06),
                blurRadius: 30,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Stack(
            children: [
              // Sliding brand-green pill that marks the active tab.
              AnimatedPositioned(
                duration: const Duration(milliseconds: 320),
                curve: Curves.easeOutCubic,
                left: indicatorLeft,
                top: 8,
                bottom: 8,
                width: indicatorWidth,
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.brand,
                    borderRadius: BorderRadius.circular(22),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.brand.withValues(alpha: 0.32),
                        blurRadius: 14,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                ),
              ),
              // Tab labels sit ABOVE the indicator. Each slot is a
              // fixed-width cell laid out left to right.
              Row(
                children: [
                  _TabSlot(
                    icon: Icons.home_rounded,
                    label: 'الرئيسية',
                    slotWidth: slotWidth,
                    selected: current == 0,
                    onTap: () => _select(0),
                  ),
                  _TabSlot(
                    icon: Icons.people_alt_rounded,
                    label: 'المشتركون',
                    slotWidth: slotWidth,
                    selected: current == 1,
                    onTap: () => _select(1),
                  ),
                  // Middle slot: the integrated FAB.
                  _FabSlot(slotWidth: slotWidth, onTap: onFabTap),
                  _TabSlot(
                    icon: Icons.insert_chart_rounded,
                    label: 'التقارير',
                    slotWidth: slotWidth,
                    selected: current == 2,
                    onTap: () => _select(2),
                  ),
                  _TabSlot(
                    icon: Icons.settings_outlined,
                    label: 'الضبط',
                    slotWidth: slotWidth,
                    selected: current == 3,
                    onTap: () => _select(3),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  void _select(int i) {
    HapticFeedback.selectionClick();
    onTabTap(i);
  }
}

class _TabSlot extends StatelessWidget {
  const _TabSlot({
    required this.icon,
    required this.label,
    required this.slotWidth,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final double slotWidth;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: slotWidth,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(22),
          child: Center(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              transitionBuilder: (child, anim) => FadeTransition(
                opacity: anim,
                child: SizeTransition(
                  axis: Axis.horizontal,
                  axisAlignment: -1,
                  sizeFactor: anim,
                  child: child,
                ),
              ),
              child: selected
                  ? Row(
                      key: const ValueKey('on'),
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(icon, color: Colors.white, size: 18),
                        const SizedBox(width: 6),
                        Text(
                          label,
                          style: AppType.label(color: Colors.white)
                              .copyWith(fontSize: 12),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    )
                  : Icon(
                      icon,
                      key: const ValueKey('off'),
                      color: AppColors.textLow,
                      size: 22,
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FabSlot extends StatelessWidget {
  const _FabSlot({required this.slotWidth, required this.onTap});

  final double slotWidth;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // FAB lifted slightly above the pill so it reads as a 'primary'
    // action without falling out of the bar visually.
    return SizedBox(
      width: slotWidth,
      child: Center(
        child: Transform.translate(
          offset: const Offset(0, -10),
          child: Material(
            color: AppColors.brand,
            shape: const CircleBorder(),
            elevation: 0,
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () {
                HapticFeedback.selectionClick();
                onTap();
              },
              customBorder: const CircleBorder(),
              child: Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.surface, width: 3),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.brand.withValues(alpha: 0.36),
                      blurRadius: 14,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: const Icon(Icons.add_rounded,
                    color: Colors.white, size: 26),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SearchPill extends StatelessWidget {
  const _SearchPill({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        customBorder: const CircleBorder(),
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.brand, width: 1.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: const Icon(Icons.search_rounded,
              color: AppColors.brand, size: 20),
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
