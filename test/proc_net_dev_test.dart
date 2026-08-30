import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/ubnt_api.dart';

/// تحليل `/proc/net/dev` — مصدر الترافيك اللحظي لجهاز المشترك.
///
/// الصيغة ثابتة عبر كل نوى لينكس، لكنّ **فهارس الحقول** سهلة الخطأ:
/// بايتات الاستقبال أوّل حقل بعد النقطتين، والإرسال التاسع — وبينهما
/// سبعة حقول (حزم · أخطاء · إسقاط · fifo · إطارات · مضغوط · بثّ).
/// خطأ فهرس واحد يعطي رقماً معقولاً تماماً لكنّه خاطئ — لا يكشفه إلّا
/// اختبار بعيّنة حقيقيّة.
void main() {
  const sample = '''
Inter-|   Receive                                                |  Transmit
 face |bytes    packets errs drop fifo frame compressed multicast|bytes    packets errs drop fifo colls carrier compressed
    lo:  999999   1000    0    0    0     0          0         0   888888    1000    0    0    0     0       0          0
  eth0: 12345678  50000    0    0    0     0          0         0  8765432   40000    0    0    0     0       0          0
  ath0:  1000000   4000    0    0    0     0          0         0   500000    3000    0    0    0     0       0          0
''';

  test('يجمع واجهات البيانات ويستثني lo', () {
    final r = UbntTrafficSession.parseProcNetDev(sample);
    expect(r, isNotNull);
    // eth0 + ath0 — و`lo` مستثناة وإلّا تضاعفت الأرقام بحركة داخليّة
    expect(r!.rx, 12345678 + 1000000);
    expect(r.tx, 8765432 + 500000);
  });

  test('الإرسال من الحقل التاسع لا الثاني', () {
    // لو أُخذ الحقل الخطأ لصار tx = عدد الحزم (50000+4000) — رقم
    // معقول تماماً في الشكل وخاطئ تماماً في المعنى.
    final r = UbntTrafficSession.parseProcNetDev(sample);
    expect(r!.tx, isNot(50000 + 4000));
    expect(r.tx, greaterThan(r.rx ~/ 2));
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
    expect(r!.rx, 500);
    expect(r.tx, 400);
  });

  test('br0 محسوبة — الواجهة الوحيدة على بعض الأجهزة', () {
    const bridged = '  br0: 700 1 0 0 0 0 0 0 300 1 0 0 0 0 0 0';
    final r = UbntTrafficSession.parseProcNetDev(bridged);
    expect(r!.rx, 700);
    expect(r.tx, 300);
  });
}
