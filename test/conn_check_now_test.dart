import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/connection_auto_api.dart';
import 'package:rad_mysvcs/models/device_health.dart';
import 'package:rad_mysvcs/models/subscriber.dart';
import 'package:rad_mysvcs/screens/whatsapp/connection_auto_widgets.dart';
import 'package:rad_mysvcs/services/conn_check_now.dart';
import 'package:rad_mysvcs/services/connection_readings_uploader.dart';
import 'package:rad_mysvcs/services/device_warm_service.dart';

import 'sim_el/sim_harness.dart';

/// «افحص الآن» في «تنبيهات المشتركين» (٤ نوفمبر — المالك: «من هو خارج شبكه او داخله يستدعي داله الفحص وينتظر لحد مايكمل الفحص
/// ويعطي النتيجه وانتبه من تكرار النقر ع الزر»): من الشبكة يفحص التطبيق بنفسه ويرفع، وخارجها جولةٌ عبر VPN الخادم — ويُنتظر.
const _v = SimVariant(390, dark: false);

Subscriber _sub(String idx) => Subscriber.fromJson({
      'idx': idx,
      'username': 'u$idx',
      'firstname': 'مشترك',
      'lastname': idx,
      'phone': '07701234567',
      'expiration': DateTime.now().add(const Duration(days: 10)).toIso8601String(),
      'enabled': 1,
    });

DeviceHealthSnapshot _snap(int signal) => DeviceHealthSnapshot(
      kind: DeviceKind.ubiquiti,
      ip: '10.0.0.2',
      ubnt: UbiquitiStatus(
        hostname: 'nano',
        firmware: 'XW.v6.3',
        uptimeSeconds: 100,
        ssid: 'AP',
        mode: 'sta',
        signalDbm: signal,
        noiseFloorDbm: -95,
        ccqPercent: 90,
        distanceMeters: 800,
        txRateKbps: 0,
        rxRateKbps: 0,
        lanPorts: const [LanPort(name: 'eth0', speed: '100Mbps-Full', plugged: true)],
        peerMac: null,
        peerCount: null,
        baseUrl: 'http://10.0.0.2',
      ),
    );

Map<String, dynamic> _status() => {
      'success': true,
      'data': {
        'available': true,
        'dry_run': true,
        'alerts_enabled': true,
        'settings': {'mode': 'approval', 'remind_days': 3, 'max_sends': 3, 'daily_cap': 30, 'hour_from': 10, 'hour_to': 20, 'confirm_min': 30,
          'kinds': ['cable', 'signal', 'ccq', 'fiber_rx', 'fiber_temp']},
        'counts': {'pending': 0, 'watching': 0, 'sent_today': 0},
        'in_window': true,
      },
    };

void main() {
  test('نصّ النتيجة من الشبكة: المقروء، ومن صار تحت المراقبة/تأكّد/حُلّ — أو «لا مشاكل جديدة»', () {
    expect(ConnCheckNow.localMessage((sent: 9, usable: 8, watching: 0, confirmed: 0, resolved: 0)),
        'فُحص من شبكتك ✓ — قُرئ 8 جهازاً — لا مشاكل جديدة');
    expect(ConnCheckNow.localMessage((sent: 9, usable: 8, watching: 2, confirmed: 1, resolved: 1)),
        'فُحص من شبكتك ✓ — قُرئ 8 جهازاً — 2 صار تحت المراقبة — 1 تأكّدت مشكلته — 1 حُلّت');
    final r = ConnCheckResult.fromVpn({'ok': true, 'message': 'فُحص عبر VPN ✓ — قُرئ 5 من 9 متّصلاً — 1 بمشكلة', 'readable': 5, 'problems': 1});
    expect((r.ok, r.via, r.readable, r.problems), (true, 'vpn', 5, 1));
    expect(ConnCheckResult.fromVpn(null).ok, false);
  });

  group('التشغيل', () {
    late SimServer server;
    setUpAll(simSetUpAll);
    setUp(() async {
      server = await simSetUp(secure: {'auth.admin_id': '2', 'auth.admin_username': 'owner'});
      ConnCheckNow.debugReset();
      ConnectionReadingsUploader.debugReset();
      DeviceWarmService.debugReset();
      ConnectionAutoApi.debugReset();
      server.reply('GET', '/api/v2/connection-alerts/auto', 200, _status());
    });
    tearDown(() {
      DeviceWarmService.debugReset();
      ConnectionReadingsUploader.debugReset();
    });

    test('من شبكة الوكيل: يفحص التطبيق بنفسه ويرفع الآن (لا VPN)، والضغطتان معاً فحصٌ واحد', () async {
      var checks = 0;
      DeviceWarmService.debugCheckNow = (onProgress) async {
        checks += 1;
        onProgress?.call(2, 2);
        return (onNet: true, subs: [_sub('101'), _sub('102')], probed: 2, reason: null);
      };
      ConnectionReadingsUploader.debugSnapshotOf = (u) => _snap(u == 'u101' ? -75 : -55);
      server.reply('POST', '/api/v2/connection-alerts/readings', 200, {
        'success': true,
        'data': {'active': true, 'received': 2, 'usable': 2, 'watching': 1, 'confirmed': 0, 'resolved': 0, 'recheck': []},
      });
      final a = ConnCheckNow.run();
      final b = ConnCheckNow.run();
      expect(identical(a, b), true, reason: 'الضغطة الثانية ⇒ الفحص نفسه');
      final r = await a;
      expect(checks, 1);
      expect((r.ok, r.via), (true, 'local'));
      expect(r.message, 'فُحص من شبكتك ✓ — قُرئ 2 جهازاً — 1 صار تحت المراقبة');
      expect(server.bodies('POST', '/api/v2/connection-alerts/readings').single['readings'], hasLength(2));
      expect(server.calls('POST', '/api/v2/conn-vpn/check-now'), isEmpty, reason: 'من الشبكة لا حِمل على خادمنا');
      expect(ConnCheckNow.last.value?.message, r.message);
      expect(ConnCheckNow.running.value, false);
    });

    test('خارج الشبكة: جولةٌ واحدة عبر VPN الخادم تُستطلع حتى تكتمل', () async {
      DeviceWarmService.debugCheckNow = (_) async => (onNet: false, subs: <Subscriber>[], probed: 0, reason: 'off_net');
      server.reply('POST', '/api/v2/conn-vpn/check-now', 200, {'success': true, 'data': {'check_id': 'c1', 'state': 'running'}});
      server.reply('GET', '/api/v2/conn-vpn/check-now/c1', 200, {
        'success': true,
        'data': {'state': 'done', 'result': {'ok': true, 'message': 'فُحص عبر VPN ✓ — قُرئ 5 من 9 متّصلاً — 1 بمشكلة', 'readable': 5, 'problems': 1}},
      });
      final r = await ConnCheckNow.run();
      expect((r.ok, r.via, r.problems), (true, 'vpn', 1));
      expect(r.message, contains('قُرئ 5 من 9'));
      expect(server.calls('POST', '/api/v2/connection-alerts/readings'), isEmpty);
    });

    test('بعد تبديل الشركة: نتيجة فحص حسابٍ آخر لا تظهر (كان «لا مشاكل» لشركةٍ فوق مشاكل غيرها)؛ والحساب نفسه تبقى له', () async {
      DeviceWarmService.debugCheckNow = (_) async => (onNet: false, subs: <Subscriber>[], probed: 0, reason: 'off_net');
      server.reply('POST', '/api/v2/conn-vpn/check-now', 200, {'success': true, 'data': {'check_id': 'c2', 'state': 'running'}});
      server.reply('GET', '/api/v2/conn-vpn/check-now/c2', 200, {
        'success': true,
        'data': {'state': 'done', 'result': {'ok': true, 'message': 'فُحص عبر VPN ✓ — قُرئ 20 من 72 متّصلاً — لا مشاكل'}},
      });
      await ConnCheckNow.run();
      await ConnCheckNow.forgetOtherAccount();
      expect(ConnCheckNow.last.value?.message, contains('20 من 72'), reason: 'الحساب نفسه ⇒ تبقى');
      FlutterSecureStorage.setMockInitialValues({'auth.admin_id': 'ip-46-225-123-41:10'});
      await ConnCheckNow.forgetOtherAccount();
      expect(ConnCheckNow.last.value, isNull, reason: 'حسابٌ آخر ⇒ تُمسح');
    });

    test('مزوّدٌ بلا عناوين أجهزة ⇒ رسالةٌ لا VPN ولا رفع', () async {
      DeviceWarmService.debugCheckNow = (_) async => (onNet: false, subs: <Subscriber>[], probed: 0, reason: 'no_devices');
      final r = await ConnCheckNow.run();
      expect((r.ok, r.via), (false, 'none'));
      expect(server.calls('POST', '/api/v2/conn-vpn/check-now'), isEmpty);
    });
  });

  group('الشاشة', () {
    late SimServer server;
    setUpAll(simSetUpAll);
    setUp(() async {
      server = await simSetUp(secure: {'auth.admin_id': '2', 'auth.admin_username': 'owner'});
      ConnCheckNow.debugReset();
      DeviceWarmService.debugReset();
      ConnectionAutoApi.debugReset();
      server.reply('GET', '/api/v2/connection-alerts/auto', 200, _status());
      server.reply('GET', '/api/v2/connection-alerts/queue', 200, {'success': true, 'data': {'available': true, 'items': []}});
      server.reply('GET', '/api/v2/connection-alerts/log', 200, {'success': true, 'data': {'available': true, 'items': []}});
    });
    tearDown(DeviceWarmService.debugReset);

    testWidgets('«افحص الآن»: معطَّلٌ وهو يفحص (النقر المكرّر لا يبدأ غيره)، ثمّ النتيجة ظاهرة', (t) async {
      DeviceWarmService.debugCheckNow = (_) async => (onNet: false, subs: <Subscriber>[], probed: 0, reason: 'off_net');
      var polls = 0;
      server.reply('POST', '/api/v2/conn-vpn/check-now', 200, {'success': true, 'data': {'check_id': 'c9', 'state': 'running'}});
      server.on('GET', '/api/v2/conn-vpn/check-now/c9', (_) {
        polls += 1;
        return SimReply(200, {
          'success': true,
          'data': polls < 2
              ? {'state': 'running', 'result': null}
              : {'state': 'done', 'result': {'ok': true, 'message': 'فُحص عبر VPN ✓ — قُرئ 3 من 4 متّصلاً — لا مشاكل'}},
        });
      });
      ConnectionAutoApi.status.value = ConnAutoStatus.fromJson(Map<String, dynamic>.from(_status()['data'] as Map));
      await pumpSim(t, _v, home: (_) => const ConnAutoQueueScreen());
      await t.pumpAndSettle();
      expect(find.text('افحص الآن'), findsOneWidget);
      await t.tap(find.text('افحص الآن'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 50));
      expect(find.text('يفحص…'), findsOneWidget);
      // النقر المكرّر والزرّ معطَّل لا يبدأ فحصاً ثانياً
      await t.tap(find.text('يفحص…'), warnIfMissed: false);
      await t.pump();
      expect(find.textContaining('يفحص عبر VPN'), findsOneWidget);
      await t.pump(const Duration(seconds: 3));
      await t.pumpAndSettle();
      expect(find.textContaining('قُرئ 3 من 4'), findsOneWidget);
      expect(find.text('افحص الآن'), findsOneWidget);
      expect(server.calls('POST', '/api/v2/conn-vpn/check-now'), hasLength(1));
      await simDrain(t);
    });
  });
}
