import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../api/auth_api.dart';
import '../../../api/employees_api.dart';
import '../../../core/widgets/app_sheet.dart';
import '../../../core/widgets/design_sheet.dart';
import '../../../services/employee_session.dart';
import '../../../services/permissions_service.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';
import '../../account/employee_login_screen.dart';
import '../../main_shell.dart';

/// ٨ نوفمبر — «موظّفٌ بأكثر من صفحة» (المالك: «نفس الموظف نسنده لاكثر من صفحه… يعني رح يصير نفس المدير بس بصلاحيات هو محددها؟
/// … تمام ابدي بيها»): «صفحاتي» كـ«شركاتي» عند المدير. الحاليّة معلَّمة، والنقر على أخرى ينقله إليها بتوكنه القائم
/// ([AuthApi.employeeSwitch]) — جلسة تلك الصفحة كاملة (صلاحيّاتها وسجلّها وأجهزتها) كما لو دخلها، ثمّ الرئيسيّة من جديد.
/// [onManagers]: صفّ «الصفحات» (المدراء الفرعيّون داخل الصفحة المفتوحة) أعلاها لموظّفٍ يملك تبديلهم.
Future<void> showEmployeePagesSheet(BuildContext context, {VoidCallback? onManagers}) {
  HapticFeedback.selectionClick();
  return showAppSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: AppColors.scrim,
    builder: (_) => EmployeePagesSheet(onManagers: onManagers),
  );
}

class EmployeePagesSheet extends StatefulWidget {
  const EmployeePagesSheet({super.key, this.onManagers});

  final VoidCallback? onManagers;

  /// منفذ الاختبار: نداء التنقّل وإكمال الجلسة (الخزنة الآمنة لا تعمل في `flutter test`).
  @visibleForTesting
  static Future<LoginResult> Function(int employeeId) switchCall = AuthApi.employeeSwitch;
  @visibleForTesting
  static Future<bool> Function(LoginSuccess s, String username) complete =
      (s, username) => EmployeeSession.completeLogin(s, username: username);

  @override
  State<EmployeePagesSheet> createState() => _EmployeePagesSheetState();
}

class _EmployeePagesSheetState extends State<EmployeePagesSheet> {
  int? _busy;
  String? _error;

  Future<void> _switch(EmployeePageRef p, List<EmployeePageRef> all) async {
    if (_busy != null || p.current) return;
    if (!p.active) {
      setState(() => _error = 'حسابك في «${p.pageName}» معطّل — راجع مدير تلك الصفحة');
      return;
    }
    HapticFeedback.lightImpact();
    setState(() {
      _busy = p.employeeId;
      _error = null;
    });
    final r = await EmployeePagesSheet.switchCall(p.employeeId);
    if (!mounted) return;
    switch (r) {
      case final LoginFailure f:
        // لم يُصدَر شيء: الجلسة الحاليّة باقية كما هي
        HapticFeedback.heavyImpact();
        setState(() {
          _busy = null;
          _error = f.message;
        });
      case final LoginSuccess s:
        final login = p.loginUsername ??
            all.firstWhere((x) => x.primary, orElse: () => p).loginUsername ??
            '';
        final ok = await EmployeePagesSheet.complete(s, login);
        if (!mounted) return;
        final nav = Navigator.of(context, rootNavigator: true);
        // تعذّر صلاحيّات الصفحة الجديدة ⇒ completeLogin مسح الجلسة كلّها (لا موظّفٌ بصلاحيّاتٍ مجهولة) — إلى دخول الموظّف
        nav.pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (_) => ok
                ? const MainShell()
                : const EmployeeLoginScreen(message: 'تعذّر تحميل صلاحيّاتك في تلك الصفحة — سجّل الدخول من جديد'),
          ),
          (_) => false,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return DesignSheet(
      header: SheetHeaderBar(
        icon: Icons.layers_outlined,
        title: 'صفحاتي',
        subtitle: 'الصفحات التي تعمل فيها — لكلّ صفحةٍ صلاحيّاتها',
        onClose: () => Navigator.of(context).maybePop(),
      ),
      body: ValueListenableBuilder<int>(
        valueListenable: PermissionsService.changes,
        builder: (context, _, __) {
          final pages = PermissionsService.employeePages;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_error != null) ...[
                Container(
                  key: const ValueKey('employee-pages-error'),
                  padding: const EdgeInsets.all(Sp.md),
                  decoration: BoxDecoration(
                    color: AppColors.dangerSoftBg,
                    borderRadius: BorderRadius.circular(R.md),
                  ),
                  child: Text(_error!, style: AppType.body(color: AppColors.error)),
                ),
                const SizedBox(height: Sp.md),
              ],
              if (widget.onManagers != null) ...[
                _PageRow(
                  icon: Icons.manage_accounts_outlined,
                  title: 'المدراء الفرعيّون',
                  subtitle: 'التبديل بين مدراء هذه الصفحة',
                  locked: _busy != null,
                  onTap: () {
                    Navigator.of(context).maybePop();
                    widget.onManagers!();
                  },
                ),
                const SizedBox(height: Sp.md),
              ],
              if (pages.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: Sp.lg),
                  child: Text('لا صفحاتٍ أخرى لك الآن',
                      textAlign: TextAlign.center, style: AppType.body(color: AppColors.textMid)),
                ),
              for (final p in pages) ...[
                _PageRow(
                  key: ValueKey('employee-page-${p.employeeId}'),
                  icon: Icons.storefront_outlined,
                  title: p.pageName,
                  subtitle: p.current
                      ? 'الصفحة الحاليّة'
                      : !p.active
                          ? 'معطّل في هذه الصفحة'
                          : p.primary
                              ? 'صفحتك الأصليّة'
                              : null,
                  current: p.current,
                  busy: _busy == p.employeeId,
                  locked: _busy != null || p.current,
                  dimmed: !p.active,
                  onTap: () => _switch(p, pages),
                ),
                const SizedBox(height: Sp.sm),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _PageRow extends StatelessWidget {
  const _PageRow({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.current = false,
    this.busy = false,
    this.locked = false,
    this.dimmed = false,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final bool current;
  final bool busy;
  final bool locked;
  final bool dimmed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Opacity(
      opacity: dimmed ? 0.55 : 1,
      child: Material(
        color: current ? AppColors.brandSoftBg : AppColors.surface,
        borderRadius: BorderRadius.circular(R.lg),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: locked ? null : onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: Sp.md),
            child: Row(
              children: [
                Container(
                  width: H.iconBox,
                  height: H.iconBox,
                  decoration: BoxDecoration(
                    color: current ? AppColors.surface : AppColors.brandSoftBg,
                    borderRadius: BorderRadius.circular(R.icon),
                  ),
                  child: Icon(icon, color: AppColors.brand, size: 20),
                ),
                const SizedBox(width: Sp.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: AppType.listName(color: AppColors.textHi),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis),
                      if (subtitle != null) ...[
                        const SizedBox(height: Sp.xxs),
                        Text(subtitle!,
                            style: AppType.muted(color: AppColors.textMid).copyWith(fontSize: 11.5),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: Sp.sm),
                if (busy)
                  const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                else if (current)
                  Icon(Icons.check_circle_rounded, color: AppColors.brand, size: 20)
                else
                  Icon(Icons.chevron_left_rounded, color: AppColors.textMid, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
