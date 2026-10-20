import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../api/cards_api.dart';
import '../api/self_deposit_api.dart';
import '../core/util/format.dart';
import '../core/widgets/permission_locked.dart';
import '../services/ai_assistant_state.dart';
import '../services/app_resumed_signal.dart';
import '../services/permissions_service.dart';
import '../services/provider_service.dart';
import '../theme/colors.dart';
import '../theme/spacing.dart';
import '../theme/typography.dart';
import 'broadcast/broadcast_screen.dart';
import 'cards/cards_screen.dart';
import 'el/required_cards_screen.dart';
import 'el/transfer_screen.dart';
import 'telegram/telegram_screen.dart';
import 'discounts/discounts_screen.dart';
import 'subscriber_prices/subscriber_prices_screen.dart';
import 'message_logs/message_logs_screen.dart';
import 'employees/employees_screen.dart';
import 'expenses/expenses_screen.dart';
import 'settlements/settlements_screen.dart';
import 'managers/managers_screen.dart';
import 'packages/packages_screen.dart';
import 'portal_settings/portal_settings_screen.dart';
import 'assistant/assistant_sheet.dart';
import 'reports_screen.dart';
import 'top_actions.dart';
import 'topup/topup_screen.dart';

/// Other modules — مطلب 2026-06-10: الـtab السفلي السابق "الضبط"
/// انتقل لاسم "قوائم أخرى" ويعرض المديولات الإضافية (الصرفيات،
/// المدراء، تسعير الباقات، إلخ). شاشة الإعدادات الفعلية انتقلت
/// لزر الـgear في الشريط العلوي على Home — ومنذ ٢٠ أكتوبر في أزرار الأعلى
/// المشتركة بكلّ التبويبات، وهذه منها ([TabHeader]).
///
/// كل بطاقة هنا stub حالياً (snack 'قيد التطوير') حتى نبني كل
/// مديول واحد واحد. الفكرة: المدير يفتح هذا الـtab فيشوف فهرس
/// واضح لما هو متاح ولما هو قادم.
class MoreModulesScreen extends StatelessWidget {
  const MoreModulesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    // بلاغ 2026-10-14: الكروت **لا تختفي** بالصلاحيّة — تبقى بمكانها مقفلةً
    // (خافتة + قفل مكان السهم، والنقر يقول «اطلبها من مديرك» ولا يفتح شيئاً)
    // فتحافظ القائمة على شكلها. ويبقى مخفيّاً ما ليس صلاحيّة: ميزةٌ لا يدعمها
    // المزوّد، أو لصاحب الحساب وحده، أو مفتاحٌ لا يُمنح لهذا الدور
    // ([permShown] — مدراء/موظّفون عند موظّف ايرث لنك). الـadmin يرى كلّ
    // الكروت مفتوحةً دائماً، و«لا صلاحيّات» احتياطٌ لقائمةٍ فارغة فقط.
    // §١٢: وشارة الكارتات أيضاً — «الكارتات» تظهر وتختفي معها بلا إعادة فتح.
    return ListenableBuilder(
      listenable: Listenable.merge([
        PermissionsService.changes,
        CardsState.badge,
        ProviderService.changes,
        // «شحن رصيد الصفحة» — الاستماع نفسه يطلب حالتها إن كانت قديمة.
        SelfDepositState.gate,
        // «كيف أسوّي؟» (المساعد الذكيّ) — مطفأٌ افتراضيّاً، يُسأل عند الاستماع.
        AiAssistantState.gate,
        // العودة للتطبيق ⇒ يُسأل ثانيةً (بمهلته) — فتشغيله من الخادم يظهر.
        AppResumedSignal.tick,
      ]),
      builder: (context, _) {
        // «كيف أسوّي؟»: الشاشة تبقى حيّةً طول الجلسة (IndexedStack) فالاستماع
        // يسأل مرّةً وحدها — وأوّل سؤالٍ فشل، أو شُغّل المساعد بعده، يُعرف هنا
        // (مهلة ٥ دقائق وتبريد ٣٠ث بعد الفشل: طلبٌ واحد على الأكثر).
        scheduleMicrotask(AiAssistantState.ensureFresh);
        final stock = CardsState.badge.value;
        const rk = [
          'reports.financial',
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
        // موظّف ايرث لنك: تلغرام (البوت والربط والبثّ) لصاحب الحساب ما لم
        // يوجد مفتاحٌ صريح — كالويب (`/telegram` ownerOnly). `whatsapp.send`
        // عنده ضمنيٌّ يتبع «إرسال واتساب» ([ElEmployeePerms.outgoing]) لا
        // مفتاحٌ صريح، فلا يفتحه؛ والباقيان لا يُمنحان له اليوم ⇒ مخفيّ
        // ([permShown]). يظهر وحده لو صار أحدهما ممّا يُمنح.
        final tgGate = ProviderService.isEarthlink && Perms.isEmployee
            ? const ['whatsapp.broadcast', 'settings.edit']
            : tgKeys;
        const logKeys = ['whatsapp.broadcast', 'whatsapp.send'];
        const pkgKeys = ['packages.view', 'packages.edit_prices'];
        final cardsLocked = !Perms.hasAny(cardKeys);
        final cards = <Widget>[
          // ١٨ أكتوبر: «كيف أسوّي؟» — المساعد الذكيّ (يشرح ويرشد، بلا أيّ
          // عمليّة). أوّل البطاقات حين يقول الخادم إنّه مفتوحٌ لهذا الحساب
          // (مطفأٌ افتراضيّاً ⇒ لا بطاقة ولا قفل). وموظّفٌ بلا «المساعد الذكي»
          // يراها بمكانها مقفلةً — والنقر رسالةٌ بلا أيّ طلب.
          if (AiAssistantState.visible)
            _ModuleCard(
              locked: AiAssistantState.askLocked,
              icon: LucideIcons.sparkles,
              tone: AppTone.brand,
              title: 'ai.ask_entry'.tr(),
              subtitle: 'ai.ask_hint_card'.tr(),
              onTap: () => AssistantSheet.showAsk(context),
            ),
          // مطلب 2026-08-12: التقارير صارت أوّل عنصر (نُقلت من tab رئيسي
          // لأن أجهزة الشبكة أكثر استعمالاً يومياً للـWISP).
          // مفتوحةٌ لأي مدير عادي، وللموظّف لو عنده أي صلاحيّة reports.*،
          // وإلّا فمقفلة بمكانها.
          if (permShown(rk))
            _ModuleCard(
              locked: !Perms.hasAny(rk),
              icon: LucideIcons.chartLine,
              tone: AppTone.success,
              title: 'nav.reports'.tr(),
              subtitle: 'more.reports_hint'.tr(),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ReportsScreen()),
              ),
            ),
          if (permShown(const ['reports.expenses']))
            _ModuleCard(
              locked: !Perms.has('reports.expenses'),
              icon: LucideIcons.receipt,
              tone: AppTone.warning,
              title: 'more.expenses'.tr(),
              subtitle: 'more.expenses_hint'.tr(),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const ExpensesScreen(),
                ),
              ),
            ),
          // 2026-10-02: «تسوية الحساب» — صندوق المدير بجانب الصرفيات، فهي
          // إدارةٌ تُنشئ سندات لا تقريرٌ يُقرأ فقط (كالصرفيات تماماً).
          if (permShown(const ['settlements.view']))
            _ModuleCard(
              locked: !Perms.has('settlements.view'),
              icon: LucideIcons.handCoins,
              tone: AppTone.brand,
              title: 'more.settlements'.tr(),
              subtitle: 'more.settlements_hint'.tr(),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const SettlementsScreen(),
                ),
              ),
            ),
          // ١٨ أكتوبر: «شحن رصيد الصفحة» — الإيداع الذاتيّ في الساس (زين كاش
          // وكارتات التعبئة). يظهر حين يقول الخادم إنّ الميزة مفتوحة لهذا
          // الحساب (مفتاحٌ مطفأ افتراضيّاً) — فلا يتغيّر شيءٌ لمن لم تُفتح له.
          // وما لا يُتاح يبقى بمكانه مقفلاً **بسببه** لا بـ«اطلبها من مديرك»:
          // الموظّف (لصاحب الحساب وحده)، ايرث لنك والمشروع الوطنيّ (المزوّد
          // بلا شحن)، صفحةٌ بلا «ايداع مالي» في الساس، أو شركةٌ بلا وسائل دفع.
          if (SelfDepositState.visible)
            _ModuleCard(
              unavailable: topupCardLock(SelfDepositState.gate.value!),
              icon: LucideIcons.banknoteArrowUp,
              tone: AppTone.success,
              title: 'شحن رصيد الصفحة',
              // «متوقّفٌ مؤقّتاً»: البطاقة مفتوحة لسجلّ العمليّات و«تحقّق» وحدهما.
              subtitle: SelfDepositState.gate.value!.block ==
                      SelfDepositBlock.paused
                  ? 'متوقّف مؤقّتاً — تابِع عمليّاتك التي لم تُحسم'
                  : 'زين كاش أو كارت تعبئة — يُضاف لرصيد صفحتك بالساس',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const TopupScreen()),
              ),
            ),
          // §١٢ «الكارتات» — مخزون كارتات التعبئة، بجانب المال لأنّه مالٌ
          // مدفوعٌ سلفاً. ⚠️ لا مفتاح صلاحيّة في التطبيق: صلاحيّات الساس
          // (`prm_users_activate_card` · `prm_cards_*`) لا تصل الموبايل،
          // فالخادم يقول `enabled` في admin-widgets والبطاقة تتبعه. ومجهولة
          // الشارة (لم يردّ أحد بعد) لا تُظهرها — لا قسم يقول «لا كارتات»
          // لمن لا يعمل بها أصلاً.
          // والموظّف يفتحه بصلاحيّة التفعيل/التمديد وحدها (مثل نافذة التفعيل)،
          // وبدونها يراه مقفلاً بلا عدد المخزون (رقمٌ لا يملك أن يراه).
          if ((stock?.enabled ?? false) && permShown(cardKeys))
            _ModuleCard(
              locked: cardsLocked,
              icon: LucideIcons.tickets,
              tone: AppTone.brand,
              title: 'cards.title'.tr(),
              // ايرث لنك بلا سلاسل: مخزونها بالباقة وحدها.
              subtitle: cardsLocked || stock!.remaining == null
                  ? (ProviderService.isEarthlink
                          ? 'cards.module_hint_pkg'
                          : 'cards.module_hint')
                      .tr()
                  : (ProviderService.isEarthlink
                          ? 'cards.module_hint_pkg_n'
                          : 'cards.module_hint_n')
                      .tr(namedArgs: {'n': formatIQD(stock.remaining!)}),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const CardsScreen()),
              ),
            ),
          // 2026-08-26: تلغرام — إعداد بوت + ربط مشتركين + بث. منقول
          // كامل من client-v2. محكوم بنفس صلاحيّة إعدادات الواتساب.
          if (permShown(tgGate))
            _ModuleCard(
              locked: !Perms.hasAny(tgGate),
              icon: LucideIcons.send,
              tone: AppTone.brand,
              brandGlyph: AppColors.channelTelegram, // أزرق تلغرام
              title: 'تلغرام',
              subtitle: 'ربط بوت + إشعارات المشتركين عبر تلغرام',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const TelegramScreen(),
                ),
              ),
            ),
          // التبليغات (broadcast) — نُقلت من client-v2/Notifications.tsx.
          // إرسال جماعي لجميع/المدينين/المنتهين/قرب انتهاء + محرّر متغيّرات.
          // لكلّ الشركات: مستلمو ايرث لنك من مصدر مشتركيها على الخادم (كلّ
          // الصفحات)، والقفل من `whatsapp.broadcast` في خريطة الخادم كغيره.
          // وموظّف ايرث لنك لا يراها ([permShown]: البثّ لا يُمنح له).
          if (permShown(const ['whatsapp.broadcast']))
            _ModuleCard(
              locked: !Perms.has('whatsapp.broadcast'),
              icon: LucideIcons.bell,
              tone: AppTone.brand,
              brandGlyph: AppColors.channelWhatsApp, // أخضر واتساب
              title: 'more.broadcast'.tr(),
              subtitle: 'more.broadcast_hint'.tr(),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const BroadcastScreen(),
                ),
              ),
            ),
          // حالة الرسائل — نُقلت من v1 mobile-app/message_logs_screen. تعرض
          // كل رسائل WhatsApp بأنواعها (broadcast/activation/expiry/…) مع
          // فلاتر + بحث + retry + auto-refresh للـpending.
          if (permShown(logKeys))
            _ModuleCard(
              locked: !Perms.hasAny(logKeys),
              icon: LucideIcons.messageSquare,
              tone: AppTone.brand,
              title: 'more.message_logs'.tr(),
              subtitle: 'more.message_logs_hint'.tr(),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const MessageLogsScreen(),
                ),
              ),
            ),
          // المدراء والموظّفون: مفتاحان لا يُمنحان لموظّف ايرث لنك أصلاً،
          // فيبقيان مخفيّين عنده ([permShown]) ومقفلين عند غيره.
          if (permShown(const ['managers.view']))
            _ModuleCard(
              locked: !Perms.has('managers.view'),
              icon: LucideIcons.userCog,
              tone: AppTone.brand,
              title: 'more.managers'.tr(),
              subtitle: 'more.managers_hint'.tr(),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const ManagersScreen(),
                ),
              ),
            ),
          if (permShown(pkgKeys))
            _ModuleCard(
              locked: !Perms.hasAny(pkgKeys),
              icon: LucideIcons.package,
              tone: AppTone.brand,
              title: 'more.packages'.tr(),
              subtitle: 'more.packages_hint'.tr(),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const PackagesScreen(),
                ),
              ),
            ),
          if (permShown(const ['discounts.view']))
            _ModuleCard(
              locked: !Perms.has('discounts.view'),
              icon: LucideIcons.percent,
              tone: AppTone.success,
              title: 'more.discounts'.tr(),
              subtitle: 'more.discounts_hint'.tr(),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const DiscountsScreen(),
                ),
              ),
            ),
          // «أسعار المشتركين» — سعر بيعٍ ثابت لمشتركٍ بعينه، بجانب الخصومات
          // لأنّه أخوها: الثابت يلغي الخصم.
          if (permShown(const ['subscriber_prices.view']))
            _ModuleCard(
              locked: !Perms.has('subscriber_prices.view'),
              icon: LucideIcons.banknote,
              tone: AppTone.brand,
              title: 'sp.title'.tr(),
              subtitle: 'sp.module_hint'.tr(),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const SubscriberPricesScreen(),
                ),
              ),
            ),
          if (permShown(const ['employees.view']))
            _ModuleCard(
              locked: !Perms.has('employees.view'),
              icon: LucideIcons.users,
              tone: AppTone.brand,
              title: 'more.employees'.tr(),
              subtitle: 'more.employees_hint'.tr(),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const EmployeesScreen(),
                ),
              ),
            ),
          // بوابة المشترك — 2026-07-13: branding + وصف الباقات (نُقلت من client-v2)
          // ١٨ أكتوبر (وسيط البوّابة): + «رمز الوكيل» الذي يدخل به المشترك
          // تطبيق MyServices. البطاقة **مفتوحةٌ لكلّ فاعل**: الرمز يحتاجه
          // الموظّف أيضاً (والخادم يعطيه بلا صلاحيّة — رمز مديره)، والتخصيص
          // داخلها بـ`settings.edit` مقفلٌ بمكانه. ولكلّ المزوّدين — ايرث لنك
          // صارت تُخدَم؛ وFTTH وحده بمكانه مقفلاً بالسبب («غير متوفّرة لشركتك
          // بعد») لا مخفيّاً (تدقيق البوّابة ٢٠٢٦-١٠-١٧ §2.7).
          _ModuleCard(
            unavailable: ProviderService.hasSubscriberPortal
                ? null
                : 'portal.unavailable_company'.tr(),
            icon: LucideIcons.smartphone,
            tone: AppTone.brand,
            title: 'portal.title'.tr(),
            subtitle: 'portal.subtitle_more'.tr(),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const PortalSettingsScreen(),
              ),
            ),
          ),
          // 2026-08-26: 'الصفحات' لها زر مخصّص جنب جرس الإشعارات فقط
          // (طلب المستخدم — إزالة من قوائم أخرى). Import يبقى للـroute
          // من dashboard.
          // 2026-08-12: الأجهزة انتقلت لـtab رئيسي (استعمالها يومي للـWISP)
          // ── ايرث لنك (البند ٤) — تظهران لموزِّعي EarthLink وحدهم.
          // الحجب من `ProviderService.isEarthlink` (مصدره /api/auth/me)،
          // لا صلاحيّة ساس — فالقائمة تستمع لـ`ProviderService.changes`.
          if (ProviderService.isEarthlink) ...[
            // تحويل الرصيد وكشف الإيداع لصاحب الحساب وحده (الخادم يردّ الموظّف
            // بـ403 OWNER_ONLY) — فلا تُعرض للموظّف بطاقةٌ تنتهي برفض.
            if (!Perms.isEmployee)
            _ModuleCard(
              icon: LucideIcons.arrowRightLeft,
              tone: AppTone.brand,
              title: 'تحويل الرصيد',
              subtitle: 'تحويل الرصيد بين الوكلاء + كشف الحساب',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ElTransferScreen()),
              ),
            ),
            // «طلب الكارتات» من ايرث لنك أُلغي نهائيّاً (قرار المالك ١٩ أكتوبر):
            // لا بطاقة ولا شاشة — والخادم يردّ مساراته «طلب الكروت غير متاح».
            // «الكارتات المطلوبة» — توقّع الكارتات والرصيد (بكلفة الشركة)
            // لمدّة؛ بلا أسعار بيع (تلك بشاشة الباقات). من «التقارير الماليّة»
            // (المدير دائماً؛ الموظّف بالمفتاح — الخادم يفرضه).
            if (permShown(const ['reports.financial']))
            _ModuleCard(
              locked: !Perms.has('reports.financial'),
              icon: LucideIcons.clipboardList,
              tone: AppTone.brand,
              title: 'الكارتات المطلوبة',
              subtitle: 'كم كارتاً ورصيداً تحتاج ليوم / ٣ أيام / أسبوع / شهر',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                    builder: (_) => const ElRequiredCardsScreen()),
              ),
            ),
          ],
        ];

        return Scaffold(
          backgroundColor: AppColors.bg,
          body: SafeArea(
            child: ListView(
              // ‎8 تحت الشقّ: أزرار الأعلى في موضعها من الرئيسيّة نفسه.
              padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.sm, Sp.lg, Sp.huge),
              children: [
                // ٢٠ أكتوبر: رأس التبويب الموحّد — العنوان والوصف يميناً، وأزرار
                // الأعلى المشتركة (المساعد · الجرس · الترس) يساراً. وبطاقة «كيف
                // أسوّي؟» تحته باقيةٌ كما هي.
                TabHeader(
                  title: 'more.title'.tr(),
                  subtitle: Text(
                    'more.subtitle'.tr(),
                    style: AppType.subtitle(color: AppColors.textMid),
                  ),
                ),
                const SizedBox(height: Sp.lg),
                if (cards.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: Sp.huge),
                    child: Center(
                      child: Column(
                        children: [
                          Icon(LucideIcons.lock,
                              size: 36, color: AppColors.textLow),
                          const SizedBox(height: 10),
                          Text(
                            'more.empty_perms'.tr(),
                            style: AppType.label(color: AppColors.textMid),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'more.empty_perms_hint'.tr(),
                            style: AppType.muted().copyWith(fontSize: 12.5),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  for (int i = 0; i < cards.length; i++) ...[
                    if (i > 0) const SizedBox(height: Sp.sm),
                    cards[i],
                  ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ModuleCard extends StatelessWidget {
  const _ModuleCard({
    this.locked = false,
    this.unavailable,
    required this.icon,
    required this.tone,
    this.brandGlyph,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  final IconData icon;

  /// نغمة دلاليّة لا لون: الخلفيّة والأيقونة تأتيان من اللوحة معاً،
  /// فلا اشتقاق بشفافيّة لا يعرف الوضع الليلي.
  final AppTone tone;

  /// لون علامة طرف ثالث للأيقونة وحدها (أخضر واتساب · أزرق تلغرام).
  /// المربّع خلفه يبقى محايداً — هويّة القناة في الرمز لا في السطح،
  /// وصبغ السطح بلون خارجي يكسر اللوحة ولا يعرف الوضع الليلي.
  final Color? brandGlyph;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  /// بلا صلاحيّة: المقاس والمكان نفسهما، الألوان خافتة ([LockedStyle])
  /// والقفل مكان السهم، والنقر رسالةٌ لا تنقّل ([showNoPermission]).
  final bool locked;

  /// ميزةٌ لا تملكها الشركة بعد (لا صلاحيّةٌ ناقصة): الشكل المقفل نفسه،
  /// والسبب مكان الوصف وفي رسالة النقر بدل «اطلبها من مديرك». يتقدّم على
  /// [locked] — فلا صلاحيّة تفتح ما لا وجود له.
  final String? unavailable;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final locked = this.locked || unavailable != null;
    final card = Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(R.lg),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: locked
            ? () => showNoPermission(context, message: unavailable)
            : () {
                HapticFeedback.selectionClick();
                onTap();
              },
        borderRadius: BorderRadius.circular(R.lg),
        child: Container(
          padding: const EdgeInsets.fromLTRB(Sp.md, Sp.md, Sp.md, Sp.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(R.lg),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: locked
                      ? LockedStyle.box
                      : brandGlyph == null
                          ? tone.softBg
                          : AppColors.surfaceSunken,
                  borderRadius: BorderRadius.circular(R.icon),
                ),
                child: Icon(
                  icon,
                  color: locked ? LockedStyle.glyph : brandGlyph ?? tone.fill,
                  size: 22,
                ),
              ),
              const SizedBox(width: Sp.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: AppType.label(
                        color: locked ? LockedStyle.title : AppColors.textHi,
                      ).copyWith(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      unavailable ?? subtitle,
                      style: AppType.muted(
                        color:
                            locked ? LockedStyle.subtitle : AppColors.textMid,
                      ).copyWith(fontSize: 11.5, height: 1.4),
                    ),
                  ],
                ),
              ),
              if (locked)
                const PermLockIcon()
              else
                Icon(LucideIcons.chevronLeft,
                    color: AppColors.textLow, size: 18),
            ],
          ),
        ),
      ),
    );
    if (!locked) return card;
    return Semantics(
      button: true,
      label: unavailable == null
          ? 'locked.a11y'.tr(args: [title])
          : '$title — $unavailable',
      excludeSemantics: true,
      child: card,
    );
  }
}
