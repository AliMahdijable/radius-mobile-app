import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/util/bidi.dart';
import '../services/active_company.dart';
import '../theme/colors.dart';
import '../theme/typography.dart';

/// «من خلال أيّ شركة أنا داخل؟» بسطرٍ واحد مدمج:
/// `[🏢] ايرث لنك · موظّف لدى admin@najaf40`
///
/// حلّ محلّ شريط الشركة الممتدّ أعلى كلّ التبويبات — طلب المستخدم
/// ٢٠٢٦-١٠-١٢: «ما يحتاج تاخذ مساحة من أعلى، كون تدرجه جوّة الاسم أو جنبه».
/// فصار سطراً تحت اسم المدير في ترويسة الرئيسيّة، ومقدّمةً لسطر العدد في رأس
/// المشتركين (حيث يفعّل المدير ويمدّد — فيرى الشركة قبل أن يضغط).
///
/// ⚠️ سطرٌ واحد دائماً (`maxLines: 1` + «…»): الترويسة محسوبة الارتفاع،
/// والتفافُ سطرٍ ثانٍ يُقصّ. والشركة **أوّلاً** عمداً: حين يضيق العرض يتنازل
/// ما بعدها (اليوزر يُختصر أو يسقط، والعدد يُبتر آخره) لا اسمها. والنصّ
/// الكامل في الدلالات.
///
/// كلّ مقطعٍ معزولٌ اتّجاهيّاً ([iso]): اسمٌ عربيّ بجانب يوزرٍ لاتينيّ يتفكّك
/// ترتيبه بلا عزل.
class ActiveCompanyLine extends StatelessWidget {
  const ActiveCompanyLine({
    super.key,
    required this.info,
    this.showWho = true,
    this.omitUsername,
    this.trailing,
    this.fontSize = 12,
  });

  final ActiveCompanyInfo info;

  /// بعد الشركة: «موظّف لدى <الأب>» للموظّف، ويوزر الدخول للمدير.
  final bool showWho;

  /// الاسم المعروض فوق السطر — إن طابق يوزر المدير لا يُكرَّر تحته.
  final String? omitUsername;

  /// نصٌّ يُلحق بعد الشركة (عدّاد المشتركين في رأس قائمتهم).
  final String? trailing;

  final double fontSize;

  /// المقطع بعد الشركة بلا علامات عزل — للدلالات.
  String get _whoPlain {
    if (!showWho) return '';
    final user = info.shownUsername;
    if (info.isEmployee) return user.isEmpty ? 'موظّف' : 'موظّف لدى $user';
    final shown = omitUsername?.trim().toLowerCase() ?? '';
    return user.toLowerCase() == shown ? '' : user;
  }

  TextStyle get _detail => AppType.body(color: AppColors.textMid)
      .copyWith(fontSize: fontSize, height: 1.35);

  /// نصوص السطر بلا الأيقونة — تُقاس وتُرسم بالأنماط نفسها.
  List<InlineSpan> _texts(String who, String tail) {
    final sep = TextSpan(
      text: ' · ',
      style: AppType.body(color: AppColors.textLow)
          .copyWith(fontSize: fontSize, height: 1.35),
    );
    return [
      TextSpan(
        text: iso(info.shortLabel),
        style: AppType.label(color: AppColors.textBody)
            .copyWith(fontSize: fontSize),
      ),
      if (who.isNotEmpty) ...[sep, TextSpan(text: who, style: _detail)],
      if (tail.isNotEmpty) ...[sep, TextSpan(text: tail, style: _detail)],
    ];
  }

  Widget _line(String who, String tail) => Text.rich(
        TextSpan(children: [
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Padding(
              padding: const EdgeInsetsDirectional.only(end: _iconGap),
              child: Icon(
                Icons.apartment_rounded,
                size: fontSize + 1,
                color: AppColors.brandAccent,
              ),
            ),
          ),
          ..._texts(who, tail),
        ]),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );

  static const double _iconGap = 4;

  /// أقصى تصغيرٍ يُقبل بدل بتر اليوزر: ما يُرجع الخطّ المكبَّر إلى حجمه
  /// الأصليّ لا أصغر (سلّم 1.2 ← حتّى 1.2)، ولا أقلّ من 8٪ (شاشة ٣٢٠ بسلّم 1).
  /// ما زاد على ذلك يُبتر بـ«…».
  static double _maxShrink(TextScaler s) => math.max(1.08, s.scale(1));

  /// عرض السطر كاملاً بلا قيد. الأيقونة تُحسب بحجمها المكبَّر مع الخطّ
  /// (`WidgetSpan` يتبع سلّم النصّ).
  double _width(BuildContext context, String who, String tail) {
    final scaler = MediaQuery.textScalerOf(context);
    final tp = TextPainter(
      text: TextSpan(children: _texts(who, tail)),
      textDirection: Directionality.of(context),
      textScaler: scaler,
      maxLines: 1,
    )..layout();
    final width = tp.width + scaler.scale(fontSize + 1 + _iconGap);
    tp.dispose();
    return width;
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final whoPlain = _whoPlain;
    final user = info.shownUsername;
    final employeeOf = info.isEmployee && showWho && user.isNotEmpty;
    final who = whoPlain.isEmpty
        ? ''
        : employeeOf
            ? 'موظّف لدى ${iso(user)}'
            : iso(whoPlain);
    final tail = trailing?.trim() ?? '';
    return Semantics(
      container: true,
      excludeSemantics: true,
      label: [
        'الشركة المفتوحة: ${info.label}',
        if (whoPlain.isNotEmpty) whoPlain,
        if (tail.isNotEmpty) tail,
      ].join('، '),
      // يوزرٌ مبتور («…admin@n») لا يقول شيئاً، فإن ضاق السطر (خطٌّ مكبَّر،
      // شاشة ٣٢٠، أو ثلاث أيقونات بجانبه):
      //   ① تجاوزٌ طفيف: يصغر السطر قليلاً ولا يُبتر ([_maxShrink])؛
      //   ② الموظّف: «لدى X» بدل «موظّف لدى X» — يوزر المدير الأب أهمّ من
      //      الكلمة — ثمّ ① عليه؛
      //   ③ وإلّا الشركة وحدها — هي غاية السطر، والكامل في الدلالات.
      // والعدّاد الملحق (رأس المشتركين) يُبتر آخره عمداً — لا تكييف له.
      child: who.isEmpty || tail.isNotEmpty
          ? _line(who, tail)
          : LayoutBuilder(
              builder: (context, c) {
                if (!c.hasBoundedWidth) return _line(who, tail);
                final shrink = _maxShrink(MediaQuery.textScalerOf(context));
                for (final shown in [
                  who,
                  if (employeeOf) 'لدى ${iso(user)}',
                ]) {
                  final need = _width(context, shown, tail);
                  if (need <= c.maxWidth) return _line(shown, tail);
                  if (need <= c.maxWidth * shrink) {
                    return FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: AlignmentDirectional.centerStart,
                      child: _line(shown, tail),
                    );
                  }
                }
                return _line('', tail);
              },
            ),
    );
  }
}
