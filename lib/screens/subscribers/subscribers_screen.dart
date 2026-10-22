import 'dart:async';
import 'dart:ui' as ui;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/platform/app_platform.dart';
import '../../api/bulk_activate_api.dart';
import '../../api/device_probe_api.dart';
import '../../models/device_health.dart';
import '../../api/subscribers_api.dart';
import '../../api/big_subscribers_api.dart';
import '../../api/managers_api.dart';
import '../../api/company_route.dart';
import '../../api/telegram_api.dart';
import '../../api/whatsapp_api.dart';
import '../../core/util/fit_hint.dart';
import '../../core/util/format.dart';
import '../../core/widgets/permission_locked.dart';
import '../../core/widgets/sheet_scaffold.dart';
import '../../models/subscriber.dart';
import '../../models/merged_company.dart';
import '../../services/merged_mode.dart';
import '../../widgets/merged_company_strip.dart';
import '../../services/active_company.dart';
import '../../services/auth_storage.dart';
import '../../services/connection_alerts.dart';
import '../../services/permissions_service.dart';
import '../../services/provider_service.dart';
import '../../services/subscriber_events.dart';
import '../../services/subscriber_usage_store.dart';
import '../../core/widgets/design_sheet.dart';
import '../../core/widgets/voice_search_button.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import '../../widgets/active_company_line.dart';
import '../../services/provider_limits.dart';
import '../top_actions.dart';
import 'sheets/bulk_activate_sheet.dart';
import 'sheets/bulk_pay_debt_sheet.dart';
import 'sheets/pay_debt_sheet.dart';
import 'connection_alert_flow.dart';
import 'subscriber_detail_screen.dart';
import 'widgets/device_chip_micro.dart';
import 'widgets/filter_chips_bar.dart';
import 'widgets/sort_sheet.dart';
import 'sheets/location_sheets.dart';
import 'widgets/subscriber_card_v3.dart';
import 'widgets/subscriber_table_row.dart';

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
  // «مهمَل» — بلا باقة ولا انتهاء، فالفرز الوحيد ذو المعنى هو اليوزر.
  SubscriberFilter.neglected: (SortField.username, SortDirection.asc),
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
  /// موجة فحصٍ جارية — يقرؤها زرّ «فحص الأجهزة» وحده ليعرض دوّارته.
  /// ولا عدّاد معها: المقدار المعروض حُذف، فلا داعي لتتبّعه.
  bool _probing = false;

  /// آخر إيقاظٍ لبطاقات الأجهزة — لخنق تواتره أثناء الموجة.
  DateTime? _lastProbeBump;

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

  // ── الحسابات الكبيرة (BigSubscribersApi، ٢١ أكتوبر) ──
  // ≥ ٥٠٠٠ مشترك: لا قائمة كاملة (٨٩ ألفاً ≈ ٩٦ث كانت تُعاد كلّ ٥ ثوانٍ). الصفحة والتبويب والبحث والترتيب وفلتر المدير
  // من الخادم، والعدّادات من summary.app بتعريفات هذه الشاشة نفسها. «مديون» من notes الساس (سوبرنت)؛ شركةٌ دينها على
  // دفترنا: نصٌّ يقول لماذا (TAB_UNSUPPORTED).
  bool _big = false;

  /// «متوسّط» (BigSubscribersApi.progressiveMin–threshold) قبل وصول القائمة الكاملة: الصفحات بطريقة الكبير بلا ملخّص (لا
  /// يزاحم القائمة على ساسٍ بطيء) والشرائح «…»؛ حين تصل القائمة يعود كلّ شيءٍ كما كان (_big = false).
  bool _progressive = false;
  bool _bigDebtorsUnsupported = false;
  List<ManagerLite>? _bigManagers;
  int? _bigParentId;
  // فلتر الباقة للكبير: المعرّف من كتالوج الباقات (المفتاح = profile_id) — الساس يفلتر به
  Map<String, PackageInfo>? _bigPackages;
  int? _bigProfileId;
  List<Subscriber> _bigRows = const [];
  int _bigTotal = 0;
  int _bigLastPage = 1;
  int _bigPageLoaded = 0;
  bool _bigLoadingMore = false;
  String? _bigError;
  BigCounts? _bigCounts;
  int _bigGen = 0;
  int _bigTick = 0;

  // ── «كل الشركات» (MergedMode، ٢١ أكتوبر): قوائم شركات الحساب مدموجةً (MergedSubscribers) — كلّ صفٍّ بشركته
  // (Subscriber.companyKey)، والفلاتر والعدّادات والبحث كالوضع العاديّ على الصفوف المدموجة. التحديد الجماعيّ للشركة وحدها.
  MergedListResult? _merged;
  int _mergedTick = 0;

  /// تحميلٌ أحدث يغلب ردّ تحميلٍ أقدم (القائمة ثمّ جلساتها ردّان منفصلان).
  int _mergedGen = 0;

  /// «كل الشركات»: آخر الدفعات وارتباطات تلغرام لكلّ شركة — موجَّهةً بمعرّف مديرها، لا من الشركة المفتوحة (يوزرٌ أو idx
  /// يتكرّر بين شركتين فيُلصق بصفٍّ ما ليس له). تُجلب مع القائمة وكلّ ٥ دقائق على الأكثر.
  final Map<String, Map<String, Map<String, dynamic>>> _mergedPayments = {};
  final Map<String, Set<String>> _mergedTelegram = {};
  DateTime? _mergedSideAt;
  bool get _mergedOn => MergedMode.active.value;
  static const int _kBigPageSize = 50;

  String _bigTab(SubscriberFilter f) => switch (f) {
        SubscriberFilter.all => 'all',
        SubscriberFilter.active => 'active_all',
        SubscriberFilter.online => 'online_all',
        SubscriberFilter.offline => 'offline',
        SubscriberFilter.disabled => 'disabled',
        SubscriberFilter.expired => 'expired_all',
        SubscriberFilter.debtors => 'debtors',
        SubscriberFilter.nearExpiry => 'near_expiry',
        SubscriberFilter.onlineNoPlan => 'online_no_plan',
        SubscriberFilter.neglected => 'neglected',
      };

  /// ما يرتّب به الساس: الباقي والانتهاء بالانتهاء (الترتيب نفسه)، واليوزر والاسم كما هما؛ وغيرها ⇒ اليوزر.
  String? get _bigSort => switch (_sortField) {
        SortField.remainingDays || SortField.expiration => 'expiration',
        SortField.username => 'username',
        SortField.firstname => 'firstname',
        _ => null,
      };

  String get _bigDir => _sortDir == SortDirection.asc ? 'asc' : 'desc';

  /// الصفحة الأولى للتبويب الحاليّ + العدّادات. جيلٌ لكلّ طلب: ردٌّ وصل بعد تغيير التبويب/البحث لا يُكتب.
  /// [fresh]: السحب للتحديث وبعد عمليّة — العدّادات بلا ذاكرة الـ٢٠ثانية.
  Future<void> _bigReload({bool fresh = false}) async {
    final gen = ++_bigGen;
    final tab = _bigTab(_filter);
    final countsF = _progressive
        ? Future<BigCounts?>.value(null)
        : BigSubscribersApi.summary(parentId: _bigParentId, profileId: _bigProfileId, fresh: fresh);
    try {
      final p = await BigSubscribersApi.page(
          page: 1, size: _kBigPageSize, tab: tab, query: _query, sort: _bigSort, dir: _bigDir,
          parentId: _bigParentId, profileId: _bigProfileId);
      final c = await countsF;
      if (!mounted || gen != _bigGen) return;
      setState(() {
        _bigRows = p.rows;
        _bigTotal = p.total;
        _bigLastPage = p.lastPage;
        _bigPageLoaded = 1;
        _bigLoadingMore = false;
        _bigError = null;
        _bigDebtorsUnsupported = false;
        _bigCounts = c ?? _bigCounts;
      });
      _bigSoonIfPending(c);
      _runProbeWave();
    } on BigListException catch (e) {
      final c = await countsF;
      if (!mounted || gen != _bigGen) return;
      // صفوف التبويب السابق لا تبقى تحت رسالة التبويب الجديد
      final unsupported = e.code == 'TAB_UNSUPPORTED';
      setState(() {
        _bigRows = const [];
        _bigTotal = 0;
        _bigLastPage = 1;
        _bigPageLoaded = 0;
        _bigLoadingMore = false;
        _bigDebtorsUnsupported = unsupported;
        _bigError = unsupported ? null : e.message;
        _bigCounts = c ?? _bigCounts;
      });
    }
  }

  /// عدد المدينين يُحسب في الخادم أوّل مرّة (قراءة قطعتهم كلّها، دقيقةٌ أو اثنتان لـ٨٩ ألفاً) — نسأل بعد ١٥ثانية لا دقيقة.
  void _bigSoonIfPending(BigCounts? c) {
    if (c != null && c.debtorsPending) _bigTick = 9;
  }

  int? _bigPackageId(String? name) {
    if (name == null) return null;
    for (final e in (_bigPackages ?? const <String, PackageInfo>{}).entries) {
      if (e.value.name == name) return int.tryParse(e.key);
    }
    return null;
  }

  int? _bigManagerId(String? username) {
    if (username == null) return null;
    for (final m in _bigManagers ?? const <ManagerLite>[]) {
      if (m.username == username) return m.id;
    }
    return null;
  }

  /// «تحميل المزيد» = الصفحة التالية من الخادم (بلا تكرار صفٍّ ظهر).
  Future<void> _loadBigMore() async {
    if (_bigLoadingMore || _bigPageLoaded >= _bigLastPage) return;
    final gen = _bigGen;
    setState(() => _bigLoadingMore = true);
    try {
      final p = await BigSubscribersApi.page(
          page: _bigPageLoaded + 1,
          size: _kBigPageSize,
          tab: _bigTab(_filter),
          query: _query,
          sort: _bigSort,
          dir: _bigDir,
          parentId: _bigParentId,
          profileId: _bigProfileId);
      if (!mounted || gen != _bigGen) return;
      final seen = _bigRows.map((s) => s.idx ?? s.username).toSet();
      setState(() {
        _bigRows = [..._bigRows, ...p.rows.where((s) => !seen.contains(s.idx ?? s.username))];
        _bigTotal = p.total;
        _bigLastPage = p.lastPage;
        _bigPageLoaded += 1;
        _bigLoadingMore = false;
      });
    } on BigListException catch (e) {
      if (!mounted || gen != _bigGen) return;
      setState(() {
        _bigLoadingMore = false;
        _bigError = e.message;
      });
    }
  }

  /// عدّادات الشرائح للحساب الكبير — «مديون» غير معروف -1 ⇒ «—» (لا صفر)، وجارٍ حسابه -2 ⇒ «…».
  Map<SubscriberFilter, int> _bigCountsMap() {
    // المتوسّط قبل القائمة: العدّادات منها حين تصل (لا أرقامٌ تتبدّل)
    if (_progressive) return {for (final f in SubscriberFilter.values) f: -2};
    final c = _bigCounts;
    if (c == null) return const {SubscriberFilter.debtors: -1};
    return {
      SubscriberFilter.all: c.all,
      SubscriberFilter.active: c.active,
      SubscriberFilter.online: c.online,
      SubscriberFilter.offline: c.offline,
      SubscriberFilter.disabled: c.disabled,
      SubscriberFilter.expired: c.expired,
      SubscriberFilter.debtors: c.debtors ?? (c.debtorsPending ? -2 : -1),
      SubscriberFilter.nearExpiry: c.nearExpiry,
      SubscriberFilter.onlineNoPlan: c.onlineNoPlan,
      SubscriberFilter.neglected: 0,
    };
  }

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
    MergedMode.active.addListener(_onMergedModeChanged);
    MergedMode.focus.addListener(_onMergedFocus);
    PermissionsService.changes.addListener(_onPermsChanged);
    _wasLocked = _locked;
    if (!_locked) _load();
    // حدود «تنبيه المشترك» — شريط المشكلة يعمل بالافتراضيّات حتّى تصل
    // حدود المدير، ثمّ يُعاد رسمه وحده عبر `ConnectionAlertSettings.current`.
    // والمقفل لا يطلبها: لا قائمة يُرسم عليها شريط.
    if (!_locked) ConnectionAlertSettings.ensureLoaded();
    _searchCtrl.addListener(_onSearchChanged);
    widget.isActive?.addListener(_onActiveChanged);
    // «عرض الاستهلاك» (شيت الترتيب) — يُعاد رسم الكارتات بسطرها أو بدونه.
    UsagePrefs.enabled.addListener(_onUsagePref);
    _startAutoRefresh();
  }

  void _onUsagePref() {
    if (mounted) setState(() {});
  }

  /// بلا `subscribers.view`: التبويب يبقى في مكانه وشاشته إطارٌ مقفل —
  /// **بلا أيّ نداء** (بلاغ ٢٠٢٦-١٠-١٤). كان `_load` يُطلق `v2/subscribers`
  /// فيردّه الخادم 403 وتبقى الشاشة دوّارةً بيضاء أبداً. والمالك لا يُقفل:
  /// `Perms.has` صحيحةٌ له دائماً.
  bool get _locked => !Perms.has('subscribers.view');
  bool _wasLocked = false;

  /// مفتاحٌ مُنح أثناء الجلسة (تحديث `/me`): يبدأ التحميل والاستطلاع الآن.
  void _onPermsChanged() {
    if (!mounted) return;
    final locked = _locked;
    if (locked == _wasLocked) return;
    _wasLocked = locked;
    if (locked) {
      _autoRefreshTimer?.cancel();
      setState(() {});
    } else {
      ConnectionAlertSettings.ensureLoaded();
      _load();
      _startAutoRefresh();
    }
  }

  /// Timer صامت — يفجّر _silentRefresh كل 5 ثواني ما دام التطبيق active.
  /// نلغي ونعيد التشغيل عند resume، ونوقف تماماً في pause/inactive.
  /// الشاشة حيّة **ومرئيّة** معاً.
  bool get _mayRefresh => widget.isActive?.value ?? true;

  void _onActiveChanged() {
    if (_locked) return;
    if (_mayRefresh) {
      _startAutoRefresh();
      // تحديث فوري عند العودة: القيم قد تكون قديمة بدقائق. ولو وصل
      // حدث تغيير أثناء الاختفاء نُنفّذ تحديثاً كاملاً لا صامتاً.
      if (!_refreshing && !_loading) {
        if (_dataStale) {
          _refresh();
        } else {
          _silentRefresh();
        }
      }
    } else {
      _autoRefreshTimer?.cancel();
    }
  }

  void _startAutoRefresh() {
    _autoRefreshTimer?.cancel();
    // ⚠️ الحارس هنا لا عند الاستدعاء: ثلاثة مسارات تستدعيها
    // (initState · didChangeAppLifecycleState · _onActiveChanged)،
    // ونسيانه في واحدة يعيد الاستنزاف كاملاً. والمقفل لا يستطلع شيئاً.
    if (!_mayRefresh || _locked) return;
    _autoRefreshTimer = Timer.periodic(_autoRefreshInterval, (_) {
      if (!mounted || !_appActive) return;
      // نتفادى overlap مع pull-to-refresh أو _load الأولي. نستخدم
      // نافذة زمنية بدل قفل صريح — لو حصل sync أثناء poll، الـpoll
      // يتخطّى ويأخذ الدور التالي بعد 5 ثواني.
      if (_refreshing || _loading) return;
      // شبكة الأمان: لو أفلتت كلّ المسارات الأخرى، النبضة تلتقط الفارق
      // خلال خمس ثوانٍ. `_refresh` لا `_silentRefresh` لأنّ الأخيرة
      // تمرّ بكاش الـ45 ثانية فقد تُعيد اللقطة القديمة نفسها.
      if (_dataStale) {
        _refresh();
        return;
      }
      _silentRefresh();
    });
  }

  Future<void> _silentRefresh() async {
    // «كل الشركات»: قوائم الشركات كلّ دقيقة (لا كلّ ٥ ثوانٍ — نداءٌ ثقيل لكلّ شركة)
    if (_mergedOn) {
      if (++_mergedTick % 12 != 0) return;
      await _loadMerged();
      return;
    }
    if (_big) {
      // المتوسّط: القائمة الكاملة في الطريق — هي التحديث
      if (_progressive) return;
      // الكبير: لا قائمة كاملة ولا قائمة متصلين (عشرات الآلاف) كلّ ٥ ثوانٍ — العدّادات وحدها كلّ دقيقة. الصفوف تتحدّث
      // بالسحب أو بعد كلّ عمليّة (SubscriberEvents) — لا قفزة إلى الصفحة الأولى تحت إصبع من مرّر.
      if (++_bigTick % 12 != 0) return;
      final c = await BigSubscribersApi.summary(parentId: _bigParentId, profileId: _bigProfileId);
      if (!mounted || c == null) return;
      setState(() {
        _bigCounts = c;
        // «مديون» بلا بحث: مجموع التبويب = العدّ الدقيق حين يكتمل (الصفحة تعطي حجم القطعة قبله)
        if (_filter == SubscriberFilter.debtors && _query.trim().isEmpty && c.debtors != null) _bigTotal = c.debtors!;
      });
      _bigSoonIfPending(c);
      return;
    }
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
      if (!_refreshing && !_loading && !_locked) _silentRefresh();
    }
    super.didChangeAppLifecycleState(state);
  }

  /// آخر نسخة بيانات رآها هذا الشاشة.
  ///
  /// 🐛 بلاغ 2026-08-31: «الداش بورد يتحدث تلقائي فقط المشتركون الا
  /// رفرش». الرئيسيّة مستمعها بلا بوّابة فتُحدَّث فوراً؛ وهذه بوّبتُها
  /// أمس لمنع `setState` على تبويب مخفيّ، فصار التحديث معلَّقاً على
  /// سلسلة أحداث (تغيّر الراية ← المستمع ← العلم) — وأيّ حلقة تُفلت
  /// تعني بياناتٍ بائتة إلى الأبد.
  ///
  /// الختم يقلب المنطق: بدل «تذكّر أن تُحدّث» صار «قارن ما رأيتَه بما
  /// هو موجود». المقارنة تصحّ من أيّ مسار — عودة التبويب أو نبضة
  /// الاستطلاع — فالتقارب مضمون خلال خمس ثوانٍ على أسوأ تقدير، لا
  /// معلَّقاً على حدثٍ قد لا يقع.
  int _seenDataVersion = SubscriberEvents.dataChanged.value;

  /// هل تغيّرت البيانات منذ آخر تحميل لهذه الشاشة؟
  bool get _dataStale => SubscriberEvents.dataChanged.value != _seenDataVersion;

  void _markDataSeen() => _seenDataVersion = SubscriberEvents.dataChanged.value;

  void _onDataChanged() {
    if (!mounted) return;
    // ⚠️ لا `setState` على تبويب مخفيّ.
    //
    // `SubscriberEvents.dataChanged` مُنبّه على مستوى العمليّة: أيّ
    // عمليّة في **أيّ** شاشة تُطلقه (شحن رصيد مدير مثلاً)، فتُعيد هذه
    // الشاشة البناء وهي غير مرئيّة داخل `IndexedStack`. وذلك يُفرّغ
    // `parentData` للدلالات عبر شجرتها بلا إعادة إسناد — راجع تعليق
    // `lazyTabChildren` في main_shell.
    //
    // ولا تضيع البيانات: العلم يُستهلك في `_onActiveChanged` لحظة
    // العودة، فيُحدَّث ما تراه قبل أن تراه.
    // مخفيّ ⇒ لا نفعل شيئاً ولا نختم. الفارق بين الختمين هو ما
    // يلتقطه أوّل مسارٍ يعود إلى الرؤية.
    if (!_mayRefresh || _locked) return;
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
    if (_big) _bigReload();
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
    MergedMode.active.removeListener(_onMergedModeChanged);
    MergedMode.focus.removeListener(_onMergedFocus);
    PermissionsService.changes.removeListener(_onPermsChanged);
    widget.isActive?.removeListener(_onActiveChanged);
    UsagePrefs.enabled.removeListener(_onUsagePref);
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  /// دخول «كل الشركات» أو الخروج منه: القائمة من جديد (لا يُعرض خليطٌ من الوضعين).
  void _onMergedModeChanged() {
    if (!mounted) return;
    setState(() {
      _all = const [];
      _merged = null;
      _mergedPayments.clear();
      _mergedTelegram.clear();
      _mergedSideAt = null;
      _big = false;
      _progressive = false;
      _selectionMode = false;
      _selected.clear();
    });
    _load();
  }

  /// «كل الشركات»: قوائم الشركات (مخبّأةٌ ٤٥ث لكلّ شركة، و[fresh] يتخطّاها) ثمّ الدمج.
  Future<void> _loadMerged({bool fresh = false}) async {
    final gen = ++_mergedGen;
    final r = await MergedSubscribers.load(fresh: fresh);
    if (!mounted || !_mergedOn || gen != _mergedGen) return;
    _markDataSeen();
    setState(() {
      _big = false;
      _progressive = false;
      _merged = r;
      _all = r.rowsFor(MergedMode.focused?.key);
      _loading = false;
    });
    final at = _mergedSideAt;
    if (fresh || at == null || DateTime.now().difference(at) > const Duration(minutes: 5)) {
      _mergedSideAt = DateTime.now();
      unawaited(_loadMergedSide(r));
    }
    // جلسات كلّ شركة بعد القائمة — كـ_fetchAndMerge في الوضع العاديّ: عنوان الجلسة ومدّتها والتحميل. عليها تقوم حالة
    // الاتصال بالكارت (الإشارة، الـONU، النانو): صفٌّ بلا عنوانٍ ولا عنوانٍ مثبَّت لا يُفحص.
    final withSessions = await MergedSubscribers.withSessions(r, fresh: fresh);
    if (!mounted || !_mergedOn || gen != _mergedGen) return;
    if (!identical(withSessions, r)) {
      setState(() {
        _merged = withSessions;
        _all = withSessions.rowsFor(MergedMode.focused?.key);
      });
    }
    // الجديد وحده كلّ دقيقة، وموجةٌ جارية لا تُقطع.
    if (!_probing) _runProbeWave();
  }

  Future<void> _loadMergedSide(MergedListResult r) async {
    final cs = [
      for (final p in r.parts)
        if (p.rows != null) p.company,
    ];
    await Future.wait([
      for (final c in cs) ...[
        CompanyRoute.run(c.key, () => SubscribersApi.loadLastPayments(adminIdOverride: c.adminId))
            .then((m) {
          if (m != null) _mergedPayments[c.key] = m;
        }).catchError((_) {}),
        CompanyRoute.run(c.key, () => TelegramApi.listBindings(c.adminId)).then((b) {
          _mergedTelegram[c.key] = {for (final x in b) x.sas4Idx};
        }).catchError((_) {}),
      ],
    ]);
    if (mounted && _mergedOn) setState(() {});
  }

  /// شركةٌ اختيرت في الشريط (أو «الكل»): صفوفها وحدها كأنّها مفتوحة — من المحفوظ، بلا طلب.
  void _onMergedFocus() {
    final r = _merged;
    if (!mounted || !_mergedOn || r == null) return;
    setState(() {
      _all = r.rowsFor(MergedMode.focused?.key);
      _visibleCount = _kPageStep;
      _selectionMode = false;
      _selected.clear();
    });
    // صفوف الشركة المختارة أوّلاً (المفحوص منها يُتخطّى)
    _runProbeWave();
  }

  /// حال شركةٍ صالحة على الشريط لا تُختار: كبيرة (تُفتح وحدها) أو تعذّرت قائمتها.
  String? _mergedProblem(MergedCompany c) {
    final p = _merged?.partOf(c.key);
    if (p == null) return null;
    if (p.bigTotal != null) return 'merged.chip_big'.tr();
    if (p.rows == null) return 'merged.chip_failed'.tr();
    return null;
  }

  /// ما لا يظهر في «كل الشركات» ولماذا — سطرٌ واحد يسمّي كلّ شركة (لا أصفارٌ صامتة). شركةٌ مختارة: ما يخصّها وحده.
  String? _mergedNoticeText(MergedListResult r) {
    final f = MergedMode.focused;
    if (f != null) {
      final p = r.partOf(f.key);
      if (p == null) return null;
      if (p.bigTotal != null) return 'merged.big'.tr(args: [f.name, formatIQD(p.bigTotal!)]);
      if (p.rows == null) return p.error ?? 'merged.failed'.tr(args: [f.name]);
      return p.partial ? 'merged.partial'.tr(args: [f.name]) : null;
    }
    final parts = <String>[
      for (final b in r.big) 'merged.big'.tr(args: [b.company.name, formatIQD(b.bigTotal!)]),
      for (final f in r.failed) f.error ?? 'merged.failed'.tr(args: [f.company.name]),
      for (final p in r.partial) 'merged.partial'.tr(args: [p.company.name]),
      if (r.missing.isNotEmpty) 'merged.missing'.tr(args: [r.missing.map((c) => c.name).join('، ')]),
      if (r.folded > 0) 'merged.folded'.tr(args: [formatIQD(r.folded)]),
    ];
    return parts.isEmpty ? null : parts.join('\n');
  }

  Future<void> _load() async {
    setState(() => _loading = true);

    if (_mergedOn) {
      await _loadMerged();
      return;
    }

    // الحسابات الكبيرة: صفٌّ واحد يحسم قبل القائمة الكاملة — التي لا تُطلب للكبير أصلاً.
    final bigTotal = await BigSubscribersApi.probe();
    if (!mounted) return;
    if (bigTotal > 0) {
      _big = true;
      await _bigReload();
      if (!mounted) return;
      _markDataSeen();
      setState(() => _loading = false);
      // آخر الدفعات وارتباطات تلغرام (قاعدتنا، لا الساس) — مرّةً، بلا انتظار.
      unawaited(_loadBigSideData());
      return;
    }

    // ── المتوسّط (١٬٠٠٠–٥٬٠٠٠): الصفحة الأولى فوراً، والقائمة الكاملة تكمل في الخلفيّة ثمّ يعود كلّ شيءٍ كما كان ──
    // قائمةٌ طازجة في الذاكرة (الرئيسيّة جلبتها للتوّ) تُعرض فوراً بلا مرحلةٍ وسطى.
    if (BigSubscribersApi.knownProgressive && !SubscribersApi.hasFreshList) {
      final fullF = SubscribersApi.loadAll(); // تبدأ الآن — مخزَّنة ومشتركة مع الرئيسيّة
      _big = true;
      _progressive = true;
      await _bigReload();
      if (!mounted) return;
      setState(() => _loading = false);
      unawaited(_loadBigSideData());
      final full = await fullF;
      if (!mounted || !_progressive) return;
      if (full == null || full.isEmpty) {
        // القائمة الكاملة تعذّرت: تبقى الصفحات كالحساب الكبير — مع عدّاداتها من الملخّص
        setState(() => _progressive = false);
        unawaited(_bigReload());
        return;
      }
      setState(() {
        _big = false;
        _progressive = false;
        _all = full;
      });
      await _fetchAndMerge();
      if (!mounted) return;
      _markDataSeen();
      setState(() => _loading = false);
      _runProbeWave();
      return;
    }
    _big = false;
    _progressive = false;

    // ── اعرض القائمة فور وصولها، ولا تنتظر الإثراء ──
    //
    // 🐛 بلاغ 2026-08-31: «شاشة بيضاء 5 إلى 10 ثوانٍ عند دخول
    // المشتركين».
    //
    // `_fetchAndMerge` ينتظر **خمسة** نداءات معاً: القائمة + المتّصلون
    // + آخر الدفعات + الباقات + ارتباطات تلغرام. وكان `_load` يحجب
    // الشاشة كلّها حتّى ينتهي **أبطؤها** — والقائمة وحدها هي ما يلزم
    // للعرض؛ البقيّة إثراء (شارة متّصل، آخر دفعة، اسم الباقة) يظهر
    // بعدها بلا ضرر.
    //
    // ولم يكن هذا محسوساً قبل التبويبات الكسولة (4.0.4): الشاشة كانت
    // تُبنى وتُحمّل عند الإقلاع، فينتهي الانتظار قبل أن يفتحها أحد.
    // أزلتُ الهدر فظهر الانتظار — وهذا يردّه إلى مكانه.
    final quick = await SubscribersApi.loadAll();
    if (!mounted) return;
    if (quick != null && quick.isNotEmpty) {
      // `loadAll` مُخزَّنة 45 ثانية ومُلغّمة ضدّ التزامن، فاستدعاؤها
      // مرّتين لا يكلّف طلباً ثانياً.
      setState(() {
        _all = quick;
        _loading = false;
      });
    }

    await _fetchAndMerge();
    if (!mounted) return;
    _markDataSeen();
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
    // الكبير: الصفوف المحمَّلة وحدها (لا ٨٩ ألف فحص).
    // «كل الشركات»: كلّ صفٍّ بشركته — إعداد جهازه وافتراضاتها من شركته (٢٢ أكتوبر).
    var targets = (_big ? _bigRows : _all)
        .where((s) => s.username.isNotEmpty)
        .map<ProbeTarget>((s) => (
              username: s.username,
              ip: (s.ipAddress ?? '').trim(),
              company: s.companyKey,
            ))
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
              DeviceProbeApi.peek(
                  username: t.username, ip: t.ip, company: t.company) ==
              null)
          .toList();
    }

    if (targets.isEmpty) {
      setState(() {
        _probing = false;
      });
      return;
    }
    if (force) {
      // الـadmin يطلب تحديث صريح — نسقط الـcache كاملاً لكل المشتركين
      // المستهدفين بالـwave فالـwarmProbe يصير لهن جلسة probe جديدة.
      for (final t in targets) {
        DeviceProbeApi.invalidateIp(t.ip, company: t.company);
      }
      DeviceProbeBus.bump();
    }
    _lastProbeBump = null;
    setState(() => _probing = true);
    // مطلب المستخدم 2026-07-12: أولوية للـviewport-visible subs.
    // الـwave يفحص هؤلاء أوّلاً حتى المستخدم يشوف حالتهم فوراً بدون
    // انتظار الـ500 مشترك يخلصون. الـpage الحالية أفضل تقريب متاح.
    final visible = _visibleForCurrentPage();
    final priorityUsernames = visible.map((s) => s.username).toSet();

    DeviceProbeApi.warmProbe(
      targets,
      priorityUsernames: priorityUsernames.isEmpty ? null : priorityUsernames,
      // ⚠️ **بلا `setState`.** كان يُعيد بناء الشاشة كاملةً مع كلّ دفعة
      //    ليُحدّث رقم العدّاد — والرقم حُذف. و`DeviceProbeBus.bump()`
      //    وحده يوقظ بطاقات الأجهزة المرئيّة لتقرأ الكاش من جديد، وهي
      //    وحدها ما يحتاج التحديث.
      //
      // ⚠️ وبخنقٍ زمنيّ: بعد تحويل الموجة إلى حوض عمّالٍ صار هذا
      //    يُنادى **لكلّ هدف** لا لكلّ دفعة — ١١٢ إيقاظاً بدل خمسة.
      //    وكلّ إيقاظٍ يُعيد بناء كلّ بطاقة جهازٍ مرئيّة. وربع الثانية
      //    أسرع ممّا تلتقطه العين، فالخنق لا يُؤخّر شيئاً يُرى.
      onProgress: (done, total) {
        if (!mounted || _probeRunId != myRun) return;
        final now = DateTime.now();
        if (done >= total ||
            _lastProbeBump == null ||
            now.difference(_lastProbeBump!) >= const Duration(milliseconds: 250)) {
          _lastProbeBump = now;
          DeviceProbeBus.bump();
        }
      },
      isCanceled: () => !mounted || _probeRunId != myRun,
    ).whenComplete(() {
      if (!mounted || _probeRunId != myRun) return;
      // ⚠️ إيقاظٌ أخير غير مخنوق: آخر نتائج الموجة قد تقع داخل ربع
      //    الثانية الأخيرة فتُبتلع، فتبقى بطاقةٌ أو اثنتان فارغةً حتّى
      //    أوّل تمرير.
      DeviceProbeBus.bump();
      setState(() => _probing = false);
    });
  }

  /// snapshot للـsubs المرئيّين على الـpage الحالية. يُستعمل كـpriority
  /// لـwarmProbe. آمن لو الصفحة تغيّرت أثناء الـwave — الأولوية تُطبَّق
  /// على snapshot اللحظة، مو reactive.
  List<Subscriber> _visibleForCurrentPage() {
    if (_big) return _bigRows;
    if (_all.isEmpty) return const [];
    // نستعمل _filteredAll اللي بيه الفلترة/الفرز مُطبّقة أصلاً.
    final visible = _filteredAll;
    if (visible.isEmpty) return const [];
    return visible.take(_visibleCount).toList();
  }

  /// الكبير: آخر الدفعات وارتباطات تلغرام مرّةً (قاعدتنا) — شارتا البطاقة.
  Future<void> _loadBigSideData() async {
    final adminId = await AuthStorage.readAdminId();
    final results = await Future.wait([
      SubscribersApi.loadLastPayments(),
      if (adminId != null) TelegramApi.listBindings(adminId) else Future.value(const <TelegramBinding>[]),
      // فلتر المدير: المدراء من الساس (المعرّف لفلتر الساس parent_id) — لا من القائمة الكاملة
      ManagersApi.lite(),
      // فلتر الباقة: كتالوج الباقات (المعرّف لفلتر الساس profile_id)
      SubscribersApi.loadPackages(),
    ]);
    if (!mounted) return;
    setState(() {
      _lastPayments = (results[0] as Map<String, Map<String, dynamic>>?) ?? _lastPayments;
      _telegramBoundIdx = ((results[1] as List<TelegramBinding>?) ?? const []).map((b) => b.sas4Idx).toSet();
      _bigManagers = results[2] as List<ManagerLite>?;
      _bigPackages = results[3] as Map<String, PackageInfo>?;
    });
  }

  /// [pull]: سحبٌ يدويّ — «كل الشركات» يتخطّى مخبأ كلّ الشركات؛ وبعد عمليّةٍ تُجلب شركتها وحدها (أُسقطت قائمتها بعد الكتابة).
  Future<void> _refresh({bool pull = false}) async {
    if (_mergedOn) {
      setState(() => _refreshing = true);
      await _loadMerged(fresh: pull);
      if (!mounted) return;
      setState(() => _refreshing = false);
      return;
    }
    if (_big) {
      setState(() => _refreshing = true);
      await _bigReload(fresh: true);
      if (!mounted) return;
      _markDataSeen();
      setState(() => _refreshing = false);
      return;
    }
    setState(() => _refreshing = true);
    // Bypass the process-wide cache so pull-to-refresh always returns
    // fresh server data even if the cached entry is still warm.
    await SubscribersApi.refreshAll();
    await _fetchAndMerge();
    if (!mounted) return;
    _markDataSeen();
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
      // الكبير: البحث على كلّ المشتركين في الساس (اليوزر/الاسم/الهاتف).
      if (_big) _bigReload();
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
    // الكبير: مدراء الساس (lite) — الصفوف المحمَّلة صفحةٌ واحدة لا تكفي لمعرفتهم
    if (_big) return [for (final m in _bigManagers ?? const <ManagerLite>[]) m.username];
    final set = <String>{};
    for (final s in _all) {
      final p = s.parentUsername;
      if (p != null && p.isNotEmpty) set.add(p);
    }
    final list = set.toList()..sort();
    return list;
  }

  /// فلتر الباقة (٢١ أكتوبر، كالويب): اسم الباقة — يُرشّح القائمة والعدّادات معاً كفلتر المدير. الكبير: معرّفها للساس.
  String? _packageFilter;

  /// أسماء الباقات المتاحة للفلتر: من القائمة المحمَّلة، والكبير من كتالوج الباقات (الصفحة لا تكفي لمعرفتها).
  List<String> get _availablePackages {
    if (_big) {
      final names = [for (final p in (_bigPackages ?? const <String, PackageInfo>{}).values) p.name]..sort();
      return names;
    }
    final set = <String>{};
    for (final s in _all) {
      final p = s.profileName;
      if (p != null && p.isNotEmpty) set.add(p);
    }
    return set.toList()..sort();
  }

  /// Pre-filter source — apply the manager filter first so chip counts
  /// AND the main filter pipeline both work off the same subset.
  List<Subscriber> get _managerScoped {
    if (_managerFilter == null && _packageFilter == null) return _all;
    return _all
        .where((s) =>
            (_managerFilter == null || s.parentUsername == _managerFilter) &&
            (_packageFilter == null || s.profileName == _packageFilter))
        .toList();
  }

  // ───────── filtering / sorting (matches v1 predicates exactly) ─────────
  List<Subscriber> get _filteredAll {
    // 2026-10-12: القائمة الافتراضيّة وكلّ الفلاتر تستثني «المهمَل»
    // (حساباتٌ لم تُفعَّل قطّ) — عدا فلتر «مهمَل» نفسه الذي يعرضها وحدها.
    Iterable<Subscriber> it = _managerScoped.where((s) => !s.isAbandoned);
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
      case SubscriberFilter.neglected:
        // «مهمَل» وحده يعرض غير المفعّلين — فيبدأ من المصدر الكامل
        // (القاعدة أعلاه استثنتهم) ويُبقي المهمَل فقط.
        it = _managerScoped.where((s) => s.isAbandoned);
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
    // مقاييس الأجهزة مسارٌ مستقلّ: قيمتها تأتي من كاش الفحص لا من صفّ
    // المشترك، وغير المفحوص يغوص في الاتّجاهين معاً — وهو ما لا يعبّر
    // عنه مقارنٌ عاديّ.
    if (_deviceFields.contains(_sortField)) {
      final asc = _sortDir == SortDirection.asc;
      // 🐛 كان يقرأ الكاش بالـIP وحده، بينما البطاقة تقرؤه بالـusername
      // أوّلاً. فالمشترك ذو عنوان الجهاز المخصّص (customIp) تظهر قراءته
      // على بطاقته ويغوص في الفرز كأنّه غير مفحوص. والمفتاح يُحسب مرّةً
      // لكلّ مشترك لا مرّتين في كلّ مقارنة.
      final keys = <Subscriber, double?>{
        for (final s in list)
          s: _deviceSortKey(
            _sortField,
            DeviceProbeApi.cachedForUser(s.username, company: s.companyKey) ??
                DeviceProbeApi.cached(s.ipAddress ?? '', company: s.companyKey),
          ),
      };
      list.sort((a, b) {
        final ka = keys[a];
        final kb = keys[b];
        if (ka == null && kb == null) return 0;
        if (ka == null) return 1; // غير المفحوص أسفلَ دائماً
        if (kb == null) return -1;
        return asc ? ka.compareTo(kb) : kb.compareTo(ka);
      });
      return;
    }
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
        // استهلاك اليوم — الرقم في الصفّ أصلاً، فالفرز بلا كلفة.
        // ومن لم يستهلك يُعدّ صفراً لا مجهولاً: صفرٌ حقيقة لا نقص بيانات.
        case SortField.dailyTraffic:
          return (a.dailyTrafficTotal ?? 0).compareTo(b.dailyTrafficTotal ?? 0);
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
        // حقول الأجهزة لا تصل هنا — تُعالَج في المسار المستقلّ أعلى
        // الدالّة وتعود قبل بناء هذا المقارن. الفرع للاكتمال النحويّ.
        case SortField.deviceRx:
        case SortField.deviceTemp:
        case SortField.deviceSignal:
        case SortField.deviceCcq:
        case SortField.deviceLan:
          return 0;
      }
    }

    list.sort(_sortDir == SortDirection.asc ? cmp : (a, b) => -cmp(a, b));
  }

  /// يحوّل مقياس جهاز إلى رقم واحد قابل للمقارنة.
  ///
  /// اصطلاح الإشارة مقصود:
  ///   • RX الضوئي وإشارة اللاسلكي **سالبان** — الأقرب إلى الصفر أقوى.
  ///   • CCQ وسرعة LAN موجبان — الأعلى أفضل.
  ///   • حرارة الـONU موجبة — الأعلى أخطر، فـ«تنازليّ» يُقدّم الأسخن.
  ///   • منفذ LAN مفصول يُرجع -1 فيغوص تحت أيّ وصلة 10Mbps في
  ///     الاتّجاهين — المدير يريدهم آخراً دائماً لا أوّلاً في أحدهما.
  ///
  /// `null` = لا لقطة (الموجة لم تصله أو الفحص فشل) — يغوص أسفل
  /// القائمة بأيّ اتّجاه: سطرٌ غامض فوق سطور مفحوصة أسوأ من غيابه.
  static double? _deviceSortKey(SortField f, DeviceHealthSnapshot? snap) {
    if (snap == null) return null;
    switch (f) {
      case SortField.deviceRx:
        if (snap.kind != DeviceKind.ont || snap.ont == null) return null;
        return double.tryParse(snap.ont!.rxPower);
      case SortField.deviceTemp:
        if (snap.kind != DeviceKind.ont || snap.ont == null) return null;
        return double.tryParse(snap.ont!.temperature.trim());
      case SortField.deviceSignal:
        if (snap.kind != DeviceKind.ubiquiti || snap.ubnt == null) return null;
        return snap.ubnt!.signalDbm?.toDouble();
      case SortField.deviceCcq:
        if (snap.kind != DeviceKind.ubiquiti || snap.ubnt == null) return null;
        return snap.ubnt!.ccqPercent?.toDouble();
      case SortField.deviceLan:
        if (snap.kind != DeviceKind.ubiquiti || snap.ubnt == null) return null;
        final speed = snap.ubnt!.primaryLan?.speed ?? '';
        final m = RegExp(r'^(\d+)Mbps').firstMatch(speed);
        if (m == null) return snap.ubnt!.lanUp ? 0 : -1;
        return double.tryParse(m.group(1)!);
      default:
        return null;
    }
  }

  static const _deviceFields = {
    SortField.deviceRx,
    SortField.deviceTemp,
    SortField.deviceSignal,
    SortField.deviceCcq,
    SortField.deviceLan,
  };

  /// تسلسل مسافات — تُترجَم مرّة واحدة لعمر الصنف لا مرّة لكلّ مقارنة.
  static final RegExp _wsRun = RegExp(r'\s+');

  Map<SubscriberFilter, int> _counts() {
    // Manager-scoped so chip counters reflect the current sub-manager
    // pick: 'متصل (3)' means 3 online subs UNDER that manager, not 3
    // across the whole tenant. Matches v1 behaviour.
    final src = _managerScoped;
    // 2026-10-12: العدّادات العاديّة على القائمة المرئيّة (بلا المهمَل)
    // حتى تطابق ما تعرضه الشاشة؛ و«مهمَل» وحده يعدّ المستثنَين. نُثبِّتها
    // قائمةً حتى لا يُعاد ترشيح `isAbandoned` مع كلّ عدّاد.
    final visible = src.where((s) => !s.isAbandoned).toList();
    return {
      SubscriberFilter.all: visible.length,
      SubscriberFilter.active: visible.where((s) => s.isActive).length,
      // 2026-07-16: نفس التغيير في العدّ — مطابق لمنطق الفلتر أعلاه.
      SubscriberFilter.online:
          visible.where((s) => s.isOnline && !s.isExpired).length,
      SubscriberFilter.offline: visible.where((s) => s.isOffline).length,
      SubscriberFilter.disabled: visible.where((s) => s.isDisabled).length,
      SubscriberFilter.expired: visible.where((s) => s.isExpired).length,
      SubscriberFilter.debtors: visible.where((s) => s.hasDebt).length,
      SubscriberFilter.nearExpiry: visible.where((s) => s.isNearExpiry).length,
      SubscriberFilter.onlineNoPlan:
          visible.where((s) => s.isOnline && s.isExpired).length,
      SubscriberFilter.neglected: src.where((s) => s.isAbandoned).length,
    };
  }

  // ───────── selection ─────────
  void _toggleSelect(Subscriber s) {
    final id = s.idx;
    if (id == null || _mergedOn) return;
    HapticFeedback.selectionClick();
    final wasSelecting = _selectionMode;
    setState(() {
      if (_selected.contains(id)) {
        _selected.remove(id);
        if (_selected.isEmpty) _selectionMode = false;
      } else {
        _selected.add(id);
        _selectionMode = true;
      }
    });
    if (!wasSelecting && _selectionMode) _warmBulkCapability();
  }

  void _enterSelectionWith(Subscriber s) {
    final id = s.idx;
    // «كل الشركات»: العمليّات الجماعيّة للشركة وحدها (مساراتها لا تُوجَّه)
    if (id == null || _mergedOn) return;
    HapticFeedback.selectionClick();
    final wasSelecting = _selectionMode;
    setState(() {
      _selectionMode = true;
      _selected.add(id);
    });
    if (!wasSelecting) _warmBulkCapability();
  }

  /// حكم الخادم على التجديد الجماعيّ لهذا المدير — يُسأل لحظة دخول وضع
  /// التحديد (من الكاش إن كان طازجاً)، فيظهر «تجديد» مقفلاً بسببه قبل أن
  /// يُضغط. ايرث لنك مقفلٌ بلا سؤال، ومن لا يملك التفعيل مقفلٌ بصلاحيّته.
  void _warmBulkCapability() {
    if (ProviderService.isEarthlink ||
        ActiveCompany.current?.sasCode == 'earthlink') {
      return;
    }
    if (!Perms.hasAny(const ['subscribers.activate', 'subscribers.extend'])) {
      return;
    }
    unawaited(BulkActivateApi.capability());
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
  /// اختصار (قاعدة: عمليّات المشترك تطابق v1 حرفيّاً).
  ///
  /// ⚠️ لا بثّ هنا: الشيت نفسه يُطلق `SubscriberEvents.notifyChange` عند
  /// النجاح (pay_debt_sheet.dart) فيُسقط الكاش ويتحدّث الصفّ والدين
  /// والرئيسيّة. وكان `dataChanged.value++` هنا بثّاً ثانياً للحدث نفسه —
  /// جلبٌ مكرّرٌ بلا داعٍ (ومرّتان لكارت الإيرادات الذي لا يُهدّئ).
  Future<void> _payDebtFromList(Subscriber s) async {
    await showPayDebtSheet(context, s);
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
      if (_big) _bigReload();
    }
  }

  String _sortLabel() => sortFieldLabel(_sortField);

  /// شيت «تصفية القائمة» — النسخة الخفيفة من المخطّط: بلا رأس مفصول،
  /// عنوان 16/w700 مع «إعادة تعيين» في الطرف، شرائح، ثمّ زرّ «تطبيق».
  /// يستبدل صفّ `_ManagerFilterBar` المسطّح الذي كان تحت البحث.
  Future<void> _openManagerFilterSheet() async {
    final picked = await showModalBottomSheet<({String? manager, String? package})>(
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
        currentPackage: _packageFilter,
        packages: _availablePackages,
      ),
    );
    if (picked == null) return; // أُغلق بلا «تطبيق»
    setState(() {
      _managerFilter = normalizeManagerFilter(picked.manager);
      _packageFilter = normalizeManagerFilter(picked.package);
      _visibleCount = _kPageStep;
      if (_big) {
        _bigParentId = _bigManagerId(_managerFilter);
        if (_bigParentId == null) _managerFilter = null; // مديرٌ لا معرّف له في الساس: لا فلتر وهميّ
        _bigProfileId = _bigPackageId(_packageFilter);
        if (_bigProfileId == null) _packageFilter = null;
      }
    });
    if (_big) _bigReload();
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
    final keep = await showBulkActivateSheet(context, subs: selected);
    if (!mounted) return;
    // لم تُفتح أصلاً (حكم الخادم بالمنع): التحديد كما هو.
    if (keep == null) return;
    // كالويب: يبقى محدّداً من لم يُفعَّل ويجوز إرساله ثانيةً (رُفض، لم يُنفَّذ،
    // لم تُجلب بياناته، أو خارج حدّ الدفعة) — ليُكمَل بعد معالجة السبب، لا
    // ليُعاد تحديده باليد. ولا أحد ⇒ خروجٌ من التحديد.
    if (keep.isEmpty) {
      _exitSelection();
      return;
    }
    setState(() {
      _selected
        ..clear()
        ..addAll(keep);
      _selectionMode = true;
    });
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
      subtitle: 'subscribers.bulk_selected'.tr(namedArgs: {'count': '$count'}),
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
    if (_locked) return const _SubscribersLocked();
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
    // الكبير: الخادم فلتر ورتّب وبحث — الصفوف المحمَّلة كما وصلت، والباقي من مجموع التبويب كلّه.
    final filtered = _big ? _bigRows : _filteredAll;
    final counts = _big ? _bigCountsMap() : _counts();
    final managers = _availableManagers;
    final packages = _availablePackages;
    final page = _big ? _bigRows : filtered.take(_visibleCount).toList();
    final remaining = _big
        ? (_bigTotal > _bigRows.length ? _bigTotal - _bigRows.length : 0)
        : filtered.length - page.length;

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: _withDetailPane(SafeArea(
        bottom: false,
        child: Column(
          children: [
            // ⚠️ **عمر البيانات على الشاشة لا في الكود.** حين تُعرض
            // نسخةٌ محفوظة بلا شبكة، يجب أن يعرف المدير أنّها قديمة
            // قبل أن يقول لزبونه «عليك ٢٥ ألفاً». رقمٌ قديمٌ بلا علامة
            // يُتّخذ عليه قرار — وهو أسوأ من لا رقم.
            if (SubscribersApi.offlineSnapshotAt != null)
              _OfflineBanner(at: SubscribersApi.offlineSnapshotAt!),
            // ⚠️ البنية هنا ليست تجميلاً: كانت أربعة صفوف ثابتة فوق
            // القائمة (بحث · شرائح · فرز · ترقيم) تحجز نحو ثلث الشاشة
            // قبل أن يُرى مشترك واحد. الآن الشرائح وحدها تثبت — وهي
            // التنقّل الأساسي — والبحث وشريط الفرز يمشيان مع التمرير.
            Expanded(
              child: RefreshIndicator(
                color: AppColors.brand,
                onRefresh: () => _refresh(pull: true),
                child: _loading
                    // أوّل تحميل: العنوان وأزرار الأعلى بمكانها فوق الدوّارة —
                    // لا تختفي الإعدادات والإشعارات والمساعد حتّى تصل القائمة.
                    ? Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(
                                Sp.lg, Sp.sm, Sp.lg, 0),
                            child: TabHeader(title: 'subscribers.title'.tr()),
                          ),
                          Expanded(
                            child: Center(
                                child: CircularProgressIndicator(
                                    color: AppColors.brand)),
                          ),
                        ],
                      )
                    : CustomScrollView(
                        controller: _scrollCtrl,
                        // بلا هذا لا يعمل السحب للتحديث حين يفرغ الفلتر:
                        // المحتوى يملأ الشاشة تماماً ولا يفيض، فلا
                        // إفراط تمرير تلتقطه `RefreshIndicator`. كان
                        // `_EmptyState` يحمل `ListView` لهذا الغرض —
                        // وهو ما فجّر الشاشة.
                        physics: const AlwaysScrollableScrollPhysics(),
                        slivers: [
                          SliverToBoxAdapter(
                            child: Column(
                              children: [
                                Padding(
                                  // ‎8 تحت الشقّ (لا ‎12): أزرار الأعلى في
                                  // موضعها من الرئيسيّة نفسه حرفيّاً.
                                  padding: const EdgeInsets.fromLTRB(
                                      Sp.lg, Sp.sm, Sp.lg, Sp.sm),
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
                                          filterActive: _managerFilter != null || _packageFilter != null,
                                          sortLabel: _sortLabel(),
                                          onSort: _openSortSheet,
                                          onFilter: managers.isEmpty && packages.isEmpty
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
                                // «كل الشركات»: الشركات بعدد كلٍّ منها — اضغط شركة لعرض مشتركيها وحدها
                                if (_mergedOn && !_selectionMode && _merged != null)
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(Sp.lg, 0, Sp.lg, Sp.sm),
                                    child: MergedCompanyStrip(
                                      countOf: (c) => _merged?.countOf(c.key),
                                      total: _merged?.total,
                                      problemOf: _mergedProblem,
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
                                filterActive: _managerFilter != null || _packageFilter != null,
                                onFilter: managers.isEmpty && packages.isEmpty
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
                                      onSelect: (f) {
                                        setState(() {
                                          _filter = f;
                                          _applyDefaultSortFor(f);
                                          _visibleCount = _kPageStep;
                                        });
                                        if (_big) _bigReload();
                                      },
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
                                    !_selectionMode &&
                                    !_big)
                                  _DebtSummaryCard(subscribers: filtered),
                                // الكبير: مجموع الديون من الخادم (قراءة كلّ المدينين، لا الصفحة المحمَّلة) حين يكتمل
                                if (_big &&
                                    _filter == SubscriberFilter.debtors &&
                                    !_selectionMode &&
                                    !_bigDebtorsUnsupported &&
                                    _query.trim().isEmpty &&
                                    _bigCounts?.debtors != null &&
                                    _bigCounts?.totalDebt != null)
                                  _DebtSummaryCard(
                                      subscribers: const [],
                                      total: _bigCounts!.totalDebt,
                                      count: _bigCounts!.debtors),
                                if (_big &&
                                    _filter == SubscriberFilter.debtors &&
                                    !_bigDebtorsUnsupported &&
                                    (_bigCounts?.debtorsPending ?? false))
                                  _BigNotice(text: 'subscribers.big_debtors_counting'.tr()),
                                // الكبير: ما يختلف — «مديون» لشركةٍ دينها على دفترنا نصٌّ صريح بدل قائمةٍ فارغة، وخطأ الصفحة برسالته.
                                if (_big && _filter == SubscriberFilter.debtors && _bigDebtorsUnsupported)
                                  _BigNotice(text: 'subscribers.big_debtors_unavailable'.tr()),
                                if (_big && _bigError != null)
                                  _BigNotice(text: _bigError!, onRetry: _bigReload),
                                if (_mergedOn && _merged != null && _mergedNoticeText(_merged!) != null)
                                  _BigNotice(text: _mergedNoticeText(_merged!)!, onRetry: _refresh),
                                // 2026-09-14: عدّاد «يفحص الأجهزة n/N» حُذف بطلب صاحب
                                // المشروع — الدوّارة داخل زرّ فحص الأجهزة تكفي للدلالة
                                // على أنّ موجةً تعمل، وصفٌّ إضافيّ فوق القائمة يزاحم
                                // كلّ نتيجة.
                                //
                                // ⚠️ وحذفه **تسريعٌ لا تجميل**: عرضه كان يُلزم
                                // `onProgress` باستدعاء `setState` على الشاشة كلّها
                                // مع كلّ دفعة، والبناء الواحد هنا يُعيد حساب
                                // `_filteredAll` و`_counts()` (ثمانية مرورات على
                                // القائمة). فكان ثمن العدّاد خمس إعادات بناءٍ كاملة
                                // في كلّ موجة.
                                // 2026-08-29: شريط شرائح فرز الأجهزة (RX · إشارة · CCQ ·
                                // LAN) حُذف بطلب المستخدم — شيت «ترتيب القائمة» يغطّي
                                // الحاجة، والشريط كان يزاحم كلّ نتيجة بصفّ إضافي.
                              ],
                            ),
                          ),
                          if (page.isEmpty && _big && ((_filter == SubscriberFilter.debtors && _bigDebtorsUnsupported) || _bigError != null))
                            const SliverToBoxAdapter(child: SizedBox.shrink())
                          else if (page.isEmpty)
                            SliverFillRemaining(
                              hasScrollBody: false,
                              child:
                                  _EmptyState(filter: _filter, query: _query),
                            )
                          else ...[
                            if (_paneMode)
                              SliverPadding(
                                padding: const EdgeInsets.symmetric(horizontal: Sp.lg),
                                sliver: SliverToBoxAdapter(
                                  child: SubscriberTableHeader(columns: _tableColumns),
                                ),
                              ),
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
                                    SizedBox(height: _paneMode ? 0 : 6),
                                itemBuilder: (_, i) {
                                  if (i == page.length) {
                                    return _LoadMoreButton(
                                      remaining: remaining,
                                      onTap: _big
                                          ? _loadBigMore
                                          : () => setState(
                                              () => _visibleCount += _kPageStep),
                                    );
                                  }
                                  final s = page[i];
                                  final isSelected = s.idx != null &&
                                      _selected.contains(s.idx);
                                  // الحاسبة: صفّ جدولٍ مضغوط بدل البطاقة — أضعاف الصفوف على الشاشة.
                                  if (_paneMode) {
                                    return SubscriberTableRow(
                                      key: ValueKey('t|${s.companyKey ?? ''}|${s.idx ?? s.username}'),
                                      sub: s,
                                      columns: _tableColumns,
                                      open: _paneKey == _rowKey(s),
                                      selected: isSelected,
                                      selectionMode: _selectionMode,
                                      onTap: () {
                                        if (_selectionMode) {
                                          _toggleSelect(s);
                                        } else {
                                          _openDetail(s);
                                        }
                                      },
                                      onLongPress: () => _enterSelectionWith(s),
                                      last: i == page.length - 1 && remaining <= 0,
                                    );
                                  }
                                  return SubscriberCardV3(
                                    // بلا مفتاح ثابت يعيد Flutter استعمال
                                    // الـElement لمشترك آخر بعد كل موجة فحص
                                    // أجهزة فتنتقل حالة الصفّ للجار.
                                    // «كل الشركات»: idx واحد في ساسين ⇒ صفّان؛ الشركة جزء المفتاح.
                                    key: ValueKey('${s.companyKey ?? ''}|${s.idx ?? s.username}'),
                                    sub: s,
                                    selected: isSelected,
                                    lastPayment: s.companyKey == null
                                        ? _lastPayments[s.username]
                                        : _mergedPayments[s.companyKey]?[s.username],
                                    hasTelegram: s.idx != null &&
                                        (s.companyKey == null
                                                ? _telegramBoundIdx
                                                : (_mergedTelegram[s.companyKey] ?? const <String>{}))
                                            .contains(s.idx.toString()),
                                    showUsage: UsagePrefs.enabled.value,
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
                                    // الصلاحيّة: مبوّبٌ بـ`subscribers.send_whatsapp`
                                    // كشقيقه onPayDebt أدناه — بدونها كان يظهر
                                    // لمديرٍ مُنِع المراسلة (تدقيق ٢٠٢٦-١٠-٠٨).
                                    onSendDebtReminder: !_mergedOn &&
                                        Perms.has('subscribers.send_whatsapp') &&
                                                s.hasDebt &&
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
                                    // «تنبيه المشترك» — الشريط نفسه لا يظهر
                                    // إلّا حين يكشف آخر فحصٍ مشكلة. والإرسال
                                    // محكومٌ بصلاحيّة «إرسال رسالة لمشترك»
                                    // التي يفحصها الخادم على send-message.
                                    // «كل الشركات»: الإرسال للشركة وحدها ⇒ لا شريط ينتهي برفض؛
                                    // قراءة الجهاز نفسها تبقى على البطاقة.
                                    onAlertConnection: !_selectionMode &&
                                            s.companyKey == null &&
                                            Perms.has('whatsapp.send') &&
                                            s.displayPhone.isNotEmpty
                                        ? () => showConnectionAlertFlow(
                                            context, s)
                                        : null,
                                  );
                                },
                              ),
                            ),
                          ],
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
      )),
      // Selection bottom action bar
      // حكم الخادم على التجديد الجماعيّ يصل بعد دخول التحديد — الشريط يُعاد
      // رسمه به (يُقفل «تجديد» بسببه إن مُنع) بلا إعادة بناء الشاشة كلّها.
      bottomNavigationBar: _selectionMode
          ? ValueListenableBuilder<BulkActivateCapability?>(
              valueListenable: BulkActivateApi.listenable,
              builder: (_, __, ___) => _BulkActionBar(
                selectedCount: _selected.length,
                debtorCount: _selectedDebtorCount,
                enabledCount: _enabledInSelection,
                disabledCount: _disabledInSelection,
                onlineCount: _onlineInSelection,
                onRenew: _openBulkActivate,
                onPayDebt: _selectedDebtorCount > 0 ? _openBulkPayDebt : null,
                onDisconnect:
                    _onlineInSelection > 0 ? _openBulkDisconnect : null,
                onDisable: () => _bulk(_BulkAction.disable),
                onEnable: () => _bulk(_BulkAction.enable),
                onDelete: () => _bulk(_BulkAction.delete),
              ),
            )
          : null,
    );
  }

  /// الحاسبة: تفاصيل المشترك في لوحةٍ بجانب القائمة بدل صفحةٍ تغطّيها — القائمة تبقى بعرضٍ مريح
  /// (لا تتمدّد بطاقاتها) والتنقّل بين المشتركين نقرةٌ واحدة.
  bool get _paneMode => AppPlatform.isDesktop && MediaQuery.sizeOf(context).width >= 1000;
  final GlobalKey<NavigatorState> _paneNav = GlobalKey<NavigatorState>();
  static const double _paneWidth = 440;

  Widget _withDetailPane(Widget list) {
    if (!_paneMode) return list;
    final mq = MediaQuery.of(context);
    return Row(
      children: [
        Expanded(child: list),
        Container(
          width: _paneWidth,
          decoration: BoxDecoration(
            color: AppColors.bg,
            border: BorderDirectional(start: BorderSide(color: AppColors.border)),
          ),
          child: ClipRect(
            // شاشة التفاصيل تقيس MediaQuery: عرض اللوحة لا النافذة.
            child: MediaQuery(
              data: mq.copyWith(size: Size(_paneWidth, mq.size.height)),
              child: Navigator(
                key: _paneNav,
                onGenerateRoute: (_) =>
                    MaterialPageRoute(builder: (_) => const _DetailPanePlaceholder()),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// صفّ المشترك المفتوح في اللوحة (يُبرز في الجدول).
  String? _paneKey;
  static String _rowKey(Subscriber s) => '${s.companyKey ?? ''}|${s.idx ?? s.username}';

  /// أعمدة الجدول بعرض منطقة القائمة (بلا لوحة التفاصيل).
  SubscriberTableColumns get _tableColumns => SubscriberTableColumns.forWidth(
      MediaQuery.sizeOf(context).width - _paneWidth);

  void _openDetail(Subscriber s) {
    final pane = _paneMode ? _paneNav.currentState : null;
    if (pane != null) {
      setState(() => _paneKey = _rowKey(s));
      // ما يُغلق التفاصيل (رجوع، حذف…) يعود للوحة الفارغة لا يغلق القسم.
      pane.pushAndRemoveUntil(
        PageRouteBuilder<void>(
          pageBuilder: (_, __, ___) => SubscriberDetailScreen(sub: s),
          transitionDuration: const Duration(milliseconds: 160),
          reverseTransitionDuration: const Duration(milliseconds: 120),
          transitionsBuilder: (_, a, __, child) => FadeTransition(opacity: a, child: child),
        ),
        (r) => r.isFirst,
      );
      return;
    }
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
    final hintStyle =
        AppType.subtitle(color: AppColors.textLow).copyWith(fontSize: 14);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ٢٠ أكتوبر: رأس التبويب الموحّد — العنوان وسطر الشركة والعدد يميناً،
        // وأزرار الأعلى المشتركة (المساعد · الجرس · الترس) يساراً بمكانها في
        // كلّ تبويب ([TabHeader]). أزرار القائمة (الرادار · الفرز · التصفية)
        // نزلت سطراً جنب البحث — كشريط البحث المطويّ تحت الشرائح.
        TabHeader(
          title: 'subscribers.title'.tr(),
          // ٢٠٢٦-١٠-١٢: الشركة المفتوحة أوّل سطر العدد — هنا يفعّل
          // المدير ويمدّد، فمالك عدّة شركات يرى أيّها قبل أن يضغط.
          // سطرٌ واحد: إن ضاق يُبتر آخره (المتّصلون، وعددهم في شريحتهم
          // تحته) لا اسم الشركة. وبلا شركة يبقى السطر كما كان حرفيّاً.
          subtitle: ValueListenableBuilder<bool>(
            valueListenable: MergedMode.active,
            builder: (context, merged, child) => merged
                ? Text(
                    MergedMode.focused == null
                        ? '${'merged.header'.tr()} · ${'merged.header_sub'.tr(args: ['${MergedMode.usable.length}'])} • $total مشترك'
                        : '«${MergedMode.focused!.name}» • $total مشترك',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.body(color: AppColors.brand).copyWith(fontSize: 12.5, fontWeight: FontWeight.w600),
                  )
                : child!,
            child: ValueListenableBuilder<ActiveCompanyInfo?>(
            valueListenable: ActiveCompany.listenable,
            builder: (context, company, _) {
              final counts = '$total مشترك • $online متصل الآن';
              if (company == null) {
                return Text(
                  counts,
                  style: AppType.body(color: AppColors.textMid)
                      .copyWith(fontSize: 12.5),
                );
              }
              return ActiveCompanyLine(
                info: company,
                showWho: false,
                trailing: counts,
                fontSize: 12.5,
              );
            },
          ),
          ),
        ),
        const SizedBox(height: Sp.lg),
        Row(
          children: [
            // حقل البحث — 46 ارتفاعاً، r16، حدّ خفيف. المخطّط يرسمه نصّاً
            // ساكناً بلا زرّ مسح؛ أبقينا زرّ المسح لأنّه سلوك قائم.
            Expanded(
              child: Container(
                height: H.search,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(R.lg),
                  border: Border.all(color: AppColors.borderSoft),
                ),
                child: Row(
                  children: [
                    Icon(Icons.search_rounded,
                        size: 20, color: AppColors.textLow),
                    const SizedBox(width: 10),
                    Expanded(
                      // الحقل يتشارك سطره مع الأزرار: أطول تلميحٍ يُقرأ كاملاً
                      // (بالهاتف ← بالاسم واليوزر ← «بحث») بدل بترٍ بـ«…».
                      child: LayoutBuilder(
                        builder: (context, c) => TextField(
                          controller: controller,
                          style: AppType.input(),
                          decoration: InputDecoration(
                            hintText: fittingHint(
                              context,
                              maxWidth: c.maxWidth,
                              style: hintStyle,
                              fieldStyle: AppType.input(),
                              candidates: [
                                'subscribers.search_hint_full'.tr(),
                                'subscribers.search_hint'.tr(),
                                'common.search'.tr(),
                              ],
                            ),
                            hintStyle: hintStyle,
                            border: InputBorder.none,
                            isCollapsed: true,
                          ),
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
            ),
            const SizedBox(width: Sp.sm),
            // الأزرار بمقاس أزرار الأعلى وفراغها: كلّ زرٍّ تحت نظيره فوقه.
            // رادار لا «تحديث»: الزرّ يفحص أجهزة المشتركين
            // (RX/إشارة/CCQ/LAN) ولا يعيد تحميل القائمة — كان يُقرأ
            // كـreload. طلب المستخدم 2026-08-29.
            _HeaderIconButton(
              icon: Icons.radar_rounded,
              active: false,
              busy: probing,
              onTap: onScanDevices ?? () {},
              tooltip: 'subscribers.probe_devices'.tr(),
              size: TopActionChip.sizeOf(context),
            ),
            SizedBox(width: TopActionChip.gapOf(context)),
            _HeaderIconButton(
              icon: Icons.swap_vert_rounded,
              active: sortActive,
              onTap: onSort,
              size: TopActionChip.sizeOf(context),
            ),
            if (onFilter != null) ...[
              SizedBox(width: TopActionChip.gapOf(context)),
              _HeaderIconButton(
                icon: Icons.tune_rounded,
                active: filterActive,
                onTap: onFilter!,
                size: TopActionChip.sizeOf(context),
              ),
            ],
          ],
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
    this.size = H.iconBtn,
  });
  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  /// يستبدل الأيقونة بدوّارة ويقفل النقر — زرّ فحص الأجهزة أثناء الموجة.
  final bool busy;
  final String? tooltip;

  /// الضلع — ‎38 افتراضاً، وفي سطر البحث بمقاس أزرار الأعلى فوقه
  /// ([TopActionChip.sizeOf]) فتصطفّ الأعمدة.
  final double size;

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
              width: size,
              height: size,
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
  const _ManagerFilterSheet({
    required this.current,
    required this.managers,
    this.currentPackage,
    this.packages = const [],
  });
  final String? current;
  final List<String> managers;

  /// فلتر الباقة (٢١ أكتوبر، كالويب) — يرجع مع المدير ({manager, package}).
  final String? currentPackage;
  final List<String> packages;

  @override
  State<_ManagerFilterSheet> createState() => _ManagerFilterSheetState();
}

class _ManagerFilterSheetState extends State<_ManagerFilterSheet> {
  late String? _picked = widget.current;
  late String? _pickedPkg = widget.currentPackage;

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
        onPressed: () => Navigator.pop(context, (manager: _picked ?? '', package: _pickedPkg ?? '')),
        leading: _ResetFilterButton(
          onTap: () => setState(() {
            _picked = null;
            _pickedPkg = null;
          }),
        ),
      ),
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.managers.isNotEmpty) ...[
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
          if (widget.packages.isNotEmpty) ...[
            const SizedBox(height: Sp.lg),
            Text('الباقة', style: AppType.pillLabel()),
            const SizedBox(height: Sp.sm),
            Wrap(
              spacing: Sp.sm,
              runSpacing: Sp.sm,
              children: [
                _chip(label: 'الكل', value: null, pkg: true),
                for (final p in widget.packages) _chip(label: p, value: p, pkg: true),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _chip({required String label, required String? value, bool pkg = false}) {
    final on = (pkg ? _pickedPkg : _picked) == value;
    return InkWell(
      onTap: () => setState(() => pkg ? _pickedPkg = value : _picked = value),
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
    // مطلب 2026-06-12: كل زر في الـbulk bar مربوط بصلاحية.
    //
    // بلاغ ٢٠٢٦-١٠-١٤ (صاحب المشروع): «القوائم تبقى بس تظهر ما عنده
    // صلاحيّة». فالزرّ الذي ينقصه مفتاحه **يبقى مقفلاً** في مكانه (قفلٌ
    // مكان الأيقونة، ونقرته رسالةٌ لا عمليّة) بدل أن يختفي — والبار نفسه
    // يظهر دائماً في وضع التحديد. ويبقى مخفيّاً ما لا يُمنح لهذا الدور
    // أصلاً (`permShown`: الحذف عند موظّف ايرث لنك)، وما تحجبه الحالة
    // (تسديد بلا مدينين، فصل بلا متّصلين).
    const renewKeys = ['subscribers.activate', 'subscribers.extend'];
    final canRenew = Perms.hasAny(renewKeys);
    // ايرث لنك (طريقة التفعيل لكلّ مشترك)، أو حكم الخادم أنّ حساب الساس لا
    // يجدّد دفعةً من الرصيد (كارت فقط، بلا صلاحيّة التفعيل): الزرّ بمكانه
    // مقفلٌ بالسبب، فوق أيّ صلاحيّة ([bulkActivateUnavailableReason]).
    final renewUnavailable = bulkActivateUnavailableReason();
    final canPayDebt = Perms.has('subscribers.pay_debt');
    final canToggle = Perms.has('subscribers.toggle');
    final canDelete = Perms.has('subscribers.delete');
    final showRenew = permShown(renewKeys);
    final showToggle = permShown(const ['subscribers.toggle']);
    // ايرث لنك لا تسمح بحذف المشترك (قرار المالك ١٩ أكتوبر): لا «حذف» جماعيّ
    // لمشتركيها أصلاً ([subscriberDeleteHidden]) — لا مقفلاً ولا بالصلاحيّة.
    final showDelete =
        !subscriberDeleteHidden() && permShown(const ['subscribers.delete']);
    // مطلب المستخدم 2026-07-12: تصميم مضغوط — صفّان بدل 4:
    //   Row1 (primary): Renew | Pay debt | Disconnect (كل ما يظهر يتقاسم العرض)
    //   Row2 (secondary): Disable | Enable | Delete
    // ارتفاع أقل بـ~40% من التصميم القديم؛ زر Renew يبقى أول+مهيمن.
    final showPay =
        debtorCount > 0 && permShown(const ['subscribers.pay_debt']);
    final showDisconnect = onlineCount > 0 && showToggle;
    // لا زرّ يُعرض أصلاً (لا مفتاح يُمنح لهذا الدور) — عمليّاً لا يقع.
    if (!showRenew && !showPay && !showDisconnect && !showToggle &&
        !showDelete) {
      return const SizedBox.shrink();
    }
    final primaryChildren = <Widget>[];
    if (showRenew) {
      primaryChildren.add(Expanded(
        flex: 2,
        child: _PrimaryPill(
          icon: LucideIcons.calendarPlus,
          label: '${'subscribers.bulk_renew'.tr()} ($selectedCount)',
          color: AppColors.brand,
          locked: !canRenew,
          unavailable: renewUnavailable,
          // قفلٌ بحكم الخادم قد يكون أقدم من منح الصلاحيّة في الساس: الضغط
          // يعيد السؤال في الخلفيّة فينفتح الزرّ به (ايرث لنك لا تسأل).
          onUnavailableTap: BulkActivateApi.recheckIfLocked,
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
          locked: !canPayDebt,
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
          locked: !canToggle,
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
            if (primaryChildren.isNotEmpty && (showToggle || showDelete))
              const SizedBox(height: 6),
            // Secondary row: Disable / Enable / Delete
            if (showToggle || showDelete)
              Row(
                children: [
                  if (showToggle) ...[
                    Expanded(
                      child: _SecondaryBtn(
                        icon: LucideIcons.ban,
                        label: enabledCount > 0
                            ? '${'subscribers.disable'.tr()} ($enabledCount)'
                            : 'subscribers.disable'.tr(),
                        color: AppColors.warning,
                        enabled: enabledCount > 0,
                        locked: !canToggle,
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
                        locked: !canToggle,
                        onTap: onEnable,
                      ),
                    ),
                    if (showDelete) const SizedBox(width: 6),
                  ],
                  if (showDelete)
                    Expanded(
                      child: _SecondaryBtn(
                        icon: LucideIcons.trash2,
                        label: 'subscribers.bulk_delete'.tr(),
                        color: AppColors.error,
                        locked: !canDelete,
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
    this.locked = false,
    this.unavailable,
    this.onUnavailableTap,
  });
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  /// لا صلاحيّة: يبقى بمقاسه ومكانه، بلا تعبئة (سطحٌ غاطس ونصٌّ خافت)
  /// وقفلٌ مكان الأيقونة، ونقرته رسالة القفل — [onTap] لا يُستدعى.
  final bool locked;

  /// عمليّةٌ لا يدعمها المزوّد (لا صلاحيّةٌ ناقصة): الشكل المقفل نفسه،
  /// ونقرته هذا السبب مكان «اطلبها من مديرك». يتقدّم على [locked].
  final String? unavailable;

  /// يُستدعى بعد عرض سبب [unavailable] — لإعادة سؤال حكمٍ قد يكون قديماً.
  final VoidCallback? onUnavailableTap;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final locked = this.locked || unavailable != null;
    final pill = SizedBox(
      height: 36,
      child: FilledButton.icon(
        style: FilledButton.styleFrom(
          backgroundColor: locked ? AppColors.surfaceSunken : color,
          foregroundColor: locked ? LockedStyle.glyph : null,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          minimumSize: const Size(0, 36),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(R.sm),
          ),
        ),
        onPressed: locked
            ? () {
                showNoPermission(context, action: true, message: unavailable);
                if (unavailable != null) onUnavailableTap?.call();
              }
            : onTap,
        icon: Icon(locked ? LucideIcons.lock : icon, size: 14),
        label: Text(
          label,
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
          style: const TextStyle(
              fontWeight: FontWeight.w700, fontSize: 12.5, height: 1.4),
        ),
      ),
    );
    if (!locked) return pill;
    return Semantics(
      button: true,
      label: unavailable == null
          ? 'locked.a11y'.tr(args: [label])
          : '$label — $unavailable',
      excludeSemantics: true,
      child: pill,
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
    this.locked = false,
  });
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  /// لا صلاحيّة — يغلب [enabled]: الزرّ يبقى قابلاً للنقر لكنّ نقرته
  /// رسالة القفل لا العمليّة، بسطحٍ غاطس وحدٍّ محايد وقفلٍ مكان الأيقونة.
  /// (حذف مشترك ايرث لنك لا يُعرض أصلاً — `subscriberDeleteHidden`.)
  final bool locked;

  /// When false the button greys out — used by the bulk bar to signal
  /// that no rows in the current selection are eligible for this
  /// action (e.g. all rows already disabled → 'تعطيل' has nothing
  /// to do).
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    if (locked) {
      return Semantics(
        button: true,
        label: 'locked.a11y'.tr(args: [label]),
        excludeSemantics: true,
        child: OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: LockedStyle.glyph,
            backgroundColor: AppColors.surfaceSunken,
            side: BorderSide(color: AppColors.border),
            padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 4),
            minimumSize: const Size(0, 34),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(R.sm),
            ),
          ),
          onPressed: () => showNoPermission(context, action: true),
          icon: const Icon(LucideIcons.lock, size: 13),
          label: Text(label,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontWeight: FontWeight.w700, fontSize: 11.5, height: 1.35)),
        ),
      );
    }
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
    // 🐛 ⚠️ لا `ListView` هنا — ولا أيّ شيء قابل للتمرير. أبداً.
    //
    // بلاغ 2026-08-31 (شاشة بيضاء + فيض لا ينقطع): كان هذا `ListView`،
    // وهو موضوع داخل `SliverFillRemaining(hasScrollBody: false)`. وتلك
    // تسأل طفلها عن ارتفاعه الذاتيّ — و`RenderViewport` لا يملك ارتفاعاً
    // ذاتيّاً بحكم تعريفه (حسابه يوجب إنشاء كلّ الأبناء، وهو نقيض
    // الكسل الذي وُجد له). فيرمي:
    //   «RenderViewport does not support returning intrinsic dimensions»
    //
    // ثمّ يتسلسل: `geometry` تبقى null → `layoutChildSequence` يرمي على
    // `child.geometry!` → `visitChildrenForSemantics` يرمي على
    // `sliver.geometry!` في كلّ إطار. فالثلاثة التي رآها المستخدم
    // (parentDataDirty · Null check · deactivated ancestor) عرَضٌ واحد
    // لهذا السطر.
    //
    // ويقع حصراً حين **يفرغ** الفلتر — ولهذا ظهر في قسم «غير مفعّل».
    //
    // والسحب للتحديث لم يضع: `CustomScrollView` أعلاه صارت
    // `AlwaysScrollableScrollPhysics`، فالإيماءة تعمل من الخارج وهو
    // موضعها الصحيح أصلاً.
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.inbox, size: 40, color: AppColors.textLow),
          const SizedBox(height: Sp.sm),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Sp.xl),
            child: Text(
              msg,
              textAlign: TextAlign.center,
              style: AppType.label(color: AppColors.textMid)
                  .copyWith(fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
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
  const _DebtSummaryCard({required this.subscribers, this.total, this.count});
  final List<Subscriber> subscribers;

  /// الحساب الكبير: المجموع والعدد من الخادم (كلّ المدينين) بدل الصفوف المحمَّلة.
  final double? total;
  final int? count;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final given = this.total;
    if (subscribers.isEmpty && given == null) return const SizedBox.shrink();
    var total = given ?? 0.0;
    if (given == null) {
      for (final s in subscribers) {
        total += s.debtAbs;
      }
    }
    final count = this.count ?? subscribers.length;
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

/// شريط «نسخة محفوظة» — يُعرض فقط حين تكون القائمة من القرص.
///
/// ⚠️ يقول **عمرها** لا مجرّد «بلا اتصال»: الفرق بين نسخةٍ عمرها
/// خمس دقائق ونسخةٍ عمرها يومان هو الفرق بين رقمٍ يُعتمد عليه ورقمٍ
/// يُضلّل. و«بلا اتصال» وحدها لا تقول أيّهما.
class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner({required this.at});
  final DateTime at;

  String get _age {
    final d = DateTime.now().difference(at);
    if (d.inMinutes < 1) return 'الآن';
    if (d.inMinutes < 60) return 'قبل ${d.inMinutes} دقيقة';
    if (d.inHours < 24) return 'قبل ${d.inHours} ساعة';
    return 'قبل ${d.inDays} يوم';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: Sp.lg, vertical: Sp.sm),
      color: AppTone.warning.softBg,
      child: Row(
        children: [
          Icon(LucideIcons.history, size: 14, color: AppTone.warning.fill),
          const SizedBox(width: Sp.sm),
          Expanded(
            child: Text(
              'نسخة محفوظة · آخر تحديث $_age — الأرقام قد تكون تغيّرت',
              style: AppType.muted(color: AppTone.warning.onSoft),
            ),
          ),
        ],
      ),
    );
  }
}

/// تبويب «المشتركون» لمن لا يملك `subscribers.view`: العنوان في مكانه
/// وتحته إطارٌ مقفل — لا بحث ولا شرائح ولا دوّارة لقائمةٍ لن تصل.
class _SubscribersLocked extends StatelessWidget {
  const _SubscribersLocked();

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        bottom: false,
        child: Padding(
          padding:
              EdgeInsets.fromLTRB(Sp.lg, Sp.sm, Sp.lg, Inset.tabBar(context)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // أزرار الأعلى بمكانها ولو قُفلت القائمة — الإعدادات والإشعارات
              // ليست من صلاحيّة المشتركين.
              TabHeader(title: 'nav.subscribers'.tr()),
              const SizedBox(height: Sp.lg),
              LockedCard(
                title: 'nav.subscribers'.tr(),
                icon: LucideIcons.users,
                block: true,
                radius: R.card,
                padding: const EdgeInsets.all(Sp.xl),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// سطرٌ في رأس القائمة للحساب الكبير: «مديون» غير متاح، أو خطأ صفحةٍ بزرّ إعادة.
class _BigNotice extends StatelessWidget {
  const _BigNotice({required this.text, this.onRetry});
  final String text;
  final Future<void> Function()? onRetry;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Container(
      margin: const EdgeInsets.fromLTRB(Sp.lg, Sp.sm, Sp.lg, Sp.sm),
      padding: const EdgeInsets.all(Sp.md),
      decoration: BoxDecoration(
        color: AppColors.warningSoftBg,
        borderRadius: BorderRadius.circular(R.md),
      ),
      // النصّ يلتفّ — والزرّ في سطرٍ مستقلّ تحته فلا يزاحمه (حارس flex_text_guard).
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline_rounded, size: 18, color: AppColors.warning),
              const SizedBox(width: Sp.sm),
              Expanded(
                child: Text(text,
                    style: AppType.body(color: AppColors.textBody).copyWith(height: 1.5)),
              ),
            ],
          ),
          if (onRetry != null)
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton(
                onPressed: () => onRetry!(),
                child: Text('common.retry'.tr(), style: AppType.button(color: AppColors.brand)),
              ),
            ),
        ],
      ),
    );
  }
}

/// لوحة التفاصيل على الحاسبة قبل اختيار مشترك.
class _DetailPanePlaceholder extends StatelessWidget {
  const _DetailPanePlaceholder();

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(Sp.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: AppColors.surfaceSunken,
                  borderRadius: BorderRadius.circular(R.lg),
                ),
                child: Icon(LucideIcons.userSearch, size: 26, color: AppColors.textLow),
              ),
              const SizedBox(height: Sp.md),
              Text(
                'desktop.pick_subscriber'.tr(),
                textAlign: TextAlign.center,
                style: AppType.label(color: AppColors.textMid),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
