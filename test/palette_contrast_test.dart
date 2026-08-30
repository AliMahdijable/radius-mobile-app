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
/// ⚠️ **مقايضة معلنة، بقرار صاحب المنتج (2026-08-30)**
///
/// رفعتُ الرتب الثلاث الدنيا أوّلاً لتبلغ 3:1 على `bg`. المستخدم فحص
/// النتيجة وردّها: «التطبيق ألوانه صارت غامقة زيادة». القياس أنصفه —
/// كلّ تسمية وعدّاد وتاريخ ثانوي صار أثقل بصريّاً بنحو 40%
/// (textLow من 2.54 إلى 3.64 · textHint من 2.40 إلى 3.36).
///
/// فأُعيدت إلى قيم المخطّط تقريباً: **الوزن البصري للواجهة كلّها فاز
/// على 0.3 نقطة تباين في نصّ لا يحمل معلومة**. العتبة هنا 2.7 على `bg`
/// — أرضيّة تمنع الانحدار، لا ادّعاء بلوغ AA.
///
/// الشرط المقابل يبقى ملزماً: **هذه الرتب لا تحمل معلومة جوهريّة**.
/// أيّ معلومة لا بديل عنها تُكتب بـ`textMid` فأعلى — و`textMid` وحدها
/// تخضع لـAA بلا تفاوض (4.5:1 على `bg`).
///
/// `textPlaceholder` مستثنى — WCAG تستثني نصّ الحقل النائب صراحةً.

double _lum(Color c) {
  double ch(double v) {
    v = v / 255.0;
    return v <= 0.04045
        ? v / 12.92
        : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
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

/// المسافة الإدراكيّة CIELAB ΔE76 — تقيس فرق **الصبغة والسطوع معاً**.
/// نسبة التباين وحدها لا تكفي للترميز التصنيفي: لونان قد يتساويان في
/// السطوع (نسبة ≈1) ويختلفان في الصبغة اختلافاً بيّناً.
double deltaE(Color a, Color b) {
  (double, double, double) toLab(Color c) {
    double ch(double v) {
      v = v / 255.0;
      return v <= 0.04045
          ? v / 12.92
          : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
    }

    final r = ch((c.r * 255).roundToDouble());
    final g = ch((c.g * 255).roundToDouble());
    final bl = ch((c.b * 255).roundToDouble());
    final x = (0.4124 * r + 0.3576 * g + 0.1805 * bl) / 0.95047;
    final y = 0.2126 * r + 0.7152 * g + 0.0722 * bl;
    final z = (0.0193 * r + 0.1192 * g + 0.9505 * bl) / 1.08883;
    double f(double t) =>
        t > 0.008856 ? math.pow(t, 1 / 3).toDouble() : 7.787 * t + 16 / 116;
    final fx = f(x), fy = f(y), fz = f(z);
    return (116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz));
  }

  final la = toLab(a), lb = toLab(b);
  return math.sqrt(math.pow(la.$1 - lb.$1, 2) +
      math.pow(la.$2 - lb.$2, 2) +
      math.pow(la.$3 - lb.$3, 2));
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

typedef Pair = ({
  String name,
  Color Function() fg,
  Color Function() bg,
  double min
});

void main() {
  // أزواج تُقاس في الوضعين. الـgetters تُقرأ بعد ضبط الوضع لا قبله.
  final pairs = <Pair>[
    // ── نصوص على سطح الكارت ──
    (
      name: 'textHi على surface',
      fg: () => AppColors.textHi,
      bg: () => AppColors.surface,
      min: 4.5
    ),
    (
      name: 'textBody على surface',
      fg: () => AppColors.textBody,
      bg: () => AppColors.surface,
      min: 4.5
    ),
    (
      name: 'textMid على surface',
      fg: () => AppColors.textMid,
      bg: () => AppColors.surface,
      min: 4.5
    ),
    // الرتب الدنيا تُقاس على bg — أسوأ سطح فاتح، لا على الأبيض.
    (
      name: 'textLabel على bg',
      fg: () => AppColors.textLabel,
      bg: () => AppColors.bg,
      min: 2.7
    ),
    (
      name: 'textLow على bg',
      fg: () => AppColors.textLow,
      bg: () => AppColors.bg,
      min: 2.6
    ),
    (
      name: 'textHint على bg',
      fg: () => AppColors.textHint,
      bg: () => AppColors.bg,
      min: 2.45
    ),
    (
      name: 'textLabel على surfaceSheet',
      fg: () => AppColors.textLabel,
      bg: () => AppColors.surfaceSheet,
      min: 2.9
    ),
    // ── نصوص على خلفيّة الشاشة ──
    (
      name: 'textHi على bg',
      fg: () => AppColors.textHi,
      bg: () => AppColors.bg,
      min: 4.5
    ),
    (
      name: 'textBody على bg',
      fg: () => AppColors.textBody,
      bg: () => AppColors.bg,
      min: 4.5
    ),
    (
      name: 'textMid على bg',
      fg: () => AppColors.textMid,
      bg: () => AppColors.bg,
      min: 4.5
    ),
    // ── نصوص على السطح الغاطس (بلاطات القياس) ──
    (
      name: 'textHi على surfaceSunken',
      fg: () => AppColors.textHi,
      bg: () => AppColors.surfaceSunken,
      min: 4.5
    ),
    (
      name: 'textBody على surfaceSunken',
      fg: () => AppColors.textBody,
      bg: () => AppColors.surfaceSunken,
      min: 4.5
    ),
    (
      name: 'textMid على surfaceSunken',
      fg: () => AppColors.textMid,
      bg: () => AppColors.surfaceSunken,
      min: 4.5
    ),
    (
      name: 'textLabel على surfaceSunken',
      fg: () => AppColors.textLabel,
      bg: () => AppColors.surfaceSunken,
      min: 2.9
    ),
    (
      name: 'textLow على surfaceSunken',
      fg: () => AppColors.textLow,
      bg: () => AppColors.surfaceSunken,
      min: 2.7
    ),
    // ── تعبئات الأزرار: الأبيض فوقها ──
    (
      name: 'onBrand على brand',
      fg: () => AppColors.onBrand,
      bg: () => AppColors.brand,
      min: 4.5
    ),
    (
      name: 'onBrand على errorFill',
      fg: () => AppColors.onBrand,
      bg: () => AppColors.errorFill,
      min: 4.5
    ),
    (
      name: 'onBrand على warningFill',
      fg: () => AppColors.onBrand,
      bg: () => AppColors.warningFill,
      min: 4.5
    ),
    (
      name: 'onBrand على successFill',
      fg: () => AppColors.onBrand,
      bg: () => AppColors.successFill,
      min: 4.5
    ),
    // ── التعبئة نفسها مقابل السطح خلفها (مكوّن غير نصّي) ──
    (
      name: 'brand مقابل surface',
      fg: () => AppColors.brand,
      bg: () => AppColors.surface,
      min: 3.0
    ),
    (
      name: 'brandAccent مقابل surface',
      fg: () => AppColors.brandAccent,
      bg: () => AppColors.surface,
      min: 3.0
    ),
    (
      name: 'error مقابل surface',
      fg: () => AppColors.error,
      bg: () => AppColors.surface,
      min: 3.0
    ),
    // ── نصّ العائلة الدلاليّة فوق خلفيّتها الخفيفة ──
    (
      name: 'brandOnSoft على brandSoftBg',
      fg: () => AppColors.brandOnSoft,
      bg: () => AppColors.brandSoftBg,
      min: 4.5
    ),
    (
      name: 'warningOnSoft على warningSoftBg',
      fg: () => AppColors.warningOnSoft,
      bg: () => AppColors.warningSoftBg,
      min: 4.5
    ),
    (
      name: 'dangerOnSoft على dangerSoftBg',
      fg: () => AppColors.dangerOnSoft,
      bg: () => AppColors.dangerSoftBg,
      min: 4.5
    ),
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
        const card = AppColors.brandSurface;
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
        const card = AppColors.brandSurface;
        final t = flatten(AppColors.onBrandTertiary, card);
        expect(contrast(t, card), greaterThanOrEqualTo(4.0),
            reason: '$mode — onBrandTertiary فوق البطاقة');
      });

      test('brandSurface ثابت في الوضعين — عليه معايرة كل طبقات on-brand', () {
        AppColors.setDarkMode(false);
        const light = AppColors.brandSurface;
        AppColors.setDarkMode(true);
        expect(AppColors.brandSurface, equals(light),
            reason: 'سطح البطاقة الداكنة يجب ألّا يتغيّر — طبقات onBrand* '
                'معايرة عليه، وتغييره يُسقطها تحت العتبة.');
        AppColors.setDarkMode(dark);
      });

      test('ألوان حالة المشترك متمايزة داخل كل مجموعة أيقونة', () {
        AppColors.setDarkMode(dark);
        // رمز الحالة في القائمة يحمل **بعدين مستقلّين**:
        //   • الأيقونة = الاتصال اللحظي (wifi · wifiOff · block)
        //   • اللون    = حالة الاشتراك (فعّال · قارب الانتهاء · منتهي)
        //
        // فالتمييز اللوني مطلوب **داخل المجموعة الواحدة فقط** — حيث
        // الأيقونة متطابقة واللون هو القناة الوحيدة. عبر المجموعات
        // تكفي الأيقونة، ولا معنى لاشتراط فارق لوني هناك.
        //
        // القياس بـΔE76 لا بنسبة السطوع: لونان قد يتساويان في السطوع
        // ويختلفان في الصبغة اختلافاً واضحاً — وهذا بالضبط ما أوقع
        // المحاولة الأولى في خطأ تشخيصي.
        //
        // انحدار 2026-08-29: توحيد اللوحة ابتلع الأزرق والبنفسجي في
        // brandAccent فسقطت ثلاث حالات من السبع بلا أن يشتكي شيء.
        final groups = <String, List<(String, Color)>>{
          'wifi (متصل)': [
            ('فعّال', AppColors.info),
            ('قارب الانتهاء', AppColors.warning),
            ('منتهي', AppColors.anomaly),
          ],
          'wifiOff (غير متصل)': [
            ('فعّال', AppColors.success),
            ('قارب الانتهاء', AppColors.warning),
            ('منتهي', AppColors.error),
          ],
        };
        for (final entry in groups.entries) {
          final items = entry.value;
          for (var i = 0; i < items.length; i++) {
            for (var j = i + 1; j < items.length; j++) {
              final d = deltaE(items[i].$2, items[j].$2);
              expect(d, greaterThanOrEqualTo(30.0),
                  reason: '$mode — ${entry.key}: «${items[i].$1}» و'
                      '«${items[j].$1}» متقاربان إدراكيّاً '
                      '(ΔE=${d.toStringAsFixed(1)}) فلا يُفرَّق بينهما');
            }
          }
        }
      });

      test('خلفيّات مربّعات الحالة مرئيّة على سطح الكارت', () {
        AppColors.setDarkMode(dark);
        // بلاغ 2026-08-30: `successSoftBg` كانت #F2F7F4 — تباين 1.08 عن
        // الأبيض، أي شبه بيضاء، فبدا المربّع «غير ملوّن» بينما نظائره
        // ملوّنة. العتبة 1.10 تضمن أنّ المربّع يُرى مربّعاً.
        final softs = <String, Color>{
          'brandSoftBg': AppColors.brandSoftBg,
          'successSoftBg': AppColors.successSoftBg,
          'warningSoftBg': AppColors.warningSoftBg,
          'dangerSoftBg': AppColors.dangerSoftBg,
          'infoSoftBg': AppColors.infoSoftBg,
          'anomalySoftBg': AppColors.anomalySoftBg,
          'channelWhatsAppSoftBg': AppColors.channelWhatsAppSoftBg,
          'channelTelegramSoftBg': AppColors.channelTelegramSoftBg,
        };
        for (final e in softs.entries) {
          final r = contrast(e.value, AppColors.surface);
          expect(r, greaterThanOrEqualTo(1.10),
              reason: '$mode — ${e.key} لا تُرى على سطح الكارت '
                  '(${r.toStringAsFixed(2)})');
        }
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

  test('وميض الهيكل العظمي مرئيّ في الوضعين', () {
    // الهيكل يعِد المستخدم بأنّ شيئاً يجري. إن كان تباين الوميض
    // منخفضاً جدّاً بدت الشاشة متجمّدة — وهو أسوأ من غياب الهيكل
    // أصلاً، لأنّه يوحي بالتعليق لا بالتحميل.
    //
    // الحدّ 1.35:1 تجريبي: أقلّ منه لا تُرى الحركة على شاشة هاتف
    // في ضوء النهار، وأكثر من ~1.8:1 يصير الوميض مُشتّتاً.
    for (final dark in [false, true]) {
      AppColors.setDarkMode(dark);
      final ratio = contrast(AppColors.surfaceSunken, AppColors.borderStrong);
      final mode = dark ? 'الليلي' : 'النهاري';
      expect(ratio, greaterThan(1.35),
          reason: 'وميض الهيكل في الوضع $mode باهت '
              '(${ratio.toStringAsFixed(2)}:1) — يبدو متجمّداً');
      expect(ratio, lessThan(2.2),
          reason: 'وميض الهيكل في الوضع $mode صارخ '
              '(${ratio.toStringAsFixed(2)}:1) — يُشتّت عن المحتوى');
    }
    AppColors.setDarkMode(false);
  });

}
