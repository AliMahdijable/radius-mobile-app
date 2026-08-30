import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/ubnt_api.dart';

/// تحليل `/proc/net/dev` — مصدر الترافيك اللحظي لجهاز المشترك.
///
/// ثلاثة أخطاء ممكنة هنا، وكلّها تُنتج **أرقاماً معقولة تماماً**:
/// 1. فهرس الحقل: الإرسال التاسع لا الثاني — الثاني عدد الحزم.
/// 2. جمع الواجهات: على CPE جسريّ ما يدخل من `ath0` يخرج من `eth0`،
///    فالمجموعان متساويان حتماً — وهو ما ظهر للمستخدم فعلاً
///    (تحميل ورفع بالقيمة نفسها دائماً).
/// 3. اتّجاه الواجهة: `ath0` تواجه البرج و`eth0` تواجه المشترك،
///    فاستقبالهما معكوسان. خلطهما يعطي رقمين مقلوبين.
void main() {
  const wireless = '''
Inter-|   Receive                                                |  Transmit
 face |bytes    packets errs drop fifo frame compressed multicast|bytes    packets errs drop fifo colls carrier compressed
    lo:  999999   1000    0    0    0     0          0         0   888888    1000    0    0    0     0       0          0
  eth0: 2000000   9000    0    0    0     0          0         0  9000000   40000    0    0    0     0       0          0
  ath0: 9000000  40000    0    0    0     0          0         0  2000000    9000    0    0    0     0       0          0
''';

  test('اللاسلكيّة تُقدَّم — واستقبالها هو تحميل المشترك', () {
    final r = UbntTrafficSession.parseProcNetDev(wireless);
    expect(r, isNotNull);
    expect(r!.down, 9000000, reason: 'ath0 RX = ما يصل المشترك');
    expect(r.up, 2000000, reason: 'ath0 TX = ما يرسله');
  });

  test('لا تُجمع الواجهات — الجمع يُساوي القيمتين حتماً', () {
    final r = UbntTrafficSession.parseProcNetDev(wireless);
    // المجموع كان سيعطي 11,000,000 للاتّجاهين — وهو العطل المُبلَّغ.
    expect(r!.down, isNot(r.up));
    expect(r.down + r.up, 11000000);
  });

  test('السلكيّة وحدها تُقلب — استقبالها رفع المشترك', () {
    const wired = '  eth0: 2000000 9 0 0 0 0 0 0 9000000 40 0 0 0 0 0 0';
    final r = UbntTrafficSession.parseProcNetDev(wired);
    expect(r!.down, 9000000, reason: 'eth0 TX = ما يُرسَل للمشترك');
    expect(r.up, 2000000, reason: 'eth0 RX = ما يرسله المشترك');
  });

  test('br0 تُعامَل كسلكيّة — الواجهة الوحيدة على بعض الأجهزة', () {
    const bridged = '  br0: 700 1 0 0 0 0 0 0 300 1 0 0 0 0 0 0';
    final r = UbntTrafficSession.parseProcNetDev(bridged);
    expect(r!.down, 300);
    expect(r.up, 700);
  });

  test('الإرسال من الحقل التاسع لا الثاني', () {
    final r = UbntTrafficSession.parseProcNetDev(wireless);
    // الحقل الثاني عدد الحزم (40000) — رقم معقول وخاطئ.
    expect(r!.up, isNot(40000));
  });

  test('خرج فارغ أو بلا واجهات بيانات يُرجع null لا صفراً', () {
    // صفر يعني «لا حركة»، وnull يعني «لا قراءة» — والفرق يحدّد هل
    // تُعرض «—» أم «0».
    expect(UbntTrafficSession.parseProcNetDev(''), isNull);
    expect(
      UbntTrafficSession.parseProcNetDev('    lo:  1 2 3 4 5 6 7 8 9 10'),
      isNull,
    );
  });

  test('سطر مبتور لا يُسقط القراءة كلّها', () {
    const partial = '''
  eth0: 500 1 0 0 0 0 0 0 400 1 0 0 0 0 0 0
  ath0: مبتور
''';
    final r = UbntTrafficSession.parseProcNetDev(partial);
    expect(r, isNotNull);
    expect(r!.down, 400);
    expect(r.up, 500);
  });
}
