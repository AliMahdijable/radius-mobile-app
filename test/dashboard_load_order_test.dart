import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/api/dashboard_api.dart';
import 'package:rad_mysvcs/screens/dashboard/dashboard_screen.dart';
import 'package:rad_mysvcs/services/dashboard_load_order.dart';

import 'visual_perm/visual_perm_harness.dart';

/// «الاولية تكون لتحميل المشتركين للداش بورد ثم بقيه الامور» + «آخر النشاطات يجلب بس ٥» (المالك ١٤ نوفمبر ٢٠٢٦).
///
/// على الرئيسيّة الحقيقيّة (مالك ساس، العدّة البصريّة) ومحوّلٌ يمسك ردّ المشتركين: لا يُطلب شيءٌ من البقيّة — آخر النشاطات،
/// الإيرادات وتوزيع الباقات، الرصيد، الواتساب — قبل وصول المشتركين؛ ثمّ تُطلب كلّها. وقائمةٌ بطيئة لا تحبس الباقي أكثر من
/// ستّ ثوانٍ. و«آخر النشاطات» تطلب ‎limit=5‎ وتعرض خمسةً ولو أعاد خادمٌ أقدم أكثر.
class _Gate implements HttpClientAdapter {
  _Gate(this.inner);
  final HttpClientAdapter inner;
  final seen = <String>[];
  final subs = Completer<void>();

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? rs, Future<void>? cf) async {
    final q = o.queryParameters.entries.map((e) => '${e.key}=${e.value}').join('&');
    seen.add('${o.method} ${o.path}${q.isEmpty ? '' : '?$q'}');
    if (o.path.startsWith('/api/v2/subscribers')) await subs.future;
    if (o.path == '/api/activities/daily-activations') {
      // خادمٌ أقدم لا يعرف limit: يعيد اليوم كلّه (٩ سطور) — التطبيق يعرض خمسة.
      return ResponseBody.fromString(
        '{"success":true,"counts":{"activate":7,"extend":2,"total":9},"data":[${List.generate(9, (i) => '{"id":${100 - i},"action_type":"SUBSCRIBER_ACTIVATE","target_name":"u$i","created_at":"2026-11-14T0$i:00:00.000Z"}').join(',')}]}',
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }
    return inner.fetch(o, rs, cf);
  }

  @override
  void close({bool force = false}) => inner.close(force: force);
}

const _rest = [
  '/api/activities/daily-activations',
  '/api/reports/finance',
  '/api/v2/admin-widgets',
  '/api/whatsapp/connection-status',
];

void main() {
  setUpAll(visualSetUpAll);
  tearDown(DashboardLoadOrder.debugReset);

  Future<_Gate> open(WidgetTester t) async {
    final server = await visualSetUp(s1bSasOwner);
    final gate = _Gate(server);
    ApiClient.dio.httpClientAdapter = gate;
    DashboardLoadOrder.debugReset();
    await pumpVisual(t, phone, home: (_) => const DashboardScreen());
    return gate;
  }

  Future<void> drain(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 8));
    await visualTearDown();
  }

  testWidgets('المشتركون أوّلاً: لا شيء من البقيّة قبل وصولهم، ثمّ كلّها — و«آخر النشاطات» limit=5 وخمسةٌ تُعرض', (t) async {
    final gate = await open(t);
    await settle(t, seconds: 2);
    final before = gate.seen.join('\n');
    expect(before, contains('GET /api/v2/subscribers'), reason: 'المشتركون طُلبوا أوّلاً:\n$before');
    for (final p in _rest) {
      expect(before.contains(p), isFalse, reason: '$p طُلب قبل وصول المشتركين:\n$before');
    }
    expect(DashboardLoadOrder.waiting, isTrue);

    gate.subs.complete();
    await settle(t);
    final after = gate.seen.join('\n');
    for (final p in ['/api/activities/daily-activations', '/api/reports/finance', '/api/v2/admin-widgets']) {
      expect(after, contains(p), reason: 'بعد المشتركين:\n$after');
    }
    final daily = gate.seen.firstWhere((x) => x.contains('daily-activations'));
    expect(daily, contains('limit=${DashboardApi.recentLimit}'));
    expect(DashboardApi.recentLimit, 5);
    // الخادم الأقدم أعاد تسعة: يُعرض أحدث خمسة.
    expect(find.text('u0'), findsWidgets);
    expect(find.text('u4'), findsWidgets);
    expect(find.text('u5'), findsNothing);
    expect(find.text('u8'), findsNothing);
    expect(t.takeException(), isNull);
    await drain(t);
  });

  testWidgets('قائمةٌ بطيئة لا تحبس الباقي: بعد ستّ ثوانٍ تُطلب البقيّة والمشتركون لم يصلوا', (t) async {
    final gate = await open(t);
    await settle(t, seconds: 3);
    expect(gate.seen.join('\n').contains('/api/reports/finance'), isFalse);
    await settle(t, seconds: 4);
    final mid = gate.seen.join('\n');
    expect(mid, contains('/api/activities/daily-activations'), reason: mid);
    expect(mid, contains('/api/reports/finance'), reason: mid);
    gate.subs.complete();
    await settle(t);
    expect(t.takeException(), isNull);
    await drain(t);
  });

  group('DashboardLoadOrder', () {
    test('بلا جولة لا انتظار؛ والجولة تنتهي بالمشتركين أو بالحدّ', () async {
      DashboardLoadOrder.debugReset();
      var done = false;
      await DashboardLoadOrder.afterSubscribers().then((_) => done = true);
      expect(done, isTrue, reason: 'نقرة المدير خارج الجولة تجلب فوراً');

      DashboardLoadOrder.begin();
      done = false;
      final w = DashboardLoadOrder.afterSubscribers().then((_) => done = true);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(done, isFalse);
      DashboardLoadOrder.begin(); // جولةٌ مفتوحة تبقى نفسها
      DashboardLoadOrder.subscribersDone();
      await w;
      expect(done, isTrue);
      expect(DashboardLoadOrder.waiting, isFalse);

      DashboardLoadOrder.begin();
      final sw = Stopwatch()..start();
      await DashboardLoadOrder.afterSubscribers(max: const Duration(milliseconds: 60));
      expect(sw.elapsedMilliseconds, greaterThanOrEqualTo(50), reason: 'انتظر حتى الحدّ');
      expect(DashboardLoadOrder.waiting, isTrue, reason: 'الحدّ يُطلق المنتظِر لا يُغلق الجولة');
      DashboardLoadOrder.subscribersDone();
    });
  });
}
