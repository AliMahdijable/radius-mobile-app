import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../api/archive_info.dart';
import '../../../core/util/bidi.dart';
import '../../../core/widgets/design_sheet.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../services/permissions_service.dart';
import '../../../theme/typography.dart';
import '../settle_widgets.dart';
import '../settlements_screen.dart';

/// شريطٌ يشرح لماذا نقص ما تراه — فوق الصرفيات وفوق التقرير الماليّ.
///
/// ⚠️ **الإخفاء بلا تفسيرٍ يُقرأ عطلاً.** ما غطّته تسويةٌ فعّالة يختفي
/// من شاشات «الآن» بأمر الخادم، فقد تجد قائمة الصرفيات **فارغةً تماماً**
/// وهي صحيحة. بلا هذا الشريط يظنّ المدير أنّ صرفيّاته ضاعت.
///
/// ولا يظهر إطلاقاً حين [ArchiveInfo.show] كاذبة — أي لا تسوياتٍ بعد.
///
/// (`docs/settlements-prompt.md` §٤ و§٦-٣ و§٦-٤)
class ArchiveBar extends StatelessWidget {
  const ArchiveBar({
    super.key,
    required this.archive,
    required this.includeArchived,
    required this.onChanged,
    this.padding,
  });

  final ArchiveInfo? archive;

  /// الوضع الحاليّ: `false` «الحاليّة»، `true` «مع الأرشيف».
  final bool includeArchived;
  final ValueChanged<bool> onChanged;

  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    // الوضع الليليّ: كلّ build يبدأ بهذا كي يُعاد الرسم عند التبديل.
    Theme.of(context);

    final a = archive;
    if (a == null || !a.show) return const SizedBox.shrink();

    // ⚠️ التاريخ يُعزَل بـ`iso`: «#2 · الخميس 2026-10-03 21:27» داخل
    // جملةٍ عربيّة يُفكّك محرّك BiDi ترتيبَه بلا العزل.
    final when = iso(settleWhen(a.lastCutAt, weekday: true));
    final text = includeArchived
        ? 'archive.showing_all'.tr(args: ['${a.settlements}'])
        : 'archive.showing_current'
            .tr(args: ['${a.lastNumber ?? a.settlements}', when]);

    return Padding(
      padding: padding ??
          const EdgeInsetsDirectional.fromSTEB(Sp.md, Sp.sm, Sp.md, Sp.sm),
      child: Container(
        padding: const EdgeInsets.all(Sp.sm),
        decoration: BoxDecoration(
          color: AppColors.surfaceSunken,
          borderRadius: BorderRadius.circular(R.md),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(LucideIcons.archive, size: 14, color: AppColors.textLow),
                const SizedBox(width: Sp.xs),
                // ⚠️ `maxLines` + `ellipsis` إلزاميّان: الأيقونة جارٌ
                // ثابت، وبلاهما يُسحق النصّ صامتاً إلى عرضٍ صفر
                // (حارسا `text_crush_test` و`flex_text_guard_test`).
                Expanded(
                  child: Text(
                    text,
                    style: AppType.micro(color: AppColors.textLow),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: Sp.sm),
            // ⚠️ `Wrap` لا `Row`: الحبّات الثلاث بالإنجليزيّة تتجاوز
            // العرض المتاح على شاشة ٣٢٠ نقطة، والفحص يشملها (§٩-٩).
            Wrap(
              spacing: Sp.xs,
              runSpacing: Sp.xs,
              children: [
                ToneChip(
                  label: 'archive.tab_current'.tr(),
                  tone: includeArchived ? AppTone.neutral : AppTone.brand,
                  dense: true,
                  onTap: includeArchived ? () => onChanged(false) : null,
                ),
                ToneChip(
                  label: 'archive.tab_all'.tr(),
                  tone: includeArchived ? AppTone.brand : AppTone.neutral,
                  dense: true,
                  onTap: includeArchived ? null : () => onChanged(true),
                ),
                // ليس مدخلاً ثانياً للشاشة بل سياقٌ يشرح الإخفاء، كما
                // في الويب. المدخل يبقى واحداً في «المزيد» (§٧).
                //
                // ⚠️ **ويُحرَس بصلاحيّته.** الصرفيات والتقرير الماليّ
                // صلاحيّتهما غير صلاحيّة التسوية، فموظّفٌ يملك
                // `reports.expenses` وحدها كان يصل من هنا إلى شاشةٍ
                // أُخفيت عنه في «المزيد» بقصد. الخادم يردّ 403 فلا
                // تتسرّب بيانات، لكنّ §٩-٢ ينصّ على ألّا يراها أصلاً.
                if (Perms.has('settlements.view'))
                  ToneChip(
                  label: 'archive.open_settlements'.tr(),
                  tone: AppTone.neutral,
                  icon: LucideIcons.arrowLeft,
                  dense: true,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const SettlementsScreen(),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
