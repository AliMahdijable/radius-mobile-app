import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../api/account_api.dart';
import '../core/widgets/app_sheet.dart';
import '../core/widgets/design_sheet.dart';
import '../models/merged_company.dart';
import '../screens/account/company_switch_sheet.dart';
import '../screens/employees/sheets/employee_pages_sheet.dart';
import '../services/active_company.dart';
import '../services/linked_companies.dart';
import '../services/merged_mode.dart';
import '../services/merged_text.dart';
import '../theme/colors.dart';
import '../theme/spacing.dart';
import '../theme/typography.dart';

/// صفّ «شركاتي» لمدير الشركة [adminId] (لا صفّ موظّف) — كما تختار نقرة إشعار شركةٍ غير المفتوحة. null ⇒ لا يُعرف (الورقة بلا
/// فتحٍ تلقائيّ والمدير يختار).
Future<LinkedCompany?> linkedCompanyOf(String adminId) async {
  LinkedCompany? pick(List<LinkedCompany>? items) {
    for (final c in items ?? const <LinkedCompany>[]) {
      if (!c.isEmployee && c.adminId == adminId) return c;
    }
    return null;
  }

  try {
    return pick(LinkedCompanies.items.value) ?? pick(await LinkedCompanies.load());
  } catch (_) {
    return null;
  }
}

/// «بدّل إلى «X»»: ورقة «شركاتي» تفتح [c] بنفسها (دخولها كما لو نقرها المدير). الموظّف («كل الصفحات»، ٩ نوفمبر): ورقة
/// «صفحاتي» تنقله إلى صفحته فيها بصفّه هناك (`employee_id`) — كما لو نقرها.
Future<void> switchToMergedCompany(BuildContext context, MergedCompany c) async {
  if (MergedMode.employeeSession) {
    await showEmployeePagesSheet(context, autoSwitchTo: c.employeeId);
    return;
  }
  final linked = await linkedCompanyOf(c.adminId);
  if (!context.mounted) return;
  await showCompanySwitchSheet(context, autoOpen: linked, notice: linked == null ? null : c.name);
}

/// «كل الشركات» — «في أيّ شركة؟» (كالموقع، P1c): عمليّةٌ لا يحدّد صفٌّ شركتها ([action]، مثل «مشترك جديد») تُسأل شركتها أوّلاً
/// فلا تذهب لشركةٍ لم يقصدها المدير. تُنفَّذ اليوم في الشركة المفتوحة وحدها: غيرها بمكانها مقفلةً بسببها ([reason]) و«بدّل إليها».
/// true = اختار المفتوحة (تُكمل العمليّة كما هي). خارج «كل الشركات»: true فوراً بلا سؤال.
///
/// [onOther]: ما يُفعل بشركةٍ غير المفتوحة (افتراضاً «بدّل إليها») — قسمٌ موجَّهٌ لها مثلاً («إضافة صرفية» ⇒ صرفياتها بمكانها)؛
/// [otherHint] سطرها حينئذٍ بدل «<reason> — بدّل إليها».
Future<bool> pickOpenCompanyFor(
  BuildContext context, {
  required String action,
  required String reason,
  Future<void> Function(MergedCompany c)? onOther,
  String? otherHint,
}) async {
  if (!MergedMode.active.value) return true;
  final open = await MergedMode.openAdminId();
  if (!context.mounted) return false;
  final picked = await showAppSheet<_Pick>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: AppColors.scrim,
    isScrollControlled: true,
    builder: (_) => _PickSheet(action: action, reason: reason, openAdmin: open, otherHint: otherHint),
  );
  if (picked == null || !context.mounted) return false;
  final other = picked.other;
  if (other == null) return true;
  if (onOther != null) {
    await onOther(other);
  } else {
    await switchToMergedCompany(context, other);
  }
  return false;
}

/// اختيار الورقة: المفتوحة ([other] null) أو شركةٌ غيرها.
class _Pick {
  const _Pick(this.other);
  final MergedCompany? other;
}

class _PickSheet extends StatelessWidget {
  const _PickSheet({required this.action, required this.reason, required this.openAdmin, this.otherHint});
  final String action;
  final String reason;
  final String? openAdmin;
  final String? otherHint;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final companies = MergedMode.usable;
    final hasOpen = companies.any((c) => c.adminId == openAdmin);
    return DesignSheet(
      header: SheetHeaderBar(
        icon: LucideIcons.building2,
        title: mergedWord('في أيّ شركة؟', 'في أيّ صفحة؟'),
        subtitle: action,
        onClose: () => Navigator.of(context).pop(),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // المفتوحة أوّلاً — هي وحدها تُنفَّذ فيها هنا
          for (final c in companies)
            if (c.adminId == openAdmin) _Row(company: c, open: true, reason: reason),
          if (!hasOpen)
            _Row(company: null, open: true, reason: reason, label: ActiveCompany.current?.label),
          for (final c in companies)
            if (c.adminId != openAdmin) _Row(company: c, open: false, reason: reason, otherHint: otherHint),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.company, required this.open, required this.reason, this.label, this.otherHint});
  final MergedCompany? company;
  final bool open;
  final String reason;
  final String? label;
  final String? otherHint;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final c = company;
    final name = c?.name ?? label ?? '—';
    return Padding(
      padding: const EdgeInsets.only(bottom: Sp.sm),
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.md),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: ValueKey('merged-pick-${c?.key ?? 'open'}'),
          // المفتوحة ⇒ تُكمل هنا؛ غيرها ⇒ «بدّل إليها» (الورقة تُغلق ثمّ «شركاتي» تفتحها)
          onTap: () => Navigator.of(context).pop(_Pick(open ? null : c)),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(R.md),
              border: Border.all(color: open ? AppColors.brand.withValues(alpha: 0.45) : AppColors.border),
            ),
            child: Row(
              children: [
                Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    color: c == null ? AppColors.textLow : AppColors.company(c.colorIndex),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: Sp.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppType.label(color: AppColors.textHi).copyWith(fontSize: 14, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text(
                        open
                            ? mergedWord('المفتوحة — تُضاف هنا', 'صفحتك الحاليّة — تُضاف هنا')
                            : (otherHint ?? '$reason — ${mergedWord('بدّل إليها', 'انتقل إليها من «صفحاتي»')}'),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppType.body(color: AppColors.textMid).copyWith(fontSize: 12.5, height: 1.4),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: Sp.sm),
                Icon(open || otherHint != null ? LucideIcons.chevronLeft : LucideIcons.arrowLeftRight,
                    size: 16, color: open ? AppColors.brand : AppColors.textMid),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
