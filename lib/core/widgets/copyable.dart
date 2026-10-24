import 'dart:async';

import 'package:flutter/material.dart';

import '../../theme/colors.dart';
import '../platform/app_platform.dart';
import '../../theme/spacing.dart';
import '../util/clipboard_helper.dart';

/// معلومةٌ تُنسخ: تسميتها كما تظهر، وقيمتها كما تُلصق.
///
/// مصدرٌ واحد للطريقين: النسخ المفرد (ضغطٌ مطوّل على [Copyable]) والنسخ
/// الكلّيّ («نسخ كلّ المعلومات» = [copyFieldsText]) — فلا تختلف تسميةٌ ولا
/// قيمةٌ بين ما يُنسخ وحده وما يُنسخ مع غيره.
@immutable
class CopyField {
  const CopyField(this.label, this.value, {String? noun}) : _noun = noun;

  /// التسمية في سطر «التسمية: القيمة».
  final String label;

  /// النصّ كما يُلصق.
  final String value;

  final String? _noun;

  /// ما يُقال بعد «تمّ نسخ» — حين لا تستقيم التسمية هناك: «تابع إلى» سطرٌ
  /// سليم، و«تمّ نسخ تابع إلى» ليست عربيّة؛ فاسمها في الإشعار «اسم المدير».
  String get noun => _noun ?? label;

  /// قيمةٌ لا معنى لنسخها: فارغةٌ أو شرطة «لا قيمة» التي ترسمها الشاشة.
  bool get isBlank => isBlankCopyValue(value);

  @override
  bool operator ==(Object other) =>
      other is CopyField && other.label == label && other.value == value;

  @override
  int get hashCode => Object.hash(label, value);

  @override
  String toString() => '$label: $value';
}

/// الشرطة التي ترسمها الشاشات مكان القيمة الغائبة («—») ليست قيمة.
bool isBlankCopyValue(String? value) {
  final v = value?.trim() ?? '';
  return v.isEmpty || v == '—' || v == '-';
}

/// سطر «التسمية: القيمة» لكلّ معلومةٍ ذات قيمة، بترتيبها.
String copyFieldsText(Iterable<CopyField> fields) => [
      for (final f in fields)
        if (!f.isBlank) '${f.label}: ${f.value.trim()}',
    ].join('\n');

/// يجعل [child] قابلاً للنسخ بالضغط المطوّل — لكلّ معلومةٍ في كارت المشترك.
///
/// الضغط المطوّل لا النقر: أغلب القيم قابلةٌ للنقر أصلاً لغرضٍ آخر (الرقم
/// يتّصل، والعنوان يفتح الجهاز)، والضغط المطوّل لا يزاحم أيّاً منها — يربح
/// المطوّل بعد مهلته، والنقر القصير يبقى لصاحبه. والسحب للتمرير يُلغيه.
///
/// الأثر: اهتزازةٌ + إشعار «تمّ نسخ …» فوق كلّ شيء ([copyToClipboard]) +
/// وميضٌ خفيفٌ على المعلومة نفسها، فيرى المدير **أيّ** معلومةٍ نُسخت حين
/// تتجاور عشر معلوماتٍ قابلةٍ للنسخ.
///
/// قيمةٌ فارغة (أو «—») ⇒ [child] كما هو، بلا لمسٍ ولا وميض.
class Copyable extends StatefulWidget {
  const Copyable({
    super.key,
    required this.label,
    required this.value,
    required this.child,
    this.noun,
    this.onBrandSurface = false,
    this.radius = R.sm,
  });

  /// من [CopyField] — التسمية والقيمة واسم الإشعار معاً.
  Copyable.field(
    CopyField field, {
    Key? key,
    required Widget child,
    bool onBrandSurface = false,
    double radius = R.sm,
  }) : this(
          key: key,
          label: field.label,
          value: field.value,
          noun: field.noun,
          onBrandSurface: onBrandSurface,
          radius: radius,
          child: child,
        );

  final String label;
  final String? value;
  final Widget child;

  /// ما يُقال بعد «تمّ نسخ» — انظر [CopyField.noun].
  final String? noun;

  /// فوق بطاقة الهويّة الخضراء الداكنة: الوميض أبيض شفّاف لا أخضر.
  final bool onBrandSurface;

  /// زوايا الوميض — بلاطةٌ مدوّرة تمرّر زواياها كي لا يبرز عنها.
  final double radius;

  @override
  State<Copyable> createState() => _CopyableState();
}

class _CopyableState extends State<Copyable> {
  bool _flash = false;
  Timer? _flashOff;

  @override
  void dispose() {
    _flashOff?.cancel();
    super.dispose();
  }

  void _copy() {
    final value = widget.value!.trim();
    setState(() => _flash = true);
    _flashOff?.cancel();
    _flashOff = Timer(const Duration(milliseconds: 450), () {
      if (mounted) setState(() => _flash = false);
    });
    copyToClipboard(context, value, label: widget.noun ?? widget.label);
  }

  @override
  Widget build(BuildContext context) {
    // ⚠️ البنية واحدةٌ فارغةً كانت القيمة أم لا — الفارغة بلا مستمعٍ وحسب:
    // قيمةٌ تمتلئ بعد وصولها («—» ثمّ رقم الترافيك) لا تهدم ما تحتها
    // وتبنيه من جديد.
    final blank = isBlankCopyValue(widget.value);
    final tint = widget.onBrandSurface
        ? AppColors.onBrand.withValues(alpha: 0.16)
        : AppColors.brand.withValues(alpha: AppColors.isDark ? 0.22 : 0.10);
    // الحاسبة (ويندوز/ماك): الضغط المطوّل بالفأرة غير مألوف — النقر بالزرّ الأيمن ينسخ أيضاً، وتلميحٌ عند
    // الوقوف يقوله (المالك ٢٤ أكتوبر: «اجعلهن قابلات للنسخ»). التلميح ثابتٌ على الحاسبة فارغةً كانت القيمة أم
    // لا، كي لا تتغيّر البنية حين تمتلئ.
    final desktop = AppPlatform.isDesktop;
    final box = GestureDetector(
      // الصندوق كلّه هدفٌ لا حروف النصّ وحدها — الفراغ بين كلمتين جزءٌ
      // من المعلومة نفسها.
      behavior: blank ? HitTestBehavior.deferToChild : HitTestBehavior.opaque,
      onLongPress: blank ? null : _copy,
      onSecondaryTap: blank || !desktop ? null : _copy,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        // فوق المعلومة لا خلفها: كثيرٌ منها بلاطاتٌ ملوّنة تحجب أيّ خلفيّة.
        foregroundDecoration: BoxDecoration(
          color: _flash ? tint : tint.withValues(alpha: 0),
          borderRadius: BorderRadius.circular(widget.radius),
        ),
        child: widget.child,
      ),
    );
    return Semantics(
      onLongPressHint: blank ? null : 'نسخ ${widget.noun ?? widget.label}',
      child: desktop
          ? Tooltip(
              message: 'انقر بالزرّ الأيمن للنسخ',
              waitDuration: const Duration(milliseconds: 800),
              excludeFromSemantics: true,
              child: box,
            )
          : box,
    );
  }
}
