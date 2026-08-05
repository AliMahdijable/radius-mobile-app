import 'package:flutter/material.dart';

import 'colors.dart';

/// Cairo مُحمَّل من assets/fonts/ محلياً (Flutter font system).
/// كنّا نستعمل google_fonts.cairo() اللي يفتح network fetch على cold
/// start (~200-500ms flash يظهر font افتراضي ثم يتبدّل). الآن الخط
/// جزء من الـAPK ويعمل offline من اللحظة الأولى.
///
/// ── v2 Type Scale (Material Design 3, Arabic-mobile tuned) ──────────
///   Hero KPI       : 22pt w800 — single biggest metric on screen
///                                (Revenue today, etc.)
///   Headline       : 18pt w800 — secondary KPIs (wallet, debt, subs
///                                total inside the ring)
///   Subhead        : 16pt w800 — in-card metric values (mini grid)
///   Section title  : 14pt w700 — 'آخر النشاطات', 'المشتركون'
///   Card title     : 12pt w600 — 'الرصيد', 'الإيرادات • اليوم'
///   Body           : 13pt w600 — activity titles, primary copy
///   Body secondary : 12pt w500 — greetings, helper text
///   Caption        : 11pt w500 — time labels, status pills, period tabs
///   Tiny label     : 10pt w700 — 'إجمالي', 'IQD' suffixes
///
/// The methods below cover the primary intent; callers override fontSize
/// for the larger headline/hero variants since those are rare.
class AppType {
  AppType._();

  // اسم الـfamily المسجّل في pubspec.yaml → assets/fonts/Cairo-*.ttf
  static const _cairo = 'Cairo';

  // 2026-07-13: كل style يستعمل AppColors.textHi/Mid/Low افتراضياً
  // حتى النصوص في dark mode تنقلب تلقائياً بلا تعديل يدوي في كل callsite.
  // الـcaller يقدر يتجاوز باللون الذي يريده.

  // Logo title
  static TextStyle title({Color? color}) => TextStyle(
        fontFamily: _cairo,
        fontSize: 22,
        fontWeight: FontWeight.w700,
        height: 1.25,
        letterSpacing: -0.3,
        color: color ?? AppColors.textHi,
      );

  static TextStyle subtitle({Color? color}) => TextStyle(
        fontFamily: _cairo,
        fontSize: 13,
        fontWeight: FontWeight.w400,
        height: 1.5,
        color: color ?? AppColors.textMid,
      );

  // Input label (above each field)
  static TextStyle label({Color? color}) => TextStyle(
        fontFamily: _cairo,
        fontSize: 12,
        fontWeight: FontWeight.w600,
        height: 1.3,
        color: color ?? AppColors.textMid,
      );

  // Input text + body
  static TextStyle input({Color? color}) => TextStyle(
        fontFamily: _cairo,
        fontSize: 15,
        fontWeight: FontWeight.w500,
        height: 1.4,
        color: color ?? AppColors.textHi,
      );

  // Button text
  static TextStyle button({Color? color}) => TextStyle(
        fontFamily: _cairo,
        fontSize: 15,
        fontWeight: FontWeight.w600,
        height: 1.2,
        color: color ?? AppColors.textHi,
      );

  // Link / tertiary text
  static TextStyle link({Color? color}) => TextStyle(
        fontFamily: _cairo,
        fontSize: 13,
        fontWeight: FontWeight.w500,
        height: 1.3,
        color: color ?? AppColors.brand,
      );

  // Footer / muted small
  static TextStyle muted({Color? color}) => TextStyle(
        fontFamily: _cairo,
        fontSize: 11,
        fontWeight: FontWeight.w400,
        height: 1.3,
        color: color ?? AppColors.textLow,
      );
}
