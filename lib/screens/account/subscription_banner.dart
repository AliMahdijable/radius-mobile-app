import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';

import '../../api/account_api.dart';
import '../../core/platform/store_policy.dart';
import '../../services/account_service.dart';
import '../../services/dashboard_refresh_signal.dart';
import '../../services/support_contact.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import 'subscription_screen.dart';
import '../../core/widgets/app_sheet.dart';

/// حالة الحساب داخل التطبيق (بعد دخول الساس) — نداءٌ واحد كلّ ١٠ دقائق
/// يكفي الشريط وكارت الإعدادات معاً.
class AccountStatusCache {
  AccountStatusCache._();

  static AccountMe? _me;
  static DateTime? _at;
  static String? _uid; // حسابٌ آخر دخل على الجهاز ← القراءة القديمة لا تخصّه

  static bool get _sameUser => _uid != null && _uid == AccountService.currentUser?.uid;

  static AccountMe? get cached => _sameUser ? _me : null;

  static Future<AccountMe?> get({bool force = false}) async {
    if (!AccountService.isReady) return null;
    final fresh = _at != null && DateTime.now().difference(_at!) < const Duration(minutes: 10);
    if (!force && _me != null && fresh && _sameUser) return _me;
    final uid = AccountService.currentUser?.uid;
    try {
      _me = await AccountApi.me();
      _at = DateTime.now();
      _uid = uid;
    } catch (_) {/* الشبكة: نُبقي آخر قراءةٍ لهذا الحساب */}
    return cached;
  }

  static void clear() {
    _me = null;
    _at = null;
    _uid = null;
  }
}

/// الأيّام التي قبلها يظهر تنبيه قرب الانتهاء (قرار المستخدم).
const int kSubscriptionWarnDays = 7;

/// Pro البند ٤: حبّة صغيرة في ترويسة الرئيسيّة بجانب حالة الواتساب — في
/// التجربة، أو حين يبقى [kSubscriptionWarnDays] أيّام أو أقلّ. الضغط يفتح
/// نافذةً صغيرة فيها «تفعيل» و«تواصل معنا». (طلب المستخدم: في الأعلى لا
/// كارتاً يأخذ مساحة في جسم الصفحة.) لا تظهر في الحالة السويّة.
///
/// آيفون ([StorePolicy.hidePurchaseFlows]): النافذة معلومةٌ وحدها («ينتهي في …»)
/// وزرّ إغلاق — لا «تفعيل» ولا «تواصل معنا» (الحساب يُفعَّل من لوحة المالك).
class SubscriptionChip extends StatefulWidget {
  const SubscriptionChip({super.key});

  @override
  State<SubscriptionChip> createState() => _SubscriptionChipState();
}

class _SubscriptionChipState extends State<SubscriptionChip> {
  AccountMe? _me = AccountStatusCache.cached;

  @override
  void initState() {
    super.initState();
    _load();
    DashboardRefreshSignal.tick.addListener(_onRefresh);
  }

  @override
  void dispose() {
    DashboardRefreshSignal.tick.removeListener(_onRefresh);
    super.dispose();
  }

  void _onRefresh() => _load(force: true);

  Future<void> _load({bool force = false}) async {
    final me = await AccountStatusCache.get(force: force);
    if (mounted) setState(() => _me = me);
  }

  Future<void> _activate(AccountMe me) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => SubscriptionScreen(me: me, fromCompanies: true),
    ));
    await _load(force: true);
  }

  void _openSheet(AccountMe me, String title, bool urgent) {
    final neutral = StorePolicy.hidePurchaseFlows;
    final ends = me.subscription.endsAt;
    final body = neutral
        ? (ends == null
            ? ''
            : 'account.banner_ends_on_neutral'.tr(args: [DateFormat('d MMMM y', context.locale.languageCode).format(ends)]))
        : (me.subscription.isTrial ? 'account.banner_trial_body' : 'account.banner_ending_body').tr();
    showAppSheet<void>(
      context: context,
      backgroundColor: AppColors.surfaceSheet,
      barrierColor: AppColors.scrim,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(R.sheet))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Sp.xl, Sp.lg, Sp.xl, Sp.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(urgent ? Icons.error_outline_rounded : Icons.hourglass_top_rounded,
                  color: urgent ? AppColors.error : AppColors.warning, size: 32),
              const SizedBox(height: Sp.sm),
              Text(title, textAlign: TextAlign.center, style: AppType.sheetTitle(color: AppColors.textHi)),
              if (body.isNotEmpty) ...[
                const SizedBox(height: Sp.xs),
                Text(body, textAlign: TextAlign.center,
                    style: AppType.body(color: AppColors.textBody).copyWith(height: 1.55)),
              ],
              const SizedBox(height: Sp.lg),
              if (neutral)
                _BannerButton(
                  label: 'common.close'.tr(),
                  icon: Icons.check_rounded,
                  filled: false,
                  onTap: () => Navigator.of(ctx).pop(),
                )
              else
                Row(
                  children: [
                    Expanded(
                      child: _BannerButton(
                        label: 'account.code_activate'.tr(),
                        icon: Icons.key_rounded,
                        filled: true,
                        onTap: () {
                          Navigator.of(ctx).pop();
                          _activate(me);
                        },
                      ),
                    ),
                    if (!me.support.isEmpty) ...[
                      const SizedBox(width: Sp.sm),
                      Expanded(
                        child: _BannerButton(
                          label: 'account.contact_us'.tr(),
                          icon: Icons.support_agent_rounded,
                          filled: false,
                          onTap: () {
                            Navigator.of(ctx).pop();
                            SupportContact.open(context, me.support);
                          },
                        ),
                      ),
                    ],
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final me = _me;
    if (me == null) return const SizedBox.shrink();
    final s = me.subscription;
    final neutral = StorePolicy.hidePurchaseFlows;
    if (!s.active) return const SizedBox.shrink();
    // آيفون: لا حبّة طوال «التجربة» — قرب الانتهاء وحده، وبصيغة «تفعيل الحساب»
    // لا «اشتراك/تجربة» (3.1.1).
    if (neutral ? s.daysLeft > kSubscriptionWarnDays : (!s.isTrial && s.daysLeft > kSubscriptionWarnDays)) {
      return const SizedBox.shrink();
    }

    final urgent = s.daysLeft <= 2;
    final title = neutral
        ? (s.daysLeft <= 1
            ? 'account.banner_today_neutral'.tr()
            : 'account.banner_neutral_title'.tr(args: ['${s.daysLeft}']))
        : s.daysLeft <= 1
            ? 'account.banner_today'.tr()
            : (s.isTrial ? 'account.banner_trial' : 'account.banner_ending').tr(args: ['${s.daysLeft}']);
    final short = s.daysLeft <= 1 ? 'account.chip_today'.tr() : 'account.chip_days_left'.tr(args: ['${s.daysLeft}']);
    final tone = urgent ? AppTone.danger : AppTone.warning;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _openSheet(me, title, urgent),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: Sp.sm, vertical: 4),
        decoration: BoxDecoration(
          color: tone.softBg,
          borderRadius: BorderRadius.circular(R.pill),
          border: Border.all(color: tone.softBorder),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.hourglass_top_rounded, size: 11, color: tone.fill),
            const SizedBox(width: 4),
            Text(short, maxLines: 1, style: AppType.muted(color: tone.onSoft).copyWith(fontSize: 11)),
          ],
        ),
      ),
    );
  }
}

class _BannerButton extends StatelessWidget {
  const _BannerButton({required this.label, required this.icon, required this.filled, required this.onTap});
  final String label;
  final IconData icon;
  final bool filled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final fg = filled ? AppColors.onBrand : AppColors.brand;
    return SizedBox(
      height: 44,
      child: Material(
        color: filled ? AppColors.brand : AppColors.surface,
        borderRadius: BorderRadius.circular(R.md),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: fg, size: 18),
              const SizedBox(width: Sp.xs + 2),
              Flexible(
                child: Text(label, style: AppType.button(color: fg).copyWith(fontSize: 13.5),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
