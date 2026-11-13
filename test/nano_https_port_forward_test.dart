import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/api/device_probe_api.dart';
import 'package:rad_mysvcs/models/device_health.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// مشتركٌ خلف بورت فورورد — المالك ١٤ نوفمبر: «النانوات تفحص https لان بورت فورود اغلبه يستخدمون المشتركين ٨٠» و«من واحد يشتغل
/// من الاجهزه الثاني ميرجع ترفك فقط واحد يرد». المقيس على جهازه: 443 ⇒ airOS (النانو)، 80 ⇒ صفحة دخول Tenda، 22 ⇒ dropbear (النانو).
///
/// كان ردّ الراوتر على 80 يحسم نوع العنوان وحده فلا يُجرَّب النانو، وعنوان «IP:443» يُعطى لـSSH بمنفذه فلا يتّصل الترافيك.
void main() {
  late HttpServer router;
  var routerHits = 0;
  late _Api api;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    routerHits = 0;
    // راوتر Tenda على «الـ80»: صفحة دخوله تعرّفه، ودخوله مرفوضٌ هنا (لا يهمّ)
    router = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    router.listen((req) async {
      routerHits++;
      final res = req.response..headers.set('Server', 'GoAhead-Webs');
      if (req.uri.path == '/login.html') {
        res.headers.contentType = ContentType.html;
        res.write('<html><title>Tenda</title><form action="/login/Auth"></form></html>');
      } else {
        res.statusCode = 404;
      }
      await res.close();
    });
    api = _Api();
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
    DeviceProbeApi.invalidateAdminDefaults();
    await DeviceProbeApi.clearAllCaches();
  });

  tearDown(() async {
    DeviceProbeApi.debugAirOsHttps = null;
    DeviceProbeApi.debugProbeUbntHttps = null;
    await router.close(force: true);
  });

  DeviceHealthSnapshot nano(String ip) => DeviceHealthSnapshot(
        kind: DeviceKind.ubiquiti,
        ip: ip,
        ubnt: UbiquitiStatus.fromJson({'sig': -38, 'ccq': 98, 'hn': 'nano'}),
      );

  test('عنوان SSH: الآيبي وحده حين يحمل العنوان منفذ الويب', () {
    expect(DeviceProbeApi.sshHost('100.64.1.2:443'), '100.64.1.2');
    expect(DeviceProbeApi.sshHost(' 10.0.0.5:8443 '), '10.0.0.5');
    expect(DeviceProbeApi.sshHost('10.0.0.5'), '10.0.0.5');
    expect(DeviceProbeApi.sshHost('cpe.example'), 'cpe.example', reason: 'اسمٌ لا يُمسّ');
  });

  test('airOS يردّ على https والراوتر على 80 ⇒ الجهاز الأوّل هو النانو، والتالي يذهب للنانو على https وحده', () async {
    final host = '127.0.0.1:${router.port}';
    var nanoReads = 0;
    DeviceProbeApi.debugAirOsHttps = (_) async => true;
    DeviceProbeApi.debugProbeUbntHttps = (ip) async {
      nanoReads++;
      return nano(ip);
    };
    final first = await DeviceProbeApi.probe(fallbackIp: host, force: true);
    expect(first?.kind, DeviceKind.ubiquiti, reason: 'كان ردّ Tenda على 80 يحسم وحده فلا يُجرَّب النانو');
    expect(first?.ubnt?.vendor, 'ubnt');
    expect(first?.ip, host, reason: 'اللقطة بعنوان المشترك نفسه');
    expect(nanoReads, 1);
    final hitsAfterFirst = routerHits;
    final second = await DeviceProbeApi.probe(fallbackIp: host, force: true);
    expect(second?.kind, DeviceKind.ubiquiti);
    expect(nanoReads, 2, reason: 'النوع محفوظ: النانو على https');
    expect(routerHits, hitsAfterFirst, reason: 'لا طلب على راوتر الـ80 بعد أن عُرف النانو');
  });

  test('airOS على https ولم يُقرأ النانو (اعتماده مرفوض) ⇒ الراوتر كما كان — لا أسوأ من قبل', () async {
    final host = '127.0.0.1:${router.port}';
    DeviceProbeApi.debugAirOsHttps = (_) async => true;
    DeviceProbeApi.debugProbeUbntHttps = (_) async => null;
    final snap = await DeviceProbeApi.probe(fallbackIp: host, force: true);
    expect(snap, isNull, reason: 'راوتر الاختبار بلا كلمة سرّ');
    expect(DeviceProbeApi.issueFor(ip: host)?.vendor, 'tenda', reason: 'فرع الراوتر جُرِّب بعد النانو');
  });

  test('لا airOS على https ⇒ الراوتر يحسم كما كان، والنانو لا يُسأل', () async {
    final host = '127.0.0.1:${router.port}';
    var nanoReads = 0;
    DeviceProbeApi.debugAirOsHttps = (_) async => false;
    DeviceProbeApi.debugProbeUbntHttps = (ip) async {
      nanoReads++;
      return nano(ip);
    };
    await DeviceProbeApi.probe(fallbackIp: host, force: true);
    expect(nanoReads, 0);
    expect(DeviceProbeApi.issueFor(ip: host)?.vendor, 'tenda');
  });
}

class _Api implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? body, Future<void>? cancel) async {
    final Object data = o.uri.path == '/api/admin/device-defaults' ? {'success': true, 'defaults': <String, Object?>{}} : {'success': true};
    return ResponseBody.fromString(jsonEncode(data), 200, headers: {
      Headers.contentTypeHeader: ['application/json'],
    });
  }

  @override
  void close({bool force = false}) {}
}
