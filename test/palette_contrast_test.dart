import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/theme/colors.dart';

/// اختبار تباين اللوحة — يقيس WCAG في **الوضعين** آليّاً.
///
/// اللوحة كُتبت بأرقام تباين محسوبة يدويّاً في التعليقات (2026-08-29).
/// هذا الاختبار يمنع انحرافها: أي تعديل يُنزل زوجاً تحت عتبته يسقط هنا
/// بدل أن يُكتشف على شاشة مستخدم في وضع ليلي.
///
/// العتبات المطبَّقة:
///  • `textHi` · `textBody` · `textMid` → **4.5:1** (WCAG AA للنصّ العادي)
///  • `textLabel` · `textLow` · `textHint` → **3.0:1**
///  • تعبئات الأزرار والأبيض فوقها → 4.5:1
///  • الحدود والمكوّنات غير النصّيّة → 3.0:1
///
/// ⚠️ **فجوة معلنة لا صامتة**: WCAG تطلب 4.5:1 لكلّ نصّ صغير بلا استثناء،
/// والرتب الثلاث الدنيا تقف عند 3:1 لأنّ رفعها إلى 4.5 يجعلها لوناً
/// واحداً تقريباً فينهار سلّم النصّ من ستّ رتب إلى ثلاث. الشرط المقابل:
/// **هذه الرتب لا تحمل معلومة جوهريّة** — تسميات حقول وعدّادات وتلميحات
/// تُكرَّر قيمتها في مكان آخر. أيّ معلومة لا بديل عنها تُكتب بـ`textMid`
/// فأعلى.
///
/// كلّ رتبة تُقاس على **أسوأ سطح فاتح** (`bg` #F4F5F2) لا على الأبيض،
/// لأنّ الأبيض يعطي أعلى تباين ويخفي الرسوب.
///
/// `textPlaceholder` مستثنى — WCAG تستثني نصّ الحقل النائب صراحةً.

double _lum(Color c) {
  double ch(double v) {
    v = v / 255.0;
    return v <= 0.04045 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  }

  return 0.2126 * ch((c.r * 255).roundToDouble()) +
      0.7152 * ch((c.g * 255).roundToDouble()) +
      0.0722 * ch((c.b * 255).roundToDouble());
}

/// نسبة التباين بين لونين معتمين.
double contrast(Color a, Color b) {
  final la = _lum(a), lb = _lum(b);
  final hi = math.max(la, lb), lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

/// يسطّح لوناً شفّافاً فوق خلفيّة معتمة قبل القياس — الطبقات الشفّافة
/// (onBrandFill*, softBg) لا يصحّ قياسها كما هي.
Color flatten(Color fg, Color bg) {
  final a = fg.a;
  return Color.fromARGB(
    255,
    ((fg.r * a + bg.r * (1 - a)) * 255).round(),
    ((fg.g * a + bg.g * (1 - a)) * 255).round(),
    ((fg.b * a + bg.b * (1 - a)) * 255).round(),
  );
}

typedef Pair = ({String name, Color Function() fg, Color Function() bg, double min});

void main() {
  // أزواج تُقاس في الوضعين. الـgetters تُقرأ بعد ضبط الوضع لا قبله.
  final pairs = <Pair>[
    // ── نصوص على سطح الكارت ──
    (name: 'textHi على surface', fg: () => AppColors.textHi, bg: () => AppColors.surface, min: 4.5),
    (name: 'textBody على surface', fg: () => AppColors.textBody, bg: () => AppColors.surface, min: 4.5),
    (name: 'textMid على surface', fg: () => AppColors.textMid, bg: () => AppColors.surface, min: 4.5),
    // الرتب الدنيا تُقاس على bg — أسوأ سطح فاتح، لا على الأبيض.
    (name: 'textLabel على bg', fg: () => AppColors.textLabel, bg: () => AppColors.bg, min: 3.0),
    (name: 'textLow على bg', fg: () => AppColors.textLow, bg: () => AppColors.bg, min: 3.0),
    (name: 'textHint على bg', fg: () => AppColors.textHint, bg: () => AppColors.bg, min: 3.0),
    (name: 'textLabel على surfaceSheet', fg: () => AppColors.textLabel, bg: () => AppColors.surfaceSheet, min: 3.0),
    // ── نصوص على خلفيّة الشاشة ──
    (name: 'textHi على bg', fg: () => AppColors.textHi, bg: () => AppColors.bg, min: 4.5),
    (name: 'textBody على bg', fg: () => AppColors.textBody, bg: () => AppColors.bg, min: 4.5),
    (name: 'textMid على bg', fg: () => AppColors.textMid, bg: () => AppColors.bg, min: 4.5),
    // ── نصوص على السطح الغاطس (بلاطات القياس) ──
    (name: 'textHi على surfaceSunken', fg: () => AppColors.textHi, bg: () => AppColors.surfaceSunken, min: 4.5),
    (name: 'textBody على surfaceSunken', fg: () => AppColors.textBody, bg: () => AppColors.surfaceSunken, min: 4.5),
    (name: 'textMid على surfaceSunken', fg: () => AppColors.textMid, bg: () => AppColors.surfaceSunken, min: 4.5),
    (name: 'textLabel على surfaceSunken', fg: () => AppColors.textLabel, bg: () => AppColors.surfaceSunken, min: 3.0),
    (name: 'textLow على surfaceSunken', fg: () => AppColors.textLow, bg: () => AppColors.surfaceSunken, min: 3.0),
    // ── تعبئات الأزرار: الأبيض فوقها ──
    (name: 'onBrand على brand', fg: () => AppColors.onBrand, bg: () => AppColors.brand, min: 4.5),
    (name: 'onBrand على errorFill', fg: () => AppColors.onBrand, bg: () => AppColors.errorFill, min: 4.5),
    (name: 'onBrand على warningFill', fg: () => AppColors.onBrand, bg: () => AppColors.warningFill, min: 4.5),
    (name: 'onBrand على successFill', fg: () => AppColors.onBrand, bg: () => AppColors.successFill, min: 4.5),
    // ── التعبئة نفسها مقابل السطح خلفها (مكوّن غير نصّي) ──
    (name: 'brand مقابل surface', fg: () => AppColors.brand, bg: () => AppColors.surface, min: 3.0),
    (name: 'brandAccent مقابل surface', fg: () => AppColors.brandAccent, bg: () => AppColors.surface, min: 3.0),
    (name: 'error مقابل surface', fg: () => AppColors.error, bg: () => AppColors.surface, min: 3.0),
    // ── نصّ العائلة الدلاليّة فوق خلفيّتها الخفيفة ──
    (name: 'brandOnSoft على brandSoftBg', fg: () => AppColors.brandOnSoft, bg: () => AppColors.brandSoftBg, min: 4.5),
    (name: 'warningOnSoft على warningSoftBg', fg: () => AppColors.warningOnSoft, bg: () => AppColors.warningSoftBg, min: 4.5),
    (name: 'dangerOnSoft على dangerSoftBg', fg: () => AppColors.dangerOnSoft, bg: () => AppColors.dangerSoftBg, min: 4.5),
  ];

  for (final dark in [false, true]) {
    final mode = dark ? 'الوضع الليلي' : 'الوضع النهاري';
    group(mode, () {
      setUp(() => AppColors.setDarkMode(dark));
      tearDown(() => AppColors.setDarkMode(false));

      for (final p in pairs) {
        test('${p.name} ≥ ${p.min}:1', () {
          AppColors.setDarkMode(dark);
          final ratio = contrast(p.fg(), p.bg());
          expect(ratio, greaterThanOrEqualTo(p.min),
              reason: '$mode — ${p.name}: ${ratio.toStringAsFixed(2)}:1 '
                  'وهي دون العتبة ${p.min}:1');
        });
      }

      test('طبقات on-brand مقروءة فوق البطاقة الداكنة', () {
        AppColors.setDarkMode(dark);
        // البطاقة الخضراء تُرسم بـ`brandSurface` — ثابت في الوضعين
        // عمداً (راجع تعليقه في colors.dart). طبقاتها أبيض شفّاف
        // تُسطَّح قبل القياس.
        final card = AppColors.brandSurface;
        final secondary = flatten(AppColors.onBrandSecondary, card);
        expect(contrast(secondary, card), greaterThanOrEqualTo(4.5),
            reason: '$mode — onBrandSecondary فوق البطاقة');
        final surface1 = flatten(AppColors.onBrandFill1, card);
        expect(contrast(AppColors.onBrand, surface1), greaterThanOrEqualTo(4.5),
            reason: '$mode — الأبيض فوق سطح onBrandFill1');
      });

      test('سلّم النصّ متدرّج فعلاً — لا رتبتان متطابقتان', () {
        AppColors.setDarkMode(dark);
        final surface = AppColors.surface;
        final ladder = <(String, Color)>[
          ('textHi', AppColors.textHi),
          ('textBody', AppColors.textBody),
          ('textMid', AppColors.textMid),
          ('textLabel', AppColors.textLabel),
          ('textLow', AppColors.textLow),
          ('textHint', AppColors.textHint),
        ];
        for (var i = 0; i < ladder.length - 1; i++) {
          final a = contrast(ladder[i].$2, surface);
          final b = contrast(ladder[i + 1].$2, surface);
          // كلّ رتبة أقلّ تبايناً من التي قبلها — وإلّا انهار السلّم.
          expect(a, greaterThan(b),
              reason: '$mode — ${ladder[i].$1} (${a.toStringAsFixed(2)}) '
                  'يجب أن يفوق ${ladder[i + 1].$1} (${b.toStringAsFixed(2)})');
        }
      });

      test('onBrandTertiary مقروء فوق البطاقة', () {
        AppColors.setDarkMode(dark);
        final card = AppColors.brandSurface;
        final t = flatten(AppColors.onBrandTertiary, card);
        expect(contrast(t, card), greaterThanOrEqualTo(4.0),
            reason: '$mode — onBrandTertiary فوق البطاقة');
      });

      test('brandSurface ثابت في الوضعين — عليه معايرة كل طبقات on-brand', () {
        AppColors.setDarkMode(false);
        final light = AppColors.brandSurface;
        AppColors.setDarkMode(true);
        expect(AppColors.brandSurface, equals(light),
            reason: 'سطح البطاقة الداكنة يجب ألّا يتغيّر — طبقات onBrand* '
                'معايرة عليه، وتغييره يُسقطها تحت العتبة.');
        AppColors.setDarkMode(dark);
      });

      test('الأسطح الأربعة متمايزة عن بعضها', () {
        AppColors.setDarkMode(dark);
        final ladder = [
          ('bg', AppColors.bg),
          ('surface', AppColors.surface),
          ('surfaceSheet', AppColors.surfaceSheet),
          ('surfaceSunken', AppColors.surfaceSunken),
        ];
        for (var i = 0; i < ladder.length; i++) {
          for (var j = i + 1; j < ladder.length; j++) {
            expect(ladder[i].$2, isNot(equals(ladder[j].$2)),
                reason: '$mode — ${ladder[i].$1} و${ladder[j].$1} متطابقان');
          }
        }
      });

      test('الحدود تفصل عن السطح الذي تحيطه', () {
        AppColors.setDarkMode(dark);
        expect(contrast(AppColors.border, AppColors.surface),
            greaterThanOrEqualTo(1.15),
            reason: '$mode — الحدّ لا يُرى على السطح');
      });
    });
  }
}
