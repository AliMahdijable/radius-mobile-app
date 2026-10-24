import 'dart:async';

import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';

import '../../api/account_api.dart';
import '../../core/platform/store_policy.dart';
import '../../services/account_service.dart';
import '../../services/support_contact.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import 'account_login_screen.dart';
import 'account_widgets.dart';
import 'my_devices_screen.dart';
import 'subscription_banner.dart';
import 'subscription_screen.dart';

/// Pro البند ٤: «الحساب والاشتراك» في الإعدادات — البريد، حالة الاشتراك
/// وتاريخ انتهائه، ومنه: كود التفعيل · أجهزتي · تواصل معنا · الخروج من الحساب
/// · حذف الحساب.
///
/// آيفون ([StorePolicy.hidePurchaseFlows]): لا «كود التفعيل» ولا «تواصل معنا»
/// هنا — الحساب يُفعَّل من لوحة المالك، والبطاقة تعرض الحالة وحدها (3.1.1).
/// «حذف الحساب» على كلّ المنصّات (5.1.1(v)).
class AccountSettingsCard extends StatefulWidget {
  const AccountSettingsCard({super.key});

  @override
  State<AccountSettingsCard> createState() => _AccountSettingsCardState();
}

class _AccountSettingsCardState extends State<AccountSettingsCard> {
  AccountMe? _me = AccountStatusCache.cached;
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool force = false}) async {
    final me = await AccountStatusCache.get(force: force);
    if (mounted) setState(() => _me = me);
  }

  String _date(DateTime? d) => d == null
      ? '—'
      : DateFormat('d MMMM y', context.locale.languageCode).format(d);

  Future<void> _openSubscription(AccountMe me) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => SubscriptionScreen(me: me, fromCompanies: true),
    ));
    await _load(force: true);
  }

  Future<void> _signOut() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('account.sign_out'.tr(),
            style: AppType.sheetTitle(color: AppColors.textHi)),
        content: Text('account.sign_out_body'.tr(),
            style: AppType.subtitle(color: AppColors.textMid)
                .copyWith(height: 1.55)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('common.cancel'.tr(),
                style: AppType.button(color: AppColors.textMid)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('account.sign_out'.tr(),
                style: AppType.button(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    AccountStatusCache.clear();
    await AccountService.signOut();
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AccountLoginScreen()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final me = _me;
    final email = me?.email ?? AccountService.currentUser?.email ?? '';
    final s = me?.subscription;
    final neutral = StorePolicy.hidePurchaseFlows;
    final String status;
    final Color tone;
    if (s == null) {
      status = 'account.checking'.tr();
      tone = AppColors.textMid;
    } else if (!s.active) {
      status = (neutral ? 'account.status_ended_neutral' : 'account.status_ended').tr();
      tone = AppColors.error;
    } else if (neutral) {
      // آيفون: لا «تجربة» ولا «مشترك · باقي X يوم» — حالة الحساب وتاريخه وحدهما (3.1.1).
      status = s.isFreeForever
          ? 'account.chip_free'.tr()
          : s.endsAt == null
              ? 'account.status_active_neutral'.tr()
              : 'account.chip_active_neutral'.tr(args: [_date(s.endsAt)]);
      tone = !s.isFreeForever && s.daysLeft <= kSubscriptionWarnDays
          ? AppColors.warning
          : AppColors.success;
    } else if (s.isFreeForever) {
      // أندرويد أيضاً: «مجّاني دائم» لا «مشترك · باقي 36500 يوم · حتى —».
      status = 'account.chip_free'.tr();
      tone = AppColors.success;
    } else {
      status =
          '${(s.isTrial ? 'account.chip_trial' : 'account.chip_active').tr(args: [
            '${s.daysLeft}'
          ])} · '
          '${'account.status_until'.tr(args: [_date(s.endsAt)])}';
      tone = s.isTrial || s.daysLeft <= kSubscriptionWarnDays
          ? AppColors.warning
          : AppColors.success;
    }

    final short = s == null
        ? ''
        : neutral
            ? (!s.active
                ? 'account.status_ended_neutral'.tr()
                : s.isFreeForever
                    ? 'account.chip_free'.tr()
                    : 'account.status_active_neutral'.tr())
            : !s.active
                ? 'account.status_ended'.tr()
                : s.isFreeForever
                    ? 'account.chip_free'.tr()
                    : (s.isTrial ? 'account.chip_trial' : 'account.chip_active')
                        .tr(args: ['${s.daysLeft}']);

    // مطويٌّ افتراضيّاً بشكل صفوف الإعدادات نفسها؛ الضغط يفتح التفاصيل والأزرار.
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(R.md),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => setState(() => _expanded = !_expanded),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(R.md),
            border: Border.all(color: AppColors.border),
          ),
          padding:
              const EdgeInsets.symmetric(horizontal: Sp.lg, vertical: Sp.md),
          child: AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(Icons.verified_user_outlined,
                        color: AppColors.textMid, size: 20),
                    const SizedBox(width: Sp.md),
                    Expanded(
                      child: Text(
                          (neutral ? 'account.settings_title_neutral' : 'account.settings_title').tr(),
                          style: AppType.label(color: AppColors.textHi),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ),
                    if (short.isNotEmpty) ...[
                      Text(short,
                          style: AppType.muted(color: tone).copyWith(
                              fontSize: 12.5, fontWeight: FontWeight.w600)),
                      const SizedBox(width: 6),
                    ],
                    Icon(
                        _expanded
                            ? Icons.expand_less_rounded
                            : Icons.expand_more_rounded,
                        color: AppColors.textLow,
                        size: 20),
                  ],
                ),
                if (_expanded) ...[
                  const SizedBox(height: Sp.md),
                  Text(email,
                      style: AppType.body(color: AppColors.textMid),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textDirection: TextDirection.ltr),
                  const SizedBox(height: Sp.xs),
                  Text(status, style: AppType.bodyStrong(color: tone)),
                  const SizedBox(height: Sp.md),
                  Wrap(
                    spacing: Sp.sm,
                    runSpacing: Sp.sm,
                    children: [
                      if (me != null && !StorePolicy.hidePurchaseFlows)
                        _Chip(
                            icon: Icons.key_rounded,
                            label: 'account.menu_code'.tr(),
                            onTap: () => _openSubscription(me)),
                      // بلا شرط قراءة الحساب: الشاشة تجلب قائمتها بنفسها (ولها
                      // حالة خطأٍ وإعادة)، و`me` يقدّم العدّاد فقط إن وُجد.
                      _Chip(
                        icon: Icons.devices_rounded,
                        label: 'account.devices_title'.tr(),
                        onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                                builder: (_) => MyDevicesScreen(me: me))),
                      ),
                      // آيفون: رابط التواصل في سياق الاشتراك يُقرأ طريقاً للشراء.
                      if (me != null &&
                          !me.support.isEmpty &&
                          !StorePolicy.hidePurchaseFlows)
                        _Chip(
                          icon: Icons.support_agent_rounded,
                          label: 'account.contact_us'.tr(),
                          onTap: () => SupportContact.open(context, me.support),
                        ),
                      _Chip(
                          icon: Icons.logout_rounded,
                          label: 'account.sign_out'.tr(),
                          danger: true,
                          onTap: _signOut),
                      _Chip(
                        icon: Icons.delete_forever_rounded,
                        label: 'account.delete_account'.tr(),
                        danger: true,
                        onTap: () => confirmAndDeleteAccount(context),
                      ),
                      _Chip(
                        icon: Icons.privacy_tip_outlined,
                        label: 'account.privacy_policy'.tr(),
                        onTap: () => openPrivacyPolicy(context),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ───────────── حذف الحساب (App Store 5.1.1(v)) ─────────────

/// حذف الحساب من داخل التطبيق: شرحٌ لما يُحذف وما يبقى ← تأكيدٌ ثانٍ صريح ←
/// [AccountService.deleteCurrentAccount] ← شاشة دخول الحساب كالخروج تماماً.
///
/// عامّةٌ لا خاصّة بالبطاقة: تُستدعى من أيّ مكانٍ يملك سياقاً (الإعدادات،
/// قائمة «شركاتي») — المراجِع قد لا يصل الإعدادات بلا دخول شركة.
///
/// التنقّل بعد النجاح بالـNavigator الجذريّ المُلتقَط قبل الحذف: البطاقة قد
/// تُزال أثناءه (المسح يُعيد بناء الشاشات)، والحذف تمّ فلا بدّ من الوصول لشاشة
/// الدخول على كلّ حال.
Future<void> confirmAndDeleteAccount(BuildContext context) async {
  final email = AccountService.currentUser?.email?.trim() ?? '';

  // ① ما يُحذف وما يبقى.
  final first = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.surface,
      title: Text('account.delete_title'.tr(),
          style: AppType.sheetTitle(color: AppColors.textHi)),
      content: SingleChildScrollView(
        child: Text('account.delete_body'.tr(),
            style: AppType.subtitle(color: AppColors.textMid)
                .copyWith(height: 1.6)),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text('common.cancel'.tr(),
              style: AppType.button(color: AppColors.textMid)),
        ),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text('account.delete_continue'.tr(),
              style: AppType.button(color: AppColors.error)),
        ),
      ],
    ),
  );
  if (first != true || !context.mounted) return;

  // ② تأكيدٌ أخير صريح — زرّ الحذف وحده يحذف، والإلغاء هو الافتراضيّ.
  final second = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.surface,
      title: Text('account.delete_confirm_title'.tr(),
          style: AppType.sheetTitle(color: AppColors.textHi)),
      content: Text(
        email.isEmpty
            ? 'account.delete_confirm_body_plain'.tr()
            : 'account.delete_confirm_body'.tr(args: [email]),
        style: AppType.subtitle(color: AppColors.textMid).copyWith(height: 1.6),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text('common.cancel'.tr(),
              style: AppType.button(color: AppColors.textMid)),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: AppColors.onBrand),
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text('account.delete_confirm_button'.tr(),
              style: AppType.button(color: AppColors.onBrand)),
        ),
      ],
    ),
  );
  if (second != true || !context.mounted) return;

  final nav = Navigator.of(context, rootNavigator: true);
  final messenger = ScaffoldMessenger.maybeOf(context);

  // ③ قفلٌ أثناء الحذف: لا رجوع ولا نقرة خارجيّة حتى يتمّ أو يفشل.
  // يُزال **مساره هو** لا «أعلى مسار»: لو أزاله مسحُ الجلسة (طردٌ إلى البوّابة)
  // أو فُتح فوقه شيء، فـ`pop` أعمى قد يُغلق الشاشة الوحيدة الباقية.
  BuildContext? progressCtx;
  unawaited(showDialog<void>(
    context: context,
    barrierDismissible: false,
    useRootNavigator: true,
    builder: (ctx) {
      progressCtx = ctx;
      return PopScope(
        canPop: false,
        child: AlertDialog(
          backgroundColor: AppColors.surface,
          content: Row(children: [
            SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                  strokeWidth: 2.4, color: AppColors.error),
            ),
            const SizedBox(width: Sp.lg),
            Expanded(
              child: Text('account.delete_progress'.tr(),
                  style: AppType.body(color: AppColors.textHi)),
            ),
          ]),
        ),
      );
    },
  ));
  // الباني يعمل في الإطار التالي — يُلتقط سياقه من داخله.

  Object? failure;
  try {
    // تشمل الخروج الكامل (الساس + الشركات + المحفوظات + Google + Firebase).
    await AccountService.deleteCurrentAccount();
  } catch (e) {
    failure = e;
  }
  AccountStatusCache.clear();
  // فشلٌ فوريّ (قبل أوّل إطارٍ للحوار) ← ننتظر بناءه كي لا يبقى معلّقاً.
  if (progressCtx == null) await WidgetsBinding.instance.endOfFrame;
  final pc = progressCtx;
  if (pc != null && pc.mounted) {
    final route = ModalRoute.of(pc);
    if (route != null && route.isActive) Navigator.of(pc).removeRoute(route);
  }

  if (failure != null) {
    // ألغى نافذة Apple — لم يؤكّد، فلا رسالة خطأ.
    if (failure is AccountDeletionException && failure.cancelled) return;
    _showSnack(messenger, _deleteErrorText(failure), error: true);
    return;
  }

  if (!nav.mounted) return;
  unawaited(nav.pushAndRemoveUntil(
    MaterialPageRoute(builder: (_) => const AccountLoginScreen()),
    (_) => false,
  ));
  _showSnack(messenger, 'account.delete_done'.tr());
}

/// رسالة فشل الحذف: [AccountDeletionException] تحمل نصّاً جاهزاً؛ وغيرها
/// (لا يُتوقَّع) نصٌّ عامّ — لا تُعرض رسالة Firebase الإنجليزيّة الخام.
String _deleteErrorText(Object e) {
  if (e is AccountDeletionException && e.message.trim().isNotEmpty) {
    return StorePolicy.storeSafe(accountText(e.message.trim()));
  }
  if (e is AccountApiException) {
    return StorePolicy.storeSafe(accountText(e.message));
  }
  return 'account.delete_failed'.tr();
}

void _showSnack(ScaffoldMessengerState? m, String msg, {bool error = false}) {
  if (m == null || !m.mounted) return;
  m.hideCurrentSnackBar();
  m.showSnackBar(SnackBar(
    content: Text(msg, style: AppType.button(color: AppColors.onBrand)),
    backgroundColor: error ? AppColors.error : AppColors.brand,
    behavior: SnackBarBehavior.floating,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(R.md)),
    margin: const EdgeInsets.all(Sp.lg),
    duration: const Duration(seconds: 5),
  ));
}

class _Chip extends StatelessWidget {
  const _Chip(
      {required this.icon,
      required this.label,
      required this.onTap,
      this.danger = false});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final fg = danger ? AppColors.error : AppColors.brand;
    return Material(
      color: danger ? AppColors.dangerSoftBg : AppColors.brandSoftBg,
      borderRadius: BorderRadius.circular(R.pill),
      child: InkWell(
        borderRadius: BorderRadius.circular(R.pill),
        onTap: onTap,
        child: Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: Sp.md, vertical: Sp.sm),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 16, color: fg),
            const SizedBox(width: Sp.xs + 2),
            Text(label,
                style: AppType.pillBold(color: fg).copyWith(fontSize: 12.5)),
          ]),
        ),
      ),
    );
  }
}
