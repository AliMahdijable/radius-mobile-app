import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/api/bdcom_epon.dart';
import 'package:rad_mysvcs/api/olt_profile.dart';
import 'package:rad_mysvcs/api/vsol_olt_api.dart';
import 'package:rad_mysvcs/models/network_device.dart';
import 'package:rad_mysvcs/screens/network_devices/widgets/vsol_live_panel.dart';
import 'package:rad_mysvcs/services/device_stats_cache.dart';
import 'package:rad_mysvcs/theme/typography.dart';

import 'support/app_fonts.dart';

/// لوحة BDCOM على عرض ٣٢٠ (٢٢ أكتوبر): العناوين العربيّة الصحيحة («MAC الـONU»
/// و«أجهزة خلف الـONU»)، الصعود الثمانية ظاهرة ولو مفصولة، قراءات الضوء
/// والمعالج، ومواصفات الطراز منفصلةً عن القراءات. الماكات اصطناعيّة.
void main() {
  setUpAll(loadAppFonts);

  testWidgets('BDCOM على ٣٢٠: ماك الـONU وأجهزته بعنوانين، والصعود والمعالج والمواصفات', (tester) async {
    final oldInterceptors = List<Interceptor>.of(ApiClient.dio.interceptors);
    ApiClient.dio.interceptors.clear();
    ApiClient.dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      handler.reject(DioException(requestOptions: options, error: 'offline fixture'));
    }));
    addTearDown(() {
      ApiClient.dio.interceptors.clear(keepImplyContentTypeInterceptor: false);
      ApiClient.dio.interceptors.addAll(oldInterceptors);
    });
    tester.view.physicalSize = const Size(320 * 3, 900 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    const id = 99004453;
    final profile = OltProfile.resolve(
      OltProfile.fromRecord(brand: 'bdcom', model: 'P3600-04'),
      sysObjectId: '1.3.6.1.4.1.3320.1.495.0',
      sysDescr: 'BDCOM(tm) P3600-04 Software, Version 124293; hardwareversion:D',
    );
    final at = DateTime.now();
    DeviceStatsCache.instance.putRaw(
      id,
      VsolOltStats(
        sysName: 'Switch',
        sysDescr: 'BDCOM(tm) P3600-04 Software, Version 124293; hardwareversion:D',
        profile: profile,
        chassis: const BdcomChassis(cpuPct: 9, boxTempC: 31, ramBytes: 268435456),
        uplinks: [
          for (var i = 1; i <= 4; i++)
            VsolUplink(index: 32 + i, name: 'GigaEthernet0/$i', up: i == 1, speedMbps: 1000, rxBytes: 0, txBytes: 0),
          for (var i = 1; i <= 4; i++)
            VsolUplink(index: 36 + i, name: 'TGigaEthernet0/$i', up: i == 2, speedMbps: 10000, rxBytes: 0, txBytes: 0),
        ],
        ponPorts: [
          const VsolPonPort(index: 41, slot: 0, port: 1, up: true, rxBytes: 0, txBytes: 0, onuTotal: 2, onuOnline: 1),
        ],
        onus: [
          VsolOnu(
            ifIndex: 97,
            slot: 0,
            ponPort: 1,
            onuId: 1,
            online: true,
            mac: '02:00:00:00:01:01',
            vendor: 'HWTC',
            reading: const BdcomOnuReading(rxDbm: -13.5, txDbm: 2.1, tempC: 46, voltV: 3.317),
            readingAt: at,
            learnedMacs: const ['02:10:00:00:00:01', '02:10:00:00:00:02'],
            learnedMacsComplete: true,
            learnedMacsReadAt: at,
          ),
          const VsolOnu(ifIndex: 103, slot: 0, ponPort: 1, onuId: 7, online: false),
        ],
      ),
    );

    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(fontFamily: AppType.family),
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: SingleChildScrollView(
            child: VsolLivePanel(
              device: NetworkDevice(
                id: id,
                adminId: 'fixture',
                name: 'OLT',
                type: 'other',
                brand: 'bdcom',
                model: 'P3600-04',
                ip: '127.0.0.1',
                port: 161,
                apiPort: 161,
                protocol: 'snmp',
                lastStatus: 'online',
                createdAt: DateTime.utc(2026),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pump();
    expect(tester.takeException(), isNull, reason: 'لا فيضان على ٣٢٠');

    expect(find.text('ماك الـONU'), findsOneWidget);
    expect(find.text('02:00:00:00:01:01'), findsOneWidget);
    expect(find.textContaining('MAC اليوزر'), findsNothing);
    expect(find.text('غير متّصل'), findsOneWidget);
    expect(find.textContaining('RX -13.5 dBm'), findsOneWidget);
    expect(find.text('CPU 9%'), findsOneWidget);
    expect(find.text('RAM 256 MB'), findsOneWidget);
    expect(find.textContaining('منافذ الصعود (2/8)'), findsOneWidget, reason: 'الثمانية ظاهرة ولو مفصولة');
    expect(find.textContaining('مواصفات الطراز P3600-04'), findsOneWidget);

    final devices = find.text('أجهزة خلف الـONU\u200F (2)');
    await tester.ensureVisible(devices);
    await tester.tap(devices);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('02:10:00:00:00:01'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 6));
  });
}
