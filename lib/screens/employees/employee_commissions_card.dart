import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../api/employee_commissions_api.dart';
import '../../core/util/format.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import '../reports/v2/report_kit.dart';

/// «عمولات الموظفين» (٢٦ نوفمبر — المالك: «شون رح يميز ٥ الالف رحت للموظف»): تحت مؤشّرات التقرير الماليّ — كبطاقة الموقع (e735fb0):
/// المجموع، ولكلّ موظّفٍ عمليّاته الكاملة بالفترة وعمولته، و«صافي الربح بعد العمولات» لمن تُصرف عمولته بكشفه. بلا سطور شرح (المالك
/// بعد اللقطة: «بس يظهر سعر الكلي والحركه»). لا تغيّر الأرقام أعلاه — العمولة تدخلها صرفيّةً يوم صرف كشفها. الشاشة تقرأ
/// [EmpCommissions] بنفسها وتضيف البطاقة حين [EmpCommissions.any] وحده.
class EmployeeCommissionsCard extends StatelessWidget {
  const EmployeeCommissionsCard({super.key, required this.c, this.net});

  final EmpCommissions c;

  /// الصافي المعروض بالبطاقة الكبرى — null ⇒ بلا سطر «بعد العمولات».
  final num? net;

  @override
  Widget build(BuildContext context) {
    final rows = c.employees.where((e) => e.ops > 0).toList();
    final showNet = net != null && c.hasNetAdjust;
    return RpCard(
      key: const ValueKey('emp-comm-card'),
      tint: AppColors.info,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          RpTitle(
            icon: LucideIcons.handCoins,
            title: 'عمولات الموظفين (${empOpsText(c.ops)})',
            tone: RpTone.info,
            trailing: Text(
              '${formatIQD(c.amount)} د.ع',
              key: const ValueKey('emp-comm-total'),
              style: AppType.bodyBold(color: AppColors.info),
            ),
          ),
          const SizedBox(height: Sp.sm),
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) Divider(height: 1, color: AppColors.border),
            _row(rows[i]),
          ],
          if (showNet) ...[
            const SizedBox(height: Sp.x6),
            Container(
              key: const ValueKey('emp-comm-net'),
              padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: Sp.sm),
              decoration: BoxDecoration(color: AppColors.surfaceSunken, borderRadius: BorderRadius.circular(R.button)),
              child: Row(
                children: [
                  Expanded(
                    child: Text('صافي الربح بعد العمولات', maxLines: 2, style: AppType.bodyBold(color: AppColors.textHi)),
                  ),
                  const SizedBox(width: Sp.sm),
                  Text(
                    '${formatIQDSigned(c.netAfter(net!))} د.ع',
                    key: const ValueKey('emp-comm-net-value'),
                    style: AppType.bodyBold(color: AppColors.textHi),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _row(EmpCommissionRow r) => Padding(
        key: ValueKey('emp-comm-${r.employeeId}'),
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
                    empOpsText(r.ops),
                    key: ValueKey('emp-comm-ops-${r.employeeId}'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.micro(color: AppColors.textMid),
                  ),
                ],
              ),
            ),
            const SizedBox(width: Sp.sm),
            Text(
              '${formatIQD(r.amount)} د.ع',
              key: ValueKey('emp-comm-amount-${r.employeeId}'),
              style: AppType.bodyBold(color: AppColors.textHi),
            ),
          ],
        ),
      );
}
