import 'dart:async';
import 'dart:ui' as ui;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../api/device_probe_api.dart';
import '../../api/subscribers_api.dart';
import '../../api/telegram_api.dart';
import '../../api/whatsapp_api.dart';
import '../../core/util/format.dart';
import '../../core/widgets/sheet_scaffold.dart';
import '../../models/subscriber.dart';
import '../../services/auth_storage.dart';
import '../../services/permissions_service.dart';
import '../../services/subscriber_events.dart';
import '../../core/widgets/design_sheet.dart';
import '../../core/widgets/voice_search_button.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import 'sheets/bulk_activate_sheet.dart';
import 'sheets/bulk_pay_debt_sheet.dart';
import 'sheets/pay_debt_sheet.dart';
import 'subscriber_detail_screen.dart';
import 'widgets/device_chip_micro.dart';
import 'widgets/filter_chips_bar.dart';
import 'widgets/sort_sheet.dart';
import 'sheets/location_sheets.dart';
import 'widgets/subscriber_card_v3.dart';

/// Default sort field + direction per filter — mirrors v1's
/// `_defaultSortByFilter`. Without this the 'قارب الانتهاء' chip
/// surfaced subscribers in random order; now it shows least-time-left
/// first, which is what admins actually want when triaging expiries.
const _defaultSortByFilter = <SubscriberFilter, (SortField, SortDirection)>{
  SubscriberFilter.all: (SortField.remainingDays, SortDirection.desc),
  SubscriberFilter.active: (SortField.remainingDays, SortDirection.desc),
  // Online filter: shortest session time first (just-connected → at
  // top). Subscribers without a session_time fall to the bottom via
  // the comparator's null handling.
  SubscriberFilter.online: (SortField.sessionTime, SortDirection.asc),
  SubscriberFilter.offline: (SortField.remainingDays, SortDirection.desc),
  SubscriberFilter.disabled: (SortField.username, SortDirection.asc),
  SubscriberFilter.expired: (SortField.expiration, SortDirection.desc),
  SubscriberFilter.debtors: (SortField.notes, SortDirection.asc),
  SubscriberFilter.nearExpiry: (SortField.remainingDays, SortDirection.asc),
  // "بدون نت" — الأكثر تخطّياً للانتهاء (الأقل remaining) أولاً حتى
  // الإدمن يشوف الأخطر (سحب طويل بدون اشتراك) قبل الحديث الانتهاء.
  SubscriberFilter.onlineNoPlan: (SortField.remainingDays, SortDirection.asc),
};

/// Subscribers list — v2 port of v1's screen with a modernized look.
/// Phase 1 covers: load, search (debounced), 8 filter chips with counts,
/// sort sheet, pagination, multi-select via long-press, bulk action bar
/// (toggle/delete wired to backend, renew deferred to Phase 5).
class SubscribersScreen extends StatefulWidget {
  const SubscribersScreen({super.key, this.filterCmd, this.isActive});

  /// هل هذا التبويب مرئيّ الآن؟ (يمرّرها `MainShell`)
  ///
  /// 🐛 تدقيق أداء 2026-08-31: الاستطلاع كان محروساً بـ`_appActive`
  /// وحدها — وهي دورة حياة **التطبيق** لا رؤية التبويب. فبمجرّد فتح
  /// المشتركين مرّة (ونقرة واحدة على أيّ عدّاد في الرئيسيّة تفتحها)
  /// يظلّ يستطلع بقيّة الجلسة مهما كان التبويب المعروض: ثلاثة طلبات
  /// بلا كاش كلّ خمس ثوانٍ = 36 في الدقيقة على شبكة خلويّة، لشاشة
  /// لا يراها أحد.
  final ValueListenable<bool>? isActive;

  /// Filter command from MainShell. When dashboard KPIs are tapped the
  /// ValueNotifier fires with the desired filter and this screen
  /// applies it WITHOUT re-fetching — the list stays cached in memory
  /// so the tab switch feels instant.
  final ValueListenable<SubscriberFilter?>? filterCmd;

  @override
  State<SubscribersScreen> createState() => _SubscribersScreenState();
}

class _SubscribersScreenState extends State<SubscribersScreen>
    with WidgetsBindingObserver {
  final _searchCtrl = TextEditingController();
  Timer? _debounce;

  List<Subscriber> _all = [];
  Map<String, Map<String, dynamic>> _lastPayments = {};

  /// 2026-08-26 (tg parity): sas4Idx للمشتركين المربوطين ببوت تلغرام.
  /// نُحمّلها مرّة مع _load ونحدّثها بصمت مع polling الـ5 ثواني. الكارت
  /// يستقبلها كـbool `hasTelegram` لعرض شارة صغيرة بجنب اسم المشترك.
  Set<String> _telegramBoundIdx = const {};
  bool _loading = true;
  bool _refreshing = false;

  /// مطلب المستخدم 2026-07-12: تحديث صامت كل 5 ثواني حتى الحالة
  /// (online/offline/expiration) تبقى fresh بدون تدخّل الأدمن. الـtimer
  /// يوقفه AppLifecycle لما التطبيق يروح للـbackground حتى ما يستهلك
  /// بطارية/data بلا فائدة.
  Timer? _autoRefreshTimer;
  static const _autoRefreshInterval = Duration(seconds: 5);
  bool _appActive = true;

  // Probe wave state — set when a wave is running so the AppBar can
  // surface a small spinner. Bumped each call to invalidate any
  // in-flight wave whose list shape no longer matches.
  int _probeRunId = 0;
  bool _probing = false;
  int _probeDone = 0;
  int _probeTotal = 0;

  /// مطلب 2026-06-11: زر تكويل عام — true يخفي قسم الاتصال على
  /// كل البطاقات المعروضة. الـSubscriberCardV3 يلتقط الـprop عبر
  /// didUpdateWidget فيتزامن الكل لحظياً.

  String _query = '';
  SubscriberFilter _filter = SubscriberFilter.all;
  SortField _sortField = SortField.remainingDays;
  SortDirection _sortDir = SortDirection.desc;

  /// كم مشتركاً معروضاً الآن. يكبر بـ`_kPageStep` عند «تحميل المزيد»
  /// بدل التنقّل بين صفحات مرقّمة: القائمة نتيجة بحث لا فهرس كتاب،
  /// والمستخدم يبحث عن مشترك بعينه لا عن «الصفحة الرابعة».
  int _visibleCount = _kPageStep;

  final _scrollCtrl = ScrollController();

  /// هل انزلق الرأس الكامل خارج الشاشة؟ يحكم محتوى الشريط المثبَّت.
  bool _compactHeader = false;

  /// عتبة التبديل — أقلّ قليلاً من ارتفاع الرأس حتى يتمّ التبديل
  /// وقت اختفائه لا بعده. القيمتان المختلفتان (56 نزولاً · 40 صعوداً)
  /// تمنعان الرفرفة حين يستقرّ التمرير عند العتبة تماماً.
  void _onScroll() {
    final o = _scrollCtrl.hasClients ? _scrollCtrl.offset : 0.0;
    final next = _compactHeader ? o > 40 : o > 56;
    if (next != _compactHeader) setState(() => _compactHeader = next);
  }

  bool _selectionMode = false;
  final Set<String> _selected = {};

  static const int _kPageStep = 25;

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
    WidgetsBinding.instance.addObserver(this);
    _filter = widget.filterCmd?.value ?? SubscriberFilter.all;
    _applyDefaultSortFor(_filter);
    widget.filterCmd?.addListener(_onFilterCmd);
    // Re-fetch whenever any operation anywhere in the app mutates a
    // subscriber (activate / extend / disconnect / toggle / delete /
    // bulk action). Mirrors v1's notifier pattern.
    SubscriberEvents.dataChanged.addListener(_onDataChanged);
    _load();
    _searchCtrl.addListener(_onSearchChanged);
    widget.isActive?.addListener(_onActiveChanged);
    _startAutoRefresh();
  }

  /// Timer صامت — يفجّر _silentRefresh كل 5 ثواني ما دام التطبيق active.
  /// نلغي ونعيد التشغيل عند resume، ونوقف تماماً في pause/inactive.
  /// الشاشة حيّة **ومرئيّة** معاً.
  bool get _mayRefresh => widget.isActive?.value ?? true;

  void _onActiveChanged() {
    if (_mayRefresh) {
      _startAutoRefresh();
      // تحديث فوري عند العودة: القيم قد تكون قديمة بدقائق.
      if (!_refreshing && !_loading) _silentRefresh();
    } else {
      _autoRefreshTimer?.cancel();
    }
  }

  void _startAutoRefresh() {
    _autoRefreshTimer?.cancel();
    // ⚠️ الحارس هنا لا عند الاستدعاء: ثلاثة مسارات تستدعيها
    // (initState · didChangeAppLifecycleState · _onActiveChanged)،
    // ونسيانه في واحدة يعيد الاستنزاف كاملاً.
    if (!_mayRefresh) return;
    _autoRefreshTimer = Timer.periodic(_autoRefreshInterval, (_) {
      if (!mounted || !_appActive) return;
      // نتفادى overlap مع pull-to-refresh أو _load الأولي. نستخدم
      // نافذة زمنية بدل قفل صريح — لو حصل sync أثناء poll، الـpoll
      // يتخطّى ويأخذ الدور التالي بعد 5 ثواني.
      if (_refreshing || _loading) return;
      _silentRefresh();
    });
  }

  Future<void> _silentRefresh() async {
    // لا نُفعّل _refreshing حتى ما تظهر أي مؤشرات UI — تحديث خفي بالكامل.
    // _fetchAndMerge يستفيد من cache الـ45 ثانية على قائمة المشتركين لكن
    // يجيب online status حديث في كل مرة (loadOnline لا يُخزَّن).
    try {
      await _fetchAndMerge();
      // ⚠️ بلا هذا السطر يُدفع ثمن الاستطلاع كاملاً بلا أثر:
      // `_fetchAndMerge` يُسند `_all = merged` بلا `setState`، فالحالة
      // الحيّة (متصل/منتهي) لا تُرسَم حتّى يقع `setState` من سبب آخر.
      // أي أنّ الحلقة كانت تعمل على الفراغ منذ إنشائها.
      if (mounted) setState(() {});
    } catch (_) {
      // silent — لا نُشوّش المستخدم بأخطاء polling. الـpull-to-refresh
      // يُعيد المحاولة صريحاً لو الاتصال انقطع.
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appActive = state == AppLifecycleState.resumed;
    if (_appActive) {
      // عند الرجوع من الـbackground: refresh فوري + إعادة تشغيل timer.
      // Timer.periodic لا يُلغى تلقائياً في pause، بس رح يتخطّى بسبب
      // _appActive check — نُعيد التأكيد بإعادة الإنشاء.
      _startAutoRefresh();
      if (!_refreshing && !_loading) _silentRefresh();
    }
    super.didChangeAppLifecycleState(state);
  }

  void _onDataChanged() {
    if (!mounted) return;
    _refresh();
  }

  /// Called when MainShell pushes a new filter via the notifier. Reset
  /// paging + apply v1's default sort for the new filter so the user
  /// sees the relevant rows up top (e.g. tapping the dashboard's
  /// 'قارب الانتهاء' KPI surfaces least-time-left first).
  void _onFilterCmd() {
    final next = widget.filterCmd?.value;
    if (next == null || next == _filter) return;
    setState(() {
      _filter = next;
      _applyDefaultSortFor(next);
      _visibleCount = _kPageStep;
    });
  }

  void _applyDefaultSortFor(SubscriberFilter f) {
    final d = _defaultSortByFilter[f];
    if (d == null) return;
    _sortField = d.$1;
    _sortDir = d.$2;
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    WidgetsBinding.instance.removeObserver(this);
    _autoRefreshTimer?.cancel();
    widget.filterCmd?.removeListener(_onFilterCmd);
    SubscriberEvents.dataChanged.removeListener(_onDataChanged);
    widget.isActive?.removeListener(_onActiveChanged);
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    await _fetchAndMerge();
    if (!mounted) return;
    setState(() => _loading = false);
    _runProbeWave();
  }

  /// مطلب 2026-06-11: مسح batched (25 concurrent) لمعلومات أجهزة
  /// كل المشتركين المتصلين فور تحميل القائمة. النتائج تنزل في cache
  /// الـDeviceProbeApi والـDeviceChipMicro يقرأ منها مباشرة.
  /// كل wave له runId — لو القائمة تغيّرت أو الشاشة ضاعت، الحلقة
  /// تتوقف وما تنادي setState بعد.
  ///
  /// `force=true` يبطل cache الـ5 دقائق فيجبر فحص جديد على كل صف —
  /// يُستعمل من زر "فحص الأجهزة" اليدوي. عند الـboot الأول نخلّيه
  /// false (لو في snapshots حديثة محفوظة في الـin-memory cache من
  /// زيارة سابقة، نريد نقدّمها فوراً).
  void _runProbeWave({bool force = false}) {
    _probeRunId += 1;
    final myRun = _probeRunId;
    // مطلب المستخدم 2026-07-12: الـwave يفحص كل مشترك — لأن المدير
    // ممكن يخزّن customIp + username + password في DeviceConfig لجهاز
    // الوصول (ONT/UBNT) حتى مع خط RADIUS مقطوع. الجهاز نفسه online.
    //
    // DeviceProbeApi.probe() داخلياً يستدعي fetchConfig ويستعمل
    // customIp لو موجود؛ لو الاثنين (fallbackIp + customIp) فارغين
    // يرجع null بلا cost شبكي.
    //
    // تكلفة: ~1 GET /api/subscribers/:username/device لكل مشترك ما
    // له IP، يُنفَّذ merci وiplevel cache 5د بعد أول wave.
    var targets = _all
        .where((s) => s.username.isNotEmpty)
        .map((s) => (username: s.username, ip: (s.ipAddress ?? '').trim()))
        .toList();

    // ⚠️ استثنِ ما هو مفحوص وطازج — إلّا حين يطلب المستخدم فحصاً صريحاً.
    //
    // بدون هذا الترشيح كانت الموجة تمرّ على الـ500 كلّهم عند كل دخول
    // للشاشة وتُطلق 500 مستقبَلاً، ولو كانت كلّ النتائج في الكاش:
    // شريط تقدّم يعدّ إلى 500 بلا عمل حقيقي، وإيحاء للمستخدم بأنّ
    // الفحص يُعاد من الصفر في كل مرّة.
    if (!force) {
      targets = targets
          .where((t) =>
              DeviceProbeApi.peek(username: t.username, ip: t.ip) == null)
          .toList();
    }

    if (targets.isEmpty) {
      setState(() {
        _probing = false;
        _probeDone = 0;
        _probeTotal = 0;
      });
      return;
    }
    if (force) {
      // الـadmin يطلب تحديث صريح — نسقط الـcache كاملاً لكل المشتركين
      // المستهدفين بالـwave فالـwarmProbe يصير لهن جلسة probe جديدة.
      for (final t in targets) {
        DeviceProbeApi.invalidateIp(t.ip);
      }
      DeviceProbeBus.bump();
    }
    setState(() {
      _probing = true;
      _probeDone = 0;
      _probeTotal = targets.length;
    });
    // مطلب المستخدم 2026-07-12: أولوية للـviewport-visible subs.
    // الـwave يفحص هؤلاء أوّلاً حتى المستخدم يشوف حالتهم فوراً بدون
    // انتظار الـ500 مشترك يخلصون. الـpage الحالية أفضل تقريب متاح.
    final visible = _visibleForCurrentPage();
    final priorityUsernames = visible.map((s) => s.username).toSet();

    DeviceProbeApi.warmProbe(
      targets,
      priorityUsernames: priorityUsernames.isEmpty ? null : priorityUsernames,
      onProgress: (done, total) {
        if (!mounted || _probeRunId != myRun) return;
        setState(() {
          _probeDone = done;
          _probeTotal = total;
        });
        // Wake every visible DeviceChipMicro to consult the cache anew.
        DeviceProbeBus.bump();
      },
      isCanceled: () => !mounted || _probeRunId != myRun,
    ).whenComplete(() {
      if (!mounted || _probeRunId != myRun) return;
      setState(() => _probing = false);
    });
  }

  /// snapshot للـsubs المرئيّين على الـpage الحالية. يُستعمل كـpriority
  /// لـwarmProbe. آمن لو الصفحة تغيّرت أثناء الـwave — الأولوية تُطبَّق
  /// على snapshot اللحظة، مو reactive.
  List<Subscriber> _visibleForCurrentPage() {
    if (_all.isEmpty) return const [];
    // نستعمل _filteredAll اللي بيه الفلترة/الفرز مُطبّقة أصلاً.
    final visible = _filteredAll;
    if (visible.isEmpty) return const [];
    return visible.take(_visibleCount).toList();
  }

  Future<void> _refresh() async {
    setState(() => _refreshing = true);
    // Bypass the process-wide cache so pull-to-refresh always returns
    // fresh server data even if the cached entry is still warm.
    await SubscribersApi.refreshAll();
    await _fetchAndMerge();
    if (!mounted) return;
    setState(() => _refreshing = false);
    // مطلب 2026-06-11: السحب والتحديث ما يفجّر فحص كامل للأجهزة
    // (يأخّر استجابة عرض المشتركين). الـcache الحالي للأجهزة يبقى
    // والـadmin يضغط زر "فحص الأجهزة" يدوياً لتحديث الإشارات/RX.
  }

  /// Pulls the 3 sources in parallel (subscribers + online list + last
  /// payments) then merges: online flag is set per username, payments
  /// land in a separate map keyed by username. Mirrors v1's
  /// loadSubscribers → loadOnlineUsers → loadLastPayments sequence but
  /// runs them concurrently to cut wall time.
  Future<void> _fetchAndMerge() async {
    final adminId = await AuthStorage.readAdminId();
    final results = await Future.wait([
      SubscribersApi.loadAll(),
      SubscribersApi.loadOnline(),
      SubscribersApi.loadLastPayments(),
      SubscribersApi.loadPackages(),
      if (adminId != null)
        TelegramApi.listBindings(adminId)
      else
        Future.value(const <TelegramBinding>[]),
    ]);
    final list = results[0] as List<Subscriber>?;
    final online = results[1] as Map<String, OnlineSessionInfo>?;
    final payments = results[2] as Map<String, Map<String, dynamic>>?;
    final packages = results[3] as Map<String, PackageInfo>?;
    final bindings = results[4] as List<TelegramBinding>? ?? const [];
    _telegramBoundIdx = bindings.map((b) => b.sas4Idx).toSet();

    if (list == null) return;
    final onlineMap = online ?? const <String, OnlineSessionInfo>{};
    final packagesById = packages ?? const <String, PackageInfo>{};
    final merged = list.map((s) {
      // Match v1 (subscribers_provider.dart:455-489) exactly:
      // /api/v2/subscribers IS the source of truth for the online flag —
      // it reads online_status / is_online directly from SAS4. The
      // separate /api/v2/online-users call only EXISTS to enrich the
      // live session row (IP / session time / DL / UL bytes) so the
      // detail screen can show them. We never demote a subscriber to
      // offline based on the online-users map missing them — doing so
      // earlier silently zeroed out 'متصل' for the whole admin tree
      // when the merge ran before /online-users finished.
      var enriched = s.enrichWithPackages(packagesById);
      final session = onlineMap[enriched.username.toLowerCase()];
      if (session != null) {
        enriched = enriched.copyWithOnline(
          online: true,
          ip: session.ip,
          session: session.sessionTime,
          dl: session.downloadBytes,
          ul: session.uploadBytes,
          device: session.device,
        );
      }
      return enriched;
    }).toList();
    _all = merged;
    _lastPayments = payments ?? {};
  }

  void _onSearchChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      if (!mounted) return;
      setState(() {
        _query = _searchCtrl.text.trim();
        _visibleCount = _kPageStep;
      });
    });
  }

  /// Manager filter — when set, the list is restricted to subscribers
  /// whose parent_username matches. Drives _managerScoped which is the
  /// pre-filter source for both _filteredAll AND _counts so the chip
  /// counters on the bar reflect the manager subset (e.g. 'متصل (3)'
  /// when looking at one manager, not the whole tenant).
  String? _managerFilter;

  /// Distinct parent_username values from the loaded list, sorted.
  /// Empty when no subscriber has a parent (single-tenant admins).
  List<String> get _availableManagers {
    final set = <String>{};
    for (final s in _all) {
      final p = s.parentUsername;
      if (p != null && p.isNotEmpty) set.add(p);
    }
    final list = set.toList()..sort();
    return list;
  }

  /// Pre-filter source — apply the manager filter first so chip counts
  /// AND the main filter pipeline both work off the same subset.
  List<Subscriber> get _managerScoped {
    if (_managerFilter == null) return _all;
    return _all.where((s) => s.parentUsername == _managerFilter).toList();
  }

  // ───────── filtering / sorting (matches v1 predicates exactly) ─────────
  List<Subscriber> get _filteredAll {
    Iterable<Subscriber> it = _managerScoped;
    switch (_filter) {
      case SubscriberFilter.all:
        break;
      case SubscriberFilter.active:
        it = it.where((s) => s.isActive); // not-expired (disabled included)
      case SubscriberFilter.online:
        // 2026-07-16: "متصل" الآن يستثني المنتهي اشتراكه — عنده فلتر
        // "بدون نت" مخصّص. المستخدم يريد الفصل الدقيق: هنا المتصلون
        // النشطون فقط، والمنتهون المتصلون في onlineNoPlan.
        it = it.where((s) => s.isOnline && !s.isExpired);
      case SubscriberFilter.offline:
        it = it.where((s) => s.isOffline); // not-online AND not-expired
      case SubscriberFilter.disabled:
        it = it.where((s) => s.isDisabled);
      case SubscriberFilter.expired:
        it = it.where((s) => s.isExpired);
      case SubscriberFilter.debtors:
        it = it.where((s) => s.hasDebt);
      case SubscriberFilter.nearExpiry:
        it = it.where((s) => s.isNearExpiry);
      case SubscriberFilter.onlineNoPlan:
        // "بدون نت" — متصل بالشبكة لكن اشتراكه منتهي.
        it = it.where((s) => s.isOnline && s.isExpired);
    }
    if (_query.isNotEmpty) {
      final q = _query.toLowerCase();
      // مطابقة الهاتف بتجريد غير-الأرقام فقط للـqueries اللي تشبه رقم
      // (أرقام + رموز فورمات: + سبيس - قوسين). لو فيها أي حرف Latin/Arabic،
      // ما نستعملها — كان `user2020` يخلي digits="2020" ويطابق كل هاتف
      // فيه "2020" (عشرات المشتركين لا علاقة لهم بالاسم — bug 2026-07-13).
      final phoneLike = RegExp(r'^[\d\s+\-()]+$').hasMatch(q);
      final digits = phoneLike ? q.replaceAll(RegExp(r'\D'), '') : '';
      it = it.where((s) {
        if (s.username.toLowerCase().contains(q)) return true;
        if (s.fullName.toLowerCase().contains(q)) return true;
        if (digits.length >= 3 && s.displayPhone.contains(digits)) return true;
        return false;
      });
    }
    final list = it.toList();
    _applySort(list);
    return list;
  }

  void _applySort(List<Subscriber> list) {
    // مطلب 2026-06-11: device-metric sort له الأولوية فوق sort field
    // العادي. مشتركون بلا snapshot (الـwave لم يصلهم بعد، أو الفحص
    // فشل) يسقطون لأسفل القائمة بأي اتجاه — admin ما يريد سطور
    // غامضة فوق السطور المفحوصة.
    // 2026-08-26: ترتيب أبجدي حقيقي — case-insensitive + trim + normalize
    // بديل قوي لـString.compareTo. للعربي: Unicode order = أبجدي طبيعي
    // (ألف→ياء). للاتيني: نتجاهل حالة الأحرف (Ali و ali نفس الشيء).
    // whitespace متعدّد يُقلَّص لحرف واحد قبل المقارنة.
    int alphaCmp(String? a, String? b) {
      // ⚠️ `_wsRun` ثابتة الصنف لا محلّيّة: كانت `RegExp(r'\s+')` تُترجَم
      // مرّتين في كلّ **مقارنة**، وفرز 384 عنصراً ≈ 3400 مقارنة — أي
      // نحو 6800 ترجمة تعبير نمطيّ لكلّ فرزة.
      final na = (a ?? '').trim().replaceAll(_wsRun, ' ').toLowerCase();
      final nb = (b ?? '').trim().replaceAll(_wsRun, ' ').toLowerCase();
      // فارغ يسقط لأسفل بغض النظر عن الاتجاه.
      if (na.isEmpty && nb.isEmpty) return 0;
      if (na.isEmpty) return 1;
      if (nb.isEmpty) return -1;
      return na.compareTo(nb);
    }

    int cmp(Subscriber a, Subscriber b) {
      switch (_sortField) {
        case SortField.username:
          return alphaCmp(a.username, b.username);
        case SortField.firstname:
          return alphaCmp(a.fullName, b.fullName);
        case SortField.profileName:
          return alphaCmp(a.profileName, b.profileName);
        case SortField.phone:
          return a.displayPhone.compareTo(b.displayPhone);
        case SortField.expiration:
          return (a.expiration ?? '').compareTo(b.expiration ?? '');
        case SortField.remainingDays:
          // مطلب 2026-06-11: SAS4 يدوّر remainingDays لصفر للمنتهي
          // ولمن باقي عنده ساعات. الـcompareTo القديم يطلع المشترك
          // اللي عنده ساعه قبل المنتهي (tie أو ترتيب عشوائي).
          // الإصلاح: استعمل parsedExpiration timestamp كمصدر دقيق،
          // فالمنتهيون فعلاً يقعدون أولاً عند ascending.
          final aExp = a.parsedExpiration;
          final bExp = b.parsedExpiration;
          if (aExp != null && bExp != null) {
            return aExp.compareTo(bExp);
          }
          // Fallback لـremainingDays فقط لو date فاضي (نادر).
          return (a.remainingDays ?? 99999).compareTo(b.remainingDays ?? 99999);
        case SortField.notes:
          return a.balanceAmount.compareTo(b.balanceAmount);
        case SortField.parentUsername:
          return alphaCmp(a.parentUsername, b.parentUsername);
        case SortField.sessionTime:
          // Null sessionTime sinks to the bottom regardless of asc/desc
          // so offline rows don't clutter the head of the online list.
          final aHas = a.sessionTime != null;
          final bHas = b.sessionTime != null;
          if (!aHas && !bHas) return 0;
          if (!aHas) return _sortDir == SortDirection.asc ? 1 : -1;
          if (!bHas) return _sortDir == SortDirection.asc ? -1 : 1;
          return a.sessionTime!.compareTo(b.sessionTime!);
      }
    }

    list.sort(_sortDir == SortDirection.asc ? cmp : (a, b) => -cmp(a, b));
  }

  /// تسلسل مسافات — تُترجَم مرّة واحدة لعمر الصنف لا مرّة لكلّ مقارنة.
  static final RegExp _wsRun = RegExp(r'\s+');

  Map<SubscriberFilter, int> _counts() {
    // Manager-scoped so chip counters reflect the current sub-manager
    // pick: 'متصل (3)' means 3 online subs UNDER that manager, not 3
    // across the whole tenant. Matches v1 behaviour.
    final src = _managerScoped;
    return {
      SubscriberFilter.all: src.length,
      SubscriberFilter.active: src.where((s) => s.isActive).length,
      // 2026-07-16: نفس التغيير في العدّ — مطابق لمنطق الفلتر أعلاه.
      SubscriberFilter.online:
          src.where((s) => s.isOnline && !s.isExpired).length,
      SubscriberFilter.offline: src.where((s) => s.isOffline).length,
      SubscriberFilter.disabled: src.where((s) => s.isDisabled).length,
      SubscriberFilter.expired: src.where((s) => s.isExpired).length,
      SubscriberFilter.debtors: src.where((s) => s.hasDebt).length,
      SubscriberFilter.nearExpiry: src.where((s) => s.isNearExpiry).length,
      SubscriberFilter.onlineNoPlan:
          src.where((s) => s.isOnline && s.isExpired).length,
    };
  }

  // ───────── selection ─────────
  void _toggleSelect(Subscriber s) {
    final id = s.idx;
    if (id == null) return;
    HapticFeedback.selectionClick();
    setState(() {
      if (_selected.contains(id)) {
        _selected.remove(id);
        if (_selected.isEmpty) _selectionMode = false;
      } else {
        _selected.add(id);
        _selectionMode = true;
      }
    });
  }

  void _enterSelectionWith(Subscriber s) {
    final id = s.idx;
    if (id == null) return;
    HapticFeedback.selectionClick();
    setState(() {
      _selectionMode = true;
      _selected.add(id);
    });
  }

  void _exitSelection() {
    setState(() {
      _selectionMode = false;
      _selected.clear();
    });
  }

  void _selectAllOnPage(List<Subscriber> page) {
    setState(() {
      final selectable = page.where((s) => s.idx != null).toList();
      final allOn = selectable.every((s) => _selected.contains(s.idx));
      if (allOn) {
        for (final s in selectable) {
          _selected.remove(s.idx);
        }
        if (_selected.isEmpty) _selectionMode = false;
      } else {
        for (final s in selectable) {
          _selected.add(s.idx!);
        }
      }
    });
  }

  /// How many selected rows currently carry debt. Powers the bulk
  /// pay-debt button — hidden when zero so the bar doesn't offer an
  /// action that would open an empty sheet.
  int get _selectedDebtorCount =>
      _filteredSubscribersForBulk().where((s) => s.hasDebt).length;

  /// Per-action counts for the bulk bar. The disable button only
  /// affects rows currently enabled; the enable button only affects
  /// rows currently disabled. Showing the count next to each button
  /// (مطلب 2026-06-07) lets the admin see e.g. "تعطيل (1)" + "تفعيل (2)"
  /// when the selection mixes states, so they pick the right action
  /// without unstacking the selection.
  int get _enabledInSelection =>
      _filteredSubscribersForBulk().where((s) => !s.isDisabled).length;
  int get _disabledInSelection =>
      _filteredSubscribersForBulk().where((s) => s.isDisabled).length;

  /// Rows currently online — the disconnect button affects only
  /// these. Subscribers who aren't connected have no session to
  /// kick, so we skip them in the loop AND hide the count when zero.
  int get _onlineInSelection =>
      _filteredSubscribersForBulk().where((s) => s.isOnline).length;

  /// مطلب 2026-06-11: زر فصل المستخدم الفردي على بطاقة المتصل.
  /// نفس مسار الـbulk-disconnect (SubscribersApi.disconnect + notifyChange
  /// + _refresh) لكن لمشترك واحد. confirm dialog قبل الإجراء لأنه
  /// مؤثّر على المستخدم النهائي.

  /// إرسال تذكير دين من زر الكرت مباشرة. طلب 2026-07-13: يظهر لكل مدين
  /// بغض النظر عن حالة الاتصال. يستعمل نفس مسار زر الديون في شاشة
  /// التفاصيل — WhatsAppApi.sendTemplateForSubscriber → قالب debt_reminder
  /// المعرّف للمدير + إرسال عبر جلسة الواتساب النشطة.
  final Set<String> _debtReminderInFlight = {};
  Future<void> _sendDebtReminderFromList(Subscriber s) async {
    if (_debtReminderInFlight.contains(s.username)) return;
    setState(() => _debtReminderInFlight.add(s.username));
    try {
      final result = await WhatsAppApi.sendTemplateWithPreview(
        context: context,
        sub: s,
        templateType: 'debt_reminder',
      );
      if (!mounted) return;
      if (result.reason == 'cancelled') return;
      final ok = result.ok;
      final okMsg = 'subscribers.wa_debt_reminder_sent'.tr();
      final chArabic = result.channelArabic;
      final msg = ok
          ? (result.message ??
              (chArabic != null ? '$okMsg · عبر $chArabic' : okMsg))
          : (result.message ?? 'subscribers.wa_message_send_failed'.tr());
      showSheetSnack(context, msg, isError: !ok);
    } finally {
      if (mounted) {
        setState(() => _debtReminderInFlight.remove(s.username));
      }
    }
  }

  /// «تسديد» من شريط الدين في الكارت. يفتح نفس شيت التفاصيل بلا
  /// اختصار (قاعدة: عمليّات المشترك تطابق v1 حرفيّاً)، ثمّ يبثّ
  /// dataChanged حتى يتحدّث الصفّ والدين فوراً.
  Future<void> _payDebtFromList(Subscriber s) async {
    final ok = await showPayDebtSheet(context, s);
    if (ok == true) {
      SubscriberEvents.dataChanged.value++;
    }
  }

  Future<void> _openSortSheet() async {
    final r = await showSortSheet(
      context,
      currentField: _sortField,
      currentDirection: _sortDir,
    );
    if (r != null) {
      setState(() {
        _sortField = r.field;
        _sortDir = r.direction;
        _visibleCount = _kPageStep;
      });
    }
  }

  String _sortLabel() => sortFieldLabel(_sortField);

  /// شيت «تصفية القائمة» — النسخة الخفيفة من المخطّط: بلا رأس مفصول،
  /// عنوان 16/w700 مع «إعادة تعيين» في الطرف، شرائح، ثمّ زرّ «تطبيق».
  /// يستبدل صفّ `_ManagerFilterBar` المسطّح الذي كان تحت البحث.
  Future<void> _openManagerFilterSheet() async {
    final picked = await showModalBottomSheet<Object?>(
      barrierColor: AppColors.scrim,
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(R.sheet)),
      ),
      builder: (ctx) => _ManagerFilterSheet(
        current: _managerFilter,
        managers: _availableManagers,
      ),
    );
    if (picked == null) return; // أُغلق بلا «تطبيق»
    setState(() {
      _managerFilter = normalizeManagerFilter(picked);
      _visibleCount = _kPageStep;
    });
  }

  Future<void> _openBulkDisconnect() async {
    final online = _filteredSubscribersForBulk()
        .where((s) => s.isOnline && s.idx != null)
        .toList();
    if (online.isEmpty) return;
    final confirm = await showConfirmSheet(
      context,
      icon: LucideIcons.power,
      tone: AppTone.danger,
      title: 'subscribers.disconnect_users'.tr(),
      message: 'subscribers.disconnect_users_body'
          .tr(namedArgs: {'count': '${online.length}'}),
      confirmLabel: 'subscribers.disconnect'.tr(),
    );
    if (confirm != true || !mounted) return;

    _showProgress('subscribers.disconnect_users'.tr());
    var ok = 0, fail = 0;
    for (final s in online) {
      final res = await SubscribersApi.disconnect(s.idx!);
      res.ok ? ok++ : fail++;
    }
    if (!mounted) return;
    Navigator.of(context).pop(); // close progress
    _exitSelection();
    // Disconnect doesn't change DB state (just kicks the live
    // session), but the online overlay should refresh so the rows
    // stop showing the connected badge. notifyChange triggers the
    // shared dataChanged → screens re-fetch.
    if (ok > 0) SubscriberEvents.notifyChange();
    await _refresh();
    if (!mounted) return;
    showSheetSnack(
      context,
      'subscribers.disconnected_count'.tr(namedArgs: {
        'ok': '$ok',
        'fail': fail > 0
            ? ' — ${'subscribers.failed_count'.tr(namedArgs: {'n': '$fail'})}'
            : '',
      }),
      isError: fail != 0,
    );
  }

  /// Resolve the selected idx set back to the live Subscriber objects
  /// the bulk sheets need (debt, name, balance). The full list comes
  /// from the same _subs we render — we just filter by idx membership.
  List<Subscriber> _filteredSubscribersForBulk() {
    if (_selected.isEmpty) return const [];
    return _all
        .where((s) => s.idx != null && _selected.contains(s.idx!))
        .toList();
  }

  Future<void> _openBulkPayDebt() async {
    final debtors =
        _filteredSubscribersForBulk().where((s) => s.hasDebt).toList();
    if (debtors.isEmpty) return;
    await showBulkPayDebtSheet(context, subs: debtors);
    if (!mounted) return;
    _exitSelection();
    // The sheet itself fires SubscriberEvents.notifyChange on any
    // success, which triggers _onDataChanged → _refresh. We still
    // exit selection mode here so the bulk bar collapses regardless.
  }

  Future<void> _openBulkActivate() async {
    final selected = _filteredSubscribersForBulk();
    if (selected.isEmpty) return;
    await showBulkActivateSheet(context, subs: selected);
    if (!mounted) return;
    _exitSelection();
  }

  Future<void> _bulk(_BulkAction action) async {
    // For toggle actions filter the selection to rows that actually
    // need the flip — disabling an already-disabled row is a no-op
    // that wastes a network call AND inflates the failure count when
    // the backend rejects it. Delete affects the whole selection.
    final selectedSubs = _filteredSubscribersForBulk();
    final eligible = switch (action) {
      _BulkAction.disable => selectedSubs.where((s) => !s.isDisabled).toList(),
      _BulkAction.enable => selectedSubs.where((s) => s.isDisabled).toList(),
      _BulkAction.delete => selectedSubs,
    };
    final ids = eligible.map((s) => s.idx).whereType<String>().toList();
    if (ids.isEmpty) return;
    final confirm = await _confirmBulk(action, ids.length);
    if (!confirm || !mounted) return;

    _showProgress(action.label);
    var ok = 0, fail = 0;
    for (final id in ids) {
      final success = await switch (action) {
        _BulkAction.disable => SubscribersApi.toggle(id, enable: false),
        _BulkAction.enable => SubscribersApi.toggle(id, enable: true),
        // delete now returns a structured result so we map to bool
        // before tallying. The error message is already surfaced via
        // the per-row tracking in the single-delete confirm flow;
        // bulk just counts ok/fail and shows a summary snackbar.
        _BulkAction.delete => SubscribersApi.delete(id).then((r) => r.ok),
      };
      success ? ok++ : fail++;
    }
    if (!mounted) return;
    Navigator.of(context).pop(); // close progress
    _exitSelection();
    if (ok > 0) SubscriberEvents.notifyChange();
    await _refresh();
    if (!mounted) return;
    showSheetSnack(
      context,
      'subscribers.done_count'.tr(namedArgs: {
        'ok': '$ok',
        'fail': fail > 0
            ? ' — ${'subscribers.failed_count'.tr(namedArgs: {'n': '$fail'})}'
            : '',
      }),
      isError: fail != 0,
    );
  }

  /// تأكيد إجراء جماعي — بالقوقعة الموحّدة لا `AlertDialog`.
  ///
  /// ⚠️ نفس الإجراء على مشترك واحد يُؤكَّد بشيت، وعلى عشرة كان يُؤكَّد
  /// بحوار Material خام: نمطان لفعل واحد، والأخطر منهما — الجماعي —
  /// كان يبدو أخفّ. (طلب المستخدم 2026-08-30: مودالات الجماعي تُشبه
  /// مودالات كارت المشترك.)
  Future<bool> _confirmBulk(_BulkAction action, int count) async {
    final destructive = action == _BulkAction.delete;
    final res = await showConfirmSheet(
      context,
      icon: switch (action) {
        _BulkAction.delete => LucideIcons.trash2,
        _BulkAction.disable => LucideIcons.ban,
        _BulkAction.enable => LucideIcons.circleCheck,
      },
      tone: destructive ? AppTone.danger : AppTone.brand,
      title: 'subscribers.confirm_bulk_action'
          .tr(namedArgs: {'label': action.label, 'count': '$count'}),
      subtitle: 'subscribers.selected_count'
          .tr(namedArgs: {'count': '$count'}, args: ['$count']),
      message: destructive
          ? 'subscribers.confirm_bulk_delete'.tr(namedArgs: {'count': '$count'})
          : 'subscribers.confirm_bulk_generic'
              .tr(namedArgs: {'label': action.label, 'count': '$count'}),
      confirmLabel: action.label,
    );
    return res ?? false;
  }

  void _showProgress(String label) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => Dialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(R.lg),
        ),
        child: Padding(
          padding: const EdgeInsets.all(Sp.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: AppColors.brand),
              const SizedBox(height: Sp.md),
              Text('subscribers.busy_action'.tr(namedArgs: {'label': label}),
                  style: AppType.label(color: AppColors.textHi)),
            ],
          ),
        ),
      ),
    );
  }

  // ───────── build ─────────
  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    // ⚡ تُحسب مرّةً واحدة للإطار (تدقيق أداء 2026-08-31).
    //
    // كانت `_filteredAll` تُستدعى ثلاثاً و`_counts()` ثلاثاً
    // و`_availableManagers` مرّتين في البناء الواحد — وكلّها جالبات
    // تُعيد الحساب كاملاً في كلّ قراءة. و`_counts()` وحدها ثمانية
    // مرورات على القائمة، فثلاث استدعاءات = 24 مروراً على 384 مشتركاً
    // في كلّ إطار، وكلّ ضغطة مفتاح في البحث تُطلق إطاراً.
    //
    // لا ذاكرة بمفتاح إبطال هنا عمداً: مفتاح خاطئ يعني قائمةً بائتة،
    // وهي عطل أسوأ من الثقل. الحساب مرّة لكلّ إطار يُبقي الصحّة
    // مضمونةً بالبناء.
    final filtered = _filteredAll;
    final counts = _counts();
    final managers = _availableManagers;
    final page = filtered.take(_visibleCount).toList();
    final remaining = filtered.length - page.length;

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // ⚠️ البنية هنا ليست تجميلاً: كانت أربعة صفوف ثابتة فوق
            // القائمة (بحث · شرائح · فرز · ترقيم) تحجز نحو ثلث الشاشة
            // قبل أن يُرى مشترك واحد. الآن الشرائح وحدها تثبت — وهي
            // التنقّل الأساسي — والبحث وشريط الفرز يمشيان مع التمرير.
            Expanded(
              child: RefreshIndicator(
                color: AppColors.brand,
                onRefresh: _refresh,
                child: _loading
                    ? Center(
                        child:
                            CircularProgressIndicator(color: AppColors.brand))
                    : CustomScrollView(
                        controller: _scrollCtrl,
                        slivers: [
                          SliverToBoxAdapter(
                            child: Column(
                              children: [
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                      Sp.lg, Sp.md, Sp.lg, Sp.sm),
                                  child: _selectionMode
                                      ? _SelectionHeader(
                                          count: _selected.length,
                                          total: page.length,
                                          onExit: _exitSelection,
                                          onSelectAll: () =>
                                              _selectAllOnPage(page),
                                        )
                                      : _ListHeader(
                                          controller: _searchCtrl,
                                          total:
                                              counts[SubscriberFilter.all] ??
                                                  0,
                                          online: counts[
                                                  SubscriberFilter.online] ??
                                              0,
                                          sortActive: _sortField !=
                                                  SortField.remainingDays ||
                                              _sortDir != SortDirection.desc,
                                          filterActive: _managerFilter != null,
                                          sortLabel: _sortLabel(),
                                          onSort: _openSortSheet,
                                          onFilter: managers.isEmpty
                                              ? null
                                              : _openManagerFilterSheet,
                                          // 2026-08-29: زرّ فحص الأجهزة انتقل من شريط شرائح
                                          // الفرز إلى هنا بجانب الفرز والتصفية — طلب المستخدم.
                                          probing: _probing,
                                          onScanDevices: _probing
                                              ? null
                                              : () =>
                                                  _runProbeWave(force: true),
                                        ),
                                ),
                              ],
                            ),
                          ),
                          SliverPersistentHeader(
                            pinned: true,
                            delegate: _ChipsBarDelegate(
                              compact: _compactHeader,
                              compactChild: _CompactSearchBar(
                                controller: _searchCtrl,
                                filterActive: _managerFilter != null,
                                onFilter: managers.isEmpty
                                    ? null
                                    : _openManagerFilterSheet,
                                onBackToTop: () => _scrollCtrl.animateTo(
                                  0,
                                  duration: const Duration(milliseconds: 260),
                                  curve: Curves.easeOutCubic,
                                ),
                              ),
                              child: ColoredBox(
                                color: AppColors.bg,
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    FilterChipsBar(
                                      current: _filter,
                                      counts: counts,
                                      onSelect: (f) => setState(() {
                                        _filter = f;
                                        _applyDefaultSortFor(f);
                                        _visibleCount = _kPageStep;
                                      }),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          SliverToBoxAdapter(
                            child: Column(
                              children: [
                                if (!_selectionMode)
                                  _ResultSortBar(
                                    count: filtered.length,
                                    sortLabel: _sortLabel(),
                                    descending: _sortDir == SortDirection.desc,
                                    onTap: _openSortSheet,
                                  ),
                                // مطلب 2026-07-14: كارت "إجمالي الديون" (نظير v1 —
                                // subscribers_screen.dart:875) — يظهر عند فلتر "المدينون"
                                // ويحترم تلقائياً فلتر المدير الفرعي لأنّه يحسب من
                                // _filteredAll الي بنفسه محكوم بـ_managerScoped.
                                if (_filter == SubscriberFilter.debtors &&
                                    !_selectionMode)
                                  _DebtSummaryCard(subscribers: filtered),
                                // مطلب 2026-06-11: شريط رفيع يبيّن تقدم فحص الأجهزة
                                // (لكل المشتركين المتصلين). يختفي لما الفحص يخلص. يظهر
                                // عدد المفحوص / الإجمالي بدون أن يحجب أي تفاعل آخر.
                                if (_probing && _probeTotal > 0)
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                        Sp.lg, 6, Sp.lg, 0),
                                    child: Row(
                                      children: [
                                        SizedBox(
                                          width: 10,
                                          height: 10,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 1.5,
                                            color: AppColors.brandAccent,
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          'subscribers.probing_devices'.tr(
                                              namedArgs: {
                                                'done': '$_probeDone',
                                                'total': '$_probeTotal'
                                              }),
                                          style: AppType.muted()
                                              .copyWith(fontSize: 10.5),
                                        ),
                                      ],
                                    ),
                                  ),
                                // 2026-08-29: شريط شرائح فرز الأجهزة (RX · إشارة · CCQ ·
                                // LAN) حُذف بطلب المستخدم — شيت «ترتيب القائمة» يغطّي
                                // الحاجة، والشريط كان يزاحم كلّ نتيجة بصفّ إضافي.
                              ],
                            ),
                          ),
                          if (page.isEmpty)
                            SliverFillRemaining(
                              hasScrollBody: false,
                              child:
                                  _EmptyState(filter: _filter, query: _query),
                            )
                          else
                            SliverPadding(
                              padding: EdgeInsets.fromLTRB(
                                Sp.lg,
                                0,
                                Sp.lg,
                                Sp.huge * 3 +
                                    MediaQuery.paddingOf(context).bottom,
                              ),
                              sliver: SliverList.separated(
                                // صفّ إضافي في الذيل لزرّ «تحميل المزيد»:
                                // داخل القائمة لا تحتها، فلا يحجز ارتفاعاً
                                // ثابتاً ولا يظهر إلّا حين يبقى ما يُحمَّل.
                                itemCount:
                                    page.length + (remaining > 0 ? 1 : 0),
                                // 2026-08-26: 8dp → 6dp بين الكارت والكارت.
                                // مع padding داخلي مخفَّض + borders أخف = تركيز
                                // بصري أعلى، صفوف أكثر مرئيّة.
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: 6),
                                itemBuilder: (_, i) {
                                  if (i == page.length) {
                                    return _LoadMoreButton(
                                      remaining: remaining,
                                      onTap: () => setState(
                                          () => _visibleCount += _kPageStep),
                                    );
                                  }
                                  final s = page[i];
                                  final isSelected = s.idx != null &&
                                      _selected.contains(s.idx);
                                  return SubscriberCardV3(
                                    // بلا مفتاح ثابت يعيد Flutter استعمال
                                    // الـElement لمشترك آخر بعد كل موجة فحص
                                    // أجهزة فتنتقل حالة الصفّ للجار.
                                    key: ValueKey(s.idx ?? s.username),
                                    sub: s,
                                    selected: isSelected,
                                    lastPayment: _lastPayments[s.username],
                                    hasTelegram: s.idx != null &&
                                        _telegramBoundIdx
                                            .contains(s.idx.toString()),
                                    onTap: () {
                                      if (_selectionMode) {
                                        _toggleSelect(s);
                                      } else {
                                        _openDetail(s);
                                      }
                                    },
                                    onLongPress: () => _enterSelectionWith(s),
                                    // تذكير دين — لكل مدين بغض النظر عن حالة
                                    // الاتصال. طلب 2026-07-13. مسار
                                    // /api/v2/subscribers/:idx/send-debt-reminder
                                    onSendDebtReminder: s.hasDebt &&
                                            !_selectionMode &&
                                            s.idx != null
                                        ? () => _sendDebtReminderFromList(s)
                                        : null,
                                    // «تسديد» داخل شريط الدين — نفس شيت
                                    // التفاصيل بلا اختصار، ومحكوم بنفس
                                    // الصلاحيّة (subscribers.pay_debt).
                                    onPayDebt: s.hasDebt &&
                                            !_selectionMode &&
                                            Perms.has('subscribers.pay_debt')
                                        ? () => _payDebtFromList(s)
                                        : null,
                                    // الموقع من القائمة مباشرةً — كان
                                    // يتطلّب فتح الكارت ثمّ «إجراءات
                                    // أخرى». الشيت يعرض جوجل وWaze.
                                    onOpenLocation: _selectionMode
                                        ? null
                                        : () =>
                                            showLocationSheet(context, sub: s),
                                  );
                                },
                              ),
                            ),
                        ],
                      ),
              ),
            ),
            if (_refreshing)
              LinearProgressIndicator(
                color: AppColors.brand,
                backgroundColor: Colors.transparent,
                minHeight: 2,
              ),
          ],
        ),
      ),
      // Selection bottom action bar
      bottomNavigationBar: _selectionMode
          ? _BulkActionBar(
              selectedCount: _selected.length,
              debtorCount: _selectedDebtorCount,
              enabledCount: _enabledInSelection,
              disabledCount: _disabledInSelection,
              onlineCount: _onlineInSelection,
              onRenew: _openBulkActivate,
              onPayDebt: _selectedDebtorCount > 0 ? _openBulkPayDebt : null,
              onDisconnect: _onlineInSelection > 0 ? _openBulkDisconnect : null,
              onDisable: () => _bulk(_BulkAction.disable),
              onEnable: () => _bulk(_BulkAction.enable),
              onDelete: () => _bulk(_BulkAction.delete),
            )
          : null,
    );
  }

  void _openDetail(Subscriber s) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SubscriberDetailScreen(sub: s),
        fullscreenDialog: true,
      ),
    );
  }
}

enum _BulkAction {
  disable('subscribers.disable'),
  enable('subscribers.enable'),
  delete('subscribers.bulk_delete');

  const _BulkAction(this._key);
  final String _key;
  // نُترجم عند الاستدعاء — الـenum ما يستطيع استدعاء tr() في constructor.
  String get label => _key.tr();
}

class _ListHeader extends StatelessWidget {
  const _ListHeader({
    required this.controller,
    required this.total,
    required this.online,
    required this.sortActive,
    required this.filterActive,
    required this.sortLabel,
    required this.onSort,
    required this.onFilter,
    required this.probing,
    required this.onScanDevices,
  });

  final TextEditingController controller;
  final int total;
  final int online;
  final bool sortActive;
  final bool filterActive;
  final String sortLabel;
  final VoidCallback onSort;

  /// null = لا مدراء فرعيّون في هذا الحساب ⇒ الزرّ يختفي بدل أن يفتح
  /// شيتاً فارغاً.
  final VoidCallback? onFilter;

  /// موجة فحص الأجهزة جارية — الزرّ يعرض دوّارة ويرفض النقر حتى لا
  /// تُطلق موجة فوق موجة.
  final bool probing;

  /// null أثناء الفحص فقط. الزرّ يبقى ظاهراً دائماً (بخلاف زرّ التصفية)
  /// لأنّه لا يعتمد على وجود مدراء فرعيّين.
  final VoidCallback? onScanDevices;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('subscribers.title'.tr(), style: AppType.title()),
                  const SizedBox(height: 2),
                  Text(
                    '$total مشترك • $online متصل الآن',
                    style: AppType.body(color: AppColors.textMid)
                        .copyWith(fontSize: 12.5),
                  ),
                ],
              ),
            ),
            // رادار لا «تحديث»: الزرّ يفحص أجهزة المشتركين
            // (RX/إشارة/CCQ/LAN) ولا يعيد تحميل القائمة — كان يُقرأ
            // كـreload. طلب المستخدم 2026-08-29.
            _HeaderIconButton(
              icon: Icons.radar_rounded,
              active: false,
              busy: probing,
              onTap: onScanDevices ?? () {},
              tooltip: 'subscribers.probe_devices'.tr(),
            ),
            const SizedBox(width: Sp.sm),
            _HeaderIconButton(
              icon: Icons.swap_vert_rounded,
              active: sortActive,
              onTap: onSort,
            ),
            if (onFilter != null) ...[
              const SizedBox(width: Sp.sm),
              _HeaderIconButton(
                icon: Icons.tune_rounded,
                active: filterActive,
                onTap: onFilter!,
              ),
            ],
          ],
        ),
        const SizedBox(height: Sp.lg),
        // حقل البحث — 46 ارتفاعاً، r16، حدّ خفيف. المخطّط يرسمه نصّاً
        // ساكناً بلا زرّ مسح؛ أبقينا زرّ المسح لأنّه سلوك قائم.
        Container(
          height: H.search,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(R.lg),
            border: Border.all(color: AppColors.borderSoft),
          ),
          child: Row(
            children: [
              Icon(Icons.search_rounded, size: 20, color: AppColors.textLow),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: controller,
                  style: AppType.input(),
                  decoration: InputDecoration(
                    hintText: 'subscribers.search_hint_full'.tr(),
                    hintStyle: AppType.subtitle(color: AppColors.textLow)
                        .copyWith(fontSize: 14),
                    border: InputBorder.none,
                    isCollapsed: true,
                  ),
                ),
              ),
              if (controller.text.isNotEmpty)
                InkResponse(
                  radius: 18,
                  onTap: controller.clear,
                  child: Icon(Icons.close_rounded,
                      size: 18, color: AppColors.textLow),
                )
              else
                // الإملاء الصوتي في مكان زرّ المسح: أحدهما فقط ذو معنى
                // في كل لحظة — الحقل فارغ فيُملى، أو فيه نصّ فيُمسح.
                VoiceSearchButton(controller: controller),
            ],
          ),
        ),
      ],
    );
  }
}

/// زرّ أيقوني 38×38 r14 في الهيدر. الحالة النشطة خضراء ناعمة مع نقطة
/// 9×9 في الزاوية الخارجيّة محاطة بحدّ بلون الخلفيّة ليبدو مقطوعاً.
class _HeaderIconButton extends StatelessWidget {
  const _HeaderIconButton({
    required this.icon,
    required this.active,
    required this.onTap,
    this.busy = false,
    this.tooltip,
  });
  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  /// يستبدل الأيقونة بدوّارة ويقفل النقر — زرّ فحص الأجهزة أثناء الموجة.
  final bool busy;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final body = _build(context);
    return tooltip == null ? body : Tooltip(message: tooltip!, child: body);
  }

  Widget _build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Material(
          color: active ? AppColors.brandSoftBg : AppColors.surface,
          borderRadius: BorderRadius.circular(R.icon),
          child: InkWell(
            onTap: busy ? null : onTap,
            borderRadius: BorderRadius.circular(R.icon),
            child: Container(
              width: H.iconBtn,
              height: H.iconBtn,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(R.icon),
                border: Border.all(
                  color:
                      active ? AppColors.brandSoftBorder : AppColors.borderSoft,
                ),
              ),
              child: busy
                  ? SizedBox(
                      width: 17,
                      height: 17,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.brandAccent,
                      ),
                    )
                  : Icon(
                      icon,
                      size: 20,
                      color: active ? AppColors.brand : AppColors.textBody,
                    ),
            ),
          ),
        ),
        if (active)
          Positioned(
            top: -3,
            left: -3,
            child: Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(
                color: AppColors.brand,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.bg, width: 2),
              ),
            ),
          ),
      ],
    );
  }
}

/// شريط «{n} نتيجة» ← «{حقل الفرز}» بسهم الاتجاه. الضغط على الطرف
/// الأيسر يفتح شيت الفرز (نفس سلوك المخطّط).
class _ResultSortBar extends StatelessWidget {
  const _ResultSortBar({
    required this.count,
    required this.sortLabel,
    required this.descending,
    required this.onTap,
  });
  final int count;
  final String sortLabel;
  final bool descending;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, Sp.lg, 22, Sp.sm),
      child: Row(
        children: [
          Text(
            '$count نتيجة',
            style: AppType.muted(color: AppColors.textLow)
                .copyWith(fontSize: 11.5),
          ),
          const Spacer(),
          InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(R.sm),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    descending
                        ? Icons.arrow_downward_rounded
                        : Icons.arrow_upward_rounded,
                    size: 14,
                    color: AppColors.brandAccent,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    sortLabel,
                    style: AppType.muted(color: AppColors.brandAccent)
                        .copyWith(fontSize: 11.5, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// يُطبّع خرج `_ManagerFilterSheet` إلى ثنائيّة واحدة: مديرٌ مختار،
/// أو `null` = «الكل».
///
/// 🐛 بلاغ 2026-08-31: اختيار مدير فرعي ثمّ العودة إلى «الكل» كان
/// يُفرّغ القائمة تماماً (0 مشترك، 0 نتيجة) حتّى إغلاق التطبيق وفتحه.
///
/// السبب أنّ الشيت يُرجع `_picked ?? ''` — فـ«الكل» تصل سلسلةً فارغة
/// لا `null` — بينما المستقبِل كان يقول `picked is String ? picked :
/// null`. والفارغة **سلسلة**، فيصير الفلتر `''` ويبحث `_managerScoped`
/// عمّن `parentUsername == ''` ولا أحد كذلك. ولأنّ الحقل يُبنى `null`
/// عند إنشاء الحالة، كان الخروج من التطبيق يبدو «إصلاحاً».
///
/// الثابتة التي تحرسها هذه الدالّة: `_managerFilter` إمّا `null` أو
/// نصّ غير فارغ — أبداً بينهما. عليها يعتمد `filterActive` أيضاً.
String? normalizeManagerFilter(Object? picked) {
  if (picked is! String) return null;
  final trimmed = picked.trim();
  return trimmed.isEmpty ? null : trimmed;
}

/// شيت تصفية القائمة — النسخة الخفيفة (بلا رأس مفصول، عنوان + إعادة
/// تعيين، شرائح، زرّ تطبيق). يرجع `String` = مدير مختار، أو
/// `''` = الكل، أو `null` إن أُغلق بلا تطبيق.
class _ManagerFilterSheet extends StatefulWidget {
  const _ManagerFilterSheet({required this.current, required this.managers});
  final String? current;
  final List<String> managers;

  @override
  State<_ManagerFilterSheet> createState() => _ManagerFilterSheetState();
}

class _ManagerFilterSheetState extends State<_ManagerFilterSheet> {
  late String? _picked = widget.current;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return DesignSheet(
      header: SheetHeaderBar(
        icon: Icons.tune_rounded,
        title: 'تصفية القائمة',
        subtitle: '',
        onClose: () => Navigator.of(context).pop(),
      ),
      footer: SheetFooterBar(
        label: 'تطبيق',
        icon: Icons.check_rounded,
        onPressed: () => Navigator.pop(context, _picked ?? ''),
        leading: _ResetFilterButton(
          onTap: () => setState(() => _picked = null),
        ),
      ),
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: Sp.lg),
          Text('المدير الفرعي', style: AppType.pillLabel()),
          const SizedBox(height: Sp.sm),
          Wrap(
            spacing: Sp.sm,
            runSpacing: Sp.sm,
            children: [
              _chip(label: 'الكل', value: null),
              for (final m in widget.managers) _chip(label: m, value: m),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chip({required String label, required String? value}) {
    final on = _picked == value;
    return InkWell(
      onTap: () => setState(() => _picked = value),
      borderRadius: BorderRadius.circular(R.chip),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
        decoration: BoxDecoration(
          color: on ? AppColors.brand : AppColors.surface,
          borderRadius: BorderRadius.circular(R.chip),
          border: Border.all(
            color: on ? AppColors.brand : AppColors.border,
            width: on ? BW.selected : BW.normal,
          ),
        ),
        child: Text(
          label,
          textDirection: value == null ? null : ui.TextDirection.ltr,
          style: AppType.bodyStrong(
            color: on ? AppColors.onBrand : AppColors.textBody,
          ),
        ),
      ),
    );
  }
}

class _SelectionHeader extends StatelessWidget {
  const _SelectionHeader({
    required this.count,
    required this.total,
    required this.onExit,
    required this.onSelectAll,
  });

  final int count;
  final int total;
  final VoidCallback onExit;
  final VoidCallback onSelectAll;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Container(
      height: 42,
      decoration: BoxDecoration(
        color: AppColors.brandSoftBg,
        borderRadius: BorderRadius.circular(R.pill),
        border: Border.all(color: AppColors.brandSoftBorder),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(LucideIcons.x, size: 18),
            color: AppColors.brand,
            visualDensity: VisualDensity.compact,
            onPressed: onExit,
          ),
          const SizedBox(width: 4),
          Text(
            '$count محدد',
            style: AppType.label(color: AppColors.brand)
                .copyWith(fontSize: 13, fontWeight: FontWeight.w700),
          ),
          const Spacer(),
          TextButton(
            onPressed: onSelectAll,
            child: Text(
              '${'subscribers.select_all'.tr()} ($total)',
              style: AppType.label(color: AppColors.brand)
                  .copyWith(fontSize: 12.5, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

/// Sub-manager (parent) filter strip — horizontal chip row matching
/// the FilterChipsBar visual language. Leading shield icon + 'كل
/// المدراء' chip + one chip per parent_username found in the loaded
/// list. Tap a chip to scope the whole screen to that sub-manager;
/// tap الكل to clear. Mirrors v1's "كل المدراء" dropdown but the
/// chip row reads at a glance instead of hiding the choices behind
/// a tap (مطلب 2026-06-09).
class _BulkActionBar extends StatelessWidget {
  const _BulkActionBar({
    required this.selectedCount,
    required this.debtorCount,
    required this.enabledCount,
    required this.disabledCount,
    required this.onlineCount,
    required this.onRenew,
    required this.onPayDebt,
    required this.onDisconnect,
    required this.onDisable,
    required this.onEnable,
    required this.onDelete,
  });
  final int selectedCount;
  final int debtorCount;

  /// Selected rows currently enabled — these are the ones a tap on
  /// 'تعطيل' will actually affect. Shown as '(N)' next to the label
  /// so the admin sees how many will flip even when the selection
  /// mixes states (مطلب 2026-06-07).
  final int enabledCount;
  final int disabledCount;

  /// Rows currently online — the disconnect button only affects
  /// these. Hidden when zero so the bar doesn't show an empty action.
  final int onlineCount;
  final VoidCallback onRenew;

  /// null = no debtors in selection → button disabled. Non-null →
  /// opens the bulk pay-debt sheet against the debtor subset.
  final VoidCallback? onPayDebt;

  /// null = no online rows in selection → button hidden entirely
  /// (no greyed-out state — disconnect is a hot action and the row
  /// is otherwise reserved for the toggle/delete trio).
  final VoidCallback? onDisconnect;
  final VoidCallback onDisable;
  final VoidCallback onEnable;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    // مطلب 2026-06-12: كل زر في الـbulk bar مربوط بصلاحية. لو الموظف
    // ما يقدر يجدّد/يسدّد/يفعّل/يحذف الزر يختفي تماماً (مو disable).
    final canRenew =
        Perms.hasAny(const ['subscribers.activate', 'subscribers.extend']);
    final canPayDebt = Perms.has('subscribers.pay_debt');
    final canToggle = Perms.has('subscribers.toggle');
    final canDelete = Perms.has('subscribers.delete');
    // لو ما عنده أي عملية مجمّعة — البار كامل ما يحتاج يظهر.
    if (!canRenew && !canPayDebt && !canToggle && !canDelete) {
      return const SizedBox.shrink();
    }
    // مطلب المستخدم 2026-07-12: تصميم مضغوط — صفّان بدل 4:
    //   Row1 (primary): Renew | Pay debt | Disconnect (كل ما يظهر يتقاسم العرض)
    //   Row2 (secondary): Disable | Enable | Delete
    // ارتفاع أقل بـ~40% من التصميم القديم؛ زر Renew يبقى أول+مهيمن.
    final showPay = debtorCount > 0 && canPayDebt;
    final showDisconnect = onlineCount > 0 && canToggle;
    final primaryChildren = <Widget>[];
    if (canRenew) {
      primaryChildren.add(Expanded(
        flex: 2,
        child: _PrimaryPill(
          icon: LucideIcons.calendarPlus,
          label: '${'subscribers.bulk_renew'.tr()} ($selectedCount)',
          color: AppColors.brand,
          onTap: onRenew,
        ),
      ));
    }
    if (showPay) {
      if (primaryChildren.isNotEmpty) {
        primaryChildren.add(const SizedBox(width: 6));
      }
      primaryChildren.add(Expanded(
        child: _PrimaryPill(
          icon: LucideIcons.banknote,
          label: '${'subscribers.pay_debt'.tr()} ($debtorCount)',
          color: AppColors.success,
          onTap: onPayDebt!,
        ),
      ));
    }
    if (showDisconnect) {
      if (primaryChildren.isNotEmpty) {
        primaryChildren.add(const SizedBox(width: 6));
      }
      primaryChildren.add(Expanded(
        child: _PrimaryPill(
          icon: LucideIcons.power,
          label: '${'subscribers.disconnect_online'.tr()} ($onlineCount)',
          color: AppColors.error,
          onTap: onDisconnect!,
        ),
      ));
    }

    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border(
            top: BorderSide(color: AppColors.border),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(Sp.md, Sp.sm, Sp.md, Sp.sm),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (primaryChildren.isNotEmpty) Row(children: primaryChildren),
            if (primaryChildren.isNotEmpty && (canToggle || canDelete))
              const SizedBox(height: 6),
            // Secondary row: Disable / Enable / Delete
            if (canToggle || canDelete)
              Row(
                children: [
                  if (canToggle) ...[
                    Expanded(
                      child: _SecondaryBtn(
                        icon: LucideIcons.ban,
                        label: enabledCount > 0
                            ? '${'subscribers.disable'.tr()} ($enabledCount)'
                            : 'subscribers.disable'.tr(),
                        color: AppColors.warning,
                        enabled: enabledCount > 0,
                        onTap: onDisable,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: _SecondaryBtn(
                        icon: LucideIcons.circleCheck,
                        label: disabledCount > 0
                            ? '${'subscribers.enable'.tr()} ($disabledCount)'
                            : 'subscribers.enable'.tr(),
                        color: AppColors.brand,
                        enabled: disabledCount > 0,
                        onTap: onEnable,
                      ),
                    ),
                    if (canDelete) const SizedBox(width: 6),
                  ],
                  if (canDelete)
                    Expanded(
                      child: _SecondaryBtn(
                        icon: LucideIcons.trash2,
                        label: 'subscribers.bulk_delete'.tr(),
                        color: AppColors.error,
                        onTap: onDelete,
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// زر أساسي مضغوط للـbulk bar. يحل محل FilledButton.icon الطويل الذي
/// كان يأخذ ~48px بالارتفاع؛ هذا يعطي ~36px + خط 12.5 + أيقونة 14.
class _PrimaryPill extends StatelessWidget {
  const _PrimaryPill({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return SizedBox(
      height: 36,
      child: FilledButton.icon(
        style: FilledButton.styleFrom(
          backgroundColor: color,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          minimumSize: const Size(0, 36),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(R.sm),
          ),
        ),
        onPressed: onTap,
        icon: Icon(icon, size: 14),
        label: Text(
          label,
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
          style: const TextStyle(
              fontWeight: FontWeight.w700, fontSize: 12.5, height: 1.4),
        ),
      ),
    );
  }
}

class _SecondaryBtn extends StatelessWidget {
  const _SecondaryBtn({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.enabled = true,
  });
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  /// When false the button greys out — used by the bulk bar to signal
  /// that no rows in the current selection are eligible for this
  /// action (e.g. all rows already disabled → 'تعطيل' has nothing
  /// to do).
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        side: BorderSide(color: color.withValues(alpha: 0.4)),
        padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 4),
        minimumSize: const Size(0, 34),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(R.sm),
        ),
      ),
      onPressed: enabled ? onTap : null,
      icon: Icon(icon, size: 13),
      label: Text(label,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
              fontWeight: FontWeight.w700, fontSize: 11.5, height: 1.35)),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.filter, required this.query});
  final SubscriberFilter filter;
  final String query;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final msg = query.isNotEmpty
        ? 'subscribers.no_search_results'.tr(namedArgs: {'q': query})
        : 'subscribers.empty_filter'.tr();
    return ListView(
      // ListView so RefreshIndicator can still pull-to-refresh.
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(height: MediaQuery.sizeOf(context).height * 0.2),
        Icon(LucideIcons.inbox, size: 40, color: AppColors.textLow),
        const SizedBox(height: Sp.sm),
        Text(
          msg,
          textAlign: TextAlign.center,
          style: AppType.label(color: AppColors.textMid)
              .copyWith(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

// مطلب 2026-06-11 (تحديث ثالث): زر التكويل انتقل إلى _SearchHeader
// بجانب زر الفرز فما عاد الـ_CollapseAllChip هنا له داعي.

/// كارت "إجمالي الديون" — نظير v1 (subscribers_screen.dart:875). يظهر
/// عند فلتر "المدينون" ويعرض الإجمالي + العدد. لأنّه يأخذ [subscribers]
/// من `_filteredAll`، هو تلقائياً محكوم بفلتر المدير الفرعي وأي بحث
/// نصّي حالي — بلا حاجة لـproviders أو حسابات خارجيّة.
class _DebtSummaryCard extends StatelessWidget {
  const _DebtSummaryCard({required this.subscribers});
  final List<Subscriber> subscribers;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    if (subscribers.isEmpty) return const SizedBox.shrink();
    var total = 0.0;
    for (final s in subscribers) {
      total += s.debtAbs;
    }
    final count = subscribers.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Sp.lg, 4, Sp.lg, 0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.warningSoftBg,
          borderRadius: BorderRadius.circular(R.sm),
          border: Border.all(
            color: AppColors.warningSoftBorder,
          ),
        ),
        child: Row(
          children: [
            Icon(
              LucideIcons.wallet,
              size: 13,
              color: AppColors.warning,
            ),
            const SizedBox(width: 6),
            Text(
              'إجمالي الديون:',
              style: AppType.muted().copyWith(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  '${formatIQD(total)} د.ع  •  $count مشترك',
                  style: AppType.bodyBold(color: AppColors.warning),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// زرّ «إعادة تعيين» في شريط شيت التصفية — كان رابطاً نصّيّاً في الرأس،
/// وهو إجراء لا عنوان فمكانه مع أزرار التنفيذ.
class _ResetFilterButton extends StatelessWidget {
  const _ResetFilterButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return SizedBox(
      height: H.button,
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.button),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(R.button),
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(R.button),
              border: Border.all(color: AppColors.borderSoft),
            ),
            padding: const EdgeInsets.symmetric(horizontal: Sp.lg),
            child: Center(
              child: Text('إعادة تعيين',
                  style: AppType.button(color: AppColors.textBody)),
            ),
          ),
        ),
      ),
    );
  }
}

/// ذيل القائمة: «تحميل المزيد» بدل شريط ترقيم الصفحات.
///
/// الترقيم يفترض أنّ المستخدم يتنقّل في فهرس مرتّب، وهو ليس كذلك هنا:
/// القائمة نتيجة بحث وفرز يتغيّران باستمرار، و«الصفحة الرابعة» لا
/// تعني شيئاً بعد تغيير الفرز. والزرّ داخل القائمة لا تحتها، فلا يحجز
/// ارتفاعاً ثابتاً حين لا يبقى ما يُحمَّل.
class _LoadMoreButton extends StatelessWidget {
  const _LoadMoreButton({required this.remaining, required this.onTap});

  final int remaining;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, Sp.md, 0, Sp.sm),
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.card),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(R.card),
          child: Container(
            height: 46,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(R.card),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(LucideIcons.chevronDown,
                    size: 15, color: AppColors.brandAccent),
                const SizedBox(width: 7),
                Text(
                  'تحميل المزيد',
                  style: AppType.button(color: AppColors.brandAccent),
                ),
                const SizedBox(width: 6),
                Text(
                  '($remaining)',
                  style: AppType.muted(color: AppColors.textLow),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// مفوِّض شريط شرائح الفلتر المثبَّت.
///
/// الشرائح وحدها تثبت من بين صفوف الرأس الأربعة السابقة: هي التنقّل
/// الأساسي في الشاشة، والبحث وشريط الفرز يُستعملان مرّة ثمّ يُنسيان
/// فيمشيان مع التمرير.
///
/// ⚠️ `ColoredBox` بلون الخلفيّة داخل الطفل ضروريّ لا تجميليّ:
/// الشريط المثبَّت يطفو فوق البطاقات وهي تمرّ تحته، وبلا خلفيّة
/// معتمة تظهر البطاقات من خلاله.
class _ChipsBarDelegate extends SliverPersistentHeaderDelegate {
  _ChipsBarDelegate({
    required this.child,
    required this.compactChild,
    required this.compact,
  }) : isDark = AppColors.isDark;

  /// المحتوى وقت الاستقرار في الأعلى — شرائح الفلتر.
  final Widget child;

  /// المحتوى بعد انزلاق الرأس — شريط بحث نحيف.
  final Widget compactChild;
  final bool compact;

  /// لقطة من راية الوضع الليلي وقت الإنشاء. `shouldRebuild` تقارنها
  /// حتى يُعاد رسم الشريط عند تبديل الثيم — بدونها يبقى بلوحته
  /// القديمة بينما تنقلب بقيّة الشاشة (نفس فخّ ترويسة الداشبورد).
  final bool isDark;

  /// ارتفاع الشريحة + تنفّس فوقها وتحتها. ثابت في الحالتين: تغيّره مع
  /// التبديل يُقفز المحتوى تحته.
  static const double _height = H.chipSm + 12;

  @override
  double get minExtent => _height;
  @override
  double get maxExtent => _height;

  /// ⚠️ بلا `AnimatedSwitcher` — وإزالتها إصلاح عطل لا تبسيط.
  ///
  /// بلاغ 2026-08-31: فيضٌ لا ينقطع في قسم «غير مفعّل» وغيره —
  ///   Failed assertion: '!semantics.parentDataDirty': is not true.
  ///   Null check operator used on a null value
  /// مئات المرّات في الثانية، بلا توقّف.
  ///
  /// السبب أُثبت بالعزل (اختبار بنفس البنية: مع المبدّل 4 أخطاء، بلاه
  /// صفر): المبدّل يُبقي الطفل الخارج حيّاً 180ms أثناء التلاشي. وعتبة
  /// الانضغاط هنا 56/40 بكسل — تمريرة سريعة تعبرها ذهاباً وإياباً داخل
  /// تلك النافذة، فيعود **نفس** المفتاح (`ValueKey('chips')`) بينما
  /// القديم ما زال خارجاً. فيقع «Duplicate keys found»، وتنكسر شجرة
  /// العناصر، ثمّ يفيض محرّك الدلالات على الشجرة المكسورة إلى الأبد.
  ///
  /// و`AnimatedCrossFade` ليست بديلاً: تُبقي الطفلين مركَّبَين دائماً،
  /// فيصير `_searchCtrl` مربوطاً بحقلَي نصّ وزرَّي إملاء معاً.
  ///
  /// الثمن: التبديل صار فوريّاً بلا تلاشٍ 180ms. والارتفاع ثابت في
  /// الحالتين أصلاً، فلا قفزة.
  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlaps) =>
      SizedBox(
        height: _height,
        child: compact ? compactChild : child,
      );

  @override
  bool shouldRebuild(_ChipsBarDelegate old) =>
      old.child != child ||
      old.compactChild != compactChild ||
      old.compact != compact ||
      old.isDark != isDark;
}

/// الشريط النحيف الذي يحلّ محلّ شرائح الفلتر بعد انزلاق الرأس.
///
/// اختير هذا على «إخفاء الرأس كلّه» لأنّ حبّة البحث العائمة رُفعت من
/// هذه الشاشة (2026-08-30): لو ذهب الرأس بالكامل لصار البحث في قائمة
/// من مئات الصفوف يتطلّب رجوعاً إلى القمّة أوّلاً. هنا البحث يبقى على
/// بُعد لمسة، بالارتفاع نفسه الذي كانت تشغله الشرائح — بلا كلفة.
class _CompactSearchBar extends StatelessWidget {
  const _CompactSearchBar({
    required this.controller,
    required this.filterActive,
    required this.onFilter,
    required this.onBackToTop,
  });

  final TextEditingController controller;
  final bool filterActive;
  final VoidCallback? onFilter;
  final VoidCallback onBackToTop;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return ColoredBox(
      color: AppColors.bg,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Sp.lg, 4, Sp.lg, 4),
        child: Row(
          children: [
            // العودة للقمّة: تكشف الرأس الكامل بشرائحه وأزراره. سهم
            // لأعلى لا أيقونة فلتر — الوجهة أصدق من الوظيفة هنا.
            InkResponse(
              radius: 18,
              onTap: onBackToTop,
              child: Icon(Icons.keyboard_arrow_up_rounded,
                  size: 20, color: AppColors.textLow),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Container(
                height: H.chipSm,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(R.pill),
                  border: Border.all(color: AppColors.borderSoft),
                ),
                child: Row(
                  children: [
                    Icon(Icons.search_rounded,
                        size: 16, color: AppColors.textLow),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: controller,
                        style: AppType.body(color: AppColors.textHi),
                        decoration: InputDecoration(
                          hintText: 'subscribers.search_hint'.tr(),
                          hintStyle: AppType.body(color: AppColors.textLow),
                          border: InputBorder.none,
                          isCollapsed: true,
                        ),
                      ),
                    ),
                    if (controller.text.isNotEmpty)
                      InkResponse(
                        radius: 16,
                        onTap: controller.clear,
                        child: Icon(Icons.close_rounded,
                            size: 16, color: AppColors.textLow),
                      )
                    else
                      VoiceSearchButton(controller: controller, size: 17),
                  ],
                ),
              ),
            ),
            if (onFilter != null) ...[
              const SizedBox(width: 8),
              _HeaderIconButton(
                icon: LucideIcons.slidersHorizontal,
                active: filterActive,
                onTap: onFilter!,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
