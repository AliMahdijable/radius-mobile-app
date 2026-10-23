// `hide TextDirection`: الحزمة تصدّر نوع intl الذي يحجب نوع dart:ui.
import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/widgets/design_sheet.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import '../account/account_widgets.dart' show openPrivacyPolicy;
import '../../core/widgets/app_sheet.dart';

/// الموافقة قبل أوّل استعمالٍ للمساعد الذكيّ (`AiConsent`): أنّ الأجوبة من
/// مزوّد ذكاءٍ اصطناعيّ خارجيّ (Anthropic)، وما يُرسل له، وأنّ الإخفاء أفضل جهدٍ
/// لا ضمان، وأنّ الجواب قد يخطئ، وما يحفظه خادمنا ومدّته (٢٤ ساعة، حتى ٣٠ يوماً)
/// وأنّه قد يُفحص آليّاً للدقّة — بلغةٍ بسيطة ورابط سياسة الخصوصيّة (البند ٣).
/// `true` = «موافق»؛ أيّ إغلاقٍ آخر (السحب، ×، «مو هسه») = لا، ولا يُرسل شيء.
Future<bool> showAssistantConsentSheet(BuildContext context) async {
  final ok = await showAppSheet<bool>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    backgroundColor: Colors.transparent,
    barrierColor: AppColors.scrim,
    builder: (_) => const AssistantConsentSheet(),
  );
  return ok == true;
}

class AssistantConsentSheet extends StatelessWidget {
  const AssistantConsentSheet({super.key});

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final nav = Navigator.of(context);
    return DesignSheet(
      header: SheetHeaderBar(
        icon: LucideIcons.shieldCheck,
        title: 'ai.title'.tr(),
        subtitle: 'ai.consent_title'.tr(),
        onClose: () => nav.pop(false),
      ),
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'ai.consent_lead'.tr(),
            style: AppType.rowValue(color: AppColors.textBody)
                .copyWith(height: 1.6),
          ),
          const SizedBox(height: Sp.md),
          _Point(icon: LucideIcons.send, text: 'ai.consent_sends'.tr()),
          _Point(icon: LucideIcons.eyeOff, text: 'ai.consent_names'.tr()),
          _Point(
              icon: LucideIcons.triangleAlert, text: 'ai.consent_may_err'.tr()),
          _Point(icon: LucideIcons.history, text: 'ai.consent_keep'.tr()),
          _Point(
              icon: LucideIcons.scanSearch, text: 'ai.consent_review'.tr()),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              onPressed: () => openPrivacyPolicy(context),
              icon: const Icon(LucideIcons.fileText, size: 16),
              label: Text('account.privacy_policy'.tr()),
            ),
          ),
        ],
      ),
      footer: SheetFooterBar(
        label: 'ai.consent_accept'.tr(),
        icon: LucideIcons.check,
        onPressed: () => nav.pop(true),
        leading: SheetSecondaryButton(
          label: 'ai.consent_decline'.tr(),
          onTap: () => nav.pop(false),
        ),
      ),
    );
  }
}

/// سطرٌ بأيقونة — نقطةٌ واحدة ممّا يوافق عليه المدير.
class _Point extends StatelessWidget {
  const _Point({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Padding(
      padding: const EdgeInsets.only(bottom: Sp.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, size: 16, color: AppColors.brandAccent),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style:
                  AppType.body(color: AppColors.textBody).copyWith(height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}
