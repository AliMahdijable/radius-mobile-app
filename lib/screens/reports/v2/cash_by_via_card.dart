import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../api/transfer_pay_api.dart';
import '../../../core/util/format.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';
import '../../settlements/transfer_pots.dart' show transferViaIcon;
import 'report_kit.dart';

/// «النقد المُستلم حسب الطريقة» في التقرير الماليّ (٢٣ نوفمبر — «الحوالات»، كالموقع CashByViaCard): المجموع نفسه (الربح لا
/// يتغيّر)، مقسوماً كاش/زين كاش/ماستر/أخرى — يظهر حين يرسل الخادم `cash_by_via` (حوالةٌ بالفترة)، وتحته رصيد الحوالات الآن.
class CashByViaCard extends StatefulWidget {
  const CashByViaCard({super.key, required this.byVia, required this.total});

  final CashByViaData byVia;

  /// بطاقة «الإيراد النقدي» نفسها — المجموع لا يتغيّر.
  final num total;

  @override
  State<CashByViaCard> createState() => _CashByViaCardState();
}

class _CashByViaCardState extends State<CashByViaCard> {
  num? _potsTotal;

  @override
  void initState() {
    super.initState();
    // رصيد الحوالات الآن (صلاحيّة «تسوية الحساب») — تعذّر/لا صلاحيّة ⇒ لا سطر
    TransferPayApi.pots().then((p) {
      if (mounted && p != null) setState(() => _potsTotal = p.total);
    });
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final cur = 'common.currency'.tr();
    final rows = widget.byVia.rows(widget.total);
    Widget line(IconData icon, String label, String value, {bool strong = false, String? hint}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: Sp.x6),
          child: Row(children: [
            Icon(icon, size: 18, color: AppColors.textMid),
            const SizedBox(width: Sp.sm),
            Expanded(
              child: Text.rich(
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                TextSpan(children: [
                  TextSpan(text: label, style: strong ? AppType.bodyBold(color: AppColors.textHi) : AppType.body(color: AppColors.textHi)),
                  if (hint != null) TextSpan(text: '  $hint', style: AppType.micro(color: AppColors.textLow)),
                ]),
              ),
            ),
            const SizedBox(width: Sp.sm),
            Text(value, style: strong ? AppType.bodyBold(color: AppColors.textHi) : AppType.bodyStrong(color: AppColors.textHi)),
          ]),
        );
    return RpCard(
      key: const ValueKey('finance-cash-by-via'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const RpTitle(icon: LucideIcons.wallet, title: 'النقد المُستلم حسب الطريقة', tone: RpTone.money),
          const SizedBox(height: Sp.sm),
          for (final r in rows)
            line(r.via == 'cash' ? LucideIcons.banknote : transferViaIcon(r.via), r.label, '${formatIQD(r.sum.round())} $cur',
                hint: r.count == null ? null : '(${r.count})'),
          Divider(height: Sp.lg, color: AppColors.border),
          line(LucideIcons.sigma, 'المجموع (نفسه — الربح لا يتغيّر)', '${formatIQD(widget.total.round())} $cur', strong: true),
          if ((_potsTotal ?? 0) != 0) ...[
            const SizedBox(height: Sp.sm),
            Container(
              key: const ValueKey('finance-transfer-pots-now'),
              padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: Sp.sm),
              decoration: BoxDecoration(color: AppColors.surfaceSunken, borderRadius: BorderRadius.circular(R.md)),
              child: Row(children: [
                Icon(LucideIcons.arrowLeftRight, size: 18, color: AppColors.textMid),
                const SizedBox(width: Sp.sm),
                Expanded(
                  child: Text('رصيد الحوالات الآن — خارج الصندوق حتى تسحبه',
                      maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.muted(color: AppColors.textMid)),
                ),
                const SizedBox(width: Sp.sm),
                Text('${formatIQD(_potsTotal!.round())} $cur', style: AppType.bodyBold(color: AppColors.brand)),
              ]),
            ),
          ],
        ],
      ),
    );
  }
}
