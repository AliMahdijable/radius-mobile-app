import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:firebase_auth/firebase_auth.dart' show FirebaseAuthException;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/platform/store_policy.dart';
import '../../core/util/email_shape.dart';
import '../../services/account_service.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import 'account_gate_screen.dart';
import 'account_settings_card.dart' show confirmAndDeleteAccount;
import 'account_widgets.dart';
import 'apple_sign_in_button.dart';
import 'employee_login_screen.dart';

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
  bool _appleBusy = false;

  /// أندرويد: رجعت نافذة Google بلا دخول (أُلغيت) ⇒ يظهر «ادخل عبر المتصفّح» تحت الأيقونات.
  /// بلاغ ٢٠٢٦-١٠-١٦: على أجهزةٍ (تكنو/هونر…) يختفي اختيار الحساب بعد النقر بلا دخول.
  bool _googleWebOffer = false;

  /// أيّ دخولٍ جارٍ — يعطّل بقيّة الأزرار حتى لا يتسابق مساران.
  bool get _anyBusy => _busy || _googleBusy || _appleBusy;

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
      if (u != null) {
        _toGate();
      } else if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android && mounted) {
        setState(() => _googleWebOffer = true);
      }
    } catch (e) {
      // فشل Google لا يُعرض «كلمة سرّ خاطئة» (لا كلمة سرّ في هذا المسار): رسالة Google بالرمز
      // الحقيقيّ — ويُكتب الرمز في السجلّ (بلا بيانات شخصيّة) فيُشخَّص التكرار من logcat.
      final code = e is FirebaseAuthException ? e.code : e.runtimeType.toString();
      debugPrint('account google sign-in failed: $code');
      if (e is FirebaseAuthException &&
          const {'user-disabled', 'network-request-failed', 'too-many-requests', 'account-exists-with-different-credential'}
              .contains(e.code)) {
        _err(e);
      } else if (mounted) {
        HapticFeedback.heavyImpact();
        showAccountSnack(context, 'account.err_google_code'.tr(args: [code]), error: true);
      }
    } finally {
      if (mounted) setState(() => _googleBusy = false);
    }
  }

  /// Google عبر المتصفّح — لا يمرّ بـCredential Manager (AccountService.signInWithGoogleWeb).
  Future<void> _googleWeb() async {
    HapticFeedback.selectionClick();
    setState(() => _googleBusy = true);
    try {
      final u = await AccountService.signInWithGoogleWeb();
      if (u != null) _toGate();
    } catch (e) {
      final code = e is FirebaseAuthException ? e.code : e.runtimeType.toString();
      debugPrint('account google web sign-in failed: $code');
      if (e is FirebaseAuthException &&
          const {'user-disabled', 'network-request-failed', 'too-many-requests', 'account-exists-with-different-credential'}
              .contains(e.code)) {
        _err(e);
      } else if (mounted) {
        HapticFeedback.heavyImpact();
        showAccountSnack(context, 'account.err_google_web_code'.tr(args: [code]), error: true);
      }
    } finally {
      if (mounted) setState(() => _googleBusy = false);
    }
  }

  /// Sign in with Apple — نفس مسار Google بعد الدخول (بوّابة الحساب ← bootstrap).
  Future<void> _apple() async {
    HapticFeedback.selectionClick();
    setState(() => _appleBusy = true);
    try {
      final u = await AccountService.signInWithApple();
      if (u != null) _toGate();
    } catch (e) {
      final code = e is FirebaseAuthException ? e.code : e.runtimeType.toString();
      debugPrint('account apple sign-in failed: $code');
      if (e is FirebaseAuthException &&
          const {'user-disabled', 'network-request-failed', 'too-many-requests', 'account-exists-with-different-credential'}
              .contains(e.code)) {
        _err(e);
      } else if (mounted) {
        HapticFeedback.heavyImpact();
        // «unknown» (ASAuthorizationError 1000) لا يفيد المستخدم — رسالةٌ بلا رمز.
        showAccountSnack(
            context,
            code == 'unknown' ? 'account.err_apple'.tr() : 'account.err_apple_code'.tr(args: [code]),
            error: true);
      }
    } finally {
      if (mounted) setState(() => _appleBusy = false);
    }
  }

  Future<void> _submitEmail() async {
    final email = _emailCtrl.text.trim();
    final pass = _passCtrl.text;
    if (looksLikeSasUsername(email)) {
      showAccountSnack(context, 'account.err_sas_username'.tr(), error: true, duration: const Duration(seconds: 9));
      return;
    }
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
    if (looksLikeSasUsername(email)) {
      showAccountSnack(context, 'account.err_sas_username'.tr(), error: true, duration: const Duration(seconds: 9));
      return;
    }
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
      compact: true,
      title: signUp ? 'account.signup_title'.tr() : 'account.signin_title'.tr(),
      subtitle: (StorePolicy.hidePurchaseFlows ? 'account.signin_subtitle_neutral' : 'account.signin_subtitle').tr(),
      children: [
        // طرق الدخول أيقوناتٌ في صفٍّ واحد بدل ثلاثة أزرارٍ عريضة — الشاشة كلّها تتّسع
        // بلا تمرير على آيفون ١٣ (طلب المستخدم ٢٠٢٦-١٠-١٤). Apple بحجم Google وبروزه (4.8).
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (AccountService.appleSignInAvailable) ...[
              SizedBox(
                width: _methodTileWidth,
                child: AccountMethodTile(
                  filled: true,
                  icon: const Icon(Icons.apple),
                  caption: 'Apple',
                  semanticLabel: 'account.continue_apple'.tr(),
                  loading: _appleBusy,
                  onTap: _busy || _googleBusy ? null : _apple,
                ),
              ),
              const SizedBox(width: Sp.lg),
            ],
            SizedBox(
              width: _methodTileWidth,
              child: AccountMethodTile(
                icon: const GoogleMark(),
                caption: 'Google',
                semanticLabel: 'account.continue_google'.tr(),
                loading: _googleBusy,
                onTap: _busy || _appleBusy ? null : _google,
              ),
            ),
            // Pro: موظّف ايرث لنك — بلا حساب إيميل؛ يوزر وكلمة سرّ من مديره.
            if (!signUp) ...[
              const SizedBox(width: Sp.lg),
              SizedBox(
                width: _methodTileWidth,
                child: AccountMethodTile(
                  icon: const Icon(Icons.badge_outlined),
                  caption: 'account.employee_short'.tr(),
                  semanticLabel: 'account.employee_entry'.tr(),
                  onTap: _anyBusy ? null : _openEmployeeLogin,
                ),
              ),
            ],
          ],
        ),
        // بعد نافذة Google رجعت بلا دخول (أندرويد) — بديل المتصفّح، سطرٌ واحد لا شريطٌ دائم.
        if (_googleWebOffer) ...[
          const SizedBox(height: Sp.sm),
          Center(
            child: Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: Sp.xs,
              children: [
                Text('account.google_web_offer'.tr(),
                    style: AppType.muted(color: AppColors.textMid)),
                TextButton(
                  onPressed: _anyBusy ? null : _googleWeb,
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.brand,
                    visualDensity: VisualDensity.compact,
                    minimumSize: const Size(48, 40),
                  ),
                  child: Text('account.google_web_action'.tr(),
                      style: AppType.label(color: AppColors.brand)
                          .copyWith(fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: Sp.lg),
        Row(children: [
          Expanded(child: Divider(color: AppColors.border)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Sp.md),
            child: Text('account.or_email'.tr(), style: AppType.muted(color: AppColors.textLow)),
          ),
          Expanded(child: Divider(color: AppColors.border)),
        ]),
        const SizedBox(height: Sp.md),
        AccountCard(
          padding: const EdgeInsets.all(Sp.lg),
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
                const SizedBox(height: Sp.md),
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
                  onTap: _googleBusy || _appleBusy ? null : _submitEmail,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: Sp.xs),
        // الذيل سطرٌ واحد: إنشاء حساب · سياسة الخصوصيّة (App Store 5.1.1(i): ظاهرةٌ قبل أيّ حساب).
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            TextButton(
              onPressed: _anyBusy
                  ? null
                  : () => setState(() {
                        _mode = signUp ? _Mode.signIn : _Mode.signUp;
                        _passCtrl.clear();
                      }),
              child: Text(signUp ? 'account.signin_short'.tr() : 'account.create_short'.tr(),
                  style: AppType.link(color: AppColors.brandAccent)),
            ),
            Text('·', style: AppType.muted(color: AppColors.textLow)),
            TextButton(
              onPressed: () => openPrivacyPolicy(context),
              child: Text('account.privacy_policy'.tr(), style: AppType.link(color: AppColors.textMid)),
            ),
          ],
        ),
        // آيفون: لا جملة «تجربة مجانيّة» على شاشة الدخول — تُقرأ عرضاً تجاريّاً بلا شراءٍ
        // داخل التطبيق (3.1.1). التجربة نفسها تعمل كما هي، والحالة تظهر بعد الدخول.
        if (!StorePolicy.hidePurchaseFlows)
          Text('account.trial_note'.tr(), textAlign: TextAlign.center, style: AppType.muted(color: AppColors.textMid)),
      ],
    );
  }

  /// عرض خانة طريقة الدخول — صغيرةٌ ومتوسّطة (طلب المستخدم: أيقوناتٌ أصغر).
  static const double _methodTileWidth = 76;

  void _openEmployeeLogin() {
    HapticFeedback.selectionClick();
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const EmployeeLoginScreen()));
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
        // App Store 5.1.1(v): حسابٌ أُنشئ ولم يُؤكَّد بريده يُحذف من هنا أيضاً (الخادم يحذف مستخدم
        // المصادقة ولو لم يُنشأ صفّ الحساب بعد).
        AccountTextLink(
          label: 'account.delete_account'.tr(),
          onTap: _busy ? null : () => confirmAndDeleteAccount(context),
          danger: true,
        ),
      ],
    );
  }
}
