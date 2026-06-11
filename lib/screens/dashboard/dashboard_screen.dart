import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../api/dashboard_api.dart';
import '../../api/sas4_api.dart';
import '../../models/dashboard.dart';
import '../../services/auth_storage.dart';
import '../../services/subscriber_events.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import '../subscribers/widgets/filter_chips_bar.dart';
import '../settings_screen.dart';
import 'widgets/hero_revenue_card.dart';
import 'widgets/recent_activities.dart';
import 'widgets/section_header.dart';
import 'widgets/stats_grid.dart';
import 'widgets/subscribers_card.dart';

/// Dashboard with a SLIVER-pinned header — header stays on screen while
/// the body scrolls underneath. All data is LIVE — there are no mock
/// fallbacks anywhere. When data hasn't loaded yet each card shows a
/// loading shimmer; when a fetch fails the card shows an explicit
/// error state, never invented numbers.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key, this.onOpenSubscribers});

  /// Set by MainShell — when any dashboard KPI tile is tapped, calls
  /// this with the matching filter so the shell can switch tabs and
  /// pre-apply the filter on the subscribers screen.
  final ValueChanged<SubscriberFilter?>? onOpenSubscribers;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  String _displayName = '';
  WhatsAppStatusResult? _waLive;
  DailyActivationsResult? _activationsLive;
  Sas4Stats? _sas4Live;
  DebtorsResult? _debtorsLive;
  WalletResult? _walletLive;

  bool _waLoaded = false;
  bool _activationsLoaded = false;
  bool _sas4Loaded = false;
  bool _debtorsLoaded = false;
  bool _walletLoaded = false;

  /// مطلب 2026-06-12: debounce — أي حركة في صفحة ثانية بتحفّز
  /// notifyChange. لو الـadmin يضغط حفظ + إغلاق + يفتح dashboard،
  /// أكثر من حدث في ثانية واحدة كان يطلق refreshLive كل واحد منهم.
  /// نوقف الـtimer ونعيد جدولته فيتم تنفيذ refresh واحد فقط.
  Timer? _refreshDebounce;

  @override
  void initState() {
    super.initState();
    _loadIdentity();
    _refreshLive(silent: false);
    // Re-fetch dashboard KPIs whenever any subscriber operation
    // anywhere in the app succeeds (activate/extend/disconnect/bulk
    // toggle/delete). Matches v1's pattern of state-driven refresh.
    SubscriberEvents.dataChanged.addListener(_onDataChanged);
  }

  void _onDataChanged() {
    if (!mounted) return;
    // Debounce — اجمع موجة الأحداث في refresh واحد.
    _refreshDebounce?.cancel();
    _refreshDebounce = Timer(const Duration(milliseconds: 700), () {
      if (!mounted) return;
      // silent: true — نُبقي الكارت بالقيم القديمة بينما البيانات
      // الجديدة تجيب. يمنع وميض القيم 0 → القيمة الحقيقية اللي كان
      // يُعطي إحساس "ببقى يحمل" بعد كل انتقال بين الصفحات.
      _refreshLive(silent: true);
    });
  }

  @override
  void dispose() {
    _refreshDebounce?.cancel();
    SubscriberEvents.dataChanged.removeListener(_onDataChanged);
    super.dispose();
  }

  Future<void> _loadIdentity() async {
    final name = await AuthStorage.readDisplayName();
    if (!mounted) return;
    setState(() => _displayName = name ?? '');
  }

  Future<void> _refreshLive({bool silent = false}) async {
    // silent=false (initial mount + pull-to-refresh): نُسقط الـloaded
    //   flags فتظهر spinners حتى البيانات الجديدة.
    // silent=true (event-driven refresh): نبقي القيم القديمة معروضة
    //   حتى الـAPI يرد بالـlatest، يجنّب وميض 0 → القيمة الجديدة.
    if (!silent) {
      setState(() {
        _waLoaded = false;
        _activationsLoaded = false;
        _sas4Loaded = false;
        _debtorsLoaded = false;
        _walletLoaded = false;
      });
    }
    // Independent fetches — each updates its loaded flag as soon as it
    // returns so cards can light up one by one instead of all-or-nothing.
    DashboardApi.fetchWhatsAppStatus().then((r) {
      if (!mounted) return;
      setState(() {
        _waLive = r;
        _waLoaded = true;
      });
    });
    DashboardApi.fetchDailyActivations().then((r) {
      if (!mounted) return;
      setState(() {
        _activationsLive = r;
        _activationsLoaded = true;
      });
    });
    Sas4Api.fetchAll().then((r) {
      if (!mounted) return;
      setState(() {
        _sas4Live = r;
        _sas4Loaded = true;
      });
    });
    DashboardApi.fetchDebtors().then((r) {
      if (!mounted) return;
      setState(() {
        _debtorsLive = r;
        _debtorsLoaded = true;
      });
    });
    DashboardApi.fetchWallet().then((r) {
      if (!mounted) return;
      setState(() {
        _walletLive = r;
        _walletLoaded = true;
      });
    });
  }

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 5) return 'مساء الخير';
    if (h < 12) return 'صباح الخير';
    if (h < 17) return 'مساء النور';
    return 'مساء الخير';
  }

  SubscribersStats? get _subscribersStats {
    if (!_debtorsLoaded) return null;
    if (_debtorsLive == null) return null;
    // مطلب 2026-06-11: نستعمل أرقام محسوبة محلياً من قائمة المشتركين
    // (مثل v1 sas4OfflineCount = enriched.where(isOffline).length). الـ
    // SAS4 widget endpoints أحياناً ترجع active=online فيطلع offline=0
    // حتى لو في عدد كبير من المشتركين غير المتصلين. الـloop المحلي
    // يطابق predicate v1 (isOnline / isOffline / isExpired) بدقة.
    final d = _debtorsLive!;
    return SubscribersStats(
      total: _sas4Live?.total ?? d.totalSubs,
      active: d.active,
      online: d.online,
      offline: d.offline,
      expired: d.expired,
      nearExpiry: d.nearExpiry,
    );
  }

  WhatsAppStatus? get _waStatus {
    if (!_waLoaded) return null;
    if (_waLive == null) return null;
    return WhatsAppStatus(
      connected: _waLive!.connected,
      phone: _waLive!.phone,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: RefreshIndicator(
        color: AppColors.brand,
        onRefresh: () async {
          await Future.wait([_loadIdentity(), _refreshLive()]);
        },
        child: CustomScrollView(
          slivers: [
            SliverPersistentHeader(
              pinned: true,
              delegate: _PinnedHeaderDelegate(
                displayName: _displayName,
                greeting: _greeting(),
                whatsApp: _waStatus,
                waLoaded: _waLoaded,
                topInset: MediaQuery.paddingOf(context).top,
              ),
            ),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                Sp.lg,
                4, // tightened from Sp.md so the subscribers card sits
                   // right under the header without dead space.
                Sp.lg,
                Sp.huge * 3 + MediaQuery.paddingOf(context).bottom,
              ),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  SubscribersCard(
                    stats: _subscribersStats,
                    onOpen: widget.onOpenSubscribers,
                  )
                      .animate()
                      .fadeIn(duration: const Duration(milliseconds: 280))
                      .slideY(begin: 0.03, end: 0),
                  const SizedBox(height: Sp.md),
                  StatsGrid(
                    wallet: _walletLoaded ? _walletLive : null,
                    debtors: _debtorsLoaded ? _debtorsLive : null,
                    onOpenDebtors: () => widget.onOpenSubscribers
                        ?.call(SubscriberFilter.debtors),
                  )
                      .animate()
                      .fadeIn(
                        delay: const Duration(milliseconds: 80),
                        duration: const Duration(milliseconds: 280),
                      )
                      .slideY(begin: 0.03, end: 0),
                  const SizedBox(height: Sp.md),
                  const HeroRevenueCard()
                      .animate()
                      .fadeIn(
                        delay: const Duration(milliseconds: 160),
                        duration: const Duration(milliseconds: 280),
                      )
                      .slideY(begin: 0.03, end: 0),
                  SectionHeader(
                    label: !_activationsLoaded
                        ? 'آخر النشاطات'
                        : _activationsLive == null
                            ? 'آخر النشاطات (تعذّر الجلب)'
                            : 'آخر النشاطات',
                    trailingLabel: 'اعرض الكل',
                    onTrailingTap: () {},
                  ),
                  if (!_activationsLoaded)
                    const _ActivitiesLoading()
                  else if (_activationsLive == null)
                    const _ActivitiesError()
                  else if (_activationsLive!.recent.isEmpty)
                    const _NoActivitiesYet()
                  else
                    RecentActivities(items: _activationsLive!.recent)
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

class _ActivitiesLoading extends StatelessWidget {
  const _ActivitiesLoading();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 120,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.lg),
        border: Border.all(color: AppColors.border),
      ),
      child: const Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(
            strokeWidth: 2.2,
            color: AppColors.brand,
          ),
        ),
      ),
    );
  }
}

class _ActivitiesError extends StatelessWidget {
  const _ActivitiesError();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: Sp.huge, horizontal: Sp.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.lg),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          const Icon(LucideIcons.triangleAlert,
              color: AppColors.error, size: 28),
          const SizedBox(height: Sp.sm),
          Text('تعذّر جلب آخر النشاطات',
              style: AppType.label(color: AppColors.error)
                  .copyWith(fontSize: 13, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text('اسحب للأسفل لإعادة المحاولة',
              style: AppType.muted(color: AppColors.textLow)
                  .copyWith(fontSize: 11, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

class _NoActivitiesYet extends StatelessWidget {
  const _NoActivitiesYet();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: Sp.huge, horizontal: Sp.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.lg),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Icon(LucideIcons.inbox, color: AppColors.textLow, size: 32),
          const SizedBox(height: Sp.sm),
          Text('لا توجد نشاطات اليوم',
              style: AppType.label(color: AppColors.textMid)
                  .copyWith(fontSize: 14, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text('سيظهر هنا أي تفعيل أو تمديد بمجرد حدوثه',
              style: AppType.muted(color: AppColors.textLow)
                  .copyWith(fontSize: 12, fontWeight: FontWeight.w500),
              textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

/// Pinned header. Renders the WhatsApp chip as a loading state while
/// the connection check is in flight (no fake 'connected' fallback).
class _PinnedHeaderDelegate extends SliverPersistentHeaderDelegate {
  _PinnedHeaderDelegate({
    required this.displayName,
    required this.greeting,
    required this.whatsApp,
    required this.waLoaded,
    required this.topInset,
  });

  final String displayName;
  final String greeting;
  final WhatsAppStatus? whatsApp;
  final bool waLoaded;
  final double topInset;

  // Tightened from 108 → 86 so there's no dead space between the
  // WhatsApp chip and the subscribers card below the header.
  static const double _contentHeight = 86;

  @override
  double get minExtent => _contentHeight + topInset;
  @override
  double get maxExtent => _contentHeight + topInset;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: AppColors.bg,
      padding: EdgeInsets.fromLTRB(Sp.lg, topInset + Sp.sm, Sp.lg, 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  greeting,
                  style: AppType.subtitle(color: AppColors.textMid)
                      .copyWith(fontSize: 12, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 2),
                Text(
                  displayName.isEmpty ? 'مرحباً' : displayName,
                  style: AppType.title(color: AppColors.textHi).copyWith(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                _WAStatusChip(status: whatsApp, loaded: waLoaded),
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
            // مطلب 2026-06-10: زر الإعدادات بالشريط العلوي يفتح
            // شاشة الإعدادات (الحساب / المظهر / واتساب / الطباعة /
            // الصلاحيات / السكون). الزر السفلي السابق "الضبط" انتقل
            // لاسم "قوائم اخرى" ويعرض المديولات الإضافية.
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const SettingsScreen(),
                fullscreenDialog: true,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  bool shouldRebuild(_PinnedHeaderDelegate old) =>
      old.displayName != displayName ||
      old.greeting != greeting ||
      old.waLoaded != waLoaded ||
      old.whatsApp?.connected != whatsApp?.connected ||
      old.whatsApp?.phone != whatsApp?.phone;
}

class _WAStatusChip extends StatelessWidget {
  const _WAStatusChip({required this.status, required this.loaded});
  final WhatsAppStatus? status;
  final bool loaded;

  @override
  Widget build(BuildContext context) {
    // 3 visual states: loading dot, connected (brand), disconnected (red).
    final Color c;
    final String label;
    if (!loaded) {
      c = AppColors.textMid;
      label = 'جارٍ التحقق…';
    } else if (status?.connected == true) {
      c = AppColors.brand;
      label = 'واتساب متصل';
    } else {
      c = AppColors.error;
      label = 'واتساب منقطع';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Sp.sm, vertical: 4),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(R.pill),
        border: Border.all(color: c.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!loaded)
            SizedBox(
              width: 10,
              height: 10,
              child: CircularProgressIndicator(strokeWidth: 1.4, color: c),
            )
          else
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(color: c, shape: BoxShape.circle),
            ),
          const SizedBox(width: 6),
          Text(label,
              style: AppType.muted(color: c).copyWith(fontSize: 11)),
        ],
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
              child: Text('$badge',
                  style: AppType.muted(color: Colors.white)
                      .copyWith(fontSize: 10, height: 1)),
            ),
          ),
      ],
    );
  }
}
