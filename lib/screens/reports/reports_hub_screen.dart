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
              title: 'التقرير المالي',
              subtitle: 'الإيرادات + الديون + المصاريف',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const FinancialReportScreen()),
              ),
            ),
          if (Perms.has('reports.activations'))
            _ReportCard(
              icon: LucideIcons.zap,
              color: const Color(0xFF3B82F6),
              title: 'التفعيلات',
              subtitle: 'كل تفعيلات الفترة (نقدي/غير نقدي)',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ActivationsReportScreen()),
              ),
            ),
          if (Perms.has('reports.daily_activations'))
            _ReportCard(
              icon: LucideIcons.calendarDays,
              color: const Color(0xFF8B5CF6),
              title: 'التفعيلات اليومية',
              subtitle: 'مجموع يومي + إيراد لكل يوم',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const DailyActivationsReportScreen()),
              ),
            ),
          if (Perms.has('reports.expenses'))
            _ReportCard(
              icon: LucideIcons.receipt,
              color: const Color(0xFFE08F2D),
              title: 'الصرفيات',
              subtitle: 'سجل + إضافة + تعديل المصاريف',
              // ExpensesScreen موجودة فعلاً — نُحوّل لها.
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ExpensesScreen()),
              ),
            ),
          if (Perms.has('reports.manager_debts'))
            _ReportCard(
              icon: LucideIcons.users,
              color: const Color(0xFF0EA5E9),
              title: 'ديون المدراء',
              subtitle: 'ديون مخصّصة على المدراء الفرعيين',
              // CustomDebtsScreen يحتاج managerId — نستعمل null
              // للوضع "الكل" (الـscreen يدعم all-managers mode).
              // ملاحظة: لو الـconstructor تتطلب param، نلف بصفحة
              // اختيار مدير. للآن نمرر اختصار "all".
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const _AllManagersDebtsRouter(),
                ),
              ),
            ),
          if (Perms.has('reports.sessions'))
            _ReportCard(
              icon: LucideIcons.activity,
              color: const Color(0xFFCD8B00),
              title: 'الجلسات',
              subtitle: 'المتصلون + سجل الجلسات',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SessionsReportScreen()),
              ),
            ),
          if (Perms.has('reports.activity_log'))
            _ReportCard(
              icon: LucideIcons.history,
              color: const Color(0xFF26A69A),
              title: 'سجل النشاط',
              subtitle: 'كل العمليات + من نفّذها',
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
              'التقارير',
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
              'ليس لديك صلاحيات لأي تقرير',
              style: AppType.label(color: AppColors.textMid),
            ),
            const SizedBox(height: 4),
            Text(
              'اتصل بالمدير العام لمنحك صلاحيات تقارير',
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

/// Shim مؤقت — CustomDebtsScreen تحتاج managerId. الـall-managers view
/// غير منفّذ كصفحة منفصلة بعد. حالياً نعرض رسالة + رابط لشاشة المدراء.
class _AllManagersDebtsRouter extends StatelessWidget {
  const _AllManagersDebtsRouter();

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        title: Text('ديون المدراء',
            style: AppType.title(color: AppColors.textHi).copyWith(fontSize: 16)),
        iconTheme: IconThemeData(color: AppColors.textHi),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(Sp.xl),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(LucideIcons.info, size: 36, color: AppColors.textLow),
              const SizedBox(height: 10),
              Text(
                'افتح المدير المطلوب من صفحة "المدراء" → "ديون أخرى" لعرض ديونه المخصّصة.',
                textAlign: TextAlign.center,
                style: AppType.subtitle(color: AppColors.textMid)
                    .copyWith(height: 1.6),
              ),
              const SizedBox(height: Sp.lg),
              ElevatedButton.icon(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(LucideIcons.chevronRight, size: 16),
                label: const Text('رجوع'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

