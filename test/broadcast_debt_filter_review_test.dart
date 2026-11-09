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

/// «تحديد المدينين» في التبليغات — مراجعة 3.0.18+179 الثانية:
///  ١. اللوحة تُبنى من جديد (تبديل الفئة والعودة) والفلتر باقٍ عند الشاشة: الحقول تُملأ منه — ما يُرى هو ما يُطبَّق (كانت «من»/«إلى»
///     تظهر فارغةً والعدّ والإرسال بمبلغها)، و«مدّة أخرى» يبدأ بالعمر المطبَّق.
///  ٢. «نحسب…» للحساب الكبير (كلّ ٤ ثوانٍ) محدود: ~٣ دقائق ثمّ السبب و«إعادة»؛ ويقف حين تختفي اللوحة أو يذهب التطبيق للخلفيّة.
/// الخادم وهميّ: لا رسالة تُرسَل، والطلبات تُسجَّل.
class _Srv implements HttpClientAdapter {
  _Srv(this.inner, {this.big = false, this.alwaysPending = false});
  final HttpClientAdapter inner;
  final bool big;
  final bool alwaysPending;
  final requests = <RequestOptions>[];

  List<Map<String, dynamic>> get previews => [
        for (final r in requests)
          if (r.method == 'POST' && r.path == '/api/whatsapp/broadcast' && (r.data as Map)['dryRun'] == true)
            Map<String, dynamic>.from(r.data as Map),
      ];

  static ResponseBody _json(int status, Object body) => ResponseBody.fromString(jsonEncode(body), status, headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      });

  static const rows = [
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
          'version': 3, 'telegram': true, 'bigPreview': 'async', 'amount': true, 'age': true, 'ageMeaning': 'oldest_unpaid',
          'presets': [7, 15, 30, 60, 90], 'maxAgeDays': 3650, 'maxAmount': 10000000000, 'previewRequired': true,
        },
      });
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
        if (alwaysPending) {
          return _json(202, {'success': true, 'dryRun': true, 'pending': true, 'total': 89177,
            'message': 'حسابك كبير (89,177 مشترك): نحسب من يطابق في الخلفيّة — تظهر النتيجة خلال دقيقة تقريباً'});
        }
        return _json(200, {
          'success': true, 'dryRun': true, 'mode': 'debtors', 'count': 2, 'audience': 2, 'excludedHighRisk': 0, 'deduped': 0,
          'rows': rows, 'truncated': false, 'audienceKey': 'r2'.padRight(32, '0'), 'missing': 0,
          'debtFilter': {'summary': 'x', 'considered': 9, 'kept': 2, 'amountOut': 1, 'ageOut': 0, 'unknownAge': 0, 'legacy': 0},
        });
      }
      return _json(200, {'success': true, 'message': 'تمت إضافة رسائل', 'summary': {'queued': 2, 'excludedHighRisk': 0}});
    }
    if (o.method == 'GET' && p.startsWith('/api/whatsapp/send-scope/')) {
      return _json(200, {'success': true, 'sendToAll': true, 'subManagers': const []});
    }
    return inner.fetch(o, requestStream, cancelFuture);
  }

  @override
  void close({bool force = false}) {}
}

const _p390 = VisualDevice('', Size(390, 1700), 3);

void main() {
  setUpAll(visualSetUpAll);

  Future<_Srv> up(WidgetTester t, {bool big = false, bool alwaysPending = false}) async {
    final inner = await visualSetUp(s1bSasOwner);
    final srv = _Srv(inner, big: big, alwaysPending: alwaysPending);
    ApiClient.dio.httpClientAdapter = srv;
    BigSubscribersApi.reset();
    SubscribersApi.clearAllCaches();
    await pumpVisual(t, _p390, home: (_) => const BroadcastScreen());
    await settle(t, seconds: 2);
    return srv;
  }

  Future<void> down(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 6));
    await visualTearDown();
    BigSubscribersApi.reset();
  }

  String textOf(WidgetTester t, String key) => t.widget<TextField>(find.byKey(ValueKey(key))).controller!.text;

  Future<void> tapText(WidgetTester t, String label) async {
    await t.ensureVisible(find.text(label));
    await t.tap(find.text(label));
  }

  group('١ — ما يُرى هو ما يُطبَّق', () {
    testWidgets('مبلغان وعمرٌ مكتوب ⇒ «كل المشتركين» ثمّ «المدينون»: الحقول بقيمها والمعاينة بها؛ وتعديل حدٍّ يُبقي الآخر الظاهر', (t) async {
      final srv = await up(t);
      await tapText(t, 'المدينون');
      await settle(t);
      await t.enterText(find.byKey(const ValueKey('df-min')), '30000');
      await t.enterText(find.byKey(const ValueKey('df-max')), '100000');
      await tapText(t, 'مدّة أخرى');
      await settle(t, seconds: 1);
      await t.enterText(find.byKey(const ValueKey('df-age-custom')), '45');
      await settle(t, seconds: 2);
      const applied = {'minAgeDays': 45, 'minAmount': 30000, 'maxAmount': 100000};
      expect(srv.previews.last['debtFilter'], applied);
      // اللوحة تختفي وتعود (حالٌ جديدة لها)
      await tapText(t, 'كل المشتركين');
      await settle(t);
      expect(find.byKey(const ValueKey('debt-filter-panel')), findsNothing);
      await tapText(t, 'المدينون');
      await settle(t, seconds: 2);
      expect(textOf(t, 'df-min'), '30,000', reason: 'الحدّ الأدنى المطبَّق ظاهر');
      expect(textOf(t, 'df-max'), '100,000');
      expect(find.byKey(const ValueKey('df-age-custom')), findsOneWidget, reason: 'العمر غير الجاهز في صندوقه');
      expect(textOf(t, 'df-age-custom'), '45');
      expect(srv.previews.last['debtFilter'], applied, reason: 'المعاينة بما يظهر');
      // تعديل «إلى» وحده: «من» الظاهر هو المطبَّق معه
      await t.enterText(find.byKey(const ValueKey('df-max')), '90000');
      await settle(t, seconds: 2);
      expect(srv.previews.last['debtFilter'], {'minAgeDays': 45, 'minAmount': 30000, 'maxAmount': 90000});
      expect(textOf(t, 'df-min'), '30,000');
      expect(t.takeException(), isNull);
      await down(t);
    });

    testWidgets('«مدّة أخرى» يبدأ بالعمر المطبَّق لا بما كُتب قبل الشريحة؛ والعودة بعمرٍ جاهز: بلا صندوق والحقلان كالفلتر', (t) async {
      final srv = await up(t);
      await tapText(t, 'المدينون');
      await settle(t);
      await tapText(t, 'مدّة أخرى');
      await settle(t, seconds: 1);
      await t.enterText(find.byKey(const ValueKey('df-age-custom')), '45');
      await settle(t, seconds: 1);
      await t.ensureVisible(find.byKey(const ValueKey('df-age-30')));
      await t.tap(find.byKey(const ValueKey('df-age-30')));
      await settle(t, seconds: 2);
      expect(srv.previews.last['debtFilter'], {'minAgeDays': 30});
      await tapText(t, 'مدّة أخرى');
      await settle(t, seconds: 1);
      expect(textOf(t, 'df-age-custom'), '30', reason: 'الصندوق بالعمر المطبَّق (30) لا بـ45 المكتوبة قبل الشريحة');
      // العودة بعد تبديل الفئة: 30 من الشرائح ⇒ لا صندوق، والحقلان فارغان كالفلتر
      await tapText(t, 'كل المشتركين');
      await settle(t);
      await tapText(t, 'المدينون');
      await settle(t, seconds: 2);
      expect(find.byKey(const ValueKey('df-age-custom')), findsNothing);
      expect(textOf(t, 'df-min'), '');
      expect(textOf(t, 'df-max'), '');
      expect(srv.previews.last['debtFilter'], {'minAgeDays': 30});
      await down(t);
    });
  });

  group('٢ — «نحسب…» للحساب الكبير', () {
    Future<_Srv> pending(WidgetTester t) async {
      final srv = await up(t, big: true, alwaysPending: true);
      await tapText(t, 'المدينون');
      await settle(t);
      await t.ensureVisible(find.byKey(const ValueKey('df-age-30')));
      await t.tap(find.byKey(const ValueKey('df-age-30')));
      await settle(t, seconds: 1);
      expect(find.byKey(const ValueKey('debt-filter-pending')), findsOneWidget);
      return srv;
    }

    testWidgets('محدود: ~٣ دقائق (٤٥ إعادة كانتظار الإرسال) ثمّ السبب و«إعادة» — ولا سؤال بعدها حتى يُطلب', (t) async {
      final srv = await pending(t);
      for (var i = 0; i < 50; i++) {
        await t.pump(const Duration(seconds: 4));
        await t.pump(const Duration(milliseconds: 50));
      }
      expect(srv.previews, hasLength(46), reason: 'السؤال الأوّل + ٤٥ إعادة');
      expect(find.text('ما زالت المعاينة تُحسب — أعد المحاولة بعد قليل'), findsOneWidget);
      expect(find.byKey(const ValueKey('debt-filter-pending')), findsNothing);
      await t.pump(const Duration(minutes: 2));
      expect(srv.previews, hasLength(46), reason: 'وقف — لا سؤال إلى ما لا نهاية');
      // «إعادة» يبدأ من جديد
      await tapText(t, 'إعادة');
      await settle(t, seconds: 1);
      expect(srv.previews, hasLength(47));
      expect(find.byKey(const ValueKey('debt-filter-pending')), findsOneWidget);
      expect(find.text('ما زالت المعاينة تُحسب — أعد المحاولة بعد قليل'), findsNothing);
      await down(t);
    });

    testWidgets('اللوحة اختفت (فئةٌ أخرى) ⇒ يقف؛ والعودة تسأل من جديد', (t) async {
      final srv = await pending(t);
      await t.pump(const Duration(seconds: 9));
      final before = srv.previews.length;
      expect(before, greaterThan(1));
      await tapText(t, 'كل المشتركين');
      await settle(t);
      await t.pump(const Duration(seconds: 40));
      expect(srv.previews, hasLength(before), reason: 'لا سؤال واللوحة مخفيّة');
      await tapText(t, 'المدينون');
      await settle(t, seconds: 1);
      expect(srv.previews, hasLength(before + 1));
      expect(find.byKey(const ValueKey('debt-filter-pending')), findsOneWidget);
      await down(t);
    });

    testWidgets('التطبيق في الخلفيّة ⇒ يقف؛ والرجوع يسأل من جديد', (t) async {
      addTearDown(() => t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed));
      final srv = await pending(t);
      await t.pump(const Duration(seconds: 5));
      final before = srv.previews.length;
      for (final s in [AppLifecycleState.inactive, AppLifecycleState.hidden, AppLifecycleState.paused]) {
        t.binding.handleAppLifecycleStateChanged(s);
      }
      await t.pump(const Duration(seconds: 40));
      expect(srv.previews, hasLength(before), reason: 'لا سؤال والتطبيق في الخلفيّة');
      for (final s in [AppLifecycleState.hidden, AppLifecycleState.inactive, AppLifecycleState.resumed]) {
        t.binding.handleAppLifecycleStateChanged(s);
      }
      await settle(t, seconds: 1);
      expect(srv.previews, hasLength(before + 1), reason: 'الرجوع يسأل من جديد');
      expect(find.byKey(const ValueKey('debt-filter-pending')), findsOneWidget);
      await down(t);
    });
  });
}
