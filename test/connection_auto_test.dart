import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/connection_auto_api.dart';
import 'package:rad_mysvcs/models/device_health.dart';
import 'package:rad_mysvcs/models/subscriber.dart';
import 'package:rad_mysvcs/screens/whatsapp/connection_auto_widgets.dart';
import 'package:rad_mysvcs/services/connection_readings_uploader.dart';
import 'package:rad_mysvcs/services/permissions_service.dart';

import 'sim_el/sim_harness.dart';

/// «تنبيه المشترك» التلقائيّ (٣ نوفمبر — الخادم server/connAlertsAuto.js): التطبيق يقيس ويرفع القراءات الخام فقط، لحسابٍ فتحه
/// الخادم وتنبيهه مفعّل ووضعه غير يدويّ، ولمشتركي الحساب نفسه، بقراءةٍ لكلّ مشترك كلّ ١٥ دقيقة؛ والوكيل يختار الوضع والضوابط
/// ويوافق من «بانتظار موافقتك».
const _v = SimVariant(390, dark: false);

UbiquitiStatus _ubnt({int? signal = -55, int? ccq = 95, List<LanPort> lan = const [LanPort(name: 'eth0', speed: '100Mbps-Full', plugged: true)]}) =>
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

DeviceHealthSnapshot _snapU(UbiquitiStatus u) => DeviceHealthSnapshot(kind: DeviceKind.ubiquiti, ip: '10.0.0.2', ubnt: u);
DeviceHealthSnapshot _snapO({String rx = '-20.5', String temp = '45'}) => DeviceHealthSnapshot(
      kind: DeviceKind.ont,
      ip: '10.0.0.3',
      ont: OntOpticalInfo(txPower: '2.1', rxPower: rx, voltage: '3300', temperature: temp, bias: '10', sendStatus: 'ok'),
    );

Subscriber _sub(String idx, {String? phone = '07701234567', String? expiration, bool enabled = true}) => Subscriber.fromJson({
      'idx': idx,
      'username': 'u$idx',
      'firstname': 'مشترك',
      'lastname': idx,
      'phone': phone,
      'expiration': expiration ?? DateTime.now().add(const Duration(days: 10)).toIso8601String(),
      'enabled': enabled ? 1 : 0,
    });

Map<String, dynamic> _status({bool available = true, bool enabled = true, String mode = 'approval', bool dry = true, int pending = 0}) => {
      'success': true,
      'data': available
          ? {
              'available': true,
              'dry_run': dry,
              'alerts_enabled': enabled,
              'settings': {'mode': mode, 'remind_days': 3, 'max_sends': 3, 'daily_cap': 30, 'hour_from': 10, 'hour_to': 20, 'confirm_min': 30,
                'kinds': ['cable', 'signal', 'ccq', 'fiber_rx', 'fiber_temp']},
              'counts': {'pending': pending, 'watching': 2, 'sent_today': 1},
              'in_window': true,
            }
          : {'available': false},
    };

void main() {
  test('القراءة: كيبل 10 ميكا والإشارة والـCCQ للنانو، والضوئيّ والحرارة للفايبر؛ «لم نقرأ» لا تُرفع؛ والمنتهي/المعطّل غير فعّال', () {
    final s = _sub('101');
    final r = ConnectionReadingsUploader.readingFor(
        s, _snapU(_ubnt(signal: -70, ccq: 40, lan: const [LanPort(name: 'eth0', speed: '10Mbps-Full', plugged: true)])))!;
    expect(r['idx'], '101');
    expect(r['phone'], '07701234567');
    expect((r['device'], r['lan'], r['signal'], r['ccq'], r['active']), ('ubnt', '10', -70, 40, true));
    final ok = ConnectionReadingsUploader.readingFor(s, _snapU(_ubnt()))!;
    expect(ok['lan'], 'ok', reason: 'سليمٌ مقروء يُرفع — هو ما يحلّ المشكلة بالخادم');
    final unplugged = ConnectionReadingsUploader.readingFor(
        s, _snapU(_ubnt(lan: const [LanPort(name: 'eth0', speed: null, plugged: false)])))!;
    expect(unplugged['lan'], 'unplugged');
    final o = ConnectionReadingsUploader.readingFor(s, _snapO(rx: '-28.4', temp: '71'))!;
    expect((o['device'], o['rx'], o['temp']), ('ont', -28.4, 71.0));
    expect(ConnectionReadingsUploader.readingFor(s, _snapU(_ubnt(signal: 0, ccq: 0, lan: const []))), isNull, reason: 'لم نقرأ شيئاً');
    final expired = _sub('7', expiration: DateTime.now().subtract(const Duration(days: 1)).toIso8601String());
    expect(ConnectionReadingsUploader.readingFor(expired, _snapU(_ubnt()))!['active'], false);
    expect(ConnectionReadingsUploader.readingFor(_sub('8', enabled: false), _snapU(_ubnt()))!['active'], false);
  });

  group('الرفع', () {
    late SimServer server;
    setUpAll(simSetUpAll);
    setUp(() async {
      server = await simSetUp(secure: {'auth.admin_id': '2', 'auth.admin_username': 'owner'});
      ConnectionAutoApi.debugReset();
      ConnectionReadingsUploader.debugReset();
      server.reply('POST', '/api/v2/connection-alerts/readings', 200, {'success': true, 'data': {'active': true, 'received': 2}});
    });

    test('مطفأ للحساب ⇒ لا رفع أبداً', () async {
      server.reply('GET', '/api/v2/connection-alerts/auto', 200, _status(available: false));
      ConnectionReadingsUploader.debugSnapshotOf = (_) => _snapU(_ubnt(signal: -70));
      await ConnectionReadingsUploader.collect([_sub('1')]);
      expect(server.calls('POST', '/api/v2/connection-alerts/readings'), isEmpty);
    });

    test('مفتوح ومفعّل ⇒ مشتركو الحساب بلقطاتهم (لا شركةٌ أخرى ولا بلا لقطة)، ثمّ لا تكرار قبل ١٥ دقيقة', () async {
      server.reply('GET', '/api/v2/connection-alerts/auto', 200, _status());
      final other = _sub('3').withCompany('nbtel:9');
      ConnectionReadingsUploader.debugSnapshotOf = (u) => u == 'u4' ? null : _snapU(_ubnt(signal: -70));
      await ConnectionReadingsUploader.collect([_sub('1'), _sub('2'), other, _sub('4')]);
      final b = server.bodies('POST', '/api/v2/connection-alerts/readings');
      expect(b, hasLength(1));
      expect((b.single['readings'] as List).map((r) => (r as Map)['idx']), ['1', '2']);
      await ConnectionReadingsUploader.collect([_sub('1'), _sub('2')]);
      expect(server.calls('POST', '/api/v2/connection-alerts/readings'), hasLength(1), reason: 'مخنوقٌ لكلّ مشترك');
    });

    test('الوضع يدويّ أو التنبيه مطفأ ⇒ لا رفع', () async {
      ConnectionReadingsUploader.debugSnapshotOf = (_) => _snapU(_ubnt(signal: -70));
      server.reply('GET', '/api/v2/connection-alerts/auto', 200, _status(mode: 'manual'));
      await ConnectionReadingsUploader.collect([_sub('1')]);
      ConnectionAutoApi.debugReset();
      server.reply('GET', '/api/v2/connection-alerts/auto', 200, _status(enabled: false));
      await ConnectionReadingsUploader.collect([_sub('1')]);
      expect(server.calls('POST', '/api/v2/connection-alerts/readings'), isEmpty);
    });
  });

  group('الواجهة', () {
    late SimServer server;
    setUpAll(simSetUpAll);
    setUp(() async {
      server = await simSetUp(secure: {'auth.admin_id': '2', 'auth.admin_username': 'owner'});
      ConnectionAutoApi.debugReset();
      PermissionsService.debugSet(isEmployee: false);
    });
    tearDown(PermissionsService.debugReset);

    testWidgets('البطاقة: مخفيّة لحسابٍ لم يُفتح له', (t) async {
      server.reply('GET', '/api/v2/connection-alerts/auto', 200, _status(available: false));
      await pumpSim(t, _v, home: (_) => const Scaffold(body: ConnAutoCard(canEdit: true)));
      await t.pumpAndSettle();
      expect(find.text('الإرسال التلقائيّ'), findsNothing);
      await simDrain(t);
    });

    testWidgets('البطاقة: «بموافقتي» افتراضاً وشريط المحاكاة؛ «تلقائيّ» + تذكيرٌ كلّ ٤ أيّام ⇒ الحفظ يرسلها', (t) async {
      server.reply('GET', '/api/v2/connection-alerts/auto', 200, _status(pending: 3));
      server.reply('PUT', '/api/v2/connection-alerts/auto', 200, {'success': true, 'message': 'تم الحفظ'});
      await pumpSim(t, _v, home: (_) => Scaffold(body: ListView(children: const [ConnAutoCard(canEdit: true)])));
      await t.pumpAndSettle();
      expect(find.text('الإرسال التلقائيّ'), findsOneWidget);
      expect(find.textContaining('وضع المحاكاة'), findsOneWidget);
      expect(find.textContaining('وأنت تضغط «أرسل»'), findsOneWidget, reason: 'شرح «بموافقتي»');
      expect(find.text('بانتظار موافقتك'), findsOneWidget);
      expect(find.text('3'), findsOneWidget, reason: 'شارة العدد');
      expect(find.text('حفظ الإرسال التلقائيّ'), findsNothing, reason: 'لا تغيير');
      await t.tap(find.text('تلقائيّ'));
      await t.pump();
      final plus = find.descendant(of: find.ancestor(of: find.text('ذكّر المشترك كلّ'), matching: find.byType(Row)).first, matching: find.byTooltip('زيادة'));
      await t.tap(plus);
      await t.pump();
      expect(find.text('4 أيّام'), findsOneWidget);
      await t.tap(find.text('حفظ الإرسال التلقائيّ'));
      await t.pumpAndSettle();
      final put = server.bodies('PUT', '/api/v2/connection-alerts/auto').single;
      expect((put['mode'], put['remind_days'], put['max_sends']), ('auto', 4, 3));
      await simDrain(t);
    });

    testWidgets('القائمة: «بانتظار موافقتك» بمشاكله وأوقاته؛ «أرسل» يرسل مفتاحه، و«أرسل للكلّ» all', (t) async {
      server.reply('GET', '/api/v2/connection-alerts/auto', 200, _status(pending: 1));
      server.on('GET', '/api/v2/connection-alerts/queue', (o) {
        final st = o.queryParameters['state'];
        return SimReply(200, {
          'success': true,
          'data': {
            'available': true,
            'items': st == 'pending'
                ? [
                    {
                      'key': 'i:101', 'idx': '101', 'username': 'u101', 'name': 'علي حسن', 'state': 'pending',
                      'problems': [{'kind': 'signal', 'label': 'الإشارة', 'text': '⁨-70 dBm⁩'}],
                      'confirmed_ms': DateTime.now().subtract(const Duration(hours: 2)).millisecondsSinceEpoch,
                      'last_reading_ms': DateTime.now().subtract(const Duration(minutes: 5)).millisecondsSinceEpoch, 'sends': 0, 'muted': false,
                    },
                  ]
                : [],
          },
        });
      });
      server.reply('POST', '/api/v2/connection-alerts/queue/action', 200, {'success': true, 'data': {'done': 1, 'skipped': 0}});
      server.reply('GET', '/api/v2/connection-alerts/log', 200, {'success': true, 'data': {'available': true, 'items': []}});
      ConnectionAutoApi.status.value = ConnAutoStatus.fromJson(Map<String, dynamic>.from(_status(pending: 1)['data'] as Map));
      await pumpSim(t, _v, home: (_) => const ConnAutoQueueScreen());
      await t.pumpAndSettle();
      expect(find.text('علي حسن'), findsOneWidget);
      expect(find.textContaining('الإشارة: '), findsOneWidget);
      expect(find.textContaining('تأكّدت منذ 2 ساعة'), findsOneWidget);
      await t.tap(find.text('أرسل'));
      await t.pumpAndSettle();
      expect(server.bodies('POST', '/api/v2/connection-alerts/queue/action').last, {'action': 'approve', 'keys': ['i:101']});
      await t.tap(find.textContaining('أرسل للكلّ'));
      await t.pumpAndSettle();
      expect(server.bodies('POST', '/api/v2/connection-alerts/queue/action').last, {'action': 'approve', 'all': true});
      await simDrain(t);
    });
  });
}
