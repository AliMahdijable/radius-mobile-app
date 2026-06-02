import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/colors.dart';
import '../theme/spacing.dart';
import '../theme/typography.dart';
import 'dashboard/dashboard_screen.dart';
import 'reports_screen.dart';
import 'settings_screen.dart';
import 'subscribers_screen.dart';

/// Pill-style floating bottom bar (round-3 redesign):
///   - Detached from the screen edges (floats with margin all around).
///   - Pill shape (fully rounded) with subtle elevation.
///   - 4 tab icons + center FAB; FAB protrudes slightly above the pill.
///   - Active tab gets a brand-tinted background behind its icon, not
///     just an oversized icon — reads more clearly than the old style.
///   - Quick-search button moved into the pill (replaces what used to
///     be a separate FAB) so the screen feels less busy.
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

  void _onSearchTap() {
    HapticFeedback.selectionClick();
    // TODO[quick-search]: open spotlight-style global search.
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      extendBody: true,
      body: Stack(
        children: [
          IndexedStack(index: _tab, children: _tabs),
          // Pill bar sits on top of body with a transparent area below it.
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  Sp.md,
                  0,
                  Sp.md,
                  Sp.sm,
                ),
                child: _PillBar(
                  current: _tab,
                  onChanged: (i) => setState(() => _tab = i),
                  onFabTap: _onFabTap,
                  onSearchTap: _onSearchTap,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PillBar extends StatelessWidget {
  const _PillBar({
    required this.current,
    required this.onChanged,
    required this.onFabTap,
    required this.onSearchTap,
  });

  final int current;
  final ValueChanged<int> onChanged;
  final VoidCallback onFabTap;
  final VoidCallback onSearchTap;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.topCenter,
      children: [
        Container(
          height: 64,
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(R.pill),
            border: Border.all(color: AppColors.border),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.07),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: Sp.sm),
          child: Row(
            children: [
              _NavSlot(
                icon: Icons.home_rounded,
                label: 'الرئيسية',
                selected: current == 0,
                onTap: () => onChanged(0),
              ),
              _NavSlot(
                icon: Icons.people_alt_rounded,
                label: 'المشتركون',
                selected: current == 1,
                onTap: () => onChanged(1),
              ),
              // Spacer for the floating FAB above.
              const SizedBox(width: 56),
              _NavSlot(
                icon: Icons.insert_chart_rounded,
                label: 'التقارير',
                selected: current == 2,
                onTap: () => onChanged(2),
              ),
              _NavSlot(
                icon: Icons.settings_outlined,
                label: 'الضبط',
                selected: current == 3,
                onTap: () => onChanged(3),
              ),
            ],
          ),
        ),
        // Floating + button — slightly above the pill, brand-color, white
        // ring matching the page background so it looks "lifted".
        Positioned(
          top: -20,
          child: GestureDetector(
            onTap: onFabTap,
            child: Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: AppColors.brand,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.bg, width: 4),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.brand.withValues(alpha: 0.22),
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
      ],
    );
  }
}

class _NavSlot extends StatelessWidget {
  const _NavSlot({
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
    return Expanded(
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          customBorder: const CircleBorder(),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            margin: const EdgeInsets.symmetric(
              vertical: Sp.sm,
              horizontal: 4,
            ),
            decoration: BoxDecoration(
              color: selected
                  ? AppColors.brand.withValues(alpha: 0.12)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(R.pill),
            ),
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    icon,
                    color: selected ? AppColors.brand : AppColors.textMid,
                    size: 22,
                  ),
                  // Label only appears on the active tab — keeps the
                  // inactive icons clean and lets the active tab carry
                  // a clear contextual label.
                  AnimatedSize(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    child: selected
                        ? Padding(
                            padding: const EdgeInsets.only(
                              right: 6,
                              left: 4,
                            ),
                            child: Text(
                              label,
                              style: AppType.label(color: AppColors.brand)
                                  .copyWith(fontSize: 12),
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
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
