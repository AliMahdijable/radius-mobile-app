import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
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

  setUp(() {
    pings.clear();
    pingReply = (status: 'online', responseMs: 12, packetLoss: 0.0);
    NetworkDevicesApi.debugIcmpUsable = true;
    NetworkDevicesApi.icmpProbe = (ip, count) async {
      pings.add(count);
      return pingReply;
    };
  });
  tearDown(() => NetworkDevicesApi.debugIcmpUsable = null);

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

    test('مطفأٌ فعلاً (لا ping ولا خدمة) ⇒ مفصول 100%', () async {
      pingReply = (status: 'offline', responseMs: null, packetLoss: 100.0);
      final r = await NetworkDevicesApi.probeDevice(_dev(await closedPort()), ping: true);
      expect([r.status, r.packetLoss, r.serviceOk], ['offline', 100.0, false]);
    });

    test('iOS (لا ping موثوق) ⇒ الخدمة وحدها كما كان، بلا ping', () async {
      NetworkDevicesApi.debugIcmpUsable = false;
      final r = await NetworkDevicesApi.probeDevice(_dev(await closedPort()), ping: true);
      expect([r.status, r.serviceOk], ['offline', false]);
      expect(pings, isEmpty);
    });
  });
}
