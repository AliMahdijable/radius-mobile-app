import 'dart:ui' as ui;

import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/auth_api.dart';
import '../theme/colors.dart';
import '../theme/spacing.dart';
import '../theme/typography.dart';
import 'two_factor_sheet.dart';
import '../core/widgets/app_sheet.dart';

/// Pro: دخول الساس مع رمز الصورة **والتحقّق بخطوتين** — مكانٌ واحد لشاشة
/// الدخول و«شركاتي» ومبدّل المدراء. بعض الساسات (الحياة عمارة…) تشترط رمز
/// صورةٍ عند الدخول وبدونه ترفض حتى المعلومات الصحيحة: يحاول الدخول، وإن طلب
/// الساس الرمز تُعرض الصورة ويُعاد الدخول بها حتى ينجح أو يغلق المستخدم
/// النافذة (`captcha-cancelled`).
///
/// ومالكٌ (ساس أو ايرث لنك) فعّل التحقّق بخطوتين من الويب: كلمة السرّ تُقبل
/// والجلسة تُعلَّق حتى الكود ← نافذة الكود ([showTwoFactorSheet]) — أو
/// `2fa-cancelled` إن أُغلقت. فما يُرجَع للشاشة جلسةٌ كاملة أو فشلٌ يُعرض.
class SasCaptchaLogin {
  SasCaptchaLogin._();

  /// تحدّياتٌ متتالية أقصاها: رمز صورة ← كود ← (انتهت المهلة فأُعيد الدخول
  /// وطلب الساس رمزاً جديداً) رمز ← كود. حدٌّ يمنع حلقةً لا تنتهي.
  static const _maxChallenges = 4;

  /// [remember] «حفظ الجلسة» يصل الخادم مع كلّ محاولة (ومعها ما بعد رمز الصورة) — [AuthApi.login].
  static Future<LoginResult> login(
    BuildContext context, {
    required String username,
    required String password,
    String? sasUrl,
    bool? remember,
  }) async {
    var r = await AuthApi.login(username: username, password: password, sasUrl: sasUrl, remember: remember);
    for (var i = 0; i < _maxChallenges; i++) {
      if (r is! LoginFailure || !context.mounted) return r;
      if (r.needsCaptcha) {
        final first = r.captcha!;
        r = await showAppSheet<LoginResult>(
              context: context,
              isScrollControlled: true,
              backgroundColor: AppColors.surfaceSheet,
              barrierColor: AppColors.scrim,
              shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(R.sheet))),
              builder: (_) => _CaptchaSheet(first: first, username: username, password: password, sasUrl: sasUrl, remember: remember),
            ) ??
            const LoginFailure('', code: 'captcha-cancelled');
      } else if (r.needs2fa) {
        r = await showTwoFactorSheet(
              context,
              challenge: r.twoFactor!,
              username: username,
              password: password,
              sasUrl: sasUrl,
              remember: remember,
            ) ??
            const LoginFailure('', code: '2fa-cancelled');
      } else {
        return r;
      }
    }
    return r;
  }
}

class _CaptchaSheet extends StatefulWidget {
  const _CaptchaSheet({required this.first, required this.username, required this.password, this.sasUrl, this.remember});
  final SasCaptcha first;
  final String username;
  final String password;
  final String? sasUrl;
  final bool? remember;

  @override
  State<_CaptchaSheet> createState() => _CaptchaSheetState();
}

class _CaptchaSheetState extends State<_CaptchaSheet> {
  final _ctrl = TextEditingController();
  late SasCaptcha _cap = widget.first;
  String? _error;
  bool _busy = false;
  bool _refreshing = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || _refreshing) return;
    final text = _ctrl.text.trim();
    if (text.isEmpty) {
      setState(() => _error = 'login.captcha_empty'.tr());
      return;
    }
    HapticFeedback.lightImpact();
    setState(() {
      _busy = true;
      _error = null;
    });
    final r = await AuthApi.login(
      username: widget.username,
      password: widget.password,
      sasUrl: widget.sasUrl,
      captchaId: _cap.id,
      captchaText: text,
      remember: widget.remember,
    );
    if (!mounted) return;
    if (r is LoginFailure && r.needsCaptcha) {
      // رمزٌ أو كلمة سرٍّ خاطئة (الساس لا يميّز) ← صورةٌ جديدة في النافذة نفسها.
      HapticFeedback.heavyImpact();
      setState(() {
        _busy = false;
        _cap = r.captcha!;
        _error = r.message;
        _ctrl.clear();
      });
      return;
    }
    Navigator.of(context).pop(r);
  }

  Future<void> _refresh() async {
    if (_busy || _refreshing) return;
    HapticFeedback.selectionClick();
    setState(() => _refreshing = true);
    // بلا رمز ← الخادم يُرجع صورةً جديدة دون محاولة دخولٍ على الساس.
    final r = await AuthApi.login(
        username: widget.username, password: widget.password, sasUrl: widget.sasUrl, remember: widget.remember);
    if (!mounted) return;
    switch (r) {
      case final LoginFailure f when f.needsCaptcha:
        setState(() {
          _refreshing = false;
          _cap = f.captcha!;
          _error = null;
          _ctrl.clear();
        });
      case final LoginFailure f when f.needs2fa:
        Navigator.of(context).pop(f); // دخلَ بلا رمز والمالك يطلب الكود ← نافذة الكود
      case final LoginFailure f when !f.isAccountGate:
        setState(() {
          _refreshing = false;
          _error = f.message;
        });
      default:
        Navigator.of(context).pop(r); // نجح بلا رمز، أو بوّابة الحساب تقرّر
    }
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(R.md),
      borderSide: BorderSide(color: _error != null ? AppColors.error : AppColors.border),
    );
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(Sp.xl, Sp.md, Sp.xl, Sp.lg + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(R.pill)),
              ),
            ),
            const SizedBox(height: Sp.md),
            Text('login.captcha_title'.tr(), textAlign: TextAlign.center, style: AppType.sheetTitle(color: AppColors.textHi)),
            const SizedBox(height: Sp.xs),
            Text('login.captcha_body'.tr(),
                textAlign: TextAlign.center, style: AppType.body(color: AppColors.textMid).copyWith(height: 1.5)),
            const SizedBox(height: Sp.lg),
            Row(
              children: [
                Expanded(
                  child: Container(
                    height: 64,
                    decoration: BoxDecoration(
                      color: AppColors.surfaceInput,
                      borderRadius: BorderRadius.circular(R.md),
                      border: Border.all(color: AppColors.border),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 150),
                      opacity: _refreshing ? 0.35 : 1,
                      child: Image.memory(_cap.image, fit: BoxFit.contain, gaplessPlayback: true),
                    ),
                  ),
                ),
                const SizedBox(width: Sp.sm),
                SizedBox(
                  width: 48,
                  height: 48,
                  child: Material(
                    color: AppColors.brandSoftBg,
                    borderRadius: BorderRadius.circular(R.md),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(R.md),
                      onTap: _refresh,
                      child: Center(
                        child: _refreshing
                            ? SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.brand),
                              )
                            : Tooltip(
                                message: 'login.captcha_refresh'.tr(),
                                child: Icon(Icons.refresh_rounded, color: AppColors.brand, size: 22),
                              ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: Sp.md),
            TextField(
              controller: _ctrl,
              autofocus: true,
              autocorrect: false,
              enableSuggestions: false,
              keyboardType: TextInputType.visiblePassword,
              textCapitalization: TextCapitalization.none,
              textInputAction: TextInputAction.done,
              textAlign: TextAlign.center,
              textDirection: ui.TextDirection.ltr,
              maxLength: 16,
              onSubmitted: (_) => _submit(),
              style: AppType.input(color: AppColors.textHi).copyWith(fontSize: 20, letterSpacing: 4),
              decoration: InputDecoration(
                counterText: '',
                hintText: 'login.captcha_hint'.tr(),
                hintStyle: AppType.input(color: AppColors.textLow),
                filled: true,
                fillColor: AppColors.surfaceInput,
                contentPadding: const EdgeInsets.symmetric(horizontal: Sp.lg, vertical: Sp.md),
                border: border,
                enabledBorder: border,
                focusedBorder: border.copyWith(
                  borderSide: BorderSide(color: _error != null ? AppColors.error : AppColors.brand, width: 1.5),
                ),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: Sp.sm),
              Text(_error!, textAlign: TextAlign.center, style: AppType.muted(color: AppColors.error)),
            ],
            const SizedBox(height: Sp.lg),
            SizedBox(
              height: 50,
              child: Material(
                color: AppColors.brand,
                borderRadius: BorderRadius.circular(R.md),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: _busy ? null : _submit,
                  child: Center(
                    child: _busy
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2.2, color: AppColors.onBrand),
                          )
                        : Text('login.sign_in'.tr(), style: AppType.button(color: AppColors.onBrand)),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
