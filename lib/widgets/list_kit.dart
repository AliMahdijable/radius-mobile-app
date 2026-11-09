import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/util/amount_input.dart';
import '../core/widgets/app_sheet.dart';
import '../core/widgets/design_sheet.dart';
import '../theme/colors.dart';
import '../theme/spacing.dart';
import '../theme/typography.dart';

/// قطع «قوائم العمل» بتصميمها الجديد (٩ نوفمبر — المالك: «بشده ركز ع تصميم التبيليغات وخصومات المشتركين واسعار المشتركين حسن
/// تصميمهم بحترافيه لان القائمة الوحيده تصميمها بالهاتف مزعج ورديئ»). مشتركةٌ بين الشاشات الثلاث كي تتشابه:
///   • بطاقات أرقامٍ ملوّنة بحدٍّ وأيقونةٍ في مربّعٍ ملوّن (ذوق المالك) — تُلمس لتصفّي القائمة.
///   • بحثٌ وشرائح تصفيةٍ بعدّها.
///   • صفٌّ واحد لكلّ مشترك (لا شبكة كرتاتٍ صغيرة) — دائرة تحديدٍ كبيرة، الاسم ثمّ اليوزر والباقة، والمبلغ في الطرف.
///   • شريط تحديدٍ سفليّ بأفعال الشاشة، والمبلغ في ورقةٍ من الأسفل.

/// عائلة اللون الدلاليّة — اللون مع الأيقونة والكلمة دائماً.
enum ListTone { brand, success, warning, danger, info }

extension ListToneColors on ListTone {
  Color get fg => switch (this) {
        ListTone.brand => AppColors.brand,
        ListTone.success => AppColors.success,
        ListTone.warning => AppColors.warning,
        ListTone.danger => AppColors.error,
        ListTone.info => AppColors.info,
      };
  Color get soft => switch (this) {
        ListTone.brand => AppColors.brandSoftBg,
        ListTone.success => AppColors.successSoftBg,
        ListTone.warning => AppColors.warningSoftBg,
        ListTone.danger => AppColors.dangerSoftBg,
        ListTone.info => AppColors.infoSoftBg,
      };
  Color get softBorder => switch (this) {
        ListTone.brand => AppColors.brandSoftBorder,
        ListTone.success => AppColors.successSoftBorder,
        ListTone.warning => AppColors.warningSoftBorder,
        ListTone.danger => AppColors.dangerSoftBorder,
        ListTone.info => AppColors.infoSoftBorder,
      };
}

/// مربّع أيقونةٍ ملوّن.
class ListIconBox extends StatelessWidget {
  const ListIconBox({super.key, required this.icon, required this.tone, this.size = 34});
  final IconData icon;
  final ListTone tone;
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

/// بطاقة رقم: أيقونة ملوّنة + الرقم + الاسم، وشريطٌ جانبيّ بلونها؛ تُلمس (إن مُرّر onTap) لتصفّي القائمة.
class ListKpiTile extends StatelessWidget {
  const ListKpiTile({
    super.key,
    required this.icon,
    required this.tone,
    required this.label,
    required this.value,
    this.unit,
    this.onTap,
    this.active = false,
  });
  final IconData icon;
  final ListTone tone;
  final String label;
  final String value;
  final String? unit;
  final VoidCallback? onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final radius = BorderRadius.circular(R.lg);
    return Material(
      color: active ? tone.soft : AppColors.surface,
      borderRadius: radius,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: Container(
          padding: const EdgeInsetsDirectional.fromSTEB(Sp.md, Sp.md, Sp.md, Sp.md),
          decoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(color: active ? tone.softBorder : AppColors.border, width: active ? BW.selected : BW.normal),
          ),
          child: Row(
            children: [
              ListIconBox(icon: icon, tone: tone),
              const SizedBox(width: Sp.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: AlignmentDirectional.centerStart,
                      child: Text.rich(
                        TextSpan(children: [
                          TextSpan(text: value, style: AppType.statValue(color: active ? tone.fg : AppColors.textHi)),
                          if (unit != null) TextSpan(text: ' $unit', style: AppType.micro(color: AppColors.textMid)),
                        ]),
                        maxLines: 1,
                      ),
                    ),
                    const SizedBox(height: 2),
                    // يصغر قليلاً على ٣٢٠ بدل أن يُقصّ («مجموع الخصو…»)
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(label, maxLines: 1, style: AppType.micro(color: AppColors.textMid)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// حقل البحث بأيقونته وزرّ المسح.
class ListSearchField extends StatelessWidget {
  const ListSearchField({super.key, required this.controller, required this.hint, this.onChanged});
  final TextEditingController controller;
  final String hint;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(R.md),
      borderSide: BorderSide(color: AppColors.border),
    );
    return SizedBox(
      height: H.search,
      child: ValueListenableBuilder<TextEditingValue>(
        valueListenable: controller,
        builder: (_, v, __) => TextField(
          controller: controller,
          onChanged: onChanged,
          textInputAction: TextInputAction.search,
          style: AppType.input(color: AppColors.textHi),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: AppType.input(color: AppColors.textPlaceholder),
            prefixIcon: Icon(LucideIcons.search, size: 18, color: AppColors.textMid),
            suffixIcon: v.text.isEmpty
                ? null
                : IconButton(
                    tooltip: 'مسح البحث',
                    icon: Icon(LucideIcons.x, size: 16, color: AppColors.textMid),
                    onPressed: () {
                      controller.clear();
                      onChanged?.call('');
                    },
                  ),
            filled: true,
            fillColor: AppColors.surface,
            contentPadding: const EdgeInsets.symmetric(horizontal: Sp.md),
            border: border,
            enabledBorder: border,
            focusedBorder: border.copyWith(borderSide: BorderSide(color: AppColors.brand, width: BW.selected)),
          ),
        ),
      ),
    );
  }
}

/// شريحة تصفية بعدّها — النشطة ملوّنة بعائلتها.
class ListFilterChip extends StatelessWidget {
  const ListFilterChip({
    super.key,
    required this.label,
    required this.active,
    required this.onTap,
    this.count,
    this.icon,
    this.tone = ListTone.brand,
    this.enabled = true,
  });
  final String label;
  final bool active;
  final VoidCallback onTap;
  final int? count;
  final IconData? icon;
  final ListTone tone;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final fg = !enabled ? AppColors.textHint : (active ? tone.fg : AppColors.textBody);
    final radius = BorderRadius.circular(R.pill);
    return Material(
      color: active ? tone.soft : AppColors.surface,
      borderRadius: radius,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: radius,
        child: Container(
          constraints: const BoxConstraints(minHeight: H.chip),
          padding: const EdgeInsets.symmetric(horizontal: Sp.md),
          decoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(color: active ? tone.softBorder : AppColors.border, width: active ? BW.selected : BW.normal),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[Icon(icon, size: 14, color: fg), const SizedBox(width: Sp.xs)],
              Text(label, style: AppType.labelBold(color: fg)),
              if (count != null) ...[
                const SizedBox(width: Sp.x6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: active ? AppColors.surface : AppColors.surfaceSunken,
                    borderRadius: radius,
                  ),
                  child: Text('$count', style: AppType.pillBold(color: fg)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// دائرة التحديد في طرف الصفّ — كبيرةٌ تُلمس بسهولة.
class ListSelectDot extends StatelessWidget {
  const ListSelectDot({super.key, required this.selected});
  final bool selected;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? AppColors.brand : AppColors.surface,
        border: Border.all(color: selected ? AppColors.brand : AppColors.borderStrong, width: 2),
      ),
      child: selected ? const Icon(LucideIcons.check, size: 14, color: AppColors.onBrand) : null,
    );
  }
}

/// صفّ مشترك: [دائرة تحديد أو حرفٌ أوّل] الاسم / اليوزر · الباقة … [المبلغ وما تحته].
class ListSubscriberRow extends StatelessWidget {
  const ListSubscriberRow({
    super.key,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.selectable,
    this.trailing,
    this.onTap,
    this.subtitleLtr = false,
  });
  final String title;
  final String subtitle;
  final bool selected;
  final bool selectable;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool subtitleLtr;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final initial = title.trim().isEmpty ? '?' : title.trim().characters.first.toUpperCase();
    return Material(
      color: selected ? AppColors.brandSoftBg : AppColors.surface,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: 10),
          child: Row(
            children: [
              if (selectable)
                ListSelectDot(selected: selected)
              else
                Container(
                  width: 32,
                  height: 32,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: AppColors.surfaceSunken, shape: BoxShape.circle),
                  child: Text(initial, style: AppType.labelBold(color: AppColors.textMid)),
                ),
              const SizedBox(width: Sp.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.cardTitle(color: AppColors.textHi)),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textDirection: subtitleLtr ? TextDirection.ltr : null,
                        style: AppType.micro(color: AppColors.textMid),
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null) ...[const SizedBox(width: Sp.sm), trailing!],
            ],
          ),
        ),
      ),
    );
  }
}

/// المبلغ في طرف الصفّ وشارةٌ صغيرة تحته («−5,000» · «ثابت» · «دين قديم»…).
class ListAmountCell extends StatelessWidget {
  const ListAmountCell({super.key, required this.amount, this.badge, this.badgeTone = ListTone.success, this.amountColor});
  final String amount;
  final String? badge;
  final ListTone badgeTone;
  final Color? amountColor;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(amount, style: AppType.rowValue(color: amountColor ?? AppColors.textHi).copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
        if (badge != null) ...[
          const SizedBox(height: 3),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: badgeTone.soft,
              borderRadius: BorderRadius.circular(R.pill),
              border: Border.all(color: badgeTone.softBorder),
            ),
            child: Text(badge!, style: AppType.pillBold(color: badgeTone.fg).copyWith(fontSize: 10.5)),
          ),
        ],
      ],
    );
  }
}

/// شريط التحديد السفليّ: ✕ والعدد وأفعال الشاشة — يظهر حين يُحدَّد أحد.
class ListSelectionBar extends StatelessWidget {
  const ListSelectionBar({super.key, required this.count, required this.onClear, required this.actions, this.noun = 'محدَّد'});
  final int count;
  final VoidCallback onClear;
  final List<Widget> actions;
  final String noun;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.dividerStrong)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Sp.md, Sp.sm, Sp.md, Sp.sm),
          child: Row(
            children: [
              IconButton(
                tooltip: 'مسح التحديد',
                onPressed: onClear,
                icon: Icon(LucideIcons.x, size: 18, color: AppColors.textMid),
              ),
              Expanded(
                child: Text.rich(
                  TextSpan(children: [
                    TextSpan(text: '$count', style: AppType.statValue(color: AppColors.brand)),
                    TextSpan(text: ' $noun', style: AppType.body(color: AppColors.textMid)),
                  ]),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              for (var i = 0; i < actions.length; i++) ...[if (i > 0) const SizedBox(width: Sp.sm), actions[i]],
            ],
          ),
        ),
      ),
    );
  }
}

/// زرّ فعلٍ في شريط التحديد (٤٤ ارتفاعاً) — ممتلئ للأساسيّ، وبحدٍّ للثانويّ.
class ListBarButton extends StatelessWidget {
  const ListBarButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.tone = ListTone.brand,
    this.filled = true,
    this.busy = false,
  });
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final ListTone tone;
  final bool filled;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final live = onPressed != null && !busy;
    final bg = filled ? (live ? tone.fg : AppColors.surfaceDisabled) : AppColors.surface;
    final fg = filled ? (live ? AppColors.onBrand : AppColors.textHint) : (live ? tone.fg : AppColors.textHint);
    final radius = BorderRadius.circular(R.md);
    return Material(
      color: bg,
      borderRadius: radius,
      child: InkWell(
        onTap: live ? onPressed : null,
        borderRadius: radius,
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: Sp.md),
          decoration: filled ? null : BoxDecoration(borderRadius: radius, border: Border.all(color: live ? tone.softBorder : AppColors.border)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (busy)
                SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: fg))
              else
                Icon(icon, size: 16, color: fg),
              const SizedBox(width: Sp.x6),
              Text(label, style: AppType.buttonBold(color: fg).copyWith(fontSize: 13.5)),
            ],
          ),
        ),
      ),
    );
  }
}

/// قائمةٌ فارغة بجملةٍ تقول ما يفعل الوكيل.
class ListEmptyNote extends StatelessWidget {
  const ListEmptyNote({super.key, required this.icon, required this.title, this.hint});
  final IconData icon;
  final String title;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Sp.huge, horizontal: Sp.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListIconBox(icon: icon, tone: ListTone.brand, size: 44),
          const SizedBox(height: Sp.sm),
          Text(title, textAlign: TextAlign.center, style: AppType.cardTitle(color: AppColors.textHi)),
          if (hint != null) ...[
            const SizedBox(height: Sp.xs),
            Text(hint!, textAlign: TextAlign.center, style: AppType.micro(color: AppColors.textMid)),
          ],
        ],
      ),
    );
  }
}

/// ورقة المبلغ من الأسفل (خصمٌ أو سعرٌ ثابت لمحدَّدين): حقل المال الموحّد + شرائح سريعة + سطر معاينة ⇒ المبلغ أو null.
/// [quickAdds] تضيف إلى الحقل (كـ«+5,000» القديمة)، و[quickSets] تضعه كما هو.
Future<int?> showListAmountSheet(
  BuildContext context, {
  required String title,
  required String subtitle,
  required IconData icon,
  required String fieldLabel,
  required String confirmLabel,
  ListTone tone = ListTone.brand,
  List<int> quickAdds = const [],
  List<int> quickSets = const [],
  String Function(int amount)? previewOf,
}) {
  return showAppSheet<int>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: AppColors.scrim,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _AmountSheet(
      title: title,
      subtitle: subtitle,
      icon: icon,
      fieldLabel: fieldLabel,
      confirmLabel: confirmLabel,
      tone: tone,
      quickAdds: quickAdds,
      quickSets: quickSets,
      previewOf: previewOf,
    ),
  );
}

class _AmountSheet extends StatefulWidget {
  const _AmountSheet({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.fieldLabel,
    required this.confirmLabel,
    required this.tone,
    required this.quickAdds,
    required this.quickSets,
    required this.previewOf,
  });
  final String title;
  final String subtitle;
  final IconData icon;
  final String fieldLabel;
  final String confirmLabel;
  final ListTone tone;
  final List<int> quickAdds;
  final List<int> quickSets;
  final String Function(int amount)? previewOf;

  @override
  State<_AmountSheet> createState() => _AmountSheetState();
}

class _AmountSheetState extends State<_AmountSheet> {
  final _ctrl = TextEditingController();
  int _amount = 0;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _set(int v) {
    HapticFeedback.selectionClick();
    final f = AmountShorthand.format(v);
    _ctrl.value = TextEditingValue(text: f, selection: TextSelection.collapsed(offset: f.length));
    setState(() => _amount = v);
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final preview = _amount > 0 ? widget.previewOf?.call(_amount) : null;
    return DesignSheet(
      header: SheetHeaderBar(
        icon: widget.icon,
        title: widget.title,
        subtitle: widget.subtitle,
        tint: widget.tone.fg,
        tintBg: widget.tone.soft,
        onClose: () => Navigator.of(context).pop(),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.fieldLabel, style: AppType.labelBold(color: AppColors.textBody)),
          const SizedBox(height: Sp.sm),
          AmountTextField(controller: _ctrl, autofocus: true, onValue: (v) => setState(() => _amount = v)),
          if (widget.quickAdds.isNotEmpty || widget.quickSets.isNotEmpty) ...[
            const SizedBox(height: Sp.md),
            Wrap(
              spacing: Sp.sm,
              runSpacing: Sp.sm,
              children: [
                for (final q in widget.quickSets)
                  SheetQuickChip(label: AmountShorthand.format(q), selected: _amount == q, onTap: () => _set(q)),
                for (final q in widget.quickAdds)
                  SheetQuickChip(label: '+${AmountShorthand.format(q)}', selected: false, onTap: () => _set(_amount + q)),
              ],
            ),
          ],
          if (preview != null) ...[
            const SizedBox(height: Sp.md),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: Sp.sm),
              decoration: BoxDecoration(
                color: widget.tone.soft,
                borderRadius: BorderRadius.circular(R.md),
                border: Border.all(color: widget.tone.softBorder),
              ),
              child: Text(preview, style: AppType.body(color: AppColors.textBody)),
            ),
          ],
        ],
      ),
      footer: SheetFooterBar(
        label: _amount > 0 ? widget.confirmLabel.replaceAll('{amount}', AmountShorthand.format(_amount)) : widget.confirmLabel.replaceAll(' {amount}', ''),
        icon: widget.icon,
        color: widget.tone.fg,
        enabled: _amount > 0,
        onPressed: () => Navigator.of(context).pop(_amount),
      ),
    );
  }
}
