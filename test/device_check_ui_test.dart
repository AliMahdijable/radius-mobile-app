import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/api/device_reach.dart';
import 'package:rad_mysvcs/api/mikrotik_api.dart';
import 'package:rad_mysvcs/api/network_devices_api.dart';
import 'package:rad_mysvcs/core/platform/app_platform.dart';
import 'package:rad_mysvcs/core/platform/desktop_layout.dart';
import 'package:rad_mysvcs/core/widgets/app_sheet.dart';
import 'package:rad_mysvcs/models/network_device.dart';
import 'package:rad_mysvcs/screens/network_devices/device_check_text.dart';
import 'package:rad_mysvcs/screens/network_devices/device_vitals.dart';
import 'package:rad_mysvcs/screens/network_devices/network_device_details_screen.dart';
import 'package:rad_mysvcs/screens/network_devices/network_device_form_sheet.dart';
import 'package:rad_mysvcs/screens/network_devices/widgets/brand_badge.dart';
import 'package:rad_mysvcs/screens/network_devices/widgets/device_big_card.dart';
import 'package:rad_mysvcs/screens/network_devices/widgets/device_image.dart';
import 'package:rad_mysvcs/services/device_read_health.dart';
import 'package:rad_mysvcs/theme/typography.dart';

import 'visual_perm/visual_perm_harness.dart';

/// ١ نوفمبر — المالك: «اذا الجهاز حتى لو ما مضيوف صح المفروض تخلي زر فحص الجهاز بالبنك يرد ويظهر شعار الجهاز يرد بنك اتصال
/// ping تاكد من الاعدادات الجهاز». الواجهة: شاشة الجهاز (هاتف وحاسبة)، شيت التعديل (الحفظ ثمّ الفحص)، البطاقة الكبيرة، والشعار.
/// الشبكة كلّها مزيّفة.
Map<String, Object?> _json({
  int id = 7,
  String brand = 'mikrotik',
  String? model = 'BaseBox 5',
  String? protocol = 'api',
  int? apiPort = 8729,
  String status = 'unknown',
}) =>
    {
      'id': id,
      'admin_id': '2',
      'name': 'سكتر 1',
      'type': 'sector',
      'brand': brand,
      'model': model,
      'ip': '10.70.241.2',
      'port': 80,
      'api_port': apiPort,
      'protocol': protocol,
      'has_credentials': 1,
      'last_status': status,
      'created_at': '2026-10-01T00:00:00Z',
    };

class _Api implements HttpClientAdapter {
  final requests = <String>[];
  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? body, Future<void>? cancel) async {
    requests.add('${o.method} ${o.uri.path}');
    Object data = {'success': true, 'data': []};
    if (o.uri.path.endsWith('/credentials')) {
      data = {'success': true, 'credentials': {'user': 'admin', 'pass': 'x', 'community': 'public'}};
    }
    if (o.method == 'PUT' && o.uri.path == '/api/v2/admin/devices/7') {
      data = {'success': true, 'data': _json()};
    }
    return ResponseBody.fromString(jsonEncode(data), 200, headers: {Headers.contentTypeHeader: ['application/json']});
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  setUpAll(visualSetUpAll);

  late _Api api;
  late List<int> knocked;

  Future<void> setUpNet(
    WidgetTester t, {
    required bool icmp,
    ReachProbe? ping,
    bool serviceUp = false,
    Map<int, PortReply> ports = const {},
    bool authFails = true,
  }) async {
    await visualSetUp(s1bSasOwner);
    api = _Api();
    ApiClient.dio.httpClientAdapter = api;
    NetworkDevicesApi.invalidateCredentialsCache();
    DeviceReadHealth.instance.debugReset();
    DeviceReach.resetForTest();
    knocked = [];
    NetworkDevicesApi.debugIcmpUsable = icmp;
    NetworkDevicesApi.icmpProbe = (ip, n) async => ping ?? (status: 'offline', responseMs: null, packetLoss: 100.0);
    NetworkDevicesApi.debugService =
        (_) async => serviceUp ? (status: 'online', responseMs: 14, packetLoss: 0.0) : (status: 'offline', responseMs: null, packetLoss: 100.0);
    DeviceReach.debugConnect = (host, port, timeout) async {
      if (host == DeviceReach.canaryHost) return (port: port, reply: PortReply.silent, ms: null);
      knocked.add(port);
      final r = ports[port] ?? PortReply.silent;
      return (port: port, reply: r, ms: r == PortReply.silent ? null : 6);
    };
    MikrotikApi.debugFetch =
        authFails ? () async => throw MikrotikException('اسم المستخدم أو كلمة المرور خاطئة', code: 'auth') : null;
    addTearDown(() async {
      MikrotikApi.debugFetch = null;
      NetworkDevicesApi.debugIcmpUsable = null;
      NetworkDevicesApi.debugService = null;
      DeviceReach.resetForTest();
      DeviceReadHealth.instance.debugReset();
      AppPlatform.debugIsDesktop = null;
      await visualTearDown();
    });
  }

  Future<void> pumpScreen(WidgetTester t, Widget home, {Size size = const Size(390, 844)}) async {
    t.view.physicalSize = size * 2;
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
      theme: ThemeData(fontFamily: AppType.family),
      home: Directionality(textDirection: TextDirection.rtl, child: home),
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

  Finder note() => find.byKey(const ValueKey('device-check-note'));
  String noteText(WidgetTester t) {
    final rich = find.descendant(of: note(), matching: find.byType(Text)).evaluate().map((e) => (e.widget as Text).textSpan?.toPlainText() ?? (e.widget as Text).data ?? '');
    return rich.join(' ');
  }

  testWidgets('🚨 iOS (لا ping)، المنفذ وكلمة المرور خطأ، وWinbox يردّ ⇒ «متّصل» بزمنه + «يردّ — تأكّد من الإعدادات» — لا «غير متّصل»',
      (t) async {
    await setUpNet(t, icmp: false, ports: {8291: PortReply.open});
    await pumpScreen(t, NetworkDeviceDetailsScreen(device: NetworkDevice.fromJson(_json())));
    await settle(t);
    expect(find.text('متّصل'), findsOneWidget);
    expect(find.text('غير متّصل'), findsNothing);
    expect(find.text('6'), findsWidgets, reason: 'زمن الاتّصال بالـms');
    expect(note(), findsOneWidget);
    final text = noteText(t);
    expect(text, contains('الجهاز يردّ على الاتصال (المنفذ 8291)'));
    expect(text, contains('تأكّد من إعدادات الجهاز: اسم المستخدم وكلمة المرور والمنفذ'));
    expect(knocked, isNot(contains(8729)), reason: 'منفذ خدمته يُفحص وحده (مزيّف هنا) لا ضمن المسح');
    await finish(t);
  });

  testWidgets('أندرويد: ping يردّ وخدمته تردّ لكنّ الدخول فشل (اللوحة) ⇒ سطر «تأكّد من إعدادات الجهاز» من قراءة اللوحة', (t) async {
    await setUpNet(t, icmp: true, ping: (status: 'online', responseMs: 9, packetLoss: 0.0), serviceUp: true);
    await pumpScreen(t, NetworkDeviceDetailsScreen(device: NetworkDevice.fromJson(_json())));
    await settle(t);
    expect(find.text('متّصل'), findsOneWidget);
    expect(DeviceReadHealth.instance.errorOf(7), 'اسم المستخدم أو كلمة المرور خاطئة', reason: 'اللوحة سجّلت فشل الدخول');
    expect(noteText(t), 'الجهاز يردّ على الاتصال (ping) — تأكّد من إعدادات الجهاز: اسم المستخدم وكلمة المرور والمنفذ');
    await finish(t);
  });

  testWidgets('لا يردّ شيء ⇒ «غير متّصل» + «لا يردّ على ping — تأكّد من العنوان والشبكة»', (t) async {
    await setUpNet(t, icmp: true);
    await pumpScreen(t, NetworkDeviceDetailsScreen(device: NetworkDevice.fromJson(_json())));
    await settle(t);
    expect(find.text('غير متّصل'), findsOneWidget);
    expect(noteText(t), 'لا يردّ على ping — تأكّد من العنوان والشبكة');
    await finish(t);
  });

  testWidgets('الحاسبة ١٢٦٠: السطر نفسه تحت «فحص الآن (ping)»، والحالة «متّصل»', (t) async {
    await setUpNet(t, icmp: false, ports: {443: PortReply.open});
    AppPlatform.debugIsDesktop = true;
    await pumpScreen(t, DesktopScope(child: NetworkDeviceDetailsScreen(device: NetworkDevice.fromJson(_json()))), size: const Size(1260, 860));
    await settle(t);
    expect(find.text('فحص الآن (ping)'), findsOneWidget);
    expect(find.text('متّصل'), findsOneWidget);
    expect(noteText(t), contains('الجهاز يردّ على الاتصال (المنفذ 443)'));
    expect(t.takeException(), isNull);
    await finish(t);
  });

  testWidgets('شيت التعديل: الحفظ ثمّ الفحص فوراً — يعود الجهاز بحالته والإشعار يقول «يردّ — تأكّد من الإعدادات»', (t) async {
    await setUpNet(t, icmp: true, ping: (status: 'online', responseMs: 4, packetLoss: 0.0));
    NetworkDevice? result;
    await pumpScreen(
      t,
      Builder(
        builder: (ctx) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () async {
                result = await showAppSheet<NetworkDevice>(
                  context: ctx,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (_) => NetworkDeviceFormSheet(existing: NetworkDevice.fromJson(_json())),
                );
              },
              child: const Text('افتح'),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('افتح'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    await settle(t, const Duration(milliseconds: 500));
    expect(find.text('حفظ التعديلات').hitTestable(), findsOneWidget);
    await t.tap(find.text('حفظ التعديلات'));
    await settle(t, const Duration(seconds: 2));
    expect(api.requests, contains('PUT /api/v2/admin/devices/7'));
    expect(result?.lastStatus, 'online', reason: 'الجهاز يعود بنتيجة الفحص');
    expect(result?.lastResponseMs, 4);
    expect(find.textContaining('تمّ الحفظ — الجهاز يردّ على الاتصال (ping)'), findsOneWidget);
    expect(find.textContaining('تأكّد من إعدادات الجهاز: اسم المستخدم وكلمة المرور والمنفذ'), findsOneWidget);
    await settle(t, const Duration(seconds: 8));
    await finish(t);
  });

  group('البطاقة الكبيرة', () {
    Widget card(String status, VitalsState st) => MaterialApp(
          theme: ThemeData(fontFamily: AppType.family),
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: SizedBox(
                width: 380,
                child: DeviceBigCard(device: NetworkDevice.fromJson(_json(status: status)), state: st),
              ),
            ),
          ),
        );

    testWidgets('🚨 يردّ على الفحص وقراءته تفشل ⇒ «يردّ على الاتصال — تأكّد من الإعدادات» لا «تعذّر الاتّصال»', (t) async {
      await t.pumpWidget(card('online', VitalsState(error: 'تعذّر الاتّصال', at: DateTime.now())));
      final d = NetworkDevice.fromJson(_json(status: 'online'));
      expect(find.text(DeviceCheckText.settingsLine(d)), findsOneWidget);
      expect(find.textContaining('تعذّر الاتّصال بالجهاز'), findsNothing);
      expect(find.textContaining('غير متّصل'), findsNothing, reason: 'شارة الحالة معزولة (iso) — نبحث بالاحتواء');
    });

    testWidgets('لم يُفحص بعد ⇒ السبب العامّ كما كان؛ مفصول ⇒ سطر «لا يردّ» لا الإعدادات', (t) async {
      await t.pumpWidget(card('unknown', VitalsState(error: 'تعذّر الاتّصال', at: DateTime.now())));
      expect(find.text('تعذّر الاتّصال بالجهاز — يعيد المحاولة تلقائيّاً'), findsOneWidget);
      await t.pumpWidget(card('offline', VitalsState(error: 'تعذّر الاتّصال', at: DateTime.now())));
      expect(find.textContaining('تأكّد من إعدادات الجهاز'), findsNothing);
      expect(find.textContaining('غير متّصل'), findsOneWidget);
    });
  });

  group('الشعار — لا صندوق فارغ', () {
    String? badgeOf(WidgetTester t) => t.widgetList<BrandBadge>(find.byType(BrandBadge)).map((b) => b.brand).firstOrNull;

    Future<void> pumpImage(WidgetTester t, String brand, String? model) => t.pumpWidget(
          MaterialApp(home: Center(child: DeviceImage(brand: brand, model: model, size: 64))),
        );

    testWidgets('أولت HSGQ بلا طراز ⇒ شعار HSGQ (لا ثلاث نقاط)', (t) async {
      await pumpImage(t, 'hsgq', null);
      expect(badgeOf(t), 'hsgq');
    });
    testWidgets('سجلٌّ «أخرى» طرازه يقول مصنّعه ⇒ شعار المصنّع', (t) async {
      await pumpImage(t, 'other', 'HSGQ OLT');
      expect(badgeOf(t), 'hsgq');
      await pumpImage(t, 'vsol', 'BDCOM GP3600');
      expect(badgeOf(t), 'bdcom');
    });
    testWidgets('طرازٌ مجهول ⇒ شعار علامته؛ لا علامة ولا طراز ⇒ الشارة العامّة', (t) async {
      await pumpImage(t, 'mikrotik', 'XYZ-لا-يوجد');
      expect(badgeOf(t), 'mikrotik');
      await pumpImage(t, 'other', null);
      expect(badgeOf(t), 'other');
    });
    test('كلّ علامةٍ في النموذج لها شعارٌ بلونها (لا الرماديّ العامّ إلّا «أخرى»)', () {
      final grey = BrandBadge.colorFor('other');
      for (final b in NetworkDeviceLabels.brands.keys.where((b) => b != 'other')) {
        expect(BrandBadge.colorFor(b), isNot(grey), reason: '$b بلا شعار');
      }
    });
  });
}
