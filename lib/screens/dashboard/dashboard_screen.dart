import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/platform/app_platform.dart';
import '../../core/util/ar_date.dart';
import '../../core/util/format.dart';
import '../../models/merged_company.dart';
import '../../services/merged_mode.dart';
import '../../widgets/merged_company_strip.dart';
import '../../api/merged_dashboard_api.dart';
import '../../api/cards_api.dart';
import '../../api/dashboard_api.dart';
import '../../api/view_scope_api.dart';
import '../../services/view_scope_events.dart';
import '../../core/widgets/permission_locked.dart';
import '../../models/dashboard.dart';
import '../../services/active_company.dart';
import '../../services/ai_assistant_state.dart';
import '../../services/alerts_service.dart';
import '../../services/app_resumed_signal.dart';
import '../../services/dashboard_refresh_signal.dart';
import '../../services/auth_storage.dart';
import '../../services/dashboard_cache.dart';
import '../../services/linked_companies.dart';
import '../../services/permissions_service.dart';
import '../../services/provider_service.dart';
import '../../services/subscriber_events.dart';
import '../../widgets/active_company_line.dart';
import '../account/company_switch_sheet.dart';
import '../reports/activity_log_report_screen.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import '../subscribers/widgets/filter_chips_bar.dart';
import '../top_actions.dart';
import 'widgets/desktop_overview.dart';
import 'widgets/desk_renewals_runway.dart';
import 'widgets/desk_status_bars.dart';
import 'widgets/desk_revenue_chart.dart';
import 'widgets/hero_revenue_card.dart';
import 'widgets/packages_summary_card.dart';
import 'widgets/recent_activities.dart';
import '../account/subscription_banner.dart';
import '../whatsapp/whatsapp_status_screen.dart';
import 'widgets/section_header.dart';
import '../desktop/desk_widgets.dart';
import 'widgets/stats_grid.dart';
import 'widgets/subscribers_card.dart';
import '../reports/financial_report_screen.dart';

/// Dashboard with a SLIVER-pinned header — header stays on screen while
/// the body scrolls underneath. All data is LIVE — there are no mock
/// fallbacks anywhere. When data hasn't loaded yet each card shows a
/// loading shimmer; when a fetch fails the card shows an explicit
/// error state, never invented numbers.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key, this.onOpenSubscribers, this.isActive});

  /// Set by MainShell — when any dashboard KPI tile is tapped, calls
  /// this with the matching filter so the shell can switch tabs and
  /// pre-apply the filter on the subscribers screen.
  final ValueChanged<SubscriberFilter?>? onOpenSubscribers;

  /// ترتفع حين يصير هذا هو التبويب المعروض.
  ///
  /// ⚠️ اللوحة مركَّبةٌ في `IndexedStack` طوال الجلسة فلا `initState`
  /// ثانٍ. وكانت تتحدّث على أربعة أحداث ليس منها **دخول التبويب** —
  /// فمن انقطعت شبكته ثمّ عادت وهو داخل التطبيق يفتح اللوحة فلا
  /// يتحدّث شيء: التطبيق لم يذهب للخلفيّة ولم تقع عمليّةٌ على مشترك.
  final ValueNotifier<bool>? isActive;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  String _displayName = '';
  WhatsAppStatusResult? _waLive;
  DailyActivationsResult? _activationsLive;
  DebtorsResult? _debtorsLive;
  /// آخر مرّةٍ وصلت فيها قائمة المشتركين سليمة — «حُدّث منذ…» برأس الحاسبة (ui-ux-pro-max: الأرقام الحيّة تُعلَن
  /// بوقت تحديثها وتُنبَّه حين تقدم). null = لم تصل بعد.
  DateTime? _freshAt;
  WalletResult? _walletLive;

  // «كل الشركات»: ما لم يدخل مجاميع الرئيسية ولماذا (القائمة، الرصيد، تفعيلات اليوم) — لا صفرٌ صامت.
  // المجاميع محفوظةٌ كما وصلت، والمعروض منها الكلّ أو الشركة المختارة في الشريط (_applyMerged) — بلا طلبٍ عند الاختيار.
  MergedListResult? _mergedList;
  MergedSum<WalletResult>? _mergedWallet;
  MergedSum<DailyActivationsResult>? _mergedDaily;
  List<String> _mergedWalletExcluded = const [];
  List<String> _mergedDailyExcluded = const [];

  bool _waLoaded = false;
  bool _activationsLoaded = false;
  bool _debtorsLoaded = false;
  bool _debtsRetry = false;
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

  /// أقسام الرئيسيّة كما ردّها الخادم (٦ مع «الباقات») — «كلّها مخفيّة» بعددها لا برقمٍ ثابت.
  int _sectionCount = 0;
  bool _sectionsLoaded = false;

  /// ⚠️ قبل وصول التفضيلات نعتبر كلّ شيء ظاهراً — وإلّا ومضت الشاشة
  /// فارغةً ثمّ امتلأت. والخطأ في هذا الاتّجاه أرحم: قسمٌ يظهر لحظةً
  /// أهون من شاشة تبدو معطوبة عند كلّ فتح.
  bool _shown(String key) => !_sectionsLoaded || !_hiddenSections.contains(key);

  // ── موظّف ايرث لنك: الأقسام تتبع صلاحيّاته ─────────────────────────
  //
  // 🐛 بلاغ ٢٠٢٦-١٠-١٢ (موظّف «تفعيل وتحصيل»): «الإيرادات — تعذّر الجلب»
  // و«آخر النشاطات (تعذّر الجلب)»، ورصيد الوكيل ظاهر. اللوحة كانت تطلب
  // مساراتٍ تردّها بوّابة الموظّفين 403 لمن لا يملك مفتاحها:
  //   الإيرادات `reports/finance` ← reports.financial
  //   الرصيد `admin-widgets` ← يُقنَّع (`balance:null`) بلا reports.financial
  //   آخر النشاطات `daily-activations` ← reports.daily_activations
  //   «عرض الكل» (سجلّ النشاط) ← reports.activity_log
  //   المشتركون والمدينون `v2/subscribers` ← subscribers.view
  //   حبّة الواتساب `connection-status` ← أيّ مفتاح whatsapp.*
  //
  // القاعدة: قسمٌ لا يملك الفاعل مفتاح بياناته **لا يُطلب** ويبقى مكانه
  // مقفلاً (بلاغ ٢٠٢٦-١٠-١٤) — لا حالة «تعذّر» توهم بعطل، ولا نداءٌ يعرف
  // الخادم أنّه سيرفضه.
  //
  // ولكلّ فاعلٍ مقيَّد لا لموظّف ايرث لنك وحده: موظّف الساس والمدير الفرعيّ
  // المقيَّد يرون «التقارير الماليّة» مقفلةً في «قوائم أخرى» والتقارير، فلا
  // تطلبها الرئيسيّة لتكتب «تعذّر الجلب» ورصيداً صفراً. والمالك كما كان
  // حرفيّاً: `Perms.has` صحيحةٌ له دائماً (وقبل تحميل `/me`).
  bool get _elEmployee => ProviderService.isEarthlink && Perms.isEmployee;
  bool _allows(String key) => Perms.has(key);

  bool get _canSubs => _allows('subscribers.view');
  bool get _canMoney => _allows('reports.financial');
  bool get _canActivity => _allows('reports.daily_activations');
  bool get _canActivityLog => _allows('reports.activity_log');
  bool get _canWa => !_elEmployee || Perms.hasAny(_waKeys);

  /// مفاتيح `connection-status` في الخادم (`requireWhatsAppAdminContext`).
  static const _waKeys = [
    'whatsapp.connect',
    'whatsapp.send',
    'whatsapp.broadcast',
    'whatsapp.templates',
    'whatsapp.schedules',
  ];

  /// بصمة ما يُسمح به الآن.
  ///
  /// `/me` يُعاد جلبه بعد كلّ إقلاع فيُطلق `PermissionsService.changes` ولو
  /// بقي كلّ شيء كما هو — فلا إعادة بناءٍ ولا جلب إلّا إن تبدّلت البصمة.
  String _access = '';
  String _accessSig() =>
      '$_elEmployee$_canSubs$_canMoney$_canActivity$_canActivityLog$_canWa';

  void _onAccessChanged() {
    if (!mounted) return;
    final sig = _accessSig();
    if (sig == _access) return;
    _access = sig;
    setState(() {});
    // ما صار مسموحاً يُجلب الآن؛ وما صار ممنوعاً لم يعد يُرسم.
    //
    // ⚠️ ومعفى من التبريد كالسحب-للتحديث: قسمٌ مُنح للتوّ ظاهرٌ بلا بيانات،
    // فلو أسقط التبريدُ جلبَه (تحديثٌ صامت سبق `/me` بأقلّ من ٣ ثوانٍ) بقي
    // دوّارةً حتّى حدثٍ لاحق لا يأتي.
    _cooling = false;
    _scheduleSilentRefresh();
  }

  /// سطر الشركة في الترويسة يتبع الجلسة حيّاً (حسم الاسم من «شركاتي»،
  /// تبديل المدير الفرعيّ) — ومعه ارتفاع الترويسة.
  void _onCompanyChanged() {
    if (mounted) setState(() {});
  }

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
      _sectionCount = r.sections.length;
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
    _access = _accessSig();
    PermissionsService.changes.addListener(_onAccessChanged);
    ProviderService.changes.addListener(_onAccessChanged);
    ActiveCompany.listenable.addListener(_onCompanyChanged);
    MergedMode.active.addListener(_onMergedChanged);
    MergedMode.focus.addListener(_onMergedFocus);
    _loadIdentity();
    // «تبديل الشركة» في الترويسة: شركات الحساب مرّةً للجلسة (مالكٌ وحده).
    unawaited(LinkedCompanies.ensureFresh());
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
    widget.isActive?.addListener(_onActiveChanged);
  }

  /// دخول التبويب ⇒ تحديثٌ صامت لكلّ شيء.
  ///
  /// ⚠️ صامتٌ لا ظاهر: المدير يتنقّل بين التبويبات كثيراً، ودوّارةٌ
  /// كاملة مع كلّ دخولٍ ضجيجٌ لا خبر. والأرقام القديمة تبقى معروضةً
  /// حتّى تصل الجديدة.
  void _onActiveChanged() {
    if (!mounted) return;
    if (widget.isActive?.value != true) return;
    _scheduleSilentRefresh();
    // والودجات التي تجلب بنفسها — كارت الإيرادات — لا تسمع
    // `_scheduleSilentRefresh` لأنّها تملك حالتها.
    DashboardRefreshSignal.bump();
  }

  void _onDataChanged() {
    if (!mounted) return;
    _scheduleSilentRefresh();
  }

  void _onAppResumed() {
    if (!mounted) return;
    _scheduleSilentRefresh();
    // شركةٌ رُبطت/أُزيلت من الويب — بعد ١٠ دقائق من آخر سؤال.
    unawaited(LinkedCompanies.ensureFresh());
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
    widget.isActive?.removeListener(_onActiveChanged);
    ViewScopeEvents.changed.removeListener(_onScopeChanged);
    PermissionsService.changes.removeListener(_onAccessChanged);
    ProviderService.changes.removeListener(_onAccessChanged);
    ActiveCompany.listenable.removeListener(_onCompanyChanged);
    MergedMode.active.removeListener(_onMergedChanged);
    MergedMode.focus.removeListener(_onMergedFocus);
    super.dispose();
  }

  /// دخول «كل الشركات» أو الخروج منه: الأرقام من جديد (لا يبقى رقم الوضع السابق تحت عنوان الجديد).
  void _onMergedChanged() {
    if (!mounted) return;
    setState(() {
      _debtorsLive = null;
      _walletLive = null;
      _activationsLive = null;
      _mergedList = null;
      _mergedWallet = null;
      _mergedDaily = null;
      _mergedWalletExcluded = const [];
      _mergedDailyExcluded = const [];
    });
    _refreshLive();
  }

  /// شركةٌ اختيرت في الشريط (أو «الكل»): الأرقام من المحفوظ — بلا طلب.
  void _onMergedFocus() {
    if (!mounted || !MergedMode.active.value) return;
    setState(_applyMerged);
  }

  /// المعروض من المجاميع المحفوظة: الكلّ، أو الشركة المختارة وحدها (قائمتها كما وصلت، ورصيدها وتفعيلاتها من المجموع).
  void _applyMerged() {
    final f = MergedMode.focused;
    final r = _mergedList;
    if (r != null) {
      // شركةٌ مختارة بلا قائمة (كبيرة، أو تعذّرت): لا أصفار — البطاقة بلا رقم والسبب في سطر الشريط
      final noList = f != null && r.partOf(f.key)?.rows == null;
      _debtorsLive = noList ? null : MergedDashboardApi.debtorsFrom(r.rowsFor(f?.key));
      _debtorsLoaded = true;
    }
    final w = _mergedWallet;
    if (w != null) {
      final v = f == null ? w : w.only(f);
      _walletLive = v.value;
      _mergedWalletExcluded = v.excluded;
      _walletLoaded = true;
    }
    final d = _mergedDaily;
    if (d != null) {
      final v = f == null ? d : d.only(f);
      _activationsLive = v.value;
      _mergedDailyExcluded = v.excluded;
      _activationsLoaded = true;
    }
  }

  /// «كل الشركات»: المشتركون والديون من الصفوف المدموجة، والرصيد وتفعيلات اليوم مجموعةً بالدينار — ولا شيء يُحفظ في
  /// مخبأ الإقلاع (هو للشركة المفتوحة). [fresh]: سحبٌ يدويّ يتخطّى مخبأ قوائم الشركات (٤٥ث).
  Future<void> _refreshMerged({required bool silent, bool fresh = false}) async {
    if (!silent) {
      setState(() {
        _activationsLoaded = false;
        _debtorsLoaded = false;
        _walletLoaded = false;
      });
    }
    final jobs = <Future<void>>[];
    if (_canSubs) {
      jobs.add(MergedSubscribers.load(fresh: fresh).then((r) {
        if (!mounted || !MergedMode.active.value) return;
        setState(() {
          _mergedList = r;
          _applyMerged();
          _freshAt = DateTime.now();
        });
      }));
    }
    if (_shown('activities') && _canActivity) {
      jobs.add(MergedDashboardApi.daily().then((m) {
        if (!mounted || !MergedMode.active.value) return;
        setState(() {
          _mergedDaily = m;
          _applyMerged();
        });
      }));
    }
    if (_shown('wallet') && _canMoney) {
      jobs.add(MergedDashboardApi.wallet().then((m) {
        if (!mounted || !MergedMode.active.value) return;
        setState(() {
          _mergedWallet = m;
          _applyMerged();
        });
      }));
    }
    await Future.wait(jobs.map((j) => j.catchError((_) {})));
  }

  /// سطر «كل الشركات» تحت الشريط: من لم يدخل الأرقام ولماذا — للكلّ، أو للشركة المختارة وحدها.
  String? _mergedNote() {
    final r = _mergedList;
    final f = MergedMode.focused;
    final parts = <String>[
      if (r != null && f == null) ...[
        for (final b in r.big) 'merged.big'.tr(args: [b.company.name, formatIQD(b.bigTotal!)]),
        for (final x in r.failed) x.error ?? 'merged.failed'.tr(args: [x.company.name]),
        for (final p in r.partial) 'merged.partial'.tr(args: [p.company.name]),
        if (r.missing.isNotEmpty) 'merged.missing'.tr(args: [r.missing.map((c) => c.name).join('، ')]),
        if (r.folded > 0) 'merged.folded'.tr(args: [formatIQD(r.folded)]),
      ],
      if (r != null && f != null) ..._focusListNote(r, f),
      ..._mergedWalletExcluded,
      ..._mergedDailyExcluded,
    ];
    return parts.isEmpty ? null : parts.join('\n');
  }

  /// ما يخصّ قائمة الشركة المختارة: كبيرة، أو تعذّرت، أو ناقصة.
  List<String> _focusListNote(MergedListResult r, MergedCompany f) {
    final p = r.partOf(f.key);
    if (p == null) return const [];
    if (p.bigTotal != null) return ['merged.big'.tr(args: [f.name, formatIQD(p.bigTotal!)])];
    if (p.rows == null) return [p.error ?? 'merged.failed'.tr(args: [f.name])];
    if (p.partial) return ['merged.partial'.tr(args: [f.name])];
    return const [];
  }

  /// حال شركةٍ صالحة على الشريط لا تُختار: كبيرة (تُفتح وحدها) أو تعذّرت قائمتها.
  String? _mergedProblem(MergedCompany c) {
    final p = _mergedList?.partOf(c.key);
    if (p == null) return null;
    if (p.bigTotal != null) return 'merged.chip_big'.tr();
    if (p.rows == null) return 'merged.chip_failed'.tr();
    return null;
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
    // موظّف ايرث لنك بلا reports.financial: لا رصيد يُرسم من القرص، ولا يبقى
    // عليه رقمٌ حفظته نسخةٌ أقدم (قبل أن يقنّعه الخادم) — الكاش لا يحمل
    // سوى المحفظة.
    if (!_canMoney) {
      unawaited(DashboardCache.clear().catchError((_) {}));
      return;
    }
    try {
      // كاش SAS4 لم يعد يُقرأ: الأرقام كلّها تُشتقّ من قائمة المشتركين
      // منذ حذف النداء المباشر (2026-08-31).
      final cachedWallet = await DashboardCache.readWallet();
      if (!mounted) return;
      // §١٢: آخر عدد كارتاتٍ معروف مع الرصيد — للوحة و«قوائم أخرى» معاً.
      // ولا يغلب ردّاً حيّاً سبقه.
      CardsState.seed(cachedWallet?.cards);
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
  /// والسحب-للتحديث معفى — المستخدم طلبه صراحةً وينتظر مؤشّره. وتبدّل
  /// الصلاحيّات معفى كذلك (`_onAccessChanged`).
  bool _cooling = false;

  /// طلبُ تحديثٍ صامتٍ وصل **أثناء** التبريد. لا يُسقَط بل يُؤجَّل فيُنفَّذ
  /// مرّةً واحدةً حين ينتهي التبريد.
  ///
  /// ⚠️ بلا هذا كان التبريد يبتلع آخر تحديثٍ في سلسلةٍ من العمليّات: تفعيلٌ
  /// تِلو تفعيلٍ بينهما ٠٫٧–٣ث (أو عمليّةٌ تِلو العودة من الخلفيّة)، أوّلها
  /// يُحدّث ويُشعل التبريد، والأخيرة يسقط تحديثها — فتبقى الأرقام قديمةً
  /// حتّى حدثٍ لاحقٍ قد لا يأتي. والمطلب أن تنعكس **كلّ** عمليّةٍ حسّاسة.
  /// وتُجمَع كلّ الطلبات التي تصل أثناء التبريد في تحديثٍ واحدٍ لاحق — فلا
  /// تعود موجات النداءات المتطابقة التي وُجد التبريد لأجلها.
  bool _refreshQueued = false;

  /// حبّة الواتساب في الترويسة ← شاشته (إعادة الاتصال/QR) ثمّ تحديث الحالة.
  Future<void> _openWhatsApp() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const WhatsAppStatusScreen()),
    );
    if (mounted) await _refreshLive();
  }

  Future<void> _refreshLive({bool silent = false, bool fresh = false}) async {
    if (silent) {
      // أثناء التبريد لا نُسقط الطلب بل نُعلّمه مؤجَّلاً: عمليّةٌ حسّاسةٌ
      // وقعت فعلاً ويجب أن تنعكس ولو جاءت بعد تحديثٍ سابقٍ بلحظات.
      if (_cooling) {
        _refreshQueued = true;
        return;
      }
      _cooling = true;
      _refreshQueued = false;
      Future.delayed(const Duration(seconds: 3), () {
        _cooling = false;
        // تأجّل تحديثٌ أثناء التبريد؟ نفّذه الآن — مرّةً واحدةً مهما
        // تراكم، فيُعيد ضبط التبريد ويبقى النظام متّسقاً بلا تكرار.
        if (_refreshQueued && mounted) {
          _refreshQueued = false;
          _refreshLive(silent: true);
        }
      });
    }
    // silent=false (initial mount + pull-to-refresh): نُسقط الـloaded
    //   flags فتظهر spinners حتى البيانات الجديدة.
    // silent=true (event-driven refresh): نبقي القيم القديمة معروضة
    //   حتى الـAPI يرد بالـlatest، يجنّب وميض 0 → القيمة الجديدة.
    if (MergedMode.active.value) {
      await _refreshMerged(silent: silent, fresh: fresh);
      return;
    }
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
    //
    // ⚠️ و`_can…` بجانب `_shown` على كلّ نداء: موظّف ايرث لنك لا يُطلب له
    // ما سيردّه الخادم 403 (انظر `_elEmployee`).
    if (_shown('wa_banner') && _canWa) {
      DashboardApi.fetchWhatsAppStatus()
          .timeout(kMaxLoad, onTimeout: () => null)
          .catchError((_) => null)
          .then((r) {
        if (!mounted || MergedMode.active.value) return;
        if (silent && r == null && _waLive != null) return;
        setState(() {
          _waLive = r;
          _waLoaded = true;
        });
      });
    }
    if (_shown('activities') && _canActivity) {
      DashboardApi.fetchDailyActivations()
          .timeout(kMaxLoad, onTimeout: () => null)
          .catchError((_) => null)
          .then((r) {
        // ردٌّ للشركة المفتوحة وصل بعد دخول «كل الشركات»: لا يكتب فوق المجموع («يظهر مال شركه وحده»)
        if (!mounted || MergedMode.active.value) return;
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
      if (!mounted || !_canSubs) return;
      DashboardApi.fetchDebtors()
          .timeout(kMaxLoad, onTimeout: () => null)
          .catchError((_) => null)
          .then((r) {
        if (!mounted || MergedMode.active.value) return;
        if (silent && r == null && _debtorsLive != null) return;
        setState(() {
          _debtorsLive = r;
          _debtorsLoaded = true;
          if (r != null) _freshAt = DateTime.now();
        });
        // نُحدّث عدّاد الجرس (near-expiry + expired-today) من نفس القائمة
        // اللي fetchDebtors شغّلها تواً — بدون طلب شبكة إضافي.
        AlertsService.refresh();
        // الحساب الكبير: عدّ المدينين أوّل مرّة يأخذ دقيقةً أو اثنتين في الخادم — نسأل مرّةً بعد ٢٠ثانية لا عند التحديث التالي.
        if (r != null && r.debtsPending && !_debtsRetry) {
          _debtsRetry = true;
          Future.delayed(const Duration(seconds: 20), () {
            _debtsRetry = false;
            if (mounted) _refreshLive(silent: true);
          });
        }
      });
    });
    // ⚠️ التبويب على النداء لا على العرض: الغاية إسقاط الطلب لا
    // إخفاء نتيجته. القسم المخفيّ يجب ألّا يكلّف شبكةً أصلاً.
    if (_shown('wallet') && _canMoney) {
      DashboardApi.fetchWallet()
          .timeout(kMaxLoad, onTimeout: () => null)
          .catchError((_) => null)
          .then((r) {
        if (!mounted || MergedMode.active.value) return;
        // صلاحيّةٌ سُحبت والطلب في الطريق (تحديث `/me`): الخادم قنّع الرصيد
        // (`balance:null` يصل صفراً) — فلا يُرسم رقمٌ كاذب ولا يُحفظ.
        if (!_canMoney) return;
        if (silent && r == null && _walletLive != null) return;
        setState(() {
          _walletLive = r;
          _walletLoaded = true;
        });
        if (r != null) {
          DashboardCache.saveWallet(r); // persist for next cold start
        }
      });
    } else if (!Perms.isEmployee ||
        Perms.hasAny(const ['subscribers.activate', 'subscribers.extend'])) {
      // §١٢: شارة الكارتات تركب admin-widgets، وهو لا يُطلب والمحفظة مخفيّة —
      // فتغيب «الكارتات» عن «قوائم أخرى» لمن يعمل بها. نداءٌ واحد للملخّص حين
      // تُجهل الشارة وحدها؛ والمعروفة لا تكلّف شيئاً.
      //
      // ولكلّ المزوّدين: مخزون كروت ايرث لنك صار يُخدَم (prepaycard/all —
      // المجموعة ② ١٨ أكتوبر) بالمفاتيح نفسها، فموظّفها بلا reports.financial
      // كموظّف الساس: رصيده مقفل وكارتاته لا. والموظّف بلا تفعيلٍ ولا تمديد لا
      // نداء له: الخادمان يردّانه 403 (`requireAnyPermission` بالساس،
      // `_EMP_ROUTE_PERMS` بايرث لنك) — نداءٌ نعرف أنّه سيُرفض.
      CardsState.ensureKnown();
    }
  }

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 5) return 'dashboard.welcome_evening'.tr();
    if (h < 12) return 'dashboard.welcome_morning'.tr();
    if (h < 17) return 'dashboard.welcome_evening_light'.tr();
    return 'dashboard.welcome_evening'.tr();
  }

  /// عمود «آخر النشاطات» على الحاسبة: العنوان ثمّ البطاقة تمتدّ لارتفاع جارتها (الإيرادات).
  Widget _deskStretch(Widget activities) {
    if (activities is! Column || activities.children.length < 2) return activities;
    final kids = activities.children;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [kids.first, Expanded(child: kids[1])],
    );
  }

  /// رسم الإيرادات على الحاسبة: بمفتاح المال وظهور القسم، وللشركة المفتوحة وحدها («كل الشركات» لها
  /// بطاقتها المجمَّعة).
  bool get _deskRevenueChart => _canMoney && _shown('revenue') && !MergedMode.active.value;

  /// توزيع المشتركين على الحاسبة — حين تصل أرقامهم.
  bool get _deskDistribution => _canSubs && _shown('subscribers') && _subscribersStats != null;

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
    // الحاسبة (منطقة محتوى عريضة): المشتركون بجانب الرصيد والإيرادات بدل عمودٍ واحدٍ يتمدّد.
    final wide = AppPlatform.isDesktop && MediaQuery.sizeOf(context).width >= 860;
    final subscribersSection = !_shown('subscribers')
        ? null
        : (_canSubs
                ? SubscribersCard(
                    stats: _subscribersStats,
                    onOpen: widget.onOpenSubscribers,
                  )
                : LockedCard(
                    title: 'nav.subscribers'.tr(),
                    icon: LucideIcons.users,
                    block: true,
                    // ارتفاع البطاقة الحيّة (هيكلها المقيس).
                    height: 285,
                    radius: R.card,
                    padding: const EdgeInsets.all(Sp.xl),
                  ))
            .animate()
            .fadeIn(duration: const Duration(milliseconds: 280))
            .slideY(begin: 0.03, end: 0);
    // الرصيد يتبع reports.financial والمدينون subscribers.view — كلٌّ نصفٌ مستقلّ، والمحجوب منهما يبقى
    // مكانه مقفلاً.
    final walletSection = !_shown('wallet')
        ? null
        : StatsGrid(
            wallet: _walletLoaded ? _walletLive : null,
            debtors: _debtorsLoaded ? _debtorsLive : null,
            balanceLocked: !_canMoney,
            debtLocked: !_canSubs,
            onOpenDebtors: () => widget.onOpenSubscribers?.call(SubscriberFilter.debtors),
          )
            .animate()
            .fadeIn(
              delay: const Duration(milliseconds: 80),
              duration: const Duration(milliseconds: 280),
            )
            .slideY(begin: 0.03, end: 0);
    // الكارت يجلب بنفسه (`reports/finance`)، فعدم بنائه يُسقط نداءه. ⚠️ المقفل لا يبني
    // `HeroRevenueCard` أصلاً — `initState` فيه يُطلق النداء.
    final revenueSection = !_shown('revenue')
        ? null
        : (_canMoney ? const HeroRevenueCard() : LockedCard(title: 'dashboard.revenue'.tr()))
            .animate()
            .fadeIn(
              delay: const Duration(milliseconds: 160),
              duration: const Duration(milliseconds: 280),
            )
            .slideY(begin: 0.03, end: 0);
    // «توزيع الباقات» (#٥، طلب المالك ٢٥ أكتوبر): يجلب بنفسه كالإيرادات — ⚠️ المقفل لا يبني `PackagesSummaryCard` أصلاً
    // (initState فيه يُطلق النداء)، والمخفيّ من «نطاق العرض» كذلك. لا تقرير باقاتٍ للوطنيّ.
    final packagesSection = !_shown('packages') || ProviderService.isFtth
        ? null
        : (_canMoney
                ? const PackagesSummaryCard()
                : LockedCard(title: 'pkgdist.card_title'.tr(), icon: LucideIcons.package))
            .animate()
            .fadeIn(
              delay: const Duration(milliseconds: 200),
              duration: const Duration(milliseconds: 280),
            )
            .slideY(begin: 0.03, end: 0);
    final activitiesSection = !_shown('activities')
        ? null
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
                    SectionHeader(
                      // المقفل لا يُجلب فلا «تعذّر» يُكتب في عنوانه أبداً.
                      label: !_canActivity || !_activationsLoaded
                          ? 'dashboard.recent_activity_label'.tr()
                          : _activationsLive == null
                              ? 'dashboard.recent_activity_fetch_failed'.tr()
                              : 'dashboard.recent_activity_label'.tr(),
                      // مطلب المستخدم 2026-07-12: زر "عرض الكل" ينقل
                      // لسجل النشاط الكامل. الـPermissionGate يتأكد من
                      // reports.activity_log؛ لو الموظف بلا صلاحية يرى
                      // شاشة رفض بدل الشاشة الفارغة. وموظّف ايرث لنك بلاها
                      // يرى الزرّ مقفلاً — ما دام المفتاح ممّا يُمنح له.
                      trailingLabel: _canActivity &&
                              (_canActivityLog ||
                                  permShown(const ['reports.activity_log']))
                          ? 'dashboard.view_all'.tr()
                          : null,
                      trailingLocked: !_canActivityLog,
                      onTrailingTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const ActivityLogReportScreen(),
                        ),
                      ),
                    ),
                    if (!_canActivity)
                      const _ActivitiesLocked()
                    else if (!_activationsLoaded)
                      const _ActivitiesLoading()
                    else if (_activationsLive == null)
                      const _ActivitiesError()
                    else if (_activationsLive!.recent.isEmpty)
                      const _NoActivitiesYet()
                    else
                      RecentActivities(
                        items: _activationsLive!.recent,
                        // الحاسبة: حصيلة اليوم مثبّتةٌ أسفل البطاقة الممتدّة (لا فراغ تحت آخر نشاط).
                        footer: wide
                            ? _TodayTally(
                                activations: _activationsLive!.activations,
                                extensions: _activationsLive!.extensions,
                              )
                            : null,
                      )
                          .animate()
                          .fadeIn(
                            delay: const Duration(milliseconds: 240),
                            duration: const Duration(milliseconds: 280),
                          ),
            ],
          );
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: RefreshIndicator(
        color: AppColors.brand,
        onRefresh: () async {
          // ⚠️ الإشارة **أوّلاً** لا بعد الانتظار: كارت الإيرادات يجلب
          //    بنفسه، فإطلاقها قبل `await` يجعل الجلبين متوازيين بدل
          //    أن ينتظر أحدهما الآخر — ومؤشّر السحب يختفي حين تنتهي
          //    الدالّة، فلا نُطيله بانتظارٍ متسلسل.
          //
          // وبدونها كان المدير يسحب فتتحدّث بقيّة الكارتات ويبقى كارت
          // الإيرادات على «تعذّر الجلب — اسحب للتحديث» مهما سحب:
          // `onRefresh` ينادي دوالّ اللوحة، ولا سبيل له إلى حالة ودجةٍ
          // ابنة تملك جلبها.
          DashboardRefreshSignal.bump();
          await Future.wait([_loadIdentity(), _refreshLive(fresh: true)]);
        },
        child: CustomScrollView(
          slivers: [
            // الحاسبة: رأس صفحةٍ كالموقع — الاسم والشركة وأزرار الأعلى في شريط الغلاف العلويّ.
            if (wide)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.xl, Sp.lg, Sp.lg),
                  child: DeskPageHeader(
                    title: 'desktop.title_dashboard'.tr(),
                    // التاريخ وحده بالأشهر العراقيّة («السبت 24 تشرين الأوّل 2026») — لا سلسلة «· …» من المعلومات.
                    subtitle: DeskSubtitle(iqLongDate(DateTime.now())),
                    actions: [
                      if (_shown('wa_banner') &&
                          _canWa &&
                          !(Perms.isEmployee && _waLoaded && _waLive == null))
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: Perms.has('whatsapp.connect') ? _openWhatsApp : null,
                          child: _WAStatusChip(status: _waStatus, loaded: _waLoaded),
                        ),
                      if (!_elEmployee) const SubscriptionChip(),
                      if (_freshAt != null) DeskFreshness(at: _freshAt!),
                      DeskIconButton(
                        icon: LucideIcons.refreshCw,
                        tooltip: 'desktop.refresh'.tr(),
                        onTap: () => Future.wait(
                            [_loadIdentity(), _refreshLive(fresh: true)]),
                      ),
                    ],
                  ),
                ),
              )
            else
            SliverPersistentHeader(
              pinned: true,
              delegate: _PinnedHeaderDelegate(
                displayName: _displayName,
                greeting: _greeting(),
                whatsApp: _waStatus,
                waLoaded: _waLoaded,
                // بلا `whatsapp.connect`: رسالة القفل لا شيء — ما دام المفتاح
                // ممّا يُمنح لهذا الدور (موظّف ايرث لنك لا يُمنحه: null كما كان).
                onWhatsAppTap: Perms.has('whatsapp.connect')
                    ? _openWhatsApp
                    : permShown(const ['whatsapp.connect'])
                        ? () => showNoPermission(context)
                        : null,
                // «تنبيه واتساب» في «نطاق العرض» يُخفي الحبّة (ونداءها) لا شريطاً.
                // وموظّف ايرث لنك بلا مفتاح واتساب: الخادم يرفض الفحص، فكانت
                // تقول «غير متصل» كذباً.
                //
                // والموظّف (أيّ مزوّد) حين لا يصل ردّ الفحص: لا «منقطع» قد
                // يكون رفضاً لا انقطاعاً — الحبّة تغيب. والمالك كما كان.
                showWhatsApp: _shown('wa_banner') &&
                    _canWa &&
                    !(Perms.isEmployee && _waLoaded && _waLive == null),
                // تنبيه اشتراك **الحساب** (إيميل المالك): موظّف ايرث لنك يدخل
                // بلا حساب، فلا يملكه ولا يفعّله.
                showSubscription: !_elEmployee,
                // الشركة المفتوحة — سطرٌ تحت الاسم بدل شريطٍ أعلى التطبيق.
                company: ActiveCompany.current,
                // «تبديل الشركة» — يظهر لمالكٍ بشركتين فأكثر ([LinkedCompanies]).
                onSwitchCompany: () => showCompanySwitchSheet(context),
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
                  // «كل الشركات»: الأرقام تحته لشركات الحساب معاً — ومن لم يدخلها ولماذا
                  if (MergedMode.active.value) ...[
                    MergedCompanyStrip(
                      countOf: (c) => _mergedList?.countOf(c.key),
                      total: _mergedList?.total,
                      problemOf: _mergedProblem,
                      note: _mergedNote(),
                      onExit: MergedMode.exit,
                    ),
                    const SizedBox(height: Sp.md),
                  ],
                  // أعلى كلّ شيء عمداً: انقطاع الجلسة يوقف كلّ تنبيهات
                  // المشتركين وفواتيرهم، فلا يجوز أن يُقرأ بعد الأرقام.
                  // ٢٠٢٦-١٠-٠٨ (طلب المستخدم): شريط «إعادة ربط واتساب» أُزيل من
                  // هنا — حالته معروضة أصلاً في الترويسة تحت اسم المدير، فكان
                  // تكراراً يأكل الشاشة. حبّة الترويسة صارت تُضغط فتفتح شاشة
                  // الواتساب (إعادة الاتصال/QR)، وتنبيه الاشتراك حبّةٌ بجانبها.
                  // موظّف ايرث لنك بلا مفتاح القسم: إطار البطاقة نفسه مقفلاً
                  // (بلاغ ٢٠٢٦-١٠-١٤) — لا اختفاء يترك فراغاً، ولا نداء.
                  // ⚠️ التفرّع على `_canSubs` **قبل** حالة التحميل: المقفل لا
                  // يجلب، فلو بُني الحيّ لبقي على هيكله دوّارةً أبداً.
                  if (wide) ...[
                    // الحاسبة: صفّ الأرقام الرئيسيّة + شريط الحالات، ثمّ الإيرادات بجانب آخر النشاطات.
                    if (_shown('subscribers') || _shown('wallet'))
                      DesktopOverview(
                        stats: _canSubs ? _subscribersStats : null,
                        wallet: _walletLoaded ? _walletLive : null,
                        debtors: _debtorsLoaded ? _debtorsLive : null,
                        subsLocked: !_canSubs,
                        balanceLocked: !_canMoney,
                        debtLocked: !_canSubs,
                        showSubscribers: _shown('subscribers'),
                        showWallet: _shown('wallet'),
                        onOpen: widget.onOpenSubscribers,
                      ).animate().fadeIn(duration: const Duration(milliseconds: 280)),
                    const SizedBox(height: Sp.md),
                    // ٢٤ أكتوبر (إعادة تصميم الحاسبة): «التجديدات القادمة» بجانب «توزيع المشتركين» — عمل الوكيل
                    // اليوميّ (من يجدّد، ومن متّصل/منتهٍ) أوّل ما تراه العين بعد الأرقام.
                    if (_deskDistribution) ...[
                      IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              flex: 7,
                              child: DeskRenewalsRunway(
                                days: _debtorsLive?.expiringByDay,
                                nearExpiry: _subscribersStats?.nearExpiry,
                                onOpen: widget.onOpenSubscribers,
                              ),
                            ),
                            const SizedBox(width: Sp.md),
                            Expanded(
                              flex: 5,
                              child: DeskStatusBars(
                                stats: _subscribersStats!,
                                onOpen: widget.onOpenSubscribers,
                              ),
                            ),
                          ],
                        ),
                      ).animate().fadeIn(duration: const Duration(milliseconds: 280)),
                      const SizedBox(height: Sp.md),
                    ],
                    // المال والنشاط: ملخّص الإيرادات (يوم/أسبوع/شهر) فوق رسم ٣٠ يوماً، بجانب «آخر النشاطات» —
                    // البطاقتان تبدآن وتنتهيان على خطٍّ واحد (بلاغ المالك ٢٣ أكتوبر: «منشزة ويّ الإيرادات»).
                    if (revenueSection != null || _deskRevenueChart || activitiesSection != null)
                      IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (revenueSection != null || _deskRevenueChart)
                              Expanded(
                                flex: 7,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    SectionHeader(
                                      label: 'desktop.revenue_header'.tr(),
                                      trailingLabel: _canMoney ? 'desktop.financial_report'.tr() : null,
                                      onTrailingTap: () => Navigator.of(context).push(
                                        MaterialPageRoute(builder: (_) => const FinancialReportScreen()),
                                      ),
                                    ),
                                    if (revenueSection != null) revenueSection,
                                    if (revenueSection != null && _deskRevenueChart) const SizedBox(height: Sp.md),
                                    if (_deskRevenueChart) const Expanded(child: DeskRevenueChart()),
                                  ],
                                ),
                              ),
                            if ((revenueSection != null || _deskRevenueChart) && activitiesSection != null)
                              const SizedBox(width: Sp.md),
                            if (activitiesSection != null)
                              Expanded(flex: 5, child: _deskStretch(activitiesSection)),
                          ],
                        ),
                      ),
                    if (packagesSection != null) ...[const SizedBox(height: Sp.md), packagesSection],
                  ] else ...[
                    // أعلى كلّ شيء عمداً: انقطاع الجلسة يوقف كلّ تنبيهات المشتركين وفواتيرهم، فلا يجوز أن
                    // يُقرأ بعد الأرقام. موظّفٌ بلا مفتاح القسم: إطار البطاقة نفسه مقفلاً — لا اختفاء يترك
                    // فراغاً، ولا نداء.
                    if (subscribersSection != null) subscribersSection,
                    // ⚠️ الفراغ خارج الشرط كما كان: المالك الذي أخفى القسم من «نطاق العرض» يرى المسافات نفسها.
                    const SizedBox(height: Sp.md),
                    if (walletSection != null) walletSection,
                    const SizedBox(height: Sp.md),
                    if (revenueSection != null) revenueSection,
                    if (packagesSection != null) ...[const SizedBox(height: Sp.md), packagesSection],
                  ],
                  if (!wide && activitiesSection != null) activitiesSection,
                  // ⚠️ لو أُخفي كلّ شيء لا تُترك الشاشة بيضاء: المدير
                  // لن يعرف أنّه هو من أخفاها، وسيظنّها معطوبة.
                  // (والموظّف بلا مفاتيح لا يصل هنا: أقسامه مقفلةٌ في أماكنها.)
                  if (_sectionsLoaded && _sectionCount > 0 && _hiddenSections.length >= _sectionCount)
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

/// حصيلة اليوم أسفل «آخر النشاطات» على الحاسبة — مجموعٌ حقيقيّ من الردّ نفسه لا زينة.
class _TodayTally extends StatelessWidget {
  const _TodayTally({required this.activations, required this.extensions});

  final int activations;
  final int extensions;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Sp.lg, vertical: Sp.md),
      child: Row(
        children: [
          Text('desktop.today_tally'.tr(), style: AppType.muted(color: AppColors.textMid).copyWith(fontSize: 13)),
          const Spacer(),
          Text(
            'desktop.today_tally_values'.tr(args: ['$activations', '$extensions']),
            style: AppType.bodyBold(color: AppColors.textHi),
          ),
        ],
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

/// «آخر النشاطات» لمن لا يملك `reports.daily_activations`: إطار
/// [_NoActivitiesYet] نفسه وفيه القفل — العنوان فوقه يكفي اسماً للقسم.
///
/// ⚠️ لا [_ActivitiesError] أبداً: لم يُطلب شيءٌ ليتعذّر.
class _ActivitiesLocked extends StatelessWidget {
  const _ActivitiesLocked();

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Semantics(
      button: true,
      label: 'locked.a11y'.tr(args: ['dashboard.recent_activity_label'.tr()]),
      excludeSemantics: true,
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.lg),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => showNoPermission(context),
          borderRadius: BorderRadius.circular(R.lg),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(
                vertical: Sp.huge, horizontal: Sp.lg),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(R.lg),
              border: Border.all(color: AppColors.border),
            ),
            child: const LockedNotice.block(),
          ),
        ),
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
    this.onWhatsAppTap,
    this.showWhatsApp = true,
    this.showSubscription = true,
    this.company,
    this.onSwitchCompany,
    required this.topInset,
    required this.textScale,
  }) : isDark = AppColors.isDark;

  final String displayName;
  final String greeting;
  final WhatsAppStatus? whatsApp;
  final bool waLoaded;

  /// الضغط على حبّة الواتساب ← شاشته (إعادة الاتصال/QR). null بلا صلاحيّة.
  final VoidCallback? onWhatsAppTap;
  final bool showWhatsApp;

  /// حبّة تنبيه اشتراك الحساب — تغيب عن موظّف ايرث لنك (لا حساب له).
  final bool showSubscription;

  /// الشركة المفتوحة — سطرٌ تحت الاسم، و`null` = لا سطر ولا ارتفاع له.
  final ActiveCompanyInfo? company;

  /// ورقة «تبديل الشركة». يظهر زرّها حين [LinkedCompanies.switcherVisible]:
  /// مربّعٌ بجانب «الصفحات» إن اتّسع الرأس، وإلّا الاسم وسطر الشركة زرّه.
  final VoidCallback? onSwitchCompany;
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
  //
  // ما يكبر (عند السلّم 1): التحيّة 18.1 + الاسم 22.1 + نصّ الحبّة 14.9
  // ≈ 55 (+3 هامش). والثابت: حشوة 8+2 · فراغان 2+6 · حشوة الحبّة 4+4
  // وحدّها 1+1 = 28.
  static const double _baseText = 58;
  static const double _baseChrome = 28;

  // صفّ الحبّات (واتساب · تنبيه الاشتراك) يسقط بارتفاعه حين لا حبّة فيه —
  // وإلّا بقي تحت الاسم فراغٌ بقدر حبّةٍ غائبة (موظّفٌ بلا مفتاح واتساب).
  static const double _chipsText = 15; // 11 × 1.35
  static const double _chipsChrome = 16; // فراغ 6 + حشوة 8 + حدّ 2

  // ٢٠٢٦-١٠-١٢: سطر الشركة تحت الاسم (كان شريطاً ممتدّاً أعلى التطبيق).
  // نصّه 12 × 1.35 = 16.2 يكبر مع الخطّ، والفراغ 2 فوقه لا يكبر.
  static const double _companyText = 17;
  static const double _companyGap = 2;

  bool get _hasChips => showWhatsApp || showSubscription;
  bool get _hasCompany => company != null;

  double get _textHeight =>
      _baseText -
      (_hasChips ? 0 : _chipsText) +
      (_hasCompany ? _companyText : 0);
  double get _fixedChrome =>
      _baseChrome -
      (_hasChips ? 0 : _chipsChrome) +
      (_hasCompany ? _companyGap : 0);
  double get _contentHeight => _textHeight * textScale + _fixedChrome;

  /// 2026-08-30: الترويسة كانت مثبَّتة بلا انكماش (minExtent == maxExtent)
  /// فتحجز 86px + الشقّ العلوي طوال التمرير. الآن تنكمش إلى الاسم
  /// والأيقونات وحدها: التحيّة وشارة واتساب معلومتان تُقرآن مرّة عند
  /// الفتح ولا حاجة لبقائهما معلّقتين فوق كلّ تمريرة.
  // والمطويّ كذلك: منه 10 نقاط حشوة ثابتة.
  //
  // وسطر الشركة **يبقى** في المطويّة: هويّة الجلسة كالاسم، لا خبرٌ يُقرأ
  // مرّة — ومن يمرّر اللوحة يبقى يرى في أيّ شركةٍ هو. الاسم والسطر
  // 22.1 + 16.2 = 38.3 ← 40، فيصير صفّ المطويّة 42 بالضبط عند السلّم 1:
  // ارتفاع أيقونات الترويسة نفسه، فلا تنضغط كما تنضغط في المطويّة بلا شركة.
  static const double _collapsedText = 34;
  static const double _collapsedCompanyText = 40;
  static const double _collapsedChrome = 10;
  double get _collapsedHeight =>
      (_hasCompany ? _collapsedCompanyText : _collapsedText) * textScale +
      _collapsedChrome +
      (_hasCompany ? _companyGap : 0);

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
    // الشفافيّة تسبق الطيّ: تنطفئ التحيّة والحبّة عند منتصفه. لوحةٌ قصيرة
    // (موظّفٌ بقسمين) لا تتمرّر حتّى آخر الطيّ فتقف الترويسة عند 0.9 مثلاً —
    // وبالشفافيّة الخطّيّة كان يبقى رأس حروف التحيّة (نقطة «خ») وحافّة الحبّة
    // شبحين فوق الاسم وتحت سطر الشركة.
    final fade = (1 - 2 * t).clamp(0.0, 1.0);
    return Container(
      color: AppColors.bg,
      padding: EdgeInsets.fromLTRB(Sp.lg, topInset + Sp.sm, Sp.lg, 2),
      // «تبديل الشركة» يتبع شركات الحساب (تصل بعد الفتح) وظهور المساعد (مربّعٌ
      // يأخذ من عرض الاسم): يُعاد بناء الصفّ وحده حين تتغيّر إحداهما.
      child: ListenableBuilder(
        listenable:
            Listenable.merge([LinkedCompanies.items, AiAssistantState.gate]),
        builder: (context, _) => _row(context, t, fade),
      ),
    );
  }

  Widget _row(BuildContext context, double t, double fade) {
    final managers = Perms.has('managers.edit');
    final switcher = onSwitchCompany != null && LinkedCompanies.switcherVisible;
    // ٢١ أكتوبر: مربّع «الشركات» جنب «الصفحات» (طلب المالك) — إن بقي للاسم
    // عرضه. شاشةٌ أضيق (٣٧٥ فما دون بالمساعد) ⇒ الاسم وسطر الشركة هما الزرّ.
    // بلا سطر شركة (لم تُعرف بعد) ⇒ المربّع على كلّ حال، فلا يغيب الزرّ.
    final companySquare = switcher &&
        (company == null ||
            CompanySwitch.fitsSquare(
              width: MediaQuery.sizeOf(context).width,
              textScale: textScale,
              // الشركات + الجرس + الترس، و«الصفحات» والمساعد إن ظهرا.
              squares:
                  3 + (managers ? 1 : 0) + (AiAssistantState.visible ? 1 : 0),
              side: TopActionChip.sizeOf(context),
              gap: TopActionChip.gapOf(context),
            ));
    final lineSwitch = switcher && !companySquare;
    final name = Text(
      displayName.isEmpty ? 'dashboard.hello'.tr() : displayName,
      style: AppType.title(color: AppColors.textHi).copyWith(
        fontSize: 17,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
    return Row(
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
                    opacity: fade,
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
              // الشركة المفتوحة مع الاسم — خارج الطيّ عمداً (انظر
              // `_collapsedCompanyText`). الاسم فوقه إن طابق يوزر المدير
              // لا يُكرَّر فيه. وحين لا مربّع لـ«تبديل الشركة»: الاسم والسطر
              // زرٌّ واحد له، وبعد السطر سهم ⌄ (الارتفاع نفسه).
              if (lineSwitch && company != null)
                CompanySwitchTap(
                  label: company!.label,
                  onTap: onSwitchCompany!,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      name,
                      const SizedBox(height: _companyGap),
                      CompanySwitchLine(
                          info: company!, omitUsername: displayName),
                    ],
                  ),
                )
              else ...[
                name,
                if (company != null) ...[
                  const SizedBox(height: _companyGap),
                  ActiveCompanyLine(info: company!, omitUsername: displayName),
                ],
              ],
              if (_hasChips) ...[
                SizedBox(height: 6 * (1 - t)),
                ClipRect(
                  child: Align(
                    alignment: AlignmentDirectional.topStart,
                    heightFactor: 1 - t,
                    child: Opacity(
                      opacity: fade,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (showWhatsApp) ...[
                            Flexible(
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: onWhatsAppTap,
                                child: _WAStatusChip(
                                    status: whatsApp, loaded: waLoaded),
                              ),
                            ),
                            const SizedBox(width: 6),
                          ],
                          // Pro البند ٤: تنبيه الاشتراك (لا يظهر إلّا قرب الانتهاء).
                          if (showSubscription) const SubscriptionChip(),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        // فاصلٌ عن الأيقونات: سطر الشركة يبلغ حافّة العمود عند تكبير الخطّ،
        // وبلا فاصل يلتصق اليوزر بزرّ «الصفحات».
        const SizedBox(width: Sp.sm),
        // «تبديل الشركة» و«الصفحات» ثمّ المساعد · الجرس · الترس — أزرار الأعلى
        // المشتركة بين التبويبات كلّها ([TopActions]، طلب المالك ٢٢ أكتوبر).
        // الرئيسيّة وحدها تُسقط مربّع الشركة حين لا يتّسع لاسم المدير، فيصير
        // سطر الشركة تحت الاسم هو الزرّ (`lineSwitch`).
        TopActions(switchers: true, companySquare: companySquare),
      ],
    );
  }

  @override
  bool shouldRebuild(_PinnedHeaderDelegate old) =>
      old.displayName != displayName ||
      old.greeting != greeting ||
      old.waLoaded != waLoaded ||
      old.showWhatsApp != showWhatsApp ||
      old.showSubscription != showSubscription ||
      (old.onSwitchCompany == null) != (onSwitchCompany == null) ||
      // السطر **والارتفاع** يتبعان الشركة: ظهورها/اختفاؤها يغيّر الحدّين.
      _companyKey(old.company) != _companyKey(company) ||
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

  /// ما يرسمه سطر الشركة — `ActiveCompanyInfo` بلا مساواة قيميّة.
  static String _companyKey(ActiveCompanyInfo? c) => c == null
      ? ''
      : '${c.label}|${c.username}|${c.parentUsername}|${c.isEmployee}';
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
    final Widget dot = !loaded
        ? SizedBox(
            width: 10,
            height: 10,
            child:
                CircularProgressIndicator(strokeWidth: 1.4, color: tone.fill),
          )
        : Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: tone.fill, shape: BoxShape.circle),
          );
    // أدنى عرضٍ للحبّة: حشوة ‎8+8 وحدّ ‎1+1 والنقطة (أو الدوّارة) وفراغها ‎6.
    final minPill = Sp.sm * 2 + 2 + (loaded ? 7 : 10) + 6;
    return LayoutBuilder(builder: (context, c) {
      // ٢٠ أكتوبر: على شاشةٍ أضيق من ‎360 صار جنب الاسم أربعة مربّعات
      // («الصفحات» + المساعد + الجرس + الترس)، فإن ظهرت حبّة الاشتراك بجانب هذه
      // لم يبقَ لها أدنى عرضها ففاضت فوق جارتها. فتبقى نقطة الحال وحدها
      // بلونها، واسمها لقارئ الشاشة، والنقر يفتح الواتساب كما كان.
      if (c.maxWidth < minPill) return Semantics(label: label, child: dot);
      return _pill(tone, label, dot);
    });
  }

  Widget _pill(AppTone tone, String label, Widget dot) {
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
          dot,
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
            textAlign: TextAlign.center,
            style: AppType.label(color: AppColors.textMid),
          ),
          const SizedBox(height: 4),
          Text(
            'أعِدها من الإعدادات ← نطاق العرض',
            textAlign: TextAlign.center,
            style: AppType.micro(color: AppColors.textLow),
          ),
        ],
      ),
    );
  }
}
