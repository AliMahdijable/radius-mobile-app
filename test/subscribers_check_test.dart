import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/vpn_now_api.dart';
import 'package:rad_mysvcs/models/device_health.dart';
import 'package:rad_mysvcs/models/subscriber.dart';
import 'package:rad_mysvcs/services/connection_alerts.dart';
import 'package:rad_mysvcs/services/subscribers_check.dart';

/// «الفحص العامّ» للمشتركين (٨ نوفمبر — المالك: «أ» و«فحص المشتركين ثكيل كلش»): من قراءات الكارتات نفسها وبحدود «تنبيه المشترك»
/// — المقروء يُعدّ، والمشكلة بنوعها (الكيبل أوّلاً)، والصفر ليس قراءة؛ وعبر الـVPN بالحدود نفسها.
Subscriber _sub(String u, {String? company, bool online = true}) => Subscriber.fromJson({
      'username': u,
      'firstname': u,
      'lastname': '',
      'online_status': online ? 1 : 0,
    }).withCompany(company);

UbiquitiStatus _ubnt(int sig, int ccq, {List<LanPort> lan = const [], String host = 'h'}) => UbiquitiStatus(
    hostname: host, firmware: 'XC.v8', uptimeSeconds: 100, ssid: 's', mode: 'sta', signalDbm: sig, noiseFloorDbm: -95,
    ccqPercent: ccq, distanceMeters: 300, txRateKbps: 100000, rxRateKbps: 100000, lanPorts: lan, peerMac: null,
    peerCount: 1, baseUrl: 'http://x');

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
  test('القراءة كاملةً لكلّ مقروء (المالك: «اظهار معلومات ال ccq كذلك») — والسليم الأقرب للحدّ أوّلاً', () {
    final subs = [_sub('a'), _sub('b'), _sub('c'), _sub('d'), _sub('e', online: false), _sub('f'), _sub('g')];
    final at = DateTime(2026, 11, 8, 4);
    final snaps = <String, DeviceHealthSnapshot>{
      // سليم بعيدٌ عن الحدّ (-70): -50 ⇒ هامش 20
      'a': DeviceHealthSnapshot(kind: DeviceKind.ubiquiti, ip: '1', ubnt: _ubnt(-50, 95, host: 'Nano-A',
          lan: const [LanPort(name: 'eth0', speed: '100Mbps-Full', plugged: true)])),
      // سليم قريب: -67 ⇒ هامش 3
      'b': DeviceHealthSnapshot(kind: DeviceKind.ubiquiti, ip: '2', ubnt: _ubnt(-67, 90,
          lan: const [LanPort(name: 'eth0', speed: null, plugged: true)])),
      // كيبل مفصول
      'c': DeviceHealthSnapshot(kind: DeviceKind.ubiquiti, ip: '3', ubnt: _ubnt(-60, 95,
          lan: const [LanPort(name: 'eth0', speed: null, plugged: false)])),
      'd': const DeviceHealthSnapshot(
          kind: DeviceKind.ont,
          ip: '4',
          ont: OntOpticalInfo(txPower: '2.1', rxPower: '-20.5', voltage: '3.3', temperature: '41', bias: '10', sendStatus: 'ok', model: 'MH80', vendor: 'zte')),
      // جهازٌ بلا مقاييس
      'g': const DeviceHealthSnapshot(kind: DeviceKind.other, ip: '7'),
    };
    final r = SubscribersCheck.local(subs, limits,
        peek: (s) => snaps[s.username] == null ? null : (snap: snaps[s.username], stale: false, at: at));
    expect(r.healthy.map((x) => x.sub.username).toList(), ['b', 'd', 'a'],
        reason: 'b هامشه 3 · d الضوء ‎-20.5 وحدّه ‎-25 ⇒ 4.5 · a هامشه 20');
    final a = r.healthy.last.reading!;
    expect([a.sig, a.ccq, a.lan, a.device, a.at], [-50, 95, '100', 'Nano-A', at]);
    expect(r.healthy.first.reading!.lan, 'on', reason: 'موصولٌ بسرعةٍ لا تُعرف ليس مفصولاً');
    final d = r.healthy[1].reading!;
    expect([d.rx, d.temp, d.device], [-20.5, 41.0, 'MH80']);
    expect(r.rows.single.sub.username, 'c');
    expect(r.rows.single.reading!.lan, 'unplugged');
    expect({for (final m in r.missing) m.sub.username: m.why},
        {'e': SubsMissWhy.offline, 'f': SubsMissWhy.noReply, 'g': SubsMissWhy.noMetrics});
    expect([r.total, r.read, r.unread], [7, 4, 3]);
  });

  test('داخل النوع الواحد: الأشدّ أوّلاً — والـVPN: من السكتر/الأولت، والبنك وحده، والميّت «لا يستجيب»', () {
    final subs = [_sub('w1'), _sub('w2'), _sub('w3'), _sub('p'), _sub('x'), _sub('o', online: false)];
    final reads = <String, VpnSubReading>{
      'w1': const VpnSubReading(src: 'cpe', sig: -74, ccq: 90, lan: '100'),
      'w2': const VpnSubReading(src: 'sector', sig: -82, ccq: 85),
      'w3': const VpnSubReading(src: 'olt', rx: -24.0, temp: 50),
      'p': const VpnSubReading(src: 'ping', ms: 12),
      'x': const VpnSubReading(src: 'dead'),
    };
    final when = DateTime(2026, 11, 8, 5);
    final r = SubscribersCheck.vpn(subs, limits, reading: (s) => reads[s.username], readAt: (_) => when);
    expect(r.rows.map((x) => x.sub.username).toList(), ['w2', 'w1'], reason: '‎-82 قبل ‎-74');
    expect(r.rows.first.reading!.via, 'السكتر');
    expect(r.rows.first.reading!.at, when);
    // ٩ نوفمبر: البنك وحده (يردّ بلا مقاييس) «لم يُقرأ» لا «سليم» — كان هنا آخر «سليم»
    expect(r.healthy.map((x) => x.sub.username).toList(), ['w3']);
    expect(r.healthy.first.reading!.via, 'الأولت');
    expect([for (final m in r.missing) m.why], [SubsMissWhy.dead, SubsMissWhy.unmeasured, SubsMissWhy.offline],
        reason: 'الميّت أوّلاً ثمّ من يردّ بلا مقاييس');
    expect(r.missing[1].sub.username, 'p');
    expect(r.missing[1].note, 'يردّ، ما انقرت مقاييسه');
    expect([r.total, r.read], [6, 3]);
  });

  group('٩ نوفمبر — «فحص المشتركين» عبر الـVPN: من يردّ ولم تُقرأ مقاييسه ليس «سليم»', () {
    test('🚨 ضغطة نفق الشركة: يردّ 156 وقُرئ 0 (رُفض الدخول 153) ⇒ لا أحد «سليم» — كلّهم «لم يُقرأ» بسببهم', () {
      // من فحص الخادم كما يُرجعه اليوم (src: ping بلا مقاييس)، وخادمٌ لاحق يضيف err
      final subs = [for (var i = 0; i < 156; i++) _sub('u$i')];
      final reads = <String, VpnSubReading>{
        for (var i = 0; i < 156; i++)
          'u$i': VpnSubReading.fromJson({'u': 'u$i', 'src': 'ping', 'ms': 20 + i % 5, if (i < 153) 'err': 'login_failed'})!,
      };
      final r = SubscribersCheck.vpn(subs, limits, reading: (s) => reads[s.username]);
      expect(r.healthy, isEmpty);
      expect(r.rows, isEmpty);
      expect([r.read, r.unread], [0, 156]);
      expect(r.missing.every((m) => m.why == SubsMissWhy.unmeasured), isTrue);
      expect(r.missing.where((m) => m.note == 'يردّ، ما انفتح برمزه المحفوظ').length, 153);
      expect(r.missing.where((m) => m.note == 'يردّ، ما انقرت مقاييسه').length, 3, reason: 'خادمٌ بلا err ⇒ السطر العامّ');
    });

    test('الأسباب من الخادم إن أعطاها، والحقل اختياريّ؛ وجهازٌ قُرئ بلا أرقام «بلا قياسات»', () {
      expect(VpnSubReading.fromJson({'src': 'ping', 'ms': 4})!.err, isNull);
      expect(VpnSubReading.fromJson({'src': 'ping', 'err': 'no_web'})!.err, 'no_web');
      expect(SubscribersCheck.unmeasuredLabel(const VpnSubReading(src: 'ping', err: 'no_web')), 'يردّ، واجهة إدارته ما تفتح');
      expect(const VpnSubReading(src: 'ping', ms: 4).measured, isFalse);
      expect(const VpnSubReading(src: 'cpe', sig: -60).measured, isTrue);
      expect(const VpnSubReading(src: 'cpe', lan: 'ok').measured, isTrue);
      expect(const VpnSubReading(src: 'cpe', sig: 0, ccq: 0).measured, isFalse, reason: 'الصفر ليس قراءة');
      final r = SubscribersCheck.vpn([_sub('c')], limits, reading: (_) => const VpnSubReading(src: 'cpe'));
      expect(r.missing.single.why, SubsMissWhy.noMetrics);
    });

    test('«كل الشركات»: البنك وحده لا يغلب قراءة الهاتف الحقيقيّة ولو أحدث؛ وبلا قراءة هاتف ⇒ «لم يُقرأ» لا «سليم»', () {
      final phoneAt = DateTime(2026, 11, 9, 10, 0);
      final vpnAt = DateTime(2026, 11, 9, 10, 5);
      final subs = [_sub('both', company: 'kE'), _sub('ping', company: 'kE')];
      final r = SubscribersCheck.mixed(
        subs,
        limits,
        peek: (s) => s.username == 'both'
            ? (snap: DeviceHealthSnapshot(kind: DeviceKind.ubiquiti, ip: '3', ubnt: _ubnt(-50, 95)), stale: false, at: phoneAt)
            : null,
        reading: (s) => const VpnSubReading(src: 'ping', ms: 9, err: 'login_failed'),
        readAt: (_) => vpnAt,
      );
      expect(r.healthy.single.sub.username, 'both');
      expect(r.healthy.single.reading!.vpn, isFalse, reason: 'قراءة الهاتف بمقاييسها');
      expect(r.missing.single.sub.username, 'ping');
      expect(r.missing.single.why, SubsMissWhy.unmeasured);
      expect(r.missing.single.note, 'يردّ، ما انفتح برمزه المحفوظ');
    });
  });
  test('«كل الشركات»: كلّ مشتركٍ بأحدث قراءته — الهاتف لشركةٍ والـVPN لأخرى، ومن لم يُقرأ وشركته لم تُفحص يُقال سببها', () {
    // المالك ٨ نوفمبر: «مايعرض مثل الاجهزه مشتركين كل شركه ونتيجه فحوصاتهم… ايرث لنك رابطلها vpn والسوبرنت تشتغل لوكل»
    final subs = [
      _sub('s1', company: 'kS'), _sub('s2', company: 'kS'), // سوبرنت — من الهاتف
      _sub('e1', company: 'kE'), _sub('e2', company: 'kE'), // ايرث لنك — عبر VPN
      _sub('x1', company: 'kX'), // شركةٌ ثالثة بلا VPN
      _sub('both', company: 'kE'), // الاثنان: الأحدث يغلب
    ];
    final phoneAt = DateTime(2026, 11, 8, 10, 0);
    final vpnAt = DateTime(2026, 11, 8, 10, 5);
    final snaps = <String, DeviceHealthSnapshot>{
      's1': DeviceHealthSnapshot(kind: DeviceKind.ubiquiti, ip: '1', ubnt: _ubnt(-80, 95)),
      's2': DeviceHealthSnapshot(kind: DeviceKind.ubiquiti, ip: '2', ubnt: _ubnt(-50, 95)),
      'both': DeviceHealthSnapshot(kind: DeviceKind.ubiquiti, ip: '3', ubnt: _ubnt(-50, 95)),
    };
    final reads = <String, VpnSubReading>{
      'e1': const VpnSubReading(src: 'cpe', sig: -55, ccq: 40, lan: '100'),
      'e2': const VpnSubReading(src: 'dead'),
      'both': const VpnSubReading(src: 'cpe', sig: -85, ccq: 90),
    };
    final r = SubscribersCheck.mixed(
      subs,
      limits,
      peek: (s) => snaps[s.username] == null ? null : (snap: snaps[s.username], stale: false, at: phoneAt),
      reading: (s) => reads[s.username],
      readAt: (c) => c == 'kE' ? vpnAt : null,
      companyNote: (c) => c == 'kX' ? '«ثالثة» تحتاج VPN' : null,
    );
    expect([r.total, r.read], [6, 4]);
    expect({for (final x in r.rows) x.sub.username}, {'s1', 'e1', 'both'});
    expect(r.rows.firstWhere((x) => x.sub.username == 'both').reading!.sig, -85,
        reason: 'قراءة الـVPN (10:05) أحدث من الهاتف (10:00)');
    expect(r.rows.firstWhere((x) => x.sub.username == 'e1').reading!.at, vpnAt);
    expect(r.healthy.single.sub.username, 's2');
    final miss = {for (final m in r.missing) m.sub.username: (m.why, m.note)};
    expect(miss['e2'], (SubsMissWhy.dead, null));
    expect(miss['x1'], (SubsMissWhy.company, '«ثالثة» تحتاج VPN'));
  });
}
