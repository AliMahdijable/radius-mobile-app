import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../api/dashboard_api.dart';
import '../../api/view_scope_api.dart';
import '../../services/view_scope_events.dart';
import '../../models/dashboard.dart';
import '../../services/alerts_service.dart';
import '../../services/app_resumed_signal.dart';
import '../../services/auth_storage.dart';
import '../../services/dashboard_cache.dart';
import '../../services/inbox_service.dart';
import '../../services/permissions_service.dart';
import '../../services/subscriber_events.dart';
import '../accounts/accounts_screen.dart';
import '../notifications/inbox_screen.dart';
import '../reports/activity_log_report_screen.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import '../subscribers/widgets/filter_chips_bar.dart';
import '../settings_screen.dart';
import 'widgets/hero_revenue_card.dart';
import 'widgets/recent_activities.dart';
import 'widgets/reconnect_banner.dart';
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
  DebtorsResult? _debtorsLive;
  WalletResult? _walletLive;

  bool _waLoaded = false;
  bool _activationsLoaded = false;
  bool _debtorsLoaded = false;
  bool _walletLoaded = false;

  /// مطلب 2026-06-12: debounce — أي حركة في صفحة ثانية بتحفّز
  /// notifyChange. لو الـadmin يضغط حفظ + إغلاق + يفتح dashboard،
  /// أكثر من حدث في ثانية واحدة كان يطلق refreshLive كل واحد منهم.
  /// نوقف الـtimer ونعيد جدولته فيتم تنفيذ refresh واحد فقط.
  Timer? _refreshDebounce;

  /// أقسام الرئيسيّة المخفيّة لهذا الحساب.
  ///
  /// ⚠️ تُقرأ **قبل** الجلب لا بعده: الغاية أن يسقط نداء القسم المخفيّ
  /// لا أن يُجلب ثمّ يُرمى. من يُخفي الإيرادات والنشاطات يسقط عنه
  /// نداءان من خمسة عند كلّ إقلاع.
  Set<String> _hiddenSections = <String>{};
  bool _sectionsLoaded = false;

  /// ⚠️ قبل وصول التفضيلات نعتبر كلّ شيء ظاهراً — وإلّا ومضت الشاشة
  /// فارغةً ثمّ امتلأت. والخطأ في هذا الاتّجاه أرحم: قسمٌ يظهر لحظةً
  /// أهون من شاشة تبدو معطوبة عند كلّ فتح.
  bool _shown(String key) => !_sectionsLoaded || !_hiddenSections.contains(key);

  /// ⚠️ لا `_refreshLive` هنا: `initState` يستدعيه بعدها مباشرةً،
  /// وإضافته كانت تُنتج جولتَي جلب لكلّ فتح (بلاغ 2026-09-01: أربع
  /// موجات نداءات متتالية في السجلّ).
  Future<void> _loadSections() async {
    final r = await ViewScopeApi.load();
    if (!mounted) return;
    setState(() {
      _hiddenSections = {
        for (final s in r.sections)
          if (s.hidden) s.key
      };
      _sectionsLoaded = true;
    });
  }

  /// تبدّل نطاق العرض في شاشة الإعدادات — أعِد قراءة الأقسام ثمّ اجلب.
  ///
  /// بلا هذا تبقى الرئيسيّة على ما قرأته عند إنشائها: هي مركَّبة في
  /// `IndexedStack` طوال الجلسة، فلا `initState` ثانٍ يُنقذها.
  Future<void> _onScopeChanged() async {
    if (!mounted) return;
    await _loadSections();
    if (!mounted) return;
    _refreshLive(silent: true);
  }

  @override
  void initState() {
    super.initState();
    _loadIdentity();
    // Cache-first: hydrate KPIs from SharedPreferences BEFORE the live
    // fetch fires. الـSpinner ما يظهر لو عندنا بيانات محفوظة — يظهر
    // فقط أوّل مرّة أو بعد logout. الـlive fetch يشتغل بالتوازي ويحدّث
    // الأرقام لمّا يوصل.
    _hydrateFromCache();
    // ⚠️ الأقسام **قبل** أوّل جلب لا بعده: الغاية إسقاط نداء القسم
    // المخفيّ، وجلبٌ يسبق معرفة التفضيلات يُطلق النداءات كلّها ثمّ
    // يُخفي نتائجها — وهو نقيض الميزة. والكاش يرسم الأرقام القديمة
    // فوراً فلا يرى المستخدم انتظاراً.
    _loadSections().then((_) {
      if (mounted) _refreshLive(silent: false);
    });
    // Re-fetch dashboard KPIs whenever any subscriber operation
    // anywhere in the app succeeds (activate/extend/disconnect/bulk
    // toggle/delete). Matches v1's pattern of state-driven refresh.
    SubscriberEvents.dataChanged.addListener(_onDataChanged);
    // إعادة الجلب لمّا التطبيق يرجع من الخلفيّة — بدون هذا الـlistener،
    // إذا المدير خرج للـHome ورجع بعد فترة، الـKPIs تبقى قديمة لأن
    // IndexedStack يحتفظ بالـDashboard مركّبة وinitState ما ينطلق ثانية.
    AppResumedSignal.tick.addListener(_onAppResumed);
    ViewScopeEvents.changed.addListener(_onScopeChanged);
  }

  void _onDataChanged() {
    if (!mounted) return;
    _scheduleSilentRefresh();
  }

  void _onAppResumed() {
    if (!mounted) return;
    _scheduleSilentRefresh();
  }

  void _scheduleSilentRefresh() {
    // Debounce — اجمع موجة الأحداث في refresh واحد. يعالج أيضاً حالة
    // resume + dataChanged بتوقيت متقارب (مثلاً مدير رجع للتطبيق بعد
    // بضع ثواني من تفعيل).
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
    AppResumedSignal.tick.removeListener(_onAppResumed);
    ViewScopeEvents.changed.removeListener(_onScopeChanged);
    super.dispose();
  }

  Future<void> _loadIdentity() async {
    final name = await AuthStorage.readDisplayName();
    if (!mounted) return;
    setState(() => _displayName = name ?? '');
  }

  /// Read the last-known KPI values from SharedPreferences and paint
  /// them right away so the user sees numbers instead of spinners while
  /// the network catches up. Non-fatal on failure.
  Future<void> _hydrateFromCache() async {
    try {
      // كاش SAS4 لم يعد يُقرأ: الأرقام كلّها تُشتقّ من قائمة المشتركين
      // منذ حذف النداء المباشر (2026-08-31).
      final cachedWallet = await DashboardCache.readWallet();
      if (!mounted) return;
      setState(() {
        if (cachedWallet != null) {
          _walletLive = cachedWallet;
          _walletLoaded = true;
        }
      });
    } catch (_) {/* silent — cache is best-effort */}
  }

  /// مهلة تبريد بين موجتَي تحديث صامت.
  ///
  /// للرئيسيّة أربعة مصادر تحديث (الإقلاع · العودة من الخلفيّة ·
  /// تغيّر بيانات مشترك · تبدّل نطاق العرض)، ولو تلاقى اثنان انطلقت
  /// موجتا نداءات متطابقة — وهو ما ظهر في سجلّ 2026-09-01.
  ///
  /// ⚠️ تبريد **لا** قفل «جلب جارٍ»: القفل الحقيقيّ يعلق أبداً إن تعلّق
  /// طلب واحد، فيُجمّد كلّ تحديث لاحق. والتبريد يُفلت وحده.
  /// والسحب-للتحديث معفى — المستخدم طلبه صراحةً وينتظر مؤشّره.
  bool _cooling = false;

  Future<void> _refreshLive({bool silent = false}) async {
    if (silent) {
      if (_cooling) return;
      _cooling = true;
      Future.delayed(const Duration(seconds: 3), () => _cooling = false);
    }
    // silent=false (initial mount + pull-to-refresh): نُسقط الـloaded
    //   flags فتظهر spinners حتى البيانات الجديدة.
    // silent=true (event-driven refresh): نبقي القيم القديمة معروضة
    //   حتى الـAPI يرد بالـlatest، يجنّب وميض 0 → القيمة الجديدة.
    if (!silent) {
      setState(() {
        _waLoaded = false;
        _activationsLoaded = false;
        _debtorsLoaded = false;
        _walletLoaded = false;
      });
    }
    // Independent fetches — each updates its loaded flag as soon as it
    // returns so cards can light up one by one instead of all-or-nothing.
    //
    // Safety net: كل fetch مغطّى بـtimeout 20 ثانية + catchError. حتى لو
    // Dio hang (network drop، auth refresh loop، backend slow query)،
    // الـFuture ما يعلق للأبد. كارت الـUI يصير إلى error state
    // بدل spinner ثابت. أُضيف بعد تقرير المدير 2026-07-22: كارت
    // البطل + المدينون كانوا يعلقون على spinner لدقائق.
    const kMaxLoad = Duration(seconds: 20);

    // UX guard: على silent refresh (event-driven أو resume)، لو fetch
    // فشل (r==null) وعندنا بيانات جيّدة سابقة، ما نستبدلها بـerror state.
    // يمنع flash "فشل جلب" العابر على شبكات ضعيفة. Pull-to-refresh
    // (silent==false) يعرض الحقيقة دائماً.
    if (_shown('wa_banner')) {
      DashboardApi.fetchWhatsAppStatus()
          .timeout(kMaxLoad, onTimeout: () => null)
          .catchError((_) => null)
          .then((r) {
        if (!mounted) return;
        if (silent && r == null && _waLive != null) return;
        setState(() {
          _waLive = r;
          _waLoaded = true;
        });
      });
    }
    if (_shown('activities')) {
      DashboardApi.fetchDailyActivations()
          .timeout(kMaxLoad, onTimeout: () => null)
          .catchError((_) => null)
          .then((r) {
        if (!mounted) return;
        if (silent && r == null && _activationsLive != null) return;
        setState(() {
          _activationsLive = r;
          _activationsLoaded = true;
        });
      });
    }
    // ⚠️ نداء SAS4 المباشر حُذف (2026-08-31).
    //
    // كان يطلق **خمسة** طلبات هاتف→reseller-supernet.net في كلّ تحديث،
    // ولا يُقرأ منها إلّا `total`. والأربعة الباقية — active · expired
    // · online · balance — تُجلب وتُحلَّل وتُخزَّن ثمّ **تُهمَل**:
    // الثلاثة الأولى تُحسب محلّيّاً من القائمة (التعليق تحت يشرح لماذا:
    // widget الـactive في SAS4 يُرجع offline=0 على بعض الحسابات)،
    // والرصيد يأتي من /api/v2/admin-widgets.
    //
    // ثمّ صار `total` نفسه ضارّاً: يتجاوز خادمنا فلا يعرف «نطاق العرض»،
    // فيعرض إجمالي المستأجر كلّه فوق قائمة مرشَّحة.
    //
    // ومعه سقط مبرّر تأخير الـ800ms أدناه — كان موضوعاً ليترك النطاق
    // الترددّي لهذه النداءات الميتة.
    // Defer debtors 800ms so the faster widgets (SAS4/wallet/finance)
    // grab bandwidth first. `subscribers/with-phones` is the heaviest
    // fetch (loads every subscriber's row + notes + package) — running
    // it in parallel with the light widgets was starving them.
    // On silent refresh we still fire immediately (no cold start).
    Future.delayed(Duration.zero, () {
      if (!mounted) return;
      DashboardApi.fetchDebtors()
          .timeout(kMaxLoad, onTimeout: () => null)
          .catchError((_) => null)
          .then((r) {
        if (!mounted) return;
        if (silent && r == null && _debtorsLive != null) return;
        setState(() {
          _debtorsLive = r;
          _debtorsLoaded = true;
        });
        // نُحدّث عدّاد الجرس (near-expiry + expired-today) من نفس القائمة
        // اللي fetchDebtors شغّلها تواً — بدون طلب شبكة إضافي.
        AlertsService.refresh();
      });
    });
    // ⚠️ التبويب على النداء لا على العرض: الغاية إسقاط الطلب لا
    // إخفاء نتيجته. القسم المخفيّ يجب ألّا يكلّف شبكةً أصلاً.
    if (_shown('wallet')) {
      DashboardApi.fetchWallet()
          .timeout(kMaxLoad, onTimeout: () => null)
          .catchError((_) => null)
          .then((r) {
        if (!mounted) return;
        if (silent && r == null && _walletLive != null) return;
        setState(() {
          _walletLive = r;
          _walletLoaded = true;
        });
        if (r != null) {
          DashboardCache.saveWallet(r); // persist for next cold start
        }
      });
    }
  }

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 5) return 'dashboard.welcome_evening'.tr();
    if (h < 12) return 'dashboard.welcome_morning'.tr();
    if (h < 17) return 'dashboard.welcome_evening_light'.tr();
    return 'dashboard.welcome_evening'.tr();
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
      // 🐛 بلاغ 2026-08-31: بعد إخفاء مدير فرعي صارت الحلقة تقول 384
      // والقائمة تقول 156 — وهو بالضبط الرقمان المتناقضان اللذان
      // وُجدت ميزة «نطاق العرض» لمنعهما.
      //
      // السبب أنّ `_sas4Live.total` يأتي من نداء مباشر هاتف→SAS4
      // يتجاوز خادمنا كلّيّاً، فلا يعرف شيئاً عن الإخفاء. بينما
      // active/online/expired تُحسب محلّيّاً من القائمة **المرشَّحة**.
      //
      // مصدر واحد لكلّ الأرقام: القائمة نفسها.
      total: d.totalSubs,
      active: d.active,
      online: d.online,
      offline: d.offline,
      expired: d.expired,
      nearExpiry: d.nearExpiry,
      onlineNoPlan: d.onlineNoPlan,
      disabled: d.disabled,
    );
  }

  WhatsAppStatus? get _waStatus {
    if (!_waLoaded) return null;
    if (_waLive == null) return null;
    return WhatsAppStatus(
      connected: _waLive!.connected,
      phone: _waLive!.phone,
      needsPairing: _waLive!.needsPairing,
      sendingRestricted: _waLive!.sendingRestricted,
      cappingWarning: _waLive!.cappingWarning,
    );
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
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
                // ⚠️ قراءةٌ مقصودة لا زائدة: `paddingOf` تبعيّة
                // **مقصورة على الحشوة**، فالشاشة لا تُعاد بناؤها عند
                // تغيير سلّم الخطّ. قراءة `textScalerOf` هنا هي ما
                // يُنشئ تلك التبعيّة. من «يُحسّنها» بحذفها يُعيد العطل.
                textScale: MediaQuery.textScalerOf(context).scale(1),
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
                  // أعلى كلّ شيء عمداً: انقطاع الجلسة يوقف كلّ تنبيهات
                  // المشتركين وفواتيرهم، فلا يجوز أن يُقرأ بعد الأرقام.
                  if (_shown('wa_banner'))
                    ReconnectBanner(
                      status: _waStatus,
                      onDone: _refreshLive,
                    ),
                  if (_shown('subscribers'))
                    SubscribersCard(
                      stats: _subscribersStats,
                      onOpen: widget.onOpenSubscribers,
                    )
                        .animate()
                        .fadeIn(duration: const Duration(milliseconds: 280))
                        .slideY(begin: 0.03, end: 0),
                  const SizedBox(height: Sp.md),
                  if (_shown('wallet'))
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
                  // الكارت يجلب بنفسه (`reports/finance`)، فعدم بنائه
                  // يُسقط نداءه بلا تبويبٍ إضافيّ.
                  if (_shown('revenue'))
                    const HeroRevenueCard()
                        .animate()
                      .fadeIn(
                        delay: const Duration(milliseconds: 160),
                        duration: const Duration(milliseconds: 280),
                      )
                      .slideY(begin: 0.03, end: 0),
                  if (_shown('activities'))
                    SectionHeader(
                      label: !_activationsLoaded
                        ? 'dashboard.recent_activity_label'.tr()
                        : _activationsLive == null
                            ? 'dashboard.recent_activity_fetch_failed'.tr()
                            : 'dashboard.recent_activity_label'.tr(),
                    trailingLabel: 'dashboard.view_all'.tr(),
                    // مطلب المستخدم 2026-07-12: زر "عرض الكل" ينقل
                    // لسجل النشاط الكامل. الـPermissionGate يتأكد من
                    // reports.activity_log؛ لو الموظف بلا صلاحية يرى
                    // شاشة رفض بدل الشاشة الفارغة.
                    onTrailingTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const ActivityLogReportScreen(),
                      ),
                    ),
                  ),
                  if (_shown('activities'))
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
                  // ⚠️ لو أُخفي كلّ شيء لا تُترك الشاشة بيضاء: المدير
                  // لن يعرف أنّه هو من أخفاها، وسيظنّها معطوبة.
                  if (_sectionsLoaded && _hiddenSections.length >= 5)
                    const _AllHidden(),
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
    Theme.of(context); // theme-dep (dark-mode)
    return Container(
      height: 120,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.lg),
        border: Border.all(color: AppColors.border),
      ),
      child: Center(
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
    Theme.of(context); // theme-dep (dark-mode)
    return Container(
      padding: const EdgeInsets.symmetric(vertical: Sp.huge, horizontal: Sp.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.lg),
        border: Border.all(color: AppColors.dangerSoftBorder),
      ),
      child: Column(
        children: [
          Icon(LucideIcons.triangleAlert, color: AppColors.error, size: 28),
          const SizedBox(height: Sp.sm),
          Text('dashboard.recent_fetch_failed'.tr(),
              style: AppType.label(color: AppColors.error)
                  .copyWith(fontSize: 13, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text('dashboard.pull_to_retry'.tr(),
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
    Theme.of(context); // theme-dep (dark-mode)
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
          Text('dashboard.no_activity_today'.tr(),
              style: AppType.label(color: AppColors.textMid)
                  .copyWith(fontSize: 14, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text('dashboard.activity_will_show'.tr(),
              style: AppType.muted(color: AppColors.textLow)
                  .copyWith(fontSize: 12.5, fontWeight: FontWeight.w500),
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
    required this.textScale,
  }) : isDark = AppColors.isDark;

  final String displayName;
  final String greeting;
  final WhatsAppStatus? whatsApp;
  final bool waLoaded;
  final double topInset;

  /// سلّم خطّ النظام وقت الإنشاء (مقيَّد 0.9–1.2 في main.dart).
  final double textScale;

  // Snapshot of the global dark-mode flag at delegate-creation time.
  // shouldRebuild compares this so a theme switch (with everything
  // else unchanged) still triggers a repaint — without it the pinned
  // header stays in the old palette while the rest of the scaffold
  // flips. مطلب 2026-06-11.
  final bool isDark;

  // Tightened from 108 → 86 so there's no dead space between the
  // WhatsApp chip and the subscribers card below the header.
  //
  // 🐛 صار محسوباً لا ثابتاً (2026-08-31): الارتفاع كان 86 مهما كبّر
  // المستخدم خطّ النظام، فالنصّ ينمو داخل علبة لا تنمو — فيُقصّ اسم
  // المدير وتُبتر شارة الواتساب.
  //
  // ⚠️ ولا يُضرَب الـ86 كلّه في السلّم: منه 28 نقطة حشوات وحدود
  // **لا تكبر مع الخطّ**. ضربُ المجموع يحجز 103 حيث تكفي 94 عند 1.2،
  // فيعود الفراغ الميّت الذي أزاله 0afcbbe حين شُدَّ الرأس 108 → 86.
  static const double _textHeight = 58;
  static const double _fixedChrome = 28;
  double get _contentHeight => _textHeight * textScale + _fixedChrome;

  /// 2026-08-30: الترويسة كانت مثبَّتة بلا انكماش (minExtent == maxExtent)
  /// فتحجز 86px + الشقّ العلوي طوال التمرير. الآن تنكمش إلى الاسم
  /// والأيقونات وحدها: التحيّة وشارة واتساب معلومتان تُقرآن مرّة عند
  /// الفتح ولا حاجة لبقائهما معلّقتين فوق كلّ تمريرة.
  // والمطويّ كذلك: منه 10 نقاط حشوة ثابتة.
  static const double _collapsedText = 34;
  static const double _collapsedChrome = 10;
  double get _collapsedHeight => _collapsedText * textScale + _collapsedChrome;

  @override
  double get minExtent => _collapsedHeight + topInset;
  @override
  double get maxExtent => _contentHeight + topInset;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    Theme.of(
        context); // theme-dep (dark-mode) — delegate.build skipped by injector
    // نسبة الانكماش: 0 مفرودة · 1 مطويّة بالكامل.
    final t = (shrinkOffset / (maxExtent - minExtent)).clamp(0.0, 1.0);
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
                // ⚠️ `ClipRect` حول `Align` ضروريّ: `heightFactor` يقصّ
                // الارتفاع المحجوز لكنّه لا يمنع الرسم خارجه، فبدون
                // القصّ يطفو النصّ على ما تحته أثناء الطيّ.
                ClipRect(
                  child: Align(
                    alignment: AlignmentDirectional.topStart,
                    heightFactor: 1 - t,
                    child: Opacity(
                      opacity: 1 - t,
                      child: Text(
                        greeting,
                        style: AppType.subtitle(color: AppColors.textMid)
                            .copyWith(
                                fontSize: 12.5, fontWeight: FontWeight.w500),
                      ),
                    ),
                  ),
                ),
                SizedBox(height: 2 * (1 - t)),
                Text(
                  displayName.isEmpty ? 'dashboard.hello'.tr() : displayName,
                  style: AppType.title(color: AppColors.textHi).copyWith(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                SizedBox(height: 6 * (1 - t)),
                ClipRect(
                  child: Align(
                    alignment: AlignmentDirectional.topStart,
                    heightFactor: 1 - t,
                    child: Opacity(
                      opacity: 1 - t,
                      child: _WAStatusChip(status: whatsApp, loaded: waLoaded),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // 2026-08-26: أيقونة "الصفحات" — التبديل السريع بين حسابات
          // المدراء الفرعيّين. طلب المستخدم أن تكون جنب جرس الإشعارات
          // للوصول السريع. محكومة بـmanagers.view.
          if (Perms.has('managers.view')) ...[
            _IconChip(
              icon: Icons.swap_horiz_rounded,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const AccountsScreen(),
                ),
              ),
            ),
            const SizedBox(width: Sp.sm),
          ],
          // Bell badge: FCM unread + مشتركين في خطر (near-expiry+expired-today).
          // نُدمج المصدرين حتى المستخدم يشوف رقم واحد يعبّر عن "شي يحتاج
          // انتباه". AlertsService.count يتحدّث تلقائياً من InboxScreen
          // بعد كل refresh.
          ValueListenableBuilder<int>(
            valueListenable: InboxService.changes,
            builder: (context, _, __) => ValueListenableBuilder<int>(
              valueListenable: AlertsService.count,
              builder: (context, alerts, __) => _IconChip(
                icon: Icons.notifications_none_rounded,
                badge: InboxService.unreadCount + alerts,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const InboxScreen(),
                  ),
                ),
              ),
            ),
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
      old.whatsApp?.phone != whatsApp?.phone ||
      old.whatsApp?.needsPairing != whatsApp?.needsPairing ||
      old.whatsApp?.sendingRestricted != whatsApp?.sendingRestricted ||
      old.whatsApp?.cappingWarning != whatsApp?.cappingWarning ||
      old.isDark != isDark ||
      // بلا هذين لا يُعاد بناء الرأس عند تدوير الجهاز (يتغيّر الشقّ
      // العلوي) ولا عند تغيير سلّم الخطّ — فيبقى بارتفاعه القديم بينما
      // محتواه تغيّر.
      old.topInset != topInset ||
      old.textScale != textScale;
}

class _WAStatusChip extends StatelessWidget {
  const _WAStatusChip({required this.status, required this.loaded});
  final WhatsAppStatus? status;
  final bool loaded;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    // خمس حالات بنغمة دلاليّة واحدة لكلٍّ. النغمة تحمل التعبئة
    // والخلفيّة والحدّ والنصّ معاً — كان الأربعة يُشتقّون من لون واحد
    // بـ`.withValues(.1)` و`.25`، وهو ما ينهار ليلاً.
    final AppTone tone;
    final String label;
    if (!loaded) {
      tone = AppTone.neutral;
      label = 'dashboard.wa_checking'.tr();
    } else if (status?.needsPairing == true) {
      tone = AppTone.warning;
      label = 'wa.needs_pairing'.tr();
    } else if (status?.sendingRestricted == true) {
      tone = AppTone.danger;
      label = 'wa.connected_limited'.tr();
    } else if (status?.cappingWarning == true) {
      tone = AppTone.warning;
      label = 'wa.outreach_warning'.tr();
    } else if (status?.connected == true) {
      tone = AppTone.success;
      label = 'dashboard.wa_connected'.tr();
    } else {
      tone = AppTone.danger;
      label = 'dashboard.wa_disconnected'.tr();
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Sp.sm, vertical: 4),
      decoration: BoxDecoration(
        color: tone.softBg,
        borderRadius: BorderRadius.circular(R.pill),
        border: Border.all(color: tone.softBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!loaded)
            SizedBox(
              width: 10,
              height: 10,
              child:
                  CircularProgressIndicator(strokeWidth: 1.4, color: tone.fill),
            )
          else
            Container(
              width: 7,
              height: 7,
              decoration:
                  BoxDecoration(color: tone.fill, shape: BoxShape.circle),
            ),
          const SizedBox(width: 6),
          // 🐛 كان نصّاً عارياً بلا `maxLines` ولا `overflow`، وهو ابن
          // `Row` بلا flex — فيُقصّ قصّاً صلباً (`clip`) بلا «…» حين
          // يضيق الرأس.
          //
          // والمقصوص هنا ليس زينة: هذه حبّة حالة الواتساب، ونصّها قد
          // يكون «جلسة واتساب تحتاج إعادة ربط» — أي التحذير الذي يخبر
          // المدير لماذا توقّف الإرسال. بترُه صامتاً يعني مديراً يظنّ
          // النظام سليماً ورسائله لا تصل.
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppType.muted(color: tone.onSoft).copyWith(fontSize: 11),
            ),
          ),
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
    Theme.of(context); // theme-dep (dark-mode)
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
                color: AppColors.errorFill,
                borderRadius: BorderRadius.circular(R.pill),
                border: Border.all(color: AppColors.bg, width: 2),
              ),
              alignment: Alignment.center,
              child: Text('$badge',
                  style: AppType.muted(color: AppColors.onBrand)
                      .copyWith(fontSize: 10.5, height: 1)),
            ),
          ),
      ],
    );
  }
}

/// كلّ الأقسام مخفيّة — لا تُترك الشاشة بيضاء.
class _AllHidden extends StatelessWidget {
  const _AllHidden();

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Sp.mega),
      child: Column(
        children: [
          Icon(LucideIcons.eyeOff, size: 32, color: AppColors.textLow),
          const SizedBox(height: Sp.sm),
          Text(
            'كلّ أقسام الرئيسيّة مخفيّة',
            style: AppType.label(color: AppColors.textMid),
          ),
          const SizedBox(height: 4),
          Text(
            'أعِدها من الإعدادات ← نطاق العرض',
            style: AppType.micro(color: AppColors.textLow),
          ),
        ],
      ),
    );
  }
}
