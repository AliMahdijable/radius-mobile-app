import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:rad_mysvcs/models/network_device.dart';
import 'package:rad_mysvcs/models/tower_layout.dart';
import 'package:rad_mysvcs/screens/network_devices/tower/tower_builder_screen.dart';
import 'package:rad_mysvcs/screens/network_devices/tower/tower_logic.dart';
import 'package:rad_mysvcs/screens/network_devices/tower/tower_place_screen.dart';

/// بناء البرج ومكان الجهاز — بلا خادم (serverReady: false ⇒ لا طلب يُرسل) وبلا بوصلة (منصّة الاختبار).
NetworkDevice dev(int id, String name, {String type = 'router', String brand = 'mikrotik', String? model}) =>
    NetworkDevice(
      id: id,
      adminId: '2',
      regionId: 1,
      name: name,
      type: type,
      brand: brand,
      model: model,
      ip: '10.0.0.$id',
      port: 8728,
      lastStatus: 'online',
      createdAt: DateTime(2026, 10, 1),
    );

final _devices = [
  dev(1, 'سكتر 1', model: 'BaseBox 5'),
  dev(2, 'سكتر 2', model: 'BaseBox 5'),
  dev(3, 'لنك المعامل', type: 'link', brand: 'ubnt', model: 'PowerBeam M5'),
  dev(4, 'سيرفر التوزيع', type: 'switch', model: 'CCR1009-7G-1C-1S+'),
];

/// يفتح الشاشة فوق صفحةٍ ويُرجع ما أعادته عند الخروج.
Future<Future<Object?> Function()> _host(WidgetTester t, Widget screen) async {
  Object? result;
  var popped = false;
  await t.pumpWidget(MaterialApp(
    home: MediaQuery(
      data: const MediaQueryData(size: Size(400, 860), disableAnimations: true),
      child: Builder(
        builder: (ctx) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () async {
                result = await Navigator.of(ctx).push(MaterialPageRoute(builder: (_) => screen));
                popped = true;
              },
              child: const Text('افتح'),
            ),
          ),
        ),
      ),
    ),
  ));
  return () async => popped ? result : null;
}

void main() {
  testWidgets('رتّبها لي: النتيجة بالأعداد، و«اعرض البرج الآن» يُرجع مكان كلّ جهاز', (t) async {
    t.view.physicalSize = const Size(400, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final result = await _host(
      t,
      TowerBuilderScreen(
        regionId: 1,
        regionName: 'برج الحيّ',
        devices: _devices,
        readings: const {},
        saved: const {},
        settings: const TowerSettings(regionId: 1),
        canEdit: true,
        serverReady: false,
      ),
    );
    await t.pump();
    await t.tap(find.text('افتح'));
    await t.pumpAndSettle();
    expect(find.text('«برج الحيّ» · 4 جهازاً'), findsOneWidget);
    expect(find.textContaining('الحفظ غير متاح الآن'), findsOneWidget);

    await t.tap(find.widgetWithText(FilledButton, 'رتّبها لي'));
    await t.pumpAndSettle();
    expect(find.text('النتيجة · جاهز للعرض'), findsOneWidget);
    expect(find.text('في الكابينة'), findsOneWidget);

    await t.scrollUntilVisible(find.text('اعرض البرج الآن'), 200);
    await t.tap(find.text('اعرض البرج الآن'));
    await t.pumpAndSettle();
    final r = await result() as TowerBuilderResult;
    expect(r.openTour, isFalse);
    expect(r.saved.keys.toSet(), {1, 2, 3, 4});
    expect(r.saved[4]!.level, TowerLevel.base, reason: 'السويج في الكابينة');
    expect(r.saved[3]!.level, TowerLevel.top, reason: 'اللنك في القمّة');
  });

  testWidgets('يدويّ: الارتفاع والحلقات بحدودهما، والرجوع يُرجع الشكل', (t) async {
    t.view.physicalSize = const Size(400, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final result = await _host(
      t,
      TowerBuilderScreen(
        regionId: 1,
        regionName: 'برج الحيّ',
        devices: _devices,
        readings: const {},
        saved: const {},
        settings: const TowerSettings(regionId: 1, heightM: 117, rings: 8),
        canEdit: true,
        serverReady: false,
      ),
    );
    await t.pump();
    await t.tap(find.text('افتح'));
    await t.pumpAndSettle();
    await t.tap(find.text('يدويّ'));
    await t.pumpAndSettle();
    await t.tap(find.bySemanticsLabel('زِد الارتفاع'));
    await t.pump();
    expect(find.text('120 م'), findsOneWidget);
    await t.tap(find.bySemanticsLabel('زِد الارتفاع'));
    await t.pump();
    expect(find.text('120 م'), findsOneWidget, reason: 'الحدّ الأعلى 120');
    await t.tap(find.text('عمود'));
    await t.pump();
    expect(find.text('الأجهزة على البرج · 4'), findsOneWidget);

    await t.tap(find.byIcon(LucideIcons.arrowRight));
    await t.pumpAndSettle();
    final r = await result() as TowerBuilderResult;
    expect(r.settings.heightM, 120);
    expect(r.settings.type, TowerType.pole);
    expect(r.settings.rings, 8);
  });

  testWidgets('مكان الجهاز بلا بوصلة: الأزرار تثبّت، والكابينة بلا اتّجاه، والمستوى يتغيّر', (t) async {
    t.view.physicalSize = const Size(400, 1000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final arranged = TowerArrange.arrange(_devices);
    final result = await _host(
      t,
      TowerPlaceScreen(
        devices: _devices,
        arranged: arranged,
        startDeviceId: 1,
        settings: const TowerSettings(regionId: 1),
        serverReady: false,
      ),
    );
    await t.pump();
    await t.tap(find.text('افتح'));
    await t.pumpAndSettle();
    expect(find.textContaining('لا بوصلة على هذا الجهاز'), findsOneWidget);
    final az0 = arranged[1]!.azimuth!;
    await t.tap(find.bySemanticsLabel('زِد 5 درجة'));
    await t.pump();
    expect(find.textContaining('مثبّت'), findsWidgets);

    // المستوى
    await t.ensureVisible(find.textContaining('السفلي'));
    await t.tap(find.textContaining('السفلي'));
    await t.pump();

    await t.ensureVisible(find.text('حفظ وإنهاء'));
    await t.tap(find.text('حفظ وإنهاء'));
    await t.pumpAndSettle();
    final r = await result() as Map<int, TowerPlacement>;
    expect(r[1]!.fixed, isTrue);
    expect(r[1]!.azimuth, normDeg(az0 + 5));
    expect(r[1]!.level, TowerLevel.lower);
    expect(r.containsKey(4), isFalse, reason: 'لم يُغيَّر شيءٌ في الكابينة');
  });

  testWidgets('جهاز الكابينة: لا بوصلة ولا اتّجاه — المستوى وحده', (t) async {
    t.view.physicalSize = const Size(400, 1000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await _host(
      t,
      TowerPlaceScreen(
        devices: _devices,
        arranged: TowerArrange.arrange(_devices),
        startDeviceId: 4,
        settings: const TowerSettings(regionId: 1),
        serverReady: false,
      ),
    );
    await t.tap(find.text('افتح'));
    await t.pumpAndSettle();
    expect(find.textContaining('في الكابينة — لا يحتاج اتّجاهاً'), findsOneWidget);
    expect(find.text('ثبّت الاتّجاه هنا'), findsNothing);
    expect(find.textContaining('جولة البوصلة · 0 من 3 مثبّتة'), findsOneWidget);
  });
}
