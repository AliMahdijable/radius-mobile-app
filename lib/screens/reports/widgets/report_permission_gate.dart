import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../services/merged_mode.dart';
import '../../../services/permissions_service.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';
import '../../desktop/desk_widgets.dart';

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
    this.companyKey,
  });

  final String permission;
  final String title;
  final Widget child;

  /// صفحة ما يعرضه التقرير («كل الصفحات» للموظّف — مراجعة 179): كشف حساب مشترك صفحةٍ أخرى وسجلّ جلساته يُطلبان من صفحته
  /// وبصلاحيّاته هناك ([MergedMode.can]) لا بصلاحيّات صفحته المفتوحة (`Perms.has`). null، والمالك، وخادمٌ بلا خرائط ⇒ Perms.has
  /// كما كان حرفاً.
  final String? companyKey;

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    // نعيد البناء حين تتغيّر الصلاحيات في-الجلسة، أو خرائط الصفحات («كل الصفحات»).
    return ListenableBuilder(
      listenable: Listenable.merge([PermissionsService.changes, MergedMode.data]),
      builder: (context, _) {
        if (MergedMode.can(companyKey, permission)) return child;
        // رفض صفحةٍ بخريطتها ⇒ يُسمّيها (صلاحيّته هناك غيرها هنا)
        final page = MergedMode.pagePerm(companyKey, permission) == false ? MergedMode.companyOf(companyKey) : null;
        return Scaffold(
          backgroundColor: AppColors.bg,
          appBar: deskPageBar(
            context,
            mobile: AppBar(
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
                        color: AppColors.dangerSoftBg,
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
                      page != null
                          ? MergedMode.deniedText(page)
                          : 'reports.no_permission_hint'.tr(namedArgs: {'perm': permission}),
                      textAlign: TextAlign.center,
                      style:
                          AppType.muted().copyWith(fontSize: 12.5, height: 1.6),
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
