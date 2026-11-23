import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../api/notifications_api.dart';
import '../../core/widgets/app_sheet.dart';
import '../../core/widgets/design_sheet.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';

/// «من موظّفيك» (المالك ٢٣ نوفمبر: «اريد بيها تخصيص يعني يخصص لاي موظف يريد يظهرله اشعاراته يحدد اكثر من واحد او واحد مستقل
/// او الكل»): من تصله عمليّاتهم من موظّفي الصفحة. نصّه في صفّ «إشعاراتي» — كالموقع (MyAlerts.tsx pickedText): الكلّ، أو اسمٌ واحد،
/// أو العدد (موظّفان / 3 موظّفين / 11 موظّفاً).
String employeeOpsPickText(List<int>? ids, List<EmployeeOpsPerson> employees) {
  if (ids == null) return 'كلّ الموظّفين';
  final names = [
    for (final e in employees)
      if (ids.contains(e.id)) e.name,
  ];
  if (names.isEmpty) return 'المختارون لم يعودوا موجودين';
  if (names.length == 1) return names.single;
  if (names.length == 2) return 'موظّفان';
  return names.length <= 10 ? '${names.length} موظّفين' : '${names.length} موظّفاً';
}

/// ورقة «من موظّفيك»: «كلّ الموظّفين» (ومن يُضاف لاحقاً) أو «موظّفون أختارهم» — واحدٌ أو أكثر. تُرجع null حين تُغلق بلا حفظ،
/// و`(ids: null)` للكلّ، و`(ids: [..])` مرتّبةً للمختارين.
Future<({List<int>? ids})?> showEmployeeOpsPickSheet(
  BuildContext context, {
  required List<EmployeeOpsPerson> employees,
  required List<int>? initial,
}) {
  return showAppSheet<({List<int>? ids})>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: AppColors.scrim,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _PickSheet(employees: employees, initial: initial),
  );
}

class _PickSheet extends StatefulWidget {
  const _PickSheet({required this.employees, required this.initial});
  final List<EmployeeOpsPerson> employees;
  final List<int>? initial;

  @override
  State<_PickSheet> createState() => _PickSheetState();
}

class _PickSheetState extends State<_PickSheet> {
  late bool _all = widget.initial == null;
  late final List<int> _picked = [
    for (final id in widget.initial ?? const <int>[])
      if (widget.employees.any((e) => e.id == id)) id,
  ];

  bool get _ready => _all || _picked.isNotEmpty;

  void _toggle(int id) => setState(() => _picked.contains(id) ? _picked.remove(id) : _picked.add(id));

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return DesignSheet(
      header: SheetHeaderBar(
        icon: LucideIcons.users,
        title: 'من موظّفيك',
        subtitle: 'عمليّات من تصلك إشعاراً',
        onClose: () => Navigator.of(context).pop(),
      ),
      footer: SheetFooterBar(
        key: const ValueKey('emp-ops-pick-save'),
        label: 'حفظ',
        icon: LucideIcons.check,
        enabled: _ready,
        onPressed: _ready ? () => Navigator.of(context).pop((ids: _all ? null : ([..._picked]..sort()))) : null,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Option(
            key: const ValueKey('emp-ops-pick-all'),
            title: 'كلّ الموظّفين',
            sub: 'ومن تضيفه لاحقاً',
            selected: _all,
            onTap: () => setState(() => _all = true),
          ),
          _Option(
            key: const ValueKey('emp-ops-pick-some'),
            title: 'موظّفون أختارهم',
            sub: 'واحدٌ أو أكثر — تصلك عمليّاتهم وحدهم',
            selected: !_all,
            onTap: () => setState(() => _all = false),
          ),
          if (!_all) ...[
            const SizedBox(height: Sp.xs),
            for (final e in widget.employees)
              _EmployeeRow(
                key: ValueKey('emp-ops-pick-${e.id}'),
                name: e.name,
                checked: _picked.contains(e.id),
                onTap: () => _toggle(e.id),
              ),
            if (_picked.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: Sp.xs),
                child: Text(
                  'اختر موظّفاً واحداً على الأقلّ',
                  style: AppType.muted(color: AppColors.textMid).copyWith(fontSize: 11.5, height: 1.5),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

/// خيار «الكلّ» / «أختارهم» — بشكل خيارات ورقة «التكرار» نفسها.
class _Option extends StatelessWidget {
  const _Option({super.key, required this.title, required this.sub, required this.selected, required this.onTap});
  final String title;
  final String sub;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Padding(
      padding: const EdgeInsets.only(bottom: Sp.sm),
      child: Material(
        color: selected ? AppColors.brandSoftBg : AppColors.surface,
        borderRadius: BorderRadius.circular(R.md),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(R.md),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: Sp.sm),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(R.md),
              border: Border.all(color: selected ? AppColors.brandSoftBorder : AppColors.border),
            ),
            child: Row(
              children: [
                Icon(selected ? LucideIcons.circleCheck : LucideIcons.circle,
                    size: 18, color: selected ? AppColors.brand : AppColors.textHint),
                const SizedBox(width: Sp.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: AppType.label(color: AppColors.textHi).copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: Sp.xxs),
                      Text(sub, style: AppType.muted(color: AppColors.textMid).copyWith(fontSize: 11.5, height: 1.4)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// موظّفٌ بمربّع اختيار — الاسم يلتفّ ولا يُقصّ.
class _EmployeeRow extends StatelessWidget {
  const _EmployeeRow({super.key, required this.name, required this.checked, required this.onTap});
  final String name;
  final bool checked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Padding(
      padding: const EdgeInsets.only(bottom: Sp.x6),
      child: Material(
        color: checked ? AppColors.brandSoftBg : AppColors.surface,
        borderRadius: BorderRadius.circular(R.md),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(R.md),
          child: Container(
            constraints: const BoxConstraints(minHeight: 44),
            padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: Sp.x6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(R.md),
              border: Border.all(color: checked ? AppColors.brandSoftBorder : AppColors.border),
            ),
            child: Row(
              children: [
                Icon(checked ? LucideIcons.squareCheck : LucideIcons.square,
                    size: 18, color: checked ? AppColors.brand : AppColors.textHint),
                const SizedBox(width: Sp.sm),
                Expanded(
                  child: Text(name, style: AppType.label(color: AppColors.textHi).copyWith(fontWeight: FontWeight.w600, height: 1.35)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
