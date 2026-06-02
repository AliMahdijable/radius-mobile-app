import 'package:flutter/material.dart';

import '../theme/colors.dart';
import '../theme/spacing.dart';
import '../theme/typography.dart';

/// Placeholder for the subscribers list tab. Real content comes next.
class SubscribersScreen extends StatelessWidget {
  const SubscribersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return _Placeholder(
      icon: Icons.people_alt_rounded,
      title: 'المشتركون',
      body: 'قائمة المشتركين مع البحث والفلاتر — تأتي في الجلسة القادمة.',
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(Sp.xxl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: AppColors.brand.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(R.lg),
                ),
                alignment: Alignment.center,
                child: Icon(icon, color: AppColors.brand, size: 32),
              ),
              const SizedBox(height: Sp.xl),
              Text(title, style: AppType.title(color: AppColors.textHi)),
              const SizedBox(height: Sp.sm),
              Text(
                body,
                textAlign: TextAlign.center,
                style: AppType.subtitle(color: AppColors.textMid)
                    .copyWith(height: 1.6),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
