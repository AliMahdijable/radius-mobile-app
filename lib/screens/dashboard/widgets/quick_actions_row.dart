import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../services/permissions_service.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';
import '../../reports/reports_hub_screen.dart';
import '../../subscribers/sheets/activate_sheet.dart';
import '../../subscribers/sheets/add_subscriber_sheet.dart';
import '../../subscribers/sheets/pay_debt_sheet.dart';
import '../../subscribers/sheets/subscriber_picker_sheet.dart';

/// صفّ الإجراءات السريعة أسفل بطاقة الإيرادات.
///
/// الأربعة كانت مدفونة خلف زرّ «+» في الشريط السفلي: الوصول إليها
/// نقرتان ومعرفةٌ مسبقة بأنّها هناك. وهي أكثر ما يُفعل يوميّاً — تجديد
/// وتسديد وإضافة مشترك — فمكانها الطبيعي سطح الشاشة الأولى.
///
/// ⚠️ كلّ زرّ محكوم بصلاحيّته: الموظّف بلا صلاحيّة لا يرى الزرّ أصلاً
/// بدل أن يضغطه فيُرفض. والصفّ كلّه يختفي حين لا يبقى زرّ واحد — لا
/// يترك صفّاً فارغاً يأكل مساحة.
class QuickActionsRow extends StatelessWidget {
  const QuickActionsRow({super.key});

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)

    final items = <Widget>[];

    if (Perms.has('reports.view')) {
      items.add(_QuickAction(
        icon: LucideIcons.chartColumn,
        tone: AppTone.info,
        label: 'dashboard.reports'.tr(),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const ReportsHubScreen()),
        ),
      ));
    }

    if (Perms.hasAny(const ['subscribers.activate', 'subscribers.extend'])) {
      items.add(_QuickAction(
        icon: LucideIcons.zap,
        tone: AppTone.brand,
        label: 'dashboard.renew_sub'.tr(),
        onTap: () async {
          final picked = await showSubscriberPickerSheet(
            context,
            title: 'dashboard.renew_sub'.tr(),
          );
          if (picked != null && context.mounted) {
            await showActivateSheet(context, picked);
          }
        },
      ));
    }

    if (Perms.has('subscribers.pay_debt')) {
      items.add(_QuickAction(
        icon: LucideIcons.banknote,
        tone: AppTone.success,
        label: 'dashboard.pay_debt'.tr(),
        onTap: () async {
          final picked = await showSubscriberPickerSheet(
            context,
            title: 'dashboard.pay_debt'.tr(),
            // بلا هذا يظهر كلّ المشتركين ثمّ يُفاجأ المدير بأنّ من
            // اختاره لا دين عليه — الفلتر جزء من المعنى لا تحسين.
            debtorsOnly: true,
          );
          if (picked != null && context.mounted) {
            await showPayDebtSheet(context, picked);
          }
        },
      ));
    }

    if (Perms.has('subscribers.add')) {
      items.add(_QuickAction(
        icon: LucideIcons.userPlus,
        tone: AppTone.warning,
        label: 'dashboard.add_subscriber'.tr(),
        onTap: () => showAddSubscriberSheet(context),
      ));
    }

    if (items.isEmpty) return const SizedBox.shrink();

    return Row(
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(child: items[i]),
        ],
      ],
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.icon,
    required this.tone,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final AppTone tone;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(R.card),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(R.card),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(R.card),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: tone.softBg,
                  borderRadius: BorderRadius.circular(R.icon),
                ),
                child: Icon(icon, size: 17, color: tone.fill),
              ),
              const SizedBox(height: 7),
              // سطر واحد بقصّ: التسميات الإنجليزيّة أطول، والالتفاف
              // يجعل أزرار الصفّ مختلفة الارتفاع.
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: AppType.micro(color: AppColors.textMid),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
