import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../services/merged_mode.dart';
import '../theme/colors.dart';
import '../theme/spacing.dart';
import '../theme/typography.dart';
import 'company_tag.dart';

/// سطرٌ في «حسب الشركة»: رقمها وسطرٌ تحته، أو سبب غيابها.
typedef MergedBreakdownRow = ({String key, String? value, String? sub, String? reason});

/// «كل الشركات»: بطاقة «حسب الشركة» — سطرٌ لكلّ شركة برقمها (أو سبب غيابها)، والضغط يعرضها وحدها. بتصميم بطاقة التقرير
/// الماليّ نفسها (financial_report_screen _mergedBreakdown).
class MergedBreakdownCard extends StatelessWidget {
  const MergedBreakdownCard({super.key, required this.rows});

  final List<MergedBreakdownRow> rows;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Container(
      key: const ValueKey('merged-breakdown'),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.lg),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(Sp.md, Sp.md, Sp.md, Sp.xs),
            child: Text('merged.finance_by_company'.tr(),
                style: AppType.label(color: AppColors.textHi).copyWith(fontSize: 13, fontWeight: FontWeight.w700)),
          ),
          for (final r in rows)
            InkWell(
              key: ValueKey('merged-breakdown-${r.key}'),
              onTap: () => MergedMode.focus.value = r.key,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: 10),
                child: Row(
                  children: [
                    Expanded(child: CompanyTag(companyKey: r.key, fontSize: 12.5)),
                    const SizedBox(width: Sp.sm),
                    if (r.value != null)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(r.value!, style: AppType.rowLabelBold(color: AppColors.textHi)),
                          if (r.sub != null)
                            Text(r.sub!, style: AppType.muted(color: AppColors.textMid).copyWith(fontSize: 11)),
                        ],
                      )
                    else
                      Flexible(
                        child: Text(
                          r.reason ?? 'common.load_failed'.tr(),
                          textAlign: TextAlign.end,
                          style: AppType.muted(color: AppColors.warning).copyWith(fontSize: 11.5),
                        ),
                      ),
                    const SizedBox(width: 4),
                    Icon(Icons.chevron_left_rounded, size: 18, color: AppColors.textLow),
                  ],
                ),
              ),
            ),
          const SizedBox(height: Sp.xs),
        ],
      ),
    );
  }
}
