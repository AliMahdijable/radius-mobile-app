
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/widgets/permission_locked.dart';
import '../theme/colors.dart';
import '../theme/spacing.dart';
import '../theme/typography.dart';
import 'app_modules.dart';
import 'top_actions.dart';
import '../widgets/merged_company_strip.dart';

/// Other modules — مطلب 2026-06-10: الـtab السفلي السابق "الضبط"
/// انتقل لاسم "قوائم أخرى" ويعرض المديولات الإضافية (الصرفيات،
/// المدراء، تسعير الباقات، إلخ). شاشة الإعدادات الفعلية انتقلت
/// لزر الـgear في الشريط العلوي على Home — ومنذ ٢٠ أكتوبر في أزرار الأعلى
/// المشتركة بكلّ التبويبات، وهذه منها ([TabHeader]).
///
/// كل بطاقة هنا stub حالياً (snack 'قيد التطوير') حتى نبني كل
/// مديول واحد واحد. الفكرة: المدير يفتح هذا الـtab فيشوف فهرس
/// واضح لما هو متاح ولما هو قادم.
class MoreModulesScreen extends StatelessWidget {
  const MoreModulesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    // بلاغ 2026-10-14: الكروت **لا تختفي** بالصلاحيّة — تبقى بمكانها مقفلةً
    // (خافتة + قفل مكان السهم، والنقر يقول «اطلبها من مديرك» ولا يفتح شيئاً)
    // فتحافظ القائمة على شكلها. ويبقى مخفيّاً ما ليس صلاحيّة: ميزةٌ لا يدعمها
    // المزوّد، أو لصاحب الحساب وحده، أو مفتاحٌ لا يُمنح لهذا الدور
    // ([permShown] — مدراء/موظّفون عند موظّف ايرث لنك). الـadmin يرى كلّ
    // الكروت مفتوحةً دائماً، و«لا صلاحيّات» احتياطٌ لقائمةٍ فارغة فقط.
    // §١٢: وشارة الكارتات أيضاً — «الكارتات» تظهر وتختفي معها بلا إعادة فتح.
    return ListenableBuilder(
      // الأقسام نفسها في القائمة الجانبيّة على الحاسبة — مصدرها واحد (app_modules.dart).
      listenable: appModulesListenable(),
      builder: (context, _) {
        final cards = <Widget>[
          for (final m in buildAppModules())
            _ModuleCard(
              locked: m.locked,
              unavailable: m.unavailable,
              icon: m.icon,
              tone: m.tone,
              brandGlyph: m.brandGlyph,
              title: m.title,
              subtitle: m.subtitle,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => m.page()),
              ),
            ),
        ];

        return Scaffold(
          backgroundColor: AppColors.bg,
          body: SafeArea(
            child: ListView(
              // ‎8 تحت الشقّ: أزرار الأعلى في موضعها من الرئيسيّة نفسه.
              padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.sm, Sp.lg, Sp.huge),
              children: [
                // ٢٠ أكتوبر: رأس التبويب الموحّد — العنوان والوصف يميناً، وأزرار
                // الأعلى المشتركة (المساعد · الجرس · الترس) يساراً. وبطاقة «كيف
                // أسوّي؟» تحته باقيةٌ كما هي.
                TabHeader(
                  title: 'more.title'.tr(),
                  subtitle: Text(
                    'more.subtitle'.tr(),
                    style: AppType.subtitle(color: AppColors.textMid),
                  ),
                ),
                // «كل الشركات»: هذه الأقسام للشركة المفتوحة وحدها — تُسمّى
                const MergedOpenCompanyNote(padding: EdgeInsets.only(top: Sp.md)),
                const SizedBox(height: Sp.lg),
                if (cards.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: Sp.huge),
                    child: Center(
                      child: Column(
                        children: [
                          Icon(LucideIcons.lock,
                              size: 36, color: AppColors.textLow),
                          const SizedBox(height: 10),
                          Text(
                            'more.empty_perms'.tr(),
                            style: AppType.label(color: AppColors.textMid),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'more.empty_perms_hint'.tr(),
                            style: AppType.muted().copyWith(fontSize: 12.5),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  for (int i = 0; i < cards.length; i++) ...[
                    if (i > 0) const SizedBox(height: Sp.sm),
                    cards[i],
                  ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ModuleCard extends StatelessWidget {
  const _ModuleCard({
    this.locked = false,
    this.unavailable,
    required this.icon,
    required this.tone,
    this.brandGlyph,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  final IconData icon;

  /// نغمة دلاليّة لا لون: الخلفيّة والأيقونة تأتيان من اللوحة معاً،
  /// فلا اشتقاق بشفافيّة لا يعرف الوضع الليلي.
  final AppTone tone;

  /// لون علامة طرف ثالث للأيقونة وحدها (أخضر واتساب · أزرق تلغرام).
  /// المربّع خلفه يبقى محايداً — هويّة القناة في الرمز لا في السطح،
  /// وصبغ السطح بلون خارجي يكسر اللوحة ولا يعرف الوضع الليلي.
  final Color? brandGlyph;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  /// بلا صلاحيّة: المقاس والمكان نفسهما، الألوان خافتة ([LockedStyle])
  /// والقفل مكان السهم، والنقر رسالةٌ لا تنقّل ([showNoPermission]).
  final bool locked;

  /// ميزةٌ لا تملكها الشركة بعد (لا صلاحيّةٌ ناقصة): الشكل المقفل نفسه،
  /// والسبب مكان الوصف وفي رسالة النقر بدل «اطلبها من مديرك». يتقدّم على
  /// [locked] — فلا صلاحيّة تفتح ما لا وجود له.
  final String? unavailable;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final locked = this.locked || unavailable != null;
    final card = Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(R.lg),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: locked
            ? () => showNoPermission(context, message: unavailable)
            : () {
                HapticFeedback.selectionClick();
                onTap();
              },
        borderRadius: BorderRadius.circular(R.lg),
        child: Container(
          padding: const EdgeInsets.fromLTRB(Sp.md, Sp.md, Sp.md, Sp.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(R.lg),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: locked
                      ? LockedStyle.box
                      : brandGlyph == null
                          ? tone.softBg
                          : AppColors.surfaceSunken,
                  borderRadius: BorderRadius.circular(R.icon),
                ),
                child: Icon(
                  icon,
                  color: locked ? LockedStyle.glyph : brandGlyph ?? tone.fill,
                  size: 22,
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
                      style: AppType.label(
                        color: locked ? LockedStyle.title : AppColors.textHi,
                      ).copyWith(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      unavailable ?? subtitle,
                      style: AppType.muted(
                        color:
                            locked ? LockedStyle.subtitle : AppColors.textMid,
                      ).copyWith(fontSize: 11.5, height: 1.4),
                    ),
                  ],
                ),
              ),
              if (locked)
                const PermLockIcon()
              else
                Icon(LucideIcons.chevronLeft,
                    color: AppColors.textLow, size: 18),
            ],
          ),
        ),
      ),
    );
    if (!locked) return card;
    return Semantics(
      button: true,
      label: unavailable == null
          ? 'locked.a11y'.tr(args: [title])
          : '$title — $unavailable',
      excludeSemantics: true,
      child: card,
    );
  }
}
