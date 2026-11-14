import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/screens/network_devices/scan_range.dart';

/// «اكتشاف الأجهزة» — النطاق (المالك ١٤ نوفمبر ٢٠٢٦: «نخلي اختياري يختار رينج من الى مثلا 10.10.10.2-10.10.10.20 … ما نقيده
/// فقط بسبنت»). خانة «شبكة» تقبل ما كانت تقبله كما كان، ومعه أيّ ‎/N‎ بحدّه الحقيقيّ والمدى الكامل؛ وخانتا «من – إلى» عنواناً
/// كاملاً وآخرَ كاملاً أو رقمه الأخير — ولو عبر أكثر من ‎/24‎.
void main() {
  String span(ScanRangeResult r) => r.range == null ? 'ERR ${r.error}' : '${r.range!.firstIp}-${r.range!.lastIp} ${r.range!.count}';

  group('خانة «شبكة» — ما كانت تقبله كما كان', () {
    test('ثلاثة أجزاء أو أربعة ⇒ ‎.1–.254‎ من ‎/24‎', () {
      expect(span(parseScanNetwork('192.168.1')), '192.168.1.1-192.168.1.254 254');
      expect(span(parseScanNetwork('192.168.1.')), '192.168.1.1-192.168.1.254 254');
      expect(span(parseScanNetwork('10.70.241.77')), '10.70.241.1-10.70.241.254 254');
      expect(span(parseScanNetwork(' 10.70.241.0/24 ')), '10.70.241.1-10.70.241.254 254');
    });
    test('‎…5-100‎ داخل ‎/24‎', () {
      expect(span(parseScanNetwork('10.70.241.5-100')), '10.70.241.5-10.70.241.100 96');
    });
  });

  group('خانة «شبكة» — الجديد', () {
    test('أيّ ‎/N‎ بحدّه الحقيقيّ (كانت ‎/24‎ بصمت)', () {
      expect(span(parseScanNetwork('10.10.0.0/22')), '10.10.0.1-10.10.3.254 1022');
      expect(span(parseScanNetwork('10.10.4.9/23')), '10.10.4.1-10.10.5.254 510');
      expect(span(parseScanNetwork('10.10.10.130/26')), '10.10.10.129-10.10.10.190 62');
      expect(span(parseScanNetwork('10.10.10.7/31')), '10.10.10.6-10.10.10.7 2');
      expect(span(parseScanNetwork('10.10.10.7/32')), '10.10.10.7-10.10.10.7 1');
      expect(span(parseScanNetwork('10.10.10/24')), '10.10.10.1-10.10.10.254 254');
    });
    test('المدى الكامل ‎A-B‎ (مثال المالك) ولو عبر ‎/24‎', () {
      expect(span(parseScanNetwork('10.10.10.2-10.10.10.20')), '10.10.10.2-10.10.10.20 19');
      expect(span(parseScanNetwork('10.10.10.250 - 10.10.11.5')), '10.10.10.250-10.10.11.5 12');
      expect(span(parseScanNetwork('10.10.10.2–10.10.10.20')), '10.10.10.2-10.10.10.20 19', reason: 'شرطة طويلة');
    });
    test('أرقامٌ عربيّة وفاصلة لوحة الأرقام', () {
      expect(span(parseScanNetwork('١٠٫١٠٫١٠٫٢-٢٠')), '10.10.10.2-10.10.10.20 19');
      expect(span(parseScanNetwork('10,10,10,2-20')), '10.10.10.2-10.10.10.20 19');
    });
    test('أكبر من الحدّ ⇒ سببٌ بالعربيّة لا مسحٌ لآلاف العناوين', () {
      final r = parseScanNetwork('10.10.0.0/21');
      expect(r.range, isNull);
      expect(r.error, contains('2046'));
      expect(r.error, contains('${ScanRange.maxCount}'));
      expect(parseScanNetwork('10.0.0.0/8').range, isNull);
    });
    test('صيغٌ فاسدة ⇒ سبب', () {
      for (final bad in ['', 'abc', '10.10', '300.1.1', '10.10.10.10/40', '10.10.10.1-2-3', '10.10.10.999']) {
        final r = parseScanNetwork(bad);
        expect(r.range, isNull, reason: bad);
        expect(r.error, isNotEmpty, reason: bad);
      }
    });
  });

  group('«من – إلى»', () {
    test('آخرٌ كامل أو رقمه الأخير وحده', () {
      expect(span(parseScanFromTo('10.10.10.2', '10.10.10.20')), '10.10.10.2-10.10.10.20 19');
      expect(span(parseScanFromTo('10.10.10.2', '20')), '10.10.10.2-10.10.10.20 19');
      expect(span(parseScanFromTo('10.10.10.2', '2')), '10.10.10.2-10.10.10.2 1');
    });
    test('عبر أكثر من ‎/24‎ — ما كان ممكناً قبل', () {
      final r = parseScanFromTo('10.10.10.200', '10.10.12.10').range!;
      expect(r.count, 323);
      expect(r.ips.first, '10.10.10.200');
      expect(r.ips[56], '10.10.11.0');
      expect(r.ips.last, '10.10.12.10');
    });
    test('الأسباب: فارغ، ناقص، معكوس، كبير', () {
      expect(parseScanFromTo('', '20').error, contains('أوّل عنوان'));
      expect(parseScanFromTo('10.10.10', '20').error, contains('أوّل عنوان غير صحيح'));
      expect(parseScanFromTo('10.10.10.2', '').error, contains('آخر عنوان'));
      expect(parseScanFromTo('10.10.10.2', '300').error, contains('آخر عنوان غير صحيح'));
      expect(parseScanFromTo('10.10.10.20', '10.10.10.2').error, contains('أكبر من آخره'));
      expect(parseScanFromTo('10.10.0.1', '10.10.9.1').error, contains('${ScanRange.maxCount}'));
    });
  });

  test('الترتيب بالعنوان كاملاً لا بجزئه الأخير', () {
    final ips = ['10.0.2.1', '10.0.1.200', '10.0.1.3'];
    ips.sort((a, b) => ScanRange.sortKey(a).compareTo(ScanRange.sortKey(b)));
    expect(ips, ['10.0.1.3', '10.0.1.200', '10.0.2.1']);
  });
}
