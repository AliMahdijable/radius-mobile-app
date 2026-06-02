import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Cairo via google_fonts (runtime download + cache). Returns TextStyles
/// from static methods because GoogleFonts.cairo() can't be const-evaluated.
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
