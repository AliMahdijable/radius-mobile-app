import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../services/permissions_service.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';

/// حماية دفاعية للشاشات: يفحص إذا الـuser عنده الصلاحية المطلوبة.
/// لو لا → يعرض شاشة "لا صلاحية" مع زر رجوع.
///
/// الـhub التقارير أصلاً يخفي التايلات المحظورة، لكن هذي طبقة أمان إضافية
/// لو صار deep-link أو تغيير صلاحيات في-الجلسة.
class ReportPermissionGate extends StatelessWidget {
  const ReportPermissionGate({
    super.key,
    required this.permission,
    required this.title,
    required this.child,
  });

  final String permission;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    // نبني ValueListenable حتى لو الصلاحيات تغيّرت في-الجلسة نُعيد البناء.
    return ValueListenableBuilder<int>(
      valueListenable: PermissionsService.changes,
      builder: (context, _, __) {
        if (Perms.has(permission)) return child;
        return Scaffold(
          backgroundColor: AppColors.bg,
          appBar: AppBar(
            backgroundColor: AppColors.surface,
            elevation: 0,
            scrolledUnderElevation: 0,
            title: Text(
              title,
              style:
                  AppType.title(color: AppColors.textHi).copyWith(fontSize: 16),
            ),
            iconTheme: IconThemeData(color: AppColors.textHi),
          ),
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(Sp.xl),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: AppColors.error.withValues(alpha: 0.10),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(LucideIcons.lock,
                          size: 28, color: AppColors.error),
                    ),
                    const SizedBox(height: Sp.md),
                    Text(
                      'reports.no_permission'.tr(),
                      style: AppType.title(color: AppColors.textHi)
                          .copyWith(fontSize: 14),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'reports.no_permission_hint'
                          .tr(namedArgs: {'perm': permission}),
                      textAlign: TextAlign.center,
                      style:
                          AppType.muted().copyWith(fontSize: 12, height: 1.6),
                    ),
                    const SizedBox(height: Sp.lg),
                    ElevatedButton.icon(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(LucideIcons.chevronRight, size: 16),
                      label: Text('common.back'.tr()),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
