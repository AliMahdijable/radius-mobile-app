// عمليّات الراوتر (١٢ نوفمبر): واي فاي Tenda (القراءة وجسم الحفظ كـgetSubmitData في صفحته)، شروط كلمة سرّ الواي فاي، معدّل
// الترافيك من عدّادين، وعناوين «الجهاز الثاني» (IP · IP:منفذ · :منفذ). أسماءٌ وكلماتٌ وهميّة.
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/device_config_api.dart';
import 'package:rad_mysvcs/api/device_probe_api.dart';
import 'package:rad_mysvcs/core/net/router_ops.dart';
import 'package:rad_mysvcs/core/net/router_types.dart';
import 'package:rad_mysvcs/core/net/tenda_service.dart';
import 'package:rad_mysvcs/core/net/tplink_classic_service.dart';
import 'package:rad_mysvcs/screens/subscribers/sheets/device_config_sheet.dart' show joinAddress, splitAddress;

void main() {
  _classic();
  group('Tenda — الواي فاي', () {
    const f3 = {'wifiEn': 'true', 'wifiSSID': 'Home-F3', 'wifiSecurityMode': 'WPA/AES', 'wifiPwd': 'old-pass-1', 'wifiHideSSID': 'false', 'HasDoubleBandUnity': 'false'};
    test('F3 بنطاقٍ واحد: شبكةٌ واحدة بكلمة سرّها', () {
      final w = TendaWifi.parse(Map<String, dynamic>.from(f3));
      expect(w.map((e) => [e.band, e.ssid, e.password, e.enabled, e.security, e.canChange]).toList(), [
        ['', 'Home-F3', 'old-pass-1', true, 'WPA', true],
      ]);
    });
    test('جسم الحفظ: module1=wifiBasicCfg ثمّ الحقول المقروءة كما هي وكلمة السرّ الجديدة (encodeURIComponent)، بلا حقول التوحيد', () {
      expect(TendaWifi.submit(Map<String, dynamic>.from(f3), 'n&ew pass'),
          'module1=wifiBasicCfg&wifiEn=true&wifiSSID=Home-F3&wifiSecurityMode=WPA%2FAES&wifiPwd=n%26ew%20pass&wifiHideSSID=false');
    });
    test('شبكةٌ مفتوحة: لا كلمة سرّ تُعرض ولا شيء يُرسل', () {
      final open = {...f3, 'wifiSecurityMode': 'none'};
      expect(TendaWifi.parse(Map<String, dynamic>.from(open)).single.password, isNull);
      expect(TendaWifi.submit(Map<String, dynamic>.from(open), 'abcdefgh'), isNull);
    });
    test('نطاقان بلا توحيد: 2.4G و5G كلٌّ بكلمته، والحفظ يغيّر الاثنين', () {
      final dual = {
        ...f3, 'HasDoubleBandUnity': 'true', 'doubleBandUnityEnable': 'false', 'wifiTotalEn': 'true',
        'wifiEn_5G': 'true', 'wifiSSID_5G': 'Home-5G', 'wifiSecurityMode_5G': 'WPA2/AES', 'wifiPwd_5G': 'old5', 'wifiHideSSID_5G': 'false',
      };
      final w = TendaWifi.parse(Map<String, dynamic>.from(dual));
      expect(w.map((e) => [e.band, e.ssid, e.password]).toList(), [
        ['2.4G', 'Home-F3', 'old-pass-1'],
        ['5G', 'Home-5G', 'old5'],
      ]);
      final body = TendaWifi.submit(Map<String, dynamic>.from(dual), 'newpass1')!;
      expect(body, contains('doubleBandUnityEnable=false'));
      expect(body, contains('wifiPwd=newpass1'));
      expect(body, contains('wifiPwd_5G=newpass1'));
      expect(body, contains('wifiSSID_5G=Home-5G'));
    });
    test('توحيد النطاقين: شبكةٌ واحدة، و5G نسخة 2.4G في الحفظ (كما تفعل الصفحة)', () {
      final unity = {
        ...f3, 'HasDoubleBandUnity': 'true', 'doubleBandUnityEnable': 'true', 'wifiTotalEn': 'true',
        'wifiEn_5G': 'true', 'wifiSSID_5G': 'Home-F3', 'wifiSecurityMode_5G': 'WPA/AES', 'wifiPwd_5G': 'old-pass-1', 'wifiHideSSID_5G': 'false',
      };
      final w = TendaWifi.parse(Map<String, dynamic>.from(unity));
      expect(w.single.band, '2.4G/5G');
      final body = TendaWifi.submit(Map<String, dynamic>.from(unity), 'newpass1')!;
      expect(body, contains('wifiPwd_5G=newpass1'));
      expect(body, contains('wifiSSID_5G=Home-F3'));
    });
  });

  test('كلمة سرّ الواي فاي: ٨–٦٣ حرفاً من ASCII المطبوع', () {
    expect(wifiPasswordProblem('1234567'), isNotNull);
    expect(wifiPasswordProblem('12345678'), isNull);
    expect(wifiPasswordProblem('a' * 63), isNull);
    expect(wifiPasswordProblem('a' * 64), isNotNull);
    expect(wifiPasswordProblem('كلمة سر عربية'), isNotNull);
    expect(wifiPasswordProblem('pass word!@#'), isNull);
  });

  test('المعدّل من عدّادين: بت/ثانية، ولا معدّل لعدّادٍ رجع (إقلاع) أو زمنٍ قصير', () {
    final t0 = DateTime(2026, 11, 12, 5);
    final a = RouterSample(rxBytes: 1000, txBytes: 500, at: t0);
    final b = RouterSample(rxBytes: 126000, txBytes: 13000, at: t0.add(const Duration(seconds: 2)));
    expect(routerRate(a, b), (down: 500000, up: 50000));
    expect(routerRate(b, a), isNull);
    expect(routerRate(a, RouterSample(rxBytes: 2000, txBytes: 600, at: t0.add(const Duration(milliseconds: 100)))), isNull);
  });

  test('عائلةٌ بلا عمليّةٍ مبنيّة: لا زرّ، وطلبها «لا يدعمها بعد»', () async {
    expect(RouterOps.canWifi('tpmer'), isTrue);
    expect(RouterOps.canWifi('tenda'), isTrue);
    expect(RouterOps.canReboot('ubnt'), isFalse);
    final r = await RouterOps.readWifi('ubnt', 'h', 'u', 'p');
    expect(r.fail, RouterFail.unsupported);
    final bad = await RouterOps.setWifiPassword('tpmer', 'h', 'u', 'p', 'short');
    expect(bad.fail, RouterFail.failed, reason: 'كلمةٌ مرفوضة لا تُرسل أبداً');
  });

  group('الجهاز الثاني — العناوين', () {
    test('addressOf: فارغ ⇒ آيبي الجلسة، «:منفذ» ⇒ الجلسة بالمنفذ، وغيره كما هو', () {
      expect(DeviceProbeApi.addressOf('100.66.1.5', null), '100.66.1.5');
      expect(DeviceProbeApi.addressOf('100.66.1.5', ':8080'), '100.66.1.5:8080');
      expect(DeviceProbeApi.addressOf('', ':8080'), '');
      expect(DeviceProbeApi.addressOf('100.66.1.5', '10.0.0.9'), '10.0.0.9');
      expect(DeviceProbeApi.addressOf('100.66.1.5', '10.0.0.9:81'), '10.0.0.9:81');
    });
    test('حقلا الشاشة ⇔ العنوان', () {
      expect(joinAddress('', ''), (value: null, error: null));
      expect(joinAddress('', '8080'), (value: ':8080', error: null));
      expect(joinAddress('010.0.0.9', ''), (value: '10.0.0.9', error: null));
      expect(joinAddress('١٠٫٠٫٠٫٩', '81'), (value: '10.0.0.9:81', error: null));
      expect(joinAddress('10.0.0', '').error, isNotNull);
      expect(joinAddress('10.0.0.9', '70000').error, isNotNull);
      expect(splitAddress(':8080'), (ip: '', port: '8080'));
      expect(splitAddress('10.0.0.9:81'), (ip: '10.0.0.9', port: '81'));
      expect(splitAddress('10.0.0.9'), (ip: '10.0.0.9', port: ''));
    });
    test('الإعداد: حقول الجهاز الثاني من الخادم وإليه، وإعداده بشكل إعدادٍ عاديّ', () {
      final c = DeviceConfig.fromJson({'customIp': '', 'secondAddress': ':8080', 'secondUsername': 'admin', 'secondPassword': 'x1'});
      expect([c.hasSecond, c.isEmpty, c.asSecond.customIp, c.asSecond.username, c.asSecond.password, c.asSecond.deviceType],
          [true, false, ':8080', 'admin', 'x1', null]);
      final j = const DeviceConfig(notes: 'n').toPutJson();
      expect([j['secondAddress'], j['secondUsername'], j['secondPassword']], ['', '', ''], reason: 'تُرسل دائماً — فراغها مسح');
      expect(const DeviceConfig().isEmpty, isTrue);
    });
  });
}

// TP-Link الكلاسيكيّ (WR940N): مصفوفات صفحة WlanSecurityRpm بشكلها الحيّ (قيمٌ وهميّة).
const _secPage = '''<SCRIPT language="javascript" type="text/javascript">
var wlanPara = new Array(
8, 1, 3, "332", 1, 0, "", 1812, "", "old pass 1", 1, 0, 0, 1, 3, 0, 0, 0, 6, 0, 1, "", 0, 0, 0 );
</SCRIPT>
<SCRIPT language="javascript" type="text/javascript">
var wlanList = new Array(
"", 0, "", 0, "", 0, "", 0, 0, 0 );
</SCRIPT>
<SCRIPT language="javascript" type="text/javascript">
var ssidList = new Array(
"Home-WR940", 0, 0 );
</SCRIPT>''';

void _classic() {
  group('TP-Link الكلاسيكيّ — الواي فاي', () {
    test('القراءة: الاسم من ssidList وكلمة السرّ wlanPara[9] لـWPA/WPA2-Personal (secType 3)', () {
      final w = TpClassicParse.wifi(_secPage)!;
      expect(w.map((e) => [e.ssid, e.password, e.security, e.canChange]).toList(), [
        ['Home-WR940', 'old pass 1', 'WPA2', true],
      ]);
      expect(TpClassicParse.wifiNeedsReboot(_secPage), isFalse);
      expect(TpClassicParse.wifiNeedsReboot(_secPage.replaceFirst('3, 0, 0, 0, 6', '3, 0, 1, 0, 6')), isTrue);
    });
    test('استعلام «Save»: حقول النموذج بقيمها المقروءة (wlanPara/wlanList) وكلمة السرّ الجديدة وحدها تتغيّر', () {
      expect(TpClassicParse.wifiSaveQuery(_secPage, 'n&ew pass'),
          'vapIdx=&wepSecOpt=3&keytype=1&keynum=1&key1=&length1=0&key2=&length2=0&key3=&length3=0&key4=&length4=0'
          '&wpaSecOpt=3&wpaCipher=1&radiusIp=&radiusPort=1812&radiusSecret=&intervalWpa=0&secType=3&pskSecOpt=2&pskCipher=3'
          '&pskSecret=n%26ew+pass&interval=0&Save=Save');
    });
    test('أمانٌ غير Personal (مطفأ/WEP/Enterprise): لا كلمة تُعرض ولا حفظ', () {
      final open = _secPage.replaceFirst('8, 1, 3, "332"', '8, 1, 0, "332"');
      expect(TpClassicParse.wifi(open)!.single.password, isNull);
      expect(TpClassicParse.wifiSaveQuery(open, 'abcdefgh'), isNull);
      expect(TpClassicParse.wifi('<html>no arrays</html>'), isNull);
    });
  });
}
