import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/screens/network_devices/devices_wall_screen.dart';

/// ترتيب «نظرة عامّة».
void main() {
  group('مفتاح ترتيب العنوان', () {
    test('🚨 رقميّ لا نصّيّ', () {
      // المقارنة النصّيّة تضع ‎.10 قبل ‎.9 لأنّ '1' يسبق '9' حرفيّاً.
      // والنتيجة قائمةٌ تبدو مرتّبةً وليست كذلك — أسوأ من غير المرتّبة
      // لأنّ العين تثق بها.
      expect('10.70.241.10'.compareTo('10.70.241.9'), lessThan(0),
          reason: 'هكذا يخطئ النصّ — الحارس تحته يمنعه');
      expect(ipSortKey('10.70.241.10'), greaterThan(ipSortKey('10.70.241.9')));
    });

    test('يرتّب شبكةً كاملة بالصواب', () {
      final ips = [
        '10.70.241.100',
        '10.70.241.2',
        '10.70.241.20',
        '10.70.241.9',
        '10.70.240.254',
      ]..sort((a, b) => ipSortKey(a).compareTo(ipSortKey(b)));
      expect(ips, [
        '10.70.240.254',
        '10.70.241.2',
        '10.70.241.9',
        '10.70.241.20',
        '10.70.241.100',
      ]);
    });

    test('الثمانيّة الثالثة تسبق الرابعة في الوزن', () {
      expect(ipSortKey('10.0.2.0'), greaterThan(ipSortKey('10.0.1.255')));
    });

    test('الحدود', () {
      expect(ipSortKey('0.0.0.0'), 0);
      expect(ipSortKey('255.255.255.255'), (1 << 32) - 1);
    });

    test('ما ليس IPv4 يُدفَع إلى الذيل ولا يرمي', () {
      // اسم مضيف أو IPv6 أو حقلٌ مشوّه — يجب ألّا يُسقط الشاشة.
      for (final bad in ['', 'router.local', '10.0.0', '10.0.0.1.5',
                         '10.0.0.256', '10.0.0.-1', 'fe80::1', '١٠.٠.٠.١']) {
        expect(ipSortKey(bad), greaterThan(ipSortKey('255.255.255.255')),
            reason: bad.isEmpty ? '(فارغ)' : bad);
      }
    });

    test('المسافات الزائدة لا تكسره', () {
      expect(ipSortKey(' 10.0.0.5 '), ipSortKey('10.0.0.5'));
    });
  });

  group('معايير الترتيب', () {
    test('ثلاثة، والحالة أوّلها', () {
      expect(WallSort.values.length, 3);
      expect(WallSort.values.first, WallSort.health,
          reason: 'الافتراضيّ — تفتح الصفحة لتجد العطل لا لتتصفّح');
      expect(WallSort.health.label, 'الحالة');
      expect(WallSort.name.label, 'الاسم');
      expect(WallSort.ip.label, 'العنوان');
    });
  });

  group('البنية', () {
    late String wall;
    late String devices;
    setUpAll(() {
      wall = File('lib/screens/network_devices/devices_wall_screen.dart')
          .readAsStringSync();
      devices = File('lib/screens/network_devices/network_devices_screen.dart')
          .readAsStringSync();
    });

    test('المناطق تتبع المعيار نفسه', () {
      // بطاقاتٌ مرتّبةٌ أبجديّاً داخل مناطق مرتّبةٍ بالأعطال تبدو عشوائيّة.
      expect(wall.contains('if (_sort == WallSort.health)'), isTrue);
      expect(wall.contains("a.region!.name.compareTo(b.region!.name)"), isTrue);
    });

    test('«بلا منطقة» تبقى في الذيل', () {
      // مجموعةٌ باقية لا اسمٌ يُرتَّب أبجديّاً.
      expect(wall.contains('if (a.region == null) return 1;'), isTrue);
    });

    test('التسمية «نظرة عامّة» في الشاشة ومدخلها', () {
      expect(wall.contains("Text('نظرة عامّة'"), isTrue);
      expect(devices.contains("tooltip: 'نظرة عامّة'"), isTrue);
      expect(wall.contains("'جدار الأجهزة'"), isFalse,
          reason: 'بقيت التسمية القديمة في نصّ واجهة');
    });
  });
}
