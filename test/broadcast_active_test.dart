import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
  _Server(this.inner, this.rows, {this.appEnabled = true});
  final HttpClientAdapter inner;
  final List<Map<String, Object?>> rows;

  /// قناة «التطبيق» مفعّلة للحساب (GET /api/whatsapp/broadcast/channels — ١٨ نوفمبر)
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
      return _json(200, {'success': true, 'message': 'تمت إضافة رسائل', 'summary': {'queued': 2, 'excludedHighRisk': 0}});
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
        // أعدادٌ لا تتكرّر بالشاشة (اختبار التخطيط يبحث عن «3» و«24»…)
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

/// ١١٠ مشتركاً كلقطة المالك: ٨٦ فعّالاً (٣ منهم قرب الانتهاء)، ٢٤ منتهياً، و٤٨ مديناً.
List<Map<String, Object?>> _ownerLikeRows() {
  String fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} ${d.hour.toString().padLeft(2, '0')}:00:00';
  final b = DateTime.now().toUtc().add(const Duration(hours: 3));
  final wall = DateTime(b.year, b.month, b.day, b.hour);
  return [
    for (var i = 0; i < 110; i++)
      {
        ..._row('u$i@x',
            expiration: fmt(i < 3
                ? wall.add(const Duration(hours: 30))
                : i < 86
                    ? wall.add(const Duration(days: 20))
                    : wall.subtract(const Duration(days: 10))),
            phone: '0770${(1000000 + i).toString()}'),
        if (i % 2 == 0 && i < 96) 'notes': '-5000',
      },
  ];
}


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

    // قناة «التطبيق» (١٨ نوفمبر): الحساب المفعَّل يرى البلاطة ويُرسَل اختياره (channels)؛ غير المفعَّل كما كان حرفاً (لا بلاطة ولا channels)
    for (final appOn in [true, false]) {
      testWidgets('قناة «التطبيق» ${appOn ? 'مفعّلة: البلاطة بعددها والاختيار يُرسَل' : 'غير مفعّلة: لا بلاطة ولا channels (كما كان)'}', (t) async {
        final inner = await visualSetUp(s1bSasOwner);
        final srv = _Server(inner, [
          _row('far@x', expiration: '2030-01-01 10:00:00'),
          _row('soon@x', expiration: '2030-01-03 10:00:00'),
        ], appEnabled: appOn);
        ApiClient.dio.httpClientAdapter = srv;
        BigSubscribersApi.reset();
        SubscribersApi.clearAllCaches();
        await pumpVisual(t, _p390, home: (_) => const BroadcastScreen());
        await settle(t, seconds: 2);
        expect(find.byKey(const ValueKey('channel-app')), appOn ? findsOneWidget : findsNothing);
        if (appOn) {
          expect(find.descendant(of: find.byKey(const ValueKey('channel-app')), matching: find.text('17')), findsOneWidget,
              reason: 'كم مشتركاً عنده التطبيق');
          await t.ensureVisible(find.byKey(const ValueKey('channel-app')));
          await t.tap(find.byKey(const ValueKey('channel-app')));
          await settle(t);
        }
        expect(find.textContaining(appOn ? 'يوصل بـالتطبيق وحده' : 'تلغرام للي رابطه'), findsOneWidget);
        await t.enterText(find.byType(TextField).last, 'عرضٌ جديد');
        await settle(t);
        await t.tap(find.byKey(const ValueKey('broadcast-send')));
        await settle(t);
        await t.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('إرسال')));
        await settle(t, seconds: 2);
        final send = srv.sends().single;
        if (appOn) {
          expect(send['channels'], ['app']);
        } else {
          expect(send.containsKey('channels'), isFalse, reason: 'الخادم يرى ما كان يراه');
          expect(send.containsKey('forceChannel'), isFalse, reason: '«تلقائي» القديم');
        }
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
        await t.pump(const Duration(seconds: 1));
        await visualTearDown();
        BigSubscribersApi.reset();
      });
    }

    testWidgets('🚨 ٢ ثمّ ٣ (١٦ نوفمبر — «تنطي الاعداد الكبيره ٢ مساحه والصغيره ٣») + أزرار «قناة الإرسال» («صلحها هم»): '
        'لا نصّ مقصوص في الشاشة كلّها على 320–480 × الخطّ 1.0/1.1/1.2، فاتحاً وداكناً', (t) async {
      Finder cardOf(String label) => find.ancestor(of: find.text(label), matching: find.byType(InkWell)).first;
      Rect rectOf(String label) => t.getRect(cardOf(label));
      final shrunk = <String>{}, heights = <String>[], modes = <String>[];
      addTearDown(() {
        debugPrint('ارتفاعات: ${heights.join(' | ')}');
        debugPrint('أزرار القناة: ${modes.join(' | ')}');
        debugPrint('صغُر: ${shrunk.isEmpty ? 'لا شيء' : shrunk.join(' | ')}');
      });
      const filterLabels = ['كل المشتركين', 'الفعّالون', 'المدينون', 'منتهي الصلاحية', 'قرب الانتهاء (3 أيام)'];
      for (final w in [320.0, 340.0, 360.0, 375.0, 390.0, 412.0, 430.0, 480.0]) {
        for (final scale in [1.0, 1.1, 1.2]) {
          for (final dark in [false, true]) {
            final tag = '$w×$scale${dark ? ' داكن' : ''}';
            final inner = await visualSetUp(s1bSasOwner);
            ApiClient.dio.httpClientAdapter = _Server(inner, _ownerLikeRows());
            BigSubscribersApi.reset();
            SubscribersApi.clearAllCaches();
            t.platformDispatcher.textScaleFactorTestValue = scale;
            await pumpVisual(t, VisualDevice('', Size(w, 3200), 3, dark: dark), home: (_) => const BroadcastScreen());
            await settle(t, seconds: 2);
            expect(t.takeException(), isNull, reason: 'فيضان $tag');

            // ① لا نصّ مقصوص في الشاشة كلّها (كان: «واتساب فقط» و«تلغرام فقط» على 320–360)
            final cut = <String>{
              for (final p in t.allRenderObjects.whereType<RenderParagraph>())
                if (p.didExceedMaxLines) p.text.toPlainText(),
            };
            expect(cut, isEmpty, reason: 'نصٌّ مقصوص $tag');

            // ② «لمن ترسل؟»: الكبيران صفٌّ، والصغار الثلاثة صفٌّ تحتهما بارتفاعٍ واحد
            final all = rectOf('كل المشتركين'), act = rectOf('الفعّالون');
            final deb = rectOf('المدينون'), exp = rectOf('منتهي الصلاحية'), soon = rectOf('قرب الانتهاء (3 أيام)');
            expect((all.top - act.top).abs(), lessThan(0.5), reason: 'الكبيران صفٌّ واحد $tag');
            for (final r in [exp, soon]) {
              expect((r.top - deb.top).abs(), lessThan(0.5), reason: 'الصغار صفٌّ واحد $tag');
              expect((r.height - deb.height).abs(), lessThan(0.5), reason: 'الصغار بارتفاعٍ واحد $tag');
            }
            expect(deb.top, greaterThan(all.bottom), reason: 'الصغار تحت الكبيرين $tag');
            final numTop = t.getRect(find.text('48')).top;
            for (final n in ['24', '3']) {
              expect((t.getRect(find.text(n)).top - numTop).abs(), lessThan(0.5),
                  reason: 'أرقام الصغار على سطرٍ واحد وإن التفّ اسم أحدها $tag');
            }
            expect(all.width, greaterThan(deb.width * 1.3), reason: 'الكبير نصفٌ والصغير ثلث $tag');
            expect(find.text('110'), findsOneWidget, reason: tag);
            expect(find.text('86'), findsOneWidget, reason: tag);

            // ③ «قناة الإرسال» (١٨ نوفمبر — «حسن تصميمها»): البلاطات الأربع (تلقائي · واتساب · تلغرام · التطبيق) صفٌّ واحد بارتفاعٍ واحد
            final tiles = [for (final c in const ['auto', 'whatsapp', 'telegram', 'app']) t.getRect(find.byKey(ValueKey('channel-$c')))];
            for (final r in tiles.skip(1)) {
              expect((r.top - tiles.first.top).abs(), lessThan(0.5), reason: 'البلاطات صفٌّ واحد $tag');
              expect((r.height - tiles.first.height).abs(), lessThan(0.5), reason: 'البلاطات بارتفاعٍ واحد $tag');
            }
            if (!dark) modes.add('$w×$scale بلاطة ${tiles.first.height.toStringAsFixed(0)}');

            // ④ ما يصغر (FittedBox) لا يصغر كثيراً: البطاقات ≤ 15٪، أسماء القناة ≤ 3٪
            for (final label in [...filterLabels, '110', '86', '48', '24', '3']) {
              final p = t.renderObject<RenderParagraph>(find.text(label));
              final box = find.ancestor(of: find.text(label), matching: find.byType(FittedBox));
              if (box.evaluate().isEmpty) continue;
              final k = t.getSize(box.first).width / p.size.width;
              const floor = 0.85;
              expect(k, greaterThanOrEqualTo(floor), reason: '«$label» صغُر إلى ${(k * 100).round()}٪ $tag');
              if (k < 0.999) shrunk.add('${w.toInt()}×$scale «$label» ${(k * 100).round()}٪');
            }
            if (!dark) heights.add('$w×$scale: كبير ${all.height.toStringAsFixed(0)} · صغير ${deb.height.toStringAsFixed(0)}');

            await t.pumpWidget(const SizedBox());
            await t.pump(const Duration(seconds: 1));
            t.platformDispatcher.clearTextScaleFactorTestValue();
            await visualTearDown();
            BigSubscribersApi.reset();
          }
        }
      }
    });
  });
}
