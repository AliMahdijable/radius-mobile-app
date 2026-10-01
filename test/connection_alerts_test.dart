import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/core/util/bidi.dart';
import 'package:rad_mysvcs/models/device_health.dart';
import 'package:rad_mysvcs/services/connection_alerts.dart';

/// حارس «تنبيه المشترك» بمشكلة الاتصال.
///
/// أخطر ما يقع هنا ليس أن نفوّت مشكلة، بل أن **نخترع** واحدة: رسالةٌ
/// تقول للمشترك «الكيبل غير مربوط» وجهازه سليم ترسله إلى السطح بلا داعٍ،
/// وتُفقد الثقة بكلّ تنبيهٍ بعدها. لذلك نصف هذه الاختبارات عن «لا مشكلة».
void main() {
  const t = ConnectionAlertThresholds.defaults;

  UbiquitiStatus ubnt({
    int? signal = -55,
    int? ccq = 95,
    List<LanPort> lan = const [
      LanPort(name: 'eth0', speed: '100Mbps-Full', plugged: true),
    ],
  }) =>
      UbiquitiStatus(
        hostname: 'nano',
        firmware: 'XW.v6.3',
        uptimeSeconds: 100,
        ssid: 'AP',
        mode: 'sta',
        signalDbm: signal,
        noiseFloorDbm: -95,
        ccqPercent: ccq,
        distanceMeters: 800,
        txRateKbps: 0,
        rxRateKbps: 0,
        lanPorts: lan,
        peerMac: null,
        peerCount: null,
        baseUrl: 'http://10.0.0.2',
      );

  DeviceHealthSnapshot snapU(UbiquitiStatus u) =>
      DeviceHealthSnapshot(kind: DeviceKind.ubiquiti, ip: '10.0.0.2', ubnt: u);

  DeviceHealthSnapshot snapO({String rx = '-20.5', String temp = '45'}) =>
      DeviceHealthSnapshot(
        kind: DeviceKind.ont,
        ip: '10.0.0.3',
        ont: OntOpticalInfo(
          txPower: '2.1',
          rxPower: rx,
          voltage: '3300',
          temperature: temp,
          bias: '10',
          sendStatus: 'ok',
        ),
      );

  List<ConnectionProblemKind> kinds(DeviceHealthSnapshot s,
          [ConnectionAlertThresholds th = t]) =>
      ConnectionAlerts.detect(s, th).map((p) => p.kind).toList();

  group('التفعيل — المدير يفعّلها بنفسه', () {
    test('🚨 الافتراضيّ متوقّف', () {
      expect(ConnectionAlertThresholds.defaults.enabled, isFalse);
      expect(ConnectionAlertThresholds.fromJson(const {}).enabled, isFalse);
    });

    test('يُقرأ من الخادم بأشكاله (true · 1 · "1")', () {
      for (final v in [true, 1, '1']) {
        expect(ConnectionAlertThresholds.fromJson({'enabled': v}).enabled,
            isTrue,
            reason: '$v');
      }
      for (final v in [false, 0, '0', null]) {
        expect(ConnectionAlertThresholds.fromJson({'enabled': v}).enabled,
            isFalse,
            reason: '$v');
      }
    });

    test('يُرسَل مع الحدود عند الحفظ', () {
      expect(t.copyWith(enabled: true).toJson()['enabled'], isTrue);
    });
  });

  group('نانو سليم = لا مشكلة', () {
    test('القيم الجيّدة', () {
      expect(kinds(snapU(ubnt())), isEmpty);
    });

    test('الإشارة على الحدّ تماماً ليست مشكلة (‎-60 ليست أضعف من ‎-60)', () {
      expect(kinds(snapU(ubnt(signal: -60))), isEmpty);
    });

    test('صفرٌ ليس قراءة — لا إشارة 0 ولا CCQ 0 لجهازٍ نصله', () {
      expect(kinds(snapU(ubnt(signal: 0, ccq: 0))), isEmpty);
    });

    test('قيمٌ غائبة لا تُعدّ مشكلة', () {
      expect(kinds(snapU(ubnt(signal: null, ccq: null))), isEmpty);
    });
  });

  group('الإشارة وCCQ بحدود المدير', () {
    test('‎-65 أضعف من ‎-60 = مشكلة', () {
      expect(kinds(snapU(ubnt(signal: -65))), [ConnectionProblemKind.signal]);
    });

    test('حدّ المدير يحكم: ‎-65 سليمة لمن حدّه ‎-70', () {
      expect(kinds(snapU(ubnt(signal: -65)), t.copyWith(signalDbm: -70)),
          isEmpty);
    });

    test('CCQ ‏50 أو أقلّ = مشكلة، و51 سليم', () {
      expect(kinds(snapU(ubnt(ccq: 50))), [ConnectionProblemKind.ccq]);
      expect(kinds(snapU(ubnt(ccq: 51))), isEmpty);
    });
  });

  group('الكيبل — سببٌ واحد لحالتين', () {
    test('غير مربوط', () {
      final u = ubnt(lan: const [
        LanPort(name: 'eth0', speed: null, plugged: false),
      ]);
      expect(ConnectionAlerts.lanState(u), 'غير مربوط');
      expect(kinds(snapU(u)), [ConnectionProblemKind.cable]);
    });

    test('يقرأ 10 ميكا', () {
      final u = ubnt(lan: const [
        LanPort(name: 'eth0', speed: '10Mbps-Half', plugged: true),
      ]);
      expect(ConnectionAlerts.lanState(u), 'يقرأ 10 ميكا');
      expect(kinds(snapU(u)), [ConnectionProblemKind.cable]);
    });

    test('‏0Mbps يعرضه التطبيق «Unplugged» — والتنبيه يتّفق معه', () {
      final u = ubnt(lan: const [
        LanPort(name: 'eth0', speed: '0Mbps', plugged: true),
      ]);
      expect(ConnectionAlerts.lanState(u), 'غير مربوط');
    });

    test('‏100 و1000 سليمان', () {
      for (final sp in ['100Mbps-Full', '1000Mbps-Full']) {
        final u = ubnt(lan: [LanPort(name: 'eth0', speed: sp, plugged: true)]);
        expect(ConnectionAlerts.lanState(u), isNull, reason: sp);
      }
    });

    test('🚨 لا منافذ مقروءة ≠ غير مربوط', () {
      expect(ConnectionAlerts.lanState(ubnt(lan: const [])), isNull);
    });

    test('موصولٌ بسرعةٍ مجهولة (airOS 5) ليس عطلاً', () {
      final u = ubnt(lan: const [
        LanPort(name: 'LAN', speed: null, plugged: true),
      ]);
      expect(ConnectionAlerts.lanState(u), isNull);
    });

    test('منفذٌ مربوط سليم ومنفذٌ ثانٍ فارغ = سليم', () {
      final u = ubnt(lan: const [
        LanPort(name: 'eth0', speed: null, plugged: false),
        LanPort(name: 'eth1', speed: '100Mbps-Full', plugged: true),
      ]);
      expect(ConnectionAlerts.lanState(u), isNull);
    });
  });

  group('الضوئي', () {
    test('سليم', () {
      expect(kinds(snapO()), isEmpty);
    });

    test('‎-28 أضعف من ‎-27 = مشكلة، و‎-27 على الحدّ سليم', () {
      expect(kinds(snapO(rx: '-28')), [ConnectionProblemKind.fiberRx]);
      expect(kinds(snapO(rx: '-27')), isEmpty);
    });

    test('حرارة 71 فوق 70 = مشكلة، و70 سليمة', () {
      expect(kinds(snapO(temp: '71')), [ConnectionProblemKind.fiberTemp]);
      expect(kinds(snapO(temp: '70')), isEmpty);
    });

    test('قراءةٌ غير مفهومة لا تُعدّ مشكلة', () {
      expect(kinds(snapO(rx: '', temp: '--')), isEmpty);
    });
  });

  group('تركيب الرسالة', () {
    final envelope = ConnectionAlertTemplates.defaultFor('connection_alert');

    test('مشكلتان = رسالةٌ واحدة بسطرين', () {
      final u = ubnt(signal: -70, lan: const [
        LanPort(name: 'eth0', speed: null, plugged: false),
      ]);
      final problems = ConnectionAlerts.detect(snapU(u), t);
      final msg = ConnectionAlerts.compose(
          envelope: envelope, lines: const {}, problems: problems);
      expect('مرحباً'.allMatches(msg).length, 1);
      expect(msg, contains('خلل بكيبل الإنترنت'));
      expect(msg, contains('الإشارة ضعيفة'));
      expect(msg, isNot(contains('{problems}')));
      expect(msg, isNot(contains('{signal}')));
    });

    test('🚨 القيمة السالبة معزولة الاتّجاه — لا تنقلب إلى 68-', () {
      final problems = ConnectionAlerts.detect(snapU(ubnt(signal: -68)), t);
      final msg = ConnectionAlerts.compose(
          envelope: envelope, lines: const {}, problems: problems);
      expect(msg, contains(iso('-68 dBm')));
    });

    test('سطر المدير يحلّ محلّ الافتراضيّ، والفارغ يعود إليه', () {
      final problems = ConnectionAlerts.detect(snapU(ubnt(ccq: 30)), t);
      final own = ConnectionAlerts.compose(
        envelope: envelope,
        lines: const {'conn_alert_ccq': '• الربط ضعيف {ccq} حبيبي'},
        problems: problems,
      );
      expect(own, contains('الربط ضعيف'));
      final blank = ConnectionAlerts.compose(
        envelope: envelope,
        lines: const {'conn_alert_ccq': '   '},
        problems: problems,
      );
      expect(blank, contains('جودة الربط منخفضة'));
    });

    test('{lan_state} اختياريّ يحمل السبب الدقيق', () {
      final u = ubnt(lan: const [
        LanPort(name: 'eth0', speed: '10Mbps-Full', plugged: true),
      ]);
      final msg = ConnectionAlerts.compose(
        envelope: envelope,
        lines: const {'conn_alert_cable': '• الكيبل {lan_state}'},
        problems: ConnectionAlerts.detect(snapU(u), t),
      );
      expect(msg, contains('• الكيبل يقرأ 10 ميكا'));
    });

    test('قالبٌ حُذف منه {problems} لا يبتلع المشاكل', () {
      final problems = ConnectionAlerts.detect(snapU(ubnt(signal: -80)), t);
      final msg = ConnectionAlerts.compose(
          envelope: 'مرحباً {subscriber_name}',
          lines: const {},
          problems: problems);
      expect(msg, contains('الإشارة ضعيفة'));
    });
  });
}
