import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/api/big_subscribers_api.dart';
import 'package:rad_mysvcs/api/subscribers_api.dart';
import 'package:rad_mysvcs/screens/broadcast/broadcast_screen.dart';
import 'package:rad_mysvcs/screens/telegram/sheets/telegram_broadcast_sheet.dart';

import 'visual_perm/visual_perm_harness.dart';

/// «تحديد المدينين» (٩ نوفمبر ٢ — المالك: «نعم» لـ«إرسال عام» تلغرام وللحسابات الكبيرة). الخادم وهميّ: لا رسالة تُرسَل، والطلبات
/// تُسجَّل لتُثبت ما يُرسَل حرفاً.
class _Srv implements HttpClientAdapter {
  _Srv(this.inner, {this.telegram = true, this.big = false, this.pendingPolls = 0});
  final HttpClientAdapter inner;
  final bool telegram;
  final bool big;
  int pendingPolls;
  final requests = <RequestOptions>[];

  List<Map<String, dynamic>> bodiesOf(String path) => [
        for (final r in requests)
          if (r.method == 'POST' && r.path == path) Map<String, dynamic>.from(r.data as Map),
      ];

  static ResponseBody _json(int status, Object body) => ResponseBody.fromString(jsonEncode(body), status, headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      });

  static const rows = [
    {'username': 'ahmed.k@najaf', 'name': 'أحمد كامل', 'debt': 75000, 'days': null, 'legacy': true},
    {'username': 'hussein77@najaf', 'name': 'حسين عبد الأمير', 'debt': 61000, 'days': 92, 'legacy': false},
    {'username': 'haider.s@najaf', 'name': 'حيدر سالم', 'debt': 52000, 'days': 31, 'legacy': false},
  ];

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requests.add(o);
    final p = o.path;
    if (o.method == 'GET' && p == '/api/whatsapp/broadcast/debt-filter') {
      return _json(200, {
        'success': true,
        'debtFilter': {
          'version': telegram ? 3 : 2, if (telegram) 'telegram': true, if (telegram) 'bigPreview': 'async',
          'amount': true, 'age': true, 'ageMeaning': 'oldest_unpaid', 'presets': [7, 15, 30, 60, 90], 'maxAgeDays': 3650,
          'maxAmount': 10000000000, 'previewRequired': true,
        },
      });
    }
    if (o.method == 'POST' && p == '/api/telegram/broadcast') {
      final b = Map<String, dynamic>.from(o.data as Map);
      if (b['dryRun'] == true) {
        return _json(200, {
          'success': true, 'dryRun': true, 'totalBound': 18, 'eligible': 3, 'blocked': 1, 'outOfScope': 0, 'rows': rows,
          'truncated': false, 'audienceKey': 't3'.padRight(32, '0'),
          'debtFilter': {'considered': 5, 'kept': 3, 'amountOut': 1, 'ageOut': 1, 'unknownAge': 0, 'legacy': 1, 'notFound': 1, 'notDebtor': 9},
        });
      }
      return _json(200, {'success': true, 'enqueued': 3, 'totalBound': 18, 'eligible': 3, 'message': 'أُدرجت 3 رسالة تلغرام — 1 مربوطٌ غير موجود في قائمة الشركة — لم يُشمل'});
    }
    if (o.method == 'GET' && p == '/api/v2/subscribers' && o.queryParameters['page'] != null && big) {
      return _json(200, {'success': true, 'data': const [], 'total': 89177, 'paged': true, 'page': 1, 'size': 1, 'last_page': 89177});
    }
    if (o.method == 'GET' && p == '/api/v2/subscribers-summary' && big) {
      return _json(200, {'success': true, 'summary': {'all': 89177, 'debtors': null, 'app': {'all': 89177, 'debtors': 21064}}});
    }
    if (o.method == 'POST' && p == '/api/whatsapp/broadcast') {
      final b = Map<String, dynamic>.from(o.data as Map);
      if (b['dryRun'] == true) {
        if (pendingPolls > 0) {
          pendingPolls--;
          return _json(202, {'success': true, 'dryRun': true, 'pending': true, 'total': 89177,
            'message': 'حسابك كبير (89,177 مشترك): نحسب من يطابق في الخلفيّة — تظهر النتيجة خلال دقيقة تقريباً'});
        }
        return _json(200, {
          'success': true, 'dryRun': true, 'mode': 'debtors', 'count': 3, 'audience': 3, 'excludedHighRisk': 0, 'deduped': 0,
          'rows': rows, 'truncated': false, 'audienceKey': 'b3'.padRight(32, '0'), 'missing': 0,
          'computedAt': '2026-11-09T12:00:00.000Z',
          'debtFilter': {'summary': 'x', 'considered': 21064, 'kept': 3, 'amountOut': 1, 'ageOut': 0, 'unknownAge': 0, 'legacy': 1},
        });
      }
      return _json(200, {'success': true, 'pending': true, 'total': 89177,
        'message': 'بدأ تجهيز التبليغ لحسابٍ كبير (89,177 مشترك) — قد يأخذ بضع دقائق، ويصلك إشعارٌ بالنتيجة'});
    }
    if (o.method == 'GET' && p.startsWith('/api/whatsapp/send-scope/')) {
      return _json(200, {'success': true, 'sendToAll': true, 'subManagers': const []});
    }
    if (o.method == 'POST' && p == '/api/v2/whatsapp/bulk-risk') {
      return _json(200, {'success': true, 'total': 0, 'noInbound': 0, 'highRisk': 0});
    }
    return inner.fetch(o, requestStream, cancelFuture);
  }

  @override
  void close({bool force = false}) {}
}

const _p390 = VisualDevice('', Size(390, 1700), 3);

void main() {
  setUpAll(visualSetUpAll);

  Future<void> down(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 6));
    await visualTearDown();
    BigSubscribersApi.reset();
  }

  group('«إرسال عام» تلغرام بالتحديد', () {
    Future<_Srv> openSheet(WidgetTester t, {bool telegram = true}) async {
      final inner = await visualSetUp(s1bSasOwner);
      final srv = _Srv(inner, telegram: telegram);
      ApiClient.dio.httpClientAdapter = srv;
      await pumpVisual(t, _p390, home: (_) => Scaffold(
            body: Builder(
              builder: (ctx) => Center(
                child: ElevatedButton(onPressed: () => showTelegramBroadcastSheet(ctx, adminId: '2683'), child: const Text('افتح')),
              ),
            ),
          ));
      await settle(t, seconds: 1);
      await t.tap(find.text('افتح'));
      await settle(t, seconds: 2);
      return srv;
    }

    testWidgets('اللوحة بإعلان الخادم ⇒ المعاينة بلا نصّ ⇒ التأكيد بالأسماء ⇒ الإرسال بالبصمة والحدود نفسها', (t) async {
      final srv = await openSheet(t);
      expect(find.byKey(const ValueKey('debt-filter-panel')), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('df-age-30')));
      await t.ensureVisible(find.text('50 إلى 100 ألف'));
      await t.tap(find.text('50 إلى 100 ألف'));
      await settle(t, seconds: 2);
      final pv = srv.bodiesOf('/api/telegram/broadcast').where((b) => b['dryRun'] == true).toList();
      expect(pv, isNotEmpty);
      expect(pv.last['debtFilter'], {'minAgeDays': 30, 'minAmount': 50000, 'maxAmount': 100000});
      expect(pv.last.containsKey('message'), isFalse, reason: 'المعاينة بالشرائح وحدها');
      expect(find.textContaining('مربوطاً مديناً يطابقون', findRichText: true), findsOneWidget);
      expect(find.textContaining('1 غير موجودين'), findsOneWidget);
      await t.enterText(find.byType(TextField).first, 'تذكير بتسديد الدين');
      await t.pump();
      await t.ensureVisible(find.byKey(const ValueKey('tg-broadcast-send')));
      await t.tap(find.byKey(const ValueKey('tg-broadcast-send')));
      await settle(t, seconds: 2);
      expect(find.text('تأكيد الإرسال عبر تلغرام'), findsOneWidget);
      expect(find.text('أحمد كامل'), findsWidgets);
      expect(find.textContaining('حظروا البوت'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('tg-confirm-send')));
      await settle(t, seconds: 2);
      final sends = srv.bodiesOf('/api/telegram/broadcast').where((b) => b['dryRun'] != true).toList();
      expect(sends, hasLength(1));
      expect(sends.single['debtFilter'], {'minAgeDays': 30, 'minAmount': 50000, 'maxAmount': 100000});
      expect(sends.single['audienceKey'], 't3'.padRight(32, '0'));
      expect(sends.single['audienceCount'], 3);
      expect(sends.single['message'], 'تذكير بتسديد الدين');
      await down(t);
    });

    testWidgets('خادمٌ لا يعلن تلغرام ⇒ بلا لوحة، والإرسال العامّ كما كان', (t) async {
      final srv = await openSheet(t, telegram: false);
      expect(find.byKey(const ValueKey('debt-filter-panel')), findsNothing);
      expect(find.text('فحص مسبق'), findsOneWidget);
      expect(srv.bodiesOf('/api/telegram/broadcast'), isEmpty);
      await down(t);
    });
  });

  group('الحساب الكبير بالتحديد', () {
    testWidgets('«نحسب…» من الخادم ثمّ النتيجة، و«الكلّ» يرسل بالبصمة بلا أسماء (الخادم يجهّزه في الخلفيّة)', (t) async {
      final inner = await visualSetUp(s1bSasOwner);
      final srv = _Srv(inner, big: true, pendingPolls: 1);
      ApiClient.dio.httpClientAdapter = srv;
      BigSubscribersApi.reset();
      SubscribersApi.clearAllCaches();
      await pumpVisual(t, _p390, home: (_) => const BroadcastScreen());
      await settle(t, seconds: 2);
      await t.tap(find.text('المدينون'));
      await settle(t);
      expect(find.byKey(const ValueKey('debt-filter-panel')), findsOneWidget, reason: 'الكبير بإعلان bigPreview');
      await t.ensureVisible(find.byKey(const ValueKey('df-age-30')));
      await t.tap(find.byKey(const ValueKey('df-age-30')));
      await settle(t, seconds: 1);
      expect(find.byKey(const ValueKey('debt-filter-pending')), findsOneWidget);
      expect(find.textContaining('نحسب من يطابق في الخلفيّة'), findsOneWidget);
      await t.pump(const Duration(seconds: 5)); // يعيد السؤال بعد ٤ ثوانٍ
      await settle(t, seconds: 1);
      expect(find.byKey(const ValueKey('debt-filter-pending')), findsNothing);
      expect(find.textContaining('مديناً يطابقون', findRichText: true), findsOneWidget);
      // «الكلّ»
      await t.ensureVisible(find.textContaining('الكلّ ('));
      await t.tap(find.textContaining('الكلّ ('));
      await settle(t);
      await t.tap(find.byKey(const ValueKey('broadcast-send')));
      await settle(t, seconds: 2);
      expect(find.textContaining('حسابٌ كبير: يُجهَّز الإرسال في الخلفيّة'), findsOneWidget);
      await t.tap(find.text('إرسال إلى 3'));
      await settle(t, seconds: 2);
      final sends = srv.bodiesOf('/api/whatsapp/broadcast').where((b) => b['dryRun'] != true).toList();
      expect(sends, hasLength(1));
      expect(sends.single['debtFilter'], {'minAgeDays': 30});
      expect(sends.single['audienceKey'], 'b3'.padRight(32, '0'));
      expect(sends.single.containsKey('targetUsernames'), isFalse, reason: 'الكلّ: الخادم يجمع ويقاطع مع ما رآه المدير');
      await down(t);
    });
  });
}
