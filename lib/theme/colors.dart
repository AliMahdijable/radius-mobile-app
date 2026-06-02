import 'package:flutter/material.dart';

/// Brand palette — agreed with user 2026-06-02:
/// - Soft pastel + premium aesthetic.
/// - Single brand: forest green #2D5F47 (premium, natural).
/// - Warm cream background — not navy.
class AppColors {
  AppColors._();

  // Brand
  static const Color brand = Color(0xFF2D5F47);
  static const Color brandDark = Color(0xFF1F4332);
  static const Color brandLight = Color(0xFF4A8B6E);

  // Light surfaces (default mode for now)
  static const Color bg = Color(0xFFF5EFE5);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceInput = Color(0xFFF9F5ED);
  static const Color border = Color(0xFFE8DFCF);
  static const Color borderStrong = Color(0xFFD7CCB7);

  // Text
  static const Color textHi = Color(0xFF1A1F1B);
  static const Color textMid = Color(0xFF6B7363);
  static const Color textLow = Color(0xFF9CA095);

  // Status (used very rarely on login)
  static const Color error = Color(0xFFC44A3D);
}
