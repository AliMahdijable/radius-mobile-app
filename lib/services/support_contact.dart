import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/account_api.dart';
import '../theme/colors.dart';
import '../theme/spacing.dart';
import '../theme/typography.dart';

/// Pro البند ٤: «تواصل معنا» — تيليجرام/واتساب كما يضبطهما المالك.
///
/// ⚠️ شرط المتاجر: الزرّ «تواصل معنا» عامّ (دعم)، لا «اشترِ/جدّد» ولا سعر.
class SupportContact {
  SupportContact._();

  static Uri? _telegram(SupportInfo s) =>
      (s.telegram ?? '').isEmpty ? null : Uri.parse('https://t.me/${s.telegram}');
  static Uri? _whatsapp(SupportInfo s) =>
      (s.whatsapp ?? '').isEmpty ? null : Uri.parse('https://wa.me/${s.whatsapp}');

  /// وسيلةٌ واحدة ← تُفتح مباشرةً؛ اثنتان ← اختيار.
  static Future<void> open(BuildContext context, SupportInfo s) async {
    final tg = _telegram(s);
    final wa = _whatsapp(s);
    if (tg == null && wa == null) {
      _snack(context, 'account.contact_none'.tr());
      return;
    }
    if (tg != null && wa != null) {
      final pick = await showModalBottomSheet<Uri>(
        context: context,
        backgroundColor: AppColors.surfaceSheet,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(R.sheet))),
        builder: (ctx) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(Sp.xl, Sp.lg, Sp.xl, Sp.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('account.contact_us'.tr(), textAlign: TextAlign.center, style: AppType.sheetTitle(color: AppColors.textHi)),
                const SizedBox(height: Sp.lg),
                _Option(icon: Icons.send_rounded, label: 'account.contact_telegram'.tr(), onTap: () => Navigator.of(ctx).pop(tg)),
                const SizedBox(height: Sp.sm),
                _Option(icon: Icons.chat_rounded, label: 'account.contact_whatsapp'.tr(), onTap: () => Navigator.of(ctx).pop(wa)),
              ],
            ),
          ),
        ),
      );
      if (pick != null && context.mounted) await _launch(context, pick);
      return;
    }
    await _launch(context, (tg ?? wa)!);
  }

  static Future<void> _launch(BuildContext context, Uri uri) async {
    var ok = false;
    try {
      ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
    if (!ok && context.mounted) _snack(context, 'account.contact_failed'.tr());
  }

  static void _snack(BuildContext context, String msg) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
      content: Text(msg, style: AppType.button(color: AppColors.onBrand)),
      backgroundColor: AppColors.brand,
      behavior: SnackBarBehavior.floating,
    ));
  }
}

class _Option extends StatelessWidget {
  const _Option({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(R.md),
      child: InkWell(
        borderRadius: BorderRadius.circular(R.md),
        onTap: onTap,
        child: Container(
          height: 54,
          padding: const EdgeInsets.symmetric(horizontal: Sp.lg),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(R.md),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(children: [
            Icon(icon, color: AppColors.brand, size: 22),
            const SizedBox(width: Sp.md),
            Expanded(child: Text(label, style: AppType.button(color: AppColors.textHi))),
          ]),
        ),
      ),
    );
  }
}
