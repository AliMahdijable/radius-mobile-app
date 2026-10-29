import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/api/device_config_api.dart';
import 'package:rad_mysvcs/api/device_probe_api.dart';
import 'package:rad_mysvcs/models/device_health.dart';
import 'package:rad_mysvcs/models/subscriber.dart';
import 'package:rad_mysvcs/screens/subscribers/widgets/subscriber_card_v3.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// موجة فحص الأجهزة على خطٍّ بعيد (٢٩ أكتوبر — المالك على الماك: «الاشارات مال اجهزه مجاي تظهر شي مثل التطبيق حتى
/// بعد اكمال الفحص» + «من انقر ع المشترك يظهر المعلومات»). الماك يصل أجهزة المشتركين عبر VPN (ذهابٌ وإياب ~٠٫٦ث):
/// أربعون عاملاً خنقت النفق فتجاوزت الفحوص سقفها، والقراءة المتأخّرة تُرمى، و«فحص الأجهزة» يعيد الفشل المحفوظ نفسه.
class _NoServer implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    final body = o.uri.path == '/api/admin/device-defaults'
        ? {'success': true, 'defaults': <String, dynamic>{}}
        : o.uri.path == '/api/v2/subscribers/device-batch'
            ? {'success': true, 'configs': <String, dynamic>{}}
            : {'success': true};
    return ResponseBody.fromString(jsonEncode(body), 200, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}

DeviceHealthSnapshot _ont(String ip, String rx) => DeviceHealthSnapshot(
      kind: DeviceKind.ont,
      ip: ip,
      ont: OntOpticalInfo(txPower: '2.0', rxPower: rx, voltage: '3300', temperature: '48', bias: '10', sendStatus: ''),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    ApiClient.dio.httpClientAdapter = _NoServer();
    DeviceConfigApi.clearAllCaches();
    await DeviceProbeApi.clearAllCaches();
    DeviceProbeApi.debugCaps(probe: const Duration(milliseconds: 60), zteExtra: const Duration(milliseconds: 10));
    DeviceProbeApi.debugConnectTime = (_) async => const Duration(milliseconds: 4);
    DeviceProbeApi.onLateResult = null;
  });

  tearDown(() {
    DeviceProbeApi.debugRunProbe = null;
    DeviceProbeApi.debugConnectTime = null;
    DeviceProbeApi.onLateResult = null;
    DeviceProbeApi.debugCaps(probe: const Duration(seconds: 15), zteExtra: const Duration(seconds: 15));
  });

  test('قراءةٌ وصلت بعد سقف الفحص تُحفظ وتوقظ الجدول (كانت تُرمى)', () async {
    DeviceProbeApi.debugRunProbe =
        (ip) => Future.delayed(const Duration(milliseconds: 200), () => _ont(ip, '-19.5'));
    var woke = 0;
    DeviceProbeApi.onLateResult = () => woke++;

    final first = await DeviceProbeApi.probe(fallbackIp: '10.9.0.1', subscriberUsername: 'late1');
    expect(first, isNull, reason: 'تجاوز سقفه (٦٠ ملّي ث) فلا نتيجة الآن');
    expect(DeviceProbeApi.cachedForUser('late1'), isNull);

    await Future<void>.delayed(const Duration(milliseconds: 260));
    expect(DeviceProbeApi.cachedForUser('late1')?.ont?.rxPower, '-19.5', reason: 'القراءة المتأخّرة رُميت');
    expect(DeviceProbeApi.cached('10.9.0.1')?.ont?.rxPower, '-19.5');
    expect(DeviceProbeApi.issueFor(username: 'late1', ip: '10.9.0.1'), isNull, reason: 'سبب الفشل بقي بعد القراءة');
    expect(woke, 1);

    final sub = Subscriber.fromJson({'username': 'late1'}).copyWithOnline(online: true, ip: '10.9.0.1');
    expect(SubscriberNetworkMetrics.snapshotOf(sub)?.ont?.rxPower, '-19.5', reason: 'الجدول والبطاقة يقرآنها');
  });

  test('قراءةٌ متأخّرة لا تغطّي نتيجةً أحدث كُتبت بعدها', () async {
    var n = 0;
    DeviceProbeApi.debugRunProbe = (ip) {
      n++;
      return n == 1
          ? Future.delayed(const Duration(milliseconds: 200), () => _ont(ip, '-30.0'))
          : Future.value(_ont(ip, '-18.0'));
    };
    expect(await DeviceProbeApi.probe(fallbackIp: '10.9.0.2', subscriberUsername: 'late2'), isNull);
    final fresh = await DeviceProbeApi.probe(fallbackIp: '10.9.0.2', subscriberUsername: 'late2', force: true);
    expect(fresh?.ont?.rxPower, '-18.0');
    await Future<void>.delayed(const Duration(milliseconds: 260));
    expect(DeviceProbeApi.cachedForUser('late2')?.ont?.rxPower, '-18.0', reason: 'القديمة المتأخّرة غطّت الأحدث');
  });

  test('«فحص الأجهزة» يعيد الفحص فعلاً — لا يعيد الفشل المحفوظ (عمره دون خمس دقائق)', () async {
    var calls = 0;
    var answer = false;
    DeviceProbeApi.debugRunProbe = (ip) async {
      calls++;
      return answer ? _ont(ip, '-21.0') : null;
    };
    const targets = [(username: 'f1', ip: '10.9.0.3', company: null)];

    await DeviceProbeApi.warmProbe(targets);
    expect(calls, 1);
    expect(DeviceProbeApi.cachedForUser('f1'), isNull);

    answer = true;
    await DeviceProbeApi.warmProbe(targets);
    expect(calls, 1, reason: 'بلا إجبار: الفشل الطازج يُعاد من الكاش (كما كان)');

    DeviceProbeApi.invalidateIp('10.9.0.3');
    await DeviceProbeApi.warmProbe(targets, force: true);
    expect(calls, 2, reason: 'الإجبار لم يصل الجهاز — نتيجة المشترك المحفوظة عادت كما هي');
    expect(DeviceProbeApi.cachedForUser('f1')?.ont?.rxPower, '-21.0');
  });

  test('عدد العمّال بحسب بُعد الخطّ: VPN بعيد ⇒ ٨، شبكة الوكيل ⇒ ٤٠ كما كان', () async {
    DeviceProbeApi.debugRunProbe = (ip) async => null;
    final targets = [for (var i = 1; i <= 50; i++) (username: 'w$i', ip: '10.8.0.$i', company: null)];

    DeviceProbeApi.debugConnectTime = (_) async => const Duration(milliseconds: 565);
    await DeviceProbeApi.warmProbe(targets, force: true);
    expect(DeviceProbeApi.lastWaveWorkers, 8);

    DeviceProbeApi.debugConnectTime = (_) async => const Duration(milliseconds: 6);
    await DeviceProbeApi.warmProbe(targets, force: true);
    expect(DeviceProbeApi.lastWaveWorkers, 40);

    // لم يردّ اثنان (أجهزةٌ مطفأة) ⇒ لا حكم ⇒ كما كان.
    var k = 0;
    DeviceProbeApi.debugConnectTime = (_) async => k++ == 0 ? const Duration(seconds: 1) : null;
    await DeviceProbeApi.warmProbe(targets, force: true);
    expect(DeviceProbeApi.lastWaveWorkers, 40);

    // عددٌ صريح يغلب القياس.
    await DeviceProbeApi.warmProbe(targets, force: true, concurrency: 3);
    expect(DeviceProbeApi.lastWaveWorkers, 3);
  });

  test('الموجة تعيد ما قدُم (> ٥ دقائق) — والقراءة تبقى ظاهرةً حتى يحلّ محلّها أحدث', () async {
    DeviceProbeApi.debugRunProbe = (ip) async => _ont(ip, '-17.0');
    expect(DeviceProbeApi.needsProbe(username: 'st1', ip: '10.9.0.4'), isTrue, reason: 'المجهول يُفحص');
    await DeviceProbeApi.probe(fallbackIp: '10.9.0.4', subscriberUsername: 'st1');
    expect(DeviceProbeApi.needsProbe(username: 'st1', ip: '10.9.0.4'), isFalse, reason: 'الطازج لا يُعاد');

    DeviceProbeApi.debugBackdate(username: 'st1', ip: '10.9.0.4', by: const Duration(minutes: 6));
    expect(DeviceProbeApi.needsProbe(username: 'st1', ip: '10.9.0.4'), isTrue, reason: 'القديم لا تعيده الموجة أبداً');
    expect(DeviceProbeApi.cachedForUser('st1'), isNull, reason: 'الواجهة القديمة بمهلتها كما هي');

    final sub = Subscriber.fromJson({'username': 'st1'}).copyWithOnline(online: true, ip: '10.9.0.4');
    expect(SubscriberNetworkMetrics.snapshotOf(sub)?.ont?.rxPower, '-17.0',
        reason: 'القراءة اختفت من الجدول بعد خمس دقائق');
  });
}
