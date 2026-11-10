import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../api/merged_dashboard_api.dart';
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
    return _TileWrap(
      wrapKey: const ValueKey('merged-balance-lines'),
      children: [for (final l in lines) _Tile(l)],
    );
  }
}

/// خانات الشركات بعمودين (وثلاثة حيث يتّسع) — الرصيد والمدينون بالشبكة نفسها.
class _TileWrap extends StatelessWidget {
  const _TileWrap({required this.wrapKey, required this.children});

  final Key wrapKey;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      const gap = Sp.sm;
      final cols = box.maxWidth >= 520 ? 3 : 2;
      final w = (box.maxWidth - gap * (cols - 1)) / cols;
      return Wrap(
        key: wrapKey,
        spacing: gap,
        runSpacing: gap,
        children: [
          for (final c in children) SizedBox(width: w, child: c),
        ],
      );
    });
  }
}

/// إطار خانة شركة: نقطة لونها وعلامتها، وحسابها تحتها، ثمّ [body] (رصيدها، أو دينها، أو سبب غيابه).
class _CompanyTile extends StatelessWidget {
  const _CompanyTile({super.key, required this.companyKey, required this.body});

  final String companyKey;
  final List<Widget> body;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final c = MergedMode.companyOf(companyKey);
    final n = mergedNameParts(c, companyKey);
    return Container(
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
        ...body,
      ]),
    );
  }
}

/// مبلغ الخانة كبيراً ووحدته — يصغر ولا يُقصّ.
class _TileAmount extends StatelessWidget {
  const _TileAmount({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: AlignmentDirectional.centerStart,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(
            text,
            textDirection: TextDirection.ltr,
            style: AppType.title(color: color).copyWith(
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
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile(this.l);
  final MergedBalanceLine l;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final neg = (l.balance ?? 0) < 0;
    return _CompanyTile(
      key: ValueKey('merged-balance-${l.key}'),
      companyKey: l.key,
      body: [
        if (l.balance != null)
          _TileAmount(text: _amount(l.balance!), color: neg ? AppColors.error : AppColors.brand)
        else
          Text(l.reason ?? 'merged.chip_failed'.trm(),
              maxLines: 2, style: AppType.muted(color: AppColors.warning).copyWith(fontSize: 11.5)),
      ],
    );
  }
}

/// سطر شركةٍ في الصيغة المضغوطة: نقطة لونها، وعلامتها وحسابها تحتها، و[trailing] بطرفه.
class _CompanyLine extends StatelessWidget {
  const _CompanyLine({super.key, required this.companyKey, required this.fontSize, required this.trailing});

  final String companyKey;
  final double fontSize;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final c = MergedMode.companyOf(companyKey);
    final n = mergedNameParts(c, companyKey);
    return Padding(
      padding: const EdgeInsets.only(bottom: Sp.x6),
      child: Row(children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: AppColors.company(c?.colorIndex ?? 0), shape: BoxShape.circle),
        ),
        const SizedBox(width: Sp.x6),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(n.brand,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppType.label(color: AppColors.textHi)
                    .copyWith(fontSize: fontSize - 1, fontWeight: FontWeight.w600)),
            if (n.account != null)
              Text(iso(n.account!),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.muted(color: AppColors.textLow).copyWith(fontSize: fontSize - 2.5)),
          ]),
        ),
        const SizedBox(width: Sp.x6),
        trailing,
      ]),
    );
  }
}

/// سبب غياب الشركة بطرف سطرها — يأخذ ما بقي ويُقصّ ولا يدفع الاسم.
Widget _lineReason(String text, Color color, double fontSize) => Flexible(
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.end,
        style: AppType.muted(color: color).copyWith(fontSize: fontSize - 2),
      ),
    );

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
          _CompanyLine(
            key: ValueKey('merged-balance-${l.key}'),
            companyKey: l.key,
            fontSize: fontSize,
            trailing: l.balance != null
                ? Text(
                    _amount(l.balance!),
                    textDirection: TextDirection.ltr,
                    style: AppType.label(color: l.balance! < 0 ? AppColors.error : AppColors.brand).copyWith(
                      fontSize: fontSize,
                      fontWeight: FontWeight.w700,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  )
                : _lineReason(l.reason ?? 'merged.chip_failed'.trm(), AppColors.warning, fontSize),
          ),
        if (more > 0)
          Text('و$more أخرى', style: AppType.muted(color: AppColors.textMid).copyWith(fontSize: fontSize - 2)),
      ],
    );
  }
}

// ── «المدينون — لكلّ شركة» (١٠ نوفمبر): خانات الرصيد نفسها بمبلغ الدين وعدد المدينين — البطاقتان زوجٌ واحد ──

String _debtors(int n) => '${formatIQD(n)} ${'dashboard.subscriber_singular'.tr()}';

/// ديون الشركات خاناتٍ بشبكة خانات الرصيد: مبلغ مدينيها كبيراً وعددهم تحته، أو سبب غيابها عن المجموع (بلا رقم).
class MergedDebtTiles extends StatelessWidget {
  const MergedDebtTiles({super.key, required this.lines});

  final List<MergedDebtLine> lines;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return _TileWrap(
      wrapKey: const ValueKey('merged-debt-lines'),
      children: [
        for (final l in lines)
          _CompanyTile(
            key: ValueKey('merged-debt-${l.key}'),
            companyKey: l.key,
            body: [
              if (l.amount != null) ...[
                _TileAmount(text: formatIQD(l.amount!), color: AppColors.warning),
                const SizedBox(height: 3),
                Text(_debtors(l.count ?? 0),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.muted(color: AppColors.textMid).copyWith(fontSize: 11, fontWeight: FontWeight.w600)),
              ] else
                Text(l.reason ?? 'merged.chip_failed'.trm(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.muted(color: AppColors.textMid).copyWith(fontSize: 11.5)),
            ],
          ),
      ],
    );
  }
}

/// الصيغة المضغوطة للحاسبة: سطرٌ لكلّ شركة — المبلغ بطرفه وعدد المدينين تحته، أو السبب.
class MergedDebtLines extends StatelessWidget {
  const MergedDebtLines({super.key, required this.lines, this.maxLines = 6, this.fontSize = 13, this.color});

  final List<MergedDebtLine> lines;
  final int maxLines;
  final double fontSize;

  /// لون المبلغ (لون بطاقته) — افتراضاً لون الدين في الهاتف.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final shown = lines.take(maxLines).toList();
    final more = lines.length - shown.length;
    return Column(
      key: const ValueKey('merged-debt-lines'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final l in shown)
          _CompanyLine(
            key: ValueKey('merged-debt-${l.key}'),
            companyKey: l.key,
            fontSize: fontSize,
            trailing: l.amount != null
                ? Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
                    Text(
                      formatIQD(l.amount!),
                      textDirection: TextDirection.ltr,
                      style: AppType.label(color: color ?? AppColors.warning).copyWith(
                        fontSize: fontSize,
                        fontWeight: FontWeight.w700,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    Text(_debtors(l.count ?? 0),
                        style: AppType.muted(color: AppColors.textLow).copyWith(fontSize: fontSize - 2.5)),
                  ])
                : _lineReason(l.reason ?? 'merged.chip_failed'.trm(), AppColors.textMid, fontSize),
          ),
        if (more > 0)
          Text('و$more أخرى', style: AppType.muted(color: AppColors.textMid).copyWith(fontSize: fontSize - 2)),
      ],
    );
  }
}

/// سطر «بلا …» تحت مجموع المدينين: من لم يدخله ولماذا ([MergedDebts.leftNote]) — لا شيء إن دخلت الشركات كلّها.
class MergedDebtNote extends StatelessWidget {
  const MergedDebtNote({super.key, required this.debts, this.fontSize = 11.5});

  final MergedDebts debts;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final note = debts.leftNote();
    if (note == null) return const SizedBox.shrink();
    return Row(
      key: const ValueKey('merged-debt-note'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(LucideIcons.info, size: fontSize, color: AppColors.warning),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Text(note,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppType.muted(color: AppColors.textMid).copyWith(fontSize: fontSize, fontWeight: FontWeight.w500)),
        ),
      ],
    );
  }
}
