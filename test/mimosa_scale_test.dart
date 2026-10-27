import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/mimosa_api.dart';
import 'package:rad_mysvcs/api/snmp_client.dart';

/// المالك ٢٧ أكتوبر: «الميموسا قراءات الـchain وبعض القراءات ظهر بدل 58.20 يكتب 582.0… راجع متغيراتها بدقة».
/// المرجع MIMOSA-NETWORKS-BFIVE-MIB / PTMP-MIB الرسميّان، وC5c الحيّ (najaf2262) الذي يُرجع الجدول بلا أعشار.
Uint8List _signed(int v) {
  final out = <int>[];
  var x = v;
  while (true) {
    out.insert(0, x & 0xff);
    final rest = x >> 8;
    final sign = (x & 0x80) != 0;
    if ((rest == 0 && !sign) || (rest == -1 && sign)) break;
    x = rest;
  }
  return Uint8List.fromList(out);
}

Varbind i(String oid, int v) => Varbind(oid: oid, rawTag: 0x02, rawBytes: _signed(v));
Varbind g(String oid, int v) => Varbind(oid: oid, rawTag: 0x42, rawBytes: _signed(v));
Varbind s(String oid, String v) => Varbind(oid: oid, rawTag: 0x04, rawBytes: Uint8List.fromList(utf8.encode(v)));
Varbind b(String oid, List<int> v, {int tag = 0x04}) => Varbind(oid: oid, rawTag: tag, rawBytes: Uint8List.fromList(v));

const bfive = '1.3.6.1.4.1.43356.2.1.2';

void main() {
  group('السلاسل: المقياس لكلّ جهاز', () {
    test('C5c القديم (حيّ): −45 / −74 / 29 أعدادٌ صحيحة', () {
      expect(MimosaApi.chainsInTenths(rx: [i('a', -45)], noise: [i('b', -74)], tx: [i('c', 21)], snr: [i('d', 29)]),
          isFalse);
      final c = MimosaChain.fromRaw(index: 1, tenths: false, tx: i('c', 21), rx: i('a', -45), noise: i('b', -74), snr: i('d', 29), freq: i('f', 6275));
      expect([c.txPowerDbm, c.rxPowerDbm, c.rxNoiseDbm, c.snrDb, c.centerFreqMhz], [21, -45, -74, 29, 6275]);
    });

    test('🚨 جهازٌ يتبع الـMIB (DecimalOne): ‎−582 ⇒ ‎−58.2 لا 582.0', () {
      final t = MimosaApi.chainsInTenths(rx: [i('a', -582)], noise: [i('b', -905)], tx: [i('c', 230)], snr: [i('d', 323)]);
      expect(t, isTrue);
      final c = MimosaChain.fromRaw(index: 1, tenths: t, tx: i('c', 230), rx: i('a', -582), noise: i('b', -905), snr: i('d', 323), freq: i('f', 5180));
      expect(c.rxPowerDbm, -58.2);
      expect(c.rxNoiseDbm, -90.5);
      expect(c.snrDb, 32.3);
      expect(c.txPowerDbm, 23.0);
    });

    test('بلا استقبالٍ ولا ضجيج: إرسالٌ فوق 40 أو SNR فوق 70 ⇒ أعشار', () {
      expect(MimosaApi.chainsInTenths(rx: const [], noise: const [], tx: [i('c', 240)], snr: const []), isTrue);
      expect(MimosaApi.chainsInTenths(rx: const [], noise: const [], tx: [i('c', 24)], snr: [i('d', 30)]), isFalse);
    });

    test('«غير صالحة» بالـMIB ⇒ لا رقم: إرسال −8 · استقبال −100 (ومعه SNR والضجيج) · تردّد 0', () {
      final c = MimosaChain.fromRaw(index: 2, tenths: false, tx: i('c', -8), rx: i('a', -100), noise: i('b', -95), snr: i('d', -100), freq: i('f', 0));
      expect([c.txPowerDbm, c.rxPowerDbm, c.rxNoiseDbm, c.snrDb, c.centerFreqMhz], [null, null, null, null, null]);
      final t = MimosaChain.fromRaw(index: 2, tenths: true, rx: i('a', -1000), snr: i('d', -1000));
      expect([t.rxPowerDbm, t.snrDb], [null, null]);
    });
  });

  group('القيم المفردة بوحداتها الرسميّة', () {
    MimosaStats stats(Map<String, Varbind> m) => MimosaStats.fromVarbinds(m);

    test('نسبة أخطاء الحزم DecimalTwo: 150 ⇒ 1.5٪ لا 15٪', () {
      final st = stats({'$bfive.7.3.0': i('$bfive.7.3.0', 150), '$bfive.7.4.0': i('$bfive.7.4.0', 7)});
      expect(st.perTxRatePct, 1.5);
      expect(st.perRxRatePct, 0.07);
    });

    test('الإشارة المستهدفة Integer32 dB: −65 كما هي، و−650 أعشار', () {
      expect(stats({'$bfive.6.7.0': i('$bfive.6.7.0', -65)}).targetRxPowerDbm, -65);
      expect(stats({'$bfive.6.7.0': i('$bfive.6.7.0', -650)}).targetRxPowerDbm, -65);
    });

    test('الإحداثيّات: العرض .2.2 والطول .2.1 بخمس منازل (أو سبع)، والأقمار .2.6', () {
      final st = stats({
        '$bfive.2.2.0': i('$bfive.2.2.0', 3212345),
        '$bfive.2.1.0': i('$bfive.2.1.0', 4442100),
        '$bfive.2.3.0': i('$bfive.2.3.0', 34),
        '$bfive.2.6.0': i('$bfive.2.6.0', 11),
      });
      expect(st.latitude, closeTo(32.12345, 1e-9));
      expect(st.longitude, closeTo(44.421, 1e-9));
      expect(st.altitude, 34);
      expect(st.gpsSats, 11);
      expect(stats({'$bfive.2.2.0': i('$bfive.2.2.0', 321234500)}).latitude, closeTo(32.12345, 1e-9));
    });

    test('سعة PHY من جدول التدفّقات وحده — لا من معدّل الحزم (7.1/7.2)', () {
      final st = MimosaStats.fromVarbinds({'$bfive.7.1.0': g('$bfive.7.1.0', 1467283), '$bfive.7.2.0': g('$bfive.7.2.0', 3593171)});
      expect(st.phyTxRateMbps, isNull);
      expect(st.phyRxRateMbps, isNull);
      expect(MimosaStats.fromVarbinds(const {}, txPhyMbps: 650, rxPhyMbps: 650).phyTxRateMbps, 650);
    });
  });

  group('عملاء السكتور من الجدولين الرسميّين', () {
    test('الماك والاسم والـIP والبرنامج والمدّة، والإشارة DecimalOne، والسرعتان', () {
      const info = '$bfive.9.5.1.1';
      const st = '$bfive.9.6.1.1';
      final list = MimosaApi.clientsFromOfficial([
        b('$info.2.1', [0x00, 0x11, 0x22, 0x33, 0x44, 0x55]),
        s('$info.3.1', 'home-1'),
        s('$info.4.1', '2.9.1'),
        b('$info.5.1', [10, 0, 0, 5], tag: 0x40),
        Varbind(oid: '$info.6.1', rawTag: 0x43, rawBytes: Uint8List.fromList([0x01, 0x86, 0xA0])), // 100000 tick = 1000 ث
        b('$info.2.2', [0x00, 0x11, 0x22, 0x33, 0x44, 0x66]),
      ], [
        b('$st.2.1', [0x00, 0x11, 0x22, 0x33, 0x44, 0x55]),
        g('$st.8.1', 200),
        g('$st.9.1', 300),
        i('$st.11.1', -582),
        b('$st.2.2', [0x00, 0x11, 0x22, 0x33, 0x44, 0x66]),
        i('$st.11.2', -71),
      ]);
      expect(list, hasLength(2));
      final a = list.firstWhere((c) => c.mac == '00:11:22:33:44:55');
      expect(a.name, 'home-1');
      expect(a.ip, '10.0.0.5');
      expect(a.fwVersion, '2.9.1');
      expect(a.rssiDbm, -58);
      expect(a.rxRateMbps, 200);
      expect(a.txRateMbps, 300);
      expect(a.uptimeSec, 1000);
      expect(list.firstWhere((c) => c.mac == '00:11:22:33:44:66').rssiDbm, -71, reason: 'برنامجٌ لا يتبع الأعشار');
      expect(list.first.rssiDbm, -58, reason: 'الأقوى أوّلاً');
    });

    test('جدولان فارغان ⇒ لا عملاء (فيُجرَّب البديل القديم)', () {
      expect(MimosaApi.clientsFromOfficial(const [], const []), isEmpty);
    });
  });
}
