import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// فحص أجهزة SNMP — بلاغ ٢٠٢٦-٠٩-٠٢: «كلّ الميموسات ما تشتغل».
///
/// السبب أنّ **١٦١ منفذ UDP**، وفحص TCP عليه يُردّ بـ`Connection
/// refused` دائماً — لا لأنّ الجهاز ساقط بل لأنّه لا يستمع بـTCP
/// أصلاً. ٣٠ جهازاً من ٣١ كانت تُعرَض «غير متّصل» أبداً.
void main() {
  late String api;
  late String wall;
  late String devices;

  setUpAll(() {
    api = File('lib/api/network_devices_api.dart').readAsStringSync();
    wall = File('lib/screens/network_devices/devices_wall_screen.dart')
        .readAsStringSync();
    devices = File('lib/screens/network_devices/network_devices_screen.dart')
        .readAsStringSync();
  });

  group('١٦١ لا يُفحَص بـTCP', () {
    test('🚨 المنفذ ١٦١ يُحوَّل إلى SNMP قبل أيّ فحص TCP', () {
      final iSnmp = api.indexOf('if (tcpPort == 161)');
      final iTcp = api.indexOf('if (tcpPort != null && tcpPort > 0)');
      expect(iSnmp, greaterThan(0), reason: 'لا مسار SNMP');
      expect(iSnmp, lessThan(iTcp),
          reason: 'فرع TCP يسبق فرع SNMP — يبتلع ١٦١ ويعيد refused دائماً');
    });

    test('الفحص استعلام SNMP حقيقيّ لا ICMP', () {
      // ICMP يقول «العنوان يردّ»؛ وSNMP يقول «الخدمة حيّة والـcommunity
      // صحيحة» — وهو ما يعني «الجهاز يعمل» فعلاً.
      expect(api.contains('_snmpProbe('), isTrue);
      expect(api.contains("_oidSysUpTime = '1.3.6.1.2.1.1.3.0'"), isTrue,
          reason: 'أخفّ استعلام قياسيّ تدعمه كلّ أجهزة SNMP');
      expect(api.contains('SnmpV2c('), isTrue);
    });

    test('الـcommunity المخزَّنة تُستعمل لا الافتراضيّة وحدها', () {
      // من غيّر الـcommunity عن «public» كان يبدو ساقطاً أبداً.
      expect(api.contains("creds['community']"), isTrue);
      expect(api.contains('snmpCommunity: community'), isTrue);
    });

    test('فشل جلب البيانات لا يمنع الفحص', () {
      final i = api.indexOf('static Future<({String status, int? responseMs, '
          'double? packetLoss})>\n      probeDevice(');
      expect(i, greaterThan(0));
      final body = api.substring(i, api.indexOf('/// `sysUpTime.0`', i));
      expect(body.contains('} catch (_) {'), isTrue,
          reason: 'خطأ في /credentials يجب ألّا يُسقط الجهاز إلى offline');
    });
  });

  group('نقطة واحدة لاختيار الطريقة', () {
    test('🚨 لا شاشة تختار المنفذ بنفسها', () {
      // كانت الشاشتان تكتبان `tcpPort: d.apiPort ?? d.port` كلٌّ على
      // حدة — فحين اتّضح أنّ ١٦١ UDP كان لا بدّ من إصلاح موضعين، وهو
      // بالضبط ما يجعل أحدهما يُنسى.
      for (final e in {'نظرة عامّة': wall, 'قائمة الأجهزة': devices}.entries) {
        expect(e.value.contains('tcpPort: d.apiPort ?? d.port'), isFalse,
            reason: '${e.key} ما زالت تختار المنفذ بنفسها');
        expect(e.value.contains('NetworkDevicesApi.probeDevice(d)'), isTrue,
            reason: '${e.key} لا تمرّ بالنقطة الموحّدة');
      }
    });
  });
}
