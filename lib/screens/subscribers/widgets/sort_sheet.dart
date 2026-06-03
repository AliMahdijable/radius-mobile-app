import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';

enum SortField {
  username, firstname, profileName, phone, expiration, remainingDays, notes, parentUsername
}

enum SortDirection { asc, desc }

const _fieldDefs = <(SortField, String, IconData)>[
  (SortField.username, 'اسم المستخدم', LucideIcons.user),
  (SortField.firstname, 'الاسم', LucideIcons.badgeCheck),
  (SortField.profileName, 'الباقة', LucideIcons.package),
  (SortField.phone, 'رقم الهاتف', LucideIcons.phone),
  (SortField.expiration, 'تاريخ الانتهاء', LucideIcons.calendar),
  (SortField.remainingDays, 'الأيام المتبقية', LucideIcons.clock),
  (SortField.notes, 'الديون', LucideIcons.wallet),
  (SortField.parentUsername, 'تابع إلى', LucideIcons.userCog),
];

Future<({SortField field, SortDirection direction})?> showSortSheet(
  BuildContext context, {
  required SortField currentField,
  required SortDirection currentDirection,
}) {
  return showModalBottomSheet<({SortField field, SortDirection direction})>(
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
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Sp.lg, 0, Sp.lg, Sp.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(LucideIcons.arrowDownUp, color: AppColors.brand),
                const SizedBox(width: Sp.sm),
                Text('ترتيب القائمة',
                    style: AppType.title(color: AppColors.textHi)
                        .copyWith(fontSize: 16)),
              ],
            ),
            const SizedBox(height: Sp.md),
            // Direction picker
            Row(
              children: [
                Expanded(
                  child: _DirBtn(
                    label: 'تصاعدي',
                    icon: LucideIcons.arrowUp,
                    selected: _direction == SortDirection.asc,
                    onTap: () => setState(() => _direction = SortDirection.asc),
                  ),
                ),
                const SizedBox(width: Sp.sm),
                Expanded(
                  child: _DirBtn(
                    label: 'تنازلي',
                    icon: LucideIcons.arrowDown,
                    selected: _direction == SortDirection.desc,
                    onTap: () => setState(() => _direction = SortDirection.desc),
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
                    label: d.$2,
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
                child: const Text('تطبيق'),
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
    final color = selected ? AppColors.brand : AppColors.textMid;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(R.md),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: Sp.md),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.brand.withValues(alpha: 0.1)
              : AppColors.surfaceInput,
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
                  fontSize: 13,
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
    final color = selected ? Colors.white : AppColors.textMid;
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
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                )),
          ],
        ),
      ),
    );
  }
}
