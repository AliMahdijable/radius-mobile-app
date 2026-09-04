import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/services/device_stats_cache.dart';

/// 🐛 بلاغ المستخدم ٢٠٢٦-٠٩-٠٤: «يفحص الأجهزة، إذا أطلع وأطبّ للتطبيق
/// عشر مرّات كلّ مرّة يرجع يفحصهن. كلّش مزعج هالشي».
///
/// ── لماذا كان يحدث ───────────────────────────────────────────────
/// حاجز الطزاجة كان يقرأ من `VitalsStore` — وهي حقلٌ في حالة الشاشة
/// يُمسح في `dispose`. فكلّ عودةٍ تبدأ من `idle`، فيرى الحاجز «لا قراءة»
/// ويُرسل جلسةً بأولويّةٍ قصوى لكلّ بطاقة مرئيّة.
///
/// والمخزن العالميّ كان يحمل الحمولة طازجةً طوال الوقت — لكنّه لم يكن
/// يحمل **القراءة المعروضة**، فلا سبيل لإعادة الرسم منه بلا جلسة.
void main() {
  group('المخزن يحفظ ما يُعيد الرسم', () {
    setUp(() => DeviceStatsCache.instance.clear());

    test('🚨 القراءة المحفوظة تُسترجَع داخل النافذة', () {
      DeviceStatsCache.instance.putVitals(7, ['a', 'b'], 'detail');
      final got = DeviceStatsCache.instance
          .vitalsOf(7, const Duration(seconds: 20));
      expect(got, isNotNull, reason: 'بلا هذا لا سبيل لرسم البطاقة بلا جلسة');
      expect(got!.vitals, equals(['a', 'b']));
      expect(got.detail, equals('detail'));
    });

    test('🚨 وتُطرَح خارجها — الرقم الميّت أسوأ من الفراغ', () {
      DeviceStatsCache.instance.putVitals(7, ['a'], null);
      expect(
        DeviceStatsCache.instance.vitalsOf(7, Duration.zero),
        isNull,
        reason: 'نافذةٌ منتهية يجب أن تُرجع null فيُعاد الفحص',
      );
    });

    test('جهازٌ لم يُقرأ قطّ يُرجع null', () {
      expect(
        DeviceStatsCache.instance.vitalsOf(999, const Duration(minutes: 5)),
        isNull,
      );
    });

    test('القراءة والحمولة مستقلّتان', () {
      // البذر يحتاج القراءة، والترقية إلى التفصيل تحتاج الحمولة.
      // خلطُهما يجعل أحدهما يُبطل الآخر.
      DeviceStatsCache.instance.putRaw(7, 'raw-payload', detailed: false);
      DeviceStatsCache.instance.putVitals(7, ['x'], null);
      expect(DeviceStatsCache.instance.seedFor<String>(7), equals('raw-payload'));
      expect(
        DeviceStatsCache.instance.vitalsOf(7, const Duration(minutes: 1))!.vitals,
        equals(['x']),
      );
    });
  });

  group('حارس البنية — لا يعود العطل', () {
    late String src;
    setUpAll(() {
      src = File('lib/screens/network_devices/devices_wall_screen.dart')
          .readAsStringSync();
    });

    test('🚨 الحفظ في المخزن يسبق حارس mounted', () {
      // جلسةٌ اكتملت بعد مغادرة المستخدم دُفع ثمنها فعلاً. رميُ نتيجتها
      // يعني أنّ العودة تُعيد الفحص على ما هو محفوظٌ أصلاً.
      final put = src.indexOf('DeviceStatsCache.instance\n              .putRaw(');
      final guard = src.indexOf('if (!mounted) return;\n        // العيّنة تُحفظ');
      expect(put, greaterThan(0), reason: 'لم أجد موضع الحفظ');
      expect(guard, greaterThan(0), reason: 'لم أجد الحارس');
      expect(
        put,
        lessThan(guard),
        reason: '🚨 الحفظ يجب أن يسبق الحارس — وإلّا أُهدرت الجلسة',
      );
    });

    test('🚨 الحاجز يسأل المخزن لا حالة الشاشة وحدها', () {
      expect(
        src.contains('final age = DeviceStatsCache.instance.ageOf(widget.device.id);'),
        isTrue,
        reason: 'بلا سؤال المخزن يبقى كلّ رجوعٍ جولةَ فحصٍ كاملة',
      );
    });

    test('🚨 البطاقة تُبذَر من المخزن عند البناء', () {
      expect(
        src.contains('.vitalsOf(widget.device.id, DeviceVitals.freshFor)'),
        isTrue,
        reason: 'بلا البذر تظهر البطاقة فارغةً فيُطلَق فحصٌ لملئها',
      );
    });

    test('والقراءة تُحفظ لا الحمولة وحدها', () {
      expect(
        src.contains('.putVitals(widget.device.id, r.vitals, r.detail)'),
        isTrue,
      );
    });
  });
}
