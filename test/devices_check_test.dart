// «الفحص الشامل» (٦ نوفمبر — المالك: «يفحص الجهاز نفسه ويفحص المشتركين الي بداخلة ويعطي تقرير منفصل لكل جهاز» · «كذلك السوجات
// من حيث المتغيرات الحيوية فكر بيها بدقة»): المقيِّم النقيّ — الحال، حيويّات الجهاز، مشتركو السكتر، منافذ السويج، الأولت، والمقارنة
// بالفحص السابق؛ وقراءة حقول منافذ مايكروتك الجديدة.
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/mikrotik_api.dart';
import 'package:rad_mysvcs/models/network_device.dart';
import 'package:rad_mysvcs/screens/network_devices/device_vitals.dart';
import 'package:rad_mysvcs/services/devices_check.dart';

NetworkDevice dev(int id, {String type = 'router', String brand = 'mikrotik', String status = 'online', String name = 'جهاز'}) =>
    NetworkDevice(
      id: id,
      adminId: '2',
      name: '$name $id',
      type: type,
      brand: brand,
      ip: '10.0.0.$id',
      port: 8728,
      hasCredentials: true,
      lastStatus: status,
      createdAt: DateTime(2026, 11, 1),
    );

DeviceDetail detail({DeviceGlance glance = const DeviceGlance(), List<PortTraffic> ports = const [], List<PeerLink> peers = const []}) =>
    DeviceDetail(glance: glance, ports: ports, peers: peers);

const lim = CheckLimits(subSignal: -70, subCcq: 50, voltBase: {1: 23.3}, voltBelow: {1: 22.2});

List<String> texts(DeviceCheckReport r) => [for (final f in r.findings) f.text];

void main() {
  group('الحال', () {
    test('لا يستجيب ⇒ «طافي» — ومنذ متى إن كان مفصولاً بالقائمة', () {
      final d = NetworkDevice(
        id: 3, adminId: '2', name: 'سكتر', type: 'sector', brand: 'ubnt', ip: '10.0.0.3', port: 80,
        lastStatus: 'offline', statusSince: DateTime(2026, 11, 6, 10), createdAt: DateTime(2026, 11, 1),
      );
      final r = DevicesCheck.evaluate(d: d, alive: false, now: DateTime(2026, 11, 6, 12));
      expect(r.state, CheckState.down);
      expect(r.role, CheckRole.sector);
      expect(texts(r).single, startsWith('لا يستجيب منذ'));
      expect(r.findings.single.level, CheckLevel.bad);
    });

    test('يردّ ولا تفاصيل ⇒ «لم يُقرأ» بسببه', () {
      final r = DevicesCheck.evaluate(d: dev(1), alive: true, unreadReason: 'بلا بيانات دخول — الحال فقط');
      expect(r.state, CheckState.unread);
      expect(texts(r), ['بلا بيانات دخول — الحال فقط']);
    });

    test('سليم بلا ملاحظات، والحيويّات للعرض', () {
      final r = DevicesCheck.evaluate(
        d: dev(1),
        alive: true,
        ms: 4,
        detail: detail(glance: const DeviceGlance(cpu: 12, mem: 40, temp: 45, voltage: 23.4, uptimeSec: 86400 * 3, ppp: 120)),
        limits: lim,
      );
      expect(r.state, CheckState.ok);
      expect(r.findings, isEmpty);
      expect(r.vitals.map((v) => v.k), containsAll(['المعالج', 'الذاكرة', 'الحرارة', 'الكهرباء', 'يعمل منذ', 'جلسات PPP', 'الاستجابة']));
    });
  });

  group('الجهاز نفسه', () {
    test('المعالج والذاكرة والحرارة فوق حدودها، والكهرباء تحت حدّها بطبيعيّها، والإقلاع القريب، وفقدان الحزم', () {
      final r = DevicesCheck.evaluate(
        d: dev(1),
        alive: true,
        loss: 33,
        detail: detail(glance: const DeviceGlance(cpu: 95, mem: 93, temp: 92, voltage: 21.0, uptimeSec: 240)),
        limits: lim,
      );
      expect(r.state, CheckState.warn);
      final t = texts(r);
      expect(t, contains('المعالج 95٪ — عالي'));
      expect(t, contains('الذاكرة 93٪ — شبه ممتلئة'));
      expect(t, contains('الحرارة 92° — عالية'));
      expect(t, contains('الكهرباء 21.0V — طبيعيّها 23.3V'));
      expect(t, contains('اشتغل قبل 4 د — انطفى أو أُعيد تشغيله'));
      expect(t, contains('فقدان حزم 33٪ — الطريق إليه متقطّع'));
      // الحرارة ≥ الحدّ + ١٠ والكهرباء خطأٌ أحمر؛ والأخطر أوّلاً
      expect(r.findings.first.level, CheckLevel.bad);
    });

    test('الكهرباء بلا معدّلٍ معروف لا تُحكم؛ ووقت الوصلة ليس إقلاع الجهاز', () {
      final r = DevicesCheck.evaluate(
        d: dev(9),
        alive: true,
        detail: detail(glance: const DeviceGlance(voltage: 11.0, uptimeSec: 60, linkUptime: true)),
        limits: lim,
      );
      expect(r.findings, isEmpty);
    });
  });

  group('السكتر ومشتركوه', () {
    test('كلّ مشترك بإشارته وCCQ؛ المشاكل أوّلاً ثمّ الأضعف — وتقريرٌ نصّيّ يضمّها', () {
      final r = DevicesCheck.evaluate(
        d: dev(5, type: 'sector', brand: 'ubnt'),
        alive: true,
        detail: detail(glance: const DeviceGlance(isAp: true, cpu: 20), peers: const [
          PeerLink(name: 'ali', signal: -62, ccq: 92, txRate: 130, rxRate: 117),
          PeerLink(name: 'omar', signal: -78, ccq: 88),
          PeerLink(name: 'zaid', signal: -65, ccq: 40),
          PeerLink(name: 'sami', signal: -58, ccq: 0), // صفر = غير متوفّر لا «جودة صفر»
        ]),
        limits: lim,
      );
      expect(r.role, CheckRole.sector);
      expect(r.state, CheckState.warn);
      expect(r.subs.map((s) => s.name), ['omar', 'zaid', 'ali', 'sami']);
      expect(r.subsWeak, 1);
      expect(r.subsLowCcq, 1);
      expect(texts(r), contains('1 إشارة ضعيفة · 1 CCQ واطي — من 4 مشترك'));
      expect(r.subs.last.ccq, isNull);
      final txt = r.toText();
      expect(txt, contains('omar: -78 dBm · CCQ 88٪'));
      expect(txt, contains('zaid: -65 dBm · CCQ 40٪'));
      expect(txt, isNot(contains('ali:')), reason: 'السليم لا يُسرد بالنسخ');
      expect(r.memo!.peers, 4);
    });

    test('سكترٌ فرغ وكان عليه ٥ ⇒ ملاحظة؛ فارغٌ بلا تاريخ ⇒ معلومة لا خطأ', () {
      final d = dev(5, type: 'sector', brand: 'ubnt');
      final emptied = DevicesCheck.evaluate(
          d: d, alive: true, detail: detail(glance: const DeviceGlance(isAp: true)), limits: lim, prev: const CheckMemo(peers: 5));
      expect(emptied.state, CheckState.warn);
      expect(texts(emptied), ['ما عليه أحد الآن — كانوا 5 بالفحص السابق']);
      final fresh = DevicesCheck.evaluate(d: d, alive: true, detail: detail(glance: const DeviceGlance(isAp: true)), limits: lim);
      expect(fresh.state, CheckState.ok);
      expect(fresh.findings.single.level, CheckLevel.info);
    });

    test('عبر الـVPN بلا جدولٍ مقروء لا يُقال «ما عليه أحد»', () {
      final r = DevicesCheck.evaluate(
          d: dev(5, type: 'sector', brand: 'ubnt'), alive: true, detail: detail(glance: const DeviceGlance(isAp: true)), viaVpn: true);
      expect(r.subsKnown, isFalse);
      expect(r.findings, isEmpty);
    });

    test('الوصلة (محطّة): إشارتها وCCQ بحدود الوكيل', () {
      final r = DevicesCheck.evaluate(
          d: dev(6, type: 'link', brand: 'ubnt'), alive: true, detail: detail(glance: const DeviceGlance(isAp: false, signal: -82, ccq: 45)));
      expect(r.role, CheckRole.link);
      expect(texts(r), containsAll(['إشارة الوصلة -82 dBm — ضعيفة', 'CCQ الوصلة 45٪ — واطي']));
    });
  });

  group('السويج — المتغيّرات الحيويّة للمنافذ', () {
    final sw = dev(7, type: 'switch');
    const uptime = DeviceGlance(uptimeSec: 86400 * 2);

    test('10M، half-duplex، ضوء SFP، PoE قصر — وما سواها سليم', () {
      final r = DevicesCheck.evaluate(
        d: sw,
        alive: true,
        detail: detail(glance: uptime, ports: const [
          PortTraffic(name: 'ether1', up: true, linkSpeed: '1Gbps'),
          PortTraffic(name: 'ether2', up: true, linkSpeed: '10Mbps'),
          PortTraffic(name: 'ether3', up: true, linkSpeed: '100Mbps', halfDuplex: true),
          PortTraffic(name: 'sfp1', up: true, linkSpeed: '1Gbps', sfpRx: -27.4),
          PortTraffic(name: 'sfp2', up: true, linkSpeed: '1Gbps', sfpRx: -31.2),
          PortTraffic(name: 'ether4', up: true, linkSpeed: '100Mbps', poeStatus: 'short-circuit'),
          PortTraffic(name: 'ether5', up: false),
          PortTraffic(name: 'bridge1', up: true, physical: false),
        ]),
      );
      expect(r.state, CheckState.warn);
      expect(r.portsTotal, 7, reason: 'الجسر واجهةٌ منطقيّة لا منفذ');
      expect(r.portsUp, 6);
      final by = {for (final p in r.ports) p.name: p};
      expect(by['ether1']!.flagged, isFalse);
      expect(by['ether2']!.notes, ['يشتغل 10Mbps — كيبل أو كونكتر']);
      expect(by['ether3']!.notes, ['half-duplex — كيبل أو إعداد']);
      expect(by['sfp1']!.notes, ['ضوء الـSFP -27.4 dBm — ضعيف']);
      expect(by['sfp1']!.level, CheckLevel.warn);
      expect(by['sfp2']!.level, CheckLevel.bad);
      expect(by['ether4']!.notes, ['PoE: قصر — الكيبل أو الجهاز']);
      expect(by['ether5']!.flagged, isFalse, reason: 'منفذٌ غير مستعمَل ليس مشكلة');
      expect(r.ports.first.flagged, isTrue, reason: 'ذات الملاحظة أوّلاً');
      expect(texts(r).first, 'منافذ فيها ملاحظات: 5');
      expect(r.findings.first.level, CheckLevel.bad);
    });

    test('بالمقارنة بالفحص السابق: طفى، نزل من 1G إلى 100M، انقطاعات وأخطاء جديدة', () {
      const prev = CheckMemo(ports: {
        'ether1': PortMemo(up: true, mbps: 1000),
        'ether2': PortMemo(up: true, mbps: 1000, linkDowns: 3, errors: 10),
        'ether3': PortMemo(up: true, mbps: 100, linkDowns: 7, errors: 500),
      });
      final r = DevicesCheck.evaluate(
        d: sw,
        alive: true,
        prev: prev,
        detail: detail(glance: uptime, ports: const [
          PortTraffic(name: 'ether1', up: false),
          PortTraffic(name: 'ether2', up: true, linkSpeed: '100Mbps', linkDowns: 6, errors: 45),
          PortTraffic(name: 'ether3', up: true, linkSpeed: '100Mbps', linkDowns: 8, errors: 510),
        ]),
      );
      final by = {for (final p in r.ports) p.name: p};
      expect(by['ether1']!.notes, ['طفى من الفحص السابق']);
      expect(by['ether2']!.notes,
          ['نزل من 1G إلى 100M — كيبل أو كونكتر', 'انقطع 3 مرّة من الفحص السابق', 'أخطاء +35 من الفحص السابق — كيبل تالف أو تشويش']);
      expect(by['ether3']!.flagged, isFalse, reason: '100M كان كذلك، وانقطاعٌ واحد و١٠ أخطاء تحت الحدّ');
      expect(r.memo!.ports['ether2']!.linkDowns, 6);
      expect(r.memo!.ports['ether1']!.up, isFalse);
    });

    test('بلا لقطةٍ سابقة: الانقطاعات والأخطاء بمعدّلها اليوميّ منذ الإقلاع', () {
      final r = DevicesCheck.evaluate(
        d: sw,
        alive: true,
        detail: detail(glance: uptime, ports: const [
          PortTraffic(name: 'ether1', up: true, linkSpeed: '1Gbps', linkDowns: 9, errors: 900),
          PortTraffic(name: 'ether2', up: true, linkSpeed: '1Gbps', linkDowns: 3, errors: 150),
        ]),
      );
      final by = {for (final p in r.ports) p.name: p};
      expect(by['ether1']!.notes, [
        'انقطع 9 مرّة خلال 2 يوم — كيبل مرخي أو كهرباء الطرف الثاني',
        'أخطاء 900 — كيبل تالف أو تشويش',
      ]);
      expect(by['ether2']!.flagged, isFalse);
    });

    test('عبر الـVPN بالأعداد وحدها: لا حكم على منفذ، واللقطة المفصّلة السابقة تبقى', () {
      const prev = CheckMemo(ports: {'ether1': PortMemo(up: true, mbps: 1000)});
      final r = DevicesCheck.evaluate(
        d: sw,
        alive: true,
        viaVpn: true,
        portsCountsOnly: true,
        prev: prev,
        detail: detail(glance: uptime, ports: const [PortTraffic(name: 'ether1', up: false), PortTraffic(name: 'ether2', up: true)]),
      );
      expect(r.ports, isEmpty);
      expect(r.findings, isEmpty);
      expect(r.portsUp, 1);
      expect(r.portsTotal, 2);
      expect(r.memo!.ports['ether1']!.up, isTrue);
    });

    test('مايكروتك: مروحةٌ عاطلة خطأ، وواقفةٌ مع حرارةٍ عالية ملاحظة، والمزوّد الثاني المفصول معلومة', () {
      const stats = MikrotikStats(
        cpuLoad: 5, memUsedPercent: 30, memTotalBytes: 1, memFreeBytes: 1, uptime: '2d', version: '7', boardName: 'CRS',
        architectureName: 'arm', cpuCount: 1, cpuFrequencyMhz: 800, temperature: 70,
        fans: [MikrotikHealthItem(name: 'fan1', intValue: 0), MikrotikHealthItem(name: 'fan2', isOk: false)],
        psus: [MikrotikHealthItem(name: 'psu2', isOk: false)],
        interfaces: [], pppActiveCount: 0, wirelessInterfaces: [], wirelessClients: [], w60gLinks: [], via: 'api',
      );
      final r = DevicesCheck.evaluate(d: sw, alive: true, raw: stats, detail: detail(glance: const DeviceGlance(temp: 70)));
      expect(texts(r), containsAll(['المروحة fan2 عاطلة', 'المروحة fan1 واقفة والحرارة 70°', 'مزوّد الكهرباء psu2 لا يعمل — إن كان موصولاً فافحصه']));
      expect(r.findings.firstWhere((f) => f.text.contains('psu2')).level, CheckLevel.info);
    });
  });

  test('الأولت: PON طافي له ONU ملاحظة، والفارغ لا', () {
    final r = DevicesCheck.evaluate(
      d: dev(8, type: 'other', brand: 'hsgq'),
      alive: true,
      detail: detail(
          glance: const DeviceGlance(onusOnline: 79, onusTotal: 101, pons: [
        PonGlance('PON1', up: true, online: 40, total: 50),
        PonGlance('PON2', up: false, online: 0, total: 12),
        PonGlance('PON3', up: false, online: 0, total: 0),
      ])),
    );
    expect(r.role, CheckRole.olt);
    expect(texts(r), ['منفذ PON طافي: PON2']);
    expect(r.vitals.firstWhere((v) => v.k == 'ONU').v, '79/101');
  });

  test('السرعة نصّاً ⇒ ميغابت', () {
    expect(DevicesCheck.mbpsOf('1Gbps'), 1000);
    expect(DevicesCheck.mbpsOf('100Mbps'), 100);
    expect(DevicesCheck.mbpsOf('2.5Gbps'), 2500);
    expect(DevicesCheck.mbpsOf('10G'), 10000);
    expect(DevicesCheck.mbpsOf('1000'), 1000);
    expect(DevicesCheck.mbpsOf('1000000000'), 1000);
    expect(DevicesCheck.mbpsOf(''), isNull);
    expect(DevicesCheck.mbpsOf('auto'), isNull);
    expect(DevicesCheck.fmtMbps(1000), '1G');
    expect(DevicesCheck.fmtMbps(2500), '2.5G');
    expect(DevicesCheck.fmtMbps(100), '100M');
  });

  test('الترتيب والتقرير الكامل: طافي ⇒ ملاحظات ⇒ لم يُقرأ ⇒ سليم', () {
    final ok = DevicesCheck.evaluate(d: dev(1, name: 'أ'), alive: true, detail: detail());
    final down = DevicesCheck.evaluate(d: dev(2, name: 'ب'), alive: false);
    final unread = DevicesCheck.evaluate(d: dev(3, name: 'ج'), alive: true);
    final warn = DevicesCheck.evaluate(d: dev(4, name: 'د'), alive: true, detail: detail(glance: const DeviceGlance(cpu: 99)));
    expect(DevicesCheck.sorted([ok, unread, warn, down]).map((r) => r.state),
        [CheckState.down, CheckState.warn, CheckState.unread, CheckState.ok]);
    final txt = DevicesCheck.reportText([ok, down, unread, warn], viaVpn: true);
    expect(txt.split('\n').first, 'الفحص الشامل — 4 جهاز (عبر الـVPN): طافي 1 · ملاحظات 1 · لم يُقرأ 1 · سليم 1');
    expect(txt, contains('ب 2 (راوتر) — طافي'));
  });

  test('اللقطة تُحفظ وتُقرأ', () {
    const m = CheckMemo(ports: {'ether1': PortMemo(up: true, mbps: 1000, linkDowns: 2, errors: 0)}, peers: 7);
    final back = CheckMemo.fromJson(m.toJson())!;
    expect(back.peers, 7);
    expect(back.ports['ether1']!.mbps, 1000);
    expect(back.ports['ether1']!.linkDowns, 2);
    expect(CheckMemo.fromJson('x'), isNull);
  });

  test('مايكروتك: حقول المنفذ الجديدة من الصفوف نفسها (link-downs، الأخطاء، half، SFP، PoE)', () {
    final i = MikrotikInterface.fromApiMap(
      {'name': 'sfp1', 'type': 'ether', 'running': 'true', 'disabled': 'false', 'link-downs': '4', 'rx-error': '12', 'tx-error': '3'},
      monitor: {'rate': '1Gbps', 'full-duplex': 'false', 'sfp-rx-power': '-23.511', 'poe-out-status': 'overload'},
    );
    expect(i.linkDowns, 4);
    expect(i.errors, 15);
    expect(i.halfDuplex, isTrue);
    expect(i.sfpRxPower, closeTo(-23.511, 1e-9));
    expect(i.poeStatus, 'overload');
    final plain = MikrotikInterface.fromApiMap({'name': 'ether2', 'type': 'ether', 'running': 'false', 'disabled': 'false'});
    expect(plain.halfDuplex, isFalse, reason: 'غياب الـmonitor ليس half');
    expect(plain.errors, isNull);
    expect(plain.linkDowns, isNull);
  });
}
