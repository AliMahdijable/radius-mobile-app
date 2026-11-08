import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/api/big_subscribers_api.dart';
import 'package:rad_mysvcs/api/subscribers_api.dart';
import 'package:rad_mysvcs/models/subscriber.dart';
import 'package:rad_mysvcs/screens/notifications/inbox_screen.dart';
import 'package:rad_mysvcs/services/alerts_service.dart';

import 'visual_perm/visual_perm_harness.dart';

/// الجرس (٨ نوفمبر — المالك: «الاشعارات زر… الي يظهر المنتهي وقريب الانتهاء يتاخر بشكل مو طبيعي بالاعداد الكبيرة والصغيرة»):
///   ١. آخر قائمةٍ معروفة تُعرض فوراً ومؤشّرٌ صغير بالعنوان، ثمّ الطازجة — لا شاشة انتظارٍ خلف القائمة والمتّصلين معاً.
///   ٢. المتّصلون البطيئون لا يؤخّرون القائمة أكثر من [_InboxScreenState.onlineBudget]، ثمّ يُدمجون حين يصلون.
///   ٣. الحساب الكبير: آخر صفحتين معروفتين فوراً ثمّ الطازجتان.

ResponseBody _json(Object body) => ResponseBody.fromString(jsonEncode(body), 200, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });

String _sas(DateTime t) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}:00';
}

Map<String, Object?> _row(String user, DateTime exp) => {'username': user, 'firstname': user, 'lastname': '', 'expiration': _sas(exp)};

class _SlowServer implements HttpClientAdapter {
  _SlowServer(this.inner, {required this.rows, this.onlineDelay = const Duration(seconds: 20)});
  final HttpClientAdapter inner;
  final List<Map<String, Object?>> rows;
  final Duration listDelay = const Duration(seconds: 2);
  final Duration onlineDelay;
  final asked = <String>[];
  bool big = false;
  List<Map<String, Object?>> bigExpired = const [];
  List<Map<String, Object?>> bigNear = const [];

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? rs, Future<void>? cf) async {
    final path = o.uri.path;
    if (path == '/api/v2/subscribers') {
      final q = o.queryParameters;
      asked.add('subscribers ${q['tab'] ?? (q['page'] != null ? 'probe' : 'all')}');
      if (q['page'] != null && q['tab'] == null) {
        return _json({'success': true, 'paged': big, 'total': big ? 9000 : rows.length, 'data': const []});
      }
      if (q['tab'] != null) {
        await Future<void>.delayed(listDelay);
        final r = q['tab'] == 'expired_today' ? bigExpired : bigNear;
        return _json({'success': true, 'paged': true, 'total': r.length + 40, 'last_page': 2, 'data': r});
      }
      await Future<void>.delayed(listDelay);
      return _json({'success': true, 'data': rows});
    }
    if (path == '/api/v2/online-users') {
      asked.add('online');
      await Future<void>.delayed(onlineDelay);
      return _json({'success': true, 'data': [
        {'username': rows.first['username'], 'ip': '10.0.0.9', 'session_time': 60},
      ]});
    }
    return inner.fetch(o, rs, cf);
  }

  @override
  void close({bool force = false}) {}
}

/// الوقت يمضي بنبضاتٍ صغيرة — سلسلة الطلب (التوكن، الاعتراض، الردّ) تحتاج عدّة نبضاتٍ لا واحدة طويلة.
Future<void> step(WidgetTester t, Duration total) async {
  for (var ms = 0; ms < total.inMilliseconds; ms += 100) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUpAll(visualSetUpAll);
  const phone = VisualDevice('', Size(390, 900), 1);

  Future<void> down(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 30));
    SubscribersApi.clearAllCaches();
    AlertsService.reset();
    await visualTearDown();
  }

  testWidgets('١ الحساب الاعتياديّ: آخر قائمةٍ فوراً، ثمّ الطازجة بلا انتظار المتّصلين، ثمّ حال الاتّصال', (t) async {
    final inner = await visualSetUp(s1bSasOwner);
    final now = DateTime.now();
    final fresh = [
      _row('fresh.near', now.add(const Duration(hours: 5))),
      _row('fresh.expired', now.subtract(const Duration(minutes: 1))),
    ];
    final srv = _SlowServer(inner, rows: fresh);
    ApiClient.dio.httpClientAdapter = srv;
    SubscribersApi.clearAllCaches();
    BigSubscribersApi.reset();
    // آخر قائمةٍ معروفة (من شاشة المشتركين مثلاً) — مشتركٌ ينتهي بعد ساعتين
    SubscribersApi.withOnline([Subscriber.fromJson(_row('old.near', now.add(const Duration(hours: 2))))], const {});

    await pumpVisual(t, phone, home: (_) => const InboxScreen());
    await step(t, const Duration(milliseconds: 600));
    expect(find.text('old.near'), findsWidgets, reason: 'فوراً من آخر قائمةٍ معروفة');
    expect(find.byKey(const ValueKey('inbox-refreshing')), findsOneWidget);

    // القائمة الطازجة بعد ثانيتين، والمتّصلون ما زالوا (٢٠ث) ⇒ تُعرض بعد مهلة ٣ث بلا انتظارهم
    await step(t, const Duration(seconds: 5));
    expect(find.text('fresh.near'), findsWidgets);
    expect(find.text('fresh.expired'), findsWidgets);
    expect(find.text('old.near'), findsNothing);
    expect(find.byKey(const ValueKey('inbox-refreshing')), findsOneWidget, reason: 'حال الاتّصال في الطريق');

    // وصل المتّصلون ⇒ يُدمجون والمؤشّر يختفي
    await step(t, const Duration(seconds: 16));
    expect(find.byKey(const ValueKey('inbox-refreshing')), findsNothing);
    expect(SubscribersApi.lastWithOnline()!.firstWhere((s) => s.username == 'fresh.near').isOnline, isTrue);
    expect(srv.asked.where((a) => a == 'subscribers all'), hasLength(1));
    await down(t);
  });

  testWidgets('١ب بلا قائمةٍ معروفة: شاشة الانتظار كما كانت ثمّ القائمة', (t) async {
    final inner = await visualSetUp(s1bSasOwner);
    final now = DateTime.now();
    final srv = _SlowServer(inner, rows: [_row('only.near', now.add(const Duration(hours: 3)))], onlineDelay: Duration.zero);
    ApiClient.dio.httpClientAdapter = srv;
    SubscribersApi.clearAllCaches();
    BigSubscribersApi.reset();
    await pumpVisual(t, phone, home: (_) => const InboxScreen());
    await step(t, const Duration(milliseconds: 600));
    expect(find.text('only.near'), findsNothing);
    expect(find.byKey(const ValueKey('inbox-refreshing')), findsNothing);
    await step(t, const Duration(seconds: 3));
    expect(find.text('only.near'), findsWidgets);
    await down(t);
  });

  testWidgets('٣ الحساب الكبير: آخر صفحتين فوراً ثمّ الطازجتان', (t) async {
    final inner = await visualSetUp(s1bSasOwner);
    final now = DateTime.now();
    final srv = _SlowServer(inner, rows: const [])
      ..big = true
      ..bigExpired = [_row('big.fresh.exp', now.subtract(const Duration(minutes: 3)))]
      ..bigNear = [_row('big.fresh.near', now.add(const Duration(hours: 4)))];
    ApiClient.dio.httpClientAdapter = srv;
    SubscribersApi.clearAllCaches();
    BigSubscribersApi.reset();
    BigSubscribersApi.remember('expired_today', 100,
        BigPage(rows: [Subscriber.fromJson(_row('big.old.exp', now.subtract(const Duration(hours: 1))))], total: 7, lastPage: 1));
    BigSubscribersApi.remember('expiring_24h', 100,
        BigPage(rows: [Subscriber.fromJson(_row('big.old.near', now.add(const Duration(hours: 6))))], total: 3, lastPage: 1));

    await pumpVisual(t, phone, home: (_) => const InboxScreen());
    await step(t, const Duration(milliseconds: 600));
    expect(find.text('big.old.exp'), findsWidgets);
    expect(find.text('big.old.near'), findsWidgets);
    expect(find.byKey(const ValueKey('inbox-refreshing')), findsOneWidget);

    await step(t, const Duration(seconds: 3));
    expect(find.text('big.fresh.exp'), findsWidgets);
    expect(find.text('big.old.exp'), findsNothing);
    expect(find.byKey(const ValueKey('inbox-refreshing')), findsNothing);
    expect(srv.asked, isNot(contains('subscribers all')), reason: 'الحساب الكبير بلا قائمةٍ كاملة');
    await down(t);
  });
}
