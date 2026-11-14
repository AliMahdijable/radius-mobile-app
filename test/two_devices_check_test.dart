import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/models/device_health.dart';
import 'package:rad_mysvcs/models/subscriber.dart';
import 'package:rad_mysvcs/services/connection_alerts.dart';
import 'package:rad_mysvcs/services/subscribers_check.dart';

/// «مشترك بجهازين» في «الفحص العامّ» (١٤ نوفمبر — المقترح الذي قبله المالك: «الفحص التلقائي هم لازم يتعرف على هلشي والفحص اليدوي
/// كذلك»): النانو يحكم والراوتر معلومة — نانو سليم وراوترٌ لا يردّ ⇒ «راوتر المشترك مطفي» في «عند المشترك» (لا عطل شبكة)؛ كيبل
/// النانو مفصول ⇒ «كيبل النانو: …» بمشكلة واحدة (لا عطلان)؛ النانو لا يردّ ⇒ لا حكم على الراوتر؛ بلا جهاز ثانٍ ⇒ كما كان.
Subscriber _sub(String u) => Subscriber.fromJson({'username': u, 'firstname': u, 'lastname': '', 'online_status': 1});

DeviceHealthSnapshot _nano({bool cableOk = true}) => DeviceHealthSnapshot(
      kind: DeviceKind.ubiquiti,
      ip: '10.0.0.1',
      ubnt: UbiquitiStatus(
          hostname: 'nano', firmware: 'XC.v8', uptimeSeconds: 100, ssid: 's', mode: 'sta', signalDbm: -55, noiseFloorDbm: -95,
          ccqPercent: 96, distanceMeters: 300, txRateKbps: 100000, rxRateKbps: 100000,
          lanPorts: [LanPort(name: 'eth0', speed: cableOk ? '100Mbps-Full' : null, plugged: cableOk)],
          peerMac: null, peerCount: 1, baseUrl: 'http://x'),
    );

void main() {
  const t = ConnectionAlertThresholds(signalDbm: -70, ccqPct: 70, fiberRxDbm: -25, fiberTempC: 70);
  ConnectionAlertThresholds limits(String? _) => t;

  tearDown(() => SubscribersCheck.debugTwo = null);

  SubsCheckReport run(Map<String, DeviceHealthSnapshot?> snaps, Map<String, ({bool second, bool routerOff})> two) {
    SubscribersCheck.debugTwo = (s) => two[s.username] ?? (second: false, routerOff: false);
    return SubscribersCheck.local([for (final u in snaps.keys) _sub(u)], limits,
        peek: (s) => snaps[s.username] == null ? null : (snap: snaps[s.username], stale: false, at: DateTime(2026, 11, 14)));
  }

  test('نانو سليم وراوترٌ لا يردّ ⇒ «عند المشترك» بسطر «راوتر المشترك مطفي»، لا «سليم» ولا «بمشكلة»', () {
    final r = run({'a': _nano(), 'b': _nano()}, {'a': (second: true, routerOff: true), 'b': (second: true, routerOff: false)});
    expect(r.atSub.map((x) => x.sub.username), ['a']);
    expect(r.atSub.single.note, SubscribersCheck.routerOffNote);
    expect(r.healthy.map((x) => x.sub.username), ['b'], reason: 'راوتره يردّ ⇒ سليم');
    expect(r.rows, isEmpty, reason: 'ليس عطل شبكة');
    expect([r.count(SubsCheckCat.atSubscriber), r.read], [1, 2]);
    final text = SubscribersCheck.reportText(r, progress: SubscribersCheck.progress(subs: 2));
    expect(text, contains('عند المشترك 1'));
    expect(text, contains('عند المشترك (1):'));
    expect(text, contains('راوتر المشترك مطفي'));
  });

  test('كيبل النانو مفصول ⇒ مشكلةٌ واحدة «كيبل النانو: …» ولو كان الراوتر مطفياً (لا عطلان)', () {
    final r = run({'a': _nano(cableOk: false)}, {'a': (second: true, routerOff: true)});
    expect(r.atSub, isEmpty);
    final row = r.rows.single;
    expect(row.worst, ConnectionProblemKind.cable);
    expect(row.problems.length, 1);
    expect(row.problems.single.label, startsWith('${SubscribersCheck.nanoCableWord}: '));
  });

  test('النانو لا يردّ ⇒ لا حكم على الراوتر: من لم يُقرأ كما كان', () {
    final r = run({'a': null}, {'a': (second: true, routerOff: true)});
    expect(r.atSub, isEmpty);
    expect(r.read, 0);
    expect(r.missing.single.sub.username, 'a');
  });

  test('كما كان: بلا جهاز ثانٍ ⇒ السليم سليم، والكيبل باسمه المعتاد', () {
    final r = run({'a': _nano(), 'b': _nano(cableOk: false)}, const {});
    expect(r.healthy.map((x) => x.sub.username), ['a']);
    expect(r.rows.single.problems.single.label, isNot(startsWith(SubscribersCheck.nanoCableWord)));
    expect(r.count(SubsCheckCat.atSubscriber), 0);
  });
}
