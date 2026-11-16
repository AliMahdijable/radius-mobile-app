import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/api/device_reach.dart';
import 'package:rad_mysvcs/api/network_devices_api.dart';
import 'package:rad_mysvcs/models/network_device.dart';
import 'package:rad_mysvcs/screens/network_devices/network_device_form_sheet.dart';
import 'package:rad_mysvcs/services/device_read_health.dart';
import 'package:rad_mysvcs/theme/typography.dart';

import 'visual_perm/visual_perm_harness.dart';

/// ١٦ نوفمبر — «دخول صفحة الأولت» في تعديل جهاز HSGQ (SNMP): يظهر لـHSGQ وحده، ويُحفظ مع الـcommunity بمفتاحي
/// `web_user`/`web_pass` (الخادم يشفّر كائن بيانات الجهاز كلّه كما هو)، ويُقرأ عند فتح التعديل.
Map<String, Object?> _json({int id = 10035, String brand = 'hsgq'}) => {
      'id': id,
      'admin_id': '2',
      'name': 'OLT',
      'type': 'switch',
      'brand': brand,
      'model': null,
      'ip': '10.150.150.254',
      'port': 80,
      'api_port': 161,
      'protocol': 'snmp',
      'has_credentials': 1,
      'last_status': 'online',
      'created_at': '2026-11-16T11:35:09Z',
    };

class _Api implements HttpClientAdapter {
  _Api(this.device);
  final Map<String, Object?> device;
  final puts = <Map<String, dynamic>>[];
  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? body, Future<void>? cancel) async {
    Object data = {'success': true, 'data': []};
    if (o.method == 'PUT' && o.uri.path == '/api/v2/admin/devices/${device['id']}') {
      puts.add((o.data is String ? jsonDecode(o.data as String) : o.data as Map).cast<String, dynamic>());
      data = {'success': true, 'data': device};
    }
    return ResponseBody.fromString(jsonEncode(data), 200, headers: {Headers.contentTypeHeader: ['application/json']});
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  setUpAll(visualSetUpAll);

  Future<_Api> open(WidgetTester t, Map<String, Object?> device, Map<String, dynamic> creds) async {
    await visualSetUp(s1bSasOwner);
    final api = _Api(device);
    ApiClient.dio.httpClientAdapter = api;
    NetworkDevicesApi.invalidateCredentialsCache();
    NetworkDevicesApi.debugSeedCredentials(device['id']! as int, creds, DateTime.now());
    DeviceReadHealth.instance.debugReset();
    DeviceReach.resetForTest();
    NetworkDevicesApi.debugIcmpUsable = false;
    NetworkDevicesApi.debugService = (_) async => (status: 'online', responseMs: 5, packetLoss: 0.0);
    DeviceReach.debugConnect = (host, port, timeout) async => (port: port, reply: PortReply.silent, ms: null);
    addTearDown(() async {
      NetworkDevicesApi.debugIcmpUsable = null;
      NetworkDevicesApi.debugService = null;
      DeviceReach.resetForTest();
      DeviceReadHealth.instance.debugReset();
      await visualTearDown();
    });
    t.view.physicalSize = const Size(390, 900) * 2;
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
      theme: ThemeData(fontFamily: AppType.family),
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Builder(
          builder: (ctx) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => showModalBottomSheet<void>(
                  context: ctx,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (_) => NetworkDeviceFormSheet(existing: NetworkDevice.fromJson(device)),
                ),
                child: const Text('افتح'),
              ),
            ),
          ),
        ),
      ),
    ));
    await t.tap(find.text('افتح'));
    for (var i = 0; i < 8; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    return api;
  }

  Future<void> finish(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 30));
  }

  Finder field(String label) => find.widgetWithText(TextFormField, label);

  testWidgets('HSGQ ‏(SNMP): الحقلان يظهران بقيمهما المحفوظة، والحفظ يرسلهما مع الـcommunity', (t) async {
    final api = await open(t, _json(), {'community': 'public', 'version': 'v2c', 'web_user': 'root', 'web_pass': 'admin'});
    // الشيت قائمةٌ كسولة: يُبنى ما يقترب من الشاشة
    await t.scrollUntilVisible(field('كلمة مرور الصفحة'), 200, scrollable: find.byType(Scrollable).first);
    expect(find.text('دخول صفحة الأولت (اختياريّ)'), findsOneWidget);
    expect(t.widget<TextFormField>(field('اسم مستخدم الصفحة')).controller!.text, 'root');
    await t.enterText(field('كلمة مرور الصفحة'), 'new-pass');
    await t.scrollUntilVisible(find.text('حفظ التعديلات'), 200, scrollable: find.byType(Scrollable).first);
    await t.tap(find.text('حفظ التعديلات'));
    for (var i = 0; i < 30; i++) {
      await t.pump(const Duration(milliseconds: 200));
    }
    expect(api.puts, hasLength(1));
    expect(api.puts.single['credentials'], {'community': 'public', 'version': 'v2c', 'web_user': 'root', 'web_pass': 'new-pass'});
    expect(t.takeException(), isNull);
    await finish(t);
  });

  testWidgets('أولت VSOL ‏(SNMP): لا حقلا صفحة، والحفظ بالـcommunity وحدها', (t) async {
    final api = await open(t, _json(id: 77, brand: 'vsol'), {'community': 'public', 'version': 'v2c'});
    // حقل الـcommunity على الشاشة وما تحته مباشرةً — حيث يكون قسم الصفحة لو ظهر
    await t.scrollUntilVisible(field('Community string'), 150, scrollable: find.byType(Scrollable).first);
    expect(field('Community string'), findsOneWidget);
    expect(find.text('دخول صفحة الأولت (اختياريّ)'), findsNothing);
    expect(field('كلمة مرور الصفحة'), findsNothing);
    await t.scrollUntilVisible(find.text('حفظ التعديلات'), 200, scrollable: find.byType(Scrollable).first);
    await t.tap(find.text('حفظ التعديلات'));
    for (var i = 0; i < 30; i++) {
      await t.pump(const Duration(milliseconds: 200));
    }
    expect(api.puts.single['credentials'], {'community': 'public', 'version': 'v2c'});
    await finish(t);
  });

  testWidgets('HSGQ بلا دخول صفحة ⇒ لا مفتاحان فارغان في المحفوظ', (t) async {
    final api = await open(t, _json(), {'community': 'public', 'version': 'v2c'});
    await t.scrollUntilVisible(find.text('حفظ التعديلات'), 200, scrollable: find.byType(Scrollable).first);
    await t.tap(find.text('حفظ التعديلات'));
    for (var i = 0; i < 30; i++) {
      await t.pump(const Duration(milliseconds: 200));
    }
    expect(api.puts.single['credentials'], {'community': 'public', 'version': 'v2c'});
    await finish(t);
  });
}
