import 'package:flutter/material.dart';

import '../theme/colors.dart';
import '../theme/spacing.dart';
import '../theme/typography.dart';

class ReportsScreen extends StatelessWidget {
  const ReportsScreen({super.key});

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
                child: const Icon(Icons.insert_chart_rounded,
                    color: AppColors.brand, size: 32),
              ),
              const SizedBox(height: Sp.xl),
              Text('التقارير',
                  style: AppType.title(color: AppColors.textHi)),
              const SizedBox(height: Sp.sm),
              Text(
                'التقارير المالية والتشغيلية — تأتي قريباً.',
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
