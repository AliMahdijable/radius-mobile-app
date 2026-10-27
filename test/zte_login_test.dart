import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/api/device_probe_api.dart';
import 'package:rad_mysvcs/core/net/zte_ont_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// دخول جهاز المشترك ZTE MH80 (٢٧ أكتوبر، المالك: «خليت يوزر وباسورد وميجلب شي… شوفلي التصحيح من السيرفر لو من
/// التطبيق؟»): الجهاز يصل والتعرّف يعمل، والعطب كان بالتطبيق — كلّ فشلٍ (حتى انقطاع) يُحفظ «اعتماداتٍ مرفوضة» فلا تُعاد،
/// و«حفظ وفحص الجهاز» لا يمسح الرفض حين الـIP من الساس، والكرت يقول «لم يُتمكّن من الوصول» لكلّ سبب.
///
/// جهازٌ وهميّ على 127.0.0.1 (خادم HTTP حقيقيّ) بنفس شكل صفحة الجهاز الحيّ؛ الاعتمادات هنا وهميّة.
void main() {
  late _FakeMh80 d;

  setUp(() async {
    d = _FakeMh80();
    await d.start();
  });

  tearDown(() => d.stop());

  group('الدخول', () {
    test('اعتماداتٌ صحيحة ⇒ جلسة، والكوكي يصل صفحة الضوء', () async {
      final s = await ZteOntService.loginConfigured(d.host, 'agent', 'secret-1');
      expect(s, isNotNull);
      final o = await ZteOntService.fetchOptical(s!);
      expect(o?.rxPower, '-18.6');
      expect(o?.vendor, 'zte');
      expect(d.pageCookie, 'SID=s1');
      expect(ZteOntService.lastIssue(d.host), isNull);
    });

    test('دخولٌ بلا كوكي (جلسةٌ بالعنوان) ⇒ ناجح، وصفحة الضوء بلا ترويسة كوكي فارغة', () async {
      d.setCookie = false;
      final s = await ZteOntService.loginConfigured(d.host, 'agent', 'secret-1');
      expect(s, isNotNull, reason: 'التحويل إلى start.ghtml هو النجاح — الكوكي ليس شرطاً');
      expect(await ZteOntService.fetchOptical(s!), isNotNull);
      expect(d.pageCookie, isNull);
    });

    test('اعتمادٌ غلط ⇒ «رُفض» ويُحفظ فلا يُعاد؛ النسيان («حفظ وفحص») يعيده مرّة', () async {
      expect(await ZteOntService.loginConfigured(d.host, 'agent', 'wrong'), isNull);
      expect(ZteOntService.lastIssue(d.host)?.issue, ZteLoginIssue.rejected);
      expect(d.posts, hasLength(1));
      expect(await ZteOntService.loginConfigured(d.host, 'agent', 'wrong'), isNull);
      expect(d.posts, hasLength(1), reason: 'المرفوض لا يُعاد — ثلاث محاولاتٍ غلط تقفل الجهاز دقيقة');
      ZteOntService.forget(d.host);
      expect(await ZteOntService.loginConfigured(d.host, 'agent', 'wrong'), isNull);
      expect(d.posts, hasLength(2));
      expect(await ZteOntService.loginConfigured(d.host, 'agent', 'secret-1'), isNotNull, reason: 'اعتماداتٌ غيرها تُجرَّب فوراً');
    });

    test('انقطاع الاتّصال عند الإرسال ليس رفضاً ⇒ الفحص التالي يحاول', () async {
      d.dropPost = true;
      expect(await ZteOntService.loginConfigured(d.host, 'agent', 'secret-1'), isNull);
      expect(ZteOntService.lastIssue(d.host)?.issue, ZteLoginIssue.unreachable);
      d.dropPost = false;
      expect(await ZteOntService.loginConfigured(d.host, 'agent', 'secret-1'), isNotNull,
          reason: 'كان يُحفظ مرفوضاً فلا يُعاد طول الجلسة');
    });

    test('قافلٌ ⇒ لا إرسال، والباقي من عدّاد الصفحة نفسها', () async {
      d.lockAt = 402900; // 402900 + 60 - 402930 = 30
      expect(await ZteOntService.loginConfigured(d.host, 'agent', 'secret-1'), isNull);
      final i = ZteOntService.lastIssue(d.host)!;
      expect(i.issue, ZteLoginIssue.locked);
      expect(i.lockLeft, 30);
      expect(d.posts, isEmpty, reason: 'كلّ محاولةٍ على جهازٍ قافل تُحسب عليه');
    });

    test('اعتماداتٌ دخلت قبل ورُفضت الآن ⇒ «مشغول» لا «رُفض»، ولا تُحفظ', () async {
      expect(await ZteOntService.loginConfigured(d.host, 'agent', 'secret-1'), isNotNull);
      d.sessionOpen = true;
      expect(await ZteOntService.loginConfigured(d.host, 'agent', 'secret-1'), isNull);
      expect(ZteOntService.lastIssue(d.host)?.issue, ZteLoginIssue.busy);
      d.sessionOpen = false;
      expect(await ZteOntService.loginConfigured(d.host, 'agent', 'secret-1'), isNull,
          reason: 'مرّةٌ بالدقيقة على الأكثر — جلسة الترافيك تعيد كلّ ١٢ ثانية وكلّ رفضٍ قد يُحسب على القفل');
      expect(d.posts, hasLength(2));
      expect(ZteOntService.lastIssue(d.host)?.trace, 'cooldown');
      ZteOntService.forget(d.host); // «حفظ وفحص» أو انقضاء الدقيقة
      expect(await ZteOntService.loginConfigured(d.host, 'agent', 'secret-1'), isNotNull,
          reason: 'جلسةٌ مفتوحة لا تقفل الوكيل عن جهازه باعتماداتٍ صحيحة');
    });

    test('عدّاد القفل كما على MH80 الحيّ', () {
      expect(ZteOntParse.lockLeft('maxtime = Math.min(60, 0 + 60 - 402930);'), isNull);
      expect(ZteOntParse.lockLeft('maxtime = Math.min(60, 402900 + 60 - 402930);'), 30);
      expect(ZteOntParse.lockLeft('<html>بلا عدّاد</html>'), isNull);
    });
  });

  group('فحص جهاز المشترك', () {
    late _FakeApi api;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      api = _FakeApi();
      final adapter = ApiClient.dio.httpClientAdapter;
      final interceptors = List<Interceptor>.of(ApiClient.dio.interceptors);
      ApiClient.dio.httpClientAdapter = api;
      ApiClient.dio.interceptors.clear();
      addTearDown(() {
        ApiClient.dio.httpClientAdapter = adapter;
        ApiClient.dio.interceptors
          ..clear()
          ..addAll(interceptors);
      });
      DeviceProbeApi.invalidateAdminDefaults();
    });

    test('جهاز ZTE ⇒ القراءة من فرع ZTE، وطلبات هواوي لا تطرقه', () async {
      api.defaults = {'ontUsername': 'agent', 'ontPassword': 'secret-1'};
      final snap = await DeviceProbeApi.probe(fallbackIp: d.host, force: true);
      expect(snap?.ont?.vendor, 'zte');
      expect(snap?.ont?.rxPower, '-18.6');
      expect(d.paths.where((p) => p.contains('GetRandCount') || p.contains('login.cgi')), isEmpty);
      expect(DeviceProbeApi.issueFor(ip: d.host), isNull);
    });

    test('بلا يوزر من الوكيل ⇒ لا دخول على ZTE بافتراضٍ من عندنا، والسبب «يحتاج يوزر وباسورد»', () async {
      final snap = await DeviceProbeApi.probe(fallbackIp: d.host, force: true);
      expect(snap, isNull);
      expect(d.posts, isEmpty);
      expect(DeviceProbeApi.issueFor(ip: d.host)?.issue, ProbeIssue.needsCredentials);
    });

    test('رفضٌ ثمّ «حفظ وفحص» بنفس الاعتمادات ⇒ يحاول مرّةً أخرى، والتشخيص يصل بلا اعتمادات', () async {
      api.defaults = {'ontUsername': 'agent', 'ontPassword': 'wrong-pass'};
      expect(await DeviceProbeApi.probe(fallbackIp: d.host, force: true), isNull);
      expect(DeviceProbeApi.issueFor(ip: d.host)?.issue, ProbeIssue.loginRejected);
      await DeviceProbeApi.probe(fallbackIp: d.host, force: true);
      expect(d.posts, hasLength(1), reason: 'التحديث العاديّ لا يعيد المرفوض');
      await DeviceProbeApi.probe(fallbackIp: d.host, force: true, retryLogin: true);
      expect(d.posts, hasLength(2), reason: '«حفظ وفحص الجهاز» يحاول ولو بقي الـIP من الساس');
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final diag = api.requests.where((r) => r.uri.path == '/api/client-diag').toList();
      expect(diag, hasLength(1), reason: 'التشخيص للمحاولة الصريحة وحدها');
      final body = diag.single.data as Map;
      expect(body['code'], 'loginRejected');
      expect('${body['message']}', contains('post:200'));
      expect(jsonEncode(body), isNot(contains('wrong-pass')));
      expect(jsonEncode(body), isNot(contains('agent')));
    });

    test('ZTE بطيء بصفحة الضوء ⇒ يُمهَل بدل أن يُقطع بلا سبب (أوّل «حفظ وفحص» على MH80)', () async {
      DeviceProbeApi.debugCaps(probe: const Duration(milliseconds: 600), zteExtra: const Duration(seconds: 3));
      addTearDown(() => DeviceProbeApi.debugCaps(probe: const Duration(seconds: 15), zteExtra: const Duration(seconds: 15)));
      api.defaults = {'ontUsername': 'agent', 'ontPassword': 'secret-1'};
      d.pageDelay = const Duration(milliseconds: 1500);
      final snap = await DeviceProbeApi.probe(fallbackIp: d.host, force: true, retryLogin: true);
      expect(snap?.ont?.rxPower, '-18.6', reason: 'كان يُقطع عند المهلة وصفحة الضوء في الطريق');
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final diag = api.requests.where((r) => r.uri.path == '/api/client-diag').single.data as Map;
      expect(diag['code'], 'ok');
    });

    test('جهازٌ لا يجاوب لا يُمهَل — موجة القائمة لا تنتظره', () async {
      DeviceProbeApi.debugCaps(probe: const Duration(milliseconds: 600), zteExtra: const Duration(seconds: 3));
      addTearDown(() => DeviceProbeApi.debugCaps(probe: const Duration(seconds: 15), zteExtra: const Duration(seconds: 15)));
      // منفذٌ يقبل الاتّصال ولا يردّ أبداً
      final silent = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final held = <Socket>[];
      silent.listen(held.add);
      addTearDown(() async {
        for (final s in held) {
          s.destroy();
        }
        await silent.close();
      });
      final sw = Stopwatch()..start();
      final snap = await DeviceProbeApi.probe(fallbackIp: '127.0.0.1:${silent.port}', force: true, retryLogin: true);
      expect(snap, isNull);
      expect(sw.elapsed, lessThan(const Duration(seconds: 2)), reason: 'التعرّف وحده جارٍ ⇒ لا مهلة إضافيّة');
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final diag = api.requests.where((r) => r.uri.path == '/api/client-diag').single.data as Map;
      expect('${diag['message']}', contains('timeout'));
      expect('${diag['message']}', contains('steps=detect+'));
    });

    test('جهازٌ لا يجاوب ⇒ «لم يُتمكّن من الوصول»', () async {
      final port = d.server.port;
      await d.stop();
      final snap = await DeviceProbeApi.probe(fallbackIp: '127.0.0.1:$port', force: true);
      expect(snap, isNull);
      expect(DeviceProbeApi.issueFor(ip: '127.0.0.1:$port')?.issue, ProbeIssue.unreachable);
    });
  });
}

/// ZTE MH80 وهميّ: صفحة دخولٍ بعدّاد القفل ورمز النموذج كالجهاز الحيّ، ودخولٌ بنموذجٍ إلى `/`، وصفحة ضوء.
class _FakeMh80 {
  late HttpServer server;
  bool setCookie = true;
  bool dropPost = false;
  bool sessionOpen = false;
  int lockAt = 0;
  Duration pageDelay = Duration.zero;
  final posts = <String>[];
  final paths = <String>[];
  String? pageCookie;
  bool _stopped = false;

  String get host => '127.0.0.1:${server.port}';

  String _loginPage() => '<html><head><title>MH80</title><script>\n'
      'maxtime = Math.min(60, $lockAt + 60 - 402930);\n'
      'getObj("Frm_Logintoken").value = "9";\n'
      '</script></head><body><form name="fLogin" id="fLogin" method="post">'
      '<input type="hidden" name="Frm_Logintoken" id="Frm_Logintoken" value=""></form></body></html>';

  static const _optical = '<html><head><title>MH80</title></head><body><script>\n'
      'var LosInfo = "0";\nvar RxPower = "-186300";\nvar TxPower = "25900";\nvar Current = "13850";\n'
      '</script><td id="Frm_Volt">3244000</td><td id="Frm_Temp">41</td></body></html>';

  Future<void> start() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      paths.add('${req.method} ${req.uri.path}');
      final res = req.response;
      res.headers.set('Server', 'Mini web server 1.0 ZTE corp 2005.');
      if (req.method == 'POST' && req.uri.path == '/') {
        final body = await utf8.decoder.bind(req).join();
        if (body.contains('logout=1')) {
          res.statusCode = 302;
          res.headers.set('Location', '/');
          await res.close();
          return;
        }
        posts.add(body);
        if (dropPost) {
          (await res.detachSocket(writeHeaders: false)).destroy();
          return;
        }
        final f = Uri.splitQueryString(body);
        final ok = !sessionOpen &&
            f['action'] == 'login' &&
            f['Frm_Logintoken'] == '9' &&
            f['username'] == 'agent' &&
            f['Password'] == 'secret-1';
        if (ok) {
          res.statusCode = 302;
          res.headers.set('Location', '/start.ghtml');
          if (setCookie) res.headers.add('Set-Cookie', 'SID=s1; path=/');
        } else {
          res.headers.contentType = ContentType.html;
          res.write(_loginPage());
        }
        await res.close();
        return;
      }
      if (req.uri.path == '/getpage.gch') {
        pageCookie = req.headers.value('cookie');
        if (pageDelay > Duration.zero) await Future<void>.delayed(pageDelay);
        res.headers.contentType = ContentType.html;
        res.write(_optical);
        await res.close();
        return;
      }
      if (req.uri.path == '/') {
        res.headers.contentType = ContentType.html;
        res.write(_loginPage());
        await res.close();
        return;
      }
      res.statusCode = 404;
      await res.close();
    });
  }

  Future<void> stop() async {
    if (_stopped) return;
    _stopped = true;
    await server.close(force: true);
  }
}

/// خادم التطبيق الوهميّ: افتراضات الأجهزة والتشخيص.
class _FakeApi implements HttpClientAdapter {
  Map<String, String> defaults = {};
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? body, Future<void>? cancel) async {
    requests.add(o);
    final Object data = o.uri.path == '/api/admin/device-defaults' ? {'success': true, 'defaults': defaults} : {'success': true};
    return ResponseBody.fromString(jsonEncode(data), 200, headers: {
      Headers.contentTypeHeader: ['application/json'],
    });
  }

  @override
  void close({bool force = false}) {}
}
