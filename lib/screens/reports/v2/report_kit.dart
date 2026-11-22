import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/util/bidi.dart';
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

/// الرقم بإشارته: [formatIQD] يأخذ القيمة المطلقة فيضيع «−» صافي ربحٍ بالخسارة (٢٢ نوفمبر). السالب معزولٌ ([iso]) فلا يقفز «−»
/// يمين الرقم في السطر العربيّ.
String rpNum(num v) => v < 0 ? iso('−${formatIQD(v)}') : formatIQD(v);

/// المبلغ بالدينار كما يُكتب في التطبيق: «12,450,000 د.ع» — وبإشارته إن كان سالباً.
String rpMoney(num v) => '${rpNum(v)} د.ع';

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
  const RpCompany({required this.name, required this.colorIndex, this.selected = false, this.note, this.key = ''});

  /// مفتاح الشركة في «كل الشركات» (`c…`) — فارغٌ في صور التصميم.
  final String key;
  final String name;
  final int colorIndex;
  final bool selected;

  /// سطرٌ صغير تحت الاسم في الشريط («جارٍ…» · «تعذّرت»).
  final String? note;

  Color get color => AppColors.company(colorIndex);
}

class RpKpi {
  const RpKpi({
    this.id = '',
    required this.label,
    required this.value,
    required this.icon,
    required this.tone,
    this.delta,
    this.upIsGood = true,
    this.isCount = false,
    this.unit,
    this.display,
    this.hint,
    this.hints = const [],
  });

  /// سطرٌ صغير تحت الرقم («الفعّالون 120» · «لا يشمل: …») — كاملاً بلا قصّ.
  final String? hint;

  /// سطورٌ تحت الرقم بعد خطٍّ فاصل، كلٌّ بسطره (تقارير الأرصدة: «نقد التفعيلات …» · «تسديد ديونها …») — كاملةً بلا قصّ.
  final List<String> hints;

  /// نصّ الرقم حين ليس مالاً ولا عدّاً («1.2 GB» في الجلسات) — يغلب [isCount] و[rpMoney].
  final String? display;

  /// اسم البطاقة الثابت (حركاتها عند اللمس) — فارغٌ في صور التصميم.
  final String id;
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

  String get text => display ?? (isCount ? '${formatIQD(value)}${unit == null ? '' : ' $unit'}' : rpMoney(value));
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
    this.cost,
    this.balanceAfter,
    this.trailing,
  });

  /// نصّ مكان المبلغ حين ليس مالاً («↓1.2 GB · ↑300 MB» في الجلسات) — يُعرض حين [amount] null.
  final String? trailing;

  final IconData icon;
  final RpTone tone;

  /// الدين المتبقّي بعد الحركة — موقَّعاً (سالبٌ = دَينٌ عليه)؛ null ⇒ لا سطر (حركةٌ لا تمسّ الرصيد، لا «0»). طلب المالك ٤ سبتمبر:
  /// «مفروض يظهر المتبقّي للدين أو رصيد في جميع التقارير» — كان في ReportLogTile وسقط من الشكل الموحّد أوّل مرّة.
  final num? balanceAfter;

  /// سطر كلفة الباقة تحت الحركة (للمالك) — null بلا كلفة.
  final String? cost;

  /// اسم المشترك (أو بند الصرفيّة).
  final String title;

  /// «تفعيل نقدي · FTTH 50 ميغا · علي حسن».
  final String detail;

  /// null = حركةٌ بلا مال (تمديد، تفعيلٌ من الساس) ⇒ لا رقم — لا «0».
  final num? amount;

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

  /// «واصل» اليوم — null = سطورٌ بلا مال (التجريبيّ) ⇒ لا «واصل 0».
  final num? sum;
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
/// فتحٌ وطيّ القسم الفرعيّ (المالك ٢٢ نوفمبر: «الأقسام الفرعيّة خلّيها مقفولة — المهمّات تظهر والفرعيّة هو ينقر عليها ويظهرها»).
class RpFold {
  const RpFold({required this.open, required this.onToggle});
  final bool open;
  final VoidCallback onToggle;
}

class RpTitle extends StatelessWidget {
  const RpTitle({super.key, required this.icon, required this.title, this.tone = RpTone.brand, this.trailing, this.fold});
  final IconData icon;
  final String title;
  final RpTone tone;
  final Widget? trailing;

  /// قسمٌ يُطوى: العنوان كلّه لمسة، وسهمٌ يدور.
  final RpFold? fold;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final row = Row(
      children: [
        RpIconBox(icon: icon, tone: tone, size: 28),
        const SizedBox(width: Sp.sm),
        Expanded(
          child: Text(title, style: AppType.cardTitleBold(color: AppColors.textHi), maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
        if (trailing != null) ...[const SizedBox(width: Sp.sm), trailing!],
        if (fold != null) ...[
          const SizedBox(width: Sp.xs),
          AnimatedRotation(
            turns: fold!.open ? 0.5 : 0,
            duration: const Duration(milliseconds: 180),
            child: Icon(LucideIcons.chevronDown, size: 18, color: AppColors.textMid),
          ),
        ],
      ],
    );
    if (fold == null) return row;
    return Semantics(button: true, expanded: fold!.open, child: _Tap(onTap: fold!.onToggle, radius: R.sm, child: row));
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
  const RpPeriodBar(
      {super.key, required this.period, required this.compareOn, required this.compareWith, this.onPeriod, this.onCompare});
  final RpPeriod period;
  final bool compareOn;

  /// «بالشهر الماضي».
  final String compareWith;
  final VoidCallback? onPeriod;
  final VoidCallback? onCompare;

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
              onTap: onPeriod,
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
          // بلا مقارنة لهذا التقرير (سجلّ الحركات، «اليوميّة» وحدها) ⇒ لا زرّ يبدو قابلاً للّمس ولا يفعل شيئاً
          if (onCompare != null || compareOn) ...[
            const SizedBox(width: Sp.sm),
            _Pill(
              selected: compareOn,
              onTap: onCompare,
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
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({super.key, required this.child, required this.selected, this.onTap, this.padding = const EdgeInsets.symmetric(horizontal: Sp.md, vertical: Sp.sm)});
  final Widget child;
  final bool selected;
  final VoidCallback? onTap;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Material(
      color: selected ? AppColors.brandSoftBg : AppColors.surface,
      borderRadius: BorderRadius.circular(R.icon),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(R.icon),
        child: Ink(
          padding: padding,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(R.icon),
            border: Border.all(
              color: selected ? AppColors.brand : AppColors.border,
              width: selected ? BW.selected : BW.normal,
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// زرٌّ بلا شكلٍ إضافيّ (لمسة على شريحة أو بطاقة) — بلا [onTap] لا يتفاعل.
class _Tap extends StatelessWidget {
  const _Tap({required this.child, this.onTap, this.radius = R.pill});
  final Widget child;
  final VoidCallback? onTap;
  final double radius;

  @override
  Widget build(BuildContext context) {
    if (onTap == null) return child;
    return Material(
      type: MaterialType.transparency,
      child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(radius), child: child),
    );
  }
}

/// «كل الشركات»: الشركات المختارة (أكثر من واحدة) — كلّ شركةٍ بلونها، و«الكل» أوّلاً.
class RpCompanyChips extends StatelessWidget {
  const RpCompanyChips({super.key, required this.companies, this.allSelected = false, this.onAll, this.onToggle});
  final List<RpCompany> companies;
  final bool allSelected;
  final VoidCallback? onAll;
  final ValueChanged<RpCompany>? onToggle;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    // «الكل» = كلّ الشركات داخلة ولو لم تُعلَّم واحدةً واحدة (كانت «0 من 2»)
    final picked = allSelected ? companies.length : companies.where((c) => c.selected).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('الشركات · $picked من ${companies.length}', style: AppType.label(color: AppColors.textMid)),
        const SizedBox(height: Sp.x6),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _Tap(onTap: onAll, child: _chip(label: 'الكل', color: AppColors.brand, selected: allSelected, dot: false)),
              for (final c in companies) ...[
                const SizedBox(width: Sp.sm),
                _Tap(
                  onTap: onToggle == null ? null : () => onToggle!(c),
                  child: _chip(
                      label: c.note == null ? c.name : '${c.name} · ${c.note}', color: c.color, selected: c.selected, dot: true),
                ),
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

/// فلترٌ فعّال: نصّه وما يزيله.
class RpChip {
  const RpChip(this.label, {this.onRemove});
  final String label;
  final VoidCallback? onRemove;
}

/// الفلاتر الفعّالة رقائق تُحذف بلمسة، و«الفلاتر» يفتح الورقة الكاملة.
class RpFilterBar extends StatelessWidget {
  const RpFilterBar({super.key, required this.chips, this.onOpen, this.onClear, this.showButton = true});
  final List<RpChip> chips;
  final VoidCallback? onOpen;
  final VoidCallback? onClear;

  /// false: الشارات الفعّالة وحدها (زرّ «الفلاتر» في سطر [RpHeader]).
  final bool showButton;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          if (showButton)
          _Tap(
            onTap: onOpen,
            child: Container(
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
          ),
          for (final c in chips) ...[
            if (showButton || c != chips.first) const SizedBox(width: Sp.sm),
            _Tap(
              onTap: c.onRemove,
              child: Container(
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
                    Text(c.label, style: AppType.pillLabel(color: AppColors.brandOnSoft), maxLines: 1),
                    const SizedBox(width: Sp.x6),
                    Icon(LucideIcons.x, size: 14, color: AppColors.brandOnSoft),
                  ],
                ),
              ),
            ),
          ],
          if (chips.isNotEmpty) ...[
            const SizedBox(width: Sp.md),
            _Tap(
              onTap: onClear,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: Sp.sm, horizontal: Sp.xs),
                child: Text('مسح الكلّ', style: AppType.pillBold(color: AppColors.error)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// رأس التقرير الموحّد بسطرٍ واحد (المالك ٢٢ نوفمبر على لقطة الماليّ: «الفلاتر والشهر وذني كلّهن يصيرون بسطر واحد حتى لا تاخذ هو من
/// مساحة التصميم، كلّ التقارير لازم» + «الأرشيف يصير فوق وصورة مختصرة»): [top] سطرٌ مختصر أعلاه (الأرشيف)، ثمّ الفترة و«قارن»
/// و«الفلاتر» صفّاً واحداً، والشارات الفعّالة تحته حين توجد وحدها. على الضيّق (< 380) «الفلاتر» أيقونةٌ وعددها فلا تأكل الفترة.
class RpHeader extends StatelessWidget {
  const RpHeader({
    super.key,
    required this.period,
    this.onPeriod,
    this.compareOn = false,
    this.onCompare,
    this.chips = const [],
    this.onFilters,
    this.onClear,
    this.top,
  });
  final RpPeriod period;
  final VoidCallback? onPeriod;
  final bool compareOn;

  /// null وبلا مقارنة ⇒ لا زرّ «قارن» (تقريرٌ بلا مقارنة).
  final VoidCallback? onCompare;
  final List<RpChip> chips;

  /// null ⇒ لا زرّ «الفلاتر» (الفترة وحدها — المصاريف).
  final VoidCallback? onFilters;
  final VoidCallback? onClear;

  /// سطرٌ مختصر فوق الصفّ (الأرشيف) — null ⇒ لا شيء.
  final Widget? top;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final compare = onCompare != null || compareOn;
    const pad = EdgeInsets.symmetric(horizontal: Sp.sm + 2, vertical: Sp.xs);
    return LayoutBuilder(
      builder: (context, box) {
        final narrow = box.maxWidth < 380;
        final row = SizedBox(
          height: 44,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _Pill(
                  key: const ValueKey('rp-head-period'),
                  selected: false,
                  onTap: onPeriod,
                  padding: pad,
                  child: Row(
                    children: [
                      Icon(LucideIcons.calendarDays, size: 16, color: AppColors.brand),
                      const SizedBox(width: Sp.x6),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            RpFitText(period.name, style: AppType.pillBold(color: AppColors.textHi)),
                            Directionality(
                              textDirection: TextDirection.ltr,
                              child: RpFitText(period.range,
                                  style: AppType.micro(color: AppColors.textMid), alignment: AlignmentDirectional.centerEnd),
                            ),
                          ],
                        ),
                      ),
                      Icon(LucideIcons.chevronDown, size: 14, color: AppColors.textLow),
                    ],
                  ),
                ),
              ),
              if (compare) ...[
                const SizedBox(width: Sp.x6),
                _Pill(
                  key: const ValueKey('rp-head-compare'),
                  selected: compareOn,
                  onTap: onCompare,
                  padding: pad,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(compareOn ? LucideIcons.squareCheck : LucideIcons.square,
                          size: 15, color: compareOn ? AppColors.brand : AppColors.textLow),
                      const SizedBox(width: Sp.xs),
                      Text('قارن', style: AppType.pillBold(color: compareOn ? AppColors.brand : AppColors.textHi), maxLines: 1),
                    ],
                  ),
                ),
              ],
              if (onFilters != null) ...[
                const SizedBox(width: Sp.x6),
                _Tap(
                  onTap: onFilters,
                  radius: R.icon,
                  child: Container(
                    key: const ValueKey('rp-head-filters'),
                    padding: const EdgeInsets.symmetric(horizontal: Sp.md),
                    decoration: BoxDecoration(color: AppColors.brand, borderRadius: BorderRadius.circular(R.icon)),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(LucideIcons.slidersHorizontal, size: 15, color: AppColors.onBrand),
                        if (!narrow) ...[
                          const SizedBox(width: Sp.x6),
                          Text('الفلاتر', style: AppType.pillBold(color: AppColors.onBrand)),
                        ],
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
                ),
              ],
            ],
          ),
        );
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (top != null) ...[top!, const SizedBox(height: Sp.sm)],
            row,
            if (chips.isNotEmpty) ...[
              const SizedBox(height: Sp.sm),
              RpFilterBar(chips: chips, onOpen: onFilters, onClear: onClear, showButton: false),
            ],
          ],
        );
      },
    );
  }
}

// ═══════════════════════════════ «حسب الشركة» ═══════════════════════════════

/// سطرٌ لكلّ شركة بأرقامها (تصل شركةً شركة)، والتي تعذّرت تُسمّى وتُستثنى من المجموع ومعها «أعد».
class RpCompanyTable extends StatelessWidget {
  const RpCompanyTable(
      {super.key,
      required this.lines,
      required this.heads,
      required this.total,
      this.outside,
      this.onTap,
      this.onRetry,
      this.tones = const [RpTone.money, RpTone.debt, RpTone.brand],
      this.fold});
  final List<RpCompanyLine> lines;
  final ValueChanged<RpCompany>? onTap;
  final ValueChanged<RpCompany>? onRetry;

  /// عناوين الأعمدة — ثلاثةٌ عادةً («الواصل» · «الدين» · «الربح»)، أو أقلّ ([total] بعددها).
  final List<String> heads;

  /// null = مجهول (مالٌ لم يصل من شركةٍ داخلة) ⇒ «—» لا رقمٌ ناقص.
  final List<num?> total;

  /// «خارج المجموع: …».
  final String? outside;

  /// ألوان الأعمدة الثلاثة (توزيع الباقات: عددٌ ثمّ إيرادٌ ثمّ ربح).
  final List<RpTone> tones;

  /// قسمٌ فرعيّ يُطوى (المالك ٢٢ نوفمبر) — null = لا يُطوى.
  final RpFold? fold;

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
            // سطران عند الضيق (320) — لا يزاحم العنوان حتى يُقصّ؛ ومطويّاً لا شركات تُلمس فلا تلميح
            trailing: (fold?.open ?? true)
                ? Flexible(
                    child: Text('لمسة على شركة تحصر التقرير عليها',
                        style: AppType.micro(color: AppColors.textLow), maxLines: 2, textAlign: TextAlign.end),
                  )
                : null,
            fold: fold,
          ),
          if (fold?.open ?? true) ...[
          const SizedBox(height: Sp.md),
          _row(
            name: const SizedBox.shrink(),
            cells: [for (final h in heads) Text(h, style: AppType.microBold(color: AppColors.textLow), maxLines: 1)],
          ),
          const SizedBox(height: Sp.xs),
          for (final l in lines) ...[
            Divider(height: Sp.md, color: AppColors.divider),
            _Tap(
              radius: R.sm,
              onTap: onTap == null || l.state != RpCompanyState.ok ? null : () => onTap!(l.company),
              child: _line(l),
            ),
          ],
          Divider(height: Sp.lg, color: AppColors.dividerStrong),
          _row(
            name: Text('المجموع', style: AppType.bodyBold(color: AppColors.textHi), maxLines: 1),
            cells: [
              for (var i = 0; i < total.length; i++)
                RpFitText(total[i] == null ? '—' : rpNum(total[i]!),
                    style: AppType.rowValue(color: tones[i].fg), alignment: AlignmentDirectional.centerEnd),
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
                  // كاملاً مهما طال — هنا سبب كلّ شركةٍ متعذّرة بنصّه (خانتها في الجدول «تعذّرت» وحدها)
                  Expanded(child: Text(outside!, style: AppType.micro(color: AppColors.warningOnSoft))),
                ],
              ),
            ),
          ],
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
        Container(
            width: 4, height: 30, decoration: BoxDecoration(color: l.company.color, borderRadius: BorderRadius.circular(R.pill))),
        const SizedBox(width: Sp.sm),
        Expanded(
            child: Text(l.company.name,
                style: AppType.bodyBold(color: AppColors.textHi), maxLines: 1, overflow: TextOverflow.ellipsis)),
      ],
    );
    switch (l.state) {
      case RpCompanyState.ok:
        // عمودٌ لكلّ عنوان (1–3): تقريرٌ برقمين (ايرث لنك: المشتركون والباقات) لا عمود «—» فارغاً له
        return _row(name: name, cells: [
          for (var i = 0; i < heads.length && i < 3; i++)
            RpFitText([l.a, l.b, l.c][i] == null ? '—' : rpNum([l.a, l.b, l.c][i]!),
                style: AppType.bodyStrong(color: tones[i].fg), alignment: AlignmentDirectional.centerEnd),
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
                  // «تعذّرت» وحدها — السبب بنصّه كاملاً في «خارج المجموع» تحت الجدول (لا «…» على 320)
                  Flexible(child: Text('تعذّرت', style: AppType.muted(color: AppColors.dangerOnSoft), maxLines: 1)),
                  const SizedBox(width: Sp.sm),
                  _Tap(
                    onTap: onRetry == null ? null : () => onRetry!(l.company),
                    child: Container(
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
  const RpHeroKpi(
      {super.key,
      required this.kpi,
      required this.compareWith,
      required this.spark,
      this.note,
      this.notes = const [],
      this.onTap});

  /// تنبيهاتٌ تحت الصيغة (كلفةٌ ناقصة، تقديريّة…).
  final List<String> notes;
  final VoidCallback? onTap;
  final RpKpi kpi;
  final String compareWith;
  final List<num> spark;

  /// سطر الحساب («الواصل − الصرفيّات − كلفة الباقات»).
  final String? note;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return _Tap(
      radius: R.lg,
      onTap: onTap,
      child: RpCard(
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
                // «›» = لمسةٌ تفتح حركاته — لا سهم لبطاقةٍ لا تُفتح
                if (onTap != null) Icon(LucideIcons.chevronLeft, size: 18, color: AppColors.textLow),
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
              Text(note!, style: AppType.micro(color: AppColors.textLow), maxLines: 3),
            ],
            for (final n in notes) ...[
              const SizedBox(height: Sp.xs),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(LucideIcons.info, size: 13, color: AppColors.warning),
                  const SizedBox(width: Sp.xs),
                  Expanded(child: Text(n, style: AppType.micro(color: AppColors.textMid), maxLines: 3)),
                ],
              ),
            ],
          ],
        ),
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
  const RpKpiCard({super.key, required this.kpi, required this.compareWith, this.onTap});
  final RpKpi kpi;
  final String compareWith;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return _Tap(
      radius: R.lg,
      onTap: onTap,
      child: RpCard(
        padding: const EdgeInsets.all(Sp.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                RpIconBox(icon: kpi.icon, tone: kpi.tone),
                const SizedBox(width: Sp.sm),
                Expanded(child: Text(kpi.label, style: AppType.label(color: AppColors.textMid), maxLines: 2)),
                if (onTap != null) Icon(LucideIcons.chevronLeft, size: 16, color: AppColors.textLow),
              ],
            ),
            const SizedBox(height: Sp.sm),
            RpFitText(kpi.text, style: AppType.statValue(color: kpi.tone.fg)),
            const SizedBox(height: Sp.xxs),
            RpDelta(kpi: kpi, compareWith: compareWith),
            if (kpi.hint != null) Text(kpi.hint!, style: AppType.micro(color: AppColors.textLow)),
            if (kpi.hints.isNotEmpty) ...[
              const SizedBox(height: Sp.x6),
              Divider(height: 1, thickness: 1, color: AppColors.divider),
              const SizedBox(height: Sp.x6),
              for (final h in kpi.hints) Text(h, style: AppType.micro(color: AppColors.textMid)),
            ],
          ],
        ),
      ),
    );
  }
}

/// البطاقات بعمودين وارتفاعٍ واحد لكلّ صفّ.
class RpKpiGrid extends StatelessWidget {
  const RpKpiGrid({super.key, required this.kpis, required this.compareWith, this.onTap, this.tappable, this.keyPrefix});
  final List<RpKpi> kpis;
  final String compareWith;
  final ValueChanged<RpKpi>? onTap;

  /// أيّ البطاقات تُفتح ([onTap]) — null = كلّها؛ غيرها بلا «›» ولا لمسة.
  final bool Function(RpKpi kpi)? tappable;

  /// مفتاح كلّ بطاقة `<keyPrefix><id>` (تقارير الأرصدة: «bal-stat-collected») — null = بلا مفاتيح.
  final String? keyPrefix;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    Widget card(RpKpi k) => RpKpiCard(
          key: keyPrefix == null ? null : ValueKey('$keyPrefix${k.id}'),
          kpi: k,
          compareWith: compareWith,
          onTap: onTap == null || !(tappable?.call(k) ?? true) ? null : () => onTap!(k),
        );
    for (var i = 0; i < kpis.length; i += 2) {
      if (rows.isNotEmpty) rows.add(const SizedBox(height: Sp.sm));
      // الأخيرة الوحيدة في صفّها تأخذ عرضه (المالك ٢٢ نوفمبر: «ليش هيج؟ الفراغ…») — لا نصفٌ فارغ بجانبها
      if (i + 1 >= kpis.length) {
        rows.add(card(kpis[i]));
        continue;
      }
      rows.add(IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: card(kpis[i])),
            const SizedBox(width: Sp.sm),
            Expanded(child: card(kpis[i + 1])),
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
                        RpFitText(items[i].display ?? formatIQD(items[i].value), style: AppType.rowValue(color: AppColors.textHi)),
                        Text(items[i].label,
                            style: AppType.micro(color: AppColors.textMid), maxLines: 1, overflow: TextOverflow.ellipsis),
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
    this.bLabel,
    this.title = 'يوماً بيوم',
    this.aTone = RpTone.money,
    this.bTone = RpTone.debt,
    this.monthly = false,
    this.fold});

  final List<RpTrendPoint> points;
  final String title;
  final String aLabel;

  /// الخطّ الثاني — `null` حين لا يعرفه الخادم: لا يُرسم صفراً كاذباً.
  final String? bLabel;
  final RpTone aTone;
  final RpTone bTone;

  /// نقطةٌ لكلّ شهر (رقمه تحت المحور) لا لكلّ يوم.
  final bool monthly;

  /// المحور بترتيب النقاط لا برقم اليوم: فترةٌ تعبر الشهر (25…31 ثمّ 1…22) كانت ترجع للخلف.
  bool _labelAt(int i) {
    if (i < 0 || i >= points.length) return false;
    if (monthly) {
      final step = (points.length / 6).ceil().clamp(1, 12);
      return i % step == 0;
    }
    final d = points[i].day;
    return i == 0 || d == 1 || d % 5 == 0;
  }

  /// قسمٌ فرعيّ يُطوى (المالك ٢٢ نوفمبر) — null = لا يُطوى.
  final RpFold? fold;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final withB = (bLabel ?? '').isNotEmpty;
    final maxY = points.fold<num>(0, (m, p) => [m, p.a, if (withB) p.b].reduce((x, y) => x > y ? x : y)).toDouble();
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
              children: [
                _legend(aLabel, aTone.fg),
                if (withB) ...[const SizedBox(width: Sp.md), _legend(bLabel!, bTone.fg)],
              ],
            ),
            fold: fold,
          ),
          if (fold?.open ?? true) ...[
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
                          child: Text(v == 0 ? '0' : rpCompact(v),
                              style: AppType.micro(color: AppColors.textLow), textAlign: TextAlign.right),
                        ),
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 22,
                        interval: 1,
                        getTitlesWidget: (v, meta) {
                          final i = v.round();
                          if (v != i || !_labelAt(i)) return const SizedBox.shrink();
                          return Padding(
                            padding: const EdgeInsets.only(top: Sp.xs),
                            child: Text('${points[i].day}', style: AppType.micro(color: AppColors.textLow)),
                          );
                        },
                      ),
                    ),
                  ),
                  lineBarsData: [
                    line([for (var i = 0; i < points.length; i++) FlSpot(i.toDouble(), points[i].a.toDouble())], aTone.fg,
                        area: true),
                    if (withB)
                      line([for (var i = 0; i < points.length; i++) FlSpot(i.toDouble(), points[i].b.toDouble())], bTone.fg),
                  ],
                ),
                duration: Duration.zero,
              ),
            ),
          ),
          ],
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
  const RpBreakdownCard({
    super.key,
    required this.tabs,
    required this.selected,
    required this.shares,
    this.tone = RpTone.money,
    this.onTab,
    this.note,
    this.more,
    this.onMore,
    this.unit = 'حركة',
    this.countOnly = false,
    this.title = 'قسّم حسب',
    this.icon = LucideIcons.chartPie,
    this.onShare,
    this.empty = 'لا حركات بهذه الفترة',
    this.fold});

  /// نصّ البطاقة بلا سطور («لا ديون أخرى متبقّية» لعمر الدين).
  final String empty;

  /// عنوان البطاقة — «الباقات» في توزيع الباقات.
  final String title;
  final IconData icon;

  /// لمسة سطرٍ تفتح تفاصيله (رقم السطر في [shares]) — null = لا لمس.
  final ValueChanged<int>? onShare;
  final List<String> tabs;
  final int selected;
  final List<RpShare> shares;
  final RpTone tone;
  final ValueChanged<int>? onTab;

  /// سطرٌ تحت التبويبات («من آخر 1000 حركة»).
  final String? note;

  /// «عرض الكلّ (12)».
  final String? more;
  final VoidCallback? onMore;

  /// وحدة العدّ تحت المبلغ.
  final String unit;

  /// العدد هو الرقم البارز لا المال (الجلسات) — المال لا يُعرض.
  final bool countOnly;

  /// قسمٌ فرعيّ يُطوى (المالك ٢٢ نوفمبر) — null = لا يُطوى.
  final RpFold? fold;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return RpCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          RpTitle(icon: icon, title: title, tone: RpTone.brand, fold: fold),
          if (fold?.open ?? true) ...[
          const SizedBox(height: Sp.md),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (var i = 0; i < tabs.length; i++) ...[
                  if (i > 0) const SizedBox(width: Sp.x6),
                  _Tap(
                    onTap: onTab == null ? null : () => onTab!(i),
                    child: Container(
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
                  ),
                ],
              ],
            ),
          ),
          if (note != null) ...[
            const SizedBox(height: Sp.sm),
            Text(note!, style: AppType.micro(color: AppColors.warningOnSoft), maxLines: 2),
          ],
          const SizedBox(height: Sp.md),
          if (shares.isEmpty) Text(empty, style: AppType.muted(color: AppColors.textMid)),
          for (var i = 0; i < shares.length; i++) ...[
            if (i > 0) const SizedBox(height: Sp.md),
            if (onShare == null) _share(shares[i]) else _Tap(radius: R.sm, onTap: () => onShare!(i), child: _share(shares[i])),
          ],
          if (more != null) ...[
            const SizedBox(height: Sp.md),
            Center(
              child: _Tap(
                onTap: onMore,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: Sp.xs),
                  child: Text(more!, style: AppType.bodyBold(color: AppColors.brand)),
                ),
              ),
            ),
          ],
          ],
        ],
      ),
    );
  }

  Widget _share(RpShare s) {
    // «حسب الشركة»: الاسم هو الشركة نفسها ⇒ لا وسم يكرّره (اللون في الشريط يكفي)
    final tag = s.company != null && s.company!.name != s.name ? s.company : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(s.name, style: AppType.bodyBold(color: AppColors.textHi), maxLines: 2, overflow: TextOverflow.ellipsis),
                  if (tag != null || s.sub != null)
                    Row(
                      children: [
                        if (tag != null) ...[
                          Container(width: 7, height: 7, decoration: BoxDecoration(color: tag.color, shape: BoxShape.circle)),
                          const SizedBox(width: Sp.xs),
                        ],
                        Flexible(
                          child: Text([tag?.name, s.sub].whereType<String>().join(' · '),
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
                Text(countOnly ? '${formatIQD(s.count)} $unit' : rpMoney(s.amount), style: AppType.bodyStrong(color: tone.fg), maxLines: 1),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!countOnly) Text('${s.count} $unit · ', style: AppType.micro(color: AppColors.textLow), maxLines: 1),
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

/// حقل بحث الحركات: يبدأ بنصّ الشاشة ([RpRowsCard.query]) ثمّ يملك نصّه.
class _RpSearchField extends StatefulWidget {
  const _RpSearchField({required this.initial, required this.hint, required this.onChanged});
  final String initial;
  final String hint;
  final ValueChanged<String> onChanged;

  @override
  State<_RpSearchField> createState() => _RpSearchFieldState();
}

class _RpSearchFieldState extends State<_RpSearchField> {
  late final _c = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
        controller: _c,
        onChanged: widget.onChanged,
        style: AppType.body(color: AppColors.textHi),
        decoration: InputDecoration(
          isCollapsed: true,
          border: InputBorder.none,
          hintText: widget.hint,
          hintStyle: AppType.body(color: AppColors.textPlaceholder),
        ),
      );
}

/// حقل البحث بشكل التقارير الموحّدة (سطحٌ غاطس بحدّ وأيقونة) — [onChanged] null ⇒ نصّه للعرض وحده (صور التصميم).
class RpSearchBox extends StatelessWidget {
  const RpSearchBox({super.key, required this.query, required this.hint, this.onChanged});
  final String query;
  final String hint;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Container(
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
            child: onChanged == null
                ? Text(hint, style: AppType.body(color: AppColors.textPlaceholder), maxLines: 1, overflow: TextOverflow.ellipsis)
                : _RpSearchField(initial: query, hint: hint, onChanged: onChanged!),
          ),
        ],
      ),
    );
  }
}

/// رأس اليوم فوق حركاته: التاريخ أرقاماً، وعددها، و«واصل» اليوم حين يكون ([RpDay.sum]).
class RpDayHead extends StatelessWidget {
  const RpDayHead({super.key, required this.day, this.unit = 'حركة', this.sumLabel = 'واصل'});
  final RpDay day;
  final String unit;

  /// اسم مجموع اليوم («المجموع» في المصاريف — لا «واصل»).
  final String sumLabel;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final d = day;
    // اليوم وعدده يميناً ومجموعه يساراً بسطرٍ واحد؛ وحين لا يتّسعان (٣٢٠ أو خطٌّ مكبَّر) ينزل المجموع سطراً تحته — كان العدد يُقصّ
    // إلى «1» بلا «مصروف» (لقطة ٢٣ نوفمبر).
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: Sp.x6),
      decoration: BoxDecoration(color: AppColors.surfaceSunken, borderRadius: BorderRadius.circular(R.sm)),
      child: SizedBox(
        width: double.infinity,
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          runSpacing: Sp.xxs,
          children: [
            // والعدد نفسه ينزل تحت التاريخ حين لا يتّسع بجانبه (أضيق هاتف بخطٍّ ×1.2) — لا فيض ولا قصّ
            Wrap(
              spacing: Sp.sm,
              runSpacing: Sp.xxs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(LucideIcons.calendar, size: 14, color: AppColors.textMid),
                    const SizedBox(width: Sp.x6),
                    Directionality(textDirection: TextDirection.ltr, child: Text(d.date, style: AppType.bodyBold(color: AppColors.textHi))),
                  ],
                ),
                Text('${d.count} $unit', style: AppType.micro(color: AppColors.textMid), maxLines: 1),
              ],
            ),
            if (d.sum != null)
              Wrap(
                spacing: Sp.xs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(sumLabel, style: AppType.micro(color: AppColors.textMid)),
                  Text(rpMoney(d.sum!), style: AppType.bodyStrong(color: AppColors.textHi), maxLines: 1),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class RpRowsCard extends StatelessWidget {
  const RpRowsCard(
      {super.key,
      required this.total,
      required this.days,
      this.more,
      this.onMore,
      this.onSearch,
      this.note,
      this.empty,
      this.searchHint = 'ابحث باسم المشترك أو يوزره أو رقمه',
      this.title = 'الحركات',
      this.unit = 'حركة',
      this.query = '',
      this.fold});
  final int total;
  final List<RpDay> days;

  /// عنوان البطاقة ووحدة العدّ («المشتركون» · «مشترك» في التجريبيّ).
  final String title;
  final String unit;

  /// نصّ حقل البحث (ديون المدراء: باسم المدير).
  final String searchHint;

  /// «عرض المزيد (٤٨)».
  final String? more;
  final VoidCallback? onMore;

  /// بحثٌ حيّ (null = حقلٌ للعرض فقط في صور التصميم).
  final ValueChanged<String>? onSearch;

  /// سطرٌ فوق القائمة («السجلّ ناقص…»).
  final String? note;

  /// نصّ القائمة الفارغة.
  final String? empty;

  /// قسمٌ فرعيّ يُطوى (المالك ٢٢ نوفمبر) — null = لا يُطوى.
  final RpFold? fold;

  /// نصّ البحث الحاليّ عند الشاشة: الحقل يُبنى من جديد حين يُفتح القسم بعد طيّه فيحمله (لا حقلٌ فارغ والقائمة محصورةٌ ببحثٍ
  /// لا يُرى)، وما دام القسم مطويّاً يُذكر البحث تحت عنوانه.
  final String query;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final folded = !(fold?.open ?? true);
    return RpCard(
      padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.lg, Sp.lg, Sp.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          RpTitle(
            icon: LucideIcons.listOrdered,
            title: title,
            tone: RpTone.neutral,
            trailing: Text('${formatIQD(total)} $unit', style: AppType.pillBold(color: AppColors.textMid)),
            fold: fold,
          ),
          if (folded && query.trim().isNotEmpty) ...[
            const SizedBox(height: Sp.x6),
            Text('البحث: «${query.trim()}»', style: AppType.micro(color: AppColors.warningOnSoft), maxLines: 2),
          ],
          if (!folded) ...[
          const SizedBox(height: Sp.md),
          RpSearchBox(query: query, hint: searchHint, onChanged: onSearch),
          if (note != null) ...[
            const SizedBox(height: Sp.sm),
            Text(note!, style: AppType.micro(color: AppColors.warningOnSoft), maxLines: 3),
          ],
          if (days.isEmpty) ...[
            const SizedBox(height: Sp.lg),
            Center(child: Text(empty ?? 'لا حركات بهذه الفترة', style: AppType.muted(color: AppColors.textMid))),
            const SizedBox(height: Sp.sm),
          ],
          for (final d in days) ...[
            const SizedBox(height: Sp.md),
            RpDayHead(day: d, unit: unit),
            for (final r in d.rows) _row(r),
          ],
          if (more != null) ...[
            const SizedBox(height: Sp.sm),
            Center(
              child: _Tap(
                onTap: onMore,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: Sp.xs),
                  child: Text(more!, style: AppType.bodyBold(color: AppColors.brand)),
                ),
              ),
            ),
          ],
          ],
        ],
      ),
    );
  }

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
                // لا قصّ على شاشةٍ ضيّقة أو خطٍّ كبير: الاسم والوصف والكلفة تلتفّ لسطرين قبل أيّ «…»
                Text(r.title, style: AppType.bodyBold(color: AppColors.textHi), maxLines: 2, overflow: TextOverflow.ellipsis),
                Text(r.detail, style: AppType.micro(color: AppColors.textMid), maxLines: 2, overflow: TextOverflow.ellipsis),
                if (r.cost != null)
                  Text(r.cost!, style: AppType.micro(color: AppColors.textLow), maxLines: 2, overflow: TextOverflow.ellipsis),
                if (r.balanceAfter != null) _balanceLine(r.balanceAfter!),
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
              if (r.amount != null)
                Directionality(
                  textDirection: TextDirection.ltr,
                  child: Text('${r.negative ? '−' : ''}${formatIQD(r.amount!)}',
                      style: AppType.bodyStrong(color: r.tone.fg), maxLines: 1),
                )
              else if (r.trailing != null)
                Directionality(
                  textDirection: TextDirection.ltr,
                  child: Text(r.trailing!, style: AppType.microBold(color: r.tone.fg), maxLines: 1),
                ),
              // «7:34 مساءً» بسطرٍ RTL: الرقم ثمّ الكلمة (LTR كان يقلبها «مساءً 7:34»)
              Text(r.time, style: AppType.micro(color: AppColors.textLow), maxLines: 1),
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
  const RpExportBar({super.key, this.onPdf, this.onExcel, this.onShare});
  final VoidCallback? onPdf;
  final VoidCallback? onExcel;
  final VoidCallback? onShare;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    Widget b(IconData icon, String label, Color color, VoidCallback? onTap) => Expanded(
          child: _Tap(
            radius: R.icon,
            onTap: onTap,
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
          ),
        );
    return Row(
      children: [
        b(LucideIcons.fileText, 'PDF', AppColors.error, onPdf),
        const SizedBox(width: Sp.sm),
        b(LucideIcons.sheet, 'Excel', AppColors.success, onExcel),
        const SizedBox(width: Sp.sm),
        b(LucideIcons.messageCircle, 'واتساب', AppColors.channelWhatsApp, onShare),
      ],
    );
  }
}

/// «الدين بعدها: 15,000 د.ع» / «رصيد دائن: …» / «لا دين بعدها» — بلون حاله (كـReportLogTile).
String rpBalanceText(num b) => b == 0
    ? 'لا دين بعدها'
    : (b < 0 ? 'الدين بعدها: ${formatIQD(b.abs().round())} د.ع' : 'رصيد دائن: ${formatIQD(b.round())} د.ع');

Widget _balanceLine(num b) {
  final color = b < 0 ? AppColors.error : (b > 0 ? AppColors.success : AppColors.textMid);
  return Padding(
    padding: const EdgeInsets.only(top: 2),
    child: Row(
      children: [
        Icon(b < 0 ? LucideIcons.trendingDown : (b > 0 ? LucideIcons.trendingUp : LucideIcons.check), size: 11, color: color),
        const SizedBox(width: Sp.xs),
        Flexible(
            child: Text(rpBalanceText(b), style: AppType.microBold(color: color), maxLines: 2, overflow: TextOverflow.ellipsis)),
      ],
    ),
  );
}
