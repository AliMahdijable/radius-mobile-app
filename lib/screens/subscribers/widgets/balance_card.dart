import 'dart:ui' as ui;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/util/format.dart';
import '../../../core/widgets/copyable.dart';
import '../../../core/widgets/permission_locked.dart';
import '../../../models/subscriber.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';
import 'debt_age.dart';

/// بطاقة الرصيد — «كم له وكم عليه؟»، السؤال الذي يُسأل في كلّ زيارة.
///
/// ثلاث حالات: دَينٌ (أحمر) · رصيدٌ دائن (أخضر) · صفر (محايد). والصفر
/// ليس واحدةً من الاثنتين: صبغُه بالأخضر يُوهم أنّ للمشترك مالاً عندك،
/// وبالأحمر يتّهمه بلا سبب. فله لونٌ محايد ونصٌّ صريح.
///
/// ── لماذا الأزرار في سطرٍ مستقلّ ───────────────────────────────────
/// 🐛 انحدارٌ أدخلتُه ٢٠٢٦-٠٩-٠٢ ورآه المستخدم في لقطة: المبلغ يُكتب
/// حرفاً في كلّ سطر، فيصير الكارت شريطاً عموديّاً بارتفاع الشاشة.
///
/// السبب حسابيّ لا غامض: كان الكلّ في `Row` واحد — أيقونة ٤٠ ثابتة،
/// ثمّ `Expanded` للنصّ، ثمّ **ثلاثة** أزرار بعرضها الطبيعيّ. ومجموع
/// الثابت ٣٢٧ نقطة على هاتفٍ عرضه ٣١٥ متاحة. فالـ`Expanded` — وهو
/// الوحيد المرن — يُعطى ما بقي: صفراً.
///
/// ⚠️ والأخطر أنّ `Row` **لا يشكو** في هذه الحالة. الفيض الأحمر يظهر
/// حين تتجاوز الأبناء الثابتة الحدّ بلا مرنٍ بينها؛ أمّا مع `Expanded`
/// فالتخطيط «ينجح» بسحق المرن إلى الصفر. لا استثناء، ولا خطّ أصفر —
/// شاشةٌ مشوّهة واختباراتٌ خضراء.
///
/// فالعلاج ليس تصغير الأزرار (يعود العطل مع أوّل زرٍّ رابع أو أوّل
/// ترجمةٍ أطول)، بل إزالة المنافسة أصلاً: النصّ يملك سطره، والأزرار
/// تملك سطرها وتتقاسمه بالتساوي. أيّ عدد، وأيّ عرض، وأيّ لغة.
///
/// ── ولا كلمة زرٍّ تُقصّ (١٧ نوفمبر — المالك: «صلحه») ────────────────
/// 🐛 «بالتساوي» وحده كان يقصّ «إضافة دين» إلى «إضاف…»: ثلاثة أثلاثٍ
/// متساوية وكلمتان قصيرتان («تذكير»، «تسديد») بجانب عبارةٍ أطول، فيفيض
/// عند القصيرتين ما ينقص الطويلة. قِيس على الصفحة الحقيقيّة: يُقصّ على
/// عرض ٣٢٠ حتى بالخطّ العاديّ، وعلى ٣٦٠ بخطٍّ 1.1 فما فوق، وعلى ٣٧٥ بـ1.2.
///
/// فالقرار بالقياس ([_DebtButtonRows]) لا بعتبة عرض:
///   ١. تتّسع الكلمات كلّها بأنصبةٍ متساوية ⇒ كما كان حرفاً؛
///   ٢. لا تتّسع متساويةً ويتّسع مجموعها ⇒ صفٌّ واحد، لكلّ زرٍّ حاجته
///      ونصيبٌ متساوٍ من الباقي (البطاقة لا تطول)؛
///   ٣. لا يتّسع المجموع ⇒ ينزل ما لا يتّسع صفّاً تحته بعرضه كاملاً —
///      والأخير هو «تسديد» (الإجراء الأساسيّ) فيأخذ الصفّ وحده.
class BalanceCard extends StatelessWidget {
  const BalanceCard({
    super.key,
    required this.sub,
    this.onRemind,
    this.onPay,
    this.onAddDebt,
    this.addDebtLocked = false,
    this.remindLocked = false,
    this.payLocked = false,
    this.lockedMessage,
    this.payLockedMessage,
    this.addDebtLockedMessage,
  });

  final Subscriber sub;

  /// null = الزرّ يختفي (لا رقم هاتف أو إرسال جارٍ أو لا دين) — **إلّا**
  /// إن كان مقفلاً بعلَمه أدناه.
  final VoidCallback? onRemind;
  final VoidCallback? onPay;
  final VoidCallback? onAddDebt;

  /// بلاغ ٢٠٢٦-١٠-١٤: نقص المفتاح وحده لا يُخفي الزرّ — يبقى في مكانه
  /// مقفلاً (حدٌّ محايد + قفل)، ونقرته رسالة القفل لا الشيت.
  final bool addDebtLocked;
  final bool remindLocked;
  final bool payLocked;

  /// سبب القفل غير الصلاحيّة (٩ نوفمبر — «كل الصفحات» للموظّف: صفحةٌ كتابتها من «صفحاتي») مكان «اطلبها من مديرك».
  final String? lockedMessage;

  /// سبب قفل «تسديد» و«إضافة دين» وحدهما — يغلب [lockedMessage] لهما (مراجعة 179: بيانات المشترك لم تتحدّث، فالدين المعروض
  /// قد يكون قبل تسديدٍ للتوّ). null ⇒ [lockedMessage].
  final String? payLockedMessage;
  final String? addDebtLockedMessage;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final isDebt = sub.hasDebt;
    final age = DebtAge.of(sub);
    final isZero = sub.balanceAmount == 0;
    final accent = isZero
        ? AppColors.textMid
        : (isDebt ? AppColors.error : AppColors.success);
    final softBg = isZero
        ? AppColors.surfaceSunken
        : (isDebt ? AppColors.dangerSoftBg : AppColors.successSoftBg);
    final borderCol = isZero
        ? AppColors.border
        : (isDebt ? AppColors.dangerBorderCard : AppColors.successSoftBorder);
    final label = isZero
        ? 'الرصيد'
        : (isDebt
            ? 'subscribers.label_debt_on_sub'.tr()
            : 'subscribers.label_balance_credit'.tr());
    final amount =
        isZero ? 'لا دين ولا رصيد' : '${formatIQD(sub.debtAbs.round())} د.ع';

    final buttons = <_DebtButton>[
      if (onAddDebt != null || addDebtLocked)
        _DebtButton(
          label: 'إضافة دين',
          icon: Icons.add_rounded,
          filled: false,
          color: AppColors.warning,
          borderColor: AppColors.warningSoftBorder,
          locked: addDebtLocked,
          lockedMessage: addDebtLockedMessage ?? lockedMessage,
          onTap: onAddDebt,
        ),
      if (onRemind != null || remindLocked)
        _DebtButton(
          label: 'تذكير',
          icon: Icons.notifications_active_rounded,
          filled: false,
          color: AppColors.warning,
          borderColor: AppColors.warningSoftBorder,
          locked: remindLocked,
          lockedMessage: lockedMessage,
          onTap: onRemind,
        ),
      if (onPay != null || payLocked)
        _DebtButton(
          label: 'تسديد',
          icon: Icons.payments_rounded,
          filled: true,
          color: isDebt ? AppColors.errorFill : AppColors.successFill,
          locked: payLocked,
          lockedMessage: payLockedMessage ?? lockedMessage,
          onTap: onPay,
        ),
    ];

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.card),
        border: Border.all(color: borderCol),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: softBg,
                  borderRadius: BorderRadius.circular(R.icon),
                ),
                child: Icon(
                  isZero
                      ? Icons.account_balance_wallet_rounded
                      : (isDebt
                          ? Icons.credit_card_rounded
                          : Icons.savings_rounded),
                  size: 21,
                  color: accent,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                // المبلغ يُنسخ كما يُرى بالضغط المطوّل — والتسمية معه هدفٌ
                // واحد، فلا يُطلب من المدير أن يصيب الرقم بإصبعه.
                child: Copyable(
                  label: label,
                  noun: isDebt ? 'الدين' : 'الرصيد',
                  value: amount,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppType.body(color: AppColors.textLabel),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        amount,
                        textDirection: isZero
                            ? ui.TextDirection.rtl
                            : ui.TextDirection.ltr,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: isZero
                            ? AppType.bodyStrong(color: accent)
                            : AppType.statValue(color: accent),
                      ),
                      // «أيّام الدين» (٣٠ أكتوبر): منذ متى ونوع آخر عمليّة دين، وتاريخها.
                      if (isDebt && age != null) ...[
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            DebtAgePill(age: age),
                            Text(age.dateLine, style: AppType.micro(color: AppColors.textLabel)),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
          if (buttons.isNotEmpty) ...[
            const SizedBox(height: Sp.md),
            _DebtButtonRows(buttons: buttons),
          ],
        ],
      ),
    );
  }
}

/// توزيع أزرارٍ بعروضها الطبيعيّة [natural] على صفوفٍ عرض كلٍّ منها [avail] وبين الزرّ وجاره [gap]: يملأ الصفّ ما دام
/// يتّسع ثمّ ينزل لصفٍّ تحته. الناتج فهارس الأزرار لكلّ صفّ بترتيبها — وزرٌّ أعرض من الصفّ يأخذ صفّاً وحده.
@visibleForTesting
List<List<int>> debtButtonRows(List<double> natural, double avail, double gap) {
  final rows = <List<int>>[];
  var row = <int>[];
  var used = 0.0;
  for (var i = 0; i < natural.length; i++) {
    final need = row.isEmpty ? natural[i] : used + gap + natural[i];
    if (row.isNotEmpty && need > avail) {
      rows.add(row);
      row = [i];
      used = natural[i];
    } else {
      row.add(i);
      used = need;
    }
  }
  if (row.isNotEmpty) rows.add(row);
  return rows;
}

/// صفّ أزرار البطاقة (أو صفّاها) — لا كلمة تُقصّ. القرار بقياس الكلمات بخطّ الهاتف الفعليّ (رأس الملفّ).
class _DebtButtonRows extends StatelessWidget {
  const _DebtButtonRows({required this.buttons});
  final List<_DebtButton> buttons;

  /// بين الزرّ وجاره، وبين الصفّ والذي تحته.
  static const double gap = 7;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final natural = [for (final b in buttons) b.naturalWidth(context)];
        final avail = c.maxWidth;
        // بلا عرضٍ محدود لا قرار يُتّخذ — صفٌّ واحد بالحاجة الطبيعيّة.
        if (!avail.isFinite) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < buttons.length; i++) ...[
                if (i > 0) const SizedBox(width: gap),
                SizedBox(width: natural[i], child: buttons[i]),
              ],
            ],
          );
        }
        final rows = debtButtonRows(natural, avail, gap);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var r = 0; r < rows.length; r++) ...[
              if (r > 0) const SizedBox(height: gap),
              _row(rows[r], natural, avail),
            ],
          ],
        );
      },
    );
  }

  /// صفٌّ واحد من الأزرار [idx] بعرض [avail].
  Widget _row(List<int> idx, List<double> natural, double avail) {
    final n = idx.length;
    final free = avail - gap * (n - 1);
    final share = free / n;
    // الكلّ يتّسع بأنصبةٍ متساوية ⇒ كما كان: `Expanded` لكلّ زرّ، فلا يُزاحم بعضهم بعضاً.
    final equal = idx.every((i) => natural[i] <= share);
    // وإلّا: لكلّ زرٍّ حاجته ونصيبٌ متساوٍ من الباقي — والأخير `Expanded` يأخذ ما بقي بالضبط (لا كسر عشريّ يفيض).
    final extra = (free - idx.fold<double>(0, (a, i) => a + natural[i])) / n;
    return Row(
      children: [
        for (var k = 0; k < n; k++) ...[
          if (k > 0) const SizedBox(width: gap),
          if (equal || k == n - 1)
            Expanded(child: buttons[idx[k]])
          else
            SizedBox(width: natural[idx[k]] + (extra > 0 ? extra : 0), child: buttons[idx[k]]),
        ],
      ],
    );
  }
}

/// زرّ داخل بطاقة الرصيد — height 36 · r12 · أيقونة 16.
///
/// يُبنى ليملأ ما يُعطى: المحتوى في الوسط. والكلمة لا تُقصّ: [_DebtButtonRows] يعطي الزرّ حاجته ([naturalWidth])،
/// وإن ضاق عنها مع ذلك (زرٌّ وحده أعرض من البطاقة — ترجمةٌ طويلة جدّاً) صغرت الكلمة قليلاً بدل «…».
class _DebtButton extends StatelessWidget {
  const _DebtButton({
    required this.label,
    required this.icon,
    required this.filled,
    required this.color,
    required this.onTap,
    this.borderColor,
    this.locked = false,
    this.lockedMessage,
  });
  final String label;
  final IconData icon;
  final bool filled;
  final Color color;
  final VoidCallback? onTap;
  final Color? borderColor;

  /// مقفل: لا تعبئة، حدٌّ محايد، قفلٌ مكان الأيقونة، ونصٌّ خافت.
  final bool locked;

  /// سبب القفل غير الصلاحيّة — null ⇒ رسالة الصلاحيّة كما كانت.
  final String? lockedMessage;

  static const double _padH = 8;
  static const double _iconSize = 16;
  static const double _iconGap = 5;

  /// مملوءٌ بلونه (لا حدّ له) — والمقفل والشبحيّ بحدٍّ يأخذ نقطةً من كلّ جهة.
  bool get _solid => filled && !locked;

  /// العرض الذي يحتاجه الزرّ لتظهر كلمته كاملةً: الحشوة + الحدّ + الأيقونة + الفاصل + الكلمة بخطّ الهاتف الفعليّ.
  ///
  /// يُقاس بما يرسمه `Text` فعلاً — نمط السياق مدموجاً بنمطنا، وسلّم خطّ الهاتف، والخطّ العريض إن طلبه النظام (درس
  /// ١٤ نوفمبر: النمط المجرّد يقيس أنقص ببضع نقاط فيُحكَم «يتّسع» لما لا يتّسع). ونقطةٌ احتياطاً لكسور التقريب.
  ///
  /// ⚠️ «نمط السياق» هنا نمط الزرّ نفسه لا نمط ما فوق البطاقة: الكلمة تُرسم تحت `Material` الزرّ، وهو يضع نمط النصّ
  /// الافتراضيّ `bodyMedium` من الثيم لكلّ ما تحته — فيُقاس به، أينما وُضعت البطاقة.
  double naturalWidth(BuildContext context) {
    final base = Theme.of(context).textTheme.bodyMedium ?? DefaultTextStyle.of(context).style;
    var style = base.merge(AppType.bodyStrong());
    if (MediaQuery.boldTextOf(context)) style = style.merge(const TextStyle(fontWeight: FontWeight.bold));
    final tp = TextPainter(
      text: TextSpan(text: label, style: style),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final text = tp.width;
    tp.dispose();
    return _padH * 2 + (_solid ? 0 : 2) + _iconSize + _iconGap + text.ceilToDouble() + 1;
  }

  @override
  Widget build(BuildContext context) {
    final solid = _solid;
    final fg = locked ? LockedStyle.glyph : (solid ? AppColors.onBrand : color);
    final button = Material(
      color: solid ? color : AppColors.surface,
      borderRadius: BorderRadius.circular(R.md),
      child: InkWell(
        onTap: locked ? () => showNoPermission(context, action: true, message: lockedMessage) : onTap,
        borderRadius: BorderRadius.circular(R.md),
        child: Container(
          height: H.chip,
          padding: const EdgeInsets.symmetric(horizontal: _padH),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(R.md),
            border: solid
                ? null
                : Border.all(
                    color: locked
                        ? AppColors.border
                        : (borderColor ?? AppColors.border)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(locked ? LucideIcons.lock : icon, size: _iconSize, color: fg),
              const SizedBox(width: _iconGap),
              // لا «…»: الكلمة بحجمها متى اتّسعت (وهو الحال دائماً بقياس [_DebtButtonRows])، وتصغر قليلاً إن ضاق الزرّ عنها.
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    maxLines: 1,
                    softWrap: false,
                    style: AppType.bodyStrong(color: fg),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (!locked) return button;
    return Semantics(
      button: true,
      label: 'locked.a11y'.tr(args: [label]),
      excludeSemantics: true,
      child: button,
    );
  }
}
