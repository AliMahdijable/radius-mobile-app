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

  // ٢٧ أكتوبر — المالك: «صور ٩٢١gs و صور بور بوكس ماكو واصدارات اجهزه لنكات مال ٦ جي هم ماكو بالمايكروتيك».
  // الأسماء الأولى كما في admin_devices حرفيّاً.
  test('921GS (mANTBox) بكلّ كتاباته', () {
    for (final m in ['RB921GS-5HPacD r2', '921', 'RB921GS-5HPacD', 'RB921GS-5HPacD-19S', 'mANTBox 19s', 'مانت بوكس']) {
      expect(img(m, 'mikrotik'), 'RB921GS-5HPacD-19S.webp', reason: m);
    }
    for (final m in ['RB921GS-5HPacD-15S', 'mANTBox 15s', 'mantbox 15']) {
      expect(img(m, 'mikrotik'), 'RB921GS-5HPacD-15S.webp', reason: m);
    }
    expect(img('mANTBox 2 12s', 'mikrotik'), 'RB911G-2HPnD-12S.webp', reason: 'mANTBox 2 باقٍ على صورته');
  });

  test('PowerBox ≠ PowerBox Pro', () {
    for (final m in ['PowerBOX', 'PowerBox', 'RB750P-PBr2', 'بور بوكس', 'باوربوكس']) {
      expect(img(m, 'mikrotik'), 'RB750P-PBr2.webp', reason: m);
    }
    for (final m in ['PowerBox Pro', 'RB960PGS-PB', 'بور بوكس برو']) {
      expect(img(m, 'mikrotik'), 'RB960PGS-PB.webp', reason: m);
    }
  });

  test('أجهزة 60 GHz: الاسم التجاريّ ورمز اللوحة وزوج Wireless Wire', () {
    const cases = {
      'LHG 60G': 'LHG 60G.webp',
      'lhg60': 'LHG 60G.webp',
      'RBLHGG-60ad': 'LHG 60G.webp',
      'Wireless Wire Dish': 'LHG 60G.webp',
      'Cube 60Pro ac': 'Cube 60Pro ac.webp',
      'CubeG-5ac60ay': 'Cube 60Pro ac.webp',
      'Wireless Wire Cube Pro': 'Cube 60Pro ac.webp',
      'Cube 60G ac': 'Cube 60G ac.webp',
      'CubeG-5ac60adpair': 'Cube 60G ac.webp',
      'Wireless Wire Cube': 'Cube 60G ac.webp',
      'wAP 60G': 'wAP 60G.webp',
      'wAP 60G AP': 'wAP 60G.webp',
      'RBwAPG-60ad-A': 'wAP 60G.webp',
      'Wireless Wire': 'wAP 60G.webp',
      'wAP 60Gx3 AP': 'wAP 60Gx3 AP.webp',
      'RBwAPG-60ad-SA': 'wAP 60Gx3 AP.webp',
      'Wireless Wire nRAY': 'Wireless Wire nRAY.webp',
      'nRAYG-60ad': 'Wireless Wire nRAY.webp',
    };
    cases.forEach((m, f) => expect(img(m, 'mikrotik'), f, reason: m));
    expect(img('60G', 'mikrotik'), isNull, reason: 'غامضٌ بين أربعة أجهزة — لا يُخمَّن');
    expect(img('Cube 60Pro ac', 'ubnt'), isNull, reason: 'البوّابة');
  });

  test('كلّ صورةٍ جديدة تعود لنفسها حين تُختار يدويّاً (اسمها يُكتب طرازاً)', () {
    for (final f in [
      'RB921GS-5HPacD-19S.webp', 'RB921GS-5HPacD-15S.webp', 'RB750P-PBr2.webp', 'Cube 60Pro ac.webp',
      'Cube 60G ac.webp', 'wAP 60G.webp', 'wAP 60Gx3 AP.webp', 'Wireless Wire nRAY.webp',
    ]) {
      expect(DeviceImage.allAssets, contains(f));
      expect(img(DeviceImage.boardNameOf(f), 'mikrotik'), f, reason: f);
    }
  });

  test('البوّابة باقية: صورة ميكروتك لا تظهر على جهازٍ علامته غيرها', () {
    expect(img('RB912UAG-6HPnD', 'ubnt'), isNull);
    expect(img('بوربيم', 'mikrotik'), isNull);
  });
}
