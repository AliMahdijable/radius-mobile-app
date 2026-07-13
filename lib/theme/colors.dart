import 'package:flutter/material.dart';

/// Brand palette — agreed with user 2026-06-02:
/// - Background: Material off-white #FAFAFA (NOT cream/milky — user
///   prefers world-standard backgrounds).
/// - Brand: forest green #2D5F47 (premium, natural).
/// - Logo: render AS-IS, no color blending — preserves the geometric
///   detail of the company mark.
///
/// Dark mode (added 2026-06-13): theme-dependent surfaces/text flip
/// based on a global `_isDark` flag. The flag is updated from
/// `ThemeService` before each `MaterialApp` rebuild. Brand + error
/// colors stay the same in both modes so they can still be declared
/// `const`. Surfaces/borders/text are `static Color get` instead of
/// `static const Color` — any callsite that wrapped them in a
/// `const` constructor (e.g. `const BorderSide(color: AppColors.border)`)
/// had to be relaxed to a non-const constructor.
class AppColors {
  AppColors._();

  static bool _isDark = false;

  /// Called from `main.dart` builder before each `MaterialApp` build
  /// so the getters below resolve to the right palette during paint.
  /// No-op when value hasn't changed — saves an unnecessary rebuild.
  static bool setDarkMode(bool dark) {
    if (_isDark == dark) return false;
    _isDark = dark;
    return true;
  }

  static bool get isDark => _isDark;

  // -------- Brand (same in both themes) --------
  static const Color brand = Color(0xFF2D5F47);
  static const Color brandDark = Color(0xFF1F4332);
  static const Color brandLight = Color(0xFF4A8B6E);

  // -------- Status (same in both themes) --------
  static const Color error = Color(0xFFDC2626);

  // -------- Light palette --------
  static const Color _lightBg = Color(0xFFFAFAFA);
  static const Color _lightSurface = Color(0xFFFFFFFF);
  static const Color _lightSurfaceInput = Color(0xFFF1F3F5);
  static const Color _lightBorder = Color(0xFFE5E7EB);
  static const Color _lightBorderStrong = Color(0xFFD1D5DB);
  static const Color _lightTextHi = Color(0xFF111827);
  static const Color _lightTextMid = Color(0xFF6B7280);
  static const Color _lightTextLow = Color(0xFF9CA3AF);

  // -------- Dark palette --------
  // 2026-07-13: كل الـmid/low خُفّت جداً — النصوص الفرعية على الكرت
  // (باقة/هاتف/انتهاء) غير مقروءة. رفعنا mid إلى #D3D7DE
  // و low إلى #9AA1AE ليتوفر contrast AA + هرم بصري واضح مع hi.
  static const Color _darkBg = Color(0xFF0F1419);
  static const Color _darkSurface = Color(0xFF1B2130);
  static const Color _darkSurfaceInput = Color(0xFF262D3C);
  static const Color _darkBorder = Color(0xFF323A4A);
  static const Color _darkBorderStrong = Color(0xFF454F63);
  static const Color _darkTextHi = Color(0xFFF3F4F6);
  static const Color _darkTextMid = Color(0xFFD3D7DE);
  static const Color _darkTextLow = Color(0xFF9AA1AE);

  // -------- Theme-aware getters --------
  static Color get bg => _isDark ? _darkBg : _lightBg;
  static Color get surface => _isDark ? _darkSurface : _lightSurface;
  static Color get surfaceInput =>
      _isDark ? _darkSurfaceInput : _lightSurfaceInput;
  static Color get border => _isDark ? _darkBorder : _lightBorder;
  static Color get borderStrong =>
      _isDark ? _darkBorderStrong : _lightBorderStrong;
  static Color get textHi => _isDark ? _darkTextHi : _lightTextHi;
  static Color get textMid => _isDark ? _darkTextMid : _lightTextMid;
  static Color get textLow => _isDark ? _darkTextLow : _lightTextLow;
}
