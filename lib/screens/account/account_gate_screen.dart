import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../api/account_api.dart';
import '../../services/account_service.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import 'account_login_screen.dart';
import 'account_widgets.dart';
import 'companies_screen.dart';
import 'subscription_screen.dart';

/// Pro البند ٤: باب التطبيق بلا جلسة ساس — يقرّر أين يذهب المستخدم:
/// لا حساب/بريدٌ غير مؤكَّد ← شاشة الحساب · اشتراكٌ منتهٍ ← التفعيل · وإلّا
/// ← «شركاتي». كلّ مسارٍ كان يذهب لشاشة دخول الساس (الإقلاع، الخروج، انتهاء
/// الجلسة، الحظر) يمرّ من هنا الآن.
class AccountGateScreen extends StatefulWidget {
  const AccountGateScreen({super.key, this.message});

  /// رسالةٌ تُعرض عند الوصول (مثلاً «انتهت الجلسة»).
  final String? message;

  @override
  State<AccountGateScreen> createState() => _AccountGateScreenState();
}

class _AccountGateScreenState extends State<AccountGateScreen> {
  String? _error; // مفتاح/رسالة خطأٍ يمنع المتابعة
  bool _disabled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.message != null && mounted) showAccountSnack(context, widget.message!);
      _decide();
    });
  }

  void _go(Widget next) {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(PageRouteBuilder(
      pageBuilder: (_, __, ___) => next,
      transitionDuration: const Duration(milliseconds: 180),
      transitionsBuilder: (_, a, __, c) => FadeTransition(opacity: a, child: c),
    ));
  }

  Future<void> _decide() async {
    setState(() {
      _error = null;
      _disabled = false;
    });
    if (!AccountService.available) {
      setState(() => _error = 'account.err_firebase');
      return;
    }
    if (!AccountService.isReady) {
      _go(const AccountLoginScreen());
      return;
    }
    try {
      var me = await AccountApi.me();
      if (!me.registered) me = await AccountApi.bootstrap();
      if (!mounted) return;
      if (me.disabled) {
        setState(() => _disabled = true);
        return;
      }
      _go(me.subscription.active ? CompaniesScreen(me: me) : SubscriptionScreen(me: me));
    } on AccountApiException catch (e) {
      if (kDebugMode) debugPrint('🟡 account gate: $e');
      if (!mounted) return;
      switch (e.code) {
        case 'email-not-verified':
          _go(const AccountLoginScreen());
        case 'account-disabled':
          setState(() => _disabled = true);
        case 'no-account' || 'invalid-account-token' || 'account-token-expired' || 'no-account-token':
          await AccountService.signOut();
          _go(const AccountLoginScreen());
        default:
          setState(() => _error = e.message);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('🔴 account gate: $e');
      if (mounted) setState(() => _error = 'account.err_network');
    }
  }

  Future<void> _signOut() async {
    await AccountService.signOut();
    _go(const AccountLoginScreen());
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    if (_disabled) {
      return AccountScaffold(
        title: 'account.disabled_title'.tr(),
        subtitle: 'account.disabled_body'.tr(),
        children: [
          AccountOutlineButton(label: 'account.sign_out'.tr(), onTap: _signOut),
        ],
      );
    }
    if (_error != null) {
      return AccountScaffold(
        title: 'account.gate_error_title'.tr(),
        subtitle: accountText(_error!),
        children: [
          AccountPrimaryButton(label: 'common.retry'.tr(), icon: Icons.refresh_rounded, onTap: _decide),
          const SizedBox(height: Sp.md),
          if (AccountService.currentUser != null)
            AccountTextLink(label: 'account.sign_out'.tr(), onTap: _signOut, danger: true),
        ],
      );
    }
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const AccountLogo(size: 88),
            const SizedBox(height: Sp.xl),
            SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(strokeWidth: 2.4, color: AppColors.brand),
            ),
            const SizedBox(height: Sp.md),
            Text('account.checking'.tr(), style: AppType.subtitle(color: AppColors.textMid)),
          ],
        ),
      ),
    );
  }
}
