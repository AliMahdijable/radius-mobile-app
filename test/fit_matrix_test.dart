import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/screens/subscribers/widgets/device_probe_card.dart';
import 'package:rad_mysvcs/theme/colors.dart';
import 'package:rad_mysvcs/theme/typography.dart';

/// مسطرة الملاءمة — تقيس بالخطّ المشحون على كلّ عرض شاشة.
///
/// 🐛 لماذا وُجدت (تدقيق 2026-08-31): حرّاس التخطيط الخمسة في هذا
/// المستودع يحكمون كلّهم بـ`tester.takeException()`. وهي تمسك فيضان
/// `RenderFlex` — الشرائط الصفراء والسوداء — لكنّها **عمياء عن القصّ**:
/// النصّ المبتور بـ`TextOverflow.ellipsis` يُرسم بلا استثناء، فالاختبار
/// يمرّ والبيانات ضائعة.
///
/// ولهذا عاش عطل بلاطة «الترافيك» في كلّ نسخة: «↓587K ↑3…» على آيفون
/// 11 برو ماكس، ورقم الرفع مختفٍ كلّياً على 360 نقطة.
///
/// ⚠️ ثلاثة فخاخ تعلّمناها بالتجربة، مثبَّتة هنا حتّى لا تتكرّر:
///
///  1. **بلا الخطّ الحقيقيّ لا معنى للقياس.** خطّ الاختبار الافتراضيّ
///     يرسم كلّ محرف مربّعاً بعرض القياس كاملاً، فيضخّم النصّ اللاتيني
///     ويصغّر العربي. القياسات هنا تُحمّل ملفّات IBM Plex المشحونة.
///  2. **لا تُقس المفاتيح.** `easy_localization` غير مهيّأة في
///     الاختبارات فـ`.tr()` تُرجع المفتاح («dashboard.near_expiry» =
///     21 محرفاً بدل «نشط» = 3). القياس هنا على النصوص الحقيقيّة.
///  3. **سلّم الخطّ مقيَّد.** `main.dart:259` يحصر التكبير بين 0.9
///     و1.2، فسيناريو «المستخدم يكبّر إلى 2.0» غير قابل للتحقّق ولا
///     يُختبَر — أسوأ حالة حقيقيّة هي 1.2.
Future<void> _loadAppFont() async {
  final loader = FontLoader(AppType.family);
  for (final w in [400, 500, 600, 700]) {
    loader.addFont(File('assets/fonts/${AppType.family}-$w.ttf')
        .readAsBytes()
        .then((b) => ByteData.view(b.buffer)));
  }
  await loader.load();
}

double _width(String text, TextStyle style, {double scale = 1.0}) {
  final tp = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
    textScaler: TextScaler.linear(scale),
  )..layout();
  return tp.width;
}

/// عروض الأجهزة الحقيقيّة التي يخدمها التطبيق.
const _widths = <({double dp, String name})>[
  (dp: 320, name: 'iPhone SE 1'),
  (dp: 360, name: 'أغلب أندرويد المتوسّط'),
  (dp: 393, name: 'Pixel 7/8'),
  (dp: 414, name: 'iPhone 11 Pro Max'),
  (dp: 430, name: 'iPhone 15 Pro Max'),
];

/// حدّا سلّم الخطّ كما يقيّدهما main.dart.
const _scales = <double>[1.0, 1.2];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(_loadAppFont);

  group('بلاطة الترافيك — بعد أن أخذت العرض الكامل', () {
    // سلسلة القيود: الشاشة − 32 حشوة القائمة − 32 حشوة الكارت
    // − 2 الحدّ = العرض الداخلي؛ ثمّ − 24 حشوة البلاطة.
    double budget(double screen) => screen - 32 - 32 - 2 - 24;

    // أسوأ سلسلة واقعيّة: رقمان من أربع خانات بوحدتين.
    const worst = '↓999.9M ↑999.9M';

    for (final e in _widths) {
      for (final scale in _scales) {
        test('${e.name} (${e.dp.toInt()}dp) × سلّم $scale', () {
          final style = AppType.cardTitle(color: AppColors.textHi)
              .copyWith(fontWeight: FontWeight.w700);
          final need = _width(worst, style, scale: scale);
          final have = budget(e.dp);
          expect(need, lessThanOrEqualTo(have),
              reason: '«$worst» يحتاج ${need.toStringAsFixed(1)} '
                  'والمتاح ${have.toStringAsFixed(1)}');
        });
      }
    }

    test('الثلث القديم كان يفيض فعلاً — إثبات أنّ المسطرة تقيس شيئاً', () {
      // لو مرّ هذا لصار الحارس بلا معنى: القياس نفسه يجب أن يرصد
      // التخطيط المكسور الذي أُزيل.
      final style = AppType.cardTitle(color: AppColors.textHi)
          .copyWith(fontWeight: FontWeight.w700);
      final need = _width('↓587K ↑3.2M', style);
      const oldThird = (414 - 32 - 32 - 2 - 16) / 3 - 24;
      expect(need, greaterThan(oldThird),
          reason: 'الثلث القديم كان ${oldThird.toStringAsFixed(1)} '
              'والنصّ ${need.toStringAsFixed(1)} — لهذا قُصّ');
    });
  });

  group('المُنسّقات لا تكذب', () {
    test('حركة حقيقيّة دون الكيلو لا تُعرَض صفراً', () {
      // كان `if (bps < 1000) return '0K'` — فمشترك يسحب 999 بت/ث يبدو
      // ميّتاً تماماً كمن لا يسحب شيئاً.
      expect(fmtBpsForTest(999), isNot(startsWith('0')));
      expect(fmtBpsForTest(400), isNot(startsWith('0')));
      expect(fmtBpsForTest(1), isNot(startsWith('0')));
    });

    test('الصفر وحده يُعرَض صفراً', () {
      expect(fmtBpsForTest(0), '0');
    });

    test('الدرجات الأعلى كما هي — لا انحدار', () {
      expect(fmtBpsForTest(587000), '587K');
      expect(fmtBpsForTest(3200000), '3.2M');
      expect(fmtBpsForTest(2500000000), '2.5G');
    });

    test('كلّ خرج يتّسع في البلاطة على أضيق شاشة', () {
      final style = AppType.cardTitle(color: AppColors.textHi)
          .copyWith(fontWeight: FontWeight.w700);
      const have = 320 - 32 - 32 - 2 - 24.0;
      for (final bps in [0, 1, 999, 1000, 587000, 3200000, 999900000]) {
        final s = '↓${fmtBpsForTest(bps)} ↑${fmtBpsForTest(bps)}';
        expect(_width(s, style, scale: 1.2), lessThanOrEqualTo(have),
            reason: 'خرج $bps → «$s» لا يتّسع على 320dp بسلّم 1.2');
      }
    });
  });
}
