import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../api/managers_api.dart';
import '_manager_form.dart';
import '../../../theme/colors.dart';

/// تعديل مدير قائم. كلمة السر اختيارية (تترك فاضية = لا تغيير).
Future<bool?> showEditManagerSheet(BuildContext context, Manager m) {
  return showModalBottomSheet<bool>(
    barrierColor: AppColors.scrim,
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _EditManagerSheet(manager: m),
  );
}

class _EditManagerSheet extends StatelessWidget {
  const _EditManagerSheet({required this.manager});
  final Manager manager;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return ManagerFormSheet(
      title: 'تعديل مدير',
      subtitle: manager.username,
      icon: LucideIcons.userCog,
      accent: AppColors.brandAccent,
      submitLabel: 'حفظ',
      requirePassword: false,
      initial: ManagerFormInitial(
        username: manager.username,
        firstname: manager.firstname,
        lastname: manager.lastname,
        mobile: manager.mobile,
        email: manager.email,
        aclGroupId: manager.aclId,
        parentId: manager.parentId,
        enabled: manager.isActive,
      ),
      onSubmit: (data) async {
        final r = await ManagersApi.update(
          id: manager.id,
          username: data.username,
          password: data.password.isEmpty ? null : data.password,
          firstname: data.firstname,
          lastname: data.lastname,
          mobile: data.mobile,
          email: data.email,
          aclGroupId: data.aclGroupId,
          enabled: data.enabled,
        );
        return (ok: r.ok, message: r.message);
      },
    );
  }
}
