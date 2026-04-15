import 'package:flutter/material.dart';
import '../widgets/loading_overlay.dart';

class ManagersScreen extends StatelessWidget {
  const ManagersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const EmptyState(
      icon: Icons.admin_panel_settings_outlined,
      title: 'المدراء',
      subtitle: 'قريباً — إدارة المدراء والصلاحيات',
    );
  }
}
