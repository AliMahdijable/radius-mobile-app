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
  static Color get successSoftBg =>
      _isDark ? const Color(0xFF152B25) : const Color(0xFFF2F7F4);
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
      _isDark ? const Color(0xFF33280F) : const Color(0xFFFBF4E8);
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
      _isDark ? const Color(0xFF351D1B) : const Color(0xFFFDF2F1);
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

  static const Color _lightTextMid = Color(0xFF6E766F);
  static const Color _darkTextMid = Color(0xFFA9B3AD);
  static Color get textMid => _isDark ? _darkTextMid : _lightTextMid;

  /// تسمية الحقل — «طريقة الدفع»، «الدين الحالي»، الجهة اليمنى من
  /// صفوف المعلومات. مقصود أن يكون خافتاً؛ لا تستعمله لنصّ يُقرأ طويلاً.
  static Color get textLabel =>
      _isDark ? const Color(0xFF9BA5A0) : const Color(0xFF8A928C);

  static const Color _lightTextLow = Color(0xFF9AA29C);
  static const Color _darkTextLow = Color(0xFF8B958F);
  static Color get textLow => _isDark ? _darkTextLow : _lightTextLow;

  /// أيقونات الحقول الساكنة ونصوص المساعدة الصغرى.
  static Color get textHint =>
      _isDark ? const Color(0xFF7C867F) : const Color(0xFFA2A9A3);

  /// نصّ الحقل الفارغ فقط.
  static Color get textPlaceholder =>
      _isDark ? const Color(0xFF5C6660) : const Color(0xFFC5CAC4);

  // ══════════════════ فوق البراند (on-brand) ══════════════════
  // طبقات ثابتة في الوضعين — سطحها داكن أصلاً. لذلك بطاقة الهويّة
  // وبطاقة كشف الحساب وبطاقة التجديد لا تحتاج أيّ تعديل في dark mode.
  static const Color onBrand = Color(0xFFFFFFFF);
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

  /// اللون الأزرق الوحيد في المخطّط (قيمة «رفع» فقط) — بلا عائلة.
  static Color get info =>
      _isDark ? const Color(0xFF8FAEE8) : const Color(0xFF3F5C99);
}
