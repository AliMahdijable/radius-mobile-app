// قارئ أطراف اللنكات لـ«الترابط» ([TowerLinkProbe]) — بقواعد البرج نفسها، وبدرس تنبيهات الأجهزة (المالك ١١ نوفمبر:
// «تنبيهات الاجهزه كذلك غير دقيقه» — جهازٌ يعمل قيل عنه طافٍ من حكمٍ قديم): «لا يردّ» بفحصٍ حديثٍ نجريه نحن وحده، والرقم
// القديم ليس رقماً، وخارج الشبكة لا يُقال شيء. الشبكة كلّها مزيّفة.
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/api/device_reach.dart';
import 'package:rad_mysvcs/api/mikrotik_api.dart';
import 'package:rad_mysvcs/api/network_devices_api.dart';
import 'package:rad_mysvcs/models/network_device.dart';
import 'package:rad_mysvcs/screens/network_devices/tower/tower_link_probe.dart';
import 'package:rad_mysvcs/services/agent_net_presence.dart';
import 'package:rad_mysvcs/services/deep_probe_scheduler.dart';
import 'package:rad_mysvcs/services/device_read_health.dart';
import 'package:rad_mysvcs/services/device_stats_cache.dart';
import 'package:rad_mysvcs/services/device_sweep_coordinator.dart';

import 'visual_perm/visual_perm_harness.dart';

NetworkDevice _dev(int id, {String status = 'online', int region = 1}) => NetworkDevice(
      id: id,
      adminId: '2',
      regionId: region,
      name: 'لنك $id',
      type: 'link',
      brand: 'mikrotik',
      model: 'LHG 5 ac',
      ip: '10.0.0.$id',
      port: 80,
      apiPort: 8728,
      protocol: 'api',
      hasCredentials: true,
      lastStatus: status,
      lastProbedAt: DateTime(2026, 11, 10, 21),
      createdAt: DateTime(2026, 10, 1),
    );

class _Api implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? body, Future<void>? cancel) async {
    Object data = {'success': true, 'data': []};
    if (o.uri.path.endsWith('/credentials')) {
      data = {'success': true, 'credentials': {'user': 'admin', 'pass': 'x'}};
    }
    return ResponseBody.fromString(jsonEncode(data), 200, headers: {Headers.contentTypeHeader: ['application/json']});
  }

  @override
  void close({bool force = false}) {}
}

MikrotikStats _stats() => const MikrotikStats(
      cpuLoad: 5,
      memUsedPercent: 37,
      memTotalBytes: 64 << 20,
      memFreeBytes: 40 << 20,
      uptime: '9w4d3h12m5s',
      version: '6.49.19',
      boardName: 'LHG 5 ac',
      architectureName: 'arm',
      cpuCount: 4,
      cpuFrequencyMhz: 716,
      temperature: 38,
      voltage: 23.9,
      interfaces: [
        MikrotikInterface(name: 'ether1', type: 'ether', running: true, disabled: false, rxBytes: 1, txBytes: 1),
        MikrotikInterface(name: 'wlan1', type: 'wlan', running: true, disabled: false, rxBytes: 1, txBytes: 1),
      ],
      pppActiveCount: 0,
      wirelessInterfaces: [
        MikrotikWireless(name: 'wlan1', ssid: 'L', mode: 'station', band: '5ghz-a/n/ac', frequency: 5745, channelWidth: 40, txPower: 24, disabled: false, running: true),
      ],
      wirelessClients: [
        MikrotikWirelessClient(mac: 'AA:BB:CC:00:00:01', iface: 'wlan1', signalStrength: -58, txSignalStrength: -60, signalToNoise: 38, txCcq: 96, rxCcq: 95, txRate: 300, rxRate: 300, uptime: 9000, comment: ''),
      ],
    );

void main() {
  setUpAll(visualSetUpAll);

  late DateTime now;
  late int reads;
  late bool readsFail;
  late Set<String> pingable;
  late List<String> reachCalls;

  Future<void> boot() async {
    await visualSetUp(s1bSasOwner);
    ApiClient.dio.httpClientAdapter = _Api();
    NetworkDevicesApi.invalidateCredentialsCache();
    DeviceStatsCache.instance.clear();
    DeepProbeScheduler.instance.resetForTest();
    DeviceReach.resetForTest();
    DeviceReadHealth.instance.debugReset();
    AgentNetPresence.reset();
    now = DateTime.now();
    DeviceReadHealth.clock = () => now;
    reads = 0;
    readsFail = false;
    pingable = {};
    reachCalls = [];
    NetworkDevicesApi.debugIcmpUsable = true;
    NetworkDevicesApi.debugService = (_) async => (status: 'offline', responseMs: null, packetLoss: 100.0);
    NetworkDevicesApi.icmpProbe = (ip, n) async {
      reachCalls.add(ip);
      return pingable.contains(ip) ? (status: 'online', responseMs: 7, packetLoss: 0.0) : (status: 'offline', responseMs: null, packetLoss: 100.0);
    };
    DeviceReach.debugConnect = (host, port, timeout) async => (port: port, reply: PortReply.silent, ms: null);
    MikrotikApi.debugFetch = () async {
      reads++;
      if (readsFail) throw MikrotikException('انتهت مهلة الاتّصال بالجهاز', code: 'timeout');
      return _stats();
    };
    addTearDown(() async {
      MikrotikApi.debugFetch = null;
      NetworkDevicesApi.debugIcmpUsable = null;
      NetworkDevicesApi.debugService = null;
      DeviceReach.resetForTest();
      DeviceReadHealth.instance.debugReset();
      DeviceReadHealth.clock = DateTime.now;
      DeepProbeScheduler.instance.resetForTest();
      DeviceStatsCache.instance.clear();
      AgentNetPresence.reset();
      if (DeviceSweep.suspended) DeviceSweep.release();
      await visualTearDown();
    });
  }

  /// يدير الزمن الوهميّ (المؤقّتات) والحقيقيّ (سلسلة الطلب) معاً.
  Future<void> run(WidgetTester t, {int seconds = 2}) async {
    for (var i = 0; i < seconds * 10; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 4)));
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('أطراف اللنكات وحدها تُقرأ كلّ دورة — وما عداها لا يُفتح له اتّصال', (t) async {
    await boot();
    final p = TowerLinkProbe();
    var notified = 0;
    p.addListener(() => notified++);
    p.setDevices(ends: [_dev(11), _dev(21, region: 2)], others: [_dev(31, region: 3), _dev(32, region: 3)]);
    p.start();
    await run(t);
    expect(reads, 2);
    expect(p.readingOf(11), isNotNull);
    expect(p.readingOf(21)!.isStation, isTrue);
    expect(p.readingOf(31), isNull);
    expect([p.isDown(11), p.isDown(21), p.needsSettings(11)], [false, false, false]);
    expect(notified, greaterThan(0), reason: 'الشاشة تُبلَّغ');
    // السرعة فرق عدّادين: أوّل قراءةٍ بلا سرعة ⇒ تُعاد مرّةً بعد ثوانٍ، لا بعد ٢٠ث
    await run(t, seconds: 4);
    expect(reads, 4, reason: 'قراءة السرعة الأولى بعد ~٤ث');
    // ثمّ الدورة كلّ ٢٠ث
    now = now.add(const Duration(seconds: 21));
    await run(t, seconds: 16);
    expect(reads, 6);
    // لقطة حال الأجهزة تتجدّد (القائمة نفسها) ⇒ لا دورة زائدة
    p.setDevices(ends: [_dev(11), _dev(21, region: 2)], others: [_dev(31, region: 3)]);
    await run(t, seconds: 1);
    expect(reads, 6);
    p.dispose();
    await t.pump(const Duration(seconds: 25));
    expect(reads, 6, reason: 'بعد الإتلاف لا قراءة');
  });

  testWidgets('🚨 قراءةٌ تفشل: لا «واقع» قبل حكم الفحص؛ لا يردّ ⇒ «واقع»، ويردّ ⇒ إعداداته — والرقم السابق لا يبقى معروضاً', (t) async {
    await boot();
    final p = TowerLinkProbe();
    p.setDevices(ends: [_dev(11), _dev(21, region: 2)]);
    p.start();
    await run(t);
    expect(p.readingOf(11), isNotNull);

    readsFail = true;
    pingable = {'10.0.0.11'}; // 11 يردّ (إعداداته)، و21 لا يردّ
    now = now.add(const Duration(seconds: 21));
    await run(t, seconds: 22);
    expect(reachCalls.toSet(), {'10.0.0.11', '10.0.0.21'}, reason: 'قراءةٌ فشلت ⇒ فحص وصولٍ خفيف');
    expect([p.isDown(11), p.needsSettings(11)], [false, true]);
    expect([p.isDown(21), p.needsSettings(21)], [true, false]);
    expect([p.readingOf(11), p.readingOf(21)], [null, null], reason: 'رقمٌ من قبل الفشل ليس رقماً');

    // 21 عاد: الفحص التالي (~٣٠ث) يراه فيُقرأ فوراً
    readsFail = false;
    pingable = {'10.0.0.11', '10.0.0.21'};
    now = now.add(const Duration(seconds: 31));
    await run(t, seconds: 22);
    expect(p.isDown(21), isFalse);
    expect(p.readingOf(21), isNotNull);
    expect(p.needsSettings(11), isFalse);
    p.dispose();
  });

  testWidgets('🚨 لقطة «لا يردّ» من السجلّ ليست حكماً: لا «واقع» حتى يجيب فحصنا — ويردّ ⇒ يُقرأ', (t) async {
    await boot();
    final p = TowerLinkProbe();
    pingable = {'10.0.0.21'};
    p.setDevices(ends: [_dev(11, status: 'offline'), _dev(21, status: 'offline', region: 2)]);
    expect([p.isDown(11), p.isDown(21)], [false, false], reason: 'قبل أيّ فحص: لا يُقال شيء');
    p.start();
    await run(t);
    expect(reachCalls.toSet(), {'10.0.0.11', '10.0.0.21'});
    expect(p.isDown(11), isTrue, reason: 'فحصنا قال لا يردّ');
    expect(p.isDown(21), isFalse, reason: 'اللقطة كانت قديمة — يردّ');
    expect(p.readingOf(21), isNotNull, reason: 'وعاد يُقرأ');
    // حكمٌ يقدُم بلا فحصٍ يجدّده (فحصٌ شامل يوقف الدورات) يسقط — لا «واقع» من حكمٍ قديم
    DeviceSweep.acquire();
    now = now.add(const Duration(seconds: 120));
    await run(t, seconds: 1);
    expect(p.isDown(11), isFalse);
    DeviceSweep.release();
    p.dispose();
  });

  testWidgets('رقمٌ قديم ليس رقماً: قراءةٌ لم تتجدّد (الدورات موقوفة) تختفي بعد دقيقتين', (t) async {
    await boot();
    final p = TowerLinkProbe();
    p.setDevices(ends: [_dev(11)]);
    p.start();
    await run(t);
    expect(p.readingOf(11), isNotNull);
    DeviceSweep.acquire(); // «الفحص الشامل» يجري ⇒ لا قراءات مفصّلة
    final before = reads;
    now = now.add(TowerLinkProbe.freshFor + const Duration(seconds: 5));
    await run(t, seconds: 21);
    expect(reads, before, reason: 'لا جلسة والفحص الشامل يجري');
    expect(p.readingOf(11), isNull);
    DeviceSweep.release();
    p.dispose();
  });

  testWidgets('خارج شبكة الأجهزة (بلا وضع VPN): لا جلسة ولا فحص ولا «واقع»', (t) async {
    await boot();
    AgentNetPresence.debugSet(NetPresence.off);
    AgentNetPresence.now = () => now;
    addTearDown(() => AgentNetPresence.now = DateTime.now);
    final p = TowerLinkProbe();
    p.setDevices(ends: [_dev(11), _dev(21, status: 'offline', region: 2)]);
    p.start();
    await run(t);
    expect(p.offNetwork, isTrue);
    expect(reads, 0);
    expect(reachCalls, isEmpty);
    expect([p.isDown(11), p.isDown(21)], [false, false]);
    p.dispose();
  });

  testWidgets('صحنٌ غير مربوط يُقرأ مرّةً واحدة (لاقتراح الوصلات) لا كلّ دورة', (t) async {
    await boot();
    final p = TowerLinkProbe();
    p.start();
    p.setDevices(ends: [_dev(11)], others: [_dev(31, region: 3)], scanOnce: [_dev(31, region: 3)]);
    await run(t);
    expect(reads, 2);
    expect(p.known.keys.toSet(), {11, 31});
    expect(p.readingOf(31), isNotNull);
    now = now.add(const Duration(seconds: 21));
    await run(t, seconds: 21);
    expect(reads, 4, reason: 'الطرف وحده بعدها: قراءة سرعته الأولى (~٤ث) ثمّ دورة ٢٠ث — الصحن لا يُعاد');
    p.setDevices(ends: [_dev(11)], others: [_dev(31, region: 3)], scanOnce: [_dev(31, region: 3)]);
    await run(t, seconds: 1);
    expect(reads, 4, reason: 'لا يُعاد مسحه');
    p.dispose();
  });
}
