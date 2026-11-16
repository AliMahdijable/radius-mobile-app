import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/mimosa_api.dart';
import 'package:rad_mysvcs/api/network_devices_api.dart';
import 'package:rad_mysvcs/api/ruijie_api.dart';
import 'package:rad_mysvcs/api/ubnt_api.dart';
import 'package:rad_mysvcs/models/network_device.dart';
import 'package:rad_mysvcs/screens/network_devices/device_vitals.dart';
import 'package:rad_mysvcs/screens/network_devices/tower/tower_reading.dart';
import 'package:rad_mysvcs/screens/network_devices/tower/tower_topology_logic.dart';

import 'support/ubnt_gen3_fixtures.dart';

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

/// ناتج `mca-status` (سطورٌ بـ`مفتاح=قيمة` مفصولةٌ بفواصل) ⇒ خريطة، كما يفعل القارئ الحقيقيّ.
Map<String, String> _parseMca(String out) {
  final map = <String, String>{};
  for (final line in out.split('\n')) {
    for (final part in line.trim().split(',')) {
      final eq = part.indexOf('=');
      if (eq <= 0) continue;
      map.putIfAbsent(part.substring(0, eq).trim(), () => part.substring(eq + 1).trim());
    }
  }
  return map;
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

    // ── airFiber X: المالك ١٦ نوفمبر (صورة «الترابط»، لنك AF-4X تحته ستّ سكترات يقرأ «9 Kbps ↓ 22 Kbps ↑»): «البارحة من صلحنا
    // بوضع سير الترفك تأثّر عدنا الجهاز 4x». القراءة هنا من **ردّ AF-4X الحقيقيّ** ([af4xMcaStatus]) بعدّادَي منفذ بياناته
    // يتقدّمان، وواجهة `air0` كما يُرجعها ifconfig: ترفك إدارةٍ بالكيلوبتات (على الجهاز الحقيقيّ 50 ميغابايت منذ الإقلاع مقابل
    // 10 تيرابايت على منفذ البيانات).
    group('airFiber X (AF-4X) — ما يعبر الهواء من منفذ البيانات لا من air0', () {
      // ترفك الإدارة على air0 خلال ٢٠ث: 9 كيلوبت وارد و22 صادر — رقما صورة المالك.
      const mgmtRx = 22500;
      const mgmtTx = 55000;

      /// [toSub]/[toMain] بايتات عبرت اللنك خلال الدورة. طرف الرئيسيّ (master) يستقبل ما ينزل للفرع من شبكة برجه على منفذ
      /// البيانات ويُخرج منه ما صعد؛ وطرف الفرعيّ (slave) بالعكس.
      UbntStats af4x(int k, {required bool slave, int toSub = down, int toMain = upB}) {
        final lanRx = slave ? toMain : toSub;
        final lanTx = slave ? toSub : toMain;
        final text = af4xMcaStatus
            .replaceFirst('lanRxBytes=10096866039227', 'lanRxBytes=${10096866039227 + k * lanRx}')
            .replaceFirst('lanTxBytes=780197904550', 'lanTxBytes=${780197904550 + k * lanTx}')
            .replaceFirst('afOpmode=master', slave ? 'afOpmode=slave' : 'afOpmode=master');
        // الثابت يحمل العدّادَين والوضع بالشكل الذي نستبدله (وإلّا فالاختبار يقرأ أرقاماً لا تتحرّك)
        for (final key in ['lanRxBytes=10096866039227', 'lanTxBytes=780197904550', 'afOpmode=master']) {
          expect(key.allMatches(af4xMcaStatus), hasLength(1), reason: key);
        }
        return UbntStats.fromMcaStatus(_parseMca(text), interfaces: [
          // eth0 كما يُرجعه ifconfig على الجهاز: منفذ إدارةٍ مطفأ (الباني يضع مكانه منفذ البيانات من lan*)
          const {'name': 'eth0', 'up': 'true', 'rx_bytes': '0', 'tx_bytes': '0', 'speed': '10'},
          {'name': 'air0', 'up': 'true', 'rx_bytes': '${49939212 + k * mgmtRx}', 'tx_bytes': '${69051794 + k * mgmtTx}'},
        ]);
      }

      Future<TowerReading> read(int id, {required bool slave, int toSub = down, int toMain = upB}) =>
          _twoReads(_dev(id, 'ubnt', model: 'airFiber 4X'), (k) {
            UbntApi.debugFetch = () async => af4x(k, slave: slave, toSub: toSub, toMain: toMain);
          });

      test('طرف الفرعيّ (slave): ينزل للفرع ما يخرجه منفذ بياناته — لا كيلوبتات air0', () async {
        final r = await read(11, slave: true);
        final f = LinkFlow.of(rb: r);
        expect(f.toSubBps, _near(_bps(down)), reason: 'كان ${_bps(mgmtRx)} bps (استقبال air0 = ترفك الإدارة)');
        expect(f.toMainBps, _near(_bps(upB)), reason: 'كان ${_bps(mgmtTx)} bps');
        // وبطاقة البرج للجهاز نفسه: المستقبِل ينزّل ما يستقبله راديوه
        expect(r.downBps, _near(_bps(down)));
        expect(r.upBps, _near(_bps(upB)));
      });

      test('طرف الرئيسيّ (master) وحده: ينزل للفرع ما يستقبله منفذ بياناته من شبكة برجه', () async {
        final r = await read(12, slave: false);
        final f = LinkFlow.of(ra: r);
        expect(f.toSubBps, _near(_bps(down)));
        expect(f.toMainBps, _near(_bps(upB)));
      });

      test('الطرفان معاً يتّفقان، ولا يدخل air0 في «أنشط منفذ» ولا في عدّ المنافذ السلكيّة', () async {
        final a = await read(13, slave: false);
        final b = await read(14, slave: true);
        final f = LinkFlow.of(ra: a, rb: b);
        expect(f.toSubBps, _near(_bps(down)));
        expect(f.toMainBps, _near(_bps(upB)));
        for (final r in [a, b]) {
          expect(r.busiestPort?.name, 'eth0', reason: 'منفذ البيانات (lan*)');
          expect(r.portsUp, 1);
          expect(r.portsTotal, 1);
          expect(r.wiredPorts.map((p) => p.name), ['eth0']);
        }
      });

      test('لنك رفعُه أكبر من تنزيله: الاتّجاه من العدّاد لا «الأكبر ينزل»', () async {
        // يصعد من الفرعيّ ١٠٠ ميغا وينزل له ١٠ (مصدر النت عند الفرعيّ) — يُعرض كما هو لا مقلوباً
        final b = await read(15, slave: true, toSub: upB, toMain: down);
        final a = await read(16, slave: false, toSub: upB, toMain: down);
        for (final f in [LinkFlow.of(rb: b), LinkFlow.of(ra: a), LinkFlow.of(ra: a, rb: b)]) {
          expect(f.toSubBps, _near(_bps(upB)));
          expect(f.toMainBps, _near(_bps(down)));
        }
      });

      test('القراءة الأولى (بلا عيّنة سابقة): لا رقم — لا معدّل air0 ولا صفر', () async {
        final d = _dev(17, 'ubnt', model: 'airFiber 4X');
        NetworkDevicesApi.debugSeedCredentials(d.id, {'user': 'u', 'pass': 'p'}, DateTime.now());
        UbntApi.debugFetch = () async => af4x(0, slave: true);
        final r = TowerReading.fromProbe(await DeviceVitals.fetch(d, detailed: true));
        final f = LinkFlow.of(rb: r);
        expect(f.toSubBps, isNull);
        expect(f.toMainBps, isNull);
        expect(r.downBps, isNull);
        expect(r.busiestPort, isNull);
      });

      test('منفذ البيانات بلا عدّادات lan* (برنامجٌ قديم): «—» لا ترفك الإدارة', () async {
        final r = await _twoReads(_dev(18, 'ubnt', model: 'airFiber 4X'), (k) {
          final text = af4xMcaStatus
              .replaceFirst(RegExp(r'lanRxBytes=\d+\n'), '')
              .replaceFirst(RegExp(r'lanTxBytes=\d+\n'), '')
              .replaceFirst('afOpmode=master', 'afOpmode=slave');
          UbntApi.debugFetch = () async => UbntStats.fromMcaStatus(_parseMca(text), interfaces: [
                const {'name': 'eth0', 'up': 'true', 'rx_bytes': '0', 'tx_bytes': '0', 'speed': '10'},
                {'name': 'air0', 'up': 'true', 'rx_bytes': '${49939212 + k * mgmtRx}', 'tx_bytes': '${69051794 + k * mgmtTx}'},
              ]);
        });
        final f = LinkFlow.of(rb: r);
        // لا رقما air0 (9 و22 كيلوبت)، ولا صفر eth0 الإداريّ المطفأ كأنّه «لا ترفك»: لم يُقرأ ⇒ null («—»)
        expect(f.toSubBps, isNull);
        expect(f.toMainBps, isNull);
        expect(r.downBps, isNull);
        expect(r.upBps, isNull);
        expect(r.busiestPort, isNull);
      });
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
