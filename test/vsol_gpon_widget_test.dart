import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/api/vsol_olt_api.dart';
import 'package:rad_mysvcs/models/network_device.dart';
import 'package:rad_mysvcs/screens/network_devices/widgets/vsol_live_panel.dart';
import 'package:rad_mysvcs/services/device_stats_cache.dart';
import 'package:rad_mysvcs/theme/typography.dart';

import 'support/app_fonts.dart';

void main() {
  setUpAll(loadAppFonts);
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
      ApiClient.dio.interceptors.clear(keepImplyContentTypeInterceptor: false);
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
        theme: ThemeData(fontFamily: AppType.family),
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
    final expansion = find.text('أجهزة خلف الـONU\u200F (2)');
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

  testWidgets('subscribers scroll inside their section and retain numbering',
      (tester) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final oldInterceptors = List<Interceptor>.of(ApiClient.dio.interceptors);
    ApiClient.dio.interceptors.clear();
    ApiClient.dio.interceptors
        .add(InterceptorsWrapper(onRequest: (options, handler) {
      handler.reject(
          DioException(requestOptions: options, error: 'offline fixture'));
    }));
    addTearDown(() {
      ApiClient.dio.interceptors.clear(keepImplyContentTypeInterceptor: false);
      ApiClient.dio.interceptors.addAll(oldInterceptors);
    });
    const id = 99004453;
    DeviceStatsCache.instance.putRaw(
        id,
        VsolOltStats(onus: [
          for (var i = 1; i <= 12; i++)
            VsolOnu(
                ifIndex: 13 + i,
                slot: 0,
                ponPort: i <= 6 ? 1 : 2,
                onuId: (i - 1) % 6 + 1,
                online: i != 2,
                technology: VsolPonTechnology.gpon,
                name: 'ONU-$i',
                serial: 'TEST000000$i'),
        ]));
    final pageScroll = ScrollController();
    addTearDown(pageScroll.dispose);
    await tester.pumpWidget(MaterialApp(
        theme: ThemeData(fontFamily: AppType.family),
        home: Scaffold(
            body: Directionality(
                textDirection: TextDirection.rtl,
                child: SingleChildScrollView(
                    controller: pageScroll,
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
                            createdAt: DateTime.utc(2026))))))));
    await tester.pumpAndSettle();
    final list = find.byKey(const PageStorageKey('vsol-$id-onu-list'));
    final innerScroll =
        find.descendant(of: list, matching: find.byType(Scrollable));
    await tester.ensureVisible(list);
    final pageOffset = pageScroll.offset;
    final search = find.byType(TextField).first;
    final searchPosition = tester.getTopLeft(search);
    await tester.drag(list, const Offset(0, -180));
    await tester.pumpAndSettle();
    expect(pageScroll.offset, pageOffset);
    expect(tester.getTopLeft(search), searchPosition);
    expect(tester.state<ScrollableState>(innerScroll).position.pixels,
        greaterThan(0));
    await tester.scrollUntilVisible(find.text('ONU-12'), 180,
        scrollable: innerScroll);
    await tester.pumpAndSettle();
    expect(find.text('ONU-12').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.ensureVisible(search);
    await tester.enterText(search, 'ONU-12');
    await tester.pumpAndSettle();
    expect(find.descendant(of: list, matching: find.text('ONU-12')),
        findsOneWidget);
    expect(
        find.byWidgetPredicate(
            (w) => w is Text && w.semanticsLabel == 'المشترك 12'),
        findsOneWidget);
    expect(tester.state<ScrollableState>(innerScroll).position.pixels, 0);
    await tester.enterText(search, '');
    await tester.pumpAndSettle();
    expect(find.text('ONU-1').hitTestable(), findsOneWidget);
    await tester.tap(find.text('المتّصلون'));
    await tester.pumpAndSettle();
    expect(find.text('المشتركون (11)'), findsOneWidget);
    expect(find.text('ONU-2'), findsNothing);
    expect(
        find.byWidgetPredicate(
            (w) => w is Text && w.semanticsLabel == 'المشترك 3'),
        findsOneWidget);
    final header = find.text('المشتركون (11)');
    await tester.ensureVisible(header);
    await tester.tap(header);
    await tester.pumpAndSettle();
    expect(list, findsNothing);
    await tester.tap(header);
    await tester.pumpAndSettle();
    expect(list, findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
