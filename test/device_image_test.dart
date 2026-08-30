import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/screens/network_devices/widgets/device_image.dart';

/// مطابقة اسم الموديل بصورة الجهاز.
///
/// الخطر هنا ليس «لا صورة» بل **الصورة الخطأ**: أسماء Mikrotik متداخلة
/// كسوابق («CCR2004-16G-2S+» سابقة لـ«CCR2004-16G-2S+PC»)، فمطابقة
/// من الأقصر تُظهر جهازاً مجاوراً — وهي أسوأ من الشارة، لأنّها تبدو
/// صحيحة فيبني عليها المدير قراراً.
void main() {
  test('مطابقة تامّة رغم اختلاف الفواصل والحالة', () {
    expect(DeviceImage.assetFor('CCR2116-12G-4S+'),
        'CCR2116-12G-4S+.webp');
    expect(DeviceImage.assetFor('ccr2116 12g 4s'), 'CCR2116-12G-4S+.webp');
    expect(DeviceImage.assetFor('rocket m5'), 'rocket m5.png');
    expect(DeviceImage.assetFor('ROCKETM5'), 'rocket m5.png');
  });

  test('السابقة الأطول تفوز — لا صورة جهاز مجاور', () {
    // «CCR2004-16G-2S+PC» تحوي «CCR2004-16G-2S+» بالكامل.
    expect(DeviceImage.assetFor('CCR2004-16G-2S+PC'),
        'CCR2004-16G-2S+PC.webp');
    expect(DeviceImage.assetFor('CCR2004-16G-2S+'), 'CCR2004-16G-2S+.webp');
    // و«RB1100AHx4 Dude Edition» تحوي «RB1100AHx4».
    expect(DeviceImage.assetFor('RB1100AHx4 Dude Edition'),
        'RB1100AHx4 Dude Edition.webp');
    expect(DeviceImage.assetFor('RB1100AHx4'), 'RB1100AHx4.webp');
  });

  test('اسم داخل جملة يُلتقط', () {
    expect(DeviceImage.assetFor('Mikrotik CCR1016-12G router'),
        'CCR1016-12G.webp');
  });

  test('موديل مجهول أو فارغ يُرجع null فتظهر الشارة', () {
    expect(DeviceImage.assetFor(null), isNull);
    expect(DeviceImage.assetFor(''), isNull);
    expect(DeviceImage.assetFor('   '), isNull);
    expect(DeviceImage.assetFor('جهاز غير معروف'), isNull);
  });

  test('جزء فريد من الاسم يُطابق', () {
    // «912» موجود في ملفّ واحد فقط — وهو ما يكتبه المدير فعلاً في
    // قاعدة البيانات لهذا الجهاز.
    expect(DeviceImage.assetFor('912'), 'RB912UAG-5HPnD-OUT.webp');
  });

  test('جزء يُطابق أكثر من طراز لا يُخمَّن', () {
    // ⚠️ عرض أحدها اعتباطاً أسوأ من الشارة: يبدو صحيحاً فيُبنى عليه
    // قرار.
    //
    // «RB5009» تُطابق طرازين (UG+S+IN و UPr+S+IN) — والثاني يدعم PoE
    // خارجاً والأوّل لا. «CCR1036» تُطابق أربعة.
    expect(DeviceImage.assetFor('RB5009'), isNull);
    expect(DeviceImage.assetFor('CCR1036'), isNull);
    expect(DeviceImage.assetFor('CRS326'), isNull);
    // وبالطراز الكامل تُطابق بلا لبس
    expect(DeviceImage.assetFor('RB5009UG+S+IN'), 'RB5009UG+S+IN.webp');
  });

  test('مفتاح قصير جدّاً لا يُطابق بالاحتواء', () {
    // حدّ الستّة محارف يمنع «m5» أو «lhg» من مطابقة نصف الفهرس.
    expect(DeviceImage.assetFor('m5'), isNull);
    expect(DeviceImage.assetFor('x'), isNull);
  });
}
