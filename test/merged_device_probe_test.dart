import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:rad_mysvcs/api/account_api.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/api/company_route.dart';
import 'package:rad_mysvcs/api/device_config_api.dart';
import 'package:rad_mysvcs/api/device_probe_api.dart';
import 'package:rad_mysvcs/screens/subscribers/sheets/device_config_sheet.dart';
import 'package:rad_mysvcs/screens/subscribers/widgets/device_probe_card.dart';
import 'package:rad_mysvcs/services/merged_mode.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'visual_perm/visual_perm_harness.dart';

/// «كل الشركات» — حالة الاتصال بكارت المشترك (إشارة الـONU والنانو، ٢٢ أكتوبر، المالك: «اريد كل الشركات هم»).
///
/// الفحص نفسه من الهاتف إلى الجهاز؛ ما يأتي من الخادم — إعداد جهاز المشترك (العنوان المحفوظ وبيانات الدخول) وافتراضات
/// المدير — يُقرأ من شركة الصفّ موجَّهاً، وكلّ كاشٍ بمفتاحها: اليوزر والعنوان فريدان داخل الساس الواحد وحده. والوضع العاديّ
/// بمفاتيحه القديمة حرفاً. وقاطع الدقيقة يحمي ميزانيّة الحساب للنداءات الموجَّهة (٦٠٠/١٠ د) من طلبٍ لكلّ مشترك.
const _kA = 'c0000000000aa';
const _kB = 'c0000000000bb';
const _kC = 'c0000000000cc';

ResponseBody _json(int status, Object body, {Map<String, List<String>> headers = const {}}) =>
    ResponseBody.fromString(jsonEncode(body), status, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
      ...headers,
    });

bool _isDevicePath(String p) =>
    p == '/api/v2/subscribers/device-batch' ||
    p == '/api/admin/device-defaults' ||
    RegExp(r'^/api/subscribers/[^/]+/device$').hasMatch(p);

/// خادمٌ وهميّ لمسارات إعداد الأجهزة الثلاثة (موجَّهةً بصدى المفتاح، وعاديّةً بلا توجيه)، والباقي للخادم المرئيّ.
class _DeviceServer implements HttpClientAdapter {
  _DeviceServer(this.inner);
  final HttpClientAdapter inner;
  final routed = <RequestOptions>[];
  final open = <RequestOptions>[];

  /// شركاتٌ يرفضها التوجيه (جلسةٌ انتهت) — 409 بنصٍّ عربيّ كالخادم.
  final failKeys = <String>{};

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    final path = o.uri.path;
    if (!_isDevicePath(path)) return inner.fetch(o, requestStream, cancelFuture);
    final key = o.headers['x-company-key'] as String?;
    (key == null ? open : routed).add(o);
    final h = <String, List<String>>{if (key != null) 'x-company-key': [key]};
    if (key != null && failKeys.contains(key)) {
      return _json(409, {
        'success': false,
        'code': 'COMPANY_SESSION_EXPIRED',
        'message': 'انتهت جلسة الشركة — افتحها مرّةً من «تبديل الشركة»',
      }, headers: h);
    }
    final tag = key == _kA ? 'A' : (key == _kB ? 'B' : 'open');
    if (path == '/api/admin/device-defaults') {
      return _json(200, {
        'success': true,
        'defaults': {
          'ontUsername': 'ont-$tag',
          'ontPassword': 'ontpw-$tag',
          'ubntUsername': 'ubnt-$tag',
          'ubntPassword': 'ubntpw-$tag',
        },
      }, headers: h);
    }
    if (path == '/api/v2/subscribers/device-batch') {
      final names = ((o.data as Map)['usernames'] as List).cast<String>();
      return _json(200, {
        'success': true,
        'configs': {
          for (final u in names)
            if (u == 'u1')
              u: {
                'customIp': tag == 'A' ? '10.1.1.1' : (tag == 'B' ? '10.2.2.2' : '10.0.0.1'),
                'notes': 'note-$tag',
              },
        },
      }, headers: h);
    }
    final u = Uri.decodeComponent(path.split('/')[3]);
    return _json(200, {'success': true, 'device': u == 'u3' ? {'notes': 'single-$tag'} : null}, headers: h);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  setUpAll(visualSetUpAll);

  late _DeviceServer srv;
  Future<void> up() async {
    final inner = await visualSetUp(s1bSasOwner);
    srv = _DeviceServer(inner);
    ApiClient.dio.httpClientAdapter = srv;
    AccountApi.tokenSource = ({bool force = false}) async => 'acct-1';
    CompanyRefs.reset();
    DeviceConfigApi.clearAllCaches();
    await DeviceProbeApi.clearAllCaches();
  }

  Future<void> down() async {
    DeviceConfigApi.clearAllCaches();
    await DeviceProbeApi.clearAllCaches();
    await visualTearDown();
  }

  // أوّلاً: الاستعادة من القرص مرّةٌ واحدة في العمليّة.
  test('لقطة الجهاز بشركتها: صفٌّ لا يقرأ قراءة العنوان نفسه في شركةٍ أخرى ولا في المفتوحة', () async {
    final now = DateTime.now().toIso8601String();
    SharedPreferences.setMockInitialValues({
      'device_probe.cache.v1': jsonEncode({
        '$_kA|10.0.0.5': {'at': now, 'snap': {'k': 'ont', 'ip': '10.0.0.5'}},
        '10.0.0.6': {'at': now, 'snap': {'k': 'ubiquiti', 'ip': '10.0.0.6'}},
      }),
    });
    await DeviceProbeApi.hydrateFromPrefs();
    expect(DeviceProbeApi.peek(ip: '10.0.0.5', company: _kA)?.snap, isNotNull);
    expect(DeviceProbeApi.cached('10.0.0.5', company: _kA), isNotNull);
    expect(DeviceProbeApi.peek(ip: '10.0.0.5'), isNull, reason: 'الشركة المفتوحة لا ترى قراءة صفٍّ مدموج');
    expect(DeviceProbeApi.peek(ip: '10.0.0.5', company: _kB), isNull, reason: 'ولا شركةٌ أخرى بالعنوان نفسه');
    expect(DeviceProbeApi.cached('10.0.0.6'), isNotNull, reason: 'الوضع العاديّ بمفاتيحه القديمة');
    expect(DeviceProbeApi.cached('10.0.0.6', company: _kA), isNull);
  });

  test('المفتاح: الوضع العاديّ كما كان حرفاً، وصفّ «كل الشركات» بشركته', () {
    expect(DeviceConfigApi.scoped(null, 'u1'), 'u1');
    expect(DeviceConfigApi.scoped('', 'u1'), 'u1');
    expect(DeviceConfigApi.scoped(_kA, 'u1'), '$_kA|u1');
    expect(MergedOps.unsupportedAt(null), isNull);
    expect(MergedOps.unsupportedAt(_kA), contains('الشركة وحدها'));
  });

  test('إعداد الجهاز: دفعةٌ لكلّ شركةٍ بمفتاحها بلا توكن المفتوحة، واليوزر نفسه في شركتين لا يلتبس', () async {
    await up();
    expect(await DeviceConfigApi.warmBatch(['u1', 'u2'], company: _kA), isTrue);
    expect(await DeviceConfigApi.warmBatch(['u1', 'u2'], company: _kB), isTrue);
    expect(srv.routed.map((o) => o.headers['x-company-key']), [_kA, _kB]);
    for (final o in srv.routed) {
      expect(o.headers['Authorization'], isNull, reason: 'توكن الشركة المفتوحة لا يخرج مع طلبٍ موجَّه');
      expect(o.headers['x-account-token'], 'acct-1');
    }
    expect(DeviceConfigApi.peekConfig('u1', company: _kA)?.customIp, '10.1.1.1');
    expect(DeviceConfigApi.peekConfig('u1', company: _kB)?.customIp, '10.2.2.2');
    expect(DeviceConfigApi.peekConfig('u2', company: _kA), isNotNull, reason: 'مفحوصٌ بلا إعداد = فارغ لا مجهول');
    expect(DeviceConfigApi.peekConfig('u2', company: _kA)?.customIp, isNull);
    expect(DeviceConfigApi.peekConfig('u1'), isNull, reason: 'الوضع العاديّ لم يسأل بعد');
    // من الكاش بلا طلب
    final n = srv.routed.length;
    expect((await DeviceConfigApi.fetchConfig('u1', company: _kB))?.notes, 'note-B');
    expect(srv.routed.length, n);
    // يوزرٌ خارج الدفعة ⇒ GET واحد موجَّه لشركته
    expect((await DeviceConfigApi.fetchConfig('u3', company: _kA))?.notes, 'single-A');
    expect(srv.routed.last.uri.path, '/api/subscribers/u3/device');
    expect(srv.routed.last.headers['x-company-key'], _kA);
    // والعاديّ بلا توجيه، بتوكن الجلسة المفتوحة
    expect((await DeviceConfigApi.fetchConfig('u3'))?.notes, 'single-open');
    expect(srv.open.single.headers['x-company-key'], isNull);
    expect(srv.open.single.headers['Authorization'], isNotNull);
    await down();
  });

  test('افتراضات الأجهزة لكلّ شركة (مرّةً لكلٍّ)، والعاديّة من الشركة المفتوحة', () async {
    await up();
    final a = await DeviceProbeApi.resolveUbntCreds(fallbackIp: '10.9.9.9', subscriberUsername: 'u9', company: _kA);
    final b = await DeviceProbeApi.resolveUbntCreds(fallbackIp: '10.9.9.9', subscriberUsername: 'u9', company: _kB);
    final o = await DeviceProbeApi.resolveOntCreds(fallbackIp: '10.9.9.9', subscriberUsername: 'u9');
    expect([a?.user, a?.pass], ['ubnt-A', 'ubntpw-A']);
    expect([b?.user, b?.pass], ['ubnt-B', 'ubntpw-B']);
    expect([o?.user, o?.pass], ['ont-open', 'ontpw-open']);
    expect((await DeviceProbeApi.resolveOntCreds(fallbackIp: '10.9.9.9', subscriberUsername: 'u9', company: _kA))?.user,
        'ont-A');
    final defaults = srv.routed.where((r) => r.uri.path == '/api/admin/device-defaults');
    expect(defaults.map((r) => r.headers['x-company-key']).toList(), [_kA, _kB], reason: 'نجاح الافتراضات يُحفظ للجلسة');
    expect(srv.open.where((r) => r.uri.path == '/api/admin/device-defaults'), hasLength(1));
    // العنوان المحفوظ في شركة الصفّ يغلب عنوان الراديوس
    await DeviceConfigApi.warmBatch(['u1'], company: _kB);
    final u1 = await DeviceProbeApi.resolveUbntCreds(fallbackIp: '10.9.9.9', subscriberUsername: 'u1', company: _kB);
    expect(u1?.ip, '10.2.2.2');
    await down();
  });

  test('شركةٌ رفضها التوجيه: لا طلبٌ آخر لها دقيقةً، ولا يُحفظ رفضها كـ«لا إعداد»، والأخرى تعمل', () async {
    await up();
    srv.failKeys.add(_kC);
    expect((await DeviceConfigApi.fetchConfig('u1', company: _kC))?.customIp, isNull);
    expect(DeviceConfigApi.routedDown(_kC), isTrue);
    expect(DeviceConfigApi.routedDown(_kA), isFalse);
    expect(DeviceConfigApi.routedDown(null), isFalse, reason: 'الوضع العاديّ بلا قاطع');
    expect(DeviceConfigApi.peekConfig('u1', company: _kC), isNull, reason: 'الرفض ليس «لا إعداد»');
    final n = srv.routed.length;
    await DeviceConfigApi.fetchConfig('u2', company: _kC);
    expect(await DeviceConfigApi.warmBatch(['u5'], company: _kC), isFalse);
    final c = await DeviceProbeApi.resolveUbntCreds(fallbackIp: '10.9.9.9', subscriberUsername: 'u2', company: _kC);
    expect(c?.user, 'ubnt', reason: 'افتراض المكتبة حين لا تُعرف افتراضات الشركة الآن');
    expect(srv.routed.length, n, reason: 'القاطع: صفر طلبات لشركةٍ رُفضت');
    expect(await DeviceConfigApi.warmBatch(['u1'], company: _kA), isTrue);
    expect(srv.routed.length, n + 1);
    await down();
  });

  test('موجة «كل الشركات»: دفعة إعداداتٍ لكلّ شركة، وما لا عنوان له في شركته يُسقط بلا فحص', () async {
    await up();
    final progress = <List<int>>[];
    await DeviceProbeApi.warmProbe([
      (username: 'u2', ip: '', company: _kA),
      (username: 'u2', ip: '', company: _kB),
      (username: 'u4', ip: '', company: null),
    ], onProgress: (d, t) => progress.add([d, t]));
    final batches = srv.routed.where((o) => o.uri.path == '/api/v2/subscribers/device-batch');
    expect(batches.map((o) => o.headers['x-company-key']).toSet(), {_kA, _kB});
    expect(srv.open.where((o) => o.uri.path == '/api/v2/subscribers/device-batch'), hasLength(1));
    expect(progress, [
      [0, 0]
    ], reason: 'لا عنوان راديوس ولا محفوظ في أيّ شركة ⇒ لا فحص');

    // شركةٌ رُفضت: صفوفها بلا عنوان لا تُفحص (ولا تسأل عن إعدادٍ واحداً واحداً)، والشركة الأخرى كما هي
    srv.failKeys.add(_kC);
    srv.routed.clear();
    progress.clear();
    await DeviceProbeApi.warmProbe([
      (username: 'u7', ip: '', company: _kC),
      (username: 'u8', ip: '', company: _kC),
      (username: 'u2', ip: '', company: _kA),
    ], onProgress: (d, t) => progress.add([d, t]));
    expect(progress, [
      [0, 0]
    ]);
    expect(srv.routed.where((o) => o.headers['x-company-key'] == _kC), hasLength(1), reason: 'الدفعة وحدها، ثمّ القاطع');
    expect(srv.routed.where((o) => o.uri.path == '/api/subscribers/u7/device'), isEmpty);
    await down();
  });

  testWidgets('كارت الجهاز لصفٍّ مدموج: إعداده من شركته، وزرّ الإعدادات يقول «للشركة وحدها» ولا يفتح الحفظ', (t) async {
    await up();
    await pumpVisual(t, phone,
        home: (_) => const Scaffold(
              body: SingleChildScrollView(
                child: DeviceProbeCard(username: 'u2', company: _kA),
              ),
            ));
    await settle(t, seconds: 2);
    expect(
        srv.routed.where((o) => o.uri.path == '/api/subscribers/u2/device' && o.headers['x-company-key'] == _kA),
        isNotEmpty,
        reason: 'إعداد الجهاز من شركة الصفّ');
    expect(srv.open.where((o) => o.uri.path == '/api/subscribers/u2/device'), isEmpty,
        reason: 'لا شيء من الشركة المفتوحة');
    await t.tap(find.byIcon(LucideIcons.settings));
    await settle(t, seconds: 1);
    expect(find.textContaining('يعمل من الشركة وحدها'), findsOneWidget);
    expect(find.byType(DeviceConfigSheet), findsNothing);
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 6));
    await down();
  });
}
