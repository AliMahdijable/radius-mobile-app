import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../api/account_api.dart';
import '../../services/account_service.dart';
import '../../services/support_contact.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import 'account_login_screen.dart';
import 'account_widgets.dart';
import 'companies_screen.dart';

/// Pro البند ٤: حالة الاشتراك + كود التفعيل.
///
/// ⚠️ شرط المتاجر: لا سعر ولا زرّ دفعٍ ولا رابط شراء — الكود يُحصَل خارج
/// التطبيق، والشاشة تطلبه فقط.
class SubscriptionScreen extends StatefulWidget {
  const SubscriptionScreen({super.key, required this.me, this.fromCompanies = false});

  final AccountMe me;

  /// فُتحت من «شركاتي» (الاشتراك ما يزال صالحاً) — رجوعٌ بدل خروج.
  final bool fromCompanies;

  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> {
  final _codeCtrl = TextEditingController();
  bool _busy = false;
  late AccountSubscription _sub = widget.me.subscription;

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  String _date(DateTime? d) => d == null ? '—' : DateFormat('d MMMM y', context.locale.languageCode).format(d);

  Future<void> _redeem() async {
    final code = _codeCtrl.text.trim();
    if (code.isEmpty) {
      showAccountSnack(context, 'account.code_empty'.tr(), error: true);
      return;
    }
    HapticFeedback.lightImpact();
    setState(() => _busy = true);
    try {
      final sub = await AccountApi.redeemCode(code);
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      setState(() => _sub = sub);
      _codeCtrl.clear();
      showAccountSnack(context, 'account.code_ok'.tr(args: [_date(sub.endsAt)]));
      if (sub.active) {
        final me = AccountMe(
          registered: true,
          email: widget.me.email,
          accountStatus: widget.me.accountStatus,
          subscription: sub,
          support: widget.me.support,
        );
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => CompaniesScreen(me: me)),
          (_) => false,
        );
      }
    } on AccountApiException catch (e) {
      if (!mounted) return;
      HapticFeedback.heavyImpact();
      showAccountSnack(context, accountText(e.message), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signOut() async {
    await AccountService.signOut();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AccountLoginScreen()),
      (_) => false,
    );
  }

  ({String title, String body, IconData icon, Color color, Color bg}) _status() {
    if (_sub.active && _sub.isTrial) {
      return (
        title: 'account.status_trial'.tr(args: ['${_sub.daysLeft}']),
        body: 'account.status_until'.tr(args: [_date(_sub.endsAt)]),
        icon: Icons.hourglass_top_rounded,
        color: AppColors.warning,
        bg: AppColors.warningSoftBg,
      );
    }
    if (_sub.active) {
      return (
        title: 'account.status_active'.tr(),
        body: 'account.status_until'.tr(args: [_date(_sub.endsAt)]),
        icon: Icons.verified_rounded,
        color: AppColors.success,
        bg: AppColors.successSoftBg,
      );
    }
    if (_sub.trialUsedElsewhere) {
      return (
        title: 'account.status_trial_used'.tr(),
        body: 'account.status_trial_used_body'.tr(),
        icon: Icons.info_outline_rounded,
        color: AppColors.error,
        bg: AppColors.dangerSoftBg,
      );
    }
    return (
      title: _sub.validUntil == null ? 'account.status_trial_ended'.tr() : 'account.status_ended'.tr(),
      body: 'account.status_ended_on'.tr(args: [_date(_sub.endsAt)]),
      icon: Icons.lock_clock_outlined,
      color: AppColors.error,
      bg: AppColors.dangerSoftBg,
    );
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final st = _status();
    return AccountScaffold(
      title: 'account.subscription_title'.tr(),
      subtitle: widget.me.email,
      onBack: widget.fromCompanies ? () => Navigator.of(context).maybePop() : null,
      showLogo: !widget.fromCompanies,
      children: [
        Container(
          padding: const EdgeInsets.all(Sp.lg),
          decoration: BoxDecoration(color: st.bg, borderRadius: BorderRadius.circular(R.lg)),
          child: Row(
            children: [
              Icon(st.icon, color: st.color, size: 28),
              const SizedBox(width: Sp.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(st.title, style: AppType.cardTitleBold(color: AppColors.textHi)),
                    const SizedBox(height: Sp.xxs),
                    Text(st.body, style: AppType.body(color: AppColors.textBody)),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: Sp.xl),
        AccountCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AccountField(
                label: 'account.code_label'.tr(),
                controller: _codeCtrl,
                hint: 'XXXX-XXXX-XXXX',
                textCapitalization: TextCapitalization.characters,
                textDirection: TextDirection.ltr,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _redeem(),
              ),
              const SizedBox(height: Sp.sm),
              Text('account.code_help'.tr(), style: AppType.muted(color: AppColors.textMid)),
              const SizedBox(height: Sp.lg),
              AccountPrimaryButton(
                label: 'account.code_activate'.tr(),
                icon: Icons.key_rounded,
                loading: _busy,
                onTap: _redeem,
              ),
            ],
          ),
        ),
        if (!widget.me.support.isEmpty) ...[
          const SizedBox(height: Sp.lg),
          AccountOutlineButton(
            label: 'account.contact_us'.tr(),
            leading: Icon(Icons.support_agent_rounded, color: AppColors.brand, size: 20),
            onTap: () => SupportContact.open(context, widget.me.support),
          ),
        ],
        const SizedBox(height: Sp.lg),
        if (!widget.fromCompanies)
          AccountTextLink(label: 'account.sign_out'.tr(), onTap: _busy ? null : _signOut, danger: true),
      ],
    );
  }
}
