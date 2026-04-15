import 'package:flutter/material.dart';
import '../widgets/loading_overlay.dart';

class ReportsScreen extends StatelessWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const EmptyState(
      icon: Icons.assessment_outlined,
      title: 'التقارير',
      subtitle: 'قريباً — التقارير المالية وكشوفات الحساب',
    );
  }
}
