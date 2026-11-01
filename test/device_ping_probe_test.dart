import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/device_reach.dart';
import 'package:rad_mysvcs/api/network_devices_api.dart';
import 'package:rad_mysvcs/models/network_device.dart';

/// ٣٠ أكتوبر — المالك (زرّ «فحص الآن (ping)» على أولتي بـSNMP:444): «ان كان الجهاز خطا معلومات او اي شي ثاني مفترض ان يرد فحص
/// البنك لان رح يربك الوكيل ان الجهاز فاصل». «متّصل» = يردّ على الشبكة (خدمته أو ping حقيقيّ)، والخدمة تُقال وحدها (serviceOk).
NetworkDevice _dev(int port, {String brand = 'ubnt', String? protocol}) => NetworkDevice.fromJson({
      'id': 1,
      'admin_id': '1',
      'name': 'جهاز',
      'type': 'switch',
      'brand': brand,
      'ip': '127.0.0.1',
      'port': port,
      'api_port': port,
      'protocol': protocol,
      'has_credentials': false,
      'last_status': 'unknown',
      'created_at': '2026-10-30T00:00:00Z',
    });

void main() {
  final pings = <int>[];
  Probe3 pingReply = (status: 'online', responseMs: 12, packetLoss: 0.0);

  // منافذ الإدارة الشائعة (١ نوفمبر): لا تُطرق شبكة الجهاز الحقيقيّة في الاختبار — صمتٌ ما لم يقل الاختبار غيره.
  final knocked = <int>[];
  PortReply Function(int port) sweepReply = (_) => PortReply.silent;

  setUp(() {
    pings.clear();
    knocked.clear();
    sweepReply = (_) => PortReply.silent;
    pingReply = (status: 'online', responseMs: 12, packetLoss: 0.0);
    NetworkDevicesApi.debugIcmpUsable = true;
    NetworkDevicesApi.icmpProbe = (ip, count) async {
      pings.add(count);
      return pingReply;
    };
    DeviceReach.resetForTest();
    DeviceReach.debugConnect = (host, port, timeout) async {
      if (host == DeviceReach.canaryHost) return (port: port, reply: PortReply.silent, ms: null);
      knocked.add(port);
      final r = sweepReply(port);
      return (port: port, reply: r, ms: r == PortReply.silent ? null : 7);
    };
  });
  tearDown(() {
    NetworkDevicesApi.debugIcmpUsable = null;
    NetworkDevicesApi.debugService = null;
    DeviceReach.resetForTest();
  });

  Future<int> closedPort() async {
    final s = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final p = s.port;
    await s.close();
    return p;
  }

  group('combineProbes', () {
    test('ping يردّ والخدمة لا ⇒ متّصل بزمن الـping، وserviceOk=false', () {
      final r = NetworkDevicesApi.combineProbes((status: 'online', responseMs: 9, packetLoss: 0.0), (status: 'offline', responseMs: null, packetLoss: 100.0));
      expect([r.status, r.responseMs, r.packetLoss, r.serviceOk], ['online', 9, 0.0, false]);
    });
    test('ping محجوب (جدار) والخدمة تردّ ⇒ متّصل بلا «فقدان 100%»', () {
      final r = NetworkDevicesApi.combineProbes((status: 'offline', responseMs: null, packetLoss: 100.0), (status: 'online', responseMs: 30, packetLoss: 0.0));
      expect([r.status, r.responseMs, r.packetLoss, r.serviceOk], ['online', 30, null, true]);
    });
    test('لا هذا ولا ذاك ⇒ مفصول', () {
      final r = NetworkDevicesApi.combineProbes((status: 'offline', responseMs: null, packetLoss: 100.0), (status: 'offline', responseMs: null, packetLoss: 100.0));
      expect([r.status, r.packetLoss, r.serviceOk], ['offline', 100.0, false]);
    });
  });

  group('probeDevice', () {
    test('🚨 منفذٌ خطأ والجهاز يردّ على ping ⇒ «متّصل» لا «مفصول 100%» — الزرّ: ٣ حزم مع الخدمة معاً', () async {
      final r = await NetworkDevicesApi.probeDevice(_dev(await closedPort()), ping: true);
      expect([r.status, r.responseMs, r.packetLoss, r.serviceOk], ['online', 12, 0.0, false]);
      expect(pings, [3]);
    });

    test('الدوريّ: الخدمة تردّ ⇒ متّصل بلا ping (أخفّ)؛ لا تردّ ⇒ حزمة ping واحدة', () async {
      DeviceReach.debugConnect = null; // اتّصالٌ حقيقيّ بخادمٍ محلّيّ — منفذ الخدمة نفسه.
      final srv = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(srv.close);
      srv.listen((s) => s.destroy());
      var r = await NetworkDevicesApi.probeDevice(_dev(srv.port));
      expect([r.status, r.serviceOk], ['online', true]);
      expect(pings, isEmpty);
      r = await NetworkDevicesApi.probeDevice(_dev(await closedPort()));
      expect([r.status, r.serviceOk], ['online', false]);
      expect(pings, [1]);
    });

    test('مطفأٌ فعلاً (لا ping ولا خدمة ولا منفذ) ⇒ مفصول 100%', () async {
      pingReply = (status: 'offline', responseMs: null, packetLoss: 100.0);
      final r = await NetworkDevicesApi.probeDevice(_dev(await closedPort()), ping: true);
      expect([r.status, r.packetLoss, r.serviceOk], ['offline', 100.0, false]);
      expect(knocked, isNotEmpty, reason: 'سُئلت منافذ الإدارة الشائعة قبل الحكم بـ«مفصول»');
    });

    test('iOS (لا ping موثوق) ⇒ بلا ping؛ لا يردّ شيء ⇒ مفصول بلا «فقدان 100%» (لم تُرسل حزمة)', () async {
      NetworkDevicesApi.debugIcmpUsable = false;
      final r = await NetworkDevicesApi.probeDevice(_dev(await closedPort()), ping: true);
      expect([r.status, r.serviceOk, r.packetLoss], ['offline', false, null]);
      expect(pings, isEmpty);
    });

    test('🚨 iOS والمنفذ المسجّل خطأ وWinbox يردّ ⇒ «متّصل» بزمن الاتّصال (١ نوفمبر: «يرد بنك» ولو مضيوف غلط)', () async {
      NetworkDevicesApi.debugIcmpUsable = false;
      // خدمته المسجّلة (API:8729) لا تردّ — مزيّفةً، فلا يطرق `mikrotikProbe` منافذ الجهاز الحقيقيّ.
      NetworkDevicesApi.debugService = (_) async => (status: 'offline', responseMs: null, packetLoss: 100.0);
      sweepReply = (p) => p == 8291 ? PortReply.open : PortReply.silent;
      final r = await NetworkDevicesApi.probeDevice(_dev(8729, brand: 'mikrotik', protocol: 'api'), ping: true);
      expect([r.status, r.responseMs, r.packetLoss, r.serviceOk], ['online', 7, null, false]);
      expect(pings, isEmpty);
    });
  });
}
