import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/ubnt_api.dart';

/// تحليل خرج `mca-status`.
///
/// ⚠️ العيّنة أدناه منسوخة من سجلّ جهاز حقيقي (airOS 6.1.7 على XW).
/// السطر الأوّل **مضغوط بفواصل** — وقسمة السطر على أوّل `=` وحدها
/// تجعله مفتاحاً واحداً قيمتُه الباقي كلّه، فيضيع `platform` وهو
/// الطراز الذي تُطابَق به صورة الجهاز. (بلاغ: صور UBNT لا تظهر)
void main() {
  const sample = '''
deviceName=Wi-Fi Aljuzurah(4),deviceId=F0:9F:C2:9C:36:24,firmwareVersion=XW.ar934x.v6.1.7-licensed.32555.180523.1625,platform=NanoStation M5,deviceIp=10.102.157.5

apMac=F0:9F:C2:9C:36:24
wlanOpmode=ap
essid=Wi-Fi Aljazra(4) 07808812101
signal=-55
noise=-85
ccq=973
lanSpeed=100Mbps-Full
''';

  test('platform يُستخرج من السطر المضغوط', () {
    final m = UbntApi.parseMcaStatusForTest(sample);
    expect(m['platform'], 'NanoStation M5');
    expect(m['deviceId'], 'F0:9F:C2:9C:36:24');
    expect(m['deviceName'], 'Wi-Fi Aljuzurah(4)');
    expect(m['firmwareVersion'],
        'XW.ar934x.v6.1.7-licensed.32555.180523.1625');
  });

  test('الأسطر العاديّة تمرّ كما هي', () {
    final m = UbntApi.parseMcaStatusForTest(sample);
    expect(m['signal'], '-55');
    expect(m['ccq'], '973');
    // قيمة فيها مسافات تبقى كاملة
    expect(m['essid'], 'Wi-Fi Aljazra(4) 07808812101');
    expect(m['lanSpeed'], '100Mbps-Full');
  });

  test('خرج فارغ لا يرمي', () {
    expect(UbntApi.parseMcaStatusForTest(''), isEmpty);
  });
}
