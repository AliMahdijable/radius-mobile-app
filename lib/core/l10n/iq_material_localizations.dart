import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

/// تقاويم Material (منتقي التاريخ ومنتقي الفترة) بأسماء الأشهر كما تُقال في العراق.
///
/// ترجمة فلاتر العربيّة تأخذ أسماء intl («أكتوبر، نوفمبر…») فكان المنتقي يقول «1 أكتوبر – 24 أكتوبر» بينما بقيّة
/// التطبيق «1 تشرين الأوّل» (المالك ٢٤ أكتوبر بصورة المنتقي). نرث الترجمة العربيّة كاملةً ونستبدل دوالّ التاريخ
/// النصّيّة وحدها؛ صيغة الإدخال الرقميّة (formatCompactDate/parseCompactDate) كما هي.
class IqMaterialLocalizationsDelegate extends LocalizationsDelegate<MaterialLocalizations> {
  const IqMaterialLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => locale.languageCode == 'ar';

  static IqMaterialLocalizationAr? _cached;

  /// متزامن كمندوب فلاتر (SynchronousFuture): بلا فجوةٍ قبل أوّل إطار. مندوب فلاتر يُحمّل بيانات intl للعربيّة
  /// (أسماء الأيّام والأنماط) أوّلاً، و`then` على SynchronousFuture ينفّذ فوراً.
  @override
  Future<MaterialLocalizations> load(Locale locale) =>
      GlobalMaterialLocalizations.delegate.load(locale).then((_) => _cached ??= IqMaterialLocalizationAr());

  @override
  bool shouldReload(IqMaterialLocalizationsDelegate old) => false;
}

class IqMaterialLocalizationAr extends MaterialLocalizationAr {
  IqMaterialLocalizationAr()
      : super(
          fullYearFormat: intl.DateFormat.y('ar'),
          compactDateFormat: intl.DateFormat.yMd('ar'),
          shortDateFormat: intl.DateFormat.yMMMd('ar'),
          mediumDateFormat: intl.DateFormat.MMMEd('ar'),
          longDateFormat: intl.DateFormat.yMMMMEEEEd('ar'),
          yearMonthFormat: intl.DateFormat.yMMMM('ar'),
          shortMonthDayFormat: intl.DateFormat.MMMd('ar'),
          decimalFormat: intl.NumberFormat.decimalPattern('ar'),
          twoDigitZeroPaddedFormat: intl.NumberFormat('00', 'ar'),
        );

  /// كما في `rexp.m1..m12` (ar.json) — المصدر الذي يكتب به التطبيق تواريخه.
  static const months = [
    'كانون الثاني', 'شباط', 'آذار', 'نيسان', 'أيّار', 'حزيران', //
    'تمّوز', 'آب', 'أيلول', 'تشرين الأوّل', 'تشرين الثاني', 'كانون الأوّل',
  ];

  static final _weekday = intl.DateFormat.EEEE('ar');

  String _m(DateTime d) => months[d.month - 1];

  @override
  String formatMonthYear(DateTime date) => '${_m(date)} ${date.year}';

  @override
  String formatShortMonthDay(DateTime date) => '${date.day} ${_m(date)}';

  @override
  String formatShortDate(DateTime date) => '${date.day} ${_m(date)} ${date.year}';

  @override
  String formatMediumDate(DateTime date) => '${_weekday.format(date)}، ${date.day} ${_m(date)}';

  @override
  String formatFullDate(DateTime date) => '${_weekday.format(date)}، ${date.day} ${_m(date)} ${date.year}';
}
