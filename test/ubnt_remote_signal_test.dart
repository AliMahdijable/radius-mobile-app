import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/ubnt_api.dart';

/// 🐛 ٨ نوفمبر — المالك بنسخة الويندوز («الفحص الشامل»): «يطلع rx وليس الاشاره tx».
/// سكتر يوبيكويتي: إشارة المشترك من جهتنا (كيف يستقبلنا) في wstalist تحت `remote.signal` — ما يقرؤه جهاز المشترك نفسه.
/// كانت تُهمَل في القراءة المحلّيّة فيظهر ما يستقبله السكتر (rx) مكانها؛ الخادم (عبر الـVPN) يقرؤها منذ صباح ٨ نوفمبر.
void main() {
  UbntStats sector(List<Map<String, dynamic>> st) =>
      UbntStats.fromMcaStatus(const {'wlanOpmode': 'ap', 'signal': '-60'}, wstalistStations: st);

  test('remote.signal ⇒ إشارة المشترك (tx)، والـrx كما هو', () {
    final s = sector([
      {
        'mac': 'AA:BB:CC:00:00:01', 'lastip': '10.0.0.11', 'signal': -60, 'rssi': 36, 'noisefloor': -96, 'ccq': 95,
        'tx': 130, 'rx': 104, 'uptime': 3600,
        'remote': {'signal': -49, 'rssi': 47, 'noisefloor': -98, 'hostname': 'cpe-1'},
      },
    ]);
    final p = s.stations.single;
    expect(p.signal, -60, reason: 'ما يستقبله السكتر منه (rx)');
    expect(p.txSignal, -49, reason: 'ما يستقبله المشترك منّا (tx) — من جهازه');
  });

  test('بلا remote.signal ⇒ لا tx (لا رقم مخترع)، والمفاتيح القديمة تبقى أوّلاً', () {
    final s = sector([
      {'mac': 'AA:BB:CC:00:00:02', 'signal': -71, 'remote': {'hostname': 'x'}},
      {'mac': 'AA:BB:CC:00:00:03', 'signal': -65, 'remote_signal': -58, 'remote': {'signal': -40}},
      {'mac': 'AA:BB:CC:00:00:04', 'signal': -66, 'remote': {'signal': 12}},
    ]);
    expect(s.stations[0].txSignal, 0);
    expect(s.stations[1].txSignal, -58, reason: 'remote_signal (airOS 5/6) كما كان');
    expect(s.stations[2].txSignal, 0, reason: 'موجبٌ ليس إشارة بالـdBm');
  });
}
