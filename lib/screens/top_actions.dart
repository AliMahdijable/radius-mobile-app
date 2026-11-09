import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../api/renew_requests_api.dart';
import '../api/tickets_api.dart';
import '../core/platform/desktop_layout.dart';
import '../core/widgets/permission_locked.dart';
import '../services/active_company.dart';
import '../services/ai_assistant_state.dart';
import '../services/alerts_service.dart';
import '../services/app_resumed_signal.dart';
import '../services/inbox_service.dart';
import '../services/linked_companies.dart';
import '../services/permissions_service.dart';
import '../theme/colors.dart';
import '../theme/spacing.dart';
import '../theme/typography.dart';
import '../widgets/active_company_line.dart';
import 'account/company_switch_sheet.dart';
import 'accounts/accounts_screen.dart';
import 'assistant/assistant_sheet.dart';
import 'employees/sheets/employee_pages_sheet.dart';
import 'voice/voice_command_sheet.dart';
import 'notifications/inbox_screen.dart';
import 'settings_screen.dart';

/// «التبديل» من رأس كلّ تبويب — **سطر الشركة تحت العنوان هو زرّه** (وفي الرئيسيّة: الاسم وسطره).
///
/// ٧ نوفمبر (المالك: «القوائم والازرار صارت بتزاحم كبير فكرلي بتصميم عصري ويحافظ ع الدوال والقوائم هاي»): كان الرأس ستّة
/// مربّعات (الشركات · الصفحات · أمر صوتي · المساعد · الجرس · الترس) فيصغر العنوان أو يُبتر. صار ثلاثة ([TopActions])، و«الشركات»
/// و«الصفحات» نزلا لسطر الشركة: النقر يفتح ورقة الشركات وأعلاها «الصفحات»، أو «الصفحات» مباشرةً لمن ليست له شركتان.
class HeaderSwitch {
  HeaderSwitch._();

  /// شركات الحساب — المالك بشركتين فأكثر ([LinkedCompanies.switcherVisible]).
  static bool get companies => LinkedCompanies.switcherVisible;

  /// «الصفحات» (المدراء الفرعيّون داخل الشركة المفتوحة). ⚠️ `managers.edit` لا `managers.view`: التبديل يستعمل كلمة سرّ المدير
  /// الفرعيّ — فهو أقوى من رؤيتها ولا يقلّ عنها حرساً.
  static bool get pages => Perms.has('managers.edit');

  /// ٨ نوفمبر — «موظّفٌ بأكثر من صفحة»: «صفحاتي» لموظّفٍ يعمل في صفحتين فأكثر ([PermissionsService.employeePages]).
  static bool get employeePages => PermissionsService.employeePages.length >= 2;

  /// للسطر نقرة؟
  static bool get available => companies || pages || employeePages;

  /// اسم الفعل — لقارئ الشاشة، ونصّ السطر حين لا تُعرف الشركة بعد.
  static String get label => employeePages
      ? 'صفحاتي'
      : companies
          ? 'company_switch.title'.tr()
          : 'accounts.title'.tr();

  /// يفتح ورقة الشركات («الصفحات» صفٌّ أعلاها)، أو «الصفحات» مباشرةً.
  static Future<void> open(BuildContext context,
      {void Function(Widget page)? openPage}) async {
    void openPages() {
      if (!context.mounted) return;
      if (openPage != null) return openPage(const AccountsScreen());
      Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => const AccountsScreen()));
    }

    // موظّفٌ بأكثر من صفحة: «صفحاتي» (و«الصفحات» صفٌّ أعلاها إن ملك تبديل المدراء الفرعيّين) — الموظّف لا «شركاتي» له
    if (employeePages) {
      return showEmployeePagesSheet(context, onManagers: pages ? openPages : null);
    }
    if (companies) {
      return showCompanySwitchSheet(context, onPages: pages ? openPages : null);
    }
    if (pages) openPages();
  }
}

/// أزرار الأعلى — **المساعد الذكيّ · الإشعارات · الإعدادات** — في رأس كلّ
/// تبويبٍ رئيسيّ وبالمكان نفسه: الزاوية العليا اليسرى، ‎16 من الحافّة و‎8 تحت
/// الشقّ العلويّ.
///
/// طلب المالك ٢٠ أكتوبر: «المساعد الذكي لو وضايفة أعلى القائمة جنب جرس التنبيه
/// مو أفضل؟ والأزرار هاي نفسها أريدها تظهر بالقوائم الأخرى». كانت الرئيسيّة
/// وحدها تحمل الترس والجرس، والمساعد بطاقةً في «قوائم أخرى» وحدها.
///
/// الترتيب بالعربيّة (من اليمين): المساعد ← الجرس ← الترس. فالترس يبقى في
/// الزاوية والجرس جنبه كما كانا في الرئيسيّة، والمساعد يُضاف جنب الجرس.
///
/// المساعد يتبع حال الخادم **كبطاقة «كيف أسوّي؟» حرفيّاً** ([AiAssistantState]):
/// • مطفأٌ لهذا الحساب (أو حالٌ لم تُعرف بعد) ⇒ لا زرّ، والجرس والترس بمكانيهما.
/// • موظّفٌ بلا الصلاحيّة ⇒ الزرّ **بمكانه مقفلاً** والنقر رسالة القفل بلا أيّ
///   طلب (قاعدة «مقفل لا مخفيّ»).
/// • وإلّا يفتح ورقة «كيف أسوّي؟» نفسها، والموافقة أوّلاً
///   ([AssistantSheet.showAsk]).
/// والبطاقة في «قوائم أخرى» باقيةٌ كما هي. ولا شيء هنا يبيع أو يجدّد (آيفون).
///
/// ٢٢ أكتوبر (المالك: «زرّ التبديل بين الأدمنية والتبديل بين الصفحات مو موجود
/// بكلّ صفحات التطبيق») كانت تسبقها «تبديل الشركة» و«الصفحات» و(٧ نوفمبر) «أمر صوتي» — ستّة مربّعات تزاحم العنوان. منذ ٧ نوفمبر
/// (المالك: «القوائم والازرار صارت بتزاحم كبير»): على الهاتف **ثلاثة** — «أمر صوتي» (أو المساعد لحسابٍ بلاه) · الجرس · الترس.
/// التبديل في سطر الشركة تحت العنوان ([HeaderSwitch])، والمساعد ثانويٌّ داخل ورقة «أمر صوتي» (المالك: «لوتخلي الامر الصوتي مجرد
/// نقر والمساعد الذكاء نخلي هو الثانوي»). شريط الحاسبة كما كان («الصفحات» و«أمر صوتي» والمساعد فيه).
class TopActions extends StatelessWidget {
  const TopActions({
    super.key,
    this.switchers = false,
    this.inDesktopBar = false,
    this.openPage,
  });

  /// الرأس يحمل التبديل: شركات الحساب تُسأل لمهلتها (سطر الشركة يقرؤها)، و«الصفحات» مربّعٌ في شريط الحاسبة.
  final bool switchers;

  /// في شريط الحاسبة العلويّ: الترس في القائمة الجانبيّة فلا يتكرّر هنا.
  final bool inDesktopBar;

  /// يفتح الصفحة في منطقة المحتوى (غلاف الحاسبة) بدل المكدّس الجذريّ الذي يغطّي القائمة.
  final void Function(Widget page)? openPage;

  void _open(BuildContext context, Widget page) {
    if (openPage != null) return openPage!(page);
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final gap = TopActionChip.gapOf(context);
    return ListenableBuilder(
      listenable: Listenable.merge([
        // مطفأٌ افتراضيّاً — الاستماع نفسه يسأل الخادم إن كانت الحال قديمة.
        AiAssistantState.gate,
        // العودة للتطبيق ⇒ يُسأل ثانيةً (بمهلته) — فتشغيله من الخادم يظهر.
        AppResumedSignal.tick,
        // شركات الحساب (تصل بعد الفتح) وصلاحيّة «الصفحات» (تُحمَّل بعد الإقلاع).
        LinkedCompanies.items,
        PermissionsService.changes,
      ]),
      builder: (context, _) {
        // كبطاقة «قوائم أخرى» تماماً: كلّ بناءٍ يسأل إن كانت الحال قديمة —
        // مهلة ٥ دقائق وتبريد ٣٠ث بعد الفشل وطلبٌ واحدٌ جارٍ على الأكثر،
        // فأربعة تبويباتٍ لا تعني أربعة طلبات.
        scheduleMicrotask(AiAssistantState.ensureFresh);
        // وشركات الحساب كذلك: مرّةً لمهلتها، وللمالك وحده (لا طلب لموظّف).
        if (switchers) scheduleMicrotask(LinkedCompanies.ensureFresh);
        // «أمر صوتي» (الخادم فتحه لهذا الحساب — ai_assistant.voice) **بنقرةٍ واحدة** مكان المساعد، والمساعد ثانويٌّ داخل ورقته
        // (٧ نوفمبر — المالك: «لوتخلي الامر الصوتي مجرد نقر والمساعد الذكاء نخلي هو الثانوي»؛ مقفلٌ لموظّفٍ ⇒ بمكانه هناك مقفلاً).
        // بلا «أمر صوتي» ⇒ المساعد بمكانه كما كان. شريط الحاسبة كما كان: المربّعان معاً.
        final voice = AiAssistantState.voice;
        final assistantSquare =
            AiAssistantState.visible && (inDesktopBar || !voice);
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // «الصفحات» مربّعٌ في شريط الحاسبة وحده — على الهاتف في سطر الشركة ([HeaderSwitch]).
            if (switchers && inDesktopBar && HeaderSwitch.pages) ...[
              TopActionChip(
                key: const ValueKey('top-actions-accounts'),
                icon: Icons.swap_horiz_rounded,
                label: 'accounts.title'.tr(),
                onTap: () => _open(context, const AccountsScreen()),
              ),
              SizedBox(width: gap),
            ],
            if (voice) ...[
              TopActionChip(
                key: const ValueKey('top-actions-voice'),
                icon: LucideIcons.mic,
                label: 'أمر صوتي',
                iconColor: AppColors.brandAccent,
                onTap: () => showVoiceCommandSheet(context),
              ),
              SizedBox(width: gap),
            ],
            if (assistantSquare) ...[
              TopActionChip(
                key: const ValueKey('top-actions-assistant'),
                icon: LucideIcons.sparkles,
                label: 'ai.title'.tr(),
                iconColor: AppColors.brandAccent,
                locked: AiAssistantState.askLocked,
                onTap: () => AssistantSheet.showAsk(context),
              ),
              SizedBox(width: gap),
            ],
            _NotificationsChip(onOpen: (page) => _open(context, page)),
            if (!inDesktopBar) ...[
              SizedBox(width: gap),
              TopActionChip(
                key: const ValueKey('top-actions-settings'),
                icon: Icons.settings_outlined,
                label: 'common.settings'.tr(),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const SettingsScreen(),
                    fullscreenDialog: true,
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// الجرس — والشارة كما كانت في الرئيسيّة: الإشعارات غير المقروءة + المشتركون
/// في خطر (قربوا الانتهاء + انتهوا اليوم)، رقمٌ واحد لكلّ ما يحتاج انتباهاً.
/// `AlertsService.count` يتحدّث من قائمة المشتركين ومن شاشة الإشعارات.
/// + «طلبات التجديد» بانتظارك (٤ نوفمبر — المالك: «في حال اكو طلب يظهر بالجرس»): الاستماع نفسه يقرؤها، والعودة للتطبيق كذلك.
/// + «تذاكر المشتركين» (٩ نوفمبر — قرار المالك، كجرس الويب): كلّ تذكرةٍ تنتظرك مرّةً واحدة — غير مقروءة أو «بانتظارك» — حتى تُعالَج
///   كطلبات التجديد ([TicketsState.bellBadge] — قاعدتها سطرٌ واحد [kTicketsBadgeRule])، لمن يرى القسم وحده؛ الاستماع يقرؤها للشركة
///   المفتوحة، والعودة للتطبيق وإشعار التذكرة كذلك.
class _NotificationsChip extends StatefulWidget {
  const _NotificationsChip({required this.onOpen});

  final void Function(Widget page) onOpen;

  @override
  State<_NotificationsChip> createState() => _NotificationsChipState();
}

class _NotificationsChipState extends State<_NotificationsChip> {
  @override
  void initState() {
    super.initState();
    AppResumedSignal.tick.addListener(_onResume);
  }

  @override
  void dispose() {
    AppResumedSignal.tick.removeListener(_onResume);
    super.dispose();
  }

  void _onResume() {
    unawaited(RenewRequestsState.onResume());
    unawaited(TicketsState.onResume());
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: InboxService.changes,
      builder: (context, _, __) => ValueListenableBuilder<int>(
        valueListenable: AlertsService.count,
        builder: (context, alerts, __) => ValueListenableBuilder<RenewSnapshot?>(
          valueListenable: RenewRequestsState.gate,
          builder: (context, _, __) => ListenableBuilder(
            // الملخّص (الأعداد) وقائمة الجرس (غير المقروءة خارج «بانتظارك») — الرقم منهما معاً
            listenable: Listenable.merge([TicketsState.gate, TicketsState.bell]),
            builder: (context, _) => TopActionChip(
              key: const ValueKey('top-actions-notifications'),
              icon: Icons.notifications_none_rounded,
              label: 'notifications.title'.tr(),
              badge: InboxService.unreadCount + alerts + RenewRequestsState.pending + TicketsState.bellBadge,
              onTap: () => widget.onOpen(const InboxScreen()),
            ),
          ),
        ),
      ),
    );
  }
}

/// مربّع أيقونة الأعلى — سطحٌ بحدٍّ ونصف قطر 12 كما كان زرّا الرئيسيّة.
///
/// ‎42×42 عادةً، و‎38 بفراغ ‎6 على الشاشات الضيّقة (أقلّ من ‎360): في الرئيسيّة
/// أربعة مربّعات بجانب اسم المدير (مع «الصفحات»)، وبالحجم الكامل لا يبقى للاسم
/// على شاشة ‎320 إلّا ‎88 نقطة فيُبتر. والحجم يتبع عرض الشاشة لا التبويب، فتبقى
/// الأزرار بمقاسٍ واحدٍ ومكانٍ واحدٍ في كلّ التبويبات.
///
/// المقفل ([locked]): المكان والمقاس نفسهما، الأيقونة خافتة وعليها شارة القفل
/// ([PermLockBadge])، والنقر رسالة القفل ([showNoPermission]) لا [onTap].
class TopActionChip extends StatelessWidget {
  const TopActionChip({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.badge = 0,
    this.iconColor,
    this.locked = false,
  });

  final IconData icon;

  /// اسم الزرّ — تلميح الضغط المطوّل ونصّ قارئ الشاشة.
  final String label;
  final VoidCallback onTap;

  /// عددٌ أحمر على الركن (الجرس) — يُخفى عند الصفر.
  final int badge;

  /// لون الأيقونة — `textHi` افتراضاً.
  final Color? iconColor;
  final bool locked;

  static const double size = 42;
  static const double compactSize = 38;

  /// أضيق من هذا تصغر المربّعات وفراغاتها.
  static const double narrowWidth = 360;

  static bool _narrow(BuildContext context) =>
      MediaQuery.sizeOf(context).width < narrowWidth;

  /// ضلع المربّع على هذه الشاشة.
  static double sizeOf(BuildContext context) =>
      _narrow(context) ? compactSize : size;

  /// الفراغ بين مربّعين على هذه الشاشة.
  static double gapOf(BuildContext context) => _narrow(context) ? Sp.x6 : Sp.sm;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final side = sizeOf(context);
    final VoidCallback tap = locked ? () => showNoPermission(context) : onTap;
    Widget chip = SizedBox(
      width: side,
      height: side,
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.md),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: tap,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(R.md),
              border: Border.all(color: AppColors.border),
            ),
            child: Icon(
              icon,
              size: 20,
              color: locked ? LockedStyle.glyph : iconColor ?? AppColors.textHi,
            ),
          ),
        ),
      ),
    );
    if (locked) chip = PermLockBadge(child: chip);
    final count = locked ? 0 : badge;
    return Semantics(
      button: true,
      label: locked
          ? 'locked.a11y'.tr(args: [label])
          : count > 0
              ? '$label ($count)'
              : label,
      // الأبناء مستبعدون (اسمٌ واحد بدل الأيقونة والتلميح) — فالنقر يُعلَن هنا،
      // وإلّا كان الزرّ مسمّىً بلا نقرة فلا يفعّله TalkBack (كـ«اشرحلي»).
      onTap: tap,
      excludeSemantics: true,
      child: Tooltip(
        message: label,
        excludeFromSemantics: true,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            chip,
            if (count > 0)
              Positioned(
                top: -4,
                left: -4,
                child: IgnorePointer(
                  child: Container(
                    constraints:
                        const BoxConstraints(minWidth: 18, minHeight: 18),
                    padding: const EdgeInsets.symmetric(horizontal: 5),
                    decoration: BoxDecoration(
                      color: AppColors.errorFill,
                      borderRadius: BorderRadius.circular(R.pill),
                      border: Border.all(color: AppColors.bg, width: 2),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '$count',
                      style: AppType.muted(color: AppColors.onBrand)
                          .copyWith(fontSize: 10.5, height: 1),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// رأس التبويب الموحّد: العنوان (وسطرٌ تحته إن وُجد) على اليمين، و[TopActions]
/// على اليسار — فالأزرار في الموضع نفسه من كلّ تبويب. عنوانٌ بسطرٍ واحد يتوسّط
/// ارتفاع الأزرار، وعنوانٌ بسطرين يبدأ معها من الأعلى.
///
/// يُلفّ بحشوةٍ ‎`fromLTRB(Sp.lg, Sp.sm, Sp.lg, …)` تحت المنطقة الآمنة — حشوة
/// ترويسة الرئيسيّة نفسها.
///
/// ٧ نوفمبر: على الهاتف سطر الشركة تحت العنوان دائماً ([HeaderSubline]) — وهو زرّ «التبديل» ([HeaderSwitch]) بسهم ⌄.
class TabHeader extends StatelessWidget {
  const TabHeader({super.key, required this.title, this.subtitle});

  final String title;

  /// سطرٌ تحت العنوان بدل سطر الشركة (المشتركون: الشركة والعدد). على الهاتف يصير زرّ التبديل كسطر الشركة.
  final Widget? subtitle;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    // الحاسبة: الأزرار في الشريط العلويّ للغلاف، والعنوان رأس صفحةٍ كبير كالموقع.
    return DesktopScope.of(context) ? _desktop() : _mobile(context);
  }

  Widget _desktop() {
    return Padding(
      padding: const EdgeInsets.only(top: Sp.md, bottom: Sp.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppType.title().copyWith(fontSize: 28, height: 1.2),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            subtitle!,
          ],
        ],
      ),
    );
  }

  Widget _mobile(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: ConstrainedBox(
            constraints:
                BoxConstraints(minHeight: TopActionChip.sizeOf(context)),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // ⚠️ يصغر ولا يُبتر: شاشة ٣٢٠ بخطٍّ مكبَّر — «المشتركو…» أسوأ من عنوانٍ أصغر قليلاً.
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    title,
                    maxLines: 1,
                    style: AppType.title(),
                  ),
                ),
                HeaderSubline(subtitle: subtitle),
              ],
            ),
          ),
        ),
        const SizedBox(width: Sp.sm),
        const TopActions(switchers: true),
      ],
    );
  }
}

/// السطر تحت عنوان التبويب: [subtitle] إن وُجد وإلّا سطر الشركة المفتوحة ([ActiveCompanyLine])، وحين يكون للحساب تبديل
/// ([HeaderSwitch.available]) يصير السطر زرّه وبعده سهم ⌄ — مكان مربّعَي «الشركات» و«الصفحات» (٧ نوفمبر).
///
/// شركةٌ لم تُعرف بعد وللحساب تبديل ⇒ اسم الفعل نفسه («تبديل الشركة ⌄») فلا يغيب الزرّ؛ وبلا تبديلٍ ولا شركة ⇒ لا سطر.
class HeaderSubline extends StatelessWidget {
  const HeaderSubline({super.key, this.subtitle});

  final Widget? subtitle;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return ListenableBuilder(
      listenable: Listenable.merge([
        ActiveCompany.listenable,
        LinkedCompanies.items,
        PermissionsService.changes,
      ]),
      builder: (context, _) {
        final company = ActiveCompany.current;
        final line = subtitle ??
            (company == null ? null : ActiveCompanyLine(info: company));
        final Widget? shown;
        if (HeaderSwitch.available) {
          shown = CompanySwitchTap(
            key: const ValueKey('header-switch'),
            label: company?.label ?? '',
            action: HeaderSwitch.label,
            onTap: () => HeaderSwitch.open(context),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: line ??
                      Text(
                        HeaderSwitch.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppType.label(color: AppColors.brand)
                            .copyWith(fontSize: 12.5),
                      ),
                ),
                const SizedBox(width: 2),
                Icon(Icons.expand_more_rounded,
                    size: 15, color: AppColors.textMid),
              ],
            ),
          );
        } else {
          shown = line;
        }
        if (shown == null) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 2),
          child: shown,
        );
      },
    );
  }
}
