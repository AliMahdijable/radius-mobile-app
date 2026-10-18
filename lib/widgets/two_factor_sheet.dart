import 'dart:async';
import 'dart:ui' as ui;

import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../api/auth_api.dart';
import '../core/util/bidi.dart';
import '../theme/colors.dart';
import '../theme/spacing.dart';
import '../theme/typography.dart';

/// Pro: نافذة كود التحقّق بخطوتين عند الدخول.
///
/// يفتحها [SasCaptchaLogin] حين يردّ الخادم `requires2fa` — مالك ساس أو ايرث
/// لنك فعّل التحقّق من الويب («الإعدادات ← التحقّق بخطوتين»). ومسارها مسار
/// الويب نفسه (`Login.tsx`): كودٌ من ٦ أرقام ← `POST /api/auth/2fa/verify
/// {tempId, code}`، وعدّادٌ لمهلة الجلسة المعلَّقة (دقيقتان).
///
/// وحين تنتهي المهلة: «إعادة الدخول» بكلمة السرّ نفسها تعطي مهلةً جديدة —
/// هي «إعادة الإرسال» هنا، فالكود لا يُرسَل أصلاً بل يولّده تطبيق المصادقة.
///
/// تُرجع: [LoginSuccess] بعد الكود · فشلاً تقرّره الشاشة (بوّابة الحساب، حدّ
/// الأجهزة، رمز صورةٍ طلبه الساس عند إعادة الدخول) · `null` إن أُغلقت.
Future<LoginResult?> showTwoFactorSheet(
  BuildContext context, {
  required TwoFactorChallenge challenge,
  required String username,
  required String password,
  String? sasUrl,
}) {
  return showModalBottomSheet<LoginResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surfaceSheet,
    barrierColor: AppColors.scrim,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(R.sheet))),
    builder: (_) => TwoFactorSheet(
      challenge: challenge,
      username: username,
      password: password,
      sasUrl: sasUrl,
    ),
  );
}

class TwoFactorSheet extends StatefulWidget {
  const TwoFactorSheet({
    super.key,
    required this.challenge,
    required this.username,
    required this.password,
    this.sasUrl,
  });

  final TwoFactorChallenge challenge;

  /// بيانات الدخول نفسها — لإعادة الدخول حين تنتهي المهلة.
  final String username;
  final String password;
  final String? sasUrl;

  /// ساعة العدّاد — منفذ الاختبار وحده.
  ///
  /// ساعة الحائط لا عدّ النبضات: المستخدم يخرج إلى تطبيق المصادقة ليقرأ
  /// الكود، ومؤقّتات التطبيق تتوقّف وهو في الخلفيّة — فعدّادٌ ينقص مع كلّ
  /// نبضة يرجع وقد بقي له أكثر ممّا بقي للخادم.
  @visibleForTesting
  static DateTime Function() clock = DateTime.now;

  @override
  State<TwoFactorSheet> createState() => _TwoFactorSheetState();
}

class _TwoFactorSheetState extends State<TwoFactorSheet>
    with WidgetsBindingObserver {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();
  late TwoFactorChallenge _challenge;
  late DateTime _deadline;
  Timer? _ticker;
  int _remaining = 0;

  /// الخادم قال إنّ الجلسة المعلَّقة لم تعد (انتهت قبل عدّادنا، أو أُعيد
  /// تشغيله) — كالانتهاء تماماً: لا كود يصلح بعدها.
  bool _gone = false;
  bool _busy = false;
  bool _relogging = false;
  String? _error;

  bool get _expired => _gone || _remaining <= 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start(widget.challenge);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // عودةٌ من تطبيق المصادقة: العدّاد بالوقت الحقيقيّ فوراً لا بعد نبضة.
    if (state == AppLifecycleState.resumed && mounted) setState(_tick);
  }

  /// يبدأ مهلة [c] من الآن — أوّل مرّة، وبعد كلّ إعادة دخول.
  void _start(TwoFactorChallenge c) {
    _challenge = c;
    _deadline = TwoFactorSheet.clock().add(Duration(seconds: c.expiresIn));
    _gone = false;
    _tick();
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      // يُعاد البناء حين يتغيّر المعروض وحده (الثانية، أو رسالة الانتهاء).
      final before = (_remaining, _error);
      _tick();
      if ((_remaining, _error) != before) setState(() {});
    });
  }

  /// الثواني الباقية بالتقريب لأعلى (١٫٢ث تُعرض «0:02» لا «0:01» — والصفر
  /// انتهاءٌ فعلاً).
  void _tick() {
    final wasExpired = _expired;
    final ms = _deadline.difference(TwoFactorSheet.clock()).inMilliseconds;
    _remaining = ms <= 0 ? 0 : (ms + 999) ~/ 1000;
    if (_remaining > 0) return;
    _ticker?.cancel();
    _ticker = null;
    if (!wasExpired) {
      _error = 'login.twofa_expired'.tr();
      _ctrl.clear();
      HapticFeedback.heavyImpact();
    }
  }

  void _onChanged(String v) {
    // يُعاد البناء مع كلّ رقم: زرّ التأكيد يتفعّل عند السادس.
    setState(() => _error = null);
    // والرقم السادس يرسل وحده (لا ضغطة زائدة) — ولصقُ الكود كاملاً كذلك.
    if (v.length == 6) _submit();
  }

  /// بعد الإطار: حقلٌ عاد مفعَّلاً في هذا البناء لا يقبل التركيز قبله.
  void _refocus() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_expired) _focus.requestFocus();
      });

  Future<void> _submit() async {
    if (_busy || _relogging || _expired) return;
    final code = _ctrl.text.replaceAll(RegExp(r'\D'), '');
    if (code.length != 6) {
      setState(() => _error = 'login.twofa_need6'.tr());
      return;
    }
    HapticFeedback.lightImpact();
    setState(() {
      _busy = true;
      _error = null;
    });
    final r = await AuthApi.verify2fa(tempId: _challenge.tempId, code: code);
    if (!mounted) return;
    if (r is LoginSuccess) {
      Navigator.of(context).pop(r);
      return;
    }
    final f = r as LoginFailure;
    HapticFeedback.heavyImpact();
    setState(() {
      _busy = false;
      _error = f.message;
      if (f.code == '2fa-expired') {
        _gone = true;
        _ticker?.cancel();
        _ticker = null;
        _ctrl.clear();
      } else if (f.code == '2fa-invalid') {
        // كودٌ خاطئ: الجلسة باقية — يُمسح ليكتب الكود التالي من جديد (كالويب).
        _ctrl.clear();
      }
      // وغيرهما (شبكة/خادم متعثّر): يبقى الكود ليُعاد بضغطة.
    });
    _refocus();
  }

  /// إعادة الدخول بكلمة السرّ نفسها — مهلةٌ جديدة ومعرّفٌ جديد.
  Future<void> _relogin() async {
    if (_busy || _relogging) return;
    HapticFeedback.selectionClick();
    setState(() {
      _relogging = true;
      _error = null;
    });
    final r = await AuthApi.login(
      username: widget.username,
      password: widget.password,
      sasUrl: widget.sasUrl,
    );
    if (!mounted) return;
    switch (r) {
      case final LoginFailure f when f.needs2fa:
        setState(() {
          _relogging = false;
          _ctrl.clear();
          _start(f.twoFactor!);
        });
        _refocus();
      case final LoginFailure f
          when !f.needsCaptcha && !f.isAccountGate && !f.isCancelled:
        // رفضٌ أو شبكة — يبقى هنا بالسبب، وتبقى «إعادة الدخول».
        setState(() {
          _relogging = false;
          _error = f.message;
        });
      default:
        // جلسةٌ بلا كود (عُطِّل التحقّق بينهما)، أو رمز صورةٍ يطلبه الساس، أو
        // بوّابة الحساب/حدّ الأجهزة — للمستدعي.
        Navigator.of(context).pop(r);
    }
  }

  String get _mmss {
    final m = _remaining ~/ 60;
    final s = (_remaining % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final expired = _expired;
    final hasError = _error != null;
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(R.md),
      borderSide:
          BorderSide(color: hasError ? AppColors.error : AppColors.border),
    );
    final busy = _busy || _relogging;
    final VoidCallback? onPrimary = busy
        ? null
        : expired
            ? _relogin
            : (_ctrl.text.length == 6 ? _submit : null);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(Sp.xl, Sp.md, Sp.xl,
            Sp.lg + MediaQuery.viewInsetsOf(context).bottom),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                      color: AppColors.border,
                      borderRadius: BorderRadius.circular(R.pill)),
                ),
              ),
              const SizedBox(height: Sp.lg),
              Center(
                child: Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: AppColors.brandSoftBg,
                    borderRadius: BorderRadius.circular(R.lg),
                  ),
                  child: Icon(LucideIcons.shieldCheck,
                      color: AppColors.brand, size: 26),
                ),
              ),
              const SizedBox(height: Sp.md),
              Text('login.twofa_title'.tr(),
                  textAlign: TextAlign.center,
                  style: AppType.sheetTitle(color: AppColors.textHi)),
              const SizedBox(height: Sp.xs),
              Text('login.twofa_body'.tr(),
                  textAlign: TextAlign.center,
                  style: AppType.body(color: AppColors.textMid)
                      .copyWith(height: 1.5)),
              const SizedBox(height: Sp.lg),
              Text('login.twofa_code'.tr(),
                  style: AppType.label(color: AppColors.textMid)),
              const SizedBox(height: Sp.sm),
              TextField(
                controller: _ctrl,
                focusNode: _focus,
                autofocus: true,
                // أثناء التحقّق للقراءة فقط لا معطَّلاً: التعطيل يُسقط التركيز
                // فتختفي لوحة المفاتيح وتعود مع كلّ محاولة.
                enabled: !expired,
                readOnly: busy,
                autocorrect: false,
                enableSuggestions: false,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.oneTimeCode],
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(6),
                ],
                textAlign: TextAlign.center,
                textDirection: ui.TextDirection.ltr,
                onChanged: _onChanged,
                onSubmitted: (_) => _submit(),
                style: AppType.input(color: AppColors.textHi).copyWith(
                  fontSize: 24,
                  letterSpacing: 10,
                  fontFeatures: const [ui.FontFeature.tabularFigures()],
                ),
                decoration: InputDecoration(
                  hintText: '000000',
                  hintStyle: AppType.input(color: AppColors.textLow)
                      .copyWith(fontSize: 24, letterSpacing: 10),
                  filled: true,
                  fillColor: AppColors.surfaceInput,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: Sp.lg, vertical: Sp.md),
                  border: border,
                  enabledBorder: border,
                  disabledBorder: border,
                  focusedBorder: border.copyWith(
                    borderSide: BorderSide(
                        color: hasError ? AppColors.error : AppColors.brand,
                        width: 1.5),
                  ),
                ),
              ),
              const SizedBox(height: Sp.sm),
              if (!expired)
                Text(
                  'login.twofa_countdown'.tr(args: [iso(_mmss)]),
                  textAlign: TextAlign.center,
                  style: AppType.muted(
                    color:
                        _remaining <= 20 ? AppColors.error : AppColors.textMid,
                  ),
                ),
              if (hasError) ...[
                const SizedBox(height: Sp.xs),
                Text(_error!,
                    textAlign: TextAlign.center,
                    style: AppType.muted(color: AppColors.error)),
              ],
              const SizedBox(height: Sp.lg),
              SizedBox(
                height: 50,
                child: Material(
                  color: onPrimary == null && !busy
                      ? AppColors.borderStrong
                      : AppColors.brand,
                  borderRadius: BorderRadius.circular(R.md),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: onPrimary,
                    child: Center(
                      child: busy
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2.2, color: AppColors.onBrand),
                            )
                          : Text(
                              (expired
                                      ? 'login.twofa_relogin'
                                      : 'login.twofa_verify')
                                  .tr(),
                              style: AppType.button(color: AppColors.onBrand)),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: Sp.xs),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text('common.cancel'.tr(),
                    style: AppType.button(color: AppColors.textMid)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
