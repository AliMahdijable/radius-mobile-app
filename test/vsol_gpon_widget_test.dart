import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/api/vsol_olt_api.dart';
import 'package:rad_mysvcs/models/network_device.dart';
import 'package:rad_mysvcs/screens/network_devices/widgets/vsol_live_panel.dart';
import 'package:rad_mysvcs/services/device_stats_cache.dart';

void main() {
  testWidgets('learned MAC expansion survives rebuild, search and reopen',
      (tester) async {
    final oldInterceptors = List<Interceptor>.of(ApiClient.dio.interceptors);
    ApiClient.dio.interceptors.clear();
    ApiClient.dio.interceptors
        .add(InterceptorsWrapper(onRequest: (options, handler) {
      handler.reject(
          DioException(requestOptions: options, error: 'offline fixture'));
    }));
    addTearDown(() {
      ApiClient.dio.interceptors.clear();
      ApiClient.dio.interceptors.addAll(oldInterceptors);
    });
    const id = 99004452;
    DeviceStatsCache.instance.putRaw(
        id,
        VsolOltStats(onus: [
          VsolOnu(
              ifIndex: 14,
              slot: 0,
              ponPort: 1,
              onuId: 1,
              online: true,
              technology: VsolPonTechnology.gpon,
              name: 'B2-W',
              serial: 'TEST00000001',
              learnedMacs: const ['02:00:00:00:00:01', '02:00:00:00:00:02'],
              learnedMacsComplete: true,
              learnedMacsReadAt: DateTime.utc(2026)),
        ]));
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child: VsolLivePanel(
                    device: NetworkDevice(
                        id: id,
                        adminId: 'fixture',
                        name: 'fixture',
                        type: 'other',
                        brand: 'vsol',
                        ip: '127.0.0.1',
                        port: 161,
                        apiPort: 161,
                        lastStatus: 'online',
                        createdAt: DateTime.utc(2026)))))));
    await tester.pump();
    final expansion = find.text('MACs المتعلّمة (2)');
    await tester.ensureVisible(expansion);
    await tester.tap(expansion);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('02:00:00:00:00:01'), findsOneWidget);
    final search = find.byType(TextField).first;
    await tester.ensureVisible(search);
    await tester.enterText(search, 'B2-W');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('02:00:00:00:00:01'), findsOneWidget);
    await tester.enterText(search, '02:00:00:00:00:02');
    await tester.pumpAndSettle();
    expect(find.text('B2-W'), findsOneWidget);
    await tester.ensureVisible(expansion);
    await tester.tap(expansion);
    await tester.pumpAndSettle();
    await tester.tap(expansion);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(
        find.byWidgetPredicate(
            (w) => w is SelectableText && w.data == '02:00:00:00:00:02'),
        findsOneWidget);
    await tester.ensureVisible(search);
    await tester.enterText(search, 'missing ONU');
    await tester.pumpAndSettle();
    expect(find.text('B2-W'), findsNothing);
    await tester.enterText(search, 'B2-W');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('02:00:00:00:00:01'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
