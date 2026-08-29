import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../services/permissions_service.dart';
import '../theme/colors.dart';
import '../theme/spacing.dart';
import '../theme/typography.dart';
import 'broadcast/broadcast_screen.dart';
import 'telegram/telegram_screen.dart';
import 'discounts/discounts_screen.dart';
import 'message_logs/message_logs_screen.dart';
import 'employees/employees_screen.dart';
import 'expenses/expenses_screen.dart';
import 'managers/managers_screen.dart';
import 'packages/packages_screen.dart';
import 'portal_settings/portal_settings_screen.dart';
import 'reports_screen.dart';

/// Other modules — مطلب 2026-06-10: الـtab السفلي السابق "الضبط"
/// انتقل لاسم "قوائم أخرى" ويعرض المديولات الإضافية (الصرفيات،
/// المدراء، تسعير الباقات، إلخ). شاشة الإعدادات الفعلية انتقلت
/// لزر الـgear في الشريط العلوي على Home.
///
/// كل بطاقة هنا stub حالياً (snack 'قيد التطوير') حتى نبني كل
/// مديول واحد واحد. الفكرة: المدير يفتح هذا الـtab فيشوف فهرس
/// واضح لما هو متاح ولما هو قادم.
class MoreModulesScreen extends StatelessWidget {
  const MoreModulesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    // مطلب 2026-06-11: الكروت تختفي حسب صلاحيات الموظف الحالي.
    // لو ما عنده ولا صلاحية يظهر empty state بدل قائمة فارغة بدون
    // سياق. الـadmin (مو موظف) يشوف كل الكروت دائماً.
    return ValueListenableBuilder<int>(
      valueListenable: PermissionsService.changes,
      builder: (context, _, __) {
        final cards = <Widget>[
          // مطلب 2026-08-12: التقارير صارت أوّل عنصر (نُقلت من tab رئيسي
          // لأن أجهزة الشبكة أكثر استعمالاً يومياً للـWISP).
          // تظهر لأي مدير عادي، وللموظّف لو عنده أي صلاحيّة reports.*
          if (Perms.hasAny([
            'reports.financial',
            'reports.activations',
            'reports.daily_activations',
            'reports.expenses',
            'reports.manager_debts',
            'reports.account_statement',
            'reports.sessions',
            'reports.activity_log',
          ]))
            _ModuleCard(
              icon: LucideIcons.chartLine,
              color: AppColors.success,
              title: 'nav.reports'.tr(),
              subtitle: 'more.reports_hint'.tr(),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ReportsScreen()),
              ),
            ),
          if (Perms.has('reports.expenses'))
            _ModuleCard(
              icon: LucideIcons.receipt,
              color: AppColors.warning,
              title: 'more.expenses'.tr(),
              subtitle: 'more.expenses_hint'.tr(),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const ExpensesScreen(),
                ),
              ),
            ),
          // 2026-08-26: تلغرام — إعداد بوت + ربط مشتركين + بث. منقول
          // كامل من client-v2. محكوم بنفس صلاحيّة إعدادات الواتساب.
          if (Perms.hasAny(
              ['whatsapp.broadcast', 'whatsapp.send', 'settings.edit']))
            _ModuleCard(
              icon: LucideIcons.send,
              color: const Color(0xFF229ED9),
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
          if (Perms.has('whatsapp.broadcast'))
            _ModuleCard(
              icon: LucideIcons.bell,
              color: const Color(0xFF25D366),
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
          if (Perms.hasAny(['whatsapp.broadcast', 'whatsapp.send']))
            _ModuleCard(
              icon: LucideIcons.messageSquare,
              color: AppColors.brandAccent,
              title: 'more.message_logs'.tr(),
              subtitle: 'more.message_logs_hint'.tr(),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const MessageLogsScreen(),
                ),
              ),
            ),
          if (Perms.has('managers.view'))
            _ModuleCard(
              icon: LucideIcons.userCog,
              color: AppColors.brandAccent,
              title: 'more.managers'.tr(),
              subtitle: 'more.managers_hint'.tr(),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const ManagersScreen(),
                ),
              ),
            ),
          if (Perms.hasAny(['packages.view', 'packages.edit_prices']))
            _ModuleCard(
              icon: LucideIcons.package,
              color: AppColors.brandAccent,
              title: 'more.packages'.tr(),
              subtitle: 'more.packages_hint'.tr(),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const PackagesScreen(),
                ),
              ),
            ),
          if (Perms.has('discounts.view'))
            _ModuleCard(
              icon: LucideIcons.percent,
              color: AppColors.success,
              title: 'more.discounts'.tr(),
              subtitle: 'more.discounts_hint'.tr(),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const DiscountsScreen(),
                ),
              ),
            ),
          if (Perms.has('employees.view'))
            _ModuleCard(
              icon: LucideIcons.users,
              color: AppColors.brandAccent,
              title: 'more.employees'.tr(),
              subtitle: 'more.employees_hint'.tr(),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const EmployeesScreen(),
                ),
              ),
            ),
          // بوابة المشترك — 2026-07-13: branding + وصف الباقات (نُقلت من client-v2)
          if (Perms.has('settings.edit'))
            _ModuleCard(
              icon: LucideIcons.smartphone,
              color: AppColors.brand,
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
        ];

        return Scaffold(
          backgroundColor: AppColors.bg,
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.lg, Sp.lg, Sp.huge),
              children: [
                Text(
                  'more.title'.tr(),
                  style: AppType.title(color: AppColors.textHi).copyWith(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'more.subtitle'.tr(),
                  style: AppType.subtitle(color: AppColors.textMid),
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
                            style: AppType.muted().copyWith(fontSize: 12),
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
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(R.lg),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
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
                  color: color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(R.md),
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(width: Sp.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: AppType.label(color: AppColors.textHi).copyWith(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: AppType.muted(color: AppColors.textMid)
                          .copyWith(fontSize: 11.5, height: 1.4),
                    ),
                  ],
                ),
              ),
              Icon(LucideIcons.chevronLeft, color: AppColors.textLow, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}
