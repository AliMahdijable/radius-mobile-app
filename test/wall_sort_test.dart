import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/models/network_device.dart';
import 'package:rad_mysvcs/screens/network_devices/device_sort.dart';

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
      expect(DeviceSortField.values.length, 3);
      expect(DeviceSortField.values.first, DeviceSortField.health,
          reason: 'الافتراضيّ — تفتح الشاشة لتجد العطل لا لتتصفّح');
      expect(DeviceSortField.health.label, 'الحالة');
      expect(DeviceSortField.name.label, 'الاسم');
      expect(DeviceSortField.ip.label, 'العنوان');
    });
  });

  group('الاتّجاه', () {
    NetworkDevice d(String name, String ip, String status, {int? ms}) =>
        NetworkDevice(
          id: name.hashCode,
          adminId: '2',
          name: name,
          type: 'link',
          brand: 'ubnt',
          ip: ip,
          port: 80,
          hasCredentials: false,
          lastStatus: status,
          lastResponseMs: ms,
          createdAt: DateTime(2026),
        );

    final a = d('ألف', '10.0.0.2', 'online', ms: 5);
    final b = d('باء', '10.0.0.10', 'offline');

    test('تنازليّ يعكس تصاعديّ تماماً', () {
      for (final f in DeviceSortField.values) {
        final asc = compareDevices(a, b, f, SortDir.asc);
        final desc = compareDevices(a, b, f, SortDir.desc);
        expect(desc, -asc, reason: 'المعيار ${f.label}');
      }
    });

    test('تصاعديّ في «الحالة» = غير المتّصل أوّلاً', () {
      // الرتبة تصعد من صفر (ساقط) إلى اثنين (سليم).
      expect(compareDevices(b, a, DeviceSortField.health, SortDir.asc),
          lessThan(0),
          reason: 'الساقط يجب أن يسبق');
      expect(compareDevices(b, a, DeviceSortField.health, SortDir.desc),
          greaterThan(0));
    });

    test('تصاعديّ في «العنوان» = الأصغر أوّلاً', () {
      expect(compareDevices(a, b, DeviceSortField.ip, SortDir.asc),
          lessThan(0), reason: '.2 قبل .10');
    });

    test('🚨 ترتيب مستقرّ — لا قفز بين الجولات', () {
      // متساويان في المعيار: بلا فاصلٍ حاسم يتبدّل موضعاهما مع كلّ
      // فرزة، فتقفز البطاقتان أمام العين كلّ عشرين ثانية.
      final x = d('ألف', '10.0.0.5', 'online', ms: 7);
      final y = d('باء', '10.0.0.5', 'online', ms: 7);
      for (final f in DeviceSortField.values) {
        expect(compareDevices(x, y, f, SortDir.asc), isNot(0),
            reason: 'المعيار ${f.label} لا يفصل المتساويات');
      }
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
      expect(wall.contains('if (_sortField == DeviceSortField.health)'),
          isTrue);
      expect(wall.contains("a.region!.name.compareTo(b.region!.name)"), isTrue);
    });

    test('«بلا منطقة» تبقى في الذيل', () {
      // مجموعةٌ باقية لا اسمٌ يُرتَّب أبجديّاً.
      expect(wall.contains('if (a.region == null) return 1;'), isTrue);
    });

    test('🚨 لا نسختين من منطق الترتيب', () {
      // كانت القائمة تحمل `_compareIps` و«نظرة عامّة» تحمل `ipSortKey`
      // — دالّتان لمسألةٍ واحدة تنحرفان حتماً، فيرى المستخدم ترتيبين
      // مختلفين لنفس الأجهزة في شاشتين متجاورتين.
      expect(devices.contains('_compareIps'), isFalse);
      expect(wall.contains('int ipSortKey('), isFalse);
      for (final f in [devices, wall]) {
        expect(f.contains('compareDevices('), isTrue);
      }
    });

    test('القسم العامّ يرتّب باختيار المستخدم', () {
      expect(devices.contains('showDeviceSortSheet('), isTrue);
      expect(devices.contains('compareDevices(a, b, _sortField, _sortDir)'),
          isTrue);
    });

    test('التسمية «نظرة عامّة» في الشاشة ومدخلها', () {
      expect(wall.contains("Text('نظرة عامّة'"), isTrue);
      expect(devices.contains("tooltip: 'نظرة عامّة'"), isTrue);
      expect(wall.contains("'جدار الأجهزة'"), isFalse,
          reason: 'بقيت التسمية القديمة في نصّ واجهة');
    });
  });
}
