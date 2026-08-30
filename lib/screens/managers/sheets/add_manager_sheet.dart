import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../api/managers_api.dart';
import '../../../theme/colors.dart';
import '_manager_form.dart';

/// إنشاء مدير فرعي جديد. الـform موحّد بين add/edit في
/// _manager_form.dart، يفرّق فقط الـsubmit + العنوان.
Future<bool?> showAddManagerSheet(BuildContext context) {
  return showModalBottomSheet<bool>(
    barrierColor: AppColors.scrim,
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => const _AddManagerSheet(),
  );
}

class _AddManagerSheet extends StatelessWidget {
  const _AddManagerSheet();

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return ManagerFormSheet(
      title: 'مدير جديد',
      subtitle: 'إضافة مدير فرعي',
      icon: LucideIcons.userPlus,
      accent: AppColors.brandAccent,
      submitLabel: 'إنشاء',
      requirePassword: true,
      onSubmit: (data) async {
        if (data.aclGroupId == null) {
          return (ok: false, message: 'اختر مجموعة الصلاحيات');
        }
        final r = await ManagersApi.create(
          username: data.username,
          password: data.password,
          aclGroupId: data.aclGroupId!,
          firstname: data.firstname,
          lastname: data.lastname,
          mobile: data.mobile,
          email: data.email,
          parentId: data.parentId,
          enabled: data.enabled,
        );
        return (ok: r.ok, message: r.message);
      },
    );
  }
}
