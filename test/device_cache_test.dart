import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/services/device_stats_cache.dart';

/// مخزن قراءات الأجهزة + التسخين في الخلفيّة.
///
/// 🐛 بلاغ ٢٠٢٦-٠٩-٠٢: «بكلّ جهاز أنقر عليه لازم يعيد إرسال الطلب. هو
/// كلّهن طلب واحد، مفروض يجلب كلّ المعلومات ويبقى يحافظها».
/// + طلب: «الفحص يبقى مستمرّاً بالخلفيّة، والداتا جاهزة».
void main() {
  final cache = DeviceStatsCache.instance;
  setUp(cache.clear);

  group('البذرة', () {
    test('🚨 حمولةٌ محفوظة تُبذَر بها اللوحة فوراً', () {
      cache.putRaw(7, 'حمولة');
      expect(cache.seedFor<String>(7), 'حمولة');
    });

    test('🚨 النوع مفحوص — جهازٌ غُيّرت علامته', () {
      // بذرُ حمولة ميكروتك في لوحة UBNT ترمي. الفحص في المخزن لا عند
      // المستدعي، فلا يُنسى في لوحةٍ من الخمس.
      cache.putRaw(7, 42);
      expect(cache.seedFor<String>(7), isNull);
      expect(cache.seedFor<int>(7), 42);
    });

    test('لا شيء لجهازٍ لم يُقرأ', () {
      expect(cache.seedFor<String>(99), isNull);
      expect(cache.ageOf(99), isNull);
    });

    test('العمر يُقاس', () {
      cache.putRaw(1, 'x');
      expect(cache.ageOf(1)!.inSeconds, lessThan(2));
    });

    test('نافذة البذر أطول من نافذة التجديد', () {
      // البذر يعرض رقماً عمره دقيقة **ثمّ يُحدّثه فوراً** — أنفع من
      // شاشةٍ فارغة تنتظر ثوانيَ.
      expect(DeviceStatsCache.seedTtl.inSeconds, greaterThan(20));
      expect(DeviceStatsCache.seedTtl.inMinutes, lessThanOrEqualTo(5),
          reason: 'وأقدمُ من ذلك يُطرح — الفراغ أصدق منه');
    });
  });

  group('العيّنات', () {
    test('تنجو من الخروج والعودة', () {
      // كانت تعيش في حالة الشاشة، فالخروج من «نظرة عامّة» يمحوها
      // والعودة تبدأ من «يقيس…».
      cache.putSample(3, {'eth': (rx: 100, tx: 50)});
      final s = cache.sampleOf(3);
      expect(s, isNotNull);
      expect(s!.counters['eth']!.rx, 100);
    });

    test('الفارغة لا تُحفظ', () {
      cache.putSample(3, {});
      expect(cache.sampleOf(3), isNull);
    });
  });

  group('العزل', () {
    test('🚨 يُفرَغ عند تبديل الحساب', () {
      // قراءاتُ مديرٍ لا تُعرض لغيره.
      cache.putRaw(1, 'x');
      expect(cache.size, 1);
      cache.clear();
      expect(cache.size, 0);
    });
  });

  group('التسخين', () {
    late String warm;
    setUpAll(() =>
        warm = File('lib/services/device_warmup.dart').readAsStringSync());

    test('🚨 واحدٌ في كلّ مرّة بأدنى أولويّة', () {
      // أيّ تزاحمٍ منه على الخانات الستّ يُبطئ ما ينظر إليه المستخدم.
      expect(warm.contains('DeepProbeScheduler.instance.submit(_WarmOwner('),
          isTrue);
      expect(warm.contains('first: true'), isFalse,
          reason: 'التسخين لا يسبق بطاقةً تنتظر قراءتها الأولى');
      expect(warm.contains('Timer(gap, _tick)'), isTrue,
          reason: 'جهازٌ ثمّ فاصل — لا دفعة');
    });

    test('يمتنع بنفس أسباب البطاقة', () {
      expect(warm.contains('DeviceVitals.skipReason(d) != null'), isTrue);
      expect(warm.contains('DeviceStatsCache.instance.ageOf(d.id) == null'),
          isTrue, reason: 'ومن حمولتُه في المخزن لا يحتاج جلسة');
    });

    test('🚨 مالكٌ مستقلّ عن البطاقة', () {
      // لو تشاركا المالك لسحب إلغاءُ إحداهما مهمّة الأخرى، ولأبطل
      // تسخينٌ متأخّر قراءةً طلبها المستخدم توّاً.
      expect(warm.contains('class _WarmOwner'), isTrue);
      expect(warm.contains('other is _WarmOwner'), isTrue);
    });

    test('يتوقّف مع الشاشة ومع الخلفيّة', () {
      final list =
          File('lib/screens/network_devices/network_devices_screen.dart')
              .readAsStringSync();
      expect(list.contains('DeviceWarmup.instance.start(_all)'), isTrue);
      expect(RegExp(r'DeviceWarmup\.instance\.stop\(\)').allMatches(list).length,
          2, reason: 'عند التخلّص وعند دخول الخلفيّة');
    });
  });

  group('اللوحات تُبذَر وتُغذّي', () {
    for (final b in ['mikrotik', 'ubnt', 'mimosa']) {
      test(b, () {
        final src =
            File('lib/screens/network_devices/widgets/${b}_live_panel.dart')
                .readAsStringSync();
        expect(src.contains('DeviceStatsCache.instance.seedFor<'), isTrue,
            reason: '$b لا تُبذَر — تفتح جلسةً والحمولة في اليد');
        expect(src.contains('DeviceStatsCache.instance.putRaw('), isTrue,
            reason: '$b لا تُغذّي المخزن — الطريق ذهاباً وإياباً');
      });
    }
  });

  group('رتبة الحمولة', () {
    setUp(cache.clear);

    test('🚨 الخفيفة لا تُحسب كاملة', () {
      // بلا التمييز نظنّ الخفيفة كافيةً فنعرض تفصيلاً فارغاً، ولا
      // تُرقَّى أبداً.
      cache.putRaw(1, 'خفيفة', detailed: false);
      expect(cache.isDetailed(1), isFalse);
      expect(cache.needsUpgrade(1), isTrue);
    });

    test('الكاملة تُنهي الحاجة', () {
      cache.putRaw(1, 'كاملة', detailed: true);
      expect(cache.isDetailed(1), isTrue);
      expect(cache.needsUpgrade(1), isFalse);
    });

    test('🚨 خفيفةٌ بعد كاملة تُحدّث العمر ولا تُجمّده', () {
      // تحذير المستخدم «المعلومات الحيّة ما تتغيّر»: كان الفرع يعود
      // صامتاً فلا يمسّ الطابع الزمنيّ — فتشيخ اللقطة حتّى تُطرح، ومن
      // يُبذَر منها يرى رقماً ميّتاً تحت شارة «مباشر».
      cache.putRaw(1, 'كاملة', detailed: true);
      final before = cache.ageOf(1);
      cache.putRaw(1, 'خفيفة', detailed: false);
      final after = cache.ageOf(1);
      expect(before, isNotNull);
      expect(after!.compareTo(before!), lessThanOrEqualTo(0),
          reason: 'العمر لم يُحدَّث — البذرة تشيخ وهي تُقرأ كلّ نبضة');
    });

    test('🚨 خفيفةٌ بعد كاملة لا تمحو التفاصيل', () {
      // البطاقة المطويّة تُجدّد أرقامها كلّ نبضة بجلسةٍ خفيفة. ولو
      // أنزلت الرتبة لأُعيدت الترقية إلى الأبد، ولاختفى التفصيل من
      // بطاقةٍ مفتوحة.
      cache.putRaw(1, 'كاملة', detailed: true);
      cache.putRaw(1, 'خفيفة', detailed: false);
      expect(cache.isDetailed(1), isTrue, reason: 'الرتبة نزلت');
      expect(cache.seedFor<String>(1), 'كاملة',
          reason: 'والحمولة استُبدلت بالناقصة');
    });

    test('من لا قراءة له ليس مرشَّحاً للترقية', () {
      expect(cache.needsUpgrade(99), isFalse);
      expect(cache.isDetailed(99), isFalse);
    });
  });

  group('الخلفيّة رخيصة', () {
    late String warm;
    late String wall;
    setUpAll(() {
      warm = File('lib/services/device_warmup.dart').readAsStringSync();
      wall = File('lib/screens/network_devices/devices_wall_screen.dart')
          .readAsStringSync();
    });

    test('🚨 التسخين يجلب الخفيف لا الكامل', () {
      // انحدارٌ أُدخل ثمّ تُرووجع ٢٠٢٦-٠٩-٠٢: جعلتُه يجلب الكامل ليجد
      // المستخدمُ التفاصيلَ جاهزة، فعاد إلى الخلفيّة ما أُزيل من
      // المقدّمة — جلسة SSH لكلّ جهاز ميكروتك، سبع عشرة متتالية.
      //
      // والحساب لا يستقيم: تفاصيلُ ثمانين جهازاً ليُفتح منها واحد.
      expect(warm.contains('detailed: true'), isFalse,
          reason: 'عاد التسخين يجرّ التفاصيل');
      expect(warm.contains('putRaw(d.id, r.raw!, detailed: false)'), isTrue);
    });

    test('🚨 ولا ترقيةَ جماعيّة', () {
      expect(warm.contains('_needsUpgrade'), isFalse);
      expect(warm.contains('..addAll(upgrades)'), isFalse);
    });

    test('🚨 الجدار لا يُشغّل التسخين', () {
      // بطاقاته تقرأ أجهزتها بنفسها وهي مرئيّة — فالتسخين لا يضيف
      // إلّا مزاحمةً على الخانات الستّ.
      expect(wall.contains('DeviceWarmup'), isFalse);
    });

    test('القائمة وحدها تُشغّله', () {
      final list =
          File('lib/screens/network_devices/network_devices_screen.dart')
              .readAsStringSync();
      expect(list.contains('DeviceWarmup.instance.start(_all)'), isTrue);
    });
  });

  group('البذرة لا تدّعي أنّها الآن', () {
    test('🚨 اللوحات تُورّث عمر البذرة لا لحظتها', () {
      // تحذير المستخدم: «المعلومات الحيّة ما تتغيّر، تبقى ثابتة».
      // والبذرة لقطةٌ قد يبلغ عمرها دقيقتين، وكانت تُعرض تحت شارة
      // «مباشر» كأنّها الآن. رقمٌ قديمٌ معلومُ القِدَم أمانة، ومعروضٌ
      // كأنّه الآن كذبة.
      for (final b in ['mikrotik', 'ubnt', 'mimosa']) {
        final src =
            File('lib/screens/network_devices/widgets/${b}_live_panel.dart')
                .readAsStringSync();
        expect(src.contains('DeviceStatsCache.instance.ageOf(widget.device.id)'),
            isTrue, reason: '$b لا تقرأ عمر البذرة');
        expect(src.contains('_lastFetch = DateTime.now().subtract(seedAge)'),
            isTrue, reason: '$b تدّعي أنّ البذرة لحظيّة');
      }
    });

    test('نبضة الشاشة المفتوحة أقصر — جهازٌ واحد لا ثمانون', () {
      for (final b in ['ubnt', 'mimosa', 'airfiber60', 'ruijie']) {
        final src =
            File('lib/screens/network_devices/widgets/${b}_live_panel.dart')
                .readAsStringSync();
        expect(src.contains('Duration(seconds: 10)'), isTrue, reason: b);
        expect(src.contains('_refreshInterval = Duration(seconds: 15)'), isFalse,
            reason: b);
      }
    });
  });
}
