import 'package:easy_localization/easy_localization.dart' show StringTranslateExtension;
import 'package:flutter/material.dart';

import '../core/util/format.dart';
import '../theme/colors.dart';
import '../theme/typography.dart';
import 'company_tag.dart';

/// رصيد شركةٍ في «كل الشركات»: قيمته، أو سبب غيابه (تعذّرت القراءة، عملةٌ أخرى).
typedef MergedBalanceLine = ({String key, num? balance, String? reason});

/// أرصدة الشركات كلٌّ بسطره داخل بطاقة الرصيد نفسها (٨ نوفمبر — المالك: «بوضع دمج الشركات الارصده افصلهن الوكيل جاي يخربط
/// بالرصيد يعني مفروض رصيد كل صفحه بيبن منفصل ولكن بنفس الكارت»): لا مجموع — رصيد كلّ صفحةٍ عند ساسها وحده ولا يُصرف من غيره.
/// السالب (دينٌ على الوكيل) بلون الخطر. أكثر من [maxLines] ⇒ «و N أخرى».
class MergedBalanceLines extends StatelessWidget {
  const MergedBalanceLines({super.key, required this.lines, this.maxLines = 6, this.fontSize = 13});

  final List<MergedBalanceLine> lines;
  final int maxLines;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final shown = lines.take(maxLines).toList();
    final more = lines.length - shown.length;
    return Column(
      key: const ValueKey('merged-balance-lines'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final l in shown)
          Padding(
            key: ValueKey('merged-balance-${l.key}'),
            padding: const EdgeInsets.only(bottom: 5),
            child: Row(
              children: [
                Expanded(child: CompanyTag(companyKey: l.key, fontSize: fontSize - 1.5)),
                const SizedBox(width: 6),
                if (l.balance != null)
                  Text(
                    '${l.balance! < 0 ? '−' : ''}${formatIQD(l.balance!.abs().round())}',
                    textDirection: TextDirection.ltr,
                    style: AppType.label(color: l.balance! < 0 ? AppColors.error : AppColors.brand).copyWith(
                      fontSize: fontSize,
                      fontWeight: FontWeight.w700,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  )
                else
                  Flexible(
                    child: Text(
                      l.reason ?? 'merged.chip_failed'.tr(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
                      style: AppType.muted(color: AppColors.warning).copyWith(fontSize: fontSize - 2),
                    ),
                  ),
              ],
            ),
          ),
        if (more > 0)
          Text('و$more أخرى', style: AppType.muted(color: AppColors.textMid).copyWith(fontSize: fontSize - 2)),
      ],
    );
  }
}
