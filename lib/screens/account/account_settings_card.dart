import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';

import '../../api/account_api.dart';
import '../../services/account_service.dart';
import '../../services/support_contact.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import 'account_login_screen.dart';
import 'subscription_banner.dart';
import 'subscription_screen.dart';

/// Pro البند ٤: «الحساب والاشتراك» في الإعدادات — البريد، حالة الاشتراك
/// وتاريخ انتهائه، ومنه: كود التفعيل · تواصل معنا · الخروج من الحساب.
class AccountSettingsCard extends StatefulWidget {
  const AccountSettingsCard({super.key});

  @override
  State<AccountSettingsCard> createState() => _AccountSettingsCardState();
}

class _AccountSettingsCardState extends State<AccountSettingsCard> {
  AccountMe? _me = AccountStatusCache.cached;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool force = false}) async {
    final me = await AccountStatusCache.get(force: force);
    if (mounted) setState(() => _me = me);
  }

  String _date(DateTime? d) => d == null ? '—' : DateFormat('d MMMM y', context.locale.languageCode).format(d);

  Future<void> _openSubscription(AccountMe me) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => SubscriptionScreen(me: me, fromCompanies: true),
    ));
    await _load(force: true);
  }

  Future<void> _signOut() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('account.sign_out'.tr(), style: AppType.sheetTitle(color: AppColors.textHi)),
        content: Text('account.sign_out_body'.tr(),
            style: AppType.subtitle(color: AppColors.textMid).copyWith(height: 1.55)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('common.cancel'.tr(), style: AppType.button(color: AppColors.textMid)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('account.sign_out'.tr(), style: AppType.button(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    AccountStatusCache.clear();
    await AccountService.signOut();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AccountLoginScreen()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final me = _me;
    final email = me?.email ?? AccountService.currentUser?.email ?? '';
    final s = me?.subscription;
    final String status;
    final Color tone;
    if (s == null) {
      status = 'account.checking'.tr();
      tone = AppColors.textMid;
    } else if (!s.active) {
      status = 'account.status_ended'.tr();
      tone = AppColors.error;
    } else {
      status = '${(s.isTrial ? 'account.chip_trial' : 'account.chip_active').tr(args: ['${s.daysLeft}'])} · '
          '${'account.status_until'.tr(args: [_date(s.endsAt)])}';
      tone = s.isTrial || s.daysLeft <= kSubscriptionWarnDays ? AppColors.warning : AppColors.success;
    }

    return Container(
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(R.card)),
      padding: const EdgeInsets.all(Sp.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: AppColors.brandSoftBg, borderRadius: BorderRadius.circular(R.md)),
                child: Icon(Icons.verified_user_outlined, color: AppColors.brand, size: 20),
              ),
              const SizedBox(width: Sp.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('account.settings_title'.tr(), style: AppType.cardTitleBold(color: AppColors.textHi)),
                    const SizedBox(height: Sp.xxs),
                    Text(email, style: AppType.body(color: AppColors.textMid),
                        maxLines: 1, overflow: TextOverflow.ellipsis, textDirection: TextDirection.ltr),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: Sp.md),
          Text(status, style: AppType.bodyStrong(color: tone)),
          const SizedBox(height: Sp.md),
          Wrap(
            spacing: Sp.sm,
            runSpacing: Sp.sm,
            children: [
              if (me != null)
                _Chip(icon: Icons.key_rounded, label: 'account.menu_code'.tr(), onTap: () => _openSubscription(me)),
              if (me != null && !me.support.isEmpty)
                _Chip(
                  icon: Icons.support_agent_rounded,
                  label: 'account.contact_us'.tr(),
                  onTap: () => SupportContact.open(context, me.support),
                ),
              _Chip(icon: Icons.logout_rounded, label: 'account.sign_out'.tr(), danger: true, onTap: _signOut),
            ],
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.label, required this.onTap, this.danger = false});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final fg = danger ? AppColors.error : AppColors.brand;
    return Material(
      color: danger ? AppColors.dangerSoftBg : AppColors.brandSoftBg,
      borderRadius: BorderRadius.circular(R.pill),
      child: InkWell(
        borderRadius: BorderRadius.circular(R.pill),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: Sp.sm),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 16, color: fg),
            const SizedBox(width: Sp.xs + 2),
            Text(label, style: AppType.pillBold(color: fg).copyWith(fontSize: 12.5)),
          ]),
        ),
      ),
    );
  }
}
