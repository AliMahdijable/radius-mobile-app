import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/widgets/permission_locked.dart';
import '../services/ai_assistant_state.dart';
import '../services/alerts_service.dart';
import '../services/app_resumed_signal.dart';
import '../services/inbox_service.dart';
import '../services/linked_companies.dart';
import '../services/permissions_service.dart';
import '../theme/colors.dart';
import '../theme/spacing.dart';
import '../theme/typography.dart';
import 'account/company_switch_sheet.dart';
import 'accounts/accounts_screen.dart';
import 'assistant/assistant_sheet.dart';
import 'notifications/inbox_screen.dart';
import 'settings_screen.dart';

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
/// بكلّ صفحات التطبيق»): مع [switchers] يسبقها **«تبديل الشركة»** (صفحات الحساب
/// المربوطة — للمالك بشركتين فأكثر) و**«الصفحات»** (المدراء الفرعيّون داخل
/// الشركة المفتوحة — بصلاحيّة `managers.edit`)، كما في الرئيسيّة حرفاً.
class TopActions extends StatelessWidget {
  const TopActions({super.key, this.switchers = false, this.companySquare = true});

  /// «تبديل الشركة» و«الصفحات» قبل المساعد.
  final bool switchers;

  /// مربّع «تبديل الشركة» نفسه — الرئيسيّة تُسقطه حين لا يتّسع لاسم المدير
  /// فيصير سطر الشركة تحت الاسم هو الزرّ.
  final bool companySquare;

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
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // «الشركات» جنب «الصفحات» من جهة الاسم، فيبقى «الصفحات» بمكانه.
            if (switchers && companySquare && LinkedCompanies.switcherVisible) ...[
              TopActionChip(
                key: const ValueKey('top-actions-company-switch'),
                icon: Icons.apartment_rounded,
                label: 'company_switch.title'.tr(),
                onTap: () => showCompanySwitchSheet(context),
              ),
              SizedBox(width: gap),
            ],
            // ⚠️ `managers.edit` لا `managers.view`: التبديل يستعمل كلمة سرّ
            // المدير الفرعيّ — فهو أقوى من رؤيتها ولا يقلّ عنها حرساً.
            if (switchers && Perms.has('managers.edit')) ...[
              TopActionChip(
                key: const ValueKey('top-actions-accounts'),
                icon: Icons.swap_horiz_rounded,
                label: 'accounts.title'.tr(),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const AccountsScreen()),
                ),
              ),
              SizedBox(width: gap),
            ],
            if (AiAssistantState.visible) ...[
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
            const _NotificationsChip(),
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
        );
      },
    );
  }
}

/// الجرس — والشارة كما كانت في الرئيسيّة: الإشعارات غير المقروءة + المشتركون
/// في خطر (قربوا الانتهاء + انتهوا اليوم)، رقمٌ واحد لكلّ ما يحتاج انتباهاً.
/// `AlertsService.count` يتحدّث من قائمة المشتركين ومن شاشة الإشعارات.
class _NotificationsChip extends StatelessWidget {
  const _NotificationsChip();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: InboxService.changes,
      builder: (context, _, __) => ValueListenableBuilder<int>(
        valueListenable: AlertsService.count,
        builder: (context, alerts, __) => TopActionChip(
          key: const ValueKey('top-actions-notifications'),
          icon: Icons.notifications_none_rounded,
          label: 'notifications.title'.tr(),
          badge: InboxService.unreadCount + alerts,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const InboxScreen()),
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
  static double gapOf(BuildContext context) =>
      _narrow(context) ? Sp.x6 : Sp.sm;

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
class TabHeader extends StatelessWidget {
  const TabHeader({super.key, required this.title, this.subtitle});

  final String title;

  /// سطرٌ تحت العنوان (الشركة والعدد في المشتركين، الوصف في «قوائم أخرى»).
  final Widget? subtitle;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
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
                // ⚠️ يصغر ولا يُبتر: مع «الشركات» و«الصفحات» خمسة مربّعات، وعلى
                // شاشة ٣٦٠ لا يبقى للعنوان إلّا ~٧٨ نقطة — «المشتركو…» أسوأ من
                // عنوانٍ أصغر قليلاً.
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    title,
                    maxLines: 1,
                    style: AppType.title(),
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  subtitle!,
                ],
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
