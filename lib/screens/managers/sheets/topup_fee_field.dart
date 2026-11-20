import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../api/topup_fee_api.dart';
import '../../../core/util/format.dart';
import '../../../core/widgets/design_sheet.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';

/// «الفائدة على الآجل» في نافذتي الشحن (الساس: balance_op_sheet، ايرث لنك: el_topup_sheet) — بدون · نسبة ٪ · مبلغ، ثمّ ما يدفعه
/// المدير قبل التنفيذ سطراً سطراً: الرصيد اللي ينشحن · الفائدة · المجموع على المدير (كالموقع: TopupFeeField.tsx).
/// الحقل لا يحمل حالةً: النوع والنصّ عند النافذة، فتُرسل ما يُعرض هنا نفسه.
class TopupFeeField extends StatelessWidget {
  const TopupFeeField({
    super.key,
    required this.base,
    required this.kind,
    required this.controller,
    required this.onKind,
    this.enabled = true,
  });

  /// مبلغ الشحن.
  final num base;
  final TopupFeeKind kind;
  final TextEditingController controller;
  final ValueChanged<TopupFeeKind> onKind;
  final bool enabled;

  static const _kinds = [TopupFeeKind.none, TopupFeeKind.percent, TopupFeeKind.fixed];

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final raw = controller.text;
    final problem = TopupFee.problem(kind, raw, base);
    final amount = TopupFee.amount(kind, TopupFee.parseValue(raw), base);
    return Container(
      key: const ValueKey('topup-fee'),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surfaceInput,
        borderRadius: BorderRadius.circular(R.sm),
        border: Border.all(color: AppColors.borderSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(LucideIcons.percent, size: 14, color: AppColors.textMid),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'الفائدة على الآجل',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.label(color: AppColors.textHi).copyWith(fontSize: 12.5, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SheetSegmented(
            key: const ValueKey('topup-fee-kind'),
            labels: const ['بدون', 'نسبة ٪', 'مبلغ'],
            selectedIndex: _kinds.indexOf(kind),
            onSelect: (i) {
              if (enabled) onKind(_kinds[i]);
            },
          ),
          if (kind != TopupFeeKind.none) ...[
            const SizedBox(height: 8),
            TextField(
              key: const ValueKey('topup-fee-value'),
              controller: controller,
              enabled: enabled,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              textDirection: TextDirection.ltr,
              style: AppType.input(color: AppColors.textHi),
              decoration: InputDecoration(
                hintText: kind == TopupFeeKind.percent ? 'مثلاً 2' : 'مثلاً 5,000',
                hintStyle: AppType.input(color: AppColors.textLow),
                filled: true,
                fillColor: AppColors.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(R.sm),
                  borderSide: BorderSide(color: AppColors.border),
                ),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                suffixText: kind == TopupFeeKind.percent ? '%' : 'د.ع',
              ),
            ),
            const SizedBox(height: 8),
            if (problem != null)
              Text(
                problem,
                key: const ValueKey('topup-fee-problem'),
                style: AppType.muted(color: AppColors.error).copyWith(fontSize: 11.5, fontWeight: FontWeight.w600),
              )
            else if (amount != null && base > 0)
              Column(
                key: const ValueKey('topup-fee-sum'),
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _sumRow('الرصيد اللي ينشحن', base),
                  const SizedBox(height: 4),
                  _sumRow('الفائدة', amount),
                  const SizedBox(height: 4),
                  _sumRow('المجموع على المدير', base + amount, strong: true),
                ],
              ),
            const SizedBox(height: 6),
            Text(
              'تُسجَّل ديناً عليه في «ديون أخرى» — الرصيد يصله كما هو',
              style: AppType.muted(color: AppColors.textMid).copyWith(fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }

  Widget _sumRow(String k, num v, {bool strong = false}) => Row(
        children: [
          // التسمية سطران عند الحاجة (لا «…» تقصّ نصّاً — 320 بخطٍّ مكبَّر)، والمبلغ كاملٌ دائماً
          Expanded(child: Text(k, maxLines: 2, style: AppType.muted().copyWith(fontSize: 12.5))),
          const SizedBox(width: 8),
          Text(
            '${formatIQD(v)} د.ع',
            textDirection: TextDirection.rtl,
            style: TextStyle(
              fontSize: strong ? 13.5 : 13,
              height: 1.35,
              fontWeight: FontWeight.w700,
              color: strong ? AppColors.warning : AppColors.textHi,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      );
}
