// الحساب المعروف ببطء قائمته (١٤ نوفمبر ٢٠٢٦ — المالك: «أوّل ٥٠ مشتركاً حيّين خلال ٣–٥ث والباقي وراهم»، ⛔ لا نسخة قديمة).
// ساسٌ بطيء وهميّ: الفحص (?page=1&size=1) ٥ ثوانٍ، والقائمة الكاملة ٢٠ ثانية، والصفحة الأولى فوراً. المعروف ببطئه يعرض الصفحة
// الأولى الحيّة من أوّل لحظة (لا انتظار الفحص ولا ١٫٢ث) ثمّ تحلّ القائمة الكاملة محلّها؛ وغير المعروف كما كان.
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/api/big_subscribers_api.dart';
import 'package:rad_mysvcs/api/subscribers_api.dart';
import 'package:rad_mysvcs/screens/subscribers/subscribers_screen.dart';
import 'package:rad_mysvcs/screens/subscribers/widgets/filter_chips_bar.dart';
import 'package:rad_mysvcs/services/known_slow_list.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'visual_perm/visual_perm_harness.dart';

/// صفوف الصفحة الأولى — بأسماءٍ لا تشبه القائمة الكاملة (fixtureSubscribers) فيُعرف مصدر ما يظهر.
final _pageRows = [
  for (var i = 1; i <= 3; i++)
    {
      'idx': 900 + i,
      'username': 'page$i@slow',
      'firstname': 'صفحة',
      'lastname': 'أولى $i',
      'profile_name': 'Economy',
      'profile_id': 7,
      'remaining_days': 10,
      'expiration': '2026-12-01 00:00:00',
      'enabled': 1,
      'notes': '',
      'debt': 0,
      'hasDebt': false,
      'package_price': 25000,
    },
];

class _SlowSas implements HttpClientAdapter {
  _SlowSas(this.inner);
  final HttpClientAdapter inner;
  final order = <String>[];

  static ResponseBody _json(Object body) => ResponseBody.fromString(jsonEncode(body), 200, headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      });

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? s, Future<void>? c) async {
    if (o.method.toUpperCase() == 'GET' && o.uri.path == '/api/v2/subscribers') {
      final q = o.uri.queryParameters;
      if (q.containsKey('page')) {
        if (q['size'] == '1') {
          order.add('probe');
          await Future<void>.delayed(const Duration(seconds: 5));
          order.add('probe-done');
          return _json({'success': true, 'paged': true, 'data': [_pageRows.first], 'total': 17, 'last_page': 17});
        }
        order.add('page');
        return _json({'success': true, 'paged': true, 'data': _pageRows, 'total': 17, 'last_page': 1});
      }
      order.add('full');
      await Future<void>.delayed(const Duration(seconds: 20));
      order.add('full-done');
    }
    return inner.fetch(o, s, c);
  }

  @override
  void close({bool force = false}) {}
}

Future<_SlowSas> _setUp({required bool knownSlow}) async {
  final srv = _SlowSas(await visualSetUp(s1bSasOwner)); // يمسح SharedPreferences ثمّ نزرع
  SharedPreferences.setMockInitialValues({
    if (knownSlow)
      'subs_known_slow_v1': jsonEncode({
        'supernet:12': {'size': 17, 'at': DateTime.now().millisecondsSinceEpoch},
      }),
  });
  KnownSlowList.adminId = () async => 'supernet:12';
  KnownSlowList.now = DateTime.now;
  ApiClient.dio.httpClientAdapter = srv;
  SubscribersApi.clearAllCaches();
  BigSubscribersApi.reset();
  return srv;
}

Future<void> _pumpFor(WidgetTester t, Duration d) async {
  final steps = d.inMilliseconds ~/ 250;
  for (var i = 0; i < steps; i++) {
    await t.pump(const Duration(milliseconds: 250));
  }
}

void main() {
  setUpAll(visualSetUpAll);

  testWidgets('المعروف ببطئه: الصفحة الأولى الحيّة من أوّل لحظة (قبل الفحص)، ثمّ القائمة الكاملة تحلّ محلّها', (t) async {
    final srv = await _setUp(knownSlow: true);
    final cmd = ValueNotifier<SubscriberFilter?>(SubscriberFilter.all);
    await pumpVisual(t, phone, home: (_) => SubscribersScreen(filterCmd: cmd));
    await _pumpFor(t, const Duration(seconds: 1));

    expect(srv.order, containsAll(<String>['page', 'full']), reason: 'الصفحة والقائمة معاً من البداية: ${srv.order}');
    expect(srv.order.contains('probe-done'), isFalse, reason: 'لم ينتظر أحدٌ الفحص (٥ث)');
    expect(find.textContaining('أولى 1'), findsWidgets, reason: 'صفوف الصفحة الأولى ظاهرة خلال ثانية');

    await _pumpFor(t, const Duration(seconds: 22));
    expect(srv.order, contains('full-done'));
    expect(find.textContaining('أولى 1'), findsNothing, reason: 'القائمة الكاملة حلّت محلّ الصفحة');
    expect(find.textContaining('الموسوي'), findsWidgets, reason: 'صفوف القائمة الكاملة ظاهرة');

    await t.pumpWidget(const SizedBox());
    await _pumpFor(t, const Duration(seconds: 6));
  });

  testWidgets('غير المعروف ببطئه كما كان: الفحص أوّلاً ثمّ القائمة — لا صفحة قبل وصول الفحص', (t) async {
    final srv = await _setUp(knownSlow: false);
    final cmd = ValueNotifier<SubscriberFilter?>(SubscriberFilter.all);
    await pumpVisual(t, phone, home: (_) => SubscribersScreen(filterCmd: cmd));
    await _pumpFor(t, const Duration(seconds: 1));

    expect(srv.order, ['probe'], reason: 'الفحص وحده قبل أيّ شيء: ${srv.order}');
    expect(find.textContaining('أولى 1'), findsNothing);

    await _pumpFor(t, const Duration(seconds: 30));
    expect(srv.order.indexOf('probe-done'), lessThan(srv.order.indexOf('full')), reason: '${srv.order}');
    expect(find.textContaining('الموسوي'), findsWidgets);

    await t.pumpWidget(const SizedBox());
    await _pumpFor(t, const Duration(seconds: 6));
  });
}
