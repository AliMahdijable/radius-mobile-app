import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/ubnt_api.dart';
import 'package:rad_mysvcs/api/ubnt_udapi.dart';

import 'support/ubnt_gen3_fixtures.dart';

/// بلاغ المالك ٢٧ أكتوبر: «ال 4x ترفك وايثرات خطا يقره… وال wave برو نقص هواي: التردّدات والنقل والاسم والنوع».
/// كلّ ما هنا من ردود جهازين حقيقيّين (popq التجريبيّ) — لا أرقام مخترعة.
Map<String, String> parseMca(String out) {
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

void main() {
  group('airFiber 4X — مفاتيح af* و lan*', () {
    // eth0 كما يُرجعه ifconfig على الجهاز: منفذ إدارةٍ مطفأ بعدّاداتٍ صفريّة وسرعة 10.
    const ifconfigEth0 = {'name': 'eth0', 'up': 'true', 'rx_bytes': '0', 'tx_bytes': '0', 'speed': '10'};
    const air0 = {'name': 'air0', 'up': 'true', 'rx_bytes': '49939212', 'tx_bytes': '69051794'};
    final s = UbntStats.fromMcaStatus(parseMca(af4xMcaStatus), interfaces: [ifconfigEth0, air0]);

    test('الاسم والطراز والبرنامج كما يكتبها الجهاز', () {
      expect(s.host.hostname, 'UBNT');
      expect(s.host.devmodel, 'airFiber 4X');
      expect(s.host.fwversion, startsWith('AF06.'));
      expect(s.wireless!.essid, 'bo-sajad313');
    });

    test('التردّد والعرض والسعة والمسافة والوضع — كانت صفراً', () {
      final w = s.wireless!;
      expect(w.frequency, 4850);
      expect(w.chanbw, 56);
      expect(w.txRate, 345, reason: 'afTxcapacity=344552320 bit/s');
      expect(w.rxRate, 116, reason: 'afRxcapacity=115700480 bit/s');
      expect(w.distance, 4142);
      expect(w.mode, 'ap-ptp');
      expect(w.signal, -41);
      expect(s.isAp, isTrue);
    });

    test('منفذ البيانات من lan* بدل eth0 الإداريّ المطفأ', () {
      final eth = s.interfaces.firstWhere((i) => i.ifname == 'eth0');
      expect(eth.rxBytes, 10096866039227);
      expect(eth.txBytes, 780197904550);
      expect(eth.speed, 1000);
      expect(eth.plugged, isTrue);
      expect(eth.duplex, isTrue);
      expect(s.interfaces.first.ifname, 'eth0', reason: 'السلكيّ أوّلاً — منه سير الترفك');
      expect(s.interfaces.where((i) => i.ifname == 'air0'), hasLength(1));
      expect(s.lanSpeed, '1000Mbps-Full');
    });

    test('الطرف الآخر من remoteIp، والحقائق الإضافيّة', () {
      expect(s.stations, hasLength(1));
      expect(s.stations.first.ip, '10.150.150.3');
      expect(s.stations.first.distanceMeters, 4142);
      expect(s.stations.first.dlCapacityKbps, 344552);
      final ex = {for (final e in s.extras) e.k: e.v};
      expect(ex['تردّد الاستقبال'], '4770 MHz');
      expect(ex['التعديل'], '8x');
      expect(ex['قدرة الإرسال'], '24 dBm · EIRP 50');
      expect(ex['استقبال السلسلتين'], '-45 / -45 dBm');
      expect(ex['حالة الوصلة'], 'تعمل');
      expect(ex['نمط الإرسال'], 'نصف مزدوج');
    });

    test('جهاز airMAX عاديّ لا يتأثّر (لا af* ⇒ لا تبديل منفذ ولا حقائق)', () {
      final plain = UbntStats.fromMcaStatus(
        {'deviceName': 'ns', 'platform': 'NanoStation M5', 'wlanEssid': 'x', 'wlanFrequency': '5180', 'lanRxBytes': '99'},
        interfaces: [ifconfigEth0],
      );
      expect(plain.wireless!.frequency, 5180);
      expect(plain.interfaces.first.rxBytes, 0, reason: 'لا نلمس eth0 إلّا لـairFiber X');
      expect(plain.extras, isEmpty);
    });
  });

  group('Wave Long-Range — واجهة udapi', () {
    final s = UbntUdapi.parse(
      device: json.decode(waveDeviceJson),
      system: json.decode(waveSystemJson),
      statistics: json.decode(waveStatisticsJson),
      interfaces: json.decode(waveInterfacesJson),
    );

    test('الاسم والطراز والبرنامج والمعالج والحرارة والذاكرة', () {
      expect(s.host.hostname, 'Wave Long-Range');
      expect(s.host.devmodel, 'Wave Long-Range');
      expect(s.host.fwversion, '4.1.1');
      expect(s.host.temperature, 57);
      expect(s.host.cpuload, inInclusiveRange(0, 100));
      expect(s.memUsedPercent, isNotNull);
    });

    test('الراديو الرئيسيّ: 68 GHz بعرض 2160 وسعة 1 Gbps، والمسافة', () {
      final w = s.wireless!;
      expect(w.frequency, 68040);
      expect(w.chanbw, 2160);
      expect(w.txRate, 1000);
      expect(w.rxRate, 1000);
      expect(w.signal, -55);
      expect(w.distance, 4111);
      expect(s.isAirFiber60, isTrue, reason: 'تفتح لوحة الـ60 GHz');
    });

    test('الطرف الآخر: الاسم والعنوان والإشارتان والسعة والتعديل', () {
      final p = s.stations.single;
      expect(p.hostname, 'Wave Long-Range');
      expect(p.ip, '10.160.160.3');
      expect(p.signal, -55);
      expect(p.txSignal, -55);
      expect(p.dlCapacityKbps, 1000000);
      expect(p.ulCapacityKbps, 1000000);
      expect(p.txMcs, 9);
      expect(p.rxMcs, 10);
      expect(p.distanceMeters, 4111);
      expect(p.isLinked60, isTrue);
      expect(p.linkUptimeSec, greaterThan(0));
    });

    test('المنافذ: الإيثرنت 1000 موصول أوّلاً بعدّاداته، والراديوان والجسر', () {
      expect(s.interfaces.first.ifname, 'eth0');
      final eth = s.interfaces.first;
      expect(eth.speed, 1000);
      expect(eth.plugged, isTrue);
      expect(eth.rxBytes, greaterThan(0));
      expect({for (final i in s.interfaces) i.ifname}, {'eth0', 'wlan0', 'ath0', 'br0'});
      expect(s.lanSpeed, '1000Mbps-Full');
    });

    test('الحقائق: التعديل والقدرة والاحتياطيّ 5 GHz والتداخل وGPS', () {
      final ex = {for (final e in s.extras) e.k: e.v};
      expect(ex['الراديو الرئيسيّ'], '68.04 GHz · عرض 2160 MHz');
      expect(ex['السعة'], '↓1000 / ↑1000 Mbps');
      expect(ex['التعديل'], 'استقبال 16QAM · إرسال QPSK');
      expect(ex['قدرة الإرسال'], '20 dBm · EIRP 66');
      expect(ex['الإشارة المثاليّة'], '-38 dBm');
      expect(ex['الاحتياطيّ 5 GHz'], startsWith('5175 MHz · عرض 40'));
      expect(ex['التداخل'], isNotNull);
      expect(ex['GPS'], startsWith('مثبّت'));
      expect(ex['الطرف الآخر'], 'Wave Long-Range · 10.160.160.3');
    });

    test('ردود ناقصة لا ترمي: بلا راديو ولا أطراف ⇒ بلا لاسلكيّ، والقيم المجهولة صفر/فارغة لا اختراع', () {
      final empty = UbntUdapi.parse(device: null, system: null, statistics: const [], interfaces: null);
      expect(empty.wireless, isNull);
      expect(empty.stations, isEmpty);
      expect(empty.host.hostname, '');
      expect(empty.extras, isEmpty);
    });
  });

  group('كشف الجيل', () {
    test('الطرفيّة تطبع «not found» لا فراغاً ⇒ لا بيانات airOS', () {
      expect(UbntApi.noAirOsOutput(''), isTrue);
      expect(UbntApi.noAirOsOutput('ash: mca-status: not found'), isTrue);
      expect(UbntApi.noAirOsOutput('sh: mca-dump: not found\n'), isTrue);
      expect(UbntApi.noAirOsOutput('-ash: ubntbox: not found'), isTrue);
      expect(UbntApi.noAirOsOutput(af4xMcaStatus), isFalse);
      expect(UbntApi.noAirOsOutput('deviceName=x,platform=NanoStation M5'), isFalse);
    });

    test('board.json يعرّف المنتج (Wave/LTU) — وغيره لا', () {
      expect(UbntUdapi.productFromBoardJson('{"identification":{"family":"wave","product":"Wave Long-Range","model":"Wave-LR"}}'),
          'Wave Long-Range');
      expect(UbntUdapi.productFromBoardJson('{"identification":{"family":"ltu","model":"LTU-Rocket"}}'), 'LTU-Rocket');
      expect(UbntUdapi.productFromBoardJson('{"identification":{"product":"x"}}'), isNull, reason: 'بلا عائلة');
      expect(UbntUdapi.productFromBoardJson('cat: /etc/board.json: No such file or directory'), isNull);
      expect(UbntUdapi.productFromBoardJson(null), isNull);
    });
  });
}
