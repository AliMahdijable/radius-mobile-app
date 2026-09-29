import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/screens/network_devices/widgets/device_image.dart';
import 'package:rad_mysvcs/screens/network_devices/widgets/device_image_ruijie_catalog.dart';
import 'package:rad_mysvcs/screens/network_devices/widgets/device_image_ubnt_catalog.dart';

/// حرّاس الكتالوجين المولَّدين — Ubiquiti وRuijie.
///
/// أكثر من ألفٍ وخمسمئة مدخلة لا تُراجَع بالعين. وما يُخطئ فيه صامتٌ دائماً:
/// مسارٌ لا ملفّ له يعطي مربّعاً فارغاً، وبوّابةٌ ناقصة تُسقط الصورة
/// عن أجهزتها كما حدث مع LHG وC5c من قبل.
void main() {
  group('الملفّات', () {
    test('لكلّ مدخلةٍ ملفٌّ فعليّ على القرص', () {
      final missing = <String>[];
      for (final e in kUbntCatalog.entries) {
        if (!File('assets/devices-images/${e.value}').existsSync()) {
          missing.add('${e.key} → ${e.value}');
        }
      }
      expect(missing, isEmpty,
          reason: 'مسارات بلا ملفّات:\n${missing.take(10).join('\n')}');
    });

    test('لا ملفّ يتيمٌ في المجلّد بلا مدخلة', () {
      final dir = Directory('assets/devices-images/ubnt');
      expect(dir.existsSync(), isTrue);
      final onDisk = dir
          .listSync()
          .whereType<File>()
          .map((f) => 'ubnt/${f.uri.pathSegments.last}')
          .where((p) => p.endsWith('.png'))
          .toSet();
      final referenced = kUbntCatalog.values.toSet();
      final orphans = onDisk.difference(referenced);
      expect(orphans, isEmpty,
          reason: 'ملفّات لا يشير إليها الكتالوج: ${orphans.take(8)}');
    });

    test('كلّ المسارات داخل ubnt/ — وإلّا انكسرت البوّابة', () {
      // البوّابة تحكم بالعلامة عبر بادئة المسار. مدخلةٌ خارج المجلّد
      // تُحسب ميكروتك وتسقط صامتةً عن أجهزة Ubiquiti.
      final stray =
          kUbntCatalog.values.where((v) => !v.startsWith('ubnt/')).toList();
      expect(stray, isEmpty);
    });
  });

  group('البوّابة', () {
    test('صورة الكتالوج تُقبل على ubnt', () {
      expect(DeviceImage.assetFor('ACB-AC', brand: 'ubnt'), isNotNull);
    });

    test('وتُرفض على العلامات الأخرى', () {
      // صورة سويتش Ubiquiti على جهاز ميكروتك تبدو صحيحة فيُبنى عليها
      // قرارٌ خاطئ — الرفض هنا مقصود.
      for (final b in ['mikrotik', 'cisco', 'mimosa', 'ruijie']) {
        expect(DeviceImage.assetFor('ACB-AC', brand: b), isNull,
            reason: 'تسرّبت إلى $b');
      }
    });
  });

  group('الأولويّة', () {
    test('المنسَّق يدويّاً يفوز على الكتالوج عند التقاطع', () {
      // خمسة مفاتيح مشتركة، واختيار المستخدم فيها مقصود.
      for (final m in ['Rocket M5', 'RocketM2', 'LocoM5', 'loco m2']) {
        final got = DeviceImage.assetFor(m, brand: 'ubnt');
        expect(got, isNotNull, reason: '$m بلا صورة');
        expect(got!.startsWith('ubnt/'), isFalse,
            reason: '$m أخذ صورة الكتالوج بدل المنسَّقة: $got');
      }
    });
  });

  group('المطابقة', () {
    test('رمز SKU تامّاً يُطابق', () {
      expect(DeviceImage.assetFor('AF-24HD', brand: 'ubnt'),
          'ubnt/AF-24HD.png');
    });

    test('وبلا شَرطات وبحالةٍ مختلفة', () {
      expect(DeviceImage.assetFor('af24hd', brand: 'ubnt'),
          'ubnt/AF-24HD.png');
    });

    test('الأطول يفوز — «AF-24HD» ليس «AF-24»', () {
      // 🐛 بلا ترتيب الطول تنازليّاً يلتقط `af24` ما هو `af24hd`،
      // فتظهر صورة الجهاز المجاور وهي تبدو صحيحة تماماً.
      final hd = DeviceImage.assetFor('airFiber 24HD outdoor', brand: 'ubnt');
      expect(hd, 'ubnt/AF-24HD.png');
    });

    test('اسمٌ حرٌّ يحوي الرمز يُطابق', () {
      expect(DeviceImage.assetFor('Ubiquiti ES-48-500W switch', brand: 'ubnt'),
          isNotNull);
    });

    test('ما ليس في الكتالوج يرجع null لا صورةً قريبة', () {
      expect(DeviceImage.assetFor('ZZ-NOT-A-REAL-MODEL', brand: 'ubnt'),
          isNull);
    });
  });

  group('السلامة', () {
    test('لا مفتاح فارغ ولا قيمة مكرّرة على مفتاحين متطابقين', () {
      expect(kUbntCatalog.keys.any((k) => k.isEmpty), isFalse);
      expect(kUbntCatalog.keys.length, kUbntCatalog.keys.toSet().length);
    });

    test('المفاتيح مطبَّعة — حروفٌ وأرقامٌ صغيرة فقط', () {
      final bad = kUbntCatalog.keys
          .where((k) => !RegExp(r'^[a-z0-9]+$').hasMatch(k))
          .toList();
      expect(bad, isEmpty, reason: 'مفاتيح غير مطبَّعة: ${bad.take(8)}');
    });
  });

  // ══════════════════════════════════════════════════════════════
  // روجي — نفس الحرّاس، ومصدرٌ أضعف: صفحات منتجاتٍ لا قاعدة بصمات.
  // ══════════════════════════════════════════════════════════════
  group('روجي — الملفّات', () {
    test('لكلّ مدخلةٍ ملفٌّ فعليّ', () {
      final missing = kRuijieCatalog.entries
          .where((e) => !File('assets/devices-images/${e.value}').existsSync())
          .map((e) => '${e.key} → ${e.value}')
          .toList();
      expect(missing, isEmpty, reason: missing.take(8).join('\n'));
    });

    test('لا ملفّ يتيم', () {
      final onDisk = Directory('assets/devices-images/ruijie')
          .listSync()
          .whereType<File>()
          .map((f) => 'ruijie/${f.uri.pathSegments.last}')
          .where((p) => p.endsWith('.png'))
          .toSet();
      // المرجع قد يكون في الكتالوج المولَّد أو في الخريطة المنسَّقة
      // يدويّاً داخل device_image.dart — كلاهما مرجعٌ صحيح.
      final referenced = {...kRuijieCatalog.values, 'ruijie/RG-EG1510XS.png'};
      expect(onDisk.difference(referenced), isEmpty);
    });

    test('كلّ المسارات داخل ruijie/', () {
      expect(kRuijieCatalog.values.where((v) => !v.startsWith('ruijie/')),
          isEmpty);
    });
  });

  group('روجي — البوّابة', () {
    test('تُقبل على ruijie وتُرفض على غيرها', () {
      final m = kRuijieCatalog.keys.first;
      expect(DeviceImage.assetFor(m, brand: 'ruijie'), isNotNull);
      for (final b in ['ubnt', 'mikrotik', 'cisco', 'mimosa']) {
        expect(DeviceImage.assetFor(m, brand: b), isNull, reason: 'تسرّبت إلى $b');
      }
    });
  });

  group('روجي — المطابقة', () {
    test('الرمز بلا بادئة RG يُطابق', () {
      // المدير يكتب «NBS3200-24GT4XS» لا «RG-NBS3200-24GT4XS».
      final withRg = kRuijieCatalog.keys.firstWhere((k) => k.startsWith('rg'),
          orElse: () => '');
      expect(withRg, isNotEmpty);
      final without = withRg.substring(2);
      if (without.length >= 4) {
        expect(DeviceImage.assetFor(without, brand: 'ruijie'), isNotNull,
            reason: 'سقط $without');
      }
    });

    test('ما ليس في الكتالوج يرجع null', () {
      expect(DeviceImage.assetFor('RG-NOT-REAL-9999', brand: 'ruijie'), isNull);
    });
  });

  group('روجي — السلامة', () {
    test('المفاتيح مطبَّعة ولا فراغ', () {
      final bad = kRuijieCatalog.keys
          .where((k) => !RegExp(r'^[a-z0-9]+$').hasMatch(k))
          .toList();
      expect(bad, isEmpty, reason: '${bad.take(6)}');
    });
  });

  group('الكتالوجان معاً', () {
    test('لا مفتاح مشترك بينهما — وإلّا صار الترتيب هو الحَكم', () {
      final shared =
          kUbntCatalog.keys.toSet().intersection(kRuijieCatalog.keys.toSet());
      expect(shared, isEmpty, reason: 'مفاتيح مشتركة: ${shared.take(8)}');
    });
  });
}
