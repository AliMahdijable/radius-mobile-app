import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../api/cards_api.dart';
import '../api/jtpay_api.dart';
import '../api/sales_api.dart';
import '../api/self_deposit_api.dart';
import '../core/util/format.dart';
import '../core/widgets/permission_locked.dart';
import '../services/app_resumed_signal.dart';
import '../services/permissions_service.dart';
import '../services/provider_limits.dart';
import '../services/provider_service.dart';
import '../theme/colors.dart';
import 'broadcast/broadcast_screen.dart';
import 'cards/cards_screen.dart';
import 'discounts/discounts_screen.dart';
import 'el/required_cards_screen.dart';
import 'el/transfer_screen.dart';
import 'employees/employees_screen.dart';
import 'expenses/expenses_screen.dart';
import 'managers/managers_screen.dart';
import 'message_logs/message_logs_screen.dart';
import 'packages/packages_screen.dart';
import 'portal_settings/portal_settings_screen.dart';
import 'reports_screen.dart';
import 'sales/sales_screen.dart';
import 'settlements/settlements_screen.dart';
import 'subscriber_prices/subscriber_prices_screen.dart';
import 'telegram/telegram_screen.dart';
import 'topup/fiberx_topup_screen.dart';
import 'topup/jtpay_screen.dart';
import 'topup/topup_screen.dart';

/// مجموعات القائمة الجانبيّة على الحاسبة — بترتيب الموقع (nav-config.ts).
enum AppModuleGroup { manage, finance, comms, customize, earthlink }

/// قسمٌ من «قوائم أخرى» كبيانات — مصدرٌ واحد لبطاقات الهاتف ولقائمة الحاسبة الجانبيّة، فالقفل
/// والإخفاء ([permShown]، المزوّد، مفاتيح الخادم) لا يُكتبان مرّتين.
class AppModule {
  const AppModule({
    required this.id,
    required this.group,
    required this.icon,
    required this.tone,
    required this.title,
    required this.subtitle,
    required this.page,
    this.brandGlyph,
    this.locked = false,
    this.unavailable,
  });

  final String id;
  final AppModuleGroup group;
  final IconData icon;
  final AppTone tone;

  /// لون علامة طرف ثالث للأيقونة وحدها (أخضر واتساب · أزرق تلغرام).
  final Color? brandGlyph;
  final String title;
  final String subtitle;
  final Widget Function() page;

  /// بلا صلاحيّة: بمكانه مقفلاً، والنقر رسالةٌ لا تنقّل.
  final bool locked;

  /// ميزةٌ لا تملكها الشركة (لا صلاحيّةٌ ناقصة) — السبب مكان الوصف. يتقدّم على [locked].
  final String? unavailable;

  bool get isLocked => locked || unavailable != null;
}

/// ما تتغيّر به القائمة: الصلاحيّات، شارة الكارتات، المزوّد، حالة الشحن والمبيعات، العودة للتطبيق.
Listenable appModulesListenable() => Listenable.merge([
      PermissionsService.changes,
      CardsState.badge,
      ProviderService.changes,
      // «شحن رصيد الصفحة» — الاستماع نفسه يطلب حالتها إن كانت قديمة.
      SelfDepositState.gate,
      // «المبيعات» — الاستماع يطلب حالتها إن كانت قديمة (مفتاحٌ بالخادم).
      SalesState.gate,
      // «شحن من pay الجزيرة» — لشركات الجزيرة وحدها (لا سؤال لغيرها).
      JtpayState.gate,
      // العودة للتطبيق ⇒ يُسأل ثانيةً (بمهلته) — فتشغيله من الخادم يظهر.
      AppResumedSignal.tick,
    ]);

/// الأقسام بترتيب الهاتف («قوائم أخرى»). الحاسبة ترتّبها بمجموعاتها.
List<AppModule> buildAppModules() {
  final stock = CardsState.badge.value;
  const rk = [
    'reports.financial',
    'reports.packages',
    'reports.activations',
    'reports.daily_activations',
    'reports.expenses',
    'reports.manager_debts',
    'reports.account_statement',
    'reports.sessions',
    'reports.activity_log',
  ];
  const cardKeys = ['subscribers.activate', 'subscribers.extend'];
  const tgKeys = ['whatsapp.broadcast', 'whatsapp.send', 'settings.edit'];
  // موظّف ايرث لنك: تلغرام (البوت والربط والبثّ) لصاحب الحساب ما لم يوجد مفتاحٌ صريح — كالويب
  // (`/telegram` ownerOnly). `whatsapp.send` عنده ضمنيٌّ يتبع «إرسال واتساب» لا مفتاحٌ صريح.
  final tgGate = ProviderService.isEarthlink && Perms.isEmployee
      ? const ['whatsapp.broadcast', 'settings.edit']
      : tgKeys;
  const logKeys = ['whatsapp.broadcast', 'whatsapp.send'];
  const pkgKeys = ['packages.view', 'packages.edit_prices'];
  final cardsLocked = !Perms.hasAny(cardKeys);
  return [
    // «كيف أسوّي؟» صار زرّاً في الأعلى بكلّ التبويبات (TopActions) — لا بطاقة هنا (المالك ٢٠ أكتوبر).
    // مطلب 2026-08-12: التقارير صارت أوّل عنصر. مفتوحةٌ لأي مدير عادي، وللموظّف لو عنده أي
    // صلاحيّة reports.*، وإلّا فمقفلة بمكانها.
    if (permShown(rk))
      AppModule(
        id: 'reports',
        group: AppModuleGroup.finance,
        locked: !Perms.hasAny(rk),
        icon: LucideIcons.chartLine,
        tone: AppTone.success,
        title: 'nav.reports'.tr(),
        subtitle: 'more.reports_hint'.tr(),
        page: () => const ReportsScreen(),
      ),
    if (permShown(const ['reports.expenses']))
      AppModule(
        id: 'expenses',
        group: AppModuleGroup.finance,
        locked: !Perms.has('reports.expenses'),
        icon: LucideIcons.receipt,
        tone: AppTone.warning,
        title: 'more.expenses'.tr(),
        subtitle: 'more.expenses_hint'.tr(),
        page: () => const ExpensesScreen(),
      ),
    // 2026-10-02: «تسوية الحساب» — صندوق المدير بجانب الصرفيات، فهي إدارةٌ تُنشئ سندات.
    if (permShown(const ['settlements.view']))
      AppModule(
        id: 'settlements',
        group: AppModuleGroup.finance,
        locked: !Perms.has('settlements.view'),
        icon: LucideIcons.handCoins,
        tone: AppTone.brand,
        title: 'more.settlements'.tr(),
        subtitle: 'more.settlements_hint'.tr(),
        page: () => const SettlementsScreen(),
      ),
    // ٢٣ أكتوبر: «المبيعات» — موادّ الوكيل ومخزونه وبيعها نقداً أو على دين المشترك. تظهر حين يقول الخادم إنّها
    // مفتوحةٌ للحساب (مفتاحٌ مطفأ افتراضيّاً)؛ الموظّف بلا `sales.view` يراها مقفلةً بمكانها، والمقيَّد بمديرٍ فرعيّ بسببها.
    if (SalesState.visible && permShown(const ['sales.view']))
      AppModule(
        id: 'sales',
        group: AppModuleGroup.finance,
        locked: !Perms.has('sales.view'),
        unavailable: SalesState.gate.value!.scoped ? 'sales.scoped'.tr() : null,
        icon: LucideIcons.shoppingCart,
        tone: AppTone.success,
        title: 'sales.title'.tr(),
        subtitle: 'sales.module_hint'.tr(),
        page: () => const SalesScreen(),
      ),
    // ١٨ أكتوبر: «شحن رصيد الصفحة» — يظهر حين يقول الخادم إنّ الميزة مفتوحة لهذا الحساب، وما لا
    // يُتاح يبقى بمكانه مقفلاً **بسببه** (الموظّف، ايرث لنك، الوطنيّ، صفحةٌ بلا إيداع، بلا وسائل).
    if (SelfDepositState.visible)
      AppModule(
        id: 'topup',
        group: AppModuleGroup.finance,
        unavailable: topupCardLock(SelfDepositState.gate.value!),
        icon: LucideIcons.banknoteArrowUp,
        tone: AppTone.success,
        title: 'شحن رصيد الصفحة',
        // «متوقّفٌ مؤقّتاً»: البطاقة مفتوحة لسجلّ العمليّات و«تحقّق» وحدهما.
        subtitle: ProviderService.isFiberx
            ? 'زين كاش أو كي كارد — يُضاف لمحفظة فايبر اكس'
            : SelfDepositState.gate.value!.block == SelfDepositBlock.paused
                ? 'متوقّف مؤقّتاً — تابِع عمليّاتك التي لم تُحسم'
                : 'زين كاش أو كارت تعبئة — يُضاف لرصيد صفحتك بالساس',
        page: () => ProviderService.isFiberx
            ? const FiberxTopupScreen()
            : const TopupScreen(),
      ),
    // ٣٠ أكتوبر: «شحن من pay الجزيرة» — لوكلاء شركة الجزيرة (jt لاسلكي / ftth فايبر) حين يقول الخادم إنّها
    // مفتوحة لحسابهم: تعبئة رصيد pay بزين كاش أو بطاقة ثمّ تحويله لصفحتهم بالساس أو لصفحة ثانية. الموظّف
    // يراها بمكانها مقفلةً بسببها. الهاتف وحده (صفحة الدفع تحتاج WebView يلتقط الرجوع).
    if (JtpayState.visible)
      AppModule(
        id: 'jtpay',
        group: AppModuleGroup.finance,
        unavailable: JtpayState.gate.value!.ownerOnly ? 'لصاحب الصفحة فقط — اطلبه من مديرك' : null,
        icon: LucideIcons.walletCards,
        tone: AppTone.success,
        title: 'شحن من pay الجزيرة',
        subtitle: JtpayState.gate.value!.paused
            ? 'متوقّف مؤقّتاً — تابِع عمليّاتك التي لم تُحسم'
            : 'زين كاش أو بطاقة ← رصيد pay ← صفحتك بالساس',
        page: () => const JtpayScreen(),
      ),
    // §١٢ «الكارتات» — مخزون كارتات التعبئة. الخادم يقول `enabled` في admin-widgets والبطاقة تتبعه،
    // ومجهولة الشارة لا تُظهرها. الموظّف يفتحه بصلاحيّة التفعيل/التمديد وحدها.
    if ((stock?.enabled ?? false) && permShown(cardKeys))
      AppModule(
        id: 'cards',
        group: AppModuleGroup.manage,
        locked: cardsLocked,
        icon: LucideIcons.tickets,
        tone: AppTone.brand,
        title: 'cards.title'.tr(),
        // ايرث لنك بلا سلاسل: مخزونها بالباقة وحدها.
        subtitle: cardsLocked || stock!.remaining == null
            ? (ProviderService.isEarthlink ? 'cards.module_hint_pkg' : 'cards.module_hint').tr()
            : (ProviderService.isEarthlink ? 'cards.module_hint_pkg_n' : 'cards.module_hint_n')
                .tr(namedArgs: {'n': formatIQD(stock.remaining!)}),
        page: () => const CardsScreen(),
      ),
    // 2026-08-26: تلغرام — إعداد بوت + ربط مشتركين + بث. محكوم بنفس صلاحيّة إعدادات الواتساب.
    if (permShown(tgGate))
      AppModule(
        id: 'telegram',
        group: AppModuleGroup.comms,
        locked: !Perms.hasAny(tgGate),
        icon: LucideIcons.send,
        tone: AppTone.brand,
        brandGlyph: AppColors.channelTelegram,
        title: 'تلغرام',
        subtitle: 'ربط بوت + إشعارات المشتركين عبر تلغرام',
        page: () => const TelegramScreen(),
      ),
    // التبليغات (broadcast) — إرسال جماعي لجميع/المدينين/المنتهين/قرب انتهاء. موظّف ايرث لنك لا يراها.
    if (permShown(const ['whatsapp.broadcast']))
      AppModule(
        id: 'broadcast',
        group: AppModuleGroup.comms,
        locked: !Perms.has('whatsapp.broadcast'),
        icon: LucideIcons.bell,
        tone: AppTone.brand,
        brandGlyph: AppColors.channelWhatsApp,
        title: 'more.broadcast'.tr(),
        subtitle: 'more.broadcast_hint'.tr(),
        page: () => const BroadcastScreen(),
      ),
    // حالة الرسائل — كل رسائل WhatsApp بأنواعها مع فلاتر + بحث + retry.
    if (permShown(logKeys))
      AppModule(
        id: 'message_logs',
        group: AppModuleGroup.comms,
        locked: !Perms.hasAny(logKeys),
        icon: LucideIcons.messageSquare,
        tone: AppTone.brand,
        title: 'more.message_logs'.tr(),
        subtitle: 'more.message_logs_hint'.tr(),
        page: () => const MessageLogsScreen(),
      ),
    // المدراء والموظّفون: مفتاحان لا يُمنحان لموظّف ايرث لنك أصلاً — مخفيّان عنده ومقفلان عند غيره.
    if (permShown(const ['managers.view']))
      AppModule(
        id: 'managers',
        group: AppModuleGroup.manage,
        locked: !Perms.has('managers.view'),
        // فايبر اكس: لا مدراء فرعيّين عندنا لحسابه بعد — بمكانه مقفلاً بالسبب لا «لا صلاحيّة».
        unavailable: sessionIsFiberx ? 'غير متاح لحساب فايبر اكس بعد' : null,
        icon: LucideIcons.userCog,
        tone: AppTone.brand,
        title: 'more.managers'.tr(),
        subtitle: 'more.managers_hint'.tr(),
        page: () => const ManagersScreen(),
      ),
    if (permShown(pkgKeys))
      AppModule(
        id: 'packages',
        group: AppModuleGroup.manage,
        locked: !Perms.hasAny(pkgKeys),
        icon: LucideIcons.package,
        tone: AppTone.brand,
        title: 'more.packages'.tr(),
        subtitle: 'more.packages_hint'.tr(),
        page: () => const PackagesScreen(),
      ),
    if (permShown(const ['discounts.view']))
      AppModule(
        id: 'discounts',
        group: AppModuleGroup.manage,
        locked: !Perms.has('discounts.view'),
        icon: LucideIcons.percent,
        tone: AppTone.success,
        title: 'more.discounts'.tr(),
        subtitle: 'more.discounts_hint'.tr(),
        page: () => const DiscountsScreen(),
      ),
    // «أسعار المشتركين» — سعر بيعٍ ثابت لمشتركٍ بعينه، بجانب الخصومات لأنّه أخوها.
    if (permShown(const ['subscriber_prices.view']))
      AppModule(
        id: 'subscriber_prices',
        group: AppModuleGroup.manage,
        locked: !Perms.has('subscriber_prices.view'),
        icon: LucideIcons.banknote,
        tone: AppTone.brand,
        title: 'sp.title'.tr(),
        subtitle: 'sp.module_hint'.tr(),
        page: () => const SubscriberPricesScreen(),
      ),
    if (permShown(const ['employees.view']))
      AppModule(
        id: 'employees',
        group: AppModuleGroup.manage,
        locked: !Perms.has('employees.view'),
        unavailable: sessionIsFiberx ? 'غير متاح لحساب فايبر اكس بعد' : null,
        icon: LucideIcons.users,
        tone: AppTone.brand,
        title: 'more.employees'.tr(),
        subtitle: 'more.employees_hint'.tr(),
        page: () => const EmployeesScreen(),
      ),
    // بوابة المشترك — مفتوحةٌ لكلّ فاعل (الرمز يحتاجه الموظّف أيضاً)، والتخصيص داخلها بـ`settings.edit`.
    // الوطنيّ وحده بمكانه مقفلاً بالسبب.
    AppModule(
      id: 'portal',
      group: AppModuleGroup.customize,
      unavailable: ProviderService.hasSubscriberPortal ? null : 'portal.unavailable_company'.tr(),
      icon: LucideIcons.smartphone,
      tone: AppTone.brand,
      title: 'portal.title'.tr(),
      subtitle: 'portal.subtitle_more'.tr(),
      page: () => const PortalSettingsScreen(),
    ),
    // ── ايرث لنك — لموزِّعي EarthLink وحدهم (من `ProviderService.isEarthlink`، لا صلاحيّة ساس).
    if (ProviderService.isEarthlink) ...[
      // تحويل الرصيد وكشف الإيداع لصاحب الحساب وحده (الخادم يردّ الموظّف بـ403 OWNER_ONLY).
      if (!Perms.isEmployee)
        AppModule(
          id: 'el_transfer',
          group: AppModuleGroup.earthlink,
          icon: LucideIcons.arrowRightLeft,
          tone: AppTone.brand,
          title: 'تحويل الرصيد',
          subtitle: 'تحويل الرصيد بين الوكلاء + كشف الحساب',
          page: () => const ElTransferScreen(),
        ),
      // «الكارتات المطلوبة» — توقّع الكارتات والرصيد لمدّة؛ من «التقارير الماليّة».
      if (permShown(const ['reports.financial']))
        AppModule(
          id: 'el_required_cards',
          group: AppModuleGroup.earthlink,
          locked: !Perms.has('reports.financial'),
          icon: LucideIcons.clipboardList,
          tone: AppTone.brand,
          title: 'الكارتات المطلوبة',
          subtitle: 'كم كارتاً ورصيداً تحتاج ليوم / ٣ أيام / أسبوع / شهر',
          page: () => const ElRequiredCardsScreen(),
        ),
    ],
  ];
}
