import 'dart:async';

import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../api/auth_api.dart';
import '../../core/platform/store_policy.dart';
import '../../services/employee_session.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import '../main_shell.dart';
import 'account_gate_screen.dart';
import 'account_widgets.dart';

/// Pro: دخول موظّف ايرث لنك — يوزر وكلمة سرّ أعطاهما المدير، بلا حساب إيميل.
///
/// النجاح يحفظ الجلسة ([EmployeeSession.completeLogin]) ويفتح [MainShell]
/// مباشرةً، والإقلاع التالي يتخطّى بوّابة الحساب. وهي أيضاً وجهة الموظّف حين
/// تنتهي جلسته أو تُطرد ([message]: انتهت الجلسة / دخولٌ من جهازٍ آخر).
class EmployeeLoginScreen extends StatefulWidget {
  const EmployeeLoginScreen({super.key, this.message});

  /// سببٌ يُعرض عند الوصول (طردٌ/انتهاء جلسة).
  final String? message;

  @override
  State<EmployeeLoginScreen> createState() => _EmployeeLoginScreenState();
}

class _EmployeeLoginScreenState extends State<EmployeeLoginScreen> {
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _passFocus = FocusNode();
  bool _obscure = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _error = widget.message ?? EmployeeSession.kickMessage;
  }

  @override
  void dispose() {
    _userCtrl.dispose();
    _passCtrl.dispose();
    _passFocus.dispose();
    super.dispose();
  }

  /// الرجوع لطبقة الحساب: من شاشة الحساب ← رجوعٌ عاديّ؛ وجذراً (بعد طردٍ/
  /// خروج، أو إقلاعٍ بعد جلسةٍ مباشرة) ← البوّابة. اختيارٌ صريحٌ لطريق الحساب،
  /// فلا يعود الإقلاع التالي إلى هذه الشاشة.
  void _back() {
    if (_busy) return;
    unawaited(EmployeeSession.leaveToAccount());
    final nav = Navigator.of(context);
    if (nav.canPop()) {
      nav.pop();
      return;
    }
    nav.pushReplacement(MaterialPageRoute(builder: (_) => const AccountGateScreen()));
  }

  Future<void> _submit() async {
    if (_busy) return;
    final username = _userCtrl.text.trim();
    final password = _passCtrl.text;
    if (username.isEmpty || password.isEmpty) {
      HapticFeedback.heavyImpact();
      setState(() => _error = 'account.employee_err_empty'.tr());
      return;
    }
    FocusScope.of(context).unfocus();
    HapticFeedback.lightImpact();
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await AuthApi.employeeLogin(username: username, password: password);
    if (!mounted) return;
    switch (result) {
      case final LoginFailure f:
        HapticFeedback.heavyImpact();
        setState(() {
          _busy = false;
          _error = StorePolicy.storeSafe(f.message);
        });
      case final LoginSuccess s:
        final ok = await EmployeeSession.completeLogin(s, username: username);
        if (!mounted) return;
        if (!ok) {
          HapticFeedback.heavyImpact();
          setState(() {
            _busy = false;
            _error = 'login.perms_fetch_failed'.tr();
          });
          return;
        }
        Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const MainShell()),
          (_) => false,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    // أثناء الدخول لا رجوع (ولا زرّ النظام): جلسةٌ تُحفظ بلا انتقالٍ لـMainShell.
    return PopScope(
      canPop: !_busy,
      child: AccountScaffold(
        title: 'account.employee_title'.tr(),
        subtitle: 'account.employee_subtitle'.tr(),
        onBack: _back,
        children: [
          AccountCard(
            child: AutofillGroup(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AccountField(
                    label: 'account.employee_username'.tr(),
                    controller: _userCtrl,
                    textInputAction: TextInputAction.next,
                    textDirection: TextDirection.ltr,
                    autofillHints: const [AutofillHints.username],
                    onSubmitted: (_) => _passFocus.requestFocus(),
                  ),
                  const SizedBox(height: Sp.lg),
                  AccountField(
                    label: 'account.employee_password'.tr(),
                    controller: _passCtrl,
                    focusNode: _passFocus,
                    hint: '••••••••',
                    obscure: _obscure,
                    onToggleObscure: () => setState(() => _obscure = !_obscure),
                    textInputAction: TextInputAction.done,
                    autofillHints: const [AutofillHints.password],
                    onSubmitted: (_) => _submit(),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: Sp.lg),
                    _InlineError(message: _error!),
                  ],
                  const SizedBox(height: Sp.xl),
                  AccountPrimaryButton(
                    label: 'account.employee_submit'.tr(),
                    loading: _busy,
                    onTap: _submit,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// خطأٌ ظاهرٌ تحت الحقول (لا snackbar يختفي): رسالة الخادم أو سبب الطرد.
class _InlineError extends StatelessWidget {
  const _InlineError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: Sp.sm),
        decoration: BoxDecoration(
          color: AppColors.dangerSoftBg,
          borderRadius: BorderRadius.circular(R.md),
          border: Border.all(color: AppColors.dangerSoftBorder),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(Icons.error_outline_rounded, size: 18, color: AppColors.dangerOnSoft),
            ),
            const SizedBox(width: Sp.sm),
            Expanded(
              child: Text(
                message,
                style: AppType.body(color: AppColors.dangerOnSoft).copyWith(height: 1.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
