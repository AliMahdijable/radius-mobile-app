import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';

/// اختصار الآلاف في حقول المال — طلب المستخدم 2026-08-29:
/// «من يكتب 25 الحقل يتحوّل إلى 25000».
///
/// ── القاعدة ─────────────────────────────────────────────────────────
/// قيمة بين 1 و999 تُضرب في 1000. ما فوقها يمرّ كما هو، فكتابة 25000
/// تبقى 25000 لا 25 مليوناً.
///
/// ── لماذا 1000 عتبةً ───────────────────────────────────────────────
/// في هذا التطبيق لا وجود لمبلغ حقيقي دون الألف: أرخص باقة 30,000،
/// وأصغر شريحة دين 5,000، وأدنى خصم 1,000. فالرقم المكوّن من ثلاث خانات
/// أو أقلّ هو دائماً اختصار لا مبلغ.
///
/// ⚠️ المقابل: لا يمكن إدخال 500 دينار بالضبط — تصير 500,000. هذا مقصود
/// ومقبول في النطاق أعلاه؛ لو ظهرت حاجة لمبالغ صغيرة فعليّة، مرّر
/// `shorthand: false` للحقل المعنيّ وحده.
///
/// ── متى يقع التحويل ────────────────────────────────────────────────
/// **عند خروج المؤشّر من الحقل** (أو الضغط على «تمّ»)، لا مع كل ضغطة
/// مفتاح. التحويل مع كل ضغطة كان سيكسر الإدخال الطويل: كتابة «2» تصير
/// فوراً 2,000 فلا يبقى للرقم التالي موضع. وقبل الخروج يظهر تلميح
/// «سيُحفظ 25,000» تحت الحقل، فلا مفاجأة ولا سحر خفيّ.
class AmountShorthand {
  AmountShorthand._();

  /// أدنى قيمة تُعتبر مبلغاً حقيقيّاً لا اختصاراً.
  static const int threshold = 1000;
  static const int multiplier = 1000;

  /// `25 → 25000` · `999 → 999000` · `1000 → 1000` · `0 → 0`.
  static int expand(int raw) {
    if (raw <= 0 || raw >= threshold) return raw;
    return raw * multiplier;
  }

  /// هل ستُطبَّق القاعدة على هذه القيمة؟ يستعمله التلميح.
  static bool applies(int raw) => raw > 0 && raw < threshold;

  /// فواصل الآلاف. تُرجع '' للصفر حتى يظهر الـhint بدل «0».
  static String format(int v) {
    if (v == 0) return '';
    final s = v.toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return buf.toString();
  }

  /// يقرأ القيمة الرقميّة من نصّ الحقل مهما احتوى فواصل.
  static int parse(String text) =>
      int.tryParse(text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
}

/// حقل المال الموحّد — يجمع في مكان واحد ما كان مكرّراً في ثمانية شيتات:
/// تنسيق الآلاف الحيّ · حارس إعادة الدخول (`_suppressFormat`) · زرّ
/// المسح · وحدة العملة · واختصار الآلاف الجديد.
class AmountTextField extends StatefulWidget {
  const AmountTextField({
    super.key,
    required this.controller,
    required this.onValue,
    this.enabled = true,
    this.autofocus = false,
    this.shorthand = true,
    this.hint = '0',
    this.currency = 'د.ع',
    this.focusNode,
  });

  final TextEditingController controller;

  /// يُنادى بالقيمة الرقميّة بعد كل تغيير — بما فيه التوسيع عند الخروج.
  final ValueChanged<int> onValue;
  final bool enabled;
  final bool autofocus;

  /// `false` يعطّل اختصار الآلاف لهذا الحقل وحده.
  final bool shorthand;
  final String hint;
  final String currency;
  final FocusNode? focusNode;

  @override
  State<AmountTextField> createState() => _AmountTextFieldState();
}

class _AmountTextFieldState extends State<AmountTextField> {
  late final FocusNode _focus = widget.focusNode ?? FocusNode();
  bool _ownsFocus = false;
  bool _suppress = false;
  int _value = 0;

  @override
  void initState() {
    super.initState();
    _ownsFocus = widget.focusNode == null;
    _value = AmountShorthand.parse(widget.controller.text);
    widget.controller.addListener(_onText);
    _focus.addListener(_onFocus);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onText);
    _focus.removeListener(_onFocus);
    if (_ownsFocus) _focus.dispose();
    super.dispose();
  }

  void _onText() {
    if (_suppress) return;
    final parsed = AmountShorthand.parse(widget.controller.text);
    final formatted = AmountShorthand.format(parsed);
    if (formatted != widget.controller.text) {
      _suppress = true;
      widget.controller.value = TextEditingValue(
        text: formatted,
        selection: TextSelection.collapsed(offset: formatted.length),
      );
      _suppress = false;
    }
    if (parsed != _value) {
      setState(() => _value = parsed);
      widget.onValue(parsed);
    }
  }

  void _onFocus() {
    if (_focus.hasFocus) return;
    _applyShorthand();
  }

  /// التوسيع عند الخروج. يُستدعى أيضاً من `onSubmitted` حتى يعمل
  /// زرّ «تمّ» في لوحة المفاتيح بلا انتظار فقد التركيز.
  void _applyShorthand() {
    if (!widget.shorthand) return;
    if (!AmountShorthand.applies(_value)) return;
    _setValue(AmountShorthand.expand(_value));
  }

  void _setValue(int v) {
    final formatted = AmountShorthand.format(v);
    _suppress = true;
    widget.controller.value = TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
    _suppress = false;
    setState(() => _value = v);
    widget.onValue(v);
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final willExpand = widget.shorthand && AmountShorthand.applies(_value);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Expanded(
              child: TextField(
                controller: widget.controller,
                focusNode: _focus,
                enabled: widget.enabled,
                autofocus: widget.autofocus,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _applyShorthand(),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9,]')),
                ],
                textDirection: TextDirection.ltr,
                textAlign: TextAlign.right,
                style: AppType.amount(),
                decoration: InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                  hintText: widget.hint,
                  hintStyle: AppType.amount(color: AppColors.textPlaceholder),
                ),
              ),
            ),
            const SizedBox(width: Sp.sm),
            Text(widget.currency,
                style: AppType.input(color: AppColors.textLabel)
                    .copyWith(fontSize: 13)),
            if (_value > 0 && widget.enabled) ...[
              const SizedBox(width: Sp.sm),
              InkWell(
                onTap: () {
                  _suppress = true;
                  widget.controller.clear();
                  _suppress = false;
                  setState(() => _value = 0);
                  widget.onValue(0);
                },
                borderRadius: BorderRadius.circular(R.pill),
                child: Icon(Icons.close_rounded,
                    size: 16, color: AppColors.textHint),
              ),
            ],
          ],
        ),
        // التلميح يسبق التحويل فلا يكون مفاجأة.
        if (willExpand) ...[
          const SizedBox(height: Sp.x6),
          Row(
            children: [
              Icon(Icons.auto_awesome_rounded,
                  size: 13, color: AppColors.brandAccent),
              const SizedBox(width: Sp.xs),
              Text(
                'سيُحفظ ${AmountShorthand.format(AmountShorthand.expand(_value))}'
                ' ${widget.currency}',
                style: AppType.muted(color: AppColors.brandOnSoft),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// غلاف يضيف اختصار الآلاف إلى حقل مبلغ **قائم** بتخطيطه الخاص، دون
/// استبداله بـ[AmountTextField].
///
/// يعمل بـ`Focus` مُحيط: حين يخرج التركيز من الشجرة الفرعيّة (أي من
/// الحقل بداخلها) يُوسَّع المحتوى إن كان اختصاراً. لا يحتاج `FocusNode`
/// في الـState المضيف ولا يمسّ الـlisteners القائمة.
///
/// يُستعمل في شيتات الصرفيّات والمدراء والعمليّات الجماعيّة حيث لكلّ
/// حقل تخطيط ومنطق مختلفان.
class AmountShorthandBox extends StatelessWidget {
  const AmountShorthandBox({
    super.key,
    required this.controller,
    required this.child,
    this.onExpanded,
    this.enabled = true,
  });

  final TextEditingController controller;
  final Widget child;

  /// يُنادى بالقيمة بعد التوسيع — لتحديث حالة الشاشة المضيفة.
  final ValueChanged<int>? onExpanded;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (hasFocus) {
        if (hasFocus || !enabled) return;
        final raw = AmountShorthand.parse(controller.text);
        if (!AmountShorthand.applies(raw)) return;
        final expanded = AmountShorthand.expand(raw);
        final text = AmountShorthand.format(expanded);
        controller.value = TextEditingValue(
          text: text,
          selection: TextSelection.collapsed(offset: text.length),
        );
        onExpanded?.call(expanded);
      },
      child: child,
    );
  }
}
