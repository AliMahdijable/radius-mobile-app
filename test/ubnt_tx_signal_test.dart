import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/ubnt_api.dart';

/// إشارة المشترك على السكتر (٨ نوفمبر — المالك مع صورتين لمشتركٍ واحد: كارت جهازه ‎-49 dBm وتنبيهه ‎-60: «الإشعارات للجهاز أو
/// الفحص مع الأجهزة أنت دائما تعتمد على الإشارة RX… المفروض بالعكس TX»): airOS يضع إشارة جهاز المشترك نفسه (كيف يستقبلنا) في
/// remote.signal — وهي التي يُحكم بها، وما يستقبله السكتر منه (rx) بجانبها.
void main() {
  test('airOS: remote.signal ⇒ txSignal (إشارة المشترك)، وsignal ما يستقبله السكتر', () {
    final s = UbntStats.fromMcaStatus(const {'deviceName': 'Sector-N'}, wstalistStations: [
      {
        'mac': 'AA:BB:CC:00:00:01',
        'lastip': '10.0.0.2',
        'signal': -60,
        'ccq': 94,
        'remote': {'signal': -49, 'hostname': 'Husein Alsaltany'},
      },
      {'mac': 'AA:BB:CC:00:00:02', 'lastip': '10.0.0.3', 'signal': -66, 'ccq': 90},
    ]);
    final a = s.stations.first;
    expect([a.signal, a.txSignal], [-60, -49]);
    expect(a.hostname, 'Husein Alsaltany');
    expect(s.stations.last.txSignal, 0, reason: 'بلا remote ⇒ لا TX (يُحكم بالـRX احتياطاً)');
  });
}
