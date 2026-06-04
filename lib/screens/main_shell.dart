import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/colors.dart';
import '../theme/spacing.dart';
import '../theme/typography.dart';
import 'dashboard/dashboard_screen.dart';
import 'reports_screen.dart';
import 'search/quick_search_overlay.dart';
import 'settings_screen.dart';
import 'subscribers/subscribers_screen.dart';
import 'subscribers/widgets/filter_chips_bar.dart';

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
  // Initial filter for the subscribers screen when opened via a
  // dashboard card tap. Bumped on every navigate so SubscribersScreen
  // sees a fresh ValueKey and re-applies the filter even if the user
  // taps the same KPI twice.
  SubscriberFilter? _pendingSubsFilter;
  int _subsNonce = 0;

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

  /// Public entry point for any tab to jump to the subscribers list
  /// with a specific filter pre-applied (dashboard taps use this).
  void _openSubscribers(SubscriberFilter? filter) {
    HapticFeedback.selectionClick();
    setState(() {
      _tab = 1;
      _pendingSubsFilter = filter;
      _subsNonce++;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Build the tab list each frame so the subscribers screen can pick
    // up a fresh initialFilter via its ValueKey (IndexedStack keeps the
    // others around — they don't rebuild).
    final tabs = <Widget>[
      DashboardScreen(onOpenSubscribers: _openSubscribers),
      SubscribersScreen(
        key: ValueKey(
            'subs-${_pendingSubsFilter?.name ?? 'all'}-$_subsNonce'),
        initialFilter: _pendingSubsFilter,
      ),
      const ReportsScreen(),
      const SettingsScreen(),
    ];

    return Scaffold(
      backgroundColor: AppColors.bg,
      extendBody: true, // body draws under the floating bar
      body: Stack(
        children: [
          IndexedStack(index: _tab, children: tabs),
          // Standalone search pill floats above the bar on the right.
          // bottom = bar height (64) + bar bottom padding (Sp.sm) +
          // safe-area inset + a gap so it doesn't touch the bar.
          Positioned(
            right: Sp.lg,
            bottom: 64 + Sp.sm + MediaQuery.paddingOf(context).bottom + 16,
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

/// Clean professional bottom nav — 4 tab icons with a brand-green tint
/// + label for the active one, plus a center FAB. No oversized pill, no
/// sliding background. Active state = icon turns brand-green and shows a
/// tiny dot underneath. Inactive = muted icon only. The shell is a
/// floating white pill with a soft shadow, slim enough to feel light.
class _PillBar extends StatelessWidget {
  const _PillBar({
    required this.current,
    required this.onTabTap,
    required this.onFabTap,
  });

  final int current;
  final ValueChanged<int> onTabTap;
  final VoidCallback onFabTap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        const totalSlots = 5;
        final slotWidth = c.maxWidth / totalSlots;
        return Container(
          height: 64,
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(32),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
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
    final fg = selected ? AppColors.brand : AppColors.textLow;
    return SizedBox(
      width: slotWidth,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: fg, size: selected ? 24 : 22),
              const SizedBox(height: 3),
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 200),
                style: AppType.muted(color: fg).copyWith(
                  fontSize: 10,
                  fontWeight:
                      selected ? FontWeight.w700 : FontWeight.w500,
                ),
                child: Text(label, maxLines: 1, overflow: TextOverflow.fade),
              ),
              const SizedBox(height: 3),
              // Tiny dot under the active tab. Reserves the same 4px of
              // vertical space whether selected or not so labels don't shift.
              SizedBox(
                height: 4,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 200),
                  opacity: selected ? 1 : 0,
                  child: Container(
                    width: 4,
                    height: 4,
                    decoration: const BoxDecoration(
                      color: AppColors.brand,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
            ],
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
    return SizedBox(
      width: slotWidth,
      child: Center(
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
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.brand.withValues(alpha: 0.35),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Icon(Icons.add_rounded,
                  color: Colors.white, size: 26),
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
            icon: Icons.receipt_long_rounded,
            color: Color(0xFFE08F2D),
            title: 'إضافة صرفية',
            subtitle: 'تسجيل مصروف جديد',
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
