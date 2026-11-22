import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/util/format.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';

// «التقارير — الشكل الموحّد» (٢٢ نوفمبر — المالك: «التقارير بشكل عامة اريد تهتم بتصميمها من جديد كل انواع التقارير بوضع كل
// الشركات من ناحيه الفلاتر وبوضع الشركه المنفرده»، ثمّ «صور وشرح تكدر تسوي حتى وراها نبلش؟»).
//
// أجزاء كلّ تقرير بترتيبٍ واحد: الفترة والمقارنة ← الشركات (بكل الشركات) ← الفلاتر الفعّالة ← «حسب الشركة» ← بطاقات الأرقام ←
// يوماً بيوم ← «قسّم حسب» ← الحركات ← التصدير. كلّ جزءٍ يأخذ أرقامه جاهزة (لا طلب ولا حساب هنا) — التقرير يملأها من الخادم.
// ⏳ غير مربوطٍ بشاشةٍ بعد: صور المقترح تُرسم منه، وبعد موافقة المالك تُبنى التقارير عليه.

/// عائلة الرقم ولونه — المال أخضر، الدين كهرمانيّ، الخسارة/الصرف أحمر، العلامة للمبيعات، الأزرق للعدّ والزمن.
enum RpTone { money, debt, loss, brand, info, neutral }

extension RpToneColors on RpTone {
  Color get fg => switch (this) {
        RpTone.money => AppColors.success,
        RpTone.debt => AppColors.warning,
        RpTone.loss => AppColors.error,
        RpTone.brand => AppColors.brand,
        RpTone.info => AppColors.info,
        RpTone.neutral => AppColors.textMid,
      };

  Color get soft => switch (this) {
        RpTone.money => AppColors.successSoftBg,
        RpTone.debt => AppColors.warningSoftBg,
        RpTone.loss => AppColors.dangerSoftBg,
        RpTone.brand => AppColors.brandSoftBg,
        RpTone.info => AppColors.infoSoftBg,
        RpTone.neutral => AppColors.surfaceSunken,
      };
}

/// المبلغ بالدينار كما يُكتب في التطبيق: «12,450,000 د.ع».
String rpMoney(num v) => '${formatIQD(v)} د.ع';

/// رقمٌ مختصر لمحور الرسم: «1.5 مليون» · «500 ألف».
String rpCompact(num v) {
  final a = v.abs();
  if (a >= 1000000) {
    final m = a / 1000000;
    return '${m == m.roundToDouble() ? m.toStringAsFixed(0) : m.toStringAsFixed(1)} مليون';
  }
  if (a >= 1000) return '${(a / 1000).round()} ألف';
  return '${a.round()}';
}

// ═══════════════════════════════ النماذج ═══════════════════════════════

class RpPeriod {
  const RpPeriod({required this.name, required this.range});

  /// «هذا الشهر» · «أمس» · «مخصّص».
  final String name;

  /// «2026/11/01 – 2026/11/22» (أرقامٌ لا أسماء أشهر).
  final String range;
}

class RpCompany {
  const RpCompany({required this.name, required this.colorIndex, this.selected = false, this.note});
  final String name;
  final int colorIndex;
  final bool selected;

  /// سطرٌ صغير تحت الاسم في الشريط («جارٍ…» · «تعذّرت»).
  final String? note;

  Color get color => AppColors.company(colorIndex);
}

class RpKpi {
  const RpKpi({
    required this.label,
    required this.value,
    required this.icon,
    required this.tone,
    this.delta,
    this.upIsGood = true,
    this.isCount = false,
    this.unit,
  });

  final String label;
  final num value;
  final IconData icon;
  final RpTone tone;

  /// الفرق عن الفترة السابقة نسبةً (0.12 = +12%) — null بلا مقارنة.
  final double? delta;

  /// الدين والصرف: الصعود سيّئ (أحمر) والنزول جيّد (أخضر).
  final bool upIsGood;
  final bool isCount;

  /// وحدة العدّ («تفعيل»).
  final String? unit;

  String get text => isCount ? '${formatIQD(value)}${unit == null ? '' : ' $unit'}' : rpMoney(value);
}

class RpTrendPoint {
  const RpTrendPoint(this.day, this.a, this.b);
  final int day;
  final num a;
  final num b;
}

class RpShare {
  const RpShare({required this.name, required this.amount, required this.count, required this.share, this.company, this.sub});
  final String name;
  final num amount;
  final int count;
  final double share;

  /// «كل الشركات»: الشركة صاحبة السطر.
  final RpCompany? company;

  /// سطرٌ فرعيّ («مدير فرعيّ لعلي حسن»).
  final String? sub;
}

enum RpCompanyState { ok, loading, failed }

class RpCompanyLine {
  const RpCompanyLine({required this.company, this.state = RpCompanyState.ok, this.a, this.b, this.c});
  final RpCompany company;
  final RpCompanyState state;
  final num? a;
  final num? b;
  final num? c;
}

class RpRow {
  const RpRow({
    required this.icon,
    required this.tone,
    required this.title,
    required this.detail,
    required this.amount,
    required this.time,
    this.company,
    this.negative = false,
  });

  final IconData icon;
  final RpTone tone;

  /// اسم المشترك (أو بند الصرفيّة).
  final String title;

  /// «تفعيل نقدي · FTTH 50 ميغا · علي حسن».
  final String detail;
  final num amount;

  /// «18:05».
  final String time;
  final RpCompany? company;
  final bool negative;
}

class RpDay {
  const RpDay({required this.date, required this.count, required this.sum, required this.rows});

  /// «2026/11/22».
  final String date;
  final int count;
  final num sum;
  final List<RpRow> rows;
}

// ═══════════════════════════════ الأساس ═══════════════════════════════

/// بطاقة التقرير: سطحٌ بحدٍّ وظلٍّ هادئ (ذوق المالك ٢٤ أكتوبر: «كارتات بألوان وحدود وتأثيرات»).
class RpCard extends StatelessWidget {
  const RpCard({super.key, required this.child, this.padding = const EdgeInsets.all(Sp.lg), this.tint});

  final Widget child;
  final EdgeInsets padding;

  /// حدٌّ ملوّن خفيف (اختيار الشركة، البطاقة الأهمّ).
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.lg),
        border: Border.all(color: tint?.withValues(alpha: 0.35) ?? AppColors.border),
        boxShadow: AppColors.isDark ? Sh.deskRestDark : Sh.deskRest,
      ),
      child: child,
    );
  }
}

/// مربّع الأيقونة الملوّن.
class RpIconBox extends StatelessWidget {
  const RpIconBox({super.key, required this.icon, required this.tone, this.size = 30});
  final IconData icon;
  final RpTone tone;
  final double size;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: tone.soft, borderRadius: BorderRadius.circular(R.sm)),
      child: Icon(icon, size: size * 0.5, color: tone.fg),
    );
  }
}

/// عنوان جزءٍ في البطاقة: أيقونة + اسم + ما بطرفه.
class RpTitle extends StatelessWidget {
  const RpTitle({super.key, required this.icon, required this.title, this.tone = RpTone.brand, this.trailing});
  final IconData icon;
  final String title;
  final RpTone tone;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Row(
      children: [
        RpIconBox(icon: icon, tone: tone, size: 28),
        const SizedBox(width: Sp.sm),
        Expanded(
          child: Text(title, style: AppType.cardTitleBold(color: AppColors.textHi), maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
        if (trailing != null) ...[const SizedBox(width: Sp.sm), trailing!],
      ],
    );
  }
}

/// مبلغٌ لا يُقصّ: يصغر بدل «…» (قاعدة المالك ١٤ نوفمبر).
class RpFitText extends StatelessWidget {
  const RpFitText(this.text, {super.key, required this.style, this.alignment = AlignmentDirectional.centerStart});
  final String text;
  final TextStyle style;
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) => FittedBox(
        fit: BoxFit.scaleDown,
        alignment: alignment,
        child: Text(text, style: style, maxLines: 1),
      );
}

// ═══════════════════════════════ الفترة والنطاق ═══════════════════════════════

/// الفترة (لمسة ⇒ تسع فتراتٍ جاهزة + مخصّص) ومفتاح المقارنة بالفترة السابقة.
class RpPeriodBar extends StatelessWidget {
  const RpPeriodBar({super.key, required this.period, required this.compareOn, required this.compareWith});
  final RpPeriod period;
  final bool compareOn;

  /// «بالشهر الماضي».
  final String compareWith;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _Pill(
              selected: false,
              child: Row(
                children: [
                  Icon(LucideIcons.calendarDays, size: 18, color: AppColors.brand),
                  const SizedBox(width: Sp.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(period.name, style: AppType.bodyBold(color: AppColors.textHi), maxLines: 1),
                        Directionality(
                          textDirection: TextDirection.ltr,
                          child: RpFitText(period.range,
                              style: AppType.micro(color: AppColors.textMid), alignment: AlignmentDirectional.centerEnd),
                        ),
                      ],
                    ),
                  ),
                  Icon(LucideIcons.chevronDown, size: 16, color: AppColors.textLow),
                ],
              ),
            ),
          ),
          const SizedBox(width: Sp.sm),
          _Pill(
            selected: compareOn,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(compareOn ? LucideIcons.squareCheck : LucideIcons.square,
                    size: 16, color: compareOn ? AppColors.brand : AppColors.textLow),
                const SizedBox(width: Sp.x6),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('قارن', style: AppType.bodyBold(color: compareOn ? AppColors.brand : AppColors.textHi), maxLines: 1),
                    Text(compareWith, style: AppType.micro(color: AppColors.textMid), maxLines: 1),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.child, required this.selected});
  final Widget child;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: Sp.sm),
      decoration: BoxDecoration(
        color: selected ? AppColors.brandSoftBg : AppColors.surface,
        borderRadius: BorderRadius.circular(R.icon),
        border: Border.all(
          color: selected ? AppColors.brand : AppColors.border,
          width: selected ? BW.selected : BW.normal,
        ),
      ),
      child: child,
    );
  }
}

/// «كل الشركات»: الشركات المختارة (أكثر من واحدة) — كلّ شركةٍ بلونها، و«الكل» أوّلاً.
class RpCompanyChips extends StatelessWidget {
  const RpCompanyChips({super.key, required this.companies, this.allSelected = false});
  final List<RpCompany> companies;
  final bool allSelected;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final picked = companies.where((c) => c.selected).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('الشركات · $picked من ${companies.length}', style: AppType.label(color: AppColors.textMid)),
        const SizedBox(height: Sp.x6),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _chip(label: 'الكل', color: AppColors.brand, selected: allSelected, dot: false),
              for (final c in companies) ...[
                const SizedBox(width: Sp.sm),
                _chip(label: c.name, color: c.color, selected: c.selected, dot: true),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _chip({required String label, required Color color, required bool selected, required bool dot}) {
    return Container(
      height: H.chip,
      padding: const EdgeInsets.symmetric(horizontal: Sp.md),
      decoration: BoxDecoration(
        color: selected ? color.withValues(alpha: 0.12) : AppColors.surface,
        borderRadius: BorderRadius.circular(R.pill),
        border: Border.all(color: selected ? color : AppColors.border, width: selected ? BW.selected : BW.normal),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (selected)
            Icon(LucideIcons.check, size: 14, color: color)
          else if (dot)
            Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          if (selected || dot) const SizedBox(width: Sp.x6),
          Text(label, style: AppType.pillBold(color: selected ? AppColors.textHi : AppColors.textMid), maxLines: 1),
        ],
      ),
    );
  }
}

/// الفلاتر الفعّالة رقائق تُحذف بلمسة، و«الفلاتر» يفتح الورقة الكاملة.
class RpFilterBar extends StatelessWidget {
  const RpFilterBar({super.key, required this.chips});
  final List<String> chips;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          Container(
            height: H.chip,
            padding: const EdgeInsets.symmetric(horizontal: Sp.md),
            decoration: BoxDecoration(
              color: AppColors.brand,
              borderRadius: BorderRadius.circular(R.pill),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(LucideIcons.slidersHorizontal, size: 15, color: AppColors.onBrand),
                const SizedBox(width: Sp.x6),
                Text('الفلاتر', style: AppType.pillBold(color: AppColors.onBrand)),
                if (chips.isNotEmpty) ...[
                  const SizedBox(width: Sp.x6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: Sp.x6),
                    decoration: BoxDecoration(color: AppColors.onBrandFill2, borderRadius: BorderRadius.circular(R.pill)),
                    child: Text('${chips.length}', style: AppType.microBold(color: AppColors.onBrand)),
                  ),
                ],
              ],
            ),
          ),
          for (final c in chips) ...[
            const SizedBox(width: Sp.sm),
            Container(
              height: H.chip,
              padding: const EdgeInsetsDirectional.only(start: Sp.md, end: Sp.sm),
              decoration: BoxDecoration(
                color: AppColors.brandSoftBg,
                borderRadius: BorderRadius.circular(R.pill),
                border: Border.all(color: AppColors.brandSoftBorder),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(c, style: AppType.pillLabel(color: AppColors.brandOnSoft), maxLines: 1),
                  const SizedBox(width: Sp.x6),
                  Icon(LucideIcons.x, size: 14, color: AppColors.brandOnSoft),
                ],
              ),
            ),
          ],
          if (chips.isNotEmpty) ...[
            const SizedBox(width: Sp.md),
            Text('مسح الكلّ', style: AppType.pillBold(color: AppColors.error)),
          ],
        ],
      ),
    );
  }
}

// ═══════════════════════════════ «حسب الشركة» ═══════════════════════════════

/// سطرٌ لكلّ شركة بأرقامها (تصل شركةً شركة)، والتي تعذّرت تُسمّى وتُستثنى من المجموع ومعها «أعد».
class RpCompanyTable extends StatelessWidget {
  const RpCompanyTable({super.key, required this.lines, required this.heads, required this.total, this.outside});
  final List<RpCompanyLine> lines;

  /// عناوين الأعمدة الثلاثة («الواصل» · «الدين» · «الربح»).
  final List<String> heads;
  final List<num> total;

  /// «خارج المجموع: …».
  final String? outside;

  static const _tones = [RpTone.money, RpTone.debt, RpTone.brand];

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return RpCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          RpTitle(
            icon: LucideIcons.building2,
            title: 'حسب الشركة',
            trailing: Text('لمسة على شركة تحصر التقرير عليها', style: AppType.micro(color: AppColors.textLow), maxLines: 1),
          ),
          const SizedBox(height: Sp.md),
          _row(
            name: const SizedBox.shrink(),
            cells: [for (final h in heads) Text(h, style: AppType.microBold(color: AppColors.textLow), maxLines: 1)],
          ),
          const SizedBox(height: Sp.xs),
          for (final l in lines) ...[
            Divider(height: Sp.md, color: AppColors.divider),
            _line(l),
          ],
          Divider(height: Sp.lg, color: AppColors.dividerStrong),
          _row(
            name: Text('المجموع', style: AppType.bodyBold(color: AppColors.textHi), maxLines: 1),
            cells: [
              for (var i = 0; i < total.length; i++)
                RpFitText(formatIQD(total[i]), style: AppType.rowValue(color: _tones[i].fg), alignment: AlignmentDirectional.centerEnd),
            ],
          ),
          if (outside != null) ...[
            const SizedBox(height: Sp.sm),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: Sp.sm),
              decoration: BoxDecoration(
                color: AppColors.warningSoftBg,
                borderRadius: BorderRadius.circular(R.md),
                border: Border.all(color: AppColors.warningSoftBorder),
              ),
              child: Row(
                children: [
                  Icon(LucideIcons.info, size: 14, color: AppColors.warningOnSoft),
                  const SizedBox(width: Sp.x6),
                  Expanded(child: Text(outside!, style: AppType.micro(color: AppColors.warningOnSoft), maxLines: 2)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _row({required Widget name, required List<Widget> cells}) => Row(
        children: [
          Expanded(flex: 5, child: name),
          for (final c in cells) ...[
            const SizedBox(width: Sp.sm),
            Expanded(flex: 4, child: Align(alignment: AlignmentDirectional.centerEnd, child: c)),
          ],
        ],
      );

  Widget _line(RpCompanyLine l) {
    final name = Row(
      children: [
        Container(width: 4, height: 30, decoration: BoxDecoration(color: l.company.color, borderRadius: BorderRadius.circular(R.pill))),
        const SizedBox(width: Sp.sm),
        Expanded(child: Text(l.company.name, style: AppType.bodyBold(color: AppColors.textHi), maxLines: 1, overflow: TextOverflow.ellipsis)),
      ],
    );
    switch (l.state) {
      case RpCompanyState.ok:
        return _row(name: name, cells: [
          for (var i = 0; i < 3; i++)
            RpFitText(formatIQD([l.a, l.b, l.c][i] ?? 0), style: AppType.bodyStrong(color: _tones[i].fg), alignment: AlignmentDirectional.centerEnd),
        ]);
      case RpCompanyState.loading:
        return Row(
          children: [
            Expanded(flex: 5, child: name),
            const SizedBox(width: Sp.sm),
            Expanded(
              flex: 12,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.brand)),
                  const SizedBox(width: Sp.sm),
                  Text('جارٍ قراءة أرقامها…', style: AppType.muted(color: AppColors.textMid), maxLines: 1),
                ],
              ),
            ),
          ],
        );
      case RpCompanyState.failed:
        return Row(
          children: [
            Expanded(flex: 5, child: name),
            const SizedBox(width: Sp.sm),
            Expanded(
              flex: 12,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Icon(LucideIcons.circleAlert, size: 14, color: AppColors.error),
                  const SizedBox(width: Sp.xs),
                  Flexible(child: Text('تعذّرت القراءة', style: AppType.muted(color: AppColors.dangerOnSoft), maxLines: 1)),
                  const SizedBox(width: Sp.sm),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: Sp.xs),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(R.pill),
                      border: Border.all(color: AppColors.dangerSoftBorder),
                      color: AppColors.dangerSoftBg,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(LucideIcons.rotateCw, size: 12, color: AppColors.dangerOnSoft),
                        const SizedBox(width: Sp.xs),
                        Text('أعد', style: AppType.microBold(color: AppColors.dangerOnSoft)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
    }
  }
}

// ═══════════════════════════════ الأرقام ═══════════════════════════════

/// الفرق عن الفترة السابقة: سهمٌ ونسبة بلون الحكم (الدين الصاعد أحمر).
class RpDelta extends StatelessWidget {
  const RpDelta({super.key, required this.kpi, required this.compareWith});
  final RpKpi kpi;
  final String compareWith;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final d = kpi.delta;
    if (d == null) return const SizedBox.shrink();
    final up = d > 0;
    final pct = (d.abs() * 100).round();
    final flat = pct == 0;
    final good = flat ? null : (up == kpi.upIsGood);
    final color = good == null ? AppColors.textMid : (good ? AppColors.success : AppColors.error);
    // السهم أيقونة لا رمز (▲ يظهر مربّعاً بخطّ التطبيق)، والنسبة معزولةً يساراً-يميناً كي لا تقفز «%».
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: AlignmentDirectional.centerStart,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(flat ? LucideIcons.equal : (up ? LucideIcons.arrowUp : LucideIcons.arrowDown), size: 13, color: color),
          const SizedBox(width: Sp.xxs),
          Directionality(textDirection: TextDirection.ltr, child: Text('$pct%', style: AppType.microBold(color: color))),
          const SizedBox(width: Sp.xs),
          Text(compareWith, style: AppType.micro(color: AppColors.textMid)),
        ],
      ),
    );
  }
}

/// الرقم الأهمّ بعرض الصفّ (صافي الربح) — ومعه خطّ الفترة الصغير.
class RpHeroKpi extends StatelessWidget {
  const RpHeroKpi({super.key, required this.kpi, required this.compareWith, required this.spark, this.note});
  final RpKpi kpi;
  final String compareWith;
  final List<num> spark;

  /// سطر الحساب («الواصل − الصرفيّات − كلفة الباقات»).
  final String? note;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return RpCard(
      tint: kpi.tone.fg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              RpIconBox(icon: kpi.icon, tone: kpi.tone, size: 36),
              const SizedBox(width: Sp.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(kpi.label, style: AppType.label(color: AppColors.textMid), maxLines: 1),
                    RpFitText(kpi.text, style: AppType.amount(color: kpi.tone.fg)),
                  ],
                ),
              ),
              Icon(LucideIcons.chevronLeft, size: 18, color: AppColors.textLow),
            ],
          ),
          const SizedBox(height: Sp.sm),
          RpDelta(kpi: kpi, compareWith: compareWith),
          if (spark.length > 1) ...[
            const SizedBox(height: Sp.sm),
            SizedBox(height: 40, child: _Spark(values: spark, color: kpi.tone.fg)),
          ],
          if (note != null) ...[
            const SizedBox(height: Sp.xs),
            Text(note!, style: AppType.micro(color: AppColors.textLow), maxLines: 2),
          ],
        ],
      ),
    );
  }
}

class _Spark extends StatelessWidget {
  const _Spark({required this.values, required this.color});
  final List<num> values;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return LineChart(
      LineChartData(
        minY: 0,
        lineTouchData: const LineTouchData(enabled: false),
        gridData: const FlGridData(show: false),
        titlesData: const FlTitlesData(show: false),
        borderData: FlBorderData(show: false),
        lineBarsData: [
          LineChartBarData(
            spots: [for (var i = 0; i < values.length; i++) FlSpot(i.toDouble(), values[i].toDouble())],
            isCurved: true,
            curveSmoothness: 0.25,
            preventCurveOverShooting: true,
            color: color,
            barWidth: 2.2,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [color.withValues(alpha: 0.22), color.withValues(alpha: 0.0)],
              ),
            ),
          ),
        ],
      ),
      duration: Duration.zero,
    );
  }
}

/// بطاقة رقم: لونٌ يعرّفه، والفرق عن الفترة السابقة، و«›» = لمسة تفتح حركاته.
class RpKpiCard extends StatelessWidget {
  const RpKpiCard({super.key, required this.kpi, required this.compareWith});
  final RpKpi kpi;
  final String compareWith;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return RpCard(
      padding: const EdgeInsets.all(Sp.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              RpIconBox(icon: kpi.icon, tone: kpi.tone),
              const SizedBox(width: Sp.sm),
              Expanded(child: Text(kpi.label, style: AppType.label(color: AppColors.textMid), maxLines: 2)),
              Icon(LucideIcons.chevronLeft, size: 16, color: AppColors.textLow),
            ],
          ),
          const SizedBox(height: Sp.sm),
          RpFitText(kpi.text, style: AppType.statValue(color: kpi.tone.fg)),
          const SizedBox(height: Sp.xxs),
          RpDelta(kpi: kpi, compareWith: compareWith),
        ],
      ),
    );
  }
}

/// البطاقات بعمودين وارتفاعٍ واحد لكلّ صفّ.
class RpKpiGrid extends StatelessWidget {
  const RpKpiGrid({super.key, required this.kpis, required this.compareWith});
  final List<RpKpi> kpis;
  final String compareWith;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < kpis.length; i += 2) {
      if (rows.isNotEmpty) rows.add(const SizedBox(height: Sp.sm));
      rows.add(IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: RpKpiCard(kpi: kpis[i], compareWith: compareWith)),
            const SizedBox(width: Sp.sm),
            Expanded(child: i + 1 < kpis.length ? RpKpiCard(kpi: kpis[i + 1], compareWith: compareWith) : const SizedBox.shrink()),
          ],
        ),
      ));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows);
  }
}

/// أعدادٌ صغيرة بصفٍّ واحد (تفعيل · تمديد · صرفيّة).
class RpCountsRow extends StatelessWidget {
  const RpCountsRow({super.key, required this.items});
  final List<RpKpi> items;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Row(
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const SizedBox(width: Sp.sm),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: Sp.sm, vertical: Sp.sm),
              decoration: BoxDecoration(
                color: items[i].tone.soft,
                borderRadius: BorderRadius.circular(R.md),
              ),
              child: Row(
                children: [
                  Icon(items[i].icon, size: 16, color: items[i].tone.fg),
                  const SizedBox(width: Sp.x6),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        RpFitText(formatIQD(items[i].value), style: AppType.rowValue(color: AppColors.textHi)),
                        Text(items[i].label, style: AppType.micro(color: AppColors.textMid), maxLines: 1, overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

// ═══════════════════════════════ يوماً بيوم ═══════════════════════════════

class RpTrendCard extends StatelessWidget {
  const RpTrendCard({
    super.key,
    required this.points,
    required this.aLabel,
    required this.bLabel,
    this.title = 'يوماً بيوم',
    this.aTone = RpTone.money,
    this.bTone = RpTone.debt,
  });

  final List<RpTrendPoint> points;
  final String title;
  final String aLabel;
  final String bLabel;
  final RpTone aTone;
  final RpTone bTone;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final maxY = points.fold<num>(0, (m, p) => [m, p.a, p.b].reduce((x, y) => x > y ? x : y)).toDouble();
    final top = _niceTop(maxY * 1.08);
    LineChartBarData line(List<FlSpot> spots, Color c, {bool area = false}) => LineChartBarData(
          spots: spots,
          isCurved: true,
          curveSmoothness: 0.2,
          preventCurveOverShooting: true,
          color: c,
          barWidth: 2.4,
          dotData: const FlDotData(show: false),
          belowBarData: BarAreaData(
            show: area,
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [c.withValues(alpha: 0.20), c.withValues(alpha: 0.0)],
            ),
          ),
        );
    return RpCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          RpTitle(
            icon: LucideIcons.chartSpline,
            title: title,
            tone: RpTone.info,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [_legend(aLabel, aTone.fg), const SizedBox(width: Sp.md), _legend(bLabel, bTone.fg)],
            ),
          ),
          const SizedBox(height: Sp.md),
          SizedBox(
            height: 170,
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: LineChart(
                LineChartData(
                  minY: 0,
                  maxY: top,
                  lineTouchData: const LineTouchData(enabled: false),
                  borderData: FlBorderData(show: false),
                  gridData: FlGridData(
                    drawVerticalLine: false,
                    horizontalInterval: top / 4,
                    getDrawingHorizontalLine: (_) => FlLine(color: AppColors.divider, strokeWidth: 1, dashArray: const [4, 4]),
                  ),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 54,
                        interval: top / 2,
                        getTitlesWidget: (v, meta) => Padding(
                          padding: const EdgeInsets.only(right: Sp.x6),
                          child: Text(v == 0 ? '0' : rpCompact(v), style: AppType.micro(color: AppColors.textLow), textAlign: TextAlign.right),
                        ),
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 22,
                        interval: 1,
                        getTitlesWidget: (v, meta) {
                          final d = v.round();
                          if (d != 1 && d % 5 != 0) return const SizedBox.shrink();
                          return Padding(
                            padding: const EdgeInsets.only(top: Sp.xs),
                            child: Text('$d', style: AppType.micro(color: AppColors.textLow)),
                          );
                        },
                      ),
                    ),
                  ),
                  lineBarsData: [
                    line([for (final p in points) FlSpot(p.day.toDouble(), p.a.toDouble())], aTone.fg, area: true),
                    line([for (final p in points) FlSpot(p.day.toDouble(), p.b.toDouble())], bTone.fg),
                  ],
                ),
                duration: Duration.zero,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static double _niceTop(double v) {
    if (v <= 0) return 1;
    const steps = [1.0, 2.0, 2.5, 4.0, 5.0, 10.0];
    var mag = 1.0;
    while (mag * 10 <= v) {
      mag *= 10;
    }
    for (final s in steps) {
      if (s * mag >= v) return s * mag;
    }
    return 10 * mag;
  }

  Widget _legend(String label, Color c) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 10, height: 3, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(R.pill))),
          const SizedBox(width: Sp.xs),
          Text(label, style: AppType.micro(color: AppColors.textMid)),
        ],
      );
}

// ═══════════════════════════════ «قسّم حسب» ═══════════════════════════════

class RpBreakdownCard extends StatelessWidget {
  const RpBreakdownCard({super.key, required this.tabs, required this.selected, required this.shares, this.tone = RpTone.money});
  final List<String> tabs;
  final int selected;
  final List<RpShare> shares;
  final RpTone tone;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return RpCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const RpTitle(icon: LucideIcons.chartPie, title: 'قسّم حسب', tone: RpTone.brand),
          const SizedBox(height: Sp.md),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (var i = 0; i < tabs.length; i++) ...[
                  if (i > 0) const SizedBox(width: Sp.x6),
                  Container(
                    height: H.chipSm,
                    padding: const EdgeInsets.symmetric(horizontal: Sp.md),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: i == selected ? AppColors.brand : AppColors.surfaceSunken,
                      borderRadius: BorderRadius.circular(R.pill),
                    ),
                    child: Text(tabs[i],
                        style: AppType.pillBold(color: i == selected ? AppColors.onBrand : AppColors.textMid), maxLines: 1),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: Sp.md),
          for (var i = 0; i < shares.length; i++) ...[
            if (i > 0) const SizedBox(height: Sp.md),
            _share(shares[i]),
          ],
        ],
      ),
    );
  }

  Widget _share(RpShare s) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(s.name, style: AppType.bodyBold(color: AppColors.textHi), maxLines: 1, overflow: TextOverflow.ellipsis),
                  if (s.company != null || s.sub != null)
                    Row(
                      children: [
                        if (s.company != null) ...[
                          Container(width: 7, height: 7, decoration: BoxDecoration(color: s.company!.color, shape: BoxShape.circle)),
                          const SizedBox(width: Sp.xs),
                        ],
                        Flexible(
                          child: Text([s.company?.name, s.sub].whereType<String>().join(' · '),
                              style: AppType.micro(color: AppColors.textMid), maxLines: 1, overflow: TextOverflow.ellipsis),
                        ),
                      ],
                    ),
                ],
              ),
            ),
            const SizedBox(width: Sp.sm),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(rpMoney(s.amount), style: AppType.bodyStrong(color: tone.fg), maxLines: 1),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('${s.count} حركة · ', style: AppType.micro(color: AppColors.textLow), maxLines: 1),
                    Directionality(
                      textDirection: TextDirection.ltr,
                      child: Text('${(s.share * 100).round()}%', style: AppType.microBold(color: AppColors.textMid)),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: Sp.x6),
        ClipRRect(
          borderRadius: BorderRadius.circular(R.pill),
          child: LinearProgressIndicator(
            value: s.share,
            minHeight: 6,
            color: s.company?.color ?? tone.fg,
            backgroundColor: AppColors.surfaceSunken,
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════ الحركات ═══════════════════════════════

class RpRowsCard extends StatelessWidget {
  const RpRowsCard({super.key, required this.total, required this.days, this.more});
  final int total;
  final List<RpDay> days;

  /// «عرض المزيد (٤٨)».
  final String? more;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return RpCard(
      padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.lg, Sp.lg, Sp.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          RpTitle(
            icon: LucideIcons.listOrdered,
            title: 'الحركات',
            tone: RpTone.neutral,
            trailing: Text('${formatIQD(total)} حركة', style: AppType.pillBold(color: AppColors.textMid)),
          ),
          const SizedBox(height: Sp.md),
          Container(
            height: H.search,
            padding: const EdgeInsets.symmetric(horizontal: Sp.md),
            decoration: BoxDecoration(
              color: AppColors.surfaceInput,
              borderRadius: BorderRadius.circular(R.icon),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                Icon(LucideIcons.search, size: 17, color: AppColors.textLow),
                const SizedBox(width: Sp.sm),
                Expanded(
                  child: Text('ابحث باسم المشترك أو يوزره أو رقمه',
                      style: AppType.body(color: AppColors.textPlaceholder), maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
          ),
          for (final d in days) ...[
            const SizedBox(height: Sp.md),
            _dayHead(d),
            for (final r in d.rows) _row(r),
          ],
          if (more != null) ...[
            const SizedBox(height: Sp.sm),
            Center(child: Text(more!, style: AppType.bodyBold(color: AppColors.brand))),
          ],
        ],
      ),
    );
  }

  Widget _dayHead(RpDay d) => Container(
        padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: Sp.x6),
        decoration: BoxDecoration(color: AppColors.surfaceSunken, borderRadius: BorderRadius.circular(R.sm)),
        child: Row(
          children: [
            Icon(LucideIcons.calendar, size: 14, color: AppColors.textMid),
            const SizedBox(width: Sp.x6),
            Directionality(textDirection: TextDirection.ltr, child: Text(d.date, style: AppType.bodyBold(color: AppColors.textHi))),
            const SizedBox(width: Sp.sm),
            Expanded(child: Text('${d.count} حركة', style: AppType.micro(color: AppColors.textMid), maxLines: 1)),
            Text(rpMoney(d.sum), style: AppType.bodyStrong(color: AppColors.textHi), maxLines: 1),
          ],
        ),
      );

  Widget _row(RpRow r) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Sp.sm),
      child: Row(
        children: [
          RpIconBox(icon: r.icon, tone: r.tone, size: 36),
          const SizedBox(width: Sp.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(r.title, style: AppType.bodyBold(color: AppColors.textHi), maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(r.detail, style: AppType.micro(color: AppColors.textMid), maxLines: 1, overflow: TextOverflow.ellipsis),
                if (r.company != null)
                  Row(
                    children: [
                      Container(width: 7, height: 7, decoration: BoxDecoration(color: r.company!.color, shape: BoxShape.circle)),
                      const SizedBox(width: Sp.xs),
                      Flexible(
                        child: Text(r.company!.name,
                            style: AppType.microBold(color: AppColors.textMid), maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          const SizedBox(width: Sp.sm),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Directionality(
                textDirection: TextDirection.ltr,
                child: Text('${r.negative ? '−' : ''}${formatIQD(r.amount)}', style: AppType.bodyStrong(color: r.tone.fg), maxLines: 1),
              ),
              Directionality(
                textDirection: TextDirection.ltr,
                child: Text(r.time, style: AppType.micro(color: AppColors.textLow)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════ التصدير ═══════════════════════════════

/// ملفٌّ بالفلاتر نفسها: PDF باسم الشركة، Excel، أو يُرسل بالواتساب.
class RpExportBar extends StatelessWidget {
  const RpExportBar({super.key});

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    Widget b(IconData icon, String label, Color color) => Expanded(
          child: Container(
            height: H.segment,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(R.icon),
              border: Border.all(color: color.withValues(alpha: 0.35)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 17, color: color),
                const SizedBox(width: Sp.x6),
                Flexible(child: Text(label, style: AppType.bodyBold(color: AppColors.textHi), maxLines: 1)),
              ],
            ),
          ),
        );
    return Row(
      children: [
        b(LucideIcons.fileText, 'PDF', AppColors.error),
        const SizedBox(width: Sp.sm),
        b(LucideIcons.sheet, 'Excel', AppColors.success),
        const SizedBox(width: Sp.sm),
        b(LucideIcons.messageCircle, 'واتساب', AppColors.channelWhatsApp),
      ],
    );
  }
}
