// «الفحص الشامل» (٦ نوفمبر — المالك: «يفحص الجهاز نفسه ويفحص المشتركين الي بداخلة ويعطي تقرير منفصل لكل جهاز» · «كذلك السوجات
// من حيث المتغيرات الحيوية فكر بيها بدقة»): المقيِّم النقيّ — الحال، حيويّات الجهاز، مشتركو السكتر، منافذ السويج، الأولت، والمقارنة
// بالفحص السابق؛ وقراءة حقول منافذ مايكروتك الجديدة.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/api/cisco_api.dart';
import 'package:rad_mysvcs/api/mikrotik_api.dart';
import 'package:rad_mysvcs/api/network_devices_api.dart';
import 'package:rad_mysvcs/api/routeros_channel.dart';
import 'package:rad_mysvcs/api/ubnt_api.dart';
import 'package:rad_mysvcs/api/vsol_olt_api.dart';
import 'package:rad_mysvcs/models/network_device.dart';
import 'package:rad_mysvcs/screens/network_devices/device_vitals.dart';
import 'package:rad_mysvcs/services/devices_check.dart';
import 'package:rad_mysvcs/services/device_stats_cache.dart';
import 'package:rad_mysvcs/services/devices_check_runner.dart';
import 'package:rad_mysvcs/services/vpn_now.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
      expect(texts(r), contains('إشارة ضعيفة: 1 · CCQ واطي: 1 — من 4 مشترك'));
      expect(r.subs.last.ccq, isNull);
      final txt = r.toText();
      expect(txt, contains('omar: rx -78 dBm · CCQ 88٪'));
      expect(txt, contains('zaid: rx -65 dBm · CCQ 40٪'));
      expect(txt, isNot(contains('ali:')), reason: 'السليم لا يُسرد بالنسخ');
      expect(r.memo!.peers, 4);
    });

    test('سكترٌ فرغ وكان عليه ٥ ⇒ ملاحظة؛ فارغٌ بلا تاريخ ⇒ معلومة لا خطأ', () {
      final d = dev(5, type: 'sector', brand: 'ubnt');
      // جدولٌ قُرئ فعلاً (peersKnown) وجاء فارغاً — «لا أحد» صادقة
      final emptied = DevicesCheck.evaluate(
          d: d,
          alive: true,
          detail: detail(glance: const DeviceGlance(isAp: true, peersKnown: true)),
          limits: lim,
          prev: const CheckMemo(peers: 5));
      expect(emptied.state, CheckState.warn);
      expect(texts(emptied), ['ما عليه أحد الآن — كانوا 5 بالفحص السابق']);
      final fresh = DevicesCheck.evaluate(
          d: d, alive: true, detail: detail(glance: const DeviceGlance(isAp: true, peersKnown: true)), limits: lim);
      expect(fresh.state, CheckState.ok);
      expect(fresh.findings.single.level, CheckLevel.info);
    });

    test('عبر الـVPN بلا جدولٍ مقروء لا يُقال «ما عليه أحد» — يُقال إنّ قائمتهم ما انقرت', () {
      final r = DevicesCheck.evaluate(
          d: dev(5, type: 'sector', brand: 'ubnt'), alive: true, detail: detail(glance: const DeviceGlance(isAp: true)), viaVpn: true);
      expect(r.subsKnown, isFalse);
      expect(texts(r), ['قائمة مشتركيه ما انقرت']);
      expect(r.state, CheckState.unread, reason: '«سليم» حكمٌ على مشتركيه أيضاً — وهم لم يُقرؤوا');
    });

    test('٩ نوفمبر: من شبكتك وجدول التسجيل لم يُقرأ (مهلة) ⇒ لا «ما عليه أحد الآن — كانوا N»، والعدد السابق يبقى للمقارنة', () {
      // كان `|| !viaVpn` يجعل كلّ سكترٍ من شبكتك «مقروء الجدول» — فجدولٌ انتهت مهلته يقول «ما عليه أحد الآن — كانوا 5»
      final r = DevicesCheck.evaluate(
        d: dev(5, type: 'sector'),
        alive: true,
        detail: detail(glance: const DeviceGlance(isAp: true, cpu: 9)),
        limits: lim,
        prev: const CheckMemo(peers: 5),
      );
      expect(r.subsKnown, isFalse);
      expect(texts(r).where((t) => t.contains('ما عليه أحد')), isEmpty);
      expect(texts(r), ['قائمة مشتركيه ما انقرت']);
      expect(r.state, CheckState.unread, reason: 'لا «سليم» لسكترٍ مشتركوه مجهولون');
      expect(r.cpu, 9, reason: 'ما قُرئ من الجهاز نفسه يُعرض');
      expect(r.memo!.peers, 5, reason: 'المجهول لا يمسح العدد السابق');
      // وبملاحظةٍ حقيقيّة (المعالج عالٍ) ⇒ «ملاحظات» كما كانت
      final hot = DevicesCheck.evaluate(
          d: dev(5, type: 'sector'), alive: true, detail: detail(glance: const DeviceGlance(isAp: true, cpu: 97)), limits: lim);
      expect(hot.state, CheckState.warn);
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

    test('قفص SFP فارغ (سكتر بيس بوكس: ether1 + sfp1 بلا وحدة) لا يُعرض ولا يُعدّ — وما كان شغّالاً ثمّ طفى يبقى', () {
      final sector = dev(8, type: 'sector');
      final r = DevicesCheck.evaluate(
        d: sector,
        alive: true,
        detail: detail(glance: uptime, ports: const [
          PortTraffic(name: 'ether1', up: true, linkSpeed: '1Gbps'),
          PortTraffic(name: 'sfp1', up: false),
        ]),
      );
      expect(r.ports.map((p) => p.name), ['ether1'], reason: 'لا «sfp» لجهازٍ بلا وحدة');
      expect([r.portsUp, r.portsTotal], [1, 1]);
      expect(r.memo!.ports.containsKey('sfp1'), isFalse);

      // كان شغّالاً في الفحص السابق ثمّ طفى ⇒ يبقى ويُقال
      final down = DevicesCheck.evaluate(
        d: sector,
        alive: true,
        prev: const CheckMemo(ports: {'sfp1': PortMemo(up: true, mbps: 1000)}),
        detail: detail(glance: uptime, ports: const [
          PortTraffic(name: 'ether1', up: true, linkSpeed: '1Gbps'),
          PortTraffic(name: 'sfp1', up: false),
        ]),
      );
      final by = {for (final p in down.ports) p.name: p};
      expect(by['sfp1']!.notes, ['طفى من الفحص السابق']);
      expect(down.portsTotal, 2);

      // شغّالٌ بوحدة ⇒ منفذٌ عاديّ بضوئه
      final fiber = DevicesCheck.evaluate(
        d: sector,
        alive: true,
        detail: detail(glance: uptime, ports: const [
          PortTraffic(name: 'ether1', up: false),
          PortTraffic(name: 'sfp1', up: true, linkSpeed: '1Gbps', sfpRx: -12.0),
        ]),
      );
      expect(fiber.ports.map((p) => p.name).toSet(), {'ether1', 'sfp1'}, reason: 'الإيثر الطافي يبقى — منفذٌ حقيقيّ');
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

  group('٦ نوفمبر — «الاشارة من عدنا وليس rx او تظهرهن الاثنين» + الأولت', () {
    test('السكتر: إشارة المشترك من جهتنا عليها الحكم، والـrx بجانبها؛ وما لا يعطيها الطراز ⇒ الـrx وحده', () {
      final r = DevicesCheck.evaluate(
        d: dev(5, type: 'sector', brand: 'ubnt'),
        alive: true,
        detail: detail(glance: const DeviceGlance(isAp: true), peers: const [
          PeerLink(name: 'abo', signal: -76, txSignal: -62, ccq: 82), // rx ضعيف لكنّه يستقبلنا جيّداً ⇒ سليم
          PeerLink(name: 'seed', signal: -60, txSignal: -74, ccq: 94), // العكس ⇒ ضعيف
          PeerLink(name: 'old', signal: -75, ccq: 90), // طرازٌ بلا إشارةٍ من جهتنا ⇒ الـrx
        ]),
        limits: lim,
      );
      final by = {for (final x in r.subs) x.name: x};
      expect((by['abo']!.signal, by['abo']!.rxSignal, by['abo']!.weak), (-62, -76, false));
      expect((by['seed']!.signal, by['seed']!.rxSignal, by['seed']!.weak), (-74, -60, true));
      expect((by['old']!.signal, by['old']!.rxSignal, by['old']!.weak), (-75, null, true));
      // ٨ نوفمبر: كلّ رقمٍ باسمه — tx إشارته من جهتنا، وrx حين لا يعطيها الطراز
      expect((by['abo']!.rxOnly, by['seed']!.rxOnly, by['old']!.rxOnly), (false, false, true));
      expect(DevicesCheck.subLine(by['seed']!), 'tx -74 dBm (rx -60) · CCQ 94٪');
      expect(DevicesCheck.subLine(by['old']!), 'rx -75 dBm · CCQ 90٪');
    });

    test('الوصلة: الإشارتان بالحيويّات، والحكم على الأضعف (عند الطرف الثاني)', () {
      final r = DevicesCheck.evaluate(
        d: dev(6, type: 'link', brand: 'ubnt'),
        alive: true,
        detail: detail(glance: const DeviceGlance(isAp: false, signal: -58, ccq: 96), peers: const [
          PeerLink(name: 'AP', signal: -58, txSignal: -83),
        ]),
      );
      expect(r.vitals.map((v) => '${v.k}=${v.v}'), containsAll(['الإشارة=-58 dBm', 'الطرف الثاني=-83 dBm', 'CCQ=96٪']));
      expect(texts(r), ['إشارة الوصلة -83 dBm — ضعيفة (عند الطرف الثاني)']);
    });

    test('الأولت: ضوء كلّ ONU بحدّ الفايبر، الأضعف أوّلاً', () {
      final r = DevicesCheck.evaluate(
        d: dev(8, type: 'other', brand: 'vsol'),
        alive: true,
        detail: const DeviceDetail(glance: DeviceGlance(onusOnline: 3, onusTotal: 4), onuLights: [
          OnuLight(name: 'ali', rx: -21.4),
          OnuLight(name: 'omar', rx: -28.9),
          OnuLight(name: 'zaid', rx: -24.0),
        ]),
        limits: const CheckLimits(fiberRxMin: -27),
      );
      expect(r.role, CheckRole.olt);
      expect(r.subs.map((x) => x.name), ['omar', 'zaid', 'ali']);
      expect(r.subs.first.weak, isTrue);
      expect(texts(r), ['ضوء ضعيف: 1 — من 3 مشترك']);
      expect(r.toText(), contains('omar: -28.9 dBm'));
    });

    test('عبر الـVPN: ts للمحطّة، وonus للأولت', () {
      final sec = DeviceVitals.fromVpn({'kind': 'airos', 'ap': true, 'peers': [{'n': 'abo', 's': -76, 'ts': -62, 'q': 82}]});
      expect((sec.detail!.peers.single.signal, sec.detail!.peers.single.txSignal), (-76, -62));
      final olt = DeviceVitals.fromVpn({'kind': 'olt', 'total': 4, 'online': 3, 'pons': [], 'onus': [{'n': 'omar', 'k': 'EPON0/1:2', 'rx': -28.9}]});
      expect(olt.detail!.onuLights.single.rx, -28.9);
      expect(olt.detail!.onuLights.single.name, 'omar');
    });
  });

  group('٦ نوفمبر — الماك: «النقر عليه يفتحله اليوزر المشابه… ونفس الشي للسكاتر»', () {
    const idx = {'a0b1c2d3e4f5': 'ali@popq', 'a0b1c2d3e4f9': 'omar@popq', '001122334455': 'zaid@popq'};
    test('المطابق، ثمّ الأقرب من الشركة نفسها بفرقٍ ≤ ٨، والتعادل والبعيد لا', () {
      expect(DevicesCheck.matchMac('A0:B1:C2:D3:E4:F5', idx), (user: 'ali@popq', approx: false));
      expect(DevicesCheck.matchMac('a0-b1-c2-d3-e4-f7', idx), isNull, reason: 'بين اثنين بالبعد نفسه ⇒ لا حسم');
      expect(DevicesCheck.matchMac('a0b1c2d3e4fb', idx), (user: 'omar@popq', approx: true));
      expect(DevicesCheck.matchMac('a0b1c2d3e5ff', idx), isNull, reason: 'أبعد من ٨');
      expect(DevicesCheck.matchMac('ffb1c2d3e4f5', idx), isNull, reason: 'شركةٌ أخرى');
      expect(DevicesCheck.matchMac('zz', idx), isNull);
      expect(DevicesCheck.fmtMac('a0b1c2d3e4f5'), 'A0:B1:C2:D3:E4:F5');
    });

    test('محطّة السكتر وONU الأولت تأخذان اليوزر بماكهما، والتقرير النصّيّ يحمل الماك', () {
      final sec = DevicesCheck.evaluate(
        d: dev(5, type: 'sector', brand: 'mikrotik'),
        alive: true,
        macUsers: idx,
        detail: detail(glance: const DeviceGlance(isAp: true), peers: const [
          PeerLink(name: '10.0.0.9', signal: -80, mac: 'A0:B1:C2:D3:E4:F5'),
          PeerLink(name: 'x', signal: -50, mac: '11:22:33:44:55:66'),
        ]),
        limits: lim,
      );
      expect(sec.subs.first.title, 'ali@popq');
      expect(sec.subs.first.mac, 'a0b1c2d3e4f5');
      expect(sec.subs.last.user, isNull);
      expect(sec.toText(), contains('ali@popq (A0:B1:C2:D3:E4:F5): rx -80 dBm'));
      final olt = DevicesCheck.evaluate(
        d: dev(8, type: 'other', brand: 'vsol'),
        alive: true,
        macUsers: idx,
        detail: const DeviceDetail(glance: DeviceGlance(onusTotal: 1), onuLights: [OnuLight(name: 'EPON0/1:3', rx: -22, mac: 'a0b1c2d3e4fb')]),
      );
      expect((olt.subs.single.title, olt.subs.single.approx), ('omar@popq', true));
    });
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

  group('٩ نوفمبر — «لم يُقرأ» بسببه الحقيقيّ (لا «تأكّد من اسم المستخدم والرمز» لكلّ فشل)', () {
    String why(Object e, {int deadline = 25, bool? serviceOk}) =>
        DevicesCheckRunner.unreadReason(e, deadline: deadline, serviceOk: serviceOk);
    const login = 'يردّ، لكن رُفض الدخول — تأكّد من اسم المستخدم والرمز';
    const service = 'يردّ، لكن خدمة الإدارة لا تجيب — تأكّد من المنفذ والبروتوكول';

    test('المهلة كلّها ⇒ «بطيء» بثوانيها (٢٥ من شبكتك، ٤٥ عبر الممرّ)', () {
      expect(why(TimeoutException('read', const Duration(seconds: 25))), 'بطيء — لم تكتمل قراءته خلال 25ث');
      expect(why(TimeoutException(null), deadline: 45), 'بطيء — لم تكتمل قراءته خلال 45ث');
    });

    test('رفض الدخول الحقيقيّ وحده يقول «اسم المستخدم والرمز» — ميكروتك، يوبيكويتي، سسكو', () {
      expect(why(MikrotikException('invalid user name or password (6)', code: 'auth')), login);
      expect(why(UbntException('اسم المستخدم أو كلمة المرور خطأ (SSH auth failed)')), login);
      expect(why(CiscoException('رُفض الدخول إلى 10.0.0.1 — تحقّق من اسم المستخدم وكلمة السرّ.')), login);
      expect(why(MikrotikException('not enough permissions (9)')), 'يردّ، لكن مستخدمه بلا صلاحيّة قراءة — راجع صلاحيّاته على الجهاز');
    });

    test('المنفذ المقفول/لا طريق ⇒ خدمة الإدارة؛ وزحمة الممرّ وسقوطه بكلمتهما', () {
      expect(why(const SocketException('Connection refused')), service);
      expect(why(MikrotikException('تعذّر الوصول عبر API والويب وSSH — فعّل إحداها على الجهاز (IP ← Services) أو اختر SNMP')), service);
      expect(why(UbntException('SSH port 22 مغلق — تأكّد أن SSH مفعّل على الجهاز')), service);
      expect(why(const SocketException('اتّصالاتٌ كثيرة الآن — لحظات')), 'اتّصالات كثيرة عبر الـVPN الآن — أعد الفحص بعد قليل');
      expect(why(const SocketException('الـVPN ما اتّصل الآن — حاول بعد قليل')), 'ممرّ الـVPN ما ردّ لحظتها — أعد الفحص بعد قليل');
    });

    test('بيانات الدخول: طلبها من خادمنا فشل (٥٠٣) أو ناقصة', () {
      final e503 = DioException(
        requestOptions: RequestOptions(path: '/api/v2/admin/devices/7/credentials'),
        response: Response(requestOptions: RequestOptions(path: '/api/v2/admin/devices/7/credentials'), statusCode: 503),
        type: DioExceptionType.badResponse,
      );
      expect(why(e503), 'تعذّر جلب بيانات دخوله من الخادم — أعد الفحص بعد قليل');
      expect(why(StateError('بيانات دخول ناقصة')), 'بيانات دخوله ناقصة — أكملها من صفحة الجهاز');
    });

    test('مهلةٌ من داخل القارئ: بطيءٌ إن أجابت خدمته البنك، وإلّا لا تُفتح؛ وSNMP بالـcommunity', () {
      final slowRead = MikrotikException('انتهت مهلة القراءة (timeout)');
      expect(why(slowRead, serviceOk: true), 'بطيء — ما كمّل جوابه بالوقت');
      expect(why(slowRead, serviceOk: false), service);
      final snmp = VsolException('تعذّر الاتّصال بالـOLT عبر SNMP: SNMP timeout بعد 4s — 10.0.0.9:161.');
      expect(why(snmp), 'يردّ، لكن SNMP ما جاوب — تأكّد من الـcommunity والمنفذ');
      expect(why(snmp, serviceOk: true), 'بطيء — ما كمّل جوابه بالوقت', reason: 'البنك أجاب بالـcommunity نفسها ⇒ بطيء لا خطأ');
    });

    test('ما لا يُعرف سببه لا يُنسب لاسم المستخدم أبداً', () {
      expect(why(StateError('x')), 'يردّ، لكن ما انقرت معلوماته');
      expect(why(StateError('x'), serviceOk: false), service);
      for (final e in [
        TimeoutException(null),
        const SocketException('Connection refused'),
        StateError('x'),
        MikrotikException('انتهت مهلة القراءة (timeout)'),
        VsolException('قراءةٌ ناقصة: لم يُجب الأولت بحالة كلّ الـONU'),
      ]) {
        expect(why(e), isNot(contains('اسم المستخدم')), reason: '$e');
      }
    });

    test('الفاحص يكتب السبب: جهازٌ بطيء «بطيء…» وجهازٌ رُفض دخوله «اسم المستخدم» — لا الجملة نفسها للاثنين', () async {
      SharedPreferences.setMockInitialValues({});
      DevicesCheckRunner.debugLimits = () async => const CheckLimits();
      DevicesCheckRunner.debugSubscribers = () async => const [];
      DevicesCheckRunner.debugProbe = (d) async => (status: 'online', responseMs: 4, packetLoss: 0.0, serviceOk: true);
      // ٩ نوفمبر (المرحلة ٢): المهلة لا تقطع — البطيء من لا تكتمل قراءته حتى السقف
      DevicesCheckRunner.debugTimes = (soft: const Duration(milliseconds: 50), hard: const Duration(milliseconds: 150));
      DevicesCheckRunner.debugFetch = (d) => d.id == 1
          ? Completer<ProbeResult>().future
          : Future<ProbeResult>.error(MikrotikException('invalid user name or password (6)', code: 'auth'));
      addTearDown(() {
        DevicesCheckRunner.debugLimits = null;
        DevicesCheckRunner.debugSubscribers = null;
        DevicesCheckRunner.debugProbe = null;
        DevicesCheckRunner.debugFetch = null;
        DevicesCheckRunner.debugTimes = null;
      });
      final run = DevicesCheckRunner([dev(1, type: 'sector'), dev(2)], viaVpn: false);
      await run.run();
      expect(run.reports[1]!.state, CheckState.unread);
      expect(texts(run.reports[1]!), ['بطيء — لم تكتمل قراءته خلال 0ث']);
      expect(texts(run.reports[2]!), [login]);
      // ومهلةٌ من داخل القارئ (لا الكلّيّة) والخدمة أجابت البنك ⇒ بطيء بلا ثوانٍ مدّعاة
      expect(DevicesCheckRunner.unreadReason(TimeoutException('ssh'), serviceOk: true), 'بطيء — ما كمّل جوابه بالوقت');
      run.dispose();
    });
  });

  group('٩ نوفمبر — جلب بيانات الدخول يتعثّر عابراً (٥٠٣): إعادة ApiClient مرّةً، ثمّ آخر بياناتٍ ≤ ١٠ د', () {
    late _CredsReplies srv;
    setUp(() {
      srv = _CredsReplies();
      ApiClient.dio.httpClientAdapter = srv;
      NetworkDevicesApi.invalidateCredentialsCache();
    });
    tearDown(NetworkDevicesApi.invalidateCredentialsCache);

    test('٥٠٣ ثمّ ٢٠٠ ⇒ تُقرأ (إعادة ApiClient العابرة)', () async {
      srv.codes.addAll([503, 200]);
      expect((await NetworkDevicesApi.getCredentials(7))['user'], 'admin');
      expect(srv.calls, 2);
    });

    test('٥٠٣ مرّتين ⇒ آخر بياناتٍ عمرها ٤ د؛ وعمرها ١١ د ⇒ يُرمى (ولا تُختلق)', () async {
      srv.codes.addAll([503, 503, 503, 503]);
      NetworkDevicesApi.debugSeedCredentials(7, {'user': 'old'}, DateTime.now().subtract(const Duration(minutes: 4)));
      expect((await NetworkDevicesApi.getCredentials(7))['user'], 'old');
      NetworkDevicesApi.debugSeedCredentials(7, {'user': 'old'}, DateTime.now().subtract(const Duration(minutes: 11)));
      await expectLater(NetworkDevicesApi.getCredentials(7), throwsA(isA<DioException>()));
      expect(srv.calls, 4, reason: 'طلبان لكلّ قراءة — لا إعادةٌ فوق إعادة ApiClient');
    });

    test('الرفض الصريح (٤٠٤ بجسم success:false) لا يأخذ القديم؛ والتحديث القسريّ لا يأخذ القديم', () async {
      srv.codes.addAll([404]);
      NetworkDevicesApi.debugSeedCredentials(7, {'user': 'old'}, DateTime.now().subtract(const Duration(minutes: 2)));
      await expectLater(NetworkDevicesApi.getCredentials(7), throwsA(isA<Exception>()));
      expect(srv.calls, 1);
      srv.codes.addAll([503, 503]);
      await expectLater(NetworkDevicesApi.getCredentials(7, forceRefresh: true), throwsA(isA<DioException>()));
      expect(srv.calls, 3);
    });
  });

  group('٩ نوفمبر — المهلة الأولى لا تقطع: سطرٌ مؤقّت ثمّ التقرير، والسقف «بطيء»، والمتأخّر يحلّ محلّه', () {
    ProbeResult res(DeviceDetail detail) => ProbeResult(vitals: const [], detail: detail, counters: const {});
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      DevicesCheckRunner.debugLimits = () async => const CheckLimits();
      DevicesCheckRunner.debugSubscribers = () async => const [];
      DevicesCheckRunner.debugProbe = (d) async => (status: 'online', responseMs: 4, packetLoss: 0.0, serviceOk: true);
      DevicesCheckRunner.debugTimes = (soft: const Duration(milliseconds: 150), hard: const Duration(milliseconds: 600));
    });
    tearDown(() {
      DevicesCheckRunner.debugLimits = null;
      DevicesCheckRunner.debugSubscribers = null;
      DevicesCheckRunner.debugProbe = null;
      DevicesCheckRunner.debugFetch = null;
      DevicesCheckRunner.debugTimes = null;
    });

    test('🚨 قراءةٌ أطول من المهلة الأولى وأقصر من السقف ⇒ «يقرأ…» مؤقّتاً ثمّ تقريرها — لا «لم يُقرأ»', () async {
      DevicesCheckRunner.debugFetch = (d) => Future.delayed(
          const Duration(milliseconds: 350), () => res(const DeviceDetail(glance: DeviceGlance(cpu: 12, uptimeSec: 86400 * 4))));
      final run = DevicesCheckRunner([dev(1)], viaVpn: false);
      final seen = <String>[];
      String? interim;
      run.addListener(() {
        final r = run.reports[1];
        if (r == null) return;
        seen.add('${r.pending ? 'pending' : r.state.name}|${run.slowPending.length}|${run.done}');
        if (r.pending) interim ??= texts(r).single;
      });
      await run.run();
      expect(seen.first, 'pending|1|0', reason: 'سطرٌ مؤقّت عند المهلة الأولى، والعدّاد لا يحسبه');
      expect(interim, startsWith('بطيء — يكمل قراءته'));
      expect(seen.last, 'ok|0|1');
      expect(run.reports[1]!.cpu, 12);
      run.dispose();
    });

    test('السقف ⇒ «بطيء — لم تكتمل قراءته خلال…»، والقراءة المتأخّرة بعده تحلّ محلّه (لا تُرمى) وتُحفظ لقطتها', () async {
      final late = Completer<ProbeResult>();
      DevicesCheckRunner.debugFetch = (d) => late.future;
      final run = DevicesCheckRunner([dev(2, type: 'switch')], viaVpn: false);
      await run.run();
      expect(run.running, isFalse);
      expect(run.reports[2]!.state, CheckState.unread);
      expect(texts(run.reports[2]!).single, startsWith('بطيء — لم تكتمل قراءته خلال'));
      expect(run.slowPending, isEmpty);
      late.complete(res(const DeviceDetail(glance: DeviceGlance(cpu: 7), ports: [PortTraffic(name: 'ether1', up: true, linkSpeed: '1Gbps')])));
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(run.reports[2]!.state, CheckState.ok);
      expect(run.reports[2]!.cpu, 7);
      expect((await DevicesCheckMemoStore.load())[2]!.ports['ether1']!.mbps, 1000);
      run.dispose();
    });

    test('أُغلق الفحص قبل أن تصل ⇒ لا تحديث بعد التخلّص (ولا استثناء)', () async {
      final late = Completer<ProbeResult>();
      DevicesCheckRunner.debugFetch = (d) => late.future;
      final run = DevicesCheckRunner([dev(3)], viaVpn: false);
      final f = run.run();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      run.dispose();
      late.complete(res(const DeviceDetail(glance: DeviceGlance(cpu: 1))));
      await f;
      await Future<void>.delayed(const Duration(milliseconds: 700));
      expect(run.reports[3], isNull);
    });

    test('🚨 ميكروتك بطيء بجدول التسجيل: الطبقة الأولى تُعرض عند المهلة الأولى، وعند السقف تبقى بحيويّاتها ومنافذها', () async {
      // القارئ الحقيقيّ (لا debugFetch): RouterOS يجيب الموارد والمنافذ فوراً وجدول التسجيل لا يجيب حتى بعد السقف
      DevicesCheckRunner.debugTimes = (soft: const Duration(milliseconds: 300), hard: const Duration(milliseconds: 900));
      NetworkDevicesApi.debugSeedCredentials(4, {'user': 'admin', 'pass': 'x'}, DateTime.now());
      final gate = Completer<void>();
      MikrotikApi.channelFactory = (route, ip, port, user, pass, timeout) => _SlowRegTable(holdRegTable: gate);
      addTearDown(() {
        if (!gate.isCompleted) gate.complete();
        NetworkDevicesApi.invalidateCredentialsCache();
        MikrotikApi.channelFactory = (route, ip, port, user, pass, timeout) => throw UnimplementedError(route);
        MikrotikApi.resetRoutesForTest();
      });
      final run = DevicesCheckRunner([dev(4, type: 'sector')], viaVpn: false);
      String? interim;
      run.addListener(() {
        final r = run.reports[4];
        if (r != null && r.pending) interim ??= '${r.cpu}|${texts(r).join(',')}';
      });
      await run.run();
      expect(interim, startsWith('9|'), reason: 'المعالج من الطبقة الأولى منذ المهلة الأولى');
      expect(interim, contains('قراءةٌ جزئيّة — بطيء — يكمل قراءته'));
      final r = run.reports[4]!;
      expect(r.cpu, 9);
      expect(r.portsTotal, 1);
      expect(texts(r), contains('قائمة مشتركيه ما انقرت'), reason: 'لا «ما عليه أحد» من طبقةٍ بلا جدول');
      expect(texts(r).any((t) => t.startsWith('قراءةٌ جزئيّة — بطيء — لم تكتمل قراءته خلال')), isTrue);
      expect(r.state, CheckState.unread);
      run.dispose();
    });
  });

  group('٩ نوفمبر — آخر قراءةٍ ≤ ٥ د حين لا تكتمل الجديدة: بعمرها، لا تُقدَّم طازجةً ولا تكتب اللقطة', () {
    setUp(() {
      DeviceStatsCache.instance.clear();
      DevicesCheckRunner.debugLimits = () async => const CheckLimits();
      DevicesCheckRunner.debugSubscribers = () async => const [];
      DevicesCheckRunner.debugProbe = (d) async => (status: 'online', responseMs: 4, packetLoss: 0.0, serviceOk: true);
      DevicesCheckRunner.debugTimes = (soft: const Duration(milliseconds: 80), hard: const Duration(milliseconds: 250));
    });
    tearDown(() {
      DeviceStatsCache.instance.clear();
      DevicesCheckRunner.debugLimits = null;
      DevicesCheckRunner.debugSubscribers = null;
      DevicesCheckRunner.debugProbe = null;
      DevicesCheckRunner.debugFetch = null;
      DevicesCheckRunner.debugTimes = null;
      VpnNow.reset();
    });

    const shown = DeviceDetail(
        glance: DeviceGlance(cpu: 33, temp: 41, uptimeSec: 86400 * 6),
        ports: [PortTraffic(name: 'ether1', up: false), PortTraffic(name: 'ether2', up: true, linkSpeed: '1Gbps')]);

    test('🚨 بطاقةٌ تعرض أرقاماً ⇒ الفحص يعرضها بعمرها مؤقّتاً وعند السقف — والمنفذ لا يُقارَن ولا تُكتب اللقطة', () async {
      SharedPreferences.setMockInitialValues({});
      await DevicesCheckMemoStore.save({
        9: const CheckMemo(ports: {'ether1': PortMemo(up: true, mbps: 1000)})
      });
      DeviceStatsCache.instance.putVitals(9, const [], shown);
      DevicesCheckRunner.debugFetch = (d) => Completer<ProbeResult>().future;
      final run = DevicesCheckRunner([dev(9, type: 'switch')], viaVpn: false);
      DeviceCheckReport? interim;
      run.addListener(() {
        final r = run.reports[9];
        if (r != null && r.pending) interim ??= r;
      });
      await run.run();
      expect(interim!.cpu, 33, reason: 'الأرقام من آخر قراءة منذ المهلة الأولى');
      expect(interim!.staleAt, isNotNull);
      final r = run.reports[9]!;
      expect(r.cpu, 33);
      expect(r.staleAge, 'قبل لحظات');
      expect(texts(r).first, startsWith('آخر قراءة قبل لحظات؛ الجديدة: بطيء — لم تكتمل قراءته خلال'),
          reason: 'العمر بالسطر نفسه (المراجعة)');
      expect(texts(r).where((t) => t.contains('طفى')), isEmpty, reason: 'لا مقارنة منافذ من قراءةٍ سابقة');
      expect(r.stateLabel, 'سليم · قبل لحظات', reason: 'الحال بعمرها — لا تُقدَّم طازجة');
      expect(r.toText(), startsWith('جهاز 9 (سويج) — سليم · قبل لحظات'), reason: 'النسخ يحمل عمرها');
      expect((await DevicesCheckMemoStore.load())[9]!.ports['ether1']!.up, isTrue, reason: 'اللقطة لا تُكتب من قراءةٍ سابقة');
      run.dispose();
    });

    test('رفض الدخول يُقال وحده — لا أرقامٌ قديمة تغطّيه؛ وبلا قراءةٍ محفوظة «لم يُقرأ» بسببه', () async {
      SharedPreferences.setMockInitialValues({});
      DeviceStatsCache.instance.putVitals(10, const [], shown);
      DevicesCheckRunner.debugFetch = (d) => Future<ProbeResult>.error(d.id == 10
          ? MikrotikException('invalid user name or password (6)', code: 'auth')
          : const SocketException('Connection refused'));
      final run = DevicesCheckRunner([dev(10), dev(11)], viaVpn: false);
      await run.run();
      expect(run.reports[10]!.staleAt, isNull);
      expect(run.reports[10]!.cpu, isNull);
      expect(texts(run.reports[10]!), ['يردّ، لكن رُفض الدخول — تأكّد من اسم المستخدم والرمز']);
      expect(run.reports[11]!.state, CheckState.unread);
      expect(run.reports[11]!.staleAt, isNull);
      run.dispose();
    });

    test('أقدم من ٥ د أو قراءةٌ بلا أرقام لا تُستعمل؛ وعبر الـVPN ما قرأه الخادم «من فحص الخادم» بلحظة خادمه', () async {
      final r = DevicesCheckRunner([dev(12)], viaVpn: true);
      expect(r.lastReadingFor(dev(12)), isNull);
      DeviceStatsCache.instance.putVitals(12, const [], const DeviceDetail());
      expect(r.lastReadingFor(dev(12)), isNull, reason: 'لا رقم فيها');
      final serverAt = DateTime.now().subtract(const Duration(minutes: 1));
      VpnNow.debugApply(
          VpnNowKind.devices,
          VpnNowResult(ok: true, message: 'تم', atMs: serverAt.millisecondsSinceEpoch, devices: const [
            VpnDeviceResult(id: 12, alive: true, vitals: {'kind': 'ros', 'cpu': 17, 'up': 3600}),
            VpnDeviceResult(id: 13, alive: true, vitals: {'kind': 'olt', 'online': 90, 'total': 100}),
          ]));
      final last = r.lastReadingFor(dev(12))!;
      expect(last.from, 'آخر قراءة من فحص الخادم');
      expect(last.detail.glance.cpu, 17);
      expect(last.at,
          DateTime.fromMillisecondsSinceEpoch(serverAt.millisecondsSinceEpoch).subtract(DevicesCheckRunner.serverVitalsReuse),
          reason: 'بلحظة الخادم ناقص نافذة إعادة استعماله — الأقدم المحتمل، لا لحظة وصولها');
      expect(r.lastReadingFor(dev(13)), isNull, reason: 'ملخّص الأولت قد يبلغ ٣٠ د بلا لحظته');
      // فحص خادمٍ انتهى قبل ٣ د ⇒ قراءته قد تكون ٥٫٥ د ⇒ لا
      VpnNow.debugApply(
          VpnNowKind.devices,
          VpnNowResult(ok: true, message: 'تم', atMs: DateTime.now().subtract(const Duration(minutes: 3)).millisecondsSinceEpoch, devices: const [
            VpnDeviceResult(id: 12, alive: true, vitals: {'kind': 'ros', 'cpu': 17, 'up': 3600}),
          ]));
      expect(r.lastReadingFor(dev(12)), isNull);
      // خادمٌ يعطي لحظة القراءة نفسها (v_at_ms) ⇒ بها، وللأولت أيضاً
      final own = DateTime.now().subtract(const Duration(minutes: 2));
      VpnNow.debugApply(
          VpnNowKind.devices,
          VpnNowResult.fromJson({
            'ok': true,
            'message': 'تم',
            'at_ms': DateTime.now().millisecondsSinceEpoch,
            'devices': [
              {'id': 13, 'alive': true, 'v': {'kind': 'olt', 'online': 90, 'total': 100}, 'v_at_ms': own.millisecondsSinceEpoch},
            ],
          }));
      expect(r.lastReadingFor(dev(13))!.at, DateTime.fromMillisecondsSinceEpoch(own.millisecondsSinceEpoch));
      expect(DevicesCheck.ago(DateTime(2026, 11, 9, 10), DateTime(2026, 11, 9, 10, 4)), 'قبل 4 د');
      r.dispose();
    });

    test('حدود آخر قراءة: المعروضة بعمر ٦ د لا؛ الخفيفة الخام بعمرها؛ والكاملة التي جدّدت لحظتَها قراءةٌ خفيفة لا', () {
      final r = DevicesCheckRunner([dev(14)], viaVpn: false);
      final real = DeviceStatsCache.clock;
      addTearDown(() => DeviceStatsCache.clock = real);
      final t0 = DateTime.now();
      DeviceStatsCache.clock = () => t0.subtract(const Duration(minutes: 6));
      DeviceStatsCache.instance.putVitals(14, const [], const DeviceDetail(glance: DeviceGlance(cpu: 9)));
      DeviceStatsCache.clock = real;
      expect(r.lastReadingFor(dev(14)), isNull, reason: 'أقدم من ٥ د');
      // الخفيفة الخام (التسخين) قبل ٣ د ⇒ تُستعمل بعمرها
      const light = MikrotikStats(
          cpuLoad: 12, memUsedPercent: 30, memTotalBytes: 64, memFreeBytes: 40, uptime: '1d', version: '7.15',
          boardName: 'CCR1009', architectureName: 'tile', cpuCount: 9, cpuFrequencyMhz: 1200,
          interfaces: [MikrotikInterface(name: 'ether1', type: 'ether', running: true, disabled: false)],
          pppActiveCount: 0, clientsRead: false);
      DeviceStatsCache.clock = () => t0.subtract(const Duration(minutes: 3));
      DeviceStatsCache.instance.putRaw(15, light, detailed: false);
      DeviceStatsCache.clock = real;
      final l = r.lastReadingFor(dev(15))!;
      expect(l.detail.glance.cpu, 12);
      expect(t0.difference(l.at).inMinutes, 3);
      // كاملةٌ قبل ٩٠ث (طازجةٌ للبذر) ثمّ خفيفةٌ الآن: تجدّد لحظتها ولا تغيّر أرقامها ⇒ لا تُقدَّم «قبل لحظات»
      DeviceStatsCache.clock = () => t0.subtract(const Duration(seconds: 90));
      DeviceStatsCache.instance.putRaw(16, light, detailed: true);
      DeviceStatsCache.clock = real;
      DeviceStatsCache.instance.putRaw(16, light, detailed: false);
      expect(r.lastReadingFor(dev(16)), isNull);
      r.dispose();
    });

    test('سكترٌ من آخر قراءةٍ بجدولٍ مقروءٍ فارغ ⇒ لا «ما عليه أحد الآن» (قراءةٌ سابقة لا تقول «الآن»)', () {
      final now = DateTime(2026, 11, 9, 12);
      final r = DevicesCheck.evaluate(
          d: dev(17, type: 'sector'),
          alive: true,
          detail: detail(glance: const DeviceGlance(isAp: true, peersKnown: true, cpu: 4)),
          limits: lim,
          prev: const CheckMemo(peers: 7),
          staleAt: now.subtract(const Duration(minutes: 2)),
          now: now);
      expect(texts(r).where((t) => t.contains('ما عليه أحد')), isEmpty);
      expect(texts(r), contains('قائمة مشتركيه ما انقرت'));
    });
  });

  group('٩ نوفمبر — «الحال فقط» قسمٌ وحده، «أعد قراءة غير المقروء»، وطريق القراءة وزمنها على السطر', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      DevicesCheckRunner.debugLimits = () async => const CheckLimits();
      DevicesCheckRunner.debugSubscribers = () async => const [];
      DevicesCheckRunner.debugProbe = (d) async => (status: 'online', responseMs: 4, packetLoss: 0.0, serviceOk: true);
    });
    tearDown(() {
      DevicesCheckRunner.debugLimits = null;
      DevicesCheckRunner.debugSubscribers = null;
      DevicesCheckRunner.debugProbe = null;
      DevicesCheckRunner.debugFetch = null;
    });

    test('بلا بيانات دخول ⇒ «الحال فقط» بسببه (لا «لم يُقرأ»)، آخراً بالترتيب ومعدودٌ وحده', () async {
      DevicesCheckRunner.debugFetch =
          (d) async => const ProbeResult(vitals: [], detail: DeviceDetail(glance: DeviceGlance(cpu: 3)), counters: {});
      final noCreds = NetworkDevice(
          id: 21, adminId: '2', name: 'كاميرا', type: 'camera', brand: 'other', ip: '10.0.0.21', port: 80,
          hasCredentials: false, lastStatus: 'online', createdAt: DateTime(2026, 11, 1));
      final run = DevicesCheckRunner([noCreds, dev(22)], viaVpn: false);
      await run.run();
      final r = run.reports[21]!;
      expect(r.state, CheckState.statusOnly);
      expect(r.stateLabel, 'الحال فقط');
      expect(texts(r), ['بلا بيانات دخول']);
      expect(run.unreadCount, 0, reason: 'ليس «لم يُقرأ» — لا يُعاد');
      expect(DevicesCheck.sorted(run.reports.values).last.device.id, 21);
      expect(DevicesCheck.reportText(run.reports.values.toList(), viaVpn: false), contains('سليم 1 · الحال فقط 1'));
      run.dispose();
    });

    test('«أعد قراءة غير المقروء» يقرأ ما لم يُقرأ وحده — والباقي بتقريره بلا جلسةٍ ثانية', () async {
      final calls = <int, int>{};
      var fail = true;
      DevicesCheckRunner.debugFetch = (d) async {
        calls[d.id] = (calls[d.id] ?? 0) + 1;
        if (d.id == 32 && fail) throw const SocketException('Connection refused');
        return const ProbeResult(vitals: [], detail: DeviceDetail(glance: DeviceGlance(cpu: 4)), counters: {});
      };
      final run = DevicesCheckRunner([dev(31), dev(32), dev(33)], viaVpn: false);
      await run.run();
      expect(run.unreadCount, 1);
      final kept = run.reports[31];
      fail = false;
      await run.rerunUnread();
      expect(calls, {31: 1, 32: 2, 33: 1});
      expect(run.reports[32]!.state, CheckState.ok);
      expect(identical(run.reports[31], kept), isTrue, reason: 'المقروء يبقى بتقريره');
      expect([run.done, run.total], [3, 3]);
      expect(run.unreadCount, 0);
      run.dispose();
    });

    test('الطريق والزمن: ميكروتك من جلسته، وSNMP للأولت وميموزا وروجي، وسسكو ببروتوكوله، وعبر الممرّ يُقال؛ يوبيكويتي لا يُخمَّن', () {
      const ssh = MikrotikStats(
          cpuLoad: 1, memUsedPercent: 1, memTotalBytes: 1, memFreeBytes: 1, uptime: '', version: '', boardName: '',
          architectureName: '', cpuCount: 1, cpuFrequencyMhz: 1, interfaces: [], pppActiveCount: 0, via: 'SSH');
      expect(DevicesCheckRunner.viaOf(dev(1), ssh, piped: false), 'SSH');
      expect(DevicesCheckRunner.viaOf(dev(1), ssh, piped: true), 'SSH عبر الـVPN');
      expect(DevicesCheckRunner.viaOf(dev(2, brand: 'mimosa'), null, piped: false), 'SNMP');
      expect(DevicesCheckRunner.viaOf(dev(3, brand: 'ubnt'), null, piped: false), isNull);
      final r = DevicesCheck.evaluate(
          d: dev(4), alive: true, detail: detail(glance: const DeviceGlance(cpu: 5)), readVia: 'SSH', readMs: 18300);
      expect(r.readLine, 'SSH · 18ث');
      final fast = DevicesCheck.evaluate(
          d: dev(4), alive: true, detail: detail(glance: const DeviceGlance(cpu: 5)), readVia: 'API', readMs: 420);
      expect(fast.readLine, 'API · 0.4ث');
    });
  });

  group('المراجعة — قراءةٌ بلا طبقة اللاسلكيّ لا تُحكم «سليم» (سكتر بيس بوكس محفوظٌ «راوتر»)', () {
    MikrotikStats tier1({bool wlan = true, bool clientsRead = false, List<MikrotikWireless> wireless = const []}) => MikrotikStats(
          cpuLoad: 9, memUsedPercent: 30, memTotalBytes: 64, memFreeBytes: 40, uptime: '2w', version: '6.34.3',
          boardName: 'BaseBox 5', architectureName: 'mipsbe', cpuCount: 1, cpuFrequencyMhz: 720,
          interfaces: [
            const MikrotikInterface(name: 'ether1', type: 'ether', running: true, disabled: false),
            if (wlan) const MikrotikInterface(name: 'wlan1', type: 'wlan', running: true, disabled: false),
          ],
          pppActiveCount: 0, wirelessInterfaces: wireless, clientsRead: clientsRead);

    test('الطبقة الأولى بواجهة wlan مفعّلة ⇒ لاسلكيّه لم يُقرأ؛ وبلا راديو (CCR) أو مقروءة كاملة ⇒ يُحكم عليه', () {
      ProbeResult r(MikrotikStats s) => DeviceVitals.mikrotikResult(dev(1), s, null, detailed: true);
      expect(r(tier1()).detail.glance.radioUnread, isTrue);
      expect(r(tier1(wlan: false)).detail.glance.radioUnread, isFalse, reason: 'لا واجهة لاسلكيّة — راوترٌ فعلاً');
      expect(r(tier1(clientsRead: true)).detail.glance.radioUnread, isFalse);
      // طبقة SNMP الأولى بلا واجهات أصلاً ⇒ مجهول
      expect(r(tier1(wlan: false).copyWith(interfaces: const [])).detail.glance.radioUnread, isTrue);
    });

    test('🚨 نوع السجلّ «راوتر» (كسجلّات المالك) ⇒ «لم يُقرأ — وضعه اللاسلكيّ ومشتركوه ما انقرأوا» لا «راوتر · سليم»', () {
      final p = DeviceVitals.mikrotikResult(dev(1), tier1(), null, detailed: true);
      final r = DevicesCheck.evaluate(d: dev(1), alive: true, detail: p.detail, raw: p.raw, limits: lim);
      expect(r.role, CheckRole.router);
      expect(r.state, CheckState.unread);
      expect(texts(r), ['وضعه اللاسلكيّ ومشتركوه ما انقرأوا']);
      expect(r.cpu, 9, reason: 'ما قُرئ يُعرض');
      // وملاحظةٌ حقيقيّة تبقى «ملاحظات»
      final hot = DeviceVitals.mikrotikResult(dev(1), tier1().copyWith(), null, detailed: true);
      final warm = DevicesCheck.evaluate(
          d: dev(1),
          alive: true,
          detail: DeviceDetail(glance: DeviceGlance(cpu: 97, radioUnread: hot.detail.glance.radioUnread)),
          limits: lim);
      expect(warm.state, CheckState.warn);
    });

    test('الدور من آخر قراءةٍ قُرئ لاسلكيّها: سكترٌ ⇒ «قائمة مشتركيه ما انقرت»، ووصلةٌ ⇒ «إشارة الوصلة ما انقرت»', () {
      final full = DeviceVitals.mikrotikResult(
          dev(1),
          tier1(clientsRead: true, wireless: const [
            MikrotikWireless(name: 'wlan1', ssid: 'S', mode: 'ap-bridge', band: '5ghz-a/n', frequency: 5180, channelWidth: 20, txPower: 20, disabled: false, running: true)
          ]),
          null,
          detailed: true);
      final first = DevicesCheck.evaluate(d: dev(1), alive: true, detail: full.detail, raw: full.raw, limits: lim);
      expect(first.role, CheckRole.sector);
      expect(first.memo!.role, CheckRole.sector, reason: 'الدور يُحفظ من قراءةٍ قُرئ لاسلكيّها');
      final memo = CheckMemo.fromJson(first.memo!.toJson());
      final part = DeviceVitals.mikrotikResult(dev(1), tier1(), null, detailed: true);
      final next = DevicesCheck.evaluate(d: dev(1), alive: true, detail: part.detail, raw: part.raw, limits: lim, prev: memo);
      expect(next.role, CheckRole.sector);
      expect(texts(next), ['قائمة مشتركيه ما انقرت']);
      expect(next.state, CheckState.unread);
      expect(next.memo!.role, CheckRole.sector, reason: 'الجهل لا يمحو الدور');
      // لقطةٌ قديمة بلا دور لكن فيها مشتركون ⇒ سكتر
      final old = DevicesCheck.evaluate(
          d: dev(1), alive: true, detail: part.detail, raw: part.raw, limits: lim, prev: const CheckMemo(peers: 6));
      expect(old.role, CheckRole.sector);
      // الوصلة (نوعها link) بلا إشارة
      final link = DevicesCheck.evaluate(d: dev(2, type: 'link'), alive: true, detail: part.detail, raw: part.raw, limits: lim);
      expect(link.role, CheckRole.link);
      expect(texts(link), ['إشارة الوصلة ما انقرت']);
      expect(link.state, CheckState.unread);
    });

    test('🚨 الفاحص: «راوتر» بطيءٌ بلاسلكيّه ⇒ المؤقّت والسقف «لم يُقرأ» بحيويّاته — لا «سليم»', () async {
      SharedPreferences.setMockInitialValues({});
      DevicesCheckRunner.debugLimits = () async => const CheckLimits();
      DevicesCheckRunner.debugSubscribers = () async => const [];
      DevicesCheckRunner.debugProbe = (d) async => (status: 'online', responseMs: 4, packetLoss: 0.0, serviceOk: true);
      DevicesCheckRunner.debugTimes = (soft: const Duration(milliseconds: 300), hard: const Duration(milliseconds: 900));
      NetworkDevicesApi.debugSeedCredentials(5, {'user': 'admin', 'pass': 'x'}, DateTime.now());
      final gate = Completer<void>();
      MikrotikApi.channelFactory = (route, ip, port, user, pass, timeout) => _SlowRegTable(holdWireless: gate);
      addTearDown(() {
        if (!gate.isCompleted) gate.complete();
        DevicesCheckRunner.debugLimits = null;
        DevicesCheckRunner.debugSubscribers = null;
        DevicesCheckRunner.debugProbe = null;
        DevicesCheckRunner.debugTimes = null;
        NetworkDevicesApi.invalidateCredentialsCache();
        MikrotikApi.channelFactory = (route, ip, port, user, pass, timeout) => throw UnimplementedError(route);
        MikrotikApi.resetRoutesForTest();
      });
      final run = DevicesCheckRunner([dev(5)], viaVpn: false); // النوع الافتراضيّ «router» كسجلّات المالك
      final interim = <CheckState>[];
      run.addListener(() {
        final r = run.reports[5];
        if (r != null && r.pending) interim.add(r.state);
      });
      await run.run();
      expect(interim, isNotEmpty);
      expect(interim.toSet(), {CheckState.unread}, reason: 'المؤقّت لا يُعدّ «سليم»');
      final r = run.reports[5]!;
      expect(r.state, CheckState.unread);
      expect(texts(r), contains('وضعه اللاسلكيّ ومشتركوه ما انقرأوا'));
      expect(r.cpu, 9);
      run.dispose();
    });

    test('آخر قراءةٍ خفيفة (التسخين) لراوترٍ له راديو ⇒ «لم يُقرأ · قبل…» لا «سليم · قبل…»', () async {
      SharedPreferences.setMockInitialValues({});
      DeviceStatsCache.instance.clear();
      addTearDown(DeviceStatsCache.instance.clear);
      DeviceStatsCache.instance.putRaw(6, tier1(), detailed: false);
      DevicesCheckRunner.debugLimits = () async => const CheckLimits();
      DevicesCheckRunner.debugSubscribers = () async => const [];
      DevicesCheckRunner.debugProbe = (d) async => (status: 'online', responseMs: 4, packetLoss: 0.0, serviceOk: true);
      DevicesCheckRunner.debugFetch = (d) => Future<ProbeResult>.error(const SocketException('Connection refused'));
      addTearDown(() {
        DevicesCheckRunner.debugLimits = null;
        DevicesCheckRunner.debugSubscribers = null;
        DevicesCheckRunner.debugProbe = null;
        DevicesCheckRunner.debugFetch = null;
      });
      final run = DevicesCheckRunner([dev(6)], viaVpn: false);
      await run.run();
      final r = run.reports[6]!;
      expect(r.staleAt, isNotNull);
      expect(r.state, CheckState.unread);
      expect(r.stateLabel, startsWith('لم يُقرأ · قبل'));
      expect(texts(r), contains('وضعه اللاسلكيّ ومشتركوه ما انقرأوا'));
      run.dispose();
    });

    test('قراءةٌ بلا منافذ (طبقة SNMP الأولى) لا تمحو منافذ اللقطة؛ والقراءة السابقة تُقدَّم مدّة تشغيلها بعمرها', () {
      const prev = CheckMemo(ports: {'sfp1': PortMemo(up: true, mbps: 1000)});
      final r = DevicesCheck.evaluate(
          d: dev(7), alive: true, detail: detail(glance: const DeviceGlance(cpu: 5)), limits: lim, prev: prev);
      expect(r.memo!.ports['sfp1']!.up, isTrue);
      final now = DateTime(2026, 11, 9, 12);
      final stale = DevicesCheck.evaluate(
          d: dev(8),
          alive: true,
          detail: detail(glance: const DeviceGlance(cpu: 5, uptimeSec: 120)),
          limits: lim,
          staleAt: now.subtract(const Duration(minutes: 4)),
          now: now);
      expect(texts(stale), contains('اشتغل قبل 6 د — انطفى أو أُعيد تشغيله'), reason: 'دقيقتان يومها + ٤ عمرها');
      expect(stale.uptimeSec, 360);
    });
  });

  group('المراجعة — المؤقّت وآخر قراءة لا يُعدّان «سليماً» الآن، والعمر ظاهرٌ دائماً', () {
    final now = DateTime(2026, 11, 9, 12);
    DeviceCheckReport rep(int id, {bool pending = false, DateTime? staleAt}) => DevicesCheck.evaluate(
        d: dev(id), alive: true, detail: detail(glance: const DeviceGlance(cpu: 5)), pending: pending, staleAt: staleAt, now: now);

    test('الشارة: الجاري «يقرأ…» ومن آخر قراءةٍ «يقرأ… · آخر قراءة قبل 3 د»؛ والنسخ كذلك', () {
      final fresh = rep(1);
      final pending = rep(2, pending: true);
      final pendingStale = rep(3, pending: true, staleAt: now.subtract(const Duration(minutes: 3)));
      final stale = rep(4, staleAt: now.subtract(const Duration(minutes: 3)));
      expect([fresh.stateLabel, pending.stateLabel, pendingStale.stateLabel, stale.stateLabel],
          ['سليم', 'يقرأ…', 'يقرأ… · آخر قراءة قبل 3 د', 'سليم · قبل 3 د']);
      expect(pendingStale.toText(), startsWith('جهاز 3 (راوتر) — يقرأ… · آخر قراءة قبل 3 د'));
      expect([fresh.bucket, pending.bucket, pendingStale.bucket, stale.bucket],
          [CheckBucket.ok, CheckBucket.pending, CheckBucket.pending, CheckBucket.stale]);
    });

    test('رأس النسخ: «سليم» للطازج وحده، و«يقرأ n» و«آخر قراءة n» وحدهما، و«لم يكتمل» أثناء الفحص', () {
      final rs = [rep(1), rep(2, pending: true), rep(4, staleAt: now.subtract(const Duration(minutes: 3)))];
      final txt = DevicesCheck.reportText(rs, viaVpn: false, progress: (done: 2, total: 5));
      expect(txt.split('\n').first, 'الفحص الشامل — 3 جهاز: سليم 1 · يقرأ 1 · آخر قراءة 1 — لم يكتمل: 2 من 5');
      expect(DevicesCheck.reportText(rs, viaVpn: false).split('\n').first, isNot(contains('لم يكتمل')));
    });
  });

  group('المراجعة — القراءة المتأخّرة لا تُسقط، و«أعد قراءة غير المقروء» لا يفتح جلسةً ثانية', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      DeviceStatsCache.instance.clear();
      DevicesCheckRunner.debugLimits = () async => const CheckLimits();
      DevicesCheckRunner.debugSubscribers = () async => const [];
      DevicesCheckRunner.debugProbe = (d) async => (status: 'online', responseMs: 4, packetLoss: 0.0, serviceOk: true);
      DevicesCheckRunner.debugTimes = (soft: const Duration(milliseconds: 200), hard: const Duration(milliseconds: 500));
    });
    tearDown(() {
      DeviceStatsCache.instance.clear();
      DevicesCheckRunner.debugLimits = null;
      DevicesCheckRunner.debugSubscribers = null;
      DevicesCheckRunner.debugProbe = null;
      DevicesCheckRunner.debugFetch = null;
      DevicesCheckRunner.debugTimes = null;
    });
    const ok = ProbeResult(vitals: [], detail: DeviceDetail(glance: DeviceGlance(cpu: 3, uptimeSec: 86400)), counters: {});

    test('🚨 جهازٌ بلغ السقف وقراءته جارية ⇒ «أعد قراءة غير المقروء» ينتظرها (لا جلسة ثانية)، ووصولها يحلّ محلّه', () async {
      final calls = <int, int>{};
      final late = Completer<ProbeResult>();
      DevicesCheckRunner.debugFetch = (d) {
        calls[d.id] = (calls[d.id] ?? 0) + 1;
        return late.future;
      };
      final run = DevicesCheckRunner([dev(41)], viaVpn: false);
      await run.run();
      expect(run.unreadCount, 1);
      final again = run.rerunUnread();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      late.complete(ok);
      await again;
      expect(calls[41], 1, reason: 'الجلسة نفسها — لا ثانيةٌ على الجهاز البطيء');
      expect(run.reports[41]!.state, CheckState.ok);
      expect(run.reports[41]!.cpu, 3);
      run.dispose();
    });

    test('🚨 بعد «أعد قراءة غير المقروء» لجهازٍ آخر: قراءة الجهاز المسقوف تصل وتحلّ محلّ سطره (لا تُسقطها الجولة الجديدة)', () async {
      // القارئ الحقيقيّ للاثنين: 42 راوترٌ بلا راديو طبقته الثانية معلّقة، و43 يرفض الاتّصال أوّلاً
      for (final id in [42, 43]) {
        NetworkDevicesApi.debugSeedCredentials(id, {'user': 'admin', 'pass': 'x'}, DateTime.now());
      }
      final gate = Completer<void>();
      var refuse43 = true;
      final realProbe = MikrotikApi.portProbe;
      addTearDown(() => MikrotikApi.portProbe = realProbe);
      MikrotikApi.portProbe = (ip, port) async => false;
      MikrotikApi.channelFactory = (route, ip, port, user, pass, timeout) => ip.endsWith('.43')
          ? (refuse43 ? _RefusedCh() : _SlowRegTable(radio: false))
          : _SlowRegTable(holdWireless: gate, radio: false);
      addTearDown(() {
        if (!gate.isCompleted) gate.complete();
        NetworkDevicesApi.invalidateCredentialsCache();
        MikrotikApi.channelFactory = (route, ip, port, user, pass, timeout) => throw UnimplementedError(route);
        MikrotikApi.resetRoutesForTest();
      });
      DevicesCheckRunner.debugFetch = null;
      final run = DevicesCheckRunner([dev(42), dev(43)], viaVpn: false);
      await run.run();
      final capped = run.reports[42]!;
      expect(capped.state, CheckState.ok, reason: 'راوترٌ بلا راديو: طبقته الأولى تكفي — ليس «لم يُقرأ» فلا يُعاد');
      expect(texts(capped).first, startsWith('قراءةٌ جزئيّة — بطيء — لم تكتمل قراءته خلال'));
      expect(run.unreadCount, 1, reason: '43 وحده');
      refuse43 = false;
      MikrotikApi.resetRoutesForTest();
      await run.rerunUnread();
      expect(run.reports[43]!.state, CheckState.ok);
      gate.complete();
      for (var i = 0; i < 50 && identical(run.reports[42], capped); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(identical(run.reports[42], capped), isFalse, reason: 'وصلت كاملةً فحلّت محلّه');
      expect(texts(run.reports[42]!).where((t) => t.startsWith('قراءةٌ جزئيّة')), isEmpty);
      run.dispose();
    });

    test('ما عُرض من آخر قراءةٍ يُعدّ ويُعاد بـ«أعد قراءة غير المقروء»', () async {
      DeviceStatsCache.instance.putVitals(44, const [], const DeviceDetail(glance: DeviceGlance(cpu: 8, uptimeSec: 86400)));
      var fail = true;
      DevicesCheckRunner.debugFetch =
          (d) => fail ? Future<ProbeResult>.error(const SocketException('Connection refused')) : Future.value(ok);
      final run = DevicesCheckRunner([dev(44)], viaVpn: false);
      await run.run();
      expect(run.reports[44]!.staleAt, isNotNull);
      expect(run.reports[44]!.state, CheckState.ok);
      expect(run.unreadCount, 1, reason: 'قراءته الجديدة لم تكتمل');
      fail = false;
      await run.rerunUnread();
      expect(run.reports[44]!.staleAt, isNull);
      expect(run.unreadCount, 0);
      run.dispose();
    });
  });
}

/// خادمٌ يردّ بالرموز بالترتيب (٢٠٠ = بيانات الدخول).
class _CredsReplies implements HttpClientAdapter {
  final codes = <int>[];
  var calls = 0;
  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? body, Future<void>? cancel) async {
    calls++;
    final code = codes.isEmpty ? 200 : codes.removeAt(0);
    final data = code == 200
        ? {'success': true, 'credentials': {'user': 'admin', 'pass': 'x'}}
        : {'success': false, 'message': 'x'};
    return ResponseBody.fromString(jsonEncode(data), code, headers: {
      Headers.contentTypeHeader: ['application/json'],
    });
  }

  @override
  void close({bool force = false}) {}
}

/// RouterOS يجيب الطبقة الأولى فوراً وجدول التسجيل بعد ثانيتين (سكتر بطيء عبر SSH).
class _SlowRegTable implements RouterOsChannel {
  _SlowRegTable({this.holdWireless, this.holdRegTable, this.radio = true});

  /// بلا راديو (CCR): لا واجهة wlan، وأمر اللاسلكيّ «no such command» (بعد بوّابته).
  final bool radio;

  /// أمر اللاسلكيّ / جدول التسجيل ينتظر حتى يُفتح البوّاب (الاختبار يفتحه بعد السقف) — لا ثوانٍ حقيقيّة.
  final Completer<void>? holdWireless;
  final Completer<void>? holdRegTable;
  @override
  String get via => 'SSH';
  @override
  Future<void> open() async {}
  @override
  Future<List<Map<String, String>>> query(List<String> words, {bool debugLog = false}) async {
    switch (words.first) {
      case '/system/resource/print':
        return [
          {'board-name': 'BaseBox 5', 'version': '6.34.3', 'cpu-load': '9', 'total-memory': '67108864', 'free-memory': '40000000', 'uptime': '2w'}
        ];
      case '/interface/print':
        return [
          {'name': 'ether1', 'type': 'ether', 'running': 'true', 'disabled': 'false'},
          if (radio) {'name': 'wlan1', 'type': 'wlan', 'running': 'true', 'disabled': 'false'},
        ];
      case '/interface/wireless/print':
        await holdWireless?.future;
        if (!radio) throw MikrotikException('no such command prefix');
        return [
          {'name': 'wlan1', 'mode': 'ap-bridge', 'band': '5ghz-a/n', 'disabled': 'false', 'running': 'true'}
        ];
      case '/interface/wireless/registration-table/print':
        await holdRegTable?.future;
        return const [];
      case '/system/health/print':
      case '/ppp/active/print':
        return const [];
    }
    throw MikrotikException('no such command');
  }

  @override
  Future<void> close() async {}
}

/// قناةٌ يرفض جهازها الاتّصال (المنفذ مقفول).
class _RefusedCh implements RouterOsChannel {
  @override
  String get via => 'API';
  @override
  Future<void> open() async => throw const SocketException('Connection refused');
  @override
  Future<List<Map<String, String>>> query(List<String> words, {bool debugLog = false}) async => const [];
  @override
  Future<void> close() async {}
}
