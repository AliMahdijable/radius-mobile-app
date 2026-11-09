import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/api/device_reach.dart';
import 'package:rad_mysvcs/api/mikrotik_api.dart';
import 'package:rad_mysvcs/api/network_devices_api.dart';
import 'package:rad_mysvcs/core/util/bidi.dart';
import 'package:rad_mysvcs/models/network_device.dart';
import 'package:rad_mysvcs/screens/network_devices/tower/tower_logic.dart';
import 'package:rad_mysvcs/screens/network_devices/tower/tower_screen.dart';
import 'package:rad_mysvcs/services/deep_probe_scheduler.dart';
import 'package:rad_mysvcs/services/device_read_health.dart';
import 'package:rad_mysvcs/services/device_stats_cache.dart';
import 'package:rad_mysvcs/services/device_sweep_coordinator.dart';
import 'package:rad_mysvcs/theme/typography.dart';

import 'visual_perm/visual_perm_harness.dart';

/// المراجعة (١ نوفمبر): «يردّ» لا يُقال إلّا بحكمٍ حديث. البرج لا يفحص الوصول من نفسه، ولقطة السجلّ من لحظة فتحه — فقراءةٌ
/// تفشل لجهازٍ لقطته «متّصل» (أو «unknown») كانت تُقال «يردّ — تأكّد من الإعدادات» وتُعدّ «يردّ» والجهاز مطفأ.
/// الشبكة كلّها مزيّفة.
NetworkDevice _dev(int id, String name, String type, String ip, String status, {String model = 'BaseBox 5'}) => NetworkDevice(
      id: id,
      adminId: '2',
      regionId: 5,
      name: name,
      type: type,
      brand: 'mikrotik',
      model: model,
      ip: ip,
      port: 80,
      apiPort: 8728,
      protocol: 'api',
      hasCredentials: true,
      lastStatus: status,
      // لقطةٌ قديمة من الخادم — قبل فتح البرج بساعات.
      lastProbedAt: DateTime(2026, 10, 31, 21),
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

void main() {
  final t0 = DateTime(2026, 11, 1, 10);
  Duration s(int n) => Duration(seconds: n);

  group('TowerLive + ReachVerdict (خالصة)', () {
    test('🚨 قراءةٌ تفشل بلا فحصٍ بعدها ⇒ «تعذّر الاتّصال» خارج «يردّ» — لقطة «متّصل» قديمة أو «unknown» لا تكفي', () {
      for (final status in ['online', 'unknown']) {
        final live = TowerLive.of(lastStatus: status, failedSince: t0, now: t0.add(s(5)));
        expect(live, TowerLive.failing, reason: status);
        expect(live.answers, isFalse, reason: status);
      }
    });

    test('فحصٌ «يردّ» من قبل بدء الفشل لا يُصدَّق', () {
      final live = TowerLive.of(
        lastStatus: 'online',
        failedSince: t0,
        reach: (reachable: true, at: t0.subtract(s(10))),
        now: t0.add(s(1)),
      );
      expect(live, TowerLive.failing);
    });

    test('فحصٌ بعد بدء الفشل: يردّ ⇒ «تحقّق من الإعدادات» ويُعدّ؛ لا يردّ ⇒ «لا يردّ» خارج العدّ', () {
      final ok = TowerLive.of(lastStatus: 'online', failedSince: t0, reach: (reachable: true, at: t0.add(s(2))), now: t0.add(s(3)));
      expect(ok, TowerLive.settings);
      expect(ok.answers, isTrue);
      final no = TowerLive.of(lastStatus: 'offline', failedSince: t0, reach: (reachable: false, at: t0.add(s(2))), now: t0.add(s(3)));
      expect(no, TowerLive.down);
      expect(no.answers, isFalse);
    });

    test('حكمٌ مضى عليه أكثر من validFor يسقط — لا «يردّ» قديم إن توقّف الفحص', () {
      final live = TowerLive.of(
        lastStatus: 'online',
        failedSince: t0,
        reach: (reachable: true, at: t0.add(s(1))),
        now: t0.add(s(1)).add(ReachVerdict.validFor).add(s(1)),
      );
      expect(live, TowerLive.failing);
    });

    test('بلا فشل: «offline» ⇒ لا يردّ، وغيره يُعدّ', () {
      expect(TowerLive.of(lastStatus: 'offline', now: t0), TowerLive.down);
      expect(TowerLive.of(lastStatus: 'unknown', now: t0), TowerLive.ok);
      expect(TowerLive.of(lastStatus: 'online', now: t0).answers, isTrue);
    });

    test('ReachVerdict.due: لا حكم، أو حكمٌ قبل الفشل، أو مضت ٣٠ث', () {
      expect(ReachVerdict.due(checkedAt: null, now: t0), isTrue);
      expect(ReachVerdict.due(checkedAt: t0, since: t0.add(s(1)), now: t0.add(s(2))), isTrue);
      expect(ReachVerdict.due(checkedAt: t0, since: t0, now: t0.add(s(29))), isFalse);
      expect(ReachVerdict.due(checkedAt: t0, since: t0, now: t0.add(s(30))), isTrue);
      expect(ReachVerdict.due(checkedAt: t0, now: t0.add(s(10))), isFalse, reason: 'جهازٌ لا يردّ بلا فشل قراءة: بالعمر وحده');
    });
  });

  group('DeviceReadHealth — بدء الفشل', () {
    setUp(DeviceReadHealth.instance.debugReset);
    tearDown(DeviceReadHealth.instance.debugReset);

    test('يبدأ بأوّل قراءةٍ فاشلة، وتغيّر الرسالة لا يبدّله، والنجاح يمسحه، وكلّ قراءةٍ فاشلة تُعلِم', () async {
      var now = t0;
      DeviceReadHealth.clock = () => now;
      final h = DeviceReadHealth.instance;
      var notified = 0;
      void count() => notified++;
      h.changes.addListener(count);
      addTearDown(() => h.changes.removeListener(count));

      h.failed(7, 'انتهت المهلة');
      now = now.add(s(8));
      h.failed(7, 'انتهت المهلة');
      now = now.add(s(8));
      h.failed(7, 'تعذّرت القراءة: 192.0.2.1:8728 (3)');
      await Future<void>.delayed(Duration.zero);
      expect(h.failureOf(7), (error: 'تعذّرت القراءة: 192.0.2.1:8728 (3)', since: t0, at: t0.add(s(16))));
      expect(notified, 3, reason: 'كلّ قراءةٍ فاشلة حدث — شاشة الجهاز تعيد فحصها إن قدُم');

      h.ok(7);
      await Future<void>.delayed(Duration.zero);
      expect(h.failureOf(7), isNull);
      expect(notified, 4);

      now = now.add(s(5));
      h.failed(7, 'انتهت المهلة');
      expect(h.failureOf(7)?.since, now, reason: 'فشلٌ جديد بعد نجاح');

      now = now.add(DeviceReadHealth.freshFor).add(s(1));
      expect(h.failureOf(7), isNull, reason: 'قديم — لا يُقال');
      h.failed(7, 'انتهت المهلة');
      expect(h.failureOf(7)?.since, now, reason: 'بعد أن قدُم الفشل السابق يبدأ من جديد');
    });
  });

  group('البرج', () {
    setUpAll(visualSetUpAll);

    late DateTime now;
    late Set<String> pingable;
    late List<String> reachCalls;
    Completer<void>? gate;

    Future<void> setUpTower(WidgetTester t) async {
      await visualSetUp(s1bSasOwner);
      ApiClient.dio.httpClientAdapter = _Api();
      NetworkDevicesApi.invalidateCredentialsCache();
      DeviceStatsCache.instance.clear();
      DeepProbeScheduler.instance.resetForTest();
      DeviceReach.resetForTest();
      DeviceReadHealth.instance.debugReset();
      now = t0;
      DeviceReadHealth.clock = () => now;
      pingable = {};
      reachCalls = [];
      gate = null;
      // أندرويد/الماك/ويندوز: الفحص الخفيف = خدمته ثمّ حزمة ping واحدة.
      NetworkDevicesApi.debugIcmpUsable = true;
      NetworkDevicesApi.debugService = (_) async => (status: 'offline', responseMs: null, packetLoss: 100.0);
      NetworkDevicesApi.icmpProbe = (ip, n) async {
        reachCalls.add(ip);
        final g = gate;
        if (g != null) await g.future;
        return pingable.contains(ip)
            ? (status: 'online', responseMs: 9, packetLoss: 0.0)
            : (status: 'offline', responseMs: null, packetLoss: 100.0);
      };
      DeviceReach.debugConnect = (host, port, timeout) async => (port: port, reply: PortReply.silent, ms: null);
      // كلّ قراءة تفشل — الجهاز مطفأ، أو كلمة مروره خطأ.
      MikrotikApi.debugFetch = () async => throw MikrotikException('انتهت مهلة الاتّصال بالجهاز', code: 'timeout');
      addTearDown(() async {
        MikrotikApi.debugFetch = null;
        NetworkDevicesApi.debugIcmpUsable = null;
        NetworkDevicesApi.debugService = null;
        DeviceReach.resetForTest();
        DeviceReadHealth.instance.debugReset();
        DeepProbeScheduler.instance.resetForTest();
        DeviceStatsCache.instance.clear();
        await visualTearDown();
      });
    }

    Future<void> pumpTower(WidgetTester t, List<NetworkDevice> devices) async {
      t.view.physicalSize = const Size(390, 1600) * 2;
      t.view.devicePixelRatio = 2;
      addTearDown(t.view.reset);
      await t.pumpWidget(MaterialApp(
        theme: ThemeData(fontFamily: AppType.family),
        home: MediaQuery(
          data: const MediaQueryData(size: Size(390, 1600), disableAnimations: true),
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: TowerScreen(regionId: 5, regionName: 'برج المعامل', devices: devices),
          ),
        ),
      ));
    }

    Future<void> settle(WidgetTester t, [Duration d = const Duration(seconds: 3)]) async {
      for (var x = Duration.zero; x < d; x += const Duration(milliseconds: 100)) {
        await t.pump(const Duration(milliseconds: 100));
      }
    }

    Future<void> finish(WidgetTester t) async {
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 30));
    }

    final devices = [
      _dev(1, 'سكتر 1', 'sector', '10.0.0.1', 'online'),
      _dev(2, 'راوتر الكابينة', 'router', '10.0.0.2', 'unknown', model: 'CCR1009-7G-1C-1S+'),
    ];

    testWidgets('🚨 لقطة «متّصل» قديمة و«unknown» وقراءةٌ تفشل والجهاز لا يردّ ⇒ لا «تحقّق من الإعدادات» ولا عدّ في «يردّ»',
        (t) async {
      await setUpTower(t);
      await pumpTower(t, devices);
      await settle(t);
      expect(find.text('تحقّق من الإعدادات'), findsNothing);
      expect(find.text('يردّ — تأكّد من إعدادات الجهاز'), findsNothing);
      expect(find.text('2 جهازاً · 0 يردّ'), findsOneWidget);
      expect(find.text(iso('0/2')), findsOneWidget, reason: 'خانة «الأجهزة»');
      expect(reachCalls.toSet(), {'10.0.0.1', '10.0.0.2'}, reason: 'قراءةٌ فشلت ⇒ البرج يفحص وصوله');
      expect(find.text('لا يردّ'), findsWidgets, reason: 'البطاقة وصفّ الكابينة');

      // ٣٠ث تمرّ والجهازان يعودان (كلمة مرورهما ما زالت خطأ): الجولة التالية تفحص وصولهما من جديد فيُعدّان.
      final asked = reachCalls.length;
      pingable = {'10.0.0.1', '10.0.0.2'};
      now = now.add(const Duration(seconds: 31));
      await settle(t, const Duration(seconds: 21));
      expect(reachCalls.length, greaterThan(asked), reason: 'لا يبقى «لا يردّ» أبداً: فحصٌ خفيف كلّ ~٣٠ث');
      expect(find.text('2 جهازاً · 2 يردّ'), findsOneWidget);
      expect(find.text('يردّ — تأكّد من إعدادات الجهاز'), findsOneWidget, reason: 'صفّ الكابينة');
      await finish(t);
    });

    testWidgets('قبل ردّ الفحص «تعذّر الاتّصال» خارج العدّ؛ يردّ ⇒ «تحقّق من الإعدادات» ويُعدّ «يردّ»', (t) async {
      await setUpTower(t);
      pingable = {'10.0.0.1', '10.0.0.2'};
      final g = gate = Completer<void>();
      await pumpTower(t, devices);
      await settle(t);
      expect(reachCalls.toSet(), {'10.0.0.1', '10.0.0.2'});
      expect(find.text('2 جهازاً · 0 يردّ'), findsOneWidget, reason: 'الفحص لم يجب بعد — لقطة السجلّ لا تقول «يردّ»');
      expect(find.text('تعذّر الاتّصال'), findsWidgets);
      expect(find.text('تحقّق من الإعدادات'), findsNothing);

      g.complete();
      await settle(t);
      expect(find.text('2 جهازاً · 2 يردّ'), findsOneWidget);
      expect(find.text('تعذّر الاتّصال'), findsNothing);
      expect(find.text('تحقّق من الإعدادات'), findsOneWidget, reason: 'بطاقة الجهاز المختار');
      expect(find.text('يردّ — تأكّد من إعدادات الجهاز'), findsOneWidget, reason: 'صفّ الكابينة');
      await finish(t);
    });

    testWidgets('المراجعة الثانية: «الفحص الشامل» يجري ⇒ البرج لا يفتح قراءات ٢٠ث المفصّلة على سكتراته؛ وبعده يعود', (t) async {
      await setUpTower(t);
      var reads = 0;
      MikrotikApi.debugFetch = () async {
        reads++;
        throw MikrotikException('انتهت مهلة الاتّصال بالجهاز', code: 'timeout');
      };
      DeviceSweep.acquire(); // فحصٌ شامل (صوتيّ أو فوق القسم على الحاسبة) يقرأ السكترات نفسها
      addTearDown(() {
        if (DeviceSweep.suspended) DeviceSweep.release();
      });
      await pumpTower(t, [_dev(1, 'سكتر 1', 'sector', '10.0.0.1', 'online')]);
      await settle(t, const Duration(seconds: 65));
      expect(reads, 0, reason: 'لا جلسة قراءةٍ مفصّلة والفحص يجري');
      DeviceSweep.release();
      await settle(t, const Duration(seconds: 25));
      expect(reads, greaterThan(0), reason: 'الجولة التالية بعده تقرأ');
      await finish(t);
    });
  });
}
