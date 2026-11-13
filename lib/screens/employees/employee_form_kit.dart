import 'package:flutter/material.dart';

import '../../core/util/amount_input.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';

/// قطع نموذج «حدود الموظف» و«راتب الموظف» — المالك ١٤ نوفمبر (صورة المحرّر): «تصميم تعبان مال الايرادات والنقود بالموظفين
/// حسّنه». كانت الحقول نصّاً عارياً بلا صندوق (تبدو معطّلة) وتحتها فقرةٌ رماديّة طويلة تشرح الثلاثة معاً.
///
/// الآن: كلّ قسمٍ بطاقةٌ برأسٍ (مربّع أيقونةٍ بلونه الدلاليّ + عنوان + سطر معنى)، وكلّ مبلغٍ حقلٌ بصندوقٍ ظاهر وأيقونةٍ بلونه
/// وشرحه القصير تحته هو — الدين كهرمانيّ، النقد أخضر، ربح العمليّة بلون العلامة، والراتب (الزمن) أزرق.
enum EmpTone { debt, cash, profit, time }

extension EmpToneColors on EmpTone {
  Color get fg => switch (this) {
        EmpTone.debt => AppColors.warning,
        EmpTone.cash => AppColors.success,
        EmpTone.profit => AppColors.brandOnSoft,
        EmpTone.time => AppColors.info,
      };

  Color get softBg => switch (this) {
        EmpTone.debt => AppColors.warningSoftBg,
        EmpTone.cash => AppColors.successSoftBg,
        EmpTone.profit => AppColors.brandSoftBg,
        EmpTone.time => AppColors.infoSoftBg,
      };

  Color get softBorder => switch (this) {
        EmpTone.debt => AppColors.warningSoftBorder,
        EmpTone.cash => AppColors.successSoftBorder,
        EmpTone.profit => AppColors.brandSoftBorder,
        EmpTone.time => AppColors.infoSoftBorder,
      };
}

/// مربّع أيقونةٍ بلون القسم/الحقل.
class EmpToneIcon extends StatelessWidget {
  const EmpToneIcon({super.key, required this.icon, required this.tone, this.size = 36});
  final IconData icon;
  final EmpTone tone;
  final double size;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: tone.softBg,
        borderRadius: BorderRadius.circular(size >= 32 ? R.sm : 7),
        border: Border.all(color: tone.softBorder),
      ),
      child: Icon(icon, size: size * 0.48, color: tone.fg),
    );
  }
}

/// قسمٌ في نموذج الموظف: بطاقةٌ برأسٍ ثمّ حقولها.
class EmpFormSection extends StatelessWidget {
  const EmpFormSection({
    super.key,
    required this.icon,
    required this.tone,
    required this.title,
    required this.subtitle,
    required this.child,
    this.titleKey,
  });
  final IconData icon;
  final EmpTone tone;
  final String title;
  final String subtitle;
  final Widget child;
  final Key? titleKey;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Container(
      padding: const EdgeInsets.all(Sp.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.lg),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              EmpToneIcon(icon: icon, tone: tone),
              const SizedBox(width: Sp.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, key: titleKey, style: AppType.bodyBold(color: AppColors.textHi)),
                    const SizedBox(height: 1),
                    Text(subtitle, style: AppType.micro(color: AppColors.textMid)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: Sp.md),
          child,
        ],
      ),
    );
  }
}

/// تسمية حقلٍ داخل القسم.
class EmpFieldLabel extends StatelessWidget {
  const EmpFieldLabel(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: Sp.x6),
        child: Text(text, style: AppType.label(color: AppColors.textHi).copyWith(fontWeight: FontWeight.w700)),
      );
}

/// شرح الحقل القصير تحته.
class EmpFieldHelp extends StatelessWidget {
  const EmpFieldHelp(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsetsDirectional.only(top: 5, start: 2),
        child: Text(text, style: AppType.micro(color: AppColors.textMid)),
      );
}

/// حقل مبلغٍ بصندوقٍ ظاهر: التسمية، ثمّ الصندوق (أيقونةٌ بلونه + الرقم + «د.ع»)، ثمّ شرحه. الحدّ يأخذ لون العلامة عند الكتابة.
class EmpAmountField extends StatefulWidget {
  const EmpAmountField({
    super.key,
    required this.fieldKey,
    required this.controller,
    required this.label,
    required this.hint,
    required this.help,
    required this.icon,
    required this.tone,
    required this.onValue,
    this.allowExact = false,
  });

  /// مفتاح [AmountTextField] نفسه (الاختبارات تكتب فيه به).
  final Key fieldKey;
  final TextEditingController controller;
  final String label;
  final String hint;
  final String help;
  final IconData icon;
  final EmpTone tone;
  final ValueChanged<int> onValue;
  final bool allowExact;

  @override
  State<EmpAmountField> createState() => _EmpAmountFieldState();
}

class _EmpAmountFieldState extends State<EmpAmountField> {
  final _node = FocusNode();

  @override
  void initState() {
    super.initState();
    _node.addListener(_onFocus);
  }

  void _onFocus() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _node.removeListener(_onFocus);
    _node.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        EmpFieldLabel(widget.label),
        // النقر على أيّ مكانٍ من الصندوق يكتب فيه (الحقل نفسه سطرٌ رفيع).
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _node.requestFocus,
          child: Container(
            constraints: const BoxConstraints(minHeight: H.search),
            padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: 11),
            decoration: BoxDecoration(
              color: AppColors.surfaceSunken,
              borderRadius: BorderRadius.circular(R.md),
              border: Border.all(color: _node.hasFocus ? AppColors.brand : AppColors.borderSoft),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Icon(widget.icon, size: 16, color: widget.tone.fg),
                ),
                const SizedBox(width: Sp.sm),
                Expanded(
                  child: AmountTextField(
                    key: widget.fieldKey,
                    controller: widget.controller,
                    focusNode: _node,
                    compact: true,
                    allowExact: widget.allowExact,
                    hint: widget.hint,
                    onValue: widget.onValue,
                  ),
                ),
              ],
            ),
          ),
        ),
        EmpFieldHelp(widget.help),
      ],
    );
  }
}

/// ملاحظةٌ ختاميّة للقسم بخلفيّةٍ خافتة (معادلة الكشف).
class EmpFormNote extends StatelessWidget {
  const EmpFormNote({super.key, required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: Sp.sm),
      decoration: BoxDecoration(
        color: AppColors.surfaceSunken,
        borderRadius: BorderRadius.circular(R.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, size: 14, color: AppColors.textMid),
          ),
          const SizedBox(width: Sp.sm),
          Expanded(child: Text(text, style: AppType.micro(color: AppColors.textMid))),
        ],
      ),
    );
  }
}
