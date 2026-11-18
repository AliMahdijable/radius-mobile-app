import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/api/subscribers_api.dart';
import 'package:rad_mysvcs/models/subscriber.dart';
import 'package:rad_mysvcs/services/provider_service.dart';

/// رقم مشترك الوطني طازجاً عند فتح لوحته (١٨ نوفمبر — المالك: «عنده هذا المشترك بدلو رقمه لكن بعده يظهر هنا مخزون عدنا» ⇒
/// «ابدي ب ١»). قوائم البوّابة بلا هاتف فالأرقام مخبّأةٌ بالخادم (٣ أيّام)؛ اللوحة تسأل `GET …/contact` (الخادم 6e1b55b) وتعرض
/// الجديد فوراً، وما لم يُقرأ الآن يبقى رقم القائمة.
class _ContactServer implements HttpClientAdapter {
  _ContactServer(this.reply);
  final ResponseBody Function(RequestOptions o) reply;
  final calls = <String>[];

  static ResponseBody json(int status, Object body) => ResponseBody.fromString(jsonEncode(body), status, headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      });

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    calls.add('${o.method} ${o.path}');
    return reply(o);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late HttpClientAdapter orig;
  setUp(() => orig = ApiClient.dio.httpClientAdapter);
  tearDown(() {
    ApiClient.dio.httpClientAdapter = orig;
    ProviderService.debugSet(null);
  });

  test('freshContact: الرقم كما تقوله البوّابة الآن من …/contact', () async {
    final s = _ContactServer((o) => _ContactServer.json(200, {
          'success': true,
          'data': {'phone': ' 07800000061 ', 'fresh': true},
        }));
    ApiClient.dio.httpClientAdapter = s;
    expect(await SubscribersApi.freshContact('8739352'), '07800000061');
    expect(s.calls, ['GET /api/v2/subscribers/8739352/contact']);
  });

  test('freshContact: لم يُقرأ الآن (fresh:false) · مزوّدٌ بلا قدرة (409) · غير موجود (404) · فشل ⇒ null (رقم القائمة يبقى)', () async {
    final replies = [
      _ContactServer.json(200, {
        'success': true,
        'data': {'phone': '07700000061', 'fresh': false},
      }),
      _ContactServer.json(409, {'success': false, 'code': 'PROVIDER_UNSUPPORTED'}),
      _ContactServer.json(404, {'success': false, 'code': 'SUBSCRIBER_NOT_FOUND'}),
      _ContactServer.json(200, {'success': false}),
      _ContactServer.json(200, {'success': true, 'data': 'x'}),
    ];
    for (final r in replies) {
      ApiClient.dio.httpClientAdapter = _ContactServer((o) => r);
      expect(await SubscribersApi.freshContact('8739352'), isNull);
    }
  });

  test('copyWithPhone: الرقم وحده يتغيّر', () {
    final a = Subscriber(
      idx: '8739352',
      username: 'u61@ftth',
      firstname: 'زبون',
      lastname: 'تجريبي',
      phone: '07700000061',
      mobile: '07700000062',
      expiration: '2026-12-09 23:15:00',
      remainingDays: 21,
      hasDebtFlag: true,
      debt: 5000,
      profileName: 'Basic',
      profileId: 7,
      parentUsername: 'FKU0052-3',
      isEnabled: true,
      isOnlineFlag: true,
      ipAddress: '10.0.0.61',
      latitude: 33.3,
      longitude: 44.4,
      addressRaw: 'حيّ تجريبي',
      companyKey: null,
      debtKind: 'activation',
    );
    final b = a.copyWithPhone('07800000061');
    expect(b.phone, '07800000061');
    expect(
      [b.idx, b.username, b.firstname, b.lastname, b.mobile, b.expiration, b.remainingDays, b.hasDebtFlag, b.debt, b.profileName,
        b.profileId, b.parentUsername, b.isEnabled, b.isOnlineFlag, b.ipAddress, b.latitude, b.longitude, b.addressRaw, b.companyKey,
        b.debtKind],
      [a.idx, a.username, a.firstname, a.lastname, a.mobile, a.expiration, a.remainingDays, a.hasDebtFlag, a.debt, a.profileName,
        a.profileId, a.parentUsername, a.isEnabled, a.isOnlineFlag, a.ipAddress, a.latitude, a.longitude, a.addressRaw, a.companyKey,
        a.debtKind],
    );
  });

  test('phoneOnOpen: المشروع الوطنيّ وحده', () {
    ProviderService.debugSet('watani');
    expect(ProviderService.phoneOnOpen, isTrue);
    for (final p in ['sas4', 'earthlink', 'ftth', 'fiberx', 'nabd', null]) {
      ProviderService.debugSet(p);
      expect(ProviderService.phoneOnOpen, isFalse, reason: '$p');
    }
  });

  test('لوحة المشترك تسأل عند الفتح للوطني وحده خارج «كل الشركات»، ولا تمسح رقماً بفراغ', () {
    final src = File('lib/screens/subscribers/subscriber_detail_screen.dart').readAsStringSync();
    expect(src, contains('if (ProviderService.phoneOnOpen && sub.companyKey == null) unawaited(_loadFreshPhone());'));
    expect(src, contains("if (!mounted || p == null || p.isEmpty || p == (sub.phone ?? '').trim()) return;"));
    expect(src, contains('setState(() => sub = sub.copyWithPhone(p));'));
  });
}
