import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/api/device_config_api.dart';
import 'package:rad_mysvcs/api/device_probe_api.dart';
import 'package:rad_mysvcs/api/network_devices_api.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// N+1 (٢٤ نوفمبر — المالك: «كمل على الباقي» بعد تدقيق N+1): طلبات التطبيق جهازاً جهازاً.
///  ١) اعتمادات الأجهزة: [NetworkDevicesApi.prefetchCredentials] بطلبٍ واحد (GET /api/v2/admin/devices/credentials?ids=) يملأ المخبأ
///     فلا يسأل كلّ جهازٍ وحده — كانت ١٦ ألف طلب/يوم وحتى ٥٠ بالدقيقة من هاتف. ما لم يرجع يُسأل وحده كما كان، وخادمٌ أقدم ⇒ لا يُعاد.
///  ٢) موجة فحص المشتركين أطول من عمر مخبأ الإعدادات (٥ د): كانت تسأل عن إعداد كلّ مشترك بعدها وحده (GET /api/subscribers/:u/device
///     — حتى ٤٤ بالدقيقة)؛ الآن أوّل هدفٍ شاخ يجدّد إعدادات الخمسين التي تبدأ به بطلبٍ واحد (device-batch).
class _Server implements HttpClientAdapter {
  final List<String> log = [];
  int batchStatus = 200;
  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    final p = o.uri.path;
    log.add(p == '/api/v2/admin/devices/credentials' ? '$p?ids=${o.uri.queryParameters['ids']}' : p);
    Object body = {'success': true};
    var status = 200;
    if (p == '/api/v2/admin/devices/credentials') {
      status = batchStatus;
      final ids = (o.uri.queryParameters['ids'] ?? '').split(',');
      body = {
        'success': true,
        'credentials': {for (final id in ids) if (id != '3') id: id == '2' ? <String, dynamic>{} : {'user': 'admin', 'pass': 'p$id'}},
        'missing': ['3'],
      };
    } else if (RegExp(r'^/api/v2/admin/devices/\d+/credentials$').hasMatch(p)) {
      body = {'success': true, 'credentials': {'user': 'solo', 'pass': 'x'}};
    } else if (p == '/api/admin/device-defaults') {
      body = {'success': true, 'defaults': <String, dynamic>{}};
    } else if (p == '/api/v2/subscribers/device-batch') {
      body = {'success': true, 'configs': <String, dynamic>{}};
    } else if (p.endsWith('/device')) {
      body = {'success': true, 'device': null};
    }
    return ResponseBody.fromString(jsonEncode(body), status, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Server server;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    server = _Server();
    ApiClient.dio.httpClientAdapter = server;
    NetworkDevicesApi.invalidateCredentialsCache();
    NetworkDevicesApi.debugResetCredentialsBatch();
    DeviceConfigApi.clearAllCaches();
    await DeviceProbeApi.clearAllCaches();
  });

  tearDown(() {
    DeviceProbeApi.debugRunProbe = null;
  });

  test('١ اعتمادات عدّة أجهزة بطلبٍ واحد، ثمّ getCredentials من المخبأ بلا طلب؛ ما لم يرجع يُسأل وحده كما كان', () async {
    await NetworkDevicesApi.prefetchCredentials([1, 2, 3, 2]);
    expect(server.log, ['/api/v2/admin/devices/credentials?ids=1,2,3']);
    expect(await NetworkDevicesApi.getCredentials(1), {'user': 'admin', 'pass': 'p1'});
    expect(await NetworkDevicesApi.getCredentials(2), <String, dynamic>{}, reason: 'بلا اعتماد ⇒ {} كالمسار الواحد');
    expect(server.log.length, 1, reason: 'لا طلب لكلّ جهاز');
    expect(await NetworkDevicesApi.getCredentials(3), {'user': 'solo', 'pass': 'x'});
    expect(server.log.last, '/api/v2/admin/devices/3/credentials', reason: 'ما لم يرجع ⇒ طلبه وحده');
    // الطازج لا يُعاد طلبه، والواحد وحده لا يستحقّ دفعة
    await NetworkDevicesApi.prefetchCredentials([1, 2, 3]);
    await NetworkDevicesApi.prefetchCredentials([9]);
    expect(server.log.length, 2);
  });

  test('٢ خادمٌ أقدم بلا المسار (٤٠٤) ⇒ يُتذكَّر فلا يُعاد، وكلٌّ يسأل وحده كما كان', () async {
    server.batchStatus = 404;
    await NetworkDevicesApi.prefetchCredentials([5, 6]);
    await NetworkDevicesApi.prefetchCredentials([7, 8]);
    expect(server.log, ['/api/v2/admin/devices/credentials?ids=5,6']);
    expect(await NetworkDevicesApi.getCredentials(5), {'user': 'solo', 'pass': 'x'});
    expect(server.log.last, '/api/v2/admin/devices/5/credentials');
  });

  test('٣ موجةٌ أطول من عمر مخبأ الإعدادات: الشائخ يُجدَّد بطلبٍ لكلّ خمسين، لا طلبٌ لكلّ مشترك', () async {
    final targets = [for (var i = 0; i < 120; i++) (username: 'u$i', ip: '10.0.${i ~/ 250}.${i % 250 + 1}', company: null)];
    var probes = 0;
    DeviceProbeApi.debugRunProbe = (ip) async {
      probes++;
      if (probes == 10) DeviceConfigApi.debugAgeAll(const Duration(minutes: 6)); // مرّت ست دقائق في منتصف الموجة
      return null;
    };
    await DeviceProbeApi.warmProbe(targets, concurrency: 4);
    expect(probes, 120);
    final batches = server.log.where((p) => p == '/api/v2/subscribers/device-batch').length;
    final singles = server.log.where((p) => RegExp(r'^/api/subscribers/[^/]+/device$').hasMatch(p)).length;
    expect(singles, lessThanOrEqualTo(4), reason: 'كان ≈١١٠ طلباً لكلّ مشترك بعد شيخوخة المخبأ (السجلّ: ${server.log.length})');
    expect(batches, inInclusiveRange(2, 8), reason: 'دفعة البدء + تجديدٌ لكلّ خمسين');
  });

  test('٤ دفعة البدء تعذّرت ⇒ لا تجديد في هذه الموجة: كلٌّ يسأل وحده كما كان', () async {
    final failing = _FailingBatch(server);
    ApiClient.dio.httpClientAdapter = failing;
    final targets = [for (var i = 0; i < 30; i++) (username: 'f$i', ip: '10.1.0.${i + 1}', company: null)];
    DeviceProbeApi.debugRunProbe = (ip) async => null;
    await DeviceProbeApi.warmProbe(targets, concurrency: 4);
    expect(failing.batches, 1, reason: 'دفعة البدء وحدها — لا محاولات تجديدٍ فاشلة');
  });
}

class _FailingBatch implements HttpClientAdapter {
  _FailingBatch(this.inner);
  final _Server inner;
  int batches = 0;
  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    if (o.uri.path == '/api/v2/subscribers/device-batch') {
      batches++;
      return ResponseBody.fromString(jsonEncode({'success': false}), 200, headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      });
    }
    return inner.fetch(o, requestStream, cancelFuture);
  }

  @override
  void close({bool force = false}) {}
}
