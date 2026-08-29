import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';

enum SortField {
  username,
  firstname,
  profileName,
  phone,
  expiration,
  remainingDays,
  notes,
  parentUsername,
  sessionTime, // for the 'متصل' filter — recent connects first when asc
}

enum SortDirection { asc, desc }

// النصوص هنا مفاتيح ترجمة — تُترجم عند الاستخدام.
const _fieldDefs = <(SortField, String, IconData)>[
  (SortField.username, 'sort.username', LucideIcons.user),
  (SortField.firstname, 'sort.firstname', LucideIcons.badgeCheck),
  (SortField.profileName, 'sort.package', LucideIcons.package),
  (SortField.phone, 'sort.phone', LucideIcons.phone),
  (SortField.expiration, 'sort.expiration', LucideIcons.calendar),
  (SortField.remainingDays, 'sort.remaining_days', LucideIcons.clock),
  (SortField.sessionTime, 'sort.session_time', LucideIcons.timer),
  (SortField.notes, 'sort.debts', LucideIcons.wallet),
  (SortField.parentUsername, 'sort.parent', LucideIcons.userCog),
];

/// تسمية حقل الفرز المترجَمة — يستعملها شريط النتيجة أعلى القائمة
/// ليعرض «الأيام المتبقية» بجانب سهم الاتجاه (مطابق للمخطّط).
String sortFieldLabel(SortField f) {
  for (final d in _fieldDefs) {
    if (d.$1 == f) return d.$2.tr();
  }
  return '';
}

Future<({SortField field, SortDirection direction})?> showSortSheet(
  BuildContext context, {
  required SortField currentField,
  required SortDirection currentDirection,
}) {
  return showModalBottomSheet<({SortField field, SortDirection direction})>(
    barrierColor: AppColors.scrim,
    context: context,
    backgroundColor: AppColors.surface,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(R.xl)),
    ),
    builder: (_) => _SortSheet(
      currentField: currentField,
      currentDirection: currentDirection,
    ),
  );
}

class _SortSheet extends StatefulWidget {
  const _SortSheet({
    required this.currentField,
    required this.currentDirection,
  });
  final SortField currentField;
  final SortDirection currentDirection;

  @override
  State<_SortSheet> createState() => _SortSheetState();
}

class _SortSheetState extends State<_SortSheet> {
  late SortField _field = widget.currentField;
  late SortDirection _direction = widget.currentDirection;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Sp.lg, 0, Sp.lg, Sp.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(LucideIcons.arrowDownUp, color: AppColors.brand),
                const SizedBox(width: Sp.sm),
                Text('sort.title'.tr(),
                    style: AppType.title(color: AppColors.textHi)
                        .copyWith(fontSize: 16, fontWeight: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: Sp.md),
            // Direction picker
            Row(
              children: [
                Expanded(
                  child: _DirBtn(
                    label: 'sort.asc'.tr(),
                    icon: LucideIcons.arrowUp,
                    selected: _direction == SortDirection.asc,
                    onTap: () => setState(() => _direction = SortDirection.asc),
                  ),
                ),
                const SizedBox(width: Sp.sm),
                Expanded(
                  child: _DirBtn(
                    label: 'sort.desc'.tr(),
                    icon: LucideIcons.arrowDown,
                    selected: _direction == SortDirection.desc,
                    onTap: () =>
                        setState(() => _direction = SortDirection.desc),
                  ),
                ),
              ],
            ),
            const SizedBox(height: Sp.md),
            // Field grid
            Wrap(
              spacing: Sp.sm,
              runSpacing: Sp.sm,
              children: [
                for (final d in _fieldDefs)
                  _FieldChip(
                    label: d.$2.tr(),
                    icon: d.$3,
                    selected: _field == d.$1,
                    onTap: () => setState(() => _field = d.$1),
                  ),
              ],
            ),
            const SizedBox(height: Sp.lg),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.brand,
                  padding: const EdgeInsets.symmetric(vertical: Sp.md),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(R.md),
                  ),
                ),
                onPressed: () => Navigator.of(context)
                    .pop((field: _field, direction: _direction)),
                child: Text('common.apply'.tr()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DirBtn extends StatelessWidget {
  const _DirBtn({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final color = selected ? AppColors.brand : AppColors.textMid;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(R.md),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: Sp.md),
        decoration: BoxDecoration(
          color: selected ? AppColors.brandSoftBg : AppColors.surfaceInput,
          borderRadius: BorderRadius.circular(R.md),
          border: Border.all(
            color: selected ? AppColors.brand : AppColors.border,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 16),
            const SizedBox(width: 6),
            Text(label,
                style: AppType.label(color: color).copyWith(
                  fontSize: 13, // Body tier — primary picker action
                  fontWeight: FontWeight.w700,
                )),
          ],
        ),
      ),
    );
  }
}

class _FieldChip extends StatelessWidget {
  const _FieldChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final color = selected ? AppColors.onBrand : AppColors.textMid;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(R.pill),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.brand : AppColors.surfaceInput,
          borderRadius: BorderRadius.circular(R.pill),
          border: Border.all(
            color: selected ? AppColors.brand : AppColors.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 13),
            const SizedBox(width: 6),
            Text(label,
                style: AppType.muted(color: color).copyWith(
                  fontSize: 12.5, // Card title tier
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                )),
          ],
        ),
      ),
    );
  }
}
