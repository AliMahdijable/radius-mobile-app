import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../api/employee_ledger_api.dart';
import '../../core/util/format.dart';
import '../../core/widgets/sheet_scaffold.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import '../../widgets/merged_section.dart';
import '../reports/v2/report_kit.dart';
import 'employee_ledger_widgets.dart';
import 'employees_screen.dart';

/// «رواتب مستحقّة» (٢٦ نوفمبر — المالك: «سويهن ال ٣» على اقتراح: الراتب المستحقّ بـ«تسوية الحساب» و«تسوية مع الموظف» والتقرير
/// الماليّ، ومعها إشعار يوم الراتب) — كبطاقة الموقع (0006b1a): من حلّ راتبه ولم يُصرف، ومبلغه، و«صرف» يفتح كشف راتبه نفسه.
///
/// الشاشة تقرأ [SalaryDue] بنفسها ([EmployeeLedgerApi.salaryDue]) وتضيف البطاقة حين [SalaryDue.any] وحده — فلا فراغ حين لا مستحقّ،
/// ولا بطاقة بلا ميزة أو بلا صلاحيّة الرواتب (الخادم يردّ 403 ⇒ null). للصفحة المفتوحة وحدها (المسار لا يُوجَّه في «كل الشركات»).
class SalaryDueCard extends StatelessWidget {
  const SalaryDueCard({super.key, required this.due, this.note, this.onPaid});

  final SalaryDue due;

  /// سطرٌ صغير تحت القائمة يقول أين يدخل الصرف (يختلف بين الصندوق والتقرير).
  final String? note;

  /// صُرف كشفٌ من البطاقة ⇒ الشاشة تعيد أرقامها والمستحقّات (الصرف صرفيّةٌ تدخل الصندوق يومها).
  final VoidCallback? onPaid;

  Future<void> _pay(BuildContext context, SalaryDueRow r) async {
    final done = await showEmployeePayslipSheet(context, employeeId: r.employeeId, name: r.name);
    if (done == null) return;
    if (context.mounted) unawaited(showSheetSnack(context, done, isError: false));
    onPaid?.call();
  }

  @override
  Widget build(BuildContext context) {
    final rows = due.employees;
    return RpCard(
      key: const ValueKey('salary-due-card'),
      tint: AppColors.warning,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          RpTitle(
            icon: LucideIcons.banknote,
            title: 'رواتب مستحقّة (${due.count})',
            tone: RpTone.debt,
            trailing: Text(
              '${formatIQD(due.amount)} د.ع',
              key: const ValueKey('salary-due-total'),
              style: AppType.bodyBold(color: AppColors.warning),
            ),
          ),
          const SizedBox(height: Sp.sm),
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) Divider(height: 1, color: AppColors.border),
            _row(context, rows[i]),
          ],
          if ((note ?? '').isNotEmpty) ...[
            const SizedBox(height: Sp.x6),
            Text(note!, key: const ValueKey('salary-due-note'), style: AppType.micro(color: AppColors.textMid)),
          ],
        ],
      ),
    );
  }

  Widget _row(BuildContext context, SalaryDueRow r) => Padding(
        key: ValueKey('salary-due-${r.employeeId}'),
        padding: const EdgeInsets.symmetric(vertical: Sp.sm),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    r.active ? r.name : '${r.name} (موقوف)',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.bodyBold(color: AppColors.textHi),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${r.when}${r.withCommission ? ' · وعمولته تُحسب عند الصرف' : ''}',
                    key: ValueKey('salary-due-when-${r.employeeId}'),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.micro(color: AppColors.textMid),
                  ),
                ],
              ),
            ),
            const SizedBox(width: Sp.sm),
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${formatIQD(r.dueAmount)} د.ع',
                  key: ValueKey('salary-due-amount-${r.employeeId}'),
                  style: AppType.bodyBold(color: AppColors.warning),
                ),
                const SizedBox(height: 4),
                SizedBox(
                  height: 34,
                  child: OutlinedButton(
                    key: ValueKey('salary-due-pay-${r.employeeId}'),
                    onPressed: () => _pay(context, r),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.brand,
                      side: BorderSide(color: AppColors.brand),
                      padding: const EdgeInsets.symmetric(horizontal: Sp.md),
                      minimumSize: const Size(64, 34),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(R.button)),
                    ),
                    child: const Text('صرف'),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
}

/// إشعار «رواتب مستحقّة اليوم» (data.type = salary_due — الخادم server/salaryDueNotifier.js، يوم الراتب ٩ص–٩م بغداد) ⇒ قسم
/// الموظّفين (نقطة «راتبٌ مستحقّ» على حساب كلٍّ منهم). الإشعار لصفحةٍ أخرى من شركات الحساب تفتحها [CompanyPush] قبل هذا.
Future<bool> openSalaryDuePush(NavigatorState nav, Map<String, String> data) async {
  if (data['type'] != 'salary_due') return false;
  await nav.push(MaterialPageRoute(
    builder: (_) => MergedSection(
      readOnly: true,
      prefixes: const ['/api/v2/employees'],
      perms: const ['employees.view'],
      lockTitle: 'more.employees'.tr(),
      child: const EmployeesScreen(),
    ),
  ));
  return true;
}
