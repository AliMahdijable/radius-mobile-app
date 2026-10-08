import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/account_service.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import 'account_gate_screen.dart';
import 'account_widgets.dart';

enum _Mode { signIn, signUp, verify }

/// Pro البند ٤ — الطبقة ①: حساب المستخدم (قبل أيّ ساس).
/// Google بضغطة، أو إيميل + كلمة سرّ مع رابط تأكيدٍ على البريد. التجربة
/// المجّانيّة والتفعيل مربوطان بالبريد المؤكَّد.
class AccountLoginScreen extends StatefulWidget {
  const AccountLoginScreen({super.key});

  @override
  State<AccountLoginScreen> createState() => _AccountLoginScreenState();
}

class _AccountLoginScreenState extends State<AccountLoginScreen> {
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _passFocus = FocusNode();
  _Mode _mode = _Mode.signIn;
  bool _obscure = true;
  bool _busy = false;
  bool _googleBusy = false;

  @override
  void initState() {
    super.initState();
    final u = AccountService.currentUser;
    if (u != null && !AccountService.isReady) {
      _mode = _Mode.verify; // دخل سابقاً بإيميل لم يؤكّده بعد
      _emailCtrl.text = u.email ?? '';
    }
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _passFocus.dispose();
    super.dispose();
  }

  void _toGate() {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const AccountGateScreen()));
  }

  void _err(Object e) {
    if (kDebugMode) debugPrint('🔴 account login: $e');
    if (!mounted) return;
    HapticFeedback.heavyImpact();
    showAccountSnack(context, AccountService.messageFor(e).tr(), error: true);
  }

  Future<void> _google() async {
    HapticFeedback.selectionClick();
    setState(() => _googleBusy = true);
    try {
      final u = await AccountService.signInWithGoogle();
      if (u != null) _toGate();
    } catch (e) {
      _err(e);
    } finally {
      if (mounted) setState(() => _googleBusy = false);
    }
  }

  Future<void> _submitEmail() async {
    final email = _emailCtrl.text.trim();
    final pass = _passCtrl.text;
    if (email.isEmpty || !email.contains('@')) {
      showAccountSnack(context, 'account.err_invalid_email'.tr(), error: true);
      return;
    }
    if (pass.length < (_mode == _Mode.signUp ? 8 : 1)) {
      showAccountSnack(context, (_mode == _Mode.signUp ? 'account.err_weak_password' : 'account.enter_password').tr(),
          error: true);
      return;
    }
    HapticFeedback.lightImpact();
    setState(() => _busy = true);
    try {
      final created = _mode == _Mode.signUp;
      if (created) {
        await AccountService.signUpWithEmail(email, pass); // يرسل رابط التأكيد
      } else {
        await AccountService.signInWithEmail(email, pass);
      }
      if (!mounted) return;
      if (AccountService.isReady) {
        _toGate();
      } else {
        setState(() => _mode = _Mode.verify);
        if (created) showAccountSnack(context, 'account.verify_sent'.tr(args: [email]));
      }
    } catch (e) {
      _err(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _forgot() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      showAccountSnack(context, 'account.forgot_need_email'.tr(), error: true);
      return;
    }
    try {
      await AccountService.sendPasswordReset(email);
      if (mounted) showAccountSnack(context, 'account.forgot_sent'.tr(args: [email]));
    } catch (e) {
      _err(e);
    }
  }

  Future<void> _checkVerified() async {
    setState(() => _busy = true);
    try {
      if (await AccountService.reloadVerified()) {
        _toGate();
      } else if (mounted) {
        showAccountSnack(context, 'account.verify_not_yet'.tr(), error: true);
      }
    } catch (e) {
      _err(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resend() async {
    try {
      await AccountService.resendVerification();
      if (mounted) showAccountSnack(context, 'account.verify_sent'.tr(args: [_emailCtrl.text.trim()]));
    } catch (e) {
      _err(e);
    }
  }

  Future<void> _useAnother() async {
    await AccountService.signOut();
    if (!mounted) return;
    setState(() {
      _mode = _Mode.signIn;
      _passCtrl.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    if (_mode == _Mode.verify) return _buildVerify();
    final signUp = _mode == _Mode.signUp;
    return AccountScaffold(
      title: signUp ? 'account.signup_title'.tr() : 'account.signin_title'.tr(),
      subtitle: 'account.signin_subtitle'.tr(),
      children: [
        AccountOutlineButton(
          label: 'account.continue_google'.tr(),
          leading: const GoogleMark(),
          loading: _googleBusy,
          onTap: _busy ? null : _google,
        ),
        const SizedBox(height: Sp.lg),
        Row(children: [
          Expanded(child: Divider(color: AppColors.border)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Sp.md),
            child: Text('account.or_email'.tr(), style: AppType.muted(color: AppColors.textLow)),
          ),
          Expanded(child: Divider(color: AppColors.border)),
        ]),
        const SizedBox(height: Sp.lg),
        AccountCard(
          child: AutofillGroup(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AccountField(
                  label: 'account.email'.tr(),
                  controller: _emailCtrl,
                  hint: 'name@gmail.com',
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  textDirection: TextDirection.ltr,
                  autofillHints: const [AutofillHints.email],
                  onSubmitted: (_) => _passFocus.requestFocus(),
                ),
                const SizedBox(height: Sp.lg),
                AccountField(
                  label: 'account.password'.tr(),
                  controller: _passCtrl,
                  focusNode: _passFocus,
                  hint: signUp ? 'account.password_hint_new'.tr() : '••••••••',
                  obscure: _obscure,
                  onToggleObscure: () => setState(() => _obscure = !_obscure),
                  textInputAction: TextInputAction.done,
                  autofillHints: [signUp ? AutofillHints.newPassword : AutofillHints.password],
                  onSubmitted: (_) => _submitEmail(),
                ),
                if (!signUp)
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: TextButton(
                      onPressed: _busy ? null : _forgot,
                      child: Text('account.forgot'.tr(), style: AppType.link(color: AppColors.brandAccent)),
                    ),
                  )
                else
                  const SizedBox(height: Sp.lg),
                AccountPrimaryButton(
                  label: signUp ? 'account.create_account'.tr() : 'account.sign_in'.tr(),
                  loading: _busy,
                  onTap: _googleBusy ? null : _submitEmail,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: Sp.md),
        AccountTextLink(
          label: signUp ? 'account.have_account'.tr() : 'account.no_account'.tr(),
          onTap: _busy
              ? null
              : () => setState(() {
                    _mode = signUp ? _Mode.signIn : _Mode.signUp;
                    _passCtrl.clear();
                  }),
        ),
        const SizedBox(height: Sp.sm),
        Text('account.trial_note'.tr(), textAlign: TextAlign.center, style: AppType.muted(color: AppColors.textMid)),
      ],
    );
  }

  Widget _buildVerify() {
    final email = AccountService.currentUser?.email ?? _emailCtrl.text.trim();
    return AccountScaffold(
      title: 'account.verify_title'.tr(),
      subtitle: 'account.verify_body'.tr(args: [email]),
      children: [
        AccountCard(
          child: Row(
            children: [
              Icon(Icons.mark_email_unread_outlined, color: AppColors.brand, size: 28),
              const SizedBox(width: Sp.md),
              Expanded(
                child: Text('account.verify_hint'.tr(),
                    style: AppType.body(color: AppColors.textBody).copyWith(height: 1.55)),
              ),
            ],
          ),
        ),
        const SizedBox(height: Sp.lg),
        AccountPrimaryButton(
          label: 'account.verify_done'.tr(),
          icon: Icons.check_circle_outline_rounded,
          loading: _busy,
          onTap: _checkVerified,
        ),
        const SizedBox(height: Sp.md),
        AccountOutlineButton(label: 'account.verify_resend'.tr(), onTap: _busy ? null : _resend),
        const SizedBox(height: Sp.sm),
        AccountTextLink(label: 'account.use_another'.tr(), onTap: _busy ? null : _useAnother),
      ],
    );
  }
}
