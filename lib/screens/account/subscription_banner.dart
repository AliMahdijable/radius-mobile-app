import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';

import '../../api/account_api.dart';
import '../../services/account_service.dart';
import '../../services/dashboard_refresh_signal.dart';
import '../../services/support_contact.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import 'subscription_screen.dart';

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

/// Pro البند ٤: شريط أعلى الصفحة الرئيسيّة — في التجربة، أو حين يبقى
/// [kSubscriptionWarnDays] أيّام أو أقلّ على الاشتراك. فيه «تفعيل كود»
/// و«تواصل معنا». لا يظهر في الحالة السويّة.
class SubscriptionBanner extends StatefulWidget {
  const SubscriptionBanner({super.key});

  @override
  State<SubscriptionBanner> createState() => _SubscriptionBannerState();
}

class _SubscriptionBannerState extends State<SubscriptionBanner> {
  AccountMe? _me = AccountStatusCache.cached;
  bool _expanded = false;

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

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final me = _me;
    if (me == null) return const SizedBox.shrink();
    final s = me.subscription;
    if (!s.active || (!s.isTrial && s.daysLeft > kSubscriptionWarnDays)) return const SizedBox.shrink();

    final urgent = s.daysLeft <= 2;
    final bg = urgent ? AppColors.dangerSoftBg : AppColors.warningSoftBg;
    final fg = urgent ? AppColors.error : AppColors.warning;
    final title = s.daysLeft <= 1
        ? 'account.banner_today'.tr()
        : (s.isTrial ? 'account.banner_trial' : 'account.banner_ending').tr(args: ['${s.daysLeft}']);
    final body = (s.isTrial ? 'account.banner_trial_body' : 'account.banner_ending_body').tr();

    // مطويٌّ افتراضيّاً (طلب المستخدم: لا يأكل الشاشة) — سطرٌ واحد، والضغط يفتح الأزرار.
    return Padding(
      padding: const EdgeInsets.only(bottom: Sp.md),
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(R.md),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          child: AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: Sp.sm + 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(urgent ? Icons.error_outline_rounded : Icons.hourglass_top_rounded, color: fg, size: 18),
                      const SizedBox(width: Sp.sm),
                      Expanded(
                        child: Text(title, style: AppType.bodyBold(color: AppColors.textHi),
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                      Icon(_expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                          color: AppColors.textMid, size: 20),
                    ],
                  ),
                  if (_expanded) ...[
                    const SizedBox(height: Sp.xs),
                    Text(body, style: AppType.body(color: AppColors.textBody).copyWith(height: 1.5)),
                    const SizedBox(height: Sp.sm + 2),
                    Row(
                      children: [
                        Expanded(
                          child: _BannerButton(
                            label: 'account.code_activate'.tr(),
                            icon: Icons.key_rounded,
                            filled: true,
                            onTap: () => _activate(me),
                          ),
                        ),
                        if (!me.support.isEmpty) ...[
                          const SizedBox(width: Sp.sm),
                          Expanded(
                            child: _BannerButton(
                              label: 'account.contact_us'.tr(),
                              icon: Icons.support_agent_rounded,
                              filled: false,
                              onTap: () => SupportContact.open(context, me.support),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
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
