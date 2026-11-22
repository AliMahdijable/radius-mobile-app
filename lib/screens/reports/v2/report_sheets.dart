import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/widgets/design_sheet.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';
import 'report_kit.dart';

// ورقتا التقرير الموحّد (٢٢ نوفمبر — نموذج المقترح، انظر report_kit.dart): الفلاتر كلّها في ورقةٍ واحدة بالترتيب نفسه لكلّ تقرير،
// وحركات رقمٍ لُمست بطاقته. ⏳ غير مربوطتين بعد.

/// اختيارٌ في قائمة (مدير، موظّف): [depth] ١ = مدير فرعيّ تحت من فوقه.
class RpPick {
  const RpPick(this.name, {this.on = false, this.depth = 0, this.sub});
  final String name;
  final bool on;
  final int depth;

  /// «مدير فرعيّ» · «موظّفة».
  final String? sub;
}

/// قائمة شركةٍ واحدة («كل الشركات» — كلّ شركةٍ بمدرائها هي)؛ [company] null في الشركة المنفردة.
class RpPickGroup {
  const RpPickGroup({this.company, required this.items});
  final RpCompany? company;
  final List<RpPick> items;
}

class RpFilterSheet extends StatelessWidget {
  const RpFilterSheet({
    super.key,
    required this.subtitle,
    required this.periods,
    required this.period,
    required this.compareOn,
    this.companies,
    required this.managers,
    required this.withSubs,
    required this.employees,
    required this.types,
    required this.payments,
    required this.results,
  });

  /// «التقرير الماليّ · هذا الشهر».
  final String subtitle;
  final List<String> periods;
  final String period;
  final bool compareOn;

  /// «كل الشركات» وحده.
  final List<RpCompany>? companies;
  final List<RpPickGroup> managers;
  final bool withSubs;
  final List<RpPickGroup> employees;
  final List<(String, bool)> types;
  final List<(String, bool)> payments;

  /// عدد الحركات بالاختيار الحاليّ — على زرّ «عرض النتائج».
  final int results;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final cos = companies;
    return DesignSheet(
      header: SheetHeaderBar(
        icon: LucideIcons.slidersHorizontal,
        title: 'الفلاتر',
        subtitle: subtitle,
        onClose: () {},
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SheetSection(
            label: 'الفترة',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: Sp.sm,
                  runSpacing: Sp.sm,
                  children: [for (final p in periods) SheetQuickChip(label: p, selected: p == period, onTap: () {})],
                ),
                const SizedBox(height: Sp.sm),
                _switchRow('قارن بالفترة السابقة', 'تحت كلّ رقم: فرقه عن الفترة السابقة ونسبته', compareOn),
              ],
            ),
          ),
          if (cos != null) ...[
            const SizedBox(height: Sp.xl),
            SheetSection(
              label: 'الشركات',
              hint: 'تختار أكثر من شركة',
              child: Wrap(
                spacing: Sp.sm,
                runSpacing: Sp.sm,
                children: [for (final c in cos) _companyChip(c)],
              ),
            ),
          ],
          const SizedBox(height: Sp.xl),
          SheetSection(
            label: 'المدير',
            hint: cos != null ? 'مدراء كلّ شركة تحت اسمها' : 'المدير ومدراؤه الفرعيّون',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _groups(managers),
                const SizedBox(height: Sp.sm),
                _switchRow('مع مدرائه الفرعيّين', 'حركاتهم تدخل مع حركات من تختاره', withSubs),
              ],
            ),
          ),
          const SizedBox(height: Sp.xl),
          SheetSection(label: 'الموظّف', hint: 'من نفّذ الحركة', child: _groups(employees)),
          const SizedBox(height: Sp.xl),
          SheetSection(
            label: 'نوع الحركة',
            child: Wrap(
              spacing: Sp.sm,
              runSpacing: Sp.sm,
              children: [for (final t in types) SheetQuickChip(label: t.$1, selected: t.$2, onTap: () {})],
            ),
          ),
          const SizedBox(height: Sp.xl),
          SheetSection(
            label: 'طريقة الدفع',
            child: Wrap(
              spacing: Sp.sm,
              runSpacing: Sp.sm,
              children: [for (final t in payments) SheetQuickChip(label: t.$1, selected: t.$2, onTap: () {})],
            ),
          ),
        ],
      ),
      footer: SheetFooterBar(
        label: 'عرض النتائج · $results',
        icon: LucideIcons.check,
        onPressed: () {},
        leading: SizedBox(
          height: H.button,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: Sp.lg),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(R.button),
              border: Border.all(color: AppColors.dangerSoftBorder),
            ),
            child: Text('مسح الكلّ', style: AppType.buttonBold(color: AppColors.error)),
          ),
        ),
      ),
    );
  }

  Widget _switchRow(String title, String hint, bool on) => Container(
        padding: const EdgeInsetsDirectional.only(start: Sp.md, end: Sp.xs, top: Sp.xs, bottom: Sp.xs),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(R.icon),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppType.bodyBold(color: AppColors.textHi), maxLines: 1),
                  Text(hint, style: AppType.micro(color: AppColors.textMid), maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            Switch(
              value: on,
              onChanged: (_) {},
              activeThumbColor: AppColors.onBrand,
              activeTrackColor: AppColors.brand,
            ),
          ],
        ),
      );

  Widget _companyChip(RpCompany c) => Container(
        height: H.chip,
        padding: const EdgeInsets.symmetric(horizontal: Sp.md),
        decoration: BoxDecoration(
          color: c.selected ? c.color.withValues(alpha: 0.12) : AppColors.surface,
          borderRadius: BorderRadius.circular(R.pill),
          border: Border.all(color: c.selected ? c.color : AppColors.border, width: c.selected ? BW.selected : BW.normal),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (c.selected)
              Icon(LucideIcons.check, size: 14, color: c.color)
            else
              Container(width: 8, height: 8, decoration: BoxDecoration(color: c.color, shape: BoxShape.circle)),
            const SizedBox(width: Sp.x6),
            Text(c.name, style: AppType.pillBold(color: c.selected ? AppColors.textHi : AppColors.textMid), maxLines: 1),
          ],
        ),
      );

  Widget _groups(List<RpPickGroup> groups) => Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(R.lg),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var g = 0; g < groups.length; g++) ...[
              if (g > 0) Divider(height: 1, color: AppColors.divider),
              if (groups[g].company != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(Sp.md, Sp.sm, Sp.md, Sp.xxs),
                  child: Row(
                    children: [
                      Container(
                          width: 8, height: 8, decoration: BoxDecoration(color: groups[g].company!.color, shape: BoxShape.circle)),
                      const SizedBox(width: Sp.x6),
                      Text(groups[g].company!.name, style: AppType.labelBold(color: AppColors.textMid)),
                    ],
                  ),
                ),
              for (final p in groups[g].items) _pick(p),
            ],
          ],
        ),
      );

  Widget _pick(RpPick p) => Padding(
        padding: EdgeInsetsDirectional.only(start: Sp.md + p.depth * Sp.xl, end: Sp.md, top: Sp.sm, bottom: Sp.sm),
        child: Row(
          children: [
            Container(
              width: H.checkbox,
              height: H.checkbox,
              decoration: BoxDecoration(
                color: p.on ? AppColors.brand : AppColors.surface,
                borderRadius: BorderRadius.circular(R.check),
                border: Border.all(color: p.on ? AppColors.brand : AppColors.borderStrong, width: BW.selected),
              ),
              child: p.on ? const Icon(LucideIcons.check, size: 14, color: AppColors.onBrand) : null,
            ),
            const SizedBox(width: Sp.md),
            if (p.depth > 0) ...[
              Icon(LucideIcons.cornerDownLeft, size: 14, color: AppColors.textLow),
              const SizedBox(width: Sp.xs),
            ],
            Expanded(
              child: Text(p.name, style: AppType.bodyBold(color: AppColors.textHi), maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            if (p.sub != null) Text(p.sub!, style: AppType.micro(color: AppColors.textLow), maxLines: 1),
          ],
        ),
      );
}

/// لمسة بطاقة رقم ⇒ الحركات التي صنعته، بالفترة والفلاتر نفسها — وتُصدَّر وحدها.
class RpDrillSheet extends StatelessWidget {
  const RpDrillSheet({super.key, required this.kpi, required this.scope, required this.chips, required this.rows});
  final RpKpi kpi;

  /// «هذا الشهر · سوبرنت، ايرث لنك».
  final String scope;
  final List<String> chips;
  final RpRowsCard rows;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return DesignSheet(
      header: SheetHeaderBar(
        icon: kpi.icon,
        title: kpi.label,
        subtitle: scope,
        onClose: () {},
        tint: kpi.tone.fg,
        tintBg: kpi.tone.soft,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          RpCard(
            tint: kpi.tone.fg,
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('المجموع', style: AppType.label(color: AppColors.textMid)),
                      RpFitText(kpi.text, style: AppType.amount(color: kpi.tone.fg)),
                    ],
                  ),
                ),
                const SizedBox(width: Sp.md),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('${rows.total}', style: AppType.statValue(color: AppColors.textHi)),
                    Text('حركة', style: AppType.micro(color: AppColors.textMid)),
                  ],
                ),
              ],
            ),
          ),
          if (chips.isNotEmpty) ...[
            const SizedBox(height: Sp.md),
            RpFilterBar(chips: chips),
          ],
          const SizedBox(height: Sp.md),
          rows,
        ],
      ),
      footer: SheetFooterBar(label: 'تصدير هذه الحركات', icon: LucideIcons.share2, onPressed: () {}),
    );
  }
}
