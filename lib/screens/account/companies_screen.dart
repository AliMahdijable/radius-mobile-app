import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../api/account_api.dart';
import '../../api/auth_api.dart';
import '../../core/platform/store_policy.dart';
import '../../services/account_service.dart';
import '../../services/company_creds_store.dart';
import '../../services/sas_login_flow.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import '../../widgets/sas_captcha_sheet.dart';
import '../login_screen.dart';
import '../main_shell.dart';
import 'account_gate_screen.dart';
import 'account_login_screen.dart';
import 'account_settings_card.dart' show confirmAndDeleteAccount;
import 'account_widgets.dart';
import 'my_devices_screen.dart';
import 'subscription_screen.dart';

/// Pro البند ٤ — الطبقة ②: «شركاتي». شركات الحساب يعرفها الخادم (كلّ دخول
/// ساسٍ ناجح بحساب الإيميل يربط شركته)، وكلمات سرّها على الجهاز. ضغطةٌ على
/// شركة = دخول ساسها مباشرةً؛ «إضافة شركة» = شاشة دخول الساس برابطها.
class CompaniesScreen extends StatefulWidget {
  const CompaniesScreen({super.key, required this.me});
  final AccountMe me;

  @override
  State<CompaniesScreen> createState() => _CompaniesScreenState();
}

class _CompaniesScreenState extends State<CompaniesScreen> {
  List<LinkedCompany>? _items;
  String? _error;
  String? _opening; // مفتاح الشركة التي يُدخَل إليها الآن
  late AccountMe _me = widget.me;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final items = await AccountApi.companies();
      if (mounted) setState(() => _items = items);
    } on AccountApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'account.err_network');
    }
  }

  String _keyOf(LinkedCompany c) => '${c.sasCode}|${c.username}';

  Future<void> _open(LinkedCompany c) async {
    if (_opening != null) return;
    HapticFeedback.selectionClick();
    final url = c.sasUrl ?? '';
    final pass = await CompanyCredsStore.passwordFor(url, c.username);
    if (!mounted) return;
    if (pass == null) {
      await _addOrLogin(sasUrl: url, username: c.username, company: c);
      return;
    }
    setState(() => _opening = _keyOf(c));
    final res = await SasCaptchaLogin.login(context, username: c.username, password: pass, sasUrl: url);
    if (!mounted) return;
    switch (res) {
      case LoginSuccess():
        // اسم الشركة وكودها من «شركاتي» — يُعرضان أعلى الواجهة بعد الدخول.
        final out = await SasLoginFlow.complete(res,
            username: c.username, password: pass, sasUrl: url, remember: true,
            companyLabel: c.label, sasCode: c.sasCode);
        if (!mounted) return;
        setState(() => _opening = null);
        if (out == SasLoginOutcome.ok) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const MainShell()),
            (_) => false,
          );
        } else {
          showAccountSnack(context,
              (out == SasLoginOutcome.needs2fa ? 'login.needs_2fa' : 'login.perms_fetch_failed').tr(),
              error: out != SasLoginOutcome.needs2fa);
        }
      case final LoginFailure f:
        setState(() => _opening = null);
        if (f.isCancelled) return;
        // حدّ الأجهزة — قبل البوّابة: كان رمز بوّابةٍ فيرتدّ المستخدم إلى هنا
        // بلا كلمة، عالقاً. «أجهزتي» تحرّر مكاناً ثمّ يُعاد هذا الدخول فوراً.
        if (f.isDeviceLimit) {
          HapticFeedback.heavyImpact();
          if (await showDeviceLimitSheet(context, message: f.message) && mounted) await _open(c);
          return;
        }
        if (_handleGate(f)) return;
        HapticFeedback.heavyImpact();
        showAccountSnack(context, StorePolicy.storeSafe(f.message), error: true);
        // كلمة سرٍّ تغيّرت في الساس: نفتح النموذج ليكتبها من جديد.
        if (f.code == null) await _addOrLogin(sasUrl: url, username: c.username, company: c);
    }
  }

  /// رموز بوّابة الحساب من الخادم: انتهى الاشتراك/الحساب معطّل… ← البوّابة تقرّر.
  bool _handleGate(LoginFailure f) {
    if (!f.isAccountGate) return false;
    // حسابٌ مجّانيّ دائم (إعفاء سوبرنت) يفتح شركةً أخرى فيرفضها الخادم باشتراكٍ منتهٍ: الإعفاء يخصّ
    // سوبرنت وحدها. البوّابة تقرأ الحساب فعّالاً فكانت تعيده إلى هنا بلا كلمة — نبقى ونقول السبب.
    if (f.code == 'subscription-ended' && _me.subscription.isFreeForever) {
      HapticFeedback.heavyImpact();
      _showCompanyNeedsPlan();
      return true;
    }
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AccountGateScreen()),
      (_) => false,
    );
    return true;
  }

  /// الشركة المرفوضة لحسابٍ مجّانيّ لسوبرنت وحدها. آيفون: سطرٌ محايد بلا دعوةٍ لتفعيلٍ (3.1.1)؛
  /// أندرويد: السبب + «تفعيل كود» إلى شاشة الاشتراك.
  Future<void> _showCompanyNeedsPlan() async {
    if (StorePolicy.hidePurchaseFlows) {
      showAccountSnack(context, 'account.company_not_active_neutral'.tr(), error: true);
      return;
    }
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('account.company_needs_plan_title'.tr(), style: AppType.sheetTitle(color: AppColors.textHi)),
        content: Text('account.company_needs_plan_body'.tr(),
            style: AppType.subtitle(color: AppColors.textMid).copyWith(height: 1.55)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('common.close'.tr(), style: AppType.button(color: AppColors.textMid)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('account.company_needs_plan_action'.tr(), style: AppType.button(color: AppColors.brand)),
          ),
        ],
      ),
    );
    if (go == true && mounted) await _openSubscription();
  }

  Future<void> _addOrLogin({String? sasUrl, String? username, LinkedCompany? company}) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => LoginScreen(
        initialSasUrl: sasUrl,
        initialUsername: username,
        initialCompanyLabel: company?.label,
        initialSasCode: company?.sasCode,
        fromCompanies: true,
      ),
    ));
    if (mounted) _load(); // ربما أُضيفت شركة
  }

  Future<void> _remove(LinkedCompany c) async {
    HapticFeedback.mediumImpact();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('account.remove_title'.tr(), style: AppType.sheetTitle(color: AppColors.textHi)),
        content: Text('account.remove_body'.tr(args: [c.label, c.username]),
            style: AppType.subtitle(color: AppColors.textMid).copyWith(height: 1.55)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('common.cancel'.tr(), style: AppType.button(color: AppColors.textMid)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('account.remove'.tr(), style: AppType.button(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await AccountApi.removeCompany(c);
      await CompanyCredsStore.remove(c.sasUrl ?? '', c.username);
      if (mounted) _load();
    } on AccountApiException catch (e) {
      if (mounted) showAccountSnack(context, accountText(e.message), error: true);
    }
  }

  Future<void> _openSubscription() async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => SubscriptionScreen(me: _me, fromCompanies: true),
    ));
    try {
      final me = await AccountApi.me();
      if (mounted) setState(() => _me = me);
    } catch (e) {
      if (kDebugMode) debugPrint('🟡 companies me: $e');
    }
  }

  /// «أجهزتي» — تعمل والحساب عند حدّ الأجهزة (بتوكن الحساب وحده).
  Future<void> _openDevices() async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => MyDevicesScreen(me: _me)));
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
    final sub = _me.subscription;
    // آيفون: المجّانيّ الدائم «مجّاني دائم» لا «باقي 36500 يوم».
    final neutral = StorePolicy.hidePurchaseFlows;
    // آيفون: «فعّال حتى …» بلا «تجربة» ولا «مشترك · باقي X يوم» (3.1.1)، والمجّانيّ
    // الدائم «مجّاني دائم» لا «باقي 36500 يوم».
    final chip = neutral
        ? (sub.isFreeForever
            ? 'account.chip_free'.tr()
            : !sub.active
                ? 'account.status_ended_neutral'.tr()
                : sub.endsAt == null
                    ? 'account.status_active_neutral'.tr()
                    : 'account.chip_active_neutral'
                        .tr(args: [DateFormat('d MMMM y', context.locale.languageCode).format(sub.endsAt!)]))
        // أندرويد أيضاً: المجّانيّ الدائم «مجّاني دائم» لا «مشترك · باقي 36500 يوم».
        : sub.isFreeForever
            ? 'account.chip_free'.tr()
            : sub.isTrial
                ? 'account.chip_trial'.tr(args: ['${sub.daysLeft}'])
                : 'account.chip_active'.tr(args: ['${sub.daysLeft}']);
    // آيفون: لونٌ بحسب قرب الانتهاء لا بحسب «تجربة».
    final warnTone = neutral
        ? (!sub.active || (!sub.isFreeForever && sub.daysLeft <= 7))
        : sub.isTrial;
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: RefreshIndicator(
          color: AppColors.brand,
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(Sp.xl, Sp.lg, Sp.xl, Sp.xl),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('account.companies_title'.tr(), style: AppType.title(color: AppColors.textHi)),
                        const SizedBox(height: Sp.xxs),
                        Text(_me.email ?? '', style: AppType.subtitle(color: AppColors.textMid),
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                  // مبدّل المظهر على صفحة البداية — يبدّل فاتح/داكن/تلقائي
                  // بلا دخولٍ لشركةٍ ولا وصولٍ للإعدادات.
                  const AccountThemeToggle(),
                  const SizedBox(width: Sp.xs),
                  PopupMenuButton<String>(
                    icon: Icon(Icons.more_vert_rounded, color: AppColors.textHi),
                    color: AppColors.surface,
                    onSelected: (v) => switch (v) {
                      'code' => _openSubscription(),
                      'devices' => _openDevices(),
                      'delete' => confirmAndDeleteAccount(context),
                      'privacy' => openPrivacyPolicy(context),
                      _ => _signOut(),
                    },
                    itemBuilder: (_) => [
                      // آيفون: لا «كود التفعيل» (الحساب يُفعَّل من لوحة المالك)؛
                      // حالة الحساب تُفتح من حبّة الحالة تحت العنوان.
                      if (!StorePolicy.hidePurchaseFlows)
                        PopupMenuItem(
                          value: 'code',
                          child: Text('account.menu_code'.tr(), style: AppType.body(color: AppColors.textHi)),
                        ),
                      PopupMenuItem(
                        value: 'devices',
                        child: Text('account.devices_title'.tr(), style: AppType.body(color: AppColors.textHi)),
                      ),
                      PopupMenuItem(
                        value: 'out',
                        child: Text('account.sign_out'.tr(), style: AppType.body(color: AppColors.error)),
                      ),
                      // حذف الحساب (App Store 5.1.1(v)) — هنا أيضاً: المراجِع قد لا يصل
                      // الإعدادات بلا دخول شركة.
                      PopupMenuItem(
                        value: 'delete',
                        child: Text('account.delete_account'.tr(), style: AppType.body(color: AppColors.error)),
                      ),
                      PopupMenuItem(
                        value: 'privacy',
                        child: Text('account.privacy_policy'.tr(), style: AppType.body(color: AppColors.textHi)),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: Sp.md),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: InkWell(
                  onTap: _openSubscription,
                  borderRadius: BorderRadius.circular(R.pill),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: Sp.xs + 2),
                    decoration: BoxDecoration(
                      color: warnTone ? AppColors.warningSoftBg : AppColors.successSoftBg,
                      borderRadius: BorderRadius.circular(R.pill),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(warnTone ? Icons.hourglass_top_rounded : Icons.verified_rounded,
                          size: 15, color: warnTone ? AppColors.warning : AppColors.success),
                      const SizedBox(width: Sp.xs + 2),
                      Text(chip, style: AppType.pillBold(color: warnTone ? AppColors.warningOnSoft : AppColors.success)),
                    ]),
                  ),
                ),
              ),
              const SizedBox(height: Sp.xl),
              ..._body(),
              const SizedBox(height: Sp.lg),
              AccountPrimaryButton(
                label: 'account.add_company'.tr(),
                icon: Icons.add_business_outlined,
                onTap: _opening == null ? () => _addOrLogin() : null,
              ),
              const SizedBox(height: Sp.md),
              Text('account.add_company_hint'.tr(),
                  textAlign: TextAlign.center, style: AppType.muted(color: AppColors.textMid)),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _body() {
    if (_error != null) {
      return [
        AccountCard(
          child: Column(children: [
            Icon(Icons.wifi_off_rounded, color: AppColors.textLow, size: 32),
            const SizedBox(height: Sp.sm),
            Text(accountText(_error!), textAlign: TextAlign.center, style: AppType.body(color: AppColors.textBody)),
            const SizedBox(height: Sp.md),
            AccountOutlineButton(label: 'common.retry'.tr(), onTap: _load),
          ]),
        ),
      ];
    }
    final items = _items;
    if (items == null) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: Sp.huge),
          child: Center(child: CircularProgressIndicator(color: AppColors.brand, strokeWidth: 2.4)),
        ),
      ];
    }
    if (items.isEmpty) {
      return [
        AccountCard(
          child: Column(children: [
            Icon(Icons.apartment_rounded, color: AppColors.brand, size: 36),
            const SizedBox(height: Sp.md),
            Text('account.no_companies'.tr(), style: AppType.cardTitleBold(color: AppColors.textHi)),
            const SizedBox(height: Sp.xs),
            Text('account.no_companies_body'.tr(),
                textAlign: TextAlign.center, style: AppType.body(color: AppColors.textMid).copyWith(height: 1.55)),
          ]),
        ),
      ];
    }
    return [
      for (final c in items) ...[
        _CompanyTile(
          company: c,
          busy: _opening == _keyOf(c),
          onTap: () => _open(c),
          onRemove: () => _remove(c),
        ),
        const SizedBox(height: Sp.md),
      ],
    ];
  }
}

class _CompanyTile extends StatelessWidget {
  const _CompanyTile({required this.company, required this.busy, required this.onTap, required this.onRemove});
  final LinkedCompany company;
  final bool busy;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final c = company;
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(R.lg),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: busy ? null : onTap,
        onLongPress: onRemove,
        child: Padding(
          padding: const EdgeInsets.all(Sp.lg),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: AppColors.brandSoftBg, borderRadius: BorderRadius.circular(R.md)),
                child: Icon(Icons.router_outlined, color: AppColors.brand, size: 22),
              ),
              const SizedBox(width: Sp.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(c.label, style: AppType.listName(color: AppColors.textHi),
                        maxLines: 1, overflow: TextOverflow.ellipsis, textDirection: TextDirection.ltr),
                    const SizedBox(height: Sp.xxs),
                    Row(children: [
                      Flexible(
                        child: Text(c.username, style: AppType.body(color: AppColors.textMid),
                            maxLines: 1, overflow: TextOverflow.ellipsis, textDirection: TextDirection.ltr),
                      ),
                      if (c.isEmployee) ...[
                        const SizedBox(width: Sp.sm),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: Sp.sm, vertical: 2),
                          decoration: BoxDecoration(
                              color: AppColors.surfaceInput, borderRadius: BorderRadius.circular(R.pill)),
                          child: Text('account.role_employee'.tr(), style: AppType.pillBold(color: AppColors.textMid)),
                        ),
                      ],
                    ]),
                  ],
                ),
              ),
              if (busy)
                SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.2, color: AppColors.brand))
              else
                Icon(Icons.chevron_left_rounded, color: AppColors.textLow),
            ],
          ),
        ),
      ),
    );
  }
}
