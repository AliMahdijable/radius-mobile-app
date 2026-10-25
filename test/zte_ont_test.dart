import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/core/net/ont_traffic.dart';
import 'package:rad_mysvcs/core/net/zte_ont_service.dart';
import 'package:rad_mysvcs/models/device_health.dart';

/// جهاز المشترك ZTE MH80 (ZXIC، EPON) — المالك ٢٥ أكتوبر: «نعرض المعلومات مال جهاز الضوئي للمشتركين وكذلك الترفك».
/// المقتطفات ببنية صفحات الجهاز الحقيقيّة (مستكشَفة حيّاً للقراءة فقط) وبقيمٍ محايدة.
const _loginPage = '''
<title>MH80</title>
<form name="fLogin" id="fLogin" method="post" onsubmit="return false;">
<input type="hidden" name="Frm_Logintoken" id="Frm_Logintoken" value="">
</form>
<script>
function dosubmit()
{
{
getObj("LoginId").disabled = true;

getObj("Frm_Logintoken").value = "3";
document.fLogin.submit();
}
}
</script>
''';

String _opticalPage({String los = '0'}) => '''
<title>MH80</title>
<td id="Frm_RxPower" name="Frm_RxPower" class="tdright">
<font id="Fnt_RxPower" name="Fnt_RxPower"></font>
</td>
<td id="Frm_Volt" name="Frm_Volt" class="tdright">3244000</td>
<td id="Frm_Current" name="Frm_Current"  class="tdright"></td>
<td id="Frm_Temp" name="Frm_Temp" class="tdright">41</td>
<SCRIPT>
function doRxTxPowerShow()
{
var LosInfo = "$los";
var RxPower = "-186300";
var TxPower = "25900";
var Current =  "13850";
}
</SCRIPT>
''';

String _lanRow(int row, String name, String state, int rx, int tx) => '''
var tblObj = getObj("Table_laninterface");
var RowNum = $row+3;
getObj("Table_laninterface_"+ RowNum +"_1_table").innerHTML = "$name";
getObj("Table_laninterface_"+ RowNum +"_2_table").innerHTML = "Half Duplex";
getObj("Table_laninterface_"+ RowNum +"_3_table").innerHTML = "Auto";
getObj("Table_laninterface_"+ RowNum +"_4_table").innerHTML = "$state";
getObj("Table_laninterface_"+ RowNum +"_5_table").innerHTML = "$rx";
getObj("Table_laninterface_"+ RowNum +"_6_table").innerHTML = "0";
getObj("Table_laninterface_"+ RowNum +"_7_table").innerHTML = "$tx";
getObj("Table_laninterface_"+ RowNum +"_8_table").innerHTML = "133208";
''';

String _wlanRow(int idx, String ssid, int rx, int tx) => '''
var RowNum = $idx+2;
getObj("Table_wlanstat_"+ RowNum +"_1_table").innerHTML = "$idx";
getObj("Table_wlanstat_"+ RowNum +"_2_table").innerHTML = "$ssid";
getObj("Table_wlanstat_"+ RowNum +"_3_table").innerHTML = "$rx";
getObj("Table_wlanstat_"+ RowNum +"_4_table").innerHTML = "9567287";
getObj("Table_wlanstat_"+ RowNum +"_5_table").innerHTML = "$tx";
getObj("Table_wlanstat_"+ RowNum +"_6_table").innerHTML = "18249482";
''';

void main() {
  group('التعرّف والدخول', () {
    test('ZTE بترويسة خادمه أو بصفحة دخوله؛ وهواوي ليس ZTE', () {
      expect(ZteOntParse.isZte('Mini web server 1.0 ZTE corp 2005.', ''), isTrue);
      expect(ZteOntParse.isZte(null, _loginPage), isTrue);
      expect(ZteOntParse.isZte('', "<html><script>var pageName = 'index.asp';</script></html>"), isFalse);
    });

    test('رمز النموذج من سكربت الصفحة («3»)، وصفحة الدخول تُعرف حين تنتهي الجلسة', () {
      expect(ZteOntParse.loginToken(_loginPage), '3');
      expect(ZteOntParse.isLoginPage(_loginPage), isTrue);
      expect(ZteOntParse.isLoginPage(_opticalPage()), isFalse);
    });
  });

  group('الضوء بوحدات هواوي نفسها', () {
    test('القدرة ÷١٠٠٠٠ dBm، والجهد µV⇒mV، والتيّار µA⇒mA، والحرارة °C، والطراز من العنوان', () {
      final o = ZteOntParse.optical(_opticalPage())!;
      expect(o.rxPower, '-18.6');
      expect(o.txPower, '2.6');
      expect(o.voltage, '3244');
      expect(o.temperature, '41');
      expect(double.parse(o.bias), closeTo(13.85, 0.06));
      expect(o.sendStatus, '', reason: 'لا حالة ليفٍ تُخترع والضوء سليم');
      expect(o.isZte, isTrue);
      expect(o.model, 'MH80');
      // مؤشّرات «جيّد/سيّئ» نفسها تعمل على القيم المحوّلة
      expect([o.rxOk, o.txOk, o.voltageOk, o.tempOk, o.biasOk], everyElement(isTrue));
    });

    test('LosInfo=1 (لا ضوء) ⇒ القدرتان «--» والليف «LOS» — لا قراءةٌ قديمة كأنّها حيّة', () {
      final o = ZteOntParse.optical(_opticalPage(los: '1'))!;
      expect([o.rxPower, o.txPower], ['--', '--']);
      expect(o.sendStatus, 'LOS');
      expect(o.rxOk, isFalse);
    });

    test('صفحةٌ بلا قدرة استقبال ليست صفحة ضوء ⇒ null', () {
      expect(ZteOntParse.optical('<title>MH80</title><p>no optics</p>'), isNull);
    });

    test('المورّد والطراز يُحفظان ويعودان، والمخزَّن القديم بلا مورّد ⇒ هواوي', () {
      final o = ZteOntParse.optical(_opticalPage())!;
      final back = OntOpticalInfo.fromJson(o.toJson());
      expect([back.vendor, back.model, back.rxPower], ['zte', 'MH80', '-18.6']);
      final legacy = OntOpticalInfo.fromJson({'tx': '2.1', 'rx': '-20.0', 'v': '3300', 't': '45', 'b': '10', 's': ''});
      expect(legacy.vendor, 'huawei');
      expect(legacy.isZte, isFalse);
      expect(const OntOpticalInfo(txPower: '', rxPower: '', voltage: '', temperature: '', bias: '', sendStatus: '')
          .toJson()
          .containsKey('vd'), isFalse, reason: 'هواوي يُخزَّن كما كان حرفاً');
    });
  });

  group('عدّادات الترافيك', () {
    test('الواي فاي: لكلّ SSID المرسَل إلى العملاء (تحميل) والمستلَم منهم (رفع)', () {
      final html = _wlanRow(1, 'Home', 2026836195, 865242695) + _wlanRow(2, 'WIFI-SSID2', 0, 0) +
          _wlanRow(5, 'Home', 2145515077, 1747764052);
      final w = ZteOntParse.wifi(html);
      expect(w.keys, containsAll(['wlan1', 'wlan2', 'wlan5']));
      expect(w['wlan1'], (sent: 865242695, received: 2026836195));
      expect(w['wlan5']!.sent, 1747764052);
    });

    test('المنافذ: المرسَل والمستلَم بالبايت، و«موصول» من الحالة', () {
      final off = _lanRow(0, 'Network port1/WAN', 'Equipment disconnected', 0, 12342481) +
          _lanRow(1, 'Network port2', 'Equipment disconnected', 0, 12342399);
      final a = ZteOntParse.lan(off);
      expect(a.counters['lan:Network port1/WAN'], (sent: 12342481, received: 0));
      expect(a.counters.length, 2);
      expect(a.linked, isFalse);
      final on = _lanRow(0, 'Network port1', 'Equipment connected', 55, 66);
      expect(ZteOntParse.lan(on).linked, isTrue);
    });

    test('المعدّل: عدّاد ٣٢ بت غير مؤشَّر — تجاوز ٢^٣١ ليس التفافاً، والالتفاف عند ٢^٣٢ يُحسب', () {
      final m = OntTrafficMeter();
      final t0 = DateTime(2026, 10, 25, 20);
      final t1 = t0.add(const Duration(seconds: 10));
      OntByteCounters at(DateTime t, int sent, int recv) => OntByteCounters({'wlan5': (sent: sent, received: recv, at: t)});
      expect(m.add(at(t0, 2147000000, 4294000000), t0), isNull, reason: 'الأولى تزرع المرجع');
      final r = m.add(at(t1, 2148000000, 500000), t1)!;
      expect(r.downBps, 800000, reason: '١٠٠٠٠٠٠ بايت في ١٠ث = ٠٫٨ ميغابت');
      expect(r.upBps, ((500000 + 4294967296 - 4294000000) * 8 / 10).round(), reason: 'التفافٌ عند ٢^٣٢');
    });
  });
}
