// راوتر TP-Link بواجهة «$.su» وبروتوكول MER (Archer C64 وأخواته — قِيس من كود الجهاز نفسه ١٢ نوفمبر): رمز الدخول
// (`$.su.encrypt` — securityEncode) بمتّجهاتٍ من منفذٍ مستقلّ للدالّة نفسها، والأوّل هو متّجه TP-Link المعروف («admin» ⇒ WaQ7xbhc9TefbwK)،
// وقرّاء الردود (رمز الخطأ والكتل والقوائم والحالة والترافيك). أسماءٌ وماكاتٌ وهميّة.
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/core/net/tplink_mer_service.dart';

const _dict = 'yLwVl0zKqws7LgKPRQ84Mdt708T1qQ3Ha7xv3H7NyU84p21BriUWBU43odz3iP4rBL3cD02KZciXTysVXiV8ngg6vL48rPJyAUw0HurW20xqxv9aYb4M9wK1Ae0wlro510qXeU07kV57fQMc8L6aLgMLwygtc0F10a0Dg70TOoouyFhdysuRMO51yY5ZlOZZLEal1h0t9YQW0Ko7oBwmCAHoic4HYbUyVeU3sfQ1xtXcPcf1aT303wAQhv66qzW';

void main() {
  test('securityEncode = \$.su.encrypt حرفاً: متّجه TP-Link المعروف، وكلمة سرٍّ أطول من المفتاح، ومفتاحٌ أطول', () {
    expect(MerParse.securityEncode('RDpbLfCPsJZ7fiv', 'admin', _dict), 'WaQ7xbhc9TefbwK');
    expect(MerParse.securityEncode('short', 'a-much-longer-test-password', _dict), '80wK7mMoCAYUYM7U97MW4990CYy');
    expect(MerParse.securityEncode(r'GK>ps(Xi2B>ql1$x[lAe41x[9ba|j(Lg', 'abc123XYZ', _dict), '7UPLL1yr2vUQo51lVo6Uc5lVqc4tBaQY');
    expect(MerParse.securityEncode('k', 'p', ''), '');
  });

  test('رمز الدخول بطبقتي الصفحة: doEncrypt() بالمفتاح والقاموس الافتراضيّين ثمّ مفتاح الجلسة وقاموسها — متّجهاتٌ من دالّة الجهاز نفسها', () {
    // حُسبت بتشغيل `$.su.encrypt` من tpEncrypt.new.js المنزَّل من الجهاز على مفتاحٍ وقاموسٍ وكلمات سرٍّ وهميّة (١٢ نوفمبر).
    const key = r'Qw3>ps(Xi2B>ql1$x[lAe41x[9ba|j(L';
    final dict = String.fromCharCodes(List.generate(255, (i) => 33 + ((i * 37 + 11) % 94)));
    expect(MerParse.defaultDict, _dict);
    expect(MerParse.securityEncode('test-pass-1', MerParse.defaultKey, MerParse.defaultDict), '77VtUtxvyWqfbwK');
    expect(MerParse.loginToken(key, dict, 'test-pass-1'), r':>s8asZ6Hs3hYg.cs<gRPGJs<<SxKE}A');
    expect(MerParse.loginToken(key, dict, 'abc'), r'N>se+m>AZ:MhYg.cs<gRPGJs<<SxKE}A');
    expect(MerParse.loginToken(key, dict, 'a-much-longer-test-password-123'), r"N'b_l0mGVQ4&fr`Yc\+j!7:LVvgJqfOA");
    // الطبقة الواحدة (خطأ النسخة الأولى) تعطي رمزاً آخر
    expect(MerParse.securityEncode(key, 'test-pass-1', dict), isNot(MerParse.loginToken(key, dict, 'test-pass-1')));
  });

  test('الردّ: رمز الخطأ في السطر الأوّل (والحالة قبل الدخول تأتي بـ401 وجسمها كهذا)، والأسطر بعده بلا ذيلٍ فارغ', () {
    final pre = MerParse.split('00007\r\n00004\r\n00000\r\nKEY\r\nDICT\r\n00001\r\n')!;
    expect(pre.code, 7);
    expect(pre.lines, ['00004', '00000', 'KEY', 'DICT', '00001']);
    expect(MerParse.split('00000\r\n')?.code, 0);
    expect(MerParse.split('<html>oops</html>'), isNull);
  });

  // الشكل الحيّ (C64، ١٢ نوفمبر): القوائم «اسم فهرس قيمة»، والقيمة الفارغة «اسم فهرس» وحده؛ جدول المحطّات ثابت الطول ينتهي بخاناتٍ فارغة.
  const read = 'id 0|1,0,0\r\nmodelName Archer C64\r\nhardVer Archer C64 1.0\r\nsoftVer 1.11.4 Build 230602\r\n'
      'id 22|1,0,0\r\nenable 1\r\nlinkType pppoe\r\n'
      'id 23|1,0,0\r\nip 100.66.1.10\r\ndns 0 8.8.8.8\r\ndns 1 1.1.1.1\r\nstatus 1\r\nupTime 12345\r\ninOctets 1000000\r\noutOctets 50000\r\n'
      'id 13|1,0,0\r\n'
      'ip 0 192.168.0.10\r\nip 1 192.168.0.11\r\nip 2 192.168.0.12\r\nip 3 192.168.0.13\r\nip 4 0.0.0.0\r\n'
      'mac 0 aa-bb-cc-00-01-01\r\nmac 1 AA-BB-CC-00-01-02\r\nmac 2 AA-BB-CC-00-01-03\r\nmac 3 AA-BB-CC-00-01-04\r\nmac 4 00-00-00-00-00-00\r\n'
      'type 0 1\r\ntype 1 0\r\ntype 2 2\r\ntype 3 1\r\ntype 4 0\r\n'
      'online 0 1\r\nonline 1 1\r\nonline 2 0\r\nonline 3 1\r\nonline 4 0\r\n'
      'blocked 0 0\r\nblocked 1 0\r\nblocked 2 0\r\nblocked 3 1\r\nblocked 4 0\r\n'
      'name 0 Phone%20A\r\nname 1\r\nname 2 Old-TV\r\nname 3 Blocked-PC\r\nname 4\r\n';

  test('الكتل: «id» يفتح كتلةً بمعرّفها الكامل، و«اسم فهرس قيمة» قائمةٌ بمواضعها، والفارغة «اسم فهرس»، و«اسم[فهرس]» كذلك', () {
    final b = MerParse.blocks(read);
    expect(b.keys.toSet(), {'0|1,0,0', '22|1,0,0', '23|1,0,0', '13|1,0,0'});
    expect(MerParse.block(b, '13')['mac'], ['aa-bb-cc-00-01-01', 'AA-BB-CC-00-01-02', 'AA-BB-CC-00-01-03', 'AA-BB-CC-00-01-04', '00-00-00-00-00-00']);
    expect(MerParse.block(b, '13')['name'], ['Phone A', '', 'Old-TV', 'Blocked-PC', '']);
    expect(MerParse.block(b, '23')['dns'], ['8.8.8.8', '1.1.1.1']);
    expect(MerParse.block(b, '23')['upTime'], '12345');
    expect(MerParse.block(b, '0')['softVer'], '1.11.4 Build 230602', reason: 'قيمةٌ فيها مسافات وأوّلها رقمٌ بنقاط ليست فهرساً');
    final idx = MerParse.blocks('id 9|1,0,0\r\nmac[0] A\r\nmac[1] B\r\n');
    expect(MerParse.block(idx, '9')['mac'], ['A', 'B']);
    // الكتلة نفسها بطبقتين (2.4G و5G) لا تختلطان
    final two = MerParse.blocks('id 33|1,1,0\r\ncSsid Home\r\nid 33|2,1,0\r\ncSsid Home-5G\r\n');
    expect([two['33|1,1,0']!['cSsid'], two['33|2,1,0']!['cSsid']], ['Home', 'Home-5G']);
  });

  test('decodeURI كالصفحة: %XX يُفكّ إلّا المحجوز، والمعطوب يبقى', () {
    expect(MerParse.decodeUri('a%20b%C3%A9'), 'a bé');
    expect(MerParse.decodeUri('x%26y%2Fz'), 'x%26y%2Fz');
    expect(MerParse.decodeUri('100%'), '100%');
    expect(MerParse.decodeUri('%zz1'), '%zz1');
  });

  test('الحالة: المتّصلون الآن من جدول المحطّات (حتى أوّل خانةٍ فارغة، بلا المحجوب ولا غير المتّصل)، مدّة الاتّصال، PPPoE، الطراز', () {
    final s = MerParse.status(MerParse.blocks(read), baseUrl: 'https://h:8443')!;
    expect([s.vendor, s.isRouter, s.peerCount, s.dhcpCount, s.wanOnlineSeconds, s.wanType, s.model, s.firmware],
        ['tpmer', true, 2, null, 12345, 'PPPoE', 'Archer C64 1.0', '1.11.4 Build 230602']);
    expect(s.clients.map((c) => [c.mac, c.name, c.ip, c.wired]).toList(), [
      ['AA-BB-CC-00-01-01', 'Phone A', '192.168.0.10', false],
      ['AA-BB-CC-00-01-02', null, '192.168.0.11', true],
    ]);
    expect(MerParse.counters(MerParse.blocks(read)), (rx: 1000000, tx: 50000));
    expect(MerParse.status(const {}, baseUrl: 'h'), isNull);
  });

  test('الواي فاي: النطاقان، كلمة السرّ لأنماط PSK وحدها، المفتوحة بلا كلمة، وEnterprise بلا كلمة (سرّ RADIUS ليس كلمة الواي فاي)', () {
    final w = MerParse.wifi(MerParse.blocks('id 33|1,1,0\r\nbEnable 1\r\ncSsid Home\r\nSecurityType 3\r\ncPskSecret pass%20word1\r\ncRadiusSecret rr\r\n'
        'id 33|2,1,0\r\nbEnable 0\r\ncSsid Home-5G\r\nSecurityType 1\r\ncPskSecret old\r\n'));
    expect(w.map((e) => [e.band, e.ssid, e.password, e.enabled, e.security, e.ref, e.canChange]).toList(), [
      ['2.4G', 'Home', 'pass word1', true, 'WPA/WPA2', '1,1,0', true],
      ['5G', 'Home-5G', null, false, 'مفتوحة', '2,1,0', false],
    ]);
    final ent = MerParse.wifi(MerParse.blocks('id 33|1,1,0\r\nbEnable 1\r\ncSsid Corp\r\nSecurityType 6\r\ncRadiusSecret rr\r\n'));
    expect([ent.single.password, ent.single.security], [null, 'Enterprise']);
    // بلا SecurityType: bSecurityEnable/uAuthType كخريطة الشبكة في الصفحة
    final old = MerParse.wifi(MerParse.blocks('id 33|1,1,0\r\nbEnable 1\r\ncSsid A\r\nbSecurityEnable 1\r\nuAuthType 3\r\ncPskSecret k1234567\r\n'));
    expect(old.single.password, 'k1234567');
  });

  test('نصّ الكتابة: «id 33|طبقات» أوّلاً ثمّ cPskSecret مرمّزةً كـtoText في الصفحة (encodeURIComponent)', () {
    expect(MerParse.wifiPasswordWrite(['1,1,0', '2,1,0'], 'a b&c'),
        'id 33|1,1,0\r\ncPskSecret a%20b%26c\r\nid 33|2,1,0\r\ncPskSecret a%20b%26c\r\n');
  });
}
