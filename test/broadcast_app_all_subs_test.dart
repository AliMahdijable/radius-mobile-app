import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/api/big_subscribers_api.dart';
import 'package:rad_mysvcs/api/subscribers_api.dart';
import 'package:rad_mysvcs/screens/broadcast/broadcast_screen.dart';

import 'visual_perm/visual_perm_harness.dart';

/// ١٩ نوفمبر — المالك: «التبليغات تعتمد إذا المشترك عنده رقم تليفون… نقدر نخلي بالقناة مال التطبيق… مسموح لكل المشتركين».
/// الاختيار يمرّ بالتطبيق («التطبيق» أو «تلقائي» — آخر محطّاته التطبيق) والقناة مفعّلة للحساب ⇒ القائمة والأعداد كلّ المشتركين،
/// ومن لا رقم له يظهر «بلا رقم — بالتطبيق» ويُرسَل اسمه حين يُختار. واتساب/تلغرام وحدهما، أو حسابٌ بلا القناة: ذوو الأرقام
/// وحدهم كما كان حرفاً. الخادم هنا وهميّ يسجّل الطلبات.
class _Server implements HttpClientAdapter {
  _Server(this.inner, this.rows, {this.appEnabled = true});
  final HttpClientAdapter inner;
  final List<Map<String, Object?>> rows;
  final bool appEnabled;
  final requests = <RequestOptions>[];

  List<Map<String, dynamic>> sends() => [
        for (final r in requests)
          if (r.method == 'POST' && r.path == '/api/whatsapp/broadcast') Map<String, dynamic>.from(r.data as Map),
      ];

  static ResponseBody _json(int status, Object body) =>
      ResponseBody.fromString(jsonEncode(body), status, headers: {Headers.contentTypeHeader: [Headers.jsonContentType]});

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requests.add(o);
    final p = o.path;
    if (o.method == 'POST' && p == '/api/whatsapp/broadcast') {
      return _json(200, {'success': true, 'message': 'التطبيق: 2 مشترك', 'summary': {'queued': 0, 'excludedHighRisk': 0}});
    }
    if (o.method == 'POST' && p == '/api/v2/whatsapp/bulk-risk') {
      return _json(200, {'success': true, 'total': 0, 'noInbound': 0, 'highRisk': 0});
    }
    if (o.method == 'GET' && p.startsWith('/api/whatsapp/send-scope/')) {
      return _json(200, {'success': true, 'sendToAll': true, 'subManagers': const []});
    }
    if (o.method == 'GET' && p == '/api/whatsapp/broadcast/channels') {
      return _json(200, {
        'success': true,
        'app': {'enabled': appEnabled},
        'reach': {'telegram': 13, if (appEnabled) 'app': 17},
        'locks': const {},
      });
    }
    if (o.method == 'GET' && p == '/api/whatsapp/broadcast/debt-filter') {
      return _json(404, {'success': false});
    }
    if (o.method == 'GET' && p == '/api/v2/subscribers' && o.queryParameters['page'] == null) {
      return _json(200, {'success': true, 'data': rows});
    }
    return inner.fetch(o, requestStream, cancelFuture);
  }

  @override
  void close({bool force = false}) {}
}

Map<String, Object?> _row(String u, {String phone = '07701234567'}) => {
      'idx': '${u.hashCode.abs() % 9000}',
      'username': u,
      'firstname': u,
      'lastname': '',
      'phone': phone,
      'profile_name': 'Economy',
      'profile_id': 7,
      'expiration': '2030-01-01 10:00:00',
      'remaining_days': 400,
      'online_status': 0,
      'enabled': 1,
    };

const _p390 = VisualDevice('', Size(390, 1800), 3);

/// مشتركٌ برقم واثنان بلا رقم.
List<Map<String, Object?>> _rows() => [
      _row('with@x'),
      _row('nophone1@x', phone: ''),
      _row('nophone2@x', phone: ''),
    ];

void main() {
  Finder cardOf(String label) => find.ancestor(of: find.text(label), matching: find.byType(InkWell)).first;
  Finder countIn(String label, String n) => find.descendant(of: cardOf(label), matching: find.text(n));
  const noPhone = 'بلا رقم — بالتطبيق';

  Future<_Server> open(WidgetTester t, {required bool appOn}) async {
    final inner = await visualSetUp(s1bSasOwner);
    final srv = _Server(inner, _rows(), appEnabled: appOn);
    ApiClient.dio.httpClientAdapter = srv;
    BigSubscribersApi.reset();
    SubscribersApi.clearAllCaches();
    await pumpVisual(t, _p390, home: (_) => const BroadcastScreen());
    await settle(t, seconds: 2);
    return srv;
  }

  Future<void> close(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 1));
    await visualTearDown();
    BigSubscribersApi.reset();
  }

  Future<void> tapKey(WidgetTester t, String key) async {
    await t.ensureVisible(find.byKey(ValueKey(key)));
    await t.tap(find.byKey(ValueKey(key)));
    await settle(t);
  }

  Future<void> pickMyself(WidgetTester t) async {
    final f = find.text('أختار بنفسي');
    await t.ensureVisible(f);
    await t.tap(f);
    await settle(t);
  }

  testWidgets('القناة مفعّلة: «تلقائي» و«التطبيق» ⇒ كلّ المشتركين (ومن لا رقم له «بلا رقم — بالتطبيق»)؛ واتساب وحده ⇒ ذوو الأرقام كما كان',
      (t) async {
    await open(t, appOn: true);
    // «تلقائي» (الافتراض): آخر محطّاته التطبيق ⇒ الثلاثة
    expect(countIn('كل المشتركين', '3'), findsOneWidget);
    await pickMyself(t);
    expect(find.text(noPhone), findsNWidgets(2));
    expect(find.text('nophone1@x'), findsWidgets);

    // واتساب وحده ⇒ من له رقم وحده
    await tapKey(t, 'channel-whatsapp');
    expect(countIn('كل المشتركين', '1'), findsOneWidget);
    expect(find.text(noPhone), findsNothing);
    expect(find.text('nophone1@x'), findsNothing);

    // + التطبيق ⇒ الثلاثة من جديد
    await tapKey(t, 'channel-app');
    expect(countIn('كل المشتركين', '3'), findsOneWidget);
    expect(find.text(noPhone), findsNWidgets(2));

    // التطبيق وحده (أُزيل واتساب) ⇒ الثلاثة
    await tapKey(t, 'channel-whatsapp');
    expect(countIn('كل المشتركين', '3'), findsOneWidget);
    expect(t.takeException(), isNull);
    await close(t);
  });

  testWidgets('القناة غير مفعّلة للحساب: كما كان حرفاً — ذوو الأرقام وحدهم ولا «بلا رقم»', (t) async {
    await open(t, appOn: false);
    expect(countIn('كل المشتركين', '1'), findsOneWidget);
    await pickMyself(t);
    expect(find.text(noPhone), findsNothing);
    expect(find.text('nophone1@x'), findsNothing);
    expect(t.takeException(), isNull);
    await close(t);
  });

  testWidgets('«التطبيق» + «أختار بنفسي»: مشتركٌ بلا رقم يُختار ويُرسَل اسمه مع channels', (t) async {
    final srv = await open(t, appOn: true);
    await tapKey(t, 'channel-app');
    await pickMyself(t);
    final row = find.text('nophone2@x').first;
    await t.ensureVisible(row);
    await t.tap(row);
    await settle(t);
    await t.enterText(find.byType(TextField).last, 'عرضٌ جديد');
    await settle(t);
    await tapKey(t, 'broadcast-send');
    await t.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('إرسال')));
    await settle(t, seconds: 2);
    final send = srv.sends().single;
    expect(send['channels'], ['app']);
    expect(send['targetUsernames'], ['nophone2@x']);
    expect(t.takeException(), isNull);
    await close(t);
  });
}
