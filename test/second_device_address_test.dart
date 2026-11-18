import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/api/device_config_api.dart';
import 'package:rad_mysvcs/api/device_probe_api.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// «الجهاز الثاني» بـ«:منفذ» على عنوان الجهاز الأوّل (١٨ نوفمبر — المالك عن z@zz: ضوئيّ HG8342R على 100.92.63.190 وراوتر
/// WR940N على :8080، «ليش مجاي يعرض الاثنين»). العنوان مثبَّت ولا جلسة بالساس ⇒ كان «:8080» يُحلّ على آيبي الجلسة الفارغ ⇒ لا هدف
/// ⇒ «لم يُتمكّن من الوصول للجهاز» والراوتر واصل.
class _Api implements HttpClientAdapter {
  Map<String, Object?> device = {};

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? body, Future<void>? cancel) async {
    final Object data = o.uri.path.endsWith('/device') ? {'success': true, 'device': device} : {'success': true, 'defaults': {}};
    return ResponseBody.fromString(jsonEncode(data), 200, headers: {
      Headers.contentTypeHeader: ['application/json'],
    });
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  test('«:منفذ» يُحلّ على عنوان الجهاز الأوّل (المثبَّت وإلّا الجلسة)، والعنوان الكامل كما هو', () {
    expect(DeviceProbeApi.secondAddressOf('', '100.92.63.190', ':8080'), '100.92.63.190:8080', reason: 'مثبَّت ولا جلسة (z@zz)');
    expect(DeviceProbeApi.secondAddressOf('10.1.1.1', '100.92.63.190', ':8080'), '100.92.63.190:8080', reason: 'مثبَّت وجلسةٌ بآيبي آخر');
    expect(DeviceProbeApi.secondAddressOf('10.1.1.1', '', ':8080'), '10.1.1.1:8080', reason: 'لا تثبيت ⇒ الجلسة كما كان');
    expect(DeviceProbeApi.secondAddressOf('10.1.1.1', null, ':8080'), '10.1.1.1:8080');
    expect(DeviceProbeApi.secondAddressOf('10.1.1.1', '100.9.9.9:9090', ':8080'), '100.9.9.9:8080', reason: 'الأوّل بمنفذ ⇒ مضيفه وحده');
    expect(DeviceProbeApi.secondAddressOf('10.1.1.1', ':9090', ':8080'), '10.1.1.1:8080', reason: 'الأوّل «:منفذ» على الجلسة');
    expect(DeviceProbeApi.secondAddressOf('', '', ':8080'), '', reason: 'لا عنوان أصلاً ⇒ لا هدف');
    expect(DeviceProbeApi.secondAddressOf('10.1.1.1', '100.9.9.9', '192.168.1.1'), '192.168.1.1');
    expect(DeviceProbeApi.secondAddressOf('10.1.1.1', '100.9.9.9', '192.168.1.1:8080'), '192.168.1.1:8080');
    expect(DeviceProbeApi.secondAddressOf('10.1.1.1', '100.9.9.9', ''), '');
    expect(DeviceProbeApi.secondAddressOf('10.1.1.1', '100.9.9.9', null), '');
    expect(DeviceProbeApi.hostOnly('100.9.9.9:9090'), '100.9.9.9');
    expect(DeviceProbeApi.hostOnly('100.9.9.9'), '100.9.9.9');
  });

  test('الفحص يطرق الراوتر على عنوان الجهاز الأوّل المثبَّت حين لا جلسة بالساس', () async {
    SharedPreferences.setMockInitialValues({});
    await DeviceProbeApi.clearAllCaches();
    final server = await ServerSocket.bind('127.0.0.1', 0);
    final hit = Completer<void>();
    server.listen((s) {
      if (!hit.isCompleted) hit.complete();
      s.destroy();
    });
    addTearDown(server.close);
    final api = _Api()
      ..device = {'customIp': '127.0.0.1', 'secondAddress': ':${server.port}', 'secondUsername': 'admin', 'secondPassword': 'x'};
    final adapter = ApiClient.dio.httpClientAdapter;
    final interceptors = List<Interceptor>.of(ApiClient.dio.interceptors);
    ApiClient.dio.httpClientAdapter = api;
    ApiClient.dio.interceptors.clear();
    addTearDown(() {
      ApiClient.dio.httpClientAdapter = adapter;
      ApiClient.dio.interceptors
        ..clear(keepImplyContentTypeInterceptor: false)
        ..addAll(interceptors);
    });
    const user = 'second-host-user';
    final cfg = await DeviceConfigApi.fetchConfig(user);
    expect(cfg?.secondAddress, ':${server.port}');
    final ok = await DeviceProbeApi.reachable(slot: 2, fallbackIp: '', subscriberUsername: user, force: true);
    expect(ok, isTrue, reason: 'كان null: «:منفذ» على آيبي جلسةٍ فارغ ⇒ لا هدف');
    await hit.future.timeout(const Duration(seconds: 3)); // الاتّصال وصل الراوتر الوهميّ نفسه
  });
}
