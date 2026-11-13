import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../api/employee_limits_api.dart';
import '../core/util/format.dart';
import '../services/dashboard_refresh_signal.dart';
import '../services/permissions_service.dart';
import '../theme/colors.dart';
import '../theme/spacing.dart';
import '../theme/typography.dart';

/// «حسابي مع المدير» — بطاقة الموظّف في الرئيسيّة (٩ نوفمبر — «حدود الموظّف»).
///
/// الموظّف وحده، وحين يقول الخادم إنّ الميزة مفتوحة لصفحته وعدّه بدأ (ضبط المدير قيمةً). غير ذلك ⇒ لا شيء ولا مساحة.
/// تجلب `/api/v2/employee-limits/me` بنفسها وتتحدّث مع سحب الرئيسيّة ([DashboardRefreshSignal]).
class EmployeeLimitsCard extends StatefulWidget {
  const EmployeeLimitsCard({super.key, this.loader});

  /// للاختبار: مصدرٌ بديل لـ[EmployeeLimitsApi.me].
  final Future<EmployeeLimitStatus?> Function()? loader;

  /// للاختبار: تعود مطويّةً (حالة الفتح تبقى ما دام التطبيق مفتوحاً).
  @visibleForTesting
  static void resetForTest() => _EmployeeLimitsCardState._open = false;

  @override
  State<EmployeeLimitsCard> createState() => _EmployeeLimitsCardState();
}

class _EmployeeLimitsCardState extends State<EmployeeLimitsCard> {
  EmployeeLimitStatus? _s;

  /// مطويّةٌ افتراضيّاً (المالك ٩ نوفمبر: «خليها افتراضي تكون مقفولة وبيها بس أرقامهن») — الأرقام الثلاثة بسطر، والنقر يفتح التفصيل.
  /// تبقى كما تركها الموظّف ما دام التطبيق مفتوحاً، وتعود مطويّةً مع كلّ تشغيل.
  static bool _open = false;

  @override
  void initState() {
    super.initState();
    DashboardRefreshSignal.tick.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    DashboardRefreshSignal.tick.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    EmployeeLimitStatus? s;
    if (widget.loader != null) {
      s = await widget.loader!();
    } else {
      if (!PermissionsService.isEmployee) return;
      final me = await EmployeeLimitsApi.me();
      s = me != null && me.isEmployee && me.featureEnabled ? me.status : null;
    }
    if (!mounted) return;
    setState(() => _s = s);
  }

  @override
  Widget build(BuildContext context) {
    final s = _s;
    if (s == null || !s.started || s.limits.isEmpty) return const SizedBox.shrink();
    void toggle() => setState(() => _open = !_open);
    return Padding(
      padding: const EdgeInsets.only(bottom: Sp.md),
      child: AnimatedSize(
        duration: const Duration(milliseconds: 180),
        alignment: Alignment.topCenter,
        child: _open
            ? EmployeeLimitsPanel(
                key: const ValueKey('emp-limits-open'),
                status: s,
                title: 'حسابي مع المدير',
                selfView: true,
                onHeaderTap: toggle,
              )
            : _CollapsedLimits(key: const ValueKey('emp-limits-collapsed'), status: s, onTap: toggle),
      ),
    );
  }
}

/// البطاقة مطويّةً: العنوان وسهمٌ للفتح، وتحته الأرقام وحدها — النقد/سقفه، الديون المفتوحة/سقفها، والربح.
class _CollapsedLimits extends StatelessWidget {
  const _CollapsedLimits({super.key, required this.status, required this.onTap});
  final EmployeeLimitStatus status;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final s = status;
    final blocked = s.cashBlocked || s.debtBlocked;
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(R.card),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, Sp.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(R.card),
            border: Border.all(color: blocked ? AppColors.error.withValues(alpha: 0.45) : AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(LucideIcons.walletCards, size: 16, color: AppColors.brand),
                  const SizedBox(width: Sp.sm),
                  Expanded(
                    child: Text('حسابي مع المدير', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.bodyBold(color: AppColors.textHi)),
                  ),
                  Icon(LucideIcons.chevronDown, size: 18, color: AppColors.textLow),
                ],
              ),
              const SizedBox(height: Sp.sm),
              Row(
                children: [
                  Expanded(
                    child: _Num(
                      key: const ValueKey('emp-limits-num-cash'),
                      label: 'نقد',
                      value: _pair(s.cashUsed, s.limits.cashCap),
                      color: _tone(s.cashUsed, s.limits.cashCap, s.cashBlocked),
                    ),
                  ),
                  const SizedBox(width: Sp.sm),
                  Expanded(
                    child: _Num(
                      key: const ValueKey('emp-limits-num-debt'),
                      label: 'ديون',
                      value: _pair(s.debtUsed, s.limits.debtCap),
                      color: _tone(s.debtUsed, s.limits.debtCap, s.debtBlocked),
                    ),
                  ),
                  const SizedBox(width: Sp.sm),
                  Expanded(
                    child: _Num(
                      key: const ValueKey('emp-limits-num-profit'),
                      label: 'ربح',
                      value: formatIQD(s.profit),
                      color: s.profit > 0 ? AppColors.success : AppColors.textHi,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _pair(double used, double? cap) => cap == null ? formatIQD(used) : '${formatIQD(used)} / ${formatIQD(cap)}';

  static Color _tone(double used, double? cap, bool blocked) {
    if (blocked) return AppColors.error;
    if (cap != null && cap > 0 && used / cap >= 0.85) return AppColors.warning;
    return AppColors.textHi;
  }
}

class _Num extends StatelessWidget {
  const _Num({super.key, required this.label, required this.value, required this.color});
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.micro(color: AppColors.textLow)),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: AlignmentDirectional.centerStart,
          child: Text(value, maxLines: 1, textDirection: TextDirection.rtl, style: AppType.bodyBold(color: color)),
        ),
      ],
    );
  }
}

/// لوحة أرقام الفترة: النقد/السقف، الدين/السقف، العمليّات والربح — للموظّف ([selfView]) وللمدير.
class EmployeeLimitsPanel extends StatelessWidget {
  const EmployeeLimitsPanel({super.key, required this.status, this.title, this.selfView = false, this.onHeaderTap});
  final EmployeeLimitStatus status;
  final String? title;
  final bool selfView;

  /// بطاقة الموظّف المفتوحة: النقر على العنوان يطويها (سهمٌ للأعلى). null ⇒ لوحة المدير كما هي.
  final VoidCallback? onHeaderTap;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final s = status;
    final since = s.periodStart;
    final blocked = s.cashBlocked || s.debtBlocked;
    return Container(
      padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, Sp.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.card),
        border: Border.all(color: blocked ? AppColors.error.withValues(alpha: 0.45) : AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onHeaderTap,
            child: Row(
              children: [
                Icon(LucideIcons.walletCards, size: 16, color: AppColors.brand),
                const SizedBox(width: Sp.sm),
                Expanded(
                  child: Text(title ?? 'حساب الموظف', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.bodyBold(color: AppColors.textHi)),
                ),
                if (since != null)
                  Text('منذ ${_dateAr(since)}', style: AppType.micro(color: AppColors.textLow)),
                if (onHeaderTap != null) ...[
                  const SizedBox(width: Sp.x6),
                  Icon(LucideIcons.chevronUp, size: 18, color: AppColors.textLow),
                ],
              ],
            ),
          ),
          const SizedBox(height: Sp.md),
          _CapRow(
            key: const ValueKey('emp-limits-cash'),
            label: 'الإيرادات النقديّة',
            used: s.cashUsed,
            cap: s.limits.cashCap,
            blocked: s.cashBlocked,
          ),
          const SizedBox(height: Sp.sm),
          _CapRow(
            key: const ValueKey('emp-limits-debt'),
            label: selfView ? 'ديونك المفتوحة عند المشتركين' : 'ديونه المفتوحة عند المشتركين',
            used: s.debtUsed,
            cap: s.limits.debtCap,
            blocked: s.debtBlocked,
          ),
          if (s.holdsCount > 0) ...[
            const SizedBox(height: Sp.x6),
            Text(
              'منها غير مؤكَّد: ${s.holdsCount} ${s.holdsCount == 1 ? 'عمليّة' : 'عمليّات'}'
              '${s.holdsCash > 0 ? ' · ${formatIQD(s.holdsCash)} نقداً' : ''}'
              '${s.holdsDebt > 0 ? ' · ${formatIQD(s.holdsDebt)} ديناً' : ''}',
              style: AppType.micro(color: AppColors.warning),
            ),
          ],
          const SizedBox(height: Sp.md),
          Row(
            children: [
              Expanded(child: _Stat(label: 'عمليّات كاملة', value: '${s.opsCount}')),
              const SizedBox(width: Sp.sm),
              Expanded(
                child: _Stat(
                  key: const ValueKey('emp-limits-profit'),
                  label: 'ربح الموظف',
                  value: '${formatIQD(s.profit)} د.ع',
                  accent: s.profit > 0,
                ),
              ),
            ],
          ),
          // «حركات الموظف» (١٣ نوفمبر): ما أخذه من النقد الذي بيده (سحب، سلفة أو راتب من يده) ⇒ يسلّم أقلّ في التسوية.
          if (s.handTaken != 0) ...[
            const SizedBox(height: Sp.sm),
            Text(
              '${selfView ? 'أخذتَ من النقد الذي بيدك' : 'أخذ من النقد الذي بيده'}: ${formatIQD(s.handTaken)} د.ع'
              '${s.toHandOver == null ? '' : ' · ${selfView ? 'تسلّم' : 'يسلّم'}: ${formatIQD(s.toHandOver!)} د.ع'}',
              key: const ValueKey('emp-hand-taken'),
              style: AppType.micro(color: AppColors.textMid),
            ),
          ],
          if (blocked) ...[
            const SizedBox(height: Sp.md),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: Sp.sm),
              decoration: BoxDecoration(
                color: AppColors.dangerSoftBg,
                borderRadius: BorderRadius.circular(R.md),
              ),
              child: Text(
                selfView
                    ? (s.cashBlocked
                        ? 'وصلت سقف الإيرادات النقديّة — سوِّ حسابك مع المدير ليُصفَّر'
                        : 'ديونك المفتوحة بلغت السقف — لا بيع ولا تفعيل بالآجل ولا إضافة دين حتى يسدّد المشتركون')
                    : (s.cashBlocked ? 'بلغ سقف الإيرادات النقديّة — يحتاج تسوية' : 'ديونه المفتوحة بلغت السقف — تنقص حين يسدّد المشتركون'),
                style: AppType.micro(color: AppColors.error).copyWith(fontWeight: FontWeight.w700),
              ),
            ),
          ],
          if (s.enforcementOff) ...[
            const SizedBox(height: Sp.sm),
            Text('الحدود موقوفةٌ مؤقّتاً — العدّ مستمرّ', style: AppType.micro(color: AppColors.textLow)),
          ],
        ],
      ),
    );
  }

  static String _dateAr(DateTime d) => '${d.day}/${d.month} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

class _CapRow extends StatelessWidget {
  const _CapRow({super.key, required this.label, required this.used, required this.cap, required this.blocked});
  final String label;
  final double used;
  final double? cap;
  final bool blocked;

  @override
  Widget build(BuildContext context) {
    final c = cap;
    final ratio = c == null || c <= 0 ? null : (used / c).clamp(0.0, 1.0);
    final color = blocked
        ? AppColors.error
        : ratio != null && ratio >= 0.85
            ? AppColors.warning
            : AppColors.brand;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.body(color: AppColors.textMid))),
            Text(
              c == null ? '${formatIQD(used)} د.ع · بلا حدّ' : '${formatIQD(used)} / ${formatIQD(c)} د.ع',
              textDirection: TextDirection.rtl,
              style: AppType.bodyBold(color: blocked ? AppColors.error : AppColors.textHi),
            ),
          ],
        ),
        if (ratio != null) ...[
          const SizedBox(height: 5),
          ClipRRect(
            borderRadius: BorderRadius.circular(R.pill),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 6,
              backgroundColor: AppColors.border,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ],
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({super.key, required this.label, required this.value, this.accent = false});
  final String label;
  final String value;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: Sp.sm),
      decoration: BoxDecoration(
        color: accent ? AppColors.successSoftBg : AppColors.bg,
        borderRadius: BorderRadius.circular(R.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppType.micro(color: AppColors.textLow)),
          const SizedBox(height: 2),
          Text(value, style: AppType.bodyBold(color: accent ? AppColors.success : AppColors.textHi)),
        ],
      ),
    );
  }
}
