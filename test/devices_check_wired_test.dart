// «الفحص الشامل» — المراجعة الثالثة لإصدار 180 (devwired): الأجهزة السلكيّة والأولت.
//   F3  روجي: جدول الجسر انتهت مهلته ⇒ لاسلكيّه مجهول لا «راوتر · سليم» (القارئ الحقيقيّ عبر ممرّ الـVPN، لا لقطة
//       محقونة)؛ وإشارة 0 من صفّ الوصلة «لم تُقرأ» لا «0 dBm».
//   F17 أولتٌ لم يُقرأ له منفذ PON واحد (لا شيء، أو منافذ الصعود وحدها) ⇒ «منافذ PON ما انقرت» و«لم يُقرأ» لا
//       «أولت · سليم» ولا «ONU 0/0».
//   F18 «كل الشركات»: الخادم يقرأ ضوء الأولت كلّه ويرسل الأضعف ≤300 ⇒ «أضعف 300 من N — الباقي أقوى منها أو لم يقرأه
//       الخادم» لا «الباقي لم يقرأه الخادم»، والضعيف «300+» حين تكون القائمة المقطوعة كلّها ضعيفة.
//   F20 ميكروتك SNMP: جدول الواجهات بلغ سقف القراءة (٦٠٠ صفّ بالأعمدة المتوازية، ٢٠٠٠ بالمسح المنفرد) وفيه بقيّة
//       ⇒ «جلسات PPP» مجهولة («—») لا رقمٌ ناقص يُعرض كأنّه العدد.
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/mikrotik_snmp.dart';
import 'package:rad_mysvcs/api/network_devices_api.dart';
import 'package:rad_mysvcs/api/ruijie_api.dart';
import 'package:rad_mysvcs/api/snmp_client.dart';
import 'package:rad_mysvcs/api/vsol_olt_api.dart';
import 'package:rad_mysvcs/core/net/device_net.dart';
import 'package:rad_mysvcs/core/net/vpn_pipe.dart';
import 'package:rad_mysvcs/models/network_device.dart';
import 'package:rad_mysvcs/screens/network_devices/device_vitals.dart';
import 'package:rad_mysvcs/services/devices_check.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_snmp_agent.dart';
import 'support/snmp_wire.dart';

NetworkDevice dev(int id,
        {String type = 'router', String brand = 'mikrotik', String protocol = 'api', String? model}) =>
    NetworkDevice(
      id: id,
      adminId: '2',
      name: 'جهاز $id',
      type: type,
      brand: brand,
      model: model,
      ip: '10.0.0.$id',
      port: 8728,
      protocol: protocol,
      hasCredentials: true,
      lastStatus: 'online',
      createdAt: DateTime(2026, 11, 1),
    );

List<String> texts(DeviceCheckReport r) => [for (final f in r.findings) f.text];

DeviceCheckReport judge(NetworkDevice d, ProbeResult p, {CheckMemo? prev}) =>
    DevicesCheck.evaluate(d: d, alive: true, detail: p.detail, raw: p.raw, prev: prev);

// ── روجي: وكيلٌ بسيط (الهويّة، المعالج والذاكرة، منفذ LAN) وجدولا الجسر إن طُلبا ──
const _rjLink = '1.3.6.1.4.1.4881.1.1.10.2.195.2.3.1';
const _rjPeer = '1.3.6.1.4.1.4881.1.1.10.2.195.2.2.1';
const _rjRole = '1.3.6.1.4.1.4881.1.1.10.2.195.1.1.0';
const _peerMac = '0.17.34.51.68.85';

Map<String, Varbind> _ruijie({Map<String, Varbind> bridge = const {}}) => {
      '1.3.6.1.2.1.1.1.0': snmpText('', 'Ruijie Reyee EST310'),
      '1.3.6.1.2.1.1.3.0': snmpTicks('', 3 * 86400 * 100),
      '1.3.6.1.2.1.1.5.0': snmpText('', 'EST310'),
      '1.3.6.1.2.1.2.2.1.2.1': snmpText('', 'LAN1'),
      '1.3.6.1.2.1.2.2.1.5.1': snmpGauge('', 1000000000),
      '1.3.6.1.2.1.2.2.1.8.1': snmpInt('', 1),
      '1.3.6.1.2.1.25.2.3.1.3.1': snmpText('', 'Physical memory'),
      '1.3.6.1.2.1.25.2.3.1.5.1': snmpInt('', 1000),
      '1.3.6.1.2.1.25.2.3.1.6.1': snmpInt('', 300),
      '1.3.6.1.2.1.25.3.3.1.2.1': snmpInt('', 4),
      '1.3.6.1.2.1.31.1.1.1.6.1': snmpGauge('', 123456),
      '1.3.6.1.2.1.31.1.1.1.10.1': snmpGauge('', 654321),
      ...bridge,
      // ما بعد كلّ الشجرات (snmpEngineTime) — كجهازٍ حقيقيّ: المسح يخرج من شجرته لا يبلغ نهاية الـMIB
      '1.3.6.1.6.3.10.2.1.3.0': snmpInt('', 1000),
    };

/// صفّ وصلةٍ واحد (والطرف المقابل) — [signal] كما يكتبه الجهاز.
Map<String, Varbind> _bridgeRow({required int signal}) => {
      '$_rjLink.3.$_peerMac': snmpText('', '5G'),
      '$_rjLink.4.$_peerMac': snmpText('', 'BH-1'),
      '$_rjLink.6.$_peerMac': snmpInt('', -95),
      '$_rjLink.7.$_peerMac': snmpInt('', signal),
      '$_rjLink.8.$_peerMac': snmpInt('', 3600),
      '$_rjLink.9.$_peerMac': snmpInt('', 433),
      '$_rjPeer.3.$_peerMac': snmpText('', '10.0.0.99'),
      _rjRole: snmpText('', 'cpe'),
    };

void main() {
  late VpnPipeTransport pipeBefore;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    pipeBefore = VpnPipe.transport;
  });
  tearDown(() {
    VpnPipe.transport = pipeBefore;
    VpnPipe.used = false;
    RuijieApi.debugFetch = null;
    MikrotikSnmp.snmpFor =
        (host, port, community, timeout) => SnmpV2c(host: host, port: port, community: community, timeout: timeout);
    MikrotikSnmp.resetForTest();
    NetworkDevicesApi.invalidateCredentialsCache();
  });

  /// قراءة الفحص الشامل نفسها عبر ممرّ الـVPN (DeviceNet.vpn) والوكيل [pipe] — القارئ كلّه حقيقيّ.
  Future<ProbeResult> readVia(SnmpWirePipe pipe, NetworkDevice d) {
    VpnPipe.transport = pipe;
    NetworkDevicesApi.debugSeedCredentials(d.id, {'community': 'public'}, DateTime.now());
    return DeviceNet.vpn(() => DeviceVitals.fetch(d, detailed: true));
  }

  group('F3 روجي: جدول الجسر', () {
    test('🚨 جسرٌ محفوظ «راوتر» ومسح جدول جسره انتهت مهلته ⇒ «وضعه اللاسلكيّ ومشتركوه ما انقرأوا» لا «راوتر · سليم»',
        () async {
      final d = dev(48, brand: 'ruijie', protocol: 'snmp');
      final pipe = SnmpWirePipe(FakeSnmpAgent(_ruijie(bridge: _bridgeRow(signal: -61))), lose: {_rjLink});
      final p = await readVia(pipe, d);
      expect(pipe.asked, contains(_rjLink), reason: 'القارئ سأل الجدول فعلاً');
      expect((p.raw! as RuijieStats).linkRead, isFalse);
      final r = judge(d, p);
      expect(r.state, CheckState.unread);
      expect(texts(r), contains('وضعه اللاسلكيّ ومشتركوه ما انقرأوا'));
      expect(r.cpu, 4, reason: 'ما قُرئ يبقى');
      // و«غير ذلك» (سجلٌّ «أخرى») كذلك — لا «سليم» بلا لاسلكيّه
      final other = dev(50, type: 'other', brand: 'ruijie', protocol: 'snmp');
      final r2 = judge(other, await readVia(SnmpWirePipe(FakeSnmpAgent(_ruijie()), lose: {_rjLink}), other));
      expect(r2.state, CheckState.unread);
    });

    test('راوتر روجي يجيب المسح بلا جدول جسر (أو يرفضه بخطأ) ⇒ «راوتر · سليم» كما كان — لا «لم يُقرأ» لكلّ راوتر',
        () async {
      final d = dev(51, brand: 'ruijie', protocol: 'snmp');
      final none = await readVia(SnmpWirePipe(FakeSnmpAgent(_ruijie())), d);
      expect((none.raw! as RuijieStats).linkRead, isTrue);
      final r = judge(d, none);
      expect([r.role, r.state], [CheckRole.router, CheckState.ok]);
      final refused = await readVia(SnmpWirePipe(FakeSnmpAgent(_ruijie()), refuse: {_rjLink}), d);
      expect((refused.raw! as RuijieStats).linkRead, isTrue, reason: 'ردّ الوكيل بخطأ = لا يدعم الجدول، ليس مهلة');
      expect(judge(d, refused).state, CheckState.ok);
    });

    test('🚨 صفّ الوصلة بإشارة 0 ⇒ الإشارة «لم تُقرأ» لا «0 dBm» ولا «وصلة · سليم»؛ والإشارة الحقيقيّة تُقرأ', () async {
      final d = dev(52, type: 'link', brand: 'ruijie', protocol: 'snmp');
      final p = await readVia(SnmpWirePipe(FakeSnmpAgent(_ruijie(bridge: _bridgeRow(signal: 0)))), d);
      expect(p.detail.glance.signal, isNull);
      expect(p.vitals.where((v) => v.label == 'الإشارة'), isEmpty, reason: 'لا خانة «0 dBm»');
      final r = judge(d, p);
      expect(r.signal, isNull);
      expect(r.state, CheckState.unread);
      expect(texts(r), contains('إشارة الوصلة ما انقرت'));
      final ok = await readVia(SnmpWirePipe(FakeSnmpAgent(_ruijie(bridge: _bridgeRow(signal: -61)))), d);
      expect(ok.detail.glance.signal, -61);
      expect(ok.detail.glance.snr, 34);
      final r2 = judge(d, ok);
      expect([r2.role, r2.state, r2.signal], [CheckRole.link, CheckState.ok, -61]);
    });
  });

  group('F17 أولتٌ بلا منفذ PON مقروء', () {
    final olt = dev(60, type: 'other', brand: 'vsol', protocol: 'snmp', model: 'V1600D8');
    const ge1 = VsolUplink(index: 1, name: 'GE1', up: true, speedMbps: 1000, rxBytes: 0, txBytes: 0);

    test('🚨 منافذ الصعود وحدها ⇒ «منافذ PON ما انقرت» و«لم يُقرأ» بلا «ONU 0/0»؛ وبلا شيءٍ (الهويّة وحدها) كذلك',
        () {
      const up = VsolOltStats(sysName: 'OLT', uptime: Duration(days: 9), uplinks: [ge1]);
      final r = judge(olt, oltProbeResult(up));
      expect(r.role, CheckRole.olt);
      expect(r.state, CheckState.unread);
      expect(texts(r), contains('منافذ PON ما انقرت'));
      expect(r.vitals.where((v) => v.k == 'ONU'), isEmpty, reason: 'لا «0/0» عن أولتٍ لم تُقرأ بنيته');
      final bare = judge(olt, oltProbeResult(const VsolOltStats(sysName: 'OLT', uptime: Duration(days: 9))));
      expect(bare.state, CheckState.unread);
      expect(texts(bare), contains('منافذ PON ما انقرت'));
    });

    test('ملخّص الخادم بلا منفذٍ ولا مشترك ⇒ «لم يُقرأ»؛ وبعدده بلا قائمة منافذه، أو ببنيته كاملة ⇒ يُحكم كما كان', () {
      DeviceCheckReport remote(Map<String, dynamic> v) =>
          DevicesCheck.evaluate(d: olt, alive: true, detail: DeviceVitals.fromVpn(v).detail);
      final none = remote({'kind': 'olt', 'total': 0, 'online': 0, 'pons': []});
      expect(none.state, CheckState.unread);
      expect(texts(none), contains('منافذ PON ما انقرت'));
      expect(none.vitals.where((v) => v.k == 'ONU'), isEmpty);
      final counted = remote({'kind': 'olt', 'total': 120, 'online': 100, 'pons': []});
      expect(counted.state, CheckState.ok, reason: 'عدد المشتركين مقروء — لا «لم يُقرأ» كاذب');
      expect(counted.vitals.firstWhere((v) => v.k == 'ONU').v, '100/120');
      final full = remote({
        'kind': 'olt',
        'total': 120,
        'online': 100,
        'pons': [
          {'label': 'PON1', 'up': true, 'online': 100, 'total': 120}
        ],
      });
      expect(full.state, CheckState.ok);
      expect(texts(full), isNot(contains('منافذ PON ما انقرت')));
      expect(texts(counted), isNot(contains('منافذ PON ما انقرت')));
    });
  });

  group('F18 ضوء أولت الخادم: الأضعف ≤300 ممّا قرأه', () {
    final olt = dev(70, type: 'other', brand: 'vsol', protocol: 'snmp', model: 'V1600D8');
    DeviceCheckReport remote({required int online, required int sent, int weak = 0, int? lw, int? lr}) =>
        DevicesCheck.evaluate(
            d: olt,
            alive: true,
            detail: DeviceVitals.fromVpn({
              'kind': 'olt',
              'total': online + 80,
              'online': online,
              'pons': [
                {'label': 'PON1', 'up': true, 'online': online, 'total': online + 80}
              ],
              'onus': [
                for (var i = 0; i < sent; i++) {'n': 'ONU $i', 'k': 'PON1:$i', 'rx': i < weak ? -29.5 : -20.0}
              ],
              if (lw != null) 'lw': lw,
              if (lr != null) 'lr': lr,
            }).detail);

    test('🚨 520 متّصلة قرأها الخادم كلّها وأرسل أضعف 300 (lw 520، lr 300) ⇒ «أضعف 300 من 520» لا «لم يقرأه الخادم»',
        () {
      final r = remote(online: 520, sent: 300, weak: 37, lw: 520, lr: 300);
      expect(texts(r), contains('الضوء: أضعف 300 من 520 — الباقي أقوى منها أو لم يقرأه الخادم'));
      expect(texts(r).where((t) => t.contains('قُرئ 300')), isEmpty);
      expect(texts(r), contains('ضوء ضعيف: 37 — من أضعف 300'), reason: 'الضعيف كلّه فيها ما دام فيها غير ضعيف');
      // القائمة المقطوعة كلّها ضعيفة ⇒ قد يكون غيرها: «300+» لا «300»
      final all = remote(online: 520, sent: 300, weak: 300, lw: 520, lr: 300);
      expect(texts(all), contains('ضوء ضعيف: 300+ — من أضعف 300'));
    });

    test('قائمةٌ دون الحدّ (لا قطع) ⇒ كما كانت: «قُرئ n من N — الباقي لم يقرأه الخادم» و«من n مشترك»', () {
      final r = remote(online: 400, sent: 120, weak: 3, lw: 400, lr: 120);
      expect(texts(r), contains('الضوء: قُرئ 120 من 400 — الباقي لم يقرأه الخادم'));
      expect(texts(r), contains('ضوء ضعيف: 3 — من 120 مشترك'));
    });
  });

  group('F20 ميكروتك SNMP: جدول واجهاتٍ مقطوع', () {
    /// راوتر PPPoE: [ethers] منفذاً (الخمسة الأولى شغّالة) ثمّ جلسات PPP شغّالة حتى [n] واجهة.
    Map<String, Varbind> pppoe(int n, {int ethers = 8}) => {
          MikrotikSnmp.sysDescr: snmpText('', 'RouterOS CCR2004-1G-12S+2XS'),
          MikrotikSnmp.sysUpTime: snmpTicks('', 3 * 86400 * 100),
          for (var k = 1; k <= n; k++) ...{
            '${MikrotikSnmp.ifName}.$k': snmpText('', k <= ethers ? 'ether$k' : '<pppoe-user$k>'),
            '${MikrotikSnmp.ifType}.$k': snmpInt('', k <= ethers ? 6 : 23),
            '${MikrotikSnmp.ifAdmin}.$k': snmpInt('', 1),
            '${MikrotikSnmp.ifOper}.$k': snmpInt('', k <= 5 || k > ethers ? 1 : 2),
          },
        };

    test('🚨 700 واجهة (692 جلسة) والأعمدة المتوازية تقف عند 600 ⇒ «جلسات PPP» مجهولة لا 592؛ والمنافذ مقروءة',
        () async {
      final d = dev(71, protocol: 'snmp');
      MikrotikSnmp.snmpFor = (h, p, c, t) => FakeSnmpAgent(pppoe(700));
      final s = await MikrotikSnmp.fetch(host: '10.0.0.71', community: 'public');
      final res = DeviceVitals.mikrotikResult(d, s, null, detailed: true);
      expect(res.detail.glance.ppp, isNull, reason: 'لا «592» عن 692 جلسة');
      final r = judge(d, res);
      expect(r.vitals.where((v) => v.k == 'جلسات PPP'), isEmpty);
      expect(r.vitals.firstWhere((v) => v.k == 'المنافذ').v, '5/8', reason: 'المنافذ في أوّل الجدول — قُرئت');
      // جدولٌ قُرئ كلّه ⇒ عدده كما هو
      MikrotikSnmp.snmpFor = (h, p, c, t) => FakeSnmpAgent(pppoe(300));
      final full = await MikrotikSnmp.fetch(host: '10.0.0.72', community: 'public');
      expect(DeviceVitals.mikrotikResult(d, full, null, detailed: true).detail.glance.ppp, 292);
    });

    test('🚨 وكيلٌ لا يقبل الأعمدة المتوازية: المسح المنفرد يقف عند 2000 صفّ ⇒ «جلسات PPP» مجهولة لا 1992', () async {
      final d = dev(73, protocol: 'snmp');
      MikrotikSnmp.snmpFor = (h, p, c, t) => _CappedWalk(pppoe(2100));
      final s = await MikrotikSnmp.fetch(host: '10.0.0.73', community: 'public');
      expect(DeviceVitals.mikrotikResult(d, s, null, detailed: true).detail.glance.ppp, isNull);
      MikrotikSnmp.snmpFor = (h, p, c, t) => _CappedWalk(pppoe(1500));
      final full = await MikrotikSnmp.fetch(host: '10.0.0.74', community: 'public');
      expect(DeviceVitals.mikrotikResult(d, full, null, detailed: true).detail.glance.ppp, 1492);
    });
  });
}

/// وكيلٌ يرفض الأعمدة المتوازية، ومسحه يقف عند سقف [SnmpV2c.walk] (chunkSize × maxIterations) كالعميل الحقيقيّ.
class _CappedWalk extends FakeSnmpAgent {
  _CappedWalk(super.data);

  @override
  Future<List<Varbind>> getBulkColumns(List<String> cursors, {int maxRepetitions = 25}) async =>
      throw SnmpTimeoutException('SNMP عبر الـVPN: الجهاز ما ردّ');

  @override
  Future<List<Varbind>> walk(String baseOid, {int chunkSize = 25, int maxIterations = 100}) async =>
      (await super.walk(baseOid, chunkSize: chunkSize, maxIterations: maxIterations))
          .take(chunkSize * maxIterations)
          .toList();
}
