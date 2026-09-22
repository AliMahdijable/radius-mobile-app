import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/network_devices_api.dart';

/// تمييز الصانع من ترويسة الخدمة.
///
/// 🐛 بلاغ المستخدم: «فحص الأجهزة ما يميّز السسكو — يظهره ubnt».
/// وكان محقّاً: الماسح يخمّن بالمنفذ وحده، و`22 => ubnt` تجعل كلّ
/// ما فتح SSH يوبيكيتي — وسويتشات سسكو منها.
void main() {
  group('ترويسة SSH', () {
    test('سسكو تُعرَف من ترويسة النسخة', () {
      // ملتقطة من جهاز حقيقي: WS-C2960-24TC-L
      expect(NetworkDevicesApi.brandFromBanner('SSH-2.0-Cisco-1.25\n'),
          'cisco');
    });

    test('راوتر أو إس', () {
      expect(NetworkDevicesApi.brandFromBanner('SSH-2.0-ROSSSH'), 'mikrotik');
    });

    test('ترويسة عامّة لا تحسم — يعود القرار للمنفذ', () {
      // dropbear وopenssh تشترك فيهما أجهزةٌ من صنّاع شتّى.
      expect(NetworkDevicesApi.brandFromBanner('SSH-2.0-dropbear_2019.78'),
          isNull);
      expect(NetworkDevicesApi.brandFromBanner('SSH-2.0-OpenSSH_8.4'), isNull);
      expect(NetworkDevicesApi.brandFromBanner(''), isNull);
    });
  });

  group('ترويسة Telnet', () {
    test('«User Access Verification» عبارة سسكو الكلاسيكيّة', () {
      // ملتقطة من جهاز حقيقي بعد إسقاط بايتات تفاوض IAC.
      const banner = '\r\n\r\nUser Access Verification\r\n\r\nUsername: ';
      expect(NetworkDevicesApi.brandFromBanner(banner), 'cisco');
    });
  });

  group('ترتيب منافذ المسح', () {
    test('منافذ الإدارة المميِّزة تسبق منافذ الويب العامّة', () {
      // 🐛 الانحدار: كان ٢٣ آخر القائمة بعد ٤٤٣ و٨٠. والماسح يتوقّف
      // عند **أوّل** منفذٍ مفتوح، والترويسة لا تُقرأ إلّا على ٢٢/٢٣.
      // فسويتش سسكو لا يفتح ٢٢ يفتح ٨٠ (‏IOS يشغّل `ip http server`
      // افتراضيّاً) فتتوقّف الحلقة قبل ٢٣ ولا تُقرأ ترويسة — فيُضاف
      // الجهاز «other» بنوع «other». هذا ما اشتكى منه المستخدم.
      const ports = NetworkDevicesApi.scanPorts;
      int at(int p) => ports.indexOf(p);

      expect(at(23), greaterThan(-1), reason: 'تلنت يجب أن يُفحَص');
      for (final generic in [443, 80, 161]) {
        if (at(generic) < 0) continue;
        expect(at(22), lessThan(at(generic)),
            reason: 'SSH يجب أن يسبق $generic');
        expect(at(23), lessThan(at(generic)),
            reason: 'Telnet يجب أن يسبق $generic');
      }
    });
  });

  group('التخمين الكامل', () {
    test('الترويسة تسبق المنفذ', () {
      final g = NetworkDevicesApi.guessDeviceFromPort(22,
          banner: 'SSH-2.0-Cisco-1.25');
      expect(g.brand, 'cisco');
      expect(g.protocol, 'ssh');
      expect(g.apiPort, 22);
    });

    test('سسكو على تلنت: البروتوكول telnet لا ssh', () {
      // 10.100.19.254 لا يفتح ٢٢ إطلاقاً — لو كتبنا ssh لفشل الاتّصال.
      final g = NetworkDevicesApi.guessDeviceFromPort(23,
          banner: 'User Access Verification\r\nUsername: ');
      expect(g.brand, 'cisco');
      expect(g.protocol, 'telnet');
      expect(g.apiPort, 23);
    });

    test('بلا ترويسة: السلوك القديم كما هو — لا انحدار', () {
      expect(NetworkDevicesApi.guessDeviceFromPort(22).brand, 'ubnt');
      expect(NetworkDevicesApi.guessDeviceFromPort(8728).brand, 'mikrotik');
      expect(NetworkDevicesApi.guessDeviceFromPort(23).brand, 'other');
    });
  });
}
