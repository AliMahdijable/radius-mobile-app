import 'package:flutter/material.dart';

import '../core/util/bidi.dart';
import '../core/util/format.dart';
import '../models/merged_company.dart';
import '../services/merged_mode.dart';
import '../theme/colors.dart';
import '../theme/spacing.dart';
import '../theme/typography.dart';
import '../services/merged_text.dart';

/// رصيد شركةٍ في «كل الشركات»: قيمته، أو سبب غيابه (تعذّرت القراءة، عملةٌ أخرى).
typedef MergedBalanceLine = ({String key, num? balance, String? reason});

/// اسم الشركة سطرين: العلامة («سوبرنت (SuperNet)») ثمّ الحساب («admin@b» · رقمه) — الاسم الواحد الطويل كان يُقصّ عند العلامة
/// فتتشابه ثلاث «سوبرنت…» (صورة المالك ٨ نوفمبر).
({String brand, String? account}) mergedNameParts(MergedCompany? c, String fallbackKey) {
  if (c == null) return (brand: fallbackKey, account: null);
  final name = c.name.trim();
  final i = name.indexOf('·');
  if (i > 0) {
    final account = name.substring(i + 1).trim();
    return (brand: name.substring(0, i).trim(), account: account.isEmpty ? null : account);
  }
  final u = c.username.trim();
  return (brand: name, account: u.isEmpty || name.contains(u) ? null : u);
}

String _amount(num v) => '${v < 0 ? '−' : ''}${formatIQD(v.abs().round())}';

/// أرصدة الشركات خاناتٍ مرتّبة بعمودين (٨ نوفمبر — المالك: «رصيد كل صفحه بيبن منفصل ولكن بنفس الكارت» ثمّ «الرصيد شوف شون صاير!
/// يحتاج تفكر بطريقة اخرى»): لكلّ شركةٍ خانة — نقطة لونها وعلامتها وحسابها ورصيدها كبيراً — بلا مجموع (رصيد كلّ صفحةٍ عند ساسها وحده).
class MergedBalanceTiles extends StatelessWidget {
  const MergedBalanceTiles({super.key, required this.lines});

  final List<MergedBalanceLine> lines;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return LayoutBuilder(builder: (context, box) {
      const gap = Sp.sm;
      final cols = box.maxWidth >= 520 ? 3 : 2;
      final w = (box.maxWidth - gap * (cols - 1)) / cols;
      return Wrap(
        key: const ValueKey('merged-balance-lines'),
        spacing: gap,
        runSpacing: gap,
        children: [
          for (final l in lines) SizedBox(width: w, child: _Tile(l)),
        ],
      );
    });
  }
}

class _Tile extends StatelessWidget {
  const _Tile(this.l);
  final MergedBalanceLine l;

  @override
  Widget build(BuildContext context) {
    final c = MergedMode.companyOf(l.key);
    final n = mergedNameParts(c, l.key);
    final neg = (l.balance ?? 0) < 0;
    return Container(
      key: ValueKey('merged-balance-${l.key}'),
      padding: const EdgeInsets.fromLTRB(Sp.sm, Sp.sm, Sp.sm, Sp.sm),
      decoration: BoxDecoration(
        color: AppColors.surfaceSunken,
        borderRadius: BorderRadius.circular(R.md),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: AppColors.company(c?.colorIndex ?? 0), shape: BoxShape.circle),
          ),
          const SizedBox(width: Sp.x6),
          Expanded(
            child: Text(n.brand,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppType.label(color: AppColors.textHi).copyWith(fontSize: 12.5, fontWeight: FontWeight.w700)),
          ),
        ]),
        if (n.account != null)
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 14),
            child: Text(iso(n.account!),
                maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.muted(color: AppColors.textLow).copyWith(fontSize: 11)),
          ),
        const SizedBox(height: Sp.x6),
        if (l.balance != null)
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  _amount(l.balance!),
                  textDirection: TextDirection.ltr,
                  style: AppType.title(color: neg ? AppColors.error : AppColors.brand).copyWith(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    height: 1.1,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(width: 4),
                Text('IQD',
                    style: AppType.muted(color: AppColors.textLow).copyWith(fontSize: 10.5, fontWeight: FontWeight.w700)),
              ],
            ),
          )
        else
          Text(l.reason ?? 'merged.chip_failed'.trm(),
              maxLines: 2, style: AppType.muted(color: AppColors.warning).copyWith(fontSize: 11.5)),
      ]),
    );
  }
}

/// الصيغة المضغوطة للحاسبة (بطاقة الرصيد بين أربع): سطرٌ لكلّ شركة — العلامة وحسابها تحتها، والرصيد بطرفه.
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
            padding: const EdgeInsets.only(bottom: Sp.x6),
            child: Row(children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                    color: AppColors.company(MergedMode.companyOf(l.key)?.colorIndex ?? 0), shape: BoxShape.circle),
              ),
              const SizedBox(width: Sp.x6),
              Expanded(
                child: Builder(builder: (_) {
                  final n = mergedNameParts(MergedMode.companyOf(l.key), l.key);
                  return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    Text(n.brand,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppType.label(color: AppColors.textHi).copyWith(fontSize: fontSize - 1, fontWeight: FontWeight.w600)),
                    if (n.account != null)
                      Text(iso(n.account!),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppType.muted(color: AppColors.textLow).copyWith(fontSize: fontSize - 2.5)),
                  ]);
                }),
              ),
              const SizedBox(width: Sp.x6),
              if (l.balance != null)
                Text(
                  _amount(l.balance!),
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
                    l.reason ?? 'merged.chip_failed'.trm(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.end,
                    style: AppType.muted(color: AppColors.warning).copyWith(fontSize: fontSize - 2),
                  ),
                ),
            ]),
          ),
        if (more > 0)
          Text('و$more أخرى', style: AppType.muted(color: AppColors.textMid).copyWith(fontSize: fontSize - 2)),
      ],
    );
  }
}
