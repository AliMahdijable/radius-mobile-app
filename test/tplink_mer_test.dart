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

  test('الردّ: رمز الخطأ في السطر الأوّل (والحالة قبل الدخول تأتي بـ401 وجسمها كهذا)، والأسطر بعده بلا ذيلٍ فارغ', () {
    final pre = MerParse.split('00007\r\n00004\r\n00000\r\nKEY\r\nDICT\r\n00001\r\n')!;
    expect(pre.code, 7);
    expect(pre.lines, ['00004', '00000', 'KEY', 'DICT', '00001']);
    expect(MerParse.split('00000\r\n')?.code, 0);
    expect(MerParse.split('<html>oops</html>'), isNull);
  });

  const read = 'id 0|1,0,0\r\nmodelName Archer C64\r\nhardVer Archer C64 1.0\r\nsoftVer 1.11.4 Build 230602\r\n'
      'id 22|1,0,0\r\nlinkType pppoe\r\n'
      'id 23|1,0,0\r\nip 100.66.1.10\r\nstatus 1\r\nupTime 12345\r\ninRates 1250\r\noutRates 125\r\n'
      'id 113|1,0,0\r\nmac AA-BB-CC-00-01-01\r\nname Phone-A\r\nmac AA-BB-CC-00-01-02\r\nname --\r\n'
      'id 9|1,0,0\r\nhostName Phone-A\r\nmac AA-BB-CC-00-01-01\r\nip 192.168.0.10\r\nhostName Laptop-B\r\nmac AA-BB-CC-00-01-02\r\nip 192.168.0.11\r\n';

  test('الكتل: «id» يفتح كتلة، والأسماء المتكرّرة قوائم، و«name[i]» قائمةٌ كذلك', () {
    final b = MerParse.blocks(read);
    expect(b.keys.toSet(), {'0', '22', '23', '113', '9'});
    expect(b['113']!['mac'], ['AA-BB-CC-00-01-01', 'AA-BB-CC-00-01-02']);
    expect(b['23']!['upTime'], '12345');
    final idx = MerParse.blocks('id 9|1,0,0\r\nmac[0] A\r\nmac[1] B\r\n');
    expect(idx['9']!['mac'], ['A', 'B']);
  });

  test('الحالة: المتّصلون من إحصاءات الوايرلس مُثرَون بإيجارات DHCP، مدّة الاتّصال، PPPoE، الطراز؛ والترافيك بايت/ث ⇒ بت/ث', () {
    final s = MerParse.status(MerParse.blocks(read), baseUrl: 'https://h:8443')!;
    expect([s.vendor, s.isRouter, s.peerCount, s.dhcpCount, s.wanOnlineSeconds, s.wanType, s.model, s.firmware],
        ['tpmer', true, 2, 2, 12345, 'PPPoE', 'Archer C64 1.0', '1.11.4 Build 230602']);
    expect(s.clients.map((c) => [c.mac, c.name, c.ip]).toList(), [
      ['AA-BB-CC-00-01-01', 'Phone-A', '192.168.0.10'],
      ['AA-BB-CC-00-01-02', 'Laptop-B', '192.168.0.11'],
    ]);
    expect(MerParse.rates(MerParse.blocks(read)), (down: 10000, up: 1000));
    expect(MerParse.status(const {}, baseUrl: 'h'), isNull);
  });
}
