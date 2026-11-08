import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/vpn_now_api.dart';
import 'package:rad_mysvcs/models/device_health.dart';
import 'package:rad_mysvcs/models/subscriber.dart';
import 'package:rad_mysvcs/services/connection_alerts.dart';
import 'package:rad_mysvcs/services/subscribers_check.dart';

/// «الفحص العامّ» للمشتركين (٨ نوفمبر — المالك: «أ» و«فحص المشتركين ثكيل كلش»): من قراءات الكارتات نفسها وبحدود «تنبيه المشترك»
/// — المقروء يُعدّ، والمشكلة بنوعها (الكيبل أوّلاً)، والصفر ليس قراءة؛ وعبر الـVPN بالحدود نفسها.
Subscriber _sub(String u, {String? company}) =>
    Subscriber.fromJson({'username': u, 'firstname': u, 'lastname': '', if (company != null) 'company_key': company});

void main() {
  const t = ConnectionAlertThresholds(signalDbm: -70, ccqPct: 70, fiberRxDbm: -25, fiberTempC: 70);
  ConnectionAlertThresholds limits(String? _) => t;

  test('من قراءات الهاتف: المقروء، والمشاكل بحدود المدير، والأسوأ أوّلاً', () {
    final subs = [_sub('a'), _sub('b'), _sub('c'), _sub('d'), _sub('e')];
    UbiquitiStatus ubnt(int sig, int ccq) => UbiquitiStatus(
          hostname: 'h', firmware: 'XC.v8', uptimeSeconds: 100, ssid: 's', mode: 'sta', signalDbm: sig, noiseFloorDbm: -95,
          ccqPercent: ccq, distanceMeters: 300, txRateKbps: 100000, rxRateKbps: 100000, lanPorts: const [], peerMac: null,
          peerCount: 1, baseUrl: 'http://x');
    final snaps = <String, DeviceHealthSnapshot>{
      'a': DeviceHealthSnapshot(kind: DeviceKind.ubiquiti, ip: '10.0.0.1', ubnt: ubnt(-78, 95)),
      'b': DeviceHealthSnapshot(kind: DeviceKind.ubiquiti, ip: '10.0.0.2', ubnt: ubnt(-55, 60)),
      'c': DeviceHealthSnapshot(kind: DeviceKind.ubiquiti, ip: '10.0.0.3', ubnt: ubnt(-50, 99)),
      'd': const DeviceHealthSnapshot(
          kind: DeviceKind.ont,
          ip: '10.0.0.4',
          ont: OntOpticalInfo(txPower: '2.1', rxPower: '-27.5', voltage: '3.3', temperature: '45', bias: '10', sendStatus: 'ok')),
    };
    final r = SubscribersCheck.local(subs, limits,
        peek: (s) => snaps[s.username] == null ? null : (snap: snaps[s.username], stale: false, at: DateTime(2026, 11, 8)));
    expect([r.total, r.read, r.unread], [5, 4, 1], reason: 'e بلا قراءة');
    expect(r.rows.map((x) => x.sub.username).toSet(), {'a', 'b', 'd'}, reason: 'c سليم');
    expect(r.of(ConnectionProblemKind.signal).single.sub.username, 'a');
    expect(r.of(ConnectionProblemKind.ccq).single.sub.username, 'b');
    expect(r.of(ConnectionProblemKind.fiberRx).single.sub.username, 'd');
  });

  test('عبر الـVPN: الكيبل والإشارة وCCQ والضوء بالحدود نفسها؛ الصفر والميّت ليسا قراءة', () {
    final subs = [_sub('a', company: 'k1'), _sub('b', company: 'k2'), _sub('c'), _sub('d'), _sub('e')];
    final reads = <String, VpnSubReading>{
      'a': const VpnSubReading(src: 'vpn', sig: -75, ccq: 0, lan: 'unplugged'),
      'b': const VpnSubReading(src: 'vpn', sig: 0, ccq: 50),
      'c': const VpnSubReading(src: 'vpn', rx: -26.0, temp: 72),
      'd': const VpnSubReading(src: 'dead'),
    };
    final r = SubscribersCheck.vpn(subs, limits, reading: (s) => reads[s.username]);
    expect([r.total, r.read], [5, 3], reason: 'd ميّت وe بلا قراءة');
    expect(r.rows.first.sub.username, 'a', reason: 'الكيبل أوّلاً');
    expect(r.rows.first.problems.map((p) => p.kind).toList(), [ConnectionProblemKind.cable, ConnectionProblemKind.signal],
        reason: 'CCQ صفرٌ ليس قراءة');
    expect(r.of(ConnectionProblemKind.ccq).single.sub.username, 'b', reason: 'إشارة صفرٌ لا تُعدّ ضعيفة');
    expect(r.of(ConnectionProblemKind.fiberRx).single.sub.username, 'c');
    expect(r.of(ConnectionProblemKind.fiberTemp).single.sub.username, 'c');
  });
}
