import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/util/format.dart';
import '../../../models/subscriber.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';

/// «أيّام الدين» — منذ كم يوم آخر عمليّة دينٍ على المشترك، ونوعها بين قوسين (تفعيل · شراء · إضافة دين).
///
/// المالك (٣٠ أكتوبر): «ميزة بفايبر اكس حلوة… ايام الدين يعني المشترك صارله شكد من عليه اخر عمليه دين وبين
/// قوسين شنو جانت تفعيل او شراء تظهر بكارت المشترك وبصفحات المشتركين» — واختار الشارة الملوّنة، ثمّ: «تكدر ترتبه
/// اكثر لان هسه ياخذ من الوجدت مساحه» ⇒ داخل شريط الدين بسطرٍ رفيع، لا شريط جديد.
///
/// المصدر الخادم (`debt_since` · `debt_kind` على صفّ المدين وحده — آخر حركةٍ زادت دينه في دفتر رصيده؛ التسديد الجزئيّ
/// لا يصفّر العدّاد). «دين قديم» = دينٌ دخل دفترنا باستيرادٍ أو ترحيل: تاريخه تاريخ الإدخال لا الدين، فلا تُكتب أيّامه
/// (المالك ٣٠ أكتوبر: التسمية الأولى «تربك الوكيل»).

/// درجة عمر الدين — اللون مع الرقم والأيقونة دائماً (لا يحمل اللون المعنى وحده).
enum DebtAgeTier { fresh, aging, old, legacy }

/// عتبات فلتر «أكثر من … يوماً» تحت «مديون».
const debtAgeThresholds = [7, 15, 30, 60, 90];

@immutable
class DebtAge {
  const DebtAge({required this.since, required this.kind});

  /// وقت آخر عمليّة دين (من الخادم، بتوقيت الجهاز).
  final DateTime since;

  /// activate · extend · sale · manual · opening.
  final String kind;

  /// عمر دين المشترك — null لغير المدين أو بلا تاريخٍ من الخادم.
  static DebtAge? of(Subscriber s) {
    final since = s.debtSince;
    if (!s.hasDebt || since == null) return null;
    return DebtAge(since: since, kind: s.debtKind ?? '');
  }

  /// بتقويم الجهاز: منتصف الليل للمنتصف (دينٌ أمس = يوم، اليوم = 0).
  int days([DateTime? now]) {
    final n = now ?? DateTime.now();
    final a = DateTime(since.year, since.month, since.day);
    final b = DateTime(n.year, n.month, n.day);
    final d = b.difference(a).inDays;
    return d < 0 ? 0 : d;
  }

  String get kindLabel => switch (kind) {
        'activate' => 'تفعيل',
        'sale' => 'شراء',
        'manual' => 'إضافة دين',
        'extend' => 'تمديد',
        _ => 'دين قديم',
      };

  bool get legacy => !const {'activate', 'sale', 'manual', 'extend'}.contains(kind);

  DebtAgeTier tierAt([DateTime? now]) {
    if (legacy) return DebtAgeTier.legacy;
    final d = days(now);
    if (d <= 7) return DebtAgeTier.fresh;
    if (d <= 30) return DebtAgeTier.aging;
    return DebtAgeTier.old;
  }

  /// «12 يوماً» · «اليوم» · «يوم» · «يومين».
  String daysText([DateTime? now]) {
    final d = days(now);
    return d == 0 ? 'اليوم' : arDays(d);
  }

  /// التاريخ بصيغة الكرت (‏2026/10/18) — معزولاً اتّجاهه (LRI…PDI) فلا تنقلب أجزاؤه بين العربيّة.
  String get dateText {
    String two(int n) => n.toString().padLeft(2, '0');
    return '\u2066${since.year}/${two(since.month)}/${two(since.day)}\u2069';
  }

  /// نصّ الشارة: «12 يوماً (تفعيل)» · «دين قديم».
  String pillText([DateTime? now]) => legacy ? 'دين قديم' : '${daysText(now)} ($kindLabel)';

  /// تحت الشارة بصفحة المشترك: «آخر دين 2026/10/18» · «قبل 2026/10/19».
  String get dateLine => legacy ? 'قبل $dateText' : 'آخر دين $dateText';
}

/// ألوان الدرجة: (خلفيّة، حدّ، نصّ).
(Color, Color, Color) debtAgeColors(DebtAgeTier t) => switch (t) {
      DebtAgeTier.fresh => (AppColors.surface, AppColors.warningSoftBorder, AppColors.warningOnSoft),
      DebtAgeTier.aging => (AppColors.warningSoftBg, AppColors.warningSoftBorder, AppColors.warningOnSoft),
      DebtAgeTier.old => (AppColors.errorFill, AppColors.errorFill, AppColors.onBrand),
      DebtAgeTier.legacy => (AppColors.surface, AppColors.border, AppColors.textMid),
    };

/// شارةٌ ملوّنة بعمر الدين — حتى 7 أيّام هادئة، 8–30 كهرمانيّة، أكثر من 30 حمراء، «دين قديم» رماديّة.
/// dense = داخل شريط الدين بكرت القائمة وخليّة الجدول: رفيعةٌ (18) كي لا يطول الكرت.
class DebtAgePill extends StatelessWidget {
  const DebtAgePill({super.key, required this.age, this.dense = false, this.fit = false});
  final DebtAge age;
  final bool dense;

  /// خليّة جدولٍ بعرضٍ ثابت: الشارة كلّها تصغر قليلاً حين لا تتّسع («38 يوماً (إضافة دين)» بعمود 120) — لا تُقصّ ولا تلاصق
  /// العمود المجاور. (بلا `Flexible` هنا: FittedBox يعطي ابنه عرضاً مفتوحاً.)
  final bool fit;

  static TextStyle _textStyle(Color fg, bool dense) =>
      AppType.pillBold(color: fg).copyWith(fontSize: dense ? 10.5 : 11.5, height: dense ? 1.1 : null);

  /// عرض الشارة كما تُرسم (للقياس قبل البناء — شريط الدين يقرّر بها «بجانب المبلغ أم تحته»).
  static double widthOf(BuildContext context, DebtAge age, {bool dense = false}) {
    final tp = TextPainter(
      text: TextSpan(text: age.pillText(), style: _textStyle(AppColors.textBody, dense)),
      textDirection: TextDirection.rtl,
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final w = tp.width;
    tp.dispose();
    return (dense ? 14 : 16) + 2 + (dense ? 11 : 12.5) + (dense ? 3 : 4) + w;
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final (bg, border, fg) = debtAgeColors(age.tierAt());
    final pill = Semantics(
      label: age.legacy ? 'دين قديم، ${age.dateLine}' : 'أيّام الدين: ${age.pillText()}',
      excludeSemantics: true,
      child: Container(
        height: dense ? 18 : 24,
        padding: EdgeInsets.symmetric(horizontal: dense ? 7 : 8),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(R.pill),
          border: Border.all(color: border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(age.legacy ? LucideIcons.history : LucideIcons.clock3, size: dense ? 11 : 12.5, color: fg),
            SizedBox(width: dense ? 3 : 4),
            if (fit)
              Text(age.pillText(), maxLines: 1, style: _textStyle(fg, dense))
            else
              Flexible(
                child: Text(
                  age.pillText(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _textStyle(fg, dense),
                ),
              ),
          ],
        ),
      ),
    );
    return fit ? FittedBox(fit: BoxFit.scaleDown, child: pill) : pill;
  }
}
