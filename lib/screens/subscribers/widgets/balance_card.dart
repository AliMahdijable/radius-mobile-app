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

    final buttons = <Widget>[
      if (onAddDebt != null || addDebtLocked)
        _DebtButton(
          label: 'إضافة دين',
          icon: Icons.add_rounded,
          filled: false,
          color: AppColors.warning,
          borderColor: AppColors.warningSoftBorder,
          locked: addDebtLocked,
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
          onTap: onRemind,
        ),
      if (onPay != null || payLocked)
        _DebtButton(
          label: 'تسديد',
          icon: Icons.payments_rounded,
          filled: true,
          color: isDebt ? AppColors.errorFill : AppColors.successFill,
          locked: payLocked,
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
            Row(
              children: [
                for (var i = 0; i < buttons.length; i++) ...[
                  if (i > 0) const SizedBox(width: 7),
                  // ⚠️ `Expanded` لكلّ زرّ: يتقاسمون العرض بالتساوي مهما
                  // كان عددهم، فلا يُزاحم بعضهم بعضاً ولا يزاحمون النصّ.
                  Expanded(child: buttons[i]),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// زرّ داخل بطاقة الرصيد — height 36 · r12 · أيقونة 16.
///
/// يُبنى ليملأ ما يُعطى: المحتوى في الوسط، والنصّ `Flexible` بقصٍّ —
/// فترجمةٌ طويلة أو شاشةٌ ضيّقة تقصّ الكلمة ولا تكسر الصفّ.
class _DebtButton extends StatelessWidget {
  const _DebtButton({
    required this.label,
    required this.icon,
    required this.filled,
    required this.color,
    required this.onTap,
    this.borderColor,
    this.locked = false,
  });
  final String label;
  final IconData icon;
  final bool filled;
  final Color color;
  final VoidCallback? onTap;
  final Color? borderColor;

  /// مقفل: لا تعبئة، حدٌّ محايد، قفلٌ مكان الأيقونة، ونصٌّ خافت.
  final bool locked;

  @override
  Widget build(BuildContext context) {
    final solid = filled && !locked;
    final fg = locked ? LockedStyle.glyph : (solid ? AppColors.onBrand : color);
    final button = Material(
      color: solid ? color : AppColors.surface,
      borderRadius: BorderRadius.circular(R.md),
      child: InkWell(
        onTap: locked ? () => showNoPermission(context, action: true) : onTap,
        borderRadius: BorderRadius.circular(R.md),
        child: Container(
          height: H.chip,
          padding: const EdgeInsets.symmetric(horizontal: 8),
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
              Icon(locked ? LucideIcons.lock : icon, size: 16, color: fg),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.bodyStrong(color: fg),
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
