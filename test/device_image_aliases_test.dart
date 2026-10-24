import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/screens/network_devices/widgets/device_image.dart';

/// أسماءٌ يكتبها الوكلاء فعلاً في طراز الجهاز (admin_devices، ٢٤ أكتوبر) ← صورة — المالك: «912 6GH هواي اجهزه
/// موجوده صورها». الصور الجديدة رسميّة من صفحة كلّ طرازٍ في mikrotik.com (عنوان الصفحة = الطراز).
void main() {
  String? img(String model, String brand) => DeviceImage.assetFor(model, brand: brand);

  test('RB912 بكلّ كتاباته، و6GHz بهيكل BaseBox نفسه', () {
    for (final m in ['912', 'rb912', 'R 912', 'RB912UAG-5HPnD', 'RB912UAG-6HPnD', 'BaseBox 6', 'RB 912BaseBox 5']) {
      expect(img(m, 'mikrotik'), 'RB912UAG-5HPnD-OUT.webp', reason: m);
    }
  });

  test('صور ميكروتك الجديدة ومرادفاتها', () {
    expect(img('RB3011UiAS', 'mikrotik'), 'RB3011UiAS-RM.webp');
    expect(img('3011', 'mikrotik'), 'RB3011UiAS-RM.webp');
    expect(img('RB2011UiAS', 'mikrotik'), 'RB2011UiAS-RM.webp');
    expect(img('RB2011iL-IN', 'mikrotik'), 'RB2011iL-IN.webp');
    expect(img('RB2011iL', 'mikrotik'), 'RB2011iL-RM.webp');
    expect(img('netPower 16P', 'mikrotik'), 'netPower 16P.webp');
    expect(img('CRS125-24G-1S', 'mikrotik'), 'CRS125-24G-1S-IN.webp');
    expect(img('CCR1009-8G-1S-1S+', 'mikrotik'), 'CCR1009-8G-1S.webp');
    expect(img('RB1100AHx2', 'mikrotik'), 'RB1100AHx2.webp');
    expect(img('PowerBox Pro', 'mikrotik'), 'RB960PGS-PB.webp');
    expect(img('rb5009', 'mikrotik'), 'RB5009UG+S+IN.webp');
  });

  test('الأسماء العربيّة وأسماء يوبيكويتي وميموزا', () {
    expect(img('بوربيم', 'ubnt'), 'powerbeam M5.webp');
    expect(img('بور بيم', 'ubnt'), 'powerbeam M5.webp');
    expect(img('نانو ستيشن', 'ubnt'), 'nano m5-2.png');
    expect(img('لايت بيم', 'ubnt'), isNotNull);
    expect(img('LiteAP AC', 'ubnt'), 'ubnt/LAP-120.png');
    expect(img('AIRSPAN-C5c', 'mimosa'), 'c5c-ptmp-hero.png');
  });

  test('البوّابة باقية: صورة ميكروتك لا تظهر على جهازٍ علامته غيرها', () {
    expect(img('RB912UAG-6HPnD', 'ubnt'), isNull);
    expect(img('بوربيم', 'mikrotik'), isNull);
  });
}
