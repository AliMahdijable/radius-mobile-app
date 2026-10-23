import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/platform/desktop_layout.dart';
import '../../services/app_version.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';

/// شاشات البداية على الحاسبة (بوّابة الحساب، دخول الحساب، شركاتي، دخول الشركة، البداية): لوحة العلامة
/// على جانب — الشعار والاسم وما يفعله التطبيق — والنموذج على الجانب الآخر بعرضٍ مريح، بدل عمود هاتفٍ وسط
/// نافذةٍ فارغة.
///
/// ⚠️ كلّ شاشةٍ تلفّ نفسها بها ([wrap]) — لا إطارٌ حول الـNavigator كلّه: الإطار حول الـNavigator كان يحصر
/// طبقة النوافذ المنبثقة في عمود النموذج، فبدا تأكيد «تسجيل الخروج» وتعتيمه محشورَين في عمودٍ ضيّق (بلاغ
/// المالك ٢٣ أكتوبر). هنا الـNavigator بعرض النافذة كلّها، والنوافذ تغطّيها كاملة.
class DeskAuthLayout extends StatelessWidget {
  const DeskAuthLayout({super.key, required this.child});

  final Widget child;

  static const double _formWidth = 560;

  /// [scaffold] كما هو على الهاتف، وبلوحة العلامة بجانبه على الحاسبة قبل الغلاف ([DeskAuthScope]).
  static Widget wrap(BuildContext context, Widget scaffold) =>
      DeskAuthScope.of(context) ? DeskAuthLayout(child: scaffold) : scaffold;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final mq = MediaQuery.of(context);
    final panel = (mq.size.width * 0.42).clamp(380.0, 600.0);
    final formArea = mq.size.width - panel;
    final formWidth = formArea < _formWidth ? formArea : _formWidth;
    return Material(
      color: AppColors.bg,
      child: Row(
        children: [
          // النموذج في بداية الاتجاه (يمين العربيّة)، والعلامة في نهايته.
          Expanded(
            child: Center(
              child: SizedBox(
                width: formWidth,
                child: MediaQuery(
                  data: mq.copyWith(size: Size(formWidth, mq.size.height)),
                  child: child,
                ),
              ),
            ),
          ),
          SizedBox(width: panel, child: const _BrandPanel()),
        ],
      ),
    );
  }
}

class _BrandPanel extends StatelessWidget {
  const _BrandPanel();

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    // لوحةٌ بسطح العلامة الداكن في الوضعين (brandSurface): طبقات onBrand* معايرةٌ عليه.
    const fg = AppColors.onBrand;
    const fgMuted = AppColors.onBrandSecondary;
    final features = <(IconData, String, String)>[
      (LucideIcons.users, 'desktop.auth_f1_title'.tr(), 'desktop.auth_f1_body'.tr()),
      (LucideIcons.router, 'desktop.auth_f2_title'.tr(), 'desktop.auth_f2_body'.tr()),
      (LucideIcons.chartLine, 'desktop.auth_f3_title'.tr(), 'desktop.auth_f3_body'.tr()),
      (LucideIcons.messageCircle, 'desktop.auth_f4_title'.tr(), 'desktop.auth_f4_body'.tr()),
    ];
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
          colors: [AppColors.brandSurface, AppColors.brandDark],
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Sp.huge, Sp.huge, Sp.huge, Sp.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.onBrand,
                      borderRadius: BorderRadius.circular(R.icon),
                    ),
                    child: Image.asset('assets/images/logo.png', fit: BoxFit.contain, cacheWidth: 160),
                  ),
                  const SizedBox(width: Sp.md),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('MyServices Pro',
                          style: AppType.title(color: fg).copyWith(fontSize: 22, height: 1.2)),
                      Text('login.subtitle'.tr(),
                          style: AppType.muted(color: fgMuted).copyWith(fontSize: 13.5)),
                    ],
                  ),
                ],
              ),
              const Spacer(),
              Text(
                'desktop.auth_headline'.tr(),
                style: AppType.title(color: fg).copyWith(fontSize: 30, height: 1.35),
              ),
              const SizedBox(height: Sp.md),
              Text(
                'desktop.auth_lead'.tr(),
                style: AppType.body(color: fgMuted).copyWith(fontSize: 15, height: 1.6),
              ),
              const SizedBox(height: Sp.xxl),
              for (final (icon, title, body) in features)
                Padding(
                  padding: const EdgeInsets.only(bottom: Sp.lg),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: AppColors.onBrandFill2,
                          borderRadius: BorderRadius.circular(R.md),
                          border: Border.all(color: AppColors.onBrandFill3),
                        ),
                        child: Icon(icon, size: 19, color: fg),
                      ),
                      const SizedBox(width: Sp.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(title,
                                style: AppType.label(color: fg).copyWith(fontSize: 15, fontWeight: FontWeight.w700)),
                            const SizedBox(height: 2),
                            Text(body,
                                style: AppType.muted(color: fgMuted).copyWith(fontSize: 13, height: 1.5)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              const Spacer(),
              Row(
                children: [
                  const Icon(LucideIcons.refreshCcw, size: 14, color: fgMuted),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'desktop.auth_sync'.tr(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.muted(color: fgMuted).copyWith(fontSize: 12.5),
                    ),
                  ),
                  Text(AppVersion.shortVersion,
                      textDirection: TextDirection.ltr,
                      style: AppType.muted(color: fgMuted).copyWith(fontSize: 12.5)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
