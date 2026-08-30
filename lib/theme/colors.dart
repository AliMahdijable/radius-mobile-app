import 'package:flutter/material.dart';

/// نظام الألوان — مشتقّ من مخطّط إعادة تصميم شاشتَي المشتركين (2026-08-29).
///
/// ── ما الذي تغيّر عن اللوحة السابقة ─────────────────────────────────
/// اللوحة القديمة كانت أخضر `#2D5F47` فوق رماديّات مائلة للأزرق
/// (hue 210-220 من طيف Tailwind). اللوحة الجديدة **أخضر-محايد بالكامل**:
/// كلّ رماديّاتها مائلة للأخضر/الزيتوني (hue 80-150)، وأخضرها درجتان
/// لا واحدة:
///   • `brand` #103D2E  = Brand Fill  — تعبئة الأزرار الأساسيّة، البطاقة
///     الداكنة، الشريحة المفعّلة، FAB، التبويب النشط. (12.15:1 مع الأبيض)
///   • `brandLight` #16624A = Brand Accent — أيقونات الكروت، الروابط،
///     قيم النجاح، أزرار المال الإيجابيّة. (7.29:1 مع الأبيض)
///
/// ── العائلات الدلاليّة ──────────────────────────────────────────────
/// كلّ عائلة (نجاح/تحذير/خطر/براند) مفكوكة إلى أربع رتب صريحة:
///   fill · softBg · softBorder · onSoft
/// وهذا بالضبط ما جعل اشتقاق الوضع الداكن ممكناً بلا إعادة تصميم.
///
/// ── الوضع الداكن ────────────────────────────────────────────────────
/// المخطّط فاتح فقط، لكنّه يحمل نظام dark مصغّراً داخله: بطاقة الهويّة
/// الخضراء #103D2E مع طبقات `white .09/.14/.16` للارتفاع و`white
/// .5/.6/.65/.8` لسلّم النصّ. عُمّم المنطق نفسه على الشاشة كلّها، وانتقلت
/// الأسطح الداكنة من hue أزرق (#0F1419) إلى hue أخضر (#0E1512) لتطابق
/// شخصيّة الفاتح. كلّ تباين أدناه محسوب: نصوص الجسم ≥ 4.5:1 وتعبئات
/// الأزرار ≥ 5:1 مع الأبيض و≥ 3:1 مع السطح خلفها.
///
/// ── الأسماء المحفوظة ───────────────────────────────────────────────
/// `brand` `brandDark` `brandLight` `error` `bg` `surface` `surfaceInput`
/// `border` `borderStrong` `textHi` `textMid` `textLow` — كلّها باقية
/// بأسمائها (2,500+ استدعاء في lib/) وتغيّرت قيمها فقط. التوكنات الجديدة
/// إضافة صرفة لا تكسر أيّ callsite.
class AppColors {
  AppColors._();

  static bool _isDark = false;

  /// تُنادى من `main.dart` قبل كل بناء لـ`MaterialApp` حتى تُحلّ الـgetters
  /// أدناه على اللوحة الصحيحة أثناء الرسم. لا تفعل شيئاً إن لم تتغيّر القيمة.
  static bool setDarkMode(bool dark) {
    if (_isDark == dark) return false;
    _isDark = dark;
    return true;
  }

  static bool get isDark => _isDark;

  // ══════════════════ البراند ══════════════════
  // fill الداكن يذوب في الخلفيّة الداكنة (1.41:1) فيُرفع في dark إلى
  // #1E7A5B — أبيض عليه 5.26:1 وفصله عن السطح 3.26:1.
  static const Color _lightBrand = Color(0xFF103D2E);
  static const Color _darkBrand = Color(0xFF1E7A5B);
  static Color get brand => _isDark ? _darkBrand : _lightBrand;

  /// سطح البطاقة الداكنة الكبيرة — بطاقة الهويّة وبطاقة الباقة وبطاقة
  /// كشف الحساب وبانر النتيجة الداكن.
  ///
  /// ⚠️ **ثابت في الوضعين عمداً**، ولهذا وُجد أصلاً: `brand` يخدم دورين
  /// متعارضين. كتعبئة زرّ يجب أن **يفتح** في الوضع الداكن ليبرز عن السطح
  /// (#103D2E عليه 1.41:1 — يذوب)، وكسطح بطاقة كبيرة يجب أن **يبقى
  /// داكناً** لأنّ كلّ طبقات `onBrand*` معايرة عليه. القياس يحسم:
  /// الأبيض على #103D2E = 12.15:1 وعلى #1E7A5B = 5.26:1، و
  /// `onBrandSecondary` ينزل من 5.41 إلى 2.95 (دون 3:1). فصل الدورين
  /// يعيد البطاقة إلى معايرتها ويُبقي الزرّ بارزاً.
  static const Color brandSurface = Color(0xFF103D2E);

  static const Color _lightBrandDark = Color(0xFF0C2E23);
  static const Color _darkBrandDark = Color(0xFF14563F);
  static Color get brandDark => _isDark ? _darkBrandDark : _lightBrandDark;

  /// Brand Accent — الدور تغيّر: لم يعد «أخضر أفتح للزينة» بل لون
  /// الأيقونات والروابط وقيم النجاح وأزرار المال الإيجابيّة.
  static const Color _lightBrandAccent = Color(0xFF16624A);
  static const Color _darkBrandAccent = Color(0xFF5BC494);
  static Color get brandLight => _isDark ? _darkBrandAccent : _lightBrandAccent;
  static Color get brandAccent => brandLight;

  /// طبقات البراند الناعمة — أيقونة رأس الـsheet 40×40، حبّة «متصل»،
  /// زرّ الفرز النشط، الشريحة المختارة الفاتحة.
  static Color get brandSoftBg =>
      _isDark ? const Color(0xFF16302A) : const Color(0xFFEAF2EE);
  static Color get brandSoftBorder =>
      _isDark ? const Color(0xFF22483C) : const Color(0xFFCDDFD6);
  static Color get brandOnSoft =>
      _isDark ? const Color(0xFF7FD9AE) : const Color(0xFF103D2E);

  // ══════════════════ النجاح ══════════════════
  // النجاح يتداخل عمداً مع brandAccent — الأخضر نفسه.
  static Color get success =>
      _isDark ? const Color(0xFF3FB37F) : const Color(0xFF16624A);
  static Color get successFill =>
      _isDark ? const Color(0xFF1E7A5B) : const Color(0xFF16624A);

  /// ⚠️ عُمّقت 2026-08-30: #F2F7F4 كانت بتباين 1.08 عن الأبيض — أي
  /// شبه بيضاء، فبدا مربّع الحالة «غير ملوّن» بينما نظائره ملوّنة.
  static Color get successSoftBg =>
      _isDark ? const Color(0xFF152B25) : const Color(0xFFE6F4EC);
  static Color get successSoftBorder =>
      _isDark ? const Color(0xFF22483C) : const Color(0xFFDFEBE5);

  /// النقطة الحيّة 6×6 داخل حبّة «متصل منذ…».
  static Color get successDot =>
      _isDark ? const Color(0xFF4FD69B) : const Color(0xFF2E9E6B);

  // ══════════════════ التحذير ══════════════════
  // ذهبي داكن لا أصفر مشرق. الـfill ينجو في الوضعين بلا تعديل:
  // أبيض عليه 5.02:1 وفصله عن السطح الداكن 3.42:1.
  static Color get warning =>
      _isDark ? const Color(0xFFE0B457) : const Color(0xFF97650B);
  static const Color warningFill = Color(0xFF97650B);
  static Color get warningSoftBg =>
      _isDark ? const Color(0xFF33280F) : const Color(0xFFF8EFDD);
  static Color get warningSoftBorder =>
      _isDark ? const Color(0xFF4D3D18) : const Color(0xFFF0E1C4);
  static Color get warningOnSoft =>
      _isDark ? const Color(0xFFE0B457) : const Color(0xFF7A5A0C);

  // ══════════════════ الخطر ══════════════════
  // أعمق وأدفأ من #DC2626 السابق.
  static const Color _lightError = Color(0xFFB02A22);
  static const Color _darkError = Color(0xFFF0837A);
  static Color get error => _isDark ? _darkError : _lightError;

  /// تعبئة زرّ الخطر — تختلف عن `error` في الوضع الداكن لأنّ النصّ
  /// الفاتح يحتاج تعبئة أغمق (#C8382F: أبيض 5.17:1).
  static Color get errorFill =>
      _isDark ? const Color(0xFFC8382F) : const Color(0xFFB02A22);
  static Color get dangerSoftBg =>
      _isDark ? const Color(0xFF3A1F1D) : const Color(0xFFFBEBE9);
  static Color get dangerSoftBorder =>
      _isDark ? const Color(0xFF4E2B27) : const Color(0xFFF6DDDA);

  /// نصّ صغير داخل البانر الأحمر — أغمق من الـfill عمداً (7.45:1).
  static Color get dangerOnSoft =>
      _isDark ? const Color(0xFFF0837A) : const Color(0xFF8E2E27);

  /// حدّ الكارت الأبيض ذي الدلالة الخطرة (كارت الدين، زرّ الحذف الشبحي).
  static Color get dangerBorderCard =>
      _isDark ? const Color(0xFF43302D) : const Color(0xFFF0DEDC);

  // ══════════════════ الأسطح ══════════════════
  // سلّم رباعي: خلفيّة الشاشة → سطح الكارت → سطح الـsheet → سطح غاطس.
  static const Color _lightBg = Color(0xFFF4F5F2);
  static const Color _darkBg = Color(0xFF0E1512);
  static Color get bg => _isDark ? _darkBg : _lightBg;

  static const Color _lightSurface = Color(0xFFFFFFFF);
  static const Color _darkSurface = Color(0xFF161D19);
  static Color get surface => _isDark ? _darkSurface : _lightSurface;

  /// سطح الـbottom sheet — أفتح من الشاشة وأدفأ من الأبيض.
  static Color get surfaceSheet =>
      _isDark ? const Color(0xFF1B231F) : const Color(0xFFFBFBF9);

  /// السطح الغاطس داخل الكارت — بلاطات تحميل/رفع/IP والإشارة/SNR/CCQ.
  /// هو نفسه `surfaceInput` (الاسم القديم محفوظ، 93 استدعاء).
  static const Color _lightSunken = Color(0xFFF7F8F5);
  static const Color _darkSunken = Color(0xFF202A25);
  static Color get surfaceInput => _isDark ? _darkSunken : _lightSunken;
  static Color get surfaceSunken => surfaceInput;

  /// خلفيّة العنصر المعطّل بالكامل.
  static Color get surfaceDisabled =>
      _isDark ? const Color(0xFF1E2622) : const Color(0xFFEFF1ED);

  // ══════════════════ الحدود والفواصل ══════════════════
  // أربع رتب مفصولة بالدور — اللوحة السابقة كان فيها اثنتان.
  static const Color _lightBorder = Color(0xFFE7E9E5);
  static const Color _darkBorder = Color(0xFF2A3630);
  static Color get border => _isDark ? _darkBorder : _lightBorder;

  static const Color _lightBorderStrong = Color(0xFFCDD2CC);
  static const Color _darkBorderStrong = Color(0xFF3A4A42);
  static Color get borderStrong =>
      _isDark ? _darkBorderStrong : _lightBorderStrong;

  /// فاصل شعري بين صفوف المعلومات داخل الكارت الواحد.
  static Color get divider =>
      _isDark ? const Color(0xFF232E29) : const Color(0xFFF0F1EE);

  /// فاصل بنيوي — رأس الـsheet عن جسمه، وجسمه عن شريط الأزرار.
  static Color get dividerStrong =>
      _isDark ? const Color(0xFF26312C) : const Color(0xFFEFF1ED);

  /// حدّ العناصر التفاعليّة الفاتحة (شريط البحث، الشريحة غير المختارة).
  static Color get borderSoft =>
      _isDark ? const Color(0xFF283330) : const Color(0xFFE4E7E2);

  /// مقبض السحب في الـsheet (42×4) والنقطة الفاصلة بين الباقة والسعر.
  static Color get grabber =>
      _isDark ? const Color(0xFF3A4A42) : const Color(0xFFDCE0DA);

  // ══════════════════ النصوص ══════════════════
  // اللوحة السابقة كانت ثلاث درجات؛ المخطّط يحتاج ستّاً. الأسماء
  // القديمة الثلاثة محفوظة وأُضيفت ثلاث حولها.
  static const Color _lightTextHi = Color(0xFF121614);
  static const Color _darkTextHi = Color(0xFFF0F3F0);
  static Color get textHi => _isDark ? _darkTextHi : _lightTextHi;

  /// نصّ الجسم — أثقل من `textMid`: تسميات بلاطات الإجراءات، نصّ
  /// الشريحة غير المختارة، نصّ الـcheckbox. (9.72:1 على أبيض)
  static Color get textBody =>
      _isDark ? const Color(0xFFCBD3CE) : const Color(0xFF3E4642);

  // #6E766F رسب بـ4.28:1 على `bg` (المطلوب 4.5). عُتّم بأربع درجات
  // فحافظ على الـhue وبلغ 4.60. **هذه الرتبة تبقى معتّمة** — إنّها
  // آخر رتبة تحمل معلومة تُقرأ، فتخضع لـAA بلا تفاوض.
  static const Color _lightTextMid = Color(0xFF69716A);
  static const Color _darkTextMid = Color(0xFFA9B3AD);
  static Color get textMid => _isDark ? _darkTextMid : _lightTextMid;

  /// تسمية الحقل — «طريقة الدفع»، «الدين الحالي»، الجهة اليمنى من
  /// صفوف المعلومات. مقصود أن يكون خافتاً؛ لا تستعمله لنصّ يُقرأ طويلاً.
  /// ⚠️ 2026-08-30: أُعيدت إلى قيمة المخطّط بعد ملاحظة المستخدم أنّ
  /// الواجهة «صارت غامقة». التعتيم السابق (#7A827C) كان لبلوغ 3:1 على
  /// `bg`، وكلفته أنّ كلّ تسمية وعدّاد وتاريخ ثانوي صار أثقل بصريّاً
  /// بنحو 40%. راجع رأس `palette_contrast_test.dart` للمقايضة كاملةً.
  static Color get textLabel =>
      _isDark ? const Color(0xFF9BA5A0) : const Color(0xFF8A928C);

  static const Color _lightTextLow = Color(0xFF909892);
  static const Color _darkTextLow = Color(0xFF8B958F);
  static Color get textLow => _isDark ? _darkTextLow : _lightTextLow;

  /// أيقونات الحقول الساكنة ونصوص المساعدة الصغرى.
  static Color get textHint =>
      _isDark ? const Color(0xFF7C867F) : const Color(0xFF969D97);

  /// نصّ الحقل الفارغ فقط.
  static Color get textPlaceholder =>
      _isDark ? const Color(0xFF5C6660) : const Color(0xFFC5CAC4);

  // ══════════════════ فوق البراند (on-brand) ══════════════════
  // طبقات ثابتة في الوضعين — سطحها داكن أصلاً. لذلك بطاقة الهويّة
  // وبطاقة كشف الحساب وبطاقة التجديد لا تحتاج أيّ تعديل في dark mode.
  static const Color onBrand = Color(0xFFFFFFFF);

  /// كلّ الرتب أدناه معايرة على `brandSurface` (#103D2E) لا على `brand`،
  /// ولذلك تصحّ كـ`const`: سطحها ثابت في الوضعين. القياسات فوقه:
  /// الأبيض 12.15 · fill1 9.34 · fill2 7.99 · secondary 5.41 · tertiary 4.27.
  static const Color onBrandSecondary = Color(0x99FFFFFF); // .60
  static const Color onBrandTertiary = Color(0x80FFFFFF); // .50
  static const Color onBrandStrong = Color(0xCCFFFFFF); // .80
  static const Color onBrandFill1 = Color(0x17FFFFFF); // .09 — سطح مرتفع
  static const Color onBrandFill2 = Color(0x24FFFFFF); // .14 — حبّة/فاصل
  static const Color onBrandFill3 = Color(0x29FFFFFF); // .16 — فاصل أدقّ
  static const Color onBrandMint = Color(0xFF6EE7A8); // نقطة حيّة + واتساب
  static const Color onBrandDanger = Color(0xFFFFC9C3); // قيمة الدين

  // ══════════════════ الطبقة المعتّمة ══════════════════
  // مبنيّة على #121614 لا على أسود صافٍ — `Colors.black.withOpacity`
  // لن تطابقها. على الداكن تُرفع إلى .62 وإلّا ضاع الفصل.
  static Color get scrim =>
      _isDark ? const Color(0x9E121614) : const Color(0x6B121614);

  /// اللون **الوحيد خارج عائلات اللوحة** — محجوز لحالة واحدة بعينها:
  /// مشترك **منتهي لكنّه لا يزال متصلاً**. هذه حالة شاذّة منطقيّاً
  /// (اشتراكه انتهى والشبكة لم تفصله) وليست درجة من درجات النجاح أو
  /// التحذير أو الخطر، فلا تصحّ في أي عائلة.
  ///
  /// أُعيد بعد بلاغ 2026-08-29: توحيد الألوان الأوّلي ابتلعه في
  /// `brandAccent` فضاعت الحالة من رمز الحالة في القائمة.
  /// القيمتان مُختارتان بقياس ΔE76 لا بالذوق: يجب أن تفترق عن `info`
  /// و`warning` — الحالتين الأخريين اللتين تشاركانها **نفس الأيقونة**
  /// (wifi)، فاللون هو القناة الوحيدة بينها. القياس:
  /// نهاراً ΔE↔info 57.8 و↔warning 128.0 · ليلاً 60.3 و120.3.
  /// (المحاولة الأولى #B79BF5 رسبت بـΔE=19 عن `info` الليلي.)
  static Color get anomaly =>
      _isDark ? const Color(0xFFC86BF5) : const Color(0xFF5B21B6);
  static Color get anomalySoftBg =>
      _isDark ? const Color(0xFF311F45) : const Color(0xFFF1ECFB);

  /// اللون الأزرق الوحيد في المخطّط (قيمة «رفع» فقط) — بلا عائلة.
  static Color get info =>
      _isDark ? const Color(0xFF8FAEE8) : const Color(0xFF3F5C99);

  /// خلفيّة `info` الناعمة. لم تكن موجودة، فكان مربّع حالة «متصل»
  /// يستعمل `brandSoftBg` الخضراء تحت أيقونة زرقاء — تناقض لاحظه
  /// المستخدم فوراً: «المتصل ملوّن فقط إشارة الواي فاي لا المربّع».
  static Color get infoSoftBg =>
      _isDark ? const Color(0xFF1C2733) : const Color(0xFFE8EEF9);
  static Color get infoSoftBorder =>
      _isDark ? const Color(0xFF2B3A4E) : const Color(0xFFCFDCF0);
}

/// النغمة الدلاليّة — رباعيّة `fill · softBg · softBorder · onSoft`
/// تُمرَّر ككيان واحد بدل تمرير `Color` مفرد.
///
/// لماذا: النمط الغالب في التطبيق كان تمرير لون واحد ثمّ اشتقاق
/// خلفيّته بـ`color.withValues(alpha: .1)` وحدّه بـ`.3`. هذا **ينهار
/// ليلاً** لسببين: الاشتقاق بالشفافيّة لا يورث وعي الوضع، وبعض التوكنات
/// تنقلب اتّجاهاً (`error` يفتح من #B02A22 إلى #F0837A فتصير خلفيّته
/// الشفّافة ضباباً وردياً بدل عتمة حمراء).
///
/// تمرير `AppTone` بدل `Color` يجعل الأربعة تأتي من اللوحة معاً، فتصحّ
/// في الوضعين بلا اشتقاق.
enum AppTone {
  brand,
  success,
  warning,
  danger,
  info,

  /// الحالة الشاذّة: «منتهي لكنّه متصل» — لا تنتمي لأي عائلة.
  anomaly,
  neutral;

  /// اللون الصلب — الأيقونة والقيمة والتعبئة.
  Color get fill => switch (this) {
        AppTone.brand => AppColors.brandAccent,
        AppTone.success => AppColors.success,
        AppTone.warning => AppColors.warningFill,
        AppTone.danger => AppColors.error,
        AppTone.info => AppColors.info,
        AppTone.anomaly => AppColors.anomaly,
        AppTone.neutral => AppColors.textMid,
      };

  /// خلفيّة الحبّة/المربّع الخفيفة.
  Color get softBg => switch (this) {
        AppTone.brand => AppColors.brandSoftBg,
        AppTone.success => AppColors.successSoftBg,
        AppTone.warning => AppColors.warningSoftBg,
        AppTone.danger => AppColors.dangerSoftBg,
        AppTone.info => AppColors.infoSoftBg,
        AppTone.anomaly => AppColors.anomalySoftBg,
        AppTone.neutral => AppColors.surfaceSunken,
      };

  /// حدّ الحبّة/الكارت الخفيف.
  Color get softBorder => switch (this) {
        AppTone.brand => AppColors.brandSoftBorder,
        AppTone.success => AppColors.successSoftBorder,
        AppTone.warning => AppColors.warningSoftBorder,
        AppTone.danger => AppColors.dangerSoftBorder,
        AppTone.info => AppColors.infoSoftBorder,
        AppTone.anomaly => AppColors.anomalySoftBg,
        AppTone.neutral => AppColors.border,
      };

  /// النصّ فوق `softBg` — أغمق من `fill` ليبلغ 4.5:1.
  Color get onSoft => switch (this) {
        AppTone.brand => AppColors.brandOnSoft,
        AppTone.success => AppColors.brandOnSoft,
        AppTone.warning => AppColors.warningOnSoft,
        AppTone.danger => AppColors.dangerOnSoft,
        AppTone.info => AppColors.info,
        AppTone.anomaly => AppColors.anomaly,
        AppTone.neutral => AppColors.textBody,
      };
}
