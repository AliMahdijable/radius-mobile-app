import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/screens/network_devices/widgets/device_image.dart';

/// اختيار صورة الجهاز.
///
/// 🐛 بلاغ ٢٠٢٦-٠٩-٠٢: «الصورة ما تظهر، وهي موجودة ضمن الصور».
/// و`c5c-ptmp-hero.png` كان مُدرَجاً في تعداد Ubiquiti — والـC5c منتَج
/// **ميموزا**. فالبوّابة تطلب `ubnt` وتجد `mimosa` فتُسقط الصورة.
void main() {
  group('صورة ميموزا C5c', () {
    // السلاسل أدناه من قاعدة البيانات الحيّة (٦٩ جهاز ميموزا).
    test('🚨 «c5c» — ١٥ جهازاً في الأسطول', () {
      expect(DeviceImage.assetFor('c5c', brand: 'mimosa'),
          'c5c-ptmp-hero.png');
    });

    test('«ميموسا C5C» — الحروف العربيّة تُحذف في التطبيع', () {
      expect(DeviceImage.assetFor('ميموسا C5C', brand: 'mimosa'),
          'c5c-ptmp-hero.png');
    });

    test('«MIMOSA C5c» — ما يكتبه الكشف التلقائيّ من sysDescr', () {
      expect(DeviceImage.assetFor('MIMOSA C5c', brand: 'mimosa'),
          'c5c-ptmp-hero.png');
    });
  });

  group('البوّابة تبقى صارمة', () {
    test('🚨 صورة ميموزا لا تظهر على جهاز ميكروتك', () {
      // صورة سويتش على سكتور تبدو صحيحة فيُبنى عليها قرار في الميدان.
      expect(DeviceImage.assetFor('c5c', brand: 'mikrotik'), isNull);
      expect(DeviceImage.assetFor('c5c', brand: 'ubnt'), isNull);
    });

    test('صورة ميكروتك لا تظهر على ميموزا', () {
      expect(DeviceImage.assetFor('CCR2116-12G-4S+', brand: 'mimosa'), isNull);
      expect(DeviceImage.assetFor('CCR2116-12G-4S+', brand: 'mikrotik'),
          isNotNull);
    });

    test('صورة Ubiquiti تبقى لـUbiquiti', () {
      expect(DeviceImage.assetFor('rocket m5', brand: 'ubnt'), isNotNull);
      expect(DeviceImage.assetFor('rocket m5', brand: 'mimosa'), isNull);
    });
  });

  group('ما لا يُطابَق يبقى بلا صورة', () {
    test('غموضٌ لا يُخمَّن', () {
      // «mimosa» وحدها لا تقول أيّ طراز — والأسطول فيه C5c وC6c.
      expect(DeviceImage.assetFor('mimosa', brand: 'mimosa'), isNull);
      expect(DeviceImage.assetFor('c6c', brand: 'mimosa'), isNull);
      expect(DeviceImage.assetFor(null, brand: 'mimosa'), isNull);
      expect(DeviceImage.assetFor('', brand: 'mimosa'), isNull);
    });
  });
}
