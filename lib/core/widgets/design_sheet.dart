// `hide TextDirection`: الحزمة تصدّر نوع intl الذي يحجب نوع
// dart:ui المستعمَل في `textDirection` عبر الملفّ.
import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';

import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';

/// قوقعة الـbottom sheet ومكوّناتها — الشريحة 5 من إعادة التصميم
/// (2026-08-29).
///
/// المخطّط يرسم **اثني عشر** شيتاً بنفس الهيكل حرفيّاً: مقبض 42×4 · رأس
/// بمربّع أيقونة 40×40 وعنوان 17/w700 وسطر معرّف 11.5 وزرّ إغلاق دائري
/// 32 · جسم بحشوة 16×20 وفواصل 16 · شريط سفلي بحدّ علوي وزرّ h50/r17.
///
/// قبل هذا الملفّ كان كلّ شيت يحمل نسخته الخاصّة من `_SheetHandle` و
/// `_SheetHeader` و`_SubmitBar` — اثنتا عشرة نسخة تنجرف عن بعضها مع
/// كلّ تعديل. الكلّ يستورد من هنا الآن.
///
/// ── ملاحظات تنفيذ ──────────────────────────────────────────────────
/// • الارتفاع الأقصى 94% كما في المخطّط، و`isScrollControlled: true`
///   شرط في `showModalBottomSheet` وإلّا قُصّ الشيت عند 50%.
/// • حشوة لوحة المفاتيح (`viewInsets.bottom`) تُضاف تحت الجسم لا تحت
///   الشريط — الشريط يبقى ملتصقاً بأعلى اللوحة كما يتوقّع المستخدم.
/// • `barrierColor` يجب أن يكون `AppColors.scrim` (مبنيّ على #121614)
///   لا `Colors.black54` — الفرق مرئي فوق الأخضر.

/// الشلّ الكامل. مرّرْ `footer` لو للشيت زرّ تنفيذ، واتركه `null`
/// للشيتات العارضة (سجل الحركات، كشف الحساب).
class DesignSheet extends StatelessWidget {
  const DesignSheet({
    super.key,
    required this.header,
    required this.body,
    this.footer,
    this.maxHeightFactor = 0.94,
    this.bodyPadding =
        const EdgeInsets.symmetric(horizontal: Sp.xl, vertical: Sp.lg),
    this.scrollable = true,
  });

  final Widget header;
  final Widget body;
  final Widget? footer;
  final double maxHeightFactor;
  final EdgeInsets bodyPadding;

  /// `false` حين يدير الجسم تمريره بنفسه (قائمة طويلة داخل `Expanded`).
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final media = MediaQuery.of(context);
    final inset = media.viewInsets.bottom;
    Widget content = Padding(padding: bodyPadding, child: body);
    if (scrollable) {
      content = SingleChildScrollView(
        padding: EdgeInsets.only(bottom: inset),
        child: content,
      );
    }
    return Container(
      constraints:
          BoxConstraints(maxHeight: media.size.height * maxHeightFactor),
      decoration: BoxDecoration(
        color: AppColors.surfaceSheet,
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(R.sheet)),
        boxShadow: Sh.sheet,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SheetHandle(),
          header,
          Flexible(child: content),
          if (footer != null)
            SafeArea(top: false, child: footer!)
          else
            SizedBox(height: media.padding.bottom + Sp.sm),
        ],
      ),
    );
  }
}

/// المقبض 42×4 — أعلى كلّ شيت في المخطّط بلا استثناء.
class SheetHandle extends StatelessWidget {
  const SheetHandle({super.key});

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Padding(
      padding: const EdgeInsets.only(top: Sp.md),
      child: Center(
        child: Container(
          width: 42,
          height: H.grabber,
          decoration: BoxDecoration(
            color: AppColors.grabber,
            borderRadius: BorderRadius.circular(R.pill),
          ),
        ),
      ),
    );
  }
}

/// رأس الشيت — مربّع أيقونة ملوّن + عنوان + معرّف + زرّ إغلاق.
///
/// `tint` يلوّن مربّع الأيقونة فقط، لا العنوان: المخطّط يستعمل الأخضر
/// للإجراءات العاديّة والكهرماني لإضافة الدين والأحمر للحذف، بينما
/// العنوان يبقى `textHi` في كلّ الحالات.
class SheetHeaderBar extends StatelessWidget {
  const SheetHeaderBar({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onClose,
    this.tint,
    this.tintBg,
    this.subtitleLtr = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onClose;

  /// لون الأيقونة. الافتراضي `brand`.
  final Color? tint;

  /// خلفيّة مربّع الأيقونة. الافتراضي `brandSoftBg`.
  final Color? tintBg;

  /// `true` للمعرّفات اللاتينيّة (`user@admin`) — المخطّط يفرض
  /// `direction:ltr` عليها حتى لا ينقلب موضع الـ@.
  final bool subtitleLtr;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Container(
      padding: const EdgeInsets.fromLTRB(Sp.xl, 18, Sp.xl, Sp.lg),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.dividerStrong)),
      ),
      child: Row(
        children: [
          Container(
            width: H.iconBox,
            height: H.iconBox,
            decoration: BoxDecoration(
              color: tintBg ?? AppColors.brandSoftBg,
              borderRadius: BorderRadius.circular(R.icon),
            ),
            child: Icon(icon, size: 20, color: tint ?? AppColors.brand),
          ),
          const SizedBox(width: Sp.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title,
                    style: AppType.sheetTitle(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 1),
                  Text(
                    subtitle,
                    textDirection: subtitleLtr ? TextDirection.ltr : null,
                    style: AppType.muted().copyWith(fontSize: 11.5),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: Sp.sm),
          SheetCloseButton(onTap: onClose),
        ],
      ),
    );
  }
}

/// زرّ الإغلاق الدائري 32 — خلفيّة `bg` وأيقونة `textMid`.
class SheetCloseButton extends StatelessWidget {
  const SheetCloseButton({super.key, required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Material(
      color: AppColors.surfaceSunken,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: H.closeBtn,
          height: H.closeBtn,
          child: Icon(Icons.close_rounded, size: 18, color: AppColors.textMid),
        ),
      ),
    );
  }
}

/// الشريط السفلي — حدّ علوي + زرّ أساسي h50/r17، ويسبقه اختياريّاً زرّ
/// أيقوني 50×50 (الحذف في شيت إعدادات الجهاز).
class SheetFooterBar extends StatelessWidget {
  const SheetFooterBar({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.busy = false,
    this.enabled = true,
    this.color,
    this.leading,
    this.above,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool busy;
  final bool enabled;

  /// لون الزرّ. الافتراضي `brand`؛ المخطّط يستعمل الكهرماني لإضافة
  /// الدين والأحمر للحذف.
  final Color? color;

  /// زرّ أيقوني ثانوي يسبق الأساسي.
  final Widget? leading;

  /// صفّ يعلو الزرّ داخل الشريط نفسه — خانة «طباعة وصل بعد التأكيد»
  /// في شيت التسديد. المخطّط يضعها فوق الزرّ لا في الجسم.
  final Widget? above;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final live = enabled && !busy && onPressed != null;
    final fill = live ? (color ?? AppColors.brand) : AppColors.surfaceDisabled;
    final fg = live ? AppColors.onBrand : AppColors.textHint;
    return Container(
      padding: const EdgeInsets.fromLTRB(Sp.xl, 14, Sp.xl, 22),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.dividerStrong)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (above != null) ...[above!, const SizedBox(height: 11)],
          Row(
            children: [
              if (leading != null) ...[leading!, const SizedBox(width: 9)],
              Expanded(
                child: SizedBox(
                  height: H.button,
                  child: Material(
                    color: fill,
                    borderRadius: BorderRadius.circular(R.button),
                    child: InkWell(
                      onTap: live ? onPressed : null,
                      borderRadius: BorderRadius.circular(R.button),
                      child: Center(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (busy)
                              SizedBox(
                                width: 19,
                                height: 19,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: fg),
                              )
                            else
                              Icon(icon, size: 19, color: fg),
                            const SizedBox(width: Sp.sm),
                            Flexible(
                              child: Text(label,
                                  style: AppType.button(color: fg),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// زرّ أيقوني 50×50 للشريط السفلي — أبيض بحدّ ملوّن خافت.
class SheetFooterIconButton extends StatelessWidget {
  const SheetFooterIconButton({
    super.key,
    required this.icon,
    required this.onTap,
    required this.color,
  });
  final IconData icon;
  final VoidCallback? onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return SizedBox(
      width: H.button,
      height: H.button,
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.button),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(R.button),
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(R.button),
              border: Border.all(color: color.withValues(alpha: 0.28)),
            ),
            child: Icon(icon, size: 20, color: color),
          ),
        ),
      ),
    );
  }
}

/// مجموعة في جسم الشيت: تسمية 11.5/w600 (+ تلميح يمين) فوق المحتوى.
class SheetSection extends StatelessWidget {
  const SheetSection({
    super.key,
    required this.label,
    required this.child,
    this.hint,
    this.gap = Sp.x6,
    this.footnote,
  });

  final String label;
  final Widget child;

  /// نصّ خافت في طرف سطر التسمية — «تلقائي يجرب Ubiquiti ثم ONT».
  final String? hint;
  final double gap;

  /// سطر تحت الحقل — «مفيد للأجهزة خلف NAT».
  final String? footnote;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(label, style: AppType.label()),
            if ((hint ?? '').isNotEmpty) ...[
              const Spacer(),
              Flexible(
                child: Text(hint!,
                    style: AppType.muted(color: AppColors.textHint),
                    textAlign: TextAlign.end,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ),
            ],
          ],
        ),
        SizedBox(height: gap),
        child,
        if ((footnote ?? '').isNotEmpty) ...[
          const SizedBox(height: Sp.x6),
          Text(footnote!, style: AppType.muted(color: AppColors.textHint)),
        ],
      ],
    );
  }
}

/// الحقل الأبيض r16 بحدّ 1px — يلفّ `TextField` أو نصّاً ساكناً.
/// الحدّ يصير 1.5 بلون البراند حين `focused`.
class SheetBox extends StatelessWidget {
  const SheetBox({
    super.key,
    required this.child,
    this.icon,
    this.focused = false,
    this.padding = const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
    this.radius = R.lg,
    this.alignTop = false,
    this.background,
    this.borderColor,
  });

  final Widget child;
  final IconData? icon;
  final bool focused;
  final EdgeInsets padding;
  final double radius;

  /// `true` لحقول متعدّدة الأسطر — الأيقونة تلتصق بأعلى النصّ.
  final bool alignTop;
  final Color? background;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: background ?? AppColors.surface,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: focused ? AppColors.brand : (borderColor ?? AppColors.border),
          width: focused ? BW.selected : BW.normal,
        ),
      ),
      child: Row(
        crossAxisAlignment:
            alignTop ? CrossAxisAlignment.start : CrossAxisAlignment.center,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 18, color: AppColors.textHint),
            const SizedBox(width: Sp.sm),
          ],
          Expanded(child: child),
        ],
      ),
    );
  }
}

/// صندوق ملخّص — تسمية يمين وقيمة بارزة يسار. «الدين الحالي».
class SheetSummaryBox extends StatelessWidget {
  const SheetSummaryBox({
    super.key,
    required this.label,
    required this.value,
    this.valueColor,
    this.background,
    this.borderColor,
    this.icon,
  });

  final String label;
  final String value;
  final Color? valueColor;
  final Color? background;
  final Color? borderColor;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Sp.lg, vertical: 14),
      decoration: BoxDecoration(
        color: background ?? AppColors.surface,
        borderRadius: BorderRadius.circular(R.card),
        border: Border.all(color: borderColor ?? AppColors.border),
      ),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: valueColor ?? AppColors.textLabel),
            const SizedBox(width: Sp.x6),
          ],
          Expanded(
            child: Text(label,
                style: AppType.body(color: AppColors.textLabel),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(width: Sp.sm),
          Text(
            value,
            textDirection: TextDirection.ltr,
            style: AppType.statValue(color: valueColor ?? AppColors.textHi),
          ),
        ],
      ),
    );
  }
}

/// شريحة مبلغ سريع — r11، مملوءة بالبراند حين تُختار.
class SheetQuickChip extends StatelessWidget {
  const SheetQuickChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
    this.suggested = false,
    this.enabled = true,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  /// شريحة «كامل الدين» — خضراء خفيفة دائماً حتى وهي غير مختارة،
  /// لأنّها اختصار مقترَح لا قيمة من سلّم المبالغ.
  final bool suggested;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final Color bg, border, fg;
    if (!enabled) {
      bg = AppColors.surfaceDisabled;
      border = AppColors.border;
      fg = AppColors.textHint;
    } else if (selected) {
      bg = AppColors.brand;
      border = AppColors.brand;
      fg = AppColors.onBrand;
    } else if (suggested) {
      bg = AppColors.brandSoftBg;
      border = AppColors.brandSoftBorder;
      fg = AppColors.brandOnSoft;
    } else {
      bg = AppColors.surface;
      border = AppColors.border;
      fg = AppColors.textBody;
    }
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(R.chip),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(R.chip),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(R.chip),
            border: Border.all(color: border),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 15, color: fg),
                const SizedBox(width: Sp.xs),
              ],
              Text(
                label,
                textDirection: icon == null ? TextDirection.ltr : null,
                style: AppType.bodyStrong(color: fg),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// شريط مقسّم h44/r14 — الاختيار يرفع سُمك الحدّ إلى 1.5 ويصبغه بالبراند.
class SheetSegmented extends StatelessWidget {
  const SheetSegmented({
    super.key,
    required this.labels,
    required this.selectedIndex,
    required this.onSelect,
    this.icons,
  });

  final List<String> labels;
  final List<IconData>? icons;
  final int selectedIndex;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final children = <Widget>[];
    for (var i = 0; i < labels.length; i++) {
      if (i > 0) children.add(const SizedBox(width: Sp.sm));
      final on = i == selectedIndex;
      children.add(Expanded(
        child: Material(
          color: on ? AppColors.brandSoftBg : AppColors.surface,
          borderRadius: BorderRadius.circular(R.icon),
          child: InkWell(
            onTap: () => onSelect(i),
            borderRadius: BorderRadius.circular(R.icon),
            child: Ink(
              height: H.segment,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(R.icon),
                border: Border.all(
                  color: on ? AppColors.brand : AppColors.border,
                  width: on ? BW.selected : BW.normal,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (icons != null) ...[
                    Icon(icons![i],
                        size: 18,
                        color: on ? AppColors.brand : AppColors.textBody),
                    const SizedBox(width: Sp.x6),
                  ],
                  Flexible(
                    child: Text(
                      labels[i],
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.input(
                        color: on ? AppColors.brand : AppColors.textBody,
                      ).copyWith(
                          fontWeight: on ? FontWeight.w700 : FontWeight.w500),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ));
    }
    return Row(children: children);
  }
}

/// بانر نتيجة ملوّن — «الدين بعد الإضافة» / «الانتهاء الجديد».
class SheetResultBanner extends StatelessWidget {
  const SheetResultBanner({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.tone,
  });

  final IconData icon;
  final String label;
  final String value;

  /// أيّ نغمة من `AppTone` — الرباعيّة الدلاليّة تتكفّل بالباقي.
  final AppTone tone;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    // كان هنا مفتاح يدويّ على `SheetTone` الثلاثيّ يعيد بناء ما
    // تعرفه `AppTone` أصلاً للتسع. حُذف الـenum المكرّر: سلّما نغمات
    // في طقم واحد يفرضان على القارئ تذكّر أيّهما لأيّ عنصر.
    final bg = tone.softBg;
    final border = tone.softBorder;
    final fg = tone.onSoft;
    final strong = tone.fill;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(R.lg),
        border: Border.all(color: border),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: fg),
          const SizedBox(width: 7),
          Expanded(
            child: Text(label,
                style: AppType.body(color: fg),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(width: Sp.sm),
          Text(
            value,
            textDirection: TextDirection.ltr,
            style: AppType.cardTitle(color: strong)
                .copyWith(fontSize: 15, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}


/// بطاقة النتيجة الداكنة — «السعر بعد الخصم» في شيت الخصم و«الملخّص»
/// في شيت التجديد. سطحها براند ثابت في الوضعين (طبقات `onBrand*`)،
/// فلا تحتاج تعديلاً في الوضع الداكن.
class SheetBrandResultCard extends StatelessWidget {
  const SheetBrandResultCard({
    super.key,
    required this.label,
    required this.value,
    this.strikethrough,
  });

  final String label;
  final String value;

  /// القيمة المشطوبة قبل التغيير — السعر الأصلي قبل الخصم.
  final String? strikethrough;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: Sp.lg),
      decoration: BoxDecoration(
        color: AppColors.brandSurface,
        borderRadius: BorderRadius.circular(R.card),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: AppType.body(color: AppColors.onBrandSecondary),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: Sp.sm),
          if ((strikethrough ?? '').isNotEmpty) ...[
            Text(
              strikethrough!,
              textDirection: TextDirection.ltr,
              style: AppType.body(color: AppColors.onBrandTertiary)
                  .copyWith(decoration: TextDecoration.lineThrough),
            ),
            const SizedBox(width: 9),
          ],
          Text(
            value,
            textDirection: TextDirection.ltr,
            style: AppType.heroName(color: AppColors.onBrand)
                .copyWith(fontSize: 20, letterSpacing: 0),
          ),
        ],
      ),
    );
  }
}

/// صفّ داخل `SheetRowsGroup`.
class SheetRowData {
  const SheetRowData({
    required this.label,
    required this.value,
    this.valueColor,
    this.strong = false,
  });
  final String label;
  final String value;
  final Color? valueColor;

  /// القيمة بوزن 700 بدل 600 — «دين حالي» في شيت التجديد.
  final bool strong;
}

/// مجموعة صفوف بيضاء r16 تفصلها خطوط شعريّة — «دين حالي · رصيد المدير ·
/// النقاط». المخطّط يجمعها في حاوية واحدة لا في كروت منفصلة.
class SheetRowsGroup extends StatelessWidget {
  const SheetRowsGroup({super.key, required this.rows});
  final List<SheetRowData> rows;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.lg),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) Divider(height: 1, color: AppColors.divider),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 11),
              child: Row(
                children: [
                  Expanded(
                    child: Text(rows[i].label,
                        style: AppType.body(color: AppColors.textLabel),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ),
                  const SizedBox(width: Sp.sm),
                  Text(
                    rows[i].value,
                    textDirection: TextDirection.ltr,
                    style: AppType.body(
                      color: rows[i].valueColor ?? AppColors.textHi,
                    ).copyWith(
                      fontWeight:
                          rows[i].strong ? FontWeight.w700 : FontWeight.w600,
                    ),
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

/// بلاطات اختيار عموديّة (أيقونة فوق تسمية) — «نقدي · دين · جزئي».
/// المختارة **مملوءة بالبراند** لا ملوّنة بلون خاصّ بها؛ المخطّط لا
/// يعطي كلّ طريقة دفع لوناً، والألوان القديمة (بنفسجي/أحمر) كانت
/// تُقرأ كحالة لا كاختيار.
class SheetChoiceTiles extends StatelessWidget {
  const SheetChoiceTiles({
    super.key,
    required this.labels,
    required this.icons,
    required this.selectedIndex,
    required this.onSelect,
    this.enabled = true,
  });

  final List<String> labels;
  final List<IconData> icons;
  final int selectedIndex;
  final ValueChanged<int> onSelect;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final children = <Widget>[];
    for (var i = 0; i < labels.length; i++) {
      if (i > 0) children.add(const SizedBox(width: Sp.sm));
      final on = i == selectedIndex;
      children.add(Expanded(
        child: Material(
          color: on ? AppColors.brand : AppColors.surface,
          borderRadius: BorderRadius.circular(R.lg),
          child: InkWell(
            onTap: enabled ? () => onSelect(i) : null,
            borderRadius: BorderRadius.circular(R.lg),
            child: Ink(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(R.lg),
                border: Border.all(
                  color: on ? AppColors.brand : AppColors.border,
                  width: on ? BW.selected : BW.normal,
                ),
              ),
              padding: const EdgeInsets.symmetric(
                  vertical: Sp.md, horizontal: Sp.x6),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icons[i],
                      size: 20,
                      color: on ? AppColors.onBrand : AppColors.textLabel),
                  const SizedBox(height: Sp.x6),
                  Text(
                    labels[i],
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.body(
                      color: on ? AppColors.onBrand : AppColors.textBody,
                    ).copyWith(
                        fontWeight: on ? FontWeight.w600 : FontWeight.w500),
                  ),
                ],
              ),
            ),
          ),
        ),
      ));
    }
    // نفس فخّ 2026-08-29: صفّ داخل ListView + stretch = ارتفاع لا نهائي.
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }
}

/// بطاقة الباقة الداكنة في شيت التجديد — اسم الباقة وحبّة المدّة،
/// وتحت خطّ شعري «المبلغ المطلوب» بقيمة 22/w700 (والسعر الأصلي
/// مشطوباً بجانبها عند وجود خصم).
class SheetPlanCard extends StatelessWidget {
  const SheetPlanCard({
    super.key,
    required this.planLabel,
    required this.planName,
    required this.durationLabel,
    required this.amountLabel,
    required this.amount,
    this.strikethrough,
  });

  final String planLabel;
  final String planName;
  final String? durationLabel;
  final String amountLabel;
  final String amount;
  final String? strikethrough;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: Sp.lg),
      decoration: BoxDecoration(
        color: AppColors.brandSurface,
        borderRadius: BorderRadius.circular(R.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(planLabel,
                        style: AppType.muted(color: AppColors.onBrandSecondary)
                            .copyWith(fontSize: 11.5)),
                    const SizedBox(height: Sp.xxs),
                    Text(
                      planName,
                      textDirection: TextDirection.ltr,
                      style: AppType.cardTitle(color: AppColors.onBrand)
                          .copyWith(fontSize: 16, fontWeight: FontWeight.w700),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if ((durationLabel ?? '').isNotEmpty) ...[
                const SizedBox(width: Sp.sm),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: Sp.md, vertical: Sp.x6),
                  decoration: BoxDecoration(
                    color: AppColors.onBrandFill2,
                    borderRadius: BorderRadius.circular(R.pill),
                  ),
                  child: Text(
                    durationLabel!,
                    style: AppType.bodyStrong(color: AppColors.onBrand)
                        .copyWith(fontSize: 12.5),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 14),
          Container(height: 1, color: AppColors.onBrandFill2),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: Text(amountLabel,
                    style: AppType.body(color: AppColors.onBrandSecondary)),
              ),
              if ((strikethrough ?? '').isNotEmpty) ...[
                Text(
                  strikethrough!,
                  textDirection: TextDirection.ltr,
                  style: AppType.body(color: AppColors.onBrandTertiary)
                      .copyWith(decoration: TextDecoration.lineThrough),
                ),
                const SizedBox(width: 9),
              ],
              Text(
                amount,
                textDirection: TextDirection.ltr,
                style: AppType.amount(color: AppColors.onBrand)
                    .copyWith(fontSize: 22),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// شيت التأكيد الموحّد — بديل `AlertDialog` في كل عمليّة تحتاج «متأكّد؟».
///
/// كان في التطبيق **٣٧ حواراً** بلغة Material الافتراضيّة: نصف قطر 28
/// وحشوة وأزرار وخطّ كلّها خارج سلّم المخطّط، ولا تعرف نغمة العمليّة.
/// وأخطرها أنّ حوار الحذف وحوار التأكيد العادي يبدوان متطابقين — فلا
/// شيء بصريّ يبطّئ اليد قبل فعل لا رجعة فيه.
///
/// هنا: مربّع أيقونة بنغمة العمليّة · عنوان `sheetTitle` · نصّ الجسم
/// `rowValue` بارتفاع سطر مريح · وزرّان بارتفاع `H.button` — المدمّر
/// منهما مملوء بلون عائلته لا رماديّاً.
///
/// يرجع `true` عند التأكيد، و`null`/`false` عند الإلغاء أو السحب.
Future<bool?> showConfirmSheet(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  String? cancelLabel,
  IconData icon = Icons.help_outline_rounded,
  AppTone tone = AppTone.brand,
  String subtitle = '',
}) {
  final (tint, tintBg, fill) = switch (tone) {
    // ⚠️ البراند هنا `brand` الداكن لا `tone.fill` (=`brandAccent`):
    // زرّ التأكيد ممتلئ وعريض، والأكسنت عليه يبدو باهتاً بجانب
    // الأزرار الأخرى في الشاشة نفسها.
    AppTone.brand => (AppColors.brand, AppColors.brandSoftBg, AppColors.brand),
    // والخطر يستعمل `errorFill` للتعبئة — أغمق من `error` النصّي.
    AppTone.danger => (AppColors.error, AppColors.dangerSoftBg, AppColors.errorFill),
    _ => (tone.fill, tone.softBg, tone.fill),
  };
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: AppColors.scrim,
    builder: (ctx) => DesignSheet(
      header: SheetHeaderBar(
        icon: icon,
        title: title,
        subtitle: subtitle,
        tint: tint,
        tintBg: tintBg,
        onClose: () => Navigator.of(ctx).pop(false),
      ),
      footer: SheetFooterBar(
        label: confirmLabel,
        icon: tone == AppTone.danger
            ? Icons.delete_outline_rounded
            : Icons.check_rounded,
        color: fill,
        onPressed: () => Navigator.of(ctx).pop(true),
        // زرّ الإلغاء يسبق المؤكِّد ويأخذ عرضه من نصّه — الترتيب في
        // RTL يضعه يمين المدمِّر، وهو الموضع الذي تقع عليه الإبهام أوّلاً.
        leading: _ConfirmCancelButton(
          label: cancelLabel ?? 'common.cancel'.tr(),
          onTap: () => Navigator.of(ctx).pop(false),
        ),
      ),
      body: Text(
        message,
        style:
            AppType.rowValue(color: AppColors.textBody).copyWith(height: 1.6),
      ),
    ),
  );
}

class _ConfirmCancelButton extends StatelessWidget {
  const _ConfirmCancelButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return SizedBox(
      height: H.button,
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.button),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(R.button),
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(R.button),
              border: Border.all(color: AppColors.borderSoft),
            ),
            padding: const EdgeInsets.symmetric(horizontal: Sp.xl),
            child: Center(
              child:
                  Text(label, style: AppType.button(color: AppColors.textBody)),
            ),
          ),
        ),
      ),
    );
  }
}

/// حبّة حالة بنغمة — العنصر الأكثر تكراراً في التطبيق بعد البلاطة
/// (٦٣ نسخة يدويّة عبر المودالات).
///
/// التوقيع يأخذ [AppTone] لا `Color` **عمداً**: تمرير لون مفرد هو ما
/// كان يدفع كلّ موضع لاشتقاق خلفيّته بـ`.withValues(alpha:)` — وهو
/// الاشتقاق الذي ينهار في الوضع الداكن لأنّ التوكن الأساس ينقلب
/// اتّجاهاً. بحصر المدخل في النغمة يستحيل الاشتقاق الخام.
class ToneChip extends StatelessWidget {
  const ToneChip({
    super.key,
    required this.label,
    this.tone = AppTone.neutral,
    this.icon,
    this.dense = false,
    this.onTap,
  });

  final String label;
  final AppTone tone;
  final IconData? icon;

  /// حبّة أضيق للصفوف المزدحمة.
  final bool dense;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final body = Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? Sp.sm : 11,
        vertical: dense ? 3 : 5,
      ),
      decoration: BoxDecoration(
        color: tone.softBg,
        borderRadius: BorderRadius.circular(R.pill),
        border: Border.all(color: tone.softBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: dense ? 11 : 13, color: tone.fill),
            const SizedBox(width: Sp.xs),
          ],
          Text(
            label,
            style: AppType.pillLabel(color: tone.onSoft)
                .copyWith(letterSpacing: 0),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
    if (onTap == null) return body;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(R.pill),
      child: body,
    );
  }
}

/// حقل الملاحظة/السبب — يتكرّر في اثنين وثلاثين مودلاً بنفس الشكل:
/// أيقونة وصف + نصّ حرّ اختياري بلا حدود داخليّة.
class SheetNoteField extends StatelessWidget {
  const SheetNoteField({
    super.key,
    required this.controller,
    required this.hint,
    this.maxLength = 120,
    this.minLines = 1,
    this.maxLines = 3,
    this.enabled = true,
    this.icon = Icons.notes_rounded,
  });

  final TextEditingController controller;
  final String hint;
  final int maxLength;
  final int minLines;
  final int maxLines;
  final bool enabled;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return SheetBox(
      icon: icon,
      alignTop: minLines > 1,
      child: TextField(
        controller: controller,
        enabled: enabled,
        minLines: minLines,
        maxLines: maxLines,
        maxLength: maxLength,
        style: AppType.input(),
        decoration: InputDecoration(
          isDense: true,
          counterText: '',
          border: InputBorder.none,
          contentPadding: EdgeInsets.zero,
          hintText: hint,
          hintStyle: AppType.input(color: AppColors.textPlaceholder),
        ),
      ),
    );
  }
}

/// حقل البحث داخل الشيتات والشاشات — خمس عشرة نسخة يدويّة، كلٌّ
/// بنصف قطر وحشوة مختلفة.
class SheetSearchField extends StatelessWidget {
  const SheetSearchField({
    super.key,
    required this.controller,
    required this.hint,
    this.onChanged,
    this.autofocus = false,
  });

  final TextEditingController controller;
  final String hint;
  final ValueChanged<String>? onChanged;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) => SheetBox(
        icon: Icons.search_rounded,
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 4),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                autofocus: autofocus,
                onChanged: onChanged,
                style: AppType.input(),
                decoration: InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  hintText: hint,
                  hintStyle: AppType.input(color: AppColors.textPlaceholder),
                ),
              ),
            ),
            if (value.text.isNotEmpty)
              InkWell(
                onTap: () {
                  controller.clear();
                  onChanged?.call('');
                },
                borderRadius: BorderRadius.circular(R.pill),
                child: Icon(Icons.close_rounded,
                    size: 17, color: AppColors.textHint),
              ),
          ],
        ),
      ),
    );
  }
}

/// صفّ مفتاح داخل مجموعة — تسمية وسطر شرح اختياري ومفتاح في الطرف.
class SheetSwitchRow extends StatelessWidget {
  const SheetSwitchRow({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.footnote,
    this.icon,
    this.enabled = true,
  });

  final String label;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final String? footnote;
  final IconData? icon;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Sp.sm),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 18, color: AppColors.textHint),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label, style: AppType.rowValue()),
                if ((footnote ?? '').isNotEmpty) ...[
                  const SizedBox(height: Sp.xxs),
                  Text(footnote!, style: AppType.muted()),
                ],
              ],
            ),
          ),
          const SizedBox(width: Sp.sm),
          Switch(
            value: value,
            onChanged: enabled ? onChanged : null,
            activeThumbColor: AppColors.onBrand,
            activeTrackColor: AppColors.brand,
          ),
        ],
      ),
    );
  }
}

/// حاوية بيضاء تجمع عدّة [SheetSwitchRow] بخطوط شعريّة — امتداد
/// [SheetRowsGroup] لصفوف تحمل ودجتاً لا نصّاً.
class SheetSwitchGroup extends StatelessWidget {
  const SheetSwitchGroup({super.key, required this.rows});
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.lg),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) Divider(height: 1, color: AppColors.divider),
            rows[i],
          ],
        ],
      ),
    );
  }
}
