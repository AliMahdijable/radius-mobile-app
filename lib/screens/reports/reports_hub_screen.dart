import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../services/permissions_service.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import '../expenses/expenses_screen.dart';
import 'activations_report_screen.dart';
import 'activity_log_report_screen.dart';
import 'all_managers_debts_screen.dart';
import 'daily_activations_report_screen.dart';
import 'financial_report_screen.dart';
import 'sessions_report_screen.dart';

/// شاشة hub للتقارير — 8 كروت تنقل لكل تقرير منفصل.
/// تستبدل reports_screen.dart placeholder "تأتي قريباً".
///
/// كل كرت مرتبط بـperm حسب catalog الـbackend:
///   reports.financial / reports.activations / reports.daily_activations
///   reports.expenses / reports.manager_debts / reports.account_statement
///   reports.sessions / reports.activity_log
///
/// Expenses + ManagerDebts يحوّلان للصفحات الموجودة فعلاً
/// (لا داعي لـduplication). AccountStatement يفتح من تفاصيل المشترك
/// لاحقاً، حالياً لا tile مستقل (مرتبط بمشترك واحد).
class ReportsHubScreen extends StatelessWidget {
  const ReportsHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return ValueListenableBuilder<int>(
      valueListenable: PermissionsService.changes,
      builder: (context, _, __) {
        final tiles = <Widget>[
          if (Perms.has('reports.financial'))
            _ReportCard(
              icon: LucideIcons.wallet,
              color: const Color(0xFF14B8A6),
              title: 'reports.financial'.tr(),
              subtitle: 'reports.financial_hint'.tr(),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const FinancialReportScreen()),
              ),
            ),
          if (Perms.has('reports.activations'))
            _ReportCard(
              icon: LucideIcons.zap,
              color: const Color(0xFF3B82F6),
              title: 'reports.activations'.tr(),
              subtitle: 'reports.activations_hint'.tr(),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ActivationsReportScreen()),
              ),
            ),
          if (Perms.has('reports.daily_activations'))
            _ReportCard(
              icon: LucideIcons.calendarDays,
              color: const Color(0xFF8B5CF6),
              title: 'reports.daily_activations'.tr(),
              subtitle: 'reports.daily_activations_hint'.tr(),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const DailyActivationsReportScreen()),
              ),
            ),
          if (Perms.has('reports.expenses'))
            _ReportCard(
              icon: LucideIcons.receipt,
              color: const Color(0xFFE08F2D),
              title: 'reports.expenses'.tr(),
              subtitle: 'reports.expenses_hint'.tr(),
              // ExpensesScreen موجودة فعلاً — نُحوّل لها.
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ExpensesScreen()),
              ),
            ),
          if (Perms.has('reports.manager_debts'))
            _ReportCard(
              icon: LucideIcons.users,
              color: const Color(0xFF0EA5E9),
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
          if (Perms.has('reports.sessions'))
            _ReportCard(
              icon: LucideIcons.activity,
              color: const Color(0xFFCD8B00),
              title: 'reports.sessions'.tr(),
              subtitle: 'reports.sessions_hint'.tr(),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SessionsReportScreen()),
              ),
            ),
          if (Perms.has('reports.activity_log'))
            _ReportCard(
              icon: LucideIcons.history,
              color: const Color(0xFF26A69A),
              title: 'reports.activity_log'.tr(),
              subtitle: 'reports.activity_log_hint'.tr(),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ActivityLogReportScreen()),
              ),
            ),
        ];

        return Scaffold(
          backgroundColor: AppColors.bg,
          appBar: AppBar(
            backgroundColor: AppColors.surface,
            elevation: 0,
            scrolledUnderElevation: 0,
            title: Text(
              'reports.title'.tr(),
              style: AppType.title(color: AppColors.textHi).copyWith(fontSize: 16),
            ),
            iconTheme: IconThemeData(color: AppColors.textHi),
          ),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.lg, Sp.lg, Sp.huge),
              children: [
                if (tiles.isEmpty)
                  _emptyState()
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
              style: AppType.muted().copyWith(fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReportCard extends StatelessWidget {
  const _ReportCard({
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
          padding: const EdgeInsets.all(Sp.md),
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
              Icon(LucideIcons.chevronLeft,
                  color: AppColors.textLow, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

