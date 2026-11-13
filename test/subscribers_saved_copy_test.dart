// «آخر نسخة محفوظة فوراً» (١٣ نوفمبر ٢٠٢٦ — المالك: «اهم شي يكون سريع الاستجابه»، بعد بلاغ «فايبر لنك كربلاء»: سيرفر
// شركته يحتاج ~٢٢ثانية للقائمة كاملة). شاشة المشتركين تعرض آخر نسخةٍ ناجحة على الجهاز لحظة الفتح بعلامة «نجلب الأحدث…»،
// والطازجة تحلّ محلّها حين تصل. خادمٌ وهميّ يؤخّر القائمة الكاملة.
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/api/big_subscribers_api.dart';
import 'package:rad_mysvcs/api/subscribers_api.dart';
import 'package:rad_mysvcs/screens/subscribers/subscribers_screen.dart';
import 'package:rad_mysvcs/screens/subscribers/widgets/filter_chips_bar.dart';
import 'package:rad_mysvcs/services/subscribers_offline_cache.dart';

import 'visual_perm/visual_perm_harness.dart';

/// يؤخّر القائمة الكاملة وحدها (GET /api/v2/subscribers بلا page) — ساسٌ بطيء.
class _SlowList implements HttpClientAdapter {
  _SlowList(this.inner, this.delay);

  final HttpClientAdapter inner;
  final Duration delay;
  int fullAsked = 0;

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? s, Future<void>? c) async {
    if (o.method.toUpperCase() == 'GET' && o.path == '/api/v2/subscribers' && o.queryParameters['page'] == null) {
      fullAsked++;
      await Future<void>.delayed(delay);
    }
    return inner.fetch(o, s, c);
  }

  @override
  void close({bool force = false}) {}
}

Map<String, dynamic> _savedRow() => {
      'idx': '9001',
      'username': 'saved.only@copy',
      'firstname': 'نسخة',
      'lastname': 'محفوظة',
      'profile_name': 'باقة',
      'profile_id': 7,
      'expiration': '2026-12-01 10:00:00',
      'remaining_days': 5,
      'enabled': 1,
    };

Future<void> _diskCatchUp(WidgetTester t) async {
  for (var i = 0; i < 8; i++) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
    await t.pump(const Duration(milliseconds: 30));
  }
}

void main() {
  setUpAll(visualSetUpAll);

  // النسخة المحفوظة ملفٌّ في مجلّد الذاكرة المؤقّتة (path_provider) — بلا منصّةٍ في الاختبار: مجلّدٌ مؤقّت.
  late Directory dir;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('subs_saved_copy_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => dir.path,
    );
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'), null);
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {/* مجلّدٌ مؤقّت */}
  });

  testWidgets('ساسٌ بطيء: آخر نسخةٍ محفوظة تظهر لحظة الفتح بعلامة «نجلب الأحدث…»، ثمّ تحلّ محلّها الطازجة وتختفي العلامة', (t) async {
    final inner = await visualSetUp(s1bSasOwner);
    final srv = _SlowList(inner, const Duration(seconds: 6));
    ApiClient.dio.httpClientAdapter = srv;
    BigSubscribersApi.reset();
    SubscribersApi.clearAllCaches();
    await t.runAsync(() => SubscribersOfflineCache.save([_savedRow()]));

    final cmd = ValueNotifier<SubscriberFilter?>(SubscriberFilter.all);
    await pumpVisual(t, phone, home: (_) => SubscribersScreen(filterCmd: cmd));
    // قراءة القرص حقيقيّة (لا تتقدّم بـpump) وبخطوات (وجود الملفّ، قراءته): وقتٌ حقيقيّ قصير ثمّ إطار، مرّاتٍ
    await _diskCatchUp(t);

    expect(srv.fullAsked, greaterThanOrEqualTo(1), reason: 'القائمة الكاملة طُلبت ولم تصل بعد');
    expect(find.text('saved.only@copy'), findsWidgets, reason: 'النسخة المحفوظة معروضة فوراً');
    expect(find.textContaining('نجلب الأحدث'), findsOneWidget, reason: 'بعلامتها');

    await settle(t, seconds: 8);
    expect(find.textContaining('نجلب الأحدث'), findsNothing, reason: 'الطازجة وصلت ⇒ لا علامة');
    expect(find.text('saved.only@copy'), findsNothing, reason: 'حلّت محلّها الطازجة');

    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 1));
    await t.runAsync(SubscribersOfflineCache.clear);
  });

  testWidgets('بلا نسخةٍ محفوظة: كما كان — لا علامة، والقائمة حين تصل', (t) async {
    final inner = await visualSetUp(s1bSasOwner);
    final srv = _SlowList(inner, const Duration(seconds: 2));
    ApiClient.dio.httpClientAdapter = srv;
    BigSubscribersApi.reset();
    SubscribersApi.clearAllCaches();
    await t.runAsync(SubscribersOfflineCache.clear);

    final cmd = ValueNotifier<SubscriberFilter?>(SubscriberFilter.all);
    await pumpVisual(t, phone, home: (_) => SubscribersScreen(filterCmd: cmd));
    await _diskCatchUp(t);
    expect(find.textContaining('نجلب الأحدث'), findsNothing);
    await settle(t, seconds: 4);
    expect(find.textContaining('نجلب الأحدث'), findsNothing);
    expect(find.textContaining('نسخة محفوظة'), findsNothing);

    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 1));
    await t.runAsync(SubscribersOfflineCache.clear);
  });

  test('عمر النسخة المعروضة فوراً ≤ ١٢ ساعة (أقصر من نسخة الانقطاع: ٣ أيّام)', () {
    expect(SubscribersApi.savedMaxAge, const Duration(hours: 12));
    expect(SubscribersApi.savedMaxAge < SubscribersOfflineCache.maxAge, isTrue);
  });
}
