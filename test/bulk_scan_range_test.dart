import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/network_devices_api.dart';
import 'package:rad_mysvcs/screens/network_devices/bulk_scan_screen.dart';

import 'sim_el/sim_harness.dart';

/// «اكتشاف الأجهزة» — «من – إلى» (المالك ١٤ نوفمبر ٢٠٢٦: «بحث نطاق البرج … نخلي اختياري يختار رينج من الى مثلا
/// 10.10.10.2-10.10.10.20 … ما نقيده فقط بسبنت»): على الشاشة الحقيقيّة — الطريقتان بحبّتين، الخانتان تمسحان ما كُتب بالضبط (ولو
/// عبر ‎/24‎)، والشبكة بحدّها الحقيقيّ، والخطأ بسببه بلا مسح؛ ولا فيضان على ٣٢٠ ولا ٤٨٠ بخطّ ١٫٢.
void main() {
  late SimServer server;
  final scanned = <List<String>>[];
  setUpAll(simSetUpAll);
  setUp(() async {
    server = await simSetUp();
    server.reply('GET', '/api/v2/admin/devices/regions', 200, {'success': true, 'data': []});
    scanned.clear();
    NetworkDevicesApi.debugScan = (ips) async {
      scanned.add(ips);
      return [
        ScanResult(ip: ips.first, openPort: 8291, responseMs: 4, guessBrand: 'mikrotik', guessProtocol: 'api', guessApiPort: 8728),
      ];
    };
  });
  tearDown(() => NetworkDevicesApi.debugScan = null);

  Future<void> open(WidgetTester t, double w, {double scale = 1.0}) async {
    t.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
    await pumpSim(t, SimVariant(w, dark: false), home: (_) => const BulkScanScreen());
  }

  Future<void> start(WidgetTester t) async {
    await t.tap(find.byKey(const ValueKey('bulk-scan-start')));
    await t.pumpAndSettle();
  }

  testWidgets('«من – إلى»: ما كُتب بالضبط — والأخير رقمه وحده، ولو عبر ‎/24‎', (t) async {
    await open(t, 390);
    expect(find.byKey(const ValueKey('bulk-scan-network')), findsOneWidget, reason: 'الافتراضيّ «شبكة» كما كان');
    await t.tap(find.text('من – إلى'));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('bulk-scan-network')), findsNothing);
    await t.enterText(find.byKey(const ValueKey('bulk-scan-from')), '10.10.10.2');
    await t.enterText(find.byKey(const ValueKey('bulk-scan-to')), '20');
    await start(t);
    expect(scanned.single.first, '10.10.10.2');
    expect(scanned.single.last, '10.10.10.20');
    expect(scanned.single.length, 19);
    expect(find.text('10.10.10.2'), findsWidgets, reason: 'النتيجة ظاهرة');

    await t.enterText(find.byKey(const ValueKey('bulk-scan-from')), '10.10.10.250');
    await t.enterText(find.byKey(const ValueKey('bulk-scan-to')), '10.10.11.5');
    await start(t);
    expect(scanned.last.length, 12);
    expect(scanned.last.last, '10.10.11.5');
    await simDrain(t);
  });

  testWidgets('الخطأ بسببه ولا مسح: معكوس، وأكبر من الحدّ', (t) async {
    await open(t, 390);
    await t.tap(find.text('من – إلى'));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const ValueKey('bulk-scan-from')), '10.10.10.20');
    await t.enterText(find.byKey(const ValueKey('bulk-scan-to')), '10.10.10.2');
    await start(t);
    expect(find.textContaining('أكبر من آخره'), findsOneWidget);
    await simDrain(t);
    await t.enterText(find.byKey(const ValueKey('bulk-scan-from')), '10.10.0.1');
    await t.enterText(find.byKey(const ValueKey('bulk-scan-to')), '10.10.9.1');
    await start(t);
    expect(find.textContaining('الحدّ'), findsOneWidget);
    expect(scanned, isEmpty);
    await simDrain(t);
  });

  testWidgets('«شبكة»: ‎/23‎ بحدّها (كانت ‎/24‎ بصمت)، والمدى الكامل بالخانة نفسها؛ والتبديل يحمل ما كُتب', (t) async {
    await open(t, 390);
    await t.enterText(find.byKey(const ValueKey('bulk-scan-network')), '10.10.4.0/23');
    await start(t);
    expect(scanned.last.length, 510);
    expect(scanned.last.first, '10.10.4.1');
    expect(scanned.last.last, '10.10.5.254');

    await t.enterText(find.byKey(const ValueKey('bulk-scan-network')), '10.10.10.2-10.10.10.20');
    await start(t);
    expect(scanned.last.length, 19);

    // «شبكة» ⇒ «من – إلى»: الخانتان تمتلئان من الشبكة المكتوبة.
    await t.enterText(find.byKey(const ValueKey('bulk-scan-network')), '192.168.7');
    await t.tap(find.text('من – إلى'));
    await t.pumpAndSettle();
    expect(find.text('192.168.7.1'), findsOneWidget);
    expect(find.text('192.168.7.254'), findsOneWidget);
    await simDrain(t);
  });

  for (final w in [320.0, 480.0]) {
    testWidgets('لا فيضان: ${w.toInt()} بخطّ ١٫٢ — بالطريقتين', (t) async {
      await open(t, w, scale: 1.2);
      expect(t.takeException(), isNull);
      await t.tap(find.text('من – إلى'));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const ValueKey('bulk-scan-from')), '255.255.255.200');
      await t.enterText(find.byKey(const ValueKey('bulk-scan-to')), '255.255.255.250');
      await t.pump();
      expect(t.takeException(), isNull);
      await simDrain(t);
    });
  }
}
