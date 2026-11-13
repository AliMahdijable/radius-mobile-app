import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/network_devices_api.dart';
import 'package:rad_mysvcs/core/net/device_net.dart';
import 'package:rad_mysvcs/core/net/vpn_pipe.dart';

import 'vpn_pipe_test.dart' show FakePipes;

/// طابور ممرّات «وضع VPN» وفحص النطاق عبره — المالك ١٤ نوفمبر: «فحص الأجهزة من ينقر ع الدرع يفحص يوصل للنصّ مرّات ويفصل»
/// و«بحث النطاق… ماكو يشتغل عبر vpn من انقر درع».
///
/// الخادم يسمح للوكيل بـ٢٤ ممرّاً معاً ويردّ فوقها «مشغول» (٥٢ رفضاً بسجلّه يومها، كلّها على الفتح): الفحص الشامل مع جولة القسم
/// كانا يتجاوزانها بمنتصف الفحص. وفحص النطاق كان يفتح مقابسه خامّةً فلا يمرّ بالممرّ أصلاً.
class _Pipes extends FakePipes {
  _Pipes(super.target);

  /// «مشغول» من الخادم لأوّل N فتحاً.
  int busyFirst = 0;
  int attempts = 0;
  final denied = <String>{};
  final tries = <String, int>{};

  @override
  Future<({String id, int? ms})> open(String host, int port, Duration timeout) async {
    attempts++;
    tries[host] = (tries[host] ?? 0) + 1;
    if (busyFirst > 0) {
      busyFirst--;
      throw const PipeBusy('الممرّ مشغول');
    }
    if (denied.contains(host)) throw VpnPipe.failure(const {'code': 'NOT_YOURS', 'message': 'ليس من أجهزتك'}, port: port);
    return super.open(host, port, timeout);
  }
}

void main() {
  late ServerSocket device;
  late _Pipes pipes;
  final accepted = <Socket>[];
  late int deadPort;

  setUp(() async {
    device = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    device.listen((s) {
      accepted.add(s);
      s.listen((_) {}, onError: (Object _) {});
    });
    // منفذٌ مقفول أكيد: يُحجز ثمّ يُغلق
    final tmp = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    deadPort = tmp.port;
    await tmp.close();
    pipes = _Pipes((host, port) => host.endsWith('.2') || host == '10.0.0.9' ? device.port : deadPort);
    VpnPipe.transport = pipes;
    VpnPipe.debugResetGate();
    VpnPipe.maxOpen = 3;
    VpnPipe.queueWait = const Duration(seconds: 5);
    VpnPipe.busyBackoffMs = const [10, 10, 10];
    DeviceNet.vpnOn = () => true;
  });

  tearDown(() async {
    for (final s in accepted) {
      s.destroy();
    }
    accepted.clear();
    await device.close();
    VpnPipe.debugResetGate();
    VpnPipe.maxOpen = 20;
    VpnPipe.queueWait = const Duration(seconds: 25);
    VpnPipe.busyBackoffMs = const [300, 500, 800, 1200, 1500, 1800];
  });

  Future<void> tick([int ms = 120]) => Future<void>.delayed(Duration(milliseconds: ms));

  group('طابور الممرّات', () {
    test('ما زاد على السقف ينتظر دوره ولا يفشل، ويدخل حين يُغلق ممرّ', () async {
      final a = await VpnPipe.connect('10.0.0.9', 80);
      final b = await VpnPipe.connect('10.0.0.9', 80);
      final c = await VpnPipe.connect('10.0.0.9', 80);
      expect(VpnPipe.openNow, 3);
      var done = false;
      final fourth = VpnPipe.connect('10.0.0.9', 80).then((s) {
        done = true;
        return s;
      });
      await tick(250);
      expect(done, isFalse, reason: 'الرابع ينتظر — لا «مشغول» ولا فتحٌ رابع عند الخادم');
      expect(pipes.opened, hasLength(3));
      a.destroy();
      final d = await fourth.timeout(const Duration(seconds: 3));
      expect(pipes.opened, hasLength(4));
      expect(VpnPipe.openNow, 3, reason: 'الدور انتقل للمنتظر');
      for (final s in [b, c, d]) {
        s.destroy();
      }
      await tick();
      expect(VpnPipe.openNow, 0);
    });

    test('الانتظار له حدّ: بعده «الممرّ مشغول» والعدّاد سليم', () async {
      VpnPipe.maxOpen = 1;
      VpnPipe.queueWait = const Duration(milliseconds: 150);
      final a = await VpnPipe.connect('10.0.0.9', 80);
      await expectLater(
        VpnPipe.connect('10.0.0.9', 80),
        throwsA(isA<SocketException>().having((e) => e.message, 'message', contains('مشغول'))),
      );
      expect(VpnPipe.openNow, 1);
      a.destroy();
      await tick();
      expect(VpnPipe.openNow, 0);
      final b = await VpnPipe.connect('10.0.0.9', 80);
      b.destroy();
    });

    test('الجهاز أغلق الاتّصال ⇒ الدور يعود بلا انتظار القارئ', () async {
      final a = await VpnPipe.connect('10.0.0.9', 80);
      a.listen((_) {}, onError: (Object _) {});
      await tick();
      expect(VpnPipe.openNow, 1);
      for (final s in accepted) {
        await s.close();
      }
      await tick(500);
      expect(VpnPipe.openNow, 0);
      a.destroy();
    });

    test('«مشغول» من الخادم يُعاد بعد لحظة ⇒ يتّصل؛ ومشغولٌ دائم ⇒ فشلٌ صريح بلا تسريب دور', () async {
      pipes.busyFirst = 2;
      final a = await VpnPipe.connect('10.0.0.9', 80);
      expect(pipes.attempts, 3, reason: 'محاولتان مشغولتان ثمّ الثالثة');
      a.destroy();
      await tick();
      pipes
        ..attempts = 0
        ..busyFirst = 99;
      await expectLater(VpnPipe.connect('10.0.0.9', 80), throwsA(isA<SocketException>()));
      expect(pipes.attempts, 4, reason: 'الأولى + ثلاث إعادات');
      expect(VpnPipe.openNow, 0);
    });

    test('فتحٌ فشل (الجهاز رفض) يعيد دوره فوراً', () async {
      await expectLater(VpnPipe.connect('10.0.0.77', 80), throwsA(isA<SocketException>()));
      expect(VpnPipe.openNow, 0);
    });

    test('«ليس من أجهزتك» ⇒ PipeDenied (فشل اتّصالٍ كغيره، ويُعرف بنوعه)', () async {
      pipes.denied.add('10.0.0.50');
      await expectLater(VpnPipe.connect('10.0.0.50', 80), throwsA(isA<PipeDenied>()));
      expect(VpnPipe.openNow, 0);
    });
  });

  group('فحص النطاق', () {
    test('بـ«وضع VPN» يمرّ من الممرّ: يجد الجهاز الحيّ، والعنوان المرفوض يُسأل مرّةً لا لكلّ منفذ', () async {
      VpnPipe.maxOpen = 20;
      pipes.denied.add('10.9.9.5');
      final found = <String>[];
      final res = await NetworkDevicesApi.bulkScanSubnet(
        base: '10.9.9',
        startOctet: 1,
        endOctet: 6,
        ports: const [80, 443, 8291],
        concurrency: 6,
        timeout: const Duration(milliseconds: 400),
        onFound: (r) => found.add(r.ip),
      );
      expect(res.map((r) => r.ip), ['10.9.9.2']);
      expect(res.single.openPort, 80);
      expect(found, ['10.9.9.2']);
      expect(pipes.tries['10.9.9.5'], 1, reason: 'مرفوضٌ على نفق الشركة ⇒ لا تُجرَّب بقيّة منافذه');
      expect(pipes.tries['10.9.9.1'], 3, reason: 'عنوانٌ مسموح بلا جهاز ⇒ كلّ المنافذ');
      await tick();
      expect(VpnPipe.openNow, 0, reason: 'لا ممرّ يبقى بعد الفحص');
    });

    test('خارج الوضع لا يمرّ بالممرّ أبداً (كما كان)', () async {
      DeviceNet.vpnOn = () => false;
      final res = await NetworkDevicesApi.bulkScanSubnet(
        base: '127.0.0',
        startOctet: 1,
        endOctet: 1,
        ports: [device.port],
        timeout: const Duration(milliseconds: 400),
      );
      expect(res.single.ip, '127.0.0.1');
      expect(pipes.attempts, 0);
    });
  });
}
