import 'dart:io' show Platform;

import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../api/account_api.dart';
import '../../api/auth_api.dart';
import '../../core/platform/store_policy.dart';
import '../../services/company_creds_store.dart';
import '../../services/sas_login_flow.dart';
import '../../services/saved_profiles_store.dart';
import '../../theme/colors.dart';
import '../../theme/typography.dart';
import '../../widgets/sas_captcha_sheet.dart';
import '../login_screen.dart';
import '../main_shell.dart';
import 'account_gate_screen.dart';
import 'my_devices_screen.dart';
import 'subscription_screen.dart' show AccountSubscriptionStatusX;

/// ما يختلف بين مدخلَي دخول الشركة — «شركاتي» (شاشة الحساب، بلا جلسة شركةٍ
/// تحتها) وورقة «تبديل الشركة» (فوق الرئيسيّة، وجلسة الشركة الحاليّة قائمة).
/// الخطوات نفسها في [CompanyOpenFlow.open]؛ هنا ما يخصّ الشاشة وحدها.
class CompanyOpenHost {
  const CompanyOpenHost({
    required this.setBusy,
    required this.showError,
    required this.accountMe,
    required this.openSubscription,
    this.afterLoginForm,
    this.beforeSessionSwap,
    this.sessionSwapFailed,
  });

  /// الدوّارة على صفّ الشركة أثناء الدخول.
  final void Function(bool busy) setBusy;

  /// رسالةٌ للمدير: شريط «شركاتي»، أو إشعارٌ فوق الورقة.
  final void Function(String message, {Duration? duration}) showError;

  /// حساب Pro — يُسأل عند «انتهى الاشتراك» وحده (إعفاء سوبرنت).
  final Future<AccountMe?> Function() accountMe;

  /// «تفعيل كود» (أندرويد) من نافذة «الشركة تحتاج باقة».
  final Future<void> Function() openSubscription;

  /// بعد إغلاق نموذج الدخول — «شركاتي» تعيد قائمتها (ربما أُضيفت شركة).
  final Future<void> Function()? afterLoginForm;

  /// قُبلت كلمة السرّ — قبل مسح الجلسة الحاليّة وحفظ الجديدة. الورقة تغطّي
  /// الرئيسيّة هنا فلا تُرى ترويستها تتبدّل خلفها أثناء التبديل.
  final void Function(LinkedCompany company)? beforeSessionSwap;

  /// تعذّر حفظ الجلسة الجديدة بعد أن مُسحت السابقة. افتراضاً [showError]
  /// («شركاتي»)؛ الورقة لا تبقى على رئيسيّةٍ مُسحت جلستها.
  final void Function(String message, {Duration? duration})? sessionSwapFailed;
}

/// دخول شركةٍ مربوطة بحساب Pro — **مسار «شركاتي» نفسه** من كلّ مدخل:
/// شاشة «شركاتي» ([CompaniesScreen]) وورقة «تبديل الشركة» في ترويسة الرئيسيّة.
///
/// كلمة السرّ المحفوظة على الجهاز لهذه الشركة+اليوزر ⇒ دخول الساس بها (رمز
/// الصورة والتحقّق بخطوتين إن طلبهما) ⇒ ما بعد الدخول في مكانه الواحد
/// ([SasLoginFlow.completeSafely]) ⇒ التطبيق كلّه من جديد على الشركة
/// ([MainShell]). لا كلمة سرٍّ محفوظة ⇒ نموذج الدخول بالرابط واليوزر معبّأين.
///
/// ⚠️ الجلسة القائمة لا تُمسّ قبل أن يقبل الخادم الدخول: المسح داخل
/// `completeSafely` بعد ردّه. فدخولٌ مرفوض (كلمة سرٍّ تغيّرت، حدّ الأجهزة…)
/// يُبقي المدير في شركته كما كان.
///
/// ٢٣ أكتوبر (المالك: تبديلٌ بلا خروجٍ ودخول): **أوّلاً «استئناف الشركة»** ([AccountApi.resumeCompany]) — جلستها
/// المحفوظة بالخادم بلا كلمة سرٍّ ولا رمز صورة، فالتبديل لحظيّ وحتى لشركةٍ لا كلمة سرٍّ لها على هذا الجهاز. وتعذّره
/// لأيّ سبب ⇒ الطريق أعلاه كما كان حرفاً (هو من يقول السبب إن رُفض).
class CompanyOpenFlow {
  CompanyOpenFlow._();

  /// منفذا الاختبار وحده: ما بعد الدخول، والغلاف الذي يُفتح بعده. في
  /// `flutter test` لا خزنة ولا مجلّدات منصّة، فيُستبدلان ليُرى أنّ الطريق
  /// واحد: ماذا يُمرَّر لإكمال الدخول، وأنّ التطبيق يُفتح من جديد.
  @visibleForTesting
  static Future<SasLoginOutcome> Function(
    LoginSuccess s, {
    required String username,
    required String? password,
    required String sasUrl,
    required bool remember,
    String? companyLabel,
    String? sasCode,
  }) completeSession = SasLoginFlow.completeSafely;

  @visibleForTesting
  static Widget Function() shellBuilder = () => const MainShell();

  /// «استئناف الشركة» من الخادم — منفذ الاختبار مثل أخويه أعلاه.
  @visibleForTesting
  static Future<LoginResult?> Function(LinkedCompany c) resumeSession = AccountApi.resumeCompany;

  /// رفضٌ يخصّ **الشركة** لا الحساب — رسالته تُعرض ويبقى المدير مكانه.
  ///
  /// `LoginFailure.isAccountGate` يعدّ كلّ رمزٍ غير المستثنى بوّابة حساب،
  /// فكانت «شركاتي» تُرسله للبوّابة فترجعه إليها بلا كلمة («حدّ الشركات»
  /// رسالته واضحة ثمّ تضيع). ومن ورقة «تبديل الشركة» كان ذلك يُخرجه من
  /// شركته المفتوحة لرفضٍ لا يخصّها.
  static const companyRefusals = {
    'company-limit',
    'ftth-web-only',
    'ftth-2fa',
  };

  static Future<void> open(
    BuildContext context,
    LinkedCompany c,
    CompanyOpenHost host,
  ) async {
    HapticFeedback.selectionClick();
    final url = c.sasUrl ?? '';
    final pass = await CompanyCredsStore.passwordFor(url, c.username);
    // «مسح الحسابات المحفوظة»: الجهاز نسي حساباته — شركةٌ بلا كلمة سرٍّ عليه لا تُستأنف بضغطة، يُطلب دخولها من جديد.
    final forgotten = pass == null && await CompanyCredsStore.forgotten();
    if (!context.mounted) return;
    // الطريق السريع: جلسة الشركة من الخادم. لا نجاح ⇒ لا شيء تغيّر، ويكمل الدخول المعتاد بلا رسالةٍ إضافيّة.
    if (!c.isEmployee && !forgotten) {
      host.setBusy(true);
      final resumed = await resumeSession(c);
      if (!context.mounted) return;
      if (resumed is LoginSuccess) {
        await _enter(context, c, host, resumed, url: url, password: pass);
        return;
      }
    }
    if (pass == null) {
      host.setBusy(false);
      await openLoginForm(context, c, host);
      return;
    }
    host.setBusy(true);
    final res = await SasCaptchaLogin.login(context,
        username: c.username, password: pass, sasUrl: url);
    if (!context.mounted) return;
    switch (res) {
      case LoginSuccess():
        await _enter(context, c, host, res, url: url, password: pass);
      case final LoginFailure f:
        host.setBusy(false);
        // أغلق نافذة رمز الصورة أو كود التحقّق بخطوتين — لا رسالة ولا نموذج.
        // (كان ردّ «أدخل كود 2FA» بلا رمز خطأٍ فيُعاد نموذج كلمة السرّ أدناه في حلقة.)
        if (f.isCancelled) return;
        // حدّ الأجهزة — قبل البوّابة: كان رمز بوّابةٍ فيرتدّ المستخدم إلى «شركاتي»
        // بلا كلمة، عالقاً. «أجهزتي» تحرّر مكاناً ثمّ يُعاد هذا الدخول فوراً.
        if (f.isDeviceLimit) {
          HapticFeedback.heavyImpact();
          if (await showDeviceLimitSheet(context, message: f.message) &&
              context.mounted) {
            await open(context, c, host);
          }
          return;
        }
        if (!companyRefusals.contains(f.code) &&
            await _handleGate(context, f, host)) {
          return;
        }
        HapticFeedback.heavyImpact();
        host.showError(StorePolicy.storeSafe(f.message));
        // كلمة سرٍّ تغيّرت في الساس: نفتح النموذج ليكتبها من جديد.
        if (f.code == null && context.mounted) {
          await openLoginForm(context, c, host);
        }
    }
  }

  /// قُبلت الجلسة (استئنافاً أو دخولاً) ⇒ تحلّ محلّ الحاليّة ثمّ التطبيق كلّه من جديد على الشركة. [password] `null`:
  /// استئنافٌ بلا كلمة سرٍّ على هذا الجهاز — لا يُكتب فوق المحفوظ شيء.
  static Future<void> _enter(
    BuildContext context,
    LinkedCompany c,
    CompanyOpenHost host,
    LoginSuccess res, {
    required String url,
    required String? password,
  }) async {
    host.beforeSessionSwap?.call(c);
    // فتح شركةٍ = صفحتها المربوطة من جديد: أيّ تبديلٍ لمديرٍ فرعيٍّ سبقه
    // انتهى، فلا «العودة لـ…» في «الصفحات» بعده (يخصّ الجلسة السابقة).
    try {
      await SavedProfilesStore.clearOriginal();
    } catch (_) {/* لا يوقف الدخول — والقراءة تتحقّق من الشركة أيضاً */}
    // اسم الشركة وكودها من «شركاتي» — يُعرضان أعلى الواجهة بعد الدخول.
    final out = await completeSession(res,
        username: c.username,
        password: password,
        sasUrl: url,
        remember: true,
        companyLabel: c.label,
        sasCode: c.sasCode);
    if (!context.mounted) return;
    host.setBusy(false);
    final failed = host.sessionSwapFailed ?? host.showError;
    if (out == SasLoginOutcome.ok) {
      Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => shellBuilder()),
        (_) => false,
      );
    } else if (out == SasLoginOutcome.storageFailed) {
      failed(
          (Platform.isAndroid
                  ? 'login.save_failed_android'
                  : 'login.save_failed')
              .tr(),
          duration: const Duration(seconds: 9));
    } else {
      failed('login.perms_fetch_failed'.tr());
    }
  }

  /// نموذج دخول الساس لهذه الشركة: الرابط واليوزر معبّآن واسمها في بطاقتها.
  static Future<void> openLoginForm(
    BuildContext context,
    LinkedCompany c,
    CompanyOpenHost host,
  ) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => LoginScreen(
        initialSasUrl: c.sasUrl ?? '',
        initialUsername: c.username,
        initialCompanyLabel: c.label,
        initialSasCode: c.sasCode,
        fromCompanies: true,
      ),
    ));
    if (context.mounted) await host.afterLoginForm?.call();
  }

  /// رموز بوّابة الحساب من الخادم: انتهى الاشتراك/الحساب معطّل… ← البوّابة تقرّر.
  static Future<bool> _handleGate(
    BuildContext context,
    LoginFailure f,
    CompanyOpenHost host,
  ) async {
    if (!f.isAccountGate) return false;
    // حسابٌ مجّانيّ دائم (إعفاء سوبرنت) يفتح شركةً أخرى فيرفضها الخادم باشتراكٍ منتهٍ: الإعفاء يخصّ
    // سوبرنت وحدها. البوّابة تقرأ الحساب فعّالاً فكانت تعيده إلى «شركاتي» بلا كلمة — نبقى ونقول السبب.
    if (f.code == 'subscription-ended') {
      final me = await host.accountMe();
      if (!context.mounted) return true;
      if (me != null && me.subscription.isFreeForever) {
        HapticFeedback.heavyImpact();
        _showCompanyNeedsPlan(context, host);
        return true;
      }
    }
    Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AccountGateScreen()),
      (_) => false,
    );
    return true;
  }

  /// الشركة المرفوضة لحسابٍ مجّانيّ لسوبرنت وحدها. آيفون: سطرٌ محايد بلا دعوةٍ لتفعيلٍ (3.1.1)؛
  /// أندرويد: السبب + «تفعيل كود» إلى شاشة الاشتراك.
  static Future<void> _showCompanyNeedsPlan(
    BuildContext context,
    CompanyOpenHost host,
  ) async {
    if (StorePolicy.hidePurchaseFlows) {
      host.showError('account.company_not_active_neutral'.tr());
      return;
    }
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('account.company_needs_plan_title'.tr(),
            style: AppType.sheetTitle(color: AppColors.textHi)),
        content: Text('account.company_needs_plan_body'.tr(),
            style: AppType.subtitle(color: AppColors.textMid)
                .copyWith(height: 1.55)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('common.close'.tr(),
                style: AppType.button(color: AppColors.textMid)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('account.company_needs_plan_action'.tr(),
                style: AppType.button(color: AppColors.brand)),
          ),
        ],
      ),
    );
    if (go == true && context.mounted) await host.openSubscription();
  }
}
