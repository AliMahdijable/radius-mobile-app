import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/widgets/permission_locked.dart';
import '../../services/permissions_service.dart';
import '../../services/provider_service.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import '../el/el_reports.dart';
import 'activations_report_screen.dart';
import 'activity_log_report_screen.dart';
import 'all_managers_debts_screen.dart';
import 'daily_activations_report_screen.dart';
import 'financial_report_screen.dart';
import 'sessions_report_screen.dart';
import '../../widgets/merged_company_strip.dart';
import '../desktop/desk_widgets.dart';
import '../../core/platform/desktop_layout.dart';

/// شاشة hub للتقارير — 7 كروت تنقل لكل تقرير منفصل.
/// تستبدل reports_screen.dart placeholder "تأتي قريباً".
///
/// كل كرت مرتبط بـperm حسب catalog الـbackend:
///   reports.financial / reports.activations / reports.daily_activations
///   reports.manager_debts / reports.account_statement
///   reports.sessions / reports.activity_log
///
/// 2026-09-13: المصروفات خرجت من هنا إلى «قوائم أخرى» وحدها — كانت
/// مكرّرةً في الشاشتين. وهي إدارةٌ لا تقرير (تُنشئ وتُعدّل وتحذف)،
/// فموضعها مع الوحدات لا مع التقارير التي تُقرأ فقط.
/// ManagerDebts يحوّل لصفحةٍ موجودة. AccountStatement يفتح من تفاصيل المشترك
/// لاحقاً، حالياً لا tile مستقل (مرتبط بمشترك واحد).
///
/// بلاغ 2026-10-14: الكرت بلا مفتاحه **يبقى بمكانه مقفلاً** (خافت + قفل،
/// والنقر رسالة لا تنقّل) بدل أن يختفي — إلّا مفتاحاً لا يُمنح لهذا الدور
/// ([permShown]: ديون المدراء عند موظّف ايرث لنك) فيبقى مخفيّاً.
class ReportsHubScreen extends StatelessWidget {
  const ReportsHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return ListenableBuilder(
      listenable: Listenable.merge([
        PermissionsService.changes,
        ProviderService.changes,
      ]),
      builder: (context, _) {
        final tiles = <Widget>[
          if (permShown(const ['reports.financial']))
            _ReportCard(
              locked: !Perms.has('reports.financial'),
              icon: LucideIcons.wallet,
              color: AppColors.success,
              title: 'reports.financial'.tr(),
              subtitle: 'reports.financial_hint'.tr(),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                    builder: (_) => const FinancialReportScreen()),
              ),
            ),
          if (permShown(const ['reports.activations']))
            _ReportCard(
              locked: !Perms.has('reports.activations'),
              icon: LucideIcons.zap,
              color: AppColors.brandAccent,
              title: 'reports.activations'.tr(),
              subtitle: 'reports.activations_hint'.tr(),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                    builder: (_) => const ActivationsReportScreen()),
              ),
            ),
          if (permShown(const ['reports.daily_activations']))
            _ReportCard(
              locked: !Perms.has('reports.daily_activations'),
              icon: LucideIcons.calendarDays,
              color: AppColors.brandAccent,
              title: 'reports.daily_activations'.tr(),
              subtitle: 'reports.daily_activations_hint'.tr(),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                    builder: (_) => const DailyActivationsReportScreen()),
              ),
            ),
          // ⚠️ **المصروفات ليست هنا**، وإنّما في «قوائم أخرى» وحدها.
          // كانت في الشاشتين بنفس الأيقونة والعنوان والوجهة — مدخلان
          // إلى صفحةٍ واحدة يجعلان المستخدم يظنّهما شيئين مختلفين
          // ويظلّ يبحث عن الفرق. (حُذفت من هنا بطلب صاحب المشروع.)
          if (permShown(const ['reports.manager_debts']))
            _ReportCard(
              locked: !Perms.has('reports.manager_debts'),
              icon: LucideIcons.users,
              color: AppColors.brandAccent,
              title: 'reports.manager_debts'.tr(),
              subtitle: 'reports.manager_debts_hint'.tr(),
              // 2026-07-14: كانت stub بس (رسالة "افتح من مكان ثاني").
              // بُنيت الآن كتقرير حقيقي — summary + list + فلاتر حالة.
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const AllManagersDebtsScreen(),
                ),
              ),
            ),
          if (permShown(const ['reports.sessions']))
            _ReportCard(
              locked: !Perms.has('reports.sessions'),
              icon: LucideIcons.activity,
              color: AppColors.warning,
              title: 'reports.sessions'.tr(),
              subtitle: 'reports.sessions_hint'.tr(),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SessionsReportScreen()),
              ),
            ),
          if (permShown(const ['reports.activity_log']))
            _ReportCard(
              locked: !Perms.has('reports.activity_log'),
              icon: LucideIcons.history,
              color: AppColors.success,
              title: 'reports.activity_log'.tr(),
              subtitle: 'reports.activity_log_hint'.tr(),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                    builder: (_) => const ActivityLogReportScreen()),
              ),
            ),
          // ── ايرث لنك (البند ٤) — تقاريرُ خاصّةٌ تُقرأ فقط، لموزِّعي
          // EarthLink وحدهم. الحجب من `ProviderService.isEarthlink` (مصدره
          // /api/auth/me) لا صلاحيّة ساس، فالقائمة تستمع لـ`ProviderService.changes`.
          // وكلٌّ منها بمفتاح الخادم الذي يفرضه (كانت بلا حجبٍ فيفتحها الموظّف
          // ثمّ يردّ الخادم 403): التجريبي والباقات ← activations، والسجلّ
          // ← activity_log.
          if (ProviderService.isEarthlink) ...[
            _ReportCard(
              locked: !Perms.has('reports.activations'),
              icon: LucideIcons.flaskConical,
              color: AppColors.brandAccent,
              title: 'el.test_usage_title'.tr(),
              subtitle: 'el.test_usage_hint'.tr(),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ElTestUsageScreen()),
              ),
            ),
            _ReportCard(
              locked: !Perms.has('reports.activity_log'),
              icon: LucideIcons.history,
              color: AppColors.brand,
              title: 'el.audit_title'.tr(),
              subtitle: 'el.audit_hint'.tr(),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ElAuditScreen()),
              ),
            ),
            _ReportCard(
              locked: !Perms.has('reports.activations'),
              icon: LucideIcons.package,
              color: AppColors.brand,
              title: 'el.by_package_title'.tr(),
              subtitle: 'el.by_package_hint'.tr(),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ElByPackageScreen()),
              ),
            ),
          ],
        ];

        return Scaffold(
          backgroundColor: AppColors.bg,
          appBar: deskPageBar(
            context,
            mobile: AppBar(
              backgroundColor: AppColors.surface,
              elevation: 0,
              scrolledUnderElevation: 0,
              title: Text(
                'reports.title'.tr(),
                style:
                    AppType.title(color: AppColors.textHi).copyWith(fontSize: 16),
              ),
              iconTheme: IconThemeData(color: AppColors.textHi),
            ),
          ),
          body: SafeArea(
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                  Sp.lg, DesktopScope.of(context) ? Sp.xs : Sp.lg, Sp.lg, Sp.huge),
              children: [
                // «كل الشركات»: الماليّ لكل الشركات، والبقيّة للشركة المفتوحة — تُسمّى
                const MergedOpenCompanyNote(
                  textKey: 'merged.reports_note',
                  padding: EdgeInsets.only(bottom: Sp.md),
                ),
                if (tiles.isEmpty)
                  _emptyState()
                else if (DesktopScope.of(context))
                  // الحاسبة: شبكة بطاقاتٍ بثلاثة أعمدة كالموقع بدل قائمةٍ بعرض الشاشة.
                  DeskGrid(children: tiles)
                else
                  for (int i = 0; i < tiles.length; i++) ...[
                    if (i > 0) const SizedBox(height: Sp.sm),
                    tiles[i],
                  ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _emptyState() {
    return Padding(
      padding: const EdgeInsets.only(top: Sp.huge),
      child: Center(
        child: Column(
          children: [
            Icon(LucideIcons.lock, size: 36, color: AppColors.textLow),
            const SizedBox(height: 10),
            Text(
              'reports.empty_perms'.tr(),
              style: AppType.label(color: AppColors.textMid),
            ),
            const SizedBox(height: 4),
            Text(
              'reports.empty_perms_hint'.tr(),
              style: AppType.muted().copyWith(fontSize: 12.5),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReportCard extends StatelessWidget {
  const _ReportCard({
    this.locked = false,
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

  /// بلا صلاحيّة: المقاس نفسه، ألوان [LockedStyle] (يُهمل [color])، والقفل
  /// مكان السهم، والنقر رسالةٌ لا تنقّل — فلا يُفتح تقريرٌ يردّه الخادم 403.
  final bool locked;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final desk = DesktopScope.of(context);
    final card = Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(R.lg),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: locked
            ? () => showNoPermission(context)
            : () {
                HapticFeedback.selectionClick();
                onTap();
              },
        borderRadius: BorderRadius.circular(R.lg),
        child: Container(
          padding: EdgeInsets.all(desk ? Sp.xl : Sp.md),
          constraints: BoxConstraints(minHeight: desk ? 104 : 0),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(R.lg),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Container(
                width: desk ? 48 : 44,
                height: desk ? 48 : 44,
                decoration: BoxDecoration(
                  color:
                      locked ? LockedStyle.box : color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(R.md),
                ),
                child: Icon(
                  icon,
                  color: locked ? LockedStyle.glyph : color,
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
                        fontSize: desk ? 16 : 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: AppType.muted(
                        color:
                            locked ? LockedStyle.subtitle : AppColors.textMid,
                      ).copyWith(fontSize: desk ? 13 : 11.5, height: 1.4),
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
      label: 'locked.a11y'.tr(args: [title]),
      excludeSemantics: true,
      child: card,
    );
  }
}
