import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/network_devices_api.dart';
import 'package:rad_mysvcs/api/ubnt_api.dart';
import 'package:rad_mysvcs/core/platform/desktop_layout.dart';
import 'package:rad_mysvcs/models/network_device.dart';
import 'package:rad_mysvcs/screens/network_devices/device_vitals.dart';
import 'package:rad_mysvcs/screens/network_devices/widgets/ubnt_live_panel.dart';
import 'package:rad_mysvcs/services/vitals_reporter.dart';

import 'support/ubnt_gen3_fixtures.dart';
import 'visual_perm/visual_perm_harness.dart';

/// «الـcpu الوهمي» (المالك ٢٢ نوفمبر، صورة «مراقبة حيّة (UBNT via SSH)»: Rocket M5 «المعالج 85٪» أحمر): التطبيق كان يضرب
/// **متوسّط الحِمل** في 100 — `loadavg=0.85` من mca-status أو أوّل رقمٍ في /proc/loadavg — ويعرضه نسبة معالج. متوسّط الحِمل عدد
/// المهامّ الجاهزة والعالقة في الانتظار، وairOS يبقيه قرب 1 ومعالجه شبه خامل؛ وجهازٌ حقيقيّ يفضحه (airFiber 60 GP:
/// `cpuUsage=12.5` بجانب `loadavg=54`). الآن: نسبة الجهاز الصريحة، أو انشغاله في ثانيةٍ هادئة من /proc/stat، وإلّا «—».
///
/// المسار يُختبر **كاملاً** على طرفيّة airOS مزيّفة ([UbntApi.debugCollect]): كلّ أمرٍ يرسله التطبيق يمرّ بها بنصّه الذي يذهب
/// في SSH، والمزيّفة تنفّذه كما ينفّذه ash على الجهاز (الأوامر المتسلسلة بـ`;`، `sleep 1` يقدّم العدّادات ثانيةً).
void main() {
  group('نافذة /proc/stat ⇒ نسبة المعالج', () {
    String line(List<int> f) => 'cpu  ${f.join(' ')}';

    test('ثانيةٌ هادئة على نواةٍ واحدة: 7 من 100 علامة مشغولة ⇒ 7٪', () {
      final a = [120000, 0, 80000, 9600000, 3000, 500, 9000, 0, 0, 0];
      final b = [120004, 0, 80002, 9600093, 3000, 500, 9001, 0, 0, 0];
      expect(UbntApi.cpuPercentFromProcStat('${line(a)}\n${line(b)}\n'), 7);
    });

    test('انتظار القرص خمولٌ لا انشغال', () {
      // 100 علامة: 40 خمول + 50 انتظار قرص + 10 عمل ⇒ 10٪ (لا 60٪)
      final a = [1000, 0, 1000, 50000, 2000, 0, 0];
      final b = [1006, 0, 1004, 50040, 2050, 0, 0];
      expect(UbntApi.cpuPercentFromProcStat('${line(a)}\n${line(b)}'), 10);
    });

    test('guest محسوبٌ داخل user — لا يُجمع مرّتين', () {
      // 100 علامة: user +30 منها guest +30 ⇒ 30٪ (جمعُ guest يجعلها 130 علامة و٪46)
      final a = [1000, 0, 1000, 50000, 0, 0, 0, 0, 500, 0];
      final b = [1030, 0, 1000, 50070, 0, 0, 0, 0, 530, 0];
      expect(UbntApi.cpuPercentFromProcStat('${line(a)}\n${line(b)}'), 30);
    });

    test('نواة 2.4 بأربعة حقول، وأربع أنوية: المتوسّط على كلّها', () {
      expect(UbntApi.cpuPercentFromProcStat('cpu 10 0 10 1000\ncpu 30 0 30 1060'), 40);
      // 400 علامة (4 أنوية × 100): 100 منها عمل ⇒ 25٪ — سطور cpu0..cpu3 لا تُحسب
      const out = 'cpu  1000 0 0 40000 0 0 0\ncpu0 250 0 0 10000\n'
          'cpu  1100 0 0 40300 0 0 0\ncpu0 275 0 0 10075\n';
      expect(UbntApi.cpuPercentFromProcStat(out), 25);
    });

    test('مشغولٌ كلّه 100، وخاملٌ كلّه 0 (صفرٌ مقيس لا مجهول)', () {
      expect(UbntApi.cpuPercentFromProcStat('cpu 0 0 0 1000\ncpu 100 0 0 1000'), 100);
      expect(UbntApi.cpuPercentFromProcStat('cpu 0 0 0 1000\ncpu 0 0 0 1100'), 0);
    });

    test('لا رقم من قراءةٍ لا تكفي: لقطةٌ واحدة · لا head · cpu0 وحده · عدّادٌ رجع · نافذةٌ أقصر من 0.2ث', () {
      expect(UbntApi.cpuPercentFromProcStat('cpu  1 0 1 100 0 0 0'), isNull);
      expect(UbntApi.cpuPercentFromProcStat('ash: head: not found\nash: head: not found\n'), isNull);
      expect(UbntApi.cpuPercentFromProcStat('cpu0 1 0 1 100\ncpu0 5 0 5 190'), isNull);
      // أُعيد تشغيل الجهاز بين اللقطتين ⇒ العدّادات أصغر
      expect(UbntApi.cpuPercentFromProcStat('cpu 9000 0 9000 90000\ncpu 10 0 10 100'), isNull);
      expect(UbntApi.cpuPercentFromProcStat('cpu 10 0 10 1000\ncpu 11 0 10 1005'), isNull);
      expect(UbntApi.cpuPercentFromProcStat(''), isNull);
    });

    test('خمولٌ رجع للوراء والكلّ تقدّم (خللٌ في عدّ النواة) ⇒ null لا «100٪»', () {
      // الكلّ +300 والخمول −100 ⇒ الحساب الساذج 133٪ يُقصّ إلى 100 أحمر — رقمٌ كاذب
      expect(UbntApi.cpuPercentFromProcStat('cpu 100 0 100 1000 500\ncpu 300 0 300 900 500'), isNull);
    });
  });

  group('نسبة المعالج من خرج الجهاز', () {
    UbntStats from(Map<String, String> m) => UbntStats.fromMcaStatus({'deviceName': 'x', ...m});

    test('متوسّط الحِمل وحده ⇒ لا رقم — كان «85٪»', () {
      expect(from({'loadavg': '0.85'}).host.cpuload, isNull);
      expect(from({'loadavg': '54'}).host.cpuload, isNull);
      expect(from({'cpuLoadAvg': '(0.85 0.60 0.40)'}).host.cpuload, isNull);
    });

    test('airFiber 60 GP الحقيقيّ: cpuUsage=12.5 بجانب loadavg=54 ⇒ 13 لا 54', () {
      expect(from({'cpuUsage': '12.5', 'loadavg': '54'}).host.cpuload, 13);
    });

    test('airFiber 4X الحقيقيّ (loadavg=0 ولا نسبة) ⇒ «—» لا «0٪»', () {
      final s = UbntStats.fromMcaStatus(UbntApi.parseMcaStatusForTest(af4xMcaStatus));
      expect(s.host.cpuload, isNull);
      expect(s.host.uptime, 776835, reason: 'بقيّة الخرج تُقرأ كما كانت');
    });

    test('ما قسناه يتقدّم على cpuload، وcpuload حين تعذّر القياس', () {
      expect(from({UbntStats.cpuMeasuredKey: '22', 'cpuload': '15.384615'}).host.cpuload, 22);
      expect(from({'cpuload': '15.384615'}).host.cpuload, 15);
      expect(from({'cpuUsage': '12.5', UbntStats.cpuMeasuredKey: '22'}).host.cpuload, 13);
    });

    test('قيمٌ لا تصلح نسبة ⇒ null لا صفر', () {
      for (final v in ['-3', '250', 'abc', 'NaN', '']) {
        expect(from({'cpuload': v}).host.cpuload, isNull, reason: v);
      }
      expect(from({'cpuload': '100.2'}).host.cpuload, 100);
    });
  });

  group('المسار كاملاً على طرفيّة airOS', () {
    test('Rocket M5 بـairOS 6: الحِمل 0.85 والمعالج 7٪ ⇒ 7٪ — بلا loadavg، والنافذة في الأمر المجمَّع', () async {
      final dev = _AirOs(mcaStatus: _rocketM5McaStatus, busyPerSecond: 7);
      UbntStats? partial;
      final s = await UbntApi.debugCollect(dev.run, onPartialReady: (p) => partial = p);

      expect(s.host.cpuload, 7);
      expect(partial, isNotNull);
      expect(partial!.host.cpuload, isNull, reason: 'القراءة الأولى السريعة لا تعرض رقماً لم يُقس بعد (ولا 85)');
      expect(dev.commands.where((c) => c.contains('loadavg')), isEmpty);
      final batched = dev.commands.singleWhere((c) => c.contains('===MYSVCS_SECTION==='));
      expect(batched, contains(UbntApi.cpuWindowCmd));
      expect(dev.windowsMeasured, 1);

      // بقيّة القراءة كما كانت (نقل الأوامر خلف منفذ الاختبار لم يغيّر شيئاً)
      expect(s.host.devmodel, 'Rocket M5');
      expect(s.host.uptime, 2318066);
      expect(s.wireless?.essid, 'Sector-North');
      expect(s.stations, hasLength(2));
      expect(s.stationsRead, isTrue);
      expect(s.memTotalKb, 29616);
      final eth0 = s.interfaces.singleWhere((i) => i.ifname == 'eth0');
      expect(eth0.speed, 100);
      expect(eth0.rxBytes, 1234567890);
    });

    test('معالجٌ مشغولٌ فعلاً 92٪ يظهر 92٪ — لا نُخفي حِملاً حقيقيّاً', () async {
      final s = await UbntApi.debugCollect(_AirOs(mcaStatus: _rocketM5McaStatus, busyPerSecond: 92).run);
      expect(s.host.cpuload, 92);
    });

    test('airFiber 60 GP يذكر نسبته (cpuUsage) ⇒ تُعرض من القراءة الأولى، بلا ثانية قياسٍ إضافيّة', () async {
      final dev = _AirOs(mcaStatus: '$_rocketM5McaStatus\ncpuUsage=12.5\nloadavg=54\n');
      UbntStats? partial;
      final s = await UbntApi.debugCollect(dev.run, onPartialReady: (p) => partial = p);
      expect(s.host.cpuload, 13);
      expect(partial!.host.cpuload, 13);
      expect(dev.windowsMeasured, 0);
      expect(dev.commands.any((c) => c.contains('sleep')), isFalse);
    });

    test('طرفيّةٌ بلا head ⇒ «—» لا 85 ولا 0', () async {
      final s = await UbntApi.debugCollect(_AirOs(mcaStatus: _rocketM5McaStatus, headMissing: true).run);
      expect(s.host.cpuload, isNull);
    });

    test('الأمر المجمَّع فشل ⇒ النافذة أمراً منفصلاً وتبقى النسبة صحيحة', () async {
      final dev = _AirOs(mcaStatus: _rocketM5McaStatus, busyPerSecond: 7, batchFails: true);
      final s = await UbntApi.debugCollect(dev.run);
      expect(dev.commands, contains(UbntApi.cpuWindowCmd));
      expect(s.host.cpuload, 7);
      expect(s.stations, hasLength(2));
    });

    test('mca-dump (JSON) بنسبة الجهاز 15.4 ونافذتنا 22 ⇒ 22؛ وإن تعذّرت النافذة ⇒ 15', () async {
      final measured = await UbntApi.debugCollect(_AirOs(mcaStatus: '', mcaDump: _acDump, busyPerSecond: 22).run);
      expect(measured.host.cpuload, 22);
      UbntStats? partial;
      final fallback = await UbntApi.debugCollect(_AirOs(mcaStatus: '', mcaDump: _acDump, headMissing: true).run,
          onPartialReady: (p) => partial = p);
      expect(fallback.host.cpuload, 15);
      expect(partial!.host.cpuload, isNull, reason: 'رقم الجهاز غير المؤكَّد لا يظهر قبل أن يفشل قياسنا');
    });
  });

  group('البطاقات والتنبيهات', () {
    NetworkDevice dev(int id) => NetworkDevice(
          id: id,
          adminId: '1',
          name: 'سكتر $id',
          type: 'ap',
          brand: 'ubnt',
          model: 'Rocket M5',
          ip: '10.9.0.$id',
          port: 22,
          hasCredentials: true,
          lastStatus: 'online',
          createdAt: DateTime(2026, 11, 1),
        );

    tearDown(() => UbntApi.debugFetch = null);

    test('لا نسبة ⇒ خانة المعالج فارغة (لا «0٪») وتنبيه «المعالج» لا يستلم شيئاً', () async {
      final d = dev(901);
      NetworkDevicesApi.debugSeedCredentials(d.id, {'user': 'u', 'pass': 'p'}, DateTime.now());
      UbntApi.debugFetch = () async => _stats(cpu: null);
      final r = await DeviceVitals.fetch(d, detailed: true);
      expect(r.vitals.map((v) => v.label), isNot(contains('المعالج')));
      expect(r.vitals.where((v) => v.value == '0'), isEmpty);
      expect(r.detail.glance.cpu, isNull);
      final reading = VitalsReporter.readingOf(d.id, r.detail.glance);
      expect(reading?.containsKey('cpu') ?? false, isFalse);
    });

    test('نسبةٌ مقيسة ⇒ في الخانة وفي التنبيه كما هي', () async {
      final d = dev(902);
      NetworkDevicesApi.debugSeedCredentials(d.id, {'user': 'u', 'pass': 'p'}, DateTime.now());
      UbntApi.debugFetch = () async => _stats(cpu: 7);
      final r = await DeviceVitals.fetch(d, detailed: true);
      final cpu = r.vitals.singleWhere((v) => v.label == 'المعالج');
      expect(cpu.value, '7');
      expect(r.detail.glance.cpu, 7);
      expect(VitalsReporter.readingOf(d.id, r.detail.glance)!['cpu'], 7);
    });
  });

  group('اللوحة الحيّة', () {
    setUpAll(visualSetUpAll);

    Future<void> pumpPanel(WidgetTester t, {required int? cpu, required bool desk, required int id}) async {
      await visualSetUp(s1bSasOwner);
      final d = NetworkDevice(
        id: id,
        adminId: '1',
        name: 'Rocket',
        type: 'ap',
        brand: 'ubnt',
        model: 'Rocket M5',
        ip: '10.9.1.$id',
        port: 22,
        hasCredentials: true,
        lastStatus: 'online',
        createdAt: DateTime(2026, 11, 1),
      );
      NetworkDevicesApi.debugSeedCredentials(d.id, {'user': 'u', 'pass': 'p'}, DateTime.now());
      UbntApi.debugFetch = () async => _stats(cpu: cpu);
      Widget panel = Scaffold(body: SingleChildScrollView(child: UbntLivePanel(device: d)));
      if (desk) panel = DesktopScope(child: panel);
      await pumpVisual(t, desk ? const VisualDevice('_desk', Size(1260, 860), 1) : phone, home: (_) => panel);
      for (var i = 0; i < 10; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
    }

    Future<void> done(WidgetTester t) async {
      UbntApi.debugFetch = null;
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 30));
      await visualTearDown();
    }

    for (final desk in [true, false]) {
      final where = desk ? 'الحاسبة' : 'الهاتف';
      testWidgets('$where: لا نسبة ⇒ «—»${desk ? ' و«لم تُقرأ»' : ''}، لا «85» ولا «0»', (t) async {
        await pumpPanel(t, cpu: null, desk: desk, id: desk ? 911 : 912);
        try {
          expect(find.text('85'), findsNothing);
          expect(find.text('—'), findsWidgets);
          if (desk) expect(find.text('لم تُقرأ'), findsOneWidget);
          expect(t.takeException(), isNull);
        } finally {
          await done(t);
        }
      });

      testWidgets('$where: نسبةٌ مقيسة 7٪ تظهر 7', (t) async {
        await pumpPanel(t, cpu: 7, desk: desk, id: desk ? 913 : 914);
        try {
          expect(find.text('7'), findsWidgets);
          expect(find.text('لم تُقرأ'), findsNothing);
          expect(t.takeException(), isNull);
        } finally {
          await done(t);
        }
      });
    }
  });
}

/// طرفيّة airOS مزيّفة: تنفّذ ما يرسله التطبيق كما ينفّذه ash على الجهاز — الأوامر المتسلسلة بـ`;` واحداً بعد الآخر، وخرج
/// stderr مدموجٌ في الخرج كما تعيده جلسة SSH، و`sleep 1` يقدّم عدّادات /proc/stat ثانيةً (100 علامة، [busyPerSecond] منها عمل).
class _AirOs {
  _AirOs({
    required this.mcaStatus,
    this.mcaDump,
    this.busyPerSecond = 7,
    this.headMissing = false,
    this.batchFails = false,
  });

  final String mcaStatus;
  final String? mcaDump;
  final int busyPerSecond;
  final bool headMissing;
  final bool batchFails;
  final commands = <String>[];
  int windowsMeasured = 0;

  // /proc/stat — نواةٌ واحدة، USER_HZ=100، جهازٌ يعمل منذ ٢٦ يوماً
  int _user = 120000, _system = 80000, _idle = 9600000, _softirq = 9000;
  String get _stat => 'cpu  $_user 0 $_system $_idle 3000 500 $_softirq 0 0 0';

  void _second() {
    windowsMeasured++;
    final b = busyPerSecond;
    final u = b ~/ 2, s = b ~/ 3;
    _user += u;
    _system += s;
    _softirq += b - u - s;
    _idle += 100 - b;
  }

  String _one(String raw) {
    final c = raw.trim();
    if (c.startsWith('echo ')) return '${c.substring(5)}\n';
    if (c.startsWith('cat /sys/class/net/')) return '';
    if (c.startsWith('mii-tool ')) return '${c.split(' ')[1]}: negotiated 100baseTx-FD flow-control, link ok\n';
    switch (c) {
      case 'mca-dump':
        return mcaDump ?? 'ash: mca-dump: not found\n';
      case 'mca-status':
        return mcaStatus;
      case 'af-status 2>/dev/null':
        return '';
      case 'wstalist 2>/dev/null':
        return _wstalist;
      case 'cat /proc/uptime':
        return '2318066.12 2201234.55\n';
      case 'cat /proc/loadavg':
        return '0.85 0.92 0.88 2/45 1234\n';
      case 'head -n 1 /proc/stat':
        return headMissing ? 'ash: head: not found\n' : '$_stat\n';
      case 'sleep 1':
        _second();
        return '';
      case 'true':
        return '';
      case 'iwconfig 2>/dev/null':
        return _iwconfig;
      case 'ifconfig':
        return _ifconfig;
    }
    return 'ash: ${c.split(' ').first}: not found\n';
  }

  Future<String> run(String cmd) async {
    commands.add(cmd);
    if (batchFails && cmd.contains('===MYSVCS_SECTION===')) throw TimeoutException('batched');
    return cmd.split(';').map(_one).join();
  }
}

/// خرج `mca-status` لـRocket M5 بـairOS 6 بشكل العيّنة الحقيقيّة (السطر الأوّل مضغوط بفواصل — mca_status_test)، ومعه
/// `loadavg` كما يطبعه الجهاز (airFiber 4X وairFiber 60 الحقيقيّان يطبعانه أيضاً).
const _rocketM5McaStatus = '''
deviceName=Sector-North-RM5,deviceId=F0:9F:C2:9C:36:24,firmwareVersion=XM.ar7240.v6.3.6.33330.210818.1640,platform=Rocket M5,deviceIp=10.102.157.5
wlanOpmode=ap
essid=Sector-North
apMac=F0:9F:C2:9C:36:24
signal=0
noise=-95
ccq=0
wlanConnections=2
lanSpeed=100Mbps-Full
uptime=2318066
loadavg=0.85
memTotal=29616
memFree=10316
memBuffers=2400
''';

const _wstalist = '[{"mac":"AA:BB:CC:00:00:01","name":"home-1","lastip":"10.0.0.21","signal":-62,"ccq":91,"tx":130,'
    '"rx":117,"uptime":3600,"noisefloor":-95,"distance":1200},{"mac":"AA:BB:CC:00:00:02","name":"home-2",'
    '"lastip":"10.0.0.22","signal":-71,"ccq":74,"tx":65,"rx":58,"uptime":7200,"noisefloor":-95,"distance":2400}]';

const _iwconfig = '''
ath0      IEEE 802.11na  ESSID:"Sector-North"  Mode:Master
          Frequency:5.745 GHz  Access Point: F0:9F:C2:9C:36:25
          Bit Rate:130 Mb/s   Tx-Power:24 dBm
''';

const _ifconfig = '''
ath0      Link encap:Ethernet  HWaddr F0:9F:C2:9C:36:25
          UP BROADCAST RUNNING MULTICAST  MTU:1500  Metric:1
          RX bytes:987654321 (941.9 MiB)  TX bytes:1234567890 (1.1 GiB)

eth0      Link encap:Ethernet  HWaddr F0:9F:C2:9C:36:24
          UP BROADCAST RUNNING MULTICAST  MTU:1500  Metric:1
          RX bytes:1234567890 (1.1 GiB)  TX bytes:987654321 (941.9 MiB)
''';

/// mca-dump (JSON) بقسم host كواجهة airOS 8 — نسبة الجهاز `cpuload` كسراً.
const _acDump = '{"host":{"hostname":"LB-AC","devmodel":"LiteBeam 5AC Gen2","fwversion":"v8.7.4","uptime":5000,'
    '"cpuload":15.384615,"loadavg":0.85},"wireless":{"essid":"Sector-AC","mode":"ap-ptmp","signal":0,"sta":[]}}';

UbntStats _stats({required int? cpu}) => UbntStats(
      host: UbntHost(hostname: 'RM5', devmodel: 'Rocket M5', fwversion: 'XM.v6.3.6', uptime: 5000, cpuload: cpu, temperature: 0),
      wireless: const UbntWireless(
        essid: 'Sector-North',
        mode: 'ap-ptmp',
        signal: 0,
        noise: -95,
        ccq: 0,
        txRate: 0,
        rxRate: 0,
        channel: 0,
        frequency: 5745,
        distance: 0,
        chanbw: 20,
      ),
      interfaces: const [
        UbntInterface(ifname: 'eth0', hwaddr: 'F0:9F:C2:9C:36:24', enabled: true, plugged: true, rxBytes: 100, txBytes: 100),
      ],
      memTotalKb: 29616,
      memFreeKb: 10316,
      memBuffersKb: 2400,
    );
