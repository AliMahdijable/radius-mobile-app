import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/api/olt_profile.dart';
import 'package:rad_mysvcs/api/vsol_olt_api.dart';
import 'package:rad_mysvcs/models/fiber_network.dart';
import 'package:rad_mysvcs/models/network_device.dart';
import 'package:rad_mysvcs/services/fiber/fiber_monitor.dart';
import 'package:rad_mysvcs/services/fiber/fiber_onu.dart';
import 'package:rad_mysvcs/services/fiber/fiber_store.dart';
import 'package:rad_mysvcs/services/fiber/fiber_watch.dart';
import 'package:rad_mysvcs/services/permissions_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// حفظ شبكة الألياف بلا خسارة: الخادم يرفض ⇒ لا يبقى على الشاشة نصفُ محفوظ؛ الخادم بلا المسارات ⇒ يُحفظ على الجهاز
/// ويُرفع أوّل ما يجيب (الصناديق قبل أجهزتها)؛ الخروج لا يمحو ما لم يصل بعد. ومراقبة الحاسبة بالخلفيّة لما بدأ الوكيل
/// يرتّبه وحده.
class _Server implements HttpClientAdapter {
  final List<RequestOptions> requests = [];

  /// 404 = الخادم بلا مسارات الألياف بعد؛ 500 = رفض.
  int status = 200;
  Map<String, dynamic> layout = {'success': true, 'boxes': [], 'onus': [], 'settings': [], 'events': [], 'caps': {}};
  int nextBox = 100;

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? body, Future<void>? cancel) async {
    requests.add(o);
    final p = o.uri.path;
    if (status != 200) {
      return ResponseBody.fromString(jsonEncode({'success': false, 'message': 'رفض الخادم'}), status, headers: {
        Headers.contentTypeHeader: ['application/json'],
      });
    }
    final b = o.data is Map ? Map<String, dynamic>.from(o.data as Map) : <String, dynamic>{};
    Object data = {'success': true};
    if (p == '/api/v2/admin/devices/fiber' && o.method == 'GET') data = layout;
    if (p.startsWith('/api/v2/admin/devices/fiber/boxes/') && o.method == 'PUT') {
      data = {'success': true, 'box': {...b, 'id': nextBox++}};
    }
    if (p == '/api/v2/admin/devices/fiber/onus') data = {'success': true, 'saved': (b['records'] as List?)?.length ?? 0};
    return ResponseBody.fromString(jsonEncode(data), 200, headers: {
      Headers.contentTypeHeader: ['application/json'],
    });
  }

  @override
  void close({bool force = false}) {}

  List<RequestOptions> to(String path, [String method = 'POST']) =>
      requests.where((r) => r.uri.path == path && r.method == method).toList();
}

FiberOnuLive _onu(int id, {String? mac}) => FiberOnuLive(
      onu: VsolOnu(ifIndex: 300 + id, slot: 0, ponPort: 3, onuId: id, online: true, mac: mac, technology: VsolPonTechnology.epon),
    );

NetworkDevice _olt(int id, {String brand = 'bdcom', String model = 'BDCOM P3600-04'}) => NetworkDevice(
      id: id,
      adminId: '2',
      name: 'OLT $id',
      type: 'other',
      brand: brand,
      model: model,
      ip: '10.0.0.$id',
      port: 161,
      apiPort: 161,
      protocol: 'snmp',
      hasCredentials: true,
      lastStatus: 'online',
      createdAt: DateTime.utc(2026),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Server server;

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({'auth.token': 't', 'auth.admin_id': '2'});
    SharedPreferences.setMockInitialValues({});
    server = _Server();
    ApiClient.dio.httpClientAdapter = server;
    FiberStore.reset();
    FiberMonitor.debugReset();
    FiberWatch.debugReset();
    PermissionsService.debugReset();
  });

  tearDown(() {
    FiberWatch.debugReset();
    FiberMonitor.debugReset();
  });

  test('الخادم يرفض حفظ صندوق ⇒ لا صندوق نصف محفوظ ولا نسخةٌ ثانية عند الإعادة', () async {
    await FiberStore.ensureLoaded();
    server.status = 500;
    final r = await FiberStore.saveBox(const FiberBox(id: 0, oltId: 9, pon: 'EPON0/3', name: 'صندوق 3-أ'));
    expect(r.ok, isFalse);
    expect(r.message, 'رفض الخادم');
    expect(FiberStore.layout.value.boxes, isEmpty);
    server.status = 200;
    final again = await FiberStore.saveBox(const FiberBox(id: 0, oltId: 9, pon: 'EPON0/3', name: 'صندوق 3-أ'));
    expect(again.ok, isTrue);
    expect(FiberStore.layout.value.boxes.keys, [100]);
  });

  test('الخادم يرفض الربط ⇒ يرجع الجهاز بلا ربط كما كان', () async {
    await FiberStore.ensureLoaded();
    server.status = 500;
    final r = await FiberStore.link(9, _onu(1), 'ali');
    expect(r.ok, isFalse);
    expect(FiberStore.layout.value.recordFor(9, 'EPON0/3:1', null), isNull);
  });

  test('اليوزر لجهازٍ واحد: ربطه بجهازٍ ثانٍ يفكّه من الأوّل بنفس الحفظ', () async {
    await FiberStore.ensureLoaded();
    await FiberStore.link(9, _onu(1), 'ali');
    await FiberStore.link(9, _onu(2), 'Ali');
    final l = FiberStore.layout.value;
    expect(l.recordFor(9, 'EPON0/3:1', null)?.username, isNull);
    expect(l.recordFor(9, 'EPON0/3:2', null)?.username, 'Ali');
    final last = server.to('/api/v2/admin/devices/fiber/onus').last.data as Map;
    expect((last['records'] as List).length, 2, reason: 'الفكّ والربط بطلبٍ واحد');
    expect(FiberStore.linkedTo(9, 'ALI')?.key, 'EPON0/3:2');
  });

  test('خادمٌ بلا المسارات ⇒ يُحفظ على الجهاز، ويُرفع أوّل ما يجيب: الصندوق ثمّ أجهزته والإعدادات', () async {
    server.status = 404;
    await FiberStore.ensureLoaded();
    expect(FiberStore.serverReady, isFalse);
    final box = await FiberStore.saveBox(const FiberBox(id: 0, oltId: 9, pon: 'EPON0/3', name: 'صندوق 3-أ'));
    expect(box.ok, isTrue);
    expect(box.box!.id, lessThan(0), reason: 'رقمٌ محلّيّ');
    await FiberStore.assign(9, [_onu(1), _onu(2)], box.box!.id);
    await FiberStore.link(9, _onu(1), 'ali');
    await FiberStore.saveSettings(const FiberOltSettings(oltId: 9, techPhone: '07701234567'));
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('fiber.pending.v1.2'), isTrue);

    // الدخول التالي والخادم صار يجيب
    FiberStore.reset();
    server.status = 200;
    server.requests.clear();
    await FiberStore.ensureLoaded();
    expect(FiberStore.serverReady, isTrue);
    final l = FiberStore.layout.value;
    expect(l.boxes.keys, [100], reason: 'الصندوق برقم الخادم');
    expect(l.recordFor(9, 'EPON0/3:1', null)?.boxId, 100);
    expect(l.recordFor(9, 'EPON0/3:1', null)?.username, 'ali');
    expect(l.recordFor(9, 'EPON0/3:2', null)?.boxId, 100);
    expect(l.settingsOf(9).techPhone, '07701234567');
    final boxPut = server.requests.indexWhere((r) => r.uri.path.startsWith('/api/v2/admin/devices/fiber/boxes/'));
    final onusPost = server.requests.indexWhere((r) => r.uri.path == '/api/v2/admin/devices/fiber/onus');
    expect(boxPut, greaterThanOrEqualTo(0));
    expect(onusPost, greaterThan(boxPut), reason: 'الصندوق قبل أجهزته');
    final recs = (server.requests[onusPost].data as Map)['records'] as List;
    expect(recs.every((r) => (r as Map)['box_id'] == 100), isTrue);
    expect(server.to('/api/v2/admin/devices/fiber/settings/9', 'PUT').length, 1);
    expect(prefs.getBool('fiber.pending.v1.2'), isNull, reason: 'رُفع كلّه ⇒ لا علم');
  });

  test('ما عند الخادم أصلاً لا يُكتب فوقه عند رفع المحلّيّ', () async {
    server.status = 404;
    await FiberStore.ensureLoaded();
    await FiberStore.link(9, _onu(1), 'local');
    FiberStore.reset();
    server.status = 200;
    server.layout = {
      'success': true,
      'boxes': [],
      'onus': [
        {'olt_id': 9, 'onu_key': 'EPON0/3:1', 'username': 'server', 'link_source': 'manual'},
      ],
      'settings': [],
      'events': [],
      'caps': {},
    };
    server.requests.clear();
    await FiberStore.ensureLoaded();
    expect(FiberStore.layout.value.recordFor(9, 'EPON0/3:1', null)?.username, 'server');
    expect(server.to('/api/v2/admin/devices/fiber/onus'), isEmpty);
  });

  test('الخروج: يمحو النسخ المحفوظة — إلّا تخطيط حسابٍ عنده ما لم يصل الخادم', () async {
    SharedPreferences.setMockInitialValues({
      'fiber.layout.v1.2': '{}',
      'fiber.rx.v1.2.9': '{}',
      'fiber.layout.v1.7': '{}',
      'fiber.pending.v1.7': true,
      'fiber.rx.v1.7.9': '{}',
      'other.key': 1,
    });
    await FiberStore.clear();
    final p = await SharedPreferences.getInstance();
    expect(p.getKeys(), {'fiber.layout.v1.7', 'fiber.pending.v1.7', 'other.key'});
  });

  test('مراقبة الحاسبة: أولتٌ بدأ الوكيل يرتّبه وتنبيهاته شغّالة فقط — والإيقاف يفكّ الكلّ', () async {
    FiberStore.debugSet(FiberLayout.empty
        .withBox(const FiberBox(id: 1, oltId: 9, pon: 'EPON0/3', name: 'صندوق'))
        .withSettings(const FiberOltSettings(oltId: 11, notifyOutages: false, notifyPower: false))
        .withRecord(const FiberOnuRecord(oltId: 12, key: 'EPON0/1:1', username: 'x')));
    FiberWatch.devices = () async => [_olt(9), _olt(10), _olt(11), _olt(12), _olt(13, brand: 'mikrotik', model: 'CCR')];
    FiberMonitor.backend = const _Silent();
    FiberWatch.start();
    await FiberWatch.sync();
    expect(FiberWatch.held, {9, 12}, reason: '10 لم يُرتَّب، و11 تنبيهاته مطفأة، و13 ليس أولت');
    expect(FiberMonitor.existing(9)!.background, isTrue);

    FiberStore.debugSet(FiberStore.layout.value.withSettings(const FiberOltSettings(oltId: 9, notifyOutages: false)));
    await FiberWatch.sync();
    expect(FiberWatch.held, {12});
    expect(FiberMonitor.existing(9)!.running, isFalse);

    FiberWatch.stop();
    expect(FiberWatch.held, isEmpty);
    expect(FiberMonitor.existing(12)!.running, isFalse);
  });

  test('مراقبة الحاسبة: بلا صلاحيّة مراقبة الأجهزة لا يُقرأ أيّ أولت', () async {
    PermissionsService.debugSet(isEmployee: true, permissions: const {'devices.view': true});
    FiberStore.debugSet(FiberLayout.empty.withBox(const FiberBox(id: 1, oltId: 9, pon: 'EPON0/3', name: 'صندوق')));
    FiberWatch.devices = () async => [_olt(9)];
    FiberWatch.start();
    await FiberWatch.sync();
    expect(FiberWatch.held, isEmpty);
    expect(FiberMonitor.existing(9), isNull);
  });

  test('رقم الجهاز من مفتاحه المحفوظ', () {
    expect(fiberOnuKeyDisplay('EPON0/3:7'), 'ONU 3:7');
    expect(fiberOnuKeyDisplay('GPON1/2:15'), 'ONU 1/2:15');
    expect(fiberOnuKeyDisplay('غريب'), 'غريب');
  });
}

/// مصدرٌ لا يجيب — المراقبة تُحسب بلا قراءة (هذا الاختبار عن من يُراقَب لا عمّا يُقرأ).
class _Silent extends FiberBackend {
  const _Silent();
  @override
  Future<String?> community(NetworkDevice d) async => null;
  @override
  Future<VsolOltStats> structure(NetworkDevice d, String community, OltProfile p, {Map<int, String>? knownNames}) async => const VsolOltStats();
}
