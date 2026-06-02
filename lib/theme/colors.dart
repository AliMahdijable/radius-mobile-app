import 'package:flutter/material.dart';

/// Brand palette — agreed with user 2026-06-02:
/// - Background: Material off-white #FAFAFA (NOT cream/milky — user
///   prefers world-standard backgrounds).
/// - Brand: forest green #2D5F47 (premium, natural).
/// - Logo: render AS-IS, no color blending — preserves the geometric
///   detail of the company mark.
class AppColors {
  AppColors._();

  // Brand
  static const Color brand = Color(0xFF2D5F47);
  static const Color brandDark = Color(0xFF1F4332);
  static const Color brandLight = Color(0xFF4A8B6E);

  // Light surfaces (Material standard, not cream)
  static const Color bg = Color(0xFFFAFAFA);         // base canvas
  static const Color surface = Color(0xFFFFFFFF);    // cards/sheets
  static const Color surfaceInput = Color(0xFFF1F3F5); // inputs
  static const Color border = Color(0xFFE5E7EB);
  static const Color borderStrong = Color(0xFFD1D5DB);

  // Text
  static const Color textHi = Color(0xFF111827);
  static const Color textMid = Color(0xFF6B7280);
  static const Color textLow = Color(0xFF9CA3AF);

  // Status
  static const Color error = Color(0xFFDC2626);
}
