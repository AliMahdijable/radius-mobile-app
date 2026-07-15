import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/api_client.dart' show authExpiredSignal;
import '../services/permissions_service.dart';
import '../theme/colors.dart';
import '../theme/spacing.dart';
import '../theme/typography.dart';
import 'dashboard/dashboard_screen.dart';
import 'login_screen.dart';
import 'more_modules_screen.dart';
import 'reports_screen.dart';
import 'search/quick_search_overlay.dart';
import 'expenses/sheets/add_expense_sheet.dart';
import 'subscribers/sheets/activate_sheet.dart';
import 'subscribers/sheets/add_debt_sheet.dart';
import 'subscribers/sheets/add_subscriber_sheet.dart';
import 'subscribers/sheets/pay_debt_sheet.dart';
import 'subscribers/sheets/subscriber_picker_sheet.dart';
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
  // Filter command channel for the subscribers screen. Updating this
  // notifier from a dashboard KPI tap pushes the new filter into the
  // already-mounted SubscribersScreen WITHOUT rebuilding it — which
  // means the cached subscriber list stays in memory and the screen
  // appears instantly instead of re-fetching all 4 sources.
  final ValueNotifier<SubscriberFilter?> _subsFilterCmd =
      ValueNotifier<SubscriberFilter?>(null);

  /// مطلب 2026-06-11: 'النقر ع زر الرجوع مرتين يلا يخرج البرنامج'.
  /// First back press shows a snackbar; a second press within this
  /// window actually exits. Standard Android double-back pattern.
  DateTime? _lastBackPress;
  static const _backExitWindow = Duration(seconds: 2);

  int _authExpiredSeen = 0;
  void _onAuthExpired() {
    final v = authExpiredSignal.value;
    if (v == _authExpiredSeen || !mounted) return;
    _authExpiredSeen = v;
    // 2026-06-14: signal من api_client.dart حين empToken الموظف انتهى
    // (refresh مرفوض بقصد). نمسح أي حالة محلية ونرجع لشاشة الدخول.
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('common.session_expired'.tr())),
    );
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  @override
  void initState() {
    super.initState();
    _authExpiredSeen = authExpiredSignal.value;
    authExpiredSignal.addListener(_onAuthExpired);
  }

  @override
  void dispose() {
    authExpiredSignal.removeListener(_onAuthExpired);
    _subsFilterCmd.dispose();
    super.dispose();
  }

  void _onFabTap() {
    HapticFeedback.selectionClick();
    // Capture the MainShell context so the QuickAddSheet callbacks
    // can route to new sheets even after the FAB sheet pops. Using
    // the bottom-sheet's own context to push a follow-up sheet
    // fails silently because that context's element unmounts on
    // pop (user report 2026-06-10: 'ما يصير أي حدث عن النقر ع
    // اليوزر').
    final rootCtx = context;
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(R.xl)),
      ),
      builder: (_) => _QuickAddSheet(rootContext: rootCtx),
    );
  }

  /// Public entry point for any tab to jump to the subscribers list
  /// with a specific filter pre-applied (dashboard taps use this).
  /// Notifier listeners on SubscribersScreen pick up the change without
  /// the widget being recreated — instant tab switch, no refetch.
  void _openSubscribers(SubscriberFilter? filter) {
    HapticFeedback.selectionClick();
    if (_tab != 1) setState(() => _tab = 1);
    // Push BOTH a marker (incrementing a value internal to the notifier
    // by wrapping in a unique object) and the filter so same-filter
    // re-taps still fire. We just set the value; ValueNotifier suppresses
    // notifications when oldValue==newValue, so to bypass that we set to
    // null first then to the real value — quick & cheap.
    _subsFilterCmd.value = null;
    _subsFilterCmd.value = filter;
  }

  /// Handler for Android system back. Returns true to let the pop
  /// proceed (i.e. exit), false to swallow it. Two-stage flow:
  ///   1. If not on Home tab → jump to Home, swallow.
  ///   2. If on Home → first press: snackbar + remember timestamp,
  ///      second press within 2s: let the pop proceed (exits app).
  Future<bool> _onWillPop() async {
    if (_tab != 0) {
      setState(() => _tab = 0);
      return false;
    }
    final now = DateTime.now();
    if (_lastBackPress != null &&
        now.difference(_lastBackPress!) < _backExitWindow) {
      return true; // allow the pop → exits the app
    }
    _lastBackPress = now;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('common.back_to_exit'.tr()),
        backgroundColor: AppColors.textHi,
        duration: _backExitWindow,
        behavior: SnackBarBehavior.floating,
      ),
    );
    return false;
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final tabs = <Widget>[
      DashboardScreen(onOpenSubscribers: _openSubscribers),
      SubscribersScreen(filterCmd: _subsFilterCmd),
      const ReportsScreen(),
      // مطلب 2026-06-10: الـtab السفلي الأخير صار "قوائم أخرى" يعرض
      // مديولات إضافية (صرفيات/مدراء/تسعير). شاشة الإعدادات الفعلية
      // انتقلت لزر الـgear بالشريط العلوي على Home.
      const MoreModulesScreen(),
    ];

    return PopScope(
      // canPop=false lets us intercept every system back press. We
      // call SystemNavigator.pop() ourselves when the user confirms
      // exit (two presses within the window).
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final shouldExit = await _onWillPop();
        if (shouldExit) {
          await SystemNavigator.pop();
        }
      },
      child: _buildScaffold(tabs),
    );
  }

  Widget _buildScaffold(List<Widget> tabs) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      extendBody: true, // body draws under the floating bar
      body: Stack(
        children: [
          IndexedStack(index: _tab, children: tabs),
          // Standalone search pill — 2026-07-14: نازل حذو الشريط السفلي
          // بدل ما يطفو فوقه بمسافة كبيرة. bottom يمركز الـpill عمودياً
          // مع الـbottom nav (nav=64px، pill=44px، فمركزه = safeArea +
          // Sp.sm + (64-44)/2 = safeArea + Sp.sm + 10). يظهر كجزء من
          // التنقّل بدل عنصر عائم منفصل.
          Positioned(
            right: Sp.lg,
            bottom: Sp.sm + MediaQuery.paddingOf(context).bottom + 10,
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
    Theme.of(context); // theme-dep (dark-mode)
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
                label: 'nav.home'.tr(),
                slotWidth: slotWidth,
                selected: current == 0,
                onTap: () => _select(0),
              ),
              _TabSlot(
                icon: Icons.people_alt_rounded,
                label: 'nav.subscribers'.tr(),
                slotWidth: slotWidth,
                selected: current == 1,
                onTap: () => _select(1),
              ),
              _FabSlot(slotWidth: slotWidth, onTap: onFabTap),
              _TabSlot(
                icon: Icons.insert_chart_rounded,
                label: 'nav.reports'.tr(),
                slotWidth: slotWidth,
                selected: current == 2,
                onTap: () => _select(2),
              ),
              _TabSlot(
                // مطلب 2026-06-10: 'قوائم أخرى' بدل 'الضبط' لأن
                // الـtab صار يعرض المديولات الإضافية لا الإعدادات.
                // الإعدادات الفعلية انتقلت لزر الـgear بالشريط العلوي.
                icon: Icons.apps_rounded,
                label: 'nav.more'.tr(),
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
    Theme.of(context); // theme-dep (dark-mode)
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
    Theme.of(context); // theme-dep (dark-mode)
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
    Theme.of(context); // theme-dep (dark-mode)
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
  const _QuickAddSheet({required this.rootContext});

  /// MainShell's context — stays alive after this sheet pops, so
  /// callbacks that open follow-up sheets (picker → activate, etc.)
  /// still have a mounted context to push from.
  final BuildContext rootContext;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    // مطلب 2026-06-12: لو الموظف ما عنده ولا صلاحية للـquick-add،
    // empty state بدل صفحة عنوان فارغة محرجة.
    final hasAny = Perms.hasAny(const [
      'subscribers.add',
      'subscribers.activate',
      'subscribers.extend',
      'subscribers.pay_debt',
      'subscribers.add_debt',
      'reports.expenses',
    ]);
    return Padding(
      padding: const EdgeInsets.fromLTRB(Sp.lg, 0, Sp.lg, Sp.huge),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('dashboard.quick_add'.tr(),
              style: AppType.title(color: AppColors.textHi)
                  .copyWith(fontSize: 18)),
          const SizedBox(height: Sp.lg),
          if (!hasAny)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: Sp.lg),
              child: Center(
                child: Text(
                  'dashboard.quick_add_empty'.tr(),
                  style: AppType.muted().copyWith(fontSize: 13),
                ),
              ),
            ),
          // مطلب 2026-06-10: الترتيب = إضافة مشترك → تجديد اشتراك →
          // تسديد دين → إضافة دين → إضافة صرفية. مطلب 2026-06-11:
          // كل بند يختفي إذا الموظف ما عنده الصلاحية المناسبة بدل
          // ما يطلع له خطأ "غير مسموح" بعد الضغط.
          if (Perms.has('subscribers.add'))
            _QuickItem(
              icon: Icons.person_add_rounded,
              color: const Color(0xFF3B82F6),
              title: 'dashboard.add_subscriber'.tr(),
              subtitle: 'dashboard.add_subscriber_hint'.tr(),
              onTap: () => showAddSubscriberSheet(rootContext),
            ),
          if (Perms.hasAny(['subscribers.activate', 'subscribers.extend']))
            _QuickItem(
              icon: Icons.bolt_rounded,
              color: AppColors.brand,
              title: 'dashboard.renew_sub'.tr(),
              subtitle: 'dashboard.renew_sub_hint'.tr(),
              onTap: () async {
                final picked = await showSubscriberPickerSheet(
                  rootContext,
                  title: 'dashboard.renew_sub'.tr(),
                );
                if (picked != null && rootContext.mounted) {
                  await showActivateSheet(rootContext, picked);
                }
              },
            ),
          if (Perms.has('subscribers.pay_debt'))
            _QuickItem(
              icon: Icons.payments_rounded,
              color: const Color(0xFF14B8A6),
              title: 'dashboard.pay_debt'.tr(),
              subtitle: 'dashboard.pay_debt_hint'.tr(),
              onTap: () async {
                final picked = await showSubscriberPickerSheet(
                  rootContext,
                  title: 'dashboard.pay_debt'.tr(),
                  debtorsOnly: true,
                );
                if (picked != null && rootContext.mounted) {
                  await showPayDebtSheet(rootContext, picked);
                }
              },
            ),
          if (Perms.has('subscribers.add_debt'))
            _QuickItem(
              icon: Icons.account_balance_wallet_rounded,
              color: const Color(0xFFE08F2D),
              title: 'dashboard.add_debt'.tr(),
              subtitle: 'dashboard.add_debt_hint'.tr(),
              onTap: () async {
                final picked = await showSubscriberPickerSheet(
                  rootContext,
                  title: 'dashboard.add_debt'.tr(),
                );
                if (picked != null && rootContext.mounted) {
                  await showAddDebtSheet(rootContext, picked);
                }
              },
            ),
          if (Perms.has('reports.expenses'))
            _QuickItem(
              icon: Icons.receipt_long_rounded,
              color: const Color(0xFF8B5CF6),
              title: 'dashboard.add_expense'.tr(),
              subtitle: 'dashboard.add_expense_hint'.tr(),
              onTap: () => showAddExpenseSheet(rootContext),
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
    this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  /// Defaults to closing the sheet — items without a wired action
  /// still let the admin dismiss the sheet by tapping.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          Navigator.of(context).pop();
          onTap?.call();
        },
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
