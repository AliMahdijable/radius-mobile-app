import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/platform/store_policy.dart';
import '../../core/widgets/explain_action.dart';
import '../../services/ai_assistant_state.dart';
import '../../services/app_version.dart';
import '../../services/theme_service.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';

/// عناصر شاشات طبقة الحساب — بنفس لغة شاشة الدخول (`login_screen.dart`):
/// كارت سطحٍ أبيض بحواف R.xl، حقولٌ بتعبئة surfaceInput، وزرٌّ أساسيّ بارتفاع 54.

/// سياسة الخصوصيّة (App Store 5.1.1(i)) — الرابط نفسه في App Store Connect.
const String kPrivacyPolicyUrl = 'https://pro.mysvcs.net/privacy';

/// صفحة الدعم (App Store 1.5) — تواصلٌ عامّ بعيداً عن سياق الاشتراك؛ نفسها رابط Support URL.
const String kSupportUrl = 'https://pro.mysvcs.net/support';

/// يفتح سياسة الخصوصيّة داخل التطبيق (SFSafariViewController / Custom Tab)،
/// وإن تعذّر فبالمتصفّح الخارجيّ.
Future<void> openPrivacyPolicy(BuildContext context) => _openInApp(context, kPrivacyPolicyUrl);

/// يفتح صفحة الدعم بالطريقة نفسها.
Future<void> openSupportPage(BuildContext context) => _openInApp(context, kSupportUrl);

Future<void> _openInApp(BuildContext context, String url) async {
  final uri = Uri.parse(url);
  var ok = false;
  try {
    ok = await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
  } catch (_) {/* نجرّب الخارجيّ */}
  if (!ok) {
    try {
      ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {/* يُعرض الخطأ أدناه */}
  }
  if (!ok && context.mounted) showAccountSnack(context, 'account.err_network'.tr(), error: true);
}

/// [explain] — «اشرحلي» على خطأ الخادم (صريحاً، وإلّا يُستنتج من الردّ المرفوض
/// الذي يعرضه الشريط). لا يظهر إلّا إن قال الخادم إنّ المساعد مفتوح — وإلّا
/// فالشريط كما كان حرفيّاً.
void showAccountSnack(
  BuildContext context,
  String msg, {
  bool error = false,
  Duration? duration,
  ExplainRequest? explain,
}) {
  final m = ScaffoldMessenger.maybeOf(context);
  if (m == null) return;
  final ask = error ? (explain ?? AiAssistantState.explainFor(msg)) : null;
  m.hideCurrentSnackBar();
  m.showSnackBar(SnackBar(
    content: ExplainSnackContent(
      message: msg,
      style: AppType.button(color: AppColors.onBrand),
      request: ask,
      onExplain: () {
        m.hideCurrentSnackBar();
        if (ask != null && context.mounted) openExplain(context, ask);
      },
    ),
    backgroundColor: error ? AppColors.error : AppColors.brand,
    behavior: SnackBarBehavior.floating,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(R.md)),
    margin: const EdgeInsets.all(Sp.lg),
    duration: explainSnackDuration(duration ?? const Duration(seconds: 4), ask),
  ));
}

/// نصٌّ قد يكون مفتاح ترجمة (`account.…`) أو رسالةً عربيّة جاهزة من الخادم.
/// رسالة الخادم على آيفون تمرّ بـ[StorePolicy.storeSafe] (لا «فعّل كوداً»/«رقِّ باقتك»).
String accountText(String keyOrMessage) =>
    keyOrMessage.startsWith('account.') ? keyOrMessage.tr() : StorePolicy.storeSafe(keyOrMessage);

class AccountScaffold extends StatelessWidget {
  const AccountScaffold({
    super.key,
    required this.title,
    this.subtitle,
    required this.children,
    this.onBack,
    this.showLogo = true,
    this.footer = true,
    this.onRefresh,
    this.compact = false,
  });

  final String title;
  final String? subtitle;
  final List<Widget> children;
  final VoidCallback? onBack;
  final bool showLogo;
  final bool footer;

  /// سحبٌ للتحديث — لقائمةٍ تتغيّر من خارج الشاشة («أجهزتي»: جهازٌ يدخل أو
  /// يُزال من جهازٍ آخر). null = بلا سحب، كما كانت الشاشات كلّها.
  final Future<void> Function()? onRefresh;

  /// شاشة الدخول: شعارٌ أصغر ومسافاتٌ أقلّ لتتّسع الشاشة كلّها بلا تمرير على
  /// هاتفٍ متوسّط (آيفون ١٣) — طلب المستخدم ٢٠٢٦-١٠-١٤ («بيها سكرول كلش هواي»).
  final bool compact;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Scaffold(
      backgroundColor: AppColors.bg,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: _refreshable(SingleChildScrollView(
          // المحتوى القصير لا يُسحب بدونها، فلا يصل السحب إلى المؤشّر.
          physics: onRefresh == null ? null : const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: Sp.xxl, vertical: Sp.xl),
          // الآيباد: عمودٌ وسطيّ بعرض نموذجٍ مريح بدل أزرارٍ ممتدّة على عرض الشاشة كلّه.
          // الهاتف أضيق من الحدّ فلا يتغيّر فيه شيء.
          child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 560), child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // شريطٌ علويّ: الرجوع (إن وُجد) في بداية الاتجاه، ومبدّل
              // المظهر في نهايته — فالمستخدم يختار فاتح/داكن/تلقائي من
              // شاشات البداية قبل الدخول، لا من الإعدادات وحدها (كان
              // التطبيق يبقى داكناً حتى يسجّل الدخول ويصل الإعدادات).
              Row(
                children: [
                  if (onBack != null)
                    IconButton(
                      onPressed: onBack,
                      icon: Icon(Icons.arrow_back_rounded, color: AppColors.textHi),
                      tooltip: 'common.back'.tr(),
                      visualDensity: VisualDensity.compact,
                    ),
                  const Spacer(),
                  const AccountThemeToggle(),
                ],
              ),
              if (showLogo) ...[
                SizedBox(height: compact ? Sp.xs : Sp.lg),
                AccountLogo(size: compact ? 84 : 104),
                SizedBox(height: compact ? Sp.md : Sp.xl),
              ],
              Text(title, textAlign: TextAlign.center, style: AppType.title(color: AppColors.textHi)),
              if (subtitle != null) ...[
                const SizedBox(height: Sp.xs),
                Text(subtitle!, textAlign: TextAlign.center, style: AppType.subtitle(color: AppColors.textMid)),
              ],
              SizedBox(height: compact ? Sp.lg : Sp.xl),
              ...children,
              if (footer) ...[
                SizedBox(height: compact ? Sp.lg : Sp.huge),
                Center(
                  child: Text(
                    '${AppVersion.shortVersion}  •  ${'login.footer_copyright'.tr()}',
                    style: AppType.muted(color: AppColors.textLow),
                  ),
                ),
                const SizedBox(height: Sp.lg),
              ],
            ],
          ))),
        )),
      ),
    );
  }

  Widget _refreshable(Widget scroll) {
    final refresh = onRefresh;
    if (refresh == null) return scroll;
    return RefreshIndicator(color: AppColors.brand, onRefresh: refresh, child: scroll);
  }
}

/// مبدّل المظهر على شاشات البداية (تلقائي/فاتح/داكن) — ثلاث حبّاتٍ
/// صغيرة، المختارة مميّزة بلون العلامة. النقر يحفظ فوراً عبر
/// [ThemeService.setMode] فيُعاد بناء كامل التطبيق (`main.dart`) ويتبدّل
/// المظهر في الحال — بلا حاجةٍ لدخولٍ أو وصولٍ لشاشة الإعدادات.
class AccountThemeToggle extends StatelessWidget {
  const AccountThemeToggle({super.key});

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeService.notifier,
      builder: (context, mode, _) {
        Widget seg(ThemeMode m, IconData icon) {
          final selected = mode == m;
          final label = ThemeService.labelFor(m);
          return Semantics(
            button: true,
            selected: selected,
            label: label,
            child: Tooltip(
              message: label,
              child: Material(
                color: selected ? AppColors.brand : Colors.transparent,
                borderRadius: BorderRadius.circular(R.pill),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: selected ? null : () => ThemeService.setMode(m),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: Sp.md, vertical: Sp.sm),
                    child: Icon(
                      icon,
                      size: 18,
                      color: selected ? AppColors.onBrand : AppColors.textMid,
                    ),
                  ),
                ),
              ),
            ),
          );
        }

        return Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(R.pill),
            border: Border.all(color: AppColors.border),
          ),
          padding: const EdgeInsets.all(3),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              seg(ThemeMode.system, Icons.brightness_auto_rounded),
              seg(ThemeMode.light, Icons.light_mode_rounded),
              seg(ThemeMode.dark, Icons.dark_mode_rounded),
            ],
          ),
        );
      },
    );
  }
}

class AccountLogo extends StatelessWidget {
  const AccountLogo({super.key, this.size = 104});
  final double size;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Center(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(R.lg),
          boxShadow: [
            BoxShadow(color: AppColors.brandSoftBg, blurRadius: 28, offset: const Offset(0, 14)),
          ],
        ),
        padding: const EdgeInsets.all(Sp.md),
        child: Image.asset('assets/images/logo.png', fit: BoxFit.contain, cacheWidth: 320),
      ),
    );
  }
}

class AccountCard extends StatelessWidget {
  const AccountCard({super.key, required this.child, this.padding = const EdgeInsets.all(Sp.xl)});
  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Container(
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(R.xl)),
      padding: padding,
      child: child,
    );
  }
}

class AccountField extends StatelessWidget {
  const AccountField({
    super.key,
    required this.label,
    required this.controller,
    this.hint,
    this.keyboardType,
    this.obscure = false,
    this.onToggleObscure,
    this.textInputAction,
    this.onSubmitted,
    this.focusNode,
    this.autofillHints,
    this.textCapitalization = TextCapitalization.none,
    this.textDirection,
  });

  final String label;
  final TextEditingController controller;
  final String? hint;
  final TextInputType? keyboardType;
  final bool obscure;
  final VoidCallback? onToggleObscure;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
  final FocusNode? focusNode;
  final Iterable<String>? autofillHints;
  final TextCapitalization textCapitalization;
  final TextDirection? textDirection;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    OutlineInputBorder b(Color c, [double w = 1]) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(R.md),
          borderSide: BorderSide(color: c, width: w),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.only(start: Sp.xs, bottom: Sp.sm),
          child: Text(label, style: AppType.label(color: AppColors.textMid)),
        ),
        TextField(
          controller: controller,
          focusNode: focusNode,
          keyboardType: keyboardType,
          obscureText: obscure,
          autocorrect: false,
          enableSuggestions: !obscure && keyboardType != TextInputType.emailAddress,
          textInputAction: textInputAction,
          onSubmitted: onSubmitted,
          autofillHints: autofillHints,
          textCapitalization: textCapitalization,
          textDirection: textDirection,
          style: AppType.input(color: AppColors.textHi),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: AppType.input(color: AppColors.textLow),
            filled: true,
            fillColor: AppColors.surfaceInput,
            contentPadding: const EdgeInsets.symmetric(horizontal: Sp.lg, vertical: Sp.md),
            border: b(AppColors.border),
            enabledBorder: b(AppColors.border),
            focusedBorder: b(AppColors.brand, 1.5),
            suffixIcon: onToggleObscure == null
                ? null
                : IconButton(
                    splashRadius: 18,
                    icon: Icon(obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                        color: AppColors.textMid, size: 20),
                    onPressed: onToggleObscure,
                  ),
          ),
        ),
      ],
    );
  }
}

class AccountPrimaryButton extends StatelessWidget {
  const AccountPrimaryButton({super.key, required this.label, required this.onTap, this.loading = false, this.icon});
  final String label;
  final VoidCallback? onTap;
  final bool loading;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final enabled = onTap != null && !loading;
    return SizedBox(
      height: 54,
      child: Material(
        color: enabled || loading ? AppColors.brand : AppColors.borderStrong,
        borderRadius: BorderRadius.circular(R.md),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: enabled ? onTap : null,
          child: Center(
            child: loading
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.2, color: AppColors.onBrand),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (icon != null) ...[
                        Icon(icon, color: AppColors.onBrand, size: 20),
                        const SizedBox(width: Sp.sm),
                      ],
                      Text(label, style: AppType.button(color: AppColors.onBrand)),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

class AccountOutlineButton extends StatelessWidget {
  const AccountOutlineButton({super.key, required this.label, required this.onTap, this.leading, this.loading = false});
  final String label;
  final VoidCallback? onTap;
  final Widget? leading;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return SizedBox(
      height: 54,
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.md),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: loading ? null : onTap,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(R.md),
              border: Border.all(color: AppColors.borderStrong),
            ),
            alignment: Alignment.center,
            child: loading
                ? SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.2, color: AppColors.brand),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (leading != null) ...[leading!, const SizedBox(width: Sp.sm)],
                      Text(label, style: AppType.button(color: AppColors.textHi)),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

class AccountTextLink extends StatelessWidget {
  const AccountTextLink({super.key, required this.label, required this.onTap, this.danger = false});
  final String label;
  final VoidCallback? onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Center(
      child: TextButton(
        onPressed: onTap,
        child: Text(label, style: AppType.link(color: danger ? AppColors.error : AppColors.brandAccent)),
      ),
    );
  }
}

/// حرف G بألوان المشروع — بلا أصلٍ مرسوم لشعار Google (والقاعدة: لا ألوان خامّة).
class GoogleMark extends StatelessWidget {
  const GoogleMark({super.key});
  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Container(
      width: 24,
      height: 24,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.borderStrong),
      ),
      child: Text('G', style: AppType.button(color: AppColors.textHi).copyWith(fontSize: 13, height: 1)),
    );
  }
}
