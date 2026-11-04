// «كل الشركات» (٤ نوفمبر): قراءات أجهزة صفوف كلّ شركةٍ تُرفع لشركتها بطلبٍ موجَّه (x-company-key) وبحالتها هي — لا تذهب
// للشركة المفتوحة، ولا تمسّ حالتها (شارتها وقسمها)، ولا تُسقط قائمة الشركة فتُجلب من جديد بعد كلّ موجة فحص. بخادمٍ وهميّ يردّ
// صدى المفتاح كالخادم (server/companyRouting.js).
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/api/company_route.dart';
import 'package:rad_mysvcs/api/connection_auto_api.dart';
import 'package:rad_mysvcs/models/device_health.dart';
import 'package:rad_mysvcs/models/subscriber.dart';
import 'package:rad_mysvcs/services/connection_readings_uploader.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _a = 'c0123456789ab';
const _b = 'cba9876543210';
const _c = 'c00000000000f';
const _readings = '/api/v2/connection-alerts/readings';
const _auto = '/api/v2/connection-alerts/auto';

class _Server implements HttpClientAdapter {
  final List<RequestOptions> requests = [];

  /// حالة «تنبيه المشترك» وردّ رفع القراءات لكلّ شركة ('' = الجلسة المفتوحة بلا توجيه).
  final Map<String, Object> status = {};
  final Map<String, Object> readings = {};

  static String keyOf(RequestOptions o) => (o.headers['x-company-key'] ?? '').toString();

  List<RequestOptions> to(String method, String path, [String? key]) => requests
      .where((r) => r.method == method && r.uri.path == path && (key == null || keyOf(r) == key))
      .toList();

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? body, Future<void>? cancel) async {
    requests.add(o);
    final key = keyOf(o);
    Object data = {'success': true};
    if (o.uri.path == _auto) data = status[key] ?? {'success': true, 'data': {'available': false}};
    if (o.uri.path == _readings) data = readings[key] ?? {'success': true, 'data': {'active': true}};
    return ResponseBody.fromString(jsonEncode(data), 200, headers: {
      Headers.contentTypeHeader: ['application/json'],
      // الطلب الموجَّه يُقبل بصدى مفتاحه وحده (api_client._onRoutedResponse) — كالخادم
      if (key.isNotEmpty) 'x-company-key': [key],
    });
  }

  @override
  void close({bool force = false}) {}
}

Map<String, dynamic> _on({int pending = 0}) => {
      'success': true,
      'data': {
        'available': true,
        'dry_run': true,
        'alerts_enabled': true,
        'settings': {'mode': 'approval', 'remind_days': 3, 'max_sends': 3, 'daily_cap': 30, 'hour_from': 10, 'hour_to': 20,
          'confirm_min': 30, 'kinds': ['cable', 'signal', 'ccq', 'fiber_rx', 'fiber_temp']},
        'counts': {'pending': pending},
        'in_window': true,
      },
    };

Subscriber _sub(String idx, [String? company]) => Subscriber.fromJson({
      'idx': idx,
      'username': 'u$idx',
      'firstname': 'مشترك',
      'lastname': idx,
      'phone': '07701234567',
      'expiration': DateTime.now().add(const Duration(days: 10)).toIso8601String(),
      'enabled': 1,
    }).withCompany(company);

DeviceHealthSnapshot _snap([int signal = -70]) => DeviceHealthSnapshot(
      kind: DeviceKind.ubiquiti,
      ip: '10.0.0.2',
      ubnt: UbiquitiStatus(
        hostname: 'nano',
        firmware: 'XW.v6.3',
        uptimeSeconds: 100,
        ssid: 'AP',
        mode: 'sta',
        signalDbm: signal,
        noiseFloorDbm: -95,
        ccqPercent: 95,
        distanceMeters: 800,
        txRateKbps: 0,
        rxRateKbps: 0,
        lanPorts: const [LanPort(name: 'eth0', speed: '100Mbps-Full', plugged: true)],
        peerMac: null,
        peerCount: null,
        baseUrl: 'http://10.0.0.2',
      ),
    );

List<String> _idxs(RequestOptions r) => [for (final x in (r.data as Map)['readings'] as List) '${(x as Map)['idx']}'];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Server server;

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({'auth.token': 'sim-token', 'auth.admin_id': '2'});
    SharedPreferences.setMockInitialValues({});
    server = _Server();
    ApiClient.dio.httpClientAdapter = server;
    ConnectionAutoApi.debugReset();
    ConnectionReadingsUploader.debugReset();
    ConnectionReadingsUploader.debugSnapshotOf = (_) => _snap();
  });

  test('كلّ شركةٍ لشركتها بطلبٍ موجَّه والمفتوحة بلا توجيه؛ المطفأة لا ترفع؛ مفتاحٌ غير صالح لا يُرفع أبداً؛ وحالة المفتوحة لا تُمسّ',
      () async {
    server.status[''] = _on(pending: 7);
    server.status[_a] = _on(pending: 1);
    server.status[_c] = _on();
    // _b مطفأة (لا ردّ ⇒ available false)
    final subs = [
      _sub('1'), _sub('2'), // المفتوحة
      _sub('1', _a), _sub('3', _a), // الاسم u1 نفسه في شركةٍ أخرى
      _sub('4', _b),
      _sub('5', _c),
      _sub('6', 'nbtel:9'), // مفتاحٌ غير صالح
    ];
    await ConnectionReadingsUploader.collect(subs);
    final posts = server.to('POST', _readings);
    expect(posts.map(_Server.keyOf), ['', _a, _c], reason: 'المفتوحة أوّلاً ثمّ كلّ شركةٍ مفعّلة — لا _b');
    expect(_idxs(posts[0]), ['1', '2']);
    expect(_idxs(posts[1]), ['1', '3']);
    expect(_idxs(posts[2]), ['5']);
    expect(posts[0].headers['x-company-key'], isNull, reason: 'المفتوحة بجلستها كما كانت');
    expect(posts.expand(_idxs), isNot(contains('6')), reason: 'صفٌّ بمفتاحٍ غير صالح لا يذهب للمفتوحة');
    expect(server.to('GET', _auto, _b), hasLength(1));
    expect(ConnectionAutoApi.status.value.count('pending'), 7, reason: 'شارة المفتوحة من حالتها هي لا حالة شركةٍ موجَّهة');

    // موجةٌ ثانية قبل ١٥ دقيقة: لا رفع (لكلّ شركةٍ ومشترك)، والحالات من الكاش
    await ConnectionReadingsUploader.collect(subs);
    expect(server.to('POST', _readings), hasLength(3));
    expect(server.to('GET', _auto, _a), hasLength(1));
    expect(server.to('GET', _auto, _b), hasLength(1));
  });

  test('تحت المراقبة لصفّ شركة: الموعد بمفتاحها، والفحص بشركتها، والرفع موجَّهٌ لها', () async {
    final due = DateTime.now().add(const Duration(minutes: 3));
    server.status[_a] = _on();
    server.readings[_a] = {
      'success': true,
      'data': {'active': true, 'recheck': [{'username': 'u3', 'due_ms': due.millisecondsSinceEpoch}]},
    };
    final probed = <String?>[];
    ConnectionReadingsUploader.debugProbe = (s) async {
      probed.add(s.companyKey);
      return _snap(-72);
    };
    await ConnectionReadingsUploader.collect([_sub('3', _a)]);
    expect(ConnectionReadingsUploader.pendingRechecks.keys, ['$_a|u3']);
    expect(await ConnectionReadingsUploader.runRechecks(now: due.subtract(const Duration(seconds: 30))), 0);
    server.readings[_a] = {'success': true, 'data': {'active': true, 'confirmed': 1, 'recheck': []}};
    expect(await ConnectionReadingsUploader.runRechecks(now: due.add(const Duration(seconds: 1))), 1);
    expect(probed, [_a], reason: 'فحصٌ مُجبَر لجهازه بشركته');
    final last = server.to('POST', _readings).last;
    expect((_Server.keyOf(last), ((last.data as Map)['readings'] as List).single['signal']), (_a, -72));
    expect(ConnectionReadingsUploader.pendingRechecks, isEmpty);
    expect(server.to('GET', _auto, ''), isEmpty, reason: 'لا شيء للمفتوحة');
  });

  test('الرفع الموجَّه لا يُسقط قائمة الشركة (ولا القراءة بـPOST) — والكتابة على المشترك تُسقطها كما كانت', () async {
    final prev = CompanyRoute.onWrite;
    final dropped = <String>[];
    CompanyRoute.onWrite = dropped.add;
    addTearDown(() => CompanyRoute.onWrite = prev);
    server.status[_a] = _on();
    await ConnectionReadingsUploader.collect([_sub('3', _a)]);
    expect(server.to('POST', _readings, _a), hasLength(1));
    await CompanyRoute.run(_a, () => ApiClient.dio.post<dynamic>('/api/v2/subscribers/device-batch', data: {'usernames': ['u3']}));
    expect(dropped, isEmpty);
    await CompanyRoute.run(_a, () => ApiClient.dio.post<dynamic>('/api/v2/subscribers/3/pay-debt', data: {'amount': 1}));
    expect(dropped, [_a]);
  });

  test('الخادم يقول «لا قياس» لشركة ⇒ تُقرأ حالتها هي من جديد (لا حالة المفتوحة) فيتوقّف رفعها', () async {
    server.status[_a] = _on();
    server.readings[_a] = {'success': true, 'data': {'active': false}};
    await ConnectionReadingsUploader.collect([_sub('3', _a)]);
    server.status.remove(_a); // أُطفئ
    await ConnectionReadingsUploader.collect([_sub('8', _a)]);
    expect(server.to('GET', _auto, _a), hasLength(2), reason: 'الكاش سقط بالردّ');
    expect(server.to('POST', _readings), hasLength(1));
    expect(server.to('GET', _auto, ''), isEmpty, reason: 'لا قراءة لحالة المفتوحة بسبب شركةٍ أخرى');
  });

  test('«افحص الآن» للشركة المفتوحة وحدها (زرّ قسمها)', () async {
    server.status[''] = _on();
    server.status[_a] = _on();
    final r = await ConnectionReadingsUploader.collectNow([_sub('1'), _sub('2', _a)]);
    expect(r?.sent, 1);
    final posts = server.to('POST', _readings);
    expect(posts.map(_Server.keyOf), ['']);
    expect(_idxs(posts.single), ['1']);
  });
}
