import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/api/big_subscribers_api.dart';
import 'package:rad_mysvcs/api/broadcast_api.dart';
import 'package:rad_mysvcs/api/subscribers_api.dart';
import 'package:rad_mysvcs/models/subscriber.dart';
import 'package:rad_mysvcs/screens/broadcast/broadcast_screen.dart';

import 'visual_perm/visual_perm_harness.dart';

/// ١٦ نوفمبر — المالك (لقطة «التبليغات»): «ضيفلنا بالتبليغات الفعالين هم يكدر يجلبهم». «الفعّالون» = اشتراكه لم ينتهِ — قاعدة
/// الخادم نفسها (`broadcastAudience.isActive`، db484d5): الانتهاء بعد الآن بساعة بغداد، وبلا تاريخٍ الأيّام الباقية ≥ 0،
/// والمجهول لا يُعدّ ولا يُرسَل له. نطاق «الكلّ» يرسل النوع `active` والخادم يختار؛ الخادم هنا وهميّ يسجّل الطلبات.
class _Server implements HttpClientAdapter {
  _Server(this.inner, this.rows);
  final HttpClientAdapter inner;
  final List<Map<String, Object?>> rows;
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
      return _json(200, {'success': true, 'message': 'تمت إضافة رسائل', 'summary': {'queued': 2, 'excludedHighRisk': 0}});
    }
    if (o.method == 'POST' && p == '/api/v2/whatsapp/bulk-risk') {
      return _json(200, {'success': true, 'total': 0, 'noInbound': 0, 'highRisk': 0});
    }
    if (o.method == 'GET' && p.startsWith('/api/whatsapp/send-scope/')) {
      return _json(200, {'success': true, 'sendToAll': true, 'subManagers': const []});
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

Map<String, Object?> _row(String u, {String? expiration, Object? remaining, String phone = '07701234567'}) => {
      'idx': '${u.hashCode.abs() % 9000}',
      'username': u,
      'firstname': u,
      'lastname': '',
      'phone': phone,
      'profile_name': 'Economy',
      'profile_id': 7,
      'expiration': expiration,
      'remaining_days': remaining,
      'online_status': 0,
      'enabled': 1,
    };

const _p390 = VisualDevice('', Size(390, 1600), 3);

void main() {
  group('القاعدة (نقيّة) — كخادمها', () {
    // 12:00 بغداد = 09:00 UTC؛ تاريخ الساس يُقرأ بساعة بغداد الجداريّة.
    final now = DateTime.utc(2026, 10, 18, 9);
    Subscriber at(String? exp, {int? remaining}) => Subscriber.fromJson({
          'idx': '1',
          'username': 'u',
          'phone': '07701234567',
          'expiration': exp,
          'remaining_days': remaining,
        });

    test('الانتهاء بعد الآن ⇒ فعّال؛ قبله ⇒ لا — بساعة بغداد', () {
      expect(broadcastActive(at('2026-10-18 12:30:00'), now: now), isTrue);
      expect(broadcastActive(at('2026-10-18 11:30:00'), now: now), isFalse, reason: 'انتهى قبل نصف ساعة');
      expect(broadcastActive(at('2026-12-01 00:00:00', remaining: -9), now: now), isTrue, reason: 'التاريخ يغلب');
    });

    test('بلا تاريخ: الأيّام الباقية ≥ 0؛ والمجهول ليس فعّالاً (لا «الكلّ» بدله)', () {
      expect(broadcastActive(at(null, remaining: 0), now: now), isTrue);
      expect(broadcastActive(at(null, remaining: 3), now: now), isTrue);
      expect(broadcastActive(at(null, remaining: -1), now: now), isFalse);
      expect(broadcastActive(at(null), now: now), isFalse);
    });

    test('النوع «active» والرسالة مطلوبة (لا قالب افتراضيّ)', () {
      expect(MessageIntent.active.apiValue, 'active');
      expect(MessageIntent.active.messageOptional, isFalse);
    });
  });

  group('الشاشة', () {
    setUpAll(visualSetUpAll);

    testWidgets('🚨 «الفعّالون» بعدده بجانب «كل المشتركين»، والإرسال للكلّ بالنوع active والخادم يختار', (t) async {
      final inner = await visualSetUp(s1bSasOwner);
      final srv = _Server(inner, [
        _row('far@x', expiration: '2030-01-01 10:00:00'),
        _row('soon@x', expiration: '2030-01-03 10:00:00'),
        _row('gone@x', expiration: '2020-01-01 10:00:00'),
        _row('nodate@x'),
        _row('nophone@x', expiration: '2030-01-01 10:00:00', phone: ''),
      ]);
      ApiClient.dio.httpClientAdapter = srv;
      BigSubscribersApi.reset();
      SubscribersApi.clearAllCaches();
      await pumpVisual(t, _p390, home: (_) => const BroadcastScreen());
      await settle(t, seconds: 2);

      final card = find.ancestor(of: find.text('الفعّالون'), matching: find.byType(InkWell)).first;
      expect(find.descendant(of: card, matching: find.text('2')), findsOneWidget,
          reason: 'far + soon — لا المنتهي ولا المجهول ولا من بلا رقم');
      // الترتيب: «كل المشتركين» ثمّ «الفعّالون» في الصفّ الأوّل
      final allX = t.getCenter(find.text('كل المشتركين')).dy;
      expect(t.getCenter(find.text('الفعّالون')).dy, closeTo(allX, 2));

      await t.tap(find.text('الفعّالون'));
      await settle(t);
      await t.enterText(find.byType(TextField).last, 'عرضٌ للفعّالين');
      await settle(t);
      await t.tap(find.byKey(const ValueKey('broadcast-send')));
      await settle(t);
      await t.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('إرسال')));
      await settle(t, seconds: 2);
      final send = srv.sends().single;
      expect(send['type'], 'active');
      expect(send.containsKey('targetUsernames'), isFalse, reason: 'نطاق «الكلّ»: الخادم يختار بقاعدته');
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 1));
      await visualTearDown();
      BigSubscribersApi.reset();
    });
  });
}
