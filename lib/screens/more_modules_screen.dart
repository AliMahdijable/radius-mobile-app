import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../theme/colors.dart';
import '../theme/spacing.dart';
import '../theme/typography.dart';

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
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.lg, Sp.lg, Sp.huge),
          children: [
            Text(
              'قوائم أخرى',
              style: AppType.title(color: AppColors.textHi).copyWith(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'المديولات الإضافية للنظام',
              style: AppType.subtitle(color: AppColors.textMid),
            ),
            const SizedBox(height: Sp.lg),
            _ModuleCard(
              icon: LucideIcons.receipt,
              color: const Color(0xFFE08F2D),
              title: 'الصرفيات',
              subtitle: 'تسجيل ومتابعة المصاريف',
              onTap: () => _todo(context, 'الصرفيات — قيد التطوير'),
            ),
            const SizedBox(height: Sp.sm),
            _ModuleCard(
              icon: LucideIcons.userCog,
              color: const Color(0xFF3B82F6),
              title: 'المدراء',
              subtitle: 'إدارة المدراء الفرعيين',
              onTap: () => _todo(context, 'المدراء — قيد التطوير'),
            ),
            const SizedBox(height: Sp.sm),
            _ModuleCard(
              icon: LucideIcons.package,
              color: const Color(0xFF8B5CF6),
              title: 'تسعير الباقات',
              subtitle: 'تعديل أسعار البيع لكل باقة',
              onTap: () => _todo(context, 'تسعير الباقات — قيد التطوير'),
            ),
            const SizedBox(height: Sp.sm),
            _ModuleCard(
              icon: LucideIcons.percent,
              color: const Color(0xFF14B8A6),
              title: 'الخصومات',
              subtitle: 'إدارة الخصومات لكل مشترك',
              onTap: () => _todo(context, 'الخصومات — قيد التطوير'),
            ),
          ],
        ),
      ),
    );
  }

  static void _todo(BuildContext ctx, String msg) {
    ScaffoldMessenger.of(ctx).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: AppColors.textHi,
        behavior: SnackBarBehavior.floating,
      ),
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
                      style: AppType.label(color: AppColors.textHi)
                          .copyWith(
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
              const Icon(LucideIcons.chevronLeft,
                  color: AppColors.textLow, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}
