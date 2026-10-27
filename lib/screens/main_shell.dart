import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/api_client.dart'
    show authExpiredSignal, accessBlockedSignal, blockedMessage;
import '../services/merged_mode.dart';
import '../services/active_company.dart';
import '../services/ai_assistant_state.dart';
import '../services/permissions_service.dart';
import '../services/provider_service.dart';
import '../core/widgets/design_sheet.dart';
import '../core/widgets/permission_locked.dart';
import '../theme/colors.dart';
import '../theme/spacing.dart';
import '../theme/typography.dart';
import 'dashboard/dashboard_screen.dart';
import 'account/account_gate_screen.dart';
import 'account/employee_login_screen.dart';
import '../services/employee_session.dart';
import 'more_modules_screen.dart';
import 'network_devices/network_devices_screen.dart';
import 'search/quick_search_overlay.dart';
import 'expenses/sheets/add_expense_sheet.dart';
import 'subscribers/sheets/activate_sheet.dart';
import 'subscribers/sheets/add_debt_sheet.dart';
import 'subscribers/sheets/add_subscriber_sheet.dart';
import 'subscribers/sheets/pay_debt_sheet.dart';
import 'subscribers/sheets/subscriber_picker_sheet.dart';
import 'managers/managers_screen.dart';
import '../services/notification_router.dart';
import 'subscribers/subscribers_screen.dart';
import 'subscribers/widgets/filter_chips_bar.dart';
import 'top_actions.dart';
import '../core/platform/desktop_layout.dart';
import 'desktop/desktop_shell.dart';
import '../core/widgets/app_sheet.dart';

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


/// أبناء `IndexedStack` كسولاً: غير المزار يبقى `SizedBox` فلا يُنشأ
/// له `State` ولا يُنفَّذ `initState`.
///
/// `IndexedStack` يبني **كلّ** أبنائه ويرسم المحدَّد وحده — وهو ما جعل
/// شاشة الأجهزة تفحص شبكةً محلّيّة بعيدة من لحظة الإقلاع لشاشة لم
/// تُفتَح. (بلاغ 2026-08-31)
///
/// المزار يبقى في الشجرة بعدها: التنقّل بين التبويبات لا يُفقد الحالة
/// ولا يُعيد الجلب.
List<Widget> lazyTabChildren(List<Widget> tabs, Set<int> visited, int active) =>
    [
      for (var i = 0; i < tabs.length; i++)
        if (visited.contains(i))
          // ⚠️ `ExcludeSemantics` ليس تجميلاً لإمكانيّة الوصول — إنّه
          // يسدّ فجوةً في الإطار نفسه.
          //
          // `RenderIndexedStack.visitChildrenForSemantics`
          // (rendering/stack.dart:782-788) تزور **الطفل المعروض وحده**،
          // فالمخفيّون لا يستلمون `parentData` للدلالات أبداً. وحين
          // يستدعي تبويبٌ مخفيّ `setState` (وعندنا مُنبّهات عامّة تفعل
          // ذلك: SubscriberEvents.dataChanged وغيرها) يُفرَّغ
          // `parentData` عبر شجرته ولا يُعاد إسناده — لأنّ المحرّك لا
          // ينزل إلى المخفيّين.
          //
          // ثمّ الطامّة: `set index` (stack.dart:792-797) تستدعي
          // `markNeedsLayout()` **فقط** — لا `markNeedsSemanticsUpdate()`
          // — رغم أنّ تغيير الفهرس يبدّل مجموعة أبناء الدلالات كاملةً.
          // فيُكشَف التبويب بـ`parentData == null`، وتسقط الثابتة
          // `!semantics.parentDataDirty` في **كلّ إطار** إلى الأبد.
          //
          // و`RenderExcludeSemantics.excluding` (proxy_box.dart:4408-4414)
          // تستدعي `markNeedsSemanticsUpdate()` في مُعيِّنها — وهي
          // الإشعار الذي يُغفله `IndexedStack`. فالتفافها حول كلّ خانة
          // يُجبر إعادة إسناد `parentData` عند كلّ تبديل تبويب.
          //
          // (فلاتر 3.47.0 — تُحقّق من stack.dart قبل إزالة هذا.)
          // ⚠️ `TickerMode` كذلك — `IndexedStack` لا يلفّ أبناءه بها.
          //
          // فحركات التبويبات المخفيّة تظلّ تنبض: AnimatedSwitcher في
          // device_chip_micro، وAnimatedOpacity في أربع لوحات أجهزة
          // حيّة، وشمعة الهيكل بـ`..repeat()` التي لا تتوقّف أبداً.
          // كلّ واحدة تُوقظ إطاراً في كلّ نبضة لشاشة لا يراها أحد —
          // بطّاريّة تُحرَق، وشجرة دلالات تُوسَّخ وهي مخفيّة (وذاك
          // بالضبط ما يجعل `ExcludeSemantics` أعلاه ضروريّة).
          //
          // الإيقاف آمن: لا شيء في المشروع يعلّق حالةً على اكتمال
          // حركة (فُحص: صفر `addStatusListener` وصفر
          // `AnimationStatus.completed`). المتوقّفة تستأنف من موضعها
          // عند العودة، والمؤقّتات (`Timer.periodic`) لا تتأثّر —
          // فجلب البيانات يبقى كما هو.
          TickerMode(
            enabled: i == active,
            child: ExcludeSemantics(excluding: i != active, child: tabs[i]),
          )
        else
          const SizedBox.shrink(),
    ];

class _MainShellState extends State<MainShell> {
  int _tab = 0;

  /// فهرس تبويب الأجهزة داخل `tabs` — مذكور مرّة واحدة لأنّ ثلاثة
  /// مواضع تعتمد عليه.
  static const _devicesTab = 2;
  static const _subsTab = 1;
  static const _dashTab = 0;

  /// التبويبات التي زارها المستخدم فعلاً.
  ///
  /// 🐛 بلاغ 2026-08-31 («التطبيق ثكيل كلش»): `IndexedStack` يبني **كلّ**
  /// أبنائه لا المرئيّ منهم — فكان `NetworkDevicesScreen.initState`
  /// يُنفَّذ لحظة الإقلاع، فيجلب الأجهزة ويُشغّل مؤقّتاً كلّ 20 ثانية
  /// يفتح مقبساً TCP لكلّ جهاز على شبكة الـLAN. وهاتف المدير خارج تلك
  /// الشبكة، فكلّ فحص ينتظر مهلته كاملة (ثانيتان) ثمّ يفشل حتماً —
  /// 14 مقبساً كلّ 20 ثانية، إلى الأبد، لشاشة لم تُفتَح قطّ.
  ///
  /// السجلّ كان يمتلئ بـ`tcpProbe … errno = 110` والمستخدم على
  /// الرئيسيّة. والكلفة على نسخة الإصدار كالتطوير: بطّاريّة وبيانات
  /// وإعادتا بناء لشجرة غير مرئيّة في كلّ جولة.
  ///
  /// الحلّ: لا يُبنى التبويب حتّى يُزار. وبعد الزيارة يبقى حيّاً —
  /// فحالته وقوائمه المحمَّلة لا تضيع عند التنقّل.
  final Set<int> _visited = <int>{0};

  /// هل تبويب الأجهزة مرئيّ الآن؟
  ///
  /// الزيارة وحدها لا تكفي: بعد فتحه مرّة يبقى حيّاً فيظلّ يفحص وأنت
  /// في تبويب آخر لساعات. الشاشة تُوقف مؤقّتها أصلاً حين يذهب التطبيق
  /// للخلفيّة — وهذه الراية تمدّ المنطق نفسه إلى الاختفاء خلف تبويب.
  final ValueNotifier<bool> _devicesActive = ValueNotifier<bool>(false);

  /// ونفسها لتبويب المشتركين — واستطلاعه أثقل: كلّ خمس ثوانٍ لا
  /// عشرين، وثلاثة طلبات بلا كاش في كلّ دورة.
  final ValueNotifier<bool> _subsActive = ValueNotifier<bool>(false);

  /// وللوحة — **لسببٍ معاكس**: لا لإيقاف استطلاعٍ بل لإطلاق تحديث.
  ///
  /// اللوحة مركَّبةٌ في `IndexedStack` طوال الجلسة، فـ`initState` لا
  /// ينطلق إلّا مرّة. وكانت تتحدّث على أربعة أحداث ليس منها **دخول
  /// التبويب**: فمن انقطعت شبكته ثمّ عادت وهو داخل التطبيق يفتح
  /// اللوحة فلا يتحدّث شيء، لأنّ التطبيق لم يذهب للخلفيّة ولم تقع
  /// عمليّةٌ على مشترك.
  final ValueNotifier<bool> _dashActive = ValueNotifier<bool>(true);

  /// تبويب الأجهزة مقفلٌ للموظّف الذي لا يملك `devices.view` (مسار القائمة عند
  /// الخادم يشترطها) — «لا صلاحيّة» بمكانه كباقي الأقسام، لا «فشل التحميل».
  /// المدير (ساس4 وايرث لنك) يملكها دائماً.
  bool get _devicesLocked => Perms.isEmployee && !Perms.has('devices.view');

  /// المدخل الوحيد لتبديل التبويب — يُسجّل الزيارة ويُحدّث الراية.
  /// أيّ مسار يكتب `_tab` مباشرةً يُفلت من الاثنين.
  /// شاشة التبويب [i] — للغلاف العريض على الحاسبة (نفس شاشات الهاتف بحالتها).
  Widget _buildTab(int i) {
    switch (i) {
      case _dashTab:
        return DashboardScreen(onOpenSubscribers: _openSubscribers, isActive: _dashActive);
      case _subsTab:
        return SubscribersScreen(filterCmd: _subsFilterCmd, isActive: _subsActive);
      default:
        return _devicesLocked
            ? const _DevicesLockedTab()
            : NetworkDevicesScreen(isActive: _devicesActive);
    }
  }

  /// الحاسبة: فُتح قسمٌ من القائمة غير التبويبات — توقف تحديثاتها الدوريّة كما لو تُركت.
  void _leaveTabs() {
    _devicesActive.value = false;
    _subsActive.value = false;
    _dashActive.value = false;
  }

  void _setTab(int i) {
    setState(() {
      _tab = i;
      _visited.add(i);
    });
    // موظّفٌ بلا «عرض الأجهزة» يرى خانةً مقفلة لا شاشة الأجهزة — فلا تُرفع رايتها.
    _devicesActive.value = !_devicesLocked && i == _devicesTab;
    _subsActive.value = i == _subsTab;
    _dashActive.value = i == _dashTab;
  }
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

  /// الغلاف يُغادر مرّةً واحدة: انتقالٌ ثانٍ وهو يُزال يبدأ انتقالاً فوق انتقال، فلا يكتمل أيّها ويبقى الغلاف
  /// مركَّباً تحت شاشة الحساب يطلب بياناته (الشاشات المتداخلة، ٢٧ أكتوبر).
  bool _leaving = false;

  void _onAuthExpired() {
    final v = authExpiredSignal.value;
    if (v == _authExpiredSeen || !mounted || _leaving) return;
    _authExpiredSeen = v;
    _leaving = true;
    // Pro: موظّف ايرث لنك المباشر (بلا حساب) ← شاشة دخوله مع السبب
    // (دخولٌ من جهازٍ آخر، أو انتهاء الجلسة) — لا بوّابة الحساب.
    if (EmployeeSession.routeToEmployeeLogin) {
      final msg = EmployeeSession.kickMessage ?? 'common.session_expired'.tr();
      Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => EmployeeLoginScreen(message: msg)),
        (_) => false,
      );
      return;
    }
    // 2026-06-14: signal من api_client.dart حين empToken الموظف انتهى
    // (refresh مرفوض بقصد). نمسح أي حالة محلية ونرجع لشاشة الدخول.
    // وسبب الخادم إن قاله (موظّف ساس عُطّل أو حُذف — 401 `EMPLOYEE_DISABLED`
    // / `EMPLOYEE_SESSION_REVOKED`) بدل «انتهت الجلسة».
    // رسالةٌ واحدة لا طابورٌ منها.
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
            content: Text(
                EmployeeSession.kickMessage ?? 'common.session_expired'.tr())),
      );
    Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AccountGateScreen()),
      (_) => false,
    );
  }

  int _accessBlockedSeen = 0;
  void _onAccessBlocked() {
    final v = accessBlockedSignal.value;
    if (v == _accessBlockedSeen || !mounted) return;
    _accessBlockedSeen = v;
    // super-admin حظر هذا الحساب. الـinterceptor مسح الجلسة بالفعل —
    // نُلقيه لـLoginScreen مع الرسالة اللي أرسلها الـsuper.
    final msg = blockedMessage ?? 'تم إيقاف حسابك — تواصل مع الإدارة';
    // dialog أوضح من snackbar للحالة الحرجة (المدير لن يرى الـsnackbar
    // لو انتقل مباشرة لـLoginScreen).
    // شيت خطر لا AlertDialog: الحوار الافتراضي يرث ثيم Material
    // (نصف قطر 28 وحشوة وأزرار خارج السلّم) ولا يعرف لغة المخطّط.
    showAppSheet<void>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: AppColors.scrim,
      builder: (ctx) => PopScope(
        canPop: false,
        child: DesignSheet(
          header: SheetHeaderBar(
            icon: Icons.block_rounded,
            title: 'تم إيقاف حسابك',
            subtitle: '',
            tint: AppColors.error,
            tintBg: AppColors.dangerSoftBg,
            onClose: () => _leaveToLogin(ctx),
          ),
          footer: SheetFooterBar(
            label: 'حسناً',
            icon: Icons.logout_rounded,
            color: AppColors.errorFill,
            onPressed: () => _leaveToLogin(ctx),
          ),
          body: Text(
            msg,
            textAlign: TextAlign.center,
            style: AppType.rowValue(color: AppColors.textBody)
                .copyWith(height: 1.6),
          ),
        ),
      ),
    );
  }

  void _leaveToLogin(BuildContext sheetCtx) {
    Navigator.of(sheetCtx).pop();
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => EmployeeSession.routeToEmployeeLogin
            ? const EmployeeLoginScreen()
            : const AccountGateScreen(),
      ),
      (_) => false,
    );
  }

  /// يترجم وجهة الإشعار المجرّدة إلى تبويبٍ ومرشِّح.
  ///
  /// الغلاف وحده يعرف بنية التبويبات، فـ`NotificationRouter` يُصدر
  /// وجهةً مجرّدة ولا يعرف أنّ المشتركين هم التبويب رقم ١.
  void _handleNotificationDestination(NotificationDestination dest) {
    if (!mounted) return;
    switch (dest) {
      case NotificationDestination.subscribersNearExpiry:
        _openSubscribers(SubscriberFilter.nearExpiry);
      case NotificationDestination.subscribersExpired:
        _openSubscribers(SubscriberFilter.expired);
      case NotificationDestination.managers:
        // المدراء ليسوا تبويباً بل داخل «قوائم أخرى» — فندفع شاشتهم.
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const ManagersScreen()),
        );
    }
  }

  @override
  void initState() {
    super.initState();
    NotificationRouter.onDestination = _handleNotificationDestination;
    // الشاشة الأولى بُنيت والجلسة قائمة — نفّذ نقرةً محفوظة إن وُجدت.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      NotificationRouter.markReady();
      // اسم الشركة (سطرها تحت اسم المدير في الرئيسيّة وفي رأس المشتركين)
      // تقديرٌ (مضيف الرابط) لجلسةٍ سبقت الميزة أو لرابطٍ يدويّ ← يُحسم من
      // «شركاتي» مرّةً، بلا انتظار.
      unawaited(ActiveCompany.resolveLabel());
      // حال المساعد الذكيّ أوّل الجلسة (مطفأً يردّ الخادم فوراً) — فبطاقة
      // «كيف أسوّي؟» لا تُدرج متأخّرةً فوق «التقارير» فتزيح البطاقات تحت
      // الإصبع، وزرّه في أزرار الأعلى (جنب الجرس) يظهر مع أوّل إطار،
      // و«اشرحلي» حاضرٌ مع أوّل إشعار خطأ.
      unawaited(AiAssistantState.ensureFresh());
      // «كل الشركات»: يعود الوضع إن كان مفعّلاً لهذا الحساب وما زال متاحاً.
      unawaited(MergedMode.restore());
    });
    _authExpiredSeen = authExpiredSignal.value;
    authExpiredSignal.addListener(_onAuthExpired);
    _accessBlockedSeen = accessBlockedSignal.value;
    accessBlockedSignal.addListener(_onAccessBlocked);
  }

  @override
  void dispose() {
    authExpiredSignal.removeListener(_onAuthExpired);
    accessBlockedSignal.removeListener(_onAccessBlocked);
    _subsFilterCmd.dispose();
    _devicesActive.dispose();
    _subsActive.dispose();
    _dashActive.dispose();
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
    showAppSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: AppColors.scrim,
      builder: (_) => _QuickAddSheet(rootContext: rootCtx),
    );
  }

  /// Public entry point for any tab to jump to the subscribers list
  /// with a specific filter pre-applied (dashboard taps use this).
  /// Notifier listeners on SubscribersScreen pick up the change without
  /// the widget being recreated — instant tab switch, no refetch.
  void _openSubscribers(SubscriberFilter? filter) {
    HapticFeedback.selectionClick();
    _setTab(1);
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
      _setTab(0);
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
    // أجهزة الشبكة لكلّ مزوّد (ساس4 وايرث لنك): القائمة عند الخادم بمعرّف المدير، والفحص من
    // الهاتف نفسه — لا ساس ولا وكيل. نستمع لـ`Perms.changes` لأنّ صلاحيّات الموظّف قد
    // تُحمَّل بعد أوّل بناء، ولـ`ProviderService.changes` لبقيّة الغلاف.
    return ListenableBuilder(
      listenable: Listenable.merge([ProviderService.changes, Perms.changes]),
      builder: (context, _) {
        // الحاسبة (نافذةٌ عريضة): قائمةٌ جانبيّة بكلّ الأقسام والمحتوى بجانبها بدل الشريط السفليّ.
        if (DesktopLayout.wide(context)) {
          return DesktopShell(
            currentTab: _tab,
            tabBuilder: _buildTab,
            onSelectTab: _setTab,
            onLeaveTabs: _leaveTabs,
            onQuickAdd: _onFabTap,
          );
        }
        final tabs = <Widget>[
          DashboardScreen(
              onOpenSubscribers: _openSubscribers, isActive: _dashActive),
          SubscribersScreen(filterCmd: _subsFilterCmd, isActive: _subsActive),
          // مطلب 2026-08-12: أجهزة الشبكة صار tab رئيسي بدل التقارير —
          // WISP يفتحها يوميّاً لمراقبة اللنكات/السكاتر. التقارير انتقلت
          // لـ"قوائم أخرى" كأوّل عنصر (الاستعمال أقلّ). موظّفٌ بلا صلاحيّة: الخانة باقيةٌ
          // بمكانها مقفلة (إخفاؤها يخلخل توزيع الأزرار حول +).
          _devicesLocked ? const _DevicesLockedTab() : NetworkDevicesScreen(isActive: _devicesActive),
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
      },
    );
  }

  Widget _buildScaffold(List<Widget> tabs) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      extendBody: true, // body draws under the floating bar
      // ٢٠٢٦-١٠-١٢: شريط «الشركة المفتوحة» الممتدّ أعلى التبويبات أُزيل
      // (طلب المستخدم: «ما يحتاج تاخذ مساحة من أعلى») — صار سطراً مدمجاً
      // تحت اسم المدير في ترويسة الرئيسيّة وفي رأس المشتركين
      // (`ActiveCompanyLine`). فالجسم مكدّسٌ ثابت لا يتبدّل أبوه أبداً،
      // والتبويبات تأخذ حشوتها العلويّة كما كانت.
      body: Stack(
        children: [
          // كسول: غير المزار يبقى `SizedBox` فلا يُنشأ `State` له ولا
          // يُنفَّذ `initState`. وبعد الزيارة يبقى في الشجرة كما كان.
          IndexedStack(
            // المزوّد قد يُحسَم بعد أن زار المستخدم فهرساً أبعد من تخطيط
            // ايرث لنك المختصر — الحصر يمنع تجاوز المدى قبل أن يُصحّح التبويبَ
            // أوّلُ نقرة.
            index: _tab.clamp(0, tabs.length - 1),
            children:
                lazyTabChildren(tabs, _visited, _tab.clamp(0, tabs.length - 1)),
          ),
          // Standalone search pill — 2026-07-14: أقرب ما يمكن للـnav
          // (4px فوق حافّته العلويّة). لا نقدر نضعه داخله لأن الـpill
          // في body's Stack والـnav يُرسم فوق (فيختفي). 4px يعطيه
          // إحساس أنّه ملحق بالتنقّل بلا فراغ.
          // 2026-08-30: الحبّة صارت على الرئيسيّة وحدها. كانت تطفو فوق
          // كلّ تبويب، وفي شاشة المشتركين تحديداً تُزاحم شريط بحث
          // كامل في رأس الصفحة — زرّان لوظيفة واحدة.
          if (_tab == 0)
            Positioned(
              right: Sp.lg,
              bottom: 64 + Sp.sm + MediaQuery.paddingOf(context).bottom + 4,
              child: _SearchPill(onTap: () => showQuickSearch(context)),
            ),
        ],
      ),
      // 2026-08-29 (S6): الشريط صار مسطّحاً من الحافة للحافة بحدّ علوي
      // بدل الحبّة العائمة — لغة المخطّط. الـSafeArea داخل _PillBar
      // ليمتدّ البياض تحت شريط الإيماءات.
      bottomNavigationBar: _PillBar(
        current: _tab,
        onTabTap: _setTab,
        onFabTap: _onFabTap,
      ),
    );
  }
}

/// الشريط السفلي — لغة المخطّط: سطح أبيض ممتدّ للحافتين بحدّ علوي
/// شعري، بلا نصف قطر وبلا ظلّ. أربعة تبويبات (أيقونة 24 + تسمية 10.5)
/// وزرّ إضافة مربّع 52×52/r18 مرفوع 14 فوق خطّ الشريط بظلّ ملوّن
/// بالبراند نفسه (`Sh.fab`) لا بالأسود.
///
/// ترتيب التبويبات محفوظ كما هو (الرئيسية أوّلاً) — المخطّط يعرضها
/// بترتيب مختلف لأنّه مرسوم على شاشة المشتركين، والتبديل يربك مَن
/// اعتاد مواضعها.
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
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 10, 18, Sp.sm),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _TabSlot(
                icon: Icons.home_rounded,
                label: 'nav.home'.tr(),
                selected: current == 0,
                onTap: () => _select(0),
              ),
              _TabSlot(
                icon: Icons.people_alt_rounded,
                label: 'nav.subscribers'.tr(),
                selected: current == 1,
                onTap: () => _select(1),
              ),
              _FabSlot(onTap: onFabTap),
              _TabSlot(
                // مطلب 2026-08-12: أجهزة الشبكة بدل التقارير. موظّفٌ بلا صلاحيّة:
                // الخانة نفسها تفتح شاشةً مقفلة — لا تختفي فيبقى التوزيع متناظراً.
                icon: Icons.router_rounded,
                label: 'nav.devices'.tr(),
                selected: current == 2,
                onTap: () => _select(2),
              ),
              _TabSlot(
                // مطلب 2026-06-10: 'قوائم أخرى' بدل 'الضبط' لأن
                // الـtab صار يعرض المديولات الإضافية لا الإعدادات.
                // الإعدادات الفعلية انتقلت لزر الـgear بالشريط العلوي.
                icon: Icons.apps_rounded,
                label: 'nav.more'.tr(),
                selected: current == 3,
                onTap: () => _select(3),
              ),
            ],
          ),
        ),
      ),
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
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final fg = selected ? AppColors.brand : AppColors.textLow;
    return SizedBox(
      width: 58,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(R.icon),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: Sp.xs),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: fg, size: 24),
                const SizedBox(height: 3),
                // المخطّط لا يضع نقطة تحت التبويب النشط — اللون
                // والوزن وحدهما يميّزانه، والنقطة كانت تضيف 7dp
                // ارتفاعاً بلا مقابل.
                AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 200),
                  style: AppType.micro(color: fg).copyWith(
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  ),
                  child: Text(label, maxLines: 1, overflow: TextOverflow.fade),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FabSlot extends StatelessWidget {
  const _FabSlot({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    // مرفوع 14 فوق خطّ الشريط كما في المخطّط، ومربّع r18 لا دائرة.
    return Transform.translate(
      offset: const Offset(0, -14),
      child: Container(
        width: H.fab,
        height: H.fab,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(R.card),
          boxShadow: Sh.fab,
        ),
        child: Material(
          color: AppColors.brand,
          borderRadius: BorderRadius.circular(R.card),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () {
              HapticFeedback.selectionClick();
              onTap();
            },
            child: const Icon(Icons.add_rounded,
                color: AppColors.onBrand, size: 26),
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
            // بلا ظلّ — نفس سبب stats_grid.
            border: Border.all(color: AppColors.brand, width: BW.selected),
          ),
          child: Icon(Icons.search_rounded, color: AppColors.brand, size: 20),
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
    // بلاغ ٢٠٢٦-١٠-١٤: البند المبوّب لا يختفي — يبقى بمكانه **مقفلاً**
    // (القفل مكان السهم، والنقر رسالةٌ لا تغلق الشيت ولا تفتح شيئاً).
    // ويختفي فقط ما لا يُمنح لهذا الدور أصلاً ([permShown]).
    const kAdd = ['subscribers.add'];
    const kActivate = ['subscribers.activate'];
    const kPay = ['subscribers.pay_debt'];
    const kAddDebt = ['subscribers.add_debt'];
    const kExpense = ['reports.expenses'];
    // الحالة الفارغة لا تظهر إلّا إن لم يُعرض بندٌ واحد (ولا مقفلاً) —
    // عمليّاً لا تُبلَغ. ⚠️ كانت `hasAny` تضمّ `extend` وليس له بند هنا،
    // فمَن يملك التمديد وحده يرى شيتاً بعنوانٍ وفراغ.
    final anyShown = permShown(kAdd) ||
        permShown(kActivate) ||
        permShown(kPay) ||
        permShown(kAddDebt) ||
        permShown(kExpense);
    return DesignSheet(
      header: SheetHeaderBar(
        icon: Icons.add_rounded,
        title: 'dashboard.quick_add'.tr(),
        subtitle: '',
        onClose: () => Navigator.of(context).pop(),
      ),
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!anyShown)
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
          // لا خطأ "غير مسموح" بعد الضغط — والبند بلا مفتاحه يبقى
          // مقفلاً بمكانه (٢٠٢٦-١٠-١٤) بدل أن يختفي.
          if (permShown(kAdd))
            _QuickItem(
              locked: !Perms.hasAny(kAdd),
              icon: Icons.person_add_rounded,
              color: AppColors.brandAccent,
              title: 'dashboard.add_subscriber'.tr(),
              subtitle: 'dashboard.add_subscriber_hint'.tr(),
              onTap: () => showAddSubscriberSheet(rootContext),
            ),
          // ⚠️ البوّابة `activate` وحدها لا `hasAny(activate, extend)`.
          //
          // كانت تسمح لمن يملك `extend` فقط، بينما الفعل يفتح شيت
          // **التفعيل** — فيرى الزرّ ويُرفض بعد الضغط. والفرق ليس
          // تسميةً: التفعيل يبدأ اشتراكاً بباقة وسعر، والتمديد يزيد
          // أيّاماً على القائم. مَن يملك التمديد وحده يصل إليه من كارت
          // المشترك، وهو موضعه الطبيعي لأنّه يحتاج اشتراكاً قائماً.
          if (permShown(kActivate))
            _QuickItem(
              locked: !Perms.hasAny(kActivate),
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
          if (permShown(kPay))
            _QuickItem(
              locked: !Perms.hasAny(kPay),
              icon: Icons.payments_rounded,
              color: AppColors.success,
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
          if (permShown(kAddDebt))
            _QuickItem(
              locked: !Perms.hasAny(kAddDebt),
              icon: Icons.account_balance_wallet_rounded,
              color: AppColors.warning,
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
          if (permShown(kExpense))
            _QuickItem(
              locked: !Perms.hasAny(kExpense),
              icon: Icons.receipt_long_rounded,
              color: AppColors.brandAccent,
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
    this.locked = false,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;

  /// Defaults to closing the sheet — items without a wired action
  /// still let the admin dismiss the sheet by tapping.
  final VoidCallback? onTap;

  /// بلا مفتاح البند: يبقى بمكانه خافتاً بقفلٍ مكان السهم، ونقره رسالةٌ
  /// **لا تغلق الشيت** ولا تستدعي [onTap] (فلا منتقي ولا شيت يُرفض).
  final bool locked;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final item = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: locked
            ? () => showNoPermission(context, action: true)
            : () {
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
                  color:
                      locked ? LockedStyle.box : color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(R.sm),
                ),
                child: Icon(icon,
                    color: locked ? LockedStyle.glyph : color, size: 22),
              ),
              const SizedBox(width: Sp.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: AppType.label(
                                color: locked
                                    ? LockedStyle.title
                                    : AppColors.textHi)
                            .copyWith(fontSize: 14)),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: AppType.subtitle(
                                color: locked
                                    ? LockedStyle.subtitle
                                    : AppColors.textMid)
                            .copyWith(fontSize: 12.5)),
                  ],
                ),
              ),
              if (locked)
                const PermLockIcon(size: 14)
              else
                Icon(Icons.arrow_back_ios_new_rounded,
                    size: 12, color: AppColors.textLow),
            ],
          ),
        ),
      ),
    );
    if (!locked) return item;
    return Semantics(
      button: true,
      label: 'locked.a11y'.tr(args: [title]),
      excludeSemantics: true,
      child: item,
    );
  }
}

/// خانة «الأجهزة» لموظّفٍ لا يملك «عرض الأجهزة»: لا تُبنى شاشة الأجهزة ولا تُطلب
/// بياناتها — «لا صلاحيّة» بمكانها كباقي الأقسام المقفلة.
class _DevicesLockedTab extends StatelessWidget {
  const _DevicesLockedTab();

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Padding(
          // حشوة رأس الرئيسيّة نفسها: أزرار الأعلى في موضعها من كلّ تبويب.
          padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.sm, Sp.lg, Sp.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // أزرار الأعلى بمكانها ولو قُفل القسم — الإعدادات والإشعارات
              // والمساعد ليست من صلاحيّة الأجهزة.
              TabHeader(title: 'nav.devices'.tr()),
              const Spacer(),
              const Center(child: LockedNotice.block()),
              const Spacer(flex: 2),
            ],
          ),
        ),
      ),
    );
  }
}
