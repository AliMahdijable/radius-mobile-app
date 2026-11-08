import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../api/cards_api.dart';
import '../api/jtpay_api.dart';
import '../api/national_more_api.dart';
import '../api/renew_requests_api.dart';
import '../api/sales_api.dart';
import '../api/self_deposit_api.dart';
import '../api/tickets_api.dart';
import '../core/util/format.dart';
import '../core/widgets/permission_locked.dart';
import '../services/app_resumed_signal.dart';
import '../services/permissions_service.dart';
import '../services/provider_limits.dart';
import '../models/merged_company.dart';
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
import 'national/national_money_screen.dart';
import 'national/national_notes_screen.dart';
import 'national/national_reports_screen.dart';
import 'national/national_sessions_screen.dart';
import 'national/national_map_screen.dart';
import 'national/national_team_screen.dart';
import 'national/national_tickets_screen.dart';
import 'national/national_wallet_screen.dart';
import 'national/national_work_screen.dart';
import 'packages/packages_screen.dart';
import 'portal_settings/portal_settings_screen.dart';
import 'renew/renew_requests_screen.dart';
import 'reports_screen.dart';
import 'sales/sales_screen.dart';
import 'settlements/settlements_screen.dart';
import 'subscriber_prices/subscriber_prices_screen.dart';
import 'telegram/telegram_screen.dart';
import 'tickets/tickets_screen.dart';
import 'topup/fiberx_topup_screen.dart';
import 'topup/jtpay_screen.dart';
import 'topup/topup_screen.dart';
import '../widgets/merged_section.dart';

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
    this.badge,
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

  /// عددٌ ينتظر صاحبه (غير المقروءة في «التذاكر») — رقمٌ صغير بجانب السهم. null/0 ⇒ لا شيء.
  final int? badge;

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
      // المشروع الوطنيّ: المفتاح التجريبيّ وقدرات مستخدم البوّابة — الاستماع يطلبها للوطنيّ وحده (لا نداء لغيره).
      NationalMoreState.gate,
      // «طلبات التفعيل» — المفتاح العامّ portal_renew وما يملكه المستخدم (الاستماع يطلبها).
      RenewRequestsState.gate,
      // «التذاكر» — المفتاح العامّ portal_tickets وما يملكه المستخدم وغير المقروءة (الاستماع يطلبها).
      TicketsState.gate,
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
  // المشروع الوطنيّ على providerKit (watani، ٣١ أكتوبر — المالك: «الطلبات التذاكر هاي مهمه مموجوده كذلك المواضع الي متعلقة
  // بالمالية»): أقسام البوّابة نفسها كالموقع. الموظّف بلا مفتاحها يراها مقفلةً بمكانها.
  final national = ProviderService.isKit && ProviderService.parentIsZone;
  // ١ نوفمبر — المالك: «اقسام البوابة البقية افضل تمضي بيها وتكملها»: الجلسات و«فريقي» و«تقارير البوّابة» و«الإشعارات والإعلانات»
  // خلف مفتاح أقسام البوّابة للحساب (الخادم يقول beta — وإلّا لا تظهر؛ وموظّفٌ رفض الخادم سؤاله يراها بمكانها مقفلة). ومستخدم البوّابة
  // الذي لا يملك قسماً يراه بمكانه مقفلاً بسببه («لا صلاحيّة في البوّابة») — ومنها «الإيرادات» (CanQueryRevenues) — لا شاشة «تعذّر».
  final nat = national ? NationalMoreState.gate.value : null;
  final beta = national && (nat?.shown ?? false);
  // مفاتيح أقسام البوّابة للموظّف وحده (العقد §9): صاحب الحساب لا تقفله — قدراته من الخادم تجعل reports.sessions false (كي لا يظهر
  // تقرير جلسات الساس العامّ لحساب شركةٍ مُضافة) وهي لا تخصّ «الجلسات» هنا (مراجعة ١ نوفمبر: كان المالك يرى «الجلسات» مقفلة).
  bool natLocked(List<String> keys) => Perms.isEmployee && !Perms.hasAny(keys);
  return [
    if (national && permShown(const ['subscribers.view']))
      AppModule(
        id: 'national_work',
        group: AppModuleGroup.manage,
        locked: !Perms.has('subscribers.view'),
        icon: LucideIcons.listChecks,
        tone: AppTone.warning,
        title: 'المهامّ والطلبات',
        subtitle: 'طلبات التسجيل والنقل ومهامّ التركيب في بوّابة الوطني',
        page: () => const NationalWorkScreen(),
      ),
    // «خريطة المشتركين» (٢ نوفمبر — كالموقع): المخطّط بالزونات والفاتات، ومواقعها على الخريطة والقمر الصناعيّ، والبحث
    if (national && permShown(const ['subscribers.view']))
      AppModule(
        id: 'national_map',
        group: AppModuleGroup.manage,
        locked: !Perms.has('subscribers.view'),
        icon: LucideIcons.map,
        tone: AppTone.success,
        title: 'خريطة المشتركين',
        subtitle: 'توزيع المشتركين على الزونات والفاتات، ومواقعها على الخريطة',
        page: () => const NationalMapScreen(),
      ),
    if (national && permShown(const ['subscribers.view']))
      AppModule(
        id: 'national_tickets',
        group: AppModuleGroup.manage,
        locked: !Perms.has('subscribers.view'),
        icon: LucideIcons.headset,
        tone: AppTone.info,
        title: 'التذاكر',
        subtitle: 'تذاكر الدعم في بوّابة الوطني',
        page: () => const NationalTicketsScreen(),
      ),
    if (beta)
      AppModule(
        id: 'national_sessions',
        group: AppModuleGroup.manage,
        locked: natLocked(const [NationalPerms.sessions]),
        unavailable: nat?.lockOf(const ['sessions']),
        icon: LucideIcons.activity,
        tone: AppTone.success,
        title: 'الجلسات',
        subtitle: 'المتّصلون الآن وغير المتّصلين في بوّابة الوطني',
        page: () => const NationalSessionsScreen(),
      ),
    if (beta)
      AppModule(
        id: 'national_team',
        group: AppModuleGroup.manage,
        locked: natLocked(const [NationalPerms.team]),
        unavailable: nat?.lockOf(const ['team']),
        icon: LucideIcons.usersRound,
        tone: AppTone.brand,
        title: 'فريقي',
        subtitle: 'مستخدمو حسابك في بوّابة الوطني وحدود محافظهم',
        page: () => const NationalTeamScreen(),
      ),
    // «محفظتي» قسمٌ بنفسها كالبوّابة (١ نوفمبر — المالك: حركات التفعيل لا تظهر): الرصيد والعمولة وكلّ حركات محفظتي لآخر ٣٠ يوماً،
    // و«التحويلات» حين يملكها الحساب. و«الإيرادات» (كانت «الحركات الماليّة» بتبويب «محفظتي») حركات التفعيل بكلّ طرق الدفع.
    if (national && permShown(const ['reports.financial']))
      AppModule(
        id: 'national_wallet',
        group: AppModuleGroup.finance,
        locked: !Perms.has('reports.financial'),
        icon: LucideIcons.walletCards,
        tone: AppTone.brand,
        title: 'محفظتي',
        subtitle: 'رصيدك وحركات محفظتك في بوّابة الوطني',
        page: () => const NationalWalletScreen(),
      ),
    if (national && permShown(const ['reports.financial']))
      AppModule(
        id: 'national_money',
        group: AppModuleGroup.finance,
        locked: !Perms.has('reports.financial'),
        // البوّابة تردّ 403 للإيرادات حين لا يملك المستخدم CanQueryRevenues (حساب المالك ١ نوفمبر) ⇒ بمكانها مقفلةً بسببها
        unavailable: nat?.lockOf(const ['revenue']),
        icon: LucideIcons.receiptText,
        tone: AppTone.success,
        title: 'الإيرادات',
        subtitle: 'حركات التفعيل بكلّ طرق الدفع في بوّابة الوطني',
        page: () => const NationalMoneyScreen(),
      ),
    // «المشتركون حسب الزون» من قائمتنا (لا قفل من البوّابة)، و«تقرير الجلسات» يُقفل داخل الصفحة وحده حين لا تعطيه البوّابة
    if (beta)
      AppModule(
        id: 'national_reports',
        group: AppModuleGroup.finance,
        locked: natLocked(const [NationalPerms.zonesReport, NationalPerms.sessionsReport]),
        icon: LucideIcons.chartColumn,
        tone: AppTone.info,
        title: 'تقارير البوّابة',
        subtitle: 'المشتركون الفعّالون والمنتهون لكلّ زون، وتقرير الجلسات',
        page: () => const NationalReportsScreen(),
      ),
    if (beta)
      AppModule(
        id: 'national_notes',
        group: AppModuleGroup.comms,
        locked: natLocked(const [NationalPerms.notes]),
        unavailable: nat?.lockOf(const ['notifications', 'announcements']),
        icon: LucideIcons.megaphone,
        tone: AppTone.brand,
        title: 'الإشعارات والإعلانات',
        subtitle: 'جرس بوّابة الوطني — للقراءة، لا تُعلَّم مقروءةً هناك',
        page: () => const NationalNotesScreen(),
      ),
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
        // «كل الشركات» (٨ نوفمبر): الشركة المختارة بمكانها — القائمة والإضافة والتعديل والحذف لسيرفرها (expenses_routed)
        page: ExpensesScreen.mergedPage,
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
        // «كل الشركات» (٨ نوفمبر): صندوق الشركة المختارة وتسويتها بمكانها (settlements_routed)
        page: SettlementsScreen.mergedPage,
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
        // «كل الشركات» (٨ نوفمبر): للمفتوحة وحدها — الشحن مالٌ يُضاف لرصيد صفحتها (لا يُوجَّه)
        page: () => MergedSection.openOnly(
            title: 'شحن رصيد الصفحة',
            reason: 'merged.reason_topup'.tr(),
            child: ProviderService.isFiberx ? const FiberxTopupScreen() : const TopupScreen()),
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
        page: () => MergedSection.openOnly(
            title: 'شحن من pay الجزيرة', reason: 'merged.reason_topup'.tr(), child: const JtpayScreen()),
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
        // «كل الشركات» (٨ نوفمبر): كارتات الشركة المختارة للعرض (الشراء والنقل من صفحتها) — الساس وايرث لنك (الخادم b42e0dc)
        page: () => MergedSection(
            readOnly: true,
            prefixes: const ['/api/v2/cards'],
            serves: (c) => c.provider == MergedProvider.sas4 || c.provider == MergedProvider.earthlink,
            servesNote: 'merged.serves_sas_el'.tr(),
            lockTitle: 'cards.title'.tr(),
            child: const CardsScreen()),
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
        page: () => const MergedSection(readOnly: true, prefixes: ['/api/telegram'], child: TelegramScreen()),
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
        page: () => const MergedSection(
            readOnly: true,
            prefixes: ['/api/whatsapp/broadcast', '/api/whatsapp/broadcasts', '/api/whatsapp/send-scope', '/api/v2/whatsapp'],
            child: BroadcastScreen()),
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
        page: MessageLogsScreen.mergedPage,
      ),
    // «التذاكر» (٩ نوفمبر — المالك: «للشركات كلها ما عدا الوطني»): تذاكر المشتركين من تطبيقهم — حين يُفتح المفتاح العامّ للحساب،
    // ومقفلٌ بمكانه لموظّفٍ بلا «التذاكر — العرض»، والمقيَّد بمديرٍ فرعيّ بسببه. الرقم: غير المقروءة.
    if (TicketsApi.servedByProvider && (TicketsState.gate.value?.available ?? false) && permShown(const ['tickets.view']))
      AppModule(
        id: 'tickets',
        group: AppModuleGroup.comms,
        locked: !Perms.has('tickets.view'),
        unavailable: TicketsState.gate.value!.scoped ? 'لموظّفي الحساب كلّه' : null,
        icon: LucideIcons.ticket,
        tone: AppTone.info,
        title: 'التذاكر',
        subtitle: switch (TicketsState.unread) {
          0 => 'تذاكر مشتركيك من تطبيقهم — ردّ وتابع حتى الحلّ',
          1 => 'تذكرةٌ فيها جديدٌ لم تقرأه',
          2 => 'تذكرتان فيهما جديدٌ لم تقرأه',
          final n => '$n تذاكر فيها جديدٌ لم تقرأه',
        },
        badge: TicketsState.unread,
        page: TicketsScreen.mergedPage,
      ),
    // «طلبات التفعيل» (٤ نوفمبر): طلبات تجديد المشتركين من تطبيقهم بصورة التحويل — حين يُفتح المفتاح العامّ للحساب، ومقفلٌ بمكانه
    // لموظّفٍ بلا «طلبات التفعيل»، والمقيَّد بمديرٍ فرعيّ بسببه (القسم يشمل كلّ مشتركي الحساب). الرقم: بانتظارك.
    if ((RenewRequestsState.gate.value?.access.available ?? false) && permShown(const ['renew_requests.use']))
      AppModule(
        id: 'renew_requests',
        group: AppModuleGroup.manage,
        locked: !Perms.has('renew_requests.use'),
        unavailable: RenewRequestsState.gate.value!.access.scoped ? 'لموظّفي الحساب كلّه' : null,
        icon: LucideIcons.inbox,
        tone: AppTone.warning,
        title: 'طلبات التفعيل',
        subtitle: RenewRequestsState.pending > 0
            ? '${RenewRequestsState.pending} بانتظارك — طلبات تجديد من تطبيق المشترك'
            : 'طلبات تجديد مشتركيك من تطبيقهم مع صورة التحويل',
        page: RenewRequestsScreen.mergedPage,
      ),
    // المدراء والموظّفون: مفتاحان لا يُمنحان لموظّف ايرث لنك أصلاً — مخفيّان عنده ومقفلان عند غيره.
    if (permShown(const ['managers.view']))
      AppModule(
        id: 'managers',
        group: AppModuleGroup.manage,
        locked: !Perms.has('managers.view'),
        // فايبر اكس: لا مدراء فرعيّين عندنا لحسابه بعد — بمكانه مقفلاً بالسبب لا «لا صلاحيّة». والشركة المُضافة: حساباتها
        // الفرعيّة عند مزوّدها بقدرة محوّله (managers.view) — بلاها السبب نفسه.
        unavailable: sessionIsFiberx
            ? 'غير متاح لحساب فايبر اكس بعد'
            : (sessionIsKit && !Perms.isEmployee && !Perms.has('managers.view'))
                ? 'more.kit_unavailable'.tr(namedArgs: {'name': ProviderService.label})
                : null,
        icon: LucideIcons.userCog,
        tone: AppTone.brand,
        title: 'more.managers'.tr(),
        subtitle: 'more.managers_hint'.tr(),
        page: ManagersScreen.mergedPage,
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
        // «كل الشركات»: للمفتوحة وحدها — الأسعار لكلّ شركةٍ على حدة (نطاق التسعير لا يُوجَّه)
        page: () => MergedSection.openOnly(
            title: 'more.packages'.tr(), reason: 'merged.reason_prices'.tr(), child: const PackagesScreen()),
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
        page: () => const MergedSection(readOnly: true, prefixes: ['/api/discounts', '/api/v2/discounts'], child: DiscountsScreen()),
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
        page: () => MergedSection.openOnly(
            title: 'sp.title'.tr(), reason: 'merged.reason_prices'.tr(), child: const SubscriberPricesScreen()),
      ),
    if (permShown(const ['employees.view']))
      AppModule(
        id: 'employees',
        group: AppModuleGroup.manage,
        locked: !Perms.has('employees.view'),
        // فايبر اكس (٣١ أكتوبر) والشركات المُضافة (٣٠ أكتوبر، الخادم 03cc682): موظّفونا لحسابها — مفتوحٌ كايرث لنك.
        icon: LucideIcons.users,
        tone: AppTone.brand,
        title: 'more.employees'.tr(),
        subtitle: 'more.employees_hint'.tr(),
        page: () => const MergedSection(readOnly: true, prefixes: ['/api/v2/employees'], child: EmployeesScreen()),
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
      page: PortalSettingsScreen.mergedPage,
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
          page: () => MergedSection.openOnly(
              title: 'تحويل الرصيد',
              reason: 'merged.reason_transfer'.tr(),
              serves: (c) => c.provider == MergedProvider.earthlink,
              servesNote: 'merged.serves_el'.tr(),
              child: const ElTransferScreen()),
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
          // ٨ نوفمبر (الخادم 99e1913): قراءةٌ موجَّهة لكلّ شركة ايرث لنك — غيرها «غير متاح» بسببه
          page: () => MergedSection(
              readOnly: true,
              prefixes: const ['/api/v2/el/prepaid-needed'],
              serves: (c) => c.provider == MergedProvider.earthlink,
              servesNote: 'merged.serves_el'.tr(),
              lockTitle: 'الكارتات المطلوبة',
              child: const ElRequiredCardsScreen()),
        ),
    ],
  ];
}
