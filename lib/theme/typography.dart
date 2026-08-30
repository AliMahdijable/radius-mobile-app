import 'package:flutter/material.dart';

import 'colors.dart';

/// سلّم الخطّ — IBM Plex Sans Arabic، بقياسات مخطّط إعادة التصميم.
///
/// الخطّ مُضمَّن في `assets/fonts/` بأربعة أوزان ساكنة (400/500/600/700)
/// — لا يُنشر كـvariable، والسلّم لا يستعمل غيرها. لا `google_fonts`
/// وقت التشغيل: التضمين يوفّر 200-500ms على الإقلاع البارد ويمنع
/// وميض تبديل الخطّ.
///
/// ── فخّان نُقلا من مراجعة المخطّط ────────────────────────────────────
/// 1. **ارتفاع السطر**: المخطّط لا يصرّح بـ`line-height` إلّا مرّة واحدة،
///    فيرث ~1.5 من المتصفّح. صندوق الخطّ في Flutter أطول، والنقل
///    الحرفي بلا `height` صريح يُنتج تباعداً مختلفاً كليّاً. لذلك كلّ
///    style أدناه يصرّح بـ`height`: ~1.15 للأرقام الكبيرة · 1.2 للأزرار
///    · 1.3 للعناوين · 1.4-1.45 للجسم.
/// 2. **العرض**: القياسات أدناه عُوير معظمها على عرض Cairo (الخطّ
///    السابق) وهو أعرض من هذا. الاتجاه آمن — نصّ أضيق لا يُفيض صفّاً
///    كان يتّسع له — لكنّ التوسيط قد يبدو مختلفاً في الصفوف الضيّقة.
///
/// ── الأوزان ─────────────────────────────────────────────────────────
/// المخطّط لا يعرف w400 إطلاقاً: w500 (الخافت) · w600 (السائد) ·
/// w700 (القيم البارزة والعناوين). لذلك `subtitle()` و`muted()`
/// رُفعا من w400 إلى w500.
class AppType {
  AppType._();

  /// اسم عائلة الخطّ — **المصدر الوحيد** في التطبيق.
  ///
  /// 2026-08-30: Cairo → IBM Plex Sans Arabic بطلب المستخدم. كان
  /// الاسم مكتوباً حرفيّاً في 110 مواضع خارج هذا الملفّ، فأيّ تبديل
  /// كان يتطلّب مروراً على كلّها ويترك ما يفوته بخطّ قديم صامتاً.
  /// الآن التبديل سطر واحد هنا، وCairo ما يزال مسجَّلاً في pubspec
  /// فالرجوع بلا تنزيل.
  ///
  /// ⚠️ IBM Plex Sans Arabic **أضيق من Cairo**. القياسات في هذا
  /// الملفّ عُوير معظمها على عرض Cairo، والاتجاه آمن (نصّ أضيق لا
  /// يُفيض صفّاً كان يتّسع له) لكنّ التوسيط قد يبدو مختلفاً قليلاً.
  static const family = 'IBMPlexSansArabic';

  static TextStyle _s({
    required double size,
    required FontWeight weight,
    required double height,
    Color? color,
    double? letterSpacing,
  }) =>
      TextStyle(
        fontFamily: family,
        fontSize: size,
        fontWeight: weight,
        height: height,
        letterSpacing: letterSpacing,
        color: color,
      );

  // ══════════════ الأسماء القائمة (750+ استدعاء) ══════════════

  /// عنوان الشاشة — «المشتركون». (22/700، ls −0.01em في المخطّط)
  static TextStyle title({Color? color}) => _s(
        size: 22,
        weight: FontWeight.w700,
        height: 1.3,
        letterSpacing: -0.22,
        color: color ?? AppColors.textHi,
      );

  static TextStyle subtitle({Color? color}) => _s(
        size: 13,
        weight: FontWeight.w500,
        height: 1.45,
        color: color ?? AppColors.textMid,
      );

  /// تسمية المجموعة فوق الحقل — أكثر تسمية تكراراً في المخطّط (45×).
  static TextStyle label({Color? color}) => _s(
        size: 11.5,
        weight: FontWeight.w600,
        height: 1.35,
        color: color ?? AppColors.textLabel,
      );

  /// قيمة الحقل ونصّ الإدخال. (15px صار محجوزاً للأزرار)
  static TextStyle input({Color? color}) => _s(
        size: 13.5,
        weight: FontWeight.w600,
        height: 1.4,
        color: color ?? AppColors.textHi,
      );

  /// نصّ الزرّ — ثابت لكلّ زرّ height:50 في المخطّط.
  static TextStyle button({Color? color}) => _s(
        size: 15,
        weight: FontWeight.w600,
        height: 1.2,
        color: color ?? AppColors.textHi,
      );

  static TextStyle link({Color? color}) => _s(
        size: 13,
        weight: FontWeight.w500,
        height: 1.35,
        color: color ?? AppColors.brandAccent,
      );

  static TextStyle muted({Color? color}) => _s(
        size: 11,
        weight: FontWeight.w500,
        height: 1.35,
        color: color ?? AppColors.textLow,
      );

  // ══════════════ إضافات المخطّط ══════════════

  /// نصّ الجسم القياسي — المقاس الأكثر استعمالاً في المخطّط (67×):
  /// صفوف المعلومات، الشرائح، بانرات النتيجة، نصّ الـcheckbox.
  static TextStyle body({Color? color}) => _s(
        size: 12.5,
        weight: FontWeight.w500,
        height: 1.4,
        color: color ?? AppColors.textBody,
      );

  static TextStyle bodyStrong({Color? color}) => _s(
        size: 12.5,
        weight: FontWeight.w600,
        height: 1.4,
        color: color ?? AppColors.textBody,
      );

  /// عنوان الـbottom sheet.
  static TextStyle sheetTitle({Color? color}) => _s(
        size: 17,
        weight: FontWeight.w700,
        height: 1.3,
        color: color ?? AppColors.textHi,
      );

  /// عنوان الكارت — «معلومات الاتصال»، «معلومات الجهاز».
  static TextStyle cardTitle({Color? color}) => _s(
        size: 14,
        weight: FontWeight.w600,
        height: 1.3,
        color: color ?? AppColors.textHi,
      );

  /// اسم المشترك في صفّ القائمة.
  static TextStyle listName({Color? color}) => _s(
        size: 15.5,
        weight: FontWeight.w600,
        height: 1.3,
        color: color ?? AppColors.textHi,
      );

  /// اسم المشترك في بطاقة الهويّة الداكنة.
  static TextStyle heroName({Color? color}) => _s(
        size: 20,
        weight: FontWeight.w700,
        height: 1.25,
        letterSpacing: -0.2,
        color: color ?? AppColors.onBrand,
      );

  /// قيمة صفّ المعلومة.
  static TextStyle rowValue({Color? color}) => _s(
        size: 13.5,
        weight: FontWeight.w600,
        height: 1.35,
        color: color ?? AppColors.textHi,
      );

  /// القيمة البارزة داخل شبكة الإحصاءات الثلاثيّة.
  static TextStyle statValue({Color? color}) => _s(
        size: 17,
        weight: FontWeight.w700,
        height: 1.2,
        color: color ?? AppColors.textHi,
      );

  /// مبلغ الإدخال الكبير في مودالات المال، و«الرصيد له».
  static TextStyle amount({Color? color}) => _s(
        size: 24,
        weight: FontWeight.w700,
        height: 1.15,
        color: color ?? AppColors.textHi,
      );

  /// رقم الأيّام المتبقّية في بلاطة القائمة — الوحيد المصرَّح بـlh 1.1.
  static TextStyle daysNumber({Color? color}) => _s(
        size: 19,
        weight: FontWeight.w700,
        height: 1.1,
        color: color,
      );

  /// الكلمة تحت رقم الأيّام («أيام متبقية») بشفافيّة 0.8 في المخطّط.
  static TextStyle daysWord({Color? color}) => _s(
        size: 9.5,
        weight: FontWeight.w600,
        height: 1.2,
        color: color,
      );

  /// تسمية البلاطة الدقيقة — SNR / CCQ / RX Power / تبويب سفلي.
  static TextStyle micro({Color? color}) => _s(
        size: 10.5,
        weight: FontWeight.w500,
        height: 1.3,
        color: color ?? AppColors.textLabel,
      );

  /// تسمية الحبّة وعناوين مجموعات الشرائح.
  static TextStyle pillLabel({Color? color}) => _s(
        size: 11,
        weight: FontWeight.w600,
        height: 1.25,
        letterSpacing: 0.22,
        color: color ?? AppColors.textLow,
      );

  /// نقاط كلمة السرّ — بلا `letterSpacing` تلتصق النقاط ببعضها.
  static TextStyle password({Color? color}) => _s(
        size: 13,
        weight: FontWeight.w600,
        height: 1.35,
        letterSpacing: 2.7,
        color: color ?? AppColors.textHi,
      );

  // ══════════════ الرتبة العريضة (w700 على المقاسات الصغيرة) ══════════════
  //
  // مسح 2026-08-30 وجد 196 نمطاً خاماً بوزن w700 على مقاسات 9.5-13،
  // كلّها عناوين أقسام وحالات فارغة وقيم لوحات. السلّم لم يكن يعرّف
  // هذه الرتبة فبقيت خارجه — لا لأنّها خطأ، بل لأنّ المخطّط الأصلي
  // لم يصل إلى هذه الشاشات. تعريفها هنا يُدخل 196 موقعاً تحت السلّم
  // بلا تغيير بكسل واحد.
  //
  // ⚠️ بلا `letterSpacing` عمداً، خلافاً لنظيراتها الخفيفة
  // (`micro` و`pillLabel` بـ0.22): التتبّع وسيلة إبراز للأوزان
  // الخفيفة عند المقاسات الصغيرة، والوزن العريض يؤدّي الدور نفسه.
  // جمعهما إبرازٌ مضاعف يُنهك السطر — وفي الشاشات المزدحمة كلوحات
  // الأجهزة يزيد العرض أيضاً فيُفيض الصفوف الضيّقة.

  /// عنوان قسم داخل شيت · عنوان حالة فارغة. (12.5/700)
  static TextStyle bodyBold({Color? color}) => _s(
        size: 12.5,
        weight: FontWeight.w700,
        height: 1.4,
        color: color ?? AppColors.textHi,
      );

  /// تسمية قيمة في لوحة مراقبة — أصغر ما يُقرأ مُبرَزاً. (10.5/700)
  static TextStyle microBold({Color? color}) => _s(
        size: 10.5,
        weight: FontWeight.w700,
        height: 1.3,
        color: color ?? AppColors.textLabel,
      );

  /// نصّ حبّة أو شارة حالة مُبرَزة. (11/700)
  static TextStyle pillBold({Color? color}) => _s(
        size: 11,
        weight: FontWeight.w700,
        height: 1.25,
        color: color ?? AppColors.textLow,
      );

  /// أصغر تسمية مُبرَزة — وحدات وزوائد الأرقام. (9.5/700)
  static TextStyle daysWordBold({Color? color}) => _s(
        size: 9.5,
        weight: FontWeight.w700,
        height: 1.2,
        color: color ?? AppColors.textLabel,
      );

  /// عنوان صفّ أو مفتاح بارز في قائمة. (13/700)
  static TextStyle rowLabelBold({Color? color}) => _s(
        size: 13,
        weight: FontWeight.w700,
        height: 1.35,
        color: color ?? AppColors.textHi,
      );

  /// عنوان بطاقة مُبرَز. (14/700)
  static TextStyle cardTitleBold({Color? color}) => _s(
        size: 14,
        weight: FontWeight.w700,
        height: 1.3,
        color: color ?? AppColors.textHi,
      );

  /// زرّ أو إجراء مُبرَز. (15/700)
  static TextStyle buttonBold({Color? color}) => _s(
        size: 15,
        weight: FontWeight.w700,
        height: 1.2,
        color: color ?? AppColors.textHi,
      );

  /// تسمية مُبرَزة بمقاس الحقول الصغيرة. (11.5/700)
  static TextStyle labelBold({Color? color}) => _s(
        size: 11.5,
        weight: FontWeight.w700,
        height: 1.35,
        color: color ?? AppColors.textLabel,
      );
}
