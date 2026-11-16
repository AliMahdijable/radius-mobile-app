import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/mimosa_api.dart';
import 'package:rad_mysvcs/api/network_devices_api.dart';
import 'package:rad_mysvcs/api/ruijie_api.dart';
import 'package:rad_mysvcs/api/ubnt_api.dart';
import 'package:rad_mysvcs/models/network_device.dart';
import 'package:rad_mysvcs/screens/network_devices/device_vitals.dart';
import 'package:rad_mysvcs/screens/network_devices/tower/tower_reading.dart';
import 'package:rad_mysvcs/screens/network_devices/tower/tower_topology_logic.dart';

/// المالك ١٦ نوفمبر (صورة «الترابط»: أربع وصلات «يعمل» بلا رقم): «اللنكات روجي ولنكات ميموسا ولنكات يوبيكويتي اتأكّد جاي
/// تعرض سير الترفك». هنا كلّ علامةٍ بقراءتين متتاليتين عبر **بانيها الحقيقيّ** (`DeviceVitals.fetch` بمنفذ الاختبار) ثمّ
/// [TowerReading.fromProbe] ثمّ [LinkFlow.of] — كما يقرأ مسبار الأبراج تماماً، والعيّنة السابقة قبل ٢٠ ثانية.
const _gap = Duration(seconds: 20);

/// بت/ثانية لفارق بايتاتٍ خلال [_gap].
int _bps(int bytes) => (bytes * 8 / _gap.inSeconds).round();

/// المعدّل يُحسب بزمن الساعة الفعليّ (ملّي ثانية): تحت حِمل الحزمة الكاملة تتأخّر القراءة الثانية ملّي ثانيةً أو اثنتين فيتزحزح
/// الرقم ١٠٠٠٠٠٠٠٠ ⇒ ٩٩٩٩٠٠٠١ — المطابقة بسماحيّة ١٪ لا تامّة (المطلوب: رقمٌ لا «يعمل»، وبالمقدار الصحيح).
Matcher _near(int bps) => closeTo(bps, bps * 0.01);

NetworkDevice _dev(int id, String brand, {String model = ''}) => NetworkDevice(
      id: id,
      adminId: '1',
      name: 'لنك $id',
      type: 'link',
      brand: brand,
      model: model.isEmpty ? null : model,
      ip: '10.0.0.$id',
      port: 22,
      hasCredentials: true,
      lastStatus: 'online',
      createdAt: DateTime(2026, 11, 1),
    );

/// قراءتان: الأولى بلا عيّنة (لا معدّل)، والثانية بعيّنة الأولى قبل [_gap] — كدورة المسبار.
Future<TowerReading> _twoReads(NetworkDevice d, void Function(int round) arm) async {
  NetworkDevicesApi.debugSeedCredentials(d.id, {'user': 'u', 'pass': 'p', 'community': 'public'}, DateTime.now());
  arm(0);
  final r1 = await DeviceVitals.fetch(d, detailed: true);
  arm(1);
  final r2 = await DeviceVitals.fetch(
    d,
    prev: CounterSample(r1.counters, DateTime.now().subtract(_gap)),
    detailed: true,
  );
  return TowerReading.fromProbe(r2);
}

UbntInterface _ui(String n, int rx, int tx) =>
    UbntInterface(ifname: n, hwaddr: '', enabled: true, plugged: true, rxBytes: rx, txBytes: tx);

UbntStats _ubnt({required String mode, required List<UbntInterface> ifs, String model = 'PowerBeam M5'}) => UbntStats(
      host: UbntHost(hostname: 'x', devmodel: model, fwversion: 'XW.v6.3', uptime: 1000, cpuload: 5, temperature: 40),
      wireless: UbntWireless(
        essid: 'link',
        mode: mode,
        signal: -55,
        noise: -95,
        ccq: 95,
        txRate: 300,
        rxRate: 300,
        channel: 0,
        frequency: 5800,
        distance: 900,
        chanbw: 40,
      ),
      interfaces: ifs,
      stations: const [],
    );

void main() {
  tearDown(() {
    UbntApi.debugFetch = null;
    MimosaApi.debugFetch = null;
    RuijieApi.debugFetch = null;
  });

  // الطرف الفرعيّ يستقبل ١٠٠ ميغا (ينزل للفرع) ويرسل ١٠ (يصعد).
  const down = 250000000; // بايت خلال ٢٠ث = ١٠٠ Mbps
  const upB = 25000000; // ١٠ Mbps

  group('كلّ علامة لنك تُعطي سير الترفك بالجهتين بعد قراءتين', () {
    test('يوبيكويتي airMAX (محطّة، ath0)', () async {
      final r = await _twoReads(_dev(1, 'ubnt'), (k) {
        UbntApi.debugFetch = () async => _ubnt(mode: 'sta', ifs: [
              _ui('ath0', 1000000000 + k * down, 200000000 + k * upB),
              _ui('br0', 300000000 + k * upB, 1100000000 + k * down),
              _ui('eth0', 200000000 + k * upB, 1000000000 + k * down),
            ]);
      });
      final f = LinkFlow.of(rb: r);
      expect(f.toSubBps, _near(_bps(down)));
      expect(f.toMainBps, _near(_bps(upB)));
    });

    test('يوبيكويتي Wave/GigaBeam (راديو ٦٠ wlan0 + احتياطيّ ٥ ath0 خامل قبله)', () async {
      final r = await _twoReads(_dev(2, 'ubnt', model: 'GigaBeam LR'), (k) {
        UbntApi.debugFetch = () async => _ubnt(model: 'GigaBeam LR', mode: 'sta-ptp', ifs: [
              _ui('eth0', 200000000 + k * upB, 1000000000 + k * down),
              _ui('ath0', 5000 + k * 100, 4000 + k * 100), // الاحتياطيّ ٥ — شبه خامل
              _ui('wlan0', 1000000000 + k * down, 200000000 + k * upB), // الـ٦٠ — الترفك كلّه
              _ui('br0', 300000000 + k * upB, 1100000000 + k * down),
            ]);
      });
      final f = LinkFlow.of(rb: r);
      expect(f.toSubBps, _near(_bps(down)), reason: 'الراديو الأنشط (الـ٦٠) لا أوّل راديو (الاحتياطيّ الخامل)');
      expect(f.toMainBps, _near(_bps(upB)));
    });

    test('ميموسا (محطّة) — كانت بلا منافذ ولا عدّادات ⇒ «يعمل» دائماً', () async {
      final r = await _twoReads(_dev(3, 'mimosa', model: 'C5c'), (k) {
        MimosaApi.debugFetch = () async => MimosaStats(
              wirelessMode: 2,
              totalRxPowerDbm: -52,
              ssid: 'BH',
              counters: [
                MimosaIfCounter(index: 1, name: 'lo', rxOctets: 1000 + k, txOctets: 1000 + k),
                MimosaIfCounter(index: 2, name: 'eth0', rxOctets: 200000000 + k * upB, txOctets: 1000000000 + k * down),
                MimosaIfCounter(index: 3, name: 'wlan0', rxOctets: 1000000000 + k * down, txOctets: 200000000 + k * upB),
                MimosaIfCounter(index: 4, name: 'br0', rxOctets: 300000000 + k * upB, txOctets: 1100000000 + k * down),
              ],
            );
      });
      final f = LinkFlow.of(rb: r);
      expect(f.toSubBps, _near(_bps(down)));
      expect(f.toMainBps, _near(_bps(upB)));
    });

    test('ميموسا بأسماء واجهاتٍ لا تقول «لاسلكيّ» ⇒ أنشط منفذ (كلوحته)، لا «يعمل»', () async {
      final r = await _twoReads(_dev(4, 'mimosa', model: 'B5c'), (k) {
        MimosaApi.debugFetch = () async => MimosaStats(
              wirelessMode: 2,
              totalRxPowerDbm: -50,
              counters: [
                MimosaIfCounter(index: 2, name: 'if2', rxOctets: 200000000 + k * upB, txOctets: 1000000000 + k * down),
                MimosaIfCounter(index: 5, name: 'if5', rxOctets: 7000 + k, txOctets: 7000 + k),
              ],
            );
      });
      final f = LinkFlow.of(rb: r);
      expect(f.toSubBps, isNotNull);
      expect(f.toMainBps, isNotNull);
      // بلا واجهةٍ لاسلكيّة مسمّاة: الأكبر «ينزل» كما يحسب البرج (اصطلاح [TowerReading])
      final big = [f.toSubBps!, f.toMainBps!]..sort();
      expect(big[1], _near(_bps(down)));
      expect(big[0], _near(_bps(upB)));
    });

    test('روجي airMetro (جسر) — منافذ IF-MIB بعدّاداتها', () async {
      final r = await _twoReads(_dev(5, 'ruijie', model: 'airMetro460G'), (k) {
        RuijieApi.debugFetch = () async => RuijieStats(
              sysName: 'airMetro460G',
              link: const RuijieWirelessLink(ssid: 'bridge', signalDbm: -48, freqMhz: 60480),
              ifaces: [
                RuijieInterface(index: 1, name: 'lo', operUp: true, speedMbps: 0, rxBytes: 9000 + k, txBytes: 9000 + k),
                RuijieInterface(
                    index: 2, name: 'eth0', operUp: true, speedMbps: 1000, rxBytes: 200000000 + k * upB, txBytes: 1000000000 + k * down),
                RuijieInterface(
                    index: 3, name: 'wlan0', operUp: true, speedMbps: 0, rxBytes: 1000000000 + k * down, txBytes: 200000000 + k * upB),
              ],
            );
      });
      final f = LinkFlow.of(rb: r);
      expect(f.toSubBps, _near(_bps(down)));
      expect(f.toMainBps, _near(_bps(upB)));
    });
  });
}
