import 'package:flutter/material.dart';

/// سلّم المسافات. استعملها ولا تكتب أرقاماً سائبة.
///
/// المخطّط الجديد يعمل بدقّة 1px لا 4pt (9px×26 · 7px×24 · 11px×15 …)،
/// وقرارنا: **نقرّب للسلّم** (9→8، 7→8، 11→12، 5→4) حفاظاً على النظام،
/// عدا `xxs=2` التي لا بديل عنها (26 استعمالاً: الفراغ داخل عمود
/// التسمية/القيمة، وحشوة حاوية صفوف المعلومات).
/// حشو أسفل القوائم — يُحسب لا يُكتب رقماً.
///
/// 🐛 بلاغ ٢٠٢٦-٠٩-٠٢: آخر بطاقة في قائمة الأجهزة يبتلعها الشريط
/// السفليّ ولا يمكن التمرير إليها. والسبب أنّ شاشات القسم كلّها تكتب
/// `90` ثابتة، بينما شاشة المشتركين تحسب `Sp.huge * 3 + المنطقة
/// الآمنة`.
///
/// ⚠️ الرقم الثابت لا يكفي: الشريط السفليّ ملفوفٌ بـ`SafeArea`، فيزيد
/// ارتفاعه بمقدار مؤشّر الشاشة (نحو ٣٤ على آيفون بلا زرّ). فقائمةٌ
/// تبدو كاملةً على أندرويد تُقتطع على آيفون — وهو بالضبط ما حدث.
class Inset {
  Inset._();

  /// أسفل قائمةٍ داخل قوقعة التبويبات (شريط سفليّ + مؤشّر الشاشة).
  static double tabBar(BuildContext c) =>
      Sp.huge * 3 + MediaQuery.paddingOf(c).bottom;

  /// أسفل قائمةٍ في مسارٍ مدفوع — لا شريط، لكنّ المؤشّر باقٍ.
  static double route(BuildContext c) =>
      Sp.mega + MediaQuery.paddingOf(c).bottom;
}

class Sp {
  Sp._();
  static const double xxs = 2;
  static const double xs = 4;
  static const double x6 = 6;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double huge = 32;
  static const double mega = 48;
}

/// أنصاف الأقطار. الخمسة الأولى قائمة من قبل (1,700+ استدعاء)،
/// والباقي مضاف من المخطّط حيث لكلّ دور نصف قطر ثابت.
class R {
  R._();
  static const double sm = 10;
  static const double chip = 11; // شريحة المبلغ السريع / الفلتر الأفقي
  static const double md = 12;
  static const double icon = 14; // مربّع الأيقونة 40×40 + البلاطة الغاطسة
  static const double lg = 16; // الحقل / مجموعة صفوف المعلومات
  static const double button = 17; // كلّ زرّ height:50 بلا استثناء
  static const double card = 20; // الكارت الكبير
  static const double xl = 24;
  static const double hero = 26; // بطاقة الهويّة
  static const double sheet = 30; // أعلى الـbottom sheet
  static const double pill = 999;
}

/// الارتفاعات المعياريّة — المخطّط يكرّرها بثبات.
class H {
  H._();
  static const double button = 50; // الزرّ الأساسي + الزرّ الأيقوني المرافق
  static const double search = 46;
  static const double segment = 44; // segmented / زرّ الاتجاه
  static const double iconBox = 40; // مربّع أيقونة رأس الـsheet
  static const double iconBtn = 38; // الزرّ الأيقوني في الرأس
  static const double chip = 36; // شريحة الفرز/التصفية
  static const double chipSm = 34; // شريحة الحالة
  static const double closeBtn = 32;
  static const double fab = 52;
  static const double checkbox = 20;
  static const double grabber = 4;
}

/// سُمك الحدّ — نمط ثابت في المخطّط: الاختيار يرفع السُمك من 1 إلى 1.5
/// مع تغيير لون الحدّ للبراند.
class BW {
  BW._();
  static const double normal = 1;
  static const double selected = 1.5;
}

/// الظلال — المخطّط شحيح جدّاً بها ويعتمد على الحدود لا الارتفاع.
/// **كلّ الكروت بلا ظلّ**: `elevation: 0` على أي `Card`/`Material`.
/// القاعدة اللونيّة #102820 (أخضر داكن) لا الأسود.
class Sh {
  Sh._();

  /// ظلّ الـbottom sheet — متجه للأعلى.
  static const List<BoxShadow> sheet = [
    BoxShadow(
      color: Color(0x59102820),
      offset: Offset(0, -20),
      blurRadius: 50,
      spreadRadius: -20,
    ),
  ];

  /// القائمة المنسدلة.
  static const List<BoxShadow> menu = [
    BoxShadow(
      color: Color(0x59102820),
      offset: Offset(0, 18),
      blurRadius: 40,
      spreadRadius: -14,
    ),
  ];

  /// ظلّ الـFAB — ملوَّن بلون الزرّ نفسه لا بالأسود.
  static const List<BoxShadow> fab = [
    BoxShadow(
      color: Color(0xB3103D2E),
      offset: Offset(0, 10),
      blurRadius: 22,
      spreadRadius: -10,
    ),
  ];
}
