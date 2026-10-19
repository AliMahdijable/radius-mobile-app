import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../core/widgets/design_sheet.dart';
import '../../../core/widgets/permission_locked.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';

/// صفّ مفتاحٍ في «بوابة المشترك» — مفتاح البوّابة ومفاتيح ما يظهر للمشتركين
/// بشكلٍ واحد: إطارٌ فيه أيقونةٌ بلون الحالة، وعنوانٌ وتلميحه، والمفتاح.
///
/// مقفلاً ([locked]) لمن لا يملك `settings.edit`: الحالة حبّةً ([stateLabel]
/// بنغمة [tone]) والقفل مكان المفتاح، والنقر لـ[onLockedTap] — فيعرف الموظّف
/// الحالة ولا يقدر يبدّلها (المقفل لا المخفيّ). و[busy] دوّارةٌ مكان المفتاح
/// أثناء الحفظ.
class PortalSwitchTile extends StatelessWidget {
  const PortalSwitchTile({
    super.key,
    required this.title,
    required this.hint,
    required this.icon,
    required this.tone,
    required this.stateLabel,
    required this.value,
    required this.busy,
    required this.locked,
    required this.onChanged,
    required this.onLockedTap,
  });

  final String title;

  /// سطرٌ تحت العنوان يقول ما تعنيه الحالة الحاليّة.
  final String hint;

  /// أيقونة الحالة الحاليّة.
  final IconData icon;

  /// نغمة الحالة الحاليّة — مربّع الأيقونة، وحبّة المقفل.
  final AppTone tone;

  /// الحالة بكلمة («مفعّلة»، «يظهر») — تُرى في المقفل وحده.
  final String stateLabel;

  final bool value;
  final bool busy;
  final bool locked;
  final ValueChanged<bool> onChanged;
  final VoidCallback onLockedTap;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final row = Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.lg),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: locked ? LockedStyle.box : tone.softBg,
              borderRadius: BorderRadius.circular(R.sm),
            ),
            child: Icon(
              icon,
              size: 18,
              color: locked ? LockedStyle.glyph : tone.fill,
            ),
          ),
          const SizedBox(width: Sp.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.rowValue(
                      color: locked ? LockedStyle.title : AppColors.textHi),
                ),
                const SizedBox(height: Sp.xxs),
                Text(
                  hint,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.muted(
                      color: locked ? LockedStyle.subtitle : AppColors.textMid),
                ),
              ],
            ),
          ),
          const SizedBox(width: Sp.sm),
          if (locked) ...[
            ToneChip(label: stateLabel, tone: tone, dense: true),
            const SizedBox(width: Sp.x6),
            const PermLockIcon(),
          ] else if (busy)
            const SizedBox(
              width: 52,
              height: 32,
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else
            Switch(
              value: value,
              onChanged: onChanged,
              activeThumbColor: AppColors.onBrand,
              activeTrackColor: AppColors.brand,
            ),
        ],
      ),
    );
    // المفتاح وتسميته عنصرٌ واحد لقارئ الشاشة (كـSwitchListTile).
    if (!locked) return MergeSemantics(child: row);
    return Semantics(
      button: true,
      label: 'locked.a11y'.tr(args: [title]),
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onLockedTap,
          borderRadius: BorderRadius.circular(R.lg),
          child: row,
        ),
      ),
    );
  }
}
