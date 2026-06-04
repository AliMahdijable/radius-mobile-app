import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Cairo via google_fonts (runtime download + cache). Returns TextStyles
/// from static methods because GoogleFonts.cairo() can't be const-evaluated.
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

  // Logo title
  static TextStyle title({Color? color}) => GoogleFonts.cairo(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        height: 1.25,
        letterSpacing: -0.3,
        color: color,
      );

  static TextStyle subtitle({Color? color}) => GoogleFonts.cairo(
        fontSize: 13,
        fontWeight: FontWeight.w400,
        height: 1.5,
        color: color,
      );

  // Input label (above each field)
  static TextStyle label({Color? color}) => GoogleFonts.cairo(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        height: 1.3,
        color: color,
      );

  // Input text + body
  static TextStyle input({Color? color}) => GoogleFonts.cairo(
        fontSize: 15,
        fontWeight: FontWeight.w500,
        height: 1.4,
        color: color,
      );

  // Button text
  static TextStyle button({Color? color}) => GoogleFonts.cairo(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        height: 1.2,
        color: color,
      );

  // Link / tertiary text
  static TextStyle link({Color? color}) => GoogleFonts.cairo(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        height: 1.3,
        color: color,
      );

  // Footer / muted small
  static TextStyle muted({Color? color}) => GoogleFonts.cairo(
        fontSize: 11,
        fontWeight: FontWeight.w400,
        height: 1.3,
        color: color,
      );
}
